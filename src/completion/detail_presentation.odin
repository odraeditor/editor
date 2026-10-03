// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package completion

import "../ui"
import "core:unicode/utf8"

/* MAX_COMPLETION_DETAIL_ROWS bounds one explicit candidate-detail surface. */
MAX_COMPLETION_DETAIL_ROWS :: 12
/* MAX_COMPLETION_DETAIL_ROW_BYTES bounds each copied detail line. */
MAX_COMPLETION_DETAIL_ROW_BYTES :: 256

/* Detail_Presentation_Request declares one bounded contextual detail generation. */
Detail_Presentation_Request :: struct {
	presentation_generation: u64,
	row_bytes:               u32,
	profile:                 ui.Presentation_Profile_Record,
}

/* Detail_Presentation reports the shared view and its minimum useful geometry. */
Detail_Presentation :: struct {
	view:          ui.Object_Handle,
	candidate_id:  Candidate_ID,
	state:         Detail_State,
	rows:          u32,
	columns:       u32,
	content_bytes: u32,
}

@(private)
Detail_Row :: struct {
	bytes:      [MAX_COMPLETION_DETAIL_ROW_BYTES]u8,
	byte_count: u16,
	style:      ui.Style_Role,
	passive:    bool,
}

/* controller_project_candidate_detail copies selected detail into shared ListView. */
controller_project_candidate_detail :: proc(
	controller: ^Controller,
	proposal: ^ui.Proposal,
	request: Detail_Presentation_Request,
) -> (presentation: Detail_Presentation, ok: bool, failure: ui.Failure) {
	if proposal == nil || request.presentation_generation == 0 || request.row_bytes < 4 ||
	   request.row_bytes > MAX_COMPLETION_DETAIL_ROW_BYTES ||
	   !completion_detail_profile_is_valid(request.profile) {
		return {}, false, completion_presentation_failure()
	}
	detail, available, _ := controller_candidate_detail(controller)
	if !available do return {}, false, completion_presentation_failure()
	definition := request.profile.definition
	content_style, content_ok := ui.presentation_profile_definition_style(&definition, .Content)
	title_style, title_ok := ui.presentation_profile_definition_style(&definition, .Title)
	if !title_ok do title_style = content_style
	attention_style, attention_ok := ui.presentation_profile_definition_style(&definition, .Attention)
	unavailable_style, unavailable_ok := ui.presentation_profile_definition_style(
		&definition,
		.Unavailable,
	)
	if !content_ok || !attention_ok || !unavailable_ok {
		return {}, false, completion_presentation_failure()
	}

	rows: [MAX_COMPLETION_DETAIL_ROWS]Detail_Row
	row_count := 0
	kind, kind_ok := completion_kind_text(detail.kind)
	if !kind_ok || !completion_detail_row_write(
		&rows[row_count],
		kind,
		text_view(&detail.label),
		request.row_bytes,
		title_style,
		false,
	) {
		return {}, false, completion_presentation_failure()
	}
	row_count += 1

	detail_text := detail.detail
	if detail_text.byte_count > 0 {
		if !completion_detail_row_write(
			&rows[row_count],
			"",
			detail_view(&detail_text),
			request.row_bytes,
			content_style,
			true,
		) {
			return {}, false, completion_presentation_failure()
		}
		row_count += 1
	}

	documentation := detail.documentation
	if documentation.byte_count > 0 {
		row_count = completion_detail_documentation_rows(
			&rows,
			row_count,
			detail_view(&documentation),
			detail.documentation_format,
			request.row_bytes,
			content_style,
		)
		if row_count < 0 do return {}, false, completion_presentation_failure()
	}
	if row_count == 1 && detail.state != .Ready {
		message := "Details available on request"
		style := attention_style
		if detail.state == .Resolving do message = "Loading details..."
		if detail.state == .Unavailable {
			message = "Details unavailable"
			style = unavailable_style
		}
		if !completion_detail_row_write(
			&rows[row_count], "", message, request.row_bytes, style, true,
		) {
			return {}, false, completion_presentation_failure()
		}
		row_count += 1
	}

	definitions: [MAX_COMPLETION_DETAIL_ROWS]ui.List_Item_Definition
	columns := u32(0)
	content_bytes := u32(0)
	for index in 0 ..< row_count {
		row := &rows[index]
		definitions[index] = {
			id = ui.List_Item_ID(index + 1),
			text = string(row.bytes[:row.byte_count]),
			passive = row.passive,
		}
		if !row.passive {
			definitions[index].action = {
				owner_id = ui.Owner_ID(detail.controller_id),
				action_id = ui.List_Action_ID(detail.candidate_id),
				generation = u64(detail.projection_generation),
			}
		}
		definitions[index].style_spans[0] = {
			start_byte = 0,
			end_byte = u32(row.byte_count),
			style_role = row.style,
		}
		definitions[index].style_span_count = 1
		columns = max(columns, u32(row.byte_count))
		content_bytes += u32(row.byte_count)
	}

	view, viewed, view_failure := ui.proposal_project_list_view(
		proposal,
		ui.List_Projection_Request {
			model = {
				owner_id = ui.Owner_ID(detail.controller_id),
				model_id = ui.Model_ID(detail.candidate_id),
				generation = ui.Model_Generation(detail.projection_generation),
			},
			position = {
				presentation_generation = request.presentation_generation,
				selection_owner = .Model,
				current_item = 0,
				viewport_items = u32(row_count),
			},
			read_only = true,
		},
		definitions[:row_count],
	)
	if !viewed do return {}, false, view_failure
	return {
		view = view,
		candidate_id = detail.candidate_id,
		state = detail.state,
		rows = u32(row_count),
		columns = columns,
		content_bytes = content_bytes,
	}, true, {}
}

@(private)
completion_detail_documentation_rows :: proc(
	rows: ^[MAX_COMPLETION_DETAIL_ROWS]Detail_Row,
	start: int,
	text: string,
	format: Documentation_Format,
	limit: u32,
	style: ui.Style_Role,
) -> int {
	if rows == nil || !utf8.valid_string(text) || format == .Invalid do return -1
	row_count := start
	line_start := 0
	for line_end in 0 ..= len(text) {
		if line_end < len(text) && text[line_end] != '\n' do continue
		if row_count >= MAX_COMPLETION_DETAIL_ROWS do break
		line := text[line_start:line_end]
		if len(line) > 0 && line[len(line) - 1] == '\r' do line = line[:len(line) - 1]
		if !completion_detail_row_normalize(
			&rows[row_count], line, format, limit, style,
		) {
			return -1
		}
		row_count += 1
		line_start = line_end + 1
	}
	return row_count
}

@(private)
completion_detail_row_normalize :: proc(
	row: ^Detail_Row,
	text: string,
	format: Documentation_Format,
	limit: u32,
	style: ui.Style_Role,
) -> bool {
	if row == nil || !utf8.valid_string(text) do return false
	storage: [MAX_COMPLETION_DETAIL_ROW_BYTES]u8
	count := 0
	line_start := true
	for byte in transmute([]u8)text {
		normalized := byte
		if normalized == '\t' do normalized = ' '
		if format == .Markdown &&
		   (normalized == '*' || normalized == '`' || line_start && normalized == '#') {
			continue
		}
		if format == .Markdown && line_start && normalized == ' ' do continue
		if count >= len(storage) do break
		storage[count] = normalized
		count += 1
		if normalized != ' ' do line_start = false
	}
	if count == 0 {
		storage[0] = ' '
		count = 1
	}
	return completion_detail_row_write(
		row,
		"",
		string(storage[:count]),
		limit,
		style,
		true,
	)
}

@(private)
completion_detail_row_write :: proc(
	row: ^Detail_Row,
	prefix, text: string,
	limit: u32,
	style: ui.Style_Role,
	passive: bool,
) -> bool {
	if row == nil || style == .Invalid || limit < 4 ||
	   limit > MAX_COMPLETION_DETAIL_ROW_BYTES || !utf8.valid_string(prefix) ||
	   !utf8.valid_string(text) {
		return false
	}
	row^ = {style = style, passive = passive}
	count := copy(row.bytes[:], transmute([]u8)prefix)
	if prefix != "" && text != "" {
		row.bytes[count] = ' '
		count += 1
	}
	count += copy(row.bytes[count:], transmute([]u8)text)
	row.byte_count = u16(count)
	if count > int(limit) {
		cut := int(limit) - 3
		for cut > 0 && !utf8.valid_string(string(row.bytes[:cut])) do cut -= 1
		copy(row.bytes[cut:int(limit)], "...")
		row.byte_count = u16(limit)
	}
	return row.byte_count > 0 && utf8.valid_string(string(row.bytes[:row.byte_count]))
}

@(private)
completion_detail_profile_is_valid :: proc(record: ui.Presentation_Profile_Record) -> bool {
	return record.handle.role == .Contextual_Information &&
		record.definition.role == .Contextual_Information &&
		ui.presentation_profile_record_is_valid(record)
}
