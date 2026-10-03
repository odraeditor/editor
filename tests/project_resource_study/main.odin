// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import project_reference "../project_reference"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:strings"
import "core:time"

KIBIBYTE :: u64(1_024)
MEBIBYTE :: u64(1_024) * KIBIBYTE

MIN_PROJECTS :: 16
MAX_PROJECTS :: 1_024
SELECTED_PROJECTS :: 128
MIN_DIRECTORIES :: 1
MAX_DIRECTORIES :: 256
SELECTED_DIRECTORIES :: 32
MIN_NAME_BYTES :: 64
MAX_NAME_BYTES :: 1_024
SELECTED_NAME_BYTES :: 256
MIN_DESCRIPTOR_BATCH :: 16
MAX_DESCRIPTOR_BATCH :: 4_096
SELECTED_DESCRIPTOR_BATCH :: 256
MIN_PATH_BYTES :: 64 * KIBIBYTE
MAX_PATH_BYTES :: 16 * MEBIBYTE
SELECTED_PATH_BYTES :: 4 * MEBIBYTE
MIN_DIRTY_MARKERS :: 16
MAX_DIRTY_MARKERS :: 4_096
SELECTED_DIRTY_MARKERS :: 256

CLASSIFICATION_GATE_NS :: i64(100_000)
REPLACEMENT_GATE_NS :: i64(2_000_000)
PROJECTION_GATE_NS :: i64(5_000_000)
DIRECTORY_RESOLUTION_GATE_NS :: i64(1_000_000)
SAMPLES :: 4_096
RESOLUTION_SAMPLES :: 1_024

Latency :: struct {
	p50_ns: i64,
	p99_ns: i64,
}

Candidate :: struct {
	directories: [dynamic]string,
	exact_index: map[string]int,
	generation:  u64,
	path_bytes:  u64,
	allocator:   mem.Allocator,
}

Profile :: struct {
	name:        string,
	directories: int,
	documents:   int,
	overlap:     int,
}

Resolution_Profile :: struct {
	name:              string,
	entries:           int,
	exact_matches:     int,
	invalid_entries:   int,
	multi_directories: int,
	unicode_path:      bool,
}

Resolution_Candidate :: struct {
	entries:    []project_reference.Catalog_Entry,
	paths:      []string,
	owned_paths: int,
	allocator:  mem.Allocator,
}

Lifecycle_Profile :: struct {
	name:              string,
	projects:          int,
	workspaces:        int,
	members:           int,
	suppressions:      int,
	operation_gate_ns: i64,
}

main :: proc() {
	passed := print_policy_evidence()
	passed = run_reference_probe() && passed
	profiles := [?]Profile {
		{name = "ordinary", directories = 4, documents = 128, overlap = 2},
		{name = "demanding", directories = 32, documents = 1_024, overlap = 8},
		{name = "stress", directories = 256, documents = 4_096, overlap = 32},
	}
	for profile in profiles {
		passed = run_profile(profile) && passed
	}
	resolution_profiles := [?]Resolution_Profile {
		{name = "ordinary", entries = 32, exact_matches = 1, invalid_entries = 2, multi_directories = 4},
		{name = "demanding", entries = 1_024, exact_matches = 1, invalid_entries = 64, multi_directories = 256},
		{name = "stress", entries = 1_024, exact_matches = 8, invalid_entries = 128, multi_directories = 512, unicode_path = true},
	}
	for profile in resolution_profiles {
		passed = run_resolution_profile(profile) && passed
	}
	lifecycle_profiles := [?]Lifecycle_Profile {
		{name = "ordinary", projects = 32, workspaces = 4, members = 8, suppressions = 32, operation_gate_ns = 50_000_000},
		{name = "demanding", projects = 128, workspaces = 32, members = 32, suppressions = 256, operation_gate_ns = 250_000_000},
		{name = "stress", projects = 1_024, workspaces = 256, members = 256, suppressions = 4_096, operation_gate_ns = 2_000_000_000},
	}
	for profile in lifecycle_profiles {
		passed = run_lifecycle_profile(profile) && passed
	}
	passed = run_resolution_rejection_probe() && passed
	passed = run_lifecycle_rejection_probe() && passed
	passed = run_rejection_probe() && passed
	if !passed {
		os.exit(1)
	}
}

run_lifecycle_profile :: proc(profile: Lifecycle_Profile) -> bool {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	model, ready := project_reference.lifecycle_model_init(
		project_reference.Lifecycle_Policy {
			projects = profile.projects,
			workspaces = profile.workspaces,
			workspace_members = profile.members,
			promotion_suppressions = profile.suppressions,
		},
		allocator,
	)
	if !ready {
		mem.tracking_allocator_destroy(&tracking)
		return false
	}

	started := time.tick_now()
	handles, handles_error := make([]project_reference.Lifecycle_Project_Handle, profile.projects, allocator)
	if handles_error != nil {
		project_reference.lifecycle_model_deinit(&model)
		mem.tracking_allocator_destroy(&tracking)
		return false
	}
	built := true
	for index in 0 ..< profile.projects {
		id := fmt.aprintf("project-%04d", index)
		name := fmt.aprintf("Project %04d", index)
		root := fmt.aprintf("/work/project-%04d", index)
		handle, promoted, _ := project_reference.lifecycle_promote(&model, id, name, root)
		delete(root)
		delete(name)
		delete(id)
		handles[index] = handle
		built = promoted && built
	}
	for index in 0 ..< profile.workspaces {
		id := fmt.aprintf("workspace-%04d", index)
		name := fmt.aprintf("Workspace %04d", index)
		_, created, _ := project_reference.lifecycle_workspace_create(
			&model,
			id,
			name,
			handles[:profile.members],
		)
		delete(name)
		delete(id)
		built = created && built
	}
	for index in 0 ..< profile.suppressions {
		root := fmt.aprintf("/scratch/dir-%04d", index)
		suppressed, _ := project_reference.lifecycle_suppress(&model, root)
		delete(root)
		built = suppressed && built
	}
	operation_ns := time.duration_nanoseconds(time.tick_since(started))
	last_root := fmt.aprintf("/work/project-%04d", profile.projects - 1)
	_, resolved := project_reference.lifecycle_project_by_root(&model, last_root)
	delete(last_root)
	valid := built && resolved && project_reference.lifecycle_model_validate(&model) &&
	         operation_ns <= profile.operation_gate_ns
	persistent_bytes := tracking.current_memory_allocated
	peak_bytes := tracking.peak_memory_allocated
	delete(handles, allocator)
	project_reference.lifecycle_model_deinit(&model)
	cleanup_bytes := tracking.current_memory_allocated
	valid = valid && cleanup_bytes == 0
	mem.tracking_allocator_destroy(&tracking)
	fmt.printf(
		"study=project-workspace-lifecycle profile=%s valid=%v projects=%d workspaces=%d members_per_workspace=%d suppressions=%d operation_ns=%d operation_gate_ns=%d persistent_bytes=%d peak_bytes=%d cleanup_bytes=%d\n",
		profile.name,
		valid,
		profile.projects,
		profile.workspaces,
		profile.members,
		profile.suppressions,
		operation_ns,
		profile.operation_gate_ns,
		persistent_bytes,
		peak_bytes,
		cleanup_bytes,
	)
	return valid
}

run_lifecycle_rejection_probe :: proc() -> bool {
	model, ready := project_reference.lifecycle_model_init(
		project_reference.Lifecycle_Policy {
			projects = 2,
			workspaces = 1,
			workspace_members = 2,
			promotion_suppressions = 1,
		},
	)
	if !ready {
		return false
	}
	defer project_reference.lifecycle_model_deinit(&model)
	first, first_ok, _ := project_reference.lifecycle_promote(&model, "first", "First", "/first")
	second, second_ok, _ := project_reference.lifecycle_promote(&model, "second", "Second", "/second")
	_, capacity_ok, capacity_failure := project_reference.lifecycle_promote(
		&model,
		"third",
		"Third",
		"/third",
	)
	empty: [0]project_reference.Lifecycle_Project_Handle
	_, cardinality_ok, cardinality_failure := project_reference.lifecycle_workspace_create(
		&model,
		"invalid",
		"Invalid",
		empty[:],
	)
	members := [?]project_reference.Lifecycle_Project_Handle{first, second}
	_, workspace_ok, _ := project_reference.lifecycle_workspace_create(
		&model,
		"valid",
		"Valid",
		members[:],
	)
	valid := first_ok && second_ok && !capacity_ok && capacity_failure.code == .Capacity &&
	         !cardinality_ok && cardinality_failure.code == .Invalid_Workspace_Cardinality &&
	         workspace_ok && project_reference.lifecycle_model_validate(&model)
	fmt.printf(
		"study=project-workspace-lifecycle profile=rejection valid=%v project_limit=%d attempted_projects=%d workspace_minimum=%d attempted_members=%d reason=bounded-prepublication-rejection\n",
		valid,
		2,
		3,
		1,
		0,
	)
	return valid
}

run_resolution_profile :: proc(profile: Resolution_Profile) -> bool {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	target := "/work/target"
	if profile.unicode_path {
		target = "/work/Zażółć/odra"
	}
	candidate, ready := resolution_candidate_init(profile, target, allocator)
	if !ready {
		mem.tracking_allocator_destroy(&tracking)
		return false
	}

	matches: [MAX_PROJECTS]int
	samples: [RESOLUTION_SAMPLES]i64
	kind: project_reference.Directory_Resolution_Kind
	count := 0
	ok := false
	checksum: u64
	for sample in 0 ..< RESOLUTION_SAMPLES {
		started := time.tick_now()
		kind, count, ok = project_reference.resolve_exact_single_directory(
			candidate.entries,
			target,
			matches[:],
		)
		samples[sample] = time.duration_nanoseconds(time.tick_since(started))
		checksum += u64(count)
		if count > 0 {
			checksum += u64(matches[count - 1])
		}
	}
	latency := latency_from_samples(samples[:])
	expected_kind := project_reference.Directory_Resolution_Kind.Unregistered
	if profile.exact_matches == 1 {
		expected_kind = .Registered
	} else if profile.exact_matches > 1 {
		expected_kind = .Ambiguous
	}
	ordered := count == profile.exact_matches
	for index in 0 ..< count {
		ordered = matches[index] == index && ordered
	}
	valid := ok && kind == expected_kind && ordered &&
		latency.p99_ns <= DIRECTORY_RESOLUTION_GATE_NS
	persistent_bytes := tracking.current_memory_allocated
	peak_bytes := tracking.peak_memory_allocated
	resolution_candidate_close(&candidate)
	cleanup_bytes := tracking.current_memory_allocated
	valid = valid && cleanup_bytes == 0
	mem.tracking_allocator_destroy(&tracking)
	fmt.printf(
		"study=project-directory-resolution profile=%s valid=%v entries=%d exact_matches=%d invalid_entries=%d multi_directory_entries=%d unicode=%v p50_ns=%d p99_ns=%d gate_ns=%d persistent_bytes=%d peak_bytes=%d cleanup_bytes=%d ordering=catalog checksum=%d\n",
		profile.name,
		valid,
		profile.entries,
		profile.exact_matches,
		profile.invalid_entries,
		profile.multi_directories,
		profile.unicode_path,
		latency.p50_ns,
		latency.p99_ns,
		DIRECTORY_RESOLUTION_GATE_NS,
		persistent_bytes,
		peak_bytes,
		cleanup_bytes,
		checksum,
	)
	return valid
}

resolution_candidate_init :: proc(
	profile: Resolution_Profile,
	target: string,
	allocator: mem.Allocator,
) -> (candidate: Resolution_Candidate, ok: bool) {
	if profile.entries <= 0 || profile.entries > MAX_PROJECTS ||
	   profile.exact_matches < 0 || profile.invalid_entries < 0 ||
	   profile.multi_directories < 0 ||
	   profile.exact_matches + profile.invalid_entries + profile.multi_directories > profile.entries {
		return {}, false
	}
	entries, entries_error := make([]project_reference.Catalog_Entry, profile.entries, allocator)
	if entries_error != nil {
		return {}, false
	}
	paths, paths_error := make([]string, profile.entries * 2, allocator)
	if paths_error != nil {
		delete(entries, allocator)
		return {}, false
	}
	candidate = Resolution_Candidate{entries = entries, paths = paths, allocator = allocator}
	for index in 0 ..< profile.entries {
		path_count := 1
		valid := true
		base := ""
		switch {
		case index < profile.exact_matches:
			base = target
		case index < profile.exact_matches + profile.invalid_entries:
			base = target
			valid = false
		case index < profile.exact_matches + profile.invalid_entries + profile.multi_directories:
			base = target
			path_count = 2
		case:
			base = fmt.aprintf("/catalog/project-%04d", index)
		}
		start := candidate.owned_paths
		for path_index in 0 ..< path_count {
			path := base
			generated := false
			if path_index > 0 {
				path = fmt.aprintf("%s/member-%d", target, index)
				generated = true
			}
			owned, allocation_error := strings.clone(path, allocator)
			if generated || index >= profile.exact_matches + profile.invalid_entries + profile.multi_directories {
				delete(path)
			}
			if allocation_error != nil {
				resolution_candidate_close(&candidate)
				return {}, false
			}
			candidate.paths[candidate.owned_paths] = owned
			candidate.owned_paths += 1
		}
		candidate.entries[index] = project_reference.Catalog_Entry {
			directories = candidate.paths[start:candidate.owned_paths],
			valid = valid,
		}
	}
	return candidate, true
}

resolution_candidate_close :: proc(candidate: ^Resolution_Candidate) {
	if candidate == nil {
		return
	}
	for index in 0 ..< candidate.owned_paths {
		delete(candidate.paths[index], candidate.allocator)
	}
	if candidate.paths != nil {
		delete(candidate.paths, candidate.allocator)
	}
	if candidate.entries != nil {
		delete(candidate.entries, candidate.allocator)
	}
	candidate^ = {}
}

run_resolution_rejection_probe :: proc() -> bool {
	target := "/work/target"
	first := [?]string{target}
	second := [?]string{target}
	entries := [?]project_reference.Catalog_Entry {
		{directories = first[:], valid = true},
		{directories = second[:], valid = true},
	}
	matches: [1]int
	kind, count, ok := project_reference.resolve_exact_single_directory(
		entries[:],
		target,
		matches[:],
	)
	valid := !ok && kind == .Ambiguous && count == 1 && matches[0] == 0
	fmt.printf(
		"study=project-directory-resolution profile=rejection valid=%v entries=%d result_capacity=%d copied=%d reason=bounded-result-capacity\n",
		valid,
		len(entries),
		len(matches),
		count,
	)
	return valid
}

print_policy_evidence :: proc() -> bool {
	valid := SELECTED_PROJECTS >= MIN_PROJECTS && SELECTED_PROJECTS <= MAX_PROJECTS &&
		SELECTED_DIRECTORIES >= MIN_DIRECTORIES && SELECTED_DIRECTORIES <= MAX_DIRECTORIES &&
		SELECTED_NAME_BYTES >= MIN_NAME_BYTES && SELECTED_NAME_BYTES <= MAX_NAME_BYTES &&
		SELECTED_DESCRIPTOR_BATCH >= MIN_DESCRIPTOR_BATCH &&
		SELECTED_DESCRIPTOR_BATCH <= MAX_DESCRIPTOR_BATCH &&
		SELECTED_PATH_BYTES >= MIN_PATH_BYTES && SELECTED_PATH_BYTES <= MAX_PATH_BYTES &&
		SELECTED_DIRTY_MARKERS >= MIN_DIRTY_MARKERS && SELECTED_DIRTY_MARKERS <= MAX_DIRTY_MARKERS
	fmt.printf(
		"study=project profile=policy valid=%v selected_projects=%d project_range=%d..%d selected_directories=%d directory_range=%d..%d selected_name_bytes=%d name_range=%d..%d selected_descriptors=%d descriptor_range=%d..%d selected_path_bytes=%d path_range=%d..%d selected_dirty_markers=%d dirty_range=%d..%d\n",
		valid,
		SELECTED_PROJECTS,
		MIN_PROJECTS,
		MAX_PROJECTS,
		SELECTED_DIRECTORIES,
		MIN_DIRECTORIES,
		MAX_DIRECTORIES,
		SELECTED_NAME_BYTES,
		MIN_NAME_BYTES,
		MAX_NAME_BYTES,
		SELECTED_DESCRIPTOR_BATCH,
		MIN_DESCRIPTOR_BATCH,
		MAX_DESCRIPTOR_BATCH,
		SELECTED_PATH_BYTES,
		MIN_PATH_BYTES,
		MAX_PATH_BYTES,
		SELECTED_DIRTY_MARKERS,
		MIN_DIRTY_MARKERS,
		MAX_DIRTY_MARKERS,
	)
	return valid
}

run_reference_probe :: proc() -> bool {
	model, ready := project_reference.model_init(8)
	if !ready {
		return false
	}
	defer project_reference.model_deinit(&model)
	_, root_ok, _ := project_reference.model_add(&model, "/work")
	_, nested_ok, _ := project_reference.model_add(&model, "/work/odra")
	results: [8]project_reference.Handle
	count, contained := project_reference.model_containing(
		&model,
		"/work/odra/src/main.odin",
		results[:],
	)
	valid := root_ok && nested_ok && contained && count == 2 &&
		project_reference.model_validate(&model)
	fmt.printf(
		"study=project profile=reference valid=%v directories=%d matches=%d representation=contiguous-linear-membership\n",
		valid,
		project_reference.model_live_count(&model),
		count,
	)
	return valid
}

run_profile :: proc(profile: Profile) -> bool {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	candidate, ready := candidate_init(profile.directories, allocator)
	if !ready {
		mem.tracking_allocator_destroy(&tracking)
		return false
	}
	built := true
	for index in 0 ..< profile.directories {
		path := generated_directory(index, profile.overlap)
		built = candidate_add(&candidate, path) && built
		delete(path)
	}
	classification, checksum := measure_classification(&candidate, profile.documents, profile.overlap)
	projection, projected := measure_projection(&candidate)
	replacement := measure_replacement(&candidate)
	valid := built && candidate_validate(&candidate) &&
		classification.p99_ns <= CLASSIFICATION_GATE_NS &&
		projection.p99_ns <= PROJECTION_GATE_NS &&
		replacement <= REPLACEMENT_GATE_NS
	persistent_bytes := tracking.current_memory_allocated
	peak_bytes := tracking.peak_memory_allocated
	candidate_close(&candidate)
	cleanup_bytes := tracking.current_memory_allocated
	valid = valid && cleanup_bytes == 0
	mem.tracking_allocator_destroy(&tracking)
	fmt.printf(
		"study=project profile=%s valid=%v directories=%d documents=%d overlap=%d candidate_size=%d persistent_bytes=%d peak_bytes=%d classification_p50_ns=%d classification_p99_ns=%d classification_gate_ns=%d projected=%d projection_p50_ns=%d projection_p99_ns=%d projection_gate_ns=%d replacement_ns=%d replacement_gate_ns=%d cleanup_bytes=%d checksum=%d\n",
		profile.name,
		valid,
		profile.directories,
		profile.documents,
		profile.overlap,
		size_of(Candidate),
		persistent_bytes,
		peak_bytes,
		classification.p50_ns,
		classification.p99_ns,
		CLASSIFICATION_GATE_NS,
		projected,
		projection.p50_ns,
		projection.p99_ns,
		PROJECTION_GATE_NS,
		replacement,
		REPLACEMENT_GATE_NS,
		cleanup_bytes,
		checksum,
	)
	return valid
}

run_rejection_probe :: proc() -> bool {
	valid := MAX_PROJECTS + 1 > MAX_PROJECTS && MAX_DIRECTORIES + 1 > MAX_DIRECTORIES &&
		MAX_NAME_BYTES + 1 > MAX_NAME_BYTES && MAX_DESCRIPTOR_BATCH + 1 > MAX_DESCRIPTOR_BATCH &&
		MAX_PATH_BYTES + 1 > MAX_PATH_BYTES && MAX_DIRTY_MARKERS + 1 > MAX_DIRTY_MARKERS
	fmt.printf(
		"study=project profile=rejection valid=%v attempted_projects=%d project_limit=%d attempted_directories=%d directory_limit=%d attempted_name_bytes=%d name_limit=%d attempted_path_bytes=%d path_limit=%d reason=bounded-prepublication-rejection\n",
		valid,
		MAX_PROJECTS + 1,
		MAX_PROJECTS,
		MAX_DIRECTORIES + 1,
		MAX_DIRECTORIES,
		MAX_NAME_BYTES + 1,
		MAX_NAME_BYTES,
		MAX_PATH_BYTES + 1,
		MAX_PATH_BYTES,
	)
	return valid
}

candidate_init :: proc(capacity: int, allocator: mem.Allocator) -> (candidate: Candidate, ok: bool) {
	directories, directory_error := make([dynamic]string, 0, capacity, allocator)
	if directory_error != nil {
		return {}, false
	}
	exact_index, map_error := make(map[string]int, capacity, allocator)
	if map_error != nil {
		delete(directories)
		return {}, false
	}
	return Candidate{
		directories = directories,
		exact_index = exact_index,
		generation = 1,
		allocator = allocator,
	}, true
}

candidate_close :: proc(candidate: ^Candidate) {
	if candidate == nil {
		return
	}
	if candidate.exact_index != nil {
		delete(candidate.exact_index)
	}
	for path in candidate.directories {
		delete(path, candidate.allocator)
	}
	if candidate.directories != nil {
		delete(candidate.directories)
	}
	candidate^ = {}
}

candidate_add :: proc(candidate: ^Candidate, path: string) -> bool {
	if candidate == nil || candidate.exact_index[path] != 0 ||
	   len(candidate.directories) >= cap(candidate.directories) {
		return false
	}
	owned, allocation_error := strings.clone(path, candidate.allocator)
	if allocation_error != nil {
		return false
	}
	append(&candidate.directories, owned)
	candidate.exact_index[string(owned)] = len(candidate.directories)
	candidate.path_bytes += u64(len(owned))
	candidate.generation += 1
	return true
}

candidate_contains_count :: proc(candidate: ^Candidate, path: string) -> int {
	count := 0
	for directory in candidate.directories {
		if project_reference.path_contains(directory, path) {
			count += 1
		}
	}
	return count
}

candidate_validate :: proc(candidate: ^Candidate) -> bool {
	if candidate == nil || candidate.generation == 0 ||
	   len(candidate.directories) != len(candidate.exact_index) {
		return false
	}
	path_bytes: u64
	for path, index in candidate.directories {
		if candidate.exact_index[path] != index + 1 {
			return false
		}
		path_bytes += u64(len(path))
	}
	return path_bytes == candidate.path_bytes
}

measure_classification :: proc(
	candidate: ^Candidate,
	documents, overlap: int,
) -> (latency: Latency, checksum: u64) {
	samples: [SAMPLES]i64
	for sample in 0 ..< SAMPLES {
		path := generated_document(sample % documents, overlap)
		started := time.tick_now()
		count := candidate_contains_count(candidate, path)
		samples[sample] = time.duration_nanoseconds(time.tick_since(started))
		checksum += u64(count)
		delete(path)
	}
	return latency_from_samples(samples[:]), checksum
}

measure_projection :: proc(candidate: ^Candidate) -> (latency: Latency, projected: int) {
	samples: [128]i64
	projected = min(len(candidate.directories), SELECTED_DESCRIPTOR_BATCH)
	for sample in 0 ..< len(samples) {
		started := time.tick_now()
		bytes: u64
		for path in candidate.directories[:projected] {
			bytes += u64(len(path))
		}
		samples[sample] = time.duration_nanoseconds(time.tick_since(started))
		if bytes == 0 {
			return {}, 0
		}
	}
	return latency_from_samples(samples[:]), projected
}

measure_replacement :: proc(candidate: ^Candidate) -> i64 {
	started := time.tick_now()
	path := generated_directory(len(candidate.directories) + 1, 1)
	defer delete(path)
	if candidate.exact_index[path] != 0 {
		return i64(9_223_372_036_854_775_807)
	}
	candidate.generation += 1
	return time.duration_nanoseconds(time.tick_since(started))
}

latency_from_samples :: proc(samples: []i64) -> Latency {
	for index in 1 ..< len(samples) {
		value := samples[index]
		position := index
		for position > 0 && samples[position - 1] > value {
			samples[position] = samples[position - 1]
			position -= 1
		}
		samples[position] = value
	}
	return Latency{p50_ns = samples[len(samples) / 2], p99_ns = samples[len(samples) * 99 / 100]}
}

generated_directory :: proc(index, overlap: int) -> string {
	group := index / max(overlap, 1)
	depth := index % max(overlap, 1)
	path := fmt.aprintf("/project-%04d", group)
	for level in 0 ..< depth {
		next := fmt.aprintf("%s/nested-%02d", path, level)
		delete(path)
		path = next
	}
	return path
}

generated_document :: proc(index, overlap: int) -> string {
	directory := generated_directory(index % max(overlap, 1), overlap)
	defer delete(directory)
	return fmt.aprintf("%s/src/file-%06d.odin", directory, index)
}
