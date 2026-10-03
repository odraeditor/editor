// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

#+build linux
package interactive_session

import "core:strings"

/* user_shell resolves one executable shell path without imposing a shell. */
user_shell :: proc() -> (path: Working_Context, ok: bool, failure: Failure_Record) {
	written: uintptr
	result := odra_pty_user_shell(
		raw_data(path.directory[:]), uintptr(len(path.directory)), &written)
	if result != .OK || written == 0 || written > uintptr(max(u16)) {
		return {}, false, map_pty_failure(.Start, result, 0)
	}
	path.length = u16(written)
	return path, true, {}
}

/* local_process_start validates structured launch data and acquires one PTY child. */
local_process_start :: proc(
	request: Process_Start_Request,
) -> (process: Local_Process, ok: bool, failure: Failure_Record) {
	if validation_failure := process_start_request_failure(request); validation_failure != .None {
		return {}, false, failure_record(.Start, validation_failure)
	}
	allocator := context.temp_allocator
	if allocator.procedure == nil {
		return {}, false, failure_record(.Start, .Allocation)
	}

	executable, allocation_error := strings.clone_to_cstring(request.executable, allocator)
	if allocation_error != nil {
		return {}, false, failure_record(.Start, .Allocation)
	}
	working_directory: cstring
	working_directory, allocation_error = strings.clone_to_cstring(
		request.working_directory, allocator)
	if allocation_error != nil {
		return {}, false, failure_record(.Start, .Allocation)
	}

	argument_values: [MAX_ARGUMENTS + 2]cstring
	argument_values[0] = executable
	for argument, index in request.arguments {
		argument_values[index + 1], allocation_error = strings.clone_to_cstring(argument, allocator)
		if allocation_error != nil {
			return {}, false, failure_record(.Start, .Allocation)
		}
	}
	argument_count := len(request.arguments) + 1
	argument_values[argument_count] = nil

	environment_values: [MAX_ENVIRONMENT_ENTRIES + 1]cstring
	for entry, index in request.environment {
		environment_values[index], allocation_error = strings.clone_to_cstring(entry, allocator)
		if allocation_error != nil {
			return {}, false, failure_record(.Start, .Allocation)
		}
	}
	environment_values[len(request.environment)] = nil

	os_errno: i32
	result := odra_pty_process_start(
		executable,
		raw_data(argument_values[:]),
		uintptr(argument_count),
		raw_data(environment_values[:]),
		uintptr(len(request.environment)),
		working_directory,
		request.columns,
		request.rows,
		&process.state,
		&os_errno,
	)
	if result != .OK {
		return {}, false, map_pty_failure(.Start, result, os_errno)
	}
	return process, true, {}
}

/* local_process_start_shell starts the resolved user shell interactively. */
local_process_start_shell :: proc(
	working_directory: string,
	columns: u16 = 80,
	rows: u16 = 24,
) -> (process: Local_Process, ok: bool, failure: Failure_Record) {
	shell_path, shell_ok, shell_failure := user_shell()
	if !shell_ok {
		return {}, false, shell_failure
	}
	shell := string(shell_path.directory[:shell_path.length])
	arguments := []string{"-i"}
	return local_process_start(Process_Start_Request {
		executable = shell,
		arguments = arguments,
		working_directory = working_directory,
		columns = columns,
		rows = rows,
	})
}

/* local_process_read performs one nonblocking PTY read. */
local_process_read :: proc(
	process: ^Local_Process,
	output: []u8,
) -> (read: int, would_block, end_of_file: bool, failure: Failure_Record) {
	if process == nil || process.state == nil || len(output) == 0 {
		return 0, false, false, failure_record(.Output, .Invalid_Argument)
	}
	foreign_read: uintptr
	os_errno: i32
	result := odra_pty_process_read(
		process.state, raw_data(output), uintptr(len(output)), &foreign_read, &os_errno)
	if result == .Would_Block {
		return 0, true, false, {}
	}
	if result == .End_Of_File {
		return 0, false, true, {}
	}
	if result != .OK || foreign_read > uintptr(max(int)) {
		return 0, false, false, map_pty_failure(.Output, result, os_errno)
	}
	return int(foreign_read), false, false, {}
}

/* local_process_write performs one nonblocking PTY write. */
local_process_write :: proc(
	process: ^Local_Process,
	input: []u8,
) -> (written: int, would_block: bool, failure: Failure_Record) {
	if process == nil || process.state == nil || len(input) == 0 {
		return 0, false, failure_record(.Input, .Invalid_Argument)
	}
	foreign_written: uintptr
	os_errno: i32
	result := odra_pty_process_write(
		process.state, raw_data(input), uintptr(len(input)), &foreign_written, &os_errno)
	if result == .Would_Block {
		return 0, true, {}
	}
	if result != .OK || foreign_written > uintptr(max(int)) {
		return 0, false, map_pty_failure(.Input, result, os_errno)
	}
	return int(foreign_written), false, {}
}

/* local_process_resize publishes one checked PTY geometry. */
local_process_resize :: proc(
	process: ^Local_Process,
	columns, rows: u16,
) -> (bool, Failure_Record) {
	if process == nil || process.state == nil || columns == 0 || rows == 0 ||
	   u64(columns) * u64(rows) > MAX_CELLS {
		return false, failure_record(.Resize, .Invalid_Argument)
	}
	os_errno: i32
	result := odra_pty_process_resize(process.state, columns, rows, &os_errno)
	if result != .OK {
		return false, map_pty_failure(.Resize, result, os_errno)
	}
	return true, {}
}

/* local_process_poll collects one child exit at most once. */
local_process_poll :: proc(process: ^Local_Process) -> (poll: Process_Poll, ok: bool, failure: Failure_Record) {
	if process == nil || process.state == nil {
		return {}, false, failure_record(.Poll, .Invalid_Argument)
	}
	signalled: bool
	status, os_errno: i32
	result := odra_pty_process_poll(
		process.state, &poll.exited, &signalled, &status, &os_errno)
	if result != .OK {
		return {}, false, map_pty_failure(.Poll, result, os_errno)
	}
	if poll.exited {
		poll.exit_status.kind = signalled ? .Signal : .Code
		poll.exit_status.value = status
	}
	return poll, true, {}
}

/* local_process_signal sends one admitted signal to the owned process group. */
local_process_signal :: proc(
	process: ^Local_Process,
	signal: Process_Signal,
) -> (bool, Failure_Record) {
	if process == nil || process.state == nil {
		return false, failure_record(.Terminate, .Invalid_Argument)
	}
	os_errno: i32
	result := odra_pty_process_signal(process.state, signal, &os_errno)
	if result != .OK {
		return false, map_pty_failure(.Terminate, result, os_errno)
	}
	return true, {}
}

/* local_process_inspect returns copied process and descriptor ownership. */
local_process_inspect :: proc(process: ^Local_Process) -> (info: Process_Info, ok: bool) {
	if process == nil || process.state == nil {
		return {}, false
	}
	result := odra_pty_process_inspect(process.state, &info)
	return info, result == .OK
}

/* local_process_close kills if necessary, reaps, closes, and invalidates ownership. */
local_process_close :: proc(process: ^Local_Process) -> (bool, Failure_Record) {
	if process == nil || process.state == nil {
		return false, failure_record(.Close, .Invalid_Argument)
	}
	os_errno: i32
	result := odra_pty_process_close(&process.state, &os_errno)
	if result != .OK {
		return false, map_pty_failure(.Close, result, os_errno)
	}
	return true, {}
}

@(private)
process_start_request_failure :: proc(request: Process_Start_Request) -> Failure_Code {
	if len(request.executable) == 0 || request.executable[0] != '/' ||
	   len(request.executable) > MAX_DIRECTORY_BYTES ||
	   strings.index_byte(request.executable, 0) >= 0 {
		return .Invalid_Executable
	}
	if len(request.working_directory) == 0 || request.working_directory[0] != '/' ||
	   len(request.working_directory) > MAX_DIRECTORY_BYTES ||
	   strings.index_byte(request.working_directory, 0) >= 0 {
		return .Invalid_Working_Context
	}
	if len(request.arguments) > MAX_ARGUMENTS ||
	   request.columns == 0 || request.rows == 0 {
		return .Invalid_Argument
	}
	for argument in request.arguments {
		if len(argument) > MAX_DIAGNOSTIC_BYTES || strings.index_byte(argument, 0) >= 0 {
			return .Invalid_Argument
		}
	}
	if len(request.environment) > MAX_ENVIRONMENT_ENTRIES {
		return .Invalid_Environment
	}
	for entry in request.environment {
		equals := strings.index_byte(entry, '=')
		if equals <= 0 || len(entry) > MAX_DIAGNOSTIC_BYTES ||
		   strings.index_byte(entry, 0) >= 0 {
			return .Invalid_Environment
		}
	}
	return .None
}

@(private)
map_pty_failure :: proc(stage: Failure_Stage, result: Pty_Result, os_errno: i32) -> Failure_Record {
	code := Failure_Code.None
	switch result {
	case .OK, .Would_Block, .End_Of_File:
		code = .None
	case .Invalid_Argument:
		code = .Invalid_Argument
	case .Executable_Invalid:
		code = .Invalid_Executable
	case .Working_Directory_Invalid:
		code = .Invalid_Working_Context
	case .Allocation_Failed:
		code = .Allocation
	case .Open_Failed:
		code = .PTY_Open
	case .Configure_Failed:
		code = .PTY_Configure
	case .Spawn_Failed:
		code = .Spawn
	case .Nonblocking_Failed:
		code = .Nonblocking
	case .Resize_Failed:
		code = .Resize
	case .Read_Failed:
		code = .Read
	case .Write_Failed:
		code = .Write
	case .Signal_Failed:
		code = .Signal
	case .Reap_Failed:
		code = .Reap
	case .Closed:
		code = .Cleanup
	case .Buffer_Too_Small:
		code = .Output_Limit
	}
	return failure_record(stage, code, os_errno)
}
