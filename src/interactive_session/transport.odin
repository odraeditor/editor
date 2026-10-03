// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package interactive_session

import "core:time"

/* registry_send copies bounded input for one running session. */
registry_send :: proc(
	registry: ^Registry,
	ref: Session_Ref,
	input: []u8,
) -> (bool, Failure_Record) {
	state := registry_state(registry)
	if state == nil {
		return false, registry_access_failure(registry, .Input)
	}
	session, resolved, code := registry_resolve(state, ref)
	if !resolved {
		return false, failure_record(.Input, code)
	}
	if session.record.lifecycle != .Running || len(input) == 0 {
		return false, failure_record(.Input, .Invalid_Transition)
	}
	pending := transport_input_pending(session)
	requested := u64(pending) + u64(len(input))
	if requested > session.limits.input_bytes {
		return false, failure_record(
			.Input,
			.Input_Limit,
			limit = session.limits.input_bytes,
			actual = requested,
		)
	}
	aggregate := registry_queued_input(state)
	if u64(len(input)) > MAX_AGGREGATE_INPUT_BYTES - min(
		aggregate,
		MAX_AGGREGATE_INPUT_BYTES,
	) {
		return false, failure_record(
			.Input,
			.Input_Limit,
			limit = MAX_AGGREGATE_INPUT_BYTES,
			actual = aggregate + u64(len(input)),
		)
	}
	transport_compact_input(session)
	old_length := len(session.input)
	if allocation_error := resize(&session.input, old_length + len(input)); allocation_error != nil {
		return false, failure_record(.Input, .Allocation)
	}
	copy(session.input[old_length:], input)
	transport_update_queue_usage(session)
	return true, {}
}

/* registry_take_output copies and consumes currently retained transport output. */
registry_take_output :: proc(
	registry: ^Registry,
	ref: Session_Ref,
	output: []u8,
) -> (copied: int, available: bool, failure: Failure_Record) {
	state := registry_state(registry)
	if state == nil {
		return 0, false, registry_access_failure(registry, .Output)
	}
	session, resolved, code := registry_resolve(state, ref)
	if !resolved {
		return 0, false, failure_record(.Output, code)
	}
	if len(output) == 0 {
		return 0, false, failure_record(.Output, .Invalid_Argument)
	}
	pending := transport_output_pending(session)
	if pending == 0 do return 0, false, {}
	copied = copy(output, session.output[session.output_offset:])
	session.output_offset += copied
	transport_compact_output(session)
	transport_update_queue_usage(session)
	return copied, true, {}
}

/* registry_request_cancel begins bounded interrupt, terminate, and kill escalation. */
registry_request_cancel :: proc(
	registry: ^Registry,
	ref: Session_Ref,
	now_ns: i64,
) -> (bool, Failure_Record) {
	state := registry_state(registry)
	if state == nil {
		return false, registry_access_failure(registry, .Terminate)
	}
	session, resolved, code := registry_resolve(state, ref)
	if !resolved {
		return false, failure_record(.Terminate, code)
	}
	if session.record.lifecycle != .Running || session.record.cancel_requested {
		return false, failure_record(.Terminate, .Invalid_Transition)
	}
	if !request_cancel(&session.record) {
		return false, failure_record(.Terminate, .Invalid_Transition)
	}
	signalled, signal_failure := local_process_signal(&session.process, .Interrupt)
	if !signalled {
		_ = record_failure(&session.record, signal_failure)
		return false, signal_failure
	}
	session.cancel_phase = 1
	session.cancel_deadline_ns = transport_deadline_add(
		now_ns,
		max(session.limits.shutdown_nanoseconds / 2, i64(1)),
	)
	return true, {}
}

/* registry_step performs one byte- and time-bounded nonblocking session turn. */
registry_step :: proc(
	registry: ^Registry,
	ref: Session_Ref,
	now_ns: i64,
) -> (step: Transport_Step, ok: bool) {
	state := registry_state(registry)
	if state == nil {
		step.failure = registry_access_failure(registry, .Poll)
		return step, false
	}
	session, resolved, code := registry_resolve(state, ref)
	if !resolved {
		step.failure = failure_record(.Poll, code)
		return step, false
	}
	return transport_step_session(
		state,
		session,
		now_ns,
		session.limits.output_turn_bytes,
		session.limits.output_turn_nanoseconds,
	)
}

/* registry_step_bounded performs one turn under caller-tightened transport limits. */
registry_step_bounded :: proc(
	registry: ^Registry,
	ref: Session_Ref,
	now_ns: i64,
	byte_limit: u64,
	time_limit_ns: i64,
) -> (step: Transport_Step, ok: bool) {
	state := registry_state(registry)
	if state == nil {
		step.failure = registry_access_failure(registry, .Poll)
		return step, false
	}
	session, resolved, code := registry_resolve(state, ref)
	if !resolved {
		step.failure = failure_record(.Poll, code)
		return step, false
	}
	if byte_limit == 0 || byte_limit > session.limits.output_turn_bytes ||
	   time_limit_ns <= 0 || time_limit_ns > session.limits.output_turn_nanoseconds {
		step.failure = failure_record(.Poll, .Invalid_Argument)
		return step, false
	}
	return transport_step_session(state, session, now_ns, byte_limit, time_limit_ns)
}

/* registry_step_all gives active sessions one fair bounded round-robin turn. */
registry_step_all :: proc(
	registry: ^Registry,
	now_ns: i64,
) -> (batch: Transport_Batch, ok: bool) {
	state := registry_state(registry)
	if state == nil {
		batch.failure = registry_access_failure(registry, .Poll)
		return batch, false
	}
	started_at := time.tick_now()
	remaining_bytes := DEFAULT_LIMITS.output_turn_bytes
	last_index := int(state.round_robin_cursor)
	for offset in 0 ..< MAX_SESSIONS {
		index := (int(state.round_robin_cursor) + offset) % MAX_SESSIONS
		last_index = index
		session := state.entries[index]
		if session == nil ||
		   (session.record.lifecycle != .Running &&
		    (session.record.lifecycle != .Exited || session.output_eof)) {
			continue
		}
		batch.sessions_visited += 1
		step, stepped := transport_step_session(
			state,
			session,
			now_ns,
			min(session.limits.output_turn_bytes, remaining_bytes),
			DEFAULT_LIMITS.output_turn_nanoseconds,
		)
		if !stepped && batch.failure.code == .None do batch.failure = step.failure
		if step.progress do batch.sessions_progressed += 1
		batch.read_bytes += step.read_bytes
		batch.written_bytes += step.written_bytes
		batch.backpressured = batch.backpressured || step.backpressured
		if step.next_wakeup_ns > 0 &&
		   (batch.next_wakeup_ns == 0 || step.next_wakeup_ns < batch.next_wakeup_ns) {
			batch.next_wakeup_ns = step.next_wakeup_ns
		}
		turn_bytes := step.read_bytes + step.written_bytes
		remaining_bytes -= min(remaining_bytes, turn_bytes)
		if remaining_bytes == 0 ||
		   time.duration_nanoseconds(time.tick_since(started_at)) >=
			DEFAULT_LIMITS.output_turn_nanoseconds {
			break
		}
	}
	state.round_robin_cursor = u8((last_index + 1) % MAX_SESSIONS)
	batch.work_remaining = registry_needs_maintenance_state(state)
	return batch, batch.failure.code == .None
}

/* registry_needs_maintenance reports whether polling or queue work remains. */
registry_needs_maintenance :: proc(registry: ^Registry) -> bool {
	state := registry_state(registry)
	return state != nil && registry_needs_maintenance_state(state)
}

@(private)
transport_step_session :: proc(
	state: ^Registry_State,
	session: ^Session_State,
	now_ns: i64,
	byte_limit: u64,
	time_limit_ns: i64,
) -> (step: Transport_Step, ok: bool) {
	step.ref = session.record.ref
	if session.record.lifecycle != .Running && session.record.lifecycle != .Exited {
		step.process_exited = session.record.lifecycle == .Exited
		return step, true
	}
	started_at := time.tick_now()
	remaining_bytes := byte_limit

	if session.record.lifecycle == .Running do transport_cancellation_step(session, now_ns, &step)
	if step.failure.code != .None do return step, false

	input_pending := transport_input_pending(session)
	if session.record.lifecycle == .Running && input_pending > 0 && remaining_bytes > 0 {
		write_count := min(
			input_pending,
			int(min(session.limits.write_chunk_bytes, remaining_bytes)),
		)
		written, would_block, write_failure := local_process_write(
			&session.process,
			session.input[session.input_offset:session.input_offset + write_count],
		)
		if write_failure.code != .None {
			_ = record_failure(&session.record, write_failure)
			step.failure = write_failure
			return step, false
		}
		session.input_offset += written
		step.written_bytes = u64(written)
		step.progress = written > 0
		step.would_block = would_block
		if written > 0 {
			session.record.resources.total_input_bytes += u64(written)
			session.record.resources.write_turns += 1
		}
		remaining_bytes -= min(remaining_bytes, u64(written))
		transport_compact_input(session)
	}

	output_pending := transport_output_pending(session)
	output_available := session.limits.output_bytes - min(
		u64(output_pending),
		session.limits.output_bytes,
	)
	aggregate_output := registry_queued_output(state)
	aggregate_available := MAX_AGGREGATE_OUTPUT_BYTES - min(
		aggregate_output,
		MAX_AGGREGATE_OUTPUT_BYTES,
	)
	output_available = min(output_available, aggregate_available)
	if output_available == 0 {
		step.backpressured = true
	} else if !session.output_eof && remaining_bytes > 0 &&
	          time.duration_nanoseconds(time.tick_since(started_at)) < time_limit_ns {
		transport_compact_output(session)
		read_limit := int(min(
			min(session.limits.read_chunk_bytes, remaining_bytes),
			output_available,
		))
		old_length := len(session.output)
		if allocation_error := resize(&session.output, old_length + read_limit); allocation_error != nil {
			failure := failure_record(.Output, .Allocation)
			_ = record_failure(&session.record, failure)
			step.failure = failure
			return step, false
		}
		read, would_block, end_of_file, read_failure := local_process_read(
			&session.process,
			session.output[old_length:],
		)
		_ = resize(&session.output, old_length + read)
		if read_failure.code != .None {
			_ = record_failure(&session.record, read_failure)
			step.failure = read_failure
			return step, false
		}
		step.read_bytes = u64(read)
		step.progress = step.progress || read > 0
		step.would_block = step.would_block || would_block
		if read > 0 {
			session.record.resources.total_output_bytes += u64(read)
			session.record.resources.read_turns += 1
		}
		session.output_eof = session.output_eof || end_of_file
	}

	if session.record.lifecycle == .Running {
		exit_collected, exit_failure := transport_collect_exit(state, session)
		if exit_failure.code != .None {
			step.failure = exit_failure
			return step, false
		}
		step.process_exited = exit_collected
		step.progress = step.progress || exit_collected
	}
	transport_update_queue_usage(session)
	step.output_ready = transport_output_pending(session) > 0
	step.input_pending = transport_input_pending(session) > 0
	step.backpressured = step.backpressured ||
		u64(transport_output_pending(session)) >= session.limits.output_bytes
	step.would_block = !step.progress &&
		(session.record.lifecycle == .Running || !session.output_eof)
	step.next_wakeup_ns = session.cancel_deadline_ns
	return step, true
}

@(private)
transport_collect_exit :: proc(
	state: ^Registry_State,
	session: ^Session_State,
) -> (bool, Failure_Record) {
	if session.record.lifecycle != .Running do return false, {}
	poll, polled, poll_failure := local_process_poll(&session.process)
	if !polled {
		_ = record_failure(&session.record, poll_failure)
		return false, poll_failure
	}
	if !poll.exited do return false, {}
	_, exit_failure := record_exit(&session.record, poll.exit_status)
	if exit_failure.code != .None {
		_ = record_failure(&session.record, exit_failure)
		return false, exit_failure
	}
	session.record.resources.open_descriptors = 1
	session.cancel_deadline_ns = 0
	if state.default_session == session.record.ref do registry_replace_default(state)
	return true, {}
}

@(private)
transport_cancellation_step :: proc(
	session: ^Session_State,
	now_ns: i64,
	step: ^Transport_Step,
) {
	if !session.record.cancel_requested || session.cancel_deadline_ns == 0 ||
	   now_ns < session.cancel_deadline_ns {
		return
	}
	signal := Process_Signal.Terminate
	if session.cancel_phase >= 2 do signal = .Kill
	signalled, signal_failure := local_process_signal(&session.process, signal)
	if !signalled {
		_ = record_failure(&session.record, signal_failure)
		step.failure = signal_failure
		return
	}
	session.cancel_phase += 1
	step.progress = true
	if session.cancel_phase < 3 {
		session.cancel_deadline_ns = transport_deadline_add(
			now_ns,
			max(session.limits.shutdown_nanoseconds / 2, i64(1)),
		)
	} else {
		session.cancel_deadline_ns = 0
	}
}

@(private)
transport_input_pending :: proc(session: ^Session_State) -> int {
	return len(session.input) - session.input_offset
}

@(private)
transport_output_pending :: proc(session: ^Session_State) -> int {
	return len(session.output) - session.output_offset
}

@(private)
transport_compact_input :: proc(session: ^Session_State) {
	if session.input_offset == 0 do return
	remaining := transport_input_pending(session)
	if remaining > 0 do copy(session.input[:remaining], session.input[session.input_offset:])
	_ = resize(&session.input, remaining)
	session.input_offset = 0
}

@(private)
transport_compact_output :: proc(session: ^Session_State) {
	if session.output_offset == 0 do return
	remaining := transport_output_pending(session)
	if remaining > 0 do copy(session.output[:remaining], session.output[session.output_offset:])
	_ = resize(&session.output, remaining)
	session.output_offset = 0
}

@(private)
transport_update_queue_usage :: proc(session: ^Session_State) {
	input_bytes := u64(transport_input_pending(session))
	output_bytes := u64(transport_output_pending(session))
	session.record.resources.queued_input_bytes = input_bytes
	session.record.resources.queued_output_bytes = output_bytes
	session.record.resources.input_peak_bytes = max(
		session.record.resources.input_peak_bytes,
		input_bytes,
	)
	session.record.resources.output_peak_bytes = max(
		session.record.resources.output_peak_bytes,
		output_bytes,
	)
}

@(private)
registry_queued_input :: proc(state: ^Registry_State) -> u64 {
	total: u64
	for session in state.entries {
		if session != nil do total += u64(transport_input_pending(session))
	}
	return total
}

@(private)
registry_queued_output :: proc(state: ^Registry_State) -> u64 {
	total: u64
	for session in state.entries {
		if session != nil do total += u64(transport_output_pending(session))
	}
	return total
}

@(private)
registry_needs_maintenance_state :: proc(state: ^Registry_State) -> bool {
	for session in state.entries {
		if session != nil &&
		   (session.record.lifecycle == .Running || transport_input_pending(session) > 0 ||
		    transport_output_pending(session) > 0 ||
		    (session.record.lifecycle == .Exited && !session.output_eof)) {
			return true
		}
	}
	return false
}

@(private)
transport_deadline_add :: proc(now_ns, duration_ns: i64) -> i64 {
	if duration_ns <= 0 || now_ns > max(i64) - duration_ns do return max(i64)
	return now_ns + duration_ns
}
