// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package kill_ring

import "base:runtime"
import "core:mem"
import "core:testing"

/* Verifies defaults and admitted limits preserve every measured cross-field relationship. */
@(test)
measured_policy_bounds_are_self_consistent :: proc(t: ^testing.T) {
	ok, failure := policy_validate(DEFAULT_POLICY)
	testing.expectf(t, ok, "default policy failed with %v", failure.code)
	invalid := DEFAULT_POLICY
	invalid.entry_bytes = MAX_ENTRY_BYTES
	invalid.temporary_bytes = MIN_TEMPORARY_BYTES
	ok, failure = policy_validate(invalid)
	testing.expect(t, !ok)
	testing.expect_value(t, failure.code, Failure_Code.Policy_Relationship)
	testing.expect_value(t, failure.field, Policy_Field.Temporary_Bytes)
}

/* Verifies reservation, abort, and commit isolate unpublished text and copied inspection. */
@(test)
reservations_publish_whole_entries :: proc(t: ^testing.T) {
	ring, ready := test_ring_init(t, Ring_ID(1), DEFAULT_POLICY)
	if !ready {
		return
	}
	defer ring_close(&ring)
	stats, _, _ := ring_stats(&ring)
	reservation: Reservation
	result, reserved, failure := admission_reserve(
		&ring,
		&reservation,
		Admission_Request {
			expected_generation = stats.generation,
			kind = .Copy,
			text = "alpha",
		},
	)
	testing.expectf(t, reserved, "copy reserve failed with %v", failure.code)
	testing.expect_value(t, result.entry.byte_count, u64(5))
	before, _, _ := ring_stats(&ring)
	testing.expect_value(t, before.usage.retained_entries, u64(0))
	testing.expect(t, before.usage.reserved_bytes > 0)
	aborted, abort_failure := reservation_abort(&reservation)
	testing.expectf(t, aborted, "copy abort failed with %v", abort_failure.code)
	after_abort, _, _ := ring_stats(&ring)
	testing.expect_value(t, after_abort.generation, stats.generation)
	testing.expect_value(t, after_abort.usage.retained_entries, u64(0))

	_, reserved, failure = admission_reserve(
		&ring,
		&reservation,
		Admission_Request {
			expected_generation = after_abort.generation,
			kind = .Copy,
			text = "alpha",
		},
	)
	testing.expectf(t, reserved, "second copy reserve failed with %v", failure.code)
	committed := reservation_commit_reserved(&reservation)
	testing.expect_value(t, committed.entry.byte_count, u64(5))
	after_commit, _, _ := ring_stats(&ring)
	testing.expect_value(t, after_commit.generation, Generation(2))
	testing.expect_value(t, after_commit.usage.retained_entries, u64(1))

	inspection, inspected, inspect_failure := ring_inspect(
		&ring,
		Inspection_Request {
			expected_generation = after_commit.generation,
			entry_limit = 1,
		},
		context.allocator,
	)
	testing.expectf(t, inspected, "inspection failed with %v", inspect_failure.code)
	defer inspection_release(&inspection, context.allocator)
	testing.expect_value(t, len(inspection.entries), 1)
	testing.expect_value(t, inspection.entries[0].id, committed.entry.id)
}

/* Verifies forward appends, backward prepends, and copy always starts a new entry. */
@(test)
kill_context_controls_coalescence :: proc(t: ^testing.T) {
	ring, ready := test_ring_init(t, Ring_ID(2), DEFAULT_POLICY)
	if !ready {
		return
	}
	defer ring_close(&ring)
	first := test_admit(t, &ring, .Kill, "A", Kill_Context {
		sequence_id = 1,
		event_sequence = 1,
		source_buffer_id = 7,
		start = 10,
		end = 11,
		direction = .Forward,
	})
	second := test_admit(t, &ring, .Kill, "B", Kill_Context {
		sequence_id = 1,
		event_sequence = 2,
		source_buffer_id = 7,
		start = 10,
		end = 11,
		direction = .Forward,
	})
	testing.expect_value(t, second.id, first.id)
	test_expect_entry_text(t, &ring, second.id, "AB")

	backward_first := test_admit(t, &ring, .Kill, "B", Kill_Context {
		sequence_id = 2,
		event_sequence = 3,
		source_buffer_id = 7,
		start = 9,
		end = 10,
		direction = .Backward,
	})
	backward_second := test_admit(t, &ring, .Kill, "A", Kill_Context {
		sequence_id = 2,
		event_sequence = 4,
		source_buffer_id = 7,
		start = 8,
		end = 9,
		direction = .Backward,
	})
	testing.expect_value(t, backward_second.id, backward_first.id)
	test_expect_entry_text(t, &ring, backward_second.id, "AB")

	copied := test_admit(t, &ring, .Copy, "copy", {})
	testing.expect(t, copied.id != backward_second.id)
	stats, _, _ := ring_stats(&ring)
	testing.expect_value(t, stats.usage.retained_entries, u64(3))
}

/* Verifies every semantic continuity mismatch starts a complete new kill entry. */
@(test)
incompatible_kill_metadata_breaks_coalescence :: proc(t: ^testing.T) {
	cases := [5]struct {name: string, previous, current: Kill_Context} {
		{
			name = "sequence",
			previous = {sequence_id = 1, event_sequence = 1, source_buffer_id = 1, start = 4, end = 5, direction = .Forward},
			current = {sequence_id = 2, event_sequence = 2, source_buffer_id = 1, start = 4, end = 5, direction = .Forward},
		},
		{
			name = "event gap",
			previous = {sequence_id = 1, event_sequence = 1, source_buffer_id = 1, start = 4, end = 5, direction = .Forward},
			current = {sequence_id = 1, event_sequence = 3, source_buffer_id = 1, start = 4, end = 5, direction = .Forward},
		},
		{
			name = "buffer",
			previous = {sequence_id = 1, event_sequence = 1, source_buffer_id = 1, start = 4, end = 5, direction = .Forward},
			current = {sequence_id = 1, event_sequence = 2, source_buffer_id = 2, start = 4, end = 5, direction = .Forward},
		},
		{
			name = "direction",
			previous = {sequence_id = 1, event_sequence = 1, source_buffer_id = 1, start = 4, end = 5, direction = .Forward},
			current = {sequence_id = 1, event_sequence = 2, source_buffer_id = 1, start = 3, end = 4, direction = .Backward},
		},
		{
			name = "position",
			previous = {sequence_id = 1, event_sequence = 1, source_buffer_id = 1, start = 4, end = 5, direction = .Forward},
			current = {sequence_id = 1, event_sequence = 2, source_buffer_id = 1, start = 5, end = 6, direction = .Forward},
		},
	}
	for fixture, index in cases {
		ring, ready := test_ring_init(t, Ring_ID(20 + index), DEFAULT_POLICY)
		if !ready {
			continue
		}
		first := test_admit(t, &ring, .Kill, "a", fixture.previous)
		second := test_admit(t, &ring, .Kill, "b", fixture.current)
		testing.expectf(t, second.id != first.id, "%s did not break coalescence", fixture.name)
		stats, _, _ := ring_stats(&ring)
		testing.expect_value(t, stats.usage.retained_entries, u64(2))
		ring_close(&ring)
	}
}

/* Verifies oldest-entry eviction is complete and oversize rejection evicts nothing. */
@(test)
bounded_admission_evicts_oldest_entries :: proc(t: ^testing.T) {
	policy := DEFAULT_POLICY
	policy.retained_entries = MIN_RETAINED_ENTRIES
	policy.entry_bytes = MIN_ENTRY_BYTES
	policy.total_bytes = MIN_TOTAL_BYTES
	ring, ready := test_ring_init(t, Ring_ID(3), policy)
	if !ready {
		return
	}
	defer ring_close(&ring)
	oldest := Entry_ID(0)
	for index in 0 ..< int(MIN_RETAINED_ENTRIES) {
		metadata := test_admit(t, &ring, .Copy, "x", {})
		if index == 0 {
			oldest = metadata.id
		}
	}
	newest := test_admit(t, &ring, .Copy, "y", {})
	stats, _, _ := ring_stats(&ring)
	testing.expect_value(t, stats.usage.retained_entries, MIN_RETAINED_ENTRIES)
	testing.expect_value(t, stats.usage.evicted_entries, u64(1))
	testing.expect_value(t, stats.newest, newest.id)

	too_large := make([]byte, int(MIN_ENTRY_BYTES) + 1)
	defer delete(too_large)
	before := stats
	reservation: Reservation
	_, admitted, failure := admission_reserve(
		&ring,
		&reservation,
		Admission_Request {
			expected_generation = before.generation,
			kind = .Copy,
			text = string(too_large),
		},
	)
	testing.expect(t, !admitted)
	testing.expect_value(t, failure.code, Failure_Code.Entry_Bytes_Limit)
	after, _, _ := ring_stats(&ring)
	testing.expect_value(t, after, before)
	_, copied, copy_failure := entry_copy(
		&ring,
		Entry_Copy_Request {
			expected_generation = after.generation,
			entry_id = oldest,
			byte_limit = policy.entry_bytes,
		},
		context.allocator,
	)
	testing.expect(t, !copied)
	testing.expect_value(t, copy_failure.code, Failure_Code.Entry_Not_Found)
}

/* Verifies one valid large candidate may replace every previously retained entry. */
@(test)
valid_admission_can_evict_the_full_previous_ring :: proc(t: ^testing.T) {
	policy := DEFAULT_POLICY
	policy.retained_entries = MIN_RETAINED_ENTRIES
	policy.entry_bytes = MIN_TOTAL_BYTES
	policy.total_bytes = MIN_TOTAL_BYTES
	ring, ready := test_ring_init(t, Ring_ID(30), policy)
	if !ready {
		return
	}
	defer ring_close(&ring)
	small := make([]byte, int(MIN_TOTAL_BYTES / MIN_RETAINED_ENTRIES))
	defer delete(small)
	for _ in 0 ..< int(MIN_RETAINED_ENTRIES) {
		test_admit(t, &ring, .Copy, string(small), {})
	}
	large := make([]byte, int(MIN_TOTAL_BYTES))
	defer delete(large)
	large[0] = 'L'
	metadata := test_admit(t, &ring, .Copy, string(large), {})
	stats, _, _ := ring_stats(&ring)
	testing.expect_value(t, stats.usage.retained_entries, u64(1))
	testing.expect_value(t, stats.usage.retained_text_bytes, MIN_TOTAL_BYTES)
	testing.expect_value(t, stats.usage.evicted_entries, MIN_RETAINED_ENTRIES)
	testing.expect_value(t, stats.newest, metadata.id)
}

/* Verifies rotation preserves ordering and rejects stale generations after admission. */
@(test)
rotation_checks_generation_and_bounds :: proc(t: ^testing.T) {
	ring, ready := test_ring_init(t, Ring_ID(4), DEFAULT_POLICY)
	if !ready {
		return
	}
	defer ring_close(&ring)
	older := test_admit(t, &ring, .Copy, "older", {})
	newest := test_admit(t, &ring, .Copy, "newest", {})
	stats, _, _ := ring_stats(&ring)
	rotated, rotated_ok, failure := rotation_next(
		&ring,
		Rotation_Request {
			expected_generation = stats.generation,
			current_entry = newest.id,
			work_limit = stats.policy.rotation_work,
			byte_limit = stats.policy.entry_bytes,
		},
		context.allocator,
	)
	testing.expectf(t, rotated_ok, "rotation failed with %v", failure.code)
	defer entry_copy_release(&rotated, context.allocator)
	testing.expect_value(t, rotated.metadata.id, older.id)
	testing.expect_value(t, rotated.text, "older")
	after_rotation, _, _ := ring_stats(&ring)
	testing.expect_value(t, after_rotation, stats)

	test_admit(t, &ring, .Copy, "changed", {})
	stale: Entry_Copy
	stale, rotated_ok, failure = rotation_next(
		&ring,
		Rotation_Request {
			expected_generation = stats.generation,
			current_entry = newest.id,
			work_limit = stats.policy.rotation_work,
			byte_limit = stats.policy.entry_bytes,
		},
		context.allocator,
	)
	testing.expect(t, !rotated_ok)
	testing.expect_value(t, failure.code, Failure_Code.Stale_Generation)
	entry_copy_release(&stale, context.allocator)
}

/* Verifies tracked persistent and reservation allocators return to zero after teardown. */
@(test)
tracked_ring_storage_returns_to_zero :: proc(t: ^testing.T) {
	persistent_tracking: mem.Tracking_Allocator
	temporary_tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&persistent_tracking, context.allocator)
	mem.tracking_allocator_init(&temporary_tracking, context.allocator)
	ring: Ring
	initialized, failure := ring_init(
		&ring,
		Ring_ID(5),
		Allocator_Set {
			persistent = mem.tracking_allocator(&persistent_tracking),
			temporary = mem.tracking_allocator(&temporary_tracking),
		},
	)
	testing.expectf(t, initialized, "tracked ring failed with %v", failure.code)
	if !initialized {
		mem.tracking_allocator_destroy(&temporary_tracking)
		mem.tracking_allocator_destroy(&persistent_tracking)
		return
	}
	stats, _, _ := ring_stats(&ring)
	reservation: Reservation
	_, reserved, _ := admission_reserve(
		&ring,
		&reservation,
		Admission_Request {
			expected_generation = stats.generation,
			kind = .Copy,
			text = "reserved",
		},
	)
	testing.expect(t, reserved)
	closed, close_failure := ring_close(&ring)
	testing.expect(t, !closed)
	testing.expect_value(t, close_failure.code, Failure_Code.Pending_Reservation)
	reservation_abort(&reservation)
	closed, close_failure = ring_close(&ring)
	testing.expectf(t, closed, "tracked close failed with %v", close_failure.code)
	testing.expect_value(t, persistent_tracking.current_memory_allocated, i64(0))
	testing.expect_value(t, temporary_tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&temporary_tracking)
	mem.tracking_allocator_destroy(&persistent_tracking)
}

/* Verifies reservation allocator failures preserve exact canonical ordering and accounting. */
@(test)
admission_alloc_faults_publish_nothing :: proc(t: ^testing.T) {
	ring, ready := test_ring_init(t, Ring_ID(6), DEFAULT_POLICY)
	if !ready {
		return
	}
	defer ring_close(&ring)
	test_admit(t, &ring, .Copy, "stable", {})
	before, _, _ := ring_stats(&ring)
	state := (^Ring_State)(ring.state)
	original_persistent := state.allocator
	failing := Ring_Failing_Allocator{backing = original_persistent, fail_after = 0}
	state.allocator = ring_failing_allocator(&failing)
	reservation: Reservation
	_, reserved, failure := admission_reserve(
		&ring,
		&reservation,
		Admission_Request {
			expected_generation = before.generation,
			kind = .Copy,
			text = "rejected",
		},
	)
	state.allocator = original_persistent
	testing.expect(t, !reserved)
	testing.expect_value(t, failure.code, Failure_Code.Persistent_Memory_Limit)
	after, _, _ := ring_stats(&ring)
	testing.expect_value(t, after, before)
	testing.expect(t, reservation.state == nil)

	original_temporary := state.temporary_allocator
	state.temporary_allocator = runtime.nil_allocator()
	_, reserved, failure = admission_reserve(
		&ring,
		&reservation,
		Admission_Request {
			expected_generation = before.generation,
			kind = .Copy,
			text = "rejected",
		},
	)
	state.temporary_allocator = original_temporary
	testing.expect(t, !reserved)
	testing.expect_value(t, failure.code, Failure_Code.Temporary_Memory_Limit)
	after, _, _ = ring_stats(&ring)
	testing.expect_value(t, after, before)
}

@(private)
test_ring_init :: proc(t: ^testing.T, ring_id: Ring_ID, policy: Policy) -> (Ring, bool) {
	ring: Ring
	initialized, failure := ring_init(
		&ring,
		ring_id,
		Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
		policy,
	)
	testing.expectf(t, initialized, "ring init failed with %v", failure.code)
	return ring, initialized
}

@(private)
test_admit :: proc(t: ^testing.T, ring: ^Ring, kind: Admission_Kind, text: string, kill: Kill_Context) -> Entry_Metadata {
	stats, stats_ok, _ := ring_stats(ring)
	testing.expect(t, stats_ok)
	reservation: Reservation
	result, reserved, failure := admission_reserve(
		ring,
		&reservation,
		Admission_Request {
			expected_generation = stats.generation,
			kind = kind,
			text = text,
			kill = kill,
		},
	)
	testing.expectf(t, reserved, "admission failed with %v", failure.code)
	if !reserved {
		return {}
	}
	committed := reservation_commit_reserved(&reservation)
	testing.expect_value(t, committed, result)
	return committed.entry
}

@(private)
test_expect_entry_text :: proc(t: ^testing.T, ring: ^Ring, entry_id: Entry_ID, expected: string) {
	stats, _, _ := ring_stats(ring)
	copied, copied_ok, failure := entry_copy(
		ring,
		Entry_Copy_Request {
			expected_generation = stats.generation,
			entry_id = entry_id,
			byte_limit = stats.policy.entry_bytes,
		},
		context.allocator,
	)
	testing.expectf(t, copied_ok, "entry copy failed with %v", failure.code)
	if !copied_ok {
		return
	}
	defer entry_copy_release(&copied, context.allocator)
	testing.expect_value(t, copied.text, expected)
}

@(private = "file")
Ring_Failing_Allocator :: struct {
	backing:                runtime.Allocator,
	fail_after:             u64,
	successful_allocations: u64,
}

@(private = "file")
ring_failing_allocator :: proc(data: ^Ring_Failing_Allocator) -> runtime.Allocator {
	return runtime.Allocator{procedure = ring_failing_allocator_proc, data = data}
}

@(private = "file")
ring_failing_allocator_proc :: proc(
	allocator_data: rawptr,
	mode: runtime.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	location := #caller_location,
) -> (result: []byte, error: runtime.Allocator_Error) {
	allocator := (^Ring_Failing_Allocator)(allocator_data)
	if mode == .Alloc || mode == .Alloc_Non_Zeroed ||
		mode == .Resize || mode == .Resize_Non_Zeroed {
		if allocator.successful_allocations >= allocator.fail_after {
			return nil, .Out_Of_Memory
		}
		allocator.successful_allocations += 1
	}
	return allocator.backing.procedure(
		allocator.backing.data,
		mode,
		size,
		alignment,
		old_memory,
		old_size,
		location,
	)
}
