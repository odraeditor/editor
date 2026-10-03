// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../../../src/bridge"
import "../../../src/editor"
import "../../../src/hosting"
import edit_transaction "../../../src/transaction"
import base_runtime "base:runtime"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:slice"
import "core:time"

WARMUP_COUNT :: 64
SAMPLE_COUNT :: 512
P99_GATE_NS :: i64(8_000_000)
RECORD_BYTES :: u64(32)

Callback_Context :: struct {
	registry:   ^bridge.Transaction_Capability_Registry,
	capability: bridge.Transaction_Capability,
	temporary:  base_runtime.Allocator,
	failure:    bridge.Failure_Context,
}

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
		fmt.eprintf("benchmark=racket-transaction-facade start_failure=%v\n", start_failure.code)
		os.exit(1)
	}
	registry: bridge.Transaction_Capability_Registry
	registry_ready, registry_failure := bridge.transaction_capability_registry_init(
		&registry,
		bridge.Registry_ID(73),
	)
	if !registry_ready {
		fmt.eprintf("benchmark=racket-transaction-facade registry_failure=%v\n", registry_failure.code)
		os.exit(1)
	}
	buffer: editor.Buffer
	buffer_ready, buffer_failure := editor.buffer_init(
		&buffer,
		editor.Buffer_ID(74),
		"abcd",
		editor.Allocator_Set{persistent = persistent, temporary = temporary},
	)
	if !buffer_ready {
		fmt.eprintf("benchmark=racket-transaction-facade buffer_failure=%v\n", buffer_failure.code)
		os.exit(1)
	}

	passed := benchmark_profile(
		&racket_runtime, &registry, &buffer, persistent, temporary, 7, "batch",
	)
	passed = benchmark_profile(
		&racket_runtime, &registry, &buffer, persistent, temporary, 8, "sequential",
	) && passed
	registry_closed, _ := bridge.transaction_capability_registry_close(&registry)
	buffer_closed, _ := editor.buffer_close(&buffer)
	runtime_stopped, _ := hosting.runtime_shutdown(&racket_runtime)
	persistent_live := persistent_tracking.current_memory_allocated
	temporary_live := temporary_tracking.current_memory_allocated
	cleanup_passed := registry_closed && buffer_closed && runtime_stopped &&
	                  persistent_live == 0 && temporary_live == 0
	fmt.printf(
		"benchmark=racket-transaction-facade cleanup_passed=%t persistent_live_bytes=%d temporary_live_bytes=%d\n",
		cleanup_passed,
		persistent_live,
		temporary_live,
	)
	mem.tracking_allocator_destroy(&temporary_tracking)
	mem.tracking_allocator_destroy(&persistent_tracking)
	if !passed || !cleanup_passed {
		os.exit(1)
	}
}

benchmark_profile :: proc(
	racket_runtime: ^hosting.Runtime,
	registry: ^bridge.Transaction_Capability_Registry,
	buffer: ^editor.Buffer,
	persistent, temporary: base_runtime.Allocator,
	scenario: i32,
	profile: string,
) -> bool {
	latencies: [SAMPLE_COUNT]i64
	for operation_index in 0 ..< WARMUP_COUNT + SAMPLE_COUNT {
		transaction: edit_transaction.Transaction
		identity := u64(scenario) * 10_000 + u64(operation_index) + 1
		transaction_ready, _ := edit_transaction.transaction_begin(
			&transaction,
			edit_transaction.Transaction_ID(identity),
			edit_transaction.Undo_Unit_ID(identity),
			buffer,
			edit_transaction.Origin{kind = .Racket, descriptor = "benchmark"},
			profile,
			edit_transaction.Allocator_Set{persistent = persistent, temporary = temporary},
		)
		if !transaction_ready {
			return false
		}
		capability, acquired, _ := bridge.transaction_capability_acquire(
			registry,
			&transaction,
			buffer,
			identity,
		)
		if !acquired {
			return false
		}
		callback_context := Callback_Context {
			registry = registry,
			capability = capability,
			temporary = temporary,
		}
		started_call := time.tick_now()
		called, _ := hosting.runtime_transaction_command(
			racket_runtime,
			scenario,
			u64(capability),
			identity,
			0,
			4,
			"uppercase-current-line",
			transaction_callback,
			&callback_context,
		)
		elapsed := time.duration_nanoseconds(time.tick_since(started_call))
		bridge.transaction_capability_release(registry, &capability)
		edit_transaction.transaction_abort(&transaction)
		edit_transaction.transaction_close(&transaction)
		if !called || callback_context.failure.code != .None {
			return false
		}
		if operation_index >= WARMUP_COUNT {
			latencies[operation_index - WARMUP_COUNT] = elapsed
		}
	}
	slice.sort(latencies[:])
	p99 := percentile_nearest_rank(latencies[:], 99)
	passed := p99 <= P99_GATE_NS
	fmt.printf(
		"benchmark=racket-transaction-facade profile=%s warmup=%d samples=%d p50_ns=%d p95_ns=%d p99_ns=%d max_ns=%d gate_p99_ns=%d passed=%t\n",
		profile,
		WARMUP_COUNT,
		SAMPLE_COUNT,
		percentile_nearest_rank(latencies[:], 50),
		percentile_nearest_rank(latencies[:], 95),
		p99,
		latencies[len(latencies) - 1],
		P99_GATE_NS,
		passed,
	)
	return passed
}

transaction_callback :: proc "c" (
	user_data: rawptr,
	kind: hosting.Scoped_Capability_Kind,
	generation, token, command_id: u64,
	operation: i32,
	arg0, arg1: u64,
	input: ^u8,
	input_length: u64,
	output: ^u8,
	output_capacity: u64,
	output_length, value: ^u64,
	failure_code: ^u32,
	limit, actual: ^u64,
) -> i32 {
	context = base_runtime.default_context()
	callback := (^Callback_Context)(user_data)
	if callback == nil || kind != .Transaction || generation == 0 ||
	   token != u64(callback.capability) || output_length == nil ||
	   value == nil || failure_code == nil || limit == nil || actual == nil {
		return 2
	}
	output_length^ = 0
	value^ = 0
	failure_code^ = 0
	limit^ = 0
	actual^ = 0
	ok := false
	failure: bridge.Failure_Context
	switch operation {
	case 1:
		if output == nil || output_capacity > u64(max(int)) {
			return 2
		}
		copied: u64
		copied, ok, failure = bridge.transaction_capability_inspect(
			callback.registry,
			callback.capability,
			command_id,
			arg0,
			arg1,
			([^]u8)(output)[:int(output_capacity)],
		)
		output_length^ = copied
	case 2:
		record_bytes, multiplied := checked_mul(arg0, RECORD_BYTES)
		if !multiplied || record_bytes != arg1 || record_bytes > input_length ||
		   arg0 > u64(max(int)) || input_length > u64(max(int)) || input == nil {
			return 2
		}
		bytes := ([^]u8)(input)[:int(input_length)]
		records, allocation_error := make(
			[]bridge.Transaction_Edit_Record,
			int(arg0),
			callback.temporary,
		)
		if allocation_error != nil {
			return 2
		}
		defer delete(records, callback.temporary)
		for &record, index in records {
			offset := u64(index) * RECORD_BYTES
			record.start = little_u64(bytes, offset)
			record.end = little_u64(bytes, offset + 8)
			record.replacement_offset = little_u64(bytes, offset + 16)
			record.replacement_bytes = little_u64(bytes, offset + 24)
		}
		ok, failure = bridge.transaction_capability_apply_batch(
			callback.registry,
			callback.capability,
			command_id,
			records,
			bytes[record_bytes:],
			callback.temporary,
		)
	case 3:
		if input == nil || input_length > u64(max(int)) {
			return 2
		}
		ok, failure = bridge.transaction_capability_splice(
			callback.registry,
			callback.capability,
			command_id,
			arg0,
			arg1,
			string(([^]u8)(input)[:int(input_length)]),
		)
	case:
		return 2
	}
	if ok {
		return 0
	}
	callback.failure = failure
	failure_code^ = u32(edit_transaction.Failure_Code.Invalid_State)
	if failure.code == .Transaction_Failure {
		failure_code^ = u32(failure.transaction_code)
	}
	limit^ = failure.limit
	actual^ = failure.actual
	return 1
}

little_u64 :: proc(bytes: []u8, offset: u64) -> u64 {
	result := u64(0)
	for index in 0 ..< 8 {
		result |= u64(bytes[offset + u64(index)]) << (u64(index) * 8)
	}
	return result
}

checked_mul :: proc(left, right: u64) -> (u64, bool) {
	if left != 0 && right > max(u64) / left {
		return 0, false
	}
	return left * right, true
}

percentile_nearest_rank :: proc(values: []i64, percentile: int) -> i64 {
	index := (len(values) * percentile + 99) / 100 - 1
	return values[clamp(index, 0, len(values) - 1)]
}
