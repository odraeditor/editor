// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_editing

import "../language"
import "core:strings"
import "core:unicode/utf8"

/* hard_indentation_plan_prepare normalizes selected source columns in one transaction. */
hard_indentation_plan_prepare :: proc(
	plan: ^language.Jan_Rewrite_Plan,
	analysis: ^language.Jan_Structural_Analysis,
	source: []u8,
	scope: Scope,
	selection: language.Jan_Source_Range,
	rewrite_generation: language.Jan_Rewrite_Generation,
	width: u8,
	allocator := context.allocator,
) -> (bool, Failure) {
	if plan == nil || analysis == nil || !scope_is_valid(scope) ||
	   selection.scope != scope.analysis ||
	   !language.jan_source_range_is_valid(selection, u64(len(source))) ||
	   rewrite_generation == language.Jan_Rewrite_Generation(0) || width == 0 || width > 16 ||
	   !utf8.valid_string(string(source)) || allocator.procedure == nil {
		return false, editing_failure(.Plan_Rewrite, .Invalid_Scope, scope)
	}
	nodes := language.jan_structural_analysis_nodes(analysis)
	usage, inspected := language.jan_structural_analysis_usage(analysis)
	if !inspected || usage.source_bytes != u64(len(source)) || len(nodes) == 0 ||
	   nodes[0].range.scope != scope.analysis {
		return false, editing_failure(.Plan_Rewrite, .Stale, scope)
	}
	builder, builder_error := strings.builder_make(allocator)
	if builder_error != nil do return false, editing_failure(.Plan_Rewrite, .Allocation_Failed, scope)
	defer strings.builder_destroy(&builder)
	changed := false
	line_start := 0
	for line_start < len(source) {
		line_end := line_start
		for line_end < len(source) && source[line_end] != '\n' do line_end += 1
		content_start := line_start
		for content_start < line_end && (source[content_start] == ' ' || source[content_start] == '\t') {
			content_start += 1
		}
		desired := content_start - line_start
		selected := editor_range_overlaps_line(selection, line_start, line_end)
		if selected && content_start < line_end {
			if hard_indentation_heading_line(source[content_start:line_end]) {
				desired = 0
			} else if owner, found := hard_indentation_line_owner(nodes, line_start); found &&
			          (owner.kind == .List_Item || navigation_kind_is_block(owner.kind)) {
				depth := max(int(owner.structural_depth), 1)
				desired = (depth - 1) * int(width)
			}
		}
		if desired != content_start - line_start do changed = true
		for _ in 0 ..< desired {
			if strings.write_byte(&builder, ' ') != 1 {
				return false, editing_failure(.Plan_Rewrite, .Allocation_Failed, scope)
			}
		}
		if strings.write_string(&builder, string(source[content_start:line_end])) != line_end - content_start {
			return false, editing_failure(.Plan_Rewrite, .Allocation_Failed, scope)
		}
		if line_end < len(source) {
			if strings.write_byte(&builder, '\n') != 1 {
				return false, editing_failure(.Plan_Rewrite, .Allocation_Failed, scope)
			}
			line_end += 1
		}
		line_start = line_end
	}
	if !changed do return false, editing_failure(.Plan_Rewrite, .Invalid_Target, scope)
	root := nodes[0]
	requests := []language.Jan_Rewrite_Request{{
		node_id = root.id,
		range = root.range,
		replacement = strings.to_string(builder),
	}}
	planned, jan_failure := language.jan_rewrite_plan_prepare(
		plan,
		analysis,
		source,
		rewrite_generation,
		requests,
		allocator = allocator,
	)
	if !planned do return false, template_failure_from_language(jan_failure, scope)
	return true, {}
}

@(private)
editor_range_overlaps_line :: proc(range: language.Jan_Source_Range, start, end: int) -> bool {
	return u64(range.end) > u64(start) && u64(range.start) <= u64(end)
}

@(private)
hard_indentation_heading_line :: proc(line: []u8) -> bool {
	if len(line) < 2 || line[0] != '*' do return false
	index := 0
	for index < len(line) && line[index] == '*' do index += 1
	return index < len(line) && line[index] == ' '
}

@(private)
hard_indentation_line_owner :: proc(
	nodes: []language.Jan_Node_Record,
	line_start: int,
) -> (language.Jan_Node_Record, bool) {
	selected: language.Jan_Node_Record
	found := false
	for node in nodes {
		if u64(node.range.start) > u64(line_start) || u64(node.range.end) <= u64(line_start) do continue
		if !found || node.range.end - node.range.start < selected.range.end - selected.range.start {
			selected = node
			found = true
		}
	}
	return selected, found
}
