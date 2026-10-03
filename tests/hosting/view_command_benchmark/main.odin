// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../../../src/bridge"
import "../../../src/command"
import "../../../src/display"
import "../../../src/editor"
import "../../../src/hosting"
import "../../../src/interaction"
import edit_transaction "../../../src/transaction"
import editor_view "../../../src/view"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:slice"
import "core:time"

WARMUP_COUNT :: 64
SAMPLE_COUNT :: 512
RACKET_COMMAND_P99_GATE_NS :: i64(8_000_000)
LINE_BYTES :: 4 * 1024

main :: proc() {
	persistent_tracking: mem.Tracking_Allocator
	temporary_tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&persistent_tracking, context.allocator)
	mem.tracking_allocator_init(&temporary_tracking, context.allocator)
	persistent := mem.tracking_allocator(&persistent_tracking)
	temporary := mem.tracking_allocator(&temporary_tracking)

	racket_runtime: hosting.Runtime
	started, start_failure := hosting.runtime_start(&racket_runtime)
	if !started {
		fmt.eprintf("benchmark=racket-view-command runtime_failure=%v\n", start_failure.code)
		os.exit(1)
	}

	line: [LINE_BYTES]u8
	for &value in line {
		value = 'a'
	}
	buffer: editor.Buffer
	buffer_ready, buffer_failure := editor.buffer_init(
		&buffer,
		editor.Buffer_ID(93),
		string(line[:]),
		editor.Allocator_Set{persistent = persistent, temporary = context.temp_allocator},
	)
	if !buffer_ready {
		fmt.eprintf("benchmark=racket-view-command buffer_failure=%v\n", buffer_failure.code)
		os.exit(1)
	}

	capabilities: bridge.Buffer_Capability_Registry
	capabilities_ready, capability_failure := bridge.buffer_capability_registry_init(
		&capabilities,
		bridge.Registry_ID(94),
	)
	transaction_capabilities: bridge.Transaction_Capability_Registry
	transaction_capabilities_ready, transaction_capability_failure :=
		bridge.transaction_capability_registry_init(
			&transaction_capabilities,
			bridge.Registry_ID(96),
		)
	views: editor_view.Registry
	views_ready, view_failure := editor_view.registry_init(
		&views,
		editor_view.Registry_ID(95),
		persistent,
	)
	view, view_ready, create_failure := editor_view.create(&views, &buffer)
	definitions := [1]interaction.Command_Definition {{
		name = "uppercase-current-line",
		route = {provider = interaction.Command_Provider_ID(1), operation = 1},
		implementation = .Racket,
		invocation = .Ordinary,
		text_requirement = .Prohibited,
		effects = {.Buffer, .View},
		description = "Uppercase the current logical line.",
	}}
	registry: interaction.Command_Registry
	registry_ready, registry_failure := interaction.command_registry_init(
		&registry,
		interaction.Registry_Generation(20),
		definitions[:],
		persistent,
	)
	uppercase, command_ready, lookup_failure := interaction.command_lookup(
		&registry,
		"uppercase-current-line",
	)
	if !capabilities_ready || !transaction_capabilities_ready || !views_ready ||
	   !view_ready || !registry_ready ||
	   !command_ready {
		fmt.eprintf(
			"benchmark=racket-view-command setup_failure capability=%v transaction=%v view=%v create=%v registry=%v lookup=%v\n",
			capability_failure.code,
			transaction_capability_failure.code,
			view_failure.code,
			create_failure.code,
			registry_failure.code,
			lookup_failure.code,
		)
		os.exit(1)
	}

	latencies: [SAMPLE_COUNT]i64
	for operation_index in 0 ..< WARMUP_COUNT + SAMPLE_COUNT {
		started_call := time.tick_now()
		result, executed, execute_failure := command.racket_command_execute(
			command.Racket_Context {
				runtime = &racket_runtime,
				capabilities = &capabilities,
				transaction_capabilities = &transaction_capabilities,
				command_registry = &registry,
				command = uppercase,
				buffer = &buffer,
				view_registry = &views,
				view = view,
				profile = display.terminal_unicode17_profile(),
				constraints = display.Viewport_Constraints {
					width_cells = 80,
					height_rows = 24,
				},
				temporary_allocator = temporary,
				persistent_allocator = persistent,
				transaction_id = edit_transaction.Transaction_ID(operation_index + 1),
				undo_unit_id = edit_transaction.Undo_Unit_ID(operation_index + 1),
			},
		)
		elapsed := time.duration_nanoseconds(time.tick_since(started_call))
		expected_completion := command.Native_Completion.No_Op
		if operation_index == 0 {
			expected_completion = .Buffer_Committed
		}
		if !executed || result.completion != expected_completion {
			fmt.eprintf(
				"benchmark=racket-view-command execute_failure=%v completion=%v\n",
				execute_failure.code,
				result.completion,
			)
			os.exit(1)
		}
		command.native_result_close(&result)
		if temporary_tracking.current_memory_allocated != 0 {
			fmt.eprintf(
				"benchmark=racket-view-command temporary_live_bytes=%d\n",
				temporary_tracking.current_memory_allocated,
			)
			os.exit(1)
		}
		if operation_index >= WARMUP_COUNT {
			latencies[operation_index - WARMUP_COUNT] = elapsed
		}
	}

	slice.sort(latencies[:])
	p99 := percentile_nearest_rank(latencies[:], 99)
	latency_passed := p99 <= RACKET_COMMAND_P99_GATE_NS

	registry_closed, _ := interaction.command_registry_close(&registry)
	view_closed, _ := editor_view.close(&views, &view)
	views_closed, _ := editor_view.registry_close(&views)
	transaction_capabilities_closed, _ := bridge.transaction_capability_registry_close(
		&transaction_capabilities,
	)
	runtime_closed, _ := command.buffer_command_shutdown(&racket_runtime, &capabilities)
	buffer_closed, _ := editor.buffer_close(&buffer)
	persistent_live_bytes := persistent_tracking.current_memory_allocated
	temporary_live_bytes := temporary_tracking.current_memory_allocated
	cleanup_passed := registry_closed && view_closed && views_closed &&
	                 transaction_capabilities_closed && runtime_closed && buffer_closed &&
	                 persistent_live_bytes == 0 && temporary_live_bytes == 0

	fmt.printf(
		"benchmark=racket-view-command bytes=%d warmup=%d samples=%d p50_ns=%d p95_ns=%d p99_ns=%d max_ns=%d gate_p99_ns=%d latency_passed=%t persistent_live_bytes=%d temporary_live_bytes=%d cleanup_passed=%t\n",
		LINE_BYTES,
		WARMUP_COUNT,
		SAMPLE_COUNT,
		percentile_nearest_rank(latencies[:], 50),
		percentile_nearest_rank(latencies[:], 95),
		p99,
		latencies[len(latencies) - 1],
		RACKET_COMMAND_P99_GATE_NS,
		latency_passed,
		persistent_live_bytes,
		temporary_live_bytes,
		cleanup_passed,
	)
	mem.tracking_allocator_destroy(&temporary_tracking)
	mem.tracking_allocator_destroy(&persistent_tracking)
	if !latency_passed || !cleanup_passed {
		os.exit(1)
	}
}

percentile_nearest_rank :: proc(values: []i64, percentile: int) -> i64 {
	assert(len(values) > 0)
	index := (percentile * len(values) + 99) / 100 - 1
	return values[clamp(index, 0, len(values) - 1)]
}
