// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_editing

import "../editor"
import "../language"
import "../view"

/* navigation_resolve derives one canonical structural destination from copied analysis. */
navigation_resolve :: proc(
	analysis: ^language.Jan_Structural_Analysis,
	source_bytes: u64,
	request: Navigation_Request,
	limits := DEFAULT_LIMITS,
) -> (result: Navigation_Result, ok: bool, failure: Failure) {
	result.kind = request.kind
	if analysis == nil || !scope_is_valid(request.scope) || !limits_are_valid(limits) ||
	   request.kind <= .Invalid || request.kind > .Previous_Footnote ||
	   request.point.buffer_id != request.scope.analysis.buffer_id ||
	   request.point.revision != request.scope.analysis.source_revision ||
	   u64(request.point.byte_offset) > source_bytes {
		return result, false, editing_failure(.Navigate, .Invalid_Scope, request.scope)
	}
	nodes := language.jan_structural_analysis_nodes(analysis)
	usage, inspected := language.jan_structural_analysis_usage(analysis)
	if !inspected || usage.source_bytes != source_bytes || len(nodes) == 0 ||
	   nodes[0].range.scope != request.scope.analysis {
		return result, false, editing_failure(.Navigate, .Stale, request.scope)
	}
	for hidden in request.hidden_ranges {
		if !navigation_hidden_range_is_valid(hidden, request.scope, source_bytes) {
			return result, false, editing_failure(.Navigate, .Invalid_Target, request.scope)
		}
	}

	current, has_current := navigation_current_heading(nodes, request.point.byte_offset)
	candidate: language.Jan_Node_Record
	found: bool
	candidates: u32

	switch request.kind {
	case .Next_Visible_Heading, .Previous_Visible_Heading:
		forward := request.kind == .Next_Visible_Heading
		candidate, found, candidates = navigation_relative_node(
			nodes,
			request.point.byte_offset,
			forward,
			.Heading,
			request.hidden_ranges,
			true,
		)
	case .Next_Same_Level_Heading, .Previous_Same_Level_Heading:
		if has_current {
			candidate, found, candidates = navigation_sibling(
				nodes,
				current,
				request.kind == .Next_Same_Level_Heading,
				request.hidden_ranges,
			)
		}
	case .Parent_Heading:
		if has_current {
			candidate, found = navigation_node_by_id(nodes, current.parent_id)
			if found && candidate.kind != .Heading do found = false
			if found do candidates = 1
		}
	case .First_Child_Heading:
		if has_current {
			candidate, found, candidates = navigation_first_child(
				nodes,
				current.id,
				request.hidden_ranges,
			)
		}
	case .Subtree_Start, .Subtree_End:
		if has_current {
			candidate, found, candidates = current, true, 1
		}
	case .Next_Structural_Element, .Previous_Structural_Element:
		candidate, found, candidates = navigation_relative_structural(
			nodes,
			request.point.byte_offset,
			request.kind == .Next_Structural_Element,
			request.hidden_ranges,
		)
	case .Next_List_Item, .Previous_List_Item:
		candidate, found, candidates = navigation_relative_node(
			nodes, request.point.byte_offset, request.kind == .Next_List_Item,
			.List_Item, request.hidden_ranges, false,
		)
	case .Next_Table_Row, .Previous_Table_Row:
		candidate, found, candidates = navigation_relative_node(
			nodes, request.point.byte_offset, request.kind == .Next_Table_Row,
			.Table_Row, request.hidden_ranges, false,
		)
	case .Next_Table_Cell, .Previous_Table_Cell:
		candidate, found, candidates = navigation_relative_node(
			nodes, request.point.byte_offset, request.kind == .Next_Table_Cell,
			.Table_Cell, request.hidden_ranges, false,
		)
	case .Next_Drawer, .Previous_Drawer:
		candidate, found, candidates = navigation_relative_drawer(
			nodes, request.point.byte_offset, request.kind == .Next_Drawer,
			request.hidden_ranges,
		)
	case .Next_Block, .Previous_Block:
		candidate, found, candidates = navigation_relative_block(
			nodes, request.point.byte_offset, request.kind == .Next_Block,
			request.hidden_ranges,
		)
	case .Next_Footnote, .Previous_Footnote:
		candidate, found, candidates = navigation_relative_footnote(
			nodes, request.point.byte_offset, request.kind == .Next_Footnote,
			request.hidden_ranges,
		)
	case .Invalid:
	}

	result.candidates = candidates
	if candidates > limits.semantic_targets {
		failure = editing_failure(.Navigate, .Limited, request.scope)
		failure.limit = u64(limits.semantic_targets)
		failure.actual = u64(candidates)
		return result, false, failure
	}
	if !found {
		result.status = .No_Target
		return result, true, {}
	}
	if navigation_node_overlaps_recovery(
		candidate,
		language.jan_structural_analysis_recoveries(analysis),
	) {
		return result, false, editing_failure(.Navigate, .Malformed, request.scope)
	}
	result.status = .Resolved
	result.target = navigation_target(candidate)
	offset := candidate.range.start
	if request.kind == .Subtree_End do offset = candidate.range.end
	result.position = {
		buffer_id = request.scope.analysis.buffer_id,
		revision = request.scope.analysis.source_revision,
		byte_offset = offset,
	}
	return result, true, {}
}

@(private)
navigation_current_heading :: proc(
	nodes: []language.Jan_Node_Record,
	point: editor.Byte_Offset,
) -> (current: language.Jan_Node_Record, found: bool) {
	for node in nodes {
		if node.kind != .Heading || point < node.range.start || point >= node.range.end do continue
		if !found || node.structural_depth >= current.structural_depth {
			current, found = node, true
		}
	}
	return
}

@(private)
navigation_relative_node :: proc(
	nodes: []language.Jan_Node_Record,
	point: editor.Byte_Offset,
	forward: bool,
	kind: language.Jan_Node_Kind,
	hidden_ranges: []view.Hidden_Range,
	require_visible: bool,
) -> (candidate: language.Jan_Node_Record, found: bool, count: u32) {
	for node in nodes {
		if node.kind != kind || (require_visible && !navigation_node_visible(node, hidden_ranges)) {
			continue
		}
		if forward {
			if node.range.start <= point do continue
			if !found || node.range.start < candidate.range.start do candidate, found = node, true
		} else {
			if node.range.start >= point do continue
			if !found || node.range.start > candidate.range.start do candidate, found = node, true
		}
		count += 1
	}
	return
}

@(private)
navigation_sibling :: proc(
	nodes: []language.Jan_Node_Record,
	current: language.Jan_Node_Record,
	forward: bool,
	hidden_ranges: []view.Hidden_Range,
) -> (candidate: language.Jan_Node_Record, found: bool, count: u32) {
	for node in nodes {
		if node.kind != .Heading || node.parent_id != current.parent_id ||
		   node.structural_depth != current.structural_depth ||
		   !navigation_node_visible(node, hidden_ranges) {
			continue
		}
		if forward {
			if node.range.start <= current.range.start do continue
			if !found || node.range.start < candidate.range.start do candidate, found = node, true
		} else {
			if node.range.start >= current.range.start do continue
			if !found || node.range.start > candidate.range.start do candidate, found = node, true
		}
		count += 1
	}
	return
}

@(private)
navigation_first_child :: proc(
	nodes: []language.Jan_Node_Record,
	parent_id: language.Jan_Node_ID,
	hidden_ranges: []view.Hidden_Range,
) -> (candidate: language.Jan_Node_Record, found: bool, count: u32) {
	for node in nodes {
		if node.kind != .Heading || node.parent_id != parent_id ||
		   !navigation_node_visible(node, hidden_ranges) {
			continue
		}
		if !found || node.range.start < candidate.range.start do candidate, found = node, true
		count += 1
	}
	return
}

@(private)
navigation_relative_structural :: proc(
	nodes: []language.Jan_Node_Record,
	point: editor.Byte_Offset,
	forward: bool,
	hidden_ranges: []view.Hidden_Range,
) -> (candidate: language.Jan_Node_Record, found: bool, count: u32) {
	for node in nodes {
		if !navigation_kind_is_structural(node.kind) || !navigation_node_visible(node, hidden_ranges) {
			continue
		}
		if forward {
			if node.range.start <= point do continue
			if !found || node.range.start < candidate.range.start do candidate, found = node, true
		} else {
			if node.range.start >= point do continue
			if !found || node.range.start > candidate.range.start do candidate, found = node, true
		}
		count += 1
	}
	return
}

@(private)
navigation_relative_drawer :: proc(
	nodes: []language.Jan_Node_Record,
	point: editor.Byte_Offset,
	forward: bool,
	hidden_ranges: []view.Hidden_Range,
) -> (candidate: language.Jan_Node_Record, found: bool, count: u32) {
	for node in nodes {
		if node.kind != .Drawer && node.kind != .Property_Drawer do continue
		if !navigation_node_visible(node, hidden_ranges) do continue
		candidate, found, count = navigation_consider_relative(candidate, found, count, node, point, forward)
	}
	return
}

@(private)
navigation_relative_block :: proc(
	nodes: []language.Jan_Node_Record,
	point: editor.Byte_Offset,
	forward: bool,
	hidden_ranges: []view.Hidden_Range,
) -> (candidate: language.Jan_Node_Record, found: bool, count: u32) {
	for node in nodes {
		if !navigation_kind_is_block(node.kind) || !navigation_node_visible(node, hidden_ranges) do continue
		candidate, found, count = navigation_consider_relative(candidate, found, count, node, point, forward)
	}
	return
}

@(private)
navigation_relative_footnote :: proc(
	nodes: []language.Jan_Node_Record,
	point: editor.Byte_Offset,
	forward: bool,
	hidden_ranges: []view.Hidden_Range,
) -> (candidate: language.Jan_Node_Record, found: bool, count: u32) {
	for node in nodes {
		if node.kind != .Footnote_Definition && node.kind != .Named_Footnote_Reference &&
		   node.kind != .Inline_Footnote_Reference &&
		   node.kind != .Anonymous_Footnote_Reference {
			continue
		}
		if !navigation_node_visible(node, hidden_ranges) do continue
		candidate, found, count = navigation_consider_relative(candidate, found, count, node, point, forward)
	}
	return
}

@(private)
navigation_consider_relative :: proc(
	candidate: language.Jan_Node_Record,
	found: bool,
	count: u32,
	node: language.Jan_Node_Record,
	point: editor.Byte_Offset,
	forward: bool,
) -> (language.Jan_Node_Record, bool, u32) {
	result_candidate := candidate
	result_found := found
	if forward {
		if node.range.start <= point do return result_candidate, result_found, count
		if !result_found || node.range.start < result_candidate.range.start {
			result_candidate, result_found = node, true
		}
	} else {
		if node.range.start >= point do return result_candidate, result_found, count
		if !result_found || node.range.start > result_candidate.range.start {
			result_candidate, result_found = node, true
		}
	}
	return result_candidate, result_found, count + 1
}

@(private)
navigation_node_by_id :: proc(
	nodes: []language.Jan_Node_Record,
	id: language.Jan_Node_ID,
) -> (language.Jan_Node_Record, bool) {
	if id == language.Jan_Node_ID(0) do return {}, false
	for node in nodes do if node.id == id do return node, true
	return {}, false
}

@(private)
navigation_target :: proc(node: language.Jan_Node_Record) -> Target {
	return {kind = navigation_target_kind(node.kind), node_id = node.id, range = node.range}
}

@(private)
navigation_target_kind :: proc(kind: language.Jan_Node_Kind) -> Target_Kind {
	#partial switch kind {
	case .Heading: return .Heading
	case .List_Item: return .List_Item
	case .Drawer, .Property_Drawer: return .Drawer
	case .Center_Block, .Quote_Block, .Special_Block, .Dynamic_Block, .Table_Provider_Form,
	     .Source_Block, .Example_Block, .Export_Block, .Comment_Block, .Lesser_Block:
		return .Block
	case .Pipe_Table: return .Table
	case .Table_Row, .Table_Separator_Row: return .Table_Row
	case .Table_Cell: return .Table_Cell
	case .Footnote_Definition, .Named_Footnote_Reference, .Inline_Footnote_Reference,
	     .Anonymous_Footnote_Reference:
		return .Footnote
	case .Invalid, .Document_Root, .Zeroth_Section, .Section, .Inline_Task, .Plain_List,
	     .Clock, .Diary_Expression, .Planning_Line, .Line_Comment, .Fixed_Width_Area,
	     .Horizontal_Rule, .Keyword, .Affiliated_Keyword, .Latex_Environment,
	     .Node_Property, .Paragraph, .Entity, .Special_Symbol, .Latex_Fragment,
	     .Export_Snippet, .Citation, .Citation_Reference, .Inline_Call,
	     .Inline_Source, .Explicit_Line_Break, .Radio_Link, .Plain_Link, .Angle_Link,
	     .Regular_Link, .Macro, .Target, .Radio_Target, .Percentage_Cookie,
	     .Fraction_Cookie, .Subscript, .Superscript, .Bold_Markup, .Italic_Markup,
	     .Underline_Markup, .Verbatim_Markup, .Code_Markup, .Strike_Through_Markup,
	     .Plain_Text, .Preserved_Whitespace, .Recovery:
	}
	return .Structural_Element
}

@(private)
navigation_kind_is_structural :: proc(kind: language.Jan_Node_Kind) -> bool {
	return kind == .Heading || kind == .List_Item || kind == .Drawer ||
	       kind == .Property_Drawer || kind == .Pipe_Table || kind == .Table_Row ||
	       kind == .Table_Separator_Row || kind == .Table_Cell ||
	       kind == .Footnote_Definition || navigation_kind_is_block(kind)
}

@(private)
navigation_kind_is_block :: proc(kind: language.Jan_Node_Kind) -> bool {
	return kind == .Center_Block || kind == .Quote_Block || kind == .Special_Block ||
	       kind == .Dynamic_Block || kind == .Table_Provider_Form ||
	       kind == .Source_Block || kind == .Example_Block || kind == .Export_Block ||
	       kind == .Comment_Block || kind == .Lesser_Block
}

@(private)
navigation_node_visible :: proc(
	node: language.Jan_Node_Record,
	hidden_ranges: []view.Hidden_Range,
) -> bool {
	for hidden in hidden_ranges {
		if node.range.start >= hidden.start.byte_offset &&
		   node.range.start < hidden.end.byte_offset {
			return false
		}
	}
	return true
}

@(private)
navigation_hidden_range_is_valid :: proc(
	hidden: view.Hidden_Range,
	scope: Scope,
	source_bytes: u64,
) -> bool {
	return hidden.start.buffer_id == scope.analysis.buffer_id &&
	       hidden.end.buffer_id == scope.analysis.buffer_id &&
	       hidden.start.revision == scope.analysis.source_revision &&
	       hidden.end.revision == scope.analysis.source_revision &&
	       hidden.start.byte_offset < hidden.end.byte_offset &&
	       u64(hidden.end.byte_offset) <= source_bytes
}

@(private)
navigation_node_overlaps_recovery :: proc(
	node: language.Jan_Node_Record,
	recoveries: []language.Jan_Recovery_Record,
) -> bool {
	for recovery in recoveries {
		if recovery.range.start < node.range.end && recovery.range.end > node.range.start {
			return true
		}
	}
	return false
}
