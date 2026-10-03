// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package history

import "../editor"
import "core:mem"
import "core:testing"

/* Verifies copied branch inspection, truncation, selection, and stale-state rejection. */
@(test)
branch_inspection_and_selection_are_bounded :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	allocator := mem.tracking_allocator(&tracking)
	store: Store
	initialized, _ := store_init(
		&store,
		Store_ID(41),
		editor.Buffer_ID(71),
		editor.Revision(0),
		Allocator_Set{persistent = allocator, temporary = allocator},
	)
	testing.expect(t, initialized)
	if !initialized {
		return
	}

	revision := editor.Revision(0)
	branch_test_commit(t, &store, &revision, 1, editor.Byte_Offset(0), "A", "", "branch-a")
	branch_test_commit(t, &store, &revision, 2, editor.Byte_Offset(1), "B", "", "branch-b")
	b_stats, _, _ := store_stats(&store)
	b_node := b_stats.active_node
	branch_test_undo(t, &store, &revision)
	branch_test_commit(t, &store, &revision, 3, editor.Byte_Offset(1), "C", "", "branch-c")
	c_stats, _, _ := store_stats(&store)
	c_node := c_stats.active_node
	branch_test_undo(t, &store, &revision)
	active, _, _ := store_stats(&store)

	inspection, inspected, inspect_failure := store_inspect(
		&store,
		Inspection_Request {
			buffer_id = active.buffer_id,
			current_revision = revision,
			active_node = active.active_node,
			policy_generation = active.policy_generation,
			result_limit = 1,
			traversal_limit = 1,
		},
		allocator,
	)
	testing.expect(t, inspected)
	testing.expect_value(t, inspect_failure.code, Failure_Code.None)
	testing.expect_value(t, inspection.active, active.active_node)
	testing.expect_value(t, inspection.preferred_child, c_node)
	testing.expect_value(t, inspection.active_projection.command, "branch-a")
	testing.expect_value(t, inspection.preferred_projection.command, "branch-c")
	testing.expect(t, inspection.has_parent)
	testing.expect(t, inspection.has_preferred_child)
	testing.expect_value(t, inspection.child_count, u64(2))
	testing.expect_value(t, inspection.traversed_nodes, u64(1))
	testing.expect(t, inspection.truncated)
	testing.expect_value(t, len(inspection.children), 1)
	testing.expect_value(t, inspection.children[0].id, c_node)
	testing.expect_value(t, inspection.children[0].command, "branch-c")
	testing.expect_value(t, inspection.children[0].record_count, u64(1))
	testing.expect_value(t, inspection.children[0].payload_bytes, u64(1))
	inspection_release(&inspection, allocator)
	testing.expect_value(t, len(inspection.children), 0)

	_, stale_ok, stale_failure := store_inspect(
		&store,
		Inspection_Request {
			buffer_id = active.buffer_id,
			current_revision = revision,
			active_node = active.active_node,
			policy_generation = Policy_Generation(u64(active.policy_generation) + 1),
			result_limit = 8,
			traversal_limit = 8,
		},
		allocator,
	)
	testing.expect(t, !stale_ok)
	testing.expect_value(t, stale_failure.code, Failure_Code.Stale_Generation)

	select_b, preliminary, selected, select_failure := navigation_prepare(
		&store,
		Navigation_Request {
			kind = .Select_Branch,
			buffer_id = active.buffer_id,
			current_revision = revision,
			active_node = active.active_node,
			target_node = b_node,
			policy_generation = active.policy_generation,
			analysis_operations = 32,
		},
	)
	testing.expect(t, selected)
	testing.expect_value(t, select_failure.code, Failure_Code.None)
	testing.expect_value(t, preliminary.outcome, Navigation_Outcome.Applied)
	testing.expect_value(t, len(select_b.edits), 1)
	testing.expect_value(t, select_b.edits[0].replacement, "B")
	revision = editor.Revision(u64(revision) + 1)
	selected_b := navigation_commit_reserved(&select_b, revision)
	testing.expect_value(t, selected_b.active_node, b_node)

	current, _, _ := store_stats(&store)
	_, _, exhausted_ok, exhausted_failure := navigation_prepare(
		&store,
		Navigation_Request {
			kind = .Select_Branch,
			buffer_id = current.buffer_id,
			current_revision = revision,
			active_node = current.active_node,
			target_node = c_node,
			policy_generation = current.policy_generation,
			analysis_operations = 1,
		},
	)
	testing.expect(t, !exhausted_ok)
	testing.expect_value(t, exhausted_failure.code, Failure_Code.Work_Limit)
	after_exhaustion, _, _ := store_stats(&store)
	testing.expect_value(t, after_exhaustion.active_node, b_node)
	testing.expect_value(t, after_exhaustion.current_revision, revision)

	select_c, _, selected_again, select_again_failure := navigation_prepare(
		&store,
		Navigation_Request {
			kind = .Select_Branch,
			buffer_id = current.buffer_id,
			current_revision = revision,
			active_node = current.active_node,
			target_node = c_node,
			policy_generation = current.policy_generation,
			analysis_operations = 64,
		},
	)
	testing.expect(t, selected_again)
	testing.expect_value(t, select_again_failure.code, Failure_Code.None)
	testing.expect_value(t, len(select_c.edits), 2)
	testing.expect_value(t, select_c.edits[0].replacement, "")
	testing.expect_value(t, select_c.edits[1].replacement, "C")
	revision = editor.Revision(u64(revision) + 1)
	selected_c := navigation_commit_reserved(&select_c, revision)
	testing.expect_value(t, selected_c.active_node, c_node)

	closed, _ := store_close(&store)
	testing.expect(t, closed)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
}

@(private = "file")
branch_test_commit :: proc(
	t: ^testing.T,
	store: ^Store,
	revision: ^editor.Revision,
	identity: u64,
	start: editor.Byte_Offset,
	replacement, removed, command: string,
) {
	next := editor.Revision(u64(revision^) + 1)
	edits := [1]Edit_Payload {{
		start = start,
		end = editor.Byte_Offset(u64(start) + u64(len(removed))),
		replacement_text = replacement,
		removed_text = removed,
	}}
	reservation: Reservation
	reserved, failure := record_reserve(store, &reservation, Record_Input {
		source_transaction_id = Source_Transaction_ID(identity),
		source_undo_unit_id = Source_Undo_Unit_ID(identity),
		buffer_id = editor.Buffer_ID(71),
		base_revision = revision^,
		result_revision = next,
		edits = edits[:],
		origin = .Built_In,
		origin_descriptor = "branch-test",
		command = command,
	})
	testing.expect(t, reserved)
	testing.expect_value(t, failure.code, Failure_Code.None)
	if reserved {
		reservation_commit_reserved(&reservation, next)
		revision^ = next
	}
}

@(private = "file")
branch_test_undo :: proc(t: ^testing.T, store: ^Store, revision: ^editor.Revision) {
	plan, preliminary, prepared, failure := navigation_prepare(
		store,
		Navigation_Request {
			kind = .Undo,
			buffer_id = editor.Buffer_ID(71),
			current_revision = revision^,
		},
	)
	testing.expect(t, prepared)
	testing.expect_value(t, failure.code, Failure_Code.None)
	testing.expect_value(t, preliminary.outcome, Navigation_Outcome.Applied)
	if prepared && preliminary.outcome == .Applied {
		revision^ = editor.Revision(u64(revision^) + 1)
		navigation_commit_reserved(&plan, revision^)
	}
}
