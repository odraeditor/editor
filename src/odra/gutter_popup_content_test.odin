// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../gutter"
import "core:testing"

@(test)
/* gutter_popup_content_projects_actionable_detail_without_internal_metadata. */
popup_content_hides_internal_metadata :: proc(t: ^testing.T) {
	state := gutter_popup_test_state()
	content, projected := gutter_popup_content_project(&state, 9)
	detail := string(content.detail[:content.detail_length])

	testing.expect(t, projected)
	testing.expect_value(t, content.generation, u64(9))
	testing.expect_value(t, content.marker_id, gutter.Marker_ID(41))
	testing.expect_value(t, content.collision_index, u8(0))
	testing.expect_value(t, content.collision_count, u8(2))
	testing.expect(t, content.actionable && !content.stale)
	testing.expect_value(t, detail, "Expected λ after operator.")
}

@(test)
/* gutter_popup_content_distinguishes_viewport_personal_and_stale_markers. */
popup_content_classifies_marker_states :: proc(t: ^testing.T) {
	state := gutter_popup_test_state()
	state.next_index = 1
	state.markers[1].role = .Clipping
	state.markers[1].stale = true
	content, projected := gutter_popup_content_project(&state, 10)
	testing.expect(t, projected && content.stale)
	testing.expect_value(
		t,
		string(content.detail[:content.detail_length]),
		"Personal marker detail.",
	)

	state.markers[1].role = .Ordinary
	personal, personal_ok := gutter_popup_content_project(&state, 11)
	testing.expect(t, personal_ok)
	testing.expect_value(
		t,
		string(personal.detail[:personal.detail_length]),
		"Personal marker detail.",
	)
}

@(test)
/* gutter_popup_content_rejects_missing_or_unbounded_source_detail. */
rejects_missing_or_unbounded_source_detail :: proc(t: ^testing.T) {
	state := gutter_popup_test_state()
	state.markers[0].detail_length = 0
	_, missing := gutter_popup_content_project(&state, 1)
	state.markers[0].detail_length = u16(len(state.markers[0].detail))
	_, bounded := gutter_popup_content_project(&state, 1)
	_, invalid_generation := gutter_popup_content_project(&state, 0)

	testing.expect(t, !missing && bounded && !invalid_generation)
}

@(private)
gutter_popup_test_state :: proc() -> Gutter_Inspection_State {
	state := Gutter_Inspection_State {
		available = true,
		marker_count = 2,
	}
	state.markers[0] = {
		id = 41,
		provider = 7,
		provider_generation = 3,
		lane = 5,
		role = .Diagnostic_Error,
		actionable = true,
		action = {registry_generation = 2, slot = 4, entry_generation = 6},
	}
	detail := "Expected λ after operator."
	state.markers[0].detail_length = u16(len(detail))
	copy(state.markers[0].detail[:state.markers[0].detail_length], transmute([]u8)detail)
	state.markers[1] = {
		id = 42,
		provider = 8,
		provider_generation = 4,
		lane = 6,
		role = .Ordinary,
	}
	other_detail := "Personal marker detail."
	state.markers[1].detail_length = u16(len(other_detail))
	copy(state.markers[1].detail[:state.markers[1].detail_length], transmute([]u8)other_detail)
	return state
}
