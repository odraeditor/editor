// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../command"
import "../display"
import "../editor_session"
import "../interaction"
import terminal "../terminal"
import "../theme"
import "../ui"
import "base:runtime"
import "core:fmt"

/* THEME_INSPECTION_UI_OWNER_ID identifies the built-in theme inspection owner. */
THEME_INSPECTION_UI_OWNER_ID :: ui.Owner_ID(10_007)
/* THEME_INSPECTION_UI_MODEL_ID identifies the built-in theme inspection model. */
THEME_INSPECTION_UI_MODEL_ID :: ui.Model_ID(10_007)
/* THEME_INSPECTION_UI_TARGET_GENERATION identifies the inspection target contract. */
THEME_INSPECTION_UI_TARGET_GENERATION :: u64(1)
/* THEME_INSPECTION_CLOSE_ACTION identifies the read-only inspection row action. */
THEME_INSPECTION_CLOSE_ACTION :: ui.List_Action_ID(1)
/* THEME_INSPECTION_SUMMARY_ROW_COUNT is the fixed registry summary size. */
THEME_INSPECTION_SUMMARY_ROW_COUNT :: 14
/* THEME_INSPECTION_PROFILE_SUMMARY_ROW_COUNT is the fixed presentation profile summary size. */
THEME_INSPECTION_PROFILE_SUMMARY_ROW_COUNT :: 11
/* THEME_INSPECTION_PROFILE_SLOT_ROW_COUNT covers every semantic chrome slot. */
THEME_INSPECTION_PROFILE_SLOT_ROW_COUNT :: ui.PRESENTATION_CHROME_SLOT_COUNT
/* THEME_INSPECTION_STYLE_ROW_START follows theme and presentation profile inspection rows. */
THEME_INSPECTION_STYLE_ROW_START :: THEME_INSPECTION_SUMMARY_ROW_COUNT +
	THEME_INSPECTION_PROFILE_SUMMARY_ROW_COUNT + THEME_INSPECTION_PROFILE_SLOT_ROW_COUNT
/* THEME_INSPECTION_ROW_COUNT includes one row for every current semantic style. */
THEME_INSPECTION_ROW_COUNT :: THEME_INSPECTION_STYLE_ROW_START + theme.CURRENT_STYLE_ROLE_COUNT
/* THEME_INSPECTION_ROW_BYTES bounds one formatted inspection row. */
THEME_INSPECTION_ROW_BYTES :: 512

@(private)
Theme_Inspection_Workflow_State :: struct {
	inspection:            theme.Registry_Inspection,
	active:                theme.Definition_Descriptor,
	fallback:              theme.Definition_Descriptor,
	baseline:              theme.Definition_Descriptor,
	provider:              theme.Provider_Descriptor,
	styles:                [theme.MAX_STYLES]ui.Style_Definition,
	style_count:           u16,
	ready:                 bool,
	return_target:         editor_session.Visible_Target,
	position:              ui.List_View_Position,
	model_generation:      u64,
	next_model_generation: u64,
}

@(private)
theme_inspection_visible_target :: proc() -> editor_session.Visible_Target {
	return editor_session.Visible_Target {
		kind = .UI_Root,
		ui = {
			owner_id = u64(THEME_INSPECTION_UI_OWNER_ID),
			model_id = u64(THEME_INSPECTION_UI_MODEL_ID),
			generation = THEME_INSPECTION_UI_TARGET_GENERATION,
		},
	}
}

@(private)
theme_inspection_workflow_reset :: proc(state: ^Theme_Inspection_Workflow_State) {
	if state == nil do return
	next_generation := state.next_model_generation
	state^ = {}
	state.next_model_generation = next_generation
}

@(private)
theme_inspection_workflow_advance_generation :: proc(
	state: ^Theme_Inspection_Workflow_State,
) -> bool {
	if state == nil || state.next_model_generation == max(u64) do return false
	state.next_model_generation += 1
	state.model_generation = state.next_model_generation
	return true
}

@(private)
theme_inspection_workflow_prepare :: proc(
	state: ^Theme_Inspection_Workflow_State,
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
			i32(THEME_INSPECTION_ROW_COUNT - 1),
		)
		state.position.first_visible_item = min(
			state.position.first_visible_item,
			u32(THEME_INSPECTION_ROW_COUNT - 1),
		)
	}
	return true, {}
}

@(private)
theme_inspection_workflow_move :: proc(
	state: ^Theme_Inspection_Workflow_State,
	delta: i32,
) -> (changed, ok: bool, failure: ui.Failure) {
	if state == nil || !state.ready {
		return false, false, ui.Failure{operation = .Navigate, code = .Invalid_List_View}
	}
	next: ui.List_View_State
	next, changed, ok, failure = ui.list_view_move_current(
		ui.List_View_State {
			present = true,
			item_count = THEME_INSPECTION_ROW_COUNT,
			position = state.position,
		},
		delta,
	)
	if ok do state.position = next.position
	return
}

@(private)
theme_inspection_list_definitions :: proc(
	state: ^Theme_Inspection_Workflow_State,
	profile_inspection: ui.Presentation_Profile_Inspection,
	active_profile: ui.Presentation_Profile_Record,
	profile: ui.Renderer_Profile,
	allocator: runtime.Allocator,
) -> (items: []ui.List_Item_Definition, storage: []u8, ok: bool) {
	if state == nil || !state.ready || state.model_generation == 0 || allocator.procedure == nil {
		return nil, nil, false
	}
	items_error: runtime.Allocator_Error
	items, items_error = make([]ui.List_Item_Definition, THEME_INSPECTION_ROW_COUNT, allocator)
	if items_error != nil do return nil, nil, false
	storage_error: runtime.Allocator_Error
	storage, storage_error = make(
		[]u8,
		THEME_INSPECTION_ROW_COUNT * THEME_INSPECTION_ROW_BYTES,
		allocator,
	)
	if storage_error != nil {
		delete(items, allocator)
		return nil, nil, false
	}
	active_identity := theme.theme_name_string(&state.active.identity)
	active_display := theme.display_name_string(&state.active.display_name)
	fallback_identity := theme.theme_name_string(&state.fallback.identity)
	baseline_identity := theme.theme_name_string(&state.baseline.identity)
	provider_name := theme.provider_name_string(&state.provider.name)
	provenance := theme.provenance_text_string(&state.active.provenance)
	inspection := &state.inspection
	profile_scope := profile_inspection.scopes[0]
	profile_definition := active_profile.definition
	profile_name := ui.presentation_profile_text_view(&profile_definition.name)
	for index in 0 ..< THEME_INSPECTION_ROW_COUNT {
		row_storage := storage[index * THEME_INSPECTION_ROW_BYTES:(index + 1) * THEME_INSPECTION_ROW_BYTES]
		row: string
		switch index {
		case 0:
			row = fmt.bprintf(row_storage, "Selection: state=%v registry=%d@%d generation=%d", inspection.selection.state, inspection.selection.registry_id, inspection.selection.registry_generation, inspection.selection.selection_generation)
		case 1:
			row = fmt.bprintf(row_storage, "Active: %s [%s] definition=%d@%d", active_display, active_identity, state.active.handle.definition_id, state.active.handle.definition_generation)
		case 2:
			row = fmt.bprintf(row_storage, "Fallback: %s definition=%d@%d", fallback_identity, state.fallback.handle.definition_id, state.fallback.handle.definition_generation)
		case 3:
			row = fmt.bprintf(row_storage, "Safe baseline: %s definition=%d@%d", baseline_identity, state.baseline.handle.definition_id, state.baseline.handle.definition_generation)
		case 4:
			row = fmt.bprintf(row_storage, "Definition: state=%v styles=%d retained-bytes=%d provenance=%s", state.active.state, state.active.style_count, state.active.retained_bytes, provenance)
		case 5:
			row = fmt.bprintf(row_storage, "Provider: %s kind=%v state=%v id=%d@%d", provider_name, state.provider.kind, state.provider.state, state.provider.handle.provider_id, state.provider.handle.provider_generation)
		case 6:
			row = fmt.bprintf(row_storage, "Semantic roles: current=%d maximum=%d", theme.CURRENT_STYLE_ROLE_COUNT, theme.MAX_STYLES)
		case 7:
			row = fmt.bprintf(row_storage, "Renderer: id=%d color=%v attributes=%v capabilities=%v", profile.id, profile.color, profile.attributes, profile.capabilities)
		case 8:
			row = fmt.bprintf(row_storage, "Registry usage: providers=%d definitions=%d", inspection.usage.providers, inspection.usage.definitions)
		case 9:
			row = fmt.bprintf(row_storage, "Memory usage: retained=%d preparation-peak=%d inspection=%d", inspection.usage.retained_definition_bytes, inspection.usage.preparation_peak_bytes, inspection.usage.inspection_bytes)
		case 10:
			row = fmt.bprintf(row_storage, "Limits: providers=%d definitions=%d operations-per-turn=%d", inspection.limits.providers, inspection.limits.definitions, inspection.limits.operations_per_turn)
		case 11:
			row = fmt.bprintf(row_storage, "Memory limits: retained=%d proposal=%d preparation=%d inspection=%d", inspection.limits.retained_definition_bytes, inspection.limits.proposal_bytes, inspection.limits.preparation_bytes, inspection.limits.inspection_bytes)
		case 12:
			row = fmt.bprintf(row_storage, "Latest rejection: operation=%v code=%v", inspection.latest_failure.operation, inspection.latest_failure.code)
		case 13:
			row = fmt.bprintf(row_storage, "Rejection detail: provider=%d definition=%d limit=%d actual=%d", inspection.latest_failure.provider.provider_id, inspection.latest_failure.definition.definition_id, inspection.latest_failure.limit, inspection.latest_failure.actual)
		case 14:
			row = fmt.bprintf(row_storage, "Presentation selection: role=%v registry=%d@%d", profile_scope.role, profile_scope.registry_id, profile_scope.registry_generation)
		case 15:
			row = fmt.bprintf(row_storage, "Presentation profile: %s kind=%v id=%d@%d", profile_name, profile_definition.kind, active_profile.handle.profile_id, active_profile.handle.profile_generation)
		case 16:
			row = fmt.bprintf(row_storage, "Presentation factory: id=%d@%d selected=%d@%d", profile_scope.factory.profile_id, profile_scope.factory.profile_generation, profile_scope.selected.profile_id, profile_scope.selected.profile_generation)
		case 17:
			row = fmt.bprintf(row_storage, "Presentation spacing: margin=%d:%d padding=%d:%d", profile_definition.margin_rows, profile_definition.margin_columns, profile_definition.padding_rows, profile_definition.padding_columns)
		case 18:
			bounds := profile_definition.bounds
			row = fmt.bprintf(row_storage, "Presentation bounds: minimum=%d:%d preferred=%d:%d maximum=%d:%d", bounds.minimum_rows, bounds.minimum_columns, bounds.preferred_rows, bounds.preferred_columns, bounds.maximum_rows, bounds.maximum_columns)
		case 19:
			row = fmt.bprintf(row_storage, "Presentation policy: border=%v clipping=%v fallback=%v degradation=%v", profile_definition.border, profile_definition.clipping, profile_definition.popup_fallback, profile_definition.degradation)
		case 20:
			supported := profile_definition.required_capabilities & profile.capabilities ==
				profile_definition.required_capabilities
			row = fmt.bprintf(row_storage, "Presentation capabilities: required=%v supported=%v", profile_definition.required_capabilities, supported)
		case 21:
			stats := profile_inspection.stats
			row = fmt.bprintf(row_storage, "Presentation usage: live=%d factory=%d package=%d personal=%d retained=%d", stats.live_profiles, stats.factory_profiles, stats.package_profiles, stats.personal_profiles, stats.retained_bytes)
		case 22:
			row = fmt.bprintf(row_storage, "Presentation mappings: current=%d maximum=%d required=%v", profile_definition.mapping_count, ui.MAX_PRESENTATION_PROFILE_MAPPINGS, ui.presentation_profile_required_slots(profile_definition.role))
		case 23:
			rejection := profile_inspection.last_rejection
			row = fmt.bprintf(row_storage, "Presentation rejection: operation=%v code=%v profile=%d@%d", rejection.operation, rejection.code, rejection.profile.profile_id, rejection.profile.profile_generation)
		case 24:
			rejection := profile_inspection.last_rejection
			row = fmt.bprintf(row_storage, "Presentation rejection detail: role=%v slot=%v limit=%d actual=%d fallback-depth=%d", rejection.role, rejection.slot, rejection.limit, rejection.actual, rejection.fallback_depth)
		case 25 ..< THEME_INSPECTION_STYLE_ROW_START:
			slot := ui.Presentation_Chrome_Slot(index - 24)
			style_role, available := ui.presentation_profile_definition_style(&profile_definition, slot)
			required := slot in ui.presentation_profile_required_slots(profile_definition.role)
			row = fmt.bprintf(row_storage, "Presentation slot %v: style=%v required=%v available=%v", slot, style_role, required, available)
		case:
			style := state.styles[index - THEME_INSPECTION_STYLE_ROW_START]
			foreground_storage, background_storage: [32]u8
			lowered_foreground_storage, lowered_background_storage: [32]u8
			foreground := theme_inspection_color_text(style.foreground, foreground_storage[:])
			background := theme_inspection_color_text(style.background, background_storage[:])
			lowered_foreground, foreground_ok := terminal.renderer_color_value_format(
				style.foreground,
				profile.color,
				lowered_foreground_storage[:],
			)
			lowered_background, background_ok := terminal.renderer_color_value_format(
				style.background,
				profile.color,
				lowered_background_storage[:],
			)
			if !foreground_ok || !background_ok {
				delete(items, allocator)
				delete(storage, allocator)
				return nil, nil, false
			}
			row = fmt.bprintf(
				row_storage,
				"Role %v: attributes=%v foreground=%s -> %s background=%s -> %s",
				style.role,
				style.attributes,
				foreground,
				lowered_foreground,
				background,
				lowered_background,
			)
		}
		items[index] = ui.List_Item_Definition {
			id = ui.List_Item_ID(index + 1),
			text = row,
			action = {
				owner_id = THEME_INSPECTION_UI_OWNER_ID,
				action_id = THEME_INSPECTION_CLOSE_ACTION,
				generation = state.model_generation,
			},
		}
	}
	return items, storage, true
}

@(private)
theme_inspection_color_text :: proc(color: ui.Optional_SRGB_Color, output: []u8) -> string {
	if !color.present {
		copy(output, "default")
		return string(output[:len("default")])
	}
	return fmt.bprintf(
		output,
		"#%02X%02X%02X",
		color.color.red,
		color.color.green,
		color.color.blue,
	)
}

@(private)
command_context_present_theme_inspection :: proc(
	commands: ^Command_Context,
	constraints: display.Viewport_Constraints,
) -> (Interaction_Result, App_Failure) {
	visible, visible_ok, visible_failure := editor_session.session_visible_target(
		commands.session_owner,
		commands.session_handle,
	)
	if !visible_ok || visible.kind != .Primary_View {
		return {}, App_Failure{stage = .Session_Access, editor_session = visible_failure}
	}
	inspection, inspected, inspection_failure := theme.theme_registry_inspect(&commands.theme_registry)
	if !inspected {
		return {}, App_Failure{stage = .Theme_Access, theme = inspection_failure}
	}
	active, active_ok, active_failure := theme.theme_registry_definition(
		&commands.theme_registry,
		inspection.selection.active,
	)
	if !active_ok do return {}, App_Failure{stage = .Theme_Access, theme = active_failure}
	fallback, fallback_ok, fallback_failure := theme.theme_registry_definition(
		&commands.theme_registry,
		inspection.selection.fallback,
	)
	if !fallback_ok do return {}, App_Failure{stage = .Theme_Access, theme = fallback_failure}
	baseline, baseline_ok, baseline_failure := theme.theme_registry_definition(
		&commands.theme_registry,
		inspection.selection.baseline,
	)
	if !baseline_ok do return {}, App_Failure{stage = .Theme_Access, theme = baseline_failure}
	provider, provider_ok, provider_failure := theme.theme_registry_provider(
		&commands.theme_registry,
		active.descriptor.provider,
	)
	if !provider_ok do return {}, App_Failure{stage = .Theme_Access, theme = provider_failure}
	state := &commands.theme_inspection_workflow
	theme_inspection_workflow_reset(state)
	state.inspection = inspection
	state.active = active.descriptor
	state.fallback = fallback.descriptor
	state.baseline = baseline.descriptor
	state.provider = provider
	copy(state.styles[:], active.styles)
	state.style_count = u16(len(active.styles))
	state.ready = true
	state.return_target = visible
	if !theme_inspection_workflow_advance_generation(state) {
		theme_inspection_workflow_reset(state)
		return {}, App_Failure{stage = .UI, ui = {operation = .Prepare, code = .Generation_Limit}}
	}
	if prepared, prepare_failure := theme_inspection_workflow_prepare(
		state,
		constraints.height_rows,
	); !prepared {
		theme_inspection_workflow_reset(state)
		return {}, App_Failure{stage = .UI, ui = prepare_failure}
	}
	target := theme_inspection_visible_target()
	_, _, presented, present_failure := editor_session.session_present_ui(
		commands.session_owner,
		commands.session_handle,
		target.ui,
	)
	if !presented {
		theme_inspection_workflow_reset(state)
		return {}, App_Failure{stage = .Session_Access, editor_session = present_failure}
	}
	commands.pending = {}
	commands.diagnostic_length = 0
	return Interaction_Result{changed = true}, {}
}

@(private)
present_theme_inspection_ui :: proc(
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
	state := &commands.theme_inspection_workflow
	if prepared, prepare_failure := theme_inspection_workflow_prepare(state, content_rows); !prepared {
		return App_Failure{stage = .UI, ui = prepare_failure}
	}
	if map_failure := command_context_sync_list_map(commands, .Theme_Inspection);
	   map_failure.stage != .None {
		return map_failure
	}
	registry, registry_ok, registry_failure := command_context_ui_registry(commands)
	if !registry_ok do return registry_failure
	profile, profile_ok := terminal.renderer_ui_profile(renderer)
	if !profile_ok do return App_Failure{stage = .Presentation, terminal = {code = .Invalid_Renderer}}
	profile_inspection, profiles_inspected, profile_inspection_failure :=
		ui.presentation_profile_registry_inspect(&commands.presentation_profiles)
	if !profiles_inspected {
		return presentation_profile_app_failure(profile_inspection_failure)
	}
	active_profile, active_profile_ok, active_profile_failure :=
		command_context_contextual_presentation_profile(commands)
	if !active_profile_ok do return active_profile_failure
	definitions, text_storage, definitions_ok := theme_inspection_list_definitions(
		state,
		profile_inspection,
		active_profile,
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
				owner_id = THEME_INSPECTION_UI_OWNER_ID,
				model_id = THEME_INSPECTION_UI_MODEL_ID,
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
			owner_id = THEME_INSPECTION_UI_OWNER_ID,
			view = view,
			focusable = true,
			visible = true,
			input_context = 3_010,
			keymap_context = 4_010,
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
dispatch_theme_inspection_list_input :: proc(
	commands: ^Command_Context,
	input: interaction.Input,
	constraints: display.Viewport_Constraints,
) -> (Interaction_Result, App_Failure) {
	state := &commands.theme_inspection_workflow
	if prepared, prepare_failure := theme_inspection_workflow_prepare(
		state,
		constraints.height_rows,
	); !prepared {
		return {}, App_Failure{stage = .UI, ui = prepare_failure}
	}
	if map_failure := command_context_sync_list_map(commands, .Theme_Inspection);
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
		changed, moved, move_failure := theme_inspection_workflow_move(state, delta)
		if !moved do return {}, App_Failure{stage = .UI, ui = move_failure}
		return Interaction_Result{changed = changed}, {}
	}
	if contextual_route == .Component_Close || command_metadata_is_native(metadata, .Keyboard_Quit) {
		return command_context_leave_theme_inspection(commands)
	}
	return {}, {}
}

@(private)
command_context_leave_theme_inspection :: proc(
	commands: ^Command_Context,
) -> (Interaction_Result, App_Failure) {
	return_target := commands.theme_inspection_workflow.return_target
	command_context_deactivate_context_map(commands, .Completed)
	theme_inspection_workflow_reset(&commands.theme_inspection_workflow)
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
