// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import interactive_session "../../src/interactive_session"
import terminal_emulator "../../src/terminal_emulator"
import terminal_session "../../src/terminal_session"
import "base:runtime"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:slice"
import "core:strconv"
import "core:strings"
import "core:time"

MAX_PROFILE_NANOSECONDS :: i64(5_000_000_000)
MAX_REVISION_NANOSECONDS :: i64(500_000_000)
MAX_RESIZE_NANOSECONDS :: i64(500_000_000)
MIN_OUTPUT_BYTES_PER_SECOND :: u64(256 * 1_024)
MAX_RESIDENT_DELTA_KIB :: u64(128 * 1_024)
SYNTHETIC_OUTPUT_BYTES :: 4 * 1_024 * 1_024
STRESS_CHUNK_BYTES :: 16 * 1_024

Failing_Allocator :: struct {
	backing: runtime.Allocator,
	fail:    bool,
}

main :: proc() {
	valid := print_policy()
	valid = run_real_output() && valid
	valid = run_synthetic_state() && valid
	valid = run_faults() && valid
	if !valid do os.exit(1)
}

print_policy :: proc() -> bool {
	valid := terminal_session.DEFAULT_LIMITS.output_turn_bytes == 256 * 1_024 &&
		terminal_session.DEFAULT_LIMITS.output_turn_nanoseconds == 4_000_000 &&
		terminal_session.DEFAULT_LIMITS.scrollback_bytes == 32 * 1_024 * 1_024 &&
		terminal_session.DEFAULT_LIMITS.scrollback_rows == 100_000 &&
		terminal_session.DEFAULT_LIMITS.state_bytes == 64 * 1_024 * 1_024 &&
		terminal_session.DEFAULT_LIMITS.copied_text_bytes == 1 * 1_024 * 1_024 &&
		terminal_session.MAX_PROJECTED_CELLS == 1_048_576 &&
		terminal_session.MAX_STATE_BYTES == 128 * 1_024 * 1_024 &&
		terminal_emulator.IMAGE_DECODED_BYTES == 16 * 1_024 * 1_024 &&
		terminal_emulator.IMAGE_STORAGE_BYTES == 32 * 1_024 * 1_024
	fmt.printf(
		"study=terminal-session profile=policy valid=%v turn_bytes=%d turn_ns=%d scrollback_bytes=%d scrollback_rows=%d state_bytes=%d copied_text_bytes=%d cells=%d\n",
		valid,
		terminal_session.DEFAULT_LIMITS.output_turn_bytes,
		terminal_session.DEFAULT_LIMITS.output_turn_nanoseconds,
		terminal_session.DEFAULT_LIMITS.scrollback_bytes,
		terminal_session.DEFAULT_LIMITS.scrollback_rows,
		terminal_session.DEFAULT_LIMITS.state_bytes,
		terminal_session.DEFAULT_LIMITS.copied_text_bytes,
		terminal_session.MAX_PROJECTED_CELLS,
	)
	return valid
}

run_real_output :: proc() -> bool {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	rss_before := resident_memory_kib()
	registry: terminal_session.Registry
	initialized, failure := terminal_session.registry_init(&registry, allocator)
	if !initialized {
		fmt.printf("study=terminal-session profile=real-output valid=false failure=%v\n", failure.code)
		mem.tracking_allocator_destroy(&tracking)
		return false
	}
	arguments := []string {
		"-c",
		"dd if=/dev/zero bs=65536 count=8 2>/dev/null | tr '\\000' x; sleep 0.05",
	}
	request := open_request("real-output", arguments)
	record: terminal_session.Session_Record
	opened: bool
	record, opened, failure = terminal_session.registry_open(&registry, request)
	if !opened {
		_, _ = terminal_session.registry_close(&registry)
		mem.tracking_allocator_destroy(&tracking)
		return false
	}
	started_at := time.tick_now()
	parsed_bytes: u64
	turns: int
	frames: int
	damaged_cells: u64
	first_revision_ns: i64
	revision_latencies: [256]i64
	revision_latency_count: int
	completed := false
	for turn in 0 ..< 20_000 {
		turns = turn + 1
		turn_started := time.tick_now()
		observation, stepped := terminal_session.registry_step_output(
			&registry, record.ref, i64(turn + 1),
		)
		if !stepped {
			failure = observation.failure
			break
		}
		parsed_bytes += observation.parsed_bytes
		if observation.parsed_bytes > 0 {
			revision, projected, projection_failure := terminal_session.registry_project_render(
				&registry, record.ref,
			)
			if !projected {
				failure = projection_failure
				break
			}
			frames += 1
			damaged_cells += revision.projection.damaged_cells
			if first_revision_ns == 0 {
				first_revision_ns = time.duration_nanoseconds(time.tick_since(turn_started))
			}
			if revision_latency_count < len(revision_latencies) {
				revision_latencies[revision_latency_count] =
					time.duration_nanoseconds(time.tick_since(turn_started))
				revision_latency_count += 1
			}
		}
		current, found, record_failure := terminal_session.registry_record(&registry, record.ref)
		if !found {
			failure = record_failure
			break
		}
		record = current
		if current.lifecycle == .Exited && !observation.output_pending {
			completed = true
			break
		}
		if !observation.progress do time.sleep(time.Millisecond)
	}
	elapsed_ns := time.duration_nanoseconds(time.tick_since(started_at))
	throughput := u64(0)
	if elapsed_ns > 0 do throughput = parsed_bytes * 1_000_000_000 / u64(elapsed_ns)
	peak_owned := tracking.peak_memory_allocated
	peak_rss := resident_memory_kib()
	emulator_ref := record.emulator
	closed, close_failure := terminal_session.registry_close(&registry)
	if !closed && failure.code == .None do failure = close_failure
	emulator_stats, emulator_result := terminal_emulator.stats(emulator_ref)
	zero_owned := tracking.current_memory_allocated == 0
	rss_delta := peak_rss - min(peak_rss, rss_before)
	valid := completed && failure.code == .None && parsed_bytes >= 512 * 1_024 &&
		frames > 0 && damaged_cells > 0 && first_revision_ns > 0 &&
		first_revision_ns <= MAX_REVISION_NANOSECONDS &&
		throughput >= MIN_OUTPUT_BYTES_PER_SECOND && elapsed_ns <= MAX_PROFILE_NANOSECONDS &&
		peak_owned <= i64(terminal_session.DEFAULT_LIMITS.state_bytes) &&
		rss_delta <= MAX_RESIDENT_DELTA_KIB && zero_owned &&
		emulator_result == .OK && !emulator_stats.live && emulator_stats.live_bytes == 0
	slice.sort(revision_latencies[:revision_latency_count])
	fmt.printf(
		"study=terminal-session profile=real-output valid=%v turns=%d parsed_bytes=%d throughput_bytes_s=%d frames=%d damaged_cells=%d first_revision_ns=%d revision_p50_ns=%d revision_p95_ns=%d revision_p99_ns=%d peak_owned_bytes=%d rss_delta_kib=%d elapsed_ns=%d failure=%v foreign_live_bytes=%d\n",
		valid,
		turns,
		parsed_bytes,
		throughput,
		frames,
		damaged_cells,
		first_revision_ns,
		study_percentile(revision_latencies[:revision_latency_count], 50),
		study_percentile(revision_latencies[:revision_latency_count], 95),
		study_percentile(revision_latencies[:revision_latency_count], 99),
		peak_owned,
		rss_delta,
		elapsed_ns,
		failure.code,
		emulator_stats.live_bytes,
	)
	mem.tracking_allocator_destroy(&tracking)
	return valid
}

run_synthetic_state :: proc() -> bool {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	rss_before := resident_memory_kib()
	registry: terminal_session.Registry
	initialized, failure := terminal_session.registry_init(&registry, allocator)
	if !initialized {
		mem.tracking_allocator_destroy(&tracking)
		return false
	}
	arguments := []string{"-c", "sleep 30"}
	request := open_request("synthetic-state", arguments)
	request.process.limits.columns = 120
	request.process.limits.rows = 40
	record: terminal_session.Session_Record
	opened: bool
	record, opened, failure = terminal_session.registry_open(&registry, request)
	if !opened {
		_, _ = terminal_session.registry_close(&registry)
		mem.tracking_allocator_destroy(&tracking)
		return false
	}
	chunk: [STRESS_CHUNK_BYTES]u8
	for &value, index in chunk {
		switch index % 82 {
		case 80: value = '\r'
		case 81: value = '\n'
		case:    value = u8('a' + index % 26)
		}
	}
	started_at := time.tick_now()
	written: u64
	for written < SYNTHETIC_OUTPUT_BYTES {
		if result := terminal_emulator.write(record.emulator, chunk[:]); result != .OK {
			failure = terminal_session.Failure_Record {
				stage = .Parse,
				code = .Emulator,
				emulator_result = result,
			}
			break
		}
		written += len(chunk)
	}
	peak_rss := max(rss_before, resident_memory_kib())
	revision, projected, projection_failure := terminal_session.registry_project_render(
		&registry, record.ref,
	)
	if !projected && failure.code == .None do failure = projection_failure
	scrollback, inspected, scrollback_failure := terminal_session.registry_scrollback(
		&registry, record.ref,
	)
	if !inspected && failure.code == .None do failure = scrollback_failure
	text := make([]u8, int(terminal_session.DEFAULT_LIMITS.copied_text_bytes), allocator)
	snapshot, copied, copy_failure := terminal_session.registry_copy_text(
		&registry,
		record.ref,
		terminal_session.Text_Request{scope = .Screen, normalized = true},
		text,
	)
	if !copied && failure.code == .None do failure = copy_failure
	delete(text, allocator)
	max_resize_ns: i64
	resize_latencies: [32]i64
	for resize_index in 0 ..< 32 {
		columns := u16(80 if resize_index % 2 == 0 else 120)
		rows := u16(24 if resize_index % 2 == 0 else 40)
		resize_started := time.tick_now()
		resized, resize_failure := terminal_session.registry_resize(
			&registry, record.ref, columns, rows, 8, 16,
		)
		resize_ns := time.duration_nanoseconds(time.tick_since(resize_started))
		max_resize_ns = max(max_resize_ns, resize_ns)
		resize_latencies[resize_index] = resize_ns
		if !resized {
			failure = resize_failure
			break
		}
	}
	compression_steps: int
	compression_supported := false
	compression_complete := false
	for compression_index in 0 ..< 4_096 {
		compression_steps = compression_index + 1
		compression, compressed, compression_failure :=
			terminal_session.registry_compress_scrollback(&registry, record.ref)
		if !compressed {
			failure = compression_failure
			break
		}
		compression_supported = compression.supported
		if !compression.supported || !compression.pending {
			compression_complete = true
			break
		}
	}
	elapsed_ns := time.duration_nanoseconds(time.tick_since(started_at))
	foreign_stats, stats_result := terminal_emulator.stats(record.emulator)
	peak_owned := tracking.peak_memory_allocated
	peak_rss = max(peak_rss, resident_memory_kib())
	emulator_ref := record.emulator
	closed, close_failure := terminal_session.registry_close(&registry)
	if !closed && failure.code == .None do failure = close_failure
	closed_stats, closed_stats_result := terminal_emulator.stats(emulator_ref)
	zero_owned := tracking.current_memory_allocated == 0
	rss_delta := peak_rss - min(peak_rss, rss_before)
	valid := failure.code == .None && written == SYNTHETIC_OUTPUT_BYTES &&
		projected && revision.projection.damaged_cells > 0 && inspected &&
		scrollback.scrollback_rows > 0 &&
		scrollback.scrollback_max_bytes == terminal_session.DEFAULT_LIMITS.scrollback_bytes &&
		scrollback.scrollback_max_rows == terminal_session.DEFAULT_LIMITS.scrollback_rows &&
		copied && snapshot.truncated && snapshot.copied_bytes <= snapshot.limit_bytes &&
		max_resize_ns <= MAX_RESIZE_NANOSECONDS && compression_steps > 0 && compression_complete &&
		elapsed_ns <= MAX_PROFILE_NANOSECONDS &&
		peak_owned <= i64(terminal_session.DEFAULT_LIMITS.state_bytes) &&
		foreign_stats.peak_bytes <= terminal_session.DEFAULT_LIMITS.state_bytes &&
		rss_delta <= MAX_RESIDENT_DELTA_KIB && zero_owned &&
		stats_result == .OK && closed_stats_result == .OK && !closed_stats.live &&
		closed_stats.live_bytes == 0
	slice.sort(resize_latencies[:])
	fmt.printf(
		"study=terminal-session profile=synthetic-state valid=%v output_bytes=%d scrollback_rows=%d copied_bytes=%d required_bytes=%d truncated=%v damaged_cells=%d resize_p50_ns=%d resize_p95_ns=%d resize_p99_ns=%d max_resize_ns=%d compression_steps=%d compression_supported=%v compression_complete=%v peak_owned_bytes=%d foreign_peak_bytes=%d rss_delta_kib=%d elapsed_ns=%d failure=%v foreign_live_bytes=%d\n",
		valid,
		written,
		scrollback.scrollback_rows,
		snapshot.copied_bytes,
		snapshot.required_bytes,
		snapshot.truncated,
		revision.projection.damaged_cells,
		study_percentile(resize_latencies[:], 50),
		study_percentile(resize_latencies[:], 95),
		study_percentile(resize_latencies[:], 99),
		max_resize_ns,
		compression_steps,
		compression_supported,
		compression_complete,
		peak_owned,
		foreign_stats.peak_bytes,
		rss_delta,
		elapsed_ns,
		failure.code,
		closed_stats.live_bytes,
	)
	mem.tracking_allocator_destroy(&tracking)
	return valid
}

study_percentile :: proc(sorted: []i64, percentile: int) -> i64 {
	if len(sorted) == 0 || percentile <= 0 || percentile > 100 do return 0
	rank := (len(sorted) * percentile + 99) / 100
	return sorted[rank - 1]
}

run_faults :: proc() -> bool {
	failing := Failing_Allocator{backing = context.allocator, fail = true}
	registry: terminal_session.Registry
	initialized, init_failure := terminal_session.registry_init(
		&registry, failing_allocator(&failing),
	)
	init_rejected := !initialized && init_failure.code == .Allocation && registry.state == nil
	failing.fail = false
	initialize_failure: terminal_session.Failure_Record
	initialized, initialize_failure = terminal_session.registry_init(
		&registry, failing_allocator(&failing),
	)
	arguments := []string{"-c", "sleep 30"}
	allocation_fault := open_request("allocation-fault", arguments)
	failing.fail = true
	_, allocation_opened, allocation_failure := terminal_session.registry_open(
		&registry, allocation_fault,
	)
	failing.fail = false
	emulator_fault := open_request("emulator-fault", arguments)
	emulator_fault.emulator.allocation_fail_after = 1
	_, emulator_opened, emulator_failure := terminal_session.registry_open(
		&registry, emulator_fault,
	)
	stats, inspected, inspect_failure := terminal_session.registry_inspect(&registry)
	closed, close_failure := terminal_session.registry_close(&registry)
	valid := init_rejected && initialized && initialize_failure.code == .None &&
		!allocation_opened && allocation_failure.code == .Allocation &&
		!emulator_opened && emulator_failure.code == .Emulator && inspected &&
		inspect_failure.code == .None && stats.session_count == 0 && closed &&
		close_failure.code == .None
	fmt.printf(
		"study=terminal-session profile=faults valid=%v init_failure=%v allocation_failure=%v emulator_failure=%v sessions=%d close_failure=%v\n",
		valid,
		init_failure.code,
		allocation_failure.code,
		emulator_failure.code,
		stats.session_count,
		close_failure.code,
	)
	return valid
}

open_request :: proc(name: string, arguments: []string) -> terminal_session.Open_Request {
	return terminal_session.Open_Request {
		process = interactive_session.Session_Prepare_Request {
			name = name,
			owner_kind = .Task,
			owner_label = "terminal session resource study",
			working_directory = "/tmp",
			limits = interactive_session.DEFAULT_LIMITS,
		},
		start = interactive_session.Process_Start_Request {
			executable = "/bin/sh",
			arguments = arguments,
			working_directory = "/tmp",
			columns = 80,
			rows = 24,
		},
		emulator = terminal_emulator.DEFAULT_OPTIONS,
		limits = terminal_session.DEFAULT_LIMITS,
	}
}

failing_allocator :: proc(state: ^Failing_Allocator) -> runtime.Allocator {
	return {procedure = failing_allocator_proc, data = state}
}

failing_allocator_proc :: proc(
	data: rawptr,
	mode: runtime.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	location := #caller_location,
) -> ([]byte, runtime.Allocator_Error) {
	state := cast(^Failing_Allocator)data
	if state.fail && (mode == .Alloc || mode == .Alloc_Non_Zeroed ||
	   mode == .Resize || mode == .Resize_Non_Zeroed) {
		return nil, .Out_Of_Memory
	}
	return state.backing.procedure(
		state.backing.data,
		mode,
		size,
		alignment,
		old_memory,
		old_size,
		location,
	)
}

resident_memory_kib :: proc() -> u64 {
	bytes, read_error := os.read_entire_file("/proc/self/status", context.temp_allocator)
	if read_error != os.ERROR_NONE do return 0
	text := string(bytes)
	marker := strings.index(text, "VmRSS:")
	if marker < 0 do return 0
	start := marker + len("VmRSS:")
	for start < len(text) && (text[start] < '0' || text[start] > '9') do start += 1
	end := start
	for end < len(text) && text[end] >= '0' && text[end] <= '9' do end += 1
	if start == end do return 0
	value, parsed := strconv.parse_u64_of_base(text[start:end], 10)
	return value if parsed else 0
}
