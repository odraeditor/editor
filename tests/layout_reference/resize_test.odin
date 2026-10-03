// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package layout_reference

import "core:testing"

/* Verifies resize selects the nearest matching ancestor and changes no other weights. */
@(test)
resize_selects_nearest_compatible_divider :: proc(t: ^testing.T) {
	model, initialized := model_init(18, 51)
	_, root_split := model_split(&model, .Above_Below)
	second_pane := u64(2)
	_, second_created := model_split_target(&model, second_pane, .Left_Right)
	_, nested_split := model_split_target(&model, second_pane, .Above_Below)
	testing.expect(t, initialized && root_split && second_created && nested_split)
	if !initialized || !root_split || !second_created || !nested_split {
		return
	}
	inner := model.nodes[model.active].parent
	middle := model.nodes[inner].parent
	root := model.root
	testing.expect(t, model_resize_active(&model, .Above_Below, 1))
	testing.expect_value(t, model.nodes[inner].first_weight, u64(5))
	testing.expect_value(t, model.nodes[inner].second_weight, u64(4))
	testing.expect_value(t, model.nodes[middle].first_weight, u64(1))
	testing.expect_value(t, model.nodes[middle].second_weight, u64(1))
	testing.expect_value(t, model.nodes[root].first_weight, u64(1))
	testing.expect_value(t, model.nodes[root].second_weight, u64(1))
	testing.expect(t, model_resize_active(&model, .Left_Right, 1))
	testing.expect_value(t, model.nodes[middle].first_weight, u64(26))
	testing.expect_value(t, model.nodes[middle].second_weight, u64(24))
	testing.expect_value(t, model.nodes[inner].first_weight, u64(5))
	testing.expect_value(t, model.nodes[inner].second_weight, u64(4))
}

/* Verifies a blocked nearest divider rejects without falling back to an ancestor. */
@(test)
resize_rejects_without_ancestor_fallback :: proc(t: ^testing.T) {
	model, initialized := model_init(12, 40)
	_, root_split := model_split(&model, .Above_Below)
	_, nested_split := model_split(&model, .Above_Below)
	testing.expect(t, initialized && root_split && nested_split)
	if !initialized || !root_split || !nested_split {
		return
	}
	before := model
	testing.expect(t, !model_resize_active(&model, .Above_Below, 1))
	testing.expect_value(t, model, before)
}

/* Verifies signed movement enlarges and reduces the active second child by one cell. */
@(test)
resize_uses_signed_one_cell_motion :: proc(t: ^testing.T) {
	model, initialized := model_init(9, 41)
	second_pane, split := model_split(&model, .Left_Right)
	focused := model_focus(&model, second_pane)
	testing.expect(t, initialized && split && focused)
	if !initialized || !split || !focused {
		return
	}
	root := model.root
	testing.expect(t, model_resize_active(&model, .Left_Right, 1))
	testing.expect_value(t, model.nodes[root].first_weight, u64(19))
	testing.expect_value(t, model.nodes[root].second_weight, u64(21))
	testing.expect(t, model_resize_active(&model, .Left_Right, -1))
	testing.expect_value(t, model.nodes[root].first_weight, u64(20))
	testing.expect_value(t, model.nodes[root].second_weight, u64(20))
	before := model
	testing.expect(t, !model_resize_active(&model, .Above_Below, 1))
	testing.expect_value(t, model, before)
}

/* Verifies maximum source weights and signed bounds remain checked and atomic. */
@(test)
resize_bounds_weights_and_delta :: proc(t: ^testing.T) {
	model, initialized := model_init(max(i32), max(i32))
	second_pane, split := model_split(&model, .Left_Right)
	focused := model_focus(&model, second_pane)
	testing.expect(t, initialized && split && focused)
	if !initialized || !split || !focused {
		return
	}
	root := model.root
	model.nodes[root].first_weight = max(u64)
	model.nodes[root].second_weight = max(u64)
	testing.expect(t, model_materialize(&model))
	testing.expect(t, model_resize_active(&model, .Left_Right, 1))
	testing.expect_value(t, model.nodes[root].first_weight, u64(1_073_741_822))
	testing.expect_value(t, model.nodes[root].second_weight, u64(1_073_741_824))
	before := model
	testing.expect(t, !model_resize_active(&model, .Left_Right, max(i32)))
	testing.expect_value(t, model, before)
	testing.expect(t, !model_resize_active(&model, .Left_Right, min(i32)))
	testing.expect_value(t, model, before)
}

@(private)
model_split_target :: proc(model: ^Model, pane_id: u64, arrangement: Arrangement) -> (u64, bool) {
	if !model_focus(model, pane_id) {
		return 0, false
	}
	return model_split(model, arrangement)
}
