// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../../src/display"
import "../../src/editor"
import "../../src/view"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:slice"
import "core:time"

WARMUP_COUNT :: 16
SAMPLE_COUNT :: 128
LAYOUT_MAPPING_P99_GATE_NS :: i64(8_000_000)

Scenario :: struct {
	name:       string,
	text:       string,
	constraints: display.Viewport_Constraints,
	horizontal: u32,
	cache:      bool,
}

main :: proc() {
	ascii_80 := ascii_grid(80, 24)
	defer delete(ascii_80)
	big_ascii := ascii_grid(240, 80)
	defer delete(big_ascii)
	unicode := repeated_text("Odra e\u0301 界 👩\u200D💻\tPolski\n", 64 * 1_024)
	defer delete(unicode)
	long_line := repeated_text("x", 20_000)
	defer delete(long_line)
	scenarios := [?]Scenario{
		{name = "ascii-80x24", text = string(ascii_80), constraints = {width_cells = 80, height_rows = 24}},
		{name = "ascii-160x50", text = string(big_ascii), constraints = {width_cells = 160, height_rows = 50}},
		{name = "ascii-240x80", text = string(big_ascii), constraints = {width_cells = 240, height_rows = 80}},
		{name = "unicode-240x80", text = string(unicode), constraints = {width_cells = 240, height_rows = 80}},
		{name = "long-line-cold", text = string(long_line), constraints = {width_cells = 240, height_rows = 1}, horizontal = 8_000},
		{name = "long-line-warm-cache", text = string(long_line), constraints = {width_cells = 240, height_rows = 1}, horizontal = 8_000, cache = true},
	}
	passed := true
	for scenario, scenario_index in scenarios {
		if !run_scenario(scenario, u64(scenario_index + 1)) {
			passed = false
		}
	}
	if !passed {
		os.exit(1)
	}
}

run_scenario :: proc(scenario: Scenario, identity: u64) -> bool {
	buffer: editor.Buffer
	buffer_ok, buffer_failure := editor.buffer_init(
		&buffer,
		editor.Buffer_ID(400 + identity),
		scenario.text,
		editor.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	if !buffer_ok {
		fmt.eprintf("benchmark=display-projection case=%s buffer_failure=%v\n", scenario.name, buffer_failure.code)
		return false
	}
	registry: view.Registry
	registry_ok, registry_failure := view.registry_init(
		&registry,
		view.Registry_ID(u32(400 + identity)),
		context.allocator,
	)
	if !registry_ok {
		fmt.eprintf("benchmark=display-projection case=%s registry_failure=%v\n", scenario.name, registry_failure.code)
		editor.buffer_close(&buffer)
		return false
	}
	handle, view_ok, view_failure := view.create(&registry, &buffer)
	if !view_ok {
		fmt.eprintf("benchmark=display-projection case=%s view_failure=%v\n", scenario.name, view_failure.code)
		view.registry_close(&registry)
		editor.buffer_close(&buffer)
		return false
	}
	origin, _, _ := editor.buffer_position(&buffer, editor.Byte_Offset(0))
	seed_horizontal := scenario.horizontal
	if scenario.cache && seed_horizontal > 100 {
		seed_horizontal -= 100
	}
	viewport_ok, _ := view.set_viewport(&registry, handle, origin, seed_horizontal)
	if !viewport_ok {
		view.close(&registry, &handle)
		view.registry_close(&registry)
		editor.buffer_close(&buffer)
		return false
	}

	persistent_tracking: mem.Tracking_Allocator
	temporary_tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&persistent_tracking, context.allocator)
	mem.tracking_allocator_init(&temporary_tracking, context.allocator)
	persistent := mem.tracking_allocator(&persistent_tracking)
	temporary := mem.tracking_allocator(&temporary_tracking)
	cache: display.Projection_Cache
	cache_storage_bytes: u64
	if scenario.cache {
		logical, _, _ := view.snapshot(&registry, handle)
		cache_ok, cache_failure := display.projection_cache_init(
			&cache,
			logical,
			display.terminal_unicode17_profile(),
			persistent,
		)
		if !cache_ok {
			fmt.eprintf("benchmark=display-projection case=%s cache_failure=%v\n", scenario.name, cache_failure.code)
			cleanup_scenario(&registry, &handle, &buffer)
			mem.tracking_allocator_destroy(&temporary_tracking)
			mem.tracking_allocator_destroy(&persistent_tracking)
			return false
		}
		seed_request := benchmark_request(identity, logical, scenario.constraints, persistent, temporary)
		seed_snapshot, seeded, seed_failure := display.project_cached(&buffer, seed_request, &cache)
		if !seeded {
			fmt.eprintf("benchmark=display-projection case=%s seed_failure=%v\n", scenario.name, seed_failure.code)
			display.projection_cache_close(&cache)
			cleanup_scenario(&registry, &handle, &buffer)
			mem.tracking_allocator_destroy(&temporary_tracking)
			mem.tracking_allocator_destroy(&persistent_tracking)
			return false
		}
		display.snapshot_close(&seed_snapshot)
		view.set_viewport(&registry, handle, origin, scenario.horizontal)
		cache_stats, _, _ := display.projection_cache_stats(&cache)
		cache_storage_bytes = cache_stats.storage_bytes
	}

	latencies: [SAMPLE_COUNT]i64
	max_retained_bytes: u64
	max_source_bytes: u64
	for operation_index in 0 ..< WARMUP_COUNT + SAMPLE_COUNT {
		logical, logical_ok, _ := view.snapshot(&registry, handle)
		if !logical_ok {
			return false
		}
		request := benchmark_request(
			identity * 1_000 + u64(operation_index + 1),
			logical,
			scenario.constraints,
			persistent,
			temporary,
		)
		started := time.tick_now()
		snapshot: display.Snapshot
		projected: bool
		failure: display.Failure_Context
		if scenario.cache {
			snapshot, projected, failure = display.project_cached(&buffer, request, &cache)
		} else {
			snapshot, projected, failure = display.project(&buffer, request)
		}
		elapsed_ns := time.duration_nanoseconds(time.tick_since(started))
		if !projected {
			fmt.eprintf("benchmark=display-projection case=%s projection_failure=%v\n", scenario.name, failure.code)
			return false
		}
		result, viewed, _ := display.snapshot_view(snapshot)
		if !viewed {
			return false
		}
		max_retained_bytes = max(max_retained_bytes, result.accounting.retained_bytes)
		max_source_bytes = max(max_source_bytes, result.accounting.source_bytes_examined)
		display.snapshot_close(&snapshot)
		if temporary_tracking.current_memory_allocated != 0 {
			fmt.eprintf("benchmark=display-projection case=%s temporary_leak=%d\n", scenario.name, temporary_tracking.current_memory_allocated)
			return false
		}
		if operation_index >= WARMUP_COUNT {
			latencies[operation_index - WARMUP_COUNT] = elapsed_ns
		}
	}
	slice.sort(latencies[:])
	p99_ns := percentile_nearest_rank(latencies[:], 99)
	latency_passed := p99_ns <= LAYOUT_MAPPING_P99_GATE_NS
	if scenario.cache {
		display.projection_cache_close(&cache)
	}
	persistent_live_before_editor_cleanup := persistent_tracking.current_memory_allocated
	cleanup_scenario(&registry, &handle, &buffer)
	cleanup_passed := persistent_tracking.current_memory_allocated == 0 &&
	                  temporary_tracking.current_memory_allocated == 0
	fmt.printf(
		"benchmark=display-projection case=%s width=%d height=%d horizontal=%d cache=%t warmup=%d samples=%d p50_ns=%d p95_ns=%d p99_ns=%d max_ns=%d gate_p99_ns=%d max_source_bytes=%d max_snapshot_bytes=%d cache_storage_bytes=%d persistent_live_before_editor_cleanup=%d persistent_live_bytes=%d temporary_peak_bytes=%d temporary_live_bytes=%d latency_passed=%t cleanup_passed=%t\n",
		scenario.name,
		scenario.constraints.width_cells,
		scenario.constraints.height_rows,
		scenario.horizontal,
		scenario.cache,
		WARMUP_COUNT,
		SAMPLE_COUNT,
		percentile_nearest_rank(latencies[:], 50),
		percentile_nearest_rank(latencies[:], 95),
		p99_ns,
		latencies[SAMPLE_COUNT - 1],
		LAYOUT_MAPPING_P99_GATE_NS,
		max_source_bytes,
		max_retained_bytes,
		cache_storage_bytes,
		persistent_live_before_editor_cleanup,
		persistent_tracking.current_memory_allocated,
		temporary_tracking.peak_memory_allocated,
		temporary_tracking.current_memory_allocated,
		latency_passed,
		cleanup_passed,
	)
	mem.tracking_allocator_destroy(&temporary_tracking)
	mem.tracking_allocator_destroy(&persistent_tracking)
	return latency_passed && cleanup_passed
}

benchmark_request :: proc(
	id: u64,
	logical: view.Snapshot,
	constraints: display.Viewport_Constraints,
	persistent, temporary: mem.Allocator,
) -> display.Projection_Request {
	return display.Projection_Request {
		snapshot_id = display.Snapshot_ID(id),
		view = logical,
		constraints = constraints,
		profile = display.terminal_unicode17_profile(),
		limits = display.DEFAULT_RESOURCE_LIMITS,
		allocators = display.Allocator_Set {persistent = persistent, temporary = temporary},
	}
}

cleanup_scenario :: proc(
	registry: ^view.Registry,
	handle: ^view.View_Handle,
	buffer: ^editor.Buffer,
) {
	view.close(registry, handle)
	view.registry_close(registry)
	editor.buffer_close(buffer)
}

ascii_grid :: proc(width, height: int) -> []u8 {
	line_bytes := width + 1
	text := make([]u8, line_bytes * height)
	for row_index in 0 ..< height {
		start := row_index * line_bytes
		for column_index in 0 ..< width {
			text[start + column_index] = 'a' + u8(column_index % 26)
		}
		text[start + width] = '\n'
	}
	return text
}

repeated_text :: proc(pattern: string, target_bytes: int) -> []u8 {
	repetitions := target_bytes / len(pattern)
	text := make([]u8, repetitions * len(pattern))
	for index in 0 ..< repetitions {
		copy(text[index * len(pattern):], pattern)
	}
	return text
}

percentile_nearest_rank :: proc(sorted_values: []i64, percentile: int) -> i64 {
	assert(len(sorted_values) > 0)
	assert(percentile > 0 && percentile <= 100)
	rank := (len(sorted_values) * percentile + 99) / 100
	return sorted_values[rank - 1]
}
