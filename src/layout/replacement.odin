// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package layout

import "../editor"
import "../editor_session"
import "../view"

/* registry_replace_pane_buffer atomically rebinds one pane to one live session entry. */
registry_replace_pane_buffer :: proc(
	registry: ^Registry,
	pane: Pane_Handle,
	session: ^editor_session.Session,
	incoming_entry: editor_session.Entry_Handle,
) -> (result: Replace_Result, ok: bool, failure: Failure_Context) {
	data, resolved := resolve_layout(registry, pane.layout, .Replace_Buffer)
	if resolved.code != .None {
		return {}, false, resolved
	}
	outgoing_slot, pane_ref, pane_failure := resolve_pane(data, pane, .Replace_Buffer)
	if pane_failure.code != .None {
		return {}, false, pane_failure
	}
	if outgoing_slot.dedication == .Hard {
		failure = data_failure(data, .Replace_Buffer, .Dedication_Conflict)
		failure.pane = pane_handle(data, pane_ref)
		failure.dedication = outgoing_slot.dedication
		return {}, false, failure
	}
	if session == nil || !editor_session.entry_handle_is_valid(incoming_entry) ||
	   !entry_session_matches(data, incoming_entry) {
		return {}, false, data_failure(data, .Replace_Buffer, .Invalid_Buffer_State)
	}
	access, accessed, access_failure := editor_session.session_entry_access(session, incoming_entry)
	if !accessed {
		return {}, false, layout_session_failure(data, .Replace_Buffer, access_failure)
	}
	incoming, borrowed, borrow_failure := editor_session.entry_access_borrow(access)
	if !borrowed {
		return {}, false, layout_session_failure(data, .Replace_Buffer, borrow_failure)
	}
	if incoming.view_registry != data.view_registry {
		return {}, false, data_failure(data, .Replace_Buffer, .Invalid_Buffer_State)
	}
	incoming_stats, stats_ok, stats_failure := editor.buffer_stats(incoming.buffer)
	if !stats_ok {
		failure = data_failure(data, .Replace_Buffer, .Invalid_Buffer_State)
		failure.session_failure = editor_session.Failure_Context {
			code = .Editor_Failure,
			operation = .Inspect,
			entry = incoming_entry,
			editor_failure = stats_failure,
		}
		return {}, false, failure
	}
	if outgoing_slot.entry == incoming_entry && outgoing_slot.buffer_id == incoming_stats.buffer_id {
		return Replace_Result {
			layout = current_layout_handle(data),
			pane = pane_handle(data, pane_ref),
			previous_entry = outgoing_slot.entry,
			entry = incoming_entry,
			view = outgoing_slot.view,
			changed = false,
		}, true, {}
	}
	if data.generation == Layout_Generation(max(u64)) || data.next_history_sequence > max(u64) - 3 {
		return {}, false, data_failure(data, .Replace_Buffer, .Generation_Limit)
	}
	if !prepared_state_fits(data) {
		return {}, false, prepared_failure(data, .Replace_Buffer)
	}
	outgoing_snapshot, outgoing_ok, outgoing_failure := view.snapshot(
		data.view_registry,
		outgoing_slot.view,
	)
	if !outgoing_ok {
		return {}, false, layout_view_failure(data, .Replace_Buffer, outgoing_failure)
	}
	outgoing_transient, transient_ok, transient_failure := view.transient_state(
		data.view_registry,
		outgoing_slot.view,
	)
	if !transient_ok {
		return {}, false, layout_view_failure(data, .Replace_Buffer, transient_failure)
	}
	if outgoing_transient.active_preparation || outgoing_transient.search ||
	   outgoing_transient.query_replacement {
		return {}, false, data_failure(data, .Replace_Buffer, .Busy)
	}
	if outgoing_snapshot.presentation_ownership == .Additional {
		close_ready, close_failure := view.validate_close(data.view_registry, outgoing_slot.view)
		if !close_ready {
			return {}, false, layout_view_failure(data, .Replace_Buffer, close_failure)
		}
	}
	incoming_snapshot, incoming_ok, incoming_failure := view.snapshot(
		data.view_registry,
		incoming.primary_view,
	)
	if !incoming_ok {
		return {}, false, layout_view_failure(data, .Replace_Buffer, incoming_failure)
	}
	if incoming_snapshot.buffer_id != incoming_stats.buffer_id ||
	   incoming_snapshot.presentation_ownership != .Retained_Primary {
		return {}, false, data_failure(data, .Replace_Buffer, .Invalid_Buffer_State)
	}
	incoming_displayed := false
	for &slot in data.nodes {
		if slot.live && slot.kind == .Pane && slot.pane_id != outgoing_slot.pane_id &&
		   slot.buffer_id == incoming_stats.buffer_id {
			incoming_displayed = true
			break
		}
	}
	incoming_view := incoming.primary_view
	created_additional := false
	if incoming_displayed {
		incoming_view, incoming_ok, incoming_failure = view.clone_additional(
			data.view_registry,
			incoming.primary_view,
		)
		if !incoming_ok {
			return {}, false, layout_view_failure(data, .Replace_Buffer, incoming_failure)
		}
		created_additional = true
		incoming_snapshot, incoming_ok, incoming_failure = view.snapshot(
			data.view_registry,
			incoming_view,
		)
		assert(incoming_ok && incoming_failure.code == .None)
	}
	restored_state, has_restored_state := pane_history_state_for_buffer(
		outgoing_slot,
		incoming_stats.buffer_id,
	)
	normalized_state := pane_buffer_state_from_view(incoming_entry, incoming_snapshot)
	if has_restored_state {
		normalized_state, incoming_ok = pane_buffer_state_normalize(
			restored_state,
			incoming_entry,
			incoming.buffer,
		)
		if !incoming_ok {
			if created_additional {
				closed, _ := view.close(data.view_registry, &incoming_view)
				assert(closed)
			}
			return {}, false, data_failure(data, .Replace_Buffer, .Invalid_Buffer_State)
		}
	}
	outgoing_state := pane_buffer_state_from_view(outgoing_slot.entry, outgoing_snapshot)
	if pane_ref == data.active {
		outgoing_state.stored_point = outgoing_snapshot.effective_point_position
	}
	proposed, prepared := prepared_state_copy(data, .Replace_Buffer)
	if prepared.code != .None {
		if created_additional {
			closed, _ := view.close(data.view_registry, &incoming_view)
			assert(closed)
		}
		return {}, false, prepared
	}
	defer prepared_state_release(proposed)
	proposed.generation = Layout_Generation(u64(data.generation) + 1)
	proposed_slot := resolve_node(proposed, pane_ref)
	assert(proposed_slot != nil && proposed_slot.kind == .Pane)
	pane_history_touch(proposed, proposed_slot, outgoing_state)
	proposed_slot.entry = incoming_entry
	proposed_slot.buffer_id = incoming_stats.buffer_id
	proposed_slot.view = incoming_view
	pane_history_touch(proposed, proposed_slot, normalized_state)
	buffer_list_touch(proposed, incoming_entry, incoming_stats.buffer_id)
	if !validate_layout_state(proposed) {
		if created_additional {
			closed, _ := view.close(data.view_registry, &incoming_view)
			assert(closed)
		}
		return {}, false, data_failure(data, .Replace_Buffer, .Invalid_Topology)
	}
	if has_restored_state {
		restored, restore_failure := view.restore_presentation(
			data.view_registry,
			incoming_view,
			normalized_state.stored_point.byte_offset,
			normalized_state.viewport_start.byte_offset,
			normalized_state.horizontal_display_column,
			normalized_state.desired_display_column,
		)
		if !restored {
			if created_additional {
				closed, _ := view.close(data.view_registry, &incoming_view)
				assert(closed)
			}
			return {}, false, layout_view_failure(data, .Replace_Buffer, restore_failure)
		}
	}
	if pane_ref == data.active {
		transferred, transfer_failure := view.transfer_focus(
			data.view_registry,
			outgoing_slot.view,
			incoming_view,
		)
		if !transferred {
			pane_view_restore_snapshot(data.view_registry, incoming_view, incoming_snapshot)
			if created_additional {
				closed, _ := view.close(data.view_registry, &incoming_view)
				assert(closed)
			}
			return {}, false, layout_view_failure(data, .Replace_Buffer, transfer_failure)
		}
	}
	if outgoing_snapshot.presentation_ownership == .Additional {
		removed := outgoing_slot.view
		closed, _ := view.close(data.view_registry, &removed)
		assert(closed)
	}
	previous_entry := outgoing_slot.entry
	result = Replace_Result {
		layout = current_layout_handle(proposed),
		pane = pane_handle(proposed, pane_ref),
		previous_entry = previous_entry,
		entry = incoming_entry,
		view = incoming_view,
		changed = true,
	}
	registry_publish(registry, proposed)
	return result, true, {}
}

@(private)
pane_history_state_for_buffer :: proc(
	slot: ^Node_Slot,
	buffer_id: editor.Buffer_ID,
) -> (Pane_Buffer_State, bool) {
	for candidate in slot.history[:slot.history_count] {
		if candidate.state.buffer_id == buffer_id {
			return candidate.state, true
		}
	}
	return {}, false
}

@(private)
pane_buffer_state_normalize :: proc(
	state: Pane_Buffer_State,
	entry: editor_session.Entry_Handle,
	buffer: ^editor.Buffer,
) -> (Pane_Buffer_State, bool) {
	stats, stats_ok, _ := editor.buffer_stats(buffer)
	if !stats_ok || stats.buffer_id != state.buffer_id {
		return {}, false
	}
	point, point_ok, _ := editor.buffer_position(
		buffer,
		editor.Byte_Offset(min(u64(state.stored_point.byte_offset), stats.text_bytes)),
	)
	viewport, viewport_ok, _ := editor.buffer_position(
		buffer,
		editor.Byte_Offset(min(u64(state.viewport_start.byte_offset), stats.text_bytes)),
	)
	if !point_ok || !viewport_ok {
		return {}, false
	}
	normalized := state
	normalized.entry = entry
	normalized.stored_point = point
	normalized.viewport_start = viewport
	return normalized, true
}

@(private)
pane_view_restore_snapshot :: proc(
	registry: ^view.Registry,
	handle: view.View_Handle,
	snapshot: view.Snapshot,
) {
	restored, _ := view.restore_presentation(
		registry,
		handle,
		snapshot.point_position.byte_offset,
		snapshot.viewport_origin_position.byte_offset,
		snapshot.horizontal_display_column,
		snapshot.desired_display_column,
	)
	assert(restored)
}

@(private)
layout_session_failure :: proc(
	data: ^Registry_Data,
	operation: Operation,
	session_failure: editor_session.Failure_Context,
) -> Failure_Context {
	failure := data_failure(data, operation, .Session_Failure)
	failure.session_failure = session_failure
	return failure
}
