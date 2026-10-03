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

STAGED_PATHS :: 96
MODIFIED_PATHS :: 32
UNTRACKED_PATHS :: 64
STATUS_OUTPUT_LIMIT :: 512 * 1_024
STATUS_LATENCY_LIMIT_NS :: i64(3_000_000_000)
STATUS_MEMORY_LIMIT :: i64(2 * 1_024 * 1_024)

main :: proc() {
	root, root_error := os.make_directory_temp("", "odra-ksawery-resource-*", context.allocator)
	if root_error != nil do os.exit(1)
	defer {
		_ = os.remove_all(root)
		delete(root)
	}

	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	defer mem.tracking_allocator_destroy(&tracking)

	initialized := run_git(root, []string{"git", "init", "-q"}, allocator)
	if !initialized {
		fmt.println("study=ksawery-repository-observation valid=false stage=initialize")
		os.exit(1)
	}

	created := create_staged_paths(root)
	staged := created && run_git(root, []string{"git", "add", "."}, allocator)
	modified := staged && modify_staged_paths(root)
	untracked := modified && create_untracked_paths(root)

	started := time.tick_now()
	state, stdout, stderr, process_error := os.process_exec(
		os.Process_Desc {
			working_dir = root,
			command = []string{"git", "status", "--porcelain=v2", "--branch", "-z"},
		},
		allocator,
	)
	elapsed_ns := time.duration_nanoseconds(time.tick_since(started))
	stdout_bytes := len(stdout)
	stderr_bytes := len(stderr)
	records := nul_records(stdout)
	contains_staged := strings.contains(string(stdout), "staged-0000.txt")
	contains_untracked := strings.contains(string(stdout), "untracked-0000.txt")
	if stdout != nil do delete(stdout, allocator)
	if stderr != nil do delete(stderr, allocator)

	peak_bytes := tracking.peak_memory_allocated
	cleanup_bytes := tracking.current_memory_allocated
	valid := initialized && created && staged && modified && untracked &&
		process_error == nil && state.exited && state.success &&
		stdout_bytes > 0 && stdout_bytes <= STATUS_OUTPUT_LIMIT &&
		stderr_bytes == 0 && records >= STAGED_PATHS + UNTRACKED_PATHS &&
		contains_staged && contains_untracked && elapsed_ns <= STATUS_LATENCY_LIMIT_NS &&
		peak_bytes <= STATUS_MEMORY_LIMIT && cleanup_bytes == 0

	fmt.printf(
		"study=ksawery-repository-observation valid=%v staged_paths=%d modified_paths=%d untracked_paths=%d records=%d stdout_bytes=%d stderr_bytes=%d output_limit=%d elapsed_ns=%d latency_limit_ns=%d peak_bytes=%d memory_limit_bytes=%d cleanup_bytes=%d capture=unbounded-study-only\n",
		valid,
		STAGED_PATHS,
		MODIFIED_PATHS,
		UNTRACKED_PATHS,
		records,
		stdout_bytes,
		stderr_bytes,
		STATUS_OUTPUT_LIMIT,
		elapsed_ns,
		STATUS_LATENCY_LIMIT_NS,
		peak_bytes,
		STATUS_MEMORY_LIMIT,
		cleanup_bytes,
	)
	if !valid do os.exit(1)
}

@(private)
run_git :: proc(directory: string, command: []string, allocator: mem.Allocator) -> bool {
	state, stdout, stderr, process_error := os.process_exec(
		os.Process_Desc {working_dir = directory, command = command},
		allocator,
	)
	if stdout != nil do delete(stdout, allocator)
	if stderr != nil do delete(stderr, allocator)
	return process_error == nil && state.exited && state.success
}

@(private)
create_staged_paths :: proc(root: string) -> bool {
	for index in 0 ..< STAGED_PATHS {
		name := fmt.aprintf("staged-%04d.txt", index)
		path, path_error := os.join_path({root, name}, context.allocator)
		delete(name)
		if path_error != nil do return false
		write_error := os.write_entire_file(path, "initial content\n")
		delete(path)
		if write_error != nil do return false
	}
	return true
}

@(private)
modify_staged_paths :: proc(root: string) -> bool {
	for index in 0 ..< MODIFIED_PATHS {
		name := fmt.aprintf("staged-%04d.txt", index)
		path, path_error := os.join_path({root, name}, context.allocator)
		delete(name)
		if path_error != nil do return false
		write_error := os.write_entire_file(path, "changed content\n")
		delete(path)
		if write_error != nil do return false
	}
	return true
}

@(private)
create_untracked_paths :: proc(root: string) -> bool {
	for index in 0 ..< UNTRACKED_PATHS {
		name := fmt.aprintf("untracked-%04d.txt", index)
		path, path_error := os.join_path({root, name}, context.allocator)
		delete(name)
		if path_error != nil do return false
		write_error := os.write_entire_file(path, "untracked content\n")
		delete(path)
		if write_error != nil do return false
	}
	return true
}

@(private)
nul_records :: proc(data: []u8) -> int {
	count := 0
	for byte in data {
		if byte == 0 do count += 1
	}
	return count
}
