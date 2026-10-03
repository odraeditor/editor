// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package layout_reference

import editor "../../src/editor"
import layout "../../src/layout"
import view "../../src/view"
import "core:testing"

/* Verifies every bounded three-pane topology against the independent exact oracle. */
@(test)
area_balance_matches_oracle :: proc(t: ^testing.T) {
	arrangements := [?]Arrangement{.Above_Below, .Left_Right}
	case_id: u64
	for root_arrangement in arrangements {
		for target_pane in u64(1) ..= u64(2) {
			for nested_arrangement in arrangements {
				case_id += 1
				expect_area_balance_topology(
					t,
					30_100 + case_id,
					root_arrangement,
					target_pane,
					nested_arrangement,
				)
			}
		}
	}
}

/* Cross-checks generated tree traces against production layout behavior. */
@(test)
generated_tree_trace_matches_production_layout :: proc(t: ^testing.T) {
	model, model_ok := model_init(192, 512)
	buffer: editor.Buffer
	views: view.Registry
	root_view: view.View_Handle
	registry: layout.Registry
	production_ok := production_init(&buffer, &views, &root_view, &registry, 192, 512)
	testing.expect(t, model_ok && production_ok)
	if !model_ok || !production_ok {
		return
	}
	defer production_close(&buffer, &views, &root_view, &registry)
	seed := u64(0x6a09e667f3bcc909)
	for step in 0 ..< 1_024 {
		seed = seed * 6_364_136_223_846_793_005 + 1_442_695_040_888_963_407
		handle, handle_ok, _ := layout.registry_handle(&registry)
		before, before_ok, _ := layout.registry_snapshot(&registry, handle)
		testing.expect(t, handle_ok && before_ok)
		switch seed % 10 {
		case 0, 1:
			if model.pane_count < 24 {
				arrangement := Arrangement.Above_Below
				if seed & 1 != 0 {
					arrangement = .Left_Right
				}
				model_pane, model_split_ok := model_split(&model, arrangement)
				production_split: layout.Split_Result
				production_split_ok: bool
				if arrangement == .Above_Below {
					production_split, production_split_ok, _ =
						layout.registry_split_below(&registry, before.active_pane)
				} else {
					production_split, production_split_ok, _ =
						layout.registry_split_right(&registry, before.active_pane)
				}
				testing.expect_value(t, production_split_ok, model_split_ok)
				if model_split_ok && production_split_ok {
					testing.expect_value(t, u64(production_split.created.pane_id), model_pane)
				}
			}
		case 2, 3:
			pane_ids: [MAX_PANES]u64
			pane_count := model_pane_ids(&model, &pane_ids)
			target_id := pane_ids[int((seed >> 16) % u64(pane_count))]
			target, target_ok := production_pane(&before, target_id)
			model_focus_ok := model_focus(&model, target_id)
			_, production_focus_ok, _ := layout.registry_focus(&registry, target)
			testing.expect(t, target_ok)
			testing.expect_value(t, production_focus_ok, model_focus_ok)
		case 4:
			if model.pane_count > 1 {
				model_close_ok := model_close_active(&model)
				_, production_close_ok, _ := layout.registry_close_pane(&registry, before.active_pane)
				testing.expect_value(t, production_close_ok, model_close_ok)
			}
		case 5:
			if model.pane_count > 6 && step % 17 == 0 {
				model_keep_ok := model_keep_only(&model)
				_, production_keep_ok, _ := layout.registry_keep_only(&registry, before.active_pane)
				testing.expect_value(t, production_keep_ok, model_keep_ok)
			}
		case 6, 7:
			arrangement := Arrangement.Above_Below
			production_arrangement := layout.Arrangement.Above_Below
			if seed & 1 != 0 {
				arrangement = .Left_Right
				production_arrangement = .Left_Right
			}
			delta := i32(1)
			if seed & 2 != 0 {
				delta = -1
			}
			model_resize_ok := model_resize_active(&model, arrangement, delta)
			_, production_resize_ok, _ := layout.registry_resize_pane(
				&registry,
				before.active_pane,
				production_arrangement,
				delta,
			)
			testing.expect_value(t, production_resize_ok, model_resize_ok)
		case 8:
			model_balance_ok := model_balance_dimensions(&model)
			_, production_balance_ok, _ := layout.registry_balance_panes(&registry, before.handle)
			testing.expect_value(t, production_balance_ok, model_balance_ok)
		case 9:
			// Inspection-only steps ensure repeated snapshots are stable.
		}
		expect_production_matches_model(t, &model, &registry)
	}
}

/* Verifies external shrink preserves the model topology, rejects splits, and resumes exact geometry. */
@(test)
resize_recovery_keeps_topology :: proc(t: ^testing.T) {
	model, model_ok := model_init(11, 40)
	buffer: editor.Buffer
	views: view.Registry
	root_view: view.View_Handle
	registry: layout.Registry
	production_ok := production_init(&buffer, &views, &root_view, &registry, 11, 40)
	testing.expect(t, model_ok && production_ok)
	if !model_ok || !production_ok {
		return
	}
	defer production_close(&buffer, &views, &root_view, &registry)
	model_split(&model, .Above_Below)
	handle, _, _ := layout.registry_handle(&registry)
	initial, _, _ := layout.registry_snapshot(&registry, handle)
	first, first_ok, _ := layout.registry_split_below(&registry, initial.active_pane)
	model_split(&model, .Left_Right)
	_, second_ok, _ := layout.registry_split_right(&registry, first.original)
	testing.expect(t, first_ok && second_ok)
	expect_production_matches_model(t, &model, &registry)

	handle, _, _ = layout.registry_handle(&registry)
	shrunken_handle, shrunken_ok, _ := layout.registry_materialize(
		&registry,
		handle,
		layout.Geometry_Request {
			rows = 3,
			columns = 8,
			global_reserved_rows = 1,
		},
		.External_Shrink,
	)
	testing.expect(t, shrunken_ok)
	shrunken, _, _ := layout.registry_snapshot(&registry, shrunken_handle)
	testing.expect_value(t, shrunken.geometry_state, layout.Geometry_State.Insufficient)
	expect_production_topology_matches_model(t, &model, shrunken)
	before_rejection := shrunken
	_, split_ok, split_failure := layout.registry_split_right(&registry, shrunken.active_pane)
	testing.expect(t, !split_ok)
	testing.expect_value(t, split_failure.code, layout.Failure_Code.Operating_Minimum)
	handle, _, _ = layout.registry_handle(&registry)
	after_rejection, _, _ := layout.registry_snapshot(&registry, handle)
	testing.expect_value(t, after_rejection, before_rejection)

	recovered_handle, recovered_ok, _ := layout.registry_materialize(
		&registry,
		handle,
		layout.Geometry_Request{rows = 11, columns = 40},
		.External_Shrink,
	)
	testing.expect(t, recovered_ok)
	recovered, _, _ := layout.registry_snapshot(&registry, recovered_handle)
	testing.expect_value(t, recovered.geometry_state, layout.Geometry_State.Operating)
	expect_production_matches_model(t, &model, &registry)

	shrunken_handle, _, _ = layout.registry_materialize(
		&registry,
		recovered_handle,
		layout.Geometry_Request {
			rows = 4,
			columns = 8,
			global_reserved_rows = 1,
		},
		.External_Shrink,
	)
	shrunken, _, _ = layout.registry_snapshot(&registry, shrunken_handle)
	kept, kept_ok, _ := layout.registry_keep_only(&registry, shrunken.active_pane)
	testing.expect(t, kept_ok)
	one, _, _ := layout.registry_snapshot(&registry, kept.layout)
	testing.expect_value(t, one.pane_count, u16(1))
	testing.expect_value(t, one.geometry_state, layout.Geometry_State.Semantic)
}

@(private)
production_init :: proc(
	buffer: ^editor.Buffer,
	views: ^view.Registry,
	root_view: ^view.View_Handle,
	registry: ^layout.Registry,
	rows, columns: i32,
) -> bool {
	buffer_ok, _ := editor.buffer_init(
		buffer,
		editor.Buffer_ID(30_001),
		"layout-reference",
		editor.Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	views_ok, _ := view.registry_init(views, view.Registry_ID(30_001), context.allocator)
	created, root_ok, _ := view.create(views, buffer)
	root_view^ = created
	registry_ok, _ := layout.registry_init(
		registry,
		layout.Owner_ID(30_001),
		layout.Layout_ID(30_001),
		views,
		root_view^,
		layout.Geometry_Request{rows = rows, columns = columns},
	)
	return buffer_ok && views_ok && root_ok && registry_ok
}

@(private)
expect_area_balance_topology :: proc(
	t: ^testing.T,
	id: u64,
	root_arrangement: Arrangement,
	target_pane: u64,
	nested_arrangement: Arrangement,
) {
	model, model_ok := model_init(18, 33)
	buffer: editor.Buffer
	views: view.Registry
	root_view: view.View_Handle
	registry: layout.Registry
	production_ok := production_init(&buffer, &views, &root_view, &registry, 18, 33)
	testing.expect(t, model_ok && production_ok)
	if !model_ok || !production_ok {
		return
	}
	defer production_close(&buffer, &views, &root_view, &registry)

	_, model_root_ok := model_split(&model, root_arrangement)
	handle, _, _ := layout.registry_handle(&registry)
	initial, _, _ := layout.registry_snapshot(&registry, handle)
	production_root_ok: bool
	if root_arrangement == .Above_Below {
		_, production_root_ok, _ = layout.registry_split_below(&registry, initial.active_pane)
	} else {
		_, production_root_ok, _ = layout.registry_split_right(&registry, initial.active_pane)
	}
	handle, _, _ = layout.registry_handle(&registry)
	root_split, _, _ := layout.registry_snapshot(&registry, handle)
	target, target_ok := production_pane(&root_split, target_pane)
	model_focus_ok := model_focus(&model, target_pane)
	_, production_focus_ok, _ := layout.registry_focus(&registry, target)
	_, model_nested_ok := model_split(&model, nested_arrangement)
	handle, _, _ = layout.registry_handle(&registry)
	focused, _, _ := layout.registry_snapshot(&registry, handle)
	production_nested_ok: bool
	if nested_arrangement == .Above_Below {
		_, production_nested_ok, _ = layout.registry_split_below(&registry, focused.active_pane)
	} else {
		_, production_nested_ok, _ = layout.registry_split_right(&registry, focused.active_pane)
	}
	testing.expect(
		t,
		model_root_ok && production_root_ok && target_ok && model_focus_ok &&
			production_focus_ok && model_nested_ok && production_nested_ok,
	)
	if !model_root_ok || !production_root_ok || !target_ok || !model_focus_ok ||
	   !production_focus_ok || !model_nested_ok || !production_nested_ok {
		return
	}

	_, _, model_balance_ok := model_balance_areas_exact(&model)
	handle, _, _ = layout.registry_handle(&registry)
	_, production_balance_ok, production_failure :=
		layout.registry_balance_pane_areas(&registry, handle)
	testing.expectf(
		t,
		model_balance_ok && production_balance_ok,
		"area balance case %d failed with %v maximum=%d actual=%d",
		id,
		production_failure.code,
		production_failure.maximum,
		production_failure.actual,
	)
	if model_balance_ok && production_balance_ok {
		expect_production_matches_model(t, &model, &registry)
	}
}

@(private)
production_close :: proc(
	buffer: ^editor.Buffer,
	views: ^view.Registry,
	root_view: ^view.View_Handle,
	registry: ^layout.Registry,
) {
	layout_closed, _ := layout.registry_close(registry)
	root_closed, _ := view.close(views, root_view)
	views_closed, _ := view.registry_close(views)
	buffer_closed, _ := editor.buffer_close(buffer)
	assert(layout_closed && root_closed && views_closed && buffer_closed)
}

@(private)
production_pane :: proc(snapshot: ^layout.Snapshot, pane_id: u64) -> (layout.Pane_Handle, bool) {
	for node in snapshot.nodes[:snapshot.node_count] {
		if node.kind == .Pane && u64(node.pane.pane_id) == pane_id {
			return node.pane, true
		}
	}
	return {}, false
}

@(private)
expect_production_matches_model :: proc(
	t: ^testing.T,
	model: ^Model,
	registry: ^layout.Registry,
) {
	handle, handle_ok, _ := layout.registry_handle(registry)
	production, production_ok, _ := layout.registry_snapshot(registry, handle)
	reference, reference_ok := model_snapshot(model)
	testing.expect(t, handle_ok && production_ok && reference_ok)
	if !handle_ok || !production_ok || !reference_ok {
		return
	}
	testing.expect_value(t, u64(production.root_id), reference.root_id)
	testing.expect_value(t, u64(production.active_pane.pane_id), reference.active_pane_id)
	testing.expect_value(t, production.node_count, reference.node_count)
	testing.expect_value(t, production.pane_count, reference.pane_count)
	testing.expect_value(t, production.partition_count, reference.partition_count)
	for index in 0 ..< int(reference.node_count) {
		actual := production.nodes[index]
		expected := reference.nodes[index]
		testing.expect_value(t, production_kind(actual.kind), expected.kind)
		testing.expect_value(t, u64(actual.node_id), expected.id)
		testing.expect_value(t, u64(actual.parent_id), expected.parent_id)
		testing.expect_value(t, actual.depth, expected.depth)
		testing.expect_value(t, production_arrangement(actual.arrangement), expected.arrangement)
		testing.expect_value(t, u64(actual.first_child_id), expected.first_id)
		testing.expect_value(t, u64(actual.second_child_id), expected.second_id)
		testing.expect_value(t, actual.first_weight, expected.first_weight)
		testing.expect_value(t, actual.second_weight, expected.second_weight)
		testing.expect_value(t, u64(actual.pane.pane_id), expected.pane_id)
		testing.expect_value(t, production_geometry(actual.geometry), expected.geometry)
		testing.expect_value(t, actual.active, expected.active)
		if expected.kind == .Pane {
			testing.expect_value(t, actual.mru_rank, expected.mru_rank)
		}
	}
}

@(private)
expect_production_topology_matches_model :: proc(
	t: ^testing.T,
	model: ^Model,
	production: layout.Snapshot,
) {
	reference, reference_ok := model_snapshot(model)
	testing.expect(t, reference_ok)
	if !reference_ok {
		return
	}
	testing.expect_value(t, u64(production.root_id), reference.root_id)
	testing.expect_value(t, u64(production.active_pane.pane_id), reference.active_pane_id)
	testing.expect_value(t, production.node_count, reference.node_count)
	testing.expect_value(t, production.pane_count, reference.pane_count)
	for index in 0 ..< int(reference.node_count) {
		actual := production.nodes[index]
		expected := reference.nodes[index]
		testing.expect_value(t, production_kind(actual.kind), expected.kind)
		testing.expect_value(t, u64(actual.node_id), expected.id)
		testing.expect_value(t, u64(actual.parent_id), expected.parent_id)
		testing.expect_value(t, production_arrangement(actual.arrangement), expected.arrangement)
		testing.expect_value(t, u64(actual.first_child_id), expected.first_id)
		testing.expect_value(t, u64(actual.second_child_id), expected.second_id)
		testing.expect_value(t, u64(actual.pane.pane_id), expected.pane_id)
		testing.expect_value(t, actual.active, expected.active)
		testing.expect_value(t, actual.geometry, layout.Pane_Geometry{})
	}
}

@(private)
production_kind :: proc(kind: layout.Node_Kind) -> Kind {
	switch kind {
	case .Partition:
		return .Partition
	case .Pane:
		return .Pane
	case .Invalid:
		return .Invalid
	}
	return .Invalid
}

@(private)
production_arrangement :: proc(arrangement: layout.Arrangement) -> Arrangement {
	switch arrangement {
	case .Above_Below:
		return .Above_Below
	case .Left_Right:
		return .Left_Right
	case .Invalid:
		return .Invalid
	}
	return .Invalid
}

@(private)
production_rect :: proc(rect: layout.Rect) -> Rect {
	return Rect{row = rect.row, column = rect.column, height = rect.height, width = rect.width}
}

@(private)
production_geometry :: proc(geometry: layout.Pane_Geometry) -> Geometry {
	return Geometry {
		outer = production_rect(geometry.outer),
		content = production_rect(geometry.content),
		status = production_rect(geometry.status),
		separator = production_rect(geometry.separator),
	}
}
