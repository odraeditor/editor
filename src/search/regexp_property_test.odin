// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package search

import "../editor"
import "base:runtime"
import "core:mem"
import "core:testing"

/* Verifies generated bounded regex turns agree with a contiguous reference model. */
@(test)
regexp_search_matches_generated_oracle :: proc(t: ^testing.T) {
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
	seed := u64(0xd1b54a32d192ed03)
	for fixture_index in 0 ..< 24 {
		seed = generated_search_next(seed)
		offset := 700 + fixture_index * 6_000 + int(seed % 400)
		digits := 1 + int((seed >> 8) % 4)
		contents[offset] = 'a'
		for digit_index in 0 ..< digits {
			contents[offset + 1 + digit_index] = byte('0' + rune((fixture_index + digit_index) % 10))
		}
		contents[offset + 1 + digits] = 'z'
	}
	buffer: editor.Buffer
	initialized, _ := editor.buffer_init(
		&buffer,
		411,
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
	query: Query
	query_ok, query_failure := query_init(
		&query,
		Query_Config {
			id = 411,
			kind = .Regular_Expression,
			pattern = "a[0-9]+z",
			policy = Policy{case_mode = .Sensitive, boundary_mode = .Unrestricted, whitespace_mode = .Exact, wrap = false},
			limits = DEFAULT_LIMITS,
			allocator = persistent,
			temporary_allocator = temporary,
		},
	)
	testing.expectf(t, query_ok, "generated regexp query failed with %v", query_failure)
	if query_ok {
		for case_index in 0 ..< 128 {
			seed = generated_search_next(seed)
			origin := editor.Byte_Offset(seed % u64(len(contents) + 1))
			direction := Direction.Forward
			if seed & 1 != 0 {
				direction = .Backward
			}
			expected_start, expected_end, expected := contiguous_regexp_oracle(
				contents[:],
				origin,
				direction,
			)
			actual_start, actual_end, actual, usage_ok := generated_regexp_search_run(
				t,
				&snapshot,
				&query,
				origin,
				direction,
				Search_Generation(case_index + 1),
				persistent,
				temporary,
			)
			testing.expectf(t, usage_ok, "case %d exceeded bounded accounting", case_index)
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

/* Verifies temporary and result allocation faults publish no result and leak no bytes. */
@(test)
regexp_search_allocator_faults_are_atomic :: proc(t: ^testing.T) {
	buffer, snapshot, opened := open_regexp_snapshot(t, 413, "alpha-42")
	if !opened {
		return
	}
	defer editor.buffer_snapshot_close(&snapshot)
	defer editor.buffer_close(&buffer)
	query := make_regexp_query(t, 413, "[a-z]+-[0-9]+")
	if query.state == nil {
		return
	}
	defer query_close(&query)
	request := Request {
		scope = Scope{buffer_id = 413, revision = 0, start = 0, end = 8},
		origin = 0,
		direction = .Forward,
		generation = 1,
	}

	temporary_tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&temporary_tracking, context.allocator)
	temporary_fault := Search_Fault_Allocator {
		backing = mem.tracking_allocator(&temporary_tracking),
		fail_after = 0,
	}
	temporary_result: Result
	temporary_ok, temporary_failure := regexp_search(
		&temporary_result,
		&snapshot,
		&query,
		request,
		nil,
		Allocator_Set {
			persistent = context.allocator,
			temporary = search_fault_allocator(&temporary_fault),
		},
	)
	testing.expect(t, !temporary_ok)
	testing.expect_value(t, temporary_failure.code, Failure_Code.Temporary_Memory_Limit)
	testing.expect(t, temporary_result.state == nil)
	testing.expect_value(t, temporary_tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&temporary_tracking)

	for fail_after in 0 ..< 2 {
		persistent_tracking: mem.Tracking_Allocator
		mem.tracking_allocator_init(&persistent_tracking, context.allocator)
		persistent_fault := Search_Fault_Allocator {
			backing = mem.tracking_allocator(&persistent_tracking),
			fail_after = u64(fail_after),
		}
		result: Result
		searched, failure := regexp_search(
			&result,
			&snapshot,
			&query,
			request,
			nil,
			Allocator_Set {
				persistent = search_fault_allocator(&persistent_fault),
				temporary = context.temp_allocator,
			},
		)
		testing.expect(t, !searched)
		testing.expect_value(t, failure.code, Failure_Code.Persistent_Memory_Limit)
		testing.expect(t, result.state == nil)
		testing.expect_value(t, persistent_tracking.current_memory_allocated, i64(0))
		mem.tracking_allocator_destroy(&persistent_tracking)
	}
}

@(private)
generated_regexp_search_run :: proc(
	t: ^testing.T,
	snapshot: ^editor.Buffer_Snapshot,
	query: ^Query,
	origin: editor.Byte_Offset,
	direction: Direction,
	generation: Search_Generation,
	persistent, temporary: runtime.Allocator,
) -> (editor.Byte_Offset, editor.Byte_Offset, bool, bool) {
	request := Request {
		scope = Scope{buffer_id = 411, revision = 0, start = 0, end = 150_000},
		origin = origin,
		direction = direction,
		generation = generation,
		wrap_already_attempted = true,
	}
	usage_ok := true
	for _ in 0 ..< 4 {
		result: Result
		searched, failure := regexp_search(
			&result,
			snapshot,
			query,
			request,
			nil,
			Allocator_Set{persistent = persistent, temporary = temporary},
		)
		testing.expectf(t, searched, "generated regexp turn failed with %v", failure.code)
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
	testing.expect(t, false, "generated regexp search exceeded bounded resume turns")
	return 0, 0, false, false
}

@(private)
contiguous_regexp_oracle :: proc(
	contents: []byte,
	origin: editor.Byte_Offset,
	direction: Direction,
) -> (editor.Byte_Offset, editor.Byte_Offset, bool) {
	if direction == .Forward {
		for start := int(origin); start < len(contents); start += 1 {
			end, matched := contiguous_regexp_candidate(contents, start)
			if matched {
				return editor.Byte_Offset(start), editor.Byte_Offset(end), true
			}
		}
		return 0, 0, false
	}
	last_start, last_end := editor.Byte_Offset(0), editor.Byte_Offset(0)
	found := false
	for start in 0 ..< int(origin) {
		end, matched := contiguous_regexp_candidate(contents, start)
		if matched && end <= int(origin) {
			last_start = editor.Byte_Offset(start)
			last_end = editor.Byte_Offset(end)
			found = true
		}
	}
	return last_start, last_end, found
}

@(private)
contiguous_regexp_candidate :: proc(contents: []byte, start: int) -> (end: int, matched: bool) {
	if start >= len(contents) || contents[start] != 'a' {
		return 0, false
	}
	cursor := start + 1
	first_digit := cursor
	for cursor < len(contents) && contents[cursor] >= '0' && contents[cursor] <= '9' {
		cursor += 1
	}
	if cursor == first_digit || cursor >= len(contents) || contents[cursor] != 'z' {
		return 0, false
	}
	return cursor + 1, true
}
