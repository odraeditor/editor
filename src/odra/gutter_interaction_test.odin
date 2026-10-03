// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../gutter"
import "../theme"
import "../ui"
import "core:strings"
import "core:testing"

@(test)
/* gutter_marker_inspection_cycles_through_primary_and_hidden_collision_members. */
marker_inspection_cycles_collisions :: proc(t: ^testing.T) {
	markers := []gutter.Marker {
		{
			id = 4,
			provider = gutter.FACTORY_SEMANTIC_PROVIDER_ID,
			provider_generation = gutter.FACTORY_SEMANTIC_PROVIDER_GENERATION,
			lane = gutter.FACTORY_SEMANTIC_LANE_ID,
			attachment = {kind = .Logical_Line, logical_line = 8, buffer_revision = 7},
			style_role = .Diagnostic_Error,
			priority = 400,
			representation = {.Glyph, "●", "E"},
			detail = "Expected an operand.",
		},
		{
			id = 5,
			provider = gutter.FACTORY_SEMANTIC_PROVIDER_ID,
			provider_generation = gutter.FACTORY_SEMANTIC_PROVIDER_GENERATION,
			lane = gutter.FACTORY_SEMANTIC_LANE_ID,
			attachment = {kind = .Logical_Line, logical_line = 8, buffer_revision = 7},
			style_role = .Diagnostic_Hint,
			priority = 100,
			representation = {.Glyph, "·", "H"},
			detail = "Consider adding a value.",
		},
	}
	publication := gutter.Marker_Generation_View {
		id = 1,
		provider = gutter.FACTORY_SEMANTIC_PROVIDER_ID,
		provider_generation = gutter.FACTORY_SEMANTIC_PROVIDER_GENERATION,
		complete = true,
		markers = markers,
	}
	resolved := gutter.Resolved_Marker_View {
		generation = 2,
		markers = make([dynamic]gutter.Resolved_Marker, 1),
		allocator = context.allocator,
	}
	defer gutter.resolved_marker_view_close(&resolved)
	resolved.markers[0] = {
		viewport_row = 0,
		logical_line = 8,
		lane = gutter.FACTORY_SEMANTIC_LANE_ID,
		primary = 4,
		member_count = 2,
		style_role = .Diagnostic_Error,
	}
	resolved.markers[0].members[0] = 4
	resolved.markers[0].members[1] = 5
	resolved.markers[0].member_providers[0] = gutter.FACTORY_SEMANTIC_PROVIDER_ID
	resolved.markers[0].member_providers[1] = gutter.FACTORY_SEMANTIC_PROVIDER_ID
	state: Gutter_Inspection_State
	gutter_inspection_observe(&state, &resolved, []gutter.Marker_Generation_View{publication}, 7, 11, 2, 9, 8)
	commands := Command_Context {
		gutter_inspection = &state,
		renderer_profile = {
			id = 1,
			capabilities = {.Popup_Overlap},
			max_rows = 24,
			max_columns = 80,
		},
	}
	profiles_ready := gutter_interaction_test_profiles_init(&commands)
	testing.expect(t, profiles_ready)
	if !profiles_ready do return
	defer {
		_, _ = ui.presentation_profile_registry_close(&commands.presentation_profiles)
		_, _ = theme.theme_registry_close(&commands.theme_registry)
	}
	first, first_failure := command_context_inspect_gutter_marker(&commands)
	first_content, first_content_ok := gutter_popup_content_project(&state, state.popup_generation)
	testing.expect(t, first.changed && first_failure.stage == .None && first_content_ok)
	testing.expect_value(t, first_content.marker_id, gutter.Marker_ID(4))
	testing.expect_value(t, first_content.collision_index, u8(0))
	second, second_failure := command_context_inspect_gutter_marker(&commands)
	second_content, second_content_ok := gutter_popup_content_project(&state, state.popup_generation)
	testing.expect(t, second.changed && second_failure.stage == .None && second_content_ok)
	testing.expect_value(t, second_content.marker_id, gutter.Marker_ID(5))
	testing.expect_value(t, second_content.collision_index, u8(1))
	testing.expect_value(t, commands.diagnostic_length, 0)
}

@(test)
/* gutter_marker_popup_reconciles_cursor_movement_and_missing_markers. */
marker_popup_tracks_cursor_and_missing :: proc(t: ^testing.T) {
	state := gutter_popup_test_state()
	marker, index, available := gutter_inspection_current(&state)
	opened := gutter_inspection_popup_open(&state, marker, index)

	resolved := gutter.Resolved_Marker_View {
		generation = 3,
		markers = make([dynamic]gutter.Resolved_Marker, 0),
		allocator = context.allocator,
	}
	defer gutter.resolved_marker_view_close(&resolved)
	gutter_inspection_observe(&state, &resolved, nil, 7, 11, 2, 9, 8, 12)

	commands := Command_Context{gutter_inspection = &state}
	result, failure := command_context_inspect_gutter_marker(&commands)
	testing.expect(t, available && opened && !state.popup_open)
	testing.expect(t, result.changed && failure.stage == .None)
	testing.expect(t, strings.contains(
		string(commands.diagnostic[:commands.diagnostic_length]),
		"No semantic Gutter markers",
	))
}

@(test)
/* gutter_marker_inspection_survives_command_navigation_viewport_reflow. */
marker_inspection_survives_reflow :: proc(t: ^testing.T) {
	state := gutter_popup_test_state()

	gutter_inspection_begin_frame(&state, true)
	marker, _, available := gutter_inspection_current(&state)
	testing.expect(t, available && marker != nil)
	if marker != nil {
		testing.expect_value(t, marker.id, gutter.Marker_ID(41))
	}

	gutter_inspection_begin_frame(&state, false)
	_, _, available = gutter_inspection_current(&state)
	testing.expect(t, !available)
}

@(test)
/* gutter_marker_inspection_uses_only_shared_feedback_when_overlap_is_unavailable. */
marker_inspection_falls_back_without_overlap :: proc(t: ^testing.T) {
	state := gutter_popup_test_state()
	commands := Command_Context {
		gutter_inspection = &state,
		renderer_profile = {id = 1, max_rows = 24, max_columns = 80},
		persistent_allocator = context.allocator,
	}
	profiles_ready := gutter_interaction_test_profiles_init(&commands)
	testing.expect(t, profiles_ready)
	if !profiles_ready do return
	defer {
		_, _ = ui.presentation_profile_registry_close(&commands.presentation_profiles)
		_, _ = theme.theme_registry_close(&commands.theme_registry)
	}
	result, failure := command_context_inspect_gutter_marker(&commands)
	content, role, fallback := popup_fallback_view(&commands.popup_fallback)

	testing.expect(t, result.changed && failure.stage == .None)
	testing.expect(t, state.popup_open && fallback)
	testing.expect_value(t, content, "Expected λ after operator.")
	testing.expect_value(t, role, ui.Style_Role.Popup_Diagnostic)
	testing.expect_value(t, commands.diagnostic_length, 0)

	popup_fallback_clear(&commands.popup_fallback)
}

@(private)
gutter_interaction_test_profiles_init :: proc(commands: ^Command_Context) -> bool {
	if commands == nil do return false
	theme_ready, _ := theme.theme_registry_init_factory(&commands.theme_registry, 12_201)
	if !theme_ready do return false
	profiles_ready, _ := ui.presentation_profile_registry_init(
		&commands.presentation_profiles,
		12_201,
	)
	if !profiles_ready {
		_, _ = theme.theme_registry_close(&commands.theme_registry)
		return false
	}
	return true
}
