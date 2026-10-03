// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package layout

import "../editor"
import "../view"
import "core:testing"

/* Verifies resize publishes exact spans at the nearest compatible divider. */
@(test)
resize_pane_moves_only_the_nearest_divider :: proc(t: ^testing.T) {
	buffer: editor.Buffer
	views: view.Registry
	root_view: view.View_Handle
	registry: Registry
	ready := geometry_test_registry(20_104, 18, 51, &buffer, &views, &root_view, &registry)
	testing.expect(t, ready)
	if !ready {
		return
	}
	defer geometry_test_close(&buffer, &views, &root_view, &registry)
	handle, _, _ := registry_handle(&registry)
	initial, _, _ := registry_snapshot(&registry, handle)
	root_split, root_ok, _ := registry_split_below(&registry, initial.active_pane)
	_, focus_ok, _ := registry_focus(&registry, root_split.created)
	handle, _, _ = registry_handle(&registry)
	focused, _, _ := registry_snapshot(&registry, handle)
	middle_split, middle_ok, _ := registry_split_right(&registry, focused.active_pane)
	_, nested_ok, _ := registry_split_below(&registry, middle_split.original)
	testing.expect(t, root_ok && focus_ok && middle_ok && nested_ok)
	handle, _, _ = registry_handle(&registry)
	before, _, _ := registry_snapshot(&registry, handle)
	vertical, vertical_ok, _ := registry_resize_pane(
		&registry,
		before.active_pane,
		.Above_Below,
		1,
	)
	testing.expect(t, vertical_ok)
	testing.expect_value(t, vertical.first_span, i32(5))
	testing.expect_value(t, vertical.second_span, i32(4))
	vertical_snapshot, _, _ := registry_snapshot(&registry, vertical.layout)
	inner := resize_test_node(&vertical_snapshot, vertical.partition_id)
	testing.expect_value(t, inner.first_weight, u64(5))
	testing.expect_value(t, inner.second_weight, u64(4))
	horizontal, horizontal_ok, _ := registry_resize_pane(
		&registry,
		vertical.pane,
		.Left_Right,
		1,
	)
	testing.expect(t, horizontal_ok)
	testing.expect_value(t, horizontal.first_span, i32(26))
	testing.expect_value(t, horizontal.second_span, i32(24))
	horizontal_snapshot, _, _ := registry_snapshot(&registry, horizontal.layout)
	middle := resize_test_node(&horizontal_snapshot, horizontal.partition_id)
	inner = resize_test_node(&horizontal_snapshot, vertical.partition_id)
	root := resize_test_node(&horizontal_snapshot, horizontal_snapshot.root_id)
	testing.expect_value(t, middle.first_weight, u64(26))
	testing.expect_value(t, middle.second_weight, u64(24))
	testing.expect_value(t, inner.first_weight, u64(5))
	testing.expect_value(t, inner.second_weight, u64(4))
	testing.expect_value(t, root.first_weight, u64(1))
	testing.expect_value(t, root.second_weight, u64(1))
}

/* Verifies blocked and absent compatible dividers reject without publication. */
@(test)
resize_pane_rejection_is_atomic :: proc(t: ^testing.T) {
	buffer: editor.Buffer
	views: view.Registry
	root_view: view.View_Handle
	registry: Registry
	ready := geometry_test_registry(20_105, 12, 40, &buffer, &views, &root_view, &registry)
	testing.expect(t, ready)
	if !ready {
		return
	}
	defer geometry_test_close(&buffer, &views, &root_view, &registry)
	handle, _, _ := registry_handle(&registry)
	initial, _, _ := registry_snapshot(&registry, handle)
	_, root_ok, _ := registry_split_below(&registry, initial.active_pane)
	handle, _, _ = registry_handle(&registry)
	two, _, _ := registry_snapshot(&registry, handle)
	_, nested_ok, _ := registry_split_below(&registry, two.active_pane)
	testing.expect(t, root_ok && nested_ok)
	handle, _, _ = registry_handle(&registry)
	before, _, _ := registry_snapshot(&registry, handle)
	_, moved, minimum_failure := registry_resize_pane(
		&registry,
		before.active_pane,
		.Above_Below,
		1,
	)
	testing.expect(t, !moved)
	testing.expect_value(t, minimum_failure.code, Failure_Code.Operating_Minimum)
	handle, _, _ = registry_handle(&registry)
	after, _, _ := registry_snapshot(&registry, handle)
	testing.expect_value(t, after, before)
	absent_failure: Failure_Context
	_, moved, absent_failure = registry_resize_pane(
		&registry,
		before.active_pane,
		.Left_Right,
		1,
	)
	testing.expect(t, !moved)
	testing.expect_value(t, absent_failure.code, Failure_Code.No_Compatible_Divider)
	handle, _, _ = registry_handle(&registry)
	after, _, _ = registry_snapshot(&registry, handle)
	testing.expect_value(t, after, before)
}

/* Verifies signed motion and stale or malformed requests preserve exact state. */
@(test)
resize_pane_checks_direction_generation :: proc(t: ^testing.T) {
	buffer: editor.Buffer
	views: view.Registry
	root_view: view.View_Handle
	registry: Registry
	ready := geometry_test_registry(20_107, 10, 42, &buffer, &views, &root_view, &registry)
	testing.expect(t, ready)
	if !ready {
		return
	}
	defer geometry_test_close(&buffer, &views, &root_view, &registry)
	handle, _, _ := registry_handle(&registry)
	initial, _, _ := registry_snapshot(&registry, handle)
	stale := initial.active_pane
	split, split_ok, _ := registry_split_right(&registry, initial.active_pane)
	focused, focus_ok, _ := registry_focus(&registry, split.created)
	testing.expect(t, split_ok && focus_ok)
	if !split_ok || !focus_ok {
		return
	}
	before, _, _ := registry_snapshot(&registry, focused.layout)
	shrunk, shrunk_ok, _ := registry_resize_pane(
		&registry,
		before.active_pane,
		.Left_Right,
		-1,
	)
	testing.expect(t, shrunk_ok)
	testing.expect_value(t, shrunk.first_span, i32(21))
	testing.expect_value(t, shrunk.second_span, i32(20))
	after_shrink, _, _ := registry_snapshot(&registry, shrunk.layout)
	_, stale_ok, stale_failure := registry_resize_pane(
		&registry,
		stale,
		.Left_Right,
		1,
	)
	_, invalid_ok, invalid_failure := registry_resize_pane(
		&registry,
		after_shrink.active_pane,
		.Left_Right,
		2,
	)
	current, current_ok, _ := registry_snapshot(&registry, shrunk.layout)
	testing.expect(t, !stale_ok && !invalid_ok && current_ok)
	testing.expect_value(t, stale_failure.code, Failure_Code.Stale_Layout)
	testing.expect_value(t, invalid_failure.code, Failure_Code.Invalid_Geometry)
	testing.expect_value(t, current, after_shrink)
}

@(private)
resize_test_node :: proc(snapshot: ^Snapshot, id: Node_ID) -> Node_Descriptor {
	for node in snapshot.nodes[:snapshot.node_count] {
		if node.node_id == id {
			return node
		}
	}
	return {}
}
