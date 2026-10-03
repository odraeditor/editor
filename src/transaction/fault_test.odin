// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package transaction

import "../editor"
import editor_view "../view"
import "base:runtime"
import "core:mem"
import "core:testing"

/* Injects logical-view preparation failure and verifies neither participant becomes visible. */
@(test)
logical_view_alloc_failure_aborts_text_and_view :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	failing := Transaction_Failing_Allocator {
		backing = mem.tracking_allocator(&tracking),
		fail_after = max(u64),
	}
	allocator := failing_allocator(&failing)
	buffer: editor.Buffer
	initialized, _ := editor.buffer_init(
		&buffer,
		editor.Buffer_ID(370),
		"abc",
		editor.Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, initialized)
	registry: editor_view.Registry
	registry_ready, _ := editor_view.registry_init(&registry, editor_view.Registry_ID(370), allocator)
	handle, view_ready, _ := editor_view.create(&registry, &buffer)
	testing.expect(t, registry_ready && view_ready)
	transaction: Transaction
	started, _ := transaction_begin(
		&transaction,
		Transaction_ID(370),
		Undo_Unit_ID(370),
		&buffer,
		Origin{kind = .Built_In, descriptor = "view-fault"},
		"insert-text",
		Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, started)
	one, _, _ := transaction_position(&transaction, editor.Byte_Offset(1))
	transaction_splice(
		&transaction,
		editor.Working_Splice{start = one, end = one, replacement = "X"},
	)
	target, _, _ := transaction_position(&transaction, editor.Byte_Offset(2))
	before, _, _ := editor_view.snapshot(&registry, handle)
	failing.fail_after = failing.successful_allocations
	prepared, prepare_failure := transaction_prepare_logical_view(
		&transaction,
		&registry,
		handle,
		target,
		2,
		.Deactivate,
	)
	testing.expect(t, !prepared)
	testing.expect_value(t, prepare_failure.code, Failure_Code.View_Failure)
	testing.expect_value(
		t,
		prepare_failure.view_failure.code,
		editor_view.Failure_Code.Persistent_Memory_Limit,
	)
	expect_lifecycle(t, &transaction, .Aborted)
	expect_confirmed_text(t, &buffer, editor.Revision(0), "abc")
	after, after_ok, _ := editor_view.snapshot(&registry, handle)
	testing.expect(t, after_ok)
	testing.expect_value(t, after, before)
	transaction_close(&transaction)
	editor_view.close(&registry, &handle)
	editor_view.registry_close(&registry)
	editor.buffer_close(&buffer)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
}

/* Injects allocation failure through begin and verifies complete cleanup. */
@(test)
begin_allocation_faults_leave_no_private_state :: proc(t: ^testing.T) {
	for fail_offset in 0 ..= 4 {
		tracking: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracking, context.allocator)
		failing := Transaction_Failing_Allocator {
			backing = mem.tracking_allocator(&tracking),
			fail_after = max(u64),
		}
		buffer: editor.Buffer
		initialized, _ := editor.buffer_init(
			&buffer,
			editor.Buffer_ID(300 + fail_offset),
			"abc",
			editor.Allocator_Set {
				persistent = failing_allocator(&failing),
				temporary = context.temp_allocator,
			},
		)
		testing.expect(t, initialized)
		failing.fail_after = failing.successful_allocations + u64(fail_offset)
		transaction: Transaction
		started, _ := transaction_begin(
			&transaction,
			Transaction_ID(300 + fail_offset),
			Undo_Unit_ID(300 + fail_offset),
			&buffer,
			Origin{kind = .Built_In, descriptor = "fault"},
			"fault-command",
			Allocator_Set {
				persistent = failing_allocator(&failing),
				temporary = context.temp_allocator,
			},
		)
		if started {
			transaction_close(&transaction)
		}
		expect_confirmed_text(t, &buffer, editor.Revision(0), "abc")
		closed, _ := editor.buffer_close(&buffer)
		testing.expect(t, closed)
		testing.expect_value(t, tracking.current_memory_allocated, i64(0))
		mem.tracking_allocator_destroy(&tracking)
	}
}

/* Injects preparation faults and verifies abort, canonical preservation, and no leaks. */
@(test)
batch_alloc_faults_never_publish_partial_text :: proc(t: ^testing.T) {
	for fail_offset in 0 ..= 12 {
		tracking: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracking, context.allocator)
		failing := Transaction_Failing_Allocator {
			backing = mem.tracking_allocator(&tracking),
			fail_after = max(u64),
		}
		buffer: editor.Buffer
		initialized, _ := editor.buffer_init(
			&buffer,
			editor.Buffer_ID(320 + fail_offset),
			"abcdef",
			editor.Allocator_Set {
				persistent = failing_allocator(&failing),
				temporary = context.temp_allocator,
			},
		)
		testing.expect(t, initialized)
		transaction: Transaction
		started, begin_failure := transaction_begin(
			&transaction,
			Transaction_ID(320 + fail_offset),
			Undo_Unit_ID(320 + fail_offset),
			&buffer,
			Origin{kind = .Built_In, descriptor = "fault"},
			"fault-command",
			Allocator_Set {
				persistent = failing_allocator(&failing),
				temporary = context.temp_allocator,
			},
		)
		testing.expectf(t, started, "begin failed before injection with %v", begin_failure.code)
		if !started {
			editor.buffer_close(&buffer)
			mem.tracking_allocator_destroy(&tracking)
			continue
		}
		start, _, _ := editor.buffer_position(&buffer, editor.Byte_Offset(1))
		end, _, _ := editor.buffer_position(&buffer, editor.Byte_Offset(5))
		failing.fail_after = failing.successful_allocations + u64(fail_offset)
		applied, _ := transaction_apply_batch(
			&transaction,
			[]Base_Splice{{start = start, end = end, replacement = "XYZ"}},
		)
		if applied {
			validated, _ := transaction_validate(&transaction)
			if validated {
				_, _, _ = transaction_commit(&transaction)
			}
		}
		stats, stats_ok, _ := editor.buffer_stats(&buffer)
		testing.expect(t, stats_ok)
		if stats.revision == editor.Revision(0) {
			expect_confirmed_text(t, &buffer, editor.Revision(0), "abcdef")
		} else {
			expect_confirmed_text(t, &buffer, editor.Revision(1), "aXYZf")
		}
		transaction_close(&transaction)
		editor.buffer_close(&buffer)
		testing.expect_value(t, tracking.current_memory_allocated, i64(0))
		mem.tracking_allocator_destroy(&tracking)
	}
}

/* Injects nested metadata faults and verifies the savepoint and root remain clean. */
@(test)
nested_begin_allocation_faults_preserve_root :: proc(t: ^testing.T) {
	for fail_offset in 0 ..= 2 {
		tracking: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracking, context.allocator)
		failing := Transaction_Failing_Allocator {
			backing = mem.tracking_allocator(&tracking),
			fail_after = max(u64),
		}
		buffer: editor.Buffer
		initialized, _ := editor.buffer_init(
			&buffer,
			editor.Buffer_ID(360 + fail_offset),
			"abc",
			editor.Allocator_Set {
				persistent = failing_allocator(&failing),
				temporary = context.temp_allocator,
			},
		)
		testing.expect(t, initialized)
		transaction: Transaction
		started, _ := transaction_begin(
			&transaction,
			Transaction_ID(360 + fail_offset),
			Undo_Unit_ID(360 + fail_offset),
			&buffer,
			Origin{kind = .Built_In, descriptor = "fault"},
			"root-command",
			Allocator_Set {
				persistent = failing_allocator(&failing),
				temporary = context.temp_allocator,
			},
		)
		testing.expect(t, started)
		failing.fail_after = failing.successful_allocations + u64(fail_offset)
		nested, nested_ok, _ := transaction_nested_begin(
			&transaction,
			Origin{kind = .Built_In, descriptor = "nested"},
			"nested-command",
		)
		if nested_ok {
			transaction_nested_fail(&transaction, &nested, .Handled)
		}
		expect_private_text(t, &transaction, "abc")
		transaction_abort(&transaction)
		transaction_close(&transaction)
		editor.buffer_close(&buffer)
		testing.expect_value(t, tracking.current_memory_allocated, i64(0))
		mem.tracking_allocator_destroy(&tracking)
	}
}

@(private)
Transaction_Failing_Allocator :: struct {
	backing:                runtime.Allocator,
	fail_after:             u64,
	successful_allocations: u64,
}

@(private)
failing_allocator :: proc(data: ^Transaction_Failing_Allocator) -> runtime.Allocator {
	return runtime.Allocator {
		procedure = failing_allocator_proc,
		data = data,
	}
}

@(private)
failing_allocator_proc :: proc(
	allocator_data: rawptr,
	mode: runtime.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	location := #caller_location,
) -> (result: []byte, error: runtime.Allocator_Error) {
	allocator := (^Transaction_Failing_Allocator)(allocator_data)
	if mode == .Alloc || mode == .Alloc_Non_Zeroed || mode == .Resize || mode == .Resize_Non_Zeroed {
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
