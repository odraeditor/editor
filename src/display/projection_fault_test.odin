// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package display

import editor_view "../view"
import "base:runtime"
import "core:mem"
import "core:testing"

/* Verifies every temporary workspace allocation failure leaves no retained storage. */
@(test)
projection_temporary_alloc_failures_are_atomic :: proc(t: ^testing.T) {
	fixture: Projection_Fixture
	ready := projection_fixture_init(t, &fixture, 81, "alpha\nbeta\ngamma")
	if !ready {
		return
	}
	defer projection_fixture_close(&fixture)
	logical, _, _ := editor_view.snapshot(&fixture.registry, fixture.handle)
	for fail_after in 0 ..< 6 {
		persistent_tracking: mem.Tracking_Allocator
		temporary_tracking: mem.Tracking_Allocator
		mem.tracking_allocator_init(&persistent_tracking, context.allocator)
		mem.tracking_allocator_init(&temporary_tracking, context.allocator)
		failing := Projection_Failing_Allocator {
			backing = mem.tracking_allocator(&temporary_tracking),
			fail_after = u64(fail_after),
		}
		request := projection_request(
			u64(100 + fail_after),
			logical,
			Viewport_Constraints{width_cells = 20, height_rows = 4},
		)
		request.allocators.persistent = mem.tracking_allocator(&persistent_tracking)
		request.allocators.temporary = projection_failing_allocator(&failing)
		_, projected, failure := project(&fixture.buffer, request)
		testing.expectf(t, !projected, "temporary allocation %d unexpectedly passed", fail_after)
		testing.expect_value(t, failure.code, Failure_Code.Temporary_Memory_Limit)
		testing.expect_value(t, temporary_tracking.current_memory_allocated, i64(0))
		testing.expect_value(t, persistent_tracking.current_memory_allocated, i64(0))
		mem.tracking_allocator_destroy(&temporary_tracking)
		mem.tracking_allocator_destroy(&persistent_tracking)
	}
}

/* Verifies every retained snapshot allocation failure rolls back exact ownership. */
@(test)
projection_persistent_alloc_failures_are_atomic :: proc(t: ^testing.T) {
	fixture: Projection_Fixture
	ready := projection_fixture_init(t, &fixture, 83, "alpha\nbeta\ngamma")
	if !ready {
		return
	}
	defer projection_fixture_close(&fixture)
	logical, _, _ := editor_view.snapshot(&fixture.registry, fixture.handle)
	for fail_after in 0 ..< 6 {
		persistent_tracking: mem.Tracking_Allocator
		temporary_tracking: mem.Tracking_Allocator
		mem.tracking_allocator_init(&persistent_tracking, context.allocator)
		mem.tracking_allocator_init(&temporary_tracking, context.allocator)
		failing := Projection_Failing_Allocator {
			backing = mem.tracking_allocator(&persistent_tracking),
			fail_after = u64(fail_after),
		}
		request := projection_request(
			u64(120 + fail_after),
			logical,
			Viewport_Constraints{width_cells = 20, height_rows = 4},
		)
		request.allocators.persistent = projection_failing_allocator(&failing)
		request.allocators.temporary = mem.tracking_allocator(&temporary_tracking)
		_, projected, failure := project(&fixture.buffer, request)
		testing.expectf(t, !projected, "persistent allocation %d unexpectedly passed", fail_after)
		testing.expect_value(t, failure.code, Failure_Code.Persistent_Memory_Limit)
		testing.expect_value(t, temporary_tracking.current_memory_allocated, i64(0))
		testing.expect_value(t, persistent_tracking.current_memory_allocated, i64(0))
		mem.tracking_allocator_destroy(&temporary_tracking)
		mem.tracking_allocator_destroy(&persistent_tracking)
	}
}

/* Verifies successful snapshot and cache lifecycles release all tracked storage. */
@(test)
cleanup_releases_tracked_storage :: proc(t: ^testing.T) {
	fixture: Projection_Fixture
	ready := projection_fixture_init(t, &fixture, 85, "tracked\nprojection")
	if !ready {
		return
	}
	defer projection_fixture_close(&fixture)
	logical, _, _ := editor_view.snapshot(&fixture.registry, fixture.handle)
	persistent_tracking: mem.Tracking_Allocator
	temporary_tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&persistent_tracking, context.allocator)
	mem.tracking_allocator_init(&temporary_tracking, context.allocator)
	persistent := mem.tracking_allocator(&persistent_tracking)
	temporary := mem.tracking_allocator(&temporary_tracking)
	cache: Projection_Cache
	cache_ready, _ := projection_cache_init(
		&cache,
		logical,
		terminal_unicode17_profile(),
		persistent,
	)
	testing.expect(t, cache_ready)
	request := projection_request(
		140,
		logical,
		Viewport_Constraints{width_cells = 20, height_rows = 3},
	)
	request.allocators = Allocator_Set{persistent = persistent, temporary = temporary}
	snapshot, projected, failure := project_cached(&fixture.buffer, request, &cache)
	testing.expectf(t, projected, "tracked projection failed with %v", failure.code)
	testing.expect_value(t, temporary_tracking.current_memory_allocated, i64(0))
	if projected {
		snapshot_close(&snapshot)
	}
	if cache_ready {
		projection_cache_close(&cache)
	}
	testing.expect_value(t, temporary_tracking.current_memory_allocated, i64(0))
	testing.expect_value(t, persistent_tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&temporary_tracking)
	mem.tracking_allocator_destroy(&persistent_tracking)
}

/* Verifies both cache initialization allocation failures preserve a zero-value owner. */
@(test)
projection_cache_allocation_failures_are_atomic :: proc(t: ^testing.T) {
	fixture: Projection_Fixture
	ready := projection_fixture_init(t, &fixture, 87, "cache")
	if !ready {
		return
	}
	defer projection_fixture_close(&fixture)
	logical, _, _ := editor_view.snapshot(&fixture.registry, fixture.handle)
	for fail_after in 0 ..< 2 {
		tracking: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracking, context.allocator)
		failing := Projection_Failing_Allocator {
			backing = mem.tracking_allocator(&tracking),
			fail_after = u64(fail_after),
		}
		cache: Projection_Cache
		initialized, _ := projection_cache_init(
			&cache,
			logical,
			terminal_unicode17_profile(),
			projection_failing_allocator(&failing),
		)
		testing.expect(t, !initialized)
		testing.expect_value(t, cache, Projection_Cache{})
		testing.expect_value(t, tracking.current_memory_allocated, i64(0))
		mem.tracking_allocator_destroy(&tracking)
	}
}

@(private)
Projection_Failing_Allocator :: struct {
	backing:                runtime.Allocator,
	fail_after:             u64,
	successful_allocations: u64,
}

@(private)
projection_failing_allocator :: proc(data: ^Projection_Failing_Allocator) -> runtime.Allocator {
	return runtime.Allocator {
		procedure = projection_failing_allocator_proc,
		data = data,
	}
}

@(private)
projection_failing_allocator_proc :: proc(
	allocator_data: rawptr,
	mode: runtime.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	location := #caller_location,
) -> (result: []byte, error: runtime.Allocator_Error) {
	allocator := (^Projection_Failing_Allocator)(allocator_data)
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
