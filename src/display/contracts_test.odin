// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package display

import "core:testing"

/* Verifies initial terminal profile identity and fixed policy. */
@(test)
terminal_profile_is_complete_and_versioned :: proc(t: ^testing.T) {
	profile := terminal_unicode17_profile()
	testing.expect(t, display_profile_is_valid(profile))
	testing.expect_value(t, profile.id, TERMINAL_UNICODE17_PROFILE_ID)
	testing.expect_value(t, profile.unicode.version, Unicode_Version{major = 17})
	testing.expect_value(t, profile.ambiguous_width_cells, u8(1))
	testing.expect_value(t, profile.replacement_rune, rune('\uFFFD'))
}

/* Verifies representative and boundary viewport geometry admission. */
@(test)
viewport_constraints_enforce_geometry :: proc(t: ^testing.T) {
	fixtures := [?]struct {
		name:        string,
		constraints: Viewport_Constraints,
	} {
		{"standard", {width_cells = 80, height_rows = 24}},
		{"wide", {width_cells = 160, height_rows = 50}},
		{"maximum", {width_cells = 240, height_rows = 80}},
	}
	for fixture in fixtures {
		ok, failure := constraints_are_valid(fixture.constraints)
		testing.expectf(t, ok, "%s geometry failed with %v", fixture.name, failure.code)
	}

	_, zero_failure := constraints_are_valid(Viewport_Constraints{})
	testing.expect_value(t, zero_failure.code, Failure_Code.Invalid_Constraints)
	_, width_failure := constraints_are_valid(
		Viewport_Constraints{width_cells = 241, height_rows = 1},
	)
	testing.expect_value(t, width_failure.code, Failure_Code.Invalid_Constraints)
	_, height_failure := constraints_are_valid(
		Viewport_Constraints{width_cells = 1, height_rows = 81},
	)
	testing.expect_value(t, height_failure.code, Failure_Code.Invalid_Constraints)
	custom_limits := DEFAULT_RESOURCE_LIMITS
	custom_limits.displayed_cells = 1_000
	_, product_failure := constraints_are_valid(
		Viewport_Constraints{width_cells = 80, height_rows = 24},
		custom_limits,
	)
	testing.expect_value(t, product_failure.code, Failure_Code.Displayed_Cell_Limit)
}

/* Verifies hybrid-row estimates remain bounded and reject every exceeded count. */
@(test)
estimates_cover_retained_categories :: proc(t: ^testing.T) {
	estimate, ok, failure := representation_estimate(
		Viewport_Constraints{width_cells = 240, height_rows = 80},
		64 * KIBIBYTE,
		64 * KIBIBYTE,
		240,
		19_280,
		256,
	)
	testing.expectf(t, ok, "estimate failed with %v", failure.code)
	if !ok {
		return
	}
	testing.expect_value(t, estimate.row_count, u32(80))
	testing.expect_value(t, estimate.run_count, u32(240))
	testing.expect(t, estimate.accounting.row_bytes > 0)
	testing.expect(t, estimate.accounting.run_bytes > 0)
	testing.expect(t, estimate.accounting.boundary_bytes > 0)
	testing.expect(t, estimate.accounting.checkpoint_bytes > 0)
	testing.expect(t, estimate.accounting.retained_bytes < MAX_DERIVED_BYTES)

	_, _, source_failure := representation_estimate(
		Viewport_Constraints{width_cells = 80, height_rows = 24},
		OPERATING_SOURCE_BYTES + 1,
		1,
		1,
		1,
		1,
	)
	testing.expect_value(t, source_failure.code, Failure_Code.Source_Byte_Limit)
	_, _, run_failure := representation_estimate(
		Viewport_Constraints{width_cells = 80, height_rows = 24},
		1,
		1,
		OPERATING_RUNS + 1,
		1,
		1,
	)
	testing.expect_value(t, run_failure.code, Failure_Code.Run_Limit)
	_, _, boundary_failure := representation_estimate(
		Viewport_Constraints{width_cells = 80, height_rows = 24},
		1,
		1,
		1,
		OPERATING_BOUNDARIES + 1,
		1,
	)
	testing.expect_value(t, boundary_failure.code, Failure_Code.Boundary_Limit)
	_, _, checkpoint_failure := representation_estimate(
		Viewport_Constraints{width_cells = 80, height_rows = 24},
		1,
		1,
		1,
		1,
		OPERATING_CHECKPOINTS + 1,
	)
	testing.expect_value(t, checkpoint_failure.code, Failure_Code.Checkpoint_Limit)
}

/* Verifies the hybrid representation remains compact with per-row rectangular selection offsets. */
@(test)
hybrid_representation_contracts_remain_compact :: proc(t: ^testing.T) {
	testing.expect(t, size_of(Text_Run) <= 16)
	testing.expect(t, size_of(Boundary_Map) <= 16)
	testing.expect(t, size_of(Display_Row) <= 80)
	testing.expect(t, size_of(Line_Checkpoint) <= 32)
	testing.expect(t, size_of(Snapshot_Key) <= 80)
}
