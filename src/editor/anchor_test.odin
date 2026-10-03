// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package editor

import "core:testing"

/* Verifies insertion affinity and current-revision resolution for persistent anchors. */
@(test)
anchors_follow_insertions_by_affinity :: proc(t: ^testing.T) {
	buffer: Buffer
	initialized, _ := buffer_init(
		&buffer,
		Buffer_ID(101),
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

	position, position_ok, _ := buffer_position(&buffer, Byte_Offset(1))
	testing.expect(t, position_ok)
	left, left_ok, _ := buffer_anchor_create(&buffer, position, .Left, .Collapse)
	right, right_ok, _ := buffer_anchor_create(&buffer, position, .Right, .Collapse)
	testing.expect(t, left_ok && right_ok)

	_, _, published, _ := buffer_splice(
		&buffer,
		Splice{start = position, end = position, replacement = "XY"},
		context.temp_allocator,
	)
	testing.expect(t, published)
	expect_anchor_offset(t, &buffer, left, Byte_Offset(1), Revision(1))
	expect_anchor_offset(t, &buffer, right, Byte_Offset(3), Revision(1))
}

/* Verifies collapse, invalidation, and boundary movement through replacement. */
@(test)
anchors_apply_deletion_policy_during_publication :: proc(t: ^testing.T) {
	buffer: Buffer
	initialized, _ := buffer_init(
		&buffer,
		Buffer_ID(103),
		"abcdef",
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

	start, _, _ := buffer_position(&buffer, Byte_Offset(1))
	inside, _, _ := buffer_position(&buffer, Byte_Offset(3))
	end, _, _ := buffer_position(&buffer, Byte_Offset(5))
	after, _, _ := buffer_position(&buffer, Byte_Offset(6))
	collapse_left, _, _ := buffer_anchor_create(&buffer, inside, .Left, .Collapse)
	collapse_right, _, _ := buffer_anchor_create(&buffer, inside, .Right, .Collapse)
	invalidate, _, _ := buffer_anchor_create(&buffer, inside, .Left, .Invalidate)
	at_end, _, _ := buffer_anchor_create(&buffer, end, .Left, .Collapse)
	after_edit, _, _ := buffer_anchor_create(&buffer, after, .Left, .Collapse)

	_, _, published, _ := buffer_splice(
		&buffer,
		Splice{start = start, end = end, replacement = "XY"},
		context.temp_allocator,
	)
	testing.expect(t, published)
	expect_anchor_offset(t, &buffer, collapse_left, Byte_Offset(1), Revision(1))
	expect_anchor_offset(t, &buffer, collapse_right, Byte_Offset(3), Revision(1))
	expect_anchor_offset(t, &buffer, at_end, Byte_Offset(3), Revision(1))
	expect_anchor_offset(t, &buffer, after_edit, Byte_Offset(4), Revision(1))
	_, invalid_ok, invalid_failure := buffer_anchor_resolve(&buffer, invalidate)
	testing.expect(t, !invalid_ok)
	testing.expect_value(t, invalid_failure.code, Failure_Code.Invalid_Anchor)
}

/* Verifies checked generations, explicit release, capacity, and close invalidation. */
@(test)
handles_reject_stale_wrong_and_closed_owners :: proc(t: ^testing.T) {
	limits := DEFAULT_LIMITS
	limits.anchors = 2
	buffer: Buffer
	initialized, _ := buffer_init(
		&buffer,
		Buffer_ID(105),
		"abc",
		Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
		limits,
	)
	testing.expect(t, initialized)
	if !initialized {
		return
	}

	position, _, _ := buffer_position(&buffer, Byte_Offset(1))
	anchor, created, _ := buffer_anchor_create(&buffer, position, .Right, .Collapse)
	testing.expect(t, created)
	_, capacity_ok, capacity_failure := buffer_anchor_create(
		&buffer,
		position,
		.Left,
		.Collapse,
	)
	testing.expect(t, !capacity_ok)
	testing.expect_value(t, capacity_failure.code, Failure_Code.Anchor_Limit)

	stale_copy := anchor
	released, _ := buffer_anchor_release(&buffer, &anchor)
	testing.expect(t, released)
	testing.expect_value(t, anchor, Anchor{})
	_, stale_ok, stale_failure := buffer_anchor_resolve(&buffer, stale_copy)
	testing.expect(t, !stale_ok)
	testing.expect_value(t, stale_failure.code, Failure_Code.Invalid_Anchor)

	replacement, replacement_ok, _ := buffer_anchor_create(
		&buffer,
		position,
		.Right,
		.Collapse,
	)
	testing.expect(t, replacement_ok)
	testing.expect(t, replacement.generation != stale_copy.generation)

	wrong := replacement
	wrong.buffer_id = Buffer_ID(999)
	_, wrong_ok, wrong_failure := buffer_anchor_resolve(&buffer, wrong)
	testing.expect(t, !wrong_ok)
	testing.expect_value(t, wrong_failure.code, Failure_Code.Wrong_Buffer)

	closed, _ := buffer_close(&buffer)
	testing.expect(t, closed)
	_, closed_ok, closed_failure := buffer_anchor_resolve(&buffer, replacement)
	testing.expect(t, !closed_ok)
	testing.expect_value(t, closed_failure.code, Failure_Code.Closed_Buffer)
}

/* Verifies that creation rejects unchecked offsets and stale revisions. */
@(test)
anchor_creation_requires_a_current_utf8_boundary :: proc(t: ^testing.T) {
	buffer: Buffer
	initialized, _ := buffer_init(
		&buffer,
		Buffer_ID(107),
		"a🙂b",
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

	middle, _ := position_make(Buffer_ID(107), Revision(0), Byte_Offset(2))
	_, middle_ok, middle_failure := buffer_anchor_create(&buffer, middle, .Left, .Collapse)
	testing.expect(t, !middle_ok)
	testing.expect_value(t, middle_failure.code, Failure_Code.Mid_Encoding_Offset)

	stale, _ := position_make(Buffer_ID(107), Revision(1), Byte_Offset(1))
	_, stale_ok, stale_failure := buffer_anchor_create(&buffer, stale, .Left, .Collapse)
	testing.expect(t, !stale_ok)
	testing.expect_value(t, stale_failure.code, Failure_Code.Stale_Revision)
}

@(private)
expect_anchor_offset :: proc(
	t: ^testing.T,
	buffer: ^Buffer,
	anchor: Anchor,
	expected_offset: Byte_Offset,
	expected_revision: Revision,
) {
	position, ok, failure := buffer_anchor_resolve(buffer, anchor)
	testing.expectf(t, ok, "anchor resolution failed with %v", failure.code)
	if !ok {
		return
	}
	testing.expect_value(t, position.byte_offset, expected_offset)
	testing.expect_value(t, position.revision, expected_revision)
}
