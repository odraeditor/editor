// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package transaction

import "../editor"
import "../history"
import editor_view "../view"
import "core:mem"
import "core:testing"

/* Verifies tracked commits undo, redo, create branches, and publish fresh revisions. */
@(test)
transactions_navigate_reversible_branches :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	buffer := test_buffer_open(t, &tracking, editor.Buffer_ID(701), "abc")
	if !editor.buffer_is_live(&buffer) {
		return
	}
	allocator := mem.tracking_allocator(&tracking)
	store: history.Store
	store_ok, store_failure := history.store_init(
		&store,
		history.Store_ID(1),
		editor.Buffer_ID(701),
		editor.Revision(0),
		history.Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, store_ok)
	testing.expect_value(t, store_failure.code, history.Failure_Code.None)
	if !store_ok {
		editor.buffer_close(&buffer)
		return
	}

	first_ok := commit_tracked_test_edit(t, &buffer, &store, &tracking, 1, 1, 2, "X")
	testing.expect(t, first_ok)
	expect_confirmed_text(t, &buffer, editor.Revision(1), "aXc")
	second_ok := commit_tracked_test_edit(t, &buffer, &store, &tracking, 2, 3, 3, "Y")
	testing.expect(t, second_ok)
	expect_confirmed_text(t, &buffer, editor.Revision(2), "aXcY")

	allocators := Allocator_Set{persistent = allocator, temporary = context.temp_allocator}
	undo_result, undo_ok, undo_failure := transaction_history_navigate(
		&store,
		&buffer,
		.Undo,
		Transaction_ID(100),
		Undo_Unit_ID(100),
		allocators,
	)
	testing.expect(t, undo_ok)
	testing.expect_value(t, undo_failure.code, Failure_Code.None)
	testing.expect_value(t, undo_result.result_revision, editor.Revision(3))
	expect_confirmed_text(t, &buffer, editor.Revision(3), "aXc")

	redo_result, redo_ok, redo_failure := transaction_history_navigate(
		&store,
		&buffer,
		.Redo,
		Transaction_ID(101),
		Undo_Unit_ID(101),
		allocators,
	)
	testing.expect(t, redo_ok)
	testing.expect_value(t, redo_failure.code, Failure_Code.None)
	testing.expect_value(t, redo_result.result_revision, editor.Revision(4))
	expect_confirmed_text(t, &buffer, editor.Revision(4), "aXcY")

	_, undo_ok, _ = transaction_history_navigate(
		&store,
		&buffer,
		.Undo,
		Transaction_ID(102),
		Undo_Unit_ID(102),
		allocators,
	)
	testing.expect(t, undo_ok)
	expect_confirmed_text(t, &buffer, editor.Revision(5), "aXc")
	branch_ok := commit_tracked_test_edit(t, &buffer, &store, &tracking, 3, 1, 2, "Z")
	testing.expect(t, branch_ok)
	expect_confirmed_text(t, &buffer, editor.Revision(6), "aZc")

	_, undo_ok, _ = transaction_history_navigate(
		&store,
		&buffer,
		.Undo,
		Transaction_ID(103),
		Undo_Unit_ID(103),
		allocators,
	)
	testing.expect(t, undo_ok)
	expect_confirmed_text(t, &buffer, editor.Revision(7), "aXc")
	branch_stats, stats_ok, _ := history.store_stats(&store)
	testing.expect(t, stats_ok)
	testing.expect_value(t, branch_stats.active_child_count, u64(2))
	testing.expect_value(t, branch_stats.usage.retained_nodes, u64(4))

	_, redo_ok, _ = transaction_history_navigate(
		&store,
		&buffer,
		.Redo,
		Transaction_ID(104),
		Undo_Unit_ID(104),
		allocators,
	)
	testing.expect(t, redo_ok)
	expect_confirmed_text(t, &buffer, editor.Revision(8), "aZc")

	history.store_close(&store)
	editor.buffer_close(&buffer)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
}

/* Verifies one semantic typing unit undoes and redoes all atomic records in sequence. */
@(test)
grouped_typing_navigates_as_one_fresh_revision :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	allocator := mem.tracking_allocator(&tracking)
	buffer := test_buffer_open(t, &tracking, editor.Buffer_ID(706), "")
	store: history.Store
	store_ok, _ := history.store_init(
		&store,
		history.Store_ID(6),
		editor.Buffer_ID(706),
		editor.Revision(0),
		history.Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, store_ok)
	if !store_ok {
		editor.buffer_close(&buffer)
		return
	}

	letters := [3]string{"a", "b", "c"}
	for letter, index in letters {
		identity := u64(index + 1)
		root := test_transaction_begin(t, &buffer, &tracking, Transaction_ID(identity))
		position, position_ok, _ := editor.buffer_position(&buffer, editor.Byte_Offset(index))
		testing.expect(t, position_ok)
		applied, _ := transaction_apply_batch(
			&root,
			[]Base_Splice{{start = position, end = position, replacement = letter}},
		)
		tracked, _ := transaction_track_history(
			&root,
			&store,
			history.Grouping_Context {
				kind = .Typing_Insert,
				view_id = editor_view.View_ID(1),
				view_generation = 1,
				continuity = 1,
				event_sequence = identity,
				monotonic_milliseconds = identity * 10,
			},
		)
		validated, _ := transaction_validate(&root)
		_, committed, _ := transaction_commit(&root)
		closed, _ := transaction_close(&root)
		testing.expect(t, applied && tracked && validated && committed && closed)
	}
	expect_confirmed_text(t, &buffer, editor.Revision(3), "abc")
	stats, _, _ := history.store_stats(&store)
	testing.expect_value(t, stats.usage.retained_nodes, u64(2))
	testing.expect_value(t, stats.usage.retained_records, u64(3))

	allocators := Allocator_Set{persistent = allocator, temporary = context.temp_allocator}
	undo, undo_ok, _ := transaction_history_navigate(
		&store,
		&buffer,
		.Undo,
		Transaction_ID(700),
		Undo_Unit_ID(700),
		allocators,
	)
	testing.expect(t, undo_ok)
	testing.expect_value(t, undo.result_revision, editor.Revision(4))
	expect_confirmed_text(t, &buffer, editor.Revision(4), "")
	redo, redo_ok, _ := transaction_history_navigate(
		&store,
		&buffer,
		.Redo,
		Transaction_ID(701),
		Undo_Unit_ID(701),
		allocators,
	)
	testing.expect(t, redo_ok)
	testing.expect_value(t, redo.result_revision, editor.Revision(5))
	expect_confirmed_text(t, &buffer, editor.Revision(5), "abc")

	history.store_close(&store)
	editor.buffer_close(&buffer)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
}

/* Verifies history reservation failure aborts before canonical text publication. */
@(test)
history_capacity_failure_keeps_confirmed_text :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	allocator := mem.tracking_allocator(&tracking)
	contents := make([]byte, 600 * 1024)
	replacement := make([]byte, 600 * 1024)
	defer delete(replacement)
	defer delete(contents)
	for index in 0 ..< len(contents) {
		contents[index] = 'a'
		replacement[index] = 'b'
	}
	buffer := test_buffer_open(t, &tracking, editor.Buffer_ID(702), string(contents))
	if !editor.buffer_is_live(&buffer) {
		return
	}
	policy := history.DEFAULT_POLICY
	policy.buffer_retained_bytes = history.MIN_BUFFER_RETAINED_BYTES
	store: history.Store
	store_ok, _ := history.store_init(
		&store,
		history.Store_ID(2),
		editor.Buffer_ID(702),
		editor.Revision(0),
		history.Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
		policy,
	)
	testing.expect(t, store_ok)
	root := test_transaction_begin(t, &buffer, &tracking, Transaction_ID(200))
	start, _, _ := editor.buffer_position(&buffer, editor.Byte_Offset(0))
	end, _, _ := editor.buffer_position(&buffer, editor.Byte_Offset(len(contents)))
	applied, _ := transaction_apply_batch(
		&root,
		[]Base_Splice {{start = start, end = end, replacement = string(replacement)}},
	)
	testing.expect(t, applied)
	tracked, _ := transaction_track_history(&root, &store)
	testing.expect(t, tracked)
	validated, validation_failure := transaction_validate(&root)
	testing.expect(t, !validated)
	testing.expect_value(t, validation_failure.code, Failure_Code.History_Failure)
	testing.expect_value(t, validation_failure.history_failure.code, history.Failure_Code.Retained_Bytes_Limit)
	expect_confirmed_text(t, &buffer, editor.Revision(0), string(contents))
	store_stats, _, _ := history.store_stats(&store)
	testing.expect_value(t, store_stats.usage.retained_nodes, u64(1))

	transaction_close(&root)
	history.store_close(&store)
	editor.buffer_close(&buffer)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
}

/* Verifies a tracked no-op keeps revision agreement without creating an undo node. */
@(test)
tracked_noop_advances_only_confirmed_revision :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	allocator := mem.tracking_allocator(&tracking)
	buffer := test_buffer_open(t, &tracking, editor.Buffer_ID(703), "abc")
	store: history.Store
	store_ok, _ := history.store_init(
		&store,
		history.Store_ID(3),
		editor.Buffer_ID(703),
		editor.Revision(0),
		history.Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, store_ok)
	root := test_transaction_begin(t, &buffer, &tracking, Transaction_ID(300))
	tracked, _ := transaction_track_history(&root, &store)
	validated, _ := transaction_validate(&root)
	result, committed, _ := transaction_commit(&root)
	testing.expect(t, tracked && validated && committed)
	testing.expect_value(t, result.result_revision, editor.Revision(1))
	store_stats, stats_ok, _ := history.store_stats(&store)
	testing.expect(t, stats_ok)
	testing.expect_value(t, store_stats.current_revision, editor.Revision(1))
	testing.expect_value(t, store_stats.usage.retained_nodes, u64(1))
	testing.expect_value(t, store_stats.usage.retained_records, u64(0))

	transaction_close(&root)
	history.store_close(&store)
	editor.buffer_close(&buffer)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
}

/* Verifies cancellation and stale attachment cannot create a history record. */
@(test)
cancelled_and_stale_tracking_keep_history_root :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	allocator := mem.tracking_allocator(&tracking)
	buffer := test_buffer_open(t, &tracking, editor.Buffer_ID(704), "abc")
	store: history.Store
	store_ok, _ := history.store_init(
		&store,
		history.Store_ID(4),
		editor.Buffer_ID(704),
		editor.Revision(0),
		history.Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, store_ok)

	cancelled := test_transaction_begin(t, &buffer, &tracking, Transaction_ID(400))
	start, _, _ := editor.buffer_position(&buffer, editor.Byte_Offset(1))
	transaction_apply_batch(
		&cancelled,
		[]Base_Splice {{start = start, end = start, replacement = "X"}},
	)
	tracked, _ := transaction_track_history(&cancelled, &store)
	testing.expect(t, tracked)
	transaction_request_cancel(&cancelled)
	validated, validation_failure := transaction_validate(&cancelled)
	testing.expect(t, !validated)
	testing.expect_value(t, validation_failure.code, Failure_Code.Cancelled)
	transaction_close(&cancelled)
	root_stats, _, _ := history.store_stats(&store)
	testing.expect_value(t, root_stats.usage.retained_nodes, u64(1))

	untracked := test_transaction_begin(t, &buffer, &tracking, Transaction_ID(401))
	position, _, _ := editor.buffer_position(&buffer, editor.Byte_Offset(3))
	transaction_apply_batch(
		&untracked,
		[]Base_Splice {{start = position, end = position, replacement = "Y"}},
	)
	transaction_validate(&untracked)
	transaction_commit(&untracked)
	transaction_close(&untracked)
	expect_confirmed_text(t, &buffer, editor.Revision(1), "abcY")

	stale := test_transaction_begin(t, &buffer, &tracking, Transaction_ID(402))
	stale_tracked, stale_failure := transaction_track_history(&stale, &store)
	testing.expect(t, !stale_tracked)
	testing.expect_value(t, stale_failure.code, Failure_Code.History_Failure)
	testing.expect_value(t, stale_failure.history_failure.code, history.Failure_Code.Stale_Revision)
	transaction_close(&stale)
	root_stats, _, _ = history.store_stats(&store)
	testing.expect_value(t, root_stats.current_revision, editor.Revision(0))
	testing.expect_value(t, root_stats.usage.retained_nodes, u64(1))

	history.store_close(&store)
	editor.buffer_close(&buffer)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
}

/* Verifies post-commit observer failure cannot erase the required history record. */
@(test)
observer_failure_preserves_committed_history :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	allocator := mem.tracking_allocator(&tracking)
	buffer := test_buffer_open(t, &tracking, editor.Buffer_ID(705), "abc")
	store: history.Store
	store_ok, _ := history.store_init(
		&store,
		history.Store_ID(5),
		editor.Buffer_ID(705),
		editor.Revision(0),
		history.Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, store_ok)
	root := test_transaction_begin(t, &buffer, &tracking, Transaction_ID(500))
	start, _, _ := editor.buffer_position(&buffer, editor.Byte_Offset(1))
	transaction_apply_batch(
		&root,
		[]Base_Splice {{start = start, end = start, replacement = "X"}},
	)
	transaction_track_history(&root, &store)
	transaction_validate(&root)
	result, committed, commit_failure := transaction_commit(
		&root,
		Commit_Observer{procedure = rejecting_history_observer},
	)
	testing.expect(t, committed)
	testing.expect_value(t, commit_failure.code, Failure_Code.None)
	testing.expect_value(t, result.observer_status, Observer_Status.Failed)
	history_stats, _, _ := history.store_stats(&store)
	testing.expect_value(t, history_stats.usage.retained_nodes, u64(2))
	testing.expect_value(t, history_stats.current_revision, editor.Revision(1))

	transaction_close(&root)
	history.store_close(&store)
	editor.buffer_close(&buffer)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
}

@(private = "file")
rejecting_history_observer :: proc(user_data: rawptr, event: Commit_Event) -> bool {
	_ = user_data
	_ = event
	return false
}

@(private = "file")
commit_tracked_test_edit :: proc(
	t: ^testing.T,
	buffer: ^editor.Buffer,
	store: ^history.Store,
	tracking: ^mem.Tracking_Allocator,
	identity: u64,
	start_offset, end_offset: u64,
	replacement: string,
) -> bool {
	root := test_transaction_begin(t, buffer, tracking, Transaction_ID(identity))
	if !transaction_is_valid(&root) {
		return false
	}
	start, start_ok, _ := editor.buffer_position(buffer, editor.Byte_Offset(start_offset))
	end, end_ok, _ := editor.buffer_position(buffer, editor.Byte_Offset(end_offset))
	if !start_ok || !end_ok {
		transaction_close(&root)
		return false
	}
	applied, _ := transaction_apply_batch(
		&root,
		[]Base_Splice {{start = start, end = end, replacement = replacement}},
	)
	tracked, _ := transaction_track_history(&root, store)
	validated, _ := transaction_validate(&root)
	_, committed, _ := transaction_commit(&root)
	closed, _ := transaction_close(&root)
	return applied && tracked && validated && committed && closed
}
