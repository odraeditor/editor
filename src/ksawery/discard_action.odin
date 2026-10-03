// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery

import "base:runtime"

/* Discard_Confirmation_ID identifies authority for one exact destructive request. */
Discard_Confirmation_ID :: distinct u64

/* Discard_Action_Request records one checked complete-path discard request. */
Discard_Action_Request :: struct {
	operation:    Index_Operation_ID,
	confirmation: Discard_Confirmation_ID,
	repository:   Repository_Context,
	target:       Path_Target,
	limits:       Process_Limits,
	confirmed:    bool,
}

/* Discard_Action_Result_Descriptor reports one bounded discard outcome. */
Discard_Action_Result_Descriptor :: struct {
	request:          Discard_Action_Request,
	exit_status:      i32,
	output_bytes:     u64,
	diagnostic_bytes: u64,
	failure:          Failure_Code,
	succeeded:        bool,
}

/* Discard_Action_Result owns copied bounded output for one completed attempt. */
Discard_Action_Result :: struct {
	state: rawptr,
}

/* Discard_Action_Usage reports retained result payload. */
Discard_Action_Usage :: struct {
	output_bytes:     u64,
	diagnostic_bytes: u64,
	allocation_bytes: u64,
}

@(private)
Discard_Action_Result_Data :: struct {
	descriptor: Discard_Action_Result_Descriptor,
	output:     [dynamic]u8,
	diagnostic: [dynamic]u8,
	allocator:  runtime.Allocator,
}

/* discard_action_prepare admits one tracked working-tree path before confirmation. */
discard_action_prepare :: proc(
	observation: ^Status_Observation,
	selection: Status_Selection,
	operation: Index_Operation_ID,
	confirmation: Discard_Confirmation_ID,
	modified_buffer: bool,
	limits := DEFAULT_PROCESS_LIMITS,
) -> (Discard_Action_Request, bool, Failure_Code) {
	if operation == Index_Operation_ID(0) || confirmation == Discard_Confirmation_ID(0) ||
	   !process_limits_are_valid(limits) {
		return {}, false, .Invalid_Request
	}
	if modified_buffer do return {}, false, .Modified_Buffer
	target, selected, failure := status_selection_path_target(observation, selection)
	if !selected do return {}, false, failure
	path, found := status_observation_path_by_id(observation, target.path)
	if !found do return {}, false, .Path_Unavailable
	if !discard_action_supports_path(path) do return {}, false, .Action_Unavailable
	descriptor, available := status_observation_descriptor(observation)
	if !available do return {}, false, .Stale_Observation
	request := Discard_Action_Request {
		operation = operation,
		confirmation = confirmation,
		repository = descriptor.repository,
		target = target,
		limits = limits,
	}
	return request, discard_action_request_is_valid(request), .None
}

/* discard_action_request_is_valid checks the closed request shape and identity. */
discard_action_request_is_valid :: proc(request: Discard_Action_Request) -> bool {
	return request.operation != Index_Operation_ID(0) &&
	       request.confirmation != Discard_Confirmation_ID(0) &&
	       repository_context_is_valid(request.repository) &&
	       path_target_is_valid(request.target) && process_limits_are_valid(request.limits)
}

/* discard_action_confirm grants authority only to the exact prepared request. */
discard_action_confirm :: proc(
	request: ^Discard_Action_Request,
	confirmation: Discard_Confirmation_ID,
) -> (bool, Failure_Code) {
	if request == nil || !discard_action_request_is_valid(request^) {
		return false, .Invalid_Request
	}
	if confirmation == Discard_Confirmation_ID(0) || confirmation != request.confirmation {
		return false, .Confirmation_Mismatch
	}
	request.confirmed = true
	return true, .None
}

/* discard_action_revalidate checks generation, path state, buffer state, and confirmation. */
discard_action_revalidate :: proc(
	observation: ^Status_Observation,
	request: Discard_Action_Request,
	modified_buffer: bool,
) -> (Status_Path, bool, Failure_Code) {
	if !discard_action_request_is_valid(request) do return {}, false, .Invalid_Request
	if !request.confirmed do return {}, false, .Confirmation_Required
	if modified_buffer do return {}, false, .Modified_Buffer
	descriptor, available := status_observation_descriptor(observation)
	if !available || descriptor.repository != request.repository ||
	   descriptor.generation != request.target.generation {
		return {}, false, .Stale_Observation
	}
	path, found := status_observation_path_by_id(observation, request.target.path)
	if !found do return {}, false, .Path_Unavailable
	if !discard_action_supports_path(path) do return {}, false, .Action_Unavailable
	return path, true, .None
}

/* discard_action_process_request maps confirmed discard to its closed process family. */
discard_action_process_request :: proc(request: Discard_Action_Request) -> (Process_Request, bool) {
	if !discard_action_request_is_valid(request) || !request.confirmed do return {}, false
	process := Process_Request {
		kind = .Discard_Path,
		repository = request.repository,
		target = request.target,
		limits = request.limits,
	}
	return process, process_request_is_valid(process)
}

/* discard_action_available reports semantic path eligibility before editor protection. */
discard_action_available :: proc(
	observation: ^Status_Observation,
	selection: Status_Selection,
) -> bool {
	_, prepared, _ := discard_action_prepare(
		observation,
		selection,
		Index_Operation_ID(1),
		Discard_Confirmation_ID(1),
		false,
	)
	return prepared
}

/* discard_action_result_open copies bounded output from one terminal outcome. */
discard_action_result_open :: proc(
	request: Discard_Action_Request,
	exit_status: i32,
	output: []u8,
	diagnostic: []u8,
	failure := Failure_Code.None,
	allocator := context.allocator,
) -> (Discard_Action_Result, bool, Failure_Code) {
	if allocator.procedure == nil || !discard_action_request_is_valid(request) {
		return {}, false, .Invalid_Request
	}
	if u64(len(output)) > request.limits.stdout_bytes ||
	   u64(len(diagnostic)) > request.limits.diagnostic_bytes {
		return {}, false, .Output_Limit
	}
	state, allocation_error := new(Discard_Action_Result_Data, allocator)
	if allocation_error != nil do return {}, false, .Allocation
	state.allocator = allocator
	state.descriptor = {
		request = request,
		exit_status = exit_status,
		output_bytes = u64(len(output)),
		diagnostic_bytes = u64(len(diagnostic)),
		failure = failure,
		succeeded = request.confirmed && failure == .None && exit_status == 0,
	}
	state.output, allocation_error = make([dynamic]u8, 0, len(output), allocator)
	if allocation_error == nil {
		state.diagnostic, allocation_error = make([dynamic]u8, 0, len(diagnostic), allocator)
	}
	if allocation_error == nil && len(output) > 0 do _, allocation_error = append(&state.output, ..output)
	if allocation_error == nil && len(diagnostic) > 0 {
		_, allocation_error = append(&state.diagnostic, ..diagnostic)
	}
	if allocation_error != nil {
		discard_action_result_data_destroy(state)
		return {}, false, .Allocation
	}
	return Discard_Action_Result{state = state}, true, .None
}

/* discard_action_result_descriptor copies immutable outcome metadata. */
discard_action_result_descriptor :: proc(
	result: ^Discard_Action_Result,
) -> (Discard_Action_Result_Descriptor, bool) {
	state := discard_action_result_data(result)
	if state == nil do return {}, false
	return state.descriptor, true
}

/* discard_action_result_output returns borrowed copied process output. */
discard_action_result_output :: proc(
	result: ^Discard_Action_Result,
) -> (output, diagnostic: []u8, ok: bool) {
	state := discard_action_result_data(result)
	if state == nil do return nil, nil, false
	return state.output[:], state.diagnostic[:], true
}

/* discard_action_result_usage reports exact retained ownership. */
discard_action_result_usage :: proc(
	result: ^Discard_Action_Result,
) -> (Discard_Action_Usage, bool) {
	state := discard_action_result_data(result)
	if state == nil do return {}, false
	return Discard_Action_Usage {
		output_bytes = u64(len(state.output)),
		diagnostic_bytes = u64(len(state.diagnostic)),
		allocation_bytes = u64(size_of(Discard_Action_Result_Data)) +
		                   u64(cap(state.output) + cap(state.diagnostic)),
	}, true
}

/* discard_action_result_close releases one owned result. */
discard_action_result_close :: proc(result: ^Discard_Action_Result) {
	state := discard_action_result_data(result)
	if state == nil do return
	discard_action_result_data_destroy(state)
	result^ = {}
}

/* discard_action_feedback maps discard failures to stable application feedback. */
discard_action_feedback :: proc(failure: Failure_Code) -> Index_Action_Feedback {
	return index_action_feedback(failure)
}

@(private)
discard_action_supports_path :: proc(path: Status_Path) -> bool {
	return path.id != Path_ID(0) && path.group == .Unstaged
}

@(private)
discard_action_result_data :: proc(result: ^Discard_Action_Result) -> ^Discard_Action_Result_Data {
	if result == nil || result.state == nil do return nil
	return cast(^Discard_Action_Result_Data)result.state
}

@(private)
discard_action_result_data_destroy :: proc(state: ^Discard_Action_Result_Data) {
	if state == nil do return
	delete(state.output)
	delete(state.diagnostic)
	free(state, state.allocator)
}
