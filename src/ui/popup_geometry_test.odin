// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ui

import "core:mem"
import "core:testing"

@(test)
/* Ensures one popup overlap composes without resizing its source surface. */
composes_one_overlap_without_resizing_source :: proc(t: ^testing.T) {
	registry: Registry
	initialized, _ := registry_init(&registry, Registry_ID(111))
	source_geometry := Cell_Rect{row = 2, column = 4, height = 10, width = 40}
	root, popup, source, published, _ := publish_anchor_test_popup(
		&registry, {}, .Cursor, source_geometry, false, popup_test_renderer(),
	)
	resolution, resolved, _ := registry_resolve_popup_anchor(&registry, popup)
	snapshot, copied, _ := registry_snapshot(&registry, root, popup_test_renderer())
	view, viewed := snapshot_view(&snapshot)

	testing.expect(t, initialized && published && resolved && copied && viewed)
	if viewed && len(view.popups) == 1 {
		geometry := view.popups[0].geometry
		testing.expect_value(t, geometry.state, Popup_Geometry_State.Placed)
		testing.expect_value(t, geometry.placement, Popup_Placement.Above)
		testing.expect_value(t, geometry.anchor, resolution.geometry)
		testing.expect_value(t, geometry.z_order, u8(1))
		testing.expect(t, geometry.obscures_underlay)
		testing.expect(t, cell_rect_contains(
			Cell_Rect{height = 80, width = 240}, geometry.outer,
		))
	}
	for snapshot_surface in view.surfaces {
		if snapshot_surface.handle == source {
			testing.expect_value(t, snapshot_surface.geometry, source_geometry)
		}
	}
	closed, _ := registry_close(&registry)
	snapshot_closed := !copied || snapshot_close(&snapshot)
	testing.expect(t, closed && snapshot_closed)
}

@(test)
/* Ensures narrow roots clip or fall back without leaving partial overlap. */
clips_or_falls_back_without_partial_overlap :: proc(t: ^testing.T) {
	clipped_renderer := popup_test_renderer()
	clipped_renderer.max_rows = 8
	clipped_renderer.max_columns = 12
	clipped_renderer.max_cells = 96
	clipped_registry: Registry
	clipped_initialized, _ := registry_init(&clipped_registry, Registry_ID(112))
	clipped_root, clipped_popup, _, clipped_published, _ := publish_anchor_test_popup(
		&clipped_registry,
		{},
		.Logical_Text,
		Cell_Rect{row = 0, column = 0, height = 8, width = 12},
		false,
		clipped_renderer,
	)
	clipped_snapshot, clipped_copied, _ := registry_snapshot(
		&clipped_registry, clipped_root, clipped_renderer,
	)
	clipped_view, clipped_viewed := snapshot_view(&clipped_snapshot)
	clipped_descriptor, clipped_inspected, _ := registry_inspect_popup(
		&clipped_registry, clipped_popup,
	)

	fallback_renderer := popup_test_renderer()
	fallback_renderer.max_rows = 3
	fallback_renderer.max_columns = 6
	fallback_renderer.max_cells = 18
	fallback_registry: Registry
	fallback_initialized, _ := registry_init(&fallback_registry, Registry_ID(113))
	fallback_root, _, _, fallback_published, _ := publish_anchor_test_popup(
		&fallback_registry,
		{},
		.Surface,
		Cell_Rect{row = 0, column = 0, height = 3, width = 6},
		false,
		fallback_renderer,
	)
	fallback_snapshot, fallback_copied, _ := registry_snapshot(
		&fallback_registry, fallback_root, fallback_renderer,
	)
	fallback_view, fallback_viewed := snapshot_view(&fallback_snapshot)

	testing.expect(
		t,
		clipped_initialized && clipped_published && clipped_copied && clipped_viewed &&
		clipped_inspected &&
		fallback_initialized && fallback_published && fallback_copied && fallback_viewed,
	)
	if clipped_viewed {
		testing.expect_value(t, clipped_descriptor.geometry.state, Popup_Geometry_State.Placed)
		testing.expect_value(t, clipped_view.popups[0].geometry.state, Popup_Geometry_State.Placed)
		testing.expect(t, clipped_view.popups[0].geometry.clipped)
	}
	if fallback_viewed {
		testing.expect_value(t, fallback_view.popups[0].geometry.state, Popup_Geometry_State.Fallback)
		testing.expect_value(t, fallback_view.popups[0].geometry.outer, Cell_Rect{})
	}
	clipped_closed, _ := registry_close(&clipped_registry)
	fallback_closed, _ := registry_close(&fallback_registry)
	clipped_snapshot_closed := !clipped_copied || snapshot_close(&clipped_snapshot)
	fallback_snapshot_closed := !fallback_copied || snapshot_close(&fallback_snapshot)
	testing.expect(
		t,
		clipped_closed && fallback_closed && clipped_snapshot_closed && fallback_snapshot_closed,
	)
}

@(test)
/* popup_geometry_resize_replaces_atomically_and_preserves_prior_snapshot. */
resize_keeps_prior_snapshot :: proc(t: ^testing.T) {
	registry: Registry
	initialized, _ := registry_init(&registry, Registry_ID(114))
	first_renderer := popup_test_renderer()
	first_renderer.max_rows = 24
	first_renderer.max_columns = 80
	first_renderer.max_cells = 1_920
	first, _, _, first_ok, _ := publish_anchor_test_popup(
		&registry,
		{},
		.Logical_Text,
		Cell_Rect{row = 2, column = 4, height = 10, width = 40},
		false,
		first_renderer,
	)
	first_snapshot, first_copied, _ := registry_snapshot(&registry, first, first_renderer)
	first_view, first_viewed := snapshot_view(&first_snapshot)

	second_renderer := popup_test_renderer()
	second_renderer.max_rows = 10
	second_renderer.max_columns = 32
	second_renderer.max_cells = 320
	second, _, _, second_ok, _ := publish_anchor_test_popup(
		&registry,
		first,
		.Logical_Text,
		Cell_Rect{row = 1, column = 1, height = 8, width = 30},
		false,
		second_renderer,
	)
	second_snapshot, second_copied, _ := registry_snapshot(&registry, second, second_renderer)
	second_view, second_viewed := snapshot_view(&second_snapshot)

	testing.expect(
		t,
		initialized && first_ok && first_copied && first_viewed && second_ok &&
		second_copied && second_viewed,
	)
	if first_viewed && second_viewed {
		first_geometry := first_view.popups[0].geometry
		second_geometry := second_view.popups[0].geometry
		testing.expect_value(t, first_view.root, first)
		testing.expect_value(t, second_view.root, second)
		testing.expect(t, first_geometry.outer != second_geometry.outer)
		testing.expect_value(t, first_view.popups[0].geometry, first_geometry)
	}
	closed, _ := registry_close(&registry)
	first_snapshot_closed := !first_copied || snapshot_close(&first_snapshot)
	second_snapshot_closed := !second_copied || snapshot_close(&second_snapshot)
	testing.expect(t, closed && first_snapshot_closed && second_snapshot_closed)
}

@(test)
/* Ensures geometry work overflow cannot publish partial popup state. */
overflow_publishes_no_partial_state :: proc(t: ^testing.T) {
	limits := popup_test_limits()
	limits.geometry_work = 1
	registry: Registry
	initialized, _ := registry_init(&registry, Registry_ID(115), limits)
	_, _, _, published, failure := publish_anchor_test_popup(
		&registry,
		{},
		.Cursor,
		Cell_Rect{row = 2, column = 4, height = 10, width = 40},
		false,
		popup_test_renderer(),
	)
	_, current, current_failure := registry_handle(&registry)
	closed, _ := registry_close(&registry)

	testing.expect(t, initialized && !published && !current && closed)
	testing.expect_value(t, failure.code, Failure_Code.Invalid_Proposal)
	testing.expect_value(t, current_failure.code, Failure_Code.Invalid_Root)
}

@(test)
/* popup_geometry_repeated_anchor_updates_remain_bounded_and_release_storage. */
anchor_updates_release_storage :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	registry: Registry
	initialized, _ := registry_init(
		&registry, Registry_ID(116), popup_test_limits(), allocator,
	)
	renderer := popup_test_renderer()
	root: Root_Handle
	updates_ok := initialized
	retained: i64
	for generation in 1 ..= 64 {
		source := Cell_Rect {
			row = i32(generation % 70),
			column = i32((generation * 7) % 200),
			height = 10,
			width = 40,
		}
		popup: Object_Handle
		published: bool
		root, popup, _, published, _ = publish_anchor_test_popup(
			&registry, root, .Cursor, source, false, renderer,
		)
		descriptor, inspected, _ := registry_inspect_popup(&registry, popup)
		updates_ok = updates_ok && published && inspected &&
			descriptor.geometry.state == .Placed && descriptor.geometry.attempts <= 4 &&
			cell_rect_contains(
				Cell_Rect{height = i32(renderer.max_rows), width = i32(renderer.max_columns)},
				descriptor.geometry.outer,
			)
		if generation == 1 {
			retained = tracking.current_memory_allocated
		} else {
			updates_ok = updates_ok && tracking.current_memory_allocated == retained
		}
	}
	closed, _ := registry_close(&registry)
	cleanup_bytes := tracking.current_memory_allocated
	mem.tracking_allocator_destroy(&tracking)

	testing.expect(t, updates_ok && closed)
	testing.expect_value(t, cleanup_bytes, i64(0))
}
