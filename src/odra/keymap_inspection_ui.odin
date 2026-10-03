// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../display"
import "../command"
import "../editor_session"
import "../interaction"
import terminal "../terminal"
import "../ui"
import "base:runtime"

/* KEYMAP_INSPECTION_UI_OWNER_ID identifies the built-in inspection projection owner. */
KEYMAP_INSPECTION_UI_OWNER_ID :: ui.Owner_ID(10_004)
/* KEYMAP_INSPECTION_UI_MODEL_ID identifies the built-in inspection list model. */
KEYMAP_INSPECTION_UI_MODEL_ID :: ui.Model_ID(10_004)
/* KEYMAP_INSPECTION_UI_TARGET_GENERATION identifies the inspection target contract. */
KEYMAP_INSPECTION_UI_TARGET_GENERATION :: u64(1)
/* KEYMAP_INSPECTION_CLOSE_ACTION identifies the read-only inspection row action. */
KEYMAP_INSPECTION_CLOSE_ACTION :: ui.List_Action_ID(1)
/* KEYMAP_HELP_ROW_BYTES bounds text copied for one help row. */
KEYMAP_HELP_ROW_BYTES :: 256

@(private)
Keymap_Inspection_Presentation :: enum u8 {
	Full,
	Concise,
	Help,
	Info,
	Variables,
	Tutorial,
}

@(private)
Keymap_Inspection_Workflow_State :: struct {
	inspection:       interaction.Inspection_Result,
	catalog:          interaction.Command_Catalog,
	return_target:    editor_session.Visible_Target,
	position:         ui.List_View_Position,
	model_generation: u64,
	next_model_generation: u64,
	presentation:     Keymap_Inspection_Presentation,
}

@(private)
keymap_inspection_is_help :: proc(state: ^Keymap_Inspection_Workflow_State) -> bool {
	return state != nil && state.presentation >= .Help
}

@(private)
keymap_inspection_item_count :: proc(state: ^Keymap_Inspection_Workflow_State) -> u32 {
	if state == nil do return 0
	switch state.presentation {
	case .Help: return 11
	case .Info: return 8
	case .Variables: return 8
	case .Tutorial: return 12
	case .Full, .Concise: return u32(max(len(state.inspection.records), 1))
	}
	return 0
}

@(private)
keymap_inspection_visible_target :: proc() -> editor_session.Visible_Target {
	return editor_session.Visible_Target {
		kind = .UI_Root,
		ui = {
			owner_id = u64(KEYMAP_INSPECTION_UI_OWNER_ID),
			model_id = u64(KEYMAP_INSPECTION_UI_MODEL_ID),
			generation = KEYMAP_INSPECTION_UI_TARGET_GENERATION,
		},
	}
}

@(private)
command_context_help_topic :: proc(
	route: command.Native_Route,
) -> (Keymap_Inspection_Presentation, bool) {
	#partial switch route {
	case .Help_About_Help: return .Help, true
	case .Info: return .Info, true
	case .Describe_Variable: return .Variables, true
	case .Open_Tutorial: return .Tutorial, true
	case: return .Full, false
	}
}

@(private)
keymap_inspection_workflow_reset :: proc(state: ^Keymap_Inspection_Workflow_State) {
	if state == nil do return
	next_model_generation := state.next_model_generation
	if state.inspection.state != nil && !state.inspection.closed {
		_ = interaction.inspection_result_close(&state.inspection)
	}
	if state.catalog.state != nil {
		_ = interaction.command_catalog_close(&state.catalog)
	}
	state^ = {}
	state.next_model_generation = next_model_generation
}

@(private)
keymap_inspection_workflow_advance_generation :: proc(
	state: ^Keymap_Inspection_Workflow_State,
) -> bool {
	if state == nil || state.next_model_generation == max(u64) do return false
	state.next_model_generation += 1
	state.model_generation = state.next_model_generation
	return true
}

@(private)
command_context_present_help :: proc(
	commands: ^Command_Context,
	presentation: Keymap_Inspection_Presentation,
	constraints: display.Viewport_Constraints,
) -> (Interaction_Result, App_Failure) {
	if commands == nil || presentation < .Help {
		return {}, App_Failure{stage = .Command_Dispatch}
	}
	visible, visible_ok, visible_failure := editor_session.session_visible_target(
		commands.session_owner,
		commands.session_handle,
	)
	if !visible_ok || visible.kind != .Primary_View {
		return {}, App_Failure{stage = .Session_Access, editor_session = visible_failure}
	}
	state := &commands.keymap_inspection_workflow
	keymap_inspection_workflow_reset(state)
	state.presentation = presentation
	state.return_target = visible
	if !keymap_inspection_workflow_advance_generation(state) {
		keymap_inspection_workflow_reset(state)
		return {}, App_Failure{stage = .UI, ui = {operation = .Prepare, code = .Generation_Limit}}
	}
	if prepared, prepare_failure := keymap_inspection_workflow_prepare(
		state,
		constraints.height_rows,
	); !prepared {
		keymap_inspection_workflow_reset(state)
		return {}, App_Failure{stage = .UI, ui = prepare_failure}
	}
	_, _, presented, present_failure := editor_session.session_present_ui(
		commands.session_owner,
		commands.session_handle,
		keymap_inspection_visible_target().ui,
	)
	if !presented {
		keymap_inspection_workflow_reset(state)
		return {}, App_Failure{stage = .Session_Access, editor_session = present_failure}
	}
	commands.pending = {}
	commands.diagnostic_length = 0
	return Interaction_Result{changed = true}, {}
}

@(private)
keymap_inspection_workflow_prepare :: proc(
	state: ^Keymap_Inspection_Workflow_State,
	viewport_items: u32,
) -> (ok: bool, failure: ui.Failure) {
	if state == nil || state.model_generation == 0 || viewport_items == 0 ||
	   viewport_items > ui.MAX_LIST_ITEMS {
		return false, ui.Failure{operation = .Prepare, code = .Invalid_List_View}
	}
	if !keymap_inspection_is_help(state) &&
	   (state.inspection.state == nil || state.inspection.closed || state.catalog.state == nil) {
		return false, ui.Failure{operation = .Prepare, code = .Invalid_List_View}
	}
	item_count := keymap_inspection_item_count(state)
	if item_count == 0 {
		return false, ui.Failure{operation = .Prepare, code = .Invalid_List_View}
	}
	if item_count > ui.MAX_LIST_ITEMS {
		return false, ui.Failure {
			operation = .Prepare,
			code = .List_Item_Limit,
			limit = u64(ui.MAX_LIST_ITEMS),
			actual = u64(item_count),
		}
	}
	if state.position.presentation_generation == 0 {
		state.position = ui.List_View_Position {
			presentation_generation = 1,
			selection_owner = .View,
			current_item = 0,
			first_visible_item = 0,
			viewport_items = viewport_items,
		}
		return true, {}
	}
	list_state := ui.List_View_State {
		present = true,
		item_count = item_count,
		position = state.position,
	}
	next, _, resized, resize_failure := ui.list_view_resize(list_state, viewport_items)
	if !resized do return false, resize_failure
	state.position = next.position
	return true, {}
}

@(private)
keymap_inspection_workflow_move :: proc(
	state: ^Keymap_Inspection_Workflow_State,
	delta: i32,
) -> (changed, ok: bool, failure: ui.Failure) {
	if state == nil || keymap_inspection_item_count(state) == 0 ||
	   (!keymap_inspection_is_help(state) &&
	    (state.inspection.state == nil || state.inspection.closed)) {
		return false, false, ui.Failure{operation = .Navigate, code = .Invalid_List_View}
	}
	list_state := ui.List_View_State {
		present = true,
		item_count = keymap_inspection_item_count(state),
		position = state.position,
	}
	next: ui.List_View_State
	next, changed, ok, failure = ui.list_view_move_current(list_state, delta)
	if ok do state.position = next.position
	return
}

@(private)
keymap_help_row :: proc(
	presentation: Keymap_Inspection_Presentation,
	index: int,
) -> string {
	switch presentation {
	case .Help:
		rows := [?]string {
			"Odra Help — q or C-g closes this view",
			"C-h ?  list help and discovery commands",
			"C-h a  search commands by name or description, then inspect one",
			"C-h i  open the built-in User Guide index",
			"C-h f  select and describe a registered interactive command",
			"C-h v  inspect configuration owners and discovery commands",
			"C-h m  inspect the active interaction profile and contextual maps",
			"C-h s  inspect the active structural syntax provider",
			"C-h b  list active bindings",
			"C-h k  describe a key sequence",
			"C-h t  open the built-in editing tutorial",
		}
		if index >= 0 && index < len(rows) do return rows[index]
	case .Info:
		rows := [?]string {
			"Odra User Guide — https://userguide.odraeditor.org/",
			"1. Start: launch Odra, open files, Dirs, Projects, and Workspaces",
			"2. Edit: navigate, select, transform, undo, save, and recover",
			"3. Understand: language support, diagnostics, structure, and themes",
			"4. Organize: Jan documents, Roman knowledge, Projects, and navigation",
			"5. Extend: packages, language bundles, commands, and interaction profiles",
			"6. Operate: terminals, version control, catalogs, and troubleshooting",
			"Use C-h ? for local discovery and M-x for the complete command catalog.",
		}
		if index >= 0 && index < len(rows) do return rows[index]
	case .Variables:
		rows := [?]string {
			"Odra configuration uses explicit owners rather than one global variable namespace.",
			"Interaction profile: select-interaction-profile; describe-keymap-state",
			"Theme: select-theme; describe-theme",
			"Language support: describe-language-state; describe-language-support",
			"Language services: describe-language-service; language-support-doctor",
			"Packages: package-list; package-describe; package-doctor",
			"Project state: describe-project; project-command-menu",
			"Personal commands: reload-personal-commands; describe-bindings",
		}
		if index >= 0 && index < len(rows) do return rows[index]
	case .Tutorial:
		rows := [?]string {
			"Odra Tutorial — perform these steps in any disposable text buffer",
			"1. Move with arrows or C-b, C-f, C-p, and C-n.",
			"2. Jump to line boundaries with C-a and C-e.",
			"3. Set the mark with C-Space, move, then copy with M-w.",
			"4. Kill the active region with C-w and restore it with C-y.",
			"5. Undo with C-/ and redo with M-/.",
			"6. Search forward with C-s; use C-g to cancel pending input.",
			"7. Save with C-x C-s and open a file with C-x C-f.",
			"8. Split below with C-x 2, move with C-x o, and close with C-x 0.",
			"9. Run M-x, type part of a command name, and press Enter.",
			"10. Use C-h k followed by a key sequence to inspect its command.",
			"Use C-h ? to continue discovery or q to return to the buffer.",
		}
		if index >= 0 && index < len(rows) do return rows[index]
	case .Full, .Concise:
	}
	return ""
}

@(private)
keymap_inspection_list_definitions :: proc(
	state: ^Keymap_Inspection_Workflow_State,
	allocator: runtime.Allocator,
) -> (items: []ui.List_Item_Definition, storage: []u8, ok: bool) {
	if state == nil || state.model_generation == 0 || allocator.procedure == nil {
		return nil, nil, false
	}
	if !keymap_inspection_is_help(state) &&
	   (state.inspection.state == nil || state.inspection.closed || state.catalog.state == nil) {
		return nil, nil, false
	}
	row_count := int(keymap_inspection_item_count(state))
	if row_count == 0 do return nil, nil, false
	definitions, definitions_error := make([]ui.List_Item_Definition, row_count, allocator)
	if definitions_error != nil do return nil, nil, false
	text, text_error := make(
		[]u8,
		row_count * max(interaction.MAX_KEYMAP_INSPECTION_ROW_BYTES, KEYMAP_HELP_ROW_BYTES),
		allocator,
	)
	if text_error != nil {
		delete(definitions, allocator)
		return nil, nil, false
	}
	for index in 0 ..< row_count {
		row_bytes := max(interaction.MAX_KEYMAP_INSPECTION_ROW_BYTES, KEYMAP_HELP_ROW_BYTES)
		row_storage := text[
			index * row_bytes:
			(index + 1) * row_bytes
		]
		row := ""
		if keymap_inspection_is_help(state) {
			row = keymap_help_row(state.presentation, index)
		} else if len(state.inspection.records) > 0 {
			if state.presentation == .Concise {
				row = interaction.keymap_help_record_text(
					state.inspection.records[index],
					&state.catalog,
					row_storage,
				)
			} else {
				row = interaction.keymap_inspection_record_text(
					state.inspection.records[index],
					&state.inspection,
					&state.catalog,
					row_storage,
				)
			}
		} else {
			row = "No matching keymap definitions."
		}
		if len(row) == 0 {
			delete(definitions, allocator)
			delete(text, allocator)
			return nil, nil, false
		}
		if keymap_inspection_is_help(state) || len(state.inspection.records) == 0 {
			copy(row_storage, transmute([]u8)row)
			row = string(row_storage[:len(row)])
		}
		definitions[index] = ui.List_Item_Definition {
			id = ui.List_Item_ID(index + 1),
			text = row,
			action = {
				owner_id = KEYMAP_INSPECTION_UI_OWNER_ID,
				action_id = KEYMAP_INSPECTION_CLOSE_ACTION,
				generation = state.model_generation,
			},
		}
	}
	return definitions, text, true
}

@(private)
present_keymap_inspection_ui :: proc(
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
	state := &commands.keymap_inspection_workflow
	if prepared, prepare_failure := keymap_inspection_workflow_prepare(
		state,
		content_rows,
	); !prepared {
		return App_Failure{stage = .UI, ui = prepare_failure}
	}
	if map_failure := command_context_sync_list_map(commands, .Keymap_Inspection);
	   map_failure.stage != .None {
		return map_failure
	}
	definitions, text_storage, definitions_ok := keymap_inspection_list_definitions(
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
				owner_id = KEYMAP_INSPECTION_UI_OWNER_ID,
				model_id = KEYMAP_INSPECTION_UI_MODEL_ID,
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
			owner_id = KEYMAP_INSPECTION_UI_OWNER_ID,
			view = view,
			focusable = true,
			visible = true,
			input_context = 3_004,
			keymap_context = 4_004,
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

@(private)
dispatch_keymap_inspection_list_input :: proc(
	commands: ^Command_Context,
	input: interaction.Input,
	constraints: display.Viewport_Constraints,
) -> (Interaction_Result, App_Failure) {
	state := &commands.keymap_inspection_workflow
	if prepared, prepare_failure := keymap_inspection_workflow_prepare(
		state,
		constraints.height_rows,
	); !prepared {
		return {}, App_Failure{stage = .UI, ui = prepare_failure}
	}
	if map_failure := command_context_sync_list_map(commands, .Keymap_Inspection);
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
		changed, moved, move_failure := keymap_inspection_workflow_move(state, delta)
		if !moved do return {}, App_Failure{stage = .UI, ui = move_failure}
		return Interaction_Result{changed = changed}, {}
	}
	if contextual_route == .Component_Close || command_metadata_is_native(metadata, .Keyboard_Quit) {
		return command_context_leave_keymap_inspection(commands)
	}
	if command_metadata_is_native(metadata, .Execute_Extended_Command) {
		left, leave_failure := command_context_leave_keymap_inspection(commands)
		if leave_failure.stage != .None do return {}, leave_failure
		access, access_ok, access_failure := editor_session.session_active_entry_access(
			commands.session_owner,
			commands.session_handle,
		)
		if !access_ok {
			return {}, App_Failure{stage = .Session_Access, editor_session = access_failure}
		}
		entry, borrowed, borrow_failure := editor_session.entry_access_borrow(access)
		if !borrowed {
			return {}, App_Failure{stage = .Session_Access, editor_session = borrow_failure}
		}
		command_context_bind_entry(commands, access.entry, entry)
		result, present_failure := command_context_present_command_navigation(
			commands,
			entry.buffer,
			entry.view_registry,
			entry.primary_view,
			constraints,
		)
		_, reconciled, reconcile_failure := editor_session.entry_access_reconcile(access)
		if !reconciled {
			return {}, App_Failure{stage = .Session_Access, editor_session = reconcile_failure}
		}
		result.changed = result.changed || left.changed
		return result, present_failure
	}
	return {}, {}
}

@(private)
command_context_leave_keymap_inspection :: proc(
	commands: ^Command_Context,
) -> (Interaction_Result, App_Failure) {
	return_target := commands.keymap_inspection_workflow.return_target
	command_context_deactivate_context_map(commands, .Completed)
	keymap_inspection_workflow_reset(&commands.keymap_inspection_workflow)
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
