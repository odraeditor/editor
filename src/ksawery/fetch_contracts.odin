// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery

import "base:runtime"

/* REMOTE_CONFIGURATION_FINGERPRINT_BYTES is the exact SHA-256 identity width. */
REMOTE_CONFIGURATION_FINGERPRINT_BYTES :: 32

/* Fetch_Operation_ID identifies one admitted checked remote fetch attempt. */
Fetch_Operation_ID :: distinct u64

/* Remote_Configuration_Fingerprint owns one credential-free canonical configuration digest. */
Remote_Configuration_Fingerprint :: struct {
	bytes: [REMOTE_CONFIGURATION_FINGERPRINT_BYTES]u8,
}

/* Remote_Configuration_Identity binds one observed remote to its exact checked configuration. */
Remote_Configuration_Identity :: struct {
	remote:      Remote_Identity,
	fingerprint: Remote_Configuration_Fingerprint,
}

/* Fetch_Precondition binds a remote configuration to one non-sequenced repository state. */
Fetch_Precondition :: struct {
	configuration: Remote_Configuration_Identity,
	operation:     Operation_State,
}

/* Fetch_Request is one closed checked fetch of exactly one configured remote. */
Fetch_Request :: struct {
	operation:    Fetch_Operation_ID,
	precondition: Fetch_Precondition,
	limits:       Process_Limits,
}

/* Fetch_Result_Descriptor reports one bounded terminal fetch outcome. */
Fetch_Result_Descriptor :: struct {
	request:          Fetch_Request,
	started:          bool,
	exit_status:      i32,
	output_bytes:     u64,
	diagnostic_bytes: u64,
	failure:          Failure_Code,
	succeeded:        bool,
	refresh_required: bool,
}

/* Fetch_Usage reports exact retained public output and diagnostic payload sizes. */
Fetch_Usage :: struct {
	output_bytes:     u64,
	diagnostic_bytes: u64,
}

/* Fetch_Result owns copied bounded public process output for one fetch attempt. */
Fetch_Result :: struct {
	state: rawptr,
}

@(private)
Fetch_Result_Data :: struct {
	descriptor: Fetch_Result_Descriptor,
	output:     [dynamic]u8,
	diagnostic: [dynamic]u8,
	allocator:  runtime.Allocator,
}

/* Fetch_Feedback classifies stable checked-fetch admission and terminal outcomes. */
Fetch_Feedback :: enum u8 {
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

/* remote_configuration_fingerprint_assign copies one exact nonzero SHA-256 digest. */
remote_configuration_fingerprint_assign :: proc(
	fingerprint: ^Remote_Configuration_Fingerprint,
	bytes: []u8,
) -> bool {
	if fingerprint == nil do return false
	fingerprint^ = {}
	if len(bytes) != REMOTE_CONFIGURATION_FINGERPRINT_BYTES do return false
	nonzero := false
	for byte in bytes {
		if byte != 0 do nonzero = true
	}
	if !nonzero do return false
	copy(fingerprint.bytes[:], bytes)
	return true
}

/* remote_configuration_fingerprint_is_valid rejects an absent configuration identity. */
remote_configuration_fingerprint_is_valid :: proc(fingerprint: Remote_Configuration_Fingerprint) -> bool {
	for byte in fingerprint.bytes {
		if byte != 0 do return true
	}
	return false
}

/* remote_configuration_identity_is_valid checks one exact observation-bound remote configuration. */
remote_configuration_identity_is_valid :: proc(identity: Remote_Configuration_Identity) -> bool {
	return remote_identity_is_valid(identity.remote) &&
	       remote_configuration_fingerprint_is_valid(identity.fingerprint)
}

/* fetch_precondition_is_valid admits only a normal repository operation state. */
fetch_precondition_is_valid :: proc(precondition: Fetch_Precondition) -> bool {
	return remote_configuration_identity_is_valid(precondition.configuration) &&
	       precondition.operation == .Normal
}

/* fetch_request_prepare binds one selected remote to its checked configuration identity. */
fetch_request_prepare :: proc(
	observation: ^Ref_Observation,
	selection: Ref_Selection,
	configuration: Remote_Configuration_Identity,
	repository_operation: Operation_State,
	operation: Fetch_Operation_ID,
	limits := DEFAULT_PROCESS_LIMITS,
) -> (Fetch_Request, bool, Failure_Code) {
	if operation == Fetch_Operation_ID(0) || !process_limits_are_valid(limits) ||
	   !remote_configuration_identity_is_valid(configuration) {
		return {}, false, .Invalid_Request
	}
	if repository_operation != .Normal do return {}, false, .Action_Unavailable
	descriptor, described := ref_observation_descriptor(observation)
	if !described || descriptor.state == .Truncated do return {}, false, .Stale_Observation
	if !ref_selection_is_current(observation, selection) || selection.current.kind != .Remote {
		return {}, false, .Remote_Unavailable
	}
	if descriptor.repository != configuration.remote.repository ||
	   descriptor.generation != configuration.remote.generation ||
	   selection.current.remote != configuration.remote {
		return {}, false, .Stale_Observation
	}
	request := Fetch_Request {
		operation = operation,
		precondition = {
			configuration = configuration,
			operation = repository_operation,
		},
		limits = limits,
	}
	return request, fetch_request_is_valid(request), .None
}

/* fetch_request_is_valid checks one closed fetch request with no free-form transport input. */
fetch_request_is_valid :: proc(request: Fetch_Request) -> bool {
	return request.operation != Fetch_Operation_ID(0) &&
	       fetch_precondition_is_valid(request.precondition) &&
	       process_limits_are_valid(request.limits)
}

/* fetch_request_revalidate proves the selected remote and configuration remain exact before start. */
fetch_request_revalidate :: proc(
	observation: ^Ref_Observation,
	configuration: Remote_Configuration_Identity,
	repository_operation: Operation_State,
	request: Fetch_Request,
) -> (bool, Failure_Code) {
	if !fetch_request_is_valid(request) || !remote_configuration_identity_is_valid(configuration) {
		return false, .Invalid_Request
	}
	if repository_operation != .Normal do return false, .Action_Unavailable
	descriptor, described := ref_observation_descriptor(observation)
	if !described || descriptor.state == .Truncated ||
	   descriptor.repository != request.precondition.configuration.remote.repository ||
	   descriptor.generation != request.precondition.configuration.remote.generation {
		return false, .Stale_Observation
	}
	if configuration != request.precondition.configuration do return false, .Stale_Observation
	if !fetch_remote_is_observed(observation, configuration.remote) do return false, .Remote_Unavailable
	return true, .None
}

/* fetch_result_open copies one bounded terminal outcome and records whether refresh is mandatory. */
fetch_result_open :: proc(
	request: Fetch_Request,
	started: bool,
	exit_status: i32,
	output: []u8,
	diagnostic: []u8,
	process_failure := Failure_Code.None,
	allocator := context.allocator,
) -> (Fetch_Result, bool, Failure_Code) {
	if allocator.procedure == nil || !fetch_request_is_valid(request) do return {}, false, .Invalid_Request
	if u64(len(output)) > request.limits.stdout_bytes || u64(len(diagnostic)) > request.limits.diagnostic_bytes {
		return {}, false, .Output_Limit
	}
	if !started && (process_failure != .Cancelled || exit_status != 0 || len(output) != 0 || len(diagnostic) != 0) {
		return {}, false, .Invalid_Request
	}
	failure := process_failure
	if started && failure == .None && exit_status != 0 do failure = .Process_Failed
	succeeded := started && failure == .None && exit_status == 0
	state, allocation_error := new(Fetch_Result_Data, allocator)
	if allocation_error != nil do return {}, false, .Allocation
	state.allocator = allocator
	state.descriptor = {
		request = request,
		started = started,
		exit_status = exit_status,
		output_bytes = u64(len(output)),
		diagnostic_bytes = u64(len(diagnostic)),
		failure = failure,
		succeeded = succeeded,
		refresh_required = started,
	}
	state.output, allocation_error = make([dynamic]u8, 0, len(output), allocator)
	if allocation_error == nil do state.diagnostic, allocation_error = make([dynamic]u8, 0, len(diagnostic), allocator)
	if allocation_error == nil && len(output) > 0 do _, allocation_error = append(&state.output, ..output)
	if allocation_error == nil && len(diagnostic) > 0 do _, allocation_error = append(&state.diagnostic, ..diagnostic)
	if allocation_error != nil {
		fetch_result_data_destroy(state)
		return {}, false, .Allocation
	}
	return Fetch_Result{state = state}, true, .None
}

/* fetch_result_descriptor returns copied immutable fetch outcome metadata. */
fetch_result_descriptor :: proc(result: ^Fetch_Result) -> (Fetch_Result_Descriptor, bool) {
	state := fetch_result_data(result)
	if state == nil do return {}, false
	return state.descriptor, true
}

/* fetch_result_descriptor_is_valid checks terminal cancellation, success, and refresh invariants. */
fetch_result_descriptor_is_valid :: proc(descriptor: Fetch_Result_Descriptor) -> bool {
	if !fetch_request_is_valid(descriptor.request) ||
	   descriptor.output_bytes > descriptor.request.limits.stdout_bytes ||
	   descriptor.diagnostic_bytes > descriptor.request.limits.diagnostic_bytes {
		return false
	}
	if !descriptor.started {
		return descriptor.exit_status == 0 && descriptor.output_bytes == 0 && descriptor.diagnostic_bytes == 0 &&
		       descriptor.failure == .Cancelled && !descriptor.succeeded && !descriptor.refresh_required
	}
	if !descriptor.refresh_required do return false
	return descriptor.succeeded == (descriptor.failure == .None && descriptor.exit_status == 0)
}

/* fetch_result_usage reports exact copied public result payload sizes. */
fetch_result_usage :: proc(result: ^Fetch_Result) -> (Fetch_Usage, bool) {
	state := fetch_result_data(result)
	if state == nil do return {}, false
	return {output_bytes = u64(len(state.output)), diagnostic_bytes = u64(len(state.diagnostic))}, true
}

/* fetch_result_output returns borrowed bounded public process output and diagnostics. */
fetch_result_output :: proc(result: ^Fetch_Result) -> (output, diagnostic: []u8, ok: bool) {
	state := fetch_result_data(result)
	if state == nil do return nil, nil, false
	return state.output[:], state.diagnostic[:], true
}

/* fetch_result_close releases every owned fetch result allocation. */
fetch_result_close :: proc(result: ^Fetch_Result) {
	state := fetch_result_data(result)
	if state == nil do return
	fetch_result_data_destroy(state)
	result^ = {}
}

/* fetch_feedback maps one checked terminal result to stable application feedback. */
fetch_feedback :: proc(descriptor: Fetch_Result_Descriptor) -> Fetch_Feedback {
	if !fetch_result_descriptor_is_valid(descriptor) do return .Invalid
	if descriptor.succeeded do return .Completed
	#partial switch descriptor.failure {
	case .Stale_Observation, .History_Continuation_Stale: return .Stale
	case .Remote_Unavailable, .Ref_Unavailable, .Action_Unavailable,
	     .Presentation_Unavailable: return .Unavailable
	case .Invalid_Context, .Invalid_Limits, .Invalid_Request,
	     .Confirmation_Required, .Confirmation_Mismatch: return .Rejected
	case .Output_Limit, .Ref_Limit, .Remote_Limit, .Ref_Metadata_Limit,
	     .Ref_Temporary_Limit, .Ref_Truncated: return .Limited
	case .Timeout: return .Timed_Out
	case .Cancelled: return .Cancelled
	case .Executable_Unavailable, .Process_Failed, .Parse, .Allocation, .Cleanup: return .Failed
	case .None: return .Failed
	case:
		return .Unavailable
	}
}

@(private)
fetch_remote_is_observed :: proc(observation: ^Ref_Observation, wanted: Remote_Identity) -> bool {
	count, available := ref_observation_remote_count(observation)
	if !available do return false
	for ordinal in 0 ..< count {
		remote, found := ref_observation_remote(observation, ordinal)
		if found && remote == wanted do return true
	}
	return false
}

@(private)
fetch_result_data :: proc(result: ^Fetch_Result) -> ^Fetch_Result_Data {
	if result == nil || result.state == nil do return nil
	return cast(^Fetch_Result_Data)result.state
}

@(private)
fetch_result_data_destroy :: proc(state: ^Fetch_Result_Data) {
	if state == nil do return
	delete(state.output)
	delete(state.diagnostic)
	free(state, state.allocator)
}
