// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../command"
import "../display"
import "../editor"
import "../interaction"
import editor_view "../view"
import "core:fmt"

/* MAX_KEYBOARD_MACRO_REPLAY_COMMANDS bounds one requested replay operation. */
MAX_KEYBOARD_MACRO_REPLAY_COMMANDS :: 4_096

@(private)
command_context_keyboard_macro_state :: proc(
	commands: ^Command_Context,
	create: bool,
) -> ^interaction.Keyboard_Macro_State {
	if commands == nil do return nil
	if commands.keyboard_macro != nil || !create do return commands.keyboard_macro
	if commands.persistent_allocator.procedure == nil do return nil
	state, allocation_error := new(
		interaction.Keyboard_Macro_State,
		commands.persistent_allocator,
	)
	if allocation_error != nil do return nil
	commands.keyboard_macro = state
	return state
}

@(private)
command_context_keyboard_macro_route :: proc(route: command.Native_Route) -> bool {
	#partial switch route {
	case .Start_Keyboard_Macro, .End_Keyboard_Macro, .Call_Last_Keyboard_Macro,
	     .Finish_Or_Call_Keyboard_Macro, .Name_Last_Keyboard_Macro,
	     .Call_Named_Keyboard_Macro:
		return true
	case:
		return false
	}
}

@(private)
command_context_keyboard_macro_record :: proc(
	commands: ^Command_Context,
	metadata: interaction.Command_Metadata,
	text: string,
	prefix: interaction.Prefix_Argument,
) {
	state := command_context_keyboard_macro_state(commands, false)
	if !interaction.keyboard_macro_is_recording(state) do return
	route, native := command.native_route_decode(metadata.route)
	if native && command_context_keyboard_macro_route(route) do return
	_, failure := interaction.keyboard_macro_append(state, metadata.name, text, prefix)
	if failure.code == .None do return
	_ = interaction.keyboard_macro_cancel(state)
	command_context_set_diagnostic(
		commands,
		fmt.tprintf("Keyboard macro recording stopped: %v", failure.code),
	)
}

@(private)
command_context_keyboard_macro_start :: proc(
	commands: ^Command_Context,
) -> (Interaction_Result, App_Failure) {
	state := command_context_keyboard_macro_state(commands, true)
	if state == nil do return {}, App_Failure{stage = .Command_Dispatch}
	started, failure := interaction.keyboard_macro_begin(state)
	if !started {
		command_context_set_diagnostic(commands, fmt.tprintf("Cannot start keyboard macro: %v", failure.code))
		return Interaction_Result{changed = true}, {}
	}
	command_context_set_diagnostic(commands, "Defining keyboard macro")
	return Interaction_Result{changed = true}, {}
}

@(private)
command_context_keyboard_macro_end :: proc(
	commands: ^Command_Context,
) -> (Interaction_Result, App_Failure) {
	state := command_context_keyboard_macro_state(commands, false)
	finished, failure := interaction.keyboard_macro_finish(state)
	if !finished {
		command_context_set_diagnostic(commands, fmt.tprintf("Cannot finish keyboard macro: %v", failure.code))
		return Interaction_Result{changed = true}, {}
	}
	command_context_set_diagnostic(commands, "Keyboard macro defined")
	return Interaction_Result{changed = true}, {}
}

@(private)
command_context_keyboard_macro_finish_or_replay :: proc(
	commands: ^Command_Context,
	buffer: ^editor.Buffer,
	view_registry: ^editor_view.Registry,
	view: editor_view.View_Handle,
	constraints: display.Viewport_Constraints,
	prefix: interaction.Prefix_Argument,
) -> (Interaction_Result, App_Failure) {
	state := command_context_keyboard_macro_state(commands, false)
	if interaction.keyboard_macro_is_recording(state) {
		return command_context_keyboard_macro_end(commands)
	}
	return command_context_keyboard_macro_replay(
		commands, buffer, view_registry, view, constraints, prefix,
	)
}

@(private)
command_context_keyboard_macro_replay :: proc(
	commands: ^Command_Context,
	buffer: ^editor.Buffer,
	view_registry: ^editor_view.Registry,
	view: editor_view.View_Handle,
	constraints: display.Viewport_Constraints,
	prefix: interaction.Prefix_Argument,
	name: string = "",
) -> (Interaction_Result, App_Failure) {
	state := command_context_keyboard_macro_state(commands, false)
	record, ready, macro_failure := interaction.keyboard_macro_replay_begin(state, name)
	if !ready {
		command_context_set_diagnostic(commands, fmt.tprintf("Keyboard macro unavailable: %v", macro_failure.code))
		return Interaction_Result{changed = true}, {}
	}
	defer interaction.keyboard_macro_replay_end(state)
	repetitions := u64(1)
	if prefix.present do repetitions = prefix.repeat_count
	if repetitions == 0 do repetitions = 1
	if record.step_count > 0 &&
	   repetitions > MAX_KEYBOARD_MACRO_REPLAY_COMMANDS / u64(record.step_count) {
		command_context_set_diagnostic(commands, "Keyboard macro repetition is too large")
		return Interaction_Result{changed = true}, {}
	}
	for _ in 0 ..< repetitions {
		for index in 0 ..< record.step_count {
			step, present := interaction.keyboard_macro_step(record, index)
			if !present {
				command_context_set_diagnostic(commands, "Keyboard macro contains an invalid step")
				return Interaction_Result{changed = true}, {}
			}
			handle, found, _ := interaction.command_lookup(commands.registry, step.command_name)
			if !found {
				command_context_set_diagnostic(
					commands,
					fmt.tprintf("Keyboard macro command is unavailable: %s", step.command_name),
				)
				return Interaction_Result{changed = true}, {}
			}
			result, step_failure := dispatch_input(
				commands,
				buffer,
				view_registry,
				view,
				{},
				constraints,
				handle,
				step.text,
				step.prefix,
			)
			if step_failure.stage != .None {
				command_context_set_diagnostic(
					commands,
					fmt.tprintf("Keyboard macro stopped at %s", step.command_name),
				)
				return Interaction_Result{changed = true}, {}
			}
			if result.exit || result.active_entry_closed || commands.prompt_workflow.mode != .None {
				return result, {}
			}
		}
	}
	command_context_set_diagnostic(commands, "Keyboard macro replayed")
	return Interaction_Result{changed = true}, {}
}

@(private)
command_context_begin_keyboard_macro_prompt :: proc(
	commands: ^Command_Context,
	mode: Prompt_Mode,
) -> (Interaction_Result, App_Failure) {
	if mode != .Keyboard_Macro_Name && mode != .Keyboard_Macro_Call {
		return {}, App_Failure{stage = .Command_Dispatch}
	}
	state := command_context_keyboard_macro_state(commands, false)
	if state == nil {
		command_context_set_diagnostic(commands, "No keyboard macro is available")
		return Interaction_Result{changed = true}, {}
	}
	prompt_ok, prompt_failure := interaction.prompt_init(
		&commands.prompt_workflow.prompt,
		interaction.Prompt_Config {
			kind = .Text_Entry,
			text_bytes_limit = interaction.MAX_COMMAND_NAME_BYTES,
			allow_empty = false,
			allocator = commands.persistent_allocator,
		},
	)
	if !prompt_ok do return {}, App_Failure{stage = .Prompt, prompt_failure = prompt_failure}
	if !prompt_workflow_begin_projection(&commands.prompt_workflow, mode) {
		_, _ = interaction.prompt_close(&commands.prompt_workflow.prompt)
		return {}, App_Failure{stage = .UI, ui = {operation = .Prepare, code = .Generation_Limit}}
	}
	if map_failure := command_context_activate_prompt_map(commands, mode); map_failure.stage != .None {
		_, _ = interaction.prompt_close(&commands.prompt_workflow.prompt)
		commands.prompt_workflow.mode = .None
		return {}, map_failure
	}
	return Interaction_Result{changed = true}, {}
}

@(private)
dispatch_keyboard_macro_prompt :: proc(
	commands: ^Command_Context,
	buffer: ^editor.Buffer,
	view_registry: ^editor_view.Registry,
	view: editor_view.View_Handle,
	input: interaction.Input,
	constraints: display.Viewport_Constraints,
) -> (Interaction_Result, App_Failure) {
	metadata, resolution, resolved, resolve_failure := command_context_resolve_prompt_input(commands, input)
	if !resolved do return {}, resolve_failure
	if resolution.kind != .Command do return {}, {}
	if command_metadata_is_cancel(metadata) {
		_, cancel_failure := interaction.prompt_cancel(&commands.prompt_workflow.prompt)
		if cancel_failure.code != .None do return {}, App_Failure{stage = .Prompt, prompt_failure = cancel_failure}
		command_context_end_prompt(commands)
		return Interaction_Result{changed = true}, {}
	}
	if command_metadata_is_contextual(metadata, .Prompt_Delete_Previous) {
		transition, prompt_failure := interaction.prompt_text_delete_previous(&commands.prompt_workflow.prompt)
		if prompt_failure.code != .None do return {}, App_Failure{stage = .Prompt, prompt_failure = prompt_failure}
		commands.prompt_workflow.rejected = false
		return Interaction_Result{changed = transition == .Changed}, {}
	}
	if command_metadata_is_contextual(metadata, .Prompt_Insert_Text) {
		transition, prompt_failure := interaction.prompt_text_append(&commands.prompt_workflow.prompt, resolution.text)
		if prompt_failure.code == .Text_Limit || prompt_failure.code == .Malformed_UTF8 {
			commands.prompt_workflow.rejected = true
			return Interaction_Result{changed = true}, {}
		}
		if prompt_failure.code != .None do return {}, App_Failure{stage = .Prompt, prompt_failure = prompt_failure}
		commands.prompt_workflow.rejected = false
		return Interaction_Result{changed = transition == .Changed}, {}
	}
	if !command_metadata_is_contextual(metadata, .Prompt_Accept) do return {}, {}
	_, accept_failure := interaction.prompt_text_accept(&commands.prompt_workflow.prompt)
	if accept_failure.code != .None {
		commands.prompt_workflow.rejected = true
		return Interaction_Result{changed = true}, {}
	}
	prompt_view, viewed, prompt_failure := interaction.prompt_view(&commands.prompt_workflow.prompt)
	if !viewed do return {}, App_Failure{stage = .Prompt, prompt_failure = prompt_failure}
	name: [interaction.MAX_COMMAND_NAME_BYTES]u8
	name_length := copy(name[:], transmute([]u8)prompt_view.text)
	mode := commands.prompt_workflow.mode
	command_context_end_prompt(commands)
	if mode == .Keyboard_Macro_Name {
		state := command_context_keyboard_macro_state(commands, false)
		named, macro_failure := interaction.keyboard_macro_name_last(state, string(name[:name_length]))
		if !named {
			command_context_set_diagnostic(commands, fmt.tprintf("Cannot name keyboard macro: %v", macro_failure.code))
			return Interaction_Result{changed = true}, {}
		}
		command_context_set_diagnostic(commands, fmt.tprintf("Keyboard macro named %s", string(name[:name_length])))
		return Interaction_Result{changed = true}, {}
	}
	return command_context_keyboard_macro_replay(
		commands,
		buffer,
		view_registry,
		view,
		constraints,
		{},
		string(name[:name_length]),
	)
}
