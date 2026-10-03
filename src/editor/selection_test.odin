// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package editor

import "core:testing"

/* Verifies a new buffer owns one canonical point and no mark. */
@(test)
selection_initializes_with_buffer_owned_point :: proc(t: ^testing.T) {
	buffer := selection_test_buffer(t, Buffer_ID(151), "abc")
	if !buffer_is_live(&buffer) {
		return
	}
	defer buffer_close(&buffer)

	selection, selected, _ := buffer_selection_snapshot(&buffer)
	anchors, anchors_ok, _ := buffer_anchor_stats(&buffer)
	testing.expect(t, selected && anchors_ok)
	testing.expect_value(t, selection.point_position.byte_offset, Byte_Offset(0))
	testing.expect(t, !selection.mark.present && !selection.region_active)
	testing.expect_value(t, selection.generation, u64(1))
	testing.expect_value(t, anchors.live_count, u32(1))
}

/* Verifies point, mark, activation, exchange, and clearing share one generation. */
@(test)
mutations_publish_one_canonical_generation :: proc(t: ^testing.T) {
	buffer := selection_test_buffer(t, Buffer_ID(152), "abcdef")
	if !buffer_is_live(&buffer) {
		return
	}
	defer buffer_close(&buffer)

	mark, _, _ := buffer_position(&buffer, Byte_Offset(2))
	point, _, _ := buffer_position(&buffer, Byte_Offset(5))
	marked, _ := buffer_selection_set_mark(&buffer, mark, true)
	moved, _ := buffer_selection_move(&buffer, point, .Preserve)
	exchanged, _ := buffer_selection_exchange(&buffer)
	selection, selected, _ := buffer_selection_snapshot(&buffer)
	testing.expect(t, marked && moved && exchanged && selected)
	testing.expect_value(t, selection.point_position.byte_offset, Byte_Offset(2))
	testing.expect_value(t, selection.mark.position.byte_offset, Byte_Offset(5))
	testing.expect(t, selection.mark.present && selection.region_active)
	testing.expect_value(t, selection.generation, u64(4))

	cleared, _ := buffer_selection_clear_mark(&buffer)
	selection, selected, _ = buffer_selection_snapshot(&buffer)
	testing.expect(t, cleared && selected)
	testing.expect(t, !selection.mark.present && !selection.region_active)
	testing.expect_value(t, selection.generation, u64(5))
}

/* Verifies canonical edits transform the buffer-owned selection anchors. */
@(test)
selection_anchors_follow_committed_text :: proc(t: ^testing.T) {
	buffer := selection_test_buffer(t, Buffer_ID(153), "abcdef")
	if !buffer_is_live(&buffer) {
		return
	}
	defer buffer_close(&buffer)

	point, _, _ := buffer_position(&buffer, Byte_Offset(5))
	mark, _, _ := buffer_position(&buffer, Byte_Offset(3))
	buffer_selection_set_point(&buffer, point)
	buffer_selection_set_mark(&buffer, mark, true)
	start, _, _ := buffer_position(&buffer, Byte_Offset(1))
	end, _, _ := buffer_position(&buffer, Byte_Offset(4))
	_, _, published, _ := buffer_splice(
		&buffer,
		Splice{start = start, end = end, replacement = "X"},
		context.temp_allocator,
	)
	selection, selected, _ := buffer_selection_snapshot(&buffer)
	testing.expect(t, published && selected)
	testing.expect_value(t, selection.point_position.byte_offset, Byte_Offset(3))
	testing.expect_value(t, selection.mark.position.byte_offset, Byte_Offset(1))
	testing.expect(t, selection.region_active)
}

/* Verifies activating a missing mark rejects without changing canonical state. */
@(test)
selection_activation_requires_mark_atomically :: proc(t: ^testing.T) {
	buffer := selection_test_buffer(t, Buffer_ID(154), "abc")
	if !buffer_is_live(&buffer) {
		return
	}
	defer buffer_close(&buffer)

	before, before_ok, _ := buffer_selection_snapshot(&buffer)
	activated, failure := buffer_selection_set_region_active(&buffer, true)
	after, after_ok, _ := buffer_selection_snapshot(&buffer)
	testing.expect(t, before_ok && after_ok && !activated)
	testing.expect_value(t, failure.code, Failure_Code.Missing_Mark)
	testing.expect_value(t, after, before)
}

/* Verifies one canonical point and mark can project a rectangular region shape. */
@(test)
selection_shape_is_canonical_and_resets_on_deactivation :: proc(t: ^testing.T) {
	buffer := selection_test_buffer(t, Buffer_ID(155), "alpha\nbeta\n")
	if !buffer_is_live(&buffer) do return
	defer buffer_close(&buffer)
	point, point_ok, _ := buffer_position(&buffer, 8)
	mark, mark_ok, _ := buffer_position(&buffer, 1)
	testing.expect(t, point_ok && mark_ok)
	marked, mark_failure := buffer_selection_set_mark(
		&buffer, mark, true, .Rectangle, .Grapheme,
	)
	testing.expectf(t, marked, "rectangle mark failed with %v", mark_failure.code)
	moved, move_failure := buffer_selection_set_point(&buffer, point)
	testing.expectf(t, moved, "rectangle point failed with %v", move_failure.code)
	selection, selected, selection_failure := buffer_selection_snapshot(&buffer)
	testing.expectf(t, selected, "rectangle snapshot failed with %v", selection_failure.code)
	testing.expect(t, selection.region_active)
	testing.expect_value(t, selection.shape, Selection_Shape.Rectangle)

	deactivated, deactivate_failure := buffer_selection_set_region_active(&buffer, false)
	testing.expectf(t, deactivated, "rectangle deactivation failed with %v", deactivate_failure.code)
	selection, selected, _ = buffer_selection_snapshot(&buffer)
	testing.expect(t, selected && !selection.region_active)
	testing.expect_value(t, selection.shape, Selection_Shape.Linear)
}

@(private)
selection_test_buffer :: proc(t: ^testing.T, id: Buffer_ID, contents: string) -> Buffer {
	buffer: Buffer
	initialized, failure := buffer_init(
		&buffer,
		id,
		contents,
		Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	testing.expectf(t, initialized, "buffer initialization failed: %v", failure.code)
	return buffer
}
