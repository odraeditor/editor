// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package display

import "../editor"
import editor_view "../view"
import "core:testing"

/* Verifies a grapheme rectangle derives one clamped half-open range per line. */
@(test)
rectangular_selection_derives_logical_line_ranges :: proc(t: ^testing.T) {
	buffer: editor.Buffer
	initialized, _ := editor.buffer_init(
		&buffer, 901, "abcd\nxy\nαβγδ\n",
		editor.Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, initialized)
	if !initialized do return
	defer editor.buffer_close(&buffer)
	registry: editor_view.Registry
	registry_ok, _ := editor_view.registry_init(&registry, 901, context.allocator)
	testing.expect(t, registry_ok)
	if !registry_ok do return
	defer {
		closed, _ := editor_view.registry_close(&registry)
		testing.expect(t, closed)
	}
	handle, viewed, _ := editor_view.create(&registry, &buffer)
	testing.expect(t, viewed)
	if !viewed do return
	defer {
		closed, _ := editor_view.close(&registry, &handle)
		testing.expect(t, closed)
	}
	anchor, anchor_ok, _ := editor.buffer_position(&buffer, 1)
	cursor, cursor_ok, _ := editor.buffer_position(&buffer, 10)
	testing.expect(t, anchor_ok && cursor_ok)
	selected, _ := editor_view.select_range(
		&registry, handle, anchor, cursor, 1, .Rectangle, .Grapheme,
	)
	testing.expect(t, selected)
	logical, snapshot_ok, _ := editor_view.snapshot(&registry, handle)
	testing.expect(t, snapshot_ok)
	descriptor, ranges, resolved, failure := rectangular_selection_ranges(
		&buffer, logical, terminal_unicode17_profile(), context.temp_allocator,
	)
	testing.expectf(t, resolved, "rectangle resolution failed with %v", failure.code)
	if !resolved do return
	defer delete(ranges, context.temp_allocator)
	testing.expect_value(t, descriptor.top_line, u64(0))
	testing.expect_value(t, descriptor.bottom_line, u64(2))
	testing.expect_value(t, descriptor.left_column, u32(1))
	testing.expect_value(t, descriptor.right_column, u32(2))
	testing.expect_value(t, len(ranges), 3)
	testing.expect_value(t, ranges[0].start.byte_offset, editor.Byte_Offset(1))
	testing.expect_value(t, ranges[0].end.byte_offset, editor.Byte_Offset(2))
	testing.expect_value(t, ranges[1].start.byte_offset, editor.Byte_Offset(6))
	testing.expect_value(t, ranges[1].end.byte_offset, editor.Byte_Offset(7))
	testing.expect_value(t, ranges[2].start.byte_offset, editor.Byte_Offset(10))
	testing.expect_value(t, ranges[2].end.byte_offset, editor.Byte_Offset(12))
}
