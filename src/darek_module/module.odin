// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package darek_module

import "../darek"
import "../filesystem"
import "../product_module"
import "../project"
import "base:runtime"
import "core:fmt"
import "core:strings"
import "core:path/filepath"

DAREK_MODULE_INSTANCE_ID :: darek.Instance_ID(1)
DAREK_MODULE_ACTION_OWNER :: u64(0x4F44_5241_4441_5245)

Input_Mode :: enum u8 {
	Browse,
	Create_File,
	Create_Directory,
	Rename,
	Move,
	Copy,
	Delete,
	Project_Rename,
	Filter,
	Shell_Node,
	Shell_Project,
	Help,
	Help_Advanced,
}

Module_Instance :: struct {
	host_call:               product_module.Host_Call,
	capability:              u64,
	instance:                darek.Instance,
	projection:              darek.Tree_Projection,
	allocator:               runtime.Allocator,
	temporary_allocator:     runtime.Allocator,
	next_generation:         darek.Instance_Generation,
	presentation_generation: u64,
	active:                  bool,
	focused:                 bool,
	help_active:             bool,
	input_mode:              Input_Mode,
	input_text:              [int(filesystem.MAX_PATH_BYTES)]u8,
	input_length:            int,
	target_path:             [int(filesystem.MAX_PATH_BYTES)]u8,
	target_path_length:      int,
	target_resource:         product_module.Filesystem_Resource,
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
	value.role = .Workspace_Hierarchy
	value.identity_length = u16(copy(value.identity[:], "odra.darek"))
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
	case .Inspect: return module_publish(state)
	case .Deactivate: return module_deactivate(state)
	case .Step:
		if !state.active do return .Unavailable
		changed := false
		if len(input_bytes) > 0 {
			view, _, inspected, _ := darek.instance_inspect(&state.instance)
			if !inspected do return .Failed
			if view.follow.enabled {
				_, changed, _ = darek.instance_reveal_path(&state.instance, string(input_bytes))
				if changed && module_publish(state) != .Ok do return .Failed
			}
		}
		if output_capacity > 0 {
			if output == nil do return .Invalid_Argument
			output^ = 1 if changed else 0
			output_length^ = 1
		}
		return .Ok
	case .Input: return module_input(state, input_bytes)
	case .Select: return module_select(state, input_bytes)
	case .Configure: return module_configure_presentation(state, input_bytes)
	case .Invalid: return .Invalid_Argument
	}
	return .Invalid_Argument
}

@(private)
module_diagnostic :: proc(state: ^Module_Instance, message: string) {
	if state == nil || state.host_call == nil do return
	bytes := transmute([]u8)message
	_ = state.host_call(
		state.capability, .Diagnostic, raw_data(bytes), u64(len(bytes)), nil, 0, nil,
	)
}

@(private)
module_prompt_state :: proc(state: ^Module_Instance, active: bool) {
	if state == nil || state.host_call == nil do return
	value := [1]u8{1 if active else 0}
	_ = state.host_call(
		state.capability, .Prompt, raw_data(value[:]), 1, nil, 0, nil,
	)
}

@(private)
module_command_request :: proc(
	state: ^Module_Instance,
	action: product_module.Command_Action,
	payload: string = "",
) -> bool {
	if state == nil || state.host_call == nil || action == .Invalid do return false
	header := product_module.Command_Request_Header {
		schema_version = product_module.COMMAND_REQUEST_SCHEMA_VERSION,
		action = action,
		payload_length = u64(len(payload)),
	}
	request, allocation_error := make(
		[]u8, size_of(header) + len(payload), state.temporary_allocator,
	)
	if allocation_error != nil do return false
	defer delete(request, state.temporary_allocator)
	copy(request[:size_of(header)], ([^]u8)(rawptr(&header))[:size_of(header)])
	copy(request[size_of(header):], transmute([]u8)payload)
	return state.host_call(
		state.capability, .Command, raw_data(request), u64(len(request)), nil, 0, nil,
	) == .Ok
}

@(private)
module_provider_request :: proc(
	state: ^Module_Instance,
	service: string,
	generation, operation: u64,
	name: string,
	payload: []u8,
	output: []u8,
) -> (u64, bool) {
	if state == nil || state.host_call == nil || len(service) == 0 || generation == 0 do return 0, false
	header := product_module.Provider_Request_Header {
		schema_version = product_module.PROVIDER_REQUEST_SCHEMA_VERSION,
		provider_generation = generation,
		operation = operation,
		service_length = u32(len(service)),
		name_length = u32(len(name)),
		payload_length = u64(len(payload)),
	}
	request, allocation_error := make(
		[]u8, size_of(header) + len(service) + len(name) + len(payload), state.temporary_allocator,
	)
	if allocation_error != nil do return 0, false
	defer delete(request, state.temporary_allocator)
	copy(request[:size_of(header)], ([^]u8)(rawptr(&header))[:size_of(header)])
	offset := size_of(header)
	offset += copy(request[offset:], service)
	offset += copy(request[offset:], name)
	copy(request[offset:], payload)
	written: u64
	status := state.host_call(
		state.capability,
		.Provider,
		raw_data(request),
		u64(len(request)),
		raw_data(output),
		u64(len(output)),
		&written,
	)
	return written, status == .Ok && written <= u64(len(output))
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
module_prompt_message :: proc(state: ^Module_Instance) {
	if state == nil do return
	label := "Resource name: "
	if state.input_mode == .Rename do label = "Rename to: "
	if state.input_mode == .Move do label = "Move to directory: "
	if state.input_mode == .Copy do label = "Copy to directory: "
	if state.input_mode == .Delete do label = "Permanently delete selected resource? [y/N] "
	if state.input_mode == .Project_Rename do label = "Project name: "
	if state.input_mode == .Filter do label = "Filter names: "
	if state.input_mode == .Shell_Node do label = "Shell command in selected Darek context: "
	if state.input_mode == .Shell_Project do label = "Shell command in selected Darek Project: "
	message := fmt.tprintf("%s%s", label, string(state.input_text[:state.input_length]))
	module_diagnostic(state, message)
}

@(private)
module_release :: proc(state: ^Module_Instance) {
	if state == nil do return
	if state.active do _, _ = module_session_request(state, .Clear_Preview, 0, "")
	if state.projection.state != nil do _ = darek.tree_projection_close(&state.projection)
	if state.instance.state != nil do _, _ = darek.instance_close(&state.instance)
	state.projection = {}
	state.instance = {}
	state.active = false
	state.focused = false
	state.help_active = false
	state.input_mode = .Browse
	state.input_length = 0
	state.target_path_length = 0
	state.target_resource = {}
	module_prompt_state(state, false)
}

@(private)
module_project_handle :: proc(index: int) -> project.Project_Handle {
	return {
		owner = {id = 1, generation = 1},
		id = project.Project_ID(index + 1),
		generation = 1,
	}
}

@(private)
module_activate :: proc(state: ^Module_Instance, payload: string) -> product_module.Status {
	if state == nil || len(payload) == 0 do return .Invalid_Argument
	trimmed_payload := strings.trim_right(payload, "\r\n")
	lines := strings.split_lines(trimmed_payload, state.temporary_allocator)
	defer delete(lines, state.temporary_allocator)
	if len(lines) < 2 do return .Invalid_Argument
	mode := lines[0]
	if mode != "directory" && mode != "project" && mode != "workspace" {
		return .Invalid_Argument
	}
	root_count := len(lines) - 1
	if mode != "workspace" && root_count != 1 do return .Invalid_Argument
	sources, allocation_error := make([]darek.Project_Root_Source, root_count, state.temporary_allocator)
	if allocation_error != nil do return .Failed
	defer delete(sources, state.temporary_allocator)
	paths, paths_error := make([]string, root_count, state.temporary_allocator)
	if paths_error != nil do return .Failed
	defer delete(paths, state.temporary_allocator)
	labels, labels_error := make([]string, root_count, state.temporary_allocator)
	if labels_error != nil do return .Failed
	defer delete(labels, state.temporary_allocator)
	for line, index in lines[1:] {
		separator := strings.index_byte(line, '\t')
		if separator < 1 || separator >= len(line) - 1 do return .Invalid_Argument
		labels[index] = line[:separator]
		paths[index] = line[separator + 1:]
		batch, observed, _ := filesystem.directory_observe(
			paths[index], u64(state.next_generation) + u64(index) + 1,
			{persistent = state.temporary_allocator, temporary = state.temporary_allocator},
		)
		if observed {
			sources[index] = {
				project = module_project_handle(index),
				resource = batch.directory_identity,
				label = labels[index],
				path = paths[index],
				provider_generation = darek.Provider_Generation(state.next_generation),
				available = true,
			}
			filesystem.directory_batch_close(&batch)
		} else {
			sources[index] = {
				project = module_project_handle(index),
				label = labels[index],
				path = paths[index],
				provider_generation = darek.Provider_Generation(state.next_generation),
			}
		}
	}
	generation := state.next_generation + 1
	if generation == 0 do generation = 1
	candidate: darek.Instance
	root_request := darek.Root_Request {
		mode = .Project,
		project = sources[0].project,
	}
	if mode == "workspace" {
		root_request = {
			mode = .Workspace,
			workspace = {
				id = "active-workspace",
				generation = u64(generation),
				root_generation = u64(generation),
			},
		}
	} else if mode == "directory" {
		root_request = {
			mode = .Directory,
			path = sources[0].path,
			resource = sources[0].resource,
		}
	}
	opened, _ := darek.instance_open(
		&candidate,
		{id = DAREK_MODULE_INSTANCE_ID, generation = generation, policy = darek.DEFAULT_POLICY, allocator = state.allocator},
		root_request,
	)
	if !opened do return .Unavailable
	published := false
	if mode == "directory" {
		published, _ = darek.instance_publish_local_root(&candidate)
	} else {
		published, _ = darek.instance_publish_project_roots(&candidate, sources)
	}
	if !published {
		_, _ = darek.instance_close(&candidate)
		return .Stale
	}
	if _, expanded, _ := darek.instance_expand_roots(&candidate); !expanded {
		_, _ = darek.instance_close(&candidate)
		return .Denied
	}
	_, _, _ = darek.instance_resize_viewport(&candidate, 40)
	previous_instance := state.instance
	previous_projection := state.projection
	previous_active := state.active
	previous_focused := state.focused
	state.instance = candidate
	state.projection = {}
	state.next_generation = generation
	state.active = true
	state.focused = true
	state.help_active = false
	state.input_mode = .Browse
	state.input_length = 0
	state.target_path_length = 0
	publish_status := module_publish(state)
	if publish_status != .Ok {
		if state.projection.state != nil do _ = darek.tree_projection_close(&state.projection)
		_, _ = darek.instance_close(&state.instance)
		state.instance = previous_instance
		state.projection = previous_projection
		state.active = previous_active
		state.focused = previous_focused
		return publish_status
	}
	if previous_projection.state != nil do _ = darek.tree_projection_close(&previous_projection)
	if previous_instance.state != nil do _, _ = darek.instance_close(&previous_instance)
	module_prompt_state(state, false)
	module_diagnostic(
		state,
		"Opened Workspace in Darek" if mode == "workspace" else
		"Opened Project in Darek" if mode == "project" else "Opened directory in Darek",
	)
	return .Ok
}

@(private)
module_selected_path :: proc(state: ^Module_Instance) -> (string, darek.Node_Kind, bool) {
	if state == nil || !state.active do return "", .Invalid, false
	target, ok, _ := darek.instance_selected_target(&state.instance)
	if !ok do return "", .Invalid, false
	return target.path, target.kind, len(target.path) > 0
}

@(private)
module_selected_project_path :: proc(state: ^Module_Instance) -> (string, bool) {
	if state == nil || !state.active do return "", false
	root, selected, _ := darek.instance_selected_project_root(&state.instance)
	return root.path, selected && len(root.path) > 0
}

@(private)
module_session_request :: proc(
	state: ^Module_Instance,
	action: product_module.Session_Action,
	target: u64,
	payload: string,
	flags: u64 = 0,
) -> (product_module.Session_Response, bool) {
	header := product_module.Session_Request_Header {
		schema_version = product_module.SESSION_REQUEST_SCHEMA_VERSION,
		action = action,
		target = target,
		flags = flags,
		payload_length = u64(len(payload)),
	}
	request, allocation_error := make([]u8, size_of(header) + len(payload), state.temporary_allocator)
	if allocation_error != nil do return {}, false
	defer delete(request, state.temporary_allocator)
	copy(request[:size_of(header)], ([^]u8)(rawptr(&header))[:size_of(header)])
	copy(request[size_of(header):], payload)
	response: product_module.Session_Response
	written: u64
	status := state.host_call(
		state.capability, .Session, raw_data(request), u64(len(request)),
		raw_data(([^]u8)(rawptr(&response))[:size_of(response)]), size_of(response), &written,
	)
	return response, status == .Ok && written == u64(size_of(response))
}

@(private)
module_open_selected :: proc(state: ^Module_Instance, placement_flags: u64, focus: bool) -> bool {
	path, kind, selected := module_selected_path(state)
	if !selected do return false
	if kind == .Directory || kind == .Project {
		changed, ok, _ := darek.instance_toggle_selected(&state.instance)
		return changed || ok
	}
	opened, opened_ok := module_session_request(state, .Open_Path, 0, path)
	if !opened_ok do return false
	if kind == .Symbol {
		target, target_ok, _ := darek.instance_selected_target(&state.instance)
		if !target_ok || target.source_revision == 0 do return false
		position := product_module.Session_Position {
			revision = target.source_revision,
			point = target.start,
		}
		payload := ([^]u8)(rawptr(&position))[:size_of(position)]
		header := product_module.Session_Request_Header {
			schema_version = product_module.SESSION_REQUEST_SCHEMA_VERSION,
			action = .Present_Position,
			target = opened.target,
			flags = product_module.SESSION_PRESENT_FOCUS,
			payload_length = u64(len(payload)),
		}
		request: [size_of(product_module.Session_Request_Header) + size_of(product_module.Session_Position)]u8
		copy(request[:size_of(header)], ([^]u8)(rawptr(&header))[:size_of(header)])
		copy(request[size_of(header):], payload)
		response: product_module.Session_Response
		written: u64
		status := state.host_call(
			state.capability, .Session, raw_data(request[:]), u64(len(request)),
			raw_data(([^]u8)(rawptr(&response))[:size_of(response)]), size_of(response), &written,
		)
		if status != .Ok || written != u64(size_of(response)) do return false
		state.focused = false
		module_diagnostic(state, "Opened Darek symbol")
		return true
	}
	flags := placement_flags
	if focus do flags |= product_module.SESSION_PRESENT_FOCUS
	_, presented := module_session_request(state, .Present_Entry, opened.target, "", flags)
	if presented {
		if focus do state.focused = false
		module_diagnostic(state, "Opened Darek file")
	}
	return presented
}

@(private)
module_project_selected_symbols :: proc(state: ^Module_Instance) -> bool {
	if state == nil || !state.active do return false
	target, selected, _ := darek.instance_selected_target(&state.instance)
	if !selected || target.kind != .File do return false
	view, _, inspected, _ := darek.instance_inspect(&state.instance)
	if !inspected do return false
	output, allocation_error := make([]u8, int(product_module.MAX_CALL_BYTES), state.temporary_allocator)
	if allocation_error != nil do return false
	defer delete(output, state.temporary_allocator)
	written, queried := module_provider_request(
		state,
		"language.document-symbols",
		u64(view.node_generation),
		1,
		target.path,
		nil,
		output,
	)
	if !queried || written < u64(size_of(product_module.Symbol_Provider_Response_Header)) {
		module_diagnostic(state, "No current symbol index is available for the selected file")
		return false
	}
	header := (^product_module.Symbol_Provider_Response_Header)(raw_data(output))
	record_bytes := u64(header.record_count) * u64(size_of(product_module.Symbol_Provider_Record))
	header_bytes := u64(size_of(product_module.Symbol_Provider_Response_Header))
	if header.schema_version != product_module.SYMBOL_PROVIDER_RESPONSE_SCHEMA_VERSION ||
	   header.provider_generation == 0 || header.source_revision == 0 ||
	   header_bytes + record_bytes + u64(header.text_bytes) != written {
		return false
	}
	symbols, symbols_error := make([]darek.Symbol_Source, int(header.record_count), state.temporary_allocator)
	if symbols_error != nil do return false
	defer delete(symbols, state.temporary_allocator)
	text := output[int(header_bytes + record_bytes):int(written)]
	for index in 0 ..< int(header.record_count) {
		offset := int(header_bytes) + index * size_of(product_module.Symbol_Provider_Record)
		record := (^product_module.Symbol_Provider_Record)(raw_data(output[offset:]))
		if record.id == 0 || record._reserved[0] != 0 || record._reserved[1] != 0 ||
		   record._reserved[2] != 0 || record._reserved[3] != 0 ||
		   record._reserved[4] != 0 || record._reserved[5] != 0 || record._reserved[6] != 0 ||
		   u64(record.name_offset) + u64(record.name_length) > u64(len(text)) {
			return false
		}
		symbols[index] = {
			id = record.id,
			parent_id = record.parent_id,
			hierarchy_depth = record.hierarchy_depth,
			name = string(text[record.name_offset:record.name_offset + u32(record.name_length)]),
			start = record.start,
			end = record.end,
		}
	}
	changed, published, _ := darek.instance_publish_symbols(
		&state.instance,
		view.node_generation,
		darek.Provider_Generation(header.provider_generation),
		target.resource,
		target.path,
		header.source_revision,
		symbols,
	)
	if !published {
		module_diagnostic(state, "The selected file changed before its symbols were published")
		return false
	}
	module_diagnostic(
		state,
		"Projected selected-file symbols in Darek" if changed else "Darek symbols are already current",
	)
	return true
}

@(private)
module_preview_selected :: proc(state: ^Module_Instance) -> bool {
	if state == nil || !state.active do return false
	request, requested, _ := darek.instance_preview_request(&state.instance)
	if !requested do return false
	opened, opened_ok := module_session_request(state, .Open_Path, 0, request.path)
	if !opened_ok do return false
	_, presented := module_session_request(state, .Present_Preview, opened.target, "")
	return presented
}

@(private)
module_scroll_preview :: proc(state: ^Module_Instance, backward, page: bool) -> bool {
	flags: u64
	if backward do flags |= product_module.SESSION_SCROLL_BACKWARD
	if page do flags |= product_module.SESSION_SCROLL_PAGE
	_, scrolled := module_session_request(state, .Scroll_Preview, 0, "", flags)
	return scrolled
}

@(private)
module_reveal_active_document :: proc(state: ^Module_Instance) -> bool {
	if state == nil || state.host_call == nil do return false
	header := product_module.Session_Request_Header {
		schema_version = product_module.SESSION_REQUEST_SCHEMA_VERSION,
		action = .Inspect_Active_Document,
	}
	path: [int(filesystem.MAX_PATH_BYTES)]u8
	written: u64
	status := state.host_call(
		state.capability,
		.Session,
		raw_data(([^]u8)(rawptr(&header))[:size_of(header)]),
		size_of(header),
		raw_data(path[:]),
		u64(len(path)),
		&written,
	)
	if status != .Ok || written == 0 || written > u64(len(path)) do return false
	_, changed, _ := darek.instance_reveal_path(&state.instance, string(path[:int(written)]))
	if changed {
		view, _, inspected, _ := darek.instance_inspect(&state.instance)
		if inspected && view.preview.enabled do _ = module_preview_selected(state)
	}
	return changed
}

@(private)
module_replace_with_directory :: proc(state: ^Module_Instance, path: string) -> bool {
	if state == nil || len(path) == 0 do return false
	label := filepath.base(path)
	if len(label) == 0 do label = path
	payload := fmt.tprintf("directory\n%s\t%s", label, path)
	return module_activate(state, payload) == .Ok
}

@(private)
module_replace_root :: proc(state: ^Module_Instance, parent: bool) -> bool {
	path, kind, selected := module_selected_path(state)
	if !selected do return false
	target := path
	if parent || kind != .Directory do target = filepath.dir(path)
	if len(target) == 0 || target == "." do return false
	return module_replace_with_directory(state, target)
}

@(private)
module_collapse_parent :: proc(state: ^Module_Instance) -> bool {
	if state == nil do return false
	moved, ok, _ := darek.instance_move_parent(&state.instance)
	if !ok do return false
	target, selected, _ := darek.instance_selected_target(&state.instance)
	if selected && (target.kind == .Directory || target.kind == .Project) &&
	   target.children == .Expanded {
		_, collapsed, _ := darek.instance_toggle_selected(&state.instance)
		return moved || collapsed
	}
	return moved
}

@(private)
module_decode_invocation :: proc(input: []u8) -> (string, bool) {
	if len(input) >= size_of(product_module.Invocation_Request_Header) {
		header := (^product_module.Invocation_Request_Header)(raw_data(input))
		if header.schema_version == product_module.INVOCATION_REQUEST_SCHEMA_VERSION &&
		   header.name_length > 0 &&
		   int(header.name_length) == len(input) - size_of(product_module.Invocation_Request_Header) {
			return string(input[size_of(product_module.Invocation_Request_Header):]), true
		}
	}
	return string(input), len(input) > 0
}

@(private)
module_begin_resource_input :: proc(state: ^Module_Instance, mode: Input_Mode) -> bool {
	if state == nil || (mode != .Create_File && mode != .Create_Directory &&
	   mode != .Rename && mode != .Move && mode != .Copy && mode != .Delete) {
		return false
	}
	path, kind, selected := module_selected_path(state)
	if !selected || kind == .Project || len(path) > len(state.target_path) do return false
	state.input_mode = mode
	state.input_length = 0
	state.target_path_length = copy(state.target_path[:], path)
	if mode == .Rename || mode == .Move || mode == .Copy || mode == .Delete {
		target, target_ok, _ := darek.instance_selected_target(&state.instance)
		if !target_ok do return false
		state.target_resource = {
			provider = target.resource.provider,
			device = target.resource.device,
			inode = target.resource.inode,
		}
		if mode == .Rename {
			name := filepath.base(path)
			if len(name) == 0 || len(name) > len(state.input_text) do return false
			state.input_length = copy(state.input_text[:], name)
		}
	}
	module_prompt_state(state, true)
	module_prompt_message(state)
	return true
}

@(private)
module_filesystem_request :: proc(
	state: ^Module_Instance,
	action: product_module.Filesystem_Action,
	resource: product_module.Filesystem_Resource,
	source, destination: string,
) -> bool {
	if state == nil || action == .Invalid || len(source) == 0 do return false
	header := product_module.Filesystem_Request_Header {
		schema_version = product_module.FILESYSTEM_REQUEST_SCHEMA_VERSION,
		action = action,
		resource = resource,
		source_length = u32(len(source)),
		destination_length = u32(len(destination)),
	}
	request, allocation_error := make(
		[]u8, size_of(header) + len(source) + len(destination), state.temporary_allocator,
	)
	if allocation_error != nil do return false
	defer delete(request, state.temporary_allocator)
	copy(request[:size_of(header)], ([^]u8)(rawptr(&header))[:size_of(header)])
	copy(request[size_of(header):], source)
	copy(request[size_of(header) + len(source):], destination)
	return state.host_call(
		state.capability, .Filesystem, raw_data(request), u64(len(request)), nil, 0, nil,
	) == .Ok
}

@(private)
module_process_request :: proc(state: ^Module_Instance, directory, command_text: string) -> bool {
	if state == nil || len(directory) == 0 || len(command_text) == 0 do return false
	header := product_module.Process_Request_Header {
		schema_version = product_module.PROCESS_REQUEST_SCHEMA_VERSION,
		action = .Shell,
		working_directory_length = u32(len(directory)),
		command_length = u32(len(command_text)),
	}
	request, allocation_error := make(
		[]u8, size_of(header) + len(directory) + len(command_text), state.temporary_allocator,
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
module_begin_shell_input :: proc(state: ^Module_Instance, project_root: bool) -> bool {
	if state == nil || state.input_mode != .Browse do return false
	path, kind, selected := module_selected_path(state)
	if !selected do return false
	directory := path if kind == .Directory || kind == .Project else filepath.dir(path)
	if project_root {
		root, root_ok, _ := darek.instance_selected_project_root(&state.instance)
		if !root_ok do return false
		directory = root.path
	}
	if len(directory) == 0 || len(directory) > len(state.target_path) do return false
	state.input_mode = .Shell_Project if project_root else .Shell_Node
	state.input_length = 0
	state.target_path_length = copy(state.target_path[:], directory)
	module_prompt_state(state, true)
	module_prompt_message(state)
	return true
}

@(private)
module_workspace_request :: proc(
	state: ^Module_Instance,
	action: product_module.Workspace_Action,
	project_path, value: string,
) -> bool {
	if state == nil || action == .Invalid do return false
	header := product_module.Workspace_Request_Header {
		schema_version = product_module.WORKSPACE_REQUEST_SCHEMA_VERSION,
		action = action,
		project_length = u32(len(project_path)),
		value_length = u32(len(value)),
	}
	request, allocation_error := make(
		[]u8, size_of(header) + len(project_path) + len(value), state.temporary_allocator,
	)
	if allocation_error != nil do return false
	defer delete(request, state.temporary_allocator)
	copy(request[:size_of(header)], ([^]u8)(rawptr(&header))[:size_of(header)])
	copy(request[size_of(header):], project_path)
	copy(request[size_of(header) + len(project_path):], value)
	return state.host_call(
		state.capability, .Workspace, raw_data(request), u64(len(request)), nil, 0, nil,
	) == .Ok
}

@(private)
module_begin_project_rename :: proc(state: ^Module_Instance) -> bool {
	if state == nil do return false
	root, selected, _ := darek.instance_selected_project_root(&state.instance)
	if !selected || len(root.path) == 0 || len(root.path) > len(state.target_path) ||
	   len(root.label) == 0 || len(root.label) > len(state.input_text) {
		return false
	}
	state.input_mode = .Project_Rename
	state.target_path_length = copy(state.target_path[:], root.path)
	state.input_length = copy(state.input_text[:], root.label)
	module_prompt_state(state, true)
	module_prompt_message(state)
	return true
}

@(private)
module_begin_filter :: proc(state: ^Module_Instance) -> bool {
	if state == nil do return false
	view, _, inspected, _ := darek.instance_inspect(&state.instance)
	if !inspected || len(view.panel.filter) > len(state.input_text) do return false
	state.input_mode = .Filter
	state.input_length = copy(state.input_text[:], view.panel.filter)
	module_prompt_state(state, true)
	module_prompt_message(state)
	return true
}

@(private)
module_apply_resource_input :: proc(state: ^Module_Instance) -> bool {
	if state == nil do return false
	if state.input_mode == .Filter {
		value := string(state.input_text[:state.input_length])
		_, filtered, _ := darek.instance_set_name_filter(&state.instance, value)
		state.input_mode = .Browse
		state.input_length = 0
		module_prompt_state(state, false)
		module_diagnostic(state, "Darek name filter updated" if filtered else "Darek name filter unchanged")
		return filtered
	}
	if state.input_mode == .Shell_Node || state.input_mode == .Shell_Project {
		if state.target_path_length == 0 || state.input_length == 0 do return false
		directory := string(state.target_path[:state.target_path_length])
		command_text := string(state.input_text[:state.input_length])
		success := module_process_request(state, directory, command_text)
		state.input_mode = .Browse
		state.input_length = 0
		state.target_path_length = 0
		module_prompt_state(state, false)
		module_diagnostic(
			state,
			"Started Darek contextual shell command" if success else "Darek shell command was rejected",
		)
		return success
	}
	if state.target_path_length == 0 ||
	   state.input_mode != .Delete && state.input_length == 0 {
		return false
	}
	name := string(state.input_text[:state.input_length])
	target := string(state.target_path[:state.target_path_length])
	success := false
	if state.input_mode == .Create_File || state.input_mode == .Create_Directory {
		_, kind, selected := module_selected_path(state)
		if !selected do return false
		parent := target if kind == .Directory else filepath.dir(target)
		action := product_module.Filesystem_Action.Create_File
		if state.input_mode == .Create_Directory do action = .Create_Directory
		success = module_filesystem_request(state, action, {}, parent, name)
		if success {
			if kind == .Directory {
				_, _, _ = darek.instance_refresh_selected(&state.instance)
			} else {
				_, _, _ = darek.instance_refresh_containing_directory(&state.instance)
			}
			module_diagnostic(state, "Created Darek resource")
		}
	} else if state.input_mode == .Rename {
		success = module_filesystem_request(
			state, .Rename, state.target_resource, target, name,
		)
		if success {
			_, _, _ = darek.instance_refresh_containing_directory(&state.instance)
			module_diagnostic(state, "Renamed Darek resource")
		}
	} else if state.input_mode == .Move || state.input_mode == .Copy {
		action := product_module.Filesystem_Action.Move
		if state.input_mode == .Copy do action = .Copy
		success = module_filesystem_request(state, action, state.target_resource, target, name)
		if success {
			_, _, _ = darek.instance_refresh_containing_directory(&state.instance)
			module_diagnostic(state, "Moved Darek resource" if action == .Move else "Copied Darek resource")
		}
	} else if state.input_mode == .Delete {
		success = module_filesystem_request(state, .Delete, state.target_resource, target, "")
		if success {
			_, _, _ = darek.instance_refresh_containing_directory(&state.instance)
			module_diagnostic(state, "Permanently deleted Darek resource; recovery is unavailable")
		}
	} else if state.input_mode == .Project_Rename {
		success = module_workspace_request(state, .Rename_Project, target, name)
		if success do module_diagnostic(state, "Renamed Project")
	}
	state.input_mode = .Browse
	state.input_length = 0
	state.target_path_length = 0
	state.target_resource = {}
	module_prompt_state(state, false)
	if !success do module_diagnostic(state, "Darek operation failed because the resource changed or is unavailable")
	return true
}

@(private)
module_input :: proc(state: ^Module_Instance, input: []u8) -> product_module.Status {
	if state == nil || !state.active || state.input_mode == .Browse ||
	   len(input) < size_of(product_module.Input_Request_Header) {
		return .Unavailable
	}
	header := (^product_module.Input_Request_Header)(raw_data(input))
	if header.schema_version != product_module.INPUT_REQUEST_SCHEMA_VERSION do return .Invalid_Argument
	if state.input_mode == .Delete && header.kind == .Key &&
	   header.key_kind == .Unicode_Scalar {
		if header.scalar == 'y' || header.scalar == 'Y' {
			return .Ok if module_apply_resource_input(state) else .Failed
		}
		state.input_mode = .Browse
		state.target_path_length = 0
		state.target_resource = {}
		module_prompt_state(state, false)
		return .Ok
	}
	if header.kind == .Text_Commit {
		header_bytes := size_of(product_module.Input_Request_Header)
		if int(header.text_length) != len(input) - header_bytes ||
		   int(header.text_length) > len(state.input_text) - state.input_length {
			return .Limit
		}
		state.input_length += copy(
			state.input_text[state.input_length:], input[header_bytes:],
		)
		module_prompt_message(state)
		return .Ok
	}
	if header.kind != .Key do return .Invalid_Argument
	#partial switch header.key_kind {
	case .Backspace, .Delete:
		if state.input_length > 0 do state.input_length -= 1
		module_prompt_message(state)
	case .Enter:
		if !module_apply_resource_input(state) do return .Failed
		return module_publish(state)
	case .Escape:
		state.input_mode = .Browse
		state.input_length = 0
		state.target_path_length = 0
		state.target_resource = {}
		module_prompt_state(state, false)
	case .Unicode_Scalar:
		if header.scalar < 0 || header.scalar > 0x7f || state.input_length >= len(state.input_text) {
			return .Invalid_Argument
		}
		state.input_text[state.input_length] = u8(header.scalar)
		state.input_length += 1
		module_prompt_message(state)
	}
	return .Ok if header.key_kind == .Backspace || header.key_kind == .Delete ||
		header.key_kind == .Escape || header.key_kind == .Unicode_Scalar else .Unavailable
}

@(private)
module_select :: proc(state: ^Module_Instance, input: []u8) -> product_module.Status {
	if state == nil || !state.active || len(input) != size_of(product_module.Selection_Request) {
		return .Invalid_Argument
	}
	request := (^product_module.Selection_Request)(raw_data(input))
	if request.schema_version != product_module.UI_TREE_PANEL_SCHEMA_VERSION || request.item_id == 0 {
		return .Invalid_Argument
	}
	selected, _, _ := darek.instance_select_node(&state.instance, darek.Node_ID(request.item_id))
	if !selected do return .Stale
	view, _, inspected, _ := darek.instance_inspect(&state.instance)
	if inspected && view.preview.enabled do _ = module_preview_selected(state)
	return module_publish(state)
}

@(private)
module_invoke :: proc(state: ^Module_Instance, input: []u8) -> product_module.Status {
	name, decoded := module_decode_invocation(input)
	if !decoded do return .Invalid_Argument
	if !state.active do return .Unavailable
	changed := true
	selection_changed := false
	switch name {
	case "darek-next-node": _, changed, _ = darek.instance_move_visible(&state.instance, 1); selection_changed = changed
	case "darek-previous-node": _, changed, _ = darek.instance_move_visible(&state.instance, -1); selection_changed = changed
	case "darek-next-sibling": _, changed, _ = darek.instance_move_sibling(&state.instance, 1); selection_changed = changed
	case "darek-previous-sibling": _, changed, _ = darek.instance_move_sibling(&state.instance, -1); selection_changed = changed
	case "darek-next-project": _, changed, _ = darek.instance_move_project(&state.instance, 1); selection_changed = changed
	case "darek-previous-project": _, changed, _ = darek.instance_move_project(&state.instance, -1); selection_changed = changed
	case "darek-parent-node": _, changed, _ = darek.instance_move_parent(&state.instance); selection_changed = changed
	case "darek-collapse-parent": changed = module_collapse_parent(state); selection_changed = changed
	case "darek-root-parent":
		return .Ok if module_replace_root(state, true) else .Unavailable
	case "darek-root-current-directory":
		return .Ok if module_replace_root(state, false) else .Unavailable
	case "darek-collapse-or-parent":
		target, selected, _ := darek.instance_selected_target(&state.instance)
		if !selected do return .Unavailable
		if (target.kind == .Directory || target.kind == .Project) && target.children == .Expanded {
			_, changed, _ = darek.instance_toggle_selected(&state.instance)
		} else {
			_, changed, _ = darek.instance_move_parent(&state.instance)
		}
	case "darek-structure-action":
		target, selected, _ := darek.instance_selected_target(&state.instance)
		if !selected do return .Unavailable
		if target.kind == .File {
			if !module_project_selected_symbols(state) do return .Unavailable
			return module_publish(state)
		}
		_, changed, _ = darek.instance_toggle_selected(&state.instance)
	case "darek-visit-action", "darek-open": changed = module_open_selected(state, 0, true)
	case "darek-open-split-below": changed = module_open_selected(state, product_module.SESSION_PRESENT_SPLIT_BELOW, true)
	case "darek-open-split-right": changed = module_open_selected(state, product_module.SESSION_PRESENT_SPLIT_RIGHT, true)
	case "darek-open-mru-pane": changed = module_open_selected(state, product_module.SESSION_PRESENT_OTHER_PANE, true)
	case "darek-open-and-hide":
		changed = module_open_selected(state, 0, true)
		if changed do _, _, _ = darek.instance_set_visible(&state.instance, false)
	case "darek-toggle":
		view, _, inspected, _ := darek.instance_inspect(&state.instance)
		if !inspected do return .Failed
		_, _, _ = darek.instance_set_visible(&state.instance, !view.visible)
		state.focused = !view.visible
	case "darek-select":
		_, _, _ = darek.instance_set_visible(&state.instance, true)
		state.focused = true
	case "darek-focus-toggle":
		state.focused = !state.focused
	case "darek-hide":
		if state.help_active {
			state.help_active = false
			state.input_mode = .Browse
			return module_publish(state)
		}
		_, _, _ = darek.instance_set_visible(&state.instance, false)
		state.focused = false
	case "darek-panel-left": _, _, _ = darek.instance_set_panel_side(&state.instance, .Left)
	case "darek-panel-right": _, _, _ = darek.instance_set_panel_side(&state.instance, .Right)
	case "darek-decrease-width": _, _, _, _ = darek.instance_adjust_panel_width(&state.instance, -i32(darek.PANEL_WIDTH_STEP))
	case "darek-increase-width": _, _, _, _ = darek.instance_adjust_panel_width(&state.instance, i32(darek.PANEL_WIDTH_STEP))
	case "darek-fit-width": _, _, _, _ = darek.instance_fit_panel_width(&state.instance)
	case "darek-toggle-extra-width": _, _, _, _, _ = darek.instance_toggle_extra_width(&state.instance)
	case "darek-toggle-width-lock": _, _, _, _ = darek.instance_toggle_width_lock(&state.instance)
	case "darek-toggle-directory-compression": _, _, _, _ = darek.instance_toggle_directory_compression(&state.instance)
	case "darek-narrow-current-project": _, changed, _ = darek.instance_set_current_project_only(&state.instance, true)
	case "darek-show-all-projects": _, changed, _ = darek.instance_set_current_project_only(&state.instance, false)
	case "darek-project-collapse": _, changed, _ = darek.instance_collapse_projects(&state.instance, .Current)
	case "darek-project-collapse-others": _, changed, _ = darek.instance_collapse_projects(&state.instance, .Others)
	case "darek-collapse-all-projects": _, changed, _ = darek.instance_collapse_projects(&state.instance, .All)
	case "darek-refresh":
		view, _, inspected, _ := darek.instance_inspect(&state.instance)
		if !inspected do return .Failed
		if view.watch.enabled && view.watch.status == .Refresh_Required {
			_, changed, _ = darek.instance_reconcile_watch(&state.instance)
		} else {
			_, changed, _ = darek.instance_refresh_selected(&state.instance)
		}
	case "darek-toggle-peek":
		enabled, _, ok, _ := darek.instance_toggle_preview(&state.instance)
		if !ok do return .Failed
		if enabled {
			if !module_preview_selected(state) {
				_, _, _, _ = darek.instance_toggle_preview(&state.instance)
				module_diagnostic(state, "Darek preview is unavailable for the selected node")
				return module_publish(state)
			}
		} else {
			_, _ = module_session_request(state, .Clear_Preview, 0, "")
		}
		module_diagnostic(state, "Darek preview enabled" if enabled else "Darek preview disabled")
	case "darek-toggle-file-follow":
		enabled, _, ok, _ := darek.instance_toggle_file_follow(&state.instance)
		if !ok do return .Failed
		module_diagnostic(state, "Darek file follow enabled" if enabled else "Darek file follow disabled")
	case "darek-toggle-hidden-files":
		view, _, inspected, _ := darek.instance_inspect(&state.instance)
		if !inspected do return .Failed
		_, changed, _ = darek.instance_set_hidden_visible(&state.instance, !view.panel.show_hidden)
		module_diagnostic(state, "Darek hidden entries visible" if !view.panel.show_hidden else "Darek hidden entries hidden")
	case "darek-toggle-vcs-ignored":
		view, _, inspected, _ := darek.instance_inspect(&state.instance)
		if !inspected do return .Failed
		_, changed, _ = darek.instance_set_ignored_visible(&state.instance, !view.panel.show_ignored)
		module_diagnostic(state, "Darek ignored entries visible" if !view.panel.show_ignored else "Darek ignored entries hidden")
	case "darek-toggle-file-watch":
		view, _, inspected, _ := darek.instance_inspect(&state.instance)
		if !inspected do return .Failed
		_, changed, _ = darek.instance_set_watch_enabled(
			&state.instance, !view.watch.enabled, darek.Provider_Generation(1),
		)
		module_diagnostic(state, "Darek file watching enabled" if !view.watch.enabled else "Darek file watching disabled")
	case "darek-toggle-vcs-decorations":
		view, _, inspected, _ := darek.instance_inspect(&state.instance)
		if !inspected do return .Failed
		_, changed, _ = darek.instance_set_version_control_visible(
			&state.instance, !view.panel.show_version_control,
		)
		module_diagnostic(state, "Darek version-control decorations visible" if !view.panel.show_version_control else "Darek version-control decorations hidden")
	case "darek-toggle-diagnostics":
		view, _, inspected, _ := darek.instance_inspect(&state.instance)
		if !inspected do return .Failed
		_, changed, _ = darek.instance_set_diagnostics_visible(
			&state.instance, !view.panel.show_diagnostics,
		)
		module_diagnostic(state, "Darek diagnostic decorations visible" if !view.panel.show_diagnostics else "Darek diagnostic decorations hidden")
	case "darek-select-sort":
		view, _, inspected, _ := darek.instance_inspect(&state.instance)
		if !inspected do return .Failed
		mode := darek.Sort_Mode.Name_Descending if view.panel.sort_mode == .Name_Ascending else .Name_Ascending
		_, changed, _ = darek.instance_set_sort_mode(&state.instance, mode)
		module_diagnostic(state, "Darek sorting: name descending" if mode == .Name_Descending else "Darek sorting: name ascending")
	case "darek-filter":
		if !module_begin_filter(state) do return .Unavailable
		return .Ok
	case "darek-workspace-switch":
		if !module_command_request(state, .Present_Workspace_Navigation) do return .Failed
	case "darek-open-external":
		module_diagnostic(state, "No external opener is available")
	case "darek-workspace-next":
		if !module_workspace_request(state, .Next, "", "") {
			module_diagnostic(state, "No next Workspace is available")
		}
	case "darek-move-project-up", "darek-move-project-down":
		path, selected := module_selected_project_path(state)
		if !selected do return .Unavailable
		action := product_module.Workspace_Action.Move_Project_Earlier
		if name == "darek-move-project-down" do action = .Move_Project_Later
		if !module_workspace_request(state, action, path, "") {
			module_diagnostic(state, "Project could not be reordered")
		}
	case "darek-project-add":
		if !module_command_request(state, .Present_Project_Navigation) do return .Failed
	case "darek-project-remove":
		path, selected := module_selected_project_path(state)
		if !selected do return .Unavailable
		if !module_workspace_request(state, .Remove_Project, path, "") {
			module_diagnostic(state, "Project could not be removed from the active Workspace")
		}
	case "darek-project-rename":
		if !module_begin_project_rename(state) do return .Unavailable
		return .Ok
	case "darek-find-current-file":
		changed = module_reveal_active_document(state)
		module_diagnostic(
			state,
			"Revealed current file in Darek" if changed else "Current file is outside the Darek roots",
		)
	case "darek-shell-command":
		if !module_begin_shell_input(state, false) do return .Unavailable
		return .Ok
	case "darek-shell-command-project":
		if !module_begin_shell_input(state, true) do return .Unavailable
		return .Ok
	case "darek-bulk-actions":
		path, kind, selected := module_selected_path(state)
		if !selected do return .Unavailable
		directory := path if kind == .Directory || kind == .Project else filepath.dir(path)
		if len(directory) == 0 || !module_command_request(state, .Present_File_Management, directory) {
			return .Failed
		}
		module_diagnostic(state, "Opened selected Darek context in Maksym for checked bulk actions")
	case "darek-context-actions":
		if !module_command_request(state, .Present_Navigation) do return .Failed
	case "darek-other-pane-next-line": changed = module_scroll_preview(state, false, false)
	case "darek-other-pane-previous-line": changed = module_scroll_preview(state, true, false)
	case "darek-other-pane-next-page": changed = module_scroll_preview(state, false, true)
	case "darek-other-pane-previous-page": changed = module_scroll_preview(state, true, true)
	case "darek-create-file":
		if !module_begin_resource_input(state, .Create_File) do return .Unavailable
		return .Ok
	case "darek-create-directory":
		if !module_begin_resource_input(state, .Create_Directory) do return .Unavailable
		return .Ok
	case "darek-rename-node":
		if !module_begin_resource_input(state, .Rename) do return .Unavailable
		return .Ok
	case "darek-move-node":
		if !module_begin_resource_input(state, .Move) do return .Unavailable
		return .Ok
	case "darek-copy-node":
		if !module_begin_resource_input(state, .Copy) do return .Unavailable
		return .Ok
	case "darek-delete-node":
		if !module_begin_resource_input(state, .Delete) do return .Unavailable
		return .Ok
	case "darek-copy-absolute-path", "darek-copy-name", "darek-copy-project-relative-path", "darek-copy-project-root":
		path, _, selected := module_selected_path(state)
		if !selected do return .Unavailable
		retained := path
		if name == "darek-copy-name" {
			retained = filepath.base(path)
		} else if name == "darek-copy-project-relative-path" || name == "darek-copy-project-root" {
			root, root_ok, _ := darek.instance_selected_project_root(&state.instance)
			if !root_ok || len(root.path) == 0 do return .Unavailable
			retained = root.path
			if name == "darek-copy-project-relative-path" {
				relative, relative_error := filepath.rel(root.path, path, state.temporary_allocator)
				if relative_error != nil do return .Unavailable
				defer delete(relative, state.temporary_allocator)
				if !module_retain_text(state, relative) do return .Failed
				module_diagnostic(state, "Copied Darek path")
				return module_publish(state)
			}
		}
		if !module_retain_text(state, retained) do return .Failed
		module_diagnostic(state, "Copied Darek path")
	case "darek-help":
		state.help_active = true
		state.input_mode = .Help
		module_diagnostic(state, "Darek help: darek-toggle-peek darek-next-node darek-previous-node darek-structure-action darek-visit-action darek-open darek-refresh darek-filter darek-hide darek-close")
	case "darek-help-advanced":
		state.help_active = true
		state.input_mode = .Help_Advanced
		module_diagnostic(state, "Darek advanced help: darek-toggle-file-follow darek-toggle-file-watch darek-toggle-hidden-files darek-toggle-vcs-ignored darek-select-sort darek-create-file darek-create-directory darek-rename-node darek-copy-absolute-path")
	case "darek-close":
		module_diagnostic(state, "Closed Darek")
		module_release(state)
		return .Ok
	case:
		return .Unavailable
	}
	if selection_changed {
		view, _, inspected, _ := darek.instance_inspect(&state.instance)
		if inspected && view.preview.enabled do _ = module_preview_selected(state)
	}
	_ = changed
	return module_publish(state)
}

@(private)
module_publish :: proc(state: ^Module_Instance) -> product_module.Status {
	if state == nil || !state.active do return .Unavailable
	if state.projection.state != nil do _ = darek.tree_projection_close(&state.projection)
	if built, _ := darek.tree_projection_build(&state.projection, &state.instance, state.allocator); !built {
		return .Failed
	}
	projection, viewed := darek.tree_projection_view(&state.projection)
	instance_view, _, inspected, _ := darek.instance_inspect(&state.instance)
	if !viewed || !inspected || len(projection.nodes) == 0 do return .Failed
	header_bytes := size_of(product_module.UI_Tree_Panel_Header)
	rows_bytes := len(projection.nodes) * size_of(product_module.UI_Tree_Panel_Row)
	text_bytes := 0
	for node in projection.nodes do text_bytes += len(node.text) + len(node.icon)
	if u64(header_bytes + rows_bytes + text_bytes) > product_module.MAX_CALL_BYTES do return .Limit
	request, allocation_error := make(
		[]u8, header_bytes + rows_bytes + text_bytes, state.temporary_allocator,
	)
	if allocation_error != nil do return .Failed
	defer delete(request, state.temporary_allocator)
	state.presentation_generation += 1
	if state.presentation_generation == 0 do state.presentation_generation = 1
	header := product_module.UI_Tree_Panel_Header {
		schema_version = product_module.UI_TREE_PANEL_SCHEMA_VERSION,
		row_count = u32(len(projection.nodes)),
		presentation_generation = state.presentation_generation,
		current_item = projection.current_node,
		first_visible_item = projection.first_visible,
		viewport_items = projection.viewport_nodes,
		panel_width = instance_view.panel.width,
		panel_edge = u8(instance_view.panel.side),
		visible = 1 if instance_view.visible else 0,
		focused = 1 if state.focused else 0,
		text_bytes = u64(text_bytes),
	}
	copy(request[:header_bytes], ([^]u8)(rawptr(&header))[:header_bytes])
	text_offset := 0
	for node, index in projection.nodes {
		row := product_module.UI_Tree_Panel_Row {
			id = u64(node.id),
			parent = u64(node.parent),
			text_offset = u64(text_offset),
			text_length = u32(len(node.text)),
			icon_offset = u32(text_offset + len(node.text)),
			icon_length = u16(len(node.icon)),
			depth = node.depth,
			indent_depth = node.indent_depth,
			expandable = 1 if node.expandable else 0,
			expanded = 1 if node.expanded else 0,
			icon_role = u8(node.icon_role),
			icon_style_role = u8(node.icon_style_role),
			action_owner_id = DAREK_MODULE_ACTION_OWNER,
			action_id = u64(node.id),
			action_generation = state.presentation_generation,
		}
		row_start := header_bytes + index * size_of(row)
		copy(request[row_start:row_start + size_of(row)], ([^]u8)(rawptr(&row))[:size_of(row)])
		content_start := header_bytes + rows_bytes + text_offset
		copy(request[content_start:], node.text)
		copy(request[content_start + len(node.text):], node.icon)
		text_offset += len(node.text) + len(node.icon)
	}
	status := state.host_call(
		state.capability, .Tree_UI, raw_data(request), u64(len(request)), nil, 0, nil,
	)
	return status
}

@(private)
module_deactivate :: proc(state: ^Module_Instance) -> product_module.Status {
	if state == nil do return .Invalid_Argument
	module_release(state)
	return .Ok
}

@(private)
module_close :: proc "c" (instance: u64) -> product_module.Status {
	context = runtime.default_context()
	if instance == 0 do return .Invalid_Argument
	state := (^Module_Instance)(uintptr(instance))
	module_release(state)
	free(state)
	return .Ok
}
