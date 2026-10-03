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
Rich_Presentation_State :: struct {
	descriptor: Rich_Presentation_Descriptor,
	items:      []Rich_Presentation_Item,
	text:       []u8,
	fallback:   []u8,
	allocator:  runtime.Allocator,
}

/* rich_presentation_prepare derives immutable rich roles without changing source. */
rich_presentation_prepare :: proc(
	presentation: ^Rich_Presentation,
	analysis: ^language.Jan_Structural_Analysis,
	source: []u8,
	request: Rich_Presentation_Request,
	limits := DEFAULT_LIMITS,
	allocator := context.allocator,
	temporary_allocator := context.temp_allocator,
) -> (descriptor: Rich_Presentation_Descriptor, ok: bool, failure: Failure) {
	if presentation == nil || presentation.state != nil || analysis == nil ||
	   request.operation_id == Operation_ID(0) ||
	   request.generation == Rich_Presentation_Generation(0) ||
	   !scope_is_valid(request.scope) || !limits_are_valid(limits) ||
	   request.surface <= .Invalid || request.surface > .Terminal_Source ||
	   request.visible_start > request.visible_end ||
	   u64(request.visible_end) > u64(len(source)) ||
	   request.visual_indent_width > 16 || !utf8.valid_string(string(source)) ||
	   allocator.procedure == nil || temporary_allocator.procedure == nil {
		return {}, false, editing_failure(.Prepare_Rich_Presentation, .Invalid_Scope, request.scope)
	}
	if request.cancel_requested != nil && request.cancel_requested^ {
		return {}, false, editing_failure(.Prepare_Rich_Presentation, .Cancelled, request.scope)
	}
	nodes := language.jan_structural_analysis_nodes(analysis)
	usage, inspected := language.jan_structural_analysis_usage(analysis)
	if !inspected || usage.source_bytes != u64(len(source)) || len(nodes) == 0 ||
	   nodes[0].range.scope != request.scope.analysis {
		return {}, false, editing_failure(.Prepare_Rich_Presentation, .Stale, request.scope)
	}
	items, item_error := make(
		[dynamic]Rich_Presentation_Item,
		0,
		min(len(nodes), int(limits.semantic_targets) + 1),
		temporary_allocator,
	)
	if item_error != nil {
		return {}, false, editing_failure(.Prepare_Rich_Presentation, .Allocation_Failed, request.scope)
	}
	defer delete(items)
	builder, builder_error := strings.builder_make(temporary_allocator)
	if builder_error != nil {
		return {}, false, editing_failure(.Prepare_Rich_Presentation, .Allocation_Failed, request.scope)
	}
	defer strings.builder_destroy(&builder)

	query, queried, query_failure := language.jan_structural_analysis_query_spans(
		analysis,
		u64(request.visible_start),
		u64(request.visible_end),
		0,
		language.Syntax_Snapshot_Generation(request.generation),
		temporary_allocator,
	)
	if !queried {
		code := Failure_Code.Stale
		if query_failure.code == .Allocation do code = .Allocation_Failed
		if query_failure.code == .Capture_Limit || query_failure.code == .Work_Limit do code = .Limited
		return {}, false, editing_failure(.Prepare_Rich_Presentation, code, request.scope)
	}
	defer language.syntax_query_result_close(&query)
	for span in query.spans {
		start := max(span.start, request.visible_start)
		end := min(span.end, request.visible_end)
		if start >= end do continue
		if !rich_item_append(
			&items,
			{
				kind = .Source_Role,
				range = {scope = request.scope.analysis, start = start, end = end},
				role = span.role,
			},
			limits,
		) {
			return {}, false, rich_limited_failure(request, limits, len(items) + 1)
		}
	}

	if request.surface == .Rich {
		counters: [1_025]u32
		checked: u32
		for node in nodes {
			checked += 1
			if checked % limits.cancellation_entries == 0 && request.cancel_requested != nil &&
			   request.cancel_requested^ {
				return {}, false, editing_failure(.Prepare_Rich_Presentation, .Cancelled, request.scope)
			}
			if node.kind == .Heading do rich_heading_counters_advance(&counters, node.structural_depth)
			if node.range.end <= request.visible_start || node.range.start >= request.visible_end do continue
			switch node.kind {
			case .Bold_Markup, .Italic_Markup, .Underline_Markup,
			     .Verbatim_Markup, .Code_Markup, .Strike_Through_Markup:
				if request.compose_markup && u64(node.range.end - node.range.start) >= 2 {
					inner := source[int(node.range.start) + 1:int(node.range.end) - 1]
					if !rich_text_item_append(&items, &builder, node, .Composed_Markup, .String, string(inner), limits) {
						return {}, false, rich_limited_or_allocation_failure(request, limits, len(items) + 1, builder)
					}
				}
			case .Entity:
				if request.prettify_entities {
					entity, mapped := rich_entity_display(source[int(node.range.start):int(node.range.end)])
					if mapped && !rich_text_item_append(&items, &builder, node, .Prettified_Entity, .Constant, entity, limits) {
						return {}, false, rich_limited_or_allocation_failure(request, limits, len(items) + 1, builder)
					}
				}
			case .Heading:
				if request.visual_indent_width > 0 && node.structural_depth > 1 {
					start := strings.builder_len(builder)
					spaces := min(
						int(node.structural_depth - 1) * int(request.visual_indent_width),
						4_096,
					)
					for _ in 0 ..< spaces {
						if strings.write_byte(&builder, ' ') != 1 {
							return {}, false, editing_failure(.Prepare_Rich_Presentation, .Allocation_Failed, request.scope)
						}
					}
					if !rich_item_append(&items, rich_text_item(node, .Visual_Indent, .Punctuation, start, spaces), limits) {
						return {}, false, rich_limited_failure(request, limits, len(items) + 1)
					}
				}
				if request.number_headings {
					start := strings.builder_len(builder)
					if !rich_heading_number_write(&builder, counters[:], node.structural_depth) {
						return {}, false, editing_failure(.Prepare_Rich_Presentation, .Allocation_Failed, request.scope)
					}
					bytes := strings.builder_len(builder) - start
					if !rich_item_append(&items, rich_text_item(node, .Heading_Number, .Number, start, bytes), limits) {
						return {}, false, rich_limited_failure(request, limits, len(items) + 1)
					}
				}
			case .Invalid, .Document_Root, .Zeroth_Section, .Section,
			     .Center_Block, .Quote_Block, .Special_Block, .Drawer,
			     .Property_Drawer, .Dynamic_Block, .Footnote_Definition,
			     .Inline_Task, .List_Item, .Plain_List, .Pipe_Table,
			     .Table_Provider_Form, .Source_Block, .Example_Block,
			     .Export_Block, .Comment_Block, .Lesser_Block, .Clock,
			     .Diary_Expression, .Planning_Line, .Line_Comment,
			     .Fixed_Width_Area, .Horizontal_Rule, .Keyword,
			     .Affiliated_Keyword, .Latex_Environment, .Node_Property,
			     .Paragraph, .Table_Row, .Table_Separator_Row,
			     .Special_Symbol, .Latex_Fragment, .Export_Snippet,
			     .Named_Footnote_Reference, .Inline_Footnote_Reference,
			     .Anonymous_Footnote_Reference, .Citation,
			     .Citation_Reference, .Inline_Call, .Inline_Source,
			     .Explicit_Line_Break, .Radio_Link, .Plain_Link, .Angle_Link,
			     .Regular_Link, .Macro, .Target, .Radio_Target,
			     .Percentage_Cookie, .Fraction_Cookie, .Subscript,
			     .Superscript, .Table_Cell, .Active_Timestamp,
			     .Inactive_Timestamp, .Diary_Timestamp, .Point_Timestamp,
			     .Timestamp_Range, .Repeating_Timestamp, .Delayed_Timestamp,
			     .Plain_Text, .Preserved_Whitespace, .Recovery:
			}
		}
	}

	state, state_error := new(Rich_Presentation_State, allocator)
	if state_error != nil {
		return {}, false, editing_failure(.Prepare_Rich_Presentation, .Allocation_Failed, request.scope)
	}
	state^ = Rich_Presentation_State{allocator = allocator}
	if len(items) > 0 {
		state.items, state_error = make([]Rich_Presentation_Item, len(items), allocator)
		if state_error == nil do copy(state.items, items[:])
	}
	display_text := strings.to_string(builder)
	if state_error == nil && len(display_text) > 0 {
		state.text, state_error = make([]u8, len(display_text), allocator)
		if state_error == nil do copy(state.text, transmute([]u8)display_text)
	}
	fallback := source[int(request.visible_start):int(request.visible_end)]
	if state_error == nil && len(fallback) > 0 {
		state.fallback, state_error = make([]u8, len(fallback), allocator)
		if state_error == nil do copy(state.fallback, fallback)
	}
	if state_error != nil {
		rich_presentation_state_close(state)
		return {}, false, editing_failure(.Prepare_Rich_Presentation, .Allocation_Failed, request.scope)
	}
	state.descriptor = {
		operation_id = request.operation_id,
		generation = request.generation,
		scope = request.scope,
		visible_start = request.visible_start,
		visible_end = request.visible_end,
		surface = request.surface,
		item_count = u32(len(state.items)),
		source_fallback = request.surface == .Terminal_Source,
		retained_bytes = u64(size_of(Rich_Presentation_State)) +
		                 u64(len(state.items)) * u64(size_of(Rich_Presentation_Item)) +
		                 u64(len(state.text)) + u64(len(state.fallback)),
	}
	presentation.state = state
	return state.descriptor, true, {}
}

/* rich_presentation_descriptor copies immutable projection identity and accounting. */
rich_presentation_descriptor :: proc(presentation: ^Rich_Presentation) -> (Rich_Presentation_Descriptor, bool) {
	state := rich_presentation_state(presentation)
	if state == nil do return {}, false
	return state.descriptor, true
}

/* rich_presentation_items borrows copied items until close. */
rich_presentation_items :: proc(presentation: ^Rich_Presentation) -> []Rich_Presentation_Item {
	state := rich_presentation_state(presentation)
	if state == nil do return nil
	return state.items
}

/* rich_presentation_item_text borrows one copied display replacement until close. */
rich_presentation_item_text :: proc(
	presentation: ^Rich_Presentation,
	item: Rich_Presentation_Item,
) -> (string, bool) {
	state := rich_presentation_state(presentation)
	end := u64(item.display_offset) + u64(item.display_bytes)
	if state == nil || end > u64(len(state.text)) do return "", false
	return string(state.text[item.display_offset:u32(end)]), true
}

/* rich_presentation_source_fallback borrows exact visible source until close. */
rich_presentation_source_fallback :: proc(presentation: ^Rich_Presentation) -> (string, bool) {
	state := rich_presentation_state(presentation)
	if state == nil do return "", false
	return string(state.fallback), true
}

/* rich_presentation_close releases copied projection state exactly once. */
rich_presentation_close :: proc(presentation: ^Rich_Presentation) {
	state := rich_presentation_state(presentation)
	if state == nil do return
	rich_presentation_state_close(state)
	presentation.state = nil
}

@(private)
rich_item_append :: proc(
	items: ^[dynamic]Rich_Presentation_Item,
	item: Rich_Presentation_Item,
	limits: Limits,
) -> bool {
	if len(items^) >= int(limits.semantic_targets) do return false
	_, append_error := append(items, item)
	return append_error == nil
}

@(private)
rich_text_item_append :: proc(
	items: ^[dynamic]Rich_Presentation_Item,
	builder: ^strings.Builder,
	node: language.Jan_Node_Record,
	kind: Rich_Item_Kind,
	role: language.Syntax_Role,
	text: string,
	limits: Limits,
) -> bool {
	start := strings.builder_len(builder^)
	if strings.write_string(builder, text) != len(text) do return false
	return rich_item_append(items, rich_text_item(node, kind, role, start, len(text)), limits)
}

@(private)
rich_text_item :: proc(
	node: language.Jan_Node_Record,
	kind: Rich_Item_Kind,
	role: language.Syntax_Role,
	start, bytes: int,
) -> Rich_Presentation_Item {
	return {
		kind = kind,
		node_kind = node.kind,
		range = node.range,
		role = role,
		display_offset = u32(start),
		display_bytes = u32(bytes),
	}
}

@(private)
rich_entity_display :: proc(source: []u8) -> (string, bool) {
	name := source
	if len(name) > 0 && name[0] == '\\' do name = name[1:]
	if len(name) >= 2 && name[len(name) - 2] == '{' && name[len(name) - 1] == '}' {
		name = name[:len(name) - 2]
	}
	switch string(name) {
	case "alpha": return "α", true
	case "beta": return "β", true
	case "gamma": return "γ", true
	case "lambda": return "λ", true
	case "pi": return "π", true
	case "nbsp": return " ", true
	}
	return "", false
}

@(private)
rich_heading_counters_advance :: proc(counters: ^[1_025]u32, depth: u16) {
	level := min(int(depth), len(counters^) - 1)
	if level <= 0 do return
	counters[level] += 1
	for index in level + 1 ..< len(counters^) do counters[index] = 0
}

@(private)
rich_heading_number_write :: proc(
	builder: ^strings.Builder,
	counters: []u32,
	depth: u16,
) -> bool {
	level := min(int(depth), len(counters) - 1)
	for index in 1 ..= level {
		if index > 1 && strings.write_byte(builder, '.') != 1 do return false
		value := counters[index]
		if value == 0 do value = 1
		if !list_write_u32(builder, value) do return false
	}
	return strings.write_byte(builder, ' ') == 1
}

@(private)
rich_limited_failure :: proc(
	request: Rich_Presentation_Request,
	limits: Limits,
	actual: int,
) -> Failure {
	failure := editing_failure(.Prepare_Rich_Presentation, .Limited, request.scope)
	failure.limit = u64(limits.semantic_targets)
	failure.actual = u64(actual)
	return failure
}

@(private)
rich_limited_or_allocation_failure :: proc(
	request: Rich_Presentation_Request,
	limits: Limits,
	actual: int,
	builder: strings.Builder,
) -> Failure {
	if actual > int(limits.semantic_targets) do return rich_limited_failure(request, limits, actual)
	_ = builder
	return editing_failure(.Prepare_Rich_Presentation, .Allocation_Failed, request.scope)
}

@(private)
rich_presentation_state :: proc(presentation: ^Rich_Presentation) -> ^Rich_Presentation_State {
	if presentation == nil || presentation.state == nil do return nil
	return cast(^Rich_Presentation_State)presentation.state
}

@(private)
rich_presentation_state_close :: proc(state: ^Rich_Presentation_State) {
	if state == nil do return
	allocator := state.allocator
	if state.fallback != nil do delete(state.fallback, allocator)
	if state.text != nil do delete(state.text, allocator)
	if state.items != nil do delete(state.items, allocator)
	state^ = {}
	free(state, allocator)
}
