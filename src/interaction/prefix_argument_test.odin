// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package interaction

import "core:testing"

@(test)
/* Verifies universal and numeric prefix arguments compose deterministically. */
prefix_argument_composes_universal_and_numeric_values :: proc(t: ^testing.T) {
	state: Prefix_Argument_State
	result := prefix_argument_compose(&state, prefix_control('u'))
	testing.expect_value(t, result.disposition, Prefix_Argument_Disposition.Pending)
	testing.expect_value(t, result.argument.value, i64(4))
	result = prefix_argument_compose(&state, prefix_control('u'))
	testing.expect_value(t, result.argument.value, i64(16))
	result = prefix_argument_compose(&state, prefix_plain('x'))
	testing.expect_value(t, result.disposition, Prefix_Argument_Disposition.Ready)
	testing.expect_value(t, result.argument.repeat_count, u64(16))

	state = {}
	_ = prefix_argument_compose(&state, prefix_meta('2'))
	_ = prefix_argument_compose(&state, prefix_plain('5'))
	result = prefix_argument_compose(&state, prefix_plain('x'))
	testing.expect_value(t, result.argument.value, i64(25))
	testing.expect_value(t, prefix_argument_take(&state).value, i64(25))
	testing.expect(t, !state.active)
}

@(test)
/* Verifies negative, zero, and cancellation prefix transitions. */
prefix_argument_supports_negative_zero_and_cancellation :: proc(t: ^testing.T) {
	state: Prefix_Argument_State
	_ = prefix_argument_compose(&state, prefix_meta('-'))
	_ = prefix_argument_compose(&state, prefix_plain('3'))
	result := prefix_argument_compose(&state, prefix_plain('x'))
	testing.expect_value(t, result.argument.value, i64(-3))
	testing.expect_value(t, result.argument.repeat_count, u64(3))

	state = {}
	_ = prefix_argument_compose(&state, prefix_meta('0'))
	result = prefix_argument_compose(&state, prefix_plain('x'))
	testing.expect_value(t, result.argument.value, i64(0))
	testing.expect_value(t, result.argument.repeat_count, u64(1))

	result = prefix_argument_compose(&state, prefix_control('g'))
	testing.expect_value(t, result.disposition, Prefix_Argument_Disposition.Cancelled)
	testing.expect(t, !state.active)
}

@(test)
/* Verifies prefix values reject overflow beyond the shared count bound. */
prefix_argument_rejects_values_above_the_shared_count_bound :: proc(t: ^testing.T) {
	state := Prefix_Argument_State {
		active = true,
		magnitude = MAX_MODAL_COUNT,
		digits_explicit = true,
	}
	result := prefix_argument_compose(&state, prefix_plain('9'))
	testing.expect_value(t, result.disposition, Prefix_Argument_Disposition.Rejected)
	testing.expect_value(t, result.limit, MAX_MODAL_COUNT)
	testing.expect(t, !state.active)
}

@(test)
/* Verifies ordinary digits pass through and consumed prefix state clears. */
prefix_argument_passes_ordinary_digits_and_clears_consumed_state :: proc(t: ^testing.T) {
	state: Prefix_Argument_State
	ordinary := prefix_argument_compose(&state, prefix_plain('7'))
	testing.expect_value(t, ordinary.disposition, Prefix_Argument_Disposition.Pass_Through)
	testing.expect(t, !state.active)
	cancel := prefix_argument_compose(&state, prefix_control('g'))
	testing.expect_value(t, cancel.disposition, Prefix_Argument_Disposition.Pass_Through)

	_ = prefix_argument_compose(&state, prefix_control('u'))
	argument := prefix_argument_take(&state)
	testing.expect(t, argument.present)
	testing.expect_value(t, argument.value, i64(4))
	testing.expect(t, !prefix_argument_inspect(&state).present)
}

@(private)
prefix_control :: proc(value: rune) -> Input {
	return {kind = .Key, stroke = {kind = .Unicode_Scalar, scalar = value, modifiers = {.Control}}}
}

@(private)
prefix_meta :: proc(value: rune) -> Input {
	return {kind = .Key, stroke = {kind = .Unicode_Scalar, scalar = value, modifiers = {.Meta}}}
}

@(private)
prefix_plain :: proc(value: rune) -> Input {
	return {kind = .Key, stroke = {kind = .Unicode_Scalar, scalar = value}}
}
