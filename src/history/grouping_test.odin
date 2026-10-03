// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package history

import "../editor"
import editor_view "../view"
import "base:runtime"
import "core:mem"
import "core:testing"

/* Verifies adjacent insertion and local Backspace records remain one bounded undo unit. */
@(test)
typing_group_coalesces_adjacent_insertions :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	allocator := mem.tracking_allocator(&tracking)
	store := grouping_test_store(t, allocator, Store_ID(20), editor.Buffer_ID(20))
	if !store_is_valid(&store) {
		return
	}

	grouping_test_commit(t, &store, 1, 0, 0, "a", "", typing_context(.Typing_Insert, 1, 100))
	grouping_test_commit(t, &store, 2, 1, 1, "界", "", typing_context(.Typing_Insert, 2, 200))
	grouping_test_commit(t, &store, 3, 1, 4, "", "界", typing_context(.Typing_Backspace, 3, 300))

	stats, stats_ok, _ := store_stats(&store)
	testing.expect(t, stats_ok)
	testing.expect_value(t, stats.usage.retained_nodes, u64(2))
	testing.expect_value(t, stats.usage.retained_records, u64(3))
	testing.expect_value(t, stats.active_record_count, u64(3))
	testing.expect_value(t, stats.active_grouping_kind, Grouping_Kind.Typing_Insert)

	undo, preliminary, prepared, _ := navigation_prepare(
		&store,
		Navigation_Request {
			kind = .Undo,
			buffer_id = editor.Buffer_ID(20),
			current_revision = editor.Revision(3),
		},
	)
	testing.expect(t, prepared && preliminary.outcome == .Applied)
	testing.expect_value(t, len(undo.edits), 3)
	if len(undo.edits) == 3 {
		testing.expect_value(t, undo.edits[0].replacement, "界")
		testing.expect_value(t, undo.edits[1].replacement, "")
		testing.expect_value(t, undo.edits[2].replacement, "")
	}
	navigation_abort(&undo)

	store_close(&store)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
}

/* Verifies semantic context, command sequence, elapsed time, and record ceilings split units. */
@(test)
typing_group_breaks_at_non_text_boundaries :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	allocator := mem.tracking_allocator(&tracking)
	policy := DEFAULT_POLICY
	policy.records_per_unit = 2
	policy.multibuffer_participants = 1
	store: Store
	initialized, _ := store_init(
		&store,
		Store_ID(21),
		editor.Buffer_ID(21),
		editor.Revision(0),
		Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
		policy,
	)
	testing.expect(t, initialized)
	if !initialized {
		return
	}

	grouping_test_commit(t, &store, 1, 0, 0, "a", "", typing_context(.Typing_Insert, 1, 100))
	grouping_test_commit(t, &store, 2, 1, 1, "b", "", typing_context(.Typing_Insert, 2, 200))
	grouping_test_commit(t, &store, 3, 2, 2, "c", "", typing_context(.Typing_Insert, 3, 300))
	stats, _, _ := store_stats(&store)
	testing.expect_value(t, stats.usage.retained_nodes, u64(3))

	view_break := typing_context(.Typing_Insert, 4, 400)
	view_break.view_id = editor_view.View_ID(2)
	grouping_test_commit(t, &store, 4, 3, 3, "d", "", view_break)
	sequence_break := typing_context(.Typing_Insert, 6, 500)
	grouping_test_commit(t, &store, 5, 4, 4, "e", "", sequence_break)
	continuity_break := typing_context(.Typing_Insert, 7, 600)
	continuity_break.continuity = 2
	grouping_test_commit(t, &store, 6, 5, 5, "f", "", continuity_break)
	time_break := typing_context(.Typing_Insert, 8, 600 + DEFAULT_TYPING_GROUP_IDLE_MILLISECONDS + 1)
	time_break.continuity = 2
	grouping_test_commit(t, &store, 7, 6, 6, "g", "", time_break)
	stats, _, _ = store_stats(&store)
	testing.expect_value(t, stats.usage.retained_nodes, u64(7))
	testing.expect_value(t, stats.usage.retained_records, u64(7))

	store_close(&store)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
}

/* Verifies aggregate retained payload ends a typing unit before its byte ceiling is crossed. */
@(test)
typing_group_breaks_before_payload_limit :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	allocator := mem.tracking_allocator(&tracking)
	policy := DEFAULT_POLICY
	policy.payload_bytes_per_unit = MIN_PAYLOAD_BYTES_PER_UNIT
	store: Store
	initialized, _ := store_init(
		&store,
		Store_ID(23),
		editor.Buffer_ID(23),
		editor.Revision(0),
		Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
		policy,
	)
	testing.expect(t, initialized)
	if !initialized {
		return
	}
	payload := make([]byte, 40 * 1024)
	defer delete(payload)
	for &value in payload {
		value = 'x'
	}
	text := string(payload)
	grouping_test_commit(t, &store, 1, 0, 0, text, "", typing_context(.Typing_Insert, 1, 10))
	grouping_test_commit(t, &store, 2, u64(len(text)), u64(len(text)), text, "", typing_context(.Typing_Insert, 2, 20))
	stats, _, _ := store_stats(&store)
	testing.expect_value(t, stats.usage.retained_nodes, u64(3))
	testing.expect_value(t, stats.usage.retained_records, u64(2))
	testing.expect_value(t, stats.active_record_count, u64(1))

	store_close(&store)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
}

/* Verifies Backspace stops at preexisting text and forward or explicit edits never join typing. */
@(test)
typing_group_excludes_unrelated_deletions :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	allocator := mem.tracking_allocator(&tracking)
	store := grouping_test_store(t, allocator, Store_ID(22), editor.Buffer_ID(22))
	if !store_is_valid(&store) {
		return
	}

	grouping_test_commit(t, &store, 1, 5, 5, "x", "", typing_context(.Typing_Insert, 1, 10))
	grouping_test_commit(t, &store, 2, 5, 6, "", "x", typing_context(.Typing_Backspace, 2, 20))
	grouping_test_commit(t, &store, 3, 4, 5, "", "p", typing_context(.Typing_Backspace, 3, 30))
	grouping_test_commit(t, &store, 4, 4, 5, "", "q", Grouping_Context{kind = .Independent})
	stats, _, _ := store_stats(&store)
	testing.expect_value(t, stats.usage.retained_nodes, u64(4))
	testing.expect_value(t, stats.usage.retained_records, u64(4))
	testing.expect_value(t, stats.active_grouping_kind, Grouping_Kind.Invalid)

	store_close(&store)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
}

/* Verifies programmable commands cannot claim the built-in typing coalescence channel. */
@(test)
typing_group_rejects_non_builtin_origin :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	allocator := mem.tracking_allocator(&tracking)
	store := grouping_test_store(t, allocator, Store_ID(24), editor.Buffer_ID(24))
	if !store_is_valid(&store) {
		return
	}
	grouping_test_commit(t, &store, 1, 0, 0, "a", "", typing_context(.Typing_Insert, 1, 10))
	edit := [1]Edit_Payload {{
		start = editor.Byte_Offset(1),
		end = editor.Byte_Offset(1),
		replacement_text = "b",
	}}
	reservation: Reservation
	reserved, failure := record_reserve(&store, &reservation, Record_Input {
		source_transaction_id = Source_Transaction_ID(2),
		source_undo_unit_id = Source_Undo_Unit_ID(2),
		buffer_id = editor.Buffer_ID(24),
		base_revision = editor.Revision(1),
		result_revision = editor.Revision(2),
		edits = edit[:],
		origin = .Racket,
		origin_descriptor = "racket-command",
		command = "extension-insert",
		grouping = typing_context(.Typing_Insert, 2, 20),
	})
	testing.expect(t, !reserved)
	testing.expect_value(t, failure.code, Failure_Code.Invalid_State)
	stats, _, _ := store_stats(&store)
	testing.expect_value(t, stats.usage.retained_nodes, u64(2))
	testing.expect_value(t, stats.usage.retained_records, u64(1))

	store_close(&store)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
}

@(private = "file")
typing_context :: proc(kind: Grouping_Kind, sequence, milliseconds: u64) -> Grouping_Context {
	return Grouping_Context {
		kind = kind,
		view_id = editor_view.View_ID(1),
		view_generation = 1,
		continuity = 1,
		event_sequence = sequence,
		monotonic_milliseconds = milliseconds,
	}
}

@(private = "file")
grouping_test_store :: proc(
	t: ^testing.T,
	allocator: runtime.Allocator,
	store_id: Store_ID,
	buffer_id: editor.Buffer_ID,
) -> Store {
	store: Store
	initialized, init_failure := store_init(
		&store,
		store_id,
		buffer_id,
		editor.Revision(0),
		Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, initialized)
	testing.expect_value(t, init_failure.code, Failure_Code.None)
	return store
}

@(private = "file")
grouping_test_commit :: proc(
	t: ^testing.T,
	store: ^Store,
	identity, start, end: u64,
	replacement, removed: string,
	grouping: Grouping_Context,
) {
	edit := [1]Edit_Payload {{
		start = editor.Byte_Offset(start),
		end = editor.Byte_Offset(end),
		replacement_text = replacement,
		removed_text = removed,
	}}
	reservation: Reservation
	reserved, reserve_failure := record_reserve(store, &reservation, Record_Input {
		source_transaction_id = Source_Transaction_ID(identity),
		source_undo_unit_id = Source_Undo_Unit_ID(identity),
		buffer_id = (^Store_State)(store.state).buffer_id,
		base_revision = editor.Revision(identity - 1),
		result_revision = editor.Revision(identity),
		edits = edit[:],
		origin = .Built_In,
		origin_descriptor = "native-command",
		command = "typing-test",
		grouping = grouping,
	})
	testing.expect(t, reserved)
	testing.expect_value(t, reserve_failure.code, Failure_Code.None)
	if reserved {
		reservation_commit_reserved(&reservation, editor.Revision(identity))
	}
}
