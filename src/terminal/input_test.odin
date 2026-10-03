// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package terminal_frontend

import "../interaction"
import "core:testing"

/* Verifies physical controls and printable UTF-8 normalize to logical input. */
@(test)
terminal_decoder_normalizes_supported_input :: proc(t: ^testing.T) {
	cases := [?]struct {
		name:      string,
		bytes:     string,
		kind:      interaction.Logical_Key_Kind,
		scalar:    rune,
		modifiers: interaction.Modifiers,
		text:      string,
	}{
		{name = "left", bytes = "\x1b[D", kind = .Left},
		{name = "right", bytes = "\x1b[C", kind = .Right},
		{name = "up", bytes = "\x1b[A", kind = .Up},
		{name = "down", bytes = "\x1b[B", kind = .Down},
		{name = "shift-left", bytes = "\x1b[1;2D", kind = .Left, modifiers = {.Shift}},
		{name = "shift-right", bytes = "\x1b[1;2C", kind = .Right, modifiers = {.Shift}},
		{name = "control-left", bytes = "\x1b[1;5D", kind = .Left, modifiers = {.Control}},
		{name = "control-right", bytes = "\x1b[1;5C", kind = .Right, modifiers = {.Control}},
		{name = "control-up", bytes = "\x1b[1;5A", kind = .Up, modifiers = {.Control}},
		{name = "control-down", bytes = "\x1b[1;5B", kind = .Down, modifiers = {.Control}},
		{name = "control-enter-csi-u", bytes = "\x1b[13;5u", kind = .Enter, modifiers = {.Control}},
		{name = "home-csi", bytes = "\x1b[H", kind = .Home},
		{name = "end-csi", bytes = "\x1b[4~", kind = .End},
		{name = "home-ss3", bytes = "\x1bOH", kind = .Home},
		{name = "end-ss3", bytes = "\x1bOF", kind = .End},
		{name = "f4-ss3", bytes = "\x1bOS", kind = .F4},
		{name = "f4-csi", bytes = "\x1b[14~", kind = .F4},
		{name = "delete", bytes = "\x1b[3~", kind = .Delete},
		{name = "insert", bytes = "\x1b[2~", kind = .Insert},
		{name = "page-up", bytes = "\x1b[5~", kind = .Prior},
		{name = "page-down", bytes = "\x1b[6~", kind = .Next},
		{name = "control-h", bytes = "\x08", kind = .Unicode_Scalar, scalar = 'h', modifiers = {.Control}},
		{name = "backspace", bytes = "\x7f", kind = .Backspace},
		{name = "tab", bytes = "\x09", kind = .Tab},
		{name = "carriage-return", bytes = "\r", kind = .Enter},
		{name = "line-feed", bytes = "\n", kind = .Enter},
		{name = "control-space", bytes = "\x00", kind = .Unicode_Scalar, scalar = ' ', modifiers = {.Control}},
		{name = "control-c", bytes = "\x03", kind = .Unicode_Scalar, scalar = 'c', modifiers = {.Control}},
		{name = "control-g", bytes = "\x07", kind = .Unicode_Scalar, scalar = 'g', modifiers = {.Control}},
		{name = "control-s", bytes = "\x13", kind = .Unicode_Scalar, scalar = 's', modifiers = {.Control}},
		{name = "control-x", bytes = "\x18", kind = .Unicode_Scalar, scalar = 'x', modifiers = {.Control}},
		{name = "control-backslash", bytes = "\x1c", kind = .Unicode_Scalar, scalar = '\\', modifiers = {.Control}},
		{name = "control-right-bracket", bytes = "\x1d", kind = .Unicode_Scalar, scalar = '%', modifiers = {.Control}},
		{name = "control-underscore", bytes = "\x1f", kind = .Unicode_Scalar, scalar = '/', modifiers = {.Control}},
		{name = "control-meta-r", bytes = "\x1b\x12", kind = .Unicode_Scalar, scalar = 'r', modifiers = {.Control, .Meta}},
		{name = "control-meta-s", bytes = "\x1b\x13", kind = .Unicode_Scalar, scalar = 's', modifiers = {.Control, .Meta}},
		{name = "control-meta-percent", bytes = "\x1b\x1d", kind = .Unicode_Scalar, scalar = '%', modifiers = {.Control, .Meta}},
		{name = "control-meta-space", bytes = "\x1b\x00", kind = .Unicode_Scalar, scalar = ' ', modifiers = {.Control, .Meta}},
		{name = "meta-w", bytes = "\x1bw", kind = .Unicode_Scalar, scalar = 'w', modifiers = {.Meta}},
		{name = "ascii-text", bytes = "q", kind = .Unicode_Scalar, scalar = 'q', text = "q"},
		{name = "accented-text", bytes = "é", kind = .Unicode_Scalar, scalar = 'é', text = "é"},
		{name = "emoji-text", bytes = "🙂", kind = .Unicode_Scalar, scalar = '🙂', text = "🙂"},
	}
	for fixture in cases {
		decoder: Decoder
		output: Decode_Output
		for index in 0 ..< len(fixture.bytes) {
			output = decoder_push(&decoder, fixture.bytes[index])
		}
		testing.expectf(t, output.status == .Event, "%s did not emit an event", fixture.name)
		testing.expectf(t, output.input.kind == .Key, "%s did not emit a key", fixture.name)
		testing.expectf(t, output.input.stroke.kind == fixture.kind, "%s decoded the wrong key kind", fixture.name)
		testing.expectf(t, output.input.stroke.scalar == fixture.scalar, "%s decoded the wrong scalar", fixture.name)
		testing.expectf(t, output.input.stroke.modifiers == fixture.modifiers, "%s decoded the wrong modifiers", fixture.name)
		testing.expectf(t, output.input.text == fixture.text, "%s decoded the wrong text", fixture.name)
	}
}

/* Verifies invalid physical input is bounded, classified, and resets cleanly. */
@(test)
terminal_decoder_rejects_invalid_sequences :: proc(t: ^testing.T) {
	decoder: Decoder
	unsupported := decoder_push(&decoder, 0x1e)
	testing.expect_value(t, unsupported.status, Decode_Status.Unsupported)
	decoder_push(&decoder, 0x1b)
	unknown := decoder_push(&decoder, 0x1e)
	testing.expect_value(t, unknown.status, Decode_Status.Unknown)
	decoder_push(&decoder, 0xf0)
	malformed := decoder_push(&decoder, 'x')
	testing.expect_value(t, malformed.status, Decode_Status.Malformed)
	decoder_push(&decoder, 0x1b)
	decoder_push(&decoder, '[')
	for _ in 0 ..< int(MAX_INPUT_SEQUENCE_BYTES - 2) {
		decoder_push(&decoder, '1')
	}
	oversized := decoder_push(&decoder, '1')
	testing.expect_value(t, oversized.status, Decode_Status.Oversized)
	decoder_push(&decoder, 0xe2)
	incomplete := decoder_finish(&decoder)
	testing.expect_value(t, incomplete.status, Decode_Status.Incomplete)
	escape_pending := decoder_push(&decoder, 0x1b)
	testing.expect_value(t, escape_pending.status, Decode_Status.Pending)
	escape := decoder_finish(&decoder)
	testing.expect_value(t, escape.status, Decode_Status.Event)
	testing.expect_value(t, escape.input.stroke.kind, interaction.Logical_Key_Kind.Escape)
	recovered := decoder_push(&decoder, 'z')
	testing.expect_value(t, recovered.input.stroke.kind, interaction.Logical_Key_Kind.Unicode_Scalar)
	testing.expect_value(t, recovered.input.text, "z")
}

/* Verifies decoding is allocation-free even when both context allocators fail. */
@(test)
terminal_decoder_does_not_depend_on_allocation :: proc(t: ^testing.T) {
	previous_allocator := context.allocator
	previous_temp_allocator := context.temp_allocator
	context.allocator = {}
	context.temp_allocator = {}
	defer {
		context.allocator = previous_allocator
		context.temp_allocator = previous_temp_allocator
	}
	decoder: Decoder
	text := "界"
	for index in 0 ..< len(text) {
		output := decoder_push(&decoder, text[index])
		if output.status == .Event {
			testing.expect_value(t, output.input.stroke.kind, interaction.Logical_Key_Kind.Unicode_Scalar)
			testing.expect_value(t, output.input.text, "界")
		}
	}
}

/* Verifies SGR pointer sequences normalize actions, coordinates, and modifiers. */
@(test)
terminal_decoder_normalizes_sgr_pointer_input :: proc(t: ^testing.T) {
	cases := [?]struct {
		name:      string,
		bytes:     string,
		action:    interaction.Pointer_Action,
		button:    interaction.Pointer_Button,
		row:       u32,
		column:    u32,
		modifiers: interaction.Pointer_Modifiers,
	}{
		{name = "primary-press", bytes = "\x1b[<0;1;1M", action = .Press, button = .Primary},
		{name = "middle-release", bytes = "\x1b[<1;2;3m", action = .Release, button = .Middle, row = 2, column = 1},
		{name = "secondary-press", bytes = "\x1b[<2;80;24M", action = .Press, button = .Secondary, row = 23, column = 79},
		{name = "primary-drag", bytes = "\x1b[<32;17;9M", action = .Motion, button = .Primary, row = 8, column = 16},
		{name = "modified-press", bytes = "\x1b[<28;4;5M", action = .Press, button = .Primary, row = 4, column = 3, modifiers = {.Shift, .Alt, .Control}},
		{name = "wheel-up", bytes = "\x1b[<64;7;8M", action = .Wheel, button = .Wheel_Up, row = 7, column = 6},
		{name = "wheel-down", bytes = "\x1b[<65;7;8M", action = .Wheel, button = .Wheel_Down, row = 7, column = 6},
	}
	for fixture in cases {
		decoder: Decoder
		output := terminal_decoder_push_bytes(&decoder, fixture.bytes, terminal_pointer_test_context())
		testing.expectf(t, output.status == .Event, "%s did not emit an event", fixture.name)
		testing.expect_value(t, output.input.kind, interaction.Input_Kind.Pointer)
		testing.expect_value(t, output.input.pointer.action, fixture.action)
		testing.expect_value(t, output.input.pointer.button, fixture.button)
		testing.expect_value(t, output.input.pointer.row, fixture.row)
		testing.expect_value(t, output.input.pointer.column, fixture.column)
		testing.expect_value(t, output.input.pointer.modifiers, fixture.modifiers)
		testing.expect_value(t, output.input.pointer.root_generation, interaction.Pointer_Root_Generation(11))
		testing.expect_value(t, output.input.pointer.geometry_generation, interaction.Pointer_Geometry_Generation(12))
		testing.expect_value(t, output.input.pointer.sequence, interaction.Pointer_Sequence(1))
	}
}

/* Verifies SGR pointer sequencing persists while ordinary decoder state resets. */
@(test)
terminal_decoder_orders_pointer_events :: proc(t: ^testing.T) {
	decoder: Decoder
	ctx := terminal_pointer_test_context()
	press := terminal_decoder_push_bytes(&decoder, "\x1b[<0;4;5M", ctx)
	motion := terminal_decoder_push_bytes(&decoder, "\x1b[<32;5;5M", ctx)
	release := terminal_decoder_push_bytes(&decoder, "\x1b[<0;5;5m", ctx)
	testing.expect_value(t, press.input.pointer.sequence, interaction.Pointer_Sequence(1))
	testing.expect_value(t, motion.input.pointer.sequence, interaction.Pointer_Sequence(2))
	testing.expect_value(t, release.input.pointer.sequence, interaction.Pointer_Sequence(3))
	testing.expect(t, interaction.pointer_event_follows(press.input.pointer, motion.input.pointer))
	testing.expect(t, interaction.pointer_event_follows(motion.input.pointer, release.input.pointer))
}

/* Verifies malformed, unsupported, and unbound pointer sequences are contained. */
@(test)
terminal_decoder_rejects_invalid_pointer_input :: proc(t: ^testing.T) {
	cases := [?]struct {
		name:    string,
		bytes:   string,
		ctx:     Pointer_Context,
		status:  Decode_Status,
	}{
		{name = "missing-context", bytes = "\x1b[<0;1;1M", status = .Malformed},
		{name = "zero-column", bytes = "\x1b[<0;0;1M", ctx = terminal_pointer_test_context(), status = .Malformed},
		{name = "zero-row", bytes = "\x1b[<0;1;0M", ctx = terminal_pointer_test_context(), status = .Malformed},
		{name = "missing-field", bytes = "\x1b[<0;1M", ctx = terminal_pointer_test_context(), status = .Malformed},
		{name = "extra-field", bytes = "\x1b[<0;1;1;1M", ctx = terminal_pointer_test_context(), status = .Malformed},
		{name = "coordinate-limit", bytes = "\x1b[<0;1048577;1M", ctx = terminal_pointer_test_context(), status = .Malformed},
		{name = "no-button-motion", bytes = "\x1b[<35;1;1M", ctx = terminal_pointer_test_context(), status = .Unsupported},
		{name = "extended-button", bytes = "\x1b[<128;1;1M", ctx = terminal_pointer_test_context(), status = .Unsupported},
	}
	for fixture in cases {
		decoder: Decoder
		output := terminal_decoder_push_bytes(&decoder, fixture.bytes, fixture.ctx)
		testing.expectf(t, output.status == fixture.status, "%s returned %v", fixture.name, output.status)
	}

	decoder: Decoder
	limited := terminal_pointer_test_context()
	limited.capabilities -= {.Motion}
	output := terminal_decoder_push_bytes(&decoder, "\x1b[<32;1;1M", limited)
	testing.expect_value(t, output.status, Decode_Status.Unsupported)
}

@(private)
terminal_pointer_test_context :: proc() -> Pointer_Context {
	return Pointer_Context {
		frontend = 9,
		source = 10,
		root_generation = 11,
		geometry_generation = 12,
		capabilities = {
			.Press,
			.Release,
			.Motion,
			.Wheel,
			.Modifiers,
			.Cell_Coordinates,
		},
	}
}

@(private)
terminal_decoder_push_bytes :: proc(
	decoder: ^Decoder,
	bytes: string,
	ctx: Pointer_Context,
) -> (output: Decode_Output) {
	for index in 0 ..< len(bytes) {
		output = decoder_push(decoder, bytes[index], ctx)
	}
	return
}
