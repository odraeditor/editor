// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package display

import "../editor"
import editor_view "../view"
import "base:runtime"

/* MAX_RECTANGLE_RANGES bounds the logical lines derived by one selection. */
MAX_RECTANGLE_RANGES :: u64(4_096)

/* Rectangle_Descriptor identifies one normalized logical grapheme rectangle. */
Rectangle_Descriptor :: struct {
	top_line:     u64,
	bottom_line:  u64,
	left_column:  u32,
	right_column: u32,
}

/* rectangular_selection_ranges derives one half-open current range per logical line. */
rectangular_selection_ranges :: proc(
	buffer: ^editor.Buffer,
	logical: editor_view.Snapshot,
	profile: Display_Profile,
	allocator: runtime.Allocator,
	limit := MAX_RECTANGLE_RANGES,
) -> (
	descriptor: Rectangle_Descriptor,
	ranges: []Selection_Range,
	ok: bool,
	failure: Failure_Context,
) {
	if buffer == nil || allocator.procedure == nil || limit == 0 ||
	   !logical.region_active || !logical.mark.present ||
	   logical.selection_shape != .Rectangle ||
	   logical.rectangle_column_policy != .Grapheme ||
	   !display_profile_is_valid(profile) ||
	   Display_Profile_ID(u64(logical.display_profile_id)) != profile.id {
		return {}, nil, false, Failure_Context{code = .Invalid_Request}
	}
	anchor_line, anchor_ok, anchor_failure := editor.buffer_line_at_position(
		buffer, logical.mark.position,
	)
	if !anchor_ok do return {}, nil, false, navigation_editor_failure(logical, anchor_failure)
	cursor_line, cursor_ok, cursor_failure := editor.buffer_line_at_position(
		buffer, logical.point_position,
	)
	if !cursor_ok do return {}, nil, false, navigation_editor_failure(logical, cursor_failure)
	anchor_column, anchor_column_ok, anchor_column_failure := rectangle_position_column(
		buffer, anchor_line, logical.mark.position, profile,
	)
	if !anchor_column_ok do return {}, nil, false, anchor_column_failure
	cursor_column, cursor_column_ok, cursor_column_failure := rectangle_position_column(
		buffer, cursor_line, logical.point_position, profile,
	)
	if !cursor_column_ok do return {}, nil, false, cursor_column_failure
	left := min(anchor_column, cursor_column)
	right_base := max(anchor_column, cursor_column)
	if right_base == max(u32) {
		return {}, nil, false, Failure_Context{code = .Work_Limit, limit = u64(max(u32)), actual = u64(right_base)}
	}
	descriptor = {
		top_line = min(anchor_line.line_index, cursor_line.line_index),
		bottom_line = max(anchor_line.line_index, cursor_line.line_index),
		left_column = left,
		right_column = right_base + 1,
	}
	count := descriptor.bottom_line - descriptor.top_line + 1
	if count > limit || count > u64(max(int)) {
		return descriptor, nil, false, Failure_Context{code = .Work_Limit, limit = limit, actual = count}
	}
	allocation_error: runtime.Allocator_Error
	ranges, allocation_error = make([]Selection_Range, int(count), allocator)
	if allocation_error != nil {
		return descriptor, nil, false, Failure_Context{code = .Temporary_Memory_Limit, actual = count * u64(size_of(Selection_Range))}
	}
	line := anchor_line
	if cursor_line.line_index < anchor_line.line_index do line = cursor_line
	for index in 0 ..< len(ranges) {
		start, start_ok, start_failure := rectangle_line_boundary(
			buffer, line, descriptor.left_column, profile,
		)
		if !start_ok {
			delete(ranges, allocator)
			return descriptor, nil, false, start_failure
		}
		end, end_ok, end_failure := rectangle_line_boundary(
			buffer, line, descriptor.right_column, profile,
		)
		if !end_ok {
			delete(ranges, allocator)
			return descriptor, nil, false, end_failure
		}
		ranges[index] = {start = start, end = end}
		if index + 1 == len(ranges) do break
		next_position, next_ok, next_failure := editor.buffer_position(buffer, line.next_start)
		if !next_ok {
			delete(ranges, allocator)
			return descriptor, nil, false, navigation_editor_failure_from_line(line, next_failure)
		}
		line, next_ok, next_failure = editor.buffer_line_at_position(buffer, next_position)
		if !next_ok {
			delete(ranges, allocator)
			return descriptor, nil, false, navigation_editor_failure_from_line(line, next_failure)
		}
	}
	return descriptor, ranges, true, {}
}

@(private)
rectangle_position_column :: proc(
	buffer: ^editor.Buffer,
	line: editor.Buffer_Line,
	position: editor.Position,
	profile: Display_Profile,
) -> (column: u32, ok: bool, failure: Failure_Context) {
	scratch: [NAVIGATION_SOURCE_BYTES]u8
	text, text_ok, text_failure := inspect_navigation_line(buffer, line, scratch[:])
	if !text_ok do return 0, false, text_failure
	target := u64(position.byte_offset) - u64(line.start)
	parsed: u64
	for parsed < target {
		grapheme, grapheme_ok, grapheme_failure := profile_next_grapheme(
			profile.unicode, text, parsed,
		)
		if !grapheme_ok || grapheme.end > target {
			return 0, false, navigation_profile_failure(line, grapheme_failure)
		}
		if column == max(u32) {
			return 0, false, Failure_Context{code = .Work_Limit, limit = u64(max(u32)), actual = u64(column)}
		}
		column += 1
		parsed = grapheme.end
	}
	return column, true, {}
}

@(private)
rectangle_line_boundary :: proc(
	buffer: ^editor.Buffer,
	line: editor.Buffer_Line,
	desired: u32,
	profile: Display_Profile,
) -> (position: editor.Position, ok: bool, failure: Failure_Context) {
	scratch: [NAVIGATION_SOURCE_BYTES]u8
	text, text_ok, text_failure := inspect_navigation_line(buffer, line, scratch[:])
	if !text_ok do return {}, false, text_failure
	parsed: u64
	column: u32
	for parsed < u64(len(text)) && column < desired {
		grapheme, grapheme_ok, grapheme_failure := profile_next_grapheme(
			profile.unicode, text, parsed,
		)
		if !grapheme_ok do return {}, false, navigation_profile_failure(line, grapheme_failure)
		parsed = grapheme.end
		column += 1
	}
	editor_failure: editor.Failure_Context
	position, ok, editor_failure = editor.buffer_position(
		buffer, editor.Byte_Offset(u64(line.start) + parsed),
	)
	if !ok do return {}, false, navigation_editor_failure_from_line(line, editor_failure)
	return position, true, {}
}
