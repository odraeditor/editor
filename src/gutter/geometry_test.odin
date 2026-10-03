// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package gutter

import "core:testing"

@(private = "file")
geometry_test_lane :: proc(
	id: u64,
	side: Side,
	order: i16,
	priority: u16,
	policy: Width_Policy,
	minimum, maximum: u16,
) -> Lane_Definition {
	return Lane_Definition {
		id = Lane_ID(id),
		provider = 1,
		provider_generation = 1,
		side = side,
		order = order,
		attachments = {.Logical_Line},
		width_policy = policy,
		minimum_cells = minimum,
		maximum_cells = maximum,
		alignment = .Right,
		visibility = .Always,
		collision = .Highest_Priority,
		priority = priority,
		style_role = .Line_Number,
	}
}

@(private = "file")
geometry_test_request :: proc(
	lanes: []Lane_Definition,
	content: []Lane_Content_Observation,
	available := u32(40),
) -> Geometry_Request {
	return Geometry_Request {
		available_cells = available,
		minimum_text_cells = MIN_TEXT_CELLS,
		lanes = lanes,
		content = content,
		limits = DEFAULT_LIMITS,
	}
}

@(test)
/* gutter_geometry_matches_independent_reference_model. */
geometry_matches_independent_reference_model :: proc(t: ^testing.T) {
	lanes := [4]Lane_Definition {
		geometry_test_lane(1, .Left, 10, 255, .Fixed, 4, 4),
		geometry_test_lane(2, .Left, 20, 100, .Automatic, 1, 12),
		geometry_test_lane(3, .Right, 10, 50, .Bounded_Automatic, 1, 4),
		geometry_test_lane(4, .Right, 20, 1, .Content_Presence, 1, 2),
	}
	content := [4]Lane_Content_Observation {
		{lane = 1, content_cells = 4, present = true},
		{lane = 2, content_cells = 3, present = true},
		{lane = 3, content_cells = 9, present = true},
		{lane = 4},
	}
	geometry, ok, failure := compose_geometry(geometry_test_request(lanes[:], content[:]))
	testing.expectf(t, ok, "geometry failed with %v", failure.code)
	testing.expect_value(t, geometry.left_cells, u16(7))
	testing.expect_value(t, geometry.right_cells, u16(4))
	testing.expect_value(t, geometry.text_cells, u32(29))
	testing.expect_value(t, geometry.lanes[0].lane, Lane_ID(1))
	testing.expect_value(t, geometry.lanes[1].lane, Lane_ID(2))
	testing.expect_value(t, geometry.lanes[2].lane, Lane_ID(3))
	testing.expect(t, !geometry.lanes[3].visible)
}

@(test)
/* Priority contraction preserves the minimum text area. */
geometry_preserves_minimum_text :: proc(t: ^testing.T) {
	lanes := [2]Lane_Definition {
		geometry_test_lane(1, .Left, 10, 255, .Fixed, 4, 4),
		geometry_test_lane(2, .Right, 10, 1, .Bounded_Automatic, 1, 6),
	}
	content := [2]Lane_Content_Observation {
		{lane = 1, content_cells = 4, present = true},
		{lane = 2, content_cells = 6, present = true},
	}
	geometry, ok, _ := compose_geometry(geometry_test_request(lanes[:], content[:], 13))
	testing.expect(t, ok)
	testing.expect_value(t, geometry.left_cells, u16(4))
	testing.expect_value(t, geometry.right_cells, u16(1))
	testing.expect_value(t, geometry.text_cells, MIN_TEXT_CELLS)
}

@(test)
/* gutter_geometry_orders_lanes_without_publication_timing. */
geometry_orders_lanes_without_publication_timing :: proc(t: ^testing.T) {
	lanes := [3]Lane_Definition {
		geometry_test_lane(3, .Right, 20, 1, .Fixed, 1, 1),
		geometry_test_lane(2, .Left, 20, 1, .Fixed, 1, 1),
		geometry_test_lane(1, .Left, 10, 1, .Fixed, 1, 1),
	}
	content := [3]Lane_Content_Observation {
		{lane = 2, content_cells = 1, present = true},
		{lane = 1, content_cells = 1, present = true},
		{lane = 3, content_cells = 1, present = true},
	}
	geometry, ok, _ := compose_geometry(geometry_test_request(lanes[:], content[:]))
	testing.expect(t, ok)
	testing.expect_value(t, geometry.lanes[0].lane, Lane_ID(1))
	testing.expect_value(t, geometry.lanes[1].lane, Lane_ID(2))
	testing.expect_value(t, geometry.lanes[2].lane, Lane_ID(3))
}

@(test)
/* Geometry rejects invalid lane identities and observations. */
geometry_rejects_invalid_identity_and_order :: proc(t: ^testing.T) {
	lanes := [2]Lane_Definition {
		geometry_test_lane(1, .Left, 10, 1, .Fixed, 1, 1),
		geometry_test_lane(1, .Right, 10, 1, .Fixed, 1, 1),
	}
	content := [2]Lane_Content_Observation {
		{lane = 1, content_cells = 1, present = true},
		{lane = 2, content_cells = 1, present = true},
	}
	_, duplicate_ok, duplicate := compose_geometry(geometry_test_request(lanes[:], content[:1]))
	testing.expect(t, !duplicate_ok)
	testing.expect_value(t, duplicate.code, Failure_Code.Duplicate_Lane)

	lanes[1].id = 2
	lanes[1].side = .Left
	_, order_ok, order_failure := compose_geometry(geometry_test_request(lanes[:], content[:]))
	testing.expect(t, !order_ok)
	testing.expect_value(t, order_failure.code, Failure_Code.Ambiguous_Order)
}

@(test)
/* gutter_geometry_reports_work_and_side_limits. */
gutter_geometry_reports_work_and_side_limits :: proc(t: ^testing.T) {
	lanes: [MAX_LANES_PER_SIDE + 1]Lane_Definition
	content: [MAX_LANES_PER_SIDE + 1]Lane_Content_Observation
	for index in 0 ..< len(lanes) {
		lanes[index] = geometry_test_lane(u64(index + 1), .Left, i16(index), 1, .Fixed, 1, 1)
		content[index] = {lane = Lane_ID(index + 1), content_cells = 1, present = true}
	}
	_, ok, failure := compose_geometry(geometry_test_request(lanes[:], content[:]))
	testing.expect(t, !ok)
	testing.expect_value(t, failure.code, Failure_Code.Side_Limit)
}
