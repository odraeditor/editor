// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package terminal_frontend

import "../interaction"
import "base:intrinsics"
import "core:c"
import "core:strings"
import "core:sys/linux"
import "core:sys/posix"
import "core:testing"

@(private)
TERMINAL_TEST_TIOCSWINSZ :: 0x5414

/* Verifies raw mode disables translations while preserving unrelated terminal state. */
@(test)
terminal_raw_mode_is_minimal_and_bounded :: proc(t: ^testing.T) {
	saved: posix.termios
	saved.c_iflag = {.BRKINT, .ICRNL, .INPCK, .ISTRIP, .IXON, .IXOFF}
	saved.c_oflag = {.OPOST, .ONLCR}
	saved.c_cflag = {.CREAD}
	saved.c_lflag = {.ECHO, .ICANON, .IEXTEN, .ISIG, .NOFLSH}
	raw := raw_attributes(saved)
	testing.expect(t, .BRKINT not_in raw.c_iflag)
	testing.expect(t, .ICRNL not_in raw.c_iflag)
	testing.expect(t, .INPCK not_in raw.c_iflag)
	testing.expect(t, .ISTRIP not_in raw.c_iflag)
	testing.expect(t, .IXON not_in raw.c_iflag)
	testing.expect(t, .IXOFF in raw.c_iflag)
	testing.expect(t, .OPOST not_in raw.c_oflag)
	testing.expect(t, .ONLCR in raw.c_oflag)
	testing.expect(t, .CS8 in raw.c_cflag)
	testing.expect(t, .CREAD in raw.c_cflag)
	testing.expect(t, .ECHO not_in raw.c_lflag)
	testing.expect(t, .ICANON not_in raw.c_lflag)
	testing.expect(t, .IEXTEN not_in raw.c_lflag)
	testing.expect(t, .ISIG not_in raw.c_lflag)
	testing.expect(t, .NOFLSH in raw.c_lflag)
	testing.expect_value(t, raw.c_cc[.VMIN], posix.cc_t(1))
	testing.expect_value(t, raw.c_cc[.VTIME], posix.cc_t(0))
}

/* Verifies zero, closed, and oversized calls fail before touching terminal state. */
@(test)
session_rejects_invalid_ownership_and_output :: proc(t: ^testing.T) {
	session: Session
	_, write_failure := session_write_all(&session, nil)
	testing.expect_value(t, write_failure.code, Failure_Code.Invalid_Session)
	_, flush_failure := session_flush(&session)
	testing.expect_value(t, flush_failure.code, Failure_Code.Invalid_Session)
	_, restore_failure := session_restore(&session)
	testing.expect_value(t, restore_failure.code, Failure_Code.Invalid_Session)
	oversized, allocation_error := make(
		[]u8,
		int(MAX_OUTPUT_BYTES) + 1,
		context.temp_allocator,
	)
	testing.expect(t, allocation_error == nil)
	if allocation_error != nil {
		return
	}
	defer delete(oversized, context.temp_allocator)
	session.acquired = true
	_, limit_failure := session_write_all(&session, oversized)
	testing.expect_value(t, limit_failure.code, Failure_Code.Output_Limit)
	testing.expect_value(t, limit_failure.limit, u64(MAX_OUTPUT_BYTES))
}

/* Verifies pointer decoding context requires one live reporting geometry. */
@(test)
session_pointer_context_requires_live_reporting :: proc(t: ^testing.T) {
	session: Session
	_, zero_ok := session_pointer_context(&session, interaction.Pointer_Root_Generation(1))
	session.acquired = true
	session.pointer_geometry_generation = 4
	_, disabled_ok := session_pointer_context(&session, interaction.Pointer_Root_Generation(1))
	session.pointer_reporting = true
	_, missing_root_ok := session_pointer_context(&session, interaction.Pointer_Root_Generation(0))
	ctx, context_ok := session_pointer_context(&session, interaction.Pointer_Root_Generation(7))

	testing.expect(t, !zero_ok && !disabled_ok && !missing_root_ok && context_ok)
	testing.expect_value(t, ctx.frontend, interaction.Pointer_Frontend_ID(1))
	testing.expect_value(t, ctx.source, interaction.Pointer_Source_ID(1))
	testing.expect_value(t, ctx.root_generation, interaction.Pointer_Root_Generation(7))
	testing.expect_value(t, ctx.geometry_generation, interaction.Pointer_Geometry_Generation(4))
	testing.expect(t, .Press in ctx.capabilities)
	testing.expect(t, .Release in ctx.capabilities)
	testing.expect(t, .Motion in ctx.capabilities)
	testing.expect(t, .Wheel in ctx.capabilities)
	testing.expect(t, .Modifiers in ctx.capabilities)
	testing.expect(t, .Cell_Coordinates in ctx.capabilities)
}

@(test)
/* Restores pointer mode, raw input, resize ownership, and repeated cleanup on one PTY. */
terminal_pointer_cleanup_restores_every_owned_resource :: proc(t: ^testing.T) {
	master, slave, opened := terminal_test_pty_open()
	testing.expect(t, opened)
	if !opened do return
	defer posix.close(master)
	defer posix.close(slave)
	session: Session
	acquired, acquire_failure := session_acquire(&session, slave, slave)
	testing.expectf(t, acquired, "terminal acquisition failed with %v", acquire_failure.code)
	if !acquired do return
	testing.expect(t, session.raw_mode && session.signal_owned && session.pointer_reporting)
	enabled: [len(POINTER_REPORTING_ENABLE)]u8
	enabled_read := terminal_test_read_exact(master, enabled[:])
	testing.expect(t, enabled_read)
	if enabled_read {
		testing.expect_value(t, string(enabled[:]), POINTER_REPORTING_ENABLE)
	}
	posix.raise(posix.Signal(posix.SIGWINCH))
	_, read_result, _ := session_read_byte(&session, 0)
	testing.expect_value(t, read_result, Read_Result.Resize)

	restored, restore_failure := session_restore(&session)
	testing.expectf(t, restored, "terminal restoration failed with %v", restore_failure.code)
	testing.expect(t, !session.acquired && session.restored)
	testing.expect(t, !session.raw_mode && !session.signal_owned && !session.pointer_reporting)
	testing.expect_value(t, intrinsics.atomic_load(&resize_signal_owned), u32(0))
	repeated, repeated_failure := session_restore(&session)
	testing.expect(t, repeated && repeated_failure.code == .None)

	disabled: [len(POINTER_REPORTING_DISABLE)]u8
	disabled_read := terminal_test_read_exact(master, disabled[:])
	testing.expect(t, disabled_read)
	if disabled_read {
		testing.expect_value(t, string(disabled[:]), POINTER_REPORTING_DISABLE)
	}
	visible: [len("\x1b[?25h\x1b[0m\r\n")]u8
	visible_read := terminal_test_read_exact(master, visible[:])
	testing.expect(t, visible_read)
	if visible_read {
		output := string(visible[:])
		testing.expect_value(t, output, "\x1b[?25h\x1b[0m\r\n")
		testing.expect(t, !strings.contains(output, "\x1b[?25h\x1b[0m\r\r\n"))
	}
}

@(test)
/* Releases internal pointer ownership even when the frontend descriptor is already lost. */
terminal_pointer_cleanup_contains_frontend_loss :: proc(t: ^testing.T) {
	session := Session {
		input_fd = -1,
		output_fd = -1,
		acquired = true,
		pointer_reporting = true,
	}
	restored, failure := session_restore(&session)
	testing.expect(t, !restored)
	testing.expect_value(t, failure.code, Failure_Code.Restoration_Failed)
	testing.expect(t, !session.acquired && session.restored)
	testing.expect(t, !session.raw_mode && !session.signal_owned && !session.pointer_reporting)
	repeated, repeated_failure := session_restore(&session)
	testing.expect(t, repeated && repeated_failure.code == .None)
}

@(test)
/* Keeps ordinary keyboard decoding available when pointer capability is absent. */
terminal_keyboard_input_survives_pointer_degradation :: proc(t: ^testing.T) {
	decoder: Decoder
	decoded := decoder_push(&decoder, 'x', {})
	testing.expect_value(t, decoded.status, Decode_Status.Event)
	testing.expect_value(t, decoded.input.kind, interaction.Input_Kind.Key)
	testing.expect_value(t, decoded.input.stroke.kind, interaction.Logical_Key_Kind.Unicode_Scalar)
	testing.expect_value(t, decoded.input.stroke.scalar, 'x')
	testing.expect_value(t, decoded.input.text, "x")
}

@(private)
terminal_test_pty_open :: proc() -> (master, slave: posix.FD, ok: bool) {
	master = posix.posix_openpt({.RDWR, .NOCTTY})
	if master < 0 do return -1, -1, false
	if posix.grantpt(master) != .OK || posix.unlockpt(master) != .OK {
		posix.close(master)
		return -1, -1, false
	}
	path := posix.ptsname(master)
	if path == nil {
		posix.close(master)
		return -1, -1, false
	}
	slave = posix.open(path, {.RDWR, .NOCTTY})
	if slave < 0 {
		posix.close(master)
		return -1, -1, false
	}
	window := Linux_Window_Size{rows = 24, columns = 80}
	if int(linux.ioctl(linux.Fd(slave), TERMINAL_TEST_TIOCSWINSZ, uintptr(rawptr(&window)))) < 0 {
		posix.close(slave)
		posix.close(master)
		return -1, -1, false
	}
	return master, slave, true
}

@(private)
terminal_test_read_exact :: proc(fd: posix.FD, destination: []u8) -> bool {
	offset: int
	for offset < len(destination) {
		poll_descriptor := posix.pollfd{fd = fd, events = {.IN}}
		poll_result := posix.poll(&poll_descriptor, 1, c.int(1000))
		if poll_result <= 0 || .ERR in poll_descriptor.revents ||
		   .HUP in poll_descriptor.revents || .NVAL in poll_descriptor.revents {
			return false
		}
		if .IN not_in poll_descriptor.revents do continue
		count := posix.read(
			fd,
			raw_data(destination[offset:]),
			c.size_t(int(len(destination)) - offset),
		)
		if count <= 0 do return false
		offset += int(count)
	}
	return true
}
