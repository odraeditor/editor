// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package history

import "../editor"
import "core:mem"
import "core:testing"

/* Verifies record reservation, abort, commit, undo, redo, accounting, and teardown. */
@(test)
store_reservations_preserve_exact_topology :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	allocator := mem.tracking_allocator(&tracking)
	store: Store
	initialized, init_failure := store_init(
		&store,
		Store_ID(1),
		editor.Buffer_ID(7),
		editor.Revision(0),
		Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, initialized)
	testing.expect_value(t, init_failure.code, Failure_Code.None)
	if !initialized {
		return
	}

	aborted_reservation: Reservation
	reserved, reserve_failure := test_record_reserve(
		&store,
		&aborted_reservation,
		editor.Buffer_ID(7),
		1,
		editor.Revision(0),
		editor.Revision(1),
		"X",
		"b",
	)
	testing.expect(t, reserved)
	testing.expect_value(t, reserve_failure.code, Failure_Code.None)
	aborted, abort_failure := reservation_abort(&aborted_reservation)
	testing.expect(t, aborted)
	testing.expect_value(t, abort_failure.code, Failure_Code.None)
	after_abort, _, _ := store_stats(&store)
	testing.expect_value(t, after_abort.usage.retained_nodes, u64(1))
	testing.expect_value(t, after_abort.current_revision, editor.Revision(0))

	committed_reservation: Reservation
	reserved, _ = test_record_reserve(
		&store,
		&committed_reservation,
		editor.Buffer_ID(7),
		2,
		editor.Revision(0),
		editor.Revision(1),
		"X",
		"b",
	)
	testing.expect(t, reserved)
	reservation_commit_reserved(&committed_reservation, editor.Revision(1))
	after_commit, _, _ := store_stats(&store)
	testing.expect_value(t, after_commit.usage.retained_nodes, u64(2))
	testing.expect_value(t, after_commit.usage.retained_records, u64(1))
	testing.expect_value(t, after_commit.usage.retained_payload_bytes, u64(2))
	testing.expect_value(t, after_commit.current_revision, editor.Revision(1))

	undo, undo_preliminary, undo_ok, undo_failure := navigation_prepare(
		&store,
		Navigation_Request {
			kind = .Undo,
			buffer_id = editor.Buffer_ID(7),
			current_revision = editor.Revision(1),
		},
	)
	testing.expect(t, undo_ok)
	testing.expect_value(t, undo_failure.code, Failure_Code.None)
	testing.expect_value(t, undo_preliminary.outcome, Navigation_Outcome.Applied)
	testing.expect_value(t, len(undo.edits), 1)
	testing.expect_value(t, undo.edits[0].replacement, "b")
	undo_result := navigation_commit_reserved(&undo, editor.Revision(2))
	testing.expect_value(t, undo_result.outcome, Navigation_Outcome.Applied)

	redo, redo_preliminary, redo_ok, redo_failure := navigation_prepare(
		&store,
		Navigation_Request {
			kind = .Redo,
			buffer_id = editor.Buffer_ID(7),
			current_revision = editor.Revision(2),
		},
	)
	testing.expect(t, redo_ok)
	testing.expect_value(t, redo_failure.code, Failure_Code.None)
	testing.expect_value(t, redo_preliminary.outcome, Navigation_Outcome.Applied)
	testing.expect_value(t, redo.edits[0].replacement, "X")
	redo_result := navigation_commit_reserved(&redo, editor.Revision(3))
	testing.expect_value(t, redo_result.result_revision, editor.Revision(3))

	closed, close_failure := store_close(&store)
	testing.expect(t, closed)
	testing.expect_value(t, close_failure.code, Failure_Code.None)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
}

/* Verifies bounded pruning removes complete inactive leaves and preserves recent activity. */
@(test)
store_pruning_removes_only_old_inactive_units :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	allocator := mem.tracking_allocator(&tracking)
	store: Store
	policy := DEFAULT_POLICY
	policy.guaranteed_recent_units = MIN_RECENT_UNITS
	initialized, _ := store_init(
		&store,
		Store_ID(2),
		editor.Buffer_ID(8),
		editor.Revision(0),
		Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
		policy,
	)
	testing.expect(t, initialized)
	if !initialized {
		return
	}
	revision := editor.Revision(0)
	for index in 0 ..< 40 {
		next_revision := editor.Revision(u64(revision) + 1)
		reservation: Reservation
		reserved, _ := test_record_reserve(
			&store,
			&reservation,
			editor.Buffer_ID(8),
			u64(index + 1),
			revision,
			next_revision,
			"x",
			"",
		)
		testing.expect(t, reserved)
		if !reserved {
			break
		}
		reservation_commit_reserved(&reservation, next_revision)
		revision = next_revision
		undo, preliminary, prepared, _ := navigation_prepare(
			&store,
			Navigation_Request {
				kind = .Undo,
				buffer_id = editor.Buffer_ID(8),
				current_revision = revision,
			},
		)
		testing.expect(t, prepared && preliminary.outcome == .Applied)
		if !prepared || preliminary.outcome != .Applied {
			break
		}
		revision = editor.Revision(u64(revision) + 1)
		navigation_commit_reserved(&undo, revision)
	}
	before, _, _ := store_stats(&store)
	pruned, prune_ok, prune_failure := store_prune(&store, DEFAULT_PRUNING_OPERATIONS)
	testing.expect(t, prune_ok)
	testing.expect_value(t, prune_failure.code, Failure_Code.None)
	testing.expect(t, pruned > 0)
	after, _, _ := store_stats(&store)
	testing.expect_value(t, after.usage.retained_nodes, before.usage.retained_nodes - pruned)
	testing.expect_value(t, after.current_revision, revision)
	testing.expect_value(t, after.active_node, before.active_node)

	store_close(&store)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
}

@(private = "file")
test_record_reserve :: proc(
	store: ^Store,
	reservation: ^Reservation,
	buffer_id: editor.Buffer_ID,
	identity: u64,
	base, result: editor.Revision,
	replacement, removed: string,
) -> (bool, Failure_Context) {
	edits := [1]Edit_Payload {{
		start = editor.Byte_Offset(1),
		end = editor.Byte_Offset(1 + len(removed)),
		replacement_text = replacement,
		removed_text = removed,
	}}
	return record_reserve(store, reservation, Record_Input {
		source_transaction_id = Source_Transaction_ID(identity),
		source_undo_unit_id = Source_Undo_Unit_ID(identity),
		buffer_id = buffer_id,
		base_revision = base,
		result_revision = result,
		edits = edits[:],
		origin = .Built_In,
		origin_descriptor = "test",
		command = "test-edit",
	})
}
