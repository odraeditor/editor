// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery

import "core:mem"
import "core:testing"

@(private)
partial_index_action_test_state :: proc(
	group: Change_Group,
	allocator := context.allocator,
) -> (Status_Observation, Path_Detail, Diff_Document, Status_Selection, bool) {
	observation, detail, ready := diff_document_test_detail(DIFF_DOCUMENT_TWO_HUNKS, false, group, allocator)
	if !ready do return {}, {}, {}, {}, false
	document, opened, _ := diff_document_open(&detail, DEFAULT_DIFF_LIMITS, allocator)
	if !opened {
		path_detail_close(&detail)
		status_observation_close(&observation)
		return {}, {}, {}, {}, false
	}
	selection, selected := status_selection_begin(&observation)
	if selected do selection, selected, _ = status_selection_move(&observation, selection, .Next, &document)
	if selected do selection, selected, _ = status_selection_move(&observation, selection, .Next, &document)
	if !selected {
		diff_document_close(&document)
		path_detail_close(&detail)
		status_observation_close(&observation)
		return {}, {}, {}, {}, false
	}
	return observation, detail, document, selection, true
}

@(private)
partial_index_action_test_close :: proc(
	observation: ^Status_Observation,
	detail: ^Path_Detail,
	document: ^Diff_Document,
) {
	diff_document_close(document)
	path_detail_close(detail)
	status_observation_close(observation)
}

/* Verifies exact working-tree and index hunks map to opposite patch directions. */
@(test)
partial_index_actions_select_checked_patch_direction :: proc(t: ^testing.T) {
	cases := []struct {
		group:     Change_Group,
		action:    Index_Action,
		direction: Patch_Direction,
	}{
		{.Unstaged, .Stage, .Apply},
		{.Staged, .Unstage, .Reverse},
	}
	for test_case in cases {
		observation, detail, document, selection, ready := partial_index_action_test_state(test_case.group)
		testing.expect(t, ready)
		if !ready do continue
		request, prepared, failure := partial_index_action_prepare(
			&observation,
			&document,
			selection,
			test_case.action,
			Index_Operation_ID(51),
		)
		testing.expectf(t, prepared, "partial request failed with %v", failure)
		if prepared {
			descriptor, described := partial_index_action_request_descriptor(&request)
			testing.expect(t, described)
			testing.expect_value(t, descriptor.direction, test_case.direction)
			testing.expect_value(t, descriptor.target.layer, diff_layer_for_group(test_case.group))
			patch, copied := partial_index_action_request_patch(&request)
			testing.expect(t, copied && len(patch) > 0)
			partial_index_action_request_close(&request)
		}
		partial_index_action_test_close(&observation, &detail, &document)
	}
}

/* Verifies mismatched operations and non-hunk selection remain unavailable. */
@(test)
partial_index_actions_reject_incompatible_selection :: proc(t: ^testing.T) {
	observation, detail, document, selection, ready := partial_index_action_test_state(.Unstaged)
	testing.expect(t, ready)
	if !ready do return
	defer partial_index_action_test_close(&observation, &detail, &document)
	_, prepared, failure := partial_index_action_prepare(
		&observation,
		&document,
		selection,
		.Unstage,
		Index_Operation_ID(52),
	)
	testing.expect(t, !prepared)
	testing.expect_value(t, failure, Failure_Code.Action_Unavailable)
	path_selection := selection
	path_selection.current.kind = .Path
	path_selection.current.source = {}
	path_selection.current.unit = {}
	_, prepared, failure = partial_index_action_prepare(
		&observation,
		&document,
		path_selection,
		.Stage,
		Index_Operation_ID(53),
	)
	testing.expect(t, !prepared)
	testing.expect_value(t, failure, Failure_Code.Diff_Unit_Unavailable)
}

/* Verifies a request owns its patch, rejects replacement, and frees all storage. */
@(test)
partial_index_actions_own_and_revalidate_patch :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	observation, detail, document, selection, ready := partial_index_action_test_state(.Unstaged, allocator)
	testing.expect(t, ready)
	if !ready {
		mem.tracking_allocator_destroy(&tracking)
		return
	}
	request, prepared, failure := partial_index_action_prepare(
		&observation,
		&document,
		selection,
		.Stage,
		Index_Operation_ID(54),
		DEFAULT_PROCESS_LIMITS,
		allocator,
	)
	testing.expectf(t, prepared, "owned request failed with %v", failure)
	if prepared {
		valid, validation_failure := partial_index_action_request_revalidate(&observation, &document, &request)
		testing.expectf(t, valid, "current request failed with %v", validation_failure)
		refreshed, refreshed_opened := semantic_test_observation(
			Observation_Generation(42),
			"# branch.head main\x001 .M N... 100644 100644 100644 aaa bbb src/main.odin\x00",
		)
		testing.expect(t, refreshed_opened)
		if refreshed_opened {
			current, stale_failure := partial_index_action_request_revalidate(&refreshed, &document, &request)
			testing.expect(t, !current)
			testing.expect_value(t, stale_failure, Failure_Code.Stale_Observation)
			status_observation_close(&refreshed)
		}
		usage, measured := partial_index_action_request_usage(&request)
		testing.expect(t, measured && usage.input_bytes > 0 && usage.allocation_bytes >= usage.input_bytes)
		request_descriptor, request_described := partial_index_action_request_descriptor(&request)
		testing.expect(t, request_described)
		result, opened, result_failure := partial_index_action_result_open(
			request_descriptor,
			0,
			transmute([]u8)(string("ok")),
			nil,
			.None,
			allocator,
		)
		testing.expectf(t, opened, "partial result failed with %v", result_failure)
		if opened {
			result_descriptor, described := partial_index_action_result_descriptor(&result)
			testing.expect(t, described && result_descriptor.succeeded)
			result_usage, measured_result := partial_index_action_result_usage(&result)
			testing.expect(t, measured_result && result_usage.output_bytes == 2)
			partial_index_action_result_close(&result)
		}
		partial_index_action_request_close(&request)
	}
	partial_index_action_test_close(&observation, &detail, &document)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&tracking)
}

/* Verifies copied hunk input cannot exceed the admitted process budget. */
@(test)
partial_index_actions_reject_oversized_patch_input :: proc(t: ^testing.T) {
	content, allocation_error := make([dynamic]u8, 0, 96 * 1_024, context.temp_allocator)
	testing.expect(t, allocation_error == nil)
	if allocation_error != nil do return
	defer delete(content)
	prefix := "diff --git a/src/main.odin b/src/main.odin\n" +
		"--- a/src/main.odin\n" +
		"+++ b/src/main.odin\n" +
		"@@ -1 +1 @@\n-"
	_, allocation_error = append(&content, ..transmute([]u8)prefix)
	for _ in 0 ..< 40 * 1_024 do append(&content, u8('a'))
	append(&content, u8('\n'))
	append(&content, u8('+'))
	for _ in 0 ..< 40 * 1_024 do append(&content, u8('b'))
	append(&content, u8('\n'))
	testing.expect(t, allocation_error == nil)
	if allocation_error != nil do return
	observation, detail, ready := diff_document_test_detail(string(content[:]))
	testing.expect(t, ready)
	if !ready do return
	defer status_observation_close(&observation)
	defer path_detail_close(&detail)
	document, opened, failure := diff_document_open(&detail)
	testing.expectf(t, opened, "large semantic diff failed with %v", failure)
	if !opened do return
	defer diff_document_close(&document)
	selection, selected := status_selection_begin(&observation)
	if selected do selection, selected, _ = status_selection_move(&observation, selection, .Next, &document)
	if selected do selection, selected, _ = status_selection_move(&observation, selection, .Next, &document)
	testing.expect(t, selected)
	if !selected do return
	limits := DEFAULT_PROCESS_LIMITS
	limits.diff_bytes = MIN_DIFF_BYTES
	_, prepared, prepare_failure := partial_index_action_prepare(
		&observation,
		&document,
		selection,
		.Stage,
		Index_Operation_ID(55),
		limits,
	)
	testing.expect(t, !prepared)
	testing.expect_value(t, prepare_failure, Failure_Code.Output_Limit)
}
