// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../../src/editor"
import "../../src/view"
import "core:fmt"
import "core:os"
import "core:slice"
import "core:time"

LOCALIZED_ANCHOR_COUNT :: 100_000
LOCALIZED_WARMUP_COUNT :: 32
LOCALIZED_SAMPLE_COUNT :: 256
LOCALIZED_P99_GATE_NS :: i64(2_000_000)
STRESS_ANCHOR_COUNT :: 1_000_000
STRESS_WARMUP_COUNT :: 8
STRESS_SAMPLE_COUNT :: 40
STRESS_P99_GATE_NS :: i64(16_000_000)
ANCHOR_STORAGE_GATE_BYTES :: u64(64)
VIEW_WARMUP_COUNT :: 32
VIEW_SAMPLE_COUNT :: 256

main :: proc() {
	localized_ok := run_anchor_case(
		"localized-anchor-transform",
		LOCALIZED_ANCHOR_COUNT,
		LOCALIZED_WARMUP_COUNT,
		LOCALIZED_SAMPLE_COUNT,
		LOCALIZED_P99_GATE_NS,
	)
	stress_ok := run_anchor_case(
		"million-anchor-transform",
		STRESS_ANCHOR_COUNT,
		STRESS_WARMUP_COUNT,
		STRESS_SAMPLE_COUNT,
		STRESS_P99_GATE_NS,
	)
	view_ok := run_view_lifecycle_case()
	if !localized_ok || !stress_ok || !view_ok {
		os.exit(1)
	}
}

run_view_lifecycle_case :: proc() -> bool {
	buffer: editor.Buffer
	initialized, init_failure := editor.buffer_init(
		&buffer,
		editor.Buffer_ID(301),
		"view lifecycle",
		editor.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	if !initialized {
		fmt.eprintf("benchmark=view-lifecycle initialization_failure=%v\n", init_failure.code)
		return false
	}
	registry: view.Registry
	ready, registry_failure := view.registry_init(
		&registry,
		view.Registry_ID(31),
		context.allocator,
	)
	if !ready {
		fmt.eprintf("benchmark=view-lifecycle registry_failure=%v\n", registry_failure.code)
		editor.buffer_close(&buffer)
		return false
	}
	registry_stats, registry_stats_ok, _ := view.registry_stats(&registry)
	if !registry_stats_ok {
		view.registry_close(&registry)
		editor.buffer_close(&buffer)
		return false
	}

	latencies := make([]i64, VIEW_SAMPLE_COUNT)
	defer delete(latencies)
	for operation_index in 0 ..< VIEW_WARMUP_COUNT + VIEW_SAMPLE_COUNT {
		started := time.tick_now()
		handle, created, create_failure := view.create(&registry, &buffer)
		if !created {
			fmt.eprintf(
				"benchmark=view-lifecycle operation=%d creation_failure=%v\n",
				operation_index,
				create_failure.code,
			)
			view.registry_close(&registry)
			editor.buffer_close(&buffer)
			return false
		}
		_, snapshot_ok, snapshot_failure := view.snapshot(&registry, handle)
		if !snapshot_ok {
			fmt.eprintf(
				"benchmark=view-lifecycle operation=%d snapshot_failure=%v\n",
				operation_index,
				snapshot_failure.code,
			)
			view.close(&registry, &handle)
			view.registry_close(&registry)
			editor.buffer_close(&buffer)
			return false
		}
		closed, close_failure := view.close(&registry, &handle)
		elapsed_ns := time.duration_nanoseconds(time.tick_since(started))
		if !closed {
			fmt.eprintf(
				"benchmark=view-lifecycle operation=%d close_failure=%v\n",
				operation_index,
				close_failure.code,
			)
			view.registry_close(&registry)
			editor.buffer_close(&buffer)
			return false
		}
		if operation_index >= VIEW_WARMUP_COUNT {
			latencies[operation_index - VIEW_WARMUP_COUNT] = elapsed_ns
		}
	}
	slice.sort(latencies)
	anchor_stats, anchor_stats_ok, _ := editor.buffer_anchor_stats(&buffer)
	registry_closed, _ := view.registry_close(&registry)
	buffer_closed, _ := editor.buffer_close(&buffer)
	if !anchor_stats_ok || anchor_stats.live_count != 0 || !registry_closed || !buffer_closed {
		fmt.eprintln("benchmark=view-lifecycle cleanup_failure")
		return false
	}
	fmt.printf(
		"benchmark=view-lifecycle warmup=%d samples=%d registry_storage_bytes=%d retained_anchor_storage_bytes=%d p50_ns=%d p95_ns=%d p99_ns=%d max_ns=%d cleanup_passed=true\n",
		VIEW_WARMUP_COUNT,
		VIEW_SAMPLE_COUNT,
		registry_stats.storage_bytes,
		anchor_stats.storage_bytes,
		percentile_nearest_rank(latencies, 50),
		percentile_nearest_rank(latencies, 95),
		percentile_nearest_rank(latencies, 99),
		latencies[len(latencies) - 1],
	)
	return true
}

run_anchor_case :: proc(
	name: string,
	anchor_count, warmup_count, sample_count: int,
	gate_ns: i64,
) -> bool {
	buffer: editor.Buffer
	initialized, init_failure := editor.buffer_init(
		&buffer,
		editor.Buffer_ID(anchor_count),
		"abc",
		editor.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	if !initialized {
		fmt.eprintf("benchmark=%s initialization_failure=%v\n", name, init_failure.code)
		return false
	}

	position, position_ok, position_failure := editor.buffer_position(
		&buffer,
		editor.Byte_Offset(1),
	)
	if !position_ok {
		fmt.eprintf("benchmark=%s position_failure=%v\n", name, position_failure.code)
		editor.buffer_close(&buffer)
		return false
	}
	for anchor_index in 0 ..< anchor_count {
		affinity := editor.Anchor_Affinity.Left
		if anchor_index % 2 != 0 {
			affinity = .Right
		}
		_, created, create_failure := editor.buffer_anchor_create(
			&buffer,
			position,
			affinity,
			.Collapse,
		)
		if !created {
			fmt.eprintf(
				"benchmark=%s anchor=%d creation_failure=%v\n",
				name,
				anchor_index,
				create_failure.code,
			)
			editor.buffer_close(&buffer)
			return false
		}
	}
	anchor_stats, stats_ok, stats_failure := editor.buffer_anchor_stats(&buffer)
	if !stats_ok {
		fmt.eprintf("benchmark=%s stats_failure=%v\n", name, stats_failure.code)
		editor.buffer_close(&buffer)
		return false
	}
	average_storage := anchor_stats.storage_bytes / u64(anchor_count)
	storage_ok := average_storage <= ANCHOR_STORAGE_GATE_BYTES

	latencies := make([]i64, sample_count)
	defer delete(latencies)
	for operation_index in 0 ..< warmup_count + sample_count {
		start, start_ok, _ := editor.buffer_position(&buffer, editor.Byte_Offset(1))
		end, end_ok, _ := editor.buffer_position(&buffer, editor.Byte_Offset(2))
		if !start_ok || !end_ok {
			fmt.eprintf("benchmark=%s operation=%d position_failure\n", name, operation_index)
			editor.buffer_close(&buffer)
			return false
		}
		replacement := "x"
		if operation_index % 2 != 0 {
			replacement = "y"
		}
		started := time.tick_now()
		_, _, published, publish_failure := editor.buffer_splice(
			&buffer,
			editor.Splice{start = start, end = end, replacement = replacement},
			context.temp_allocator,
		)
		elapsed_ns := time.duration_nanoseconds(time.tick_since(started))
		if !published {
			fmt.eprintf(
				"benchmark=%s operation=%d publication_failure=%v\n",
				name,
				operation_index,
				publish_failure.code,
			)
			editor.buffer_close(&buffer)
			return false
		}
		if operation_index >= warmup_count {
			latencies[operation_index - warmup_count] = elapsed_ns
		}
	}
	slice.sort(latencies)
	p50 := percentile_nearest_rank(latencies, 50)
	p95 := percentile_nearest_rank(latencies, 95)
	p99 := percentile_nearest_rank(latencies, 99)
	latency_ok := p99 <= gate_ns
	closed, close_failure := editor.buffer_close(&buffer)
	if !closed {
		fmt.eprintf("benchmark=%s close_failure=%v\n", name, close_failure.code)
		return false
	}
	fmt.printf(
		"benchmark=%s anchors=%d slot_bytes=%d storage_bytes=%d average_storage_bytes=%d storage_gate_bytes=%d p50_ns=%d p95_ns=%d p99_ns=%d max_ns=%d latency_gate_ns=%d storage_passed=%t latency_passed=%t\n",
		name,
		anchor_count,
		anchor_stats.slot_bytes,
		anchor_stats.storage_bytes,
		average_storage,
		ANCHOR_STORAGE_GATE_BYTES,
		p50,
		p95,
		p99,
		latencies[len(latencies) - 1],
		gate_ns,
		storage_ok,
		latency_ok,
	)
	return storage_ok && latency_ok
}

percentile_nearest_rank :: proc(sorted_values: []i64, percentile: int) -> i64 {
	assert(len(sorted_values) > 0)
	assert(percentile > 0 && percentile <= 100)
	rank := (len(sorted_values) * percentile + 99) / 100
	return sorted_values[rank - 1]
}
