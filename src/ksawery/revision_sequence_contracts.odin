// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery

import "base:runtime"
import "core:crypto/sha2"

/* MIN_REVISION_SEQUENCE_COMMITS is the smallest admitted ordered commit-set capacity. */
MIN_REVISION_SEQUENCE_COMMITS :: u32(1)
/* MAX_REVISION_SEQUENCE_COMMITS is the immutable ordered commit-set capacity ceiling. */
MAX_REVISION_SEQUENCE_COMMITS :: u32(4_096)
/* DEFAULT_REVISION_SEQUENCE_COMMITS is the initial ordered commit-set capacity. */
DEFAULT_REVISION_SEQUENCE_COMMITS :: u32(256)
/* REVISION_SEQUENCE_FINGERPRINT_BYTES is the SHA-256 width for ordered set and index identities. */
REVISION_SEQUENCE_FINGERPRINT_BYTES :: 32
/* MAX_REVISION_SEQUENCE_EDITOR_RESOURCES bounds repository buffers checked before mutation. */
MAX_REVISION_SEQUENCE_EDITOR_RESOURCES :: u32(4_096)

/* Revision_Sequence_Operation_ID identifies one admitted cherry-pick or revert action. */
Revision_Sequence_Operation_ID :: distinct u64
/* Revision_Sequence_Confirmation_ID identifies one exact sequence-action confirmation. */
Revision_Sequence_Confirmation_ID :: distinct u64

/* Revision_Sequence_Family selects one closed exact-commit application family. */
Revision_Sequence_Family :: enum u8 {
	Invalid,
	Cherry_Pick,
	Revert,
}

/* Revision_Sequence_Action selects one closed family-specific mutation. */
Revision_Sequence_Action :: enum u8 {
	Invalid,
	Start,
	Continue,
	Skip,
	Abort,
}

/* Revision_Sequence_Message_Mode defines the bounded commit-message authority for one action. */
Revision_Sequence_Message_Mode :: enum u8 {
	Invalid,
	Not_Used,
	Preserve_Selected,
	Git_Prepared,
	Composed,
}

/* Revision_Sequence_Signing_Mode keeps configured signing explicit without bypassing repository policy. */
Revision_Sequence_Signing_Mode :: enum u8 {
	Invalid,
	Not_Used,
	Configured,
}

/* Revision_Sequence_Limits bounds one retained ordered exact commit set. */
Revision_Sequence_Limits :: struct {
	commits: u32,
}

/* DEFAULT_REVISION_SEQUENCE_LIMITS selects the initial ordered commit-set capacity. */
DEFAULT_REVISION_SEQUENCE_LIMITS :: Revision_Sequence_Limits {
	commits = DEFAULT_REVISION_SEQUENCE_COMMITS,
}

/* Revision_Sequence_Fingerprint identifies one ordered set of exact commits and mainlines. */
Revision_Sequence_Fingerprint :: struct {
	bytes: [REVISION_SEQUENCE_FINGERPRINT_BYTES]u8,
}

/* Revision_Sequence_Index_Fingerprint identifies one complete staged-index snapshot. */
Revision_Sequence_Index_Fingerprint :: struct {
	bytes: [REVISION_SEQUENCE_FINGERPRINT_BYTES]u8,
}

/* Revision_Sequence_Mainline binds a merge commit to one exact numbered parent. */
Revision_Sequence_Mainline :: struct {
	number: u8,
	parent: Revision_Identity,
}

/* Revision_Sequence_Target identifies one exact commit and any required merge mainline. */
Revision_Sequence_Target :: struct {
	revision:     Revision_Identity,
	parent_count: u8,
	mainline:     Revision_Sequence_Mainline,
}

/* Revision_Sequence_Set_Identity binds an ordered commit count to its exact fingerprint. */
Revision_Sequence_Set_Identity :: struct {
	fingerprint: Revision_Sequence_Fingerprint,
	commits:     u32,
	merges:      u32,
}

/* Revision_Sequence_Set_Usage reports exact retained ordered target ownership. */
Revision_Sequence_Set_Usage :: struct {
	commits:          u32,
	merges:           u32,
	allocation_bytes: u64,
}

/* Revision_Sequence_Set owns one bounded ordered set of exact commit targets. */
Revision_Sequence_Set :: struct {
	state: rawptr,
}

@(private)
Revision_Sequence_Set_Data :: struct {
	identity:  Revision_Sequence_Set_Identity,
	targets:   [dynamic]Revision_Sequence_Target,
	limits:    Revision_Sequence_Limits,
	allocator: runtime.Allocator,
}

/* Revision_Sequence_Editor_State summarizes repository buffers one sequence action may replace. */
Revision_Sequence_Editor_State :: struct {
	repository_resources:          u32,
	modified_repository_resources: u32,
}

/* Revision_Sequence_Message binds one closed message behavior to optional composed content. */
Revision_Sequence_Message :: struct {
	mode:    Revision_Sequence_Message_Mode,
	content: Commit_Message,
}

/* Revision_Sequence_Step identifies one exact currently applied or reverted commit. */
Revision_Sequence_Step :: struct {
	position: u32,
	total:    u32,
	target:   Revision_Sequence_Target,
}

/* Revision_Sequence_Origin records the exact pre-sequence local branch name and revision. */
Revision_Sequence_Origin :: struct {
	branch:   Ref_Name,
	revision: Revision_Identity,
}

/* Revision_Sequence_Precondition binds one action to exact repository and ordered-set truth. */
Revision_Sequence_Precondition :: struct {
	repository:           Repository_Context,
	status_generation:    Observation_Generation,
	history_generation:   History_Generation,
	ref_generation:       Ref_Generation,
	sequence_generation:  Sequence_Generation,
	head:                 Head_Observation,
	original_head:        Revision_Sequence_Origin,
	index_tree:           Index_Tree_Identity,
	index_fingerprint:    Revision_Sequence_Index_Fingerprint,
	repository_operation: Operation_State,
	sequence_kind:        Sequence_Kind,
	sequence_state:       Sequence_Observation_State,
	sequence:             Sequence_Target,
	step:                 Revision_Sequence_Step,
	worktree_paths:       u32,
	unmerged_paths:       u32,
	editor:               Revision_Sequence_Editor_State,
	family:               Revision_Sequence_Family,
	action:               Revision_Sequence_Action,
	selection:            Revision_Sequence_Set_Identity,
	message:              Revision_Sequence_Message,
	signing:              Revision_Sequence_Signing_Mode,
}

/* Revision_Sequence_Confirmation owns one one-shot acknowledgement of an exact action. */
Revision_Sequence_Confirmation :: struct {
	id:           Revision_Sequence_Confirmation_ID,
	precondition: Revision_Sequence_Precondition,
	confirmed:    bool,
	consumed:     bool,
}

/* Revision_Sequence_Request is one closed confirmed sequence action with bounded process ownership. */
Revision_Sequence_Request :: struct {
	operation:    Revision_Sequence_Operation_ID,
	precondition: Revision_Sequence_Precondition,
	confirmation: Revision_Sequence_Confirmation_ID,
	limits:       Process_Limits,
}

/* Revision_Sequence_Outcome separates child completion from refreshed repository authority. */
Revision_Sequence_Outcome :: enum u8 {
	Invalid,
	Cancelled_Before_Start,
	Awaiting_Refresh,
	Completed,
	Paused_Conflict,
	Advanced,
	Skipped,
	Aborted,
	Known_Partial_State,
	Indeterminate,
}

/* Revision_Sequence_Lineage records the original branch, ordered set, and refreshed result. */
Revision_Sequence_Lineage :: struct {
	original_head: Revision_Sequence_Origin,
	selection:     Revision_Sequence_Set_Identity,
	resulting:     Revision_Identity,
}

/* Revision_Sequence_Result_Descriptor retains bounded child evidence pending refreshed verification. */
Revision_Sequence_Result_Descriptor :: struct {
	request:           Revision_Sequence_Request,
	outcome:           Revision_Sequence_Outcome,
	lineage:           Revision_Sequence_Lineage,
	sequence:          Sequence_Target,
	step:              Revision_Sequence_Step,
	started:           bool,
	verified:          bool,
	exit_status:       i32,
	output_bytes:      u64,
	diagnostic_bytes:  u64,
	failure:           Failure_Code,
	process_succeeded: bool,
	refresh_required:  bool,
}

/* Revision_Sequence_Usage reports ordered targets, message bytes, and copied child payload sizes. */
Revision_Sequence_Usage :: struct {
	commits:          u32,
	message_bytes:    u64,
	output_bytes:     u64,
	diagnostic_bytes: u64,
}

/* Revision_Sequence_Result owns one copied child outcome pending refreshed repository verification. */
Revision_Sequence_Result :: struct {
	state: rawptr,
}

@(private)
Revision_Sequence_Result_Data :: struct {
	descriptor: Revision_Sequence_Result_Descriptor,
	output:     [dynamic]u8,
	diagnostic: [dynamic]u8,
	allocator:  runtime.Allocator,
}

/* revision_sequence_limits_are_valid checks the immutable ordered commit-set bound. */
revision_sequence_limits_are_valid :: proc(limits: Revision_Sequence_Limits) -> bool {
	return limits.commits >= MIN_REVISION_SEQUENCE_COMMITS && limits.commits <= MAX_REVISION_SEQUENCE_COMMITS
}

/* revision_sequence_fingerprint_is_valid rejects an absent ordered-set identity. */
revision_sequence_fingerprint_is_valid :: proc(fingerprint: Revision_Sequence_Fingerprint) -> bool {
	for byte in fingerprint.bytes {
		if byte != 0 do return true
	}
	return false
}

/* revision_sequence_index_fingerprint_assign copies one exact nonzero staged-index digest. */
revision_sequence_index_fingerprint_assign :: proc(
	fingerprint: ^Revision_Sequence_Index_Fingerprint,
	bytes: []u8,
) -> bool {
	if fingerprint == nil do return false
	fingerprint^ = {}
	if len(bytes) != REVISION_SEQUENCE_FINGERPRINT_BYTES do return false
	copy(fingerprint.bytes[:], bytes)
	return revision_sequence_index_fingerprint_is_valid(fingerprint^)
}

/* revision_sequence_index_fingerprint_compute derives one digest from complete staged-index bytes. */
revision_sequence_index_fingerprint_compute :: proc(
	fingerprint: ^Revision_Sequence_Index_Fingerprint,
	bytes: []u8,
) -> bool {
	if fingerprint == nil do return false
	ctx: sha2.Context_256
	sha2.init_256(&ctx)
	sha2.update(&ctx, bytes)
	sha2.final(&ctx, fingerprint.bytes[:])
	return revision_sequence_index_fingerprint_is_valid(fingerprint^)
}

/* revision_sequence_index_fingerprint_is_valid rejects an absent staged-index identity. */
revision_sequence_index_fingerprint_is_valid :: proc(fingerprint: Revision_Sequence_Index_Fingerprint) -> bool {
	for byte in fingerprint.bytes {
		if byte != 0 do return true
	}
	return false
}

/* revision_sequence_mainline_is_valid checks a merge mainline number and exact parent identity. */
revision_sequence_mainline_is_valid :: proc(
	mainline: Revision_Sequence_Mainline,
	parent_count: u8,
) -> bool {
	return parent_count > 1 && mainline.number > 0 && mainline.number <= parent_count &&
	       revision_identity_is_valid(mainline.parent)
}

/* revision_sequence_target_is_valid requires a mainline exactly when the target is a merge commit. */
revision_sequence_target_is_valid :: proc(target: Revision_Sequence_Target) -> bool {
	if !revision_identity_is_valid(target.revision) do return false
	if target.parent_count <= 1 do return target.mainline == {}
	return revision_sequence_mainline_is_valid(target.mainline, target.parent_count) &&
	       target.mainline.parent != target.revision
}

/* revision_sequence_set_identity_is_valid checks one bounded nonempty ordered-set identity. */
revision_sequence_set_identity_is_valid :: proc(
	identity: Revision_Sequence_Set_Identity,
	limits := DEFAULT_REVISION_SEQUENCE_LIMITS,
) -> bool {
	return revision_sequence_limits_are_valid(limits) &&
	       revision_sequence_fingerprint_is_valid(identity.fingerprint) &&
	       identity.commits > 0 && identity.commits <= limits.commits && identity.merges <= identity.commits
}

/* revision_sequence_set_open copies one exact ordered target list without positional display authority. */
revision_sequence_set_open :: proc(
	targets: []Revision_Sequence_Target,
	limits := DEFAULT_REVISION_SEQUENCE_LIMITS,
	allocator := context.allocator,
) -> (Revision_Sequence_Set, bool, Failure_Code) {
	if allocator.procedure == nil || !revision_sequence_limits_are_valid(limits) || len(targets) == 0 {
		return {}, false, .Invalid_Request
	}
	if u64(len(targets)) > u64(limits.commits) do return {}, false, .Target_Limit
	state, allocation_error := new(Revision_Sequence_Set_Data, allocator)
	if allocation_error != nil do return {}, false, .Allocation
	state.allocator = allocator
	state.limits = limits
	state.targets, allocation_error = make([dynamic]Revision_Sequence_Target, len(targets), allocator)
	if allocation_error != nil {
		revision_sequence_set_data_destroy(state)
		return {}, false, .Allocation
	}
	for target, index in targets {
		if !revision_sequence_target_is_valid(target) {
			revision_sequence_set_data_destroy(state)
			return {}, false, .Target_Incompatible
		}
		for previous in 0 ..< index {
			if targets[previous].revision == target.revision {
				revision_sequence_set_data_destroy(state)
				return {}, false, .Target_Duplicate
			}
		}
		state.targets[index] = target
		if target.parent_count > 1 do state.identity.merges += 1
	}
	state.identity.commits = u32(len(targets))
	if !revision_sequence_set_fingerprint_compute(&state.identity.fingerprint, state.targets[:]) {
		revision_sequence_set_data_destroy(state)
		return {}, false, .Invalid_Request
	}
	return Revision_Sequence_Set{state = state}, true, .None
}

/* revision_sequence_set_descriptor returns the copied immutable ordered-set identity. */
revision_sequence_set_descriptor :: proc(
	set: ^Revision_Sequence_Set,
) -> (Revision_Sequence_Set_Identity, bool) {
	state := revision_sequence_set_data(set)
	if state == nil do return {}, false
	return state.identity, revision_sequence_set_identity_is_valid(state.identity, state.limits)
}

/* revision_sequence_set_target returns one copied target in confirmed application order. */
revision_sequence_set_target :: proc(
	set: ^Revision_Sequence_Set,
	ordinal: u32,
) -> (Revision_Sequence_Target, bool) {
	state := revision_sequence_set_data(set)
	if state == nil || ordinal >= u32(len(state.targets)) do return {}, false
	return state.targets[ordinal], true
}

/* revision_sequence_set_matches checks one resource against a retained exact ordered-set identity. */
revision_sequence_set_matches :: proc(
	set: ^Revision_Sequence_Set,
	identity: Revision_Sequence_Set_Identity,
) -> bool {
	descriptor, described := revision_sequence_set_descriptor(set)
	return described && descriptor == identity
}

/* revision_sequence_set_usage reports exact retained target allocation. */
revision_sequence_set_usage :: proc(
	set: ^Revision_Sequence_Set,
) -> (Revision_Sequence_Set_Usage, bool) {
	state := revision_sequence_set_data(set)
	if state == nil do return {}, false
	return {
		commits = state.identity.commits,
		merges = state.identity.merges,
		allocation_bytes = u64(size_of(Revision_Sequence_Set_Data)) +
		                   u64(cap(state.targets)) * u64(size_of(Revision_Sequence_Target)),
	}, true
}

/* revision_sequence_set_close releases one ordered target owner and clears its handle. */
revision_sequence_set_close :: proc(set: ^Revision_Sequence_Set) {
	state := revision_sequence_set_data(set)
	if state == nil do return
	revision_sequence_set_data_destroy(state)
	set^ = {}
}

/* revision_sequence_editor_state_is_valid bounds repository and modified-buffer counts. */
revision_sequence_editor_state_is_valid :: proc(state: Revision_Sequence_Editor_State) -> bool {
	return state.repository_resources <= MAX_REVISION_SEQUENCE_EDITOR_RESOURCES &&
	       state.modified_repository_resources <= state.repository_resources
}

/* revision_sequence_message_is_valid checks one action-independent closed message choice. */
revision_sequence_message_is_valid :: proc(message: Revision_Sequence_Message) -> bool {
	switch message.mode {
	case .Not_Used, .Preserve_Selected, .Git_Prepared:
		return message.content == {}
	case .Composed:
		return commit_message_is_valid(message.content)
	case .Invalid:
		return false
	}
	return false
}

/* revision_sequence_step_is_valid checks one exact bounded active sequence step. */
revision_sequence_step_is_valid :: proc(step: Revision_Sequence_Step) -> bool {
	return step.position > 0 && step.total > 0 && step.position <= step.total &&
	       revision_sequence_target_is_valid(step.target)
}

/* revision_sequence_origin_is_valid checks one exact pre-sequence local branch boundary. */
revision_sequence_origin_is_valid :: proc(origin: Revision_Sequence_Origin) -> bool {
	return ref_name_is_valid(origin.branch) && revision_identity_is_valid(origin.revision)
}

/* revision_sequence_precondition_is_valid checks one complete family-specific mutation boundary. */
revision_sequence_precondition_is_valid :: proc(precondition: Revision_Sequence_Precondition) -> bool {
	if !repository_context_is_valid(precondition.repository) ||
	   precondition.status_generation == Observation_Generation(0) ||
	   precondition.history_generation == History_Generation(0) ||
	   precondition.ref_generation == Ref_Generation(0) ||
	   precondition.sequence_generation == Sequence_Generation(0) ||
	   !head_observation_is_valid(precondition.head) ||
	   precondition.head.state != .Symbolic || precondition.head.branch.kind != .Local_Branch ||
	   precondition.head.branch.repository != precondition.repository ||
	   precondition.head.branch.generation != precondition.ref_generation ||
	   !revision_sequence_origin_is_valid(precondition.original_head) ||
	   precondition.head.branch.name != precondition.original_head.branch ||
	   !revision_sequence_index_fingerprint_is_valid(precondition.index_fingerprint) ||
	   !revision_sequence_editor_state_is_valid(precondition.editor) ||
	   precondition.editor.modified_repository_resources != 0 ||
	   precondition.worktree_paths > MAX_STATUS_PATHS ||
	   precondition.unmerged_paths > precondition.worktree_paths ||
	   !revision_sequence_set_identity_is_valid(precondition.selection) ||
	   !revision_sequence_message_is_valid(precondition.message) ||
	   precondition.family == .Invalid || precondition.action == .Invalid ||
	   precondition.sequence_kind == .Invalid {
		return false
	}
	expected_operation, expected_kind, family_valid := revision_sequence_family_state(precondition.family)
	if !family_valid do return false
	switch precondition.action {
	case .Start:
		return precondition.head.object == precondition.original_head.revision &&
		       precondition.repository_operation == .Normal && precondition.sequence_state == .Inactive &&
		       precondition.sequence_kind == .None &&
		       precondition.sequence == {} && precondition.step == {} && precondition.worktree_paths == 0 &&
		       precondition.unmerged_paths == 0 && index_tree_identity_is_valid(precondition.index_tree) &&
		       revision_sequence_start_message_is_valid(precondition.message, precondition.selection.commits) &&
		       precondition.signing == .Configured
	case .Continue:
		return precondition.repository_operation == expected_operation &&
		       precondition.sequence_kind == expected_kind &&
		       precondition.sequence_state == .Active && sequence_target_is_valid(precondition.sequence) &&
		       precondition.sequence.generation == precondition.sequence_generation &&
		       revision_sequence_step_is_valid(precondition.step) &&
		       precondition.step.position <= precondition.selection.commits && precondition.unmerged_paths == 0 &&
		       index_tree_identity_is_valid(precondition.index_tree) &&
		       (precondition.message.mode == .Git_Prepared || precondition.message.mode == .Composed) &&
		       precondition.signing == .Configured && expected_kind != .None
	case .Skip:
		return precondition.repository_operation == expected_operation &&
		       precondition.sequence_kind == expected_kind &&
		       (precondition.sequence_state == .Active || precondition.sequence_state == .Conflicted) &&
		       sequence_target_is_valid(precondition.sequence) &&
		       precondition.sequence.generation == precondition.sequence_generation &&
		       revision_sequence_step_is_valid(precondition.step) &&
		       precondition.step.position <= precondition.selection.commits &&
		       precondition.message.mode == .Not_Used && precondition.signing == .Not_Used &&
		       expected_kind != .None
	case .Abort:
		return precondition.repository_operation == expected_operation &&
		       precondition.sequence_kind == expected_kind &&
		       (precondition.sequence_state == .Active || precondition.sequence_state == .Conflicted) &&
		       sequence_target_is_valid(precondition.sequence) &&
		       precondition.sequence.generation == precondition.sequence_generation &&
		       (precondition.step == {} || revision_sequence_step_is_valid(precondition.step)) &&
		       precondition.message.mode == .Not_Used && precondition.signing == .Not_Used &&
		       expected_kind != .None
	case .Invalid:
		return false
	}
	return false
}

/* revision_sequence_precondition_failure classifies expected admission failures. */
revision_sequence_precondition_failure :: proc(precondition: Revision_Sequence_Precondition) -> Failure_Code {
	if !repository_context_is_valid(precondition.repository) ||
	   precondition.status_generation == Observation_Generation(0) ||
	   precondition.history_generation == History_Generation(0) ||
	   precondition.ref_generation == Ref_Generation(0) ||
	   precondition.sequence_generation == Sequence_Generation(0) ||
	   !head_observation_is_valid(precondition.head) ||
	   !revision_sequence_origin_is_valid(precondition.original_head) ||
	   !revision_sequence_index_fingerprint_is_valid(precondition.index_fingerprint) ||
	   !revision_sequence_editor_state_is_valid(precondition.editor) ||
	   !revision_sequence_set_identity_is_valid(precondition.selection) ||
	   !revision_sequence_message_is_valid(precondition.message) ||
	   precondition.family == .Invalid || precondition.action == .Invalid ||
	   precondition.signing == .Invalid || precondition.sequence_kind == .Invalid {
		return .Invalid_Request
	}
	if precondition.editor.modified_repository_resources != 0 do return .Modified_Buffer
	if precondition.head.branch.repository != precondition.repository ||
	   precondition.head.branch.generation != precondition.ref_generation ||
	   precondition.head.branch.name != precondition.original_head.branch {
		return .Stale_Observation
	}
	if precondition.worktree_paths > MAX_STATUS_PATHS ||
	   precondition.unmerged_paths > precondition.worktree_paths {
		return .Invalid_Request
	}
	if !revision_sequence_precondition_is_valid(precondition) do return .Action_Unavailable
	return .None
}

/* revision_sequence_confirmation_prepare binds one acknowledgement to exact action truth. */
revision_sequence_confirmation_prepare :: proc(
	precondition: Revision_Sequence_Precondition,
	id: Revision_Sequence_Confirmation_ID,
) -> (Revision_Sequence_Confirmation, bool, Failure_Code) {
	if id == Revision_Sequence_Confirmation_ID(0) do return {}, false, .Invalid_Request
	if failure := revision_sequence_precondition_failure(precondition); failure != .None {
		return {}, false, failure
	}
	return {id = id, precondition = precondition}, true, .None
}

/* revision_sequence_confirmation_confirm accepts only the exact unused confirmation identity. */
revision_sequence_confirmation_confirm :: proc(
	confirmation: ^Revision_Sequence_Confirmation,
	id: Revision_Sequence_Confirmation_ID,
) -> (bool, Failure_Code) {
	if confirmation == nil || !revision_sequence_confirmation_input_is_valid(confirmation^) {
		return false, .Invalid_Request
	}
	if confirmation.id != id || confirmation.confirmed || confirmation.consumed {
		return false, .Confirmation_Mismatch
	}
	confirmation.confirmed = true
	return true, .None
}

/* revision_sequence_request_prepare consumes one exact confirmation into a closed request. */
revision_sequence_request_prepare :: proc(
	precondition: Revision_Sequence_Precondition,
	operation: Revision_Sequence_Operation_ID,
	confirmation: ^Revision_Sequence_Confirmation,
	limits := DEFAULT_PROCESS_LIMITS,
) -> (Revision_Sequence_Request, bool, Failure_Code) {
	if operation == Revision_Sequence_Operation_ID(0) || !process_limits_are_valid(limits) {
		return {}, false, .Invalid_Request
	}
	if failure := revision_sequence_precondition_failure(precondition); failure != .None {
		return {}, false, failure
	}
	if confirmation == nil || !confirmation.confirmed do return {}, false, .Confirmation_Required
	if confirmation.consumed || !revision_sequence_confirmation_input_is_valid(confirmation^) ||
	   confirmation.precondition != precondition {
		return {}, false, .Confirmation_Mismatch
	}
	confirmation.consumed = true
	request := Revision_Sequence_Request {
		operation = operation,
		precondition = precondition,
		confirmation = confirmation.id,
		limits = limits,
	}
	return request, revision_sequence_request_is_valid(request), .None
}

/* revision_sequence_request_is_valid checks one closed confirmed process request. */
revision_sequence_request_is_valid :: proc(request: Revision_Sequence_Request) -> bool {
	return request.operation != Revision_Sequence_Operation_ID(0) &&
	       request.confirmation != Revision_Sequence_Confirmation_ID(0) &&
	       process_limits_are_valid(request.limits) &&
	       revision_sequence_precondition_is_valid(request.precondition)
}

/* revision_sequence_request_revalidate rejects any drift from the confirmed action boundary. */
revision_sequence_request_revalidate :: proc(
	current: Revision_Sequence_Precondition,
	request: Revision_Sequence_Request,
) -> (bool, Failure_Code) {
	if !revision_sequence_request_is_valid(request) do return false, .Invalid_Request
	if failure := revision_sequence_precondition_failure(current); failure != .None do return false, failure
	if current != request.precondition do return false, .Stale_Observation
	return true, .None
}

/* revision_sequence_result_open copies one bounded child outcome pending refreshed verification. */
revision_sequence_result_open :: proc(
	request: Revision_Sequence_Request,
	started: bool,
	exit_status: i32,
	output, diagnostic: []u8,
	failure: Failure_Code,
	allocator := context.allocator,
) -> (Revision_Sequence_Result, bool, Failure_Code) {
	if allocator.procedure == nil || !revision_sequence_request_is_valid(request) ||
	   u64(len(output)) > request.limits.stdout_bytes ||
	   u64(len(diagnostic)) > request.limits.diagnostic_bytes {
		return {}, false, .Invalid_Request
	}
	if !started && (exit_status != 0 || len(output) != 0 || len(diagnostic) != 0 || failure != .Cancelled) {
		return {}, false, .Invalid_Request
	}
	state, allocation_error := new(Revision_Sequence_Result_Data, allocator)
	if allocation_error != nil do return {}, false, .Allocation
	state.allocator = allocator
	state.descriptor = {
		request = request,
		outcome = .Awaiting_Refresh if started else .Cancelled_Before_Start,
		lineage = {
			original_head = request.precondition.original_head,
			selection = request.precondition.selection,
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
	if !started do state.descriptor.failure = .Cancelled
	state.output, allocation_error = make([dynamic]u8, len(output), allocator)
	if allocation_error == nil do state.diagnostic, allocation_error = make([dynamic]u8, len(diagnostic), allocator)
	if allocation_error != nil {
		revision_sequence_result_data_destroy(state)
		return {}, false, .Allocation
	}
	copy(state.output[:], output)
	copy(state.diagnostic[:], diagnostic)
	if !revision_sequence_result_descriptor_is_valid(state.descriptor) {
		revision_sequence_result_data_destroy(state)
		return {}, false, .Invalid_Request
	}
	return Revision_Sequence_Result{state = state}, true, .None
}

/* revision_sequence_result_descriptor returns copied immutable child metadata. */
revision_sequence_result_descriptor :: proc(
	result: ^Revision_Sequence_Result,
) -> (Revision_Sequence_Result_Descriptor, bool) {
	state := revision_sequence_result_data(result)
	if state == nil do return {}, false
	return state.descriptor, revision_sequence_result_descriptor_is_valid(state.descriptor)
}

/* revision_sequence_result_usage reports exact selection, message, and copied payload sizes. */
revision_sequence_result_usage :: proc(
	result: ^Revision_Sequence_Result,
) -> (Revision_Sequence_Usage, bool) {
	state := revision_sequence_result_data(result)
	if state == nil do return {}, false
	message_bytes: u64
	if state.descriptor.request.precondition.message.mode == .Composed {
		message_bytes = u64(state.descriptor.request.precondition.message.content.length)
	}
	return {
		commits = state.descriptor.request.precondition.selection.commits,
		message_bytes = message_bytes,
		output_bytes = u64(len(state.output)),
		diagnostic_bytes = u64(len(state.diagnostic)),
	}, true
}

/* revision_sequence_result_close releases copied process evidence and clears its handle. */
revision_sequence_result_close :: proc(result: ^Revision_Sequence_Result) {
	state := revision_sequence_result_data(result)
	if state == nil do return
	revision_sequence_result_data_destroy(state)
	result^ = {}
}

@(private)
revision_sequence_start_message_is_valid :: proc(message: Revision_Sequence_Message, commits: u32) -> bool {
	return message.mode == .Preserve_Selected && message.content == {} ||
	       message.mode == .Composed && commits == 1 && commit_message_is_valid(message.content)
}

@(private)
revision_sequence_family_state :: proc(
	family: Revision_Sequence_Family,
) -> (Operation_State, Sequence_Kind, bool) {
	switch family {
	case .Cherry_Pick: return .Cherry_Picking, .Cherry_Pick, true
	case .Revert: return .Reverting, .Revert, true
	case .Invalid: return .Unknown, .None, false
	}
	return .Unknown, .None, false
}

@(private)
revision_sequence_confirmation_input_is_valid :: proc(confirmation: Revision_Sequence_Confirmation) -> bool {
	return confirmation.id != Revision_Sequence_Confirmation_ID(0) &&
	       revision_sequence_precondition_is_valid(confirmation.precondition) &&
	       !(confirmation.consumed && !confirmation.confirmed)
}

@(private)
revision_sequence_result_descriptor_is_valid :: proc(
	descriptor: Revision_Sequence_Result_Descriptor,
) -> bool {
	if !revision_sequence_request_is_valid(descriptor.request) || descriptor.verified ||
	   descriptor.sequence != {} || descriptor.lineage.resulting != {} ||
	   descriptor.lineage.original_head != descriptor.request.precondition.original_head ||
	   descriptor.lineage.selection != descriptor.request.precondition.selection ||
	   descriptor.step != descriptor.request.precondition.step ||
	   descriptor.output_bytes > descriptor.request.limits.stdout_bytes ||
	   descriptor.diagnostic_bytes > descriptor.request.limits.diagnostic_bytes {
		return false
	}
	if !descriptor.started {
		return descriptor.outcome == .Cancelled_Before_Start && descriptor.exit_status == 0 &&
		       descriptor.output_bytes == 0 && descriptor.diagnostic_bytes == 0 &&
		       descriptor.failure == .Cancelled && !descriptor.process_succeeded &&
		       !descriptor.refresh_required
	}
	return descriptor.outcome == .Awaiting_Refresh && descriptor.refresh_required &&
	       descriptor.process_succeeded == (descriptor.failure == .None && descriptor.exit_status == 0)
}

@(private)
revision_sequence_set_fingerprint_compute :: proc(
	fingerprint: ^Revision_Sequence_Fingerprint,
	targets: []Revision_Sequence_Target,
) -> bool {
	if fingerprint == nil || len(targets) == 0 do return false
	ctx: sha2.Context_256
	sha2.init_256(&ctx)
	for target in targets {
		revision := target.revision
		sha2.update(&ctx, revision.bytes[:revision.length])
		shape := [3]u8{target.parent_count, target.mainline.number, 0xff}
		sha2.update(&ctx, shape[:])
		if target.mainline != {} {
			parent := target.mainline.parent
			sha2.update(&ctx, parent.bytes[:parent.length])
		}
		sha2.update(&ctx, []u8{0})
	}
	sha2.final(&ctx, fingerprint.bytes[:])
	return revision_sequence_fingerprint_is_valid(fingerprint^)
}

@(private)
revision_sequence_set_data :: proc(set: ^Revision_Sequence_Set) -> ^Revision_Sequence_Set_Data {
	if set == nil || set.state == nil do return nil
	return cast(^Revision_Sequence_Set_Data)set.state
}

@(private)
revision_sequence_set_data_destroy :: proc(state: ^Revision_Sequence_Set_Data) {
	if state == nil do return
	allocator := state.allocator
	delete(state.targets)
	free(state, allocator)
}

@(private)
revision_sequence_result_data :: proc(result: ^Revision_Sequence_Result) -> ^Revision_Sequence_Result_Data {
	if result == nil || result.state == nil do return nil
	return cast(^Revision_Sequence_Result_Data)result.state
}

@(private)
revision_sequence_result_data_destroy :: proc(state: ^Revision_Sequence_Result_Data) {
	if state == nil do return
	allocator := state.allocator
	delete(state.output)
	delete(state.diagnostic)
	free(state, allocator)
}
