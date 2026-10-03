// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package layout

import "../editor"
import "../view"
import "core:testing"

/* Verifies nested integer geometry, status rows, separators, and rounding. */
@(test)
nested_geometry_uses_exact_rounding_status_rows :: proc(t: ^testing.T) {
	buffer: editor.Buffer
	views: view.Registry
	root_view: view.View_Handle
	registry: Registry
	ready := geometry_test_registry(20_101, 11, 21, &buffer, &views, &root_view, &registry)
	testing.expect(t, ready)
	if !ready {
		return
	}
	defer geometry_test_close(&buffer, &views, &root_view, &registry)
	geometry_test_install_three_pane_tree(&registry, 1, 1, 1, 1)
	handle, _, _ := registry_handle(&registry)
	materialized, materialize_ok, _ := registry_materialize(
		&registry,
		handle,
		Geometry_Request{rows = 11, columns = 21},
	)
	testing.expect(t, materialize_ok)
	if !materialize_ok {
		return
	}
	snapshot, snapshot_ok, _ := registry_snapshot(&registry, materialized)
	testing.expect(t, snapshot_ok)
	testing.expect_value(t, snapshot.geometry_state, Geometry_State.Operating)
	testing.expect_value(t, snapshot.node_count, u16(5))
	first := snapshot_node(&snapshot, Node_ID(2))
	second_partition := snapshot_node(&snapshot, Node_ID(3))
	second := snapshot_node(&snapshot, Node_ID(4))
	third := snapshot_node(&snapshot, Node_ID(5))
	testing.expect_value(t, first.geometry.outer, Rect{height = 5, width = 21})
	testing.expect_value(t, first.geometry.content.height, i32(3))
	testing.expect_value(t, first.geometry.status.row, i32(3))
	testing.expect_value(t, second_partition.geometry.outer, Rect{row = 5, height = 6, width = 21})
	testing.expect_value(t, second_partition.geometry.separator, Rect{row = 5, column = 10, height = 6, width = 1})
	testing.expect_value(t, second.geometry.outer, Rect{row = 5, height = 6, width = 10})
	testing.expect_value(t, third.geometry.outer, Rect{row = 5, column = 11, height = 6, width = 10})
}

/* Verifies minimum clamping does not rewrite exact partition weights. */
@(test)
clamps_effective_spans_without_rewriting_weights :: proc(t: ^testing.T) {
	buffer: editor.Buffer
	views: view.Registry
	root_view: view.View_Handle
	registry: Registry
	ready := geometry_test_registry(20_102, 8, 18, &buffer, &views, &root_view, &registry)
	testing.expect(t, ready)
	if !ready {
		return
	}
	defer geometry_test_close(&buffer, &views, &root_view, &registry)
	geometry_test_install_two_pane_tree(&registry, .Left_Right, 1, 9)
	handle, _, _ := registry_handle(&registry)
	materialized, materialize_ok, _ := registry_materialize(
		&registry,
		handle,
		Geometry_Request{rows = 8, columns = 18},
	)
	testing.expect(t, materialize_ok)
	snapshot, snapshot_ok, _ := registry_snapshot(&registry, materialized)
	testing.expect(t, snapshot_ok)
	root := snapshot_node(&snapshot, Node_ID(1))
	first := snapshot_node(&snapshot, Node_ID(2))
	second := snapshot_node(&snapshot, Node_ID(3))
	testing.expect_value(t, root.first_weight, u64(1))
	testing.expect_value(t, root.second_weight, u64(9))
	testing.expect_value(t, first.geometry.outer.width, i32(8))
	testing.expect_value(t, second.geometry.outer.width, i32(9))
}

/* Verifies external shrink distinguishes semantic and insufficient states. */
@(test)
external_shrink_distinguishes_semantic :: proc(t: ^testing.T) {
	buffer: editor.Buffer
	views: view.Registry
	root_view: view.View_Handle
	registry: Registry
	ready := geometry_test_registry(20_103, 8, 24, &buffer, &views, &root_view, &registry)
	testing.expect(t, ready)
	if !ready {
		return
	}
	defer geometry_test_close(&buffer, &views, &root_view, &registry)
	geometry_test_install_two_pane_tree(&registry, .Left_Right, 1, 1)
	handle, _, _ := registry_handle(&registry)
	semantic, semantic_ok, _ := registry_materialize(
		&registry,
		handle,
		Geometry_Request{rows = 3, columns = 3},
		.External_Shrink,
	)
	testing.expect(t, semantic_ok)
	semantic_snapshot, semantic_snapshot_ok, _ := registry_snapshot(&registry, semantic)
	testing.expect(t, semantic_snapshot_ok)
	testing.expect_value(t, semantic_snapshot.geometry_state, Geometry_State.Semantic)
	insufficient, insufficient_ok, _ := registry_materialize(
		&registry,
		semantic,
		Geometry_Request{rows = 3, columns = 2},
		.External_Shrink,
	)
	testing.expect(t, insufficient_ok)
	insufficient_snapshot, insufficient_snapshot_ok, _ := registry_snapshot(&registry, insufficient)
	testing.expect(t, insufficient_snapshot_ok)
	testing.expect_value(t, insufficient_snapshot.geometry_state, Geometry_State.Insufficient)
	testing.expect_value(t, insufficient_snapshot.nodes[1].geometry, Pane_Geometry{})
}

@(private)
geometry_test_registry :: proc(
	id: u64,
	rows, columns: i32,
	buffer: ^editor.Buffer,
	views: ^view.Registry,
	root_view: ^view.View_Handle,
	registry: ^Registry,
) -> bool {
	buffer_ok, _ := editor.buffer_init(
		buffer,
		editor.Buffer_ID(id),
		"geometry",
		editor.Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	views_ok, _ := view.registry_init(views, view.Registry_ID(u32(id)), context.allocator)
	created_view, root_ok, _ := view.create(views, buffer)
	root_view^ = created_view
	registry_ok, _ := registry_init(
		registry,
		Owner_ID(id),
		Layout_ID(id),
		views,
		root_view^,
		Geometry_Request{rows = rows, columns = columns},
	)
	return buffer_ok && views_ok && root_ok && registry_ok
}

@(private)
geometry_test_close :: proc(
	buffer: ^editor.Buffer,
	views: ^view.Registry,
	root_view: ^view.View_Handle,
	registry: ^Registry,
) {
	registry_closed, _ := registry_close(registry)
	root_closed, _ := view.close(views, root_view)
	views_closed, _ := view.registry_close(views)
	buffer_closed, _ := editor.buffer_close(buffer)
	assert(registry_closed)
	assert(root_closed)
	assert(views_closed)
	assert(buffer_closed)
}

@(private)
geometry_test_install_two_pane_tree :: proc(
	registry: ^Registry,
	arrangement: Arrangement,
	first_weight, second_weight: u64,
) {
	data := registry_data(registry)
	assert(data != nil)
	root_view := data.nodes[0].view
	buffer_id := data.nodes[0].buffer_id
	data.nodes[0] = Node_Slot {
		live = true,
		kind = .Partition,
		node_id = Node_ID(1),
		generation = 1,
		arrangement = arrangement,
		first = Node_Ref{slot = 1, generation = 1},
		second = Node_Ref{slot = 2, generation = 1},
		first_weight = first_weight,
		second_weight = second_weight,
	}
	data.nodes[1] = Node_Slot {
		live = true,
		kind = .Pane,
		node_id = Node_ID(2),
		generation = 1,
		parent = data.root,
		depth = 1,
		pane_id = Pane_ID(1),
		view = root_view,
		buffer_id = buffer_id,
	}
	data.nodes[2] = Node_Slot {
		live = true,
		kind = .Pane,
		node_id = Node_ID(3),
		generation = 1,
		parent = data.root,
		depth = 1,
		pane_id = Pane_ID(2),
		view = root_view,
		buffer_id = buffer_id,
	}
	data.active = Node_Ref{slot = 1, generation = 1}
	data.mru[0] = data.active
	data.mru[1] = Node_Ref{slot = 2, generation = 1}
	data.mru_count = 2
	data.node_count = 3
	data.pane_count = 2
	data.partition_count = 1
	data.next_node_id = Node_ID(4)
	data.next_pane_id = Pane_ID(3)
}

@(private)
geometry_test_install_three_pane_tree :: proc(
	registry: ^Registry,
	root_first, root_second, nested_first, nested_second: u64,
) {
	geometry_test_install_two_pane_tree(registry, .Above_Below, root_first, root_second)
	data := registry_data(registry)
	second_view := data.nodes[2].view
	buffer_id := data.nodes[2].buffer_id
	second_partition := Node_Ref{slot = 2, generation = 1}
	data.nodes[2] = Node_Slot {
		live = true,
		kind = .Partition,
		node_id = Node_ID(3),
		generation = 1,
		parent = data.root,
		depth = 1,
		arrangement = .Left_Right,
		first = Node_Ref{slot = 3, generation = 1},
		second = Node_Ref{slot = 4, generation = 1},
		first_weight = nested_first,
		second_weight = nested_second,
	}
	data.nodes[3] = Node_Slot {
		live = true,
		kind = .Pane,
		node_id = Node_ID(4),
		generation = 1,
		parent = second_partition,
		depth = 2,
		pane_id = Pane_ID(2),
		view = second_view,
		buffer_id = buffer_id,
	}
	data.nodes[4] = Node_Slot {
		live = true,
		kind = .Pane,
		node_id = Node_ID(5),
		generation = 1,
		parent = second_partition,
		depth = 2,
		pane_id = Pane_ID(3),
		view = second_view,
		buffer_id = buffer_id,
	}
	data.mru[1] = Node_Ref{slot = 3, generation = 1}
	data.mru[2] = Node_Ref{slot = 4, generation = 1}
	data.mru_count = 3
	data.node_count = 5
	data.pane_count = 3
	data.partition_count = 2
	data.next_node_id = Node_ID(6)
	data.next_pane_id = Pane_ID(4)
}

@(private)
snapshot_node :: proc(snapshot: ^Snapshot, id: Node_ID) -> Node_Descriptor {
	for node in snapshot.nodes[:snapshot.node_count] {
		if node.node_id == id {
			return node
		}
	}
	return {}
}
