// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery

import "base:runtime"

/* Index_Operation_ID identifies one admitted index mutation attempt. */
Index_Operation_ID :: distinct u64

/* Index_Action identifies the complete-path index mutations in this delivery. */
Index_Action :: enum u8 {
	Invalid,
	Stage,
	Unstage,
}

/* Index_Action_Request is one checked generation-bound complete-path mutation. */
Index_Action_Request :: struct {
	operation:  Index_Operation_ID,
	action:     Index_Action,
	repository: Repository_Context,
	target:     Path_Target,
	limits:     Process_Limits,
}

/* Index_Action_Result_Descriptor reports one bounded process outcome. */
Index_Action_Result_Descriptor :: struct {
	operation:        Index_Operation_ID,
	action:           Index_Action,
	target:           Path_Target,
	exit_status:      i32,
	output_bytes:     u64,
	diagnostic_bytes: u64,
	failure:          Failure_Code,
	succeeded:        bool,
}

/* Index_Action_Result owns copied bounded output for one completed attempt. */
Index_Action_Result :: struct {
	state: rawptr,
}

@(private)
Index_Action_Result_Data :: struct {
	descriptor: Index_Action_Result_Descriptor,
	output:     [dynamic]u8,
	diagnostic: [dynamic]u8,
	allocator:  runtime.Allocator,
}

/* Index_Action_Feedback classifies an action outcome for the application layer. */
Index_Action_Feedback :: enum u8 {
	Invalid,
	Completed,
	Stale,
	Unavailable,
	Rejected,
	Failed,
	Limited,
	Timed_Out,
	Cancelled,
}

/* index_action_prepare admits one action from the selected semantic path. */
index_action_prepare :: proc(
	observation: ^Status_Observation,
	selection: Status_Selection,
	action: Index_Action,
	operation: Index_Operation_ID,
	limits := DEFAULT_PROCESS_LIMITS,
) -> (Index_Action_Request, bool, Failure_Code) {
	if operation == Index_Operation_ID(0) || !process_limits_are_valid(limits) {
		return {}, false, .Invalid_Request
	}
	target, selected, failure := status_selection_path_target(observation, selection)
	if !selected do return {}, false, failure
	path, found := status_observation_path_by_id(observation, target.path)
	if !found do return {}, false, .Path_Unavailable
	if !index_action_supports_group(action, path.group) do return {}, false, .Action_Unavailable
	descriptor, available := status_observation_descriptor(observation)
	if !available do return {}, false, .Stale_Observation
	request := Index_Action_Request {
		operation = operation,
		action = action,
		repository = descriptor.repository,
		target = target,
		limits = limits,
	}
	return request, index_action_request_is_valid(request), .None
}

/* index_action_request_is_valid checks the closed request shape. */
index_action_request_is_valid :: proc(request: Index_Action_Request) -> bool {
	return request.operation != Index_Operation_ID(0) && request.action != .Invalid &&
	       repository_context_is_valid(request.repository) && path_target_is_valid(request.target) &&
	       process_limits_are_valid(request.limits)
}

/* index_action_available reports whether the selected semantic path admits one action. */
index_action_available :: proc(
	observation: ^Status_Observation,
	selection: Status_Selection,
	action: Index_Action,
) -> bool {
	_, prepared, _ := index_action_prepare(
		observation,
		selection,
		action,
		Index_Operation_ID(1),
	)
	return prepared
}

/* index_action_process_request maps an admitted action to its closed process family. */
index_action_process_request :: proc(request: Index_Action_Request) -> (Process_Request, bool) {
	if !index_action_request_is_valid(request) do return {}, false
	kind := Request_Kind.Stage_Path
	if request.action == .Unstage do kind = .Unstage_Path
	process := Process_Request {
		kind = kind,
		repository = request.repository,
		target = request.target,
		limits = request.limits,
	}
	return process, process_request_is_valid(process)
}

/* index_action_revalidate proves the target and path state still match before execution. */
index_action_revalidate :: proc(
	observation: ^Status_Observation,
	request: Index_Action_Request,
) -> (Status_Path, bool, Failure_Code) {
	descriptor, available := status_observation_descriptor(observation)
	if !available || descriptor.generation != request.target.generation ||
	   descriptor.repository != request.repository {
		return {}, false, .Stale_Observation
	}
	path, found := status_observation_path_by_id(observation, request.target.path)
	if !found do return {}, false, .Path_Unavailable
	if !index_action_supports_group(request.action, path.group) {
		return {}, false, .Action_Unavailable
	}
	return path, true, .None
}

/* index_action_result_open copies bounded output from one completed mutation. */
index_action_result_open :: proc(
	request: Index_Action_Request,
	exit_status: i32,
	output: []u8,
	diagnostic: []u8,
	process_failure := Failure_Code.None,
	allocator := context.allocator,
) -> (Index_Action_Result, bool, Failure_Code) {
	if allocator.procedure == nil || !index_action_request_is_valid(request) {
		return {}, false, .Invalid_Request
	}
	if u64(len(output)) > request.limits.stdout_bytes ||
	   u64(len(diagnostic)) > request.limits.diagnostic_bytes {
		return {}, false, .Output_Limit
	}
	state, allocation_error := new(Index_Action_Result_Data, allocator)
	if allocation_error != nil do return {}, false, .Allocation
	state.allocator = allocator
	state.descriptor = {
		operation = request.operation,
		action = request.action,
		target = request.target,
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
		index_action_result_data_destroy(state)
		return {}, false, .Allocation
	}
	return Index_Action_Result{state = state}, true, .None
}

/* index_action_result_descriptor returns copied immutable result metadata. */
index_action_result_descriptor :: proc(result: ^Index_Action_Result) -> (Index_Action_Result_Descriptor, bool) {
	state := index_action_result_data(result)
	if state == nil do return {}, false
	return state.descriptor, true
}

/* index_action_result_output returns borrowed copied process output. */
index_action_result_output :: proc(result: ^Index_Action_Result) -> (output, diagnostic: []u8, ok: bool) {
	state := index_action_result_data(result)
	if state == nil do return nil, nil, false
	return state.output[:], state.diagnostic[:], true
}

/* index_action_result_is_current rejects result authority after observation replacement. */
index_action_result_is_current :: proc(
	result: ^Index_Action_Result,
	observation: ^Status_Observation,
) -> bool {
	result_state := index_action_result_data(result)
	observation_descriptor, available := status_observation_descriptor(observation)
	if result_state == nil || !available ||
	   result_state.descriptor.target.generation != observation_descriptor.generation {
		return false
	}
	_, found := status_observation_path_by_id(observation, result_state.descriptor.target.path)
	return found
}

/* index_action_result_close releases one owned action result. */
index_action_result_close :: proc(result: ^Index_Action_Result) {
	state := index_action_result_data(result)
	if state == nil do return
	index_action_result_data_destroy(state)
	result^ = {}
}

/* index_action_feedback maps repository failures to stable application feedback. */
index_action_feedback :: proc(failure: Failure_Code) -> Index_Action_Feedback {
	#partial switch failure {
	case .None: return .Completed
	case .Stale_Observation: return .Stale
	case .Path_Unavailable, .Action_Unavailable, .Diff_Unsupported,
	     .Diff_Unit_Unavailable, .Patch_Unavailable, .History_Unborn,
	     .Revision_Unavailable, .Presentation_Unavailable,
	     .Commit_Unavailable: return .Unavailable
	case .Invalid_Context, .Invalid_Limits, .Invalid_Request, .Target_Duplicate,
	     .Target_Incompatible, .Target_Overlap, .Confirmation_Required,
	     .Confirmation_Mismatch, .Commit_Message_Invalid: return .Rejected
	case .Modified_Buffer: return .Unavailable
	case .Output_Limit, .Diff_Truncated, .Target_Limit, .History_Limit,
	     .Parent_Limit, .History_Metadata_Limit, .History_Message_Limit,
	     .History_Topology_Limit, .History_Temporary_Limit, .History_Truncated: return .Limited
	case .History_Continuation_Stale: return .Stale
	case .Timeout: return .Timed_Out
	case .Cancelled: return .Cancelled
	case .Executable_Unavailable, .Process_Failed, .Parse, .Allocation, .Cleanup: return .Failed
	}
	return .Invalid
}

@(private)
index_action_supports_group :: proc(action: Index_Action, group: Change_Group) -> bool {
	if action == .Stage do return group == .Untracked || group == .Unstaged
	if action == .Unstage do return group == .Staged
	return false
}

@(private)
index_action_result_data :: proc(result: ^Index_Action_Result) -> ^Index_Action_Result_Data {
	if result == nil || result.state == nil do return nil
	return cast(^Index_Action_Result_Data)result.state
}

@(private)
index_action_result_data_destroy :: proc(state: ^Index_Action_Result_Data) {
	if state == nil do return
	delete(state.output)
	delete(state.diagnostic)
	free(state, state.allocator)
}
