// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package gutter

import "base:runtime"
import "core:fmt"
import "core:unicode/utf8"

/* Resolved_Marker is one deterministic lane result with inspectable membership. */
Resolved_Marker :: struct {
	viewport_row: u32,
	logical_line: u64,
	lane:         Lane_ID,
	primary:      Marker_ID,
	primary_provider: Provider_ID,
	members:      [MAX_COLLISION_MEMBERS]Marker_ID,
	member_providers: [MAX_COLLISION_MEMBERS]Provider_ID,
	member_count: u8,
	text:         [MAX_ROW_TEXT_BYTES]u8,
	text_length:  u16,
	style_role:   Semantic_Role,
	actions:      [MAX_ACTIONS_PER_MARKER]Command_Reference,
	action_count: u8,
	stale:        bool,
}

/* Resolved_Marker_View owns one bounded visible collision composition. */
Resolved_Marker_View :: struct {
	generation:     Generation,
	markers:        [dynamic]Resolved_Marker,
	work:           u32,
	retained_bytes: u64,
	allocator:      runtime.Allocator,
}

/* Marker_Composition_Request borrows exact lanes, publications, and view coordinates. */
Marker_Composition_Request :: struct {
	generation:            Generation,
	lanes:                 []Lane_Definition,
	publications:          []Marker_Generation_View,
	rows:                  []Visible_Row,
	buffer_revision:       u64,
	view_identity:         u64,
	view_generation:       u32,
	projection_generation: u64,
	allocator:             runtime.Allocator,
	limits:                Limits,
}

/* compose_markers resolves every visible lane coordinate deterministically. */
compose_markers :: proc(
	request: Marker_Composition_Request,
) -> (Resolved_Marker_View, bool, Failure_Context) {
	if request.generation == 0 || request.allocator.procedure == nil ||
	   !limits_are_valid(request.limits) ||
	   len(request.lanes) == 0 || len(request.lanes) > int(request.limits.lanes) ||
	   len(request.rows) > int(request.limits.visible_rows) {
		return {}, false, Failure_Context{operation = .Project, code = .Invalid_Request}
	}
	for publication in request.publications {
		if !publication.complete {
			return {}, false, Failure_Context{operation = .Project, code = .Incomplete_Generation}
		}
	}
	capacity := min(
		int(request.limits.markers_per_generation),
		len(request.rows) * len(request.lanes),
	)
	view := Resolved_Marker_View{generation = request.generation, allocator = request.allocator}
	allocation_error: runtime.Allocator_Error
	view.markers, allocation_error = make([dynamic]Resolved_Marker, 0, capacity, request.allocator)
	if allocation_error != nil {
		return {}, false, Failure_Context{operation = .Project, code = .Allocation}
	}
	defer if view.allocator.procedure != nil do resolved_marker_view_close(&view)
	work: u32
	for row in request.rows {
		for lane in request.lanes {
			if !lane_definition_is_valid(lane, request.limits) do return {}, false, marker_lane_failure(lane)
			members: [MAX_COLLISION_MEMBERS]^Marker
			member_count := 0
			for publication in request.publications {
				if publication.provider != lane.provider ||
				   publication.provider_generation != lane.provider_generation {
					continue
				}
				for &marker in publication.markers {
					work += 1
					if work > request.limits.work {
						return {}, false, Failure_Context {
							operation = .Project, code = .Work_Limit,
							limit = u64(request.limits.work), actual = u64(work),
						}
					}
					if marker.lane != lane.id || !marker_matches_row(marker, lane, row, request) {
						continue
					}
					if member_count >= MAX_COLLISION_MEMBERS {
						return {}, false, Failure_Context {
							operation = .Project, code = .Collision_Limit, lane = lane.id,
							limit = MAX_COLLISION_MEMBERS, actual = u64(member_count + 1),
						}
					}
					members[member_count] = &marker
					member_count += 1
				}
			}
			if member_count == 0 do continue
			marker_sort(members[:member_count])
			resolved := resolve_collision(lane, row, members[:member_count])
			if _, append_error := append(&view.markers, resolved); append_error != nil {
				return {}, false, Failure_Context{operation = .Project, code = .Allocation}
			}
		}
	}
	view.work = work
	view.retained_bytes = u64(cap(view.markers)) * u64(size_of(Resolved_Marker))
	result := view
	view = {}
	return result, true, {}
}

/* resolved_marker_text borrows one composed representation. */
resolved_marker_text :: proc(marker: ^Resolved_Marker) -> string {
	if marker == nil || marker.text_length == 0 do return ""
	return string(marker.text[:marker.text_length])
}

/* resolved_marker_view_close releases one composition exactly once. */
resolved_marker_view_close :: proc(view: ^Resolved_Marker_View) -> (bool, Failure_Context) {
	if view == nil || view.allocator.procedure == nil {
		return false, Failure_Context{operation = .Close, code = .Closed_View}
	}
	if view.markers != nil do delete(view.markers)
	view^ = {}
	return true, {}
}

@(private = "file")
marker_matches_row :: proc(
	marker: Marker,
	lane: Lane_Definition,
	row: Visible_Row,
	request: Marker_Composition_Request,
) -> bool {
	if (marker.attachment.buffer_revision != request.buffer_revision &&
	    !(marker.provider == PROGRAMMABLE_PROVIDER_ID && marker.attachment.buffer_revision == 0)) ||
	   marker.attachment.kind not_in lane.attachments {
		return false
	}
	switch marker.attachment.kind {
	case .Logical_Line:
		return marker.attachment.logical_line == row.logical_line
	case .Display_Row:
		return marker.attachment.display_row == row.viewport_row &&
			marker.attachment.view_identity == request.view_identity &&
			marker.attachment.view_generation == request.view_generation &&
			marker.attachment.projection_generation == request.projection_generation
	}
	return false
}

@(private = "file")
marker_sort :: proc(markers: []^Marker) {
	for index in 1 ..< len(markers) {
		cursor := index
		for cursor > 0 && marker_precedes(markers[cursor], markers[cursor - 1]) {
			markers[cursor], markers[cursor - 1] = markers[cursor - 1], markers[cursor]
			cursor -= 1
		}
	}
}

@(private = "file")
marker_precedes :: proc(left, right: ^Marker) -> bool {
	return left.priority > right.priority ||
		(left.priority == right.priority && left.id < right.id)
}

@(private = "file")
resolve_collision :: proc(
	lane: Lane_Definition,
	row: Visible_Row,
	members: []^Marker,
) -> Resolved_Marker {
	primary := members[0]
	result := Resolved_Marker {
		viewport_row = row.viewport_row,
		logical_line = row.logical_line,
		lane = lane.id,
		primary = primary.id,
		primary_provider = primary.provider,
		member_count = u8(len(members)),
		style_role = primary.style_role,
		actions = primary.actions,
		action_count = primary.action_count,
		stale = primary.stale,
	}
	for member, index in members {
		result.members[index] = member.id
		result.member_providers[index] = member.provider
	}
	if primary.stale do result.style_role = .Stale
	switch lane.collision {
	case .Highest_Priority, .Primary_With_Details:
		resolved_marker_append(&result, primary.representation.value, lane.maximum_cells)
	case .Stack:
		for member in members {
			resolved_marker_append(&result, member.representation.value, lane.maximum_cells)
		}
	case .Aggregate:
		if len(members) == 1 {
			resolved_marker_append(&result, primary.representation.value, lane.maximum_cells)
		} else {
			result.style_role = .Aggregate
			if len(primary.aggregation_label) > 0 {
				resolved_marker_append(&result, primary.aggregation_label, lane.maximum_cells)
			} else {
				storage: [24]u8
				label := fmt.bprintf(storage[:], "+%d", len(members))
				resolved_marker_append(&result, label, lane.maximum_cells)
			}
		}
	case .Invalid:
	}
	return result
}

@(private = "file")
resolved_marker_append :: proc(result: ^Resolved_Marker, value: string, maximum_cells: u16) {
	if result == nil || len(value) == 0 do return
	used_cells := utf8.rune_count(string(result.text[:result.text_length]))
	if used_cells + utf8.rune_count(value) > int(maximum_cells) do return
	available := len(result.text) - int(result.text_length)
	if len(value) > available do return
	copy(result.text[result.text_length:int(result.text_length) + len(value)], transmute([]u8)value)
	result.text_length += u16(len(value))
}

@(private = "file")
marker_lane_failure :: proc(lane: Lane_Definition) -> Failure_Context {
	return Failure_Context{operation = .Project, code = .Invalid_Lane, lane = lane.id}
}
