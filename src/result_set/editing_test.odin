// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package result_set

import "../editor"
import "../history"
import edit_transaction "../transaction"
import "base:runtime"
import "core:mem"
import "core:testing"

/* Ensures staged result edits remain protected and apply as one undo unit. */
@(test)
editable_results_stage_protect :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	allocator := mem.tracking_allocator(&tracking)
	buffer := edit_test_buffer(t, allocator, 41, "alpha beta")
	store := edit_test_history(t, allocator, 41)
	locations := []Location {{id = 1, buffer_id = 41, revision = 0, start = 0, end = 5}}
	projection: Edit_Projection
	opened, _ := edit_projection_begin(&projection,
		View{set_id = 1, generation = 1, edit_capability = .Single_Buffer, locations = locations}, allocator)
	testing.expect(t, opened)
	staged, _ := edit_projection_stage(&projection, 1, "ALPHA")
	testing.expect(t, staged)
	_, protected_failure := edit_projection_close(&projection)
	testing.expect_value(t, protected_failure.code, Failure_Code.Invalid_Publication)
	result, applied, apply_failure := edit_projection_apply(&projection,
		[]Edit_Target{{buffer = &buffer, history = &store}}, 71, 71,
		edit_transaction.Allocator_Set{persistent = allocator, temporary = context.temp_allocator})
	testing.expectf(t, applied, "result edit apply failed with %v", apply_failure.code)
	testing.expect_value(t, result.proposal_count, u32(1))
	testing.expect_value(t, edit_test_text(t, &buffer), "ALPHA beta")
	close_ready, close_failure := history.store_close_ready(&store)
	testing.expectf(t, close_ready, "single-buffer result history blocks close with %v", close_failure.code)
	closed, _ := edit_projection_close(&projection)
	testing.expect(t, closed)
	history.multibuffer_stores_close([]^history.Store{&store})
	editor.buffer_close(&buffer)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
}

/* Ensures stale targets abort a multi-buffer result edit before any publication. */
@(test)
stale_target_blocks_all_result_edits :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	allocator := mem.tracking_allocator(&tracking)
	first := edit_test_buffer(t, allocator, 51, "one")
	second := edit_test_buffer(t, allocator, 52, "two")
	first_store := edit_test_history(t, allocator, 51)
	second_store := edit_test_history(t, allocator, 52)
	locations := []Location {
		{id = 1, buffer_id = 51, revision = 0, start = 0, end = 3},
		{id = 2, buffer_id = 52, revision = 9, start = 0, end = 3},
	}
	projection: Edit_Projection
	edit_projection_begin(&projection,
		View{set_id = 2, generation = 1, edit_capability = .Multiple_Buffers, locations = locations}, allocator)
	edit_projection_stage(&projection, 1, "ONE")
	edit_projection_stage(&projection, 2, "TWO")
	_, applied, failure := edit_projection_apply(&projection,
		[]Edit_Target{{buffer = &first, history = &first_store},
			{buffer = &second, history = &second_store}}, 81, 81,
		edit_transaction.Allocator_Set{persistent = allocator, temporary = context.temp_allocator})
	testing.expect(t, !applied)
	testing.expect_value(t, failure.code, edit_transaction.Failure_Code.Stale_Revision)
	testing.expect_value(t, edit_test_text(t, &first), "one")
	testing.expect_value(t, edit_test_text(t, &second), "two")
	edit_projection_close(&projection, true)
	history.multibuffer_stores_close([]^history.Store{&first_store, &second_store})
	editor.buffer_close(&second)
	editor.buffer_close(&first)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
}

@(private)
edit_test_buffer :: proc(t: ^testing.T, allocator: runtime.Allocator, id: editor.Buffer_ID, text: string) -> editor.Buffer {
	buffer: editor.Buffer
	initialized, failure := editor.buffer_init(&buffer, id, text,
		editor.Allocator_Set{persistent = allocator, temporary = context.temp_allocator})
	testing.expectf(t, initialized, "buffer init failed with %v", failure.code)
	return buffer
}

@(private)
edit_test_history :: proc(t: ^testing.T, allocator: runtime.Allocator, id: u64) -> history.Store {
	store: history.Store
	initialized, failure := history.store_init(&store, history.Store_ID(id), editor.Buffer_ID(id), 0,
		history.Allocator_Set{persistent = allocator, temporary = context.temp_allocator})
	testing.expectf(t, initialized, "history init failed with %v", failure.code)
	return store
}

@(private)
edit_test_text :: proc(t: ^testing.T, buffer: ^editor.Buffer) -> string {
	stats, stats_ok, _ := editor.buffer_stats(buffer)
	testing.expect(t, stats_ok)
	storage, allocation_error := make([]u8, int(stats.text_bytes), context.temp_allocator)
	testing.expect(t, allocation_error == nil)
	if allocation_error != nil do return ""
	snapshot: editor.Buffer_Snapshot
	opened, _ := editor.buffer_snapshot_open(buffer, &snapshot)
	testing.expect(t, opened)
	if opened {
		_, read_ok, _ := editor.buffer_snapshot_read(&snapshot, 0, storage)
		testing.expect(t, read_ok)
		editor.buffer_snapshot_close(&snapshot)
	}
	return string(storage)
}
