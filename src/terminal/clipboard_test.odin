// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package terminal_frontend

import "core:mem"
import "core:sys/posix"
import "core:testing"

@(private)
Fake_Mode :: enum u8 {
	Success,
	Failure,
	Timeout,
	Partial,
}

@(private)
Fake_Clipboard :: struct {
	write_mode:     Fake_Mode,
	read_mode:      Fake_Mode,
	write_storage:  [1024]u8,
	write_bytes:    int,
	read_storage:   [64]u8,
	read_bytes:     int,
	read_token:     Clipboard_Change_Token,
	close_called:   bool,
	close_failure:  bool,
}

@(private)
Cancel_State :: struct {
	checks:       int,
	cancel_after: int,
}

/* Verifies the admitted Herdr route exposes write without inventing clipboard read. */
@(test)
osc52_capabilities_follow_the_presentation_path :: proc(t: ^testing.T) {
	session := Session{acquired = true}
	admitted := clipboard_osc52_transport(
		&session,
		Clipboard_Environment{remote = true, herdr = true},
	)
	testing.expect(t, admitted.capabilities.write)
	testing.expect(t, !admitted.capabilities.read)
	testing.expect_value(t, admitted.capabilities.presentation, Clipboard_Presentation.Outer_Terminal_Client)

	nested := clipboard_osc52_transport(
		&session,
		Clipboard_Environment{remote = true, herdr = true, nested_tmux = true},
	)
	testing.expect(t, !nested.capabilities.write && !nested.capabilities.read)
	testing.expect_value(t, nested.capabilities.presentation, Clipboard_Presentation.Unavailable)
}

/* Verifies copied fake read/write values, tokens, framing, accounting, and teardown. */
@(test)
adapter_copies_complete_values_and_cleans_up :: proc(t: ^testing.T) {
	persistent_tracking: mem.Tracking_Allocator
	temporary_tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&persistent_tracking, context.allocator)
	mem.tracking_allocator_init(&temporary_tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&persistent_tracking)
	defer mem.tracking_allocator_destroy(&temporary_tracking)

	fake := fake_clipboard("external", Clipboard_Change_Token(41))
	adapter: Clipboard_Adapter
	config := clipboard_default_config(
		mem.tracking_allocator(&persistent_tracking),
		mem.tracking_allocator(&temporary_tracking),
	)
	initialized, init_failure := clipboard_adapter_init(
		&adapter,
		config,
		fake_transport(&fake, true, true),
	)
	testing.expect(t, initialized && init_failure.code == .None)
	if !initialized {
		return
	}

	written, write_ok, write_failure := clipboard_write(
		&adapter,
		Clipboard_Write_Request{text = "Odra"},
	)
	testing.expect(t, write_ok && write_failure.code == .None)
	testing.expect_value(t, written.token, Clipboard_Change_Token(1))
	testing.expect_value(t, written.bytes, u64(4))
	testing.expect_value(t, string(fake.write_storage[:fake.write_bytes]), "\x1b]52;c;T2RyYQ==\x07")

	read, read_ok, read_failure := clipboard_read(
		&adapter,
		Clipboard_Read_Request{result_allocator = mem.tracking_allocator(&persistent_tracking)},
	)
	testing.expect(t, read_ok && read_failure.code == .None)
	testing.expect_value(t, read.text, "external")
	testing.expect_value(t, read.token, Clipboard_Change_Token(41))
	fake.read_storage[0] = 'X'
	testing.expect_value(t, read.text, "external")
	clipboard_read_result_close(&read)

	stats, stats_ok, stats_failure := clipboard_stats(&adapter)
	testing.expect(t, stats_ok && stats_failure.code == .None)
	testing.expect_value(t, stats.completed_writes, u64(1))
	testing.expect_value(t, stats.completed_reads, u64(1))
	testing.expect_value(t, stats.next_token, Clipboard_Change_Token(2))
	testing.expect_value(t, stats.temporary_bytes, u64(0))
	testing.expect(t, stats.peak_temporary_bytes > 0)

	closed, close_failure := clipboard_adapter_close(&adapter)
	testing.expect(t, closed && close_failure.code == .None)
	testing.expect(t, fake.close_called)
	testing.expect_value(t, persistent_tracking.current_memory_allocated, i64(0))
	testing.expect_value(t, temporary_tracking.current_memory_allocated, i64(0))
}

/* Verifies read-only and write-only adapters expose only their admitted operation. */
@(test)
clipboard_adapter_preserves_capability_asymmetry :: proc(t: ^testing.T) {
	read_fake := fake_clipboard("external", Clipboard_Change_Token(7))
	read_adapter: Clipboard_Adapter
	read_initialized, _ := clipboard_adapter_init(
		&read_adapter,
		clipboard_default_config(),
		fake_transport(&read_fake, true, false),
	)
	testing.expect(t, read_initialized)
	if !read_initialized {
		return
	}
	_, write_ok, write_failure := clipboard_write(&read_adapter, Clipboard_Write_Request{text = "value"})
	testing.expect(t, !write_ok)
	testing.expect_value(t, write_failure.code, Clipboard_Failure_Code.Write_Unavailable)
	read, read_ok, read_failure := clipboard_read(
		&read_adapter,
		Clipboard_Read_Request{result_allocator = context.allocator},
	)
	testing.expect(t, read_ok && read_failure.code == .None)
	testing.expect_value(t, read.text, "external")
	clipboard_read_result_close(&read)
	read_closed, _ := clipboard_adapter_close(&read_adapter)
	testing.expect(t, read_closed && read_fake.close_called)

	write_fake := fake_clipboard("", Clipboard_Change_Token(1))
	write_adapter: Clipboard_Adapter
	write_initialized, _ := clipboard_adapter_init(
		&write_adapter,
		clipboard_default_config(),
		fake_transport(&write_fake, false, true),
	)
	testing.expect(t, write_initialized)
	if !write_initialized {
		return
	}
	written, write_only_ok, write_only_failure := clipboard_write(
		&write_adapter,
		Clipboard_Write_Request{text = "value"},
	)
	testing.expect(t, write_only_ok && write_only_failure.code == .None)
	testing.expect_value(t, written.bytes, u64(5))
	_, unavailable_ok, unavailable_failure := clipboard_read(
		&write_adapter,
		Clipboard_Read_Request{result_allocator = context.allocator},
	)
	testing.expect(t, !unavailable_ok)
	testing.expect_value(t, unavailable_failure.code, Clipboard_Failure_Code.Read_Unavailable)
	write_closed, _ := clipboard_adapter_close(&write_adapter)
	testing.expect(t, write_closed && write_fake.close_called)
}

/* Verifies malformed, oversized, cancelled, partial, and timed-out work is rejected. */
@(test)
adapter_rejects_bounded_request_failures :: proc(t: ^testing.T) {
	fake := fake_clipboard("external", Clipboard_Change_Token(9))
	adapter: Clipboard_Adapter
	initialized, _ := clipboard_adapter_init(
		&adapter,
		clipboard_default_config(),
		fake_transport(&fake, true, true),
	)
	testing.expect(t, initialized)
	if !initialized {
		return
	}

	_, empty_ok, empty_failure := clipboard_write(&adapter, Clipboard_Write_Request{text = ""})
	testing.expect(t, !empty_ok)
	testing.expect_value(t, empty_failure.code, Clipboard_Failure_Code.Empty_Text)
	invalid_bytes := [?]u8{0xff}
	invalid := transmute(string)invalid_bytes[:]
	_, invalid_ok, invalid_failure := clipboard_write(&adapter, Clipboard_Write_Request{text = invalid})
	testing.expect(t, !invalid_ok)
	testing.expect_value(t, invalid_failure.code, Clipboard_Failure_Code.Invalid_UTF8)
	oversized, allocation_error := make([]byte, int(MAX_CLIPBOARD_TEXT_BYTES) + 1, context.temp_allocator)
	testing.expect(t, allocation_error == nil)
	if allocation_error == nil {
		_, oversized_ok, oversized_failure := clipboard_write(
			&adapter,
			Clipboard_Write_Request{text = string(oversized)},
		)
		testing.expect(t, !oversized_ok)
		testing.expect_value(t, oversized_failure.code, Clipboard_Failure_Code.Text_Limit)
		delete(oversized, context.temp_allocator)
	}

	cancel := Cancel_State{cancel_after = 3}
	_, cancelled_ok, cancelled_failure := clipboard_write(
		&adapter,
		Clipboard_Write_Request {
			text = "cancel",
			cancellation = Clipboard_Cancellation {
				user_data = rawptr(&cancel),
				check = fake_cancel_check,
			},
		},
	)
	testing.expect(t, !cancelled_ok)
	testing.expect_value(t, cancelled_failure.code, Clipboard_Failure_Code.Cancelled)

	fake.write_mode = .Partial
	_, partial_ok, partial_failure := clipboard_write(&adapter, Clipboard_Write_Request{text = "partial"})
	testing.expect(t, !partial_ok)
	testing.expect_value(t, partial_failure.code, Clipboard_Failure_Code.Partial_Response)
	fake.write_mode = .Timeout
	_, timeout_ok, timeout_failure := clipboard_write(&adapter, Clipboard_Write_Request{text = "timeout"})
	testing.expect(t, !timeout_ok)
	testing.expect_value(t, timeout_failure.code, Clipboard_Failure_Code.Timed_Out)

	fake.read_mode = .Partial
	_, partial_read_ok, partial_read_failure := clipboard_read(
		&adapter,
		Clipboard_Read_Request{result_allocator = context.allocator},
	)
	testing.expect(t, !partial_read_ok)
	testing.expect_value(t, partial_read_failure.code, Clipboard_Failure_Code.Partial_Response)
	fake.read_mode = .Timeout
	_, timeout_read_ok, timeout_read_failure := clipboard_read(
		&adapter,
		Clipboard_Read_Request{result_allocator = context.allocator},
	)
	testing.expect(t, !timeout_read_ok)
	testing.expect_value(t, timeout_read_failure.code, Clipboard_Failure_Code.Timed_Out)

	read_cancel := Cancel_State{cancel_after = 1}
	_, cancelled_read_ok, cancelled_read_failure := clipboard_read(
		&adapter,
		Clipboard_Read_Request {
			result_allocator = context.allocator,
			cancellation = Clipboard_Cancellation {
				user_data = rawptr(&read_cancel),
				check = fake_cancel_check,
			},
		},
	)
	testing.expect(t, !cancelled_read_ok)
	testing.expect_value(t, cancelled_read_failure.code, Clipboard_Failure_Code.Cancelled)

	stats, stats_ok, _ := clipboard_stats(&adapter)
	testing.expect(t, stats_ok)
	testing.expect_value(t, stats.completed_writes, u64(0))
	testing.expect_value(t, stats.completed_reads, u64(0))
	testing.expect_value(t, stats.temporary_bytes, u64(0))
	closed, _ := clipboard_adapter_close(&adapter)
	testing.expect(t, closed)
}

/* Verifies malformed and oversized physical reads never escape as copied values. */
@(test)
adapter_rejects_invalid_external_values :: proc(t: ^testing.T) {
	fake := fake_clipboard("external", Clipboard_Change_Token(15))
	config := clipboard_default_config()
	config.max_text_bytes = 4
	adapter: Clipboard_Adapter
	initialized, _ := clipboard_adapter_init(
		&adapter,
		config,
		fake_transport(&fake, true, false),
	)
	testing.expect(t, initialized)
	if !initialized {
		return
	}

	_, oversized_ok, oversized_failure := clipboard_read(
		&adapter,
		Clipboard_Read_Request{result_allocator = context.allocator},
	)
	testing.expect(t, !oversized_ok)
	testing.expect_value(t, oversized_failure.code, Clipboard_Failure_Code.Text_Limit)

	fake.read_storage[0] = 0xff
	fake.read_bytes = 1
	_, invalid_ok, invalid_failure := clipboard_read(
		&adapter,
		Clipboard_Read_Request{result_allocator = context.allocator},
	)
	testing.expect(t, !invalid_ok)
	testing.expect_value(t, invalid_failure.code, Clipboard_Failure_Code.Invalid_UTF8)

	stats, stats_ok, _ := clipboard_stats(&adapter)
	testing.expect(t, stats_ok)
	testing.expect_value(t, stats.completed_reads, u64(0))
	closed, _ := clipboard_adapter_close(&adapter)
	testing.expect(t, closed)
}

/* Verifies failed transport teardown preserves ownership for one checked retry. */
@(test)
adapter_contains_transport_close_failure :: proc(t: ^testing.T) {
	fake := fake_clipboard("", Clipboard_Change_Token(1))
	fake.close_failure = true
	adapter: Clipboard_Adapter
	initialized, _ := clipboard_adapter_init(
		&adapter,
		clipboard_default_config(),
		fake_transport(&fake, false, true),
	)
	testing.expect(t, initialized)
	if !initialized {
		return
	}
	closed, close_failure := clipboard_adapter_close(&adapter)
	testing.expect(t, !closed)
	testing.expect_value(t, close_failure.code, Clipboard_Failure_Code.Transport_Restore_Failed)
	_, stats_ok, _ := clipboard_stats(&adapter)
	testing.expect(t, stats_ok)
	fake.close_failure = false
	retried, retry_failure := clipboard_adapter_close(&adapter)
	testing.expect(t, retried && retry_failure.code == .None)
}

/* Verifies the POSIX transport writes one frame and restores descriptor flags. */
@(test)
osc52_transport_writes_one_bounded_frame :: proc(t: ^testing.T) {
	fds: [2]posix.FD
	pipe_result := posix.pipe(&fds)
	testing.expect(t, pipe_result == .OK)
	if pipe_result != .OK {
		return
	}
	defer posix.close(fds[0])
	defer posix.close(fds[1])
	initial_flags := posix.fcntl(fds[1], .GETFL, 0)
	session := Session{output_fd = fds[1], acquired = true}
	adapter: Clipboard_Adapter
	initialized, _ := clipboard_adapter_init(
		&adapter,
		clipboard_default_config(),
		clipboard_osc52_transport(
			&session,
			Clipboard_Environment{remote = true, herdr = true},
		),
	)
	testing.expect(t, initialized)
	if !initialized {
		return
	}
	written, write_ok, write_failure := clipboard_write(
		&adapter,
		Clipboard_Write_Request{text = "physical"},
	)
	testing.expect(t, write_ok && write_failure.code == .None)
	testing.expect_value(t, written.bytes, u64(8))
	buffer: [128]u8
	read_count := posix.read(fds[0], raw_data(buffer[:]), len(buffer))
	testing.expect(t, read_count > 0)
	if read_count > 0 {
		testing.expect_value(t, string(buffer[:read_count]), "\x1b]52;c;cGh5c2ljYWw=\x07")
	}
	final_flags := posix.fcntl(fds[1], .GETFL, 0)
	testing.expect_value(t, final_flags, initial_flags)
	closed, _ := clipboard_adapter_close(&adapter)
	testing.expect(t, closed)
	session.acquired = false
}

@(private)
fake_clipboard :: proc(text: string, token: Clipboard_Change_Token) -> Fake_Clipboard {
	fake: Fake_Clipboard
	copy(fake.read_storage[:], text)
	fake.read_bytes = len(text)
	fake.read_token = token
	return fake
}

@(private)
fake_transport :: proc(fake: ^Fake_Clipboard, read, write: bool) -> Clipboard_Transport {
	presentation := Clipboard_Presentation.Unavailable
	if read || write {
		presentation = .Outer_Terminal_Client
	}
	return Clipboard_Transport {
		user_data = rawptr(fake),
		capabilities = Clipboard_Capabilities {
			read = read,
			write = write,
			presentation = presentation,
		},
		write = write ? fake_clipboard_write : nil,
		read = read ? fake_clipboard_read : nil,
		close = fake_clipboard_close,
	}
}

@(private)
fake_clipboard_write :: proc "odin" (
	user_data: rawptr,
	frame: []u8,
	_: u32,
	_: u64,
	_: Clipboard_Cancellation,
) -> (u64, bool, Clipboard_Failure_Context) {
	fake := (^Fake_Clipboard)(user_data)
	switch fake.write_mode {
	case .Failure:
		return 0, false, Clipboard_Failure_Context{code = .Write_Failed}
	case .Timeout:
		return 0, false, Clipboard_Failure_Context{code = .Timed_Out}
	case .Partial:
		return u64(len(frame) - 1), true, {}
	case .Success:
		if len(frame) > len(fake.write_storage) {
			return 0, false, Clipboard_Failure_Context{code = .Write_Failed}
		}
		copy(fake.write_storage[:], frame)
		fake.write_bytes = len(frame)
		return u64(len(frame)), true, {}
	}
	unreachable()
}

@(private)
fake_clipboard_read :: proc "odin" (
	user_data: rawptr,
	_: u32,
	_: Clipboard_Cancellation,
) -> (Clipboard_Transport_Read, bool, Clipboard_Failure_Context) {
	fake := (^Fake_Clipboard)(user_data)
	switch fake.read_mode {
	case .Failure:
		return {}, false, Clipboard_Failure_Context{code = .Read_Failed}
	case .Timeout:
		return {}, false, Clipboard_Failure_Context{code = .Timed_Out}
	case .Partial:
		return Clipboard_Transport_Read {
			text = fake.read_storage[:fake.read_bytes],
			token = fake.read_token,
			reported_bytes = u64(fake.read_bytes + 1),
			complete = false,
		}, true, {}
	case .Success:
		return Clipboard_Transport_Read {
			text = fake.read_storage[:fake.read_bytes],
			token = fake.read_token,
			reported_bytes = u64(fake.read_bytes),
			complete = true,
		}, true, {}
	}
	unreachable()
}

@(private)
fake_clipboard_close :: proc "odin" (user_data: rawptr) -> (bool, Clipboard_Failure_Context) {
	fake := (^Fake_Clipboard)(user_data)
	fake.close_called = true
	if fake.close_failure {
		return false, Clipboard_Failure_Context{code = .Transport_Restore_Failed}
	}
	return true, {}
}

@(private)
fake_cancel_check :: proc "odin" (user_data: rawptr) -> bool {
	state := (^Cancel_State)(user_data)
	state.checks += 1
	return state.checks >= state.cancel_after
}
