// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package interaction

import "base:runtime"
import "core:unicode/utf8"

/* MAX_PROMPT_TEXT_BYTES bounds one frontend-independent text-entry prompt. */
MAX_PROMPT_TEXT_BYTES :: u64(4_096)
/* MAX_PROMPT_CHOICES bounds one fixed-choice prompt. */
MAX_PROMPT_CHOICES :: u8(4)
/* MAX_PROMPT_CHOICE_NAME_BYTES bounds one visible fixed-choice alternative. */
MAX_PROMPT_CHOICE_NAME_BYTES :: 64

/* Prompt_Kind selects the bounded interaction state represented by a Prompt. */
Prompt_Kind :: enum u8 {
	Invalid,
	Text_Entry,
	Fixed_Choice,
}

/* Prompt_Status reports whether a prompt still accepts input or reached a terminal outcome. */
Prompt_Status :: enum u8 {
	Invalid,
	Active,
	Accepted,
	Cancelled,
}

/* Prompt_Transition classifies one prompt operation without implying editor effects. */
Prompt_Transition :: enum u8 {
	Invalid,
	No_Change,
	Changed,
	Completed,
}

/* Prompt_Failure_Code classifies expected prompt lifecycle and bound failures. */
Prompt_Failure_Code :: enum u8 {
	None,
	Invalid_Config,
	Closed_Prompt,
	Wrong_Kind,
	Not_Active,
	Malformed_UTF8,
	Text_Limit,
	Empty_Text,
	Invalid_Choice,
	Persistent_Memory_Limit,
}

/* Prompt_Config describes one bounded prompt and borrows no data after initialization. */
Prompt_Config :: struct {
	kind:             Prompt_Kind,
	text_bytes_limit: u64,
	choices:          []Prompt_Choice_Definition,
	allow_empty:      bool,
	allocator:        runtime.Allocator,
}

/* Prompt_Choice_Definition names one alternative and its existing command. */
Prompt_Choice_Definition :: struct {
	name:         string,
	command_name: string,
}

/* Prompt_Choice_View borrows one copied alternative until the prompt closes. */
Prompt_Choice_View :: struct {
	name:         string,
	command_name: string,
}

/* Prompt_View borrows active or completed prompt text until the next operation or close. */
Prompt_View :: struct {
	kind:            Prompt_Kind,
	status:          Prompt_Status,
	text:            string,
	text_bytes_limit: u64,
	choices:         []Prompt_Choice_View,
	selected_choice: u8,
}

/* Prompt_Failure reports the prompt state and relevant violated bound. */
Prompt_Failure :: struct {
	code:   Prompt_Failure_Code,
	limit:  u64,
	actual: u64,
}

/* Prompt is an opaque owner of one bounded frontend-independent interaction. */
Prompt :: struct {
	state: rawptr,
}

@(private)
Prompt_State :: struct {
	kind:             Prompt_Kind,
	status:           Prompt_Status,
	text:             []byte,
	text_length:      int,
	text_bytes_limit: u64,
	choice_content:   []byte,
	choices:          [MAX_PROMPT_CHOICES]Prompt_Choice_View,
	choice_count:     u8,
	selected_choice:  u8,
	allow_empty:      bool,
	allocator:        runtime.Allocator,
}

/* prompt_init creates one active prompt and owns its bounded text storage until close. */
prompt_init :: proc(prompt: ^Prompt, config: Prompt_Config) -> (ok: bool, failure: Prompt_Failure) {
	assert(prompt != nil)
	assert(prompt.state == nil, "prompt is already initialized")
	if config.allocator.procedure == nil {
		return false, Prompt_Failure{code = .Persistent_Memory_Limit}
	}
	if config.kind == .Text_Entry {
		if config.text_bytes_limit == 0 || config.text_bytes_limit > MAX_PROMPT_TEXT_BYTES ||
		   len(config.choices) != 0 {
			return false, Prompt_Failure{code = .Invalid_Config}
		}
	} else if config.kind == .Fixed_Choice {
		if len(config.choices) == 0 || len(config.choices) > int(MAX_PROMPT_CHOICES) ||
		   config.text_bytes_limit != 0 || config.allow_empty {
			return false, Prompt_Failure{code = .Invalid_Config}
		}
		content_bytes := 0
		for choice, index in config.choices {
			if !prompt_choice_definition_valid(choice) ||
			   len(choice.name) > max(int) - content_bytes ||
			   len(choice.command_name) > max(int) - content_bytes - len(choice.name) {
				return false, Prompt_Failure{code = .Invalid_Config}
			}
			for previous in 0 ..< index {
				if config.choices[previous].name == choice.name ||
				   config.choices[previous].command_name == choice.command_name {
					return false, Prompt_Failure{code = .Invalid_Config}
				}
			}
			content_bytes += len(choice.name) + len(choice.command_name)
		}
	} else {
		return false, Prompt_Failure{code = .Invalid_Config}
	}

	state, state_error := new(Prompt_State, config.allocator)
	if state_error != nil {
		return false, Prompt_Failure {
			code = .Persistent_Memory_Limit,
			actual = u64(size_of(Prompt_State)),
		}
	}
	state.kind = config.kind
	state.status = .Active
	state.text_bytes_limit = config.text_bytes_limit
	state.choice_count = u8(len(config.choices))
	state.allow_empty = config.allow_empty
	state.allocator = config.allocator
	if config.kind == .Text_Entry {
		text, text_error := make([]byte, int(config.text_bytes_limit), config.allocator)
		if text_error != nil {
			free(state, config.allocator)
			return false, Prompt_Failure {
				code = .Persistent_Memory_Limit,
				limit = config.text_bytes_limit,
				actual = config.text_bytes_limit,
			}
		}
		state.text = text
	} else {
		content_bytes := 0
		for choice in config.choices do content_bytes += len(choice.name) + len(choice.command_name)
		content, content_error := make([]byte, content_bytes, config.allocator)
		if content_error != nil {
			free(state, config.allocator)
			return false, Prompt_Failure {
				code = .Persistent_Memory_Limit,
				actual = u64(content_bytes),
			}
		}
		state.choice_content = content
		offset := 0
		for choice, index in config.choices {
			name_start := offset
			copy(content[offset:], transmute([]u8)choice.name)
			offset += len(choice.name)
			command_start := offset
			copy(content[offset:], transmute([]u8)choice.command_name)
			offset += len(choice.command_name)
			state.choices[index] = Prompt_Choice_View {
				name = string(content[name_start:name_start + len(choice.name)]),
				command_name = string(content[command_start:command_start + len(choice.command_name)]),
			}
		}
	}
	prompt.state = state
	return true, {}
}

/* prompt_view reports the current state and borrows any entered text. */
prompt_view :: proc(prompt: ^Prompt) -> (view: Prompt_View, ok: bool, failure: Prompt_Failure) {
	state := prompt_state(prompt)
	if state == nil {
		return {}, false, Prompt_Failure{code = .Closed_Prompt}
	}
	return Prompt_View {
		kind = state.kind,
		status = state.status,
		text = string(state.text[:state.text_length]),
		text_bytes_limit = state.text_bytes_limit,
		choices = state.choices[:state.choice_count],
		selected_choice = state.selected_choice,
	}, true, {}
}

/* prompt_text_append appends exact well-formed UTF-8 while the text prompt is active. */
prompt_text_append :: proc(
	prompt: ^Prompt,
	text: string,
) -> (transition: Prompt_Transition, failure: Prompt_Failure) {
	state, state_failure := active_prompt_state(prompt, .Text_Entry)
	if state_failure.code != .None {
		return .Invalid, state_failure
	}
	if len(text) == 0 {
		return .No_Change, {}
	}
	if !utf8.valid_string(text) {
		return .Invalid, Prompt_Failure{code = .Malformed_UTF8, actual = u64(len(text))}
	}
	result_bytes := u64(state.text_length) + u64(len(text))
	if result_bytes > state.text_bytes_limit {
		return .Invalid, Prompt_Failure {
			code = .Text_Limit,
			limit = state.text_bytes_limit,
			actual = result_bytes,
		}
	}
	copy(state.text[state.text_length:], transmute([]u8)text)
	state.text_length = int(result_bytes)
	return .Changed, {}
}

/* prompt_text_replace atomically replaces active text with one admitted UTF-8 value. */
prompt_text_replace :: proc(
	prompt: ^Prompt,
	text: string,
) -> (transition: Prompt_Transition, failure: Prompt_Failure) {
	state, state_failure := active_prompt_state(prompt, .Text_Entry)
	if state_failure.code != .None {
		return .Invalid, state_failure
	}
	if !utf8.valid_string(text) {
		return .Invalid, Prompt_Failure{code = .Malformed_UTF8, actual = u64(len(text))}
	}
	if u64(len(text)) > state.text_bytes_limit {
		return .Invalid, Prompt_Failure {
			code = .Text_Limit,
			limit = state.text_bytes_limit,
			actual = u64(len(text)),
		}
	}
	if string(state.text[:state.text_length]) == text {
		return .No_Change, {}
	}
	copy(state.text, transmute([]u8)text)
	state.text_length = len(text)
	return .Changed, {}
}

/* prompt_text_delete_previous removes one complete UTF-8 scalar without allocation. */
prompt_text_delete_previous :: proc(
	prompt: ^Prompt,
) -> (transition: Prompt_Transition, failure: Prompt_Failure) {
	state, state_failure := active_prompt_state(prompt, .Text_Entry)
	if state_failure.code != .None {
		return .Invalid, state_failure
	}
	if state.text_length == 0 {
		return .No_Change, {}
	}
	start := state.text_length - 1
	for start > 0 && state.text[start] & 0xc0 == 0x80 {
		start -= 1
	}
	state.text_length = start
	return .Changed, {}
}

/* prompt_text_accept completes a nonempty text prompt unless empty input was admitted. */
prompt_text_accept :: proc(
	prompt: ^Prompt,
) -> (transition: Prompt_Transition, failure: Prompt_Failure) {
	state, state_failure := active_prompt_state(prompt, .Text_Entry)
	if state_failure.code != .None {
		return .Invalid, state_failure
	}
	if state.text_length == 0 && !state.allow_empty {
		return .Invalid, Prompt_Failure{code = .Empty_Text}
	}
	state.status = .Accepted
	return .Completed, {}
}

/* prompt_choice_accept completes a fixed-choice prompt with a one-based choice index. */
prompt_choice_accept :: proc(
	prompt: ^Prompt,
	choice: u8,
) -> (transition: Prompt_Transition, failure: Prompt_Failure) {
	state, state_failure := active_prompt_state(prompt, .Fixed_Choice)
	if state_failure.code != .None {
		return .Invalid, state_failure
	}
	if choice == 0 || choice > state.choice_count {
		return .Invalid, Prompt_Failure {
			code = .Invalid_Choice,
			limit = u64(state.choice_count),
			actual = u64(choice),
		}
	}
	state.selected_choice = choice
	state.status = .Accepted
	return .Completed, {}
}

/* prompt_cancel completes either active prompt kind without accepting text or a choice. */
prompt_cancel :: proc(prompt: ^Prompt) -> (transition: Prompt_Transition, failure: Prompt_Failure) {
	state := prompt_state(prompt)
	if state == nil {
		return .Invalid, Prompt_Failure{code = .Closed_Prompt}
	}
	if state.status != .Active {
		return .Invalid, Prompt_Failure{code = .Not_Active}
	}
	state.status = .Cancelled
	return .Completed, {}
}

/* prompt_close releases all prompt storage and invalidates its handle. */
prompt_close :: proc(prompt: ^Prompt) -> (ok: bool, failure: Prompt_Failure) {
	state := prompt_state(prompt)
	if state == nil {
		return false, Prompt_Failure{code = .Closed_Prompt}
	}
	allocator := state.allocator
	if len(state.text) > 0 {
		delete(state.text, allocator)
	}
	if len(state.choice_content) > 0 {
		delete(state.choice_content, allocator)
	}
	prompt.state = nil
	free(state, allocator)
	return true, {}
}

@(private)
prompt_choice_definition_valid :: proc(choice: Prompt_Choice_Definition) -> bool {
	return len(choice.name) > 0 && len(choice.name) <= MAX_PROMPT_CHOICE_NAME_BYTES &&
		len(choice.command_name) > 0 && len(choice.command_name) <= MAX_COMMAND_NAME_BYTES &&
		utf8.valid_string(choice.name) && utf8.valid_string(choice.command_name)
}

@(private)
prompt_state :: proc(prompt: ^Prompt) -> ^Prompt_State {
	if prompt == nil || prompt.state == nil {
		return nil
	}
	return (^Prompt_State)(prompt.state)
}

@(private)
active_prompt_state :: proc(
	prompt: ^Prompt,
	kind: Prompt_Kind,
) -> (^Prompt_State, Prompt_Failure) {
	state := prompt_state(prompt)
	if state == nil {
		return nil, Prompt_Failure{code = .Closed_Prompt}
	}
	if state.kind != kind {
		return nil, Prompt_Failure{code = .Wrong_Kind}
	}
	if state.status != .Active {
		return nil, Prompt_Failure{code = .Not_Active}
	}
	return state, {}
}
