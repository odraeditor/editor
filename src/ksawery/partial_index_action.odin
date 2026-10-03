// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery

import "base:runtime"
import "core:bytes"

/* Patch_Direction identifies how one exact diff unit changes the Git index. */
Patch_Direction :: enum u8 {
	Invalid,
	Apply,
	Reverse,
}

/* Partial_Index_Action_Request owns one checked hunk patch and its authority. */
Partial_Index_Action_Request :: struct {
	state: rawptr,
}

/* Partial_Index_Action_Request_Descriptor reports one immutable hunk action. */
Partial_Index_Action_Request_Descriptor :: struct {
	operation:   Index_Operation_ID,
	action:      Index_Action,
	direction:   Patch_Direction,
	repository:  Repository_Context,
	target:      Diff_Unit_Target,
	limits:      Process_Limits,
	input_bytes: u64,
}

/* Partial_Index_Action_Usage reports retained request or result payload. */
Partial_Index_Action_Usage :: struct {
	input_bytes:      u64,
	output_bytes:     u64,
	diagnostic_bytes: u64,
	allocation_bytes: u64,
}

@(private)
Partial_Index_Action_Request_Data :: struct {
	descriptor: Partial_Index_Action_Request_Descriptor,
	patch:      [dynamic]u8,
	allocator:  runtime.Allocator,
}

/* Partial_Index_Action_Result owns one bounded completed hunk-action outcome. */
Partial_Index_Action_Result :: struct {
	state: rawptr,
}

/* Partial_Index_Action_Result_Descriptor reports one bounded process outcome. */
Partial_Index_Action_Result_Descriptor :: struct {
	request:          Partial_Index_Action_Request_Descriptor,
	exit_status:      i32,
	output_bytes:     u64,
	diagnostic_bytes: u64,
	failure:          Failure_Code,
	succeeded:        bool,
}

@(private)
Partial_Index_Action_Result_Data :: struct {
	descriptor: Partial_Index_Action_Result_Descriptor,
	output:     [dynamic]u8,
	diagnostic: [dynamic]u8,
	allocator:  runtime.Allocator,
}

/* partial_index_action_prepare copies one exact selected hunk into a request. */
partial_index_action_prepare :: proc(
	observation: ^Status_Observation,
	document: ^Diff_Document,
	selection: Status_Selection,
	action: Index_Action,
	operation: Index_Operation_ID,
	limits := DEFAULT_PROCESS_LIMITS,
	allocator := context.allocator,
) -> (Partial_Index_Action_Request, bool, Failure_Code) {
	if allocator.procedure == nil || operation == Index_Operation_ID(0) ||
	   !process_limits_are_valid(limits) {
		return {}, false, .Invalid_Request
	}
	target, selected, failure := status_selection_diff_unit_target(observation, document, selection)
	if !selected do return {}, false, failure
	direction, supported := partial_index_action_direction(action, target.layer)
	if !supported do return {}, false, .Action_Unavailable
	descriptor, available := status_observation_descriptor(observation)
	if !available do return {}, false, .Stale_Observation
	patch, patch_available, patch_failure := diff_document_unit_patch(document, target)
	if !patch_available do return {}, false, patch_failure
	if len(patch) == 0 do return {}, false, .Patch_Unavailable
	if u64(len(patch)) > limits.diff_bytes do return {}, false, .Output_Limit

	state, allocation_error := new(Partial_Index_Action_Request_Data, allocator)
	if allocation_error != nil do return {}, false, .Allocation
	state.allocator = allocator
	state.descriptor = {
		operation = operation,
		action = action,
		direction = direction,
		repository = descriptor.repository,
		target = target,
		limits = limits,
		input_bytes = u64(len(patch)),
	}
	state.patch, allocation_error = make([dynamic]u8, 0, len(patch), allocator)
	if allocation_error == nil do _, allocation_error = append(&state.patch, ..patch)
	if allocation_error != nil {
		partial_index_action_request_data_destroy(state)
		return {}, false, .Allocation
	}
	return Partial_Index_Action_Request{state = state}, true, .None
}

/* partial_index_action_request_descriptor copies immutable request metadata. */
partial_index_action_request_descriptor :: proc(
	request: ^Partial_Index_Action_Request,
) -> (Partial_Index_Action_Request_Descriptor, bool) {
	state := partial_index_action_request_data(request)
	if state == nil || !partial_index_action_request_descriptor_is_valid(state.descriptor) do return {}, false
	return state.descriptor, true
}

/* partial_index_action_request_patch returns borrowed owned patch input. */
partial_index_action_request_patch :: proc(request: ^Partial_Index_Action_Request) -> ([]u8, bool) {
	state := partial_index_action_request_data(request)
	if state == nil || u64(len(state.patch)) != state.descriptor.input_bytes do return nil, false
	return state.patch[:], true
}

/* partial_index_action_request_revalidate proves target and bytes are current. */
partial_index_action_request_revalidate :: proc(
	observation: ^Status_Observation,
	document: ^Diff_Document,
	request: ^Partial_Index_Action_Request,
) -> (bool, Failure_Code) {
	state := partial_index_action_request_data(request)
	if state == nil || !partial_index_action_request_descriptor_is_valid(state.descriptor) {
		return false, .Invalid_Request
	}
	observation_descriptor, observed := status_observation_descriptor(observation)
	if !observed || observation_descriptor.repository != state.descriptor.repository ||
	   observation_descriptor.generation != state.descriptor.target.path.generation ||
	   !diff_document_is_current(document, observation) {
		return false, .Stale_Observation
	}
	patch, available, failure := diff_document_unit_patch(document, state.descriptor.target)
	if !available do return false, failure
	if u64(len(patch)) != state.descriptor.input_bytes || !bytes.equal(patch, state.patch[:]) {
		return false, .Patch_Unavailable
	}
	return true, .None
}

/* partial_index_action_process_request maps one hunk action to its process family. */
partial_index_action_process_request :: proc(
	request: ^Partial_Index_Action_Request,
) -> (Process_Request, bool) {
	descriptor, available := partial_index_action_request_descriptor(request)
	if !available do return {}, false
	kind := Request_Kind.Stage_Diff_Unit
	if descriptor.action == .Unstage do kind = .Unstage_Diff_Unit
	process := Process_Request {
		kind = kind,
		repository = descriptor.repository,
		target = descriptor.target.path,
		limits = descriptor.limits,
	}
	return process, process_request_is_valid(process)
}

/* partial_index_action_available reports whether one selected hunk admits an action. */
partial_index_action_available :: proc(
	observation: ^Status_Observation,
	document: ^Diff_Document,
	selection: Status_Selection,
	action: Index_Action,
) -> bool {
	target, selected, _ := status_selection_diff_unit_target(observation, document, selection)
	if !selected do return false
	_, supported := partial_index_action_direction(action, target.layer)
	return supported
}

/* partial_index_action_request_usage reports exact retained patch ownership. */
partial_index_action_request_usage :: proc(
	request: ^Partial_Index_Action_Request,
) -> (Partial_Index_Action_Usage, bool) {
	state := partial_index_action_request_data(request)
	if state == nil do return {}, false
	return Partial_Index_Action_Usage {
		input_bytes = u64(len(state.patch)),
		allocation_bytes = u64(size_of(Partial_Index_Action_Request_Data)) +
		                   u64(cap(state.patch)) * u64(size_of(u8)),
	}, true
}

/* partial_index_action_request_close releases one owned checked patch. */
partial_index_action_request_close :: proc(request: ^Partial_Index_Action_Request) {
	state := partial_index_action_request_data(request)
	if state == nil do return
	partial_index_action_request_data_destroy(state)
	request^ = {}
}

/* partial_index_action_result_open copies one bounded process outcome. */
partial_index_action_result_open :: proc(
	request: Partial_Index_Action_Request_Descriptor,
	exit_status: i32,
	output: []u8,
	diagnostic: []u8,
	process_failure := Failure_Code.None,
	allocator := context.allocator,
) -> (Partial_Index_Action_Result, bool, Failure_Code) {
	if allocator.procedure == nil || !partial_index_action_request_descriptor_is_valid(request) {
		return {}, false, .Invalid_Request
	}
	if u64(len(output)) > request.limits.stdout_bytes ||
	   u64(len(diagnostic)) > request.limits.diagnostic_bytes {
		return {}, false, .Output_Limit
	}
	state, allocation_error := new(Partial_Index_Action_Result_Data, allocator)
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
		partial_index_action_result_data_destroy(state)
		return {}, false, .Allocation
	}
	return Partial_Index_Action_Result{state = state}, true, .None
}

/* partial_index_action_result_descriptor copies immutable outcome metadata. */
partial_index_action_result_descriptor :: proc(
	result: ^Partial_Index_Action_Result,
) -> (Partial_Index_Action_Result_Descriptor, bool) {
	state := partial_index_action_result_data(result)
	if state == nil do return {}, false
	return state.descriptor, true
}

/* partial_index_action_result_output returns borrowed copied process output. */
partial_index_action_result_output :: proc(
	result: ^Partial_Index_Action_Result,
) -> (output, diagnostic: []u8, ok: bool) {
	state := partial_index_action_result_data(result)
	if state == nil do return nil, nil, false
	return state.output[:], state.diagnostic[:], true
}

/* partial_index_action_result_usage reports exact retained result ownership. */
partial_index_action_result_usage :: proc(
	result: ^Partial_Index_Action_Result,
) -> (Partial_Index_Action_Usage, bool) {
	state := partial_index_action_result_data(result)
	if state == nil do return {}, false
	return Partial_Index_Action_Usage {
		output_bytes = u64(len(state.output)),
		diagnostic_bytes = u64(len(state.diagnostic)),
		allocation_bytes = u64(size_of(Partial_Index_Action_Result_Data)) +
		                   u64(cap(state.output) + cap(state.diagnostic)) * u64(size_of(u8)),
	}, true
}

/* partial_index_action_result_is_current checks its exact hunk observation. */
partial_index_action_result_is_current :: proc(
	result: ^Partial_Index_Action_Result,
	observation: ^Status_Observation,
) -> bool {
	state := partial_index_action_result_data(result)
	descriptor, available := status_observation_descriptor(observation)
	if state == nil || !available ||
	   state.descriptor.request.repository != descriptor.repository ||
	   state.descriptor.request.target.path.generation != descriptor.generation {
		return false
	}
	_, found := status_observation_path_by_id(observation, state.descriptor.request.target.path.path)
	return found
}

/* partial_index_action_result_close releases one owned action result. */
partial_index_action_result_close :: proc(result: ^Partial_Index_Action_Result) {
	state := partial_index_action_result_data(result)
	if state == nil do return
	partial_index_action_result_data_destroy(state)
	result^ = {}
}

/* partial_index_action_feedback maps failures to stable application feedback. */
partial_index_action_feedback :: proc(failure: Failure_Code) -> Index_Action_Feedback {
	return index_action_feedback(failure)
}

@(private)
partial_index_action_direction :: proc(action: Index_Action, layer: Diff_Layer) -> (Patch_Direction, bool) {
	if action == .Stage && layer == .Working_Tree do return .Apply, true
	if action == .Unstage && layer == .Index do return .Reverse, true
	return .Invalid, false
}

@(private)
partial_index_action_request_descriptor_is_valid :: proc(
	descriptor: Partial_Index_Action_Request_Descriptor,
) -> bool {
	direction, supported := partial_index_action_direction(descriptor.action, descriptor.target.layer)
	return supported && descriptor.direction == direction && descriptor.operation != Index_Operation_ID(0) &&
	       repository_context_is_valid(descriptor.repository) && diff_unit_target_is_valid(descriptor.target) &&
	       process_limits_are_valid(descriptor.limits) && descriptor.input_bytes > 0 &&
	       descriptor.input_bytes <= descriptor.limits.diff_bytes
}

@(private)
partial_index_action_request_data :: proc(
	request: ^Partial_Index_Action_Request,
) -> ^Partial_Index_Action_Request_Data {
	if request == nil || request.state == nil do return nil
	return cast(^Partial_Index_Action_Request_Data)request.state
}

@(private)
partial_index_action_request_data_destroy :: proc(state: ^Partial_Index_Action_Request_Data) {
	if state == nil do return
	delete(state.patch)
	free(state, state.allocator)
}

@(private)
partial_index_action_result_data :: proc(
	result: ^Partial_Index_Action_Result,
) -> ^Partial_Index_Action_Result_Data {
	if result == nil || result.state == nil do return nil
	return cast(^Partial_Index_Action_Result_Data)result.state
}

@(private)
partial_index_action_result_data_destroy :: proc(state: ^Partial_Index_Action_Result_Data) {
	if state == nil do return
	delete(state.output)
	delete(state.diagnostic)
	free(state, state.allocator)
}
