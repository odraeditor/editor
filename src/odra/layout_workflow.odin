// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../command"
import "../display"
import "../editor_session"
import "../interaction"
import "../layout"
import editor_view "../view"
import "core:fmt"

@(private)
EDITOR_LAYOUT_RESERVED_ROWS :: i32(1)

@(private)
command_context_layout_is_live :: proc(commands: ^Command_Context) -> bool {
	return commands != nil && commands.layout_registry.state != nil && !commands.layout_registry.closed
}

@(private)
command_context_layout_ensure :: proc(
	commands: ^Command_Context,
	views: ^editor_view.Registry,
	root_view: editor_view.View_Handle,
	constraints: display.Viewport_Constraints,
) -> App_Failure {
	if command_context_layout_is_live(commands) {
		if commands.layout_entry == commands.current_entry {
			return {}
		}
		return command_context_layout_replace_active(commands, commands.current_entry)
	}
	allocator := commands.persistent_allocator
	if allocator.procedure == nil {
		allocator = context.allocator
	}
	ok, failure := layout.registry_init(
		&commands.layout_registry,
		layout.Owner_ID(1),
		layout.Layout_ID(1),
		views,
		root_view,
		command_context_layout_geometry(commands, constraints),
		layout.DEFAULT_POLICY,
		allocator,
		commands.current_entry,
	)
	if !ok {
		return App_Failure{stage = .Layout, layout = failure}
	}
	commands.layout_entry = commands.current_entry
	return {}
}

@(private)
command_context_layout_replace_active :: proc(
	commands: ^Command_Context,
	entry: editor_session.Entry_Handle,
) -> App_Failure {
	if !command_context_layout_is_live(commands) || commands.session_owner == nil ||
	   !editor_session.entry_handle_is_valid(entry) {
		return App_Failure{stage = .Layout}
	}
	handle, handle_ok, handle_failure := layout.registry_handle(&commands.layout_registry)
	if !handle_ok {
		return App_Failure{stage = .Layout, layout = handle_failure}
	}
	snapshot, allocation_error := new(layout.Snapshot, commands.temporary_allocator)
	if allocation_error != nil do return App_Failure{stage = .Layout}
	defer free(snapshot, commands.temporary_allocator)
	snapshot_ok, snapshot_failure := layout.registry_snapshot_into(
		&commands.layout_registry,
		handle,
		snapshot,
	)
	if !snapshot_ok {
		return App_Failure{stage = .Layout, layout = snapshot_failure}
	}
	active, active_ok := command_context_layout_active_node(snapshot)
	if !active_ok {
		return App_Failure{stage = .Layout}
	}
	_, replaced, replace_failure := layout.registry_replace_pane_buffer(
		&commands.layout_registry,
		active.pane,
		commands.session_owner,
		entry,
	)
	if !replaced {
		_, rolled_back, rollback_failure := editor_session.session_activate(
			commands.session_owner,
			active.entry,
		)
		if !rolled_back {
			return App_Failure{stage = .Session_Access, editor_session = rollback_failure}
		}
		commands.layout_entry = active.entry
		return App_Failure{stage = .Layout, layout = replace_failure}
	}
	commands.layout_entry = entry
	return {}
}

@(private)
command_context_layout_sync_active_entry :: proc(commands: ^Command_Context) -> App_Failure {
	if !command_context_layout_is_live(commands) || commands.session_owner == nil {
		return {}
	}
	handle, handle_ok, handle_failure := layout.registry_handle(&commands.layout_registry)
	if !handle_ok {
		return App_Failure{stage = .Layout, layout = handle_failure}
	}
	snapshot, snapshot_ok, snapshot_failure := layout.registry_snapshot(
		&commands.layout_registry,
		handle,
	)
	if !snapshot_ok {
		return App_Failure{stage = .Layout, layout = snapshot_failure}
	}
	active, active_ok := command_context_layout_active_node(&snapshot)
	if !active_ok || !editor_session.entry_handle_is_valid(active.entry) {
		return App_Failure{stage = .Layout}
	}
	if active.entry == commands.layout_entry {
		return {}
	}
	_, activated, activation_failure := editor_session.session_activate(
		commands.session_owner,
		active.entry,
	)
	if !activated {
		return App_Failure{stage = .Session_Access, editor_session = activation_failure}
	}
	commands.layout_entry = active.entry
	return {}
}

@(private)
command_context_layout_display_entry :: proc(
	commands: ^Command_Context,
	entry: editor_session.Entry_Handle,
	focus: bool,
) -> (ok: bool, failure: App_Failure) {
	_, ok, failure = command_context_layout_display_entry_result(commands, entry, focus)
	return
}

@(private)
command_context_layout_display_entry_result :: proc(
	commands: ^Command_Context,
	entry: editor_session.Entry_Handle,
	focus: bool,
) -> (result: layout.Display_Result, ok: bool, failure: App_Failure) {
	if !command_context_layout_is_live(commands) || commands.session_owner == nil ||
	   !editor_session.entry_handle_is_valid(entry) {
		return {}, false, App_Failure{stage = .Layout}
	}
	handle, handle_ok, handle_failure := layout.registry_handle(&commands.layout_registry)
	if !handle_ok {
		return {}, false, App_Failure{stage = .Layout, layout = handle_failure}
	}
	request, requested, request_failure := layout.registry_display_request(
		&commands.layout_registry,
		handle,
		commands.session_owner,
		entry,
	)
	if !requested {
		return {}, false, App_Failure{stage = .Layout, layout = request_failure}
	}
	proposal, proposed, proposal_failure := layout.registry_display_policy_factory_proposal(
		&commands.layout_registry,
		commands.session_owner,
		request,
	)
	if !proposed {
		return {}, false, App_Failure{stage = .Layout, layout = proposal_failure}
	}
	display_result, displayed, display_failure := layout.registry_display_buffer(
		&commands.layout_registry,
		commands.session_owner,
		proposal,
	)
	if !displayed {
		return {}, false, App_Failure{stage = .Layout, layout = display_failure}
	}
	if !focus {
		return display_result, true, {}
	}
	_, focused, focus_failure := layout.registry_focus(
		&commands.layout_registry,
		display_result.pane,
	)
	if !focused {
		return {}, false, App_Failure{stage = .Layout, layout = focus_failure}
	}
	_, activated, activation_failure := editor_session.session_activate(
		commands.session_owner,
		entry,
	)
	if !activated {
		return {}, false, App_Failure{stage = .Session_Access, editor_session = activation_failure}
	}
	commands.layout_entry = entry
	return display_result, true, {}
}

@(private)
command_context_layout_split_entry :: proc(
	commands: ^Command_Context,
	entry: editor_session.Entry_Handle,
	below: bool,
) -> (ok: bool, failure: App_Failure) {
	if !command_context_layout_is_live(commands) || commands.session_owner == nil ||
	   !editor_session.entry_handle_is_valid(entry) {
		return false, App_Failure{stage = .Layout}
	}
	handle, handle_ok, handle_failure := layout.registry_handle(&commands.layout_registry)
	if !handle_ok do return false, App_Failure{stage = .Layout, layout = handle_failure}
	snapshot, snapshot_ok, snapshot_failure := layout.registry_snapshot(&commands.layout_registry, handle)
	if !snapshot_ok do return false, App_Failure{stage = .Layout, layout = snapshot_failure}
	active, active_ok := command_context_layout_active_node(&snapshot)
	if !active_ok do return false, App_Failure{stage = .Layout}
	split: layout.Split_Result
	split_ok: bool
	split_failure: layout.Failure_Context
	if below {
		split, split_ok, split_failure = layout.registry_split_below(&commands.layout_registry, active.pane)
	} else {
		split, split_ok, split_failure = layout.registry_split_right(&commands.layout_registry, active.pane)
	}
	if !split_ok {
		_, _, _ = editor_session.session_activate(commands.session_owner, active.entry)
		commands.layout_entry = active.entry
		return false, App_Failure{stage = .Layout, layout = split_failure}
	}
	replaced, replaced_ok, replace_failure := layout.registry_replace_pane_buffer(
		&commands.layout_registry, split.created, commands.session_owner, entry,
	)
	if !replaced_ok {
		command_context_layout_rollback_created_pane(commands, split.created, active.entry)
		return false, App_Failure{stage = .Layout, layout = replace_failure}
	}
	focus_result, focused, focus_failure := layout.registry_focus(&commands.layout_registry, replaced.pane)
	if !focused {
		command_context_layout_rollback_created_pane(commands, replaced.pane, active.entry)
		return false, App_Failure{stage = .Layout, layout = focus_failure}
	}
	_, activated, activation_failure := editor_session.session_activate(commands.session_owner, entry)
	if !activated {
		command_context_layout_rollback_created_pane(commands, focus_result.active, active.entry)
		return false, App_Failure{stage = .Session_Access, editor_session = activation_failure}
	}
	commands.layout_entry = entry
	return true, {}
}

@(private)
command_context_layout_replace_mru_entry :: proc(
	commands: ^Command_Context,
	entry: editor_session.Entry_Handle,
) -> (ok: bool, failure: App_Failure) {
	if !command_context_layout_is_live(commands) || commands.session_owner == nil ||
	   !editor_session.entry_handle_is_valid(entry) {
		return false, App_Failure{stage = .Layout}
	}
	handle, handle_ok, handle_failure := layout.registry_handle(&commands.layout_registry)
	if !handle_ok do return false, App_Failure{stage = .Layout, layout = handle_failure}
	snapshot, snapshot_ok, snapshot_failure := layout.registry_snapshot(&commands.layout_registry, handle)
	if !snapshot_ok do return false, App_Failure{stage = .Layout, layout = snapshot_failure}
	active, active_ok := command_context_layout_active_node(&snapshot)
	if !active_ok do return false, App_Failure{stage = .Layout}
	target := active
	best_rank := max(u16)
	for node in snapshot.nodes[:int(snapshot.node_count)] {
		if node.kind != .Pane || node.active || node.dedication != .None do continue
		if node.mru_rank < best_rank {
			target = node
			best_rank = node.mru_rank
		}
	}
	replaced, replaced_ok, replace_failure := layout.registry_replace_pane_buffer(
		&commands.layout_registry, target.pane, commands.session_owner, entry,
	)
	if !replaced_ok {
		_, _, _ = editor_session.session_activate(commands.session_owner, active.entry)
		commands.layout_entry = active.entry
		return false, App_Failure{stage = .Layout, layout = replace_failure}
	}
	focus_result, focused, focus_failure := layout.registry_focus(&commands.layout_registry, replaced.pane)
	if !focused {
		_, _, _ = layout.registry_replace_pane_buffer(
			&commands.layout_registry, replaced.pane, commands.session_owner, target.entry,
		)
		_, _, _ = editor_session.session_activate(commands.session_owner, active.entry)
		commands.layout_entry = active.entry
		return false, App_Failure{stage = .Layout, layout = focus_failure}
	}
	_, activated, activation_failure := editor_session.session_activate(commands.session_owner, entry)
	if !activated {
		_, _, _ = layout.registry_replace_pane_buffer(
			&commands.layout_registry, focus_result.active, commands.session_owner, target.entry,
		)
		_, _, _ = editor_session.session_activate(commands.session_owner, active.entry)
		commands.layout_entry = active.entry
		return false, App_Failure{stage = .Session_Access, editor_session = activation_failure}
	}
	commands.layout_entry = entry
	return true, {}
}

@(private)
command_context_layout_rollback_created_pane :: proc(
	commands: ^Command_Context,
	created: layout.Pane_Handle,
	entry: editor_session.Entry_Handle,
) {
	if commands == nil do return
	focused, focused_ok, _ := layout.registry_focus(&commands.layout_registry, created)
	if focused_ok {
		_, _, _ = layout.registry_close_pane(&commands.layout_registry, focused.active)
	}
	if commands.session_owner != nil && editor_session.entry_handle_is_valid(entry) {
		_, _, _ = editor_session.session_activate(commands.session_owner, entry)
		commands.layout_entry = entry
	}
}

@(private)
command_context_layout_display_diagnostic :: proc(
	commands: ^Command_Context,
	failure: App_Failure,
) {
	if failure.stage == .Layout && failure.layout.code == .No_Other_Pane {
		command_context_set_diagnostic(commands, "No other pane is available")
		return
	}
	if failure.stage == .Layout {
		command_context_layout_failure_diagnostic(
			commands,
			"Other-pane display rejected",
			failure.layout,
		)
		return
	}
	command_context_set_diagnostic(commands, "Other-pane display failed")
}

@(private)
command_context_layout_failure_diagnostic :: proc(
	commands: ^Command_Context,
	label: string,
	failure: layout.Failure_Context,
) {
	message := fmt.bprintf(
		commands.diagnostic[:],
		"%s: %v during %v (layout %d:%d@%d, pane %d, limit %d, actual %d, view %v/%v, session %v/%v, policy %d/%d, hook %d, deferred %d)",
		label,
		failure.code,
		failure.operation,
		u64(failure.layout.owner_id),
		u64(failure.layout.layout_id),
		u64(failure.layout.generation),
		u64(failure.pane.pane_id),
		failure.maximum,
		failure.actual,
		failure.view_failure.code,
		failure.view_failure.editor_failure.code,
		failure.session_failure.code,
		failure.session_failure.view_failure.code,
		u64(failure.display_policy_generation),
		failure.display_action_index,
		u64(failure.hook.hook_id),
		u64(failure.deferred_sequence),
	)
	commands.diagnostic_length = len(message)
}

@(private)
command_context_layout_active_node :: proc(
	snapshot: ^layout.Snapshot,
) -> (layout.Node_Descriptor, bool) {
	if snapshot == nil do return {}, false
	for index in 0 ..< int(snapshot.node_count) {
		node := snapshot.nodes[index]
		if node.kind == .Pane && node.active {
			return node, true
		}
	}
	return {}, false
}

@(private)
command_context_kill_buffer :: proc(
	commands: ^Command_Context,
	selection_label: string,
	authority := editor_session.Close_Authority.Preserve_Modified,
	coordinated_terminal: editor_session.Terminal_Session_Ref = {},
) -> (result: command.Buffer_Kill_Result, ok: bool, failure: command.Failure_Context) {
	request := command.Buffer_Session_Context {
		session = commands.session_owner,
		handle = commands.session_handle,
		command = commands.document_workflow.buffer_command,
		configuration = commands.entry_configuration,
	}
	entry, found, find_failure := editor_session.session_find_label(
		commands.session_owner,
		commands.session_handle,
		selection_label,
	)
	if find_failure.code != .None || !found {
		return {}, false, command.Failure_Context {
			code = .Editor_Session_Failure,
			command = request.command,
			editor_session_code = find_failure.code,
		}
	}
	if !command_context_layout_is_live(commands) {
		assessment, assessed, assessment_failure := editor_session.session_assess_buffer_close(
			commands.session_owner,
			entry,
		)
		if !assessed {
			return {}, false, command.Failure_Context {
				code = .Editor_Session_Failure,
				command = request.command,
				editor_session_code = assessment_failure.code,
			}
		}
		if assessment.outcome == .Discard_Required && authority != .Discard_Modified {
			return command.buffer_session_kill_buffer(request, selection_label, authority)
		}
		factory_entry: editor_session.Entry_Handle
		if assessment.last_buffer {
			scratch, scratch_ok, scratch_failure := editor_session.session_create_buffer(
				commands.session_owner,
				editor_session.Create_Buffer_Request {
					session = commands.session_handle,
					name = "*scratch*",
					configuration = commands.entry_configuration,
				},
			)
			if !scratch_ok {
				return {}, false, command.Failure_Context {
					code = .Editor_Session_Failure,
					command = request.command,
					editor_session_code = scratch_failure.code,
				}
			}
			factory_entry = scratch.entry
		}
		kill_result, killed, kill_failure := command.buffer_session_kill_buffer(
			request,
			selection_label,
			authority,
		)
		if !killed && editor_session.entry_handle_is_valid(factory_entry) {
			_, scratch_closed, _ := editor_session.session_close_buffer(
				commands.session_owner,
				editor_session.Close_Buffer_Request {
					entry = factory_entry,
					authority = .Discard_Modified,
				},
			)
			assert(scratch_closed)
			_, reactivated, _ := editor_session.session_activate(commands.session_owner, entry)
			assert(reactivated)
		}
		if killed {
			kill_result.closure.was_visible = assessment.was_visible
		}
		return kill_result, killed, kill_failure
	}
	visible_before, visible_ok, _ := editor_session.session_visible_target(
		commands.session_owner,
		commands.session_handle,
	)
	target_was_visible := visible_ok && visible_before.kind == .Primary_View &&
	                      visible_before.entry == entry
	killed: layout.Kill_Result
	killed_ok: bool
	kill_failure: layout.Failure_Context
	if editor_session.terminal_session_ref_is_valid(coordinated_terminal) {
		killed, killed_ok, kill_failure = layout.registry_kill_terminal_buffer(
			&commands.layout_registry,
			commands.session_owner,
			entry,
			coordinated_terminal,
		)
	} else {
		killed, killed_ok, kill_failure = layout.registry_kill_buffer(
			&commands.layout_registry,
			commands.session_owner,
			entry,
			authority,
		)
	}
	if !killed_ok && kill_failure.code == .No_Fallback {
		scratch, scratch_ok, scratch_failure := editor_session.session_create_buffer(
			commands.session_owner,
			editor_session.Create_Buffer_Request {
				session = commands.session_handle,
				name = "*scratch*",
				configuration = commands.entry_configuration,
			},
		)
		if !scratch_ok {
			return {}, false, command.Failure_Context {
				code = .Editor_Session_Failure,
				command = request.command,
				editor_session_code = scratch_failure.code,
			}
		}
		if editor_session.terminal_session_ref_is_valid(coordinated_terminal) {
			killed, killed_ok, kill_failure = layout.registry_kill_terminal_buffer(
				&commands.layout_registry,
				commands.session_owner,
				entry,
				coordinated_terminal,
				scratch.entry,
			)
		} else {
			killed, killed_ok, kill_failure = layout.registry_kill_buffer(
				&commands.layout_registry,
				commands.session_owner,
				entry,
				authority,
				scratch.entry,
			)
		}
		if !killed_ok {
			_, scratch_closed, _ := editor_session.session_close_buffer(
				commands.session_owner,
				editor_session.Close_Buffer_Request {
					entry = scratch.entry,
					authority = .Discard_Modified,
				},
			)
			assert(scratch_closed)
			_, reactivated, _ := editor_session.session_activate(commands.session_owner, entry)
			assert(reactivated)
		}
	}
	if !killed_ok {
		return {}, false, command.Failure_Context {
			code = .Layout_Failure,
			command = request.command,
			layout_code = kill_failure.code,
			layout_failure = kill_failure,
			limit = kill_failure.maximum,
			actual = kill_failure.actual,
		}
	}
	if killed.outcome == .Discard_Required {
		return command.Buffer_Kill_Result {
			completion = .Discard_Required,
			closure = killed.closure,
		}, true, {}
	}
	if killed.outcome != .Killed {
		return {}, false, command.Failure_Context {
			code = .Layout_Failure,
			command = request.command,
		}
	}
	commands.layout_entry = killed.active_entry
	killed.closure.was_visible = target_was_visible
	return command.Buffer_Kill_Result {
		completion = .Closed,
		closure = killed.closure,
	}, true, {}
}

@(private)
command_context_layout_reset :: proc(commands: ^Command_Context) -> App_Failure {
	if !command_context_layout_is_live(commands) {
		commands.layout_registry = {}
		commands.layout_entry = {}
		return {}
	}
	closed, failure := layout.registry_close(&commands.layout_registry)
	if !closed {
		return App_Failure{stage = .Layout, layout = failure}
	}
	commands.layout_registry = {}
	commands.layout_entry = {}
	return {}
}

@(private)
command_context_layout_close :: proc(commands: ^Command_Context) -> App_Failure {
	if commands == nil || !command_context_layout_is_live(commands) {
		return {}
	}
	closed, failure := layout.registry_close(&commands.layout_registry)
	if !closed {
		return App_Failure{stage = .Layout, layout = failure}
	}
	commands.layout_registry = {}
	commands.layout_entry = {}
	return {}
}

@(private)
command_context_layout_active_view :: proc(
	commands: ^Command_Context,
	entry: editor_session.Entry_Handle,
	fallback: editor_view.View_Handle,
) -> (editor_view.View_Handle, App_Failure) {
	if !command_context_layout_is_live(commands) || commands.layout_entry != entry {
		return fallback, {}
	}
	handle, handle_ok, handle_failure := layout.registry_handle(&commands.layout_registry)
	if !handle_ok {
		return {}, App_Failure{stage = .Layout, layout = handle_failure}
	}
	snapshot, snapshot_ok, snapshot_failure := layout.registry_snapshot(
		&commands.layout_registry,
		handle,
	)
	if !snapshot_ok {
		return {}, App_Failure{stage = .Layout, layout = snapshot_failure}
	}
	for index in 0 ..< int(snapshot.node_count) {
		node := snapshot.nodes[index]
		if node.kind == .Pane && node.active {
			return node.view, {}
		}
	}
	return {}, App_Failure{stage = .Layout}
}

@(private)
command_context_layout_resize :: proc(
	commands: ^Command_Context,
	constraints: display.Viewport_Constraints,
) -> App_Failure {
	if !command_context_layout_is_live(commands) {
		return {}
	}
	handle, handle_ok, handle_failure := layout.registry_handle(&commands.layout_registry)
	if !handle_ok {
		return App_Failure{stage = .Resize, layout = handle_failure}
	}
	_, resized, resize_failure := layout.registry_materialize(
		&commands.layout_registry,
		handle,
		command_context_layout_geometry(commands, constraints),
		.External_Shrink,
	)
	if !resized {
		return App_Failure{stage = .Resize, layout = resize_failure}
	}
	return {}
}

@(private)
command_context_layout_is_insufficient :: proc(commands: ^Command_Context) -> bool {
	if !command_context_layout_is_live(commands) {
		return false
	}
	handle, handle_ok, _ := layout.registry_handle(&commands.layout_registry)
	if !handle_ok {
		return false
	}
	snapshot, snapshot_ok, _ := layout.registry_snapshot(&commands.layout_registry, handle)
	return snapshot_ok && snapshot.geometry_state == .Insufficient
}

@(private)
command_context_layout_has_single_pane :: proc(commands: ^Command_Context) -> bool {
	if !command_context_layout_is_live(commands) do return false
	handle, handle_ok, _ := layout.registry_handle(&commands.layout_registry)
	if !handle_ok do return false
	snapshot, snapshot_ok, _ := layout.registry_snapshot(&commands.layout_registry, handle)
	return snapshot_ok && snapshot.pane_count == 1
}

@(private)
command_context_is_layout_route :: proc(route: command.Native_Route) -> bool {
	return route == .Split_Pane_Below || route == .Split_Pane_Right || route == .Close_Pane ||
	       route == .Keep_Only_Pane || route == .Focus_Next_Pane ||
	       route == .Focus_Pane_Left || route == .Focus_Pane_Down ||
	       route == .Focus_Pane_Up || route == .Focus_Pane_Right ||
	       route == .Enlarge_Pane_Vertically || route == .Enlarge_Pane_Horizontally ||
	       route == .Shrink_Pane_Horizontally || route == .Balance_Panes ||
	       route == .Balance_Pane_Areas ||
	       route == .Find_File_Other_Pane || route == .Switch_To_Buffer_Other_Pane ||
	       route == .Display_Buffer_Other_Pane
}

@(private)
command_context_recovery_route_is_allowed :: proc(route: interaction.Command_Route) -> bool {
	native, ok := command.native_route_decode(route)
	return ok && (native == .Close_Pane || native == .Keep_Only_Pane ||
	       native == .Request_Editor_Exit)
}

@(private)
command_context_layout_geometry :: proc(
	commands: ^Command_Context,
	constraints: display.Viewport_Constraints,
) -> layout.Geometry_Request {
	return layout.Geometry_Request {
		rows = i32(constraints.height_rows),
		columns = i32(constraints.width_cells),
		global_reserved_rows = EDITOR_LAYOUT_RESERVED_ROWS,
		global_reserved_columns = i32(darek_workflow_reserved_columns(commands, constraints)),
	}
}
