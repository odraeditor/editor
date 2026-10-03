// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package layout

import "../editor"
import "../view"
import "base:runtime"
import "core:mem"
import "core:testing"

/* Verifies registry allocation failure preserves external owners. */
@(test)
registry_alloc_fault_keeps_owners :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	failing := Layout_Failing_Allocator{backing = mem.tracking_allocator(&tracking), fail_after = 0}
	buffer: editor.Buffer
	buffer_ok, _ := editor.buffer_init(
		&buffer,
		editor.Buffer_ID(20_301),
		"allocation",
		editor.Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	views: view.Registry
	views_ok, _ := view.registry_init(&views, view.Registry_ID(20_301), context.allocator)
	root, root_ok, _ := view.create(&views, &buffer)
	registry: Registry
	registry_ok, registry_failure := registry_init(
		&registry,
		Owner_ID(20_301),
		Layout_ID(20_301),
		&views,
		root,
		Geometry_Request{rows = 12, columns = 40},
		DEFAULT_POLICY,
		layout_failing_allocator(&failing),
	)
	view_stats, view_stats_ok, _ := view.registry_stats(&views)
	testing.expect(t, buffer_ok && views_ok && root_ok && !registry_ok && view_stats_ok)
	testing.expect_value(t, registry_failure.code, Failure_Code.Persistent_Memory_Limit)
	testing.expect_value(t, view_stats.live_count, u16(1))
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	root_closed, _ := view.close(&views, &root)
	views_closed, _ := view.registry_close(&views)
	buffer_closed, _ := editor.buffer_close(&buffer)
	testing.expect(t, root_closed && views_closed && buffer_closed)
}

/* Verifies split view allocation failure preserves layout and accounting. */
@(test)
split_alloc_fault_keeps_layout :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	failing := Layout_Failing_Allocator {
		backing = mem.tracking_allocator(&tracking),
		fail_after = max(u64),
	}
	limits := editor.DEFAULT_LIMITS
	limits.anchors = 1_026
	buffer: editor.Buffer
	buffer_ok, _ := editor.buffer_init(
		&buffer,
		editor.Buffer_ID(20_302),
		"allocation",
		editor.Allocator_Set {
			persistent = layout_failing_allocator(&failing),
			temporary = context.temp_allocator,
		},
		limits,
	)
	views: view.Registry
	views_ok, _ := view.registry_init(&views, view.Registry_ID(20_302), context.allocator)
	root, root_ok, _ := view.create(&views, &buffer)
	registry: Registry
	registry_ok, _ := registry_init(
		&registry,
		Owner_ID(20_302),
		Layout_ID(20_302),
		&views,
		root,
		Geometry_Request{rows = 12, columns = 40},
	)
	testing.expect(t, buffer_ok && views_ok && root_ok && registry_ok)
	if !buffer_ok || !views_ok || !root_ok || !registry_ok {
		return
	}
	position, _, _ := editor.buffer_position(&buffer, 0)
	anchor_stats, _, _ := editor.buffer_anchor_stats(&buffer)
	for _ in anchor_stats.live_count ..< 1_024 {
		_, anchor_ok, _ := editor.buffer_anchor_create(&buffer, position, .Left, .Collapse)
		testing.expect(t, anchor_ok)
	}
	handle, _, _ := registry_handle(&registry)
	before, _, _ := registry_snapshot(&registry, handle)
	views_before, _, _ := view.registry_stats(&views)
	failing.fail_after = failing.successful_allocations
	_, split_ok, split_failure := registry_split_right(&registry, before.active_pane)
	after, after_ok, _ := registry_snapshot(&registry, handle)
	views_after, views_after_ok, _ := view.registry_stats(&views)
	testing.expect(t, !split_ok && after_ok && views_after_ok)
	testing.expect_value(t, split_failure.code, Failure_Code.View_Failure)
	testing.expect_value(t, split_failure.view_failure.code, view.Failure_Code.Editor_Failure)
	testing.expect_value(
		t,
		split_failure.view_failure.editor_failure.code,
		editor.Failure_Code.Persistent_Memory_Limit,
	)
	testing.expect_value(t, after, before)
	testing.expect_value(t, views_after, views_before)
	registry_closed, _ := registry_close(&registry)
	root_closed, _ := view.close(&views, &root)
	views_closed, _ := view.registry_close(&views)
	buffer_closed, _ := editor.buffer_close(&buffer)
	testing.expect(t, registry_closed && root_closed && views_closed && buffer_closed)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
}

/* Verifies prepared-memory and checked-integer failures precede publication. */
@(test)
limits_reject_before_publication :: proc(t: ^testing.T) {
	buffer: editor.Buffer
	views: view.Registry
	root: view.View_Handle
	registry: Registry
	ready := geometry_test_registry(20_303, 12, 40, &buffer, &views, &root, &registry)
	testing.expect(t, ready)
	if !ready {
		return
	}
	defer geometry_test_close(&buffer, &views, &root, &registry)
	handle, _, _ := registry_handle(&registry)
	before, _, _ := registry_snapshot(&registry, handle)
	registry_data(&registry).policy.prepared_bytes = 1
	_, split_ok, split_failure := registry_split_below(&registry, before.active_pane)
	after, after_ok, _ := registry_snapshot(&registry, handle)
	testing.expect(t, !split_ok && after_ok)
	testing.expect_value(t, split_failure.code, Failure_Code.Prepared_Memory_Limit)
	testing.expect_value(t, after, before)

	overflow_policy := DEFAULT_POLICY
	overflow_policy.operating_content_rows = max(i32)
	overflow_registry: Registry
	overflow_ok, overflow_failure := registry_init(
		&overflow_registry,
		Owner_ID(20_304),
		Layout_ID(20_304),
		&views,
		root,
		Geometry_Request{rows = 12, columns = 40},
		overflow_policy,
	)
	testing.expect(t, !overflow_ok)
	testing.expect_value(t, overflow_failure.code, Failure_Code.Checked_Integer_Overflow)
}

/* Verifies dedication mutation faults and removed identities preserve published state. */
@(test)
dedication_faults_keep_panes_invalid :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	failing := Layout_Failing_Allocator {
		backing = mem.tracking_allocator(&tracking),
		fail_after = max(u64),
	}
	fixture: Replacement_Test_Fixture
	if !replacement_test_fixture_init(
		t,
		&fixture,
		20_891,
		layout_failing_allocator(&failing),
	) {
		mem.tracking_allocator_destroy(&tracking)
		return
	}

	handle, _, _ := registry_handle(&fixture.registry)
	initial, _, _ := registry_snapshot(&fixture.registry, handle)
	failing.fail_after = failing.successful_allocations
	_, set_ok, set_failure := registry_pane_dedication_set(
		&fixture.registry,
		initial.active_pane,
		.Soft,
	)
	failing.fail_after = max(u64)
	after_failure, after_failure_ok, _ := registry_snapshot(&fixture.registry, handle)
	testing.expect(t, !set_ok && after_failure_ok)
	testing.expect_value(t, set_failure.code, Failure_Code.Prepared_Memory_Limit)
	testing.expect_value(t, after_failure, initial)

	split, split_ok, _ := registry_split_right(&fixture.registry, initial.active_pane)
	if !split_ok {
		testing.expect(t, false)
		replacement_test_fixture_close(t, &fixture)
		mem.tracking_allocator_destroy(&tracking)
		return
	}
	focused, focus_ok, _ := registry_focus(&fixture.registry, split.created)
	if !focus_ok {
		testing.expect(t, false)
		replacement_test_fixture_close(t, &fixture)
		mem.tracking_allocator_destroy(&tracking)
		return
	}
	closed, close_ok, _ := registry_close_pane(&fixture.registry, focused.active)
	testing.expect(t, close_ok)
	removed := split.created
	removed.layout = closed.layout
	_, inspect_ok, inspect_failure := registry_pane_dedication_inspect(&fixture.registry, removed)
	testing.expect(t, !inspect_ok)
	testing.expect_value(t, inspect_failure.code, Failure_Code.Stale_Pane)

	current, _, _ := registry_snapshot(&fixture.registry, closed.layout)
	registry_data(&fixture.registry).generation = Layout_Generation(max(u64))
	current.active_pane.layout.generation = Layout_Generation(max(u64))
	before_limit, before_limit_ok, _ := registry_snapshot(
		&fixture.registry,
		current.active_pane.layout,
	)
	_, limit_ok, limit_failure := registry_pane_dedication_set(
		&fixture.registry,
		current.active_pane,
		.Hard,
	)
	after_limit, after_limit_ok, _ := registry_snapshot(
		&fixture.registry,
		current.active_pane.layout,
	)
	testing.expect(t, before_limit_ok && !limit_ok && after_limit_ok)
	testing.expect_value(t, limit_failure.code, Failure_Code.Generation_Limit)
	testing.expect_value(t, after_limit, before_limit)

	replacement_test_fixture_close(t, &fixture)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&tracking)
}

/* Verifies resize and balance allocation faults preserve state and accounting. */
@(test)
resize_and_balance_allocation_faults_are_atomic :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	failing := Layout_Failing_Allocator {
		backing = mem.tracking_allocator(&tracking),
		fail_after = max(u64),
	}
	buffer: editor.Buffer
	buffer_ok, _ := editor.buffer_init(
		&buffer,
		editor.Buffer_ID(20_305),
		"resize-fault",
		editor.Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	views: view.Registry
	views_ok, _ := view.registry_init(&views, view.Registry_ID(20_305), context.allocator)
	root, root_ok, _ := view.create(&views, &buffer)
	registry: Registry
	registry_ok, _ := registry_init(
		&registry,
		Owner_ID(20_305),
		Layout_ID(20_305),
		&views,
		root,
		Geometry_Request{rows = 12, columns = 42},
		DEFAULT_POLICY,
		layout_failing_allocator(&failing),
	)
	testing.expect(t, buffer_ok && views_ok && root_ok && registry_ok)
	if !buffer_ok || !views_ok || !root_ok || !registry_ok {
		mem.tracking_allocator_destroy(&tracking)
		return
	}
	handle, _, _ := registry_handle(&registry)
	initial, _, _ := registry_snapshot(&registry, handle)
	split, split_ok, _ := registry_split_right(&registry, initial.active_pane)
	testing.expect(t, split_ok)
	if !split_ok {
		registry_close(&registry)
		view.close(&views, &root)
		view.registry_close(&views)
		editor.buffer_close(&buffer)
		mem.tracking_allocator_destroy(&tracking)
		return
	}
	before, _, _ := registry_snapshot(&registry, split.layout)
	stats_before, stats_before_ok, _ := registry_stats(&registry)
	failing.fail_after = failing.successful_allocations
	_, resize_ok, resize_failure := registry_resize_pane(
		&registry,
		before.active_pane,
		.Left_Right,
		1,
	)
	_, balance_ok, balance_failure := registry_balance_panes(&registry, before.handle)
	_, area_ok, area_failure := registry_balance_pane_areas(&registry, before.handle)
	failing.fail_after = max(u64)
	after, after_ok, _ := registry_snapshot(&registry, before.handle)
	stats_after, stats_after_ok, _ := registry_stats(&registry)
	testing.expect(
		t,
		!resize_ok && !balance_ok && !area_ok && after_ok && stats_before_ok && stats_after_ok,
	)
	testing.expect_value(t, resize_failure.code, Failure_Code.Prepared_Memory_Limit)
	testing.expect_value(t, balance_failure.code, Failure_Code.Prepared_Memory_Limit)
	testing.expect_value(t, area_failure.code, Failure_Code.Prepared_Memory_Limit)
	testing.expect_value(t, after, before)
	testing.expect_value(t, stats_after, stats_before)
	registry_closed, _ := registry_close(&registry)
	root_closed, _ := view.close(&views, &root)
	views_closed, _ := view.registry_close(&views)
	buffer_closed, _ := editor.buffer_close(&buffer)
	testing.expect(t, registry_closed && root_closed && views_closed && buffer_closed)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&tracking)
}

@(private)
Layout_Failing_Allocator :: struct {
	backing:                runtime.Allocator,
	fail_after:             u64,
	successful_allocations: u64,
}

@(private)
layout_failing_allocator :: proc(data: ^Layout_Failing_Allocator) -> runtime.Allocator {
	return runtime.Allocator{procedure = layout_failing_allocator_proc, data = data}
}

@(private)
layout_failing_allocator_proc :: proc(
	allocator_data: rawptr,
	mode: runtime.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	location := #caller_location,
) -> (result: []byte, error: runtime.Allocator_Error) {
	allocator := (^Layout_Failing_Allocator)(allocator_data)
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
