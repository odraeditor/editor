// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_editing

import "../language"
import "core:testing"

/* Verifies display width, alignment, truncation, and grouping never rewrite stored source. */
@(test)
table_presentation_separates_display_policy_from_stored_cells :: proc(t: ^testing.T) {
	source := "| name | value |\n|---+---|\n| λ | 界 |\n"
	fixture: List_Test_Fixture
	if !list_test_fixture_open(t, &fixture, source, 1_801) do return
	defer list_test_fixture_close(&fixture)
	table, found := list_test_node(&fixture.analysis, .Pipe_Table, 0)
	testing.expect(t, found)
	if !found do return
	policies := [2]Table_Column_Policy{
		{width = 4, alignment = .Left, group_after = true},
		{width = 5, alignment = .Right},
	}
	presentation: Table_Presentation
	descriptor, prepared, failure := table_presentation_prepare(
		&presentation,
		&fixture.analysis,
		transmute([]u8)source,
		{operation_id = 121, scope = fixture.scope, table_id = table.id, columns = policies[:]},
	)
	testing.expectf(t, prepared, "presentation failed with %v", failure.code)
	if !prepared do return
	defer table_presentation_close(&presentation)
	testing.expect_value(t, descriptor.cells, u32(4))
	testing.expect_value(t, descriptor.truncated_cells, u32(0))
	text, inspected := table_presentation_text(&presentation)
	testing.expect(t, inspected)
	testing.expect_value(
		t,
		text,
		"| name || value |\n|------+-------|\n| λ    ||    界 |\n",
	)
	testing.expect_value(t, fixture.source, source)
	wide_cell, wide_found := list_test_node(&fixture.analysis, .Table_Cell, 3)
	testing.expect(t, wide_found)
	if wide_found {
		focused, focused_ok, focused_failure := table_focused_cell_inspect(
			&fixture.analysis,
			transmute([]u8)source,
			fixture.scope,
			wide_cell.id,
		)
		testing.expectf(t, focused_ok, "wide cell inspection failed with %v", focused_failure.code)
		if focused_ok {
			testing.expect_value(t, focused.row, u32(1))
			testing.expect_value(t, focused.column, u32(1))
			testing.expect_value(
				t,
				string(transmute([]u8)source[int(focused.selection.start):int(focused.selection.end)]),
				"界",
			)
		}
	}

	truncated_policies := [2]Table_Column_Policy{
		{width = 3, alignment = .Left, truncate = true},
		{width = 2, alignment = .Left, truncate = true},
	}
	table_presentation_close(&presentation)
	descriptor, prepared, failure = table_presentation_prepare(
		&presentation,
		&fixture.analysis,
		transmute([]u8)source,
		{operation_id = 122, scope = fixture.scope, table_id = table.id, columns = truncated_policies[:]},
	)
	testing.expectf(t, prepared, "truncated presentation failed with %v", failure.code)
	if !prepared do return
	testing.expect(t, descriptor.truncated_cells > 0)
	text, inspected = table_presentation_text(&presentation)
	testing.expect(t, inspected)
	testing.expect(t, len(text) > 0)
}

/* Verifies source alignment changes padding only and preserves affiliated syntax. */
@(test)
table_presentation_aligns_source_without_changing_values :: proc(t: ^testing.T) {
	source := "#+name: data\n| a | longer |\n| λ | 界 |\n#+TBLFM: $1=$2\n"
	fixture: List_Test_Fixture
	if !list_test_fixture_open(t, &fixture, source, 1_802) do return
	defer list_test_fixture_close(&fixture)
	table, found := list_test_node(&fixture.analysis, .Pipe_Table, 0)
	testing.expect(t, found)
	if !found do return
	policies := [2]Table_Column_Policy{
		{width = 2, alignment = .Right},
		{width = 6, alignment = .Left},
	}
	plan: language.Jan_Rewrite_Plan
	planned, failure := table_source_alignment_plan_prepare(
		&plan,
		&fixture.analysis,
		transmute([]u8)source,
		{operation_id = 123, scope = fixture.scope, table_id = table.id, columns = policies[:]},
		123,
	)
	testing.expectf(t, planned, "source alignment failed with %v", failure.code)
	if !planned do return
	defer language.jan_rewrite_plan_close(&plan)
	testing.expect(t, list_test_publish_and_history(
		&fixture,
		&plan,
		"#+name: data\n|  a | longer |\n|  λ | 界     |\n#+TBLFM: $1=$2\n",
	))
}

/* Verifies focused cell inspection and replacement retain table delimiters and metadata. */
@(test)
table_presentation_focuses_one_exact_cell :: proc(t: ^testing.T) {
	source := "#+caption: Demo\n| a | value |\n#+TBLFM: $1=$2\n"
	fixture: List_Test_Fixture
	if !list_test_fixture_open(t, &fixture, source, 1_803) do return
	defer list_test_fixture_close(&fixture)
	cell_node, found := list_test_node(&fixture.analysis, .Table_Cell, 1)
	testing.expect(t, found)
	if !found do return
	cell, inspected, failure := table_focused_cell_inspect(
		&fixture.analysis,
		transmute([]u8)source,
		fixture.scope,
		cell_node.id,
	)
	testing.expectf(t, inspected, "cell inspection failed with %v", failure.code)
	testing.expect_value(t, cell.row, u32(0))
	testing.expect_value(t, cell.column, u32(1))
	testing.expect_value(
		t,
		string(transmute([]u8)source[int(cell.selection.start):int(cell.selection.end)]),
		"value",
	)
	plan: language.Jan_Rewrite_Plan
	planned, plan_failure := table_focused_cell_plan_prepare(
		&plan,
		&fixture.analysis,
		transmute([]u8)source,
		{operation_id = 124, scope = fixture.scope, cell_id = cell_node.id, rewrite_generation = 124, text = "new \\| value λ"},
	)
	testing.expectf(t, planned, "cell plan failed with %v", plan_failure.code)
	if !planned do return
	defer language.jan_rewrite_plan_close(&plan)
	testing.expect(t, list_test_publish_and_history(
		&fixture,
		&plan,
		"#+caption: Demo\n| a | new \\| value λ |\n#+TBLFM: $1=$2\n",
	))
}
