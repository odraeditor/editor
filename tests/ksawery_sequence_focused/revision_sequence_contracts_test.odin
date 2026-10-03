// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery_sequence_focused

import ksawery "../../src/ksawery"
import "core:mem"
import "core:testing"

REVISION_SEQUENCE_CURRENT :: "3456789012345678901234567890123456789012"
REVISION_SEQUENCE_FIRST :: "4567890123456789012345678901234567890123"
REVISION_SEQUENCE_SECOND :: "5678901234567890123456789012345678901234"
REVISION_SEQUENCE_PARENT :: "6789012345678901234567890123456789012345"
REVISION_SEQUENCE_TREE :: "7890123456789012345678901234567890123456"

/* Verifies exact ordered targets retain application order and explicit merge mainlines. */
@(test)
revision_sequence_sets_preserve_order_and_mainline_identity :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	first := revision_sequence_test_target(t, REVISION_SEQUENCE_FIRST)
	second := revision_sequence_test_target(t, REVISION_SEQUENCE_SECOND)
	second.parent_count = 2
	second.mainline = {number = 2, parent = conflict_test_revision(t, REVISION_SEQUENCE_PARENT)}
	targets := [?]ksawery.Revision_Sequence_Target{first, second}
	set, opened, failure := ksawery.revision_sequence_set_open(
		targets[:], ksawery.DEFAULT_REVISION_SEQUENCE_LIMITS, allocator,
	)
	testing.expectf(t, opened, "ordered revision set failed with %v", failure)
	if opened {
		descriptor, described := ksawery.revision_sequence_set_descriptor(&set)
		testing.expect(t, described && descriptor.commits == 2 && descriptor.merges == 1)
		retained_first, first_found := ksawery.revision_sequence_set_target(&set, 0)
		retained_second, second_found := ksawery.revision_sequence_set_target(&set, 1)
		testing.expect(t, first_found && second_found)
		testing.expect_value(t, retained_first, first)
		testing.expect_value(t, retained_second, second)
		testing.expect(t, ksawery.revision_sequence_set_matches(&set, descriptor))
		usage, measured := ksawery.revision_sequence_set_usage(&set)
		testing.expect(t, measured && usage.commits == 2 && usage.merges == 1 && usage.allocation_bytes > 0)
		ksawery.revision_sequence_set_close(&set)
	}
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&tracking)
}

/* Verifies duplicate commits, missing mainlines, and changed order never become authority. */
@(test)
revision_sequence_sets_reject_ambiguous_or_changed_targets :: proc(t: ^testing.T) {
	first := revision_sequence_test_target(t, REVISION_SEQUENCE_FIRST)
	merge := revision_sequence_test_target(t, REVISION_SEQUENCE_SECOND)
	merge.parent_count = 2
	invalid_merge := [?]ksawery.Revision_Sequence_Target{first, merge}
	_, opened, failure := ksawery.revision_sequence_set_open(invalid_merge[:])
	testing.expect(t, !opened && failure == .Target_Incompatible)
	merge.mainline = {number = 1, parent = conflict_test_revision(t, REVISION_SEQUENCE_PARENT)}
	duplicate := [?]ksawery.Revision_Sequence_Target{first, first}
	_, opened, failure = ksawery.revision_sequence_set_open(duplicate[:])
	testing.expect(t, !opened && failure == .Target_Duplicate)
	limits := ksawery.DEFAULT_REVISION_SEQUENCE_LIMITS
	limits.commits = 1
	_, opened, failure = ksawery.revision_sequence_set_open(invalid_merge[:], limits)
	testing.expect(t, !opened && failure == .Target_Limit)

	forward := [?]ksawery.Revision_Sequence_Target{first, merge}
	reverse := [?]ksawery.Revision_Sequence_Target{merge, first}
	forward_set, forward_opened, _ := ksawery.revision_sequence_set_open(forward[:])
	reverse_set, reverse_opened, _ := ksawery.revision_sequence_set_open(reverse[:])
	if forward_opened && reverse_opened {
		defer ksawery.revision_sequence_set_close(&forward_set)
		defer ksawery.revision_sequence_set_close(&reverse_set)
		forward_identity, _ := ksawery.revision_sequence_set_descriptor(&forward_set)
		reverse_identity, _ := ksawery.revision_sequence_set_descriptor(&reverse_set)
		testing.expect(t, forward_identity != reverse_identity)
	}
}

/* Verifies cherry-pick and revert starts share exact clean-state rules without sharing family identity. */
@(test)
revision_sequence_starts_bind_family_order_message_and_repository_state :: proc(t: ^testing.T) {
	families := [2]ksawery.Revision_Sequence_Family {
		ksawery.Revision_Sequence_Family.Cherry_Pick,
		ksawery.Revision_Sequence_Family.Revert,
	}
	for family in families {
		precondition := revision_sequence_test_start(t, family)
		testing.expect(t, ksawery.revision_sequence_precondition_is_valid(precondition))
		changed_family := precondition
		changed_family.family = family == .Cherry_Pick ? .Revert : .Cherry_Pick
		testing.expect(t, ksawery.revision_sequence_precondition_is_valid(changed_family))
		confirmation, prepared, _ := ksawery.revision_sequence_confirmation_prepare(precondition, 71)
		if prepared {
			confirmed, _ := ksawery.revision_sequence_confirmation_confirm(&confirmation, confirmation.id)
			if confirmed {
				_, requested, request_failure := ksawery.revision_sequence_request_prepare(
					changed_family, 71, &confirmation,
				)
				testing.expect(t, !requested && request_failure == .Confirmation_Mismatch)
			}
		}
		dirty := precondition
		dirty.worktree_paths = 1
		testing.expect_value(
			t,
			ksawery.revision_sequence_precondition_failure(dirty),
			ksawery.Failure_Code.Action_Unavailable,
		)
		modified := precondition
		modified.editor.modified_repository_resources = 1
		testing.expect_value(
			t,
			ksawery.revision_sequence_precondition_failure(modified),
			ksawery.Failure_Code.Modified_Buffer,
		)
		composed := precondition
		composed.message.mode = .Composed
		testing.expect(t, ksawery.commit_message_assign(&composed.message.content, "Use one selected commit"))
		testing.expect(t, !ksawery.revision_sequence_precondition_is_valid(composed))
	}
}

/* Verifies Continue, Skip, and Abort remain exact operation-specific sequence controls. */
@(test)
revision_sequence_controls_are_family_and_step_exact :: proc(t: ^testing.T) {
	continued := revision_sequence_test_control(t, .Cherry_Pick, .Continue, .Active)
	testing.expect(t, ksawery.revision_sequence_precondition_is_valid(continued))
	wrong_kind := continued
	wrong_kind.sequence_kind = .Revert
	testing.expect(t, !ksawery.revision_sequence_precondition_is_valid(wrong_kind))
	unresolved := continued
	unresolved.sequence_state = .Conflicted
	unresolved.unmerged_paths = 1
	unresolved.worktree_paths = 1
	testing.expect(t, !ksawery.revision_sequence_precondition_is_valid(unresolved))

	skipped := revision_sequence_test_control(t, .Revert, .Skip, .Conflicted)
	testing.expect(t, ksawery.revision_sequence_precondition_is_valid(skipped))
	changed_step := skipped
	changed_step.step.position = 2
	confirmation, prepared, _ := ksawery.revision_sequence_confirmation_prepare(skipped, 91)
	testing.expect(t, prepared)
	if prepared {
		confirmed, _ := ksawery.revision_sequence_confirmation_confirm(&confirmation, confirmation.id)
		testing.expect(t, confirmed)
		_, requested, request_failure := ksawery.revision_sequence_request_prepare(
			changed_step, 91, &confirmation,
		)
		testing.expect(t, !requested && request_failure == .Confirmation_Mismatch)
	}
	aborted := revision_sequence_test_control(t, .Revert, .Abort, .Conflicted)
	aborted.step = {}
	testing.expect(t, ksawery.revision_sequence_precondition_is_valid(aborted))
}

/* Verifies confirmation is single-use, drift is stale, and bounded results release all ownership. */
@(test)
revision_sequence_requests_and_results_are_exact_and_bounded :: proc(t: ^testing.T) {
	precondition := revision_sequence_test_start(t, .Cherry_Pick)
	confirmation, prepared, prepare_failure := ksawery.revision_sequence_confirmation_prepare(precondition, 101)
	testing.expectf(t, prepared, "revision sequence confirmation failed with %v", prepare_failure)
	if !prepared do return
	confirmed, confirmation_failure := ksawery.revision_sequence_confirmation_confirm(
		&confirmation, confirmation.id,
	)
	testing.expectf(t, confirmed, "revision sequence confirmation was rejected with %v", confirmation_failure)
	request, requested, request_failure := ksawery.revision_sequence_request_prepare(
		precondition, 101, &confirmation,
	)
	testing.expectf(t, requested, "revision sequence request failed with %v", request_failure)
	if !requested do return
	_, repeated, repeated_failure := ksawery.revision_sequence_request_prepare(precondition, 102, &confirmation)
	testing.expect(t, !repeated && repeated_failure == .Confirmation_Mismatch)
	drifted := precondition
	drifted.selection.fingerprint.bytes[0] = drifted.selection.fingerprint.bytes[0] ~ 0xff
	current, current_failure := ksawery.revision_sequence_request_revalidate(drifted, request)
	testing.expect(t, !current && current_failure == .Stale_Observation)

	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	result, opened, result_failure := ksawery.revision_sequence_result_open(
		request,
		true,
		1,
		transmute([]u8)(string("partial sequence")),
		transmute([]u8)(string("conflict")),
		.Process_Failed,
		allocator,
	)
	testing.expectf(t, opened, "revision sequence result failed with %v", result_failure)
	if opened {
		descriptor, described := ksawery.revision_sequence_result_descriptor(&result)
		testing.expect(t, described && descriptor.outcome == .Awaiting_Refresh && descriptor.refresh_required)
		usage, measured := ksawery.revision_sequence_result_usage(&result)
		testing.expect(t, measured && usage.commits == precondition.selection.commits)
		ksawery.revision_sequence_result_close(&result)
	}
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&tracking)
}

revision_sequence_test_target :: proc(t: ^testing.T, text: string) -> ksawery.Revision_Sequence_Target {
	return {revision = conflict_test_revision(t, text), parent_count = 1}
}

revision_sequence_test_set_identity :: proc(t: ^testing.T) -> ksawery.Revision_Sequence_Set_Identity {
	targets := [?]ksawery.Revision_Sequence_Target {
		revision_sequence_test_target(t, REVISION_SEQUENCE_FIRST),
		revision_sequence_test_target(t, REVISION_SEQUENCE_SECOND),
	}
	set, opened, _ := ksawery.revision_sequence_set_open(targets[:])
	if !opened do return {}
	defer ksawery.revision_sequence_set_close(&set)
	identity, _ := ksawery.revision_sequence_set_descriptor(&set)
	return identity
}

revision_sequence_test_start :: proc(
	t: ^testing.T,
	family: ksawery.Revision_Sequence_Family,
) -> ksawery.Revision_Sequence_Precondition {
	repository: ksawery.Repository_Context
	testing.expect(t, ksawery.repository_context_assign(&repository, "/tmp/odra-ksawery-revision-sequence"))
	current := conflict_test_revision(t, REVISION_SEQUENCE_CURRENT)
	branch_name: ksawery.Ref_Name
	testing.expect(t, ksawery.ref_name_assign(&branch_name, "refs/heads/main"))
	branch := ksawery.Ref_Identity {
		repository = repository,
		generation = 82,
		kind = .Local_Branch,
		name = branch_name,
		object = current,
		object_type = .Commit,
	}
	index_fingerprint: ksawery.Revision_Sequence_Index_Fingerprint
	bytes: [ksawery.REVISION_SEQUENCE_FINGERPRINT_BYTES]u8
	for &byte, index in bytes do byte = u8(index + 1)
	testing.expect(t, ksawery.revision_sequence_index_fingerprint_assign(&index_fingerprint, bytes[:]))
	return {
		repository = repository,
		status_generation = 80,
		history_generation = 81,
		ref_generation = 82,
		sequence_generation = 83,
		head = {.Symbolic, branch, current},
		original_head = {branch = branch_name, revision = current},
		index_tree = {conflict_test_revision(t, REVISION_SEQUENCE_TREE)},
		index_fingerprint = index_fingerprint,
		repository_operation = .Normal,
		sequence_kind = .None,
		sequence_state = .Inactive,
		editor = {repository_resources = 2},
		family = family,
		action = .Start,
		selection = revision_sequence_test_set_identity(t),
		message = {.Preserve_Selected, {}},
		signing = .Configured,
	}
}

revision_sequence_test_control :: proc(
	t: ^testing.T,
	family: ksawery.Revision_Sequence_Family,
	action: ksawery.Revision_Sequence_Action,
	state: ksawery.Sequence_Observation_State,
) -> ksawery.Revision_Sequence_Precondition {
	precondition := revision_sequence_test_start(t, family)
	precondition.head.object = conflict_test_revision(t, REVISION_SEQUENCE_FIRST)
	precondition.head.branch.object = precondition.head.object
	precondition.repository_operation = family == .Cherry_Pick ? .Cherry_Picking : .Reverting
	precondition.sequence_kind = family == .Cherry_Pick ? .Cherry_Pick : .Revert
	precondition.sequence_state = state
	precondition.sequence = {generation = precondition.sequence_generation, fingerprint = 84}
	precondition.step = {
		position = 1,
		total = precondition.selection.commits,
		target = revision_sequence_test_target(t, REVISION_SEQUENCE_FIRST),
	}
	precondition.action = action
	precondition.message = {.Not_Used, {}}
	precondition.signing = .Not_Used
	if action == .Continue {
		precondition.message = {.Git_Prepared, {}}
		precondition.signing = .Configured
	}
	if state == .Conflicted {
		precondition.worktree_paths = 1
		precondition.unmerged_paths = 1
	}
	return precondition
}
