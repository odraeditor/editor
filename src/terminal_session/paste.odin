// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package terminal_session

import "core:unicode/utf8"
import "../interactive_session"
import "../terminal_emulator"

/* registry_paste validates, terminal-frames, and atomically queues retained text. */
registry_paste :: proc(
	registry: ^Registry,
	ref: Session_Ref,
	request: Paste_Request,
) -> (observation: Paste_Observation, ok: bool, failure: Failure_Record) {
	observation.ref = ref
	observation.text_bytes = u64(len(request.text))
	state := registry_state(registry)
	if state == nil do return observation, false, registry_access_failure(registry, .Paste)
	session, resolved := registry_resolve(state, ref)
	if !resolved do return observation, false, failure_record(.Paste, .Stale_Reference)
	if session.record.lifecycle != .Running || len(request.text) == 0 ||
	   !utf8.valid_string(request.text) || request.replace_codepoints > MAX_INPUT_REPEAT_COUNT {
		return observation, false, failure_record(.Paste, .Invalid_Argument)
	}
	if u64(len(request.text)) > session.limits.copied_text_bytes {
		return observation, false, failure_record(
			.Paste,
			.Input_Limit,
			limit = session.limits.copied_text_bytes,
			actual = u64(len(request.text)),
		)
	}
	backspace: [MAX_ENCODED_KEY_BYTES]u8
	backspace_bytes := 0
	if request.replace_codepoints > 0 {
		backspace_result: terminal_emulator.Result
		backspace_bytes, backspace_result = terminal_emulator.encode_key(
			session.record.emulator,
			.Backspace,
			.Press,
			{},
			nil,
			backspace[:],
		)
		if backspace_result != .OK do return observation, false, emulator_failure(.Paste, backspace_result)
	}
	replacement_bytes := backspace_bytes * int(request.replace_codepoints)
	encoded_capacity := replacement_bytes + len(request.text) + MAX_PASTE_FRAMING_BYTES
	mutable_text, text_error := make([]u8, len(request.text), state.allocator)
	if text_error != nil do return observation, false, failure_record(.Paste, .Allocation)
	defer delete(mutable_text, state.allocator)
	copy(mutable_text, transmute([]u8)request.text)
	encoded, encoded_error := make([]u8, encoded_capacity, state.allocator)
	if encoded_error != nil do return observation, false, failure_record(.Paste, .Allocation)
	defer delete(encoded, state.allocator)
	paste_bytes, bracketed, encode_result := terminal_emulator.encode_paste(
		session.record.emulator,
		mutable_text,
		request.allow_unsafe,
		encoded[replacement_bytes:],
	)
	if encode_result == .Rejected {
		return observation, false, failure_record(.Paste, .Paste_Rejected)
	}
	if encode_result != .OK do return observation, false, emulator_failure(.Paste, encode_result)
	if paste_bytes == 0 do return observation, false, failure_record(.Paste, .Invalid_Argument)
	if replacement_bytes > 0 {
		offset := 0
		for _ in 0 ..< request.replace_codepoints {
			copy(encoded[offset:offset + backspace_bytes], backspace[:backspace_bytes])
			offset += backspace_bytes
		}
	}
	written := replacement_bytes + paste_bytes
	if u64(written) > session.process_input_bytes {
		return observation, false, failure_record(
			.Paste,
			.Input_Limit,
			limit = session.process_input_bytes,
			actual = u64(written),
		)
	}
	queued, process_issue := interactive_session.registry_send(
		&state.interactive,
		session.record.process.ref,
		encoded[:written],
	)
	if !queued do return observation, false, paste_process_failure(process_issue)
	process_record, recorded, record_issue := interactive_session.registry_record(
		&state.interactive,
		session.record.process.ref,
	)
	if !recorded do return observation, false, paste_process_failure(record_issue)
	session.record.process = process_record
	observation.encoded_bytes = u64(written)
	observation.queued_bytes = u64(written)
	observation.queue_bytes = process_record.resources.queued_input_bytes
	observation.bracketed = bracketed
	observation.unsafe_accepted = request.allow_unsafe
	observation.replaced_codepoints = request.replace_codepoints
	return observation, true, {}
}

@(private)
paste_process_failure :: proc(issue: interactive_session.Failure_Record) -> Failure_Record {
	if issue.code == .Input_Limit {
		return failure_record(.Paste, .Input_Limit, limit = issue.limit, actual = issue.actual)
	}
	return process_failure(.Paste, issue)
}
