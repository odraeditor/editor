// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package gutter

import "base:runtime"
import "core:testing"

@(private = "file")
Factory_Failing_Allocator :: struct {
	backing:                runtime.Allocator,
	fail_after:             u64,
	successful_allocations: u64,
}

@(private = "file")
factory_failing_allocator_proc :: proc(
	allocator_data: rawptr,
	mode: runtime.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	location := #caller_location,
) -> ([]byte, runtime.Allocator_Error) {
	allocator := cast(^Factory_Failing_Allocator)allocator_data
	if mode == .Alloc || mode == .Alloc_Non_Zeroed || mode == .Resize ||
	   mode == .Resize_Non_Zeroed {
		if allocator.successful_allocations >= allocator.fail_after {
			return nil, .Out_Of_Memory
		}
		allocator.successful_allocations += 1
	}
	return allocator.backing.procedure(
		allocator.backing.data,
		mode,
		size,
		alignment,
		old_memory,
		old_size,
		location,
	)
}

@(private = "file")
factory_test_request :: proc(rows: []Visible_Row, line_count := u64(120)) -> Factory_Request {
	return Factory_Request {
		generation = 1,
		available_cells = 80,
		minimum_text_cells = MIN_TEXT_CELLS,
		line_count = line_count,
		viewport_rows = 4,
		rows = rows,
		cursor_logical_line = 9,
		cursor_visible = true,
		cursor_viewport_row = 1,
		policy = DEFAULT_FACTORY_POLICY,
		allocator = context.allocator,
		limits = DEFAULT_LIMITS,
	}
}

@(test)
/* gutter_factory_composes_relative_numbers_around_the_logical_cursor. */
relative_numbers_follow_cursor :: proc(t: ^testing.T) {
	rows := []Visible_Row {
		{viewport_row = 0, logical_line = 7, has_content = true},
		{viewport_row = 1, logical_line = 9, has_content = true},
		{viewport_row = 2, logical_line = 12, has_content = true},
	}
	request := factory_test_request(rows)
	request.policy.mode = .Relative
	request.policy.current_line = .Zero
	view, ok, failure := compose_factory(request)
	testing.expectf(t, ok, "relative factory failed with %v", failure.code)
	if !ok do return
	defer view_close(&view)
	testing.expect_value(t, string(view.text[0:8]), "   2 │")
	testing.expect_value(t, string(view.text[8:16]), "   0 │")
	testing.expect_value(t, string(view.text[16:24]), "   3 │")
}

@(test)
/* gutter_factory_composes_hybrid_numbers_with_one_absolute_current_line. */
hybrid_numbers_keep_current_absolute :: proc(t: ^testing.T) {
	rows := []Visible_Row {
		{viewport_row = 0, logical_line = 8, has_content = true},
		{viewport_row = 1, logical_line = 9, has_content = true},
		{viewport_row = 2, logical_line = 10, has_content = true},
	}
	request := factory_test_request(rows)
	request.policy.mode = .Hybrid
	view, ok, failure := compose_factory(request)
	testing.expectf(t, ok, "hybrid factory failed with %v", failure.code)
	if !ok do return
	defer view_close(&view)
	testing.expect_value(t, string(view.text[0:8]), "   1 │")
	testing.expect_value(t, string(view.text[8:16]), "  10 │")
	testing.expect_value(t, string(view.text[16:24]), "   1 │")
}

@(test)
/* gutter_factory_applies_current_line_presentation_independently. */
current_line_style_is_independent :: proc(t: ^testing.T) {
	rows := []Visible_Row{{viewport_row = 1, logical_line = 9, has_content = true}}
	request := factory_test_request(rows)
	request.policy.current_line = .Zero
	zero, zero_ok, _ := compose_factory(request)
	testing.expect(t, zero_ok)
	if !zero_ok do return
	testing.expect_value(t, string(zero.text[8:16]), "   0 │")
	view_close(&zero)
	request.policy.current_line = .Hidden
	hidden, hidden_ok, _ := compose_factory(request)
	testing.expect(t, hidden_ok)
	if !hidden_ok do return
	defer view_close(&hidden)
	testing.expect_value(t, string(hidden.text[8:16]), "     │")
}

@(test)
/* gutter_factory_places_numbering_on_the_configured_side. */
factory_places_numbering_on_the_configured_side :: proc(t: ^testing.T) {
	rows := []Visible_Row{{viewport_row = 0, logical_line = 8, has_content = true}}
	request := factory_test_request(rows)
	request.policy.side = .Right
	view, ok, failure := compose_factory(request)
	testing.expectf(t, ok, "right factory failed with %v", failure.code)
	if !ok do return
	defer view_close(&view)
	testing.expect_value(t, view.geometry.left_cells, u16(0))
	testing.expect_value(t, view.geometry.right_cells, u16(6))
	testing.expect_value(t, string(view.text[0:8]), "│   9 ")
	testing.expect_value(t, view.rows[0].right_role, Semantic_Role.Line_Number)
}

@(test)
/* gutter_factory_relative_numbering_uses_bounded_visible_work. */
relative_numbering_bounds_visible_work :: proc(t: ^testing.T) {
	rows := []Visible_Row {
		{viewport_row = 0, logical_line = 499_998, has_content = true},
		{viewport_row = 1, logical_line = 499_999, has_content = true},
		{viewport_row = 2, logical_line = 500_000, has_content = true},
	}
	request := factory_test_request(rows, 1_000_000)
	request.cursor_logical_line = 499_999
	request.policy.mode = .Relative
	view, ok, failure := compose_factory(request)
	testing.expectf(t, ok, "bounded relative factory failed with %v", failure.code)
	if !ok do return
	defer view_close(&view)
	testing.expect_value(t, view.accounting.work, request.viewport_rows)
	testing.expect_value(t, view.geometry.left_cells, u16(9))
}

@(test)
/* gutter_factory_composes_stable_absolute_line_numbers. */
factory_composes_stable_absolute_line_numbers :: proc(t: ^testing.T) {
	rows := []Visible_Row {
		{viewport_row = 0, logical_line = 8, has_content = true},
		{viewport_row = 1, logical_line = 9, has_content = true},
		{viewport_row = 2, logical_line = 10, has_content = true},
		{viewport_row = 3, logical_line = 0, has_content = false},
	}
	view, ok, failure := compose_factory(factory_test_request(rows))
	testing.expectf(t, ok, "factory failed with %v", failure.code)
	if !ok do return
	defer view_close(&view)
	testing.expect_value(t, view.geometry.left_cells, u16(6))
	testing.expect_value(t, view.geometry.text_cells, u32(74))
	testing.expect_value(t, len(view.rows), 4)
	testing.expect_value(t, string(view.text[0:8]), "   9 │")
	testing.expect_value(t, string(view.text[8:16]), "  10 │")
	testing.expect_value(t, string(view.text[16:24]), "  11 │")
	testing.expect_value(t, string(view.text[24:32]), "     │")
	testing.expect_value(t, view.rows[1].left_role, Semantic_Role.Current_Line_Number)
	testing.expect_value(t, view.accounting.visible_rows, u16(4))
}

@(test)
/* gutter_factory_reserves_four_number_columns_before_dynamic_growth. */
reserves_four_columns_before_growth :: proc(t: ^testing.T) {
	rows := []Visible_Row{{viewport_row = 0, logical_line = 0, has_content = true}}
	line_counts := [?]u64{1, 9, 10, 99, 100, 999, 1_000, 9_999}
	for line_count in line_counts {
		view, ok, _ := compose_factory(factory_test_request(rows, line_count))
		testing.expect(t, ok)
		if !ok do continue
		testing.expect_value(t, view.geometry.left_cells, u16(6))
		testing.expect_value(t, string(view.text), "   1 │     │     │     │")
		view_close(&view)
	}
	view, ok, _ := compose_factory(factory_test_request(rows, 10_000))
	testing.expect(t, ok)
	if !ok do return
	defer view_close(&view)
	testing.expect_value(t, view.geometry.left_cells, u16(7))
}

@(test)
/* gutter_factory_width_depends_on_total_lines_not_cursor_position. */
width_uses_total_lines_not_cursor :: proc(t: ^testing.T) {
	rows := []Visible_Row{{viewport_row = 0, logical_line = 0, has_content = true}}
	first, first_ok, _ := compose_factory(factory_test_request(rows, 9_999))
	testing.expect(t, first_ok)
	if !first_ok do return
	defer view_close(&first)
	rows[0].logical_line = 9_998
	last, last_ok, _ := compose_factory(factory_test_request(rows, 9_999))
	testing.expect(t, last_ok)
	if !last_ok do return
	defer view_close(&last)
	testing.expect_value(t, first.geometry.left_cells, last.geometry.left_cells)
}

@(test)
/* gutter_factory_none_preserves_complete_text_geometry. */
factory_none_preserves_complete_text_geometry :: proc(t: ^testing.T) {
	request := factory_test_request(nil)
	request.policy.mode = .None
	request.cursor_visible = false
	view, ok, _ := compose_factory(request)
	testing.expect(t, ok)
	if !ok do return
	closed, _ := view_close(&view)
	testing.expect(t, closed)
	testing.expect_value(t, view.generation, Generation(0))
	testing.expect(t, view.text == nil && view.rows == nil && view.allocator.procedure == nil)
}

@(test)
/* gutter_factory_rejects_visual_scope_without_reinterpreting_it. */
rejects_visual_scope_without_reinterpretation :: proc(t: ^testing.T) {
	request := factory_test_request(nil)
	request.policy.scope = .Visual
	_, ok, failure := compose_factory(request)
	testing.expect(t, !ok)
	testing.expect_value(t, failure.code, Failure_Code.Unsupported_Scope)
}

@(test)
/* gutter_factory_hides_the_lane_before_consuming_minimum_text_width. */
hides_lane_before_minimum_text_width :: proc(t: ^testing.T) {
	request := factory_test_request(nil)
	request.available_cells = MIN_TEXT_CELLS
	view, ok, failure := compose_factory(request)
	testing.expectf(t, ok, "narrow factory failed with %v", failure.code)
	if !ok do return
	defer view_close(&view)
	testing.expect_value(t, view.geometry.left_cells, u16(0))
	testing.expect_value(t, view.geometry.text_cells, MIN_TEXT_CELLS)
	testing.expect(t, view.rows == nil && view.text == nil)
}

@(test)
/* gutter_factory_contains_partial_allocation_failure. */
factory_contains_partial_allocation_failure :: proc(t: ^testing.T) {
	rows := []Visible_Row{{viewport_row = 0, logical_line = 0, has_content = true}}
	failing := Factory_Failing_Allocator{backing = context.allocator, fail_after = 1}
	request := factory_test_request(rows)
	request.allocator = runtime.Allocator {
		procedure = factory_failing_allocator_proc,
		data = &failing,
	}
	_, ok, failure := compose_factory(request)
	testing.expect(t, !ok)
	testing.expect_value(t, failure.code, Failure_Code.Allocation)
}
