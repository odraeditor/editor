// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery_module

import "../command"
import "../display"
import "../interaction"
import "../product_module"
import "../ui"
import "base:runtime"
import "core:time"

/* Host_Context is the opaque public capability connection owned by one module instance. */
Host_Context :: struct {
	call:       product_module.Host_Call,
	capability: u64,
}

@(private)
App_Stage :: enum u8 {
	None,
	Command_Resolution,
	Session_Publish,
	Session_Access,
	Presentation,
	UI,
	Command_Dispatch,
	Prompt,
}

@(private)
App_Failure :: struct {
	stage:          App_Stage,
	host_status:    product_module.Status,
	prompt_failure: interaction.Prompt_Failure,
	interaction:    interaction.Failure_Context,
	ui:             ui.Failure,
}

@(private)
Interaction_Result :: struct {
	changed:          bool,
	deferred_command: interaction.Command_Handle,
}

@(private)
Prompt_Mode :: enum u8 {
	None,
	Ksawery_Discard_Choice,
}

@(private)
Prompt_Workflow_State :: struct {
	prompt:                interaction.Prompt,
	mode:                  Prompt_Mode,
	projection_generation: ui.Model_Generation,
	next_projection_generation: ui.Model_Generation,
	focus_captured:        bool,
}

@(private)
Personal_Configuration_Result :: enum u8 {
	Invalid,
	Confirmed,
	Rejected,
}

@(private)
Personal_Configuration_Startup_State :: struct {
	status:               Personal_Configuration_Result,
	confirmed_generation: u64,
	rejected_generation:  u64,
	diagnostic_length:    int,
}

@(private)
Command_Context :: struct {
	host:                   Host_Context,
	ksawery_workflow:       ^Ksawery_Workflow_State,
	persistent_allocator:   runtime.Allocator,
	temporary_allocator:    runtime.Allocator,
	prompt_workflow:        Prompt_Workflow_State,
	personal_configuration: Personal_Configuration_Startup_State,
	grouping_started:       time.Tick,
}

@(private)
host_session_request :: proc(
	host: ^Host_Context,
	action: product_module.Session_Action,
	target: u64,
	flags: u64,
	payload: string,
) -> (product_module.Session_Response, bool) {
	if host == nil || host.call == nil || host.capability == 0 || action == .Invalid ||
	   u64(len(payload)) > product_module.MAX_CALL_BYTES {
		return {}, false
	}
	header := product_module.Session_Request_Header {
		schema_version = product_module.SESSION_REQUEST_SCHEMA_VERSION,
		action = action,
		target = target,
		flags = flags,
		payload_length = u64(len(payload)),
	}
	request_length := size_of(header) + len(payload)
	request, allocation_error := make([]u8, request_length, context.temp_allocator)
	if allocation_error != nil do return {}, false
	defer delete(request, context.temp_allocator)
	header_bytes := ([^]u8)(rawptr(&header))[:size_of(header)]
	copy(request[:size_of(header)], header_bytes)
	copy(request[size_of(header):], payload)
	response: product_module.Session_Response
	response_bytes := ([^]u8)(rawptr(&response))[:size_of(response)]
	written: u64
	status := host.call(
		host.capability,
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
host_command_request :: proc(
	host: ^Host_Context,
	action: product_module.Command_Action,
	payload: string,
) -> bool {
	if host == nil || host.call == nil || host.capability == 0 || action == .Invalid ||
	   u64(len(payload)) > product_module.MAX_CALL_BYTES {
		return false
	}
	header := product_module.Command_Request_Header {
		schema_version = product_module.COMMAND_REQUEST_SCHEMA_VERSION,
		action = action,
		payload_length = u64(len(payload)),
	}
	request_length := size_of(header) + len(payload)
	request, allocation_error := make([]u8, request_length, context.temp_allocator)
	if allocation_error != nil do return false
	defer delete(request, context.temp_allocator)
	header_bytes := ([^]u8)(rawptr(&header))[:size_of(header)]
	copy(request[:size_of(header)], header_bytes)
	copy(request[size_of(header):], payload)
	status := host.call(
		host.capability,
		.Command,
		raw_data(request),
		u64(len(request)),
		nil,
		0,
		nil,
	)
	return status == .Ok
}

@(private)
host_provider_invoke :: proc(
	host: ^Host_Context,
	service: string,
	provider_generation: u64,
	operation: u64,
	name: string,
	payload: []u8,
	output: []u8,
) -> (written: u64, ok: bool) {
	if host == nil || host.call == nil || host.capability == 0 || len(service) == 0 ||
	   u64(len(payload)) > product_module.MAX_CALL_BYTES {
		return 0, false
	}
	header := product_module.Provider_Request_Header {
		schema_version = product_module.PROVIDER_REQUEST_SCHEMA_VERSION,
		provider_generation = provider_generation,
		operation = operation,
		service_length = u32(len(service)),
		name_length = u32(len(name)),
		payload_length = u64(len(payload)),
	}
	request_length := size_of(header) + len(service) + len(name) + len(payload)
	if u64(request_length) > product_module.MAX_CALL_BYTES do return 0, false
	request, allocation_error := make([]u8, request_length, context.temp_allocator)
	if allocation_error != nil do return 0, false
	defer delete(request, context.temp_allocator)
	header_bytes := ([^]u8)(rawptr(&header))[:size_of(header)]
	copy(request[:size_of(header)], header_bytes)
	cursor := size_of(header)
	cursor += copy(request[cursor:], service)
	cursor += copy(request[cursor:], name)
	cursor += copy(request[cursor:], payload)
	assert(cursor == len(request))
	status := host.call(
		host.capability,
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
command_context_set_diagnostic :: proc(commands: ^Command_Context, message: string) {
	if commands == nil || commands.host.call == nil || commands.host.capability == 0 do return
	if commands.ksawery_workflow != nil {
		state := commands.ksawery_workflow
		state.diagnostic_length = u16(copy(state.diagnostic[:], message))
	}
	bytes := transmute([]u8)message
	_ = commands.host.call(
		commands.host.capability,
		.Diagnostic,
		raw_data(bytes),
		u64(len(bytes)),
		nil,
		0,
		nil,
	)
}

@(private)
command_context_reload_personal_commands :: proc(
	commands: ^Command_Context,
) -> (Interaction_Result, App_Failure) {
	if commands == nil || commands.host.call == nil do return {}, {stage = .Command_Dispatch}
	if !host_command_request(&commands.host, .Reload, "") do return {}, {stage = .Command_Dispatch}
	return {changed = true}, {}
}

@(private)
pointer_text_capture_clear :: proc(commands: ^Command_Context) {
	if commands == nil || commands.host.call == nil do return
	_ = commands.host.call(commands.host.capability, .UI, nil, 0, nil, 0, nil)
}

@(private)
prompt_yes_no_choices :: proc() -> [2]interaction.Prompt_Choice_Definition {
	return {
		{name = "[y]es", command_name = "prompt-choice-1"},
		{name = "[n]o", command_name = "prompt-choice-2"},
	}
}

@(private)
prompt_workflow_begin_projection :: proc(state: ^Prompt_Workflow_State, mode: Prompt_Mode) -> bool {
	if state == nil || mode == .None || state.mode != .None do return false
	state.mode = mode
	state.next_projection_generation += 1
	state.projection_generation = state.next_projection_generation
	return true
}

@(private)
command_context_activate_prompt_map :: proc(
	commands: ^Command_Context,
	mode: Prompt_Mode,
) -> App_Failure {
	if commands == nil || mode == .None || commands.host.call == nil {
		return {stage = .Prompt}
	}
	status := commands.host.call(commands.host.capability, .Prompt, nil, 0, nil, 0, nil)
	if status != .Ok do return {stage = .Prompt}
	return {}
}

@(private)
command_context_end_prompt :: proc(commands: ^Command_Context) {
	if commands == nil do return
	if commands.prompt_workflow.prompt.state != nil {
		_, _ = interaction.prompt_close(&commands.prompt_workflow.prompt)
	}
	commands.prompt_workflow.mode = .None
	commands.prompt_workflow.focus_captured = false
	commands.prompt_workflow.projection_generation = 0
}

@(private)
command_context_resolve_prompt_input :: proc(
	commands: ^Command_Context,
	input: interaction.Input,
) -> (metadata: interaction.Command_Metadata, resolution: interaction.Resolution, ok: bool, failure: App_Failure) {
	if commands == nil do return {}, {}, false, {stage = .Prompt}
	route := command.Contextual_Route.Invalid
	choice: rune
	if input.kind == .Text_Commit && len(input.text) == 1 {
		choice = rune(input.text[0])
	} else if input.kind == .Key && input.stroke.kind == .Unicode_Scalar {
		choice = input.stroke.scalar
	}
	if choice != 0 {
		switch choice {
		case 'y', 'Y': route = .Prompt_Choice_1
		case 'n', 'N': route = .Prompt_Choice_2
		}
	} else if input.kind == .Key && input.stroke.kind == .Escape {
		route = .Cancel
	}
	if route == .Invalid do return {}, {kind = .Rejected}, true, {}
	metadata.route = command.contextual_route(route)
	resolution.kind = .Command
	resolution.command = metadata.handle
	return metadata, resolution, true, {}
}

@(private)
command_metadata_is_contextual :: proc(
	metadata: interaction.Command_Metadata,
	route: command.Contextual_Route,
) -> bool {
	decoded, ok := command.contextual_route_decode(metadata.route)
	return ok && decoded == route
}

@(private)
command_metadata_is_cancel :: proc(metadata: interaction.Command_Metadata) -> bool {
	return command_metadata_is_contextual(metadata, .Cancel)
}

@(private)
command_context_deactivate_prompt_map :: proc(
	commands: ^Command_Context,
	_: interaction.Context_Map_End,
) {
	if commands == nil do return
}

@(private)
transient_input_content_rows :: proc(
	_: ^Command_Context,
	constraints: display.Viewport_Constraints,
) -> (u32, bool) {
	return constraints.height_rows, constraints.height_rows > 0
}

@(private)
List_Context_Kind :: enum u8 {
	Invalid,
	Ksawery_Status,
}

@(private)
command_context_sync_list_map :: proc(
	commands: ^Command_Context,
	kind: List_Context_Kind,
) -> App_Failure {
	if commands == nil || kind != .Ksawery_Status do return {stage = .Command_Resolution}
	return {}
}

@(private)
command_context_resolve_context_input :: proc(
	commands: ^Command_Context,
	input: interaction.Input,
) -> (metadata: interaction.Command_Metadata, resolution: interaction.Resolution, ok: bool, failure: App_Failure) {
	if commands == nil do return {}, {}, false, {stage = .Command_Resolution}
	if input.kind == .Key && input.stroke.kind == .Unicode_Scalar {
		if input.stroke.scalar == 'x' && input.stroke.modifiers == {.Meta} {
			metadata.route = command.native_route(.Execute_Extended_Command)
			resolution.kind = .Command
			return metadata, resolution, true, {}
		}
		if input.stroke.scalar == 'g' && input.stroke.modifiers == {.Control} {
			metadata.route = command.native_route(.Keyboard_Quit)
			resolution.kind = .Command
			return metadata, resolution, true, {}
		}
	}
	route := ksawery_input_route(input)
	if route == .Invalid do return {}, {kind = .Unbound}, true, {}
	metadata.route = command.contextual_route(route)
	resolution.kind = .Command
	resolution.command = metadata.handle
	return metadata, resolution, true, {}
}

@(private)
command_context_deactivate_context_map :: proc(
	_: ^Command_Context,
	_: interaction.Context_Map_End,
) {}

@(private)
command_context_publish_ksawery_list :: proc(
	commands: ^Command_Context,
	definitions: []ui.List_Item_Definition,
	_: []u8,
	_: display.Viewport_Constraints,
	position: ui.List_View_Position,
) -> App_Failure {
	if commands == nil || commands.host.call == nil || len(definitions) == 0 ||
	   len(definitions) > int(max(u32)) {
		return {stage = .UI}
	}
	text_bytes: u64
	mark_lane := false
	for definition in definitions {
		if u64(len(definition.text)) > product_module.MAX_CALL_BYTES - text_bytes {
			return {stage = .UI, host_status = .Limit}
		}
		text_bytes += u64(len(definition.text))
		mark_lane = mark_lane || definition.mark != .None
	}
	row_bytes := u64(len(definitions)) * u64(size_of(product_module.UI_List_Row))
	header_bytes := u64(size_of(product_module.UI_List_Header))
	if row_bytes > product_module.MAX_CALL_BYTES - header_bytes ||
	   text_bytes > product_module.MAX_CALL_BYTES - header_bytes - row_bytes {
		return {stage = .UI, host_status = .Limit}
	}
	request, allocation_error := make(
		[]u8,
		int(header_bytes + row_bytes + text_bytes),
		commands.temporary_allocator,
	)
	if allocation_error != nil do return {stage = .UI, host_status = .Failed}
	defer delete(request, commands.temporary_allocator)
	header := product_module.UI_List_Header {
		schema_version = product_module.UI_LIST_SCHEMA_VERSION,
		row_count = u32(len(definitions)),
		presentation_generation = position.presentation_generation,
		current_item = position.current_item,
		first_visible_item = position.first_visible_item,
		viewport_items = position.viewport_items,
		selection_owner = u8(position.selection_owner),
		mark_lane = 1 if mark_lane else 0,
		text_bytes = text_bytes,
	}
	copy(request[:int(header_bytes)], ([^]u8)(rawptr(&header))[:int(header_bytes)])
	text_offset := u64(0)
	for definition, index in definitions {
		row: product_module.UI_List_Row
		row.id = u64(definition.id)
		row.text_offset = text_offset
		row.text_length = u32(len(definition.text))
		row.emphasis_bytes = definition.emphasis_bytes
		row.action_owner_id = u64(definition.action.owner_id)
		row.action_id = u64(definition.action.action_id)
		row.action_generation = definition.action.generation
		row.icon_role = u8(definition.icon_role)
		row.icon_style_role = u8(definition.icon_style_role)
		row.mark = u8(definition.mark)
		row.passive = 1 if definition.passive else 0
		row.emphasis_style = u8(definition.emphasis_style)
		row.style_span_count = definition.style_span_count
		for span_index in 0 ..< int(definition.style_span_count) {
			span := definition.style_spans[span_index]
			row.style_spans[span_index] = {
				start_byte = span.start_byte,
				end_byte = span.end_byte,
				style_role = u8(span.style_role),
			}
		}
		row_start := int(header_bytes) + index * size_of(product_module.UI_List_Row)
		row_end := row_start + size_of(product_module.UI_List_Row)
		copy(request[row_start:row_end], ([^]u8)(rawptr(&row))[:size_of(row)])
		content_start := int(header_bytes + row_bytes + text_offset)
		copy(request[content_start:], transmute([]u8)definition.text)
		text_offset += u64(len(definition.text))
	}
	status := commands.host.call(
		commands.host.capability, .UI,
		raw_data(request), u64(len(request)), nil, 0, nil,
	)
	if status != .Ok do return {stage = .UI, host_status = status}
	return {}
}

@(private)
ksawery_input_route :: proc(input: interaction.Input) -> command.Contextual_Route {
	if input.kind != .Key do return .Invalid
	if input.stroke.modifiers != {} do return .Invalid
	if input.stroke.kind == .Up do return .Component_Previous_Row
	if input.stroke.kind == .Down do return .Component_Next_Row
	if input.stroke.kind == .Tab do return .Component_Complete_Current
	if input.stroke.kind == .Enter do return .Component_Activate_Current
	if input.stroke.kind != .Unicode_Scalar do return .Invalid
	switch input.stroke.scalar {
	case 'q': return .Component_Close
	case 'g': return .Result_Refresh
	case '*': return .Ksawery_Mark
	case '-': return .Ksawery_Unmark
	case '0': return .Ksawery_Clear_Marks
	case 's': return .Ksawery_Stage
	case 'u': return .Ksawery_Unstage
	case 'k': return .Ksawery_Discard
	case 'c': return .Ksawery_Commit
	case 'A': return .Ksawery_Amend
	case 'F': return .Ksawery_Fixup
	case 'o': return .Ksawery_Sequence
	case 'h': return .Ksawery_History
	case 'f': return .Ksawery_History_Next
	case 'b': return .Ksawery_Refs
	case '$': return .Ksawery_Processes
	case 'v': return .Ksawery_Providers
	case 'L': return .Ksawery_Provider_Reload
	case 'z': return .Ksawery_Provider_Disable
	case '!': return .Ksawery_Raw_Command
	case '&': return .Ksawery_Fetch
	case 'p': return .Ksawery_Push
	case 'n': return .Ksawery_Branch_Create
	case 'S': return .Ksawery_Branch_Switch
	case 'R': return .Ksawery_Branch_Rename
	case 'D': return .Ksawery_Branch_Delete
	case 't': return .Ksawery_Tag_Create
	case 'T': return .Ksawery_Tag_Delete
	case '=': return .Ksawery_Merge_Fast_Forward
	case 'i': return .Ksawery_Merge
	case 'I': return .Ksawery_Merge_No_Fast_Forward
	case '>': return .Ksawery_Merge_Continue
	case 'X': return .Ksawery_Merge_Abort
	case 'e': return .Ksawery_Rebase
	case ']': return .Ksawery_Rebase_Continue
	case ';': return .Ksawery_Rebase_Skip
	case 'Z': return .Ksawery_Rebase_Abort
	case 'a': return .Ksawery_Sequence_Mark
	case 'U': return .Ksawery_Sequence_Unmark
	case 'P': return .Ksawery_Cherry_Pick
	case '{': return .Ksawery_Cherry_Pick_Continue
	case 'l': return .Ksawery_Cherry_Pick_Skip
	case 'Y': return .Ksawery_Cherry_Pick_Abort
	case 'V': return .Ksawery_Revert
	case '}': return .Ksawery_Revert_Continue
	case 'j': return .Ksawery_Revert_Skip
	case 'Q': return .Ksawery_Revert_Abort
	case 'G': return .Ksawery_Bisect_Good
	case 'B': return .Ksawery_Bisect_Bad
	case '?': return .Ksawery_Bisect_Start
	case '|': return .Ksawery_Bisect_Skip
	case '~': return .Ksawery_Bisect_Reset
	case 'x': return .Ksawery_Conflict_Mark
	case 'H': return .Ksawery_Conflict_Assist
	case '1': return .Ksawery_Conflict_Use_Base
	case '2': return .Ksawery_Conflict_Use_Current
	case '3': return .Ksawery_Conflict_Use_Applied
	case 'K': return .Ksawery_Conflict_Delete
	}
	return .Invalid
}
