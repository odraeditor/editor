// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../display"
import "../gutter"
import "core:testing"

@(test)
/* viewport_gutter_indicators_follow_exact_projection_identity_and_clipping_side. */
viewport_indicators_follow_projection :: proc(t: ^testing.T) {
	rows := []display.Display_Row {
		{viewport_row = 0, logical_line = 4, clipped_right = true, has_content = true},
		{viewport_row = 1, logical_line = 5, clipped_left = true, clipped_right = true, has_content = true},
	}
	view := display.Snapshot_View {
		key = {
			snapshot_id = 9,
			buffer_id = 3,
			buffer_revision = 7,
			view_id = 11,
			view_generation = 2,
		},
		rows = rows,
	}
	generation, present := display_view_gutter_indicators(view)
	testing.expect(t, present)
	if !present do return
	defer gutter.marker_generation_close(&generation)
	testing.expect_value(t, len(generation.markers), 2)
	testing.expect_value(t, generation.markers[0].representation.value, "›")
	testing.expect_value(t, generation.markers[1].representation.value, "↔")
	testing.expect_value(t, generation.markers[1].attachment.view_identity, u64(11))
	testing.expect_value(t, generation.markers[1].attachment.projection_generation, u64(9))
}

@(test)
/* viewport_gutter_indicators_omit_unclipped_rows. */
viewport_gutter_indicators_omit_unclipped_rows :: proc(t: ^testing.T) {
	view := display.Snapshot_View {
		key = {snapshot_id = 9, buffer_id = 3, buffer_revision = 7, view_id = 11, view_generation = 2},
		rows = []display.Display_Row{{viewport_row = 0, logical_line = 4, has_content = true}},
	}
	testing.expect(t, !display_view_has_gutter_indicators(view))
	_, present := display_view_gutter_indicators(view)
	testing.expect(t, !present)
}
