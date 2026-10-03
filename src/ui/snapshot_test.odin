// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ui

import "base:runtime"
import "core:mem"
import "core:testing"

@(test)
/* Ensures snapshots remain immutable after their root is replaced. */
remains_immutable_after_root_replacement :: proc(t: ^testing.T) {
	registry: Registry
	initialized, _ := registry_init(&registry, Registry_ID(51))
	testing.expect(t, initialized)
	if !initialized {
		return
	}
	defer registry_close(&registry)
	first, first_ok := publish_single_text_root(&registry, {})
	testing.expect(t, first_ok)
	if !first_ok {
		return
	}

	snapshot, copied, _ := registry_snapshot(&registry, first, test_renderer())
	testing.expect(t, copied)
	if !copied {
		return
	}
	defer snapshot_close(&snapshot)
	before, before_ok := snapshot_view(&snapshot)
	second, second_ok := publish_single_text_root(&registry, first)
	after, after_ok := snapshot_view(&snapshot)

	testing.expect(t, before_ok && second_ok && after_ok)
	testing.expect_value(t, before.root, first)
	testing.expect_value(t, after.root, first)
	testing.expect_value(t, len(after.surfaces), 1)
	testing.expect_value(t, after.surfaces[0], before.surfaces[0])
	testing.expect_value(t, second.generation, Root_Generation(2))
}

@(test)
/* Ensures stale or incompatible consumers cannot read a snapshot. */
rejects_stale_and_incompatible_consumers :: proc(t: ^testing.T) {
	registry: Registry
	initialized, _ := registry_init(&registry, Registry_ID(52))
	testing.expect(t, initialized)
	if !initialized {
		return
	}
	defer registry_close(&registry)
	root, published := publish_single_text_root(&registry, {})
	second, replaced := publish_single_text_root(&registry, root)
	testing.expect(t, published && replaced)
	if !published || !replaced {
		return
	}

	_, stale_ok, stale_failure := registry_snapshot(&registry, root, test_renderer())
	incompatible := test_renderer()
	incompatible.max_columns = 120
	incompatible.max_cells = 9_600
	_, compatible_ok, compatible_failure := registry_snapshot(
		&registry,
		second,
		incompatible,
	)

	testing.expect(t, !stale_ok && !compatible_ok)
	testing.expect_value(t, stale_failure.code, Failure_Code.Stale_Root)
	testing.expect_value(t, compatible_failure.code, Failure_Code.Renderer_Incompatible)
}

@(test)
/* Ensures allocation faults release every partial snapshot copy. */
allocation_faults_release_partial_copies :: proc(t: ^testing.T) {
	registry: Registry
	initialized, _ := registry_init(&registry, Registry_ID(53))
	testing.expect(t, initialized)
	if !initialized {
		return
	}
	defer registry_close(&registry)
	root, published := publish_single_text_root(&registry, {})
	testing.expect(t, published)
	if !published {
		return
	}

	for fail_after in 0 ..< 6 {
		tracking: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracking, context.allocator)
		failing := UI_Failing_Allocator {
			backing = mem.tracking_allocator(&tracking),
			fail_after = u64(fail_after),
		}
		snapshot, copied, failure := registry_snapshot(
			&registry,
			root,
			test_renderer(),
			ui_failing_allocator(&failing),
		)
		testing.expectf(t, !copied, "snapshot allocation %d unexpectedly passed", fail_after)
		testing.expect_value(t, failure.code, Failure_Code.Allocation)
		testing.expect_value(t, snapshot, Snapshot{})
		testing.expect_value(t, tracking.current_memory_allocated, i64(0))
		mem.tracking_allocator_destroy(&tracking)
	}
	current, current_ok, _ := registry_handle(&registry)
	testing.expect(t, current_ok)
	testing.expect_value(t, current, root)
}

@(test)
/* Ensures successful snapshots release all copied storage. */
snapshot_success_releases_all_copied_storage :: proc(t: ^testing.T) {
	registry: Registry
	initialized, _ := registry_init(&registry, Registry_ID(54))
	testing.expect(t, initialized)
	if !initialized {
		return
	}
	defer registry_close(&registry)
	root, published := publish_single_text_root(&registry, {})
	testing.expect(t, published)
	if !published {
		return
	}

	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	snapshot, copied, _ := registry_snapshot(
		&registry,
		root,
		test_renderer(),
		mem.tracking_allocator(&tracking),
	)
	testing.expect(t, copied)
	if copied {
		testing.expect(t, tracking.current_memory_allocated > 0)
		testing.expect(t, snapshot_close(&snapshot))
	}
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&tracking)
}

@(private)
UI_Failing_Allocator :: struct {
	backing:                runtime.Allocator,
	fail_after:             u64,
	successful_allocations: u64,
}

@(private)
ui_failing_allocator :: proc(data: ^UI_Failing_Allocator) -> runtime.Allocator {
	return runtime.Allocator {
		procedure = ui_failing_allocator_proc,
		data = data,
	}
}

@(private)
ui_failing_allocator_proc :: proc(
	allocator_data: rawptr,
	mode: runtime.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	location := #caller_location,
) -> (result: []byte, error: runtime.Allocator_Error) {
	allocator := cast(^UI_Failing_Allocator)allocator_data
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
