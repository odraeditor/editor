// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package display

import "../editor"
import editor_view "../view"
import "../search"
import "core:testing"

/* Complete lines covered by checked view ranges are absent from projection. */
@(test)
hidden_lines_are_omitted_from_projection :: proc(t: ^testing.T) {
	fixture: Projection_Fixture
	ready := projection_fixture_init(t, &fixture, 59, "heading\nhidden one\nhidden two\nvisible\n")
	if !ready do return
	defer projection_fixture_close(&fixture)
	start, start_ok, _ := editor.buffer_position(&fixture.buffer, 8)
	end, end_ok, _ := editor.buffer_position(&fixture.buffer, 30)
	testing.expect(t, start_ok && end_ok)
	if !start_ok || !end_ok do return
	_, replaced, replace_failure := editor_view.visibility_replace(
		&fixture.registry,
		fixture.handle,
		[]editor_view.Hidden_Range{{start = start, end = end}},
	)
	testing.expectf(t, replaced, "visibility replacement failed with %v", replace_failure.code)
	if !replaced do return
	logical, logical_ok, _ := editor_view.snapshot(&fixture.registry, fixture.handle)
	testing.expect(t, logical_ok)
	request := projection_request(59, logical, {width_cells = 32, height_rows = 3})
	snapshot, projected, projection_failure := project_view(
		&fixture.buffer,
		&fixture.registry,
		fixture.handle,
		request,
	)
	testing.expectf(t, projected, "hidden-line projection failed with %v", projection_failure.code)
	if !projected do return
	defer snapshot_close(&snapshot)
	projected_view, viewed, _ := snapshot_view(snapshot)
	testing.expect(t, viewed)
	if !viewed do return
	testing.expect_value(t, projected_view.rows[0].source_start, editor.Byte_Offset(0))
	testing.expect_value(t, projected_view.rows[1].source_start, editor.Byte_Offset(30))
	testing.expect_value(t, projected_view.rows[1].logical_line, Logical_Line_Index(3))
	testing.expect_value(t, projected_view.rows[2].source_start, editor.Byte_Offset(38))
	testing.expect_value(t, projected_view.rows[2].logical_line, Logical_Line_Index(4))
}

/* Verifies search matches remain revisioned across clipping, scrolling, and resize. */
@(test)
maps_current_and_secondary_search_matches :: proc(t: ^testing.T) {
	fixture: Projection_Fixture
	ready := projection_fixture_init(t, &fixture, 50, "needle one\nneedle two")
	if !ready {
		return
	}
	defer projection_fixture_close(&fixture)
	occurrences := [2]search.Occurrence {
		{buffer_id = 50, revision = 0, start = 0, end = 6},
		{buffer_id = 50, revision = 0, start = 11, end = 17},
	}
	logical, logical_ok, _ := editor_view.snapshot(&fixture.registry, fixture.handle)
	testing.expect(t, logical_ok)
	search_snapshot := editor_view.Search_Snapshot {
		present = true,
		interaction_generation = 1,
		source_revision = 0,
		direction = .Forward,
		scope = search.Scope{buffer_id = 50, revision = 0, start = 0, end = 21},
		status = .Active,
		query = "needle",
		last_successful_query = "needle",
		effective_case = .Insensitive,
		has_current = true,
		current_index = 0,
		occurrences = occurrences[:],
	}
	first_request := projection_request(10, logical, Viewport_Constraints{width_cells = 10, height_rows = 1})
	first_request.search = search_snapshot
	first_snapshot, first_ok, first_failure := project(
		&fixture.buffer,
		first_request,
	)
	testing.expectf(t, first_ok, "search projection failed with %v", first_failure.code)
	if first_ok {
		first, _, _ := snapshot_view(first_snapshot)
		testing.expect_value(t, len(first.search_matches), 2)
		testing.expect(t, first.search_matches[0].current)
		testing.expect(t, first.search_matches[0].start_visible)
		testing.expect(t, first.search_matches[0].end_visible)
		testing.expect(t, !first.search_matches[1].intersects_visible)
		testing.expect(t, first.accounting.search_match_bytes > 0)
		snapshot_close(&first_snapshot)
	}
	line_search := search_snapshot
	line_search.presentation = .Lines
	line_request := projection_request(13, logical, Viewport_Constraints{width_cells = 20, height_rows = 2})
	line_request.search = line_search
	line_snapshot, line_ok, line_failure := project(&fixture.buffer, line_request)
	testing.expectf(t, line_ok, "line search projection failed with %v", line_failure.code)
	if line_ok {
		line_view, _, _ := snapshot_view(line_snapshot)
		testing.expect_value(t, line_view.search_matches[0].start, editor.Byte_Offset(0))
		testing.expect_value(t, line_view.search_matches[0].end, editor.Byte_Offset(11))
		testing.expect_value(t, line_view.search_matches[1].start, editor.Byte_Offset(11))
		testing.expect_value(t, line_view.search_matches[1].end, editor.Byte_Offset(21))
		snapshot_close(&line_snapshot)
	}

	second_line, _, _ := editor.buffer_position(&fixture.buffer, 11)
	scrolled, _ := editor_view.set_viewport(&fixture.registry, fixture.handle, second_line, 0)
	testing.expect(t, scrolled)
	logical, _, _ = editor_view.snapshot(&fixture.registry, fixture.handle)
	search_snapshot = editor_view.Search_Snapshot {
		present = true,
		interaction_generation = 1,
		source_revision = 0,
		direction = .Forward,
		scope = search.Scope{buffer_id = 50, revision = 0, start = 0, end = 21},
		status = .Active,
		query = "needle",
		last_successful_query = "needle",
		effective_case = .Insensitive,
		has_current = true,
		current_index = 0,
		occurrences = occurrences[:],
	}
	clipped_request := projection_request(11, logical, Viewport_Constraints{width_cells = 4, height_rows = 1})
	clipped_request.search = search_snapshot
	clipped_snapshot, clipped_ok, _ := project(
		&fixture.buffer,
		clipped_request,
	)
	testing.expect(t, clipped_ok)
	if clipped_ok {
		clipped, _, _ := snapshot_view(clipped_snapshot)
		testing.expect(t, !clipped.search_matches[0].intersects_visible)
		testing.expect(t, clipped.search_matches[1].intersects_visible)
		testing.expect(t, clipped.search_matches[1].start_visible)
		testing.expect(t, clipped.search_matches[1].clipped_end)
		snapshot_close(&clipped_snapshot)
	}
	resized_request := projection_request(12, logical, Viewport_Constraints{width_cells = 12, height_rows = 1})
	resized_request.search = search_snapshot
	resized_snapshot, resized_ok, _ := project(
		&fixture.buffer,
		resized_request,
	)
	testing.expect(t, resized_ok)
	if resized_ok {
		resized, _, _ := snapshot_view(resized_snapshot)
		testing.expect(t, resized.search_matches[1].start_visible)
		testing.expect(t, resized.search_matches[1].end_visible)
		testing.expect(t, !resized.search_matches[1].clipped_end)
		snapshot_close(&resized_snapshot)
	}
}

/* Verifies ASCII rows, cursor and region mappings, and deterministic unused rows. */
@(test)
maps_rows_cursor_region_and_unused_space :: proc(t: ^testing.T) {
	fixture: Projection_Fixture
	ready := projection_fixture_init(t, &fixture, 51, "alpha\nbeta")
	if !ready {
		return
	}
	defer projection_fixture_close(&fixture)
	cursor, _, _ := editor.buffer_position(&fixture.buffer, editor.Byte_Offset(2))
	mark, _, _ := editor.buffer_position(&fixture.buffer, editor.Byte_Offset(8))
	cursor_ok, _ := editor_view.set_point(&fixture.registry, fixture.handle, cursor)
	mark_ok, _ := editor_view.set_mark(&fixture.registry, fixture.handle, mark)
	testing.expect(t, cursor_ok && mark_ok)

	logical, logical_ok, _ := editor_view.snapshot(&fixture.registry, fixture.handle)
	snapshot, projected, failure := project(
		&fixture.buffer,
		projection_request(1, logical, Viewport_Constraints{width_cells = 12, height_rows = 4}),
	)
	testing.expectf(t, logical_ok && projected, "projection failed with %v", failure.code)
	if !logical_ok || !projected {
		return
	}
	defer snapshot_close(&snapshot)
	result, viewed, _ := snapshot_view(snapshot)
	testing.expect(t, viewed)
	testing.expect_value(t, result.text, "alphabeta")
	testing.expect_value(t, len(result.rows), 4)
	testing.expect(t, result.rows[0].has_content && result.rows[1].has_content)
	testing.expect(t, !result.rows[2].has_content && !result.rows[3].has_content)
	testing.expect_value(t, result.rows[0].logical_line, Logical_Line_Index(0))
	testing.expect_value(t, result.rows[1].logical_line, Logical_Line_Index(1))
	testing.expect(t, result.cursor.visible)
	testing.expect_value(t, result.cursor.viewport_row, Display_Row_Index(0))
	testing.expect_value(t, result.cursor.column, Display_Column(2))
	testing.expect(t, result.region.active)
	testing.expect(t, result.region.start_visible && result.region.end_visible)
	testing.expect_value(t, result.region.start_viewport_row, Display_Row_Index(0))
	testing.expect_value(t, result.region.start_column, Display_Column(2))
	testing.expect_value(t, result.region.end_viewport_row, Display_Row_Index(1))
	testing.expect_value(t, result.region.end_column, Display_Column(2))
}

/* Verifies rectangular regions project one independent range per logical row. */
@(test)
maps_rectangular_region_per_logical_row :: proc(t: ^testing.T) {
	fixture: Projection_Fixture
	if !projection_fixture_init(t, &fixture, 54, "abcd\nxy\nαβγδ\n") do return
	defer projection_fixture_close(&fixture)
	anchor, anchor_ok, _ := editor.buffer_position(&fixture.buffer, 1)
	point, point_ok, _ := editor.buffer_position(&fixture.buffer, 10)
	testing.expect(t, anchor_ok && point_ok)
	selected, select_failure := editor_view.select_range(
		&fixture.registry, fixture.handle, anchor, point, 1, .Rectangle, .Grapheme,
	)
	testing.expectf(t, selected, "rectangle selection failed with %v", select_failure.code)
	if !selected do return
	logical, logical_ok, _ := editor_view.snapshot(&fixture.registry, fixture.handle)
	testing.expect(t, logical_ok)
	snapshot, projected, failure := project(
		&fixture.buffer,
		projection_request(14, logical, Viewport_Constraints{width_cells = 12, height_rows = 4}),
	)
	testing.expectf(t, projected, "rectangle projection failed with %v", failure.code)
	if !projected do return
	defer snapshot_close(&snapshot)
	result, viewed, _ := snapshot_view(snapshot)
	testing.expect(t, viewed)
	testing.expect(t, result.region.active && result.region.rectangular)
	testing.expect_value(t, len(result.rows), 4)
	testing.expect(t, result.rows[0].region_active)
	testing.expect_value(t, result.rows[0].region_start, editor.Byte_Offset(1))
	testing.expect_value(t, result.rows[0].region_end, editor.Byte_Offset(2))
	testing.expect(t, result.rows[1].region_active)
	testing.expect_value(t, result.rows[1].region_start, editor.Byte_Offset(6))
	testing.expect_value(t, result.rows[1].region_end, editor.Byte_Offset(7))
	testing.expect(t, result.rows[2].region_active)
	testing.expect_value(t, result.rows[2].region_start, editor.Byte_Offset(10))
	testing.expect_value(t, result.rows[2].region_end, editor.Byte_Offset(12))
	testing.expect(t, !result.rows[3].region_active)
}

/* Verifies inactive, empty, reverse, and clipped Unicode regions remain logical. */
@(test)
maps_region_without_cell_bounds :: proc(t: ^testing.T) {
	fixture: Projection_Fixture
	ready := projection_fixture_init(t, &fixture, 52, "\t界e\u0301🙂Z")
	if !ready {
		return
	}
	defer projection_fixture_close(&fixture)
	start, _, _ := editor.buffer_position(&fixture.buffer, editor.Byte_Offset(0))
	end, _, _ := editor.buffer_position(&fixture.buffer, editor.Byte_Offset(11))
	point_ok, _ := editor_view.set_point(&fixture.registry, fixture.handle, end)
	mark_ok, _ := editor_view.set_mark(&fixture.registry, fixture.handle, start, false)
	testing.expect(t, point_ok && mark_ok)
	inactive, _, _ := editor_view.snapshot(&fixture.registry, fixture.handle)
	inactive_snapshot, inactive_ok, _ := project(
		&fixture.buffer,
		projection_request(11, inactive, Viewport_Constraints{width_cells = 6, height_rows = 1}),
	)
	testing.expect(t, inactive_ok)
	if inactive_ok {
		inactive_view, _, _ := snapshot_view(inactive_snapshot)
		testing.expect(t, !inactive_view.region.active)
		snapshot_close(&inactive_snapshot)
	}

	active_ok, _ := editor_view.set_region_active(&fixture.registry, fixture.handle, true)
	viewport_ok, _ := editor_view.set_viewport(&fixture.registry, fixture.handle, start, 3)
	testing.expect(t, active_ok && viewport_ok)
	active, _, _ := editor_view.snapshot(&fixture.registry, fixture.handle)
	active_snapshot, projected, failure := project(
		&fixture.buffer,
		projection_request(12, active, Viewport_Constraints{width_cells = 6, height_rows = 1}),
	)
	testing.expectf(t, projected, "region projection failed with %v", failure.code)
	if projected {
		projected_view, _, _ := snapshot_view(active_snapshot)
		testing.expect_value(t, projected_view.text, "界e\u0301🙂")
		testing.expect(t, projected_view.region.active)
		testing.expect_value(t, projected_view.region.start, editor.Byte_Offset(0))
		testing.expect_value(t, projected_view.region.end, editor.Byte_Offset(11))
		testing.expect(t, !projected_view.region.start_visible)
		testing.expect(t, projected_view.region.end_visible)
		testing.expect_value(t, projected_view.region.end_column, Display_Column(6))
		snapshot_close(&active_snapshot)
	}

	point_at_start, _ := editor_view.set_point(&fixture.registry, fixture.handle, start)
	mark_at_start, _ := editor_view.set_mark(&fixture.registry, fixture.handle, start, true)
	testing.expect(t, point_at_start && mark_at_start)
	empty, _, _ := editor_view.snapshot(&fixture.registry, fixture.handle)
	empty_snapshot, empty_ok, _ := project(
		&fixture.buffer,
		projection_request(13, empty, Viewport_Constraints{width_cells = 6, height_rows = 1}),
	)
	testing.expect(t, empty_ok)
	if empty_ok {
		empty_view, _, _ := snapshot_view(empty_snapshot)
		testing.expect(t, empty_view.region.active)
		testing.expect_value(t, empty_view.region.start, empty_view.region.end)
		snapshot_close(&empty_snapshot)
	}
}

/* Verifies tabs, wide text, combining text, emoji, and cluster-safe horizontal clipping. */
@(test)
projection_expands_and_clips_unicode_clusters :: proc(t: ^testing.T) {
	fixture: Projection_Fixture
	ready := projection_fixture_init(t, &fixture, 53, "\t界e\u0301🙂Z")
	if !ready {
		return
	}
	defer projection_fixture_close(&fixture)
	cursor, _, _ := editor.buffer_position(&fixture.buffer, editor.Byte_Offset(4))
	origin, _, _ := editor.buffer_position(&fixture.buffer, editor.Byte_Offset(0))
	cursor_ok, _ := editor_view.set_point(&fixture.registry, fixture.handle, cursor)
	viewport_ok, _ := editor_view.set_viewport(&fixture.registry, fixture.handle, origin, 3)
	testing.expect(t, cursor_ok && viewport_ok)
	logical, _, _ := editor_view.snapshot(&fixture.registry, fixture.handle)
	snapshot, projected, failure := project(
		&fixture.buffer,
		projection_request(2, logical, Viewport_Constraints{width_cells = 6, height_rows = 1}),
	)
	testing.expectf(t, projected, "projection failed with %v", failure.code)
	if !projected {
		return
	}
	defer snapshot_close(&snapshot)
	result, viewed, _ := snapshot_view(snapshot)
	testing.expect(t, viewed)
	testing.expect_value(t, result.text, "界e\u0301🙂")
	testing.expect_value(t, result.rows[0].run_count, u32(1))
	run := result.runs[result.rows[0].first_run]
	testing.expect_value(t, run.start_column, Display_Column(4))
	testing.expect_value(t, run.cell_count, u32(5))
	testing.expect(t, result.rows[0].clipped_left && result.rows[0].clipped_right)
	testing.expect(t, result.cursor.visible)
	testing.expect_value(t, result.cursor.column, Display_Column(3))
}

/* Verifies empty and trailing-empty logical lines remain distinct content rows. */
@(test)
projection_preserves_empty_logical_lines :: proc(t: ^testing.T) {
	fixture: Projection_Fixture
	ready := projection_fixture_init(t, &fixture, 55, "a\n")
	if !ready {
		return
	}
	defer projection_fixture_close(&fixture)
	logical, _, _ := editor_view.snapshot(&fixture.registry, fixture.handle)
	snapshot, projected, _ := project(
		&fixture.buffer,
		projection_request(3, logical, Viewport_Constraints{width_cells = 4, height_rows = 3}),
	)
	testing.expect(t, projected)
	if !projected {
		return
	}
	defer snapshot_close(&snapshot)
	result, _, _ := snapshot_view(snapshot)
	testing.expect(t, result.rows[0].has_content)
	testing.expect(t, result.rows[1].has_content)
	testing.expect(t, !result.rows[2].has_content)
	testing.expect_value(t, result.rows[1].logical_line, Logical_Line_Index(1))
	testing.expect_value(t, result.rows[1].source_start, editor.Byte_Offset(2))
	testing.expect_value(t, result.rows[1].source_end, editor.Byte_Offset(2))
}

/* Verifies CRLF is structural while isolated carriage returns cannot control the terminal. */
@(test)
preserves_crlf_mapping_and_replaces_isolated_cr :: proc(t: ^testing.T) {
	fixture: Projection_Fixture
	ready := projection_fixture_init(t, &fixture, 56, "first\r\nsecond\rthird")
	if !ready {
		return
	}
	defer projection_fixture_close(&fixture)
	logical, _, _ := editor_view.snapshot(&fixture.registry, fixture.handle)
	snapshot, projected, failure := project(
		&fixture.buffer,
		projection_request(31, logical, Viewport_Constraints{width_cells = 20, height_rows = 2}),
	)
	testing.expectf(t, projected, "CR projection failed with %v", failure.code)
	if !projected {
		return
	}
	defer snapshot_close(&snapshot)
	result, viewed, _ := snapshot_view(snapshot)
	testing.expect(t, viewed)
	testing.expect_value(t, result.text, "firstsecond\uFFFDthird")
	testing.expect(t, !result.rows[0].used_replacement)
	testing.expect(t, result.rows[1].used_replacement)
}

/* Verifies stale logical snapshots and bounded source work fail before publication. */
@(test)
rejects_stale_and_overlong_grapheme_work :: proc(t: ^testing.T) {
	fixture: Projection_Fixture
	ready := projection_fixture_init(t, &fixture, 57, "abcdef")
	if !ready {
		return
	}
	defer projection_fixture_close(&fixture)
	stale, _, _ := editor_view.snapshot(&fixture.registry, fixture.handle)
	start, _, _ := editor.buffer_position(&fixture.buffer, editor.Byte_Offset(0))
	end, _, _ := editor.buffer_position(&fixture.buffer, editor.Byte_Offset(1))
	_, _, published, _ := editor.buffer_splice(
		&fixture.buffer,
		editor.Splice{start = start, end = end, replacement = "x"},
		context.temp_allocator,
	)
	testing.expect(t, published)
	_, stale_projected, stale_failure := project(
		&fixture.buffer,
		projection_request(4, stale, Viewport_Constraints{width_cells = 4, height_rows = 1}),
	)
	testing.expect(t, !stale_projected)
	testing.expect_value(t, stale_failure.code, Failure_Code.Stale_Snapshot)

	combining: Projection_Fixture
	combining_ready := projection_fixture_init(t, &combining, 59, "e\u0301\u0301\u0301")
	if !combining_ready {
		return
	}
	defer projection_fixture_close(&combining)
	logical, _, _ := editor_view.snapshot(&combining.registry, combining.handle)
	request := projection_request(5, logical, Viewport_Constraints{width_cells = 4, height_rows = 1})
	request.limits.source_bytes = 4
	_, bounded, bounded_failure := project(&combining.buffer, request)
	testing.expect(t, !bounded)
	testing.expect_value(t, bounded_failure.code, Failure_Code.Source_Byte_Limit)
}

/* Verifies snapshot close invalidates its owner and reports deterministic cleanup. */
@(test)
projection_snapshot_close_is_terminal :: proc(t: ^testing.T) {
	fixture: Projection_Fixture
	ready := projection_fixture_init(t, &fixture, 61, "close")
	if !ready {
		return
	}
	defer projection_fixture_close(&fixture)
	logical, _, _ := editor_view.snapshot(&fixture.registry, fixture.handle)
	snapshot, projected, _ := project(
		&fixture.buffer,
		projection_request(6, logical, Viewport_Constraints{width_cells = 8, height_rows = 1}),
	)
	testing.expect(t, projected)
	if !projected {
		return
	}
	closed, _ := snapshot_close(&snapshot)
	testing.expect(t, closed)
	_, viewed, view_failure := snapshot_view(snapshot)
	testing.expect(t, !viewed)
	testing.expect_value(t, view_failure.code, Failure_Code.Closed_Snapshot)
}

/* Verifies resize produces a new projection without mutating the logical view. */
@(test)
recomputes_rows_for_changed_constraints :: proc(t: ^testing.T) {
	fixture: Projection_Fixture
	ready := projection_fixture_init(t, &fixture, 63, "abcdefghij")
	if !ready {
		return
	}
	defer projection_fixture_close(&fixture)
	logical, _, _ := editor_view.snapshot(&fixture.registry, fixture.handle)
	narrow, narrow_ok, narrow_failure := project(
		&fixture.buffer,
		projection_request(7, logical, Viewport_Constraints{width_cells = 4, height_rows = 1}),
	)
	testing.expectf(t, narrow_ok, "narrow projection failed with %v", narrow_failure.code)
	if !narrow_ok {
		return
	}
	defer snapshot_close(&narrow)
	wide, wide_ok, wide_failure := project(
		&fixture.buffer,
		projection_request(8, logical, Viewport_Constraints{width_cells = 8, height_rows = 1}),
	)
	testing.expectf(t, wide_ok, "wide projection failed with %v", wide_failure.code)
	if !wide_ok {
		return
	}
	defer snapshot_close(&wide)
	narrow_result, _, _ := snapshot_view(narrow)
	wide_result, _, _ := snapshot_view(wide)
	testing.expect_value(t, narrow_result.text, "abcd")
	testing.expect(t, narrow_result.rows[0].clipped_right)
	testing.expect_value(t, wide_result.text, "abcdefgh")
	testing.expect(t, wide_result.rows[0].clipped_right)
	_, compatibility_failure := snapshot_is_compatible(
		narrow,
		logical,
		Viewport_Constraints{width_cells = 8, height_rows = 1},
		terminal_unicode17_profile(),
	)
	testing.expect_value(t, compatibility_failure.code, Failure_Code.Incompatible_Snapshot)
	unchanged, _, _ := editor_view.snapshot(&fixture.registry, fixture.handle)
	testing.expect_value(t, unchanged.state_generation, logical.state_generation)
}

@(private)
Projection_Fixture :: struct {
	buffer:   editor.Buffer,
	registry: editor_view.Registry,
	handle:   editor_view.View_Handle,
}

@(private)
projection_fixture_init :: proc(
	t: ^testing.T,
	fixture: ^Projection_Fixture,
	id: u64,
	text: string,
) -> bool {
	assert(fixture != nil)
	buffer_ok, buffer_failure := editor.buffer_init(
		&fixture.buffer,
		editor.Buffer_ID(id),
		text,
		editor.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	testing.expectf(t, buffer_ok, "buffer initialization failed with %v", buffer_failure.code)
	if !buffer_ok {
		return false
	}
	registry_ok, registry_failure := editor_view.registry_init(
		&fixture.registry,
		editor_view.Registry_ID(u32(id)),
		context.allocator,
	)
	testing.expectf(t, registry_ok, "registry initialization failed with %v", registry_failure.code)
	if !registry_ok {
		editor.buffer_close(&fixture.buffer)
		return false
	}
	handle, view_ok, view_failure := editor_view.create(&fixture.registry, &fixture.buffer)
	testing.expectf(t, view_ok, "view creation failed with %v", view_failure.code)
	if !view_ok {
		editor_view.registry_close(&fixture.registry)
		editor.buffer_close(&fixture.buffer)
		return false
	}
	fixture.handle = handle
	return true
}

@(private)
projection_fixture_close :: proc(fixture: ^Projection_Fixture) {
	if fixture.handle.view_id != editor_view.View_ID(0) {
		editor_view.close(&fixture.registry, &fixture.handle)
	}
	if !fixture.registry.closed {
		editor_view.registry_close(&fixture.registry)
	}
	if editor.buffer_is_live(&fixture.buffer) {
		editor.buffer_close(&fixture.buffer)
	}
}

@(private)
projection_request :: proc(
	id: u64,
	logical: editor_view.Snapshot,
	constraints: Viewport_Constraints,
) -> Projection_Request {
	return Projection_Request {
		snapshot_id = Snapshot_ID(id),
		view = logical,
		constraints = constraints,
		profile = terminal_unicode17_profile(),
		limits = DEFAULT_RESOURCE_LIMITS,
		allocators = Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	}
}
