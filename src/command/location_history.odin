// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../editor"

/* MAX_LOCATION_HISTORY_ENTRIES bounds session-local return locations. */
MAX_LOCATION_HISTORY_ENTRIES :: 128

/* Location_State is one portable buffer selection state retained for return navigation. */
Location_State :: struct {
	buffer_id:     editor.Buffer_ID,
	revision:      editor.Revision,
	point:         editor.Position,
	mark:          editor.Selection_Mark_Snapshot,
	region_active: bool,
}

/* Location_History retains newest-first restorable session-local locations. */
Location_History :: struct {
	entries: [MAX_LOCATION_HISTORY_ENTRIES]Location_State,
	count:   u16,
}

/* location_state_from_selection copies one current selection state for bounded retention. */
location_state_from_selection :: proc(selection: editor.Selection_Snapshot) -> (Location_State, bool) {
	if selection.buffer_id == editor.Buffer_ID(0) ||
	   selection.point_position.buffer_id != selection.buffer_id ||
	   selection.point_position.revision != selection.revision ||
	   selection.region_active && !selection.mark.present ||
	   selection.mark.present &&
		(selection.mark.position.buffer_id != selection.buffer_id ||
		 selection.mark.position.revision != selection.revision) {
		return {}, false
	}
	return Location_State {
		buffer_id = selection.buffer_id,
		revision = selection.revision,
		point = selection.point_position,
		mark = selection.mark,
		region_active = selection.region_active,
	}, true
}

/* location_history_push retains one state and evicts only the oldest complete entry. */
location_history_push :: proc(history: ^Location_History, state: Location_State) -> bool {
	if history == nil || !location_state_is_valid(state) ||
	   history.count > u16(MAX_LOCATION_HISTORY_ENTRIES) {
		return false
	}
	if history.count == u16(MAX_LOCATION_HISTORY_ENTRIES) {
		for index in 0..<MAX_LOCATION_HISTORY_ENTRIES - 1 {
			history.entries[index] = history.entries[index + 1]
		}
		history.count -= 1
	}
	history.entries[history.count] = state
	history.count += 1
	return true
}

/* location_history_pop returns and consumes the most recently retained state. */
location_history_pop :: proc(history: ^Location_History) -> (Location_State, bool) {
	if history == nil || history.count == 0 || history.count > u16(MAX_LOCATION_HISTORY_ENTRIES) {
		return {}, false
	}
	history.count -= 1
	result := history.entries[history.count]
	history.entries[history.count] = {}
	if !location_state_is_valid(result) {
		return {}, false
	}
	return result, true
}

/* location_history_count reports the current admitted bounded entry count. */
location_history_count :: proc(history: ^Location_History) -> (u16, bool) {
	if history == nil || history.count > u16(MAX_LOCATION_HISTORY_ENTRIES) {
		return 0, false
	}
	return history.count, true
}

@(private)
location_state_is_valid :: proc(state: Location_State) -> bool {
	if state.buffer_id == editor.Buffer_ID(0) || state.point.buffer_id != state.buffer_id ||
	   state.point.revision != state.revision || state.region_active && !state.mark.present {
		return false
	}
	return !state.mark.present ||
		(state.mark.position.buffer_id == state.buffer_id &&
		 state.mark.position.revision == state.revision)
}
