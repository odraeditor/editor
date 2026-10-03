// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package transaction

import "../editor"
import "../history"
import "core:mem"
import "core:testing"

/* Verifies primary and additional completion edits commit as one undoable unit. */
@(test)
commits_and_navigates_one_history_unit :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	allocator := mem.tracking_allocator(&tracking)
	buffer := test_buffer_open(
		t,
		&tracking,
		editor.Buffer_ID(901),
		"main :: proc() { pri(\"value\") }\n",
	)
	store: history.Store
	store_ok, _ := history.store_init(
		&store,
		history.Store_ID(901),
		editor.Buffer_ID(901),
		editor.Revision(0),
		history.Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, store_ok)
	if !store_ok {
		editor.buffer_close(&buffer)
		return
	}

	root := test_transaction_begin(t, &buffer, &tracking, Transaction_ID(901))
	import_position, import_ok, _ := editor.buffer_position(&buffer, 0)
	primary_start, primary_start_ok, _ := editor.buffer_position(&buffer, 17)
	primary_end, primary_end_ok, _ := editor.buffer_position(&buffer, 20)
	testing.expect(t, import_ok && primary_start_ok && primary_end_ok)
	batch := []Base_Splice {
		{
			start = import_position,
			end = import_position,
			replacement = "import \"core:fmt\"\n\n",
		},
		{start = primary_start, end = primary_end, replacement = "fmt.println"},
	}
	applied, apply_failure := transaction_apply_batch(&root, batch)
	tracked, track_failure := transaction_track_history(&root, &store)
	validated, validation_failure := transaction_validate(&root)
	result, committed, commit_failure := transaction_commit(&root)
	testing.expectf(t, applied, "completion batch failed with %v", apply_failure.code)
	testing.expectf(t, tracked, "completion history failed with %v", track_failure.code)
	testing.expectf(t, validated, "completion validation failed with %v", validation_failure.code)
	testing.expectf(t, committed, "completion commit failed with %v", commit_failure.code)
	testing.expect_value(t, result.undo_unit_id, Undo_Unit_ID(901))
	testing.expect_value(t, len(result.splices), 2)
	expect_confirmed_text(
		t,
		&buffer,
		editor.Revision(1),
		"import \"core:fmt\"\n\nmain :: proc() { fmt.println(\"value\") }\n",
	)
	transaction_close(&root)

	allocators := Allocator_Set{persistent = allocator, temporary = context.temp_allocator}
	_, undo_ok, undo_failure := transaction_history_navigate(
		&store,
		&buffer,
		.Undo,
		Transaction_ID(902),
		Undo_Unit_ID(902),
		allocators,
	)
	testing.expectf(t, undo_ok, "completion undo failed with %v", undo_failure.code)
	expect_confirmed_text(
		t,
		&buffer,
		editor.Revision(2),
		"main :: proc() { pri(\"value\") }\n",
	)
	_, redo_ok, redo_failure := transaction_history_navigate(
		&store,
		&buffer,
		.Redo,
		Transaction_ID(903),
		Undo_Unit_ID(903),
		allocators,
	)
	testing.expectf(t, redo_ok, "completion redo failed with %v", redo_failure.code)
	expect_confirmed_text(
		t,
		&buffer,
		editor.Revision(3),
		"import \"core:fmt\"\n\nmain :: proc() { fmt.println(\"value\") }\n",
	)

	history.store_close(&store)
	editor.buffer_close(&buffer)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
}

/* Verifies overlapping completion edits abort without publishing partial text. */
@(test)
rejects_overlap_and_rolls_back_private_state :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	buffer := test_buffer_open(t, &tracking, editor.Buffer_ID(911), "0123456789")
	root := test_transaction_begin(t, &buffer, &tracking, Transaction_ID(911))
	primary_start, _, _ := editor.buffer_position(&buffer, 3)
	primary_end, _, _ := editor.buffer_position(&buffer, 7)
	additional_start, _, _ := editor.buffer_position(&buffer, 6)
	additional_end, _, _ := editor.buffer_position(&buffer, 8)
	applied, failure := transaction_apply_batch(
		&root,
		[]Base_Splice {
			{start = primary_start, end = primary_end, replacement = "primary"},
			{start = additional_start, end = additional_end, replacement = "extra"},
		},
	)
	testing.expect(t, !applied)
	testing.expect_value(t, failure.code, Failure_Code.Overlapping_Batch)
	expect_confirmed_text(t, &buffer, editor.Revision(0), "0123456789")
	closed, close_failure := transaction_close(&root)
	testing.expectf(t, closed, "completion rollback close failed with %v", close_failure.code)
	expect_confirmed_text(t, &buffer, editor.Revision(0), "0123456789")
	editor.buffer_close(&buffer)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
}

/* Verifies candidate edits bound to an older revision cannot be transformed or retried. */
@(test)
rejects_stale_revision_before_publication :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	buffer := test_buffer_open(t, &tracking, editor.Buffer_ID(921), "pri")
	stale_start, _, _ := editor.buffer_position(&buffer, 0)
	stale_end, _, _ := editor.buffer_position(&buffer, 3)

	intervening := test_transaction_begin(t, &buffer, &tracking, Transaction_ID(921))
	end, _, _ := transaction_position(&intervening, 3)
	_, _ = transaction_splice(
		&intervening,
		editor.Working_Splice{start = end, end = end, replacement = "!"},
	)
	_, _ = transaction_validate(&intervening)
	_, committed, _ := transaction_commit(&intervening)
	testing.expect(t, committed)
	transaction_close(&intervening)

	root := test_transaction_begin(t, &buffer, &tracking, Transaction_ID(922))
	applied, failure := transaction_apply_batch(
		&root,
		[]Base_Splice{{start = stale_start, end = stale_end, replacement = "print"}},
	)
	testing.expect(t, !applied)
	testing.expect_value(t, failure.code, Failure_Code.Stale_Revision)
	expect_confirmed_text(t, &buffer, editor.Revision(1), "pri!")
	transaction_close(&root)
	editor.buffer_close(&buffer)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
}
