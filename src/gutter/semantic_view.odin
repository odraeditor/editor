// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package gutter

import "core:unicode/utf8"

/* FACTORY_SEMANTIC_PROVIDER_ID identifies native semantic marker projection. */
FACTORY_SEMANTIC_PROVIDER_ID :: Provider_ID(2)
/* FACTORY_SEMANTIC_PROVIDER_GENERATION identifies its current lane contract. */
FACTORY_SEMANTIC_PROVIDER_GENERATION :: Provider_Generation(1)
/* FACTORY_SEMANTIC_LANE_ID identifies the compact semantic marker lane. */
FACTORY_SEMANTIC_LANE_ID :: Lane_ID(2)

/* factory_semantic_lane places semantic markers opposite the number lane. */
factory_semantic_lane :: proc(number_side: Side) -> Lane_Definition {
	side := Side.Right
	if number_side == .Right do side = .Left
	return Lane_Definition {
		id = FACTORY_SEMANTIC_LANE_ID,
		provider = FACTORY_SEMANTIC_PROVIDER_ID,
		provider_generation = FACTORY_SEMANTIC_PROVIDER_GENERATION,
		side = side,
		order = 10,
		attachments = {.Logical_Line, .Display_Row},
		width_policy = .Content_Presence,
		minimum_cells = 2,
		maximum_cells = 2,
		alignment = .Center,
		visibility = .When_Content,
		collision = .Highest_Priority,
		priority = 200,
		style_role = .Ordinary,
		separator = {kind = .Glyph, value = "│", fallback = "|"},
	}
}

/* view_add_marker_lane atomically adds one ordered marker lane to a factory view. */
view_add_marker_lane :: proc(
	view: ^View,
	lane: Lane_Definition,
	markers: ^Resolved_Marker_View,
	visible_rows: []Visible_Row,
	cells_reserved := false,
) -> (bool, Failure_Context) {
	if view == nil || view.allocator.procedure == nil || markers == nil ||
	   markers.allocator.procedure == nil || !lane_definition_is_valid(lane) ||
	   len(markers.markers) == 0 || len(visible_rows) > MAX_VISIBLE_ROWS ||
	   lane.maximum_cells == 0 || view.geometry.lane_count >= MAX_LANES ||
	   (!cells_reserved && view.geometry.text_cells < MIN_TEXT_CELLS + u32(lane.maximum_cells)) {
		return false, Failure_Context{operation = .Project, code = .Invalid_Request, lane = lane.id}
	}
	lane_cells := lane.maximum_cells
	separator := lane.separator.value
	separator_cells := u16(1)
	if lane_cells <= separator_cells {
		return false, Failure_Context{operation = .Project, code = .Invalid_Lane, lane = lane.id}
	}
	content_cells := lane_cells - separator_cells
	prepend := marker_lane_precedes_existing(view, lane)
	row_count := len(view.rows)
	if row_count == 0 do row_count = len(visible_rows)
	text_bytes := 0
	for index in 0 ..< row_count {
		viewport_row: u32
		if len(view.rows) > 0 {
			viewport_row = view.rows[index].viewport_row
		} else {
			viewport_row = visible_rows[index].viewport_row
		}
		marker := semantic_marker_for_row(markers, viewport_row, lane.id)
		value_bytes := int(content_cells)
		if marker != nil {
			marker_text := resolved_marker_text(marker)
			marker_cells := utf8.rune_count(marker_text)
			if marker_cells > int(content_cells) {
				return false, Failure_Context {
					operation = .Project, code = .Text_Limit, lane = lane.id,
					limit = u64(content_cells), actual = u64(marker_cells),
				}
			}
			value_bytes = len(marker_text) + int(content_cells) - marker_cells
		}
		left_bytes, right_bytes: u16
		if len(view.rows) > 0 {
			left_bytes = view.rows[index].left_bytes
			right_bytes = view.rows[index].right_bytes
		}
		text_bytes += int(left_bytes) + int(right_bytes) + len(separator) + value_bytes
	}
	if text_bytes > int(DEFAULT_LIMITS.view_text_bytes) {
		return false, Failure_Context {
			operation = .Project, code = .Text_Limit,
			limit = u64(DEFAULT_LIMITS.view_text_bytes), actual = u64(text_bytes), lane = lane.id,
		}
	}
	new_text, text_error := make([]u8, text_bytes, view.allocator)
	if text_error != nil {
		return false, Failure_Context{operation = .Project, code = .Allocation, actual = u64(text_bytes)}
	}
	new_rows, rows_error := make([]Row_View, row_count, view.allocator)
	if rows_error != nil {
		delete(new_text, view.allocator)
		return false, Failure_Context {
			operation = .Project, code = .Allocation,
			actual = u64(text_bytes) + u64(len(view.rows)) * u64(size_of(Row_View)),
		}
	}
	cursor := 0
	for index in 0 ..< row_count {
		row: Row_View
		if len(view.rows) > 0 {
			row = view.rows[index]
		} else {
			row.viewport_row = visible_rows[index].viewport_row
			row.logical_line = visible_rows[index].logical_line
		}
		new_rows[index] = row
		entry := &new_rows[index]
		marker := semantic_marker_for_row(markers, row.viewport_row, lane.id)
		marker_text := ""
		role := Semantic_Role.Background
		if marker != nil {
			marker_text = resolved_marker_text(marker)
			role = marker.style_role
		}
		lane_text_start := cursor
		if lane.side == .Left {
			entry.left_offset = u32(lane_text_start)
			if !prepend && row.left_bytes > 0 {
				copy(new_text[cursor:], view.text[row.left_offset:row.left_offset + u32(row.left_bytes)])
				cursor += int(row.left_bytes)
			}
			lane_start := cursor
			cursor += programmable_marker_segment_write(
				new_text[cursor:], marker_text, content_cells, lane.alignment,
			)
			copy(new_text[cursor:], transmute([]u8)separator)
			cursor += len(separator)
			lane_bytes := cursor - lane_start
			if prepend && row.left_bytes > 0 {
				copy(new_text[cursor:], view.text[row.left_offset:row.left_offset + u32(row.left_bytes)])
				cursor += int(row.left_bytes)
			}
			entry.left_bytes = row.left_bytes + u16(lane_bytes)
			entry.left_cells = row.left_cells + lane_cells
			entry.left_separator_bytes = u8(len(separator))
			if prepend && row.left_separator_bytes > 0 {
				entry.left_separator_bytes = row.left_separator_bytes
			}
			entry.left_role = role
		} else if row.left_bytes > 0 {
			entry.left_offset = u32(cursor)
			copy(new_text[cursor:], view.text[row.left_offset:row.left_offset + u32(row.left_bytes)])
			cursor += int(row.left_bytes)
		}
		if lane.side == .Right {
			lane_text_start = cursor
			entry.right_offset = u32(lane_text_start)
			if !prepend && row.right_bytes > 0 {
				copy(new_text[cursor:], view.text[row.right_offset:row.right_offset + u32(row.right_bytes)])
				cursor += int(row.right_bytes)
			}
			lane_start := cursor
			copy(new_text[cursor:], transmute([]u8)separator)
			cursor += len(separator)
			cursor += programmable_marker_segment_write(
				new_text[cursor:], marker_text, content_cells, lane.alignment,
			)
			lane_bytes := cursor - lane_start
			if prepend && row.right_bytes > 0 {
				copy(new_text[cursor:], view.text[row.right_offset:row.right_offset + u32(row.right_bytes)])
				cursor += int(row.right_bytes)
			}
			entry.right_bytes = row.right_bytes + u16(lane_bytes)
			entry.right_cells = row.right_cells + lane_cells
			entry.right_separator_bytes = u8(len(separator))
			if !prepend && row.right_separator_bytes > 0 {
				entry.right_separator_bytes = row.right_separator_bytes
			}
			entry.right_role = role
		} else if row.right_bytes > 0 {
			entry.right_offset = u32(cursor)
			copy(new_text[cursor:], view.text[row.right_offset:row.right_offset + u32(row.right_bytes)])
			cursor += int(row.right_bytes)
		}
	}
	delete(view.text, view.allocator)
	delete(view.rows, view.allocator)
	view.text = new_text
	view.rows = new_rows
	if lane.side == .Left do view.geometry.left_cells += lane_cells
	if lane.side == .Right do view.geometry.right_cells += lane_cells
	if cells_reserved {
		view.geometry.available_cells += u32(lane_cells)
	} else {
		view.geometry.text_cells -= u32(lane_cells)
	}
	view.geometry.lanes[view.geometry.lane_count] = Lane_Geometry {
		lane = lane.id, side = lane.side, order = lane.order, width_cells = lane_cells,
		visible = true, style_role = lane.style_role,
	}
	view.geometry.lane_count += 1
	view.accounting.visible_lanes += 1
	view.accounting.visible_rows = u16(row_count)
	view.accounting.text_bytes = u32(text_bytes)
	view.accounting.retained_bytes = u64(text_bytes) + u64(len(new_rows)) * u64(size_of(Row_View))
	return true, {}
}

/* view_add_semantic_lane preserves the factory semantic-lane entry point. */
view_add_semantic_lane :: proc(
	view: ^View,
	lane: Lane_Definition,
	markers: ^Resolved_Marker_View,
	visible_rows: []Visible_Row,
	cells_reserved := false,
) -> (bool, Failure_Context) {
	return view_add_marker_lane(view, lane, markers, visible_rows, cells_reserved)
}

@(private = "file")
marker_lane_precedes_existing :: proc(view: ^View, lane: Lane_Definition) -> bool {
	if view == nil do return true
	for existing in view.geometry.lanes[:view.geometry.lane_count] {
		if existing.side == lane.side && existing.visible do return lane.order < existing.order
	}
	return true
}

@(private = "file")
programmable_marker_segment_write :: proc(
	destination: []u8,
	value: string,
	cells: u16,
	alignment: Alignment,
) -> int {
	value_cells := utf8.rune_count(value)
	padding := int(cells) - value_cells
	left_padding := 0
	switch alignment {
	case .Right: left_padding = padding
	case .Center: left_padding = padding / 2
	case .Left, .Invalid:
	}
	for index in 0 ..< left_padding do destination[index] = ' '
	cursor := left_padding
	copy(destination[cursor:], transmute([]u8)value)
	cursor += len(value)
	for _ in 0 ..< padding - left_padding {
		destination[cursor] = ' '
		cursor += 1
	}
	return cursor
}

@(private = "file")
semantic_marker_for_row :: proc(
	markers: ^Resolved_Marker_View,
	viewport_row: u32,
	lane: Lane_ID,
) -> ^Resolved_Marker {
	if markers == nil do return nil
	for &marker in markers.markers {
		if marker.viewport_row == viewport_row && marker.lane == lane do return &marker
	}
	return nil
}
