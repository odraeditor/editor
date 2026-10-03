// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../interaction"
import "../display"
import "../document"
import "../editor_session"
import "../layout"
import "../theme"
import terminal "../terminal"
import "../ui"
import "base:runtime"
import "core:fmt"
import "core:unicode/utf8"

/* CANDIDATE_UI_OWNER_ID identifies the built-in candidate UI root owner. */
CANDIDATE_UI_OWNER_ID :: ui.Owner_ID(10_005)
/* CANDIDATE_UI_MODEL_ID identifies the built-in candidate root target. */
CANDIDATE_UI_MODEL_ID :: ui.Model_ID(10_005)
/* CANDIDATE_UI_TARGET_GENERATION identifies the candidate target contract. */
CANDIDATE_UI_TARGET_GENERATION :: u64(1)

@(private)
Candidate_UI_Workflow_State :: struct {
	catalog:                          interaction.Command_Catalog,
	session:                          interaction.Candidate_Session,
	return_target:                    editor_session.Visible_Target,
	theme_selection:                  theme.Selection,
	next_session_id:                  u64,
	next_source_generation:           u64,
	next_presentation_generation:     u64,
}

@(private)
Candidate_Command_Columns :: struct {
	label_cells:   u32,
	binding_cells: u32,
}

@(private)
Candidate_Named_Slot_Columns :: struct {
	label_cells: u32,
}

@(private)
Candidate_Filesystem_Columns :: struct {
	label_cells:    u32,
	size_cells:     u32,
	modified_cells: u32,
	permissions:    bool,
	size:           bool,
	modified:       bool,
}

@(private)
Candidate_Result_Columns :: struct {
	path_cells:       u32,
	path:             bool,
	tabular_location: bool,
}

@(private)
Candidate_UI_Composition :: struct {
	root_node:       ui.Object_Handle,
	focus_surface:   ui.Object_Handle,
	input_surface:   ui.Object_Handle,
	presentation_generation: u64,
}

@(private)
candidate_ui_visible_target :: proc() -> editor_session.Visible_Target {
	return editor_session.Visible_Target {
		kind = .UI_Root,
		ui = {
			owner_id = u64(CANDIDATE_UI_OWNER_ID),
			model_id = u64(CANDIDATE_UI_MODEL_ID),
			generation = CANDIDATE_UI_TARGET_GENERATION,
		},
	}
}

@(private)
candidate_ui_workflow_reset :: proc(state: ^Candidate_UI_Workflow_State) {
	if state == nil do return
	next_session_id := state.next_session_id
	next_source_generation := state.next_source_generation
	next_presentation_generation := state.next_presentation_generation
	if state.catalog.state != nil do interaction.command_catalog_close(&state.catalog)
	if state.session.state != nil do _, _, _ = interaction.candidate_session_close(&state.session)
	state^ = {}
	state.next_session_id = next_session_id
	state.next_source_generation = next_source_generation
	state.next_presentation_generation = next_presentation_generation
}

@(private)
dispatch_candidate_ui_input :: proc(
	commands: ^Command_Context,
	input: interaction.Input,
	constraints: display.Viewport_Constraints,
) -> (Interaction_Result, App_Failure) {
	view, viewed, view_failure := interaction.candidate_session_view(&commands.candidate_ui.session)
	if !viewed {
		return {}, App_Failure{stage = .Component_Access, candidate = view_failure}
	}
	#partial switch view.source_kind {
	case .Commands:
		return dispatch_command_navigation_input(commands, input, constraints)
	case .Session_Buffers:
		return dispatch_buffer_navigation_input(commands, input)
	case .Project_Buffers:
		return dispatch_project_buffer_navigation_input(commands, input)
	case .Project_Files, .Dir_Files:
		return dispatch_project_file_navigation_input(commands, input)
	case .Themes:
		return dispatch_theme_navigation_input(commands, input)
	case .Interaction_Profiles:
		return dispatch_interaction_profile_navigation_input(commands, input)
	case .Projects:
		return dispatch_project_navigation_input(commands, input, constraints)
	case .Workspaces:
		return dispatch_workspace_navigation_input(commands, input, constraints)
	case .Named_Locations:
		return dispatch_named_location_navigation_input(commands, input)
	case .Named_Slots:
		return dispatch_named_slot_navigation_input(commands, input, constraints)
	case .Language_Diagnostics:
		return dispatch_language_diagnostic_input(commands, input)
	case .Results:
		return dispatch_result_input(commands, input)
	case .Personal_Command_Results:
		return dispatch_personal_candidate_input(commands, input)
	case .Filesystem_Entries:
		return dispatch_filesystem_path_navigation_input(commands, input, constraints)
	case .Status_Segments:
		return dispatch_status_bar_segment_input(commands, input, constraints)
	case .Package_Catalogs, .Packages, .Package_Catalog_Diagnostics:
		return dispatch_package_catalog_candidate_input(commands, input)
	case:
		return {}, App_Failure{stage = .Component_Access}
	}
}

@(private)
present_candidate_ui :: proc(
	commands: ^Command_Context,
	session: ^terminal.Session,
	renderer: ^terminal.Renderer,
	constraints: display.Viewport_Constraints,
) -> App_Failure {
	if commands == nil || constraints.height_rows < 2 || constraints.width_cells < 2 {
		return App_Failure{stage = .UI, ui = {operation = .Prepare, code = .Invalid_Layout}}
	}
	view, viewed, view_failure := interaction.candidate_session_view(&commands.candidate_ui.session)
	if !viewed {
		return App_Failure{stage = .Component_Access, candidate = view_failure}
	}
	label_storage: [interaction.MAX_CANDIDATE_PROMPT_LABEL_BYTES]u8
	label, label_ok := interaction.candidate_prompt_label(view, label_storage[:])
	if view.source_kind == .Commands && command_context_command_navigation_describes(commands) {
		selected := u32(0)
		if view.has_selection do selected = view.selected_row + 1
		label = fmt.bprintf(
			label_storage[:],
			"Commands [active editor context] %d/%d Describe: ",
			selected,
			len(view.rows),
		)
		label_ok = len(label) > 0
	}
	if view.source_kind == .Personal_Command_Results {
		personal_label, personal_label_ok := personal_candidate_workflow_prompt_label(
			commands, view, label_storage[:],
		)
		if personal_label_ok {
			label = personal_label
			label_ok = true
		}
	}
	if view.source_kind == .Filesystem_Entries {
		label, label_ok = filesystem_path_navigation_prompt_label(commands, view, label_storage[:])
	}
	if commands.prompt_workflow.mode == .Result_Edit {
		label = "Edit result text: "
		label_ok = true
	}
	if !label_ok || len(label) >= int(constraints.width_cells) {
		return App_Failure{stage = .UI, ui = {operation = .Prepare, code = .Invalid_Layout}}
	}
	input_storage: [document.MAX_PATH_BYTES]u8
	input_value := view.query
	if view.source_kind == .Filesystem_Entries {
		input_value, label_ok = filesystem_path_navigation_input_value(commands, view.query, input_storage[:])
		if !label_ok do return App_Failure{stage = .UI, ui = {operation = .Prepare, code = .Invalid_View}}
	}
	if commands.prompt_workflow.mode == .Result_Edit {
		prompt_view, prompt_ok, prompt_failure := interaction.prompt_view(&commands.prompt_workflow.prompt)
		if !prompt_ok do return App_Failure{stage = .Prompt, prompt_failure = prompt_failure}
		input_value = prompt_view.text
	}
	validation := ui.Input_Validation_State.Valid
	if commands.prompt_workflow.mode == .Result_Edit && commands.prompt_workflow.rejected {
		validation = .Rejected
	}
	if commands.diagnostic_length > 0 {
		input_value = string(commands.diagnostic[:commands.diagnostic_length])
		validation = .Rejected
	}
	input_width := constraints.width_cells - u32(len(label))
	first_visible, viewport_bytes, viewport_ok := candidate_ui_input_viewport(input_value, input_width)
	if !viewport_ok {
		return App_Failure{stage = .UI, ui = {operation = .Prepare, code = .Invalid_View}}
	}
	if commands.candidate_ui.next_presentation_generation == max(u64) {
		return App_Failure{stage = .UI, ui = {operation = .Prepare, code = .Generation_Limit}}
	}
	presentation_generation := commands.candidate_ui.next_presentation_generation + 1
	registry, registry_ok, registry_failure := command_context_ui_registry(commands)
	if !registry_ok do return registry_failure
	profile, profile_ok := terminal.renderer_ui_profile(renderer)
	if !profile_ok {
		return App_Failure{stage = .Presentation, terminal = {code = .Invalid_Renderer}}
	}
	proposal, proposal_ok, proposal_failure := ui.proposal_begin(registry, commands.ui_root)
	if !proposal_ok do return App_Failure{stage = .UI, ui = proposal_failure}
	defer if proposal.state != nil do ui.proposal_abort(&proposal)
	styles_ok, styles_failure := proposal_resolve_session_theme(&proposal, commands)
	if !styles_ok do return styles_failure
	candidate_rows := min(
		u32(len(view.rows)),
		candidate_ui_candidate_row_limit(constraints.height_rows),
	)
	input_row := constraints.height_rows - candidate_rows - 1
	input_view, input_ok, input_failure := ui.proposal_project_input(
		&proposal,
		ui.Input_Projection_Request {
			model = {
				owner_id = ui.Owner_ID(view.session_id),
				model_id = ui.Model_ID(view.source_kind),
				generation = ui.Model_Generation(view.session_generation),
			},
			presentation_generation = presentation_generation,
			backing_generation = u64(view.session_generation),
			cursor_offset = u32(len(input_value)),
			first_visible_byte = first_visible,
			viewport_bytes = viewport_bytes,
			validation = validation,
		},
		input_value,
	)
	if !input_ok do return App_Failure{stage = .UI, ui = input_failure}
	input_surface, input_surface_ok, input_surface_failure := ui.proposal_add_surface(
		&proposal,
		ui.Surface_Descriptor {
			owner_id = CANDIDATE_UI_OWNER_ID,
			view = input_view,
			focusable = true,
			visible = true,
			input_context = 3_006,
			keymap_context = 4_006,
			required_profile = profile.id,
			geometry = {
				row = i32(input_row),
				column = i32(len(label)),
				height = 1,
				width = i32(input_width),
			},
		},
	)
	if !input_surface_ok do return App_Failure{stage = .UI, ui = input_surface_failure}
	input_node, input_node_ok, input_node_failure := ui.proposal_add_surface_node(&proposal, input_surface)
	if !input_node_ok do return App_Failure{stage = .UI, ui = input_node_failure}
	root_node := input_node
	if candidate_rows > 0 {
		list_view, list_ok, list_failure := proposal_project_candidate_list(
			&proposal,
			view,
			candidate_rows,
			commands.temporary_allocator,
			constraints.width_cells,
		)
		if !list_ok do return App_Failure{stage = .UI, ui = list_failure}
		list_surface, list_surface_ok, list_surface_failure := ui.proposal_add_surface(
			&proposal,
			ui.Surface_Descriptor {
				owner_id = CANDIDATE_UI_OWNER_ID,
				view = list_view,
				focusable = true,
				visible = true,
				input_context = 3_005,
				keymap_context = 4_005,
				required_profile = profile.id,
				geometry = {
					row = i32(input_row + 1),
					height = i32(candidate_rows),
					width = i32(constraints.width_cells),
				},
			},
		)
		if !list_surface_ok do return App_Failure{stage = .UI, ui = list_surface_failure}
		list_node, list_node_ok, list_node_failure := ui.proposal_add_surface_node(&proposal, list_surface)
		if !list_node_ok do return App_Failure{stage = .UI, ui = list_node_failure}
		root_ok: bool
		root_failure: ui.Failure
		root_node, root_ok, root_failure = ui.proposal_add_split(
			&proposal,
			input_node,
			list_node,
			.Above_Below,
			1,
			u64(candidate_rows),
		)
		if !root_ok do return App_Failure{stage = .UI, ui = root_failure}
	}
	if input_row > 0 {
		blank_view, blank_view_ok, blank_view_failure := ui.proposal_project_list_view(
			&proposal,
			ui.List_Projection_Request {
				model = {
					owner_id = ui.Owner_ID(view.session_id),
					model_id = ui.Model_ID(10_000 + u64(view.source_kind)),
					generation = ui.Model_Generation(view.session_generation),
				},
				position = {
					presentation_generation = presentation_generation,
					selection_owner = .View,
					current_item = -1,
					viewport_items = input_row,
				},
				read_only = true,
			},
			nil,
		)
		if !blank_view_ok do return App_Failure{stage = .UI, ui = blank_view_failure}
		blank_surface, blank_surface_ok, blank_surface_failure := ui.proposal_add_surface(
			&proposal,
			ui.Surface_Descriptor {
				owner_id = CANDIDATE_UI_OWNER_ID,
				view = blank_view,
				visible = true,
				required_profile = profile.id,
				geometry = {height = i32(input_row), width = i32(constraints.width_cells)},
			},
		)
		if !blank_surface_ok do return App_Failure{stage = .UI, ui = blank_surface_failure}
		blank_node, blank_node_ok, blank_node_failure := ui.proposal_add_surface_node(
			&proposal,
			blank_surface,
		)
		if !blank_node_ok do return App_Failure{stage = .UI, ui = blank_node_failure}
		full_root_ok: bool
		full_root_failure: ui.Failure
		root_node, full_root_ok, full_root_failure = ui.proposal_add_split(
			&proposal,
			blank_node,
			root_node,
			.Above_Below,
			u64(input_row),
			u64(candidate_rows + 1),
		)
		if !full_root_ok do return App_Failure{stage = .UI, ui = full_root_failure}
	}
	_, status_region_ok, status_region_failure := ui.proposal_add_status(
		&proposal,
		ui.Status_Region_Descriptor {
			owner_id = CANDIDATE_UI_OWNER_ID,
			placement = .Root_Edge,
			rows = 1,
			geometry = {
				row = i32(input_row),
				height = 1,
				width = i32(constraints.width_cells),
			},
			style_role = .Status_Active,
			active = true,
		},
		label,
	)
	if !status_region_ok do return App_Failure{stage = .UI, ui = status_region_failure}
	if root_ok, root_failure := ui.proposal_set_root(&proposal, root_node, input_surface); !root_ok {
		return App_Failure{stage = .UI, ui = root_failure}
	}
	root, published, publish_failure := ui.proposal_publish(registry, &proposal, profile)
	if !published do return App_Failure{stage = .UI, ui = publish_failure}
	commands.ui_root = root
	captured, capture_failure := ui.registry_capture_focus(registry, input_surface)
	if !captured do return App_Failure{stage = .UI, ui = capture_failure}
	commands.candidate_ui.next_presentation_generation = presentation_generation
	snapshot, copied, copy_failure := ui.registry_snapshot(registry, root, profile)
	if !copied do return App_Failure{stage = .UI, ui = copy_failure}
	defer ui.snapshot_close(&snapshot)
	presented, presentation_failure := terminal.renderer_present_ui(
		renderer,
		session,
		terminal.UI_Presentation{root = &snapshot},
	)
	if !presented {
		return App_Failure{stage = .Presentation, terminal = presentation_failure}
	}
	return {}
}

@(private)
candidate_ui_editor_rows :: proc(
	commands: ^Command_Context,
	constraints: display.Viewport_Constraints,
	pane_count: u16,
) -> (editor_rows, candidate_rows: u32, ok: bool) {
	if commands == nil || commands.candidate_ui.session.state == nil || pane_count == 0 ||
	   constraints.width_cells < 2 {
		return 0, 0, false
	}
	view, viewed, _ := interaction.candidate_session_view(&commands.candidate_ui.session)
	if !viewed do return 0, 0, false
	minimum_editor_rows := u32(pane_count) *
		u32(layout.SEMANTIC_CONTENT_ROWS + layout.PANE_STATUS_ROWS) +
		u32(EDITOR_LAYOUT_RESERVED_ROWS)
	if constraints.height_rows < minimum_editor_rows + 1 do return 0, 0, false
	available_candidate_rows := constraints.height_rows - minimum_editor_rows - 1
	candidate_rows = min(
		u32(len(view.rows)),
		available_candidate_rows,
		candidate_ui_candidate_row_limit(constraints.height_rows),
	)
	editor_rows = constraints.height_rows - candidate_rows - 1
	return editor_rows, candidate_rows, true
}

@(private)
candidate_ui_candidate_row_limit :: proc(height_rows: u32) -> u32 {
	panel_rows := height_rows / 2
	if panel_rows == 0 do return 0
	return panel_rows - 1
}

@(private)
proposal_compose_candidate_ui :: proc(
	proposal: ^ui.Proposal,
	commands: ^Command_Context,
	base_root, base_focus: ui.Object_Handle,
	constraints: display.Viewport_Constraints,
	editor_rows, candidate_rows: u32,
	profile: ui.Renderer_Profile_ID,
) -> (composition: Candidate_UI_Composition, ok: bool, failure: ui.Failure) {
	if proposal == nil || commands == nil || commands.candidate_ui.session.state == nil ||
	   editor_rows == 0 ||
	   editor_rows + candidate_rows + 1 != constraints.height_rows ||
	   constraints.width_cells < 2 || profile == ui.Renderer_Profile_ID(0) {
		return {}, false, ui.Failure{operation = .Prepare, code = .Invalid_Layout}
	}
	view, viewed, _ := interaction.candidate_session_view(&commands.candidate_ui.session)
	if !viewed {
		return {}, false, ui.Failure{operation = .Prepare, code = .Invalid_View}
	}
	label_storage: [interaction.MAX_CANDIDATE_PROMPT_LABEL_BYTES]u8
	label, label_ok := interaction.candidate_prompt_label(view, label_storage[:])
	if view.source_kind == .Personal_Command_Results {
		personal_label, personal_label_ok := personal_candidate_workflow_prompt_label(
			commands, view, label_storage[:],
		)
		if personal_label_ok {
			label = personal_label
			label_ok = true
		}
	}
	if view.source_kind == .Filesystem_Entries {
		label, label_ok = filesystem_path_navigation_prompt_label(commands, view, label_storage[:])
	}
	if commands.prompt_workflow.mode == .Result_Edit {
		label = "Edit result text: "
		label_ok = true
	}
	if !label_ok || len(label) >= int(constraints.width_cells) {
		return {}, false, ui.Failure{operation = .Prepare, code = .Invalid_Layout}
	}
	input_storage: [document.MAX_PATH_BYTES]u8
	input_value := view.query
	if view.source_kind == .Filesystem_Entries {
		input_value, label_ok = filesystem_path_navigation_input_value(commands, view.query, input_storage[:])
		if !label_ok do return {}, false, ui.Failure{operation = .Prepare, code = .Invalid_View}
	}
	if commands.prompt_workflow.mode == .Result_Edit {
		prompt_view, prompt_ok, _ := interaction.prompt_view(&commands.prompt_workflow.prompt)
		if !prompt_ok do return {}, false, ui.Failure{operation = .Prepare, code = .Invalid_View}
		input_value = prompt_view.text
	}
	validation := ui.Input_Validation_State.Valid
	if commands.prompt_workflow.mode == .Result_Edit && commands.prompt_workflow.rejected {
		validation = .Rejected
	}
	if commands.diagnostic_length > 0 {
		input_value = string(commands.diagnostic[:commands.diagnostic_length])
		validation = .Rejected
	}
	input_width := constraints.width_cells - u32(len(label))
	first_visible, viewport_bytes, viewport_ok := candidate_ui_input_viewport(input_value, input_width)
	if !viewport_ok {
		return {}, false, ui.Failure{operation = .Prepare, code = .Invalid_View}
	}
	if commands.candidate_ui.next_presentation_generation == max(u64) {
		return {}, false, ui.Failure{operation = .Prepare, code = .Generation_Limit}
	}
	presentation_generation := commands.candidate_ui.next_presentation_generation + 1
	input_view, input_ok, input_failure := ui.proposal_project_input(
		proposal,
		ui.Input_Projection_Request {
			model = {
				owner_id = ui.Owner_ID(view.session_id),
				model_id = ui.Model_ID(view.source_kind),
				generation = ui.Model_Generation(view.session_generation),
			},
			presentation_generation = presentation_generation,
			backing_generation = u64(view.session_generation),
			cursor_offset = u32(len(input_value)),
			first_visible_byte = first_visible,
			viewport_bytes = viewport_bytes,
			validation = validation,
		},
		input_value,
	)
	if !input_ok do return {}, false, input_failure
	input_surface, input_surface_ok, input_surface_failure := ui.proposal_add_surface(
		proposal,
		ui.Surface_Descriptor {
			owner_id = CANDIDATE_UI_OWNER_ID,
			view = input_view,
			focusable = true,
			visible = true,
			input_context = 3_006,
			keymap_context = 4_006,
			required_profile = profile,
			geometry = {
				row = i32(editor_rows),
				column = i32(len(label)),
				height = 1,
				width = i32(input_width),
			},
		},
	)
	if !input_surface_ok do return {}, false, input_surface_failure
	input_node, input_node_ok, input_node_failure := ui.proposal_add_surface_node(proposal, input_surface)
	if !input_node_ok do return {}, false, input_node_failure
	panel_node := input_node
	if candidate_rows > 0 {
		list_view, list_ok, list_failure := proposal_project_candidate_list(
			proposal,
			view,
			candidate_rows,
			commands.temporary_allocator,
			constraints.width_cells,
		)
		if !list_ok do return {}, false, list_failure
		list_surface, list_surface_ok, list_surface_failure := ui.proposal_add_surface(
			proposal,
			ui.Surface_Descriptor {
				owner_id = CANDIDATE_UI_OWNER_ID,
				view = list_view,
				focusable = true,
				visible = true,
				input_context = 3_005,
				keymap_context = 4_005,
				required_profile = profile,
				geometry = {
					row = i32(editor_rows + 1),
					height = i32(candidate_rows),
					width = i32(constraints.width_cells),
				},
			},
		)
		if !list_surface_ok do return {}, false, list_surface_failure
		list_node, list_node_ok, list_node_failure := ui.proposal_add_surface_node(proposal, list_surface)
		if !list_node_ok do return {}, false, list_node_failure
		panel_ok: bool
		panel_failure: ui.Failure
		panel_node, panel_ok, panel_failure = ui.proposal_add_split(
			proposal,
			input_node,
			list_node,
			.Above_Below,
			1,
			u64(candidate_rows),
		)
		if !panel_ok do return {}, false, panel_failure
	}
	root_node, root_ok, root_failure := ui.proposal_add_split(
		proposal,
		base_root,
		panel_node,
		.Above_Below,
		u64(editor_rows),
		u64(candidate_rows + 1),
	)
	if !root_ok do return {}, false, root_failure
	_, status_ok, status_failure := ui.proposal_add_status(
		proposal,
		ui.Status_Region_Descriptor {
			owner_id = CANDIDATE_UI_OWNER_ID,
			placement = .Root_Edge,
			rows = 1,
			geometry = {
				row = i32(editor_rows),
				height = 1,
				width = i32(constraints.width_cells),
			},
			style_role = .Status_Active,
			active = true,
		},
		label,
	)
	if !status_ok do return {}, false, status_failure
	if published_root, publish_failure := ui.proposal_set_root(proposal, root_node, base_focus);
	   !published_root {
		return {}, false, publish_failure
	}
	return Candidate_UI_Composition {
		root_node = root_node,
		focus_surface = base_focus,
		input_surface = input_surface,
		presentation_generation = presentation_generation,
	}, true, {}
}

@(private)
candidate_ui_input_viewport :: proc(
	value: string,
	viewport_cells: u32,
) -> (first_visible, viewport_bytes: u32, ok: bool) {
	if viewport_cells == 0 || len(value) > int(ui.MAX_INPUT_BYTES) || !utf8.valid_string(value) {
		return 0, 0, false
	}
	profile := display.terminal_unicode17_profile()
	starts: [ui.MAX_INPUT_BYTES]u32
	widths: [ui.MAX_INPUT_BYTES]u16
	first_index, count := 0, 0
	visible_cells := u32(0)
	offset: u64
	for offset < u64(len(value)) {
		grapheme, grapheme_ok, _ := display.profile_next_grapheme(profile.unicode, value, offset)
		if !grapheme_ok || count >= len(starts) do return 0, 0, false
		cluster := value[grapheme.start:grapheme.end]
		width, width_ok, _ := display.profile_cluster_width(
			profile.unicode,
			cluster,
			visible_cells,
			4,
		)
		if !width_ok do return 0, 0, false
		cells := u32(width.cells)
		if width.is_line_break || width.is_tab || width.used_replacement do cells = 1
		starts[count] = u32(grapheme.start)
		widths[count] = u16(cells)
		count += 1
		visible_cells += cells
		for visible_cells >= viewport_cells && first_index < count {
			visible_cells -= u32(widths[first_index])
			first_index += 1
		}
		offset = grapheme.end
	}
	first_visible = u32(len(value))
	if first_index < count do first_visible = starts[first_index]
	viewport_bytes = u32(len(value)) - first_visible + 1
	return first_visible, viewport_bytes, true
}

@(private)
/* proposal_project_candidate_list copies one canonical candidate view into shared ListView. */
proposal_project_candidate_list :: proc(
	proposal: ^ui.Proposal,
	view: interaction.Candidate_View,
	viewport_items: u32,
	allocator: runtime.Allocator,
	viewport_cells := max(u32),
) -> (handle: ui.Object_Handle, ok: bool, failure: ui.Failure) {
	if proposal == nil || !candidate_ui_view_is_valid(view) || viewport_items == 0 ||
	   viewport_items > ui.MAX_LIST_ITEMS || allocator.procedure == nil {
		return {}, false, ui.Failure{operation = .Prepare, code = .Invalid_List_View}
	}
	definitions, definitions_error := make([]ui.List_Item_Definition, len(view.rows), allocator)
	if definitions_error != nil {
		return {}, false, ui.Failure{operation = .Prepare, code = .Allocation}
	}
	defer delete(definitions, allocator)
	command_columns: Candidate_Command_Columns
	if view.source_kind == .Commands {
		columns, columns_ok := candidate_ui_command_columns(view)
		if !columns_ok {
			return {}, false, ui.Failure{operation = .Prepare, code = .Invalid_List_Item}
		}
		command_columns = columns
	}
	named_slot_columns: Candidate_Named_Slot_Columns
	if view.source_kind == .Named_Slots {
		columns, columns_ok := candidate_ui_named_slot_columns(view)
		if !columns_ok {
			return {}, false, ui.Failure{operation = .Prepare, code = .Invalid_List_Item}
		}
		named_slot_columns = columns
	}
	filesystem_columns: Candidate_Filesystem_Columns
	if view.source_kind == .Filesystem_Entries {
		columns, columns_ok := candidate_ui_filesystem_columns(view, viewport_cells)
		if !columns_ok {
			return {}, false, ui.Failure{operation = .Prepare, code = .Invalid_List_Item}
		}
		filesystem_columns = columns
	}
	result_columns: Candidate_Result_Columns
	if view.source_kind == .Results {
		columns, columns_ok := candidate_ui_result_columns(view)
		if !columns_ok {
			return {}, false, ui.Failure{operation = .Prepare, code = .Invalid_List_Item}
		}
		result_columns = columns
	}
	text_bytes := 0
	for row in view.rows {
		size, valid := interaction.candidate_row_text_size(view.source_kind, row)
		if view.source_kind == .Commands {
			size, valid = candidate_ui_command_row_size(row, command_columns)
		} else if view.source_kind == .Named_Slots {
			size, valid = candidate_ui_named_slot_row_size(row, named_slot_columns)
		} else if view.source_kind == .Filesystem_Entries {
			size, valid = candidate_ui_filesystem_row_size(row, filesystem_columns)
		} else if view.source_kind == .Results {
			size, valid = candidate_ui_result_row_size(row, result_columns)
		}
		if !valid || size > max(int) - text_bytes {
			return {}, false, ui.Failure{operation = .Prepare, code = .Invalid_List_Item}
		}
		text_bytes += size
	}
	text, text_error := make([]u8, text_bytes, allocator)
	if text_error != nil {
		return {}, false, ui.Failure{operation = .Prepare, code = .Allocation}
	}
	defer delete(text, allocator)
	offset := 0
	for row, index in view.rows {
		size, _ := interaction.candidate_row_text_size(view.source_kind, row)
		if view.source_kind == .Commands {
			size, _ = candidate_ui_command_row_size(row, command_columns)
		} else if view.source_kind == .Named_Slots {
			size, _ = candidate_ui_named_slot_row_size(row, named_slot_columns)
		} else if view.source_kind == .Filesystem_Entries {
			size, _ = candidate_ui_filesystem_row_size(row, filesystem_columns)
		} else if view.source_kind == .Results {
			size, _ = candidate_ui_result_row_size(row, result_columns)
		}
		row_text, formatted := interaction.candidate_row_text_write(
			view.source_kind, row, text[offset:offset + size],
		)
		if view.source_kind == .Commands {
			row_text, formatted = candidate_ui_command_row_write(
				row, command_columns, text[offset:offset + size],
			)
		} else if view.source_kind == .Named_Slots {
			row_text, formatted = candidate_ui_named_slot_row_write(
				row, named_slot_columns, text[offset:offset + size],
			)
		} else if view.source_kind == .Filesystem_Entries {
			row_text, formatted = candidate_ui_filesystem_row_write(
				row, filesystem_columns, text[offset:offset + size],
			)
		} else if view.source_kind == .Results {
			row_text, formatted = candidate_ui_result_row_write(
				row, result_columns, text[offset:offset + size],
			)
		}
		if !formatted {
			return {}, false, ui.Failure{operation = .Prepare, code = .Invalid_List_Item}
		}
		definitions[index] = ui.List_Item_Definition {
			id = ui.List_Item_ID(index + 1),
			text = row_text,
			emphasis_bytes = u32(len(row.label)) if view.source_kind == .Commands else 0,
			emphasis_style = .List_Emphasis if view.source_kind == .Commands else .Invalid,
			action = {
				owner_id = ui.Owner_ID(view.session_id),
				action_id = ui.List_Action_ID(index + 1),
				generation = u64(view.session_generation),
			},
		}
		if view.source_kind == .Named_Slots {
			preview, present, preview_ok := interaction.candidate_named_slot_presentation(row)
			if !preview_ok {
				return {}, false, ui.Failure{operation = .Prepare, code = .Invalid_List_Item}
			}
			if present {
				label_cells, label_ok := candidate_ui_text_cells(row.label)
				preview_start := u32(len(row.label)) + named_slot_columns.label_cells - label_cells + 4
				if !label_ok || !candidate_ui_append_style_span(
					&definitions[index].style_spans,
					&definitions[index].style_span_count,
					.List_Emphasis,
					preview_start,
					preview_start + u32(len(preview)),
				) {
					return {}, false, ui.Failure{operation = .Prepare, code = .Invalid_List_Item}
				}
			}
		} else if view.source_kind == .Filesystem_Entries {
			spans, span_count, spans_ok := candidate_ui_filesystem_row_style_spans(
				row, filesystem_columns,
			)
			if !spans_ok {
				return {}, false, ui.Failure{operation = .Prepare, code = .Invalid_List_Item}
			}
			definitions[index].style_spans = spans
			definitions[index].style_span_count = span_count
		} else if view.source_kind == .Results {
			prefix_bytes, prefix_ok := candidate_ui_result_prefix_bytes(row, result_columns)
			metadata_end, metadata_ok := candidate_ui_result_metadata_end_bytes(row, result_columns)
			if !prefix_ok || !metadata_ok || !candidate_ui_append_style_span(
				&definitions[index].style_spans,
				&definitions[index].style_span_count,
				.List_Emphasis,
				0,
				metadata_end,
			) {
				return {}, false, ui.Failure{operation = .Prepare, code = .Invalid_List_Item}
			}
			if row.label_highlight_present && !candidate_ui_append_style_span(
				&definitions[index].style_spans,
				&definitions[index].style_span_count,
				.Text_Search_Current,
				prefix_bytes + row.label_highlight_start,
				prefix_bytes + row.label_highlight_end,
			) {
				return {}, false, ui.Failure{operation = .Prepare, code = .Invalid_List_Item}
			}
		}
		offset += size
	}
	assert(offset == text_bytes)
	current_item := i32(-1)
	first_visible_item := u32(0)
	if view.has_selection {
		current_item = i32(view.selected_row)
		if view.selected_row >= viewport_items {
			first_visible_item = view.selected_row - viewport_items + 1
		}
	}
	return ui.proposal_project_list_view(
		proposal,
		ui.List_Projection_Request {
			model = {
				owner_id = ui.Owner_ID(view.session_id),
				model_id = ui.Model_ID(view.source_kind),
				generation = ui.Model_Generation(view.session_generation),
			},
			position = {
				presentation_generation = u64(view.session_generation),
				selection_owner = .Model,
				current_item = current_item,
				first_visible_item = first_visible_item,
				viewport_items = viewport_items,
			},
			read_only = true,
		},
		definitions,
	)
}

@(private)
candidate_ui_result_columns :: proc(
	view: interaction.Candidate_View,
) -> (columns: Candidate_Result_Columns, ok: bool) {
	if view.source_kind != .Results do return {}, false
	columns.tabular_location = true
	for row in view.rows {
		path, location, fields_ok := interaction.candidate_result_presentation(row)
		_, _, location_ok := candidate_ui_result_location_parts(location)
		if !fields_ok do return {}, false
		if !location_ok {
			columns.tabular_location = false
			continue
		}
		path_cells, path_ok := candidate_ui_text_cells(path)
		if !path_ok do return {}, false
		columns.path_cells = max(columns.path_cells, path_cells)
		columns.path = columns.path || len(path) > 0
	}
	return columns, true
}

@(private)
candidate_ui_result_prefix_bytes :: proc(
	row: interaction.Candidate_Row,
	columns: Candidate_Result_Columns,
) -> (bytes: u32, ok: bool) {
	path, location, fields_ok := interaction.candidate_result_presentation(row)
	if !fields_ok do return 0, false
	if !columns.tabular_location {
		encoded := u64(len(location)) + 3
		if len(path) > 0 do encoded += u64(len(path)) + 2
		if encoded > u64(max(u32)) do return 0, false
		return u32(encoded), true
	}
	path_cells, path_ok := candidate_ui_text_cells(path)
	_, _, location_ok := candidate_ui_result_location_parts(location)
	if !fields_ok || !location_ok || !path_ok || path_cells > columns.path_cells {
		return 0, false
	}
	encoded := u64(0)
	if columns.path {
		encoded += u64(len(path)) + u64(columns.path_cells - path_cells) + 2
	}
	encoded += u64(len(location)) + 3
	if encoded > u64(max(u32)) do return 0, false
	return u32(encoded), true
}

@(private)
candidate_ui_result_metadata_end_bytes :: proc(
	row: interaction.Candidate_Row,
	columns: Candidate_Result_Columns,
) -> (bytes: u32, ok: bool) {
	prefix, prefix_ok := candidate_ui_result_prefix_bytes(row, columns)
	if !prefix_ok do return 0, false
	if !columns.tabular_location {
		if prefix <= 3 do return 0, false
		return prefix - 3, true
	}
	if prefix <= 3 do return 0, false
	return prefix - 3, true
}

@(private)
candidate_ui_result_row_size :: proc(
	row: interaction.Candidate_Row,
	columns: Candidate_Result_Columns,
) -> (size: int, ok: bool) {
	if !columns.tabular_location {
		return interaction.candidate_row_text_size(.Results, row)
	}
	prefix, prefix_ok := candidate_ui_result_prefix_bytes(row, columns)
	if !prefix_ok || u64(prefix) + u64(len(row.label)) > u64(max(int)) do return 0, false
	return int(prefix) + len(row.label), true
}

@(private)
candidate_ui_result_row_write :: proc(
	row: interaction.Candidate_Row,
	columns: Candidate_Result_Columns,
	output: []u8,
) -> (text: string, ok: bool) {
	if !columns.tabular_location {
		return interaction.candidate_row_text_write(.Results, row, output)
	}
	size, valid := candidate_ui_result_row_size(row, columns)
	if !valid || len(output) < size do return "", false
	path, location, _ := interaction.candidate_result_presentation(row)
	path_cells, _ := candidate_ui_text_cells(path)
	offset := 0
	if columns.path {
		offset = candidate_ui_text_append(output, offset, path)
		offset = candidate_ui_space_append(output, offset, columns.path_cells - path_cells + 2)
	}
	offset = candidate_ui_text_append(output, offset, location)
	offset = candidate_ui_space_append(output, offset, 3)
	offset = candidate_ui_text_append(output, offset, row.label)
	assert(offset == size)
	return string(output[:offset]), true
}

@(private)
candidate_ui_result_location_parts :: proc(location: string) -> (
	line, column: string,
	ok: bool,
) {
	separator := -1
	for value, index in location {
		if value != ':' do continue
		if separator >= 0 do return "", "", false
		separator = index
	}
	if separator <= 0 || separator >= len(location) - 1 do return "", "", false
	line = location[:separator]
	column = location[separator + 1:]
	for value in line do if value < '0' || value > '9' do return "", "", false
	for value in column do if value < '0' || value > '9' do return "", "", false
	return line, column, true
}

@(private)
candidate_ui_filesystem_columns :: proc(
	view: interaction.Candidate_View,
	viewport_cells: u32,
) -> (columns: Candidate_Filesystem_Columns, ok: bool) {
	if view.source_kind != .Filesystem_Entries || viewport_cells == 0 do return {}, false
	for row in view.rows {
		permissions, size, modified, fields_ok := interaction.candidate_filesystem_presentation(row)
		label_cells, label_ok := candidate_ui_text_cells(row.label)
		size_cells, size_ok := candidate_ui_text_cells(size)
		modified_cells, modified_ok := candidate_ui_text_cells(modified)
		if !fields_ok || !label_ok || !size_ok || !modified_ok || len(permissions) != 10 {
			return {}, false
		}
		columns.label_cells = max(columns.label_cells, label_cells)
		columns.size_cells = max(columns.size_cells, size_cells)
		columns.modified_cells = max(columns.modified_cells, modified_cells)
	}
	required := u64(columns.label_cells)
	if required + 2 + 10 <= u64(viewport_cells) {
		columns.permissions = true
		required += 12
	}
	if columns.permissions && required + 2 + u64(columns.size_cells) <= u64(viewport_cells) {
		columns.size = true
		required += 2 + u64(columns.size_cells)
	}
	if columns.size && required + 2 + u64(columns.modified_cells) <= u64(viewport_cells) {
		columns.modified = true
	}
	return columns, true
}

@(private)
candidate_ui_filesystem_row_size :: proc(
	row: interaction.Candidate_Row,
	columns: Candidate_Filesystem_Columns,
) -> (size: int, ok: bool) {
	permissions, size_text, modified, fields_ok := interaction.candidate_filesystem_presentation(row)
	label_cells, label_ok := candidate_ui_text_cells(row.label)
	if !fields_ok || !label_ok || label_cells > columns.label_cells do return 0, false
	encoded := u64(len(row.label))
	if columns.permissions {
		encoded += u64(columns.label_cells - label_cells) + 2 + u64(len(permissions))
	}
	if columns.size {
		size_cells, size_ok := candidate_ui_text_cells(size_text)
		if !size_ok || size_cells > columns.size_cells do return 0, false
		encoded += 2 + u64(columns.size_cells - size_cells) + u64(len(size_text))
	}
	if columns.modified do encoded += 2 + u64(len(modified))
	if encoded > u64(max(int)) do return 0, false
	return int(encoded), true
}

@(private)
candidate_ui_filesystem_row_write :: proc(
	row: interaction.Candidate_Row,
	columns: Candidate_Filesystem_Columns,
	output: []u8,
) -> (text: string, ok: bool) {
	size, valid := candidate_ui_filesystem_row_size(row, columns)
	if !valid || len(output) < size do return "", false
	permissions, size_text, modified, _ := interaction.candidate_filesystem_presentation(row)
	label_cells, _ := candidate_ui_text_cells(row.label)
	offset := candidate_ui_text_append(output, 0, row.label)
	if columns.permissions {
		offset = candidate_ui_space_append(output, offset, columns.label_cells - label_cells + 2)
		offset = candidate_ui_text_append(output, offset, permissions)
	}
	if columns.size {
		size_cells, _ := candidate_ui_text_cells(size_text)
		offset = candidate_ui_space_append(output, offset, 2 + columns.size_cells - size_cells)
		offset = candidate_ui_text_append(output, offset, size_text)
	}
	if columns.modified {
		offset = candidate_ui_space_append(output, offset, 2)
		offset = candidate_ui_text_append(output, offset, modified)
	}
	assert(offset == size)
	return string(output[:offset]), true
}

@(private)
candidate_ui_filesystem_row_style_spans :: proc(
	row: interaction.Candidate_Row,
	columns: Candidate_Filesystem_Columns,
) -> (spans: [ui.MAX_LIST_ITEM_STYLE_SPANS]ui.List_Item_Style_Span, count: u8, ok: bool) {
	permissions, size_text, modified, fields_ok := interaction.candidate_filesystem_presentation(row)
	label_cells, label_ok := candidate_ui_text_cells(row.label)
	if !fields_ok || !label_ok || label_cells > columns.label_cells do return {}, 0, false
	if permissions[0] == 'd' && !candidate_ui_append_style_span(
		&spans, &count, .Filesystem_Directory, 0, u32(len(row.label)),
	) {
		return {}, 0, false
	}
	if !columns.permissions do return spans, count, true
	permission_start := u32(len(row.label)) + columns.label_cells - label_cells + 2
	for mark, index in transmute([]u8)permissions {
		role := ui.Style_Role.Filesystem_Metadata
		switch mark {
		case 'd': role = .Filesystem_Directory
		case 'r': role = .Filesystem_Permission_Read
		case 'w': role = .Filesystem_Permission_Write
		case 'x': role = .Filesystem_Permission_Execute
		case '-':
		case: return {}, 0, false
		}
		if !candidate_ui_append_style_span(
			&spans, &count, role, permission_start + u32(index), permission_start + u32(index) + 1,
		) {
			return {}, 0, false
		}
	}
	end := permission_start + u32(len(permissions))
	if columns.size {
		size_cells, size_ok := candidate_ui_text_cells(size_text)
		if !size_ok do return {}, 0, false
		start := end + 2 + columns.size_cells - size_cells
		if !candidate_ui_append_style_span(
			&spans, &count, .Filesystem_Metadata, start, start + u32(len(size_text)),
		) {
			return {}, 0, false
		}
		end = start + u32(len(size_text))
	}
	if columns.modified {
		start := end + 2
		if !candidate_ui_append_style_span(
			&spans, &count, .Filesystem_Metadata, start, start + u32(len(modified)),
		) {
			return {}, 0, false
		}
	}
	return spans, count, true
}

@(private)
candidate_ui_append_style_span :: proc(
	spans: ^[ui.MAX_LIST_ITEM_STYLE_SPANS]ui.List_Item_Style_Span,
	count: ^u8,
	role: ui.Style_Role,
	start, end: u32,
) -> bool {
	if spans == nil || count == nil || start >= end || count^ >= ui.MAX_LIST_ITEM_STYLE_SPANS {
		return false
	}
	spans[count^] = {start_byte = start, end_byte = end, style_role = role}
	count^ += 1
	return true
}

@(private)
candidate_ui_named_slot_columns :: proc(
	view: interaction.Candidate_View,
) -> (columns: Candidate_Named_Slot_Columns, ok: bool) {
	if view.source_kind != .Named_Slots do return {}, false
	for row in view.rows {
		_, _, preview_ok := interaction.candidate_named_slot_presentation(row)
		label_cells, label_ok := candidate_ui_text_cells(row.label)
		if !preview_ok || !label_ok do return {}, false
		columns.label_cells = max(columns.label_cells, label_cells)
	}
	return columns, true
}

@(private)
candidate_ui_named_slot_row_size :: proc(
	row: interaction.Candidate_Row,
	columns: Candidate_Named_Slot_Columns,
) -> (size: int, ok: bool) {
	preview, present, preview_ok := interaction.candidate_named_slot_presentation(row)
	label_cells, label_ok := candidate_ui_text_cells(row.label)
	if !preview_ok || !label_ok || label_cells > columns.label_cells do return 0, false
	size = len(row.label)
	if present {
		padding := u64(columns.label_cells - label_cells) + 4
		encoded := u64(size) + padding + u64(len(preview))
		if encoded > u64(max(int)) do return 0, false
		size = int(encoded)
	}
	return size, true
}

@(private)
candidate_ui_named_slot_row_write :: proc(
	row: interaction.Candidate_Row,
	columns: Candidate_Named_Slot_Columns,
	output: []u8,
) -> (text: string, ok: bool) {
	size, valid := candidate_ui_named_slot_row_size(row, columns)
	if !valid || len(output) < size do return "", false
	preview, present, _ := interaction.candidate_named_slot_presentation(row)
	label_cells, _ := candidate_ui_text_cells(row.label)
	offset := candidate_ui_text_append(output, 0, row.label)
	if present {
		offset = candidate_ui_space_append(
			output, offset, columns.label_cells - label_cells + 4,
		)
		offset = candidate_ui_text_append(output, offset, preview)
	}
	assert(offset == size)
	return string(output[:offset]), true
}

@(private)
candidate_ui_command_columns :: proc(
	view: interaction.Candidate_View,
) -> (columns: Candidate_Command_Columns, ok: bool) {
	if view.source_kind != .Commands do return {}, false
	for row in view.rows {
		binding, _, fields_ok := interaction.candidate_command_presentation(row)
		if !fields_ok do return {}, false
		label_cells, label_ok := candidate_ui_text_cells(row.label)
		binding_cells, binding_ok := candidate_ui_text_cells(binding)
		if !label_ok || !binding_ok do return {}, false
		if binding_cells > 0 do binding_cells += 2
		columns.label_cells = max(columns.label_cells, label_cells)
		columns.binding_cells = max(columns.binding_cells, binding_cells)
	}
	return columns, true
}

@(private)
candidate_ui_command_row_size :: proc(
	row: interaction.Candidate_Row,
	columns: Candidate_Command_Columns,
) -> (size: int, ok: bool) {
	binding, description, fields_ok := interaction.candidate_command_presentation(row)
	label_cells, label_ok := candidate_ui_text_cells(row.label)
	binding_cells, binding_ok := candidate_ui_text_cells(binding)
	if !fields_ok || !label_ok || !binding_ok || label_cells > columns.label_cells {
		return 0, false
	}
	if binding_cells > 0 do binding_cells += 2
	if binding_cells > columns.binding_cells do return 0, false
	padding := u64(columns.label_cells - label_cells) + 2 +
		u64(columns.binding_cells - binding_cells) + 2
	encoded := u64(len(row.label)) + u64(len(binding)) + u64(len(description)) + padding
	if len(binding) > 0 do encoded += 2
	if encoded > u64(max(int)) do return 0, false
	return int(encoded), true
}

@(private)
candidate_ui_command_row_write :: proc(
	row: interaction.Candidate_Row,
	columns: Candidate_Command_Columns,
	output: []u8,
) -> (text: string, ok: bool) {
	size, valid := candidate_ui_command_row_size(row, columns)
	if !valid || len(output) < size do return "", false
	binding, description, _ := interaction.candidate_command_presentation(row)
	label_cells, _ := candidate_ui_text_cells(row.label)
	binding_cells, _ := candidate_ui_text_cells(binding)
	if binding_cells > 0 do binding_cells += 2
	offset := candidate_ui_text_append(output, 0, row.label)
	offset = candidate_ui_space_append(output, offset, columns.label_cells - label_cells + 2)
	if len(binding) > 0 {
		offset = candidate_ui_text_append(output, offset, "[")
		offset = candidate_ui_text_append(output, offset, binding)
		offset = candidate_ui_text_append(output, offset, "]")
	}
	offset = candidate_ui_space_append(
		output, offset, columns.binding_cells - binding_cells + 2,
	)
	offset = candidate_ui_text_append(output, offset, description)
	assert(offset == size)
	return string(output[:offset]), true
}

@(private)
candidate_ui_text_cells :: proc(value: string) -> (cells: u32, ok: bool) {
	profile := display.unicode17_profile()
	offset: u64
	for offset < u64(len(value)) {
		grapheme, grapheme_ok, _ := display.profile_next_grapheme(profile, value, offset)
		if !grapheme_ok do return 0, false
		width, width_ok, _ := display.profile_cluster_width(
			profile,
			value[int(grapheme.start):int(grapheme.end)],
			cells,
			4,
		)
		if !width_ok || width.is_line_break || width.is_tab || width.used_replacement {
			return 0, false
		}
		cells += u32(width.cells)
		offset = grapheme.end
	}
	return cells, true
}

@(private)
candidate_ui_text_append :: proc(output: []u8, offset: int, value: string) -> int {
	copy(output[offset:], transmute([]u8)value)
	return offset + len(value)
}

@(private)
candidate_ui_space_append :: proc(output: []u8, offset: int, count: u32) -> int {
	for index in 0 ..< int(count) do output[offset + index] = ' '
	return offset + int(count)
}

@(private)
/* candidate_ui_action_row resolves one checked list action into its canonical candidate row. */
candidate_ui_action_row :: proc(
	view: interaction.Candidate_View,
	action: ui.List_Action_Reference,
) -> (row: interaction.Candidate_Row, index: u32, ok: bool) {
	if !candidate_ui_view_is_valid(view) || action.owner_id != ui.Owner_ID(view.session_id) ||
	   action.generation != u64(view.session_generation) || action.action_id == ui.List_Action_ID(0) {
		return {}, 0, false
	}
	encoded := u64(action.action_id)
	if encoded == 0 || encoded > u64(len(view.rows)) {
		return {}, 0, false
	}
	index = u32(encoded - 1)
	return view.rows[index], index, true
}

@(private)
candidate_ui_view_is_valid :: proc(view: interaction.Candidate_View) -> bool {
	valid_source := view.source_kind == .Commands || view.source_kind == .Session_Buffers ||
		view.source_kind == .Project_Buffers || view.source_kind == .Project_Files ||
		view.source_kind == .Dir_Files ||
		view.source_kind == .Themes || view.source_kind == .Interaction_Profiles ||
		view.source_kind == .Projects ||
		view.source_kind == .Workspaces ||
		view.source_kind == .Named_Locations ||
		view.source_kind == .Named_Slots ||
		view.source_kind == .Language_Diagnostics ||
		view.source_kind == .Filesystem_Entries ||
		view.source_kind == .Results ||
		view.source_kind == .Personal_Command_Results ||
		view.source_kind == .Status_Segments ||
		view.source_kind == .Package_Catalogs ||
		view.source_kind == .Packages ||
		view.source_kind == .Package_Catalog_Diagnostics
	return valid_source && view.session_id != interaction.Candidate_Session_ID(0) &&
		view.session_generation != interaction.Candidate_Session_Generation(0) &&
		view.scope_identity != 0 && view.scope_generation != 0 &&
		view.source_generation != 0 && !view.cancelled &&
		(view.has_selection && view.selected_row < u32(len(view.rows)) ||
		 !view.has_selection && len(view.rows) == 0)
}
