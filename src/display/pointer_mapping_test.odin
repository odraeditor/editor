// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package display

import "../editor"
import editor_view "../view"
import "core:testing"

/* Verifies immutable text hits encode exact, leading, and trailing boundary affinity. */
@(test)
pointer_text_hit_contract_models_boundary_affinity :: proc(t: ^testing.T) {
	fixtures := [?]struct {
		name:     string,
		display:  Display_Column,
		position: editor.Byte_Offset,
		start:    Display_Column,
		end:      Display_Column,
		affinity: Text_Hit_Affinity,
	} {
		{"utf8 grapheme boundary", 0, 0, 0, 0, .Exact},
		{"combining grapheme cell", 1, 3, 1, 2, .Leading},
		{"wide glyph trailing cell", 3, 7, 2, 4, .Trailing},
		{"tab interior leading half", 2, 0, 0, 8, .Leading},
		{"tab interior trailing half", 6, 1, 0, 8, .Trailing},
		{"wrapped row boundary", 0, 12, 0, 0, .Exact},
		{"viewport offset boundary", 4, 16, 4, 4, .Exact},
		{"end of line", 9, 21, 9, 9, .Exact},
		{"end of buffer", 0, 22, 0, 0, .Exact},
	}
	for fixture, index in fixtures {
		hit := pointer_text_hit_fixture(
			fixture.display,
			fixture.position,
			fixture.start,
			fixture.end,
			fixture.affinity,
			u64(index + 1),
		)
		testing.expectf(t, text_hit_is_valid(hit), "%s text hit was invalid", fixture.name)
	}
}

/* Verifies clipped, padding, stale, and noncanonical shapes cannot become valid text hits. */
@(test)
pointer_text_hit_contract_rejects_fabricated_shapes :: proc(t: ^testing.T) {
	valid := pointer_text_hit_fixture(2, 4, 2, 2, .Exact, 1)
	fixtures := [?]struct {
		name: string,
		hit:  Text_Hit,
	} {
		{"missing snapshot", Text_Hit{}},
		{"wrong canonical buffer", valid},
		{"wrong canonical revision", valid},
		{"column before represented span", valid},
		{"column after represented span", valid},
		{"reversed represented span", valid},
		{"invalid affinity", valid},
	}
	fixtures[1].hit.position.buffer_id = 18
	fixtures[2].hit.position.revision = 8
	fixtures[3].hit.display.column = 1
	fixtures[4].hit.display.column = 3
	fixtures[5].hit.span_start = 3
	fixtures[6].hit.affinity = .Invalid
	for fixture in fixtures {
		testing.expectf(t, !text_hit_is_valid(fixture.hit), "%s text hit was accepted", fixture.name)
	}
}

/* Verifies a copied semantic hit cannot retain display-snapshot storage. */
@(test)
pointer_text_hit_is_compact_and_pointer_free :: proc(t: ^testing.T) {
	testing.expect(t, size_of(Text_Hit) <= 104)
}

/* Verifies canonical mapping across tabs, wide Unicode, graphemes, EOL, EOF, and padding. */
@(test)
pointer_text_mapping_resolves_only_represented_cells :: proc(t: ^testing.T) {
	fixture: Projection_Fixture
	if !projection_fixture_init(t, &fixture, 121, "\t界e\u0301\n🙂x") do return
	defer projection_fixture_close(&fixture)
	logical, _, _ := editor_view.snapshot(&fixture.registry, fixture.handle)
	snapshot, projected, failure := project(
		&fixture.buffer,
		projection_request(31, logical, Viewport_Constraints{width_cells = 12, height_rows = 2}),
	)
	testing.expectf(t, projected, "projection failed with %v", failure.code)
	if !projected do return
	defer snapshot_close(&snapshot)
	fixtures := [?]struct {
		name:     string,
		row:      Display_Row_Index,
		column:   Display_Column,
		offset:   editor.Byte_Offset,
		affinity: Text_Hit_Affinity,
	} {
		{"tab start", 0, 0, 0, .Exact},
		{"tab leading half", 0, 1, 0, .Leading},
		{"tab trailing half", 0, 2, 1, .Trailing},
		{"wide glyph trailing cell", 0, 5, 4, .Trailing},
		{"combining grapheme", 0, 6, 4, .Exact},
		{"end of line", 0, 7, 7, .Exact},
		{"emoji trailing cell", 1, 1, 12, .Trailing},
		{"end of buffer", 1, 3, 13, .Exact},
	}
	for fixture in fixtures {
		hit, mapped, map_failure := snapshot_display_to_text_hit(
			snapshot,
			Display_Position{viewport_row = fixture.row, column = fixture.column},
		)
		testing.expectf(t, mapped, "%s failed with %v", fixture.name, map_failure.code)
		if mapped {
			testing.expect(t, text_hit_is_valid(hit))
			testing.expect_value(t, hit.position.byte_offset, fixture.offset)
			testing.expect_value(t, hit.affinity, fixture.affinity)
		}
	}
	_, padding_mapped, padding_failure := snapshot_display_to_text_hit(
		snapshot,
		Display_Position{viewport_row = 0, column = 8},
	)
	testing.expect(t, !padding_mapped)
	testing.expect_value(t, padding_failure.code, Failure_Code.Mapping_Miss)
}

/* Verifies viewport offsets preserve canonical identity and reject clipped clusters. */
@(test)
pointer_text_mapping_honors_viewport_clipping :: proc(t: ^testing.T) {
	fixture: Projection_Fixture
	if !projection_fixture_init(t, &fixture, 123, "\t界alpha\nsecond") do return
	defer projection_fixture_close(&fixture)
	origin, _, _ := editor.buffer_position(&fixture.buffer, editor.Byte_Offset(0))
	viewport_ok, _ := editor_view.set_viewport(&fixture.registry, fixture.handle, origin, 1)
	testing.expect(t, viewport_ok)
	logical, _, _ := editor_view.snapshot(&fixture.registry, fixture.handle)
	snapshot, projected, _ := project(
		&fixture.buffer,
		projection_request(33, logical, Viewport_Constraints{width_cells = 5, height_rows = 1}),
	)
	testing.expect(t, projected)
	if !projected do return
	defer snapshot_close(&snapshot)
	_, clipped_mapped, clipped_failure := snapshot_display_to_text_hit(
		snapshot,
		Display_Position{viewport_row = 0, column = 0},
	)
	testing.expect(t, !clipped_mapped)
	testing.expect_value(t, clipped_failure.code, Failure_Code.Mapping_Miss)
	hit, mapped, _ := snapshot_display_to_text_hit(
		snapshot,
		Display_Position{viewport_row = 0, column = 3},
	)
	testing.expect(t, mapped)
	if mapped {
		testing.expect_value(t, hit.position.byte_offset, editor.Byte_Offset(1))
		testing.expect_value(t, hit.display.column, Display_Column(3))
		testing.expect_value(t, hit.snapshot_id, Snapshot_ID(33))
		testing.expect_value(t, hit.view_state_generation, logical.state_generation)
	}
}

/* Verifies vertical viewport origin, unused rows, bounds, and closed owners reject safely. */
@(test)
pointer_text_mapping_rejects_unrepresented_rows_and_closed_snapshots :: proc(t: ^testing.T) {
	fixture: Projection_Fixture
	if !projection_fixture_init(t, &fixture, 125, "first\nsecond") do return
	defer projection_fixture_close(&fixture)
	second, _, _ := editor.buffer_position(&fixture.buffer, editor.Byte_Offset(6))
	viewport_ok, _ := editor_view.set_viewport(&fixture.registry, fixture.handle, second, 0)
	testing.expect(t, viewport_ok)
	logical, _, _ := editor_view.snapshot(&fixture.registry, fixture.handle)
	snapshot, projected, _ := project(
		&fixture.buffer,
		projection_request(35, logical, Viewport_Constraints{width_cells = 8, height_rows = 2}),
	)
	testing.expect(t, projected)
	if !projected do return
	hit, mapped, _ := snapshot_display_to_text_hit(snapshot, Display_Position{})
	testing.expect(t, mapped)
	if mapped {
		testing.expect_value(t, hit.position.byte_offset, editor.Byte_Offset(6))
		testing.expect_value(t, hit.logical_line, Logical_Line_Index(1))
	}
	_, unused_mapped, _ := snapshot_display_to_text_hit(
		snapshot,
		Display_Position{viewport_row = 1, column = 0},
	)
	testing.expect(t, !unused_mapped)
	_, outside_mapped, _ := snapshot_display_to_text_hit(
		snapshot,
		Display_Position{viewport_row = 0, column = 8},
	)
	testing.expect(t, !outside_mapped)
	snapshot_close(&snapshot)
	_, closed_mapped, closed_failure := snapshot_display_to_text_hit(snapshot, {})
	testing.expect(t, !closed_mapped)
	testing.expect_value(t, closed_failure.code, Failure_Code.Closed_Snapshot)
}

/* Verifies drag clamping stays on represented text and region projection stays canonical. */
@(test)
pointer_text_mapping_clamps_to_semantic_region_boundaries :: proc(t: ^testing.T) {
	fixture: Projection_Fixture
	if !projection_fixture_init(t, &fixture, 127, "abcdef\nxy") do return
	defer projection_fixture_close(&fixture)
	mark, _, _ := editor.buffer_position(&fixture.buffer, editor.Byte_Offset(1))
	point, _, _ := editor.buffer_position(&fixture.buffer, editor.Byte_Offset(8))
	mark_ok, _ := editor_view.set_mark(&fixture.registry, fixture.handle, mark, true)
	point_ok, _ := editor_view.set_point(&fixture.registry, fixture.handle, point)
	testing.expect(t, mark_ok && point_ok)
	logical, _, _ := editor_view.snapshot(&fixture.registry, fixture.handle)
	snapshot, projected, _ := project(
		&fixture.buffer,
		projection_request(37, logical, Viewport_Constraints{width_cells = 4, height_rows = 3}),
	)
	testing.expect(t, projected)
	if !projected do return
	defer snapshot_close(&snapshot)
	fixtures := [?]struct {
		name:   string,
		row:    i64,
		column: i64,
		offset: editor.Byte_Offset,
	} {
		{"above and left", -4, -9, 0},
		{"right of clipped row", 0, 90, 4},
		{"short-row padding", 1, 3, 9},
		{"below and right", 20, 90, 9},
	}
	for fixture in fixtures {
		hit, mapped, failure := snapshot_clamp_display_to_text_hit(
			snapshot,
			fixture.row,
			fixture.column,
		)
		testing.expectf(t, mapped, "%s clamp failed with %v", fixture.name, failure.code)
		if mapped do testing.expect_value(t, hit.position.byte_offset, fixture.offset)
	}
	view, viewed, _ := snapshot_view(snapshot)
	testing.expect(t, viewed && view.region.active)
	if viewed {
		testing.expect_value(t, view.region.start, editor.Byte_Offset(1))
		testing.expect_value(t, view.region.end, editor.Byte_Offset(8))
		testing.expect(t, view.region.start_visible && view.region.end_visible)
		testing.expect_value(t, view.region.start_viewport_row, Display_Row_Index(0))
		testing.expect_value(t, view.region.start_column, Display_Column(1))
		testing.expect_value(t, view.region.end_viewport_row, Display_Row_Index(1))
		testing.expect_value(t, view.region.end_column, Display_Column(1))
	}
}

@(test)
/* Rejects pointer mapping when its explicit per-event work budget is exhausted. */
pointer_text_mapping_enforces_work_budget :: proc(t: ^testing.T) {
	fixture: Projection_Fixture
	if !projection_fixture_init(t, &fixture, 129, "abcdef") do return
	defer projection_fixture_close(&fixture)
	logical, _, _ := editor_view.snapshot(&fixture.registry, fixture.handle)
	snapshot, projected, _ := project(
		&fixture.buffer,
		projection_request(39, logical, Viewport_Constraints{width_cells = 4, height_rows = 2}),
	)
	testing.expect(t, projected)
	if !projected do return
	defer snapshot_close(&snapshot)

	_, mapped, failure := snapshot_clamp_display_to_text_hit(snapshot, 0, 3, 1)
	testing.expect(t, !mapped)
	testing.expect_value(t, failure.code, Failure_Code.Work_Limit)
	testing.expect_value(t, failure.limit, u64(1))
}

@(private)
pointer_text_hit_fixture :: proc(
	display_column: Display_Column,
	position: editor.Byte_Offset,
	span_start, span_end: Display_Column,
	affinity: Text_Hit_Affinity,
	line: u64,
) -> Text_Hit {
	return Text_Hit {
		snapshot_id = 41,
		buffer_id = 17,
		buffer_revision = 7,
		view_id = 23,
		view_generation = 3,
		view_state_generation = 11,
		display = {viewport_row = Display_Row_Index(line - 1), column = display_column},
		position = {buffer_id = 17, revision = 7, byte_offset = position},
		logical_line = Logical_Line_Index(line),
		span_start = span_start,
		span_end = span_end,
		affinity = affinity,
	}
}
