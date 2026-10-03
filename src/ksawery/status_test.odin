// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery

import "core:mem"
import "core:testing"

/* Verifies porcelain-v2 records become bounded semantic Status paths. */
@(test)
status_observation_parses_branch_groups_and_rename_records :: proc(t: ^testing.T) {
	repository: Repository_Context
	ready := repository_context_assign(&repository, "/work/example")
	testing.expect(t, ready)
	if !ready do return
	output := transmute([]u8)(string(
		"# branch.oid 0123456789abcdef\x00" +
		"# branch.head main\x00" +
		"1 M. N... 100644 100644 100644 aaa bbb src/main.odin\x00" +
		"? notes.txt\x00" +
		"2 R. N... 100644 100644 100644 aaa bbb R100 new-name.txt\x00old-name.txt\x00" +
		"u UU N... 100644 100644 100644 100644 aaa bbb ccc conflict.txt\x00",
	))
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	observation, opened, failure := status_observation_open(
		repository,
		Observation_Generation(1),
		output,
		nil,
		DEFAULT_PROCESS_LIMITS,
		allocator,
	)
	testing.expectf(t, opened, "status parse failed with %v", failure)
	if !opened {
		mem.tracking_allocator_destroy(&tracking)
		return
	}

	descriptor, described := status_observation_descriptor(&observation)
	testing.expect(t, described)
	testing.expect_value(t, descriptor.path_count, u32(4))
	testing.expect_value(t, repository_context_string(&descriptor.repository), "/work/example")
	testing.expect_value(t, string(descriptor.branch.bytes[:descriptor.branch.length]), "main")

	first, first_found := status_observation_path(&observation, 0)
	second, second_found := status_observation_path(&observation, 1)
	third, third_found := status_observation_path(&observation, 2)
	fourth, fourth_found := status_observation_path(&observation, 3)
	testing.expect(t, first_found && second_found && third_found && fourth_found)
	testing.expect_value(t, first.group, Change_Group.Staged)
	testing.expect_value(t, second.group, Change_Group.Untracked)
	testing.expect_value(t, third.group, Change_Group.Staged)
	testing.expect_value(t, fourth.group, Change_Group.Unmerged)
	path_text, copied := status_observation_path_text(&observation, third)
	testing.expect(t, copied)
	testing.expect_value(t, string(path_text), "new-name.txt")

	status_observation_close(&observation)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&tracking)
}

/* Verifies clean and detached observations remain valid without synthetic paths. */
@(test)
status_observation_accepts_clean_detached_repository :: proc(t: ^testing.T) {
	repository: Repository_Context
	ready := repository_context_assign(&repository, "/work/example/nested")
	testing.expect(t, ready)
	if !ready do return
	output := transmute([]u8)(string("# branch.oid deadbeef\x00# branch.head (detached)\x00"))
	observation, opened, failure := status_observation_open(
		repository,
		Observation_Generation(7),
		output,
		nil,
		DEFAULT_PROCESS_LIMITS,
	)
	testing.expectf(t, opened, "clean detached parse failed with %v", failure)
	if !opened do return
	defer status_observation_close(&observation)
	descriptor, described := status_observation_descriptor(&observation)
	testing.expect(t, described)
	testing.expect_value(t, descriptor.path_count, u32(0))
	testing.expect_value(t, string(descriptor.branch.bytes[:descriptor.branch.length]), "(detached)")
}

/* Verifies staged and unstaged records preserve their distinct semantic groups. */
@(test)
status_observation_distinguishes_index_and_worktree_changes :: proc(t: ^testing.T) {
	repository: Repository_Context
	ready := repository_context_assign(&repository, "/work/example")
	testing.expect(t, ready)
	if !ready do return
	output := transmute([]u8)(string(
		"# branch.head main\x00" +
		"1 M. N... 100644 100644 100644 aaa bbb index.txt\x00" +
		"1 .M N... 100644 100644 100644 aaa bbb worktree.txt\x00",
	))
	observation, opened, failure := status_observation_open(
		repository,
		Observation_Generation(3),
		output,
		nil,
		DEFAULT_PROCESS_LIMITS,
	)
	testing.expectf(t, opened, "index/worktree parse failed with %v", failure)
	if !opened do return
	defer status_observation_close(&observation)
	first, first_found := status_observation_path(&observation, 0)
	second, second_found := status_observation_path(&observation, 1)
	testing.expect(t, first_found && second_found)
	testing.expect_value(t, first.group, Change_Group.Staged)
	testing.expect_value(t, second.group, Change_Group.Unstaged)
}

/* Verifies malformed porcelain records cannot publish a partial Status observation. */
@(test)
status_observation_rejects_malformed_records :: proc(t: ^testing.T) {
	repository: Repository_Context
	ready := repository_context_assign(&repository, "/work/example")
	testing.expect(t, ready)
	if !ready do return
	malformed := transmute([]u8)(string("1 M. N... missing-fields\x00"))
	_, opened, failure := status_observation_open(
		repository,
		Observation_Generation(1),
		malformed,
		nil,
		DEFAULT_PROCESS_LIMITS,
	)
	testing.expect(t, !opened)
	testing.expect_value(t, failure, Failure_Code.Parse)
}

/* Verifies one path changed in both layers becomes two distinct semantic targets. */
@(test)
status_observation_separates_index_and_worktree_changes_for_one_path :: proc(t: ^testing.T) {
	repository: Repository_Context
	testing.expect(t, repository_context_assign(&repository, "/work/example"))
	observation, opened, failure := status_observation_open(
		repository,
		Observation_Generation(15),
		transmute([]u8)(string("# branch.head main\x001 MM N... 100644 100644 100644 aaa bbb notes.txt\x00")),
		nil,
		DEFAULT_PROCESS_LIMITS,
	)
	testing.expectf(t, opened, "dual-layer observation failed with %v", failure)
	if !opened do return
	defer status_observation_close(&observation)
	count, counted := status_observation_path_count(&observation)
	testing.expect(t, counted)
	testing.expect_value(t, count, u32(2))
	indexed, indexed_found := status_observation_path(&observation, 0)
	working, working_found := status_observation_path(&observation, 1)
	testing.expect(t, indexed_found && working_found)
	if indexed_found do testing.expect_value(t, indexed.group, Change_Group.Staged)
	if working_found do testing.expect_value(t, working.group, Change_Group.Unstaged)
	indexed_text, indexed_copied := status_observation_path_text(&observation, indexed)
	working_text, working_copied := status_observation_path_text(&observation, working)
	testing.expect(t, indexed_copied && working_copied)
	if indexed_copied do testing.expect_value(t, string(indexed_text), "notes.txt")
	if working_copied do testing.expect_value(t, string(working_text), "notes.txt")
}
