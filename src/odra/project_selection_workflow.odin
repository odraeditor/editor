// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../command"
import "../display"
import "../document"
import "../editor_session"
import "../interaction"
import "../project"

@(private)
command_context_present_project_navigation :: proc(
	commands: ^Command_Context,
	purpose: Project_Selection_Purpose = .Open,
) -> (Interaction_Result, App_Failure) {
	if commands == nil || commands.racket_runtime == nil ||
	   len(commands.project_catalog_root) == 0 {
		return {}, App_Failure{stage = .Component_Access}
	}
	visible, visible_ok, visible_failure := editor_session.session_visible_target(
		commands.session_owner,
		commands.session_handle,
	)
	if !visible_ok {
		return {}, App_Failure{stage = .Session_Access, editor_session = visible_failure}
	}
	listed, listed_ok, list_failure := command.project_catalog_candidates_resolve(
		commands.racket_runtime,
		commands.project_catalog_root,
		commands.persistent_allocator,
	)
	if !listed_ok {
		command_context_set_diagnostic(commands, list_failure.diagnostic)
		return Interaction_Result{changed = true}, {}
	}
	keep_batch := false
	defer if !keep_batch do command.project_directory_candidate_batch_close(&listed)

	fields: [project.DEFAULT_CATALOG_PROJECTS][2]string
	annotations: [project.DEFAULT_CATALOG_PROJECTS][1]interaction.Candidate_Annotation_Definition
	descriptors: [project.DEFAULT_CATALOG_PROJECTS]interaction.Candidate_Descriptor_Definition
	if len(listed.candidates) > len(descriptors) {
		return {}, App_Failure{stage = .Component_Access}
	}
	source_generation := commands.candidate_ui.next_source_generation
	session_id := commands.candidate_ui.next_session_id
	if source_generation == 0 || source_generation == max(u64) ||
	   session_id == 0 || session_id == max(u64) {
		return {}, App_Failure{stage = .Component_Access}
	}
	for candidate, index in listed.candidates {
		fields[index] = {candidate.durable_id, candidate.path}
		annotations[index] = {{kind = .Project_Member, text = candidate.path}}
		descriptors[index] = interaction.Candidate_Descriptor_Definition {
			identity = {
				kind = 11,
				primary = u64(index + 1),
				secondary = u64(candidate.project_generation),
			},
			label = candidate.name,
			searchable_fields = fields[index][:],
			annotations = annotations[index][:],
			action = {
				kind = .Open_Project,
				owner_generation = source_generation,
				primary = u64(index + 1),
				secondary = u64(candidate.project_generation),
			},
			availability = .Available,
			durable_category = .Project,
			durable_key = candidate.durable_id,
		}
	}
	source_definition := interaction.Candidate_Source_Definition {
		kind = .Projects,
		scope_identity = 1,
		scope_generation = max(listed.catalog_generation, 1),
		source_generation = source_generation,
		descriptors = descriptors[:len(listed.candidates)],
	}
	command_context_global_candidate_history_rank_source(commands, &source_definition)
	candidate_session: interaction.Candidate_Session
	_, initialized, candidate_failure := interaction.candidate_session_init(
		&candidate_session,
		interaction.Candidate_Config {
			session_id = interaction.Candidate_Session_ID(session_id),
			limits = interaction.DEFAULT_CANDIDATE_LIMITS,
			persistent_allocator = commands.persistent_allocator,
			temporary_allocator = commands.temporary_allocator,
		},
		source_definition,
	)
	if !initialized {
		command_context_candidate_failure_diagnostic(commands, "Project candidate session", candidate_failure)
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
	if commands.project_workflow.selection_candidates.state != nil {
		command.project_directory_candidate_batch_close(
			&commands.project_workflow.selection_candidates,
		)
	}
	commands.project_workflow.selection_candidates = listed
	commands.project_workflow.selection_purpose = purpose
	commands.candidate_ui.session = candidate_session
	commands.candidate_ui.return_target = visible
	commands.candidate_ui.next_session_id = session_id + 1
	commands.candidate_ui.next_source_generation = source_generation + 1
	keep_batch = true
	keep_session = true
	target := candidate_ui_visible_target()
	_, _, presented, present_failure := editor_session.session_present_ui(
		commands.session_owner,
		commands.session_handle,
		target.ui,
	)
	if !presented {
		command_context_close_project_navigation(commands)
		return {}, App_Failure{stage = .Session_Access, editor_session = present_failure}
	}
	commands.pending = {}
	commands.diagnostic_length = 0
	return Interaction_Result{changed = true}, {}
}

@(private)
dispatch_project_navigation_input :: proc(
	commands: ^Command_Context,
	input: interaction.Input,
	constraints: display.Viewport_Constraints,
) -> (Interaction_Result, App_Failure) {
	view, viewed, view_failure := interaction.candidate_session_view(&commands.candidate_ui.session)
	if !viewed || view.source_kind != .Projects {
		return {}, App_Failure{stage = .Component_Access, candidate = view_failure}
	}
	if map_failure := command_context_sync_candidate_map(commands, .Projects);
	   map_failure.stage != .None {
		return {}, map_failure
	}
	metadata, resolution, resolved, resolution_failure := command_context_resolve_context_input(commands, input)
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
			command_context_candidate_failure_diagnostic(commands, "Project candidate movement", move_failure)
		}
		return Interaction_Result{changed = true}, {}
	}
	if contextual_route == .Component_Query_Text {
		if len(resolution.text) == 0 do return {}, {}
		if len(view.query) + len(resolution.text) > int(interaction.MAX_CANDIDATE_QUERY_BYTES) {
			command_context_set_diagnostic(commands, "Project query limit reached")
			return Interaction_Result{changed = true}, {}
		}
		query: [interaction.MAX_CANDIDATE_QUERY_BYTES]u8
		copy(query[:], transmute([]u8)view.query)
		copy(query[len(view.query):], transmute([]u8)resolution.text)
		return command_context_refresh_project_navigation(
			commands,
			string(query[:len(view.query) + len(resolution.text)]),
		)
	}
	if contextual_route == .Component_Query_Delete_Previous {
		if len(view.query) == 0 do return {}, {}
		end := len(view.query) - 1
		bytes := transmute([]u8)view.query
		for end > 0 && bytes[end] & 0xc0 == 0x80 do end -= 1
		return command_context_refresh_project_navigation(commands, view.query[:end])
	}
	if contextual_route == .Component_Activate_Current {
		if !view.has_selection || len(view.rows) == 0 do return {}, {}
		row := view.rows[view.selected_row]
		candidate, valid := project_selection_action_candidate(
			row.action,
			view.source_generation,
			commands.project_workflow.selection_candidates.candidates,
		)
		if !valid {
			command_context_set_diagnostic(commands, "Project changed; reopen the list")
			return Interaction_Result{changed = true}, {}
		}
		if commands.project_workflow.selection_purpose == .Unregister {
			_, removed, remove_failure := command.project_unregister(
				command_context_project_command_context(commands),
				commands.racket_runtime,
				commands.project_catalog_root,
				candidate.durable_id,
				candidate.path,
				candidate.project_generation,
			)
			command_context_deactivate_context_map(commands, .Completed)
			command_context_close_project_navigation(commands)
			if !removed {
				command_context_project_failure_diagnostic(commands, remove_failure)
				return Interaction_Result{changed = true}, {}
			}
			command_context_set_diagnostic(commands, "Project removed from registry")
			return Interaction_Result{changed = true}, {}
		}
		if commands.project_workflow.selection_purpose == .Workspace_Add ||
		   commands.project_workflow.selection_purpose == .Workspace_Remove {
			if len(candidate.path) > len(commands.project_workflow.pending_workspace_project_path) {
				return {}, App_Failure{stage = .Component_Access}
			}
			copy(
				commands.project_workflow.pending_workspace_project_path[:],
				transmute([]u8)candidate.path,
			)
			commands.project_workflow.pending_workspace_project_path_length = len(candidate.path)
			purpose := Workspace_Selection_Purpose.Add_Project
			if commands.project_workflow.selection_purpose == .Workspace_Remove {
				purpose = .Remove_Project
			}
			command_context_deactivate_context_map(commands, .Completed)
			command_context_close_project_navigation(commands)
			return command_context_present_workspace_navigation(commands, purpose)
		}
		if commands.project_workflow.selection_purpose == .Workspace_Hierarchy_Module_Add {
			path_storage: [document.MAX_PATH_BYTES]u8
			path_length := copy(path_storage[:], transmute([]u8)candidate.path)
			command_context_deactivate_context_map(commands, .Completed)
			command_context_close_project_navigation(commands)
			status := product_module_workspace_add_project(
				commands, string(path_storage[:path_length]),
			)
			if status != .Ok {
				command_context_set_diagnostic(commands, "Project could not be added to the active Workspace")
			}
			return {changed = true}, {}
		}
		path_storage: [document.MAX_PATH_BYTES]u8
		copy(path_storage[:], transmute([]u8)candidate.path)
		path_length := len(candidate.path)
		if len(candidate.durable_id) > len(commands.project_workflow.pending_selection_id) {
			return {}, App_Failure{stage = .Component_Access}
		}
		copy(
			commands.project_workflow.pending_selection_id[:],
			transmute([]u8)candidate.durable_id,
		)
		commands.project_workflow.pending_selection_id_length = len(candidate.durable_id)
		command_context_deactivate_context_map(commands, .Completed)
		command_context_close_project_navigation(commands)
		return command_context_open_project_directory(
			commands,
			string(path_storage[:path_length]),
			constraints,
		)
	}
	if contextual_route == .Component_Close || command_metadata_is_native(metadata, .Keyboard_Quit) {
		return command_context_leave_project_navigation(commands)
	}
	return {}, {}
}

@(private)
command_context_refresh_project_navigation :: proc(
	commands: ^Command_Context,
	query: string,
) -> (Interaction_Result, App_Failure) {
	view, viewed, view_failure := interaction.candidate_session_view(&commands.candidate_ui.session)
	if !viewed || view.source_kind != .Projects {
		return {}, App_Failure{stage = .Component_Access, candidate = view_failure}
	}
	_, refreshed, refresh_failure := interaction.candidate_session_set_query(
		&commands.candidate_ui.session,
		interaction.Candidate_Request {
			session_id = view.session_id,
			session_generation = view.session_generation,
		},
		query,
	)
	if !refreshed {
		command_context_candidate_failure_diagnostic(commands, "Project candidate query", refresh_failure)
	}
	commands.diagnostic_length = 0
	return Interaction_Result{changed = true}, {}
}

@(private)
command_context_leave_project_navigation :: proc(
	commands: ^Command_Context,
) -> (Interaction_Result, App_Failure) {
	command_context_deactivate_context_map(commands, .Completed)
	view, viewed, view_failure := interaction.candidate_session_view(&commands.candidate_ui.session)
	if !viewed {
		return {}, App_Failure{stage = .Component_Access, candidate = view_failure}
	}
	_, cancelled, cancel_failure := interaction.candidate_session_cancel(
		&commands.candidate_ui.session,
		interaction.Candidate_Request {
			session_id = view.session_id,
			session_generation = view.session_generation,
		},
	)
	if !cancelled {
		return {}, App_Failure{stage = .Component_Access, candidate = cancel_failure}
	}
	return_target := commands.candidate_ui.return_target
	defer command_context_close_project_navigation(commands)
	commands.diagnostic_length = 0
	switch return_target.kind {
	case .Primary_View:
		_, activated, activation_failure := editor_session.session_activate(
			commands.session_owner,
			return_target.entry,
		)
		if !activated {
			return {}, App_Failure{stage = .Session_Access, editor_session = activation_failure}
		}
	case .UI_Root:
		_, _, presented, present_failure := editor_session.session_present_ui(
			commands.session_owner,
			commands.session_handle,
			return_target.ui,
		)
		if !presented {
			return {}, App_Failure{stage = .Session_Access, editor_session = present_failure}
		}
	case .None:
		return {}, App_Failure{stage = .Session_Access}
	}
	return Interaction_Result{changed = true}, {}
}

@(private)
command_context_close_project_navigation :: proc(commands: ^Command_Context) {
	if commands == nil do return
	if commands.candidate_ui.session.state != nil {
		_, _, _ = interaction.candidate_session_close(&commands.candidate_ui.session)
	}
	if commands.project_workflow.selection_candidates.state != nil {
		command.project_directory_candidate_batch_close(
			&commands.project_workflow.selection_candidates,
		)
	}
	commands.project_workflow.selection_purpose = .Open
	commands.candidate_ui.return_target = {}
}

@(private)
project_selection_action_candidate :: proc(
	action: interaction.Candidate_Action,
	source_generation: u64,
	candidates: []command.Project_Directory_Candidate,
) -> (^command.Project_Directory_Candidate, bool) {
	if action.kind != .Open_Project || action.owner_generation != source_generation ||
	   action.primary == 0 || action.primary > u64(len(candidates)) {
		return nil, false
	}
	candidate := &candidates[int(action.primary - 1)]
	return candidate, u64(candidate.project_generation) == action.secondary
}
