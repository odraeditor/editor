// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../../src/command"
import "../../src/display"
import "../../src/editor"
import "../../src/interaction"
import edit_transaction "../../src/transaction"
import editor_view "../../src/view"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:slice"
import "core:time"

WARMUP_COUNT :: 256
SAMPLE_COUNT :: 8_192
NATIVE_DISPATCH_P99_GATE_NS :: i64(2_000_000)

main :: proc() {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)

	buffer: editor.Buffer
	buffer_ready, buffer_failure := editor.buffer_init(
		&buffer,
		editor.Buffer_ID(91),
		"ab",
		editor.Allocator_Set {
			persistent = allocator,
			temporary = context.temp_allocator,
		},
	)
	if !buffer_ready {
		fmt.eprintf("benchmark=native-command buffer_failure=%v\n", buffer_failure.code)
		os.exit(1)
	}
	views: editor_view.Registry
	views_ready, view_failure := editor_view.registry_init(
		&views,
		editor_view.Registry_ID(92),
		allocator,
	)
	view, view_ready, create_failure := editor_view.create(&views, &buffer)
	if !views_ready || !view_ready {
		fmt.eprintf(
			"benchmark=native-command view_failure=%v create_failure=%v\n",
			view_failure.code,
			create_failure.code,
		)
		os.exit(1)
	}
	definitions := command.native_command_definitions()
	registry: interaction.Command_Registry
	registry_ready, registry_failure := interaction.command_registry_init(
		&registry,
		interaction.Registry_Generation(1),
		definitions[:],
		allocator,
	)
	if !registry_ready {
		fmt.eprintf("benchmark=native-command registry_failure=%v\n", registry_failure.code)
		os.exit(1)
	}
	right, right_ok, _ := interaction.command_lookup(&registry, "cursor-next-grapheme")
	left, left_ok, _ := interaction.command_lookup(&registry, "cursor-previous-grapheme")
	if !right_ok || !left_ok {
		fmt.eprintln("benchmark=native-command command_lookup_failure=true")
		os.exit(1)
	}

	latencies: [SAMPLE_COUNT]i64
	for operation_index in 0 ..< WARMUP_COUNT + SAMPLE_COUNT {
		handle := right
		if operation_index & 1 == 1 {
			handle = left
		}
		started := time.tick_now()
		result, executed, execute_failure := command.native_command_execute(
			command.Native_Context {
				registry = &registry,
				command = handle,
				buffer = &buffer,
				view_registry = &views,
				view = view,
				profile = display.terminal_unicode17_profile(),
					constraints = display.Viewport_Constraints {
					width_cells = 80,
					height_rows = 24,
					},
					temporary_allocator = context.temp_allocator,
					persistent_allocator = allocator,
					transaction_id = edit_transaction.Transaction_ID(operation_index + 1),
					undo_unit_id = edit_transaction.Undo_Unit_ID(operation_index + 1),
				},
			)
			command.native_result_close(&result)
		elapsed := time.duration_nanoseconds(time.tick_since(started))
		if !executed || result.completion != .View_Changed {
			fmt.eprintf("benchmark=native-command dispatch_failure=%v\n", execute_failure.code)
			os.exit(1)
		}
		if operation_index >= WARMUP_COUNT {
			latencies[operation_index - WARMUP_COUNT] = elapsed
		}
	}
	slice.sort(latencies[:])
	p99 := percentile_nearest_rank(latencies[:], 99)
	latency_passed := p99 <= NATIVE_DISPATCH_P99_GATE_NS

	registry_closed, _ := interaction.command_registry_close(&registry)
	view_closed, _ := editor_view.close(&views, &view)
	views_closed, _ := editor_view.registry_close(&views)
	buffer_closed, _ := editor.buffer_close(&buffer)
	live_bytes := tracking.current_memory_allocated
	cleanup_passed := registry_closed && view_closed && views_closed && buffer_closed && live_bytes == 0
	mem.tracking_allocator_destroy(&tracking)
	fmt.printf(
		"benchmark=native-command-dispatch warmup=%d samples=%d p50_ns=%d p95_ns=%d p99_ns=%d max_ns=%d gate_p99_ns=%d latency_passed=%t live_bytes=%d cleanup_passed=%t\n",
		WARMUP_COUNT,
		SAMPLE_COUNT,
		percentile_nearest_rank(latencies[:], 50),
		percentile_nearest_rank(latencies[:], 95),
		p99,
		latencies[len(latencies) - 1],
		NATIVE_DISPATCH_P99_GATE_NS,
		latency_passed,
		live_bytes,
		cleanup_passed,
	)
	if !latency_passed || !cleanup_passed {
		os.exit(1)
	}
}

percentile_nearest_rank :: proc(values: []i64, percentile: int) -> i64 {
	assert(len(values) > 0)
	index := (percentile * len(values) + 99) / 100 - 1
	return values[clamp(index, 0, len(values) - 1)]
}
