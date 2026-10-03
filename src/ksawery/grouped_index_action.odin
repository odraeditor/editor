// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery

import "base:runtime"
import "core:bytes"

/* Grouped_Input_Kind distinguishes pathspec and unified-patch process input. */
Grouped_Input_Kind :: enum u8 {
	Invalid,
	Pathspec,
	Patch,
}

/* Grouped_Index_Action_Request owns one checked compatible operation input. */
Grouped_Index_Action_Request :: struct {
	state: rawptr,
}

/* Grouped_Index_Action_Request_Descriptor reports one immutable group action. */
Grouped_Index_Action_Request_Descriptor :: struct {
	operation:   Index_Operation_ID,
	selection:   Grouped_Selection_Descriptor,
	input_kind:  Grouped_Input_Kind,
	limits:      Process_Limits,
	input_bytes: u64,
}

/* Grouped_Index_Action_Result owns one bounded completed group outcome. */
Grouped_Index_Action_Result :: struct {
	state: rawptr,
}

/* Grouped_Index_Action_Result_Descriptor reports one bounded process outcome. */
Grouped_Index_Action_Result_Descriptor :: struct {
	request:          Grouped_Index_Action_Request_Descriptor,
	exit_status:      i32,
	output_bytes:     u64,
	diagnostic_bytes: u64,
	failure:          Failure_Code,
	succeeded:        bool,
}

/* Grouped_Index_Action_Usage reports retained request or result payload. */
Grouped_Index_Action_Usage :: struct {
	input_bytes:      u64,
	output_bytes:     u64,
	diagnostic_bytes: u64,
	allocation_bytes: u64,
}

@(private)
Grouped_Index_Action_Request_Data :: struct {
	descriptor: Grouped_Index_Action_Request_Descriptor,
	input:      [dynamic]u8,
	allocator:  runtime.Allocator,
}

@(private)
Grouped_Index_Action_Result_Data :: struct {
	descriptor: Grouped_Index_Action_Result_Descriptor,
	output:     [dynamic]u8,
	diagnostic: [dynamic]u8,
	allocator:  runtime.Allocator,
}

/* grouped_index_action_prepare owns exact bounded input for one marked group. */
grouped_index_action_prepare :: proc(
	observation: ^Status_Observation,
	document: ^Diff_Document,
	selection: ^Grouped_Selection,
	operation: Index_Operation_ID,
	limits := DEFAULT_PROCESS_LIMITS,
	allocator := context.allocator,
) -> (Grouped_Index_Action_Request, bool, Failure_Code) {
	selection_descriptor, selected := grouped_selection_descriptor(selection)
	observation_descriptor, observed := status_observation_descriptor(observation)
	if allocator.procedure == nil || operation == Index_Operation_ID(0) || !selected || !observed ||
	   !process_limits_are_valid(limits) || selection_descriptor.id == Grouped_Selection_ID(0) ||
	   selection_descriptor.targets < 2 || selection_descriptor.repository != observation_descriptor.repository ||
	   selection_descriptor.generation != observation_descriptor.generation {
		return {}, false, .Invalid_Request
	}
	input_kind := Grouped_Input_Kind.Pathspec
	if selection_descriptor.granularity == .Diff_Units do input_kind = .Patch
	if input_kind == .Patch && (document == nil || !diff_document_is_current(document, observation)) {
		return {}, false, .Stale_Observation
	}
	state, allocation_error := new(Grouped_Index_Action_Request_Data, allocator)
	if allocation_error != nil do return {}, false, .Allocation
	state.allocator = allocator
	state.input, allocation_error = make([dynamic]u8, 0, int(min(limits.diff_bytes, 64 * KIBIBYTE)), allocator)
	if allocation_error != nil {
		grouped_index_action_request_data_destroy(state)
		return {}, false, .Allocation
	}
	failure := grouped_index_action_assemble_input(observation, document, selection, input_kind, &state.input)
	if failure != .None || len(state.input) == 0 || u64(len(state.input)) > limits.diff_bytes {
		grouped_index_action_request_data_destroy(state)
		if failure != .None do return {}, false, failure
		return {}, false, .Output_Limit
	}
	state.descriptor = {
		operation = operation,
		selection = selection_descriptor,
		input_kind = input_kind,
		limits = limits,
		input_bytes = u64(len(state.input)),
	}
	return Grouped_Index_Action_Request{state = state}, true, .None
}

/* grouped_index_action_request_descriptor copies immutable request metadata. */
grouped_index_action_request_descriptor :: proc(
	request: ^Grouped_Index_Action_Request,
) -> (Grouped_Index_Action_Request_Descriptor, bool) {
	state := grouped_index_action_request_data(request)
	if state == nil || !grouped_index_action_request_descriptor_is_valid(state.descriptor) do return {}, false
	return state.descriptor, true
}

/* grouped_index_action_request_input returns borrowed owned process input. */
grouped_index_action_request_input :: proc(request: ^Grouped_Index_Action_Request) -> ([]u8, bool) {
	state := grouped_index_action_request_data(request)
	if state == nil || u64(len(state.input)) != state.descriptor.input_bytes do return nil, false
	return state.input[:], true
}

/* grouped_index_action_request_revalidate proves every exact target is current. */
grouped_index_action_request_revalidate :: proc(
	observation: ^Status_Observation,
	document: ^Diff_Document,
	selection: ^Grouped_Selection,
	request: ^Grouped_Index_Action_Request,
) -> (bool, Failure_Code) {
	state := grouped_index_action_request_data(request)
	selection_descriptor, selected := grouped_selection_descriptor(selection)
	observation_descriptor, observed := status_observation_descriptor(observation)
	if state == nil || !grouped_index_action_request_descriptor_is_valid(state.descriptor) || !selected {
		return false, .Invalid_Request
	}
	if !observed || observation_descriptor.repository != state.descriptor.selection.repository ||
	   observation_descriptor.generation != state.descriptor.selection.generation ||
	   selection_descriptor != state.descriptor.selection {
		return false, .Stale_Observation
	}
	if state.descriptor.input_kind == .Patch && !diff_document_is_current(document, observation) {
		return false, .Stale_Observation
	}
	for ordinal in 0 ..< selection_descriptor.targets {
		target, available := grouped_selection_target(selection, ordinal)
		if !available do return false, .Target_Incompatible
		if target.granularity == .Complete_Paths {
			path, found := status_observation_path_by_id(observation, target.path.path)
			action, layer, supported := grouped_path_action(path.group)
			if !found || !supported || action != selection_descriptor.action || layer != selection_descriptor.layer {
				return false, .Target_Incompatible
			}
		} else {
			_, patch_available, failure := diff_document_unit_patch(document, target.unit)
			if !patch_available do return false, failure
		}
	}
	return true, .None
}

/* grouped_index_action_process_request maps one group to its closed process family. */
grouped_index_action_process_request :: proc(
	request: ^Grouped_Index_Action_Request,
) -> (Process_Request, bool) {
	descriptor, available := grouped_index_action_request_descriptor(request)
	if !available do return {}, false
	kind := Request_Kind.Stage_Group
	if descriptor.selection.action == .Unstage do kind = .Unstage_Group
	process := Process_Request {
		kind = kind,
		repository = descriptor.selection.repository,
		limits = descriptor.limits,
	}
	return process, process_request_is_valid(process)
}

/* grouped_index_action_request_usage reports exact retained input ownership. */
grouped_index_action_request_usage :: proc(
	request: ^Grouped_Index_Action_Request,
) -> (Grouped_Index_Action_Usage, bool) {
	state := grouped_index_action_request_data(request)
	if state == nil do return {}, false
	return Grouped_Index_Action_Usage {
		input_bytes = u64(len(state.input)),
		allocation_bytes = u64(size_of(Grouped_Index_Action_Request_Data)) + u64(cap(state.input)),
	}, true
}

/* grouped_index_action_request_close releases one owned grouped input. */
grouped_index_action_request_close :: proc(request: ^Grouped_Index_Action_Request) {
	state := grouped_index_action_request_data(request)
	if state == nil do return
	grouped_index_action_request_data_destroy(state)
	request^ = {}
}

/* grouped_index_action_result_open copies one bounded process outcome. */
grouped_index_action_result_open :: proc(
	request: Grouped_Index_Action_Request_Descriptor,
	exit_status: i32,
	output: []u8,
	diagnostic: []u8,
	process_failure := Failure_Code.None,
	allocator := context.allocator,
) -> (Grouped_Index_Action_Result, bool, Failure_Code) {
	if allocator.procedure == nil || !grouped_index_action_request_descriptor_is_valid(request) {
		return {}, false, .Invalid_Request
	}
	if u64(len(output)) > request.limits.stdout_bytes || u64(len(diagnostic)) > request.limits.diagnostic_bytes {
		return {}, false, .Output_Limit
	}
	state, allocation_error := new(Grouped_Index_Action_Result_Data, allocator)
	if allocation_error != nil do return {}, false, .Allocation
	state.allocator = allocator
	state.descriptor = {
		request = request,
		exit_status = exit_status,
		output_bytes = u64(len(output)),
		diagnostic_bytes = u64(len(diagnostic)),
		failure = process_failure,
		succeeded = process_failure == .None && exit_status == 0,
	}
	state.output, allocation_error = make([dynamic]u8, 0, len(output), allocator)
	if allocation_error == nil do state.diagnostic, allocation_error = make([dynamic]u8, 0, len(diagnostic), allocator)
	if allocation_error == nil && len(output) > 0 do _, allocation_error = append(&state.output, ..output)
	if allocation_error == nil && len(diagnostic) > 0 do _, allocation_error = append(&state.diagnostic, ..diagnostic)
	if allocation_error != nil {
		grouped_index_action_result_data_destroy(state)
		return {}, false, .Allocation
	}
	return Grouped_Index_Action_Result{state = state}, true, .None
}

/* grouped_index_action_result_descriptor copies immutable outcome metadata. */
grouped_index_action_result_descriptor :: proc(
	result: ^Grouped_Index_Action_Result,
) -> (Grouped_Index_Action_Result_Descriptor, bool) {
	state := grouped_index_action_result_data(result)
	if state == nil do return {}, false
	return state.descriptor, true
}

/* grouped_index_action_result_output returns borrowed copied process output. */
grouped_index_action_result_output :: proc(
	result: ^Grouped_Index_Action_Result,
) -> (output, diagnostic: []u8, ok: bool) {
	state := grouped_index_action_result_data(result)
	if state == nil do return nil, nil, false
	return state.output[:], state.diagnostic[:], true
}

/* grouped_index_action_result_usage reports exact retained result ownership. */
grouped_index_action_result_usage :: proc(
	result: ^Grouped_Index_Action_Result,
) -> (Grouped_Index_Action_Usage, bool) {
	state := grouped_index_action_result_data(result)
	if state == nil do return {}, false
	return Grouped_Index_Action_Usage {
		output_bytes = u64(len(state.output)),
		diagnostic_bytes = u64(len(state.diagnostic)),
		allocation_bytes = u64(size_of(Grouped_Index_Action_Result_Data)) +
		                   u64(cap(state.output) + cap(state.diagnostic)),
	}, true
}

/* grouped_index_action_result_close releases one owned group result. */
grouped_index_action_result_close :: proc(result: ^Grouped_Index_Action_Result) {
	state := grouped_index_action_result_data(result)
	if state == nil do return
	grouped_index_action_result_data_destroy(state)
	result^ = {}
}

@(private)
grouped_index_action_assemble_input :: proc(
	observation: ^Status_Observation,
	document: ^Diff_Document,
	selection: ^Grouped_Selection,
	kind: Grouped_Input_Kind,
	input: ^[dynamic]u8,
) -> Failure_Code {
	descriptor, described := grouped_selection_descriptor(selection)
	if !described || input == nil do return .Invalid_Request
	if kind == .Pathspec {
		for ordinal in 0 ..< descriptor.targets {
			target, available := grouped_selection_target(selection, ordinal)
			if !available || target.granularity != .Complete_Paths do return .Target_Incompatible
			path, found := status_observation_path_by_id(observation, target.path.path)
			if !found do return .Path_Unavailable
			text, copied := status_observation_path_text(observation, path)
			if !copied || len(text) == 0 do return .Path_Unavailable
			_, allocation_error := append(input, ..text)
			if allocation_error == nil do _, allocation_error = append(input, u8(0))
			if allocation_error != nil do return .Allocation
		}
		return .None
	}
	if kind != .Patch || document == nil do return .Invalid_Request
	order: [MAX_GROUP_TARGETS]u32
	for ordinal in 0 ..< descriptor.targets do order[ordinal] = ordinal
	for index in 1 ..< descriptor.targets {
		value := order[index]
		cursor := index
		for cursor > 0 {
			left, _ := grouped_selection_target(selection, order[cursor - 1])
			right, _ := grouped_selection_target(selection, value)
			if left.old_start < right.old_start ||
			   (left.old_start == right.old_start && left.new_start <= right.new_start) {
				break
			}
			order[cursor] = order[cursor - 1]
			cursor -= 1
		}
		order[cursor] = value
	}
	prelude: []u8
	for index in 0 ..< descriptor.targets {
		target, available := grouped_selection_target(selection, order[index])
		if !available || target.granularity != .Diff_Units do return .Target_Incompatible
		patch, patch_available, failure := diff_document_unit_patch(document, target.unit)
		if !patch_available do return failure
		hunk_start, found := grouped_patch_hunk_start(patch)
		if !found do return .Patch_Unavailable
		if index == 0 {
			prelude = patch[:hunk_start]
			_, allocation_error := append(input, ..prelude)
			if allocation_error != nil do return .Allocation
		} else if !bytes.equal(prelude, patch[:hunk_start]) {
			return .Target_Incompatible
		}
		_, allocation_error := append(input, ..patch[hunk_start:])
		if allocation_error != nil do return .Allocation
	}
	return .None
}

@(private)
grouped_patch_hunk_start :: proc(patch: []u8) -> (int, bool) {
	if len(patch) < 4 do return 0, false
	for index in 0 ..< len(patch) - 3 {
		if (index == 0 || patch[index - 1] == '\n') && patch[index] == '@' && patch[index + 1] == '@' &&
		   patch[index + 2] == ' ' && patch[index + 3] == '-' {
			return index, true
		}
	}
	return 0, false
}

@(private)
grouped_index_action_request_descriptor_is_valid :: proc(
	descriptor: Grouped_Index_Action_Request_Descriptor,
) -> bool {
	selection := descriptor.selection
	input_matches := (selection.granularity == .Complete_Paths && descriptor.input_kind == .Pathspec) ||
	                 (selection.granularity == .Diff_Units && descriptor.input_kind == .Patch)
	return descriptor.operation != Index_Operation_ID(0) && selection.id != Grouped_Selection_ID(0) &&
	       selection.targets >= 2 && selection.action != .Invalid && selection.layer != .Invalid &&
	       repository_context_is_valid(selection.repository) &&
	       selection.generation != Observation_Generation(0) && input_matches &&
	       process_limits_are_valid(descriptor.limits) && descriptor.input_bytes > 0 &&
	       descriptor.input_bytes <= descriptor.limits.diff_bytes
}

@(private)
grouped_index_action_request_data :: proc(
	request: ^Grouped_Index_Action_Request,
) -> ^Grouped_Index_Action_Request_Data {
	if request == nil || request.state == nil do return nil
	return cast(^Grouped_Index_Action_Request_Data)request.state
}

@(private)
grouped_index_action_request_data_destroy :: proc(state: ^Grouped_Index_Action_Request_Data) {
	if state == nil do return
	delete(state.input)
	free(state, state.allocator)
}

@(private)
grouped_index_action_result_data :: proc(
	result: ^Grouped_Index_Action_Result,
) -> ^Grouped_Index_Action_Result_Data {
	if result == nil || result.state == nil do return nil
	return cast(^Grouped_Index_Action_Result_Data)result.state
}

@(private)
grouped_index_action_result_data_destroy :: proc(state: ^Grouped_Index_Action_Result_Data) {
	if state == nil do return
	delete(state.output)
	delete(state.diagnostic)
	free(state, state.allocator)
}
