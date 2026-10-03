// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package search

import "base:runtime"
import "core:unicode/utf8"

/* Source_Match is one byte range produced from borrowed immutable source text. */
Source_Match :: struct {
	start: u64,
	end:   u64,
}

/* Source_Turn reports one bounded forward scan over immutable source text. */
Source_Turn :: struct {
	matches:             u32,
	next_offset:         u64,
	logical_bytes:       u64,
	read_bytes:          u64,
	cancellation_checks: u64,
	complete:            bool,
}

/* source_search_turn applies one admitted query without creating an editor buffer. */
source_search_turn :: proc(
	query: ^Query,
	source: string,
	origin: u64,
	destination: []Source_Match,
	temporary_allocator: runtime.Allocator,
) -> (turn: Source_Turn, ok: bool, failure: Failure) {
	view, viewed, query_failure := query_view(query)
	if !viewed {
		return {}, false, query_failure
	}
	if !utf8.valid_string(source) {
		return {}, false, Failure{code = .Malformed_UTF8, query_id = view.id, actual = u64(len(source))}
	}
	if temporary_allocator.procedure == nil {
		return {}, false, Failure{code = .Temporary_Memory_Limit, query_id = view.id}
	}
	if len(destination) == 0 {
		return {}, false, Failure{code = .Work_Limit, query_id = view.id}
	}
	if origin > u64(len(source)) || !source_offset_is_boundary(source, origin) {
		return {}, false, Failure{code = .Out_Of_Range, query_id = view.id,
			limit = u64(len(source)), actual = origin}
	}
	if origin == u64(len(source)) {
		return Source_Turn{next_offset = origin, complete = true}, true, {}
	}
	if view.kind == .Literal {
		return source_literal_turn(view, source, origin, destination)
	}
	if view.kind == .Regular_Expression {
		return source_regexp_turn(query, view, source, origin, destination, temporary_allocator)
	}
	return {}, false, Failure{code = .Invalid_Pattern_Kind, query_id = view.id}
}

@(private)
source_literal_turn :: proc(
	query: Query_View,
	source: string,
	origin: u64,
	destination: []Source_Match,
) -> (Source_Turn, bool, Failure) {
	bytes := transmute([]byte)source
	logical_end := min(u64(len(bytes)), origin + query.limits.scan_window_bytes)
	overlap := query.pattern_runes * 4
	read_end := min(u64(len(bytes)), logical_end + overlap)
	read_end = source_next_boundary(source, read_end)
	window := bytes[:int(read_end)]
	cursor := int(origin)
	count := 0
	for cursor < int(logical_end) {
		match_end, matched := literal_match_at(window, cursor, query)
		next := next_rune_boundary(bytes, cursor)
		if matched && u64(match_end) <= u64(len(bytes)) {
			destination[count] = {start = u64(cursor), end = u64(match_end)}
			count += 1
			if count == len(destination) {
				return Source_Turn{matches = u32(count), next_offset = u64(next),
					logical_bytes = u64(next) - origin, read_bytes = read_end - origin,
					cancellation_checks = 1, complete = next >= len(bytes)}, true, {}
			}
		}
		cursor = next
	}
	next := source_next_boundary(source, logical_end)
	return Source_Turn{matches = u32(count), next_offset = next,
		logical_bytes = next - origin, read_bytes = read_end - origin,
		cancellation_checks = 1, complete = next >= u64(len(bytes))}, true, {}
}

@(private)
source_regexp_turn :: proc(
	query: ^Query,
	view: Query_View,
	source: string,
	origin: u64,
	destination: []Source_Match,
	temporary_allocator: runtime.Allocator,
) -> (Source_Turn, bool, Failure) {
	logical_end := min(u64(len(source)), origin + view.limits.scan_window_bytes)
	read_end := min(u64(len(source)), logical_end + view.limits.match_span_bytes - 1)
	read_end = source_next_boundary(source, read_end)
	window := source[int(origin):int(read_end)]
	matcher: Regex_Matcher
	initialized, failure := regex_matcher_init(&matcher, query, window, temporary_allocator)
	if !initialized {
		return {}, false, failure
	}
	defer regex_matcher_close(&matcher)
	count := 0
	next := source_next_boundary(source, logical_end)
	for {
		group_count, matched := regex_matcher_match(&matcher)
		if !matched || group_count == 0 {
			break
		}
		whole := matcher.positions[0]
		if whole[0] < 0 || whole[1] < whole[0] || whole[1] > len(window) {
			return {}, false, Failure{code = .Out_Of_Range, query_id = view.id}
		}
		start := origin + u64(whole[0])
		end := origin + u64(whole[1])
		if end - start > view.limits.match_span_bytes {
			return {}, false, Failure{code = .Match_Span_Limit, query_id = view.id,
				limit = view.limits.match_span_bytes, actual = end - start}
		}
		if start >= logical_end {
			break
		}
		if match_respects_boundary(transmute([]byte)source, int(start), int(end), view.policy.boundary_mode) {
			destination[count] = {start = start, end = end}
			count += 1
			if count == len(destination) {
				if end > start {
					next = end
				} else {
					next = source_next_boundary(source, start + 1)
				}
				return Source_Turn{matches = u32(count), next_offset = next,
					logical_bytes = next - origin, read_bytes = read_end - origin,
					cancellation_checks = 1, complete = next >= u64(len(source))}, true, {}
			}
		}
		if whole[0] == whole[1] && !regex_matcher_advance_empty(&matcher, transmute([]byte)window, whole[1]) {
			break
		}
	}
	return Source_Turn{matches = u32(count), next_offset = next,
		logical_bytes = next - origin, read_bytes = read_end - origin,
		cancellation_checks = 1, complete = next >= u64(len(source))}, true, {}
}

@(private)
source_offset_is_boundary :: proc(source: string, offset: u64) -> bool {
	return offset == 0 || offset == u64(len(source)) ||
		(transmute([]byte)source)[int(offset)] & 0xc0 != 0x80
}

@(private)
source_next_boundary :: proc(source: string, offset: u64) -> u64 {
	result := min(offset, u64(len(source)))
	bytes := transmute([]byte)source
	for result < u64(len(bytes)) && bytes[int(result)] & 0xc0 == 0x80 do result += 1
	return result
}
