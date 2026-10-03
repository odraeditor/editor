// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language

/* jan_structural_analysis_query_spans publishes Jan roles through shared syntax records. */
jan_structural_analysis_query_spans :: proc(
	analysis: ^Jan_Structural_Analysis,
	visible_start, visible_end: u64,
	halo_bytes: u64,
	generation: Syntax_Snapshot_Generation,
	allocator := context.allocator,
) -> (result: Syntax_Query_Result, ok: bool, failure: Failure) {
	nodes := jan_structural_analysis_nodes(analysis)
	usage, usage_ok := jan_structural_analysis_usage(analysis)
	if len(nodes) == 0 || !usage_ok {
		return {}, false, jan_syntax_failure({}, .Parser_Initialization)
	}
	scope := nodes[0].range.scope
	if !jan_analysis_scope_is_valid(scope) || visible_start > visible_end ||
	   visible_end > usage.source_bytes {
		return {}, false, jan_syntax_failure(scope, .Invalid_Transaction)
	}
	if halo_bytes > MAX_VISIBLE_HALO_BYTES {
		failure = jan_syntax_failure(scope, .Work_Limit)
		failure.limit = MAX_VISIBLE_HALO_BYTES
		failure.actual = halo_bytes
		return {}, false, failure
	}
	if generation == Syntax_Snapshot_Generation(0) || allocator.procedure == nil {
		return {}, false, jan_syntax_failure(scope, .Allocation)
	}
	query_start := visible_start - min(visible_start, halo_bytes)
	query_end := min(usage.source_bytes, visible_end + min(halo_bytes, usage.source_bytes - visible_end))
	captures, capture_error := make([dynamic]Raw_Syntax_Capture, 0, min(len(nodes), int(MAX_VISIBLE_QUERY_SPANS)), allocator)
	if capture_error != nil do return {}, false, jan_syntax_failure(scope, .Allocation)
	defer delete(captures)
	serial: u32
	for node in nodes {
		start := u64(node.range.start)
		end := u64(node.range.end)
		if start >= end || end <= query_start || start >= query_end do continue
		role, precedence, mapped := jan_node_syntax_role(node.kind)
		if !mapped do continue
		if len(captures) >= int(MAX_VISIBLE_QUERY_SPANS) {
			failure = jan_syntax_failure(scope, .Capture_Limit)
			failure.limit = MAX_VISIBLE_QUERY_SPANS
			failure.actual = u64(len(captures)) + 1
			return {}, false, failure
		}
		_, append_error := append(&captures, Raw_Syntax_Capture {
			start = u32(node.range.start),
			end = u32(node.range.end),
			role = role,
			precedence = precedence,
			serial = serial,
		})
		if append_error != nil do return {}, false, jan_syntax_failure(scope, .Allocation)
		serial += 1
	}
	for recovery in jan_structural_analysis_recoveries(analysis) {
		start := u64(recovery.range.start)
		end := u64(recovery.range.end)
		if start >= end || end <= query_start || start >= query_end do continue
		if len(captures) >= int(MAX_VISIBLE_QUERY_SPANS) {
			failure = jan_syntax_failure(scope, .Capture_Limit)
			failure.limit = MAX_VISIBLE_QUERY_SPANS
			failure.actual = u64(len(captures)) + 1
			return {}, false, failure
		}
		_, append_error := append(&captures, Raw_Syntax_Capture {
			start = u32(recovery.range.start),
			end = u32(recovery.range.end),
			role = .Comment,
			precedence = 1_000,
			serial = serial,
		})
		if append_error != nil do return {}, false, jan_syntax_failure(scope, .Allocation)
		serial += 1
	}
	spans, spans_failure := syntax_captures_normalize(
		captures[:],
		scope.provider,
		scope.source_revision,
		allocator,
	)
	if spans_failure.code != .None do return {}, false, spans_failure
	resource_usage := Resource_Usage {
		retained_source_bytes = usage.source_bytes,
		retained_tree_bytes = usage.retained_bytes,
		temporary_bytes = usage.temporary_bytes,
		captures = u32(len(captures)),
		spans = u32(len(spans)),
		work_bytes = usage.work_bytes,
	}
	resource_usage.retained_span_bytes = u64(len(spans)) * u64(size_of(Syntax_Span))
	result = Syntax_Query_Result {
		snapshot = {
			generation = generation,
			buffer_id = scope.buffer_id,
			source_revision = scope.source_revision,
			language = scope.language,
			provider = scope.provider,
			selection_generation = scope.selection_generation,
			parser_generation = scope.parser_generation,
			query_generation = 1,
			span_count = u32(len(spans)),
			usage = resource_usage,
		},
		spans = spans,
		allocator = allocator,
	}
	return result, true, {}
}

@(private)
jan_node_syntax_role :: proc(kind: Jan_Node_Kind) -> (role: Syntax_Role, precedence: u16, ok: bool) {
	switch kind {
	case .Heading, .Target, .Radio_Target:
		return .Label, 100, true
	case .Keyword, .Affiliated_Keyword, .Planning_Line, .Dynamic_Block,
	     .Center_Block, .Quote_Block, .Special_Block:
		return .Keyword, 180, true
	case .Node_Property, .Property_Drawer, .Drawer:
		return .Attribute, 200, true
	case .Line_Comment, .Comment_Block:
		return .Comment, 400, true
	case .Source_Block, .Example_Block, .Export_Block, .Lesser_Block,
	     .Latex_Environment, .Latex_Fragment, .Export_Snippet, .Inline_Call,
	     .Inline_Source, .Verbatim_Markup, .Code_Markup:
		return .String, 220, true
	case .Entity, .Special_Symbol, .Macro, .Active_Timestamp, .Inactive_Timestamp,
	     .Diary_Timestamp, .Point_Timestamp, .Timestamp_Range,
	     .Repeating_Timestamp, .Delayed_Timestamp:
		return .Constant, 260, true
	case .Named_Footnote_Reference, .Inline_Footnote_Reference,
	     .Anonymous_Footnote_Reference, .Citation, .Citation_Reference,
	     .Radio_Link, .Plain_Link, .Angle_Link, .Regular_Link:
		return .String, 280, true
	case .Percentage_Cookie, .Fraction_Cookie:
		return .Number, 260, true
	case .Bold_Markup, .Italic_Markup, .Underline_Markup, .Strike_Through_Markup:
		return .String, 240, true
	case .List_Item, .Plain_List, .Pipe_Table, .Table_Provider_Form,
	     .Table_Row, .Table_Separator_Row, .Table_Cell, .Horizontal_Rule,
	     .Explicit_Line_Break:
		return .Punctuation, 140, true
	case .Recovery:
		return .Comment, 1_000, true
	case .Invalid, .Document_Root, .Zeroth_Section, .Section,
	     .Footnote_Definition, .Inline_Task, .Clock, .Diary_Expression,
	     .Fixed_Width_Area, .Paragraph, .Subscript, .Superscript,
	     .Plain_Text, .Preserved_Whitespace:
		return .Invalid, 0, false
	}
	return .Invalid, 0, false
}

@(private)
jan_syntax_failure :: proc(scope: Jan_Analysis_Scope, code: Failure_Code) -> Failure {
	return {
		operation = .Publish_Syntax,
		code = code,
		language_id = scope.language.id,
		provider = scope.provider,
		selection_generation = scope.selection_generation,
		source_revision = scope.source_revision,
	}
}
