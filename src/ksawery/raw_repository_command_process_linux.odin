// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

#+build linux
package ksawery

import "core:os"

@(private)
RAW_REPOSITORY_COMMAND_PROCESS_ENVIRONMENT :: [4]string {
	"PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
	"LANG=C",
	"LC_ALL=C",
	"GIT_TERMINAL_PROMPT=0",
}

/* repository_process_start_raw_repository_command owns one confirmed built-in raw child. */
repository_process_start_raw_repository_command :: proc(
	request: Raw_Repository_Command_Request,
	current_repository: Repository_Context,
	current_repository_generation: Repository_Generation,
	now_ns: i64,
	allocator := context.allocator,
) -> (Repository_Process, bool, Raw_Repository_Command_Failure) {
	current, current_failure := raw_repository_command_request_is_current(
		request,
		current_repository,
		current_repository_generation,
	)
	if !current do return {}, false, current_failure
	failure := Raw_Repository_Command_Failure{command = request.intent.command}
	if allocator.procedure == nil {
		failure.code = .Allocation
		return {}, false, failure
	}
	if now_ns < 0 || request.intent.limits.deadline_nanoseconds > max(i64) - now_ns {
		failure.code = .Deadline_Limit
		return {}, false, failure
	}

	state, allocation_error := new(Repository_Process_Data, allocator)
	if allocation_error != nil {
		failure.code = .Allocation
		return {}, false, failure
	}
	state.allocator = allocator
	state.raw_repository_command = request
	state.request = {
		kind = .Raw_Command,
		repository = request.intent.repository,
		limits = DEFAULT_PROCESS_LIMITS,
	}
	state.request.limits.stdout_bytes = request.intent.limits.output_bytes
	state.request.limits.diagnostic_bytes = request.intent.limits.diagnostic_bytes
	state.request.limits.timeout_nanoseconds = request.intent.limits.deadline_nanoseconds
	state.request.limits.cancellation_grace_ns = request.intent.limits.cancellation_grace_ns
	state.output_limit = request.intent.limits.output_bytes
	state.output, allocation_error = make(
		[dynamic]u8,
		0,
		int(min(state.output_limit, 64 * KIBIBYTE)),
		allocator,
	)
	if allocation_error == nil {
		state.diagnostic, allocation_error = make(
			[dynamic]u8,
			0,
			int(min(request.intent.limits.diagnostic_bytes, 16 * KIBIBYTE)),
			allocator,
		)
	}
	if allocation_error != nil {
		repository_process_data_destroy(state)
		failure.code = .Allocation
		return {}, false, failure
	}

	command: []string
	switch request.intent.input.mode {
	case .Git:
		argument_count, parsed := raw_repository_command_parse_git_arguments(state)
		if !parsed {
			repository_process_data_destroy(state)
			failure.code = .Invalid_Input
			return {}, false, failure
		}
		command = state.raw_command_arguments[:argument_count]
	case .Shell:
		program := raw_repository_command_input_text(&state.raw_repository_command.intent.input)
		if len(program) == 0 {
			repository_process_data_destroy(state)
			failure.code = .Invalid_Input
			return {}, false, failure
		}
		state.command = {"/bin/sh", "-c", program, "", "", "", "", "", "", ""}
		state.command_count = 3
		command = state.command[:state.command_count]
	case .Invalid:
		repository_process_data_destroy(state)
		failure.code = .Invalid_Input
		return {}, false, failure
	}
	repository := state.request.repository
	environment := RAW_REPOSITORY_COMMAND_PROCESS_ENVIRONMENT
	state.child, state.failure = local_child_start_with_environment(
		command,
		repository_context_string(&repository),
		environment[:],
	)
	if state.failure != .None {
		child_failure := state.failure
		repository_process_data_destroy(state)
		failure.code = .Process_Start
		if child_failure == .Executable_Unavailable do failure.code = .Executable_Unavailable
		return {}, false, failure
	}
	if state.child.stdin != nil {
		if os.close(state.child.stdin) != nil {
			repository_process_data_destroy(state)
			failure.code = .Process_Start
			return {}, false, failure
		}
		state.child.stdin = nil
	}
	state.stdin_closed = true
	state.deadline_ns = now_ns + request.intent.limits.deadline_nanoseconds
	state.state = .Running
	return Repository_Process{state = state}, true, {}
}

/* repository_process_raw_repository_command_snapshot borrows bounded private execution evidence. */
repository_process_raw_repository_command_snapshot :: proc(
	process: ^Repository_Process,
) -> (
	command: Raw_Repository_Command_ID,
	mode: Raw_Repository_Command_Mode,
	lifecycle: Repository_Process_Lifecycle_View,
	output: []u8,
	diagnostic: []u8,
	stdin_closed: bool,
	ok: bool,
) {
	state := repository_process_data(process)
	if state == nil || state.request.kind != .Raw_Command ||
	   !raw_repository_command_request_is_valid(state.raw_repository_command) {
		return
	}
	lifecycle, ok = repository_process_lifecycle_view(process)
	if !ok do return
	command = state.raw_repository_command.intent.command
	mode = state.raw_repository_command.intent.input.mode
	output = state.output[:]
	diagnostic = state.diagnostic[:]
	stdin_closed = state.stdin_closed
	return
}

@(private)
/* Parses one quoted argument line without admitting a shell in Git mode. */
raw_repository_command_parse_git_arguments :: proc(
	state: ^Repository_Process_Data,
) -> (argument_count: int, ok: bool) {
	if state == nil || !raw_repository_command_request_is_valid(state.raw_repository_command) ||
	   state.raw_repository_command.intent.input.mode != .Git {
		return 0, false
	}
	input := raw_repository_command_input_text(&state.raw_repository_command.intent.input)
	if len(input) == 0 do return 0, false
	state.raw_command_arguments = {}
	state.raw_command_argument_storage = {}
	state.raw_command_arguments[0] = "git"
	argument_count = 1
	write := 0
	token_start := 0
	token_started := false
	quote: u8
	escaped := false
	for byte in transmute([]u8)input {
		if escaped {
			if write >= len(state.raw_command_argument_storage) do return 0, false
			state.raw_command_argument_storage[write] = byte
			write += 1
			escaped = false
			token_started = true
			continue
		}
		if quote == '\'' {
			if byte == '\'' {
				quote = 0
			} else {
				if write >= len(state.raw_command_argument_storage) do return 0, false
				state.raw_command_argument_storage[write] = byte
				write += 1
			}
			token_started = true
			continue
		}
		if quote == '"' {
			if byte == '"' {
				quote = 0
			} else if byte == '\\' {
				escaped = true
			} else {
				if write >= len(state.raw_command_argument_storage) do return 0, false
				state.raw_command_argument_storage[write] = byte
				write += 1
			}
			token_started = true
			continue
		}
		switch byte {
		case ' ', '\t':
			if token_started {
				if !raw_repository_command_finish_git_argument(
					state, token_start, write, &argument_count,
				) {
					return 0, false
				}
				token_start = write
				token_started = false
			}
		case '\'', '"':
			quote = byte
			token_started = true
		case '\\':
			escaped = true
			token_started = true
		case:
			if write >= len(state.raw_command_argument_storage) do return 0, false
			state.raw_command_argument_storage[write] = byte
			write += 1
			token_started = true
		}
	}
	if escaped || quote != 0 do return 0, false
	if token_started && !raw_repository_command_finish_git_argument(
		state, token_start, write, &argument_count,
	) {
		return 0, false
	}
	if argument_count <= 1 do return 0, false
	return argument_count, true
}

@(private = "file")
raw_repository_command_finish_git_argument :: proc(
	state: ^Repository_Process_Data,
	start, end: int,
	argument_count: ^int,
) -> bool {
	if state == nil || argument_count == nil || start < 0 || end < start ||
	   end > len(state.raw_command_argument_storage) ||
	   argument_count^ >= len(state.raw_command_arguments) {
		return false
	}
	state.raw_command_arguments[argument_count^] =
		string(state.raw_command_argument_storage[start:end])
	argument_count^ += 1
	return true
}
