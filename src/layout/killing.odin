// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package layout

import "../editor"
import "../editor_session"
import "../view"

/* registry_kill_buffer coordinates pane fallbacks before releasing one session graph. */
registry_kill_buffer :: proc(
	registry: ^Registry,
	session: ^editor_session.Session,
	entry: editor_session.Entry_Handle,
	authority := editor_session.Close_Authority.Preserve_Modified,
	factory_fallback: editor_session.Entry_Handle = {},
) -> (result: Kill_Result, ok: bool, failure: Failure_Context) {
	return registry_kill_buffer_checked(
		registry,
		session,
		entry,
		authority,
		factory_fallback,
		{},
	)
}

/* registry_kill_terminal_buffer closes one exact externally disposed terminal graph. */
registry_kill_terminal_buffer :: proc(
	registry: ^Registry,
	session: ^editor_session.Session,
	entry: editor_session.Entry_Handle,
	terminal: editor_session.Terminal_Session_Ref,
	factory_fallback: editor_session.Entry_Handle = {},
) -> (result: Kill_Result, ok: bool, failure: Failure_Context) {
	if !editor_session.terminal_session_ref_is_valid(terminal) {
		return {}, false, registry_failure(registry, .Kill_Buffer, .Invalid_Buffer_State)
	}
	return registry_kill_buffer_checked(
		registry,
		session,
		entry,
		.Discard_Modified,
		factory_fallback,
		terminal,
	)
}

@(private)
registry_kill_buffer_checked :: proc(
	registry: ^Registry,
	session: ^editor_session.Session,
	entry: editor_session.Entry_Handle,
	authority: editor_session.Close_Authority,
	factory_fallback: editor_session.Entry_Handle,
	coordinated_terminal: editor_session.Terminal_Session_Ref,
) -> (result: Kill_Result, ok: bool, failure: Failure_Context) {
	data := registry_data(registry)
	if data == nil || data.state != .Ready {
		return {}, false, registry_failure(registry, .Kill_Buffer, .Invalid_Registry)
	}
	assessment: editor_session.Closure_Result
	assessed: bool
	assess_failure: editor_session.Failure_Context
	if editor_session.terminal_session_ref_is_valid(coordinated_terminal) {
		assessment, assessed, assess_failure = editor_session.session_assess_terminal_buffer_close(
			session,
			entry,
			coordinated_terminal,
		)
	} else {
		assessment, assessed, assess_failure = editor_session.session_assess_buffer_close(session, entry)
	}
	if !assessed {
		return {}, false, layout_session_failure(data, .Kill_Buffer, assess_failure)
	}
	if assessment.outcome == .Discard_Required && authority != .Discard_Modified {
		return Kill_Result {
			outcome = .Discard_Required,
			layout = current_layout_handle(data),
			active_pane = pane_handle(data, data.active),
			closure = assessment,
		}, true, {}
	}
	if data.generation == Layout_Generation(max(u64)) {
		return {}, false, data_failure(data, .Kill_Buffer, .Generation_Limit)
	}
	if !prepared_state_fits(data) {
		return {}, false, prepared_failure(data, .Kill_Buffer)
	}
	target_access, target_ok, target_failure := editor_session.session_entry_access(session, entry)
	if !target_ok {
		return {}, false, layout_session_failure(data, .Kill_Buffer, target_failure)
	}
	target, target_borrowed, target_borrow_failure := editor_session.entry_access_borrow(target_access)
	if !target_borrowed {
		return {}, false, layout_session_failure(data, .Kill_Buffer, target_borrow_failure)
	}
	if target.view_registry != data.view_registry || assessment.graph.buffer_id == editor.Buffer_ID(0) {
		return {}, false, data_failure(data, .Kill_Buffer, .Invalid_Buffer_State)
	}
	choices, choices_error := make([]Kill_Choice, MAX_LIVE_PANES, data.allocator)
	if choices_error != nil {
		return {}, false, prepared_failure(data, .Kill_Buffer)
	}
	defer delete(choices, data.allocator)
	choice_count: int
	removals, removals_error := make([]Kill_Removal, MAX_LIVE_PANES, data.allocator)
	if removals_error != nil {
		return {}, false, prepared_failure(data, .Kill_Buffer)
	}
	defer delete(removals, data.allocator)
	removal_count: int
	dedicated_affected: u16
	for &slot in data.nodes {
		if slot.live && slot.kind == .Pane && slot.buffer_id == assessment.graph.buffer_id &&
		   slot.dedication != .None {
			dedicated_affected += 1
		}
	}
	final_dedicated_ref := Node_Ref{}
	if dedicated_affected == data.pane_count {
		final_dedicated_ref = data.active
	}
	rollback_choices := false
	defer {
		if rollback_choices {
			kill_choices_rollback(data, choices[:choice_count], target.primary_view)
		}
	}
	for &slot, slot_index in data.nodes {
		if !slot.live || slot.kind != .Pane || slot.buffer_id != assessment.graph.buffer_id {
			continue
		}
		if data.next_history_sequence > max(u64) - u64(choice_count * 3 + 3) {
			rollback_choices = true
			return {}, false, data_failure(data, .Kill_Buffer, .Generation_Limit)
		}
		outgoing_snapshot, outgoing_ok, outgoing_failure := view.snapshot(
			data.view_registry,
			slot.view,
		)
		if !outgoing_ok {
			rollback_choices = true
			return {}, false, layout_view_failure(data, .Kill_Buffer, outgoing_failure)
		}
		outgoing_transient, transient_ok, transient_failure := view.transient_state(
			data.view_registry,
			slot.view,
		)
		if !transient_ok {
			rollback_choices = true
			return {}, false, layout_view_failure(data, .Kill_Buffer, transient_failure)
		}
		if outgoing_transient.active_preparation || outgoing_transient.search ||
		   outgoing_transient.query_replacement {
			rollback_choices = true
			return {}, false, data_failure(data, .Kill_Buffer, .Busy)
		}
		ref := Node_Ref{slot = u16(slot_index), generation = slot.generation}
		if slot.dedication != .None && ref != final_dedicated_ref {
			if outgoing_snapshot.presentation_ownership == .Additional {
				close_ready, close_failure := view.validate_close(data.view_registry, slot.view)
				if !close_ready {
					rollback_choices = true
					return {}, false, layout_view_failure(data, .Kill_Buffer, close_failure)
				}
			}
			removals[removal_count] = Kill_Removal {
				ref = ref,
				handle = slot.view,
				snapshot = outgoing_snapshot,
				active = ref == data.active,
			}
			removal_count += 1
			continue
		}
		fallback, fallback_ok := kill_fallback_select(
			data,
			&slot,
			session,
			entry,
			assessment.graph.buffer_id,
			factory_fallback,
		)
		if !fallback_ok {
			rollback_choices = true
			return {}, false, data_failure(data, .Kill_Buffer, .No_Fallback)
		}
		additional_required := kill_fallback_is_displayed(
			data,
			assessment.graph.buffer_id,
			fallback.buffer_id,
			choices[:choice_count],
		)
		incoming_view := fallback.primary_view
		created := false
		rebound := false
		if additional_required {
			if outgoing_snapshot.presentation_ownership == .Additional {
				rebound_ok, rebound_failure := view.rebind_additional(
					data.view_registry,
					slot.view,
					fallback.primary_view,
				)
				if !rebound_ok {
					rollback_choices = true
					return {}, false, layout_view_failure(data, .Kill_Buffer, rebound_failure)
				}
				incoming_view = slot.view
				rebound = true
			} else {
				incoming_view, outgoing_ok, outgoing_failure = view.clone_additional(
					data.view_registry,
					fallback.primary_view,
				)
				if !outgoing_ok {
					rollback_choices = true
					return {}, false, layout_view_failure(data, .Kill_Buffer, outgoing_failure)
				}
				created = true
			}
		}
		incoming_snapshot, incoming_ok, incoming_failure := view.snapshot(
			data.view_registry,
			incoming_view,
		)
		if !incoming_ok {
			rollback_choices = true
			return {}, false, layout_view_failure(data, .Kill_Buffer, incoming_failure)
		}
		incoming_state := pane_buffer_state_from_view(fallback.entry, incoming_snapshot)
		if fallback.has_state {
			incoming_state, incoming_ok = pane_buffer_state_normalize(
				fallback.state,
				fallback.entry,
				fallback.buffer,
			)
			if !incoming_ok {
				rollback_choices = true
				return {}, false, data_failure(data, .Kill_Buffer, .Invalid_Buffer_State)
			}
		}
		outgoing_state := pane_buffer_state_from_view(slot.entry, outgoing_snapshot)
		if ref == data.active {
			outgoing_state.stored_point = outgoing_snapshot.effective_point_position
		}
		choices[choice_count] = Kill_Choice {
			ref = ref,
			outgoing_view = slot.view,
			outgoing_snapshot = outgoing_snapshot,
			outgoing_state = outgoing_state,
			incoming_entry = fallback.entry,
			incoming_buffer_id = fallback.buffer_id,
			incoming_view = incoming_view,
			incoming_snapshot = incoming_snapshot,
			incoming_state = incoming_state,
			created = created,
			rebound = rebound,
			active = ref == data.active,
			clear_dedication = slot.dedication != .None,
		}
		choice_count += 1
	}
	proposed, prepared := prepared_state_copy(data, .Kill_Buffer)
	if prepared.code != .None {
		rollback_choices = true
		return {}, false, prepared
	}
	defer prepared_state_release(proposed)
	proposed.generation = Layout_Generation(u64(data.generation) + 1)
	for choice in choices[:choice_count] {
		slot := resolve_node(proposed, choice.ref)
		assert(slot != nil && slot.kind == .Pane)
		pane_history_touch(proposed, slot, choice.outgoing_state)
		slot.entry = choice.incoming_entry
		slot.buffer_id = choice.incoming_buffer_id
		slot.view = choice.incoming_view
		if choice.clear_dedication {
			slot.dedication = .None
		}
		pane_history_touch(proposed, slot, choice.incoming_state)
		buffer_list_touch(proposed, choice.incoming_entry, choice.incoming_buffer_id)
	}
	for removal in removals[:removal_count] {
		if !remove_pane_from_state(proposed, removal.ref) {
			rollback_choices = true
			return {}, false, data_failure(data, .Kill_Buffer, .Invalid_Topology)
		}
	}
	for &slot in proposed.nodes {
		if slot.live && slot.kind == .Pane {
			pane_history_remove(&slot, entry, assessment.graph.buffer_id)
		}
	}
	buffer_list_remove(proposed, entry, assessment.graph.buffer_id)
	if removal_count > 0 {
		materialized, materialize_failure := geometry_materialize_data(
			proposed,
			proposed.geometry_request,
			.External_Shrink,
			.Kill_Buffer,
			false,
		)
		if !materialized {
			rollback_choices = true
			return {}, false, materialize_failure
		}
	}
	if !validate_layout_state(proposed) {
		rollback_choices = true
		return {}, false, data_failure(data, .Kill_Buffer, .Invalid_Topology)
	}
	for choice in choices[:choice_count] {
		restored, restore_failure := view.restore_presentation(
			data.view_registry,
			choice.incoming_view,
			choice.incoming_state.stored_point.byte_offset,
			choice.incoming_state.viewport_start.byte_offset,
			choice.incoming_state.horizontal_display_column,
			choice.incoming_state.desired_display_column,
		)
		if !restored {
			rollback_choices = true
			return {}, false, layout_view_failure(data, .Kill_Buffer, restore_failure)
		}
	}
	active_choice_index := -1
	for choice, index in choices[:choice_count] {
		if !choice.active {
			continue
		}
		active_choice_index = index
		if choice.rebound && choice.incoming_view == choice.outgoing_view {
			restored, restore_failure := view.restore_stored_point(
				data.view_registry,
				choice.incoming_view,
			)
			if !restored {
				rollback_choices = true
				return {}, false, layout_view_failure(data, .Kill_Buffer, restore_failure)
			}
		} else {
			transferred, transfer_failure := view.transfer_focus(
				data.view_registry,
				choice.outgoing_view,
				choice.incoming_view,
			)
			if !transferred {
				rollback_choices = true
				return {}, false, layout_view_failure(data, .Kill_Buffer, transfer_failure)
			}
		}
		break
	}
	active_removal_index := -1
	if active_choice_index < 0 {
		for removal, index in removals[:removal_count] {
			if !removal.active {
				continue
			}
			active_removal_index = index
			incoming := resolve_node(proposed, proposed.active)
			assert(incoming != nil && incoming.kind == .Pane)
			transferred, transfer_failure := view.transfer_focus(
				data.view_registry,
				removal.handle,
				incoming.view,
			)
			if !transferred {
				rollback_choices = true
				return {}, false, layout_view_failure(data, .Kill_Buffer, transfer_failure)
			}
			break
		}
	}
	detached: editor_session.Detached_Entry
	detachment, detached_ok, detach_failure := editor_session.session_entry_detach(
		session,
		entry,
		&detached,
	)
	if !detached_ok {
		if active_choice_index >= 0 {
			choice := choices[active_choice_index]
			if !choice.rebound || choice.incoming_view != choice.outgoing_view {
				rolled_back, _ := view.transfer_focus(
					data.view_registry,
					choice.incoming_view,
					choice.outgoing_view,
				)
				assert(rolled_back)
			}
		}
		if active_removal_index >= 0 {
			removal := removals[active_removal_index]
			incoming := resolve_node(proposed, proposed.active)
			assert(incoming != nil && incoming.kind == .Pane)
			rolled_back, _ := view.transfer_focus(
				data.view_registry,
				incoming.view,
				removal.handle,
			)
			assert(rolled_back)
		}
		rollback_choices = true
		return {}, false, layout_session_failure(data, .Kill_Buffer, detach_failure)
	}
	data^ = proposed^
	rollback_choices = false
	for choice in choices[:choice_count] {
		if choice.outgoing_snapshot.presentation_ownership == .Additional && !choice.rebound {
			removed := choice.outgoing_view
			closed, _ := view.close(data.view_registry, &removed)
			assert(closed)
		}
	}
	for removal in removals[:removal_count] {
		if removal.snapshot.presentation_ownership == .Additional {
			removed := removal.handle
			closed, _ := view.close(data.view_registry, &removed)
			assert(closed)
		}
	}
	active_slot := resolve_node(data, data.active)
	assert(active_slot != nil && active_slot.kind == .Pane)
	_, activated, activation_failure := editor_session.session_activate(session, active_slot.entry)
	if !activated {
		return {}, false, layout_session_failure(data, .Kill_Buffer, activation_failure)
	}
	cleanup, cleaned, cleanup_failure := editor_session.detached_entry_cleanup(&detached)
	if !cleaned {
		return {}, false, layout_session_failure(data, .Kill_Buffer, cleanup_failure)
	}
	released, release_failure := editor_session.detached_entry_release(&detached)
	if !released {
		return {}, false, layout_session_failure(data, .Kill_Buffer, release_failure)
	}
	usage, usage_ok, usage_failure := editor_session.session_usage(
		session,
		entry.registry.session,
	)
	if !usage_ok {
		return {}, false, layout_session_failure(data, .Kill_Buffer, usage_failure)
	}
	assessment.outcome = .Closed
	assessment.was_visible = detachment.was_visible
	assessment.successor = detachment.successor
	assessment.last_buffer = false
	assessment.cleanup = cleanup
	assessment.usage = usage
	result = Kill_Result {
		outcome = .Killed,
		layout = current_layout_handle(data),
		active_pane = pane_handle(data, data.active),
		active_entry = active_slot.entry,
		closure = assessment,
		replacements = u16(choice_count),
	}
	registry_notify_publication(registry)
	return result, true, {}
}

@(private)
Kill_Fallback :: struct {
	entry:        editor_session.Entry_Handle,
	buffer_id:    editor.Buffer_ID,
	buffer:       ^editor.Buffer,
	primary_view: view.View_Handle,
	state:        Pane_Buffer_State,
	has_state:    bool,
}

@(private)
Kill_Choice :: struct {
	ref:                Node_Ref,
	outgoing_view:      view.View_Handle,
	outgoing_snapshot:  view.Snapshot,
	outgoing_state:     Pane_Buffer_State,
	incoming_entry:     editor_session.Entry_Handle,
	incoming_buffer_id: editor.Buffer_ID,
	incoming_view:      view.View_Handle,
	incoming_snapshot:  view.Snapshot,
	incoming_state:     Pane_Buffer_State,
	created:            bool,
	rebound:            bool,
	active:             bool,
	clear_dedication:   bool,
}

@(private)
Kill_Removal :: struct {
	ref:      Node_Ref,
	handle:   view.View_Handle,
	snapshot: view.Snapshot,
	active:   bool,
}

@(private)
kill_fallback_select :: proc(
	data: ^Registry_Data,
	slot: ^Node_Slot,
	session: ^editor_session.Session,
	killed_entry: editor_session.Entry_Handle,
	killed_buffer: editor.Buffer_ID,
	factory_fallback: editor_session.Entry_Handle,
) -> (Kill_Fallback, bool) {
	for candidate in slot.history[:slot.history_count] {
		if candidate.state.entry == killed_entry || candidate.state.buffer_id == killed_buffer {
			continue
		}
		fallback, ok := kill_fallback_resolve(
			data,
			session,
			candidate.state.entry,
			candidate.state.buffer_id,
		)
		if ok {
			fallback.state = candidate.state
			fallback.has_state = true
			return fallback, true
		}
	}
	for candidate in data.buffer_list[:data.buffer_list_count] {
		if candidate.entry == killed_entry || candidate.buffer_id == killed_buffer {
			continue
		}
		fallback, ok := kill_fallback_resolve(
			data,
			session,
			candidate.entry,
			candidate.buffer_id,
		)
		if ok {
			return fallback, true
		}
	}
	if editor_session.entry_handle_is_valid(factory_fallback) && factory_fallback != killed_entry {
		fallback, ok := kill_fallback_resolve_entry(data, session, factory_fallback)
		if ok && fallback.buffer_id != killed_buffer {
			return fallback, true
		}
	}
	return {}, false
}

@(private)
kill_fallback_resolve_entry :: proc(
	data: ^Registry_Data,
	session: ^editor_session.Session,
	entry: editor_session.Entry_Handle,
) -> (Kill_Fallback, bool) {
	access, accessed, _ := editor_session.session_entry_access(session, entry)
	if !accessed {
		return {}, false
	}
	borrow, borrowed, _ := editor_session.entry_access_borrow(access)
	if !borrowed || borrow.view_registry != data.view_registry {
		return {}, false
	}
	stats, stats_ok, _ := editor.buffer_stats(borrow.buffer)
	if !stats_ok {
		return {}, false
	}
	return Kill_Fallback {
		entry = entry,
		buffer_id = stats.buffer_id,
		buffer = borrow.buffer,
		primary_view = borrow.primary_view,
	}, true
}

@(private)
kill_fallback_resolve :: proc(
	data: ^Registry_Data,
	session: ^editor_session.Session,
	entry: editor_session.Entry_Handle,
	buffer_id: editor.Buffer_ID,
) -> (Kill_Fallback, bool) {
	access, accessed, _ := editor_session.session_entry_access(session, entry)
	if !accessed {
		return {}, false
	}
	borrow, borrowed, _ := editor_session.entry_access_borrow(access)
	if !borrowed || borrow.view_registry != data.view_registry {
		return {}, false
	}
	stats, stats_ok, _ := editor.buffer_stats(borrow.buffer)
	if !stats_ok || stats.buffer_id != buffer_id {
		return {}, false
	}
	return Kill_Fallback {
		entry = entry,
		buffer_id = buffer_id,
		buffer = borrow.buffer,
		primary_view = borrow.primary_view,
	}, true
}

@(private)
kill_fallback_is_displayed :: proc(
	data: ^Registry_Data,
	killed_buffer, fallback_buffer: editor.Buffer_ID,
	choices: []Kill_Choice,
) -> bool {
	for &slot in data.nodes {
		if slot.live && slot.kind == .Pane && slot.buffer_id != killed_buffer &&
		   slot.buffer_id == fallback_buffer {
			return true
		}
	}
	for choice in choices {
		if choice.incoming_buffer_id == fallback_buffer {
			return true
		}
	}
	return false
}

@(private)
kill_choices_rollback :: proc(
	data: ^Registry_Data,
	choices: []Kill_Choice,
	killed_primary: view.View_Handle,
) {
	for index := len(choices) - 1; index >= 0; index -= 1 {
		choice := choices[index]
		if choice.rebound {
			rebound, _ := view.rebind_additional(
				data.view_registry,
				choice.incoming_view,
				killed_primary,
			)
			assert(rebound)
			pane_view_restore_snapshot(
				data.view_registry,
				choice.incoming_view,
				choice.outgoing_snapshot,
			)
			if choice.active {
				point_set, _ := view.set_point(
					data.view_registry,
					choice.incoming_view,
					choice.outgoing_snapshot.effective_point_position,
				)
				assert(point_set)
			}
		} else {
			pane_view_restore_snapshot(
				data.view_registry,
				choice.incoming_view,
				choice.incoming_snapshot,
			)
			if choice.created {
				removed := choice.incoming_view
				closed, _ := view.close(data.view_registry, &removed)
				assert(closed)
			}
		}
	}
}
