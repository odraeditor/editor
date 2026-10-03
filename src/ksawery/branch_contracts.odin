// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery

import "base:runtime"
import "core:strings"
import "core:unicode/utf8"

/* MAX_LOCAL_BRANCH_NAME_BYTES bounds one user-supplied local branch name without the refs/heads prefix. */
MAX_LOCAL_BRANCH_NAME_BYTES :: 240
LOCAL_BRANCH_REF_PREFIX :: "refs/heads/"
/* MAX_BRANCH_EDITOR_RESOURCES bounds repository-associated editor resources inspected before a worktree transition. */
MAX_BRANCH_EDITOR_RESOURCES :: u32(4_096)

/* Branch_Operation_ID identifies one admitted local branch mutation attempt. */
Branch_Operation_ID :: distinct u64

/* Branch_Confirmation_ID identifies one explicit local branch mutation confirmation. */
Branch_Confirmation_ID :: distinct u64

/* Branch_Operation selects one closed local branch mutation family. */
Branch_Operation :: enum u8 {
	Invalid,
	Create,
	Switch,
	Rename,
	Delete,
}

/* Local_Branch_Name owns one validated complete refs/heads name derived from bounded user input. */
Local_Branch_Name :: struct {
	reference: Ref_Name,
}

/* Branch_Editor_State summarizes retained repository resources relevant to worktree replacement. */
Branch_Editor_State :: struct {
	repository_resources:          u32,
	modified_repository_resources: u32,
}

/* Branch_Intent binds one operation to its exact selected target and optional new local name. */
Branch_Intent :: struct {
	operation:      Branch_Operation,
	selected:       Ref_Identity,
	name:           Local_Branch_Name,
	require_merged_to_head: bool,
}

/* Branch_Precondition binds Ref, Status, worktree, index, and editor truth to one local branch intent. */
Branch_Precondition :: struct {
	repository:      Repository_Context,
	status_generation: Observation_Generation,
	ref_generation:  Ref_Generation,
	head:            Head_Observation,
	repository_operation: Operation_State,
	worktree_paths:  u32,
	unmerged_paths:  u32,
	editor:          Branch_Editor_State,
	intent:          Branch_Intent,
}

/* Branch_Confirmation owns one one-shot acknowledgement of an exact local branch mutation. */
Branch_Confirmation :: struct {
	id:           Branch_Confirmation_ID,
	precondition: Branch_Precondition,
	confirmed:    bool,
	consumed:     bool,
}

/* Branch_Request is one closed confirmed local branch operation with no force mode. */
Branch_Request :: struct {
	operation:    Branch_Operation_ID,
	precondition: Branch_Precondition,
	confirmation: Branch_Confirmation_ID,
	limits:       Process_Limits,
}

/* Branch_Lineage records checked HEAD and target identity before and after one started operation. */
Branch_Lineage :: struct {
	head_before:   Head_Observation,
	head_after:    Head_Observation,
	target_before: Ref_Identity,
	target_after:  Ref_Identity,
}

/* Branch_Result_Descriptor separates process completion from refreshed branch truth. */
Branch_Result_Descriptor :: struct {
	request:          Branch_Request,
	lineage:          Branch_Lineage,
	started:          bool,
	verified:         bool,
	exit_status:      i32,
	output_bytes:     u64,
	diagnostic_bytes: u64,
	failure:          Failure_Code,
	process_succeeded: bool,
	succeeded:        bool,
	refresh_required: bool,
}

/* Branch_Usage reports exact retained public result payload sizes. */
Branch_Usage :: struct {
	output_bytes:     u64,
	diagnostic_bytes: u64,
}

/* Branch_Result owns copied bounded local branch process output. */
Branch_Result :: struct {
	state: rawptr,
}

@(private)
Branch_Result_Data :: struct {
	descriptor: Branch_Result_Descriptor,
	output:     [dynamic]u8,
	diagnostic: [dynamic]u8,
	allocator:  runtime.Allocator,
}

/* Branch_Feedback classifies stable local branch admission, refresh, and terminal outcomes. */
Branch_Feedback :: enum u8 {
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

/* local_branch_name_assign validates bounded user input and derives one complete refs/heads name. */
local_branch_name_assign :: proc(name: ^Local_Branch_Name, text: string) -> bool {
	if name == nil do return false
	name^ = {}
	if !local_branch_short_name_is_valid(text) do return false
	prefix := LOCAL_BRANCH_REF_PREFIX
	storage: [len(LOCAL_BRANCH_REF_PREFIX) + MAX_LOCAL_BRANCH_NAME_BYTES]u8
	copy(storage[:len(prefix)], transmute([]u8)prefix)
	copy(storage[len(prefix):len(prefix) + len(text)], transmute([]u8)text)
	return ref_name_assign(&name.reference, string(storage[:len(prefix) + len(text)]))
}

/* local_branch_name_is_valid checks one owned complete local branch name. */
local_branch_name_is_valid :: proc(name: Local_Branch_Name) -> bool {
	if !ref_name_is_valid(name.reference) do return false
	copy := name
	full := ref_name_string(&copy.reference)
	prefix := "refs/heads/"
	return ref_name_has_prefix(full, prefix) && local_branch_short_name_is_valid(full[len(prefix):])
}

/* local_branch_name_string returns the bounded user-visible branch name without refs/heads. */
local_branch_name_string :: proc(name: ^Local_Branch_Name) -> string {
	if name == nil || !local_branch_name_is_valid(name^) do return ""
	full := ref_name_string(&name.reference)
	return full[len("refs/heads/"):]
}

/* branch_editor_state_is_valid bounds retained repository resource counts. */
branch_editor_state_is_valid :: proc(state: Branch_Editor_State) -> bool {
	return state.repository_resources <= MAX_BRANCH_EDITOR_RESOURCES &&
	       state.modified_repository_resources <= state.repository_resources
}

/* branch_intent_is_valid checks the closed operation-specific target and name shape. */
branch_intent_is_valid :: proc(intent: Branch_Intent) -> bool {
	switch intent.operation {
	case .Create:
		return intent.selected == {} && local_branch_name_is_valid(intent.name) && !intent.require_merged_to_head
	case .Switch:
		return ref_identity_is_valid(intent.selected) && intent.selected.kind == .Local_Branch &&
		       intent.name == {} && !intent.require_merged_to_head
	case .Rename:
		return ref_identity_is_valid(intent.selected) && intent.selected.kind == .Local_Branch &&
		       local_branch_name_is_valid(intent.name) && !intent.require_merged_to_head
	case .Delete:
		return ref_identity_is_valid(intent.selected) && intent.selected.kind == .Local_Branch &&
		       intent.name == {}
	case .Invalid:
		return false
	}
	return false
}

/* branch_precondition_is_valid checks the complete mode-specific mutation boundary. */
branch_precondition_is_valid :: proc(precondition: Branch_Precondition) -> bool {
	if !repository_context_is_valid(precondition.repository) ||
	   precondition.status_generation == Observation_Generation(0) ||
	   precondition.ref_generation == Ref_Generation(0) ||
	   !head_observation_is_valid(precondition.head) || precondition.head.state != .Symbolic ||
	   precondition.repository_operation != .Normal ||
	   precondition.worktree_paths > MAX_STATUS_PATHS || precondition.unmerged_paths > precondition.worktree_paths ||
	   !branch_editor_state_is_valid(precondition.editor) || !branch_intent_is_valid(precondition.intent) {
		return false
	}
	if precondition.head.branch.repository != precondition.repository ||
	   precondition.head.branch.generation != precondition.ref_generation {
		return false
	}
	intent := precondition.intent
	if intent.selected != {} && (intent.selected.repository != precondition.repository ||
	   intent.selected.generation != precondition.ref_generation) {
		return false
	}
	switch intent.operation {
	case .Create:
		return true
	case .Switch:
		return intent.selected != precondition.head.branch && precondition.worktree_paths == 0 &&
		       precondition.unmerged_paths == 0 && precondition.editor.modified_repository_resources == 0
	case .Rename:
		return intent.name.reference != intent.selected.name
	case .Delete:
		return intent.selected != precondition.head.branch
	case .Invalid:
		return false
	}
	return false
}

/* branch_precondition_prepare derives one exact mode-specific boundary from current Status and Ref observations. */
branch_precondition_prepare :: proc(
	status: ^Status_Observation,
	refs: ^Ref_Observation,
	editor: Branch_Editor_State,
	intent: Branch_Intent,
) -> (Branch_Precondition, bool, Failure_Code) {
	if !branch_editor_state_is_valid(editor) || !branch_intent_is_valid(intent) {
		return {}, false, .Invalid_Request
	}
	status_descriptor, status_described := status_observation_descriptor(status)
	ref_descriptor, refs_described := ref_observation_descriptor(refs)
	if !status_described || !refs_described || ref_descriptor.state == .Truncated {
		return {}, false, .Stale_Observation
	}
	if status_descriptor.repository != ref_descriptor.repository || ref_descriptor.state == .Unborn ||
	   ref_descriptor.head.state != .Symbolic {
		return {}, false, .Ref_Unavailable
	}
	if status_descriptor.operation != .Normal do return {}, false, .Action_Unavailable
	unmerged_paths: u32
	path_count, counted := status_observation_path_count(status)
	if !counted || path_count != status_descriptor.path_count do return {}, false, .Stale_Observation
	for ordinal in 0 ..< path_count {
		path, found := status_observation_path(status, ordinal)
		if !found do return {}, false, .Stale_Observation
		if path.group == .Unmerged do unmerged_paths += 1
	}
	if intent.selected != {} && !branch_ref_is_observed(refs, intent.selected) {
		return {}, false, .Ref_Unavailable
	}
	if intent.operation == .Create || intent.operation == .Rename {
		if branch_ref_name_is_observed(refs, intent.name.reference) do return {}, false, .Target_Duplicate
	}
	if intent.operation == .Switch {
		if intent.selected == ref_descriptor.head.branch do return {}, false, .Target_Duplicate
		if path_count != 0 || unmerged_paths != 0 do return {}, false, .Action_Unavailable
		if editor.modified_repository_resources != 0 do return {}, false, .Modified_Buffer
	}
	if intent.operation == .Rename && intent.name.reference == intent.selected.name {
		return {}, false, .Target_Duplicate
	}
	if intent.operation == .Delete {
		if intent.selected == ref_descriptor.head.branch do return {}, false, .Action_Unavailable
		if !intent.require_merged_to_head do return {}, false, .Action_Unavailable
	}
	precondition := Branch_Precondition {
		repository = status_descriptor.repository,
		status_generation = status_descriptor.generation,
		ref_generation = ref_descriptor.generation,
		head = ref_descriptor.head,
		repository_operation = status_descriptor.operation,
		worktree_paths = path_count,
		unmerged_paths = unmerged_paths,
		editor = editor,
		intent = intent,
	}
	return precondition, branch_precondition_is_valid(precondition), .None
}

/* branch_confirmation_prepare binds one explicit one-shot confirmation to exact local branch truth. */
branch_confirmation_prepare :: proc(
	precondition: Branch_Precondition,
	id: Branch_Confirmation_ID,
) -> (Branch_Confirmation, bool, Failure_Code) {
	if id == Branch_Confirmation_ID(0) || !branch_precondition_is_valid(precondition) {
		return {}, false, .Invalid_Request
	}
	return {id = id, precondition = precondition}, true, .None
}

/* branch_confirmation_confirm accepts only the exact unused confirmation identity. */
branch_confirmation_confirm :: proc(
	confirmation: ^Branch_Confirmation,
	id: Branch_Confirmation_ID,
) -> (bool, Failure_Code) {
	if confirmation == nil || !branch_confirmation_input_is_valid(confirmation^) {
		return false, .Invalid_Request
	}
	if confirmation.id != id || confirmation.confirmed || confirmation.consumed {
		return false, .Confirmation_Mismatch
	}
	confirmation.confirmed = true
	return true, .None
}

/* branch_request_prepare consumes one exact confirmation into a closed non-force request. */
branch_request_prepare :: proc(
	precondition: Branch_Precondition,
	operation: Branch_Operation_ID,
	confirmation: ^Branch_Confirmation,
	limits := DEFAULT_PROCESS_LIMITS,
) -> (Branch_Request, bool, Failure_Code) {
	if operation == Branch_Operation_ID(0) || !branch_precondition_is_valid(precondition) ||
	   !process_limits_are_valid(limits) {
		return {}, false, .Invalid_Request
	}
	if confirmation == nil || !confirmation.confirmed do return {}, false, .Confirmation_Required
	if confirmation.consumed || !branch_confirmation_input_is_valid(confirmation^) ||
	   confirmation.precondition != precondition {
		return {}, false, .Confirmation_Mismatch
	}
	confirmation.consumed = true
	request := Branch_Request {
		operation = operation,
		precondition = precondition,
		confirmation = confirmation.id,
		limits = limits,
	}
	return request, branch_request_is_valid(request), .None
}

/* branch_request_is_valid checks one closed confirmed request without force or arbitrary revision modes. */
branch_request_is_valid :: proc(request: Branch_Request) -> bool {
	return request.operation != Branch_Operation_ID(0) && request.confirmation != Branch_Confirmation_ID(0) &&
	       branch_precondition_is_valid(request.precondition) && process_limits_are_valid(request.limits)
}

/* branch_request_revalidate proves the exact Status, Ref, and editor boundary remains current before start. */
branch_request_revalidate :: proc(
	status: ^Status_Observation,
	refs: ^Ref_Observation,
	editor: Branch_Editor_State,
	request: Branch_Request,
) -> (bool, Failure_Code) {
	if !branch_request_is_valid(request) do return false, .Invalid_Request
	current, prepared, failure := branch_precondition_prepare(status, refs, editor, request.precondition.intent)
	if !prepared do return false, failure
	if current != request.precondition do return false, .Stale_Observation
	return true, .None
}

/* branch_result_open copies one bounded process outcome pending refreshed repository truth. */
branch_result_open :: proc(
	request: Branch_Request,
	started: bool,
	exit_status: i32,
	output: []u8,
	diagnostic: []u8,
	process_failure := Failure_Code.None,
	allocator := context.allocator,
) -> (Branch_Result, bool, Failure_Code) {
	if allocator.procedure == nil || !branch_request_is_valid(request) do return {}, false, .Invalid_Request
	if u64(len(output)) > request.limits.stdout_bytes ||
	   u64(len(diagnostic)) > request.limits.diagnostic_bytes {
		return {}, false, .Output_Limit
	}
	if !started && (process_failure != .Cancelled || exit_status != 0 || len(output) != 0 || len(diagnostic) != 0) {
		return {}, false, .Invalid_Request
	}
	failure := process_failure
	if started && failure == .None && exit_status != 0 do failure = .Process_Failed
	state, allocation_error := new(Branch_Result_Data, allocator)
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
		branch_result_data_destroy(state)
		return {}, false, .Allocation
	}
	return Branch_Result{state = state}, true, .None
}

/* branch_result_verify records fresh Ref and Status truth and permits success only for the requested mutation. */
branch_result_verify :: proc(
	result: ^Branch_Result,
	fresh_status: ^Status_Observation,
	fresh_refs: ^Ref_Observation,
) -> (bool, Failure_Code) {
	state := branch_result_data(result)
	if state == nil || !state.descriptor.started || state.descriptor.verified ||
	   !branch_request_is_valid(state.descriptor.request) {
		return false, .Invalid_Request
	}
	status_descriptor, status_described := status_observation_descriptor(fresh_status)
	ref_descriptor, refs_described := ref_observation_descriptor(fresh_refs)
	before := state.descriptor.request.precondition
	if !status_described || !refs_described || ref_descriptor.state == .Truncated ||
	   status_descriptor.repository != before.repository || ref_descriptor.repository != before.repository ||
	   status_descriptor.generation == before.status_generation || ref_descriptor.generation == before.ref_generation ||
	   status_descriptor.operation != .Normal || ref_descriptor.state != .Available ||
	   !branch_status_matches_head(status_descriptor.branch, ref_descriptor.head) {
		branch_result_finish_verification(state, .Stale_Observation)
		return true, .Stale_Observation
	}
	state.descriptor.lineage.head_before = before.head
	state.descriptor.lineage.head_after = ref_descriptor.head
	state.descriptor.lineage.target_before = before.intent.selected
	intent := before.intent
	verified := false
	switch intent.operation {
	case .Create:
		target, found := branch_ref_by_name(fresh_refs, intent.name.reference)
		if found {
			state.descriptor.lineage.target_after = target
			verified = target.object == before.head.object && branch_head_same_object(ref_descriptor.head, before.head)
		}
	case .Switch:
		target, found := branch_ref_by_name(fresh_refs, intent.selected.name)
		if found {
			state.descriptor.lineage.target_after = target
			verified = ref_descriptor.head.state == .Symbolic &&
			           ref_descriptor.head.branch.name == intent.selected.name &&
			           ref_descriptor.head.object == intent.selected.object &&
			           status_descriptor.path_count == 0
		}
	case .Rename:
		target, found := branch_ref_by_name(fresh_refs, intent.name.reference)
		_, old_found := branch_ref_by_name(fresh_refs, intent.selected.name)
		if found {
			state.descriptor.lineage.target_after = target
			head_ok := branch_head_same_object(ref_descriptor.head, before.head)
			if intent.selected == before.head.branch {
				head_ok = ref_descriptor.head.state == .Symbolic &&
				          ref_descriptor.head.branch.name == intent.name.reference &&
				          ref_descriptor.head.object == intent.selected.object
			}
			verified = !old_found && target.object == intent.selected.object && head_ok
		}
	case .Delete:
		_, found := branch_ref_by_name(fresh_refs, intent.selected.name)
		verified = !found && branch_head_same_object(ref_descriptor.head, before.head)
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

/* branch_result_descriptor returns copied immutable branch outcome metadata. */
branch_result_descriptor :: proc(result: ^Branch_Result) -> (Branch_Result_Descriptor, bool) {
	state := branch_result_data(result)
	if state == nil do return {}, false
	return state.descriptor, branch_result_descriptor_is_valid(state.descriptor)
}

/* branch_result_descriptor_is_valid checks cancellation, refresh, and verified-success invariants. */
branch_result_descriptor_is_valid :: proc(descriptor: Branch_Result_Descriptor) -> bool {
	if !branch_request_is_valid(descriptor.request) ||
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

/* branch_result_usage reports exact copied public result payload sizes. */
branch_result_usage :: proc(result: ^Branch_Result) -> (Branch_Usage, bool) {
	state := branch_result_data(result)
	if state == nil do return {}, false
	return {output_bytes = u64(len(state.output)), diagnostic_bytes = u64(len(state.diagnostic))}, true
}

/* branch_result_output returns borrowed bounded public process output and diagnostics. */
branch_result_output :: proc(result: ^Branch_Result) -> (output, diagnostic: []u8, ok: bool) {
	state := branch_result_data(result)
	if state == nil do return nil, nil, false
	return state.output[:], state.diagnostic[:], true
}

/* branch_result_close releases every owned local branch result allocation. */
branch_result_close :: proc(result: ^Branch_Result) {
	state := branch_result_data(result)
	if state == nil do return
	branch_result_data_destroy(state)
	result^ = {}
}

/* branch_feedback maps checked branch state to stable application feedback. */
branch_feedback :: proc(descriptor: Branch_Result_Descriptor) -> Branch_Feedback {
	if !branch_result_descriptor_is_valid(descriptor) do return .Invalid
	if !descriptor.started do return .Cancelled
	if !descriptor.verified do return .Refreshing
	if descriptor.succeeded do return .Completed
	#partial switch descriptor.failure {
	case .Stale_Observation: return .Stale
	case .Ref_Unavailable, .Action_Unavailable, .Modified_Buffer, .Presentation_Unavailable: return .Unavailable
	case .Invalid_Context, .Invalid_Limits, .Invalid_Request, .Target_Duplicate,
	     .Confirmation_Required, .Confirmation_Mismatch: return .Rejected
	case .Output_Limit, .Ref_Limit, .Ref_Metadata_Limit, .Ref_Temporary_Limit, .Ref_Truncated: return .Limited
	case .Timeout: return .Timed_Out
	case .Cancelled: return .Cancelled
	case .Executable_Unavailable, .Process_Failed, .Parse, .Allocation, .Cleanup: return .Failed
	case .None: return .Failed
	case:
		return .Unavailable
	}
}

@(private)
local_branch_short_name_is_valid :: proc(text: string) -> bool {
	if len(text) == 0 || len(text) > MAX_LOCAL_BRANCH_NAME_BYTES || text == "@" || !utf8.valid_string(text) ||
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
branch_confirmation_input_is_valid :: proc(confirmation: Branch_Confirmation) -> bool {
	return confirmation.id != Branch_Confirmation_ID(0) &&
	       branch_precondition_is_valid(confirmation.precondition) &&
	       !(confirmation.consumed && !confirmation.confirmed)
}

@(private)
branch_ref_is_observed :: proc(observation: ^Ref_Observation, wanted: Ref_Identity) -> bool {
	count, available := ref_observation_ref_count(observation)
	if !available do return false
	for ordinal in 0 ..< count {
		candidate, found := ref_observation_ref(observation, ordinal)
		if found && candidate == wanted do return true
	}
	return false
}

@(private)
branch_ref_name_is_observed :: proc(observation: ^Ref_Observation, wanted: Ref_Name) -> bool {
	_, found := branch_ref_by_name(observation, wanted)
	return found
}

@(private)
branch_ref_by_name :: proc(observation: ^Ref_Observation, wanted: Ref_Name) -> (Ref_Identity, bool) {
	if !ref_name_is_valid(wanted) do return {}, false
	count, available := ref_observation_ref_count(observation)
	if !available do return {}, false
	for ordinal in 0 ..< count {
		candidate, found := ref_observation_ref(observation, ordinal)
		if found && candidate.kind == .Local_Branch && candidate.name == wanted do return candidate, true
	}
	return {}, false
}

@(private)
branch_head_same_object :: proc(next, previous: Head_Observation) -> bool {
	return next.state == .Symbolic && previous.state == .Symbolic &&
	       next.branch.name == previous.branch.name && next.object == previous.object
}

@(private)
branch_status_matches_head :: proc(label: Branch_Label, head: Head_Observation) -> bool {
	if !branch_label_is_valid(label) || !head_observation_is_valid(head) || head.state != .Symbolic do return false
	branch_name := head.branch.name
	name := ref_name_string(&branch_name)
	prefix := LOCAL_BRANCH_REF_PREFIX
	if !ref_name_has_prefix(name, prefix) do return false
	short := name[len(prefix):]
	label_copy := label
	return int(label.length) == len(short) && string(label_copy.bytes[:label_copy.length]) == short
}

@(private)
branch_result_finish_verification :: proc(state: ^Branch_Result_Data, failure: Failure_Code) {
	if state == nil do return
	state.descriptor.verified = true
	state.descriptor.succeeded = false
	state.descriptor.failure = failure
}

@(private)
branch_result_data :: proc(result: ^Branch_Result) -> ^Branch_Result_Data {
	if result == nil || result.state == nil do return nil
	return cast(^Branch_Result_Data)result.state
}

@(private)
branch_result_data_destroy :: proc(state: ^Branch_Result_Data) {
	if state == nil do return
	allocator := state.allocator
	if state.output != nil do delete(state.output)
	if state.diagnostic != nil do delete(state.diagnostic)
	free(state, allocator)
}
