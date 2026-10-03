// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package completion

import "core:unicode"
import "core:unicode/utf8"

/* Query_Context is one copied canonical filtering range and trigger context. */
Query_Context :: struct {
	range:             Byte_Range,
	text:              Text,
	grapheme_count:    u16,
	trigger:           Trigger_Kind,
	trigger_character: Text,
}

/* Query_Edit describes one canonical document splice used to update a query. */
Query_Edit :: struct {
	start:       u64,
	end:         u64,
	replacement: string,
}

/* query_derive resolves one generic Unicode-aware query at a cursor boundary. */
query_derive :: proc(
	document_text: string,
	cursor_byte: u64,
	trigger: Trigger_Kind,
	trigger_character := Text{},
	previous_range := Byte_Range{},
) -> (Query_Context, bool, Failure) {
	if !utf8.valid_string(document_text) || cursor_byte > u64(len(document_text)) ||
	   !utf8.valid_string(document_text[:int(cursor_byte)]) || trigger == .Invalid {
		return {}, false, failure(.Start, .Invalid_Range)
	}
	start := cursor_byte
	switch trigger {
	case .Explicit, .Identifier:
		start = query_identifier_start(document_text, cursor_byte)
	case .Trigger_Character:
		character := trigger_character
		value := text_view(&character)
		if value == "" || u64(len(value)) > cursor_byte ||
		   document_text[int(cursor_byte) - len(value):int(cursor_byte)] != value {
			return {}, false, failure(.Start, .Invalid_Request)
		}
	case .Incomplete:
		if !range_is_valid(previous_range) || previous_range.start > cursor_byte ||
		   cursor_byte > u64(len(document_text)) ||
		   !utf8.valid_string(document_text[:int(previous_range.start)]) {
			return {}, false, failure(.Update, .Stale_Request)
		}
		start = previous_range.start
	case .Invalid:
		return {}, false, failure(.Start, .Invalid_Request)
	}
	query_text := document_text[int(start):int(cursor_byte)]
	query, copied := text_copy(query_text)
	if !copied {
		result := failure(.Start, .Text_Limit)
		result.limit = MAX_COMPLETION_TEXT_BYTES
		result.actual = u64(len(query_text))
		return {}, false, result
	}
	graphemes, _, _ := utf8.grapheme_count(query_text)
	if graphemes < 0 || graphemes > int(max(u16)) {
		return {}, false, failure(.Start, .Generation_Limit)
	}
	return Query_Context {
		range = {start = start, end = cursor_byte},
		text = query,
		grapheme_count = u16(graphemes),
		trigger = trigger,
		trigger_character = trigger_character,
	}, true, {}
}

/* query_reconcile_edit updates a compatible query after one exact splice. */
query_reconcile_edit :: proc(
	query: Query_Context,
	base_text: string,
	target_text: string,
	edit: Query_Edit,
) -> (Query_Context, bool, Failure) {
	query_value := query
	if !query_context_is_valid(&query_value) || !query_edit_matches(base_text, target_text, edit) {
		return {}, false, failure(.Update, .Invalid_Request)
	}
	if edit.start < query.range.start || edit.end > query.range.end {
		return {}, false, failure(.Update, .Stale_Request)
	}
	removed := edit.end - edit.start
	replacement_bytes := u64(len(edit.replacement))
	new_end := query.range.end - removed
	if replacement_bytes > max(u64) - new_end {
		return {}, false, failure(.Update, .Generation_Limit)
	}
	new_end += replacement_bytes
	return query_derive(
		target_text,
		new_end,
		.Incomplete,
		{},
		Byte_Range{start = query.range.start, end = new_end},
	)
}

/* query_context_is_valid validates one copied query against its own range. */
query_context_is_valid :: proc(query: ^Query_Context) -> bool {
	if query == nil || !range_is_valid(query.range) || query.trigger == .Invalid do return false
	text := text_view(&query.text)
	return u64(len(text)) == query.range.end - query.range.start &&
		(query.trigger == .Trigger_Character) == (query.trigger_character.byte_count > 0)
}

/* query_context_from_request copies one already validated request query. */
query_context_from_request :: proc(request: ^Request) -> (Query_Context, bool) {
	if request == nil || !request_is_valid(request) do return {}, false
	query := request.query
	query_text := text_view(&query)
	graphemes, _, _ := utf8.grapheme_count(query_text)
	if graphemes < 0 || graphemes > int(max(u16)) do return {}, false
	return Query_Context {
		range = request.query_range,
		text = request.query,
		grapheme_count = u16(graphemes),
		trigger = request.trigger,
		trigger_character = request.trigger_character,
	}, true
}

@(private = "file")
query_identifier_start :: proc(document_text: string, cursor_byte: u64) -> u64 {
	start := int(cursor_byte)
	for start > 0 {
		value, width := utf8.decode_last_rune(document_text[:start])
		if width <= 0 || !query_identifier_rune(value) do break
		start -= width
	}
	return u64(start)
}

@(private = "file")
query_identifier_rune :: proc(value: rune) -> bool {
	return unicode.is_letter(value) || unicode.is_number(value) || value == '_'
}

@(private = "file")
query_edit_matches :: proc(base_text, target_text: string, edit: Query_Edit) -> bool {
	if !utf8.valid_string(base_text) || !utf8.valid_string(target_text) ||
	   !utf8.valid_string(edit.replacement) || edit.start > edit.end ||
	   edit.end > u64(len(base_text)) ||
	   !utf8.valid_string(base_text[:int(edit.start)]) ||
	   !utf8.valid_string(base_text[:int(edit.end)]) {
		return false
	}
	expected := u64(len(base_text)) - (edit.end - edit.start)
	if u64(len(edit.replacement)) > max(u64) - expected ||
	   expected + u64(len(edit.replacement)) != u64(len(target_text)) {
		return false
	}
	replacement_end := int(edit.start) + len(edit.replacement)
	return target_text[:int(edit.start)] == base_text[:int(edit.start)] &&
		target_text[int(edit.start):replacement_end] == edit.replacement &&
		target_text[replacement_end:] == base_text[int(edit.end):]
}
