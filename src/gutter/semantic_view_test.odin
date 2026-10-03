// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package gutter

import "core:testing"

@(private = "file")
semantic_view_test_markers :: proc(
	rows: []Visible_Row,
	marker: Marker,
) -> (Resolved_Marker_View, bool) {
	lane := factory_semantic_lane(.Left)
	publication := Marker_Generation_View {
		id = 1,
		provider = FACTORY_SEMANTIC_PROVIDER_ID,
		provider_generation = FACTORY_SEMANTIC_PROVIDER_GENERATION,
		complete = true,
		markers = []Marker{marker},
	}
	view, ok, _ := compose_markers(Marker_Composition_Request {
		generation = 2,
		lanes = []Lane_Definition{lane},
		publications = []Marker_Generation_View{publication},
		rows = rows,
		buffer_revision = 7,
		allocator = context.allocator,
		limits = DEFAULT_LIMITS,
	})
	return view, ok
}

@(test)
/* semantic_lane_projects_diagnostics_opposite_line_numbers_without_entering_text. */
diagnostics_project_beside_line_numbers :: proc(t: ^testing.T) {
	rows := []Visible_Row{{viewport_row = 0, logical_line = 4, has_content = true}}
	request := Factory_Request {
		generation = 2,
		available_cells = 78,
		minimum_text_cells = MIN_TEXT_CELLS,
		line_count = 10,
		viewport_rows = 1,
		rows = rows,
		policy = DEFAULT_FACTORY_POLICY,
		allocator = context.allocator,
		limits = DEFAULT_LIMITS,
	}
	view, ok, _ := compose_factory(request)
	testing.expect(t, ok)
	if !ok do return
	defer view_close(&view)
	marker := Marker {
		id = 1,
		provider = FACTORY_SEMANTIC_PROVIDER_ID,
		provider_generation = FACTORY_SEMANTIC_PROVIDER_GENERATION,
		lane = FACTORY_SEMANTIC_LANE_ID,
		attachment = {kind = .Logical_Line, logical_line = 4, buffer_revision = 7},
		style_role = .Diagnostic_Error,
		priority = 400,
		representation = {.Glyph, "●", "E"},
	}
	markers, markers_ok := semantic_view_test_markers(rows, marker)
	testing.expect(t, markers_ok)
	if !markers_ok do return
	defer resolved_marker_view_close(&markers)
	lane := factory_semantic_lane(.Left)
	added, failure := view_add_semantic_lane(&view, lane, &markers, rows, true)
	testing.expectf(t, added, "semantic lane failed with %v", failure.code)
	if !added do return
	testing.expect_value(t, view.geometry.available_cells, u32(80))
	testing.expect_value(t, view.geometry.text_cells, u32(72))
	testing.expect_value(t, view.geometry.right_cells, u16(2))
	testing.expect_value(t, view.rows[0].right_role, Semantic_Role.Diagnostic_Error)
	testing.expect_value(t, string(view.text[view.rows[0].right_offset:]), "│●")
}

@(test)
/* semantic_lane_materializes_rows_when_numbering_is_hidden. */
semantic_lane_materializes_without_numbers :: proc(t: ^testing.T) {
	rows := []Visible_Row{{viewport_row = 3, logical_line = 8, has_content = true}}
	request := Factory_Request {
		generation = 2,
		available_cells = 78,
		minimum_text_cells = MIN_TEXT_CELLS,
		line_count = 10,
		viewport_rows = 4,
		rows = rows,
		policy = DEFAULT_FACTORY_POLICY,
		allocator = context.allocator,
		limits = DEFAULT_LIMITS,
	}
	request.policy.mode = .None
	view, ok, _ := compose_factory(request)
	testing.expect(t, ok)
	if !ok do return
	defer view_close(&view)
	marker := Marker {
		id = 1,
		provider = FACTORY_SEMANTIC_PROVIDER_ID,
		provider_generation = FACTORY_SEMANTIC_PROVIDER_GENERATION,
		lane = FACTORY_SEMANTIC_LANE_ID,
		attachment = {kind = .Logical_Line, logical_line = 8, buffer_revision = 7},
		style_role = .Diagnostic_Warning,
		priority = 300,
		representation = {.Glyph, "▲", "W"},
	}
	markers, markers_ok := semantic_view_test_markers(rows, marker)
	testing.expect(t, markers_ok)
	if !markers_ok do return
	defer resolved_marker_view_close(&markers)
	added, _ := view_add_semantic_lane(
		&view,
		factory_semantic_lane(.Left),
		&markers,
		rows,
		true,
	)
	testing.expect(t, added)
	if !added do return
	testing.expect_value(t, len(view.rows), 1)
	testing.expect_value(t, view.rows[0].viewport_row, u32(3))
	testing.expect_value(t, view.rows[0].logical_line, u64(8))
}

@(test)
/* programmable_lane_composes_beside_factory_content_in_declared_order. */
programmable_lane_preserves_declared_order :: proc(t: ^testing.T) {
	rows := []Visible_Row{{viewport_row = 0, logical_line = 4, has_content = true}}
	request := Factory_Request {
		generation = 3,
		available_cells = 76,
		minimum_text_cells = MIN_TEXT_CELLS,
		line_count = 10,
		viewport_rows = 1,
		rows = rows,
		policy = DEFAULT_FACTORY_POLICY,
		allocator = context.allocator,
		limits = DEFAULT_LIMITS,
	}
	view, ok, _ := compose_factory(request)
	if !testing.expect(t, ok) do return
	defer view_close(&view)
	lane := Lane_Definition {
		id = PROGRAMMABLE_LANE_ID_BASE,
		provider = PROGRAMMABLE_PROVIDER_ID,
		provider_generation = 1,
		side = .Left,
		order = 50,
		attachments = {.Logical_Line},
		width_policy = .Content_Presence,
		minimum_cells = 3,
		maximum_cells = 3,
		alignment = .Right,
		visibility = .When_Content,
		collision = .Highest_Priority,
		priority = 100,
		style_role = .Diagnostic_Information,
		separator = {.Glyph, "│", "|"},
	}
	marker := Marker {
		id = 1,
		provider = PROGRAMMABLE_PROVIDER_ID,
		provider_generation = 1,
		lane = PROGRAMMABLE_LANE_ID_BASE,
		attachment = {kind = .Logical_Line, logical_line = 4, buffer_revision = 0},
		style_role = .Diagnostic_Information,
		priority = 10,
		representation = {.Glyph, "◆", "*"},
	}
	publication := Marker_Generation_View {
		id = 1,
		provider = PROGRAMMABLE_PROVIDER_ID,
		provider_generation = 1,
		complete = true,
		markers = []Marker{marker},
	}
	markers, composed, failure := compose_markers(Marker_Composition_Request {
		generation = 3,
		lanes = []Lane_Definition{lane},
		publications = []Marker_Generation_View{publication},
		rows = rows,
		buffer_revision = 7,
		allocator = context.allocator,
		limits = DEFAULT_LIMITS,
	})
	if !testing.expectf(t, composed, "marker composition failed: %v", failure.code) do return
	defer resolved_marker_view_close(&markers)
	added, add_failure := view_add_marker_lane(&view, lane, &markers, rows, true)
	if !testing.expectf(t, added, "programmable lane failed: %v", add_failure.code) do return
	entry := view.rows[0]
	left := string(view.text[entry.left_offset:entry.left_offset + u32(entry.left_bytes)])
	testing.expect_value(t, left, " ◆│   5 │")
	testing.expect_value(t, view.geometry.left_cells, u16(9))
	testing.expect_value(t, view.geometry.text_cells, u32(70))
	testing.expect_value(t, view.geometry.lane_count, u8(2))
	testing.expect_value(t, view.geometry.lanes[1].lane, PROGRAMMABLE_LANE_ID_BASE)
}
