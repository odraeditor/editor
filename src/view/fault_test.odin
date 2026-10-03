// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package view

import "../editor"
import "base:runtime"
import "core:mem"
import "core:testing"

/* Verifies registry and view allocation failures preserve ownership and occupancy. */
@(test)
alloc_failures_leave_no_view_or_anchor_leaks :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	failing := Failing_Allocator {
		backing = mem.tracking_allocator(&tracking),
		fail_after = 0,
	}

	failed_registry: Registry
	registry_ok, registry_failure := registry_init(
		&failed_registry,
		Registry_ID(21),
		failing_allocator(&failing),
	)
	testing.expect(t, !registry_ok)
	testing.expect_value(t, registry_failure.code, Failure_Code.Persistent_Memory_Limit)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))

	failing.fail_after = max(u64)
	buffer: editor.Buffer
	limits := editor.DEFAULT_LIMITS
	limits.anchors = 1_026
	buffer_ok, _ := editor.buffer_init(
		&buffer,
		editor.Buffer_ID(211),
		"abc",
		editor.Allocator_Set {
			persistent = failing_allocator(&failing),
			temporary = context.temp_allocator,
		},
		limits,
	)
	testing.expect(t, buffer_ok)
	if !buffer_ok {
		return
	}

	registry: Registry
	ready, _ := registry_init(&registry, Registry_ID(22), context.allocator)
	testing.expect(t, ready)
	position, position_ok, _ := editor.buffer_position(&buffer, editor.Byte_Offset(0))
	testing.expect(t, position_ok)
	for _ in 0 ..< 1_023 {
		_, anchor_ok, _ := editor.buffer_anchor_create(
			&buffer,
			position,
			.Left,
			.Collapse,
		)
		testing.expect(t, anchor_ok)
	}
	failing.fail_after = failing.successful_allocations
	_, created, create_failure := create(&registry, &buffer)
	testing.expect(t, !created)
	testing.expect_value(t, create_failure.code, Failure_Code.Editor_Failure)
	testing.expect_value(
		t,
		create_failure.editor_failure.code,
		editor.Failure_Code.Persistent_Memory_Limit,
	)
	anchor_stats, stats_ok, _ := editor.buffer_anchor_stats(&buffer)
	testing.expect(t, stats_ok)
	testing.expect_value(t, anchor_stats.live_count, u32(1_024))
	registry_closed, _ := registry_close(&registry)
	buffer_closed, _ := editor.buffer_close(&buffer)
	testing.expect(t, registry_closed && buffer_closed)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
}

/* Verifies complete cleanup for two views, retained marks, anchors, and registry storage. */
@(test)
view_cleanup_releases_all_tracked_storage :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	allocator := mem.tracking_allocator(&tracking)
	buffer: editor.Buffer
	buffer_ok, _ := editor.buffer_init(
		&buffer,
		editor.Buffer_ID(213),
		"abcdef",
		editor.Allocator_Set {
			persistent = allocator,
			temporary = context.temp_allocator,
		},
	)
	testing.expect(t, buffer_ok)
	if !buffer_ok {
		return
	}
	registry: Registry
	ready, _ := registry_init(&registry, Registry_ID(23), allocator)
	first, first_ok, _ := create(&registry, &buffer)
	second, second_ok, _ := clone_additional(&registry, first)
	testing.expect(t, ready && first_ok && second_ok)
	mark, _, _ := editor.buffer_position(&buffer, editor.Byte_Offset(3))
	first_mark, _ := set_mark(&registry, first, mark)
	second_mark, _ := set_mark(&registry, second, mark)
	testing.expect(t, first_mark && second_mark)

	first_closed, _ := close(&registry, &first)
	second_closed, _ := close(&registry, &second)
	registry_closed, _ := registry_close(&registry)
	buffer_closed, _ := editor.buffer_close(&buffer)
	testing.expect(t, first_closed && second_closed && registry_closed && buffer_closed)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
}

@(private)
Failing_Allocator :: struct {
	backing:                runtime.Allocator,
	fail_after:             u64,
	successful_allocations: u64,
}

@(private)
failing_allocator :: proc(data: ^Failing_Allocator) -> runtime.Allocator {
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
	allocator := (^Failing_Allocator)(allocator_data)
	if mode == .Alloc || mode == .Alloc_Non_Zeroed || mode == .Resize ||
	   mode == .Resize_Non_Zeroed {
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
