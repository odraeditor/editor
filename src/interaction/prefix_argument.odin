// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package interaction

/* Prefix_Argument_Disposition describes one Direct-profile prefix transition. */
Prefix_Argument_Disposition :: enum u8 {
	Pass_Through,
	Pending,
	Ready,
	Cancelled,
	Rejected,
}

/* Prefix_Argument_State retains one bounded universal or numeric argument. */
Prefix_Argument_State :: struct {
	active:          bool,
	magnitude:       u64,
	negative:        bool,
	digits_explicit: bool,
}

/* Prefix_Argument is the immutable argument delivered to one command. */
Prefix_Argument :: struct {
	present:      bool,
	value:        i64,
	repeat_count: u64,
}

/* Prefix_Argument_Result reports one prefix parser transition. */
Prefix_Argument_Result :: struct {
	disposition: Prefix_Argument_Disposition,
	argument:    Prefix_Argument,
	limit:       u64,
	actual:      u64,
}

/* prefix_argument_compose consumes Direct-profile universal and numeric prefixes. */
prefix_argument_compose :: proc(
	state: ^Prefix_Argument_State,
	input: Input,
) -> Prefix_Argument_Result {
	assert(state != nil)
	if !input_is_valid(input) do return {disposition = .Pass_Through}
	if prefix_argument_is_cancel_input(input) {
		if state.active {
			state^ = {}
			return {disposition = .Cancelled}
		}
		return {disposition = .Pass_Through}
	}
	if prefix_argument_universal_input(input) {
		if !state.active {
			state^ = {active = true, magnitude = 4}
			return prefix_argument_pending(state^)
		}
		if state.digits_explicit {
			return prefix_argument_ready(state^)
		}
		if state.magnitude > MAX_MODAL_COUNT / 4 {
			actual := state.magnitude
			state^ = {}
			return {
				disposition = .Rejected,
				limit = MAX_MODAL_COUNT,
				actual = actual * 4,
			}
		}
		state.magnitude *= 4
		return prefix_argument_pending(state^)
	}
	digit, digit_input := prefix_argument_digit(input, state.active)
	if digit_input {
		if !state.active {
			state^ = {active = true, magnitude = digit, digits_explicit = true}
			return prefix_argument_pending(state^)
		}
		if !state.digits_explicit {
			state.magnitude = digit
			state.digits_explicit = true
			return prefix_argument_pending(state^)
		}
		if state.magnitude > (MAX_MODAL_COUNT - digit) / 10 {
			actual := state.magnitude
			state^ = {}
			return {
				disposition = .Rejected,
				limit = MAX_MODAL_COUNT,
				actual = actual * 10 + digit,
			}
		}
		state.magnitude = state.magnitude * 10 + digit
		return prefix_argument_pending(state^)
	}
	if prefix_argument_negative_input(input, state.active) {
		if !state.active {
			state^ = {active = true, magnitude = 1, negative = true}
		} else {
			state.negative = true
		}
		return prefix_argument_pending(state^)
	}
	if state.active do return prefix_argument_ready(state^)
	return {disposition = .Pass_Through}
}

/* prefix_argument_inspect returns the current argument without consuming it. */
prefix_argument_inspect :: proc(state: ^Prefix_Argument_State) -> Prefix_Argument {
	if state == nil || !state.active do return {}
	return prefix_argument_from_state(state^)
}

@(private)
prefix_argument_from_state :: proc(state: Prefix_Argument_State) -> Prefix_Argument {
	if !state.active do return {}
	magnitude := state.magnitude
	value := i64(magnitude)
	if state.negative do value = -value
	repeat_count := magnitude
	if repeat_count == 0 do repeat_count = 1
	return {present = true, value = value, repeat_count = repeat_count}
}

/* prefix_argument_take returns and clears the current argument. */
prefix_argument_take :: proc(state: ^Prefix_Argument_State) -> Prefix_Argument {
	argument := prefix_argument_inspect(state)
	prefix_argument_clear(state)
	return argument
}

/* prefix_argument_clear discards any retained Direct-profile prefix. */
prefix_argument_clear :: proc(state: ^Prefix_Argument_State) {
	if state != nil do state^ = {}
}

/* prefix_argument_is_cancel_input reports an ordinary Direct-profile cancellation. */
prefix_argument_is_cancel_input :: proc(input: Input) -> bool {
	return input.kind == .Key &&
	       ((input.stroke.kind == .Escape && input.stroke.modifiers == {}) ||
	        (input.stroke.kind == .Unicode_Scalar && input.stroke.scalar == 'g' &&
	         input.stroke.modifiers == {.Control}))
}

@(private)
prefix_argument_pending :: proc(state: Prefix_Argument_State) -> Prefix_Argument_Result {
	argument := prefix_argument_from_state(state)
	return {disposition = .Pending, argument = argument}
}

@(private)
prefix_argument_ready :: proc(state: Prefix_Argument_State) -> Prefix_Argument_Result {
	argument := prefix_argument_from_state(state)
	return {disposition = .Ready, argument = argument}
}

@(private)
prefix_argument_universal_input :: proc(input: Input) -> bool {
	return input.kind == .Key && input.stroke.kind == .Unicode_Scalar &&
	       input.stroke.scalar == 'u' && input.stroke.modifiers == {.Control}
}

@(private)
prefix_argument_digit :: proc(input: Input, active: bool) -> (u64, bool) {
	if input.kind != .Key || input.stroke.kind != .Unicode_Scalar ||
	   input.stroke.scalar < '0' || input.stroke.scalar > '9' {
		return 0, false
	}
	if input.stroke.modifiers == {.Meta} || (active && input.stroke.modifiers == {}) {
		return u64(input.stroke.scalar - '0'), true
	}
	return 0, false
}

@(private)
prefix_argument_negative_input :: proc(input: Input, active: bool) -> bool {
	if input.kind != .Key || input.stroke.kind != .Unicode_Scalar || input.stroke.scalar != '-' {
		return false
	}
	return input.stroke.modifiers == {.Meta} || (active && input.stroke.modifiers == {})
}
