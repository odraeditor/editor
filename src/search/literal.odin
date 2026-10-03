// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package search

import "../editor"
import "core:mem"
import "core:strings"
import "core:unicode"
import "core:unicode/utf8"

/*
literal_search scans at most one admitted logical window of an immutable snapshot.
It returns copied occurrences or resumable progress and retains no snapshot data.
*/
literal_search :: proc(
	result: ^Result,
	snapshot: ^editor.Buffer_Snapshot,
	query: ^Query,
	request: Request,
	cancellation: ^Cancellation,
	allocators: Allocator_Set,
) -> (ok: bool, failure: Failure) {
	assert(result != nil)
	assert(result.state == nil, "result is already initialized")
	query_value, query_ok, query_failure := query_view(query)
	if !query_ok {
		return false, query_failure
	}
	if query_value.kind != .Literal {
		return false, Failure{code = .Invalid_Pattern_Kind, query_id = query_value.id}
	}
	stats, stats_ok, _ := editor.buffer_snapshot_stats(snapshot)
	if !stats_ok {
		return false, Failure{code = .Wrong_Buffer, query_id = query_value.id}
	}
	request_ok, request_failure := request_validate(query, request, stats)
	if !request_ok {
		return false, request_failure
	}
	if allocators.persistent.procedure == nil {
		return false, Failure{code = .Persistent_Memory_Limit, query_id = query_value.id}
	}
	if allocators.temporary.procedure == nil {
		return false, Failure{code = .Temporary_Memory_Limit, query_id = query_value.id}
	}
	boundaries := [3]editor.Byte_Offset {
		request.scope.start,
		request.scope.end,
		request.origin,
	}
	for boundary in boundaries {
		boundary_ok, boundary_failure := snapshot_boundary_is_valid(snapshot, stats, boundary)
		if !boundary_ok {
			boundary_failure.query_id = query_value.id
			return false, boundary_failure
		}
	}
	if cancellation_requested(cancellation, request.generation) {
		return create_terminal_result(
			result,
			.Cancelled,
			request,
			Usage{cancellation_checks = 1},
			allocators.persistent,
			query_value.limits,
		)
	}

	logical_start, logical_end, read_start, read_end := scan_bounds(query_value, request)
	read_start, read_end = literal_add_boundary_context(
		snapshot,
		stats,
		request.scope,
		read_start,
		read_end,
	)
	logical_bytes := logical_end - logical_start
	if logical_bytes == 0 {
		return create_boundary_result(result, query_value, request, allocators.persistent)
	}
	read_bytes := read_end - read_start
	if read_bytes > query_value.limits.temporary_bytes {
		return false, Failure {
			code = .Temporary_Memory_Limit,
			buffer_id = request.scope.buffer_id,
			revision = request.scope.revision,
			query_id = query_value.id,
			limit = query_value.limits.temporary_bytes,
			actual = read_bytes,
		}
	}
	scratch, scratch_error := make([]byte, int(read_bytes), allocators.temporary)
	if scratch_error != nil {
		return false, Failure {
			code = .Temporary_Memory_Limit,
			buffer_id = request.scope.buffer_id,
			revision = request.scope.revision,
			query_id = query_value.id,
			limit = query_value.limits.temporary_bytes,
			actual = read_bytes,
		}
	}
	defer delete(scratch, allocators.temporary)
	copied, read_ok, _ := editor.buffer_snapshot_read(
		snapshot,
		editor.Byte_Offset(read_start),
		scratch,
	)
	if !read_ok || copied != read_bytes {
		return false, Failure {
			code = .Out_Of_Range,
			buffer_id = request.scope.buffer_id,
			revision = request.scope.revision,
			query_id = query_value.id,
			limit = read_bytes,
			actual = copied,
		}
	}

	retained, retained_error := make(
		[]Occurrence,
		int(query_value.limits.retained_occurrences),
		allocators.temporary,
	)
	if retained_error != nil {
		return false, Failure {
			code = .Temporary_Memory_Limit,
			buffer_id = request.scope.buffer_id,
			revision = request.scope.revision,
			query_id = query_value.id,
			limit = query_value.limits.temporary_bytes,
			actual = u64(query_value.limits.retained_occurrences) * u64(size_of(Occurrence)),
		}
	}
	defer delete(retained, allocators.temporary)
	count := collect_literal_occurrences(
		retained,
		scratch,
		read_start,
		logical_start,
		logical_end,
		query_value,
		request,
	)
	usage := Usage {
		logical_bytes = logical_bytes,
		read_bytes = read_bytes,
		scan_turns = 1,
		cancellation_checks = 1,
		temporary_peak_bytes = read_bytes +
			u64(len(retained)) * u64(size_of(Occurrence)),
	}
	if cancellation_requested(cancellation, request.generation) {
		return create_terminal_result(
			result,
			.Cancelled,
			request,
			usage,
			allocators.persistent,
			query_value.limits,
		)
	}
	progress := Progress {
		next_offset = next_scan_offset(request.direction, logical_start, logical_end),
		complete = scan_reached_boundary(request.direction, request.scope, logical_start, logical_end),
	}
	if count > 0 {
		return result_init(
			result,
			Result_Config {
				outcome = .Matched,
				scope = request.scope,
				has_current = true,
				current_index = 0,
				occurrences = retained[:count],
				progress = progress,
				usage = usage,
				limits = query_value.limits,
				allocator = allocators.persistent,
			},
		)
	}
	if !progress.complete {
		return result_init(
			result,
			Result_Config {
				outcome = .Incomplete,
				scope = request.scope,
				progress = progress,
				usage = usage,
				limits = query_value.limits,
				allocator = allocators.persistent,
			},
		)
	}
	return create_boundary_result_with_usage(
		result,
		query_value,
		request,
		usage,
		allocators.persistent,
	)
}

@(private)
scan_bounds :: proc(query: Query_View, request: Request) -> (u64, u64, u64, u64) {
	scope_start := u64(request.scope.start)
	scope_end := u64(request.scope.end)
	origin := u64(request.origin)
	maximum_span := u64(len(query.pattern))
	if query.effective_case == .Insensitive {
		maximum_span = query.pattern_runes * 4
	}
	overlap := max(maximum_span, u64(1)) - 1
	if request.direction == .Forward {
		logical_start := origin
		logical_end := min(scope_end, origin + query.limits.scan_window_bytes)
		read_end := min(scope_end, logical_end + overlap)
		return logical_start, logical_end, logical_start, read_end
	}
	logical_end := origin
	logical_start := max(scope_start, origin - min(origin - scope_start, query.limits.scan_window_bytes))
	read_start := max(scope_start, logical_start - min(logical_start - scope_start, overlap))
	return logical_start, logical_end, read_start, logical_end
}

@(private)
collect_literal_occurrences :: proc(
	destination: []Occurrence,
	bytes: []byte,
	read_start, logical_start, logical_end: u64,
	query: Query_View,
	request: Request,
) -> int {
	count := 0
	if request.direction == .Forward {
		local_start := int(logical_start - read_start)
		local_end := int(logical_end - read_start)
		for local_start < local_end {
			match_end, matched := literal_match_at(bytes, local_start, query)
			if matched {
				global_end := read_start + u64(match_end)
				if global_end <= u64(request.scope.end) && count < len(destination) {
					destination[count] = Occurrence {
						buffer_id = request.scope.buffer_id,
						revision = request.scope.revision,
						start = editor.Byte_Offset(read_start + u64(local_start)),
						end = editor.Byte_Offset(global_end),
					}
					count += 1
				}
			}
			local_start = next_rune_boundary(bytes, local_start)
		}
		return count
	}
	local_start := previous_rune_boundary(bytes, int(logical_end - read_start))
	minimum_start := int(logical_start - read_start -
		min(logical_start - read_start, query.pattern_runes * 4))
	for local_start >= minimum_start {
		match_end, matched := literal_match_at(bytes, local_start, query)
		if matched {
			global_start := read_start + u64(local_start)
			global_end := read_start + u64(match_end)
			if global_end > logical_start && global_end <= logical_end &&
			   global_start >= u64(request.scope.start) && count < len(destination) {
				destination[count] = Occurrence {
					buffer_id = request.scope.buffer_id,
					revision = request.scope.revision,
					start = editor.Byte_Offset(global_start),
					end = editor.Byte_Offset(global_end),
				}
				count += 1
			}
		}
		local_start = previous_rune_boundary(bytes, local_start)
	}
	return count
}

@(private)
literal_match_at :: proc(bytes: []byte, start: int, query: Query_View) -> (end: int, matched: bool) {
	if start < 0 || start >= len(bytes) {
		return start, false
	}
	end = start
	pattern_index := 0
	for pattern_index < len(query.pattern) {
		pattern_rune, pattern_width := utf8.decode_rune_in_string(query.pattern[pattern_index:])
		if pattern_width <= 0 {
			return start, false
		}
		if query.policy.whitespace_mode == .Flexible && unicode.is_space(pattern_rune) {
			pattern_index += pattern_width
			for pattern_index < len(query.pattern) {
				next_pattern, next_width := utf8.decode_rune_in_string(query.pattern[pattern_index:])
				if next_width <= 0 || !unicode.is_space(next_pattern) {
					break
				}
				pattern_index += next_width
			}
			if end >= len(bytes) {
				return start, false
			}
			source_rune, source_width := utf8.decode_rune(bytes[end:])
			if source_width <= 0 || !unicode.is_space(source_rune) {
				return start, false
			}
			for end < len(bytes) {
				source_rune, source_width = utf8.decode_rune(bytes[end:])
				if source_width <= 0 || !unicode.is_space(source_rune) {
					break
				}
				end += source_width
			}
			continue
		}
		if end >= len(bytes) {
			return start, false
		}
		_, source_width := utf8.decode_rune(bytes[end:])
		if source_width <= 0 || end + source_width > len(bytes) {
			return start, false
		}
		pattern_part := query.pattern[pattern_index:pattern_index + pattern_width]
		source_part := string(bytes[end:end + source_width])
		equal := source_part == pattern_part
		if query.effective_case == .Insensitive {
			equal = strings.equal_fold(source_part, pattern_part)
		}
		if !equal {
			return start, false
		}
		pattern_index += pattern_width
		end += source_width
	}
	return end, match_respects_boundary(bytes, start, end, query.policy.boundary_mode)
}

@(private)
literal_add_boundary_context :: proc(
	snapshot: ^editor.Buffer_Snapshot,
	stats: editor.Buffer_Snapshot_Stats,
	scope: Scope,
	read_start, read_end: u64,
) -> (u64, u64) {
	result_start := read_start
	result_end := read_end
	if result_start > u64(scope.start) {
		candidate := editor.Byte_Offset(result_start - 1)
		for candidate > scope.start {
			valid, _ := snapshot_boundary_is_valid(snapshot, stats, candidate)
			if valid {
				break
			}
			candidate = editor.Byte_Offset(u64(candidate) - 1)
		}
		result_start = u64(candidate)
	}
	if result_end < u64(scope.end) {
		candidate := editor.Byte_Offset(result_end + 1)
		for candidate < scope.end {
			valid, _ := snapshot_boundary_is_valid(snapshot, stats, candidate)
			if valid {
				break
			}
			candidate = editor.Byte_Offset(u64(candidate) + 1)
		}
		result_end = u64(candidate)
	}
	return result_start, result_end
}

@(private)
next_rune_boundary :: proc(bytes: []byte, start: int) -> int {
	if start >= len(bytes) {
		return len(bytes)
	}
	_, rune_bytes := utf8.decode_rune(bytes[start:])
	return start + max(rune_bytes, 1)
}

@(private)
previous_rune_boundary :: proc(bytes: []byte, exclusive_end: int) -> int {
	if exclusive_end <= 0 {
		return -1
	}
	start := min(exclusive_end, len(bytes)) - 1
	for start > 0 && bytes[start] & 0xc0 == 0x80 {
		start -= 1
	}
	return start
}

@(private)
snapshot_boundary_is_valid :: proc(
	snapshot: ^editor.Buffer_Snapshot,
	stats: editor.Buffer_Snapshot_Stats,
	offset: editor.Byte_Offset,
) -> (bool, Failure) {
	value := u64(offset)
	if value > stats.text_bytes {
		return false, Failure {
			code = .Out_Of_Range,
			buffer_id = stats.buffer_id,
			revision = stats.revision,
			limit = stats.text_bytes,
			actual = value,
		}
	}
	if value == 0 || value == stats.text_bytes {
		return true, {}
	}
	byte_storage: [1]byte
	_, read_ok, _ := editor.buffer_snapshot_read(snapshot, offset, byte_storage[:])
	if !read_ok || byte_storage[0] & 0xc0 == 0x80 {
		return false, Failure {
			code = .Out_Of_Range,
			buffer_id = stats.buffer_id,
			revision = stats.revision,
			limit = stats.text_bytes,
			actual = value,
		}
	}
	return true, {}
}

@(private)
next_scan_offset :: proc(direction: Direction, logical_start, logical_end: u64) -> editor.Byte_Offset {
	if direction == .Forward {
		return editor.Byte_Offset(logical_end)
	}
	return editor.Byte_Offset(logical_start)
}

@(private)
scan_reached_boundary :: proc(
	direction: Direction,
	scope: Scope,
	logical_start, logical_end: u64,
) -> bool {
	if direction == .Forward {
		return logical_end == u64(scope.end)
	}
	return logical_start == u64(scope.start)
}

@(private)
create_boundary_result :: proc(
	result: ^Result,
	query: Query_View,
	request: Request,
	allocator: mem.Allocator,
) -> (bool, Failure) {
	return create_boundary_result_with_usage(result, query, request, {}, allocator)
}

@(private)
create_boundary_result_with_usage :: proc(
	result: ^Result,
	query: Query_View,
	request: Request,
	usage: Usage,
	allocator: mem.Allocator,
) -> (bool, Failure) {
	if query.policy.wrap && !request.wrap_already_attempted {
		wrap_offset := request.scope.start
		if request.direction == .Backward {
			wrap_offset = request.scope.end
		}
		return result_init(
			result,
			Result_Config {
				outcome = .Incomplete,
				scope = request.scope,
				progress = Progress{next_offset = wrap_offset, wrapped = true},
				usage = usage,
				limits = query.limits,
				allocator = allocator,
			},
		)
	}
	return create_terminal_result(
		result,
		.No_Match,
		request,
		usage,
		allocator,
		query.limits,
	)
}

@(private)
create_terminal_result :: proc(
	result: ^Result,
	outcome: Outcome,
	request: Request,
	usage: Usage,
	allocator: mem.Allocator,
	limits: Limits,
) -> (bool, Failure) {
	return result_init(
		result,
		Result_Config {
			outcome = outcome,
			scope = request.scope,
			progress = Progress{next_offset = request.origin, complete = true},
			usage = usage,
			limits = limits,
			allocator = allocator,
		},
	)
}
