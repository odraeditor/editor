// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery

import "base:runtime"
import "core:strings"
import "core:unicode/utf8"

/* MAX_LOCAL_TAG_NAME_BYTES bounds one user-supplied local tag name without the refs/tags prefix. */
MAX_LOCAL_TAG_NAME_BYTES :: 240
LOCAL_TAG_REF_PREFIX :: "refs/tags/"

/* Tag_Operation_ID identifies one admitted local tag mutation attempt. */
Tag_Operation_ID :: distinct u64

/* Tag_Confirmation_ID identifies one explicit local tag mutation confirmation. */
Tag_Confirmation_ID :: distinct u64

/* Tag_Operation selects one closed local tag mutation family. */
Tag_Operation :: enum u8 {
	Invalid,
	Create,
	Delete,
}

/* Local_Tag_Name owns one validated complete refs/tags name derived from bounded user input. */
Local_Tag_Name :: struct {
	reference: Ref_Name,
}

/* Tag_Intent binds one operation to its exact selected target and optional new local tag name. */
Tag_Intent :: struct {
	operation: Tag_Operation,
	target:    Ref_Identity,
	name:      Local_Tag_Name,
}

/* Tag_Precondition binds Ref, Status, and repository-operation truth to one local tag intent. */
Tag_Precondition :: struct {
	repository:           Repository_Context,
	status_generation:    Observation_Generation,
	ref_generation:       Ref_Generation,
	repository_operation: Operation_State,
	intent:               Tag_Intent,
}

/* Tag_Confirmation owns one one-shot acknowledgement of an exact local tag mutation. */
Tag_Confirmation :: struct {
	id:           Tag_Confirmation_ID,
	precondition: Tag_Precondition,
	confirmed:    bool,
	consumed:     bool,
}

/* Tag_Request is one closed confirmed local tag operation with no signing, force, or remote mode. */
Tag_Request :: struct {
	operation:    Tag_Operation_ID,
	precondition: Tag_Precondition,
	confirmation: Tag_Confirmation_ID,
	limits:       Process_Limits,
}

/* Tag_Lineage records the exact selected target and resulting local tag identity. */
Tag_Lineage :: struct {
	target_before: Ref_Identity,
	tag_before:    Ref_Identity,
	tag_after:     Ref_Identity,
}

/* Tag_Result_Descriptor separates process completion from refreshed local tag truth. */
Tag_Result_Descriptor :: struct {
	request:           Tag_Request,
	lineage:           Tag_Lineage,
	started:           bool,
	verified:          bool,
	exit_status:       i32,
	output_bytes:      u64,
	diagnostic_bytes:  u64,
	failure:           Failure_Code,
	process_succeeded: bool,
	succeeded:         bool,
	refresh_required:  bool,
}

/* Tag_Usage reports exact retained public result payload sizes. */
Tag_Usage :: struct {
	output_bytes:     u64,
	diagnostic_bytes: u64,
}

/* Tag_Result owns copied bounded local tag process output. */
Tag_Result :: struct {
	state: rawptr,
}

@(private)
Tag_Result_Data :: struct {
	descriptor: Tag_Result_Descriptor,
	output:     [dynamic]u8,
	diagnostic: [dynamic]u8,
	allocator:  runtime.Allocator,
}

/* Tag_Feedback classifies stable local tag admission, refresh, and terminal outcomes. */
Tag_Feedback :: enum u8 {
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

/* local_tag_name_assign validates bounded user input and derives one complete refs/tags name. */
local_tag_name_assign :: proc(name: ^Local_Tag_Name, text: string) -> bool {
	if name == nil do return false
	name^ = {}
	if !local_tag_short_name_is_valid(text) do return false
	prefix := LOCAL_TAG_REF_PREFIX
	storage: [len(LOCAL_TAG_REF_PREFIX) + MAX_LOCAL_TAG_NAME_BYTES]u8
	copy(storage[:len(prefix)], transmute([]u8)prefix)
	copy(storage[len(prefix):len(prefix) + len(text)], transmute([]u8)text)
	return ref_name_assign(&name.reference, string(storage[:len(prefix) + len(text)]))
}

/* local_tag_name_is_valid checks one owned complete local tag name. */
local_tag_name_is_valid :: proc(name: Local_Tag_Name) -> bool {
	if !ref_name_is_valid(name.reference) do return false
	copy := name
	full := ref_name_string(&copy.reference)
	prefix := "refs/tags/"
	return ref_name_has_prefix(full, prefix) && local_tag_short_name_is_valid(full[len(prefix):])
}

/* local_tag_name_string returns the bounded user-visible tag name without refs/tags. */
local_tag_name_string :: proc(name: ^Local_Tag_Name) -> string {
	if name == nil || !local_tag_name_is_valid(name^) do return ""
	full := ref_name_string(&name.reference)
	return full[len("refs/tags/"):]
}

/* tag_intent_is_valid checks the closed operation-specific target and name shape. */
tag_intent_is_valid :: proc(intent: Tag_Intent) -> bool {
	if !ref_identity_is_valid(intent.target) do return false
	switch intent.operation {
	case .Create:
		return intent.target.object_type == .Commit && local_tag_name_is_valid(intent.name)
	case .Delete:
		return intent.target.kind == .Tag && intent.name == {}
	case .Invalid:
		return false
	}
	return false
}

/* tag_precondition_is_valid checks the complete mode-specific mutation boundary. */
tag_precondition_is_valid :: proc(precondition: Tag_Precondition) -> bool {
	if !repository_context_is_valid(precondition.repository) ||
	   precondition.status_generation == Observation_Generation(0) ||
	   precondition.ref_generation == Ref_Generation(0) ||
	   precondition.repository_operation != .Normal || !tag_intent_is_valid(precondition.intent) {
		return false
	}
	return precondition.intent.target.repository == precondition.repository &&
	       precondition.intent.target.generation == precondition.ref_generation
}

/* tag_precondition_prepare derives one exact mode-specific boundary from current Status and Ref observations. */
tag_precondition_prepare :: proc(
	status: ^Status_Observation,
	refs: ^Ref_Observation,
	intent: Tag_Intent,
) -> (Tag_Precondition, bool, Failure_Code) {
	if !tag_intent_is_valid(intent) do return {}, false, .Invalid_Request
	status_descriptor, status_described := status_observation_descriptor(status)
	ref_descriptor, refs_described := ref_observation_descriptor(refs)
	if !status_described || !refs_described || ref_descriptor.state == .Truncated {
		return {}, false, .Stale_Observation
	}
	if status_descriptor.repository != ref_descriptor.repository || ref_descriptor.state != .Available {
		return {}, false, .Ref_Unavailable
	}
	if status_descriptor.operation != .Normal do return {}, false, .Action_Unavailable
	if !tag_ref_is_observed(refs, intent.target) do return {}, false, .Ref_Unavailable
	if intent.operation == .Create {
		if intent.target.object_type != .Commit do return {}, false, .Action_Unavailable
		if tag_ref_name_is_observed(refs, intent.name.reference) do return {}, false, .Target_Duplicate
	}
	precondition := Tag_Precondition {
		repository = status_descriptor.repository,
		status_generation = status_descriptor.generation,
		ref_generation = ref_descriptor.generation,
		repository_operation = status_descriptor.operation,
		intent = intent,
	}
	return precondition, tag_precondition_is_valid(precondition), .None
}

/* tag_confirmation_prepare binds one explicit one-shot confirmation to exact local tag truth. */
tag_confirmation_prepare :: proc(
	precondition: Tag_Precondition,
	id: Tag_Confirmation_ID,
) -> (Tag_Confirmation, bool, Failure_Code) {
	if id == Tag_Confirmation_ID(0) || !tag_precondition_is_valid(precondition) {
		return {}, false, .Invalid_Request
	}
	return {id = id, precondition = precondition}, true, .None
}

/* tag_confirmation_confirm accepts only the exact unused confirmation identity. */
tag_confirmation_confirm :: proc(
	confirmation: ^Tag_Confirmation,
	id: Tag_Confirmation_ID,
) -> (bool, Failure_Code) {
	if confirmation == nil || !tag_confirmation_input_is_valid(confirmation^) {
		return false, .Invalid_Request
	}
	if confirmation.id != id || confirmation.confirmed || confirmation.consumed {
		return false, .Confirmation_Mismatch
	}
	confirmation.confirmed = true
	return true, .None
}

/* tag_request_prepare consumes one exact confirmation into a closed lightweight-tag request. */
tag_request_prepare :: proc(
	precondition: Tag_Precondition,
	operation: Tag_Operation_ID,
	confirmation: ^Tag_Confirmation,
	limits := DEFAULT_PROCESS_LIMITS,
) -> (Tag_Request, bool, Failure_Code) {
	if operation == Tag_Operation_ID(0) || !tag_precondition_is_valid(precondition) ||
	   !process_limits_are_valid(limits) {
		return {}, false, .Invalid_Request
	}
	if confirmation == nil || !confirmation.confirmed do return {}, false, .Confirmation_Required
	if confirmation.consumed || !tag_confirmation_input_is_valid(confirmation^) ||
	   confirmation.precondition != precondition {
		return {}, false, .Confirmation_Mismatch
	}
	confirmation.consumed = true
	request := Tag_Request {
		operation = operation,
		precondition = precondition,
		confirmation = confirmation.id,
		limits = limits,
	}
	return request, tag_request_is_valid(request), .None
}

/* tag_request_is_valid checks one closed confirmed request without signing, force, or remote modes. */
tag_request_is_valid :: proc(request: Tag_Request) -> bool {
	return request.operation != Tag_Operation_ID(0) && request.confirmation != Tag_Confirmation_ID(0) &&
	       tag_precondition_is_valid(request.precondition) && process_limits_are_valid(request.limits)
}

/* tag_request_revalidate proves the exact Status and Ref boundary remains current before start. */
tag_request_revalidate :: proc(
	status: ^Status_Observation,
	refs: ^Ref_Observation,
	request: Tag_Request,
) -> (bool, Failure_Code) {
	if !tag_request_is_valid(request) do return false, .Invalid_Request
	current, prepared, failure := tag_precondition_prepare(status, refs, request.precondition.intent)
	if !prepared do return false, failure
	if current != request.precondition do return false, .Stale_Observation
	return true, .None
}

/* tag_result_open copies one bounded process outcome pending refreshed repository truth. */
tag_result_open :: proc(
	request: Tag_Request,
	started: bool,
	exit_status: i32,
	output: []u8,
	diagnostic: []u8,
	process_failure := Failure_Code.None,
	allocator := context.allocator,
) -> (Tag_Result, bool, Failure_Code) {
	if allocator.procedure == nil || !tag_request_is_valid(request) do return {}, false, .Invalid_Request
	if u64(len(output)) > request.limits.stdout_bytes ||
	   u64(len(diagnostic)) > request.limits.diagnostic_bytes {
		return {}, false, .Output_Limit
	}
	if !started && (process_failure != .Cancelled || exit_status != 0 || len(output) != 0 || len(diagnostic) != 0) {
		return {}, false, .Invalid_Request
	}
	failure := process_failure
	if started && failure == .None && exit_status != 0 do failure = .Process_Failed
	state, allocation_error := new(Tag_Result_Data, allocator)
	if allocation_error != nil do return {}, false, .Allocation
	state.allocator = allocator
	state.descriptor = {
		request = request,
		started = started,
		exit_status = exit_status,
		output_bytes = u64(len(output)),
		diagnostic_bytes = u64(len(diagnostic)),
		failure = failure,
		process_succeeded = started && failure == .None && exit_status == 0,
		refresh_required = started,
	}
	state.output, allocation_error = make([dynamic]u8, 0, len(output), allocator)
	if allocation_error == nil do state.diagnostic, allocation_error = make([dynamic]u8, 0, len(diagnostic), allocator)
	if allocation_error == nil && len(output) > 0 do _, allocation_error = append(&state.output, ..output)
	if allocation_error == nil && len(diagnostic) > 0 do _, allocation_error = append(&state.diagnostic, ..diagnostic)
	if allocation_error != nil {
		tag_result_data_destroy(state)
		return {}, false, .Allocation
	}
	return Tag_Result{state = state}, true, .None
}

/* tag_result_verify records fresh Ref truth and permits success only for the requested mutation. */
tag_result_verify :: proc(result: ^Tag_Result, fresh_refs: ^Ref_Observation) -> (bool, Failure_Code) {
	state := tag_result_data(result)
	if state == nil || !state.descriptor.started || state.descriptor.verified ||
	   !tag_request_is_valid(state.descriptor.request) {
		return false, .Invalid_Request
	}
	ref_descriptor, described := ref_observation_descriptor(fresh_refs)
	before := state.descriptor.request.precondition
	if !described || ref_descriptor.state != .Available ||
	   ref_descriptor.repository != before.repository || ref_descriptor.generation == before.ref_generation {
		tag_result_finish_verification(state, .Stale_Observation)
		return true, .Stale_Observation
	}
	intent := before.intent
	state.descriptor.lineage.target_before = intent.target
	verified := false
	switch intent.operation {
	case .Create:
		tag, found := tag_ref_by_name(fresh_refs, intent.name.reference)
		if found {
			state.descriptor.lineage.tag_after = tag
			verified = tag.object == intent.target.object && tag.object_type == intent.target.object_type
		}
	case .Delete:
		state.descriptor.lineage.tag_before = intent.target
		_, found := tag_ref_by_name(fresh_refs, intent.target.name)
		verified = !found
	case .Invalid:
	}
	state.descriptor.verified = true
	if state.descriptor.process_succeeded && verified {
		state.descriptor.failure = .None
		state.descriptor.succeeded = true
		return true, .None
	}
	if state.descriptor.failure == .None do state.descriptor.failure = .Process_Failed
	state.descriptor.succeeded = false
	return true, state.descriptor.failure
}

/* tag_result_descriptor returns copied immutable local tag outcome metadata. */
tag_result_descriptor :: proc(result: ^Tag_Result) -> (Tag_Result_Descriptor, bool) {
	state := tag_result_data(result)
	if state == nil do return {}, false
	return state.descriptor, tag_result_descriptor_is_valid(state.descriptor)
}

/* tag_result_descriptor_is_valid checks cancellation, refresh, and verified-success invariants. */
tag_result_descriptor_is_valid :: proc(descriptor: Tag_Result_Descriptor) -> bool {
	if !tag_request_is_valid(descriptor.request) ||
	   descriptor.output_bytes > descriptor.request.limits.stdout_bytes ||
	   descriptor.diagnostic_bytes > descriptor.request.limits.diagnostic_bytes {
		return false
	}
	if !descriptor.started {
		return !descriptor.verified && descriptor.lineage == {} && descriptor.exit_status == 0 &&
		       descriptor.failure == .Cancelled && !descriptor.process_succeeded && !descriptor.succeeded &&
		       !descriptor.refresh_required
	}
	if !descriptor.refresh_required || descriptor.process_succeeded && descriptor.exit_status != 0 do return false
	if !descriptor.verified {
		return descriptor.lineage == {} && !descriptor.succeeded &&
		       descriptor.process_succeeded == (descriptor.exit_status == 0 && descriptor.failure == .None)
	}
	if descriptor.succeeded do return descriptor.process_succeeded && descriptor.failure == .None
	return descriptor.failure != .None
}

/* tag_result_usage reports exact copied public result payload sizes. */
tag_result_usage :: proc(result: ^Tag_Result) -> (Tag_Usage, bool) {
	state := tag_result_data(result)
	if state == nil do return {}, false
	return {output_bytes = u64(len(state.output)), diagnostic_bytes = u64(len(state.diagnostic))}, true
}

/* tag_result_output returns borrowed bounded public process output and diagnostics. */
tag_result_output :: proc(result: ^Tag_Result) -> (output, diagnostic: []u8, ok: bool) {
	state := tag_result_data(result)
	if state == nil do return nil, nil, false
	return state.output[:], state.diagnostic[:], true
}

/* tag_result_close releases every owned local tag result allocation. */
tag_result_close :: proc(result: ^Tag_Result) {
	state := tag_result_data(result)
	if state == nil do return
	tag_result_data_destroy(state)
	result^ = {}
}

/* tag_feedback maps checked local tag state to stable application feedback. */
tag_feedback :: proc(descriptor: Tag_Result_Descriptor) -> Tag_Feedback {
	if !tag_result_descriptor_is_valid(descriptor) do return .Invalid
	if !descriptor.started do return .Cancelled
	if !descriptor.verified do return .Refreshing
	if descriptor.succeeded do return .Completed
	#partial switch descriptor.failure {
	case .Stale_Observation: return .Stale
	case .Ref_Unavailable, .Action_Unavailable, .Presentation_Unavailable: return .Unavailable
	case .Invalid_Context, .Invalid_Limits, .Invalid_Request, .Target_Duplicate,
	     .Confirmation_Required, .Confirmation_Mismatch: return .Rejected
	case .Output_Limit, .Ref_Limit, .Ref_Metadata_Limit, .Ref_Temporary_Limit, .Ref_Truncated: return .Limited
	case .Timeout: return .Timed_Out
	case .Cancelled: return .Cancelled
	case .Executable_Unavailable, .Process_Failed, .Parse, .Allocation, .Cleanup: return .Failed
	case .Modified_Buffer: return .Unavailable
	case .None: return .Failed
	case:
		return .Unavailable
	}
}

@(private)
local_tag_short_name_is_valid :: proc(text: string) -> bool {
	if len(text) == 0 || len(text) > MAX_LOCAL_TAG_NAME_BYTES || text == "@" || !utf8.valid_string(text) ||
	   text[0] == '/' || text[len(text) - 1] == '/' || text[len(text) - 1] == '.' ||
	   strings.contains(text, "..") || strings.contains(text, "@{") || strings.contains(text, "//") ||
	   strings.contains(text, "./") || strings.contains(text, ".lock/") || strings.has_suffix(text, ".lock") {
		return false
	}
	component_start := true
	for byte in transmute([]u8)text {
		if byte <= 0x20 || byte == 0x7f || byte == '~' || byte == '^' || byte == ':' ||
		   byte == '?' || byte == '*' || byte == '[' || byte == '\\' {
			return false
		}
		if component_start && byte == '.' do return false
		component_start = byte == '/'
	}
	return true
}

@(private)
tag_confirmation_input_is_valid :: proc(confirmation: Tag_Confirmation) -> bool {
	return confirmation.id != Tag_Confirmation_ID(0) &&
	       tag_precondition_is_valid(confirmation.precondition) &&
	       !(confirmation.consumed && !confirmation.confirmed)
}

@(private)
tag_ref_is_observed :: proc(observation: ^Ref_Observation, wanted: Ref_Identity) -> bool {
	count, available := ref_observation_ref_count(observation)
	if !available do return false
	for ordinal in 0 ..< count {
		candidate, found := ref_observation_ref(observation, ordinal)
		if found && candidate == wanted do return true
	}
	return false
}

@(private)
tag_ref_name_is_observed :: proc(observation: ^Ref_Observation, wanted: Ref_Name) -> bool {
	_, found := tag_ref_by_name(observation, wanted)
	return found
}

@(private)
tag_ref_by_name :: proc(observation: ^Ref_Observation, wanted: Ref_Name) -> (Ref_Identity, bool) {
	if !ref_name_is_valid(wanted) do return {}, false
	count, available := ref_observation_ref_count(observation)
	if !available do return {}, false
	for ordinal in 0 ..< count {
		candidate, found := ref_observation_ref(observation, ordinal)
		if found && candidate.kind == .Tag && candidate.name == wanted do return candidate, true
	}
	return {}, false
}

@(private)
tag_result_finish_verification :: proc(state: ^Tag_Result_Data, failure: Failure_Code) {
	if state == nil do return
	state.descriptor.verified = true
	state.descriptor.succeeded = false
	state.descriptor.failure = failure
}

@(private)
tag_result_data :: proc(result: ^Tag_Result) -> ^Tag_Result_Data {
	if result == nil || result.state == nil do return nil
	return cast(^Tag_Result_Data)result.state
}

@(private)
tag_result_data_destroy :: proc(state: ^Tag_Result_Data) {
	if state == nil do return
	allocator := state.allocator
	if state.output != nil do delete(state.output)
	if state.diagnostic != nil do delete(state.diagnostic)
	free(state, allocator)
}
