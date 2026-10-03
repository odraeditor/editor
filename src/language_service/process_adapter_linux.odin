// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

#+build linux
package language_service

import "core:io"
import "core:os"
import "core:sys/linux"

@(private)
Platform_Child :: struct {
	process: os.Process,
	stdin:   ^os.File,
	stdout:  ^os.File,
	stderr:  ^os.File,
	live:    bool,
	reaped:  bool,
}

@(private)
platform_child_start :: proc(
	command: []string,
	environment: []string,
	working_directory: string,
) -> (Platform_Child, bool, Failure_Context) {
	if len(command) == 0 do return {}, false, Failure_Context{code = .Invalid_Input}
	stdin_read, stdin_write, stdin_error := os.pipe()
	if stdin_error != nil do return {}, false, Failure_Context{code = .Pipe}
	stdout_read, stdout_write, stdout_error := os.pipe()
	if stdout_error != nil {
		os.close(stdin_read)
		os.close(stdin_write)
		return {}, false, Failure_Context{code = .Pipe}
	}
	stderr_read, stderr_write, stderr_error := os.pipe()
	if stderr_error != nil {
		os.close(stdout_read)
		os.close(stdout_write)
		os.close(stdin_read)
		os.close(stdin_write)
		return {}, false, Failure_Context{code = .Pipe}
	}

	ready := platform_file_nonblocking(stdin_write) &&
		platform_file_nonblocking(stdout_read) &&
		platform_file_nonblocking(stderr_read)
	if !ready {
		close_pipe_set(stdin_read, stdin_write, stdout_read, stdout_write, stderr_read, stderr_write)
		return {}, false, Failure_Context{code = .Pipe}
	}
	process, process_error := os.process_start(os.Process_Desc {
		working_dir = working_directory,
		command = command,
		env = environment,
		stderr = stderr_write,
		stdout = stdout_write,
		stdin = stdin_read,
	})
	os.close(stdin_read)
	os.close(stdout_write)
	os.close(stderr_write)
	if process_error != nil {
		os.close(stdin_write)
		os.close(stdout_read)
		os.close(stderr_read)
		return {}, false, Failure_Context{code = .Spawn}
	}
	return Platform_Child {
		process = process,
		stdin = stdin_write,
		stdout = stdout_read,
		stderr = stderr_read,
		live = true,
	}, true, {}
}

@(private)
platform_child_read :: proc(file: ^os.File, output: []u8) -> (int, bool, bool, Failure_Context) {
	if file == nil || len(output) == 0 do return 0, false, false, Failure_Context{code = .Invalid_Input}
	count, read_error := os.read(file, output)
	if read_error == nil do return count, false, count == 0, {}
	if os_error_is_again(read_error) do return count, true, false, {}
	if os_error_is_closed_stream(read_error) do return count, false, true, {}
	return count, false, false, Failure_Context{code = .Pipe}
}

@(private)
platform_child_write :: proc(file: ^os.File, input: []u8) -> (int, bool, Failure_Context) {
	if file == nil || len(input) == 0 do return 0, false, Failure_Context{code = .Invalid_Input}
	count, write_error := os.write(file, input)
	if write_error == nil do return count, false, {}
	if os_error_is_again(write_error) do return count, true, {}
	return count, false, Failure_Context{code = .Pipe}
}

@(private)
platform_child_poll :: proc(child: ^Platform_Child) -> (bool, i32, Failure_Context) {
	if child == nil || !child.live do return false, 0, {}
	state, wait_error := os.process_wait(child.process, 0)
	if wait_error != nil {
		if os_error_is_timeout(wait_error) do return false, 0, {}
		return false, 0, Failure_Context{code = .Reap}
	}
	child.live = false
	child.reaped = true
	return state.exited, i32(state.exit_code), {}
}

@(private)
platform_child_terminate :: proc(child: ^Platform_Child) -> bool {
	return child != nil && child.live && os.process_terminate(child.process) == nil
}

@(private)
platform_child_kill :: proc(child: ^Platform_Child) -> bool {
	return child != nil && child.live && os.process_kill(child.process) == nil
}

@(private)
platform_child_close :: proc(child: ^Platform_Child) {
	if child == nil do return
	if child.live {
		_ = os.process_kill(child.process)
		_, _ = os.process_wait(child.process)
		child.live = false
		child.reaped = true
	}
	if child.stdin != nil do os.close(child.stdin)
	if child.stdout != nil do os.close(child.stdout)
	if child.stderr != nil do os.close(child.stderr)
	child^ = Platform_Child{reaped = true}
}

@(private = "file")
platform_file_nonblocking :: proc(file: ^os.File) -> bool {
	if file == nil do return false
	fd := linux.Fd(os.fd(file))
	flags, get_error := linux.fcntl(fd, linux.F_GETFL)
	if get_error != .NONE do return false
	flags += {.NONBLOCK}
	return linux.fcntl(fd, linux.F_SETFL, flags) == .NONE
}

@(private = "file")
close_pipe_set :: proc(files: ..^os.File) {
	for file in files {
		if file != nil do os.close(file)
	}
}

@(private = "file")
os_error_is_again :: proc(value: os.Error) -> bool {
	#partial switch error_value in value {
	case os.Platform_Error:
		return error_value == .EAGAIN
	case:
		return false
	}
}

@(private = "file")
os_error_is_timeout :: proc(value: os.Error) -> bool {
	#partial switch error_value in value {
	case os.General_Error:
		return error_value == .Timeout
	case:
		return false
	}
}

@(private = "file")
os_error_is_closed_stream :: proc(value: os.Error) -> bool {
	#partial switch error_value in value {
	case os.General_Error:
		return error_value == .Broken_Pipe
	case io.Error:
		return error_value == .EOF
	case:
		return false
	}
}
