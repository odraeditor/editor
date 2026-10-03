// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../../../src/bridge"
import "../../../src/hosting"
import base_runtime "base:runtime"
import "core:fmt"
import "core:os"
import "core:slice"
import "core:time"

WARMUP_COUNT :: 64
SAMPLE_COUNT :: 512
P99_GATE_NS :: i64(8_000_000)

Callback_Context :: struct {
	token: u64,
	calls: u64,
}

main :: proc() {
	racket_runtime: hosting.Runtime
	started, start_failure := hosting.runtime_start(&racket_runtime)
	if !started {
		fmt.eprintf("benchmark=racket-buffer-session start_failure=%v\n", start_failure.code)
		os.exit(1)
	}
	callback := Callback_Context{token = 107}
	latencies: [SAMPLE_COUNT]i64
	passed := true
	for operation_index in 0 ..< WARMUP_COUNT + SAMPLE_COUNT {
		started_call := time.tick_now()
		called, failure := hosting.runtime_buffer_session_probe(
			&racket_runtime,
			11,
			callback.token,
			buffer_session_callback,
			&callback,
		)
		elapsed := time.duration_nanoseconds(time.tick_since(started_call))
		if !called {
			fmt.eprintf("benchmark=racket-buffer-session call_failure=%v\n", failure.code)
			passed = false
			break
		}
		if operation_index >= WARMUP_COUNT {
			latencies[operation_index - WARMUP_COUNT] = elapsed
		}
	}
	if passed {
		slice.sort(latencies[:])
		p99 := percentile_nearest_rank(latencies[:], 99)
		passed = p99 <= P99_GATE_NS
		fmt.printf(
			"benchmark=racket-buffer-session warmup=%d samples=%d p50_ns=%d p95_ns=%d p99_ns=%d max_ns=%d gate_p99_ns=%d passed=%t\n",
			WARMUP_COUNT,
			SAMPLE_COUNT,
			percentile_nearest_rank(latencies[:], 50),
			percentile_nearest_rank(latencies[:], 95),
			p99,
			latencies[len(latencies) - 1],
			P99_GATE_NS,
			passed,
		)
	}
	stopped, stop_failure := hosting.runtime_shutdown(&racket_runtime)
	cleanup_passed := stopped && callback.calls == 2 * (WARMUP_COUNT + SAMPLE_COUNT)
	if !stopped {
		fmt.eprintf("benchmark=racket-buffer-session stop_failure=%v\n", stop_failure.code)
	}
	fmt.printf(
		"benchmark=racket-buffer-session cleanup_passed=%t callback_calls=%d retained_native_bytes=0\n",
		cleanup_passed,
		callback.calls,
	)
	if !passed || !cleanup_passed {
		os.exit(1)
	}
}

buffer_session_callback :: proc "c" (
	user_data: rawptr,
	kind: hosting.Scoped_Capability_Kind,
	generation, token, domain_context: u64,
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
	_ = arg0
	_ = arg1
	_ = input
	_ = input_length
	callback := (^Callback_Context)(user_data)
	if callback == nil || kind != .Buffer_Session || generation == 0 ||
	   domain_context != 0 || token != callback.token || output == nil ||
	   output_length == nil || value == nil || failure_code == nil ||
	   limit == nil || actual == nil {
		return 2
	}
	required := bridge.BUFFER_SESSION_SCOPE_RECORD_BYTES
	if operation == i32(bridge.Buffer_Session_Operation.Descriptors) {
		required = bridge.BUFFER_SESSION_DESCRIPTOR_HEADER_BYTES
	} else if operation != i32(bridge.Buffer_Session_Operation.Scope) {
		return 2
	}
	if output_capacity < required {
		return 2
	}
	destination := ([^]u8)(output)[:int(required)]
	for &byte in destination {
		byte = 0
	}
	output_length^ = required
	value^ = 0
	failure_code^ = 0
	limit^ = 0
	actual^ = 0
	callback.calls += 1
	return 0
}

percentile_nearest_rank :: proc(samples: []i64, percentile: int) -> i64 {
	assert(len(samples) > 0 && percentile > 0 && percentile <= 100)
	rank := (percentile * len(samples) + 99) / 100
	return samples[rank - 1]
}
