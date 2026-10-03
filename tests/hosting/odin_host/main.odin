// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

// The Odin-host probe enters a real embedded Racket CS runtime through a C adapter.
package main

import "core:fmt"
import "core:os"
import "core:slice"
import "core:time"

@(private)
RACKET_PROBE_LIBRARY :: #config(RACKET_PROBE_LIBRARY, "")

foreign import racket_probe {RACKET_PROBE_LIBRARY}

@(default_calling_convention="c")
foreign racket_probe {
	// odra_racket_probe_boot starts Racket CS and registers the embedded probe module.
	odra_racket_probe_boot :: proc() -> i32 ---
	// odra_racket_probe_boot_at starts Racket CS from one explicit boot-image directory.
	odra_racket_probe_boot_at :: proc(boot_directory: cstring) -> i32 ---
	// odra_racket_probe_call invokes one contained probe scenario.
	odra_racket_probe_call :: proc(input: i64, scenario: i32, output: ^i64) -> i32 ---
	// odra_racket_probe_transform copies one bounded byte payload through Racket.
	odra_racket_probe_transform :: proc(
		input: ^u8,
		length: u64,
		output: ^u8,
		output_capacity: u64,
		written: ^u64,
	) -> i32 ---
	// odra_racket_probe_force_collection completes one full Racket collection.
	odra_racket_probe_force_collection :: proc() -> i32 ---
	// odra_racket_probe_cumulative_memory_bytes returns Racket allocation since boot.
	odra_racket_probe_cumulative_memory_bytes :: proc(allocated_bytes: ^u64) -> i32 ---
	// odra_racket_probe_rss_kib returns current Linux resident memory in KiB.
	odra_racket_probe_rss_kib :: proc() -> u64 ---
	// odra_racket_probe_shutdown releases the embedded Racket CS runtime.
	odra_racket_probe_shutdown :: proc() -> i32 ---
}

main :: proc() {
	if len(os.args) == 2 && os.args[1] == "--cold" {
		if !run_cold_probe() {
			os.exit(1)
		}
		return
	}
	if len(os.args) == 2 && os.args[1] == "--benchmark" {
		if !run_benchmark_probe() {
			os.exit(1)
		}
		return
	}

	run_boundary_tests()
}

@(private)
run_boundary_tests :: proc() {
	assert(
		odra_racket_probe_boot_at("/odra-missing-racket-runtime") == 0,
		"missing Racket boot files were accepted",
	)
	assert(odra_racket_probe_boot() == 1, "embedded Racket boot failed")

	result: i64
	status := odra_racket_probe_call(41, 0, &result)
	assert(status == 0, "embedded Racket round trip failed")
	assert(result == 42, "embedded Racket returned the wrong value")
	fmt.printfln("odin-host: %d", result)

	for scenario: i32 = 1; scenario <= 4; scenario += 1 {
		status = odra_racket_probe_call(41, scenario, &result)
		assert(status == 1, "embedded Racket failure escaped its boundary")
	}

	assert(odra_racket_probe_shutdown() == 1, "embedded Racket shutdown failed")
	assert(odra_racket_probe_call(41, 0, &result) == 2, "call after shutdown was accepted")
	assert(odra_racket_probe_shutdown() == 0, "duplicate shutdown was accepted")
}

@(private)
run_cold_probe :: proc() -> bool {
	started := time.tick_now()
	if odra_racket_probe_boot() != 1 {
		return false
	}
	result: i64
	if odra_racket_probe_call(41, 0, &result) != 0 || result != 42 {
		return false
	}
	boot_module_ns := time.duration_nanoseconds(time.tick_since(started))
	if odra_racket_probe_force_collection() != 1 {
		return false
	}
	rss_kib := odra_racket_probe_rss_kib()
	shutdown_started := time.tick_now()
	if odra_racket_probe_shutdown() != 1 {
		return false
	}
	shutdown_ns := time.duration_nanoseconds(time.tick_since(shutdown_started))
	fmt.printfln(
		"candidate=odin-host metric=cold boot_module_ns=%d rss_kib=%d shutdown_ns=%d",
		boot_module_ns,
		rss_kib,
		shutdown_ns,
	)
	return true
}

@(private)
run_benchmark_probe :: proc() -> bool {
	baseline_rss_kib := odra_racket_probe_rss_kib()
	boot_started := time.tick_now()
	if odra_racket_probe_boot() != 1 {
		return false
	}
	result: i64
	if odra_racket_probe_call(41, 0, &result) != 0 || result != 42 {
		return false
	}
	boot_module_ns := time.duration_nanoseconds(time.tick_since(boot_started))
	fmt.printfln(
		"candidate=odin-host metric=boot-module elapsed_ns=%d gate_ns=%d passed=%t",
		boot_module_ns,
		1_000_000_000,
		boot_module_ns <= 1_000_000_000,
	)
	if odra_racket_probe_force_collection() != 1 {
		return false
	}
	rss_kib := odra_racket_probe_rss_kib()
	rss_increase_kib := rss_kib - baseline_rss_kib if rss_kib >= baseline_rss_kib else 0
	fmt.printfln(
		"candidate=odin-host metric=idle-memory rss_kib=%d increase_kib=%d gate_kib=%d passed=%t",
		rss_kib,
		rss_increase_kib,
		256 * 1024,
		rss_increase_kib <= 256 * 1024,
	)

	passed := benchmark_scalar_calls() &&
		benchmark_exception_calls() &&
		benchmark_payload(4 * 1024, 32, 256, 5_000_000) &&
		benchmark_payload(1024 * 1024, 4, 40, 100_000_000)
	if odra_racket_probe_force_collection() != 1 {
		return false
	}
	repeated_rss_kib := odra_racket_probe_rss_kib()
	repeated_passed := repeated_rss_kib <= rss_kib + 16 * 1024
	fmt.printfln(
		"candidate=odin-host metric=repeated crossings=10000 rss_kib=%d growth_gate_kib=%d passed=%t",
		repeated_rss_kib,
		16 * 1024,
		repeated_passed,
	)

	shutdown_started := time.tick_now()
	shutdown_ok := odra_racket_probe_shutdown() == 1
	shutdown_ns := time.duration_nanoseconds(time.tick_since(shutdown_started))
	shutdown_passed := shutdown_ok && shutdown_ns <= 1_000_000_000
	fmt.printfln(
		"candidate=odin-host metric=shutdown elapsed_ns=%d gate_ns=%d passed=%t",
		shutdown_ns,
		1_000_000_000,
		shutdown_passed,
	)
	return boot_module_ns <= 1_000_000_000 && passed && repeated_passed && shutdown_passed
}

@(private)
benchmark_scalar_calls :: proc() -> bool {
	latencies := make([]i64, 10_000)
	defer delete(latencies)
	result: i64
	for operation in 0 ..< 10_100 {
		started := time.tick_now()
		status := odra_racket_probe_call(41, 0, &result)
		elapsed := time.duration_nanoseconds(time.tick_since(started))
		if status != 0 || result != 42 {
			return false
		}
		if operation >= 100 {
			latencies[operation - 100] = elapsed
		}
	}
	return report_latency("odin-host", "scalar", latencies, 1_000_000)
}

@(private)
benchmark_exception_calls :: proc() -> bool {
	latencies := make([]i64, 1_000)
	defer delete(latencies)
	result: i64
	for operation in 0 ..< 1_032 {
		started := time.tick_now()
		status := odra_racket_probe_call(41, 3, &result)
		elapsed := time.duration_nanoseconds(time.tick_since(started))
		if status != 1 {
			return false
		}
		if operation >= 32 {
			latencies[operation - 32] = elapsed
		}
	}
	return report_latency("odin-host", "exception", latencies, 10_000_000)
}

@(private)
benchmark_payload :: proc(
	byte_count: int,
	warmup_count: int,
	sample_count: int,
	gate_ns: i64,
) -> bool {
	input := make([]u8, byte_count)
	output := make([]u8, byte_count)
	latencies := make([]i64, sample_count)
	defer delete(input)
	defer delete(output)
	defer delete(latencies)
	for &value in input {
		value = 'a'
	}
	allocated_before: u64
	if odra_racket_probe_cumulative_memory_bytes(&allocated_before) != 1 {
		return false
	}

	total_operations := warmup_count + sample_count
	for operation in 0 ..< total_operations {
		written: u64
		started := time.tick_now()
		status := odra_racket_probe_transform(
			raw_data(input),
			u64(byte_count),
			raw_data(output),
			u64(len(output)),
			&written,
		)
		valid_output := true
		for value in output {
			if value != 'a' {
				valid_output = false
				break
			}
		}
		elapsed := time.duration_nanoseconds(time.tick_since(started))
		if status != 0 || written != u64(byte_count) || !valid_output {
			fmt.eprintfln(
				"payload benchmark failed: bytes=%d status=%d written=%d valid=%t",
				byte_count,
				status,
				written,
				valid_output,
			)
			return false
		}
		if operation >= warmup_count {
			latencies[operation - warmup_count] = elapsed
		}
	}
	allocated_after: u64
	if odra_racket_probe_cumulative_memory_bytes(&allocated_after) != 1 || allocated_after < allocated_before {
		return false
	}
	allocated_per_call := (allocated_after - allocated_before) / u64(total_operations)
	fmt.printfln(
		"candidate=odin-host metric=payload-allocation bytes=%d allocated_bytes_per_call=%d",
		byte_count,
		allocated_per_call,
	)
	return report_latency("odin-host", fmt.tprintf("payload-%d", byte_count), latencies, gate_ns)
}

@(private)
report_latency :: proc(candidate: string, metric: string, latencies: []i64, gate_ns: i64) -> bool {
	slice.sort(latencies)
	p50 := percentile_nearest_rank(latencies, 50)
	p95 := percentile_nearest_rank(latencies, 95)
	p99 := percentile_nearest_rank(latencies, 99)
	passed := p99 <= gate_ns
	fmt.printfln(
		"candidate=%s metric=%s samples=%d p50_ns=%d p95_ns=%d p99_ns=%d max_ns=%d gate_ns=%d passed=%t",
		candidate,
		metric,
		len(latencies),
		p50,
		p95,
		p99,
		latencies[len(latencies) - 1],
		gate_ns,
		passed,
	)
	return passed
}

@(private)
percentile_nearest_rank :: proc(sorted_values: []i64, percentile: int) -> i64 {
	assert(len(sorted_values) > 0)
	rank := (len(sorted_values) * percentile + 99) / 100
	return sorted_values[rank - 1]
}
