// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package layout

import "../editor"
import "../view"
import "core:testing"

/* Verifies dimensional balance preserves topology and favors orthogonal full spans. */
@(test)
balance_panes_uses_topology_dimension_units :: proc(t: ^testing.T) {
	buffer: editor.Buffer
	views: view.Registry
	root_view: view.View_Handle
	registry: Registry
	ready := geometry_test_registry(20_106, 18, 51, &buffer, &views, &root_view, &registry)
	testing.expect(t, ready)
	if !ready {
		return
	}
	defer geometry_test_close(&buffer, &views, &root_view, &registry)
	handle, _, _ := registry_handle(&registry)
	initial, _, _ := registry_snapshot(&registry, handle)
	root_split, root_ok, _ := registry_split_below(&registry, initial.active_pane)
	_, focus_bottom_ok, _ := registry_focus(&registry, root_split.created)
	handle, _, _ = registry_handle(&registry)
	focused_bottom, _, _ := registry_snapshot(&registry, handle)
	_, bottom_split_ok, _ := registry_split_right(&registry, focused_bottom.active_pane)
	handle, _, _ = registry_handle(&registry)
	bottom_split, _, _ := registry_snapshot(&registry, handle)
	top := balance_test_pane(&bottom_split, Pane_ID(1))
	_, focus_top_ok, _ := registry_focus(&registry, top)
	handle, _, _ = registry_handle(&registry)
	focused_top, _, _ := registry_snapshot(&registry, handle)
	_, top_split_ok, _ := registry_split_below(&registry, focused_top.active_pane)
	testing.expect(t, root_ok && focus_bottom_ok && bottom_split_ok && focus_top_ok && top_split_ok)
	handle, _, _ = registry_handle(&registry)
	before, _, _ := registry_snapshot(&registry, handle)
	balanced, balanced_ok, _ := registry_balance_panes(&registry, before.handle)
	testing.expect(t, balanced_ok && balanced.changed)
	after, _, _ := registry_snapshot(&registry, balanced.layout)
	testing.expect_value(t, after.root_id, before.root_id)
	testing.expect_value(t, after.node_count, before.node_count)
	testing.expect_value(t, after.active_pane.pane_id, before.active_pane.pane_id)
	root := snapshot_node(&after, after.root_id)
	testing.expect_value(t, root.first_weight, u64(12))
	testing.expect_value(t, root.second_weight, u64(6))
	first := snapshot_node(&after, root.first_child_id)
	second := snapshot_node(&after, root.second_child_id)
	testing.expect_value(t, first.first_weight, u64(6))
	testing.expect_value(t, first.second_weight, u64(6))
	testing.expect_value(t, second.first_weight, u64(25))
	testing.expect_value(t, second.second_weight, u64(25))
	for pane_id in Pane_ID(1) ..= Pane_ID(4) {
		pane := balance_test_pane_node(&after, pane_id)
		testing.expect_value(t, pane.geometry.outer.height, i32(6))
	}
	testing.expect_value(t, balance_test_pane_node(&after, Pane_ID(1)).geometry.outer.width, i32(51))
	testing.expect_value(t, balance_test_pane_node(&after, Pane_ID(4)).geometry.outer.width, i32(51))
	testing.expect_value(t, balance_test_pane_node(&after, Pane_ID(2)).geometry.outer.width, i32(25))
	testing.expect_value(t, balance_test_pane_node(&after, Pane_ID(3)).geometry.outer.width, i32(25))
	repeated, repeated_ok, _ := registry_balance_panes(&registry, after.handle)
	testing.expect(t, repeated_ok && !repeated.changed)
	testing.expect_value(t, repeated.layout, after.handle)
}

/* Verifies odd-span ties resolve deterministically and remain stable. */
@(test)
panes_persists_deterministic_odd_rounding :: proc(t: ^testing.T) {
	buffer: editor.Buffer
	views: view.Registry
	root_view: view.View_Handle
	registry: Registry
	ready := geometry_test_registry(20_108, 10, 42, &buffer, &views, &root_view, &registry)
	testing.expect(t, ready)
	if !ready {
		return
	}
	defer geometry_test_close(&buffer, &views, &root_view, &registry)
	handle, _, _ := registry_handle(&registry)
	initial, _, _ := registry_snapshot(&registry, handle)
	split, split_ok, _ := registry_split_right(&registry, initial.active_pane)
	testing.expect(t, split_ok)
	if !split_ok {
		return
	}
	resized, resized_ok, _ := registry_resize_pane(
		&registry,
		split.original,
		.Left_Right,
		1,
	)
	testing.expect(t, resized_ok)
	balanced, balanced_ok, _ := registry_balance_panes(&registry, resized.layout)
	testing.expect(t, balanced_ok && balanced.changed)
	after, _, _ := registry_snapshot(&registry, balanced.layout)
	root := snapshot_node(&after, after.root_id)
	first := snapshot_node(&after, root.first_child_id)
	second := snapshot_node(&after, root.second_child_id)
	testing.expect_value(t, root.first_weight, u64(20))
	testing.expect_value(t, root.second_weight, u64(21))
	testing.expect_value(t, first.geometry.outer.width, i32(20))
	testing.expect_value(t, second.geometry.outer.width, i32(21))
	repeated, repeated_ok, _ := registry_balance_panes(&registry, after.handle)
	testing.expect(t, repeated_ok && !repeated.changed)
	testing.expect_value(t, repeated.layout, after.handle)
}

/* Verifies stale, work-limit, and generation-limit failures publish nothing. */
@(test)
balance_panes_limit_failures_are_atomic :: proc(t: ^testing.T) {
	buffer: editor.Buffer
	views: view.Registry
	root_view: view.View_Handle
	registry: Registry
	ready := geometry_test_registry(20_109, 10, 42, &buffer, &views, &root_view, &registry)
	testing.expect(t, ready)
	if !ready {
		return
	}
	defer geometry_test_close(&buffer, &views, &root_view, &registry)
	handle, _, _ := registry_handle(&registry)
	initial, _, _ := registry_snapshot(&registry, handle)
	stale := initial.handle
	split, split_ok, _ := registry_split_right(&registry, initial.active_pane)
	testing.expect(t, split_ok)
	if !split_ok {
		return
	}
	before, _, _ := registry_snapshot(&registry, split.layout)
	_, stale_ok, stale_failure := registry_balance_panes(&registry, stale)
	after_stale, _, _ := registry_snapshot(&registry, split.layout)
	testing.expect(t, !stale_ok)
	testing.expect_value(t, stale_failure.code, Failure_Code.Stale_Layout)
	testing.expect_value(t, after_stale, before)

	data := registry_data(&registry)
	data.policy.geometry_work = 1
	_, work_ok, work_failure := registry_balance_panes(&registry, split.layout)
	after_work, _, _ := registry_snapshot(&registry, split.layout)
	testing.expect(t, !work_ok)
	testing.expect_value(t, work_failure.code, Failure_Code.Geometry_Work_Limit)
	testing.expect_value(t, after_work, before)

	data.policy.geometry_work = DEFAULT_POLICY.geometry_work
	data.generation = Layout_Generation(max(u64))
	maximum := current_layout_handle(data)
	before_limit, before_limit_ok, _ := registry_snapshot(&registry, maximum)
	_, limit_ok, limit_failure := registry_balance_panes(&registry, maximum)
	after_limit, after_limit_ok, _ := registry_snapshot(&registry, maximum)
	testing.expect(t, before_limit_ok && !limit_ok && after_limit_ok)
	testing.expect_value(t, limit_failure.code, Failure_Code.Generation_Limit)
	testing.expect_value(t, after_limit, before_limit)
}

@(private)
balance_test_pane :: proc(snapshot: ^Snapshot, pane_id: Pane_ID) -> Pane_Handle {
	return balance_test_pane_node(snapshot, pane_id).pane
}

@(private)
balance_test_pane_node :: proc(snapshot: ^Snapshot, pane_id: Pane_ID) -> Node_Descriptor {
	for node in snapshot.nodes[:snapshot.node_count] {
		if node.kind == .Pane && node.pane.pane_id == pane_id {
			return node
		}
	}
	return {}
}
