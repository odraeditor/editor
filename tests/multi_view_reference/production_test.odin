// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package multi_view_reference

import editor "../../src/editor"
import view "../../src/view"
import "core:mem"
import "core:testing"

/* Cross-checks generated same-buffer traces against production ownership. */
@(test)
generated_trace_matches_ownership :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	allocator := mem.tracking_allocator(&tracking)

	model, model_ok := model_init(1, 4, allocator)
	buffer_id, buffer_model_ok, _ := model_add_buffer(&model, 0)
	root_pane, root_ok, _ := model_open_root(&model, buffer_id)
	second_pane, second_ok, _ := model_split_active(&model)
	third_pane, third_ok, _ := model_split_active(&model)
	fourth_pane, fourth_ok, _ := model_split_active(&model)
	testing.expect(t, model_ok && buffer_model_ok && root_ok && second_ok && third_ok && fourth_ok)
	if !model_ok || !buffer_model_ok || !root_ok || !second_ok || !third_ok || !fourth_ok {
		model_deinit(&model)
		return
	}

	buffer: editor.Buffer
	buffer_ok, _ := editor.buffer_init(
		&buffer,
		editor.Buffer_ID(9_001),
		"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789",
		editor.Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
	)
	registry: view.Registry
	registry_ok, _ := view.registry_init(&registry, view.Registry_ID(9_001), allocator)
	primary, primary_ok, _ := view.create(&registry, &buffer)
	second, second_view_ok, _ := view.clone_additional(&registry, primary)
	third, third_view_ok, _ := view.clone_additional(&registry, primary)
	fourth, fourth_view_ok, _ := view.clone_additional(&registry, primary)
	testing.expect(
		t,
		buffer_ok && registry_ok && primary_ok && second_view_ok && third_view_ok && fourth_view_ok,
	)
	if !buffer_ok || !registry_ok || !primary_ok || !second_view_ok || !third_view_ok ||
	   !fourth_view_ok {
		return
	}

	panes := [4]Pane_ID{root_pane, second_pane, third_pane, fourth_pane}
	views := [4]view.View_Handle{primary, second, third, fourth}
	active := 0
	seed := u64(0x9e3779b97f4a7c15)
	for _ in 0 ..< 512 {
		seed = seed * 6_364_136_223_846_793_005 + 1_442_695_040_888_963_407
		offset := seed % 63
		switch seed % 6 {
		case 0:
			position, position_ok, _ := editor.buffer_position(&buffer, editor.Byte_Offset(offset))
			model_changed, _ := model_set_active_point(&model, offset, u32(offset))
			view_changed, _ := view.move_point(
				&registry,
				views[active],
				position,
				u32(offset),
				.Preserve,
			)
			testing.expect(t, position_ok && model_changed && view_changed)
		case 1:
			position, position_ok, _ := editor.buffer_position(&buffer, editor.Byte_Offset(offset))
			active_region := (seed & 8) != 0
			model_changed, _ := model_set_mark(&model, buffer_id, offset, true, active_region)
			view_changed, _ := view.set_mark(&registry, views[active], position, active_region)
			testing.expect(t, position_ok && model_changed && view_changed)
		case 2:
			model_changed, _ := model_set_mark(&model, buffer_id, 0, false, false)
			view_changed, _ := view.clear_mark(&registry, views[active])
			testing.expect(t, model_changed && view_changed)
		case 3:
			position, position_ok, _ := editor.buffer_position(&buffer, editor.Byte_Offset(offset))
			column := u32((seed >> 8) % 17)
			model_changed, _ := model_set_viewport(&model, panes[active], offset, column)
			view_changed, _ := view.set_viewport(&registry, views[active], position, column)
			testing.expect(t, position_ok && model_changed && view_changed)
		case 4:
			target := int((seed >> 16) % 4)
			if target != active {
				stored, _ := view.store_effective_point(&registry, views[active])
				restored, _ := view.restore_stored_point(&registry, views[target])
				focused, _ := model_focus(&model, panes[target])
				testing.expect(t, stored && restored && focused)
				active = target
			}
		case 5:
			active_region := (seed & 32) != 0
			buffer_state, _ := model_inspect_buffer(&model, buffer_id)
			if buffer_state.mark_present {
				model_changed, _ := model_set_mark(
					&model,
					buffer_id,
					buffer_state.mark,
					true,
					active_region,
				)
				view_changed, _ := view.set_region_active(
					&registry,
					views[active],
					active_region,
				)
				testing.expect(t, model_changed && view_changed)
			}
		}
		expect_model_matches_views(t, &model, buffer_id, panes[:], &registry, views[:])
	}

	for index := len(views) - 1; index >= 0; index -= 1 {
		closed, _ := view.close(&registry, &views[index])
		testing.expect(t, closed)
	}
	registry_closed, _ := view.registry_close(&registry)
	buffer_closed, _ := editor.buffer_close(&buffer)
	model_deinit(&model)
	testing.expect(t, registry_closed && buffer_closed)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
}

/* Ensures selection state cannot leak between buffers displayed in separate panes. */
@(test)
cross_buffer_selection_state_remains_isolated :: proc(t: ^testing.T) {
	first_buffer: editor.Buffer
	second_buffer: editor.Buffer
	first_ok, _ := editor.buffer_init(
		&first_buffer,
		editor.Buffer_ID(9_002),
		"first",
		editor.Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	second_ok, _ := editor.buffer_init(
		&second_buffer,
		editor.Buffer_ID(9_003),
		"second",
		editor.Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	registry: view.Registry
	registry_ok, _ := view.registry_init(&registry, view.Registry_ID(9_002), context.allocator)
	first, first_view_ok, _ := view.create(&registry, &first_buffer)
	second, second_view_ok, _ := view.create(&registry, &second_buffer)
	first_point, _, _ := editor.buffer_position(&first_buffer, 5)
	first_mark, _, _ := editor.buffer_position(&first_buffer, 1)
	second_point, _, _ := editor.buffer_position(&second_buffer, 6)
	second_mark, _, _ := editor.buffer_position(&second_buffer, 2)
	first_point_ok, _ := view.set_point(&registry, first, first_point)
	first_mark_ok, _ := view.set_mark(&registry, first, first_mark, true)
	second_point_ok, _ := view.set_point(&registry, second, second_point)
	second_mark_ok, _ := view.set_mark(&registry, second, second_mark, false)
	first_state, first_snapshot_ok, _ := view.snapshot(&registry, first)
	second_state, second_snapshot_ok, _ := view.snapshot(&registry, second)
	testing.expect(
		t,
		first_ok && second_ok && registry_ok && first_view_ok && second_view_ok &&
		first_point_ok && first_mark_ok && second_point_ok && second_mark_ok &&
		first_snapshot_ok && second_snapshot_ok,
	)
	testing.expect_value(t, first_state.point_position.byte_offset, editor.Byte_Offset(5))
	testing.expect_value(t, first_state.mark.position.byte_offset, editor.Byte_Offset(1))
	testing.expect(t, first_state.region_active)
	testing.expect_value(t, second_state.point_position.byte_offset, editor.Byte_Offset(6))
	testing.expect_value(t, second_state.mark.position.byte_offset, editor.Byte_Offset(2))
	testing.expect(t, !second_state.region_active)
	view.close(&registry, &second)
	view.close(&registry, &first)
	view.registry_close(&registry)
	editor.buffer_close(&second_buffer)
	editor.buffer_close(&first_buffer)
}

@(private)
expect_model_matches_views :: proc(
	t: ^testing.T,
	model: ^Model,
	buffer_id: Buffer_ID,
	panes: []Pane_ID,
	registry: ^view.Registry,
	views: []view.View_Handle,
) {
	buffer_state, buffer_ok := model_inspect_buffer(model, buffer_id)
	testing.expect(t, buffer_ok && len(panes) == len(views))
	for current, index in views {
		pane_state, pane_ok := model_inspect_pane(model, panes[index])
		snapshot, snapshot_ok, _ := view.snapshot(registry, current)
		testing.expect(t, pane_ok && snapshot_ok)
		testing.expect_value(t, u64(snapshot.point_position.byte_offset), pane_state.stored_point)
		testing.expect_value(t, u64(snapshot.effective_point_position.byte_offset), buffer_state.effective_point)
		testing.expect_value(t, snapshot.mark.present, buffer_state.mark_present)
		if buffer_state.mark_present {
			testing.expect_value(t, u64(snapshot.mark.position.byte_offset), buffer_state.mark)
		}
		testing.expect_value(t, snapshot.region_active, buffer_state.region_active)
		testing.expect_value(t, u64(snapshot.viewport_origin_position.byte_offset), pane_state.viewport_start)
		testing.expect_value(t, snapshot.horizontal_display_column, pane_state.viewport_column)
	}
	testing.expect(t, model_validate(model))
}
