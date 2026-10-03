// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../command"
import "../display"
import "../editor_session"
import "../interaction"
import "../workspace"
import "core:fmt"

@(private)
Workspace_Selection_Purpose :: enum u8 {
	Open,
	Add_Project,
	Remove_Project,
	Unregister,
	Workspace_Hierarchy_Module_Switch,
}

@(private)
Workspace_Workflow_State :: struct {
	batch: command.Workspace_Command_Batch,
	purpose: Workspace_Selection_Purpose,
}

@(private)
workspace_workflow_reset :: proc(state: ^Workspace_Workflow_State) {
	if state == nil do return
	if state.batch.state != nil do command.workspace_command_batch_close(&state.batch)
	state^ = {}
}

@(private)
command_context_present_workspace_navigation :: proc(
	commands: ^Command_Context,
	purpose: Workspace_Selection_Purpose = .Open,
) -> (Interaction_Result, App_Failure) {
	if commands == nil || commands.racket_runtime == nil ||
	   len(commands.lifecycle_configuration_root) == 0 {
		return {}, App_Failure{stage = .Component_Access}
	}
	visible, visible_ok, visible_failure := editor_session.session_visible_target(
		commands.session_owner,
		commands.session_handle,
	)
	if !visible_ok {
		return {}, App_Failure{stage = .Session_Access, editor_session = visible_failure}
	}
	listed, listed_ok, list_failure := command.workspace_list(
		command_context_project_command_context(commands),
		commands.racket_runtime,
		commands.lifecycle_configuration_root,
	)
	if !listed_ok {
		command_context_project_failure_diagnostic(commands, list_failure)
		return Interaction_Result{changed = true}, {}
	}
	keep_batch := false
	defer if !keep_batch do command.workspace_command_batch_close(&listed.batch)

	fields: [workspace.MAX_WORKSPACES][2]string
	annotations: [workspace.MAX_WORKSPACES][1]interaction.Candidate_Annotation_Definition
	member_labels: [workspace.MAX_WORKSPACES][32]u8
	descriptors: [workspace.MAX_WORKSPACES]interaction.Candidate_Descriptor_Definition
	if len(listed.batch.descriptors) > len(descriptors) {
		return {}, App_Failure{stage = .Component_Access}
	}
	source_generation := commands.candidate_ui.next_source_generation
	session_id := commands.candidate_ui.next_session_id
	if source_generation == 0 || source_generation == max(u64) ||
	   session_id == 0 || session_id == max(u64) {
		return {}, App_Failure{stage = .Component_Access}
	}
	for descriptor, index in listed.batch.descriptors {
		member_label := fmt.bprintf(
			member_labels[index][:],
			"%d %s",
			descriptor.member_count,
			"Project" if descriptor.member_count == 1 else "Projects",
		)
		fields[index] = {descriptor.id, member_label}
		annotations[index] = {{kind = .Project_Member, text = member_label}}
		availability := interaction.Candidate_Availability.Available
		for member_index in 0 ..< int(descriptor.member_count) {
			member := &listed.batch.members[int(descriptor.member_offset) + member_index]
			if member.state != .Ready {
				availability = .Unavailable
				break
			}
		}
		descriptors[index] = interaction.Candidate_Descriptor_Definition {
			identity = {kind = 10, primary = u64(index + 1), secondary = descriptor.generation},
			label = descriptor.name,
			searchable_fields = fields[index][:],
			annotations = annotations[index][:],
			action = {
				kind = .Open_Workspace,
				owner_generation = source_generation,
				primary = u64(index + 1),
				secondary = descriptor.generation,
			},
			availability = availability,
			durable_category = .Workspace,
			durable_key = descriptor.id,
		}
	}
	source_definition := interaction.Candidate_Source_Definition {
		kind = .Workspaces,
		scope_identity = 1,
		scope_generation = max(listed.batch.publication, 1),
		source_generation = source_generation,
		descriptors = descriptors[:len(listed.batch.descriptors)],
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
		command_context_candidate_failure_diagnostic(
			commands,
			"Workspace candidate session",
			candidate_failure,
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
	workspace_workflow_reset(&commands.workspace_workflow)
	commands.workspace_workflow.batch = listed.batch
	commands.workspace_workflow.purpose = purpose
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
		command_context_close_workspace_navigation(commands)
		return {}, App_Failure{stage = .Session_Access, editor_session = present_failure}
	}
	commands.pending = {}
	commands.diagnostic_length = 0
	return Interaction_Result{changed = true}, {}
}

@(private)
dispatch_workspace_navigation_input :: proc(
	commands: ^Command_Context,
	input: interaction.Input,
	constraints: display.Viewport_Constraints,
) -> (Interaction_Result, App_Failure) {
	view, viewed, view_failure := interaction.candidate_session_view(&commands.candidate_ui.session)
	if !viewed || view.source_kind != .Workspaces {
		return {}, App_Failure{stage = .Component_Access, candidate = view_failure}
	}
	if map_failure := command_context_sync_candidate_map(commands, .Workspaces);
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
			command_context_candidate_failure_diagnostic(commands, "Workspace candidate movement", move_failure)
		}
		return Interaction_Result{changed = true}, {}
	}
	if contextual_route == .Component_Query_Text {
		if len(resolution.text) == 0 do return {}, {}
		if len(view.query) + len(resolution.text) > int(interaction.MAX_CANDIDATE_QUERY_BYTES) {
			command_context_set_diagnostic(commands, "Workspace query limit reached")
			return Interaction_Result{changed = true}, {}
		}
		query: [interaction.MAX_CANDIDATE_QUERY_BYTES]u8
		copy(query[:], transmute([]u8)view.query)
		copy(query[len(view.query):], transmute([]u8)resolution.text)
		return command_context_refresh_workspace_navigation(
			commands,
			string(query[:len(view.query) + len(resolution.text)]),
		)
	}
	if contextual_route == .Component_Query_Delete_Previous {
		if len(view.query) == 0 do return {}, {}
		end := len(view.query) - 1
		bytes := transmute([]u8)view.query
		for end > 0 && bytes[end] & 0xc0 == 0x80 do end -= 1
		return command_context_refresh_workspace_navigation(commands, view.query[:end])
	}
	if contextual_route == .Component_Activate_Current {
		if !view.has_selection || len(view.rows) == 0 do return {}, {}
		row := view.rows[view.selected_row]
		descriptor, valid := workspace_candidate_action_descriptor(
			row.action,
			view.source_generation,
			commands.workspace_workflow.batch.descriptors,
		)
		if !valid {
			command_context_set_diagnostic(commands, "Workspace changed; reopen the list")
			return Interaction_Result{changed = true}, {}
		}
		if commands.workspace_workflow.purpose == .Add_Project ||
		   commands.workspace_workflow.purpose == .Remove_Project {
			project_path := string(
				commands.project_workflow.pending_workspace_project_path[:commands.project_workflow.pending_workspace_project_path_length]
			)
			if len(project_path) == 0 {
				command_context_set_diagnostic(commands, "Workspace command requires a selected Project")
				return Interaction_Result{changed = true}, {}
			}
			updated: command.Workspace_Command_Result
			updated_ok: bool
			update_failure: command.Failure_Context
			if commands.workspace_workflow.purpose == .Add_Project {
				updated, updated_ok, update_failure = command.workspace_add_project(
					command_context_project_command_context(commands),
					commands.racket_runtime,
					commands.lifecycle_configuration_root,
					descriptor.id,
					descriptor.generation,
					project_path,
				)
			} else {
				updated, updated_ok, update_failure = command.workspace_remove_project(
					command_context_project_command_context(commands),
					commands.racket_runtime,
					commands.lifecycle_configuration_root,
					descriptor.id,
					descriptor.generation,
					project_path,
				)
			}
			if !updated_ok {
				command_context_project_failure_diagnostic(commands, update_failure)
				return Interaction_Result{changed = true}, {}
			}
			defer command.workspace_command_batch_close(&updated.batch)
			switch updated.completion {
			case .Project_Added, .Project_Removed:
				command_context_deactivate_context_map(commands, .Completed)
				command_context_close_workspace_navigation(commands)
				commands.project_workflow.pending_workspace_project_path_length = 0
				command_context_set_diagnostic(
					commands,
					"Workspace updated",
				)
				return Interaction_Result{changed = true}, {}
			case .Unavailable_Members:
				command_context_workspace_member_diagnostic(commands, &updated.batch)
				return Interaction_Result{changed = true}, {}
			case .Dirty_Protection_Required:
				command_context_set_diagnostic(commands, "Workspace update requires resolving modified buffers")
				return Interaction_Result{changed = true}, {}
			case .Created, .Opened, .Updated, .Listed, .Inspected, .Project_Reordered,
			     .Workspace_Removed, .Invalid:
				return {}, App_Failure{stage = .Command_Dispatch}
			}
		}
		if commands.workspace_workflow.purpose == .Unregister {
			removed, removed_ok, remove_failure := command.workspace_unregister(
				command_context_project_command_context(commands),
				commands.racket_runtime,
				commands.lifecycle_configuration_root,
				descriptor.id,
				descriptor.generation,
			)
			if !removed_ok {
				command_context_project_failure_diagnostic(commands, remove_failure)
				return Interaction_Result{changed = true}, {}
			}
			defer command.workspace_command_batch_close(&removed.batch)
			command_context_deactivate_context_map(commands, .Completed)
			command_context_close_workspace_navigation(commands)
			command_context_set_diagnostic(commands, "Workspace removed from registry")
			return Interaction_Result{changed = true}, {}
		}
		opened, opened_ok, open_failure := command.workspace_open(
			command_context_project_command_context(commands),
			commands.racket_runtime,
			commands.lifecycle_configuration_root,
			descriptor.id,
		)
		if !opened_ok {
			command_context_project_failure_diagnostic(commands, open_failure)
			return Interaction_Result{changed = true}, {}
		}
		defer command.workspace_command_batch_close(&opened.batch)
		switch opened.completion {
		case .Opened:
			return_target := commands.candidate_ui.return_target
			purpose := commands.workspace_workflow.purpose
			_ = command_context_global_candidate_history_record(
				commands,
				.Workspace,
				descriptor.id,
			)
			_, recorded, record_failure := interaction.candidate_session_record_success(
				&commands.candidate_ui.session,
				request,
				row.identity,
			)
			if !recorded {
				command_context_candidate_failure_diagnostic(commands, "Workspace candidate recency", record_failure)
			}
			command_context_deactivate_context_map(commands, .Completed)
			if purpose == .Workspace_Hierarchy_Module_Switch {
				if restore_failure := command_context_restore_workspace_return_target(commands, return_target);
				   restore_failure.stage != .None {
					command_context_close_workspace_navigation(commands)
					return {}, restore_failure
				}
				command_context_close_workspace_navigation(commands)
				return product_module_workflow_activate_workspace_hierarchy_projects(commands, true)
			}
			recent_entry, recent_found, recent_failure := editor_session.session_workspace_recent_entry(
				commands.session_owner,
				commands.session_handle,
				opened.activation.roots.generation,
			)
			if recent_failure.code != .None {
				command_context_close_workspace_navigation(commands)
				return {}, App_Failure{stage = .Session_Access, editor_session = recent_failure}
			}
			if recent_found {
				_, activated, activation_failure := editor_session.session_activate(
					commands.session_owner,
					recent_entry,
				)
				if !activated {
					command_context_close_workspace_navigation(commands)
					return {}, App_Failure{stage = .Session_Access, editor_session = activation_failure}
				}
			} else if _, scratch_opened, scratch_failure := command.buffer_session_switch_to_buffer(
				command.Buffer_Session_Context {
					session = commands.session_owner,
					handle = commands.session_handle,
					configuration = commands.entry_configuration,
				},
				"*scratch*",
			); !scratch_opened {
				command_context_project_failure_diagnostic(commands, scratch_failure)
				if restore_failure := command_context_restore_workspace_return_target(
					commands,
					return_target,
				); restore_failure.stage != .None {
					command_context_close_workspace_navigation(commands)
					return {}, restore_failure
				}
				command_context_close_workspace_navigation(commands)
				return Interaction_Result{changed = true}, {}
			}
			command_context_close_workspace_navigation(commands)
			result, darek_failure := command_context_open_darek_projects(commands, true, constraints, {})
			if darek_failure.stage != .None {
				return result, darek_failure
			}
			commands.product_module_workflow.tree_projection.focused = !recent_found
			return result, {}
		case .Unavailable_Members:
			command_context_workspace_member_diagnostic(commands, &opened.batch)
			return Interaction_Result{changed = true}, {}
		case .Dirty_Protection_Required:
			command_context_set_diagnostic(commands, "Workspace opening requires resolving modified buffers")
			return Interaction_Result{changed = true}, {}
		case .Created, .Updated, .Listed, .Inspected, .Project_Added, .Project_Removed,
		     .Project_Reordered,
		     .Workspace_Removed, .Invalid:
			return {}, App_Failure{stage = .Command_Dispatch}
		}
	}
	if contextual_route == .Component_Close || command_metadata_is_native(metadata, .Keyboard_Quit) {
		return command_context_leave_workspace_navigation(commands)
	}
	return {}, {}
}

@(private)
command_context_refresh_workspace_navigation :: proc(
	commands: ^Command_Context,
	query: string,
) -> (Interaction_Result, App_Failure) {
	view, viewed, view_failure := interaction.candidate_session_view(&commands.candidate_ui.session)
	if !viewed || view.source_kind != .Workspaces {
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
		command_context_candidate_failure_diagnostic(commands, "Workspace candidate query", refresh_failure)
	}
	commands.diagnostic_length = 0
	return Interaction_Result{changed = true}, {}
}

@(private)
command_context_leave_workspace_navigation :: proc(
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
	defer command_context_close_workspace_navigation(commands)
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
command_context_close_workspace_navigation :: proc(commands: ^Command_Context) {
	if commands == nil do return
	if commands.candidate_ui.session.state != nil {
		_, _, _ = interaction.candidate_session_close(&commands.candidate_ui.session)
	}
	workspace_workflow_reset(&commands.workspace_workflow)
	commands.project_workflow.pending_workspace_project_path_length = 0
	commands.candidate_ui.return_target = {}
}

@(private)
command_context_restore_workspace_return_target :: proc(
	commands: ^Command_Context,
	return_target: editor_session.Visible_Target,
) -> App_Failure {
	if commands == nil || commands.session_owner == nil {
		return App_Failure{stage = .Session_Access}
	}
	switch return_target.kind {
	case .Primary_View:
		_, activated, activation_failure := editor_session.session_activate(
			commands.session_owner,
			return_target.entry,
		)
		if !activated {
			return App_Failure{stage = .Session_Access, editor_session = activation_failure}
		}
	case .UI_Root:
		_, _, presented, present_failure := editor_session.session_present_ui(
			commands.session_owner,
			commands.session_handle,
			return_target.ui,
		)
		if !presented {
			return App_Failure{stage = .Session_Access, editor_session = present_failure}
		}
	case .None:
		return App_Failure{stage = .Session_Access}
	}
	return {}
}

@(private)
workspace_candidate_action_descriptor :: proc(
	action: interaction.Candidate_Action,
	source_generation: u64,
	descriptors: []command.Workspace_Command_Descriptor,
) -> (^command.Workspace_Command_Descriptor, bool) {
	if action.kind != .Open_Workspace || action.owner_generation != source_generation ||
	   action.primary == 0 || action.primary > u64(len(descriptors)) {
		return nil, false
	}
	descriptor := &descriptors[int(action.primary - 1)]
	return descriptor, descriptor.generation == action.secondary
}

@(private)
command_context_workspace_member_diagnostic :: proc(
	commands: ^Command_Context,
	batch: ^command.Workspace_Command_Batch,
) {
	if commands == nil || batch == nil {
		return
	}
	unavailable := 0
	first := ""
	for member in batch.members {
		if member.state == .Ready do continue
		unavailable += 1
		if len(first) == 0 do first = member.diagnostic
	}
	message := fmt.bprintf(
		commands.diagnostic[:],
		"Workspace unavailable: %d %s%s%s",
		unavailable,
		"member" if unavailable == 1 else "members",
		": " if len(first) > 0 else "",
		first,
	)
	commands.diagnostic_length = len(message)
}
