// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../command"
import "../editor"
import "../editor_session"
import "../interaction"
import "../result_set"
import edit_transaction "../transaction"
import editor_view "../view"

@(private)
Result_Workflow_State :: struct {
	projection:  result_set.Edit_Projection,
	set_id:      result_set.Result_Set_ID,
	generation:  result_set.Result_Set_Generation,
	location_id: result_set.Location_ID,
}

@(private)
command_context_present_results :: proc(
	commands: ^Command_Context,
	set_id: result_set.Result_Set_ID,
) -> (Interaction_Result, App_Failure) {
	visible, visible_ok, visible_failure := editor_session.session_visible_target(
		commands.session_owner, commands.session_handle)
	if !visible_ok || visible.kind != .Primary_View {
		return {}, App_Failure{stage = .Session_Access, editor_session = visible_failure}
	}
	registry, registry_ok, registry_failure := editor_session.session_result_registry(
		commands.session_owner, commands.session_handle)
	if !registry_ok do return {}, App_Failure{stage = .Session_Access, editor_session = registry_failure}
	result_view, viewed, _ := result_set.registry_view(registry, set_id)
	if !viewed {
		command_context_set_diagnostic(commands, "No current results")
		return Interaction_Result{changed = true}, {}
	}
	source_generation := commands.candidate_ui.next_source_generation
	session_id := commands.candidate_ui.next_session_id
	if source_generation == 0 || source_generation == max(u64) || session_id == 0 || session_id == max(u64) {
		return {}, App_Failure{stage = .Component_Access}
	}
	source, built, source_failure := interaction.result_candidate_source_build(
		result_view, source_generation, commands.temporary_allocator)
	if !built do return {}, App_Failure{stage = .Component_Access, candidate = source_failure}
	defer interaction.result_candidate_source_close(&source)
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
	)
	if !initialized do return {}, App_Failure{stage = .Component_Access, candidate = initialization_failure}
	keep_session := false
	defer if !keep_session do _, _, _ = interaction.candidate_session_close(&candidate_session)
	if result_view.has_selection && result_view.selected_index > 0 {
		candidate_view, _, _ := interaction.candidate_session_view(&candidate_session)
		_, _, _ = interaction.candidate_session_move(
			&candidate_session,
			{session_id = candidate_view.session_id, session_generation = candidate_view.session_generation},
			i32(result_view.selected_index),
		)
	}
	if commands.candidate_ui.catalog.state != nil do interaction.command_catalog_close(&commands.candidate_ui.catalog)
	if commands.candidate_ui.session.state != nil do _, _, _ = interaction.candidate_session_close(&commands.candidate_ui.session)
	commands.candidate_ui.session = candidate_session
	commands.candidate_ui.return_target = visible
	commands.candidate_ui.next_session_id = session_id + 1
	commands.candidate_ui.next_source_generation = source_generation + 1
	keep_session = true
	command_context_end_prompt(commands)
	_, _, presented, present_failure := editor_session.session_present_ui(
		commands.session_owner, commands.session_handle, candidate_ui_visible_target().ui)
	if !presented do return {}, App_Failure{stage = .Session_Access, editor_session = present_failure}
	commands.pending = {}
	return Interaction_Result{changed = true}, {}
}

@(private)
dispatch_result_input :: proc(
	commands: ^Command_Context,
	input: interaction.Input,
) -> (Interaction_Result, App_Failure) {
	view, viewed, view_failure := interaction.candidate_session_view(&commands.candidate_ui.session)
	if !viewed || view.source_kind != .Results {
		return {}, App_Failure{stage = .Component_Access, candidate = view_failure}
	}
	if map_failure := command_context_sync_candidate_map(commands, .Results); map_failure.stage != .None {
		return {}, map_failure
	}
	metadata, resolution, resolved, resolution_failure := command_context_resolve_context_input(
		commands, input)
	if !resolved do return {}, resolution_failure
	if resolution.kind != .Command do return {}, {}
	request := interaction.Candidate_Request{session_id = view.session_id,
		session_generation = view.session_generation}
	contextual_route, contextual_ok := command.contextual_route_decode(metadata.route)
	if contextual_ok && (contextual_route == .Component_Previous_Row ||
	   contextual_route == .Component_Next_Row || contextual_route == .Result_First ||
	   contextual_route == .Result_Last) {
		delta := i32(1)
		if contextual_route == .Component_Previous_Row do delta = -1
		if contextual_route == .Result_First do delta = -i32(view.selected_row) - 1
		if contextual_route == .Result_Last do delta = i32(len(view.rows))
		movement, moved, move_failure := interaction.candidate_session_move(
			&commands.candidate_ui.session, request, delta)
		if !moved do command_context_candidate_failure_diagnostic(commands, "Result movement", move_failure)
		if !moved do return Interaction_Result{changed = true}, {}
		if movement.transition == .No_Change do return {}, {}
		command_context_sync_result_selection(commands)
		return Interaction_Result{changed = true}, {}
	}
	if contextual_route == .Component_Query_Text {
		if len(resolution.text) == 0 do return {}, {}
		if len(view.query) + len(resolution.text) > int(interaction.MAX_CANDIDATE_QUERY_BYTES) {
			command_context_set_diagnostic(commands, "Result query limit reached")
			return Interaction_Result{changed = true}, {}
		}
		query: [interaction.MAX_CANDIDATE_QUERY_BYTES]u8
		copy(query[:], transmute([]u8)view.query)
		copy(query[len(view.query):], transmute([]u8)resolution.text)
		_, queried, query_failure := interaction.candidate_session_set_query(
			&commands.candidate_ui.session, request,
			string(query[:len(view.query) + len(resolution.text)]))
		if !queried do command_context_candidate_failure_diagnostic(commands, "Result query", query_failure)
		if queried do command_context_sync_result_selection(commands)
		return Interaction_Result{changed = true}, {}
	}
	if contextual_route == .Component_Query_Delete_Previous {
		if len(view.query) == 0 do return {}, {}
		end := len(view.query) - 1
		bytes := transmute([]u8)view.query
		for end > 0 && bytes[end] & 0xc0 == 0x80 do end -= 1
		_, queried, query_failure := interaction.candidate_session_set_query(
			&commands.candidate_ui.session, request, view.query[:end])
		if !queried do command_context_candidate_failure_diagnostic(commands, "Result query", query_failure)
		if queried do command_context_sync_result_selection(commands)
		return Interaction_Result{changed = true}, {}
	}
	if contextual_route == .Component_Activate_Current {
		if !view.has_selection || len(view.rows) == 0 do return {}, {}
		if !command_context_visit_result(commands, view.rows[view.selected_row].action) {
			command_context_set_diagnostic(commands, "Result location is stale")
			return Interaction_Result{changed = true}, {}
		}
		return command_context_leave_results(commands, false)
	}
	if contextual_route == .Result_Refresh {
		return command_context_refresh_results(commands)
	}
	if contextual_route == .Result_Edit {
		return command_context_begin_result_edit(commands, view)
	}
	if contextual_route == .Result_Apply {
		return command_context_apply_result_edits(commands)
	}
	if command_metadata_is_native(metadata, .Keyboard_Quit) && command_context_result_edits_dirty(commands) {
		command_context_discard_result_edits(commands)
		command_context_set_diagnostic(commands, "Result edits discarded")
		return Interaction_Result{changed = true}, {}
	}
	if contextual_route == .Component_Close || command_metadata_is_native(metadata, .Keyboard_Quit) {
		return command_context_leave_results(commands, true)
	}
	return {}, {}
}

@(private)
command_context_sync_result_selection :: proc(commands: ^Command_Context) {
	view, viewed, _ := interaction.candidate_session_view(&commands.candidate_ui.session)
	if !viewed || !view.has_selection || len(view.rows) == 0 do return
	action := view.rows[view.selected_row].action
	if action.kind != .Visit_Result do return
	registry, registry_ok, _ := editor_session.session_result_registry(commands.session_owner, commands.session_handle)
	if !registry_ok do return
	_, _, _ = result_set.registry_select(registry, result_set.Result_Set_ID(action.primary),
		result_set.Result_Set_Generation(action.owner_generation), result_set.Location_ID(action.secondary))
}

@(private)
command_context_begin_result_edit :: proc(
	commands: ^Command_Context,
	candidate_view: interaction.Candidate_View,
) -> (Interaction_Result, App_Failure) {
	if !candidate_view.has_selection || len(candidate_view.rows) == 0 {
		command_context_set_diagnostic(commands, "No selected result")
		return Interaction_Result{changed = true}, {}
	}
	action := candidate_view.rows[candidate_view.selected_row].action
	if action.kind != .Visit_Result {
		return {}, App_Failure{stage = .Component_Access}
	}
	registry, registry_ok, registry_failure := editor_session.session_result_registry(
		commands.session_owner, commands.session_handle)
	if !registry_ok do return {}, App_Failure{stage = .Session_Access, editor_session = registry_failure}
	set_view, viewed, _ := result_set.registry_view(registry, result_set.Result_Set_ID(action.primary))
	if !viewed || u64(set_view.generation) != action.owner_generation ||
	   set_view.edit_capability == .Read_Only || set_view.edit_capability == .Invalid {
		command_context_set_diagnostic(commands, "This result set is read-only")
		return Interaction_Result{changed = true}, {}
	}
	location, found := result_workflow_location(set_view, result_set.Location_ID(action.secondary))
	if !found || u64(location.end - location.start) > interaction.MAX_PROMPT_TEXT_BYTES {
		command_context_set_diagnostic(commands, "Selected result is not editable")
		return Interaction_Result{changed = true}, {}
	}
	inspection, projection_active := result_set.edit_projection_inspect(&commands.result_workflow.projection)
	if !projection_active {
		began, _ := result_set.edit_projection_begin(
			&commands.result_workflow.projection, set_view, commands.persistent_allocator)
		if !began {
			command_context_set_diagnostic(commands, "Editable result projection is unavailable")
			return Interaction_Result{changed = true}, {}
		}
		commands.result_workflow.set_id = set_view.set_id
		commands.result_workflow.generation = set_view.generation
	} else if inspection.set_id != set_view.set_id || inspection.generation != set_view.generation {
		command_context_set_diagnostic(commands, "Finish staged result edits before changing sets")
		return Interaction_Result{changed = true}, {}
	}
	access, accessible, access_failure := editor_session.session_entry_access(
		commands.session_owner, commands.candidate_ui.return_target.entry)
	if !accessible do return {}, App_Failure{stage = .Session_Access, editor_session = access_failure}
	entry, borrowed, borrow_failure := editor_session.entry_access_borrow(access)
	if !borrowed do return {}, App_Failure{stage = .Session_Access, editor_session = borrow_failure}
	stats, stats_ok, _ := editor.buffer_stats(entry.buffer)
	if !stats_ok || stats.buffer_id != location.buffer_id || stats.revision != location.revision {
		command_context_set_diagnostic(commands, "Result location is stale")
		return Interaction_Result{changed = true}, {}
	}
	text_storage: [4_096]byte
	copied, copied_ok, _ := editor.buffer_inspect(entry.buffer, location.start, location.end, text_storage[:])
	if !copied_ok {
		command_context_set_diagnostic(commands, "Result text is unavailable")
		return Interaction_Result{changed = true}, {}
	}
	prompt_ok, prompt_failure := interaction.prompt_init(&commands.prompt_workflow.prompt,
		interaction.Prompt_Config{kind = .Text_Entry, text_bytes_limit = interaction.MAX_PROMPT_TEXT_BYTES,
			allow_empty = true, allocator = commands.persistent_allocator})
	if !prompt_ok do return {}, App_Failure{stage = .Prompt, prompt_failure = prompt_failure}
	_, prompt_failure = interaction.prompt_text_replace(&commands.prompt_workflow.prompt,
		string(text_storage[:int(copied)]))
	if prompt_failure.code != .None {
		_, _ = interaction.prompt_close(&commands.prompt_workflow.prompt)
		return {}, App_Failure{stage = .Prompt, prompt_failure = prompt_failure}
	}
	if !prompt_workflow_begin_projection(&commands.prompt_workflow, .Result_Edit) {
		_, _ = interaction.prompt_close(&commands.prompt_workflow.prompt)
		return {}, App_Failure{stage = .UI, ui = {operation = .Prepare, code = .Generation_Limit}}
	}
	if map_failure := command_context_activate_prompt_map(commands, .Result_Edit); map_failure.stage != .None {
		command_context_end_prompt(commands)
		return {}, map_failure
	}
	commands.result_workflow.location_id = location.id
	return Interaction_Result{changed = true}, {}
}

@(private)
dispatch_result_edit_prompt :: proc(
	commands: ^Command_Context,
	input: interaction.Input,
) -> (Interaction_Result, App_Failure) {
	metadata, resolution, resolved, resolve_failure := command_context_resolve_prompt_input(commands, input)
	if !resolved do return {}, resolve_failure
	if resolution.kind != .Command do return {}, {}
	if command_metadata_is_cancel(metadata) {
		_, _ = interaction.prompt_cancel(&commands.prompt_workflow.prompt)
		command_context_end_prompt(commands)
		commands.result_workflow.location_id = {}
		return Interaction_Result{changed = true}, {}
	}
	if command_metadata_is_contextual(metadata, .Prompt_Delete_Previous) {
		transition, prompt_failure := interaction.prompt_text_delete_previous(&commands.prompt_workflow.prompt)
		if prompt_failure.code != .None do return {}, App_Failure{stage = .Prompt, prompt_failure = prompt_failure}
		commands.prompt_workflow.rejected = false
		return Interaction_Result{changed = transition == .Changed}, {}
	}
	if command_metadata_is_contextual(metadata, .Prompt_Insert_Text) {
		transition, prompt_failure := interaction.prompt_text_append(&commands.prompt_workflow.prompt, resolution.text)
		if prompt_failure.code == .Text_Limit || prompt_failure.code == .Malformed_UTF8 {
			commands.prompt_workflow.rejected = true
			return Interaction_Result{changed = true}, {}
		}
		if prompt_failure.code != .None do return {}, App_Failure{stage = .Prompt, prompt_failure = prompt_failure}
		commands.prompt_workflow.rejected = false
		return Interaction_Result{changed = transition == .Changed}, {}
	}
	if !command_metadata_is_contextual(metadata, .Prompt_Accept) do return {}, {}
	_, accept_failure := interaction.prompt_text_accept(&commands.prompt_workflow.prompt)
	if accept_failure.code != .None {
		commands.prompt_workflow.rejected = true
		return Interaction_Result{changed = true}, {}
	}
	prompt_view, viewed, view_failure := interaction.prompt_view(&commands.prompt_workflow.prompt)
	if !viewed do return {}, App_Failure{stage = .Prompt, prompt_failure = view_failure}
	staged, _ := result_set.edit_projection_stage(&commands.result_workflow.projection,
		commands.result_workflow.location_id, prompt_view.text)
	command_context_end_prompt(commands)
	commands.result_workflow.location_id = {}
	if !staged {
		command_context_set_diagnostic(commands, "Result edit could not be staged")
		return Interaction_Result{changed = true}, {}
	}
	command_context_set_diagnostic(commands, "Result edit staged")
	return Interaction_Result{changed = true}, {}
}

@(private)
command_context_apply_result_edits :: proc(commands: ^Command_Context) -> (Interaction_Result, App_Failure) {
	inspection, active := result_set.edit_projection_inspect(&commands.result_workflow.projection)
	if !active || !inspection.dirty {
		command_context_set_diagnostic(commands, "No staged result edits")
		return Interaction_Result{changed = true}, {}
	}
	if commands.next_transaction_id == 0 || commands.next_undo_unit_id == 0 {
		return {}, App_Failure{stage = .Command_Dispatch}
	}
	access, accessible, access_failure := editor_session.session_entry_access(
		commands.session_owner, commands.candidate_ui.return_target.entry)
	if !accessible do return {}, App_Failure{stage = .Session_Access, editor_session = access_failure}
	entry, borrowed, borrow_failure := editor_session.entry_access_borrow(access)
	if !borrowed do return {}, App_Failure{stage = .Session_Access, editor_session = borrow_failure}
	targets := []result_set.Edit_Target{{buffer = entry.buffer, history = entry.history_store}}
	transaction_id := edit_transaction.Transaction_ID(commands.next_transaction_id)
	undo_unit_id := edit_transaction.Undo_Unit_ID(commands.next_undo_unit_id)
	result, applied, _ := result_set.edit_projection_apply(&commands.result_workflow.projection,
		targets, transaction_id, undo_unit_id,
		edit_transaction.Allocator_Set{persistent = commands.persistent_allocator,
			temporary = commands.temporary_allocator})
	if !applied {
		command_context_set_diagnostic(commands, "Result edits could not be applied")
		return Interaction_Result{changed = true}, {}
	}
	commands.next_transaction_id += 1
	commands.next_undo_unit_id += 1
	_, _ = result_set.edit_projection_close(&commands.result_workflow.projection)
	commands.result_workflow = {}
	command_context_set_diagnostic(commands, "Result edits applied")
	_ = result
	return command_context_leave_results(commands, true)
}

@(private)
command_context_result_edits_dirty :: proc(commands: ^Command_Context) -> bool {
	inspection, active := result_set.edit_projection_inspect(&commands.result_workflow.projection)
	return active && inspection.dirty
}

@(private)
command_context_discard_result_edits :: proc(commands: ^Command_Context) {
	if _, active := result_set.edit_projection_inspect(&commands.result_workflow.projection); active {
		_, _ = result_set.edit_projection_close(&commands.result_workflow.projection, true)
	}
	commands.result_workflow = {}
}

@(private)
result_workflow_location :: proc(view: result_set.View, id: result_set.Location_ID) -> (result_set.Location, bool) {
	for location in view.locations do if location.id == id do return location, true
	return {}, false
}

@(private)
command_context_visit_result :: proc(commands: ^Command_Context, action: interaction.Candidate_Action) -> bool {
	if action.kind != .Visit_Result || commands.candidate_ui.return_target.kind != .Primary_View do return false
	previous, previous_ok := command_context_named_location_return_state(
		commands,
		commands.candidate_ui.return_target,
	)
	registry, registry_ok, _ := editor_session.session_result_registry(commands.session_owner, commands.session_handle)
	if !registry_ok do return false
	view, viewed, _ := result_set.registry_view(registry, result_set.Result_Set_ID(action.primary))
	if !viewed || u64(view.generation) != action.owner_generation do return false
	location_index := -1
	for location, index in view.locations do if u64(location.id) == action.secondary do location_index = index
	if location_index < 0 do return false
	location := view.locations[location_index]
	if view.source.kind == .Project_Search {
		return command_context_visit_project_search_location(
			commands, location, commands.candidate_ui.return_target,
		)
	}
	access, accessible, _ := editor_session.session_entry_access(commands.session_owner,
		commands.candidate_ui.return_target.entry)
	if !accessible do return false
	entry, borrowed, _ := editor_session.entry_access_borrow(access)
	if !borrowed do return false
	stats, stats_ok, _ := editor.buffer_stats(entry.buffer)
	if !stats_ok || stats.buffer_id != location.buffer_id || stats.revision != location.revision ||
	   u64(location.start) > stats.text_bytes {
		return false
	}
	position, positioned, _ := editor.buffer_position(entry.buffer, location.start)
	if !positioned do return false
	_, activated, _ := editor_session.session_activate(commands.session_owner,
		commands.candidate_ui.return_target.entry)
	if !activated do return false
	moved, _ := editor_view.set_point(entry.view_registry, entry.primary_view, position)
	if moved && previous_ok && commands.location_history != nil {
		_ = command.location_history_push(commands.location_history, previous)
	}
	return moved
}

@(private)
command_context_refresh_results :: proc(commands: ^Command_Context) -> (Interaction_Result, App_Failure) {
	if command_context_result_edits_dirty(commands) {
		command_context_set_diagnostic(commands, "Apply or discard staged result edits before refreshing")
		return Interaction_Result{changed = true}, {}
	}
	command_context_discard_result_edits(commands)
	candidate_view, candidate_viewed, candidate_failure := interaction.candidate_session_view(
		&commands.candidate_ui.session)
	if !candidate_viewed {
		return {}, App_Failure{stage = .Component_Access, candidate = candidate_failure}
	}
	registry, registry_ok, registry_failure := editor_session.session_result_registry(
		commands.session_owner, commands.session_handle)
	if !registry_ok do return {}, App_Failure{stage = .Session_Access, editor_session = registry_failure}
	current, current_ok, _ := result_set.registry_view(
		registry, result_set.Result_Set_ID(candidate_view.scope_identity))
	if !current_ok do return Interaction_Result{changed = true}, {}
	if current.source.kind == .Language_Symbols {
		return command_context_refresh_symbol_results(commands, current)
	}
	if current.source.kind == .Project_Search {
		return command_context_refresh_project_search_results(commands, current)
	}
	if commands.candidate_ui.return_target.kind != .Primary_View do return {}, App_Failure{stage = .Session_Access}
	access, accessible, access_failure := editor_session.session_entry_access(
		commands.session_owner, commands.candidate_ui.return_target.entry)
	if !accessible do return {}, App_Failure{stage = .Session_Access, editor_session = access_failure}
	entry, borrowed, borrow_failure := editor_session.entry_access_borrow(access)
	if !borrowed do return {}, App_Failure{stage = .Session_Access, editor_session = borrow_failure}
	snapshot, search_ok, _ := editor_view.search_session_view(entry.view_registry, entry.primary_view)
	if !search_ok || !snapshot.present {
		command_context_set_diagnostic(commands, "Result source is no longer available")
		return Interaction_Result{changed = true}, {}
	}
	if current.source.kind != .Active_Search {
		command_context_set_diagnostic(commands, "Result source cannot be refreshed")
		return Interaction_Result{changed = true}, {}
	}
	_, refreshed, _ := result_set.search_materialize(registry, snapshot,
		result_set.Search_Materialization_Config{set_id = 1,
			expected_generation = current.generation, source_id = 1,
			buffer = entry.buffer,
			allocator = commands.temporary_allocator})
	if !refreshed {
		command_context_set_diagnostic(commands, "Result refresh was rejected")
		return Interaction_Result{changed = true}, {}
	}
	updated, _, _ := result_set.registry_view(registry, 1)
	source_generation := commands.candidate_ui.next_source_generation
	source, built, source_failure := interaction.result_candidate_source_build(
		updated, source_generation, commands.temporary_allocator)
	if !built do return {}, App_Failure{stage = .Component_Access, candidate = source_failure}
	defer interaction.result_candidate_source_close(&source)
	view, _, _ := interaction.candidate_session_view(&commands.candidate_ui.session)
	_, candidate_refreshed, candidate_refresh_failure := interaction.candidate_session_refresh(
		&commands.candidate_ui.session,
		{session_id = view.session_id, session_generation = view.session_generation},
		source.definition)
	if !candidate_refreshed do return {}, App_Failure{stage = .Component_Access, candidate = candidate_refresh_failure}
	commands.candidate_ui.next_source_generation = source_generation + 1
	command_context_sync_result_selection(commands)
	return Interaction_Result{changed = true}, {}
}

@(private)
command_context_leave_results :: proc(commands: ^Command_Context, close_set: bool) -> (Interaction_Result, App_Failure) {
	if command_context_result_edits_dirty(commands) {
		command_context_set_diagnostic(commands, "Apply or discard staged result edits before closing")
		return Interaction_Result{changed = true}, {}
	}
	command_context_deactivate_context_map(commands, .Completed)
	view, viewed, view_failure := interaction.candidate_session_view(&commands.candidate_ui.session)
	if !viewed do return {}, App_Failure{stage = .Component_Access, candidate = view_failure}
	if close_set {
		registry, registry_ok, registry_failure := editor_session.session_result_registry(
			commands.session_owner, commands.session_handle)
		if !registry_ok do return {}, App_Failure{stage = .Session_Access, editor_session = registry_failure}
		set_id := result_set.Result_Set_ID(view.scope_identity)
		generation := result_set.Result_Set_Generation(view.scope_generation)
		_, _, _ = result_set.registry_close_set(registry, set_id, generation)
		_, _ = editor_session.session_result_source_clear(
			commands.session_owner, commands.session_handle, set_id, generation)
	}
	command_context_discard_result_edits(commands)
	return_target := commands.candidate_ui.return_target
	if commands.candidate_ui.session.state != nil do _, _, _ = interaction.candidate_session_close(&commands.candidate_ui.session)
	commands.candidate_ui.return_target = {}
	if return_target.kind != .Primary_View do return {}, App_Failure{stage = .Session_Access}
	access, accessible, access_failure := editor_session.session_entry_access(
		commands.session_owner, return_target.entry)
	if !accessible do return {}, App_Failure{stage = .Session_Access, editor_session = access_failure}
	entry, borrowed, borrow_failure := editor_session.entry_access_borrow(access)
	if !borrowed do return {}, App_Failure{stage = .Session_Access, editor_session = borrow_failure}
	transient, transient_ok, transient_failure := editor_view.transient_state(
		entry.view_registry, entry.primary_view)
	if !transient_ok {
		return {}, App_Failure{stage = .View_Snapshot, view = transient_failure}
	}
	if transient.search {
		accepted, accept_failure := command.incremental_search_accept(
			entry.view_registry, entry.primary_view)
		if !accepted do return {}, App_Failure{stage = .Command_Dispatch, command = accept_failure}
	}
	_, activated, activation_failure := editor_session.session_activate(commands.session_owner, return_target.entry)
	if !activated do return {}, App_Failure{stage = .Session_Access, editor_session = activation_failure}
	return Interaction_Result{changed = true}, {}
}

@(private)
command_context_move_active_location :: proc(
	commands: ^Command_Context,
	forward: bool,
) -> (Interaction_Result, App_Failure) {
	previous, previous_ok := command_context_named_location_return_state(
		commands,
		editor_session.Visible_Target{kind = .Primary_View, entry = commands.current_entry},
	)
	source, source_ok, _ := editor_session.session_active_location_source(
		commands.session_owner, commands.session_handle,
	)
	movement := result_set.Movement.Previous
	if forward do movement = .Next
	_, location, moved, move_failure := editor_session.session_result_source_move(
		commands.session_owner, commands.session_handle, movement)
	if !moved {
		command_context_set_diagnostic(commands, "No active location source")
		_ = move_failure
		return Interaction_Result{changed = true}, {}
	}
	if source_ok && source.source.kind == .Project_Search {
		if !command_context_move_project_search_location(
			commands,
			location,
			{kind = .Primary_View, entry = commands.current_entry},
		) {
			command_context_set_diagnostic(commands, "Location target is stale")
		}
		return Interaction_Result{changed = true}, {}
	}
	entry_handle, found, _ := editor_session.session_entry_for_buffer(
		commands.session_owner, commands.session_handle, location.buffer_id)
	if !found {
		command_context_set_diagnostic(commands, "Location target is no longer open")
		return Interaction_Result{changed = true}, {}
	}
	access, accessible, _ := editor_session.session_entry_access(commands.session_owner, entry_handle)
	if !accessible do return {}, App_Failure{stage = .Session_Access}
	entry, borrowed, _ := editor_session.entry_access_borrow(access)
	if !borrowed do return {}, App_Failure{stage = .Session_Access}
	stats, stats_ok, _ := editor.buffer_stats(entry.buffer)
	if !stats_ok || stats.revision != location.revision || u64(location.start) > stats.text_bytes {
		command_context_set_diagnostic(commands, "Location target is stale")
		return Interaction_Result{changed = true}, {}
	}
	position, positioned, _ := editor.buffer_position(entry.buffer, location.start)
	if !positioned do return {}, App_Failure{stage = .Component_Access}
	_, activated, activation_failure := editor_session.session_activate(commands.session_owner, entry_handle)
	if !activated do return {}, App_Failure{stage = .Session_Access, editor_session = activation_failure}
	point_moved, _ := editor_view.set_point(entry.view_registry, entry.primary_view, position)
	if !point_moved do return {}, App_Failure{stage = .Component_Access}
	if previous_ok && commands.location_history != nil {
		_ = command.location_history_push(commands.location_history, previous)
	}
	return Interaction_Result{changed = true}, {}
}
