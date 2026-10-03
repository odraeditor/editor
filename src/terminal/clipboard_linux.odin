// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

#+build linux
package terminal_frontend

import "core:c"
import "core:sys/posix"
import "core:time"

@(private)
clipboard_osc52_session_write :: proc "odin" (
	user_data: rawptr,
	frame: []u8,
	timeout_milliseconds: u32,
	cancellation_bytes: u64,
	cancellation: Clipboard_Cancellation,
) -> (bytes_done: u64, ok: bool, failure: Clipboard_Failure_Context) {
	session := (^Session)(user_data)
	if !session_is_live(session) {
		return 0, false, Clipboard_Failure_Context{code = .Write_Unavailable}
	}
	if len(frame) == 0 || len(frame) > int(MAX_OUTPUT_BYTES) || cancellation_bytes == 0 {
		return 0, false, Clipboard_Failure_Context {
			code = .Write_Failed,
			limit = u64(MAX_OUTPUT_BYTES),
			actual = u64(len(frame)),
		}
	}
	flags_value := posix.fcntl(session.output_fd, .GETFL, 0)
	if flags_value < 0 {
		return 0, false, clipboard_os_failure(.Write_Failed)
	}
	flags := transmute(posix.O_Flags)flags_value
	restore_flags := .NONBLOCK not_in flags
	if restore_flags {
		flags += {.NONBLOCK}
		if posix.fcntl(session.output_fd, .SETFL, flags) < 0 {
			return 0, false, clipboard_os_failure(.Write_Failed)
		}
	}
	defer if restore_flags {
		flags -= {.NONBLOCK}
		if posix.fcntl(session.output_fd, .SETFL, flags) < 0 {
			ok = false
			failure = clipboard_os_failure(.Transport_Restore_Failed)
			failure.bytes_done = bytes_done
		}
	}

	started := time.tick_now()
	for bytes_done < u64(len(frame)) {
		if clipboard_cancelled(cancellation) {
			return bytes_done, false, Clipboard_Failure_Context {
				code = .Cancelled,
				bytes_done = bytes_done,
			}
		}
		remaining_ms, within_time := clipboard_transport_remaining_milliseconds(
			started,
			timeout_milliseconds,
		)
		if !within_time {
			return bytes_done, false, Clipboard_Failure_Context {
				code = .Timed_Out,
				bytes_done = bytes_done,
			}
		}
		poll_descriptor := posix.pollfd {
			fd = session.output_fd,
			events = {.OUT},
		}
		poll_result := posix.poll(&poll_descriptor, 1, c.int(remaining_ms))
		if poll_result == 0 {
			return bytes_done, false, Clipboard_Failure_Context {
				code = .Timed_Out,
				bytes_done = bytes_done,
			}
		}
		if poll_result < 0 {
			if posix.errno() == .EINTR {
				continue
			}
			poll_failure := clipboard_os_failure(.Write_Failed)
			poll_failure.bytes_done = bytes_done
			return bytes_done, false, poll_failure
		}
		if .ERR in poll_descriptor.revents || .HUP in poll_descriptor.revents ||
		   .NVAL in poll_descriptor.revents {
			poll_failure := clipboard_os_failure(.Write_Failed)
			poll_failure.bytes_done = bytes_done
			return bytes_done, false, poll_failure
		}
		if .OUT not_in poll_descriptor.revents {
			continue
		}
		chunk_bytes := min(cancellation_bytes, u64(len(frame)) - bytes_done)
		count := posix.write(
			session.output_fd,
			raw_data(frame[int(bytes_done):int(bytes_done + chunk_bytes)]),
			c.size_t(chunk_bytes),
		)
		if count < 0 {
			if posix.errno() == .EAGAIN || posix.errno() == .EWOULDBLOCK || posix.errno() == .EINTR {
				continue
			}
			write_failure := clipboard_os_failure(.Write_Failed)
			write_failure.bytes_done = bytes_done
			return bytes_done, false, write_failure
		}
		if count == 0 {
			return bytes_done, false, Clipboard_Failure_Context {
				code = .Write_Failed,
				bytes_done = bytes_done,
			}
		}
		bytes_done += u64(count)
	}
	return bytes_done, true, {}
}

@(private)
clipboard_transport_remaining_milliseconds :: proc(
	started: time.Tick,
	timeout_milliseconds: u32,
) -> (u32, bool) {
	elapsed_ns := time.duration_nanoseconds(time.tick_since(started))
	if elapsed_ns < 0 {
		return 0, false
	}
	elapsed_ms := u64(elapsed_ns) / 1_000_000
	if elapsed_ms >= u64(timeout_milliseconds) {
		return 0, false
	}
	return timeout_milliseconds - u32(elapsed_ms), true
}

@(private)
clipboard_os_failure :: proc(code: Clipboard_Failure_Code) -> Clipboard_Failure_Context {
	return Clipboard_Failure_Context{code = code, os_errno = i32(posix.errno())}
}
