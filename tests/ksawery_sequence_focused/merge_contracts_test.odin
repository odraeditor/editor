// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery_sequence_focused

import ksawery "../../src/ksawery"
import "core:fmt"
import "core:mem"
import "core:testing"

MERGE_CURRENT_REVISION :: "0123456789012345678901234567890123456789"
MERGE_SOURCE_REVISION :: "1234567890123456789012345678901234567890"
MERGE_INDEX_TREE :: "2345678901234567890123456789012345678901"

/* Verifies merge sources retain the selected Ref identity and resolved complete revision. */
@(test)
merge_sources_and_policies_are_explicit :: proc(t: ^testing.T) {
	start := merge_test_start_precondition(t, .Fast_Forward_Only, {.Not_Used, {}})
	testing.expect(t, ksawery.merge_precondition_is_valid(start))
	testing.expect_value(t, start.head.branch.object, start.head.object)
	testing.expect_value(t, start.source.reference.object, start.source.revision)
	testing.expect_value(t, start.policy, ksawery.Merge_Fast_Forward_Policy.Fast_Forward_Only)

	message: ksawery.Commit_Message
	testing.expect(t, ksawery.commit_message_assign(&message, "Merge selected source\n\nReviewed in Odra."))
	composed := merge_test_start_precondition(t, .Require_Merge_Commit, {.Composed, message})
	testing.expect(t, ksawery.merge_precondition_is_valid(composed))

	invalid_message := composed
	invalid_message.message = {.Not_Used, {}}
	testing.expect(t, !ksawery.merge_precondition_is_valid(invalid_message))
	testing.expect_value(
		t,
		ksawery.merge_precondition_failure(invalid_message),
		ksawery.Failure_Code.Commit_Message_Invalid,
	)
}

/* Verifies merge start rejects dirty repository state, active sequences, detached HEAD, and modified buffers. */
@(test)
merge_start_requires_clean_checked_state :: proc(t: ^testing.T) {
	start := merge_test_start_precondition(t, .Allow_Merge_Commit, {.Git_Default, {}})

	dirty := start
	dirty.worktree_paths = 1
	testing.expect(t, !ksawery.merge_precondition_is_valid(dirty))
	testing.expect_value(t, ksawery.merge_precondition_failure(dirty), ksawery.Failure_Code.Action_Unavailable)

	sequenced := start
	sequenced.repository_operation = .Merging
	sequenced.sequence_state = .Conflicted
	sequenced.sequence = {generation = sequenced.sequence_generation, fingerprint = 41}
	testing.expect(t, !ksawery.merge_precondition_is_valid(sequenced))

	modified := start
	modified.editor = {repository_resources = 2, modified_repository_resources = 1}
	testing.expect(t, !ksawery.merge_precondition_is_valid(modified))
	testing.expect_value(t, ksawery.merge_precondition_failure(modified), ksawery.Failure_Code.Modified_Buffer)

	detached := start
	detached.head = {.Detached, {}, start.head.object}
	testing.expect(t, !ksawery.merge_precondition_is_valid(detached))
	testing.expect_value(t, ksawery.merge_precondition_failure(detached), ksawery.Failure_Code.Action_Unavailable)
}

/* Verifies one exact confirmation is consumed once and any later repository drift is stale. */
@(test)
merge_requests_consume_confirmation_and_reject_stale_truth :: proc(t: ^testing.T) {
	start := merge_test_start_precondition(t, .Allow_Merge_Commit, {.Git_Default, {}})
	confirmation, prepared, prepare_failure := ksawery.merge_confirmation_prepare(
		start,
		ksawery.Merge_Confirmation_ID(71),
	)
	testing.expectf(t, prepared, "merge confirmation failed with %v", prepare_failure)
	if !prepared do return

	_, unconfirmed, unconfirmed_failure := ksawery.merge_request_prepare(
		start,
		ksawery.Merge_Operation_ID(71),
		&confirmation,
	)
	testing.expect(t, !unconfirmed && unconfirmed_failure == .Confirmation_Required)

	confirmed, confirmation_failure := ksawery.merge_confirmation_confirm(
		&confirmation,
		ksawery.Merge_Confirmation_ID(71),
	)
	testing.expectf(t, confirmed, "merge confirmation was rejected with %v", confirmation_failure)
	request, requested, request_failure := ksawery.merge_request_prepare(
		start,
		ksawery.Merge_Operation_ID(71),
		&confirmation,
	)
	testing.expectf(t, requested, "merge request failed with %v", request_failure)
	if !requested do return
	testing.expect(t, ksawery.merge_request_is_valid(request))

	_, repeated, repeated_failure := ksawery.merge_request_prepare(
		start,
		ksawery.Merge_Operation_ID(72),
		&confirmation,
	)
	testing.expect(t, !repeated && repeated_failure == .Confirmation_Mismatch)

	revalidated, revalidation_failure := ksawery.merge_request_revalidate(start, request)
	testing.expect(t, revalidated && revalidation_failure == .None)
	changed := start
	changed.status_generation += 1
	revalidated, revalidation_failure = ksawery.merge_request_revalidate(changed, request)
	testing.expect(t, !revalidated && revalidation_failure == .Stale_Observation)
}

/* Verifies Continue and Abort retain distinct sequence, conflict, and message preconditions. */
@(test)
merge_controls_are_sequence_exact_and_distinct :: proc(t: ^testing.T) {
	continued := merge_test_control_precondition(t, .Continue)
	testing.expect(t, ksawery.merge_precondition_is_valid(continued))

	unresolved := continued
	unresolved.sequence_state = .Conflicted
	unresolved.worktree_paths = 1
	unresolved.unmerged_paths = 1
	testing.expect(t, !ksawery.merge_precondition_is_valid(unresolved))
	testing.expect_value(t, ksawery.merge_precondition_failure(unresolved), ksawery.Failure_Code.Action_Unavailable)

	aborted := merge_test_control_precondition(t, .Abort)
	aborted.sequence_state = .Conflicted
	aborted.worktree_paths = 2
	aborted.unmerged_paths = 1
	testing.expect(t, ksawery.merge_precondition_is_valid(aborted))

	wrong_generation := aborted
	wrong_generation.sequence.generation += 1
	testing.expect(t, !ksawery.merge_precondition_is_valid(wrong_generation))
}

/* Verifies merge results retain bounded child evidence, require refresh, and release all ownership. */
@(test)
merge_results_bound_process_evidence_and_cleanup :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	request, requested := merge_test_request(t)
	if !requested {
		mem.tracking_allocator_destroy(&tracking)
		return
	}

	result, opened, failure := ksawery.merge_result_open(
		request,
		true,
		1,
		transmute([]u8)(string("Automatic merge failed")),
		transmute([]u8)(string("conflict")),
		.None,
		allocator,
	)
	testing.expectf(t, opened, "merge result failed with %v", failure)
	if opened {
		descriptor, described := ksawery.merge_result_descriptor(&result)
		testing.expect(t, described)
		testing.expect_value(t, descriptor.outcome, ksawery.Merge_Outcome.Awaiting_Refresh)
		testing.expect(t, descriptor.started && descriptor.refresh_required)
		testing.expect(t, !descriptor.process_succeeded)
		testing.expect_value(t, descriptor.failure, ksawery.Failure_Code.Process_Failed)
		usage, measured := ksawery.merge_result_usage(&result)
		testing.expect(t, measured)
		testing.expect_value(t, usage.output_bytes, u64(len("Automatic merge failed")))
		testing.expect_value(t, usage.diagnostic_bytes, u64(len("conflict")))
		ksawery.merge_result_close(&result)
	}

	cancelled, cancelled_opened, cancelled_failure := ksawery.merge_result_open(
		request,
		false,
		0,
		nil,
		nil,
		.Cancelled,
		allocator,
	)
	testing.expectf(t, cancelled_opened, "cancelled merge result failed with %v", cancelled_failure)
	if cancelled_opened {
		descriptor, described := ksawery.merge_result_descriptor(&cancelled)
		testing.expect(t, described)
		testing.expect_value(t, descriptor.outcome, ksawery.Merge_Outcome.Cancelled_Before_Start)
		testing.expect(t, !descriptor.started && !descriptor.refresh_required)
		ksawery.merge_result_close(&cancelled)
	}
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&tracking)
}

/* Verifies refreshed repository truth distinguishes merge completion, known stops, and indeterminate results. */
@(test)
merge_results_require_exact_ref_and_sequence_verification :: proc(t: ^testing.T) {
	fast_forward := merge_test_start_precondition(t, .Fast_Forward_Only, {.Not_Used, {}})
	merge_test_expect_verified_outcome(
		t,
		fast_forward,
		MERGE_SOURCE_REVISION,
		true,
		false,
		.Fast_Forwarded,
		.None,
	)

	merge_commit := merge_test_start_precondition(t, .Allow_Merge_Commit, {.Git_Default, {}})
	merge_test_expect_verified_outcome(
		t,
		merge_commit,
		"3456789012345678901234567890123456789012",
		true,
		false,
		.Merge_Commit_Created,
		.None,
	)
	merge_test_expect_verified_outcome(
		t,
		merge_commit,
		MERGE_CURRENT_REVISION,
		false,
		true,
		.Paused_Conflict,
		.Process_Failed,
	)
	merge_test_expect_verified_outcome(
		t,
		merge_commit,
		MERGE_CURRENT_REVISION,
		false,
		false,
		.Known_Failure,
		.Process_Failed,
	)
	merge_test_expect_verified_outcome(
		t,
		fast_forward,
		MERGE_CURRENT_REVISION,
		true,
		false,
		.Indeterminate,
		.Stale_Observation,
	)
}

merge_test_start_precondition :: proc(
	t: ^testing.T,
	policy: ksawery.Merge_Fast_Forward_Policy,
	message: ksawery.Merge_Message,
) -> ksawery.Merge_Precondition {
	repository, head, source, index_tree := merge_test_identities(t)
	return {
		repository = repository,
		status_generation = 31,
		ref_generation = 32,
		sequence_generation = 33,
		head = head,
		index_tree = index_tree,
		index_fingerprint = merge_test_index_fingerprint(t),
		repository_operation = .Normal,
		sequence_state = .Inactive,
		editor = {repository_resources = 3},
		action = .Start,
		source = source,
		target_revision = source.revision,
		policy = policy,
		message = message,
	}
}

merge_test_control_precondition :: proc(
	t: ^testing.T,
	action: ksawery.Merge_Action,
) -> ksawery.Merge_Precondition {
	repository, head, _, index_tree := merge_test_identities(t)
	message := ksawery.Merge_Message{.Not_Used, {}}
	if action == .Continue do message = {.Git_Default, {}}
	return {
		repository = repository,
		status_generation = 41,
		ref_generation = 32,
		sequence_generation = 43,
		head = head,
		index_tree = action == .Abort ? ksawery.Index_Tree_Identity{} : index_tree,
		index_fingerprint = merge_test_index_fingerprint(t),
		repository_operation = .Merging,
		sequence_state = .Active,
		sequence = {generation = 43, fingerprint = 44},
		editor = {repository_resources = 3},
		action = action,
		target_revision = conflict_test_revision(t, MERGE_SOURCE_REVISION),
		message = message,
	}
}

merge_test_index_fingerprint :: proc(t: ^testing.T) -> ksawery.Merge_Index_Fingerprint {
	bytes: [ksawery.MERGE_INDEX_FINGERPRINT_BYTES]u8
	for &byte, index in bytes do byte = u8(index + 1)
	fingerprint: ksawery.Merge_Index_Fingerprint
	testing.expect(t, ksawery.merge_index_fingerprint_assign(&fingerprint, bytes[:]))
	return fingerprint
}

merge_test_request :: proc(t: ^testing.T) -> (ksawery.Merge_Request, bool) {
	precondition := merge_test_start_precondition(t, .Allow_Merge_Commit, {.Git_Default, {}})
	return merge_test_request_for(t, precondition, 81)
}

merge_test_request_for :: proc(
	t: ^testing.T,
	precondition: ksawery.Merge_Precondition,
	id: u64,
) -> (ksawery.Merge_Request, bool) {
	confirmation, prepared, _ := ksawery.merge_confirmation_prepare(
		precondition,
		ksawery.Merge_Confirmation_ID(id),
	)
	if !prepared do return {}, false
	confirmed, _ := ksawery.merge_confirmation_confirm(&confirmation, confirmation.id)
	if !confirmed do return {}, false
	request, requested, failure := ksawery.merge_request_prepare(
		precondition,
		ksawery.Merge_Operation_ID(id),
		&confirmation,
	)
	testing.expectf(t, requested, "merge test request failed with %v", failure)
	return request, requested
}

merge_test_expect_verified_outcome :: proc(
	t: ^testing.T,
	precondition: ksawery.Merge_Precondition,
	resulting_text: string,
	process_succeeded: bool,
	conflicted: bool,
	expected: ksawery.Merge_Outcome,
	expected_failure: ksawery.Failure_Code,
) {
	request, requested := merge_test_request_for(t, precondition, u64(90 + int(expected)))
	if !requested do return
	exit_status := i32(0)
	if !process_succeeded do exit_status = 1
	result, opened, open_failure := ksawery.merge_result_open(
		request,
		true,
		exit_status,
		nil,
		nil,
		.None,
	)
	testing.expectf(t, opened, "verified merge result failed to open with %v", open_failure)
	if !opened do return
	defer ksawery.merge_result_close(&result)

	resulting := conflict_test_revision(t, resulting_text)
	refs, refs_opened := merge_test_ref_observation(t, precondition.repository, resulting)
	if !refs_opened do return
	defer ksawery.ref_observation_close(&refs)
	sequence, sequence_opened := merge_test_sequence_observation(t, precondition, resulting, conflicted)
	if !sequence_opened do return
	defer ksawery.sequence_observation_close(&sequence)

	verified, failure := ksawery.merge_result_verify(&result, &refs, &sequence)
	testing.expectf(t, verified, "merge verification failed with %v", failure)
	descriptor, described := ksawery.merge_result_descriptor(&result)
	testing.expect(t, described)
	if described {
		testing.expect_value(t, descriptor.outcome, expected)
		testing.expect_value(t, descriptor.failure, expected_failure)
		testing.expect_value(t, descriptor.lineage.resulting, resulting)
	}
}

merge_test_ref_observation :: proc(
	t: ^testing.T,
	repository: ksawery.Repository_Context,
	head: ksawery.Revision_Identity,
) -> (ksawery.Ref_Observation, bool) {
	head_identity := head
	head_text := ksawery.revision_identity_string(&head_identity)
	refs_output := fmt.aprintf(
		"refs/heads/main%c%s%ccommit%c%c%c*%c\n",
		u8(0),
		head_text,
		u8(0),
		u8(0),
		u8(0),
		u8(0),
		u8(0),
	)
	defer delete(refs_output)
	head_output := fmt.aprintf("%s\n", head_text)
	defer delete(head_output)
	observation, opened, failure := ksawery.ref_observation_open(
		repository,
		ksawery.Ref_Generation(501),
		transmute([]u8)refs_output,
		nil,
		transmute([]u8)head_output,
	)
	testing.expectf(t, opened, "verified Ref observation failed with %v", failure)
	return observation, opened
}

merge_test_sequence_observation :: proc(
	t: ^testing.T,
	precondition: ksawery.Merge_Precondition,
	current: ksawery.Revision_Identity,
	conflicted: bool,
) -> (ksawery.Sequence_Observation, bool) {
	source := ksawery.Sequence_Source {
		kind = .None,
		origin = .External,
		supported = true,
	}
	output: []u8
	if conflicted {
		source = {
			kind = .Merge,
			origin = .Associated,
			marker_mask = 1,
			current = current,
			target = precondition.target_revision,
			metadata_bytes = 40,
			supported = true,
		}
		output = transmute([]u8)(string(
			"u UU N... 100644 100644 100644 100644 " + MERGE_CURRENT_REVISION + " " +
			MERGE_SOURCE_REVISION + " " + MERGE_INDEX_TREE + " conflict.txt\x00",
		))
	}
	observation, opened, failure := ksawery.sequence_observation_open(
		precondition.repository,
		ksawery.Sequence_Generation(502),
		source,
		output,
	)
	testing.expectf(t, opened, "verified Sequence observation failed with %v", failure)
	return observation, opened
}

merge_test_identities :: proc(t: ^testing.T) -> (
	ksawery.Repository_Context,
	ksawery.Head_Observation,
	ksawery.Merge_Source,
	ksawery.Index_Tree_Identity,
) {
	repository: ksawery.Repository_Context
	testing.expect(t, ksawery.repository_context_assign(&repository, "/tmp/odra-ksawery-merge-contracts"))
	current, source_revision, index_revision: ksawery.Revision_Identity
	testing.expect(t, ksawery.revision_identity_assign(&current, MERGE_CURRENT_REVISION))
	testing.expect(t, ksawery.revision_identity_assign(&source_revision, MERGE_SOURCE_REVISION))
	testing.expect(t, ksawery.revision_identity_assign(&index_revision, MERGE_INDEX_TREE))
	current_name, source_name: ksawery.Ref_Name
	testing.expect(t, ksawery.ref_name_assign(&current_name, "refs/heads/main"))
	testing.expect(t, ksawery.ref_name_assign(&source_name, "refs/remotes/origin/topic"))
	current_branch := ksawery.Ref_Identity {
		repository = repository,
		generation = 32,
		kind = .Local_Branch,
		name = current_name,
		object = current,
		object_type = .Commit,
	}
	source_ref := ksawery.Ref_Identity {
		repository = repository,
		generation = 32,
		kind = .Remote_Tracking_Branch,
		name = source_name,
		object = source_revision,
		object_type = .Commit,
	}
	return repository,
	       {.Symbolic, current_branch, current},
	       {source_ref, source_revision},
	       {index_revision}
}
