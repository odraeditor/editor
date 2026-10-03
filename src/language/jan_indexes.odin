// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language

/* jan_build_document_indexes derives only source-local facts from one analysis. */
@(private)
jan_build_document_indexes :: proc(
	state: ^Jan_Structural_Analysis_State,
	source_bytes: u64,
	limits: Jan_Resource_Limits,
) -> Jan_Failure_Code {
	if state == nil do return .Invalid_Index
	for node in state.nodes {
		kinds: [2]Jan_Index_Kind
		count := jan_node_index_kinds(node.kind, &kinds)
		for index in 0 ..< count {
			failure := jan_append_index_fact(state, kinds[index], node, source_bytes, limits)
			if failure != .None do return failure
		}
	}
	for attribute in state.attributes {
		node_index := int(attribute.node_id) - 1
		if node_index < 0 || node_index >= len(state.nodes) do return .Invalid_Index
		node := state.nodes[node_index]
		kind, admitted := jan_attribute_index_kind(node, attribute)
		if !admitted do continue
		failure := jan_append_index_fact(state, kind, node, source_bytes, limits)
		if failure != .None do return failure
	}
	for recovery in state.recoveries {
		node_index := int(recovery.node_id) - 1
		if node_index < 0 || node_index >= len(state.nodes) do return .Invalid_Index
		node := state.nodes[node_index]
		recovery_kinds := [2]Jan_Index_Kind{
			Jan_Index_Kind.Recovery_Region,
			Jan_Index_Kind.Lint_Fact,
		}
		for kind in recovery_kinds {
			failure := jan_append_index_fact(state, kind, node, source_bytes, limits)
			if failure != .None do return failure
		}
	}
	return .None
}

@(private)
jan_node_index_kinds :: proc(
	kind: Jan_Node_Kind,
	result: ^[2]Jan_Index_Kind,
) -> int {
	if result == nil do return 0
	#partial switch kind {
	case .Heading: result[0] = .Heading; return 1
	case .Node_Property: result[0] = .Property; return 1
	case .Target: result[0] = .Target; return 1
	case .Radio_Target: result[0] = .Radio_Target; return 1
	case .Plain_Link, .Angle_Link, .Regular_Link, .Radio_Link:
		result[0] = .Link
		return 1
	case .Active_Timestamp, .Inactive_Timestamp, .Diary_Timestamp,
	     .Point_Timestamp, .Timestamp_Range, .Repeating_Timestamp, .Delayed_Timestamp:
		result[0] = .Timestamp
		return 1
	case .Planning_Line: result[0] = .Planning; return 1
	case .Clock: result[0] = .Clock; return 1
	case .Footnote_Definition, .Named_Footnote_Reference,
	     .Inline_Footnote_Reference, .Anonymous_Footnote_Reference:
		result[0] = .Footnote
		return 1
	case .Citation, .Citation_Reference:
		result[0] = .Citation
		return 1
	case .Pipe_Table, .Table_Provider_Form, .Table_Row, .Table_Separator_Row, .Table_Cell:
		result[0] = .Table
		return 1
	case .Center_Block, .Quote_Block, .Special_Block, .Dynamic_Block,
	     .Source_Block, .Example_Block, .Export_Block, .Comment_Block,
	     .Lesser_Block:
		result[0] = .Block
		if kind == .Source_Block {
			result[1] = .Code_Reference
			return 2
		}
		return 1
	case .Inline_Call: result[0] = .Call; return 1
	case .Inline_Source: result[0] = .Code_Reference; return 1
	case .Affiliated_Keyword: result[0] = .Affiliated_Keyword; return 1
	}
	return 0
}

@(private)
jan_attribute_index_kind :: proc(
	node: Jan_Node_Record,
	attribute: Jan_Attribute_Record,
) -> (Jan_Index_Kind, bool) {
	if jan_index_attribute_name(attribute, "task-state") do return .Task_State, true
	if jan_index_attribute_name(attribute, "priority") do return .Priority, true
	if jan_index_attribute_name(attribute, "tag") do return .Tag, true
	if jan_index_attribute_name(attribute, "file-local-setting") &&
	   jan_index_attribute_value(attribute, "true") {
		return .File_Local_Setting, true
	}
	if (jan_index_attribute_name(attribute, "configured") ||
	    jan_index_attribute_name(attribute, "boundary-valid")) &&
	   jan_index_attribute_value(attribute, "false") {
		return .Lint_Fact, true
	}
	if jan_index_attribute_name(attribute, "scheme") &&
	   jan_index_attribute_value_folded(attribute, "coderef") {
		return .Code_Reference, true
	}
	if !jan_index_attribute_name(attribute, "key") do return .Invalid, false
	if node.kind == .Node_Property {
		if jan_index_attribute_value_folded(attribute, "id") ||
		   jan_index_attribute_value_folded(attribute, "custom_id") {
			return .Identifier, true
		}
		return .Invalid, false
	}
	if node.kind != .Keyword && node.kind != .Affiliated_Keyword do return .Invalid, false
	if jan_index_attribute_value_folded(attribute, "name") do return .Name, true
	if jan_index_attribute_value_folded(attribute, "results") do return .Result, true
	if jan_index_attribute_value_folded(attribute, "tblfm") do return .Formula, true
	if jan_index_attribute_value_folded(attribute, "call") do return .Call, true
	if jan_index_attribute_value_folded(attribute, "bibliography") ||
	   jan_index_attribute_value_folded(attribute, "print_bibliography") {
		return .Bibliography, true
	}
	return .Invalid, false
}

@(private)
jan_append_index_fact :: proc(
	state: ^Jan_Structural_Analysis_State,
	kind: Jan_Index_Kind,
	node: Jan_Node_Record,
	source_bytes: u64,
	limits: Jan_Resource_Limits,
) -> Jan_Failure_Code {
	if state == nil || kind < .Heading || kind > .Recovery_Region do return .Invalid_Index
	for fact in state.indexes {
		if fact.kind == kind && fact.node_id == node.id do return .None
	}
	if len(state.indexes) >= int(limits.index_facts) do return .Limited
	fact := Jan_Index_Fact {
		id = Jan_Index_Fact_ID(len(state.indexes) + 1),
		kind = kind,
		node_id = node.id,
		range = node.range,
	}
	if !jan_index_fact_is_valid(fact, source_bytes) do return .Invalid_Index
	if _, append_error := append(&state.indexes, fact); append_error != nil {
		return .Allocation_Failed
	}
	return .None
}

@(private)
jan_index_attribute_name :: proc(attribute: Jan_Attribute_Record, expected: string) -> bool {
	return jan_bounded_text_matches(attribute.name.bytes, attribute.name.length, expected)
}

@(private)
jan_index_attribute_value :: proc(attribute: Jan_Attribute_Record, expected: string) -> bool {
	return jan_bounded_text_matches(attribute.value.bytes, attribute.value.length, expected)
}

@(private)
jan_index_attribute_value_folded :: proc(
	attribute: Jan_Attribute_Record,
	expected: string,
) -> bool {
	value := attribute.value
	return jan_ascii_equal_folded(value.bytes[:value.length], expected)
}
