// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery

import "core:mem"
import "core:testing"

BRANCH_TEST_MAIN_OBJECT :: "1111111111111111111111111111111111111111"
BRANCH_TEST_TOPIC_OBJECT :: "2222222222222222222222222222222222222222"

@(private)
branch_contracts_test_status :: proc(
	generation: Observation_Generation,
	paths: []u8 = nil,
	allocator := context.allocator,
	branch := "main",
) -> (Status_Observation, bool) {
	repository: Repository_Context
	if !repository_context_assign(&repository, "/work/branches") do return {}, false
	storage: [512]u8
	prefix := transmute([]u8)(string("# branch.head "))
	required := len(prefix) + len(branch) + 1 + len(paths)
	if len(branch) == 0 || required > len(storage) do return {}, false
	copy(storage[:len(prefix)], prefix)
	copy(storage[len(prefix):len(prefix) + len(branch)], transmute([]u8)branch)
	storage[len(prefix) + len(branch)] = 0
	copy(storage[len(prefix) + len(branch) + 1:required], paths)
	observation, opened, _ := status_observation_open(
		repository,
		generation,
		storage[:required],
		nil,
		DEFAULT_PROCESS_LIMITS,
		allocator,
	)
	return observation, opened
}

@(private)
branch_contracts_test_refs :: proc(
	generation: Ref_Generation,
	output: []u8,
	head: string,
	allocator := context.allocator,
) -> (Ref_Observation, bool) {
	repository: Repository_Context
	if !repository_context_assign(&repository, "/work/branches") do return {}, false
	observation, opened, _ := ref_observation_open(
		repository,
		generation,
		output,
		nil,
		transmute([]u8)head,
		DEFAULT_REF_LIMITS,
		allocator,
	)
	return observation, opened
}

@(private)
branch_contracts_test_before_refs :: proc(
	generation: Ref_Generation,
	allocator := context.allocator,
) -> (Ref_Observation, bool) {
	return branch_contracts_test_refs(
		generation,
		transmute([]u8)(string(
			"refs/heads/main\x00" + BRANCH_TEST_MAIN_OBJECT + "\x00commit\x00\x00\x00*\x00\n" +
			"refs/heads/topic\x00" + BRANCH_TEST_TOPIC_OBJECT + "\x00commit\x00\x00\x00 \x00\n",
		)),
		BRANCH_TEST_MAIN_OBJECT + "\n",
		allocator,
	)
}

@(private)
branch_contracts_test_ref :: proc(observation: ^Ref_Observation, name: string) -> (Ref_Identity, bool) {
	ref_name: Ref_Name
	if !ref_name_assign(&ref_name, name) do return {}, false
	return branch_ref_by_name(observation, ref_name)
}

@(private)
branch_contracts_test_request :: proc(
	status: ^Status_Observation,
	refs: ^Ref_Observation,
	intent: Branch_Intent,
	operation: Branch_Operation_ID,
	editor: Branch_Editor_State = {},
) -> (Branch_Request, bool, Failure_Code) {
	precondition, prepared, failure := branch_precondition_prepare(status, refs, editor, intent)
	if !prepared do return {}, false, failure
	confirmation, confirmation_ready, confirmation_failure := branch_confirmation_prepare(
		precondition,
		Branch_Confirmation_ID(u64(operation)),
	)
	if !confirmation_ready do return {}, false, confirmation_failure
	confirmed, confirm_failure := branch_confirmation_confirm(&confirmation, confirmation.id)
	if !confirmed do return {}, false, confirm_failure
	return branch_request_prepare(precondition, operation, &confirmation)
}

/* Verifies local branch names use one bounded Git-compatible refs/heads namespace. */
@(test)
local_branch_names_reject_ambiguous_or_unsafe_user_input :: proc(t: ^testing.T) {
	valid := []string{"topic", "feature/safe-name", "release-1.2"}
	for text in valid {
		name: Local_Branch_Name
		testing.expectf(t, local_branch_name_assign(&name, text), "valid branch name rejected: %s", text)
		if local_branch_name_is_valid(name) {
			testing.expect_value(t, local_branch_name_string(&name), text)
			full := name.reference
			testing.expect(t, ref_name_has_prefix(ref_name_string(&full), "refs/heads/"))
		}
	}
	invalid := []string{
		"", "@", ".hidden", "topic.lock", "topic..next", "topic@{next", "topic//next",
		"topic/", "/topic", "topic.", "topic name", "topic~1", "topic^", "topic:",
		"topic?", "topic*", "topic[", "topic\\next", "topic\nnext",
	}
	for text in invalid {
		name: Local_Branch_Name
		testing.expectf(t, !local_branch_name_assign(&name, text), "invalid branch name admitted: %s", text)
	}
}

/* Verifies mode-specific preconditions protect worktree replacement, current branch, duplicates, and merged deletion. */
@(test)
branch_preconditions_are_operation_specific_and_editor_aware :: proc(t: ^testing.T) {
	status, status_opened := branch_contracts_test_status(Observation_Generation(71))
	refs, refs_opened := branch_contracts_test_before_refs(Ref_Generation(71))
	testing.expect(t, status_opened && refs_opened)
	if !status_opened || !refs_opened do return
	defer status_observation_close(&status)
	defer ref_observation_close(&refs)
	topic, topic_found := branch_contracts_test_ref(&refs, "refs/heads/topic")
	main, main_found := branch_contracts_test_ref(&refs, "refs/heads/main")
	created: Local_Branch_Name
	renamed: Local_Branch_Name
	testing.expect(t, topic_found && main_found && local_branch_name_assign(&created, "created") &&
	                  local_branch_name_assign(&renamed, "renamed"))
	if !topic_found || !main_found do return
	intents := []Branch_Intent{
		{operation = .Create, name = created},
		{operation = .Switch, selected = topic},
		{operation = .Rename, selected = topic, name = renamed},
		{operation = .Delete, selected = topic, require_merged_to_head = true},
	}
	for intent in intents {
		precondition, prepared, failure := branch_precondition_prepare(&status, &refs, {repository_resources = 2}, intent)
		testing.expectf(t, prepared && branch_precondition_is_valid(precondition), "%v precondition failed with %v", intent.operation, failure)
	}
	_, duplicate_ready, duplicate_failure := branch_precondition_prepare(
		&status,
		&refs,
		{},
		{operation = .Create, name = {reference = main.name}},
	)
	testing.expect(t, !duplicate_ready && duplicate_failure == .Target_Duplicate)
	_, current_switch, current_switch_failure := branch_precondition_prepare(
		&status,
		&refs,
		{},
		{operation = .Switch, selected = main},
	)
	testing.expect(t, !current_switch && current_switch_failure == .Target_Duplicate)
	_, current_delete, current_delete_failure := branch_precondition_prepare(
		&status,
		&refs,
		{},
		{operation = .Delete, selected = main, require_merged_to_head = true},
	)
	testing.expect(t, !current_delete && current_delete_failure == .Action_Unavailable)
	_, unmerged_delete, unmerged_delete_failure := branch_precondition_prepare(
		&status,
		&refs,
		{},
		{operation = .Delete, selected = topic},
	)
	testing.expect(t, !unmerged_delete && unmerged_delete_failure == .Action_Unavailable)

	dirty, dirty_opened := branch_contracts_test_status(
		Observation_Generation(72),
		transmute([]u8)(string("? dirty.txt\x00")),
	)
	testing.expect(t, dirty_opened)
	if dirty_opened {
		defer status_observation_close(&dirty)
		_, switched, switch_failure := branch_precondition_prepare(
			&dirty,
			&refs,
			{},
			{operation = .Switch, selected = topic},
		)
		testing.expect(t, !switched && switch_failure == .Action_Unavailable)
		create_precondition, created_ready, _ := branch_precondition_prepare(
			&dirty,
			&refs,
			{},
			{operation = .Create, name = created},
		)
		testing.expect(t, created_ready && create_precondition.worktree_paths == 1)
	}
	unmerged, unmerged_opened := branch_contracts_test_status(
		Observation_Generation(73),
		transmute([]u8)(string("u UU N... 100644 100644 100644 100644 aaa bbb ccc conflict.txt\x00")),
	)
	testing.expect(t, unmerged_opened)
	if unmerged_opened {
		defer status_observation_close(&unmerged)
		_, switched, switch_failure := branch_precondition_prepare(
			&unmerged,
			&refs,
			{},
			{operation = .Switch, selected = topic},
		)
		testing.expect(t, !switched && switch_failure == .Action_Unavailable)
	}
	_, modified_switch, modified_failure := branch_precondition_prepare(
		&status,
		&refs,
		{repository_resources = 2, modified_repository_resources = 1},
		{operation = .Switch, selected = topic},
	)
	testing.expect(t, !modified_switch && modified_failure == .Modified_Buffer)
}

/* Verifies every local branch mutation consumes one exact confirmation and has no force request shape. */
@(test)
branch_requests_require_one_shot_exact_confirmation :: proc(t: ^testing.T) {
	status, status_opened := branch_contracts_test_status(Observation_Generation(73))
	refs, refs_opened := branch_contracts_test_before_refs(Ref_Generation(73))
	testing.expect(t, status_opened && refs_opened)
	if !status_opened || !refs_opened do return
	defer status_observation_close(&status)
	defer ref_observation_close(&refs)
	topic, found := branch_contracts_test_ref(&refs, "refs/heads/topic")
	if !found do return
	precondition, prepared, failure := branch_precondition_prepare(
		&status,
		&refs,
		{},
		{operation = .Delete, selected = topic, require_merged_to_head = true},
	)
	testing.expectf(t, prepared, "delete precondition failed with %v", failure)
	if !prepared do return
	_, request_ready, request_failure := branch_request_prepare(precondition, Branch_Operation_ID(73), nil)
	testing.expect(t, !request_ready && request_failure == .Confirmation_Required)
	confirmation, confirmation_ready, _ := branch_confirmation_prepare(precondition, Branch_Confirmation_ID(73))
	testing.expect(t, confirmation_ready)
	if !confirmation_ready do return
	confirmed, confirmation_failure := branch_confirmation_confirm(&confirmation, Branch_Confirmation_ID(74))
	testing.expect(t, !confirmed && confirmation_failure == .Confirmation_Mismatch)
	confirmed, confirmation_failure = branch_confirmation_confirm(&confirmation, Branch_Confirmation_ID(73))
	testing.expect(t, confirmed && confirmation_failure == .None)
	request, request_prepared, request_prepare_failure := branch_request_prepare(
		precondition,
		Branch_Operation_ID(73),
		&confirmation,
	)
	testing.expect(t, request_prepared && request_prepare_failure == .None && branch_request_is_valid(request))
	_, repeated, repeated_failure := branch_request_prepare(precondition, Branch_Operation_ID(74), &confirmation)
	testing.expect(t, !repeated && repeated_failure == .Confirmation_Mismatch)
}

/* Verifies refreshed semantic truth, not process output, proves create, switch, rename, and delete outcomes. */
@(test)
branch_results_require_fresh_operation_specific_truth_and_release_output :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	status, status_opened := branch_contracts_test_status(Observation_Generation(75), nil, allocator)
	before, before_opened := branch_contracts_test_before_refs(Ref_Generation(75), allocator)
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
	topic, topic_found := branch_contracts_test_ref(&before, "refs/heads/topic")
	created: Local_Branch_Name
	renamed: Local_Branch_Name
	testing.expect(t, topic_found && local_branch_name_assign(&created, "created") &&
	                  local_branch_name_assign(&renamed, "renamed"))
	if !topic_found do return
	intents := []Branch_Intent{
		{operation = .Create, name = created},
		{operation = .Switch, selected = topic},
		{operation = .Rename, selected = topic, name = renamed},
		{operation = .Delete, selected = topic, require_merged_to_head = true},
	}
	fresh_outputs := [][]u8{
		transmute([]u8)(string(
			"refs/heads/created\x00" + BRANCH_TEST_MAIN_OBJECT + "\x00commit\x00\x00\x00 \x00\n" +
			"refs/heads/main\x00" + BRANCH_TEST_MAIN_OBJECT + "\x00commit\x00\x00\x00*\x00\n" +
			"refs/heads/topic\x00" + BRANCH_TEST_TOPIC_OBJECT + "\x00commit\x00\x00\x00 \x00\n",
		)),
		transmute([]u8)(string(
			"refs/heads/main\x00" + BRANCH_TEST_MAIN_OBJECT + "\x00commit\x00\x00\x00 \x00\n" +
			"refs/heads/topic\x00" + BRANCH_TEST_TOPIC_OBJECT + "\x00commit\x00\x00\x00*\x00\n",
		)),
		transmute([]u8)(string(
			"refs/heads/main\x00" + BRANCH_TEST_MAIN_OBJECT + "\x00commit\x00\x00\x00*\x00\n" +
			"refs/heads/renamed\x00" + BRANCH_TEST_TOPIC_OBJECT + "\x00commit\x00\x00\x00 \x00\n",
		)),
		transmute([]u8)(string(
			"refs/heads/main\x00" + BRANCH_TEST_MAIN_OBJECT + "\x00commit\x00\x00\x00*\x00\n",
		)),
	}
	fresh_heads := []string{
		BRANCH_TEST_MAIN_OBJECT + "\n",
		BRANCH_TEST_TOPIC_OBJECT + "\n",
		BRANCH_TEST_MAIN_OBJECT + "\n",
		BRANCH_TEST_MAIN_OBJECT + "\n",
	}
	for intent, index in intents {
		request, prepared, failure := branch_contracts_test_request(
			&status,
			&before,
			intent,
			Branch_Operation_ID(75 + index),
		)
		testing.expectf(t, prepared, "%v request failed with %v", intent.operation, failure)
		if !prepared do continue
		result, opened, result_failure := branch_result_open(
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
		descriptor, described := branch_result_descriptor(&result)
		testing.expect(t, described && !descriptor.verified && !descriptor.succeeded)
		testing.expect_value(t, branch_feedback(descriptor), Branch_Feedback.Refreshing)
		fresh_status, fresh_status_opened := branch_contracts_test_status(
			Observation_Generation(76 + index),
			nil,
			allocator,
			"topic" if intent.operation == .Switch else "main",
		)
		fresh_refs, fresh_refs_opened := branch_contracts_test_refs(
			Ref_Generation(76 + index),
			fresh_outputs[index],
			fresh_heads[index],
			allocator,
		)
		testing.expect(t, fresh_status_opened && fresh_refs_opened)
		if fresh_status_opened && fresh_refs_opened {
			verified, verify_failure := branch_result_verify(&result, &fresh_status, &fresh_refs)
			testing.expectf(t, verified, "%v verification failed with %v", intent.operation, verify_failure)
			descriptor, described = branch_result_descriptor(&result)
			testing.expect(t, described && descriptor.verified && descriptor.succeeded)
			testing.expect_value(t, branch_feedback(descriptor), Branch_Feedback.Completed)
		}
		if fresh_status.state != nil do status_observation_close(&fresh_status)
		if fresh_refs.state != nil do ref_observation_close(&fresh_refs)
		branch_result_close(&result)
	}
	cancel_request, prepared, _ := branch_contracts_test_request(
		&status,
		&before,
		{operation = .Switch, selected = topic},
		Branch_Operation_ID(80),
	)
	if prepared {
		cancelled, opened, _ := branch_result_open(cancel_request, false, 0, nil, nil, .Cancelled, allocator)
		testing.expect(t, opened)
		if opened {
			descriptor, described := branch_result_descriptor(&cancelled)
			testing.expect(t, described && !descriptor.refresh_required)
			testing.expect_value(t, branch_feedback(descriptor), Branch_Feedback.Cancelled)
			branch_result_close(&cancelled)
		}
	}
}
