// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package search

import "../editor"
import "base:runtime"
import "core:mem"
import "core:text/regex"
import regex_vm "core:text/regex/virtual_machine"
import "core:unicode/utf8"

@(private)
Regex_Matcher :: struct {
	query_id:    Query_ID,
	compiled:    regex.Regular_Expression,
	vm:          regex_vm.Machine,
	positions:   [MAX_CAPTURE_GROUPS][2]int,
	groups:      [MAX_CAPTURE_GROUPS]u16,
	group_count: int,
	threads:     int,
	index:       int,
	done:        bool,
	arena:       mem.Dynamic_Arena,
	allocator:   runtime.Allocator,
	ready:       bool,
}

/*
regexp_search scans at most one admitted logical window of an immutable snapshot.
It returns copied revisioned matches and captures without retaining rope storage.
*/
regexp_search :: proc(
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
	if query_value.kind != .Regular_Expression {
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
	boundaries := [3]editor.Byte_Offset{request.scope.start, request.scope.end, request.origin}
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
	window, planned, plan_failure := regex_window_plan(query, request)
	if !planned {
		return false, plan_failure
	}
	window = regex_add_boundary_context(snapshot, stats, request.scope, window)
	read_bytes := u64(window.read_end) - u64(window.read_start)
	logical_bytes := u64(window.logical_end) - u64(window.logical_start)
	occurrence_bytes := u64(query_value.limits.retained_occurrences) * u64(size_of(Occurrence))
	capture_capacity := u64(query_value.limits.retained_occurrences) * u64(query_value.limits.capture_groups)
	capture_bytes := capture_capacity * u64(size_of(Capture))
	temporary_required := read_bytes + 2 * occurrence_bytes + 2 * capture_bytes
	if temporary_required > query_value.limits.temporary_bytes {
		return false, Failure {
			code = .Temporary_Memory_Limit,
			buffer_id = request.scope.buffer_id,
			revision = request.scope.revision,
			query_id = query_value.id,
			limit = query_value.limits.temporary_bytes,
			actual = temporary_required,
		}
	}
	scratch, scratch_error := make([]byte, int(read_bytes), allocators.temporary)
	if scratch_error != nil {
		return false, Failure{code = .Temporary_Memory_Limit, query_id = query_value.id, actual = read_bytes}
	}
	defer delete(scratch, allocators.temporary)
	if read_bytes > 0 {
		copied, read_ok, _ := editor.buffer_snapshot_read(snapshot, window.read_start, scratch)
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
	}
	retained, retained_error := make(
		[]Occurrence,
		int(query_value.limits.retained_occurrences),
		allocators.temporary,
	)
	if retained_error != nil {
		return false, Failure{code = .Temporary_Memory_Limit, query_id = query_value.id, actual = occurrence_bytes}
	}
	defer delete(retained, allocators.temporary)
	retained_captures, retained_captures_error := make(
		[]Capture,
		int(capture_capacity),
		allocators.temporary,
	)
	if retained_captures_error != nil {
		return false, Failure{code = .Temporary_Memory_Limit, query_id = query_value.id, actual = capture_bytes}
	}
	defer delete(retained_captures, allocators.temporary)
	ring, ring_error := make([]Occurrence, len(retained), allocators.temporary)
	if ring_error != nil {
		return false, Failure{code = .Temporary_Memory_Limit, query_id = query_value.id, actual = occurrence_bytes}
	}
	defer delete(ring, allocators.temporary)
	ring_captures, ring_captures_error := make(
		[]Capture,
		len(retained_captures),
		allocators.temporary,
	)
	if ring_captures_error != nil {
		return false, Failure{code = .Temporary_Memory_Limit, query_id = query_value.id, actual = capture_bytes}
	}
	defer delete(ring_captures, allocators.temporary)
	matcher: Regex_Matcher
	matcher_ok, matcher_failure := regex_matcher_init(
		&matcher,
		query,
		string(scratch),
		allocators.temporary,
	)
	if !matcher_ok {
		return false, matcher_failure
	}
	defer regex_matcher_close(&matcher)
	count, capture_count, collect_failure := collect_regexp_occurrences(
		retained,
		retained_captures,
		ring,
		ring_captures,
		scratch,
		window,
		query_value,
		request,
		&matcher,
	)
	if collect_failure.code != .None {
		return false, collect_failure
	}
	usage := Usage {
		logical_bytes = logical_bytes,
		read_bytes = read_bytes,
		scan_turns = 1,
		cancellation_checks = 1,
		temporary_peak_bytes = temporary_required,
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
		next_offset = next_scan_offset(
			request.direction,
			u64(window.logical_start),
			u64(window.logical_end),
		),
		complete = scan_reached_boundary(
			request.direction,
			request.scope,
			u64(window.logical_start),
			u64(window.logical_end),
		),
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
				captures = retained_captures[:capture_count],
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
regex_matcher_init :: proc(
	matcher: ^Regex_Matcher,
	query: ^Query,
	text: string,
	allocator: runtime.Allocator,
) -> (bool, Failure) {
	view, viewed, failure := query_view(query)
	if !viewed {
		return false, failure
	}
	compiled, compiled_ok := query_compiled_regex(query)
	if !compiled_ok {
		return false, Failure{code = .Invalid_Pattern_Kind, query_id = view.id}
	}
	matcher.query_id = view.id
	matcher.allocator = allocator
	mem.dynamic_arena_init(&matcher.arena, allocator, allocator)
	matcher.compiled = compiled
	matcher.vm = regex_vm.create(compiled.program, text, allocator)
	matcher.vm.class_data = compiled.class_data
	matcher.threads = max(1, regex_vm.opcode_count(compiled.program) - 1)
	matcher.ready = true
	return true, {}
}

@(private)
regex_matcher_match :: proc(
	matcher: ^Regex_Matcher,
) -> (group_count: int, matched: bool) {
	assert(matcher != nil && matcher.ready)
	if matcher.done {
		return 0, false
	}
	mem.dynamic_arena_free_all(&matcher.arena)
	if matcher.index > 0 {
		matcher.vm.top_thread = 0
		matcher.vm.current_rune = 0
		matcher.vm.current_rune_size = 0
		for thread_index in 0 ..< matcher.threads {
			matcher.vm.threads[thread_index] = {}
			matcher.vm.next_threads[thread_index] = {}
		}
	}
	pointer_before := matcher.vm.string_pointer
	saved: ^[2 * int(MAX_CAPTURE_GROUPS)]int
	// The public iterator compacts absent optional captures. Reading the VM's
	// saved slots here preserves the group numbers required by replacement.
	{
		context.allocator = mem.dynamic_arena_allocator(&matcher.arena)
		if .Unicode in matcher.compiled.flags {
			saved, matched = regex_vm.run(&matcher.vm, true)
		} else {
			saved, matched = regex_vm.run(&matcher.vm, false)
		}
	}
	if !matched {
		return 0, false
	}
	if matcher.vm.string_pointer == pointer_before ||
	   matcher.vm.string_pointer == len(matcher.vm.memory) {
		matcher.done = true
	}
	matcher.group_count = 0
	if saved != nil {
		for saved_index := 0; saved_index < len(saved); saved_index += 2 {
			start, end := saved[saved_index], saved[saved_index + 1]
			if start == -1 || end == -1 {
				continue
			}
			matcher.positions[matcher.group_count] = {start, end}
			matcher.groups[matcher.group_count] = u16(saved_index / 2)
			matcher.group_count += 1
		}
	}
	matcher.index += 1
	return matcher.group_count, true
}

@(private)
regex_matcher_advance_empty :: proc(matcher: ^Regex_Matcher, bytes: []byte, offset: int) -> bool {
	assert(matcher != nil && matcher.ready)
	if offset >= len(bytes) {
		return false
	}
	next := next_rune_boundary(bytes, offset)
	last_rune, _ := utf8.decode_last_rune(bytes[:next])
	matcher.vm.string_pointer = next
	matcher.vm.last_rune = last_rune
	matcher.done = false
	return true
}

@(private)
regex_matcher_close :: proc(matcher: ^Regex_Matcher) {
	if matcher == nil || !matcher.ready {
		return
	}
	regex_vm.destroy(matcher.vm, matcher.allocator)
	mem.dynamic_arena_destroy(&matcher.arena)
	matcher^ = {}
}

@(private)
collect_regexp_occurrences :: proc(
	destination: []Occurrence,
	destination_captures: []Capture,
	ring: []Occurrence,
	ring_captures: []Capture,
	bytes: []byte,
	window: Regex_Window,
	query: Query_View,
	request: Request,
	matcher: ^Regex_Matcher,
) -> (count: int, capture_count: int, failure: Failure) {
	read_start := u64(window.read_start)
	logical_start := u64(window.logical_start)
	logical_end := u64(window.logical_end)
	seen := 0
	for {
		group_count, matched := regex_matcher_match(matcher)
		if !matched || group_count == 0 {
			break
		}
		whole := matcher.positions[0]
		local_start := whole[0]
		local_end := whole[1]
		if local_start < 0 || local_end < local_start || local_end > len(bytes) {
			return 0, 0, Failure{code = .Out_Of_Range, query_id = query.id}
		}
		global_start := read_start + u64(local_start)
		global_end := read_start + u64(local_end)
		span := global_end - global_start
		if span > query.limits.match_span_bytes {
			return 0, 0, Failure {
				code = .Match_Span_Limit,
				buffer_id = request.scope.buffer_id,
				revision = request.scope.revision,
				query_id = query.id,
				limit = query.limits.match_span_bytes,
				actual = span,
			}
		}
		admitted := global_start >= u64(request.scope.start) &&
			global_end <= u64(request.scope.end) &&
			match_respects_boundary(bytes, local_start, local_end, query.policy.boundary_mode)
		if request.direction == .Forward {
			admitted = admitted && global_start >= logical_start && global_start < logical_end
		} else if global_start == global_end {
			admitted = admitted && global_start >= logical_start && global_start < logical_end
		} else {
			admitted = admitted && global_end > logical_start && global_end <= logical_end
		}
		if admitted {
			if request.direction == .Forward {
				if count >= len(destination) {
					break
				}
				capture_count = copy_regexp_occurrence(
					destination,
					destination_captures,
					count,
					capture_count,
					matcher.positions[:group_count],
					matcher.groups[:group_count],
					0,
					read_start,
					request,
				)
				count += 1
			} else {
				slot := seen % len(ring)
				ring_capture_start := slot * int(query.limits.capture_groups)
				_ = copy_regexp_occurrence(
					ring,
					ring_captures,
					slot,
					ring_capture_start,
					matcher.positions[:group_count],
					matcher.groups[:group_count],
					0,
					read_start,
					request,
				)
				seen += 1
			}
		}
		if local_start == local_end {
			if !regex_matcher_advance_empty(matcher, bytes, local_end) {
				break
			}
		}
	}
	if request.direction == .Forward {
		return count, capture_count, {}
	}
	count = min(seen, len(destination))
	for destination_index in 0 ..< count {
		slot := (seen - 1 - destination_index) % len(ring)
		source := ring[slot]
		source_capture_start := int(source.first_capture)
		source_capture_end := source_capture_start + int(source.capture_count)
		destination[destination_index] = source
		destination[destination_index].first_capture = u32(capture_count)
		copy(
			destination_captures[capture_count:],
			ring_captures[source_capture_start:source_capture_end],
		)
		capture_count += int(source.capture_count)
	}
	return count, capture_count, {}
}

@(private)
copy_regexp_occurrence :: proc(
	occurrences: []Occurrence,
	captures: []Capture,
	occurrence_index: int,
	capture_start: int,
	positions: [][2]int,
	groups: []u16,
	match_cursor: int,
	read_start: u64,
	request: Request,
) -> int {
	for position, index in positions {
		captures[capture_start + index] = Capture {
			group = groups[index],
			start = editor.Byte_Offset(read_start + u64(match_cursor + position[0])),
			end = editor.Byte_Offset(read_start + u64(match_cursor + position[1])),
		}
	}
	whole := captures[capture_start]
	occurrences[occurrence_index] = Occurrence {
		buffer_id = request.scope.buffer_id,
		revision = request.scope.revision,
		start = whole.start,
		end = whole.end,
		first_capture = u32(capture_start),
		capture_count = u16(len(positions)),
	}
	return capture_start + len(positions)
}

@(private)
regex_add_boundary_context :: proc(
	snapshot: ^editor.Buffer_Snapshot,
	stats: editor.Buffer_Snapshot_Stats,
	scope: Scope,
	window: Regex_Window,
) -> Regex_Window {
	result := window
	if result.read_start > scope.start {
		candidate := editor.Byte_Offset(u64(result.read_start) - 1)
		for candidate > scope.start {
			valid, _ := snapshot_boundary_is_valid(snapshot, stats, candidate)
			if valid {
				break
			}
			candidate = editor.Byte_Offset(u64(candidate) - 1)
		}
		result.read_start = candidate
	}
	if result.read_end < scope.end {
		candidate := editor.Byte_Offset(u64(result.read_end) + 1)
		for candidate < scope.end {
			valid, _ := snapshot_boundary_is_valid(snapshot, stats, candidate)
			if valid {
				break
			}
			candidate = editor.Byte_Offset(u64(candidate) + 1)
		}
		result.read_end = candidate
	}
	return result
}
