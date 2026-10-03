// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery

import "base:runtime"
import "core:crypto/sha2"

/* CONFLICT_CONTENT_FINGERPRINT_BYTES is the exact SHA-256 width for checked worktree content. */
CONFLICT_CONTENT_FINGERPRINT_BYTES :: 32

/* Conflict_Resolution_Operation_ID identifies one admitted whole-path resolution attempt. */
Conflict_Resolution_Operation_ID :: distinct u64
/* Conflict_Resolution_Confirmation_ID identifies one destructive whole-path confirmation. */
Conflict_Resolution_Confirmation_ID :: distinct u64

/* Conflict_Node_Kind classifies the checked worktree result independently from text encoding. */
Conflict_Node_Kind :: enum u8 {
	Invalid,
	Regular,
	Executable,
	Symlink,
	Submodule,
	Other,
}

/* Conflict_Content_Kind distinguishes editable text from bounded non-text inspection. */
Conflict_Content_Kind :: enum u8 {
	Invalid,
	Text,
	Binary,
	Unavailable,
}

/* Conflict_Content_Fingerprint owns one nonzero digest of exact saved worktree content. */
Conflict_Content_Fingerprint :: struct {
	bytes: [CONFLICT_CONTENT_FINGERPRINT_BYTES]u8,
}

/* Conflict_Worktree_Result identifies exact saved content or an absent result path. */
Conflict_Worktree_Result :: struct {
	exists:      bool,
	node:        Conflict_Node_Kind,
	content:     Conflict_Content_Kind,
	mode:        u32,
	git_object:  Revision_Identity,
	fingerprint: Conflict_Content_Fingerprint,
}

/* Conflict_Editor_State binds an ordinary buffer to the exact saved worktree result. */
Conflict_Editor_State :: struct {
	open:              bool,
	modified:          bool,
	saved_fingerprint: Conflict_Content_Fingerprint,
}

/* Conflict_Resolution_Action selects one closed whole-path index replacement. */
Conflict_Resolution_Action :: enum u8 {
	Invalid,
	Mark_Saved_Result,
	Use_Base,
	Use_Current,
	Use_Applied,
	Delete_Result,
}

/* Conflict_Resolution_Precondition binds one exact conflict and saved result to current Git truth. */
Conflict_Resolution_Precondition :: struct {
	repository:           Repository_Context,
	status_generation:    Observation_Generation,
	sequence_generation:  Sequence_Generation,
	repository_operation: Operation_State,
	sequence_state:       Sequence_Observation_State,
	sequence:             Sequence_Target,
	conflict:             Conflict_Target_ID,
	target:               Conflict_Target,
	worktree:             Conflict_Worktree_Result,
	editor:               Conflict_Editor_State,
	unmerged_paths:       u32,
	action:               Conflict_Resolution_Action,
}

/* Conflict_Resolution_Confirmation owns one exact one-shot destructive action acknowledgement. */
Conflict_Resolution_Confirmation :: struct {
	id:           Conflict_Resolution_Confirmation_ID,
	precondition: Conflict_Resolution_Precondition,
	confirmed:    bool,
	consumed:     bool,
}

/* Conflict_Resolution_Request is one checked whole-path resolution with bounded process ownership. */
Conflict_Resolution_Request :: struct {
	operation:    Conflict_Resolution_Operation_ID,
	precondition: Conflict_Resolution_Precondition,
	confirmation: Conflict_Resolution_Confirmation_ID,
	limits:       Process_Limits,
}

/* Conflict_Stage_Zero_State identifies the refreshed index result for one path. */
Conflict_Stage_Zero_State :: enum u8 {
	Invalid,
	Present,
	Deleted,
	Still_Unmerged,
}

/* Conflict_Stage_Zero records exact refreshed stage-zero identity or deletion. */
Conflict_Stage_Zero :: struct {
	state:  Conflict_Stage_Zero_State,
	mode:   u32,
	object: Revision_Identity,
}

/* Conflict_Resolution_Outcome distinguishes pending refresh from verified whole-path state. */
Conflict_Resolution_Outcome :: enum u8 {
	Invalid,
	Cancelled_Before_Start,
	Awaiting_Refresh,
	Resolved,
	Deleted,
	Still_Unmerged,
	Known_Failure,
	Indeterminate,
}

/* Conflict_Resolution_Result_Descriptor separates child completion from refreshed index truth. */
Conflict_Resolution_Result_Descriptor :: struct {
	request:           Conflict_Resolution_Request,
	outcome:           Conflict_Resolution_Outcome,
	stage_zero:        Conflict_Stage_Zero,
	fresh_sequence:    Sequence_Target,
	started:           bool,
	verified:          bool,
	exit_status:       i32,
	output_bytes:      u64,
	diagnostic_bytes:  u64,
	failure:           Failure_Code,
	process_succeeded: bool,
	refresh_required:  bool,
}

/* Conflict_Resolution_Result owns copied bounded process evidence. */
Conflict_Resolution_Result :: struct {
	state: rawptr,
}

@(private)
Conflict_Resolution_Result_Data :: struct {
	descriptor: Conflict_Resolution_Result_Descriptor,
	output:     [dynamic]u8,
	diagnostic: [dynamic]u8,
	allocator:  runtime.Allocator,
}

/* conflict_content_fingerprint_assign copies one exact nonzero content digest. */
conflict_content_fingerprint_assign :: proc(
	fingerprint: ^Conflict_Content_Fingerprint,
	bytes: []u8,
) -> bool {
	if fingerprint == nil do return false
	fingerprint^ = {}
	if len(bytes) != CONFLICT_CONTENT_FINGERPRINT_BYTES do return false
	nonzero := false
	for byte in bytes {
		if byte != 0 do nonzero = true
	}
	if !nonzero do return false
	copy(fingerprint.bytes[:], bytes)
	return true
}

/* conflict_content_fingerprint_compute derives one exact digest from saved worktree bytes. */
conflict_content_fingerprint_compute :: proc(
	fingerprint: ^Conflict_Content_Fingerprint,
	bytes: []u8,
) -> bool {
	if fingerprint == nil do return false
	ctx: sha2.Context_256
	sha2.init_256(&ctx)
	sha2.update(&ctx, bytes)
	sha2.final(&ctx, fingerprint.bytes[:])
	return conflict_content_fingerprint_is_valid(fingerprint^)
}

/* conflict_content_fingerprint_is_valid rejects an absent saved-content identity. */
conflict_content_fingerprint_is_valid :: proc(fingerprint: Conflict_Content_Fingerprint) -> bool {
	for byte in fingerprint.bytes {
		if byte != 0 do return true
	}
	return false
}

/* conflict_worktree_result_is_valid checks exact regular, special, or absent result state. */
conflict_worktree_result_is_valid :: proc(result: Conflict_Worktree_Result) -> bool {
	if !result.exists {
		return result.node == .Invalid && result.content == .Unavailable && result.mode == 0 &&
		       result.git_object == {} && result.fingerprint == {}
	}
	if !revision_identity_is_valid(result.git_object) ||
	   !conflict_content_fingerprint_is_valid(result.fingerprint) {
		return false
	}
	switch result.node {
	case .Regular:
		return result.mode == 0o100644 && (result.content == .Text || result.content == .Binary)
	case .Executable:
		return result.mode == 0o100755 && (result.content == .Text || result.content == .Binary)
	case .Symlink:
		return result.mode == 0o120000 && result.content == .Text
	case .Submodule:
		return result.mode == 0o160000 && result.content == .Unavailable
	case .Other:
		return result.mode != 0 && result.content == .Unavailable
	case .Invalid:
		return false
	}
	return false
}

/* conflict_editor_state_is_valid protects an exact saved result from unsaved buffer divergence. */
conflict_editor_state_is_valid :: proc(
	editor: Conflict_Editor_State,
	worktree: Conflict_Worktree_Result,
) -> bool {
	if editor.modified do return editor.open
	if !editor.open do return editor.saved_fingerprint == {}
	if !worktree.exists do return editor.saved_fingerprint == {}
	return editor.saved_fingerprint == worktree.fingerprint
}

/* conflict_resolution_precondition_is_valid checks one complete whole-path action boundary. */
conflict_resolution_precondition_is_valid :: proc(
	precondition: Conflict_Resolution_Precondition,
) -> bool {
	if !repository_context_is_valid(precondition.repository) ||
	   precondition.status_generation == Observation_Generation(0) ||
	   precondition.sequence_generation == Sequence_Generation(0) ||
	   precondition.repository_operation != .Merging ||
	   precondition.sequence_state != .Conflicted ||
	   !sequence_target_is_valid(precondition.sequence) ||
	   precondition.sequence.generation != precondition.sequence_generation ||
	   !conflict_target_id_is_valid(precondition.conflict) ||
	   precondition.conflict.sequence != precondition.sequence ||
	   precondition.target.id != precondition.conflict.conflict ||
	   !conflict_target_is_complete(precondition.target) ||
	   !conflict_worktree_result_is_valid(precondition.worktree) ||
	   !conflict_editor_state_is_valid(precondition.editor, precondition.worktree) ||
	   precondition.unmerged_paths == 0 || precondition.unmerged_paths > MAX_STATUS_PATHS {
		return false
	}
	if precondition.editor.modified do return false
	switch precondition.action {
	case .Mark_Saved_Result:
		return precondition.worktree.exists &&
		       (precondition.worktree.node == .Regular || precondition.worktree.node == .Executable) &&
		       precondition.worktree.content == .Text
	case .Use_Base:
		return conflict_target_stage_is_available(precondition.target, .Base)
	case .Use_Current:
		return conflict_target_stage_is_available(precondition.target, .Current)
	case .Use_Applied:
		return conflict_target_stage_is_available(precondition.target, .Applied)
	case .Delete_Result:
		return precondition.target.kind != .Invalid && precondition.target.kind != .Other
	case .Invalid:
		return false
	}
	return false
}

/* conflict_resolution_precondition_failure classifies expected whole-path admission failures. */
conflict_resolution_precondition_failure :: proc(
	precondition: Conflict_Resolution_Precondition,
) -> Failure_Code {
	if !repository_context_is_valid(precondition.repository) ||
	   precondition.status_generation == Observation_Generation(0) ||
	   precondition.sequence_generation == Sequence_Generation(0) ||
	   !sequence_target_is_valid(precondition.sequence) ||
	   !conflict_target_id_is_valid(precondition.conflict) ||
	   !conflict_worktree_result_is_valid(precondition.worktree) ||
	   !conflict_editor_state_is_valid(precondition.editor, precondition.worktree) ||
	   precondition.action == .Invalid {
		return .Invalid_Request
	}
	if precondition.editor.modified do return .Modified_Buffer
	if precondition.sequence.generation != precondition.sequence_generation ||
	   precondition.conflict.sequence != precondition.sequence ||
	   precondition.target.id != precondition.conflict.conflict {
		return .Stale_Observation
	}
	if precondition.repository_operation != .Merging || precondition.sequence_state != .Conflicted ||
	   precondition.unmerged_paths == 0 || precondition.unmerged_paths > MAX_STATUS_PATHS ||
	   !conflict_target_is_complete(precondition.target) {
		return .Action_Unavailable
	}
	switch precondition.action {
	case .Mark_Saved_Result:
		if !precondition.worktree.exists ||
		   (precondition.worktree.node != .Regular && precondition.worktree.node != .Executable) ||
		   precondition.worktree.content != .Text {
			return .Action_Unavailable
		}
	case .Use_Base:
		if !conflict_target_stage_is_available(precondition.target, .Base) do return .Action_Unavailable
	case .Use_Current:
		if !conflict_target_stage_is_available(precondition.target, .Current) do return .Action_Unavailable
	case .Use_Applied:
		if !conflict_target_stage_is_available(precondition.target, .Applied) do return .Action_Unavailable
	case .Delete_Result:
		if precondition.target.kind == .Invalid || precondition.target.kind == .Other {
			return .Action_Unavailable
		}
	case .Invalid:
		return .Invalid_Request
	}
	return .None
}

/* conflict_resolution_confirmation_prepare binds a destructive action to exact conflict truth. */
conflict_resolution_confirmation_prepare :: proc(
	precondition: Conflict_Resolution_Precondition,
	id: Conflict_Resolution_Confirmation_ID,
) -> (Conflict_Resolution_Confirmation, bool, Failure_Code) {
	if id == Conflict_Resolution_Confirmation_ID(0) ||
	   !conflict_resolution_action_requires_confirmation(precondition.action) {
		return {}, false, .Invalid_Request
	}
	if failure := conflict_resolution_precondition_failure(precondition); failure != .None {
		return {}, false, failure
	}
	return {id = id, precondition = precondition}, true, .None
}

/* conflict_resolution_confirmation_confirm accepts only one exact unused confirmation identity. */
conflict_resolution_confirmation_confirm :: proc(
	confirmation: ^Conflict_Resolution_Confirmation,
	id: Conflict_Resolution_Confirmation_ID,
) -> (bool, Failure_Code) {
	if confirmation == nil || !conflict_resolution_confirmation_is_valid(confirmation^) {
		return false, .Invalid_Request
	}
	if confirmation.id != id || confirmation.confirmed || confirmation.consumed {
		return false, .Confirmation_Mismatch
	}
	confirmation.confirmed = true
	return true, .None
}

/* conflict_resolution_request_prepare admits one exact whole-path action and consumes confirmation when required. */
conflict_resolution_request_prepare :: proc(
	precondition: Conflict_Resolution_Precondition,
	operation: Conflict_Resolution_Operation_ID,
	confirmation: ^Conflict_Resolution_Confirmation = nil,
	limits := DEFAULT_PROCESS_LIMITS,
) -> (Conflict_Resolution_Request, bool, Failure_Code) {
	if operation == Conflict_Resolution_Operation_ID(0) || !process_limits_are_valid(limits) {
		return {}, false, .Invalid_Request
	}
	if failure := conflict_resolution_precondition_failure(precondition); failure != .None {
		return {}, false, failure
	}
	confirmation_id: Conflict_Resolution_Confirmation_ID
	if conflict_resolution_action_requires_confirmation(precondition.action) {
		if confirmation == nil || !confirmation.confirmed do return {}, false, .Confirmation_Required
		if confirmation.consumed || !conflict_resolution_confirmation_is_valid(confirmation^) ||
		   confirmation.precondition != precondition {
			return {}, false, .Confirmation_Mismatch
		}
		confirmation.consumed = true
		confirmation_id = confirmation.id
	} else if confirmation != nil {
		return {}, false, .Confirmation_Mismatch
	}
	request := Conflict_Resolution_Request {
		operation = operation,
		precondition = precondition,
		confirmation = confirmation_id,
		limits = limits,
	}
	return request, conflict_resolution_request_is_valid(request), .None
}

/* conflict_resolution_request_is_valid checks one closed whole-path request shape. */
conflict_resolution_request_is_valid :: proc(request: Conflict_Resolution_Request) -> bool {
	if request.operation == Conflict_Resolution_Operation_ID(0) ||
	   !conflict_resolution_precondition_is_valid(request.precondition) ||
	   !process_limits_are_valid(request.limits) {
		return false
	}
	required := conflict_resolution_action_requires_confirmation(request.precondition.action)
	return required == (request.confirmation != Conflict_Resolution_Confirmation_ID(0))
}

/* conflict_resolution_request_revalidate rejects changed stages, worktree content, buffers, or sequence identity. */
conflict_resolution_request_revalidate :: proc(
	current: Conflict_Resolution_Precondition,
	request: Conflict_Resolution_Request,
) -> (bool, Failure_Code) {
	if !conflict_resolution_request_is_valid(request) do return false, .Invalid_Request
	if failure := conflict_resolution_precondition_failure(current); failure != .None do return false, failure
	if current != request.precondition do return false, .Stale_Observation
	return true, .None
}

/* conflict_stage_zero_is_valid checks one refreshed stage-zero or still-unmerged result. */
conflict_stage_zero_is_valid :: proc(stage: Conflict_Stage_Zero) -> bool {
	switch stage.state {
	case .Present:
		return conflict_mode_is_supported(stage.mode) && revision_identity_is_valid(stage.object)
	case .Deleted, .Still_Unmerged:
		return stage.mode == 0 && stage.object == {}
	case .Invalid:
		return false
	}
	return false
}

/* conflict_resolution_result_open copies one bounded child outcome pending mandatory refresh. */
conflict_resolution_result_open :: proc(
	request: Conflict_Resolution_Request,
	started: bool,
	exit_status: i32,
	output: []u8,
	diagnostic: []u8,
	process_failure := Failure_Code.None,
	allocator := context.allocator,
) -> (Conflict_Resolution_Result, bool, Failure_Code) {
	if allocator.procedure == nil || !conflict_resolution_request_is_valid(request) {
		return {}, false, .Invalid_Request
	}
	if u64(len(output)) > request.limits.stdout_bytes ||
	   u64(len(diagnostic)) > request.limits.diagnostic_bytes {
		return {}, false, .Output_Limit
	}
	if !started && (process_failure != .Cancelled || exit_status != 0 || len(output) != 0 || len(diagnostic) != 0) {
		return {}, false, .Invalid_Request
	}
	failure := process_failure
	if started && failure == .None && exit_status != 0 do failure = .Process_Failed
	state, allocation_error := new(Conflict_Resolution_Result_Data, allocator)
	if allocation_error != nil do return {}, false, .Allocation
	state.allocator = allocator
	state.descriptor = {
		request = request,
		outcome = started ? .Awaiting_Refresh : .Cancelled_Before_Start,
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
		conflict_resolution_result_data_destroy(state)
		return {}, false, .Allocation
	}
	return Conflict_Resolution_Result{state = state}, true, .None
}

/* conflict_resolution_result_verify records only refreshed stage-zero or explicit still-unmerged truth. */
conflict_resolution_result_verify :: proc(
	result: ^Conflict_Resolution_Result,
	stage_zero: Conflict_Stage_Zero,
	fresh_sequence: Sequence_Target,
) -> (bool, Failure_Code) {
	state := conflict_resolution_result_data(result)
	if state == nil || state.descriptor.verified || !conflict_stage_zero_is_valid(stage_zero) {
		return false, .Invalid_Request
	}
	descriptor := &state.descriptor
	descriptor.verified = true
	descriptor.stage_zero = stage_zero
	descriptor.fresh_sequence = fresh_sequence
	if !descriptor.started || !descriptor.process_succeeded {
		descriptor.outcome = descriptor.started ? .Known_Failure : .Cancelled_Before_Start
		return true, descriptor.failure
	}
	if stage_zero.state == .Still_Unmerged {
		descriptor.outcome = .Still_Unmerged
		descriptor.failure = .Process_Failed
		return true, descriptor.failure
	}
	if !sequence_target_is_valid(fresh_sequence) {
		descriptor.outcome = .Indeterminate
		descriptor.failure = .Stale_Observation
		return true, descriptor.failure
	}
	action := descriptor.request.precondition.action
	if action == .Delete_Result {
		if stage_zero.state != .Deleted {
			descriptor.outcome = .Indeterminate
			descriptor.failure = .Process_Failed
			return true, descriptor.failure
		}
		descriptor.outcome = .Deleted
		descriptor.failure = .None
		return true, .None
	}
	if stage_zero.state != .Present || !conflict_resolution_stage_matches_request(stage_zero, descriptor.request) {
		descriptor.outcome = .Indeterminate
		descriptor.failure = .Process_Failed
		return true, descriptor.failure
	}
	descriptor.outcome = .Resolved
	descriptor.failure = .None
	return true, .None
}

/* conflict_resolution_result_descriptor returns copied immutable resolution outcome metadata. */
conflict_resolution_result_descriptor :: proc(
	result: ^Conflict_Resolution_Result,
) -> (Conflict_Resolution_Result_Descriptor, bool) {
	state := conflict_resolution_result_data(result)
	if state == nil do return {}, false
	return state.descriptor, conflict_resolution_result_descriptor_is_valid(state.descriptor)
}

/* conflict_resolution_result_descriptor_is_valid checks process and refreshed-index invariants. */
conflict_resolution_result_descriptor_is_valid :: proc(
	descriptor: Conflict_Resolution_Result_Descriptor,
) -> bool {
	if !conflict_resolution_request_is_valid(descriptor.request) ||
	   descriptor.output_bytes > descriptor.request.limits.stdout_bytes ||
	   descriptor.diagnostic_bytes > descriptor.request.limits.diagnostic_bytes {
		return false
	}
	if !descriptor.started {
		return descriptor.outcome == .Cancelled_Before_Start && descriptor.stage_zero == {} &&
		       descriptor.fresh_sequence == {} && descriptor.exit_status == 0 &&
		       descriptor.output_bytes == 0 && descriptor.diagnostic_bytes == 0 &&
		       descriptor.failure == .Cancelled && !descriptor.process_succeeded &&
		       !descriptor.refresh_required
	}
	if !descriptor.refresh_required ||
	   descriptor.process_succeeded != (descriptor.exit_status == 0 &&
	   (descriptor.failure == .None || descriptor.verified)) {
		return false
	}
	if !descriptor.verified {
		return descriptor.outcome == .Awaiting_Refresh && descriptor.stage_zero == {} &&
		       descriptor.fresh_sequence == {}
	}
	return conflict_stage_zero_is_valid(descriptor.stage_zero) &&
	       descriptor.outcome != .Awaiting_Refresh && descriptor.outcome != .Invalid
}

/* conflict_resolution_result_output returns borrowed bounded public process output and diagnostics. */
conflict_resolution_result_output :: proc(
	result: ^Conflict_Resolution_Result,
) -> (output, diagnostic: []u8, ok: bool) {
	state := conflict_resolution_result_data(result)
	if state == nil do return nil, nil, false
	return state.output[:], state.diagnostic[:], true
}

/* conflict_resolution_result_close releases every owned resolution-result allocation. */
conflict_resolution_result_close :: proc(result: ^Conflict_Resolution_Result) {
	state := conflict_resolution_result_data(result)
	if state == nil do return
	conflict_resolution_result_data_destroy(state)
	result^ = {}
}

conflict_resolution_action_requires_confirmation :: proc(action: Conflict_Resolution_Action) -> bool {
	return action == .Use_Base || action == .Use_Current || action == .Use_Applied || action == .Delete_Result
}

@(private)
conflict_target_is_complete :: proc(target: Conflict_Target) -> bool {
	if target.id == Conflict_ID(0) || target.kind == .Invalid || target.index == 0 || target.worktree == 0 {
		return false
	}
	for stage, index in target.stages {
		if stage.kind != Conflict_Index_Stage_Kind(index + 1) do return false
		if stage.available != revision_identity_is_valid(stage.object) do return false
		if stage.available != (stage.mode != 0) do return false
	}
	return true
}

@(private)
conflict_target_stage_is_available :: proc(
	target: Conflict_Target,
	kind: Conflict_Index_Stage_Kind,
) -> bool {
	for stage in target.stages {
		if stage.kind == kind do return stage.available
	}
	return false
}

@(private)
conflict_target_stage :: proc(
	target: Conflict_Target,
	kind: Conflict_Index_Stage_Kind,
) -> (Conflict_Index_Stage, bool) {
	for stage in target.stages {
		if stage.kind == kind && stage.available do return stage, true
	}
	return {}, false
}

@(private)
conflict_mode_is_supported :: proc(mode: u32) -> bool {
	return mode == 0o100644 || mode == 0o100755 || mode == 0o120000 || mode == 0o160000
}

@(private)
conflict_resolution_confirmation_is_valid :: proc(
	confirmation: Conflict_Resolution_Confirmation,
) -> bool {
	return confirmation.id != Conflict_Resolution_Confirmation_ID(0) &&
	       conflict_resolution_action_requires_confirmation(confirmation.precondition.action) &&
	       conflict_resolution_precondition_is_valid(confirmation.precondition) &&
	       !(confirmation.consumed && !confirmation.confirmed)
}

@(private)
conflict_resolution_stage_matches_request :: proc(
	stage: Conflict_Stage_Zero,
	request: Conflict_Resolution_Request,
) -> bool {
	precondition := request.precondition
	switch precondition.action {
	case .Mark_Saved_Result:
		return stage.mode == precondition.worktree.mode && stage.object == precondition.worktree.git_object
	case .Use_Base:
		expected, found := conflict_target_stage(precondition.target, .Base)
		return found && stage.mode == expected.mode && stage.object == expected.object
	case .Use_Current:
		expected, found := conflict_target_stage(precondition.target, .Current)
		return found && stage.mode == expected.mode && stage.object == expected.object
	case .Use_Applied:
		expected, found := conflict_target_stage(precondition.target, .Applied)
		return found && stage.mode == expected.mode && stage.object == expected.object
	case .Delete_Result, .Invalid:
		return false
	}
	return false
}

@(private)
conflict_resolution_result_data :: proc(
	result: ^Conflict_Resolution_Result,
) -> ^Conflict_Resolution_Result_Data {
	if result == nil || result.state == nil do return nil
	return cast(^Conflict_Resolution_Result_Data)result.state
}

@(private)
conflict_resolution_result_data_destroy :: proc(state: ^Conflict_Resolution_Result_Data) {
	if state == nil do return
	delete(state.output)
	delete(state.diagnostic)
	free(state, state.allocator)
}
