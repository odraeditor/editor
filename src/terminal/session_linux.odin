// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

#+build linux
package terminal_frontend

import "../interaction"
import "base:intrinsics"
import "core:c"
import "core:sys/linux"
import "core:sys/posix"

@(private)
Linux_Window_Size :: struct {
	rows:     u16,
	columns:  u16,
	x_pixels: u16,
	y_pixels: u16,
}

#assert(size_of(Linux_Window_Size) == 8)

@(private)
resize_signal_generation: u32

@(private)
resize_signal_owned: u32

@(private)
POINTER_REPORTING_ENABLE :: "\x1b[?1002h\x1b[?1006h"

@(private)
POINTER_REPORTING_DISABLE :: "\x1b[?1002l\x1b[?1006l"

/* session_acquire owns raw mode, resize notification, and the initial geometry. */
session_acquire :: proc(
	session: ^Session,
	input_fd := posix.FD(posix.STDIN_FILENO),
	output_fd := posix.FD(posix.STDOUT_FILENO),
) -> (ok: bool, failure: Failure_Context) {
	if session == nil || session.acquired || session.restored {
		return false, Failure_Context{code = .Invalid_Session}
	}
	if !bool(posix.isatty(input_fd)) || !bool(posix.isatty(output_fd)) {
		return false, os_failure(.Not_A_Terminal)
	}
	if intrinsics.atomic_exchange(&resize_signal_owned, u32(1)) != 0 {
		return false, Failure_Context{code = .Already_Acquired}
	}
	session.input_fd = input_fd
	session.output_fd = output_fd
	if posix.tcgetattr(input_fd, &session.saved_attributes) != .OK {
		intrinsics.atomic_store(&resize_signal_owned, u32(0))
		return false, os_failure(.Acquisition_Failed)
	}
	raw := raw_attributes(session.saved_attributes)
	if posix.tcsetattr(input_fd, .TCSAFLUSH, &raw) != .OK {
		intrinsics.atomic_store(&resize_signal_owned, u32(0))
		return false, os_failure(.Raw_Mode_Failed)
	}
	session.raw_mode = true
	action: posix.sigaction_t
	action.sa_handler = resize_signal_handler
	posix.sigemptyset(&action.sa_mask)
	if posix.sigaction(posix.Signal(posix.SIGWINCH), &action, &session.saved_resize_action) != .OK {
		signal_failure := os_failure(.Signal_Failed)
		restore_failure := restore_attributes_only(session)
		intrinsics.atomic_store(&resize_signal_owned, u32(0))
		if restore_failure.code != .None {
			return false, restore_failure
		}
		return false, signal_failure
	}
	session.signal_owned = true
	session.resize_generation = intrinsics.atomic_load(&resize_signal_generation)
	geometry, geometry_ok, geometry_failure := query_geometry(output_fd)
	if !geometry_ok {
		restore_failure := restore_acquired_parts(session)
		if restore_failure.code != .None {
			return false, restore_failure
		}
		return false, geometry_failure
	}
	session.geometry = geometry
	session.acquired = true
	session.pointer_geometry_generation = 1
	pointer_ok, pointer_failure := pointer_reporting_enable(session)
	if !pointer_ok {
		restore_failure := restore_acquired_parts(session)
		session.acquired = false
		if restore_failure.code != .None do return false, restore_failure
		return false, pointer_failure
	}
	return true, {}
}

/* session_geometry queries current geometry and reports a physical size change. */
session_geometry :: proc(
	session: ^Session,
) -> (geometry: Geometry, changed: bool, ok: bool, failure: Failure_Context) {
	if !session_is_live(session) {
		return {}, false, false, Failure_Context{code = .Invalid_Session}
	}
	generation := intrinsics.atomic_load(&resize_signal_generation)
	current, current_ok, current_failure := query_geometry(session.output_fd)
	if !current_ok {
		return {}, false, false, current_failure
	}
	changed = current != session.geometry
	if changed {
		if session.pointer_geometry_generation == interaction.Pointer_Geometry_Generation(max(u64)) {
			return {}, false, false, Failure_Context{code = .Geometry_Failed, actual = max(u64)}
		}
		session.pointer_geometry_generation = interaction.Pointer_Geometry_Generation(
			u64(session.pointer_geometry_generation) + 1,
		)
	}
	session.geometry = current
	session.resize_generation = generation
	return current, changed, true, {}
}

/* session_pointer_context binds decoded input to the current root and geometry. */
session_pointer_context :: proc(
	session: ^Session,
	root_generation: interaction.Pointer_Root_Generation,
) -> (ctx: Pointer_Context, ok: bool) {
	if !session_is_live(session) || !session.pointer_reporting ||
	   root_generation == interaction.Pointer_Root_Generation(0) ||
	   session.pointer_geometry_generation == interaction.Pointer_Geometry_Generation(0) {
		return {}, false
	}
	return Pointer_Context {
		frontend = 1,
		source = 1,
		root_generation = root_generation,
		geometry_generation = session.pointer_geometry_generation,
		capabilities = {
			.Press,
			.Release,
			.Motion,
			.Wheel,
			.Modifiers,
			.Cell_Coordinates,
		},
	}, true
}

/* session_write_all writes one bounded byte sequence or reports partial progress. */
session_write_all :: proc(
	session: ^Session,
	bytes: []u8,
) -> (ok: bool, failure: Failure_Context) {
	if !session_is_live(session) {
		return false, Failure_Context{code = .Invalid_Session}
	}
	if len(bytes) > int(MAX_OUTPUT_BYTES) {
		return false, Failure_Context {
			code = .Output_Limit,
			limit = u64(MAX_OUTPUT_BYTES),
			actual = u64(len(bytes)),
		}
	}
	written: uint
	for written < len(bytes) {
		count := posix.write(
			session.output_fd,
			raw_data(bytes[written:]),
			c.size_t(len(bytes) - written),
		)
		if count < 0 && posix.errno() == .EINTR {
			continue
		}
		if count <= 0 {
			failure = os_failure(.Write_Failed)
			failure.bytes_done = u64(written)
			return false, failure
		}
		written += uint(count)
	}
	return true, {}
}

/* session_flush waits until previously written terminal output is transmitted. */
session_flush :: proc(session: ^Session) -> (ok: bool, failure: Failure_Context) {
	if !session_is_live(session) {
		return false, Failure_Context{code = .Invalid_Session}
	}
	if posix.tcdrain(session.output_fd) != .OK {
		return false, os_failure(.Flush_Failed)
	}
	return true, {}
}

/* session_read_byte returns one raw byte, bounded idle step, or resize interruption. */
session_read_byte :: proc(
	session: ^Session,
	wait_milliseconds: u32 = 50,
) -> (value: u8, result: Read_Result, failure: Failure_Context) {
	if !session_is_live(session) {
		return 0, .Failure, Failure_Context{code = .Invalid_Session}
	}
	generation := intrinsics.atomic_load(&resize_signal_generation)
	if generation != session.resize_generation {
		return 0, .Resize, {}
	}
	poll_descriptor := posix.pollfd{fd = session.input_fd, events = {.IN}}
	poll_result := posix.poll(&poll_descriptor, 1, c.int(wait_milliseconds))
	if poll_result == 0 do return 0, .Idle, {}
	if poll_result < 0 {
		if posix.errno() == .EINTR do return 0, .Resize, Failure_Context{code = .Interrupted, os_errno = i32(posix.Errno.EINTR)}
		return 0, .Failure, os_failure(.Read_Failed)
	}
	if .ERR in poll_descriptor.revents || .HUP in poll_descriptor.revents ||
	   .NVAL in poll_descriptor.revents {
		return 0, .Failure, os_failure(.Read_Failed)
	}
	buffer: [1]u8
	count := posix.read(session.input_fd, raw_data(buffer[:]), 1)
	if count == 1 {
		return buffer[0], .Byte, {}
	}
	if count < 0 && posix.errno() == .EINTR {
		return 0, .Resize, Failure_Context{code = .Interrupted, os_errno = i32(posix.Errno.EINTR)}
	}
	return 0, .Failure, os_failure(.Read_Failed)
}

/* session_restore restores signal ownership and the exact acquired termios state. */
session_restore :: proc(
	session: ^Session,
) -> (ok: bool, failure: Failure_Context) {
	if session != nil && session.restored && !session.acquired do return true, {}
	if !session_is_live(session) {
		return false, Failure_Context{code = .Invalid_Session}
	}
	failure = pointer_reporting_disable(session)
	visible_cursor := [?]u8{0x1b, '[', '?', '2', '5', 'h', 0x1b, '[', '0', 'm', '\r', '\n'}
	output_ok, output_failure := session_write_all(session, visible_cursor[:])
	if output_ok {
		output_ok, output_failure = session_flush(session)
	}
	if !output_ok && failure.code == .None {
		failure = output_failure
		failure.code = .Restoration_Failed
	}
	restore_failure := restore_acquired_parts(session)
	if failure.code == .None && restore_failure.code != .None {
		failure = restore_failure
	}
	session.acquired = false
	session.restored = true
	return failure.code == .None, failure
}

@(private)
pointer_reporting_enable :: proc(session: ^Session) -> (ok: bool, failure: Failure_Context) {
	assert(session_is_live(session) && !session.pointer_reporting)
	session.pointer_reporting = true
	ok, failure = session_write_all(session, transmute([]u8)(string(POINTER_REPORTING_ENABLE)))
	if ok do ok, failure = session_flush(session)
	return
}

@(private)
pointer_reporting_disable :: proc(session: ^Session) -> Failure_Context {
	if !session.pointer_reporting do return {}
	ok, failure := session_write_all(session, transmute([]u8)(string(POINTER_REPORTING_DISABLE)))
	if ok do ok, failure = session_flush(session)
	session.pointer_reporting = false
	if !ok {
		failure.code = .Restoration_Failed
		return failure
	}
	return {}
}

@(private)
raw_attributes :: proc(saved: posix.termios) -> posix.termios {
	raw := saved
	raw.c_iflag -= {.BRKINT, .ICRNL, .INPCK, .ISTRIP, .IXON}
	raw.c_oflag -= {.OPOST}
	raw.c_cflag += {.CS8}
	raw.c_lflag -= {.ECHO, .ICANON, .IEXTEN, .ISIG}
	raw.c_cc[.VMIN] = 1
	raw.c_cc[.VTIME] = 0
	return raw
}

@(private)
query_geometry :: proc(
	fd: posix.FD,
) -> (geometry: Geometry, ok: bool, failure: Failure_Context) {
	window: Linux_Window_Size
	result := linux.ioctl(linux.Fd(fd), linux.TIOCGWINSZ, uintptr(rawptr(&window)))
	if int(result) < 0 {
		return {}, false, os_failure(.Geometry_Failed)
	}
	if window.columns == 0 || window.rows == 0 {
		return {}, false, Failure_Context {
			code = .Invalid_Geometry,
			actual = u64(window.columns) * u64(window.rows),
		}
	}
	return Geometry{width_cells = u32(window.columns), height_rows = u32(window.rows)}, true, {}
}

@(private)
resize_signal_handler :: proc "c" (_: posix.Signal) {
	intrinsics.atomic_add(&resize_signal_generation, u32(1))
}

@(private)
restore_attributes_only :: proc(session: ^Session) -> Failure_Context {
	failure: Failure_Context
	if session.raw_mode {
		if posix.tcsetattr(
			session.input_fd,
			.TCSAFLUSH,
			&session.saved_attributes,
		) != .OK {
			failure = os_failure(.Restoration_Failed)
		}
		session.raw_mode = false
	}
	return failure
}

@(private)
restore_acquired_parts :: proc(session: ^Session) -> Failure_Context {
	first_failure := pointer_reporting_disable(session)
	if session.signal_owned {
		if posix.sigaction(posix.Signal(posix.SIGWINCH), &session.saved_resize_action, nil) != .OK {
			if first_failure.code == .None do first_failure = os_failure(.Restoration_Failed)
		}
		session.signal_owned = false
	}
	attribute_failure := restore_attributes_only(session)
	if first_failure.code == .None && attribute_failure.code != .None {
		first_failure = attribute_failure
	}
	intrinsics.atomic_store(&resize_signal_owned, u32(0))
	return first_failure
}

@(private)
os_failure :: proc(code: Failure_Code) -> Failure_Context {
	return Failure_Context{code = code, os_errno = i32(posix.errno())}
}
