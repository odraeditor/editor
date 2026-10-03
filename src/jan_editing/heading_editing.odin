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

@(private)
Subtree_Copy_State :: struct {
	descriptor: Subtree_Copy_Descriptor,
	text:       []u8,
	allocator:  runtime.Allocator,
}

/* heading_edit_plan_prepare constructs one checked Stage 2 rewrite plan. */
heading_edit_plan_prepare :: proc(
	plan: ^language.Jan_Rewrite_Plan,
	analysis: ^language.Jan_Structural_Analysis,
	source: []u8,
	request: Heading_Edit_Request,
	limits := DEFAULT_LIMITS,
	allocator := context.allocator,
	temporary_allocator := context.temp_allocator,
) -> (ok: bool, failure: Failure) {
	if plan == nil || analysis == nil || !scope_is_valid(request.scope) ||
	   request.operation_id == Operation_ID(0) || request.kind <= .Invalid ||
	   request.kind > .List_Item_To_Heading ||
	   request.rewrite_generation == language.Jan_Rewrite_Generation(0) ||
	   !limits_are_valid(limits) || allocator.procedure == nil ||
	   temporary_allocator.procedure == nil || !utf8.valid_string(string(source)) ||
	   !utf8.valid_string(request.text) || heading_text_has_line_break(request.text) {
		return false, editing_failure(.Plan_Heading_Edit, .Invalid_Scope, request.scope)
	}
	nodes := language.jan_structural_analysis_nodes(analysis)
	usage, inspected := language.jan_structural_analysis_usage(analysis)
	if !inspected || usage.source_bytes != u64(len(source)) || len(nodes) == 0 ||
	   nodes[0].range.scope != request.scope.analysis {
		return false, editing_failure(.Plan_Heading_Edit, .Stale, request.scope)
	}
	target, found := navigation_node_by_id(nodes, request.target_id)
	if !found || !heading_edit_target_kind_matches(target.kind, request.kind) {
		return false, editing_failure(.Plan_Heading_Edit, .Invalid_Target, request.scope)
	}
	if navigation_node_overlaps_recovery(
		target,
		language.jan_structural_analysis_recoveries(analysis),
	) {
		return false, editing_failure(.Plan_Heading_Edit, .Malformed, request.scope)
	}

	requests: [2]language.Jan_Rewrite_Request
	request_count: int
	builder, builder_error := strings.builder_make(temporary_allocator)
	if builder_error != nil {
		return false, editing_failure(.Plan_Heading_Edit, .Allocation_Failed, request.scope)
	}
	defer strings.builder_destroy(&builder)

	switch request.kind {
	case .Insert_Before, .Insert_After, .Insert_Below:
		if len(request.text) == 0 {
			return false, editing_failure(.Plan_Heading_Edit, .Invalid_Target, request.scope)
		}
		level := target.structural_depth
		if request.kind == .Insert_Below {
			if level >= language.MAX_JAN_STRUCTURAL_DEPTH {
				return false, editing_failure(.Plan_Heading_Edit, .Limited, request.scope)
			}
			level += 1
		}
		if !heading_build_insertion(&builder, source, target, request.kind, level, request.text) {
			return false, editing_failure(.Plan_Heading_Edit, .Allocation_Failed, request.scope)
		}
		requests[0] = {
			node_id = target.id,
			range = target.range,
			replacement = strings.to_string(builder),
		}
		request_count = 1
	case .Split:
		if !heading_build_split(&builder, source, target, request.split_offset) {
			return false, editing_failure(.Plan_Heading_Edit, .Invalid_Target, request.scope)
		}
		requests[0] = {node_id = target.id, range = target.range, replacement = strings.to_string(builder)}
		request_count = 1
	case .Promote_Text:
		level := request.level
		if level == 0 do level = 1
		if level > language.MAX_JAN_STRUCTURAL_DEPTH ||
		   !heading_write_marker(&builder, level) ||
		   strings.write_byte(&builder, ' ') != 1 ||
		   strings.write_string(&builder, string(source[int(target.range.start):int(target.range.end)])) !=
			len(source[int(target.range.start):int(target.range.end)]) {
			return false, editing_failure(.Plan_Heading_Edit, .Limited, request.scope)
		}
		requests[0] = {node_id = target.id, range = target.range, replacement = strings.to_string(builder)}
		request_count = 1
	case .Promote_Heading, .Demote_Heading:
		promote := request.kind == .Promote_Heading
		if !heading_levels_are_admitted(nodes, target, promote) ||
		   !heading_build_level_change(&builder, nodes, source, target, promote) {
			return false, editing_failure(.Plan_Heading_Edit, .Invalid_Target, request.scope)
		}
		requests[0] = {node_id = target.id, range = target.range, replacement = strings.to_string(builder)}
		request_count = 1
	case .Move_Up, .Move_Down:
		sibling, sibling_ok, _ := navigation_sibling(
			nodes,
			target,
			request.kind == .Move_Down,
			nil,
		)
		if !sibling_ok {
			return false, editing_failure(.Plan_Heading_Edit, .Invalid_Target, request.scope)
		}
		requests[0] = {
			node_id = target.id,
			range = target.range,
			replacement = string(source[int(sibling.range.start):int(sibling.range.end)]),
		}
		requests[1] = {
			node_id = sibling.id,
			range = sibling.range,
			replacement = string(source[int(target.range.start):int(target.range.end)]),
		}
		request_count = 2
	case .Clone_Subtree:
		text := string(source[int(target.range.start):int(target.range.end)])
		if strings.write_string(&builder, text) != len(text) ||
		   strings.write_string(&builder, text) != len(text) {
			return false, editing_failure(.Plan_Heading_Edit, .Allocation_Failed, request.scope)
		}
		requests[0] = {node_id = target.id, range = target.range, replacement = strings.to_string(builder)}
		request_count = 1
	case .Kill_Subtree:
		requests[0] = {node_id = target.id, range = target.range, replacement = ""}
		request_count = 1
	case .Sort_Children:
		if !heading_build_sorted_children(
			&builder,
			nodes,
			source,
			target,
			limits,
			temporary_allocator,
		) {
			return false, editing_failure(.Plan_Heading_Edit, .Invalid_Target, request.scope)
		}
		requests[0] = {node_id = target.id, range = target.range, replacement = strings.to_string(builder)}
		request_count = 1
	case .Heading_To_List_Item:
		if !heading_is_leaf(nodes, target) ||
		   !heading_build_heading_to_list(&builder, source, target) {
			return false, editing_failure(.Plan_Heading_Edit, .Invalid_Target, request.scope)
		}
		requests[0] = {node_id = target.id, range = target.range, replacement = strings.to_string(builder)}
		request_count = 1
	case .List_Item_To_Heading:
		level := request.level
		if level == 0 do level = 1
		if level > language.MAX_JAN_STRUCTURAL_DEPTH ||
		   !heading_build_list_to_heading(&builder, source, target, level) {
			return false, editing_failure(.Plan_Heading_Edit, .Invalid_Target, request.scope)
		}
		requests[0] = {node_id = target.id, range = target.range, replacement = strings.to_string(builder)}
		request_count = 1
	case .Invalid:
	}

	jan_limits := language.DEFAULT_JAN_RESOURCE_LIMITS
	jan_limits.rewrite_splices = min(jan_limits.rewrite_splices, limits.rewrite_splices)
	planned, jan_failure := language.jan_rewrite_plan_prepare(
		plan,
		analysis,
		source,
		request.rewrite_generation,
		requests[:request_count],
		jan_limits,
		allocator,
	)
	if !planned do return false, heading_edit_failure_from_language(jan_failure, request.scope)
	return true, {}
}

/* subtree_copy_prepare owns one exact copied subtree independently from analysis. */
subtree_copy_prepare :: proc(
	copy_state: ^Subtree_Copy,
	analysis: ^language.Jan_Structural_Analysis,
	source: []u8,
	operation_id: Operation_ID,
	scope: Scope,
	heading_id: language.Jan_Node_ID,
	allocator := context.allocator,
) -> (descriptor: Subtree_Copy_Descriptor, ok: bool, failure: Failure) {
	if copy_state == nil || copy_state.state != nil || analysis == nil ||
	   operation_id == Operation_ID(0) || !scope_is_valid(scope) || allocator.procedure == nil {
		return {}, false, editing_failure(.Copy_Subtree, .Invalid_Scope, scope)
	}
	nodes := language.jan_structural_analysis_nodes(analysis)
	usage, inspected := language.jan_structural_analysis_usage(analysis)
	if !inspected || usage.source_bytes != u64(len(source)) || len(nodes) == 0 ||
	   nodes[0].range.scope != scope.analysis {
		return {}, false, editing_failure(.Copy_Subtree, .Stale, scope)
	}
	heading, found := navigation_node_by_id(nodes, heading_id)
	if !found || heading.kind != .Heading || navigation_node_overlaps_recovery(
		heading,
		language.jan_structural_analysis_recoveries(analysis),
	) {
		return {}, false, editing_failure(.Copy_Subtree, .Invalid_Target, scope)
	}
	state, state_error := new(Subtree_Copy_State, allocator)
	if state_error != nil {
		return {}, false, editing_failure(.Copy_Subtree, .Allocation_Failed, scope)
	}
	state^ = Subtree_Copy_State{allocator = allocator}
	count := int(heading.range.end - heading.range.start)
	state.text, state_error = make([]u8, count, allocator)
	if state_error != nil {
		free(state, allocator)
		return {}, false, editing_failure(.Copy_Subtree, .Allocation_Failed, scope)
	}
	copy(state.text, source[int(heading.range.start):int(heading.range.end)])
	state.descriptor = {
		operation_id = operation_id,
		scope = scope.analysis,
		target = navigation_target(heading),
		retained_bytes = u64(size_of(Subtree_Copy_State)) + u64(len(state.text)),
	}
	copy_state.state = state
	return state.descriptor, true, {}
}

/* subtree_copy_text borrows copied bytes until the next close. */
subtree_copy_text :: proc(copy_state: ^Subtree_Copy) -> (string, bool) {
	state := subtree_copy_state(copy_state)
	if state == nil do return "", false
	return string(state.text), true
}

/* subtree_insert_plan_prepare inserts one exact copied subtree beside a current heading. */
subtree_insert_plan_prepare :: proc(
	plan: ^language.Jan_Rewrite_Plan,
	copy_state: ^Subtree_Copy,
	analysis: ^language.Jan_Structural_Analysis,
	source: []u8,
	scope: Scope,
	destination_id: language.Jan_Node_ID,
	after: bool,
	rewrite_generation: language.Jan_Rewrite_Generation,
	allocator := context.allocator,
	temporary_allocator := context.temp_allocator,
) -> (ok: bool, failure: Failure) {
	state := subtree_copy_state(copy_state)
	if state == nil || state.descriptor.scope != scope.analysis {
		return false, editing_failure(.Plan_Heading_Edit, .Stale, scope)
	}
	nodes := language.jan_structural_analysis_nodes(analysis)
	destination, found := navigation_node_by_id(nodes, destination_id)
	if !found || destination.kind != .Heading {
		return false, editing_failure(.Plan_Heading_Edit, .Invalid_Target, scope)
	}
	builder, builder_error := strings.builder_make(temporary_allocator)
	if builder_error != nil {
		return false, editing_failure(.Plan_Heading_Edit, .Allocation_Failed, scope)
	}
	defer strings.builder_destroy(&builder)
	destination_text := string(source[int(destination.range.start):int(destination.range.end)])
	copy_text := string(state.text)
	if after {
		if strings.write_string(&builder, destination_text) != len(destination_text) ||
		   strings.write_string(&builder, copy_text) != len(copy_text) {
			return false, editing_failure(.Plan_Heading_Edit, .Allocation_Failed, scope)
		}
	} else {
		if strings.write_string(&builder, copy_text) != len(copy_text) ||
		   strings.write_string(&builder, destination_text) != len(destination_text) {
			return false, editing_failure(.Plan_Heading_Edit, .Allocation_Failed, scope)
		}
	}
	request := [1]language.Jan_Rewrite_Request{{
		node_id = destination.id,
		range = destination.range,
		replacement = strings.to_string(builder),
	}}
	planned, jan_failure := language.jan_rewrite_plan_prepare(
		plan,
		analysis,
		source,
		rewrite_generation,
		request[:],
		allocator = allocator,
	)
	if !planned do return false, heading_edit_failure_from_language(jan_failure, scope)
	return true, {}
}

/* subtree_copy_close releases copied source exactly once. */
subtree_copy_close :: proc(copy_state: ^Subtree_Copy) {
	state := subtree_copy_state(copy_state)
	if state == nil do return
	allocator := state.allocator
	if state.text != nil do delete(state.text, allocator)
	state^ = {}
	free(state, allocator)
	copy_state.state = nil
}

@(private)
subtree_copy_state :: proc(copy_state: ^Subtree_Copy) -> ^Subtree_Copy_State {
	if copy_state == nil || copy_state.state == nil do return nil
	return cast(^Subtree_Copy_State)copy_state.state
}

@(private)
heading_edit_target_kind_matches :: proc(
	kind: language.Jan_Node_Kind,
	operation: Heading_Edit_Kind,
) -> bool {
	if operation == .Promote_Text do return kind == .Paragraph
	if operation == .List_Item_To_Heading do return kind == .List_Item
	return kind == .Heading
}

@(private)
heading_build_insertion :: proc(
	builder: ^strings.Builder,
	source: []u8,
	target: language.Jan_Node_Record,
	kind: Heading_Edit_Kind,
	level: u16,
	title: string,
) -> bool {
	text := string(source[int(target.range.start):int(target.range.end)])
	if kind == .Insert_After {
		return strings.write_string(builder, text) == len(text) &&
		       heading_write_line(builder, level, title)
	}
	if kind == .Insert_Before {
		return heading_write_line(builder, level, title) &&
		       strings.write_string(builder, text) == len(text)
	}
	header_end := int(outline_heading_line_end(source, target))
	header := string(source[int(target.range.start):header_end])
	body := string(source[header_end:int(target.range.end)])
	return strings.write_string(builder, header) == len(header) &&
	       heading_write_line(builder, level, title) &&
	       strings.write_string(builder, body) == len(body)
}

@(private)
heading_build_split :: proc(
	builder: ^strings.Builder,
	source: []u8,
	target: language.Jan_Node_Record,
	split: editor.Byte_Offset,
) -> bool {
	line_end := outline_heading_line_end(source, target)
	content_start := target.range.start + editor.Byte_Offset(target.structural_depth)
	for content_start < line_end &&
	    (source[int(content_start)] == ' ' || source[int(content_start)] == '\t') {
		content_start += 1
	}
	if split <= content_start || split >= line_end ||
	   !language.jan_source_range_is_valid(
		{scope = target.range.scope, start = split, end = split},
		u64(len(source)),
	) || !heading_utf8_boundary(source, split) {
		return false
	}
	left_end := int(split)
	for left_end > int(content_start) &&
	    (source[left_end - 1] == ' ' || source[left_end - 1] == '\t') {
		left_end -= 1
	}
	right_start := int(split)
	for right_start < int(line_end) &&
	    (source[right_start] == ' ' || source[right_start] == '\t') {
		right_start += 1
	}
	if left_end <= int(content_start) || right_start >= int(line_end) do return false
	left := string(source[int(target.range.start):left_end])
	right := string(source[right_start:int(target.range.end)])
	return strings.write_string(builder, left) == len(left) &&
	       strings.write_byte(builder, '\n') == 1 &&
	       heading_write_marker(builder, target.structural_depth) &&
	       strings.write_byte(builder, ' ') == 1 &&
	       strings.write_string(builder, right) == len(right)
}

@(private)
heading_levels_are_admitted :: proc(
	nodes: []language.Jan_Node_Record,
	target: language.Jan_Node_Record,
	promote: bool,
) -> bool {
	for node in nodes {
		if node.kind != .Heading || node.range.start < target.range.start ||
		   node.range.start >= target.range.end {
			continue
		}
		if promote && node.structural_depth <= 1 do return false
		if !promote && node.structural_depth >= language.MAX_JAN_STRUCTURAL_DEPTH do return false
	}
	return true
}

@(private)
heading_build_level_change :: proc(
	builder: ^strings.Builder,
	nodes: []language.Jan_Node_Record,
	source: []u8,
	target: language.Jan_Node_Record,
	promote: bool,
) -> bool {
	cursor := target.range.start
	for node in nodes {
		if node.kind != .Heading || node.range.start < target.range.start ||
		   node.range.start >= target.range.end {
			continue
		}
		prefix := string(source[int(cursor):int(node.range.start)])
		if strings.write_string(builder, prefix) != len(prefix) do return false
		if !promote && strings.write_byte(builder, '*') != 1 do return false
		cursor = node.range.start
		if promote do cursor += 1
	}
	suffix := string(source[int(cursor):int(target.range.end)])
	return strings.write_string(builder, suffix) == len(suffix)
}

@(private)
heading_build_sorted_children :: proc(
	builder: ^strings.Builder,
	nodes: []language.Jan_Node_Record,
	source: []u8,
	parent: language.Jan_Node_Record,
	limits: Limits,
	allocator: runtime.Allocator,
) -> bool {
	children, children_error := make(
		[dynamic]language.Jan_Node_Record,
		0,
		min(len(nodes), int(limits.semantic_targets) + 1),
		allocator,
	)
	if children_error != nil do return false
	defer delete(children)
	for node in nodes {
		if node.kind != .Heading || node.parent_id != parent.id do continue
		if len(children) >= int(limits.semantic_targets) do return false
		if _, append_error := append(&children, node); append_error != nil do return false
	}
	if len(children) < 2 do return false
	for index in 1 ..< len(children) {
		child := children[index]
		cursor := index
		for cursor > 0 && heading_source_key_less(source, child, children[cursor - 1]) {
			children[cursor] = children[cursor - 1]
			cursor -= 1
		}
		children[cursor] = child
	}
	first_start := parent.range.end
	for child in children do first_start = min(first_start, child.range.start)
	prefix := string(source[int(parent.range.start):int(first_start)])
	if strings.write_string(builder, prefix) != len(prefix) do return false
	for child in children {
		text := string(source[int(child.range.start):int(child.range.end)])
		if strings.write_string(builder, text) != len(text) do return false
	}
	return true
}

@(private)
heading_source_key_less :: proc(
	source: []u8,
	left, right: language.Jan_Node_Record,
) -> bool {
	left_start := int(left.range.start) + int(left.structural_depth)
	right_start := int(right.range.start) + int(right.structural_depth)
	left_end := int(outline_heading_line_end(source, left))
	right_end := int(outline_heading_line_end(source, right))
	for left_start < left_end && (source[left_start] == ' ' || source[left_start] == '\t') do left_start += 1
	for right_start < right_end && (source[right_start] == ' ' || source[right_start] == '\t') do right_start += 1
	left_text := source[left_start:left_end]
	right_text := source[right_start:right_end]
	limit := min(len(left_text), len(right_text))
	for index in 0 ..< limit {
		if left_text[index] != right_text[index] do return left_text[index] < right_text[index]
	}
	return len(left_text) < len(right_text)
}

@(private)
heading_is_leaf :: proc(
	nodes: []language.Jan_Node_Record,
	heading: language.Jan_Node_Record,
) -> bool {
	for node in nodes do if node.kind == .Heading && node.parent_id == heading.id do return false
	return true
}

@(private)
heading_build_heading_to_list :: proc(
	builder: ^strings.Builder,
	source: []u8,
	heading: language.Jan_Node_Record,
) -> bool {
	start := int(heading.range.start) + int(heading.structural_depth)
	for start < int(heading.range.end) && (source[start] == ' ' || source[start] == '\t') do start += 1
	text := string(source[start:int(heading.range.end)])
	return strings.write_string(builder, "- ") == 2 &&
	       strings.write_string(builder, text) == len(text)
}

@(private)
heading_build_list_to_heading :: proc(
	builder: ^strings.Builder,
	source: []u8,
	item: language.Jan_Node_Record,
	level: u16,
) -> bool {
	start := int(item.range.start)
	line_end := int(outline_heading_line_end(source, item))
	if start >= line_end do return false
	if source[start] == '-' || source[start] == '+' || source[start] == '*' {
		start += 1
	} else {
		for start < line_end && source[start] >= '0' && source[start] <= '9' do start += 1
		if start >= line_end || (source[start] != '.' && source[start] != ')') do return false
		start += 1
	}
	for start < line_end && (source[start] == ' ' || source[start] == '\t') do start += 1
	text := string(source[start:int(item.range.end)])
	return heading_write_marker(builder, level) &&
	       strings.write_byte(builder, ' ') == 1 &&
	       strings.write_string(builder, text) == len(text)
}

@(private)
heading_write_line :: proc(builder: ^strings.Builder, level: u16, title: string) -> bool {
	return heading_write_marker(builder, level) &&
	       strings.write_byte(builder, ' ') == 1 &&
	       strings.write_string(builder, title) == len(title) &&
	       strings.write_byte(builder, '\n') == 1
}

@(private)
heading_write_marker :: proc(builder: ^strings.Builder, level: u16) -> bool {
	if level == 0 || level > language.MAX_JAN_STRUCTURAL_DEPTH do return false
	for _ in 0 ..< int(level) do if strings.write_byte(builder, '*') != 1 do return false
	return true
}

@(private)
heading_text_has_line_break :: proc(text: string) -> bool {
	for byte in transmute([]u8)text do if byte == '\r' || byte == '\n' do return true
	return false
}

@(private)
heading_utf8_boundary :: proc(source: []u8, offset: editor.Byte_Offset) -> bool {
	if offset == 0 || int(offset) == len(source) do return true
	if int(offset) < 0 || int(offset) > len(source) do return false
	return source[int(offset)] & 0xc0 != 0x80
}

@(private)
heading_edit_failure_from_language :: proc(jan: language.Jan_Failure, scope: Scope) -> Failure {
	code := Failure_Code.Invalid_Target
	#partial switch jan.code {
	case .Stale, .Incomplete: code = .Stale
	case .Limited: code = .Limited
	case .Allocation_Failed: code = .Allocation_Failed
	case .Malformed: code = .Malformed
	case .Cancelled: code = .Cancelled
	}
	return {
		operation = .Plan_Heading_Edit,
		code = code,
		scope = scope,
		limit = jan.limit,
		actual = jan.actual,
	}
}
