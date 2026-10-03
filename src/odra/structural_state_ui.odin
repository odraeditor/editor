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
import "../language"
import terminal "../terminal"
import "../ui"
import editor_view "../view"
import "base:runtime"
import "core:fmt"

/* STRUCTURAL_STATE_UI_OWNER_ID identifies the built-in structural inspection owner. */
STRUCTURAL_STATE_UI_OWNER_ID :: ui.Owner_ID(10_011)
/* STRUCTURAL_STATE_UI_MODEL_ID identifies the built-in structural inspection model. */
STRUCTURAL_STATE_UI_MODEL_ID :: ui.Model_ID(10_011)
/* STRUCTURAL_STATE_UI_TARGET_GENERATION identifies the structural inspection target contract. */
STRUCTURAL_STATE_UI_TARGET_GENERATION :: u64(1)
/* STRUCTURAL_STATE_CLOSE_ACTION identifies the read-only inspection row action. */
STRUCTURAL_STATE_CLOSE_ACTION :: ui.List_Action_ID(1)
/* STRUCTURAL_STATE_ROW_COUNT bounds the copied structural inspection inventory. */
STRUCTURAL_STATE_ROW_COUNT :: 13
/* STRUCTURAL_STATE_ROW_BYTES bounds one formatted structural inspection row. */
STRUCTURAL_STATE_ROW_BYTES :: 512

@(private)
Structural_State_Workflow_State :: struct {
	available:             bool,
	scope:                 language.Structural_Scope,
	logical:               editor_view.Snapshot,
	command_state:         command.Structural_Capability_State,
	language_failure:      language.Failure,
	capability_generation: u64,
	ready:                 bool,
	return_target:         editor_session.Visible_Target,
	position:              ui.List_View_Position,
	model_generation:      u64,
	next_model_generation: u64,
}

@(private)
structural_state_visible_target :: proc() -> editor_session.Visible_Target {
	return editor_session.Visible_Target {
		kind = .UI_Root,
		ui = {
			owner_id = u64(STRUCTURAL_STATE_UI_OWNER_ID),
			model_id = u64(STRUCTURAL_STATE_UI_MODEL_ID),
			generation = STRUCTURAL_STATE_UI_TARGET_GENERATION,
		},
	}
}

@(private)
structural_state_workflow_reset :: proc(state: ^Structural_State_Workflow_State) {
	if state == nil do return
	next_generation := state.next_model_generation
	state^ = {}
	state.next_model_generation = next_generation
}

@(private)
structural_state_workflow_advance_generation :: proc(
	state: ^Structural_State_Workflow_State,
) -> bool {
	if state == nil || state.next_model_generation == max(u64) do return false
	state.next_model_generation += 1
	state.model_generation = state.next_model_generation
	return true
}

@(private)
structural_state_workflow_prepare :: proc(
	state: ^Structural_State_Workflow_State,
	viewport_items: u32,
) -> (ok: bool, failure: ui.Failure) {
	if state == nil || !state.ready || state.model_generation == 0 || viewport_items == 0 ||
	   viewport_items > ui.MAX_LIST_ITEMS {
		return false, ui.Failure{operation = .Prepare, code = .Invalid_List_View}
	}
	if state.position.presentation_generation == 0 {
		state.position = ui.List_View_Position {
			presentation_generation = 1,
			selection_owner = .View,
			viewport_items = viewport_items,
		}
	} else {
		state.position.viewport_items = viewport_items
		state.position.current_item = min(
			state.position.current_item,
			i32(STRUCTURAL_STATE_ROW_COUNT - 1),
		)
		state.position.first_visible_item = min(
			state.position.first_visible_item,
			u32(STRUCTURAL_STATE_ROW_COUNT - 1),
		)
	}
	return true, {}
}

@(private)
structural_state_workflow_move :: proc(
	state: ^Structural_State_Workflow_State,
	delta: i32,
) -> (changed, ok: bool, failure: ui.Failure) {
	if state == nil || !state.ready {
		return false, false, ui.Failure{operation = .Prepare, code = .Invalid_List_View}
	}
	next: ui.List_View_State
	next, changed, ok, failure = ui.list_view_move_current(
		ui.List_View_State {
			present = true,
			item_count = STRUCTURAL_STATE_ROW_COUNT,
			position = state.position,
		},
		delta,
	)
	if ok do state.position = next.position
	return changed, ok, failure
}

@(private)
structural_state_list_definitions :: proc(
	state: ^Structural_State_Workflow_State,
	allocator: runtime.Allocator,
) -> (items: []ui.List_Item_Definition, storage: []u8, ok: bool) {
	if state == nil || !state.ready || state.model_generation == 0 ||
	   allocator.procedure == nil {
		return nil, nil, false
	}
	items_error: runtime.Allocator_Error
	items, items_error = make([]ui.List_Item_Definition, STRUCTURAL_STATE_ROW_COUNT, allocator)
	if items_error != nil do return nil, nil, false
	storage_error: runtime.Allocator_Error
	storage, storage_error = make(
		[]u8,
		STRUCTURAL_STATE_ROW_COUNT * STRUCTURAL_STATE_ROW_BYTES,
		allocator,
	)
	if storage_error != nil {
		delete(items, allocator)
		return nil, nil, false
	}
	target := state.command_state.last_target
	kind := "none"
	if target.kind.length > 0 {
		kind = string(target.kind.bytes[:target.kind.length])
	}
	mark := u64(state.logical.point_position.byte_offset)
	if state.logical.mark.present do mark = u64(state.logical.mark.position.byte_offset)
	diagnostic := string(
		state.command_state.diagnostic[:state.command_state.diagnostic_length],
	)
	limits := language.DEFAULT_STRUCTURAL_LIMITS
	for index in 0 ..< STRUCTURAL_STATE_ROW_COUNT {
		row_storage := storage[index * STRUCTURAL_STATE_ROW_BYTES:(index + 1) * STRUCTURAL_STATE_ROW_BYTES]
		row: string
		switch index {
		case 0:
			row = fmt.bprintf(row_storage, "Capability: available=%v generation=%d grammar=Odin", state.available, state.capability_generation)
		case 1:
			row = fmt.bprintf(row_storage, "Scope: buffer=%d revision=%d view=%d@%d", state.scope.buffer_id, state.scope.source_revision, state.logical.view_id, state.logical.view_generation)
		case 2:
			row = fmt.bprintf(row_storage, "Language: id=%d@%d provider=%d@%d selection=%d", state.scope.language.id, state.scope.language.generation, state.scope.provider.provider_id, state.scope.provider.provider_generation, state.scope.selection_generation)
		case 3:
			row = fmt.bprintf(row_storage, "Analysis: parser-generation=%d tree-generation=%d source-revision=%d", state.scope.parser_generation, state.scope.tree_generation, state.scope.source_revision)
		case 4:
			row = fmt.bprintf(row_storage, "Grammar rules: named nodes; indentation=%d spaces; comments, strings, blanks, and syntax-error regions preserved", language.FACTORY_ODIN_INDENT_BYTES)
		case 5:
			row = fmt.bprintf(row_storage, "Selection: point=%d mark=%d present=%v active=%v generation=%d", state.logical.point_position.byte_offset, mark, state.logical.mark.present, state.logical.region_active, state.logical.selection_generation)
		case 6:
			row = fmt.bprintf(row_storage, "Last target: kind=%s range=%d..%d depth=%d buffer=%d revision=%d", kind, target.start, target.end, target.depth, target.scope.buffer_id, target.scope.source_revision)
		case 7:
			row = fmt.bprintf(row_storage, "Last operation: operation=%v completion=%v changed=%v", state.command_state.last_operation, state.command_state.last_completion, state.command_state.last_changed)
		case 8:
			row = fmt.bprintf(row_storage, "Last indentation: range=%d..%d edits=%d", state.command_state.plan_start, state.command_state.plan_end, state.command_state.plan_edit_count)
		case 9:
			row = fmt.bprintf(row_storage, "Usage traversal: nodes=%d depth=%d temporary-bytes=%d", state.command_state.usage.visited_nodes, state.command_state.usage.visited_depth, state.command_state.usage.temporary_bytes)
		case 10:
			row = fmt.bprintf(row_storage, "Usage indentation: lines=%d prepared-bytes=%d", state.command_state.usage.indent_lines, state.command_state.usage.prepared_bytes)
		case 11:
			row = fmt.bprintf(row_storage, "Limits: nodes=%d depth=%d lines=%d prepared=%d kind=%d diagnostic=%d inspection=%d", limits.nodes, limits.depth, limits.indent_lines, limits.prepared_bytes, limits.node_kind_bytes, limits.diagnostic_bytes, limits.inspection_bytes)
		case 12:
			row = fmt.bprintf(row_storage, "Latest rejection: command=%v structural=%v analysis=%v revision=%d limit=%d actual=%d diagnostic=%q", state.command_state.latest_failure.code, state.command_state.latest_failure.structural_code, state.language_failure.code, state.command_state.latest_failure.revision, state.command_state.latest_failure.limit, state.command_state.latest_failure.actual, diagnostic)
		}
		items[index] = ui.List_Item_Definition {
			id = ui.List_Item_ID(index + 1),
			text = row,
			action = {
				owner_id = STRUCTURAL_STATE_UI_OWNER_ID,
				action_id = STRUCTURAL_STATE_CLOSE_ACTION,
				generation = state.model_generation,
			},
		}
	}
	return items, storage, true
}

@(private)
command_context_present_structural_state :: proc(
	commands: ^Command_Context,
	buffer: ^editor.Buffer,
	view_registry: ^editor_view.Registry,
	view: editor_view.View_Handle,
	constraints: display.Viewport_Constraints,
) -> (Interaction_Result, App_Failure) {
	if commands == nil || buffer == nil || view_registry == nil ||
	   !syntax_workflow_is_live(commands.syntax_workflow) {
		return {}, App_Failure{stage = .Command_Dispatch}
	}
	visible, visible_ok, visible_failure := editor_session.session_visible_target(
		commands.session_owner,
		commands.session_handle,
	)
	if !visible_ok || visible.kind != .Primary_View {
		return {}, App_Failure{stage = .Session_Access, editor_session = visible_failure}
	}
	logical, logical_ok, logical_failure := editor_view.snapshot(view_registry, view)
	if !logical_ok {
		return {}, App_Failure{stage = .Command_Dispatch, command = {
			code = .View_Failure,
			view_code = logical_failure.code,
		}}
	}
	_, _, scope, available, language_failure := syntax_workflow_structural_context(
		commands.syntax_workflow,
		buffer,
	)
	state := &commands.structural_state_workflow
	structural_state_workflow_reset(state)
	state.available = available
	state.scope = scope
	state.logical = logical
	if commands.structural_command_state != nil do state.command_state = commands.structural_command_state^
	state.language_failure = language_failure
	state.capability_generation = commands.structural_capability_generation
	state.ready = true
	state.return_target = visible
	if !structural_state_workflow_advance_generation(state) {
		structural_state_workflow_reset(state)
		return {}, App_Failure{stage = .UI, ui = {operation = .Prepare, code = .Generation_Limit}}
	}
	if prepared, prepare_failure := structural_state_workflow_prepare(
		state,
		constraints.height_rows,
	); !prepared {
		structural_state_workflow_reset(state)
		return {}, App_Failure{stage = .UI, ui = prepare_failure}
	}
	target := structural_state_visible_target()
	_, _, presented, present_failure := editor_session.session_present_ui(
		commands.session_owner,
		commands.session_handle,
		target.ui,
	)
	if !presented {
		structural_state_workflow_reset(state)
		return {}, App_Failure{stage = .Session_Access, editor_session = present_failure}
	}
	commands.pending = {}
	commands.diagnostic_length = 0
	return Interaction_Result{changed = true}, {}
}

@(private)
present_structural_state_ui :: proc(
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
	state := &commands.structural_state_workflow
	if prepared, prepare_failure := structural_state_workflow_prepare(state, content_rows); !prepared {
		return App_Failure{stage = .UI, ui = prepare_failure}
	}
	if map_failure := command_context_sync_list_map(commands, .Structural_State);
	   map_failure.stage != .None {
		return map_failure
	}
	registry, registry_ok, registry_failure := command_context_ui_registry(commands)
	if !registry_ok do return registry_failure
	profile, profile_ok := terminal.renderer_ui_profile(renderer)
	if !profile_ok do return App_Failure{stage = .Presentation, terminal = {code = .Invalid_Renderer}}
	definitions, text_storage, definitions_ok := structural_state_list_definitions(
		state,
		commands.temporary_allocator,
	)
	if !definitions_ok {
		return App_Failure{stage = .UI, ui = {operation = .Prepare, code = .Allocation}}
	}
	defer delete(definitions, commands.temporary_allocator)
	defer delete(text_storage, commands.temporary_allocator)
	proposal, proposal_ok, proposal_failure := ui.proposal_begin(registry, commands.ui_root)
	if !proposal_ok do return App_Failure{stage = .UI, ui = proposal_failure}
	defer if proposal.state != nil do ui.proposal_abort(&proposal)
	styles_ok, styles_failure := proposal_resolve_session_theme(&proposal, commands)
	if !styles_ok do return styles_failure
	view_handle, projected, projection_failure := ui.proposal_project_list_view(
		&proposal,
		ui.List_Projection_Request {
			model = {
				owner_id = STRUCTURAL_STATE_UI_OWNER_ID,
				model_id = STRUCTURAL_STATE_UI_MODEL_ID,
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
		ui.Surface_Descriptor {
			owner_id = STRUCTURAL_STATE_UI_OWNER_ID,
			view = view_handle,
			focusable = true,
			visible = true,
			input_context = 3_011,
			keymap_context = 4_011,
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

@(private)
dispatch_structural_state_list_input :: proc(
	commands: ^Command_Context,
	input: interaction.Input,
	constraints: display.Viewport_Constraints,
) -> (Interaction_Result, App_Failure) {
	state := &commands.structural_state_workflow
	if prepared, prepare_failure := structural_state_workflow_prepare(
		state,
		constraints.height_rows,
	); !prepared {
		return {}, App_Failure{stage = .UI, ui = prepare_failure}
	}
	if map_failure := command_context_sync_list_map(commands, .Structural_State);
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
		changed, moved, move_failure := structural_state_workflow_move(state, delta)
		if !moved do return {}, App_Failure{stage = .UI, ui = move_failure}
		return Interaction_Result{changed = changed}, {}
	}
	if contextual_route == .Component_Close || command_metadata_is_native(metadata, .Keyboard_Quit) {
		return command_context_leave_structural_state(commands)
	}
	return {}, {}
}

@(private)
command_context_leave_structural_state :: proc(
	commands: ^Command_Context,
) -> (Interaction_Result, App_Failure) {
	return_target := commands.structural_state_workflow.return_target
	command_context_deactivate_context_map(commands, .Completed)
	structural_state_workflow_reset(&commands.structural_state_workflow)
	if return_target.kind != .Primary_View {
		return {}, App_Failure{stage = .Session_Access}
	}
	_, activated, activation_failure := editor_session.session_activate(
		commands.session_owner,
		return_target.entry,
	)
	if !activated {
		return {}, App_Failure{stage = .Session_Access, editor_session = activation_failure}
	}
	return Interaction_Result{changed = true}, {}
}
