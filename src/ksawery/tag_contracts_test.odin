// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery

import "core:mem"
import "core:testing"

TAG_TEST_MAIN_OBJECT :: "1111111111111111111111111111111111111111"
TAG_TEST_OTHER_OBJECT :: "2222222222222222222222222222222222222222"

@(private)
tag_contracts_test_status :: proc(
	generation: Observation_Generation,
	allocator := context.allocator,
) -> (Status_Observation, bool) {
	repository: Repository_Context
	if !repository_context_assign(&repository, "/work/tags") do return {}, false
	observation, opened, _ := status_observation_open(
		repository,
		generation,
		transmute([]u8)(string("# branch.head main\x00")),
		nil,
		DEFAULT_PROCESS_LIMITS,
		allocator,
	)
	return observation, opened
}

@(private)
tag_contracts_test_refs :: proc(
	generation: Ref_Generation,
	output: []u8,
	allocator := context.allocator,
) -> (Ref_Observation, bool) {
	repository: Repository_Context
	if !repository_context_assign(&repository, "/work/tags") do return {}, false
	observation, opened, _ := ref_observation_open(
		repository,
		generation,
		output,
		nil,
		transmute([]u8)(string(TAG_TEST_MAIN_OBJECT + "\n")),
		DEFAULT_REF_LIMITS,
		allocator,
	)
	return observation, opened
}

@(private)
tag_contracts_test_before_refs :: proc(
	generation: Ref_Generation,
	allocator := context.allocator,
) -> (Ref_Observation, bool) {
	return tag_contracts_test_refs(
		generation,
		transmute([]u8)(string(
			"refs/heads/main\x00" + TAG_TEST_MAIN_OBJECT + "\x00commit\x00\x00\x00*\x00\n" +
			"refs/remotes/origin/main\x00" + TAG_TEST_MAIN_OBJECT + "\x00commit\x00\x00\x00 \x00\n" +
			"refs/tags/annotated\x00" + TAG_TEST_OTHER_OBJECT + "\x00tag\x00\x00\x00 \x00\n" +
			"refs/tags/v0.1.0\x00" + TAG_TEST_MAIN_OBJECT + "\x00commit\x00\x00\x00 \x00\n",
		)),
		allocator,
	)
}

@(private)
tag_contracts_test_ref :: proc(observation: ^Ref_Observation, name: string) -> (Ref_Identity, bool) {
	count, counted := ref_observation_ref_count(observation)
	if !counted do return {}, false
	for ordinal in 0 ..< count {
		identity, found := ref_observation_ref(observation, ordinal)
		if !found do continue
		copy := identity
		if ref_name_string(&copy.name) == name do return identity, true
	}
	return {}, false
}

@(private)
tag_contracts_test_request :: proc(
	status: ^Status_Observation,
	refs: ^Ref_Observation,
	intent: Tag_Intent,
	operation: Tag_Operation_ID,
) -> (Tag_Request, bool, Failure_Code) {
	precondition, prepared, failure := tag_precondition_prepare(status, refs, intent)
	if !prepared do return {}, false, failure
	confirmation, confirmation_ready, confirmation_failure := tag_confirmation_prepare(
		precondition,
		Tag_Confirmation_ID(u64(operation)),
	)
	if !confirmation_ready do return {}, false, confirmation_failure
	confirmed, confirm_failure := tag_confirmation_confirm(&confirmation, confirmation.id)
	if !confirmed do return {}, false, confirm_failure
	return tag_request_prepare(precondition, operation, &confirmation)
}

/* Verifies local tag names use one bounded Git-compatible refs/tags namespace. */
@(test)
local_tag_names_reject_ambiguous_or_unsafe_user_input :: proc(t: ^testing.T) {
	valid := []string{"v0.1.0", "release/preview-1", "candidate.2"}
	for text in valid {
		name: Local_Tag_Name
		testing.expectf(t, local_tag_name_assign(&name, text), "valid tag name rejected: %s", text)
		if local_tag_name_is_valid(name) {
			testing.expect_value(t, local_tag_name_string(&name), text)
			full := name.reference
			testing.expect(t, ref_name_has_prefix(ref_name_string(&full), "refs/tags/"))
		}
	}
	invalid := []string{
		"", "@", ".hidden", "release.lock", "release..next", "release@{next", "release//next",
		"release/", "/release", "release.", "release name", "release~1", "release^", "release:",
		"release?", "release*", "release[", "release\\next", "release\nnext",
	}
	for text in invalid {
		name: Local_Tag_Name
		testing.expectf(t, !local_tag_name_assign(&name, text), "invalid tag name admitted: %s", text)
	}
}

/* Verifies create and delete preconditions bind observed commit targets and reject duplicates or drift. */
@(test)
tag_preconditions_require_exact_observed_targets :: proc(t: ^testing.T) {
	status, status_opened := tag_contracts_test_status(Observation_Generation(91))
	refs, refs_opened := tag_contracts_test_before_refs(Ref_Generation(91))
	testing.expect(t, status_opened && refs_opened)
	if !status_opened || !refs_opened do return
	defer status_observation_close(&status)
	defer ref_observation_close(&refs)
	main, main_found := tag_contracts_test_ref(&refs, "refs/heads/main")
	remote, remote_found := tag_contracts_test_ref(&refs, "refs/remotes/origin/main")
	annotated, annotated_found := tag_contracts_test_ref(&refs, "refs/tags/annotated")
	existing, existing_found := tag_contracts_test_ref(&refs, "refs/tags/v0.1.0")
	created: Local_Tag_Name
	duplicate: Local_Tag_Name
	testing.expect(t, main_found && remote_found && annotated_found && existing_found &&
	                  local_tag_name_assign(&created, "v0.2.0") &&
	                  local_tag_name_assign(&duplicate, "v0.1.0"))
	if !main_found || !remote_found || !annotated_found || !existing_found do return
	create, create_ready, create_failure := tag_precondition_prepare(
		&status, &refs, {operation = .Create, target = main, name = created},
	)
	testing.expectf(t, create_ready && tag_precondition_is_valid(create), "create failed with %v", create_failure)
	remote_create, remote_ready, remote_failure := tag_precondition_prepare(
		&status, &refs, {operation = .Create, target = remote, name = created},
	)
	testing.expectf(t, remote_ready && tag_precondition_is_valid(remote_create), "remote target failed with %v", remote_failure)
	deletion, delete_ready, delete_failure := tag_precondition_prepare(
		&status, &refs, {operation = .Delete, target = existing},
	)
	testing.expectf(t, delete_ready && tag_precondition_is_valid(deletion), "delete failed with %v", delete_failure)
	_, duplicate_ready, duplicate_failure := tag_precondition_prepare(
		&status, &refs, {operation = .Create, target = main, name = duplicate},
	)
	testing.expect(t, !duplicate_ready && duplicate_failure == .Target_Duplicate)
	_, annotated_ready, annotated_failure := tag_precondition_prepare(
		&status, &refs, {operation = .Create, target = annotated, name = created},
	)
	testing.expect(t, !annotated_ready && annotated_failure == .Invalid_Request)
	stale := main
	stale.generation = Ref_Generation(92)
	_, stale_ready, stale_failure := tag_precondition_prepare(
		&status, &refs, {operation = .Create, target = stale, name = created},
	)
	testing.expect(t, !stale_ready && stale_failure == .Ref_Unavailable)
}

/* Verifies every local tag mutation consumes one exact confirmation without signing, force, or remote fields. */
@(test)
tag_requests_require_one_shot_exact_confirmation :: proc(t: ^testing.T) {
	status, status_opened := tag_contracts_test_status(Observation_Generation(93))
	refs, refs_opened := tag_contracts_test_before_refs(Ref_Generation(93))
	testing.expect(t, status_opened && refs_opened)
	if !status_opened || !refs_opened do return
	defer status_observation_close(&status)
	defer ref_observation_close(&refs)
	main, found := tag_contracts_test_ref(&refs, "refs/heads/main")
	name: Local_Tag_Name
	testing.expect(t, found && local_tag_name_assign(&name, "v0.2.0"))
	if !found do return
	precondition, prepared, failure := tag_precondition_prepare(
		&status, &refs, {operation = .Create, target = main, name = name},
	)
	testing.expectf(t, prepared, "tag precondition failed with %v", failure)
	if !prepared do return
	_, request_ready, request_failure := tag_request_prepare(precondition, Tag_Operation_ID(93), nil)
	testing.expect(t, !request_ready && request_failure == .Confirmation_Required)
	confirmation, confirmation_ready, _ := tag_confirmation_prepare(precondition, Tag_Confirmation_ID(93))
	testing.expect(t, confirmation_ready)
	if !confirmation_ready do return
	confirmed, confirmation_failure := tag_confirmation_confirm(&confirmation, Tag_Confirmation_ID(94))
	testing.expect(t, !confirmed && confirmation_failure == .Confirmation_Mismatch)
	confirmed, confirmation_failure = tag_confirmation_confirm(&confirmation, Tag_Confirmation_ID(93))
	testing.expect(t, confirmed && confirmation_failure == .None)
	request, request_prepared, request_prepare_failure := tag_request_prepare(precondition, Tag_Operation_ID(93), &confirmation)
	testing.expect(t, request_prepared && request_prepare_failure == .None && tag_request_is_valid(request))
	_, repeated, repeated_failure := tag_request_prepare(precondition, Tag_Operation_ID(94), &confirmation)
	testing.expect(t, !repeated && repeated_failure == .Confirmation_Mismatch)
}

/* Verifies refreshed semantic truth proves create and delete outcomes and releases retained output. */
@(test)
tag_results_require_fresh_operation_specific_truth_and_cleanup :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	status, status_opened := tag_contracts_test_status(Observation_Generation(95), allocator)
	before, before_opened := tag_contracts_test_before_refs(Ref_Generation(95), allocator)
	testing.expect(t, status_opened && before_opened)
	if !status_opened || !before_opened {
		if status.state != nil do status_observation_close(&status)
		if before.state != nil do ref_observation_close(&before)
		mem.tracking_allocator_destroy(&tracking)
		return
	}
	defer {
		status_observation_close(&status)
		ref_observation_close(&before)
		testing.expect_value(t, tracking.current_memory_allocated, i64(0))
		mem.tracking_allocator_destroy(&tracking)
	}
	main, main_found := tag_contracts_test_ref(&before, "refs/heads/main")
	existing, existing_found := tag_contracts_test_ref(&before, "refs/tags/v0.1.0")
	created: Local_Tag_Name
	testing.expect(t, main_found && existing_found && local_tag_name_assign(&created, "v0.2.0"))
	if !main_found || !existing_found do return
	intents := []Tag_Intent{
		{operation = .Create, target = main, name = created},
		{operation = .Delete, target = existing},
	}
	fresh_outputs := [][]u8{
		transmute([]u8)(string(
			"refs/heads/main\x00" + TAG_TEST_MAIN_OBJECT + "\x00commit\x00\x00\x00*\x00\n" +
			"refs/tags/v0.1.0\x00" + TAG_TEST_MAIN_OBJECT + "\x00commit\x00\x00\x00 \x00\n" +
			"refs/tags/v0.2.0\x00" + TAG_TEST_MAIN_OBJECT + "\x00commit\x00\x00\x00 \x00\n",
		)),
		transmute([]u8)(string(
			"refs/heads/main\x00" + TAG_TEST_MAIN_OBJECT + "\x00commit\x00\x00\x00*\x00\n",
		)),
	}
	for intent, index in intents {
		request, prepared, failure := tag_contracts_test_request(
			&status, &before, intent, Tag_Operation_ID(95 + index),
		)
		testing.expectf(t, prepared, "%v request failed with %v", intent.operation, failure)
		if !prepared do continue
		result, opened, result_failure := tag_result_open(
			request,
			true,
			0,
			transmute([]u8)(string("ok\n")),
			nil,
			.None,
			allocator,
		)
		testing.expectf(t, opened, "%v result failed with %v", intent.operation, result_failure)
		if !opened do continue
		descriptor, described := tag_result_descriptor(&result)
		testing.expect(t, described && !descriptor.verified && !descriptor.succeeded)
		testing.expect_value(t, tag_feedback(descriptor), Tag_Feedback.Refreshing)
		fresh, fresh_opened := tag_contracts_test_refs(
			Ref_Generation(96 + index), fresh_outputs[index], allocator,
		)
		testing.expect(t, fresh_opened)
		if fresh_opened {
			verified, verify_failure := tag_result_verify(&result, &fresh)
			testing.expectf(t, verified, "%v verification failed with %v", intent.operation, verify_failure)
			descriptor, described = tag_result_descriptor(&result)
			testing.expect(t, described && descriptor.verified && descriptor.succeeded)
			testing.expect_value(t, tag_feedback(descriptor), Tag_Feedback.Completed)
			tag_result_close(&result)
			ref_observation_close(&fresh)
		} else {
			tag_result_close(&result)
		}
	}
	cancel_request, prepared, _ := tag_contracts_test_request(
		&status,
		&before,
		{operation = .Create, target = main, name = created},
		Tag_Operation_ID(98),
	)
	if prepared {
		cancelled, opened, _ := tag_result_open(cancel_request, false, 0, nil, nil, .Cancelled, allocator)
		testing.expect(t, opened)
		if opened {
			descriptor, described := tag_result_descriptor(&cancelled)
			testing.expect(t, described && !descriptor.refresh_required)
			testing.expect_value(t, tag_feedback(descriptor), Tag_Feedback.Cancelled)
			tag_result_close(&cancelled)
		}
	}
}
