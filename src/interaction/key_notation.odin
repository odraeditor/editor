// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package interaction

import "core:unicode/utf8"

/* MAX_KEY_SEQUENCE_NOTATION_BYTES bounds one complete human-readable sequence. */
MAX_KEY_SEQUENCE_NOTATION_BYTES :: MAX_SEQUENCE_STROKES * 32

/* key_sequence_notation writes one normalized key sequence without truncation. */
key_sequence_notation :: proc(
	sequence: Key_Sequence,
	output: []u8,
) -> (text: string, ok: bool) {
	if sequence.stroke_count == 0 || int(sequence.stroke_count) > MAX_SEQUENCE_STROKES {
		return "", false
	}
	required := key_sequence_notation_length(sequence)
	if required < 0 || required > len(output) {
		return "", false
	}
	offset := 0
	for index in 0 ..< int(sequence.stroke_count) {
		if index > 0 {
			output[offset] = ' '
			offset += 1
		}
		offset = key_stroke_notation_write(sequence.strokes[index], output, offset)
	}
	assert(offset == required)
	return string(output[:offset]), true
}

/* key_sequence_notation_length returns the exact UTF-8 byte count for one sequence. */
key_sequence_notation_length :: proc(sequence: Key_Sequence) -> int {
	if sequence.stroke_count == 0 || int(sequence.stroke_count) > MAX_SEQUENCE_STROKES {
		return -1
	}
	length := int(sequence.stroke_count) - 1
	for index in 0 ..< int(sequence.stroke_count) {
		stroke_length := key_stroke_notation_length(sequence.strokes[index])
		if stroke_length < 0 {
			return -1
		}
		length += stroke_length
	}
	return length
}

@(private)
key_stroke_notation_length :: proc(stroke: Key_Stroke) -> int {
	if !key_stroke_is_valid(stroke) {
		return -1
	}
	length := 0
	if .Control in stroke.modifiers {length += 2}
	if .Meta in stroke.modifiers {length += 2}
	if .Alt in stroke.modifiers {length += 2}
	if .Super in stroke.modifiers {length += 2}
	if .Shift in stroke.modifiers {length += 2}
	switch stroke.kind {
	case .Unicode_Scalar:
		if stroke.scalar == ' ' {
			return length + 3
		}
		_, bytes := utf8.encode_rune(stroke.scalar)
		return length + bytes
	case .Left:      return length + 4
	case .Right:     return length + 5
	case .Up:        return length + 2
	case .Down:      return length + 4
	case .Home:      return length + 4
	case .End:       return length + 3
	case .Backspace: return length + 3
	case .Delete:    return length + 3
	case .Enter:     return length + 3
	case .Tab:       return length + 3
	case .Insert:    return length + 3
	case .Prior:     return length + 5
	case .Next:      return length + 4
	case .Escape:    return length + 3
	case .F4:        return length + 2
	case .Invalid:   return -1
	}
	unreachable()
}

@(private)
key_stroke_notation_write :: proc(stroke: Key_Stroke, output: []u8, offset: int) -> int {
	cursor := offset
	if .Control in stroke.modifiers {cursor = key_notation_append(output, cursor, "C-")}
	if .Meta in stroke.modifiers {cursor = key_notation_append(output, cursor, "M-")}
	if .Alt in stroke.modifiers {cursor = key_notation_append(output, cursor, "A-")}
	if .Super in stroke.modifiers {cursor = key_notation_append(output, cursor, "s-")}
	if .Shift in stroke.modifiers {cursor = key_notation_append(output, cursor, "S-")}
	switch stroke.kind {
	case .Unicode_Scalar:
		if stroke.scalar == ' ' {
			return key_notation_append(output, cursor, "SPC")
		}
		encoded, bytes := utf8.encode_rune(stroke.scalar)
		copy(output[cursor:], encoded[:bytes])
		return cursor + bytes
	case .Left:      return key_notation_append(output, cursor, "LEFT")
	case .Right:     return key_notation_append(output, cursor, "RIGHT")
	case .Up:        return key_notation_append(output, cursor, "UP")
	case .Down:      return key_notation_append(output, cursor, "DOWN")
	case .Home:      return key_notation_append(output, cursor, "HOME")
	case .End:       return key_notation_append(output, cursor, "END")
	case .Backspace: return key_notation_append(output, cursor, "DEL")
	case .Delete:    return key_notation_append(output, cursor, "DEL")
	case .Enter:     return key_notation_append(output, cursor, "RET")
	case .Tab:       return key_notation_append(output, cursor, "TAB")
	case .Insert:    return key_notation_append(output, cursor, "INS")
	case .Prior:     return key_notation_append(output, cursor, "PRIOR")
	case .Next:      return key_notation_append(output, cursor, "NEXT")
	case .Escape:    return key_notation_append(output, cursor, "ESC")
	case .F4:        return key_notation_append(output, cursor, "F4")
	case .Invalid:   return cursor
	}
	unreachable()
}

@(private)
key_notation_append :: proc(output: []u8, offset: int, value: string) -> int {
	copy(output[offset:], transmute([]u8)value)
	return offset + len(value)
}
