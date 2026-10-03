// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_editing

import "../editor"
import "../language"
import "base:runtime"
import "core:strings"
import "core:unicode/utf8"

/* list_edit_plan_prepare constructs one checked plain-list rewrite. */
list_edit_plan_prepare :: proc(
	plan: ^language.Jan_Rewrite_Plan,
	analysis: ^language.Jan_Structural_Analysis,
	source: []u8,
	request: List_Edit_Request,
	limits := DEFAULT_LIMITS,
	allocator := context.allocator,
	temporary_allocator := context.temp_allocator,
) -> (ok: bool, failure: Failure) {
	if plan == nil || analysis == nil || !scope_is_valid(request.scope) ||
	   request.operation_id == Operation_ID(0) || request.kind <= .Invalid ||
	   request.kind > .Convert_Region ||
	   request.rewrite_generation == language.Jan_Rewrite_Generation(0) ||
	   !limits_are_valid(limits) || allocator.procedure == nil ||
	   temporary_allocator.procedure == nil || !utf8.valid_string(string(source)) ||
	   !utf8.valid_string(request.text) || heading_text_has_line_break(request.text) {
		return false, editing_failure(.Plan_List_Edit, .Invalid_Scope, request.scope)
	}
	nodes := language.jan_structural_analysis_nodes(analysis)
	usage, inspected := language.jan_structural_analysis_usage(analysis)
	if !inspected || usage.source_bytes != u64(len(source)) || len(nodes) == 0 ||
	   nodes[0].range.scope != request.scope.analysis {
		return false, editing_failure(.Plan_List_Edit, .Stale, request.scope)
	}
	target, found := navigation_node_by_id(nodes, request.target_id)
	if !found || !list_target_matches_operation(target.kind, request.kind) {
		return false, editing_failure(.Plan_List_Edit, .Invalid_Target, request.scope)
	}
	if navigation_node_overlaps_recovery(
		target,
		language.jan_structural_analysis_recoveries(analysis),
	) {
		return false, editing_failure(.Plan_List_Edit, .Malformed, request.scope)
	}

	builder, builder_error := strings.builder_make(temporary_allocator)
	if builder_error != nil {
		return false, editing_failure(.Plan_List_Edit, .Allocation_Failed, request.scope)
	}
	defer strings.builder_destroy(&builder)
	edit_start, edit_end := target.range.start, target.range.end

	switch request.kind {
	case .Insert_Before, .Insert_After:
		if len(request.text) == 0 || request.bullet == .Invalid {
			return false, editing_failure(.Plan_List_Edit, .Invalid_Target, request.scope)
		}
		edit_end = list_item_extent(nodes, source, target)
		item := string(source[int(edit_start):int(edit_end)])
		indent := list_line_indent(source, edit_start)
		if request.kind == .Insert_After {
			if strings.write_string(&builder, item) != len(item) ||
			   !list_write_item(&builder, indent, request.bullet, request.text, request.counter) {
				return false, editing_failure(.Plan_List_Edit, .Allocation_Failed, request.scope)
			}
		} else if !list_write_item(&builder, indent, request.bullet, request.text, request.counter) ||
		          strings.write_string(&builder, item) != len(item) {
			return false, editing_failure(.Plan_List_Edit, .Allocation_Failed, request.scope)
		}
	case .Delete_Item:
		edit_end = list_item_extent(nodes, source, target)
	case .Promote_Item, .Demote_Item:
		edit_end = list_item_extent(nodes, source, target)
		width := request.indent_width
		if width == 0 do width = 2
		if !list_build_indent_shift(
			&builder,
			source[int(edit_start):int(edit_end)],
			int(width),
			request.kind == .Demote_Item,
		) {
			return false, editing_failure(.Plan_List_Edit, .Invalid_Target, request.scope)
		}
	case .Move_Up, .Move_Down:
		edit_end = list_item_extent(nodes, source, target)
		sibling, sibling_ok := list_sibling(
			nodes,
			source,
			target,
			request.kind == .Move_Down,
		)
		if !sibling_ok {
			return false, editing_failure(.Plan_List_Edit, .Invalid_Target, request.scope)
		}
		sibling_end := list_item_extent(nodes, source, sibling)
		first, first_end := target, edit_end
		second, second_end := sibling, sibling_end
		if second.range.start < first.range.start {
			first, second = second, first
			first_end, second_end = second_end, first_end
		}
		edit_start, edit_end = first.range.start, second_end
		first_text := string(source[int(first.range.start):int(first_end)])
		middle := string(source[int(first_end):int(second.range.start)])
		second_text := string(source[int(second.range.start):int(second_end)])
		if strings.write_string(&builder, second_text) != len(second_text) ||
		   strings.write_string(&builder, middle) != len(middle) ||
		   strings.write_string(&builder, first_text) != len(first_text) {
			return false, editing_failure(.Plan_List_Edit, .Allocation_Failed, request.scope)
		}
	case .Duplicate_Item:
		edit_end = list_item_extent(nodes, source, target)
		item := string(source[int(edit_start):int(edit_end)])
		if strings.write_string(&builder, item) != len(item) ||
		   strings.write_string(&builder, item) != len(item) {
			return false, editing_failure(.Plan_List_Edit, .Allocation_Failed, request.scope)
		}
	case .Sort_Items:
		if !list_build_sorted_items(
			&builder,
			nodes,
			source,
			target,
			limits,
			temporary_allocator,
			&edit_start,
			&edit_end,
		) {
			return false, editing_failure(.Plan_List_Edit, .Invalid_Target, request.scope)
		}
	case .Select_Bullet:
		if request.bullet == .Invalid ||
		   !list_build_selected_bullet(&builder, source, target, request.bullet) {
			return false, editing_failure(.Plan_List_Edit, .Invalid_Target, request.scope)
		}
	case .Set_Counter:
		if request.counter == 0 || !list_build_counter(&builder, source, target, request.counter) {
			return false, editing_failure(.Plan_List_Edit, .Invalid_Target, request.scope)
		}
	case .Repair_Indentation:
		edit_end = list_item_extent(nodes, source, target)
		width := request.indent_width
		if width == 0 do width = 2
		if !list_build_repaired_indentation(
			&builder,
			source[int(edit_start):int(edit_end)],
			list_line_indent(source, edit_start),
			int(width),
		) {
			return false, editing_failure(.Plan_List_Edit, .Allocation_Failed, request.scope)
		}
	case .Convert_Region:
		if request.bullet == .Invalid ||
		   !list_build_region_conversion(
			&builder,
			source[int(edit_start):int(edit_end)],
			request.bullet,
		) {
			return false, editing_failure(.Plan_List_Edit, .Invalid_Target, request.scope)
		}
	case .Invalid:
	}
	for recovery in language.jan_structural_analysis_recoveries(analysis) {
		if recovery.range.start < edit_end && recovery.range.end > edit_start {
			return false, editing_failure(.Plan_List_Edit, .Malformed, request.scope)
		}
	}

	replacement := ""
	if request.kind != .Delete_Item do replacement = strings.to_string(builder)
	planned, jan_failure := jan_editing_prepare_range_rewrite(
		plan,
		analysis,
		source,
		request.scope,
		edit_start,
		edit_end,
		replacement,
		request.rewrite_generation,
		limits,
		allocator,
		temporary_allocator,
	)
	if !planned do return false, list_edit_failure_from_language(jan_failure, request.scope)
	return true, {}
}

@(private)
jan_editing_prepare_range_rewrite :: proc(
	plan: ^language.Jan_Rewrite_Plan,
	analysis: ^language.Jan_Structural_Analysis,
	source: []u8,
	scope: Scope,
	edit_start, edit_end: editor.Byte_Offset,
	replacement: string,
	generation: language.Jan_Rewrite_Generation,
	limits: Limits,
	allocator, temporary_allocator: runtime.Allocator,
) -> (bool, language.Jan_Failure) {
	if edit_start > edit_end || u64(edit_end) > u64(len(source)) {
		return false, language.Jan_Failure{code = .Invalid_Range, scope = scope.analysis}
	}
	nodes := language.jan_structural_analysis_nodes(analysis)
	owner: language.Jan_Node_Record
	found := false
	for node in nodes {
		if node.layer == .Inline || node.layer == .Recovery ||
		   node.range.start > edit_start || node.range.end < edit_end {
			continue
		}
		if !found || node.range.end - node.range.start < owner.range.end - owner.range.start {
			owner, found = node, true
		}
	}
	if !found {
		return false, language.Jan_Failure{code = .Invalid_Node, scope = scope.analysis}
	}
	builder, builder_error := strings.builder_make(temporary_allocator)
	if builder_error != nil {
		return false, language.Jan_Failure{code = .Allocation_Failed, scope = scope.analysis}
	}
	defer strings.builder_destroy(&builder)
	prefix := string(source[int(owner.range.start):int(edit_start)])
	suffix := string(source[int(edit_end):int(owner.range.end)])
	if strings.write_string(&builder, prefix) != len(prefix) ||
	   strings.write_string(&builder, replacement) != len(replacement) ||
	   strings.write_string(&builder, suffix) != len(suffix) {
		return false, language.Jan_Failure{code = .Allocation_Failed, scope = scope.analysis}
	}
	requests := [1]language.Jan_Rewrite_Request{{
		node_id = owner.id,
		range = owner.range,
		replacement = strings.to_string(builder),
	}}
	jan_limits := language.DEFAULT_JAN_RESOURCE_LIMITS
	jan_limits.rewrite_splices = min(jan_limits.rewrite_splices, limits.rewrite_splices)
	return language.jan_rewrite_plan_prepare(
		plan,
		analysis,
		source,
		generation,
		requests[:],
		jan_limits,
		allocator,
	)
}

@(private)
list_target_matches_operation :: proc(
	kind: language.Jan_Node_Kind,
	operation: List_Edit_Kind,
) -> bool {
	if operation == .Sort_Items do return kind == .Plain_List
	if operation == .Convert_Region do return kind == .Paragraph
	return kind == .List_Item
}

@(private)
list_item_extent :: proc(
	nodes: []language.Jan_Node_Record,
	source: []u8,
	item: language.Jan_Node_Record,
) -> editor.Byte_Offset {
	end := item.range.end
	indent := list_line_indent(source, item.range.start)
	cursor := int(end)
	for cursor < len(source) {
		line_start := cursor
		line_end := cursor
		for line_end < len(source) && source[line_end] != '\r' && source[line_end] != '\n' do line_end += 1
		next := line_end
		if next < len(source) && source[next] == '\r' do next += 1
		if next < len(source) && source[next] == '\n' do next += 1
		blank := true
		for index in line_start ..< line_end {
			if source[index] != ' ' && source[index] != '\t' {
				blank = false
				break
			}
		}
		if blank {
			cursor = next
			end = editor.Byte_Offset(next)
			continue
		}
		line_indent := list_source_indent(source[line_start:line_end])
		if line_indent <= indent do break
		end = editor.Byte_Offset(next)
		cursor = next
	}
	return end
}

@(private)
list_sibling :: proc(
	nodes: []language.Jan_Node_Record,
	source: []u8,
	target: language.Jan_Node_Record,
	forward: bool,
) -> (candidate: language.Jan_Node_Record, found: bool) {
	indent := list_line_indent(source, target.range.start)
	for node in nodes {
		if node.kind != .List_Item || node.parent_id != target.parent_id ||
		   list_line_indent(source, node.range.start) != indent {
			continue
		}
		if forward {
			if node.range.start <= target.range.start do continue
			if !found || node.range.start < candidate.range.start do candidate, found = node, true
		} else {
			if node.range.start >= target.range.start do continue
			if !found || node.range.start > candidate.range.start do candidate, found = node, true
		}
	}
	return
}

@(private)
list_build_indent_shift :: proc(
	builder: ^strings.Builder,
	text: []u8,
	width: int,
	demote: bool,
) -> bool {
	line_start := true
	for index := 0; index < len(text); {
		if line_start {
			if demote {
				for _ in 0 ..< width do if strings.write_byte(builder, ' ') != 1 do return false
			} else {
				removed := 0
				for index < len(text) && removed < width && text[index] == ' ' {
					index += 1
					removed += 1
				}
				if removed < width do return false
			}
			line_start = false
		}
		if index >= len(text) do break
		if strings.write_byte(builder, text[index]) != 1 do return false
		line_start = text[index] == '\n'
		index += 1
	}
	return true
}

@(private)
list_build_selected_bullet :: proc(
	builder: ^strings.Builder,
	source: []u8,
	item: language.Jan_Node_Record,
	bullet: List_Bullet_Kind,
) -> bool {
	indent := list_line_indent(source, item.range.start)
	marker_end, ok := list_marker_end(source, item.range.start, item.range.end)
	if !ok do return false
	for _ in 0 ..< indent do if strings.write_byte(builder, ' ') != 1 do return false
	if !list_write_marker(builder, bullet, 1) do return false
	rest := string(source[int(marker_end):int(item.range.end)])
	return strings.write_string(builder, rest) == len(rest)
}

@(private)
list_build_counter :: proc(
	builder: ^strings.Builder,
	source: []u8,
	item: language.Jan_Node_Record,
	counter: u32,
) -> bool {
	marker_end, marker_ok := list_marker_end(source, item.range.start, item.range.end)
	if !marker_ok || !list_marker_is_ordered(source, item.range.start, marker_end) do return false
	prefix := string(source[int(item.range.start):int(marker_end)])
	if strings.write_string(builder, prefix) != len(prefix) do return false
	cursor := int(marker_end)
	for cursor < int(item.range.end) && (source[cursor] == ' ' || source[cursor] == '\t') do cursor += 1
	if cursor + 3 < int(item.range.end) && source[cursor] == '[' && source[cursor + 1] == '@' {
		for cursor < int(item.range.end) && source[cursor] != ']' do cursor += 1
		if cursor < int(item.range.end) do cursor += 1
		for cursor < int(item.range.end) && (source[cursor] == ' ' || source[cursor] == '\t') do cursor += 1
	}
	if strings.write_string(builder, " [@") != 3 || !list_write_u32(builder, counter) ||
	   strings.write_string(builder, "] ") != 2 {
		return false
	}
	rest := string(source[cursor:int(item.range.end)])
	return strings.write_string(builder, rest) == len(rest)
}

@(private)
list_build_repaired_indentation :: proc(
	builder: ^strings.Builder,
	text: []u8,
	base_indent, width: int,
) -> bool {
	line := 0
	for cursor := 0; cursor < len(text); line += 1 {
		end := cursor
		for end < len(text) && text[end] != '\n' do end += 1
		if line == 0 {
			segment := string(text[cursor:min(end + 1, len(text))])
			if strings.write_string(builder, segment) != len(segment) do return false
			cursor = min(end + 1, len(text))
			continue
		}
		content := cursor
		for content < end && (text[content] == ' ' || text[content] == '\t') do content += 1
		if content < end {
			existing := content - cursor
			for _ in 0 ..< max(existing, base_indent + width) {
				if strings.write_byte(builder, ' ') != 1 do return false
			}
		}
		segment := string(text[content:min(end + 1, len(text))])
		if strings.write_string(builder, segment) != len(segment) do return false
		cursor = min(end + 1, len(text))
	}
	return true
}

@(private)
list_build_region_conversion :: proc(
	builder: ^strings.Builder,
	text: []u8,
	bullet: List_Bullet_Kind,
) -> bool {
	for cursor := 0; cursor < len(text); {
		end := cursor
		for end < len(text) && text[end] != '\n' do end += 1
		content := cursor
		for content < end && (text[content] == ' ' || text[content] == '\t') do content += 1
		if content < end {
			if !list_write_marker(builder, bullet, 1) || strings.write_byte(builder, ' ') != 1 {
				return false
			}
			line := string(text[content:end])
			if strings.write_string(builder, line) != len(line) do return false
		}
		if end < len(text) && strings.write_byte(builder, '\n') != 1 do return false
		cursor = min(end + 1, len(text))
	}
	return true
}

@(private)
list_build_sorted_items :: proc(
	builder: ^strings.Builder,
	nodes: []language.Jan_Node_Record,
	source: []u8,
	list: language.Jan_Node_Record,
	limits: Limits,
	allocator: runtime.Allocator,
	edit_start, edit_end: ^editor.Byte_Offset,
) -> bool {
	items, allocation_error := make(
		[dynamic]language.Jan_Node_Record,
		0,
		min(len(nodes), int(limits.semantic_targets) + 1),
		allocator,
	)
	if allocation_error != nil do return false
	defer delete(items)
	for node in nodes {
		if node.kind != .List_Item || node.parent_id != list.id do continue
		if len(items) >= int(limits.semantic_targets) do return false
		if _, append_error := append(&items, node); append_error != nil do return false
	}
	if len(items) < 2 do return false
	for index in 1 ..< len(items) {
		item := items[index]
		cursor := index
		for cursor > 0 && list_item_key_less(source, item, items[cursor - 1]) {
			items[cursor] = items[cursor - 1]
			cursor -= 1
		}
		items[cursor] = item
	}
	start := items[0].range.start
	end := list_item_extent(nodes, source, items[0])
	for item in items {
		start = min(start, item.range.start)
		end = max(end, list_item_extent(nodes, source, item))
	}
	for item in items {
		item_end := list_item_extent(nodes, source, item)
		text := string(source[int(item.range.start):int(item_end)])
		if strings.write_string(builder, text) != len(text) do return false
	}
	edit_start^, edit_end^ = start, end
	return true
}

@(private)
list_item_key_less :: proc(source: []u8, left, right: language.Jan_Node_Record) -> bool {
	left_start, left_ok := list_marker_end(source, left.range.start, left.range.end)
	right_start, right_ok := list_marker_end(source, right.range.start, right.range.end)
	if !left_ok || !right_ok do return left.range.start < right.range.start
	for int(left_start) < int(left.range.end) &&
	    (source[int(left_start)] == ' ' || source[int(left_start)] == '\t') {
		left_start += 1
	}
	for int(right_start) < int(right.range.end) &&
	    (source[int(right_start)] == ' ' || source[int(right_start)] == '\t') {
		right_start += 1
	}
	left_text := source[int(left_start):int(left.range.end)]
	right_text := source[int(right_start):int(right.range.end)]
	limit := min(len(left_text), len(right_text))
	for index in 0 ..< limit {
		if left_text[index] != right_text[index] do return left_text[index] < right_text[index]
	}
	return len(left_text) < len(right_text)
}

@(private)
list_write_item :: proc(
	builder: ^strings.Builder,
	indent: int,
	bullet: List_Bullet_Kind,
	text: string,
	counter: u32,
) -> bool {
	for _ in 0 ..< indent do if strings.write_byte(builder, ' ') != 1 do return false
	if !list_write_marker(builder, bullet, max(counter, 1)) || strings.write_byte(builder, ' ') != 1 {
		return false
	}
	if counter > 0 && (bullet == .Ordered_Dot || bullet == .Ordered_Paren) {
		if strings.write_string(builder, "[@") != 2 || !list_write_u32(builder, counter) ||
		   strings.write_string(builder, "] ") != 2 {
			return false
		}
	}
	return strings.write_string(builder, text) == len(text) &&
	       strings.write_byte(builder, '\n') == 1
}

@(private)
list_write_marker :: proc(builder: ^strings.Builder, bullet: List_Bullet_Kind, value: u32) -> bool {
	switch bullet {
	case .Unordered_Dash, .Descriptive: return strings.write_byte(builder, '-') == 1
	case .Unordered_Plus: return strings.write_byte(builder, '+') == 1
	case .Unordered_Star: return strings.write_byte(builder, '*') == 1
	case .Ordered_Dot:
		return list_write_u32(builder, value) && strings.write_byte(builder, '.') == 1
	case .Ordered_Paren:
		return list_write_u32(builder, value) && strings.write_byte(builder, ')') == 1
	case .Invalid:
	}
	return false
}

@(private)
list_write_u32 :: proc(builder: ^strings.Builder, value: u32) -> bool {
	buffer: [10]u8
	length: int
	remaining := value
	if remaining == 0 {
		buffer[0] = '0'
		length = 1
	} else {
		for remaining > 0 {
			buffer[length] = u8(remaining % 10) + '0'
			remaining /= 10
			length += 1
		}
	}
	for index := length - 1; index >= 0; index -= 1 {
		if strings.write_byte(builder, buffer[index]) != 1 do return false
	}
	return true
}

@(private)
list_marker_end :: proc(
	source: []u8,
	start, end: editor.Byte_Offset,
) -> (editor.Byte_Offset, bool) {
	cursor := int(start)
	limit := min(int(end), len(source))
	for cursor < limit && (source[cursor] == ' ' || source[cursor] == '\t') do cursor += 1
	if cursor >= limit do return 0, false
	if source[cursor] == '-' || source[cursor] == '+' || source[cursor] == '*' {
		return editor.Byte_Offset(cursor + 1), true
	}
	if (source[cursor] >= '0' && source[cursor] <= '9') ||
	   (source[cursor] >= 'A' && source[cursor] <= 'Z') ||
	   (source[cursor] >= 'a' && source[cursor] <= 'z') {
		cursor += 1
		for cursor < limit && source[cursor] >= '0' && source[cursor] <= '9' do cursor += 1
		if cursor < limit && (source[cursor] == '.' || source[cursor] == ')') {
			return editor.Byte_Offset(cursor + 1), true
		}
	}
	return 0, false
}

@(private)
list_marker_is_ordered :: proc(source: []u8, start, marker_end: editor.Byte_Offset) -> bool {
	cursor := int(start)
	for cursor < int(marker_end) && (source[cursor] == ' ' || source[cursor] == '\t') do cursor += 1
	return cursor < int(marker_end) && source[cursor] != '-' && source[cursor] != '+' &&
	       source[cursor] != '*'
}

@(private)
list_line_indent :: proc(source: []u8, start: editor.Byte_Offset) -> int {
	return list_source_indent(source[int(start):])
}

@(private)
list_source_indent :: proc(source: []u8) -> int {
	indent: int
	for indent < len(source) {
		if source[indent] == ' ' {
			indent += 1
		} else if source[indent] == '\t' {
			indent += 4
		} else {
			break
		}
	}
	return indent
}

@(private)
list_edit_failure_from_language :: proc(jan: language.Jan_Failure, scope: Scope) -> Failure {
	code := Failure_Code.Invalid_Target
	#partial switch jan.code {
	case .Stale, .Incomplete: code = .Stale
	case .Limited: code = .Limited
	case .Allocation_Failed: code = .Allocation_Failed
	case .Malformed: code = .Malformed
	case .Cancelled: code = .Cancelled
	}
	return {
		operation = .Plan_List_Edit,
		code = code,
		scope = scope,
		limit = jan.limit,
		actual = jan.actual,
	}
}
