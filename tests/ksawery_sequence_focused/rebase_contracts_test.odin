// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery_sequence_focused

import ksawery "../../src/ksawery"
import "core:fmt"
import "core:mem"
import "core:testing"

REBASE_OLD_TIP :: "4567890123456789012345678901234567890123"
REBASE_UPSTREAM :: "5678901234567890123456789012345678901234"
REBASE_STEP :: "6789012345678901234567890123456789012345"
REBASE_TARGET :: "7890123456789012345678901234567890123456"
REBASE_TREE :: "8901234567890123456789012345678901234567"

/* Verifies ordinary and autosquash modes bind exact branch, base, and accepted-plan identities. */
@(test)
rebase_modes_bind_exact_endpoints_and_reviewed_plan :: proc(t: ^testing.T) {
	ordinary := rebase_test_start_precondition(t, .Ordinary)
	testing.expect(t, ksawery.rebase_precondition_is_valid(ordinary))
	testing.expect_value(t, ordinary.branch.object, ordinary.old_tip)
	testing.expect_value(t, ordinary.base.reference.object, ordinary.base.revision)
	testing.expect_value(t, ordinary.plan, ksawery.Rebase_Reviewed_Plan{})

	autosquash := rebase_test_start_precondition(t, .Autosquash)
	testing.expect(t, ksawery.rebase_precondition_is_valid(autosquash))
	testing.expect(t, ksawery.rebase_reviewed_plan_is_valid(autosquash.plan, autosquash.plan_limits))
	changed_endpoint := autosquash
	changed_endpoint.plan.old_tip = conflict_test_revision(t, REBASE_STEP)
	testing.expect(t, !ksawery.rebase_precondition_is_valid(changed_endpoint))
	unaccepted := autosquash
	unaccepted.plan.accepted = false
	testing.expect(t, !ksawery.rebase_precondition_is_valid(unaccepted))
}

/* Verifies rebase start rejects dirty state, detached HEAD, duplicate base, and modified buffers. */
@(test)
rebase_start_requires_clean_checked_branch_state :: proc(t: ^testing.T) {
	start := rebase_test_start_precondition(t, .Ordinary)
	dirty := start
	dirty.worktree_paths = 1
	testing.expect(t, !ksawery.rebase_precondition_is_valid(dirty))
	testing.expect_value(t, ksawery.rebase_precondition_failure(dirty), ksawery.Failure_Code.Action_Unavailable)

	detached := start
	detached.head = {.Detached, {}, start.old_tip}
	testing.expect(t, !ksawery.rebase_precondition_is_valid(detached))

	modified := start
	modified.editor = {repository_resources = 2, modified_repository_resources = 1}
	testing.expect(t, !ksawery.rebase_precondition_is_valid(modified))
	testing.expect_value(t, ksawery.rebase_precondition_failure(modified), ksawery.Failure_Code.Modified_Buffer)

	duplicate := start
	duplicate.base.revision = duplicate.old_tip
	duplicate.base.reference.object = duplicate.old_tip
	testing.expect(t, !ksawery.rebase_precondition_is_valid(duplicate))
	testing.expect_value(t, ksawery.rebase_precondition_failure(duplicate), ksawery.Failure_Code.Target_Duplicate)
}

/* Verifies every history rewrite consumes one exact confirmation and rejects later observation drift. */
@(test)
rebase_requests_consume_confirmation_and_reject_stale_truth :: proc(t: ^testing.T) {
	start := rebase_test_start_precondition(t, .Autosquash)
	confirmation, prepared, prepare_failure := ksawery.rebase_confirmation_prepare(
		start,
		ksawery.Rebase_Confirmation_ID(601),
	)
	testing.expectf(t, prepared, "rebase confirmation failed with %v", prepare_failure)
	if !prepared do return
	_, unconfirmed, unconfirmed_failure := ksawery.rebase_request_prepare(
		start,
		ksawery.Rebase_Operation_ID(601),
		&confirmation,
	)
	testing.expect(t, !unconfirmed && unconfirmed_failure == .Confirmation_Required)
	confirmed, confirmation_failure := ksawery.rebase_confirmation_confirm(
		&confirmation,
		confirmation.id,
	)
	testing.expectf(t, confirmed, "rebase confirmation was rejected with %v", confirmation_failure)
	request, requested, request_failure := ksawery.rebase_request_prepare(
		start,
		ksawery.Rebase_Operation_ID(601),
		&confirmation,
	)
	testing.expectf(t, requested, "rebase request failed with %v", request_failure)
	if !requested do return
	_, repeated, repeated_failure := ksawery.rebase_request_prepare(
		start,
		ksawery.Rebase_Operation_ID(602),
		&confirmation,
	)
	testing.expect(t, !repeated && repeated_failure == .Confirmation_Mismatch)
	revalidated, revalidation_failure := ksawery.rebase_request_revalidate(start, request)
	testing.expect(t, revalidated && revalidation_failure == .None)
	changed := start
	changed.status_generation += 1
	revalidated, revalidation_failure = ksawery.rebase_request_revalidate(changed, request)
	testing.expect(t, !revalidated && revalidation_failure == .Stale_Observation)
	changed = start
	changed.base.revision = conflict_test_revision(t, REBASE_TARGET)
	changed.base.reference.object = changed.base.revision
	changed.plan.upstream = changed.base.revision
	revalidated, revalidation_failure = ksawery.rebase_request_revalidate(changed, request)
	testing.expect(t, !revalidated && revalidation_failure == .Stale_Observation)
	changed = start
	changed.old_tip = conflict_test_revision(t, REBASE_STEP)
	changed.branch.object = changed.old_tip
	changed.head.branch = changed.branch
	changed.head.object = changed.old_tip
	changed.plan.old_tip = changed.old_tip
	revalidated, revalidation_failure = ksawery.rebase_request_revalidate(changed, request)
	testing.expect(t, !revalidated && revalidation_failure == .Stale_Observation)
	changed = start
	changed.plan.fingerprint.bytes[0] = changed.plan.fingerprint.bytes[0] ~ 0xff
	revalidated, revalidation_failure = ksawery.rebase_request_revalidate(changed, request)
	testing.expect(t, !revalidated && revalidation_failure == .Stale_Observation)
}

/* Verifies Continue, Skip, and Abort retain distinct exact replay-state requirements. */
@(test)
rebase_controls_are_step_exact_and_distinct :: proc(t: ^testing.T) {
	continued := rebase_test_control_precondition(t, .Continue, .Active)
	testing.expect(t, ksawery.rebase_precondition_is_valid(continued))
	conflicted_continue := continued
	conflicted_continue.sequence_state = .Conflicted
	conflicted_continue.unmerged_paths = 1
	testing.expect(t, !ksawery.rebase_precondition_is_valid(conflicted_continue))

	skipped := rebase_test_control_precondition(t, .Skip, .Conflicted)
	testing.expect(t, ksawery.rebase_precondition_is_valid(skipped))
	missing_step := skipped
	missing_step.step = {}
	testing.expect(t, !ksawery.rebase_precondition_is_valid(missing_step))

	aborted := rebase_test_control_precondition(t, .Abort, .Conflicted)
	aborted.step = {}
	testing.expect(t, ksawery.rebase_precondition_is_valid(aborted))
	wrong_sequence := aborted
	wrong_sequence.sequence.generation += 1
	testing.expect(t, !ksawery.rebase_precondition_is_valid(wrong_sequence))
}

/* Verifies replay-step and plan limits exclude unbound or unsupported autosquash instructions. */
@(test)
rebase_steps_and_plan_limits_are_closed :: proc(t: ^testing.T) {
	pick := rebase_test_step(t, .Pick)
	testing.expect(t, ksawery.rebase_replay_step_is_valid(pick))
	fixup := rebase_test_step(t, .Fixup)
	fixup.target = conflict_test_revision(t, REBASE_TARGET)
	testing.expect(t, ksawery.rebase_replay_step_is_valid(fixup))
	unbound := fixup
	unbound.target = {}
	testing.expect(t, !ksawery.rebase_replay_step_is_valid(unbound))
	testing.expect(t, ksawery.rebase_plan_limits_are_valid(ksawery.DEFAULT_REBASE_PLAN_LIMITS))
	testing.expect(t, !ksawery.rebase_plan_limits_are_valid({steps = 0}))
	testing.expect(t, !ksawery.rebase_plan_limits_are_valid({steps = ksawery.MAX_REBASE_PLAN_STEPS + 1}))
}

/* Verifies bounded replay results preserve child evidence and release every owned byte. */
@(test)
rebase_results_bound_process_evidence_and_cleanup :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	request, requested := rebase_test_request(t)
	if !requested {
		mem.tracking_allocator_destroy(&tracking)
		return
	}
	result, opened, failure := ksawery.rebase_result_open(
		request,
		true,
		1,
		transmute([]u8)(string("rebase stopped")),
		transmute([]u8)(string("conflict")),
		.None,
		allocator,
	)
	testing.expectf(t, opened, "rebase result failed with %v", failure)
	if opened {
		descriptor, described := ksawery.rebase_result_descriptor(&result)
		testing.expect(t, described)
		testing.expect_value(t, descriptor.outcome, ksawery.Rebase_Outcome.Awaiting_Refresh)
		testing.expect(t, descriptor.started && descriptor.refresh_required && !descriptor.process_succeeded)
		testing.expect_value(t, descriptor.failure, ksawery.Failure_Code.Process_Failed)
		usage, measured := ksawery.rebase_result_usage(&result)
		testing.expect(t, measured)
		testing.expect_value(t, usage.plan_steps, request.precondition.plan.steps)
		ksawery.rebase_result_close(&result)
	}
	cancelled, cancelled_opened, cancelled_failure := ksawery.rebase_result_open(
		request,
		false,
		0,
		nil,
		nil,
		.Cancelled,
		allocator,
	)
	testing.expectf(t, cancelled_opened, "cancelled rebase result failed with %v", cancelled_failure)
	if cancelled_opened {
		descriptor, described := ksawery.rebase_result_descriptor(&cancelled)
		testing.expect(t, described && descriptor.outcome == .Cancelled_Before_Start)
		ksawery.rebase_result_close(&cancelled)
	}
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&tracking)
}

/* Verifies refreshed Ref and Sequence truth classifies replay success and mismatches exactly. */
@(test)
rebase_results_require_fresh_operation_specific_truth :: proc(t: ^testing.T) {
	precondition := rebase_test_start_precondition(t, .Ordinary)
	request, requested := rebase_test_request_for(t, precondition, 711)
	if !requested do return
	resulting := conflict_test_revision(t, REBASE_TARGET)
	refs, refs_opened := rebase_test_ref_observation(t, precondition.repository, resulting)
	if !refs_opened do return
	defer ksawery.ref_observation_close(&refs)
	inactive, sequence_opened := rebase_test_inactive_sequence(t, precondition.repository)
	if !sequence_opened do return
	defer ksawery.sequence_observation_close(&inactive)
	result, opened, open_failure := ksawery.rebase_result_open(request, true, 0, nil, nil, .None)
	testing.expectf(t, opened, "successful rebase result failed to open with %v", open_failure)
	if opened {
		verified, verify_failure := ksawery.rebase_result_verify(&result, &refs, &inactive)
		testing.expectf(t, verified, "successful rebase result failed verification with %v", verify_failure)
		descriptor, described := ksawery.rebase_result_descriptor(&result)
		testing.expect(t, described)
		if described {
			testing.expect_value(t, descriptor.outcome, ksawery.Rebase_Outcome.Replayed)
			testing.expect_value(t, descriptor.lineage.resulting, resulting)
			testing.expect(t, descriptor.verified && descriptor.failure == .None)
		}
		ksawery.rebase_result_close(&result)
	}

	mismatch, mismatch_opened, mismatch_failure := ksawery.rebase_result_open(
		request, true, 0, nil, nil, .None,
	)
	testing.expectf(t, mismatch_opened, "mismatch rebase result failed to open with %v", mismatch_failure)
	if !mismatch_opened do return
	defer ksawery.rebase_result_close(&mismatch)
	merge_source := ksawery.Sequence_Source {
		kind = .Merge,
		origin = .External,
		marker_mask = 1,
		current = resulting,
		target = precondition.base.revision,
		metadata_bytes = 40,
		supported = true,
	}
	merge_sequence, merge_opened, merge_failure := ksawery.sequence_observation_open(
		precondition.repository, 713, merge_source, nil,
	)
	testing.expectf(t, merge_opened, "mismatch Sequence observation failed with %v", merge_failure)
	if !merge_opened do return
	defer ksawery.sequence_observation_close(&merge_sequence)
	verified, verify_failure := ksawery.rebase_result_verify(&mismatch, &refs, &merge_sequence)
	testing.expect(t, verified && verify_failure == .Stale_Observation)
	descriptor, described := ksawery.rebase_result_descriptor(&mismatch)
	testing.expect(t, described && descriptor.outcome == .Indeterminate)
}

rebase_test_start_precondition :: proc(t: ^testing.T, mode: ksawery.Rebase_Mode) -> ksawery.Rebase_Precondition {
	repository, branch, base := rebase_test_identities(t)
	old_tip := branch.object
	plan: ksawery.Rebase_Reviewed_Plan
	if mode == .Autosquash {
		fingerprint: ksawery.Rebase_Plan_Fingerprint
		testing.expect(t, ksawery.rebase_plan_fingerprint_compute(
			&fingerprint,
			transmute([]u8)(string("pick old-tip\nfixup target\n")),
		))
		plan = {
			fingerprint = fingerprint,
			old_tip = old_tip,
			upstream = base.revision,
			steps = 2,
			fixups = 1,
			accepted = true,
		}
	}
	return {
		repository = repository,
		status_generation = 51,
		ref_generation = 52,
		sequence_generation = 53,
		head = {.Symbolic, branch, old_tip},
		branch = branch,
		old_tip = old_tip,
		base = base,
		index_tree = {conflict_test_revision(t, REBASE_TREE)},
		index_fingerprint = rebase_test_index_fingerprint(t),
		repository_operation = .Normal,
		sequence_state = .Inactive,
		editor = {repository_resources = 3},
		action = .Start,
		mode = mode,
		plan = plan,
		plan_limits = ksawery.DEFAULT_REBASE_PLAN_LIMITS,
	}
}

rebase_test_control_precondition :: proc(
	t: ^testing.T,
	action: ksawery.Rebase_Action,
	state: ksawery.Sequence_Observation_State,
) -> ksawery.Rebase_Precondition {
	precondition := rebase_test_start_precondition(t, .Ordinary)
	precondition.head = {.Detached, {}, conflict_test_revision(t, REBASE_STEP)}
	precondition.repository_operation = .Rebasing
	precondition.sequence_state = state
	precondition.sequence = {generation = precondition.sequence_generation, fingerprint = 54}
	precondition.step = rebase_test_step(t, .Pick)
	precondition.worktree_paths = state == .Conflicted ? 1 : 0
	precondition.unmerged_paths = state == .Conflicted ? 1 : 0
	precondition.action = action
	return precondition
}

rebase_test_step :: proc(t: ^testing.T, action: ksawery.Rebase_Replay_Action) -> ksawery.Rebase_Replay_Step {
	return {
		position = 1,
		total = 3,
		action = action,
		revision = conflict_test_revision(t, REBASE_STEP),
	}
}

rebase_test_index_fingerprint :: proc(t: ^testing.T) -> ksawery.Rebase_Index_Fingerprint {
	bytes: [ksawery.REBASE_FINGERPRINT_BYTES]u8
	for &byte, index in bytes do byte = u8(index + 1)
	fingerprint: ksawery.Rebase_Index_Fingerprint
	testing.expect(t, ksawery.rebase_index_fingerprint_assign(&fingerprint, bytes[:]))
	return fingerprint
}

rebase_test_request :: proc(t: ^testing.T) -> (ksawery.Rebase_Request, bool) {
	precondition := rebase_test_start_precondition(t, .Autosquash)
	return rebase_test_request_for(t, precondition, 701)
}

rebase_test_request_for :: proc(
	t: ^testing.T,
	precondition: ksawery.Rebase_Precondition,
	id: u64,
) -> (ksawery.Rebase_Request, bool) {
	confirmation, prepared, _ := ksawery.rebase_confirmation_prepare(
		precondition,
		ksawery.Rebase_Confirmation_ID(id),
	)
	if !prepared do return {}, false
	confirmed, _ := ksawery.rebase_confirmation_confirm(&confirmation, confirmation.id)
	if !confirmed do return {}, false
	request, requested, failure := ksawery.rebase_request_prepare(
		precondition,
		ksawery.Rebase_Operation_ID(id),
		&confirmation,
	)
	testing.expectf(t, requested, "rebase test request failed with %v", failure)
	return request, requested
}

rebase_test_ref_observation :: proc(
	t: ^testing.T,
	repository: ksawery.Repository_Context,
	head: ksawery.Revision_Identity,
) -> (ksawery.Ref_Observation, bool) {
	head_identity := head
	head_text := ksawery.revision_identity_string(&head_identity)
	refs_output := fmt.aprintf(
		"refs/heads/topic%c%s%ccommit%c%c%c*%c\n",
		u8(0), head_text, u8(0), u8(0), u8(0), u8(0), u8(0),
	)
	defer delete(refs_output)
	head_output := fmt.aprintf("%s\n", head_text)
	defer delete(head_output)
	observation, opened, failure := ksawery.ref_observation_open(
		repository, 712, transmute([]u8)refs_output, nil, transmute([]u8)head_output,
	)
	testing.expectf(t, opened, "verified Ref observation failed with %v", failure)
	return observation, opened
}

rebase_test_inactive_sequence :: proc(
	t: ^testing.T,
	repository: ksawery.Repository_Context,
) -> (ksawery.Sequence_Observation, bool) {
	source := ksawery.Sequence_Source {
		kind = .None,
		origin = .External,
		supported = true,
	}
	observation, opened, failure := ksawery.sequence_observation_open(repository, 712, source, nil)
	testing.expectf(t, opened, "inactive Sequence observation failed with %v", failure)
	return observation, opened
}

rebase_test_identities :: proc(t: ^testing.T) -> (
	ksawery.Repository_Context,
	ksawery.Ref_Identity,
	ksawery.Rebase_Base,
) {
	repository: ksawery.Repository_Context
	testing.expect(t, ksawery.repository_context_assign(&repository, "/tmp/odra-ksawery-rebase-contracts"))
	old_tip := conflict_test_revision(t, REBASE_OLD_TIP)
	upstream := conflict_test_revision(t, REBASE_UPSTREAM)
	branch_name, base_name: ksawery.Ref_Name
	testing.expect(t, ksawery.ref_name_assign(&branch_name, "refs/heads/topic"))
	testing.expect(t, ksawery.ref_name_assign(&base_name, "refs/remotes/origin/main"))
	branch := ksawery.Ref_Identity {
		repository = repository,
		generation = 52,
		kind = .Local_Branch,
		name = branch_name,
		object = old_tip,
		object_type = .Commit,
	}
	base_ref := ksawery.Ref_Identity {
		repository = repository,
		generation = 52,
		kind = .Remote_Tracking_Branch,
		name = base_name,
		object = upstream,
		object_type = .Commit,
	}
	return repository, branch, {reference = base_ref, revision = upstream}
}
