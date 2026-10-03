// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package terminal_frontend

import "core:encoding/base64"
import "core:os"
import "core:path/filepath"
import "core:time"
import "core:unicode/utf8"

@(private)
OSC52_BODY_LIMIT_BYTES :: u64(256 * 1024)
@(private)
OSC52_BODY_PREFIX :: "52;c;"
@(private)
OSC52_FRAME_PREFIX :: "\x1b]52;c;"
@(private)
OSC52_TERMINATOR :: byte(0x07)

@(private)
Clipboard_State :: struct {
	config:               Clipboard_Config,
	transport:            Clipboard_Transport,
	next_token:           Clipboard_Change_Token,
	completed_reads:      u64,
	completed_writes:     u64,
	temporary_bytes:      u64,
	peak_temporary_bytes: u64,
}

/* clipboard_environment_detect returns only capability-relevant process observations. */
clipboard_environment_detect :: proc() -> Clipboard_Environment {
	return Clipboard_Environment {
		remote = clipboard_env_present("SSH_CONNECTION") || clipboard_env_present("SSH_TTY"),
		herdr = (clipboard_env_present("HERDR_PANE_ID") && clipboard_env_present("HERDR_SOCKET_PATH")) ||
			clipboard_process_ancestor_present("herdr"),
		nested_tmux = clipboard_env_present("TMUX"),
		nested_zellij = clipboard_env_present("ZELLIJ"),
		graphical_session = clipboard_env_present("WAYLAND_DISPLAY") || clipboard_env_present("DISPLAY"),
	}
}

@(private)
clipboard_process_ancestor_present :: proc(executable_name: string) -> bool {
	pid := os.get_ppid()
	for _ in 0 ..< 8 {
		if pid <= 1 {
			return false
		}
		info, info_error := os.process_info_by_pid(
			pid,
			{.Executable_Path, .PPid},
			context.temp_allocator,
		)
		has_path := .Executable_Path in info.fields
		has_parent := .PPid in info.fields
		matched := has_path && filepath.base(info.executable_path) == executable_name
		parent_pid := info.ppid
		os.free_process_info(info, context.temp_allocator)
		if matched {
			return true
		}
		if info_error != nil || !has_parent || parent_pid <= 1 || parent_pid == pid {
			return false
		}
		pid = parent_pid
	}
	return false
}

/* clipboard_osc52_transport admits direct Herdr export and never claims a query path. */
clipboard_osc52_transport :: proc(
	session: ^Session,
	environment: Clipboard_Environment,
) -> Clipboard_Transport {
	write_capable := session_is_live(session) && environment.herdr &&
		!environment.nested_tmux && !environment.nested_zellij
	return Clipboard_Transport {
		user_data = rawptr(session),
		capabilities = Clipboard_Capabilities {
			read = false,
			write = write_capable,
			presentation = write_capable ? .Outer_Terminal_Client : .Unavailable,
		},
		write = write_capable ? clipboard_osc52_session_write : nil,
	}
}

/* clipboard_adapter_init owns policy and transport lifecycle without owning editor state. */
clipboard_adapter_init :: proc(
	adapter: ^Clipboard_Adapter,
	config: Clipboard_Config,
	transport: Clipboard_Transport,
) -> (ok: bool, failure: Clipboard_Failure_Context) {
	if adapter == nil || adapter.state != nil || adapter.closed {
		return false, Clipboard_Failure_Context{code = .Invalid_Adapter}
	}
	if !clipboard_config_valid(config) || !clipboard_transport_valid(transport) {
		return false, Clipboard_Failure_Context{code = .Invalid_Config}
	}
	state, allocation_error := new(Clipboard_State, config.persistent_allocator)
	if allocation_error != nil {
		return false, Clipboard_Failure_Context {
			code = .Persistent_Memory_Limit,
			actual = u64(size_of(Clipboard_State)),
		}
	}
	state.config = config
	state.transport = transport
	state.next_token = Clipboard_Change_Token(1)
	adapter.state = state
	return true, {}
}

/* clipboard_capabilities reports immutable independently negotiated capabilities. */
clipboard_capabilities :: proc(
	adapter: ^Clipboard_Adapter,
) -> (capabilities: Clipboard_Capabilities, ok: bool, failure: Clipboard_Failure_Context) {
	state := clipboard_state(adapter)
	if state == nil {
		return {}, false, Clipboard_Failure_Context{code = .Invalid_Adapter}
	}
	return state.transport.capabilities, true, {}
}

/* clipboard_stats reports exact adapter storage and completed synchronous work. */
clipboard_stats :: proc(
	adapter: ^Clipboard_Adapter,
) -> (stats: Clipboard_Stats, ok: bool, failure: Clipboard_Failure_Context) {
	state := clipboard_state(adapter)
	if state == nil {
		return {}, false, Clipboard_Failure_Context{code = .Invalid_Adapter}
	}
	return Clipboard_Stats {
		capabilities = state.transport.capabilities,
		next_token = state.next_token,
		completed_reads = state.completed_reads,
		completed_writes = state.completed_writes,
		retained_bytes = u64(size_of(Clipboard_State)),
		temporary_bytes = state.temporary_bytes,
		peak_temporary_bytes = state.peak_temporary_bytes,
	}, true, {}
}

/* clipboard_write copies, validates, frames, and exports one complete UTF-8 value. */
clipboard_write :: proc(
	adapter: ^Clipboard_Adapter,
	request: Clipboard_Write_Request,
) -> (result: Clipboard_Write_Result, ok: bool, failure: Clipboard_Failure_Context) {
	state := clipboard_state(adapter)
	if state == nil {
		return {}, false, Clipboard_Failure_Context{code = .Invalid_Adapter}
	}
	if !state.transport.capabilities.write || state.transport.write == nil {
		return {}, false, Clipboard_Failure_Context{code = .Write_Unavailable}
	}
	if len(request.text) == 0 {
		return {}, false, Clipboard_Failure_Context{code = .Empty_Text}
	}
	if !utf8.valid_string(request.text) {
		return {}, false, Clipboard_Failure_Context{code = .Invalid_UTF8}
	}
	text_bytes := u64(len(request.text))
	if text_bytes > state.config.max_text_bytes {
		return {}, false, clipboard_limit_failure(.Text_Limit, state.config.max_text_bytes, text_bytes)
	}
	if state.next_token == Clipboard_Change_Token(0) {
		return {}, false, Clipboard_Failure_Context{code = .Token_Exhausted}
	}
	started := time.tick_now()
	if clipboard_cancelled(request.cancellation) {
		return {}, false, Clipboard_Failure_Context{code = .Cancelled}
	}

	text_copy, copied, copy_failure := clipboard_copy_text(state, request.text, request.cancellation, started)
	if !copied {
		return {}, false, copy_failure
	}
	defer clipboard_temporary_delete(state, text_copy)
	frame, framed, frame_failure := clipboard_frame(state, text_copy, request.cancellation, started)
	if !framed {
		return {}, false, frame_failure
	}
	defer clipboard_temporary_delete(state, frame)
	remaining, remaining_ok := clipboard_remaining_milliseconds(state, started)
	if !remaining_ok {
		return {}, false, Clipboard_Failure_Context{code = .Timed_Out}
	}
	bytes_done, written, write_failure := state.transport.write(
		state.transport.user_data,
		frame,
		remaining,
		state.config.cancellation_bytes,
		request.cancellation,
	)
	if !written {
		write_failure.bytes_done = bytes_done
		if write_failure.code == .None {
			write_failure.code = .Write_Failed
		}
		return {}, false, write_failure
	}
	if _, within_time := clipboard_remaining_milliseconds(state, started); !within_time {
		return {}, false, Clipboard_Failure_Context {
			code = .Timed_Out,
			bytes_done = bytes_done,
		}
	}
	if bytes_done != u64(len(frame)) {
		return {}, false, Clipboard_Failure_Context {
			code = .Partial_Response,
			limit = u64(len(frame)),
			actual = bytes_done,
			bytes_done = bytes_done,
		}
	}
	result = Clipboard_Write_Result{token = state.next_token, bytes = text_bytes}
	state.completed_writes += 1
	if state.next_token == Clipboard_Change_Token(max(u64)) {
		state.next_token = Clipboard_Change_Token(0)
	} else {
		state.next_token = Clipboard_Change_Token(u64(state.next_token) + 1)
	}
	return result, true, {}
}

/* clipboard_read requests, validates, and copies one complete external UTF-8 value. */
clipboard_read :: proc(
	adapter: ^Clipboard_Adapter,
	request: Clipboard_Read_Request,
) -> (result: Clipboard_Read_Result, ok: bool, failure: Clipboard_Failure_Context) {
	state := clipboard_state(adapter)
	if state == nil {
		return {}, false, Clipboard_Failure_Context{code = .Invalid_Adapter}
	}
	if !state.transport.capabilities.read || state.transport.read == nil {
		return {}, false, Clipboard_Failure_Context{code = .Read_Unavailable}
	}
	if request.result_allocator.procedure == nil {
		return {}, false, Clipboard_Failure_Context{code = .Invalid_Config}
	}
	if clipboard_cancelled(request.cancellation) {
		return {}, false, Clipboard_Failure_Context{code = .Cancelled}
	}
	started := time.tick_now()
	response, read_ok, read_failure := state.transport.read(
		state.transport.user_data,
		state.config.timeout_milliseconds,
		request.cancellation,
	)
	if !read_ok {
		if read_failure.code == .None {
			read_failure.code = .Read_Failed
		}
		return {}, false, read_failure
	}
	if _, within_time := clipboard_remaining_milliseconds(state, started); !within_time {
		return {}, false, Clipboard_Failure_Context{code = .Timed_Out}
	}
	if !response.complete || response.reported_bytes != u64(len(response.text)) {
		return {}, false, Clipboard_Failure_Context {
			code = .Partial_Response,
			limit = response.reported_bytes,
			actual = u64(len(response.text)),
		}
	}
	if response.token == Clipboard_Change_Token(0) {
		return {}, false, Clipboard_Failure_Context{code = .Read_Failed}
	}
	if u64(len(response.text)) > state.config.max_text_bytes {
		return {}, false, clipboard_limit_failure(
			.Text_Limit,
			state.config.max_text_bytes,
			u64(len(response.text)),
		)
	}
	if !utf8.valid_string(string(response.text)) {
		return {}, false, Clipboard_Failure_Context{code = .Invalid_UTF8}
	}
	copy_bytes, allocation_error := make([]byte, len(response.text), request.result_allocator)
	if allocation_error != nil {
		return {}, false, Clipboard_Failure_Context {
			code = .Temporary_Memory_Limit,
			actual = u64(len(response.text)),
		}
	}
	copy(copy_bytes, response.text)
	state.completed_reads += 1
	return Clipboard_Read_Result {
		text = string(copy_bytes),
		token = response.token,
		allocator = request.result_allocator,
	}, true, {}
}

/* clipboard_read_result_close releases one copied result without consulting adapter state. */
clipboard_read_result_close :: proc(result: ^Clipboard_Read_Result) {
	if result == nil {
		return
	}
	if len(result.text) > 0 && result.allocator.procedure != nil {
		delete(transmute([]byte)result.text, result.allocator)
	}
	result^ = {}
}

/* clipboard_adapter_close releases transport resources and retained adapter state exactly once. */
clipboard_adapter_close :: proc(
	adapter: ^Clipboard_Adapter,
) -> (ok: bool, failure: Clipboard_Failure_Context) {
	state := clipboard_state(adapter)
	if state == nil || state.temporary_bytes != 0 {
		return false, Clipboard_Failure_Context{code = .Invalid_Adapter, actual = state == nil ? 0 : state.temporary_bytes}
	}
	if state.transport.close != nil {
		closed, close_failure := state.transport.close(state.transport.user_data)
		if !closed {
			if close_failure.code == .None {
				close_failure.code = .Transport_Restore_Failed
			}
			return false, close_failure
		}
	}
	allocator := state.config.persistent_allocator
	free(state, allocator)
	adapter.state = nil
	adapter.closed = true
	return true, {}
}

@(private)
clipboard_state :: proc(adapter: ^Clipboard_Adapter) -> ^Clipboard_State {
	if adapter == nil || adapter.state == nil || adapter.closed {
		return nil
	}
	return (^Clipboard_State)(adapter.state)
}

@(private)
clipboard_config_valid :: proc(config: Clipboard_Config) -> bool {
	if config.persistent_allocator.procedure == nil || config.temporary_allocator.procedure == nil ||
	   config.max_text_bytes == 0 || config.max_text_bytes > MAX_CLIPBOARD_TEXT_BYTES ||
	   config.timeout_milliseconds < MIN_CLIPBOARD_TIMEOUT_MILLISECONDS ||
	   config.timeout_milliseconds > MAX_CLIPBOARD_TIMEOUT_MILLISECONDS ||
	   config.cancellation_bytes < DEFAULT_CLIPBOARD_CANCELLATION_BYTES ||
	   config.cancellation_bytes > MAX_CLIPBOARD_CANCELLATION_BYTES {
		return false
	}
	encoded := 4 * ((config.max_text_bytes + 2) / 3)
	frame_bytes := u64(len(OSC52_FRAME_PREFIX)) + encoded + 1
	return u64(len(OSC52_BODY_PREFIX)) + encoded <= OSC52_BODY_LIMIT_BYTES &&
		config.max_text_bytes + frame_bytes <= config.max_temporary_bytes
}

@(private)
clipboard_transport_valid :: proc(transport: Clipboard_Transport) -> bool {
	if transport.capabilities.read && transport.read == nil {
		return false
	}
	if transport.capabilities.write && transport.write == nil {
		return false
	}
	if (transport.capabilities.read || transport.capabilities.write) && transport.user_data == nil {
		return false
	}
	if transport.capabilities.presentation == .Unavailable &&
	   (transport.capabilities.read || transport.capabilities.write) {
		return false
	}
	return true
}

@(private)
clipboard_env_present :: proc(name: string) -> bool {
	buffer: [1024]u8
	value, _ := os.lookup_env(buffer[:], name)
	return len(value) > 0
}

@(private)
clipboard_cancelled :: proc(cancellation: Clipboard_Cancellation) -> bool {
	return cancellation.check != nil && cancellation.check(cancellation.user_data)
}

@(private)
clipboard_copy_text :: proc(
	state: ^Clipboard_State,
	text: string,
	cancellation: Clipboard_Cancellation,
	started: time.Tick,
) -> (copied: []byte, ok: bool, failure: Clipboard_Failure_Context) {
	storage, allocated := clipboard_temporary_make(state, u64(len(text)))
	if !allocated {
		return nil, false, clipboard_limit_failure(.Temporary_Memory_Limit, state.config.max_temporary_bytes, u64(len(text)))
	}
	copied = storage
	offset := 0
	for offset < len(text) {
		if clipboard_cancelled(cancellation) {
			clipboard_temporary_delete(state, copied)
			return nil, false, Clipboard_Failure_Context{code = .Cancelled}
		}
		if _, within_time := clipboard_remaining_milliseconds(state, started); !within_time {
			clipboard_temporary_delete(state, copied)
			return nil, false, Clipboard_Failure_Context{code = .Timed_Out}
		}
		end := min(len(text), offset + int(state.config.cancellation_bytes))
		copy(copied[offset:end], text[offset:end])
		offset = end
	}
	return copied, true, {}
}

@(private)
clipboard_frame :: proc(
	state: ^Clipboard_State,
	text: []byte,
	cancellation: Clipboard_Cancellation,
	started: time.Tick,
) -> (frame: []byte, ok: bool, failure: Clipboard_Failure_Context) {
	encoded_bytes := 4 * ((len(text) + 2) / 3)
	frame_bytes := len(OSC52_FRAME_PREFIX) + encoded_bytes + 1
	storage, allocated := clipboard_temporary_make(state, u64(frame_bytes))
	if !allocated {
		return nil, false, clipboard_limit_failure(.Temporary_Memory_Limit, state.config.max_temporary_bytes, u64(frame_bytes))
	}
	frame = storage
	copy(frame, OSC52_FRAME_PREFIX)
	source_offset := 0
	encoded_offset := len(OSC52_FRAME_PREFIX)
	for source_offset < len(text) {
		if clipboard_cancelled(cancellation) {
			clipboard_temporary_delete(state, frame)
			return nil, false, Clipboard_Failure_Context{code = .Cancelled}
		}
		if _, within_time := clipboard_remaining_milliseconds(state, started); !within_time {
			clipboard_temporary_delete(state, frame)
			return nil, false, Clipboard_Failure_Context{code = .Timed_Out}
		}
		remaining := len(text) - source_offset
		chunk_bytes := min(remaining, int(state.config.cancellation_bytes))
		if chunk_bytes < remaining {
			chunk_bytes -= chunk_bytes % 3
		}
		chunk := text[source_offset:source_offset + chunk_bytes]
		encoded_chunk_bytes := base64.encoded_len(chunk)
		_, encoding_error := base64.encode_into_buf(
			frame[encoded_offset:encoded_offset + encoded_chunk_bytes],
			chunk,
		)
		if encoding_error != nil {
			clipboard_temporary_delete(state, frame)
			return nil, false, Clipboard_Failure_Context{code = .Write_Failed}
		}
		source_offset += chunk_bytes
		encoded_offset += encoded_chunk_bytes
	}
	frame[encoded_offset] = OSC52_TERMINATOR
	return frame[:encoded_offset + 1], true, {}
}

@(private)
clipboard_temporary_make :: proc(state: ^Clipboard_State, size: u64) -> ([]byte, bool) {
	if size > state.config.max_temporary_bytes - state.temporary_bytes || size > u64(max(int)) {
		return nil, false
	}
	storage, allocation_error := make([]byte, int(size), state.config.temporary_allocator)
	if allocation_error != nil {
		return nil, false
	}
	state.temporary_bytes += size
	state.peak_temporary_bytes = max(state.peak_temporary_bytes, state.temporary_bytes)
	return storage, true
}

@(private)
clipboard_temporary_delete :: proc(state: ^Clipboard_State, storage: []byte) {
	assert(state != nil && u64(len(storage)) <= state.temporary_bytes)
	state.temporary_bytes -= u64(len(storage))
	delete(storage, state.config.temporary_allocator)
}

@(private)
clipboard_remaining_milliseconds :: proc(state: ^Clipboard_State, started: time.Tick) -> (u32, bool) {
	elapsed_ns := time.duration_nanoseconds(time.tick_since(started))
	if elapsed_ns < 0 {
		return 0, false
	}
	elapsed_ms := u64(elapsed_ns) / 1_000_000
	if elapsed_ms >= u64(state.config.timeout_milliseconds) {
		return 0, false
	}
	return state.config.timeout_milliseconds - u32(elapsed_ms), true
}

@(private)
clipboard_limit_failure :: proc(code: Clipboard_Failure_Code, limit, actual: u64) -> Clipboard_Failure_Context {
	return Clipboard_Failure_Context{code = code, limit = limit, actual = actual}
}
