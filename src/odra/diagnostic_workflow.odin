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
import editor_view "../view"

@(private)
command_context_present_language_diagnostics :: proc(
	commands: ^Command_Context,
) -> (Interaction_Result, App_Failure) {
	visible, visible_ok, visible_failure := editor_session.session_visible_target(
		commands.session_owner,
		commands.session_handle,
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
	source, built, source_failure := language_service_workflow_diagnostic_source(
		commands.language_service_workflow,
		source_generation,
		commands.temporary_allocator,
	)
	if !built {
		command_context_set_diagnostic(commands, "No current language diagnostics")
		_ = source_failure
		return Interaction_Result{changed = true}, {}
	}
	defer language_service_diagnostic_source_close(&source)
	if len(source.source.definition.descriptors) == 0 {
		command_context_set_diagnostic(commands, "No current language diagnostics")
		return Interaction_Result{changed = true}, {}
	}
	if !command_context_publish_diagnostic_results(commands, source.source) {
		command_context_set_diagnostic(commands, "Language diagnostics could not be published")
		return Interaction_Result{changed = true}, {}
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
		source.source.definition,
	)
	if !initialized {
		command_context_candidate_failure_diagnostic(
			commands,
			"Language diagnostic candidates",
			initialization_failure,
		)
		return Interaction_Result{changed = true}, {}
	}
	keep_session := false
	defer if !keep_session do _, _, _ = interaction.candidate_session_close(&candidate_session)
	if commands.candidate_ui.catalog.state != nil {
		interaction.command_catalog_close(&commands.candidate_ui.catalog)
	}
	if commands.candidate_ui.session.state != nil {
		_, _, _ = interaction.candidate_session_close(&commands.candidate_ui.session)
	}
	commands.candidate_ui.session = candidate_session
	commands.candidate_ui.return_target = visible
	commands.candidate_ui.next_session_id = session_id + 1
	commands.candidate_ui.next_source_generation = source_generation + 1
	keep_session = true
	target := candidate_ui_visible_target()
	_, _, presented, present_failure := editor_session.session_present_ui(
		commands.session_owner,
		commands.session_handle,
		target.ui,
	)
	if !presented {
		return {}, App_Failure{stage = .Session_Access, editor_session = present_failure}
	}
	commands.pending = {}
	return Interaction_Result{changed = true}, {}
}

@(private)
dispatch_language_diagnostic_input :: proc(
	commands: ^Command_Context,
	input: interaction.Input,
) -> (Interaction_Result, App_Failure) {
	view, viewed, view_failure := interaction.candidate_session_view(&commands.candidate_ui.session)
	if !viewed || view.source_kind != .Language_Diagnostics {
		return {}, App_Failure{stage = .Component_Access, candidate = view_failure}
	}
	if map_failure := command_context_sync_candidate_map(commands, .Language_Diagnostics);
	   map_failure.stage != .None {
		return {}, map_failure
	}
	metadata, resolution, resolved, resolution_failure := command_context_resolve_context_input(
		commands,
		input,
	)
	if !resolved do return {}, resolution_failure
	if resolution.kind != .Command do return {}, {}
	request := interaction.Candidate_Request {
		session_id = view.session_id,
		session_generation = view.session_generation,
	}
	contextual_route, contextual_ok := command.contextual_route_decode(metadata.route)
	if contextual_ok &&
	   (contextual_route == .Component_Previous_Row || contextual_route == .Component_Next_Row) {
		if len(view.rows) == 0 do return {}, {}
		delta := i32(1)
		if contextual_route == .Component_Previous_Row do delta = -1
		_, moved, move_failure := interaction.candidate_session_move(
			&commands.candidate_ui.session,
			request,
			delta,
		)
		if !moved {
			command_context_candidate_failure_diagnostic(commands, "Diagnostic candidate movement", move_failure)
		}
		return Interaction_Result{changed = true}, {}
	}
	if contextual_route == .Component_Query_Text {
		if len(resolution.text) == 0 do return {}, {}
		if len(view.query) + len(resolution.text) > int(interaction.MAX_CANDIDATE_QUERY_BYTES) {
			command_context_set_diagnostic(commands, "Diagnostic query limit reached")
			return Interaction_Result{changed = true}, {}
		}
		query: [interaction.MAX_CANDIDATE_QUERY_BYTES]u8
		copy(query[:], transmute([]u8)view.query)
		copy(query[len(view.query):], transmute([]u8)resolution.text)
		return command_context_refresh_language_diagnostics(
			commands,
			string(query[:len(view.query) + len(resolution.text)]),
		)
	}
	if contextual_route == .Component_Query_Delete_Previous {
		if len(view.query) == 0 do return {}, {}
		end := len(view.query) - 1
		bytes := transmute([]u8)view.query
		for end > 0 && bytes[end] & 0xc0 == 0x80 do end -= 1
		return command_context_refresh_language_diagnostics(commands, view.query[:end])
	}
	if contextual_route == .Component_Activate_Current {
		if !view.has_selection || len(view.rows) == 0 do return {}, {}
		row := view.rows[view.selected_row]
		if !command_context_navigate_language_diagnostic(commands, row.action) {
			command_context_set_diagnostic(commands, "Language diagnostic changed; refresh or reopen the list")
			return Interaction_Result{changed = true}, {}
		}
		_, recorded, record_failure := interaction.candidate_session_record_success(
			&commands.candidate_ui.session,
			request,
			row.identity,
		)
		command_context_deactivate_context_map(commands, .Completed)
		command_context_close_language_diagnostics(commands)
		if !recorded {
			command_context_candidate_failure_diagnostic(commands, "Diagnostic candidate recency", record_failure)
		}
		return Interaction_Result{changed = true}, {}
	}
	if contextual_route == .Component_Close || command_metadata_is_native(metadata, .Keyboard_Quit) {
		return command_context_leave_language_diagnostics(commands)
	}
	return {}, {}
}

@(private)
command_context_select_diagnostic_result :: proc(
	commands: ^Command_Context,
	action: interaction.Candidate_Action,
) {
	if action.kind != .Navigate_Diagnostic do return
	registry, registry_ok, _ := editor_session.session_result_registry(
		commands.session_owner, commands.session_handle)
	if !registry_ok do return
	view, viewed, _ := result_set.registry_view(registry, 2)
	if !viewed do return
	identity := (action.graph_identity[0] << 32) | action.graph_identity[3]
	if identity == 0 do return
	_, _, _ = result_set.registry_select(
		registry, view.set_id, view.generation, result_set.Location_ID(identity))
}

@(private)
command_context_refresh_language_diagnostics :: proc(
	commands: ^Command_Context,
	query: string,
) -> (Interaction_Result, App_Failure) {
	view, viewed, view_failure := interaction.candidate_session_view(&commands.candidate_ui.session)
	if !viewed || view.source_kind != .Language_Diagnostics {
		return {}, App_Failure{stage = .Component_Access, candidate = view_failure}
	}
	source_generation := commands.candidate_ui.next_source_generation
	source, built, source_failure := language_service_workflow_diagnostic_source(
		commands.language_service_workflow,
		source_generation,
		commands.temporary_allocator,
	)
	if !built {
		command_context_set_diagnostic(commands, "No current language diagnostics")
		_ = source_failure
		return Interaction_Result{changed = true}, {}
	}
	defer language_service_diagnostic_source_close(&source)
	request := interaction.Candidate_Request {
		session_id = view.session_id,
		session_generation = view.session_generation,
	}
	_, refreshed, refresh_failure := interaction.candidate_session_refresh(
		&commands.candidate_ui.session,
		request,
		source.source.definition,
	)
	if !refreshed {
		command_context_candidate_failure_diagnostic(commands, "Diagnostic candidate refresh", refresh_failure)
		return Interaction_Result{changed = true}, {}
	}
	commands.candidate_ui.next_source_generation = source_generation + 1
	view, viewed, view_failure = interaction.candidate_session_view(&commands.candidate_ui.session)
	if !viewed do return {}, App_Failure{stage = .Component_Access, candidate = view_failure}
	_, queried, query_failure := interaction.candidate_session_set_query(
		&commands.candidate_ui.session,
		interaction.Candidate_Request {
			session_id = view.session_id,
			session_generation = view.session_generation,
		},
		query,
	)
	if !queried {
		command_context_candidate_failure_diagnostic(commands, "Diagnostic candidate query", query_failure)
	}
	commands.diagnostic_length = 0
	return Interaction_Result{changed = true}, {}
}

@(private)
command_context_move_language_diagnostic :: proc(
	commands: ^Command_Context,
	buffer: ^editor.Buffer,
	views: ^editor_view.Registry,
	view: editor_view.View_Handle,
	forward: bool,
) -> (Interaction_Result, App_Failure) {
	_ = buffer
	_ = views
	_ = view
	source_generation := commands.candidate_ui.next_source_generation
	source, built, _ := language_service_workflow_diagnostic_source(
		commands.language_service_workflow,
		source_generation,
		commands.temporary_allocator,
	)
	if !built {
		command_context_set_diagnostic(commands, "No current language diagnostics")
		return Interaction_Result{changed = true}, {}
	}
	defer language_service_diagnostic_source_close(&source)
	if len(source.source.locations) == 0 {
		command_context_set_diagnostic(commands, "No current language diagnostics")
		return Interaction_Result{changed = true}, {}
	}
	commands.candidate_ui.next_source_generation = source_generation + 1
	if !command_context_publish_diagnostic_results(commands, source.source) {
		command_context_set_diagnostic(commands, "Language diagnostics could not be published")
		return Interaction_Result{changed = true}, {}
	}
	return command_context_move_active_location(commands, forward)
}

@(private)
command_context_publish_diagnostic_results :: proc(
	commands: ^Command_Context,
	source: interaction.Diagnostic_Candidate_Source,
) -> bool {
	registry, registry_ok, _ := editor_session.session_result_registry(
		commands.session_owner, commands.session_handle)
	if !registry_ok do return false
	expected := result_set.Result_Set_Generation(0)
	if current, present, _ := result_set.registry_view(registry, 2); present do expected = current.generation
	definitions, allocation_error := make(
		[]result_set.Location_Definition,
		len(source.locations),
		commands.temporary_allocator,
	)
	if allocation_error != nil do return false
	defer delete(definitions, commands.temporary_allocator)
	for location, index in source.locations {
		descriptor := source.definition.descriptors[index]
		identity := (u64(location.binding.id) << 32) | u64(location.diagnostic_id)
		if identity == 0 do identity = u64(index + 1)
		definitions[index] = {
			id = result_set.Location_ID(identity),
			buffer_id = editor.Buffer_ID(location.buffer_id),
			revision = editor.Revision(location.canonical_revision),
			start = editor.Byte_Offset(location.start),
			end = editor.Byte_Offset(location.end),
			source_identity = identity,
			preview = descriptor.label,
			annotation = location.path,
		}
	}
	_, published, _ := result_set.registry_publish(registry, result_set.Publication {
		set_id = 2,
		expected_generation = expected,
		source = {id = 2, generation = result_set.Source_Generation(source.definition.source_generation),
			kind = .Language_Diagnostics},
		metadata = {descriptor = "Language diagnostics"},
		completeness = .Complete,
		refresh = {provider = 2, query_identity = source.definition.scope_identity,
			scope_generation = source.definition.scope_generation},
		edit_capability = .Read_Only,
		locations = definitions,
	})
	if !published do return false
	_, activated, _ := editor_session.session_result_source_activate(
		commands.session_owner, commands.session_handle, 2)
	return activated
}

@(private)
command_context_navigate_language_diagnostic :: proc(
	commands: ^Command_Context,
	action: interaction.Candidate_Action,
) -> bool {
	entry_handle, start, resolved := language_service_workflow_resolve_diagnostic_action(
		commands.language_service_workflow,
		action,
	)
	if !resolved do return false
	access, accessible, _ := editor_session.session_entry_access(commands.session_owner, entry_handle)
	if !accessible do return false
	entry, borrowed, _ := editor_session.entry_access_borrow(access)
	if !borrowed do return false
	stats, stats_ok, _ := editor.buffer_stats(entry.buffer)
	if !stats_ok || u64(stats.revision) != action.secondary || start > stats.text_bytes do return false
	position, positioned, _ := editor.buffer_position(entry.buffer, editor.Byte_Offset(start))
	if !positioned do return false
	_, activated, _ := editor_session.session_activate(commands.session_owner, entry_handle)
	if !activated do return false
	moved, _ := editor_view.set_point(entry.view_registry, entry.primary_view, position)
	if moved do command_context_select_diagnostic_result(commands, action)
	return moved
}

@(private)
command_context_leave_language_diagnostics :: proc(
	commands: ^Command_Context,
) -> (Interaction_Result, App_Failure) {
	command_context_deactivate_context_map(commands, .Completed)
	view, viewed, view_failure := interaction.candidate_session_view(&commands.candidate_ui.session)
	if !viewed do return {}, App_Failure{stage = .Component_Access, candidate = view_failure}
	_, cancelled, cancel_failure := interaction.candidate_session_cancel(
		&commands.candidate_ui.session,
		interaction.Candidate_Request {
			session_id = view.session_id,
			session_generation = view.session_generation,
		},
	)
	if !cancelled do return {}, App_Failure{stage = .Component_Access, candidate = cancel_failure}
	return_target := commands.candidate_ui.return_target
	defer command_context_close_language_diagnostics(commands)
	commands.diagnostic_length = 0
	if return_target.kind != .Primary_View do return {}, App_Failure{stage = .Session_Access}
	_, activated, activation_failure := editor_session.session_activate(
		commands.session_owner,
		return_target.entry,
	)
	if !activated {
		return {}, App_Failure{stage = .Session_Access, editor_session = activation_failure}
	}
	return Interaction_Result{changed = true}, {}
}

@(private)
command_context_close_language_diagnostics :: proc(commands: ^Command_Context) {
	if commands.candidate_ui.session.state != nil {
		_, _, _ = interaction.candidate_session_close(&commands.candidate_ui.session)
	}
	commands.candidate_ui.return_target = {}
}
