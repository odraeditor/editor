// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

#+build linux
package ksawery_extension_focused

import ksawery "../../src/ksawery"
import "core:os"
import "core:strings"
import "core:testing"
import "core:time"

/* raw_repository_command_process_start starts and associates one exact raw request. */
raw_repository_command_process_start :: proc(
	mode: ksawery.Raw_Repository_Command_Mode,
	text: string,
	repository_path := "/tmp",
	limits := ksawery.DEFAULT_RAW_REPOSITORY_COMMAND_LIMITS,
) -> (ksawery.Repository_Process, ksawery.Raw_Repository_Command_Request, bool) {
	repository: ksawery.Repository_Context
	if !ksawery.repository_context_assign(&repository, repository_path) do return {}, {}, false
	intent := raw_repository_command_test_intent(mode)
	intent.repository = repository
	assigned, _ := ksawery.raw_repository_command_input_assign(&intent.input, mode, text)
	if !assigned do return {}, {}, false
	intent.limits = limits
	request := raw_repository_command_test_request(intent)
	process, started, _ := ksawery.repository_process_start_raw_repository_command(
		request,
		repository,
		intent.repository_generation,
		1,
	)
	if !started do return {}, request, false
	associated, _ := ksawery.repository_process_associate(
		&process,
		{
			authority = {
				operation = request.operation,
				repository = repository,
				observation_generation = intent.observation_generation,
				kind = .Raw_Command,
			},
			generation = 1,
		},
		1,
	)
	if !associated {
		ksawery.repository_process_close(&process)
		return {}, request, false
	}
	return process, request, true
}

/* Verifies a nonzero raw child remains a known process failure. */
@(test)
raw_repository_command_retains_nonzero_exit :: proc(t: ^testing.T) {
	process, _, started := raw_repository_command_process_start(.Shell, "exit 7")
	testing.expect(t, started)
	if !started do return
	defer ksawery.repository_process_close(&process)
	poll := operation_process_wait(&process)
	testing.expect_value(t, poll.state, ksawery.Repository_Process_State.Failed)
	testing.expect_value(t, poll.exit_status, i32(7))
	testing.expect_value(t, poll.failure, ksawery.Failure_Code.Process_Failed)
	_, _, lifecycle, _, _, _, available :=
		ksawery.repository_process_raw_repository_command_snapshot(&process)
	testing.expect(t, available)
	testing.expect(t, lifecycle.child.exit_status_available)
	testing.expect_value(t, lifecycle.child.exit_status, i32(7))
}

/* Verifies raw children terminate within the core deadline and grace envelope. */
@(test)
raw_repository_command_enforces_deadline_and_grace :: proc(t: ^testing.T) {
	limits := ksawery.DEFAULT_RAW_REPOSITORY_COMMAND_LIMITS
	limits.deadline_nanoseconds = ksawery.MIN_PROCESS_TIMEOUT_NANOSECONDS
	limits.cancellation_grace_ns = i64(10 * time.Millisecond)
	process, _, started := raw_repository_command_process_start(
		.Shell, "sleep 2", "/tmp", limits,
	)
	testing.expect(t, started)
	if !started do return
	defer ksawery.repository_process_close(&process)
	poll := operation_process_wait(&process)
	testing.expect_value(t, poll.state, ksawery.Repository_Process_State.Failed)
	testing.expect_value(t, poll.failure, ksawery.Failure_Code.Timeout)
	_, _, lifecycle, _, _, _, available :=
		ksawery.repository_process_raw_repository_command_snapshot(&process)
	testing.expect(t, available)
	testing.expect_value(
		t,
		lifecycle.termination.reason,
		ksawery.Repository_Process_Termination_Reason.Timeout,
	)
	testing.expect_value(
		t,
		lifecycle.termination.phase,
		ksawery.Repository_Process_Termination_Phase.Reaped,
	)
}

/* Verifies excessive raw output fails closed at the core byte ceiling. */
@(test)
raw_repository_command_enforces_output_limit :: proc(t: ^testing.T) {
	limits := ksawery.DEFAULT_RAW_REPOSITORY_COMMAND_LIMITS
	limits.output_bytes = ksawery.MIN_PROCESS_OUTPUT_BYTES
	process, _, started := raw_repository_command_process_start(
		.Shell, "yes x", "/tmp", limits,
	)
	testing.expect(t, started)
	if !started do return
	defer ksawery.repository_process_close(&process)
	poll := operation_process_wait(&process)
	testing.expect_value(t, poll.state, ksawery.Repository_Process_State.Failed)
	testing.expect_value(t, poll.failure, ksawery.Failure_Code.Output_Limit)
	_, _, lifecycle, output, _, _, available :=
		ksawery.repository_process_raw_repository_command_snapshot(&process)
	testing.expect(t, available)
	testing.expect(t, lifecycle.output_truncated)
	testing.expect_value(t, u64(len(output)), limits.output_bytes)
}

/* Verifies Git mode parses bounded arguments without admitting a shell. */
@(test)
raw_repository_command_runs_direct_git_arguments :: proc(t: ^testing.T) {
	process, request, started := raw_repository_command_process_start(
		.Git,
		"rev-parse --sq-quote 'two words'",
	)
	testing.expect(t, started)
	if !started do return
	defer ksawery.repository_process_close(&process)
	poll := operation_process_wait(&process)
	testing.expect_value(t, poll.state, ksawery.Repository_Process_State.Completed)
	command, mode, lifecycle, output, _, stdin_closed, available :=
		ksawery.repository_process_raw_repository_command_snapshot(&process)
	testing.expect(t, available)
	testing.expect_value(t, command, request.intent.command)
	testing.expect_value(t, mode, ksawery.Raw_Repository_Command_Mode.Git)
	testing.expect_value(t, lifecycle.association.authority.kind, ksawery.Repository_Operation_Kind.Raw_Command)
	testing.expect(t, stdin_closed)
	testing.expect(t, strings.contains(string(output), "two words"))
}

/* Verifies shell mode uses the checked repository cwd and receives closed input. */
@(test)
raw_repository_command_runs_shell_in_repository_with_closed_input :: proc(t: ^testing.T) {
	directory, directory_error := os.make_directory_temp(
		"",
		"odra-raw-command-process-*",
		context.allocator,
	)
	testing.expect(t, directory_error == nil)
	if directory_error != nil do return
	defer {
		_ = os.remove_all(directory)
		delete(directory)
	}
	process, _, started := raw_repository_command_process_start(
		.Shell,
		"read value || printf '%s' \"$PWD\"",
		directory,
	)
	testing.expect(t, started)
	if !started do return
	defer ksawery.repository_process_close(&process)
	poll := operation_process_wait(&process)
	testing.expect_value(t, poll.state, ksawery.Repository_Process_State.Completed)
	_, mode, _, output, _, stdin_closed, available :=
		ksawery.repository_process_raw_repository_command_snapshot(&process)
	testing.expect(t, available)
	testing.expect_value(t, mode, ksawery.Raw_Repository_Command_Mode.Shell)
	testing.expect(t, stdin_closed)
	testing.expect_value(t, string(output), directory)
}

/* Verifies raw children receive only the core-owned repository environment. */
@(test)
raw_repository_command_uses_core_environment :: proc(t: ^testing.T) {
	process, _, started := raw_repository_command_process_start(
		.Shell,
		"printf '%s\\n' \"$PATH\" \"$LANG\" \"$LC_ALL\" \"$GIT_TERMINAL_PROMPT\"",
	)
	testing.expect(t, started)
	if !started do return
	defer ksawery.repository_process_close(&process)
	poll := operation_process_wait(&process)
	testing.expect_value(t, poll.state, ksawery.Repository_Process_State.Completed)
	_, _, _, output, _, _, available :=
		ksawery.repository_process_raw_repository_command_snapshot(&process)
	testing.expect(t, available)
	testing.expect_value(
		t,
		string(output),
		"/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin\nC\nC\n0\n",
	)
}
