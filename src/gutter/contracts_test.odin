// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package gutter

import "core:testing"

@(private = "file")
contracts_test_lane :: proc(policy := Width_Policy.Bounded_Automatic) -> Lane_Definition {
	return Lane_Definition {
		id = 1,
		provider = 1,
		provider_generation = 1,
		side = .Left,
		order = 10,
		attachments = {.Logical_Line},
		width_policy = policy,
		minimum_cells = 1,
		maximum_cells = 8,
		alignment = .Right,
		visibility = .Always,
		collision = .Highest_Priority,
		priority = 255,
		style_role = .Line_Number,
		separator = {kind = .Text, value = " ", fallback = " "},
	}
}

@(test)
/* gutter_contracts_admit_complete_bounded_lanes. */
gutter_contracts_admit_complete_bounded_lanes :: proc(t: ^testing.T) {
	lane := contracts_test_lane()
	testing.expect(t, limits_are_valid(DEFAULT_LIMITS))
	testing.expect(t, lane_definition_is_valid(lane))
	testing.expect(t, representation_is_valid({kind = .Glyph, value = "│", fallback = "|"}))
	testing.expect(t, numbering_mode_is_valid(.None))
	testing.expect(t, numbering_mode_is_valid(.Absolute))
	testing.expect(t, numbering_scope_is_valid(.Logical))
}

@(test)
/* gutter_contracts_reject_incomplete_or_ambiguous_values. */
contracts_reject_incomplete_or_ambiguous_values :: proc(t: ^testing.T) {
	invalid := contracts_test_lane()
	invalid.provider_generation = 0
	testing.expect(t, !lane_definition_is_valid(invalid))

	invalid = contracts_test_lane(.Fixed)
	invalid.minimum_cells = 2
	invalid.maximum_cells = 3
	testing.expect(t, !lane_definition_is_valid(invalid))

	invalid = contracts_test_lane()
	invalid.separator = {kind = .Glyph, value = "│"}
	testing.expect(t, !lane_definition_is_valid(invalid))
	testing.expect(t, !numbering_mode_is_valid(.Invalid))
	testing.expect(t, !numbering_scope_is_valid(.Invalid))
}

@(test)
/* Contract bounds fit the operating view limits. */
contract_bounds_fit_operating_limits :: proc(t: ^testing.T) {
	testing.expect(t, DEFAULT_LIMITS.visible_rows >= 80)
	testing.expect(t, DEFAULT_LIMITS.lanes_per_side * 2 == DEFAULT_LIMITS.lanes)
	testing.expect(t, DEFAULT_LIMITS.view_text_bytes >=
		u32(DEFAULT_LIMITS.visible_rows) * u32(DEFAULT_LIMITS.row_text_bytes) * 2)
	testing.expect(t, DEFAULT_LIMITS.actions_per_marker <= MAX_ACTIONS_PER_MARKER)
}
