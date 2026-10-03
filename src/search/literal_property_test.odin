// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package search

import "../editor"
import "base:runtime"
import "core:mem"
import "core:testing"
import "core:unicode/utf8"

/* Verifies generated bounded turns agree with a contiguous literal oracle. */
@(test)
literal_search_matches_generated_oracle :: proc(t: ^testing.T) {
	persistent_tracking: mem.Tracking_Allocator
	temporary_tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&persistent_tracking, context.allocator)
	mem.tracking_allocator_init(&temporary_tracking, context.allocator)
	persistent := mem.tracking_allocator(&persistent_tracking)
	temporary := mem.tracking_allocator(&temporary_tracking)
	contents: [150_000]byte
	for index in 0 ..< len(contents) {
		contents[index] = 'x'
	}
	placements := [?]struct { offset: int, text: string } {
		{100, "alpha"},
		{4_093, "alpha"},
		{8_187, "\u017c\u00f3\u0142\u0107"},
		{65_533, "alpha"},
		{72_001, "e\u0301"},
		{110_003, "\U0001f642"},
		{149_000, "alpha"},
	}
	for fixture in placements {
		copy(contents[fixture.offset:], fixture.text)
	}
	testing.expect(t, utf8.valid_string(string(contents[:])))

	buffer: editor.Buffer
	initialized, _ := editor.buffer_init(
		&buffer,
		401,
		string(contents[:]),
		editor.Allocator_Set{persistent = persistent, temporary = temporary},
	)
	testing.expect(t, initialized)
	if !initialized {
		mem.tracking_allocator_destroy(&temporary_tracking)
		mem.tracking_allocator_destroy(&persistent_tracking)
		return
	}
	snapshot: editor.Buffer_Snapshot
	opened, _ := editor.buffer_snapshot_open(&buffer, &snapshot)
	testing.expect(t, opened)
	if !opened {
		editor.buffer_close(&buffer)
		mem.tracking_allocator_destroy(&temporary_tracking)
		mem.tracking_allocator_destroy(&persistent_tracking)
		return
	}
	patterns := [?]string{"alpha", "\u017c\u00f3\u0142\u0107", "e\u0301", "\U0001f642", "missing"}
	seed := u64(0x9e3779b97f4a7c15)
	for case_index in 0 ..< 256 {
		seed = generated_search_next(seed)
		pattern := patterns[int(seed % u64(len(patterns)))]
		origin := generated_search_boundary(contents[:], seed)
		direction := Direction.Forward
		if seed & 1 != 0 {
			direction = .Backward
		}
		query: Query
		query_ok, query_failure := query_init(
			&query,
			Query_Config {
				id = Query_ID(case_index + 1),
				kind = .Literal,
				pattern = pattern,
				policy = Policy{case_mode = .Sensitive, boundary_mode = .Unrestricted, whitespace_mode = .Exact, wrap = false},
				limits = DEFAULT_LIMITS,
				allocator = persistent,
			},
		)
		testing.expectf(t, query_ok, "case %d query failed with %v", case_index, query_failure.code)
		if !query_ok {
			continue
		}
		expected_start, expected_end, expected := contiguous_literal_oracle(
			contents[:],
			pattern,
			origin,
			direction,
		)
		actual_start, actual_end, actual, usage_ok := generated_search_run(
			t,
			&snapshot,
			&query,
			origin,
			direction,
			Search_Generation(case_index + 1),
			persistent,
			temporary,
		)
		testing.expectf(t, usage_ok, "case %d exceeded one-turn accounting", case_index)
		testing.expectf(t, actual == expected, "case %d presence mismatch", case_index)
		if expected && actual {
			testing.expectf(
				t,
				actual_start == expected_start && actual_end == expected_end,
				"case %d got %d..%d instead of %d..%d",
				case_index,
				actual_start,
				actual_end,
				expected_start,
				expected_end,
			)
		}
		query_close(&query)
	}
	editor.buffer_snapshot_close(&snapshot)
	editor.buffer_close(&buffer)
	testing.expect_value(t, temporary_tracking.current_memory_allocated, i64(0))
	testing.expect_value(t, persistent_tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&temporary_tracking)
	mem.tracking_allocator_destroy(&persistent_tracking)
}

/* Verifies query and result allocator faults publish no owner and leak no bytes. */
@(test)
literal_search_allocator_faults_are_atomic :: proc(t: ^testing.T) {
	for fail_after in 0 ..< 2 {
		tracking: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracking, context.allocator)
		fault := Search_Fault_Allocator {
			backing = mem.tracking_allocator(&tracking),
			fail_after = u64(fail_after),
		}
		query: Query
		initialized, failure := query_init(
			&query,
			Query_Config {
				id = 1,
				kind = .Literal,
				pattern = "alpha",
				policy = DEFAULT_POLICY,
				limits = DEFAULT_LIMITS,
				allocator = search_fault_allocator(&fault),
			},
		)
		testing.expect(t, !initialized)
		testing.expect_value(t, failure.code, Failure_Code.Persistent_Memory_Limit)
		testing.expect(t, query.state == nil)
		testing.expect_value(t, tracking.current_memory_allocated, i64(0))
		mem.tracking_allocator_destroy(&tracking)
	}

	buffer: editor.Buffer
	buffer_ok, _ := editor.buffer_init(
		&buffer,
		403,
		"alpha",
		editor.Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, buffer_ok)
	if !buffer_ok {
		return
	}
	defer editor.buffer_close(&buffer)
	snapshot: editor.Buffer_Snapshot
	opened, _ := editor.buffer_snapshot_open(&buffer, &snapshot)
	testing.expect(t, opened)
	if !opened {
		return
	}
	defer editor.buffer_snapshot_close(&snapshot)
	query := make_literal_query(t, 11, "alpha")
	if query.state == nil {
		return
	}
	defer query_close(&query)
	for fail_after in 0 ..< 2 {
		tracking: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracking, context.allocator)
		fault := Search_Fault_Allocator {
			backing = mem.tracking_allocator(&tracking),
			fail_after = u64(fail_after),
		}
		result: Result
		searched, failure := literal_search(
			&result,
			&snapshot,
			&query,
			Request {
				scope = Scope{buffer_id = 403, revision = 0, start = 0, end = 5},
				origin = 0,
				direction = .Forward,
				generation = 1,
			},
			nil,
			Allocator_Set {
				persistent = search_fault_allocator(&fault),
				temporary = context.temp_allocator,
			},
		)
		testing.expect(t, !searched)
		testing.expect_value(t, failure.code, Failure_Code.Persistent_Memory_Limit)
		testing.expect(t, result.state == nil)
		testing.expect_value(t, tracking.current_memory_allocated, i64(0))
		mem.tracking_allocator_destroy(&tracking)
	}
}

@(private)
generated_search_run :: proc(
	t: ^testing.T,
	snapshot: ^editor.Buffer_Snapshot,
	query: ^Query,
	origin: editor.Byte_Offset,
	direction: Direction,
	generation: Search_Generation,
	persistent, temporary: runtime.Allocator,
) -> (editor.Byte_Offset, editor.Byte_Offset, bool, bool) {
	request := Request {
		scope = Scope{buffer_id = 401, revision = 0, start = 0, end = 150_000},
		origin = origin,
		direction = direction,
		generation = generation,
		wrap_already_attempted = true,
	}
	usage_ok := true
	for _ in 0 ..< 4 {
		result: Result
		searched, failure := literal_search(
			&result,
			snapshot,
			query,
			request,
			nil,
			Allocator_Set{persistent = persistent, temporary = temporary},
		)
		testing.expectf(t, searched, "generated turn failed with %v", failure.code)
		if !searched {
			return 0, 0, false, false
		}
		view, viewed, _ := result_view(&result)
		testing.expect(t, viewed)
		usage_ok = usage_ok && view.usage.logical_bytes <= DEFAULT_SCAN_WINDOW_BYTES &&
		           view.usage.temporary_peak_bytes <= DEFAULT_LIMITS.temporary_bytes
		if view.outcome == .Matched {
			current := view.occurrences[view.current_index]
			start, end := current.start, current.end
			result_close(&result)
			return start, end, true, usage_ok
		}
		if view.outcome == .No_Match {
			result_close(&result)
			return 0, 0, false, usage_ok
		}
		request.origin = view.progress.next_offset
		result_close(&result)
	}
	testing.expect(t, false, "generated search exceeded bounded resume turns")
	return 0, 0, false, false
}

@(private)
contiguous_literal_oracle :: proc(
	contents: []byte,
	pattern: string,
	origin: editor.Byte_Offset,
	direction: Direction,
) -> (editor.Byte_Offset, editor.Byte_Offset, bool) {
	if direction == .Forward {
		offset := int(origin)
		for offset + len(pattern) <= len(contents) {
			if string(contents[offset:offset + len(pattern)]) == pattern {
				return editor.Byte_Offset(offset), editor.Byte_Offset(offset + len(pattern)), true
			}
			_, rune_bytes := utf8.decode_rune(contents[offset:])
			offset += max(rune_bytes, 1)
		}
		return 0, 0, false
	}
	last_start, last_end := editor.Byte_Offset(0), editor.Byte_Offset(0)
	found := false
	offset := 0
	for offset < int(origin) {
		end := offset + len(pattern)
		if end <= int(origin) && end <= len(contents) &&
		   string(contents[offset:end]) == pattern {
			last_start = editor.Byte_Offset(offset)
			last_end = editor.Byte_Offset(end)
			found = true
		}
		_, rune_bytes := utf8.decode_rune(contents[offset:])
		offset += max(rune_bytes, 1)
	}
	return last_start, last_end, found
}

@(private)
generated_search_boundary :: proc(contents: []byte, seed: u64) -> editor.Byte_Offset {
	offset := int(seed % (u64(len(contents)) + 1))
	for offset < len(contents) && !utf8.rune_start(contents[offset]) {
		offset += 1
	}
	return editor.Byte_Offset(offset)
}

@(private)
generated_search_next :: proc(state: u64) -> u64 {
	value := state
	value ~= value << 13
	value ~= value >> 7
	value ~= value << 17
	return value
}

@(private)
Search_Fault_Allocator :: struct {
	backing:                runtime.Allocator,
	fail_after:             u64,
	successful_allocations: u64,
}

@(private)
search_fault_allocator :: proc(state: ^Search_Fault_Allocator) -> runtime.Allocator {
	return runtime.Allocator{procedure = search_fault_allocator_proc, data = state}
}

@(private)
search_fault_allocator_proc :: proc(
	allocator_data: rawptr,
	mode: runtime.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	location := #caller_location,
) -> (result: []byte, error: runtime.Allocator_Error) {
	state := (^Search_Fault_Allocator)(allocator_data)
	if mode == .Alloc || mode == .Alloc_Non_Zeroed || mode == .Resize ||
	   mode == .Resize_Non_Zeroed {
		if state.successful_allocations >= state.fail_after {
			return nil, .Out_Of_Memory
		}
		state.successful_allocations += 1
	}
	return state.backing.procedure(
		state.backing.data,
		mode,
		size,
		alignment,
		old_memory,
		old_size,
		location,
	)
}
