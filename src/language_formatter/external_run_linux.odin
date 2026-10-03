// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

#+build linux
package language_formatter

import "base:runtime"
import "core:io"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:sys/linux"
import "core:unicode/utf8"

TEMPORARY_FILE_ARGUMENT :: "{file}"
EXTERNAL_IO_CHUNK_BYTES :: 64 * 1_024
EXTERNAL_STDERR_BYTES :: 64 * 1_024
EXTERNAL_KILL_GRACE_NS :: i64(100_000_000)

External_Run_Request :: struct {
	definition:        ^Formatter_Record,
	input:             []u8,
	admitted_root:     string,
	working_directory: string,
	project_trusted:   bool,
	now_ns:            i64,
}

External_Run_Status :: enum u8 {Invalid, Running, Completed, Failed, Timed_Out, Closed}

External_Run_Poll :: struct {
	status:       External_Run_Status,
	read_bytes:   u64,
	written_bytes: u64,
	exited:       bool,
	exit_code:    i32,
	failure:      Failure,
}

External_Run :: struct {state: rawptr}

@(private)
External_Run_State :: struct {
	process:       os.Process,
	stdin:         ^os.File,
	stdout:        ^os.File,
	stderr:        ^os.File,
	input:         []u8,
	input_offset:  int,
	output:        [dynamic]u8,
	standard_error: [dynamic]u8,
	output_mode:   Output_Mode,
	limits:        Formatter_Limits,
	deadline_ns:   i64,
	kill_due_ns:   i64,
	temporary_file: ^os.File,
	temporary_path: string,
	live:          bool,
	reaped:        bool,
	stdin_closed:  bool,
	stdout_closed: bool,
	status:        External_Run_Status,
	exit_code:     i32,
	failure:       Failure,
	allocator:     runtime.Allocator,
}

/* external_run_start launches one formatter without a shell or canonical document path. */
external_run_start :: proc(
	request: External_Run_Request,
	allocator := context.allocator,
) -> (External_Run, bool, Failure) {
	if allocator.procedure == nil || !external_request_valid(request) do return {}, false, Failure{code = .Invalid_Input}
	state, allocation_error := new(External_Run_State, allocator)
	if allocation_error != nil do return {}, false, Failure{code = .Allocation}
	state^ = {
		output_mode = request.definition.output_mode,
		limits = request.definition.limits,
		deadline_ns = external_deadline(request.now_ns, request.definition.limits.timeout_ns),
		status = .Running,
		allocator = allocator,
	}
	state.input, allocation_error = make([]u8, len(request.input), allocator)
	if allocation_error == nil do copy(state.input, request.input)
	if allocation_error == nil do state.output, allocation_error = make([dynamic]u8, 0, min(len(request.input) + 1_024, int(request.definition.limits.output_bytes)), allocator)
	if allocation_error == nil do state.standard_error, allocation_error = make([dynamic]u8, 0, 1_024, allocator)
	if allocation_error != nil {
		external_state_destroy(state)
		return {}, false, Failure{code = .Allocation}
	}

	needs_temporary := request.definition.input_mode == .Temporary_File || request.definition.output_mode == .Temporary_File
	if needs_temporary {
		state.temporary_file, _ = os.create_temp_file("", "odra-format-*.tmp")
		if state.temporary_file == nil {
			external_state_destroy(state)
			return {}, false, Failure{code = .Pipe, resource = .Temporary_Bytes}
		}
		state.temporary_path, allocation_error = strings.clone(os.name(state.temporary_file), allocator)
		if allocation_error != nil {
			external_state_destroy(state)
			return {}, false, Failure{code = .Allocation}
		}
		if request.definition.input_mode == .Temporary_File && !external_file_write_all(state.temporary_file, request.input) {
			external_state_destroy(state)
			return {}, false, Failure{code = .Pipe, resource = .Temporary_Bytes}
		}
	}

	command, command_ok := external_command(request.definition, state.temporary_path, needs_temporary, context.temp_allocator)
	if !command_ok {
		external_state_destroy(state)
		return {}, false, Failure{code = .Invalid_Definition}
	}
	stdin_read, stdin_write, stdin_error := os.pipe()
	if stdin_error != nil {
		external_state_destroy(state)
		return {}, false, Failure{code = .Pipe}
	}
	stdout_read, stdout_write, stdout_error := os.pipe()
	if stdout_error != nil {
		os.close(stdin_read); os.close(stdin_write)
		external_state_destroy(state)
		return {}, false, Failure{code = .Pipe}
	}
	stderr_read, stderr_write, stderr_error := os.pipe()
	if stderr_error != nil {
		external_close_files(stdin_read, stdin_write, stdout_read, stdout_write)
		external_state_destroy(state)
		return {}, false, Failure{code = .Pipe}
	}
	if !external_nonblocking(stdin_write) || !external_nonblocking(stdout_read) || !external_nonblocking(stderr_read) {
		external_close_files(stdin_read, stdin_write, stdout_read, stdout_write, stderr_read, stderr_write)
		external_state_destroy(state)
		return {}, false, Failure{code = .Pipe}
	}
	environment := external_environment(request.definition, context.temp_allocator)
	process_error: os.Error
	state.process, process_error = os.process_start(os.Process_Desc {
		working_dir = request.working_directory,
		command = command[:],
		env = environment[:],
		stdin = stdin_read,
		stdout = stdout_write,
		stderr = stderr_write,
	})
	os.close(stdin_read); os.close(stdout_write); os.close(stderr_write)
	if process_error != nil {
		external_close_files(stdin_write, stdout_read, stderr_read)
		external_state_destroy(state)
		return {}, false, Failure{code = .Spawn}
	}
	state.stdin = stdin_write
	state.stdout = stdout_read
	state.stderr = stderr_read
	state.live = true
	if request.definition.input_mode == .Temporary_File {
		os.close(state.stdin)
		state.stdin = nil
		state.stdin_closed = true
	}
	return External_Run{state = state}, true, {}
}

/* external_run_poll performs one bounded nonblocking formatter IO and lifecycle step. */
external_run_poll :: proc(run: ^External_Run, now_ns: i64) -> (External_Run_Poll, bool) {
	state := external_state(run)
	if state == nil do return External_Run_Poll{status = .Closed, failure = {code = .Closed}}, false
	result := External_Run_Poll{status = state.status, failure = state.failure}
	if state.status != .Running && state.live == false {
		result.exited = state.reaped
		result.exit_code = state.exit_code
		return result, true
	}
	buffer: [EXTERNAL_IO_CHUNK_BYTES]u8
	if state.stdin != nil && !state.stdin_closed {
		if state.input_offset < len(state.input) {
			written, write_error := os.write(state.stdin, state.input[state.input_offset:])
			if write_error == nil {
				state.input_offset += written
				result.written_bytes += u64(written)
			} else if !external_error_again(write_error) {
				external_fail(state, .Pipe)
			}
		}
		if state.input_offset == len(state.input) {
			os.close(state.stdin)
			state.stdin = nil
			state.stdin_closed = true
		}
	}
	if state.stdout != nil && !state.stdout_closed {
		read_count, read_error := os.read(state.stdout, buffer[:])
		if read_count > 0 {
			result.read_bytes += u64(read_count)
			if state.output_mode == .Standard_Output {
				if u64(len(state.output)) + u64(read_count) > state.limits.output_bytes {
				external_fail(state, .Output_Limit, .Output_Bytes, state.limits.output_bytes, u64(len(state.output)) + u64(read_count))
				} else if _, append_error := append(&state.output, ..buffer[:read_count]); append_error != nil {
					external_fail(state, .Allocation)
				}
			}
		}
		if external_error_eof(read_error) || (read_error == nil && read_count == 0) {
			os.close(state.stdout)
			state.stdout = nil
			state.stdout_closed = true
		} else if read_error != nil && !external_error_again(read_error) {
			external_fail(state, .Pipe)
		}
	}
	if state.stderr != nil {
		read_count, read_error := os.read(state.stderr, buffer[:])
		if read_count > 0 do external_stderr_append(state, buffer[:read_count])
		if external_error_eof(read_error) || (read_error == nil && read_count == 0) {
			os.close(state.stderr)
			state.stderr = nil
		} else if read_error != nil && !external_error_again(read_error) {
			external_fail(state, .Pipe)
		}
	}
	if state.live {
		process_state, wait_error := os.process_wait(state.process, 0)
		if wait_error == nil && process_state.exited {
			state.live = false
			state.reaped = true
			state.exit_code = i32(process_state.exit_code)
			result.exited = true
			result.exit_code = state.exit_code
		} else if wait_error != nil && !external_error_timeout(wait_error) {
			external_fail(state, .Exit_Failure)
		}
	}
	if state.live && state.deadline_ns > 0 && now_ns >= state.deadline_ns && state.kill_due_ns == 0 {
		_ = os.process_terminate(state.process)
		state.failure = {code = .Timeout}
		state.status = .Timed_Out
		state.kill_due_ns = external_deadline(now_ns, EXTERNAL_KILL_GRACE_NS)
	}
	if state.live && state.kill_due_ns > 0 && now_ns >= state.kill_due_ns {
		_ = os.process_kill(state.process)
		state.kill_due_ns = max(i64)
	}
	if !state.live && state.reaped {
		if state.status == .Running && state.exit_code != 0 do external_fail(state, .Exit_Failure)
		if state.status == .Running && state.output_mode == .Temporary_File && !external_read_temporary_output(state) {
			if state.failure.code == .None do external_fail(state, .Pipe, .Temporary_Bytes)
		}
		if state.status == .Running {
			state.status = .Completed
			if !utf8.valid_string(string(state.output[:])) do external_fail(state, .Malformed_Output)
		}
	}
	result.status = state.status
	result.failure = state.failure
	return result, true
}

external_run_output :: proc(run: ^External_Run) -> ([]u8, bool, Failure) {
	state := external_state(run)
	if state == nil do return nil, false, Failure{code = .Closed}
	if state.status != .Completed do return nil, false, state.failure
	return state.output[:], true, {}
}

external_run_stderr :: proc(run: ^External_Run) -> ([]u8, bool) {
	state := external_state(run)
	if state == nil do return nil, false
	return state.standard_error[:], true
}

external_run_close :: proc(run: ^External_Run) -> bool {
	state := external_state(run)
	if state == nil do return false
	external_state_destroy(state)
	run^ = {}
	return true
}

@(private)
external_state :: proc(run: ^External_Run) -> ^External_Run_State {
	if run == nil || run.state == nil do return nil
	return cast(^External_Run_State)run.state
}

@(private)
external_request_valid :: proc(request: External_Run_Request) -> bool {
	definition := request.definition
	if definition == nil do return false
	if definition.kind != .External || definition.profile.availability != .Available ||
	   !formatter_limits_valid(definition.limits) || u64(len(request.input)) > definition.limits.input_bytes ||
	   !utf8.valid_string(string(request.input)) || !request.project_trusted || request.admitted_root == "" ||
	   request.working_directory != request.admitted_root || !filepath.is_abs(request.admitted_root) ||
	   !filepath.is_abs(text_view(&definition.profile.resolved)) || request.now_ns < 0 {
		return false
	}
	return true
}

@(private)
external_command :: proc(
	definition: ^Formatter_Record,
	temporary_path: string,
	needs_temporary: bool,
	allocator: runtime.Allocator,
) -> ([dynamic]string, bool) {
	command, allocation_error := make([dynamic]string, 0, int(definition.argument_count) + 1, allocator)
	if allocation_error != nil do return nil, false
	_, allocation_error = append(&command, text_view(&definition.profile.resolved))
	if allocation_error != nil do return nil, false
	placeholder_found := false
	for index in 0..<int(definition.argument_count) {
		argument := text_view(&definition.arguments[index])
		if argument == TEMPORARY_FILE_ARGUMENT {
			placeholder_found = true
			argument = temporary_path
		}
		_, allocation_error = append(&command, argument)
		if allocation_error != nil do return nil, false
	}
	return command, placeholder_found == needs_temporary
}

@(private)
external_environment :: proc(definition: ^Formatter_Record, allocator: runtime.Allocator) -> [dynamic]string {
	if definition == nil do return nil
	values, _ := make([dynamic]string, 0, int(definition.environment_count), allocator)
	for index in 0..<int(definition.environment_count) do append(&values, text_view(&definition.environment[index]))
	return values
}

@(private)
external_file_write_all :: proc(file: ^os.File, input: []u8) -> bool {
	written := 0
	for written < len(input) {
		count, write_error := os.write(file, input[written:])
		if write_error != nil || count <= 0 do return false
		written += count
	}
	_, seek_error := os.seek(file, 0, .Start)
	return seek_error == nil
}

@(private)
external_read_temporary_output :: proc(state: ^External_Run_State) -> bool {
	if state.temporary_file != nil {
		os.close(state.temporary_file)
		state.temporary_file = nil
	}
	info, stat_error := os.stat(state.temporary_path, context.temp_allocator)
	if stat_error != nil do return false
	defer os.file_info_delete(info, context.temp_allocator)
	if info.size < 0 || u64(info.size) > state.limits.output_bytes {
		external_fail(state, .Output_Limit, .Output_Bytes, state.limits.output_bytes, u64(max(info.size, 0)))
		return false
	}
	data, read_error := os.read_entire_file(state.temporary_path, state.allocator)
	if read_error != nil do return false
	defer delete(data, state.allocator)
	if resize_error := resize(&state.output, len(data)); resize_error != nil {
		external_fail(state, .Allocation)
		return false
	}
	copy(state.output[:], data)
	return true
}

@(private)
external_state_destroy :: proc(state: ^External_Run_State) {
	if state == nil do return
	if state.live {
		_ = os.process_kill(state.process)
		_, _ = os.process_wait(state.process)
	}
	external_close_files(state.stdin, state.stdout, state.stderr, state.temporary_file)
	if state.temporary_path != "" {
		_ = os.remove(state.temporary_path)
		delete(state.temporary_path, state.allocator)
	}
	if state.input != nil do delete(state.input, state.allocator)
	if state.output != nil do delete(state.output)
	if state.standard_error != nil do delete(state.standard_error)
	allocator := state.allocator
	free(state, allocator)
}

@(private)
external_nonblocking :: proc(file: ^os.File) -> bool {
	if file == nil do return false
	fd := linux.Fd(os.fd(file))
	flags, get_error := linux.fcntl(fd, linux.F_GETFL)
	if get_error != .NONE do return false
	flags += {.NONBLOCK}
	return linux.fcntl(fd, linux.F_SETFL, flags) == .NONE
}

@(private)
external_close_files :: proc(files: ..^os.File) {
	for file in files do if file != nil do os.close(file)
}

@(private)
external_deadline :: proc(now_ns, duration_ns: i64) -> i64 {
	if duration_ns <= 0 || now_ns > max(i64) - duration_ns do return max(i64)
	return now_ns + duration_ns
}

@(private)
external_fail :: proc(
	state: ^External_Run_State,
	code: Failure_Code,
	resource := Resource_Kind.None,
	limit := u64(0),
	actual := u64(0),
) {
	if state.failure.code != .None do return
	state.failure = {code = code, resource = resource, limit = limit, actual = actual}
	state.status = .Failed
	if state.live {
		_ = os.process_kill(state.process)
		state.kill_due_ns = max(i64)
	}
}

@(private)
external_stderr_append :: proc(state: ^External_Run_State, input: []u8) {
	if len(input) >= EXTERNAL_STDERR_BYTES {
		resize(&state.standard_error, 0)
		append(&state.standard_error, ..input[len(input) - EXTERNAL_STDERR_BYTES:])
		return
	}
	excess := len(state.standard_error) + len(input) - EXTERNAL_STDERR_BYTES
	if excess > 0 {
		copy(state.standard_error[:], state.standard_error[excess:])
		resize(&state.standard_error, len(state.standard_error) - excess)
	}
	append(&state.standard_error, ..input)
}

@(private)
external_error_again :: proc(value: os.Error) -> bool {
	#partial switch error_value in value {
	case os.Platform_Error:
		return error_value == .EAGAIN
	case:
		return false
	}
}

@(private)
external_error_eof :: proc(value: os.Error) -> bool {
	#partial switch error_value in value {
	case os.General_Error:
		return error_value == .Broken_Pipe
	case io.Error:
		return error_value == .EOF
	case:
		return false
	}
}

@(private)
external_error_timeout :: proc(value: os.Error) -> bool {
	#partial switch error_value in value {
	case os.General_Error:
		return error_value == .Timeout
	case:
		return false
	}
}
