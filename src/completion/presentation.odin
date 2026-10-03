// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package completion

import "../ui"
import "core:unicode/utf8"

/* MAX_COMPLETION_PRESENTATION_ROW_BYTES bounds one copied candidate row. */
MAX_COMPLETION_PRESENTATION_ROW_BYTES :: 832
/* MIN_COMPLETION_PRESENTATION_ROW_BYTES preserves one useful portable fallback. */
MIN_COMPLETION_PRESENTATION_ROW_BYTES :: 4

/* Presentation_Request declares one bounded candidate-list generation. */
Presentation_Request :: struct {
	presentation_generation: u64,
	viewport_items:          u32,
	row_bytes:               u32,
	profile:                 ui.Presentation_Profile_Record,
}

@(private)
Presentation_Row :: struct {
	bytes:      [MAX_COMPLETION_PRESENTATION_ROW_BYTES]u8,
	byte_count: u16,
	annotation_start: u16,
	annotation_end:   u16,
	availability_start: u16,
	kind_icon: ui.List_Icon_Role,
	kind_style: ui.Style_Role,
}

/* controller_project_candidates copies one active completion projection into shared ListView. */
controller_project_candidates :: proc(
	controller: ^Controller,
	proposal: ^ui.Proposal,
	request: Presentation_Request,
	allocator := context.allocator,
) -> (handle: ui.Object_Handle, ok: bool, failure: ui.Failure) {
	state := controller_state(controller)
	if state == nil || proposal == nil || allocator.procedure == nil ||
	   request.presentation_generation == 0 || request.viewport_items == 0 ||
	   request.viewport_items > ui.MAX_LIST_ITEMS ||
	   request.row_bytes < MIN_COMPLETION_PRESENTATION_ROW_BYTES ||
	   request.row_bytes > MAX_COMPLETION_PRESENTATION_ROW_BYTES ||
	   !completion_presentation_profile_is_valid(request.profile) ||
	   (state.session_state != .Ready && state.session_state != .Empty &&
	    !(state.session_state == .Requesting && state.retained_during_refresh)) ||
	   state.projection.item_count != u16(len(state.projection.items)) ||
	   state.projection.batch_id != state.batch.id ||
	   state.projection.batch_generation != state.batch.generation {
		return {}, false, completion_presentation_failure()
	}

	rows, rows_error := make([]Presentation_Row, len(state.projection.items), allocator)
	if rows_error != nil {
		return {}, false, ui.Failure{operation = .Prepare, code = .Allocation}
	}
	defer delete(rows, allocator)
	definitions, definitions_error := make(
		[]ui.List_Item_Definition,
		len(state.projection.items),
		allocator,
	)
	if definitions_error != nil {
		return {}, false, ui.Failure{operation = .Prepare, code = .Allocation}
	}
	defer delete(definitions, allocator)

	profile_definition := request.profile.definition
	annotation_style, annotation_ok := ui.presentation_profile_definition_style(
		&profile_definition,
		.Annotation,
	)
	unavailable_style, unavailable_ok := ui.presentation_profile_definition_style(
		&profile_definition,
		.Unavailable,
	)
	if !annotation_ok || !unavailable_ok {
		return {}, false, completion_presentation_failure()
	}

	current_item := i32(-1)
	for projection_item, index in state.projection.items {
		if int(projection_item.source_index) >= len(state.batch.items) {
			return {}, false, completion_presentation_failure()
		}
		candidate := &state.batch.items[projection_item.source_index]
		if candidate.id == Candidate_ID(0) || candidate.id != projection_item.candidate_id {
			return {}, false, completion_presentation_failure()
		}
		row_ok := completion_presentation_row(
			&rows[index],
			candidate,
			int(request.row_bytes),
		)
		if !row_ok {
			return {}, false, completion_presentation_failure()
		}
		row := &rows[index]
		definitions[index] = {
			id = ui.List_Item_ID(candidate.id),
			text = string(row.bytes[:row.byte_count]),
			icon_role = row.kind_icon,
			icon_style_role = row.kind_style,
			action = {
				owner_id = ui.Owner_ID(state.controller_id),
				action_id = ui.List_Action_ID(candidate.id),
				generation = u64(state.projection.generation),
			},
		}
		completion_presentation_add_span(
			&definitions[index],
			u32(row.annotation_start),
			u32(row.annotation_end),
			annotation_style,
		)
		completion_presentation_add_span(
			&definitions[index],
			u32(row.availability_start),
			u32(row.byte_count),
			unavailable_style,
		)
		if candidate.id == state.selected_candidate do current_item = i32(index)
	}

	if len(definitions) > 0 && current_item < 0 {
		return {}, false, completion_presentation_failure()
	}
	first_visible := u32(0)
	if current_item >= i32(request.viewport_items) {
		first_visible = u32(current_item) - request.viewport_items + 1
	}
	return ui.proposal_project_list_view(
		proposal,
		ui.List_Projection_Request {
			model = {
				owner_id = ui.Owner_ID(state.controller_id),
				model_id = ui.Model_ID(state.session_id),
				generation = ui.Model_Generation(state.session_generation),
			},
			position = {
				presentation_generation = request.presentation_generation,
				selection_owner = .Model,
				current_item = current_item,
				first_visible_item = first_visible,
				viewport_items = request.viewport_items,
			},
			read_only = true,
		},
		definitions,
	)
}

@(private)
completion_presentation_row :: proc(
	row: ^Presentation_Row,
	candidate: ^Candidate,
	limit: int,
) -> bool {
	if row == nil || candidate == nil || limit < MIN_COMPLETION_PRESENTATION_ROW_BYTES ||
	   limit > MAX_COMPLETION_PRESENTATION_ROW_BYTES {
		return false
	}
	row^ = {}
	kind_icon, kind_style, kind_ok := completion_kind_icon_presentation(candidate.kind)
	if !kind_ok do return false
	row.kind_icon = kind_icon
	row.kind_style = kind_style
	offset := 0
	label := candidate.label
	offset += copy(row.bytes[offset:], transmute([]u8)text_view(&label))

	label_detail := candidate.label_detail
	description := candidate.description
	detail := text_view(&label_detail)
	description_text := text_view(&description)
	if detail != "" || description_text != "" {
		offset += copy(row.bytes[offset:], "  ")
		row.annotation_start = u16(offset)
		if detail != "" do offset += copy(row.bytes[offset:], transmute([]u8)detail)
		if detail != "" && description_text != "" {
			offset += copy(row.bytes[offset:], " - ")
		}
		if description_text != "" {
			offset += copy(row.bytes[offset:], transmute([]u8)description_text)
		}
		row.annotation_end = u16(offset)
	}

	availability := completion_availability_text(candidate.availability)
	if availability != "" {
		offset += copy(row.bytes[offset:], "  ")
		row.availability_start = u16(offset)
		offset += copy(row.bytes[offset:], transmute([]u8)availability)
	} else {
		row.availability_start = u16(offset)
	}
	if offset > len(row.bytes) do return false
	row.byte_count = u16(offset)
	completion_presentation_truncate(row, limit)
	return utf8.valid_string(string(row.bytes[:row.byte_count]))
}

@(private)
completion_kind_icon_presentation :: proc(
	kind: Candidate_Kind,
) -> (icon: ui.List_Icon_Role, style: ui.Style_Role, ok: bool) {
	switch kind {
	case .Textual:   return .Textual, .Syntax_String, true
	case .Callable:  return .Callable, .Syntax_Function, true
	case .Construct: return .Construct, .Syntax_Constructor, true
	case .Value:     return .Value, .Syntax_Constant, true
	case .Type:      return .Type, .Syntax_Type, true
	case .Module:    return .Module, .Syntax_Label, true
	case .Field:     return .Field, .Syntax_Attribute, true
	case .Keyword:   return .Keyword, .Syntax_Keyword, true
	case .Invalid:
		return .Invalid, .Invalid, false
	}
	return .Invalid, .Invalid, false
}

@(private)
completion_kind_text :: proc(kind: Candidate_Kind) -> (string, bool) {
	switch kind {
	case .Textual:   return "[text]", true
	case .Callable:  return "[call]", true
	case .Construct: return "[ctor]", true
	case .Value:     return "[value]", true
	case .Type:      return "[type]", true
	case .Module:    return "[module]", true
	case .Field:     return "[field]", true
	case .Keyword:   return "[keyword]", true
	case .Invalid:   return "", false
	}
	return "", false
}

@(private)
completion_availability_text :: proc(availability: Candidate_Availability) -> string {
	switch availability {
	case .Available: return ""
	case .Deprecated: return "[deprecated]"
	case .Unavailable: return "[unavailable]"
	case .Invalid: return ""
	}
	return ""
}

@(private)
completion_presentation_truncate :: proc(row: ^Presentation_Row, limit: int) {
	if row == nil || int(row.byte_count) <= limit do return
	cut := limit - 3
	for cut > 0 && !utf8.valid_string(string(row.bytes[:cut])) do cut -= 1
	copy(row.bytes[cut:limit], "...")
	row.byte_count = u16(limit)
	row.annotation_start = min(row.annotation_start, row.byte_count)
	row.annotation_end = min(row.annotation_end, row.byte_count)
	if row.annotation_start >= row.annotation_end {
		row.annotation_start = 0
		row.annotation_end = 0
	}
	row.availability_start = min(row.availability_start, row.byte_count)
}

@(private)
completion_presentation_add_span :: proc(
	definition: ^ui.List_Item_Definition,
	start, end: u32,
	style: ui.Style_Role,
) {
	if definition == nil || start >= end || style == .Invalid ||
	   definition.style_span_count >= ui.MAX_LIST_ITEM_STYLE_SPANS {
		return
	}
	definition.style_spans[definition.style_span_count] = {
		start_byte = start,
		end_byte = end,
		style_role = style,
	}
	definition.style_span_count += 1
}

@(private)
completion_presentation_profile_is_valid :: proc(record: ui.Presentation_Profile_Record) -> bool {
	return record.handle.role == .Interactive_Candidates &&
		record.definition.role == .Interactive_Candidates &&
		ui.presentation_profile_record_is_valid(record)
}

@(private)
completion_presentation_failure :: proc() -> ui.Failure {
	return {operation = .Prepare, code = .Invalid_List_View}
}
