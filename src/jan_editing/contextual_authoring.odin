// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_editing

import "../editor"
import "../language"

/* Authoring_Context is the stable contextual-action precedence vocabulary. */
Authoring_Context :: enum u8 {
	Invalid,
	Document,
	Paragraph,
	Heading,
	List_Item,
	Block,
	Drawer,
	Table,
	Footnote,
	Link,
	Future_Task,
	Future_Property,
	Future_Time,
	Future_Table_Formula,
	Future_Source_Execution,
	Future_Citation,
}

/* Authoring_Command is the inspectable semantic result, independent of a physical key. */
Authoring_Command :: enum u8 {
	Invalid,
	Cycle_Global,
	Expand_Template,
	Cycle_Heading,
	Insert_List_Item,
	Select_Structure,
	Cycle_Drawer,
	Next_Table_Cell,
	Visit_Footnote,
	Inspect_Link,
	Move_Up,
	Move_Down,
	Unavailable,
}

/* Context_Resolution_Status distinguishes a concrete command from explicit absence. */
Context_Resolution_Status :: enum u8 {
	Invalid,
	Resolved,
	Unavailable,
	No_Context,
}

/* Context_Resolution exposes the chosen syntax, target, command, and later-stage owner. */
Context_Resolution :: struct {
	operation_id: Operation_ID,
	scope:        Scope,
	status:       Context_Resolution_Status,
	ctx:          Authoring_Context,
	command:      Authoring_Command,
	target:       Target,
	precedence:   u8,
	future_owner: language.Jan_Stage,
}

/* Context_Action_Request resolves one exact source position. */
Context_Action_Request :: struct {
	operation_id: Operation_ID,
	scope:        Scope,
	point:        editor.Byte_Offset,
}

/* Speed_Key_Resolution reports admission only at one declared structural position. */
Speed_Key_Resolution :: struct {
	admitted: bool,
	key:      rune,
	ctx:      Authoring_Context,
	command:  Authoring_Command,
	target:   Target,
}

/* Repeat_Kind is the closed semantic repetition family. */
Repeat_Kind :: enum u8 {
	Invalid,
	Context_Action,
	Move_Up,
	Move_Down,
	Insert_After,
}

/* Semantic_Repeat_Metadata retains intent but no byte range or parser identity. */
Semantic_Repeat_Metadata :: struct {
	operation_id:             Operation_ID,
	buffer_id:                editor.Buffer_ID,
	source_revision:          editor.Revision,
	configuration_generation: Configuration_Generation,
	repeat:                   Repeat_Kind,
	command:                  Authoring_Command,
	ctx:                      Authoring_Context,
}

/* context_action_resolve selects the deepest admitted syntax through fixed precedence. */
context_action_resolve :: proc(
	analysis: ^language.Jan_Structural_Analysis,
	source: []u8,
	request: Context_Action_Request,
) -> (Context_Resolution, bool, Failure) {
	if analysis == nil || request.operation_id == Operation_ID(0) ||
	   !scope_is_valid(request.scope) || u64(request.point) > u64(len(source)) {
		return {}, false, editing_failure(.Resolve_Context, .Invalid_Scope, request.scope)
	}
	nodes := language.jan_structural_analysis_nodes(analysis)
	usage, inspected := language.jan_structural_analysis_usage(analysis)
	if !inspected || usage.source_bytes != u64(len(source)) || len(nodes) == 0 ||
	   nodes[0].range.scope != request.scope.analysis {
		return {}, false, editing_failure(.Resolve_Context, .Stale, request.scope)
	}
	selected: language.Jan_Node_Record
	selected_context := Authoring_Context.Invalid
	selected_precedence: u8
	found := false
	for node in nodes {
		if request.point < node.range.start || request.point > node.range.end do continue
		ctx := authoring_context_from_node(node.kind)
		precedence := authoring_context_precedence(ctx)
		if precedence == 0 do continue
		if !found || precedence > selected_precedence ||
		   (precedence == selected_precedence &&
		    node.range.end - node.range.start < selected.range.end - selected.range.start) {
			selected = node
			selected_context = ctx
			selected_precedence = precedence
			found = true
		}
	}
	if !found {
		return {
			operation_id = request.operation_id,
			scope = request.scope,
			status = .No_Context,
		}, true, {}
	}
	command, future_owner := authoring_context_command(selected_context)
	status := Context_Resolution_Status.Resolved
	if command == .Unavailable do status = .Unavailable
	return {
		operation_id = request.operation_id,
		scope = request.scope,
		status = status,
		ctx = selected_context,
		command = command,
		target = navigation_target(selected),
		precedence = selected_precedence,
		future_owner = future_owner,
	}, true, {}
}

/* speed_key_resolve admits compact keys only on exact structural prefixes. */
speed_key_resolve :: proc(
	analysis: ^language.Jan_Structural_Analysis,
	source: []u8,
	request: Context_Action_Request,
	key: rune,
) -> (Speed_Key_Resolution, bool, Failure) {
	resolution, resolved, failure := context_action_resolve(analysis, source, request)
	if !resolved do return {}, false, failure
	if resolution.status != .Resolved ||
	   !speed_key_structural_position(source, request.point, resolution.ctx) {
		return {key = key, ctx = resolution.ctx, target = resolution.target}, true, {}
	}
	command := Authoring_Command.Invalid
	switch key {
	case 'n': command = .Move_Down
	case 'p': command = .Move_Up
	case '\t': command = resolution.command
	}
	if command == .Invalid {
		return {key = key, ctx = resolution.ctx, target = resolution.target}, true, {}
	}
	return {
		admitted = true,
		key = key,
		ctx = resolution.ctx,
		command = command,
		target = resolution.target,
	}, true, {}
}

/* semantic_repeat_capture publishes intent without retaining a stale target range. */
semantic_repeat_capture :: proc(
	resolution: Context_Resolution,
	repeat: Repeat_Kind,
) -> (Semantic_Repeat_Metadata, bool) {
	if resolution.status != .Resolved || repeat <= .Invalid || repeat > .Insert_After ||
	   resolution.operation_id == Operation_ID(0) || !scope_is_valid(resolution.scope) {
		return {}, false
	}
	command := resolution.command
	#partial switch repeat {
	case .Move_Up: command = .Move_Up
	case .Move_Down: command = .Move_Down
	}
	return {
		operation_id = resolution.operation_id,
		buffer_id = resolution.scope.analysis.buffer_id,
		source_revision = resolution.scope.analysis.source_revision,
		configuration_generation = resolution.scope.configuration_generation,
		repeat = repeat,
		command = command,
		ctx = resolution.ctx,
	}, true
}

/* semantic_repeat_resolve finds a fresh contextual target on the current revision. */
semantic_repeat_resolve :: proc(
	analysis: ^language.Jan_Structural_Analysis,
	source: []u8,
	current_scope: Scope,
	point: editor.Byte_Offset,
	metadata: Semantic_Repeat_Metadata,
) -> (Context_Resolution, bool, Failure) {
	if metadata.operation_id == Operation_ID(0) || metadata.buffer_id == editor.Buffer_ID(0) ||
	   metadata.repeat <= .Invalid || metadata.repeat > .Insert_After ||
	   current_scope.analysis.buffer_id != metadata.buffer_id ||
	   current_scope.configuration_generation != metadata.configuration_generation {
		return {}, false, editing_failure(.Resolve_Context, .Stale, current_scope)
	}
	request := Context_Action_Request {
		operation_id = metadata.operation_id,
		scope = current_scope,
		point = point,
	}
	resolution, resolved, failure := context_action_resolve(analysis, source, request)
	if !resolved || resolution.status != .Resolved do return resolution, resolved, failure
	#partial switch metadata.repeat {
	case .Move_Up: resolution.command = .Move_Up
	case .Move_Down: resolution.command = .Move_Down
	case .Insert_After:
		if resolution.ctx == .List_Item {
			resolution.command = .Insert_List_Item
		} else if resolution.ctx != .Heading {
			resolution.status = .Unavailable
			resolution.command = .Unavailable
		}
	}
	return resolution, true, {}
}

/* authoring_context_precedence is the stable public resolution order. */
authoring_context_precedence :: proc(ctx: Authoring_Context) -> u8 {
	return u8(ctx)
}

@(private)
authoring_context_from_node :: proc(kind: language.Jan_Node_Kind) -> Authoring_Context {
	#partial switch kind {
	case .Document_Root, .Zeroth_Section, .Section: return .Document
	case .Paragraph, .Plain_Text: return .Paragraph
	case .Heading: return .Heading
	case .List_Item, .Plain_List: return .List_Item
	case .Center_Block, .Quote_Block, .Special_Block, .Dynamic_Block,
	     .Source_Block, .Example_Block, .Export_Block, .Comment_Block,
	     .Lesser_Block: return .Block
	case .Drawer: return .Drawer
	case .Pipe_Table, .Table_Row, .Table_Separator_Row, .Table_Cell: return .Table
	case .Footnote_Definition, .Named_Footnote_Reference,
	     .Inline_Footnote_Reference, .Anonymous_Footnote_Reference: return .Footnote
	case .Radio_Link, .Plain_Link, .Angle_Link, .Regular_Link: return .Link
	case .Inline_Task: return .Future_Task
	case .Property_Drawer, .Node_Property: return .Future_Property
	case .Clock, .Diary_Expression, .Planning_Line, .Active_Timestamp,
	     .Inactive_Timestamp, .Diary_Timestamp, .Point_Timestamp,
	     .Timestamp_Range, .Repeating_Timestamp, .Delayed_Timestamp: return .Future_Time
	case .Table_Provider_Form: return .Future_Table_Formula
	case .Inline_Call, .Inline_Source: return .Future_Source_Execution
	case .Citation, .Citation_Reference: return .Future_Citation
	case .Invalid, .Line_Comment, .Fixed_Width_Area,
	     .Horizontal_Rule, .Keyword, .Affiliated_Keyword, .Latex_Environment,
	     .Entity, .Special_Symbol, .Latex_Fragment, .Export_Snippet,
	     .Macro, .Target, .Radio_Target, .Percentage_Cookie, .Fraction_Cookie,
	     .Subscript, .Superscript, .Bold_Markup, .Italic_Markup,
	     .Underline_Markup, .Verbatim_Markup, .Code_Markup,
	     .Strike_Through_Markup, .Preserved_Whitespace, .Recovery:
	}
	return .Invalid
}

@(private)
authoring_context_command :: proc(ctx: Authoring_Context) -> (Authoring_Command, language.Jan_Stage) {
	switch ctx {
	case .Document:  return .Cycle_Global, .Structured_Editing
	case .Paragraph: return .Expand_Template, .Structured_Editing
	case .Heading:   return .Cycle_Heading, .Structured_Editing
	case .List_Item: return .Insert_List_Item, .Structured_Editing
	case .Block:     return .Select_Structure, .Structured_Editing
	case .Drawer:    return .Cycle_Drawer, .Structured_Editing
	case .Table:     return .Next_Table_Cell, .Structured_Editing
	case .Footnote:  return .Visit_Footnote, .Structured_Editing
	case .Link:      return .Inspect_Link, .Structured_Editing
	case .Future_Task, .Future_Property, .Future_Time:
		return .Unavailable, .Planning_And_Agenda
	case .Future_Table_Formula, .Future_Source_Execution:
		return .Unavailable, .Computable_Documents
	case .Future_Citation:
		return .Unavailable, .Export_Publishing_And_Integration
	case .Invalid:
	}
	return .Invalid, .Invalid
}

@(private)
speed_key_structural_position :: proc(source: []u8, point: editor.Byte_Offset, ctx: Authoring_Context) -> bool {
	position := int(point)
	if position < 0 || position >= len(source) do return false
	line_start := position
	for line_start > 0 && source[line_start - 1] != '\n' do line_start -= 1
	first := line_start
	for first < len(source) && (source[first] == ' ' || source[first] == '\t') do first += 1
	if position != first do return false
	switch ctx {
	case .Heading: return first == line_start && source[first] == '*'
	case .List_Item: return source[first] == '-' || source[first] == '+' || source[first] == '*'
	case .Table: return source[first] == '|'
	case .Block: return first + 8 <= len(source) && string(source[first:first + 8]) == "#+begin_"
	case .Drawer: return source[first] == ':'
	case .Invalid, .Document, .Paragraph, .Footnote, .Link, .Future_Task,
	     .Future_Property, .Future_Time, .Future_Table_Formula,
	     .Future_Source_Execution, .Future_Citation:
	}
	return false
}
