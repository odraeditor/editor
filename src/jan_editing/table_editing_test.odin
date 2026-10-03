// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_editing

import "../language"
import "core:testing"

/* Verifies empty creation and delimited conversion produce bounded pipe tables. */
@(test)
table_editing_creates_and_converts_tables :: proc(t: ^testing.T) {
	table_test_expect_edit(t, "Replace me\n", "|  |  |  |\n|  |  |  |\n", .Create, .Paragraph, 0, 2, 3, 0, {}, "")
	table_test_expect_edit(
		t,
		"alpha, beta\ngamma,δ\n",
		"| alpha | beta |\n| gamma | δ |\n",
		.Convert_Delimited,
		.Paragraph,
		0,
		0,
		0,
		',',
		{},
		"",
	)
}

/* Verifies row and separator operations preserve complete stored values. */
@(test)
table_editing_reorganizes_rows_and_separators :: proc(t: ^testing.T) {
	base := "| a | b |\n|---+---|\n| c | d |\n"
	table_test_expect_edit(t, base, "|  |  |\n| a | b |\n|---+---|\n| c | d |\n", .Insert_Row_Before, .Table_Row, 0, 0, 0, 0, {}, "")
	table_test_expect_edit(t, base, "| a | b |\n|  |  |\n|---+---|\n| c | d |\n", .Insert_Row_After, .Table_Row, 0, 0, 0, 0, {}, "")
	table_test_expect_edit(t, base, "|---+---|\n| c | d |\n", .Delete_Row, .Table_Row, 0, 0, 0, 0, {}, "")
	table_test_expect_edit(t, "| a | b |\n| c | d |\n", "| c | d |\n| a | b |\n", .Move_Row_Down, .Table_Row, 0, 0, 0, 0, {}, "")
	table_test_expect_edit(t, "| a | b |\n| c | d |\n", "| c | d |\n| a | b |\n", .Move_Row_Up, .Table_Row, 1, 0, 0, 0, {}, "")
	table_test_expect_edit(t, "| a | b |\n", "| a | b |\n| a | b |\n", .Duplicate_Row, .Table_Row, 0, 0, 0, 0, {}, "")
	table_test_expect_edit(t, "| a | b |\n", "| a | b |\n|---+---|\n", .Insert_Separator_After, .Table_Row, 0, 0, 0, 0, {}, "")
	table_test_expect_edit(t, base, "| a | b |\n| c | d |\n", .Delete_Separator, .Table_Separator_Row, 0, 0, 0, 0, {}, "")
}

/* Verifies column operations apply to every data row and retain separators. */
@(test)
table_editing_reorganizes_columns :: proc(t: ^testing.T) {
	base := "| a | b |\n|---+---|\n| c | d |\n"
	table_test_expect_edit(t, base, "|  | a | b |\n|---+---+---|\n|  | c | d |\n", .Insert_Column_Before, .Table_Cell, 0, 0, 0, 0, {}, "")
	table_test_expect_edit(t, base, "| a |  | b |\n|---+---+---|\n| c |  | d |\n", .Insert_Column_After, .Table_Cell, 0, 0, 0, 0, {}, "")
	table_test_expect_edit(t, base, "| b |\n|---|\n| d |\n", .Delete_Column, .Table_Cell, 0, 0, 0, 0, {}, "")
	table_test_expect_edit(t, base, "| b | a |\n|---+---|\n| d | c |\n", .Move_Column_Right, .Table_Cell, 0, 0, 0, 0, {}, "")
	table_test_expect_edit(t, base, "| b | a |\n|---+---|\n| d | c |\n", .Move_Column_Left, .Table_Cell, 1, 0, 0, 0, {}, "")
	table_test_expect_edit(t, base, "| a | a | b |\n|---+---+---|\n| c | c | d |\n", .Duplicate_Column, .Table_Cell, 0, 0, 0, 0, {}, "")
}

/* Verifies rectangular copy, cut, and paste use complete data-cell coordinates. */
@(test)
table_editing_copies_cuts_and_pastes_rectangles :: proc(t: ^testing.T) {
	source := "| a | b | c |\n| d | e | f |\n| g | h | i |\n"
	fixture: List_Test_Fixture
	if !list_test_fixture_open(t, &fixture, source, 1_601) do return
	defer list_test_fixture_close(&fixture)
	table, table_found := list_test_node(&fixture.analysis, .Pipe_Table, 0)
	testing.expect(t, table_found)
	if !table_found do return
	selection := Table_Rectangle{row_start = 0, row_end = 2, column_start = 1, column_end = 3}
	copy_state: Table_Rectangle_Copy
	descriptor, copied, failure := table_rectangle_copy_prepare(
		&copy_state,
		&fixture.analysis,
		transmute([]u8)source,
		101,
		fixture.scope,
		table.id,
		selection,
	)
	testing.expectf(t, copied, "rectangle copy failed with %v", failure.code)
	if !copied do return
	defer table_rectangle_copy_close(&copy_state)
	testing.expect_value(t, descriptor.cell_count, u32(4))
	text, inspected := table_rectangle_copy_text(&copy_state)
	testing.expect(t, inspected)
	testing.expect_value(t, text, "b\tc\ne\tf")

	table_test_expect_edit(
		t, source,
		"| a |  |  |\n| d |  |  |\n| g | h | i |\n",
		.Cut_Rectangle, .Pipe_Table, 0, 0, 0, 0, selection, "",
	)
	table_test_expect_edit(
		t, source,
		"| x | y | c |\n| z | w | f |\n| g | h | i |\n",
		.Paste_Rectangle, .Pipe_Table, 0, 0, 0, 0,
		Table_Rectangle{row_start = 0, row_end = 2, column_start = 0, column_end = 2},
		"x\ty\nz\tw",
	)
}

@(private = "file")
table_test_expect_edit :: proc(
	t: ^testing.T,
	source, expected: string,
	kind: Table_Edit_Kind,
	target_kind: language.Jan_Node_Kind,
	ordinal: int,
	rows, columns: u32,
	delimiter: u8,
	rectangle: Table_Rectangle,
	text: string,
) {
	fixture: List_Test_Fixture
	id := u64(1_700 + int(kind) * 8 + ordinal)
	if !list_test_fixture_open(t, &fixture, source, id) do return
	defer list_test_fixture_close(&fixture)
	target, found := list_test_node(&fixture.analysis, target_kind, ordinal)
	testing.expect(t, found)
	if !found do return
	request := table_test_request(fixture.scope, kind, target.id)
	request.rows = rows
	request.columns = columns
	request.delimiter = delimiter
	request.rectangle = rectangle
	request.text = text
	plan: language.Jan_Rewrite_Plan
	planned, failure := table_edit_plan_prepare(
		&plan,
		&fixture.analysis,
		transmute([]u8)fixture.source,
		request,
	)
	testing.expectf(t, planned, "%v plan failed with %v", kind, failure.code)
	if !planned do return
	defer language.jan_rewrite_plan_close(&plan)
	testing.expect(t, list_test_publish_and_history(&fixture, &plan, expected))
}

@(private)
table_test_request :: proc(scope: Scope, kind: Table_Edit_Kind, target_id: language.Jan_Node_ID) -> Table_Edit_Request {
	return {operation_id = 111, scope = scope, kind = kind, target_id = target_id, rewrite_generation = 111}
}
