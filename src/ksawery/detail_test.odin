// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery

import "core:testing"

/* Verifies detail binds copied content to the exact path generation and state. */
@(test)
path_detail_is_bounded_and_generation_checked :: proc(t: ^testing.T) {
	observation, opened := semantic_test_observation(Observation_Generation(12),
		"# branch.head main\x00? notes.txt\x00")
	testing.expect(t, opened)
	if !opened do return
	defer status_observation_close(&observation)
	path, found := status_observation_path_by_id(&observation, Path_ID(1))
	testing.expect(t, found)
	if !found do return
	target := Path_Target{generation = Observation_Generation(12), path = path.id}
	detail, detail_opened, failure := path_detail_open(
		&observation, target, transmute([]u8)(string("new file\n")), true, DEFAULT_PROCESS_LIMITS,
	)
	testing.expectf(t, detail_opened, "detail open failed with %v", failure)
	if !detail_opened do return
	defer path_detail_close(&detail)
	descriptor, described := path_detail_descriptor(&detail)
	testing.expect(t, described)
	testing.expect_value(t, descriptor.kind, Path_Detail_Kind.Untracked)
	testing.expect(t, descriptor.truncated)
	testing.expect(t, path_detail_is_current(&detail, &observation))

	refreshed, refreshed_opened := semantic_test_observation(Observation_Generation(13),
		"# branch.head main\x00? notes.txt\x00")
	testing.expect(t, refreshed_opened)
	if refreshed_opened {
		testing.expect(t, !path_detail_is_current(&detail, &refreshed))
		status_observation_close(&refreshed)
	}
}

/* Verifies stale path targets and over-limit detail are rejected before publication. */
@(test)
path_detail_rejects_stale_and_oversized_content :: proc(t: ^testing.T) {
	observation, opened := semantic_test_observation(Observation_Generation(14),
		"# branch.head main\x00? notes.txt\x00")
	testing.expect(t, opened)
	if !opened do return
	defer status_observation_close(&observation)

	stale := Path_Target{generation = Observation_Generation(15), path = Path_ID(1)}
	_, stale_opened, stale_failure := path_detail_open(&observation, stale, nil, false, DEFAULT_PROCESS_LIMITS)
	testing.expect(t, !stale_opened)
	testing.expect_value(t, stale_failure, Failure_Code.Stale_Observation)

	oversized, allocation_error := make([]u8, int(DEFAULT_DIFF_BYTES) + 1)
	testing.expect(t, allocation_error == nil)
	if allocation_error != nil do return
	defer delete(oversized)
	target := Path_Target{generation = Observation_Generation(14), path = Path_ID(1)}
	_, oversized_opened, oversized_failure := path_detail_open(&observation, target, oversized[:], false, DEFAULT_PROCESS_LIMITS)
	testing.expect(t, !oversized_opened)
	testing.expect_value(t, oversized_failure, Failure_Code.Output_Limit)
}
