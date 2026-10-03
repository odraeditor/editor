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
import "base:runtime"
import "core:fmt"

/* LANGUAGE_STATE_UI_OWNER_ID identifies the built-in language inspection owner. */
LANGUAGE_STATE_UI_OWNER_ID :: ui.Owner_ID(10_006)
/* LANGUAGE_STATE_UI_MODEL_ID identifies the built-in language inspection model. */
LANGUAGE_STATE_UI_MODEL_ID :: ui.Model_ID(10_006)
/* LANGUAGE_STATE_UI_TARGET_GENERATION identifies the language inspection target contract. */
LANGUAGE_STATE_UI_TARGET_GENERATION :: u64(1)
/* LANGUAGE_STATE_CLOSE_ACTION identifies the read-only inspection row action. */
LANGUAGE_STATE_CLOSE_ACTION :: ui.List_Action_ID(1)
/* LANGUAGE_STATE_ROW_COUNT bounds the copied inspection inventory. */
LANGUAGE_STATE_ROW_COUNT :: 14
/* LANGUAGE_STATE_ROW_BYTES bounds one formatted inspection row. */
LANGUAGE_STATE_ROW_BYTES :: 512

@(private)
Language_State_Workflow_State :: struct {
	inspection:            language.Language_Selection_Inspection,
	provider:              language.Provider_Descriptor,
	provider_found:        bool,
	ready:                 bool,
	return_target:         editor_session.Visible_Target,
	position:              ui.List_View_Position,
	model_generation:      u64,
	next_model_generation: u64,
}

@(private)
language_state_visible_target :: proc() -> editor_session.Visible_Target {
	return editor_session.Visible_Target {
		kind = .UI_Root,
		ui = {
			owner_id = u64(LANGUAGE_STATE_UI_OWNER_ID),
			model_id = u64(LANGUAGE_STATE_UI_MODEL_ID),
			generation = LANGUAGE_STATE_UI_TARGET_GENERATION,
		},
	}
}

@(private)
language_state_workflow_reset :: proc(state: ^Language_State_Workflow_State) {
	if state == nil do return
	next_generation := state.next_model_generation
	state^ = {}
	state.next_model_generation = next_generation
}

@(private)
language_state_workflow_advance_generation :: proc(state: ^Language_State_Workflow_State) -> bool {
	if state == nil || state.next_model_generation == max(u64) do return false
	state.next_model_generation += 1
	state.model_generation = state.next_model_generation
	return true
}

@(private)
language_state_workflow_prepare :: proc(
	state: ^Language_State_Workflow_State,
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
			i32(LANGUAGE_STATE_ROW_COUNT - 1),
		)
		state.position.first_visible_item = min(
			state.position.first_visible_item,
			u32(LANGUAGE_STATE_ROW_COUNT - 1),
		)
	}
	return true, {}
}

@(private)
language_state_workflow_move :: proc(
	state: ^Language_State_Workflow_State,
	delta: i32,
) -> (changed, ok: bool, failure: ui.Failure) {
	if state == nil || !state.ready {
		return false, false, ui.Failure{operation = .Prepare, code = .Invalid_List_View}
	}
	next: ui.List_View_State
	next, changed, ok, failure = ui.list_view_move_current(
		ui.List_View_State {
			present = true,
			item_count = LANGUAGE_STATE_ROW_COUNT,
			position = state.position,
		},
		delta,
	)
	if ok do state.position = next.position
	return changed, ok, failure
}

@(private)
language_state_list_definitions :: proc(
	state: ^Language_State_Workflow_State,
	profile: ui.Renderer_Profile,
	allocator: runtime.Allocator,
) -> (items: []ui.List_Item_Definition, storage: []u8, ok: bool) {
	if state == nil || !state.ready || state.model_generation == 0 || allocator.procedure == nil {
		return nil, nil, false
	}
	items_error: runtime.Allocator_Error
	items, items_error = make([]ui.List_Item_Definition, LANGUAGE_STATE_ROW_COUNT, allocator)
	if items_error != nil do return nil, nil, false
	storage_error: runtime.Allocator_Error
	storage, storage_error = make(
		[]u8,
		LANGUAGE_STATE_ROW_COUNT * LANGUAGE_STATE_ROW_BYTES,
		allocator,
	)
	if storage_error != nil {
		delete(items, allocator)
		return nil, nil, false
	}
	inspection := &state.inspection
	provider := &state.provider
	language_name := string(inspection.association.language.name.bytes[:inspection.association.language.name.length])
	association := string(inspection.association.value.bytes[:inspection.association.value.length])
	provider_name := "unavailable"
	parser_name := "unavailable"
	provenance := "unavailable"
	is_jan := inspection.association.language.id == language.FACTORY_JAN_LANGUAGE_ID
	if state.provider_found {
		provider_name = string(provider.name.bytes[:provider.name.length])
		parser_name = string(provider.parser_name.bytes[:provider.parser_name.length])
		provenance = string(provider.provenance.bytes[:provider.provenance.length])
	}
	for index in 0 ..< LANGUAGE_STATE_ROW_COUNT {
		row_storage := storage[index * LANGUAGE_STATE_ROW_BYTES:(index + 1) * LANGUAGE_STATE_ROW_BYTES]
		row: string
		switch index {
		case 0:
			row = fmt.bprintf(row_storage, "Language: %s id=%d@%d association=%v %q buffer=%d document=%d", language_name, inspection.association.language.id, inspection.association.language.generation, inspection.association.source, association, inspection.buffer_id, inspection.document_id)
		case 1:
			row = fmt.bprintf(row_storage, "Selection: %v registry=%d@%d generation=%d active=%d@%d factory=%d@%d", inspection.selection.state, inspection.selection.registry_id, inspection.selection.registry_generation, inspection.selection_generation, inspection.selection.active.provider_id, inspection.selection.active.provider_generation, inspection.selection.factory.provider_id, inspection.selection.factory.provider_generation)
		case 2:
			row = fmt.bprintf(row_storage, "Provider: %s kind=%v state=%v parser=%s grammar-abi=%d", provider_name, provider.kind, provider.state, parser_name, provider.grammar_abi)
		case 3:
			if is_jan {
				capabilities := language.jan_capability_availability()
				future_count := 0
				for capability in capabilities do if capability.class == .Future_Stage do future_count += 1
				row = fmt.bprintf(row_storage, "Baseline: %s syntax=%s future-stage-capabilities=%d", language.JAN_BASELINE_NAME, language.JAN_ORG_SYNTAX_VERSION, future_count)
			} else {
				row = fmt.bprintf(row_storage, "Provider capabilities: %v provenance=%s", provider.capabilities, provenance)
			}
		case 4:
			row = fmt.bprintf(row_storage, "Revisions: confirmed=%d parse=%d syntax=%d", inspection.confirmed_revision, inspection.parse_snapshot.source_revision, inspection.syntax_snapshot.source_revision)
		case 5:
			row = fmt.bprintf(row_storage, "Parser: lifecycle=%v status=%v parser-generation=%d tree-generation=%d", inspection.parser_lifecycle, inspection.analysis_status, inspection.parse_snapshot.parser_generation, inspection.parse_snapshot.tree_generation)
		case 6:
			row = fmt.bprintf(row_storage, "Query: provider-generation=%d query-generation=%d syntax-generation=%d", inspection.parse_snapshot.provider.provider_generation, inspection.parse_snapshot.query_generation, inspection.syntax_snapshot.generation)
		case 7:
			row = fmt.bprintf(row_storage, "Syntax: roles=%d captures=%d spans=%d", int(language.Syntax_Role.Variable_Parameter), inspection.usage.captures, inspection.syntax_snapshot.span_count)
		case 8:
			row = fmt.bprintf(row_storage, "Styles: factory semantic roles=%d color=%v attributes=%v", int(language.Syntax_Role.Variable_Parameter), profile.color, profile.attributes)
		case 9:
			row = fmt.bprintf(row_storage, "Renderer capabilities: %v unicode=%d geometry=%dx%d cells=%d", profile.capabilities, profile.unicode_profile, profile.max_columns, profile.max_rows, profile.max_cells)
		case 10:
			row = fmt.bprintf(row_storage, "Usage retained bytes: source=%d tree=%d query=%d spans=%d", inspection.usage.retained_source_bytes, inspection.usage.retained_tree_bytes, inspection.usage.retained_query_bytes, inspection.usage.retained_span_bytes)
		case 11:
			if is_jan {
				limits := language.DEFAULT_JAN_RESOURCE_LIMITS
				row = fmt.bprintf(row_storage, "Jan limits: source=%d diagnostics=%d inspection=%d candidate-ns=%d", limits.source_bytes, limits.diagnostics, limits.inspection_bytes, limits.candidate_nanoseconds)
			} else {
				row = fmt.bprintf(row_storage, "Usage work: temporary=%d work=%d captures=%d spans=%d", inspection.usage.temporary_bytes, inspection.usage.work_bytes, inspection.usage.captures, inspection.usage.spans)
			}
		case 12:
			row = fmt.bprintf(row_storage, "Pending: kind=%v revision=%d work=%d cancellation-checks=%d refresh=%v", inspection.pending.kind, inspection.pending.source_revision, inspection.pending.work_bytes, inspection.pending.cancellation_checks, inspection.pending.refresh_requested)
		case 13:
			row = fmt.bprintf(row_storage, "Latest rejection: operation=%v code=%v revision=%d limit=%d actual=%d", inspection.latest_failure.operation, inspection.latest_failure.code, inspection.latest_failure.source_revision, inspection.latest_failure.limit, inspection.latest_failure.actual)
		}
		items[index] = ui.List_Item_Definition {
			id = ui.List_Item_ID(index + 1),
			text = row,
			action = {
				owner_id = LANGUAGE_STATE_UI_OWNER_ID,
				action_id = LANGUAGE_STATE_CLOSE_ACTION,
				generation = state.model_generation,
			},
		}
	}
	return items, storage, true
}

@(private)
command_context_present_language_state :: proc(
	commands: ^Command_Context,
	buffer: ^editor.Buffer,
	constraints: display.Viewport_Constraints,
) -> (Interaction_Result, App_Failure) {
	if commands == nil || buffer == nil || !syntax_workflow_is_live(commands.syntax_workflow) {
		return {}, App_Failure{stage = .Command_Dispatch}
	}
	visible, visible_ok, visible_failure := editor_session.session_visible_target(
		commands.session_owner,
		commands.session_handle,
	)
	if !visible_ok || visible.kind != .Primary_View {
		return {}, App_Failure{stage = .Session_Access, editor_session = visible_failure}
	}
	inspection, provider, provider_found, inspected := syntax_workflow_inspect_buffer(
		commands.syntax_workflow,
		buffer,
	)
	if !inspected do return {}, App_Failure{stage = .Command_Dispatch}
	state := &commands.language_state_workflow
	language_state_workflow_reset(state)
	state.inspection = inspection
	state.provider = provider
	state.provider_found = provider_found
	state.ready = true
	state.return_target = visible
	if !language_state_workflow_advance_generation(state) {
		language_state_workflow_reset(state)
		return {}, App_Failure{stage = .UI, ui = {operation = .Prepare, code = .Generation_Limit}}
	}
	if prepared, prepare_failure := language_state_workflow_prepare(
		state,
		constraints.height_rows,
	); !prepared {
		language_state_workflow_reset(state)
		return {}, App_Failure{stage = .UI, ui = prepare_failure}
	}
	target := language_state_visible_target()
	_, _, presented, present_failure := editor_session.session_present_ui(
		commands.session_owner,
		commands.session_handle,
		target.ui,
	)
	if !presented {
		language_state_workflow_reset(state)
		return {}, App_Failure{stage = .Session_Access, editor_session = present_failure}
	}
	commands.pending = {}
	commands.diagnostic_length = 0
	return Interaction_Result{changed = true}, {}
}

@(private)
present_language_state_ui :: proc(
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
	state := &commands.language_state_workflow
	if prepared, prepare_failure := language_state_workflow_prepare(state, content_rows); !prepared {
		return App_Failure{stage = .UI, ui = prepare_failure}
	}
	if map_failure := command_context_sync_list_map(commands, .Language_State);
	   map_failure.stage != .None {
		return map_failure
	}
	registry, registry_ok, registry_failure := command_context_ui_registry(commands)
	if !registry_ok do return registry_failure
	profile, profile_ok := terminal.renderer_ui_profile(renderer)
	if !profile_ok do return App_Failure{stage = .Presentation, terminal = {code = .Invalid_Renderer}}
	definitions, text_storage, definitions_ok := language_state_list_definitions(
		state,
		profile,
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
	view, projected, projection_failure := ui.proposal_project_list_view(
		&proposal,
		ui.List_Projection_Request {
			model = {
				owner_id = LANGUAGE_STATE_UI_OWNER_ID,
				model_id = LANGUAGE_STATE_UI_MODEL_ID,
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
			owner_id = LANGUAGE_STATE_UI_OWNER_ID,
			view = view,
			focusable = true,
			visible = true,
			input_context = 3_006,
			keymap_context = 4_006,
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
dispatch_language_state_list_input :: proc(
	commands: ^Command_Context,
	input: interaction.Input,
	constraints: display.Viewport_Constraints,
) -> (Interaction_Result, App_Failure) {
	state := &commands.language_state_workflow
	if prepared, prepare_failure := language_state_workflow_prepare(
		state,
		constraints.height_rows,
	); !prepared {
		return {}, App_Failure{stage = .UI, ui = prepare_failure}
	}
	if map_failure := command_context_sync_list_map(commands, .Language_State);
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
		changed, moved, move_failure := language_state_workflow_move(state, delta)
		if !moved do return {}, App_Failure{stage = .UI, ui = move_failure}
		return Interaction_Result{changed = changed}, {}
	}
	if contextual_route == .Component_Close || command_metadata_is_native(metadata, .Keyboard_Quit) {
		return command_context_leave_language_state(commands)
	}
	return {}, {}
}

@(private)
command_context_leave_language_state :: proc(
	commands: ^Command_Context,
) -> (Interaction_Result, App_Failure) {
	return_target := commands.language_state_workflow.return_target
	command_context_deactivate_context_map(commands, .Completed)
	language_state_workflow_reset(&commands.language_state_workflow)
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
