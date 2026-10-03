// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ui

import "core:testing"

@(test)
/* Generates the complete bounded grid to prove popup, overlap, clipping, and background precedence. */
hit_test_generated_grid_preserves_precedence :: proc(t: ^testing.T) {
	fixture: Hit_Test_Fixture
	snapshot := hit_test_snapshot(&fixture)
	popup_handle := hit_test_handle(50, 7)
	popups := [1]Popup_Descriptor {{
		handle = popup_handle,
		content_surface = hit_test_handle(51, 8),
		geometry = {
			state = .Placed,
			outer = {row = 3, column = 4, height = 5, width = 12},
			content = {row = 4, column = 5, height = 3, width = 10},
			z_order = 9,
			obscures_underlay = true,
		},
	}}
	snapshot.popups = popups[:]

	for row in -1 ..= i32(snapshot.renderer.max_rows) {
		for column in -1 ..= i32(snapshot.renderer.max_columns) {
			result, hit, failure := snapshot_hit_test(
				snapshot,
				Hit_Request{root = snapshot.root, row = row, column = column},
			)
			inside := row >= 0 && column >= 0 &&
				row < i32(snapshot.renderer.max_rows) &&
				column < i32(snapshot.renderer.max_columns)
			if !inside {
				testing.expectf(t, !hit, "outside coordinate (%d,%d) was admitted", row, column)
				testing.expect_value(t, failure.code, Failure_Code.Invalid_Hit)
				continue
			}
			expected := generated_hit_kind(row, column)
			testing.expectf(t, hit, "coordinate (%d,%d) was rejected", row, column)
			if !hit do continue
			testing.expectf(
				t,
				result.kind == expected,
				"coordinate (%d,%d) expected %v and got %v",
				row,
				column,
				expected,
				result.kind,
			)
			if expected == .Popup do testing.expect_value(t, result.popup, popup_handle)
			if expected == .Content || expected == .Gutter || expected == .Status ||
			   expected == .Separator || expected == .Surface {
				if row >= 2 && row <= 13 && column >= 2 && column <= 23 {
					testing.expect_value(t, result.surface, hit_test_handle(20, 2))
				}
			}
		}
	}
}

@(private)
generated_hit_kind :: proc(row, column: i32) -> Hit_Kind {
	if row >= 3 && row < 8 && column >= 4 && column < 16 do return .Popup
	if row == 12 && column >= 2 && column < 22 do return .Status
	if row == 13 && column >= 2 && column < 22 do return .Separator
	if row >= 2 && row < 12 && column >= 2 && column < 22 {
		if column < 5 || column >= 20 do return .Gutter
		return .Content
	}
	if row >= 2 && row < 14 && column >= 2 && column < 24 do return .Surface
	if row >= 0 && row < 20 && column >= 0 && column < 40 do return .Content
	return .Background
}
