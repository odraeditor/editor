// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package terminal_session

import "core:unicode/utf8"
import "../terminal_emulator"

/* registry_effect_configure replaces one session's explicit host-effect policy. */
registry_effect_configure :: proc(
	registry: ^Registry,
	ref: Session_Ref,
	policy: Effect_Policy,
) -> (record: Effect_Record, ok: bool, failure: Failure_Record) {
	state := registry_state(registry)
	if state == nil do return {}, false, registry_access_failure(registry, .Process)
	session, resolved := registry_resolve(state, ref)
	if !resolved do return {}, false, failure_record(.Process, .Stale_Reference)
	if policy.attention > .Both || policy.bell_interval_nanoseconds <= 0 {
		return {}, false, failure_record(.Process, .Invalid_Argument)
	}
	session.record.effects.policy = policy
	return session.record.effects, true, {}
}

/* registry_effect_record copies bounded effect accounting for inspection. */
registry_effect_record :: proc(
	registry: ^Registry,
	ref: Session_Ref,
) -> (record: Effect_Record, ok: bool, failure: Failure_Record) {
	state := registry_state(registry)
	if state == nil do return {}, false, registry_access_failure(registry, .Process)
	session, resolved := registry_resolve(state, ref)
	if !resolved do return {}, false, failure_record(.Process, .Stale_Reference)
	return session.record.effects, true, {}
}

/* registry_metadata_copy copies retained child metadata without granting authority. */
registry_metadata_copy :: proc(
	registry: ^Registry,
	ref: Session_Ref,
	kind: Metadata_Kind,
	output: []u8,
) -> (result: Metadata_Copy, ok: bool, failure: Failure_Record) {
	result.ref = ref
	result.kind = kind
	state := registry_state(registry)
	if state == nil do return result, false, registry_access_failure(registry, .Process)
	session, resolved := registry_resolve(state, ref)
	if !resolved do return result, false, failure_record(.Process, .Stale_Reference)

	value: []u8
	switch kind {
	case .Title:
		value = session.title[:session.title_length]
	case .Working_Context:
		value = session.working_context[:session.working_context_length]
	case .Invalid:
		return result, false, failure_record(.Process, .Invalid_Argument)
	}
	result.revision = session.record.effects.metadata_revision
	result.required_bytes = u64(len(value))
	copy_length := min(len(output), len(value))
	for copy_length > 0 && !utf8.valid_string(string(value[:copy_length])) {
		copy_length -= 1
	}
	if copy_length > 0 do copy(output[:copy_length], value[:copy_length])
	result.copied_bytes = u64(copy_length)
	result.truncated = copy_length < len(value)
	return result, true, {}
}

@(private)
terminal_effect_initialize_working_context :: proc(session: ^Session_State, value: string) {
	if session == nil || len(value) > MAX_METADATA_BYTES || !utf8.valid_string(value) do return
	bytes := transmute([]u8)value
	if len(bytes) > 0 do copy(session.working_context[:len(bytes)], bytes)
	session.working_context_length = u16(len(bytes))
}

@(private)
output_observe_effects :: proc(
	state: ^Registry_State,
	session: ^Session_State,
	observation: ^Output_Observation,
	now_ns: i64,
) -> Failure_Record {
	effects, result := terminal_emulator.effects(session.record.emulator)
	if result != .OK do return emulator_failure(.Parse, result)
	previous := session.observed_effects
	if effects.writeback_dropped_bytes > previous.writeback_dropped_bytes {
		dropped := effects.writeback_dropped_bytes - previous.writeback_dropped_bytes
		session.observed_effects = effects
		return failure_record(
			.Parse,
			.Output_Limit,
			limit = terminal_emulator.WRITEBACK_CAPACITY,
			actual = terminal_emulator.WRITEBACK_CAPACITY + dropped,
		)
	}

	observe_bells(state, session, observation, now_ns, effect_delta(effects.bell_count, previous.bell_count))
	writebacks := effect_delta(effects.writeback_count, previous.writeback_count)
	observation.writeback_count = effect_add(observation.writeback_count, writebacks)
	session.record.effects.device_responses = effect_add(
		session.record.effects.device_responses, writebacks,
	)

	observe_metadata(
		state, session, observation, .Title,
		effect_delta(effects.title_change_count, previous.title_change_count),
	)
	observe_metadata(
		state, session, observation, .Working_Context,
		effect_delta(effects.pwd_change_count, previous.pwd_change_count),
	)
	observe_denied_effects(session, observation, effects, previous)
	observe_progress(session, observation, effects, previous)
	observe_unknown_sequences(session, observation, effects, previous)
	session.observed_effects = effects
	return {}
}

@(private)
observe_bells :: proc(
	state: ^Registry_State,
	session: ^Session_State,
	observation: ^Output_Observation,
	now_ns: i64,
	requests: u64,
) {
	if requests == 0 do return
	observation.bell_count = effect_add(observation.bell_count, requests)
	observation.effects.bell_requests = effect_add(observation.effects.bell_requests, requests)
	session.record.effects.bell_requests = effect_add(session.record.effects.bell_requests, requests)

	policy := session.record.effects.policy
	channel_enabled := policy.attention != .None
	interval_elapsed := !session.bell_admitted_once ||
		(now_ns >= session.last_admitted_bell_ns &&
		 now_ns - session.last_admitted_bell_ns >= policy.bell_interval_nanoseconds)
	admitted := channel_enabled && interval_elapsed
	if admitted {
		session.bell_admitted_once = true
		session.last_admitted_bell_ns = now_ns
		session.record.effects.bell_admitted = effect_add(session.record.effects.bell_admitted, 1)
		observation.effects.bell_admitted = true
		observation.effects.audible_attention = policy.attention == .Audible || policy.attention == .Both
		observation.effects.visual_attention = policy.attention == .Visual || policy.attention == .Both
	}
	suppressed := requests
	if admitted do suppressed -= 1
	session.record.effects.bell_suppressed = effect_add(
		session.record.effects.bell_suppressed, suppressed,
	)
	terminal_event_publish(
		state, session, .Bell, "terminal",
		{requests, u64(admitted), u64(observation.effects.audible_attention), u64(observation.effects.visual_attention)},
	)
}

@(private)
observe_metadata :: proc(
	state: ^Registry_State,
	session: ^Session_State,
	observation: ^Output_Observation,
	kind: Metadata_Kind,
	change_requests: u64,
) {
	if change_requests == 0 do return
	if kind == .Title {
		session.record.effects.title_changes = effect_add(
			session.record.effects.title_changes, change_requests,
		)
	} else {
		session.record.effects.working_context_changes = effect_add(
			session.record.effects.working_context_changes, change_requests,
		)
	}

	buffer: [MAX_METADATA_BYTES]u8
	metadata: terminal_emulator.Metadata_Copy
	result: terminal_emulator.Result
	if kind == .Title {
		metadata, result = terminal_emulator.title_copy(session.record.emulator, buffer[:])
	} else {
		metadata, result = terminal_emulator.pwd_copy(session.record.emulator, buffer[:])
	}
	if result != .OK || metadata.truncated || metadata.required_bytes > MAX_METADATA_BYTES ||
	   metadata.copied_bytes > MAX_METADATA_BYTES ||
	   !utf8.valid_string(string(buffer[:metadata.copied_bytes])) {
		session.record.effects.metadata_truncations = effect_add(
			session.record.effects.metadata_truncations, 1,
		)
		effect_note_diagnostics(session, observation, 1)
		return
	}

	length := int(metadata.copied_bytes)
	changed: bool
	if kind == .Title {
		changed = !effect_bytes_equal(session.title[:session.title_length], buffer[:length])
		if changed {
			if length > 0 do copy(session.title[:length], buffer[:length])
			session.title_length = u16(length)
			observation.effects.title_changed = true
		}
	} else {
		changed = !effect_bytes_equal(
			session.working_context[:session.working_context_length], buffer[:length],
		)
		if changed {
			if length > 0 do copy(session.working_context[:length], buffer[:length])
			session.working_context_length = u16(length)
			observation.effects.working_context_changed = true
		}
	}
	if !changed do return
	session.record.effects.metadata_revision = effect_add(
		session.record.effects.metadata_revision, 1,
	)
	event_kind: Event_Kind = .Title
	if kind == .Working_Context do event_kind = .Working_Context
	terminal_event_publish(
		state, session, event_kind, "terminal",
		{session.record.effects.metadata_revision, u64(length), 0, 0},
		payload = buffer[:length],
	)
}

@(private)
observe_denied_effects :: proc(
	session: ^Session_State,
	observation: ^Output_Observation,
	effects: terminal_emulator.Effects,
	previous: terminal_emulator.Effects,
) {
	clipboard_reads := effect_delta(
		effects.clipboard_read_denied_count, previous.clipboard_read_denied_count,
	)
	clipboard_writes := effect_delta(
		effects.clipboard_write_denied_count, previous.clipboard_write_denied_count,
	)
	notifications := effect_delta(
		effects.notification_denied_count, previous.notification_denied_count,
	)
	session.record.effects.clipboard_read_denials = effect_add(
		session.record.effects.clipboard_read_denials, clipboard_reads,
	)
	session.record.effects.clipboard_write_denials = effect_add(
		session.record.effects.clipboard_write_denials, clipboard_writes,
	)
	session.record.effects.notification_denials = effect_add(
		session.record.effects.notification_denials, notifications,
	)
	denied := effect_add(effect_add(clipboard_reads, clipboard_writes), notifications)
	observation.effects.denied_effects = effect_add(observation.effects.denied_effects, denied)
	if denied > 0 do effect_note_diagnostics(session, observation, denied)
}

@(private)
observe_progress :: proc(
	session: ^Session_State,
	observation: ^Output_Observation,
	effects: terminal_emulator.Effects,
	previous: terminal_emulator.Effects,
) {
	reports := effect_delta(effects.progress_count, previous.progress_count)
	if reports == 0 do return
	session.record.effects.progress_reports = effect_add(
		session.record.effects.progress_reports, reports,
	)
	state: Progress_State
	switch effects.progress_state {
	case 0: state = .Removed
	case 1: state = .Set
	case 2: state = .Error
	case 3: state = .Indeterminate
	case 4: state = .Paused
	case:
		effect_note_diagnostics(session, observation, 1)
		return
	}
	if effects.progress_percent < -1 || effects.progress_percent > 100 {
		effect_note_diagnostics(session, observation, 1)
		return
	}
	session.record.effects.progress_state = state
	session.record.effects.progress_percent = i16(effects.progress_percent)
	observation.effects.progress_changed = true
}

@(private)
observe_unknown_sequences :: proc(
	session: ^Session_State,
	observation: ^Output_Observation,
	effects: terminal_emulator.Effects,
	previous: terminal_emulator.Effects,
) {
	sequences := effect_delta(effects.unknown_sequence_count, previous.unknown_sequence_count)
	bytes := effect_delta(effects.unknown_sequence_bytes, previous.unknown_sequence_bytes)
	truncated := effect_delta(effects.unknown_truncated_count, previous.unknown_truncated_count)
	session.record.effects.unknown_sequences = effect_add(
		session.record.effects.unknown_sequences, sequences,
	)
	session.record.effects.unknown_sequence_bytes = effect_add(
		session.record.effects.unknown_sequence_bytes, bytes,
	)
	if sequences > 0 || truncated > 0 {
		effect_note_diagnostics(session, observation, effect_add(sequences, truncated))
	}
}

@(private)
effect_note_diagnostics :: proc(
	session: ^Session_State,
	observation: ^Output_Observation,
	count: u64,
) {
	session.record.effects.diagnostics = effect_add(session.record.effects.diagnostics, count)
	observation.effects.diagnostics = effect_add(observation.effects.diagnostics, count)
}

@(private)
effect_delta :: proc(current, previous: u64) -> u64 {
	if current < previous do return 0
	return current - previous
}

@(private)
effect_add :: proc(value, increment: u64) -> u64 {
	if increment > max(u64) - value do return max(u64)
	return value + increment
}

@(private)
effect_bytes_equal :: proc(left, right: []u8) -> bool {
	if len(left) != len(right) do return false
	for byte, index in left {
		if byte != right[index] do return false
	}
	return true
}
