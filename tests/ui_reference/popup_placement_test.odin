// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ui_reference

import "core:testing"

/* Ensures placement chooses the first fitting preference without moving its anchor. */
@(test)
placement_uses_first_fit :: proc(t: ^testing.T) {
	request := popup_placement_fixture()
	request.anchor = {row = 1, column = 20, height = 1, width = 1}
	result := popup_place(request)

	testing.expect_value(t, result.state, Popup_Placement_State.Placed)
	testing.expect_value(t, result.placement, Popup_Placement.Below)
	testing.expect_value(t, result.attempts, u8(2))
	testing.expect(t, rect_contains(request.root, result.geometry))
	testing.expect(t, result.geometry.row >= request.anchor.row + request.anchor.height)
}

/* Ensures each root edge produces deterministic popup geometry. */
@(test)
handles_every_root_edge_deterministically :: proc(t: ^testing.T) {
	anchors := [?]Rect {
		{row = 0, column = 0, height = 1, width = 1},
		{row = 0, column = 79, height = 1, width = 1},
		{row = 23, column = 0, height = 1, width = 1},
		{row = 23, column = 79, height = 1, width = 1},
	}
	for anchor in anchors {
		request := popup_placement_fixture()
		request.anchor = anchor
		first := popup_place(request)
		second := popup_place(request)
		testing.expect_value(t, first, second)
		testing.expect_value(t, first.state, Popup_Placement_State.Placed)
		testing.expect(t, rect_contains(request.root, first.geometry))
	}
}

/* Ensures clipping uses terminal cells rather than encoded text bytes. */
@(test)
clips_cell_extent_without_using_text_bytes :: proc(t: ^testing.T) {
	request := popup_placement_fixture()
	request.root = {row = 0, column = 0, height = 8, width = 12}
	request.anchor = {row = 3, column = 10, height = 1, width = 1}
	request.measured_rows = 3
	request.measured_columns = 18
	request.bounds.minimum_columns = 5
	request.bounds.preferred_columns = 8
	request.bounds.maximum_columns = 20
	request.placements = {.Below, .Above, .Before, .After}
	result := popup_place(request)

	testing.expect_value(t, result.state, Popup_Placement_State.Placed)
	testing.expect(t, result.clipped)
	testing.expect(t, result.geometry.width >= request.bounds.minimum_columns)
	testing.expect(t, result.geometry.width <= request.root.width)
	// The measured input is already terminal-cell geometry for wide and combining text.
	testing.expect_value(t, result.geometry.width, i32(12))
}

/* Ensures bounded placement reports whether it fell back or rejected the popup. */
@(test)
placement_falls_back_after_bounds :: proc(t: ^testing.T) {
	request := popup_placement_fixture()
	request.root = {row = 0, column = 0, height = 3, width = 6}
	request.anchor = {row = 1, column = 2, height = 1, width = 1}
	request.bounds.minimum_rows = 3
	request.bounds.minimum_columns = 6
	request.bounds.preferred_rows = 3
	request.bounds.preferred_columns = 6
	request.bounds.maximum_rows = 3
	request.bounds.maximum_columns = 6
	request.clipping = .Reject
	fallback := popup_place(request)
	request.fallback = .Reject
	rejected := popup_place(request)

	testing.expect_value(t, fallback.state, Popup_Placement_State.Fallback)
	testing.expect_value(t, fallback.attempts, request.placement_count)
	testing.expect_value(t, rejected.state, Popup_Placement_State.Rejected)
	testing.expect_value(t, rejected.attempts, request.placement_count)
}

/* Ensures invalid bounds, anchors, and duplicate preferences fail before placement. */
@(test)
placement_rejects_bad_geometry :: proc(t: ^testing.T) {
	invalid_bounds := popup_placement_fixture()
	invalid_bounds.bounds.minimum_rows = invalid_bounds.bounds.maximum_rows + 1

	outside_anchor := popup_placement_fixture()
	outside_anchor.anchor.column = outside_anchor.root.width

	duplicate := popup_placement_fixture()
	duplicate.placements[1] = duplicate.placements[0]

	testing.expect_value(t, popup_place(invalid_bounds).state, Popup_Placement_State.Rejected)
	testing.expect_value(t, popup_place(outside_anchor).state, Popup_Placement_State.Rejected)
	testing.expect_value(t, popup_place(duplicate).state, Popup_Placement_State.Rejected)
}

@(private)
popup_placement_fixture :: proc() -> Popup_Placement_Request {
	return Popup_Placement_Request {
		root = {row = 0, column = 0, height = 24, width = 80},
		anchor = {row = 12, column = 40, height = 1, width = 1},
		placements = {.Above, .Below, .Before, .After},
		placement_count = 4,
		bounds = {
			minimum_rows = 2,
			minimum_columns = 8,
			preferred_rows = 5,
			preferred_columns = 32,
			maximum_rows = 12,
			maximum_columns = 64,
		},
		measured_rows = 5,
		measured_columns = 32,
		clipping = .Clip,
		fallback = .Compact_Feedback,
	}
}
