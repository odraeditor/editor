// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language_service

import "core:testing"

/* Verifies fragmented Content-Length frames are copied and trailing frames retained. */
@(test)
framing_accepts_fragmentation :: proc(t: ^testing.T) {
	decoder, opened, failure := frame_decoder_open()
	testing.expectf(t, opened, "decoder open failed with %v", failure.code)
	defer frame_decoder_close(&decoder)

	first := transmute([]u8)(string("Content-Length: 17\r\n\r\n{\"jsonrpc\":\"2.0\"}"))
	second := transmute([]u8)(string("Content-Length: 17\r\n\r\n{\"jsonrpc\":\"2.0\"}"))
	state, accepted, _ := frame_decoder_push(&decoder, first[:12])
	testing.expect(t, accepted)
	testing.expect_value(t, state, Framing_State.Pending_Headers)
	combined := make([dynamic]u8, 0, len(first) - 12 + len(second))
	defer delete(combined)
	_, _ = append(&combined, ..first[12:])
	_, _ = append(&combined, ..second)
	state, accepted, _ = frame_decoder_push(&decoder, combined[:])
	testing.expect(t, accepted)
	testing.expect_value(t, state, Framing_State.Ready)

	frame, taken, _ := frame_decoder_take(&decoder)
	testing.expect(t, taken)
	testing.expect_value(t, string(frame.body), "{\"jsonrpc\":\"2.0\"}")
	frame_close(&frame)
	state, _, _, _ = frame_decoder_inspect(&decoder)
	testing.expect_value(t, state, Framing_State.Ready)
	frame, taken, _ = frame_decoder_take(&decoder)
	testing.expect(t, taken)
	frame_close(&frame)
}

/* Verifies malformed, duplicate, excessive, and overflowing frame lengths reject. */
@(test)
framing_contains_invalid_headers_and_lengths :: proc(t: ^testing.T) {
	cases := [?]struct {
		name:  string,
		input: string,
	} {
		{name = "non-numeric-length", input = "Content-Length: x\r\n\r\n"},
		{name = "duplicate-length", input = "Content-Length: 1\r\nContent-Length: 1\r\n\r\nx"},
		{name = "overflowing-length", input = "Content-Length: 18446744073709551616\r\n\r\n"},
		{name = "missing-length", input = "Missing: 1\r\n\r\nx"},
	}
	for test_case in cases {
		decoder, opened, _ := frame_decoder_open()
		testing.expectf(t, opened, "%s decoder did not open", test_case.name)
		_, accepted, failure := frame_decoder_push(&decoder, transmute([]u8)test_case.input)
		testing.expectf(t, !accepted, "%s frame was accepted", test_case.name)
		testing.expectf(
			t,
			failure.code == .Framing || failure.code == .Resource_Limit,
			"%s frame returned the wrong failure",
			test_case.name,
		)
		frame_decoder_close(&decoder)
	}
}

/* Verifies strict JSON-RPC envelopes, copied identifiers, and capabilities. */
@(test)
protocol_copies_messages_and_capability_values :: proc(t: ^testing.T) {
	request_text := `{"jsonrpc":"2.0","id":"abc","method":"custom/request","params":{"x":1}}`
	message, decoded, failure := message_decode(transmute([]u8)request_text)
	testing.expectf(t, decoded, "message decode failed with %v", failure.code)
	testing.expect_value(t, message.record.kind, Message_Kind.Request)
	testing.expect_value(t, message.record.id.kind, Request_ID_Kind.Text)
	testing.expect_value(t, unknown_method_action(message.record), Unknown_Method_Action.Reply_Method_Not_Found)
	message_close(&message)

	response_text := `{"jsonrpc":"2.0","id":1,"result":{"capabilities":{"positionEncoding":"utf-8","textDocumentSync":{"change":2},"completionProvider":{"resolveProvider":true,"triggerCharacters":[".","::"]}}}}`
	message, decoded, failure = message_decode(transmute([]u8)response_text)
	testing.expectf(t, decoded, "capability decode failed with %v", failure.code)
	testing.expect_value(t, message.record.kind, Message_Kind.Response)
	testing.expect_value(t, message.record.capabilities.position_encoding, Position_Encoding.UTF_8)
	testing.expect_value(t, message.record.capabilities.synchronization_mode, Synchronization_Mode.Incremental)
	testing.expect(t, .Incremental_Synchronization in message.record.capabilities.capabilities)
	testing.expect(t, .Completion in message.record.capabilities.capabilities)
	testing.expect(t, message.record.capabilities.completion.available)
	testing.expect(t, message.record.capabilities.completion.resolve)
	testing.expect_value(t, message.record.capabilities.completion.trigger_count, u8(2))
	message_close(&message)
}

/* Verifies malformed JSON, invalid envelopes, and excessive depth are contained. */
@(test)
rejects_malformed_and_excessive_messages :: proc(t: ^testing.T) {
	cases := [?]struct {
		name:  string,
		input: string,
	} {
		{name = "wrong-version", input = `{"jsonrpc":"1.0","id":1,"result":null}`},
		{name = "non-string-method", input = `{"jsonrpc":"2.0","id":1,"method":3}`},
		{name = "result-and-error", input = `{"jsonrpc":"2.0","id":1,"result":null,"error":{}}`},
		{name = "truncated-object", input = `{"jsonrpc":"2.0",`},
	}
	for test_case in cases {
		_, decoded, _ := message_decode(transmute([]u8)test_case.input)
		testing.expectf(t, !decoded, "%s message was decoded", test_case.name)
	}
	deep := make([dynamic]u8)
	defer delete(deep)
	for _ in 0 ..< int(DEFAULT_LIMITS.json_depth + 1) do append(&deep, '[')
	for _ in 0 ..< int(DEFAULT_LIMITS.json_depth + 1) do append(&deep, ']')
	_, decoded, failure := message_decode(deep[:])
	testing.expect(t, !decoded)
	testing.expect_value(t, failure.code, Failure_Code.Malformed_JSON)
}

/* Verifies UTF-8 byte offsets round-trip through all negotiated position units. */
@(test)
position_conversion_is_revision_text_bound :: proc(t: ^testing.T) {
	text := "a🙂界\nz"
	cases := [?]struct {
		name:      string,
		encoding:  Position_Encoding,
		character: u32,
	} {
		{name = "utf-8", encoding = .UTF_8, character = 5},
		{name = "utf-16", encoding = .UTF_16, character = 3},
		{name = "utf-32", encoding = .UTF_32, character = 2},
	}
	for item in cases {
		offset, converted, _ := position_to_byte_offset(
			text,
			LSP_Position{line = 0, character = item.character},
			item.encoding,
		)
		testing.expectf(t, converted, "%s position did not convert", item.name)
		testing.expectf(t, offset == 5, "%s position converted to the wrong byte", item.name)
		position, reversed, _ := byte_offset_to_position(text, offset, item.encoding)
		testing.expectf(t, reversed, "%s byte offset did not convert", item.name)
		testing.expectf(
			t,
			position == LSP_Position{line = 0, character = item.character},
			"%s byte offset converted to the wrong position",
			item.name,
		)
	}
	_, converted, _ := position_to_byte_offset(text, LSP_Position{line = 0, character = 2}, .UTF_16)
	testing.expect(t, !converted)
	_, converted, _ = byte_offset_to_position(text, 2, .UTF_16)
	testing.expect(t, !converted)
}
