// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package view

import "../editor"
import "core:mem"
import "core:testing"

/* Verifies normalization and independent hidden state for two views of one buffer. */
@(test)
hidden_ranges_are_normalized_and_view_local :: proc(t: ^testing.T) {
	buffer: editor.Buffer
	registry: Registry
	first: View_Handle
	ready := hidden_range_test_context(
		t,
		301,
		"012345678901234567890123456789",
		&buffer,
		&registry,
		&first,
	)
	if !ready do return
	defer hidden_range_test_close(t, &buffer, &registry, &first)
	second, second_ok, _ := clone_additional(&registry, first)
	testing.expect(t, second_ok)
	if !second_ok do return
	defer close(&registry, &second)

	ranges := [4]Hidden_Range {
		hidden_range_test_range(&buffer, 20, 25),
		hidden_range_test_range(&buffer, 2, 8),
		hidden_range_test_range(&buffer, 7, 12),
		hidden_range_test_range(&buffer, 25, 30),
	}
	update, replaced, failure := visibility_replace(&registry, first, ranges[:])
	testing.expectf(t, replaced, "visibility replace failed with %v", failure.code)
	testing.expect_value(t, update.range_count, u32(2))
	testing.expect_value(t, update.generation, Visibility_Generation(1))

	copied: [2]Hidden_Range
	snapshot, copied_ok, copy_failure := visibility_copy_ranges(&registry, first, copied[:])
	testing.expectf(t, copied_ok, "visibility copy failed with %v", copy_failure.code)
	testing.expect_value(t, snapshot.range_count, u32(2))
	testing.expect_value(t, copied[0].start.byte_offset, editor.Byte_Offset(2))
	testing.expect_value(t, copied[0].end.byte_offset, editor.Byte_Offset(12))
	testing.expect_value(t, copied[1].start.byte_offset, editor.Byte_Offset(20))
	testing.expect_value(t, copied[1].end.byte_offset, editor.Byte_Offset(30))

	second_state, second_copy_ok, _ := visibility_copy_ranges(&registry, second, nil)
	testing.expect(t, second_copy_ok)
	testing.expect_value(t, second_state.range_count, u32(0))
}

/* Verifies reveal operations remove only affected ranges and reject stale positions. */
@(test)
hidden_ranges_reveal_checked_source_positions :: proc(t: ^testing.T) {
	buffer: editor.Buffer
	registry: Registry
	handle: View_Handle
	ready := hidden_range_test_context(
		t,
		303,
		"012345678901234567890123456789",
		&buffer,
		&registry,
		&handle,
	)
	if !ready do return
	defer hidden_range_test_close(t, &buffer, &registry, &handle)
	ranges := [3]Hidden_Range {
		hidden_range_test_range(&buffer, 2, 8),
		hidden_range_test_range(&buffer, 12, 20),
		hidden_range_test_range(&buffer, 24, 30),
	}
	_, replaced, _ := visibility_replace(&registry, handle, ranges[:])
	testing.expect(t, replaced)

	inside, _, _ := editor.buffer_position(&buffer, 15)
	hidden, checked, _ := visibility_position_is_hidden(&registry, handle, inside)
	testing.expect(t, checked && hidden)
	point_update, revealed, _ := visibility_reveal_position(&registry, handle, inside)
	testing.expect(t, revealed && point_update.changed)
	testing.expect_value(t, point_update.range_count, u32(2))

	start, _, _ := editor.buffer_position(&buffer, 6)
	end, _, _ := editor.buffer_position(&buffer, 26)
	range_update, range_revealed, _ := visibility_reveal_range(&registry, handle, start, end)
	testing.expect(t, range_revealed && range_update.changed)
	testing.expect_value(t, range_update.range_count, u32(0))

	stale := inside
	point, _, _ := editor.buffer_position(&buffer, 0)
	_, _, published, _ := editor.buffer_splice(
		&buffer,
		editor.Splice{start = point, end = point, replacement = "x"},
		context.temp_allocator,
	)
	testing.expect(t, published)
	_, stale_ok, stale_failure := visibility_reveal_position(&registry, handle, stale)
	testing.expect(t, !stale_ok)
	testing.expect_value(t, stale_failure.code, Failure_Code.Invalid_Hidden_Range)
}

/* Verifies anchors transform retained ranges and collapsed ranges are discarded. */
@(test)
hidden_ranges_follow_buffer_revisions :: proc(t: ^testing.T) {
	buffer: editor.Buffer
	registry: Registry
	handle: View_Handle
	ready := hidden_range_test_context(
		t,
		305,
		"abcdefghij",
		&buffer,
		&registry,
		&handle,
	)
	if !ready do return
	defer hidden_range_test_close(t, &buffer, &registry, &handle)
	ranges := [1]Hidden_Range{hidden_range_test_range(&buffer, 2, 8)}
	_, replaced, _ := visibility_replace(&registry, handle, ranges[:])
	testing.expect(t, replaced)

	insert, _, _ := editor.buffer_position(&buffer, 0)
	_, _, inserted, _ := editor.buffer_splice(
		&buffer,
		editor.Splice{start = insert, end = insert, replacement = "XY"},
		context.temp_allocator,
	)
	testing.expect(t, inserted)
	copied: [1]Hidden_Range
	snapshot, copied_ok, _ := visibility_copy_ranges(&registry, handle, copied[:])
	testing.expect(t, copied_ok)
	testing.expect_value(t, snapshot.source_revision, editor.Revision(1))
	testing.expect_value(t, copied[0].start.byte_offset, editor.Byte_Offset(4))
	testing.expect_value(t, copied[0].end.byte_offset, editor.Byte_Offset(10))

	delete_start, _, _ := editor.buffer_position(&buffer, 4)
	delete_end, _, _ := editor.buffer_position(&buffer, 10)
	_, _, deleted, _ := editor.buffer_splice(
		&buffer,
		editor.Splice{start = delete_start, end = delete_end, replacement = ""},
		context.temp_allocator,
	)
	testing.expect(t, deleted)
	empty, empty_ok, _ := visibility_copy_ranges(&registry, handle, nil)
	testing.expect(t, empty_ok)
	testing.expect_value(t, empty.range_count, u32(0))
}

/* Verifies invalid input, capacity, and destination limits preserve prior state. */
@(test)
hidden_range_limits_reject_without_replacement :: proc(t: ^testing.T) {
	buffer: editor.Buffer
	registry: Registry
	handle: View_Handle
	ready := hidden_range_test_context(
		t,
		306,
		"0123456789",
		&buffer,
		&registry,
		&handle,
	)
	if !ready do return
	defer hidden_range_test_close(t, &buffer, &registry, &handle)
	ranges := [1]Hidden_Range{hidden_range_test_range(&buffer, 2, 8)}
	_, replaced, _ := visibility_replace(&registry, handle, ranges[:])
	testing.expect(t, replaced)

	too_many, too_many_error := make([]Hidden_Range, int(MAX_HIDDEN_RANGES) + 1)
	testing.expect(t, too_many_error == nil)
	if too_many_error == nil {
		defer delete(too_many)
		_, overflow_ok, overflow := visibility_replace(&registry, handle, too_many)
		testing.expect(t, !overflow_ok)
		testing.expect_value(t, overflow.code, Failure_Code.Hidden_Range_Limit)
		testing.expect_value(t, overflow.limit, u64(MAX_HIDDEN_RANGES))
	}

	_, short_ok, short := visibility_copy_ranges(&registry, handle, nil)
	testing.expect(t, !short_ok)
	testing.expect_value(t, short.code, Failure_Code.Hidden_Range_Destination_Limit)
	copied: [1]Hidden_Range
	retained, retained_ok, _ := visibility_copy_ranges(&registry, handle, copied[:])
	testing.expect(t, retained_ok)
	testing.expect_value(t, retained.range_count, u32(1))
}

/* Verifies retained visibility allocation is accounted and released on close. */
@(test)
hidden_range_storage_and_faults_are_contained :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	allocator := mem.tracking_allocator(&tracking)
	buffer: editor.Buffer
	buffer_ok, _ := editor.buffer_init(
		&buffer,
		editor.Buffer_ID(307),
		"0123456789",
		editor.Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, buffer_ok)
	if !buffer_ok do return
	registry: Registry
	registry_ok, _ := registry_init(&registry, Registry_ID(307), allocator)
	handle, view_ok, _ := create(&registry, &buffer)
	testing.expect(t, registry_ok && view_ok)
	if !registry_ok || !view_ok do return

	before, before_ok, _ := registry_stats(&registry)
	ranges := [1]Hidden_Range{hidden_range_test_range(&buffer, 2, 8)}
	_, replaced, _ := visibility_replace(&registry, handle, ranges[:])
	after, after_ok, _ := registry_stats(&registry)
	testing.expect(t, replaced && before_ok && after_ok)
	testing.expect_value(
		t,
		after.storage_bytes - before.storage_bytes,
		u64(size_of(Hidden_Range_State)),
	)

	data := registry_data(&registry)
	failing := Failing_Allocator{backing = allocator, fail_after = 0}
	data.allocator = failing_allocator(&failing)
	second := [1]Hidden_Range{hidden_range_test_range(&buffer, 1, 9)}
	_, failed_ok, failed := visibility_replace(&registry, handle, second[:])
	testing.expect(t, !failed_ok)
	testing.expect_value(t, failed.code, Failure_Code.Persistent_Memory_Limit)
	copied: [1]Hidden_Range
	retained, retained_ok, _ := visibility_copy_ranges(&registry, handle, copied[:])
	testing.expect(t, retained_ok)
	testing.expect_value(t, retained.range_count, u32(1))
	testing.expect_value(t, copied[0].start.byte_offset, editor.Byte_Offset(2))
	data.allocator = allocator

	view_closed, _ := close(&registry, &handle)
	registry_closed, _ := registry_close(&registry)
	buffer_closed, _ := editor.buffer_close(&buffer)
	testing.expect(t, view_closed && registry_closed && buffer_closed)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
}

@(private)
hidden_range_test_context :: proc(
	t: ^testing.T,
	identity: u64,
	contents: string,
	buffer: ^editor.Buffer,
	registry: ^Registry,
	handle: ^View_Handle,
) -> bool {
	buffer_ok, _ := editor.buffer_init(
		buffer,
		editor.Buffer_ID(identity),
		contents,
		editor.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	registry_ok, _ := registry_init(registry, Registry_ID(identity), context.allocator)
	ready := false
	if buffer_ok && registry_ok {
		handle^, ready, _ = create(registry, buffer)
	}
	testing.expect(t, buffer_ok && registry_ok && ready)
	return buffer_ok && registry_ok && ready
}

@(private)
hidden_range_test_range :: proc(buffer: ^editor.Buffer, start, end: u64) -> Hidden_Range {
	start_position, _, _ := editor.buffer_position(buffer, editor.Byte_Offset(start))
	end_position, _, _ := editor.buffer_position(buffer, editor.Byte_Offset(end))
	return Hidden_Range{start = start_position, end = end_position}
}

@(private)
hidden_range_test_close :: proc(
	t: ^testing.T,
	buffer: ^editor.Buffer,
	registry: ^Registry,
	handle: ^View_Handle,
) {
	view_closed, _ := close(registry, handle)
	registry_closed, _ := registry_close(registry)
	buffer_closed, _ := editor.buffer_close(buffer)
	testing.expect(t, view_closed && registry_closed && buffer_closed)
}
