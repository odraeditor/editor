// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery

import "base:runtime"
import "core:crypto/sha2"

/* MAX_MERGE_EDITOR_RESOURCES bounds repository-associated buffers inspected before merge actions. */
MAX_MERGE_EDITOR_RESOURCES :: u32(4_096)
/* MERGE_INDEX_FINGERPRINT_BYTES is the exact SHA-256 width for one complete staged-index snapshot. */
MERGE_INDEX_FINGERPRINT_BYTES :: 32

/* Merge_Operation_ID identifies one admitted checked merge action. */
Merge_Operation_ID :: distinct u64
/* Merge_Confirmation_ID identifies one explicit checked merge confirmation. */
Merge_Confirmation_ID :: distinct u64

/* Merge_Action selects one closed merge mutation family. */
Merge_Action :: enum u8 {
	Invalid,
	Start,
	Continue,
	Abort,
}

/* Merge_Fast_Forward_Policy makes the selected Git merge topology explicit. */
Merge_Fast_Forward_Policy :: enum u8 {
	Invalid,
	Fast_Forward_Only,
	Allow_Merge_Commit,
	Require_Merge_Commit,
}

/* Merge_Message_Mode distinguishes an unused message, Git's prepared message, and composed content. */
Merge_Message_Mode :: enum u8 {
	Invalid,
	Not_Used,
	Git_Default,
	Composed,
}

/* Merge_Message binds one closed message choice to optional bounded commit content. */
Merge_Message :: struct {
	mode:    Merge_Message_Mode,
	content: Commit_Message,
}

/* Merge_Source binds one selected compatible ref to its resolved complete commit identity. */
Merge_Source :: struct {
	reference: Ref_Identity,
	revision:  Revision_Identity,
}

/* Merge_Editor_State summarizes repository buffers that a merge action may replace. */
Merge_Editor_State :: struct {
	repository_resources:          u32,
	modified_repository_resources: u32,
}

/* Merge_Index_Fingerprint owns one nonzero digest of the complete staged index. */
Merge_Index_Fingerprint :: struct {
	bytes: [MERGE_INDEX_FINGERPRINT_BYTES]u8,
}

/* Merge_Precondition binds one action to exact Status, Ref, sequence, index, and editor truth. */
Merge_Precondition :: struct {
	repository:           Repository_Context,
	status_generation:    Observation_Generation,
	ref_generation:       Ref_Generation,
	sequence_generation:  Sequence_Generation,
	head:                 Head_Observation,
	index_tree:           Index_Tree_Identity,
	index_fingerprint:    Merge_Index_Fingerprint,
	repository_operation: Operation_State,
	sequence_state:       Sequence_Observation_State,
	sequence:             Sequence_Target,
	worktree_paths:       u32,
	unmerged_paths:       u32,
	editor:               Merge_Editor_State,
	action:               Merge_Action,
	source:               Merge_Source,
	target_revision:      Revision_Identity,
	policy:               Merge_Fast_Forward_Policy,
	message:              Merge_Message,
}

/* Merge_Confirmation owns one one-shot acknowledgement of an exact merge action. */
Merge_Confirmation :: struct {
	id:           Merge_Confirmation_ID,
	precondition: Merge_Precondition,
	confirmed:    bool,
	consumed:     bool,
}

/* Merge_Request is one closed confirmed merge action with bounded process ownership. */
Merge_Request :: struct {
	operation:    Merge_Operation_ID,
	precondition: Merge_Precondition,
	confirmation: Merge_Confirmation_ID,
	limits:       Process_Limits,
}

/* Merge_Outcome distinguishes refresh-pending and verified repository outcomes. */
Merge_Outcome :: enum u8 {
	Invalid,
	Cancelled_Before_Start,
	Awaiting_Refresh,
	Fast_Forwarded,
	Merge_Commit_Created,
	Paused_Conflict,
	Continued,
	Aborted,
	Known_Failure,
	Indeterminate,
}

/* Merge_Lineage records exact current, source, and refreshed resulting revision identities. */
Merge_Lineage :: struct {
	current:   Revision_Identity,
	source:    Revision_Identity,
	resulting: Revision_Identity,
}

/* Merge_Result_Descriptor separates child completion from refreshed Git authority. */
Merge_Result_Descriptor :: struct {
	request:           Merge_Request,
	outcome:           Merge_Outcome,
	lineage:           Merge_Lineage,
	sequence:          Sequence_Target,
	started:           bool,
	verified:          bool,
	exit_status:       i32,
	output_bytes:      u64,
	diagnostic_bytes:  u64,
	failure:           Failure_Code,
	process_succeeded: bool,
	refresh_required:  bool,
}

/* Merge_Usage reports exact retained merge process payload sizes. */
Merge_Usage :: struct {
	message_bytes:    u64,
	output_bytes:     u64,
	diagnostic_bytes: u64,
}

/* Merge_Result owns copied bounded output pending refreshed repository verification. */
Merge_Result :: struct {
	state: rawptr,
}

@(private)
Merge_Result_Data :: struct {
	descriptor: Merge_Result_Descriptor,
	output:     [dynamic]u8,
	diagnostic: [dynamic]u8,
	allocator:  runtime.Allocator,
}

/* merge_message_is_valid checks one action-independent closed message choice. */
merge_message_is_valid :: proc(message: Merge_Message) -> bool {
	switch message.mode {
	case .Not_Used, .Git_Default:
		return message.content == {}
	case .Composed:
		return commit_message_is_valid(message.content)
	case .Invalid:
		return false
	}
	return false
}

/* merge_source_is_valid checks one exact compatible ref and resolved commit identity. */
merge_source_is_valid :: proc(source: Merge_Source) -> bool {
	if !ref_identity_is_valid(source.reference) || !revision_identity_is_valid(source.revision) {
		return false
	}
	switch source.reference.kind {
	case .Local_Branch, .Remote_Tracking_Branch:
		return source.reference.object_type == .Commit && source.reference.object == source.revision
	case .Tag:
		if source.reference.object_type == .Commit do return source.reference.object == source.revision
		return source.reference.object_type == .Tag
	case .Invalid:
		return false
	}
	return false
}

/* merge_editor_state_is_valid bounds repository buffers and modified-buffer counts. */
merge_editor_state_is_valid :: proc(state: Merge_Editor_State) -> bool {
	return state.repository_resources <= MAX_MERGE_EDITOR_RESOURCES &&
	       state.modified_repository_resources <= state.repository_resources
}

/* merge_index_fingerprint_assign copies one exact nonzero staged-index digest. */
merge_index_fingerprint_assign :: proc(fingerprint: ^Merge_Index_Fingerprint, bytes: []u8) -> bool {
	if fingerprint == nil do return false
	fingerprint^ = {}
	if len(bytes) != MERGE_INDEX_FINGERPRINT_BYTES do return false
	nonzero := false
	for byte in bytes {
		if byte != 0 do nonzero = true
	}
	if !nonzero do return false
	copy(fingerprint.bytes[:], bytes)
	return true
}

/* merge_index_fingerprint_compute derives one exact digest from complete staged-index bytes. */
merge_index_fingerprint_compute :: proc(fingerprint: ^Merge_Index_Fingerprint, bytes: []u8) -> bool {
	if fingerprint == nil do return false
	ctx: sha2.Context_256
	sha2.init_256(&ctx)
	sha2.update(&ctx, bytes)
	sha2.final(&ctx, fingerprint.bytes[:])
	return merge_index_fingerprint_is_valid(fingerprint^)
}

/* merge_index_fingerprint_is_valid rejects an absent staged-index identity. */
merge_index_fingerprint_is_valid :: proc(fingerprint: Merge_Index_Fingerprint) -> bool {
	for byte in fingerprint.bytes {
		if byte != 0 do return true
	}
	return false
}

/* merge_precondition_is_valid checks one complete action-specific repository boundary. */
merge_precondition_is_valid :: proc(precondition: Merge_Precondition) -> bool {
	if !repository_context_is_valid(precondition.repository) ||
	   precondition.status_generation == Observation_Generation(0) ||
	   precondition.ref_generation == Ref_Generation(0) ||
	   precondition.sequence_generation == Sequence_Generation(0) ||
	   !head_observation_is_valid(precondition.head) || precondition.head.state != .Symbolic ||
	   !merge_index_fingerprint_is_valid(precondition.index_fingerprint) ||
	   precondition.worktree_paths > MAX_STATUS_PATHS ||
	   precondition.unmerged_paths > precondition.worktree_paths ||
	   !merge_editor_state_is_valid(precondition.editor) ||
	   precondition.head.branch.repository != precondition.repository ||
	   precondition.head.branch.generation != precondition.ref_generation {
		return false
	}
	switch precondition.action {
	case .Start:
		return precondition.repository_operation == .Normal &&
		       precondition.sequence_state == .Inactive && precondition.sequence == {} &&
		       precondition.worktree_paths == 0 && precondition.unmerged_paths == 0 &&
		       precondition.editor.modified_repository_resources == 0 &&
		       index_tree_identity_is_valid(precondition.index_tree) &&
		       merge_source_is_valid(precondition.source) &&
		       precondition.source.reference.repository == precondition.repository &&
		       precondition.source.reference.generation == precondition.ref_generation &&
		       precondition.target_revision == precondition.source.revision &&
		       precondition.target_revision != precondition.head.object &&
		       merge_start_message_is_valid(precondition.policy, precondition.message)
	case .Continue:
		return precondition.repository_operation == .Merging &&
		       precondition.sequence_state == .Active &&
		       sequence_target_is_valid(precondition.sequence) &&
		       precondition.sequence.generation == precondition.sequence_generation &&
		       precondition.unmerged_paths == 0 &&
		       precondition.editor.modified_repository_resources == 0 &&
		       index_tree_identity_is_valid(precondition.index_tree) &&
		       revision_identity_is_valid(precondition.target_revision) &&
		       precondition.source == {} && precondition.policy == .Invalid &&
		       merge_continue_message_is_valid(precondition.message)
	case .Abort:
		return precondition.repository_operation == .Merging &&
		       (precondition.sequence_state == .Active || precondition.sequence_state == .Conflicted) &&
		       sequence_target_is_valid(precondition.sequence) &&
		       precondition.sequence.generation == precondition.sequence_generation &&
		       precondition.editor.modified_repository_resources == 0 &&
		       revision_identity_is_valid(precondition.target_revision) &&
		       (precondition.sequence_state == .Conflicted && precondition.index_tree == {} ||
		        precondition.sequence_state == .Active && index_tree_identity_is_valid(precondition.index_tree)) &&
		       precondition.source == {} && precondition.policy == .Invalid &&
		       precondition.message.mode == .Not_Used && precondition.message.content == {}
	case .Invalid:
		return false
	}
	return false
}

/* merge_precondition_failure classifies expected admission failures without weakening exact identity. */
merge_precondition_failure :: proc(precondition: Merge_Precondition) -> Failure_Code {
	if !repository_context_is_valid(precondition.repository) ||
	   precondition.status_generation == Observation_Generation(0) ||
	   precondition.ref_generation == Ref_Generation(0) ||
	   precondition.sequence_generation == Sequence_Generation(0) ||
	   !head_observation_is_valid(precondition.head) ||
	   !merge_index_fingerprint_is_valid(precondition.index_fingerprint) ||
	   !merge_editor_state_is_valid(precondition.editor) || precondition.action == .Invalid {
		return .Invalid_Request
	}
	if precondition.head.state != .Symbolic do return .Action_Unavailable
	if precondition.head.branch.repository != precondition.repository ||
	   precondition.head.branch.generation != precondition.ref_generation {
		return .Stale_Observation
	}
	if precondition.editor.modified_repository_resources != 0 do return .Modified_Buffer
	switch precondition.action {
	case .Start:
		if !merge_source_is_valid(precondition.source) do return .Ref_Unavailable
		if precondition.source.reference.repository != precondition.repository ||
		   precondition.source.reference.generation != precondition.ref_generation {
			return .Stale_Observation
		}
		if precondition.target_revision != precondition.source.revision do return .Stale_Observation
		if precondition.target_revision == precondition.head.object do return .Target_Duplicate
		if !index_tree_identity_is_valid(precondition.index_tree) do return .Invalid_Request
		if !merge_start_message_is_valid(precondition.policy, precondition.message) {
			return .Commit_Message_Invalid
		}
		if precondition.repository_operation != .Normal || precondition.sequence_state != .Inactive ||
		   precondition.sequence != {} || precondition.worktree_paths != 0 || precondition.unmerged_paths != 0 {
			return .Action_Unavailable
		}
	case .Continue:
		if !merge_continue_message_is_valid(precondition.message) do return .Commit_Message_Invalid
		if !index_tree_identity_is_valid(precondition.index_tree) ||
		   !revision_identity_is_valid(precondition.target_revision) {
			return .Invalid_Request
		}
		if precondition.repository_operation != .Merging || precondition.sequence_state != .Active ||
		   !sequence_target_is_valid(precondition.sequence) ||
		   precondition.sequence.generation != precondition.sequence_generation ||
		   precondition.unmerged_paths != 0 || precondition.source != {} || precondition.policy != .Invalid {
			return .Action_Unavailable
		}
	case .Abort:
		if precondition.message.mode != .Not_Used || precondition.message.content != {} {
			return .Commit_Message_Invalid
		}
		if !revision_identity_is_valid(precondition.target_revision) ||
		   (precondition.sequence_state == .Conflicted && precondition.index_tree != {}) ||
		   (precondition.sequence_state == .Active && !index_tree_identity_is_valid(precondition.index_tree)) {
			return .Invalid_Request
		}
		if precondition.repository_operation != .Merging ||
		   (precondition.sequence_state != .Active && precondition.sequence_state != .Conflicted) ||
		   !sequence_target_is_valid(precondition.sequence) ||
		   precondition.sequence.generation != precondition.sequence_generation ||
		   precondition.source != {} || precondition.policy != .Invalid {
			return .Action_Unavailable
		}
	case .Invalid:
		return .Invalid_Request
	}
	if precondition.worktree_paths > MAX_STATUS_PATHS ||
	   precondition.unmerged_paths > precondition.worktree_paths {
		return .Invalid_Request
	}
	return .None
}

/* merge_confirmation_prepare binds one one-shot confirmation to exact checked merge truth. */
merge_confirmation_prepare :: proc(
	precondition: Merge_Precondition,
	id: Merge_Confirmation_ID,
) -> (Merge_Confirmation, bool, Failure_Code) {
	if id == Merge_Confirmation_ID(0) do return {}, false, .Invalid_Request
	if failure := merge_precondition_failure(precondition); failure != .None do return {}, false, failure
	return {id = id, precondition = precondition}, true, .None
}

/* merge_confirmation_confirm accepts only the exact unused confirmation identity. */
merge_confirmation_confirm :: proc(
	confirmation: ^Merge_Confirmation,
	id: Merge_Confirmation_ID,
) -> (bool, Failure_Code) {
	if confirmation == nil || !merge_confirmation_input_is_valid(confirmation^) {
		return false, .Invalid_Request
	}
	if confirmation.id != id || confirmation.confirmed || confirmation.consumed {
		return false, .Confirmation_Mismatch
	}
	confirmation.confirmed = true
	return true, .None
}

/* merge_request_prepare consumes one exact confirmation into a closed process request. */
merge_request_prepare :: proc(
	precondition: Merge_Precondition,
	operation: Merge_Operation_ID,
	confirmation: ^Merge_Confirmation,
	limits := DEFAULT_PROCESS_LIMITS,
) -> (Merge_Request, bool, Failure_Code) {
	if operation == Merge_Operation_ID(0) || !process_limits_are_valid(limits) {
		return {}, false, .Invalid_Request
	}
	if failure := merge_precondition_failure(precondition); failure != .None do return {}, false, failure
	if confirmation == nil || !confirmation.confirmed do return {}, false, .Confirmation_Required
	if confirmation.consumed || !merge_confirmation_input_is_valid(confirmation^) ||
	   confirmation.precondition != precondition {
		return {}, false, .Confirmation_Mismatch
	}
	confirmation.consumed = true
	request := Merge_Request {
		operation = operation,
		precondition = precondition,
		confirmation = confirmation.id,
		limits = limits,
	}
	return request, merge_request_is_valid(request), .None
}

/* merge_request_is_valid checks one closed confirmed request with no arbitrary Git arguments. */
merge_request_is_valid :: proc(request: Merge_Request) -> bool {
	return request.operation != Merge_Operation_ID(0) &&
	       request.confirmation != Merge_Confirmation_ID(0) &&
	       merge_precondition_is_valid(request.precondition) &&
	       process_limits_are_valid(request.limits)
}

/* merge_request_revalidate rejects any changed checked repository or editor precondition. */
merge_request_revalidate :: proc(
	current: Merge_Precondition,
	request: Merge_Request,
) -> (bool, Failure_Code) {
	if !merge_request_is_valid(request) do return false, .Invalid_Request
	if failure := merge_precondition_failure(current); failure != .None do return false, failure
	if current != request.precondition do return false, .Stale_Observation
	return true, .None
}

/* merge_result_open copies one bounded child outcome pending mandatory repository refresh. */
merge_result_open :: proc(
	request: Merge_Request,
	started: bool,
	exit_status: i32,
	output: []u8,
	diagnostic: []u8,
	process_failure := Failure_Code.None,
	allocator := context.allocator,
) -> (Merge_Result, bool, Failure_Code) {
	if allocator.procedure == nil || !merge_request_is_valid(request) do return {}, false, .Invalid_Request
	if u64(len(output)) > request.limits.stdout_bytes ||
	   u64(len(diagnostic)) > request.limits.diagnostic_bytes {
		return {}, false, .Output_Limit
	}
	if !started && (process_failure != .Cancelled || exit_status != 0 || len(output) != 0 || len(diagnostic) != 0) {
		return {}, false, .Invalid_Request
	}
	failure := process_failure
	if started && failure == .None && exit_status != 0 do failure = .Process_Failed
	state, allocation_error := new(Merge_Result_Data, allocator)
	if allocation_error != nil do return {}, false, .Allocation
	state.allocator = allocator
	state.descriptor = {
		request = request,
		outcome = started ? .Awaiting_Refresh : .Cancelled_Before_Start,
		lineage = {
			current = request.precondition.head.object,
			source = request.precondition.target_revision,
		},
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
		merge_result_data_destroy(state)
		return {}, false, .Allocation
	}
	return Merge_Result{state = state}, true, .None
}

/* merge_result_descriptor returns copied immutable merge child outcome metadata. */
merge_result_descriptor :: proc(result: ^Merge_Result) -> (Merge_Result_Descriptor, bool) {
	state := merge_result_data(result)
	if state == nil do return {}, false
	return state.descriptor, merge_result_descriptor_is_valid(state.descriptor)
}

/* merge_result_verify classifies one child outcome against refreshed exact HEAD and Sequence truth. */
merge_result_verify :: proc(
	result: ^Merge_Result,
	refs: ^Ref_Observation,
	sequence: ^Sequence_Observation,
) -> (bool, Failure_Code) {
	state := merge_result_data(result)
	refs_descriptor, refs_described := ref_observation_descriptor(refs)
	sequence_descriptor, sequence_described := sequence_observation_descriptor(sequence)
	if state == nil || state.descriptor.verified || !state.descriptor.started ||
	   !state.descriptor.refresh_required || !refs_described || !sequence_described ||
	   refs_descriptor.repository != state.descriptor.request.precondition.repository ||
	   sequence_descriptor.repository != refs_descriptor.repository || refs_descriptor.head.state != .Symbolic {
		return false, .Invalid_Request
	}
	descriptor := &state.descriptor
	precondition := descriptor.request.precondition
	descriptor.verified = true
	descriptor.lineage.resulting = refs_descriptor.head.object
	if sequence_descriptor.state != .Inactive {
		if sequence_descriptor.kind == .Merge &&
		   sequence_descriptor.target == precondition.target_revision &&
		   (sequence_descriptor.state == .Active || sequence_descriptor.state == .Conflicted) {
			descriptor.sequence = {
				generation = sequence_descriptor.generation,
				fingerprint = sequence_descriptor.fingerprint,
			}
			descriptor.outcome = .Paused_Conflict
			descriptor.failure = .Process_Failed
			return true, descriptor.failure
		}
		descriptor.outcome = .Indeterminate
		descriptor.failure = .Stale_Observation
		return true, descriptor.failure
	}
	if !descriptor.started || !descriptor.process_succeeded {
		descriptor.outcome = descriptor.started ? .Known_Failure : .Cancelled_Before_Start
		return true, descriptor.failure
	}
	switch precondition.action {
	case .Start:
		if precondition.policy != .Require_Merge_Commit &&
		   refs_descriptor.head.object == precondition.target_revision {
			descriptor.outcome = .Fast_Forwarded
			descriptor.failure = .None
			return true, .None
		}
		if precondition.policy != .Fast_Forward_Only &&
		   refs_descriptor.head.object != precondition.head.object &&
		   refs_descriptor.head.object != precondition.target_revision {
			descriptor.outcome = .Merge_Commit_Created
			descriptor.failure = .None
			return true, .None
		}
	case .Continue:
		if refs_descriptor.head.object != precondition.head.object {
			descriptor.outcome = .Continued
			descriptor.failure = .None
			return true, .None
		}
	case .Abort:
		if refs_descriptor.head.object == precondition.head.object {
			descriptor.outcome = .Aborted
			descriptor.failure = .None
			return true, .None
		}
	case .Invalid:
	}
	descriptor.outcome = .Indeterminate
	descriptor.failure = .Stale_Observation
	return true, descriptor.failure
}

/* merge_result_descriptor_is_valid checks cancellation and refresh-pending process invariants. */
merge_result_descriptor_is_valid :: proc(descriptor: Merge_Result_Descriptor) -> bool {
	if !merge_request_is_valid(descriptor.request) ||
	   descriptor.output_bytes > descriptor.request.limits.stdout_bytes ||
	   descriptor.diagnostic_bytes > descriptor.request.limits.diagnostic_bytes {
		return false
	}
	expected_source := descriptor.request.precondition.target_revision
	if descriptor.lineage.current != descriptor.request.precondition.head.object ||
	   descriptor.lineage.source != expected_source {
		return false
	}
	if !descriptor.started {
		return descriptor.outcome == .Cancelled_Before_Start && descriptor.exit_status == 0 &&
		       descriptor.output_bytes == 0 && descriptor.diagnostic_bytes == 0 &&
		       descriptor.failure == .Cancelled && !descriptor.process_succeeded && !descriptor.refresh_required
	}
	if !descriptor.verified {
		return descriptor.outcome == .Awaiting_Refresh && descriptor.sequence == {} &&
		       descriptor.lineage.resulting == {} && descriptor.refresh_required &&
		       descriptor.process_succeeded == (descriptor.failure == .None && descriptor.exit_status == 0)
	}
	if !revision_identity_is_valid(descriptor.lineage.resulting) ||
	   descriptor.outcome == .Awaiting_Refresh || descriptor.outcome == .Invalid {
		return false
	}
	return descriptor.outcome == .Paused_Conflict ? sequence_target_is_valid(descriptor.sequence) : descriptor.sequence == {}
}

/* merge_result_usage reports exact fixed message and copied public result payload sizes. */
merge_result_usage :: proc(result: ^Merge_Result) -> (Merge_Usage, bool) {
	state := merge_result_data(result)
	if state == nil do return {}, false
	message_bytes: u64
	if state.descriptor.request.precondition.message.mode == .Composed {
		message_bytes = u64(state.descriptor.request.precondition.message.content.length)
	}
	return {
		message_bytes = message_bytes,
		output_bytes = u64(len(state.output)),
		diagnostic_bytes = u64(len(state.diagnostic)),
	}, true
}

/* merge_result_output returns borrowed bounded public process output and diagnostics. */
merge_result_output :: proc(result: ^Merge_Result) -> (output, diagnostic: []u8, ok: bool) {
	state := merge_result_data(result)
	if state == nil do return nil, nil, false
	return state.output[:], state.diagnostic[:], true
}

/* merge_result_close releases every owned merge result allocation. */
merge_result_close :: proc(result: ^Merge_Result) {
	state := merge_result_data(result)
	if state == nil do return
	merge_result_data_destroy(state)
	result^ = {}
}

@(private)
merge_start_message_is_valid :: proc(
	policy: Merge_Fast_Forward_Policy,
	message: Merge_Message,
) -> bool {
	switch policy {
	case .Fast_Forward_Only:
		return message.mode == .Not_Used && message.content == {}
	case .Allow_Merge_Commit, .Require_Merge_Commit:
		return message.mode == .Git_Default && message.content == {} ||
		       message.mode == .Composed && commit_message_is_valid(message.content)
	case .Invalid:
		return false
	}
	return false
}

@(private)
merge_continue_message_is_valid :: proc(message: Merge_Message) -> bool {
	return message.mode == .Git_Default && message.content == {} ||
	       message.mode == .Composed && commit_message_is_valid(message.content)
}

@(private)
merge_confirmation_input_is_valid :: proc(confirmation: Merge_Confirmation) -> bool {
	return confirmation.id != Merge_Confirmation_ID(0) &&
	       merge_precondition_is_valid(confirmation.precondition) &&
	       !(confirmation.consumed && !confirmation.confirmed)
}

@(private)
merge_result_data :: proc(result: ^Merge_Result) -> ^Merge_Result_Data {
	if result == nil || result.state == nil do return nil
	return cast(^Merge_Result_Data)result.state
}

@(private)
merge_result_data_destroy :: proc(state: ^Merge_Result_Data) {
	if state == nil do return
	delete(state.output)
	delete(state.diagnostic)
	free(state, state.allocator)
}
