// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

#+build linux
package interactive_session

import "core:strings"
import "core:testing"
import "core:time"

@(private)
test_process_request :: proc(executable: string, arguments: []string) -> Process_Start_Request {
	return Process_Start_Request {
		executable = executable,
		arguments = arguments,
		working_directory = "/tmp",
		columns = 80,
		rows = 24,
	}
}

@(private)
test_wait_for_text :: proc(process: ^Local_Process, expected: string) -> (found: bool, failure: Failure_Record) {
	storage: [4 * 1_024]u8
	used := 0
	for _ in 0 ..< 2_000 {
		read, would_block, end_of_file, read_failure := local_process_read(process, storage[used:])
		if read_failure.code != .None {
			return false, read_failure
		}
		used += read
		if strings.contains(string(storage[:used]), expected) {
			return true, {}
		}
		if end_of_file || used == len(storage) {
			return false, {}
		}
		if would_block || read == 0 {
			time.sleep(time.Millisecond)
		}
	}
	return false, failure_record(.Output, .Read)
}

@(private)
test_wait_for_exit :: proc(process: ^Local_Process) -> (poll: Process_Poll, ok: bool, failure: Failure_Record) {
	for _ in 0 ..< 2_000 {
		poll, ok, failure = local_process_poll(process)
		if !ok || poll.exited {
			return
		}
		time.sleep(time.Millisecond)
	}
	return {}, false, failure_record(.Poll, .Reap)
}

/* Verifies shell discovery returns one absolute executable path. */
@(test)
local_process_resolves_user_shell :: proc(t: ^testing.T) {
	shell, ok, failure := user_shell()
	testing.expectf(t, ok, "shell discovery failed with %v", failure.code)
	if !ok do return
	path := string(shell.directory[:shell.length])
	testing.expect(t, len(path) > 1 && path[0] == '/')
}

/* Verifies invalid launch fields fail before acquiring process resources. */
@(test)
local_process_rejects_invalid_launch_context :: proc(t: ^testing.T) {
	arguments := []string{"-c", "exit 0"}
	request := test_process_request("relative", arguments)
	_, ok, failure := local_process_start(request)
	testing.expect(t, !ok)
	testing.expect_value(t, failure.code, Failure_Code.Invalid_Executable)

	request.executable = "/bin/sh"
	request.working_directory = "relative"
	_, ok, failure = local_process_start(request)
	testing.expect(t, !ok)
	testing.expect_value(t, failure.code, Failure_Code.Invalid_Working_Context)

	request.working_directory = "/tmp"
	request.environment = []string{"MISSING_EQUALS"}
	_, ok, failure = local_process_start(request)
	testing.expect(t, !ok)
	testing.expect_value(t, failure.code, Failure_Code.Invalid_Environment)

	request.environment = nil
	request.executable = "/not/an/executable"
	_, ok, failure = local_process_start(request)
	testing.expect(t, !ok)
	testing.expect_value(t, failure.code, Failure_Code.Invalid_Executable)

	request.executable = "/bin/sh"
	request.working_directory = "/not/a/directory"
	_, ok, failure = local_process_start(request)
	testing.expect(t, !ok)
	testing.expect_value(t, failure.code, Failure_Code.Invalid_Working_Context)
}

/* Verifies nonblocking PTY IO, resize, exit status, and exact cleanup. */
@(test)
local_process_round_trips_pty_and_reaps_child :: proc(t: ^testing.T) {
	arguments := []string {
		"-c",
		"printf 'ready\\n'; IFS= read -r line; printf 'got:%s\\n' \"$line\"; exit 7",
	}
	process, started, failure := local_process_start(test_process_request("/bin/sh", arguments))
	testing.expectf(t, started, "PTY start failed with %v errno %v", failure.code, failure.os_errno)
	if !started do return
	defer if process.state != nil {
		_, _ = local_process_close(&process)
	}

	info, inspected := local_process_inspect(&process)
	testing.expect(t, inspected)
	testing.expectf(
		t,
		info.live && info.open_descriptors == 1,
		"unexpected process inspection: live=%v descriptors=%v pid=%v pgid=%v",
		info.live,
		info.open_descriptors,
		info.process_id,
		info.process_group_id,
	)
	testing.expect_value(t, info.process_group_id, info.process_id)
	resized, resize_failure := local_process_resize(&process, 132, 43)
	testing.expectf(t, resized, "PTY resize failed with %v", resize_failure.code)

	ready, read_failure := test_wait_for_text(&process, "ready")
	testing.expectf(t, ready, "initial PTY output failed with %v", read_failure.code)
	input := transmute([]u8)(string("Odra\n"))
	written, would_block, write_failure := local_process_write(&process, input)
	testing.expectf(t, write_failure.code == .None, "PTY write failed with %v", write_failure.code)
	testing.expect(t, !would_block && written == len(input))
	replied: bool
	replied, read_failure = test_wait_for_text(&process, "got:Odra")
	testing.expectf(t, replied, "PTY reply failed with %v", read_failure.code)

	poll, exited, poll_failure := test_wait_for_exit(&process)
	testing.expectf(t, exited, "PTY exit collection failed with %v", poll_failure.code)
	testing.expect_value(t, poll.exit_status.kind, Exit_Kind.Code)
	testing.expect_value(t, poll.exit_status.value, i32(7))
	closed, close_failure := local_process_close(&process)
	testing.expectf(t, closed, "PTY close failed with %v", close_failure.code)
	testing.expect(t, process.state == nil)
	closed, close_failure = local_process_close(&process)
	testing.expect(t, !closed)
	testing.expect_value(t, close_failure.code, Failure_Code.Invalid_Argument)
}

/* Verifies admitted signals address the owned process group and remain reapable. */
@(test)
local_process_signals_process_group :: proc(t: ^testing.T) {
	arguments := []string{"30"}
	process, started, failure := local_process_start(test_process_request("/bin/sleep", arguments))
	testing.expectf(t, started, "PTY start failed with %v errno %v", failure.code, failure.os_errno)
	if !started do return
	defer if process.state != nil {
		_, _ = local_process_close(&process)
	}

	signalled, signal_failure := local_process_signal(&process, .Terminate)
	testing.expectf(t, signalled, "PTY signal failed with %v", signal_failure.code)
	poll, exited, poll_failure := test_wait_for_exit(&process)
	testing.expectf(t, exited, "signalled PTY exit failed with %v", poll_failure.code)
	testing.expect_value(t, poll.exit_status.kind, Exit_Kind.Signal)
	closed, close_failure := local_process_close(&process)
	testing.expectf(t, closed, "signalled PTY close failed with %v", close_failure.code)
}
