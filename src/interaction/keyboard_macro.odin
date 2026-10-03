// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package interaction

/* MAX_KEYBOARD_MACRO_STEPS bounds one semantic command sequence. */
MAX_KEYBOARD_MACRO_STEPS :: 128
/* MAX_KEYBOARD_MACRO_TEXT_BYTES bounds all copied text arguments in one macro. */
MAX_KEYBOARD_MACRO_TEXT_BYTES :: 8 * 1_024
/* MAX_NAMED_KEYBOARD_MACROS bounds session-local retained macro identities. */
MAX_NAMED_KEYBOARD_MACROS :: 8

/* Keyboard_Macro_Failure_Code classifies bounded recorder and replay failures. */
Keyboard_Macro_Failure_Code :: enum u8 {
	None,
	Invalid_State,
	No_Macro,
	Step_Limit,
	Text_Limit,
	Invalid_Name,
	Name_Limit,
}

/* Keyboard_Macro_Failure reports one rejected state transition or resource bound. */
Keyboard_Macro_Failure :: struct {
	code:   Keyboard_Macro_Failure_Code,
	limit:  u64,
	actual: u64,
}

/* Keyboard_Macro_Step retains one canonical command identity and copied arguments. */
Keyboard_Macro_Step :: struct {
	command_name:        [MAX_COMMAND_NAME_BYTES]u8,
	command_name_length: u8,
	text_offset:         u16,
	text_length:         u16,
	prefix:              Prefix_Argument,
}

/* Keyboard_Macro_Record owns one complete bounded semantic sequence. */
Keyboard_Macro_Record :: struct {
	valid:       bool,
	steps:       [MAX_KEYBOARD_MACRO_STEPS]Keyboard_Macro_Step,
	step_count:  u16,
	text:        [MAX_KEYBOARD_MACRO_TEXT_BYTES]u8,
	text_length: u16,
}

/* Named_Keyboard_Macro retains one session-local alias and independent record. */
Named_Keyboard_Macro :: struct {
	name:        [MAX_COMMAND_NAME_BYTES]u8,
	name_length: u8,
	record:      Keyboard_Macro_Record,
}

/* Keyboard_Macro_State owns recording, replay, last-record, and named aliases. */
Keyboard_Macro_State :: struct {
	recording:   bool,
	replaying:   bool,
	working:     Keyboard_Macro_Record,
	last:        Keyboard_Macro_Record,
	named:       [MAX_NAMED_KEYBOARD_MACROS]Named_Keyboard_Macro,
	named_count: u8,
}

/* Keyboard_Macro_Step_View borrows one immutable step from a retained record. */
Keyboard_Macro_Step_View :: struct {
	command_name: string,
	text:         string,
	prefix:       Prefix_Argument,
}

/* keyboard_macro_clear forgets all session-local macro state. */
keyboard_macro_clear :: proc(state: ^Keyboard_Macro_State) {
	if state != nil do state^ = {}
}

/* keyboard_macro_begin starts a fresh definition while preserving the last macro. */
keyboard_macro_begin :: proc(
	state: ^Keyboard_Macro_State,
) -> (bool, Keyboard_Macro_Failure) {
	if state == nil || state.recording || state.replaying {
		return false, {code = .Invalid_State}
	}
	state.working = {}
	state.recording = true
	return true, {}
}

/* keyboard_macro_append copies one resolved canonical command into the definition. */
keyboard_macro_append :: proc(
	state: ^Keyboard_Macro_State,
	command_name, text: string,
	prefix: Prefix_Argument = {},
) -> (bool, Keyboard_Macro_Failure) {
	if state == nil || !state.recording || state.replaying {
		return false, {code = .Invalid_State}
	}
	if !valid_bounded_text(command_name, MAX_COMMAND_NAME_BYTES, false) {
		return false, {
			code = .Invalid_Name,
			limit = MAX_COMMAND_NAME_BYTES,
			actual = u64(len(command_name)),
		}
	}
	if state.working.step_count >= MAX_KEYBOARD_MACRO_STEPS {
		return false, {
			code = .Step_Limit,
			limit = MAX_KEYBOARD_MACRO_STEPS,
			actual = u64(state.working.step_count) + 1,
		}
	}
	if u64(state.working.text_length) + u64(len(text)) > MAX_KEYBOARD_MACRO_TEXT_BYTES {
		return false, {
			code = .Text_Limit,
			limit = MAX_KEYBOARD_MACRO_TEXT_BYTES,
			actual = u64(state.working.text_length) + u64(len(text)),
		}
	}
	step := &state.working.steps[state.working.step_count]
	step.command_name_length = u8(copy(step.command_name[:], transmute([]u8)command_name))
	step.text_offset = state.working.text_length
	step.text_length = u16(len(text))
	step.prefix = prefix
	if len(text) > 0 {
		start := int(state.working.text_length)
		copy(state.working.text[start:], transmute([]u8)text)
		state.working.text_length += u16(len(text))
	}
	state.working.step_count += 1
	return true, {}
}

/* keyboard_macro_finish publishes the current definition as the last macro. */
keyboard_macro_finish :: proc(
	state: ^Keyboard_Macro_State,
) -> (bool, Keyboard_Macro_Failure) {
	if state == nil || !state.recording || state.replaying {
		return false, {code = .Invalid_State}
	}
	state.working.valid = true
	state.last = state.working
	state.working = {}
	state.recording = false
	return true, {}
}

/* keyboard_macro_cancel abandons only the in-progress definition. */
keyboard_macro_cancel :: proc(state: ^Keyboard_Macro_State) -> bool {
	if state == nil || !state.recording do return false
	state.working = {}
	state.recording = false
	return true
}

/* keyboard_macro_name_last copies the last definition under a session-local alias. */
keyboard_macro_name_last :: proc(
	state: ^Keyboard_Macro_State,
	name: string,
) -> (bool, Keyboard_Macro_Failure) {
	if state == nil || state.recording || state.replaying || !state.last.valid {
		return false, {code = .No_Macro}
	}
	if !valid_bounded_text(name, MAX_COMMAND_NAME_BYTES, false) {
		return false, {
			code = .Invalid_Name,
			limit = MAX_COMMAND_NAME_BYTES,
			actual = u64(len(name)),
		}
	}
	index := int(state.named_count)
	for &candidate, candidate_index in state.named[:state.named_count] {
		if string(candidate.name[:candidate.name_length]) == name {
			index = candidate_index
			break
		}
	}
	if index == int(state.named_count) {
		if state.named_count >= MAX_NAMED_KEYBOARD_MACROS {
			return false, {
				code = .Name_Limit,
				limit = MAX_NAMED_KEYBOARD_MACROS,
				actual = u64(state.named_count) + 1,
			}
		}
		state.named_count += 1
	}
	entry := &state.named[index]
	entry^ = {}
	entry.name_length = u8(copy(entry.name[:], transmute([]u8)name))
	entry.record = state.last
	return true, {}
}

/* keyboard_macro_replay_begin borrows the last or one named immutable record. */
keyboard_macro_replay_begin :: proc(
	state: ^Keyboard_Macro_State,
	name: string = "",
) -> (^Keyboard_Macro_Record, bool, Keyboard_Macro_Failure) {
	if state == nil || state.recording || state.replaying {
		return nil, false, {code = .Invalid_State}
	}
	record := &state.last
	if len(name) > 0 {
		record = nil
		for &candidate in state.named[:state.named_count] {
			if string(candidate.name[:candidate.name_length]) == name {
				record = &candidate.record
				break
			}
		}
	}
	if record == nil || !record.valid {
		return nil, false, {code = .No_Macro}
	}
	state.replaying = true
	return record, true, {}
}

/* keyboard_macro_replay_end releases replay ownership after success or failure. */
keyboard_macro_replay_end :: proc(state: ^Keyboard_Macro_State) {
	if state != nil do state.replaying = false
}

/* keyboard_macro_step borrows one checked step and its copied text. */
keyboard_macro_step :: proc(
	record: ^Keyboard_Macro_Record,
	index: u16,
) -> (Keyboard_Macro_Step_View, bool) {
	if record == nil || !record.valid || index >= record.step_count do return {}, false
	step := &record.steps[index]
	text_start := int(step.text_offset)
	text_end := text_start + int(step.text_length)
	if text_end > int(record.text_length) do return {}, false
	return {
		command_name = string(step.command_name[:step.command_name_length]),
		text = string(record.text[text_start:text_end]),
		prefix = step.prefix,
	}, true
}

/* keyboard_macro_is_recording reports whether ordinary resolved commands are retained. */
keyboard_macro_is_recording :: proc(state: ^Keyboard_Macro_State) -> bool {
	return state != nil && state.recording
}
