// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package terminal_session

import "core:unicode/utf8"
import "../interactive_session"
import "../terminal_emulator"

/* registry_send_input encodes and atomically queues one normalized input request. */
registry_send_input :: proc(
	registry: ^Registry,
	ref: Session_Ref,
	request: Input_Request,
) -> (observation: Input_Observation, ok: bool, failure: Failure_Record) {
	observation = Input_Observation {
		ref = ref,
		kind = request.kind,
		source = request.source,
		repeat_count = request.repeat_count,
	}
	state := registry_state(registry)
	if state == nil do return observation, false, registry_access_failure(registry, .Input)
	session, resolved := registry_resolve(state, ref)
	if !resolved do return observation, false, failure_record(.Input, .Stale_Reference)
	if session.record.lifecycle != .Running {
		return observation, false, failure_record(.Input, .Invalid_Argument)
	}
	if !input_request_valid(request) {
		return observation, false, failure_record(.Input, .Invalid_Argument)
	}

	first: [MAX_ENCODED_KEY_BYTES]u8
	repeated: [MAX_ENCODED_KEY_BYTES]u8
	first_count, repeated_count, focus_reporting, encoded := input_encode_request(
		session,
		request,
		first[:],
		repeated[:],
	)
	if encoded.code != .None do return observation, false, encoded
	observation.focus_reporting = focus_reporting
	if first_count == 0 {
		return observation, true, {}
	}

	batch_count := first_count
	if request.repeat_count > 1 {
		batch_count += repeated_count * (int(request.repeat_count) - 1)
	}
	observation.encoded_bytes = u64(batch_count)
	if u64(batch_count) > session.process_input_bytes {
		return observation, false, failure_record(
			.Input,
			.Input_Limit,
			limit = session.process_input_bytes,
			actual = u64(batch_count),
		)
	}

	if request.repeat_count == 1 {
		queued, process_issue := interactive_session.registry_send(
			&state.interactive,
			session.record.process.ref,
			first[:first_count],
		)
		if !queued do return observation, false, input_process_failure(process_issue)
	} else {
		batch, allocation_error := make([]u8, batch_count, state.allocator)
		if allocation_error != nil do return observation, false, failure_record(.Input, .Allocation)
		defer delete(batch, state.allocator)
		copy(batch[:first_count], first[:first_count])
		offset := first_count
		for _ in 1 ..< request.repeat_count {
			copy(batch[offset:offset + repeated_count], repeated[:repeated_count])
			offset += repeated_count
		}
		queued, process_issue := interactive_session.registry_send(
			&state.interactive,
			session.record.process.ref,
			batch,
		)
		if !queued do return observation, false, input_process_failure(process_issue)
	}

	process_record, recorded, process_issue := interactive_session.registry_record(
		&state.interactive,
		session.record.process.ref,
	)
	if !recorded do return observation, false, input_process_failure(process_issue)
	session.record.process = process_record
	observation.queued_bytes = u64(batch_count)
	observation.queue_bytes = process_record.resources.queued_input_bytes
	return observation, true, {}
}

@(private)
input_request_valid :: proc(request: Input_Request) -> bool {
	if request.source != .Ordinary && request.source != .Literal_Next do return false
	if request.repeat_count == 0 || request.repeat_count > MAX_INPUT_REPEAT_COUNT do return false
	switch request.kind {
	case .Text:
		return len(request.text) > 0 && len(request.text) <= MAX_INPUT_TEXT_BYTES &&
			utf8.valid_string(request.text) && request.key == .Invalid &&
			request.action == .Press && card(request.modifiers) == 0 && request.focus == .Invalid
	case .Key:
		if request.key == .Invalid || request.action == .Invalid || request.focus != .Invalid {
			return false
		}
		if request.key == .Character {
			return len(request.text) > 0 && len(request.text) <= MAX_INPUT_TEXT_BYTES &&
				utf8.valid_string(request.text)
		}
		return len(request.text) == 0
	case .Focus:
		return request.focus != .Invalid && request.repeat_count == 1 &&
			request.key == .Invalid && request.action == .Press &&
			card(request.modifiers) == 0 && len(request.text) == 0
	case .Invalid:
		return false
	}
	return false
}

@(private)
input_encode_request :: proc(
	session: ^Session_State,
	request: Input_Request,
	first, repeated: []u8,
) -> (first_count, repeated_count: int, focus_reporting: bool, failure: Failure_Record) {
	switch request.kind {
	case .Text:
		copy(first, transmute([]u8)request.text)
		copy(repeated, transmute([]u8)request.text)
		return len(request.text), len(request.text), false, {}
	case .Key:
		key, mapped := input_emulator_key(request.key)
		if !mapped do return 0, 0, false, failure_record(.Input, .Invalid_Argument)
		modifiers := input_emulator_modifiers(request.modifiers)
		first_action := terminal_emulator.Key_Action.Press
		if request.action == .Repeat do first_action = .Repeat
		result: terminal_emulator.Result
		first_count, result = terminal_emulator.encode_key(
			session.record.emulator,
			key,
			first_action,
			modifiers,
			transmute([]u8)request.text,
			first,
		)
		if result != .OK do return 0, 0, false, input_emulator_failure(result)
		repeated_count = first_count
		if request.repeat_count > 1 {
			repeated_count, result = terminal_emulator.encode_key(
				session.record.emulator,
				key,
				.Repeat,
				modifiers,
				transmute([]u8)request.text,
				repeated,
			)
			if result != .OK do return 0, 0, false, input_emulator_failure(result)
		}
		return first_count, repeated_count, false, {}
	case .Focus:
		event := terminal_emulator.Focus_Event.Gained
		if request.focus == .Lost do event = .Lost
		result: terminal_emulator.Result
		first_count, focus_reporting, result = terminal_emulator.encode_focus(
			session.record.emulator,
			event,
			first,
		)
		if result != .OK do return 0, 0, false, input_emulator_failure(result)
		return first_count, first_count, focus_reporting, {}
	case .Invalid:
	}
	return 0, 0, false, failure_record(.Input, .Invalid_Argument)
}

@(private)
input_emulator_key :: proc(key: Input_Key) -> (terminal_emulator.Key, bool) {
	switch key {
	case .Character: return .Character, true
	case .Enter:     return .Enter, true
	case .Tab:       return .Tab, true
	case .Backspace: return .Backspace, true
	case .Delete:    return .Delete, true
	case .Escape:    return .Escape, true
	case .Up:        return .Arrow_Up, true
	case .Down:      return .Arrow_Down, true
	case .Left:      return .Arrow_Left, true
	case .Right:     return .Arrow_Right, true
	case .Home:      return .Home, true
	case .End:       return .End, true
	case .Prior:     return .Page_Up, true
	case .Next:      return .Page_Down, true
	case .Space:     return .Space, true
	case .Invalid:
	}
	return {}, false
}

@(private)
input_emulator_modifiers :: proc(modifiers: Input_Modifiers) -> bit_set[terminal_emulator.Modifier; u32] {
	result: bit_set[terminal_emulator.Modifier; u32]
	if .Shift in modifiers do result += {.Shift}
	if .Control in modifiers do result += {.Control}
	if .Alt in modifiers do result += {.Alt}
	if .Super in modifiers do result += {.Super}
	return result
}

@(private)
input_emulator_failure :: proc(result: terminal_emulator.Result) -> Failure_Record {
	if result == .Buffer_Too_Small {
		return failure_record(.Input, .Input_Limit, limit = MAX_ENCODED_KEY_BYTES)
	}
	return emulator_failure(.Input, result)
}

@(private)
input_process_failure :: proc(issue: interactive_session.Failure_Record) -> Failure_Record {
	if issue.code == .Input_Limit {
		return failure_record(.Input, .Input_Limit, limit = issue.limit, actual = issue.actual)
	}
	return process_failure(.Input, issue)
}
