// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package status_bar

import "core:testing"

@(private = "file")
Reference_Group :: enum u8 {
	Left,
	Right,
}

@(private = "file")
Reference_Segment :: struct {
	group:         Reference_Group,
	priority:      u8,
	full:          string,
	compact:       string,
	required:      bool,
	truncatable:   bool,
}

@(private = "file")
reference_segment_text :: proc(segment: Reference_Segment, compact: bool) -> string {
	if compact && len(segment.compact) > 0 do return segment.compact
	return segment.full
}

@(private = "file")
reference_group_width :: proc(
	segments: []Reference_Segment,
	compact: []bool,
	omitted: []bool,
	group: Reference_Group,
) -> int {
	width := 0
	visible := 0
	for segment, index in segments {
		if segment.group != group || omitted[index] do continue
		if visible > 0 do width += 1
		width += len(reference_segment_text(segment, compact[index]))
		visible += 1
	}
	return width
}

@(private = "file")
reference_status_width :: proc(
	segments: []Reference_Segment,
	compact: []bool,
	omitted: []bool,
) -> int {
	left := reference_group_width(segments, compact, omitted, .Left)
	right := reference_group_width(segments, compact, omitted, .Right)
	if left > 0 && right > 0 do return left + 1 + right
	return left + right
}

@(private = "file")
reference_status_fit :: proc(
	segments: []Reference_Segment,
	width: int,
	compact: []bool,
	omitted: []bool,
) -> bool {
	if len(compact) != len(segments) || len(omitted) != len(segments) || width <= 0 {
		return false
	}
	for reference_status_width(segments, compact, omitted) > width {
		changed := false
		for priority in 0 ..< 255 {
			for segment, index in segments {
				if omitted[index] || segment.priority != u8(priority) do continue
				if !compact[index] && len(segment.compact) > 0 &&
				   len(segment.compact) < len(segment.full) {
					compact[index] = true
					changed = true
					break
				}
				if !segment.required {
					omitted[index] = true
					changed = true
					break
				}
			}
			if changed do break
		}
		if !changed do return false
	}
	return true
}

@(test)
/* Verifies the independent model compacts low-priority status before required identity. */
status_model_preserves_required_information :: proc(t: ^testing.T) {
	segments := []Reference_Segment {
		{group = .Left, priority = 255, full = "--", required = true},
		{group = .Left, priority = 254, full = "main.odin", required = true, truncatable = true},
		{group = .Right, priority = 1, full = "UTF-8 LF", compact = "UTF-8"},
		{group = .Right, priority = 253, full = "23% (418,17)", compact = "23%", required = true},
	}
	compact: [4]bool
	omitted: [4]bool
	ordinary := reference_status_fit(segments, 40, compact[:], omitted[:])
	testing.expect(t, ordinary)
	testing.expect_value(t, reference_status_width(segments, compact[:], omitted[:]), 34)

	compact = {}
	omitted = {}
	narrow := reference_status_fit(segments, 20, compact[:], omitted[:])
	testing.expect(t, narrow)
	testing.expect(t, compact[2] && compact[3])
	testing.expect(t, omitted[2])
	testing.expect(t, !omitted[0] && !omitted[1] && !omitted[3])
	testing.expect_value(t, reference_status_width(segments, compact[:], omitted[:]), 16)
}

@(test)
/* Verifies the independent model rejects widths that cannot retain required segments. */
status_reference_model_rejects_impossible_width :: proc(t: ^testing.T) {
	segments := []Reference_Segment {
		{group = .Left, priority = 255, full = "--", required = true},
		{group = .Left, priority = 254, full = "buffer", required = true, truncatable = true},
		{group = .Right, priority = 253, full = "100%", required = true},
	}
	compact: [3]bool
	omitted: [3]bool
	testing.expect(t, !reference_status_fit(segments, 8, compact[:], omitted[:]))
}
