// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../../src/editor"
import "../reference"
import "../storage_probe"
import "core:fmt"
import "core:os"
import "core:slice"
import "core:time"

SEED :: u64(0x4f44_5241_0000_0001)
INITIAL_BYTES :: 1024 * 1024
OPERATION_COUNT :: 128
SPLICE_TEXT_BYTES :: 100 * 1024 * 1024
SPLICE_WARMUP_COUNT :: 32
SPLICE_SAMPLE_COUNT :: 256
LARGE_SPLICE_WARMUP_COUNT :: 5
LARGE_SPLICE_SAMPLE_COUNT :: 40
LOCALIZED_P99_GATE_NS :: i64(2_000_000)
ALTERNATING_P99_GATE_NS :: i64(5_000_000)
LARGE_P95_GATE_NS :: i64(25_000_000)

main :: proc() {
	run_storage_probe()
	run_persistent_rope_probe()
	run_reference_probe()
	if !run_splice_probe() {
		os.exit(1)
	}
}

run_storage_probe :: proc() {
	probe, ok := storage_probe.probe_build_uniform(100 * 1024 * 1024)
	if !ok {
		fmt.eprintln("storage probe initialization failed")
		return
	}
	defer storage_probe.probe_deinit(&probe)

	started := time.tick_now()
	visits := u64(0)
	for sample in 0 ..< 100_000 {
		offset := u64(sample) * probe.text_bytes / 100_000
		_, _, path_visits, locate_ok := storage_probe.probe_locate(&probe, offset)
		if !locate_ok {
			fmt.eprintf("storage traversal failed at sample %d\n", sample)
			return
		}
		visits += path_visits
	}
	elapsed := time.tick_since(started)

	fmt.printf(
		"benchmark=storage-layout text_bytes=%d leaves=%d nodes=%d levels=%d estimated_bytes=%d traversals=%d path_visits=%d elapsed_ns=%d\n",
		probe.text_bytes,
		len(probe.leaves),
		storage_probe.probe_node_count(&probe),
		storage_probe.probe_tree_levels(&probe),
		storage_probe.probe_estimated_persistent_bytes(&probe),
		100_000,
		visits,
		time.duration_nanoseconds(elapsed),
	)
}

run_persistent_rope_probe :: proc() {
	text_bytes := 100 * 1024 * 1024
	contents := make([]byte, text_bytes)
	defer delete(contents)
	for &value in contents {
		value = 'a'
	}

	buffer: editor.Buffer
	started_build := time.tick_now()
	initialized, failure := editor.buffer_init(
		&buffer,
		editor.Buffer_ID(1),
		string(contents),
		editor.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	build_elapsed := time.tick_since(started_build)
	if !initialized {
		fmt.eprintf("persistent rope initialization failed: %v\n", failure.code)
		return
	}

	stats, stats_ok, stats_failure := editor.buffer_stats(&buffer)
	if !stats_ok {
		fmt.eprintf("persistent rope stats failed: %v\n", stats_failure.code)
		editor.buffer_close(&buffer)
		return
	}
	if stats.persistent_bytes > 135 * 1024 * 1024 {
		fmt.eprintf("persistent rope exceeded allocation target: %d\n", stats.persistent_bytes)
		editor.buffer_close(&buffer)
		return
	}

	inspection := make([]byte, int(editor.MAX_INSPECTION_BYTES))
	defer delete(inspection)
	started_inspection := time.tick_now()
	inspected := u64(0)
	for inspected < u64(text_bytes) {
		remaining := u64(text_bytes) - inspected
		length := min(remaining, editor.MAX_INSPECTION_BYTES)
		copied, inspect_ok, inspect_failure := editor.buffer_inspect(
			&buffer,
			editor.Byte_Offset(inspected),
			editor.Byte_Offset(inspected + length),
			inspection[:int(length)],
		)
		if !inspect_ok || copied != length {
			fmt.eprintf("persistent rope inspection failed: %v\n", inspect_failure.code)
			editor.buffer_close(&buffer)
			return
		}
		inspected += copied
	}
	inspection_elapsed := time.tick_since(started_inspection)

	started_close := time.tick_now()
	closed, close_failure := editor.buffer_close(&buffer)
	close_elapsed := time.tick_since(started_close)
	if !closed {
		fmt.eprintf("persistent rope close failed: %v\n", close_failure.code)
		return
	}

	fmt.printf(
		"benchmark=persistent-rope text_bytes=%d chunks=%d nodes=%d levels=%d persistent_bytes=%d build_ns=%d inspect_ns=%d close_ns=%d\n",
		stats.text_bytes,
		stats.chunk_count,
		stats.node_count,
		stats.tree_height,
		stats.persistent_bytes,
		time.duration_nanoseconds(build_elapsed),
		time.duration_nanoseconds(inspection_elapsed),
		time.duration_nanoseconds(close_elapsed),
	)
}

run_reference_probe :: proc() {
	initial := make([]u8, INITIAL_BYTES)
	defer delete(initial)
	for index in 0 ..< len(initial) {
		initial[index] = 'a'
	}

	model, failure, ok := reference.model_init(transmute(string)initial)
	if !ok {
		fmt.eprintf("benchmark initialization failed: %v\n", failure.code)
		return
	}
	defer reference.model_deinit(&model)

	generator := reference.generator_init(SEED)
	started := time.tick_now()
	for operation_index in 0 ..< OPERATION_COUNT {
		operation := reference.generator_next(&generator, &model)
		splice, splice_ok := reference.operation_splice(&model, operation)
		if !splice_ok {
			fmt.eprintf("operation %d could not be materialized\n", operation_index)
			return
		}
		apply_failure, apply_ok := reference.model_splice(&model, splice)
		if !apply_ok {
			fmt.eprintf("operation %d failed: %v\n", operation_index, apply_failure.code)
			return
		}
	}
	elapsed := time.tick_since(started)

	fmt.printf(
		"benchmark=contiguous-reference seed=%d initial_bytes=%d operations=%d result_bytes=%d elapsed_ns=%d\n",
		SEED,
		INITIAL_BYTES,
		OPERATION_COUNT,
		len(model.bytes),
		time.duration_nanoseconds(elapsed),
	)
}

run_splice_probe :: proc() -> bool {
	contents := make([]byte, SPLICE_TEXT_BYTES)
	defer delete(contents)
	for &value in contents {
		value = 'a'
	}

	buffer: editor.Buffer
	initialized, init_failure := editor.buffer_init(
		&buffer,
		editor.Buffer_ID(2),
		string(contents),
		editor.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	if !initialized {
		fmt.eprintf("splice benchmark initialization failed: %v\n", init_failure.code)
		return false
	}

	initial_stats, initial_stats_ok, initial_stats_failure := editor.buffer_stats(&buffer)
	if !initial_stats_ok {
		fmt.eprintf("splice benchmark stats failed: %v\n", initial_stats_failure.code)
		editor.buffer_close(&buffer)
		return false
	}
	if initial_stats.persistent_bytes > 135 * 1024 * 1024 {
		fmt.eprintf("splice benchmark exceeded initial allocation gate: %d\n", initial_stats.persistent_bytes)
		editor.buffer_close(&buffer)
		return false
	}

	localized_ok := benchmark_fixed_splices(
		&buffer,
		"localized-splice",
		SPLICE_TEXT_BYTES / 2,
		1,
		[2]string{"x", "y"},
		false,
		SPLICE_WARMUP_COUNT,
		SPLICE_SAMPLE_COUNT,
		99,
		LOCALIZED_P99_GATE_NS,
	)
	alternating_ok := benchmark_fixed_splices(
		&buffer,
		"alternating-distant-splice",
		1,
		1,
		[2]string{"m", "n"},
		true,
		SPLICE_WARMUP_COUNT,
		SPLICE_SAMPLE_COUNT,
		99,
		ALTERNATING_P99_GATE_NS,
	)

	large_a := make([]byte, 1024 * 1024)
	large_b := make([]byte, 1024 * 1024)
	defer delete(large_a)
	defer delete(large_b)
	for &value in large_a {
		value = 'b'
	}
	for &value in large_b {
		value = 'c'
	}
	large_ok := benchmark_fixed_splices(
		&buffer,
		"one-mib-replacement",
		SPLICE_TEXT_BYTES / 2,
		1024 * 1024,
		[2]string{string(large_a), string(large_b)},
		false,
		LARGE_SPLICE_WARMUP_COUNT,
		LARGE_SPLICE_SAMPLE_COUNT,
		95,
		LARGE_P95_GATE_NS,
	)

	final_stats, final_stats_ok, final_stats_failure := editor.buffer_stats(&buffer)
	if !final_stats_ok {
		fmt.eprintf("splice benchmark final stats failed: %v\n", final_stats_failure.code)
		editor.buffer_close(&buffer)
		return false
	}
	closed, close_failure := editor.buffer_close(&buffer)
	if !closed {
		fmt.eprintf("splice benchmark close failed: %v\n", close_failure.code)
		return false
	}

	fmt.printf(
		"benchmark=atomic-splice-allocation text_bytes=%d initial_persistent_bytes=%d final_persistent_bytes=%d final_revision=%d\n",
		initial_stats.text_bytes,
		initial_stats.persistent_bytes,
		final_stats.persistent_bytes,
		u64(final_stats.revision),
	)
	return localized_ok && alternating_ok && large_ok
}

benchmark_fixed_splices :: proc(
	buffer: ^editor.Buffer,
	benchmark_name: string,
	fixed_start, removed_bytes: u64,
	replacements: [2]string,
	alternate_edges: bool,
	warmup_count, sample_count: int,
	gate_percentile: int,
	gate_nanoseconds: i64,
) -> bool {
	latencies := make([]i64, sample_count)
	defer delete(latencies)
	total_operations := warmup_count + sample_count
	for operation_index in 0 ..< total_operations {
		stats, stats_ok, stats_failure := editor.buffer_stats(buffer)
		if !stats_ok {
			fmt.eprintf("%s stats failed: %v\n", benchmark_name, stats_failure.code)
			return false
		}
		start_offset := fixed_start
		if alternate_edges {
			start_offset = 1 if operation_index % 2 == 0 else stats.text_bytes - removed_bytes - 1
		}
		start, start_ok, start_failure := editor.buffer_position(
			buffer,
			editor.Byte_Offset(start_offset),
		)
		end, end_ok, end_failure := editor.buffer_position(
			buffer,
			editor.Byte_Offset(start_offset + removed_bytes),
		)
		if !start_ok || !end_ok {
			failure := start_failure
			if start_ok {
				failure = end_failure
			}
			fmt.eprintf("%s position failed: %v\n", benchmark_name, failure.code)
			return false
		}

		replacement := replacements[operation_index % len(replacements)]
		started := time.tick_now()
		change_set, undo_record, published, publish_failure := editor.buffer_splice(
			buffer,
			editor.Splice {
				start = start,
				end = end,
				replacement = replacement,
			},
			context.temp_allocator,
		)
		elapsed := time.duration_nanoseconds(time.tick_since(started))
		if !published {
			fmt.eprintf("%s publication failed: %v\n", benchmark_name, publish_failure.code)
			return false
		}
		if change_set.base_revision != stats.revision ||
		   change_set.result_revision != editor.Revision(u64(stats.revision) + 1) ||
		   undo_record.result_revision != change_set.result_revision ||
		   u64(len(change_set.replacement_text)) != removed_bytes {
			fmt.eprintf("%s record validation failed\n", benchmark_name)
			return false
		}
		if operation_index >= warmup_count {
			latencies[operation_index - warmup_count] = elapsed
		}
	}

	slice.sort(latencies)
	p50 := percentile_nearest_rank(latencies, 50)
	p95 := percentile_nearest_rank(latencies, 95)
	p99 := percentile_nearest_rank(latencies, 99)
	gate_value := percentile_nearest_rank(latencies, gate_percentile)
	passed := gate_value <= gate_nanoseconds
	fmt.printf(
		"benchmark=%s warmup=%d samples=%d p50_ns=%d p95_ns=%d p99_ns=%d max_ns=%d gate_percentile=%d gate_ns=%d passed=%t\n",
		benchmark_name,
		warmup_count,
		sample_count,
		p50,
		p95,
		p99,
		latencies[len(latencies) - 1],
		gate_percentile,
		gate_nanoseconds,
		passed,
	)
	return passed
}

percentile_nearest_rank :: proc(sorted_values: []i64, percentile: int) -> i64 {
	assert(len(sorted_values) > 0)
	assert(percentile > 0 && percentile <= 100)
	rank := (len(sorted_values) * percentile + 99) / 100
	return sorted_values[rank - 1]
}
