// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package terminal_session

import "core:time"
import "../interactive_session"
import "../terminal_emulator"

/* registry_step_output performs one byte- and time-bounded terminal-output turn. */
registry_step_output :: proc(
	registry: ^Registry,
	ref: Session_Ref,
	now_ns: i64,
) -> (observation: Output_Observation, ok: bool) {
	state := registry_state(registry)
	if state == nil {
		observation.failure = registry_access_failure(registry, .Parse)
		return observation, false
	}
	session, resolved := registry_resolve(state, ref)
	if !resolved {
		observation.failure = failure_record(.Parse, .Stale_Reference)
		return observation, false
	}
	return output_step_session(
		state,
		session,
		now_ns,
		session.limits.output_turn_bytes,
		session.limits.output_turn_nanoseconds,
	)
}

/* registry_step_output_all gives each composed session one fair bounded turn. */
registry_step_output_all :: proc(
	registry: ^Registry,
	now_ns: i64,
) -> (batch: Output_Batch, ok: bool) {
	state := registry_state(registry)
	if state == nil {
		batch.failure = registry_access_failure(registry, .Parse)
		return batch, false
	}
	started_at := time.tick_now()
	remaining_bytes := DEFAULT_LIMITS.output_turn_bytes
	last_index := int(state.round_robin_cursor)
	for offset in 0 ..< MAX_SESSIONS {
		index := (int(state.round_robin_cursor) + offset) % MAX_SESSIONS
		last_index = index
		session := state.entries[index]
		if session == nil || !session.occupied ||
		   (session.record.lifecycle != .Running && session.record.lifecycle != .Exited) {
			continue
		}
		elapsed_ns := time.duration_nanoseconds(time.tick_since(started_at))
		if remaining_bytes == 0 || elapsed_ns >= DEFAULT_LIMITS.output_turn_nanoseconds {
			break
		}
		batch.sessions_visited += 1
		observation, stepped := output_step_session(
			state,
			session,
			now_ns,
			min(session.limits.output_turn_bytes, remaining_bytes),
			min(
				session.limits.output_turn_nanoseconds,
				DEFAULT_LIMITS.output_turn_nanoseconds - elapsed_ns,
			),
		)
		if !stepped && batch.failure.code == .None do batch.failure = observation.failure
		if observation.progress do batch.sessions_progressed += 1
		batch.process_read_bytes += observation.process_read_bytes
		batch.parsed_bytes += observation.parsed_bytes
		batch.writeback_bytes += observation.writeback_bytes
		remaining_bytes -= min(remaining_bytes, observation.parsed_bytes)
	}
	state.round_robin_cursor = u8((last_index + 1) % MAX_SESSIONS)
	batch.work_remaining = output_work_remaining(state)
	return batch, batch.failure.code == .None
}

@(private)
output_step_session :: proc(
	state: ^Registry_State,
	session: ^Session_State,
	now_ns: i64,
	byte_limit: u64,
	time_limit_ns: i64,
) -> (observation: Output_Observation, ok: bool) {
	observation.ref = session.record.ref
	started_at := time.tick_now()
	transport, stepped := interactive_session.registry_step_bounded(
		&state.interactive,
		session.record.process.ref,
		now_ns,
		min(byte_limit, session.process_output_turn_bytes),
		min(time_limit_ns, session.process_output_turn_nanoseconds),
	)
	observation.process_read_bytes = transport.read_bytes
	observation.process_exited = transport.process_exited
	observation.progress = transport.progress
	if !stepped {
		return output_fail(session, process_failure(.Process, transport.failure), &observation)
	}

	output: [OUTPUT_CHUNK_BYTES]u8
	for observation.parsed_bytes < byte_limit {
		elapsed_ns := time.duration_nanoseconds(time.tick_since(started_at))
		if elapsed_ns >= time_limit_ns {
			observation.time_budget_exhausted = true
			break
		}
		remaining := byte_limit - observation.parsed_bytes
		copy_limit := int(min(remaining, OUTPUT_CHUNK_BYTES))
		copied, available, take_failure := interactive_session.registry_take_output(
			&state.interactive,
			session.record.process.ref,
			output[:copy_limit],
		)
		if take_failure.code != .None {
			return output_fail(session, process_failure(.Parse, take_failure), &observation)
		}
		if !available || copied == 0 do break
		semantic_sequence_before := session.semantic.next_sequence
		active_command_before := session.semantic.active_command_sequence
		if emulator_result := semantic_write_session(session, output[:copied]); emulator_result != .OK {
			return output_fail(session, emulator_failure(.Parse, emulator_result), &observation)
		}
		observation.parsed_bytes += u64(copied)
		observation.progress = true
		terminal_event_publish_output(
			state, session, output[:copied], semantic_sequence_before, active_command_before,
		)

		effect_failure := output_observe_effects(state, session, &observation, now_ns)
		if effect_failure.code != .None {
			return output_fail(session, effect_failure, &observation)
		}
		writeback_failure := output_route_writeback(state, session, &observation)
		if writeback_failure.code != .None {
			return output_fail(session, writeback_failure, &observation)
		}
	}

	process_record, found, process_issue := interactive_session.registry_record(
		&state.interactive,
		session.record.process.ref,
	)
	if !found {
		return output_fail(session, process_failure(.Process, process_issue), &observation)
	}
	session.record.process = process_record
	if process_record.lifecycle == .Exited do session.record.lifecycle = .Exited
	if process_record.lifecycle == .Exited && !session.exit_event_published {
		terminal_event_publish(
			state, session, .Process_Exit, "terminal",
			{u64(process_record.exit_status.kind), 0, 0, 0}, process_record.exit_status.value,
		)
		session.exit_event_published = true
	}
	if process_record.lifecycle == .Failed {
		return output_fail(session, process_failure(.Process, process_record.failure), &observation)
	}
	observation.output_pending = process_record.resources.queued_output_bytes > 0
	observation.input_pending = process_record.resources.queued_input_bytes > 0
	observation.byte_budget_exhausted = observation.parsed_bytes >= byte_limit
	observation.time_budget_exhausted =
		time.duration_nanoseconds(time.tick_since(started_at)) >= time_limit_ns ||
		observation.time_budget_exhausted
	return observation, true
}

@(private)
output_route_writeback :: proc(
	state: ^Registry_State,
	session: ^Session_State,
	observation: ^Output_Observation,
) -> Failure_Record {
	writeback: [OUTPUT_CHUNK_BYTES]u8
	for {
		copied, pending, result := terminal_emulator.writeback_copy(
			session.record.emulator,
			writeback[:],
		)
		if result != .OK do return emulator_failure(.Parse, result)
		if pending == 0 do return {}
		if copied <= 0 do return emulator_failure(.Parse, .Foreign_Failure)

		process_record, found, process_issue := interactive_session.registry_record(
			&state.interactive,
			session.record.process.ref,
		)
		if !found do return process_failure(.Parse, process_issue)
		requested := process_record.resources.queued_input_bytes + u64(copied)
		if requested > session.process_input_bytes {
			return Failure_Record {
				stage = .Parse,
				code = .Output_Limit,
				process_code = .Input_Limit,
				limit = session.process_input_bytes,
				actual = requested,
			}
		}
		queued, queue_failure := interactive_session.registry_send(
			&state.interactive,
			session.record.process.ref,
			writeback[:copied],
		)
		if !queued do return process_failure(.Parse, queue_failure)
		if consume_result := terminal_emulator.writeback_consume(
			session.record.emulator,
			copied,
		); consume_result != .OK {
			return emulator_failure(.Parse, consume_result)
		}
		observation.writeback_bytes += u64(copied)
		session.record.writeback_bytes += u64(copied)
	}
}

@(private)
output_fail :: proc(
	session: ^Session_State,
	failure: Failure_Record,
	observation: ^Output_Observation,
) -> (Output_Observation, bool) {
	session.record.lifecycle = .Failed
	session.record.failure = failure
	observation.failure = failure
	return observation^, false
}

@(private)
output_work_remaining :: proc(state: ^Registry_State) -> bool {
	for session in state.entries {
		if session == nil || !session.occupied do continue
		if session.record.lifecycle == .Running ||
		   session.record.process.resources.queued_output_bytes > 0 {
			return true
		}
	}
	return false
}
