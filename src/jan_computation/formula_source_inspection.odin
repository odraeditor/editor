// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_computation

import "../editor"
import "../language"
import "base:runtime"
import "core:strconv"
import "core:strings"

/* Formula_Source_Inspection owns one copied, non-mutating source-form trace. */
Formula_Source_Inspection :: struct {
	state: rawptr,
}

/* Formula_Source_Inspection_View borrows one inspected formula until close. */
Formula_Source_Inspection_View :: struct {
	formula_range: language.Jan_Source_Range,
	table_range:   language.Jan_Source_Range,
	target:        string,
	expression:    string,
	row_count:     u32,
	column_count:  u32,
	target_row:    u32,
	target_column: u32,
	value:         Cell_Value,
	trace:         []Debug_Step,
}

@(private)
Formula_Source_Inspection_State :: struct {
	view:      Formula_Source_Inspection_View,
	text:      []u8,
	trace:     []Debug_Step,
	allocator: runtime.Allocator,
}

/* inspect_formula_source evaluates one compatible formula without changing source. */
inspect_formula_source :: proc(
	inspection: ^Formula_Source_Inspection,
	analysis: ^language.Jan_Structural_Analysis,
	source: []u8,
	point: editor.Byte_Offset,
	allocator := context.allocator,
	temporary_allocator := context.temp_allocator,
) -> (ok: bool, failure: Failure) {
	if inspection == nil || inspection.state != nil || analysis == nil || len(source) == 0 ||
	   allocator.procedure == nil || temporary_allocator.procedure == nil {
		return false, formula_failure(.Invalid_Request, .Formula)
	}
	usage, inspected := language.jan_structural_analysis_usage(analysis)
	if !inspected || usage.source_bytes != u64(len(source)) {
		return false, formula_failure(.Stale, .Scope)
	}
	fact, found := formula_source_fact_select(
		language.jan_structural_analysis_indexes(analysis), point,
	)
	if !found do return false, formula_failure(.Unavailable, .Formula)
	table, table_found := formula_source_table_select(
		language.jan_structural_analysis_nodes(analysis), fact.range,
	)
	if !table_found do return false, formula_failure(.Unavailable, .Target)
	formula_text := strings.trim_space(string(source[int(fact.range.start):int(fact.range.end)]))
	target, expression, parsed := formula_source_assignment(formula_text)
	if !parsed do return false, formula_failure(.Malformed, .Formula)
	row_count, column_count, measured := formula_source_table_shape(
		source[int(table.range.start):int(table.range.end)],
	)
	if !measured || row_count == 0 || column_count == 0 ||
	   u64(row_count) * u64(column_count) > u64(MAX_TABLE_CELLS) {
		return false, formula_failure(.Malformed, .Target)
	}
	cells, cells_error := make([]Cell_Value, int(row_count * column_count), temporary_allocator)
	if cells_error != nil do return false, formula_failure(.Allocation_Failed, .Limit)
	defer delete(cells, temporary_allocator)
	column_names, names_error := make([]string, int(column_count), temporary_allocator)
	if names_error != nil do return false, formula_failure(.Allocation_Failed, .Limit)
	defer delete(column_names, temporary_allocator)
	if !formula_source_table_copy(
		source[int(table.range.start):int(table.range.end)],
		row_count,
		column_count,
		cells,
		column_names,
	) {
		return false, formula_failure(.Malformed, .Target)
	}
	target_row, target_column, target_ok := formula_source_target(target, row_count, column_count)
	if !target_ok do return false, formula_failure(.Malformed, .Target)
	instruction, instruction_ok := formula_source_expression(
		expression, target_row, target_column, row_count, column_count,
	)
	if !instruction_ok do return false, formula_failure(.Unavailable, .Formula)
	scope := Scope {
		analysis = fact.range.scope,
		source_bytes = u64(len(source)),
		configuration_generation = 1,
		adapter_generation = 1,
		policy_generation = 1,
	}
	snapshot := Table_Snapshot {
		identity = u64(table.id),
		scope = scope,
		row_count = row_count,
		column_count = column_count,
		column_names = column_names,
		cells = cells,
	}
	instructions := [1]Formula_Instruction{instruction}
	program := Formula_Program {
		identity = u64(fact.id),
		source_range = fact.range,
		current_row = target_row,
		current_column = target_column,
		instructions = instructions[:],
	}
	stack: [1]Cell_Value
	trace: [1]Debug_Step
	value, trace_count, evaluated, evaluation_failure := evaluate_formula(
		snapshot, program, stack[:], trace[:],
	)
	if !evaluated do return false, evaluation_failure
	state, state_error := new(Formula_Source_Inspection_State, allocator)
	if state_error != nil do return false, formula_failure(.Allocation_Failed, .Limit)
	state^ = Formula_Source_Inspection_State{allocator = allocator}
	text_bytes := len(target) + len(expression)
	state.text, state_error = make([]u8, text_bytes, allocator)
	if state_error == nil do state.trace, state_error = make([]Debug_Step, int(trace_count), allocator)
	if state_error != nil {
		formula_source_inspection_state_close(state)
		return false, formula_failure(.Allocation_Failed, .Limit)
	}
	target_length := copy(state.text, target)
	copy(state.text[target_length:], expression)
	copy(state.trace, trace[:trace_count])
	state.view = {
		formula_range = fact.range,
		table_range = table.range,
		target = string(state.text[:target_length]),
		expression = string(state.text[target_length:]),
		row_count = row_count,
		column_count = column_count,
		target_row = target_row,
		target_column = target_column,
		value = value,
		trace = state.trace,
	}
	inspection.state = state
	return true, {}
}

/* formula_source_inspection_view borrows the current copied inspection. */
formula_source_inspection_view :: proc(
	inspection: ^Formula_Source_Inspection,
) -> (Formula_Source_Inspection_View, bool) {
	state := formula_source_inspection_state(inspection)
	if state == nil do return {}, false
	return state.view, true
}

/* formula_source_inspection_close releases one copied inspection exactly once. */
formula_source_inspection_close :: proc(inspection: ^Formula_Source_Inspection) {
	state := formula_source_inspection_state(inspection)
	if state != nil do formula_source_inspection_state_close(state)
	if inspection != nil do inspection^ = {}
}

@(private)
formula_source_fact_select :: proc(
	facts: []language.Jan_Index_Fact,
	point: editor.Byte_Offset,
) -> (language.Jan_Index_Fact, bool) {
	first: language.Jan_Index_Fact
	for fact in facts {
		if fact.kind != .Formula do continue
		if first.id == language.Jan_Index_Fact_ID(0) do first = fact
		if point >= fact.range.start && point <= fact.range.end do return fact, true
	}
	return first, first.id != language.Jan_Index_Fact_ID(0)
}

@(private)
formula_source_table_select :: proc(
	nodes: []language.Jan_Node_Record,
	formula: language.Jan_Source_Range,
) -> (language.Jan_Node_Record, bool) {
	selected: language.Jan_Node_Record
	for node in nodes {
		if node.kind != .Pipe_Table || node.range.scope != formula.scope ||
		   node.range.end > formula.start {
			continue
		}
		if selected.id == language.Jan_Node_ID(0) || node.range.end > selected.range.end do selected = node
	}
	return selected, selected.id != language.Jan_Node_ID(0)
}

@(private)
formula_source_assignment :: proc(line: string) -> (target, expression: string, ok: bool) {
	colon := strings.index_byte(line, ':')
	if colon < 0 || colon + 1 >= len(line) do return
	assignment := strings.trim_space(line[colon + 1:])
	next := strings.index(assignment, "::")
	if next >= 0 do assignment = assignment[:next]
	format := strings.index_byte(assignment, ';')
	if format >= 0 do assignment = assignment[:format]
	equals := strings.index_byte(assignment, '=')
	if equals <= 0 || equals + 1 >= len(assignment) do return
	target = strings.trim_space(assignment[:equals])
	expression = strings.trim_space(assignment[equals + 1:])
	return target, expression, len(target) > 0 && len(expression) > 0
}

@(private)
formula_source_table_shape :: proc(table: []u8) -> (rows, columns: u32, ok: bool) {
	cursor := 0
	for cursor < len(table) {
		line_start, line_end, next := formula_source_line(table, cursor)
		cursor = next
		line := strings.trim_space(string(table[line_start:line_end]))
		if len(line) == 0 || line[0] != '|' || formula_source_separator(line) do continue
		count := formula_source_column_count(line)
		if count == 0 do return 0, 0, false
		columns = max(columns, count)
		rows += 1
	}
	return rows, columns, rows > 0 && columns > 0
}

@(private)
formula_source_table_copy :: proc(
	table: []u8,
	row_count, column_count: u32,
	cells: []Cell_Value,
	column_names: []string,
) -> bool {
	if len(cells) != int(row_count * column_count) || len(column_names) != int(column_count) do return false
	for &cell in cells do cell = {kind = .Empty}
	cursor, row := 0, u32(0)
	for cursor < len(table) {
		line_start, line_end, next := formula_source_line(table, cursor)
		cursor = next
		line := strings.trim_space(string(table[line_start:line_end]))
		if len(line) == 0 || line[0] != '|' || formula_source_separator(line) do continue
		column, cell_start := u32(0), 1
		for cell_start < len(line) && column < column_count {
			cell_end := strings.index_byte(line[cell_start:], '|')
			if cell_end < 0 do return false
			cell_end += cell_start
			text := strings.trim_space(line[cell_start:cell_end])
			if row == 0 do column_names[column] = text
			if value, parsed := strconv.parse_f64(text); parsed {
				cells[int(row * column_count + column)] = {kind = .Number, number = value}
			}
			column += 1
			cell_start = cell_end + 1
		}
		row += 1
	}
	return row == row_count
}

@(private)
formula_source_target :: proc(
	target: string,
	row_count, column_count: u32,
) -> (row, column: u32, ok: bool) {
	if len(target) < 2 do return
	row = 1 if row_count > 1 else 0
	cursor := 0
	if target[0] == '@' {
		cursor = 1
		if cursor < len(target) && target[cursor] == '>' {
			row = row_count - 1
			cursor += 1
		} else {
			value, next, parsed := formula_source_unsigned(target, cursor)
			if !parsed || value == 0 || value > row_count do return 0, 0, false
			row, cursor = value - 1, next
		}
	}
	if cursor >= len(target) || target[cursor] != '$' do return 0, 0, false
	value, next, parsed := formula_source_unsigned(target, cursor + 1)
	if !parsed || value == 0 || value > column_count || next != len(target) do return 0, 0, false
	return row, value - 1, true
}

@(private)
formula_source_expression :: proc(
	expression: string,
	target_row, target_column, row_count, column_count: u32,
) -> (Formula_Instruction, bool) {
	prefix := "vsum("
	if !strings.has_prefix(expression, prefix) || len(expression) <= len(prefix) ||
	   expression[len(expression) - 1] != ')' {
		return {}, false
	}
	range := expression[len(prefix):len(expression) - 1]
	separator := strings.index(range, "..")
	if separator <= 0 || separator + 2 >= len(range) do return {}, false
	row_start, column_start, first_ok := formula_source_reference(
		range[:separator], target_column, row_count, column_count,
	)
	row_end, column_end, second_ok := formula_source_reference(
		range[separator + 2:], target_column, row_count, column_count,
	)
	if !first_ok || !second_ok || row_end < row_start || column_end < column_start do return {}, false
	return {
		kind = .Sum_Range,
		reference = {
			kind = .Range,
			row = i32(row_start),
			column = i32(column_start),
			row_end = i32(row_end),
			column_end = i32(column_end),
		},
	}, true
}

@(private)
formula_source_reference :: proc(
	text: string,
	default_column, row_count, column_count: u32,
) -> (row, column: u32, ok: bool) {
	if len(text) < 2 || text[0] != '@' do return
	row_value, cursor, row_ok := formula_source_unsigned(text, 1)
	if !row_ok || row_value == 0 || row_value > row_count do return 0, 0, false
	column = default_column
	if cursor < len(text) {
		if text[cursor] != '$' do return 0, 0, false
		column_value, next, column_ok := formula_source_unsigned(text, cursor + 1)
		if !column_ok || column_value == 0 || column_value > column_count || next != len(text) {
			return 0, 0, false
		}
		column = column_value - 1
	}
	return row_value - 1, column, true
}

@(private)
formula_source_unsigned :: proc(text: string, start: int) -> (value: u32, next: int, ok: bool) {
	if start < 0 || start >= len(text) do return
	next = start
	for next < len(text) && text[next] >= '0' && text[next] <= '9' {
		value = value * 10 + u32(text[next] - '0')
		next += 1
	}
	return value, next, next > start
}

@(private)
formula_source_line :: proc(source: []u8, start: int) -> (line_start, line_end, next: int) {
	line_start, line_end = start, start
	for line_end < len(source) && source[line_end] != '\r' && source[line_end] != '\n' do line_end += 1
	next = line_end
	if next < len(source) && source[next] == '\r' do next += 1
	if next < len(source) && source[next] == '\n' do next += 1
	return
}

@(private)
formula_source_separator :: proc(line: string) -> bool {
	if len(line) < 3 do return false
	for value in line {
		if value == '-' do return true
		if value != '|' && value != '+' && value != ':' && value != ' ' && value != '\t' do return false
	}
	return false
}

@(private)
formula_source_column_count :: proc(line: string) -> u32 {
	if len(line) < 2 || line[0] != '|' do return 0
	count: u32
	for value in line[1:] do if value == '|' do count += 1
	return count
}

@(private)
formula_source_inspection_state :: proc(
	inspection: ^Formula_Source_Inspection,
) -> ^Formula_Source_Inspection_State {
	if inspection == nil || inspection.state == nil do return nil
	return (^Formula_Source_Inspection_State)(inspection.state)
}

@(private)
formula_source_inspection_state_close :: proc(state: ^Formula_Source_Inspection_State) {
	if state == nil do return
	if state.text != nil do delete(state.text, state.allocator)
	if state.trace != nil do delete(state.trace, state.allocator)
	allocator := state.allocator
	state^ = {}
	free(state, allocator)
}
