// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_editing

import "../editor"
import "../language"
import "core:strings"
import "core:unicode/utf8"

@(private)
Footnote_Label_Edit :: struct {
	node_id: language.Jan_Node_ID,
	start:   editor.Byte_Offset,
	end:     editor.Byte_Offset,
}

/* footnote_visit_local resolves a named destination or the current inline footnote. */
footnote_visit_local :: proc(
	analysis: ^language.Jan_Structural_Analysis,
	source: []u8,
	scope: Scope,
	target_id: language.Jan_Node_ID,
) -> (resolution: Footnote_Resolution, ok: bool, failure: Failure) {
	if analysis == nil || !scope_is_valid(scope) {
		return {}, false, editing_failure(.Resolve_Footnote, .Invalid_Scope, scope)
	}
	nodes := language.jan_structural_analysis_nodes(analysis)
	usage, inspected := language.jan_structural_analysis_usage(analysis)
	if !inspected || usage.source_bytes != u64(len(source)) || len(nodes) == 0 ||
	   nodes[0].range.scope != scope.analysis {
		return {}, false, editing_failure(.Resolve_Footnote, .Stale, scope)
	}
	target, found := navigation_node_by_id(nodes, target_id)
	if !found || !footnote_node_kind(target.kind) {
		return {}, false, editing_failure(.Resolve_Footnote, .Invalid_Target, scope)
	}
	if navigation_node_overlaps_recovery(target, language.jan_structural_analysis_recoveries(analysis)) {
		return {}, false, editing_failure(.Resolve_Footnote, .Malformed, scope)
	}
	resolution.source = navigation_target(target)
	label_start, label_end, label_ok := footnote_label_range(source, target)
	if !label_ok || label_start == label_end {
		resolution.destination = resolution.source
		resolution.inline = target.kind == .Inline_Footnote_Reference ||
		                    target.kind == .Anonymous_Footnote_Reference
		resolution.position = footnote_position(target)
		return resolution, true, {}
	}
	resolution.named = true
	label := source[int(label_start):int(label_end)]
	destination: language.Jan_Node_Record
	destination_found := false
	if target.kind == .Footnote_Definition {
		for node in nodes {
			if node.kind != .Named_Footnote_Reference && node.kind != .Inline_Footnote_Reference do continue
			start, end, parsed := footnote_label_range(source, node)
			if parsed && footnote_bytes_equal(source[int(start):int(end)], label) {
				destination, destination_found = node, true
				break
			}
		}
	} else {
		for node in nodes {
			if node.kind != .Footnote_Definition do continue
			start, end, parsed := footnote_label_range(source, node)
			if parsed && footnote_bytes_equal(source[int(start):int(end)], label) {
				destination, destination_found = node, true
				break
			}
		}
	}
	if !destination_found {
		return {}, false, editing_failure(.Resolve_Footnote, .Invalid_Target, scope)
	}
	resolution.destination = navigation_target(destination)
	resolution.inline = destination.kind != .Footnote_Definition
	resolution.position = footnote_position(destination)
	return resolution, true, {}
}

/* footnote_edit_plan_prepare constructs one checked same-document footnote rewrite. */
footnote_edit_plan_prepare :: proc(
	plan: ^language.Jan_Rewrite_Plan,
	analysis: ^language.Jan_Structural_Analysis,
	source: []u8,
	request: Footnote_Edit_Request,
	limits := DEFAULT_LIMITS,
	allocator := context.allocator,
	temporary_allocator := context.temp_allocator,
) -> (ok: bool, failure: Failure) {
	if plan == nil || analysis == nil || request.operation_id == Operation_ID(0) ||
	   request.kind <= .Invalid || request.kind > .Move_Definition_Down ||
	   request.rewrite_generation == language.Jan_Rewrite_Generation(0) ||
	   !scope_is_valid(request.scope) || !limits_are_valid(limits) ||
	   !utf8.valid_string(string(source)) || !utf8.valid_string(request.name) ||
	   !utf8.valid_string(request.text) || allocator.procedure == nil ||
	   temporary_allocator.procedure == nil {
		return false, editing_failure(.Plan_Footnote_Edit, .Invalid_Scope, request.scope)
	}
	nodes := language.jan_structural_analysis_nodes(analysis)
	usage, inspected := language.jan_structural_analysis_usage(analysis)
	if !inspected || usage.source_bytes != u64(len(source)) || len(nodes) == 0 ||
	   nodes[0].range.scope != request.scope.analysis {
		return false, editing_failure(.Plan_Footnote_Edit, .Stale, request.scope)
	}
	if len(language.jan_structural_analysis_recoveries(analysis)) > 0 {
		return false, editing_failure(.Plan_Footnote_Edit, .Malformed, request.scope)
	}
	builder, builder_error := strings.builder_make(temporary_allocator)
	if builder_error != nil {
		return false, editing_failure(.Plan_Footnote_Edit, .Allocation_Failed, request.scope)
	}
	defer strings.builder_destroy(&builder)

	switch request.kind {
	case .Create_Definition:
		if !footnote_name_is_valid(request.name) || len(request.text) == 0 ||
		   footnote_definition_exists(nodes, source, transmute([]u8)request.name) {
			return false, editing_failure(.Plan_Footnote_Edit, .Invalid_Target, request.scope)
		}
		if !footnote_write_source_with_definition(&builder, source, request.name, request.text) {
			return false, editing_failure(.Plan_Footnote_Edit, .Allocation_Failed, request.scope)
		}
	case .Normalize_Inline:
		target, found := navigation_node_by_id(nodes, request.target_id)
		if !found || (target.kind != .Inline_Footnote_Reference &&
		              target.kind != .Anonymous_Footnote_Reference) {
			return false, editing_failure(.Plan_Footnote_Edit, .Invalid_Target, request.scope)
		}
		label_start, label_end, parsed := footnote_label_range(source, target)
		if !parsed {
			return false, editing_failure(.Plan_Footnote_Edit, .Malformed, request.scope)
		}
		name := request.name
		if len(name) == 0 do name = string(source[int(label_start):int(label_end)])
		body_start, body_end, body_ok := footnote_inline_body_range(source, target)
		if !body_ok || !footnote_name_is_valid(name) ||
		   footnote_definition_exists(nodes, source, transmute([]u8)name) {
			return false, editing_failure(.Plan_Footnote_Edit, .Invalid_Target, request.scope)
		}
		if !footnote_write_normalized_inline(
			&builder,
			source,
			target,
			name,
			string(source[int(body_start):int(body_end)]),
		) {
			return false, editing_failure(.Plan_Footnote_Edit, .Allocation_Failed, request.scope)
		}
	case .Renumber_Local:
		edits, edits_error := make(
			[dynamic]Footnote_Label_Edit,
			0,
			min(len(nodes), int(limits.semantic_targets) + 1),
			temporary_allocator,
		)
		if edits_error != nil {
			return false, editing_failure(.Plan_Footnote_Edit, .Allocation_Failed, request.scope)
		}
		defer delete(edits)
		if !footnote_label_edits_collect(&edits, nodes, source, limits) {
			failure = editing_failure(.Plan_Footnote_Edit, .Limited, request.scope)
			failure.limit = u64(limits.semantic_targets)
			failure.actual = u64(len(edits)) + 1
			return false, failure
		}
		if len(edits) == 0 || !footnote_write_renumbered(&builder, source, edits[:]) {
			return false, editing_failure(.Plan_Footnote_Edit, .Invalid_Target, request.scope)
		}
	case .Move_Definition_Up, .Move_Definition_Down:
		target, found := navigation_node_by_id(nodes, request.target_id)
		if !found || target.kind != .Footnote_Definition {
			return false, editing_failure(.Plan_Footnote_Edit, .Invalid_Target, request.scope)
		}
		other, other_found := footnote_adjacent_definition(
			nodes,
			target,
			request.kind == .Move_Definition_Down,
		)
		if !other_found {
			return false, editing_failure(.Plan_Footnote_Edit, .Invalid_Target, request.scope)
		}
		requests := [2]language.Jan_Rewrite_Request{
			{node_id = target.id, range = target.range, replacement = string(source[int(other.range.start):int(other.range.end)])},
			{node_id = other.id, range = other.range, replacement = string(source[int(target.range.start):int(target.range.end)])},
		}
		jan_limits := language.DEFAULT_JAN_RESOURCE_LIMITS
		jan_limits.rewrite_splices = min(jan_limits.rewrite_splices, limits.rewrite_splices)
		planned, jan_failure := language.jan_rewrite_plan_prepare(
			plan,
			analysis,
			source,
			request.rewrite_generation,
			requests[:],
			jan_limits,
			allocator,
		)
		if !planned do return false, footnote_failure_from_language(jan_failure, request.scope)
		return true, {}
	case .Invalid:
	}

	planned, jan_failure := jan_editing_prepare_range_rewrite(
		plan,
		analysis,
		source,
		request.scope,
		0,
		editor.Byte_Offset(len(source)),
		strings.to_string(builder),
		request.rewrite_generation,
		limits,
		allocator,
		temporary_allocator,
	)
	if !planned do return false, footnote_failure_from_language(jan_failure, request.scope)
	return true, {}
}

/* footnote_cross_resource_availability reports the linked external-resource owner. */
footnote_cross_resource_availability :: proc() -> language.Jan_Availability_Record {
	for record in language.jan_future_stage_availability() {
		capability := record.capability
		if string(capability.bytes[:capability.length]) == "jan-external-resources" do return record
	}
	assert(false, "Jan external-resource availability is missing")
	return {}
}

@(private)
footnote_node_kind :: proc(kind: language.Jan_Node_Kind) -> bool {
	return kind == .Footnote_Definition || kind == .Named_Footnote_Reference ||
	       kind == .Inline_Footnote_Reference || kind == .Anonymous_Footnote_Reference
}

@(private)
footnote_position :: proc(node: language.Jan_Node_Record) -> editor.Position {
	return {
		buffer_id = node.range.scope.buffer_id,
		revision = node.range.scope.source_revision,
		byte_offset = node.range.start,
	}
}

@(private)
footnote_label_range :: proc(
	source: []u8,
	node: language.Jan_Node_Record,
) -> (editor.Byte_Offset, editor.Byte_Offset, bool) {
	start, end := int(node.range.start), int(node.range.end)
	if start < 0 || end > len(source) || end - start < 5 ||
	   source[start] != '[' || source[start + 1] != 'f' || source[start + 2] != 'n' ||
	   source[start + 3] != ':' {
		return 0, 0, false
	}
	label_start := start + 4
	label_end := label_start
	for label_end < end && source[label_end] != ':' && source[label_end] != ']' do label_end += 1
	if label_end >= end do return 0, 0, false
	return editor.Byte_Offset(label_start), editor.Byte_Offset(label_end), true
}

@(private)
footnote_inline_body_range :: proc(
	source: []u8,
	node: language.Jan_Node_Record,
) -> (editor.Byte_Offset, editor.Byte_Offset, bool) {
	_, label_end, parsed := footnote_label_range(source, node)
	end := int(node.range.end)
	if !parsed || int(label_end) >= end || source[int(label_end)] != ':' ||
	   source[end - 1] != ']' || int(label_end) + 1 > end - 1 {
		return 0, 0, false
	}
	return label_end + 1, editor.Byte_Offset(end - 1), true
}

@(private)
footnote_name_is_valid :: proc(name: string) -> bool {
	if len(name) == 0 || len(name) > 64 do return false
	for byte in transmute([]u8)name {
		if (byte >= 'a' && byte <= 'z') || (byte >= 'A' && byte <= 'Z') ||
		   (byte >= '0' && byte <= '9') || byte == '-' || byte == '_' {
			continue
		}
		return false
	}
	return true
}

@(private)
footnote_definition_exists :: proc(
	nodes: []language.Jan_Node_Record,
	source, name: []u8,
) -> bool {
	for node in nodes {
		if node.kind != .Footnote_Definition do continue
		start, end, parsed := footnote_label_range(source, node)
		if parsed && footnote_bytes_equal(source[int(start):int(end)], name) do return true
	}
	return false
}

@(private)
footnote_write_source_with_definition :: proc(
	builder: ^strings.Builder,
	source: []u8,
	name, text: string,
) -> bool {
	if strings.write_string(builder, string(source)) != len(source) do return false
	if len(source) > 0 && source[len(source) - 1] != '\n' && strings.write_byte(builder, '\n') != 1 do return false
	return strings.write_string(builder, "[fn:") == 4 &&
	       strings.write_string(builder, name) == len(name) &&
	       strings.write_string(builder, "] ") == 2 &&
	       strings.write_string(builder, text) == len(text) &&
	       (len(text) > 0 && text[len(text) - 1] == '\n' || strings.write_byte(builder, '\n') == 1)
}

@(private)
footnote_write_normalized_inline :: proc(
	builder: ^strings.Builder,
	source: []u8,
	target: language.Jan_Node_Record,
	name, body: string,
) -> bool {
	start, end := int(target.range.start), int(target.range.end)
	if strings.write_string(builder, string(source[:start])) != start ||
	   strings.write_string(builder, "[fn:") != 4 ||
	   strings.write_string(builder, name) != len(name) ||
	   strings.write_byte(builder, ']') != 1 ||
	   strings.write_string(builder, string(source[end:])) != len(source) - end {
		return false
	}
	if len(source) > 0 && source[len(source) - 1] != '\n' && strings.write_byte(builder, '\n') != 1 do return false
	return strings.write_string(builder, "[fn:") == 4 &&
	       strings.write_string(builder, name) == len(name) &&
	       strings.write_string(builder, "] ") == 2 &&
	       strings.write_string(builder, body) == len(body) &&
	       strings.write_byte(builder, '\n') == 1
}

@(private)
footnote_label_edits_collect :: proc(
	edits: ^[dynamic]Footnote_Label_Edit,
	nodes: []language.Jan_Node_Record,
	source: []u8,
	limits: Limits,
) -> bool {
	for node in nodes {
		if !footnote_node_kind(node.kind) do continue
		start, end, parsed := footnote_label_range(source, node)
		if !parsed || start == end do continue
		if len(edits^) >= int(limits.semantic_targets) do return false
		edit := Footnote_Label_Edit{node_id = node.id, start = start, end = end}
		if _, append_error := append(edits, edit); append_error != nil {
			return false
		}
	}
	for index in 1 ..< len(edits^) {
		value := edits^[index]
		cursor := index
		for cursor > 0 && value.start < edits^[cursor - 1].start {
			edits^[cursor] = edits^[cursor - 1]
			cursor -= 1
		}
		edits^[cursor] = value
	}
	for index in 1 ..< len(edits^) do if edits^[index].start < edits^[index - 1].end do return false
	return true
}

@(private)
footnote_write_renumbered :: proc(
	builder: ^strings.Builder,
	source: []u8,
	edits: []Footnote_Label_Edit,
) -> bool {
	cursor: int
	for edit, index in edits {
		start, end := int(edit.start), int(edit.end)
		if start < cursor || end > len(source) ||
		   strings.write_string(builder, string(source[cursor:start])) != start - cursor {
			return false
		}
		ordinal: u32 = 1
		for prior_index in 0 ..< index {
			prior := edits[prior_index]
			if footnote_bytes_equal(source[int(prior.start):int(prior.end)], source[start:end]) {
				ordinal = footnote_label_ordinal(source, edits, prior_index)
				break
			}
			if footnote_label_is_first(source, edits, prior_index) do ordinal += 1
		}
		if !list_write_u32(builder, ordinal) do return false
		cursor = end
	}
	return strings.write_string(builder, string(source[cursor:])) == len(source) - cursor
}

@(private)
footnote_label_ordinal :: proc(source: []u8, edits: []Footnote_Label_Edit, target: int) -> u32 {
	ordinal: u32 = 1
	for index in 0 ..< target do if footnote_label_is_first(source, edits, index) do ordinal += 1
	return ordinal
}

@(private)
footnote_label_is_first :: proc(source: []u8, edits: []Footnote_Label_Edit, target: int) -> bool {
	label := source[int(edits[target].start):int(edits[target].end)]
	for index in 0 ..< target {
		prior := source[int(edits[index].start):int(edits[index].end)]
		if footnote_bytes_equal(prior, label) do return false
	}
	return true
}

@(private)
footnote_adjacent_definition :: proc(
	nodes: []language.Jan_Node_Record,
	target: language.Jan_Node_Record,
	forward: bool,
) -> (language.Jan_Node_Record, bool) {
	candidate: language.Jan_Node_Record
	found := false
	for node in nodes {
		if node.kind != .Footnote_Definition || node.id == target.id do continue
		if forward {
			if node.range.start <= target.range.start do continue
			if !found || node.range.start < candidate.range.start do candidate, found = node, true
		} else {
			if node.range.start >= target.range.start do continue
			if !found || node.range.start > candidate.range.start do candidate, found = node, true
		}
	}
	return candidate, found
}

@(private)
footnote_bytes_equal :: proc(left, right: []u8) -> bool {
	if len(left) != len(right) do return false
	for byte, index in left do if byte != right[index] do return false
	return true
}

@(private)
footnote_failure_from_language :: proc(jan: language.Jan_Failure, scope: Scope) -> Failure {
	code := Failure_Code.Invalid_Target
	switch jan.code {
	case .Stale: code = .Stale
	case .Limited: code = .Limited
	case .Cancelled: code = .Cancelled
	case .Allocation_Failed: code = .Allocation_Failed
	case .Malformed, .Incomplete: code = .Malformed
	case .None, .Unsupported, .Provider_Failed, .Invalid_Baseline,
	     .Invalid_Configuration, .Invalid_Range, .Invalid_Node, .Invalid_Index,
	     .Invalid_Rewrite, .Timeout:
	}
	return {
		operation = .Plan_Footnote_Edit,
		code = code,
		scope = scope,
		limit = jan.limit,
		actual = jan.actual,
	}
}
