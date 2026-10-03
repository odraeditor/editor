// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../../src/display"
import "base:runtime"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:slice"
import "core:time"

WARMUP_COUNT :: 8
SAMPLE_COUNT :: 32
STRESS_WARMUP_COUNT :: 2
STRESS_SAMPLE_COUNT :: 8
LAYOUT_MAPPING_P99_GATE_NS :: i64(8_000_000)
CHECKPOINT_INTERVAL_BYTES :: u64(256)

Scenario :: struct {
	name:         string,
	pattern:      string,
	target_bytes: int,
	constraints:  display.Viewport_Constraints,
	operating:    bool,
	full_grid:    bool,
	scan_all:     bool,
}

Measurement :: struct {
	graphemes:          u64,
	display_cells:      u64,
	logical_rows:       u32,
	runs:               u32,
	boundaries:         u32,
	checkpoints:        u32,
	retained_bytes:     u64,
	allocation_peak:    i64,
	allocation_current: i64,
	source_examined:    u64,
}

main :: proc() {
	ordinary := display.Viewport_Constraints{width_cells = 80, height_rows = 24}
	large := display.Viewport_Constraints{width_cells = 160, height_rows = 50}
	worst_operating := display.Viewport_Constraints{width_cells = 240, height_rows = 80}
	scenarios := [?]Scenario{
		Scenario{name = "ascii-multiline", pattern = "alpha beta gamma delta\n", target_bytes = 32 * int(display.KIBIBYTE), constraints = ordinary, operating = true},
		Scenario{name = "multilingual", pattern = "Odra Ελληνικά Polski العربية हिन्दी\n", target_bytes = 48 * int(display.KIBIBYTE), constraints = large, operating = true},
		Scenario{name = "full-grid-ascii", pattern = "x", constraints = worst_operating, operating = true, full_grid = true},
		Scenario{name = "combining-dense", pattern = "e\u0301 a\u0308 n\u0303 o\u0328\n", target_bytes = 64 * int(display.KIBIBYTE), constraints = worst_operating, operating = true},
		Scenario{name = "wide-dense", pattern = "界面 文本 編集 表示\n", target_bytes = 64 * int(display.KIBIBYTE), constraints = worst_operating, operating = true},
		Scenario{name = "emoji-dense", pattern = "👩\u200D💻 🙂 🇵🇱 1\uFE0F\u20E3\n", target_bytes = 64 * int(display.KIBIBYTE), constraints = worst_operating, operating = true},
		Scenario{name = "tabbed-multiline", pattern = "alpha\tbeta\tgamma\n", target_bytes = 64 * int(display.KIBIBYTE), constraints = worst_operating, operating = true},
		Scenario{name = "mixed-multiline", pattern = "Odra e\u0301 界 👩\u200D💻\tPolski\n", target_bytes = 64 * int(display.KIBIBYTE), constraints = worst_operating, operating = true},
		Scenario{name = "uncached-replay-combining", pattern = "e\u0301", target_bytes = 16 * int(display.KIBIBYTE), constraints = worst_operating, operating = true, scan_all = true},
		Scenario{name = "long-line-operating", pattern = "x", target_bytes = 64 * int(display.KIBIBYTE), constraints = worst_operating, operating = true},
		Scenario{name = "long-line-ceiling-probe", pattern = "x", target_bytes = int(display.MEBIBYTE), constraints = worst_operating, operating = false},
	}

	passed := true
	for scenario in scenarios {
		if !run_scenario(scenario) {
			passed = false
		}
	}
	if !passed {
		os.exit(1)
	}
}

run_scenario :: proc(scenario: Scenario) -> bool {
	input, input_error := repeated_input(scenario.pattern, scenario.target_bytes)
	if scenario.full_grid {
		delete(input)
		input, input_error = ascii_grid_input(scenario.constraints)
	}
	if input_error != nil {
		fmt.eprintf("evidence=display-projection-model case=%s input_allocation_failure=%v\n", scenario.name, input_error)
		return false
	}
	defer delete(input)

	warmup_count := WARMUP_COUNT
	sample_count := SAMPLE_COUNT
	if !scenario.operating {
		warmup_count = STRESS_WARMUP_COUNT
		sample_count = STRESS_SAMPLE_COUNT
	}
	latencies: [SAMPLE_COUNT]i64
	measurement: Measurement
	for sample_index in 0 ..< warmup_count + sample_count {
		started := time.tick_now()
		current, measured := measure_snapshot(string(input), scenario.constraints, scenario.scan_all)
		elapsed_ns := time.duration_nanoseconds(time.tick_since(started))
		if !measured {
			fmt.eprintf("evidence=display-projection-model case=%s measurement_failure=true\n", scenario.name)
			return false
		}
		measurement = current
		if sample_index >= warmup_count {
			latencies[sample_index - warmup_count] = elapsed_ns
		}
	}
	sorted := latencies[:sample_count]
	slice.sort(sorted)
	p99_ns := percentile_nearest_rank(sorted, 99)
	latency_passed := !scenario.operating || p99_ns <= LAYOUT_MAPPING_P99_GATE_NS
	cleanup_passed := measurement.allocation_current == 0
	fmt.printf(
		"evidence=display-projection-model case=%s operating=%t width=%d height=%d corpus_bytes=%d source_examined_bytes=%d graphemes=%d display_cells=%d logical_rows=%d runs=%d boundaries=%d checkpoints=%d retained_bytes=%d allocation_peak_bytes=%d allocation_live_bytes=%d warmup=%d samples=%d p50_ns=%d p95_ns=%d p99_ns=%d max_ns=%d gate_applies=%t gate_p99_ns=%d latency_passed=%t cleanup_passed=%t\n",
		scenario.name,
		scenario.operating,
		scenario.constraints.width_cells,
		scenario.constraints.height_rows,
		len(input),
		measurement.source_examined,
		measurement.graphemes,
		measurement.display_cells,
		measurement.logical_rows,
		measurement.runs,
		measurement.boundaries,
		measurement.checkpoints,
		measurement.retained_bytes,
		measurement.allocation_peak,
		measurement.allocation_current,
		warmup_count,
		sample_count,
		percentile_nearest_rank(sorted, 50),
		percentile_nearest_rank(sorted, 95),
		p99_ns,
		sorted[len(sorted) - 1],
		scenario.operating,
		LAYOUT_MAPPING_P99_GATE_NS,
		latency_passed,
		cleanup_passed,
	)
	return latency_passed && cleanup_passed
}

measure_snapshot :: proc(
	text: string,
	constraints: display.Viewport_Constraints,
	scan_all: bool,
) -> (measurement: Measurement, ok: bool) {
	profile := display.terminal_unicode17_profile()
	offset := u64(0)
	column := u32(0)
	logical_rows := u32(1)
	graphemes := u64(0)
	display_cells := u64(0)
	for offset < u64(len(text)) {
		grapheme, grapheme_ok, _ := display.profile_next_grapheme(profile.unicode, text, offset)
		if !grapheme_ok {
			return {}, false
		}
		width, width_ok, _ := display.profile_cluster_width(
			profile.unicode,
			text[grapheme.start:grapheme.end],
			column,
			display.DEFAULT_TAB_WIDTH,
		)
		if !width_ok {
			return {}, false
		}
		graphemes += 1
		if width.is_line_break {
			if !scan_all && logical_rows >= constraints.height_rows {
				offset = grapheme.end
				break
			}
			logical_rows += 1
			column = 0
		} else {
			column += u32(width.cells)
			display_cells += u64(width.cells)
			if !scan_all && column >= constraints.width_cells {
				line_end := int(grapheme.end)
				for line_end < len(text) && text[line_end] != '\n' {
					line_end += 1
				}
				if line_end == len(text) || logical_rows >= constraints.height_rows {
					offset = grapheme.end
					break
				}
				logical_rows += 1
				column = 0
				offset = u64(line_end + 1)
				continue
			}
		}
		offset = grapheme.end
	}

	row_count := min(logical_rows, constraints.height_rows)
	run_count := max(row_count, u32(1))
	boundary_total := graphemes + u64(row_count)
	if boundary_total > u64(max(u32)) {
		return {}, false
	}
	boundary_count := u32(boundary_total)
	checkpoint_count := u32((u64(len(text)) + CHECKPOINT_INTERVAL_BYTES - 1) / CHECKPOINT_INTERVAL_BYTES)
	estimate, estimate_ok, _ := display.representation_estimate(
		constraints,
		offset,
		offset,
		run_count,
		boundary_count,
		checkpoint_count,
		display.SAFETY_RESOURCE_LIMITS,
	)
	if !estimate_ok {
		return {}, false
	}

	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	text_storage, text_error := make([]u8, int(offset), allocator)
	rows, rows_error := make([]display.Display_Row, int(estimate.row_count), allocator)
	runs, runs_error := make([]display.Text_Run, int(estimate.run_count), allocator)
	boundaries, boundaries_error := make([]display.Boundary_Map, int(estimate.boundary_count), allocator)
	checkpoints, checkpoints_error := make([]display.Line_Checkpoint, int(estimate.checkpoint_count), allocator)
	if text_error != nil || rows_error != nil || runs_error != nil || boundaries_error != nil || checkpoints_error != nil {
		delete(checkpoints, allocator)
		delete(boundaries, allocator)
		delete(runs, allocator)
		delete(rows, allocator)
		delete(text_storage, allocator)
		mem.tracking_allocator_destroy(&tracking)
		return {}, false
	}
	copy(text_storage, text[:offset])
	allocation_peak := tracking.peak_memory_allocated
	delete(checkpoints, allocator)
	delete(boundaries, allocator)
	delete(runs, allocator)
	delete(rows, allocator)
	delete(text_storage, allocator)
	allocation_current := tracking.current_memory_allocated
	mem.tracking_allocator_destroy(&tracking)
	return Measurement{
		graphemes = graphemes,
		display_cells = display_cells,
		logical_rows = logical_rows,
		runs = estimate.run_count,
		boundaries = estimate.boundary_count,
		checkpoints = estimate.checkpoint_count,
		retained_bytes = estimate.accounting.retained_bytes,
		allocation_peak = allocation_peak,
		allocation_current = allocation_current,
		source_examined = offset,
	}, true
}

repeated_input :: proc(pattern: string, target_bytes: int) -> (input: []u8, error: runtime.Allocator_Error) {
	if len(pattern) == 0 || target_bytes < len(pattern) {
		return nil, nil
	}
	repetition_count := target_bytes / len(pattern)
	input, error = make([]u8, repetition_count * len(pattern))
	if error != nil {
		return nil, error
	}
	for repetition_index in 0 ..< repetition_count {
		copy(input[repetition_index * len(pattern):], pattern)
	}
	return input, nil
}

ascii_grid_input :: proc(
	constraints: display.Viewport_Constraints,
) -> (input: []u8, error: runtime.Allocator_Error) {
	line_bytes := int(constraints.width_cells) + 1
	input, error = make([]u8, line_bytes * int(constraints.height_rows))
	if error != nil {
		return nil, error
	}
	for row_index in 0 ..< int(constraints.height_rows) {
		line_start := row_index * line_bytes
		for column_index in 0 ..< int(constraints.width_cells) {
			input[line_start + column_index] = 'x'
		}
		input[line_start + int(constraints.width_cells)] = '\n'
	}
	return input, nil
}

percentile_nearest_rank :: proc(sorted_values: []i64, percentile: int) -> i64 {
	assert(len(sorted_values) > 0)
	assert(percentile > 0 && percentile <= 100)
	rank := (len(sorted_values) * percentile + 99) / 100
	return sorted_values[rank - 1]
}
