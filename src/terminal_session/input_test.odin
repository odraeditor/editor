// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package terminal_session

import "core:testing"
import "../terminal_emulator"

@(private)
test_input_request :: proc(
	key: Input_Key,
	text := "",
	modifiers: Input_Modifiers = {},
	source := Input_Source.Ordinary,
	repeat_count: u16 = 1,
) -> Input_Request {
	return Input_Request {
		kind = .Key,
		key = key,
		action = .Press,
		modifiers = modifiers,
		text = text,
		source = source,
		repeat_count = repeat_count,
	}
}

/* Verifies semantic keys follow active emulator modes before bounded queuing. */
@(test)
input_encodes_semantic_keys_and_application_modes :: proc(t: ^testing.T) {
	registry: Registry
	initialized, _ := registry_init(&registry)
	testing.expect(t, initialized)
	if !initialized do return
	defer if registry.state != nil do _, _ = registry_close(&registry)
	record, opened, failure := registry_open(
		&registry,
		test_open_request("input modes", arguments = []string{"-c", "sleep 2"}),
	)
	testing.expectf(t, opened, "terminal open failed with %v", failure.code)
	if !opened do return

	state := registry_state(&registry)
	session, resolved := registry_resolve(state, record.ref)
	testing.expect(t, resolved)
	if !resolved do return
	first, repeated: [MAX_ENCODED_KEY_BYTES]u8
	count, _, _, encoded_failure := input_encode_request(
		session,
		test_input_request(.Up),
		first[:],
		repeated[:],
	)
	testing.expect_value(t, encoded_failure.code, Failure_Code.None)
	testing.expect_value(t, string(first[:count]), "\x1b[A")
	testing.expect_value(
		t,
		terminal_emulator.write(record.emulator, transmute([]u8)(string("\x1b[?1h"))),
		terminal_emulator.Result.OK,
	)
	count, _, _, encoded_failure = input_encode_request(
		session,
		test_input_request(.Up),
		first[:],
		repeated[:],
	)
	testing.expect_value(t, encoded_failure.code, Failure_Code.None)
	testing.expect_value(t, string(first[:count]), "\x1bOA")

	cases := []struct {key: Input_Key, expected: string} {
		{.Enter, "\r"},
		{.Tab, "\t"},
		{.Backspace, "\x7f"},
		{.Delete, "\x1b[3~"},
		{.Prior, "\x1b[5~"},
		{.Next, "\x1b[6~"},
	}
	for test_case in cases {
		count, _, _, encoded_failure = input_encode_request(
			session,
			test_input_request(test_case.key),
			first[:],
			repeated[:],
		)
		testing.expect_value(t, encoded_failure.code, Failure_Code.None)
		testing.expect_value(t, string(first[:count]), test_case.expected)
	}
	count, _, _, encoded_failure = input_encode_request(
		session,
		test_input_request(.Character, text = "c", modifiers = {.Control}),
		first[:],
		repeated[:],
	)
	testing.expect_value(t, encoded_failure.code, Failure_Code.None)
	testing.expect_value(t, string(first[:count]), "\x03")
}

/* Verifies UTF-8, repeats, literal-next provenance, and focus reports are queued. */
@(test)
input_queues_text_repeats_literals_and_focus :: proc(t: ^testing.T) {
	registry: Registry
	initialized, _ := registry_init(&registry)
	testing.expect(t, initialized)
	if !initialized do return
	defer if registry.state != nil do _, _ = registry_close(&registry)
	record, opened, failure := registry_open(
		&registry,
		test_open_request("input queue", arguments = []string{"-c", "sleep 2"}),
	)
	testing.expectf(t, opened, "terminal open failed with %v", failure.code)
	if !opened do return

	text := Input_Request {
		kind = .Text,
		action = .Press,
		text = "界",
		source = .Literal_Next,
		repeat_count = 3,
	}
	observation, queued, input_failure := registry_send_input(&registry, record.ref, text)
	testing.expectf(t, queued, "UTF-8 input failed with %v", input_failure.code)
	testing.expect_value(t, observation.source, Input_Source.Literal_Next)
	testing.expect_value(t, observation.encoded_bytes, u64(9))
	testing.expect_value(t, observation.queued_bytes, u64(9))
	testing.expect_value(t, observation.queue_bytes, u64(9))

	repeated_key := test_input_request(.Left, repeat_count = 4)
	observation, queued, input_failure = registry_send_input(&registry, record.ref, repeated_key)
	testing.expectf(t, queued, "repeated key failed with %v", input_failure.code)
	testing.expect_value(t, observation.repeat_count, u16(4))
	testing.expect(t, observation.queued_bytes >= 4)

	focus := Input_Request {
		kind = .Focus,
		action = .Press,
		focus = .Gained,
		source = .Ordinary,
		repeat_count = 1,
	}
	observation, queued, input_failure = registry_send_input(&registry, record.ref, focus)
	testing.expectf(t, queued, "disabled focus input failed with %v", input_failure.code)
	testing.expect(t, !observation.focus_reporting)
	testing.expect_value(t, observation.queued_bytes, u64(0))
	testing.expect_value(
		t,
		terminal_emulator.write(record.emulator, transmute([]u8)(string("\x1b[?1004h"))),
		terminal_emulator.Result.OK,
	)
	observation, queued, input_failure = registry_send_input(&registry, record.ref, focus)
	testing.expectf(t, queued, "enabled focus input failed with %v", input_failure.code)
	testing.expect(t, observation.focus_reporting)
	testing.expect_value(t, observation.queued_bytes, u64(3))
}

/* Verifies malformed, oversized, stale, and queue-overflow input is rejected. */
@(test)
input_rejects_invalid_and_overflowing_requests :: proc(t: ^testing.T) {
	registry: Registry
	initialized, _ := registry_init(&registry)
	testing.expect(t, initialized)
	if !initialized do return
	defer if registry.state != nil do _, _ = registry_close(&registry)
	request := test_open_request("input limits", arguments = []string{"-c", "sleep 2"})
	request.process.limits.input_bytes = 8
	record, opened, failure := registry_open(&registry, request)
	testing.expectf(t, opened, "terminal open failed with %v", failure.code)
	if !opened do return

	invalid_bytes := []u8{0xff}
	invalid := Input_Request {
		kind = .Text,
		action = .Press,
		text = transmute(string)invalid_bytes,
		source = .Ordinary,
		repeat_count = 1,
	}
	observation: Input_Observation
	queued: bool
	input_failure: Failure_Record
	observation, queued, input_failure = registry_send_input(&registry, record.ref, invalid)
	testing.expect(t, !queued)
	testing.expect_value(t, input_failure.code, Failure_Code.Invalid_Argument)

	full := Input_Request {
		kind = .Text,
		action = .Press,
		text = "12345678",
		source = .Ordinary,
		repeat_count = 1,
	}
	observation, queued, input_failure = registry_send_input(&registry, record.ref, full)
	testing.expectf(t, queued, "bounded input failed with %v", input_failure.code)
	testing.expect_value(t, observation.queue_bytes, u64(8))
	_, queued, input_failure = registry_send_input(
		&registry,
		record.ref,
		Input_Request {
			kind = .Text,
			action = .Press,
			text = "x",
			source = .Ordinary,
			repeat_count = 1,
		},
	)
	testing.expect(t, !queued)
	testing.expect_value(t, input_failure.code, Failure_Code.Input_Limit)
	testing.expect_value(t, input_failure.limit, u64(8))
	testing.expect_value(t, input_failure.actual, u64(9))

	_, queued, input_failure = registry_send_input(
		&registry,
		Session_Ref{id = record.ref.id, generation = record.ref.generation + 1},
		full,
	)
	testing.expect(t, !queued)
	testing.expect_value(t, input_failure.code, Failure_Code.Stale_Reference)
}
