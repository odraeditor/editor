// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package maksym_module

import "../filesystem"
import "../maksym"
import "../product_module"
import "../ui"
import "base:runtime"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

MAKSYM_MODULE_HEADER_ID :: u64(1)
MAKSYM_MODULE_STATUS_ID :: u64(0xFFFF_FFFF_FFFF_FFFE)
MAKSYM_TARGET_SET_ID :: maksym.Target_Set_ID(1)
MAKSYM_SHELL_COMMAND_BYTES :: 4_096

Input_Mode :: enum u8 {
	Browse,
	Jump,
	Edit,
	Create_Directory,
	Copy_Targets,
	Move_Targets,
	Delete_Targets,
	Shell_Targets,
	Shell_Targets_Async,
	Shell_Directory,
	Filter_Name,
	Pattern_Match,
	Pattern_Replacement,
	Pattern_Confirm,
	Find_Relative,
}

Input_Prefix :: enum u8 {
	None,
	Control_X,
	Control_C,
	Control_Zero,
	Percent,
}

Maksym_Item_Reference :: struct {
	id:       u64,
	identity: filesystem.Resource_ID,
}

Module_Instance :: struct {
	host_call:          product_module.Host_Call,
	capability:         u64,
	buffer:             maksym.Directory_Buffer,
	projection:         maksym.Projection,
	targets:            maksym.Target_Set,
	editable:           maksym.Editable_Listing,
	pending:            maksym.Rename_Plan,
	edited_names:       []string,
	jump_filter:        string,
	allocator:          runtime.Allocator,
	temporary_allocator: runtime.Allocator,
	next_generation:    u64,
	presentation_generation: u64,
	previous_target:    u64,
	mode:               Input_Mode,
	prefix:             Input_Prefix,
	active:             bool,
	status:             [192]u8,
	status_length:      u16,
	item_references:    []Maksym_Item_Reference,
	next_item_id:       u64,
	input_text:         [int(filesystem.MAX_PATH_BYTES)]u8,
	input_length:       int,
	listing_filter:     string,
	pattern_text:       string,
	replacement_text:   string,
}

@(export)
odra_product_module_entrypoint :: proc "c" (
	descriptor: ^product_module.Descriptor,
	descriptor_size: u64,
) -> product_module.Status {
	if descriptor == nil || descriptor_size != size_of(product_module.Descriptor) {
		return .Invalid_Argument
	}
	value: product_module.Descriptor
	value.struct_size = size_of(product_module.Descriptor)
	value.abi_minimum = product_module.ABI_VERSION
	value.abi_maximum = product_module.ABI_VERSION
	value.role = .File_Management
	value.identity_length = u16(copy(value.identity[:], "odra.maksym"))
	value.version_length = u16(copy(value.version[:], "1.0.0"))
	value.open = module_open
	value.call = module_call
	value.close = module_close
	descriptor^ = value
	return .Ok
}

@(private)
module_open :: proc "c" (
	host_call: product_module.Host_Call,
	capability: u64,
	instance: ^u64,
) -> product_module.Status {
	context = runtime.default_context()
	if host_call == nil || capability == 0 || instance == nil do return .Invalid_Argument
	state := new(Module_Instance)
	if state == nil do return .Failed
	state.host_call = host_call
	state.capability = capability
	state.allocator = context.allocator
	state.temporary_allocator = context.temp_allocator
	state.next_generation = 1
	state.next_item_id = 2
	instance^ = u64(uintptr(state))
	return .Ok
}

@(private)
module_call :: proc "c" (
	instance: u64,
	operation: product_module.Operation,
	input: ^u8,
	input_length: u64,
	output: ^u8,
	output_capacity: u64,
	output_length: ^u64,
) -> product_module.Status {
	context = runtime.default_context()
	if instance == 0 || output_length == nil || input_length > product_module.MAX_CALL_BYTES ||
	   output_capacity > product_module.MAX_CALL_BYTES {
		return .Invalid_Argument
	}
	output_length^ = 0
	state := (^Module_Instance)(uintptr(instance))
	input_bytes: []u8
	if input_length > 0 {
		if input == nil do return .Invalid_Argument
		input_bytes = ([^]u8)(input)[:int(input_length)]
	}
	_ = output
	switch operation {
	case .Activate: return module_activate(state, string(input_bytes))
	case .Invoke: return module_invoke(state, input_bytes)
	case .Input: return module_input(state, input_bytes)
	case .Select: return module_select(state, input_bytes)
	case .Inspect: return module_publish(state)
	case .Deactivate: return module_deactivate(state, true)
	case .Step:
		if !state.active do return .Unavailable
		if output_capacity > 0 {
			if output == nil do return .Invalid_Argument
			output^ = 0
			output_length^ = 1
		}
		return .Ok
	case .Configure: return .Ok
	case .Invalid: return .Invalid_Argument
	}
	return .Invalid_Argument
}

@(private)
module_diagnostic :: proc(state: ^Module_Instance, message: string) {
	if state == nil || state.host_call == nil do return
	state.status_length = u16(copy(state.status[:], message))
	bytes := transmute([]u8)message
	_ = state.host_call(
		state.capability,
		.Diagnostic,
		raw_data(bytes),
		u64(len(bytes)),
		nil,
		0,
		nil,
	)
}

@(private)
module_session_request :: proc(
	state: ^Module_Instance,
	action: product_module.Session_Action,
	target: u64,
	payload: string,
	flags: u64 = 0,
) -> (product_module.Session_Response, bool) {
	if state == nil || state.host_call == nil || action == .Invalid do return {}, false
	header := product_module.Session_Request_Header {
		schema_version = product_module.SESSION_REQUEST_SCHEMA_VERSION,
		action = action,
		target = target,
		flags = flags,
		payload_length = u64(len(payload)),
	}
	request, allocation_error := make(
		[]u8,
		size_of(header) + len(payload),
		state.temporary_allocator,
	)
	if allocation_error != nil do return {}, false
	defer delete(request, state.temporary_allocator)
	copy(request[:size_of(header)], ([^]u8)(rawptr(&header))[:size_of(header)])
	copy(request[size_of(header):], transmute([]u8)payload)
	response: product_module.Session_Response
	response_bytes := ([^]u8)(rawptr(&response))[:size_of(response)]
	written: u64
	status := state.host_call(
		state.capability,
		.Session,
		raw_data(request),
		u64(len(request)),
		raw_data(response_bytes),
		u64(len(response_bytes)),
		&written,
	)
	return response, status == .Ok && written == u64(size_of(response))
}

@(private)
module_command_request :: proc(state: ^Module_Instance, name: string) -> bool {
	if state == nil || state.host_call == nil || len(name) == 0 do return false
	header := product_module.Command_Request_Header {
		schema_version = product_module.COMMAND_REQUEST_SCHEMA_VERSION,
		action = .Invoke,
		payload_length = u64(len(name)),
	}
	request, allocation_error := make(
		[]u8,
		size_of(header) + len(name),
		state.temporary_allocator,
	)
	if allocation_error != nil do return false
	defer delete(request, state.temporary_allocator)
	copy(request[:size_of(header)], ([^]u8)(rawptr(&header))[:size_of(header)])
	copy(request[size_of(header):], transmute([]u8)name)
	return state.host_call(
		state.capability,
		.Command,
		raw_data(request),
		u64(len(request)),
		nil,
		0,
		nil,
	) == .Ok
}

@(private)
module_release_editing :: proc(state: ^Module_Instance) {
	if state == nil do return
	if state.pending.state != nil do _, _ = maksym.rename_plan_close(&state.pending)
	if state.editable.state != nil do _, _ = maksym.editable_listing_close(&state.editable)
	for name in state.edited_names do if len(name) > 0 do delete(name, state.allocator)
	if state.edited_names != nil do delete(state.edited_names, state.allocator)
	if len(state.jump_filter) > 0 do delete(state.jump_filter, state.allocator)
	state.edited_names = nil
	state.jump_filter = ""
	state.mode = .Browse
}

@(private)
module_release_directory :: proc(state: ^Module_Instance) {
	if state == nil do return
	module_prompt_state(state, false)
	state.input_text = {}
	state.input_length = 0
	if len(state.listing_filter) > 0 do delete(state.listing_filter, state.allocator)
	if len(state.pattern_text) > 0 do delete(state.pattern_text, state.allocator)
	if len(state.replacement_text) > 0 do delete(state.replacement_text, state.allocator)
	state.listing_filter = ""
	state.pattern_text = ""
	state.replacement_text = ""
	module_release_editing(state)
	if state.item_references != nil do delete(state.item_references, state.allocator)
	state.item_references = nil
	state.next_item_id = 2
	if state.projection.state != nil do _, _ = maksym.projection_close(&state.projection)
	if state.targets.state != nil do _, _ = maksym.target_set_close(&state.targets)
	if state.buffer.state != nil do _, _ = maksym.directory_buffer_close(&state.buffer)
	state.active = false
}

@(private)
module_item_id_allocate :: proc(state: ^Module_Instance) -> (u64, bool) {
	if state == nil || state.next_item_id < 2 || state.next_item_id >= MAKSYM_MODULE_STATUS_ID {
		return 0, false
	}
	id := state.next_item_id
	state.next_item_id += 1
	return id, true
}

@(private)
module_item_reference_id :: proc(
	references: []Maksym_Item_Reference,
	identity: filesystem.Resource_ID,
) -> (u64, bool) {
	for reference in references {
		if reference.identity == identity do return reference.id, true
	}
	return 0, false
}

@(private)
module_item_reference_identity :: proc(
	references: []Maksym_Item_Reference,
	id: u64,
) -> (filesystem.Resource_ID, bool) {
	for reference in references {
		if reference.id == id do return reference.identity, true
	}
	return {}, false
}

@(private)
module_sync_item_references :: proc(
	state: ^Module_Instance,
	entries: []filesystem.Entry_Descriptor,
) -> bool {
	if state == nil do return false
	references, allocation_error := make(
		[]Maksym_Item_Reference,
		len(entries),
		state.allocator,
	)
	if allocation_error != nil do return false
	for entry, index in entries {
		id, retained := module_item_reference_id(state.item_references, entry.identity)
		if !retained {
			allocated: bool
			id, allocated = module_item_id_allocate(state)
			if !allocated {
				delete(references, state.allocator)
				return false
			}
		}
		references[index] = {id = id, identity = entry.identity}
	}
	if state.item_references != nil do delete(state.item_references, state.allocator)
	state.item_references = references
	return true
}

@(private)
module_open_directory :: proc(state: ^Module_Instance, path: string) -> bool {
	if state == nil || len(path) == 0 do return false
	owned_path, path_error := strings.clone(path, state.temporary_allocator)
	if path_error != nil do return false
	defer delete(owned_path, state.temporary_allocator)
	module_release_directory(state)
	retain_directory := false
	defer if !retain_directory do module_release_directory(state)
	batch, observed, _ := filesystem.directory_observe(
		owned_path,
		state.next_generation,
		{persistent = state.allocator, temporary = state.temporary_allocator},
	)
	if !observed do return false
	state.next_generation += 1
	if state.next_generation == 0 do state.next_generation = 1
	defer if batch.state != nil do _, _ = filesystem.directory_batch_close(&batch)
	opened, _ := maksym.directory_buffer_open(&state.buffer, &batch, state.allocator)
	if !opened do return false
	view, viewed, _ := maksym.directory_buffer_view(&state.buffer)
	if !viewed do return false
	targets_opened, _ := maksym.target_set_open(
		&state.targets,
		{
			id = MAKSYM_TARGET_SET_ID,
			directory_identity = view.directory_identity,
			listing_generation = view.generation,
			member_limit = maksym.MAX_TARGET_SET_MEMBERS,
			allocator = state.allocator,
		},
	)
	if !targets_opened do return false
	built, _ := maksym.projection_build(
		&state.projection,
		view,
		maksym.default_projection_config(state.allocator),
	)
	if !built || !module_sync_item_references(state, view.entries) do return false
	state.active = true
	retain_directory = true
	return true
}

@(private)
module_rebuild_projection :: proc(state: ^Module_Instance) -> bool {
	if state == nil || state.buffer.state == nil do return false
	if state.projection.state != nil do _, _ = maksym.projection_close(&state.projection)
	view, viewed, _ := maksym.directory_buffer_view(&state.buffer)
	if !viewed do return false
	filtered_entries: []filesystem.Entry_Descriptor
	if len(state.listing_filter) > 0 {
		match_count := 0
		for entry in view.entries do if strings.contains(entry.name, state.listing_filter) do match_count += 1
		allocation_error: runtime.Allocator_Error
		filtered_entries, allocation_error = make(
			[]filesystem.Entry_Descriptor,
			match_count,
			state.temporary_allocator,
		)
		if allocation_error != nil do return false
		defer delete(filtered_entries, state.temporary_allocator)
		match_index := 0
		selected_index := -1
		for entry in view.entries {
			if !strings.contains(entry.name, state.listing_filter) do continue
			filtered_entries[match_index] = entry
			if entry.identity == view.selected_identity do selected_index = match_index
			match_index += 1
		}
		if selected_index < 0 && len(filtered_entries) > 0 {
			_, _ = maksym.directory_buffer_select(&state.buffer, filtered_entries[0].identity)
			view.selected_identity = filtered_entries[0].identity
			view.has_selection = true
			selected_index = 0
		}
		view.entries = filtered_entries
		view.selected_index = selected_index
		if len(filtered_entries) == 0 {
			view.has_selection = false
			view.selected_identity = {}
		}
	}
	built, _ := maksym.projection_build(
		&state.projection,
		view,
		maksym.default_projection_config(state.allocator),
	)
	return built && module_sync_item_references(state, view.entries)
}

@(private)
module_activate :: proc(state: ^Module_Instance, path: string) -> product_module.Status {
	if state == nil || len(path) == 0 do return .Invalid_Argument
	if !module_open_directory(state, path) {
		module_diagnostic(state, "Directory is unavailable")
		return .Unavailable
	}
	response, presented := module_session_request(state, .Present_Surface, 0, "file-management.directory")
	if !presented {
		module_release_directory(state)
		return .Unavailable
	}
	state.previous_target = response.target
	module_diagnostic(state, "Opened directory")
	return module_publish(state)
}

@(private)
module_projection_text :: proc(
	state: ^Module_Instance,
	projection: maksym.Projection_View,
	targets: maksym.Target_Set_View,
	row_index: int,
) -> string {
	row := projection.rows[row_index]
	marked := false
	for target in targets.members {
		if target.identity == row.identity {
			marked = true
			break
		}
	}
	mark := "* " if marked else "  "
	if state.mode != .Edit || row_index >= len(state.edited_names) {
		end := int(row.row_end)
		if end > int(row.row_start) && projection.text[end - 1] == '\n' do end -= 1
		return fmt.tprintf("%s%s", mark, projection.text[int(row.row_start):end])
	}
	prefix := projection.text[int(row.row_start):int(row.name_start)]
	suffix := "/" if row.kind == .Directory else ""
	return fmt.tprintf("%s%s%s%s", mark, prefix, state.edited_names[row_index], suffix)
}

@(private)
module_publish :: proc(state: ^Module_Instance) -> product_module.Status {
	if state == nil || !state.active do return .Unavailable
	view, viewed, _ := maksym.directory_buffer_view(&state.buffer)
	projection, projected, _ := maksym.projection_view(&state.projection)
	if !viewed || !projected do return .Failed
	target_snapshot: maksym.Target_Set_Snapshot
	targets_inspected, _ := maksym.target_set_inspect(&state.targets, &target_snapshot)
	if !targets_inspected do return .Failed
	defer maksym.target_set_snapshot_close(&target_snapshot)
	targets, targets_viewed, _ := maksym.target_set_snapshot_view(&target_snapshot)
	if !targets_viewed || projection.directory_identity != view.directory_identity ||
	   projection.generation != view.generation || targets.directory_identity != view.directory_identity ||
	   targets.listing_generation != view.generation {
		return .Failed
	}
	for target in targets.members {
		found := false
		for entry in view.entries {
			if entry.identity == target.identity {
				found = true
				break
			}
		}
		if !found do return .Failed
	}
	empty_row := len(projection.rows) == 0
	current_item: i32 = 1 if empty_row else -1
	if !empty_row && view.has_selection {
		for row, index in projection.rows {
			if row.identity == view.selected_identity {
				current_item = i32(index + 1)
				break
			}
		}
	}
	row_count := len(projection.rows) + 1
	if empty_row do row_count += 1
	if state.status_length > 0 do row_count += 1
	header_bytes := size_of(product_module.UI_List_Header)
	rows_bytes := row_count * size_of(product_module.UI_List_Row)
	header_text := fmt.tprintf("%s:", view.directory)
	text_bytes := len(header_text)
	for _, index in projection.rows {
		text_bytes += len(module_projection_text(state, projection, targets, index))
	}
	if empty_row do text_bytes += len("Directory is empty")
	if state.status_length > 0 do text_bytes += int(state.status_length)
	if u64(header_bytes + rows_bytes + text_bytes) > product_module.MAX_CALL_BYTES do return .Limit
	request, allocation_error := make(
		[]u8,
		header_bytes + rows_bytes + text_bytes,
		state.temporary_allocator,
	)
	if allocation_error != nil do return .Failed
	defer delete(request, state.temporary_allocator)
	state.presentation_generation += 1
	if state.presentation_generation == 0 do state.presentation_generation = 1
	header := product_module.UI_List_Header {
		schema_version = product_module.UI_LIST_SCHEMA_VERSION,
		row_count = u32(row_count),
		presentation_generation = state.presentation_generation,
		current_item = current_item,
		first_visible_item = 0,
		viewport_items = u32(row_count),
		selection_owner = u8(ui.Selection_Owner.Model),
		text_bytes = u64(text_bytes),
	}
	copy(request[:header_bytes], ([^]u8)(rawptr(&header))[:header_bytes])
	text_offset := 0
	for row_index in 0 ..< row_count {
		row: product_module.UI_List_Row
		status_row := state.status_length > 0 && row_index == row_count - 1
		placeholder_row := empty_row && row_index == 1
		row.id = MAKSYM_MODULE_STATUS_ID if status_row else MAKSYM_MODULE_HEADER_ID if row_index == 0 else
		         u64(row_index + 1) if placeholder_row else state.item_references[row_index - 1].id
		row.text_offset = u64(text_offset)
		row.icon_role = u8(ui.List_Icon_Role.Textual)
		row.icon_style_role = u8(ui.Style_Role.Filesystem_Directory) if row_index == 0 else u8(ui.Style_Role.List_Normal)
		row.passive = 1 if row_index == 0 || status_row || placeholder_row else 0
		if row_index > 0 && !status_row && !placeholder_row {
			row.action_owner_id = 0x4F44_5241_4D41_4B53
			row.action_id = row.id
			row.action_generation = state.presentation_generation
		}
		text := string(state.status[:state.status_length]) if status_row else
		        header_text if row_index == 0 else
		        "Directory is empty" if placeholder_row else
		        module_projection_text(state, projection, targets, row_index - 1)
		row.text_length = u32(len(text))
		if row_index > 0 && !status_row && !placeholder_row {
			projection_row := projection.rows[row_index - 1]
			if projection_row.kind == .Directory {
				row.emphasis_style = u8(ui.Style_Role.Filesystem_Directory)
				row.emphasis_bytes = u32(len(text))
			}
		}
		row_start := header_bytes + row_index * size_of(product_module.UI_List_Row)
		copy(request[row_start:row_start + size_of(row)], ([^]u8)(rawptr(&row))[:size_of(row)])
		content_start := header_bytes + rows_bytes + text_offset
		copy(request[content_start:], transmute([]u8)text)
		text_offset += len(text)
	}
	status := state.host_call(
		state.capability,
		.UI,
		raw_data(request),
		u64(len(request)),
		nil,
		0,
		nil,
	)
	return status
}

@(private)
module_command_name :: proc(request: []u8) -> string {
	if len(request) >= size_of(product_module.Invocation_Request_Header) {
		header := (^product_module.Invocation_Request_Header)(raw_data(request))
		if header.schema_version == product_module.INVOCATION_REQUEST_SCHEMA_VERSION &&
		   int(header.name_length) == len(request) - size_of(product_module.Invocation_Request_Header) {
			return string(request[size_of(product_module.Invocation_Request_Header):])
		}
	}
	return string(request)
}

@(private)
module_invoke :: proc(state: ^Module_Instance, request: []u8) -> product_module.Status {
	if state == nil || !state.active || len(request) == 0 do return .Invalid_Argument
	name := module_command_name(request)
	switch name {
	case "maksym-next-entry", "maksym-editable-next-line", "component-next-row":
		_, _, _ = maksym.directory_buffer_move(&state.buffer, 1)
	case "maksym-previous-entry", "maksym-editable-previous-line", "component-previous-row":
		_, _, _ = maksym.directory_buffer_move(&state.buffer, -1)
	case "maksym-refresh", "result-refresh":
		if !module_refresh(state) do return .Failed
	case "maksym-toggle-details":
		_, toggled, _ := maksym.directory_buffer_toggle_details(&state.buffer)
		if !toggled || !module_rebuild_projection(state) do return .Failed
		module_diagnostic(state, "Maksym listing details toggled")
	case "maksym-cycle-sort":
		order, sorted, _ := maksym.directory_buffer_cycle_sort(&state.buffer)
		if !sorted || !module_rebuild_projection(state) do return .Failed
		module_diagnostic(state, "Maksym sorted by name" if order == .Name else "Maksym sorted with directories first")
	case "maksym-mark-entry":
		if !module_mark_selection(state, true) do return .Failed
	case "maksym-unmark-entry":
		if !module_mark_selection(state, false) do return .Failed
	case "maksym-invert-marks":
		if !module_invert_marks(state) do return .Failed
	case "maksym-unmark-all":
		if !module_clear_marks(state) do return .Failed
	case "maksym-next-marked-entry":
		if !module_move_marked(state, 1) do return .Failed
	case "maksym-previous-marked-entry":
		if !module_move_marked(state, -1) do return .Failed
	case "maksym-create-directory":
		if !module_begin_target_prompt(state, .Create_Directory) do return .Failed
	case "maksym-copy-targets":
		if !module_begin_target_prompt(state, .Copy_Targets) do return .Failed
	case "maksym-move-targets":
		if !module_begin_target_prompt(state, .Move_Targets) do return .Failed
	case "maksym-delete-targets":
		if !module_begin_target_prompt(state, .Delete_Targets) do return .Failed
	case "maksym-copy-names":
		if !module_copy_target_text(state, false) do return .Failed
	case "maksym-copy-absolute-paths":
		if !module_copy_target_text(state, true) do return .Failed
	case "maksym-describe-entry-type":
		if !module_describe_selection(state, false) do return .Failed
	case "maksym-describe-entry-metadata":
		if !module_describe_selection(state, true) do return .Failed
	case "maksym-shell-command":
		if !module_begin_shell_prompt(state, .Shell_Targets) do return .Failed
	case "maksym-shell-command-async":
		if !module_begin_shell_prompt(state, .Shell_Targets_Async) do return .Failed
	case "maksym-shell-command-current-directory":
		if !module_begin_shell_prompt(state, .Shell_Directory) do return .Failed
	case "maksym-filter-name":
		if !module_begin_text_prompt(state, .Filter_Name, "Filter Maksym names: ") do return .Failed
	case "maksym-clear-filter":
		if len(state.listing_filter) > 0 do delete(state.listing_filter, state.allocator)
		state.listing_filter = ""
		if !module_rebuild_projection(state) do return .Failed
		module_diagnostic(state, "Cleared Maksym name filter")
	case "maksym-rename-pattern":
		if !module_begin_text_prompt(state, .Pattern_Match, "Rename literal match: ") do return .Failed
	case "maksym-find-file-relative":
		if !module_begin_text_prompt(state, .Find_Relative, "Find relative to Maksym directory: ") do return .Failed
	case "maksym-jump-to-entry":
		if len(state.jump_filter) > 0 do delete(state.jump_filter, state.allocator)
		state.jump_filter = ""
		state.mode = .Jump
		module_diagnostic(state, "Jump to Maksym entry [local]")
	case "maksym-toggle-editable-listing":
		if state.mode == .Edit {
			module_release_editing(state)
			module_diagnostic(state, "Maksym filename editing cancelled")
		} else if !module_begin_editing(state) {
			return .Failed
		}
	case "maksym-apply-editable-listing":
		if !module_apply_editing(state) do return .Failed
	case "maksym-cancel-editable-listing":
		module_release_editing(state)
		module_diagnostic(state, "Maksym filename editing cancelled")
	case "maksym-parent-directory":
		view, viewed, _ := maksym.directory_buffer_view(&state.buffer)
		if !viewed || !module_open_directory(state, filepath.dir(view.directory)) do return .Failed
		module_diagnostic(state, "Opened parent directory")
	case "maksym-open-entry", "component-activate-current":
		if !module_open_selection(state, 0) {
			module_diagnostic(state, "Maksym entry could not be opened")
		}
	case "maksym-open-entry-other-pane":
		if !module_open_selection(
			state,
			product_module.SESSION_PRESENT_OTHER_PANE | product_module.SESSION_PRESENT_FOCUS,
		) {
			module_diagnostic(state, "Maksym entry could not be opened in another pane")
		}
	case "maksym-display-entry-other-pane":
		if !module_open_selection(state, product_module.SESSION_PRESENT_OTHER_PANE) {
			module_diagnostic(state, "Maksym entry could not be opened")
		}
	case "component-close":
		return module_deactivate(state, true)
	case:
		return .Unavailable
	}
	return module_publish(state)
}

@(private)
module_target_generation :: proc(state: ^Module_Instance) -> (maksym.Target_Set_Generation, bool) {
	if state == nil || state.targets.state == nil do return {}, false
	snapshot: maksym.Target_Set_Snapshot
	inspected, _ := maksym.target_set_inspect(&state.targets, &snapshot)
	if !inspected do return {}, false
	defer maksym.target_set_snapshot_close(&snapshot)
	view, viewed, _ := maksym.target_set_snapshot_view(&snapshot)
	return view.generation, viewed
}

@(private)
module_mark_selection :: proc(state: ^Module_Instance, mark: bool) -> bool {
	view, viewed, _ := maksym.directory_buffer_view(&state.buffer)
	generation, generation_ok := module_target_generation(state)
	if !viewed || !generation_ok || !view.has_selection do return false
	transition: maksym.Target_Set_Transition
	changed: bool
	if mark {
		transition, changed, _ = maksym.target_set_mark(
			&state.targets, generation, view.generation, view.selected_identity,
		)
	} else {
		transition, changed, _ = maksym.target_set_unmark(
			&state.targets, generation, view.generation, view.selected_identity,
		)
	}
	if !changed do return false
	module_diagnostic(state, "Maksym entry marked" if mark else "Maksym entry unmarked")
	_ = transition
	return true
}

@(private)
module_invert_marks :: proc(state: ^Module_Instance) -> bool {
	view, viewed, _ := maksym.directory_buffer_view(&state.buffer)
	generation, generation_ok := module_target_generation(state)
	if !viewed || !generation_ok do return false
	members, allocation_error := make(
		[]maksym.Target_Set_Member,
		len(view.entries),
		state.temporary_allocator,
	)
	if allocation_error != nil do return false
	defer delete(members, state.temporary_allocator)
	for entry, index in view.entries do members[index] = {identity = entry.identity}
	_, inverted, _ := maksym.target_set_invert(
		&state.targets, generation, view.generation, members,
	)
	if !inverted do return false
	module_diagnostic(state, "Maksym marks inverted")
	return true
}

@(private)
module_clear_marks :: proc(state: ^Module_Instance) -> bool {
	view, viewed, _ := maksym.directory_buffer_view(&state.buffer)
	generation, generation_ok := module_target_generation(state)
	if !viewed || !generation_ok do return false
	_, cleared, _ := maksym.target_set_clear(
		&state.targets, generation, view.generation,
	)
	if !cleared do return false
	module_diagnostic(state, "Maksym marks cleared")
	return true
}

@(private)
module_move_marked :: proc(state: ^Module_Instance, delta: i32) -> bool {
	generation, generation_ok := module_target_generation(state)
	if !generation_ok do return false
	movement, moved, _ := maksym.target_set_move_current(&state.targets, generation, delta)
	if !moved do return false
	if !filesystem.resource_id_valid(movement.identity) {
		module_diagnostic(state, "No marked Maksym entries")
		return true
	}
	selected, _ := maksym.directory_buffer_select(&state.buffer, movement.identity)
	if !selected do return false
	module_diagnostic(state, "Selected marked Maksym entry")
	return true
}

@(private)
module_prompt_state :: proc(state: ^Module_Instance, active: bool) {
	if state == nil || state.host_call == nil do return
	value := [1]u8{1 if active else 0}
	_ = state.host_call(state.capability, .Prompt, raw_data(value[:]), 1, nil, 0, nil)
}

@(private)
module_end_target_prompt :: proc(state: ^Module_Instance) {
	if state == nil do return
	state.mode = .Browse
	state.input_length = 0
	state.input_text = {}
	module_prompt_state(state, false)
}

@(private)
module_target_entries :: proc(
	state: ^Module_Instance,
) -> ([]filesystem.Entry_Descriptor, bool) {
	if state == nil do return nil, false
	directory, viewed, _ := maksym.directory_buffer_view(&state.buffer)
	if !viewed do return nil, false
	snapshot: maksym.Target_Set_Snapshot
	inspected, _ := maksym.target_set_inspect(&state.targets, &snapshot)
	if !inspected do return nil, false
	defer maksym.target_set_snapshot_close(&snapshot)
	targets, targets_viewed, _ := maksym.target_set_snapshot_view(&snapshot)
	if !targets_viewed || targets.directory_identity != directory.directory_identity ||
	   targets.listing_generation != directory.generation {
		return nil, false
	}
	count := len(targets.members)
	if count == 0 && directory.has_selection do count = 1
	if count == 0 do return nil, false
	entries, allocation_error := make(
		[]filesystem.Entry_Descriptor,
		count,
		state.temporary_allocator,
	)
	if allocation_error != nil do return nil, false
	if len(targets.members) == 0 {
		entries[0] = directory.entries[directory.selected_index]
		return entries, true
	}
	for target, target_index in targets.members {
		found := false
		for entry in directory.entries {
			if entry.identity == target.identity {
				entries[target_index] = entry
				found = true
				break
			}
		}
		if !found {
			delete(entries, state.temporary_allocator)
			return nil, false
		}
	}
	return entries, true
}

@(private)
module_begin_target_prompt :: proc(state: ^Module_Instance, mode: Input_Mode) -> bool {
	if state == nil || state.mode != .Browse ||
	   (mode != .Create_Directory && mode != .Copy_Targets && mode != .Move_Targets &&
	    mode != .Delete_Targets) {
		return false
	}
	if mode != .Create_Directory {
		targets, resolved := module_target_entries(state)
		if !resolved do return false
		defer delete(targets, state.temporary_allocator)
	}
	state.mode = mode
	state.input_text = {}
	state.input_length = 0
	module_prompt_state(state, true)
	message := "Directory name: "
	if mode == .Copy_Targets do message = "Copy targets to directory: "
	if mode == .Move_Targets do message = "Move targets to directory or rename one target: "
	if mode == .Delete_Targets {
		targets, _ := module_target_entries(state)
		defer delete(targets, state.temporary_allocator)
		message = fmt.tprintf(
			"Permanently delete %d Maksym target(s)? Recovery is unavailable. [y/N]",
			len(targets),
		)
	}
	module_diagnostic(state, message)
	return true
}

@(private)
module_append_prompt_text :: proc(state: ^Module_Instance, text: string) -> bool {
	if state == nil || len(text) == 0 || state.input_length + len(text) > len(state.input_text) {
		return false
	}
	state.input_length += copy(state.input_text[state.input_length:], text)
	return true
}

@(private)
module_delete_prompt_text :: proc(state: ^Module_Instance) {
	if state != nil && state.input_length > 0 do state.input_length -= 1
}

@(private)
module_apply_create_directory :: proc(state: ^Module_Instance) -> bool {
	directory, viewed, _ := maksym.directory_buffer_view(&state.buffer)
	if !viewed || state.input_length == 0 do return false
	_, created, _ := filesystem.directory_child_create(
		directory.directory,
		{
			parent_identity = directory.directory_identity,
			name = string(state.input_text[:state.input_length]),
			kind = .Directory,
		},
		{persistent = state.allocator, temporary = state.temporary_allocator},
	)
	module_end_target_prompt(state)
	if !created {
		module_diagnostic(state, "Maksym directory creation was rejected")
		return true
	}
	if !module_refresh(state) do return false
	module_diagnostic(state, "Created Maksym directory")
	return true
}

@(private)
module_apply_transfer :: proc(state: ^Module_Instance, move: bool) -> bool {
	directory, viewed, _ := maksym.directory_buffer_view(&state.buffer)
	targets, resolved := module_target_entries(state)
	if !viewed || !resolved || state.input_length == 0 do return false
	defer delete(targets, state.temporary_allocator)
	destination_text := string(state.input_text[:state.input_length])
	destination, destination_observed, _ := filesystem.directory_observe(
		destination_text,
		1,
		{persistent = state.temporary_allocator, temporary = state.temporary_allocator},
		true,
	)
	rename_one := move && !destination_observed && len(targets) == 1
	if rename_one {
		destination_text = directory.directory
	} else if !destination_observed {
		module_end_target_prompt(state)
		module_diagnostic(state, "Maksym destination directory is unavailable")
		return true
	}
	defer if destination.state != nil do filesystem.directory_batch_close(&destination)
	destination_identity := directory.directory_identity if rename_one else destination.directory_identity
	applied := 0
	failure_code := filesystem.Failure_Code.None
	for target in targets {
		destination_name := string(state.input_text[:state.input_length]) if rename_one else target.name
		ok := false
		if move {
			failure: filesystem.Failure_Context
			_, ok, failure = filesystem.directory_entry_move(
				directory.directory,
				destination_text,
				{
					source_parent_identity = directory.directory_identity,
					source_identity = target.identity,
					source_name = target.name,
					source_kind = target.kind,
					destination_parent_identity = destination_identity,
					destination_name = destination_name,
				},
				{persistent = state.allocator, temporary = state.temporary_allocator},
			)
			failure_code = failure.code
		} else {
			failure: filesystem.Failure_Context
			_, ok, failure = filesystem.directory_entry_copy(
				directory.directory,
				destination_text,
				{
					source_parent_identity = directory.directory_identity,
					source_identity = target.identity,
					source_name = target.name,
					source_kind = target.kind,
					destination_parent_identity = destination_identity,
					destination_name = destination_name,
					limits = filesystem.DEFAULT_COPY_LIMITS,
				},
				{persistent = state.allocator, temporary = state.temporary_allocator},
			)
			failure_code = failure.code
		}
		if !ok do break
		applied += 1
	}
	module_end_target_prompt(state)
	if move && applied > 0 && !module_refresh(state) do return false
	module_diagnostic(
		state,
		fmt.tprintf(
			"%s %d of %d Maksym target(s); failure=%v",
			"Moved" if move else "Copied",
			applied,
			len(targets),
			failure_code,
		),
	)
	return true
}

@(private)
module_apply_delete_targets :: proc(state: ^Module_Instance) -> bool {
	directory, viewed, _ := maksym.directory_buffer_view(&state.buffer)
	targets, resolved := module_target_entries(state)
	if !viewed || !resolved do return false
	defer delete(targets, state.temporary_allocator)
	requests, request_error := make([]filesystem.Delete_Request, len(targets), state.temporary_allocator)
	if request_error != nil do return false
	defer delete(requests, state.temporary_allocator)
	results, result_error := make([]filesystem.Delete_Result, len(targets), state.temporary_allocator)
	if result_error != nil do return false
	defer delete(results, state.temporary_allocator)
	for target, index in targets {
		requests[index] = {identity = target.identity, name = target.name, kind = target.kind}
	}
	_, _ = filesystem.directory_delete_batch_apply(
		directory.directory,
		directory.directory_identity,
		requests,
		results,
		{persistent = state.allocator, temporary = state.temporary_allocator},
	)
	applied := 0
	for result in results do if result.outcome == .Applied do applied += 1
	module_end_target_prompt(state)
	if applied > 0 && !module_refresh(state) do return false
	module_diagnostic(
		state,
		fmt.tprintf("Permanently deleted %d of %d Maksym target(s)", applied, len(targets)),
	)
	return true
}

@(private)
module_retain_text :: proc(state: ^Module_Instance, value: string) -> bool {
	if state == nil || state.host_call == nil || len(value) == 0 do return false
	bytes := transmute([]u8)value
	return state.host_call(
		state.capability, .Clipboard, raw_data(bytes), u64(len(bytes)), nil, 0, nil,
	) == .Ok
}

@(private)
module_copy_target_text :: proc(state: ^Module_Instance, absolute: bool) -> bool {
	targets, resolved := module_target_entries(state)
	if !resolved do return false
	defer delete(targets, state.temporary_allocator)
	total := 0
	for target, index in targets {
		value := target.path if absolute else target.name
		total += len(value)
		if index > 0 do total += 1
	}
	text, allocation_error := make([]u8, total, state.temporary_allocator)
	if allocation_error != nil do return false
	defer delete(text, state.temporary_allocator)
	offset := 0
	for target, index in targets {
		if index > 0 {
			text[offset] = '\n'
			offset += 1
		}
		value := target.path if absolute else target.name
		offset += copy(text[offset:], value)
	}
	if !module_retain_text(state, string(text)) do return false
	module_diagnostic(
		state,
		"Copied Maksym target paths" if absolute else "Copied Maksym target names",
	)
	return true
}

@(private)
module_describe_selection :: proc(state: ^Module_Instance, metadata: bool) -> bool {
	directory, viewed, _ := maksym.directory_buffer_view(&state.buffer)
	if !viewed || !directory.has_selection do return false
	entry := directory.entries[directory.selected_index]
	kind := "directory" if entry.kind == .Directory else "regular file"
	if metadata {
		module_diagnostic(
			state,
			fmt.tprintf(
				"Maksym %s: size=%d permissions=%03o modified=%d",
				kind,
				entry.size_bytes,
				entry.permissions,
				entry.modified_seconds,
			),
		)
	} else {
		module_diagnostic(state, fmt.tprintf("Maksym entry type: %s", kind))
	}
	return true
}

@(private)
module_begin_shell_prompt :: proc(state: ^Module_Instance, mode: Input_Mode) -> bool {
	if state == nil || state.mode != .Browse ||
	   (mode != .Shell_Targets && mode != .Shell_Targets_Async && mode != .Shell_Directory) {
		return false
	}
	target_count := 0
	if mode != .Shell_Directory {
		targets, resolved := module_target_entries(state)
		if !resolved do return false
		target_count = len(targets)
		delete(targets, state.temporary_allocator)
	}
	state.mode = mode
	state.input_text = {}
	state.input_length = 0
	module_prompt_state(state, true)
	message := "Shell command in current Maksym directory: "
	if mode != .Shell_Directory {
		message = fmt.tprintf("Shell command for %d checked Maksym target(s): ", target_count)
	}
	module_diagnostic(state, message)
	return true
}

@(private)
module_shell_append :: proc(output: []u8, length: ^int, value: string) -> bool {
	if length == nil || length^ + len(value) > len(output) do return false
	length^ += copy(output[length^:], value)
	return true
}

@(private)
module_shell_append_quoted :: proc(output: []u8, length: ^int, value: string) -> bool {
	if !module_shell_append(output, length, " '") do return false
	for byte in transmute([]u8)value {
		if byte == '\'' {
			if !module_shell_append(output, length, "'\\''") do return false
		} else {
			if length^ >= len(output) do return false
			output[length^] = byte
			length^ += 1
		}
	}
	return module_shell_append(output, length, "'")
}

@(private)
module_host_process :: proc(
	state: ^Module_Instance,
	directory, command_text: string,
	async: bool,
) -> bool {
	header := product_module.Process_Request_Header {
		schema_version = product_module.PROCESS_REQUEST_SCHEMA_VERSION,
		action = .Async_Shell if async else .Shell,
		working_directory_length = u32(len(directory)),
		command_length = u32(len(command_text)),
	}
	request, allocation_error := make(
		[]u8,
		size_of(header) + len(directory) + len(command_text),
		state.temporary_allocator,
	)
	if allocation_error != nil do return false
	defer delete(request, state.temporary_allocator)
	copy(request[:size_of(header)], ([^]u8)(rawptr(&header))[:size_of(header)])
	copy(request[size_of(header):], directory)
	copy(request[size_of(header) + len(directory):], command_text)
	return state.host_call(
		state.capability, .Process, raw_data(request), u64(len(request)), nil, 0, nil,
	) == .Ok
}

@(private)
module_apply_shell_prompt :: proc(state: ^Module_Instance) -> bool {
	directory, viewed, _ := maksym.directory_buffer_view(&state.buffer)
	if !viewed || state.input_length == 0 do return false
	command_storage: [MAKSYM_SHELL_COMMAND_BYTES]u8
	command_length := 0
	if !module_shell_append(
		command_storage[:],
		&command_length,
		string(state.input_text[:state.input_length]),
	) {
		return false
	}
	if state.mode != .Shell_Directory {
		targets, resolved := module_target_entries(state)
		if !resolved do return false
		defer delete(targets, state.temporary_allocator)
		for target in targets {
			if !module_shell_append_quoted(command_storage[:], &command_length, target.path) {
				return false
			}
		}
	}
	async := state.mode == .Shell_Targets_Async
	ok := module_host_process(
		state,
		directory.directory,
		string(command_storage[:command_length]),
		async,
	)
	module_end_target_prompt(state)
	if !ok do module_diagnostic(state, "Maksym shell command was rejected")
	return true
}

@(private)
module_begin_text_prompt :: proc(
	state: ^Module_Instance,
	mode: Input_Mode,
	message: string,
) -> bool {
	if state == nil || state.mode != .Browse ||
	   (mode != .Filter_Name && mode != .Pattern_Match && mode != .Find_Relative) {
		return false
	}
	if mode == .Pattern_Match {
		targets, resolved := module_target_entries(state)
		if !resolved do return false
		delete(targets, state.temporary_allocator)
	}
	state.mode = mode
	state.input_text = {}
	state.input_length = 0
	module_prompt_state(state, true)
	module_diagnostic(state, message)
	return true
}

@(private)
module_apply_find_relative :: proc(state: ^Module_Instance) -> bool {
	directory, viewed, _ := maksym.directory_buffer_view(&state.buffer)
	if !viewed || state.input_length == 0 do return false
	path, path_error := os.join_path(
		{directory.directory, string(state.input_text[:state.input_length])},
		state.temporary_allocator,
	)
	if path_error != nil do return false
	defer delete(path, state.temporary_allocator)
	module_end_target_prompt(state)
	if os.is_dir(path) {
		if !module_open_directory(state, path) do return false
		module_diagnostic(state, "Opened relative Maksym directory")
		return true
	}
	response, opened := module_session_request(state, .Open_Path, 0, path)
	if !opened {
		module_diagnostic(state, "Relative Maksym path is unavailable")
		return true
	}
	_, presented := module_session_request(state, .Present_Entry, response.target, "")
	if presented do module_diagnostic(state, "Opened relative Maksym file")
	return presented
}

@(private)
module_retain_owned_text :: proc(
	state: ^Module_Instance,
	target: ^string,
	value: string,
) -> bool {
	if state == nil || target == nil do return false
	copy_value, copy_error := strings.clone(value, state.allocator)
	if copy_error != nil do return false
	if len(target^) > 0 do delete(target^, state.allocator)
	target^ = copy_value
	return true
}

@(private)
module_prepare_pattern_replacement :: proc(state: ^Module_Instance) -> bool {
	if state == nil || state.mode != .Pattern_Match || state.input_length == 0 do return false
	if !module_retain_owned_text(
		state,
		&state.pattern_text,
		string(state.input_text[:state.input_length]),
	) {
		return false
	}
	state.mode = .Pattern_Replacement
	state.input_text = {}
	state.input_length = 0
	module_diagnostic(state, "Rename literal replacement: ")
	return true
}

@(private)
module_prepare_pattern_confirmation :: proc(state: ^Module_Instance) -> bool {
	if state == nil || state.mode != .Pattern_Replacement do return false
	if !module_retain_owned_text(
		state,
		&state.replacement_text,
		string(state.input_text[:state.input_length]),
	) {
		return false
	}
	targets, resolved := module_target_entries(state)
	if !resolved do return false
	defer delete(targets, state.temporary_allocator)
	changes := 0
	for target in targets do if strings.contains(target.name, state.pattern_text) do changes += 1
	state.mode = .Pattern_Confirm
	state.input_text = {}
	state.input_length = 0
	module_diagnostic(
		state,
		fmt.tprintf("Apply checked literal rename to %d Maksym target(s)? [y/N]", changes),
	)
	return true
}

@(private)
module_apply_pattern_rename :: proc(state: ^Module_Instance) -> bool {
	if state == nil || state.mode != .Pattern_Confirm || len(state.pattern_text) == 0 {
		return false
	}
	directory, viewed, _ := maksym.directory_buffer_view(&state.buffer)
	targets, resolved := module_target_entries(state)
	if !viewed || !resolved do return false
	defer delete(targets, state.temporary_allocator)
	change_count := 0
	for target in targets do if strings.contains(target.name, state.pattern_text) do change_count += 1
	if change_count == 0 {
		module_end_target_prompt(state)
		module_diagnostic(state, "No Maksym target names matched")
		return true
	}
	requests, request_error := make([]filesystem.Move_Request, change_count, state.temporary_allocator)
	if request_error != nil do return false
	defer delete(requests, state.temporary_allocator)
	results, result_error := make([]filesystem.Rename_Result, change_count, state.temporary_allocator)
	if result_error != nil do return false
	defer delete(results, state.temporary_allocator)
	owned_names, names_error := make([]string, change_count, state.temporary_allocator)
	if names_error != nil do return false
	defer {
		for name in owned_names do if len(name) > 0 do delete(name, state.temporary_allocator)
		delete(owned_names, state.temporary_allocator)
	}
	request_index := 0
	for target in targets {
		if !strings.contains(target.name, state.pattern_text) do continue
		replaced, allocated := strings.replace_all(
			target.name,
			state.pattern_text,
			state.replacement_text,
			state.temporary_allocator,
		)
		if !allocated || replaced == target.name {
			module_end_target_prompt(state)
			module_diagnostic(state, "Maksym pattern rename produced an invalid unchanged target")
			return true
		}
		owned_names[request_index] = replaced
		requests[request_index] = {
			identity = target.identity,
			from = target.name,
			to = replaced,
		}
		request_index += 1
	}
	applied, _ := filesystem.directory_move_batch_apply(
		directory.directory,
		directory.directory_identity,
		requests,
		results,
		{persistent = state.allocator, temporary = state.temporary_allocator},
	)
	module_end_target_prompt(state)
	if !applied {
		module_diagnostic(state, "Maksym pattern rename was rejected before publication")
		return true
	}
	if !module_refresh(state) do return false
	module_diagnostic(state, fmt.tprintf("Renamed %d Maksym target(s)", change_count))
	return true
}

@(private)
module_begin_editing :: proc(state: ^Module_Instance) -> bool {
	if state == nil || state.mode == .Edit do return false
	projection, projected, _ := maksym.projection_view(&state.projection)
	if !projected do return false
	opened, _ := maksym.editable_listing_open(&state.editable, projection, state.allocator)
	if !opened do return false
	state.edited_names, _ = make([]string, len(projection.rows), state.allocator)
	if state.edited_names == nil && len(projection.rows) > 0 {
		_, _ = maksym.editable_listing_close(&state.editable)
		return false
	}
	for row, index in projection.rows {
		name, clone_error := strings.clone(
			projection.text[int(row.name_start):int(row.name_end)],
			state.allocator,
		)
		if clone_error != nil {
			module_release_editing(state)
			return false
		}
		state.edited_names[index] = name
	}
	state.mode = .Edit
	module_diagnostic(state, "Maksym filename editing enabled")
	return true
}

@(private)
module_edited_text :: proc(state: ^Module_Instance) -> (string, bool) {
	if state == nil || state.mode != .Edit do return "", false
	projection, projected, _ := maksym.projection_view(&state.projection)
	if !projected || len(projection.rows) != len(state.edited_names) do return "", false
	total := int(projection.header_end)
	for row, index in projection.rows {
		total += int(row.name_start - row.row_start) + len(state.edited_names[index]) + 1
		if row.kind == .Directory do total += 1
	}
	storage, allocation_error := make([]u8, total, state.temporary_allocator)
	if allocation_error != nil do return "", false
	offset := copy(storage, transmute([]u8)projection.text[:projection.header_end])
	for row, index in projection.rows {
		offset += copy(storage[offset:], transmute([]u8)projection.text[row.row_start:row.name_start])
		offset += copy(storage[offset:], transmute([]u8)state.edited_names[index])
		if row.kind == .Directory {
			storage[offset] = '/'
			offset += 1
		}
		storage[offset] = '\n'
		offset += 1
	}
	return string(storage), true
}

@(private)
module_apply_editing :: proc(state: ^Module_Instance) -> bool {
	if state == nil || state.mode != .Edit || state.editable.state == nil {
		module_diagnostic(state, "Maksym filename editing is not active")
		return true
	}
	edited, built := module_edited_text(state)
	if !built do return false
	defer delete(edited, state.temporary_allocator)
	if state.pending.state != nil do _, _ = maksym.rename_plan_close(&state.pending)
	calculated, _ := maksym.editable_listing_calculate(&state.editable, edited, &state.pending)
	if !calculated {
		module_diagnostic(state, "Editable Maksym text is invalid")
		return true
	}
	plan, viewed, _ := maksym.rename_plan_view(&state.pending)
	if !viewed do return false
	if len(plan.changes) == 0 {
		module_diagnostic(state, "No Maksym filename changes to apply")
		return true
	}
	view, directory_viewed, _ := maksym.directory_buffer_view(&state.buffer)
	if !directory_viewed do return false
	renames, moves, deletions := 0, 0, 0
	for change in plan.changes {
		switch change.kind {
		case .Rename: renames += 1
		case .Move: moves += 1
		case .Delete:
			if change.entry_kind == .Directory {
				module_diagnostic(state, "Recursive directory deletion is unavailable")
				return true
			}
			deletions += 1
		case .Invalid:
		}
	}
	move_requests, move_error := make([]filesystem.Move_Request, renames + moves, state.temporary_allocator)
	if move_error != nil do return false
	defer delete(move_requests, state.temporary_allocator)
	move_results, result_error := make([]filesystem.Rename_Result, len(move_requests), state.temporary_allocator)
	if result_error != nil do return false
	defer delete(move_results, state.temporary_allocator)
	delete_requests, delete_error := make([]filesystem.Delete_Request, deletions, state.temporary_allocator)
	if delete_error != nil do return false
	defer delete(delete_requests, state.temporary_allocator)
	delete_results, delete_result_error := make([]filesystem.Delete_Result, deletions, state.temporary_allocator)
	if delete_result_error != nil do return false
	defer delete(delete_results, state.temporary_allocator)
	move_index, delete_index := 0, 0
	for change in plan.changes {
		if change.kind == .Delete {
			delete_requests[delete_index] = {identity = change.identity, name = change.from, kind = change.entry_kind}
			delete_index += 1
		} else {
			move_requests[move_index] = {identity = change.identity, from = change.from, to = change.to}
			move_index += 1
		}
	}
	allocators := filesystem.Allocator_Set {persistent = state.allocator, temporary = state.temporary_allocator}
	if len(delete_requests) > 0 {
		valid, _ := filesystem.directory_delete_batch_preflight(
			view.directory, plan.directory_identity, delete_requests, allocators,
		)
		if !valid {
			module_diagnostic(state, "Maksym deletion preflight rejected the change set")
			return true
		}
	}
	if len(move_requests) > 0 {
		applied, _ := filesystem.directory_move_batch_apply(
			view.directory, plan.directory_identity, move_requests, move_results, allocators,
		)
		if !applied {
			module_diagnostic(state, "Maksym rename or move preflight rejected the change set")
			return true
		}
	}
	if len(delete_requests) > 0 {
		deleted, _ := filesystem.directory_delete_batch_apply(
			view.directory, plan.directory_identity, delete_requests, delete_results, allocators,
		)
		if !deleted {
			module_diagnostic(state, "Maksym deletion batch was rejected")
			return true
		}
	}
	message_storage: [192]u8
	message := fmt.bprintf(
		message_storage[:],
		"Applied %d rename(s), %d move(s), and %d permanent deletion(s)",
		renames,
		moves,
		deletions,
	)
	module_release_editing(state)
	if !module_refresh(state) do return false
	module_diagnostic(state, message)
	return true
}

@(private)
module_refresh :: proc(state: ^Module_Instance) -> bool {
	if state == nil || state.buffer.state == nil do return false
	view, viewed, _ := maksym.directory_buffer_view(&state.buffer)
	if !viewed do return false
	batch, observed, _ := filesystem.directory_observe(
		view.directory,
		state.next_generation,
		{persistent = state.allocator, temporary = state.temporary_allocator},
	)
	if !observed do return false
	state.next_generation += 1
	if state.next_generation == 0 do state.next_generation = 1
	defer if batch.state != nil do _, _ = filesystem.directory_batch_close(&batch)
	module_release_editing(state)
	if batch.directory_identity != view.directory_identity || batch.generation <= view.generation {
		return false
	}
	target_snapshot: maksym.Target_Set_Snapshot
	inspected, _ := maksym.target_set_inspect(&state.targets, &target_snapshot)
	if !inspected do return false
	defer maksym.target_set_snapshot_close(&target_snapshot)
	target_view, target_viewed, _ := maksym.target_set_snapshot_view(&target_snapshot)
	if !target_viewed || target_view.directory_identity != view.directory_identity ||
	   target_view.listing_generation != view.generation {
		return false
	}
	visible, allocation_error := make(
		[]maksym.Target_Set_Member,
		len(batch.descriptors),
		state.temporary_allocator,
	)
	if allocation_error != nil do return false
	defer delete(visible, state.temporary_allocator)
	for entry, index in batch.descriptors do visible[index] = {identity = entry.identity}
	_, reconciled, _ := maksym.target_set_reconcile(
		&state.targets,
		target_view.generation,
		target_view.listing_generation,
		batch.directory_identity,
		batch.generation,
		visible,
	)
	if !reconciled do return false
	refreshed, _ := maksym.directory_buffer_refresh(&state.buffer, &batch)
	return refreshed && module_rebuild_projection(state)
}

@(private)
module_open_selection :: proc(state: ^Module_Instance, presentation_flags: u64) -> bool {
	view, viewed, _ := maksym.directory_buffer_view(&state.buffer)
	if !viewed do return false
	if len(view.entries) == 0 {
		module_diagnostic(state, "Directory is empty")
		return true
	}
	if !view.has_selection || view.selected_index < 0 || view.selected_index >= len(view.entries) {
		return false
	}
	selected := view.entries[view.selected_index]
	if selected.kind == .Directory {
		return module_open_directory(state, selected.path)
	}
	response, opened := module_session_request(state, .Open_Path, 0, selected.path)
	if !opened do return false
	_, presented := module_session_request(
		state,
		.Present_Entry,
		response.target,
		"",
		presentation_flags,
	)
	return presented
}

@(private)
module_append_filter :: proc(state: ^Module_Instance, text: string) -> bool {
	if state == nil || len(text) == 0 do return false
	joined := fmt.tprintf("%s%s", state.jump_filter, text)
	copied, copy_error := strings.clone(joined, state.allocator)
	if copy_error != nil do return false
	if len(state.jump_filter) > 0 do delete(state.jump_filter, state.allocator)
	state.jump_filter = copied
	return true
}

@(private)
module_append_edit :: proc(state: ^Module_Instance, text: string) -> bool {
	view, viewed, _ := maksym.directory_buffer_view(&state.buffer)
	if !viewed || !view.has_selection || view.selected_index < 0 ||
	   view.selected_index >= len(state.edited_names) {
		return false
	}
	index := view.selected_index
	joined := fmt.tprintf("%s%s", state.edited_names[index], text)
	copied, copy_error := strings.clone(joined, state.allocator)
	if copy_error != nil do return false
	if len(state.edited_names[index]) > 0 do delete(state.edited_names[index], state.allocator)
	state.edited_names[index] = copied
	return true
}

@(private)
module_delete_edit :: proc(state: ^Module_Instance) -> bool {
	view, viewed, _ := maksym.directory_buffer_view(&state.buffer)
	if !viewed || !view.has_selection || view.selected_index < 0 ||
	   view.selected_index >= len(state.edited_names) {
		return false
	}
	index := view.selected_index
	name := state.edited_names[index]
	if len(name) == 0 do return true
	copied, copy_error := strings.clone(name[1:], state.allocator)
	if copy_error != nil do return false
	delete(name, state.allocator)
	state.edited_names[index] = copied
	return true
}

@(private)
module_complete_jump :: proc(state: ^Module_Instance) {
	view, viewed, _ := maksym.directory_buffer_view(&state.buffer)
	if viewed {
		for entry in view.entries {
			if len(state.jump_filter) == 0 || strings.contains(entry.name, state.jump_filter) {
				_, _ = maksym.directory_buffer_select(&state.buffer, entry.identity)
				module_diagnostic(state, "Selected Maksym entry")
				break
			}
		}
	}
	if len(state.jump_filter) > 0 do delete(state.jump_filter, state.allocator)
	state.jump_filter = ""
	state.mode = .Browse
}

@(private)
module_input :: proc(state: ^Module_Instance, request: []u8) -> product_module.Status {
	if state == nil || !state.active || len(request) < size_of(product_module.Input_Request_Header) {
		return .Invalid_Argument
	}
	header := (^product_module.Input_Request_Header)(raw_data(request))
	if header.schema_version != product_module.INPUT_REQUEST_SCHEMA_VERSION ||
	   int(header.text_length) != len(request) - size_of(product_module.Input_Request_Header) {
		return .Invalid_Argument
	}
	text := string(request[size_of(product_module.Input_Request_Header):])
	target_prompt := state.mode == .Create_Directory || state.mode == .Copy_Targets ||
	                 state.mode == .Move_Targets || state.mode == .Delete_Targets ||
	                 state.mode == .Shell_Targets || state.mode == .Shell_Targets_Async ||
	                 state.mode == .Shell_Directory || state.mode == .Filter_Name ||
	                 state.mode == .Pattern_Match || state.mode == .Pattern_Replacement ||
	                 state.mode == .Pattern_Confirm || state.mode == .Find_Relative
	if target_prompt {
		if header.kind == .Text_Commit {
			if state.mode == .Delete_Targets || state.mode == .Pattern_Confirm ||
			   !module_append_prompt_text(state, text) {
				return .Failed
			}
			return module_publish(state)
		}
		if header.kind != .Key do return .Invalid_Argument
		if header.key_kind == .Escape ||
		   (header.key_kind == .Unicode_Scalar && header.modifiers == 1 && rune(header.scalar) == 'g') {
			module_end_target_prompt(state)
			module_diagnostic(state, "Maksym operation cancelled")
			return module_publish(state)
		}
		if state.mode == .Delete_Targets || state.mode == .Pattern_Confirm {
			if header.key_kind == .Unicode_Scalar && header.modifiers == 0 &&
			   (rune(header.scalar) == 'y' || rune(header.scalar) == 'Y') {
				if state.mode == .Delete_Targets {
					if !module_apply_delete_targets(state) do return .Failed
				} else if !module_apply_pattern_rename(state) do return .Failed
			} else if header.key_kind == .Enter ||
			          (header.key_kind == .Unicode_Scalar && header.modifiers == 0 &&
			           (rune(header.scalar) == 'n' || rune(header.scalar) == 'N')) {
				module_end_target_prompt(state)
				module_diagnostic(state, "Maksym operation cancelled")
			}
			return module_publish(state)
		}
		if header.key_kind == .Backspace {
			module_delete_prompt_text(state)
		} else if header.key_kind == .Enter {
			applied := false
			#partial switch state.mode {
			case .Create_Directory: applied = module_apply_create_directory(state)
			case .Copy_Targets: applied = module_apply_transfer(state, false)
			case .Move_Targets: applied = module_apply_transfer(state, true)
			case .Shell_Targets, .Shell_Targets_Async, .Shell_Directory:
				applied = module_apply_shell_prompt(state)
			case .Filter_Name:
				applied = module_retain_owned_text(
					state,
					&state.listing_filter,
					string(state.input_text[:state.input_length]),
				)
				if applied {
					module_end_target_prompt(state)
					applied = module_rebuild_projection(state)
					module_diagnostic(state, "Filtered Maksym names")
				}
			case .Pattern_Match: applied = module_prepare_pattern_replacement(state)
			case .Pattern_Replacement: applied = module_prepare_pattern_confirmation(state)
			case .Find_Relative: applied = module_apply_find_relative(state)
			case: return .Failed
			}
			if !applied do return .Failed
		} else if header.key_kind == .Unicode_Scalar && header.modifiers == 0 {
			if !module_append_prompt_text(state, fmt.tprintf("%c", rune(header.scalar))) do return .Failed
		}
		return module_publish(state)
	}
	if header.kind == .Key && header.key_kind == .Unicode_Scalar {
		control := header.modifiers == 1
		meta := header.modifiers == 2
		scalar := rune(header.scalar)
		if state.mode == .Browse && meta && scalar == '{' {
			return module_invoke(state, transmute([]u8)(string("maksym-previous-marked-entry")))
		}
		if state.mode == .Browse && meta && scalar == '}' {
			return module_invoke(state, transmute([]u8)(string("maksym-next-marked-entry")))
		}
		if state.mode == .Browse && meta && scalar == '!' {
			return module_invoke(
				state,
				transmute([]u8)(string("maksym-shell-command-current-directory")),
			)
		}
		if state.prefix != .None {
			prefix := state.prefix
			state.prefix = .None
			if prefix == .Control_X {
				if control && scalar == 'q' {
					return module_invoke(state, transmute([]u8)(string("maksym-toggle-editable-listing")))
				} else if control && scalar == 's' && state.mode == .Edit {
					return module_invoke(state, transmute([]u8)(string("maksym-apply-editable-listing")))
				} else if control && scalar == 'c' {
					if !module_command_request(state, "request-editor-exit") do return .Failed
					return .Ok
				} else if !control && scalar == 'd' {
					if !module_command_request(state, "maksym-open-directory") do return .Failed
					return .Ok
				} else if control && scalar == 'f' {
					return module_invoke(
						state,
						transmute([]u8)(string("maksym-find-file-relative")),
					)
				}
			} else if prefix == .Control_C && control {
				if scalar == 'c' && state.mode == .Edit {
					return module_invoke(state, transmute([]u8)(string("maksym-apply-editable-listing")))
				} else if (scalar == 'k' || scalar == '[') && state.mode == .Edit {
					return module_invoke(state, transmute([]u8)(string("maksym-cancel-editable-listing")))
				}
			} else if prefix == .Control_Zero && !control && scalar == 'w' {
				return module_invoke(state, transmute([]u8)(string("maksym-copy-absolute-paths")))
			} else if prefix == .Percent && !control && scalar == 'R' {
				return module_invoke(state, transmute([]u8)(string("maksym-rename-pattern")))
			}
			return module_publish(state)
		}
		if control && scalar == 'x' {
			state.prefix = .Control_X
			return .Ok
		}
		if control && scalar == 'c' {
			state.prefix = .Control_C
			return .Ok
		}
		if control && scalar == '0' {
			state.prefix = .Control_Zero
			return .Ok
		}
		if !control && !meta && scalar == '%' {
			state.prefix = .Percent
			return .Ok
		}
	}
	if header.kind == .Text_Commit {
		if state.mode == .Jump {
			if !module_append_filter(state, text) do return .Failed
		} else if state.mode == .Edit {
			if !module_append_edit(state, text) do return .Failed
		}
		return module_publish(state)
	}
	if header.kind != .Key do return .Invalid_Argument
	if state.mode == .Jump {
		if header.key_kind == .Enter {
			module_complete_jump(state)
		} else if header.key_kind == .Backspace && len(state.jump_filter) > 0 {
			copy, copy_error := strings.clone(state.jump_filter[:len(state.jump_filter) - 1], state.allocator)
			if copy_error != nil do return .Failed
			delete(state.jump_filter, state.allocator)
			state.jump_filter = copy
		} else if header.key_kind == .Unicode_Scalar && header.modifiers == 0 {
			if !module_append_filter(state, fmt.tprintf("%c", rune(header.scalar))) do return .Failed
		}
		return module_publish(state)
	}
	if state.mode == .Edit {
		if header.key_kind == .Delete {
			if !module_delete_edit(state) do return .Failed
		} else if header.key_kind == .Down {
			_, _, _ = maksym.directory_buffer_move(&state.buffer, 1)
		} else if header.key_kind == .Up {
			_, _, _ = maksym.directory_buffer_move(&state.buffer, -1)
		} else if header.key_kind == .Unicode_Scalar && header.modifiers == 0 {
			if !module_append_edit(state, fmt.tprintf("%c", rune(header.scalar))) do return .Failed
		}
		return module_publish(state)
	}
	if header.key_kind == .Down {
		_, _, _ = maksym.directory_buffer_move(&state.buffer, 1)
	} else if header.key_kind == .Up {
		_, _, _ = maksym.directory_buffer_move(&state.buffer, -1)
	} else if header.key_kind == .Enter {
		if !module_open_selection(state, 0) {
			module_diagnostic(state, "Maksym entry could not be opened")
		}
	} else if header.key_kind == .Unicode_Scalar && header.modifiers == 1 {
		switch rune(header.scalar) {
		case 'n': _, _, _ = maksym.directory_buffer_move(&state.buffer, 1)
		case 'p': _, _, _ = maksym.directory_buffer_move(&state.buffer, -1)
		case 'o': return module_invoke(state, transmute([]u8)(string("maksym-display-entry-other-pane")))
		case:
		}
	} else if header.key_kind == .Unicode_Scalar && header.modifiers == 0 {
		switch rune(header.scalar) {
		case 'n', ' ': _, _, _ = maksym.directory_buffer_move(&state.buffer, 1)
		case 'p': _, _, _ = maksym.directory_buffer_move(&state.buffer, -1)
		case 'e', 'f': return module_invoke(state, transmute([]u8)(string("maksym-open-entry")))
		case 'o': return module_invoke(state, transmute([]u8)(string("maksym-open-entry-other-pane")))
		case 's': return module_invoke(state, transmute([]u8)(string("maksym-cycle-sort")))
		case 'j': return module_invoke(state, transmute([]u8)(string("maksym-jump-to-entry")))
		case 'g': return module_invoke(state, transmute([]u8)(string("maksym-refresh")))
		case '(' : return module_invoke(state, transmute([]u8)(string("maksym-toggle-details")))
		case 'm': return module_invoke(state, transmute([]u8)(string("maksym-mark-entry")))
		case 'u': return module_invoke(state, transmute([]u8)(string("maksym-unmark-entry")))
		case 't': return module_invoke(state, transmute([]u8)(string("maksym-invert-marks")))
		case 'U': return module_invoke(state, transmute([]u8)(string("maksym-unmark-all")))
		case '+': return module_invoke(state, transmute([]u8)(string("maksym-create-directory")))
		case 'C': return module_invoke(state, transmute([]u8)(string("maksym-copy-targets")))
		case 'R': return module_invoke(state, transmute([]u8)(string("maksym-move-targets")))
		case 'D': return module_invoke(state, transmute([]u8)(string("maksym-delete-targets")))
		case 'w': return module_invoke(state, transmute([]u8)(string("maksym-copy-names")))
		case 'y': return module_invoke(state, transmute([]u8)(string("maksym-describe-entry-type")))
		case 'X', '!': return module_invoke(state, transmute([]u8)(string("maksym-shell-command")))
		case '&': return module_invoke(state, transmute([]u8)(string("maksym-shell-command-async")))
		case '^': return module_invoke(state, transmute([]u8)(string("maksym-parent-directory")))
		case 'q': return module_deactivate(state, true)
		case:
		}
	}
	return module_publish(state)
}

@(private)
module_select :: proc(state: ^Module_Instance, request: []u8) -> product_module.Status {
	if state == nil || !state.active || len(request) != size_of(product_module.Selection_Request) {
		return .Invalid_Argument
	}
	selection := (^product_module.Selection_Request)(raw_data(request))
	if selection.schema_version != product_module.UI_LIST_SCHEMA_VERSION ||
	   selection.item_id <= MAKSYM_MODULE_HEADER_ID {
		return .Invalid_Argument
	}
	identity, referenced := module_item_reference_identity(state.item_references, selection.item_id)
	if !referenced do return .Stale
	selected, _ := maksym.directory_buffer_select(&state.buffer, identity)
	if !selected do return .Failed
	return module_publish(state)
}

@(private)
module_deactivate :: proc(state: ^Module_Instance, restore: bool) -> product_module.Status {
	if state == nil do return .Invalid_Argument
	restored := true
	if restore && state.active {
		_, restored = module_session_request(state, .Restore_Target, state.previous_target, "")
	}
	module_release_directory(state)
	state.previous_target = 0
	return .Ok if restored else .Failed
}

@(private)
module_close :: proc "c" (instance: u64) -> product_module.Status {
	context = runtime.default_context()
	if instance == 0 do return .Invalid_Argument
	state := (^Module_Instance)(uintptr(instance))
	status := module_deactivate(state, false)
	free(state)
	return status
}
