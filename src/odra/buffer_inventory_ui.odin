// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../command"
import "../display"
import "../editor_session"
import terminal "../terminal"
import "../ui"

/* BUFFER_INVENTORY_UI_OWNER_ID identifies the built-in Buffer Menu projection owner. */
BUFFER_INVENTORY_UI_OWNER_ID :: ui.Owner_ID(10_002)
/* BUFFER_INVENTORY_UI_MODEL_ID identifies the built-in Buffer Menu model. */
BUFFER_INVENTORY_UI_MODEL_ID :: ui.Model_ID(10_002)
/* BUFFER_INVENTORY_UI_TARGET_GENERATION identifies the Buffer Menu target contract. */
BUFFER_INVENTORY_UI_TARGET_GENERATION :: u64(1)
/* BUFFER_INVENTORY_SELECT_ACTION activates the current checked buffer entry. */
BUFFER_INVENTORY_SELECT_ACTION :: ui.List_Action_ID(1)

@(private)
buffer_inventory_visible_target :: proc() -> editor_session.Visible_Target {
	return editor_session.Visible_Target {
		kind = .UI_Root,
		ui = {
			owner_id = u64(BUFFER_INVENTORY_UI_OWNER_ID),
			model_id = u64(BUFFER_INVENTORY_UI_MODEL_ID),
			generation = BUFFER_INVENTORY_UI_TARGET_GENERATION,
		},
	}
}

@(private)
inventory_workflow_advance_generation :: proc(state: ^Inventory_Workflow_State) -> bool {
	if state == nil || state.model_generation == max(u64) do return false
	state.model_generation += 1
	return true
}

@(private)
inventory_descriptor_index :: proc(
	descriptors: []editor_session.Entry_Descriptor,
	entry: editor_session.Entry_Handle,
) -> (index: int, found: bool) {
	for candidate, descriptor_index in descriptors {
		if candidate.graph.entry == entry do return descriptor_index, true
	}
	return 0, false
}

@(private)
inventory_workflow_visible_descriptors :: proc(
	state: ^Inventory_Workflow_State,
	descriptors: []editor_session.Entry_Descriptor,
	storage: []editor_session.Entry_Descriptor,
) -> []editor_session.Entry_Descriptor {
	if state == nil || !state.terminal_only do return descriptors
	count := 0
	for descriptor in descriptors {
		if descriptor.kind != .Terminal do continue
		if count >= len(storage) do break
		storage[count] = descriptor
		count += 1
	}
	return storage[:count]
}

@(private)
inventory_mark_index :: proc(
	state: ^Inventory_Workflow_State,
	entry: editor_session.Entry_Handle,
) -> (index: int, found: bool) {
	if state == nil do return 0, false
	for mark_index in 0 ..< int(state.mark_count) {
		if state.marks[mark_index].entry == entry do return mark_index, true
	}
	return 0, false
}

@(private)
inventory_workflow_prepare :: proc(
	state: ^Inventory_Workflow_State,
	descriptors: []editor_session.Entry_Descriptor,
	viewport_items: u32,
) -> (ok: bool, failure: ui.Failure) {
	if state == nil || len(descriptors) == 0 ||
	   len(descriptors) > int(editor_session.MAX_INVENTORY_MARKS) ||
	   viewport_items == 0 || viewport_items > ui.MAX_LIST_ITEMS {
		return false, ui.Failure{operation = .Prepare, code = .Invalid_List_View}
	}
	write := 0
	for index in 0 ..< int(state.mark_count) {
		marked := state.marks[index]
		if _, found := inventory_descriptor_index(descriptors, marked.entry); !found do continue
		state.marks[write] = marked
		write += 1
	}
	for index in write ..< int(state.mark_count) do state.marks[index] = {}
	state.mark_count = u32(write)
	current_index, current_found := inventory_descriptor_index(descriptors, state.current_entry)
	if !current_found {
		current_index = 0
		state.current_entry = descriptors[0].graph.entry
	}
	if state.model_generation == 0 do state.model_generation = 1
	previous_position := state.position
	if state.position.presentation_generation == 0 {
		state.position = ui.List_View_Position {
			presentation_generation = 1,
			selection_owner = .View,
			current_item = i32(current_index),
			first_visible_item = 0,
			viewport_items = viewport_items,
		}
	} else {
		state.position.current_item = i32(current_index)
		state.position.viewport_items = viewport_items
		if u32(current_index) < state.position.first_visible_item {
			state.position.first_visible_item = u32(current_index)
		}
		end := u64(state.position.first_visible_item) + u64(viewport_items)
		if u64(current_index) >= end {
			state.position.first_visible_item = u32(current_index) - viewport_items + 1
		}
		if state.position != previous_position {
			if previous_position.presentation_generation == max(u64) {
				return false, ui.Failure{operation = .Resize, code = .Generation_Limit}
			}
			state.position.presentation_generation = previous_position.presentation_generation + 1
		}
	}
	list_state := ui.List_View_State {
		present = true,
		item_count = u32(len(descriptors)),
		position = state.position,
	}
	if !ui.list_view_state_is_valid(list_state) {
		return false, ui.Failure{operation = .Prepare, code = .Invalid_List_View}
	}
	return true, {}
}

@(private)
inventory_workflow_move :: proc(
	state: ^Inventory_Workflow_State,
	descriptors: []editor_session.Entry_Descriptor,
	delta: i32,
) -> (changed, ok: bool, failure: ui.Failure) {
	list_state := ui.List_View_State {
		present = true,
		item_count = u32(len(descriptors)),
		position = state.position,
	}
	next: ui.List_View_State
	next, changed, ok, failure = ui.list_view_move_current(list_state, delta)
	if ok {
		state.position = next.position
		state.current_entry = descriptors[next.position.current_item].graph.entry
	}
	return
}

@(private)
inventory_workflow_set_current_mark :: proc(
	state: ^Inventory_Workflow_State,
	descriptors: []editor_session.Entry_Descriptor,
	kind: command.Buffer_Mark_Kind,
) -> (ok: bool, failure: ui.Failure) {
	if state == nil || state.position.current_item < 0 ||
	   state.position.current_item >= i32(len(descriptors)) ||
	   (kind != .Invalid && kind != .Save && kind != .Kill) {
		return false, ui.Failure{operation = .Navigate, code = .Invalid_List_Mark}
	}
	entry := descriptors[state.position.current_item].graph.entry
	index, found := inventory_mark_index(state, entry)
	if kind == .Invalid {
		if found {
			for current in index ..< int(state.mark_count) - 1 {
				state.marks[current] = state.marks[current + 1]
			}
			state.mark_count -= 1
			state.marks[state.mark_count] = {}
		}
	} else if found {
		state.marks[index].kind = kind
	} else {
		if state.mark_count >= editor_session.DEFAULT_INVENTORY_MARKS {
			return false, ui.Failure {
				operation = .Navigate,
				code = .List_Item_Limit,
				limit = u64(editor_session.DEFAULT_INVENTORY_MARKS),
				actual = u64(state.mark_count) + 1,
			}
		}
		state.marks[state.mark_count] = command.Buffer_Marked_Entry{entry = entry, kind = kind}
		state.mark_count += 1
	}
	if !inventory_workflow_advance_generation(state) {
		return false, ui.Failure{operation = .Navigate, code = .Generation_Limit}
	}
	_, moved, move_failure := inventory_workflow_move(state, descriptors, 1)
	if !moved do return false, move_failure
	return true, {}
}

@(private)
inventory_workflow_clear_marks :: proc(state: ^Inventory_Workflow_State) {
	if state == nil do return
	for index in 0 ..< int(state.mark_count) do state.marks[index] = {}
	state.mark_count = 0
	_ = inventory_workflow_advance_generation(state)
}

@(private)
inventory_workflow_unmark_entry :: proc(
	state: ^Inventory_Workflow_State,
	entry: editor_session.Entry_Handle,
) -> bool {
	index, found := inventory_mark_index(state, entry)
	if !found do return false
	for current in index ..< int(state.mark_count) - 1 {
		state.marks[current] = state.marks[current + 1]
	}
	state.mark_count -= 1
	state.marks[state.mark_count] = {}
	return inventory_workflow_advance_generation(state)
}

@(private)
inventory_workflow_snapshot_marks :: proc(state: ^Inventory_Workflow_State) -> []command.Buffer_Marked_Entry {
	for index in 0 ..< int(state.batch_count) do state.batch[index] = {}
	state.batch_count = state.mark_count
	copy(state.batch[:state.batch_count], state.marks[:state.mark_count])
	return state.batch[:state.batch_count]
}

@(private)
present_buffer_inventory_ui :: proc(
	commands: ^Command_Context,
	session: ^terminal.Session,
	renderer: ^terminal.Renderer,
	constraints: display.Viewport_Constraints,
) -> App_Failure {
	content_rows, rows_ok := transient_input_content_rows(commands, constraints)
	if !rows_ok do return App_Failure{stage = .UI, ui = {operation = .Prepare, code = .Invalid_Layout}}
	descriptors, copied, copy_failure := editor_session.session_descriptors(
		commands.session_owner,
		commands.session_handle,
		commands.temporary_allocator,
	)
	if !copied do return App_Failure{stage = .Session_Access, editor_session = copy_failure}
	defer editor_session.descriptor_batch_close(&descriptors)
	filtered: [editor_session.MAX_LIVE_BUFFERS]editor_session.Entry_Descriptor
	visible := inventory_workflow_visible_descriptors(
		&commands.inventory_workflow,
		descriptors.descriptors,
		filtered[:],
	)
	if prepared, prepare_failure := inventory_workflow_prepare(
		&commands.inventory_workflow,
		visible,
		content_rows,
	); !prepared {
		return App_Failure{stage = .UI, ui = prepare_failure}
	}
	if map_failure := command_context_sync_list_map(commands, .Buffer_Inventory); map_failure.stage != .None {
		return map_failure
	}
	definitions, definitions_error := make(
		[]ui.List_Item_Definition,
		len(visible),
		commands.temporary_allocator,
	)
	if definitions_error != nil {
		return App_Failure{stage = .UI, ui = {operation = .Prepare, code = .Allocation}}
	}
	defer delete(definitions, commands.temporary_allocator)
	text_bytes := 0
	for descriptor in visible {
		text_bytes += len(descriptor.selection_label) + 5
		if commands.inventory_workflow.terminal_only {
			text_bytes += len(descriptor.terminal.working_context) + len(terminal_inventory_lifecycle(descriptor.terminal.lifecycle)) + 16
		}
	}
	text, text_error := make([]u8, text_bytes, commands.temporary_allocator)
	if text_error != nil {
		return App_Failure{stage = .UI, ui = {operation = .Prepare, code = .Allocation}}
	}
	defer delete(text, commands.temporary_allocator)
	offset := 0
	for descriptor, index in visible {
		text[offset] = '.' if descriptor.active else ' '
		text[offset + 1] = '*' if descriptor.modified else ' '
		text[offset + 2] = 'T' if descriptor.kind == .Terminal else ('F' if descriptor.association == .Document else 'U')
		text[offset + 3] = '!' if descriptor.operation != .Idle else ' '
		text[offset + 4] = ' '
		copy(text[offset + 5:], transmute([]u8)descriptor.selection_label)
		length := len(descriptor.selection_label) + 5
		if commands.inventory_workflow.terminal_only {
			lifecycle := terminal_inventory_lifecycle(descriptor.terminal.lifecycle)
			copy(text[offset + length:], "  ")
			length += 2
			copy(text[offset + length:], transmute([]u8)lifecycle)
			length += len(lifecycle)
			copy(text[offset + length:], "  user  ")
			length += 8
			copy(text[offset + length:], transmute([]u8)descriptor.terminal.working_context)
			length += len(descriptor.terminal.working_context)
		}
		mark := ui.List_Mark.None
		if mark_index, marked := inventory_mark_index(
			&commands.inventory_workflow,
			descriptor.graph.entry,
		); marked {
			mark = .Save if commands.inventory_workflow.marks[mark_index].kind == .Save else .Kill
		}
		definitions[index] = ui.List_Item_Definition {
			id = ui.List_Item_ID(descriptor.graph.entry.entry_id),
			text = string(text[offset:offset + length]),
			action = {
				owner_id = BUFFER_INVENTORY_UI_OWNER_ID,
				action_id = BUFFER_INVENTORY_SELECT_ACTION,
				generation = commands.inventory_workflow.model_generation,
			},
			mark = mark,
		}
		offset += length
	}
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
				owner_id = BUFFER_INVENTORY_UI_OWNER_ID,
				model_id = BUFFER_INVENTORY_UI_MODEL_ID,
				generation = ui.Model_Generation(commands.inventory_workflow.model_generation),
			},
			position = commands.inventory_workflow.position,
			mark_lane = true,
		},
		definitions,
	)
	if !projected do return App_Failure{stage = .UI, ui = projection_failure}
	surface, surface_ok, surface_failure := ui.proposal_add_surface(
		&proposal,
		ui.Surface_Descriptor {
			owner_id = BUFFER_INVENTORY_UI_OWNER_ID,
			view = view,
			focusable = true,
			visible = true,
			input_context = 3_002,
			keymap_context = 4_002,
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
terminal_inventory_lifecycle :: proc(value: editor_session.Terminal_Lifecycle) -> string {
	switch value {
	case .Running: return "Running"
	case .Exited:  return "Exited"
	case .Failed:  return "Failed"
	case .Invalid: return "Invalid"
	}
	return "Invalid"
}
