// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package gutter

import "core:testing"

@(private = "file")
Reference_Side :: enum u8 {
	Left,
	Right,
}

@(private = "file")
Reference_Width_Policy :: enum u8 {
	Fixed,
	Automatic,
	Bounded_Automatic,
	Content_Presence,
}

@(private = "file")
Reference_Lane :: struct {
	id:       u8,
	side:     Reference_Side,
	order:    i16,
	priority: u8,
	policy:   Reference_Width_Policy,
	minimum:  u8,
	maximum:  u8,
	content:  u8,
	present:  bool,
}

@(private = "file")
Reference_Geometry :: struct {
	left:       u16,
	right:      u16,
	text:       u16,
	widths:     [16]u8,
	visible:    [16]bool,
	lane_count: u8,
}

@(private = "file")
reference_lane_width :: proc(lane: Reference_Lane) -> (u8, bool) {
	if lane.id == 0 || lane.minimum > lane.maximum || lane.maximum == 0 {
		return 0, false
	}
	switch lane.policy {
	case .Fixed:
		if lane.minimum != lane.maximum do return 0, false
		return lane.minimum, true
	case .Automatic:
		return max(lane.minimum, lane.content), true
	case .Bounded_Automatic:
		return clamp(lane.content, lane.minimum, lane.maximum), true
	case .Content_Presence:
		if !lane.present || lane.content == 0 do return 0, true
		return clamp(lane.content, lane.minimum, lane.maximum), true
	}
	return 0, false
}

@(private = "file")
reference_compose :: proc(
	lanes: []Reference_Lane,
	available, minimum_text: u16,
) -> (geometry: Reference_Geometry, ok: bool) {
	if len(lanes) > len(geometry.widths) || available < minimum_text {
		return {}, false
	}
	geometry.text = available
	geometry.lane_count = u8(len(lanes))
	for lane, index in lanes {
		width, valid := reference_lane_width(lane)
		if !valid do return {}, false
		for prior in lanes[:index] {
			if prior.id == lane.id do return {}, false
			if prior.side == lane.side && prior.order == lane.order do return {}, false
		}
		geometry.widths[index] = width
		geometry.visible[index] = width > 0
		if lane.side == .Left {
			geometry.left += u16(width)
		} else {
			geometry.right += u16(width)
		}
	}
	reserved := geometry.left + geometry.right
	for reserved + minimum_text > available {
		candidate := -1
		candidate_priority := max(u8)
		candidate_order := min(i16)
		for lane, index in lanes {
			if geometry.widths[index] == 0 do continue
			if candidate < 0 || lane.priority < candidate_priority ||
			   lane.priority == candidate_priority && lane.order > candidate_order {
				candidate = index
				candidate_priority = lane.priority
				candidate_order = lane.order
			}
		}
		if candidate < 0 do return {}, false
		lane := lanes[candidate]
		width := geometry.widths[candidate]
		if width > lane.minimum {
			geometry.widths[candidate] -= 1
			if lane.side == .Left do geometry.left -= 1
			if lane.side == .Right do geometry.right -= 1
			reserved -= 1
			continue
		}
		geometry.widths[candidate] = 0
		geometry.visible[candidate] = false
		if lane.side == .Left do geometry.left -= u16(width)
		if lane.side == .Right do geometry.right -= u16(width)
		reserved -= u16(width)
	}
	geometry.text = available - reserved
	return geometry, true
}

@(test)
/* gutter_reference_model_resolves_both_sides_and_width_policies. */
model_resolves_sides_and_widths :: proc(t: ^testing.T) {
	lanes := []Reference_Lane {
		{id = 1, side = .Left, order = 10, priority = 255, policy = .Fixed,
		 minimum = 4, maximum = 4, present = true},
		{id = 2, side = .Left, order = 20, priority = 100, policy = .Automatic,
		 minimum = 1, maximum = 12, content = 3, present = true},
		{id = 3, side = .Right, order = 10, priority = 50, policy = .Bounded_Automatic,
		 minimum = 1, maximum = 4, content = 9, present = true},
		{id = 4, side = .Right, order = 20, priority = 1, policy = .Content_Presence,
		 minimum = 1, maximum = 2, content = 0},
	}
	geometry, ok := reference_compose(lanes, 40, 8)
	testing.expect(t, ok)
	testing.expect_value(t, geometry.left, u16(7))
	testing.expect_value(t, geometry.right, u16(4))
	testing.expect_value(t, geometry.text, u16(29))
	testing.expect(t, !geometry.visible[3])
}

@(test)
/* gutter_reference_model_contracts_low_priority_lanes_before_text. */
model_contracts_low_priority_lanes :: proc(t: ^testing.T) {
	lanes := []Reference_Lane {
		{id = 1, side = .Left, order = 10, priority = 255, policy = .Fixed,
		 minimum = 4, maximum = 4, present = true},
		{id = 2, side = .Right, order = 10, priority = 1, policy = .Bounded_Automatic,
		 minimum = 1, maximum = 6, content = 6, present = true},
	}
	geometry, ok := reference_compose(lanes, 13, 8)
	testing.expect(t, ok)
	testing.expect_value(t, geometry.widths[0], u8(4))
	testing.expect_value(t, geometry.widths[1], u8(1))
	testing.expect_value(t, geometry.text, u16(8))
}

@(test)
/* gutter_reference_model_is_independent_of_declaration_order. */
model_ignores_declaration_order :: proc(t: ^testing.T) {
	first := []Reference_Lane {
		{id = 1, side = .Left, order = 10, priority = 255, policy = .Fixed,
		 minimum = 3, maximum = 3, present = true},
		{id = 2, side = .Right, order = 20, priority = 1, policy = .Content_Presence,
		 minimum = 1, maximum = 2, content = 2, present = true},
	}
	second := []Reference_Lane{first[1], first[0]}
	left, left_ok := reference_compose(first, 20, 8)
	right, right_ok := reference_compose(second, 20, 8)
	testing.expect(t, left_ok && right_ok)
	testing.expect_value(t, left.left, right.left)
	testing.expect_value(t, left.right, right.right)
	testing.expect_value(t, left.text, right.text)
}

@(test)
/* gutter_reference_model_rejects_ambiguous_or_impossible_geometry. */
model_rejects_impossible_geometry :: proc(t: ^testing.T) {
	duplicate := []Reference_Lane {
		{id = 1, side = .Left, order = 10, priority = 1, policy = .Fixed,
		 minimum = 2, maximum = 2},
		{id = 1, side = .Right, order = 10, priority = 1, policy = .Fixed,
		 minimum = 2, maximum = 2},
	}
	_, duplicate_ok := reference_compose(duplicate, 20, 8)
	testing.expect(t, !duplicate_ok)

	ambiguous := duplicate
	ambiguous[1].id = 2
	ambiguous[1].side = .Left
	_, ambiguous_ok := reference_compose(ambiguous, 20, 8)
	testing.expect(t, !ambiguous_ok)

	_, impossible_ok := reference_compose(duplicate[:1], 7, 8)
	testing.expect(t, !impossible_ok)
}
