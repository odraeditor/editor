// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery_sequence_focused

import ksawery "../../src/ksawery"
import "core:mem"
import "core:testing"

BISECT_BAD :: "9012345678901234567890123456789012345678"
BISECT_GOOD_ONE :: "0123456789012345678901234567890123456789"
BISECT_GOOD_TWO :: "1234567890123456789012345678901234567890"
BISECT_CANDIDATE :: "2345678901234567890123456789012345678901"
BISECT_TREE :: "3456789012345678901234567890123456789012"

/* Verifies one bounded boundary owner retains exact bad and ordered known-good identities. */
@(test)
bisect_boundaries_are_exact_bounded_and_owned :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	bad := conflict_test_revision(t, BISECT_BAD)
	good := [?]ksawery.Revision_Identity {
		conflict_test_revision(t, BISECT_GOOD_ONE),
		conflict_test_revision(t, BISECT_GOOD_TWO),
	}
	set, opened, failure := ksawery.bisect_boundary_set_open(bad, good[:], allocator = allocator)
	testing.expectf(t, opened, "bisect boundary set failed with %v", failure)
	if opened {
		descriptor, described := ksawery.bisect_boundary_set_descriptor(&set)
		testing.expect(t, described)
		testing.expect_value(t, descriptor.bad, bad)
		testing.expect_value(t, descriptor.good_count, u32(2))
		for expected, index in good {
			boundary, found := ksawery.bisect_boundary_set_good(&set, u32(index))
			testing.expect(t, found)
			testing.expect_value(t, boundary, expected)
		}
		testing.expect(t, ksawery.bisect_boundary_set_matches(&set, descriptor))
		usage, measured := ksawery.bisect_boundary_set_usage(&set)
		testing.expect(t, measured && usage.good_boundaries == 2 && usage.allocation_bytes > 0)
		ksawery.bisect_boundary_set_close(&set)
	}
	duplicate := [?]ksawery.Revision_Identity{good[0], good[0]}
	_, duplicate_opened, duplicate_failure := ksawery.bisect_boundary_set_open(bad, duplicate[:])
	testing.expect(t, !duplicate_opened && duplicate_failure == .Target_Duplicate)
	overlap := [?]ksawery.Revision_Identity{bad}
	_, overlap_opened, overlap_failure := ksawery.bisect_boundary_set_open(bad, overlap[:])
	testing.expect(t, !overlap_opened && overlap_failure == .Target_Overlap)
	limits := ksawery.DEFAULT_BISECT_LIMITS
	limits.good_boundaries = 1
	_, limited_opened, limited_failure := ksawery.bisect_boundary_set_open(bad, good[:], limits)
	testing.expect(t, !limited_opened && limited_failure == .Target_Limit)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&tracking)
}

/* Verifies bisect start binds clean exact boundaries and symbolic or detached origin. */
@(test)
bisect_start_binds_clean_origin_and_boundaries :: proc(t: ^testing.T) {
	start := bisect_test_start_precondition(t, false)
	testing.expect(t, ksawery.bisect_precondition_is_valid(start))
	detached := bisect_test_start_precondition(t, true)
	testing.expect(t, ksawery.bisect_precondition_is_valid(detached))
	dirty := start
	dirty.worktree_paths = 1
	testing.expect(t, !ksawery.bisect_precondition_is_valid(dirty))
	modified := start
	modified.editor = {repository_resources = 2, modified_repository_resources = 1}
	testing.expect(t, !ksawery.bisect_precondition_is_valid(modified))
	testing.expect_value(t, ksawery.bisect_precondition_failure(modified), ksawery.Failure_Code.Modified_Buffer)
	changed_origin := start
	changed_origin.origin.head.object = conflict_test_revision(t, BISECT_CANDIDATE)
	changed_origin.origin.head.branch.object = changed_origin.origin.head.object
	testing.expect(t, !ksawery.bisect_precondition_is_valid(changed_origin))
}

/* Verifies every classification and reset targets the exact current detached candidate. */
@(test)
bisect_controls_are_candidate_exact_and_closed :: proc(t: ^testing.T) {
	cases := [?]struct {
		action: ksawery.Bisect_Action,
		classification: ksawery.Bisect_Classification,
	} {
		{.Good, .Good},
		{.Bad, .Bad},
		{.Skip, .Skipped},
		{.Reset, .None},
	}
	for test_case in cases {
		precondition := bisect_test_control_precondition(t, test_case.action, test_case.classification)
		testing.expect(t, ksawery.bisect_precondition_is_valid(precondition))
		wrong_classification := precondition
		wrong_classification.classification = .None
		if test_case.action != .Reset {
			testing.expect(t, !ksawery.bisect_precondition_is_valid(wrong_classification))
		}
		stale_candidate := precondition
		stale_candidate.head.object = conflict_test_revision(t, BISECT_GOOD_TWO)
		testing.expect(t, !ksawery.bisect_precondition_is_valid(stale_candidate))
	}
	progress := bisect_test_control_precondition(t, .Good, .Good).progress
	testing.expect(t, ksawery.bisect_progress_is_valid(progress))
	progress.complete = true
	progress.remaining = 0
	progress.first_bad = progress.candidate
	testing.expect(t, ksawery.bisect_progress_is_valid(progress))
	completed_reset := bisect_test_control_precondition(t, .Reset, .None)
	completed_reset.progress = progress
	completed_reset.head.object = progress.candidate
	testing.expect(t, ksawery.bisect_precondition_is_valid(completed_reset))
	progress.first_bad = conflict_test_revision(t, BISECT_GOOD_TWO)
	testing.expect(t, !ksawery.bisect_progress_is_valid(progress))
}

/* Verifies one exact confirmation is consumed and any later observation drift is rejected. */
@(test)
bisect_requests_consume_confirmation_and_reject_drift :: proc(t: ^testing.T) {
	precondition := bisect_test_start_precondition(t, false)
	confirmation, prepared, prepare_failure := ksawery.bisect_confirmation_prepare(
		precondition,
		ksawery.Bisect_Confirmation_ID(801),
	)
	testing.expectf(t, prepared, "bisect confirmation failed with %v", prepare_failure)
	if !prepared do return
	_, unconfirmed, unconfirmed_failure := ksawery.bisect_request_prepare(
		precondition,
		ksawery.Bisect_Operation_ID(801),
		&confirmation,
	)
	testing.expect(t, !unconfirmed && unconfirmed_failure == .Confirmation_Required)
	confirmed, confirm_failure := ksawery.bisect_confirmation_confirm(&confirmation, confirmation.id)
	testing.expectf(t, confirmed, "bisect confirmation was rejected with %v", confirm_failure)
	request, requested, request_failure := ksawery.bisect_request_prepare(
		precondition,
		ksawery.Bisect_Operation_ID(801),
		&confirmation,
	)
	testing.expectf(t, requested, "bisect request failed with %v", request_failure)
	if !requested do return
	_, repeated, repeated_failure := ksawery.bisect_request_prepare(
		precondition,
		ksawery.Bisect_Operation_ID(802),
		&confirmation,
	)
	testing.expect(t, !repeated && repeated_failure == .Confirmation_Mismatch)
	revalidated, revalidation_failure := ksawery.bisect_request_revalidate(precondition, request)
	testing.expect(t, revalidated && revalidation_failure == .None)
	changed := precondition
	changed.boundaries.fingerprint.bytes[0] = changed.boundaries.fingerprint.bytes[0] ~ 0xff
	revalidated, revalidation_failure = ksawery.bisect_request_revalidate(changed, request)
	testing.expect(t, !revalidated && revalidation_failure == .Stale_Observation)
	changed = precondition
	changed.status_generation += 1
	revalidated, revalidation_failure = ksawery.bisect_request_revalidate(changed, request)
	testing.expect(t, !revalidated && revalidation_failure == .Stale_Observation)
}

/* Verifies bounded bisect results retain child evidence and release every owned byte. */
@(test)
bisect_results_bound_evidence_and_cleanup :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	request, requested := bisect_test_request(t)
	if !requested {
		mem.tracking_allocator_destroy(&tracking)
		return
	}
	result, opened, failure := ksawery.bisect_result_open(
		request,
		true,
		0,
		transmute([]u8)(string("Bisecting: 2 revisions left")),
		nil,
		.None,
		allocator,
	)
	testing.expectf(t, opened, "bisect result failed with %v", failure)
	if opened {
		descriptor, described := ksawery.bisect_result_descriptor(&result)
		testing.expect(t, described && descriptor.outcome == .Awaiting_Refresh)
		usage, measured := ksawery.bisect_result_usage(&result)
		testing.expect(t, measured && usage.good_boundaries == 2 && usage.output_bytes > 0)
		ksawery.bisect_result_close(&result)
	}
	cancelled, cancelled_opened, cancelled_failure := ksawery.bisect_result_open(
		request, false, 0, nil, nil, .Cancelled, allocator,
	)
	testing.expectf(t, cancelled_opened, "cancelled bisect result failed with %v", cancelled_failure)
	if cancelled_opened do ksawery.bisect_result_close(&cancelled)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&tracking)
}

bisect_test_start_precondition :: proc(t: ^testing.T, detached: bool) -> ksawery.Bisect_Precondition {
	repository: ksawery.Repository_Context
	testing.expect(t, ksawery.repository_context_assign(&repository, "/tmp/odra-ksawery-bisect-contracts"))
	head_revision := conflict_test_revision(t, BISECT_BAD)
	head: ksawery.Head_Observation
	if detached {
		head = {.Detached, {}, head_revision}
	} else {
		branch_name: ksawery.Ref_Name
		testing.expect(t, ksawery.ref_name_assign(&branch_name, "refs/heads/topic"))
		branch := ksawery.Ref_Identity {
			repository = repository,
			generation = 73,
			kind = .Local_Branch,
			name = branch_name,
			object = head_revision,
			object_type = .Commit,
		}
		head = {.Symbolic, branch, head_revision}
	}
	return {
		repository = repository,
		status_generation = 71,
		history_generation = 72,
		ref_generation = 73,
		sequence_generation = 74,
		head = head,
		origin = {head = head},
		index_tree = {conflict_test_revision(t, BISECT_TREE)},
		index_fingerprint = bisect_test_index_fingerprint(t),
		repository_operation = .Normal,
		sequence_state = .Inactive,
		boundaries = bisect_test_boundary_identity(t),
		action = .Start,
		classification = .None,
		editor = {repository_resources = 2},
		limits = ksawery.DEFAULT_BISECT_LIMITS,
	}
}

bisect_test_control_precondition :: proc(
	t: ^testing.T,
	action: ksawery.Bisect_Action,
	classification: ksawery.Bisect_Classification,
) -> ksawery.Bisect_Precondition {
	precondition := bisect_test_start_precondition(t, false)
	candidate := conflict_test_revision(t, BISECT_CANDIDATE)
	precondition.head = {.Detached, {}, candidate}
	precondition.repository_operation = .Bisecting
	precondition.sequence_state = .Active
	precondition.sequence = {generation = precondition.sequence_generation, fingerprint = 75}
	precondition.progress = {
		candidate = candidate,
		classifications = 1,
		remaining = 2,
	}
	precondition.action = action
	precondition.classification = classification
	return precondition
}

bisect_test_boundary_identity :: proc(t: ^testing.T) -> ksawery.Bisect_Boundary_Identity {
	bad := conflict_test_revision(t, BISECT_BAD)
	good := [?]ksawery.Revision_Identity {
		conflict_test_revision(t, BISECT_GOOD_ONE),
		conflict_test_revision(t, BISECT_GOOD_TWO),
	}
	set, opened, failure := ksawery.bisect_boundary_set_open(bad, good[:])
	testing.expectf(t, opened, "bisect test boundaries failed with %v", failure)
	if !opened do return {}
	defer ksawery.bisect_boundary_set_close(&set)
	identity, described := ksawery.bisect_boundary_set_descriptor(&set)
	testing.expect(t, described)
	return identity
}

bisect_test_index_fingerprint :: proc(t: ^testing.T) -> ksawery.Bisect_Index_Fingerprint {
	fingerprint: ksawery.Bisect_Index_Fingerprint
	testing.expect(t, ksawery.bisect_index_fingerprint_compute(&fingerprint, nil))
	return fingerprint
}

bisect_test_request :: proc(t: ^testing.T) -> (ksawery.Bisect_Request, bool) {
	precondition := bisect_test_start_precondition(t, false)
	confirmation, prepared, _ := ksawery.bisect_confirmation_prepare(
		precondition,
		ksawery.Bisect_Confirmation_ID(811),
	)
	if !prepared do return {}, false
	confirmed, _ := ksawery.bisect_confirmation_confirm(&confirmation, confirmation.id)
	if !confirmed do return {}, false
	request, requested, failure := ksawery.bisect_request_prepare(
		precondition,
		ksawery.Bisect_Operation_ID(811),
		&confirmation,
	)
	testing.expectf(t, requested, "bisect test request failed with %v", failure)
	return request, requested
}
