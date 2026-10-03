// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../bridge"
import "../hosting"
import "../interactive_session"
import "../terminal_emulator"
import "../terminal_session"
import "core:encoding/endian"
import "core:os"
import "core:strings"
import "core:testing"
import "core:time"

/* Verifies the runtime bridge lists only explicitly authorized copied sessions. */
verify_racket_terminal_capability :: proc(t: ^testing.T, racket_runtime: ^hosting.Runtime) {
	registry: terminal_session.Registry
	ready, ready_failure := terminal_session.registry_init(&registry)
	testing.expectf(t, ready, "terminal registry initialization failed: %v", ready_failure.code)
	if !ready do return
	defer terminal_session.registry_close(&registry)

	capability := Terminal_Capability_Context {
		registry = &registry,
		authority_generation = 101,
		access = {.Inspect, .Input, .Terminate, .Subscribe},
		now_nanoseconds = 1,
	}
	turn, executed, failure := racket_terminal_turn(racket_runtime, capability, 0)
	testing.expectf(t, executed, "terminal capability turn failed: %v", failure)
	if executed do testing.expect_value(t, turn.calls, u16(1))
	delivery_turn, delivery_executed, delivery_failure := racket_terminal_delivery_turn(
		racket_runtime, capability,
	)
	testing.expectf(t, delivery_executed, "terminal delivery turn failed: %v", delivery_failure)
	if delivery_executed do testing.expect_value(t, delivery_turn.calls, u16(1))

	without_runtime: hosting.Runtime
	_, unavailable, unavailable_failure := racket_terminal_turn(&without_runtime, capability, 0)
	testing.expect(t, !unavailable)
	testing.expect_value(t, unavailable_failure, bridge.Terminal_Capability_Failure_Code.Unavailable)

	cancelled := capability
	cancelled.cancelled = true
	_, cancellation_ok, cancellation_failure := racket_terminal_turn(racket_runtime, cancelled, 0)
	testing.expect(t, !cancellation_ok)
	testing.expect_value(t, cancellation_failure, bridge.Terminal_Capability_Failure_Code.Cancelled)

	restricted := capability
	restricted.access = {}
	_, authorized, authority_failure := racket_terminal_turn(racket_runtime, restricted, 0)
	testing.expect(t, !authorized)
	testing.expect_value(t, authority_failure, bridge.Terminal_Capability_Failure_Code.Denied)

	call := Racket_Terminal_Call{ctx = capability, token = 109}
	delivery: [bridge.TERMINAL_SUBSCRIPTION_RECORD_BYTES + terminal_session.MAX_EVENT_PROVIDER_BYTES]u8
	status, failure_code := terminal_test_callback(&call, .Delivery_Next, 0, 0, nil, delivery[:])
	testing.expect_value(t, status, i32(0))
	testing.expect_value(t, failure_code, u32(bridge.Terminal_Capability_Failure_Code.None))

	before, inspected, _ := terminal_session.registry_inspect(&registry)
	testing.expect(t, inspected)
	malformed_key: [bridge.TERMINAL_KEY_RECORD_BYTES]u8
	status, failure_code = terminal_test_callback(
		&call, .Send_Key, 77, 79, malformed_key[:], nil,
	)
	testing.expect_value(t, status, i32(1))
	testing.expect_value(t, failure_code, u32(bridge.Terminal_Capability_Failure_Code.Stale))
	after, inspected_after, _ := terminal_session.registry_inspect(&registry)
	testing.expect(t, inspected_after)
	testing.expect_value(t, after, before)
}

/* Verifies one PTY supports independent human and structured consumers through checked hosting calls. */
verify_structured_terminal_integration :: proc(t: ^testing.T) {
	working_directory, working_directory_error := os.get_working_directory(context.temp_allocator)
	testing.expect(t, working_directory_error == nil)
	if working_directory_error != nil do return
	fixture, fixture_error := os.join_path(
		{working_directory, "tests/fixtures/terminal-structured-adapter.rkt"},
		context.temp_allocator,
	)
	testing.expect(t, fixture_error == nil)
	if fixture_error != nil do return

	registry: terminal_session.Registry
	initialized, initialize_failure := terminal_session.registry_init(&registry)
	testing.expectf(t, initialized, "terminal registry initialization failed: %v", initialize_failure.code)
	if !initialized do return
	defer if registry.state != nil do terminal_session.registry_close(&registry)
	request := terminal_session.Open_Request {
		process = {
			name = "structured-fixture",
			owner_kind = .Language_Integration,
			owner_label = "provider-neutral structured fixture",
			working_directory = working_directory,
			limits = interactive_session.DEFAULT_LIMITS,
			make_default = true,
		},
		start = {
			executable = "/usr/bin/racket",
			arguments = []string{fixture},
			working_directory = working_directory,
			columns = 80,
			rows = 24,
		},
		emulator = terminal_emulator.DEFAULT_OPTIONS,
		limits = terminal_session.DEFAULT_LIMITS,
	}
	record, opened, open_failure := terminal_session.registry_open(&registry, request)
	testing.expectf(t, opened, "structured fixture failed to open: %v", open_failure)
	if !opened do return

	sessions := [1]Terminal_Capability_Session{{
		ref = record.ref,
		scope = .Instance,
		workspace_identity = "structured-workspace",
		project_identity = "structured-project",
		title = "Structured fixture",
	}}
	call := Racket_Terminal_Call {
		ctx = {
			registry = &registry,
			sessions = sessions[:],
			authority_generation = 401,
			access = {.Inspect, .Input, .Terminate, .Subscribe},
			now_nanoseconds = 1,
		},
		token = 409,
	}
	structured_subscription, structured_subscribed := terminal_test_subscribe(
		&call, record.ref, .Raw_Output, true, "structured-adapter",
	)
	testing.expect(t, structured_subscribed)
	human_subscription, human_subscribed := terminal_test_subscribe(
		&call, record.ref, .Terminal_Revision, false, "human-projection",
	)
	testing.expect(t, human_subscribed)
	if !structured_subscribed || !human_subscribed do return

	ready := terminal_test_wait_for_text(&registry, record.ref, "human:ready", 2_000)
	testing.expect(t, ready)
	if !ready do return
	matched, malformed := terminal_test_wait_for_protocol(
		&registry, record.ref, structured_subscription,
		"ODRA/1 response 0 ready", 2_000,
	)
	testing.expect(t, matched)
	testing.expect(t, malformed)
	_, human_copied := terminal_test_collect_events(
		&registry, human_subscription, nil, .Terminal_Revision,
	)
	testing.expect(t, human_copied)

	before_cancel, before_cancel_ok, _ := terminal_session.registry_record(&registry, record.ref)
	testing.expect(t, before_cancel_ok)
	call.ctx.cancelled = true
	cancelled_request := "request 8 cancelled\n"
	status, failure_code := terminal_test_callback(
		&call, .Send_Text, u64(record.ref.id), u64(record.ref.generation),
		transmute([]u8)cancelled_request, nil,
	)
	testing.expect_value(t, status, i32(1))
	testing.expect_value(t, failure_code, u32(bridge.Terminal_Capability_Failure_Code.Cancelled))
	call.ctx.cancelled = false
	after_cancel, after_cancel_ok, _ := terminal_session.registry_record(&registry, record.ref)
	testing.expect(t, after_cancel_ok)
	if before_cancel_ok && after_cancel_ok {
		testing.expect_value(
			t, after_cancel.process.resources.queued_input_bytes,
			before_cancel.process.resources.queued_input_bytes,
		)
	}

	request_input := "request 7 alpha\n"
	status, failure_code = terminal_test_callback(
		&call, .Send_Text, u64(record.ref.id), u64(record.ref.generation),
		transmute([]u8)request_input, nil,
	)
	testing.expect_value(t, status, i32(0))
	testing.expect_value(t, failure_code, u32(bridge.Terminal_Capability_Failure_Code.None))
	responded := terminal_test_wait_for_text(
		&registry, record.ref, "human:request:alpha", 2_000,
	)
	testing.expect(t, responded)
	if !responded do return
	matched, _ = terminal_test_wait_for_protocol(
		&registry, record.ref, structured_subscription,
		"ODRA/1 response 7 alpha", 2_000,
	)
	testing.expect(t, matched)
	_, human_copied = terminal_test_collect_events(
		&registry, human_subscription, nil, .Terminal_Revision,
	)
	testing.expect(t, human_copied)

	limits := terminal_session.DEFAULT_EVENT_LIMITS
	limits.event_entries = 64
	configured, configuration_failure := terminal_session.registry_event_configure(&registry, limits)
	testing.expectf(t, configured, "event policy failed: %v", configuration_failure.code)
	if configured {
		overload_frame := "\x1eODRA/1 response 9 overload\x1f"
		for _ in 0 ..< 80 {
			_, queued, queue_failure := terminal_session.registry_event_append(
				&registry, record.ref, .Raw_Output, "structured-adapter",
				payload = transmute([]u8)overload_frame,
			)
			testing.expectf(t, queued, "structured overload append failed: %v", queue_failure.code)
		}
		events: [64]terminal_session.Event_Record
		payload: [8 * 1_024]u8
		batch, copied, copy_failure := terminal_session.registry_event_snapshot(
			&registry, structured_subscription, events[:], payload[:],
		)
		testing.expectf(t, copied, "structured overload snapshot failed: %v", copy_failure.code)
		if copied {
			saw_overflow := false
			for event in batch.events do saw_overflow = saw_overflow ||
				event.kind == .Overflow || event.flags & 2 != 0
			testing.expect(t, saw_overflow)
			acked, ack_failure := terminal_session.registry_event_ack(&registry, batch)
			testing.expectf(t, acked, "structured overload acknowledgment failed: %v", ack_failure.code)
		}
	}
	current, current_ok, current_failure := terminal_session.registry_record(&registry, record.ref)
	testing.expectf(t, current_ok, "overload invalidated terminal: %v", current_failure.code)
	if current_ok do testing.expect_value(t, current.lifecycle, terminal_session.Lifecycle.Running)

	quit_request := "quit\n"
	status, failure_code = terminal_test_callback(
		&call, .Send_Text, u64(record.ref.id), u64(record.ref.generation),
		transmute([]u8)quit_request, nil,
	)
	testing.expect_value(t, status, i32(0))
	testing.expect_value(t, failure_code, u32(bridge.Terminal_Capability_Failure_Code.None))
	exited := terminal_test_wait_for_exit(&registry, record.ref, 2_000)
	testing.expect(t, exited)
	terminal_test_unsubscribe(t, &call, structured_subscription)
	terminal_test_unsubscribe(t, &call, human_subscription)
	closed, close_failure := terminal_session.registry_close_session(&registry, record.ref)
	testing.expectf(t, closed, "structured fixture close failed: %v", close_failure.code)
	stats, inspected, inspect_failure := terminal_session.registry_inspect(&registry)
	testing.expectf(t, inspected, "terminal teardown inspection failed: %v", inspect_failure.code)
	if inspected do testing.expect_value(t, stats.session_count, u16(0))
}

@(private)
terminal_test_subscribe :: proc(
	call: ^Racket_Terminal_Call,
	ref: terminal_session.Session_Ref,
	kind: terminal_session.Event_Kind,
	raw_output: bool,
	handler: string,
) -> (terminal_session.Subscription_Ref, bool) {
	input: [bridge.TERMINAL_SUBSCRIPTION_HEADER_BYTES + 16 +
		terminal_session.MAX_EVENT_PROVIDER_BYTES]u8
	handler_bytes := transmute([]u8)handler
	handler_offset := int(bridge.TERMINAL_SUBSCRIPTION_HEADER_BYTES) + 16
	values := [10]u64 {
		1,
		u64(1) << u64(kind),
		1 if raw_output else 0,
		64,
		64 * 1_024,
		25,
		8 * 1_024 * 1_024,
		u64(handler_offset),
		u64(len(handler_bytes)),
		bridge.TERMINAL_SUBSCRIPTION_HEADER_BYTES,
	}
	for value, index in values do assert(endian.put_u64(input[index * 8:], .Little, value))
	refs_offset := int(bridge.TERMINAL_SUBSCRIPTION_HEADER_BYTES)
	assert(endian.put_u64(input[refs_offset:], .Little, u64(ref.id)))
	assert(endian.put_u64(input[refs_offset + 8:], .Little, u64(ref.generation)))
	copy(input[handler_offset:], handler_bytes)
	output: [16]u8
	status, failure_code := terminal_test_callback(
		call, .Subscribe, 0, 0,
		input[:handler_offset + len(handler_bytes)], output[:],
	)
	if status != 0 || failure_code != u32(bridge.Terminal_Capability_Failure_Code.None) {
		return {}, false
	}
	id, id_ok := endian.get_u64(output[:], .Little)
	generation, generation_ok := endian.get_u64(output[8:], .Little)
	if !id_ok || !generation_ok || id == 0 || generation == 0 do return {}, false
	return terminal_session.Subscription_Ref {
		id = terminal_session.Subscription_ID(u32(id)),
		generation = terminal_session.Subscription_Generation(u32(generation)),
	}, true
}

@(private)
terminal_test_collect_events :: proc(
	registry: ^terminal_session.Registry,
	subscription: terminal_session.Subscription_Ref,
	output: []u8,
	kind: terminal_session.Event_Kind,
) -> (int, bool) {
	events: [64]terminal_session.Event_Record
	payload: [64 * 1_024]u8
	batch, copied, _ := terminal_session.registry_event_snapshot(
		registry, subscription, events[:], payload[:],
	)
	if !copied do return 0, false
	written := 0
	found := false
	for event in batch.events {
		if event.kind != kind do continue
		found = true
		if written < len(output) {
			written += copy(output[written:], event.payload)
		}
	}
	acked, _ := terminal_session.registry_event_ack(registry, batch)
	return written, found && acked
}

@(private)
terminal_test_structured_protocol :: proc(
	input: []u8,
	expected: string,
) -> (matched, malformed: bool) {
	offset := 0
	for offset < len(input) {
		start := -1
		for index in offset ..< len(input) {
			if input[index] == 0x1e {
				start = index + 1
				break
			}
		}
		if start < 0 do break
		end := -1
		for index in start ..< len(input) {
			if input[index] == 0x1f {
				end = index
				break
			}
		}
		if end < 0 {
			malformed = true
			break
		}
		frame := string(input[start:end])
		if frame == expected do matched = true
		if !strings.has_prefix(frame, "ODRA/1 response ") &&
		   !strings.has_prefix(frame, "ODRA/1 error ") {
			malformed = true
		}
		offset = end + 1
	}
	return
}

@(private)
terminal_test_wait_for_protocol :: proc(
	registry: ^terminal_session.Registry,
	ref: terminal_session.Session_Ref,
	subscription: terminal_session.Subscription_Ref,
	expected: string,
	turn_limit: int,
) -> (matched, malformed: bool) {
	raw: [64 * 1_024]u8
	written := 0
	for turn in 0 ..< turn_limit {
		observation, stepped := terminal_session.registry_step_output(
			registry, ref, i64(turn + 5_000),
		)
		if !stepped do return false, malformed
		if written < len(raw) {
			copied, available := terminal_test_collect_events(
				registry, subscription, raw[written:], .Raw_Output,
			)
			if available do written += copied
		}
		matched_now, malformed_now := terminal_test_structured_protocol(raw[:written], expected)
		malformed = malformed || malformed_now
		if matched_now do return true, malformed
		if !observation.progress do time.sleep(time.Millisecond)
	}
	return false, malformed
}

@(private)
terminal_test_wait_for_text :: proc(
	registry: ^terminal_session.Registry,
	ref: terminal_session.Session_Ref,
	expected: string,
	turn_limit: int,
) -> bool {
	text: [64 * 1_024]u8
	for turn in 0 ..< turn_limit {
		observation, stepped := terminal_session.registry_step_output(
			registry, ref, i64(turn + 1),
		)
		if !stepped do return false
		_, projected, _ := terminal_session.registry_project_render(registry, ref)
		if projected {
			copy_record, copied, _ := terminal_session.registry_copy_text(
				registry, ref,
				terminal_session.Text_Request{scope = .Screen, normalized = true},
				text[:],
			)
			if copied && strings.contains(
				string(text[:int(copy_record.copied_bytes)]), expected,
			) {
				return true
			}
		}
		if !observation.progress do time.sleep(time.Millisecond)
	}
	return false
}

@(private)
terminal_test_wait_for_exit :: proc(
	registry: ^terminal_session.Registry,
	ref: terminal_session.Session_Ref,
	turn_limit: int,
) -> bool {
	for turn in 0 ..< turn_limit {
		observation, stepped := terminal_session.registry_step_output(
			registry, ref, i64(turn + 10_000),
		)
		if !stepped do return false
		record, found, _ := terminal_session.registry_record(registry, ref)
		if found && record.lifecycle == .Exited {
			return record.process.exit_status.kind == .Code && record.process.exit_status.value == 0
		}
		if !observation.progress do time.sleep(time.Millisecond)
	}
	return false
}

@(private)
terminal_test_unsubscribe :: proc(
	t: ^testing.T,
	call: ^Racket_Terminal_Call,
	subscription: terminal_session.Subscription_Ref,
) {
	status, failure_code := terminal_test_callback(
		call, .Unsubscribe, u64(subscription.id), u64(subscription.generation), nil, nil,
	)
	testing.expect_value(t, status, i32(0))
	testing.expect_value(t, failure_code, u32(bridge.Terminal_Capability_Failure_Code.None))
}

@(private)
terminal_test_callback :: proc(
	call: ^Racket_Terminal_Call,
	operation: bridge.Terminal_Capability_Operation,
	arg0, arg1: u64,
	input, output: []u8,
) -> (i32, u32) {
	output_length, value, limit, actual: u64
	failure_code: u32
	input_pointer: ^u8
	if len(input) > 0 do input_pointer = raw_data(input)
	output_pointer: ^u8
	if len(output) > 0 do output_pointer = raw_data(output)
	status := racket_terminal_callback(
		call,
		.Terminal,
		1,
		call.token,
		0,
		i32(operation),
		arg0,
		arg1,
		input_pointer,
		u64(len(input)),
		output_pointer,
		u64(len(output)),
		&output_length,
		&value,
		&failure_code,
		&limit,
		&actual,
	)
	return status, failure_code
}
