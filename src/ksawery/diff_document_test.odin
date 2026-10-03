// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery

import "core:mem"
import "core:testing"

@(private)
diff_document_test_detail :: proc(
	content: string,
	truncated := false,
	group := Change_Group.Unstaged,
	allocator := context.allocator,
) -> (Status_Observation, Path_Detail, bool) {
	output := "# branch.head main\x001 .M N... 100644 100644 100644 aaa bbb src/main.odin\x00"
	if group == .Staged {
		output = "# branch.head main\x001 M. N... 100644 100644 100644 aaa bbb src/main.odin\x00"
	} else if group == .Untracked {
		output = "# branch.head main\x00? src/main.odin\x00"
	}
	observation, opened := semantic_test_observation(Observation_Generation(41), output)
	if !opened do return {}, {}, false
	path, found := status_observation_path_by_id(&observation, Path_ID(1))
	if !found {
		status_observation_close(&observation)
		return {}, {}, false
	}
	detail, detail_opened, _ := path_detail_open(
		&observation,
		{generation = Observation_Generation(41), path = path.id},
		transmute([]u8)content,
		truncated,
		DEFAULT_PROCESS_LIMITS,
		allocator,
	)
	if !detail_opened {
		status_observation_close(&observation)
		return {}, {}, false
	}
	return observation, detail, true
}

@(private)
DIFF_DOCUMENT_TWO_HUNKS :: "diff --git a/src/main.odin b/src/main.odin\n" +
	"index 1111111..2222222 100644\n" +
	"--- a/src/main.odin\n" +
	"+++ b/src/main.odin\n" +
	"@@ -1,3 +1,3 @@\n" +
	" package main\n" +
	"-old first\n" +
	"+new first\n" +
	" context\n" +
	"@@ -10,2 +10,3 @@ tail\n" +
	" line ten\n" +
	"+inserted\n" +
	" line eleven\n"

/* Verifies complete unified diff becomes exact semantic units and patch material. */
@(test)
diff_document_parses_semantic_hunks :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	observation, detail, ready := diff_document_test_detail(DIFF_DOCUMENT_TWO_HUNKS, false, .Unstaged, allocator)
	testing.expect(t, ready)
	if !ready {
		mem.tracking_allocator_destroy(&tracking)
		return
	}
	document, opened, failure := diff_document_open(&detail, DEFAULT_DIFF_LIMITS, allocator)
	testing.expectf(t, opened, "semantic diff open failed with %v", failure)
	if opened {
		descriptor, described := diff_document_descriptor(&document)
		testing.expect(t, described)
		testing.expect_value(t, descriptor.layer, Diff_Layer.Working_Tree)
		testing.expect_value(t, descriptor.unit_count, u32(2))
		first, first_found := diff_document_unit(&document, 0)
		second, second_found := diff_document_unit(&document, 1)
		testing.expect(t, first_found && second_found)
		testing.expect_value(t, first.old_start, u32(1))
		testing.expect_value(t, first.old_count, u32(3))
		testing.expect_value(t, second.new_count, u32(3))
		testing.expect(t, first.target.source == second.target.source)
		first_patch, patch_found, patch_failure := diff_document_unit_patch(&document, first.target)
		testing.expectf(t, patch_found, "unit patch failed with %v", patch_failure)
		if patch_found {
			testing.expect(t, diff_bytes_have_prefix(first_patch, transmute([]u8)(string("diff --git "))))
			testing.expect(t, !diff_bytes_have_prefix(first_patch, transmute([]u8)(string("@@ "))))
		}
		first_line, line_found := diff_document_line(&document, 0)
		testing.expect(t, line_found)
		testing.expect_value(t, first_line.kind, Diff_Line_Kind.Context)
		testing.expect_value(t, first_line.old_line, u32(1))
		testing.expect_value(t, first_line.new_line, u32(1))
		usage, usage_ok := diff_document_usage(&document)
		testing.expect(t, usage_ok)
		testing.expect_value(t, usage.units, u32(2))
		testing.expect(t, usage.lines >= 7 && usage.patch_bytes > usage.presentation_bytes)
		testing.expect(t, diff_document_is_current(&document, &observation))
		diff_document_close(&document)
	}
	path_detail_close(&detail)
	status_observation_close(&observation)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&tracking)
}

/* Verifies indexed detail selects the index layer and stale patch targets fail. */
@(test)
diff_document_binds_patch_to_exact_source :: proc(t: ^testing.T) {
	observation, detail, ready := diff_document_test_detail(DIFF_DOCUMENT_TWO_HUNKS, false, .Staged)
	testing.expect(t, ready)
	if !ready do return
	defer status_observation_close(&observation)
	defer path_detail_close(&detail)
	document, opened, _ := diff_document_open(&detail)
	testing.expect(t, opened)
	if !opened do return
	defer diff_document_close(&document)
	unit, found := diff_document_unit(&document, 0)
	testing.expect(t, found)
	if !found do return
	testing.expect_value(t, unit.target.layer, Diff_Layer.Index)
	stale := unit.target
	stale.source += 1
	_, patch_found, failure := diff_document_unit_patch(&document, stale)
	testing.expect(t, !patch_found)
	testing.expect_value(t, failure, Failure_Code.Stale_Observation)
}

/* Verifies malformed, truncated, unsupported, and over-limit details publish no units. */
@(test)
diff_document_rejects_incomplete_authority :: proc(t: ^testing.T) {
	malformed := "diff --git a/file b/file\n--- a/file\n+++ b/file\n@@ -1,2 +1,2 @@\n-old\n+new\n"
	observation, detail, ready := diff_document_test_detail(malformed)
	testing.expect(t, ready)
	if ready {
		_, opened, failure := diff_document_open(&detail)
		testing.expect(t, !opened)
		testing.expect_value(t, failure, Failure_Code.Parse)
		path_detail_close(&detail)
		status_observation_close(&observation)
	}

	truncated_observation, truncated_detail, truncated_ready := diff_document_test_detail(
		DIFF_DOCUMENT_TWO_HUNKS,
		true,
	)
	testing.expect(t, truncated_ready)
	if truncated_ready {
		_, opened, failure := diff_document_open(&truncated_detail)
		testing.expect(t, !opened)
		testing.expect_value(t, failure, Failure_Code.Diff_Truncated)
		path_detail_close(&truncated_detail)
		status_observation_close(&truncated_observation)
	}

	untracked_observation, untracked_detail, untracked_ready := diff_document_test_detail(
		DIFF_DOCUMENT_TWO_HUNKS,
		false,
		.Untracked,
	)
	testing.expect(t, untracked_ready)
	if untracked_ready {
		_, opened, failure := diff_document_open(&untracked_detail)
		testing.expect(t, !opened)
		testing.expect_value(t, failure, Failure_Code.Diff_Unsupported)
		path_detail_close(&untracked_detail)
		status_observation_close(&untracked_observation)
	}

	limited_observation, limited_detail, limited_ready := diff_document_test_detail(DIFF_DOCUMENT_TWO_HUNKS)
	testing.expect(t, limited_ready)
	if limited_ready {
		limits := DEFAULT_DIFF_LIMITS
		limits.units = 1
		_, opened, failure := diff_document_open(&limited_detail, limits)
		testing.expect(t, !opened)
		testing.expect_value(t, failure, Failure_Code.Invalid_Request)
		path_detail_close(&limited_detail)
		status_observation_close(&limited_observation)
	}

	binary := "diff --git a/src/main.odin b/src/main.odin\n" +
		"index 1111111..2222222 100644\n" +
		"Binary files a/src/main.odin and b/src/main.odin differ\n"
	binary_observation, binary_detail, binary_ready := diff_document_test_detail(binary)
	testing.expect(t, binary_ready)
	if binary_ready {
		_, opened, failure := diff_document_open(&binary_detail)
		testing.expect(t, !opened)
		testing.expect_value(t, failure, Failure_Code.Diff_Unsupported)
		path_detail_close(&binary_detail)
		status_observation_close(&binary_observation)
	}
}
