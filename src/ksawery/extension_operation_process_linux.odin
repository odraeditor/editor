// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

#+build linux
package ksawery

import "core:os"

@(private)
EXTENSION_OPERATION_PROCESS_ENVIRONMENT :: [4]string {
	"PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
	"LANG=C",
	"LC_ALL=C",
	"GIT_TERMINAL_PROMPT=0",
}

/* repository_process_start_extension_operation admits and owns one declared child. */
repository_process_start_extension_operation :: proc(
	submission: Extension_Operation_Submission,
	plan: Extension_Operation_Plan,
	declaration: Contribution_Declaration,
	current_contributor: Contributor_Handle,
	current_repository: Repository_Context,
	current_repository_generation: Repository_Generation,
	now_ns: i64,
	allocator := context.allocator,
) -> (Repository_Process, bool, Extension_Operation_Failure) {
	_, admission_failure := extension_operation_submission_validate(
		submission,
		plan,
		declaration,
		current_contributor,
		current_repository,
		current_repository_generation,
	)
	if admission_failure.code != .None do return {}, false, admission_failure
	failure := Extension_Operation_Failure{plan = plan.plan}
	if allocator.procedure == nil || now_ns < 0 ||
	   plan.process_limits.deadline_nanoseconds > max(i64) - now_ns {
		failure.code = .Invalid_Plan
		return {}, false, failure
	}

	state, allocation_error := new(Repository_Process_Data, allocator)
	if allocation_error != nil {
		failure.code = .Allocation
		return {}, false, failure
	}
	state.allocator = allocator
	state.extension_operation_submission = submission
	state.extension_operation = plan
	state.request = {
		kind = .External_Operation,
		repository = submission.repository,
		limits = DEFAULT_PROCESS_LIMITS,
	}
	state.request.limits.stdout_bytes = plan.process_limits.output_bytes
	state.request.limits.diagnostic_bytes = plan.process_limits.diagnostic_bytes
	state.request.limits.timeout_nanoseconds = plan.process_limits.deadline_nanoseconds
	state.request.limits.cancellation_grace_ns = plan.process_limits.cancellation_grace_ns
	state.output_limit = plan.process_limits.output_bytes

	state.extension_operation_arguments, allocation_error = make(
		[dynamic]Extension_Operation_Argument,
		len(plan.arguments),
		len(plan.arguments),
		allocator,
	)
	if allocation_error != nil {
		repository_process_data_destroy(state)
		failure.code = .Allocation
		return {}, false, failure
	}
	copy(state.extension_operation_arguments[:], plan.arguments)
	state.extension_operation.arguments = state.extension_operation_arguments[:]

	state.output, allocation_error = make(
		[dynamic]u8,
		0,
		int(min(state.output_limit, 64 * KIBIBYTE)),
		allocator,
	)
	if allocation_error != nil {
		repository_process_data_destroy(state)
		failure.code = .Allocation
		return {}, false, failure
	}
	state.diagnostic, allocation_error = make(
		[dynamic]u8,
		0,
		int(min(plan.process_limits.diagnostic_bytes, 16 * KIBIBYTE)),
		allocator,
	)
	if allocation_error != nil {
		repository_process_data_destroy(state)
		failure.code = .Allocation
		return {}, false, failure
	}

	executable, resolved := extension_operation_process_executable(&state.extension_operation)
	if !resolved {
		repository_process_data_destroy(state)
		failure.code = .Invalid_Executable
		return {}, false, failure
	}
	state.extension_operation_command[0] = executable
	for &argument, index in state.extension_operation_arguments {
		state.extension_operation_command[index + 1] = extension_operation_process_argument(&argument)
	}
	state.command_count = u8(len(state.extension_operation_arguments) + 1)
	repository := state.request.repository
	environment := EXTENSION_OPERATION_PROCESS_ENVIRONMENT
	state.child, state.failure = local_child_start_with_environment(
		state.extension_operation_command[:int(state.command_count)],
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
	state.deadline_ns = now_ns + plan.process_limits.deadline_nanoseconds
	state.state = .Running
	return Repository_Process{state = state}, true, {}
}

/* repository_process_extension_operation_snapshot borrows bounded owned evidence. */
repository_process_extension_operation_snapshot :: proc(
	process: ^Repository_Process,
) -> (
	Extension_Operation_Submission,
	Extension_Operation_Plan,
	Repository_Process_Lifecycle_View,
	[]u8,
	[]u8,
	bool,
) {
	state := repository_process_data(process)
	if state == nil || state.request.kind != .External_Operation do return {}, {}, {}, nil, nil, false
	view, viewed := repository_process_lifecycle_view(process)
	if !viewed do return {}, {}, {}, nil, nil, false
	diagnostic := state.diagnostic[:]
	if state.extension_operation.diagnostic_policy == .Suppressed do diagnostic = nil
	return state.extension_operation_submission,
		state.extension_operation,
		view,
		state.output[:],
		diagnostic,
		true
}

@(private)
extension_operation_process_executable :: proc(
	plan: ^Extension_Operation_Plan,
) -> (string, bool) {
	if plan == nil do return "", false
	switch plan.executable.kind {
	case .Built_In_Git:
		return "git", true
	case .Configured_Absolute_Path:
		if plan.executable.path_length == 0 ||
		   int(plan.executable.path_length) > len(plan.executable.path) {
			return "", false
		}
		return string(plan.executable.path[:plan.executable.path_length]), true
	case .Invalid:
		return "", false
	}
	return "", false
}

@(private)
extension_operation_process_argument :: proc(argument: ^Extension_Operation_Argument) -> string {
	if argument == nil || argument.length == 0 || int(argument.length) > len(argument.bytes) {
		return ""
	}
	return string(argument.bytes[:argument.length])
}
