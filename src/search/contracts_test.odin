// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package search

import "../editor"
import "core:mem"
import "core:testing"

/* Verifies measured defaults admit a copied query and release every owned byte. */
@(test)
queries_copy_patterns_select_smart_case :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	query: Query
	initialized, failure := query_init(
		&query,
		Query_Config {
			id = 1,
			kind = .Literal,
			pattern = "Odra",
			policy = DEFAULT_POLICY,
			limits = DEFAULT_LIMITS,
			allocator = allocator,
		},
	)
	testing.expectf(t, initialized, "query init failed with %v", failure.code)
	if !initialized {
		mem.tracking_allocator_destroy(&tracking)
		return
	}
	view, viewed, view_failure := query_view(&query)
	testing.expectf(t, viewed, "query view failed with %v", view_failure.code)
	testing.expect_value(t, view.pattern, "Odra")
	testing.expect_value(t, view.effective_case, Effective_Case.Sensitive)
	closed, close_failure := query_close(&query)
	testing.expectf(t, closed, "query close failed with %v", close_failure.code)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&tracking)
}

/* Verifies malformed, empty, oversized, and invalid-policy queries fail atomically. */
@(test)
queries_reject_invalid_inputs_without_ownership :: proc(t: ^testing.T) {
	invalid_utf8 := [1]byte{0xff}
	cases := [?]struct {
		name:     string,
		config:   Query_Config,
		expected: Failure_Code,
	} {
		{
			name = "zero identity",
			config = Query_Config{kind = .Literal, pattern = "x", policy = DEFAULT_POLICY, limits = DEFAULT_LIMITS, allocator = context.allocator},
			expected = .Invalid_Query_ID,
		},
		{
			name = "empty pattern",
			config = Query_Config{id = 1, kind = .Literal, policy = DEFAULT_POLICY, limits = DEFAULT_LIMITS, allocator = context.allocator},
			expected = .Empty_Pattern,
		},
		{
			name = "malformed utf8",
			config = Query_Config{id = 1, kind = .Literal, pattern = string(invalid_utf8[:]), policy = DEFAULT_POLICY, limits = DEFAULT_LIMITS, allocator = context.allocator},
			expected = .Malformed_UTF8,
		},
		{
			name = "pattern limit",
			config = Query_Config{id = 1, kind = .Literal, pattern = "xx", policy = DEFAULT_POLICY, limits = Limits{pattern_bytes = 1, scan_window_bytes = MIN_SCAN_WINDOW_BYTES, cancellation_bytes = MIN_CANCELLATION_BYTES, retained_occurrences = MIN_RETAINED_OCCURRENCES, temporary_bytes = MIN_TEMPORARY_BYTES, capture_groups = MAX_CAPTURE_GROUPS, match_span_bytes = MIN_MATCH_SPAN_BYTES}, allocator = context.allocator},
			expected = .Pattern_Limit,
		},
		{
			name = "invalid case mode",
			config = Query_Config{id = 1, kind = .Literal, pattern = "x", policy = {}, limits = DEFAULT_LIMITS, allocator = context.allocator},
			expected = .Invalid_Case_Mode,
		},
	}
	for test_case in cases {
		query: Query
		initialized, failure := query_init(&query, test_case.config)
		testing.expectf(t, !initialized, "%s unexpectedly initialized", test_case.name)
		testing.expectf(
			t,
			failure.code == test_case.expected,
			"%s returned %v instead of %v",
			test_case.name,
			failure.code,
			test_case.expected,
		)
		testing.expectf(t, query.state == nil, "%s retained query state", test_case.name)
	}
}

/* Verifies requests require exact snapshot identity, revision, direction, and bounds. */
@(test)
requests_validate_revisioned_scopes_and_origins :: proc(t: ^testing.T) {
	query: Query
	initialized, _ := query_init(
		&query,
		Query_Config{id = 7, kind = .Literal, pattern = "odra", policy = DEFAULT_POLICY, limits = DEFAULT_LIMITS, allocator = context.allocator},
	)
	testing.expect(t, initialized)
	if !initialized {
		return
	}
	defer query_close(&query)
	stats := editor.Buffer_Snapshot_Stats{buffer_id = 11, revision = 3, text_bytes = 128}
	request := Request {
		scope = Scope{buffer_id = 11, revision = 3, start = 10, end = 100},
		origin = 25,
		direction = .Forward,
		generation = 1,
	}
	valid, failure := request_validate(&query, request, stats)
	testing.expectf(t, valid, "valid request failed with %v", failure.code)
	request.scope.revision = 2
	valid, failure = request_validate(&query, request, stats)
	testing.expect(t, !valid)
	testing.expect_value(t, failure.code, Failure_Code.Stale_Revision)
	request.scope.revision = 3
	request.origin = 101
	valid, failure = request_validate(&query, request, stats)
	testing.expect(t, !valid)
	testing.expect_value(t, failure.code, Failure_Code.Out_Of_Range)
}

/* Verifies generation-scoped cancellation cannot leak into later work. */
@(test)
cancellation_is_generation_scoped :: proc(t: ^testing.T) {
	cancellation: Cancellation
	reset, failure := cancellation_reset(&cancellation, 4)
	testing.expectf(t, reset, "cancellation reset failed with %v", failure.code)
	testing.expect(t, !cancellation_request(&cancellation, 3))
	testing.expect(t, !cancellation_requested(&cancellation, 4))
	testing.expect(t, cancellation_request(&cancellation, 4))
	testing.expect(t, cancellation_requested(&cancellation, 4))
	reset, _ = cancellation_reset(&cancellation, 5)
	testing.expect(t, reset)
	testing.expect(t, !cancellation_requested(&cancellation, 4))
	testing.expect(t, !cancellation_requested(&cancellation, 5))
}

/* Verifies copied result records remain exact and teardown releases all storage. */
@(test)
results_copy_revisioned_records :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	scope := Scope{buffer_id = 19, revision = 8, start = 0, end = 64}
	occurrences := [1]Occurrence{{buffer_id = 19, revision = 8, start = 4, end = 8}}
	result: Result
	initialized, failure := result_init(
		&result,
		Result_Config {
			outcome = .Matched,
			scope = scope,
			has_current = true,
			current_index = 0,
			occurrences = occurrences[:],
			progress = Progress{next_offset = 8, complete = true},
			limits = DEFAULT_LIMITS,
			allocator = allocator,
		},
	)
	testing.expectf(t, initialized, "result init failed with %v", failure.code)
	if !initialized {
		mem.tracking_allocator_destroy(&tracking)
		return
	}
	occurrences[0].start = 20
	view, viewed, view_failure := result_view(&result)
	testing.expectf(t, viewed, "result view failed with %v", view_failure.code)
	testing.expect_value(t, view.occurrences[0].start, editor.Byte_Offset(4))
	testing.expect_value(t, view.usage.retained_occurrences, u32(1))
	closed, close_failure := result_close(&result)
	testing.expectf(t, closed, "result close failed with %v", close_failure.code)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&tracking)
}
