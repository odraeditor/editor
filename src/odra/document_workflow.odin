// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../command"
import "../document"
import "../editor"
import "../editor_session"
import "../interaction"
import "base:runtime"
import "core:os"
import "core:strconv"
import "core:unicode/utf8"

@(private)
Dir_Abandonment_Continuation :: enum u8 {
	None,
	Open_Path,
	Exit,
}

@(private)
Document_Workflow_State :: struct {
	buffer_command: interaction.Command_Handle,
	kill_entry:     editor_session.Entry_Handle,
	kill_label:     editor_session.Closure_Label,
	exit_entries:   [editor_session.MAX_LIVE_BUFFERS]editor_session.Entry_Handle,
	exit_count:     u32,
	exit_index:     u32,
	exit_command:   interaction.Command_Handle,
	dir_abandonment: editor_session.Dir_Abandonment_Preparation,
	dir_abandonment_continuation: Dir_Abandonment_Continuation,
	dir_abandonment_next_root: u32,
	dir_abandonment_open_path: [document.MAX_PATH_BYTES]u8,
	dir_abandonment_open_path_length: int,
	deferred_text: []u8,
	deferred_text_allocator: runtime.Allocator,
	deferred_argument: i64,
	deferred_command: interaction.Command_Handle,
}

@(private)
document_workflow_reset_transient :: proc(state: ^Document_Workflow_State) {
	if state == nil {
		return
	}
	state.buffer_command = {}
	state.kill_entry = {}
	state.kill_label = {}
}

@(private)
document_workflow_clear_deferred_text :: proc(state: ^Document_Workflow_State) {
	if state == nil do return
	if state.deferred_text != nil && state.deferred_text_allocator.procedure != nil {
		delete(state.deferred_text, state.deferred_text_allocator)
	}
	state.deferred_text = nil
	state.deferred_text_allocator = {}
	state.deferred_command = {}
}

@(private)
document_workflow_clear_deferred_argument :: proc(state: ^Document_Workflow_State) {
	if state == nil do return
	state.deferred_argument = 0
	state.deferred_command = {}
}

@(private)
command_context_begin_alternate_file :: proc(
	commands: ^Command_Context,
	command_handle: interaction.Command_Handle,
) -> (Interaction_Result, App_Failure) {
	if commands.session_owner == nil || !editor_session.entry_handle_is_valid(commands.current_entry) {
		return {}, App_Failure{stage = .Session_Access}
	}
	assessment, assessed, assess_failure := editor_session.session_assess_buffer_close(
		commands.session_owner,
		commands.current_entry,
	)
	if !assessed do return {}, App_Failure{stage = .Session_Access, editor_session = assess_failure}
	if assessment.modified {
		command_context_set_diagnostic(commands, "Save or discard changes before replacing the current buffer")
		return Interaction_Result{changed = true}, {}
	}
	commands.document_workflow.kill_entry = commands.current_entry
	return filesystem_path_navigation_begin(commands, .Find_Alternate_File, command_handle)
}

@(private)
document_workflow_reset_exit :: proc(state: ^Document_Workflow_State) {
	if state == nil {
		return
	}
	for index in 0 ..< int(state.exit_count) {
		state.exit_entries[index] = {}
	}
	state.exit_count = 0
	state.exit_index = 0
	state.exit_command = {}
	if state.dir_abandonment_continuation == .Exit {
		document_workflow_reset_dir_abandonment(state)
	}
}

@(private)
document_workflow_reset_dir_abandonment :: proc(state: ^Document_Workflow_State) {
	if state == nil {
		return
	}
	editor_session.session_abort_dir_abandonment(&state.dir_abandonment)
	state.dir_abandonment_continuation = .None
	state.dir_abandonment_next_root = 0
	state.dir_abandonment_open_path_length = 0
}

@(private)
dispatch_buffer_session_prompt :: proc(
	commands: ^Command_Context,
	input: interaction.Input,
) -> (Interaction_Result, App_Failure) {
	metadata, resolution, resolved, resolve_failure := command_context_resolve_prompt_input(commands, input)
	if !resolved {
		return {}, resolve_failure
	}
	if resolution.kind != .Command {
		return {}, {}
	}
	if command_metadata_is_cancel(metadata) {
		_, cancel_failure := interaction.prompt_cancel(&commands.prompt_workflow.prompt)
		if cancel_failure.code != .None {
			return {}, App_Failure{stage = .Prompt, prompt_failure = cancel_failure}
		}
		command_context_deactivate_prompt_map(commands, .Cancelled)
		command_context_end_prompt(commands)
		return Interaction_Result{changed = true}, {}
	}
	if command_metadata_is_contextual(metadata, .Prompt_Delete_Previous) {
		transition, prompt_failure := interaction.prompt_text_delete_previous(&commands.prompt_workflow.prompt)
		if prompt_failure.code != .None {
			return {}, App_Failure{stage = .Prompt, prompt_failure = prompt_failure}
		}
		commands.prompt_workflow.rejected = false
		return Interaction_Result{changed = transition == .Changed}, {}
	}
	if command_metadata_is_contextual(metadata, .Prompt_Accept) {
		_, accept_failure := interaction.prompt_text_accept(&commands.prompt_workflow.prompt)
		if accept_failure.code != .None {
			commands.prompt_workflow.rejected = true
			return Interaction_Result{changed = true}, {}
		}
		view, viewed, view_failure := interaction.prompt_view(&commands.prompt_workflow.prompt)
		if !viewed {
			return {}, App_Failure{stage = .Prompt, prompt_failure = view_failure}
		}
		path := view.text
		request := command.Buffer_Session_Context {
			session = commands.session_owner,
			handle = commands.session_handle,
			command = commands.document_workflow.buffer_command,
			configuration = commands.entry_configuration,
		}
		result: command.Buffer_Session_Result
		completed := false
		command_failure: command.Failure_Context
		find_file_other_pane := commands.prompt_workflow.mode == .Find_File_Other_Pane
		if commands.prompt_workflow.mode == .Find_File || find_file_other_pane {
			path_storage: [document.MAX_PATH_BYTES]u8
			path_ok: bool
			path, path_ok = command_context_expand_home_path(commands, path, path_storage[:])
			if !path_ok {
				command_context_end_prompt(commands)
				command_context_set_diagnostic(commands, "Home-relative path exceeds the path limit")
				return Interaction_Result{changed = true}, {}
			}
			result, completed, command_failure = command.buffer_session_find_file(request, path)
		} else if commands.prompt_workflow.mode == .Switch_To_Buffer {
			result, completed, command_failure = command.buffer_session_switch_to_buffer(
				request,
				view.text,
			)
		} else {
			if entry, live := command_context_live_terminal_named(commands, view.text); live {
				return command_context_begin_terminal_kill(commands, request.command, entry)
			}
			kill_result, killed, kill_failure := command_context_kill_buffer(
				commands,
				view.text,
			)
			if !killed {
				command_context_end_prompt(commands)
				command_context_buffer_session_diagnostic(commands, kill_failure)
				return Interaction_Result{changed = true}, {}
			}
			if kill_result.completion == .Discard_Required {
				return command_context_begin_kill_choice(commands, request.command, kill_result.closure)
			}
			command_context_end_prompt(commands)
			fallback_ok, fallback_failure := command_context_ensure_text_fallback(
				commands,
				kill_result.closure,
			)
			if !fallback_ok {
				return {}, fallback_failure
			}
			command_context_set_diagnostic(commands, "Killed buffer")
			return Interaction_Result {
				changed = true,
				active_entry_closed = kill_result.closure.was_visible,
			}, {}
		}
		command_context_end_prompt(commands)
		if !completed {
			command_context_buffer_session_diagnostic(commands, command_failure)
			return Interaction_Result{changed = true}, {}
		}
		if find_file_other_pane {
			displayed, display_failure := command_context_layout_display_entry(
				commands,
				result.entry,
				true,
			)
			if !displayed {
				if editor_session.entry_handle_is_valid(commands.layout_entry) {
					_, _, _ = editor_session.session_activate(
						commands.session_owner,
						commands.layout_entry,
					)
				}
				command_context_layout_display_diagnostic(commands, display_failure)
				return Interaction_Result{changed = true}, {}
			}
		}
		switch result.completion {
		case .Opened:         command_context_set_diagnostic(commands, "Opened file")
		case .Reused:         command_context_set_diagnostic(commands, "Selected open file")
		case .Created:        command_context_set_diagnostic(commands, "Created buffer")
		case .Activated:      command_context_set_diagnostic(commands, "Switched buffer")
		case .Already_Active: command_context_set_diagnostic(commands, "Buffer already active")
		case .Invalid:        return {}, App_Failure{stage = .Command_Dispatch}
		}
		return Interaction_Result{changed = true}, {}
	}
	if command_metadata_is_contextual(metadata, .Prompt_Insert_Text) {
		transition, prompt_failure := interaction.prompt_text_append(&commands.prompt_workflow.prompt, resolution.text)
		if prompt_failure.code == .Text_Limit || prompt_failure.code == .Malformed_UTF8 {
			commands.prompt_workflow.rejected = true
			return Interaction_Result{changed = true}, {}
		}
		if prompt_failure.code != .None {
			return {}, App_Failure{stage = .Prompt, prompt_failure = prompt_failure}
		}
		commands.prompt_workflow.rejected = false
		return Interaction_Result{changed = transition == .Changed}, {}
	}
	return {}, {}
}

@(private)
command_context_live_terminal_named :: proc(
	commands: ^Command_Context,
	name: string,
) -> (editor_session.Entry_Handle, bool) {
	if commands == nil || commands.session_owner == nil do return {}, false
	descriptors, copied, _ := editor_session.session_descriptors(
		commands.session_owner,
		commands.session_handle,
		commands.temporary_allocator,
	)
	if !copied do return {}, false
	defer editor_session.descriptor_batch_close(&descriptors)
	for descriptor in descriptors.descriptors {
		if descriptor.kind != .Terminal || descriptor.selection_label != name do continue
		state, inspected, _ := editor_session.session_terminal_buffer_state(
			commands.session_owner,
			descriptor.graph.entry,
		)
		return descriptor.graph.entry, inspected && state.lifecycle == .Running
	}
	return {}, false
}

@(private)
command_context_begin_terminal_kill :: proc(
	commands: ^Command_Context,
	command_handle: interaction.Command_Handle,
	entry: editor_session.Entry_Handle,
) -> (Interaction_Result, App_Failure) {
	label, label_ok, label_failure := editor_session.session_entry_label(commands.session_owner, entry)
	if !label_ok do return {}, App_Failure{stage = .Session_Access, editor_session = label_failure}
	command_context_end_prompt(commands)
	choices := prompt_yes_no_choices()
	prompt_ok, prompt_failure := interaction.prompt_init(
		&commands.prompt_workflow.prompt,
		interaction.Prompt_Config {
			kind = .Fixed_Choice,
			choices = choices[:],
			allocator = commands.persistent_allocator,
		},
	)
	if !prompt_ok do return {}, App_Failure{stage = .Prompt, prompt_failure = prompt_failure}
	if !prompt_workflow_begin_projection(&commands.prompt_workflow, .Terminal_Kill_Choice) {
		_, _ = interaction.prompt_close(&commands.prompt_workflow.prompt)
		return {}, App_Failure{stage = .UI, ui = {operation = .Prepare, code = .Generation_Limit}}
	}
	commands.document_workflow.buffer_command = command_handle
	commands.document_workflow.kill_entry = entry
	commands.document_workflow.kill_label = label
	if map_failure := command_context_activate_prompt_map(commands, .Terminal_Kill_Choice);
	   map_failure.stage != .None {
		_, _ = interaction.prompt_close(&commands.prompt_workflow.prompt)
		commands.prompt_workflow.mode = .None
		return {}, map_failure
	}
	return Interaction_Result{changed = true}, {}
}

@(private)
dispatch_terminal_kill_prompt :: proc(
	commands: ^Command_Context,
	input: interaction.Input,
) -> (Interaction_Result, App_Failure) {
	metadata, resolution, resolved, resolve_failure := command_context_resolve_prompt_input(commands, input)
	if !resolved do return {}, resolve_failure
	if resolution.kind != .Command do return {}, {}
	if command_metadata_is_cancel(metadata) {
		_, _ = interaction.prompt_cancel(&commands.prompt_workflow.prompt)
		command_context_deactivate_prompt_map(commands, .Cancelled)
		command_context_end_prompt(commands)
		return Interaction_Result{changed = true}, {}
	}
	choice := command_metadata_prompt_choice(metadata)
	if choice < 1 || choice > 2 do return {}, {}
	_, choice_failure := interaction.prompt_choice_accept(&commands.prompt_workflow.prompt, choice)
	if choice_failure.code != .None do return {}, App_Failure{stage = .Prompt, prompt_failure = choice_failure}
	command_context_deactivate_prompt_map(commands, .Completed)
	if choice == 2 {
		command_context_end_prompt(commands)
		return Interaction_Result{changed = true}, {}
	}
	entry := commands.document_workflow.kill_entry
	state, state_ok, state_failure := editor_session.session_terminal_buffer_state(commands.session_owner, entry)
	if !state_ok do return {}, App_Failure{stage = .Session_Access, editor_session = state_failure}
	disposed, dispose_failure := terminal_workflow_dispose(
		commands.terminal_workflow,
		terminal_session_ref(state.terminal),
	)
	if !disposed do return {}, app_terminal_workflow_failure(dispose_failure)
	label := editor_session.closure_label_text(&commands.document_workflow.kill_label)
	kill_result, killed, kill_failure := command_context_kill_buffer(
		commands,
		label,
		.Discard_Modified,
		state.terminal,
	)
	command_context_end_prompt(commands)
	if !killed || kill_result.completion != .Closed {
		command_context_buffer_session_diagnostic(commands, kill_failure)
		return Interaction_Result{changed = true}, {}
	}
	fallback_ok, fallback_failure := command_context_ensure_text_fallback(commands, kill_result.closure)
	if !fallback_ok do return {}, fallback_failure
	command_context_set_diagnostic(commands, "Terminated and closed terminal")
	return Interaction_Result {
		changed = true,
		active_entry_closed = kill_result.closure.was_visible,
	}, {}
}


@(private)
dispatch_exit_choice_prompt :: proc(
	commands: ^Command_Context,
	buffer: ^editor.Buffer,
	input: interaction.Input,
) -> (Interaction_Result, App_Failure) {
	metadata, resolution, resolved, resolve_failure := command_context_resolve_prompt_input(commands, input)
	if !resolved {
		return {}, resolve_failure
	}
	if resolution.kind != .Command {
		return {}, {}
	}
	if command_metadata_is_cancel(metadata) {
		_, cancel_failure := interaction.prompt_cancel(&commands.prompt_workflow.prompt)
		if cancel_failure.code != .None {
			return {}, App_Failure{stage = .Prompt, prompt_failure = cancel_failure}
		}
		command_context_deactivate_prompt_map(commands, .Cancelled)
		command_context_end_prompt(commands)
		command_context_clear_exit(commands)
		return Interaction_Result{changed = true}, {}
	}
	choice := command_metadata_prompt_choice(metadata)
	if choice == 0 {
		return {}, {}
	}
	_, choice_failure := interaction.prompt_choice_accept(&commands.prompt_workflow.prompt, choice)
	if choice_failure.code != .None {
		return {}, App_Failure{stage = .Prompt, prompt_failure = choice_failure}
	}
	switch choice {
	case 1:
		return command_context_save_for_exit(commands, buffer)
	case 2:
		command_context_end_prompt(commands)
		if commands.session_owner == nil {
			command_context_clear_exit(commands)
			return Interaction_Result{exit = true}, {}
		}
		commands.document_workflow.exit_index += 1
		return command_context_advance_exit(commands)
	case 3:
		command_context_end_prompt(commands)
		command_context_clear_exit(commands)
		return Interaction_Result{changed = true}, {}
	}
	unreachable()
}

@(private)
command_context_begin_last_pane_exit :: proc(
	commands: ^Command_Context,
	command_handle: interaction.Command_Handle,
) -> (Interaction_Result, App_Failure) {
	choices := prompt_yes_no_choices()
	prompt_ok, prompt_failure := interaction.prompt_init(
		&commands.prompt_workflow.prompt,
		interaction.Prompt_Config {
			kind = .Fixed_Choice,
			choices = choices[:],
			allocator = commands.persistent_allocator,
		},
	)
	if !prompt_ok do return {}, App_Failure{stage = .Prompt, prompt_failure = prompt_failure}
	if !prompt_workflow_begin_projection(&commands.prompt_workflow, .Last_Pane_Exit_Choice) {
		_, _ = interaction.prompt_close(&commands.prompt_workflow.prompt)
		return {}, App_Failure{stage = .UI, ui = {operation = .Prepare, code = .Generation_Limit}}
	}
	commands.document_workflow.exit_command = command_handle
	if map_failure := command_context_activate_prompt_map(commands, .Last_Pane_Exit_Choice);
	   map_failure.stage != .None {
		_, _ = interaction.prompt_close(&commands.prompt_workflow.prompt)
		commands.prompt_workflow.mode = .None
		command_context_clear_exit(commands)
		return {}, map_failure
	}
	return Interaction_Result{changed = true}, {}
}

@(private)
dispatch_last_pane_exit_prompt :: proc(
	commands: ^Command_Context,
	input: interaction.Input,
) -> (Interaction_Result, App_Failure) {
	metadata, resolution, resolved, resolve_failure := command_context_resolve_prompt_input(commands, input)
	if !resolved do return {}, resolve_failure
	if resolution.kind != .Command do return {}, {}
	if command_metadata_is_cancel(metadata) {
		_, cancel_failure := interaction.prompt_cancel(&commands.prompt_workflow.prompt)
		if cancel_failure.code != .None {
			return {}, App_Failure{stage = .Prompt, prompt_failure = cancel_failure}
		}
		command_context_end_prompt(commands)
		command_context_clear_exit(commands)
		return Interaction_Result{changed = true}, {}
	}
	choice := command_metadata_prompt_choice(metadata)
	if choice < 1 || choice > 2 do return {}, {}
	_, choice_failure := interaction.prompt_choice_accept(&commands.prompt_workflow.prompt, choice)
	if choice_failure.code != .None {
		return {}, App_Failure{stage = .Prompt, prompt_failure = choice_failure}
	}
	command_handle := commands.document_workflow.exit_command
	command_context_end_prompt(commands)
	if choice == 2 {
		command_context_clear_exit(commands)
		return Interaction_Result{changed = true}, {}
	}
	return command_context_request_exit(commands, command_handle, nil)
}

@(private)
command_context_begin_kill_choice :: proc(
	commands: ^Command_Context,
	command_handle: interaction.Command_Handle,
	closure: editor_session.Closure_Result,
) -> (Interaction_Result, App_Failure) {
	command_context_end_prompt(commands)
	unassociated := closure.association == .Unassociated
	yes_no_choices := prompt_yes_no_choices()
	save_discard_cancel_choices := prompt_save_discard_cancel_choices()
	choices := yes_no_choices[:]
	if unassociated do choices = save_discard_cancel_choices[:]
	prompt_ok, prompt_failure := interaction.prompt_init(
		&commands.prompt_workflow.prompt,
		interaction.Prompt_Config {
			kind = .Fixed_Choice,
			choices = choices,
			allocator = commands.persistent_allocator,
		},
	)
	if !prompt_ok {
		return {}, App_Failure{stage = .Prompt, prompt_failure = prompt_failure}
	}
	mode := Prompt_Mode.Kill_Unassociated_Choice if unassociated else .Kill_File_Discard_Choice
	if !prompt_workflow_begin_projection(&commands.prompt_workflow, mode) {
		_, _ = interaction.prompt_close(&commands.prompt_workflow.prompt)
		return {}, App_Failure{stage = .UI, ui = {operation = .Prepare, code = .Generation_Limit}}
	}
	commands.document_workflow.buffer_command = command_handle
	commands.document_workflow.kill_entry = closure.graph.entry
	commands.document_workflow.kill_label = closure.selection_label
	if map_failure := command_context_activate_prompt_map(commands, commands.prompt_workflow.mode); map_failure.stage != .None {
		_, _ = interaction.prompt_close(&commands.prompt_workflow.prompt)
		commands.prompt_workflow.mode = .None
		return {}, map_failure
	}
	return Interaction_Result{changed = true}, {}
}

@(private)
dispatch_kill_choice_prompt :: proc(
	commands: ^Command_Context,
	input: interaction.Input,
) -> (Interaction_Result, App_Failure) {
	metadata, resolution, resolved, resolve_failure := command_context_resolve_prompt_input(commands, input)
	if !resolved {
		return {}, resolve_failure
	}
	if resolution.kind != .Command {
		return {}, {}
	}
	if command_metadata_is_cancel(metadata) {
		_, cancel_failure := interaction.prompt_cancel(&commands.prompt_workflow.prompt)
		if cancel_failure.code != .None {
			return {}, App_Failure{stage = .Prompt, prompt_failure = cancel_failure}
		}
		command_context_deactivate_prompt_map(commands, .Cancelled)
		command_context_end_prompt(commands)
		return Interaction_Result{changed = true}, {}
	}
	unassociated := commands.prompt_workflow.mode == .Kill_Unassociated_Choice
	choice := command_metadata_prompt_choice(metadata)
	if choice == 0 {
		return {}, {}
	}
	_, choice_failure := interaction.prompt_choice_accept(&commands.prompt_workflow.prompt, choice)
	if choice_failure.code != .None {
		return {}, App_Failure{stage = .Prompt, prompt_failure = choice_failure}
	}
	if unassociated && choice == 1 {
		command_handle := commands.document_workflow.buffer_command
		entry := commands.document_workflow.kill_entry
		command_context_end_prompt(commands)
		prompt_ok, prompt_failure := interaction.prompt_init(
			&commands.prompt_workflow.prompt,
			interaction.Prompt_Config {
				kind = .Text_Entry,
				text_bytes_limit = document.MAX_PATH_BYTES,
				allocator = commands.persistent_allocator,
			},
		)
		if !prompt_ok {
			return {}, App_Failure{stage = .Prompt, prompt_failure = prompt_failure}
		}
		if !prompt_workflow_begin_projection(&commands.prompt_workflow, .Kill_Save_Path) {
			_, _ = interaction.prompt_close(&commands.prompt_workflow.prompt)
			return {}, App_Failure{stage = .UI, ui = {operation = .Prepare, code = .Generation_Limit}}
		}
		commands.document_workflow.buffer_command = command_handle
		commands.document_workflow.kill_entry = entry
		if map_failure := command_context_activate_prompt_map(commands, .Kill_Save_Path); map_failure.stage != .None {
			_, _ = interaction.prompt_close(&commands.prompt_workflow.prompt)
			commands.prompt_workflow.mode = .None
			return {}, map_failure
		}
		return Interaction_Result{changed = true}, {}
	}
	if (unassociated && choice == 3) || (!unassociated && choice == 2) {
		command_context_end_prompt(commands)
		return Interaction_Result{changed = true}, {}
	}
	return command_context_kill_with_authority(commands, .Discard_Modified)
}

@(private)
command_context_kill_with_authority :: proc(
	commands: ^Command_Context,
	authority: editor_session.Close_Authority,
) -> (Interaction_Result, App_Failure) {
	label := editor_session.closure_label_text(&commands.document_workflow.kill_label)
	result, killed, kill_failure := command_context_kill_buffer(
		commands,
		label,
		authority,
	)
	command_context_end_prompt(commands)
	if !killed || result.completion != .Closed {
		command_context_buffer_session_diagnostic(commands, kill_failure)
		return Interaction_Result{changed = true}, {}
	}
	fallback_ok, fallback_failure := command_context_ensure_text_fallback(commands, result.closure)
	if !fallback_ok {
		return {}, fallback_failure
	}
	command_context_set_diagnostic(commands, "Killed buffer")
	return Interaction_Result {
		changed = true,
		active_entry_closed = result.closure.was_visible,
	}, {}
}

@(private)
dispatch_save_path_prompt :: proc(
	commands: ^Command_Context,
	buffer: ^editor.Buffer,
	input: interaction.Input,
) -> (Interaction_Result, App_Failure) {
	metadata, resolution, resolved, resolve_failure := command_context_resolve_prompt_input(commands, input)
	if !resolved {
		return {}, resolve_failure
	}
	if resolution.kind != .Command {
		return {}, {}
	}
	if command_metadata_is_cancel(metadata) {
		exit_prompt := commands.prompt_workflow.mode == .Exit_Save_Path
		_, cancel_failure := interaction.prompt_cancel(&commands.prompt_workflow.prompt)
		if cancel_failure.code != .None {
			return {}, App_Failure{stage = .Prompt, prompt_failure = cancel_failure}
		}
		command_context_deactivate_prompt_map(commands, .Cancelled)
		command_context_end_prompt(commands)
		if exit_prompt {
			command_context_clear_exit(commands)
		}
		return Interaction_Result{changed = true}, {}
	}
	if command_metadata_is_contextual(metadata, .Prompt_Delete_Previous) {
		transition, prompt_failure := interaction.prompt_text_delete_previous(&commands.prompt_workflow.prompt)
		if prompt_failure.code != .None {
			return {}, App_Failure{stage = .Prompt, prompt_failure = prompt_failure}
		}
		commands.prompt_workflow.rejected = false
		return Interaction_Result{changed = transition == .Changed}, {}
	}
	if command_metadata_is_contextual(metadata, .Prompt_Accept) {
		exit_after_save := commands.prompt_workflow.mode == .Exit_Save_Path
		kill_after_save := commands.prompt_workflow.mode == .Kill_Save_Path
		write_file := commands.prompt_workflow.mode == .Write_File_Path
		_, accept_failure := interaction.prompt_text_accept(&commands.prompt_workflow.prompt)
		if accept_failure.code != .None {
			commands.prompt_workflow.rejected = true
			return Interaction_Result{changed = true}, {}
		}
		view, viewed, view_failure := interaction.prompt_view(&commands.prompt_workflow.prompt)
		if !viewed {
			return {}, App_Failure{stage = .Prompt, prompt_failure = view_failure}
		}
		path_storage: [document.MAX_PATH_BYTES]u8
		path, path_ok := command_context_expand_home_path(commands, view.text, path_storage[:])
		if !path_ok {
			command_context_end_prompt(commands)
			if exit_after_save do command_context_clear_exit(commands)
			command_context_set_diagnostic(commands, "Home-relative path exceeds the path limit")
			return Interaction_Result{changed = true}, {}
		}
		if kill_after_save {
			request := command.Buffer_Session_Context {
				session = commands.session_owner,
				handle = commands.session_handle,
				command = commands.document_workflow.buffer_command,
				configuration = commands.entry_configuration,
			}
			entry := commands.document_workflow.kill_entry
			save_result, saved, save_failure := command.buffer_session_first_save(
				request,
				entry,
				path,
			)
			command_context_end_prompt(commands)
			if !saved {
				command_context_first_save_diagnostic(commands, save_failure)
				return Interaction_Result{changed = true, save = save_result.save}, {}
			}
			kill_result, killed, kill_failure := command_context_kill_buffer(
				commands,
				editor_session.closure_label_text(&save_result.selection_label),
			)
			if !killed || kill_result.completion != .Closed {
				command_context_buffer_session_diagnostic(commands, kill_failure)
				return Interaction_Result{changed = true, save = save_result.save}, {}
			}
			fallback_ok, fallback_failure := command_context_ensure_text_fallback(
				commands,
				kill_result.closure,
			)
			if !fallback_ok {
				return {}, fallback_failure
			}
			command_context_set_channel_diagnostic(commands, .Save, "Saved and killed buffer")
			return Interaction_Result {
				changed = true,
				active_entry_closed = kill_result.closure.was_visible,
				save = save_result.save,
			}, {}
		}
		if commands.session_owner != nil &&
		   (exit_after_save || editor_session.entry_handle_is_valid(commands.current_entry)) {
			entry := commands.current_entry
			if exit_after_save {
				if commands.document_workflow.exit_index >= commands.document_workflow.exit_count {
					command_context_end_prompt(commands)
					command_context_clear_exit(commands)
					return {}, App_Failure{stage = .Command_Dispatch}
				}
				entry = commands.document_workflow.exit_entries[commands.document_workflow.exit_index]
			}
			request := command.Buffer_Session_Context {
				session = commands.session_owner,
				handle = commands.session_handle,
				command = commands.document_workflow.exit_command,
				configuration = commands.entry_configuration,
			}
			if !exit_after_save {
				request.command = commands.document_workflow.buffer_command
			}
			save_result: editor_session.Associate_Save_Result
			saved := false
			save_failure: command.Failure_Context
			if write_file {
				save_result, saved, save_failure = command.buffer_session_write_file(request, entry, path)
			} else {
				save_result, saved, save_failure = command.buffer_session_first_save(request, entry, path)
			}
			command_context_end_prompt(commands)
			if !saved {
				command_context_first_save_diagnostic(commands, save_failure)
				if exit_after_save {
					command_context_clear_exit(commands)
				}
				return Interaction_Result{changed = true, save = save_result.save}, {}
			}
			if exit_after_save {
				commands.document_workflow.exit_index += 1
				advanced, advance_failure := command_context_advance_exit(commands)
				advanced.save = save_result.save
				return advanced, advance_failure
			}
			command_context_set_channel_diagnostic(commands, .Save, "Saved")
			return Interaction_Result{changed = true, save = save_result.save}, {}
		}
		association: document.Prepared_Association
		associated, association_failure := document.document_association_prepare(
			commands.document_owner,
			path,
			&association,
			document.Allocator_Set {
				persistent = commands.persistent_allocator,
				temporary = commands.temporary_allocator,
			},
		)
		command_context_end_prompt(commands)
		if !associated {
			command_context_document_diagnostic(commands, "Save failed", association_failure)
			return Interaction_Result{changed = true}, {}
		}
		result, saved, save_failure := document.prepared_association_publish(&association, buffer)
		if !saved {
			command_context_document_diagnostic(commands, "Save failed", save_failure)
			return Interaction_Result{changed = true, save = result}, {}
		}
		command_context_set_channel_diagnostic(commands, .Save, "Saved")
		return Interaction_Result{changed = true, exit = exit_after_save, save = result}, {}
	}
	if command_metadata_is_contextual(metadata, .Prompt_Insert_Text) {
		transition, prompt_failure := interaction.prompt_text_append(&commands.prompt_workflow.prompt, resolution.text)
		if prompt_failure.code == .Text_Limit || prompt_failure.code == .Malformed_UTF8 {
			commands.prompt_workflow.rejected = true
			return Interaction_Result{changed = true}, {}
		}
		if prompt_failure.code != .None {
			return {}, App_Failure{stage = .Prompt, prompt_failure = prompt_failure}
		}
		commands.prompt_workflow.rejected = false
		return Interaction_Result{changed = transition == .Changed}, {}
	}
	return {}, {}
}

@(private)
command_context_request_exit :: proc(
	commands: ^Command_Context,
	command_handle: interaction.Command_Handle,
	buffer: ^editor.Buffer,
) -> (Interaction_Result, App_Failure) {
	if commands.session_owner == nil {
		status, status_ok, status_failure := document.document_status(commands.document_owner)
		if !status_ok {
			return {}, App_Failure{stage = .Document_Inspect, document = status_failure}
		}
		stats, stats_ok, stats_failure := editor.buffer_stats(buffer)
		if !stats_ok {
			return {}, App_Failure{stage = .Document_Inspect, editor = stats_failure}
		}
		clean := status.persistence == .Clean && status.has_saved_revision &&
		         status.saved_revision == stats.revision
		if clean {
			return Interaction_Result{exit = true}, {}
		}
		choices := prompt_save_discard_cancel_choices()
		prompt_ok, prompt_failure := interaction.prompt_init(
			&commands.prompt_workflow.prompt,
			interaction.Prompt_Config {
				kind = .Fixed_Choice,
				choices = choices[:],
				allocator = commands.persistent_allocator,
			},
		)
		if !prompt_ok {
			return {}, App_Failure{stage = .Prompt, prompt_failure = prompt_failure}
		}
		if !prompt_workflow_begin_projection(&commands.prompt_workflow, .Exit_Choice) {
			_, _ = interaction.prompt_close(&commands.prompt_workflow.prompt)
			return {}, App_Failure{stage = .UI, ui = {operation = .Prepare, code = .Generation_Limit}}
		}
		if map_failure := command_context_activate_prompt_map(commands, .Exit_Choice); map_failure.stage != .None {
			_, _ = interaction.prompt_close(&commands.prompt_workflow.prompt)
			commands.prompt_workflow.mode = .None
			return {}, map_failure
		}
		return Interaction_Result{changed = true}, {}
	}
	command_context_clear_exit(commands)
	count, copied, copy_failure := editor_session.session_mru_entries(
		commands.session_owner,
		commands.session_handle,
		commands.document_workflow.exit_entries[:],
	)
	if !copied {
		return {}, App_Failure{stage = .Session_Access, editor_session = copy_failure}
	}
	commands.document_workflow.exit_count = count
	commands.document_workflow.exit_command = command_handle
	return command_context_advance_exit(commands)
}

@(private)
command_context_advance_exit :: proc(
	commands: ^Command_Context,
) -> (Interaction_Result, App_Failure) {
	if commands.terminal_workflow != nil && commands.terminal_workflow.initialized &&
	   !commands.terminal_workflow.exit_confirmed &&
	   terminal_workflow_live_count(commands.terminal_workflow) > 0 {
		return command_context_begin_terminal_exit(commands)
	}
	for commands.document_workflow.exit_index < commands.document_workflow.exit_count {
		entry := commands.document_workflow.exit_entries[commands.document_workflow.exit_index]
		assessment, assessed, assess_failure := editor_session.session_assess_buffer_close(
			commands.session_owner,
			entry,
		)
		if !assessed {
			if assess_failure.code == .Terminal_Coordination_Required {
				commands.document_workflow.exit_index += 1
				continue
			}
			command_context_clear_exit(commands)
			return {}, App_Failure{stage = .Session_Access, editor_session = assess_failure}
		}
		if !assessment.modified {
			commands.document_workflow.exit_index += 1
			continue
		}
		choices := prompt_save_discard_cancel_choices()
		prompt_ok, prompt_failure := interaction.prompt_init(
			&commands.prompt_workflow.prompt,
			interaction.Prompt_Config {
				kind = .Fixed_Choice,
				choices = choices[:],
				allocator = commands.persistent_allocator,
			},
		)
		if !prompt_ok {
			command_context_clear_exit(commands)
			return {}, App_Failure{stage = .Prompt, prompt_failure = prompt_failure}
		}
		if !prompt_workflow_begin_projection(&commands.prompt_workflow, .Exit_Choice) {
			_, _ = interaction.prompt_close(&commands.prompt_workflow.prompt)
			command_context_clear_exit(commands)
			return {}, App_Failure{stage = .UI, ui = {operation = .Prepare, code = .Generation_Limit}}
		}
		commands.document_workflow.kill_label = assessment.selection_label
		if map_failure := command_context_activate_prompt_map(commands, .Exit_Choice); map_failure.stage != .None {
			_, _ = interaction.prompt_close(&commands.prompt_workflow.prompt)
			commands.prompt_workflow.mode = .None
			command_context_clear_exit(commands)
			return {}, map_failure
		}
		return Interaction_Result{changed = true}, {}
	}
	if commands.document_workflow.dir_abandonment_continuation == .None {
		return command_context_begin_dir_abandonment(
			commands,
			.Exit,
			.Exit,
		)
	}
	command_context_clear_exit(commands)
	return Interaction_Result{exit = true}, {}
}

@(private)
command_context_begin_terminal_exit :: proc(
	commands: ^Command_Context,
) -> (Interaction_Result, App_Failure) {
	choices := prompt_yes_no_choices()
	prompt_ok, prompt_failure := interaction.prompt_init(
		&commands.prompt_workflow.prompt,
		interaction.Prompt_Config {
			kind = .Fixed_Choice,
			choices = choices[:],
			allocator = commands.persistent_allocator,
		},
	)
	if !prompt_ok do return {}, App_Failure{stage = .Prompt, prompt_failure = prompt_failure}
	if !prompt_workflow_begin_projection(&commands.prompt_workflow, .Terminal_Exit_Choice) {
		_, _ = interaction.prompt_close(&commands.prompt_workflow.prompt)
		return {}, App_Failure{stage = .UI, ui = {operation = .Prepare, code = .Generation_Limit}}
	}
	if map_failure := command_context_activate_prompt_map(commands, .Terminal_Exit_Choice);
	   map_failure.stage != .None {
		_, _ = interaction.prompt_close(&commands.prompt_workflow.prompt)
		commands.prompt_workflow.mode = .None
		return {}, map_failure
	}
	return Interaction_Result{changed = true}, {}
}

@(private)
dispatch_terminal_exit_prompt :: proc(
	commands: ^Command_Context,
	input: interaction.Input,
) -> (Interaction_Result, App_Failure) {
	metadata, resolution, resolved, resolve_failure := command_context_resolve_prompt_input(commands, input)
	if !resolved do return {}, resolve_failure
	if resolution.kind != .Command do return {}, {}
	if command_metadata_is_cancel(metadata) {
		_, _ = interaction.prompt_cancel(&commands.prompt_workflow.prompt)
		command_context_deactivate_prompt_map(commands, .Cancelled)
		command_context_end_prompt(commands)
		command_context_clear_exit(commands)
		return Interaction_Result{changed = true}, {}
	}
	choice := command_metadata_prompt_choice(metadata)
	if choice < 1 || choice > 2 do return {}, {}
	_, choice_failure := interaction.prompt_choice_accept(&commands.prompt_workflow.prompt, choice)
	if choice_failure.code != .None do return {}, App_Failure{stage = .Prompt, prompt_failure = choice_failure}
	command_context_deactivate_prompt_map(commands, .Completed)
	command_context_end_prompt(commands)
	if choice == 2 {
		command_context_clear_exit(commands)
		return Interaction_Result{changed = true}, {}
	}
	commands.terminal_workflow.exit_confirmed = true
	return command_context_advance_exit(commands)
}

@(private)
command_context_save_for_exit :: proc(
	commands: ^Command_Context,
	buffer: ^editor.Buffer,
) -> (Interaction_Result, App_Failure) {
	if commands.session_owner == nil {
		status, status_ok, status_failure := document.document_status(commands.document_owner)
		if !status_ok {
			return {}, App_Failure{stage = .Document_Inspect, document = status_failure}
		}
		if status.persistence == .Unassociated {
			command_context_end_prompt(commands)
			return command_context_begin_save_path(commands, true)
		}
		prepared: document.Prepared_Save
		prepared_ok, prepare_failure := document.save_prepare(
			commands.document_owner,
			buffer,
			&prepared,
		)
		command_context_end_prompt(commands)
		if !prepared_ok {
			command_context_document_diagnostic(commands, "Save failed", prepare_failure)
			return Interaction_Result{changed = true}, {}
		}
		result, saved, save_failure := document.prepared_save_publish(&prepared)
		if !saved {
			command_context_document_diagnostic(commands, "Save failed", save_failure)
			return Interaction_Result{changed = true, save = result}, {}
		}
		command_context_set_channel_diagnostic(commands, .Save, "Saved")
		return Interaction_Result{exit = true, save = result}, {}
	}
	if commands.document_workflow.exit_index >= commands.document_workflow.exit_count {
		command_context_clear_exit(commands)
		return {}, App_Failure{stage = .Command_Dispatch}
	}
	entry := commands.document_workflow.exit_entries[commands.document_workflow.exit_index]
	assessment, assessed, assess_failure := editor_session.session_assess_buffer_close(
		commands.session_owner,
		entry,
	)
	if !assessed {
		command_context_end_prompt(commands)
		command_context_clear_exit(commands)
		return {}, App_Failure{stage = .Session_Access, editor_session = assess_failure}
	}
	if assessment.association == .Unassociated {
		command_context_end_prompt(commands)
		return command_context_begin_save_path(commands, true)
	}
	access, access_ok, access_failure := editor_session.session_entry_access(
		commands.session_owner,
		entry,
	)
	if !access_ok {
		command_context_end_prompt(commands)
		command_context_clear_exit(commands)
		return {}, App_Failure{stage = .Session_Access, editor_session = access_failure}
	}
	borrow, borrowed, borrow_failure := editor_session.entry_access_borrow(access)
	if !borrowed || !borrow.has_document {
		command_context_end_prompt(commands)
		command_context_clear_exit(commands)
		return {}, App_Failure{stage = .Session_Access, editor_session = borrow_failure}
	}
	prepared: document.Prepared_Save
	prepared_ok, prepare_failure := document.save_prepare(
		borrow.document,
		borrow.buffer,
		&prepared,
	)
	command_context_end_prompt(commands)
	if !prepared_ok {
		command_context_document_diagnostic(commands, "Save failed", prepare_failure)
		command_context_clear_exit(commands)
		return Interaction_Result{changed = true}, {}
	}
	result, saved, save_failure := document.prepared_save_publish(&prepared)
	if !saved {
		command_context_document_diagnostic(commands, "Save failed", save_failure)
		command_context_clear_exit(commands)
		return Interaction_Result{changed = true, save = result}, {}
	}
	commands.document_workflow.exit_index += 1
	advanced, advance_failure := command_context_advance_exit(commands)
	advanced.save = result
	return advanced, advance_failure
}

@(private)
command_context_begin_save_path :: proc(
	commands: ^Command_Context,
	exit_after_save: bool,
	write_file := false,
) -> (Interaction_Result, App_Failure) {
	prompt_ok, prompt_failure := interaction.prompt_init(
		&commands.prompt_workflow.prompt,
		interaction.Prompt_Config {
			kind = .Text_Entry,
			text_bytes_limit = document.MAX_PATH_BYTES,
			allocator = commands.persistent_allocator,
		},
	)
	if !prompt_ok {
		return {}, App_Failure{stage = .Prompt, prompt_failure = prompt_failure}
	}
	mode := Prompt_Mode.Exit_Save_Path if exit_after_save else .Save_Path
	if write_file do mode = .Write_File_Path
	if !prompt_workflow_begin_projection(&commands.prompt_workflow, mode) {
		_, _ = interaction.prompt_close(&commands.prompt_workflow.prompt)
		return {}, App_Failure{stage = .UI, ui = {operation = .Prepare, code = .Generation_Limit}}
	}
	if map_failure := command_context_activate_prompt_map(commands, commands.prompt_workflow.mode); map_failure.stage != .None {
		_, _ = interaction.prompt_close(&commands.prompt_workflow.prompt)
		commands.prompt_workflow.mode = .None
		return {}, map_failure
	}
	return Interaction_Result{changed = true}, {}
}

@(private)
command_context_begin_insert_file_path :: proc(
	commands: ^Command_Context,
	command_handle: interaction.Command_Handle,
) -> (Interaction_Result, App_Failure) {
	prompt_ok, prompt_failure := interaction.prompt_init(
		&commands.prompt_workflow.prompt,
		interaction.Prompt_Config {
			kind = .Text_Entry,
			text_bytes_limit = document.MAX_PATH_BYTES,
			allocator = commands.persistent_allocator,
		},
	)
	if !prompt_ok do return {}, App_Failure{stage = .Prompt, prompt_failure = prompt_failure}
	if !prompt_workflow_begin_projection(&commands.prompt_workflow, .Insert_File_Path) {
		_, _ = interaction.prompt_close(&commands.prompt_workflow.prompt)
		return {}, App_Failure{stage = .UI, ui = {operation = .Prepare, code = .Generation_Limit}}
	}
	if map_failure := command_context_activate_prompt_map(commands, .Insert_File_Path); map_failure.stage != .None {
		_, _ = interaction.prompt_close(&commands.prompt_workflow.prompt)
		commands.prompt_workflow.mode = .None
		return {}, map_failure
	}
	commands.document_workflow.buffer_command = command_handle
	return Interaction_Result{changed = true}, {}
}

@(private)
dispatch_insert_file_path_prompt :: proc(
	commands: ^Command_Context,
	input: interaction.Input,
) -> (Interaction_Result, App_Failure) {
	metadata, resolution, resolved, resolve_failure := command_context_resolve_prompt_input(commands, input)
	if !resolved do return {}, resolve_failure
	if resolution.kind != .Command do return {}, {}
	if command_metadata_is_cancel(metadata) {
		_, cancel_failure := interaction.prompt_cancel(&commands.prompt_workflow.prompt)
		if cancel_failure.code != .None do return {}, App_Failure{stage = .Prompt, prompt_failure = cancel_failure}
		command_context_deactivate_prompt_map(commands, .Cancelled)
		command_context_end_prompt(commands)
		return Interaction_Result{changed = true}, {}
	}
	if command_metadata_is_contextual(metadata, .Prompt_Delete_Previous) {
		transition, prompt_failure := interaction.prompt_text_delete_previous(&commands.prompt_workflow.prompt)
		if prompt_failure.code != .None do return {}, App_Failure{stage = .Prompt, prompt_failure = prompt_failure}
		commands.prompt_workflow.rejected = false
		return Interaction_Result{changed = transition == .Changed}, {}
	}
	if command_metadata_is_contextual(metadata, .Prompt_Accept) {
		_, accept_failure := interaction.prompt_text_accept(&commands.prompt_workflow.prompt)
		if accept_failure.code != .None {
			commands.prompt_workflow.rejected = true
			return Interaction_Result{changed = true}, {}
		}
		view, viewed, view_failure := interaction.prompt_view(&commands.prompt_workflow.prompt)
		if !viewed do return {}, App_Failure{stage = .Prompt, prompt_failure = view_failure}
		path_storage: [document.MAX_PATH_BYTES]u8
		path, path_ok := command_context_expand_home_path(commands, view.text, path_storage[:])
		if !path_ok {
			command_context_end_prompt(commands)
			command_context_set_diagnostic(commands, "Home-relative path exceeds the path limit")
			return Interaction_Result{changed = true}, {}
		}
		contents, read_error := os.read_entire_file(path, commands.temporary_allocator)
		if read_error != nil {
			command_context_end_prompt(commands)
			command_context_set_diagnostic(commands, "File could not be read")
			return Interaction_Result{changed = true}, {}
		}
		defer delete(contents, commands.temporary_allocator)
		if len(contents) == 0 || !utf8.valid_string(string(contents)) {
			command_context_end_prompt(commands)
			command_context_set_diagnostic(commands, "File is empty or not valid UTF-8")
			return Interaction_Result{changed = true}, {}
		}
		document_workflow_clear_deferred_text(&commands.document_workflow)
		deferred_text, allocation_error := make(
			[]u8,
			len(contents),
			commands.persistent_allocator,
		)
		if allocation_error != nil {
			command_context_end_prompt(commands)
			return {}, App_Failure{stage = .Component_Access}
		}
		copy(deferred_text, contents)
		commands.document_workflow.deferred_text = deferred_text
		commands.document_workflow.deferred_text_allocator = commands.persistent_allocator
		commands.document_workflow.deferred_command = commands.document_workflow.buffer_command
		deferred_command := commands.document_workflow.buffer_command
		command_context_end_prompt(commands)
		return Interaction_Result{changed = true, deferred_command = deferred_command}, {}
	}
	if command_metadata_is_contextual(metadata, .Prompt_Insert_Text) {
		transition, prompt_failure := interaction.prompt_text_append(&commands.prompt_workflow.prompt, resolution.text)
		if prompt_failure.code != .None {
			commands.prompt_workflow.rejected = true
			return Interaction_Result{changed = true}, {}
		}
		commands.prompt_workflow.rejected = false
		return Interaction_Result{changed = transition == .Changed}, {}
	}
	return {}, {}
}

@(private)
command_context_begin_navigation_target :: proc(
	commands: ^Command_Context,
	command_handle: interaction.Command_Handle,
) -> (Interaction_Result, App_Failure) {
	prompt_ok, prompt_failure := interaction.prompt_init(
		&commands.prompt_workflow.prompt,
		interaction.Prompt_Config {
			kind = .Text_Entry,
			text_bytes_limit = 20,
			allocator = commands.persistent_allocator,
		},
	)
	if !prompt_ok do return {}, App_Failure{stage = .Prompt, prompt_failure = prompt_failure}
	if !prompt_workflow_begin_projection(&commands.prompt_workflow, .Navigation_Target) {
		_, _ = interaction.prompt_close(&commands.prompt_workflow.prompt)
		return {}, App_Failure{stage = .UI, ui = {operation = .Prepare, code = .Generation_Limit}}
	}
	if map_failure := command_context_activate_prompt_map(commands, .Navigation_Target); map_failure.stage != .None {
		_, _ = interaction.prompt_close(&commands.prompt_workflow.prompt)
		commands.prompt_workflow.mode = .None
		return {}, map_failure
	}
	commands.document_workflow.buffer_command = command_handle
	return Interaction_Result{changed = true}, {}
}

@(private)
dispatch_navigation_target_prompt :: proc(
	commands: ^Command_Context,
	input: interaction.Input,
) -> (Interaction_Result, App_Failure) {
	metadata, resolution, resolved, resolve_failure := command_context_resolve_prompt_input(commands, input)
	if !resolved do return {}, resolve_failure
	if resolution.kind != .Command do return {}, {}
	if command_metadata_is_cancel(metadata) {
		_, cancel_failure := interaction.prompt_cancel(&commands.prompt_workflow.prompt)
		if cancel_failure.code != .None do return {}, App_Failure{stage = .Prompt, prompt_failure = cancel_failure}
		command_context_deactivate_prompt_map(commands, .Cancelled)
		command_context_end_prompt(commands)
		return Interaction_Result{changed = true}, {}
	}
	if command_metadata_is_contextual(metadata, .Prompt_Delete_Previous) {
		transition, prompt_failure := interaction.prompt_text_delete_previous(&commands.prompt_workflow.prompt)
		if prompt_failure.code != .None do return {}, App_Failure{stage = .Prompt, prompt_failure = prompt_failure}
		commands.prompt_workflow.rejected = false
		return Interaction_Result{changed = transition == .Changed}, {}
	}
	if command_metadata_is_contextual(metadata, .Prompt_Accept) {
		_, accept_failure := interaction.prompt_text_accept(&commands.prompt_workflow.prompt)
		if accept_failure.code != .None {
			commands.prompt_workflow.rejected = true
			return Interaction_Result{changed = true}, {}
		}
		view, viewed, view_failure := interaction.prompt_view(&commands.prompt_workflow.prompt)
		if !viewed do return {}, App_Failure{stage = .Prompt, prompt_failure = view_failure}
		value, parsed := strconv.parse_i64_of_base(view.text, 10)
		if !parsed || value < 1 {
			commands.prompt_workflow.rejected = true
			return Interaction_Result{changed = true}, {}
		}
		deferred_command := commands.document_workflow.buffer_command
		commands.document_workflow.deferred_argument = value
		commands.document_workflow.deferred_command = deferred_command
		command_context_end_prompt(commands)
		return Interaction_Result{changed = true, deferred_command = deferred_command}, {}
	}
	if command_metadata_is_contextual(metadata, .Prompt_Insert_Text) {
		transition, prompt_failure := interaction.prompt_text_append(&commands.prompt_workflow.prompt, resolution.text)
		if prompt_failure.code != .None {
			commands.prompt_workflow.rejected = true
			return Interaction_Result{changed = true}, {}
		}
		commands.prompt_workflow.rejected = false
		return Interaction_Result{changed = transition == .Changed}, {}
	}
	return {}, {}
}

@(private)
command_context_begin_buffer_prompt :: proc(
	commands: ^Command_Context,
	mode: Prompt_Mode,
	command_handle: interaction.Command_Handle,
) -> (Interaction_Result, App_Failure) {
	if mode != .Find_File && mode != .Find_File_Other_Pane &&
	   mode != .Switch_To_Buffer && mode != .Kill_Buffer {
		return {}, App_Failure{stage = .Prompt}
	}
	if mode == .Find_File || mode == .Find_File_Other_Pane {
		return filesystem_path_navigation_begin(commands, mode, command_handle)
	}
	limit := document.MAX_PATH_BYTES
	if mode == .Switch_To_Buffer || mode == .Kill_Buffer {
		limit = editor_session.MAX_NAME_BYTES
		if mode == .Kill_Buffer {
			limit = editor_session.MAX_CLOSURE_LABEL_BYTES
		}
	}
	prompt_ok, prompt_failure := interaction.prompt_init(
		&commands.prompt_workflow.prompt,
		interaction.Prompt_Config {
			kind = .Text_Entry,
			text_bytes_limit = limit,
			allocator = commands.persistent_allocator,
		},
	)
	if !prompt_ok {
		return {}, App_Failure{stage = .Prompt, prompt_failure = prompt_failure}
	}
	if mode == .Kill_Buffer {
		label, label_ok, label_failure := editor_session.session_entry_label(
			commands.session_owner,
			commands.current_entry,
		)
		if !label_ok {
			_, _ = interaction.prompt_close(&commands.prompt_workflow.prompt)
			return {}, App_Failure{stage = .Session_Access, editor_session = label_failure}
		}
		_, append_failure := interaction.prompt_text_append(
			&commands.prompt_workflow.prompt,
			editor_session.closure_label_text(&label),
		)
		if append_failure.code != .None {
			_, _ = interaction.prompt_close(&commands.prompt_workflow.prompt)
			return {}, App_Failure{stage = .Prompt, prompt_failure = append_failure}
		}
	}
	if !prompt_workflow_begin_projection(&commands.prompt_workflow, mode) {
		_, _ = interaction.prompt_close(&commands.prompt_workflow.prompt)
		return {}, App_Failure{stage = .UI, ui = {operation = .Prepare, code = .Generation_Limit}}
	}
	commands.document_workflow.buffer_command = command_handle
	if map_failure := command_context_activate_prompt_map(commands, mode); map_failure.stage != .None {
		_, _ = interaction.prompt_close(&commands.prompt_workflow.prompt)
		commands.prompt_workflow.mode = .None
		commands.document_workflow.buffer_command = {}
		return {}, map_failure
	}
	return Interaction_Result{changed = true}, {}
}

@(private)
command_context_ensure_text_fallback :: proc(
	commands: ^Command_Context,
	closure: editor_session.Closure_Result,
) -> (ok: bool, failure: App_Failure) {
	if !closure.last_buffer {
		return true, {}
	}
	target := startup_visible_target()
	_, _, presented, present_failure := editor_session.session_present_ui(
		commands.session_owner,
		commands.session_handle,
		target.ui,
	)
	if !presented {
		return false, App_Failure{stage = .Session_Access, editor_session = present_failure}
	}
	return true, {}
}
