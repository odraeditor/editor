// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery_sequence_focused

import ksawery "../../src/ksawery"
import "core:mem"
import "core:testing"

/* Verifies checked worktree results distinguish text, binary, symlink, submodule, and deletion state. */
@(test)
conflict_worktree_results_preserve_content_and_node_kind :: proc(t: ^testing.T) {
	fingerprint := conflict_test_fingerprint(t, 1)
	object := conflict_test_revision(t, "7890123456789012345678901234567890123456")
	testing.expect(t, ksawery.conflict_worktree_result_is_valid({
		exists = true,
		node = .Regular,
		content = .Text,
		mode = 0o100644,
		git_object = object,
		fingerprint = fingerprint,
	}))
	testing.expect(t, ksawery.conflict_worktree_result_is_valid({
		exists = true,
		node = .Executable,
		content = .Binary,
		mode = 0o100755,
		git_object = object,
		fingerprint = fingerprint,
	}))
	testing.expect(t, ksawery.conflict_worktree_result_is_valid({
		exists = true,
		node = .Symlink,
		content = .Text,
		mode = 0o120000,
		git_object = object,
		fingerprint = fingerprint,
	}))
	testing.expect(t, ksawery.conflict_worktree_result_is_valid({
		exists = true,
		node = .Submodule,
		content = .Unavailable,
		mode = 0o160000,
		git_object = object,
		fingerprint = fingerprint,
	}))
	testing.expect(t, ksawery.conflict_worktree_result_is_valid({
		content = .Unavailable,
	}))
	testing.expect(t, !ksawery.conflict_worktree_result_is_valid({
		exists = true,
		node = .Submodule,
		content = .Text,
		mode = 0o160000,
		git_object = object,
		fingerprint = fingerprint,
	}))
}

/* Verifies Mark Saved Result admits only exact saved text without unsaved buffer divergence. */
@(test)
mark_saved_conflict_result_requires_saved_text :: proc(t: ^testing.T) {
	precondition := conflict_test_precondition(t, .Mark_Saved_Result)
	testing.expect(t, ksawery.conflict_resolution_precondition_is_valid(precondition))
	request, requested, failure := ksawery.conflict_resolution_request_prepare(
		precondition,
		ksawery.Conflict_Resolution_Operation_ID(101),
	)
	testing.expectf(t, requested, "mark resolved request failed with %v", failure)
	if requested do testing.expect_value(t, request.confirmation, ksawery.Conflict_Resolution_Confirmation_ID(0))

	modified := precondition
	modified.editor.modified = true
	testing.expect(t, !ksawery.conflict_resolution_precondition_is_valid(modified))
	testing.expect_value(
		t,
		ksawery.conflict_resolution_precondition_failure(modified),
		ksawery.Failure_Code.Modified_Buffer,
	)

	binary := precondition
	binary.worktree.content = .Binary
	testing.expect(t, !ksawery.conflict_resolution_precondition_is_valid(binary))
	testing.expect_value(
		t,
		ksawery.conflict_resolution_precondition_failure(binary),
		ksawery.Failure_Code.Action_Unavailable,
	)
}

/* Verifies complete-side replacement requires an available exact stage and one-shot confirmation. */
@(test)
conflict_side_replacement_is_stage_exact_and_confirmed :: proc(t: ^testing.T) {
	precondition := conflict_test_precondition(t, .Use_Current)
	testing.expect(t, ksawery.conflict_resolution_precondition_is_valid(precondition))
	confirmation, prepared, prepare_failure := ksawery.conflict_resolution_confirmation_prepare(
		precondition,
		ksawery.Conflict_Resolution_Confirmation_ID(111),
	)
	testing.expectf(t, prepared, "side confirmation failed with %v", prepare_failure)
	if !prepared do return
	_, unconfirmed, unconfirmed_failure := ksawery.conflict_resolution_request_prepare(
		precondition,
		ksawery.Conflict_Resolution_Operation_ID(111),
		&confirmation,
	)
	testing.expect(t, !unconfirmed && unconfirmed_failure == .Confirmation_Required)
	confirmed, confirmation_failure := ksawery.conflict_resolution_confirmation_confirm(
		&confirmation,
		confirmation.id,
	)
	testing.expectf(t, confirmed, "side confirmation was rejected with %v", confirmation_failure)
	request, requested, request_failure := ksawery.conflict_resolution_request_prepare(
		precondition,
		ksawery.Conflict_Resolution_Operation_ID(111),
		&confirmation,
	)
	testing.expectf(t, requested, "side request failed with %v", request_failure)
	if requested do testing.expect(t, ksawery.conflict_resolution_request_is_valid(request))

	missing := precondition
	missing.target.stages[1].available = false
	missing.target.stages[1].mode = 0
	missing.target.stages[1].object = {}
	testing.expect(t, !ksawery.conflict_resolution_precondition_is_valid(missing))
	testing.expect_value(
		t,
		ksawery.conflict_resolution_precondition_failure(missing),
		ksawery.Failure_Code.Action_Unavailable,
	)
}

/* Verifies resolution requests reject changed worktree and index-stage identities as stale. */
@(test)
conflict_resolution_revalidation_rejects_exact_state_drift :: proc(t: ^testing.T) {
	request, requested := conflict_test_request(t, .Mark_Saved_Result)
	if !requested do return
	current := request.precondition
	revalidated, failure := ksawery.conflict_resolution_request_revalidate(current, request)
	testing.expect(t, revalidated && failure == .None)

	current.worktree.fingerprint = conflict_test_fingerprint(t, 17)
	current.editor.saved_fingerprint = current.worktree.fingerprint
	revalidated, failure = ksawery.conflict_resolution_request_revalidate(current, request)
	testing.expect(t, !revalidated && failure == .Stale_Observation)

	current = request.precondition
	current.target.stages[2].object = conflict_test_revision(t, "3456789012345678901234567890123456789012")
	revalidated, failure = ksawery.conflict_resolution_request_revalidate(current, request)
	testing.expect(t, !revalidated && failure == .Stale_Observation)
}

/* Verifies refreshed stage zero must match the selected side or explicit deletion. */
@(test)
conflict_resolution_verifies_stage_zero_and_refresh :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	request, requested := conflict_test_request(t, .Use_Applied)
	if !requested {
		mem.tracking_allocator_destroy(&tracking)
		return
	}
	result, opened, failure := ksawery.conflict_resolution_result_open(
		request,
		true,
		0,
		nil,
		nil,
		.None,
		allocator,
	)
	testing.expectf(t, opened, "resolution result failed with %v", failure)
	if opened {
		expected := request.precondition.target.stages[2]
		verified, verify_failure := ksawery.conflict_resolution_result_verify(
			&result,
			{state = .Present, mode = expected.mode, object = expected.object},
			{generation = 121, fingerprint = 122},
		)
		testing.expectf(t, verified, "stage-zero verification failed with %v", verify_failure)
		descriptor, described := ksawery.conflict_resolution_result_descriptor(&result)
		testing.expect(t, described)
		testing.expect_value(t, descriptor.outcome, ksawery.Conflict_Resolution_Outcome.Resolved)
		ksawery.conflict_resolution_result_close(&result)
	}

	delete_request, delete_requested := conflict_test_request(t, .Delete_Result)
	if delete_requested {
		deleted, delete_opened, _ := ksawery.conflict_resolution_result_open(
			delete_request,
			true,
			0,
			nil,
			nil,
			.None,
			allocator,
		)
		if delete_opened {
			verified, verify_failure := ksawery.conflict_resolution_result_verify(
				&deleted,
				{state = .Deleted},
				{generation = 123, fingerprint = 124},
			)
			testing.expect(t, verified && verify_failure == .None)
			descriptor, described := ksawery.conflict_resolution_result_descriptor(&deleted)
			testing.expect(t, described && descriptor.outcome == .Deleted)
			ksawery.conflict_resolution_result_close(&deleted)
		}
	}
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&tracking)
}

conflict_test_request :: proc(
	t: ^testing.T,
	action: ksawery.Conflict_Resolution_Action,
) -> (ksawery.Conflict_Resolution_Request, bool) {
	precondition := conflict_test_precondition(t, action)
	if action == .Mark_Saved_Result {
		request, requested, failure := ksawery.conflict_resolution_request_prepare(
			precondition,
			ksawery.Conflict_Resolution_Operation_ID(131),
		)
		testing.expectf(t, requested, "resolution test request failed with %v", failure)
		return request, requested
	}
	confirmation, prepared, _ := ksawery.conflict_resolution_confirmation_prepare(
		precondition,
		ksawery.Conflict_Resolution_Confirmation_ID(131),
	)
	if !prepared do return {}, false
	confirmed, _ := ksawery.conflict_resolution_confirmation_confirm(&confirmation, confirmation.id)
	if !confirmed do return {}, false
	request, requested, failure := ksawery.conflict_resolution_request_prepare(
		precondition,
		ksawery.Conflict_Resolution_Operation_ID(131),
		&confirmation,
	)
	testing.expectf(t, requested, "confirmed resolution test request failed with %v", failure)
	return request, requested
}

conflict_test_precondition :: proc(
	t: ^testing.T,
	action: ksawery.Conflict_Resolution_Action,
) -> ksawery.Conflict_Resolution_Precondition {
	repository: ksawery.Repository_Context
	testing.expect(t, ksawery.repository_context_assign(&repository, "/tmp/odra-ksawery-conflict-contracts"))
	base := conflict_test_revision(t, "4567890123456789012345678901234567890123")
	current := conflict_test_revision(t, "5678901234567890123456789012345678901234")
	applied := conflict_test_revision(t, "6789012345678901234567890123456789012345")
	fingerprint := conflict_test_fingerprint(t, 1)
	sequence := ksawery.Sequence_Target{generation = 91, fingerprint = 92}
	target := ksawery.Conflict_Target {
		id = 1,
		path = {offset = 0, length = 12},
		kind = .Both_Modified,
		index = 'U',
		worktree = 'U',
		stages = {
			{kind = .Base, available = true, mode = 0o100644, object = base},
			{kind = .Current, available = true, mode = 0o100644, object = current},
			{kind = .Applied, available = true, mode = 0o100644, object = applied},
		},
	}
	return {
		repository = repository,
		status_generation = 90,
		sequence_generation = 91,
		repository_operation = .Merging,
		sequence_state = .Conflicted,
		sequence = sequence,
		conflict = {sequence = sequence, conflict = 1},
		target = target,
		worktree = {
			exists = true,
			node = .Regular,
			content = .Text,
			mode = 0o100644,
			git_object = conflict_test_revision(t, "7890123456789012345678901234567890123456"),
			fingerprint = fingerprint,
		},
		editor = {open = true, saved_fingerprint = fingerprint},
		unmerged_paths = 1,
		action = action,
	}
}

conflict_test_fingerprint :: proc(
	t: ^testing.T,
	seed: u8,
) -> ksawery.Conflict_Content_Fingerprint {
	bytes: [ksawery.CONFLICT_CONTENT_FINGERPRINT_BYTES]u8
	for &byte, index in bytes do byte = seed + u8(index)
	fingerprint: ksawery.Conflict_Content_Fingerprint
	testing.expect(t, ksawery.conflict_content_fingerprint_assign(&fingerprint, bytes[:]))
	return fingerprint
}

conflict_test_revision :: proc(t: ^testing.T, text: string) -> ksawery.Revision_Identity {
	revision: ksawery.Revision_Identity
	testing.expect(t, ksawery.revision_identity_assign(&revision, text))
	return revision
}
