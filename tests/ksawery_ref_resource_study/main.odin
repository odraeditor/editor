// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "core:fmt"
import "core:mem"
import "core:os"
import "core:time"

KIBIBYTE :: 1_024
ORDINARY_BRANCHES :: 16
ORDINARY_TAGS :: 32
ORDINARY_REMOTES :: 2
WIDE_BRANCHES :: 96
WIDE_TAGS :: 256
WIDE_REMOTES :: 32
STRESS_BRANCHES :: 512
STRESS_TAGS :: 1_024
STRESS_REMOTES :: 64
SELECTED_DEFAULT_REF_ENTRIES :: 256
SELECTED_MAX_REF_ENTRIES :: 4_096
SELECTED_DEFAULT_REMOTE_ENTRIES :: 32
SELECTED_MAX_REMOTE_ENTRIES :: 512
SELECTED_DEFAULT_NAME_BYTES :: 512
SELECTED_MAX_NAME_BYTES :: 1_024
SELECTED_DEFAULT_RETAINED_BYTES :: 512 * KIBIBYTE
SELECTED_MAX_RETAINED_BYTES :: 4 * 1_024 * KIBIBYTE
STUDY_LATENCY_LIMIT_NS :: i64(10_000_000_000)
STUDY_MEMORY_LIMIT_BYTES :: i64(8 * 1_024 * 1_024)

Ref_Measurement :: struct {
	references:    int,
	branches:      int,
	tags:          int,
	remotes:       int,
	bytes:         int,
	maximum_name:  int,
	elapsed_ns:    i64,
	peak_bytes:    i64,
	cleanup_bytes: i64,
	monochrome:    bool,
}

main :: proc() {
	ordinary, ordinary_ok := measure_refs("ordinary", ORDINARY_BRANCHES, ORDINARY_TAGS, ORDINARY_REMOTES)
	wide, wide_ok := measure_refs("wide", WIDE_BRANCHES, WIDE_TAGS, WIDE_REMOTES)
	stress, stress_ok := measure_refs("stress", STRESS_BRANCHES, STRESS_TAGS, STRESS_REMOTES)
	unborn_ok := measure_unborn_refs()
	detached_ok := measure_detached_head()
	remote_less_ok := measure_remote_less_refs()
	malformed := []u8{'r', 'e', 'f', 's', '/', 'h', 'e', 'a', 'd', 's', '/', 'm', 'a', 'i', 'n', 0}
	_, malformed_ok, malformed_name := ref_shape(malformed[:])
	truncated := []u8{'r', 'e', 'f', 's', '/', 'h', 'e', 'a', 'd', 's', '/', 'm', 'a', 'i', 'n', 0, '0', '1', 0, 'c', 'o', 'm', 'm', 'i', 't', 0}
	_, truncated_ok, truncated_name := ref_shape(truncated[:])

	valid := ordinary_ok && wide_ok && stress_ok && unborn_ok && detached_ok && remote_less_ok &&
		ordinary.references == ORDINARY_BRANCHES + ORDINARY_TAGS &&
		wide.references == WIDE_BRANCHES + WIDE_TAGS &&
		stress.references == STRESS_BRANCHES + STRESS_TAGS &&
		ordinary.branches == ORDINARY_BRANCHES && wide.branches == WIDE_BRANCHES && stress.branches == STRESS_BRANCHES &&
		ordinary.tags == ORDINARY_TAGS && wide.tags == WIDE_TAGS && stress.tags == STRESS_TAGS &&
		ordinary.remotes == ORDINARY_REMOTES && wide.remotes == WIDE_REMOTES && stress.remotes == STRESS_REMOTES &&
		wide.references > SELECTED_DEFAULT_REF_ENTRIES && stress.references <= SELECTED_MAX_REF_ENTRIES &&
		wide.remotes == SELECTED_DEFAULT_REMOTE_ENTRIES && stress.remotes <= SELECTED_MAX_REMOTE_ENTRIES &&
		ordinary.maximum_name <= SELECTED_DEFAULT_NAME_BYTES && stress.maximum_name <= SELECTED_MAX_NAME_BYTES &&
		stress.bytes <= SELECTED_DEFAULT_RETAINED_BYTES && SELECTED_DEFAULT_RETAINED_BYTES <= SELECTED_MAX_RETAINED_BYTES &&
		ordinary.monochrome && wide.monochrome && stress.monochrome &&
		ordinary.elapsed_ns <= STUDY_LATENCY_LIMIT_NS && wide.elapsed_ns <= STUDY_LATENCY_LIMIT_NS && stress.elapsed_ns <= STUDY_LATENCY_LIMIT_NS &&
		ordinary.peak_bytes <= STUDY_MEMORY_LIMIT_BYTES && wide.peak_bytes <= STUDY_MEMORY_LIMIT_BYTES && stress.peak_bytes <= STUDY_MEMORY_LIMIT_BYTES &&
		ordinary.cleanup_bytes == 0 && wide.cleanup_bytes == 0 && stress.cleanup_bytes == 0 &&
		!malformed_ok && !truncated_ok && malformed_name == 15 && truncated_name == 15

	fmt.printf(
		"study=ksawery-refs valid=%v ordinary_refs=%d ordinary_branches=%d ordinary_tags=%d ordinary_remotes=%d ordinary_bytes=%d ordinary_maximum_name=%d ordinary_elapsed_ns=%d ordinary_peak_bytes=%d ordinary_cleanup_bytes=%d wide_refs=%d wide_branches=%d wide_tags=%d wide_remotes=%d wide_bytes=%d wide_maximum_name=%d wide_elapsed_ns=%d wide_peak_bytes=%d wide_cleanup_bytes=%d stress_refs=%d stress_branches=%d stress_tags=%d stress_remotes=%d stress_bytes=%d stress_maximum_name=%d stress_elapsed_ns=%d stress_peak_bytes=%d stress_cleanup_bytes=%d unborn=%v detached=%v remote_less=%v malformed_rejected=%v truncated_rejected=%v selected_default_ref_entries=%d selected_max_ref_entries=%d selected_default_remote_entries=%d selected_max_remote_entries=%d selected_default_name_bytes=%d selected_max_name_bytes=%d selected_default_retained_bytes=%d selected_max_retained_bytes=%d latency_limit_ns=%d memory_limit_bytes=%d capture=unbounded-study-only\n",
		valid,
		ordinary.references, ordinary.branches, ordinary.tags, ordinary.remotes, ordinary.bytes, ordinary.maximum_name, ordinary.elapsed_ns, ordinary.peak_bytes, ordinary.cleanup_bytes,
		wide.references, wide.branches, wide.tags, wide.remotes, wide.bytes, wide.maximum_name, wide.elapsed_ns, wide.peak_bytes, wide.cleanup_bytes,
		stress.references, stress.branches, stress.tags, stress.remotes, stress.bytes, stress.maximum_name, stress.elapsed_ns, stress.peak_bytes, stress.cleanup_bytes,
		unborn_ok, detached_ok, remote_less_ok, !malformed_ok, !truncated_ok,
		SELECTED_DEFAULT_REF_ENTRIES, SELECTED_MAX_REF_ENTRIES, SELECTED_DEFAULT_REMOTE_ENTRIES, SELECTED_MAX_REMOTE_ENTRIES,
		SELECTED_DEFAULT_NAME_BYTES, SELECTED_MAX_NAME_BYTES, SELECTED_DEFAULT_RETAINED_BYTES, SELECTED_MAX_RETAINED_BYTES,
		STUDY_LATENCY_LIMIT_NS, STUDY_MEMORY_LIMIT_BYTES,
	)
	if !valid do os.exit(1)
}

@(private)
measure_refs :: proc(name: string, branches, tags, remotes: int) -> (Ref_Measurement, bool) {
	template := fmt.aprintf("odra-ksawery-refs-%s-*", name)
	defer delete(template)
	root, root_error := os.make_directory_temp("", template, context.allocator)
	if root_error != nil do return {}, false
	defer {
		_ = os.remove_all(root)
		delete(root)
	}
	if !initialize_repository(root) || !create_refs(root, branches, tags) || !configure_remotes(root, remotes) {
		return {}, false
	}

	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	defer mem.tracking_allocator_destroy(&tracking)

	started := time.tick_now()
	state, stdout, stderr, process_error := os.process_exec(
		os.Process_Desc {
			working_dir = root,
			command = []string {
				"git", "-c", "color.ui=false", "for-each-ref",
				"--format=%(refname)%00%(objectname)%00%(objecttype)%00%(symref)%00",
			},
		},
		allocator,
	)
	elapsed_ns := time.duration_nanoseconds(time.tick_since(started))
	references, shaped, maximum_name := ref_shape(stdout)
	measurement := Ref_Measurement {
		references = references,
		branches = prefix_count(stdout, "refs/heads/"),
		tags = prefix_count(stdout, "refs/tags/"),
		remotes = remote_count(root),
		bytes = len(stdout),
		maximum_name = maximum_name,
		elapsed_ns = elapsed_ns,
		peak_bytes = tracking.peak_memory_allocated,
		monochrome = !contains_escape(stdout),
	}
	ok := process_error == nil && state.exited && state.success && len(stderr) == 0 && shaped
	if stdout != nil do delete(stdout, allocator)
	if stderr != nil do delete(stderr, allocator)
	measurement.cleanup_bytes = tracking.current_memory_allocated
	return measurement, ok
}

@(private)
initialize_repository :: proc(root: string) -> bool {
	if !run_git(root, "git", "init", "-q", "-b", "main") ||
	   !run_git(root, "git", "config", "user.name", "Ksawery Study") ||
	   !run_git(root, "git", "config", "user.email", "study@example.invalid") {
		return false
	}
	path, path_error := os.join_path({root, "refs.txt"}, context.allocator)
	if path_error != nil do return false
	defer delete(path)
	if os.write_entire_file(path, "refs\n") != nil do return false
	return run_git(root, "git", "add", "refs.txt") &&
	       run_git(root, "git", "-c", "commit.gpgSign=false", "commit", "-q", "-m", "create refs fixture")
}

@(private)
create_refs :: proc(root: string, branches, tags: int) -> bool {
	if branches < 1 || tags < 0 do return false
	for index in 1 ..< branches {
		branch := fmt.aprintf("study/branch-%04d", index)
		created := run_git(root, "git", "branch", branch)
		delete(branch)
		if !created do return false
	}
	for index in 0 ..< tags {
		tag := fmt.aprintf("study-tag-%04d", index)
		created := run_git(root, "git", "tag", tag)
		delete(tag)
		if !created do return false
	}
	return true
}

@(private)
configure_remotes :: proc(root: string, remotes: int) -> bool {
	for index in 0 ..< remotes {
		remote := fmt.aprintf("study-remote-%02d", index)
		location := fmt.aprintf("../study-remote-%02d.git", index)
		configured := run_git(root, "git", "remote", "add", remote, location)
		delete(location)
		delete(remote)
		if !configured do return false
	}
	return true
}

@(private)
measure_unborn_refs :: proc() -> bool {
	root, root_error := os.make_directory_temp("", "odra-ksawery-refs-unborn-*", context.allocator)
	if root_error != nil do return false
	defer {
		_ = os.remove_all(root)
		delete(root)
	}
	if !run_git(root, "git", "init", "-q", "-b", "main") do return false
	state, stdout, stderr, process_error := os.process_exec(
		os.Process_Desc {
			working_dir = root,
			command = []string {"git", "-c", "color.ui=false", "for-each-ref", "--format=%(refname)%00%(objectname)%00%(objecttype)%00%(symref)%00"},
		},
		context.allocator,
	)
	valid := process_error == nil && state.exited && state.success && len(stdout) == 0 && len(stderr) == 0
	if stdout != nil do delete(stdout)
	if stderr != nil do delete(stderr)
	return valid
}

@(private)
measure_detached_head :: proc() -> bool {
	root, root_error := os.make_directory_temp("", "odra-ksawery-refs-detached-*", context.allocator)
	if root_error != nil do return false
	defer {
		_ = os.remove_all(root)
		delete(root)
	}
	if !initialize_repository(root) || !run_git(root, "git", "checkout", "-q", "--detach") do return false
	state, stdout, stderr, process_error := os.process_exec(
		os.Process_Desc {working_dir = root, command = []string {"git", "symbolic-ref", "-q", "HEAD"}},
		context.allocator,
	)
	if stdout != nil do delete(stdout)
	if stderr != nil do delete(stderr)
	return process_error == nil && state.exited && !state.success
}

@(private)
measure_remote_less_refs :: proc() -> bool {
	root, root_error := os.make_directory_temp("", "odra-ksawery-refs-remote-less-*", context.allocator)
	if root_error != nil do return false
	defer {
		_ = os.remove_all(root)
		delete(root)
	}
	if !initialize_repository(root) do return false
	return remote_count(root) == 0
}

@(private)
remote_count :: proc(root: string) -> int {
	state, stdout, stderr, process_error := os.process_exec(
		os.Process_Desc {working_dir = root, command = []string {"git", "remote"}},
		context.allocator,
	)
	if process_error != nil || !state.exited || !state.success || len(stderr) != 0 {
		if stdout != nil do delete(stdout)
		if stderr != nil do delete(stderr)
		return -1
	}
	count := 0
	for byte in stdout {
		if byte == '\n' do count += 1
	}
	if stdout != nil do delete(stdout)
	if stderr != nil do delete(stderr)
	return count
}

@(private)
run_git :: proc(directory: string, command: ..string) -> bool {
	state, stdout, stderr, process_error := os.process_exec(
		os.Process_Desc {working_dir = directory, command = command},
		context.allocator,
	)
	if stdout != nil do delete(stdout)
	if stderr != nil do delete(stderr)
	return process_error == nil && state.exited && state.success
}

@(private)
ref_shape :: proc(data: []u8) -> (references: int, valid: bool, maximum_name: int) {
	if len(data) == 0 do return
	valid = true
	offset := 0
	for offset < len(data) {
		for field_index in 0 ..< 4 {
			end := offset
			for end < len(data) && data[end] != 0 do end += 1
			if end == len(data) do return references, false, maximum_name
			if field_index == 0 {
				if end == offset do return references, false, maximum_name
				maximum_name = max(maximum_name, end - offset)
			}
			offset = end + 1
		}
		if offset >= len(data) || data[offset] != '\n' do return references, false, maximum_name
		offset += 1
		references += 1
	}
	return
}

@(private)
prefix_count :: proc(data: []u8, prefix: string) -> int {
	count := 0
	offset := 0
	for offset < len(data) {
		end := offset
		for end < len(data) && data[end] != 0 do end += 1
		if end == len(data) do return count
		name := string(data[offset:end])
		if len(name) >= len(prefix) && name[:len(prefix)] == prefix do count += 1
		for offset < len(data) && data[offset] != '\n' do offset += 1
		if offset < len(data) do offset += 1
	}
	return count
}

@(private)
contains_escape :: proc(data: []u8) -> bool {
	for byte in data {
		if byte == 0x1b do return true
	}
	return false
}
