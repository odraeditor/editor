// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery

import "core:testing"

@(private)
semantic_test_observation :: proc(generation: Observation_Generation, output: string) -> (Status_Observation, bool) {
	repository: Repository_Context
	if !repository_context_assign(&repository, "/work/example") do return {}, false
	observation, opened, _ := status_observation_open(
		repository,
		generation,
		transmute([]u8)output,
		nil,
		DEFAULT_PROCESS_LIMITS,
	)
	return observation, opened
}

/* Verifies hierarchy order skips empty groups and retains parent identities. */
@(test)
status_hierarchy_omits_empty_groups :: proc(t: ^testing.T) {
	observation, opened := semantic_test_observation(Observation_Generation(4),
		"# branch.head main\x00? notes.txt\x001 .M N... 100644 100644 100644 aaa bbb src/main.odin\x00")
	testing.expect(t, opened)
	if !opened do return
	defer status_observation_close(&observation)

	count, available := status_hierarchy_item_count(&observation)
	testing.expect(t, available)
	testing.expect_value(t, count, u32(4))
	first, first_found := status_hierarchy_item(&observation, 0)
	second, second_found := status_hierarchy_item(&observation, 1)
	third, third_found := status_hierarchy_item(&observation, 2)
	fourth, fourth_found := status_hierarchy_item(&observation, 3)
	testing.expect(t, first_found && second_found && third_found && fourth_found)
	testing.expect_value(t, first.id, Status_Item_ID{kind = .Group, group = .Untracked})
	testing.expect_value(t, second.parent, first.id)
	testing.expect_value(t, third.id, Status_Item_ID{kind = .Group, group = .Unstaged})
	testing.expect_value(t, fourth.parent, third.id)
}

/* Verifies path selection uses exact generation identities and expansion remains local. */
@(test)
status_selection_moves_and_toggles_path_expansion :: proc(t: ^testing.T) {
	observation, opened := semantic_test_observation(Observation_Generation(8),
		"# branch.head main\x00? notes.txt\x00")
	testing.expect(t, opened)
	if !opened do return
	defer status_observation_close(&observation)

	selection, started := status_selection_begin(&observation)
	testing.expect(t, started)
	testing.expect_value(t, selection.current, Status_Item_ID{kind = .Group, group = .Untracked})
	moved, moved_ok, moved_failure := status_selection_move(&observation, selection, .Next)
	testing.expectf(t, moved_ok, "selection move failed with %v", moved_failure)
	if !moved_ok do return
	testing.expect_value(t, moved.current.kind, Status_Item_Kind.Path)
	expanded, expanded_ok, expanded_failure := status_selection_toggle_expansion(&observation, moved)
	testing.expectf(t, expanded_ok, "expansion failed with %v", expanded_failure)
	if !expanded_ok do return
	testing.expect_value(t, expanded.expanded.generation, Observation_Generation(8))
	testing.expect_value(t, expanded.expanded.path, moved.current.path)
	collapsed, collapsed_ok, collapsed_failure := status_selection_toggle_expansion(&observation, expanded)
	testing.expectf(t, collapsed_ok, "collapse failed with %v", collapsed_failure)
	testing.expect(t, collapsed_ok)
	if collapsed_ok do testing.expect_value(t, collapsed.expanded, Path_Target{})
}

/* Verifies refresh preserves a matching path and invalidates a stale generation. */
@(test)
status_selection_reconciles_paths_and_falls_back_to_group :: proc(t: ^testing.T) {
	previous, previous_opened := semantic_test_observation(Observation_Generation(9),
		"# branch.head main\x00? notes.txt\x00? removed.txt\x00")
	next, next_opened := semantic_test_observation(Observation_Generation(10),
		"# branch.head main\x00? notes.txt\x00")
	testing.expect(t, previous_opened && next_opened)
	if !previous_opened || !next_opened {
		if previous_opened do status_observation_close(&previous)
		if next_opened do status_observation_close(&next)
		return
	}
	defer status_observation_close(&previous)
	defer status_observation_close(&next)

	selection, started := status_selection_begin(&previous)
	testing.expect(t, started)
	selected, selected_ok, selected_failure := status_selection_move(&previous, selection, .Next)
	testing.expectf(t, selected_ok, "selection move failed with %v", selected_failure)
	if !selected_ok do return
	expanded, expanded_ok, expanded_failure := status_selection_toggle_expansion(&previous, selected)
	testing.expectf(t, expanded_ok, "expansion failed with %v", expanded_failure)
	if !expanded_ok do return
	reconciled, reconciled_ok, reconciled_failure := status_selection_reconcile(&previous, &next, expanded)
	testing.expectf(t, reconciled_ok, "reconciliation failed with %v", reconciled_failure)
	if !reconciled_ok do return
	testing.expect_value(t, reconciled.current.kind, Status_Item_Kind.Path)
	testing.expect_value(t, reconciled.expanded.generation, Observation_Generation(10))
	_, target_ok, target_failure := status_selection_path_target(&previous, reconciled)
	testing.expect(t, !target_ok)
	testing.expect_value(t, target_failure, Failure_Code.Stale_Observation)

	removed, removed_ok, removed_failure := status_selection_move(&previous, selected, .Next)
	testing.expectf(t, removed_ok, "second selection move failed with %v", removed_failure)
	if !removed_ok do return
	fallback, fallback_ok, fallback_failure := status_selection_reconcile(&previous, &next, removed)
	testing.expectf(t, fallback_ok, "fallback reconciliation failed with %v", fallback_failure)
	if fallback_ok do testing.expect_value(t, fallback.current, Status_Item_ID{kind = .Group, group = .Untracked})
}

/* Verifies expanded tracked detail inserts selectable semantic hunks under its path. */
@(test)
status_selection_navigates_semantic_diff_units :: proc(t: ^testing.T) {
	observation, detail, ready := diff_document_test_detail(DIFF_DOCUMENT_TWO_HUNKS)
	testing.expect(t, ready)
	if !ready do return
	defer status_observation_close(&observation)
	defer path_detail_close(&detail)
	document, opened, failure := diff_document_open(&detail)
	testing.expectf(t, opened, "semantic document failed with %v", failure)
	if !opened do return
	defer diff_document_close(&document)

	selection, selected := status_selection_begin(&observation)
	testing.expect(t, selected)
	selection, selected, _ = status_selection_move(&observation, selection, .Next)
	testing.expect(t, selected && selection.current.kind == .Path)
	selection, selected, _ = status_selection_toggle_expansion(&observation, selection)
	testing.expect(t, selected)
	count, counted := status_hierarchy_item_count(&observation, &document)
	testing.expect(t, counted)
	testing.expect_value(t, count, u32(4))

	first, moved, move_failure := status_selection_move(&observation, selection, .Next, &document)
	testing.expectf(t, moved, "first diff move failed with %v", move_failure)
	if !moved do return
	testing.expect_value(t, first.current.kind, Status_Item_Kind.Diff_Unit)
	testing.expect_value(t, first.current.unit, Diff_Unit_ID(1))
	target, targeted, target_failure := status_selection_diff_unit_target(&observation, &document, first)
	testing.expectf(t, targeted, "diff target failed with %v", target_failure)
	if targeted do testing.expect_value(t, target.unit, Diff_Unit_ID(1))

	second, second_moved, second_failure := status_selection_move(&observation, first, .Next, &document)
	testing.expectf(t, second_moved, "second diff move failed with %v", second_failure)
	if !second_moved do return
	testing.expect_value(t, second.current.unit, Diff_Unit_ID(2))
	collapsed, collapsed_ok, collapse_failure := status_selection_toggle_expansion(
		&observation,
		second,
		&document,
	)
	testing.expectf(t, collapsed_ok, "diff collapse failed with %v", collapse_failure)
	if collapsed_ok {
		testing.expect_value(t, collapsed.current.kind, Status_Item_Kind.Path)
		testing.expect_value(t, collapsed.expanded, Path_Target{})
	}
}

/* Verifies refresh falls a semantic hunk back to its surviving path. */
@(test)
status_selection_reconcile_does_not_invent_diff_unit_identity :: proc(t: ^testing.T) {
	previous, detail, ready := diff_document_test_detail(DIFF_DOCUMENT_TWO_HUNKS)
	testing.expect(t, ready)
	if !ready do return
	defer status_observation_close(&previous)
	defer path_detail_close(&detail)
	document, opened, _ := diff_document_open(&detail)
	testing.expect(t, opened)
	if !opened do return
	defer diff_document_close(&document)

	selection, _ := status_selection_begin(&previous)
	selection, _, _ = status_selection_move(&previous, selection, .Next)
	selection, _, _ = status_selection_toggle_expansion(&previous, selection)
	selection, _, _ = status_selection_move(&previous, selection, .Next, &document)
	next, next_opened := semantic_test_observation(
		Observation_Generation(42),
		"# branch.head main\x001 .M N... 100644 100644 100644 aaa bbb src/main.odin\x00",
	)
	testing.expect(t, next_opened)
	if !next_opened do return
	defer status_observation_close(&next)
	reconciled, reconciled_ok, reconcile_failure := status_selection_reconcile(
		&previous,
		&next,
		selection,
		&document,
	)
	testing.expectf(t, reconciled_ok, "diff reconciliation failed with %v", reconcile_failure)
	if reconciled_ok {
		testing.expect_value(t, reconciled.current.kind, Status_Item_Kind.Path)
		testing.expect_value(t, reconciled.generation, Observation_Generation(42))
	}
}
