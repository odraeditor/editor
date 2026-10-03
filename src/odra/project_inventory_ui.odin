// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../display"
import "../editor_session"
import "../project"
import terminal "../terminal"
import "../ui"
import "base:runtime"
import "core:fmt"

/* PROJECT_LIST_UI_OWNER_ID identifies the built-in Project list projection owner. */
PROJECT_LIST_UI_OWNER_ID :: ui.Owner_ID(10_003)
/* PROJECT_LIST_UI_MODEL_ID identifies the built-in Project list model. */
PROJECT_LIST_UI_MODEL_ID :: ui.Model_ID(10_003)
/* PROJECT_LIST_UI_TARGET_GENERATION identifies the Project list target contract. */
PROJECT_LIST_UI_TARGET_GENERATION :: u64(1)
/* PROJECT_LIST_SELECT_ACTION activates one copied Project semantic record. */
PROJECT_LIST_SELECT_ACTION :: ui.List_Action_ID(1)
/* PROJECT_LIST_CLOSE_ACTION identifies the Project summary close row. */
PROJECT_LIST_CLOSE_ACTION :: ui.List_Action_ID(2)

@(private)
Project_List_Mode :: enum u8 {
	Invalid,
	Inventory,
	Directory_Choices,
}

@(private)
Project_List_Current_Action :: enum u8 {
	Invalid,
	Close,
	Inspect_Directory,
	Open_Directory_Candidate,
}

@(private)
project_list_visible_target :: proc() -> editor_session.Visible_Target {
	return editor_session.Visible_Target {
		kind = .UI_Root,
		ui = {
			owner_id = u64(PROJECT_LIST_UI_OWNER_ID),
			model_id = u64(PROJECT_LIST_UI_MODEL_ID),
			generation = PROJECT_LIST_UI_TARGET_GENERATION,
		},
	}
}

@(private)
project_list_workflow_reset :: proc(state: ^Project_Workflow_State) {
	if state == nil do return
	next_model_generation := state.list_next_model_generation
	state.list_mode = .Invalid
	state.list_position = {}
	state.list_return_target = {}
	state.list_project = {}
	state.list_current_membership = {}
	state.list_current_candidate_id = {}
	state.list_current_candidate_generation = {}
	state.list_model_generation = 0
	state.list_next_model_generation = next_model_generation
}

@(private)
project_list_workflow_advance_generation :: proc(state: ^Project_Workflow_State) -> bool {
	if state == nil || state.list_next_model_generation == max(u64) do return false
	state.list_next_model_generation += 1
	state.list_model_generation = state.list_next_model_generation
	return true
}

@(private)
project_list_item_count :: proc(state: ^Project_Workflow_State) -> (count: u32, ok: bool) {
	if state == nil || state.list_model_generation == 0 do return 0, false
	switch state.list_mode {
	case .Inventory:
		count_64 := u64(len(state.directory_candidates.descriptors)) + 1
		if count_64 > u64(ui.MAX_LIST_ITEMS) do return 0, false
		return u32(count_64), true
	case .Directory_Choices:
		count_64 := u64(len(state.directory_open_candidates.candidates))
		if count_64 == 0 || count_64 > u64(ui.MAX_LIST_ITEMS) do return 0, false
		return u32(count_64), true
	case .Invalid:
	}
	return 0, false
}

@(private)
project_list_current_index :: proc(state: ^Project_Workflow_State) -> int {
	if state.list_mode == .Inventory && project.membership_handle_is_valid(state.list_current_membership) {
		for descriptor, index in state.directory_candidates.descriptors {
			if descriptor.handle.id == state.list_current_membership.id &&
			   descriptor.handle.generation == state.list_current_membership.generation {
				return index + 1
			}
		}
	} else if state.list_mode == .Directory_Choices &&
	          state.list_current_candidate_id != project.Project_ID(0) {
		for candidate, index in state.directory_open_candidates.candidates {
			if candidate.project_id == state.list_current_candidate_id {
				return index
			}
		}
	}
	return 0
}

@(private)
project_list_sync_current_identity :: proc(state: ^Project_Workflow_State) {
	if state == nil do return
	index := state.list_position.current_item
	if state.list_mode == .Inventory {
		state.list_current_candidate_id = {}
		state.list_current_candidate_generation = {}
		state.list_current_membership = {}
		if index > 0 && index <= i32(len(state.directory_candidates.descriptors)) {
			state.list_current_membership = state.directory_candidates.descriptors[index - 1].handle
		}
	} else if state.list_mode == .Directory_Choices {
		state.list_current_membership = {}
		state.list_current_candidate_id = {}
		state.list_current_candidate_generation = {}
		if index >= 0 && index < i32(len(state.directory_open_candidates.candidates)) {
			candidate := state.directory_open_candidates.candidates[index]
			state.list_current_candidate_id = candidate.project_id
			state.list_current_candidate_generation = candidate.project_generation
		}
	}
}

@(private)
project_list_workflow_prepare :: proc(
	state: ^Project_Workflow_State,
	viewport_items: u32,
) -> (ok: bool, failure: ui.Failure) {
	item_count, count_ok := project_list_item_count(state)
	if !count_ok || viewport_items == 0 || viewport_items > ui.MAX_LIST_ITEMS {
		return false, ui.Failure{operation = .Prepare, code = .Invalid_List_View}
	}
	current_index := project_list_current_index(state)
	if state.list_position.presentation_generation == 0 {
		state.list_position = ui.List_View_Position {
			presentation_generation = 1,
			selection_owner = .View,
			current_item = i32(current_index),
			first_visible_item = 0,
			viewport_items = viewport_items,
		}
	} else {
		previous := state.list_position
		state.list_position.current_item = i32(current_index)
		state.list_position.viewport_items = viewport_items
		if u32(current_index) < state.list_position.first_visible_item {
			state.list_position.first_visible_item = u32(current_index)
		}
		end := u64(state.list_position.first_visible_item) + u64(viewport_items)
		if u64(current_index) >= end {
			state.list_position.first_visible_item = u32(current_index) - viewport_items + 1
		}
		if state.list_position != previous {
			if previous.presentation_generation == max(u64) {
				return false, ui.Failure{operation = .Resize, code = .Generation_Limit}
			}
			state.list_position.presentation_generation = previous.presentation_generation + 1
		}
	}
	list_state := ui.List_View_State {
		present = true,
		item_count = item_count,
		position = state.list_position,
	}
	if !ui.list_view_state_is_valid(list_state) {
		return false, ui.Failure{operation = .Prepare, code = .Invalid_List_View}
	}
	project_list_sync_current_identity(state)
	return true, {}
}

@(private)
project_list_workflow_move :: proc(
	state: ^Project_Workflow_State,
	delta: i32,
) -> (changed, ok: bool, failure: ui.Failure) {
	item_count, count_ok := project_list_item_count(state)
	if !count_ok {
		return false, false, ui.Failure{operation = .Navigate, code = .Invalid_List_View}
	}
	list_state := ui.List_View_State {
		present = true,
		item_count = item_count,
		position = state.list_position,
	}
	next: ui.List_View_State
	next, changed, ok, failure = ui.list_view_move_current(list_state, delta)
	if ok {
		state.list_position = next.position
		project_list_sync_current_identity(state)
	}
	return
}

@(private)
project_list_workflow_current_action :: proc(
	state: ^Project_Workflow_State,
) -> (action: Project_List_Current_Action, index: int, ok: bool) {
	if state == nil do return {}, 0, false
	index = int(state.list_position.current_item)
	if state.list_mode == .Inventory {
		if index == 0 do return .Close, 0, true
		if index > 0 && index <= len(state.directory_candidates.descriptors) {
			return .Inspect_Directory, index - 1, true
		}
	} else if state.list_mode == .Directory_Choices &&
	          index >= 0 && index < len(state.directory_open_candidates.candidates) {
		return .Open_Directory_Candidate, index, true
	}
	return {}, 0, false
}

@(private)
project_list_definitions :: proc(
	state: ^Project_Workflow_State,
	allocator: runtime.Allocator,
) -> (items: []ui.List_Item_Definition, storage: []u8, ok: bool) {
	item_count, count_ok := project_list_item_count(state)
	if !count_ok do return nil, nil, false
	definitions, definitions_error := make([]ui.List_Item_Definition, int(item_count), allocator)
	if definitions_error != nil do return nil, nil, false
	text_capacity := 0
	if state.list_mode == .Inventory {
		text_capacity = len(project.project_name_text(&state.list_project.name)) + 64
		for &descriptor in state.directory_candidates.descriptors {
			text_capacity += len(project.directory_path_text(&descriptor.path)) + 96
		}
	} else {
		for candidate in state.directory_open_candidates.candidates {
			text_capacity += len(candidate.name) + len(candidate.durable_id) + 8
		}
	}
	text, text_error := make([]u8, text_capacity, allocator)
	if text_error != nil {
		delete(definitions, allocator)
		return nil, nil, false
	}
	action := proc(action_id: ui.List_Action_ID, generation: u64) -> ui.List_Action_Reference {
		return ui.List_Action_Reference {
			owner_id = PROJECT_LIST_UI_OWNER_ID,
			action_id = action_id,
			generation = generation,
		}
	}
	offset := 0
	if state.list_mode == .Inventory {
			header := fmt.bprintf(
				text[offset:],
				"Project: %s [local Project; one root]",
				project.project_name_text(&state.list_project.name),
			)
		definitions[0] = ui.List_Item_Definition {
			id = 1,
			text = header,
			action = action(PROJECT_LIST_CLOSE_ACTION, state.list_model_generation),
		}
		offset += len(header)
		for &descriptor, index in state.directory_candidates.descriptors {
			row := fmt.bprintf(
				text[offset:],
					"Root [%v; %v]: %s",
				descriptor.trust,
				descriptor.availability,
				project.directory_path_text(&descriptor.path),
			)
			definitions[index + 1] = ui.List_Item_Definition {
				id = ui.List_Item_ID(u64(descriptor.handle.slot) + 2),
				text = row,
				action = action(PROJECT_LIST_SELECT_ACTION, state.list_model_generation),
			}
			offset += len(row)
		}
	} else {
		for candidate, index in state.directory_open_candidates.candidates {
			row := fmt.bprintf(text[offset:], "%s [%s]", candidate.name, candidate.durable_id)
			definitions[index] = ui.List_Item_Definition {
				id = ui.List_Item_ID(candidate.project_id),
				text = row,
				action = action(PROJECT_LIST_SELECT_ACTION, state.list_model_generation),
			}
			offset += len(row)
		}
	}
	return definitions, text, true
}

@(private)
present_project_list_ui :: proc(
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
	state := &commands.project_workflow
	if prepared, prepare_failure := project_list_workflow_prepare(
		state,
		content_rows,
	); !prepared {
		return App_Failure{stage = .UI, ui = prepare_failure}
	}
	if map_failure := command_context_sync_list_map(commands, .Project); map_failure.stage != .None {
		return map_failure
	}
	definitions, text_storage, definitions_ok := project_list_definitions(
		state,
		commands.temporary_allocator,
	)
	if !definitions_ok {
		return App_Failure{stage = .UI, ui = {operation = .Prepare, code = .Allocation}}
	}
	defer delete(definitions, commands.temporary_allocator)
	defer delete(text_storage, commands.temporary_allocator)
	registry, registry_ok, registry_failure := command_context_ui_registry(commands)
	if !registry_ok do return registry_failure
	profile, profile_ok := terminal.renderer_ui_profile(renderer)
	if !profile_ok do return App_Failure{stage = .Presentation, terminal = {code = .Invalid_Renderer}}
	proposal, proposal_ok, proposal_failure := ui.proposal_begin(registry, commands.ui_root)
	if !proposal_ok do return App_Failure{stage = .UI, ui = proposal_failure}
	defer if proposal.state != nil do ui.proposal_abort(&proposal)
	styles_ok, styles_failure := proposal_resolve_session_theme(&proposal, commands)
	if !styles_ok do return styles_failure
	view, projected, projection_failure := ui.proposal_project_list_view(
		&proposal,
		ui.List_Projection_Request {
			model = {
				owner_id = PROJECT_LIST_UI_OWNER_ID,
				model_id = PROJECT_LIST_UI_MODEL_ID,
				generation = ui.Model_Generation(state.list_model_generation),
			},
			position = state.list_position,
			read_only = true,
		},
		definitions,
	)
	if !projected do return App_Failure{stage = .UI, ui = projection_failure}
	surface, surface_ok, surface_failure := ui.proposal_add_surface(
		&proposal,
		ui.Surface_Descriptor {
			owner_id = PROJECT_LIST_UI_OWNER_ID,
			view = view,
			focusable = true,
			visible = true,
			input_context = 3_005,
			keymap_context = 4_005,
			required_profile = profile.id,
			geometry = {height = i32(content_rows), width = i32(constraints.width_cells)},
		},
	)
	if !surface_ok do return App_Failure{stage = .UI, ui = surface_failure}
	node, node_ok, node_failure := ui.proposal_add_surface_node(&proposal, surface)
	if !node_ok do return App_Failure{stage = .UI, ui = node_failure}
	input_surface: ui.Object_Handle
	if prompt_mode_projects_input(commands.prompt_workflow.mode) {
		composition, composed, compose_failure := proposal_compose_transient_input(
			&proposal, commands, node, surface, constraints, profile.id,
		)
		if !composed do return App_Failure{stage = .UI, ui = compose_failure}
		input_surface = composition.input_surface
	} else if transient_feedback_projects_root_edge(commands) {
		if composed, compose_failure := proposal_compose_command_feedback(
			&proposal, commands, node, surface, constraints,
		); !composed {
			return App_Failure{stage = .UI, ui = compose_failure}
		}
	} else if root_ok, root_failure := ui.proposal_set_root(&proposal, node, surface); !root_ok {
		return App_Failure{stage = .UI, ui = root_failure}
	}
	root, published, publish_failure := ui.proposal_publish(registry, &proposal, profile)
	if !published do return App_Failure{stage = .UI, ui = publish_failure}
	commands.ui_root = root
	if prompt_mode_projects_input(commands.prompt_workflow.mode) {
		commands.prompt_workflow.focus_captured = false
		if capture_failure := command_context_capture_prompt_focus(commands, input_surface);
		   capture_failure.stage != .None {
			return capture_failure
		}
	}
	snapshot, snapped, snapshot_failure := ui.registry_snapshot(registry, root, profile)
	if !snapped do return App_Failure{stage = .UI, ui = snapshot_failure}
	defer ui.snapshot_close(&snapshot)
	presented, presentation_failure := terminal.renderer_present_ui(
		renderer,
		session,
		terminal.UI_Presentation{root = &snapshot},
	)
	if !presented do return App_Failure{stage = .Presentation, terminal = presentation_failure}
	return {}
}
