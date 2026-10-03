// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery

import "base:runtime"
import "core:crypto/sha2"

/* MIN_REBASE_PLAN_STEPS is the smallest admitted autosquash preview capacity. */
MIN_REBASE_PLAN_STEPS :: u32(1)
/* MAX_REBASE_PLAN_STEPS is the immutable autosquash preview capacity ceiling. */
MAX_REBASE_PLAN_STEPS :: u32(4_096)
/* DEFAULT_REBASE_PLAN_STEPS is the initial bounded autosquash preview capacity. */
DEFAULT_REBASE_PLAN_STEPS :: u32(512)
/* MIN_REBASE_PLAN_SUBJECT_BYTES is the smallest admitted aggregate subject budget. */
MIN_REBASE_PLAN_SUBJECT_BYTES :: u64(4 * KIBIBYTE)
/* MAX_REBASE_PLAN_SUBJECT_BYTES is the immutable aggregate subject budget ceiling. */
MAX_REBASE_PLAN_SUBJECT_BYTES :: u64(4 * MEBIBYTE)
/* DEFAULT_REBASE_PLAN_SUBJECT_BYTES is the initial aggregate autosquash subject budget. */
DEFAULT_REBASE_PLAN_SUBJECT_BYTES :: u64(256 * KIBIBYTE)
/* REBASE_FINGERPRINT_BYTES is the SHA-256 width for index and reviewed-plan identity. */
REBASE_FINGERPRINT_BYTES :: 32
/* MAX_REBASE_EDITOR_RESOURCES bounds repository buffers checked before replay mutations. */
MAX_REBASE_EDITOR_RESOURCES :: u32(4_096)

/* Rebase_Operation_ID identifies one admitted checked replay action. */
Rebase_Operation_ID :: distinct u64
/* Rebase_Confirmation_ID identifies one exact history-rewrite confirmation. */
Rebase_Confirmation_ID :: distinct u64

/* Rebase_Action selects one closed history-replay mutation. */
Rebase_Action :: enum u8 {
	Invalid,
	Start,
	Continue,
	Skip,
	Abort,
}

/* Rebase_Mode distinguishes Git replay order from one accepted semantic autosquash plan. */
Rebase_Mode :: enum u8 {
	Invalid,
	Ordinary,
	Autosquash,
}

/* Rebase_Replay_Action is the only instruction vocabulary admitted by the reviewed plan. */
Rebase_Replay_Action :: enum u8 {
	Invalid,
	Pick,
	Fixup,
	Squash,
}

/* Rebase_Plan_Limits bounds retained semantic replay steps. */
Rebase_Plan_Limits :: struct {
	steps:         u32,
	subject_bytes: u64,
}

/* DEFAULT_REBASE_PLAN_LIMITS selects the initial bounded autosquash preview capacity. */
DEFAULT_REBASE_PLAN_LIMITS :: Rebase_Plan_Limits {
	steps = DEFAULT_REBASE_PLAN_STEPS,
	subject_bytes = DEFAULT_REBASE_PLAN_SUBJECT_BYTES,
}

/* Rebase_Plan_Fingerprint identifies one complete reviewed semantic replay plan. */
Rebase_Plan_Fingerprint :: struct {
	bytes: [REBASE_FINGERPRINT_BYTES]u8,
}

/* Rebase_Index_Fingerprint identifies one complete staged-index snapshot. */
Rebase_Index_Fingerprint :: struct {
	bytes: [REBASE_FINGERPRINT_BYTES]u8,
}

/* Rebase_Base binds one selected Ref to its resolved complete upstream revision. */
Rebase_Base :: struct {
	reference: Ref_Identity,
	revision:  Revision_Identity,
}

/* Rebase_Replay_Step identifies the exact checked commit currently being replayed. */
Rebase_Replay_Step :: struct {
	position: u32,
	total:    u32,
	action:   Rebase_Replay_Action,
	revision: Revision_Identity,
	target:   Revision_Identity,
}

/* Rebase_Reviewed_Plan binds accepted autosquash semantics to exact replay endpoints. */
Rebase_Reviewed_Plan :: struct {
	fingerprint: Rebase_Plan_Fingerprint,
	old_tip:     Revision_Identity,
	upstream:    Revision_Identity,
	steps:       u32,
	fixups:      u32,
	squashes:    u32,
	accepted:    bool,
}

/* Rebase_Editor_State summarizes repository buffers a replay action may replace. */
Rebase_Editor_State :: struct {
	repository_resources:          u32,
	modified_repository_resources: u32,
}

/* Rebase_Precondition binds one action to exact Status, Ref, sequence, index, and plan truth. */
Rebase_Precondition :: struct {
	repository:           Repository_Context,
	status_generation:    Observation_Generation,
	ref_generation:       Ref_Generation,
	sequence_generation:  Sequence_Generation,
	head:                 Head_Observation,
	branch:               Ref_Identity,
	old_tip:              Revision_Identity,
	base:                 Rebase_Base,
	index_tree:           Index_Tree_Identity,
	index_fingerprint:    Rebase_Index_Fingerprint,
	repository_operation: Operation_State,
	sequence_state:       Sequence_Observation_State,
	sequence:             Sequence_Target,
	step:                 Rebase_Replay_Step,
	worktree_paths:       u32,
	unmerged_paths:       u32,
	editor:               Rebase_Editor_State,
	action:               Rebase_Action,
	mode:                 Rebase_Mode,
	plan:                 Rebase_Reviewed_Plan,
	plan_limits:          Rebase_Plan_Limits,
}

/* Rebase_Confirmation owns one one-shot history-rewrite acknowledgement. */
Rebase_Confirmation :: struct {
	id:           Rebase_Confirmation_ID,
	precondition: Rebase_Precondition,
	confirmed:    bool,
	consumed:     bool,
}

/* Rebase_Request is one closed confirmed replay action with bounded process ownership. */
Rebase_Request :: struct {
	operation:    Rebase_Operation_ID,
	precondition: Rebase_Precondition,
	confirmation: Rebase_Confirmation_ID,
	limits:       Process_Limits,
}

/* Rebase_Outcome separates child completion from refreshed replay authority. */
Rebase_Outcome :: enum u8 {
	Invalid,
	Cancelled_Before_Start,
	Awaiting_Refresh,
	Replayed,
	Paused_Conflict,
	Advanced,
	Skipped,
	Aborted,
	Known_Failure,
	Indeterminate,
}

/* Rebase_Lineage records the exact branch tip, upstream base, and refreshed result. */
Rebase_Lineage :: struct {
	branch:    Ref_Identity,
	old_tip:   Revision_Identity,
	upstream:  Revision_Identity,
	resulting: Revision_Identity,
}

/* Rebase_Result_Descriptor retains bounded child evidence pending refreshed Git verification. */
Rebase_Result_Descriptor :: struct {
	request:           Rebase_Request,
	outcome:           Rebase_Outcome,
	lineage:           Rebase_Lineage,
	sequence:          Sequence_Target,
	step:              Rebase_Replay_Step,
	started:           bool,
	verified:          bool,
	exit_status:       i32,
	output_bytes:      u64,
	diagnostic_bytes:  u64,
	failure:           Failure_Code,
	process_succeeded: bool,
	refresh_required:  bool,
}

/* Rebase_Usage reports reviewed plan and copied child payload sizes. */
Rebase_Usage :: struct {
	plan_steps:       u32,
	output_bytes:     u64,
	diagnostic_bytes: u64,
}

/* Rebase_Result owns one copied child outcome pending refreshed repository verification. */
Rebase_Result :: struct {
	state: rawptr,
}

@(private)
Rebase_Result_Data :: struct {
	descriptor: Rebase_Result_Descriptor,
	output:     [dynamic]u8,
	diagnostic: [dynamic]u8,
	allocator:  runtime.Allocator,
}

/* rebase_plan_limits_are_valid checks the immutable semantic preview bounds. */
rebase_plan_limits_are_valid :: proc(limits: Rebase_Plan_Limits) -> bool {
	return limits.steps >= MIN_REBASE_PLAN_STEPS && limits.steps <= MAX_REBASE_PLAN_STEPS &&
	       limits.subject_bytes >= MIN_REBASE_PLAN_SUBJECT_BYTES &&
	       limits.subject_bytes <= MAX_REBASE_PLAN_SUBJECT_BYTES
}

/* rebase_plan_fingerprint_assign copies one exact nonzero reviewed-plan digest. */
rebase_plan_fingerprint_assign :: proc(fingerprint: ^Rebase_Plan_Fingerprint, bytes: []u8) -> bool {
	if fingerprint == nil do return false
	fingerprint^ = {}
	if len(bytes) != REBASE_FINGERPRINT_BYTES do return false
	copy(fingerprint.bytes[:], bytes)
	return rebase_plan_fingerprint_is_valid(fingerprint^)
}

/* rebase_plan_fingerprint_compute derives one exact digest from a complete semantic plan. */
rebase_plan_fingerprint_compute :: proc(fingerprint: ^Rebase_Plan_Fingerprint, bytes: []u8) -> bool {
	if fingerprint == nil || len(bytes) == 0 do return false
	ctx: sha2.Context_256
	sha2.init_256(&ctx)
	sha2.update(&ctx, bytes)
	sha2.final(&ctx, fingerprint.bytes[:])
	return rebase_plan_fingerprint_is_valid(fingerprint^)
}

/* rebase_plan_fingerprint_is_valid rejects an absent reviewed-plan identity. */
rebase_plan_fingerprint_is_valid :: proc(fingerprint: Rebase_Plan_Fingerprint) -> bool {
	for byte in fingerprint.bytes {
		if byte != 0 do return true
	}
	return false
}

/* rebase_index_fingerprint_assign copies one exact nonzero staged-index digest. */
rebase_index_fingerprint_assign :: proc(fingerprint: ^Rebase_Index_Fingerprint, bytes: []u8) -> bool {
	if fingerprint == nil do return false
	fingerprint^ = {}
	if len(bytes) != REBASE_FINGERPRINT_BYTES do return false
	copy(fingerprint.bytes[:], bytes)
	return rebase_index_fingerprint_is_valid(fingerprint^)
}

/* rebase_index_fingerprint_compute derives one exact digest from a complete staged index. */
rebase_index_fingerprint_compute :: proc(fingerprint: ^Rebase_Index_Fingerprint, bytes: []u8) -> bool {
	if fingerprint == nil do return false
	ctx: sha2.Context_256
	sha2.init_256(&ctx)
	sha2.update(&ctx, bytes)
	sha2.final(&ctx, fingerprint.bytes[:])
	return rebase_index_fingerprint_is_valid(fingerprint^)
}

/* rebase_index_fingerprint_is_valid rejects an absent staged-index identity. */
rebase_index_fingerprint_is_valid :: proc(fingerprint: Rebase_Index_Fingerprint) -> bool {
	for byte in fingerprint.bytes {
		if byte != 0 do return true
	}
	return false
}

/* rebase_base_is_valid checks one selected compatible Ref and resolved upstream revision. */
rebase_base_is_valid :: proc(base: Rebase_Base) -> bool {
	if !ref_identity_is_valid(base.reference) || !revision_identity_is_valid(base.revision) {
		return false
	}
	switch base.reference.kind {
	case .Local_Branch, .Remote_Tracking_Branch:
		return base.reference.object_type == .Commit && base.reference.object == base.revision
	case .Tag:
		if base.reference.object_type == .Commit do return base.reference.object == base.revision
		return base.reference.object_type == .Tag
	case .Invalid:
		return false
	}
	return false
}

/* rebase_replay_step_is_valid admits only exact pick, fixup, or squash step identities. */
rebase_replay_step_is_valid :: proc(step: Rebase_Replay_Step) -> bool {
	if step.position == 0 || step.total == 0 || step.position > step.total ||
	   !revision_identity_is_valid(step.revision) {
		return false
	}
	switch step.action {
	case .Pick:
		return step.target == {}
	case .Fixup, .Squash:
		return revision_identity_is_valid(step.target) && step.target != step.revision
	case .Invalid:
		return false
	}
	return false
}

/* rebase_reviewed_plan_is_valid checks accepted bounded autosquash plan identity and counts. */
rebase_reviewed_plan_is_valid :: proc(
	plan: Rebase_Reviewed_Plan,
	limits := DEFAULT_REBASE_PLAN_LIMITS,
) -> bool {
	return rebase_plan_limits_are_valid(limits) && rebase_plan_fingerprint_is_valid(plan.fingerprint) &&
	       revision_identity_is_valid(plan.old_tip) && revision_identity_is_valid(plan.upstream) &&
	       plan.old_tip != plan.upstream && plan.steps > 0 && plan.steps <= limits.steps &&
	       plan.fixups <= plan.steps && plan.squashes <= plan.steps - plan.fixups && plan.accepted
}

/* rebase_editor_state_is_valid bounds repository buffers and modified-buffer counts. */
rebase_editor_state_is_valid :: proc(state: Rebase_Editor_State) -> bool {
	return state.repository_resources <= MAX_REBASE_EDITOR_RESOURCES &&
	       state.modified_repository_resources <= state.repository_resources
}

/* rebase_precondition_is_valid checks one action-specific exact replay boundary. */
rebase_precondition_is_valid :: proc(precondition: Rebase_Precondition) -> bool {
	if !repository_context_is_valid(precondition.repository) ||
	   precondition.status_generation == Observation_Generation(0) ||
	   precondition.ref_generation == Ref_Generation(0) ||
	   precondition.sequence_generation == Sequence_Generation(0) ||
	   !head_observation_is_valid(precondition.head) ||
	   !ref_identity_is_valid(precondition.branch) || precondition.branch.kind != .Local_Branch ||
	   precondition.branch.repository != precondition.repository ||
	   precondition.branch.generation != precondition.ref_generation ||
	   precondition.branch.object != precondition.old_tip ||
	   !revision_identity_is_valid(precondition.old_tip) || !rebase_base_is_valid(precondition.base) ||
	   precondition.base.reference.repository != precondition.repository ||
	   precondition.base.reference.generation != precondition.ref_generation ||
	   precondition.base.revision == precondition.old_tip ||
	   !rebase_index_fingerprint_is_valid(precondition.index_fingerprint) ||
	   !rebase_editor_state_is_valid(precondition.editor) ||
	   precondition.editor.modified_repository_resources != 0 ||
	   precondition.worktree_paths > MAX_STATUS_PATHS ||
	   precondition.unmerged_paths > precondition.worktree_paths ||
	   !rebase_plan_limits_are_valid(precondition.plan_limits) ||
	   !rebase_mode_plan_is_valid(precondition) {
		return false
	}
	switch precondition.action {
	case .Start:
		return precondition.head.state == .Symbolic && precondition.head.branch == precondition.branch &&
		       precondition.head.object == precondition.old_tip &&
		       precondition.repository_operation == .Normal &&
		       precondition.sequence_state == .Inactive && precondition.sequence == {} &&
		       precondition.step == {} && precondition.worktree_paths == 0 &&
		       precondition.unmerged_paths == 0 && index_tree_identity_is_valid(precondition.index_tree)
	case .Continue:
		return precondition.repository_operation == .Rebasing &&
		       precondition.sequence_state == .Active && sequence_target_is_valid(precondition.sequence) &&
		       precondition.sequence.generation == precondition.sequence_generation &&
		       rebase_replay_step_is_valid(precondition.step) && precondition.unmerged_paths == 0 &&
		       index_tree_identity_is_valid(precondition.index_tree)
	case .Skip:
		return precondition.repository_operation == .Rebasing &&
		       (precondition.sequence_state == .Active || precondition.sequence_state == .Conflicted) &&
		       sequence_target_is_valid(precondition.sequence) &&
		       precondition.sequence.generation == precondition.sequence_generation &&
		       rebase_replay_step_is_valid(precondition.step)
	case .Abort:
		return precondition.repository_operation == .Rebasing &&
		       (precondition.sequence_state == .Active || precondition.sequence_state == .Conflicted) &&
		       sequence_target_is_valid(precondition.sequence) &&
		       precondition.sequence.generation == precondition.sequence_generation &&
		       (precondition.step == {} || rebase_replay_step_is_valid(precondition.step))
	case .Invalid:
		return false
	}
	return false
}

/* rebase_precondition_failure classifies expected admission failures without weakening identity. */
rebase_precondition_failure :: proc(precondition: Rebase_Precondition) -> Failure_Code {
	if !repository_context_is_valid(precondition.repository) ||
	   precondition.status_generation == Observation_Generation(0) ||
	   precondition.ref_generation == Ref_Generation(0) ||
	   precondition.sequence_generation == Sequence_Generation(0) ||
	   !head_observation_is_valid(precondition.head) ||
	   !ref_identity_is_valid(precondition.branch) ||
	   !revision_identity_is_valid(precondition.old_tip) ||
	   !rebase_index_fingerprint_is_valid(precondition.index_fingerprint) ||
	   !rebase_editor_state_is_valid(precondition.editor) ||
	   !rebase_plan_limits_are_valid(precondition.plan_limits) || precondition.action == .Invalid ||
	   precondition.mode == .Invalid {
		return .Invalid_Request
	}
	if precondition.editor.modified_repository_resources != 0 do return .Modified_Buffer
	if precondition.branch.repository != precondition.repository ||
	   precondition.branch.generation != precondition.ref_generation ||
	   precondition.branch.object != precondition.old_tip {
		return .Stale_Observation
	}
	if !rebase_base_is_valid(precondition.base) do return .Ref_Unavailable
	if precondition.base.reference.repository != precondition.repository ||
	   precondition.base.reference.generation != precondition.ref_generation {
		return .Stale_Observation
	}
	if precondition.base.revision == precondition.old_tip do return .Target_Duplicate
	if !rebase_mode_plan_is_valid(precondition) do return .Invalid_Request
	if precondition.worktree_paths > MAX_STATUS_PATHS ||
	   precondition.unmerged_paths > precondition.worktree_paths {
		return .Invalid_Request
	}
	if !rebase_precondition_is_valid(precondition) do return .Action_Unavailable
	return .None
}

/* rebase_confirmation_prepare binds one rewrite acknowledgement to exact checked replay truth. */
rebase_confirmation_prepare :: proc(
	precondition: Rebase_Precondition,
	id: Rebase_Confirmation_ID,
) -> (Rebase_Confirmation, bool, Failure_Code) {
	if id == Rebase_Confirmation_ID(0) do return {}, false, .Invalid_Request
	if failure := rebase_precondition_failure(precondition); failure != .None do return {}, false, failure
	return {id = id, precondition = precondition}, true, .None
}

/* rebase_confirmation_confirm accepts only the exact unused confirmation identity. */
rebase_confirmation_confirm :: proc(
	confirmation: ^Rebase_Confirmation,
	id: Rebase_Confirmation_ID,
) -> (bool, Failure_Code) {
	if confirmation == nil || !rebase_confirmation_input_is_valid(confirmation^) {
		return false, .Invalid_Request
	}
	if confirmation.id != id || confirmation.confirmed || confirmation.consumed {
		return false, .Confirmation_Mismatch
	}
	confirmation.confirmed = true
	return true, .None
}

/* rebase_request_prepare consumes one exact confirmation into a closed process request. */
rebase_request_prepare :: proc(
	precondition: Rebase_Precondition,
	operation: Rebase_Operation_ID,
	confirmation: ^Rebase_Confirmation,
	limits := DEFAULT_PROCESS_LIMITS,
) -> (Rebase_Request, bool, Failure_Code) {
	if operation == Rebase_Operation_ID(0) || !process_limits_are_valid(limits) {
		return {}, false, .Invalid_Request
	}
	if failure := rebase_precondition_failure(precondition); failure != .None do return {}, false, failure
	if confirmation == nil || !confirmation.confirmed do return {}, false, .Confirmation_Required
	if confirmation.consumed || !rebase_confirmation_input_is_valid(confirmation^) ||
	   confirmation.precondition != precondition {
		return {}, false, .Confirmation_Mismatch
	}
	confirmation.consumed = true
	request := Rebase_Request {
		operation = operation,
		precondition = precondition,
		confirmation = confirmation.id,
		limits = limits,
	}
	return request, rebase_request_is_valid(request), .None
}

/* rebase_request_is_valid checks one closed request with no free-form todo instructions. */
rebase_request_is_valid :: proc(request: Rebase_Request) -> bool {
	return request.operation != Rebase_Operation_ID(0) &&
	       request.confirmation != Rebase_Confirmation_ID(0) &&
	       rebase_precondition_is_valid(request.precondition) && process_limits_are_valid(request.limits)
}

/* rebase_request_revalidate rejects any changed repository, editor, step, or plan truth. */
rebase_request_revalidate :: proc(
	current: Rebase_Precondition,
	request: Rebase_Request,
) -> (bool, Failure_Code) {
	if !rebase_request_is_valid(request) do return false, .Invalid_Request
	if failure := rebase_precondition_failure(current); failure != .None do return false, failure
	if current != request.precondition do return false, .Stale_Observation
	return true, .None
}

/* rebase_result_open copies one bounded child outcome pending mandatory repository refresh. */
rebase_result_open :: proc(
	request: Rebase_Request,
	started: bool,
	exit_status: i32,
	output: []u8,
	diagnostic: []u8,
	process_failure := Failure_Code.None,
	allocator := context.allocator,
) -> (Rebase_Result, bool, Failure_Code) {
	if allocator.procedure == nil || !rebase_request_is_valid(request) do return {}, false, .Invalid_Request
	if u64(len(output)) > request.limits.stdout_bytes ||
	   u64(len(diagnostic)) > request.limits.diagnostic_bytes {
		return {}, false, .Output_Limit
	}
	if !started && (process_failure != .Cancelled || exit_status != 0 || len(output) != 0 || len(diagnostic) != 0) {
		return {}, false, .Invalid_Request
	}
	failure := process_failure
	if started && failure == .None && exit_status != 0 do failure = .Process_Failed
	state, allocation_error := new(Rebase_Result_Data, allocator)
	if allocation_error != nil do return {}, false, .Allocation
	state.allocator = allocator
	state.descriptor = {
		request = request,
		outcome = started ? .Awaiting_Refresh : .Cancelled_Before_Start,
		lineage = {
			branch = request.precondition.branch,
			old_tip = request.precondition.old_tip,
			upstream = request.precondition.base.revision,
		},
		step = request.precondition.step,
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
		rebase_result_data_destroy(state)
		return {}, false, .Allocation
	}
	return Rebase_Result{state = state}, true, .None
}

/* rebase_result_descriptor returns copied immutable replay child metadata. */
rebase_result_descriptor :: proc(result: ^Rebase_Result) -> (Rebase_Result_Descriptor, bool) {
	state := rebase_result_data(result)
	if state == nil do return {}, false
	return state.descriptor, rebase_result_descriptor_is_valid(state.descriptor)
}

/* rebase_result_verify classifies one child outcome against refreshed Ref and Sequence truth. */
rebase_result_verify :: proc(
	result: ^Rebase_Result,
	refs: ^Ref_Observation,
	sequence: ^Sequence_Observation,
) -> (bool, Failure_Code) {
	state := rebase_result_data(result)
	refs_descriptor, refs_described := ref_observation_descriptor(refs)
	sequence_descriptor, sequence_described := sequence_observation_descriptor(sequence)
	if state == nil || state.descriptor.verified || !state.descriptor.started ||
	   !state.descriptor.refresh_required || !refs_described || !sequence_described ||
	   refs_descriptor.repository != state.descriptor.request.precondition.repository ||
	   sequence_descriptor.repository != refs_descriptor.repository {
		return false, .Invalid_Request
	}
	descriptor := &state.descriptor
	precondition := descriptor.request.precondition
	branch, branch_found := rebase_result_find_branch(refs, precondition.branch.name)
	if !branch_found {
		descriptor.verified = true
		descriptor.outcome = .Indeterminate
		descriptor.failure = .Stale_Observation
		return true, descriptor.failure
	}
	descriptor.verified = true
	descriptor.lineage.resulting = branch.object
	if sequence_descriptor.state != .Inactive {
		if sequence_descriptor.kind != .Rebase ||
		   (sequence_descriptor.state != .Active && sequence_descriptor.state != .Conflicted) {
			descriptor.outcome = .Indeterminate
			descriptor.failure = .Stale_Observation
			return true, descriptor.failure
		}
		descriptor.sequence = {
			generation = sequence_descriptor.generation,
			fingerprint = sequence_descriptor.fingerprint,
		}
		descriptor.outcome = .Advanced
		if precondition.action == .Start && sequence_descriptor.state == .Conflicted {
			descriptor.outcome = .Paused_Conflict
		} else if precondition.action == .Skip {
			descriptor.outcome = .Skipped
		}
		descriptor.failure = descriptor.process_succeeded ? .None : .Process_Failed
		return true, descriptor.failure
	}
	if refs_descriptor.head.state != .Symbolic || refs_descriptor.head.branch.name != precondition.branch.name ||
	   refs_descriptor.head.object != branch.object {
		descriptor.outcome = .Indeterminate
		descriptor.failure = .Stale_Observation
		return true, descriptor.failure
	}
	if !descriptor.process_succeeded {
		descriptor.outcome = .Known_Failure
		return true, descriptor.failure
	}
	switch precondition.action {
	case .Start:
		descriptor.outcome = .Replayed
	case .Continue:
		descriptor.outcome = .Advanced
	case .Skip:
		descriptor.outcome = .Skipped
	case .Abort:
		if branch.object != precondition.old_tip {
			descriptor.outcome = .Indeterminate
			descriptor.failure = .Stale_Observation
			return true, descriptor.failure
		}
		descriptor.outcome = .Aborted
	case .Invalid:
		descriptor.outcome = .Indeterminate
		descriptor.failure = .Invalid_Request
		return true, descriptor.failure
	}
	descriptor.failure = .None
	return true, .None
}

/* rebase_result_usage reports exact reviewed-plan and copied result payload sizes. */
rebase_result_usage :: proc(result: ^Rebase_Result) -> (Rebase_Usage, bool) {
	state := rebase_result_data(result)
	if state == nil do return {}, false
	return {
		plan_steps = state.descriptor.request.precondition.plan.steps,
		output_bytes = u64(len(state.output)),
		diagnostic_bytes = u64(len(state.diagnostic)),
	}, true
}

/* rebase_result_close releases one owned replay result and clears its handle. */
rebase_result_close :: proc(result: ^Rebase_Result) {
	state := rebase_result_data(result)
	if state == nil do return
	rebase_result_data_destroy(state)
	result^ = {}
}

@(private)
rebase_mode_plan_is_valid :: proc(precondition: Rebase_Precondition) -> bool {
	switch precondition.mode {
	case .Ordinary:
		return precondition.plan == {}
	case .Autosquash:
		return rebase_reviewed_plan_is_valid(precondition.plan, precondition.plan_limits) &&
		       precondition.plan.old_tip == precondition.old_tip &&
		       precondition.plan.upstream == precondition.base.revision
	case .Invalid:
		return false
	}
	return false
}

@(private)
rebase_confirmation_input_is_valid :: proc(confirmation: Rebase_Confirmation) -> bool {
	return confirmation.id != Rebase_Confirmation_ID(0) &&
	       rebase_precondition_is_valid(confirmation.precondition) &&
	       !(confirmation.consumed && !confirmation.confirmed)
}

@(private)
rebase_result_descriptor_is_valid :: proc(descriptor: Rebase_Result_Descriptor) -> bool {
	if !rebase_request_is_valid(descriptor.request) ||
	   descriptor.output_bytes > descriptor.request.limits.stdout_bytes ||
	   descriptor.diagnostic_bytes > descriptor.request.limits.diagnostic_bytes ||
	   descriptor.lineage.branch != descriptor.request.precondition.branch ||
	   descriptor.lineage.old_tip != descriptor.request.precondition.old_tip ||
	   descriptor.lineage.upstream != descriptor.request.precondition.base.revision ||
	   descriptor.step != descriptor.request.precondition.step {
		return false
	}
	if !descriptor.started {
		return descriptor.outcome == .Cancelled_Before_Start && descriptor.exit_status == 0 &&
		       descriptor.output_bytes == 0 && descriptor.diagnostic_bytes == 0 &&
		       descriptor.failure == .Cancelled && !descriptor.process_succeeded &&
		       !descriptor.refresh_required
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
	if descriptor.outcome == .Paused_Conflict ||
	   ((descriptor.outcome == .Advanced || descriptor.outcome == .Skipped) && descriptor.sequence != {}) {
		return sequence_target_is_valid(descriptor.sequence)
	}
	return descriptor.sequence == {}
}

@(private)
rebase_result_find_branch :: proc(refs: ^Ref_Observation, name: Ref_Name) -> (Ref_Identity, bool) {
	count, counted := ref_observation_ref_count(refs)
	if !counted do return {}, false
	for index in 0 ..< count {
		candidate, found := ref_observation_ref(refs, index)
		if !found do return {}, false
		if candidate.kind == .Local_Branch && candidate.name == name do return candidate, true
	}
	return {}, false
}

@(private)
rebase_result_data :: proc(result: ^Rebase_Result) -> ^Rebase_Result_Data {
	if result == nil || result.state == nil do return nil
	return cast(^Rebase_Result_Data)result.state
}

@(private)
rebase_result_data_destroy :: proc(state: ^Rebase_Result_Data) {
	if state == nil do return
	allocator := state.allocator
	delete(state.output)
	delete(state.diagnostic)
	free(state, allocator)
}
