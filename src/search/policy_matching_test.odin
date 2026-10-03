// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package search

import "core:testing"

/* Verifies queries reject incomplete boundary and whitespace policy dimensions. */
@(test)
queries_require_complete_search_policies :: proc(t: ^testing.T) {
	cases := [?]struct {
		name:     string,
		policy:   Policy,
		expected: Failure_Code,
	} {
		{
			name = "missing-boundary-mode",
			policy = Policy{case_mode = .Smart, whitespace_mode = .Exact},
			expected = .Invalid_Boundary_Mode,
		},
		{
			name = "missing-whitespace-mode",
			policy = Policy{case_mode = .Smart, boundary_mode = .Unrestricted},
			expected = .Invalid_Whitespace_Mode,
		},
	}
	for test_case, index in cases {
		query: Query
		initialized, failure := query_init(
			&query,
			Query_Config {
				id = Query_ID(index + 1),
				kind = .Literal,
				pattern = "odra",
				policy = test_case.policy,
				limits = DEFAULT_LIMITS,
				allocator = context.allocator,
			},
		)
		testing.expectf(t, !initialized, "%s policy was accepted", test_case.name)
		testing.expectf(t, failure.code == test_case.expected, "%s policy returned the wrong failure", test_case.name)
	}
}

/* Verifies literal matching applies nonempty whitespace and generic boundaries. */
@(test)
literal_policies_match_flexible_whitespace :: proc(t: ^testing.T) {
	flexible := Query_View {
		pattern = "cat dog",
		policy = Policy {
			case_mode = .Sensitive,
			boundary_mode = .Word,
			whitespace_mode = .Flexible,
		},
		effective_case = .Sensitive,
	}
	text := string("cat\n\t dog scatter")
	end, matched := literal_match_at(transmute([]u8)text, 0, flexible)
	testing.expect(t, matched)
	testing.expect_value(t, end, 9)

	word := Query_View {
		pattern = "cat",
		policy = Policy {
			case_mode = .Sensitive,
			boundary_mode = .Word,
			whitespace_mode = .Exact,
		},
		effective_case = .Sensitive,
	}
	_, embedded := literal_match_at(transmute([]u8)text, 11, word)
	testing.expect(t, !embedded)

	symbol := Query_View {
		pattern = "foo",
		policy = Policy {
			case_mode = .Sensitive,
			boundary_mode = .Symbol,
			whitespace_mode = .Exact,
		},
		effective_case = .Sensitive,
	}
	symbol_text := string("foo-bar foo")
	_, hyphenated := literal_match_at(transmute([]u8)symbol_text, 0, symbol)
	testing.expect(t, !hyphenated)
	_, standalone := literal_match_at(transmute([]u8)symbol_text, 8, symbol)
	testing.expect(t, standalone)
}

/* Verifies flexible regexp whitespace preserves escaped and character-class spaces. */
@(test)
regexp_normalizes_unescaped_whitespace :: proc(t: ^testing.T) {
	query: Query
	initialized, failure := query_init(
		&query,
		Query_Config {
			id = 9,
			kind = .Regular_Expression,
			pattern = "cat +[ ]dog",
			policy = Policy {
				case_mode = .Sensitive,
				boundary_mode = .Unrestricted,
				whitespace_mode = .Flexible,
			},
			limits = DEFAULT_LIMITS,
			allocator = context.allocator,
			temporary_allocator = context.temp_allocator,
		},
	)
	testing.expectf(t, initialized, "regexp query failed with %v", failure.code)
	if !initialized {
		return
	}
	defer query_close(&query)
	positions: [MAX_CAPTURE_GROUPS][2]int
	_, matched, match_failure := regex_match_contiguous(
		&query,
		"cat\n\t  dog",
		positions[:],
		context.temp_allocator,
	)
	testing.expectf(t, matched, "regexp did not match with %v", match_failure.code)
}
