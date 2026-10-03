// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package terminal_session

import "core:unicode/utf8"
import "../terminal_emulator"
import base_runtime "base:runtime"

/* registry_subscribe admits one generation-scoped bounded terminal observation. */
registry_subscribe :: proc(
	registry: ^Registry,
	definition: Subscription_Definition,
) -> (record: Subscription_Record, ok: bool, failure: Failure_Record) {
	state := registry_state(registry)
	if state == nil do return {}, false, registry_access_failure(registry, .Process)
	if !subscription_definition_valid(definition) {
		return {}, false, failure_record(.Process, .Invalid_Argument)
	}
	if state.subscriber_count >= state.event_limits.subscribers {
		return {}, false, failure_record(
			.Process, .Subscriber_Limit, limit = u64(state.event_limits.subscribers),
			actual = u64(state.subscriber_count) + 1,
		)
	}
	for ref, index in definition.sessions {
		if _, current, _ := registry_record(registry, ref); !current {
			return {}, false, failure_record(.Process, .Stale_Reference)
		}
		for previous in definition.sessions[:index] {
			if previous == ref do return {}, false, failure_record(.Process, .Invalid_Argument)
		}
		if terminal_subscriber_count(state, ref) >= state.event_limits.subscribers_per_session {
			return {}, false, failure_record(
				.Process, .Subscriber_Limit, limit = u64(state.event_limits.subscribers_per_session),
				actual = u64(terminal_subscriber_count(state, ref)) + 1,
			)
		}
	}
	index := terminal_subscription_free_index(state)
	if index < 0 {
		return {}, false, failure_record(.Process, .Subscriber_Limit, limit = MAX_SUBSCRIBERS, actual = MAX_SUBSCRIBERS + 1)
	}
	generation := state.subscription_generations[index] + 1
	if generation == 0 do generation = 1
	subscription := &state.subscriptions[index]
	subscription^ = Subscription_State {
		record = {
			ref = {id = Subscription_ID(index + 1), generation = generation},
			session_count = u8(len(definition.sessions)),
			handler = event_provider(definition.handler),
			batch_events = definition.batch_events,
			batch_bytes = definition.batch_bytes,
			turn_milliseconds = definition.turn_milliseconds,
			temporary_memory_bytes = definition.temporary_memory_bytes,
			active = true,
		},
		kinds = definition.kinds,
		raw_output = definition.raw_output,
		occupied = true,
	}
	for ref, session_index in definition.sessions {
		subscription.sessions[session_index] = ref
		session := terminal_event_session(state, ref)
		if session != nil do subscription.cursors[session_index] = session.next_event_sequence - 1
	}
	state.subscription_generations[index] = generation
	state.subscriber_count += 1
	return subscription.record, true, {}
}

/* registry_unsubscribe closes one exact subscription without changing its sessions. */
registry_unsubscribe :: proc(
	registry: ^Registry,
	ref: Subscription_Ref,
) -> (bool, Failure_Record) {
	state := registry_state(registry)
	if state == nil do return false, registry_access_failure(registry, .Process)
	subscription := terminal_subscription_resolve(state, ref)
	if subscription == nil do return false, failure_record(.Process, .Stale_Reference)
	terminal_subscription_close(state, subscription)
	terminal_event_reclaim_all(state)
	return true, {}
}

/* registry_subscription_record copies one exact subscriber generation. */
registry_subscription_record :: proc(
	registry: ^Registry,
	ref: Subscription_Ref,
) -> (Subscription_Record, bool, Failure_Record) {
	state := registry_state(registry)
	if state == nil do return {}, false, registry_access_failure(registry, .Process)
	subscription := terminal_subscription_resolve(state, ref)
	if subscription == nil do return {}, false, failure_record(.Process, .Stale_Reference)
	return subscription.record, true, {}
}

/* registry_event_append copies one admitted adapter observation into bounded native storage. */
registry_event_append :: proc(
	registry: ^Registry,
	ref: Session_Ref,
	kind: Event_Kind,
	provider: string,
	values: [4]u64 = {},
	signed_value: i32 = 0,
	flags: u8 = 0,
	payload: []u8 = nil,
) -> (sequence: u64, queued: bool, failure: Failure_Record) {
	state := registry_state(registry)
	if state == nil do return 0, false, registry_access_failure(registry, .Process)
	session := terminal_event_session(state, ref)
	if session == nil do return 0, false, failure_record(.Process, .Stale_Reference)
	if !event_request_valid(kind, provider, payload) {
		return 0, false, failure_record(.Process, .Invalid_Argument)
	}
	if !terminal_event_subscriber_present(state, ref, kind) {
		return 0, true, {}
	}
	if u64(len(payload)) > state.event_limits.event_bytes {
		return 0, false, failure_record(.Process, .Event_Limit, limit = state.event_limits.event_bytes, actual = u64(len(payload)))
	}
	if kind == .Terminal_Revision && len(session.events) > 0 {
		last := &session.events[len(session.events) - 1]
		if last.kind == .Terminal_Revision {
			sequence = session.next_event_sequence
			if sequence == 0 do return 0, false, failure_record(.Process, .Event_Limit)
			session.next_event_sequence += 1
			last.sequence = sequence
			last.values = values
			last.flags |= 1
			return sequence, true, {}
		}
	}
	dropped_events, dropped_bytes := u64(0), u64(0)
	reserve_entries := 1
	if len(session.events) >= int(state.event_limits.event_entries) ||
	   session.event_bytes + u64(len(payload)) > state.event_limits.event_bytes ||
	   state.event_entries + 1 > state.event_limits.aggregate_event_entries ||
	   state.event_bytes + u64(len(payload)) > state.event_limits.aggregate_event_bytes {
		reserve_entries = 2
	}
	for len(session.events) + reserve_entries > int(state.event_limits.event_entries) ||
	    session.event_bytes + u64(len(payload)) > state.event_limits.event_bytes ||
	    state.event_entries + u64(reserve_entries) > state.event_limits.aggregate_event_entries ||
	    state.event_bytes + u64(len(payload)) > state.event_limits.aggregate_event_bytes {
		if len(session.events) == 0 do break
		dropped_events += 1
		dropped_bytes += u64(len(session.events[0].payload))
		terminal_event_drop_first(state, session)
	}
	if dropped_events > 0 {
		overflow_sequence := session.next_event_sequence
		if overflow_sequence == 0 do return 0, false, failure_record(.Process, .Event_Limit)
		session.next_event_sequence += 1
		overflow := Event_Record {
			ref = ref, sequence = overflow_sequence, kind = .Overflow,
			provider = event_provider("terminal"), values = {dropped_events, dropped_bytes, 0, 0}, flags = 1,
		}
		if !terminal_event_store(state, session, overflow) {
			return 0, false, failure_record(.Process, .Allocation)
		}
	}
	sequence = session.next_event_sequence
	if sequence == 0 do return 0, false, failure_record(.Process, .Event_Limit)
	session.next_event_sequence += 1
	owned_payload: []u8
	if len(payload) > 0 {
		allocation_error: base_runtime.Allocator_Error
		owned_payload, allocation_error = make([]u8, len(payload), state.allocator)
		if allocation_error != nil do return 0, false, failure_record(.Process, .Allocation)
		copy(owned_payload, payload)
	}
	event := Event_Record {
		ref = ref, sequence = sequence, kind = kind,
		provider = event_provider(provider), values = values,
		signed_value = signed_value, flags = flags, payload = owned_payload,
	}
	if !terminal_event_store(state, session, event) {
		if owned_payload != nil do delete(owned_payload, state.allocator)
		return 0, false, failure_record(.Process, .Allocation)
	}
	return sequence, true, {}
}

@(private)
terminal_event_publish :: proc(
	state: ^Registry_State,
	session: ^Session_State,
	kind: Event_Kind,
	provider: string,
	values: [4]u64 = {},
	signed_value: i32 = 0,
	flags: u8 = 0,
	payload: []u8 = nil,
) {
	registry := Registry{state = state}
	_, _, _ = registry_event_append(
		&registry, session.record.ref, kind, provider, values,
		signed_value, flags, payload,
	)
}

@(private)
terminal_event_publish_output :: proc(
	state: ^Registry_State,
	session: ^Session_State,
	bytes: []u8,
	semantic_sequence_before: u64,
	active_command_before: u64,
) {
	terminal_event_publish(state, session, .Raw_Output, "terminal", payload = bytes)
	plain := utf8.valid_string(string(bytes))
	if plain {
		for byte in bytes {
			if byte < 0x20 && byte != '\n' && byte != '\r' && byte != '\t' {
				plain = false
				break
			}
		}
	}
	if plain do terminal_event_publish(state, session, .Normalized_Text, "terminal", payload = bytes)
	if session.semantic.active_command_sequence != 0 &&
	   session.semantic.active_command_sequence != active_command_before {
		terminal_event_publish(
			state, session, .Command_Boundary, "shell-integration",
			{1, session.semantic.active_command_sequence, 0, 0},
		)
	}
	for prompt in session.semantic.prompts[:session.semantic.prompt_count] {
		if prompt.sequence < semantic_sequence_before do continue
		row, column, result := terminal_emulator.semantic_anchor_resolve(session.record.emulator, prompt.anchor)
		if result == .OK {
			terminal_event_publish(
				state, session, .Prompt_Boundary, "shell-integration",
				{row, u64(column), prompt.sequence, 0},
			)
		}
	}
	for result in session.semantic.results[:session.semantic.result_count] {
		if result.sequence < semantic_sequence_before do continue
		flags: u8
		if result.exit_status_present do flags |= 2
		terminal_event_publish(
			state, session, .Command_Boundary, "shell-integration",
			{2, result.sequence, result.output_start_bytes, result.output_end_bytes},
			result.exit_status, flags,
		)
	}
}

/* registry_event_next_subscription chooses one fair subscriber with pending observations. */
registry_event_next_subscription :: proc(
	registry: ^Registry,
) -> (Subscription_Record, bool, Failure_Record) {
	state := registry_state(registry)
	if state == nil do return {}, false, registry_access_failure(registry, .Process)
	for offset in 0 ..< MAX_SUBSCRIBERS {
		index := (int(state.next_subscription_cursor) + offset) % MAX_SUBSCRIBERS
		subscription := &state.subscriptions[index]
		if !subscription.occupied || !subscription.record.active ||
		   !terminal_subscription_pending(state, subscription) {
			continue
		}
		state.next_subscription_cursor = u8((index + 1) % MAX_SUBSCRIBERS)
		return subscription.record, true, {}
	}
	return {}, false, {}
}

/* registry_event_pending reports whether one active subscriber has queued observations. */
registry_event_pending :: proc(registry: ^Registry) -> bool {
	state := registry_state(registry)
	if state == nil do return false
	for &subscription in state.subscriptions {
		if subscription.occupied && subscription.record.active &&
		   terminal_subscription_pending(state, &subscription) {
			return true
		}
	}
	return false
}

/* registry_event_can_configure validates one policy against immutable and live bounds. */
registry_event_can_configure :: proc(
	registry: ^Registry,
	limits: Event_Limits,
) -> (bool, Failure_Record) {
	state := registry_state(registry)
	if state == nil do return false, registry_access_failure(registry, .Process)
	if !event_limits_valid(limits) {
		return false, failure_record(.Process, .Invalid_Argument)
	}
	if state.event_entries > limits.aggregate_event_entries ||
	   state.event_bytes > limits.aggregate_event_bytes {
		return false, failure_record(
			.Process, .Event_Limit, limit = limits.aggregate_event_bytes,
			actual = state.event_bytes,
		)
	}
	if state.subscriber_count > limits.subscribers {
		return false, failure_record(
			.Process, .Subscriber_Limit, limit = u64(limits.subscribers),
			actual = u64(state.subscriber_count),
		)
	}
	for session in state.entries {
		if session == nil || !session.occupied do continue
		if len(session.events) > int(limits.event_entries) ||
		   session.event_bytes > limits.event_bytes {
			return false, failure_record(
				.Process, .Event_Limit, limit = limits.event_bytes,
				actual = session.event_bytes,
			)
		}
		if terminal_subscriber_count(state, session.record.ref) > limits.subscribers_per_session {
			return false, failure_record(
				.Process, .Subscriber_Limit,
				limit = u64(limits.subscribers_per_session),
				actual = u64(terminal_subscriber_count(state, session.record.ref)),
			)
		}
	}
	return true, {}
}

/* registry_event_configure atomically publishes one already valid event policy. */
registry_event_configure :: proc(
	registry: ^Registry,
	limits: Event_Limits,
) -> (bool, Failure_Record) {
	valid, failure := registry_event_can_configure(registry, limits)
	if !valid do return false, failure
	state := registry_state(registry)
	state.event_limits = limits
	return true, {}
}

/* registry_event_snapshot copies one bounded batch without advancing its subscription. */
registry_event_snapshot :: proc(
	registry: ^Registry,
	ref: Subscription_Ref,
	events: []Event_Record,
	payload: []u8,
) -> (batch: Event_Batch, ok: bool, failure: Failure_Record) {
	state := registry_state(registry)
	if state == nil do return {}, false, registry_access_failure(registry, .Process)
	subscription := terminal_subscription_resolve(state, ref)
	if subscription == nil do return {}, false, failure_record(.Process, .Stale_Reference)
	if !subscription.record.active do return {}, false, subscription.record.failure
	limit_events := min(int(subscription.record.batch_events), len(events), MAX_EVENT_BATCH_ENTRIES)
	limit_bytes := min(subscription.record.batch_bytes, u64(len(payload)), u64(MAX_EVENT_BATCH_BYTES))
	batch.subscription = ref
	batch.events = events
	batch.payload = payload
	for session_index in 0 ..< int(subscription.record.session_count) {
		session_ref := subscription.sessions[session_index]
		session := terminal_event_session(state, session_ref)
		if session == nil do return {}, false, failure_record(.Process, .Stale_Reference)
		cursor := subscription.cursors[session_index]
		if len(session.events) > 0 && session.events[0].sequence > cursor + 1 &&
		   int(batch.event_count) < limit_events {
			batch.events[batch.event_count] = Event_Record {
				ref = session_ref,
				sequence = session.events[0].sequence - 1,
				kind = .Overflow,
				provider = event_provider("terminal"),
				values = {session.events[0].sequence - cursor - 1, 0, 0, 0},
				flags = 1,
			}
			batch.event_count += 1
		}
		for &event in session.events {
			if event.sequence <= cursor do continue
			if int(batch.event_count) >= limit_events do return batch, true, {}
			expected_sequence := cursor + 1
			if event.kind not_in subscription.kinds && event.kind != .Overflow ||
			   (event.kind == .Raw_Output && !subscription.raw_output) {
				cursor = event.sequence
				batch.sessions[session_index] = session_ref
				batch.cursors[session_index] = cursor
				batch.session_count = max(batch.session_count, u8(session_index + 1))
				continue
			}
			copy_length := len(event.payload)
			truncated := false
			if batch.payload_bytes + u64(copy_length) > limit_bytes {
				if batch.event_count > 0 do return batch, true, {}
				if event.kind != .Normalized_Text && event.kind != .Raw_Output {
					return {}, false, failure_record(
						.Process, .Event_Limit, limit = limit_bytes,
						actual = u64(copy_length),
					)
				}
				copy_length = int(limit_bytes - batch.payload_bytes)
				if event.kind == .Normalized_Text {
					for copy_length > 0 && !utf8.valid_string(string(event.payload[:copy_length])) {
						copy_length -= 1
					}
				}
				truncated = true
			}
			cursor = event.sequence
			batch.sessions[session_index] = session_ref
			batch.cursors[session_index] = cursor
			batch.session_count = max(batch.session_count, u8(session_index + 1))
			copied := event
			if truncated {
				if event.kind == .Normalized_Text do copied.flags |= 4
				if event.kind == .Raw_Output do copied.flags |= 2
			}
			if copy_length > 0 {
				start := int(batch.payload_bytes)
				copy(payload[start:], event.payload[:copy_length])
				copied.payload = payload[start:start + copy_length]
				batch.payload_bytes += u64(copy_length)
			} else {
				copied.payload = nil
			}
			if event.sequence != expected_sequence do copied.flags |= 1
			events[batch.event_count] = copied
			batch.event_count += 1
		}
	}
	return batch, true, {}
}

/* registry_event_ack advances only the exact successfully delivered batch. */
registry_event_ack :: proc(
	registry: ^Registry,
	batch: Event_Batch,
) -> (bool, Failure_Record) {
	state := registry_state(registry)
	if state == nil do return false, registry_access_failure(registry, .Process)
	subscription := terminal_subscription_resolve(state, batch.subscription)
	if subscription == nil do return false, failure_record(.Process, .Stale_Reference)
	for index in 0 ..< int(batch.session_count) {
		if batch.sessions[index] != subscription.sessions[index] ||
		   batch.cursors[index] < subscription.cursors[index] {
			return false, failure_record(.Process, .Invalid_Argument)
		}
		subscription.cursors[index] = batch.cursors[index]
	}
	terminal_event_reclaim_all(state)
	return true, {}
}

/* registry_event_reject disables one subscriber generation without affecting sessions. */
registry_event_reject :: proc(
	registry: ^Registry,
	ref: Subscription_Ref,
	failure: Failure_Record,
) -> (bool, Failure_Record) {
	state := registry_state(registry)
	if state == nil do return false, registry_access_failure(registry, .Process)
	subscription := terminal_subscription_resolve(state, ref)
	if subscription == nil do return false, failure_record(.Process, .Stale_Reference)
	if subscription.record.active do state.subscriber_count -= 1
	subscription.record.active = false
	subscription.record.failure = failure
	terminal_event_reclaim_all(state)
	return true, {}
}

@(private)
subscription_definition_valid :: proc(definition: Subscription_Definition) -> bool {
	return len(definition.sessions) > 0 && len(definition.sessions) <= MAX_SESSIONS &&
		len(definition.handler) > 0 && len(definition.handler) <= MAX_EVENT_PROVIDER_BYTES &&
		definition.kinds != {} &&
		definition.raw_output == (.Raw_Output in definition.kinds) &&
		definition.batch_events > 0 && definition.batch_events <= MAX_EVENT_BATCH_ENTRIES &&
		definition.batch_bytes > 0 && definition.batch_bytes <= MAX_EVENT_BATCH_BYTES &&
		definition.turn_milliseconds > 0 && definition.turn_milliseconds <= MAX_SUBSCRIBER_TURN_MILLISECONDS &&
		definition.temporary_memory_bytes > 0 && definition.temporary_memory_bytes <= MAX_SUBSCRIBER_TEMPORARY_BYTES
}

@(private)
event_request_valid :: proc(kind: Event_Kind, provider: string, payload: []u8) -> bool {
	if kind == .Invalid || len(provider) == 0 || len(provider) > MAX_EVENT_PROVIDER_BYTES do return false
	if kind == .Normalized_Text || kind == .Working_Context || kind == .Title || kind == .Result_Location {
		return utf8.valid_string(string(payload))
	}
	return true
}

@(private)
event_provider :: proc(value: string) -> Event_Provider {
	provider: Event_Provider
	provider.length = u8(min(len(value), MAX_EVENT_PROVIDER_BYTES))
	copy(provider.bytes[:provider.length], transmute([]u8)value)
	return provider
}

@(private)
terminal_event_store :: proc(state: ^Registry_State, session: ^Session_State, event: Event_Record) -> bool {
	if _, append_error := append(&session.events, event); append_error != nil do return false
	session.event_bytes += u64(len(event.payload))
	state.event_entries += 1
	state.event_bytes += u64(len(event.payload))
	return true
}

@(private)
terminal_event_drop_first :: proc(state: ^Registry_State, session: ^Session_State) {
	if len(session.events) == 0 do return
	event := session.events[0]
	bytes := u64(len(event.payload))
	if event.payload != nil do delete(event.payload, state.allocator)
	copy(session.events[0:], session.events[1:])
	_ = pop(&session.events)
	session.event_bytes -= bytes
	state.event_entries -= 1
	state.event_bytes -= bytes
}

@(private)
terminal_event_session :: proc(state: ^Registry_State, ref: Session_Ref) -> ^Session_State {
	session, resolved := registry_resolve(state, ref)
	if !resolved do return nil
	return session
}

@(private)
terminal_subscription_free_index :: proc(state: ^Registry_State) -> int {
	for &subscription, index in state.subscriptions do if !subscription.occupied do return index
	return -1
}

@(private)
terminal_subscription_resolve :: proc(state: ^Registry_State, ref: Subscription_Ref) -> ^Subscription_State {
	if ref.id == 0 || ref.generation == 0 || u32(ref.id) > MAX_SUBSCRIBERS do return nil
	index := int(u32(ref.id) - 1)
	subscription := &state.subscriptions[index]
	if !subscription.occupied || subscription.record.ref != ref || state.subscription_generations[index] != ref.generation do return nil
	return subscription
}

@(private)
terminal_subscriber_count :: proc(state: ^Registry_State, ref: Session_Ref) -> u16 {
	count: u16
	for &subscription in state.subscriptions {
		if !subscription.occupied || !subscription.record.active do continue
		for index in 0 ..< int(subscription.record.session_count) {
			if subscription.sessions[index] == ref {
				count += 1
				break
			}
		}
	}
	return count
}

@(private)
terminal_event_subscriber_present :: proc(
	state: ^Registry_State,
	ref: Session_Ref,
	kind: Event_Kind,
) -> bool {
	for &subscription in state.subscriptions {
		if !subscription.occupied || !subscription.record.active ||
		   kind not_in subscription.kinds ||
		   (kind == .Raw_Output && !subscription.raw_output) {
			continue
		}
		for index in 0 ..< int(subscription.record.session_count) do if subscription.sessions[index] == ref do return true
	}
	return false
}

@(private)
event_limits_valid :: proc(limits: Event_Limits) -> bool {
	return limits.event_entries >= 64 && limits.event_entries <= MAX_EVENT_ENTRIES &&
		limits.event_bytes >= 64 * 1_024 && limits.event_bytes <= MAX_EVENT_BYTES &&
		limits.aggregate_event_entries >= u64(limits.event_entries) &&
		limits.aggregate_event_entries <= MAX_AGGREGATE_EVENT_ENTRIES &&
		limits.aggregate_event_bytes >= limits.event_bytes &&
		limits.aggregate_event_bytes <= MAX_AGGREGATE_EVENT_BYTES &&
		limits.subscribers_per_session > 0 &&
		limits.subscribers_per_session <= MAX_SUBSCRIBERS_PER_SESSION &&
		limits.subscribers >= limits.subscribers_per_session &&
		limits.subscribers <= MAX_SUBSCRIBERS
}

@(private)
terminal_subscription_pending :: proc(state: ^Registry_State, subscription: ^Subscription_State) -> bool {
	for index in 0 ..< int(subscription.record.session_count) {
		session := terminal_event_session(state, subscription.sessions[index])
		if session == nil do continue
		for &event in session.events do if event.sequence > subscription.cursors[index] do return true
	}
	return false
}

@(private)
terminal_subscription_close :: proc(state: ^Registry_State, subscription: ^Subscription_State) {
	if !subscription.occupied do return
	if subscription.record.active do state.subscriber_count -= 1
	subscription^ = {}
}

@(private)
terminal_event_reclaim_all :: proc(state: ^Registry_State) {
	for session in state.entries {
		if session == nil || !session.occupied do continue
		minimum := session.next_event_sequence - 1
		found := false
		for &subscription in state.subscriptions {
			if !subscription.occupied || !subscription.record.active do continue
			for index in 0 ..< int(subscription.record.session_count) {
				if subscription.sessions[index] == session.record.ref {
					minimum = min(minimum, subscription.cursors[index])
					found = true
				}
			}
		}
		if !found do minimum = session.next_event_sequence - 1
		for len(session.events) > 0 && session.events[0].sequence <= minimum do terminal_event_drop_first(state, session)
	}
}

@(private)
registry_event_session_close :: proc(state: ^Registry_State, ref: Session_Ref) {
	for &subscription in state.subscriptions {
		if !subscription.occupied do continue
		for index in 0 ..< int(subscription.record.session_count) {
			if subscription.sessions[index] == ref {
				terminal_subscription_close(state, &subscription)
				break
			}
		}
	}
	session := terminal_event_session(state, ref)
	if session == nil do return
	for len(session.events) > 0 do terminal_event_drop_first(state, session)
}
