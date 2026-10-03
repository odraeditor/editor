// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery

import "core:mem"
import "core:testing"

/* Verifies stage and unstage availability derives from the selected semantic state. */
@(test)
index_actions_admit_only_supported_path_groups :: proc(t: ^testing.T) {
	observation, opened := semantic_test_observation(Observation_Generation(40),
		"# branch.head main\x00? new.txt\x001 .M N... 100644 100644 100644 aaa bbb edited.txt\x001 M. N... 100644 100644 100644 aaa bbb staged.txt\x00")
	testing.expect(t, opened)
	if !opened do return
	defer status_observation_close(&observation)
	selection, _ := status_selection_begin(&observation)
	selection, _, _ = status_selection_move(&observation, selection, .Next)
	stage, staged, stage_failure := index_action_prepare(&observation, selection, .Stage, Index_Operation_ID(1))
	testing.expectf(t, staged, "stage request failed with %v", stage_failure)
	if staged {
		process, process_ok := index_action_process_request(stage)
		testing.expect(t, process_ok)
		testing.expect_value(t, process.kind, Request_Kind.Stage_Path)
	}
	_, unstaged, unstage_failure := index_action_prepare(&observation, selection, .Unstage, Index_Operation_ID(2))
	testing.expect(t, !unstaged)
	testing.expect_value(t, unstage_failure, Failure_Code.Action_Unavailable)
}

/* Verifies exact generation revalidation rejects replaced observations. */
@(test)
index_actions_reject_stale_observations :: proc(t: ^testing.T) {
	previous, previous_opened := semantic_test_observation(Observation_Generation(41),
		"# branch.head main\x00? new.txt\x00")
	next, next_opened := semantic_test_observation(Observation_Generation(42),
		"# branch.head main\x00? new.txt\x00")
	testing.expect(t, previous_opened && next_opened)
	if !previous_opened || !next_opened do return
	defer status_observation_close(&previous)
	defer status_observation_close(&next)
	selection, _ := status_selection_begin(&previous)
	selection, _, _ = status_selection_move(&previous, selection, .Next)
	request, prepared, _ := index_action_prepare(&previous, selection, .Stage, Index_Operation_ID(3))
	testing.expect(t, prepared)
	_, valid, failure := index_action_revalidate(&next, request)
	testing.expect(t, !valid)
	testing.expect_value(t, failure, Failure_Code.Stale_Observation)
	result, result_opened, result_failure := index_action_result_open(request, 0, nil, nil)
	testing.expectf(t, result_opened, "action result failed with %v", result_failure)
	if result_opened {
		testing.expect(t, index_action_result_is_current(&result, &previous))
		testing.expect(t, !index_action_result_is_current(&result, &next))
		index_action_result_close(&result)
	}
}

/* Verifies bounded action results own and release copied output. */
@(test)
index_action_results_copy_bounded_output :: proc(t: ^testing.T) {
	observation, opened := semantic_test_observation(Observation_Generation(43),
		"# branch.head main\x00? new.txt\x00")
	testing.expect(t, opened)
	if !opened do return
	defer status_observation_close(&observation)
	selection, _ := status_selection_begin(&observation)
	selection, _, _ = status_selection_move(&observation, selection, .Next)
	request, prepared, _ := index_action_prepare(&observation, selection, .Stage, Index_Operation_ID(4))
	testing.expect(t, prepared)
	if !prepared do return
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	result, result_opened, failure := index_action_result_open(
		request, 0, transmute([]u8)(string("ok")), nil, .None, allocator,
	)
	testing.expectf(t, result_opened, "result open failed with %v", failure)
	if result_opened {
		descriptor, described := index_action_result_descriptor(&result)
		testing.expect(t, described && descriptor.succeeded)
		index_action_result_close(&result)
	}
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&tracking)
}

/* Verifies result ownership rejects process output beyond the admitted limit. */
@(test)
index_action_results_reject_output_beyond_request_limit :: proc(t: ^testing.T) {
	observation, opened := semantic_test_observation(
		Observation_Generation(44),
		"# branch.head main\x00? new.txt\x00",
	)
	testing.expect(t, opened)
	if !opened do return
	defer status_observation_close(&observation)
	selection, _ := status_selection_begin(&observation)
	selection, _, _ = status_selection_move(&observation, selection, .Next)
	request, prepared, _ := index_action_prepare(
		&observation,
		selection,
		.Stage,
		Index_Operation_ID(5),
	)
	testing.expect(t, prepared)
	if !prepared do return
	oversized := make([]u8, int(request.limits.stdout_bytes) + 1, context.temp_allocator)
	defer delete(oversized, context.temp_allocator)
	_, result_opened, failure := index_action_result_open(request, 0, oversized, nil)
	testing.expect(t, !result_opened)
	testing.expect_value(t, failure, Failure_Code.Output_Limit)
}
