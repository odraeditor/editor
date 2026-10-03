// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery

import "base:runtime"

/* Push_Operation_ID identifies one admitted checked single-branch push attempt. */
Push_Operation_ID :: distinct u64

/* Push_Confirmation_ID identifies one explicit exact-destination push confirmation. */
Push_Confirmation_ID :: distinct u64

/* Push_Configuration_Identity binds one remote to exact URL and push-URL configuration. */
Push_Configuration_Identity :: struct {
	remote:      Remote_Identity,
	fingerprint: Remote_Configuration_Fingerprint,
}

/* Push_Destination binds one configured remote to one derived branch and tracking ref. */
Push_Destination :: struct {
	remote:   Remote_Identity,
	branch:   Ref_Name,
	tracking: Ref_Identity,
}

/* Push_Precondition binds one source branch and derived destination to checked repository truth. */
Push_Precondition :: struct {
	configuration: Push_Configuration_Identity,
	source:        Ref_Identity,
	destination:   Push_Destination,
	tracking:      Tracking_Relationship,
	head:          Head_Observation,
	operation:     Operation_State,
}

/* Push_Confirmation owns one one-shot acknowledgement of the exact publication boundary. */
Push_Confirmation :: struct {
	id:           Push_Confirmation_ID,
	precondition: Push_Precondition,
	confirmed:    bool,
	consumed:     bool,
}

/* Push_Request is one closed non-force publication of one exact local branch. */
Push_Request :: struct {
	operation:    Push_Operation_ID,
	precondition: Push_Precondition,
	confirmation: Push_Confirmation_ID,
	limits:       Process_Limits,
}

/* Push_Lineage records checked local and remote-tracking state across one started push. */
Push_Lineage :: struct {
	source_before:   Ref_Identity,
	tracking_before: Tracking_Relationship,
	source_after:    Ref_Identity,
	tracking_after:  Tracking_Relationship,
}

/* Push_Result_Descriptor separates transport completion from refreshed publication proof. */
Push_Result_Descriptor :: struct {
	request:             Push_Request,
	lineage:             Push_Lineage,
	started:             bool,
	verified:            bool,
	exit_status:         i32,
	output_bytes:        u64,
	diagnostic_bytes:    u64,
	failure:             Failure_Code,
	transport_succeeded: bool,
	succeeded:           bool,
	refresh_required:    bool,
}

/* Push_Usage reports exact retained public output and diagnostic payload sizes. */
Push_Usage :: struct {
	output_bytes:     u64,
	diagnostic_bytes: u64,
}

/* Push_Result owns copied bounded process output and refreshed publication proof. */
Push_Result :: struct {
	state: rawptr,
}

@(private)
Push_Result_Data :: struct {
	descriptor: Push_Result_Descriptor,
	output:     [dynamic]u8,
	diagnostic: [dynamic]u8,
	allocator:  runtime.Allocator,
}

/* Push_Feedback classifies stable push admission, refresh, and terminal outcomes. */
Push_Feedback :: enum u8 {
	Invalid,
	Refreshing,
	Completed,
	Stale,
	Unavailable,
	Rejected,
	Failed,
	Limited,
	Timed_Out,
	Cancelled,
}

/* push_configuration_identity_is_valid rejects an absent push destination identity. */
push_configuration_identity_is_valid :: proc(identity: Push_Configuration_Identity) -> bool {
	return remote_identity_is_valid(identity.remote) &&
	       remote_configuration_fingerprint_is_valid(identity.fingerprint)
}

/* push_destination_is_valid checks one derived single-branch destination shape. */
push_destination_is_valid :: proc(destination: Push_Destination) -> bool {
	if !remote_identity_is_valid(destination.remote) ||
	   !ref_name_is_valid(destination.branch) ||
	   !ref_identity_is_valid(destination.tracking) ||
	   destination.tracking.kind != .Remote_Tracking_Branch ||
	   destination.remote.repository != destination.tracking.repository ||
	   destination.remote.generation != destination.tracking.generation {
		return false
	}
	branch := destination.branch
	if !ref_name_has_prefix(ref_name_string(&branch), "refs/heads/") do return false
	derived, resolved := push_destination_from_tracking(destination.remote, destination.tracking)
	return resolved && derived == destination
}

/* push_precondition_is_valid checks one exact source, upstream, remote, and normal operation. */
push_precondition_is_valid :: proc(precondition: Push_Precondition) -> bool {
	if !push_configuration_identity_is_valid(precondition.configuration) ||
	   !ref_identity_is_valid(precondition.source) || precondition.source.kind != .Local_Branch ||
	   !push_destination_is_valid(precondition.destination) ||
	   !tracking_relationship_is_valid(precondition.tracking) ||
	   !head_observation_is_valid(precondition.head) || precondition.head.state != .Symbolic ||
	   precondition.operation != .Normal {
		return false
	}
	remote := precondition.configuration.remote
	return precondition.destination.remote == remote &&
	       precondition.tracking.local == precondition.source &&
	       precondition.tracking.upstream == precondition.destination.tracking &&
	       precondition.source.repository == remote.repository &&
	       precondition.source.generation == remote.generation &&
	       precondition.head.branch.repository == precondition.source.repository &&
	       precondition.head.branch.generation == precondition.source.generation
}

/* push_precondition_prepare derives one destination only from an observed tracking relationship. */
push_precondition_prepare :: proc(
	observation: ^Ref_Observation,
	source: Ref_Identity,
	configuration: Push_Configuration_Identity,
	repository_operation: Operation_State,
) -> (Push_Precondition, bool, Failure_Code) {
	if !ref_identity_is_valid(source) || !push_configuration_identity_is_valid(configuration) {
		return {}, false, .Invalid_Request
	}
	if source.kind != .Local_Branch do return {}, false, .Ref_Unavailable
	if repository_operation != .Normal do return {}, false, .Action_Unavailable
	descriptor, described := ref_observation_descriptor(observation)
	if !described || descriptor.state == .Truncated do return {}, false, .Stale_Observation
	if descriptor.state == .Unborn || descriptor.head.state != .Symbolic {
		return {}, false, .Ref_Unavailable
	}
	remote := configuration.remote
	if descriptor.repository != source.repository || descriptor.repository != remote.repository ||
	   descriptor.generation != source.generation || descriptor.generation != remote.generation {
		return {}, false, .Stale_Observation
	}
	if !push_ref_is_observed(observation, source) do return {}, false, .Ref_Unavailable
	if !push_remote_is_observed(observation, remote) do return {}, false, .Remote_Unavailable
	tracking, tracked := push_tracking_for_source(observation, source)
	if !tracked || tracking.state == .Missing || tracking.state == .Unavailable {
		return {}, false, .Remote_Unavailable
	}
	destination, resolved := push_destination_from_tracking(remote, tracking.upstream)
	if !resolved do return {}, false, .Remote_Unavailable
	precondition := Push_Precondition {
		configuration = configuration,
		source = source,
		destination = destination,
		tracking = tracking,
		head = descriptor.head,
		operation = repository_operation,
	}
	return precondition, push_precondition_is_valid(precondition), .None
}

/* push_confirmation_prepare binds one exact one-shot publication acknowledgement. */
push_confirmation_prepare :: proc(
	precondition: Push_Precondition,
	id: Push_Confirmation_ID,
) -> (Push_Confirmation, bool, Failure_Code) {
	if id == Push_Confirmation_ID(0) || !push_precondition_is_valid(precondition) {
		return {}, false, .Invalid_Request
	}
	return {id = id, precondition = precondition}, true, .None
}

/* push_confirmation_confirm accepts only the exact unused confirmation identity. */
push_confirmation_confirm :: proc(
	confirmation: ^Push_Confirmation,
	id: Push_Confirmation_ID,
) -> (bool, Failure_Code) {
	if confirmation == nil || !push_confirmation_input_is_valid(confirmation^) {
		return false, .Invalid_Request
	}
	if confirmation.id != id || confirmation.confirmed || confirmation.consumed {
		return false, .Confirmation_Mismatch
	}
	confirmation.confirmed = true
	return true, .None
}

/* push_request_prepare consumes one exact confirmation into a closed single-ref request. */
push_request_prepare :: proc(
	precondition: Push_Precondition,
	operation: Push_Operation_ID,
	confirmation: ^Push_Confirmation,
	limits := DEFAULT_PROCESS_LIMITS,
) -> (Push_Request, bool, Failure_Code) {
	if operation == Push_Operation_ID(0) || !push_precondition_is_valid(precondition) ||
	   !process_limits_are_valid(limits) {
		return {}, false, .Invalid_Request
	}
	if confirmation == nil || !confirmation.confirmed do return {}, false, .Confirmation_Required
	if confirmation.consumed || !push_confirmation_input_is_valid(confirmation^) ||
	   confirmation.precondition != precondition {
		return {}, false, .Confirmation_Mismatch
	}
	confirmation.consumed = true
	request := Push_Request {
		operation = operation,
		precondition = precondition,
		confirmation = confirmation.id,
		limits = limits,
	}
	return request, push_request_is_valid(request), .None
}

/* push_request_is_valid checks a closed confirmed request with no force or delete mode. */
push_request_is_valid :: proc(request: Push_Request) -> bool {
	return request.operation != Push_Operation_ID(0) &&
	       request.confirmation != Push_Confirmation_ID(0) &&
	       push_precondition_is_valid(request.precondition) &&
	       process_limits_are_valid(request.limits)
}

/* push_request_revalidate proves the exact observed publication boundary remains current. */
push_request_revalidate :: proc(
	observation: ^Ref_Observation,
	configuration: Push_Configuration_Identity,
	repository_operation: Operation_State,
	request: Push_Request,
) -> (bool, Failure_Code) {
	if !push_request_is_valid(request) || !push_configuration_identity_is_valid(configuration) {
		return false, .Invalid_Request
	}
	if repository_operation != .Normal do return false, .Action_Unavailable
	if configuration != request.precondition.configuration do return false, .Stale_Observation
	descriptor, described := ref_observation_descriptor(observation)
	if !described || descriptor.state == .Truncated || descriptor.state == .Unborn ||
	   descriptor.repository != request.precondition.source.repository ||
	   descriptor.generation != request.precondition.source.generation ||
	   descriptor.head != request.precondition.head {
		return false, .Stale_Observation
	}
	if !push_ref_is_observed(observation, request.precondition.source) do return false, .Ref_Unavailable
	if !push_remote_is_observed(observation, request.precondition.destination.remote) {
		return false, .Remote_Unavailable
	}
	tracking, tracked := push_tracking_for_source(observation, request.precondition.source)
	if !tracked || tracking != request.precondition.tracking do return false, .Stale_Observation
	destination, resolved := push_destination_from_tracking(configuration.remote, tracking.upstream)
	if !resolved || destination != request.precondition.destination do return false, .Stale_Observation
	return true, .None
}

/* push_result_open copies one bounded transport outcome pending refreshed truth. */
push_result_open :: proc(
	request: Push_Request,
	started: bool,
	exit_status: i32,
	output: []u8,
	diagnostic: []u8,
	process_failure := Failure_Code.None,
	allocator := context.allocator,
) -> (Push_Result, bool, Failure_Code) {
	if allocator.procedure == nil || !push_request_is_valid(request) do return {}, false, .Invalid_Request
	if u64(len(output)) > request.limits.stdout_bytes ||
	   u64(len(diagnostic)) > request.limits.diagnostic_bytes {
		return {}, false, .Output_Limit
	}
	if !started && (process_failure != .Cancelled || exit_status != 0 || len(output) != 0 || len(diagnostic) != 0) {
		return {}, false, .Invalid_Request
	}
	failure := process_failure
	if started && failure == .None && exit_status != 0 do failure = .Process_Failed
	state, allocation_error := new(Push_Result_Data, allocator)
	if allocation_error != nil do return {}, false, .Allocation
	state.allocator = allocator
	state.descriptor = {
		request = request,
		started = started,
		exit_status = exit_status,
		output_bytes = u64(len(output)),
		diagnostic_bytes = u64(len(diagnostic)),
		failure = failure,
		transport_succeeded = started && failure == .None && exit_status == 0,
		refresh_required = started,
	}
	state.output, allocation_error = make([dynamic]u8, 0, len(output), allocator)
	if allocation_error == nil do state.diagnostic, allocation_error = make([dynamic]u8, 0, len(diagnostic), allocator)
	if allocation_error == nil && len(output) > 0 do _, allocation_error = append(&state.output, ..output)
	if allocation_error == nil && len(diagnostic) > 0 do _, allocation_error = append(&state.diagnostic, ..diagnostic)
	if allocation_error != nil {
		push_result_data_destroy(state)
		return {}, false, .Allocation
	}
	return Push_Result{state = state}, true, .None
}

/* push_result_verify records fresh Ref truth and permits success only when it proves publication. */
push_result_verify :: proc(
	result: ^Push_Result,
	fresh: ^Ref_Observation,
) -> (bool, Failure_Code) {
	state := push_result_data(result)
	if state == nil || !state.descriptor.started || state.descriptor.verified ||
	   !push_request_is_valid(state.descriptor.request) {
		return false, .Invalid_Request
	}
	descriptor, described := ref_observation_descriptor(fresh)
	before := state.descriptor.request.precondition
	if !described || descriptor.state == .Truncated || descriptor.state == .Unborn ||
	   descriptor.repository != before.source.repository || descriptor.generation == before.source.generation {
		push_result_finish_verification(state, .Stale_Observation)
		return true, .Stale_Observation
	}
	source_after, source_found := push_ref_by_name(fresh, before.source.name, .Local_Branch)
	if !source_found {
		push_result_finish_verification(state, .Ref_Unavailable)
		return true, .Ref_Unavailable
	}
	tracking_after, tracked := push_tracking_for_source(fresh, source_after)
	if !tracked {
		push_result_finish_verification(state, .Remote_Unavailable)
		return true, .Remote_Unavailable
	}
	remote_after, remote_found := push_remote_by_name(fresh, before.destination.remote.name)
	if !remote_found {
		push_result_finish_verification(state, .Remote_Unavailable)
		return true, .Remote_Unavailable
	}
	destination_after, resolved := push_destination_from_tracking(remote_after, tracking_after.upstream)
	if !resolved || destination_after.branch != before.destination.branch {
		push_result_finish_verification(state, .Stale_Observation)
		return true, .Stale_Observation
	}
	state.descriptor.lineage = {
		source_before = before.source,
		tracking_before = before.tracking,
		source_after = source_after,
		tracking_after = tracking_after,
	}
	state.descriptor.verified = true
	if source_after.object != before.source.object {
		state.descriptor.failure = .Stale_Observation
		state.descriptor.succeeded = false
		return true, .Stale_Observation
	}
	if state.descriptor.transport_succeeded &&
	   push_lineage_supports_publication(state.descriptor.lineage, before.destination) {
		state.descriptor.failure = .None
		state.descriptor.succeeded = true
		return true, .None
	}
	if state.descriptor.failure == .None do state.descriptor.failure = .Process_Failed
	state.descriptor.succeeded = false
	return true, state.descriptor.failure
}

/* push_result_descriptor returns copied immutable push outcome metadata. */
push_result_descriptor :: proc(result: ^Push_Result) -> (Push_Result_Descriptor, bool) {
	state := push_result_data(result)
	if state == nil do return {}, false
	return state.descriptor, push_result_descriptor_is_valid(state.descriptor)
}

/* push_result_descriptor_is_valid checks cancellation, refresh, and verified-success invariants. */
push_result_descriptor_is_valid :: proc(descriptor: Push_Result_Descriptor) -> bool {
	if !push_request_is_valid(descriptor.request) ||
	   descriptor.output_bytes > descriptor.request.limits.stdout_bytes ||
	   descriptor.diagnostic_bytes > descriptor.request.limits.diagnostic_bytes {
		return false
	}
	if !descriptor.started {
		return !descriptor.verified && descriptor.lineage == {} && descriptor.exit_status == 0 &&
		       descriptor.failure == .Cancelled && !descriptor.transport_succeeded && !descriptor.succeeded &&
		       !descriptor.refresh_required
	}
	if !descriptor.refresh_required || descriptor.transport_succeeded && descriptor.exit_status != 0 do return false
	if !descriptor.verified &&
	   descriptor.transport_succeeded != (descriptor.exit_status == 0 && descriptor.failure == .None) {
		return false
	}
	if !descriptor.verified do return descriptor.lineage == {} && !descriptor.succeeded
	if descriptor.succeeded {
		return descriptor.transport_succeeded && descriptor.failure == .None &&
		       push_lineage_supports_publication(descriptor.lineage, descriptor.request.precondition.destination)
	}
	return descriptor.failure != .None
}

/* push_result_usage reports exact copied public result payload sizes. */
push_result_usage :: proc(result: ^Push_Result) -> (Push_Usage, bool) {
	state := push_result_data(result)
	if state == nil do return {}, false
	return {output_bytes = u64(len(state.output)), diagnostic_bytes = u64(len(state.diagnostic))}, true
}

/* push_result_output returns borrowed bounded public process output and diagnostics. */
push_result_output :: proc(result: ^Push_Result) -> (output, diagnostic: []u8, ok: bool) {
	state := push_result_data(result)
	if state == nil do return nil, nil, false
	return state.output[:], state.diagnostic[:], true
}

/* push_result_close releases every owned push result allocation. */
push_result_close :: proc(result: ^Push_Result) {
	state := push_result_data(result)
	if state == nil do return
	push_result_data_destroy(state)
	result^ = {}
}

/* push_feedback maps checked push state to stable application feedback. */
push_feedback :: proc(descriptor: Push_Result_Descriptor) -> Push_Feedback {
	if !push_result_descriptor_is_valid(descriptor) do return .Invalid
	if !descriptor.started do return .Cancelled
	if !descriptor.verified do return .Refreshing
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
push_confirmation_input_is_valid :: proc(confirmation: Push_Confirmation) -> bool {
	return confirmation.id != Push_Confirmation_ID(0) &&
	       push_precondition_is_valid(confirmation.precondition) &&
	       !(confirmation.consumed && !confirmation.confirmed)
}

@(private)
push_ref_is_observed :: proc(observation: ^Ref_Observation, wanted: Ref_Identity) -> bool {
	count, available := ref_observation_ref_count(observation)
	if !available do return false
	for ordinal in 0 ..< count {
		candidate, found := ref_observation_ref(observation, ordinal)
		if found && candidate == wanted do return true
	}
	return false
}

@(private)
push_remote_is_observed :: proc(observation: ^Ref_Observation, wanted: Remote_Identity) -> bool {
	count, available := ref_observation_remote_count(observation)
	if !available do return false
	for ordinal in 0 ..< count {
		candidate, found := ref_observation_remote(observation, ordinal)
		if found && candidate == wanted do return true
	}
	return false
}

@(private)
push_remote_by_name :: proc(
	observation: ^Ref_Observation,
	name: Remote_Name,
) -> (Remote_Identity, bool) {
	count, available := ref_observation_remote_count(observation)
	if !available do return {}, false
	for ordinal in 0 ..< count {
		candidate, found := ref_observation_remote(observation, ordinal)
		if found && candidate.name == name do return candidate, true
	}
	return {}, false
}

@(private)
push_tracking_for_source :: proc(
	observation: ^Ref_Observation,
	source: Ref_Identity,
) -> (Tracking_Relationship, bool) {
	descriptor, described := ref_observation_descriptor(observation)
	if !described do return {}, false
	for ordinal in 0 ..< descriptor.tracking_relationships {
		tracking, found := ref_observation_tracking(observation, ordinal)
		if found && tracking.local == source do return tracking, true
	}
	return {}, false
}

@(private)
push_ref_by_name :: proc(
	observation: ^Ref_Observation,
	name: Ref_Name,
	kind: Ref_Kind,
) -> (Ref_Identity, bool) {
	count, available := ref_observation_ref_count(observation)
	if !available do return {}, false
	for ordinal in 0 ..< count {
		candidate, found := ref_observation_ref(observation, ordinal)
		if found && candidate.kind == kind && candidate.name == name do return candidate, true
	}
	return {}, false
}

@(private)
push_destination_from_tracking :: proc(
	remote: Remote_Identity,
	tracking: Ref_Identity,
) -> (Push_Destination, bool) {
	if !remote_identity_is_valid(remote) || !ref_identity_is_valid(tracking) ||
	   tracking.kind != .Remote_Tracking_Branch || tracking.repository != remote.repository ||
	   tracking.generation != remote.generation {
		return {}, false
	}
	prefix_storage: [MAX_REF_NAME_BYTES]u8
	prefix, prefix_ready := push_remote_tracking_prefix(remote, &prefix_storage)
	tracking_name := tracking.name
	tracking_text := ref_name_string(&tracking_name)
	if !prefix_ready || len(tracking_text) <= len(prefix) || tracking_text[:len(prefix)] != prefix {
		return {}, false
	}
	suffix := tracking_text[len(prefix):]
	branch_prefix := "refs/heads/"
	if len(branch_prefix) + len(suffix) > MAX_REF_NAME_BYTES do return {}, false
	branch_storage: [MAX_REF_NAME_BYTES]u8
	copy(branch_storage[:len(branch_prefix)], transmute([]u8)branch_prefix)
	copy(branch_storage[len(branch_prefix):len(branch_prefix) + len(suffix)], transmute([]u8)suffix)
	branch: Ref_Name
	if !ref_name_assign(&branch, string(branch_storage[:len(branch_prefix) + len(suffix)])) do return {}, false
	return {remote = remote, branch = branch, tracking = tracking}, true
}

@(private)
push_remote_tracking_prefix :: proc(
	remote: Remote_Identity,
	storage: ^[MAX_REF_NAME_BYTES]u8,
) -> (string, bool) {
	if storage == nil || !remote_identity_is_valid(remote) do return "", false
	remote_name := remote.name
	name := remote_name_string(&remote_name)
	prefix := "refs/remotes/"
	required := len(prefix) + len(name) + 1
	if required >= len(storage^) do return "", false
	copy(storage^[:len(prefix)], transmute([]u8)prefix)
	copy(storage^[len(prefix):len(prefix) + len(name)], transmute([]u8)name)
	storage^[required - 1] = '/'
	return string(storage^[:required]), true
}

@(private)
push_lineage_supports_publication :: proc(
	lineage: Push_Lineage,
	destination: Push_Destination,
) -> bool {
	if !ref_identity_is_valid(lineage.source_before) ||
	   !tracking_relationship_is_valid(lineage.tracking_before) ||
	   !ref_identity_is_valid(lineage.source_after) ||
	   !tracking_relationship_is_valid(lineage.tracking_after) ||
	   !push_destination_is_valid(destination) {
		return false
	}
	if lineage.tracking_before.local != lineage.source_before ||
	   lineage.tracking_before.upstream != destination.tracking ||
	   lineage.tracking_after.local != lineage.source_after ||
	   lineage.source_after.repository != lineage.source_before.repository ||
	   lineage.source_after.generation == lineage.source_before.generation ||
	   lineage.source_after.name != lineage.source_before.name ||
	   lineage.source_after.object != lineage.source_before.object ||
	   lineage.tracking_after.state != .Equal ||
	   lineage.tracking_after.upstream.object != lineage.source_before.object {
		return false
	}
	derived, resolved := push_destination_from_tracking(
		Remote_Identity {
			repository = destination.remote.repository,
			generation = lineage.source_after.generation,
			name = destination.remote.name,
		},
		lineage.tracking_after.upstream,
	)
	return resolved && derived.branch == destination.branch
}

@(private)
push_result_finish_verification :: proc(state: ^Push_Result_Data, failure: Failure_Code) {
	if state == nil do return
	state.descriptor.verified = true
	state.descriptor.failure = failure
	state.descriptor.succeeded = false
}

@(private)
push_result_data :: proc(result: ^Push_Result) -> ^Push_Result_Data {
	if result == nil || result.state == nil do return nil
	return cast(^Push_Result_Data)result.state
}

@(private)
push_result_data_destroy :: proc(state: ^Push_Result_Data) {
	if state == nil do return
	delete(state.output)
	delete(state.diagnostic)
	free(state, state.allocator)
}
