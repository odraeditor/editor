// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package gutter

@(private = "file")
Resolved_Lane :: struct {
	definition: Lane_Definition,
	width:      u16,
	visible:    bool,
}

/* compose_geometry resolves bounded left and right lanes before text projection. */
compose_geometry :: proc(request: Geometry_Request) -> (Geometry, bool, Failure_Context) {
	if !geometry_request_is_valid(request) {
		return {}, false, Failure_Context{operation = .Compose_Geometry, code = .Invalid_Request}
	}
	if len(request.lanes) > int(request.limits.lanes) {
		return {}, false, Failure_Context {
			operation = .Compose_Geometry,
			code = .Lane_Limit,
			limit = u64(request.limits.lanes),
			actual = u64(len(request.lanes)),
		}
	}

	resolved: [MAX_LANES]Resolved_Lane
	left_count, right_count: u8
	work: u32
	for lane, index in request.lanes {
		if !lane_definition_is_valid(lane, request.limits) {
			return {}, false, lane_geometry_failure(.Invalid_Lane, lane)
		}
		for prior in request.lanes[:index] {
			work += 1
			if work > request.limits.work {
				return {}, false, geometry_limit_failure(.Work_Limit, request.limits.work, work)
			}
			if prior.id == lane.id {
				return {}, false, lane_geometry_failure(.Duplicate_Lane, lane)
			}
			if prior.side == lane.side && prior.order == lane.order {
				return {}, false, lane_geometry_failure(.Ambiguous_Order, lane)
			}
		}
		if lane.side == .Left do left_count += 1
		if lane.side == .Right do right_count += 1
		if left_count > request.limits.lanes_per_side ||
		   right_count > request.limits.lanes_per_side {
			return {}, false, Failure_Context {
				operation = .Compose_Geometry,
				code = .Side_Limit,
				lane = lane.id,
				limit = u64(request.limits.lanes_per_side),
				actual = u64(max(left_count, right_count)),
			}
		}
		observation, observed := lane_content_find(request.content, lane.id)
		if !observed {
			return {}, false, lane_geometry_failure(.Invalid_Request, lane)
		}
		width, visible, width_ok := lane_resolve_width(lane, observation)
		if !width_ok {
			return {}, false, lane_geometry_failure(.Invalid_Lane, lane)
		}
		resolved[index] = Resolved_Lane{definition = lane, width = width, visible = visible}
	}
	if len(request.content) != len(request.lanes) {
		return {}, false, Failure_Context{operation = .Compose_Geometry, code = .Invalid_Request}
	}

	reserved := geometry_reserved_cells(resolved[:len(request.lanes)])
	for u64(reserved) + u64(request.minimum_text_cells) > u64(request.available_cells) {
		candidate := geometry_contraction_candidate(resolved[:len(request.lanes)], &work)
		if work > request.limits.work {
			return {}, false, geometry_limit_failure(.Work_Limit, request.limits.work, work)
		}
		if candidate < 0 {
			return {}, false, geometry_limit_failure(
				.Width_Insufficient,
				request.available_cells,
				reserved + request.minimum_text_cells,
			)
		}
		entry := &resolved[candidate]
		if entry.width > entry.definition.minimum_cells {
			entry.width -= 1
		} else {
			entry.width = 0
			entry.visible = false
		}
		reserved = geometry_reserved_cells(resolved[:len(request.lanes)])
	}

	return geometry_materialize(request, resolved[:len(request.lanes)], work)
}

@(private = "file")
geometry_request_is_valid :: proc(request: Geometry_Request) -> bool {
	return limits_are_valid(request.limits) && request.available_cells > 0 &&
		request.minimum_text_cells >= MIN_TEXT_CELLS &&
		request.minimum_text_cells <= request.available_cells &&
		len(request.lanes) > 0 && len(request.lanes) <= MAX_LANES
}

@(private = "file")
lane_content_find :: proc(
	observations: []Lane_Content_Observation,
	lane: Lane_ID,
) -> (Lane_Content_Observation, bool) {
	found: Lane_Content_Observation
	seen := false
	for observation in observations {
		if observation.lane != lane do continue
		if seen do return {}, false
		found = observation
		seen = true
	}
	return found, seen
}

@(private = "file")
lane_resolve_width :: proc(
	lane: Lane_Definition,
	observation: Lane_Content_Observation,
) -> (width: u16, visible: bool, ok: bool) {
	present := observation.present
	if lane.visibility == .When_Content && observation.content_cells == 0 do present = false
	if lane.visibility == .Configured && !observation.present do present = false
	if lane.width_policy == .Content_Presence && observation.content_cells == 0 do present = false
	if !present do return 0, false, true

	switch lane.width_policy {
	case .Fixed:
		width = lane.minimum_cells
	case .Automatic:
		if observation.content_cells > lane.maximum_cells do return 0, false, false
		width = max(lane.minimum_cells, observation.content_cells)
	case .Bounded_Automatic, .Content_Presence:
		width = clamp(observation.content_cells, lane.minimum_cells, lane.maximum_cells)
	case .Invalid:
		return 0, false, false
	}
	return width, width > 0, true
}

@(private = "file")
geometry_reserved_cells :: proc(lanes: []Resolved_Lane) -> u32 {
	reserved: u32
	for lane in lanes {
		if lane.visible do reserved += u32(lane.width)
	}
	return reserved
}

@(private = "file")
geometry_contraction_candidate :: proc(lanes: []Resolved_Lane, work: ^u32) -> int {
	candidate := -1
	priority := max(u16)
	order := min(i16)
	for lane, index in lanes {
		work^ += 1
		if !lane.visible do continue
		if candidate < 0 || lane.definition.priority < priority ||
		   lane.definition.priority == priority && lane.definition.order > order {
			candidate = index
			priority = lane.definition.priority
			order = lane.definition.order
		}
	}
	return candidate
}

@(private = "file")
geometry_materialize :: proc(
	request: Geometry_Request,
	resolved: []Resolved_Lane,
	work: u32,
) -> (Geometry, bool, Failure_Context) {
	geometry := Geometry {
		available_cells = request.available_cells,
		text_cells = request.available_cells - geometry_reserved_cells(resolved),
	}
	for side in Side.Left ..= Side.Right {
		for _ in 0 ..< len(resolved) {
			candidate := -1
			candidate_order := max(i16)
			for lane, index in resolved {
				if lane.definition.side != side || geometry_lane_present(&geometry, lane.definition.id) {
					continue
				}
				if candidate < 0 || lane.definition.order < candidate_order {
					candidate = index
					candidate_order = lane.definition.order
				}
			}
			if candidate < 0 do break
			lane := resolved[candidate]
			entry := &geometry.lanes[geometry.lane_count]
			entry^ = Lane_Geometry {
				lane = lane.definition.id,
				side = side,
				order = lane.definition.order,
				width_cells = lane.width,
				visible = lane.visible,
				style_role = lane.definition.style_role,
			}
			if side == .Left {
				entry.start_cell = geometry.left_cells
				if lane.visible do geometry.left_cells += lane.width
			} else {
				entry.start_cell = geometry.right_cells
				if lane.visible do geometry.right_cells += lane.width
			}
			geometry.lane_count += 1
		}
	}
	_ = work
	return geometry, true, {}
}

@(private = "file")
geometry_lane_present :: proc(geometry: ^Geometry, lane: Lane_ID) -> bool {
	if geometry == nil do return false
	for entry in geometry.lanes[:geometry.lane_count] {
		if entry.lane == lane do return true
	}
	return false
}

@(private = "file")
lane_geometry_failure :: proc(code: Failure_Code, lane: Lane_Definition) -> Failure_Context {
	return Failure_Context{operation = .Compose_Geometry, code = code, lane = lane.id}
}

@(private = "file")
geometry_limit_failure :: proc(code: Failure_Code, limit, actual: $T) -> Failure_Context {
	return Failure_Context {
		operation = .Compose_Geometry,
		code = code,
		limit = u64(limit),
		actual = u64(actual),
	}
}
