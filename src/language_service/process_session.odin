// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language_service

import "base:runtime"
import "core:fmt"
import "core:strings"
import "core:unicode/utf8"

/* Process_Start_Request borrows validated launch data for one copied session owner. */
Process_Start_Request :: struct {
	handle:            Session_Handle,
	command:           []string,
	environment:       []string,
	working_directory: string,
	limits:            Service_Limits,
	deadlines:         Deadline_Policy,
	restart:           Restart_Policy,
}

/* Process_Session owns one child, nonblocking streams, queues, and lifecycle. */
Process_Session :: struct {
	state: rawptr,
}

/* Process_Poll reports one bounded nonblocking maintenance step. */
Process_Poll :: struct {
	health:         Health,
	read_bytes:     u64,
	written_bytes:  u64,
	standard_error_bytes: u64,
	frame_ready:    bool,
	process_exited: bool,
	exit_status:    i32,
	failure:        Failure_Context,
}

@(private)
Process_Session_State :: struct {
	handle:            Session_Handle,
	child:             Platform_Child,
	decoder:           Frame_Decoder,
	command:           []string,
	environment:       []string,
	working_directory: string,
	outbound:          [dynamic]u8,
	outbound_offset:   int,
	standard_error:    [dynamic]u8,
	health:            Health,
	capabilities:      Capability_Values,
	limits:            Service_Limits,
	deadlines:         Deadline_Policy,
	restart:           Restart_Policy,
	automatic_restarts: u8,
	deadline_ns:       i64,
	termination_sent:  bool,
	latest_failure:    Failure_Context,
	allocator:         runtime.Allocator,
}

/* process_session_start copies launch data and starts one nonblocking child. */
process_session_start :: proc(
	request: Process_Start_Request,
	now_ns: i64,
	allocator := context.allocator,
) -> (Process_Session, bool, Failure_Context) {
	if allocator.procedure == nil || !process_start_request_valid(request) {
		return {}, false, Failure_Context{code = .Invalid_Input}
	}
	state, allocation_error := new(Process_Session_State, allocator)
	if allocation_error != nil do return {}, false, Failure_Context{code = .Allocation}
	state.allocator = allocator
	state.handle = request.handle
	state.limits = request.limits
	state.deadlines = request.deadlines
	state.restart = request.restart

	state.command, allocation_error = clone_strings(request.command, allocator)
	if allocation_error != nil {
		process_session_state_destroy(state)
		return {}, false, Failure_Context{code = .Allocation}
	}
	state.environment, allocation_error = clone_strings(request.environment, allocator)
	if allocation_error != nil {
		process_session_state_destroy(state)
		return {}, false, Failure_Context{code = .Allocation}
	}
	state.working_directory, allocation_error = strings.clone(request.working_directory, allocator)
	if allocation_error != nil {
		process_session_state_destroy(state)
		return {}, false, Failure_Context{code = .Allocation}
	}
	state.outbound, allocation_error = make([dynamic]u8, 0, int(min(request.limits.queue_bytes, 64 * KIBIBYTE)), allocator)
	if allocation_error != nil {
		process_session_state_destroy(state)
		return {}, false, Failure_Context{code = .Allocation}
	}
	state.standard_error, allocation_error = make([dynamic]u8, 0, int(min(request.limits.standard_error_bytes, 16 * KIBIBYTE)), allocator)
	if allocation_error != nil {
		process_session_state_destroy(state)
		return {}, false, Failure_Context{code = .Allocation}
	}
	state.decoder, _, state.latest_failure = frame_decoder_open(request.limits, allocator)
	if state.latest_failure.code != .None {
		process_session_state_destroy(state)
		return {}, false, state.latest_failure
	}
	state.child, _, state.latest_failure = platform_child_start(
		state.command,
		state.environment,
		state.working_directory,
	)
	if state.latest_failure.code != .None {
		process_session_state_destroy(state)
		return {}, false, state.latest_failure
	}
	state.health = .Initializing
	state.deadline_ns = deadline_add(now_ns, request.deadlines.initialization_ns)
	return Process_Session{state = state}, true, {}
}

/* process_session_confirm_initialized publishes negotiated active capability state. */
process_session_confirm_initialized :: proc(
	session: ^Process_Session,
	capabilities: Capability_Values,
) -> (bool, Failure_Context) {
	state := process_session_state(session)
	if state == nil do return false, Failure_Context{code = .Closed}
	if state.health != .Initializing || !state.child.live {
		return false, Failure_Context{code = .Invalid_Session, session = state.handle}
	}
	state.capabilities = capabilities
	state.health = .Active
	state.deadline_ns = 0
	return true, {}
}

/* process_session_send_frame copies one bounded body into the nonblocking write queue. */
process_session_send_frame :: proc(
	session: ^Process_Session,
	body: []u8,
) -> (bool, Failure_Context) {
	state := process_session_state(session)
	if state == nil do return false, Failure_Context{code = .Closed}
	if state.health == .Stopped || state.health == .Failed || state.health == .Closed ||
	   state.health == .Terminating {
		return false, Failure_Context{code = .Invalid_Session, session = state.handle}
	}
	if len(body) == 0 || u64(len(body)) > state.limits.message_bytes || !utf8.valid_string(string(body)) {
		return false, Failure_Context{code = .Resource_Limit, resource = .Message_Bytes, limit = state.limits.message_bytes, actual = u64(len(body))}
	}
	header_storage: [64]u8
	header := fmt.bprintf(header_storage[:], "Content-Length: %d\r\n\r\n", len(body))
	pending := len(state.outbound) - state.outbound_offset
	needed := u64(pending) + u64(len(header)) + u64(len(body))
	if needed > state.limits.queue_bytes {
		return false, Failure_Context{code = .Resource_Limit, resource = .Queue_Bytes, limit = state.limits.queue_bytes, actual = needed}
	}
	compact_outbound(state)
	_, append_error := append(&state.outbound, ..transmute([]u8)header)
	if append_error == nil do _, append_error = append(&state.outbound, ..body)
	if append_error != nil do return false, Failure_Context{code = .Allocation}
	return true, {}
}

/* process_session_poll performs bounded nonblocking IO, deadlines, and reaping. */
process_session_poll :: proc(
	session: ^Process_Session,
	now_ns: i64,
) -> (Process_Poll, bool) {
	state := process_session_state(session)
	if state == nil do return Process_Poll{health = .Closed, failure = {code = .Closed}}, false
	result := Process_Poll{health = state.health, failure = state.latest_failure}
	work_limit := int(min(state.limits.work_bytes_per_turn, u64(64 * KIBIBYTE)))
	read_buffer: [64 * 1_024]u8

	if state.child.live && state.health != .Stopped {
		count, would_block, closed, failure := platform_child_read(state.child.stdout, read_buffer[:work_limit])
		if count > 0 {
			result.read_bytes += u64(count)
			_, accepted, frame_failure := frame_decoder_push(&state.decoder, read_buffer[:count])
			if !accepted {
				state.latest_failure = frame_failure
				state.health = .Failed
			}
		}
		if failure.code != .None {
			state.latest_failure = failure
			state.health = .Failed
		}
		_ = would_block
		_ = closed

		stderr_count, _, _, stderr_failure := platform_child_read(state.child.stderr, read_buffer[:work_limit])
		if stderr_count > 0 do stderr_append(state, read_buffer[:stderr_count])
		if stderr_failure.code != .None {
			state.latest_failure = stderr_failure
			state.health = .Failed
		}

		if state.outbound_offset < len(state.outbound) {
			write_end := min(len(state.outbound), state.outbound_offset + work_limit)
			written, _, write_failure := platform_child_write(
				state.child.stdin,
				state.outbound[state.outbound_offset:write_end],
			)
			state.outbound_offset += written
			result.written_bytes += u64(written)
			if write_failure.code != .None {
				state.latest_failure = write_failure
				state.health = .Failed
			}
			compact_outbound(state)
		}
	}

	exited, exit_status, reap_failure := platform_child_poll(&state.child)
	if reap_failure.code != .None {
		state.latest_failure = reap_failure
		state.health = .Failed
	} else if exited {
		result.process_exited = true
		result.exit_status = exit_status
		if state.health == .Terminating || state.health == .Shutting_Down {
			state.health = .Stopped
			state.deadline_ns = 0
		} else {
			state.health = .Failed
			state.latest_failure = Failure_Context{code = .Process_Exit, session = state.handle, actual = u64(i64(exit_status))}
		}
	}

	process_session_deadline_step(state, now_ns)
	framing_state, _, _, framing_failure := frame_decoder_inspect(&state.decoder)
	if framing_state == .Failed {
		state.latest_failure = framing_failure
		state.health = .Failed
	}
	result.health = state.health
	result.frame_ready = framing_state == .Ready
	result.standard_error_bytes = u64(len(state.standard_error))
	result.failure = state.latest_failure
	return result, true
}

/* process_session_take_frame copies one ready stdout protocol frame. */
process_session_take_frame :: proc(
	session: ^Process_Session,
) -> (Frame, bool, Failure_Context) {
	state := process_session_state(session)
	if state == nil do return {}, false, Failure_Context{code = .Closed}
	return frame_decoder_take(&state.decoder)
}

/* process_session_begin_cancellation starts one bounded cancellation interval. */
process_session_begin_cancellation :: proc(session: ^Process_Session, now_ns: i64) -> (bool, Failure_Context) {
	state := process_session_state(session)
	if state == nil do return false, Failure_Context{code = .Closed}
	if state.health != .Active do return false, Failure_Context{code = .Invalid_Session, session = state.handle}
	state.health = .Cancelling
	state.deadline_ns = deadline_add(now_ns, state.deadlines.cancellation_ns)
	return true, {}
}

/* process_session_complete_cancellation returns one live cancelled session to active. */
process_session_complete_cancellation :: proc(session: ^Process_Session) -> (bool, Failure_Context) {
	state := process_session_state(session)
	if state == nil do return false, Failure_Context{code = .Closed}
	if state.health != .Cancelling do return false, Failure_Context{code = .Invalid_Session, session = state.handle}
	state.health = .Active
	state.deadline_ns = 0
	return true, {}
}

/* process_session_begin_shutdown starts one graceful bounded shutdown interval. */
process_session_begin_shutdown :: proc(session: ^Process_Session, now_ns: i64) -> (bool, Failure_Context) {
	state := process_session_state(session)
	if state == nil do return false, Failure_Context{code = .Closed}
	if state.health != .Active do return false, Failure_Context{code = .Invalid_Session, session = state.handle}
	state.health = .Shutting_Down
	state.deadline_ns = deadline_add(now_ns, state.deadlines.shutdown_ns)
	return true, {}
}

/* process_session_force_terminate requests immediate forced child termination. */
process_session_force_terminate :: proc(session: ^Process_Session, now_ns: i64) -> (bool, Failure_Context) {
	state := process_session_state(session)
	if state == nil do return false, Failure_Context{code = .Closed}
	if !state.child.live do return false, Failure_Context{code = .Invalid_Process, session = state.handle}
	if !platform_child_kill(&state.child) do return false, Failure_Context{code = .Termination, session = state.handle}
	state.health = .Terminating
	state.termination_sent = true
	state.deadline_ns = deadline_add(now_ns, state.deadlines.forced_termination_ns)
	return true, {}
}

/* process_session_restart starts the one admitted replacement after exact reap. */
process_session_restart :: proc(session: ^Process_Session, now_ns: i64) -> (bool, Failure_Context) {
	state := process_session_state(session)
	if state == nil do return false, Failure_Context{code = .Closed}
	if state.health != .Failed || state.child.live || !state.child.reaped {
		return false, Failure_Context{code = .Invalid_Session, session = state.handle}
	}
	if state.automatic_restarts >= state.restart.automatic_restarts {
		return false, Failure_Context{code = .Restart_Exhausted, session = state.handle, limit = u64(state.restart.automatic_restarts), actual = u64(state.automatic_restarts) + 1}
	}
	if state.handle.generation == Session_Generation(max(u64)) {
		return false, Failure_Context{code = .Arithmetic_Overflow, session = state.handle}
	}
	platform_child_close(&state.child)
	child, started, failure := platform_child_start(state.command, state.environment, state.working_directory)
	if !started {
		state.latest_failure = failure
		return false, failure
	}
	state.child = child
	state.handle.generation += 1
	state.automatic_restarts += 1
	state.health = .Initializing
	state.capabilities = {}
	state.deadline_ns = deadline_add(now_ns, state.deadlines.initialization_ns)
	state.termination_sent = false
	state.latest_failure = {}
	return true, {}
}

/* process_session_copy_stderr copies the retained standard-error tail. */
process_session_copy_stderr :: proc(session: ^Process_Session, output: []u8) -> (int, bool) {
	state := process_session_state(session)
	if state == nil || len(output) < len(state.standard_error) do return 0, false
	copy(output, state.standard_error[:])
	return len(state.standard_error), true
}

/* process_session_inspect returns one pointer-free copied lifecycle and resource view. */
process_session_inspect :: proc(session: ^Process_Session) -> (Inspection_Record, bool) {
	state := process_session_state(session)
	if state == nil do return {}, false
	process_state := Process_State.Running if state.child.live else Process_State.Reaped
	return Inspection_Record {
		kind = .Session,
		session = {
			handle = state.handle,
			health = state.health,
			capabilities = state.capabilities.capabilities,
			position_encoding = state.capabilities.position_encoding,
			synchronization_mode = state.capabilities.synchronization_mode,
			automatic_restarts = state.automatic_restarts,
		},
		process = {
			handle = {session = state.handle, id = 1, generation = Process_Generation(state.handle.generation)},
			state = process_state,
			os_process_id = i64(state.child.process.pid),
			termination_due_ns = state.deadline_ns,
		},
		usage = {
			queue_depth = u32(1 if state.outbound_offset < len(state.outbound) else 0),
			queue_bytes = u64(len(state.outbound) - state.outbound_offset),
			standard_error_bytes = u64(len(state.standard_error)),
			retained_bytes = u64(cap(state.outbound) + cap(state.standard_error)),
		},
		limits = state.limits,
		failure = state.latest_failure,
	}, true
}

/* process_session_validate_handle rejects identities from another lifecycle generation. */
process_session_validate_handle :: proc(
	session: ^Process_Session,
	expected: Session_Handle,
) -> (bool, Failure_Context) {
	state := process_session_state(session)
	if state == nil do return false, Failure_Context{code = .Closed}
	if expected.id == 0 || expected.generation == 0 {
		return false, Failure_Context{code = .Invalid_Session, session = expected}
	}
	if expected != state.handle {
		return false, Failure_Context {
			code = .Stale_Generation,
			session = expected,
			limit = u64(state.handle.generation),
			actual = u64(expected.generation),
		}
	}
	return true, {}
}

/* process_session_close kills, reaps, closes streams, and releases all storage. */
process_session_close :: proc(session: ^Process_Session) -> bool {
	state := process_session_state(session)
	if state == nil do return false
	process_session_state_destroy(state)
	session^ = Process_Session{}
	return true
}

@(private = "file")
process_session_state :: proc(session: ^Process_Session) -> ^Process_Session_State {
	if session == nil || session.state == nil do return nil
	return cast(^Process_Session_State)session.state
}

@(private = "file")
process_start_request_valid :: proc(request: Process_Start_Request) -> bool {
	if request.handle.id == 0 || request.handle.generation == 0 ||
	   len(request.command) == 0 || len(request.command) > int(request.limits.arguments) ||
	   !service_limits_valid(request.limits) || !deadline_policy_valid(request.deadlines) ||
	   request.restart.automatic_restarts > DEFAULT_RESTART_POLICY.automatic_restarts ||
	   request.restart.stability_ns != request.deadlines.restart_stability_ns {
		return false
	}
	command_bytes := u64(0)
	for value in request.command {
		if len(value) == 0 || !utf8.valid_string(value) || strings.index_byte(value, 0) >= 0 do return false
		if u64(len(value)) > request.limits.argument_bytes - min(command_bytes, request.limits.argument_bytes) do return false
		command_bytes += u64(len(value))
	}
	environment_bytes := u64(0)
	if len(request.environment) > int(request.limits.environment_entries) do return false
	for value in request.environment {
		if !utf8.valid_string(value) || strings.index_byte(value, 0) >= 0 do return false
		if u64(len(value)) > request.limits.environment_bytes - min(environment_bytes, request.limits.environment_bytes) do return false
		environment_bytes += u64(len(value))
	}
	return utf8.valid_string(request.working_directory) &&
		strings.index_byte(request.working_directory, 0) < 0 &&
		u64(len(request.working_directory)) <= request.limits.root_bytes
}

@(private = "file")
clone_strings :: proc(values: []string, allocator: runtime.Allocator) -> ([]string, runtime.Allocator_Error) {
	owned, allocation_error := make([]string, len(values), allocator)
	if allocation_error != nil do return nil, allocation_error
	for value, index in values {
		owned[index], allocation_error = strings.clone(value, allocator)
		if allocation_error != nil {
			for previous in 0 ..< index do delete(owned[previous], allocator)
			delete(owned, allocator)
			return nil, allocation_error
		}
	}
	return owned, nil
}

@(private = "file")
process_session_deadline_step :: proc(state: ^Process_Session_State, now_ns: i64) {
	if state.deadline_ns == 0 || now_ns < state.deadline_ns do return
	#partial switch state.health {
	case .Initializing, .Cancelling:
		state.latest_failure = Failure_Context{code = .Timeout, session = state.handle}
		state.health = .Failed
		if state.child.live && platform_child_terminate(&state.child) {
			state.termination_sent = true
			state.deadline_ns = deadline_add(now_ns, state.deadlines.forced_termination_ns)
		} else {
			state.deadline_ns = 0
		}
	case .Shutting_Down:
		if state.child.live && platform_child_terminate(&state.child) {
			state.health = .Terminating
			state.termination_sent = true
			state.deadline_ns = deadline_add(now_ns, state.deadlines.forced_termination_ns)
		} else {
			state.latest_failure = Failure_Context{code = .Termination, session = state.handle}
			state.health = .Failed
			state.deadline_ns = 0
		}
	case .Terminating, .Failed:
		if state.child.live {
			_ = platform_child_kill(&state.child)
			state.termination_sent = true
		}
		state.deadline_ns = 0
	case:
		state.deadline_ns = 0
	}
}

@(private = "file")
stderr_append :: proc(state: ^Process_Session_State, input: []u8) {
	limit := int(state.limits.standard_error_bytes)
	if len(input) >= limit {
		resize(&state.standard_error, 0)
		_, _ = append(&state.standard_error, ..input[len(input) - limit:])
		return
	}
	excess := len(state.standard_error) + len(input) - limit
	if excess > 0 {
		remaining := len(state.standard_error) - excess
		if remaining > 0 do copy(state.standard_error[:remaining], state.standard_error[excess:])
		resize(&state.standard_error, max(remaining, 0))
	}
	_, _ = append(&state.standard_error, ..input)
}

@(private = "file")
compact_outbound :: proc(state: ^Process_Session_State) {
	if state.outbound_offset == 0 do return
	remaining := len(state.outbound) - state.outbound_offset
	if remaining > 0 do copy(state.outbound[:remaining], state.outbound[state.outbound_offset:])
	resize(&state.outbound, remaining)
	state.outbound_offset = 0
}

@(private = "file")
deadline_add :: proc(now_ns, duration_ns: i64) -> i64 {
	if duration_ns <= 0 || now_ns > max(i64) - duration_ns do return max(i64)
	return now_ns + duration_ns
}

@(private = "file")
process_session_state_destroy :: proc(state: ^Process_Session_State) {
	if state == nil do return
	allocator := state.allocator
	platform_child_close(&state.child)
	if state.decoder.state != nil do frame_decoder_close(&state.decoder)
	if state.outbound != nil do delete(state.outbound)
	if state.standard_error != nil do delete(state.standard_error)
	for value in state.command do delete(value, allocator)
	if state.command != nil do delete(state.command, allocator)
	for value in state.environment do delete(value, allocator)
	if state.environment != nil do delete(state.environment, allocator)
	if len(state.working_directory) > 0 do delete(state.working_directory, allocator)
	free(state, allocator)
}
