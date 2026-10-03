// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery

import "base:runtime"

/* Path_Detail_Kind identifies the repository state used to inspect one path. */
Path_Detail_Kind :: enum u8 {
	Invalid,
	Unmerged,
	Untracked,
	Unstaged,
	Staged,
}

/* Path_Detail_Descriptor is copied metadata for one bounded read-only detail. */
Path_Detail_Descriptor :: struct {
	target:    Path_Target,
	kind:      Path_Detail_Kind,
	bytes:     u64,
	truncated: bool,
}

/* Path_Detail owns one copied bounded path inspection result. */
Path_Detail :: struct {
	state: rawptr,
}

@(private)
Path_Detail_Data :: struct {
	descriptor: Path_Detail_Descriptor,
	content:    [dynamic]u8,
	allocator:  runtime.Allocator,
}

/* path_detail_kind_for_path selects the read-only inspection state for one path. */
path_detail_kind_for_path :: proc(path: Status_Path) -> Path_Detail_Kind {
	switch path.group {
	case .Unmerged: return .Unmerged
	case .Untracked: return .Untracked
	case .Unstaged: return .Unstaged
	case .Staged: return .Staged
	case .Invalid: return .Invalid
	}
	return .Invalid
}

/* path_detail_open copies one bounded detail result for an exact Status path. */
path_detail_open :: proc(
	observation: ^Status_Observation,
	target: Path_Target,
	content: []u8,
	truncated: bool,
	limits: Process_Limits,
	allocator := context.allocator,
) -> (Path_Detail, bool, Failure_Code) {
	descriptor, available := status_observation_descriptor(observation)
	if allocator.procedure == nil || !available || !process_limits_are_valid(limits) ||
	   !path_target_is_valid(target) || target.generation != descriptor.generation {
		return {}, false, .Stale_Observation
	}
	path, found := status_observation_path_by_id(observation, target.path)
	if !found do return {}, false, .Path_Unavailable
	if u64(len(content)) > limits.diff_bytes do return {}, false, .Output_Limit
	state, allocation_error := new(Path_Detail_Data, allocator)
	if allocation_error != nil do return {}, false, .Allocation
	state.allocator = allocator
	state.descriptor = {
		target = target,
		kind = path_detail_kind_for_path(path),
		bytes = u64(len(content)),
		truncated = truncated,
	}
	state.content, allocation_error = make([dynamic]u8, 0, len(content), allocator)
	if allocation_error != nil {
		path_detail_data_destroy(state)
		return {}, false, .Allocation
	}
	if len(content) > 0 {
		_, allocation_error = append(&state.content, ..content)
		if allocation_error != nil {
			path_detail_data_destroy(state)
			return {}, false, .Allocation
		}
	}
	return Path_Detail{state = state}, true, .None
}

/* repository_process_take_path_detail copies a completed or truncated detail result. */
repository_process_take_path_detail :: proc(
	process: ^Repository_Process,
	observation: ^Status_Observation,
	allocator := context.allocator,
) -> (Path_Detail, bool, Failure_Code) {
	state := repository_process_data(process)
	if state == nil || state.request.kind != .Inspect_Path do return {}, false, .Invalid_Request
	if state.state != .Completed && !(state.state == .Failed && state.failure == .Output_Limit) {
		return {}, false, state.failure
	}
	return path_detail_open(
		observation,
		state.request.target,
		state.output[:],
		state.failure == .Output_Limit,
		state.request.limits,
		allocator,
	)
}

/* path_detail_descriptor returns copied immutable detail metadata. */
path_detail_descriptor :: proc(detail: ^Path_Detail) -> (Path_Detail_Descriptor, bool) {
	state := path_detail_data(detail)
	if state == nil do return {}, false
	return state.descriptor, true
}

/* path_detail_content returns borrowed copied bytes owned by this detail result. */
path_detail_content :: proc(detail: ^Path_Detail) -> ([]u8, bool) {
	state := path_detail_data(detail)
	if state == nil do return nil, false
	return state.content[:], true
}

/* path_detail_is_current rejects retained detail after a fresh observation replaces it. */
path_detail_is_current :: proc(detail: ^Path_Detail, observation: ^Status_Observation) -> bool {
	state := path_detail_data(detail)
	descriptor, available := status_observation_descriptor(observation)
	if state == nil || !available || state.descriptor.target.generation != descriptor.generation do return false
	_, found := status_observation_path_by_id(observation, state.descriptor.target.path)
	return found
}

/* path_detail_close releases every owned detail allocation. */
path_detail_close :: proc(detail: ^Path_Detail) {
	state := path_detail_data(detail)
	if state == nil do return
	path_detail_data_destroy(state)
	detail^ = {}
}

@(private)
path_detail_data :: proc(detail: ^Path_Detail) -> ^Path_Detail_Data {
	if detail == nil || detail.state == nil do return nil
	return cast(^Path_Detail_Data)detail.state
}

@(private)
path_detail_data_destroy :: proc(state: ^Path_Detail_Data) {
	if state == nil do return
	delete(state.content)
	free(state, state.allocator)
}
