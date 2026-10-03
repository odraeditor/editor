// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../command"
import "../editor_session"
import "../interactive_session"
import "../interaction"
import "../terminal_emulator"
import "../terminal_session"
import "core:os"

/* MAX_SHELL_COMMAND_BYTES bounds one retained shell or compilation command. */
MAX_SHELL_COMMAND_BYTES :: 4_096

@(private)
command_context_begin_shell_command :: proc(
	commands: ^Command_Context,
	route: command.Native_Route,
) -> (Interaction_Result, App_Failure) {
	mode := Prompt_Mode.Shell_Command
	if route == .Async_Shell_Command {
		mode = .Async_Shell_Command
	} else if route == .Compile {
		mode = .Compile_Command
	}
	prompt_ok, prompt_failure := interaction.prompt_init(
		&commands.prompt_workflow.prompt,
		{
			kind = .Text_Entry,
			text_bytes_limit = MAX_SHELL_COMMAND_BYTES,
			allow_empty = false,
			allocator = commands.persistent_allocator,
		},
	)
	if !prompt_ok do return {}, App_Failure{stage = .Prompt, prompt_failure = prompt_failure}
	if mode == .Compile_Command {
		initial := "make"
		workflow := commands.terminal_workflow
		if workflow != nil && workflow.last_compile_length > 0 {
			initial = string(workflow.last_compile_command[:workflow.last_compile_length])
		}
		_, append_failure := interaction.prompt_text_append(&commands.prompt_workflow.prompt, initial)
		if append_failure.code != .None {
			_, _ = interaction.prompt_close(&commands.prompt_workflow.prompt)
			return {}, App_Failure{stage = .Prompt, prompt_failure = append_failure}
		}
	}
	if !prompt_workflow_begin_projection(&commands.prompt_workflow, mode) {
		_, _ = interaction.prompt_close(&commands.prompt_workflow.prompt)
		return {}, App_Failure{stage = .UI, ui = {operation = .Prepare, code = .Generation_Limit}}
	}
	if map_failure := command_context_activate_prompt_map(commands, mode); map_failure.stage != .None {
		command_context_end_prompt(commands)
		return {}, map_failure
	}
	return Interaction_Result{changed = true}, {}
}

@(private)
dispatch_shell_command_prompt :: proc(
	commands: ^Command_Context,
	input: interaction.Input,
) -> (Interaction_Result, App_Failure) {
	metadata, resolution, resolved, resolve_failure := command_context_resolve_prompt_input(commands, input)
	if !resolved do return {}, resolve_failure
	if resolution.kind != .Command do return {}, {}
	if command_metadata_is_cancel(metadata) {
		_, _ = interaction.prompt_cancel(&commands.prompt_workflow.prompt)
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
		transition, prompt_failure := interaction.prompt_text_append(
			&commands.prompt_workflow.prompt,
			resolution.text,
		)
		if prompt_failure.code != .None {
			commands.prompt_workflow.rejected = true
			return Interaction_Result{changed = true}, {}
		}
		commands.prompt_workflow.rejected = false
		return Interaction_Result{changed = transition == .Changed}, {}
	}
	if !command_metadata_is_contextual(metadata, .Prompt_Accept) do return {}, {}
	_, accept_failure := interaction.prompt_text_accept(&commands.prompt_workflow.prompt)
	if accept_failure.code != .None {
		commands.prompt_workflow.rejected = true
		return Interaction_Result{changed = true}, {}
	}
	view, viewed, view_failure := interaction.prompt_view(&commands.prompt_workflow.prompt)
	if !viewed do return {}, App_Failure{stage = .Prompt, prompt_failure = view_failure}
	command_text: [MAX_SHELL_COMMAND_BYTES]u8
	command_length := copy(command_text[:], transmute([]u8)view.text)
	mode := commands.prompt_workflow.mode
	command_context_end_prompt(commands)
	kind := Terminal_One_Shot_Kind.Shell
	if mode == .Async_Shell_Command {
		kind = .Async_Shell
	} else if mode == .Compile_Command {
		kind = .Compilation
	}
	return command_context_run_shell_command(
		commands,
		string(command_text[:command_length]),
		kind,
	)
}

@(private)
command_context_recompile :: proc(commands: ^Command_Context) -> (Interaction_Result, App_Failure) {
	workflow := commands.terminal_workflow
	if workflow == nil || workflow.last_compile_length == 0 {
		command_context_set_diagnostic(commands, "No compilation command has been run")
		return Interaction_Result{changed = true}, {}
	}
	command_text: [MAX_SHELL_COMMAND_BYTES]u8
	command_length := copy(
		command_text[:],
		workflow.last_compile_command[:workflow.last_compile_length],
	)
	return command_context_run_shell_command(
		commands,
		string(command_text[:command_length]),
		.Compilation,
	)
}

@(private)
command_context_run_shell_command :: proc(
	commands: ^Command_Context,
	command_text: string,
	kind: Terminal_One_Shot_Kind,
	working_directory_override: string = "",
) -> (Interaction_Result, App_Failure) {
	if commands == nil || commands.terminal_workflow == nil ||
	   len(command_text) == 0 || len(command_text) > MAX_SHELL_COMMAND_BYTES || kind == .None {
		return {}, App_Failure{stage = .Component_Access}
	}
	working, resolution, context_failure := terminal_context_resolve(
		commands,
		{
			purpose = .Default,
			global_shell = commands.terminal_global_shell,
			workspace_shell = commands.terminal_workspace_shell,
		},
	)
	if resolution != .Resolved {
		terminal_context_failure_diagnostic(commands, context_failure)
		return Interaction_Result{changed = true}, {}
	}
	name_storage: [interactive_session.MAX_NAME_BYTES]u8
	name, named := terminal_workflow_next_name(commands.terminal_workflow, name_storage[:])
	if !named do return {}, App_Failure{stage = .Component_Access}
	directory := terminal_context_directory(&working)
	if len(working_directory_override) > 0 {
		if !os.is_absolute_path(working_directory_override) ||
		   !os.is_dir(working_directory_override) {
			return {}, App_Failure{stage = .Component_Access}
		}
		directory = working_directory_override
	}
	shell := terminal_context_shell(&working)
	arguments := [2]string{"-lc", command_text}
	options := terminal_emulator.DEFAULT_OPTIONS
	presentation := Terminal_Presentation.Replace_Active
	owner_label := "shell command"
	if kind == .Async_Shell {
		presentation = .Hidden
		owner_label = "asynchronous shell command"
	} else if kind == .Compilation {
		owner_label = "compilation"
	}
	opened, open_ok, open_failure := terminal_workflow_open(
		commands.terminal_workflow,
		commands.session_owner,
		commands.session_handle,
		&commands.layout_registry,
		{
			name = name,
			working_context = directory,
			presentation = presentation,
			configuration = commands.entry_configuration,
			scope = terminal_workflow_scope(&working),
			default_session = false,
			one_shot_kind = kind,
			terminal = {
				process = {
					name = name,
					owner_kind = .Task,
					owner_label = owner_label,
					working_directory = directory,
					limits = terminal_interactive_limits(),
				},
				start = {
					executable = shell,
					arguments = arguments[:],
					working_directory = directory,
					columns = options.columns,
					rows = options.rows,
				},
				emulator = options,
				limits = terminal_session.DEFAULT_LIMITS,
			},
		},
	)
	if !open_ok do return {}, app_terminal_workflow_failure(open_failure)
	_ = terminal_workflow_commit_name(commands.terminal_workflow)
	if kind == .Compilation {
		workflow := commands.terminal_workflow
		workflow.last_compile_command = {}
		workflow.last_compile_length = u16(copy(workflow.last_compile_command[:], transmute([]u8)command_text))
	}
	if presentation != .Hidden {
		_, activated, activation_failure := editor_session.session_activate(
			commands.session_owner,
			opened.entry,
		)
		if !activated do return {}, App_Failure{stage = .Session_Access, editor_session = activation_failure}
		commands.layout_entry = opened.entry
		commands.current_entry = opened.entry
		_ = terminal_workflow_note_focus(commands.terminal_workflow, opened.terminal)
	}
	message := "Shell command started"
	if kind == .Async_Shell {
		message = "Async shell command started; use terminal-list to view output"
	} else if kind == .Compilation {
		message = "Compilation started"
	}
	command_context_set_diagnostic(commands, message)
	return Interaction_Result{changed = true}, {}
}
