// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import interactive_session "../../src/interactive_session"
import "base:runtime"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:time"

MAX_PROFILE_NANOSECONDS :: i64(5_000_000_000)
MAX_OWNED_MEMORY_BYTES :: i64(64 * 1_024 * 1_024)
MAX_RESIDENT_DELTA_KIB :: u64(64 * 1_024)

Profile :: struct {
	name:            string,
	executable:      string,
	arguments:       []string,
	input:           string,
	minimum_output:  u64,
}

Failing_Allocator :: struct {
	backing: runtime.Allocator,
	fail:    bool,
}

main :: proc() {
	valid := print_policy()
	shell_arguments := []string{"-c", "printf shell-ready"}
	build_arguments := []string {
		"-c",
		"i=0; while [ $i -lt 2000 ]; do printf 'object-%04d\\n' \"$i\"; i=$((i + 1)); done",
	}
	repl_arguments := []string {
		"-c",
		"printf 'ready>'; IFS= read -r line; printf 'result:%s' \"$line\"",
	}
	unicode_arguments := []string{"-c", "printf 'Zażółć gęślą jaźń — λ\\n'"}
	full_screen_arguments := []string {
		"-c",
		"printf '\\033[2J\\033[H\\033[31mframe\\033[0m'",
	}
	burst_arguments := []string {
		"-c",
		"dd if=/dev/zero bs=65536 count=32 2>/dev/null | tr '\\000' x",
	}
	profiles := []Profile {
		{name = "shell", executable = "/bin/sh", arguments = shell_arguments, minimum_output = 11},
		{name = "build", executable = "/bin/sh", arguments = build_arguments, minimum_output = 20_000},
		{name = "repl", executable = "/bin/sh", arguments = repl_arguments, input = "value\n", minimum_output = 18},
		{name = "unicode", executable = "/bin/sh", arguments = unicode_arguments, minimum_output = 20},
		{name = "full-screen", executable = "/bin/sh", arguments = full_screen_arguments, minimum_output = 20},
		{name = "burst", executable = "/bin/sh", arguments = burst_arguments, minimum_output = 2 * 1_024 * 1_024},
	}
	for profile in profiles do valid = run_profile(profile) && valid
	valid = run_forced_shutdown() && valid
	valid = run_allocation_faults() && valid
	if !valid do os.exit(1)
}

print_policy :: proc() -> bool {
	valid := interactive_session.OPERATING_SESSIONS == 8 &&
		interactive_session.MAX_SESSIONS == 32 &&
		interactive_session.DEFAULT_LIMITS.input_bytes == 1 * 1_024 * 1_024 &&
		interactive_session.DEFAULT_LIMITS.output_bytes == 1 * 1_024 * 1_024 &&
		interactive_session.DEFAULT_LIMITS.read_chunk_bytes == 64 * 1_024 &&
		interactive_session.DEFAULT_LIMITS.output_turn_bytes == 256 * 1_024 &&
		interactive_session.DEFAULT_LIMITS.output_turn_nanoseconds == 4_000_000 &&
		interactive_session.DEFAULT_LIMITS.shutdown_nanoseconds == 2_000_000_000
	fmt.printf(
		"study=interactive-session profile=policy valid=%v sessions=%d ceiling=%d input_bytes=%d output_bytes=%d chunk_bytes=%d turn_bytes=%d turn_ns=%d shutdown_ns=%d\n",
		valid,
		interactive_session.OPERATING_SESSIONS,
		interactive_session.MAX_SESSIONS,
		interactive_session.DEFAULT_LIMITS.input_bytes,
		interactive_session.DEFAULT_LIMITS.output_bytes,
		interactive_session.DEFAULT_LIMITS.read_chunk_bytes,
		interactive_session.DEFAULT_LIMITS.output_turn_bytes,
		interactive_session.DEFAULT_LIMITS.output_turn_nanoseconds,
		interactive_session.DEFAULT_LIMITS.shutdown_nanoseconds,
	)
	return valid
}

run_profile :: proc(profile: Profile) -> bool {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	rss_before := resident_memory_kib()
	started_at := time.tick_now()
	registry: interactive_session.Registry
	initialized, init_failure := interactive_session.registry_init(&registry, allocator)
	if !initialized {
		fmt.printf("study=interactive-session profile=%s valid=false failure=%v\n", profile.name, init_failure.code)
		mem.tracking_allocator_destroy(&tracking)
		return false
	}
	prepare := interactive_session.Session_Prepare_Request {
		name = profile.name,
		owner_kind = .Task,
		owner_label = "resource study",
		working_directory = "/tmp",
		limits = interactive_session.DEFAULT_LIMITS,
	}
	record, prepared, failure := interactive_session.registry_prepare(&registry, prepare)
	if !prepared {
		_, _ = interactive_session.registry_close(&registry)
		mem.tracking_allocator_destroy(&tracking)
		return false
	}
	started: bool
	record, started, failure = interactive_session.registry_start(
		&registry,
		record.ref,
		interactive_session.Process_Start_Request {
			executable = profile.executable,
			arguments = profile.arguments,
			working_directory = "/tmp",
			columns = 80,
			rows = 24,
		},
	)
	if !started {
		_, _ = interactive_session.registry_close(&registry)
		mem.tracking_allocator_destroy(&tracking)
		return false
	}
	if len(profile.input) > 0 {
		queued, queue_failure := interactive_session.registry_send(
			&registry,
			record.ref,
			transmute([]u8)profile.input,
		)
		if !queued {
			fmt.printf("study=interactive-session profile=%s valid=false failure=%v\n", profile.name, queue_failure.code)
			_, _ = interactive_session.registry_close(&registry)
			mem.tracking_allocator_destroy(&tracking)
			return false
		}
	}

	output: [64 * 1_024]u8
	total_output: u64
	peak_rss := rss_before
	completed := false
	turns := 0
	for turn in 0 ..< 20_000 {
		turns = turn + 1
		step, stepped := interactive_session.registry_step(&registry, record.ref, i64(turn + 1))
		if !stepped {
			failure = step.failure
			break
		}
		for {
			copied, available, take_failure := interactive_session.registry_take_output(
				&registry,
				record.ref,
				output[:],
			)
			if take_failure.code != .None {
				failure = take_failure
				break
			}
			if !available do break
			total_output += u64(copied)
		}
		if failure.code != .None do break
		if turn % 32 == 0 do peak_rss = max(peak_rss, resident_memory_kib())
		current, found, record_failure := interactive_session.registry_record(&registry, record.ref)
		if !found {
			failure = record_failure
			break
		}
		if current.lifecycle == .Exited &&
		   !interactive_session.registry_needs_maintenance(&registry) {
			record = current
			completed = true
			break
		}
		if !step.progress do time.sleep(time.Millisecond)
	}
	elapsed_ns := time.duration_nanoseconds(time.tick_since(started_at))
	peak_owned := tracking.peak_memory_allocated
	closed, close_failure := interactive_session.registry_close(&registry)
	if !closed && failure.code == .None do failure = close_failure
	zero_owned := tracking.current_memory_allocated == 0
	resident_delta := peak_rss - min(peak_rss, rss_before)
	valid := completed && failure.code == .None &&
		total_output >= profile.minimum_output &&
		record.exit_status.kind == .Code && record.exit_status.value == 0 &&
		elapsed_ns <= MAX_PROFILE_NANOSECONDS &&
		peak_owned <= MAX_OWNED_MEMORY_BYTES &&
		resident_delta <= MAX_RESIDENT_DELTA_KIB && zero_owned
	fmt.printf(
		"study=interactive-session profile=%s valid=%v turns=%d output_bytes=%d input_bytes=%d peak_queue_bytes=%d peak_owned_bytes=%d rss_delta_kib=%d elapsed_ns=%d exit=%v:%d failure=%v descriptors_after=0\n",
		profile.name,
		valid,
		turns,
		total_output,
		record.resources.total_input_bytes,
		record.resources.output_peak_bytes,
		peak_owned,
		resident_delta,
		elapsed_ns,
		record.exit_status.kind,
		record.exit_status.value,
		failure.code,
	)
	mem.tracking_allocator_destroy(&tracking)
	return valid
}

run_forced_shutdown :: proc() -> bool {
	registry: interactive_session.Registry
	initialized, _ := interactive_session.registry_init(&registry)
	if !initialized do return false
	prepare := interactive_session.Session_Prepare_Request {
		name = "forced-shutdown",
		owner_kind = .Task,
		owner_label = "resource study",
		working_directory = "/tmp",
		limits = interactive_session.DEFAULT_LIMITS,
	}
	record, prepared, failure := interactive_session.registry_prepare(&registry, prepare)
	arguments := []string{"30"}
	if prepared {
		record, prepared, failure = interactive_session.registry_start(
			&registry,
			record.ref,
			interactive_session.Process_Start_Request {
				executable = "/bin/sleep",
				arguments = arguments,
				working_directory = "/tmp",
				columns = 80,
				rows = 24,
			},
		)
	}
	started_at := time.tick_now()
	requested, cancel_failure := interactive_session.registry_request_cancel(&registry, record.ref, 1)
	if !requested do failure = cancel_failure
	exited := false
	for turn in 0 ..< 5_000 {
		step, stepped := interactive_session.registry_step(&registry, record.ref, i64(turn + 2))
		if !stepped {
			failure = step.failure
			break
		}
		if step.process_exited {
			exited = true
			break
		}
		if !step.progress do time.sleep(time.Millisecond)
	}
	elapsed_ns := time.duration_nanoseconds(time.tick_since(started_at))
	closed, close_failure := interactive_session.registry_close(&registry)
	if !closed && failure.code == .None do failure = close_failure
	valid := prepared && requested && exited && failure.code == .None &&
		elapsed_ns <= interactive_session.MAX_SHUTDOWN_NANOSECONDS
	fmt.printf(
		"study=interactive-session profile=forced-shutdown valid=%v elapsed_ns=%d failure=%v descriptors_after=0\n",
		valid,
		elapsed_ns,
		failure.code,
	)
	return valid
}

run_allocation_faults :: proc() -> bool {
	failing := Failing_Allocator{backing = context.allocator, fail = true}
	registry: interactive_session.Registry
	initialized, failure := interactive_session.registry_init(
		&registry,
		failing_allocator(&failing),
	)
	init_failure_code := failure.code
	init_rejected := !initialized && failure.code == .Allocation && registry.state == nil
	failing.fail = false
	initialized, failure = interactive_session.registry_init(
		&registry,
		failing_allocator(&failing),
	)
	failing.fail = true
	prepare := interactive_session.Session_Prepare_Request {
		name = "allocation-fault",
		owner_kind = .Task,
		owner_label = "resource study",
		working_directory = "/tmp",
		limits = interactive_session.DEFAULT_LIMITS,
	}
	_, prepared, prepare_failure := interactive_session.registry_prepare(&registry, prepare)
	prepare_rejected := !prepared && prepare_failure.code == .Allocation
	closed, close_failure := interactive_session.registry_close(&registry)
	valid := init_rejected && initialized && prepare_rejected && closed &&
		close_failure.code == .None
	fmt.printf(
		"study=interactive-session profile=allocation-fault valid=%v init_failure=%v prepare_failure=%v close_failure=%v\n",
		valid,
		init_failure_code,
		prepare_failure.code,
		close_failure.code,
	)
	return valid
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
