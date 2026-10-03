// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_editing

import "../display"
import "../editor"
import "../language"
import "base:runtime"
import "core:strings"
import "core:unicode/utf8"

@(private)
Table_Presentation_State :: struct {
	descriptor: Table_Presentation_Descriptor,
	text:       []u8,
	allocator:  runtime.Allocator,
}

/* table_presentation_prepare copies aligned display text without rewriting source. */
table_presentation_prepare :: proc(
	presentation: ^Table_Presentation,
	analysis: ^language.Jan_Structural_Analysis,
	source: []u8,
	request: Table_Presentation_Request,
	limits := DEFAULT_LIMITS,
	allocator := context.allocator,
	temporary_allocator := context.temp_allocator,
) -> (descriptor: Table_Presentation_Descriptor, ok: bool, failure: Failure) {
	if presentation == nil || presentation.state != nil || analysis == nil ||
	   request.operation_id == Operation_ID(0) || !scope_is_valid(request.scope) ||
	   !limits_are_valid(limits) || allocator.procedure == nil || temporary_allocator.procedure == nil {
		return {}, false, editing_failure(.Prepare_Table_Presentation, .Invalid_Scope, request.scope)
	}
	nodes := language.jan_structural_analysis_nodes(analysis)
	usage, inspected := language.jan_structural_analysis_usage(analysis)
	if !inspected || usage.source_bytes != u64(len(source)) || len(nodes) == 0 ||
	   nodes[0].range.scope != request.scope.analysis {
		return {}, false, editing_failure(.Prepare_Table_Presentation, .Stale, request.scope)
	}
	table, found := navigation_node_by_id(nodes, request.table_id)
	if !found || table.kind != .Pipe_Table {
		return {}, false, editing_failure(.Prepare_Table_Presentation, .Invalid_Target, request.scope)
	}
	model_request := Table_Edit_Request {
		operation_id = request.operation_id,
		scope = request.scope,
		kind = .Cut_Rectangle,
		target_id = table.id,
		rewrite_generation = 1,
		cancel_requested = request.cancel_requested,
	}
	data, modeled, model_failure := table_data_prepare(
		nodes, source, table, model_request, limits, temporary_allocator,
	)
	if !modeled {
		model_failure.operation = .Prepare_Table_Presentation
		return {}, false, model_failure
	}
	defer table_data_close(&data)
	if len(request.columns) != 0 && len(request.columns) != data.columns {
		return {}, false, editing_failure(.Prepare_Table_Presentation, .Invalid_Target, request.scope)
	}
	for policy in request.columns {
		if policy.alignment <= .Invalid || policy.alignment > .Right ||
		   policy.width > 4_096 || policy.truncate && policy.width == 0 {
			return {}, false, editing_failure(.Prepare_Table_Presentation, .Invalid_Target, request.scope)
		}
	}
	widths, widths_error := make([]u16, data.columns, temporary_allocator)
	if widths_error != nil {
		return {}, false, editing_failure(.Prepare_Table_Presentation, .Allocation_Failed, request.scope)
	}
	defer delete(widths, temporary_allocator)
	profile := display.unicode17_profile()
	for row in data.rows {
		if row.separator do continue
		for cell, column in row.cells {
			width, width_ok := table_text_width(cell.value, profile)
			if !width_ok {
				return {}, false, editing_failure(.Prepare_Table_Presentation, .Malformed, request.scope)
			}
			widths[column] = max(widths[column], width)
		}
	}
	for width, column in widths {
		widths[column] = max(width, 1)
		if len(request.columns) == 0 do continue
		policy := request.columns[column]
		if policy.width == 0 do continue
		if policy.truncate {
			widths[column] = policy.width
		} else {
			widths[column] = max(widths[column], policy.width)
		}
	}
	builder, builder_error := strings.builder_make(temporary_allocator)
	if builder_error != nil {
		return {}, false, editing_failure(.Prepare_Table_Presentation, .Allocation_Failed, request.scope)
	}
	defer strings.builder_destroy(&builder)
	truncated: u32
	if !table_write_presentation(&builder, &data, widths, request.columns, profile, &truncated) {
		return {}, false, editing_failure(.Prepare_Table_Presentation, .Allocation_Failed, request.scope)
	}
	text := strings.to_string(builder)
	state, state_error := new(Table_Presentation_State, allocator)
	if state_error != nil {
		return {}, false, editing_failure(.Prepare_Table_Presentation, .Allocation_Failed, request.scope)
	}
	state^ = Table_Presentation_State{allocator = allocator}
	state.text, state_error = make([]u8, len(text), allocator)
	if state_error != nil {
		free(state, allocator)
		return {}, false, editing_failure(.Prepare_Table_Presentation, .Allocation_Failed, request.scope)
	}
	copy(state.text, transmute([]u8)text)
	state.descriptor = {
		operation_id = request.operation_id,
		scope = request.scope,
		table = navigation_target(table),
		rows = u32(len(data.rows)),
		columns = u32(data.columns),
		cells = u32(data.cell_count),
		truncated_cells = truncated,
		retained_bytes = u64(size_of(Table_Presentation_State)) + u64(len(state.text)),
	}
	presentation.state = state
	return state.descriptor, true, {}
}

/* table_presentation_text returns presentation-owned aligned text. */
table_presentation_text :: proc(presentation: ^Table_Presentation) -> (string, bool) {
	state := table_presentation_state(presentation)
	if state == nil do return "", false
	return string(state.text), true
}

/* table_presentation_is_valid reports whether copied display text is live. */
table_presentation_is_valid :: proc(presentation: ^Table_Presentation) -> bool {
	return table_presentation_state(presentation) != nil
}

/* table_formula_inspect exposes adjacent TBLFM syntax without evaluating it. */
table_formula_inspect :: proc(
	analysis: ^language.Jan_Structural_Analysis,
	source: []u8,
	scope: Scope,
	table_id: language.Jan_Node_ID,
) -> (status: Table_Formula_Status, ok: bool, failure: Failure) {
	if analysis == nil || !scope_is_valid(scope) {
		return {}, false, editing_failure(.Inspect_Table_Formula, .Invalid_Scope, scope)
	}
	nodes := language.jan_structural_analysis_nodes(analysis)
	usage, inspected := language.jan_structural_analysis_usage(analysis)
	if !inspected || usage.source_bytes != u64(len(source)) || len(nodes) == 0 ||
	   nodes[0].range.scope != scope.analysis {
		return {}, false, editing_failure(.Inspect_Table_Formula, .Stale, scope)
	}
	table, found := navigation_node_by_id(nodes, table_id)
	if !found || table.kind != .Pipe_Table {
		return {}, false, editing_failure(.Inspect_Table_Formula, .Invalid_Target, scope)
	}
	status.table = navigation_target(table)
	cursor := int(table.range.end)
	for cursor < len(source) && (source[cursor] == '\r' || source[cursor] == '\n') do cursor += 1
	line_end := cursor
	for line_end < len(source) && source[line_end] != '\r' && source[line_end] != '\n' do line_end += 1
	prefix := "#+tblfm:"
	if line_end - cursor >= len(prefix) {
		matches := true
		for byte, index in transmute([]u8)prefix {
			left := source[cursor + index]
			if left >= 'A' && left <= 'Z' do left += 'a' - 'A'
			if left != byte {
				matches = false
				break
			}
		}
		if matches {
			status.present = true
			status.range = {scope = scope.analysis, start = editor.Byte_Offset(cursor), end = editor.Byte_Offset(line_end)}
		}
	}
	return status, true, {}
}

/* table_future_stage_availability retains its API while reporting the linked formula owner. */
table_future_stage_availability :: proc() -> language.Jan_Availability_Record {
	for record in language.jan_future_stage_availability() {
		capability := record.capability
		if string(capability.bytes[:capability.length]) == "jan-computable-tables" do return record
	}
	assert(false, "Jan computable-table availability is missing")
	return {}
}

/* table_presentation_close releases copied display text. */
table_presentation_close :: proc(presentation: ^Table_Presentation) {
	if presentation == nil do return
	state := table_presentation_state(presentation)
	if state != nil {
		if state.text != nil do delete(state.text, state.allocator)
		allocator := state.allocator
		state^ = {}
		free(state, allocator)
	}
	presentation^ = {}
}

/* table_source_alignment_plan_prepare aligns source while preserving cell values. */
table_source_alignment_plan_prepare :: proc(
	plan: ^language.Jan_Rewrite_Plan,
	analysis: ^language.Jan_Structural_Analysis,
	source: []u8,
	request: Table_Presentation_Request,
	generation: language.Jan_Rewrite_Generation,
	limits := DEFAULT_LIMITS,
	allocator := context.allocator,
	temporary_allocator := context.temp_allocator,
) -> (ok: bool, failure: Failure) {
	if plan == nil || generation == language.Jan_Rewrite_Generation(0) {
		return false, editing_failure(.Plan_Table_Edit, .Invalid_Scope, request.scope)
	}
	for policy in request.columns {
		if policy.truncate || policy.group_after {
			return false, editing_failure(.Plan_Table_Edit, .Invalid_Target, request.scope)
		}
	}
	presentation: Table_Presentation
	descriptor, prepared, prepare_failure := table_presentation_prepare(
		&presentation, analysis, source, request, limits,
		temporary_allocator, temporary_allocator,
	)
	if !prepared {
		prepare_failure.operation = .Plan_Table_Edit
		return false, prepare_failure
	}
	defer table_presentation_close(&presentation)
	text, inspected := table_presentation_text(&presentation)
	if !inspected do return false, editing_failure(.Plan_Table_Edit, .Invalid_Target, request.scope)
	planned, jan_failure := jan_editing_prepare_range_rewrite(
		plan, analysis, source, request.scope,
		descriptor.table.range.start, descriptor.table.range.end, text,
		generation, limits, allocator, temporary_allocator,
	)
	if !planned do return false, table_edit_failure_from_language(jan_failure, request.scope)
	return true, {}
}

/* table_focused_cell_inspect derives the exact editable value range. */
table_focused_cell_inspect :: proc(
	analysis: ^language.Jan_Structural_Analysis,
	source: []u8,
	scope: Scope,
	cell_id: language.Jan_Node_ID,
	temporary_allocator := context.temp_allocator,
) -> (cell: Focused_Table_Cell, ok: bool, failure: Failure) {
	if analysis == nil || !scope_is_valid(scope) || temporary_allocator.procedure == nil {
		return {}, false, editing_failure(.Plan_Table_Cell_Edit, .Invalid_Scope, scope)
	}
	nodes := language.jan_structural_analysis_nodes(analysis)
	usage, inspected := language.jan_structural_analysis_usage(analysis)
	if !inspected || usage.source_bytes != u64(len(source)) || len(nodes) == 0 ||
	   nodes[0].range.scope != scope.analysis {
		return {}, false, editing_failure(.Plan_Table_Cell_Edit, .Stale, scope)
	}
	target, found := navigation_node_by_id(nodes, cell_id)
	if !found || target.kind != .Table_Cell {
		return {}, false, editing_failure(.Plan_Table_Cell_Edit, .Invalid_Target, scope)
	}
	row, row_ok := navigation_node_by_id(nodes, target.parent_id)
	if !row_ok do return {}, false, editing_failure(.Plan_Table_Cell_Edit, .Invalid_Target, scope)
	table, table_ok := table_owner(nodes, row)
	if !table_ok do return {}, false, editing_failure(.Plan_Table_Cell_Edit, .Invalid_Target, scope)
	model_request := Table_Edit_Request {
		operation_id = 1, scope = scope, kind = .Cut_Rectangle,
		target_id = table.id, rewrite_generation = 1,
	}
	data, modeled, model_failure := table_data_prepare(
		nodes, source, table, model_request, DEFAULT_LIMITS, temporary_allocator,
	)
	if !modeled {
		model_failure.operation = .Plan_Table_Cell_Edit
		return {}, false, model_failure
	}
	defer table_data_close(&data)
	row_index, row_found := table_row_index(&data, target)
	column_index, column_found := table_column_index(&data, target)
	if !row_found || !column_found {
		return {}, false, editing_failure(.Plan_Table_Cell_Edit, .Invalid_Target, scope)
	}
	modeled_cell := data.rows[row_index].cells[column_index]
	start, end := int(modeled_cell.source_start), int(modeled_cell.source_end)
	if end > start && source[end - 1] == '|' do end -= 1
	for start < end && (source[start] == ' ' || source[start] == '\t') do start += 1
	for end > start && (source[end - 1] == ' ' || source[end - 1] == '\t') do end -= 1
	row_ordinal := table_data_row_ordinal(&data, row_index)
	return {
		target = navigation_target(target),
		selection = {scope = scope.analysis, start = editor.Byte_Offset(start), end = editor.Byte_Offset(end)},
		row = row_ordinal,
		column = u32(column_index),
	}, true, {}
}

/* table_focused_cell_plan_prepare replaces one stored value without table execution. */
table_focused_cell_plan_prepare :: proc(
	plan: ^language.Jan_Rewrite_Plan,
	analysis: ^language.Jan_Structural_Analysis,
	source: []u8,
	request: Table_Cell_Edit_Request,
	limits := DEFAULT_LIMITS,
	allocator := context.allocator,
	temporary_allocator := context.temp_allocator,
) -> (ok: bool, failure: Failure) {
	if plan == nil || request.operation_id == Operation_ID(0) ||
	   request.rewrite_generation == language.Jan_Rewrite_Generation(0) ||
	   !utf8.valid_string(request.text) || table_cell_text_is_invalid(request.text) {
		return false, editing_failure(.Plan_Table_Cell_Edit, .Invalid_Target, request.scope)
	}
	cell, inspected, inspect_failure := table_focused_cell_inspect(
		analysis, source, request.scope, request.cell_id, temporary_allocator,
	)
	if !inspected do return false, inspect_failure
	planned, jan_failure := jan_editing_prepare_range_rewrite(
		plan, analysis, source, request.scope,
		cell.selection.start, cell.selection.end, request.text,
		request.rewrite_generation, limits, allocator, temporary_allocator,
	)
	if !planned do return false, table_cell_failure_from_language(jan_failure, request.scope)
	return true, {}
}

@(private)
table_presentation_state :: proc(presentation: ^Table_Presentation) -> ^Table_Presentation_State {
	if presentation == nil || presentation.state == nil do return nil
	return (^Table_Presentation_State)(presentation.state)
}

@(private)
table_text_width :: proc(text: string, profile: display.Unicode_Profile) -> (u16, bool) {
	offset: u64
	total: u32
	for offset < u64(len(text)) {
		grapheme, grapheme_ok, _ := display.profile_next_grapheme(profile, text, offset)
		if !grapheme_ok || grapheme.end <= offset do return 0, false
		width, width_ok, _ := display.profile_cluster_width(
			profile, text[int(grapheme.start):int(grapheme.end)], total, 4,
		)
		if !width_ok || width.is_line_break do return 0, false
		total += u32(width.cells)
		if total > u32(max(u16)) do return 0, false
		offset = grapheme.end
	}
	return u16(total), true
}

@(private)
table_write_presentation :: proc(
	builder: ^strings.Builder,
	data: ^Table_Data,
	widths: []u16,
	policies: []Table_Column_Policy,
	profile: display.Unicode_Profile,
	truncated: ^u32,
) -> bool {
	for row in data.rows {
		if row.separator {
			if strings.write_byte(builder, '|') != 1 do return false
			for width, column in widths {
				for _ in 0 ..< int(width) + 2 do if strings.write_byte(builder, '-') != 1 do return false
				separator := u8('|')
				if column + 1 < len(widths) do separator = '+'
				if strings.write_byte(builder, separator) != 1 do return false
			}
			if strings.write_byte(builder, '\n') != 1 do return false
			continue
		}
		if strings.write_string(builder, "| ") != 2 do return false
		for cell, column in row.cells {
			policy := Table_Column_Policy{alignment = .Left}
			if len(policies) > 0 do policy = policies[column]
			value_width, width_ok := table_text_width(cell.value, profile)
			if !width_ok do return false
			written_width := value_width
			will_truncate := policy.truncate && value_width > widths[column]
			if will_truncate {
				written_width = widths[column]
				truncated^ += 1
			}
			padding := int(widths[column] - written_width)
			left_padding := 0
			if policy.alignment == .Right do left_padding = padding
			if policy.alignment == .Center do left_padding = padding / 2
			for _ in 0 ..< left_padding do if strings.write_byte(builder, ' ') != 1 do return false
			if will_truncate {
				if !table_write_truncated(builder, cell.value, widths[column], profile) do return false
			} else if strings.write_string(builder, cell.value) != len(cell.value) {
				return false
			}
			for _ in 0 ..< padding - left_padding do if strings.write_byte(builder, ' ') != 1 do return false
			group := len(policies) > 0 && policies[column].group_after && column + 1 < len(row.cells)
			if group {
				if strings.write_string(builder, " || ") != 4 do return false
			} else if column + 1 < len(row.cells) {
				if strings.write_string(builder, " | ") != 3 do return false
			} else if strings.write_string(builder, " |\n") != 3 {
				return false
			}
		}
	}
	return true
}

@(private)
table_write_truncated :: proc(
	builder: ^strings.Builder,
	text: string,
	width: u16,
	profile: display.Unicode_Profile,
) -> bool {
	if width == 0 do return true
	if width == 1 do return strings.write_string(builder, "…") == len("…")
	limit := u32(width - 1)
	offset: u64
	used: u32
	for offset < u64(len(text)) {
		grapheme, ok, _ := display.profile_next_grapheme(profile, text, offset)
		if !ok do return false
		cluster := text[int(grapheme.start):int(grapheme.end)]
		cluster_width, width_ok, _ := display.profile_cluster_width(profile, cluster, used, 4)
		if !width_ok || used + u32(cluster_width.cells) > limit do break
		if strings.write_string(builder, cluster) != len(cluster) do return false
		used += u32(cluster_width.cells)
		offset = grapheme.end
	}
	for used < limit {
		if strings.write_byte(builder, ' ') != 1 do return false
		used += 1
	}
	return strings.write_string(builder, "…") == len("…")
}

@(private)
table_data_row_ordinal :: proc(data: ^Table_Data, row_index: int) -> u32 {
	ordinal: u32
	for index in 0 ..< row_index do if !data.rows[index].separator do ordinal += 1
	return ordinal
}

@(private)
table_cell_text_is_invalid :: proc(text: string) -> bool {
	escaped := false
	for byte in transmute([]u8)text {
		if byte == '\r' || byte == '\n' do return true
		if byte == '|' && !escaped do return true
		if byte == '\\' {
			escaped = !escaped
		} else {
			escaped = false
		}
	}
	return false
}

@(private)
table_cell_failure_from_language :: proc(jan: language.Jan_Failure, scope: Scope) -> Failure {
	failure := table_edit_failure_from_language(jan, scope)
	failure.operation = .Plan_Table_Cell_Edit
	return failure
}
