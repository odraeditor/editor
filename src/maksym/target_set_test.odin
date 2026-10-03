// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package maksym

import "../filesystem"
import "core:mem"
import "core:testing"

@(private)
target_set_test_resource :: proc(inode: u64) -> filesystem.Resource_ID {
	return {provider = filesystem.LOCAL_PROVIDER_ID, device = 7, inode = inode}
}

@(test)
/* Verifies ordered membership, current identity, generations, and copied inspection. */
target_set_publishes_copied_ordered_generation :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	allocator := mem.tracking_allocator(&tracking)
	baseline := tracking.current_memory_allocated
	set: Target_Set
	opened, open_failure := target_set_open(
		&set,
		{
			id = Target_Set_ID(17),
			directory_identity = target_set_test_resource(1),
			listing_generation = 11,
			member_limit = 4,
			allocator = allocator,
		},
	)
	testing.expectf(t, opened, "target set open failed: %v", open_failure.code)
	if !opened do return
	members := [2]Target_Set_Member{
		{identity = target_set_test_resource(3)},
		{identity = target_set_test_resource(2)},
	}
	generation, replaced, replace_failure := target_set_replace(
		&set,
		Target_Set_Generation(1),
		11,
		members[:],
		1,
	)
	testing.expectf(t, replaced, "target set replace failed: %v", replace_failure.code)
	testing.expect_value(t, generation, Target_Set_Generation(2))
	snapshot: Target_Set_Snapshot
	inspected, inspect_failure := target_set_inspect(&set, &snapshot)
	testing.expectf(t, inspected, "target set inspect failed: %v", inspect_failure.code)
	if inspected {
		view, viewed, view_failure := target_set_snapshot_view(&snapshot)
		testing.expectf(t, viewed, "target set snapshot failed: %v", view_failure.code)
		if viewed {
			testing.expect_value(t, view.id, Target_Set_ID(17))
			testing.expect_value(t, view.generation, Target_Set_Generation(2))
			testing.expect_value(t, view.listing_generation, u64(11))
			testing.expect_value(t, len(view.members), 2)
			testing.expect_value(t, view.members[0].identity, members[0].identity)
			testing.expect_value(t, view.members[1].identity, members[1].identity)
			testing.expect(t, view.has_current)
			testing.expect_value(t, view.current_index, 1)
		}
		closed, close_failure := target_set_snapshot_close(&snapshot)
		testing.expectf(t, closed, "target set snapshot close failed: %v", close_failure.code)
	}
	closed, close_failure := target_set_close(&set)
	testing.expectf(t, closed, "target set close failed: %v", close_failure.code)
	testing.expect_value(t, tracking.current_memory_allocated, baseline)
}

@(test)
/* Verifies invalid, duplicate, over-limit, and stale replacements preserve authority. */
target_set_rejects_invalid_candidate_generations :: proc(t: ^testing.T) {
	set: Target_Set
	opened, _ := target_set_open(
		&set,
		{
			id = Target_Set_ID(9),
			directory_identity = target_set_test_resource(1),
			listing_generation = 4,
			member_limit = 2,
			allocator = context.allocator,
		},
	)
	testing.expect(t, opened)
	if !opened do return
	defer target_set_close(&set)
	duplicate := [2]Target_Set_Member{
		{identity = target_set_test_resource(2)},
		{identity = target_set_test_resource(2)},
	}
	_, replaced, failure := target_set_replace(
		&set,
		Target_Set_Generation(1),
		4,
		duplicate[:],
		0,
	)
	testing.expect(t, !replaced)
	testing.expect_value(t, failure.code, Failure_Code.Duplicate_Target)
	over_limit := [3]Target_Set_Member{
		{identity = target_set_test_resource(2)},
		{identity = target_set_test_resource(3)},
		{identity = target_set_test_resource(4)},
	}
	_, replaced, failure = target_set_replace(
		&set,
		Target_Set_Generation(1),
		4,
		over_limit[:],
		0,
	)
	testing.expect(t, !replaced)
	testing.expect_value(t, failure.code, Failure_Code.Target_Set_Limit)
	one := [1]Target_Set_Member{{identity = target_set_test_resource(2)}}
	_, replaced, failure = target_set_replace(
		&set,
		Target_Set_Generation(2),
		4,
		one[:],
		0,
	)
	testing.expect(t, !replaced)
	testing.expect_value(t, failure.code, Failure_Code.Stale_Target_Set)
	snapshot: Target_Set_Snapshot
	inspected, _ := target_set_inspect(&set, &snapshot)
	testing.expect(t, inspected)
	if inspected {
		view, _, _ := target_set_snapshot_view(&snapshot)
		testing.expect_value(t, view.generation, Target_Set_Generation(1))
		testing.expect_value(t, len(view.members), 0)
		_, _ = target_set_snapshot_close(&snapshot)
	}
}

@(test)
/* Verifies reconciliation retains ordered survivors and rejects stale listing authority. */
target_set_reconciles_one_checked_newer_listing :: proc(t: ^testing.T) {
	set: Target_Set
	opened, _ := target_set_open(
		&set,
		{
			id = Target_Set_ID(13),
			directory_identity = target_set_test_resource(1),
			listing_generation = 7,
			member_limit = 4,
			allocator = context.allocator,
		},
	)
	testing.expect(t, opened)
	if !opened do return
	defer target_set_close(&set)
	first := target_set_test_resource(2)
	second := target_set_test_resource(3)
	third := target_set_test_resource(4)
	transition, marked, _ := target_set_mark(&set, Target_Set_Generation(1), 7, first)
	testing.expect(t, marked)
	transition, marked, _ = target_set_mark(&set, transition.generation, 7, second)
	testing.expect(t, marked)
	transition, marked, _ = target_set_mark(&set, transition.generation, 7, third)
	testing.expect(t, marked)
	visible := [2]Target_Set_Member{{identity = first}, {identity = third}}
	reconciliation, reconciled, failure := target_set_reconcile(
		&set,
		transition.generation,
		7,
		target_set_test_resource(1),
		8,
		visible[:],
	)
	testing.expectf(t, reconciled, "target set reconcile failed: %v", failure.code)
	testing.expect(t, reconciliation.changed)
	_, marked, failure = target_set_mark(
		&set,
		reconciliation.generation,
		7,
		second,
	)
	testing.expect(t, !marked)
	testing.expect_value(t, failure.code, Failure_Code.Invalid_Generation)
	snapshot: Target_Set_Snapshot
	inspected, _ := target_set_inspect(&set, &snapshot)
	testing.expect(t, inspected)
	if inspected {
		view, _, _ := target_set_snapshot_view(&snapshot)
		testing.expect_value(t, view.listing_generation, u64(8))
		testing.expect_value(t, len(view.members), 2)
		testing.expect_value(t, view.members[0].identity, first)
		testing.expect_value(t, view.members[1].identity, third)
		_, _ = target_set_snapshot_close(&snapshot)
	}
	_, reconciled, failure = target_set_reconcile(
		&set,
		reconciliation.generation,
		7,
		target_set_test_resource(1),
		9,
		visible[:],
	)
	testing.expect(t, !reconciled)
	testing.expect_value(t, failure.code, Failure_Code.Invalid_Generation)
	_, reconciled, failure = target_set_reconcile(
		&set,
		reconciliation.generation,
		8,
		target_set_test_resource(99),
		9,
		visible[:],
	)
	testing.expect(t, !reconciled)
	testing.expect_value(t, failure.code, Failure_Code.Directory_Changed)
}

@(test)
/* Verifies mark, unmark, inversion, clearing, and bounded marked navigation. */
target_set_edits_membership_and_current_target :: proc(t: ^testing.T) {
	set: Target_Set
	opened, _ := target_set_open(
		&set,
		{
			id = Target_Set_ID(11),
			directory_identity = target_set_test_resource(1),
			listing_generation = 1,
			member_limit = 4,
			allocator = context.allocator,
		},
	)
	testing.expect(t, opened)
	if !opened do return
	defer target_set_close(&set)
	first := target_set_test_resource(2)
	second := target_set_test_resource(3)
	third := target_set_test_resource(4)
	transition, marked, _ := target_set_mark(
		&set, Target_Set_Generation(1), 1, first,
	)
	testing.expect(t, marked && transition.changed)
	transition, marked, _ = target_set_mark(&set, transition.generation, 1, third)
	testing.expect(t, marked && transition.changed)
	movement, moved, _ := target_set_move_current(&set, transition.generation, -1)
	testing.expect(t, moved && movement.changed)
	testing.expect_value(t, movement.identity, first)
	unmark_transition, unmarked, _ := target_set_unmark(&set, movement.generation, 1, first)
	testing.expect(t, unmarked && unmark_transition.changed)
	visible := [3]Target_Set_Member{
		{identity = first},
		{identity = second},
		{identity = third},
	}
	invert_transition, inverted, _ := target_set_invert(
		&set, unmark_transition.generation, 1, visible[:],
	)
	testing.expect(t, inverted && invert_transition.changed)
	snapshot: Target_Set_Snapshot
	inspected, _ := target_set_inspect(&set, &snapshot)
	testing.expect(t, inspected)
	if inspected {
		view, _, _ := target_set_snapshot_view(&snapshot)
		testing.expect_value(t, len(view.members), 2)
		testing.expect_value(t, view.members[0].identity, first)
		testing.expect_value(t, view.members[1].identity, second)
		_, _ = target_set_snapshot_close(&snapshot)
	}
	clear_transition, cleared, _ := target_set_clear(&set, invert_transition.generation, 1)
	testing.expect(t, cleared && clear_transition.changed)
	contains, checked, _ := target_set_contains(&set, clear_transition.generation, second)
	testing.expect(t, checked && !contains)
}
