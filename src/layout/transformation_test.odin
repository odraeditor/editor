// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package layout

import "../editor"
import "../view"
import "core:testing"

/* Verifies split copies view state while preserving active pane and MRU. */
@(test)
split_copies_state_and_mru_order :: proc(t: ^testing.T) {
	buffer: editor.Buffer
	views: view.Registry
	root_view: view.View_Handle
	registry: Registry
	ready := geometry_test_registry(20_201, 12, 40, &buffer, &views, &root_view, &registry)
	testing.expect(t, ready)
	if !ready {
		return
	}
	defer geometry_test_close(&buffer, &views, &root_view, &registry)
	handle, _, _ := registry_handle(&registry)
	before, _, _ := registry_snapshot(&registry, handle)
	result, split_ok, _ := registry_split_right(&registry, before.active_pane)
	testing.expect(t, split_ok)
	if !split_ok {
		return
	}
	after, after_ok, _ := registry_snapshot(&registry, result.layout)
	testing.expect(t, after_ok)
	testing.expect_value(t, after.node_count, u16(3))
	testing.expect_value(t, after.pane_count, u16(2))
	testing.expect_value(t, after.active_pane, result.original)
	original := snapshot_pane(&after, result.original.pane_id)
	created := snapshot_pane(&after, result.created.pane_id)
	testing.expect(t, original.active && !created.active)
	testing.expect_value(t, original.mru_rank, u16(0))
	testing.expect_value(t, created.mru_rank, u16(1))
	testing.expect_value(t, original.geometry.outer.width, i32(19))
	testing.expect_value(t, created.geometry.outer.width, i32(20))
	original_view, original_ok, _ := view.snapshot(&views, original.view)
	created_view, created_ok, _ := view.snapshot(&views, created.view)
	testing.expect(t, original_ok && created_ok && original.view != created.view)
	testing.expect_value(t, created_view.point_position, original_view.point_position)
	testing.expect_value(t, created_view.viewport_origin_position, original_view.viewport_origin_position)
	testing.expect_value(t, created_view.presentation_ownership, view.Presentation_Ownership.Additional)
}

/* Verifies focus synchronizes same-buffer points and rejects stale handles. */
@(test)
focus_syncs_points_and_rejects_stale :: proc(t: ^testing.T) {
	buffer: editor.Buffer
	views: view.Registry
	root_view: view.View_Handle
	registry: Registry
	ready := geometry_test_registry(20_202, 12, 40, &buffer, &views, &root_view, &registry)
	testing.expect(t, ready)
	if !ready {
		return
	}
	defer geometry_test_close(&buffer, &views, &root_view, &registry)
	handle, _, _ := registry_handle(&registry)
	initial, _, _ := registry_snapshot(&registry, handle)
	stale := initial.active_pane
	split, split_ok, _ := registry_split_right(&registry, initial.active_pane)
	testing.expect(t, split_ok)
	stored, _, _ := editor.buffer_position(&buffer, editor.Byte_Offset(2))
	effective, _, _ := editor.buffer_position(&buffer, editor.Byte_Offset(6))
	created_node_before := snapshot_pane_from_registry(&registry, split.layout, split.created.pane_id)
	created_set, _ := view.set_point(&views, created_node_before.view, stored)
	effective_set, _ := editor.buffer_selection_set_point(&buffer, effective)
	testing.expect(t, created_set && effective_set)
	focused, focus_ok, _ := registry_focus(&registry, split.created)
	testing.expect(t, focus_ok)
	after, after_ok, _ := registry_snapshot(&registry, focused.layout)
	testing.expect(t, after_ok)
	testing.expect_value(t, after.active_pane, focused.active)
	testing.expect_value(t, snapshot_pane(&after, focused.active.pane_id).mru_rank, u16(0))
	original_node := snapshot_pane(&after, split.original.pane_id)
	created_node := snapshot_pane(&after, split.created.pane_id)
	original_state, original_ok, _ := view.snapshot(&views, original_node.view)
	created_state, created_ok, _ := view.snapshot(&views, created_node.view)
	testing.expect(t, original_ok && created_ok)
	testing.expect_value(t, original_state.point_position.byte_offset, editor.Byte_Offset(6))
	testing.expect_value(t, created_state.point_position.byte_offset, editor.Byte_Offset(2))
	testing.expect_value(t, created_state.effective_point_position.byte_offset, editor.Byte_Offset(2))
	before_stale := after
	_, stale_ok, stale_failure := registry_focus(&registry, stale)
	current, current_ok, _ := registry_snapshot(&registry, focused.layout)
	testing.expect(t, !stale_ok && current_ok)
	testing.expect_value(t, stale_failure.code, Failure_Code.Stale_Layout)
	testing.expect_value(t, current, before_stale)
}

/* Verifies close collapses the parent, focuses MRU, and releases its view. */
@(test)
close_collapses_and_releases_view :: proc(t: ^testing.T) {
	buffer: editor.Buffer
	views: view.Registry
	root_view: view.View_Handle
	registry: Registry
	ready := geometry_test_registry(20_203, 12, 40, &buffer, &views, &root_view, &registry)
	testing.expect(t, ready)
	if !ready {
		return
	}
	defer geometry_test_close(&buffer, &views, &root_view, &registry)
	handle, _, _ := registry_handle(&registry)
	initial, _, _ := registry_snapshot(&registry, handle)
	split, split_ok, _ := registry_split_below(&registry, initial.active_pane)
	focused, focus_ok, _ := registry_focus(&registry, split.created)
	testing.expect(t, split_ok && focus_ok)
	closed, close_ok, _ := registry_close_pane(&registry, focused.active)
	testing.expect(t, close_ok)
	after, after_ok, _ := registry_snapshot(&registry, closed.layout)
	view_stats, view_stats_ok, _ := view.registry_stats(&views)
	testing.expect(t, after_ok && view_stats_ok)
	testing.expect_value(t, after.node_count, u16(1))
	testing.expect_value(t, after.pane_count, u16(1))
	testing.expect_value(t, after.active_pane.pane_id, split.original.pane_id)
	testing.expect_value(t, after.nodes[0].depth, u16(0))
	testing.expect_value(t, view_stats.live_count, u16(1))
	testing.expect_value(t, view_stats.additional_count, u16(0))
	before_final := after
	_, final_ok, final_failure := registry_close_pane(&registry, after.active_pane)
	current, current_ok, _ := registry_snapshot(&registry, closed.layout)
	testing.expect(t, !final_ok && current_ok)
	testing.expect_value(t, final_failure.code, Failure_Code.Final_Pane)
	testing.expect_value(t, current, before_final)
}

/* Verifies keep-only retains the active leaf and detaches primary state. */
@(test)
keep_only_detaches_primary_view :: proc(t: ^testing.T) {
	buffer: editor.Buffer
	views: view.Registry
	root_view: view.View_Handle
	registry: Registry
	ready := geometry_test_registry(20_204, 24, 80, &buffer, &views, &root_view, &registry)
	testing.expect(t, ready)
	if !ready {
		return
	}
	defer geometry_test_close(&buffer, &views, &root_view, &registry)
	handle, _, _ := registry_handle(&registry)
	initial, _, _ := registry_snapshot(&registry, handle)
	first_split, first_ok, _ := registry_split_below(&registry, initial.active_pane)
	focused, focus_ok, _ := registry_focus(&registry, first_split.created)
	second_split, second_ok, _ := registry_split_right(&registry, focused.active)
	testing.expect(t, first_ok && focus_ok && second_ok)
	kept, keep_ok, _ := registry_keep_only(&registry, second_split.original)
	testing.expect(t, keep_ok)
	after, after_ok, _ := registry_snapshot(&registry, kept.layout)
	view_stats, view_stats_ok, _ := view.registry_stats(&views)
	testing.expect(t, after_ok && view_stats_ok)
	testing.expect_value(t, after.node_count, u16(1))
	testing.expect_value(t, after.pane_count, u16(1))
	testing.expect_value(t, after.active_pane.pane_id, second_split.original.pane_id)
	testing.expect_value(t, after.nodes[0].depth, u16(0))
	testing.expect_value(t, after.nodes[0].geometry.outer, Rect{height = 24, width = 80})
	testing.expect_value(t, view_stats.live_count, u16(2))
	testing.expect_value(t, view_stats.retained_count, u16(1))
	testing.expect_value(t, view_stats.additional_count, u16(1))
}

/* Verifies split minimum rejection preserves layout and view accounting. */
@(test)
small_split_keeps_layout_and_views :: proc(t: ^testing.T) {
	buffer: editor.Buffer
	views: view.Registry
	root_view: view.View_Handle
	registry: Registry
	ready := geometry_test_registry(20_205, 4, 8, &buffer, &views, &root_view, &registry)
	testing.expect(t, ready)
	if !ready {
		return
	}
	defer geometry_test_close(&buffer, &views, &root_view, &registry)
	handle, _, _ := registry_handle(&registry)
	before, _, _ := registry_snapshot(&registry, handle)
	views_before, _, _ := view.registry_stats(&views)
	_, split_ok, split_failure := registry_split_right(&registry, before.active_pane)
	after, after_ok, _ := registry_snapshot(&registry, handle)
	views_after, views_after_ok, _ := view.registry_stats(&views)
	testing.expect(t, !split_ok && after_ok && views_after_ok)
	testing.expect_value(t, split_failure.code, Failure_Code.Operating_Minimum)
	testing.expect_value(t, after, before)
	testing.expect_value(t, views_after, views_before)
}

@(private)
snapshot_pane :: proc(snapshot: ^Snapshot, pane_id: Pane_ID) -> Node_Descriptor {
	for node in snapshot.nodes[:snapshot.node_count] {
		if node.kind == .Pane && node.pane.pane_id == pane_id {
			return node
		}
	}
	return {}
}

@(private)
snapshot_pane_from_registry :: proc(
	registry: ^Registry,
	handle: Layout_Handle,
	pane_id: Pane_ID,
) -> Node_Descriptor {
	snapshot, ok, _ := registry_snapshot(registry, handle)
	assert(ok)
	return snapshot_pane(&snapshot, pane_id)
}
