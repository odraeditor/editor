// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../../../src/bridge"
import "../../../src/command"
import "../../../src/editor"
import "../../../src/hosting"
import edit_transaction "../../../src/transaction"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:slice"
import "core:time"

WARMUP_COUNT :: 32
SAMPLE_COUNT :: 128
COMMAND_P95_GATE_NS :: i64(10_000_000)
COMMAND_BENCHMARK_SCENARIO :: i32(#config(ODRA_RACKET_COMMAND_SCENARIO, 0))

main :: proc() {
	racket_runtime: hosting.Runtime
	started, start_failure := hosting.runtime_start(&racket_runtime)
	if !started {
		fmt.eprintf("command benchmark runtime start failed: %s\n", start_failure.diagnostic)
		os.exit(1)
	}

	buffer: editor.Buffer
	persistent_tracking: mem.Tracking_Allocator
	temporary_tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&persistent_tracking, context.allocator)
	mem.tracking_allocator_init(&temporary_tracking, context.allocator)
	initialized, init_failure := editor.buffer_init(
		&buffer,
		editor.Buffer_ID(9),
		"hello odra",
		editor.Allocator_Set {
			persistent = mem.tracking_allocator(&persistent_tracking),
			temporary = context.temp_allocator,
		},
	)
	if !initialized {
		fmt.eprintf("command benchmark buffer init failed: %v\n", init_failure.code)
		hosting.runtime_shutdown(&racket_runtime)
		os.exit(1)
	}

	registry: bridge.Buffer_Capability_Registry
	registry_ready, _ := bridge.buffer_capability_registry_init(&registry, bridge.Registry_ID(7))
	capability, identity, acquired, _ := bridge.buffer_capability_acquire(&registry, &buffer)
	if !registry_ready || !acquired {
		fmt.eprintln("command benchmark capability setup failed")
		editor.buffer_close(&buffer)
		hosting.runtime_shutdown(&racket_runtime)
		os.exit(1)
	}

	latencies: [SAMPLE_COUNT]i64
	for operation_index in 0 ..< WARMUP_COUNT + SAMPLE_COUNT {
		started_call := time.tick_now()
		result, executed, command_failure := command.buffer_command_run(
			&racket_runtime,
			&registry,
			capability,
			identity.buffer_id,
			editor.Revision(operation_index),
			mem.tracking_allocator(&persistent_tracking),
			mem.tracking_allocator(&temporary_tracking),
			edit_transaction.Transaction_ID(operation_index + 1),
			edit_transaction.Undo_Unit_ID(operation_index + 1),
		)
		elapsed := time.duration_nanoseconds(time.tick_since(started_call))
		if !executed || result.publication.commit.result_revision != editor.Revision(operation_index + 1) {
			fmt.eprintf("command benchmark call failed: %v\n", command_failure.code)
			os.exit(1)
		}
		command.command_result_close(&result)
		if temporary_tracking.current_memory_allocated != 0 {
			fmt.eprintf(
				"command benchmark retained temporary bytes: %d\n",
				temporary_tracking.current_memory_allocated,
			)
			os.exit(1)
		}
		if operation_index >= WARMUP_COUNT {
			latencies[operation_index - WARMUP_COUNT] = elapsed
		}
	}

	slice.sort(latencies[:])
	p50 := percentile_nearest_rank(latencies[:], 50)
	p95 := percentile_nearest_rank(latencies[:], 95)
	p99 := percentile_nearest_rank(latencies[:], 99)
	latency_gated := COMMAND_BENCHMARK_SCENARIO != 4
	latency_passed := !latency_gated || p95 <= COMMAND_P95_GATE_NS
	reported_gate_ns := COMMAND_P95_GATE_NS if latency_gated else 0
	passed := latency_passed && temporary_tracking.current_memory_allocated == 0
	operation_count := WARMUP_COUNT + SAMPLE_COUNT
	allocated_bytes_per_command := temporary_tracking.total_memory_allocated / i64(operation_count)
	fmt.printf(
		"benchmark=racket-buffer-command forced_gc=%t warmup=%d samples=%d p50_ns=%d p95_ns=%d p99_ns=%d max_ns=%d copied_bytes_per_command=8 temporary_allocated_bytes_per_command=%d temporary_peak_bytes=%d temporary_live_bytes=%d latency_gated=%t gate_p95_ns=%d passed=%t\n",
		COMMAND_BENCHMARK_SCENARIO == 4,
		WARMUP_COUNT,
		SAMPLE_COUNT,
		p50,
		p95,
		p99,
		latencies[SAMPLE_COUNT - 1],
		allocated_bytes_per_command,
		temporary_tracking.peak_memory_allocated,
		temporary_tracking.current_memory_allocated,
		latency_gated,
		reported_gate_ns,
		passed,
	)

	bridge.buffer_capability_release(&registry, &capability)
	shutdown_started := time.tick_now()
	shutdown, shutdown_failure := command.buffer_command_shutdown(&racket_runtime, &registry)
	shutdown_ns := time.duration_nanoseconds(time.tick_since(shutdown_started))
	if !shutdown {
		fmt.eprintf("command benchmark shutdown failed: %v\n", shutdown_failure.code)
		os.exit(1)
	}
	editor.buffer_close(&buffer)
	fmt.printf(
		"benchmark=racket-buffer-command-cleanup forced_gc=%t shutdown_ns=%d persistent_live_bytes=%d temporary_live_bytes=%d\n",
		COMMAND_BENCHMARK_SCENARIO == 4,
		shutdown_ns,
		persistent_tracking.current_memory_allocated,
		temporary_tracking.current_memory_allocated,
	)
	if persistent_tracking.current_memory_allocated != 0 ||
	   temporary_tracking.current_memory_allocated != 0 {
		passed = false
	}
	mem.tracking_allocator_destroy(&temporary_tracking)
	mem.tracking_allocator_destroy(&persistent_tracking)
	if !passed {
		os.exit(1)
	}
}

percentile_nearest_rank :: proc(sorted_values: []i64, percentile: int) -> i64 {
	assert(len(sorted_values) > 0)
	assert(percentile > 0 && percentile <= 100)
	rank := (len(sorted_values) * percentile + 99) / 100
	return sorted_values[rank - 1]
}
