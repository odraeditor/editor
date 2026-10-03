// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../gutter"

@(private)
Gutter_Popup_Content :: struct {
	generation:          u64,
	marker_id:           gutter.Marker_ID,
	provider:            gutter.Provider_ID,
	provider_generation: gutter.Provider_Generation,
	lane:                gutter.Lane_ID,
	role:                gutter.Semantic_Role,
	collision_index:     u8,
	collision_count:     u8,
	stale:               bool,
	actionable:          bool,
	action:              gutter.Command_Reference,
	detail:              [MAX_GUTTER_INSPECTION_DETAIL_BYTES]u8,
	detail_length:       u16,
}

@(private)
gutter_popup_content_project :: proc(
	state: ^Gutter_Inspection_State,
	generation: u64,
) -> (content: Gutter_Popup_Content, ok: bool) {
	marker, index, available := gutter_inspection_current(state)
	if state != nil && state.popup_open && state.popup_index < state.marker_count {
		index = state.popup_index
		marker = &state.markers[index]
		available = true
	}
	if !available || generation == 0 || marker.provider == gutter.Provider_ID(0) ||
	   marker.provider_generation == gutter.Provider_Generation(0) ||
	   marker.lane == gutter.Lane_ID(0) || marker.detail_length == 0 {
		return {}, false
	}
	content.generation = generation
	content.marker_id = marker.id
	content.provider = marker.provider
	content.provider_generation = marker.provider_generation
	content.lane = marker.lane
	content.role = marker.role
	content.collision_index = index
	content.collision_count = state.marker_count
	content.stale = marker.stale
	content.actionable = marker.actionable
	content.action = marker.action
	content.detail_length = marker.detail_length
	copy(content.detail[:content.detail_length], marker.detail[:marker.detail_length])
	return content, true
}
