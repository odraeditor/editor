// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package display

import "../editor"
import editor_view "../view"
import "core:unicode"
import "core:unicode/utf8"

@(private)
NAVIGATION_SOURCE_BYTES :: int(OPERATING_SOURCE_BYTES)

/* Selection_Range owns two current buffer boundaries selected by a direct command. */
Selection_Range :: struct {
	start: editor.Position,
	end:   editor.Position,
}

/* word_selection_range resolves one complete direct-profile word on the point line. */
word_selection_range :: proc(
	buffer: ^editor.Buffer,
	logical: editor_view.Snapshot,
	profile: Display_Profile,
) -> (range: Selection_Range, found: bool, ok: bool, failure: Failure_Context) {
	if !display_profile_is_valid(profile) ||
	   Display_Profile_ID(u64(logical.display_profile_id)) != profile.id {
		return {}, false, false, Failure_Context{code = .Invalid_Profile}
	}
	line, line_ok, line_failure := editor.buffer_line_at_position(buffer, logical.point_position)
	if !line_ok do return {}, false, false, navigation_editor_failure(logical, line_failure)
	scratch: [NAVIGATION_SOURCE_BYTES]u8
	text, text_ok, text_failure := inspect_navigation_line(buffer, line, scratch[:])
	if !text_ok do return {}, false, false, text_failure
	point := u64(logical.point_position.byte_offset) - u64(line.start)
	start, end, selected, range_failure := word_selection_offsets(text, point, line, profile)
	if range_failure.code != .None do return {}, false, false, range_failure
	if !selected do return {}, false, true, {}
	start_position, start_ok, start_failure := editor.buffer_position(
		buffer,
		editor.Byte_Offset(u64(line.start) + start),
	)
	if !start_ok do return {}, false, false, navigation_editor_failure_from_line(line, start_failure)
	end_position, end_ok, end_failure := editor.buffer_position(
		buffer,
		editor.Byte_Offset(u64(line.start) + end),
	)
	if !end_ok do return {}, false, false, navigation_editor_failure_from_line(line, end_failure)
	return Selection_Range{start = start_position, end = end_position}, true, true, {}
}

/* paragraph_selection_range resolves the maximal matching blank or nonblank logical-line run. */
paragraph_selection_range :: proc(
	buffer: ^editor.Buffer,
	logical: editor_view.Snapshot,
) -> (range: Selection_Range, ok: bool, failure: Failure_Context) {
	line, line_ok, line_failure := editor.buffer_line_at_position(buffer, logical.point_position)
	if !line_ok do return {}, false, navigation_editor_failure(logical, line_failure)
	blank, inspected, blank_ok, blank_failure := navigation_line_blank(buffer, line)
	if !blank_ok do return {}, false, blank_failure
	start := line
	end := line
	inspected_bytes := inspected
	for start.line_index > 0 {
		probe, probe_ok, probe_failure := editor.buffer_position(
			buffer,
			editor.Byte_Offset(u64(start.start) - 1),
		)
		if !probe_ok do return {}, false, navigation_editor_failure_from_line(start, probe_failure)
		previous, previous_ok, previous_failure := editor.buffer_line_at_position(buffer, probe)
		if !previous_ok do return {}, false, navigation_editor_failure_from_line(start, previous_failure)
		separator_bytes := u64(start.start) - u64(previous.content_end)
		if inspected_bytes + separator_bytes > u64(NAVIGATION_SOURCE_BYTES) {
			return {}, false, word_navigation_limit_failure(previous, inspected_bytes + separator_bytes)
		}
		candidate_blank, candidate_bytes, candidate_ok, candidate_failure := navigation_line_blank(buffer, previous)
		if !candidate_ok do return {}, false, candidate_failure
		if inspected_bytes + separator_bytes + candidate_bytes > u64(NAVIGATION_SOURCE_BYTES) {
			return {}, false, word_navigation_limit_failure(previous, inspected_bytes + separator_bytes + candidate_bytes)
		}
		if candidate_blank != blank do break
		inspected_bytes += separator_bytes + candidate_bytes
		start = previous
	}
	for end.next_start != end.content_end {
		probe, probe_ok, probe_failure := editor.buffer_position(buffer, end.next_start)
		if !probe_ok do return {}, false, navigation_editor_failure_from_line(end, probe_failure)
		next, next_ok, next_failure := editor.buffer_line_at_position(buffer, probe)
		if !next_ok do return {}, false, navigation_editor_failure_from_line(end, next_failure)
		separator_bytes := u64(end.next_start) - u64(end.content_end)
		if inspected_bytes + separator_bytes > u64(NAVIGATION_SOURCE_BYTES) {
			return {}, false, word_navigation_limit_failure(end, inspected_bytes + separator_bytes)
		}
		candidate_blank, candidate_bytes, candidate_ok, candidate_failure := navigation_line_blank(buffer, next)
		if !candidate_ok do return {}, false, candidate_failure
		if inspected_bytes + separator_bytes + candidate_bytes > u64(NAVIGATION_SOURCE_BYTES) {
			return {}, false, word_navigation_limit_failure(next, inspected_bytes + separator_bytes + candidate_bytes)
		}
		if candidate_blank != blank do break
		inspected_bytes += separator_bytes + candidate_bytes
		end = next
	}
	start_position, start_ok, start_failure := editor.buffer_position(buffer, start.start)
	if !start_ok do return {}, false, navigation_editor_failure_from_line(start, start_failure)
	end_position, end_ok, end_failure := editor.buffer_position(buffer, end.next_start)
	if !end_ok do return {}, false, navigation_editor_failure_from_line(end, end_failure)
	return Selection_Range{start = start_position, end = end_position}, true, {}
}

/* navigation_target resolves one grapheme-aware movement without mutating editor state. */
navigation_target :: proc(
	buffer: ^editor.Buffer,
	logical: editor_view.Snapshot,
	kind: Navigation_Kind,
	profile: Display_Profile,
) -> (target: editor.Position, desired_column: u32, ok: bool, failure: Failure_Context) {
	if !display_profile_is_valid(profile) ||
	   Display_Profile_ID(u64(logical.display_profile_id)) != profile.id {
		return {}, 0, false, Failure_Context{code = .Invalid_Profile}
	}
	line, line_ok, line_failure := editor.buffer_line_at_position(
		buffer,
		logical.point_position,
	)
	if !line_ok {
		return {}, 0, false, navigation_editor_failure(logical, line_failure)
	}
	current_column, column_ok, column_failure := position_display_column(
		buffer,
		logical.point_position,
		profile,
		logical.tab_width,
	)
	if !column_ok {
		return {}, 0, false, column_failure
	}
	switch kind {
	case .Line_Start:
		target, ok, line_failure = editor.buffer_position(buffer, line.start)
		return target, 0, ok, navigation_editor_failure_if_needed(logical, line_failure)
	case .Line_End:
		target, ok, line_failure = editor.buffer_position(buffer, line.content_end)
		end_column, end_ok, end_failure := line_boundary_at_column(
			buffer,
			line,
			max(u32),
			profile,
			logical.tab_width,
		)
		if !ok {
			return {}, 0, false, navigation_editor_failure(logical, line_failure)
		}
		if !end_ok {
			return {}, 0, false, end_failure
		}
		return target, end_column.column, true, {}
	case .Previous_Grapheme:
		if logical.point_position.byte_offset == line.start {
			if line.line_index == 0 {
				return logical.point_position, current_column, true, {}
			}
			previous_position, previous_ok, previous_failure := editor.buffer_position(
				buffer,
				editor.Byte_Offset(u64(line.start) - 1),
			)
			if !previous_ok {
				return {}, 0, false, navigation_editor_failure(logical, previous_failure)
			}
			previous_column, previous_column_ok, previous_column_failure := position_display_column(
				buffer,
				previous_position,
				profile,
				logical.tab_width,
			)
			return previous_position, previous_column, previous_column_ok, previous_column_failure
		}
		boundary, boundary_ok, boundary_failure := previous_boundary(
			buffer,
			line,
			logical.point_position.byte_offset,
			profile,
			logical.tab_width,
		)
		return boundary.position, boundary.column, boundary_ok, boundary_failure
	case .Next_Grapheme:
		if logical.point_position.byte_offset == line.content_end {
			if line.next_start == line.content_end {
				return logical.point_position, current_column, true, {}
			}
			next_position, next_ok, next_failure := editor.buffer_position(buffer, line.next_start)
			if !next_ok {
				return {}, 0, false, navigation_editor_failure(logical, next_failure)
			}
			return next_position, 0, true, {}
		}
		boundary, boundary_ok, boundary_failure := next_boundary(
			buffer,
			line,
			logical.point_position.byte_offset,
			profile,
			logical.tab_width,
		)
		return boundary.position, boundary.column, boundary_ok, boundary_failure
	case .Previous_Line, .Next_Line:
		target_line := line
		if kind == .Previous_Line {
			if line.line_index == 0 {
				return logical.point_position, logical.desired_display_column, true, {}
			}
			probe, probe_ok, probe_failure := editor.buffer_position(
				buffer,
				editor.Byte_Offset(u64(line.start) - 1),
			)
			if !probe_ok {
				return {}, 0, false, navigation_editor_failure(logical, probe_failure)
			}
			target_line, line_ok, line_failure = editor.buffer_line_at_position(buffer, probe)
		} else {
			if line.next_start == line.content_end {
				return logical.point_position, logical.desired_display_column, true, {}
			}
			probe, probe_ok, probe_failure := editor.buffer_position(buffer, line.next_start)
			if !probe_ok {
				return {}, 0, false, navigation_editor_failure(logical, probe_failure)
			}
			target_line, line_ok, line_failure = editor.buffer_line_at_position(buffer, probe)
		}
		if !line_ok {
			return {}, 0, false, navigation_editor_failure(logical, line_failure)
		}
		boundary, boundary_ok, boundary_failure := line_boundary_at_column(
			buffer,
			target_line,
			logical.desired_display_column,
			profile,
			logical.tab_width,
		)
		return boundary.position, logical.desired_display_column, boundary_ok, boundary_failure
	case .Previous_Word, .Next_Word:
		forward := kind == .Next_Word
		word_target, target_ok, target_failure := word_navigation_target(buffer, logical, line, forward, profile)
		if !target_ok {
			return {}, 0, false, target_failure
		}
		desired, desired_ok, desired_failure := position_display_column(
			buffer,
			word_target,
			profile,
			logical.tab_width,
		)
		return word_target, desired, desired_ok, desired_failure
	case .Next_Word_Start:
		word_target, target_ok, target_failure := next_word_start_navigation_target(
			buffer,
			logical,
			line,
			profile,
		)
		if !target_ok {
			return {}, 0, false, target_failure
		}
		desired, desired_ok, desired_failure := position_display_column(
			buffer,
			word_target,
			profile,
			logical.tab_width,
		)
		return word_target, desired, desired_ok, desired_failure
	case .Line_First_Non_Whitespace:
		word_target, target_ok, target_failure := first_non_whitespace_target(buffer, line, profile)
		if !target_ok {
			return {}, 0, false, target_failure
		}
		desired, desired_ok, desired_failure := position_display_column(
			buffer,
			word_target,
			profile,
			logical.tab_width,
		)
		return word_target, desired, desired_ok, desired_failure
	case .Buffer_Start, .Buffer_End:
		stats, stats_ok, stats_failure := editor.buffer_stats(buffer)
		if !stats_ok {
			return {}, 0, false, navigation_editor_failure(logical, stats_failure)
		}
		offset := editor.Byte_Offset(0)
		if kind == .Buffer_End do offset = editor.Byte_Offset(stats.text_bytes)
		buffer_target, target_ok, target_failure := editor.buffer_position(buffer, offset)
		if !target_ok {
			return {}, 0, false, navigation_editor_failure(logical, target_failure)
		}
		desired, desired_ok, desired_failure := position_display_column(
			buffer,
			buffer_target,
			profile,
			logical.tab_width,
		)
		return buffer_target, desired, desired_ok, desired_failure
	}
	unreachable()
}

/* line_character_navigation_target resolves one checked match on the current logical line. */
line_character_navigation_target :: proc(
	buffer: ^editor.Buffer,
	logical: editor_view.Snapshot,
	target_text: string,
	kind: Line_Character_Target_Kind,
	occurrence: u64,
	profile: Display_Profile,
) -> (target: editor.Position, desired_column: u32, found: bool, ok: bool, failure: Failure_Context) {
	if !display_profile_is_valid(profile) ||
	   Display_Profile_ID(u64(logical.display_profile_id)) != profile.id ||
	   kind == .Invalid || occurrence == 0 {
		return {}, 0, false, false, Failure_Context{code = .Invalid_Request}
	}
	target_grapheme, target_ok, target_failure := profile_next_grapheme(profile.unicode, target_text, 0)
	if !target_ok {
		return {}, 0, false, false, navigation_profile_failure(
			editor.Buffer_Line{buffer_id = logical.buffer_id, revision = logical.revision},
			target_failure,
		)
	}
	if target_grapheme.start != 0 || target_grapheme.end != u64(len(target_text)) {
		return {}, 0, false, false, Failure_Context{code = .Invalid_Request}
	}
	line, line_ok, line_failure := editor.buffer_line_at_position(buffer, logical.point_position)
	if !line_ok do return {}, 0, false, false, navigation_editor_failure(logical, line_failure)
	scratch: [NAVIGATION_SOURCE_BYTES]u8
	text, text_ok, text_failure := inspect_navigation_line(buffer, line, scratch[:])
	if !text_ok do return {}, 0, false, false, text_failure
	point := u64(logical.point_position.byte_offset) - u64(line.start)
	matched_start: u64
	matched_end: u64
	matches: u64
	matched := false
	if kind == .Find_Next || kind == .Till_Next {
		parsed := point
		if parsed < u64(len(text)) {
			current, current_ok, current_failure := profile_next_grapheme(profile.unicode, text, parsed)
			if !current_ok do return {}, 0, false, false, navigation_profile_failure(line, current_failure)
			parsed = current.end
		}
		for parsed < u64(len(text)) {
			candidate, candidate_ok, candidate_failure := profile_next_grapheme(profile.unicode, text, parsed)
			if !candidate_ok do return {}, 0, false, false, navigation_profile_failure(line, candidate_failure)
			if text[candidate.start:candidate.end] == target_text {
				matches += 1
				if matches == occurrence {
					matched_start = candidate.start
					matched_end = candidate.end
					matched = true
					break
				}
			}
			parsed = candidate.end
		}
	} else {
		parsed: u64
		for parsed < point {
			candidate, candidate_ok, candidate_failure := profile_next_grapheme(profile.unicode, text, parsed)
			if !candidate_ok || candidate.end > point {
				return {}, 0, false, false, navigation_profile_failure(line, candidate_failure)
			}
			if text[candidate.start:candidate.end] == target_text do matches += 1
			parsed = candidate.end
		}
		if matches >= occurrence {
			desired_match := matches - occurrence + 1
			matches = 0
			parsed = 0
			for parsed < point {
				candidate, candidate_ok, candidate_failure := profile_next_grapheme(
					profile.unicode, text, parsed,
				)
				if !candidate_ok do return {}, 0, false, false, navigation_profile_failure(line, candidate_failure)
				if text[candidate.start:candidate.end] == target_text {
					matches += 1
					if matches == desired_match {
						matched_start = candidate.start
						matched_end = candidate.end
						matched = true
						break
					}
				}
				parsed = candidate.end
			}
		}
	}
	if !matched {
		return logical.point_position, logical.desired_display_column, false, true, {}
	}
	target_offset := matched_start
	if kind == .Till_Next {
		if matched_start == 0 do return logical.point_position, logical.desired_display_column, false, true, {}
		parsed: u64
		for parsed < matched_start {
			previous, previous_ok, previous_failure := profile_next_grapheme(
				profile.unicode, text, parsed,
			)
			if !previous_ok do return {}, 0, false, false, navigation_profile_failure(line, previous_failure)
			if previous.end == matched_start {
				target_offset = previous.start
				break
			}
			parsed = previous.end
		}
	} else if kind == .Till_Previous {
		target_offset = matched_end
	}
	position, position_ok, position_failure := editor.buffer_position(
		buffer,
		editor.Byte_Offset(u64(line.start) + target_offset),
	)
	if !position_ok do return {}, 0, false, false, navigation_editor_failure_from_line(line, position_failure)
	desired, desired_ok, desired_failure := position_display_column(
		buffer,
		position,
		profile,
		logical.tab_width,
	)
	return position, desired, true, desired_ok, desired_failure
}

/* position_display_column resolves one current position to its logical line column. */
position_display_column :: proc(
	buffer: ^editor.Buffer,
	position: editor.Position,
	profile: Display_Profile,
	tab_width: u16,
) -> (column: u32, ok: bool, failure: Failure_Context) {
	line, line_ok, line_failure := editor.buffer_line_at_position(buffer, position)
	if !line_ok {
		return 0, false, Failure_Context{code = .Editor_Failure, editor_failure = line_failure}
	}
	boundary, boundary_ok, boundary_failure := line_boundary_at_offset(
		buffer,
		line,
		position.byte_offset,
		profile,
		tab_width,
	)
	return boundary.column, boundary_ok, boundary_failure
}

@(private)
Navigation_Boundary :: struct {
	position: editor.Position,
	column:   u32,
}

@(private)
previous_boundary :: proc(
	buffer: ^editor.Buffer,
	line: editor.Buffer_Line,
	offset: editor.Byte_Offset,
	profile: Display_Profile,
	tab_width: u16,
) -> (Navigation_Boundary, bool, Failure_Context) {
	scratch: [NAVIGATION_SOURCE_BYTES]u8
	text, text_ok, text_failure := inspect_navigation_line(buffer, line, scratch[:])
	if !text_ok {
		return {}, false, text_failure
	}
	target := u64(offset) - u64(line.start)
	parsed: u64
	column: u32
	previous_offset: u64
	previous_column: u32
	for parsed < target {
		grapheme, grapheme_ok, grapheme_failure := profile_next_grapheme(profile.unicode, text, parsed)
		if !grapheme_ok || grapheme.end > target {
			return {}, false, navigation_profile_failure(line, grapheme_failure)
		}
		previous_offset = parsed
		previous_column = column
		width, width_ok, width_failure := profile_cluster_width(
			profile.unicode,
			text[grapheme.start:grapheme.end],
			column,
			tab_width,
		)
		if !width_ok {
			return {}, false, navigation_profile_failure(line, width_failure)
		}
		column += u32(width.cells)
		parsed = grapheme.end
	}
	position, position_ok, position_failure := editor.buffer_position(
		buffer,
		editor.Byte_Offset(u64(line.start) + previous_offset),
	)
	if !position_ok {
		return {}, false, navigation_editor_failure_from_line(line, position_failure)
	}
	return Navigation_Boundary{position = position, column = previous_column}, true, {}
}

@(private)
next_boundary :: proc(
	buffer: ^editor.Buffer,
	line: editor.Buffer_Line,
	offset: editor.Byte_Offset,
	profile: Display_Profile,
	tab_width: u16,
) -> (Navigation_Boundary, bool, Failure_Context) {
	scratch: [NAVIGATION_SOURCE_BYTES]u8
	text, text_ok, text_failure := inspect_navigation_line(buffer, line, scratch[:])
	if !text_ok {
		return {}, false, text_failure
	}
	target := u64(offset) - u64(line.start)
	column, column_ok, column_failure := column_at_local_offset(text, target, line, profile, tab_width)
	if !column_ok {
		return {}, false, column_failure
	}
	grapheme, grapheme_ok, grapheme_failure := profile_next_grapheme(profile.unicode, text, target)
	if !grapheme_ok {
		return {}, false, navigation_profile_failure(line, grapheme_failure)
	}
	width, width_ok, width_failure := profile_cluster_width(
		profile.unicode,
		text[grapheme.start:grapheme.end],
		column,
		tab_width,
	)
	if !width_ok {
		return {}, false, navigation_profile_failure(line, width_failure)
	}
	position, position_ok, position_failure := editor.buffer_position(
		buffer,
		editor.Byte_Offset(u64(line.start) + grapheme.end),
	)
	if !position_ok {
		return {}, false, navigation_editor_failure_from_line(line, position_failure)
	}
	return Navigation_Boundary {
		position = position,
		column = column + u32(width.cells),
	}, true, {}
}

@(private)
word_navigation_target :: proc(
	buffer: ^editor.Buffer,
	logical: editor_view.Snapshot,
	line: editor.Buffer_Line,
	forward: bool,
	profile: Display_Profile,
) -> (editor.Position, bool, Failure_Context) {
	current_line := line
	current_offset := u64(logical.point_position.byte_offset) - u64(line.start)
	inspected_bytes: u64
	for {
		scratch: [NAVIGATION_SOURCE_BYTES]u8
		text, text_ok, text_failure := inspect_navigation_line(buffer, current_line, scratch[:])
		if !text_ok {
			return {}, false, text_failure
		}
		line_bytes := u64(len(text))
		if inspected_bytes + line_bytes > u64(NAVIGATION_SOURCE_BYTES) {
			return {}, false, word_navigation_limit_failure(current_line, inspected_bytes + line_bytes)
		}
		inspected_bytes += line_bytes

		local_target: u64
		found: bool
		if forward {
			local_target, found, text_failure = next_word_target(text, current_offset, current_line, profile)
		} else {
			local_target, found, text_failure = previous_word_target(text, current_offset, current_line, profile)
		}
		if text_failure.code != .None {
			return {}, false, text_failure
		}
		if found {
			position, position_ok, position_failure := editor.buffer_position(
				buffer,
				editor.Byte_Offset(u64(current_line.start) + local_target),
			)
			if !position_ok {
				return {}, false, navigation_editor_failure_from_line(current_line, position_failure)
			}
			return position, true, {}
		}

		if forward {
			if current_line.next_start == current_line.content_end {
				position, position_ok, position_failure := editor.buffer_position(buffer, current_line.content_end)
				if !position_ok {
					return {}, false, navigation_editor_failure_from_line(current_line, position_failure)
				}
				return position, true, {}
			}
			separator_bytes := u64(current_line.next_start) - u64(current_line.content_end)
			if inspected_bytes + separator_bytes > u64(NAVIGATION_SOURCE_BYTES) {
				return {}, false, word_navigation_limit_failure(current_line, inspected_bytes + separator_bytes)
			}
			inspected_bytes += separator_bytes
			probe, probe_ok, probe_failure := editor.buffer_position(buffer, current_line.next_start)
			if !probe_ok {
				return {}, false, navigation_editor_failure_from_line(current_line, probe_failure)
			}
			next_line, next_line_ok, next_line_failure := editor.buffer_line_at_position(buffer, probe)
			if !next_line_ok {
				return {}, false, navigation_editor_failure(logical, next_line_failure)
			}
			current_line = next_line
			current_offset = 0
		} else {
			if current_line.line_index == 0 {
				position, position_ok, position_failure := editor.buffer_position(buffer, current_line.start)
				if !position_ok {
					return {}, false, navigation_editor_failure_from_line(current_line, position_failure)
				}
				return position, true, {}
			}
			next_start := current_line.start
			probe, probe_ok, probe_failure := editor.buffer_position(
				buffer,
				editor.Byte_Offset(u64(current_line.start) - 1),
			)
			if !probe_ok {
				return {}, false, navigation_editor_failure_from_line(current_line, probe_failure)
			}
			previous_line, previous_line_ok, previous_line_failure := editor.buffer_line_at_position(buffer, probe)
			if !previous_line_ok {
				return {}, false, navigation_editor_failure(logical, previous_line_failure)
			}
			separator_bytes := u64(next_start) - u64(previous_line.content_end)
			if inspected_bytes + separator_bytes > u64(NAVIGATION_SOURCE_BYTES) {
				return {}, false, word_navigation_limit_failure(current_line, inspected_bytes + separator_bytes)
			}
			inspected_bytes += separator_bytes
			current_line = previous_line
			current_offset = u64(current_line.content_end) - u64(current_line.start)
		}
	}
}

@(private)
next_word_start_navigation_target :: proc(
	buffer: ^editor.Buffer,
	logical: editor_view.Snapshot,
	line: editor.Buffer_Line,
	profile: Display_Profile,
) -> (editor.Position, bool, Failure_Context) {
	current_line := line
	current_offset := u64(logical.point_position.byte_offset) - u64(line.start)
	inspected_bytes: u64
	current_class := Word_Navigation_Class.Invalid
	left_current_class := false
	first_line := true
	for {
		scratch: [NAVIGATION_SOURCE_BYTES]u8
		text, text_ok, text_failure := inspect_navigation_line(buffer, current_line, scratch[:])
		if !text_ok do return {}, false, text_failure
		line_bytes := u64(len(text))
		if inspected_bytes + line_bytes > u64(NAVIGATION_SOURCE_BYTES) {
			return {}, false, word_navigation_limit_failure(current_line, inspected_bytes + line_bytes)
		}
		inspected_bytes += line_bytes
		if first_line && current_offset < line_bytes {
			current, current_ok, current_failure := profile_next_grapheme(
				profile.unicode,
				text,
				current_offset,
			)
			if !current_ok do return {}, false, navigation_profile_failure(current_line, current_failure)
			current_class, current_ok = grapheme_word_navigation_class(
				text[current.start:current.end],
			)
			if !current_ok {
				return {}, false, navigation_profile_failure(
					current_line,
					Profile_Failure{code = .Malformed_UTF8},
				)
			}
		}
		parsed := current_offset
		for parsed < line_bytes {
			candidate, candidate_ok, candidate_failure := profile_next_grapheme(profile.unicode, text, parsed)
			if !candidate_ok do return {}, false, navigation_profile_failure(current_line, candidate_failure)
			candidate_class, class_ok := grapheme_word_navigation_class(
				text[candidate.start:candidate.end],
			)
			if !class_ok {
				return {}, false, navigation_profile_failure(
					current_line,
					Profile_Failure{code = .Malformed_UTF8},
				)
			}
			if !left_current_class {
				if candidate_class == current_class {
					parsed = candidate.end
					continue
				}
				left_current_class = true
			}
			if candidate_class != .Whitespace {
				position, position_ok, position_failure := editor.buffer_position(
					buffer,
					editor.Byte_Offset(u64(current_line.start) + candidate.start),
				)
				if !position_ok {
					return {}, false, navigation_editor_failure_from_line(current_line, position_failure)
				}
				return position, true, {}
			}
			parsed = candidate.end
		}
		if current_line.next_start == current_line.content_end {
			position, position_ok, position_failure := editor.buffer_position(buffer, current_line.content_end)
			if !position_ok {
				return {}, false, navigation_editor_failure_from_line(current_line, position_failure)
			}
			return position, true, {}
		}
		separator_bytes := u64(current_line.next_start) - u64(current_line.content_end)
		if inspected_bytes + separator_bytes > u64(NAVIGATION_SOURCE_BYTES) {
			return {}, false, word_navigation_limit_failure(current_line, inspected_bytes + separator_bytes)
		}
		inspected_bytes += separator_bytes
		probe, probe_ok, probe_failure := editor.buffer_position(buffer, current_line.next_start)
		if !probe_ok do return {}, false, navigation_editor_failure_from_line(current_line, probe_failure)
		next_line, next_ok, next_failure := editor.buffer_line_at_position(buffer, probe)
		if !next_ok do return {}, false, navigation_editor_failure(logical, next_failure)
		current_line = next_line
		current_offset = 0
		left_current_class = true
		first_line = false
	}
}

@(private)
Word_Navigation_Class :: enum u8 {
	Invalid,
	Word,
	Whitespace,
	Punctuation,
}

@(private)
grapheme_word_navigation_class :: proc(grapheme: string) -> (Word_Navigation_Class, bool) {
	first, bytes := utf8.decode_rune(grapheme)
	if bytes == 0 || first == utf8.RUNE_ERROR && bytes == 1 do return .Invalid, false
	if unicode.is_letter(first) || unicode.is_digit(first) || first == '_' do return .Word, true
	if unicode.is_space(first) do return .Whitespace, true
	return .Punctuation, true
}

@(private)
next_word_target :: proc(
	text: string,
	start: u64,
	line: editor.Buffer_Line,
	profile: Display_Profile,
) -> (target: u64, found: bool, failure: Failure_Context) {
	parsed := start
	in_word := false
	for parsed < u64(len(text)) {
		grapheme, grapheme_ok, grapheme_failure := profile_next_grapheme(profile.unicode, text, parsed)
		if !grapheme_ok {
			return 0, false, navigation_profile_failure(line, grapheme_failure)
		}
		word, word_ok := grapheme_is_word(text[grapheme.start:grapheme.end])
		if !word_ok {
			return 0, false, navigation_profile_failure(line, Profile_Failure{code = .Malformed_UTF8})
		}
		if word {
			in_word = true
		} else if in_word {
			return parsed, true, {}
		}
		parsed = grapheme.end
	}
	if in_word {
		return parsed, true, {}
	}
	return 0, false, {}
}

@(private)
previous_word_target :: proc(
	text: string,
	end: u64,
	line: editor.Buffer_Line,
	profile: Display_Profile,
) -> (target: u64, found: bool, failure: Failure_Context) {
	parsed: u64
	run_start: u64
	last_word_start: u64
	in_word := false
	found_word := false
	for parsed < end {
		grapheme, grapheme_ok, grapheme_failure := profile_next_grapheme(profile.unicode, text, parsed)
		if !grapheme_ok || grapheme.end > end {
			return 0, false, navigation_profile_failure(line, grapheme_failure)
		}
		word, word_ok := grapheme_is_word(text[grapheme.start:grapheme.end])
		if !word_ok {
			return 0, false, navigation_profile_failure(line, Profile_Failure{code = .Malformed_UTF8})
		}
		if word {
			if !in_word {
				run_start = grapheme.start
			}
			last_word_start = run_start
			found_word = true
		}
		in_word = word
		parsed = grapheme.end
	}
	return last_word_start, found_word, {}
}

@(private)
word_selection_offsets :: proc(
	text: string,
	point: u64,
	line: editor.Buffer_Line,
	profile: Display_Profile,
) -> (start, end: u64, found: bool, failure: Failure_Context) {
	parsed: u64
	previous_start: u64
	previous_end: u64
	previous_found := false
	in_word := false
	run_start: u64
	for parsed < u64(len(text)) {
		grapheme, grapheme_ok, grapheme_failure := profile_next_grapheme(profile.unicode, text, parsed)
		if !grapheme_ok do return 0, 0, false, navigation_profile_failure(line, grapheme_failure)
		word, word_ok := grapheme_is_word(text[grapheme.start:grapheme.end])
		if !word_ok {
			return 0, 0, false, navigation_profile_failure(line, Profile_Failure{code = .Malformed_UTF8})
		}
		if word && !in_word do run_start = grapheme.start
		if !word && in_word {
			if run_start <= point && point < parsed do return run_start, parsed, true, {}
			if run_start >= point do return run_start, parsed, true, {}
			previous_start = run_start
			previous_end = parsed
			previous_found = true
		}
		in_word = word
		parsed = grapheme.end
	}
	if in_word {
		if run_start <= point && point < parsed do return run_start, parsed, true, {}
		if run_start >= point do return run_start, parsed, true, {}
		previous_start = run_start
		previous_end = parsed
		previous_found = true
	}
	return previous_start, previous_end, previous_found, {}
}

@(private)
navigation_line_blank :: proc(
	buffer: ^editor.Buffer,
	line: editor.Buffer_Line,
) -> (blank: bool, inspected: u64, ok: bool, failure: Failure_Context) {
	scratch: [NAVIGATION_SOURCE_BYTES]u8
	text, text_ok, text_failure := inspect_navigation_line(buffer, line, scratch[:])
	if !text_ok do return false, 0, false, text_failure
	parsed: u64
	for parsed < u64(len(text)) {
		rune, bytes := utf8.decode_rune(text[parsed:])
		if bytes == 0 || rune == utf8.RUNE_ERROR && bytes == 1 {
			return false, 0, false, navigation_profile_failure(line, Profile_Failure{code = .Malformed_UTF8})
		}
		if !unicode.is_space(rune) do return false, u64(len(text)), true, {}
		parsed += u64(bytes)
	}
	return true, u64(len(text)), true, {}
}

@(private)
grapheme_is_word :: proc(grapheme: string) -> (bool, bool) {
	first, bytes := utf8.decode_rune(grapheme)
	if bytes == 0 || first == utf8.RUNE_ERROR && bytes == 1 {
		return false, false
	}
	return unicode.is_letter(first) || unicode.is_digit(first) || first == '_', true
}

@(private)
word_navigation_limit_failure :: proc(line: editor.Buffer_Line, actual: u64) -> Failure_Context {
	return Failure_Context {
		code = .Source_Byte_Limit,
		buffer_id = line.buffer_id,
		buffer_revision = line.revision,
		limit = u64(NAVIGATION_SOURCE_BYTES),
		actual = actual,
	}
}

@(private)
first_non_whitespace_target :: proc(
	buffer: ^editor.Buffer,
	line: editor.Buffer_Line,
	profile: Display_Profile,
) -> (editor.Position, bool, Failure_Context) {
	scratch: [NAVIGATION_SOURCE_BYTES]u8
	text, text_ok, text_failure := inspect_navigation_line(buffer, line, scratch[:])
	if !text_ok {
		return {}, false, text_failure
	}
	target := u64(len(text))
	parsed: u64
	for parsed < u64(len(text)) {
		grapheme, grapheme_ok, grapheme_failure := profile_next_grapheme(profile.unicode, text, parsed)
		if !grapheme_ok {
			return {}, false, navigation_profile_failure(line, grapheme_failure)
		}
		whitespace, whitespace_ok := grapheme_is_whitespace(text[grapheme.start:grapheme.end])
		if !whitespace_ok {
			return {}, false, navigation_profile_failure(line, Profile_Failure{code = .Malformed_UTF8})
		}
		if !whitespace {
			target = grapheme.start
			break
		}
		parsed = grapheme.end
	}
	position, position_ok, position_failure := editor.buffer_position(
		buffer,
		editor.Byte_Offset(u64(line.start) + target),
	)
	if !position_ok {
		return {}, false, navigation_editor_failure_from_line(line, position_failure)
	}
	return position, true, {}
}

@(private)
grapheme_is_whitespace :: proc(grapheme: string) -> (bool, bool) {
	first, bytes := utf8.decode_rune(grapheme)
	if bytes == 0 || first == utf8.RUNE_ERROR && bytes == 1 {
		return false, false
	}
	return unicode.is_space(first), true
}

@(private)
line_boundary_at_offset :: proc(
	buffer: ^editor.Buffer,
	line: editor.Buffer_Line,
	offset: editor.Byte_Offset,
	profile: Display_Profile,
	tab_width: u16,
) -> (Navigation_Boundary, bool, Failure_Context) {
	scratch: [NAVIGATION_SOURCE_BYTES]u8
	text, text_ok, text_failure := inspect_navigation_line(buffer, line, scratch[:])
	if !text_ok {
		return {}, false, text_failure
	}
	local := u64(offset) - u64(line.start)
	column, column_ok, column_failure := column_at_local_offset(text, local, line, profile, tab_width)
	if !column_ok {
		return {}, false, column_failure
	}
	return Navigation_Boundary{position = editor.Position{
		buffer_id = line.buffer_id,
		revision = line.revision,
		byte_offset = offset,
	}, column = column}, true, {}
}

@(private)
line_boundary_at_column :: proc(
	buffer: ^editor.Buffer,
	line: editor.Buffer_Line,
	desired: u32,
	profile: Display_Profile,
	tab_width: u16,
) -> (Navigation_Boundary, bool, Failure_Context) {
	scratch: [NAVIGATION_SOURCE_BYTES]u8
	text, text_ok, text_failure := inspect_navigation_line(buffer, line, scratch[:])
	if !text_ok {
		return {}, false, text_failure
	}
	parsed: u64
	column: u32
	best_offset: u64
	best_column: u32
	for parsed < u64(len(text)) {
		grapheme, grapheme_ok, grapheme_failure := profile_next_grapheme(profile.unicode, text, parsed)
		if !grapheme_ok {
			return {}, false, navigation_profile_failure(line, grapheme_failure)
		}
		width, width_ok, width_failure := profile_cluster_width(
			profile.unicode,
			text[grapheme.start:grapheme.end],
			column,
			tab_width,
		)
		if !width_ok {
			return {}, false, navigation_profile_failure(line, width_failure)
		}
		next_column := column + u32(width.cells)
		if desired < next_column {
			if desired - min(desired, column) > next_column - desired {
				best_offset = grapheme.end
				best_column = next_column
			}
			break
		}
		best_offset = grapheme.end
		best_column = next_column
		column = next_column
		parsed = grapheme.end
	}
	position, position_ok, position_failure := editor.buffer_position(
		buffer,
		editor.Byte_Offset(u64(line.start) + best_offset),
	)
	if !position_ok {
		return {}, false, navigation_editor_failure_from_line(line, position_failure)
	}
	return Navigation_Boundary{position = position, column = best_column}, true, {}
}

@(private)
column_at_local_offset :: proc(
	text: string,
	target: u64,
	line: editor.Buffer_Line,
	profile: Display_Profile,
	tab_width: u16,
) -> (u32, bool, Failure_Context) {
	parsed: u64
	column: u32
	for parsed < target {
		grapheme, grapheme_ok, grapheme_failure := profile_next_grapheme(profile.unicode, text, parsed)
		if !grapheme_ok || grapheme.end > target {
			return 0, false, navigation_profile_failure(line, grapheme_failure)
		}
		width, width_ok, width_failure := profile_cluster_width(
			profile.unicode,
			text[grapheme.start:grapheme.end],
			column,
			tab_width,
		)
		if !width_ok {
			return 0, false, navigation_profile_failure(line, width_failure)
		}
		column += u32(width.cells)
		parsed = grapheme.end
	}
	if parsed != target {
		return 0, false, Failure_Context{code = .Mapping_Miss, actual = target}
	}
	return column, true, {}
}

@(private)
inspect_navigation_line :: proc(
	buffer: ^editor.Buffer,
	line: editor.Buffer_Line,
	destination: []u8,
) -> (string, bool, Failure_Context) {
	line_bytes := u64(line.content_end) - u64(line.start)
	if line_bytes > u64(NAVIGATION_SOURCE_BYTES) || line_bytes > u64(len(destination)) {
		return "", false, Failure_Context {
			code = .Source_Byte_Limit,
			buffer_id = line.buffer_id,
			buffer_revision = line.revision,
			limit = u64(NAVIGATION_SOURCE_BYTES),
			actual = line_bytes,
		}
	}
	_, inspected, inspection_failure := editor.buffer_inspect(
		buffer,
		line.start,
		line.content_end,
		destination[:int(line_bytes)],
	)
	if !inspected {
		return "", false, navigation_editor_failure_from_line(line, inspection_failure)
	}
	return string(destination[:int(line_bytes)]), true, {}
}

@(private)
navigation_profile_failure :: proc(line: editor.Buffer_Line, failure: Profile_Failure) -> Failure_Context {
	return Failure_Context {
		code = .Malformed_UTF8,
		buffer_id = line.buffer_id,
		buffer_revision = line.revision,
		actual = failure.actual,
	}
}

@(private)
navigation_editor_failure :: proc(logical: editor_view.Snapshot, failure: editor.Failure_Context) -> Failure_Context {
	return Failure_Context {
		code = .Editor_Failure,
		buffer_id = logical.buffer_id,
		buffer_revision = logical.revision,
		editor_failure = failure,
	}
}

@(private)
navigation_editor_failure_from_line :: proc(line: editor.Buffer_Line, failure: editor.Failure_Context) -> Failure_Context {
	return Failure_Context {
		code = .Editor_Failure,
		buffer_id = line.buffer_id,
		buffer_revision = line.revision,
		editor_failure = failure,
	}
}

@(private)
navigation_editor_failure_if_needed :: proc(logical: editor_view.Snapshot, failure: editor.Failure_Context) -> Failure_Context {
	if failure.code == .None {
		return {}
	}
	return navigation_editor_failure(logical, failure)
}
