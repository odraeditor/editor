// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../command"
import "../display"
import "../document"
import "../editor"
import "../editor_session"
import "../filesystem"
import "../hosting"
import "../history"
import "../interaction"
import "../kill_ring"
import "../language"
import "../layout"
import "../product_module"
import "../project"
import edit_transaction "../transaction"
import terminal "../terminal"
import "../ui"
import editor_view "../view"
import "base:runtime"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strconv"
import "core:strings"

/* PRODUCT_MODULE_UI_OWNER_ID identifies loadable product-module projections. */
PRODUCT_MODULE_UI_OWNER_ID :: ui.Owner_ID(0x4F44_5241_4D4F_4455)
/* PRODUCT_MODULE_UI_MODEL_ID identifies the shared product-module model. */
PRODUCT_MODULE_UI_MODEL_ID :: ui.Model_ID(1)
/* PRODUCT_MODULE_UI_TARGET_GENERATION identifies the product-module target contract. */
PRODUCT_MODULE_UI_TARGET_GENERATION :: u64(1)

@(private)
Product_Module_Projection :: struct {
	definitions: []ui.List_Item_Definition,
	text:        []u8,
	position:    ui.List_View_Position,
	mark_lane:   bool,
	generation:  u64,
}

@(private)
Product_Module_Tree_Projection :: struct {
	definitions: []ui.Tree_Node_Definition,
	text:        []u8,
	position:    ui.List_View_Position,
	panel_edge:  ui.Panel_Edge,
	panel_width: u32,
	visible:     bool,
	focused:     bool,
	generation:  u64,
}

@(private)
Product_Module_Document_Context :: struct {
	buffer:          ^editor.Buffer,
	views:           ^editor_view.Registry,
	view:            editor_view.View_Handle,
	transaction_id:  edit_transaction.Transaction_ID,
	undo_unit_id:    edit_transaction.Undo_Unit_ID,
	grouping:        history.Grouping_Context,
	commit_observer: edit_transaction.Commit_Observer,
}

@(private)
Product_Module_Workflow_State :: struct {
	runtime:              product_module.Runtime,
	file_management_runtime: product_module.Runtime,
	workspace_hierarchy_runtime: product_module.Runtime,
	structured_document_runtime: product_module.Runtime,
	projection:           Product_Module_Projection,
	tree_projection:      Product_Module_Tree_Projection,
	return_target:        editor_session.Visible_Target,
	opened_entry:         editor_session.Entry_Handle,
	opened_entry_token:   u64,
	preview_present:      bool,
	preview_created:      bool,
	preview_pane:         layout.Pane_Handle,
	preview_view:         editor_view.View_Handle,
	preview_entry:        editor_session.Entry_Handle,
	preview_prior_entry:  editor_session.Entry_Handle,
	active:               bool,
	available:            bool,
	file_management_available: bool,
	workspace_hierarchy_available: bool,
	structured_document_available: bool,
	workspace_hierarchy_prompt_active: bool,
	active_role:          product_module.Role,
	requested_reload:     bool,
	requested_navigation: bool,
	requested_workspace_navigation: bool,
	requested_project_navigation: bool,
	requested_file_management: []u8,
	requested_workspace_refresh: bool,
	requested_invoke:     []u8,
	document_context:     ^Product_Module_Document_Context,
	host_role:            product_module.Role,
}

@(private)
PRODUCT_MODULE_MANIFEST_LIMIT :: 8

@(private)
Product_Module_Manifest :: struct {
	artifacts: [PRODUCT_MODULE_MANIFEST_LIMIT]product_module.Artifact,
	count:     int,
}

@(private)
product_module_workflow_runtime :: proc(
	commands: ^Command_Context,
	role: product_module.Role,
) -> ^product_module.Runtime {
	if commands == nil do return nil
	switch role {
	case .Source_Control: return &commands.product_module_workflow.runtime
	case .File_Management: return &commands.product_module_workflow.file_management_runtime
	case .Workspace_Hierarchy: return &commands.product_module_workflow.workspace_hierarchy_runtime
	case .Structured_Document: return &commands.product_module_workflow.structured_document_runtime
	case .Invalid:
	}
	return nil
}

@(private)
product_module_workflow_role_available :: proc(
	commands: ^Command_Context,
	role: product_module.Role,
) -> bool {
	if commands == nil do return false
	switch role {
	case .Source_Control: return commands.product_module_workflow.available
	case .File_Management: return commands.product_module_workflow.file_management_available
	case .Workspace_Hierarchy: return commands.product_module_workflow.workspace_hierarchy_available
	case .Structured_Document: return commands.product_module_workflow.structured_document_available
	case .Invalid:
	}
	return false
}

@(private)
product_module_workflow_active_runtime :: proc(commands: ^Command_Context) -> ^product_module.Runtime {
	if commands == nil || !commands.product_module_workflow.active do return nil
	return product_module_workflow_runtime(commands, commands.product_module_workflow.active_role)
}

@(private)
product_module_visible_target :: proc() -> editor_session.Visible_Target {
	return {
		kind = .UI_Root,
		ui = {
			owner_id = u64(PRODUCT_MODULE_UI_OWNER_ID),
			model_id = u64(PRODUCT_MODULE_UI_MODEL_ID),
			generation = PRODUCT_MODULE_UI_TARGET_GENERATION,
		},
	}
}

@(private)
product_module_projection_close :: proc(
	projection: ^Product_Module_Projection,
	allocator: runtime.Allocator,
) {
	if projection == nil do return
	if projection.definitions != nil do delete(projection.definitions, allocator)
	if projection.text != nil do delete(projection.text, allocator)
	projection^ = {}
}

@(private)
product_module_tree_projection_close :: proc(
	projection: ^Product_Module_Tree_Projection,
	allocator: runtime.Allocator,
) {
	if projection == nil do return
	if projection.definitions != nil do delete(projection.definitions, allocator)
	if projection.text != nil do delete(projection.text, allocator)
	projection^ = {}
}

@(private)
product_module_tree_projection_replace :: proc(
	commands: ^Command_Context,
	input: []u8,
) -> product_module.Status {
	if commands == nil || len(input) < size_of(product_module.UI_Tree_Panel_Header) {
		return .Invalid_Argument
	}
	header := (^product_module.UI_Tree_Panel_Header)(raw_data(input))
	if header.schema_version != product_module.UI_TREE_PANEL_SCHEMA_VERSION ||
	   header.row_count == 0 || header.row_count > ui.MAX_TREE_NODES ||
	   header.panel_edge < u8(ui.Panel_Edge.Left) ||
	   header.panel_edge > u8(ui.Panel_Edge.Right) ||
	   header.visible > 1 || header.focused > 1 || header.panel_width == 0 {
		return .Invalid_Argument
	}
	row_bytes := u64(header.row_count) * u64(size_of(product_module.UI_Tree_Panel_Row))
	header_bytes := u64(size_of(product_module.UI_Tree_Panel_Header))
	if row_bytes > u64(len(input)) - header_bytes ||
	   header.text_bytes != u64(len(input)) - header_bytes - row_bytes ||
	   header.text_bytes > product_module.MAX_CALL_BYTES {
		return .Invalid_Argument
	}
	definitions, definitions_error := make(
		[]ui.Tree_Node_Definition,
		int(header.row_count),
		commands.persistent_allocator,
	)
	if definitions_error != nil do return .Failed
	text, text_error := make([]u8, int(header.text_bytes), commands.persistent_allocator)
	if text_error != nil {
		delete(definitions, commands.persistent_allocator)
		return .Failed
	}
	content_start := int(header_bytes + row_bytes)
	copy(text, input[content_start:])
	for index in 0 ..< int(header.row_count) {
		row := (^product_module.UI_Tree_Panel_Row)(rawptr(
			uintptr(raw_data(input)) + uintptr(size_of(product_module.UI_Tree_Panel_Header)) +
			uintptr(index * size_of(product_module.UI_Tree_Panel_Row)),
		))
		if row.id == 0 || row.expandable > 1 || row.expanded > 1 ||
		   row.text_offset > header.text_bytes ||
		   u64(row.text_length) > header.text_bytes - row.text_offset ||
		   u64(row.icon_offset) > header.text_bytes ||
		   u64(row.icon_length) > header.text_bytes - u64(row.icon_offset) {
			delete(definitions, commands.persistent_allocator)
			delete(text, commands.persistent_allocator)
			return .Invalid_Argument
		}
		definition := &definitions[index]
		definition.id = ui.Tree_Node_ID(row.id)
		definition.parent = ui.Tree_Node_ID(row.parent)
		definition.text = string(text[int(row.text_offset):int(row.text_offset + u64(row.text_length))])
		definition.icon = string(text[int(row.icon_offset):int(u64(row.icon_offset) + u64(row.icon_length))])
		definition.icon_role = ui.Tree_Icon_Role(row.icon_role)
		definition.icon_style_role = ui.Style_Role(row.icon_style_role)
		definition.depth = row.depth
		definition.indent_depth = row.indent_depth
		definition.expandable = row.expandable == 1
		definition.expanded = row.expanded == 1
		definition.action = {
			owner_id = ui.Owner_ID(row.action_owner_id),
			action_id = ui.List_Action_ID(row.action_id),
			generation = row.action_generation,
		}
	}
	product_module_tree_projection_close(
		&commands.product_module_workflow.tree_projection,
		commands.persistent_allocator,
	)
	commands.product_module_workflow.tree_projection = {
		definitions = definitions,
		text = text,
		position = {
			presentation_generation = header.presentation_generation,
			selection_owner = .Model,
			current_item = header.current_item,
			first_visible_item = header.first_visible_item,
			viewport_items = header.viewport_items,
		},
		panel_edge = ui.Panel_Edge(header.panel_edge),
		panel_width = header.panel_width,
		visible = header.visible == 1,
		focused = header.focused == 1,
		generation = header.presentation_generation,
	}
	return .Ok
}

@(private)
product_module_projection_replace :: proc(
	commands: ^Command_Context,
	input: []u8,
) -> product_module.Status {
	if commands == nil || len(input) < size_of(product_module.UI_List_Header) {
		return .Invalid_Argument
	}
	header := (^product_module.UI_List_Header)(raw_data(input))
	if header.schema_version != product_module.UI_LIST_SCHEMA_VERSION || header.row_count == 0 ||
	   header.row_count > ui.MAX_LIST_ITEMS || header.selection_owner > u8(ui.Selection_Owner.View) ||
	   header.mark_lane > 1 {
		return .Invalid_Argument
	}
	row_bytes := u64(header.row_count) * u64(size_of(product_module.UI_List_Row))
	header_bytes := u64(size_of(product_module.UI_List_Header))
	if row_bytes > u64(len(input)) - header_bytes ||
	   header.text_bytes != u64(len(input)) - header_bytes - row_bytes ||
	   header.text_bytes > product_module.MAX_CALL_BYTES {
		return .Invalid_Argument
	}
	definitions, definitions_error := make(
		[]ui.List_Item_Definition,
		int(header.row_count),
		commands.persistent_allocator,
	)
	if definitions_error != nil do return .Failed
	text, text_error := make([]u8, int(header.text_bytes), commands.persistent_allocator)
	if text_error != nil {
		delete(definitions, commands.persistent_allocator)
		return .Failed
	}
	content_start := int(header_bytes + row_bytes)
	copy(text, input[content_start:])
	for index in 0 ..< int(header.row_count) {
		row := (^product_module.UI_List_Row)(rawptr(
			uintptr(raw_data(input)) + uintptr(size_of(product_module.UI_List_Header)) +
			uintptr(index * size_of(product_module.UI_List_Row)),
		))
		if row.id == 0 || row.passive > 1 ||
		   row.style_span_count > product_module.UI_LIST_MAX_STYLE_SPANS ||
		   row.text_offset > header.text_bytes ||
		   u64(row.text_length) > header.text_bytes - row.text_offset {
			delete(definitions, commands.persistent_allocator)
			delete(text, commands.persistent_allocator)
			return .Invalid_Argument
		}
		definition := &definitions[index]
		definition.id = ui.List_Item_ID(row.id)
		definition.text = string(text[int(row.text_offset):int(row.text_offset + u64(row.text_length))])
		definition.icon_role = ui.List_Icon_Role(row.icon_role)
		definition.icon_style_role = ui.Style_Role(row.icon_style_role)
		definition.action = {
			owner_id = ui.Owner_ID(row.action_owner_id),
			action_id = ui.List_Action_ID(row.action_id),
			generation = row.action_generation,
		}
		definition.mark = ui.List_Mark(row.mark)
		definition.passive = row.passive == 1
		definition.emphasis_bytes = row.emphasis_bytes
		definition.emphasis_style = ui.Style_Role(row.emphasis_style)
		definition.style_span_count = row.style_span_count
		for span_index in 0 ..< int(row.style_span_count) {
			span := row.style_spans[span_index]
			definition.style_spans[span_index] = {
				start_byte = span.start_byte,
				end_byte = span.end_byte,
				style_role = ui.Style_Role(span.style_role),
			}
		}
	}
	product_module_projection_close(
		&commands.product_module_workflow.projection,
		commands.persistent_allocator,
	)
	commands.product_module_workflow.projection = {
		definitions = definitions,
		text = text,
		position = {
			presentation_generation = header.presentation_generation,
			selection_owner = ui.Selection_Owner(header.selection_owner),
			current_item = header.current_item,
			first_visible_item = header.first_visible_item,
			viewport_items = header.viewport_items,
		},
		mark_lane = header.mark_lane == 1,
		generation = header.presentation_generation,
	}
	return .Ok
}

@(private)
product_module_document_inspection :: proc(
	commands: ^Command_Context,
	flags: u64,
	path: string,
) -> (product_module.Session_Response, product_module.Status) {
	if commands == nil || len(path) == 0 ||
	   flags & (product_module.SESSION_PATH_EXACT | product_module.SESSION_PATH_PREFIX) == 0 {
		return {}, .Invalid_Argument
	}
	batch, copied, _ := editor_session.session_descriptors(
		commands.session_owner,
		commands.session_handle,
		commands.temporary_allocator,
	)
	if !copied do return {}, .Failed
	defer editor_session.descriptor_batch_close(&batch)
	response: product_module.Session_Response
	for descriptor in batch.descriptors {
		if !descriptor.graph.has_document do continue
		access, accessible, _ := editor_session.session_entry_access(
			commands.session_owner,
			descriptor.graph.entry,
		)
		if !accessible do return {}, .Failed
		entry, borrowed, _ := editor_session.entry_access_borrow(access)
		if !borrowed || !entry.has_document || entry.document == nil do return {}, .Failed
		status, inspected, _ := document.document_status(entry.document)
		if !inspected || !status.has_target do continue
		matches := status.target_path == path
		if flags & product_module.SESSION_PATH_PREFIX != 0 {
			matches = strings.has_prefix(status.target_path, path) &&
				(len(status.target_path) == len(path) || path[len(path) - 1] == '/' ||
				 status.target_path[len(path)] == '/')
		}
		if !matches do continue
		response.total += 1
		response.flags |= product_module.SESSION_DOCUMENT_OPEN
		if descriptor.modified {
			response.modified += 1
			response.flags |= product_module.SESSION_DOCUMENT_MODIFIED
		}
	}
	return response, .Ok
}

@(private)
product_module_restore_target :: proc(commands: ^Command_Context) -> product_module.Status {
	if commands == nil do return .Invalid_Argument
	target := commands.product_module_workflow.return_target
	switch target.kind {
	case .Primary_View:
		_, activated, _ := editor_session.session_activate(commands.session_owner, target.entry)
		if !activated do return .Failed
	case .UI_Root:
		_, _, presented, _ := editor_session.session_present_ui(
			commands.session_owner,
			commands.session_handle,
			target.ui,
		)
		if !presented do return .Failed
	case .None:
		return .Failed
	}
	commands.product_module_workflow.return_target = {}
	return .Ok
}

@(private)
product_module_clear_preview :: proc(commands: ^Command_Context) {
	if commands == nil do return
	state := &commands.product_module_workflow
	defer {
		state.preview_present = false
		state.preview_created = false
		state.preview_pane = {}
		state.preview_view = {}
		state.preview_entry = {}
		state.preview_prior_entry = {}
	}
	if !state.preview_present || !command_context_layout_is_live(commands) do return
	handle, handled, _ := layout.registry_handle(&commands.layout_registry)
	if !handled do return
	snapshot, snapshot_error := new(layout.Snapshot, commands.temporary_allocator)
	if snapshot_error != nil do return
	defer free(snapshot, commands.temporary_allocator)
	if snapshot_ok, _ := layout.registry_snapshot_into(&commands.layout_registry, handle, snapshot);
	   !snapshot_ok {
		return
	}
	preview_node: layout.Node_Descriptor
	found := false
	for node in snapshot.nodes[:int(snapshot.node_count)] {
		if node.kind == .Pane && node.pane.pane_id == state.preview_pane.pane_id {
			preview_node = node
			found = true
			break
		}
	}
	if !found do return
	if state.preview_created && snapshot.pane_count > 1 {
		active := snapshot.active_pane
		focused, focused_ok, _ := layout.registry_focus(&commands.layout_registry, preview_node.pane)
		if !focused_ok do return
		_, closed, _ := layout.registry_close_pane(&commands.layout_registry, focused.active)
		if !closed || active.pane_id == preview_node.pane.pane_id do return
		current_handle, current_ok, _ := layout.registry_handle(&commands.layout_registry)
		if !current_ok do return
		current, current_error := new(layout.Snapshot, commands.temporary_allocator)
		if current_error != nil do return
		defer free(current, commands.temporary_allocator)
		if current_snapshot_ok, _ := layout.registry_snapshot_into(
			&commands.layout_registry, current_handle, current,
		); current_snapshot_ok {
			for node in current.nodes[:int(current.node_count)] {
				if node.kind == .Pane && node.pane.pane_id == active.pane_id {
					_, _, _ = layout.registry_focus(&commands.layout_registry, node.pane)
					break
				}
			}
		}
	} else if editor_session.entry_handle_is_valid(state.preview_prior_entry) {
		_, _, _ = layout.registry_replace_pane_buffer(
			&commands.layout_registry,
			preview_node.pane,
			commands.session_owner,
			state.preview_prior_entry,
		)
	}
}

@(private)
product_module_present_preview :: proc(commands: ^Command_Context, target: u64) -> product_module.Status {
	if commands == nil || target == 0 ||
	   target != commands.product_module_workflow.opened_entry_token ||
	   !editor_session.entry_handle_is_valid(commands.product_module_workflow.opened_entry) ||
	   !command_context_layout_is_live(commands) {
		return .Stale
	}
	product_module_clear_preview(commands)
	handle, handled, _ := layout.registry_handle(&commands.layout_registry)
	if !handled do return .Failed
	before, allocation_error := new(layout.Snapshot, commands.temporary_allocator)
	if allocation_error != nil do return .Failed
	defer free(before, commands.temporary_allocator)
	if before_ok, _ := layout.registry_snapshot_into(&commands.layout_registry, handle, before);
	   !before_ok {
		return .Failed
	}
	active_entry := commands.layout_entry
	display_result, displayed, _ := command_context_layout_display_entry_result(
		commands, commands.product_module_workflow.opened_entry, false,
	)
	if editor_session.entry_handle_is_valid(active_entry) {
		_, _, _ = editor_session.session_activate(commands.session_owner, active_entry)
		commands.layout_entry = active_entry
	}
	if !displayed do return .Failed
	prior: editor_session.Entry_Handle
	if !display_result.created {
		for node in before.nodes[:int(before.node_count)] {
			if node.kind == .Pane && node.pane.pane_id == display_result.pane.pane_id {
				prior = node.entry
				break
			}
		}
	}
	state := &commands.product_module_workflow
	state.preview_present = true
	state.preview_created = display_result.created
	state.preview_pane = display_result.pane
	state.preview_view = display_result.view
	state.preview_entry = state.opened_entry
	state.preview_prior_entry = prior
	return .Ok
}

@(private)
product_module_scroll_preview :: proc(commands: ^Command_Context, flags: u64) -> product_module.Status {
	if commands == nil || !commands.product_module_workflow.preview_present do return .Unavailable
	state := &commands.product_module_workflow
	access, accessed, _ := editor_session.session_entry_access(commands.session_owner, state.preview_entry)
	if !accessed do return .Stale
	borrow, borrowed, _ := editor_session.entry_access_borrow(access)
	if !borrowed do return .Stale
	view_state, viewed, _ := editor_view.snapshot(borrow.view_registry, state.preview_view)
	if !viewed do return .Stale
	steps := 1
	if flags & product_module.SESSION_SCROLL_PAGE != 0 {
		handle, handle_ok, _ := layout.registry_handle(&commands.layout_registry)
		if handle_ok {
			if snapshot, snapshot_ok, _ := layout.registry_snapshot(&commands.layout_registry, handle);
			   snapshot_ok {
				for node in snapshot.nodes[:int(snapshot.node_count)] {
					if node.kind == .Pane && node.pane.pane_id == state.preview_pane.pane_id {
						steps = max(1, int(node.geometry.content.height) - 1)
						break
					}
				}
			}
		}
	}
	backward := flags & product_module.SESSION_SCROLL_BACKWARD != 0
	position := view_state.viewport_origin_position
	for _ in 0 ..< steps {
		line, line_ok, _ := editor.buffer_line_at_position(borrow.buffer, position)
		if !line_ok do break
		offset := line.next_start
		if backward {
			if line.start == 0 do break
			previous, previous_ok, _ := editor.buffer_position(
				borrow.buffer, editor.Byte_Offset(u64(line.start) - 1),
			)
			if !previous_ok do break
			previous_line, previous_line_ok, _ := editor.buffer_line_at_position(borrow.buffer, previous)
			if !previous_line_ok do break
			offset = previous_line.start
		} else if line.next_start <= line.start {
			break
		}
		next, next_ok, _ := editor.buffer_position(borrow.buffer, offset)
		if !next_ok do break
		position = next
	}
	if position.byte_offset == view_state.viewport_origin_position.byte_offset do return .Ok
	set, _ := editor_view.set_viewport(
		borrow.view_registry, state.preview_view, position, view_state.horizontal_display_column,
	)
	return .Ok if set else .Failed
}

@(private)
product_module_host_session :: proc(
	commands: ^Command_Context,
	input: []u8,
	output: []u8,
	output_length: ^u64,
) -> product_module.Status {
	if commands == nil || len(input) < size_of(product_module.Session_Request_Header) {
		return .Invalid_Argument
	}
	header := (^product_module.Session_Request_Header)(raw_data(input))
	if header.schema_version != product_module.SESSION_REQUEST_SCHEMA_VERSION ||
	   header.payload_length != u64(len(input) - size_of(product_module.Session_Request_Header)) {
		return .Invalid_Argument
	}
	payload := string(input[size_of(product_module.Session_Request_Header):])
	response: product_module.Session_Response
	status := product_module.Status.Ok
	switch header.action {
	case .Present_Surface:
		previous, _, presented, _ := editor_session.session_present_ui(
			commands.session_owner,
			commands.session_handle,
			product_module_visible_target().ui,
		)
		if !presented do return .Failed
		if commands.product_module_workflow.return_target.kind == .None {
			commands.product_module_workflow.return_target = previous
		}
		if commands.product_module_workflow.host_role != .Invalid {
			commands.product_module_workflow.active = true
			commands.product_module_workflow.active_role = commands.product_module_workflow.host_role
		}
		response.target = 1
	case .Restore_Target:
		if header.target != 1 do return .Stale
		status = product_module_restore_target(commands)
		if status == .Ok {
			commands.product_module_workflow.active = false
			commands.product_module_workflow.active_role = .Invalid
		}
	case .Inspect_Documents:
		response, status = product_module_document_inspection(commands, header.flags, payload)
	case .Open_Path:
		opened, opened_ok, _ := editor_session.session_open_path(
			commands.session_owner,
			editor_session.Open_Path_Request {
				session = commands.session_handle,
				path = payload,
				encoding = .UTF8,
				configuration = commands.entry_configuration,
			},
		)
		if !opened_ok do return .Failed
		commands.product_module_workflow.opened_entry = opened.entry
		commands.product_module_workflow.opened_entry_token += 1
		if commands.product_module_workflow.opened_entry_token == 0 {
			commands.product_module_workflow.opened_entry_token = 1
		}
		response.target = commands.product_module_workflow.opened_entry_token
	case .Present_Entry:
		if header.target == 0 ||
		   header.target != commands.product_module_workflow.opened_entry_token {
			return .Stale
		}
		split_below := header.flags & product_module.SESSION_PRESENT_SPLIT_BELOW != 0
		split_right := header.flags & product_module.SESSION_PRESENT_SPLIT_RIGHT != 0
		if split_below && split_right do return .Invalid_Argument
		if split_below || split_right {
			if product_module_restore_target(commands) != .Ok do return .Failed
			if split, _ := command_context_layout_split_entry(
				commands, commands.product_module_workflow.opened_entry, split_below,
			); !split {
				return .Failed
			}
		} else if header.flags & product_module.SESSION_PRESENT_OTHER_PANE != 0 {
			if product_module_restore_target(commands) != .Ok do return .Failed
			focused := header.flags & product_module.SESSION_PRESENT_FOCUS != 0
			displayed, _ := command_context_layout_display_entry(
				commands,
				commands.product_module_workflow.opened_entry,
				focused,
			)
			if !displayed do return .Failed
		} else {
			_, activated, _ := editor_session.session_activate(
				commands.session_owner,
				commands.product_module_workflow.opened_entry,
			)
			if !activated do return .Failed
		}
		commands.product_module_workflow.active = false
		commands.product_module_workflow.active_role = .Invalid
	case .Present_Position:
		if header.target == 0 ||
		   header.target != commands.product_module_workflow.opened_entry_token ||
		   len(payload) != size_of(product_module.Session_Position) {
			return .Stale
		}
		position_request := (^product_module.Session_Position)(raw_data(input[size_of(product_module.Session_Request_Header):]))
		access, accessed, _ := editor_session.session_entry_access(
			commands.session_owner,
			commands.product_module_workflow.opened_entry,
		)
		if !accessed do return .Stale
		entry, borrowed, _ := editor_session.entry_access_borrow(access)
		if !borrowed || entry.buffer == nil do return .Stale
		stats, stats_ok, _ := editor.buffer_stats(entry.buffer)
		if !stats_ok || u64(stats.revision) != position_request.revision ||
		   position_request.point > stats.text_bytes {
			return .Stale
		}
		position, positioned, _ := editor.buffer_position(
			entry.buffer, editor.Byte_Offset(position_request.point),
		)
		if !positioned do return .Stale
		_, activated, _ := editor_session.session_activate(
			commands.session_owner,
			commands.product_module_workflow.opened_entry,
		)
		if !activated do return .Failed
		moved, _ := editor_view.set_point(entry.view_registry, entry.primary_view, position)
		if !moved do return .Failed
		commands.product_module_workflow.active = false
		commands.product_module_workflow.active_role = .Invalid
	case .Present_Preview:
		status = product_module_present_preview(commands, header.target)
	case .Clear_Preview:
		product_module_clear_preview(commands)
	case .Scroll_Preview:
		status = product_module_scroll_preview(commands, header.flags)
	case .Inspect_Active_Document:
		access, accessed, _ := editor_session.session_active_entry_access(
			commands.session_owner, commands.session_handle,
		)
		if !accessed do return .Unavailable
		entry, borrowed, _ := editor_session.entry_access_borrow(access)
		if !borrowed || !entry.has_document || entry.document == nil do return .Unavailable
		document_status, inspected, _ := document.document_status(entry.document)
		if !inspected || !document_status.has_target || len(document_status.target_path) == 0 {
			return .Unavailable
		}
		if output_length == nil do return .Invalid_Argument
		if len(output) < len(document_status.target_path) do return .Limit
		copy(output, document_status.target_path)
		output_length^ = u64(len(document_status.target_path))
		return .Ok
	case .Invalid:
		return .Invalid_Argument
	}
	if status != .Ok do return status
	if output_length == nil do return .Invalid_Argument
	if len(output) < size_of(response) do return .Limit
	copy(output[:size_of(response)], ([^]u8)(rawptr(&response))[:size_of(response)])
	output_length^ = u64(size_of(response))
	return .Ok
}

@(private)
product_module_host_command :: proc(
	commands: ^Command_Context,
	input: []u8,
) -> product_module.Status {
	if commands == nil || len(input) < size_of(product_module.Command_Request_Header) {
		return .Invalid_Argument
	}
	header := (^product_module.Command_Request_Header)(raw_data(input))
	if header.schema_version != product_module.COMMAND_REQUEST_SCHEMA_VERSION ||
	   header.payload_length != u64(len(input) - size_of(product_module.Command_Request_Header)) {
		return .Invalid_Argument
	}
	switch header.action {
	case .Reload:
		commands.product_module_workflow.requested_reload = true
	case .Present_Navigation:
		commands.product_module_workflow.requested_navigation = true
	case .Present_Workspace_Navigation:
		commands.product_module_workflow.requested_workspace_navigation = true
	case .Present_Project_Navigation:
		commands.product_module_workflow.requested_project_navigation = true
	case .Present_File_Management:
		payload := input[size_of(product_module.Command_Request_Header):]
		if len(payload) == 0 || len(payload) > int(filesystem.MAX_PATH_BYTES) ||
		   !filepath.is_abs(string(payload)) {
			return .Invalid_Argument
		}
		state := &commands.product_module_workflow
		if state.requested_file_management != nil do return .Denied
		request, allocation_error := make([]u8, len(payload), commands.persistent_allocator)
		if allocation_error != nil do return .Failed
		copy(request, payload)
		state.requested_file_management = request
	case .Invoke:
		payload := input[size_of(product_module.Command_Request_Header):]
		if len(payload) == 0 || len(payload) > interaction.MAX_COMMAND_NAME_BYTES {
			return .Invalid_Argument
		}
		state := &commands.product_module_workflow
		if state.requested_invoke != nil do return .Denied
		request, allocation_error := make([]u8, len(payload), commands.persistent_allocator)
		if allocation_error != nil do return .Failed
		copy(request, payload)
		state.requested_invoke = request
	case .Invalid:
		return .Invalid_Argument
	}
	return .Ok
}

@(private)
product_module_host_provider :: proc(
	commands: ^Command_Context,
	input: []u8,
	output: []u8,
	output_length: ^u64,
) -> product_module.Status {
	if commands == nil || output_length == nil ||
	   len(input) < size_of(product_module.Provider_Request_Header) {
		return .Invalid_Argument
	}
	header := (^product_module.Provider_Request_Header)(raw_data(input))
	if header.schema_version != product_module.PROVIDER_REQUEST_SCHEMA_VERSION {
		return .Invalid_Argument
	}
	header_bytes := u64(size_of(product_module.Provider_Request_Header))
	content_bytes := u64(header.service_length) + u64(header.name_length) + header.payload_length
	if content_bytes > u64(len(input)) - header_bytes || header_bytes + content_bytes != u64(len(input)) {
		return .Invalid_Argument
	}
	service_start := size_of(product_module.Provider_Request_Header)
	name_start := service_start + int(header.service_length)
	payload_start := name_start + int(header.name_length)
	service := string(input[service_start:name_start])
	name := string(input[name_start:payload_start])
	payload := input[payload_start:]
	if service == "language.document-symbols" {
		if header.provider_generation == 0 || header.operation != 1 || len(name) == 0 ||
		   len(payload) != 0 {
			return .Invalid_Argument
		}
		return product_module_host_document_symbols(commands, name, output, output_length)
	}
	if commands.racket_runtime == nil do return .Unavailable
	written, ok, _ := hosting.runtime_provider_invoke(
		commands.racket_runtime,
		service,
		header.provider_generation,
		header.operation,
		name,
		payload,
		output,
	)
	if !ok do return .Failed
	output_length^ = written
	return .Ok
}

@(private)
product_module_host_document_symbols :: proc(
	commands: ^Command_Context,
	path: string,
	output: []u8,
	output_length: ^u64,
) -> product_module.Status {
	opened, opened_ok, _ := editor_session.session_open_path(
		commands.session_owner,
		editor_session.Open_Path_Request {
			session = commands.session_handle,
			path = path,
			encoding = .UTF8,
			configuration = commands.entry_configuration,
		},
	)
	if !opened_ok do return .Unavailable
	access, accessed, _ := editor_session.session_entry_access(commands.session_owner, opened.entry)
	if !accessed do return .Failed
	entry, borrowed, _ := editor_session.entry_access_borrow(access)
	if !borrowed || entry.buffer == nil do return .Failed
	document_id := document.Document_ID(0)
	has_document := false
	if entry.has_document && entry.document != nil {
		status, inspected, _ := document.document_status(entry.document)
		if inspected && status.document_id != document.Document_ID(0) {
			document_id = status.document_id
			has_document = true
		}
	}
	request_generation := commands.symbol_workflow.next_request_generation
	result_generation := commands.symbol_workflow.next_result_generation
	if request_generation == language.Symbol_Request_Generation(0) do request_generation = 1
	if result_generation == language.Symbol_Result_Generation(0) do result_generation = 1
	if request_generation == language.Symbol_Request_Generation(max(u64)) ||
	   result_generation == language.Symbol_Result_Generation(max(u64)) {
		return .Limit
	}
	index, indexed, _ := syntax_workflow_symbol_index(
		commands.syntax_workflow,
		entry.buffer,
		document_id,
		has_document,
		request_generation,
		result_generation,
		commands.temporary_allocator,
	)
	if !indexed do return .Unavailable
	defer language.symbol_index_close(&index)
	view, viewed, _ := language.symbol_index_view(&index)
	if !viewed do return .Failed
	text_bytes := 0
	for ordinal in 0 ..< view.symbols {
		descriptor, described, _ := language.symbol_index_descriptor(&index, ordinal)
		if !described do return .Failed
		text_bytes += int(descriptor.name.length)
	}
	header_bytes := size_of(product_module.Symbol_Provider_Response_Header)
	record_bytes := int(view.symbols) * size_of(product_module.Symbol_Provider_Record)
	total_bytes := header_bytes + record_bytes + text_bytes
	if total_bytes > len(output) do return .Limit
	header := product_module.Symbol_Provider_Response_Header {
		schema_version = product_module.SYMBOL_PROVIDER_RESPONSE_SCHEMA_VERSION,
		complete = 1 if view.descriptor.completeness == .Complete else 0,
		provider_generation = u64(view.descriptor.generation),
		source_revision = u64(view.descriptor.scope.source_revision),
		record_count = view.symbols,
		text_bytes = u32(text_bytes),
	}
	copy(output[:header_bytes], ([^]u8)(rawptr(&header))[:header_bytes])
	text_offset := 0
	for ordinal in 0 ..< view.symbols {
		descriptor, described, _ := language.symbol_index_descriptor(&index, ordinal)
		if !described do return .Failed
		record := product_module.Symbol_Provider_Record {
			id = u64(descriptor.id),
			parent_id = u64(descriptor.parent_id),
			start = u64(descriptor.location.start),
			end = u64(descriptor.location.end),
			name_offset = u32(text_offset),
			name_length = descriptor.name.length,
			hierarchy_depth = descriptor.hierarchy_depth,
			kind = u8(descriptor.kind),
		}
		record_start := header_bytes + int(ordinal) * size_of(product_module.Symbol_Provider_Record)
		copy(
			output[record_start:record_start + size_of(record)],
			([^]u8)(rawptr(&record))[:size_of(record)],
		)
		name_start := header_bytes + record_bytes + text_offset
		copy(output[name_start:name_start + int(descriptor.name.length)], descriptor.name.bytes[:descriptor.name.length])
		text_offset += int(descriptor.name.length)
	}
	commands.symbol_workflow.next_request_generation = request_generation + 1
	commands.symbol_workflow.next_result_generation = result_generation + 1
	output_length^ = u64(total_bytes)
	return .Ok
}

@(private)
product_module_host_clipboard :: proc(
	commands: ^Command_Context,
	input: []u8,
) -> product_module.Status {
	if commands == nil || commands.kill_ring == nil || len(input) == 0 do return .Invalid_Argument
	if !kill_ring.ring_is_valid(commands.kill_ring) do return .Unavailable
	stats, inspected, _ := kill_ring.ring_stats(commands.kill_ring)
	if !inspected do return .Failed
	reservation: kill_ring.Reservation
	_, reserved, _ := kill_ring.admission_reserve(
		commands.kill_ring,
		&reservation,
		{expected_generation = stats.generation, kind = .Copy, text = string(input)},
	)
	if !reserved do return .Denied
	_ = kill_ring.reservation_commit_reserved(&reservation)
	return .Ok
}

@(private)
product_module_filesystem_resource :: proc(
	value: product_module.Filesystem_Resource,
) -> filesystem.Resource_ID {
	return {provider = value.provider, device = value.device, inode = value.inode}
}

@(private)
product_module_filesystem_target :: proc(
	commands: ^Command_Context,
	path: string,
	expected: filesystem.Resource_ID,
) -> (parent: string, name: string, parent_id: filesystem.Resource_ID, kind: filesystem.Entry_Kind, ok: bool) {
	if commands == nil || len(path) == 0 || !filepath.is_abs(path) ||
	   !filesystem.resource_id_valid(expected) {
		return
	}
	parent = filepath.dir(path)
	name = filepath.base(path)
	if len(parent) == 0 || len(name) == 0 do return
	batch, observed, _ := filesystem.directory_observe(
		parent, 1,
		{persistent = commands.temporary_allocator, temporary = commands.temporary_allocator},
		true,
	)
	if !observed do return
	defer filesystem.directory_batch_close(&batch)
	for descriptor in batch.descriptors {
		if descriptor.identity == expected && descriptor.name == name {
			parent_id = batch.directory_identity
			kind = descriptor.kind
			ok = true
			return
		}
	}
	return
}

@(private)
product_module_host_filesystem :: proc(
	commands: ^Command_Context,
	input: []u8,
) -> product_module.Status {
	if commands == nil || len(input) < size_of(product_module.Filesystem_Request_Header) {
		return .Invalid_Argument
	}
	header := (^product_module.Filesystem_Request_Header)(raw_data(input))
	if header.schema_version != product_module.FILESYSTEM_REQUEST_SCHEMA_VERSION ||
	   header.action == .Invalid {
		return .Invalid_Argument
	}
	header_bytes := u64(size_of(product_module.Filesystem_Request_Header))
	content_bytes := u64(header.source_length) + u64(header.destination_length)
	if content_bytes != u64(len(input)) - header_bytes ||
	   header.source_length == 0 || header.source_length > u32(filesystem.MAX_PATH_BYTES) ||
	   header.destination_length > u32(filesystem.MAX_PATH_BYTES) {
		return .Invalid_Argument
	}
	source_start := size_of(product_module.Filesystem_Request_Header)
	destination_start := source_start + int(header.source_length)
	source := string(input[source_start:destination_start])
	destination := string(input[destination_start:])
	if !filepath.is_abs(source) do return .Invalid_Argument
	allocators := filesystem.Allocator_Set {
		persistent = commands.persistent_allocator,
		temporary = commands.temporary_allocator,
	}
	if header.action == .Create_File || header.action == .Create_Directory {
		if len(destination) == 0 || filepath.is_abs(destination) do return .Invalid_Argument
		batch, observed, _ := filesystem.directory_observe(
			source, 1,
			{persistent = commands.temporary_allocator, temporary = commands.temporary_allocator},
			true,
		)
		if !observed do return .Stale
		defer filesystem.directory_batch_close(&batch)
		kind := filesystem.Creation_Kind.Regular_File
		if header.action == .Create_Directory do kind = .Directory
		_, created, _ := filesystem.directory_child_create(
			source,
			{parent_identity = batch.directory_identity, name = destination, kind = kind},
			allocators,
		)
		return .Ok if created else .Denied
	}
	expected := product_module_filesystem_resource(header.resource)
	parent, name, parent_id, kind, target_ok := product_module_filesystem_target(
		commands, source, expected,
	)
	if !target_ok do return .Stale
	if header.action == .Delete {
		if len(destination) != 0 do return .Invalid_Argument
		open_count, counted, _ := editor_session.session_document_paths_under(
			commands.session_owner, commands.session_handle, source, kind == .Directory,
		)
		if !counted do return .Failed
		if open_count > 0 do return .Denied
		requests := [?]filesystem.Delete_Request{{identity = expected, name = name, kind = kind}}
		results: [1]filesystem.Delete_Result
		deleted, _ := filesystem.directory_delete_batch_apply(
			parent, parent_id, requests[:], results[:], allocators,
		)
		return .Ok if deleted else .Denied
	}
	if len(destination) == 0 do return .Invalid_Argument
	if header.action == .Rename {
		if filepath.is_abs(destination) do return .Invalid_Argument
		_, moved, _ := filesystem.directory_entry_move(
			parent, parent,
			{
				source_parent_identity = parent_id,
				source_identity = expected,
				source_name = name,
				source_kind = kind,
				destination_parent_identity = parent_id,
				destination_name = destination,
			},
			allocators,
		)
		if !moved do return .Denied
		to, join_error := os.join_path({parent, destination}, commands.temporary_allocator)
		if join_error != nil do return .Failed
		defer delete(to, commands.temporary_allocator)
		_, relocated, _ := editor_session.session_relocate_document_paths(
			commands.session_owner, commands.session_handle,
			{from = source, to = to, directory = kind == .Directory},
		)
		if relocated do return .Ok
		_, _, _ = filesystem.directory_entry_move(
			parent, parent,
			{
				source_parent_identity = parent_id,
				source_identity = expected,
				source_name = destination,
				source_kind = kind,
				destination_parent_identity = parent_id,
				destination_name = name,
			},
			allocators,
		)
		return .Failed
	}
	if !filepath.is_abs(destination) do return .Invalid_Argument
	destination_batch, destination_ok, _ := filesystem.directory_observe(
		destination, 1,
		{persistent = commands.temporary_allocator, temporary = commands.temporary_allocator},
		true,
	)
	if !destination_ok do return .Stale
	defer filesystem.directory_batch_close(&destination_batch)
	if header.action == .Copy {
		_, copied, _ := filesystem.directory_entry_copy(
			parent, destination,
			{
				source_parent_identity = parent_id,
				source_identity = expected,
				source_name = name,
				source_kind = kind,
				destination_parent_identity = destination_batch.directory_identity,
				destination_name = name,
				limits = filesystem.DEFAULT_COPY_LIMITS,
			},
			allocators,
		)
		return .Ok if copied else .Denied
	}
	if header.action != .Move do return .Invalid_Argument
	_, moved, _ := filesystem.directory_entry_move(
		parent, destination,
		{
			source_parent_identity = parent_id,
			source_identity = expected,
			source_name = name,
			source_kind = kind,
			destination_parent_identity = destination_batch.directory_identity,
			destination_name = name,
		},
		allocators,
	)
	if !moved do return .Denied
	to, join_error := os.join_path({destination, name}, commands.temporary_allocator)
	if join_error != nil do return .Failed
	defer delete(to, commands.temporary_allocator)
	_, relocated, _ := editor_session.session_relocate_document_paths(
		commands.session_owner, commands.session_handle,
		{from = source, to = to, directory = kind == .Directory},
	)
	if relocated do return .Ok
	_, _, _ = filesystem.directory_entry_move(
		destination, parent,
		{
			source_parent_identity = destination_batch.directory_identity,
			source_identity = expected,
			source_name = name,
			source_kind = kind,
			destination_parent_identity = parent_id,
			destination_name = name,
		},
		allocators,
	)
	return .Failed
}

@(private)
product_module_workspace_result :: proc(
	commands: ^Command_Context,
	result: ^command.Workspace_Command_Result,
	ok: bool,
	failure: command.Failure_Context,
) -> product_module.Status {
	if !ok {
		command_context_project_failure_diagnostic(commands, failure)
		return .Denied
	}
	if result != nil && result.batch.state != nil do defer command.workspace_command_batch_close(&result.batch)
	commands.product_module_workflow.requested_workspace_refresh = true
	return .Ok
}

@(private)
product_module_workspace_add_project :: proc(
	commands: ^Command_Context,
	project_path: string,
) -> product_module.Status {
	if commands == nil || commands.racket_runtime == nil || len(project_path) == 0 {
		return .Invalid_Argument
	}
	active, active_ok, _ := editor_session.session_active_workspace(
		commands.session_owner, commands.session_handle,
	)
	if !active_ok || !active.active do return .Unavailable
	result, updated, failure := command.workspace_add_project(
		command_context_project_command_context(commands),
		commands.racket_runtime,
		commands.lifecycle_configuration_root,
		editor_session.workspace_id_text(&active.descriptor.id),
		active.descriptor.generation,
		project_path,
	)
	return product_module_workspace_result(commands, &result, updated, failure)
}

@(private)
product_module_host_workspace :: proc(
	commands: ^Command_Context,
	input: []u8,
) -> product_module.Status {
	if commands == nil || commands.racket_runtime == nil ||
	   len(input) < size_of(product_module.Workspace_Request_Header) {
		return .Invalid_Argument
	}
	header := (^product_module.Workspace_Request_Header)(raw_data(input))
	if header.schema_version != product_module.WORKSPACE_REQUEST_SCHEMA_VERSION ||
	   header.action == .Invalid {
		return .Invalid_Argument
	}
	header_bytes := u64(size_of(product_module.Workspace_Request_Header))
	content_bytes := u64(header.project_length) + u64(header.value_length)
	if content_bytes != u64(len(input)) - header_bytes ||
	   header.project_length > u32(filesystem.MAX_PATH_BYTES) {
		return .Invalid_Argument
	}
	project_start := size_of(product_module.Workspace_Request_Header)
	value_start := project_start + int(header.project_length)
	project_path := string(input[project_start:value_start])
	value := string(input[value_start:])
	ctx := command_context_project_command_context(commands)
	if header.action == .Next {
		listed, listed_ok, list_failure := command.workspace_list(
			ctx, commands.racket_runtime, commands.lifecycle_configuration_root,
		)
		if !listed_ok {
			command_context_project_failure_diagnostic(commands, list_failure)
			return .Denied
		}
		defer command.workspace_command_batch_close(&listed.batch)
		if len(listed.batch.descriptors) == 0 do return .Unavailable
		active_id := ""
		if active, active_ok, _ := editor_session.session_active_workspace(
			commands.session_owner, commands.session_handle,
		); active_ok && active.active {
			active_id = editor_session.workspace_id_text(&active.descriptor.id)
		}
		next_index := 0
		for descriptor, index in listed.batch.descriptors {
			if descriptor.id == active_id {
				next_index = (index + 1) % len(listed.batch.descriptors)
				break
			}
		}
		opened, opened_ok, open_failure := command.workspace_open(
			ctx, commands.racket_runtime, commands.lifecycle_configuration_root,
			listed.batch.descriptors[next_index].id,
		)
		if !opened_ok {
			command_context_project_failure_diagnostic(commands, open_failure)
			return .Denied
		}
		defer command.workspace_command_batch_close(&opened.batch)
		if opened.completion != .Opened do return .Denied
		commands.product_module_workflow.requested_workspace_refresh = true
		return .Ok
	}
	if len(project_path) == 0 do return .Invalid_Argument
	active, active_ok, _ := editor_session.session_active_workspace(
		commands.session_owner, commands.session_handle,
	)
	if !active_ok || !active.active do return .Unavailable
	workspace_id := editor_session.workspace_id_text(&active.descriptor.id)
	generation := active.descriptor.generation
	if header.action == .Remove_Project {
		result, updated, failure := command.workspace_remove_project(
			ctx, commands.racket_runtime, commands.lifecycle_configuration_root,
			workspace_id, generation, project_path,
		)
		return product_module_workspace_result(commands, &result, updated, failure)
	}
	if header.action == .Move_Project_Earlier || header.action == .Move_Project_Later {
		result, moved, failure := command.workspace_move_project(
			ctx, commands.racket_runtime, commands.lifecycle_configuration_root,
			workspace_id, generation, project_path,
			header.action == .Move_Project_Earlier,
		)
		return product_module_workspace_result(commands, &result, moved, failure)
	}
	if header.action != .Rename_Project || len(value) == 0 do return .Invalid_Argument
	roots, roots_ok, _ := editor_session.session_roots(commands.session_owner, commands.session_handle)
	if !roots_ok do return .Failed
	defer editor_session.root_batch_close(&roots)
	project_generation: project.Project_Generation
	for root in roots.descriptors {
		if root.kind == .Project && root.path == project_path {
			project_generation = root.project.generation
			break
		}
	}
	if project_generation == 0 do return .Stale
	_, renamed, rename_failure := command.project_rename(
		ctx, commands.racket_runtime, commands.project_catalog_root,
		project_path, value, project_generation,
	)
	if !renamed {
		command_context_project_failure_diagnostic(commands, rename_failure)
		return .Denied
	}
	commands.product_module_workflow.requested_workspace_refresh = true
	return .Ok
}

@(private)
product_module_host_document_inspect :: proc(
	commands: ^Command_Context,
	output: []u8,
	output_length: ^u64,
) -> product_module.Status {
	ctx := commands.product_module_workflow.document_context
	if ctx == nil || ctx.buffer == nil || ctx.views == nil || output_length == nil do return .Unavailable
	logical, logical_ok, _ := editor_view.snapshot(ctx.views, ctx.view)
	if !logical_ok do return .Stale
	snapshot: editor.Buffer_Snapshot
	opened, _ := editor.buffer_snapshot_open(ctx.buffer, &snapshot)
	if !opened do return .Failed
	defer editor.buffer_snapshot_close(&snapshot)
	stats, stats_ok, _ := editor.buffer_snapshot_stats(&snapshot)
	if !stats_ok || logical.hidden_range_count > editor_view.MAX_HIDDEN_RANGES {
		return .Limit
	}
	range_bytes := u64(logical.hidden_range_count) * u64(size_of(product_module.Document_Range))
	if stats.text_bytes > product_module.MAX_CALL_BYTES -
	                       u64(size_of(product_module.Document_Snapshot_Header)) - range_bytes {
		return .Limit
	}
	required := size_of(product_module.Document_Snapshot_Header) + int(stats.text_bytes + range_bytes)
	if len(output) < required do return .Limit
	hidden_ranges, ranges_error := make(
		[]editor_view.Hidden_Range,
		int(logical.hidden_range_count),
		commands.temporary_allocator,
	)
	if ranges_error != nil do return .Failed
	defer delete(hidden_ranges, commands.temporary_allocator)
	visibility, ranges_ok, _ := editor_view.visibility_copy_ranges(ctx.views, ctx.view, hidden_ranges)
	if !ranges_ok || visibility.generation != logical.visibility_generation ||
	   visibility.source_revision != stats.revision ||
	   visibility.range_count != logical.hidden_range_count {
		return .Stale
	}
	header := product_module.Document_Snapshot_Header {
		schema_version = product_module.DOCUMENT_REQUEST_SCHEMA_VERSION,
		buffer_id = u64(stats.buffer_id),
		revision = u64(stats.revision),
		point = u64(logical.point_position.byte_offset),
		view_generation = logical.state_generation,
		visibility_generation = u64(logical.visibility_generation),
		source_length = stats.text_bytes,
		hidden_range_count = logical.hidden_range_count,
	}
	if logical.mark.present {
		header.flags |= product_module.DOCUMENT_SNAPSHOT_MARK_PRESENT
		header.mark = u64(logical.mark.position.byte_offset)
	}
	if logical.region_active do header.flags |= product_module.DOCUMENT_SNAPSHOT_REGION_ACTIVE
	copy(output[:size_of(header)], ([^]u8)(rawptr(&header))[:size_of(header)])
	copied, read_ok, _ := editor.buffer_snapshot_read(
		&snapshot,
		0,
		output[size_of(header):size_of(header) + int(stats.text_bytes)],
	)
	if !read_ok || copied != stats.text_bytes do return .Failed
	range_start := size_of(header) + int(stats.text_bytes)
	for hidden, index in hidden_ranges {
		row := product_module.Document_Range {
			start = u64(hidden.start.byte_offset),
			end = u64(hidden.end.byte_offset),
		}
		offset := range_start + index * size_of(product_module.Document_Range)
		copy(output[offset:offset + size_of(row)], ([^]u8)(rawptr(&row))[:size_of(row)])
	}
	output_length^ = u64(required)
	return .Ok
}

@(private)
product_module_host_document_rewrite :: proc(
	commands: ^Command_Context,
	header: ^product_module.Document_Request_Header,
	payload: []u8,
) -> product_module.Status {
	ctx := commands.product_module_workflow.document_context
	if ctx == nil || ctx.buffer == nil || ctx.views == nil || header.count == 0 ||
	   u64(header.count) > edit_transaction.MAX_SPLICES {
		return .Invalid_Argument
	}
	stats, stats_ok, _ := editor.buffer_stats(ctx.buffer)
	if !stats_ok || u64(stats.revision) != header.base_revision do return .Stale
	row_bytes := u64(header.count) * u64(size_of(product_module.Document_Splice))
	if row_bytes > u64(len(payload)) do return .Invalid_Argument
	text := payload[int(row_bytes):]
	splices, allocation_error := make(
		[]edit_transaction.Base_Splice,
		int(header.count),
		commands.temporary_allocator,
	)
	if allocation_error != nil do return .Failed
	defer delete(splices, commands.temporary_allocator)
	for index in 0 ..< int(header.count) {
		row := (^product_module.Document_Splice)(rawptr(
			uintptr(raw_data(payload)) + uintptr(index * size_of(product_module.Document_Splice)),
		))
		if row.start > row.end || row.end > stats.text_bytes || row.text_offset > u64(len(text)) ||
		   row.text_length > u64(len(text)) - row.text_offset {
			return .Invalid_Argument
		}
		start, start_ok, _ := editor.buffer_position(ctx.buffer, editor.Byte_Offset(row.start))
		end, end_ok, _ := editor.buffer_position(ctx.buffer, editor.Byte_Offset(row.end))
		if !start_ok || !end_ok do return .Stale
		splices[index] = {
			start = start,
			end = end,
			replacement = string(text[int(row.text_offset):int(row.text_offset + row.text_length)]),
		}
	}
	transaction: edit_transaction.Transaction
	started, _ := edit_transaction.transaction_begin(
		&transaction,
		ctx.transaction_id,
		ctx.undo_unit_id,
		ctx.buffer,
		{kind = .Language_Tool, descriptor = "structured-document-module"},
		"structured-document-module",
		{persistent = commands.persistent_allocator, temporary = commands.temporary_allocator},
	)
	if !started do return .Failed
	defer if edit_transaction.transaction_is_valid(&transaction) {
		edit_transaction.transaction_close(&transaction)
	}
	applied, _ := edit_transaction.transaction_apply_batch(&transaction, splices)
	if !applied do return .Denied
	if commands.history_store != nil {
		tracked, _ := edit_transaction.transaction_track_history(
			&transaction, commands.history_store, ctx.grouping,
		)
		if !tracked do return .Failed
	}
	validated, _ := edit_transaction.transaction_validate(&transaction)
	if !validated do return .Denied
	_, committed, _ := edit_transaction.transaction_commit(&transaction, ctx.commit_observer)
	if !committed do return .Failed
	return .Ok
}

@(private)
product_module_host_document_move :: proc(
	commands: ^Command_Context,
	header: ^product_module.Document_Request_Header,
) -> product_module.Status {
	ctx := commands.product_module_workflow.document_context
	if ctx == nil || ctx.buffer == nil || ctx.views == nil do return .Unavailable
	stats, stats_ok, _ := editor.buffer_stats(ctx.buffer)
	if !stats_ok || u64(stats.revision) != header.base_revision || header.point > stats.text_bytes {
		return .Stale
	}
	position, positioned, _ := editor.buffer_position(ctx.buffer, editor.Byte_Offset(header.point))
	if !positioned do return .Stale
	moved, _ := editor_view.move_point(ctx.views, ctx.view, position, 0, .Deactivate)
	return .Ok if moved else .Failed
}

@(private)
product_module_host_document_visibility :: proc(
	commands: ^Command_Context,
	header: ^product_module.Document_Request_Header,
	payload: []u8,
) -> product_module.Status {
	ctx := commands.product_module_workflow.document_context
	if ctx == nil || ctx.buffer == nil || ctx.views == nil ||
	   u64(header.count) * u64(size_of(product_module.Document_Range)) != u64(len(payload)) {
		return .Invalid_Argument
	}
	stats, stats_ok, _ := editor.buffer_stats(ctx.buffer)
	if !stats_ok || u64(stats.revision) != header.base_revision do return .Stale
	ranges, allocation_error := make(
		[]editor_view.Hidden_Range,
		int(header.count),
		commands.temporary_allocator,
	)
	if allocation_error != nil do return .Failed
	defer delete(ranges, commands.temporary_allocator)
	for index in 0 ..< int(header.count) {
		row := (^product_module.Document_Range)(rawptr(
			uintptr(raw_data(payload)) + uintptr(index * size_of(product_module.Document_Range)),
		))
		if row.start >= row.end || row.end > stats.text_bytes do return .Invalid_Argument
		start, start_ok, _ := editor.buffer_position(ctx.buffer, editor.Byte_Offset(row.start))
		end, end_ok, _ := editor.buffer_position(ctx.buffer, editor.Byte_Offset(row.end))
		if !start_ok || !end_ok do return .Stale
		ranges[index] = {start = start, end = end}
	}
	_, replaced, _ := editor_view.visibility_replace(ctx.views, ctx.view, ranges)
	return .Ok if replaced else .Failed
}

@(private)
product_module_host_document :: proc(
	commands: ^Command_Context,
	input: []u8,
	output: []u8,
	output_length: ^u64,
) -> product_module.Status {
	if commands == nil || len(input) < size_of(product_module.Document_Request_Header) {
		return .Invalid_Argument
	}
	header := (^product_module.Document_Request_Header)(raw_data(input))
	if header.schema_version != product_module.DOCUMENT_REQUEST_SCHEMA_VERSION ||
	   header.payload_length != u64(len(input) - size_of(product_module.Document_Request_Header)) {
		return .Invalid_Argument
	}
	payload := input[size_of(product_module.Document_Request_Header):]
	switch header.action {
	case .Inspect: return product_module_host_document_inspect(commands, output, output_length)
	case .Apply_Rewrite: return product_module_host_document_rewrite(commands, header, payload)
	case .Move_Point: return product_module_host_document_move(commands, header)
	case .Replace_Visibility: return product_module_host_document_visibility(commands, header, payload)
	case .Invalid: return .Invalid_Argument
	}
	return .Invalid_Argument
}

@(private)
product_module_host_process :: proc(
	commands: ^Command_Context,
	input: []u8,
) -> product_module.Status {
	if commands == nil || len(input) < size_of(product_module.Process_Request_Header) {
		return .Invalid_Argument
	}
	header := (^product_module.Process_Request_Header)(raw_data(input))
	content_length := u64(header.working_directory_length) + u64(header.command_length)
	if header.schema_version != product_module.PROCESS_REQUEST_SCHEMA_VERSION ||
	   header.action == .Invalid || header.working_directory_length == 0 ||
	   header.command_length == 0 || header.command_length > MAX_SHELL_COMMAND_BYTES ||
	   content_length != u64(len(input) - size_of(product_module.Process_Request_Header)) {
		return .Invalid_Argument
	}
	directory_start := size_of(product_module.Process_Request_Header)
	command_start := directory_start + int(header.working_directory_length)
	directory := string(input[directory_start:command_start])
	command_text := string(input[command_start:])
	kind := Terminal_One_Shot_Kind.Shell
	if header.action == .Async_Shell do kind = .Async_Shell
	_, failure := command_context_run_shell_command(commands, command_text, kind, directory)
	return .Ok if failure.stage == .None else .Failed
}

@(private)
product_module_host_call :: proc "c" (
	capability: u64,
	operation: product_module.Host_Operation,
	input_pointer: ^u8,
	input_length: u64,
	output_pointer: ^u8,
	output_capacity: u64,
	output_length: ^u64,
) -> product_module.Status {
	context = runtime.default_context()
	if capability == 0 || input_length > product_module.MAX_CALL_BYTES ||
	   output_capacity > product_module.MAX_CALL_BYTES || input_length > 0 && input_pointer == nil ||
	   output_capacity > 0 && output_pointer == nil {
		return .Invalid_Argument
	}
	commands := (^Command_Context)(uintptr(capability))
	input: []u8
	output: []u8
	if input_length > 0 do input = ([^]u8)(input_pointer)[:int(input_length)]
	if output_capacity > 0 do output = ([^]u8)(output_pointer)[:int(output_capacity)]
	if output_length != nil do output_length^ = 0
	switch operation {
	case .Diagnostic:
		command_context_set_diagnostic(commands, string(input))
		return .Ok
	case .Command:
		return product_module_host_command(commands, input)
	case .Prompt:
		if len(input) == 1 {
			commands.product_module_workflow.workspace_hierarchy_prompt_active = input[0] == 1
		}
		return .Ok
	case .Session:
		return product_module_host_session(commands, input, output, output_length)
	case .UI:
		return product_module_projection_replace(commands, input)
	case .Process:
		return product_module_host_process(commands, input)
	case .Provider:
		return product_module_host_provider(commands, input, output, output_length)
	case .Tree_UI:
		return product_module_tree_projection_replace(commands, input)
	case .Clipboard:
		return product_module_host_clipboard(commands, input)
	case .Filesystem:
		return product_module_host_filesystem(commands, input)
	case .Workspace:
		return product_module_host_workspace(commands, input)
	case .Document:
		return product_module_host_document(commands, input, output, output_length)
	case .Invalid:
		return .Invalid_Argument
	}
	return .Invalid_Argument
}

/* Product_Module_Manifest_Record is one validated loadable module declaration. */
Product_Module_Manifest_Record :: struct {
	identity:    string,
	version:     string,
	role:        string,
	artifact:    string,
	digest:      string,
	size:        string,
	entrypoint:  string,
	abi_minimum: string,
	abi_maximum: string,
}

@(private)
product_module_manifest_value :: proc(line, key: string) -> (string, bool) {
	prefix := fmt.tprintf("%s=", key)
	if !strings.has_prefix(line, prefix) || len(line) == len(prefix) do return "", false
	return line[len(prefix):], true
}

@(private)
product_module_manifest_hex :: proc(value: string, output: []u8) -> bool {
	if len(value) != len(output) * 2 do return false
	for _, index in output {
		high := value[index * 2]
		low := value[index * 2 + 1]
		high_value := high - '0' if high >= '0' && high <= '9' else high - 'a' + 10 if high >= 'a' && high <= 'f' else 255
		low_value := low - '0' if low >= '0' && low <= '9' else low - 'a' + 10 if low >= 'a' && low <= 'f' else 255
		if high_value > 15 || low_value > 15 do return false
		output[index] = high_value << 4 | low_value
	}
	return true
}

@(private)
product_module_manifest_artifact :: proc(
	manifest_path: string,
	record: Product_Module_Manifest_Record,
	allocator: runtime.Allocator,
) -> (product_module.Artifact, bool) {
	if len(record.identity) == 0 || len(record.version) == 0 ||
	   len(record.role) == 0 || len(record.artifact) == 0 ||
	   len(record.identity) > product_module.MAX_IDENTITY_BYTES ||
	   len(record.version) > product_module.MAX_VERSION_BYTES ||
	   len(record.entrypoint) == 0 ||
	   len(record.entrypoint) > product_module.MAX_ENTRYPOINT_BYTES ||
	   strings.contains(record.artifact, "/") || strings.contains(record.artifact, "\\") ||
	   record.artifact == "." || record.artifact == ".." {
		return {}, false
	}
	size, size_ok := strconv.parse_u64_of_base(record.size, 10)
	abi_minimum, minimum_ok := strconv.parse_u64_of_base(record.abi_minimum, 10)
	abi_maximum, maximum_ok := strconv.parse_u64_of_base(record.abi_maximum, 10)
	if !size_ok || size == 0 || !minimum_ok || !maximum_ok ||
	   abi_minimum == 0 || abi_minimum > u64(max(u32)) || abi_maximum > u64(max(u32)) {
		return {}, false
	}
	path, path_error := os.join_path(
		{filepath.dir(manifest_path), record.artifact},
		allocator,
	)
	if path_error != nil do return {}, false
	defer delete(path, allocator)
	if len(path) > product_module.MAX_ARTIFACT_PATH_BYTES do return {}, false
	artifact: product_module.Artifact
	artifact.identity_length = u16(copy(artifact.identity[:], record.identity))
	artifact.version_length = u16(copy(artifact.version[:], record.version))
	artifact.path_length = u16(copy(artifact.path[:], path))
	artifact.size = size
	artifact.entrypoint_length = u16(copy(artifact.entrypoint[:], record.entrypoint))
	artifact.abi_minimum = u32(abi_minimum)
	artifact.abi_maximum = u32(abi_maximum)
	switch record.role {
	case "source-control": artifact.role = .Source_Control
	case "file-management": artifact.role = .File_Management
	case "workspace-hierarchy": artifact.role = .Workspace_Hierarchy
	case "structured-document": artifact.role = .Structured_Document
	case: return {}, false
	}
	if !product_module_manifest_hex(record.digest, artifact.digest[:]) do return {}, false
	return artifact, true
}

@(private)
product_module_manifest_load :: proc(
	path: string,
	allocator: runtime.Allocator,
) -> (Product_Module_Manifest, bool) {
	if len(path) == 0 || !filepath.is_abs(path) do return {}, false
	content, read_error := os.read_entire_file(path, allocator)
	if read_error != nil do return {}, false
	defer delete(content, allocator)
	lines := strings.split_lines(string(content), allocator)
	defer delete(lines, allocator)
	if len(lines) < 4 || lines[0] != "odra-product-modules 1" do return {}, false
	in_module := false
	manifest: Product_Module_Manifest
	record: Product_Module_Manifest_Record
	for line in lines[1:] {
		if line == "module" {
			if in_module do return {}, false
			in_module = true
			record = {}
			continue
		}
		if line == "end" {
			if !in_module do return {}, false
			if manifest.count >= len(manifest.artifacts) do return {}, false
			artifact, prepared := product_module_manifest_artifact(path, record, allocator)
			if !prepared do return {}, false
			for index in 0 ..< manifest.count {
				if manifest.artifacts[index].role == artifact.role do return {}, false
			}
			manifest.artifacts[manifest.count] = artifact
			manifest.count += 1
			in_module = false
			continue
		}
		if !in_module || len(line) == 0 do continue
		if identity, identity_ok := product_module_manifest_value(line, "identity"); identity_ok do record.identity = identity
		else if version, version_ok := product_module_manifest_value(line, "version"); version_ok do record.version = version
		else if role, role_ok := product_module_manifest_value(line, "role"); role_ok do record.role = role
		else if artifact_name, artifact_ok := product_module_manifest_value(line, "artifact"); artifact_ok do record.artifact = artifact_name
		else if digest, digest_ok := product_module_manifest_value(line, "digest"); digest_ok do record.digest = digest
		else if size_text, size_ok := product_module_manifest_value(line, "size"); size_ok do record.size = size_text
		else if entrypoint, entrypoint_ok := product_module_manifest_value(line, "entrypoint"); entrypoint_ok do record.entrypoint = entrypoint
		else if abi_minimum, minimum_ok := product_module_manifest_value(line, "abi-minimum"); minimum_ok do record.abi_minimum = abi_minimum
		else if abi_maximum, maximum_ok := product_module_manifest_value(line, "abi-maximum"); maximum_ok do record.abi_maximum = abi_maximum
		else do return {}, false
	}
	return manifest, manifest.count > 0 && !in_module
}

@(private)
product_module_default_manifest_path :: proc(allocator: runtime.Allocator) -> (string, bool) {
	if len(os.args) == 0 do return "", false
	executable, path_error := filepath.abs(os.args[0], allocator)
	if path_error != nil do return "", false
	directory := filepath.dir(executable)
	path, join_error := os.join_path(
		{directory, "modules", "product-modules.manifest"},
		allocator,
	)
	delete(executable, allocator)
	if join_error != nil do return "", false
	return path, true
}

@(private)
product_module_workflow_init :: proc(commands: ^Command_Context) -> bool {
	if commands == nil do return false
	path, resolved := product_module_default_manifest_path(commands.temporary_allocator)
	if !resolved do return false
	defer delete(path, commands.temporary_allocator)
	manifest, prepared := product_module_manifest_load(path, commands.temporary_allocator)
	if !prepared do return false
	loaded_count := 0
	for index in 0 ..< manifest.count {
		artifact := &manifest.artifacts[index]
		module_runtime := product_module_workflow_runtime(commands, artifact.role)
		if module_runtime == nil do continue
		loaded, _ := product_module.load(module_runtime, artifact)
		if !loaded {
			continue
		}
		opened, _ := product_module.open(
			module_runtime,
			product_module_host_call,
			u64(uintptr(commands)),
		)
		if !opened {
			_, _ = product_module.close(module_runtime)
			continue
		}
		switch artifact.role {
		case .Source_Control: commands.product_module_workflow.available = true
		case .File_Management: commands.product_module_workflow.file_management_available = true
		case .Workspace_Hierarchy: commands.product_module_workflow.workspace_hierarchy_available = true
		case .Structured_Document:
			_, activated, _ := product_module.call(module_runtime, .Activate, nil, nil)
			if activated {
				commands.product_module_workflow.structured_document_available = true
			}
		case .Invalid:
		}
		loaded_count += 1
	}
	return loaded_count > 0
}

@(private)
product_module_workflow_configure :: proc(
	commands: ^Command_Context,
	generation: u64,
	payload: []u8,
	disposition := product_module.Configuration_Disposition.Confirmed,
) -> bool {
	if commands == nil do return false
	if !commands.product_module_workflow.available do return true
	if generation == 0 || disposition == .Invalid ||
	   u64(len(payload)) > product_module.MAX_CALL_BYTES - u64(size_of(product_module.Configuration_Request_Header)) {
		return false
	}
	header := product_module.Configuration_Request_Header {
		schema_version = product_module.CONFIGURATION_REQUEST_SCHEMA_VERSION,
		disposition = disposition,
		generation = generation,
		payload_length = u64(len(payload)),
	}
	request, allocation_error := make(
		[]u8,
		size_of(header) + len(payload),
		commands.temporary_allocator,
	)
	if allocation_error != nil do return false
	defer delete(request, commands.temporary_allocator)
	copy(request[:size_of(header)], ([^]u8)(rawptr(&header))[:size_of(header)])
	copy(request[size_of(header):], payload)
	_, configured, _ := product_module.call(
		&commands.product_module_workflow.runtime,
		.Configure,
		request,
		nil,
	)
	return configured
}

@(private)
product_module_workflow_close :: proc(commands: ^Command_Context) {
	if commands == nil do return
	state := &commands.product_module_workflow
	product_module_clear_preview(commands)
	product_module_projection_close(&state.projection, commands.persistent_allocator)
	product_module_tree_projection_close(&state.tree_projection, commands.persistent_allocator)
	if state.requested_file_management != nil {
		delete(state.requested_file_management, commands.persistent_allocator)
		state.requested_file_management = nil
	}
	if state.requested_invoke != nil {
		delete(state.requested_invoke, commands.persistent_allocator)
		state.requested_invoke = nil
	}
	if state.runtime.lifecycle != .Invalid && state.runtime.lifecycle != .Closed {
		_, _ = product_module.close(&state.runtime)
	}
	if state.file_management_runtime.lifecycle != .Invalid &&
	   state.file_management_runtime.lifecycle != .Closed {
		_, _ = product_module.close(&state.file_management_runtime)
	}
	if state.workspace_hierarchy_runtime.lifecycle != .Invalid &&
	   state.workspace_hierarchy_runtime.lifecycle != .Closed {
		_, _ = product_module.close(&state.workspace_hierarchy_runtime)
	}
	if state.structured_document_runtime.lifecycle != .Invalid &&
	   state.structured_document_runtime.lifecycle != .Closed {
		_, _ = product_module.close(&state.structured_document_runtime)
	}
	state.active = false
	state.available = false
	state.file_management_available = false
	state.workspace_hierarchy_available = false
	state.structured_document_available = false
	state.workspace_hierarchy_prompt_active = false
	state.active_role = .Invalid
}

@(private)
product_module_workflow_deactivate_active :: proc(commands: ^Command_Context) -> bool {
	if commands == nil || !commands.product_module_workflow.active do return true
	module_runtime := product_module_workflow_active_runtime(commands)
	if module_runtime == nil do return false
	product_module_clear_preview(commands)
	_, deactivated, _ := product_module.call(module_runtime, .Deactivate, nil, nil)
	if !deactivated {
		return false
	}
	product_module_projection_close(
		&commands.product_module_workflow.projection,
		commands.persistent_allocator,
	)
	commands.product_module_workflow.active = false
	commands.product_module_workflow.active_role = .Invalid
	return true
}

@(private)
product_module_workflow_activate_source_control :: proc(
	commands: ^Command_Context,
) -> (Interaction_Result, App_Failure) {
	if commands == nil || !commands.product_module_workflow.available {
		command_context_set_diagnostic(commands, "Source control module is unavailable")
		return Interaction_Result{changed = true}, {}
	}
	if commands.product_module_workflow.active &&
	   !product_module_workflow_deactivate_active(commands) {
		return {}, {stage = .Command_Dispatch}
	}
	document_owner := commands.document_owner
	if document_owner == nil {
		command_context_set_diagnostic(commands, "Source control requires an associated local file")
		return Interaction_Result{changed = true}, {}
	}
	status, inspected, _ := document.document_status(document_owner)
	if !inspected || !status.has_target || len(status.target_path) == 0 {
		command_context_set_diagnostic(commands, "Source control requires an associated local file")
		return Interaction_Result{changed = true}, {}
	}
	directory := filepath.dir(status.target_path)
	_, activated, _ := product_module.call(
		&commands.product_module_workflow.runtime,
		.Activate,
		transmute([]u8)directory,
		nil,
	)
	if !activated {
		command_context_set_diagnostic(commands, "Source control module could not activate")
		return Interaction_Result{changed = true}, {}
	}
	commands.product_module_workflow.active = true
	commands.product_module_workflow.active_role = .Source_Control
	if !product_module_workflow_refresh_projection(commands) {
		command_context_set_diagnostic(commands, "Source control module could not publish its initial view")
	}
	return Interaction_Result{changed = true}, {}
}

@(private)
product_module_workflow_activate_file_management :: proc(
	commands: ^Command_Context,
	path: string,
) -> (Interaction_Result, App_Failure) {
	if commands == nil || len(path) == 0 ||
	   !product_module_workflow_role_available(commands, .File_Management) {
		command_context_set_diagnostic(commands, "File-management module is unavailable")
		return Interaction_Result{changed = true}, {}
	}
	if commands.product_module_workflow.active &&
	   !product_module_workflow_deactivate_active(commands) {
		return {}, {stage = .Command_Dispatch}
	}
	module_runtime := product_module_workflow_runtime(commands, .File_Management)
	_, activated, _ := product_module.call(
		module_runtime,
		.Activate,
		transmute([]u8)path,
		nil,
	)
	if !activated {
		command_context_set_diagnostic(commands, "Directory could not be opened")
		return Interaction_Result{changed = true}, {}
	}
	commands.product_module_workflow.active = true
	commands.product_module_workflow.active_role = .File_Management
	if !product_module_workflow_refresh_projection(commands) {
		command_context_set_diagnostic(commands, "Directory view could not publish")
	}
	return Interaction_Result{changed = true}, {}
}

@(private)
product_module_workflow_activate_workspace_hierarchy_payload :: proc(
	commands: ^Command_Context,
	payload: string,
) -> (Interaction_Result, App_Failure) {
	if commands == nil || len(payload) == 0 ||
	   !product_module_workflow_role_available(commands, .Workspace_Hierarchy) {
		command_context_set_diagnostic(commands, "Workspace-hierarchy module is unavailable")
		return {changed = true}, {}
	}
	module_runtime := product_module_workflow_runtime(commands, .Workspace_Hierarchy)
	if module_runtime.lifecycle == .Active {
		_, deactivated, _ := product_module.call(module_runtime, .Deactivate, nil, nil)
		if !deactivated {
			return {}, {stage = .Command_Dispatch}
		}
	}
	_, activated, failure := product_module.call(
		module_runtime,
		.Activate,
		transmute([]u8)payload,
		nil,
	)
	if !activated {
		command_context_set_diagnostic(
			commands,
			fmt.tprintf("Workspace hierarchy could not activate (%v/%v)", failure.code, failure.status),
		)
		return {changed = true}, {}
	}
	return {changed = true}, {}
}

@(private)
product_module_workflow_activate_workspace_hierarchy_directory :: proc(
	commands: ^Command_Context,
	path: string,
) -> (Interaction_Result, App_Failure) {
	if commands == nil || len(path) == 0 do return {}, {stage = .Component_Access}
	payload := fmt.tprintf("directory\n%s\t%s", filepath.base(path), path)
	return product_module_workflow_activate_workspace_hierarchy_payload(commands, payload)
}

@(private)
product_module_workflow_activate_workspace_hierarchy_projects :: proc(
	commands: ^Command_Context,
	workspace_context: bool,
) -> (Interaction_Result, App_Failure) {
	if commands == nil || commands.session_owner == nil do return {}, {stage = .Component_Access}
	roots, roots_ok, _ := editor_session.session_roots(commands.session_owner, commands.session_handle)
	if !roots_ok do return {}, {stage = .Session_Access}
	defer editor_session.root_batch_close(&roots)
	active_project, active_ok, _ := editor_session.session_active_project(
		commands.session_owner, commands.session_handle,
	)
	if !active_ok || !active_project.active {
		command_context_set_diagnostic(commands, "No active Project is available")
		return {changed = true}, {}
	}
	active_workspace, workspace_ok, _ := editor_session.session_active_workspace(
		commands.session_owner, commands.session_handle,
	)
	use_workspace := workspace_context && workspace_ok && active_workspace.active
	builder, builder_error := strings.builder_make(commands.temporary_allocator)
	if builder_error != nil do return {}, {stage = .Component_Access}
	defer strings.builder_destroy(&builder)
	mode := "workspace\n" if use_workspace else "project\n"
	if strings.write_string(&builder, mode) != len(mode) do return {}, {stage = .Component_Access}
	written := 0
	for root in roots.descriptors {
		if root.kind != .Project || (!use_workspace && root.project != active_project.descriptor.handle) {
			continue
		}
		label := filepath.base(root.path)
		access, access_ok, _ := editor_session.session_project_registry_access(
			commands.session_owner, commands.session_handle, root.project,
		)
		if access_ok {
			registry, borrowed, _ := editor_session.project_registry_access_borrow(access)
			if borrowed {
				descriptor, described, _ := project.registry_project_descriptor(registry, root.project)
				if described do label = project.project_name_text(&descriptor.name)
			}
		}
		if strings.write_string(&builder, label) != len(label) ||
		   strings.write_byte(&builder, '\t') != 1 ||
		   strings.write_string(&builder, root.path) != len(root.path) ||
		   strings.write_byte(&builder, '\n') != 1 {
			return {}, {stage = .Component_Access}
		}
		written += 1
		if !use_workspace do break
	}
	if written == 0 do return {}, {stage = .Session_Access}
	payload := strings.to_string(builder)
	return product_module_workflow_activate_workspace_hierarchy_payload(commands, payload)
}

@(private)
product_module_workflow_refresh_projection :: proc(commands: ^Command_Context) -> bool {
	if commands == nil || !commands.product_module_workflow.active do return false
	module_runtime := product_module_workflow_active_runtime(commands)
	if module_runtime == nil do return false
	_, inspected, failure := product_module.call(
		module_runtime,
		.Inspect,
		nil,
		nil,
	)
	if inspected do return true
	if failure.status == .Unavailable {
		commands.product_module_workflow.active = false
		commands.product_module_workflow.active_role = .Invalid
		product_module_projection_close(
			&commands.product_module_workflow.projection,
			commands.persistent_allocator,
		)
		return true
	}
	return false
}

@(private)
product_module_workflow_apply_requests :: proc(
	commands: ^Command_Context,
	constraints: display.Viewport_Constraints,
) -> (Interaction_Result, App_Failure) {
	if commands == nil do return {}, {stage = .Command_Dispatch}
	changed := false
	if commands.product_module_workflow.requested_reload {
		commands.product_module_workflow.requested_reload = false
		result, failure := command_context_reload_personal_commands(commands)
		if failure.stage != .None do return {}, failure
		changed = changed || result.changed
		if result.changed && commands.product_module_workflow.active {
			changed = product_module_workflow_refresh_projection(commands) || changed
		}
	}
	if commands.product_module_workflow.requested_navigation {
		commands.product_module_workflow.requested_navigation = false
		result, failure := product_module_workflow_present_command_navigation(
			commands, constraints,
		)
		if failure.stage != .None do return {}, failure
		changed = changed || result.changed
	}
	if commands.product_module_workflow.requested_workspace_navigation {
		commands.product_module_workflow.requested_workspace_navigation = false
		result, failure := command_context_present_workspace_navigation(
			commands, .Workspace_Hierarchy_Module_Switch,
		)
		if failure.stage != .None do return {}, failure
		changed = changed || result.changed
	}
	if commands.product_module_workflow.requested_project_navigation {
		commands.product_module_workflow.requested_project_navigation = false
		result, failure := command_context_present_project_navigation(
			commands, .Workspace_Hierarchy_Module_Add,
		)
		if failure.stage != .None do return {}, failure
		changed = changed || result.changed
	}
	if commands.product_module_workflow.requested_file_management != nil {
		state := &commands.product_module_workflow
		request := state.requested_file_management
		state.requested_file_management = nil
		defer delete(request, commands.persistent_allocator)
		path := string(request)
		result, failure := product_module_workflow_activate_file_management(commands, path)
		if failure.stage != .None do return {}, failure
		changed = changed || result.changed
	}
	if commands.product_module_workflow.requested_workspace_refresh {
		commands.product_module_workflow.requested_workspace_refresh = false
		result, failure := product_module_workflow_activate_workspace_hierarchy_projects(
			commands, true,
		)
		if failure.stage != .None do return {}, failure
		changed = changed || result.changed
	}
	if commands.product_module_workflow.requested_invoke != nil {
		state := &commands.product_module_workflow
		request := state.requested_invoke
		state.requested_invoke = nil
		defer delete(request, commands.persistent_allocator)
		name := string(request)
		handle, found, lookup_failure := interaction.command_lookup(commands.registry, name)
		if !found {
			return {}, {stage = .Command_Dispatch, interaction = lookup_failure}
		}
		return {changed = true, deferred_command = handle}, {}
	}
	return {changed = changed}, {}
}

@(private)
product_module_workflow_present_command_navigation :: proc(
	commands: ^Command_Context,
	constraints: display.Viewport_Constraints,
) -> (Interaction_Result, App_Failure) {
	if commands == nil || !commands.product_module_workflow.active ||
	   commands.product_module_workflow.return_target.kind != .Primary_View {
		return {}, {stage = .Session_Access}
	}
	target := commands.product_module_workflow.return_target
	access, access_ok, access_failure := editor_session.session_entry_access(
		commands.session_owner,
		target.entry,
	)
	if !access_ok {
		return {}, {stage = .Session_Access, editor_session = access_failure}
	}
	entry, borrowed, borrow_failure := editor_session.entry_access_borrow(access)
	if !borrowed {
		return {}, {stage = .Session_Access, editor_session = borrow_failure}
	}
	_, activated, activation_failure := editor_session.session_activate(
		commands.session_owner,
		target.entry,
	)
	if !activated {
		return {}, {stage = .Session_Access, editor_session = activation_failure}
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
		return {}, {stage = .Session_Access, editor_session = reconcile_failure}
	}
	if present_failure.stage != .None do return {}, present_failure
	commands.candidate_ui.return_target = product_module_visible_target()
	return result, {}
}

@(private)
product_module_workflow_invoke :: proc(
	commands: ^Command_Context,
	metadata: interaction.Command_Metadata,
	constraints: display.Viewport_Constraints,
) -> (Interaction_Result, App_Failure) {
	if commands == nil || !commands.product_module_workflow.active || len(metadata.name) == 0 ||
	   metadata.route.provider == 0 || metadata.route.operation == 0 ||
	   len(metadata.name) > int(product_module.MAX_CALL_BYTES - u64(size_of(product_module.Invocation_Request_Header))) {
		return {}, {stage = .Command_Dispatch}
	}
	module_runtime := product_module_workflow_active_runtime(commands)
	if module_runtime == nil do return {}, {stage = .Command_Dispatch}
	header := product_module.Invocation_Request_Header {
		schema_version = product_module.INVOCATION_REQUEST_SCHEMA_VERSION,
		provider = u16(metadata.route.provider),
		operation = metadata.route.operation,
		name_length = u32(len(metadata.name)),
	}
	request, allocation_error := make(
		[]u8,
		size_of(header) + len(metadata.name),
		commands.temporary_allocator,
	)
	if allocation_error != nil do return {}, {stage = .Command_Dispatch}
	defer delete(request, commands.temporary_allocator)
	copy(request[:size_of(header)], ([^]u8)(rawptr(&header))[:size_of(header)])
	copy(request[size_of(header):], transmute([]u8)metadata.name)
	_, invoked, _ := product_module.call(
		module_runtime,
		.Invoke,
		request,
		nil,
	)
	if !invoked {
		command_context_set_diagnostic(commands, "Product module command was rejected")
	}
	request_result, request_failure := product_module_workflow_apply_requests(
		commands, constraints,
	)
	if request_failure.stage != .None do return {}, request_failure
	if request_result.deferred_command.registry_generation != 0 {
		request_result.changed = true
		return request_result, {}
	}
	if !product_module_workflow_refresh_projection(commands) &&
	   commands.product_module_workflow.active {
		command_context_set_diagnostic(commands, "Product module view could not refresh")
	}
	request_result.changed = true
	return request_result, {}
}

@(private)
product_module_workflow_invoke_role :: proc(
	commands: ^Command_Context,
	role: product_module.Role,
	metadata: interaction.Command_Metadata,
	constraints: display.Viewport_Constraints,
) -> (Interaction_Result, App_Failure) {
	if role == commands.product_module_workflow.active_role &&
	   commands.product_module_workflow.active {
		return product_module_workflow_invoke(commands, metadata, constraints)
	}
	if commands == nil || len(metadata.name) == 0 || metadata.route.provider == 0 ||
	   metadata.route.operation == 0 ||
	   !product_module_workflow_role_available(commands, role) {
		return {}, {stage = .Command_Dispatch}
	}
	module_runtime := product_module_workflow_runtime(commands, role)
	if module_runtime == nil || module_runtime.lifecycle != .Active {
		return {}, {stage = .Command_Dispatch}
	}
	header := product_module.Invocation_Request_Header {
		schema_version = product_module.INVOCATION_REQUEST_SCHEMA_VERSION,
		provider = u16(metadata.route.provider),
		operation = metadata.route.operation,
		name_length = u32(len(metadata.name)),
	}
	request, allocation_error := make(
		[]u8, size_of(header) + len(metadata.name), commands.temporary_allocator,
	)
	if allocation_error != nil do return {}, {stage = .Command_Dispatch}
	defer delete(request, commands.temporary_allocator)
	copy(request[:size_of(header)], ([^]u8)(rawptr(&header))[:size_of(header)])
	copy(request[size_of(header):], transmute([]u8)metadata.name)
	commands.product_module_workflow.host_role = role
	defer commands.product_module_workflow.host_role = .Invalid
	_, invoked, failure := product_module.call(module_runtime, .Invoke, request, nil)
	if !invoked {
		if failure.status != .Unavailable {
			command_context_set_diagnostic(commands, "Product module command was rejected")
		}
		return {changed = true}, {}
	}
	request_result, request_failure := product_module_workflow_apply_requests(
		commands, constraints,
	)
	if request_failure.stage != .None do return {}, request_failure
	request_result.changed = true
	return request_result, {}
}

@(private)
product_module_workflow_invoke_structured_document :: proc(
	commands: ^Command_Context,
	buffer: ^editor.Buffer,
	views: ^editor_view.Registry,
	view: editor_view.View_Handle,
	command_handle: interaction.Command_Handle,
	constraints: display.Viewport_Constraints,
	transaction_id: edit_transaction.Transaction_ID,
	undo_unit_id: edit_transaction.Undo_Unit_ID,
	grouping: history.Grouping_Context,
	commit_observer: edit_transaction.Commit_Observer,
) -> (Interaction_Result, App_Failure) {
	if commands == nil || buffer == nil || views == nil {
		return {}, {stage = .Command_Dispatch}
	}
	metadata, found, metadata_failure := interaction.command_metadata(commands.registry, command_handle)
	if !found do return {}, {stage = .Command_Dispatch, interaction = metadata_failure}
	state := &commands.product_module_workflow
	if state.document_context != nil do return {}, {stage = .Command_Dispatch}
	document_context := Product_Module_Document_Context {
		buffer = buffer,
		views = views,
		view = view,
		transaction_id = transaction_id,
		undo_unit_id = undo_unit_id,
		grouping = grouping,
		commit_observer = commit_observer,
	}
	state.document_context = &document_context
	defer state.document_context = nil
	return product_module_workflow_invoke_role(
		commands,
		.Structured_Document,
		metadata,
		constraints,
	)
}

@(private)
product_module_workflow_select_role :: proc(
	commands: ^Command_Context,
	role: product_module.Role,
	item_id: u64,
	schema_version: u32,
	constraints: display.Viewport_Constraints,
) -> (Interaction_Result, App_Failure) {
	if commands == nil || item_id == 0 || schema_version == 0 ||
	   !product_module_workflow_role_available(commands, role) {
		return {}, {stage = .Command_Dispatch}
	}
	module_runtime := product_module_workflow_runtime(commands, role)
	if module_runtime == nil || module_runtime.lifecycle != .Active {
		return {}, {stage = .Command_Dispatch}
	}
	request := product_module.Selection_Request {
		schema_version = schema_version,
		item_id = item_id,
	}
	commands.product_module_workflow.host_role = role
	defer commands.product_module_workflow.host_role = .Invalid
	_, selected, _ := product_module.call(
		module_runtime,
		.Select,
		([^]u8)(rawptr(&request))[:size_of(request)],
		nil,
	)
	if !selected {
		return {}, {stage = .Command_Dispatch}
	}
	result, request_failure := product_module_workflow_apply_requests(commands, constraints)
	if request_failure.stage != .None do return {}, request_failure
	result.changed = true
	return result, {}
}

@(private)
product_module_input_request :: proc(
	input: interaction.Input,
	storage: []u8,
) -> ([]u8, bool) {
	if len(storage) < size_of(product_module.Input_Request_Header) do return nil, false
	header: product_module.Input_Request_Header
	header.schema_version = product_module.INPUT_REQUEST_SCHEMA_VERSION
	switch input.kind {
	case .Key:
		header.kind = .Key
		header.key_kind = product_module.Key_Kind(input.stroke.kind)
		header.modifiers = transmute(u8)input.stroke.modifiers
		header.scalar = i32(input.stroke.scalar)
	case .Text_Commit:
		if len(input.text) == 0 || len(input.text) > len(storage) - size_of(header) do return nil, false
		header.kind = .Text_Commit
		header.text_length = u32(len(input.text))
	case .Pointer, .Invalid:
		return nil, false
	}
	copy(storage[:size_of(header)], ([^]u8)(rawptr(&header))[:size_of(header)])
	if header.text_length > 0 {
		copy(storage[size_of(header):], transmute([]u8)input.text)
	}
	return storage[:size_of(header) + int(header.text_length)], true
}

@(private)
product_module_workflow_dispatch_input :: proc(
	commands: ^Command_Context,
	input: interaction.Input,
	constraints: display.Viewport_Constraints,
	direct_command: interaction.Command_Handle = {},
) -> (Interaction_Result, App_Failure) {
	if commands == nil || !commands.product_module_workflow.active do return {}, {stage = .UI}
	module_runtime := product_module_workflow_active_runtime(commands)
	if module_runtime == nil do return {}, {stage = .UI}
	if direct_command.registry_generation != 0 {
		metadata, found, metadata_failure := interaction.command_metadata(
			commands.registry,
			direct_command,
		)
		if !found {
			return {}, {
				stage = .Command_Dispatch,
				interaction = metadata_failure,
			}
		}
		native_route, native_route_ok := command.native_route_decode(metadata.route)
		if native_route_ok {
			#partial switch native_route {
			case .Request_Editor_Exit:
				return command_context_request_exit(commands, direct_command, nil)
			case .Dir_Open, .Maksym_Open_Directory, .Maksym_Open_Directory_Other_Pane,
			     .Maksym_Open_Directory_Below, .Maksym_Open_Directory_Right,
			     .Maksym_Open_Containing_Directory, .Maksym_Open_Containing_Directory_Other_Pane:
				return command_context_dispatch_maksym_route(
					commands,
					native_route,
					constraints,
					direct_command,
				)
			}
		}
		return product_module_workflow_invoke(commands, metadata, constraints)
	}
	storage: [size_of(product_module.Input_Request_Header) + interaction.MAX_TEXT_BYTES]u8
	request, encoded := product_module_input_request(input, storage[:])
	if !encoded do return {}, {}
	_, dispatched, _ := product_module.call(
		module_runtime,
		.Input,
		request,
		nil,
	)
	if !dispatched {
		command_context_set_diagnostic(commands, "Product module input was rejected")
		return Interaction_Result{changed = true}, {}
	}
	request_result, request_failure := product_module_workflow_apply_requests(
		commands, constraints,
	)
	if request_failure.stage != .None do return {}, request_failure
	if request_result.deferred_command.registry_generation != 0 {
		request_result.changed = true
		return request_result, {}
	}
	if !product_module_workflow_refresh_projection(commands) &&
	   commands.product_module_workflow.active {
		command_context_set_diagnostic(commands, "Product module view could not refresh")
	}
	request_result.changed = true
	return request_result, {}
}

@(private)
product_module_workflow_dispatch_role_input :: proc(
	commands: ^Command_Context,
	role: product_module.Role,
	input: interaction.Input,
) -> (Interaction_Result, App_Failure) {
	if commands == nil || !product_module_workflow_role_available(commands, role) {
		return {}, {stage = .UI}
	}
	module_runtime := product_module_workflow_runtime(commands, role)
	if module_runtime == nil || module_runtime.lifecycle != .Active do return {}, {stage = .UI}
	storage: [size_of(product_module.Input_Request_Header) + interaction.MAX_TEXT_BYTES]u8
	request, encoded := product_module_input_request(input, storage[:])
	if !encoded do return {}, {}
	_, dispatched, _ := product_module.call(module_runtime, .Input, request, nil)
	if !dispatched {
		return {}, {stage = .Command_Dispatch}
	}
	return {changed = true}, {}
}

@(private)
product_module_workflow_step :: proc(commands: ^Command_Context) -> bool {
	if commands == nil || !commands.product_module_workflow.active do return false
	module_runtime := product_module_workflow_active_runtime(commands)
	if module_runtime == nil do return false
	changed: [1]u8
	written, stepped, failure := product_module.call(
		module_runtime,
		.Step,
		nil,
		changed[:],
	)
	if !stepped {
		if failure.status == .Unavailable {
			commands.product_module_workflow.active = false
			commands.product_module_workflow.active_role = .Invalid
			product_module_projection_close(
				&commands.product_module_workflow.projection,
				commands.persistent_allocator,
			)
			return true
		}
		commands.product_module_workflow.active = false
		commands.product_module_workflow.active_role = .Invalid
		command_context_set_diagnostic(commands, "Product module stopped after a failed turn")
		return true
	}
	if written != 1 || changed[0] == 0 do return false
	return product_module_workflow_refresh_projection(commands)
}

@(private)
present_product_module_ui :: proc(
	commands: ^Command_Context,
	session: ^terminal.Session,
	renderer: ^terminal.Renderer,
	constraints: display.Viewport_Constraints,
) -> App_Failure {
	if commands == nil || !commands.product_module_workflow.active ||
	   len(commands.product_module_workflow.projection.definitions) == 0 {
		return App_Failure{stage = .UI}
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
	projection := &commands.product_module_workflow.projection
	view, projected, projection_failure := ui.proposal_project_list_view(
		&proposal,
		ui.List_Projection_Request {
			model = {
				owner_id = PRODUCT_MODULE_UI_OWNER_ID,
				model_id = PRODUCT_MODULE_UI_MODEL_ID,
				generation = ui.Model_Generation(max(projection.generation, 1)),
			},
			position = projection.position,
			read_only = true,
			mark_lane = projection.mark_lane,
		},
		projection.definitions,
	)
	if !projected do return App_Failure{stage = .UI, ui = projection_failure}
	surface, surface_ok, surface_failure := ui.proposal_add_surface(
		&proposal,
		ui.Surface_Descriptor {
			owner_id = PRODUCT_MODULE_UI_OWNER_ID,
			view = view,
			focusable = true,
			visible = true,
			input_context = 3_090,
			keymap_context = 4_090,
			required_profile = profile.id,
			geometry = {height = i32(constraints.height_rows), width = i32(constraints.width_cells)},
		},
	)
	if !surface_ok do return App_Failure{stage = .UI, ui = surface_failure}
	node, node_ok, node_failure := ui.proposal_add_surface_node(&proposal, surface)
	if !node_ok do return App_Failure{stage = .UI, ui = node_failure}
	if root_ok, root_failure := ui.proposal_set_root(&proposal, node, surface); !root_ok {
		return App_Failure{stage = .UI, ui = root_failure}
	}
	root, published, publish_failure := ui.proposal_publish(registry, &proposal, profile)
	if !published do return App_Failure{stage = .UI, ui = publish_failure}
	previous := commands.ui_root
	commands.ui_root = root
	pointer_capture_reconcile_root(commands, previous, root)
	snapshot, copied, copy_failure := ui.registry_snapshot(registry, root, profile)
	if !copied do return App_Failure{stage = .UI, ui = copy_failure}
	defer ui.snapshot_close(&snapshot)
	presented, presentation_failure := terminal.renderer_present_ui(
		renderer,
		session,
		terminal.UI_Presentation{root = &snapshot},
	)
	if !presented do return App_Failure{stage = .Presentation, terminal = presentation_failure}
	return {}
}
