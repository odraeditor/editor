// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_editing

import "../language"
import "base:runtime"
import "core:strings"
import "core:unicode/utf8"

@(private)
Table_Cell_Data :: struct {
	node:         language.Jan_Node_Record,
	value:        string,
	source_start: u64,
	source_end:   u64,
}

@(private)
Table_Row_Data :: struct {
	node:         language.Jan_Node_Record,
	separator:    bool,
	cells:        [dynamic]Table_Cell_Data,
	source_start: u64,
	source_end:   u64,
	separator_columns: int,
}

@(private)
Table_Data :: struct {
	table:       language.Jan_Node_Record,
	rows:        [dynamic]Table_Row_Data,
	columns:     int,
	cell_count:  int,
	allocator:   runtime.Allocator,
}

@(private)
Table_Rectangle_Copy_State :: struct {
	descriptor: Table_Rectangle_Descriptor,
	text:       []u8,
	allocator:  runtime.Allocator,
}

/* table_edit_plan_prepare constructs one checked non-executing table rewrite. */
table_edit_plan_prepare :: proc(
	plan: ^language.Jan_Rewrite_Plan,
	analysis: ^language.Jan_Structural_Analysis,
	source: []u8,
	request: Table_Edit_Request,
	limits := DEFAULT_LIMITS,
	allocator := context.allocator,
	temporary_allocator := context.temp_allocator,
) -> (ok: bool, failure: Failure) {
	if plan == nil || analysis == nil || !scope_is_valid(request.scope) ||
	   request.operation_id == Operation_ID(0) || request.kind <= .Invalid ||
	   request.kind > .Paste_Rectangle ||
	   request.rewrite_generation == language.Jan_Rewrite_Generation(0) ||
	   !limits_are_valid(limits) || allocator.procedure == nil ||
	   temporary_allocator.procedure == nil || !utf8.valid_string(string(source)) ||
	   !utf8.valid_string(request.text) {
		return false, editing_failure(.Plan_Table_Edit, .Invalid_Scope, request.scope)
	}
	nodes := language.jan_structural_analysis_nodes(analysis)
	usage, inspected := language.jan_structural_analysis_usage(analysis)
	if !inspected || usage.source_bytes != u64(len(source)) || len(nodes) == 0 ||
	   nodes[0].range.scope != request.scope.analysis {
		return false, editing_failure(.Plan_Table_Edit, .Stale, request.scope)
	}
	target, found := navigation_node_by_id(nodes, request.target_id)
	if !found {
		return false, editing_failure(.Plan_Table_Edit, .Invalid_Target, request.scope)
	}
	if navigation_node_overlaps_recovery(target, language.jan_structural_analysis_recoveries(analysis)) {
		return false, editing_failure(.Plan_Table_Edit, .Malformed, request.scope)
	}
	builder, builder_error := strings.builder_make(temporary_allocator)
	if builder_error != nil {
		return false, editing_failure(.Plan_Table_Edit, .Allocation_Failed, request.scope)
	}
	defer strings.builder_destroy(&builder)
	edit_start, edit_end := target.range.start, target.range.end

	if request.kind == .Create {
		if target.kind != .Paragraph || request.rows == 0 || request.columns == 0 ||
		   u64(request.rows) * u64(request.columns) > u64(limits.table_cells) {
			_, invalid := table_edit_limit_or_target(request, limits)
			return false, invalid
		}
		if !table_write_empty(&builder, int(request.rows), int(request.columns)) {
			return false, editing_failure(.Plan_Table_Edit, .Allocation_Failed, request.scope)
		}
	} else if request.kind == .Convert_Delimited {
		if target.kind != .Paragraph || request.delimiter == 0 || request.delimiter == '\n' ||
		   request.delimiter == '\r' || request.delimiter == '|' ||
		   !table_write_delimited_conversion(
			&builder,
			string(source[int(target.range.start):int(target.range.end)]),
			request.delimiter,
			limits.table_cells,
			temporary_allocator,
		) {
			return false, editing_failure(.Plan_Table_Edit, .Invalid_Target, request.scope)
		}
	} else {
		table_node, table_found := table_owner(nodes, target)
		if !table_found {
			return false, editing_failure(.Plan_Table_Edit, .Invalid_Target, request.scope)
		}
		if navigation_node_overlaps_recovery(
			table_node,
			language.jan_structural_analysis_recoveries(analysis),
		) {
			return false, editing_failure(.Plan_Table_Edit, .Malformed, request.scope)
		}
		data, modeled, model_failure := table_data_prepare(
			nodes,
			source,
			table_node,
			request,
			limits,
			temporary_allocator,
		)
		if !modeled do return false, model_failure
		defer table_data_close(&data)
		if !table_apply_edit(&data, target, request, limits, temporary_allocator) {
			return false, editing_failure(.Plan_Table_Edit, .Invalid_Target, request.scope)
		}
		if !table_write(&builder, &data) {
			return false, editing_failure(.Plan_Table_Edit, .Allocation_Failed, request.scope)
		}
		edit_start, edit_end = table_node.range.start, table_node.range.end
	}
	planned, jan_failure := jan_editing_prepare_range_rewrite(
		plan, analysis, source, request.scope, edit_start, edit_end,
		strings.to_string(builder), request.rewrite_generation, limits,
		allocator, temporary_allocator,
	)
	if !planned do return false, table_edit_failure_from_language(jan_failure, request.scope)
	return true, {}
}

/* table_rectangle_copy_prepare owns one bounded TSV rectangle. */
table_rectangle_copy_prepare :: proc(
	copy_state: ^Table_Rectangle_Copy,
	analysis: ^language.Jan_Structural_Analysis,
	source: []u8,
	operation_id: Operation_ID,
	scope: Scope,
	table_id: language.Jan_Node_ID,
	selection: Table_Rectangle,
	limits := DEFAULT_LIMITS,
	allocator := context.allocator,
	temporary_allocator := context.temp_allocator,
) -> (descriptor: Table_Rectangle_Descriptor, ok: bool, failure: Failure) {
	if copy_state == nil || copy_state.state != nil || analysis == nil ||
	   operation_id == Operation_ID(0) || !scope_is_valid(scope) ||
	   !limits_are_valid(limits) || allocator.procedure == nil || temporary_allocator.procedure == nil {
		return {}, false, editing_failure(.Copy_Table_Rectangle, .Invalid_Scope, scope)
	}
	nodes := language.jan_structural_analysis_nodes(analysis)
	usage, inspected := language.jan_structural_analysis_usage(analysis)
	if !inspected || usage.source_bytes != u64(len(source)) || len(nodes) == 0 ||
	   nodes[0].range.scope != scope.analysis {
		return {}, false, editing_failure(.Copy_Table_Rectangle, .Stale, scope)
	}
	table, found := navigation_node_by_id(nodes, table_id)
	if !found || table.kind != .Pipe_Table ||
	   navigation_node_overlaps_recovery(table, language.jan_structural_analysis_recoveries(analysis)) {
		return {}, false, editing_failure(.Copy_Table_Rectangle, .Invalid_Target, scope)
	}
	request := Table_Edit_Request {
		operation_id = operation_id, scope = scope, kind = .Cut_Rectangle,
		target_id = table_id, rewrite_generation = 1,
	}
	data, modeled, model_failure := table_data_prepare(
		nodes, source, table, request, limits, temporary_allocator,
	)
	if !modeled {
		model_failure.operation = .Copy_Table_Rectangle
		return {}, false, model_failure
	}
	defer table_data_close(&data)
	if !table_rectangle_is_valid(&data, selection) {
		return {}, false, editing_failure(.Copy_Table_Rectangle, .Invalid_Target, scope)
	}
	builder, builder_error := strings.builder_make(temporary_allocator)
	if builder_error != nil {
		return {}, false, editing_failure(.Copy_Table_Rectangle, .Allocation_Failed, scope)
	}
	defer strings.builder_destroy(&builder)
	if !table_write_rectangle(&builder, &data, selection) {
		return {}, false, editing_failure(.Copy_Table_Rectangle, .Allocation_Failed, scope)
	}
	text := strings.to_string(builder)
	state, state_error := new(Table_Rectangle_Copy_State, allocator)
	if state_error != nil {
		return {}, false, editing_failure(.Copy_Table_Rectangle, .Allocation_Failed, scope)
	}
	state^ = Table_Rectangle_Copy_State{allocator = allocator}
	state.text, state_error = make([]u8, len(text), allocator)
	if state_error != nil {
		free(state, allocator)
		return {}, false, editing_failure(.Copy_Table_Rectangle, .Allocation_Failed, scope)
	}
	copy(state.text, transmute([]u8)text)
	cell_count := (selection.row_end - selection.row_start) *
	              (selection.column_end - selection.column_start)
	state.descriptor = {
		operation_id = operation_id,
		scope = scope,
		table = navigation_target(table),
		selection = selection,
		cell_count = cell_count,
		retained_bytes = u64(size_of(Table_Rectangle_Copy_State)) + u64(len(state.text)),
	}
	copy_state.state = state
	return state.descriptor, true, {}
}

/* table_rectangle_copy_text returns copy-owned TSV bytes. */
table_rectangle_copy_text :: proc(copy_state: ^Table_Rectangle_Copy) -> (string, bool) {
	state := table_rectangle_copy_state(copy_state)
	if state == nil do return "", false
	return string(state.text), true
}

/* table_rectangle_copy_is_valid reports whether copied rectangle text is live. */
table_rectangle_copy_is_valid :: proc(copy_state: ^Table_Rectangle_Copy) -> bool {
	return table_rectangle_copy_state(copy_state) != nil
}

/* table_rectangle_copy_close releases copied rectangular text. */
table_rectangle_copy_close :: proc(copy_state: ^Table_Rectangle_Copy) {
	if copy_state == nil do return
	state := table_rectangle_copy_state(copy_state)
	if state != nil {
		if state.text != nil do delete(state.text, state.allocator)
		allocator := state.allocator
		state^ = {}
		free(state, allocator)
	}
	copy_state^ = {}
}

@(private)
table_rectangle_copy_state :: proc(copy_state: ^Table_Rectangle_Copy) -> ^Table_Rectangle_Copy_State {
	if copy_state == nil || copy_state.state == nil do return nil
	return (^Table_Rectangle_Copy_State)(copy_state.state)
}

@(private)
table_owner :: proc(
	nodes: []language.Jan_Node_Record,
	target: language.Jan_Node_Record,
) -> (language.Jan_Node_Record, bool) {
	current := target
	for current.id != language.Jan_Node_ID(0) {
		if current.kind == .Pipe_Table do return current, true
		if current.parent_id == language.Jan_Node_ID(0) do break
		parent, found := navigation_node_by_id(nodes, current.parent_id)
		if !found do break
		current = parent
	}
	return {}, false
}

@(private)
table_data_prepare :: proc(
	nodes: []language.Jan_Node_Record,
	source: []u8,
	table: language.Jan_Node_Record,
	request: Table_Edit_Request,
	limits: Limits,
	allocator: runtime.Allocator,
) -> (data: Table_Data, ok: bool, failure: Failure) {
	data = {table = table, allocator = allocator}
	rows, rows_error := make([dynamic]Table_Row_Data, 0, 16, allocator)
	if rows_error != nil {
		return {}, false, editing_failure(.Plan_Table_Edit, .Allocation_Failed, request.scope)
	}
	data.rows = rows
	checked: u32
	cursor := int(table.range.start)
	for cursor < int(table.range.end) {
		if checked % limits.cancellation_entries == 0 && request.cancel_requested != nil &&
		   request.cancel_requested^ {
			table_data_close(&data)
			return {}, false, editing_failure(.Plan_Table_Edit, .Cancelled, request.scope)
		}
		line_start := cursor
		line_end := cursor
		for line_end < int(table.range.end) && source[line_end] != '\r' && source[line_end] != '\n' do line_end += 1
		next := line_end
		if next < int(table.range.end) && source[next] == '\r' do next += 1
		if next < int(table.range.end) && source[next] == '\n' do next += 1
		if line_start >= line_end || source[line_start] != '|' {
			table_data_close(&data)
			return {}, false, editing_failure(.Plan_Table_Edit, .Malformed, request.scope)
		}
		node, _ := table_source_row_node(nodes, table.id, line_start, line_end)
		separator, separator_columns := table_source_separator(source[line_start:line_end])
		row := Table_Row_Data {
			node = node,
			separator = separator,
			source_start = u64(line_start),
			source_end = u64(next),
			separator_columns = separator_columns,
		}
		if !row.separator {
			cells, cells_error := make([dynamic]Table_Cell_Data, 0, 8, allocator)
			if cells_error != nil {
				table_data_close(&data)
				return {}, false, editing_failure(.Plan_Table_Edit, .Allocation_Failed, request.scope)
			}
			row.cells = cells
			cell_start := line_start + 1
			row_complete := false
			for cell_start <= line_end {
				delimiter := table_source_cell_end(source, cell_start, line_end)
				if delimiter < 0 do break
				cell_node, _ := table_source_cell_node(nodes, node.id, cell_start, delimiter + 1)
				value := strings.trim_space(string(source[cell_start:delimiter]))
				cell := Table_Cell_Data {
					node = cell_node,
					value = value,
					source_start = u64(cell_start),
					source_end = u64(delimiter + 1),
				}
				if _, append_error := append(&row.cells, cell); append_error != nil {
					delete(row.cells)
					table_data_close(&data)
					return {}, false, editing_failure(.Plan_Table_Edit, .Allocation_Failed, request.scope)
				}
				data.cell_count += 1
				data.columns = max(data.columns, len(row.cells))
				if data.cell_count > int(limits.table_cells) {
					actual := u64(data.cell_count)
					delete(row.cells)
					table_data_close(&data)
					failure = editing_failure(.Plan_Table_Edit, .Limited, request.scope)
					failure.limit, failure.actual = u64(limits.table_cells), actual
					return {}, false, failure
				}
				cell_start = delimiter + 1
				if cell_start >= line_end {
					row_complete = true
					break
				}
			}
			if len(row.cells) == 0 || !row_complete {
				delete(row.cells)
				table_data_close(&data)
				return {}, false, editing_failure(.Plan_Table_Edit, .Malformed, request.scope)
			}
		} else {
			data.columns = max(data.columns, separator_columns)
		}
		if _, append_error := append(&data.rows, row); append_error != nil {
			if row.cells != nil do delete(row.cells)
			table_data_close(&data)
			return {}, false, editing_failure(.Plan_Table_Edit, .Allocation_Failed, request.scope)
		}
		checked += 1
		cursor = next
	}
	if len(data.rows) == 0 || data.columns == 0 {
		table_data_close(&data)
		return {}, false, editing_failure(.Plan_Table_Edit, .Malformed, request.scope)
	}
	for index in 0 ..< len(data.rows) {
		if data.rows[index].separator {
			if data.rows[index].separator_columns != data.columns {
				table_data_close(&data)
				return {}, false, editing_failure(.Plan_Table_Edit, .Malformed, request.scope)
			}
			continue
		}
		for len(data.rows[index].cells) < data.columns {
			if _, append_error := append(&data.rows[index].cells, Table_Cell_Data{}); append_error != nil {
				table_data_close(&data)
				return {}, false, editing_failure(.Plan_Table_Edit, .Allocation_Failed, request.scope)
			}
		}
	}
	return data, true, {}
}

@(private)
table_data_close :: proc(data: ^Table_Data) {
	if data == nil do return
	for row in data.rows do if row.cells != nil do delete(row.cells)
	if data.rows != nil do delete(data.rows)
	data^ = {}
}

@(private)
table_source_row_node :: proc(
	nodes: []language.Jan_Node_Record,
	table_id: language.Jan_Node_ID,
	start, end: int,
) -> (language.Jan_Node_Record, bool) {
	for node in nodes {
		if node.parent_id == table_id &&
		   (node.kind == .Table_Row || node.kind == .Table_Separator_Row) &&
		   int(node.range.start) == start && int(node.range.end) >= end {
			return node, true
		}
	}
	return {}, false
}

@(private)
table_source_cell_node :: proc(
	nodes: []language.Jan_Node_Record,
	row_id: language.Jan_Node_ID,
	start, end: int,
) -> (language.Jan_Node_Record, bool) {
	for node in nodes {
		if node.parent_id == row_id && node.kind == .Table_Cell &&
		   int(node.range.start) == start && int(node.range.end) >= end {
			return node, true
		}
	}
	return {}, false
}

@(private)
table_source_cell_end :: proc(source: []u8, start, end: int) -> int {
	escaped := false
	for cursor in start ..< end {
		if source[cursor] == '|' && !escaped do return cursor
		if source[cursor] == '\\' {
			escaped = !escaped
		} else {
			escaped = false
		}
	}
	return -1
}

@(private)
table_source_separator :: proc(line: []u8) -> (bool, int) {
	columns := 1
	has_dash := false
	for byte in line[1:] {
		switch byte {
		case '-': has_dash = true
		case '+': columns += 1
		case '|', ':', ' ', '\t':
		case: return false, 0
		}
	}
	return has_dash, columns
}

@(private)
table_apply_edit :: proc(
	data: ^Table_Data,
	target: language.Jan_Node_Record,
	request: Table_Edit_Request,
	limits: Limits,
	allocator: runtime.Allocator,
) -> bool {
	row_index, row_found := table_row_index(data, target)
	column_index, column_found := table_column_index(data, target)
	switch request.kind {
	case .Insert_Row_Before, .Insert_Row_After:
		if !row_found do return false
		insert_at := row_index
		if request.kind == .Insert_Row_After do insert_at += 1
		return table_insert_row(data, insert_at, false, allocator, limits)
	case .Delete_Row:
		if !row_found || data.rows[row_index].separator do return false
		table_remove_row(data, row_index)
		return table_data_row_count(data) > 0
	case .Move_Row_Up, .Move_Row_Down:
		if !row_found do return false
		destination := row_index - 1
		if request.kind == .Move_Row_Down do destination = row_index + 1
		if destination < 0 || destination >= len(data.rows) do return false
		data.rows[row_index], data.rows[destination] = data.rows[destination], data.rows[row_index]
		return true
	case .Duplicate_Row:
		if !row_found || data.rows[row_index].separator do return false
		return table_duplicate_row(data, row_index, allocator, limits)
	case .Insert_Separator_After:
		if !row_found do return false
		return table_insert_row(data, row_index + 1, true, allocator, limits)
	case .Delete_Separator:
		if !row_found || !data.rows[row_index].separator do return false
		table_remove_row(data, row_index)
		return true
	case .Insert_Column_Before, .Insert_Column_After:
		if !column_found do return false
		insert_at := column_index
		if request.kind == .Insert_Column_After do insert_at += 1
		return table_insert_column(data, insert_at, allocator, limits)
	case .Delete_Column:
		if !column_found || data.columns <= 1 do return false
		table_remove_column(data, column_index)
		return true
	case .Move_Column_Left, .Move_Column_Right:
		if !column_found do return false
		destination := column_index - 1
		if request.kind == .Move_Column_Right do destination = column_index + 1
		if destination < 0 || destination >= data.columns do return false
		for &row in data.rows {
			if row.separator do continue
			row.cells[column_index], row.cells[destination] = row.cells[destination], row.cells[column_index]
		}
		return true
	case .Duplicate_Column:
		if !column_found do return false
		return table_duplicate_column(data, column_index, allocator, limits)
	case .Cut_Rectangle:
		if !table_rectangle_is_valid(data, request.rectangle) do return false
		return table_clear_rectangle(data, request.rectangle)
	case .Paste_Rectangle:
		return table_paste_rectangle(data, request.rectangle, request.text, limits, allocator)
	case .Invalid, .Create, .Convert_Delimited:
	}
	return false
}

@(private)
table_row_index :: proc(data: ^Table_Data, target: language.Jan_Node_Record) -> (int, bool) {
	row_id := target.id
	if target.kind == .Table_Cell do row_id = target.parent_id
	for row, index in data.rows do if row.node.id != 0 && row.node.id == row_id do return index, true
	for row, index in data.rows {
		if u64(target.range.start) >= row.source_start && u64(target.range.start) < row.source_end {
			return index, true
		}
	}
	return 0, false
}

@(private)
table_column_index :: proc(data: ^Table_Data, target: language.Jan_Node_Record) -> (int, bool) {
	if target.kind != .Table_Cell do return 0, false
	row_index, found := table_row_index(data, target)
	if !found do return 0, false
	for cell, index in data.rows[row_index].cells {
		if cell.node.id != 0 && cell.node.id == target.id do return index, true
	}
	for cell, index in data.rows[row_index].cells {
		if u64(target.range.start) >= cell.source_start && u64(target.range.start) < cell.source_end {
			return index, true
		}
	}
	if len(data.rows[row_index].cells) > 0 &&
	   u64(target.range.start) + 1 == data.rows[row_index].source_end {
		return len(data.rows[row_index].cells) - 1, true
	}
	return 0, false
}

@(private)
table_insert_row :: proc(data: ^Table_Data, index: int, separator: bool, allocator: runtime.Allocator, limits: Limits) -> bool {
	if index < 0 || index > len(data.rows) do return false
	if !separator && data.cell_count + data.columns > int(limits.table_cells) do return false
	row := Table_Row_Data{separator = separator}
	if !separator {
		cells, cells_error := make([dynamic]Table_Cell_Data, data.columns, data.columns, allocator)
		if cells_error != nil do return false
		row.cells = cells
	}
	if _, append_error := append(&data.rows, row); append_error != nil {
		if row.cells != nil do delete(row.cells)
		return false
	}
	for cursor := len(data.rows) - 1; cursor > index; cursor -= 1 do data.rows[cursor] = data.rows[cursor - 1]
	data.rows[index] = row
	if !separator do data.cell_count += data.columns
	return true
}

@(private)
table_remove_row :: proc(data: ^Table_Data, index: int) {
	if data.rows[index].cells != nil {
		data.cell_count -= len(data.rows[index].cells)
		delete(data.rows[index].cells)
	}
	ordered_remove(&data.rows, index)
}

@(private)
table_duplicate_row :: proc(data: ^Table_Data, index: int, allocator: runtime.Allocator, limits: Limits) -> bool {
	if data.cell_count + data.columns > int(limits.table_cells) do return false
	cells, cells_error := make([dynamic]Table_Cell_Data, data.columns, data.columns, allocator)
	if cells_error != nil do return false
	copy(cells[:], data.rows[index].cells[:])
	row := Table_Row_Data{cells = cells}
	if _, append_error := append(&data.rows, row); append_error != nil {
		delete(cells)
		return false
	}
	for cursor := len(data.rows) - 1; cursor > index + 1; cursor -= 1 do data.rows[cursor] = data.rows[cursor - 1]
	data.rows[index + 1] = row
	data.cell_count += data.columns
	return true
}

@(private)
table_insert_column :: proc(data: ^Table_Data, index: int, allocator: runtime.Allocator, limits: Limits) -> bool {
	row_count := table_data_row_count(data)
	if index < 0 || index > data.columns || data.cell_count + row_count > int(limits.table_cells) do return false
	for &row in data.rows {
		if row.separator do continue
		if _, append_error := append(&row.cells, Table_Cell_Data{}); append_error != nil do return false
		for cursor := len(row.cells) - 1; cursor > index; cursor -= 1 do row.cells[cursor] = row.cells[cursor - 1]
		row.cells[index] = {}
	}
	data.columns += 1
	data.cell_count += row_count
	_ = allocator
	return true
}

@(private)
table_remove_column :: proc(data: ^Table_Data, index: int) {
	for &row in data.rows {
		if row.separator do continue
		ordered_remove(&row.cells, index)
		data.cell_count -= 1
	}
	data.columns -= 1
}

@(private)
table_duplicate_column :: proc(data: ^Table_Data, index: int, allocator: runtime.Allocator, limits: Limits) -> bool {
	if !table_insert_column(data, index + 1, allocator, limits) do return false
	for &row in data.rows {
		if row.separator do continue
		row.cells[index + 1] = row.cells[index]
	}
	return true
}

@(private)
table_data_row_count :: proc(data: ^Table_Data) -> int {
	count: int
	for row in data.rows do if !row.separator do count += 1
	return count
}

@(private)
table_rectangle_is_valid :: proc(data: ^Table_Data, rectangle: Table_Rectangle) -> bool {
	rows := table_data_row_count(data)
	return rectangle.row_start < rectangle.row_end && rectangle.column_start < rectangle.column_end &&
	       rectangle.row_end <= u32(rows) && rectangle.column_end <= u32(data.columns)
}

@(private)
table_data_row_at :: proc(data: ^Table_Data, ordinal: int) -> (^Table_Row_Data, bool) {
	seen: int
	for &row in data.rows {
		if row.separator do continue
		if seen == ordinal do return &row, true
		seen += 1
	}
	return nil, false
}

@(private)
table_clear_rectangle :: proc(data: ^Table_Data, rectangle: Table_Rectangle) -> bool {
	for row_index in int(rectangle.row_start) ..< int(rectangle.row_end) {
		row, found := table_data_row_at(data, row_index)
		if !found do return false
		for column in int(rectangle.column_start) ..< int(rectangle.column_end) do row.cells[column].value = ""
	}
	return true
}

@(private)
table_paste_rectangle :: proc(data: ^Table_Data, rectangle: Table_Rectangle, text: string, limits: Limits, allocator: runtime.Allocator) -> bool {
	if rectangle.row_start >= rectangle.row_end || rectangle.column_start >= rectangle.column_end do return false
	rows := strings.split_lines(text, allocator)
	defer delete(rows, allocator)
	if len(rows) != int(rectangle.row_end - rectangle.row_start) do return false
	for line, row_offset in rows {
		cells := strings.split(line, "\t", allocator)
		defer delete(cells, allocator)
		if len(cells) != int(rectangle.column_end - rectangle.column_start) do return false
		if u64(len(rows) * len(cells)) > u64(limits.table_cells) do return false
		row, found := table_data_row_at(data, int(rectangle.row_start) + row_offset)
		if !found || rectangle.column_end > u32(len(row.cells)) do return false
		for cell, column_offset in cells {
			row.cells[int(rectangle.column_start) + column_offset].value = cell
		}
	}
	return true
}

@(private)
table_write_rectangle :: proc(builder: ^strings.Builder, data: ^Table_Data, rectangle: Table_Rectangle) -> bool {
	for row_index in int(rectangle.row_start) ..< int(rectangle.row_end) {
		row, found := table_data_row_at(data, row_index)
		if !found do return false
		for column in int(rectangle.column_start) ..< int(rectangle.column_end) {
			if column > int(rectangle.column_start) && strings.write_byte(builder, '\t') != 1 do return false
			value := row.cells[column].value
			if strings.write_string(builder, value) != len(value) do return false
		}
		if row_index + 1 < int(rectangle.row_end) && strings.write_byte(builder, '\n') != 1 do return false
	}
	return true
}

@(private)
table_write :: proc(builder: ^strings.Builder, data: ^Table_Data) -> bool {
	for row in data.rows {
		if row.separator {
			if strings.write_byte(builder, '|') != 1 do return false
			for column in 0 ..< data.columns {
				if strings.write_string(builder, "---") != 3 do return false
				separator := u8('|')
				if column + 1 < data.columns do separator = '+'
				if strings.write_byte(builder, separator) != 1 do return false
			}
			if strings.write_byte(builder, '\n') != 1 do return false
			continue
		}
		if strings.write_byte(builder, '|') != 1 do return false
		for cell in row.cells {
			if strings.write_byte(builder, ' ') != 1 ||
			   strings.write_string(builder, cell.value) != len(cell.value) ||
			   strings.write_string(builder, " |") != 2 {
				return false
			}
		}
		if strings.write_byte(builder, '\n') != 1 do return false
	}
	return true
}

@(private)
table_write_empty :: proc(builder: ^strings.Builder, rows, columns: int) -> bool {
	for _ in 0 ..< rows {
		if strings.write_byte(builder, '|') != 1 do return false
		for _ in 0 ..< columns do if strings.write_string(builder, "  |") != 3 do return false
		if strings.write_byte(builder, '\n') != 1 do return false
	}
	return true
}

@(private)
table_write_delimited_conversion :: proc(
	builder: ^strings.Builder,
	text: string,
	delimiter: u8,
	cell_limit: u32,
	allocator: runtime.Allocator,
) -> bool {
	lines := strings.split_lines(text, allocator)
	defer delete(lines, allocator)
	if len(lines) == 0 do return false
	columns := 0
	cell_count: int
	for line in lines {
		if len(line) == 0 do continue
		parts := strings.split(line, string([]u8{delimiter}), allocator)
		defer delete(parts, allocator)
		if columns == 0 do columns = len(parts)
		if len(parts) != columns || columns == 0 do return false
		cell_count += len(parts)
		if cell_count > int(cell_limit) do return false
		if strings.write_byte(builder, '|') != 1 do return false
		for part in parts {
			value := strings.trim_space(part)
			if strings.write_byte(builder, ' ') != 1 ||
			   strings.write_string(builder, value) != len(value) ||
			   strings.write_string(builder, " |") != 2 {
				return false
			}
		}
		if strings.write_byte(builder, '\n') != 1 do return false
	}
	return cell_count > 0
}

@(private)
table_edit_limit_or_target :: proc(request: Table_Edit_Request, limits: Limits) -> (bool, Failure) {
	actual := u64(request.rows) * u64(request.columns)
	if actual > u64(limits.table_cells) {
		failure := editing_failure(.Plan_Table_Edit, .Limited, request.scope)
		failure.limit, failure.actual = u64(limits.table_cells), actual
		return false, failure
	}
	return false, editing_failure(.Plan_Table_Edit, .Invalid_Target, request.scope)
}

@(private)
table_edit_failure_from_language :: proc(jan: language.Jan_Failure, scope: Scope) -> Failure {
	code := Failure_Code.Invalid_Target
	#partial switch jan.code {
	case .Stale, .Incomplete: code = .Stale
	case .Limited: code = .Limited
	case .Allocation_Failed: code = .Allocation_Failed
	case .Malformed: code = .Malformed
	case .Cancelled: code = .Cancelled
	}
	return {operation = .Plan_Table_Edit, code = code, scope = scope, limit = jan.limit, actual = jan.actual}
}
