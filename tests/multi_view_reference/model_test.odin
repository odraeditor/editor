// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package multi_view_reference

import "core:testing"

/* Ensures splitting copies presentation state without stealing focus. */
@(test)
split_copies_presentation_without_focus :: proc(t: ^testing.T) {
	model, ready := model_init(2, 2)
	testing.expect(t, ready)
	if !ready {
		return
	}
	defer model_deinit(&model)

	buffer, buffer_ok, _ := model_add_buffer(&model, 17, 9, true, true)
	original, root_ok, _ := model_open_root(&model, buffer, 5, 2)
	new_pane, split_ok, _ := model_split_active(&model)
	original_state, original_ok := model_inspect_pane(&model, original)
	new_state, new_ok := model_inspect_pane(&model, new_pane)

	testing.expect(t, buffer_ok && root_ok && split_ok && original_ok && new_ok)
	testing.expect_value(t, model.active_pane, original)
	testing.expect_value(t, new_state.buffer, original_state.buffer)
	testing.expect_value(t, new_state.stored_point, original_state.stored_point)
	testing.expect_value(t, new_state.viewport_start, original_state.viewport_start)
	testing.expect_value(t, new_state.viewport_column, original_state.viewport_column)
	testing.expect(t, model_validate(&model))
}

/* Ensures pane-local points remain independent while the buffer mark stays shared. */
@(test)
focus_keeps_pane_points_and_mark :: proc(t: ^testing.T) {
	model, ready := model_init(1, 2)
	testing.expect(t, ready)
	if !ready {
		return
	}
	defer model_deinit(&model)

	buffer, _, _ := model_add_buffer(&model, 10, 50, true, true)
	original, _, _ := model_open_root(&model, buffer, 1)
	secondary, _, _ := model_split_active(&model)
	point_changed, _ := model_set_effective_point(&model, buffer, 25)
	focused_secondary, _ := model_focus(&model, secondary)
	secondary_point_changed, _ := model_set_effective_point(&model, buffer, 80)
	focused_original, _ := model_focus(&model, original)

	buffer_state, buffer_ok := model_inspect_buffer(&model, buffer)
	original_state, original_ok := model_inspect_pane(&model, original)
	secondary_state, secondary_ok := model_inspect_pane(&model, secondary)
	testing.expect(
		t,
		point_changed && focused_secondary && secondary_point_changed && focused_original &&
		buffer_ok && original_ok && secondary_ok,
	)
	testing.expect_value(t, buffer_state.effective_point, u64(25))
	testing.expect_value(t, original_state.stored_point, u64(25))
	testing.expect_value(t, secondary_state.stored_point, u64(80))
	testing.expect_value(t, buffer_state.mark, u64(50))
	testing.expect(t, buffer_state.mark_present && buffer_state.region_active)
	testing.expect(t, model_validate(&model))
}

/* Ensures focus changes effective point without moving another buffer selection. */
@(test)
focus_changes_point_only_for_target :: proc(t: ^testing.T) {
	model, ready := model_init(2, 2)
	testing.expect(t, ready)
	if !ready {
		return
	}
	defer model_deinit(&model)

	first_buffer, _, _ := model_add_buffer(&model, 10, 4, true, true)
	second_buffer, _, _ := model_add_buffer(&model, 90, 70, true, false)
	first_pane, _, _ := model_open_root(&model, first_buffer)
	second_pane, _, _ := model_split_active(&model)
	second_state, _ := model_inspect_pane(&model, second_pane)
	second_state.buffer = second_buffer
	second_state.stored_point = 90
	model.panes[1] = second_state

	first_changed, _ := model_set_effective_point(&model, first_buffer, 22)
	focused, _ := model_focus(&model, second_pane)
	first_state, first_ok := model_inspect_buffer(&model, first_buffer)
	second_buffer_state, second_ok := model_inspect_buffer(&model, second_buffer)

	testing.expect(t, first_changed && focused && first_ok && second_ok)
	testing.expect_value(t, model.active_pane, second_pane)
	testing.expect_value(t, first_state.effective_point, u64(22))
	testing.expect_value(t, first_state.mark, u64(4))
	testing.expect_value(t, second_buffer_state.effective_point, u64(90))
	testing.expect_value(t, second_buffer_state.mark, u64(70))
	testing.expect(t, model_validate(&model))
	_ = first_pane
}

/* Ensures pane-capacity rejection leaves the current layout unchanged. */
@(test)
pane_capacity_rejection_preserves_existing_state :: proc(t: ^testing.T) {
	model, ready := model_init(1, 1)
	testing.expect(t, ready)
	if !ready {
		return
	}
	defer model_deinit(&model)

	buffer, _, _ := model_add_buffer(&model, 3)
	original, _, _ := model_open_root(&model, buffer, 2, 1)
	_, split, failure := model_split_active(&model)
	state, inspected := model_inspect_pane(&model, original)

	testing.expect(t, !split && inspected)
	testing.expect_value(t, failure.code, Failure_Code.Pane_Capacity)
	testing.expect_value(t, model.pane_count, 1)
	testing.expect_value(t, model.active_pane, original)
	testing.expect_value(t, state.viewport_start, u64(2))
	testing.expect(t, model_validate(&model))
}
