// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ui

import "core:testing"

/* Verifies every semantic anchor resolves into the expected root geometry. */
@(test)
resolves_all_checked_semantic_categories :: proc(t: ^testing.T) {
	cases := [?]struct {
		name: string,
		kind: Popup_Anchor_Kind,
		row:  i32,
		column: i32,
	} {
		{name = "cursor", kind = .Cursor, row = 5, column = 9},
		{name = "logical-text", kind = .Logical_Text, row = 4, column = 8},
		{name = "gutter-marker", kind = .Gutter_Marker, row = 2, column = 4},
		{name = "surface", kind = .Surface, row = 3, column = 4},
	}
	for test_case, index in cases {
		registry: Registry
		initialized, _ := registry_init(&registry, Registry_ID(81 + index))
		root, popup, _, published, _ := publish_anchor_test_popup(
			&registry,
			{},
			test_case.kind,
			Cell_Rect{row = 2, column = 4, height = 10, width = 40},
			false,
			popup_test_renderer(),
		)
		resolution, resolved, _ := registry_resolve_popup_anchor(&registry, popup)

		testing.expectf(t, initialized && published && resolved, "%s anchor did not resolve", test_case.name)
		testing.expectf(t, resolution.root == root, "%s anchor resolved against the wrong root", test_case.name)
		testing.expectf(t, resolution.kind == test_case.kind, "%s anchor changed kind", test_case.name)
		testing.expectf(t, resolution.geometry.row == test_case.row, "%s anchor resolved to the wrong row", test_case.name)
		testing.expectf(t, resolution.geometry.column == test_case.column, "%s anchor resolved to the wrong column", test_case.name)
		testing.expectf(
			t,
			resolution.geometry.height > 0 && resolution.geometry.width > 0,
			"%s anchor resolved without area",
			test_case.name,
		)
		closed, _ := registry_close(&registry)
		testing.expectf(t, closed, "%s anchor registry did not close", test_case.name)
	}
}

/* Verifies stale semantic anchors and backend coordinates are rejected. */
@(test)
rejects_stale_semantic_generations :: proc(t: ^testing.T) {
	cases := [?]struct {
		name: string,
		kind: Popup_Anchor_Kind,
	} {
		{name = "stale-cursor", kind = .Cursor},
		{name = "stale-logical-text", kind = .Logical_Text},
		{name = "stale-gutter-marker", kind = .Gutter_Marker},
	}
	for test_case, index in cases {
		registry: Registry
		initialized, _ := registry_init(&registry, Registry_ID(90 + index))
		_, _, _, published, failure := publish_anchor_test_popup(
			&registry,
			{},
			test_case.kind,
			Cell_Rect{row = 0, column = 0, height = 12, width = 40},
			true,
			popup_test_renderer(),
		)
		testing.expectf(t, initialized && !published, "%s anchor was published", test_case.name)
		testing.expectf(t, failure.code == .Invalid_Popup_Anchor, "%s anchor returned the wrong failure", test_case.name)
		closed, _ := registry_close(&registry)
		testing.expectf(t, closed, "%s anchor registry did not close", test_case.name)
	}

	registry: Registry
	initialized, _ := registry_init(&registry, Registry_ID(99))
	_, _, _, published, failure := publish_anchor_test_popup(
		&registry,
		{},
		.Backend_Coordinates,
		Cell_Rect{row = 0, column = 0, height = 12, width = 40},
		false,
		popup_test_renderer(),
	)
	testing.expect(t, initialized && !published)
	testing.expect_value(t, failure.code, Failure_Code.Invalid_Popup_Anchor)
	closed, _ := registry_close(&registry)
	testing.expect(t, closed)
}

/* Verifies replacement follows layout changes and invalidates closed sources. */
@(test)
replacement_tracks_scroll_split :: proc(t: ^testing.T) {
	registry: Registry
	initialized, _ := registry_init(&registry, Registry_ID(100))
	first, first_popup, _, first_ok, _ := publish_anchor_test_popup(
		&registry,
		{},
		.Logical_Text,
		Cell_Rect{row = 1, column = 1, height = 12, width = 40},
		false,
		popup_test_renderer(),
	)
	first_resolution, first_resolved, _ := registry_resolve_popup_anchor(
		&registry, first_popup,
	)
	second, second_popup, _, second_ok, _ := publish_anchor_test_popup(
		&registry,
		first,
		.Logical_Text,
		Cell_Rect{row = 6, column = 44, height = 10, width = 32},
		false,
		popup_test_renderer(),
	)
	second_resolution, second_resolved, _ := registry_resolve_popup_anchor(
		&registry, second_popup,
	)
	_, stale_ok, stale_failure := registry_resolve_popup_anchor(&registry, first_popup)
	closed_root, closed_ok := publish_single_text_root(&registry, second)
	_, closed_source_ok, closed_failure := registry_resolve_popup_anchor(
		&registry, second_popup,
	)

	testing.expect(
		t,
		initialized && first_ok && first_resolved && second_ok && second_resolved &&
		!stale_ok && closed_ok && !closed_source_ok,
	)
	testing.expect_value(t, first_resolution.geometry, Cell_Rect{row = 3, column = 5, height = 1, width = 4})
	testing.expect_value(t, second_resolution.geometry, Cell_Rect{row = 8, column = 48, height = 1, width = 4})
	testing.expect_value(t, stale_failure.code, Failure_Code.Stale_Popup)
	testing.expect_value(t, closed_failure.code, Failure_Code.Stale_Popup)
	testing.expect_value(t, closed_root.generation, Root_Generation(3))
	closed, _ := registry_close(&registry)
	testing.expect(t, closed)
}

@(private)
publish_anchor_test_popup :: proc(
	registry: ^Registry,
	expected: Root_Handle,
	kind: Popup_Anchor_Kind,
	source_geometry: Cell_Rect,
	stale: bool,
	renderer: Renderer_Profile,
) -> (
	root: Root_Handle,
	popup, source: Object_Handle,
	ok: bool,
	failure: Failure,
) {
	proposal, prepared, begin_failure := proposal_begin(registry, expected)
	if !prepared {
		return {}, {}, {}, false, begin_failure
	}
	defer if proposal.state != nil do proposal_abort(&proposal)
	_, style_ok, _ := proposal_add_style(&proposal, .Text_Normal)
	source_projection, source_projection_ok, _ := proposal_add_projection(
		&proposal,
		Model_Reference{owner_id = 1, model_id = 1, generation = 1},
		256,
	)
	text := Text_View_State {
		present = true,
		source = {
			registry_id = 1,
			view_id = 101,
			view_generation = 1,
			state_generation = 10,
			selection_generation = 1,
		},
		buffer_id = 201,
		revision = 20,
		source_text_bytes = 256,
		stored_point = 25,
		effective_point = 25,
		viewport_origin = 0,
		tab_width = 4,
		display_profile_id = 1,
		presentation_ownership = .Retained_Primary,
	}
	if kind == .Gutter_Marker {
		text.gutter = Text_Gutter_State {
			present = true,
			generation = 30,
			text_cells = u32(source_geometry.width),
			row_count = 1,
		}
		text.gutter.rows[0] = Text_Gutter_Row_Descriptor {
			viewport_row = 0,
			logical_line = 7,
		}
	}
	source_view, source_view_ok, _ := proposal_add_view(
		&proposal,
		Visual_View_Descriptor {
			kind = .Text_View,
			projection = source_projection,
			text = text,
		},
	)
	content_projection, content_projection_ok, _ := proposal_add_projection(
		&proposal,
		Model_Reference{owner_id = 2, model_id = 2, generation = 41},
		1_024,
	)
	content_view, content_view_ok, _ := proposal_add_view(
		&proposal,
		Visual_View_Descriptor{kind = .Text_View, projection = content_projection, read_only = true},
	)
	source_ok: bool
	source, source_ok, _ = proposal_add_surface(
		&proposal,
		Surface_Descriptor {
			owner_id = 1,
			view = source_view,
			focusable = true,
			visible = true,
			required_profile = 1,
			geometry = source_geometry,
		},
	)
	content, content_ok, _ := proposal_add_surface(
		&proposal,
		Surface_Descriptor {
			owner_id = 2,
			view = content_view,
			focusable = false,
			visible = true,
			required_profile = 1,
			geometry = {height = 4, width = 24},
		},
	)
	node, node_ok, _ := proposal_add_surface_node(&proposal, source)
	anchor := Popup_Anchor_Reference {
		kind = kind,
		source_surface = source,
		owner_id = 3,
		source_id = 101,
		source_generation = 10,
		start = 25,
		end = 25,
		presentation_generation = 10,
		viewport_row = 3,
		viewport_column = 5,
		height_rows = 1,
		width_columns = 1,
	}
	switch kind {
	case .Cursor:
		if stale do anchor.source_generation -= 1
	case .Logical_Text:
		anchor.source_id = 201
		anchor.source_generation = 20
		anchor.start = 5
		anchor.end = 9
		anchor.viewport_row = 2
		anchor.viewport_column = 4
		anchor.width_columns = 4
		if stale do anchor.source_generation -= 1
	case .Gutter_Marker:
		anchor.source_id = 301
		anchor.source_generation = 30
		anchor.start = 7
		anchor.end = 7
		anchor.viewport_row = 0
		anchor.viewport_column = 0
		if stale do anchor.source_generation -= 1
	case .Surface:
		anchor.source_id = u64(source.object_id)
		anchor.source_generation = u64(source.root_generation)
		anchor.presentation_generation = u64(source.root_generation)
		anchor.viewport_row = 1
		anchor.viewport_column = 0
		anchor.width_columns = u16(source_geometry.width)
	case .Backend_Coordinates, .Invalid:
	}
	popup_ok: bool
	popup_failure: Failure
	descriptor := Popup_Descriptor {
			id = 51,
			generation = Popup_Generation(u64(expected.generation) + 1),
			owner_id = 3,
			owner_generation = u64(expected.generation) + 1,
			anchor = anchor,
			content_surface = content,
			content_generation = 41,
			placements = {.Above, .Below, .Before, .After},
			placement_count = 4,
			bounds = {
				minimum_rows = 1,
				minimum_columns = 8,
				preferred_rows = 4,
				preferred_columns = 24,
				maximum_rows = 8,
				maximum_columns = 40,
			},
			clipping = .Clip,
			behavior = .Informational,
			input_policy = .Preserve_Source_Focus,
			dismissal = {.Explicit_Cancel, .Anchor_Invalidation},
			fallback = .Compact_Feedback,
			required_profile = 1,
			content_bytes = 1_024,
	}
	popup_test_attach_presentation_profile(&descriptor)
	popup, popup_ok, popup_failure = proposal_add_popup(&proposal, descriptor)
	root_ok, _ := proposal_set_root(&proposal, node, source)
	if !popup_ok {
		return {}, {}, {}, false, popup_failure
	}
	published: bool
	root, published, failure = proposal_publish(registry, &proposal, renderer)
	return root, popup, source, style_ok && source_projection_ok && source_view_ok &&
		content_projection_ok && content_view_ok && source_ok && content_ok && node_ok &&
		root_ok && published, failure
}
