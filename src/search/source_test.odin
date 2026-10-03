// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package search

import "core:testing"

@(test)
/* Verifies direct sources preserve literal Unicode and boundary policy. */
turn_preserves_literal_unicode :: proc(t: ^testing.T) {
	query: Query
	initialized, _ := query_init(&query, Query_Config{id = 1, kind = .Literal,
		pattern = "żółć", policy = Policy{case_mode = .Sensitive,
			boundary_mode = .Word, whitespace_mode = .Exact}, limits = DEFAULT_LIMITS,
		allocator = context.allocator, temporary_allocator = context.temp_allocator})
	testing.expect(t, initialized)
	defer query_close(&query)
	matches: [8]Source_Match
	turn, searched, failure := source_search_turn(
		&query, "żółć żółcie żółć", 0, matches[:], context.temp_allocator,
	)
	testing.expectf(t, searched, "source search failed with %v", failure.code)
	testing.expect_value(t, turn.matches, 2)
	testing.expect(t, turn.complete)
	testing.expect_value(t, matches[0].start, 0)
	testing.expect_value(t, matches[1].end, u64(len("żółć żółcie żółć")))
}

@(test)
/* Ensures source search uses the shared regular-expression compiler. */
turn_uses_the_shared_regular_expression_compiler :: proc(t: ^testing.T) {
	query: Query
	initialized, _ := query_init(&query, Query_Config{id = 2, kind = .Regular_Expression,
		pattern = `value\s*=\s*[0-9]+`, policy = DEFAULT_POLICY, limits = DEFAULT_LIMITS,
		allocator = context.allocator, temporary_allocator = context.temp_allocator})
	testing.expect(t, initialized)
	defer query_close(&query)
	matches: [8]Source_Match
	turn, searched, failure := source_search_turn(
		&query, "value = 10\nvalue = 20\n", 0, matches[:], context.temp_allocator,
	)
	testing.expectf(t, searched, "source search failed with %v", failure.code)
	testing.expect_value(t, turn.matches, 2)
	testing.expect(t, turn.complete)
}
