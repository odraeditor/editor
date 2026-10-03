// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package search

import "../editor"
import "core:mem"
import "core:testing"

/* Verifies forward and backward literal matches cross rope leaves and scan windows. */
@(test)
navigates_cross_leaf_matches_in_both_directions :: proc(t: ^testing.T) {
	contents: [140_000]byte
	for index in 0 ..< len(contents) {
		contents[index] = 'x'
	}
	pattern := "needle-\u017c\u00f3\u0142\u0107"
	first := 4_096 - len(pattern) / 2
	last := 65_536 - len(pattern) / 2
	copy(contents[first:], pattern)
	copy(contents[last:], pattern)
	buffer: editor.Buffer
	initialized, _ := editor.buffer_init(
		&buffer,
		211,
		string(contents[:]),
		editor.Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, initialized)
	if !initialized {
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
	query := make_literal_query(t, 1, pattern)
	if query.state == nil {
		return
	}
	defer query_close(&query)
	scope := Scope{buffer_id = 211, revision = 0, start = 0, end = editor.Byte_Offset(len(contents))}
	forward := run_literal_turn(t, &snapshot, &query, Request{scope = scope, origin = 0, direction = .Forward, generation = 1})
	testing.expect_value(t, forward.outcome, Outcome.Matched)
	testing.expect_value(t, forward.current.start, editor.Byte_Offset(first))
	backward_pending := run_literal_turn(t, &snapshot, &query, Request{scope = scope, origin = scope.end, direction = .Backward, generation = 2})
	testing.expect_value(t, backward_pending.outcome, Outcome.Incomplete)
	backward := run_literal_turn(t, &snapshot, &query, Request{scope = scope, origin = backward_pending.progress.next_offset, direction = .Backward, generation = 2})
	testing.expect_value(t, backward.outcome, Outcome.Matched)
	testing.expect_value(t, backward.current.start, editor.Byte_Offset(last))
}

/* Verifies smart case uses Unicode folding and uppercase input forces sensitivity. */
@(test)
literal_search_applies_unicode_smart_case :: proc(t: ^testing.T) {
	buffer: editor.Buffer
	initialized, _ := editor.buffer_init(
		&buffer,
		213,
		"A \u017b\u00d3\u0141\u0106 B",
		editor.Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, initialized)
	if !initialized {
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
	stats, _, _ := editor.buffer_snapshot_stats(&snapshot)
	scope := Scope{buffer_id = 213, revision = 0, start = 0, end = editor.Byte_Offset(stats.text_bytes)}
	lower := make_literal_query(t, 3, "\u017c\u00f3\u0142\u0107")
	if lower.state == nil {
		return
	}
	defer query_close(&lower)
	lower_result := run_literal_turn(t, &snapshot, &lower, Request{scope = scope, origin = 0, direction = .Forward, generation = 1})
	testing.expect_value(t, lower_result.outcome, Outcome.Matched)
	uppercase := make_literal_query(t, 4, "\u017b\u00f3\u0142\u0107")
	if uppercase.state == nil {
		return
	}
	defer query_close(&uppercase)
	uppercase_result := run_literal_turn(t, &snapshot, &uppercase, Request{scope = scope, origin = 0, direction = .Forward, generation = 2, wrap_already_attempted = true})
	testing.expect_value(t, uppercase_result.outcome, Outcome.No_Match)
}

/* Verifies long misses resume by measured windows and expose explicit wrap state. */
@(test)
literal_search_reports_bounded_progress_and_wrap :: proc(t: ^testing.T) {
	contents: [140_000]byte
	for index in 0 ..< len(contents) {
		contents[index] = 'x'
	}
	buffer: editor.Buffer
	initialized, _ := editor.buffer_init(
		&buffer,
		215,
		string(contents[:]),
		editor.Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, initialized)
	if !initialized {
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
	query := make_literal_query(t, 5, "absent")
	if query.state == nil {
		return
	}
	defer query_close(&query)
	scope := Scope{buffer_id = 215, revision = 0, start = 0, end = editor.Byte_Offset(len(contents))}
	first := run_literal_turn(t, &snapshot, &query, Request{scope = scope, origin = 0, direction = .Forward, generation = 1})
	testing.expect_value(t, first.outcome, Outcome.Incomplete)
	testing.expect_value(t, first.progress.next_offset, editor.Byte_Offset(DEFAULT_SCAN_WINDOW_BYTES))
	testing.expect(t, !first.progress.wrapped)
	last := run_literal_turn(t, &snapshot, &query, Request{scope = scope, origin = editor.Byte_Offset(131_072), direction = .Forward, generation = 2})
	testing.expect_value(t, last.outcome, Outcome.Incomplete)
	testing.expect(t, last.progress.wrapped)
	testing.expect_value(t, last.progress.next_offset, scope.start)
	completed := run_literal_turn(t, &snapshot, &query, Request{scope = scope, origin = editor.Byte_Offset(131_072), direction = .Forward, generation = 3, wrap_already_attempted = true})
	testing.expect_value(t, completed.outcome, Outcome.No_Match)
}

/* Verifies scope boundaries, generation cancellation, accounting, and teardown. */
@(test)
honors_scope_cancellation_and_exact_accounting :: proc(t: ^testing.T) {
	persistent_tracking: mem.Tracking_Allocator
	temporary_tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&persistent_tracking, context.allocator)
	mem.tracking_allocator_init(&temporary_tracking, context.allocator)
	persistent := mem.tracking_allocator(&persistent_tracking)
	temporary := mem.tracking_allocator(&temporary_tracking)
	buffer: editor.Buffer
	initialized, _ := editor.buffer_init(
		&buffer,
		217,
		"outside inside outside",
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
	query := make_literal_query_with_allocator(t, 6, "outside", persistent)
	if !opened || query.state == nil {
		if opened {
			editor.buffer_snapshot_close(&snapshot)
		}
		editor.buffer_close(&buffer)
		mem.tracking_allocator_destroy(&temporary_tracking)
		mem.tracking_allocator_destroy(&persistent_tracking)
		return
	}
	scope := Scope{buffer_id = 217, revision = 0, start = 8, end = 14}
	scoped_result: Result
	scoped, scoped_failure := literal_search(
		&scoped_result,
		&snapshot,
		&query,
		Request{scope = scope, origin = scope.start, direction = .Forward, generation = 8, wrap_already_attempted = true},
		nil,
		Allocator_Set{persistent = persistent, temporary = temporary},
	)
	testing.expectf(t, scoped, "scoped search failed with %v", scoped_failure.code)
	scoped_view, scoped_viewed, _ := result_view(&scoped_result)
	testing.expect(t, scoped_viewed)
	testing.expect_value(t, scoped_view.outcome, Outcome.No_Match)
	result_close(&scoped_result)
	cancellation: Cancellation
	_, _ = cancellation_reset(&cancellation, 9)
	testing.expect(t, cancellation_request(&cancellation, 9))
	result: Result
	searched, failure := literal_search(
		&result,
		&snapshot,
		&query,
		Request{scope = scope, origin = scope.start, direction = .Forward, generation = 9},
		&cancellation,
		Allocator_Set{persistent = persistent, temporary = temporary},
	)
	testing.expectf(t, searched, "cancelled search failed with %v", failure.code)
	view, viewed, _ := result_view(&result)
	testing.expect(t, viewed)
	testing.expect_value(t, view.outcome, Outcome.Cancelled)
	testing.expect_value(t, view.usage.cancellation_checks, u64(1))
	result_close(&result)
	query_close(&query)
	editor.buffer_snapshot_close(&snapshot)
	editor.buffer_close(&buffer)
	testing.expect_value(t, temporary_tracking.current_memory_allocated, i64(0))
	testing.expect_value(t, persistent_tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&temporary_tracking)
	mem.tracking_allocator_destroy(&persistent_tracking)
}

/* Verifies previous-query relations preserve only safe literal reuse. */
@(test)
literal_queries_report_previous_query_reuse :: proc(t: ^testing.T) {
	previous := make_literal_query(t, 7, "odra")
	current := make_literal_query(t, 8, "odra!")
	shorter := make_literal_query(t, 9, "odr")
	if previous.state == nil || current.state == nil || shorter.state == nil {
		return
	}
	defer query_close(&previous)
	defer query_close(&current)
	defer query_close(&shorter)
	reuse, ok := query_reuse(&previous, &current)
	testing.expect(t, ok)
	testing.expect_value(t, reuse.kind, Reuse_Kind.Extended)
	testing.expect_value(t, reuse.common_prefix_bytes, u64(4))
	reuse, ok = query_reuse(&previous, &shorter)
	testing.expect(t, ok)
	testing.expect_value(t, reuse.kind, Reuse_Kind.Shortened)
	testing.expect_value(t, reuse.common_prefix_bytes, u64(3))
}

@(private)
make_literal_query :: proc(t: ^testing.T, id: Query_ID, pattern: string) -> Query {
	return make_literal_query_with_allocator(t, id, pattern, context.allocator)
}

@(private)
make_literal_query_with_allocator :: proc(
	t: ^testing.T,
	id: Query_ID,
	pattern: string,
	allocator: mem.Allocator,
) -> Query {
	query: Query
	initialized, failure := query_init(
		&query,
		Query_Config{id = id, kind = .Literal, pattern = pattern, policy = DEFAULT_POLICY, limits = DEFAULT_LIMITS, allocator = allocator},
	)
	testing.expectf(t, initialized, "query init failed with %v", failure.code)
	return query
}

@(private)
Test_Turn :: struct {
	outcome: Outcome,
	has_current: bool,
	current: Occurrence,
	progress: Progress,
	usage: Usage,
}

@(private)
run_literal_turn :: proc(
	t: ^testing.T,
	snapshot: ^editor.Buffer_Snapshot,
	query: ^Query,
	request: Request,
) -> Test_Turn {
	result: Result
	searched, failure := literal_search(
		&result,
		snapshot,
		query,
		request,
		nil,
		Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	testing.expectf(t, searched, "literal search failed with %v", failure.code)
	if !searched {
		return {}
	}
	view, viewed, view_failure := result_view(&result)
	testing.expectf(t, viewed, "result view failed with %v", view_failure.code)
	turn := Test_Turn {
		outcome = view.outcome,
		has_current = view.has_current,
		progress = view.progress,
		usage = view.usage,
	}
	if len(view.occurrences) > 0 {
		turn.current = view.occurrences[0]
	}
	result_close(&result)
	return turn
}
