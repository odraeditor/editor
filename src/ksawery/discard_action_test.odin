// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery

import "core:mem"
import "core:testing"

@(private)
discard_test_selection :: proc(
	observation: ^Status_Observation,
	moves: int,
) -> (Status_Selection, bool) {
	selection, selected := status_selection_begin(observation)
	if !selected do return {}, false
	for _ in 0 ..< moves {
		selection, selected, _ = status_selection_move(observation, selection, .Next)
		if !selected do return {}, false
	}
	return selection, true
}

/* Verifies discard admits only one tracked working-tree path without modified buffer state. */
@(test)
discard_admits_only_unstaged_tracked_paths :: proc(t: ^testing.T) {
	observation, opened := semantic_test_observation(
		Observation_Generation(70),
		"# branch.head main\x00? new.txt\x001 .M N... 100644 100644 100644 aaa bbb edited.txt\x001 M. N... 100644 100644 100644 aaa bbb staged.txt\x00",
	)
	testing.expect(t, opened)
	if !opened do return
	defer status_observation_close(&observation)

	untracked, selected := discard_test_selection(&observation, 1)
	testing.expect(t, selected)
	_, prepared, failure := discard_action_prepare(
		&observation, untracked, Index_Operation_ID(1), Discard_Confirmation_ID(1), false,
	)
	testing.expect(t, !prepared)
	testing.expect_value(t, failure, Failure_Code.Action_Unavailable)

	unstaged, unstaged_selected := discard_test_selection(&observation, 3)
	testing.expect(t, unstaged_selected)
	request, discard_prepared, discard_failure := discard_action_prepare(
		&observation, unstaged, Index_Operation_ID(2), Discard_Confirmation_ID(2), false,
	)
	testing.expectf(t, discard_prepared, "discard request failed with %v", discard_failure)
	if discard_prepared do testing.expect(t, discard_action_request_is_valid(request))

	_, modified_prepared, modified_failure := discard_action_prepare(
		&observation, unstaged, Index_Operation_ID(3), Discard_Confirmation_ID(3), true,
	)
	testing.expect(t, !modified_prepared)
	testing.expect_value(t, modified_failure, Failure_Code.Modified_Buffer)

	staged, staged_selected := discard_test_selection(&observation, 5)
	testing.expect(t, staged_selected)
	_, staged_prepared, staged_failure := discard_action_prepare(
		&observation, staged, Index_Operation_ID(4), Discard_Confirmation_ID(4), false,
	)
	testing.expect(t, !staged_prepared)
	testing.expect_value(t, staged_failure, Failure_Code.Action_Unavailable)
}

/* Verifies only the exact confirmation grants process authority. */
@(test)
discard_requires_exact_confirmation_identity :: proc(t: ^testing.T) {
	observation, opened := semantic_test_observation(
		Observation_Generation(71),
		"# branch.head main\x001 .M N... 100644 100644 100644 aaa bbb edited.txt\x00",
	)
	testing.expect(t, opened)
	if !opened do return
	defer status_observation_close(&observation)
	selection, selected := discard_test_selection(&observation, 1)
	testing.expect(t, selected)
	request, prepared, _ := discard_action_prepare(
		&observation, selection, Index_Operation_ID(5), Discard_Confirmation_ID(8), false,
	)
	testing.expect(t, prepared)
	if !prepared do return

	_, current, failure := discard_action_revalidate(&observation, request, false)
	testing.expect(t, !current)
	testing.expect_value(t, failure, Failure_Code.Confirmation_Required)
	confirmed, confirmation_failure := discard_action_confirm(&request, Discard_Confirmation_ID(9))
	testing.expect(t, !confirmed)
	testing.expect_value(t, confirmation_failure, Failure_Code.Confirmation_Mismatch)
	confirmed, confirmation_failure = discard_action_confirm(&request, Discard_Confirmation_ID(8))
	testing.expectf(t, confirmed, "confirmation failed with %v", confirmation_failure)
	process, mapped := discard_action_process_request(request)
	testing.expect(t, mapped)
	if mapped do testing.expect_value(t, process.kind, Request_Kind.Discard_Path)
}

/* Verifies confirmation does not survive observation replacement or new buffer edits. */
@(test)
discard_revalidation_rejects_stale_or_modified_targets :: proc(t: ^testing.T) {
	previous, previous_opened := semantic_test_observation(
		Observation_Generation(72),
		"# branch.head main\x001 .M N... 100644 100644 100644 aaa bbb edited.txt\x00",
	)
	next, next_opened := semantic_test_observation(
		Observation_Generation(73),
		"# branch.head main\x001 .M N... 100644 100644 100644 aaa bbb edited.txt\x00",
	)
	testing.expect(t, previous_opened && next_opened)
	if !previous_opened || !next_opened do return
	defer status_observation_close(&previous)
	defer status_observation_close(&next)
	selection, selected := discard_test_selection(&previous, 1)
	testing.expect(t, selected)
	request, prepared, _ := discard_action_prepare(
		&previous, selection, Index_Operation_ID(6), Discard_Confirmation_ID(10), false,
	)
	testing.expect(t, prepared)
	if !prepared do return
	confirmed, _ := discard_action_confirm(&request, Discard_Confirmation_ID(10))
	testing.expect(t, confirmed)

	_, current, failure := discard_action_revalidate(&next, request, false)
	testing.expect(t, !current)
	testing.expect_value(t, failure, Failure_Code.Stale_Observation)
	_, current, failure = discard_action_revalidate(&previous, request, true)
	testing.expect(t, !current)
	testing.expect_value(t, failure, Failure_Code.Modified_Buffer)
}

/* Verifies discard results own bounded output and release all retained memory. */
@(test)
discard_results_are_bounded_and_released :: proc(t: ^testing.T) {
	observation, opened := semantic_test_observation(
		Observation_Generation(74),
		"# branch.head main\x001 .M N... 100644 100644 100644 aaa bbb edited.txt\x00",
	)
	testing.expect(t, opened)
	if !opened do return
	defer status_observation_close(&observation)
	selection, selected := discard_test_selection(&observation, 1)
	testing.expect(t, selected)
	request, prepared, _ := discard_action_prepare(
		&observation, selection, Index_Operation_ID(7), Discard_Confirmation_ID(11), false,
	)
	testing.expect(t, prepared)
	if !prepared do return
	confirmed, _ := discard_action_confirm(&request, Discard_Confirmation_ID(11))
	testing.expect(t, confirmed)

	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	result, result_opened, failure := discard_action_result_open(
		request, 0, transmute([]u8)(string("ok")), transmute([]u8)(string("note")), .None, allocator,
	)
	testing.expectf(t, result_opened, "discard result failed with %v", failure)
	if result_opened {
		descriptor, described := discard_action_result_descriptor(&result)
		testing.expect(t, described && descriptor.succeeded)
		usage, measured := discard_action_result_usage(&result)
		testing.expect(t, measured)
		if measured {
			testing.expect_value(t, usage.output_bytes, u64(2))
			testing.expect_value(t, usage.diagnostic_bytes, u64(4))
			testing.expect(t, usage.allocation_bytes >= usage.output_bytes + usage.diagnostic_bytes)
		}
		discard_action_result_close(&result)
	}
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&tracking)
}
