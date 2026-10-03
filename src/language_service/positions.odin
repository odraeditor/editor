// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language_service

import json "core:encoding/json"
import "core:unicode/utf8"

/* LSP_Position is one zero-based line and negotiated-encoding character pair. */
LSP_Position :: struct {
	line:      u32,
	character: u32,
}

/* lsp_position_from_json validates one unsigned protocol position. */
lsp_position_from_json :: proc(value: json.Value) -> (LSP_Position, bool) {
	object, object_ok := value.(json.Object)
	if !object_ok do return {}, false
	line_value, line_present := object["line"]
	character_value, character_present := object["character"]
	line, line_ok := line_value.(json.Integer)
	character, character_ok := character_value.(json.Integer)
	if !line_present || !character_present || !line_ok || !character_ok ||
	   line < 0 || character < 0 || line > i64(max(u32)) || character > i64(max(u32)) {
		return {}, false
	}
	return LSP_Position{line = u32(line), character = u32(character)}, true
}

/* position_to_byte_offset converts one revision-bound LSP position to UTF-8 bytes. */
position_to_byte_offset :: proc(
	text: string,
	position: LSP_Position,
	encoding: Position_Encoding,
) -> (u64, bool, Failure_Context) {
	if !utf8.valid_string(text) || encoding == .Invalid {
		return 0, false, Failure_Context{code = .Invalid_Input}
	}
	line_start, line_end, line_ok := line_extent(text, position.line)
	if !line_ok do return 0, false, Failure_Context{code = .Invalid_Input}
	index := line_start
	units := u32(0)
	for index < line_end {
		if units == position.character do return u64(index), true, {}
		value, width := utf8.decode_rune_in_string(text[index:line_end])
		if width <= 0 || value == utf8.RUNE_ERROR {
			return 0, false, Failure_Context{code = .Invalid_Input}
		}
		increment := position_units(value, width, encoding)
		if increment == 0 || position.character - min(position.character, units) < increment {
			return 0, false, Failure_Context{code = .Invalid_Input}
		}
		units += increment
		index += width
	}
	if units == position.character do return u64(line_end), true, {}
	return 0, false, Failure_Context{code = .Invalid_Input}
}

/* byte_offset_to_position converts one UTF-8 boundary to negotiated LSP units. */
byte_offset_to_position :: proc(
	text: string,
	offset: u64,
	encoding: Position_Encoding,
) -> (LSP_Position, bool, Failure_Context) {
	if offset > u64(len(text)) || encoding == .Invalid || !utf8.valid_string(text) ||
	   !utf8.valid_string(text[:int(offset)]) {
		return {}, false, Failure_Context{code = .Invalid_Input}
	}
	line := u32(0)
	line_start := 0
	for index in 0 ..< int(offset) {
		if text[index] == '\n' {
			if line == max(u32) do return {}, false, Failure_Context{code = .Arithmetic_Overflow}
			line += 1
			line_start = index + 1
		}
	}
	character := u32(0)
	index := line_start
	for index < int(offset) {
		value, width := utf8.decode_rune_in_string(text[index:int(offset)])
		if width <= 0 || value == utf8.RUNE_ERROR {
			return {}, false, Failure_Context{code = .Invalid_Input}
		}
		increment := position_units(value, width, encoding)
		if increment == 0 || increment > max(u32) - character {
			return {}, false, Failure_Context{code = .Arithmetic_Overflow}
		}
		character += increment
		index += width
	}
	return LSP_Position{line = line, character = character}, true, {}
}

@(private = "file")
line_extent :: proc(text: string, requested: u32) -> (int, int, bool) {
	line := u32(0)
	start := 0
	for index in 0 ..< len(text) {
		if text[index] != '\n' do continue
		if line == requested do return start, index, true
		if line == max(u32) do return 0, 0, false
		line += 1
		start = index + 1
	}
	if line == requested do return start, len(text), true
	return 0, 0, false
}

@(private = "file")
position_units :: proc(value: rune, width: int, encoding: Position_Encoding) -> u32 {
	switch encoding {
	case .UTF_8:
		return u32(width)
	case .UTF_16:
		return 2 if value > 0xffff else 1
	case .UTF_32:
		return 1
	case .Invalid:
		return 0
	}
	return 0
}
