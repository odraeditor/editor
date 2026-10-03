// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package search

import "../editor"
import "core:mem"
import "core:testing"
import "core:unicode/utf8"

/* Verifies regex queries compile with fixed flags, captures, and exact cleanup. */
@(test)
regexp_compiles_standard_profiles :: proc(t: ^testing.T) {
	persistent_tracking: mem.Tracking_Allocator
	temporary_tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&persistent_tracking, context.allocator)
	mem.tracking_allocator_init(&temporary_tracking, context.allocator)
	persistent := mem.tracking_allocator(&persistent_tracking)
	temporary := mem.tracking_allocator(&temporary_tracking)
	query: Query
	initialized, failure := query_init(
		&query,
		Query_Config {
			id = 301,
			kind = .Regular_Expression,
			pattern = "(rzeka)-(odra)",
			policy = DEFAULT_POLICY,
			limits = DEFAULT_LIMITS,
			allocator = persistent,
			temporary_allocator = temporary,
		},
	)
	testing.expectf(t, initialized, "regex query init failed with %v", failure)
	if !initialized {
		mem.tracking_allocator_destroy(&temporary_tracking)
		mem.tracking_allocator_destroy(&persistent_tracking)
		return
	}
	view, viewed, view_failure := query_view(&query)
	testing.expectf(t, viewed, "regex query view failed with %v", view_failure)
	testing.expect(t, view.regex.present)
	testing.expect(t, view.regex.unicode)
	testing.expect(t, view.regex.multiline)
	testing.expect(t, view.regex.case_insensitive)
	testing.expect_value(t, view.regex.shorthands, Regex_Shorthand_Mode.ASCII)
	testing.expect_value(t, view.regex.capture_groups, MAX_CAPTURE_GROUPS)
	testing.expect_value(t, view.regex.defined_capture_groups, u16(2))
	testing.expect_value(t, view.regex.maximum_match_span_bytes, DEFAULT_MATCH_SPAN_BYTES)
	capture_positions: [MAX_CAPTURE_GROUPS][2]int
	group_count, matched, match_failure := regex_match_contiguous(
		&query,
		"RZEKA-ODRA",
		capture_positions[:],
		temporary,
	)
	testing.expectf(t, matched, "regex match failed with %v", match_failure)
	testing.expect_value(t, group_count, 3)
	testing.expect_value(t, capture_positions[1], [2]int{0, 5})
	testing.expect_value(t, capture_positions[2], [2]int{6, 10})
	closed, close_failure := query_close(&query)
	testing.expectf(t, closed, "regex query close failed with %v", close_failure)
	testing.expect_value(t, temporary_tracking.current_memory_allocated, i64(0))
	testing.expect_value(t, persistent_tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&temporary_tracking)
	mem.tracking_allocator_destroy(&persistent_tracking)
}

/* Verifies malformed patterns return checked parser diagnostics without ownership. */
@(test)
regexp_reports_parser_errors_atomically :: proc(t: ^testing.T) {
	query: Query
	initialized, failure := query_init(
		&query,
		Query_Config {
			id = 303,
			kind = .Regular_Expression,
			pattern = "(",
			policy = DEFAULT_POLICY,
			limits = DEFAULT_LIMITS,
			allocator = context.allocator,
			temporary_allocator = context.temp_allocator,
		},
	)
	testing.expect(t, !initialized)
	testing.expect_value(t, failure.code, Failure_Code.Regex_Parser_Error)
	testing.expect(t, failure.diagnostic.kind != .None)
	testing.expect(t, failure.diagnostic.byte_offset <= 1)
	testing.expect(t, query.state == nil)
}

/* Verifies multiline anchors, ASCII shorthands, and explicit case overrides. */
@(test)
regexp_queries_apply_documented_standard_flags :: proc(t: ^testing.T) {
	query := make_regexp_query(t, 304, "^\\w+$")
	if query.state == nil {
		return
	}
	captures: [MAX_CAPTURE_GROUPS][2]int
	group_count, matched, failure := regex_match_contiguous(
		&query,
		"first\nascii_42\nlast",
		captures[:],
		context.temp_allocator,
	)
	testing.expectf(t, matched, "ASCII multiline match failed with %v", failure)
	testing.expect_value(t, group_count, 1)
	testing.expect_value(t, captures[0], [2]int{0, 6})
	_, unicode_matched, _ := regex_match_contiguous(
		&query,
		"\u017c\u00f3\u0142\u0107",
		captures[:],
		context.temp_allocator,
	)
	testing.expect(t, !unicode_matched)
	query_close(&query)

	sensitive: Query
	initialized, init_failure := query_init(
		&sensitive,
		Query_Config {
			id = 306,
			kind = .Regular_Expression,
			pattern = "odra",
			policy = Policy{case_mode = .Sensitive, boundary_mode = .Unrestricted, whitespace_mode = .Exact, wrap = true},
			limits = DEFAULT_LIMITS,
			allocator = context.allocator,
			temporary_allocator = context.temp_allocator,
		},
	)
	testing.expectf(t, initialized, "sensitive regex failed with %v", init_failure)
	if initialized {
		_, sensitive_matched, _ := regex_match_contiguous(
			&sensitive,
			"ODRA",
			captures[:],
			context.temp_allocator,
		)
		testing.expect(t, !sensitive_matched)
		query_close(&sensitive)
	}
}

/* Verifies every admitted standard-library expression feature used by Odra. */
@(test)
regexp_queries_match_documented_feature_matrix :: proc(t: ^testing.T) {
	cases := [?]struct {
		name:     string,
		pattern:  string,
		text:     string,
		expected: [2]int,
	}{
		{"alternation", "apple|cherry", "xxcherry", {2, 8}},
		{"positive-class", "[0-9_]+", "ab12_3", {2, 6}},
		{"negated-class", "[^0-9_]+", "12abc_", {2, 5}},
		{"digit-class", "\\d+", "a42", {1, 3}},
		{"non-digit-class", "\\D+", "42ab", {2, 4}},
		{"space-class", "\\s+", "a \t", {1, 3}},
		{"non-space-class", "\\S+", " a", {1, 2}},
		{"word-class", "\\w+", "._a9", {1, 4}},
		{"non-word-class", "\\W+", "a-!", {1, 3}},
		{"unicode-wildcard", "a.c", "xxaβc", {2, 6}},
		{"zero-or-more", "ab*", "abbb", {0, 4}},
		{"one-or-more", "ab+", "abbb", {0, 4}},
		{"exact-repeat", "ab{3}", "abbb", {0, 4}},
		{"optional", "colou?r", "color", {0, 5}},
		{"noncapturing-group", "(?:ab)+", "zzabab", {2, 6}},
		{"line-anchors", "^first$", "first\nsecond", {0, 6}},
		{"word-boundary", "\\bword\\b", "a word!", {2, 6}},
		{"non-boundary", "word\\B", "words", {0, 4}},
		{"lazy-repeat", "a+?", "aaaa", {0, 1}},
	}
	for fixture, case_index in cases {
		query := make_regexp_query(t, Query_ID(320 + case_index), fixture.pattern)
		if query.state == nil {
			continue
		}
		positions: [MAX_CAPTURE_GROUPS][2]int
		group_count, matched, failure := regex_match_contiguous(
			&query,
			fixture.text,
			positions[:],
			context.temp_allocator,
		)
		testing.expectf(t, matched, "%s feature failed with %v", fixture.name, failure)
		testing.expectf(t, group_count > 0, "%s feature returned no complete capture", fixture.name)
		if group_count > 0 {
			testing.expectf(
				t,
				positions[0] == fixture.expected,
				"%s feature got %v instead of %v",
				fixture.name,
				positions[0],
				fixture.expected,
			)
		}
		query_close(&query)
	}
}

/* Verifies parser and compiler bounds become checked query diagnostics. */
@(test)
regexp_queries_report_documented_error_matrix :: proc(t: ^testing.T) {
	malformed := [?]struct {
		name:    string,
		pattern: string,
	} {
		{"unterminated-group", "("},
		{"unterminated-class", "[abc"},
		{"reversed-repeat", "a{3,2}"},
		{"zero-repeat", "a{0}"},
	}
	for test_case, case_index in malformed {
		query: Query
		initialized, failure := query_init(
			&query,
			Query_Config {
				id = Query_ID(350 + case_index),
				kind = .Regular_Expression,
				pattern = test_case.pattern,
				policy = DEFAULT_POLICY,
				limits = DEFAULT_LIMITS,
				allocator = context.allocator,
				temporary_allocator = context.temp_allocator,
			},
		)
		testing.expectf(t, !initialized, "%s expression was admitted", test_case.name)
		testing.expectf(t, failure.code == .Regex_Parser_Error, "%s expression returned the wrong failure", test_case.name)
		testing.expectf(t, failure.diagnostic.kind != .None, "%s expression returned no diagnostic", test_case.name)
		testing.expectf(t, query.state == nil, "%s expression retained query state", test_case.name)
		if initialized {
			query_close(&query)
		}
	}

	class_pattern := regexp_class_limit_pattern()
	defer delete(class_pattern)
	limits := DEFAULT_LIMITS
	limits.pattern_bytes = MAX_PATTERN_BYTES
	class_query: Query
	class_ok, class_failure := query_init(
		&class_query,
		Query_Config {
			id = 370,
			kind = .Regular_Expression,
			pattern = string(class_pattern[:]),
			policy = DEFAULT_POLICY,
			limits = limits,
			allocator = context.allocator,
			temporary_allocator = context.temp_allocator,
		},
	)
	testing.expect(t, !class_ok)
	testing.expect_value(t, class_failure.code, Failure_Code.Regex_Compiler_Error)
	testing.expect_value(t, class_failure.diagnostic.kind, Regex_Diagnostic_Kind.Too_Many_Classes)
	testing.expect(t, class_query.state == nil)
	if class_ok {
		query_close(&class_query)
	}

	program_pattern := regexp_program_limit_pattern()
	defer delete(program_pattern)
	program_query: Query
	program_ok, program_failure := query_init(
		&program_query,
		Query_Config {
			id = 371,
			kind = .Regular_Expression,
			pattern = string(program_pattern[:]),
			policy = DEFAULT_POLICY,
			limits = limits,
			allocator = context.allocator,
			temporary_allocator = context.temp_allocator,
		},
	)
	testing.expect(t, !program_ok)
	testing.expect_value(t, program_failure.code, Failure_Code.Regex_Compiler_Error)
	testing.expect_value(t, program_failure.diagnostic.kind, Regex_Diagnostic_Kind.Program_Too_Big)
	testing.expect(t, program_query.state == nil)
	if program_ok {
		query_close(&program_query)
	}
}

/* Verifies forward and backward plans retain only bounded cross-window overlap. */
@(test)
regexp_plans_bound_bidirectional_reads :: proc(t: ^testing.T) {
	query := make_regexp_query(t, 305, "first.*last")
	if query.state == nil {
		return
	}
	defer query_close(&query)
	scope := Scope{buffer_id = 81, revision = 4, start = 1_000, end = 1_000_000}
	forward, planned, failure := regex_window_plan(
		&query,
		Request{scope = scope, origin = 20_000, direction = .Forward, generation = 1},
	)
	testing.expectf(t, planned, "forward window failed with %v", failure)
	testing.expect_value(t, forward.logical_start, editor.Byte_Offset(20_000))
	testing.expect_value(t, forward.logical_end, editor.Byte_Offset(20_000 + DEFAULT_SCAN_WINDOW_BYTES))
	testing.expect_value(t, forward.read_start, forward.logical_start)
	testing.expect_value(
		t,
		forward.read_end,
		editor.Byte_Offset(20_000 + DEFAULT_SCAN_WINDOW_BYTES + DEFAULT_MATCH_SPAN_BYTES - 1),
	)
	backward, backward_planned, backward_failure := regex_window_plan(
		&query,
		Request{scope = scope, origin = 400_000, direction = .Backward, generation = 2},
	)
	testing.expectf(t, backward_planned, "backward window failed with %v", backward_failure)
	testing.expect_value(t, backward.logical_end, editor.Byte_Offset(400_000))
	testing.expect_value(t, backward.logical_start, editor.Byte_Offset(400_000 - DEFAULT_SCAN_WINDOW_BYTES))
	testing.expect_value(t, backward.read_end, backward.logical_end)
	testing.expect_value(
		t,
		backward.read_start,
		editor.Byte_Offset(400_000 - DEFAULT_SCAN_WINDOW_BYTES - DEFAULT_MATCH_SPAN_BYTES + 1),
	)
	too_small: [1][2]int
	_, matched, capture_failure := regex_match_contiguous(
		&query,
		"first then last",
		too_small[:],
		context.temp_allocator,
	)
	testing.expect(t, !matched)
	testing.expect_value(t, capture_failure.code, Failure_Code.Capture_Limit)
	oversized := make([]byte, int(DEFAULT_SCAN_WINDOW_BYTES + DEFAULT_MATCH_SPAN_BYTES))
	defer delete(oversized)
	positions: [MAX_CAPTURE_GROUPS][2]int
	_, oversized_matched, work_failure := regex_match_contiguous(
		&query,
		string(oversized),
		positions[:],
		context.temp_allocator,
	)
	testing.expect(t, !oversized_matched)
	testing.expect_value(t, work_failure.code, Failure_Code.Work_Limit)
}

@(private)
make_regexp_query :: proc(t: ^testing.T, id: Query_ID, pattern: string) -> Query {
	query: Query
	initialized, failure := query_init(
		&query,
		Query_Config {
			id = id,
			kind = .Regular_Expression,
			pattern = pattern,
			policy = DEFAULT_POLICY,
			limits = DEFAULT_LIMITS,
			allocator = context.allocator,
			temporary_allocator = context.temp_allocator,
		},
	)
	testing.expectf(t, initialized, "regex query init failed with %v", failure)
	return query
}

@(private)
regexp_class_limit_pattern :: proc() -> [dynamic]byte {
	pattern := make([dynamic]byte, 0, 2_048)
	for index in 0 ..< 255 {
		append(&pattern, '[')
		append(&pattern, 'a')
		encoded, width := utf8.encode_rune(rune(0x0100 + index))
		append(&pattern, ..encoded[:width])
		append(&pattern, ']')
	}
	return pattern
}

@(private)
regexp_program_limit_pattern :: proc() -> [dynamic]byte {
	pattern := make([dynamic]byte, 0, 36_000)
	for index in 0 ..< 12_000 {
		encoded, width := utf8.encode_rune(rune(0x0100 + index % 512))
		append(&pattern, ..encoded[:width])
	}
	return pattern
}
