// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery

import "core:mem"
import "core:testing"

@(private)
commit_contracts_test_precondition :: proc(
	generation := Commit_Generation(71),
) -> (Commit_Precondition, bool) {
	repository: Repository_Context
	head, head_assigned := history_test_identity(HISTORY_TEST_SHA256)
	tree, tree_assigned := history_test_identity(HISTORY_TEST_SHA1)
	if !repository_context_assign(&repository, "/work/commit-contracts") || !head_assigned || !tree_assigned {
		return {}, false
	}
	return {
		repository = repository,
		generation = generation,
		head = {kind = .Revision, revision = head},
		index_tree = {object = tree},
		operation = .Normal,
		staged_paths = 1,
		unmerged_paths = 0,
	}, true
}

/* Verifies owned messages normalize line endings, retain a subject boundary, and reject empty subjects. */
@(test)
commit_messages_normalize_and_require_a_subject :: proc(t: ^testing.T) {
	message: Commit_Message
	testing.expect(t, commit_message_assign(&message, "subject\r\nbody\r\n"))
	text, copied := commit_message_text(&message)
	testing.expect(t, copied)
	if copied do testing.expect_value(t, string(text), "subject\nbody")
	testing.expect_value(t, message.subject_length, u32(7))
	testing.expect(t, commit_message_assign(&message, "Descripción"))
	invalid_utf8 := [1]u8{0xff}
	testing.expect(t, !commit_message_assign(&message, string(invalid_utf8[:])))
	testing.expect(t, !commit_message_assign(&message, "\nbody"))
	testing.expect(t, !commit_message_assign(&message, "\t  \nbody"))
	precondition, ready := commit_contracts_test_precondition()
	testing.expect(t, ready)
	if ready {
		_, prepared, failure := commit_request_prepare(precondition, message, Commit_Operation_ID(6))
		testing.expect(t, !prepared && failure == .Commit_Message_Invalid)
	}
}

/* Verifies normal commits bind one exact checked HEAD, index tree, operation, and staged-content state. */
@(test)
commit_requests_require_checked_normal_state_and_revalidate_exact_identities :: proc(t: ^testing.T) {
	precondition, ready := commit_contracts_test_precondition()
	testing.expect(t, ready)
	if !ready do return
	message: Commit_Message
	testing.expect(t, commit_message_assign(&message, "checked commit"))
	request, prepared, failure := commit_request_prepare(precondition, message, Commit_Operation_ID(1))
	testing.expectf(t, prepared, "commit request failed with %v", failure)
	if !prepared do return
	current, current_failure := commit_request_revalidate(precondition, request)
	testing.expectf(t, current, "current request failed with %v", current_failure)

	stale_head := precondition
	stale_head.generation += 1
	current, current_failure = commit_request_revalidate(stale_head, request)
	testing.expect(t, !current && current_failure == .Stale_Observation)
	stale_index := precondition
	changed_tree, tree_assigned := history_test_identity(HISTORY_TEST_SHA256)
	testing.expect(t, tree_assigned)
	if tree_assigned {
		stale_index.index_tree.object = changed_tree
		current, current_failure = commit_request_revalidate(stale_index, request)
		testing.expect(t, !current && current_failure == .Stale_Observation)
	}
	unstaged := precondition
	unstaged.staged_paths = 0
	_, admitted, admission_failure := commit_request_prepare(unstaged, message, Commit_Operation_ID(2))
	testing.expect(t, !admitted && admission_failure == .Commit_Unavailable)
	sequenced := precondition
	sequenced.operation = .Rebasing
	_, admitted, admission_failure = commit_request_prepare(sequenced, message, Commit_Operation_ID(3))
	testing.expect(t, !admitted && admission_failure == .Commit_Unavailable)
	unmerged := precondition
	unmerged.unmerged_paths = 1
	_, admitted, admission_failure = commit_request_prepare(unmerged, message, Commit_Operation_ID(4))
	testing.expect(t, !admitted && admission_failure == .Commit_Unavailable)
}

/* Verifies an unborn repository remains an explicit normal-commit precondition. */
@(test)
commit_requests_admit_staged_unborn_repositories :: proc(t: ^testing.T) {
	precondition, ready := commit_contracts_test_precondition()
	testing.expect(t, ready)
	if !ready do return
	precondition.head = {kind = .Unborn}
	message: Commit_Message
	testing.expect(t, commit_message_assign(&message, "root commit"))
	_, prepared, failure := commit_request_prepare(precondition, message, Commit_Operation_ID(5))
	testing.expectf(t, prepared, "unborn request failed with %v", failure)
}

/* Verifies bounded normal-commit outcomes copy and release process payloads. */
@(test)
commit_results_copy_and_release_bounded_process_payloads :: proc(t: ^testing.T) {
	precondition, ready := commit_contracts_test_precondition()
	testing.expect(t, ready)
	if !ready do return
	message: Commit_Message
	testing.expect(t, commit_message_assign(&message, "result ownership"))
	request, prepared, _ := commit_request_prepare(precondition, message, Commit_Operation_ID(6))
	testing.expect(t, prepared)
	if !prepared do return
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	resulting, result_assigned := history_test_identity(HISTORY_TEST_SHA1)
	testing.expect(t, result_assigned)
	result, opened, failure := commit_result_open(
		request, resulting, 0, transmute([]u8)(string("created")), transmute([]u8)(string("note")), .None, allocator,
	)
	testing.expectf(t, opened, "commit result failed with %v", failure)
	if opened {
		descriptor, described := commit_result_descriptor(&result)
		testing.expect(t, described && descriptor.succeeded)
		if described do testing.expect_value(t, descriptor.lineage.resulting, resulting)
		output, diagnostic, copied := commit_result_output(&result)
		testing.expect(t, copied)
		if copied {
			testing.expect_value(t, string(output), "created")
			testing.expect_value(t, string(diagnostic), "note")
		}
		commit_result_close(&result)
	}
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&tracking)
}

/* Verifies exact amend confirmation binds the checked HEAD, index, and message before replacement. */
@(test)
amend_requests_require_exact_confirmed_inputs_and_report_lineage :: proc(t: ^testing.T) {
	precondition, ready := commit_contracts_test_precondition()
	testing.expect(t, ready)
	if !ready do return
	history_output := transmute([]u8)(string(
		"\x1e" + HISTORY_TEST_SHA256 + "\x00" + HISTORY_TEST_SHA1 + "\x00Ada\x00ada@example.invalid\x002026-01-02T00:00:00+00:00\x002026-01-02T00:00:00+00:00\x00current subject\x00current body\x00" +
		"\x1e" + HISTORY_TEST_SHA1 + "\x00\x00Ada\x00ada@example.invalid\x002026-01-01T00:00:00+00:00\x002026-01-01T00:00:00+00:00\x00root\x00root body\x00",
	))
	history, opened, open_failure := history_observation_open(
		precondition.repository,
		History_Generation(81),
		history_output,
		{limits = DEFAULT_HISTORY_LIMITS},
	)
	testing.expectf(t, opened, "amend history failed with %v", open_failure)
	if !opened do return
	defer history_observation_close(&history)
	message: Commit_Message
	testing.expect(t, commit_message_assign(&message, "amended subject\n\nbody"))
	confirmation, prepared, prepare_failure := amend_confirmation_prepare(
		precondition, &history, message, Commit_Confirmation_ID(81),
	)
	testing.expectf(t, prepared, "amend confirmation failed with %v", prepare_failure)
	if !prepared do return
	testing.expect_value(t, confirmation.target.observation.revision, precondition.head.revision)
	confirmation_subject, subject_copied := commit_target_subject_text(&confirmation.target.subject)
	testing.expect(t, subject_copied)
	if subject_copied do testing.expect_value(t, string(confirmation_subject), "current subject")
	request_prepared: bool
	request_failure: Failure_Code
	_, request_prepared, request_failure = amend_request_prepare(
		precondition, message, Commit_Operation_ID(81), &confirmation,
	)
	testing.expect(t, !request_prepared && request_failure == .Confirmation_Required)
	confirmed, confirmation_failure := amend_confirmation_confirm(&confirmation, Commit_Confirmation_ID(82))
	testing.expect(t, !confirmed && confirmation_failure == .Confirmation_Mismatch)
	confirmed, confirmation_failure = amend_confirmation_confirm(&confirmation, Commit_Confirmation_ID(81))
	testing.expectf(t, confirmed, "amend confirmation acceptance failed with %v", confirmation_failure)
	if !confirmed do return
	request: Commit_Request
	request, request_prepared, request_failure = amend_request_prepare(
		precondition, message, Commit_Operation_ID(81), &confirmation,
	)
	testing.expectf(t, request_prepared, "amend request failed with %v", request_failure)
	if !request_prepared do return
	testing.expect_value(t, request.mode, Commit_Mode.Amend)
	testing.expect_value(t, request.arguments.amend_confirmation, Commit_Confirmation_ID(81))
	testing.expect_value(t, request.arguments.target, confirmation.target)
	lineage, derived := commit_request_lineage(request)
	testing.expect(t, derived)
	if derived {
		testing.expect_value(t, lineage.prior_head, precondition.head)
		testing.expect_value(t, lineage.replaced, precondition.head.revision)
		testing.expect_value(t, lineage.fixup_target, Revision_Identity{})
	}
	changed_index := precondition
	changed_index.index_tree.object, _ = history_test_identity(HISTORY_TEST_SHA256)
	_, request_prepared, request_failure = amend_request_prepare(
		changed_index, message, Commit_Operation_ID(82), &confirmation,
	)
	testing.expect(t, !request_prepared && request_failure == .Confirmation_Mismatch)
	_, request_prepared, request_failure = amend_request_prepare(
		precondition, message, Commit_Operation_ID(83), &confirmation,
	)
	testing.expect(t, !request_prepared && request_failure == .Confirmation_Mismatch)
	unborn := precondition
	unborn.head = {kind = .Unborn}
	_, request_prepared, request_failure = amend_request_prepare(
		unborn, message, Commit_Operation_ID(84), &confirmation,
	)
	testing.expect(t, !request_prepared && request_failure == .Commit_Unavailable)
}

/* Verifies fixup requests retain one exact History target and bounded result lineage. */
@(test)
fixup_requests_require_current_history_targets_and_report_lineage :: proc(t: ^testing.T) {
	precondition, ready := commit_contracts_test_precondition()
	testing.expect(t, ready)
	if !ready do return
	history_output := transmute([]u8)(string(
		"\x1e" + HISTORY_TEST_SHA256 + "\x00" + HISTORY_TEST_SHA1 + "\x00Ada\x00ada@example.invalid\x002026-01-02T00:00:00+00:00\x002026-01-02T00:00:00+00:00\x00child\x00child body\x00" +
		"\x1e" + HISTORY_TEST_SHA1 + "\x00\x00Ada\x00ada@example.invalid\x002026-01-01T00:00:00+00:00\x002026-01-01T00:00:00+00:00\x00root\x00root body\x00",
	))
	history, opened, open_failure := history_observation_open(
		precondition.repository,
		History_Generation(91),
		history_output,
		{limits = DEFAULT_HISTORY_LIMITS},
	)
	testing.expectf(t, opened, "fixup history failed with %v", open_failure)
	if !opened do return
	defer history_observation_close(&history)
	descriptor, described := history_observation_descriptor(&history)
	testing.expect(t, described)
	if !described do return
	target := History_Target{generation = descriptor.generation, revision = descriptor.head}
	request, prepared, prepare_failure := fixup_request_prepare(
		precondition, &history, target, Commit_Operation_ID(91),
	)
	testing.expectf(t, prepared, "fixup request failed with %v", prepare_failure)
	if !prepared do return
	testing.expect_value(t, request.mode, Commit_Mode.Fixup)
	testing.expect_value(t, request.arguments.target.observation, target)
	target_subject, subject_copied := commit_target_subject_text(&request.arguments.target.subject)
	testing.expect(t, subject_copied)
	if subject_copied do testing.expect_value(t, string(target_subject), "child")
	message, message_copied := commit_message_text(&request.message)
	testing.expect(t, message_copied)
	if message_copied do testing.expect_value(t, string(message), "fixup! child")
	lineage, derived := commit_request_lineage(request)
	testing.expect(t, derived)
	if derived do testing.expect_value(t, lineage.fixup_target, target.revision)
	stale_target := target
	stale_target.generation += 1
	_, prepared, prepare_failure = fixup_request_prepare(
		precondition, &history, stale_target, Commit_Operation_ID(92),
	)
	testing.expect(t, !prepared && prepare_failure == .Stale_Observation)

	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	resulting, result_assigned := history_test_identity(HISTORY_TEST_SHA1)
	testing.expect(t, result_assigned)
	result, result_opened, result_failure := commit_result_open(
		request, resulting, 0, transmute([]u8)(string("created")), transmute([]u8)(string("note")), .None, allocator,
	)
	testing.expectf(t, result_opened, "fixup result failed with %v", result_failure)
	if result_opened {
		result_descriptor, result_described := commit_result_descriptor(&result)
		testing.expect(t, result_described && result_descriptor.succeeded)
		if result_described {
			testing.expect_value(t, result_descriptor.lineage.fixup_target, target.revision)
			testing.expect_value(t, result_descriptor.lineage.resulting, resulting)
		}
		usage, measured := commit_result_usage(&result)
		testing.expect(t, measured)
		if measured {
			testing.expect_value(t, usage.message_bytes, u64(len("fixup! child")))
			testing.expect_value(t, usage.target_subject_bytes, u64(len("child")))
			testing.expect_value(t, usage.output_bytes, u64(len("created")))
			testing.expect_value(t, usage.diagnostic_bytes, u64(len("note")))
		}
		commit_result_close(&result)
	}
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&tracking)
}
