// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package interaction

import "core:testing"

/* Verifies recording copies canonical commands, text, and prefix arguments. */
@(test)
keyboard_macro_records_and_replays_semantic_steps :: proc(t: ^testing.T) {
	state, allocation_error := new(Keyboard_Macro_State, context.allocator)
	testing.expect(t, allocation_error == nil)
	if allocation_error != nil do return
	defer free(state, context.allocator)
	started, _ := keyboard_macro_begin(state)
	testing.expect(t, started)
	prefix := Prefix_Argument{present = true, value = 3, repeat_count = 3}
	appended, _ := keyboard_macro_append(state, "insert-text", "alpha", prefix)
	testing.expect(t, appended)
	appended, _ = keyboard_macro_append(state, "cursor-next-line", "")
	testing.expect(t, appended)
	finished, _ := keyboard_macro_finish(state)
	testing.expect(t, finished)
	record, replaying, _ := keyboard_macro_replay_begin(state)
	testing.expect(t, replaying)
	first, first_ok := keyboard_macro_step(record, 0)
	testing.expect(t, first_ok)
	testing.expect_value(t, first.command_name, "insert-text")
	testing.expect_value(t, first.text, "alpha")
	testing.expect_value(t, first.prefix, prefix)
	second, second_ok := keyboard_macro_step(record, 1)
	testing.expect(t, second_ok)
	testing.expect_value(t, second.command_name, "cursor-next-line")
	_, absent := keyboard_macro_step(record, 2)
	testing.expect(t, !absent)
	keyboard_macro_replay_end(state)
}

/* Verifies cancellation preserves the last macro and named aliases retain copies. */
@(test)
keyboard_macro_cancellation_and_names_are_independent :: proc(t: ^testing.T) {
	state, allocation_error := new(Keyboard_Macro_State, context.allocator)
	testing.expect(t, allocation_error == nil)
	if allocation_error != nil do return
	defer free(state, context.allocator)
	keyboard_macro_begin(state)
	keyboard_macro_append(state, "insert-text", "first")
	keyboard_macro_finish(state)
	named, _ := keyboard_macro_name_last(state, "first-macro")
	testing.expect(t, named)
	keyboard_macro_begin(state)
	keyboard_macro_append(state, "insert-text", "discarded")
	testing.expect(t, keyboard_macro_cancel(state))
	record, replaying, _ := keyboard_macro_replay_begin(state, "first-macro")
	testing.expect(t, replaying)
	step, found := keyboard_macro_step(record, 0)
	testing.expect(t, found)
	testing.expect_value(t, step.text, "first")
	keyboard_macro_replay_end(state)
	keyboard_macro_begin(state)
	keyboard_macro_append(state, "insert-text", "second")
	keyboard_macro_finish(state)
	record, replaying, _ = keyboard_macro_replay_begin(state, "first-macro")
	testing.expect(t, replaying)
	step, found = keyboard_macro_step(record, 0)
	testing.expect(t, found)
	testing.expect_value(t, step.text, "first")
	keyboard_macro_replay_end(state)
}

/* Verifies bounds and replay state fail without replacing the last valid macro. */
@(test)
keyboard_macro_contains_limits_and_invalid_transitions :: proc(t: ^testing.T) {
	state, allocation_error := new(Keyboard_Macro_State, context.allocator)
	testing.expect(t, allocation_error == nil)
	if allocation_error != nil do return
	defer free(state, context.allocator)
	_, replayed, missing := keyboard_macro_replay_begin(state)
	testing.expect(t, !replayed)
	testing.expect_value(t, missing.code, Keyboard_Macro_Failure_Code.No_Macro)
	keyboard_macro_begin(state)
	too_large := make([]u8, MAX_KEYBOARD_MACRO_TEXT_BYTES + 1, context.temp_allocator)
	defer delete(too_large, context.temp_allocator)
	appended, failure := keyboard_macro_append(state, "insert-text", string(too_large))
	testing.expect(t, !appended)
	testing.expect_value(t, failure.code, Keyboard_Macro_Failure_Code.Text_Limit)
	testing.expect(t, keyboard_macro_cancel(state))
}
