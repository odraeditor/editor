// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package terminal_session

import "core:testing"

@(test)
/* Verifies filtered batches preserve order, copied payloads, gaps, and explicit acknowledgment. */
event_delivery_is_bounded_and_generation_scoped :: proc(t: ^testing.T) {
	registry, ref, ready := terminal_event_test_registry(t)
	if !ready do return
	defer terminal_event_test_registry_close(&registry, ref)

	definition := Subscription_Definition {
		sessions = []Session_Ref{ref},
		kinds = {.Normalized_Text, .Terminal_Revision},
		handler = "test-handler",
		batch_events = 4,
		batch_bytes = 64,
		turn_milliseconds = 10,
		temporary_memory_bytes = 4 * 1_024 * 1_024,
	}
	subscription, subscribed, subscribe_failure := registry_subscribe(&registry, definition)
	testing.expectf(t, subscribed, "subscription failed: %v", subscribe_failure.code)
	if !subscribed do return

	mutable := []u8{'o', 'n', 'e'}
	_, queued, _ := registry_event_append(&registry, ref, .Normalized_Text, "adapter", payload = mutable)
	testing.expect(t, queued)
	mutable[0] = 'X'
	_, _, _ = registry_event_append(&registry, ref, .Raw_Output, "terminal", payload = []u8{0xff})
	_, _, _ = registry_event_append(&registry, ref, .Terminal_Revision, "terminal", {7, 0, 0, 0})
	_, _, _ = registry_event_append(&registry, ref, .Terminal_Revision, "terminal", {8, 0, 0, 0})

	events: [4]Event_Record
	payload: [64]u8
	batch, copied, copy_failure := registry_event_snapshot(
		&registry, subscription.ref, events[:], payload[:],
	)
	testing.expectf(t, copied, "event snapshot failed: %v", copy_failure.code)
	if !copied do return
	testing.expect_value(t, batch.event_count, u16(2))
	testing.expect_value(t, string(batch.events[0].payload), "one")
	testing.expect_value(t, batch.events[1].kind, Event_Kind.Terminal_Revision)
	testing.expect_value(t, batch.events[1].values[0], u64(8))
	testing.expect(t, batch.events[1].flags & 1 != 0)
	acked, ack_failure := registry_event_ack(&registry, batch)
	testing.expectf(t, acked, "event acknowledgment failed: %v", ack_failure.code)
	large: [80]u8
	for &byte in large do byte = 'x'
	_, queued, _ = registry_event_append(&registry, ref, .Normalized_Text, "adapter", payload = large[:])
	truncated, truncated_ok, _ := registry_event_snapshot(
		&registry, subscription.ref, events[:], payload[:],
	)
	testing.expect(t, truncated_ok)
	if truncated_ok && truncated.event_count == 1 {
		testing.expect_value(t, len(truncated.events[0].payload), len(payload))
		testing.expect(t, truncated.events[0].flags & 4 != 0)
		_, _ = registry_event_ack(&registry, truncated)
	}
	_, pending, _ := registry_event_next_subscription(&registry)
	testing.expect(t, !pending)
	unsubscribed, unsubscribe_failure := registry_unsubscribe(&registry, subscription.ref)
	testing.expectf(t, unsubscribed, "unsubscribe failed: %v", unsubscribe_failure.code)
	_, stale, stale_failure := registry_subscription_record(&registry, subscription.ref)
	testing.expect(t, !stale)
	testing.expect_value(t, stale_failure.code, Failure_Code.Stale_Reference)
}

@(test)
/* Verifies overload reports overflow while preserving terminal-session ownership. */
event_overflow_and_subscriber_failure_do_not_close_session :: proc(t: ^testing.T) {
	registry, ref, ready := terminal_event_test_registry(t)
	if !ready do return
	defer terminal_event_test_registry_close(&registry, ref)

	definition := Subscription_Definition {
		sessions = []Session_Ref{ref},
		kinds = {.Bell},
		handler = "slow-handler",
		batch_events = MAX_EVENT_BATCH_ENTRIES,
		batch_bytes = MAX_EVENT_BATCH_BYTES,
		turn_milliseconds = MAX_SUBSCRIBER_TURN_MILLISECONDS,
		temporary_memory_bytes = MAX_SUBSCRIBER_TEMPORARY_BYTES,
	}
	subscription, subscribed, _ := registry_subscribe(&registry, definition)
	testing.expect(t, subscribed)
	if !subscribed do return
	for index in 0 ..< OPERATING_EVENT_ENTRIES + 8 {
		_, queued, _ := registry_event_append(
			&registry, ref, .Bell, "terminal", {u64(index), 1, 0, 0},
		)
		testing.expect(t, queued)
	}
	events: [MAX_EVENT_BATCH_ENTRIES]Event_Record
	payload: [1]u8
	batch, copied, _ := registry_event_snapshot(&registry, subscription.ref, events[:], payload[:])
	testing.expect(t, copied)
	overflow := false
	for event, index in batch.events[:batch.event_count] {
		if event.kind == .Overflow do overflow = true
		if index > 0 do testing.expect(t, batch.events[index - 1].sequence < event.sequence)
	}
	testing.expect(t, overflow)
	rejected, reject_failure := registry_event_reject(
		&registry, subscription.ref,
		failure_record(.Process, .Event_Limit, limit = 10, actual = 11),
	)
	testing.expectf(t, rejected, "subscriber rejection failed: %v", reject_failure.code)
	testing.expect_value(t, registry_state(&registry).subscriber_count, u16(0))
	record, current, record_failure := registry_record(&registry, ref)
	testing.expectf(t, current, "subscriber failure closed session: %v", record_failure.code)
	if current do testing.expect_value(t, record.lifecycle, Lifecycle.Running)
	inspection, inspected, _ := registry_subscription_record(&registry, subscription.ref)
	testing.expect(t, inspected)
	if inspected {
		testing.expect(t, !inspection.active)
		testing.expect_value(t, inspection.failure.code, Failure_Code.Event_Limit)
	}
}

@(test)
/* Verifies policy changes honor ceilings and preserve the last valid live configuration. */
event_configuration_is_atomic_across_static_and_live_bounds :: proc(t: ^testing.T) {
	registry, ref, ready := terminal_event_test_registry(t)
	if !ready do return
	defer terminal_event_test_registry_close(&registry, ref)

	upward := DEFAULT_EVENT_LIMITS
	upward.event_entries = MAX_EVENT_ENTRIES
	upward.event_bytes = MAX_EVENT_BYTES
	configured, configure_failure := registry_event_configure(&registry, upward)
	testing.expectf(t, configured, "upward configuration failed: %v", configure_failure.code)
	if !configured do return
	testing.expect_value(t, registry_state(&registry).event_limits, upward)

	invalid := upward
	invalid.event_entries = 63
	configured, configure_failure = registry_event_configure(&registry, invalid)
	testing.expect(t, !configured)
	testing.expect_value(t, configure_failure.code, Failure_Code.Invalid_Argument)
	testing.expect_value(t, registry_state(&registry).event_limits, upward)

	definition := Subscription_Definition {
		sessions = []Session_Ref{ref},
		kinds = {.Bell},
		handler = "policy-handler",
		batch_events = 1,
		batch_bytes = 1,
		turn_milliseconds = 1,
		temporary_memory_bytes = 1,
	}
	subscription, subscribed, subscribe_failure := registry_subscribe(&registry, definition)
	testing.expectf(t, subscribed, "subscription failed: %v", subscribe_failure.code)
	if !subscribed do return
	defer {_, _ = registry_unsubscribe(&registry, subscription.ref)}
	for index in 0 ..< 65 {
		_, queued, queue_failure := registry_event_append(
			&registry, ref, .Bell, "terminal", {u64(index), 0, 0, 0},
		)
		testing.expectf(t, queued, "event append failed: %v", queue_failure.code)
	}
	downward := upward
	downward.event_entries = 64
	configured, configure_failure = registry_event_configure(&registry, downward)
	testing.expect(t, !configured)
	testing.expect_value(t, configure_failure.code, Failure_Code.Event_Limit)
	testing.expect_value(t, registry_state(&registry).event_limits, upward)
}

@(private)
terminal_event_test_registry :: proc(t: ^testing.T) -> (Registry, Session_Ref, bool) {
	registry: Registry
	initialized, failure := registry_init(&registry)
	testing.expectf(t, initialized, "registry initialization failed: %v", failure.code)
	if !initialized do return {}, {}, false
	state := registry_state(&registry)
	session, allocation_error := new(Session_State, state.allocator)
	if allocation_error != nil {
		_, _ = registry_close(&registry)
		testing.expect(t, false)
		return {}, {}, false
	}
	events: [dynamic]Event_Record
	events, allocation_error = make([dynamic]Event_Record, 0, 0, state.allocator)
	if allocation_error != nil {
		free(session, state.allocator)
		_, _ = registry_close(&registry)
		testing.expect(t, false)
		return {}, {}, false
	}
	ref := Session_Ref{id = 1, generation = 1}
	session^ = {record = {ref = ref, lifecycle = .Running}, events = events,
		next_event_sequence = 1, occupied = true}
	state.entries[0] = session
	state.generations[0] = ref.generation
	return registry, ref, true
}

@(private)
terminal_event_test_registry_close :: proc(registry: ^Registry, ref: Session_Ref) {
	state := registry_state(registry)
	if state != nil {
		session := terminal_event_session(state, ref)
		if session != nil {
			registry_event_session_close(state, ref)
			delete(session.events)
			free(session, state.allocator)
			state.entries[0] = nil
		}
	}
	_, _ = registry_close(registry)
}
