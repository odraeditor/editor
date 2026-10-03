// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../command"
import "../display"
import "../editor"
import "../editor_session"
import "../interaction"
import language_service_workflow "../language_service_workflow"
import terminal "../terminal"
import "../ui"
import "core:fmt"

@(private)
LANGUAGE_SERVICE_INSPECTION_UI_OWNER_ID :: ui.Owner_ID(language_service_workflow.LANGUAGE_SERVICE_INSPECTION_UI_OWNER_ID)
@(private)
LANGUAGE_SERVICE_INSPECTION_UI_MODEL_ID :: ui.Model_ID(language_service_workflow.LANGUAGE_SERVICE_INSPECTION_UI_MODEL_ID)
@(private)
LANGUAGE_SERVICE_INSPECTION_UI_TARGET_GENERATION :: u64(language_service_workflow.LANGUAGE_SERVICE_INSPECTION_UI_TARGET_GENERATION)
@(private)
LANGUAGE_SERVICE_INSPECTION_CLOSE_ACTION :: ui.List_Action_ID(language_service_workflow.LANGUAGE_SERVICE_INSPECTION_CLOSE_ACTION)
@(private)
LANGUAGE_SERVICE_INSPECTION_BASE_ROWS :: int(language_service_workflow.LANGUAGE_SERVICE_INSPECTION_BASE_ROWS)
@(private)
LANGUAGE_SERVICE_INSPECTION_ROW_BYTES :: int(language_service_workflow.LANGUAGE_SERVICE_INSPECTION_ROW_BYTES)

@(private)
Language_Service_Inspection_Workflow_State :: language_service_workflow.Inspection_State
language_service_inspection_visible_target :: language_service_workflow.Language_Service_Inspection_Visible_Target
language_service_inspection_workflow_reset :: language_service_workflow.Language_Service_Inspection_Workflow_Reset
language_service_inspection_workflow_advance_generation :: language_service_workflow.Language_Service_Inspection_Workflow_Advance_Generation
language_service_inspection_workflow_prepare :: language_service_workflow.Language_Service_Inspection_Workflow_Prepare
language_service_inspection_workflow_move :: language_service_workflow.Language_Service_Inspection_Workflow_Move
language_service_inspection_workflow_capture :: language_service_workflow.Language_Service_Inspection_Workflow_Capture
language_service_inspection_list_definitions :: language_service_workflow.Language_Service_Inspection_List_Definitions

@(private)
command_context_present_language_service_inspection :: proc(
	commands: ^Command_Context,
	buffer: ^editor.Buffer,
	constraints: display.Viewport_Constraints,
) -> (Interaction_Result, App_Failure) {
	visible, visible_ok, visible_failure := editor_session.session_visible_target(
		commands.session_owner,
		commands.session_handle,
	)
	if !visible_ok || visible.kind != .Primary_View {
		return {}, App_Failure{stage = .Session_Access, editor_session = visible_failure}
	}
	state := &commands.language_service_inspection_workflow
	if !language_service_inspection_workflow_capture(
		state,
		commands.language_service_workflow,
		buffer,
		commands.persistent_allocator,
		commands.temporary_allocator,
	) {
		return {}, App_Failure{stage = .Component_Access}
	}
	state.return_target = visible
	if !language_service_inspection_workflow_advance_generation(state) {
		language_service_inspection_workflow_reset(state)
		return {}, App_Failure{stage = .UI, ui = {operation = .Prepare, code = .Generation_Limit}}
	}
	if prepared, prepare_failure := language_service_inspection_workflow_prepare(
		state,
		constraints.height_rows,
	); !prepared {
		language_service_inspection_workflow_reset(state)
		return {}, App_Failure{stage = .UI, ui = prepare_failure}
	}
	target := language_service_inspection_visible_target()
	_, _, presented, present_failure := editor_session.session_present_ui(
		commands.session_owner,
		commands.session_handle,
		target.ui,
	)
	if !presented {
		language_service_inspection_workflow_reset(state)
		return {}, App_Failure{stage = .Session_Access, editor_session = present_failure}
	}
	commands.pending = {}
	commands.diagnostic_length = 0
	return Interaction_Result{changed = true}, {}
}

@(private)
command_context_restart_language_service :: proc(
	commands: ^Command_Context,
	buffer: ^editor.Buffer,
) -> (Interaction_Result, App_Failure) {
	stats, stats_ok, _ := editor.buffer_stats(buffer)
	if !stats_ok do return {}, App_Failure{stage = .Component_Access}
	if completion_workflow_has_interaction(commands.completion_workflow) {
		completion_workflow_cancel_current(commands, true)
	}
	restarted, failure := language_service_workflow_restart(
		commands.language_service_workflow,
		stats.buffer_id,
	)
	if !restarted {
		command_context_set_channel_diagnostic(
			commands,
			.Language_Service,
			"Language service restart was rejected",
			.Warning,
			fmt.bprintf(commands.feedback_content[:], "Language service restart rejected: %v", failure.code),
		)
		return Interaction_Result{changed = true}, {}
	}
	command_context_set_channel_diagnostic(commands, .Language_Service, "Language service restart started")
	return Interaction_Result{changed = true}, {}
}

@(private)
present_language_service_inspection_ui :: proc(
	commands: ^Command_Context,
	session: ^terminal.Session,
	renderer: ^terminal.Renderer,
	constraints: display.Viewport_Constraints,
) -> App_Failure {
	if commands == nil || constraints.width_cells == 0 || constraints.height_rows == 0 {
		return App_Failure{stage = .UI, ui = {operation = .Prepare, code = .Invalid_List_View}}
	}
	content_rows, rows_ok := transient_input_content_rows(commands, constraints)
	if !rows_ok do return App_Failure{stage = .UI, ui = {operation = .Prepare, code = .Invalid_Layout}}
	state := &commands.language_service_inspection_workflow
	if prepared, prepare_failure := language_service_inspection_workflow_prepare(
		state,
		content_rows,
	); !prepared {
		return App_Failure{stage = .UI, ui = prepare_failure}
	}
	if map_failure := command_context_sync_list_map(commands, .Language_Service_Inspection);
	   map_failure.stage != .None {
		return map_failure
	}
	registry, registry_ok, registry_failure := command_context_ui_registry(commands)
	if !registry_ok do return registry_failure
	profile, profile_ok := terminal.renderer_ui_profile(renderer)
	if !profile_ok do return App_Failure{stage = .Presentation, terminal = {code = .Invalid_Renderer}}
	definitions, definitions_ok := language_service_inspection_list_definitions(
		state,
		commands.temporary_allocator,
	)
	if !definitions_ok do return App_Failure{stage = .UI, ui = {operation = .Prepare, code = .Allocation}}
	defer delete(definitions, commands.temporary_allocator)
	proposal, proposal_ok, proposal_failure := ui.proposal_begin(registry, commands.ui_root)
	if !proposal_ok do return App_Failure{stage = .UI, ui = proposal_failure}
	defer if proposal.state != nil do ui.proposal_abort(&proposal)
	styles_ok, styles_failure := proposal_resolve_session_theme(&proposal, commands)
	if !styles_ok do return styles_failure
	view, projected, projection_failure := ui.proposal_project_list_view(
		&proposal,
		{
			model = {
				owner_id = LANGUAGE_SERVICE_INSPECTION_UI_OWNER_ID,
				model_id = LANGUAGE_SERVICE_INSPECTION_UI_MODEL_ID,
				generation = ui.Model_Generation(state.model_generation),
			},
			position = state.position,
			read_only = true,
		},
		definitions,
	)
	if !projected do return App_Failure{stage = .UI, ui = projection_failure}
	surface, surface_ok, surface_failure := ui.proposal_add_surface(
		&proposal,
		{
			owner_id = LANGUAGE_SERVICE_INSPECTION_UI_OWNER_ID,
			view = view,
			focusable = true,
			visible = true,
			input_context = 3_012,
			keymap_context = 4_012,
			required_profile = profile.id,
			geometry = {height = i32(content_rows), width = i32(constraints.width_cells)},
		},
	)
	if !surface_ok do return App_Failure{stage = .UI, ui = surface_failure}
	node, node_ok, node_failure := ui.proposal_add_surface_node(&proposal, surface)
	if !node_ok do return App_Failure{stage = .UI, ui = node_failure}
	if transient_feedback_projects_root_edge(commands) {
		if composed, compose_failure := proposal_compose_command_feedback(
			&proposal,
			commands,
			node,
			surface,
			constraints,
		); !composed {
			return App_Failure{stage = .UI, ui = compose_failure}
		}
	} else if root_ok, root_failure := ui.proposal_set_root(&proposal, node, surface); !root_ok {
		return App_Failure{stage = .UI, ui = root_failure}
	}
	root, published, publish_failure := ui.proposal_publish(registry, &proposal, profile)
	if !published do return App_Failure{stage = .UI, ui = publish_failure}
	commands.ui_root = root
	snapshot, copied, copy_failure := ui.registry_snapshot(registry, root, profile)
	if !copied do return App_Failure{stage = .UI, ui = copy_failure}
	defer ui.snapshot_close(&snapshot)
	if presented, presentation_failure := terminal.renderer_present_ui(
		renderer,
		session,
		terminal.UI_Presentation{root = &snapshot},
	); !presented {
		return App_Failure{stage = .Presentation, terminal = presentation_failure}
	}
	return {}
}

@(private)
dispatch_language_service_inspection_list_input :: proc(
	commands: ^Command_Context,
	input: interaction.Input,
	constraints: display.Viewport_Constraints,
) -> (Interaction_Result, App_Failure) {
	content_rows, rows_ok := transient_input_content_rows(commands, constraints)
	if !rows_ok do return {}, App_Failure{stage = .UI, ui = {operation = .Prepare, code = .Invalid_Layout}}
	state := &commands.language_service_inspection_workflow
	if prepared, prepare_failure := language_service_inspection_workflow_prepare(
		state,
		content_rows,
	); !prepared {
		return {}, App_Failure{stage = .UI, ui = prepare_failure}
	}
	if map_failure := command_context_sync_list_map(commands, .Language_Service_Inspection);
	   map_failure.stage != .None {
		return {}, map_failure
	}
	metadata, resolution, resolved, resolution_failure := command_context_resolve_context_input(
		commands,
		input,
	)
	if !resolved do return {}, resolution_failure
	if resolution.kind != .Command do return {}, {}
	contextual_route, contextual_ok := command.contextual_route_decode(metadata.route)
	if contextual_ok &&
	   (contextual_route == .Component_Previous_Row || contextual_route == .Component_Next_Row) {
		delta := i32(1)
		if contextual_route == .Component_Previous_Row do delta = -1
		changed, moved, move_failure := language_service_inspection_workflow_move(state, delta)
		if !moved do return {}, App_Failure{stage = .UI, ui = move_failure}
		return Interaction_Result{changed = changed}, {}
	}
	if contextual_route == .Component_Close || command_metadata_is_native(metadata, .Keyboard_Quit) {
		return command_context_leave_language_service_inspection(commands)
	}
	return {}, {}
}

@(private)
command_context_leave_language_service_inspection :: proc(
	commands: ^Command_Context,
) -> (Interaction_Result, App_Failure) {
	return_target := commands.language_service_inspection_workflow.return_target
	command_context_deactivate_context_map(commands, .Completed)
	language_service_inspection_workflow_reset(&commands.language_service_inspection_workflow)
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
