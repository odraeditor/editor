// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery

import "core:mem"
import "core:testing"

/* Verifies complete paths retain explicit mark order and one action direction. */
@(test)
grouped_selection_admits_compatible_complete_paths :: proc(t: ^testing.T) {
	observation, opened := semantic_test_observation(
		Observation_Generation(301),
		"# branch.head main\x00? new.txt\x001 .M N... 100644 100644 100644 aaa bbb edited.txt\x00",
	)
	testing.expect(t, opened)
	if !opened do return
	defer status_observation_close(&observation)
	grouped, grouped_opened, failure := grouped_selection_open(&observation)
	testing.expectf(t, grouped_opened, "grouped selection failed with %v", failure)
	if !grouped_opened do return
	defer grouped_selection_close(&grouped)
	selection, selected := status_selection_begin(&observation)
	if selected do selection, selected, _ = status_selection_move(&observation, selection, .Next)
	testing.expect(t, selected)
	marked, mark_failure := grouped_selection_mark(&observation, nil, selection, &grouped)
	testing.expectf(t, marked, "first path mark failed with %v", mark_failure)
	selection, selected, _ = status_selection_move(&observation, selection, .Next)
	selection, selected, _ = status_selection_move(&observation, selection, .Next)
	testing.expect(t, selected)
	marked, mark_failure = grouped_selection_mark(&observation, nil, selection, &grouped)
	testing.expectf(t, marked, "second path mark failed with %v", mark_failure)
	descriptor, described := grouped_selection_descriptor(&grouped)
	testing.expect(t, described)
	testing.expect_value(t, descriptor.granularity, Grouped_Granularity.Complete_Paths)
	testing.expect_value(t, descriptor.action, Index_Action.Stage)
	testing.expect_value(t, descriptor.targets, u32(2))
	testing.expect(t, grouped_selection_action_available(&grouped, .Stage))
	first, first_found := grouped_selection_target(&grouped, 0)
	second, second_found := grouped_selection_target(&grouped, 1)
	testing.expect(t, first_found && second_found)
	if first_found && second_found {
		testing.expect_value(t, first.group, Change_Group.Untracked)
		testing.expect_value(t, second.group, Change_Group.Unstaged)
	}
}

/* Verifies same-path hunks reject duplicates and incompatible path targets. */
@(test)
grouped_selection_admits_only_compatible_diff_units :: proc(t: ^testing.T) {
	observation, detail, document, selection, ready := partial_index_action_test_state(.Unstaged)
	testing.expect(t, ready)
	if !ready do return
	defer partial_index_action_test_close(&observation, &detail, &document)
	grouped, opened, failure := grouped_selection_open(&observation)
	testing.expectf(t, opened, "hunk group failed with %v", failure)
	if !opened do return
	defer grouped_selection_close(&grouped)
	marked, mark_failure := grouped_selection_mark(&observation, &document, selection, &grouped)
	testing.expectf(t, marked, "first hunk failed with %v", mark_failure)
	marked, mark_failure = grouped_selection_mark(&observation, &document, selection, &grouped)
	testing.expect(t, !marked)
	testing.expect_value(t, mark_failure, Failure_Code.Target_Duplicate)
	moved := false
	selection, moved, _ = status_selection_move(&observation, selection, .Next, &document)
	testing.expect(t, moved)
	marked, mark_failure = grouped_selection_mark(&observation, &document, selection, &grouped)
	testing.expectf(t, marked, "second hunk failed with %v", mark_failure)
	descriptor, described := grouped_selection_descriptor(&grouped)
	testing.expect(t, described && descriptor.targets == 2)
	testing.expect_value(t, descriptor.granularity, Grouped_Granularity.Diff_Units)
	testing.expect(t, grouped_selection_action_available(&grouped, .Stage))
	path_selection := selection
	path_selection.current.kind = Status_Item_Kind.Path
	path_selection.current.source = {}
	path_selection.current.unit = {}
	marked, mark_failure = grouped_selection_mark(&observation, &document, path_selection, &grouped)
	testing.expect(t, !marked)
	testing.expect_value(t, mark_failure, Failure_Code.Target_Incompatible)
}

/* Verifies target limits, fresh-observation invalidation, and exact cleanup. */
@(test)
grouped_selection_bounds_reconciles_and_releases :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	observation, opened := semantic_test_observation(
		Observation_Generation(302),
		"# branch.head main\x00? first.txt\x00? second.txt\x00? third.txt\x00",
	)
	testing.expect(t, opened)
	if !opened {
		mem.tracking_allocator_destroy(&tracking)
		return
	}
	grouped, grouped_opened, failure := grouped_selection_open(
		&observation,
		Grouped_Selection_Limits{targets = 2},
		allocator,
	)
	testing.expectf(t, grouped_opened, "bounded group failed with %v", failure)
	if !grouped_opened {
		status_observation_close(&observation)
		mem.tracking_allocator_destroy(&tracking)
		return
	}
	selection, selected := status_selection_begin(&observation)
	if selected do selection, selected, _ = status_selection_move(&observation, selection, .Next)
	for index in 0 ..< 2 {
		marked, mark_failure := grouped_selection_mark(&observation, nil, selection, &grouped)
		testing.expectf(t, marked, "bounded mark %d failed with %v", index, mark_failure)
		if index == 0 {
			selection, selected, _ = status_selection_move(&observation, selection, .Next)
		}
	}
	selection, selected, _ = status_selection_move(&observation, selection, .Next)
	_, limit_failure := grouped_selection_mark(&observation, nil, selection, &grouped)
	testing.expect_value(t, limit_failure, Failure_Code.Target_Limit)
	usage, measured := grouped_selection_usage(&grouped)
	testing.expect(t, measured && usage.targets == 2 && usage.allocation_bytes > 0)
	refreshed, refreshed_opened := semantic_test_observation(
		Observation_Generation(303),
		"# branch.head main\x00? first.txt\x00? second.txt\x00",
	)
	testing.expect(t, refreshed_opened)
	if refreshed_opened {
		removed, reconciled, reconcile_failure := grouped_selection_reconcile(&grouped, &refreshed)
		testing.expectf(t, reconciled, "group reconciliation failed with %v", reconcile_failure)
		testing.expect_value(t, removed, u32(2))
		descriptor, _ := grouped_selection_descriptor(&grouped)
		testing.expect_value(t, descriptor.targets, u32(0))
		status_observation_close(&refreshed)
	}
	grouped_selection_close(&grouped)
	status_observation_close(&observation)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&tracking)
}

/* Verifies unsupported, mixed-direction, stale, and overlapping targets are rejected. */
@(test)
grouped_selection_rejects_incompatible_target_shapes :: proc(t: ^testing.T) {
	observation, opened := semantic_test_observation(
		Observation_Generation(304),
		"# branch.head main\x00? new.txt\x001 M. N... 100644 100644 100644 aaa bbb staged.txt\x00" +
		"u UU N... 100644 100644 100644 100644 aaa bbb ccc conflict.txt\x00",
	)
	testing.expect(t, opened)
	if !opened do return
	defer status_observation_close(&observation)
	grouped, grouped_opened, _ := grouped_selection_open(&observation)
	testing.expect(t, grouped_opened)
	if !grouped_opened do return
	defer grouped_selection_close(&grouped)
	selection, staged_selection, unmerged_selection: Status_Selection
	path_count, counted := status_observation_path_count(&observation)
	testing.expect(t, counted)
	for index in 0 ..< path_count {
		path, found := status_observation_path(&observation, index)
		if !found do continue
		candidate := Status_Selection {
			generation = Observation_Generation(304),
			current = {kind = .Path, group = path.group, path = path.id},
		}
		switch path.group {
		case .Untracked: selection = candidate
		case .Staged: staged_selection = candidate
		case .Unmerged: unmerged_selection = candidate
		case .Unstaged, .Invalid:
		}
	}
	selected := selection.current.kind == .Path && staged_selection.current.kind == .Path &&
	            unmerged_selection.current.kind == .Path
	testing.expect(t, selected)
	if !selected do return
	marked, mark_failure := grouped_selection_mark(&observation, nil, selection, &grouped)
	testing.expectf(t, selected && marked, "initial target failed with %v", mark_failure)
	mixed, mixed_failure := grouped_selection_mark(&observation, nil, staged_selection, &grouped)
	testing.expect(t, !mixed)
	testing.expect_value(t, mixed_failure, Failure_Code.Target_Incompatible)
	unsupported, unsupported_failure := grouped_selection_mark(
		&observation,
		nil,
		unmerged_selection,
		&grouped,
	)
	testing.expect(t, !unsupported)
	testing.expect_value(t, unsupported_failure, Failure_Code.Action_Unavailable)
	refreshed, refreshed_opened := semantic_test_observation(
		Observation_Generation(305),
		"# branch.head main\x00? new.txt\x00",
	)
	testing.expect(t, refreshed_opened)
	if refreshed_opened {
		stale, stale_failure := grouped_selection_mark(&refreshed, nil, selection, &grouped)
		testing.expect(t, !stale)
		testing.expect_value(t, stale_failure, Failure_Code.Stale_Observation)
		status_observation_close(&refreshed)
	}
	first := Grouped_Target {
		granularity = .Diff_Units,
		old_start = 10,
		old_count = 4,
		new_start = 10,
		new_count = 4,
	}
	overlapping := Grouped_Target {
		granularity = .Diff_Units,
		old_start = 13,
		old_count = 2,
		new_start = 20,
		new_count = 2,
	}
	disjoint := Grouped_Target {
		granularity = .Diff_Units,
		old_start = 20,
		old_count = 2,
		new_start = 20,
		new_count = 2,
	}
	testing.expect(t, grouped_diff_targets_overlap(first, overlapping))
	testing.expect(t, !grouped_diff_targets_overlap(first, disjoint))
}

/* Verifies the shared admission predicate rejects cross-path hunks and mixed layers. */
@(test)
grouped_selection_compatibility_rejects_cross_path_and_layer :: proc(t: ^testing.T) {
	observation, detail, document, selection, ready := partial_index_action_test_state(.Unstaged)
	testing.expect(t, ready)
	if !ready do return
	defer partial_index_action_test_close(&observation, &detail, &document)
	grouped, opened, _ := grouped_selection_open(&observation)
	testing.expect(t, opened)
	if !opened do return
	defer grouped_selection_close(&grouped)
	marked, _ := grouped_selection_mark(&observation, &document, selection, &grouped)
	testing.expect(t, marked)
	state := grouped_selection_data(&grouped)
	testing.expect(t, state != nil && len(state.targets) == 1)
	if state == nil || len(state.targets) != 1 do return
	cross_path := state.targets[0]
	cross_path.path.path += 1
	cross_path.unit.path.path += 1
	cross_path.unit.unit += 1
	cross_path.old_start += 100
	cross_path.new_start += 100
	testing.expect_value(
		t,
		grouped_target_compatibility(state, cross_path, .Stage, .Working_Tree),
		Failure_Code.Target_Incompatible,
	)
	mixed_layer := state.targets[0]
	mixed_layer.unit.unit += 1
	mixed_layer.old_start += 100
	mixed_layer.new_start += 100
	testing.expect_value(
		t,
		grouped_target_compatibility(state, mixed_layer, .Unstage, .Index),
		Failure_Code.Target_Incompatible,
	)
	overlapping := state.targets[0]
	overlapping.unit.unit += 1
	testing.expect_value(
		t,
		grouped_target_compatibility(state, overlapping, .Stage, .Working_Tree),
		Failure_Code.Target_Overlap,
	)
}
