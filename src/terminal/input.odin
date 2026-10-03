// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package terminal_frontend

import "../interaction"
import "core:unicode/utf8"

/* decoder_push consumes one byte and returns at most one normalized event. */
decoder_push :: proc(
	decoder: ^Decoder,
	value: u8,
	pointer_context: Pointer_Context = {},
) -> Decode_Output {
	assert(decoder != nil)
	switch decoder.state {
	case .Ground:
		return decoder_ground(decoder, value)
	case .Escape:
		if value != '[' && value != 'O' {
			count := decoder.count + 1
			decoder_reset(decoder)
			if value == 0x00 {
				return control_meta_key_output(' ', count)
			}
			// Terminals encode C-% (also produced by C-5) as the GS control byte.
			if value == 0x1d {
				return control_meta_key_output('%', count)
			}
			if value >= 0x01 && value <= 0x1a {
				return control_meta_key_output(rune('a' + value - 1), count)
			}
			if value >= 0x20 && value <= 0x7e {
				return meta_key_output(rune(value), count)
			}
			return Decode_Output{status = .Unknown, sequence_bytes = count}
		}
		decoder.bytes[decoder.count] = value
		decoder.count += 1
		decoder.state = .CSI if value == '[' else .SS3
		return Decode_Output{status = .Pending, sequence_bytes = decoder.count}
	case .CSI:
		if decoder.count >= MAX_INPUT_SEQUENCE_BYTES {
			count := decoder.count + 1
			decoder_reset(decoder)
			return Decode_Output{status = .Oversized, sequence_bytes = count}
		}
		decoder.bytes[decoder.count] = value
		decoder.count += 1
		if value >= 0x40 && value <= 0x7e {
			return decoder_finish_csi(decoder, pointer_context)
		}
		return Decode_Output{status = .Pending, sequence_bytes = decoder.count}
	case .SS3:
		decoder.bytes[decoder.count] = value
		decoder.count += 1
		return decoder_finish_ss3(decoder)
	case .UTF8:
		if value < 0x80 || value > 0xbf {
			count := decoder.count + 1
			decoder_reset(decoder)
			return Decode_Output{status = .Malformed, sequence_bytes = count}
		}
		decoder.bytes[decoder.count] = value
		decoder.count += 1
		if decoder.count < decoder.expected {
			return Decode_Output{status = .Pending, sequence_bytes = decoder.count}
		}
		decoded, width := utf8.decode_rune(decoder.bytes[:decoder.count])
		if width != int(decoder.expected) || decoded < 0 {
			count := decoder.count
			decoder_reset(decoder)
			return Decode_Output{status = .Malformed, sequence_bytes = count}
		}
		return decoder_text_event(decoder)
	}
	unreachable()
}

@(private)
decoder_finish_ss3 :: proc(decoder: ^Decoder) -> Decode_Output {
	count := decoder.count
	kind := interaction.Logical_Key_Kind.Invalid
	switch decoder.bytes[2] {
	case 'H': kind = .Home
	case 'F': kind = .End
	case 'S': kind = .F4
	case:    kind = .Invalid
	}
	decoder_reset(decoder)
	if kind == .Invalid {
		return Decode_Output{status = .Unknown, sequence_bytes = count}
	}
	return key_output(kind, count)
}

/* decoder_finish emits a lone Escape or clears one incomplete physical sequence. */
decoder_finish :: proc(decoder: ^Decoder) -> Decode_Output {
	assert(decoder != nil)
	if decoder.state == .Ground {
		return Decode_Output{status = .Pending}
	}
	count := decoder.count
	if decoder.state == .Escape && count == 1 {
		decoder_reset(decoder)
		return key_output(.Escape, count)
	}
	decoder_reset(decoder)
	return Decode_Output{status = .Incomplete, sequence_bytes = count}
}

/* decoder_reset discards one pending physical sequence without producing an event. */
decoder_reset :: proc(decoder: ^Decoder) {
	assert(decoder != nil)
	decoder.count = 0
	decoder.expected = 0
	decoder.state = .Ground
}

@(private)
decoder_ground :: proc(decoder: ^Decoder, value: u8) -> Decode_Output {
	switch value {
	case 0x00: return control_key_output(' ')
	case 0x08: return control_key_output('h')
	case 0x09: return key_output(.Tab, 1)
	case 0x7f: return key_output(.Backspace, 1)
	case 0x0a, 0x0d: return key_output(.Enter, 1)
	// Terminals encode C-\\ as the ASCII File Separator byte.
	case 0x1c: return control_key_output('\\')
	case 0x1d: return control_key_output('%')
	// Terminals encode C-/ and C-_ as the same ASCII Unit Separator byte.
	case 0x1f: return control_key_output('/')
	}
	if value >= 0x01 && value <= 0x1a {
		return control_key_output(rune('a' + value - 1))
	}
	if value == 0x1b {
		decoder.bytes[0] = value
		decoder.count = 1
		decoder.state = .Escape
		return Decode_Output{status = .Pending, sequence_bytes = 1}
	}
	if value >= 0x20 && value <= 0x7e {
		decoder.bytes[0] = value
		decoder.count = 1
		decoder.expected = 1
		return decoder_text_event(decoder)
	}
	expected := utf8_sequence_length(value)
	if expected == 0 {
		return Decode_Output{status = .Unsupported, sequence_bytes = 1}
	}
	decoder.bytes[0] = value
	decoder.count = 1
	decoder.expected = expected
	decoder.state = .UTF8
	return Decode_Output{status = .Pending, sequence_bytes = 1}
}

@(private)
decoder_finish_csi :: proc(decoder: ^Decoder, pointer_context: Pointer_Context) -> Decode_Output {
	count := decoder.count
	if count >= 6 && decoder.bytes[2] == '<' &&
	   (decoder.bytes[count - 1] == 'M' || decoder.bytes[count - 1] == 'm') {
		return decoder_finish_pointer(decoder, pointer_context)
	}
	kind := interaction.Logical_Key_Kind.Invalid
	modifiers: interaction.Modifiers
	if count == 3 {
		switch decoder.bytes[2] {
		case 'A': kind = .Up
		case 'B': kind = .Down
		case 'C': kind = .Right
		case 'D': kind = .Left
		case 'H': kind = .Home
		case 'F': kind = .End
		case:    kind = .Invalid
		}
	} else if count == 4 && decoder.bytes[3] == '~' {
		switch decoder.bytes[2] {
		case '1', '7': kind = .Home
		case '2':      kind = .Insert
		case '3':      kind = .Delete
		case '4', '8': kind = .End
		case '5':      kind = .Prior
		case '6':      kind = .Next
		case:         kind = .Invalid
		}
	} else if count == 5 && decoder.bytes[2] == '1' && decoder.bytes[3] == '4' &&
	          decoder.bytes[4] == '~' {
		kind = .F4
	} else if count == 6 && decoder.bytes[2] == '1' && decoder.bytes[3] == ';' &&
	          (decoder.bytes[4] == '2' || decoder.bytes[4] == '5') {
		switch decoder.bytes[5] {
		case 'A': kind = .Up
		case 'B': kind = .Down
		case 'C': kind = .Right
		case 'D': kind = .Left
		case:    kind = .Invalid
		}
		modifiers = {.Shift} if decoder.bytes[4] == '2' else {.Control}
	} else if count == 7 && decoder.bytes[2] == '1' && decoder.bytes[3] == '3' &&
	          decoder.bytes[4] == ';' && decoder.bytes[5] == '5' && decoder.bytes[6] == 'u' {
		kind = .Enter
		modifiers = {.Control}
	}
	decoder_reset(decoder)
	if kind == .Invalid {
		return Decode_Output{status = .Unknown, sequence_bytes = count}
	}
	return modified_key_output(kind, modifiers, count)
}

@(private)
decoder_finish_pointer :: proc(decoder: ^Decoder, ctx: Pointer_Context) -> Decode_Output {
	count := decoder.count
	code, column, row, parsed := decoder_pointer_fields(decoder.bytes[:count])
	if !parsed || !pointer_context_is_valid(ctx) ||
	   decoder.pointer_sequence == interaction.Pointer_Sequence(max(u64)) {
		decoder_reset(decoder)
		return Decode_Output{status = .Malformed, sequence_bytes = count}
	}
	action: interaction.Pointer_Action
	button: interaction.Pointer_Button
	modifiers: interaction.Pointer_Modifiers
	if code & 4 != 0 do modifiers += {.Shift}
	if code & 8 != 0 do modifiers += {.Alt}
	if code & 16 != 0 do modifiers += {.Control}
	motion := code & 32 != 0
	wheel := code & 64 != 0
	button_code := code & 3
	final := decoder.bytes[count - 1]
	if code & ~u32(127) != 0 {
		decoder_reset(decoder)
		return Decode_Output{status = .Unsupported, sequence_bytes = count}
	}
	if wheel {
		if motion || final != 'M' || button_code > 1 {
			decoder_reset(decoder)
			return Decode_Output{status = .Unsupported, sequence_bytes = count}
		}
		action = .Wheel
		button = .Wheel_Up if button_code == 0 else .Wheel_Down
	} else {
		if button_code > 2 {
			decoder_reset(decoder)
			return Decode_Output{status = .Unsupported, sequence_bytes = count}
		}
		switch button_code {
		case 0: button = .Primary
		case 1: button = .Middle
		case 2: button = .Secondary
		}
		if final == 'm' {
			if motion {
				decoder_reset(decoder)
				return Decode_Output{status = .Unsupported, sequence_bytes = count}
			}
			action = .Release
		} else if motion {
			action = .Motion
		} else {
			action = .Press
		}
	}
	sequence := interaction.Pointer_Sequence(u64(decoder.pointer_sequence) + 1)
	event := interaction.Pointer_Event {
		frontend = ctx.frontend,
		source = ctx.source,
		action = action,
		button = button,
		modifiers = modifiers,
		coordinate_space = .Cell,
		row = row - 1,
		column = column - 1,
		root_generation = ctx.root_generation,
		geometry_generation = ctx.geometry_generation,
		sequence = sequence,
		capabilities = ctx.capabilities,
	}
	if !interaction.pointer_event_is_valid(event) {
		decoder_reset(decoder)
		return Decode_Output{status = .Unsupported, sequence_bytes = count}
	}
	decoder.pointer_sequence = sequence
	decoder_reset(decoder)
	return Decode_Output {
		status = .Event,
		input = interaction.Input{kind = .Pointer, pointer = event},
		sequence_bytes = count,
	}
}

@(private)
decoder_pointer_fields :: proc(bytes: []u8) -> (code, column, row: u32, ok: bool) {
	if len(bytes) < 6 || bytes[0] != 0x1b || bytes[1] != '[' || bytes[2] != '<' ||
	   (bytes[len(bytes) - 1] != 'M' && bytes[len(bytes) - 1] != 'm') {
		return 0, 0, 0, false
	}
	values: [3]u32
	value_index: int
	digits: int
	for index in 3 ..< len(bytes) - 1 {
		value := bytes[index]
		if value == ';' {
			if digits == 0 || value_index >= 2 do return 0, 0, 0, false
			value_index += 1
			digits = 0
			continue
		}
		if value < '0' || value > '9' do return 0, 0, 0, false
		digit := u32(value - '0')
		if values[value_index] > (max(u32) - digit) / 10 do return 0, 0, 0, false
		values[value_index] = values[value_index] * 10 + digit
		digits += 1
	}
	if value_index != 2 || digits == 0 || values[1] == 0 || values[2] == 0 ||
	   values[1] - 1 > interaction.MAX_POINTER_COORDINATE ||
	   values[2] - 1 > interaction.MAX_POINTER_COORDINATE {
		return 0, 0, 0, false
	}
	return values[0], values[1], values[2], true
}

@(private)
pointer_context_is_valid :: proc(ctx: Pointer_Context) -> bool {
	return ctx.frontend != interaction.Pointer_Frontend_ID(0) &&
		ctx.source != interaction.Pointer_Source_ID(0) &&
		ctx.root_generation != interaction.Pointer_Root_Generation(0) &&
		ctx.geometry_generation != interaction.Pointer_Geometry_Generation(0) &&
		.Cell_Coordinates in ctx.capabilities
}

@(private)
decoder_text_event :: proc(decoder: ^Decoder) -> Decode_Output {
	count := decoder.count
	decoded, width := utf8.decode_rune(decoder.bytes[:count])
	assert(width == int(count) && decoded >= 0)
	text := string(decoder.bytes[:count])
	input := interaction.Input {
		kind = .Key,
		stroke = interaction.Key_Stroke{kind = .Unicode_Scalar, scalar = decoded},
		text = text,
	}
	decoder_reset(decoder)
	return Decode_Output {
		status = .Event,
		input = input,
		sequence_bytes = count,
	}
}

@(private)
key_output :: proc(kind: interaction.Logical_Key_Kind, count: u8) -> Decode_Output {
	return modified_key_output(kind, {}, count)
}

@(private)
modified_key_output :: proc(
	kind: interaction.Logical_Key_Kind,
	modifiers: interaction.Modifiers,
	count: u8,
) -> Decode_Output {
	return Decode_Output {
		status = .Event,
		input = interaction.Input {
			kind = .Key,
			stroke = interaction.Key_Stroke{kind = kind, modifiers = modifiers},
		},
		sequence_bytes = count,
	}
}

@(private)
control_key_output :: proc(scalar: rune) -> Decode_Output {
	return Decode_Output {
		status = .Event,
		input = interaction.Input {
			kind = .Key,
			stroke = interaction.Key_Stroke {
				kind = .Unicode_Scalar,
				scalar = scalar,
				modifiers = {.Control},
			},
		},
		sequence_bytes = 1,
	}
}

@(private)
control_meta_key_output :: proc(scalar: rune, count: u8) -> Decode_Output {
	return Decode_Output {
		status = .Event,
		input = interaction.Input {
			kind = .Key,
			stroke = interaction.Key_Stroke {
				kind = .Unicode_Scalar,
				scalar = scalar,
				modifiers = {.Control, .Meta},
			},
		},
		sequence_bytes = count,
	}
}

@(private)
meta_key_output :: proc(scalar: rune, count: u8) -> Decode_Output {
	return Decode_Output {
		status = .Event,
		input = interaction.Input {
			kind = .Key,
			stroke = interaction.Key_Stroke {
				kind = .Unicode_Scalar,
				scalar = scalar,
				modifiers = {.Meta},
			},
		},
		sequence_bytes = count,
	}
}

@(private)
utf8_sequence_length :: proc(first: u8) -> u8 {
	if first >= 0xc2 && first <= 0xdf {
		return 2
	}
	if first >= 0xe0 && first <= 0xef {
		return 3
	}
	if first >= 0xf0 && first <= 0xf4 {
		return 4
	}
	return 0
}
