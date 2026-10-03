// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package interaction

import "base:runtime"
import "core:mem"
import "core:testing"

/* Verifies bounded UTF-8 text entry, scalar deletion, acceptance, and borrowed results. */
@(test)
text_prompts_complete_exact_bounded_input :: proc(t: ^testing.T) {
	prompt: Prompt
	initialized, failure := prompt_init(
		&prompt,
		Prompt_Config {
			kind = .Text_Entry,
			text_bytes_limit = 12,
			allocator = context.allocator,
		},
	)
	testing.expectf(t, initialized, "prompt init failed with %v", failure.code)
	if !initialized {
		return
	}
	defer prompt_close(&prompt)
	transition, append_failure := prompt_text_append(&prompt, "a/界")
	testing.expect_value(t, transition, Prompt_Transition.Changed)
	testing.expect_value(t, append_failure.code, Prompt_Failure_Code.None)
	transition, _ = prompt_text_delete_previous(&prompt)
	testing.expect_value(t, transition, Prompt_Transition.Changed)
	transition, _ = prompt_text_append(&prompt, "file")
	testing.expect_value(t, transition, Prompt_Transition.Changed)
	transition, _ = prompt_text_replace(&prompt, "search")
	testing.expect_value(t, transition, Prompt_Transition.Changed)
	accept_failure: Prompt_Failure
	transition, accept_failure = prompt_text_accept(&prompt)
	testing.expect_value(t, transition, Prompt_Transition.Completed)
	testing.expect_value(t, accept_failure.code, Prompt_Failure_Code.None)
	view, viewed, _ := prompt_view(&prompt)
	testing.expect(t, viewed)
	testing.expect_value(t, view.status, Prompt_Status.Accepted)
	testing.expect_value(t, view.text, "search")
	transition, append_failure = prompt_text_append(&prompt, "x")
	testing.expect_value(t, transition, Prompt_Transition.Invalid)
	testing.expect_value(t, append_failure.code, Prompt_Failure_Code.Not_Active)
}

/* Verifies invalid continuation and text limits preserve accepted prompt bytes. */
@(test)
text_prompts_reject_bad_continuation_atomically :: proc(t: ^testing.T) {
	prompt: Prompt
	initialized, _ := prompt_init(
		&prompt,
		Prompt_Config {
			kind = .Text_Entry,
			text_bytes_limit = 4,
			allocator = context.allocator,
		},
	)
	testing.expect(t, initialized)
	if !initialized {
		return
	}
	defer prompt_close(&prompt)
	_, _ = prompt_text_append(&prompt, "abc")
	transition, limit_failure := prompt_text_append(&prompt, "de")
	testing.expect_value(t, transition, Prompt_Transition.Invalid)
	testing.expect_value(t, limit_failure.code, Prompt_Failure_Code.Text_Limit)
	invalid := []byte{0xff}
	utf8_failure: Prompt_Failure
	transition, utf8_failure = prompt_text_append(&prompt, string(invalid))
	testing.expect_value(t, transition, Prompt_Transition.Invalid)
	testing.expect_value(t, utf8_failure.code, Prompt_Failure_Code.Malformed_UTF8)
	view, viewed, _ := prompt_view(&prompt)
	testing.expect(t, viewed)
	testing.expect_value(t, view.text, "abc")
}

/* Verifies fixed choices and cancellation produce explicit terminal outcomes. */
@(test)
prompts_complete_or_cancel_explicitly :: proc(t: ^testing.T) {
	choice: Prompt
	choice_ok, _ := prompt_init(
		&choice,
		Prompt_Config {
			kind = .Fixed_Choice,
			choices = []Prompt_Choice_Definition {
				{name = "Save", command_name = "prompt-choice-1"},
				{name = "Discard", command_name = "prompt-choice-2"},
				{name = "Cancel", command_name = "prompt-choice-3"},
			},
			allocator = context.allocator,
		},
	)
	testing.expect(t, choice_ok)
	if !choice_ok {
		return
	}
	transition, invalid_failure := prompt_choice_accept(&choice, 4)
	testing.expect_value(t, transition, Prompt_Transition.Invalid)
	testing.expect_value(t, invalid_failure.code, Prompt_Failure_Code.Invalid_Choice)
	transition, _ = prompt_choice_accept(&choice, 2)
	testing.expect_value(t, transition, Prompt_Transition.Completed)
	view, viewed, _ := prompt_view(&choice)
	testing.expect(t, viewed)
	testing.expect_value(t, view.status, Prompt_Status.Accepted)
	testing.expect_value(t, view.selected_choice, u8(2))
	testing.expect_value(t, view.choices[1].name, "Discard")
	testing.expect_value(t, view.choices[1].command_name, "prompt-choice-2")
	prompt_close(&choice)

	cancelled: Prompt
	cancelled_ok, _ := prompt_init(
		&cancelled,
		Prompt_Config {
			kind = .Text_Entry,
			text_bytes_limit = MAX_PROMPT_TEXT_BYTES,
			allocator = context.allocator,
		},
	)
	testing.expect(t, cancelled_ok)
	if !cancelled_ok {
		return
	}
	_, _ = prompt_text_append(&cancelled, "discarded")
	transition, _ = prompt_cancel(&cancelled)
	testing.expect_value(t, transition, Prompt_Transition.Completed)
	view, viewed, _ = prompt_view(&cancelled)
	testing.expect(t, viewed)
	testing.expect_value(t, view.status, Prompt_Status.Cancelled)
	prompt_close(&cancelled)
}

/* Verifies fixed-choice names and commands are bounded, unique, and copied. */
@(test)
choices_reject_ambiguous_alternatives :: proc(t: ^testing.T) {
	duplicate_commands := []Prompt_Choice_Definition {
		{name = "Save", command_name = "prompt-choice-1"},
		{name = "Again", command_name = "prompt-choice-1"},
	}
	prompt: Prompt
	initialized, failure := prompt_init(
		&prompt,
		Prompt_Config {
			kind = .Fixed_Choice,
			choices = duplicate_commands,
			allocator = context.allocator,
		},
	)
	testing.expect(t, !initialized)
	testing.expect_value(t, failure.code, Prompt_Failure_Code.Invalid_Config)
	testing.expect(t, prompt.state == nil)

	empty_name := []Prompt_Choice_Definition {{name = "", command_name = "prompt-choice-1"}}
	initialized, failure = prompt_init(
		&prompt,
		Prompt_Config {
			kind = .Fixed_Choice,
			choices = empty_name,
			allocator = context.allocator,
		},
	)
	testing.expect(t, !initialized)
	testing.expect_value(t, failure.code, Prompt_Failure_Code.Invalid_Config)
}

/* Verifies allocation failure and close release every prompt-owned byte. */
@(test)
prompt_storage_failures_are_atomic_and_released :: proc(t: ^testing.T) {
	for fail_after in 0 ..< 2 {
		tracking: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracking, context.allocator)
		failing := Prompt_Failing_Allocator {
			backing = mem.tracking_allocator(&tracking),
			fail_after = u64(fail_after),
		}
		prompt: Prompt
		initialized, failure := prompt_init(
			&prompt,
			Prompt_Config {
				kind = .Text_Entry,
				text_bytes_limit = MAX_PROMPT_TEXT_BYTES,
				allocator = prompt_failing_allocator(&failing),
			},
		)
		testing.expect(t, !initialized)
		testing.expect_value(t, failure.code, Prompt_Failure_Code.Persistent_Memory_Limit)
		testing.expect(t, prompt.state == nil)
		testing.expect_value(t, tracking.current_memory_allocated, i64(0))
		mem.tracking_allocator_destroy(&tracking)
	}

	choices := []Prompt_Choice_Definition {
		{name = "Save", command_name = "prompt-choice-1"},
		{name = "Discard", command_name = "prompt-choice-2"},
	}
	for fail_after in 0 ..< 2 {
		choice_tracking: mem.Tracking_Allocator
		mem.tracking_allocator_init(&choice_tracking, context.allocator)
		failing := Prompt_Failing_Allocator {
			backing = mem.tracking_allocator(&choice_tracking),
			fail_after = u64(fail_after),
		}
		failed_prompt: Prompt
		choice_initialized, choice_failure := prompt_init(
			&failed_prompt,
			Prompt_Config {
				kind = .Fixed_Choice,
				choices = choices,
				allocator = prompt_failing_allocator(&failing),
			},
		)
		testing.expect(t, !choice_initialized)
		testing.expect_value(t, choice_failure.code, Prompt_Failure_Code.Persistent_Memory_Limit)
		testing.expect(t, failed_prompt.state == nil)
		testing.expect_value(t, choice_tracking.current_memory_allocated, i64(0))
		mem.tracking_allocator_destroy(&choice_tracking)
	}

	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	prompt: Prompt
	initialized, _ := prompt_init(
		&prompt,
		Prompt_Config {
			kind = .Fixed_Choice,
			choices = []Prompt_Choice_Definition {
				{name = "Save", command_name = "prompt-choice-1"},
				{name = "Discard", command_name = "prompt-choice-2"},
				{name = "Cancel", command_name = "prompt-choice-3"},
			},
			allocator = mem.tracking_allocator(&tracking),
		},
	)
	testing.expect(t, initialized)
	if initialized {
		closed, _ := prompt_close(&prompt)
		testing.expect(t, closed)
	}
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&tracking)
}

@(private)
Prompt_Failing_Allocator :: struct {
	backing:                runtime.Allocator,
	fail_after:             u64,
	successful_allocations: u64,
}

@(private)
prompt_failing_allocator :: proc(data: ^Prompt_Failing_Allocator) -> runtime.Allocator {
	return runtime.Allocator{procedure = prompt_failing_allocator_proc, data = data}
}

@(private)
prompt_failing_allocator_proc :: proc(
	allocator_data: rawptr,
	mode: runtime.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	location := #caller_location,
) -> (result: []byte, error: runtime.Allocator_Error) {
	allocator := (^Prompt_Failing_Allocator)(allocator_data)
	if mode == .Alloc || mode == .Alloc_Non_Zeroed || mode == .Resize ||
	   mode == .Resize_Non_Zeroed {
		if allocator.successful_allocations >= allocator.fail_after {
			return nil, .Out_Of_Memory
		}
		allocator.successful_allocations += 1
	}
	return allocator.backing.procedure(
		allocator.backing.data,
		mode,
		size,
		alignment,
		old_memory,
		old_size,
		location,
	)
}
