// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package layout

import "../editor"
import "../view"
import "core:mem"
import "core:testing"

/* Verifies one root pane publishes complete geometry and exact accounting. */
@(test)
single_pane_registry_exposes_snapshot :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	allocator := mem.tracking_allocator(&tracking)

	buffer: editor.Buffer
	buffer_ok, _ := editor.buffer_init(
		&buffer,
		editor.Buffer_ID(20_001),
		"layout",
		editor.Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
	)
	views: view.Registry
	views_ok, _ := view.registry_init(&views, view.Registry_ID(20_001), allocator)
	root_view, root_view_ok, _ := view.create(&views, &buffer)
	registry: Registry
	registry_ok, _ := registry_init(
		&registry,
		Owner_ID(1),
		Layout_ID(1),
		&views,
		root_view,
		Geometry_Request{rows = 24, columns = 80},
		DEFAULT_POLICY,
		allocator,
	)
	testing.expect(t, buffer_ok && views_ok && root_view_ok && registry_ok)
	if !buffer_ok || !views_ok || !root_view_ok || !registry_ok {
		return
	}

	handle, handle_ok, _ := registry_handle(&registry)
	snapshot, snapshot_ok, _ := registry_snapshot(&registry, handle)
	stats, stats_ok, _ := registry_stats(&registry)
	testing.expect(t, handle_ok && snapshot_ok && stats_ok)
	testing.expect_value(t, snapshot.handle, handle)
	testing.expect_value(t, snapshot.geometry_state, Geometry_State.Operating)
	testing.expect_value(t, snapshot.node_count, u16(1))
	testing.expect_value(t, snapshot.pane_count, u16(1))
	testing.expect_value(t, snapshot.partition_count, u16(0))
	testing.expect_value(t, snapshot.nodes[0].kind, Node_Kind.Pane)
	testing.expect_value(t, snapshot.nodes[0].pane, snapshot.active_pane)
	testing.expect(t, snapshot.nodes[0].active)
	testing.expect_value(t, snapshot.nodes[0].mru_rank, u16(0))
	testing.expect_value(t, snapshot.nodes[0].geometry.outer, Rect{height = 24, width = 80})
	testing.expect_value(t, snapshot.nodes[0].geometry.content, Rect{height = 22, width = 80})
	testing.expect_value(t, snapshot.nodes[0].geometry.status, Rect{row = 22, height = 2, width = 80})
	testing.expect_value(t, stats.storage_bytes, u64(size_of(Registry_Data)))

	closed, _ := registry_close(&registry)
	root_closed, _ := view.close(&views, &root_view)
	views_closed, _ := view.registry_close(&views)
	buffer_closed, _ := editor.buffer_close(&buffer)
	testing.expect(t, closed && root_closed && views_closed && buffer_closed)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
}

/* Verifies teardown accepts a primary view already released by its session owner. */
@(test)
teardown_accepts_released_primary_view :: proc(t: ^testing.T) {
	buffer: editor.Buffer
	buffer_ok, _ := editor.buffer_init(
		&buffer,
		editor.Buffer_ID(20_004),
		"layout",
		editor.Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	views: view.Registry
	views_ok, _ := view.registry_init(&views, view.Registry_ID(20_004), context.allocator)
	root_view, root_view_ok, _ := view.create(&views, &buffer)
	registry: Registry
	registry_ok, _ := registry_init(
		&registry,
		Owner_ID(4),
		Layout_ID(4),
		&views,
		root_view,
		Geometry_Request{rows = 24, columns = 80},
	)
	testing.expect(t, buffer_ok && views_ok && root_view_ok && registry_ok)
	if !buffer_ok || !views_ok || !root_view_ok || !registry_ok {
		return
	}

	root_closed, _ := view.close(&views, &root_view)
	layout_closed, layout_failure := registry_close(&registry)
	views_closed, _ := view.registry_close(&views)
	buffer_closed, _ := editor.buffer_close(&buffer)
	testing.expect(t, root_closed && layout_closed && views_closed && buffer_closed)
	testing.expect_value(t, layout_failure.code, Failure_Code.None)
}

/* Verifies stale and wrong-owner layout handles preserve registry state. */
@(test)
bad_layout_handles_keep_state :: proc(t: ^testing.T) {
	buffer: editor.Buffer
	buffer_ok, _ := editor.buffer_init(
		&buffer,
		editor.Buffer_ID(20_002),
		"abc",
		editor.Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	views: view.Registry
	views_ok, _ := view.registry_init(&views, view.Registry_ID(20_002), context.allocator)
	root_view, root_view_ok, _ := view.create(&views, &buffer)
	registry: Registry
	registry_ok, _ := registry_init(
		&registry,
		Owner_ID(2),
		Layout_ID(2),
		&views,
		root_view,
		Geometry_Request{rows = 10, columns = 40},
	)
	testing.expect(t, buffer_ok && views_ok && root_view_ok && registry_ok)
	if !buffer_ok || !views_ok || !root_view_ok || !registry_ok {
		return
	}
	handle, _, _ := registry_handle(&registry)
	wrong := handle
	wrong.owner_id = Owner_ID(99)
	_, wrong_ok, wrong_failure := registry_snapshot(&registry, wrong)
	stale := handle
	stale.generation = Layout_Generation(u64(stale.generation) + 1)
	_, stale_ok, stale_failure := registry_snapshot(&registry, stale)
	stats, stats_ok, _ := registry_stats(&registry)
	testing.expect(t, !wrong_ok && !stale_ok && stats_ok)
	testing.expect_value(t, wrong_failure.code, Failure_Code.Wrong_Owner)
	testing.expect_value(t, stale_failure.code, Failure_Code.Stale_Layout)
	testing.expect_value(t, stats.node_count, u16(1))

	registry_close(&registry)
	view.close(&views, &root_view)
	view.registry_close(&views)
	editor.buffer_close(&buffer)
}

/* Verifies teardown preflights every additional view before releasing any layout state. */
@(test)
teardown_failure_keeps_registry_state :: proc(t: ^testing.T) {
	buffer: editor.Buffer
	views: view.Registry
	root_view: view.View_Handle
	registry: Registry
	ready := geometry_test_registry(20_003, 40, 80, &buffer, &views, &root_view, &registry)
	testing.expect(t, ready)
	if !ready {
		return
	}

	handle, _, _ := registry_handle(&registry)
	initial, _, _ := registry_snapshot(&registry, handle)
	first, first_ok, _ := registry_split_right(&registry, initial.active_pane)
	focused, focused_ok, _ := registry_focus(&registry, first.created)
	second, second_ok, _ := registry_split_below(&registry, focused.active)
	testing.expect(t, first_ok && focused_ok && second_ok)
	if !first_ok || !focused_ok || !second_ok {
		geometry_test_close(&buffer, &views, &root_view, &registry)
		return
	}
	current, _, _ := registry_handle(&registry)
	snapshot, _, _ := registry_snapshot(&registry, current)
	blocked_view: view.View_Handle
	for index in 0 ..< int(snapshot.node_count) {
		node := snapshot.nodes[index]
		if node.kind == .Pane && node.pane == second.created {
			blocked_view = node.view
			break
		}
	}
	stats, stats_ok, _ := editor.buffer_stats(&buffer)
	prepared: view.Prepared_Logical_Edit
	prepared_ok, _ := view.logical_edit_prepare(
		&views,
		blocked_view,
		view.Logical_Edit_Request {
			buffer_id = stats.buffer_id,
			base_revision = stats.revision,
			result_point_offset = 0,
			region = .Preserve,
			mark = .Preserve,
		},
		&prepared,
	)
	testing.expect(t, stats_ok && prepared_ok)
	if !stats_ok || !prepared_ok {
		geometry_test_close(&buffer, &views, &root_view, &registry)
		return
	}

	view_stats_before, _, _ := view.registry_stats(&views)
	closed, close_failure := registry_close(&registry)
	view_stats_after, view_stats_ok, _ := view.registry_stats(&views)
	retained, retained_ok, _ := registry_snapshot(&registry, current)
	testing.expect(t, !closed && view_stats_ok && retained_ok)
	testing.expect_value(t, close_failure.operation, Operation.Teardown)
	testing.expect_value(t, close_failure.code, Failure_Code.View_Failure)
	testing.expect_value(t, close_failure.view_failure.code, view.Failure_Code.Active_Preparation)
	testing.expect_value(t, view_stats_after.live_count, view_stats_before.live_count)
	testing.expect_value(t, view_stats_after.additional_count, view_stats_before.additional_count)
	testing.expect_value(t, retained.handle, snapshot.handle)
	testing.expect_value(t, retained.node_count, snapshot.node_count)

	aborted, _ := view.logical_edit_abort(&prepared)
	closed, _ = registry_close(&registry)
	root_closed, _ := view.close(&views, &root_view)
	views_closed, _ := view.registry_close(&views)
	buffer_closed, _ := editor.buffer_close(&buffer)
	testing.expect(t, aborted && closed && root_closed && views_closed && buffer_closed)
}
