// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../display"
import "../feedback_routing"
import "../interaction"
import "../ui"
import editor_view "../view"
import "core:fmt"

/* COMMAND_FEEDBACK_OWNER_ID identifies built-in passive and diagnostic status. */
COMMAND_FEEDBACK_OWNER_ID :: ui.Owner_ID(2_100)

/* Prompt_Input_Projection_Request describes one visual generation of a live prompt. */
Prompt_Input_Projection_Request :: struct {
	presentation_generation: u64,
	first_visible_byte:      u32,
	viewport_bytes:          u32,
}

@(private)
Transient_Input_Composition :: struct {
	root_node:    ui.Object_Handle,
	focus_surface: ui.Object_Handle,
	input_surface: ui.Object_Handle,
}

@(private)
prompt_mode_owner_id :: proc(mode: Prompt_Mode) -> u64 {
	if mode == .None do return 0
	return 2_000 + u64(mode)
}

@(private)
prompt_mode_projects_input :: proc(mode: Prompt_Mode) -> bool {
	switch mode {
	case .Save_Path, .Write_File_Path, .Insert_File_Path, .Navigation_Target,
	     .Find_File, .Find_File_Other_Pane, .Darek_Show_Directory,
	     .Switch_To_Buffer, .Kill_Buffer,
	     .Project_Create_Directory, .Project_Promote_Name,
	     .Terminal_Rename, .Terminal_Kill_Choice,
	     .Project_Search, .Named_Location_Name,
	     .Named_Slot_Input, .Named_Slot_Confirmation,
	     .Package_Catalog_Input, .Package_Catalog_Confirmation, .Result_Edit,
	     .Dir_Abandonment_Choice,
	     .Kill_File_Discard_Choice, .Kill_Unassociated_Choice,
	     .Kill_Save_Path, .Marked_Kill_Choice, .Project_Close_Choice, .Marked_Save_Path,
	     .Last_Pane_Exit_Choice, .Terminal_Exit_Choice, .Exit_Choice, .Exit_Save_Path, .Keymap_Sequence,
	     .Keymap_Command, .Keymap_Map, .Keyboard_Macro_Name, .Keyboard_Macro_Call,
	     .Shell_Command, .Async_Shell_Command, .Compile_Command,
	     .Incremental_Search, .Query_Replacement_Pattern,
	     .Query_Replacement_Replacement, .Query_Replacement_Response:
		return true
	case .None, .Find_Alternate_File:
		return false
	}
	return false
}

@(private)
prompt_mode_prompt_kind :: proc(mode: Prompt_Mode) -> interaction.Prompt_Kind {
	switch mode {
	case .Save_Path, .Write_File_Path, .Insert_File_Path, .Navigation_Target,
	     .Find_File, .Find_File_Other_Pane, .Darek_Show_Directory,
	     .Switch_To_Buffer, .Kill_Buffer,
	     .Project_Create_Directory, .Project_Promote_Name, .Terminal_Rename,
	     .Named_Location_Name,
	     .Named_Slot_Input, .Package_Catalog_Input,
	     .Kill_Save_Path, .Marked_Save_Path, .Exit_Save_Path,
	     .Keymap_Command, .Keymap_Map, .Keyboard_Macro_Name, .Keyboard_Macro_Call,
	     .Shell_Command, .Async_Shell_Command, .Compile_Command,
	     .Incremental_Search, .Project_Search, .Query_Replacement_Pattern,
	     .Query_Replacement_Replacement, .Result_Edit:
		return .Text_Entry
	case .Kill_File_Discard_Choice, .Kill_Unassociated_Choice, .Marked_Kill_Choice,
	     .Project_Close_Choice, .Last_Pane_Exit_Choice, .Terminal_Exit_Choice,
	     .Terminal_Kill_Choice, .Exit_Choice,
	     .Dir_Abandonment_Choice, .Named_Slot_Confirmation,
	     .Package_Catalog_Confirmation:
		return .Fixed_Choice
	case .None, .Find_Alternate_File, .Query_Replacement_Response, .Keymap_Sequence:
		return .Invalid
	}
	return .Invalid
}

@(private)
prompt_workflow_begin_projection :: proc(state: ^Prompt_Workflow_State, mode: Prompt_Mode) -> bool {
	if state == nil || !prompt_mode_projects_input(mode) ||
	   (prompt_mode_projects_input(state.mode) &&
	    state.projection_generation != ui.Model_Generation(0)) ||
	   state.next_projection_generation == ui.Model_Generation(max(u64)) {
		return false
	}
	state.next_projection_generation = ui.Model_Generation(u64(state.next_projection_generation) + 1)
	state.projection_generation = state.next_projection_generation
	state.mode = mode
	state.rejected = false
	return true
}

@(private)
prompt_workflow_advance_projection :: proc(state: ^Prompt_Workflow_State) -> bool {
	if state == nil || !prompt_mode_projects_input(state.mode) ||
	   state.projection_generation == ui.Model_Generation(0) ||
	   state.next_projection_generation == ui.Model_Generation(max(u64)) {
		return false
	}
	state.next_projection_generation = ui.Model_Generation(u64(state.next_projection_generation) + 1)
	state.projection_generation = state.next_projection_generation
	return true
}

@(private)
command_context_capture_prompt_focus :: proc(
	commands: ^Command_Context,
	input_surface: ui.Object_Handle,
) -> App_Failure {
	registry, registry_ok, registry_failure := command_context_ui_registry(commands)
	if !registry_ok do return registry_failure
	if commands.prompt_workflow.focus_captured {
		return App_Failure{stage = .UI, ui = {operation = .Capture_Focus, code = .Focus_Captured}}
	}
	captured, capture_failure := ui.registry_capture_focus(registry, input_surface)
	if !captured do return App_Failure{stage = .UI, ui = capture_failure}
	commands.prompt_workflow.focus_captured = true
	return {}
}

@(private)
command_context_release_prompt_focus :: proc(commands: ^Command_Context) {
	if commands == nil || !commands.prompt_workflow.focus_captured do return
	if commands.ui_registry.state != nil && !commands.ui_registry.closed {
		_, _, _ = ui.registry_release_focus(&commands.ui_registry)
	}
	commands.prompt_workflow.focus_captured = false
}

@(private)
proposal_project_prompt_input :: proc(
	proposal: ^ui.Proposal,
	commands: ^Command_Context,
	request: Prompt_Input_Projection_Request,
	view_registry: ^editor_view.Registry = nil,
	view: editor_view.View_Handle = {},
) -> (handle: ui.Object_Handle, ok: bool, failure: ui.Failure) {
	if proposal == nil || commands == nil ||
	   !prompt_mode_projects_input(commands.prompt_workflow.mode) ||
	   commands.prompt_workflow.projection_generation == ui.Model_Generation(0) {
		return {}, false, ui.Failure{operation = .Prepare, code = .Invalid_View}
	}
	mode := commands.prompt_workflow.mode
	value := ""
	choice_definitions: [5]ui.Input_Choice_Definition
	choice_count := 0
	if mode == .Query_Replacement_Response {
		if view_registry == nil {
			return {}, false, ui.Failure{operation = .Prepare, code = .Invalid_View}
		}
		state, state_ok, _ := editor_view.query_replacement_session_view(view_registry, view)
		if !state_ok || !state.present {
			return {}, false, ui.Failure{operation = .Prepare, code = .Invalid_View}
		}
		value = fmt.bprintf(commands.overlay_text[:], "%s -> %s", state.pattern, state.replacement)
		choice_names := [5]string {
			"[y/SPC] replace",
			"[n/DEL] skip",
			"[!] replace remaining",
			"[.] replace and exit",
			"[q/RET] quit",
		}
		for name, index in choice_names {
			choice_definitions[index] = ui.Input_Choice_Definition {
				id = ui.Input_Choice_ID(index + 1),
				name = name,
				action = {
					owner_id = ui.Owner_ID(prompt_mode_owner_id(mode)),
					action_id = ui.List_Action_ID(index + 1),
					generation = u64(commands.prompt_workflow.projection_generation),
				},
			}
		}
		choice_count = len(choice_names)
	} else if mode == .Keymap_Sequence {
		if commands.interaction_workflow.inspection_sequence.stroke_count > 0 {
			notation, notation_ok := interaction.key_sequence_notation(
				commands.interaction_workflow.inspection_sequence,
				commands.overlay_text[:],
			)
			if !notation_ok {
				return {}, false, ui.Failure{operation = .Prepare, code = .Invalid_View}
			}
			value = notation
		}
	} else {
		prompt_view, viewed, _ := interaction.prompt_view(&commands.prompt_workflow.prompt)
		if !viewed || prompt_view.status != .Active || prompt_view.kind != prompt_mode_prompt_kind(mode) {
			return {}, false, ui.Failure{operation = .Prepare, code = .Invalid_View}
		}
		value = prompt_view.text
		for choice, index in prompt_view.choices {
			choice_definitions[index] = ui.Input_Choice_Definition {
				id = ui.Input_Choice_ID(index + 1),
				name = choice.name,
				action = {
					owner_id = ui.Owner_ID(prompt_mode_owner_id(mode)),
					action_id = ui.List_Action_ID(index + 1),
					generation = u64(commands.prompt_workflow.projection_generation),
				},
			}
		}
		choice_count = len(prompt_view.choices)
	}
	validation := ui.Input_Validation_State.Valid
	if commands.prompt_workflow.rejected do validation = .Rejected
	return ui.proposal_project_input(
		proposal,
		ui.Input_Projection_Request {
			model = {
				owner_id = ui.Owner_ID(prompt_mode_owner_id(mode)),
				model_id = ui.Model_ID(mode),
				generation = commands.prompt_workflow.projection_generation,
			},
			presentation_generation = request.presentation_generation,
			backing_generation = u64(commands.prompt_workflow.projection_generation),
			cursor_offset = u32(len(value)),
			first_visible_byte = request.first_visible_byte,
			viewport_bytes = request.viewport_bytes,
			validation = validation,
		},
		value,
		choice_definitions[:choice_count],
	)
}

@(private)
prompt_input_choice_command :: proc(
	commands: ^Command_Context,
	action: ui.List_Action_Reference,
) -> (command_name: string, ok: bool) {
	if commands == nil || !prompt_mode_projects_input(commands.prompt_workflow.mode) ||
	   commands.prompt_workflow.projection_generation == ui.Model_Generation(0) ||
	   action.owner_id != ui.Owner_ID(prompt_mode_owner_id(commands.prompt_workflow.mode)) ||
	   action.generation != u64(commands.prompt_workflow.projection_generation) ||
	   action.action_id == ui.List_Action_ID(0) {
		return "", false
	}
	if commands.prompt_workflow.mode == .Query_Replacement_Response {
		command_names := [5]string {
			"prompt-choice-1",
			"prompt-choice-2",
			"prompt-choice-3",
			"query-replace-and-exit",
			"query-quit",
		}
		if u64(action.action_id) > u64(len(command_names)) do return "", false
		return command_names[int(action.action_id) - 1], true
	}
	prompt_view, viewed, _ := interaction.prompt_view(&commands.prompt_workflow.prompt)
	if !viewed || prompt_view.kind != .Fixed_Choice || prompt_view.status != .Active ||
	   u64(action.action_id) > u64(len(prompt_view.choices)) {
		return "", false
	}
	return prompt_view.choices[int(action.action_id) - 1].command_name, true
}

@(private)
transient_input_content_rows :: proc(
	commands: ^Command_Context,
	constraints: display.Viewport_Constraints,
) -> (rows: u32, ok: bool) {
	if constraints.height_rows == 0 do return 0, false
	if commands == nil || !transient_feedback_projects_root_edge(commands) {
		return constraints.height_rows, true
	}
	if constraints.height_rows < 2 do return 0, false
	return constraints.height_rows - 1, true
}

@(private)
command_feedback_content :: proc(commands: ^Command_Context) -> (
	content: string,
	role: ui.Style_Role,
	active: bool,
	ok: bool,
) {
	if commands == nil || prompt_mode_projects_input(commands.prompt_workflow.mode) {
		return "", .Invalid, false, false
	}
	if commands.diagnostic_length > 0 {
		diagnostic := string(commands.diagnostic[:commands.diagnostic_length])
		if projection, projected := command_context_feedback_projection(commands); projected {
			projected_content := feedback_routing.projection_content(&projection)
			if projected_content == diagnostic {
				return diagnostic, projection.style_role, true, true
			}
		}
		return diagnostic, .Diagnostic_Normal, true, true
	}
	if fallback_content, fallback_role, fallback := popup_fallback_view(&commands.popup_fallback); fallback {
		return fallback_content, fallback_role, true, true
	}
	label, text, overlay := command_context_overlay(commands, nil, {})
	if !overlay do return "", .Invalid, false, false
	if len(label) == 0 do return text, .Status_Normal, false, true
	message := fmt.bprintf(commands.feedback_content[:], "%s%s", label, text)
	return message, .Status_Normal, false, true
}

@(private)
transient_feedback_projects_root_edge :: proc(commands: ^Command_Context) -> bool {
	if commands == nil do return false
	if prompt_mode_projects_input(commands.prompt_workflow.mode) do return true
	_, _, _, present := command_feedback_content(commands)
	return present
}

@(private)
proposal_compose_command_feedback :: proc(
	proposal: ^ui.Proposal,
	commands: ^Command_Context,
	base_root, base_focus: ui.Object_Handle,
	constraints: display.Viewport_Constraints,
) -> (ok: bool, failure: ui.Failure) {
	if proposal == nil || constraints.height_rows < 2 || constraints.width_cells < 2 {
		return false, ui.Failure{operation = .Prepare, code = .Invalid_Layout}
	}
	content, role, active, present := command_feedback_content(commands)
	if !present {
		return false, ui.Failure{operation = .Prepare, code = .Invalid_Status_Region}
	}
	_, status_ok, status_failure := ui.proposal_add_status(
		proposal,
		ui.Status_Region_Descriptor {
			owner_id = COMMAND_FEEDBACK_OWNER_ID,
			placement = .Root_Edge,
			rows = 1,
			geometry = {
				row = i32(constraints.height_rows - 1),
				height = 1,
				width = i32(constraints.width_cells),
			},
			style_role = role,
			active = active,
		},
		content,
	)
	if !status_ok do return false, status_failure
	return ui.proposal_set_root(proposal, base_root, base_focus)
}

@(private)
proposal_compose_transient_input :: proc(
	proposal: ^ui.Proposal,
	commands: ^Command_Context,
	base_root, base_focus: ui.Object_Handle,
	constraints: display.Viewport_Constraints,
	profile: ui.Renderer_Profile_ID,
	view_registry: ^editor_view.Registry = nil,
	view: editor_view.View_Handle = {},
) -> (composition: Transient_Input_Composition, ok: bool, failure: ui.Failure) {
	if proposal == nil || commands == nil || !prompt_mode_projects_input(commands.prompt_workflow.mode) ||
	   constraints.height_rows < 2 || constraints.width_cells < 2 || profile == ui.Renderer_Profile_ID(0) {
		return {}, false, ui.Failure{operation = .Prepare, code = .Invalid_Layout}
	}
	label, label_ok := prompt_input_status_label(commands, view_registry, view)
	if !label_ok {
		return {}, false, ui.Failure{operation = .Prepare, code = .Invalid_Layout}
	}
	visible_label, label_cells, label_viewport_ok := transient_input_label_viewport(
		label,
		constraints.width_cells - 1,
	)
	if !label_viewport_ok {
		return {}, false, ui.Failure{operation = .Prepare, code = .Invalid_View}
	}
	label = visible_label
	input_width := constraints.width_cells - label_cells
	value, value_ok := prompt_input_value(commands, view_registry, view)
	if !value_ok do return {}, false, ui.Failure{operation = .Prepare, code = .Invalid_View}
	first_visible, viewport_bytes, viewport_ok := candidate_ui_input_viewport(value, input_width)
	if !viewport_ok do return {}, false, ui.Failure{operation = .Prepare, code = .Invalid_View}
	input_view, input_ok, input_failure := proposal_project_prompt_input(
		proposal,
		commands,
		Prompt_Input_Projection_Request {
			presentation_generation = u64(commands.prompt_workflow.projection_generation),
			first_visible_byte = first_visible,
			viewport_bytes = viewport_bytes,
		},
		view_registry,
		view,
	)
	if !input_ok do return {}, false, input_failure
	input_surface, surface_ok, surface_failure := ui.proposal_add_surface(
		proposal,
		ui.Surface_Descriptor {
			owner_id = ui.Owner_ID(prompt_mode_owner_id(commands.prompt_workflow.mode)),
			view = input_view,
			focusable = true,
			visible = true,
			input_context = 3_006,
			keymap_context = 4_006,
			required_profile = profile,
			geometry = {
				row = i32(constraints.height_rows - 1),
				column = i32(label_cells),
				height = 1,
				width = i32(input_width),
			},
		},
	)
	if !surface_ok do return {}, false, surface_failure
	input_node, node_ok, node_failure := ui.proposal_add_surface_node(proposal, input_surface)
	if !node_ok do return {}, false, node_failure
	root_node, split_ok, split_failure := ui.proposal_add_split(
		proposal,
		base_root,
		input_node,
		.Above_Below,
		u64(constraints.height_rows - 1),
		1,
	)
	if !split_ok do return {}, false, split_failure
	_, status_ok, status_failure := ui.proposal_add_status(
		proposal,
		ui.Status_Region_Descriptor {
			owner_id = ui.Owner_ID(prompt_mode_owner_id(commands.prompt_workflow.mode)),
			placement = .Root_Edge,
			rows = 1,
			geometry = {
				row = i32(constraints.height_rows - 1),
				height = 1,
				width = i32(constraints.width_cells),
			},
			style_role = .Status_Active,
			active = true,
		},
		label,
	)
	if !status_ok do return {}, false, status_failure
	if root_ok, root_failure := ui.proposal_set_root(proposal, root_node, base_focus); !root_ok {
		return {}, false, root_failure
	}
	return Transient_Input_Composition {
		root_node = root_node,
		focus_surface = base_focus,
		input_surface = input_surface,
	}, true, {}
}

@(private)
transient_input_label_viewport :: proc(label: string, max_cells: u32) -> (
	viewport: string,
	visible_cells: u32,
	ok: bool,
) {
	profile := display.unicode17_profile()
	byte_offset: u64
	for byte_offset < u64(len(label)) {
		grapheme, grapheme_ok, _ := display.profile_next_grapheme(profile, label, byte_offset)
		if !grapheme_ok || grapheme.end <= byte_offset || grapheme.end > u64(len(label)) {
			return "", 0, false
		}
		width, width_ok, _ := display.profile_cluster_width(
			profile,
			label[int(grapheme.start):int(grapheme.end)],
			visible_cells,
			4,
		)
		if !width_ok || width.is_line_break do return "", 0, false
		if visible_cells + u32(width.cells) > max_cells do break
		visible_cells += u32(width.cells)
		byte_offset = grapheme.end
	}
	return label[:int(byte_offset)], visible_cells, true
}

@(private)
prompt_input_value :: proc(
	commands: ^Command_Context,
	view_registry: ^editor_view.Registry = nil,
	view: editor_view.View_Handle = {},
) -> (string, bool) {
	if commands == nil || !prompt_mode_projects_input(commands.prompt_workflow.mode) do return "", false
	if commands.prompt_workflow.mode == .Query_Replacement_Response {
		_, text, overlay := command_context_overlay(commands, view_registry, view)
		return text, overlay
	}
	if commands.prompt_workflow.mode == .Keymap_Sequence {
		if commands.interaction_workflow.inspection_sequence.stroke_count == 0 do return "", true
		return interaction.key_sequence_notation(
			commands.interaction_workflow.inspection_sequence,
			commands.overlay_text[:],
		)
	}
	view, viewed, _ := interaction.prompt_view(&commands.prompt_workflow.prompt)
	if !viewed || view.status != .Active do return "", false
	return view.text, true
}

@(private)
prompt_input_status_label :: proc(
	commands: ^Command_Context,
	view_registry: ^editor_view.Registry = nil,
	view: editor_view.View_Handle = {},
) -> (string, bool) {
	label, _, overlay := command_context_overlay(commands, view_registry, view)
	if !overlay do return "", false
	if commands.prompt_workflow.mode == .Keymap_Sequence ||
	   commands.prompt_workflow.mode == .Query_Replacement_Response {
		return label, true
	}
	view, viewed, _ := interaction.prompt_view(&commands.prompt_workflow.prompt)
	if !viewed || view.status != .Active do return "", false
	if view.kind != .Fixed_Choice do return label, true
	switch len(view.choices) {
	case 1:
		return fmt.bprintf(commands.overlay_label[:], "%s%s ", label, view.choices[0].name), true
	case 2:
		return fmt.bprintf(
			commands.overlay_label[:], "%s%s %s ",
			label, view.choices[0].name, view.choices[1].name,
		), true
	case 3:
		return fmt.bprintf(
			commands.overlay_label[:], "%s%s %s %s ",
			label, view.choices[0].name, view.choices[1].name, view.choices[2].name,
		), true
	case 4:
		return fmt.bprintf(
			commands.overlay_label[:], "%s%s %s %s %s ",
			label,
			view.choices[0].name,
			view.choices[1].name,
			view.choices[2].name,
			view.choices[3].name,
		), true
	case:
		return "", false
	}
}
