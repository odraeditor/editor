// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../display"
import "../editor_session"
import terminal "../terminal"
import "../ui"

/* STARTUP_UI_OWNER_ID identifies the built-in Startup list projection owner. */
STARTUP_UI_OWNER_ID :: ui.Owner_ID(10_001)
/* STARTUP_UI_MODEL_ID identifies the built-in Startup list model. */
STARTUP_UI_MODEL_ID :: ui.Model_ID(10_001)
/* STARTUP_UI_GENERATION identifies the stable built-in Startup model contract. */
STARTUP_UI_GENERATION :: ui.Model_Generation(1)
/* STARTUP_CREATE_BUFFER_ACTION selects the existing buffer-creation workflow. */
STARTUP_CREATE_BUFFER_ACTION :: ui.List_Action_ID(1)
/* STARTUP_OPEN_PATH_ACTION selects the existing file-opening workflow. */
STARTUP_OPEN_PATH_ACTION :: ui.List_Action_ID(2)
/* STARTUP_OPEN_PROJECT_DIRECTORY_ACTION selects the existing Project-opening workflow. */
STARTUP_OPEN_PROJECT_DIRECTORY_ACTION :: ui.List_Action_ID(3)
/* STARTUP_OPEN_PROJECT_ACTION selects registered Project navigation. */
STARTUP_OPEN_PROJECT_ACTION :: ui.List_Action_ID(4)
/* STARTUP_OPEN_WORKSPACE_ACTION selects persistent Workspace navigation. */
STARTUP_OPEN_WORKSPACE_ACTION :: ui.List_Action_ID(5)
/* STARTUP_ART_ROWS is the accepted compact Odra terminal mark height. */
STARTUP_ART_ROWS :: 7
/* STARTUP_ACTION_ROW_OFFSET separates passive branding from interactive actions. */
STARTUP_ACTION_ROW_OFFSET :: STARTUP_ART_ROWS + 1
/* STARTUP_LIST_ITEM_COUNT bounds the complete branded startup projection. */
STARTUP_LIST_ITEM_COUNT :: 13
/* STARTUP_ART_COLUMNS is the exact width of the accepted terminal mark. */
STARTUP_ART_COLUMNS :: 33
/* STARTUP_SURFACE_COLUMNS fits the complete unmarked terminal mark. */
STARTUP_SURFACE_COLUMNS :: STARTUP_ART_COLUMNS
/* STARTUP_ACTION_COUNT bounds the interactive entries beneath the terminal mark. */
STARTUP_ACTION_COUNT :: 5
/* STARTUP_ACTION_TEXT_CAPACITY bounds one padded startup action in UTF-8 bytes. */
STARTUP_ACTION_TEXT_CAPACITY :: 128

/* STARTUP_ACTION_LABELS defines the visible ordered startup menu entries. */
STARTUP_ACTION_LABELS :: [STARTUP_ACTION_COUNT]string {
	"Create a new buffer",
	"Open File",
	"Open Dir",
	"Open Project",
	"Open Workspace",
}

/* STARTUP_ACTION_IDS maps startup menu rows to their command actions. */
STARTUP_ACTION_IDS :: [STARTUP_ACTION_COUNT]ui.List_Action_ID {
	STARTUP_CREATE_BUFFER_ACTION,
	STARTUP_OPEN_PATH_ACTION,
	STARTUP_OPEN_PROJECT_DIRECTORY_ACTION,
	STARTUP_OPEN_PROJECT_ACTION,
	STARTUP_OPEN_WORKSPACE_ACTION,
}

@(private)
Startup_Workflow_State :: struct {
	position: ui.List_View_Position,
}

@(private)
startup_visible_target :: proc() -> editor_session.Visible_Target {
	return editor_session.Visible_Target {
		kind = .UI_Root,
		ui = {
			owner_id = u64(STARTUP_UI_OWNER_ID),
			model_id = u64(STARTUP_UI_MODEL_ID),
			generation = u64(STARTUP_UI_GENERATION),
		},
	}
}

@(private)
startup_text_cell_width :: proc(
	text: string,
	profile: display.Unicode_Profile,
) -> (cells: u32, ok: bool) {
	offset: u64
	for offset < u64(len(text)) {
		grapheme, grapheme_ok, _ := display.profile_next_grapheme(profile, text, offset)
		if !grapheme_ok do return 0, false
		cluster := text[grapheme.start:grapheme.end]
		width, width_ok, _ := display.profile_cluster_width(
			profile,
			cluster,
			cells,
			display.DEFAULT_TAB_WIDTH,
		)
		if !width_ok || width.is_line_break do return 0, false
		cells += u32(width.cells)
		offset = grapheme.end
	}
	return cells, true
}

@(private)
startup_action_block_inset :: proc(
	profile: display.Unicode_Profile,
) -> (inset: u32, ok: bool) {
	widest: u32
	for label in STARTUP_ACTION_LABELS {
		width, width_ok := startup_text_cell_width(label, profile)
		if !width_ok do return 0, false
		widest = max(widest, width)
	}
	if widest > STARTUP_SURFACE_COLUMNS do return 0, false
	return (STARTUP_SURFACE_COLUMNS - widest) / 2, true
}

@(private)
startup_list_items :: proc(
	action_text: ^[STARTUP_ACTION_COUNT][STARTUP_ACTION_TEXT_CAPACITY]u8,
	profile: display.Unicode_Profile,
) -> (items: [STARTUP_LIST_ITEM_COUNT]ui.List_Item_Definition, ok: bool) {
	if action_text == nil do return {}, false
	action := proc(action_id: ui.List_Action_ID) -> ui.List_Action_Reference {
		return ui.List_Action_Reference {
			owner_id = STARTUP_UI_OWNER_ID,
			action_id = action_id,
			generation = u64(STARTUP_UI_GENERATION),
		}
	}
	items = [STARTUP_LIST_ITEM_COUNT]ui.List_Item_Definition {
		{id = 1, text = " ██████╗ ██████╗ ██████╗  █████╗", passive = true},
		{id = 2, text = "██╔═══██╗██╔══██╗██╔══██╗██╔══██╗", passive = true},
		{id = 3, text = "██║◈☼◈██║██║☼◈██║██████╔╝███████║", passive = true},
		{id = 4, text = "██║☼◆☼██║██║◈☼██║██╔══██╗██╔══██║", passive = true},
		{id = 5, text = "██║◈☼◈██║██║☼◈██║██║  ██║██║◈☼██║", passive = true},
		{id = 6, text = "╚██████╔╝██████╔╝██║  ██║██║  ██║", passive = true},
		{id = 7, text = " ╚═════╝ ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝", passive = true},
		{id = 8, text = "", passive = true},
		{},
		{},
		{},
		{},
		{},
	}
	inset, inset_ok := startup_action_block_inset(profile)
	if !inset_ok do return {}, false
	action_ids := STARTUP_ACTION_IDS
	for label, index in STARTUP_ACTION_LABELS {
		length := int(inset) + len(label)
		if length > STARTUP_ACTION_TEXT_CAPACITY do return {}, false
		for byte_index in 0 ..< int(inset) {
			action_text[index][byte_index] = ' '
		}
		copy(action_text[index][int(inset):], transmute([]u8)label)
		items[STARTUP_ACTION_ROW_OFFSET + index] = ui.List_Item_Definition {
			id = ui.List_Item_ID(STARTUP_ACTION_ROW_OFFSET + index + 1),
			text = string(action_text[index][:length]),
			action = action(action_ids[index]),
		}
	}
	return items, true
}

@(private)
startup_surface_geometry :: proc(
	constraints: display.Viewport_Constraints,
	content_rows: u32,
) -> ui.Cell_Rect {
	height := min(content_rows, u32(STARTUP_LIST_ITEM_COUNT))
	width := min(constraints.width_cells, u32(STARTUP_SURFACE_COLUMNS))
	return ui.Cell_Rect {
		row = i32((content_rows - height) / 2),
		column = i32((constraints.width_cells - width) / 2),
		height = i32(height),
		width = i32(width),
	}
}

@(private)
startup_first_visible_item :: proc(current_item: i32, viewport_items: u32) -> u32 {
	assert(current_item >= STARTUP_ACTION_ROW_OFFSET)
	assert(viewport_items > 0)
	current := u32(current_item)
	if current < viewport_items do return 0
	return current - viewport_items + 1
}

@(private)
startup_workflow_prepare :: proc(
	state: ^Startup_Workflow_State,
	viewport_items: u32,
) -> (ok: bool, failure: ui.Failure) {
	if state == nil || viewport_items == 0 || viewport_items > ui.MAX_LIST_ITEMS {
		return false, ui.Failure{operation = .Resize, code = .Invalid_List_View}
	}
	if state.position.presentation_generation == 0 {
		state.position = ui.List_View_Position {
			presentation_generation = 1,
			selection_owner = .View,
			current_item = STARTUP_ACTION_ROW_OFFSET,
			first_visible_item = startup_first_visible_item(
				STARTUP_ACTION_ROW_OFFSET,
				viewport_items,
			),
			viewport_items = viewport_items,
		}
		return true, {}
	}
	list_state := ui.List_View_State {
		present = true,
		item_count = STARTUP_LIST_ITEM_COUNT,
		position = state.position,
	}
	next, _, resized, resize_failure := ui.list_view_resize(list_state, viewport_items)
	if !resized {
		return false, resize_failure
	}
	next.position.first_visible_item = startup_first_visible_item(
		next.position.current_item,
		viewport_items,
	)
	state.position = next.position
	return true, {}
}

@(private)
startup_workflow_move :: proc(
	state: ^Startup_Workflow_State,
	delta: i32,
) -> (changed, ok: bool, failure: ui.Failure) {
	if state == nil {
		return false, false, ui.Failure{operation = .Navigate, code = .Invalid_List_View}
	}
	list_state := ui.List_View_State {
		present = true,
		item_count = STARTUP_LIST_ITEM_COUNT,
		position = state.position,
	}
	target := i64(state.position.current_item) + i64(delta)
	target = max(
		i64(STARTUP_ACTION_ROW_OFFSET),
		min(target, i64(STARTUP_LIST_ITEM_COUNT - 1)),
	)
	next: ui.List_View_State
	next, changed, ok, failure = ui.list_view_move_current(
		list_state,
		i32(target - i64(state.position.current_item)),
	)
	if ok {
		next.position.first_visible_item = startup_first_visible_item(
			next.position.current_item,
			next.position.viewport_items,
		)
		state.position = next.position
	}
	return changed, ok, failure
}

@(private)
startup_workflow_current_action :: proc(
	state: ^Startup_Workflow_State,
) -> (action: ui.List_Action_ID, ok: bool) {
	if state == nil || state.position.current_item < STARTUP_ACTION_ROW_OFFSET ||
	   state.position.current_item >= STARTUP_LIST_ITEM_COUNT {
		return {}, false
	}
	switch state.position.current_item {
	case 8: return STARTUP_CREATE_BUFFER_ACTION, true
	case 9: return STARTUP_OPEN_PATH_ACTION, true
	case 10: return STARTUP_OPEN_PROJECT_DIRECTORY_ACTION, true
	case 11: return STARTUP_OPEN_PROJECT_ACTION, true
	case 12: return STARTUP_OPEN_WORKSPACE_ACTION, true
	}
	return {}, false
}

@(private)
present_startup_ui :: proc(
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
	geometry := startup_surface_geometry(constraints, content_rows)
	if prepared, prepare_failure := startup_workflow_prepare(
		&commands.startup_workflow,
		u32(geometry.height),
	); !prepared {
		return App_Failure{stage = .UI, ui = prepare_failure}
	}
	if map_failure := command_context_sync_list_map(commands, .Startup); map_failure.stage != .None {
		return map_failure
	}
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
	action_text: [STARTUP_ACTION_COUNT][STARTUP_ACTION_TEXT_CAPACITY]u8
	items, items_ok := startup_list_items(&action_text, display.unicode17_profile())
	if !items_ok {
		return App_Failure{stage = .UI, ui = {operation = .Prepare, code = .Invalid_List_View}}
	}
	view, projected, projection_failure := ui.proposal_project_list_view(
		&proposal,
		ui.List_Projection_Request {
			model = {
				owner_id = STARTUP_UI_OWNER_ID,
				model_id = STARTUP_UI_MODEL_ID,
				generation = STARTUP_UI_GENERATION,
			},
			position = commands.startup_workflow.position,
			read_only = true,
		},
		items[:],
	)
	if !projected do return App_Failure{stage = .UI, ui = projection_failure}
	surface, surface_ok, surface_failure := ui.proposal_add_surface(
		&proposal,
		ui.Surface_Descriptor {
			owner_id = STARTUP_UI_OWNER_ID,
			view = view,
			focusable = true,
			visible = true,
			input_context = 3_001,
			keymap_context = 4_001,
			required_profile = profile.id,
			geometry = geometry,
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
