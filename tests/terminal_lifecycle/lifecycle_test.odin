// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package terminal_lifecycle_tests

import terminal "../../src/terminal"
import "core:c"
import "core:sys/linux"
import "core:sys/posix"
import "core:testing"

@(private)
TIOCSWINSZ :: u32(0x5414)

@(private)
Window_Size :: struct {
	rows:     u16,
	columns:  u16,
	x_pixels: u16,
	y_pixels: u16,
}

/* Verifies real PTY acquisition, raw mode, resize, bounded output, and restoration. */
@(test)
terminal_session_restores_a_real_pseudo_terminal :: proc(t: ^testing.T) {
	master := posix.posix_openpt({.RDWR, .NOCTTY})
	testing.expect(t, master != posix.FD(-1))
	if master == posix.FD(-1) {
		return
	}
	defer posix.close(master)
	granted := posix.grantpt(master) == .OK
	unlocked := posix.unlockpt(master) == .OK
	testing.expect(t, granted && unlocked)
	if !granted || !unlocked {
		return
	}
	name := posix.ptsname(master)
	testing.expect(t, name != nil)
	if name == nil {
		return
	}
	slave := posix.open(name, {.RDWR, .NOCTTY})
	testing.expect(t, slave != posix.FD(-1))
	if slave == posix.FD(-1) {
		return
	}
	defer posix.close(slave)
	initial_window := Window_Size{rows = 24, columns = 80}
	set_result := linux.ioctl(linux.Fd(slave), TIOCSWINSZ, uintptr(rawptr(&initial_window)))
	testing.expect(t, int(set_result) >= 0)
	saved: posix.termios
	testing.expect(t, posix.tcgetattr(slave, &saved) == .OK)

	session: terminal.Session
	acquired, acquisition_failure := terminal.session_acquire(&session, slave, slave)
	testing.expectf(t, acquired, "acquisition failed with %v errno=%d", acquisition_failure.code, acquisition_failure.os_errno)
	if !acquired {
		return
	}
	enabled: [16]u8
	testing.expect(t, terminal_lifecycle_read_exact(master, enabled[:]))
	testing.expect_value(t, string(enabled[:]), "\x1b[?1002h\x1b[?1006h")
	restored := false
	defer {
		if !restored && terminal.session_is_live(&session) {
			terminal.session_restore(&session)
		}
	}
	geometry, changed, geometry_ok, _ := terminal.session_geometry(&session)
	testing.expect(t, geometry_ok && !changed)
	testing.expect_value(t, geometry, terminal.Geometry{width_cells = 80, height_rows = 24})
	current: posix.termios
	testing.expect(t, posix.tcgetattr(slave, &current) == .OK)
	testing.expect(t, .ICANON not_in current.c_lflag)
	testing.expect(t, .ECHO not_in current.c_lflag)

	payload := [?]u8{'o', 'd', 'r', 'a'}
	written, write_failure := terminal.session_write_all(&session, payload[:])
	testing.expectf(t, written, "write failed with %v", write_failure.code)
	received: [4]u8
	count := posix.read(master, raw_data(received[:]), c.size_t(len(received)))
	testing.expect_value(t, count, c.ssize_t(4))
	testing.expect_value(t, received, [4]u8{'o', 'd', 'r', 'a'})

	resized_window := Window_Size{rows = 50, columns = 160}
	resize_result := linux.ioctl(linux.Fd(slave), TIOCSWINSZ, uintptr(rawptr(&resized_window)))
	testing.expect(t, int(resize_result) >= 0)
	testing.expect(t, posix.kill(posix.getpid(), posix.Signal(posix.SIGWINCH)) == .OK)
	resized, resize_changed, resize_ok, _ := terminal.session_geometry(&session)
	testing.expect(t, resize_ok && resize_changed)
	testing.expect_value(t, resized, terminal.Geometry{width_cells = 160, height_rows = 50})

	restore_ok, restore_failure := terminal.session_restore(&session)
	testing.expectf(t, restore_ok, "restore failed with %v errno=%d", restore_failure.code, restore_failure.os_errno)
	restored = restore_ok
	disabled: [16]u8
	testing.expect(t, terminal_lifecycle_read_exact(master, disabled[:]))
	testing.expect_value(t, string(disabled[:]), "\x1b[?1002l\x1b[?1006l")
	after: posix.termios
	testing.expect(t, posix.tcgetattr(slave, &after) == .OK)
	testing.expect_value(t, after, saved)
	second_restored, second_restore_failure := terminal.session_restore(&session)
	testing.expect(t, second_restored)
	testing.expect_value(t, second_restore_failure.code, terminal.Failure_Code.None)

	terminal_session_reports_eof_and_consumes_failed_restoration(t)
}

@(private)
terminal_session_reports_eof_and_consumes_failed_restoration :: proc(t: ^testing.T) {
	master := posix.posix_openpt({.RDWR, .NOCTTY})
	testing.expect(t, master != posix.FD(-1))
	if master == posix.FD(-1) {
		return
	}
	master_open := true
	defer {
		if master_open {
			posix.close(master)
		}
	}
	granted := posix.grantpt(master) == .OK
	unlocked := posix.unlockpt(master) == .OK
	testing.expect(t, granted && unlocked)
	if !granted || !unlocked {
		return
	}
	name := posix.ptsname(master)
	testing.expect(t, name != nil)
	if name == nil {
		return
	}
	slave := posix.open(name, {.RDWR, .NOCTTY})
	testing.expect(t, slave != posix.FD(-1))
	if slave == posix.FD(-1) {
		return
	}
	defer posix.close(slave)
	window := Window_Size{rows = 24, columns = 80}
	set_result := linux.ioctl(linux.Fd(slave), TIOCSWINSZ, uintptr(rawptr(&window)))
	testing.expect(t, int(set_result) >= 0)

	session: terminal.Session
	acquired, acquisition_failure := terminal.session_acquire(&session, slave, slave)
	testing.expectf(t, acquired, "acquisition failed with %v", acquisition_failure.code)
	if !acquired {
		return
	}
	posix.close(master)
	master_open = false
	_, result, read_failure := terminal.session_read_byte(&session)
	testing.expect_value(t, result, terminal.Read_Result.Failure)
	testing.expect_value(t, read_failure.code, terminal.Failure_Code.Read_Failed)
	restored, restore_failure := terminal.session_restore(&session)
	testing.expect(t, !restored)
	testing.expect_value(t, restore_failure.code, terminal.Failure_Code.Restoration_Failed)
	testing.expect(t, !terminal.session_is_live(&session))
}

@(private)
terminal_lifecycle_read_exact :: proc(fd: posix.FD, destination: []u8) -> bool {
	offset: int
	for offset < len(destination) {
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
