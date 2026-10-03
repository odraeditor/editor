// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package editor

import "core:testing"

/* Verifies logical-line resolution at content, line-feed, trailing-empty, and EOF offsets. */
@(test)
buffer_lines_resolve_from_current_positions :: proc(t: ^testing.T) {
	buffer: Buffer
	initialized, _ := buffer_init(
		&buffer,
		Buffer_ID(41),
		"alpha\nbeta\n",
		Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	testing.expect(t, initialized)
	if !initialized {
		return
	}
	defer buffer_close(&buffer)

	fixtures := [?]struct {
		name:        string,
		offset:      Byte_Offset,
		line_index:  u64,
		start:       Byte_Offset,
		content_end: Byte_Offset,
		next_start:  Byte_Offset,
	}{
		{name = "first-line-start", offset = 0, line_index = 0, start = 0, content_end = 5, next_start = 6},
		{name = "first-line-end", offset = 5, line_index = 0, start = 0, content_end = 5, next_start = 6},
		{name = "second-line-start", offset = 6, line_index = 1, start = 6, content_end = 10, next_start = 11},
		{name = "second-line-end", offset = 10, line_index = 1, start = 6, content_end = 10, next_start = 11},
		{name = "empty-final-line", offset = 11, line_index = 2, start = 11, content_end = 11, next_start = 11},
	}
	for fixture in fixtures {
		position, position_ok, _ := buffer_position(&buffer, fixture.offset)
		line, line_ok, failure := buffer_line_at_position(&buffer, position)
		testing.expectf(t, position_ok && line_ok, "%s failed with %v", fixture.name, failure.code)
		if !position_ok || !line_ok {
			continue
		}
		testing.expectf(t, line.line_index == fixture.line_index, "%s returned the wrong line index", fixture.name)
		testing.expectf(t, line.start == fixture.start, "%s returned the wrong start", fixture.name)
		testing.expectf(t, line.content_end == fixture.content_end, "%s returned the wrong content end", fixture.name)
		testing.expectf(t, line.next_start == fixture.next_start, "%s returned the wrong next start", fixture.name)
	}
}

/* Verifies line resolution rejects positions from an obsolete buffer revision. */
@(test)
buffer_line_resolution_rejects_stale_positions :: proc(t: ^testing.T) {
	buffer: Buffer
	initialized, _ := buffer_init(
		&buffer,
		Buffer_ID(43),
		"abc",
		Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	testing.expect(t, initialized)
	if !initialized {
		return
	}
	defer buffer_close(&buffer)
	stale, _, _ := buffer_position(&buffer, Byte_Offset(0))
	end, _, _ := buffer_position(&buffer, Byte_Offset(1))
	_, _, published, _ := buffer_splice(
		&buffer,
		Splice{start = stale, end = end, replacement = "x"},
		context.temp_allocator,
	)
	testing.expect(t, published)
	_, resolved, failure := buffer_line_at_position(&buffer, stale)
	testing.expect(t, !resolved)
	testing.expect_value(t, failure.code, Failure_Code.Stale_Revision)
}

/* Verifies summarized line lookup crosses multiple persistent rope leaves. */
@(test)
buffer_lines_resolve_across_rope_leaves :: proc(t: ^testing.T) {
	text: [8_194]u8
	for &value in text {
		value = 'a'
	}
	text[4_095] = '\n'
	for index in 4_096 ..< 8_192 {
		text[index] = 'b'
	}
	text[8_192] = '\n'
	text[8_193] = 'c'
	buffer: Buffer
	initialized, failure := buffer_init(
		&buffer,
		Buffer_ID(45),
		string(text[:]),
		Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	testing.expectf(t, initialized, "buffer initialization failed with %v", failure.code)
	if !initialized {
		return
	}
	defer buffer_close(&buffer)

	second_position, _, _ := buffer_position(&buffer, Byte_Offset(5_000))
	second, second_ok, second_failure := buffer_line_at_position(&buffer, second_position)
	testing.expectf(t, second_ok, "second line failed with %v", second_failure.code)
	if second_ok {
		testing.expect_value(t, second.line_index, u64(1))
		testing.expect_value(t, second.start, Byte_Offset(4_096))
		testing.expect_value(t, second.content_end, Byte_Offset(8_192))
		testing.expect_value(t, second.next_start, Byte_Offset(8_193))
	}
	third_position, _, _ := buffer_position(&buffer, Byte_Offset(8_193))
	third, third_ok, third_failure := buffer_line_at_position(&buffer, third_position)
	testing.expectf(t, third_ok, "third line failed with %v", third_failure.code)
	if third_ok {
		testing.expect_value(t, third.line_index, u64(2))
		testing.expect_value(t, third.start, Byte_Offset(8_193))
		testing.expect_value(t, third.content_end, Byte_Offset(8_194))
		testing.expect_value(t, third.next_start, Byte_Offset(8_194))
	}
}
