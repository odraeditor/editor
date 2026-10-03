// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../editor"
import "core:testing"

/* Verifies retained locations preserve complete point, mark, and activation state. */
@(test)
location_history_retains_selection_state :: proc(t: ^testing.T) {
	selection := editor.Selection_Snapshot {
		buffer_id = editor.Buffer_ID(31),
		revision = editor.Revision(7),
		point_position = {
			buffer_id = editor.Buffer_ID(31),
			revision = editor.Revision(7),
			byte_offset = editor.Byte_Offset(12),
		},
		mark = {
			present = true,
			position = {
				buffer_id = editor.Buffer_ID(31),
				revision = editor.Revision(7),
				byte_offset = editor.Byte_Offset(4),
			},
		},
		region_active = true,
	}
	state, copied := location_state_from_selection(selection)
	history: Location_History
	pushed := location_history_push(&history, state)
	count, counted := location_history_count(&history)
	restored, popped := location_history_pop(&history)
	testing.expect(t, copied && pushed && counted && popped)
	testing.expect_value(t, count, u16(1))
	testing.expect_value(t, restored, state)
}

/* Verifies return history consumes states in reverse insertion order. */
@(test)
location_history_returns_newest_state_first :: proc(t: ^testing.T) {
	history: Location_History
	for offset in 1..=3 {
		pushed := location_history_push(&history, location_history_test_state(u64(offset)))
		testing.expect(t, pushed)
	}
	for offset in 1..=3 {
		state, popped := location_history_pop(&history)
		testing.expect(t, popped)
		testing.expect_value(t, state.point.byte_offset, editor.Byte_Offset(4 - offset))
	}
	_, popped := location_history_pop(&history)
	testing.expect(t, !popped)
}

/* Verifies capacity pressure removes only the oldest complete return location. */
@(test)
location_history_evicts_oldest_entry_at_capacity :: proc(t: ^testing.T) {
	history: Location_History
	for offset in 0..<MAX_LOCATION_HISTORY_ENTRIES + 1 {
		pushed := location_history_push(&history, location_history_test_state(u64(offset)))
		testing.expect(t, pushed)
	}
	count, counted := location_history_count(&history)
	oldest: Location_State
	for index in 0..<MAX_LOCATION_HISTORY_ENTRIES {
		state, popped := location_history_pop(&history)
		testing.expect(t, popped)
		oldest = state
		if index == 0 {
			testing.expect_value(t, state.point.byte_offset, editor.Byte_Offset(MAX_LOCATION_HISTORY_ENTRIES))
		}
	}
	testing.expect(t, counted)
	testing.expect_value(t, count, u16(MAX_LOCATION_HISTORY_ENTRIES))
	testing.expect_value(t, oldest.point.byte_offset, editor.Byte_Offset(1))
}

/* Verifies incomplete or mismatched selection data is not admitted. */
@(test)
location_history_rejects_invalid_selection_state :: proc(t: ^testing.T) {
	history: Location_History
	invalid := editor.Selection_Snapshot {
		buffer_id = editor.Buffer_ID(32),
		revision = editor.Revision(1),
		point_position = {
			buffer_id = editor.Buffer_ID(32),
			revision = editor.Revision(1),
		},
		region_active = true,
	}
	state, copied := location_state_from_selection(invalid)
	pushed := location_history_push(&history, state)
	count, counted := location_history_count(&history)
	testing.expect(t, !copied && !pushed && counted)
	testing.expect_value(t, count, u16(0))
}

@(private)
location_history_test_state :: proc(offset: u64) -> Location_State {
	return Location_State {
		buffer_id = editor.Buffer_ID(33),
		revision = editor.Revision(1),
		point = {
			buffer_id = editor.Buffer_ID(33),
			revision = editor.Revision(1),
			byte_offset = editor.Byte_Offset(offset),
		},
	}
}
