// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "core:fmt"
import "core:mem"
import "core:os"
import "core:strings"
import "core:time"

KIBIBYTE :: 1_024
ORDINARY_HUNKS :: 32
STRESS_HUNKS :: 512
LINES_PER_HUNK :: 12
SELECTED_DEFAULT_HUNKS :: 512
SELECTED_MAX_HUNKS :: 4_096
SELECTED_MAX_LINE_BYTES :: 64 * KIBIBYTE
SELECTED_PATCH_BYTES :: 512 * KIBIBYTE
STUDY_LATENCY_LIMIT_NS :: i64(3_000_000_000)
STUDY_MEMORY_LIMIT_BYTES :: i64(4 * 1_024 * 1_024)

Diff_Measurement :: struct {
	bytes:          int,
	hunks:          int,
	maximum_line:   int,
	elapsed_ns:     i64,
	peak_bytes:     i64,
	cleanup_bytes:  i64,
}

main :: proc() {
	root, root_error := os.make_directory_temp("", "odra-ksawery-diff-unit-*", context.allocator)
	if root_error != nil do os.exit(1)
	defer {
		_ = os.remove_all(root)
		delete(root)
	}

	initialized := run_git(root, []string{"git", "init", "-q"})
	ordinary, ordinary_ok := measure_text_diff(root, "ordinary.txt", ORDINARY_HUNKS)
	stress, stress_ok := measure_text_diff(root, "stress.txt", STRESS_HUNKS)
	binary_ok := measure_binary_diff(root)
	malformed := transmute([]u8)(string("diff --git a/file b/file\n@@ invalid header @@\n-old\n+new\n"))
	malformed_candidates, malformed_maximum := diff_shape(malformed)
	truncated := stress.bytes > 8 && stress.hunks > 1

	valid := initialized && ordinary_ok && stress_ok && binary_ok && truncated &&
		ordinary.hunks == ORDINARY_HUNKS && stress.hunks == STRESS_HUNKS &&
		stress.hunks <= SELECTED_DEFAULT_HUNKS &&
		SELECTED_DEFAULT_HUNKS < SELECTED_MAX_HUNKS &&
		stress.bytes <= SELECTED_PATCH_BYTES &&
		ordinary.maximum_line <= SELECTED_MAX_LINE_BYTES &&
		stress.maximum_line <= SELECTED_MAX_LINE_BYTES &&
		ordinary.elapsed_ns <= STUDY_LATENCY_LIMIT_NS &&
		stress.elapsed_ns <= STUDY_LATENCY_LIMIT_NS &&
		ordinary.peak_bytes <= STUDY_MEMORY_LIMIT_BYTES &&
		stress.peak_bytes <= STUDY_MEMORY_LIMIT_BYTES &&
		ordinary.cleanup_bytes == 0 && stress.cleanup_bytes == 0 &&
		malformed_candidates == 0 && malformed_maximum > 0

	fmt.printf(
		"study=ksawery-diff-units valid=%v ordinary_hunks=%d ordinary_bytes=%d ordinary_max_line=%d ordinary_elapsed_ns=%d ordinary_peak_bytes=%d ordinary_cleanup_bytes=%d stress_hunks=%d stress_bytes=%d stress_max_line=%d stress_elapsed_ns=%d stress_peak_bytes=%d stress_cleanup_bytes=%d malformed_candidates=%d binary_detected=%v selected_default_hunks=%d selected_max_hunks=%d selected_max_line_bytes=%d selected_patch_bytes=%d latency_limit_ns=%d memory_limit_bytes=%d capture=unbounded-study-only\n",
		valid,
		ordinary.hunks,
		ordinary.bytes,
		ordinary.maximum_line,
		ordinary.elapsed_ns,
		ordinary.peak_bytes,
		ordinary.cleanup_bytes,
		stress.hunks,
		stress.bytes,
		stress.maximum_line,
		stress.elapsed_ns,
		stress.peak_bytes,
		stress.cleanup_bytes,
		malformed_candidates,
		binary_ok,
		SELECTED_DEFAULT_HUNKS,
		SELECTED_MAX_HUNKS,
		SELECTED_MAX_LINE_BYTES,
		SELECTED_PATCH_BYTES,
		STUDY_LATENCY_LIMIT_NS,
		STUDY_MEMORY_LIMIT_BYTES,
	)
	if !valid do os.exit(1)
}

@(private)
measure_text_diff :: proc(root, name: string, hunk_count: int) -> (Diff_Measurement, bool) {
	path, path_error := os.join_path({root, name}, context.allocator)
	if path_error != nil do return {}, false
	defer delete(path)
	baseline, baseline_ok := text_fixture(hunk_count, false)
	if !baseline_ok do return {}, false
	defer delete(baseline)
	changed, changed_ok := text_fixture(hunk_count, true)
	if !changed_ok do return {}, false
	defer delete(changed)
	if os.write_entire_file(path, baseline[:]) != nil do return {}, false
	if !run_git(root, []string{"git", "add", "--", name}) do return {}, false
	if os.write_entire_file(path, changed[:]) != nil do return {}, false

	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	started := time.tick_now()
	state, stdout, stderr, process_error := os.process_exec(
		os.Process_Desc {
			working_dir = root,
			command = []string{"git", "-c", "color.ui=false", "diff", "--no-ext-diff", "--no-color", "--unified=3", "--", name},
		},
		allocator,
	)
	elapsed_ns := time.duration_nanoseconds(time.tick_since(started))
	hunks, maximum_line := diff_shape(stdout)
	measurement := Diff_Measurement {
		bytes = len(stdout),
		hunks = hunks,
		maximum_line = maximum_line,
		elapsed_ns = elapsed_ns,
		peak_bytes = tracking.peak_memory_allocated,
	}
	ok := process_error == nil && state.exited && state.success && len(stderr) == 0
	if stdout != nil do delete(stdout, allocator)
	if stderr != nil do delete(stderr, allocator)
	measurement.cleanup_bytes = tracking.current_memory_allocated
	mem.tracking_allocator_destroy(&tracking)
	return measurement, ok
}

@(private)
text_fixture :: proc(hunk_count: int, changed: bool) -> ([dynamic]u8, bool) {
	if hunk_count <= 0 do return nil, false
	content, allocation_error := make([dynamic]u8, 0, hunk_count * LINES_PER_HUNK * 28)
	if allocation_error != nil do return nil, false
	for line_index in 0 ..< hunk_count * LINES_PER_HUNK {
		changed_line := changed && line_index % LINES_PER_HUNK == LINES_PER_HUNK / 2
		state := "changed" if changed_line else "baseline"
		line := fmt.aprintf("line-%06d %s\n", line_index, state)
		_, append_error := append(&content, ..transmute([]u8)line)
		delete(line)
		if append_error != nil {
			delete(content)
			return nil, false
		}
	}
	return content, true
}

@(private)
measure_binary_diff :: proc(root: string) -> bool {
	name := "binary.bin"
	path, path_error := os.join_path({root, name}, context.allocator)
	if path_error != nil do return false
	defer delete(path)
	baseline := []u8{0, 1, 2, 3, 4}
	changed := []u8{0, 1, 9, 3, 4}
	if os.write_entire_file(path, baseline) != nil do return false
	if !run_git(root, []string{"git", "add", "--", name}) do return false
	if os.write_entire_file(path, changed) != nil do return false
	state, stdout, stderr, process_error := os.process_exec(
		os.Process_Desc {
			working_dir = root,
			command = []string{"git", "-c", "color.ui=false", "diff", "--no-ext-diff", "--no-color", "--", name},
		},
		context.allocator,
	)
	ok := process_error == nil && state.exited && state.success && len(stderr) == 0 &&
		strings.contains(string(stdout), "Binary files")
	if stdout != nil do delete(stdout)
	if stderr != nil do delete(stderr)
	return ok
}

@(private)
run_git :: proc(directory: string, command: []string) -> bool {
	state, stdout, stderr, process_error := os.process_exec(
		os.Process_Desc {working_dir = directory, command = command},
		context.allocator,
	)
	if stdout != nil do delete(stdout)
	if stderr != nil do delete(stderr)
	return process_error == nil && state.exited && state.success
}

@(private)
diff_shape :: proc(data: []u8) -> (hunks, maximum_line: int) {
	line_start := 0
	for index in 0 ..= len(data) {
		if index < len(data) && data[index] != '\n' do continue
		line := data[line_start:index]
		maximum_line = max(maximum_line, len(line))
		if len(line) >= 4 && line[0] == '@' && line[1] == '@' && line[2] == ' ' && line[3] == '-' {
			hunks += 1
		}
		line_start = index + 1
	}
	return
}
