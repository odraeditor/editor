// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../gutter"
import "../ui"
import "core:testing"

@(test)
/* gutter_popup_composition_anchors_exact_marker_content_and_preserves_focus. */
popup_anchors_content_and_keeps_focus :: proc(t: ^testing.T) {
	registry: ui.Registry
	initialized, _ := ui.registry_init(&registry, 12_014)
	defer ui.registry_close(&registry)
	state := gutter_popup_test_state()
	state.logical_line = 8
	state.popup_open = true
	state.popup_marker = 41
	state.popup_index = 0
	state.popup_generation = 2
	root, popup_handle, source, published := gutter_popup_test_publish(
		&registry,
		{},
		&state,
		transient_input_test_renderer(),
	)
	popup, inspected, _ := ui.registry_inspect_popup(&registry, popup_handle)
	focus, focused, _ := ui.registry_focus(&registry)

	testing.expect(t, initialized && published && inspected && focused)
	testing.expect_value(t, root.generation, ui.Root_Generation(1))
	testing.expect_value(t, popup.id, GUTTER_POPUP_ID)
	testing.expect_value(t, popup.anchor.kind, ui.Popup_Anchor_Kind.Gutter_Marker)
	testing.expect_value(t, popup.anchor.start, u64(8))
	testing.expect_value(t, popup.anchor.viewport_row, u32(2))
	testing.expect_value(t, popup.anchor.viewport_column, u32(0))
	testing.expect_value(t, popup.anchor.source_generation, u64(17))
	testing.expect_value(t, popup.action_count, u16(1))
	testing.expect_value(t, popup.margin_rows, u8(0))
	testing.expect_value(t, popup.margin_columns, u8(1))
	testing.expect_value(t, popup.padding_rows, u8(0))
	testing.expect_value(t, popup.padding_columns, u8(0))
	testing.expect_value(
		t,
		popup.presentation_profile.handle.role,
		ui.Presentation_Profile_Role.Contextual_Information,
	)
	testing.expect_value(t, popup.presentation_profile.handle.profile_id, ui.Presentation_Profile_ID(1))
	testing.expect_value(t, popup.presentation_profile.definition.mapping_count, u8(10))
	testing.expect_value(t, popup.geometry.content.column - popup.geometry.outer.column, i32(2))
	testing.expect_value(t, popup.geometry.state, ui.Popup_Geometry_State.Placed)
	testing.expect_value(t, focus.target, source)
	testing.expect(t, !focus.captured)
}

@(test)
/* gutter_popup_composition_replaces_collisions_and_degrades_narrow_geometry. */
popup_replaces_collisions_on_narrow_views :: proc(t: ^testing.T) {
	registry: ui.Registry
	initialized, _ := ui.registry_init(&registry, 12_015)
	defer ui.registry_close(&registry)
	state := gutter_popup_test_state()
	state.logical_line = 8
	state.popup_open = true
	state.popup_marker = 41
	state.popup_index = 0
	state.popup_generation = 3
	first, first_popup, _, first_ok := gutter_popup_test_publish(
		&registry,
		{},
		&state,
		transient_input_test_renderer(),
	)
	state.popup_marker = 42
	state.popup_index = 1
	second, second_popup, _, second_ok := gutter_popup_test_publish(
		&registry,
		first,
		&state,
		transient_input_test_renderer(),
	)
	_, stale_visible, stale_failure := ui.registry_inspect_popup(&registry, first_popup)
	second_descriptor, second_visible, _ := ui.registry_inspect_popup(&registry, second_popup)

	narrow := transient_input_test_renderer()
	narrow.max_columns = 12
	narrow.max_cells = u64(narrow.max_rows) * u64(narrow.max_columns)
	proposal, prepared, _ := ui.proposal_begin(&registry, second)
	defer if proposal.state != nil do ui.proposal_abort(&proposal)
	_, source, base_ok := gutter_popup_test_source(&proposal, narrow)
	rows := [1]gutter.Row_View{{viewport_row = 2, logical_line = 8}}
	view := gutter_popup_test_view(rows[:])
	composition, composed, _ := proposal_compose_gutter_popup(
		&proposal, &state, source, 10, view, gutter_popup_test_presentation_profile(), narrow,
	)

	testing.expect(t, initialized && first_ok && second_ok && second_visible)
	testing.expect(t, second.generation > first.generation)
	testing.expect(t, !stale_visible && stale_failure.code == .Stale_Popup)
	testing.expect_value(t, second_descriptor.id, GUTTER_POPUP_ID)
	testing.expect(t, second_descriptor.generation > ui.Popup_Generation(3))
	testing.expect(t, prepared && base_ok && composed && !composition.present)
}

@(private)
gutter_popup_test_publish :: proc(
	registry: ^ui.Registry,
	expected: ui.Root_Handle,
	state: ^Gutter_Inspection_State,
	profile: ui.Renderer_Profile,
) -> (root: ui.Root_Handle, popup, source: ui.Object_Handle, ok: bool) {
	proposal, prepared, _ := ui.proposal_begin(registry, expected)
	if !prepared do return
	defer if proposal.state != nil do ui.proposal_abort(&proposal)
	source_ok: bool
	_, source, source_ok = gutter_popup_test_source(&proposal, profile)
	rows := [1]gutter.Row_View{{viewport_row = 2, logical_line = 8}}
	view := gutter_popup_test_view(rows[:])
	composition, composed, _ := proposal_compose_gutter_popup(
		&proposal,
		state,
		source,
		10,
		view,
		gutter_popup_test_presentation_profile(),
		profile,
	)
	if !source_ok || !composed || !composition.present do return
	root, ok, _ = ui.proposal_publish(registry, &proposal, profile)
	return root, composition.handle, source, ok
}

@(private)
gutter_popup_test_source :: proc(
	proposal: ^ui.Proposal,
	profile: ui.Renderer_Profile,
) -> (node, surface: ui.Object_Handle, ok: bool) {
	styles := [?]ui.Style_Role {
		.Text_Normal,
		.List_Normal,
		.List_Current,
		.List_Emphasis,
		.Popup_Background,
		.Popup_Content,
		.Popup_Border,
		.Popup_Diagnostic,
		.Popup_Unavailable,
		.Gutter_Line_Number,
	}
	for role in styles {
		if _, added, _ := ui.proposal_add_style(proposal, role); !added do return
	}
	projection, projection_ok, _ := ui.proposal_add_projection(
		proposal,
		{owner_id = 1, model_id = 1, generation = 1},
		256,
	)
	text := ui.Text_View_State {
		present = true,
		source = {
			registry_id = 1,
			view_id = 11,
			view_generation = 2,
			state_generation = 10,
			selection_generation = 1,
		},
		buffer_id = 21,
		revision = 7,
		source_text_bytes = 256,
		stored_point = 8,
		effective_point = 8,
		tab_width = 4,
		display_profile_id = 1,
		presentation_ownership = .Retained_Primary,
		gutter = {
			present = true,
			generation = 17,
			left_cells = 2,
			text_cells = 78,
			row_count = 3,
		},
	}
	text.gutter.rows[0] = {
		viewport_row = 0,
		logical_line = 6,
		left_cells = 2,
		left_style_role = .Gutter_Line_Number,
	}
	text.gutter.rows[1] = {
		viewport_row = 1,
		logical_line = 7,
		left_cells = 2,
		left_style_role = .Gutter_Line_Number,
	}
	text.gutter.rows[2] = {
		viewport_row = 2,
		logical_line = 8,
		left_cells = 2,
		left_style_role = .Gutter_Line_Number,
	}
	view, view_ok, _ := ui.proposal_add_view(
		proposal,
		{kind = .Text_View, projection = projection, text = text},
	)
	surface_ok: bool
	surface, surface_ok, _ = ui.proposal_add_surface(
		proposal,
		{
			owner_id = 1,
			view = view,
			focusable = true,
			visible = true,
			required_profile = profile.id,
			geometry = {row = 0, column = 0, height = 20, width = 80},
		},
	)
	node_ok: bool
	node, node_ok, _ = ui.proposal_add_surface_node(proposal, surface)
	root_ok, _ := ui.proposal_set_root(proposal, node, surface)
	return node, surface, projection_ok && view_ok && surface_ok && node_ok && root_ok
}

@(private)
gutter_popup_test_presentation_profile :: proc() -> ui.Presentation_Profile_Record {
	registry: ui.Presentation_Profile_Registry
	initialized, _ := ui.presentation_profile_registry_init(&registry, 12_101)
	assert(initialized)
	scope, scoped, _ := ui.presentation_profile_registry_scope(
		&registry,
		.Contextual_Information,
	)
	assert(scoped)
	record, recorded, _ := ui.presentation_profile_registry_record(&registry, scope.selected)
	assert(recorded)
	closed, _ := ui.presentation_profile_registry_close(&registry)
	assert(closed)
	return record
}

@(private)
gutter_popup_test_view :: proc(rows: []gutter.Row_View) -> gutter.View {
	view := gutter.View {
		generation = 17,
		geometry = {
			available_cells = 80,
			left_cells = 2,
			text_cells = 78,
			lane_count = 2,
		},
		rows = rows,
	}
	view.geometry.lanes[0] = {
		lane = 5,
		side = .Left,
		width_cells = 1,
		visible = true,
	}
	view.geometry.lanes[1] = {
		lane = 6,
		side = .Left,
		start_cell = 1,
		width_cells = 1,
		visible = true,
	}
	return view
}
