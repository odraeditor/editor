// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../command"
import "../display"
import "../editor"
import "../interaction"
import "../search"
import editor_view "../view"
import "base:runtime"
import "core:strings"

@(private)
command_context_modal_operator_begin_search :: proc(
	commands: ^Command_Context,
	operation: interaction.Modal_Operator_Result,
) -> (Interaction_Result, App_Failure) {
	direction := search.Direction.Forward
	if operation.target == .Search_Backward do direction = .Backward
	if commands.profile_activation == nil ||
	   !interaction.profile_activation_modal_operator_execution_begin(
		commands.profile_activation,
		operation,
	) {
		return {}, App_Failure{stage = .Command_Dispatch}
	}
	result, failure := command_context_begin_search(commands, direction, .Literal)
	if failure.stage != .None do interaction.profile_activation_modal_operator_execution_clear(commands.profile_activation)
	return result, failure
}

@(private)
command_context_modal_operator_defer_search :: proc(
	commands: ^Command_Context,
	buffer: ^editor.Buffer,
	view_registry: ^editor_view.Registry,
	view: editor_view.View_Handle,
) -> (Interaction_Result, App_Failure) {
	if commands.profile_activation == nil do return Interaction_Result{changed = true}, {}
	workflow, active := interaction.profile_activation_modal_operator_execution_inspect(
		commands.profile_activation,
	)
	if !active || !workflow.active do return Interaction_Result{changed = true}, {}
	logical, viewed, view_failure := editor_view.snapshot(view_registry, view)
	if !viewed {
		interaction.profile_activation_modal_operator_execution_clear(commands.profile_activation)
		return {}, App_Failure{stage = .Command_Dispatch, view = view_failure}
	}
	operation := workflow.operation
	if operation.capture.buffer_identity != u64(logical.buffer_id) ||
	   operation.capture.buffer_revision != u64(logical.revision) {
		interaction.profile_activation_modal_operator_execution_clear(commands.profile_activation)
		return {}, App_Failure{stage = .Command_Dispatch, interaction = {code = .Stale_Context}}
	}
	origin, origin_ok, origin_failure := editor.buffer_position(
		buffer,
		editor.Byte_Offset(operation.capture.point_offset),
	)
	if !origin_ok {
		interaction.profile_activation_modal_operator_execution_clear(commands.profile_activation)
		return {}, App_Failure{stage = .Command_Dispatch, editor = origin_failure}
	}
	target := logical.point_position
	if target.byte_offset == origin.byte_offset {
		interaction.profile_activation_modal_operator_execution_clear(commands.profile_activation)
		command_context_set_diagnostic(commands, "Modal operator search target unavailable")
		return Interaction_Result{changed = true}, {}
	}
	start := origin
	end := target
	if start.byte_offset > end.byte_offset do start, end = end, start
	command_name, named := command_context_modal_operator_command(operation.operator)
	if !named {
		interaction.profile_activation_modal_operator_execution_clear(commands.profile_activation)
		command_context_set_diagnostic(commands, "Modal operator is unavailable")
		return Interaction_Result{changed = true}, {}
	}
	handle, found, lookup_failure := interaction.command_lookup(commands.registry, command_name)
	if !found {
		interaction.profile_activation_modal_operator_execution_clear(commands.profile_activation)
		return {}, App_Failure{stage = .Command_Resolution, interaction = lookup_failure}
	}
	deferred := interaction.profile_activation_modal_operator_execution_defer(
		commands.profile_activation,
		u64(start.byte_offset),
		u64(end.byte_offset),
		origin.byte_offset > target.byte_offset,
	)
	if !deferred do return {}, App_Failure{stage = .Command_Dispatch}
	return Interaction_Result{changed = true, deferred_command = handle}, {}
}

@(private)
command_context_modal_operator_deferred :: proc(
	commands: ^Command_Context,
	buffer: ^editor.Buffer,
) -> (
	operation: interaction.Modal_Operator_Result,
	explicit: command.Native_Explicit_Range,
	ready: bool,
	failure: App_Failure,
) {
	if commands.profile_activation == nil do return {}, {}, false, {}
	execution, inspected := interaction.profile_activation_modal_operator_execution_inspect(
		commands.profile_activation,
	)
	if !inspected || !execution.deferred do return {}, {}, false, {}
	stats, stats_ok, stats_failure := editor.buffer_stats(buffer)
	if !stats_ok {
		interaction.profile_activation_modal_operator_execution_clear(commands.profile_activation)
		return {}, {}, false, App_Failure{stage = .Command_Dispatch, editor = stats_failure}
	}
	if execution.operation.capture.buffer_identity != u64(stats.buffer_id) ||
	   execution.operation.capture.buffer_revision != u64(stats.revision) {
		interaction.profile_activation_modal_operator_execution_clear(commands.profile_activation)
		return {}, {}, false, App_Failure {
			stage = .Command_Dispatch,
			interaction = {code = .Stale_Context},
		}
	}
	start, start_ok, start_failure := editor.buffer_position(
		buffer,
		editor.Byte_Offset(execution.start_offset),
	)
	if !start_ok {
		interaction.profile_activation_modal_operator_execution_clear(commands.profile_activation)
		return {}, {}, false, App_Failure{stage = .Command_Dispatch, editor = start_failure}
	}
	end, end_ok, end_failure := editor.buffer_position(
		buffer,
		editor.Byte_Offset(execution.end_offset),
	)
	if !end_ok {
		interaction.profile_activation_modal_operator_execution_clear(commands.profile_activation)
		return {}, {}, false, App_Failure{stage = .Command_Dispatch, editor = end_failure}
	}
	return execution.operation, command.Native_Explicit_Range {
		present = true,
		start = start,
		end = end,
		backward = execution.backward,
	}, true, {}
}

@(private)
command_context_modal_operator_request :: proc(
	request: interaction.Modal_Navigation_Request,
) -> interaction.Modal_Operator_Request {
	return interaction.Modal_Operator_Request {
		profile = request.profile,
		state = request.state,
		catalog_generation = request.catalog_generation,
		snapshot_generation = request.snapshot_generation,
		ctx = request.ctx,
		view_identity = request.view_identity,
		view_generation = request.view_generation,
		buffer_identity = request.buffer_identity,
		buffer_revision = request.buffer_revision,
		point_offset = request.point_offset,
		input = request.input,
	}
}

@(private)
command_context_modal_operator_command :: proc(
	operator: interaction.Modal_Operator_Kind,
) -> (string, bool) {
	switch operator {
	case .Delete, .Change: return "kill-region", true
	case .Yank:            return "copy-region", true
	case .Replace:         return "replace-region-text", true
	case .Indent:  return "indent-lines", true
	case .Outdent: return "outdent-lines", true
	case .None:    return "", false
	}
	unreachable()
}

@(private)
command_context_modal_named_slot_text :: proc(
	commands: ^Command_Context,
	operation: interaction.Modal_Operator_Result,
) -> (text: []u8, ready: bool, failure: App_Failure) {
	captured := operation
	name := interaction.modal_operator_result_named_slot(&captured)
	if len(name) == 0 do return nil, false, {}
	batch, found, lookup_failure := command.named_slot_lookup_text(
		commands.racket_runtime,
		commands.lifecycle_configuration_root,
		name,
		commands.temporary_allocator,
	)
	_ = lookup_failure
	if !found {
		if batch.state != nil do command.named_slot_batch_close(&batch)
		return nil, false, {}
	}
	defer command.named_slot_batch_close(&batch)
	if len(batch.slots) != 1 || batch.slots[0].kind != .Text do return nil, false, {}
	value := batch.slots[0].text
	if len(value) == 0 || operation.count == 0 ||
	   operation.count > u64(command.MAX_NAMED_SLOT_TEXT_BYTES) / u64(len(value)) {
		return nil, false, {}
	}
	bytes := u64(len(value)) * operation.count
	allocation_error: runtime.Allocator_Error
	text, allocation_error = make([]u8, int(bytes), commands.temporary_allocator)
	if allocation_error != nil do return nil, false, App_Failure{stage = .Component_Access}
	for index in 0 ..< int(operation.count) {
		copy(text[index * len(value):], transmute([]u8)value)
	}
	return text, true, {}
}

@(private)
command_context_modal_named_slot_store :: proc(
	commands: ^Command_Context,
	buffer: ^editor.Buffer,
	operation: interaction.Modal_Operator_Result,
	explicit: command.Native_Explicit_Range,
	command_handle: interaction.Command_Handle,
) -> (result: Interaction_Result, execute: bool, handled: bool, failure: App_Failure) {
	if commands == nil || buffer == nil || commands.profile_activation == nil ||
	   commands.racket_runtime == nil || len(commands.lifecycle_configuration_root) == 0 ||
	   !explicit.present || explicit.start.byte_offset >= explicit.end.byte_offset {
		return {}, false, false, App_Failure{stage = .Component_Access}
	}
	captured := operation
	name := interaction.modal_operator_result_named_slot(&captured)
	if len(name) == 0 do return {}, true, false, {}
	length := u64(explicit.end.byte_offset) - u64(explicit.start.byte_offset)
	if length == 0 || length > command.MAX_NAMED_SLOT_TEXT_BYTES {
		command_context_set_diagnostic(commands, "Named text slot value exceeds its limit")
		return Interaction_Result{changed = true}, false, true, {}
	}
	bytes, allocation_error := make([]byte, int(length), commands.persistent_allocator)
	if allocation_error != nil do return {}, false, false, App_Failure{stage = .Component_Access}
	value := string(bytes)
	keep_value := false
	defer if !keep_value do delete(bytes, commands.persistent_allocator)
	_, inspected, inspect_failure := editor.buffer_inspect(
		buffer,
		explicit.start.byte_offset,
		explicit.end.byte_offset,
		bytes,
	)
	if !inspected do return {}, false, false, App_Failure{stage = .Command_Dispatch, editor = inspect_failure}

	listed, listed_ok, list_failure := command.named_slots_list(
		commands.racket_runtime,
		commands.lifecycle_configuration_root,
		commands.temporary_allocator,
	)
	if !listed_ok {
		if listed.state != nil do command.named_slot_batch_close(&listed)
		return {}, false, false, App_Failure{stage = .Command_Dispatch, command = list_failure}
	}
	defer command.named_slot_batch_close(&listed)
	found := false
	kind := command.Named_Slot_Kind.Invalid
	for slot in listed.slots {
		if slot.name == name {
			found = true
			kind = slot.kind
			break
		}
	}
	if !found {
		command_context_set_diagnostic(commands, "Named text slot not found")
		return Interaction_Result{changed = true}, false, true, {}
	}
	if kind == .Text {
		stored, stored_ok, store_failure := command.named_slot_store_text(
			commands.racket_runtime,
			commands.lifecycle_configuration_root,
			name,
			value,
			false,
			commands.temporary_allocator,
		)
		if stored.state != nil do command.named_slot_batch_close(&stored)
		if !stored_ok {
			return {}, false, false, App_Failure{stage = .Command_Dispatch, command = store_failure}
		}
		return {}, true, false, {}
	}

	named_slot_workflow_reset(&commands.named_slot_workflow)
	state := &commands.named_slot_workflow
	state.operation = .Modal_Store_Text
	state.phase = .Confirm_Replacement
	state.command_handle = command_handle
	state.value = value
	state.allocator = commands.persistent_allocator
	state.region_entry = commands.current_entry
	name_copy, name_error := strings.clone(name, state.allocator)
	if name_error != nil {
		named_slot_workflow_reset(state)
		return {}, false, false, App_Failure{stage = .Component_Access}
	}
	state.name = name_copy
	keep_value = true
	if !interaction.profile_activation_modal_operator_execution_begin(
		commands.profile_activation,
		operation,
	) || !interaction.profile_activation_modal_operator_execution_defer(
		commands.profile_activation,
		u64(explicit.start.byte_offset),
		u64(explicit.end.byte_offset),
		explicit.backward,
	) || !interaction.profile_activation_modal_operator_execution_slot_generation_set(
		commands.profile_activation,
		listed.generation,
	) {
		named_slot_workflow_reset(state)
		interaction.profile_activation_modal_operator_execution_clear(commands.profile_activation)
		return {}, false, false, App_Failure{stage = .Command_Dispatch}
	}
	prompt_failure: App_Failure
	result, prompt_failure = command_context_begin_named_slot_prompt(
		commands,
		.Named_Slot_Confirmation,
		.Fixed_Choice,
		0,
		false,
	)
	if prompt_failure.stage != .None {
		named_slot_workflow_reset(state)
		interaction.profile_activation_modal_operator_execution_clear(commands.profile_activation)
		return {}, false, false, prompt_failure
	}
	return result, false, true, {}
}

@(private)
command_context_modal_operator_range :: proc(
	buffer: ^editor.Buffer,
	view_registry: ^editor_view.Registry,
	view: editor_view.View_Handle,
	operation: interaction.Modal_Operator_Result,
	profile: display.Display_Profile,
	constraints: display.Viewport_Constraints,
) -> (explicit: command.Native_Explicit_Range, ready: bool, failure: App_Failure) {
	logical, viewed, view_failure := editor_view.snapshot(view_registry, view)
	if !viewed do return {}, false, App_Failure{stage = .Command_Dispatch, view = view_failure}
	if operation.capture.view_identity != u64(logical.view_id) ||
	   operation.capture.view_generation != logical.view_generation ||
	   operation.capture.buffer_identity != u64(logical.buffer_id) ||
	   operation.capture.buffer_revision != u64(logical.revision) {
		return {}, false, App_Failure {
			stage = .Command_Dispatch,
			interaction = {code = .Stale_Context},
		}
	}
	if operation.count == 0 || operation.count > interaction.MAX_MODAL_COUNT {
		return {}, false, App_Failure {
			stage = .Command_Dispatch,
			interaction = {
				code = .Invalid_Input,
				limit = interaction.MAX_MODAL_COUNT,
				actual = operation.count,
			},
		}
	}
	origin, origin_ok, origin_failure := editor.buffer_position(
		buffer,
		editor.Byte_Offset(operation.capture.point_offset),
	)
	if !origin_ok do return {}, false, App_Failure{stage = .Command_Dispatch, editor = origin_failure}
	start := origin
	end := origin
	switch operation.target {
	case .Active_Selection:
		if !logical.region_active || !logical.mark.present do return {}, false, {}
		start = logical.mark.position
		end = logical.point_position
		if start.byte_offset > end.byte_offset do start, end = end, start
	case .Line:
		target := origin
		if operation.count > 1 {
			target, ready, failure = modal_operator_repeated_navigation(
				buffer, logical, .Next_Line, operation.count - 1, profile,
			)
			if failure.stage != .None || !ready do return {}, ready, failure
		}
		start, end, ready, failure = modal_operator_line_range(buffer, origin, target)
		if failure.stage != .None || !ready do return {}, ready, failure
	case .Inner_Word, .Around_Word:
		range, found, selected, range_failure := display.word_selection_range(
			buffer, logical, profile,
		)
		if !selected do return {}, false, App_Failure{stage = .Command_Dispatch, display = range_failure}
		if !found do return {}, false, {}
		start = range.start
		end = range.end
	case .Inner_Paragraph, .Around_Paragraph:
		range, selected, range_failure := display.paragraph_selection_range(buffer, logical)
		if !selected do return {}, false, App_Failure{stage = .Command_Dispatch, display = range_failure}
		start = range.start
		end = range.end
	case .Character_Target, .Repeat_Character_Target:
		kind, kind_ok := modal_operator_character_target(operation.character_target)
		if !kind_ok do return {}, false, {}
		captured := operation
		target, _, found, resolved, target_failure := display.line_character_navigation_target(
			buffer,
			logical,
			interaction.modal_operator_result_text(&captured),
			kind,
			operation.count,
			profile,
		)
		if !resolved do return {}, false, App_Failure{stage = .Command_Dispatch, display = target_failure}
		if !found do return {}, false, {}
		start, end = modal_operator_character_range(origin, target)
	case .Previous_Page, .Next_Page:
		if constraints.height_rows <= 1 do return {}, false, {}
		rows := u64(constraints.height_rows - 1)
		steps := rows * operation.count
		if rows == 0 || steps / rows != operation.count {
			return {}, false, App_Failure {
				stage = .Command_Dispatch,
				interaction = {code = .Sequence_Limit, limit = interaction.MAX_MODAL_COUNT, actual = operation.count},
			}
		}
		kind := display.Navigation_Kind.Previous_Line
		if operation.target == .Next_Page do kind = .Next_Line
		target, resolved, target_failure := modal_operator_repeated_navigation(
			buffer, logical, kind, steps, profile,
		)
		if target_failure.stage != .None || !resolved do return {}, resolved, target_failure
		start, end, ready, failure = modal_operator_line_range(buffer, origin, target)
		if failure.stage != .None || !ready do return {}, ready, failure
	case .Previous_Line, .Next_Line, .Buffer_Start, .Buffer_End:
		kind, kind_ok := modal_operator_navigation_kind(operation.target)
		if !kind_ok do return {}, false, {}
		target, resolved, target_failure := modal_operator_repeated_navigation(
			buffer, logical, kind, operation.count, profile,
		)
		if target_failure.stage != .None || !resolved do return {}, resolved, target_failure
		start, end, ready, failure = modal_operator_line_range(buffer, origin, target)
		if failure.stage != .None || !ready do return {}, ready, failure
	case .Search_Forward, .Search_Backward, .Search_Next, .Search_Previous,
	     .Named_Slot_Before, .Named_Slot_After:
		return {}, false, {}
	case .Previous_Grapheme, .Next_Grapheme, .Line_Start, .Line_End,
	     .Line_First_Non_Whitespace, .Previous_Word, .Next_Word_Start, .Word_End:
		kind, kind_ok := modal_operator_navigation_kind(operation.target)
		if !kind_ok do return {}, false, {}
		target, resolved, target_failure := modal_operator_repeated_navigation(
			buffer, logical, kind, operation.count, profile,
		)
		if target_failure.stage != .None || !resolved do return {}, resolved, target_failure
		start = origin
		end = target
		if start.byte_offset > end.byte_offset do start, end = end, start
	case .None:
		return {}, false, {}
	}
	if start.byte_offset == end.byte_offset do return {}, false, {}
	return command.Native_Explicit_Range {
		present = true,
		start = start,
		end = end,
		backward = logical.point_position.byte_offset > start.byte_offset,
	}, true, {}
}

@(private)
modal_operator_repeated_navigation :: proc(
	buffer: ^editor.Buffer,
	logical: editor_view.Snapshot,
	kind: display.Navigation_Kind,
	count: u64,
	profile: display.Display_Profile,
) -> (target: editor.Position, ready: bool, failure: App_Failure) {
	target = logical.point_position
	probe := logical
	for _ in 0 ..< count {
		next, desired, resolved, target_failure := display.navigation_target(
			buffer, probe, kind, profile,
		)
		if !resolved {
			return {}, false, App_Failure{stage = .Command_Dispatch, display = target_failure}
		}
		if next == target do break
		target = next
		probe.point_position = next
		probe.desired_display_column = desired
	}
	return target, target != logical.point_position, {}
}

@(private)
modal_operator_line_range :: proc(
	buffer: ^editor.Buffer,
	first, second: editor.Position,
) -> (start, end: editor.Position, ready: bool, failure: App_Failure) {
	first_line, first_ok, first_failure := editor.buffer_line_at_position(buffer, first)
	if !first_ok do return {}, {}, false, App_Failure{stage = .Command_Dispatch, editor = first_failure}
	second_line, second_ok, second_failure := editor.buffer_line_at_position(buffer, second)
	if !second_ok do return {}, {}, false, App_Failure{stage = .Command_Dispatch, editor = second_failure}
	start_offset := first_line.start
	end_offset := second_line.next_start
	if first_line.line_index > second_line.line_index {
		start_offset = second_line.start
		end_offset = first_line.next_start
	}
	start_ok: bool
	start_failure: editor.Failure_Context
	start, start_ok, start_failure = editor.buffer_position(buffer, start_offset)
	if !start_ok do return {}, {}, false, App_Failure{stage = .Command_Dispatch, editor = start_failure}
	end_ok: bool
	end_failure: editor.Failure_Context
	end, end_ok, end_failure = editor.buffer_position(buffer, end_offset)
	if !end_ok do return {}, {}, false, App_Failure{stage = .Command_Dispatch, editor = end_failure}
	return start, end, start.byte_offset < end.byte_offset, {}
}

@(private)
modal_operator_character_range :: proc(
origin, target: editor.Position,
) -> (start, end: editor.Position) {
	start = origin
	end = target
	if start.byte_offset > end.byte_offset do start, end = end, start
	return
}

@(private)
modal_operator_navigation_kind :: proc(
	target: interaction.Modal_Operator_Target_Kind,
) -> (display.Navigation_Kind, bool) {
	#partial switch target {
	case .Previous_Grapheme:          return .Previous_Grapheme, true
	case .Next_Grapheme:              return .Next_Grapheme, true
	case .Previous_Line:              return .Previous_Line, true
	case .Next_Line:                  return .Next_Line, true
	case .Line_Start:                 return .Line_Start, true
	case .Line_End:                   return .Line_End, true
	case .Line_First_Non_Whitespace:  return .Line_First_Non_Whitespace, true
	case .Previous_Word:              return .Previous_Word, true
	case .Next_Word_Start:            return .Next_Word_Start, true
	case .Word_End:                   return .Next_Word, true
	case .Buffer_Start:               return .Buffer_Start, true
	case .Buffer_End:                 return .Buffer_End, true
	}
	return .Previous_Grapheme, false
}

@(private)
modal_operator_character_target :: proc(
	target: interaction.Modal_Character_Target_Kind,
) -> (display.Line_Character_Target_Kind, bool) {
	switch target {
	case .Find_Next:     return .Find_Next, true
	case .Find_Previous: return .Find_Previous, true
	case .Till_Next:     return .Till_Next, true
	case .Till_Previous: return .Till_Previous, true
	case .None:          return .Invalid, false
	}
	unreachable()
}
