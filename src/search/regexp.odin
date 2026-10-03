// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package search

import "../editor"
import "base:runtime"
import "core:mem"
import "core:text/regex"
import "core:unicode/utf8"

/* Regex_Window describes one bounded contiguous view over a rope snapshot. */
Regex_Window :: struct {
	logical_start: editor.Byte_Offset,
	logical_end:   editor.Byte_Offset,
	read_start:    editor.Byte_Offset,
	read_end:      editor.Byte_Offset,
}

/*
regex_match_contiguous applies one compiled query to one admitted rope window.
Capture positions are copied as byte offsets relative to the borrowed window.
*/
regex_match_contiguous :: proc(
	query: ^Query,
	window_text: string,
	capture_positions: [][2]int,
	temporary_allocator: runtime.Allocator,
) -> (group_count: int, matched: bool, failure: Failure) {
	view, viewed, query_failure := query_view(query)
	if !viewed {
		return 0, false, query_failure
	}
	if view.kind != .Regular_Expression {
		return 0, false, Failure{code = .Invalid_Pattern_Kind, query_id = view.id}
	}
	if !utf8.valid_string(window_text) {
		return 0, false, Failure {
			code = .Malformed_UTF8,
			query_id = view.id,
			actual = u64(len(window_text)),
		}
	}
	maximum_window_bytes := view.limits.scan_window_bytes + view.limits.match_span_bytes - 1
	if u64(len(window_text)) > maximum_window_bytes {
		return 0, false, Failure {
			code = .Work_Limit,
			query_id = view.id,
			limit = maximum_window_bytes,
			actual = u64(len(window_text)),
		}
	}
	if len(capture_positions) < int(view.limits.capture_groups) {
		return 0, false, Failure {
			code = .Capture_Limit,
			query_id = view.id,
			limit = u64(view.limits.capture_groups),
			actual = u64(len(capture_positions)),
		}
	}
	if temporary_allocator.procedure == nil {
		return 0, false, Failure{code = .Temporary_Memory_Limit, query_id = view.id}
	}
	compiled, compiled_ok := query_compiled_regex(query)
	if !compiled_ok {
		return 0, false, Failure{code = .Closed_Query, query_id = view.id}
	}
	match_arena: mem.Dynamic_Arena
	mem.dynamic_arena_init(&match_arena, temporary_allocator, temporary_allocator)
	defer mem.dynamic_arena_destroy(&match_arena)
	arena_allocator := mem.dynamic_arena_allocator(&match_arena)
	capture := regex.preallocate_capture(arena_allocator)
	group_count, matched = regex.match_with_preallocated_capture(
		compiled,
		window_text,
		&capture,
		arena_allocator,
	)
	if !matched {
		return 0, false, {}
	}
	if group_count > len(capture_positions) {
		return 0, false, Failure {
			code = .Capture_Limit,
			query_id = view.id,
			limit = u64(len(capture_positions)),
			actual = u64(group_count),
		}
	}
	copy(capture_positions[:group_count], capture.pos[:group_count])
	return group_count, true, {}
}

/*
regex_window_plan bounds one regex turn and its cross-window match overlap.
Matches longer than the admitted maximum span are rejected by navigation.
*/
regex_window_plan :: proc(
	query: ^Query,
	request: Request,
) -> (window: Regex_Window, ok: bool, failure: Failure) {
	view, viewed, query_failure := query_view(query)
	if !viewed {
		return {}, false, query_failure
	}
	if view.kind != .Regular_Expression {
		return {}, false, Failure{code = .Invalid_Pattern_Kind, query_id = view.id}
	}
	if request.direction != .Forward && request.direction != .Backward {
		return {}, false, Failure{code = .Invalid_Direction, query_id = view.id}
	}
	scope_start := u64(request.scope.start)
	scope_end := u64(request.scope.end)
	origin := u64(request.origin)
	if scope_start > scope_end {
		return {}, false, Failure {
			code = .Invalid_Scope,
			buffer_id = request.scope.buffer_id,
			revision = request.scope.revision,
			query_id = view.id,
			limit = scope_end,
			actual = scope_start,
		}
	}
	if origin < scope_start || origin > scope_end {
		return {}, false, Failure {
			code = .Out_Of_Range,
			buffer_id = request.scope.buffer_id,
			revision = request.scope.revision,
			query_id = view.id,
			limit = scope_end,
			actual = origin,
		}
	}
	overlap := view.limits.match_span_bytes - 1
	if request.direction == .Forward {
		logical_end := min(scope_end, origin + view.limits.scan_window_bytes)
		read_end := min(scope_end, logical_end + overlap)
		return Regex_Window {
			logical_start = request.origin,
			logical_end = editor.Byte_Offset(logical_end),
			read_start = request.origin,
			read_end = editor.Byte_Offset(read_end),
		}, true, {}
	}
	logical_start := max(
		scope_start,
		origin - min(origin - scope_start, view.limits.scan_window_bytes),
	)
	read_start := max(
		scope_start,
		logical_start - min(logical_start - scope_start, overlap),
	)
	return Regex_Window {
		logical_start = editor.Byte_Offset(logical_start),
		logical_end = request.origin,
		read_start = editor.Byte_Offset(read_start),
		read_end = request.origin,
	}, true, {}
}
