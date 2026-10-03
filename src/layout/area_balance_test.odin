// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package layout

import "../editor"
import "../view"
import "core:testing"
import "core:time"

@(private)
AREA_BALANCE_DEMANDING_LATENCY_GATE_NS :: i64(25_000_000)

/* Verifies exact area balance differs from ordinary dimensional balance. */
@(test)
balance_minimizes_leaf_area_difference :: proc(t: ^testing.T) {
	buffer: editor.Buffer
	views: view.Registry
	root_view: view.View_Handle
	registry: Registry
	ready := geometry_test_registry(20_110, 18, 33, &buffer, &views, &root_view, &registry)
	testing.expect(t, ready)
	if !ready {
		return
	}
	defer geometry_test_close(&buffer, &views, &root_view, &registry)
	handle, _, _ := registry_handle(&registry)
	initial, _, _ := registry_snapshot(&registry, handle)
	below, below_ok, _ := registry_split_below(&registry, initial.active_pane)
	_, right_ok, _ := registry_split_right(&registry, below.original)
	testing.expect(t, below_ok && right_ok)
	if !below_ok || !right_ok {
		return
	}
	handle, _, _ = registry_handle(&registry)
	before, _, _ := registry_snapshot(&registry, handle)
	balanced, balanced_ok, balance_failure := registry_balance_pane_areas(&registry, before.handle)
	testing.expectf(
		t,
		balanced_ok && balanced.changed,
		"area balance failed with %v maximum=%d actual=%d",
		balance_failure.code,
		balance_failure.maximum,
		balance_failure.actual,
	)
	after, _, _ := registry_snapshot(&registry, balanced.layout)
	testing.expect_value(t, after.root_id, before.root_id)
	testing.expect_value(t, after.active_pane.pane_id, before.active_pane.pane_id)
	root := snapshot_node(&after, after.root_id)
	testing.expect_value(t, root.first_weight, u64(12))
	testing.expect_value(t, root.second_weight, u64(6))
	upper := snapshot_node(&after, root.first_child_id)
	testing.expect_value(t, upper.first_weight, u64(16))
	testing.expect_value(t, upper.second_weight, u64(16))
	first_area := rect_area(snapshot_node(&after, upper.first_child_id).geometry.outer)
	second_area := rect_area(snapshot_node(&after, upper.second_child_id).geometry.outer)
	third_area := rect_area(snapshot_node(&after, root.second_child_id).geometry.outer)
	testing.expect_value(t, first_area, u64(192))
	testing.expect_value(t, second_area, u64(192))
	testing.expect_value(t, third_area, u64(198))
}

/* Verifies symmetric ties favor the ordered second child and then remain stable. */
@(test)
balance_pane_areas_persists_deterministic_ties :: proc(t: ^testing.T) {
	buffer: editor.Buffer
	views: view.Registry
	root_view: view.View_Handle
	registry: Registry
	ready := geometry_test_registry(20_111, 6, 18, &buffer, &views, &root_view, &registry)
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
	balanced, balanced_ok, balance_failure := registry_balance_pane_areas(&registry, split.layout)
	testing.expectf(
		t,
		balanced_ok,
		"area balance failed with %v maximum=%d actual=%d",
		balance_failure.code,
		balance_failure.maximum,
		balance_failure.actual,
	)
	after, _, _ := registry_snapshot(&registry, balanced.layout)
	root := snapshot_node(&after, after.root_id)
	testing.expect_value(t, root.first_weight, u64(8))
	testing.expect_value(t, root.second_weight, u64(9))
	repeated, repeated_ok, _ := registry_balance_pane_areas(&registry, after.handle)
	testing.expect(t, repeated_ok && !repeated.changed)
	testing.expect_value(t, repeated.layout, after.handle)
}

/* Verifies a generated demanding tree balances within selected work and latency gates. */
@(test)
balance_handles_generated_tree :: proc(t: ^testing.T) {
	buffer: editor.Buffer
	views: view.Registry
	root_view: view.View_Handle
	registry: Registry
	ready := geometry_test_registry(20_112, 16, 35, &buffer, &views, &root_view, &registry)
	testing.expect(t, ready)
	if !ready {
		return
	}
	defer geometry_test_close(&buffer, &views, &root_view, &registry)
	for _ in 0 ..< 15 {
		handle, _, _ := registry_handle(&registry)
		snapshot, snapshot_ok, _ := registry_snapshot(&registry, handle)
		target := area_balance_shallowest_pane(&snapshot)
		_, focus_ok, _ := registry_focus(&registry, target.pane)
		handle, _, _ = registry_handle(&registry)
		focused, _, _ := registry_snapshot(&registry, handle)
		split_ok: bool
		if target.depth & 1 == 0 {
			_, split_ok, _ = registry_split_below(&registry, focused.active_pane)
		} else {
			_, split_ok, _ = registry_split_right(&registry, focused.active_pane)
		}
		testing.expect(t, snapshot_ok && focus_ok && split_ok)
		if !snapshot_ok || !focus_ok || !split_ok {
			return
		}
	}
	handle, _, _ := registry_handle(&registry)
	before, before_ok, _ := registry_snapshot(&registry, handle)
	started := time.tick_now()
	balanced, balanced_ok, balance_failure := registry_balance_pane_areas(&registry, handle)
	elapsed_ns := time.duration_nanoseconds(time.tick_since(started))
	stats, stats_ok, _ := registry_stats(&registry)
	testing.expectf(
		t,
		before_ok && balanced_ok && stats_ok,
		"generated area balance failed with %v maximum=%d actual=%d",
		balance_failure.code,
		balance_failure.maximum,
		balance_failure.actual,
	)
	if !before_ok || !balanced_ok || !stats_ok {
		return
	}
	after, after_ok, _ := registry_snapshot(&registry, balanced.layout)
	testing.expect(t, after_ok)
	testing.expect_value(t, after.root_id, before.root_id)
	testing.expect_value(t, after.node_count, u16(31))
	testing.expect_value(t, after.pane_count, u16(16))
	testing.expect_value(t, after.partition_count, u16(15))
	testing.expect_value(t, stats.geometry_work, u64(139))
	testing.expect(t, elapsed_ns <= AREA_BALANCE_DEMANDING_LATENCY_GATE_NS)
	repeated, repeated_ok, _ := registry_balance_pane_areas(&registry, after.handle)
	testing.expect(t, repeated_ok && !repeated.changed)
	testing.expect_value(t, repeated.layout, after.handle)
}

/* Verifies stale, work, insufficient-geometry, and generation failures are atomic. */
@(test)
balance_pane_areas_limit_failures_are_atomic :: proc(t: ^testing.T) {
	buffer: editor.Buffer
	views: view.Registry
	root_view: view.View_Handle
	registry: Registry
	ready := geometry_test_registry(20_113, 10, 42, &buffer, &views, &root_view, &registry)
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
	_, stale_ok, stale_failure := registry_balance_pane_areas(&registry, stale)
	after_stale, _, _ := registry_snapshot(&registry, split.layout)
	testing.expect(t, !stale_ok)
	testing.expect_value(t, stale_failure.code, Failure_Code.Stale_Layout)
	testing.expect_value(t, after_stale, before)

	data := registry_data(&registry)
	data.policy.geometry_work = 1
	_, work_ok, work_failure := registry_balance_pane_areas(&registry, split.layout)
	after_work, _, _ := registry_snapshot(&registry, split.layout)
	testing.expect(t, !work_ok)
	testing.expect_value(t, work_failure.code, Failure_Code.Geometry_Work_Limit)
	testing.expect_value(t, after_work, before)
	data.policy.geometry_work = DEFAULT_POLICY.geometry_work

	shrunk, shrink_ok, _ := registry_materialize(
		&registry,
		split.layout,
		Geometry_Request{rows = 2, columns = 2},
		.External_Shrink,
	)
	insufficient, insufficient_ok, _ := registry_snapshot(&registry, shrunk)
	_, area_ok, area_failure := registry_balance_pane_areas(&registry, shrunk)
	after_insufficient, after_insufficient_ok, _ := registry_snapshot(&registry, shrunk)
	testing.expect(t, shrink_ok && insufficient_ok && !area_ok && after_insufficient_ok)
	testing.expect_value(t, insufficient.geometry_state, Geometry_State.Insufficient)
	testing.expect_value(t, area_failure.code, Failure_Code.Semantic_Insufficient)
	testing.expect_value(t, after_insufficient, insufficient)

	recovered, recover_ok, _ := registry_materialize(
		&registry,
		shrunk,
		Geometry_Request{rows = 10, columns = 42},
		.External_Shrink,
	)
	testing.expect(t, recover_ok)
	data.generation = Layout_Generation(max(u64))
	maximum := current_layout_handle(data)
	before_limit, before_limit_ok, _ := registry_snapshot(&registry, maximum)
	_, limit_ok, limit_failure := registry_balance_pane_areas(&registry, maximum)
	after_limit, after_limit_ok, _ := registry_snapshot(&registry, maximum)
	testing.expect(t, recovered.layout_id == maximum.layout_id)
	testing.expect(t, before_limit_ok && !limit_ok && after_limit_ok)
	testing.expect_value(t, limit_failure.code, Failure_Code.Generation_Limit)
	testing.expect_value(t, after_limit, before_limit)
}

@(private)
area_balance_shallowest_pane :: proc(snapshot: ^Snapshot) -> Node_Descriptor {
	selected: Node_Descriptor
	selected_depth := max(u16)
	for node in snapshot.nodes[:snapshot.node_count] {
		if node.kind == .Pane && node.depth < selected_depth {
			selected = node
			selected_depth = node.depth
		}
	}
	return selected
}
