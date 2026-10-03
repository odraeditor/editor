// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package display

import "core:strconv"
import "core:strings"
import "core:testing"
import "core:unicode/utf8"

@(private)
UNICODE_17_GRAPHEME_BREAK_TESTS :: #load(
	"../../third_party/unicode/17.0.0/ucd/auxiliary/GraphemeBreakTest.txt",
)

/* Verifies every official Unicode 17.0.0 extended-grapheme conformance case. */
@(test)
unicode17_graphemes_pass_official_conformance :: proc(t: ^testing.T) {
	remaining := string(UNICODE_17_GRAPHEME_BREAK_TESTS)
	case_count := 0
	for raw_line in strings.split_lines_iterator(&remaining) {
		line := raw_line
		for body in strings.split_iterator(&line, "#") {
			line = strings.trim_space(body)
			break
		}
		if len(line) == 0 {
			continue
		}
		text: [256]u8
		boundaries: [128]u16
		text_length := 0
		boundary_count := 0
		fields := line
		expect_boundary := false
		for field in strings.fields_iterator(&fields) {
			if field == "÷" {
				expect_boundary = true
				continue
			}
			if field == "×" {
				expect_boundary = false
				continue
			}
			value, parsed := strconv.parse_u64_of_base(field, 16)
			testing.expectf(t, parsed, "case %d contains invalid code point %s", case_count, field)
			if !parsed {
				return
			}
			if expect_boundary {
				assert(boundary_count < len(boundaries))
				boundaries[boundary_count] = u16(text_length)
				boundary_count += 1
			}
			encoded, encoded_length := utf8.encode_rune(rune(value))
			assert(text_length + encoded_length <= len(text))
			copy(text[text_length:], encoded[:encoded_length])
			text_length += encoded_length
			expect_boundary = false
		}
		if expect_boundary {
			assert(boundary_count < len(boundaries))
			boundaries[boundary_count] = u16(text_length)
			boundary_count += 1
		}

		offset := u64(0)
		observed_boundary := 0
		for offset < u64(text_length) {
			grapheme, ok, failure := unicode17_next_grapheme(
				string(text[:text_length]),
				offset,
			)
			testing.expectf(
				t,
				ok,
				"case %d failed at byte %d with %v",
				case_count,
				offset,
				failure.code,
			)
			if !ok {
				return
			}
			observed_boundary += 1
			testing.expectf(
				t,
				observed_boundary < boundary_count,
				"case %d produced too many graphemes",
				case_count,
			)
			if observed_boundary >= boundary_count {
				return
			}
			testing.expect_value(t, grapheme.end, u64(boundaries[observed_boundary]))
			offset = grapheme.end
		}
		testing.expect_value(t, observed_boundary + 1, boundary_count)
		case_count += 1
	}
	testing.expect_value(t, case_count, 766)
}

/* Verifies the initial terminal width, tab, emoji, and replacement policies. */
@(test)
unicode17_width_policy_is_deterministic :: proc(t: ^testing.T) {
	expect_width(t, "a", 0, 4, 1, false, false, false)
	expect_width(t, "界", 0, 4, 2, false, false, false)
	expect_width(t, "¡", 0, 4, 1, false, false, false)
	expect_width(t, "e\u0301", 0, 4, 1, false, false, false)
	expect_width(t, "🙂", 0, 4, 2, false, false, false)
	expect_width(t, "👩\u200D💻", 0, 4, 2, false, false, false)
	expect_width(t, "🇵🇱", 0, 4, 2, false, false, false)
	expect_width(t, "1\uFE0F\u20E3", 0, 4, 2, false, false, false)
	expect_width(t, "\t", 0, 4, 4, true, false, false)
	expect_width(t, "\t", 3, 4, 1, true, false, false)
	expect_width(t, "\n", 0, 4, 0, false, true, false)
	expect_width(t, "\u0301", 0, 4, 1, false, false, true)
	expect_width(t, "\u0007", 0, 4, 1, false, false, true)
}

/* Verifies later Unicode data can enter through the same profile interface. */
@(test)
profiles_substitute_by_versioned_ops :: proc(t: ^testing.T) {
	profile := unicode17_profile()
	testing.expect(t, profile_is_valid(profile))
	testing.expect_value(t, profile.version, Unicode_Version{major = 17})

	fixture := Unicode_Profile {
		id = Unicode_Profile_ID(99),
		version = Unicode_Version{major = 99},
		next_grapheme = fixture_next_grapheme,
		cluster_width = fixture_cluster_width,
	}
	grapheme, grapheme_ok, _ := profile_next_grapheme(fixture, "abc", 0)
	width, width_ok, _ := profile_cluster_width(fixture, "abc", 0, 4)
	testing.expect(t, grapheme_ok && width_ok)
	testing.expect_value(t, grapheme, Grapheme{start = 0, end = 3})
	testing.expect_value(t, width.cells, u16(7))
}

@(private)
expect_width :: proc(
	t: ^testing.T,
	text: string,
	start_column: u32,
	tab_width: u16,
	cells: u16,
	is_tab, is_line_break, used_replacement: bool,
) {
	width, ok, failure := unicode17_cluster_width(text, start_column, tab_width)
	testing.expectf(t, ok, "width failed for %q with %v", text, failure.code)
	if !ok {
		return
	}
	testing.expect_value(t, width.cells, cells)
	testing.expect_value(t, width.is_tab, is_tab)
	testing.expect_value(t, width.is_line_break, is_line_break)
	testing.expect_value(t, width.used_replacement, used_replacement)
}

@(private)
fixture_next_grapheme :: proc(
	text: string,
	start: u64,
) -> (Grapheme, bool, Profile_Failure) {
	if start != 0 || len(text) == 0 {
		return {}, false, Profile_Failure{code = .End_Of_Text}
	}
	return Grapheme{start = 0, end = u64(len(text))}, true, {}
}

@(private)
fixture_cluster_width :: proc(
	text: string,
	start_column: u32,
	tab_width: u16,
) -> (Cluster_Width, bool, Profile_Failure) {
	_ = text
	_ = start_column
	_ = tab_width
	return Cluster_Width{cells = 7}, true, {}
}
