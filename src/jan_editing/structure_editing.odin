// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_editing

import "../editor"
import "../language"
import "../view"
import "core:strings"
import "core:unicode/utf8"

/* structure_inspect derives complete selection and foldable body ranges. */
structure_inspect :: proc(
	analysis: ^language.Jan_Structural_Analysis,
	source: []u8,
	scope: Scope,
	target_id: language.Jan_Node_ID,
) -> (inspection: Structure_Inspection, ok: bool, failure: Failure) {
	if analysis == nil || !scope_is_valid(scope) || !utf8.valid_string(string(source)) {
		return {}, false, editing_failure(.Plan_Structure_Edit, .Invalid_Scope, scope)
	}
	nodes := language.jan_structural_analysis_nodes(analysis)
	usage, inspected := language.jan_structural_analysis_usage(analysis)
	if !inspected || usage.source_bytes != u64(len(source)) || len(nodes) == 0 ||
	   nodes[0].range.scope != scope.analysis {
		return {}, false, editing_failure(.Plan_Structure_Edit, .Stale, scope)
	}
	target, found := navigation_node_by_id(nodes, target_id)
	if !found || !structure_kind_is_drawer(target.kind) && !navigation_kind_is_block(target.kind) {
		return {}, false, editing_failure(.Plan_Structure_Edit, .Invalid_Target, scope)
	}
	if navigation_node_overlaps_recovery(target, language.jan_structural_analysis_recoveries(analysis)) {
		return {}, false, editing_failure(.Plan_Structure_Edit, .Malformed, scope)
	}
	body_start, body_end, body_ok := structure_body_bounds(source, target)
	if !body_ok {
		return {}, false, editing_failure(.Plan_Structure_Edit, .Malformed, scope)
	}
	start_position := editor.Position {
		buffer_id = scope.analysis.buffer_id,
		revision = scope.analysis.source_revision,
		byte_offset = body_start,
	}
	end_position := start_position
	end_position.byte_offset = body_end
	return {
		target = navigation_target(target),
		selection = target.range,
		body = {scope = scope.analysis, start = body_start, end = body_end},
		fold_range = view.Hidden_Range{start = start_position, end = end_position},
		foldable = body_start < body_end,
	}, true, {}
}

/* structure_future_stage_availability retains its API while reporting linked planning owners. */
structure_future_stage_availability :: proc() -> [2]language.Jan_Availability_Record {
	all := language.jan_capability_availability()
	result: [2]language.Jan_Availability_Record
	count: int
	for record in all {
		capability := record.capability
		name := string(capability.bytes[:capability.length])
		if name != "jan-task-planning" && name != "jan-property-operations" do continue
		result[count] = record
		count += 1
	}
	assert(count == len(result))
	return result
}

/* structure_edit_plan_prepare constructs one checked complete-structure rewrite. */
structure_edit_plan_prepare :: proc(
	plan: ^language.Jan_Rewrite_Plan,
	analysis: ^language.Jan_Structural_Analysis,
	source: []u8,
	request: Structure_Edit_Request,
	limits := DEFAULT_LIMITS,
	allocator := context.allocator,
	temporary_allocator := context.temp_allocator,
) -> (ok: bool, failure: Failure) {
	if plan == nil || analysis == nil || !scope_is_valid(request.scope) ||
	   request.operation_id == Operation_ID(0) || request.kind <= .Invalid ||
	   request.kind > .Rename ||
	   request.rewrite_generation == language.Jan_Rewrite_Generation(0) ||
	   !limits_are_valid(limits) || allocator.procedure == nil ||
	   temporary_allocator.procedure == nil || !utf8.valid_string(string(source)) ||
	   !utf8.valid_string(request.name) || !utf8.valid_string(request.arguments) ||
	   !utf8.valid_string(request.body) || structure_text_has_line_break(request.name) ||
	   structure_text_has_line_break(request.arguments) {
		return false, editing_failure(.Plan_Structure_Edit, .Invalid_Scope, request.scope)
	}
	nodes := language.jan_structural_analysis_nodes(analysis)
	usage, inspected := language.jan_structural_analysis_usage(analysis)
	if !inspected || usage.source_bytes != u64(len(source)) || len(nodes) == 0 ||
	   nodes[0].range.scope != request.scope.analysis {
		return false, editing_failure(.Plan_Structure_Edit, .Stale, request.scope)
	}
	target, found := navigation_node_by_id(nodes, request.target_id)
	if !found {
		return false, editing_failure(.Plan_Structure_Edit, .Invalid_Target, request.scope)
	}
	is_structure := structure_kind_is_drawer(target.kind) || navigation_kind_is_block(target.kind)
	if request.kind != .Insert_Before && request.kind != .Insert_After &&
	   request.kind != .Expand_Template && !is_structure {
		return false, editing_failure(.Plan_Structure_Edit, .Invalid_Target, request.scope)
	}
	if navigation_node_overlaps_recovery(target, language.jan_structural_analysis_recoveries(analysis)) {
		return false, editing_failure(.Plan_Structure_Edit, .Malformed, request.scope)
	}
	builder, builder_error := strings.builder_make(temporary_allocator)
	if builder_error != nil {
		return false, editing_failure(.Plan_Structure_Edit, .Allocation_Failed, request.scope)
	}
	defer strings.builder_destroy(&builder)
	edit_start, edit_end := target.range.start, target.range.end

	switch request.kind {
	case .Insert_Before, .Insert_After, .Expand_Template:
		if request.template == .Invalid || !structure_template_is_valid(request.template, request.name) {
			return false, editing_failure(.Plan_Structure_Edit, .Invalid_Target, request.scope)
		}
		original := string(source[int(edit_start):int(edit_end)])
		if request.kind == .Insert_After && strings.write_string(&builder, original) != len(original) {
			return false, editing_failure(.Plan_Structure_Edit, .Allocation_Failed, request.scope)
		}
		if !structure_write_template(
			&builder,
			request.template,
			request.name,
			request.arguments,
			request.body,
		) {
			return false, editing_failure(.Plan_Structure_Edit, .Allocation_Failed, request.scope)
		}
		if request.kind == .Insert_Before && strings.write_string(&builder, original) != len(original) {
			return false, editing_failure(.Plan_Structure_Edit, .Allocation_Failed, request.scope)
		}
	case .Delete:
	case .Move_Up, .Move_Down:
		sibling, sibling_ok := structure_sibling(nodes, target, request.kind == .Move_Down)
		if !sibling_ok {
			return false, editing_failure(.Plan_Structure_Edit, .Invalid_Target, request.scope)
		}
		first, second := target, sibling
		if second.range.start < first.range.start do first, second = second, first
		edit_start, edit_end = first.range.start, second.range.end
		first_text := string(source[int(first.range.start):int(first.range.end)])
		middle := string(source[int(first.range.end):int(second.range.start)])
		second_text := string(source[int(second.range.start):int(second.range.end)])
		if strings.write_string(&builder, second_text) != len(second_text) ||
		   strings.write_string(&builder, middle) != len(middle) ||
		   strings.write_string(&builder, first_text) != len(first_text) {
			return false, editing_failure(.Plan_Structure_Edit, .Allocation_Failed, request.scope)
		}
	case .Rename:
		if !structure_name_is_valid(request.name) || target.kind == .Dynamic_Block {
			return false, editing_failure(.Plan_Structure_Edit, .Invalid_Target, request.scope)
		}
		if !structure_write_renamed(&builder, source, target, request.name) {
			return false, editing_failure(.Plan_Structure_Edit, .Allocation_Failed, request.scope)
		}
	case .Invalid:
	}

	replacement := ""
	if request.kind != .Delete do replacement = strings.to_string(builder)
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
	if !planned do return false, structure_failure_from_language(jan_failure, request.scope)
	return true, {}
}

@(private)
structure_body_bounds :: proc(
	source: []u8,
	target: language.Jan_Node_Record,
) -> (editor.Byte_Offset, editor.Byte_Offset, bool) {
	start, end := int(target.range.start), int(target.range.end)
	if start < 0 || end > len(source) || start >= end do return 0, 0, false
	body_start := start
	for body_start < end && source[body_start] != '\r' && source[body_start] != '\n' do body_start += 1
	if body_start >= end do return 0, 0, false
	if source[body_start] == '\r' do body_start += 1
	if body_start < end && source[body_start] == '\n' do body_start += 1
	closing_end := end
	for closing_end > body_start && (source[closing_end - 1] == '\r' || source[closing_end - 1] == '\n') {
		closing_end -= 1
	}
	closing_start := closing_end
	for closing_start > body_start && source[closing_start - 1] != '\r' && source[closing_start - 1] != '\n' {
		closing_start -= 1
	}
	return editor.Byte_Offset(body_start), editor.Byte_Offset(closing_start), closing_start <= closing_end
}

@(private)
structure_sibling :: proc(
	nodes: []language.Jan_Node_Record,
	target: language.Jan_Node_Record,
	forward: bool,
) -> (candidate: language.Jan_Node_Record, found: bool) {
	for node in nodes {
		if node.parent_id != target.parent_id ||
		   !structure_kind_is_drawer(node.kind) && !navigation_kind_is_block(node.kind) {
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
structure_write_template :: proc(
	builder: ^strings.Builder,
	template: Structure_Template_Kind,
	name, arguments, body: string,
) -> bool {
	if template == .Drawer {
		return strings.write_byte(builder, ':') == 1 &&
		       strings.write_string(builder, name) == len(name) &&
		       strings.write_string(builder, ":\n") == 2 &&
		       structure_write_body(builder, body) &&
		       strings.write_string(builder, ":END:\n") == 6
	}
	delimiter := structure_template_delimiter(template, name)
	if len(delimiter) == 0 do return false
	if template == .Dynamic_Block {
		if strings.write_string(builder, "#+begin: ") != 9 ||
		   strings.write_string(builder, delimiter) != len(delimiter) {
			return false
		}
	} else if strings.write_string(builder, "#+begin_") != 8 ||
	          strings.write_string(builder, delimiter) != len(delimiter) {
		return false
	}
	if len(arguments) > 0 &&
	   (strings.write_byte(builder, ' ') != 1 || strings.write_string(builder, arguments) != len(arguments)) {
		return false
	}
	if strings.write_byte(builder, '\n') != 1 || !structure_write_body(builder, body) do return false
	if template == .Dynamic_Block {
		return strings.write_string(builder, "#+end:\n") == 7
	}
	return strings.write_string(builder, "#+end_") == 6 &&
	       strings.write_string(builder, delimiter) == len(delimiter) &&
	       strings.write_byte(builder, '\n') == 1
}

@(private)
structure_write_body :: proc(builder: ^strings.Builder, body: string) -> bool {
	if strings.write_string(builder, body) != len(body) do return false
	return len(body) == 0 || body[len(body) - 1] == '\n' || strings.write_byte(builder, '\n') == 1
}

@(private)
structure_template_delimiter :: proc(template: Structure_Template_Kind, name: string) -> string {
	switch template {
	case .Source_Block: return "src"
	case .Example_Block: return "example"
	case .Quote_Block: return "quote"
	case .Center_Block: return "center"
	case .Comment_Block: return "comment"
	case .Export_Block: return "export"
	case .Special_Block, .Dynamic_Block: return name
	case .Invalid, .Drawer:
	}
	return ""
}

@(private)
structure_template_is_valid :: proc(template: Structure_Template_Kind, name: string) -> bool {
	if template == .Drawer || template == .Special_Block || template == .Dynamic_Block {
		return structure_name_is_valid(name)
	}
	return template > .Invalid && template < .Special_Block
}

@(private)
structure_name_is_valid :: proc(name: string) -> bool {
	if len(name) == 0 do return false
	for byte in transmute([]u8)name {
		if (byte >= 'A' && byte <= 'Z') || (byte >= 'a' && byte <= 'z') ||
		   (byte >= '0' && byte <= '9') || byte == '_' || byte == '-' {
			continue
		}
		return false
	}
	return true
}

@(private)
structure_write_renamed :: proc(
	builder: ^strings.Builder,
	source: []u8,
	target: language.Jan_Node_Record,
	name: string,
) -> bool {
	start, end := int(target.range.start), int(target.range.end)
	body_start, body_end, bounds_ok := structure_body_bounds(source, target)
	if !bounds_ok do return false
	begin_name_start, begin_name_end, begin_ok := structure_delimiter_name_bounds(
		source,
		start,
		int(body_start),
		structure_kind_is_drawer(target.kind),
		false,
	)
	if structure_kind_is_drawer(target.kind) {
		if !begin_ok do return false
		prefix := string(source[start:begin_name_start])
		suffix := string(source[begin_name_end:end])
		return strings.write_string(builder, prefix) == len(prefix) &&
		       strings.write_string(builder, name) == len(name) &&
		       strings.write_string(builder, suffix) == len(suffix)
	}
	closing_end := end
	for closing_end > int(body_end) && (source[closing_end - 1] == '\r' || source[closing_end - 1] == '\n') {
		closing_end -= 1
	}
	end_name_start, end_name_end, end_ok := structure_delimiter_name_bounds(
		source,
		int(body_end),
		closing_end,
		structure_kind_is_drawer(target.kind),
		true,
	)
	if !begin_ok || !end_ok do return false
	parts := [5]string {
		string(source[start:begin_name_start]),
		name,
		string(source[begin_name_end:end_name_start]),
		name,
		string(source[end_name_end:end]),
	}
	for part in parts do if strings.write_string(builder, part) != len(part) do return false
	return true
}

@(private)
structure_delimiter_name_bounds :: proc(
	source: []u8,
	start, end: int,
	drawer, closing: bool,
) -> (int, int, bool) {
	if start < 0 || end > len(source) || start >= end do return 0, 0, false
	cursor := start
	if drawer {
		if source[cursor] != ':' do return 0, 0, false
		cursor += 1
		name_start := cursor
		for cursor < end && source[cursor] != ':' do cursor += 1
		return name_start, cursor, cursor > name_start && cursor < end
	}
	prefix := "#+begin_"
	if closing do prefix = "#+end_"
	if end - start < len(prefix) do return 0, 0, false
	for byte, index in transmute([]u8)prefix {
		left := source[start + index]
		if left >= 'A' && left <= 'Z' do left += 'a' - 'A'
		if left != byte do return 0, 0, false
	}
	cursor += len(prefix)
	name_start := cursor
	for cursor < end && source[cursor] != ' ' && source[cursor] != '\t' &&
	    source[cursor] != '\r' && source[cursor] != '\n' {
		cursor += 1
	}
	return name_start, cursor, cursor > name_start
}

@(private)
structure_text_has_line_break :: proc(text: string) -> bool {
	for byte in transmute([]u8)text do if byte == '\r' || byte == '\n' do return true
	return false
}

@(private)
structure_kind_is_drawer :: proc(kind: language.Jan_Node_Kind) -> bool {
	return kind == .Drawer || kind == .Property_Drawer
}

@(private)
structure_failure_from_language :: proc(jan: language.Jan_Failure, scope: Scope) -> Failure {
	code := Failure_Code.Invalid_Target
	#partial switch jan.code {
	case .Stale, .Incomplete: code = .Stale
	case .Limited: code = .Limited
	case .Allocation_Failed: code = .Allocation_Failed
	case .Malformed: code = .Malformed
	case .Cancelled: code = .Cancelled
	}
	return {operation = .Plan_Structure_Edit, code = code, scope = scope, limit = jan.limit, actual = jan.actual}
}
