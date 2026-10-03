// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../display"
import terminal "../terminal"
import "core:c"
import "core:fmt"
import "core:mem"
import "core:slice"
import "core:sys/linux"
import "core:sys/posix"
import "core:testing"
import "core:time"

@(private)
ODRA_TERMINAL_BENCHMARK_ENABLED :: #config(ODRA_TERMINAL_BENCHMARK, false)
@(private)
ODRA_TERMINAL_BENCHMARK_WARMUP :: 16
@(private)
ODRA_TERMINAL_BENCHMARK_SAMPLES :: 128
@(private)
ORDINARY_EVENT_P99_GATE_NS :: i64(16_000_000)
@(private)
RESIZE_P99_GATE_NS :: i64(33_000_000)
@(private)
TERMINAL_BENCHMARK_TEXT :: "Odra terminal benchmark\nUnicode: cafe \U0001F642\n"

@(private)
BENCHMARK_TIOCSWINSZ :: u32(0x5414)

@(private)
Benchmark_Window_Size :: struct {
	rows:     u16,
	columns:  u16,
	x_pixels: u16,
	y_pixels: u16,
}

/* Measures normalized navigation, insertion, and resize through a real PTY flush. */
@(test)
terminal_interaction_meets_end_to_end_p99_gates :: proc(t: ^testing.T) {
	if !ODRA_TERMINAL_BENCHMARK_ENABLED {
		return
	}
	fixture: Interaction_Fixture
	ready := interaction_fixture_init(t, &fixture, TERMINAL_BENCHMARK_TEXT)
	if !ready {
		return
	}
	defer interaction_fixture_close(&fixture)
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
	window := Benchmark_Window_Size{rows = 24, columns = 80}
	testing.expect(t, int(linux.ioctl(linux.Fd(slave), BENCHMARK_TIOCSWINSZ, uintptr(rawptr(&window)))) >= 0)
	session: terminal.Session
	acquired, acquisition_failure := terminal.session_acquire(&session, slave, slave)
	testing.expectf(t, acquired, "acquisition failed with %v", acquisition_failure.code)
	if !acquired {
		return
	}
	defer {
		if terminal.session_is_live(&session) {
			terminal.session_restore(&session)
			terminal_benchmark_drain(master)
		}
	}
	constraints := display.Viewport_Constraints{width_cells = 80, height_rows = 24}
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	renderer: terminal.Renderer
	renderer_ready, renderer_failure := terminal.renderer_init(
		&renderer,
		terminal.Renderer_Config {
			constraints = constraints,
			profile = display.terminal_unicode17_profile(),
			max_output_bytes = terminal.MAX_OUTPUT_BYTES,
			allocator = mem.tracking_allocator(&tracking),
		},
	)
	testing.expectf(t, renderer_ready, "renderer failed with %v", renderer_failure.code)
	if !renderer_ready {
		return
	}
	next_snapshot_id := u64(10_000)
	initial_failure := present_current_view(
		&fixture.buffer,
		&fixture.registry,
		fixture.handle,
		&session,
		&renderer,
		constraints,
		&next_snapshot_id,
	)
	testing.expectf(
		t,
		initial_failure.stage == .None,
		"initial presentation failed at %v with UI %v/%v",
		initial_failure.stage,
		initial_failure.ui.operation,
		initial_failure.ui.code,
	)
	if initial_failure.stage != .None {
		terminal.renderer_close(&renderer)
		return
	}
	terminal_benchmark_drain(master)
	navigation_ok := benchmark_terminal_events(
		t,
		"navigation",
		&fixture,
		&session,
		master,
		&renderer,
		constraints,
		&next_snapshot_id,
		false,
	)
	insertion_ok := benchmark_terminal_events(
		t,
		"utf8-insertion",
		&fixture,
		&session,
		master,
		&renderer,
		constraints,
		&next_snapshot_id,
		true,
	)
	resize_ok := benchmark_terminal_resize(
		t,
		&fixture,
		&session,
		master,
		&renderer,
		&next_snapshot_id,
	)
	terminal.renderer_close(&renderer)
	cleanup_passed := tracking.current_memory_allocated == 0
	fmt.printf(
		"benchmark=terminal-end-to-end cleanup_peak_bytes=%d cleanup_live_bytes=%d cleanup_passed=%t\n",
		tracking.peak_memory_allocated,
		tracking.current_memory_allocated,
		cleanup_passed,
	)
	testing.expect(t, navigation_ok && insertion_ok && resize_ok && cleanup_passed)
}

@(private)
benchmark_terminal_events :: proc(
	t: ^testing.T,
	name: string,
	fixture: ^Interaction_Fixture,
	session: ^terminal.Session,
	master: posix.FD,
	renderer: ^terminal.Renderer,
	constraints: display.Viewport_Constraints,
	next_snapshot_id: ^u64,
	insertion: bool,
) -> bool {
	latencies: [ODRA_TERMINAL_BENCHMARK_SAMPLES]i64
	decoder: terminal.Decoder
	for operation_index in 0 ..< ODRA_TERMINAL_BENCHMARK_WARMUP + ODRA_TERMINAL_BENCHMARK_SAMPLES {
		physical := "\x1b[C"
		if insertion {
			physical = "é"
		} else if operation_index % 2 == 1 {
			physical = "\x1b[D"
		}
		started := time.tick_now()
		decoded: terminal.Decode_Output
		for value in transmute([]u8)physical {
			decoded = terminal.decoder_push(&decoder, value)
		}
		testing.expect_value(t, decoded.status, terminal.Decode_Status.Event)
		if decoded.status != .Event {
			return false
		}
		dispatched, dispatch_failure := dispatch_input(
			&fixture.commands,
			&fixture.buffer,
			&fixture.registry,
			fixture.handle,
			decoded.input,
			constraints,
		)
		failure := dispatch_failure
		if failure.stage == .None && dispatched.changed {
			failure = present_current_view(
				&fixture.buffer,
				&fixture.registry,
				fixture.handle,
				session,
				renderer,
				constraints,
				next_snapshot_id,
			)
		}
		elapsed_ns := time.duration_nanoseconds(time.tick_since(started))
		testing.expect_value(t, failure.stage, App_Stage.None)
		testing.expect(t, dispatched.changed)
		if failure.stage != .None || !dispatched.changed {
			return false
		}
		terminal_benchmark_drain(master)
		if operation_index >= ODRA_TERMINAL_BENCHMARK_WARMUP {
			latencies[operation_index - ODRA_TERMINAL_BENCHMARK_WARMUP] = elapsed_ns
		}
	}
	return report_terminal_latency(name, latencies[:], ORDINARY_EVENT_P99_GATE_NS)
}

@(private)
benchmark_terminal_resize :: proc(
	t: ^testing.T,
	fixture: ^Interaction_Fixture,
	session: ^terminal.Session,
	master: posix.FD,
	renderer: ^terminal.Renderer,
	next_snapshot_id: ^u64,
) -> bool {
	latencies: [ODRA_TERMINAL_BENCHMARK_SAMPLES]i64
	for operation_index in 0 ..< ODRA_TERMINAL_BENCHMARK_WARMUP + ODRA_TERMINAL_BENCHMARK_SAMPLES {
		constraints := display.Viewport_Constraints{width_cells = 80, height_rows = 24}
		if operation_index % 2 == 1 {
			constraints = display.Viewport_Constraints{width_cells = 100, height_rows = 30}
		}
		started := time.tick_now()
		resized, resize_failure := terminal.renderer_resize(renderer, constraints)
		failure: App_Failure
		if !resized {
			failure = App_Failure{stage = .Resize, terminal = resize_failure}
		} else {
			failure = present_current_view(
				&fixture.buffer,
				&fixture.registry,
				fixture.handle,
				session,
				renderer,
				constraints,
				next_snapshot_id,
			)
		}
		elapsed_ns := time.duration_nanoseconds(time.tick_since(started))
		testing.expect_value(t, failure.stage, App_Stage.None)
		if failure.stage != .None {
			return false
		}
		terminal_benchmark_drain(master)
		if operation_index >= ODRA_TERMINAL_BENCHMARK_WARMUP {
			latencies[operation_index - ODRA_TERMINAL_BENCHMARK_WARMUP] = elapsed_ns
		}
	}
	return report_terminal_latency("resize-full-redraw", latencies[:], RESIZE_P99_GATE_NS)
}

@(private)
report_terminal_latency :: proc(name: string, latencies: []i64, gate_ns: i64) -> bool {
	slice.sort(latencies)
	p99_ns := odra_terminal_benchmark_percentile(latencies, 99)
	passed := p99_ns <= gate_ns
	fmt.printf(
		"benchmark=terminal-end-to-end case=%s warmup=%d samples=%d p50_ns=%d p95_ns=%d p99_ns=%d max_ns=%d gate_p99_ns=%d latency_passed=%t\n",
		name,
		ODRA_TERMINAL_BENCHMARK_WARMUP,
		ODRA_TERMINAL_BENCHMARK_SAMPLES,
		odra_terminal_benchmark_percentile(latencies, 50),
		odra_terminal_benchmark_percentile(latencies, 95),
		p99_ns,
		latencies[len(latencies) - 1],
		gate_ns,
		passed,
	)
	return passed
}

@(private)
terminal_benchmark_drain :: proc(master: posix.FD) {
	bytes: [64 * 1024]u8
	count := posix.read(master, raw_data(bytes[:]), c.size_t(len(bytes)))
	assert(count > 0)
}

@(private)
odra_terminal_benchmark_percentile :: proc(sorted_values: []i64, percentile: int) -> i64 {
	assert(len(sorted_values) > 0)
	assert(percentile > 0 && percentile <= 100)
	rank := (len(sorted_values) * percentile + 99) / 100
	return sorted_values[rank - 1]
}
