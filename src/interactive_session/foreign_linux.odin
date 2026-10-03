// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

#+build linux
package interactive_session

@(private)
ODRA_INTERACTIVE_SESSION_ADAPTER_LIBRARY :: #config(
	ODRA_INTERACTIVE_SESSION_ADAPTER_LIBRARY,
	"../../.build/interactive-session/libodra-interactive-session-adapter.a",
)

foreign import interactive_session_adapter {ODRA_INTERACTIVE_SESSION_ADAPTER_LIBRARY}

@(private)
Pty_Result :: enum i32 {
	OK = 0,
	Invalid_Argument,
	Executable_Invalid,
	Working_Directory_Invalid,
	Allocation_Failed,
	Open_Failed,
	Configure_Failed,
	Spawn_Failed,
	Nonblocking_Failed,
	Resize_Failed,
	Read_Failed,
	Write_Failed,
	Signal_Failed,
	Reap_Failed,
	Closed,
	Would_Block,
	End_Of_File,
	Buffer_Too_Small,
}

@(private, default_calling_convention="c")
foreign interactive_session_adapter {
	odra_pty_user_shell :: proc(
		output: ^u8,
		output_capacity: uintptr,
		out_written: ^uintptr,
	) -> Pty_Result ---
	odra_pty_process_start :: proc(
		executable: cstring,
		arguments: [^]cstring,
		argument_count: uintptr,
		environment: [^]cstring,
		environment_count: uintptr,
		working_directory: cstring,
		columns, rows: u16,
		out_process: ^rawptr,
		out_errno: ^i32,
	) -> Pty_Result ---
	odra_pty_process_read :: proc(
		process: rawptr,
		output: ^u8,
		output_capacity: uintptr,
		out_read: ^uintptr,
		out_errno: ^i32,
	) -> Pty_Result ---
	odra_pty_process_write :: proc(
		process: rawptr,
		input: ^u8,
		input_length: uintptr,
		out_written: ^uintptr,
		out_errno: ^i32,
	) -> Pty_Result ---
	odra_pty_process_resize :: proc(
		process: rawptr,
		columns, rows: u16,
		out_errno: ^i32,
	) -> Pty_Result ---
	odra_pty_process_poll :: proc(
		process: rawptr,
		out_exited, out_signalled: ^bool,
		out_status, out_errno: ^i32,
	) -> Pty_Result ---
	odra_pty_process_signal :: proc(
		process: rawptr,
		signal: Process_Signal,
		out_errno: ^i32,
	) -> Pty_Result ---
	odra_pty_process_inspect :: proc(process: rawptr, out_info: ^Process_Info) -> Pty_Result ---
	odra_pty_process_close :: proc(process: ^rawptr, out_errno: ^i32) -> Pty_Result ---
}
