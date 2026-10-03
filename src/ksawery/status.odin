// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery

import "base:runtime"

/* Status_Observation owns one parsed immutable repository status result. */
Status_Observation :: struct {
	state: rawptr,
}

@(private)
Status_Observation_Data :: struct {
	descriptor:  Observation_Descriptor,
	paths:       [dynamic]Status_Path,
	path_storage: [dynamic]u8,
	diagnostic:  [dynamic]u8,
	allocator:   runtime.Allocator,
}

/* repository_process_take_status parses the completed bounded process output. */
repository_process_take_status :: proc(
	process: ^Repository_Process,
	generation: Observation_Generation,
	allocator := context.allocator,
) -> (Status_Observation, bool, Failure_Code) {
	state := repository_process_data(process)
	if state == nil || state.state != .Completed do return {}, false, .Invalid_Request
	return status_observation_open(
		state.request.repository,
		generation,
		state.output[:],
		state.diagnostic[:],
		state.request.limits,
		allocator,
	)
}

/* status_observation_open parses one bounded porcelain-v2 status result. */
status_observation_open :: proc(
	repository: Repository_Context,
	generation: Observation_Generation,
	output: []u8,
	diagnostic: []u8,
	limits: Process_Limits,
	allocator := context.allocator,
) -> (Status_Observation, bool, Failure_Code) {
	if allocator.procedure == nil || !repository_context_is_valid(repository) ||
	   generation == Observation_Generation(0) || !process_limits_are_valid(limits) ||
	   u64(len(output)) > limits.stdout_bytes || u64(len(diagnostic)) > limits.diagnostic_bytes {
		return {}, false, .Invalid_Request
	}
	state, allocation_error := new(Status_Observation_Data, allocator)
	if allocation_error != nil do return {}, false, .Allocation
	state.allocator = allocator
	state.descriptor.repository = repository
	state.descriptor.generation = generation
	state.descriptor.operation = .Normal
	if !branch_label_assign(&state.descriptor.branch, "HEAD") {
		status_observation_data_destroy(state)
		return {}, false, .Allocation
	}
	state.paths, allocation_error = make([dynamic]Status_Path, 0, min(int(limits.status_paths), 64), allocator)
	if allocation_error != nil {
		status_observation_data_destroy(state)
		return {}, false, .Allocation
	}
	state.path_storage, allocation_error = make([dynamic]u8, 0, min(int(limits.status_path_bytes), int(4 * KIBIBYTE)), allocator)
	if allocation_error != nil {
		status_observation_data_destroy(state)
		return {}, false, .Allocation
	}
	state.diagnostic, allocation_error = make([dynamic]u8, 0, len(diagnostic), allocator)
	if allocation_error != nil {
		status_observation_data_destroy(state)
		return {}, false, .Allocation
	}
	if len(diagnostic) > 0 {
		_, allocation_error = append(&state.diagnostic, ..diagnostic)
		if allocation_error != nil {
			status_observation_data_destroy(state)
			return {}, false, .Allocation
		}
	}
	if failure := status_observation_parse(state, output, limits); failure != .None {
		status_observation_data_destroy(state)
		return {}, false, failure
	}
	state.descriptor.path_count = u32(len(state.paths))
	state.descriptor.path_bytes = u64(len(state.path_storage))
	state.descriptor.diagnostic_bytes = u64(len(state.diagnostic))
	if !observation_descriptor_is_valid(state.descriptor, limits) {
		status_observation_data_destroy(state)
		return {}, false, .Parse
	}
	return Status_Observation{state = state}, true, .None
}

/* status_observation_descriptor returns copied immutable status metadata. */
status_observation_descriptor :: proc(observation: ^Status_Observation) -> (Observation_Descriptor, bool) {
	state := status_observation_data(observation)
	if state == nil do return {}, false
	return state.descriptor, true
}

/* status_observation_path_count reports the number of semantic changed paths. */
status_observation_path_count :: proc(observation: ^Status_Observation) -> (u32, bool) {
	state := status_observation_data(observation)
	if state == nil do return 0, false
	return u32(len(state.paths)), true
}

/* status_observation_path returns one copied semantic changed path. */
status_observation_path :: proc(observation: ^Status_Observation, index: u32) -> (Status_Path, bool) {
	state := status_observation_data(observation)
	if state == nil || int(index) >= len(state.paths) do return {}, false
	return state.paths[int(index)], true
}

/* status_observation_path_text returns borrowed copied path bytes for one listed path. */
status_observation_path_text :: proc(observation: ^Status_Observation, path: Status_Path) -> ([]u8, bool) {
	state := status_observation_data(observation)
	end := u64(path.text.offset) + u64(path.text.length)
	if state == nil || end > u64(len(state.path_storage)) do return nil, false
	return state.path_storage[int(path.text.offset):int(end)], true
}

/* status_observation_close releases every owned parsed status allocation. */
status_observation_close :: proc(observation: ^Status_Observation) {
	state := status_observation_data(observation)
	if state == nil do return
	status_observation_data_destroy(state)
	observation^ = {}
}

@(private)
status_observation_data :: proc(observation: ^Status_Observation) -> ^Status_Observation_Data {
	if observation == nil || observation.state == nil do return nil
	return cast(^Status_Observation_Data)observation.state
}

@(private)
status_observation_parse :: proc(
	state: ^Status_Observation_Data,
	output: []u8,
	limits: Process_Limits,
) -> Failure_Code {
	offset := 0
	for offset < len(output) {
		end := offset
		for end < len(output) && output[end] != 0 do end += 1
		record := output[offset:end]
		next := end + 1
		if len(record) == 0 {
			offset = next
			continue
		}
		switch record[0] {
		case '#':
			if !status_observation_parse_branch(state, record) do return .Parse
		case '?':
			if len(record) < 3 || record[1] != ' ' do return .Parse
			if failure := status_observation_append_path(state, .Untracked, 0, 0, record[2:], limits); failure != .None do return failure
		case '1', '2':
			if len(record) < 4 do return .Parse
			indexed := record[2] != '.' && record[2] != ' '
			working := record[3] != '.' && record[3] != ' '
			if !indexed && !working do return .Parse
			field_count := 8
			if record[0] == '2' do field_count = 9
			path, found := status_observation_path_after_fields(record, field_count)
			if !found do return .Parse
			if indexed {
				if failure := status_observation_append_path(state, .Staged, record[2], record[3], path, limits); failure != .None do return failure
			}
			if working {
				if failure := status_observation_append_path(state, .Unstaged, record[2], record[3], path, limits); failure != .None do return failure
			}
			if record[0] == '2' {
				if end >= len(output) do return .Parse
				origin_end := next
				for origin_end < len(output) && output[origin_end] != 0 do origin_end += 1
				if origin_end == next do return .Parse
				next = origin_end + 1
			}
		case 'u':
			if len(record) < 4 do return .Parse
			path, found := status_observation_path_after_fields(record, 10)
			if !found do return .Parse
			if failure := status_observation_append_path(state, .Unmerged, record[2], record[3], path, limits); failure != .None do return failure
		case '!':
			// Ignored paths do not belong in the actionable Status projection.
		case:
			return .Parse
		}
		offset = next
	}
	return .None
}

@(private)
status_observation_parse_branch :: proc(state: ^Status_Observation_Data, record: []u8) -> bool {
	prefix := "# branch.head "
	if len(record) < len(prefix) || string(record[:len(prefix)]) != prefix do return true
	return branch_label_assign(&state.descriptor.branch, string(record[len(prefix):]))
}

@(private)
status_observation_path_after_fields :: proc(record: []u8, field_count: int) -> ([]u8, bool) {
	offset := 0
	for _ in 0 ..< field_count {
		for offset < len(record) && record[offset] != ' ' do offset += 1
		if offset >= len(record) do return nil, false
		offset += 1
	}
	return record[offset:], offset < len(record)
}

@(private)
status_observation_append_path :: proc(
	state: ^Status_Observation_Data,
	group: Change_Group,
	index: u8,
	worktree: u8,
	path: []u8,
	limits: Process_Limits,
) -> Failure_Code {
	if len(path) == 0 || len(state.paths) >= int(limits.status_paths) ||
	   u64(len(state.path_storage)) + u64(len(path)) > limits.status_path_bytes {
		return .Output_Limit
	}
	entry := Status_Path {
		id = Path_ID(u32(len(state.paths)) + 1),
		group = group,
		text = {offset = u32(len(state.path_storage)), length = u32(len(path))},
		index = index,
		worktree = worktree,
	}
	_, allocation_error := append(&state.path_storage, ..path)
	if allocation_error != nil do return .Allocation
	_, allocation_error = append(&state.paths, entry)
	if allocation_error != nil do return .Allocation
	return .None
}

@(private)
status_observation_data_destroy :: proc(state: ^Status_Observation_Data) {
	if state == nil do return
	delete(state.paths)
	delete(state.path_storage)
	delete(state.diagnostic)
	free(state, state.allocator)
}
