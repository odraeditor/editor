// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package search

import "../editor"
import "core:mem"
import "core:testing"

/* Verifies forward and backward regex matches cross rope leaves with captures. */
@(test)
navigates_cross_leaf_multiline_matches :: proc(t: ^testing.T) {
	contents: [140_000]byte
	for index in 0 ..< len(contents) {
		contents[index] = 'x'
	}
	text := "needle-rzeka\nOdra"
	first := 4_096 - 7
	last := 90_000
	copy(contents[first:], text)
	copy(contents[last:], text)
	buffer, snapshot, opened := open_regexp_snapshot(t, 401, string(contents[:]))
	if !opened {
		return
	}
	defer editor.buffer_snapshot_close(&snapshot)
	defer editor.buffer_close(&buffer)
	query := make_regexp_query(t, 401, "(needle)-([a-z]+)\n(Odra)")
	if query.state == nil {
		return
	}
	defer query_close(&query)
	scope := Scope{buffer_id = 401, revision = 0, start = 0, end = editor.Byte_Offset(len(contents))}
	forward := run_regexp_turn(
		t,
		&snapshot,
		&query,
		Request{scope = scope, origin = 0, direction = .Forward, generation = 1},
	)
	testing.expect_value(t, forward.outcome, Outcome.Matched)
	testing.expect_value(t, forward.current.start, editor.Byte_Offset(first))
	testing.expect_value(t, forward.capture_count, 4)
	testing.expect_value(t, forward.captures[1].start, editor.Byte_Offset(first))
	testing.expect_value(t, forward.captures[1].end, editor.Byte_Offset(first + 6))
	backward_origin := scope.end
	backward: Regexp_Test_Turn
	for _ in 0 ..< 4 {
		backward = run_regexp_turn(
			t,
			&snapshot,
			&query,
			Request{scope = scope, origin = backward_origin, direction = .Backward, generation = 2},
		)
		if backward.outcome == .Matched {
			break
		}
		backward_origin = backward.progress.next_offset
	}
	testing.expect_value(t, backward.outcome, Outcome.Matched)
	testing.expect_value(t, backward.current.start, editor.Byte_Offset(last))
}

/* Verifies rope-window context prevents artificial anchor matches. */
@(test)
preserves_anchor_context_at_window_edges :: proc(t: ^testing.T) {
	contents: [150_000]byte
	for index in 0 ..< len(contents) {
		contents[index] = 'x'
	}
	buffer, snapshot, opened := open_regexp_snapshot(t, 403, string(contents[:]))
	if !opened {
		return
	}
	defer editor.buffer_snapshot_close(&snapshot)
	defer editor.buffer_close(&buffer)
	query := make_regexp_query(t, 403, "^x")
	if query.state == nil {
		return
	}
	defer query_close(&query)
	scope := Scope{buffer_id = 403, revision = 0, start = 0, end = editor.Byte_Offset(len(contents))}
	turn := run_regexp_turn(
		t,
		&snapshot,
		&query,
		Request {
			scope = scope,
			origin = editor.Byte_Offset(DEFAULT_SCAN_WINDOW_BYTES),
			direction = .Forward,
			generation = 1,
		},
	)
	testing.expect_value(t, turn.outcome, Outcome.Incomplete)
	testing.expect(t, !turn.has_current)
}

/* Verifies zero-width matches advance by Unicode boundaries within one turn. */
@(test)
advances_zero_width_matches_unicode_safely :: proc(t: ^testing.T) {
	buffer, snapshot, opened := open_regexp_snapshot(t, 405, "a\u03b2c")
	if !opened {
		return
	}
	defer editor.buffer_snapshot_close(&snapshot)
	defer editor.buffer_close(&buffer)
	query := make_regexp_query(t, 405, "a*?")
	if query.state == nil {
		return
	}
	defer query_close(&query)
	scope := Scope{buffer_id = 405, revision = 0, start = 0, end = 4}
	result: Result
	searched, failure := regexp_search(
		&result,
		&snapshot,
		&query,
		Request{scope = scope, origin = 0, direction = .Forward, generation = 1},
		nil,
		Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	testing.expectf(t, searched, "zero-width search failed with %v", failure)
	if !searched {
		return
	}
	defer result_close(&result)
	view, viewed, _ := result_view(&result)
	testing.expect(t, viewed)
	testing.expect(t, len(view.occurrences) >= 3)
	if len(view.occurrences) >= 3 {
		testing.expect_value(t, view.occurrences[0].start, editor.Byte_Offset(0))
		testing.expect_value(t, view.occurrences[1].start, editor.Byte_Offset(1))
		testing.expect_value(t, view.occurrences[2].start, editor.Byte_Offset(3))
	}
}

/* Verifies absent optional captures do not renumber later participating groups. */
@(test)
preserves_optional_capture_group_identity :: proc(t: ^testing.T) {
	buffer, snapshot, opened := open_regexp_snapshot(t, 406, "b")
	if !opened {
		return
	}
	defer editor.buffer_snapshot_close(&snapshot)
	defer editor.buffer_close(&buffer)
	query := make_regexp_query(t, 406, "(a)?(b)")
	if query.state == nil {
		return
	}
	defer query_close(&query)
	turn := run_regexp_turn(
		t,
		&snapshot,
		&query,
		Request {
			scope = Scope{buffer_id = 406, revision = 0, start = 0, end = 1},
			origin = 0,
			direction = .Forward,
			generation = 1,
		},
	)
	testing.expect_value(t, turn.outcome, Outcome.Matched)
	testing.expect_value(t, turn.capture_count, 2)
	if turn.capture_count == 2 {
		testing.expect_value(t, turn.captures[0].group, u16(0))
		testing.expect_value(t, turn.captures[1].group, u16(2))
		testing.expect_value(t, turn.captures[1].start, editor.Byte_Offset(0))
		testing.expect_value(t, turn.captures[1].end, editor.Byte_Offset(1))
	}
}

/* Verifies observed oversized matches fail before publishing a result. */
@(test)
rejects_matches_beyond_the_admitted_span :: proc(t: ^testing.T) {
	contents := make([]byte, int(MIN_MATCH_SPAN_BYTES + 64))
	defer delete(contents)
	for index in 0 ..< len(contents) {
		contents[index] = 'a'
	}
	buffer, snapshot, opened := open_regexp_snapshot(t, 407, string(contents))
	if !opened {
		return
	}
	defer editor.buffer_snapshot_close(&snapshot)
	defer editor.buffer_close(&buffer)
	limits := DEFAULT_LIMITS
	limits.match_span_bytes = MIN_MATCH_SPAN_BYTES
	query: Query
	initialized, init_failure := query_init(
		&query,
		Query_Config {
			id = 407,
			kind = .Regular_Expression,
			pattern = "a+",
			policy = DEFAULT_POLICY,
			limits = limits,
			allocator = context.allocator,
			temporary_allocator = context.temp_allocator,
		},
	)
	testing.expectf(t, initialized, "span query failed with %v", init_failure)
	if !initialized {
		return
	}
	defer query_close(&query)
	result: Result
	searched, failure := regexp_search(
		&result,
		&snapshot,
		&query,
		Request {
			scope = Scope{buffer_id = 407, revision = 0, start = 0, end = editor.Byte_Offset(len(contents))},
			origin = 0,
			direction = .Forward,
			generation = 1,
		},
		nil,
		Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, !searched)
	testing.expect_value(t, failure.code, Failure_Code.Match_Span_Limit)
	testing.expect(t, result.state == nil)
}

/* Verifies regex turns expose wrapping and reject stale source revisions. */
@(test)
reports_wrap_and_stale_revision_explicitly :: proc(t: ^testing.T) {
	buffer, snapshot, opened := open_regexp_snapshot(t, 408, "abc")
	if !opened {
		return
	}
	defer editor.buffer_snapshot_close(&snapshot)
	defer editor.buffer_close(&buffer)
	query := make_regexp_query(t, 408, "z+")
	if query.state == nil {
		return
	}
	defer query_close(&query)
	scope := Scope{buffer_id = 408, revision = 0, start = 0, end = 3}
	wrapped := run_regexp_turn(
		t,
		&snapshot,
		&query,
		Request{scope = scope, origin = scope.end, direction = .Forward, generation = 1},
	)
	testing.expect_value(t, wrapped.outcome, Outcome.Incomplete)
	testing.expect(t, wrapped.progress.wrapped)
	testing.expect_value(t, wrapped.progress.next_offset, scope.start)
	result: Result
	stale_scope := scope
	stale_scope.revision = 9
	searched, failure := regexp_search(
		&result,
		&snapshot,
		&query,
		Request{scope = stale_scope, origin = 0, direction = .Forward, generation = 2},
		nil,
		Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, !searched)
	testing.expect_value(t, failure.code, Failure_Code.Stale_Revision)
	testing.expect(t, result.state == nil)
}

/* Verifies cancellation, copied results, and every allocation domain clean up. */
@(test)
honors_cancellation_and_releases_owned_storage :: proc(t: ^testing.T) {
	persistent_tracking: mem.Tracking_Allocator
	temporary_tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&persistent_tracking, context.allocator)
	mem.tracking_allocator_init(&temporary_tracking, context.allocator)
	persistent := mem.tracking_allocator(&persistent_tracking)
	temporary := mem.tracking_allocator(&temporary_tracking)
	buffer: editor.Buffer
	initialized, _ := editor.buffer_init(
		&buffer,
		409,
		"one two one",
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
	query: Query
	query_ok, _ := query_init(
		&query,
		Query_Config {
			id = 409,
			kind = .Regular_Expression,
			pattern = "(one)",
			policy = DEFAULT_POLICY,
			limits = DEFAULT_LIMITS,
			allocator = persistent,
			temporary_allocator = temporary,
		},
	)
	if !opened || !query_ok {
		if opened {
			editor.buffer_snapshot_close(&snapshot)
		}
		editor.buffer_close(&buffer)
		mem.tracking_allocator_destroy(&temporary_tracking)
		mem.tracking_allocator_destroy(&persistent_tracking)
		return
	}
	cancellation: Cancellation
	_, _ = cancellation_reset(&cancellation, 9)
	testing.expect(t, cancellation_request(&cancellation, 9))
	result: Result
	searched, failure := regexp_search(
		&result,
		&snapshot,
		&query,
		Request {
			scope = Scope{buffer_id = 409, revision = 0, start = 0, end = 11},
			origin = 0,
			direction = .Forward,
			generation = 9,
		},
		&cancellation,
		Allocator_Set{persistent = persistent, temporary = temporary},
	)
	testing.expectf(t, searched, "cancelled regex search failed with %v", failure)
	if searched {
		view, viewed, _ := result_view(&result)
		testing.expect(t, viewed)
		testing.expect_value(t, view.outcome, Outcome.Cancelled)
		result_close(&result)
	}
	query_close(&query)
	editor.buffer_snapshot_close(&snapshot)
	editor.buffer_close(&buffer)
	testing.expect_value(t, temporary_tracking.current_memory_allocated, i64(0))
	testing.expect_value(t, persistent_tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&temporary_tracking)
	mem.tracking_allocator_destroy(&persistent_tracking)
}

@(private)
Regexp_Test_Turn :: struct {
	outcome:       Outcome,
	has_current:   bool,
	current:       Occurrence,
	progress:      Progress,
	capture_count: int,
	captures:      [MAX_CAPTURE_GROUPS]Capture,
}

@(private)
run_regexp_turn :: proc(
	t: ^testing.T,
	snapshot: ^editor.Buffer_Snapshot,
	query: ^Query,
	request: Request,
) -> Regexp_Test_Turn {
	result: Result
	searched, failure := regexp_search(
		&result,
		snapshot,
		query,
		request,
		nil,
		Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	testing.expectf(t, searched, "regex search failed with %v", failure)
	if !searched {
		return {}
	}
	view, viewed, view_failure := result_view(&result)
	testing.expectf(t, viewed, "regex result failed with %v", view_failure)
	turn := Regexp_Test_Turn {
		outcome = view.outcome,
		has_current = view.has_current,
		progress = view.progress,
		capture_count = min(len(view.captures), int(MAX_CAPTURE_GROUPS)),
	}
	if len(view.occurrences) > 0 {
		turn.current = view.occurrences[0]
	}
	copy(turn.captures[:], view.captures[:turn.capture_count])
	result_close(&result)
	return turn
}

@(private)
open_regexp_snapshot :: proc(
	t: ^testing.T,
	buffer_id: editor.Buffer_ID,
	contents: string,
) -> (buffer: editor.Buffer, snapshot: editor.Buffer_Snapshot, ok: bool) {
	initialized, init_failure := editor.buffer_init(
		&buffer,
		buffer_id,
		contents,
		editor.Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	testing.expectf(t, initialized, "buffer failed with %v", init_failure)
	if !initialized {
		return {}, {}, false
	}
	opened, open_failure := editor.buffer_snapshot_open(&buffer, &snapshot)
	testing.expectf(t, opened, "snapshot failed with %v", open_failure)
	if !opened {
		editor.buffer_close(&buffer)
		return {}, {}, false
	}
	return buffer, snapshot, true
}
