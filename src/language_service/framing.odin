// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language_service

import "base:runtime"
import "core:strings"

/* Framing_State reports one bounded Content-Length decoder disposition. */
Framing_State :: enum u8 {
	Pending_Headers,
	Pending_Body,
	Ready,
	Failed,
	Closed,
}

/* Frame_Decoder owns buffered protocol bytes until frames are copied out. */
Frame_Decoder :: struct {
	state: rawptr,
}

/* Frame owns one copied UTF-8 JSON body until frame_close. */
Frame :: struct {
	body:      []u8,
	allocator: runtime.Allocator,
	closed:    bool,
}

@(private)
Decoder_State :: struct {
	buffer:        [dynamic]u8,
	limits:        Service_Limits,
	state:         Framing_State,
	body_start:    int,
	expected_body: int,
	allocator:     runtime.Allocator,
	failure:       Failure_Context,
}

/* frame_decoder_open creates one empty bounded streaming frame decoder. */
frame_decoder_open :: proc(
	limits := DEFAULT_LIMITS,
	allocator := context.allocator,
) -> (Frame_Decoder, bool, Failure_Context) {
	if allocator.procedure == nil || !service_limits_valid(limits) {
		return {}, false, Failure_Context{code = .Invalid_Input}
	}
	state, state_error := new(Decoder_State, allocator)
	if state_error != nil {
		return {}, false, Failure_Context{code = .Allocation}
	}
	state.buffer, state_error = make([dynamic]u8, 0, int(min(limits.frame_header_bytes, 4 * KIBIBYTE)), allocator)
	if state_error != nil {
		free(state, allocator)
		return {}, false, Failure_Context{code = .Allocation}
	}
	state.limits = limits
	state.state = .Pending_Headers
	state.expected_body = -1
	state.allocator = allocator
	return Frame_Decoder{state = state}, true, {}
}

/* frame_decoder_push copies one input fragment and advances bounded framing. */
frame_decoder_push :: proc(
	decoder: ^Frame_Decoder,
	input: []u8,
) -> (Framing_State, bool, Failure_Context) {
	state := decoder_state(decoder)
	if state == nil || state.state == .Closed {
		return .Closed, false, Failure_Context{code = .Closed}
	}
	if state.state == .Failed do return .Failed, false, state.failure
	if state.state == .Ready && len(input) > 0 {
		return decoder_fail(state, .Protocol, .Stream_Bytes, state.limits.buffered_stream_bytes, u64(len(state.buffer) + len(input)))
	}
	if len(input) > int(state.limits.buffered_stream_bytes) - len(state.buffer) {
		return decoder_fail(state, .Resource_Limit, .Stream_Bytes, state.limits.buffered_stream_bytes, u64(len(state.buffer)) + u64(len(input)))
	}
	if len(input) > 0 {
		_, append_error := append(&state.buffer, ..input)
		if append_error != nil do return decoder_fail(state, .Allocation, .Stream_Bytes, state.limits.buffered_stream_bytes, u64(len(state.buffer) + len(input)))
	}
	return decoder_advance(state)
}

/* frame_decoder_take copies the ready body and advances retained trailing bytes. */
frame_decoder_take :: proc(
	decoder: ^Frame_Decoder,
) -> (Frame, bool, Failure_Context) {
	state := decoder_state(decoder)
	if state == nil || state.state == .Closed {
		return {}, false, Failure_Context{code = .Closed}
	}
	if state.state == .Failed do return {}, false, state.failure
	if state.state != .Ready {
		return {}, false, Failure_Context{code = .Invalid_Input}
	}
	body, allocation_error := make([]u8, state.expected_body, state.allocator)
	if allocation_error != nil {
		return {}, false, Failure_Context{code = .Allocation, resource = .Message_Bytes, actual = u64(state.expected_body)}
	}
	copy(body, state.buffer[state.body_start:state.body_start + state.expected_body])
	consumed := state.body_start + state.expected_body
	remaining := len(state.buffer) - consumed
	if remaining > 0 do copy(state.buffer[:remaining], state.buffer[consumed:])
	if resize_error := resize(&state.buffer, remaining); resize_error != nil {
		delete(body, state.allocator)
		return {}, false, Failure_Context{code = .Allocation}
	}
	state.state = .Pending_Headers
	state.body_start = 0
	state.expected_body = -1
	_, _, _ = decoder_advance(state)
	return Frame{body = body, allocator = state.allocator}, true, {}
}

/* frame_decoder_inspect reports current state, buffered bytes, and expected body. */
frame_decoder_inspect :: proc(decoder: ^Frame_Decoder) -> (Framing_State, u64, u64, Failure_Context) {
	state := decoder_state(decoder)
	if state == nil do return .Closed, 0, 0, Failure_Context{code = .Closed}
	expected := u64(0)
	if state.expected_body >= 0 do expected = u64(state.expected_body)
	return state.state, u64(len(state.buffer)), expected, state.failure
}

/* frame_decoder_close releases all buffered protocol storage exactly once. */
frame_decoder_close :: proc(decoder: ^Frame_Decoder) -> bool {
	state := decoder_state(decoder)
	if state == nil do return false
	allocator := state.allocator
	if state.buffer != nil do delete(state.buffer)
	state^ = Decoder_State{state = .Closed}
	free(state, allocator)
	decoder^ = Frame_Decoder{}
	return true
}

/* frame_close releases one copied frame body exactly once. */
frame_close :: proc(frame: ^Frame) -> bool {
	if frame == nil || frame.closed || frame.allocator.procedure == nil do return false
	if frame.body != nil do delete(frame.body, frame.allocator)
	frame^ = Frame{closed = true}
	return true
}

@(private = "file")
decoder_state :: proc(decoder: ^Frame_Decoder) -> ^Decoder_State {
	if decoder == nil || decoder.state == nil do return nil
	return cast(^Decoder_State)decoder.state
}

@(private = "file")
decoder_advance :: proc(state: ^Decoder_State) -> (Framing_State, bool, Failure_Context) {
	if state.state == .Pending_Headers {
		separator := header_separator(state.buffer[:])
		if separator < 0 {
			if u64(len(state.buffer)) > state.limits.frame_header_bytes {
				return decoder_fail(state, .Resource_Limit, .Frame_Header_Bytes, state.limits.frame_header_bytes, u64(len(state.buffer)))
			}
			return state.state, true, {}
		}
		header_bytes := separator + 4
		if u64(header_bytes) > state.limits.frame_header_bytes {
			return decoder_fail(state, .Resource_Limit, .Frame_Header_Bytes, state.limits.frame_header_bytes, u64(header_bytes))
		}
		content_length, ok := parse_content_length(string(state.buffer[:separator]))
		if !ok {
			return decoder_fail(state, .Framing, .Frame_Header_Bytes, state.limits.frame_header_bytes, u64(header_bytes))
		}
		if content_length > state.limits.message_bytes {
			return decoder_fail(state, .Resource_Limit, .Message_Bytes, state.limits.message_bytes, content_length)
		}
		state.expected_body = int(content_length)
		state.body_start = header_bytes
		state.state = .Pending_Body
	}
	if state.state == .Pending_Body && len(state.buffer) - state.body_start >= state.expected_body {
		state.state = .Ready
	}
	return state.state, true, {}
}

@(private = "file")
decoder_fail :: proc(
	state: ^Decoder_State,
	code: Failure_Code,
	resource: Resource_Kind,
	limit, actual: u64,
) -> (Framing_State, bool, Failure_Context) {
	state.state = .Failed
	state.failure = Failure_Context{code = code, resource = resource, limit = limit, actual = actual}
	return state.state, false, state.failure
}

@(private = "file")
header_separator :: proc(input: []u8) -> int {
	if len(input) < 4 do return -1
	for index in 0 ..< len(input) - 3 {
		if input[index] == '\r' && input[index + 1] == '\n' &&
		   input[index + 2] == '\r' && input[index + 3] == '\n' {
			return index
		}
	}
	return -1
}

@(private = "file")
parse_content_length :: proc(headers: string) -> (u64, bool) {
	found := false
	content_length := u64(0)
	remaining := headers
	for len(remaining) > 0 {
		line_end := strings.index(remaining, "\r\n")
		line := remaining
		if line_end >= 0 {
			line = remaining[:line_end]
			remaining = remaining[line_end + 2:]
		} else {
			remaining = ""
		}
		colon := strings.index_byte(line, ':')
		if colon <= 0 do return 0, false
		name := trim_ascii_space(line[:colon])
		value := trim_ascii_space(line[colon + 1:])
		if strings.equal_fold(name, "Content-Length") {
			if found do return 0, false
			parsed, ok := parse_decimal_u64(value)
			if !ok do return 0, false
			content_length = parsed
			found = true
		}
	}
	return content_length, found
}

@(private = "file")
trim_ascii_space :: proc(value: string) -> string {
	start := 0
	end := len(value)
	for start < end && (value[start] == ' ' || value[start] == '\t') do start += 1
	for end > start && (value[end - 1] == ' ' || value[end - 1] == '\t') do end -= 1
	return value[start:end]
}

@(private = "file")
parse_decimal_u64 :: proc(value: string) -> (u64, bool) {
	if len(value) == 0 do return 0, false
	result := u64(0)
	for character in transmute([]u8)value {
		if character < '0' || character > '9' do return 0, false
		digit := u64(character - '0')
		if result > (max(u64) - digit) / 10 do return 0, false
		result = result * 10 + digit
	}
	return result, true
}
