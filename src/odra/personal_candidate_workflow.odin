// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../command"
import "../display"
import "../document"
import "../editor"
import "../editor_session"
import "../hosting"
import "../interaction"
import editor_view "../view"
import edit_transaction "../transaction"
import "base:runtime"
import "core:fmt"

@(private)
Personal_Candidate_Workflow_State :: struct {
	payload:        []u8,
	command_handle: interaction.Command_Handle,
	constraints:    display.Viewport_Constraints,
	title:          [interaction.MAX_CANDIDATE_PROMPT_LABEL_BYTES]u8,
	title_length:   u32,
	allocator:      runtime.Allocator,
}

@(private)
command_context_present_personal_candidates :: proc(
	commands: ^Command_Context,
	payload: []u8,
	command_handle: interaction.Command_Handle,
	constraints: display.Viewport_Constraints,
) -> (Interaction_Result, App_Failure) {
	if commands == nil || len(payload) == 0 {
		return {}, App_Failure{stage = .Component_Access}
	}
	visible, visible_ok, visible_failure := editor_session.session_visible_target(
		commands.session_owner, commands.session_handle,
	)
	if !visible_ok || visible.kind != .Primary_View {
		return {}, App_Failure{stage = .Session_Access, editor_session = visible_failure}
	}
	source_generation := commands.candidate_ui.next_source_generation
	session_id := commands.candidate_ui.next_session_id
	if source_generation == 0 || source_generation == max(u64) ||
	   session_id == 0 || session_id == max(u64) {
		return {}, App_Failure{stage = .Component_Access}
	}
	source, decoded, decode_failure := interaction.personal_candidate_source_decode(
		payload, source_generation, commands.temporary_allocator,
	)
	if !decoded {
		command_context_candidate_failure_diagnostic(commands, "Command candidates", decode_failure)
		return Interaction_Result{changed = true}, {}
	}
	defer interaction.personal_candidate_source_close(&source)
	if len(source.targets) == 1 && source.targets[0].action == .Navigate_Direct {
		return command_context_open_personal_target(
			commands,
			source.targets[0],
			source.descriptors[0].label,
			visible,
			command_handle,
			false,
		)
	}
	candidate_session: interaction.Candidate_Session
	_, initialized, initialization_failure := interaction.candidate_session_init(
		&candidate_session,
		interaction.Candidate_Config {
			session_id = interaction.Candidate_Session_ID(session_id),
			limits = interaction.DEFAULT_CANDIDATE_LIMITS,
			persistent_allocator = commands.persistent_allocator,
			temporary_allocator = commands.temporary_allocator,
		},
		source.definition,
		source.initial_query,
	)
	if !initialized {
		command_context_candidate_failure_diagnostic(
			commands, "Command candidate session", initialization_failure,
		)
		return Interaction_Result{changed = true}, {}
	}
	keep_session := false
	defer if !keep_session do _, _, _ = interaction.candidate_session_close(&candidate_session)
	owned_payload, allocation_error := make([]u8, len(payload), commands.persistent_allocator)
	if allocation_error != nil do return {}, App_Failure{stage = .Component_Access}
	copy(owned_payload, payload)
	personal_candidate_workflow_reset(commands)
	if commands.candidate_ui.catalog.state != nil {
		interaction.command_catalog_close(&commands.candidate_ui.catalog)
	}
	if commands.candidate_ui.session.state != nil {
		_, _, _ = interaction.candidate_session_close(&commands.candidate_ui.session)
	}
	commands.personal_candidate_workflow = {
		payload = owned_payload,
		command_handle = command_handle,
		constraints = constraints,
		allocator = commands.persistent_allocator,
	}
	commands.personal_candidate_workflow.title_length = u32(copy(
		commands.personal_candidate_workflow.title[:],
		transmute([]u8)source.title,
	))
	commands.candidate_ui.session = candidate_session
	commands.candidate_ui.return_target = visible
	commands.candidate_ui.next_session_id = session_id + 1
	commands.candidate_ui.next_source_generation = source_generation + 1
	keep_session = true
	command_context_end_prompt(commands)
	_, _, presented, present_failure := editor_session.session_present_ui(
		commands.session_owner, commands.session_handle, candidate_ui_visible_target().ui,
	)
	if !presented {
		personal_candidate_workflow_reset(commands)
		return {}, App_Failure{stage = .Session_Access, editor_session = present_failure}
	}
	commands.pending = {}
	return Interaction_Result{changed = true}, {}
}

@(private)
dispatch_personal_candidate_input :: proc(
	commands: ^Command_Context,
	input: interaction.Input,
) -> (Interaction_Result, App_Failure) {
	view, viewed, view_failure := interaction.candidate_session_view(&commands.candidate_ui.session)
	if !viewed || view.source_kind != .Personal_Command_Results {
		return {}, App_Failure{stage = .Component_Access, candidate = view_failure}
	}
	if map_failure := command_context_sync_candidate_map(commands, .Personal_Command_Results);
	   map_failure.stage != .None do return {}, map_failure
	metadata, resolution, resolved, resolution_failure :=
		command_context_resolve_context_input(commands, input)
	if !resolved do return {}, resolution_failure
	if resolution.kind != .Command do return {}, {}
	request := interaction.Candidate_Request {
		session_id = view.session_id,
		session_generation = view.session_generation,
	}
	contextual_route, contextual_ok := command.contextual_route_decode(metadata.route)
	if contextual_ok && (contextual_route == .Component_Previous_Row ||
	   contextual_route == .Component_Next_Row || contextual_route == .Result_First ||
	   contextual_route == .Result_Last) {
		delta := i32(1)
		if contextual_route == .Component_Previous_Row do delta = -1
		if contextual_route == .Result_First do delta = -i32(view.selected_row) - 1
		if contextual_route == .Result_Last do delta = i32(len(view.rows))
		movement, moved, move_failure := interaction.candidate_session_move(
			&commands.candidate_ui.session, request, delta,
		)
		if !moved {
			command_context_candidate_failure_diagnostic(commands, "Candidate movement", move_failure)
			return Interaction_Result{changed = true}, {}
		}
		return Interaction_Result{changed = movement.transition != .No_Change}, {}
	}
	if contextual_route == .Component_Query_Text {
		if len(resolution.text) == 0 do return {}, {}
		if len(view.query) + len(resolution.text) > int(interaction.MAX_CANDIDATE_QUERY_BYTES) {
			command_context_set_diagnostic(commands, "Candidate query limit reached")
			return Interaction_Result{changed = true}, {}
		}
		query: [interaction.MAX_CANDIDATE_QUERY_BYTES]u8
		copy(query[:], transmute([]u8)view.query)
		copy(query[len(view.query):], transmute([]u8)resolution.text)
		_, queried, query_failure := interaction.candidate_session_set_query(
			&commands.candidate_ui.session, request,
			string(query[:len(view.query) + len(resolution.text)]),
		)
		if !queried do command_context_candidate_failure_diagnostic(commands, "Candidate query", query_failure)
		return Interaction_Result{changed = true}, {}
	}
	if contextual_route == .Component_Query_Delete_Previous {
		if len(view.query) == 0 do return {}, {}
		end := len(view.query) - 1
		bytes := transmute([]u8)view.query
		for end > 0 && bytes[end] & 0xc0 == 0x80 do end -= 1
		_, queried, query_failure := interaction.candidate_session_set_query(
			&commands.candidate_ui.session, request, view.query[:end],
		)
		if !queried do command_context_candidate_failure_diagnostic(commands, "Candidate query", query_failure)
		return Interaction_Result{changed = true}, {}
	}
	if contextual_route == .Component_Activate_Current {
		return command_context_activate_personal_candidate(commands, view)
	}
	if contextual_route == .Result_Refresh {
		return command_context_refresh_personal_candidates(commands, view)
	}
	if contextual_route == .Component_Close || command_metadata_is_native(metadata, .Keyboard_Quit) {
		return command_context_leave_personal_candidates(commands)
	}
	return {}, {}
}

@(private)
command_context_refresh_personal_candidates :: proc(
	commands: ^Command_Context,
	view: interaction.Candidate_View,
) -> (Interaction_Result, App_Failure) {
	if commands == nil || view.source_kind != .Personal_Command_Results ||
	   commands.candidate_ui.return_target.kind != .Primary_View ||
	   commands.next_transaction_id == 0 || commands.next_undo_unit_id == 0 {
		return {}, App_Failure{stage = .Component_Access}
	}
	query: [interaction.MAX_CANDIDATE_QUERY_BYTES]u8
	query_length := copy(query[:], transmute([]u8)view.query)
	return_target := commands.candidate_ui.return_target
	command_handle := commands.personal_candidate_workflow.command_handle
	constraints := commands.personal_candidate_workflow.constraints
	access, accessible, access_failure := editor_session.session_entry_access(
		commands.session_owner,
		return_target.entry,
	)
	if !accessible {
		return {}, App_Failure{stage = .Session_Access, editor_session = access_failure}
	}
	entry, borrowed, borrow_failure := editor_session.entry_access_borrow(access)
	if !borrowed {
		return {}, App_Failure{stage = .Session_Access, editor_session = borrow_failure}
	}
	command_context_bind_entry(commands, return_target.entry, entry)
	transaction_id := commands.next_transaction_id
	undo_unit_id := commands.next_undo_unit_id
	if transaction_id == max(u64) {
		commands.next_transaction_id = 0
	} else {
		commands.next_transaction_id += 1
	}
	if undo_unit_id == max(u64) {
		commands.next_undo_unit_id = 0
	} else {
		commands.next_undo_unit_id += 1
	}
	observer_context := Syntax_Commit_Observer_Context {
		workflow = commands.syntax_workflow,
		buffer = entry.buffer,
	}
	result, executed, execute_failure := command.racket_command_execute(
		command.Racket_Context {
			runtime = commands.racket_runtime,
			capabilities = commands.capabilities,
			transaction_capabilities = commands.transaction_capabilities,
			command_registry = commands.registry,
			command = command_handle,
			buffer = entry.buffer,
			document = entry.document if entry.has_document else nil,
			session_owner = commands.session_owner,
			session_handle = commands.session_handle,
			view_registry = entry.view_registry,
			view = entry.primary_view,
			profile = display.terminal_unicode17_profile(),
			constraints = constraints,
			temporary_allocator = commands.temporary_allocator,
			persistent_allocator = commands.persistent_allocator,
			transaction_id = edit_transaction.Transaction_ID(transaction_id),
			undo_unit_id = edit_transaction.Undo_Unit_ID(undo_unit_id),
			history_store = entry.history_store,
			commit_observer = syntax_workflow_commit_observer(&observer_context),
		},
	)
	defer command.native_result_close(&result)
	if !executed {
		if command_context_contain_personal_command_failure(
			commands, .Personal, execute_failure,
		) {
			return Interaction_Result{changed = true}, {}
		}
		return {}, App_Failure{stage = .Command_Dispatch, command = execute_failure}
	}
	if len(result.personal_result) == 0 {
		message := hosting.runtime_diagnostic(commands.racket_runtime)
		if len(message) > 0 {
			command_context_set_diagnostic(commands, message)
		} else {
			command_context_set_diagnostic(commands, "Candidate refresh returned no results")
		}
		return Interaction_Result{changed = true}, {}
	}
	_, activated, activation_failure := editor_session.session_activate(
		commands.session_owner,
		return_target.entry,
	)
	if !activated {
		return {}, App_Failure{stage = .Session_Access, editor_session = activation_failure}
	}
	presented, present_failure := command_context_present_personal_candidates(
		commands, result.personal_result, command_handle, constraints,
	)
	if present_failure.stage != .None do return {}, present_failure
	if query_length > 0 {
		refreshed, viewed, _ := interaction.candidate_session_view(&commands.candidate_ui.session)
		if viewed {
			_, _, _ = interaction.candidate_session_set_query(
				&commands.candidate_ui.session,
				interaction.Candidate_Request {
					session_id = refreshed.session_id,
					session_generation = refreshed.session_generation,
				},
				string(query[:query_length]),
			)
		}
	}
	return presented, {}
}

@(private)
command_context_activate_personal_candidate :: proc(
	commands: ^Command_Context,
	view: interaction.Candidate_View,
) -> (Interaction_Result, App_Failure) {
	if !view.has_selection || len(view.rows) == 0 do return {}, {}
	source, decoded, _ := interaction.personal_candidate_source_decode(
		commands.personal_candidate_workflow.payload,
		view.source_generation,
		commands.temporary_allocator,
	)
	if !decoded {
		command_context_set_diagnostic(commands, "Candidate target is unavailable")
		return Interaction_Result{changed = true}, {}
	}
	defer interaction.personal_candidate_source_close(&source)
	target, found := interaction.personal_candidate_action_target(
		view.rows[view.selected_row].action, &source,
	)
	if !found || u64(len(target.document_path)) > document.MAX_PATH_BYTES {
		command_context_set_diagnostic(commands, "Candidate target is stale")
		return Interaction_Result{changed = true}, {}
	}
	if target.action == .Resume {
		return command_context_resume_personal_candidate(
			commands, target, target.identity, false,
		)
	}
	if target.action == .Resume_Value {
		return command_context_resume_personal_candidate(
			commands, target, target.identity, true,
		)
	}
	if target.action == .Resume_Query {
		if len(view.query) == 0 {
			command_context_set_diagnostic(commands, "Enter a value before continuing")
			return Interaction_Result{changed = true}, {}
		}
		return command_context_resume_personal_candidate(
			commands, target, view.query, true,
		)
	}
	if target.action != .Navigate {
		command_context_set_diagnostic(commands, "Candidate target is unavailable")
		return Interaction_Result{changed = true}, {}
	}
	return command_context_open_personal_target(
		commands,
		target,
		view.rows[view.selected_row].label,
		commands.candidate_ui.return_target,
		commands.personal_candidate_workflow.command_handle,
		true,
	)
}

@(private)
command_context_open_personal_target :: proc(
	commands: ^Command_Context,
	target: interaction.Personal_Candidate_Target,
	label: string,
	return_target: editor_session.Visible_Target,
	command_handle: interaction.Command_Handle,
	candidate_workflow: bool,
) -> (Interaction_Result, App_Failure) {
	if u64(len(target.document_path)) > document.MAX_PATH_BYTES ||
	   return_target.kind != .Primary_View {
		command_context_set_diagnostic(commands, "Candidate target is stale")
		return Interaction_Result{changed = true}, {}
	}
	path: [document.MAX_PATH_BYTES]u8
	path_length := copy(path[:], transmute([]u8)target.document_path)
	previous, previous_ok := command_context_named_location_return_state(
		commands, return_target,
	)
	result, opened, open_failure := command.buffer_session_find_file(
		command.Buffer_Session_Context {
			session = commands.session_owner,
			handle = commands.session_handle,
			command = command_handle,
			configuration = commands.entry_configuration,
		},
		string(path[:path_length]),
	)
	if !opened {
		command_context_buffer_session_diagnostic(commands, open_failure)
		return Interaction_Result{changed = true}, {}
	}
	access, accessible, access_failure := editor_session.session_entry_access(
		commands.session_owner, result.entry,
	)
	if !accessible do return {}, App_Failure{stage = .Session_Access, editor_session = access_failure}
	entry, borrowed, borrow_failure := editor_session.entry_access_borrow(access)
	if !borrowed do return {}, App_Failure{stage = .Session_Access, editor_session = borrow_failure}
	stats, stats_ok, _ := editor.buffer_stats(entry.buffer)
	if !stats_ok || target.start > target.end || target.end > stats.text_bytes {
		if candidate_workflow {
			_, _, represented, representation_failure := editor_session.session_present_ui(
				commands.session_owner,
				commands.session_handle,
				candidate_ui_visible_target().ui,
			)
			if !represented {
				return {}, App_Failure{stage = .Session_Access, editor_session = representation_failure}
			}
		}
		command_context_set_diagnostic(commands, "Candidate target is stale")
		return Interaction_Result{changed = true}, {}
	}
	position, positioned, _ := editor.buffer_position(entry.buffer, editor.Byte_Offset(target.start))
	if !positioned {
		command_context_set_diagnostic(commands, "Candidate target is stale")
		return Interaction_Result{changed = true}, {}
	}
	moved, _ := editor_view.set_point(entry.view_registry, entry.primary_view, position)
	if !moved do return {}, App_Failure{stage = .Component_Access}
	cleared, clear_failure := editor.buffer_selection_clear_mark(entry.buffer)
	if !cleared do return {}, App_Failure{stage = .Component_Access, editor = clear_failure}
	diagnostic: [document.MAX_DIAGNOSTIC_BYTES]u8
	message := fmt.bprintf(
		diagnostic[:],
		"Opened %s",
		label,
	)
	command_context_set_diagnostic(commands, message)
	if candidate_workflow {
		command_context_deactivate_context_map(commands, .Completed)
		personal_candidate_workflow_reset(commands)
	}
	if previous_ok && commands.location_history != nil {
		_ = command.location_history_push(commands.location_history, previous)
	}
	return Interaction_Result{changed = true}, {}
}

@(private)
command_context_resume_personal_candidate :: proc(
	commands: ^Command_Context,
	target: interaction.Personal_Candidate_Target,
	selection_value: string,
	clear_region: bool,
) -> (Interaction_Result, App_Failure) {
	if len(selection_value) == 0 || len(selection_value) > 4_096 ||
	   commands.candidate_ui.return_target.kind != .Primary_View ||
	   commands.next_transaction_id == 0 || commands.next_undo_unit_id == 0 {
		command_context_set_diagnostic(commands, "Candidate target is stale")
		return Interaction_Result{changed = true}, {}
	}
	selection_storage: [4_096]u8
	selection_length := copy(selection_storage[:], transmute([]u8)selection_value)
	selection := string(selection_storage[:selection_length])
	return_target := commands.candidate_ui.return_target
	command_handle := commands.personal_candidate_workflow.command_handle
	constraints := commands.personal_candidate_workflow.constraints
	command_context_deactivate_context_map(commands, .Completed)
	personal_candidate_workflow_reset(commands)
	_, activated, activation_failure := editor_session.session_activate(
		commands.session_owner, return_target.entry,
	)
	if !activated {
		return {}, App_Failure{stage = .Session_Access, editor_session = activation_failure}
	}
	access, accessible, access_failure := editor_session.session_entry_access(
		commands.session_owner, return_target.entry,
	)
	if !accessible {
		return {}, App_Failure{stage = .Session_Access, editor_session = access_failure}
	}
	entry, borrowed, borrow_failure := editor_session.entry_access_borrow(access)
	if !borrowed {
		return {}, App_Failure{stage = .Session_Access, editor_session = borrow_failure}
	}
	command_context_bind_entry(commands, return_target.entry, entry)
	logical, logical_ok, _ := editor_view.snapshot(entry.view_registry, entry.primary_view)
	status: document.Document_Status
	status_ok := false
	if entry.has_document && entry.document != nil {
		status, status_ok, _ = document.document_status(entry.document)
	}
	region_matches := false
	if logical_ok {
		if target.start == target.end {
			region_matches = !logical.region_active &&
			                 u64(logical.point_position.byte_offset) == target.start
		} else if logical.region_active && logical.mark.present {
			point := u64(logical.point_position.byte_offset)
			mark := u64(logical.mark.position.byte_offset)
			region_matches = min(point, mark) == target.start &&
			                 max(point, mark) == target.end
		}
	}
	if !logical_ok || !status_ok || !status.has_target ||
	   status.target_path != target.document_path ||
	   u64(logical.revision) != target.source_revision || !region_matches {
		command_context_set_diagnostic(commands, "Candidate target is stale")
		return Interaction_Result{changed = true}, {}
	}
	if clear_region {
		cleared, clear_failure := editor.buffer_selection_clear_mark(entry.buffer)
		if !cleared {
			return {}, App_Failure{stage = .Component_Access, editor = clear_failure}
		}
	}
	transaction_id := commands.next_transaction_id
	undo_unit_id := commands.next_undo_unit_id
	if transaction_id == max(u64) {
		commands.next_transaction_id = 0
	} else {
		commands.next_transaction_id += 1
	}
	if undo_unit_id == max(u64) {
		commands.next_undo_unit_id = 0
	} else {
		commands.next_undo_unit_id += 1
	}
	observer_context := Syntax_Commit_Observer_Context {
		workflow = commands.syntax_workflow,
		buffer = entry.buffer,
	}
	result, executed, execute_failure := command.racket_command_execute(
		command.Racket_Context {
			runtime = commands.racket_runtime,
			capabilities = commands.capabilities,
			transaction_capabilities = commands.transaction_capabilities,
			command_registry = commands.registry,
			command = command_handle,
			buffer = entry.buffer,
			document = entry.document if entry.has_document else nil,
			session_owner = commands.session_owner,
			session_handle = commands.session_handle,
			view_registry = entry.view_registry,
			view = entry.primary_view,
			profile = display.terminal_unicode17_profile(),
			constraints = constraints,
			temporary_allocator = commands.temporary_allocator,
			persistent_allocator = commands.persistent_allocator,
			transaction_id = edit_transaction.Transaction_ID(transaction_id),
			undo_unit_id = edit_transaction.Undo_Unit_ID(undo_unit_id),
			history_store = entry.history_store,
			commit_observer = syntax_workflow_commit_observer(&observer_context),
			personal_selection = selection,
		},
	)
	defer command.native_result_close(&result)
	if !executed {
		if command_context_contain_personal_command_failure(
			commands, .Personal, execute_failure,
		) {
			return Interaction_Result{changed = true}, {}
		}
		return {}, App_Failure{stage = .Command_Dispatch, command = execute_failure}
	}
	message := hosting.runtime_diagnostic(commands.racket_runtime)
	if len(message) > 0 do command_context_set_diagnostic(commands, message)
	if len(result.personal_result) > 0 {
		return command_context_present_personal_candidates(
			commands, result.personal_result, command_handle, constraints,
		)
	}
	return Interaction_Result{changed = true}, {}
}

@(private)
command_context_leave_personal_candidates :: proc(
	commands: ^Command_Context,
) -> (Interaction_Result, App_Failure) {
	return_target := commands.candidate_ui.return_target
	command_context_deactivate_context_map(commands, .Cancelled)
	personal_candidate_workflow_reset(commands)
	if return_target.kind != .Primary_View do return {}, App_Failure{stage = .Session_Access}
	_, activated, activation_failure := editor_session.session_activate(
		commands.session_owner, return_target.entry,
	)
	if !activated do return {}, App_Failure{stage = .Session_Access, editor_session = activation_failure}
	commands.diagnostic_length = 0
	return Interaction_Result{changed = true}, {}
}

@(private)
personal_candidate_workflow_reset :: proc(commands: ^Command_Context) {
	if commands == nil do return
	if commands.candidate_ui.session.state != nil {
		_, _, _ = interaction.candidate_session_close(&commands.candidate_ui.session)
	}
	commands.candidate_ui.return_target = {}
	state := &commands.personal_candidate_workflow
	if state.payload != nil && state.allocator.procedure != nil {
		delete(state.payload, state.allocator)
	}
	state^ = {}
}

@(private)
personal_candidate_workflow_prompt_label :: proc(
	commands: ^Command_Context,
	view: interaction.Candidate_View,
	output: []u8,
) -> (string, bool) {
	if commands == nil || commands.personal_candidate_workflow.title_length == 0 {
		return "", false
	}
	state := &commands.personal_candidate_workflow
	title := string(state.title[:int(state.title_length)])
	selected := u32(0)
	if view.has_selection && len(view.rows) > 0 do selected = view.selected_row + 1
	label := fmt.bprintf(output, "%s %d/%d Filter: ", title, selected, len(view.rows))
	return label, len(label) > 0
}
