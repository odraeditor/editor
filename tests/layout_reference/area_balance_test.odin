// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package layout_reference

import "core:testing"

/* Verifies exact area balance differs from full-span dimensional balance. */
@(test)
area_balance_minimizes_pairwise_leaf_difference :: proc(t: ^testing.T) {
	model, initialized := model_init(18, 33)
	_, below := model_split(&model, .Above_Below)
	_, right := model_split_target(&model, 1, .Left_Right)
	testing.expect(t, initialized && below && right)
	if !initialized || !below || !right {
		return
	}
	dimensional := model
	testing.expect(t, model_balance_dimensions(&dimensional))
	dimensional_score, dimensional_scored := model_area_score(&dimensional)
	score, work, balanced := model_balance_areas_exact(&model)
	testing.expect(t, dimensional_scored && balanced)
	testing.expect_value(t, work, u64(198))
	testing.expect(t, score.pairwise_difference < dimensional_score.pairwise_difference)
	testing.expect_value(t, score.pairwise_difference, u128(12))
	testing.expect_value(t, score.range, u64(6))
	testing.expect_value(t, model.nodes[model.root].first_weight, u64(12))
	testing.expect_value(t, model.nodes[model.root].second_weight, u64(6))
}

/* Verifies symmetric optima select the smaller ordered first-child span. */
@(test)
breaks_ties_by_spatial_partition_spans :: proc(t: ^testing.T) {
	model, initialized := model_init(6, 18)
	_, split := model_split(&model, .Left_Right)
	testing.expect(t, initialized && split)
	if !initialized || !split {
		return
	}
	score, _, balanced := model_balance_areas_exact(&model)
	testing.expect(t, balanced)
	testing.expect_value(t, score.pairwise_difference, u128(6))
	testing.expect_value(t, score.range, u64(6))
	testing.expect_value(t, score.first_spans[0], u64(8))
	testing.expect_value(t, model.nodes[model.root].first_weight, u64(8))
	testing.expect_value(t, model.nodes[model.root].second_weight, u64(9))
}

/* Verifies adversarial mixed topology remains valid within the selected oracle ceiling. */
@(test)
area_balance_admits_adversarial_mixed_tree :: proc(t: ^testing.T) {
	model, initialized := model_init(21, 41)
	_, below := model_split(&model, .Above_Below)
	_, upper_right := model_split_target(&model, 1, .Left_Right)
	_, lower_right := model_split_target(&model, 2, .Left_Right)
	testing.expect(t, initialized && below && upper_right && lower_right)
	if !initialized || !below || !upper_right || !lower_right {
		return
	}
	before, before_ok := model_area_score(&model)
	after, work, balanced := model_balance_areas_exact(&model)
	testing.expect(t, before_ok && balanced && model_validate(&model))
	testing.expect_value(t, work, u64(9_114))
	testing.expect(t, after.pairwise_difference <= before.pairwise_difference)
	testing.expect_value(t, after.leaf_count, u16(4))
	testing.expect_value(t, after.partition_count, u16(3))
}

/* Verifies the demanding exact profile remains below the selected search ceiling. */
@(test)
area_balance_calibrates_demanding_search_work :: proc(t: ^testing.T) {
	model, initialized := model_init(29, 57)
	_, root_below := model_split(&model, .Above_Below)
	_, upper_right := model_split_target(&model, 1, .Left_Right)
	_, upper_nested := model_split_target(&model, 1, .Above_Below)
	_, lower_right := model_split_target(&model, 2, .Left_Right)
	testing.expect(t, initialized && root_below && upper_right && upper_nested && lower_right)
	if !initialized || !root_below || !upper_right || !upper_nested || !lower_right {
		return
	}
	before := model
	_, work, balanced := model_balance_areas_exact(&model)
	testing.expect(t, balanced && model_validate(&model))
	testing.expect_value(t, work, u64(295_218))
	testing.expect(t, work < AREA_BALANCE_ORACLE_WORK_LIMIT)

	rejected := before
	_, rejected_work, rejected_ok := model_balance_areas_exact(&rejected, work - 1)
	testing.expect(t, !rejected_ok)
	testing.expect_value(t, rejected_work, work - 1)
	testing.expect_value(t, rejected, before)
}

/* Verifies maximum integer geometry scores without overflow. */
@(test)
score_checks_maximum_integer_geometry :: proc(t: ^testing.T) {
	model, initialized := model_init(max(i32), max(i32))
	_, split := model_split(&model, .Left_Right)
	testing.expect(t, initialized && split)
	if !initialized || !split {
		return
	}
	score, scored := model_area_score(&model)
	testing.expect(t, scored)
	testing.expect_value(t, score.leaf_count, u16(2))
	testing.expect_value(t, score.pairwise_difference, u128(0))
	testing.expect_value(t, score.range, u64(0))
}

/* Verifies exhaustive search rejects atomically at its selected work ceiling. */
@(test)
area_balance_rejects_bounded_search_atomically :: proc(t: ^testing.T) {
	model, initialized := model_init(18, 33)
	_, below := model_split(&model, .Above_Below)
	_, right := model_split_target(&model, 1, .Left_Right)
	testing.expect(t, initialized && below && right)
	if !initialized || !below || !right {
		return
	}
	before := model
	_, work, balanced := model_balance_areas_exact(&model, 1)
	testing.expect(t, !balanced)
	testing.expect_value(t, work, u64(1))
	testing.expect_value(t, model, before)
}
