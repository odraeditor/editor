// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../gutter"

@(private)
MAX_GUTTER_INSPECTION_DETAIL_BYTES :: 1_024

@(private)
Gutter_Inspection_Marker :: struct {
	id:            gutter.Marker_ID,
	provider:      gutter.Provider_ID,
	provider_generation: gutter.Provider_Generation,
	lane:          gutter.Lane_ID,
	role:          gutter.Semantic_Role,
	detail:        [MAX_GUTTER_INSPECTION_DETAIL_BYTES]u8,
	detail_length: u16,
	action:        gutter.Command_Reference,
	actionable:    bool,
	stale:         bool,
}

@(private)
Gutter_Inspection_State :: struct {
	available:        bool,
	buffer_revision:  u64,
	view_identity:    u64,
	view_generation:  u32,
	logical_line:     u64,
	cursor_offset:    u64,
	projection:       u64,
	markers:          [gutter.MAX_COLLISION_MEMBERS]Gutter_Inspection_Marker,
	marker_count:     u8,
	next_index:       u8,
	popup_open:       bool,
	popup_marker:     gutter.Marker_ID,
	popup_index:      u8,
	popup_generation: u64,
}

@(private)
gutter_inspection_reset :: proc(state: ^Gutter_Inspection_State) {
	if state == nil do return
	state.available = false
	state.marker_count = 0
}

@(private)
gutter_inspection_begin_frame :: proc(
	state: ^Gutter_Inspection_State,
	preserve_editor_snapshot: bool,
) {
	if preserve_editor_snapshot do return
	gutter_inspection_reset(state)
}

@(private)
gutter_inspection_observe :: proc(
	state: ^Gutter_Inspection_State,
	resolved: ^gutter.Resolved_Marker_View,
	publications: []gutter.Marker_Generation_View,
	buffer_revision: u64,
	view_identity: u64,
	view_generation: u32,
	projection: u64,
	logical_line: u64,
	cursor_offset: u64 = 0,
) {
	if state == nil || resolved == nil || resolved.allocator.procedure == nil do return
	same_location := state.buffer_revision == buffer_revision && state.view_identity == view_identity &&
		state.view_generation == view_generation && state.logical_line == logical_line &&
		state.cursor_offset == cursor_offset
	previous_next := state.next_index if same_location else 0
	popup_open := state.popup_open && same_location
	popup_marker := state.popup_marker
	popup_generation := state.popup_generation
	state^ = Gutter_Inspection_State {
		buffer_revision = buffer_revision,
		view_identity = view_identity,
		view_generation = view_generation,
		logical_line = logical_line,
		cursor_offset = cursor_offset,
		projection = projection,
		popup_open = popup_open,
		popup_marker = popup_marker,
		popup_generation = popup_generation,
	}
	for composed in resolved.markers {
		if composed.logical_line != logical_line do continue
		for member_index in 0 ..< int(composed.member_count) {
			if state.marker_count >= gutter.MAX_COLLISION_MEMBERS do break
			marker, found := gutter_inspection_find_marker(
				publications,
				composed.member_providers[member_index],
				composed.members[member_index],
			)
			if !found do continue
			entry := &state.markers[state.marker_count]
			entry.id = marker.id
			entry.provider = marker.provider
			entry.provider_generation = marker.provider_generation
			entry.lane = marker.lane
			entry.role = marker.style_role
			entry.detail_length = u16(min(len(marker.detail), len(entry.detail)))
			copy(entry.detail[:entry.detail_length], transmute([]u8)marker.detail[:entry.detail_length])
			if marker.action_count > 0 {
				entry.action = marker.actions[0]
				entry.actionable = entry.action.registry_generation != 0
			}
			entry.stale = marker.stale
			state.marker_count += 1
		}
	}
	state.available = state.marker_count > 0
	if state.available do state.next_index = previous_next % state.marker_count
	if state.popup_open {
		found := false
		for marker, index in state.markers[:state.marker_count] {
			if marker.id != state.popup_marker do continue
			state.popup_index = u8(index)
			found = true
			break
		}
		if !found do gutter_inspection_popup_dismiss(state)
	}
}

@(private)
gutter_inspection_find_marker :: proc(
	publications: []gutter.Marker_Generation_View,
	provider: gutter.Provider_ID,
	id: gutter.Marker_ID,
) -> (gutter.Marker, bool) {
	for publication in publications {
		if publication.provider != provider do continue
		for marker in publication.markers {
			if marker.id == id do return marker, true
		}
	}
	return {}, false
}

@(private)
gutter_inspection_current :: proc(
	state: ^Gutter_Inspection_State,
) -> (^Gutter_Inspection_Marker, u8, bool) {
	if state == nil || !state.available || state.marker_count == 0 do return nil, 0, false
	index := state.next_index % state.marker_count
	return &state.markers[index], index, true
}

@(private)
gutter_inspection_popup_open :: proc(
	state: ^Gutter_Inspection_State,
	marker: ^Gutter_Inspection_Marker,
	index: u8,
) -> bool {
	if state == nil || marker == nil || !state.available || index >= state.marker_count ||
	   state.popup_generation == max(u64) {
		return false
	}
	state.popup_open = true
	state.popup_marker = marker.id
	state.popup_index = index
	state.popup_generation += 1
	return true
}

@(private)
gutter_inspection_popup_dismiss :: proc(state: ^Gutter_Inspection_State) {
	if state == nil do return
	state.popup_open = false
	state.popup_marker = 0
	state.popup_index = 0
}
