// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../../src/interaction"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:slice"
import "core:time"

COMPILE_WARMUP_COUNT :: 16
COMPILE_SAMPLE_COUNT :: 128
COMPILE_P99_GATE_NS :: i64(5_000_000)
RESOLVE_WARMUP_COUNT :: 256
RESOLVE_SAMPLE_COUNT :: 8_192
RESOLVE_P99_GATE_NS :: i64(10_000)

main :: proc() {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	definitions := [?]interaction.Command_Definition {
		{
			name = "insert-text",
			route = {provider = interaction.Command_Provider_ID(1), operation = 1},
			implementation = .Native,
			invocation = .Text_Input,
			text_requirement = .Required,
			effects = {.Buffer, .View},
			description = "Insert committed text.",
		},
		{
			name = "cursor-previous-grapheme",
			route = {provider = interaction.Command_Provider_ID(1), operation = 2},
			implementation = .Native,
			invocation = .Ordinary,
			text_requirement = .Prohibited,
			effects = {.View},
			description = "Move to the previous grapheme.",
		},
	}
	registry: interaction.Command_Registry
	registry_ready, registry_failure := interaction.command_registry_init(
		&registry,
		interaction.Registry_Generation(1),
		definitions[:],
		allocator,
	)
	if !registry_ready {
		fmt.eprintf("benchmark=interaction setup_failure=%v\n", registry_failure.code)
		os.exit(1)
	}

	bindings: [interaction.MAX_BINDINGS]interaction.Binding_Definition
	for &binding, index in bindings {
		binding.strokes[0] = interaction.Key_Stroke {
			kind = .Unicode_Scalar,
			scalar = rune(0x4e00 + index),
		}
		binding.stroke_count = 1
		binding.command_name = "cursor-previous-grapheme"
	}
	definition := interaction.Keymap_Definition {
		registry_generation = interaction.Registry_Generation(1),
		bindings = bindings[:],
		text_fallback_name = "insert-text",
	}

	snapshot: interaction.Resolution_Snapshot
	compile_latencies: [COMPILE_SAMPLE_COUNT]i64
	for operation_index in 0 ..< COMPILE_WARMUP_COUNT + COMPILE_SAMPLE_COUNT {
		started := time.tick_now()
		compiled, compile_failure := interaction.snapshot_compile(
			&snapshot,
			&registry,
			interaction.Snapshot_Generation(operation_index + 1),
			definition,
			allocator,
		)
		elapsed := time.duration_nanoseconds(time.tick_since(started))
		if !compiled {
			fmt.eprintf("benchmark=interaction compilation_failure=%v\n", compile_failure.code)
			os.exit(1)
		}
		if operation_index >= COMPILE_WARMUP_COUNT {
			compile_latencies[operation_index - COMPILE_WARMUP_COUNT] = elapsed
		}
	}
	slice.sort(compile_latencies[:])
	compile_p99 := percentile_nearest_rank(compile_latencies[:], 99)

	resolve_latencies: [RESOLVE_SAMPLE_COUNT]i64
	target := interaction.Key_Stroke{kind = .Unicode_Scalar, scalar = rune(0x4fff)}
	for operation_index in 0 ..< RESOLVE_WARMUP_COUNT + RESOLVE_SAMPLE_COUNT {
		pending: interaction.Pending_State
		started := time.tick_now()
		resolved, resolve_failure := interaction.resolve_input(
			&snapshot,
			interaction.Registry_Generation(1),
			&pending,
			interaction.Input{kind = .Key, stroke = target},
		)
		elapsed := time.duration_nanoseconds(time.tick_since(started))
		if resolve_failure.code != .None || resolved.kind != .Command {
			fmt.eprintf("benchmark=interaction resolution_failure=%v\n", resolve_failure.code)
			os.exit(1)
		}
		if operation_index >= RESOLVE_WARMUP_COUNT {
			resolve_latencies[operation_index - RESOLVE_WARMUP_COUNT] = elapsed
		}
	}
	slice.sort(resolve_latencies[:])
	resolve_p99 := percentile_nearest_rank(resolve_latencies[:], 99)

	snapshot_stats, stats_ok, _ := interaction.snapshot_stats(&snapshot)
	snapshot_closed, _ := interaction.snapshot_close(&snapshot)
	registry_closed, _ := interaction.command_registry_close(&registry)
	live_bytes := tracking.current_memory_allocated
	mem.tracking_allocator_destroy(&tracking)
	compile_passed := compile_p99 <= COMPILE_P99_GATE_NS
	resolve_passed := resolve_p99 <= RESOLVE_P99_GATE_NS
	cleanup_passed := stats_ok && snapshot_closed && registry_closed && live_bytes == 0
	fmt.printf(
		"benchmark=interaction-keymap bindings=%d storage_bytes=%d compile_warmup=%d compile_samples=%d compile_p50_ns=%d compile_p99_ns=%d compile_gate_ns=%d compile_passed=%t resolve_warmup=%d resolve_samples=%d resolve_p50_ns=%d resolve_p99_ns=%d resolve_gate_ns=%d resolve_passed=%t live_bytes=%d cleanup_passed=%t\n",
		len(bindings),
		snapshot_stats.storage_bytes,
		COMPILE_WARMUP_COUNT,
		COMPILE_SAMPLE_COUNT,
		percentile_nearest_rank(compile_latencies[:], 50),
		compile_p99,
		COMPILE_P99_GATE_NS,
		compile_passed,
		RESOLVE_WARMUP_COUNT,
		RESOLVE_SAMPLE_COUNT,
		percentile_nearest_rank(resolve_latencies[:], 50),
		resolve_p99,
		RESOLVE_P99_GATE_NS,
		resolve_passed,
		live_bytes,
		cleanup_passed,
	)
	if !compile_passed || !resolve_passed || !cleanup_passed {
		os.exit(1)
	}
}

percentile_nearest_rank :: proc(values: []i64, percentile: int) -> i64 {
	assert(len(values) > 0)
	index := (percentile * len(values) + 99) / 100 - 1
	return values[clamp(index, 0, len(values) - 1)]
}
