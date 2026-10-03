// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package display

import "../editor"
import editor_view "../view"
import "core:testing"

/* Verifies horizontal movement crosses complete graphemes and logical line boundaries. */
@(test)
navigation_moves_across_unicode_graphemes :: proc(t: ^testing.T) {
	fixture: Projection_Fixture
	ready := projection_fixture_init(t, &fixture, 91, "a🙂b\nx界z")
	if !ready {
		return
	}
	defer projection_fixture_close(&fixture)
	cursor, _, _ := editor.buffer_position(&fixture.buffer, editor.Byte_Offset(1))
	editor_view.set_point(&fixture.registry, fixture.handle, cursor)
	logical, _, _ := editor_view.snapshot(&fixture.registry, fixture.handle)
	next, next_column, next_ok, next_failure := navigation_target(
		&fixture.buffer,
		logical,
		.Next_Grapheme,
		terminal_unicode17_profile(),
	)
	testing.expectf(t, next_ok, "next failed with %v", next_failure.code)
	testing.expect_value(t, next.byte_offset, editor.Byte_Offset(5))
	testing.expect_value(t, next_column, u32(3))
	previous_logical := logical
	previous_logical.point_position = next
	previous, previous_column, previous_ok, _ := navigation_target(
		&fixture.buffer,
		previous_logical,
		.Previous_Grapheme,
		terminal_unicode17_profile(),
	)
	testing.expect(t, previous_ok)
	testing.expect_value(t, previous.byte_offset, editor.Byte_Offset(1))
	testing.expect_value(t, previous_column, u32(1))
}

/* Verifies vertical movement chooses the nearest boundary and preserves desired column. */
@(test)
navigation_preserves_desired_column_across_lines :: proc(t: ^testing.T) {
	fixture: Projection_Fixture
	ready := projection_fixture_init(t, &fixture, 93, "a🙂b\nx界z\nq")
	if !ready {
		return
	}
	defer projection_fixture_close(&fixture)
	cursor, _, _ := editor.buffer_position(&fixture.buffer, editor.Byte_Offset(5))
	editor_view.move_point(&fixture.registry, fixture.handle, cursor, 3)
	logical, _, _ := editor_view.snapshot(&fixture.registry, fixture.handle)
	down, desired, down_ok, _ := navigation_target(
		&fixture.buffer,
		logical,
		.Next_Line,
		terminal_unicode17_profile(),
	)
	testing.expect(t, down_ok)
	testing.expect_value(t, down.byte_offset, editor.Byte_Offset(11))
	testing.expect_value(t, desired, u32(3))
	editor_view.move_point(&fixture.registry, fixture.handle, down, desired)
	second, _, _ := editor_view.snapshot(&fixture.registry, fixture.handle)
	short, retained, short_ok, _ := navigation_target(
		&fixture.buffer,
		second,
		.Next_Line,
		terminal_unicode17_profile(),
	)
	testing.expect(t, short_ok)
	testing.expect_value(t, short.byte_offset, editor.Byte_Offset(14))
	testing.expect_value(t, retained, u32(3))
}

/* Verifies navigation rejects logical lines beyond the operating source bound. */
@(test)
navigation_rejects_overlong_logical_lines :: proc(t: ^testing.T) {
	text: [65_537]u8
	for &value in text {
		value = 'x'
	}
	fixture: Projection_Fixture
	ready := projection_fixture_init(t, &fixture, 95, string(text[:]))
	if !ready {
		return
	}
	defer projection_fixture_close(&fixture)
	logical, _, _ := editor_view.snapshot(&fixture.registry, fixture.handle)
	_, _, moved, failure := navigation_target(
		&fixture.buffer,
		logical,
		.Next_Grapheme,
		terminal_unicode17_profile(),
	)
	testing.expect(t, !moved)
	testing.expect_value(t, failure.code, Failure_Code.Source_Byte_Limit)
}

/* Verifies word navigation uses Unicode letters, digits, and underscore runs across lines. */
@(test)
moves_across_unicode_words_and_punctuation :: proc(t: ^testing.T) {
	contents := "  Żółć,_42 !!!\n界 foo"
	fixture: Projection_Fixture
	ready := projection_fixture_init(t, &fixture, 96, contents)
	if !ready do return
	defer projection_fixture_close(&fixture)
	logical, _, _ := editor_view.snapshot(&fixture.registry, fixture.handle)
	first, first_column, first_ok, _ := navigation_target(
		&fixture.buffer, logical, .Next_Word, terminal_unicode17_profile(),
	)
	testing.expect(t, first_ok)
	testing.expect_value(t, first.byte_offset, editor.Byte_Offset(len("  Żółć")))
	testing.expect_value(t, first_column, u32(6))
	logical.point_position.byte_offset = 0
	before_start, _, before_start_ok, _ := navigation_target(
		&fixture.buffer, logical, .Previous_Word, terminal_unicode17_profile(),
	)
	testing.expect(t, before_start_ok)
	testing.expect_value(t, before_start.byte_offset, editor.Byte_Offset(0))
	logical.point_position = first
	second, _, second_ok, _ := navigation_target(
		&fixture.buffer, logical, .Next_Word, terminal_unicode17_profile(),
	)
	testing.expect(t, second_ok)
	testing.expect_value(t, second.byte_offset, editor.Byte_Offset(len("  Żółć,_42")))
	logical.point_position = second
	third, _, third_ok, _ := navigation_target(
		&fixture.buffer, logical, .Next_Word, terminal_unicode17_profile(),
	)
	testing.expect(t, third_ok)
	testing.expect_value(t, third.byte_offset, editor.Byte_Offset(len("  Żółć,_42 !!!\n界")))
	logical.point_position = third
	previous, _, previous_ok, _ := navigation_target(
		&fixture.buffer, logical, .Previous_Word, terminal_unicode17_profile(),
	)
	testing.expect(t, previous_ok)
	testing.expect_value(t, previous.byte_offset, editor.Byte_Offset(len("  Żółć,_42 !!!\n")))
	logical.point_position = third
	logical.point_position.byte_offset = editor.Byte_Offset(len(contents))
	start, _, start_ok, _ := navigation_target(
		&fixture.buffer, logical, .Next_Word, terminal_unicode17_profile(),
	)
	testing.expect(t, start_ok)
	testing.expect_value(t, start.byte_offset, editor.Byte_Offset(len(contents)))
}

/* Verifies modal word-start and buffer boundaries reuse canonical positions. */
@(test)
modal_navigation_resolves_word_and_buffer_boundaries :: proc(t: ^testing.T) {
	contents := "alpha  βeta\ngamma"
	fixture: Projection_Fixture
	ready := projection_fixture_init(t, &fixture, 98, contents)
	if !ready do return
	defer projection_fixture_close(&fixture)
	logical, _, _ := editor_view.snapshot(&fixture.registry, fixture.handle)
	next, _, next_ok, next_failure := navigation_target(
		&fixture.buffer, logical, .Next_Word_Start, terminal_unicode17_profile(),
	)
	testing.expectf(t, next_ok, "next word start failed with %v", next_failure.code)
	testing.expect_value(t, next.byte_offset, editor.Byte_Offset(len("alpha  ")))
	logical.point_position = next
	end, _, end_ok, end_failure := navigation_target(
		&fixture.buffer, logical, .Buffer_End, terminal_unicode17_profile(),
	)
	testing.expectf(t, end_ok, "buffer end failed with %v", end_failure.code)
	testing.expect_value(t, end.byte_offset, editor.Byte_Offset(len(contents)))
	logical.point_position = end
	start, _, start_ok, start_failure := navigation_target(
		&fixture.buffer, logical, .Buffer_Start, terminal_unicode17_profile(),
	)
	testing.expectf(t, start_ok, "buffer start failed with %v", start_failure.code)
	testing.expect_value(t, start.byte_offset, editor.Byte_Offset(0))
}

/* Verifies modal word starts treat a punctuation run as an independent target. */
@(test)
modal_navigation_stops_at_unicode_punctuation :: proc(t: ^testing.T) {
	contents := "one 🙂two"
	fixture: Projection_Fixture
	ready := projection_fixture_init(t, &fixture, 99, contents)
	if !ready do return
	defer projection_fixture_close(&fixture)
	logical, _, _ := editor_view.snapshot(&fixture.registry, fixture.handle)

	target, _, resolved, failure := navigation_target(
		&fixture.buffer,
		logical,
		.Next_Word_Start,
		terminal_unicode17_profile(),
	)

	testing.expectf(t, resolved, "punctuation word start failed with %v", failure.code)
	testing.expect_value(t, target.byte_offset, editor.Byte_Offset(len("one ")))
}

/* Verifies line-character targets are Unicode-aware, counted, and line-local. */
@(test)
modal_line_character_navigation_is_counted_and_atomic :: proc(t: ^testing.T) {
	contents := "a🙂b🙂c\n🙂"
	fixture: Projection_Fixture
	ready := projection_fixture_init(t, &fixture, 99, contents)
	if !ready do return
	defer projection_fixture_close(&fixture)
	logical, _, _ := editor_view.snapshot(&fixture.registry, fixture.handle)
	second, _, found, second_ok, second_failure := line_character_navigation_target(
		&fixture.buffer,
		logical,
		"🙂",
		.Find_Next,
		2,
		terminal_unicode17_profile(),
	)
	testing.expectf(t, second_ok && found, "second character failed with %v", second_failure.code)
	testing.expect_value(t, second.byte_offset, editor.Byte_Offset(len("a🙂b")))
	till, _, till_found, till_ok, till_failure := line_character_navigation_target(
		&fixture.buffer,
		logical,
		"🙂",
		.Till_Next,
		2,
		terminal_unicode17_profile(),
	)
	testing.expectf(t, till_ok && till_found, "till character failed with %v", till_failure.code)
	testing.expect_value(t, till.byte_offset, editor.Byte_Offset(len("a🙂")))
	line_end, _, _ := editor.buffer_position(&fixture.buffer, editor.Byte_Offset(len("a🙂b🙂c")))
	logical.point_position = line_end
	previous, _, previous_found, previous_ok, previous_failure := line_character_navigation_target(
		&fixture.buffer,
		logical,
		"🙂",
		.Find_Previous,
		2,
		terminal_unicode17_profile(),
	)
	testing.expectf(t, previous_ok && previous_found, "previous character failed with %v", previous_failure.code)
	testing.expect_value(t, previous.byte_offset, editor.Byte_Offset(1))
	till_previous, _, till_previous_found, till_previous_ok, till_previous_failure :=
		line_character_navigation_target(
			&fixture.buffer,
			logical,
			"🙂",
			.Till_Previous,
			1,
			terminal_unicode17_profile(),
		)
	testing.expectf(
		t,
		till_previous_ok && till_previous_found,
		"till previous character failed with %v",
		till_previous_failure.code,
	)
	testing.expect_value(t, till_previous.byte_offset, editor.Byte_Offset(len("a🙂b🙂")))
	missing, _, missing_found, missing_ok, missing_failure := line_character_navigation_target(
		&fixture.buffer,
		logical,
		"z",
		.Find_Next,
		1,
		terminal_unicode17_profile(),
	)
	testing.expectf(t, missing_ok && !missing_found, "missing target failed with %v", missing_failure.code)
	testing.expect_value(t, missing, logical.point_position)
}

/* Verifies first-non-whitespace movement handles tabs and whitespace-only lines. */
@(test)
moves_to_first_non_whitespace_or_line_end :: proc(t: ^testing.T) {
	contents := "\t  éx\n    \n界"
	fixture: Projection_Fixture
	ready := projection_fixture_init(t, &fixture, 97, contents)
	if !ready do return
	defer projection_fixture_close(&fixture)
	logical, _, _ := editor_view.snapshot(&fixture.registry, fixture.handle)
	first, _, first_ok, _ := navigation_target(
		&fixture.buffer, logical, .Line_First_Non_Whitespace, terminal_unicode17_profile(),
	)
	testing.expect(t, first_ok)
	testing.expect_value(t, first.byte_offset, editor.Byte_Offset(len("\t  ")))
	second_position, _, _ := editor.buffer_position(&fixture.buffer, editor.Byte_Offset(len("\t  éx\n")))
	logical.point_position = second_position
	second, _, second_ok, _ := navigation_target(
		&fixture.buffer, logical, .Line_First_Non_Whitespace, terminal_unicode17_profile(),
	)
	testing.expect(t, second_ok)
	testing.expect_value(t, second.byte_offset, editor.Byte_Offset(len("\t  éx\n    ")))
}
