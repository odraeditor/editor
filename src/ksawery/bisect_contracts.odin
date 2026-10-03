// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery

import "base:runtime"
import "core:crypto/sha2"

/* MIN_BISECT_GOOD_BOUNDARIES is the smallest admitted known-good boundary count. */
MIN_BISECT_GOOD_BOUNDARIES :: u32(1)
/* MAX_BISECT_GOOD_BOUNDARIES is the immutable known-good boundary ceiling. */
MAX_BISECT_GOOD_BOUNDARIES :: u32(240)
/* DEFAULT_BISECT_GOOD_BOUNDARIES is the initial known-good boundary capacity. */
DEFAULT_BISECT_GOOD_BOUNDARIES :: u32(32)
/* MAX_BISECT_CLASSIFICATIONS bounds retained manual bisect progress. */
MAX_BISECT_CLASSIFICATIONS :: u32(4_096)
/* BISECT_FINGERPRINT_BYTES is the SHA-256 width for boundary and index identities. */
BISECT_FINGERPRINT_BYTES :: 32
/* MAX_BISECT_EDITOR_RESOURCES bounds repository buffers checked before mutation. */
MAX_BISECT_EDITOR_RESOURCES :: u32(4_096)

/* Bisect_Operation_ID identifies one admitted manual bisect action. */
Bisect_Operation_ID :: distinct u64
/* Bisect_Confirmation_ID identifies one exact manual bisect confirmation. */
Bisect_Confirmation_ID :: distinct u64

/* Bisect_Action selects one closed manual bisect mutation. */
Bisect_Action :: enum u8 {
	Invalid,
	Start,
	Good,
	Bad,
	Skip,
	Reset,
}

/* Bisect_Classification is the closed verdict vocabulary for one exact candidate. */
Bisect_Classification :: enum u8 {
	Invalid,
	None,
	Good,
	Bad,
	Skipped,
}

/* Bisect_Limits bounds exact known-good boundaries and retained progress. */
Bisect_Limits :: struct {
	good_boundaries: u32,
	classifications: u32,
}

/* DEFAULT_BISECT_LIMITS selects the initial manual bisect envelope. */
DEFAULT_BISECT_LIMITS :: Bisect_Limits {
	good_boundaries = DEFAULT_BISECT_GOOD_BOUNDARIES,
	classifications = MAX_BISECT_CLASSIFICATIONS,
}

/* Bisect_Boundary_Fingerprint identifies one exact bad and ordered known-good set. */
Bisect_Boundary_Fingerprint :: struct {
	bytes: [BISECT_FINGERPRINT_BYTES]u8,
}

/* Bisect_Index_Fingerprint identifies one complete staged-index snapshot. */
Bisect_Index_Fingerprint :: struct {
	bytes: [BISECT_FINGERPRINT_BYTES]u8,
}

/* Bisect_Boundary_Identity binds exact bad and known-good revisions to one fingerprint. */
Bisect_Boundary_Identity :: struct {
	fingerprint: Bisect_Boundary_Fingerprint,
	bad:         Revision_Identity,
	good_count:  u32,
}

/* Bisect_Boundary_Set owns one bounded copied boundary selection. */
Bisect_Boundary_Set :: struct {
	state: rawptr,
}

@(private)
Bisect_Boundary_Set_Data :: struct {
	identity:  Bisect_Boundary_Identity,
	good:      [dynamic]Revision_Identity,
	limits:    Bisect_Limits,
	allocator: runtime.Allocator,
}

/* Bisect_Origin records the exact symbolic or detached pre-bisect HEAD. */
Bisect_Origin :: struct {
	head: Head_Observation,
}

/* Bisect_Progress binds bounded progress to the exact current candidate or final answer. */
Bisect_Progress :: struct {
	candidate:      Revision_Identity,
	first_bad:      Revision_Identity,
	classifications: u32,
	skipped:        u32,
	remaining:      u32,
	complete:       bool,
}

/* Bisect_Editor_State summarizes repository buffers one bisect action may replace. */
Bisect_Editor_State :: struct {
	repository_resources:          u32,
	modified_repository_resources: u32,
}

/* Bisect_Precondition binds one action to exact repository and bisect truth. */
Bisect_Precondition :: struct {
	repository:           Repository_Context,
	status_generation:    Observation_Generation,
	history_generation:   History_Generation,
	ref_generation:       Ref_Generation,
	sequence_generation:  Sequence_Generation,
	head:                 Head_Observation,
	origin:               Bisect_Origin,
	index_tree:           Index_Tree_Identity,
	index_fingerprint:    Bisect_Index_Fingerprint,
	repository_operation: Operation_State,
	sequence_state:       Sequence_Observation_State,
	sequence:             Sequence_Target,
	boundaries:           Bisect_Boundary_Identity,
	progress:             Bisect_Progress,
	action:               Bisect_Action,
	classification:       Bisect_Classification,
	worktree_paths:       u32,
	unmerged_paths:       u32,
	editor:               Bisect_Editor_State,
	limits:               Bisect_Limits,
}

/* Bisect_Confirmation owns one one-shot acknowledgement of an exact action. */
Bisect_Confirmation :: struct {
	id:           Bisect_Confirmation_ID,
	precondition: Bisect_Precondition,
	confirmed:    bool,
	consumed:     bool,
}

/* Bisect_Request is one closed confirmed manual action with bounded process ownership. */
Bisect_Request :: struct {
	operation:    Bisect_Operation_ID,
	precondition: Bisect_Precondition,
	confirmation: Bisect_Confirmation_ID,
	limits:       Process_Limits,
}

/* Bisect_Outcome separates child completion from refreshed repository authority. */
Bisect_Outcome :: enum u8 {
	Invalid,
	Cancelled_Before_Start,
	Awaiting_Refresh,
	Started,
	Advanced,
	Found_First_Bad,
	Reset,
	Known_Failure,
	Indeterminate,
}

/* Bisect_Result_Descriptor retains bounded child evidence pending refreshed verification. */
Bisect_Result_Descriptor :: struct {
	request:           Bisect_Request,
	outcome:           Bisect_Outcome,
	progress:          Bisect_Progress,
	resulting_head:    Head_Observation,
	started:           bool,
	verified:          bool,
	exit_status:       i32,
	output_bytes:      u64,
	diagnostic_bytes:  u64,
	failure:           Failure_Code,
	process_succeeded: bool,
	refresh_required:  bool,
}

/* Bisect_Usage reports retained boundary and child payload ownership. */
Bisect_Usage :: struct {
	good_boundaries: u32,
	output_bytes:    u64,
	diagnostic_bytes: u64,
	allocation_bytes: u64,
}

/* Bisect_Result owns one copied child outcome pending refreshed repository verification. */
Bisect_Result :: struct {
	state: rawptr,
}

@(private)
Bisect_Result_Data :: struct {
	descriptor: Bisect_Result_Descriptor,
	output:     [dynamic]u8,
	diagnostic: [dynamic]u8,
	allocator:  runtime.Allocator,
}

/* bisect_limits_are_valid checks the immutable manual bisect envelope. */
bisect_limits_are_valid :: proc(limits: Bisect_Limits) -> bool {
	return limits.good_boundaries >= MIN_BISECT_GOOD_BOUNDARIES &&
	       limits.good_boundaries <= MAX_BISECT_GOOD_BOUNDARIES &&
	       limits.classifications > 0 && limits.classifications <= MAX_BISECT_CLASSIFICATIONS
}

/* bisect_boundary_fingerprint_is_valid rejects an absent boundary-set identity. */
bisect_boundary_fingerprint_is_valid :: proc(fingerprint: Bisect_Boundary_Fingerprint) -> bool {
	for byte in fingerprint.bytes {
		if byte != 0 do return true
	}
	return false
}

/* bisect_index_fingerprint_compute derives one digest from complete staged-index bytes. */
bisect_index_fingerprint_compute :: proc(fingerprint: ^Bisect_Index_Fingerprint, bytes: []u8) -> bool {
	if fingerprint == nil do return false
	ctx: sha2.Context_256
	sha2.init_256(&ctx)
	sha2.update(&ctx, bytes)
	sha2.final(&ctx, fingerprint.bytes[:])
	return bisect_index_fingerprint_is_valid(fingerprint^)
}

/* bisect_index_fingerprint_is_valid rejects an absent staged-index identity. */
bisect_index_fingerprint_is_valid :: proc(fingerprint: Bisect_Index_Fingerprint) -> bool {
	for byte in fingerprint.bytes {
		if byte != 0 do return true
	}
	return false
}

/* bisect_boundary_identity_is_valid checks one bounded nonempty exact boundary identity. */
bisect_boundary_identity_is_valid :: proc(
	identity: Bisect_Boundary_Identity,
	limits := DEFAULT_BISECT_LIMITS,
) -> bool {
	return bisect_limits_are_valid(limits) && bisect_boundary_fingerprint_is_valid(identity.fingerprint) &&
	       revision_identity_is_valid(identity.bad) && identity.good_count > 0 &&
	       identity.good_count <= limits.good_boundaries
}

/* bisect_boundary_set_open copies one exact bad and ordered known-good boundary set. */
bisect_boundary_set_open :: proc(
	bad: Revision_Identity,
	good: []Revision_Identity,
	limits := DEFAULT_BISECT_LIMITS,
	allocator := context.allocator,
) -> (Bisect_Boundary_Set, bool, Failure_Code) {
	if allocator.procedure == nil || !bisect_limits_are_valid(limits) ||
	   !revision_identity_is_valid(bad) || len(good) == 0 {
		return {}, false, .Invalid_Request
	}
	if u64(len(good)) > u64(limits.good_boundaries) do return {}, false, .Target_Limit
	state, allocation_error := new(Bisect_Boundary_Set_Data, allocator)
	if allocation_error != nil do return {}, false, .Allocation
	state.allocator = allocator
	state.limits = limits
	state.good, allocation_error = make([dynamic]Revision_Identity, len(good), allocator)
	if allocation_error != nil {
		bisect_boundary_set_data_destroy(state)
		return {}, false, .Allocation
	}
	for boundary, index in good {
		if !revision_identity_is_valid(boundary) || boundary == bad {
			bisect_boundary_set_data_destroy(state)
			return {}, false, boundary == bad ? .Target_Overlap : .Target_Incompatible
		}
		for previous in 0 ..< index {
			if good[previous] == boundary {
				bisect_boundary_set_data_destroy(state)
				return {}, false, .Target_Duplicate
			}
		}
		state.good[index] = boundary
	}
	state.identity.bad = bad
	state.identity.good_count = u32(len(good))
	if !bisect_boundary_fingerprint_compute(&state.identity.fingerprint, bad, state.good[:]) {
		bisect_boundary_set_data_destroy(state)
		return {}, false, .Invalid_Request
	}
	return Bisect_Boundary_Set{state = state}, true, .None
}

/* bisect_boundary_set_descriptor returns one copied immutable boundary identity. */
bisect_boundary_set_descriptor :: proc(set: ^Bisect_Boundary_Set) -> (Bisect_Boundary_Identity, bool) {
	state := bisect_boundary_set_data(set)
	if state == nil do return {}, false
	return state.identity, bisect_boundary_identity_is_valid(state.identity, state.limits)
}

/* bisect_boundary_set_good returns one copied known-good boundary in retained order. */
bisect_boundary_set_good :: proc(set: ^Bisect_Boundary_Set, ordinal: u32) -> (Revision_Identity, bool) {
	state := bisect_boundary_set_data(set)
	if state == nil || ordinal >= u32(len(state.good)) do return {}, false
	return state.good[ordinal], true
}

/* bisect_boundary_set_matches checks one owner against a confirmed exact identity. */
bisect_boundary_set_matches :: proc(set: ^Bisect_Boundary_Set, identity: Bisect_Boundary_Identity) -> bool {
	descriptor, described := bisect_boundary_set_descriptor(set)
	return described && descriptor == identity
}

/* bisect_boundary_set_usage reports exact retained boundary ownership. */
bisect_boundary_set_usage :: proc(set: ^Bisect_Boundary_Set) -> (Bisect_Usage, bool) {
	state := bisect_boundary_set_data(set)
	if state == nil do return {}, false
	return {
		good_boundaries = state.identity.good_count,
		allocation_bytes = u64(size_of(Bisect_Boundary_Set_Data)) +
		                   u64(cap(state.good)) * u64(size_of(Revision_Identity)),
	}, true
}

/* bisect_boundary_set_close releases one boundary owner and clears its handle. */
bisect_boundary_set_close :: proc(set: ^Bisect_Boundary_Set) {
	state := bisect_boundary_set_data(set)
	if state == nil do return
	bisect_boundary_set_data_destroy(state)
	set^ = {}
}

/* bisect_origin_is_valid admits one exact symbolic or detached pre-bisect HEAD. */
bisect_origin_is_valid :: proc(origin: Bisect_Origin) -> bool {
	return head_observation_is_valid(origin.head) &&
	       (origin.head.state == .Symbolic || origin.head.state == .Detached)
}

/* bisect_progress_is_valid checks bounded active-candidate or final-answer progress. */
bisect_progress_is_valid :: proc(progress: Bisect_Progress, limits := DEFAULT_BISECT_LIMITS) -> bool {
	if !bisect_limits_are_valid(limits) || progress.classifications > limits.classifications ||
	   progress.skipped > progress.classifications || !revision_identity_is_valid(progress.candidate) {
		return false
	}
	if progress.complete {
		return progress.remaining == 0 && revision_identity_is_valid(progress.first_bad) &&
		       progress.candidate == progress.first_bad
	}
	return progress.first_bad == {} && progress.remaining <= limits.classifications
}

/* bisect_editor_state_is_valid bounds repository buffers and modified-buffer counts. */
bisect_editor_state_is_valid :: proc(state: Bisect_Editor_State) -> bool {
	return state.repository_resources <= MAX_BISECT_EDITOR_RESOURCES &&
	       state.modified_repository_resources <= state.repository_resources
}

/* bisect_precondition_is_valid checks one action-specific exact manual bisect boundary. */
bisect_precondition_is_valid :: proc(precondition: Bisect_Precondition) -> bool {
	if !repository_context_is_valid(precondition.repository) ||
	   precondition.status_generation == Observation_Generation(0) ||
	   precondition.history_generation == History_Generation(0) ||
	   precondition.ref_generation == Ref_Generation(0) ||
	   precondition.sequence_generation == Sequence_Generation(0) ||
	   !head_observation_is_valid(precondition.head) || !bisect_origin_is_valid(precondition.origin) ||
	   !bisect_boundary_identity_is_valid(precondition.boundaries, precondition.limits) ||
	   !bisect_index_fingerprint_is_valid(precondition.index_fingerprint) ||
	   !bisect_editor_state_is_valid(precondition.editor) ||
	   precondition.editor.modified_repository_resources != 0 ||
	   precondition.worktree_paths > MAX_STATUS_PATHS ||
	   precondition.unmerged_paths > precondition.worktree_paths || precondition.unmerged_paths != 0 ||
	   precondition.action == .Invalid || precondition.classification == .Invalid {
		return false
	}
	if precondition.origin.head.state == .Symbolic &&
	   precondition.origin.head.branch.repository != precondition.repository {
		return false
	}
	switch precondition.action {
	case .Start:
		return precondition.head == precondition.origin.head &&
		       precondition.repository_operation == .Normal && precondition.sequence_state == .Inactive &&
		       precondition.sequence == {} && precondition.progress == {} &&
		       precondition.classification == .None && precondition.worktree_paths == 0 &&
		       index_tree_identity_is_valid(precondition.index_tree)
	case .Good, .Bad, .Skip, .Reset:
		if precondition.repository_operation != .Bisecting || precondition.sequence_state != .Active ||
		   !sequence_target_is_valid(precondition.sequence) ||
		   precondition.sequence.generation != precondition.sequence_generation ||
		   !bisect_progress_is_valid(precondition.progress, precondition.limits) ||
		   (precondition.progress.complete && precondition.action != .Reset) ||
		   precondition.head.object != precondition.progress.candidate ||
		   precondition.worktree_paths != 0 || !index_tree_identity_is_valid(precondition.index_tree) {
			return false
		}
		if precondition.action == .Reset do return precondition.classification == .None
		if precondition.action == .Good do return precondition.classification == .Good
		if precondition.action == .Bad do return precondition.classification == .Bad
		return precondition.classification == .Skipped
	case .Invalid:
		return false
	}
	return false
}

/* bisect_precondition_failure classifies expected admission failures without weakening identity. */
bisect_precondition_failure :: proc(precondition: Bisect_Precondition) -> Failure_Code {
	if !repository_context_is_valid(precondition.repository) ||
	   precondition.status_generation == Observation_Generation(0) ||
	   precondition.history_generation == History_Generation(0) ||
	   precondition.ref_generation == Ref_Generation(0) ||
	   precondition.sequence_generation == Sequence_Generation(0) ||
	   !head_observation_is_valid(precondition.head) || !bisect_origin_is_valid(precondition.origin) ||
	   !bisect_boundary_identity_is_valid(precondition.boundaries, precondition.limits) ||
	   !bisect_index_fingerprint_is_valid(precondition.index_fingerprint) ||
	   !bisect_editor_state_is_valid(precondition.editor) || precondition.action == .Invalid ||
	   precondition.classification == .Invalid {
		return .Invalid_Request
	}
	if precondition.editor.modified_repository_resources != 0 do return .Modified_Buffer
	if precondition.origin.head.state == .Symbolic &&
	   precondition.origin.head.branch.repository != precondition.repository {
		return .Stale_Observation
	}
	if precondition.worktree_paths > MAX_STATUS_PATHS ||
	   precondition.unmerged_paths > precondition.worktree_paths {
		return .Invalid_Request
	}
	if !bisect_precondition_is_valid(precondition) do return .Action_Unavailable
	return .None
}

/* bisect_confirmation_prepare binds one acknowledgement to exact manual bisect truth. */
bisect_confirmation_prepare :: proc(
	precondition: Bisect_Precondition,
	id: Bisect_Confirmation_ID,
) -> (Bisect_Confirmation, bool, Failure_Code) {
	if id == Bisect_Confirmation_ID(0) do return {}, false, .Invalid_Request
	if failure := bisect_precondition_failure(precondition); failure != .None do return {}, false, failure
	return {id = id, precondition = precondition}, true, .None
}

/* bisect_confirmation_confirm accepts only the exact unused confirmation identity. */
bisect_confirmation_confirm :: proc(
	confirmation: ^Bisect_Confirmation,
	id: Bisect_Confirmation_ID,
) -> (bool, Failure_Code) {
	if confirmation == nil || !bisect_confirmation_input_is_valid(confirmation^) {
		return false, .Invalid_Request
	}
	if confirmation.id != id || confirmation.confirmed || confirmation.consumed {
		return false, .Confirmation_Mismatch
	}
	confirmation.confirmed = true
	return true, .None
}

/* bisect_request_prepare consumes one exact confirmation into a closed process request. */
bisect_request_prepare :: proc(
	precondition: Bisect_Precondition,
	operation: Bisect_Operation_ID,
	confirmation: ^Bisect_Confirmation,
	limits := DEFAULT_PROCESS_LIMITS,
) -> (Bisect_Request, bool, Failure_Code) {
	if operation == Bisect_Operation_ID(0) || !process_limits_are_valid(limits) {
		return {}, false, .Invalid_Request
	}
	if failure := bisect_precondition_failure(precondition); failure != .None do return {}, false, failure
	if confirmation == nil || !confirmation.confirmed do return {}, false, .Confirmation_Required
	if confirmation.consumed || !bisect_confirmation_input_is_valid(confirmation^) ||
	   confirmation.precondition != precondition {
		return {}, false, .Confirmation_Mismatch
	}
	confirmation.consumed = true
	request := Bisect_Request {
		operation = operation,
		precondition = precondition,
		confirmation = confirmation.id,
		limits = limits,
	}
	return request, bisect_request_is_valid(request), .None
}

/* bisect_request_is_valid checks one closed confirmed manual bisect request. */
bisect_request_is_valid :: proc(request: Bisect_Request) -> bool {
	return request.operation != Bisect_Operation_ID(0) && request.confirmation != Bisect_Confirmation_ID(0) &&
	       bisect_precondition_is_valid(request.precondition) && process_limits_are_valid(request.limits)
}

/* bisect_request_revalidate rejects any changed repository, candidate, or boundary truth. */
bisect_request_revalidate :: proc(current: Bisect_Precondition, request: Bisect_Request) -> (bool, Failure_Code) {
	if !bisect_request_is_valid(request) do return false, .Invalid_Request
	if failure := bisect_precondition_failure(current); failure != .None do return false, failure
	if current != request.precondition do return false, .Stale_Observation
	return true, .None
}

/* bisect_result_open copies one bounded child outcome pending mandatory repository refresh. */
bisect_result_open :: proc(
	request: Bisect_Request,
	started: bool,
	exit_status: i32,
	output, diagnostic: []u8,
	failure: Failure_Code,
	allocator := context.allocator,
) -> (Bisect_Result, bool, Failure_Code) {
	if allocator.procedure == nil || !bisect_request_is_valid(request) ||
	   u64(len(output)) > request.limits.stdout_bytes ||
	   u64(len(diagnostic)) > request.limits.diagnostic_bytes {
		return {}, false, .Invalid_Request
	}
	if !started && (failure != .Cancelled || exit_status != 0 || len(output) != 0 || len(diagnostic) != 0) {
		return {}, false, .Invalid_Request
	}
	result_failure := failure
	if started && result_failure == .None && exit_status != 0 do result_failure = .Process_Failed
	state, allocation_error := new(Bisect_Result_Data, allocator)
	if allocation_error != nil do return {}, false, .Allocation
	state.allocator = allocator
	state.descriptor = {
		request = request,
		outcome = started ? .Awaiting_Refresh : .Cancelled_Before_Start,
		progress = request.precondition.progress,
		started = started,
		exit_status = exit_status,
		output_bytes = u64(len(output)),
		diagnostic_bytes = u64(len(diagnostic)),
		failure = result_failure,
		process_succeeded = started && result_failure == .None && exit_status == 0,
		refresh_required = started,
	}
	state.output, allocation_error = make([dynamic]u8, 0, len(output), allocator)
	if allocation_error == nil do state.diagnostic, allocation_error = make([dynamic]u8, 0, len(diagnostic), allocator)
	if allocation_error == nil && len(output) > 0 do _, allocation_error = append(&state.output, ..output)
	if allocation_error == nil && len(diagnostic) > 0 do _, allocation_error = append(&state.diagnostic, ..diagnostic)
	if allocation_error != nil {
		bisect_result_data_destroy(state)
		return {}, false, .Allocation
	}
	return Bisect_Result{state = state}, true, .None
}

/* bisect_result_descriptor returns copied immutable manual bisect child metadata. */
bisect_result_descriptor :: proc(result: ^Bisect_Result) -> (Bisect_Result_Descriptor, bool) {
	state := bisect_result_data(result)
	if state == nil do return {}, false
	return state.descriptor, bisect_result_descriptor_is_valid(state.descriptor)
}

/* bisect_result_verify classifies one child outcome against refreshed Ref and Sequence truth. */
bisect_result_verify :: proc(
	result: ^Bisect_Result,
	refs: ^Ref_Observation,
	sequence: ^Sequence_Observation,
) -> (bool, Failure_Code) {
	state := bisect_result_data(result)
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
	descriptor.verified = true
	descriptor.resulting_head = refs_descriptor.head
	if precondition.action == .Reset {
		if sequence_descriptor.state == .Inactive && sequence_descriptor.kind == .None &&
		   bisect_head_matches_origin(refs_descriptor.head, precondition.origin) && descriptor.process_succeeded {
			descriptor.outcome = .Reset
			descriptor.progress = {}
			descriptor.failure = .None
			return true, .None
		}
		descriptor.outcome = .Indeterminate
		descriptor.failure = .Stale_Observation
		return true, descriptor.failure
	}
	if sequence_descriptor.state != .Active || sequence_descriptor.kind != .Bisect ||
	   refs_descriptor.head.state != .Detached ||
	   refs_descriptor.head.object != sequence_descriptor.current {
		descriptor.outcome = .Indeterminate
		descriptor.failure = .Stale_Observation
		return true, descriptor.failure
	}
	progress := precondition.progress
	progress.candidate = refs_descriptor.head.object
	if precondition.action != .Start {
		if progress.classifications >= precondition.limits.classifications {
			descriptor.outcome = .Indeterminate
			descriptor.failure = .Target_Limit
			return true, descriptor.failure
		}
		progress.classifications += 1
		if precondition.action == .Skip do progress.skipped += 1
	}
	if remaining, parsed := bisect_result_parse_remaining(state.output[:]); parsed {
		progress.remaining = remaining
	}
	current := progress.candidate
	current_text := revision_identity_string(&current)
	if bisect_result_output_contains_first_bad(state.output[:], current_text) {
		progress.first_bad = progress.candidate
		progress.remaining = 0
		progress.complete = true
	}
	descriptor.progress = progress
	if !bisect_progress_is_valid(progress, precondition.limits) {
		descriptor.outcome = .Indeterminate
		descriptor.failure = .Parse
		return true, descriptor.failure
	}
	if !descriptor.process_succeeded {
		descriptor.outcome = .Known_Failure
		return true, descriptor.failure
	}
	descriptor.outcome = progress.complete ? .Found_First_Bad :
	                     (precondition.action == .Start ? .Started : .Advanced)
	descriptor.failure = .None
	return true, .None
}

/* bisect_result_usage reports exact retained boundary and child payload ownership. */
bisect_result_usage :: proc(result: ^Bisect_Result) -> (Bisect_Usage, bool) {
	state := bisect_result_data(result)
	if state == nil do return {}, false
	return {
		good_boundaries = state.descriptor.request.precondition.boundaries.good_count,
		output_bytes = u64(len(state.output)),
		diagnostic_bytes = u64(len(state.diagnostic)),
		allocation_bytes = u64(size_of(Bisect_Result_Data)) + u64(cap(state.output)) + u64(cap(state.diagnostic)),
	}, true
}

/* bisect_result_close releases one owned result and clears its handle. */
bisect_result_close :: proc(result: ^Bisect_Result) {
	state := bisect_result_data(result)
	if state == nil do return
	bisect_result_data_destroy(state)
	result^ = {}
}

@(private)
bisect_confirmation_input_is_valid :: proc(confirmation: Bisect_Confirmation) -> bool {
	return confirmation.id != Bisect_Confirmation_ID(0) &&
	       bisect_precondition_is_valid(confirmation.precondition) &&
	       !(confirmation.consumed && !confirmation.confirmed)
}

@(private)
bisect_result_descriptor_is_valid :: proc(descriptor: Bisect_Result_Descriptor) -> bool {
	if !bisect_request_is_valid(descriptor.request) ||
	   descriptor.output_bytes > descriptor.request.limits.stdout_bytes ||
	   descriptor.diagnostic_bytes > descriptor.request.limits.diagnostic_bytes {
		return false
	}
	if !descriptor.started {
		return descriptor.outcome == .Cancelled_Before_Start && descriptor.exit_status == 0 &&
		       descriptor.output_bytes == 0 && descriptor.diagnostic_bytes == 0 &&
		       descriptor.failure == .Cancelled && !descriptor.process_succeeded &&
		       !descriptor.refresh_required && !descriptor.verified
	}
	if !descriptor.verified {
		return descriptor.outcome == .Awaiting_Refresh && descriptor.resulting_head == {} &&
		       descriptor.refresh_required &&
		       descriptor.process_succeeded == (descriptor.failure == .None && descriptor.exit_status == 0)
	}
	if descriptor.outcome == .Invalid || descriptor.outcome == .Awaiting_Refresh ||
	   !head_observation_is_valid(descriptor.resulting_head) {
		return false
	}
	if descriptor.outcome == .Reset do return descriptor.progress == {}
	return bisect_progress_is_valid(descriptor.progress, descriptor.request.precondition.limits)
}

@(private)
bisect_result_parse_remaining :: proc(output: []u8) -> (u32, bool) {
	prefix := transmute([]u8)(string("Bisecting: "))
	if len(output) < len(prefix) do return 0, false
	for start in 0 ..= len(output) - len(prefix) {
		if string(output[start:start + len(prefix)]) != "Bisecting: " do continue
		cursor := start + len(prefix)
		value: u64
		digits: u32
		for cursor < len(output) && output[cursor] >= '0' && output[cursor] <= '9' {
			value = value * 10 + u64(output[cursor] - '0')
			if value > u64(MAX_BISECT_CLASSIFICATIONS) do return 0, false
			cursor += 1
			digits += 1
		}
		return u32(value), digits > 0
	}
	return 0, false
}

@(private)
bisect_result_output_contains_first_bad :: proc(output: []u8, revision: string) -> bool {
	if len(revision) == 0 do return false
	suffixes := [?]string{" is the first 'bad' commit", " is the first bad commit"}
	for suffix in suffixes {
		needle_length := len(revision) + len(suffix)
		if len(output) < needle_length do continue
		for start in 0 ..= len(output) - needle_length {
			if string(output[start:start + len(revision)]) != revision do continue
			if string(output[start + len(revision):start + needle_length]) == suffix do return true
		}
	}
	return false
}

@(private)
bisect_head_matches_origin :: proc(head: Head_Observation, origin: Bisect_Origin) -> bool {
	if !head_observation_is_valid(head) || !bisect_origin_is_valid(origin) ||
	   head.state != origin.head.state || head.object != origin.head.object {
		return false
	}
	if head.state == .Detached do return true
	return head.branch.kind == .Local_Branch && origin.head.branch.kind == .Local_Branch &&
	       head.branch.repository == origin.head.branch.repository &&
	       head.branch.name == origin.head.branch.name && head.branch.object == origin.head.branch.object
}

@(private)
bisect_boundary_fingerprint_compute :: proc(
	fingerprint: ^Bisect_Boundary_Fingerprint,
	bad: Revision_Identity,
	good: []Revision_Identity,
) -> bool {
	if fingerprint == nil || !revision_identity_is_valid(bad) || len(good) == 0 do return false
	ctx: sha2.Context_256
	sha2.init_256(&ctx)
	bad_copy := bad
	sha2.update(&ctx, bad_copy.bytes[:bad_copy.length])
	sha2.update(&ctx, []u8{0xff})
	for boundary in good {
		copy := boundary
		sha2.update(&ctx, copy.bytes[:copy.length])
		sha2.update(&ctx, []u8{0})
	}
	sha2.final(&ctx, fingerprint.bytes[:])
	return bisect_boundary_fingerprint_is_valid(fingerprint^)
}

@(private)
bisect_boundary_set_data :: proc(set: ^Bisect_Boundary_Set) -> ^Bisect_Boundary_Set_Data {
	if set == nil || set.state == nil do return nil
	return cast(^Bisect_Boundary_Set_Data)set.state
}

@(private)
bisect_boundary_set_data_destroy :: proc(state: ^Bisect_Boundary_Set_Data) {
	if state == nil do return
	allocator := state.allocator
	delete(state.good)
	free(state, allocator)
}

@(private)
bisect_result_data :: proc(result: ^Bisect_Result) -> ^Bisect_Result_Data {
	if result == nil || result.state == nil do return nil
	return cast(^Bisect_Result_Data)result.state
}

@(private)
bisect_result_data_destroy :: proc(state: ^Bisect_Result_Data) {
	if state == nil do return
	allocator := state.allocator
	delete(state.output)
	delete(state.diagnostic)
	free(state, allocator)
}
