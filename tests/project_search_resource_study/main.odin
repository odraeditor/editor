// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import project "../../src/project"
import "../../src/project_search"
import "../../src/search"
import "core:fmt"
import "core:os"
import "core:time"

main :: proc() {
	root, root_error := os.make_directory_temp("", "odra-project-search-study-*", context.allocator)
	if root_error != nil do os.exit(1)
	defer {
		os.remove_all(root)
		delete(root)
	}
	content := make([]u8, 64 * 1_024)
	defer delete(content)
	for &byte in content do byte = 'a'
	copy(content[:], "alpha beta needle gamma_delta\n")
	for index in 0 ..< 128 {
		name := fmt.tprintf("source-%04d.odin", index)
		path, path_error := os.join_path({root, name}, context.temp_allocator)
		if path_error != nil do os.exit(1)
		write_error := os.write_entire_file(path, content)
		delete(path, context.temp_allocator)
		if write_error != nil do os.exit(1)
	}
	project_handle := project.Project_Handle {
		owner = {id = 1, generation = 1},
		id = 1,
		generation = 1,
	}
	membership := project.Membership_Handle {
		project = project_handle,
		id = 1,
		generation = 1,
	}
	root_path: project.Directory_Path
	root_path.length = u32(copy(root_path.bytes[:], root))
	roots := [1]project_search.Root {{membership = membership, path = root_path}}
	limits := project_search.DEFAULT_LIMITS
	limits.matches = 8_192
	request := project_search.Request {
		id = 1,
		generation = 1,
		provider = 1,
		provider_generation = 1,
		project = project_handle,
		query_id = 1,
		pattern_kind = .Literal,
		pattern = "needle",
		policy = {search = search.DEFAULT_POLICY, hidden = .Exclude,
			ignored = .Respect, binary = .Exclude},
		search_limits = search.DEFAULT_LIMITS,
		limits = limits,
		roots = roots[:],
	}
	provider: project_search.Native_Provider
	initialized, failure := project_search.native_provider_init(
		&provider,
		request,
		{persistent = context.allocator, temporary = context.temp_allocator},
	)
	if !initialized {
		fmt.eprintf("study=project-search failure=%v\n", failure.code)
		os.exit(1)
	}
	defer project_search.native_provider_close(&provider)
	started := time.tick_now()
	inspection: project_search.Inspection
	for turn in 0 ..< 4_096 {
		advanced: bool
		inspection, advanced, failure = project_search.native_provider_advance(&provider, project_handle)
		if !advanced {
			fmt.eprintf("study=project-search failure=%v turn=%d\n", failure.code, turn)
			os.exit(1)
		}
		if inspection.lifecycle == .Complete do break
	}
	elapsed := time.duration_nanoseconds(time.tick_since(started))
	fmt.printf("study=project-search files=%d bytes=%d matches=%d retained=%d temporary=%d work=%d elapsed_ns=%d complete=%v\n",
		inspection.usage.files, inspection.usage.read_bytes, inspection.usage.matches,
		inspection.usage.retained_bytes, inspection.usage.temporary_peak_bytes,
		inspection.usage.work_items, elapsed, inspection.completeness)
	if inspection.lifecycle != .Complete || inspection.usage.files != 128 ||
	   inspection.usage.read_bytes > request.limits.total_read_bytes ||
	   inspection.usage.retained_bytes > request.limits.retained_bytes ||
	   inspection.usage.temporary_peak_bytes > request.limits.temporary_bytes {
		os.exit(1)
	}
}
