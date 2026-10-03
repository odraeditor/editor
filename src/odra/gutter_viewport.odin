// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../display"
import "../gutter"

@(private)
FACTORY_VIEWPORT_MARKER_ID_BASE :: u64(1 << 63)

@(private)
display_view_has_gutter_indicators :: proc(view: display.Snapshot_View) -> bool {
	for row in view.rows {
		if row.clipped_left || row.clipped_right do return true
	}
	return false
}

@(private)
display_view_gutter_indicators :: proc(
	view: display.Snapshot_View,
	allocator := context.allocator,
) -> (gutter.Marker_Generation, bool) {
	if view.key.snapshot_id == 0 || allocator.procedure == nil do return {}, false
	markers: [gutter.MAX_VISIBLE_ROWS]gutter.Marker
	count := 0
	for row in view.rows {
		if !row.clipped_left && !row.clipped_right do continue
		glyph, fallback, detail := gutter_clipping_presentation(row.clipped_left, row.clipped_right)
		markers[count] = gutter.Marker {
			id = gutter.Marker_ID(FACTORY_VIEWPORT_MARKER_ID_BASE + u64(row.viewport_row) + 1),
			provider = gutter.FACTORY_SEMANTIC_PROVIDER_ID,
			provider_generation = gutter.FACTORY_SEMANTIC_PROVIDER_GENERATION,
			lane = gutter.FACTORY_SEMANTIC_LANE_ID,
			attachment = {
				kind = .Display_Row,
				display_row = u32(row.viewport_row),
				buffer_revision = u64(view.key.buffer_revision),
				view_identity = view.key.view_id,
				view_generation = view.key.view_generation,
				projection_generation = u64(view.key.snapshot_id),
			},
			style_role = .Clipping,
			priority = 50,
			representation = {.Glyph, glyph, fallback},
			aggregation_label = fallback,
			detail = detail,
		}
		count += 1
	}
	if count == 0 do return {}, false
	generation, ok, _ := gutter.marker_generation_copy(
		gutter.Marker_Generation_Proposal {
			id = gutter.Marker_Generation_ID(view.key.snapshot_id),
			provider = gutter.FACTORY_SEMANTIC_PROVIDER_ID,
			provider_generation = gutter.FACTORY_SEMANTIC_PROVIDER_GENERATION,
			complete = true,
			markers = markers[:count],
		},
		allocator,
	)
	return generation, ok
}

@(private)
gutter_clipping_presentation :: proc(left, right: bool) -> (string, string, string) {
	if left && right do return "↔", "*", "Content is clipped on both sides."
	if left do return "‹", "<", "Content is clipped on the left."
	return "›", ">", "Content is clipped on the right."
}
