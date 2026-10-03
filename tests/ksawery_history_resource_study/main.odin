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
ORDINARY_REVISIONS :: 64
WIDE_REVISIONS :: 32
WIDE_MERGE_BRANCHES :: 8
STRESS_REVISIONS :: 512
SELECTED_DEFAULT_PAGE_REVISIONS :: 128
SELECTED_MAX_PAGE_REVISIONS :: 2_048
SELECTED_MAX_PARENTS :: 16
SELECTED_METADATA_BYTES :: 512 * KIBIBYTE
SELECTED_MESSAGE_BYTES :: 16 * KIBIBYTE
STUDY_LATENCY_LIMIT_NS :: i64(10_000_000_000)
STUDY_MEMORY_LIMIT_BYTES :: i64(4 * 1_024 * 1_024)

History_Measurement :: struct {
	revisions:      int,
	parent_links:   int,
	bytes:          int,
	maximum_field:  int,
	elapsed_ns:     i64,
	peak_bytes:     i64,
	cleanup_bytes:  i64,
}

main :: proc() {
	ordinary, ordinary_ok := measure_history("ordinary", ORDINARY_REVISIONS, true, false)
	wide, wide_ok := measure_history("wide", WIDE_REVISIONS, false, true)
	stress, stress_ok := measure_history("stress", STRESS_REVISIONS, false, false)
	unborn_ok := measure_unborn_history()
	malformed := []u8{0x1e, 'x', 0}
	_, _, malformed_field, malformed_ok := history_shape(malformed[:])
	truncated := []u8{0x1e, 'x', 0, 'y', 0, 'z', 0}
	_, _, truncated_field, truncated_ok := history_shape(truncated[:])

	valid := ordinary_ok && wide_ok && stress_ok && unborn_ok && !malformed_ok && !truncated_ok &&
		ordinary.revisions == ORDINARY_REVISIONS + 1 && ordinary.parent_links == ORDINARY_REVISIONS + 1 &&
		wide.revisions == WIDE_REVISIONS && wide.parent_links == WIDE_REVISIONS + WIDE_MERGE_BRANCHES - 1 &&
		wide.maximum_field <= SELECTED_MESSAGE_BYTES &&
		stress.revisions == STRESS_REVISIONS && stress.parent_links == STRESS_REVISIONS - 1 &&
		stress.revisions > SELECTED_DEFAULT_PAGE_REVISIONS &&
		SELECTED_DEFAULT_PAGE_REVISIONS < SELECTED_MAX_PAGE_REVISIONS &&
		WIDE_MERGE_BRANCHES + 1 <= SELECTED_MAX_PARENTS &&
		stress.bytes <= SELECTED_METADATA_BYTES &&
		ordinary.maximum_field <= SELECTED_MESSAGE_BYTES && stress.maximum_field <= SELECTED_MESSAGE_BYTES &&
		ordinary.elapsed_ns <= STUDY_LATENCY_LIMIT_NS && stress.elapsed_ns <= STUDY_LATENCY_LIMIT_NS &&
		ordinary.peak_bytes <= STUDY_MEMORY_LIMIT_BYTES && wide.peak_bytes <= STUDY_MEMORY_LIMIT_BYTES && stress.peak_bytes <= STUDY_MEMORY_LIMIT_BYTES &&
		ordinary.cleanup_bytes == 0 && wide.cleanup_bytes == 0 && stress.cleanup_bytes == 0 &&
		malformed_field == 1 && truncated_field == 1

	fmt.printf(
		"study=ksawery-revision-history valid=%v ordinary_revisions=%d ordinary_parent_links=%d ordinary_bytes=%d ordinary_max_field=%d ordinary_elapsed_ns=%d ordinary_peak_bytes=%d ordinary_cleanup_bytes=%d wide_revisions=%d wide_parent_links=%d wide_bytes=%d wide_max_field=%d wide_elapsed_ns=%d wide_peak_bytes=%d wide_cleanup_bytes=%d stress_revisions=%d stress_parent_links=%d stress_bytes=%d stress_max_field=%d stress_elapsed_ns=%d stress_peak_bytes=%d stress_cleanup_bytes=%d unborn=%v malformed_rejected=%v truncated_rejected=%v selected_default_page_revisions=%d selected_max_page_revisions=%d selected_max_parents=%d selected_metadata_bytes=%d selected_message_bytes=%d latency_limit_ns=%d memory_limit_bytes=%d capture=unbounded-study-only\n",
		valid,
		ordinary.revisions,
		ordinary.parent_links,
		ordinary.bytes,
		ordinary.maximum_field,
		ordinary.elapsed_ns,
		ordinary.peak_bytes,
		ordinary.cleanup_bytes,
		wide.revisions,
		wide.parent_links,
		wide.bytes,
		wide.maximum_field,
		wide.elapsed_ns,
		wide.peak_bytes,
		wide.cleanup_bytes,
		stress.revisions,
		stress.parent_links,
		stress.bytes,
		stress.maximum_field,
		stress.elapsed_ns,
		stress.peak_bytes,
		stress.cleanup_bytes,
		unborn_ok,
		!malformed_ok,
		!truncated_ok,
		SELECTED_DEFAULT_PAGE_REVISIONS,
		SELECTED_MAX_PAGE_REVISIONS,
		SELECTED_MAX_PARENTS,
		SELECTED_METADATA_BYTES,
		SELECTED_MESSAGE_BYTES,
		STUDY_LATENCY_LIMIT_NS,
		STUDY_MEMORY_LIMIT_BYTES,
	)
	if !valid do os.exit(1)
}

@(private)
measure_history :: proc(name: string, revision_count: int, include_merge, include_wide_merge: bool) -> (History_Measurement, bool) {
	template := fmt.aprintf("odra-ksawery-history-%s-*", name)
	defer delete(template)
	root, root_error := os.make_directory_temp("", template, context.allocator)
	if root_error != nil do return {}, false
	defer {
		_ = os.remove_all(root)
		delete(root)
	}

	initialized := run_git(root, []string{"git", "init", "-q", "-b", "main"}) &&
	              run_git(root, []string{"git", "config", "user.name", "Ksawery Study"}) &&
	              run_git(root, []string{"git", "config", "user.email", "study@example.invalid"})
	if !initialized do return {}, false

	linear_revisions := revision_count - 2
	if include_wide_merge do linear_revisions = revision_count - WIDE_MERGE_BRANCHES - 2
	committed := true
	for index in 0 ..< linear_revisions {
		if !commit_fixture_revision(root, index, "history.txt") {
			committed = false
			break
		}
	}
	if include_wide_merge && committed {
		committed = create_wide_merge_fixture(root, linear_revisions)
	} else if include_merge && committed {
		committed = create_merge_fixture(root, linear_revisions)
	} else if committed {
		for index in linear_revisions ..< revision_count {
			if !commit_fixture_revision(root, index, "history.txt") {
				committed = false
				break
			}
		}
	}
	if !committed do return {}, false

	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	defer mem.tracking_allocator_destroy(&tracking)

	started := time.tick_now()
	max_count := fmt.aprintf("--max-count=%d", revision_count + 2)
	defer delete(max_count)
	state, stdout, stderr, process_error := os.process_exec(
		os.Process_Desc {
			working_dir = root,
			command = []string{
				"git", "-c", "color.ui=false", "log", "--topo-order", "--date-order",
				max_count,
				"--pretty=format:%x1e%H%x00%P%x00%an%x00%ae%x00%aI%x00%cI%x00%s%x00%b%x00",
			},
		},
		allocator,
	)
	elapsed_ns := time.duration_nanoseconds(time.tick_since(started))
	revisions, parent_links, maximum_field, shaped := history_shape(stdout)
	measurement := History_Measurement {
		revisions = revisions,
		parent_links = parent_links,
		bytes = len(stdout),
		maximum_field = maximum_field,
		elapsed_ns = elapsed_ns,
		peak_bytes = tracking.peak_memory_allocated,
	}
	ok := process_error == nil && state.exited && state.success && len(stderr) == 0 && shaped
	if stdout != nil do delete(stdout, allocator)
	if stderr != nil do delete(stderr, allocator)
	measurement.cleanup_bytes = tracking.current_memory_allocated
	return measurement, ok
}

@(private)
measure_unborn_history :: proc() -> bool {
	root, root_error := os.make_directory_temp("", "odra-ksawery-history-unborn-*", context.allocator)
	if root_error != nil do return false
	defer {
		_ = os.remove_all(root)
		delete(root)
	}
	if !run_git(root, []string{"git", "init", "-q", "-b", "main"}) do return false
	state, stdout, stderr, process_error := os.process_exec(
		os.Process_Desc {working_dir = root, command = []string{"git", "rev-parse", "--verify", "HEAD"}},
		context.allocator,
	)
	if stdout != nil do delete(stdout)
	if stderr != nil do delete(stderr)
	return process_error == nil && state.exited && !state.success
}

@(private)
commit_fixture_revision :: proc(root: string, index: int, filename: string) -> bool {
	path, path_error := os.join_path({root, filename}, context.allocator)
	if path_error != nil do return false
	defer delete(path)
	content := fmt.aprintf("revision-%04d\n", index)
	defer delete(content)
	if os.write_entire_file(path, content) != nil do return false
	if !run_git(root, []string{"git", "add", "--", filename}) do return false
	subject := fmt.aprintf("history revision %04d", index)
	defer delete(subject)
	body := fmt.aprintf("bounded history fixture %04d", index)
	defer delete(body)
	return run_git(root, []string{"git", "-c", "commit.gpgSign=false", "commit", "-q", "-m", subject, "-m", body})
}

@(private)
create_merge_fixture :: proc(root: string, index: int) -> bool {
	if !run_git(root, []string{"git", "checkout", "-q", "-b", "side"}) do return false
	if !commit_fixture_revision(root, index, "side.txt") do return false
	if !run_git(root, []string{"git", "checkout", "-q", "main"}) do return false
	if !commit_fixture_revision(root, index + 1, "main.txt") do return false
	return run_git(
		root,
		[]string{"git", "-c", "commit.gpgSign=false", "merge", "--no-ff", "-q", "side", "-m", "merge history fixture"},
	)
}

@(private)
create_wide_merge_fixture :: proc(root: string, index: int) -> bool {
	for branch_index in 0 ..< WIDE_MERGE_BRANCHES {
		if !run_git(root, []string{"git", "checkout", "-q", "main"}) do return false
		branch := fmt.aprintf("side-%d", branch_index)
		defer delete(branch)
		if !run_git(root, []string{"git", "checkout", "-q", "-b", branch}) do return false
		filename := fmt.aprintf("side-%d.txt", branch_index)
		defer delete(filename)
		if !commit_fixture_revision(root, index + branch_index, filename) do return false
	}
	if !run_git(root, []string{"git", "checkout", "-q", "main"}) do return false
	if !commit_fixture_revision(root, index + WIDE_MERGE_BRANCHES, "main.txt") do return false
	return run_git(
		root,
		[]string{
			"git", "-c", "commit.gpgSign=false", "merge", "--no-ff", "-q",
			"side-0", "side-1", "side-2", "side-3", "side-4", "side-5", "side-6", "side-7",
			"-m", "wide merge history fixture",
		},
	)
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
history_shape :: proc(data: []u8) -> (revisions, parent_links, maximum_field: int, valid: bool) {
	if len(data) == 0 do return
	valid = true
	offset := 0
	for offset < len(data) {
		if data[offset] != 0x1e do return 0, 0, maximum_field, false
		offset += 1
		for field_index in 0 ..< 8 {
			end := offset
			for end < len(data) && data[end] != 0 do end += 1
			if end == len(data) do return revisions, parent_links, maximum_field, false
			field_bytes := end - offset
			maximum_field = max(maximum_field, field_bytes)
			if field_index == 1 && field_bytes > 0 {
				parent_links += 1
				for byte in data[offset:end] {
					if byte == ' ' do parent_links += 1
				}
			}
			offset = end + 1
		}
		if offset < len(data) && data[offset] == '\n' do offset += 1
		revisions += 1
	}
	return
}
