// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package terminal_session

import "core:testing"
import "../terminal_emulator"

/* Verifies terminal mode controls safe framing before one atomic PTY queue. */
@(test)
paste_frames_text_for_current_terminal_mode :: proc(t: ^testing.T) {
	registry: Registry
	initialized, _ := registry_init(&registry)
	testing.expect(t, initialized)
	if !initialized do return
	defer if registry.state != nil do _, _ = registry_close(&registry)
	record, opened, open_failure := registry_open(
		&registry,
		test_open_request("paste modes", arguments = []string{"-c", "sleep 2"}),
	)
	testing.expectf(t, opened, "terminal open failed with %v", open_failure.code)
	if !opened do return

	plain, pasted, paste_failure := registry_paste(
		&registry, record.ref, Paste_Request{text = "alpha"},
	)
	testing.expectf(t, pasted, "plain paste failed with %v", paste_failure.code)
	testing.expect(t, !plain.bracketed)
	testing.expect_value(t, plain.encoded_bytes, u64(5))

	_, pasted, paste_failure = registry_paste(
		&registry, record.ref, Paste_Request{text = "one\ntwo"},
	)
	testing.expect(t, !pasted)
	testing.expect_value(t, paste_failure.code, Failure_Code.Paste_Rejected)
	testing.expect_value(
		t,
		terminal_emulator.write(record.emulator, transmute([]u8)(string("\x1b[?2004h"))),
		terminal_emulator.Result.OK,
	)
	bracketed, bracketed_ok, bracketed_failure := registry_paste(
		&registry, record.ref, Paste_Request{text = "one\ntwo"},
	)
	testing.expectf(
		t, bracketed_ok, "bracketed paste failed with %v", bracketed_failure.code,
	)
	testing.expect(t, bracketed.bracketed)
	testing.expect_value(t, bracketed.encoded_bytes, u64(len("one\ntwo") + MAX_PASTE_FRAMING_BYTES))

	_, pasted, paste_failure = registry_paste(
		&registry, record.ref, Paste_Request{text = "safe\x1b[201~unsafe"},
	)
	testing.expect(t, !pasted)
	testing.expect_value(t, paste_failure.code, Failure_Code.Paste_Rejected)
	accepted, accepted_ok, accepted_failure := registry_paste(
		&registry,
		record.ref,
		Paste_Request{text = "safe\x1b[201~unsafe", allow_unsafe = true},
	)
	testing.expectf(t, accepted_ok, "confirmed paste failed with %v", accepted_failure.code)
	testing.expect(t, accepted.unsafe_accepted)
	replaced, replaced_ok, replaced_failure := registry_paste(
		&registry,
		record.ref,
		Paste_Request{text = "new", replace_codepoints = 3},
	)
	testing.expectf(t, replaced_ok, "replacement paste failed with %v", replaced_failure.code)
	if replaced_ok {
		testing.expect_value(t, replaced.replaced_codepoints, u32(3))
		testing.expect(t, replaced.encoded_bytes > u64(len("new")))
	}
}

/* Verifies malformed, oversized, stale, and queue-limited paste is rejected. */
@(test)
paste_rejects_invalid_and_bounded_requests :: proc(t: ^testing.T) {
	registry: Registry
	initialized, _ := registry_init(&registry)
	testing.expect(t, initialized)
	if !initialized do return
	defer if registry.state != nil do _, _ = registry_close(&registry)
	request := test_open_request("paste limits", arguments = []string{"-c", "sleep 2"})
	request.process.limits.input_bytes = 8
	request.limits.copied_text_bytes = 4
	record, opened, open_failure := registry_open(&registry, request)
	testing.expectf(t, opened, "terminal open failed with %v", open_failure.code)
	if !opened do return

	invalid_bytes := []u8{0xff}
	_, pasted, paste_failure := registry_paste(
		&registry,
		record.ref,
		Paste_Request{text = transmute(string)invalid_bytes},
	)
	testing.expect(t, !pasted)
	testing.expect_value(t, paste_failure.code, Failure_Code.Invalid_Argument)
	_, pasted, paste_failure = registry_paste(
		&registry, record.ref, Paste_Request{text = "12345"},
	)
	testing.expect(t, !pasted)
	testing.expect_value(t, paste_failure.code, Failure_Code.Input_Limit)
	testing.expect_value(t, paste_failure.limit, u64(4))

	accepted, accepted_ok, accepted_failure := registry_paste(
		&registry, record.ref, Paste_Request{text = "1234"},
	)
	testing.expectf(t, accepted_ok, "bounded paste failed with %v", accepted_failure.code)
	testing.expect_value(t, accepted.queue_bytes, u64(4))
	second, second_ok, second_failure := registry_paste(
		&registry, record.ref, Paste_Request{text = "1234"},
	)
	testing.expectf(t, second_ok, "second bounded paste failed with %v", second_failure.code)
	testing.expect_value(t, second.queue_bytes, u64(8))
	_, pasted, paste_failure = registry_paste(
		&registry, record.ref, Paste_Request{text = "1"},
	)
	testing.expect(t, !pasted)
	testing.expect_value(t, paste_failure.code, Failure_Code.Input_Limit)
	_, pasted, paste_failure = registry_paste(
		&registry,
		Session_Ref{id = record.ref.id, generation = record.ref.generation + 1},
		Paste_Request{text = "x"},
	)
	testing.expect(t, !pasted)
	testing.expect_value(t, paste_failure.code, Failure_Code.Stale_Reference)
}
