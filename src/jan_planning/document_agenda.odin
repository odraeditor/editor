// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_planning

import "../editor"
import "../language"
import "core:strings"

/* Document_Agenda_Row borrows one task heading and its planning text from exact source bytes. */
Document_Agenda_Row :: struct {
	target:        Semantic_Target,
	task_state:    string,
	heading:       string,
	planning:      string,
	has_planning: bool,
}

/* agenda_document_row_count reports task headings available to one document agenda. */
agenda_document_row_count :: proc(
	nodes: []language.Jan_Node_Record,
	attributes: []language.Jan_Attribute_Record,
) -> int {
	count := 0
	for node in nodes {
		if node.kind != .Heading do continue
		for attribute in attributes {
			if attribute.node_id == node.id && agenda_attribute_name_matches(attribute.name, "task-state") {
				count += 1
				break
			}
		}
	}
	return count
}

/* agenda_document_row borrows one task row in source order without changing the document. */
agenda_document_row :: proc(
	nodes: []language.Jan_Node_Record,
	attributes: []language.Jan_Attribute_Record,
	source: []u8,
	position: int,
) -> (Document_Agenda_Row, bool) {
	if position < 0 || len(source) == 0 do return {}, false
	current := 0
	for node in nodes {
		if node.kind != .Heading do continue
		task_state, task := agenda_document_task_state(node, attributes, source)
		if !task do continue
		if current != position {
			current += 1
			continue
		}
		heading := agenda_document_heading(node, source)
		planning, has_planning := agenda_document_planning(node, nodes, source)
		return {
			target = {node_id = node.id, kind = node.kind, range = node.range},
			task_state = task_state,
			heading = heading,
			planning = planning,
			has_planning = has_planning,
		}, true
	}
	return {}, false
}

@(private)
agenda_document_task_state :: proc(
	heading: language.Jan_Node_Record,
	attributes: []language.Jan_Attribute_Record,
	source: []u8,
) -> (string, bool) {
	for attribute in attributes {
		if attribute.node_id == heading.id &&
		   agenda_attribute_name_matches(attribute.name, "task-state") &&
		   attribute.range.end <= editor.Byte_Offset(len(source)) {
			return string(source[int(attribute.range.start):int(attribute.range.end)]), true
		}
	}
	return "", false
}

@(private)
agenda_document_heading :: proc(heading: language.Jan_Node_Record, source: []u8) -> string {
	start := int(heading.range.start)
	end := start
	for end < len(source) && source[end] != '\r' && source[end] != '\n' do end += 1
	return strings.trim_space(string(source[start:end]))
}

@(private)
agenda_document_planning :: proc(
	heading: language.Jan_Node_Record,
	nodes: []language.Jan_Node_Record,
	source: []u8,
) -> (string, bool) {
	limit := heading.range.end
	for node in nodes {
		if node.kind == .Heading && node.range.start > heading.range.start && node.range.start < limit {
			limit = node.range.start
		}
	}
	for node in nodes {
		if node.kind != .Planning_Line || node.range.start <= heading.range.start ||
		   node.range.start >= limit || node.range.end > editor.Byte_Offset(len(source)) {
			continue
		}
		return strings.trim_space(string(source[int(node.range.start):int(node.range.end)])), true
	}
	return "", false
}

@(private)
agenda_attribute_name_matches :: proc(name: language.Jan_Attribute_Name, expected: string) -> bool {
	if int(name.length) != len(expected) do return false
	for value, index in expected do if name.bytes[index] != u8(value) do return false
	return true
}
