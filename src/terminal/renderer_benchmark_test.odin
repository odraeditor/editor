// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package terminal_frontend

import "../display"
import editor_view "../view"
import "core:fmt"
import "core:mem"
import "core:slice"
import "core:testing"
import "core:time"

@(private)
TERMINAL_BENCHMARK_ENABLED :: #config(ODRA_TERMINAL_BENCHMARK, false)
@(private)
TERMINAL_BENCHMARK_WARMUP :: 16
@(private)
TERMINAL_BENCHMARK_SAMPLES :: 128
@(private)
TERMINAL_OUTPUT_P99_GATE_NS :: i64(4_000_000)

/* Measures full terminal-output construction for ordinary and Unicode-heavy grids. */
@(test)
terminal_output_construction_meets_p99_gate :: proc(t: ^testing.T) {
	if !TERMINAL_BENCHMARK_ENABLED {
		return
	}
	benchmark_terminal_output(t, 111, "ascii-240x80", "abcdefghijklmnopqrstuvwxyz")
	benchmark_terminal_output(t, 113, "unicode-240x80", "café e\u0301 界 👩\u200D💻 ")
}

@(private)
benchmark_terminal_output :: proc(t: ^testing.T, id: u64, name, pattern: string) {
	text := terminal_benchmark_text(pattern, 64 * 1024)
	defer delete(text)
	fixture: Renderer_Fixture
	ready := renderer_fixture_init(t, &fixture, id, string(text))
	if !ready {
		return
	}
	defer renderer_fixture_close(&fixture)
	logical, _, _ := editor_view.snapshot(&fixture.registry, fixture.handle)
	constraints := display.Viewport_Constraints{width_cells = 240, height_rows = 80}
	snapshot, projected, projection_failure := display.project(
		&fixture.buffer,
		renderer_projection_request(id, logical, constraints),
	)
	testing.expectf(t, projected, "projection failed with %v", projection_failure.code)
	if !projected {
		return
	}
	defer display.snapshot_close(&snapshot)
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	config := renderer_config(constraints)
	config.allocator = mem.tracking_allocator(&tracking)
	renderer: Renderer
	initialized, init_failure := renderer_init(&renderer, config)
	testing.expectf(t, initialized, "renderer failed with %v", init_failure.code)
	if !initialized {
		return
	}
	ui_root: Text_UI_Test_Root
	if !text_ui_test_root_init(
		t, &ui_root, &fixture, &renderer, snapshot, logical, constraints,
	) {
		renderer_close(&renderer)
		return
	}
	defer text_ui_test_root_close(&ui_root)
	presentation := text_ui_test_root_presentation(&ui_root)
	latencies: [TERMINAL_BENCHMARK_SAMPLES]i64
	for operation_index in 0 ..< TERMINAL_BENCHMARK_WARMUP + TERMINAL_BENCHMARK_SAMPLES {
		started := time.tick_now()
		frame, prepared, prepare_failure := renderer_prepare_ui(
			renderer_state(&renderer),
			presentation,
		)
		elapsed_ns := time.duration_nanoseconds(time.tick_since(started))
		testing.expectf(t, prepared, "frame failed with %v", prepare_failure.code)
		if !prepared {
			renderer_close(&renderer)
			return
		}
		frame_close(&frame)
		if operation_index >= TERMINAL_BENCHMARK_WARMUP {
			latencies[operation_index - TERMINAL_BENCHMARK_WARMUP] = elapsed_ns
		}
	}
	slice.sort(latencies[:])
	p99_ns := terminal_benchmark_percentile(latencies[:], 99)
	peak_bytes := tracking.peak_memory_allocated
	renderer_close(&renderer)
	cleanup_passed := tracking.current_memory_allocated == 0
	latency_passed := p99_ns <= TERMINAL_OUTPUT_P99_GATE_NS
	fmt.printf(
		"benchmark=terminal-output case=%s warmup=%d samples=%d p50_ns=%d p95_ns=%d p99_ns=%d max_ns=%d gate_p99_ns=%d peak_bytes=%d live_bytes=%d latency_passed=%t cleanup_passed=%t\n",
		name,
		TERMINAL_BENCHMARK_WARMUP,
		TERMINAL_BENCHMARK_SAMPLES,
		terminal_benchmark_percentile(latencies[:], 50),
		terminal_benchmark_percentile(latencies[:], 95),
		p99_ns,
		latencies[TERMINAL_BENCHMARK_SAMPLES - 1],
		TERMINAL_OUTPUT_P99_GATE_NS,
		peak_bytes,
		tracking.current_memory_allocated,
		latency_passed,
		cleanup_passed,
	)
	testing.expect(t, latency_passed)
	testing.expect(t, cleanup_passed)
}

@(private)
terminal_benchmark_text :: proc(pattern: string, target_bytes: int) -> []u8 {
	line_pattern_bytes := len(pattern) * 8
	line_bytes := line_pattern_bytes + 1
	line_count := target_bytes / line_bytes
	text := make([]u8, line_count * line_bytes)
	for line_index in 0 ..< line_count {
		start := line_index * line_bytes
		for pattern_index in 0 ..< 8 {
			copy(text[start + pattern_index * len(pattern):], pattern)
		}
		text[start + line_pattern_bytes] = '\n'
	}
	return text
}

@(private)
terminal_benchmark_percentile :: proc(sorted_values: []i64, percentile: int) -> i64 {
	assert(len(sorted_values) > 0)
	assert(percentile > 0 && percentile <= 100)
	rank := (len(sorted_values) * percentile + 99) / 100
	return sorted_values[rank - 1]
}
