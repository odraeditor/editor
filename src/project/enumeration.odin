// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package project

import "../document"
import "base:runtime"
import "core:os"
import "core:slice"
import "core:strings"

@(private)
File_Candidate_Owner :: struct {
	path:             string,
	membership_count: u32,
}

@(private)
File_Enumerator_State :: struct {
	dir:                Dir_Handle,
	project:            Project_Handle,
	root_paths:         []string,
	candidates:         [dynamic]File_Candidate_Owner,
	root_index:         int,
	walker:             os.Walker,
	walker_active:      bool,
	examined_entries:   u32,
	retained_path_bytes: u64,
	generation:         File_Enumeration_Generation,
	complete:           bool,
	cancelled:          bool,
	policy:             Policy,
	allocators:         Allocator_Set,
}

@(private)
File_Candidate_Batch_State :: struct {
	descriptors: []File_Candidate_Descriptor,
	paths:       []u8,
	allocator:   runtime.Allocator,
}

/* file_enumerator_init copies exact Project roots and prepares private bounded traversal. */
file_enumerator_init :: proc(
	enumerator: ^File_Enumerator,
	project: Project_Handle,
	memberships: []Membership_Descriptor,
	policy: Policy,
	allocators: Allocator_Set,
) -> (ok: bool, failure: Failure_Context) {
	if !project_handle_is_valid(project) || len(memberships) == 0 {
		return false, Failure_Context{code = .Invalid_Project, operation = .Initialize_File_Enumeration, project = project}
	}
	if len(memberships) > int(policy.directories) {
		failure = enumeration_failure(project, .Initialize_File_Enumeration, .Directory_Limit)
		failure.maximum = u64(policy.directories)
		failure.actual = u64(len(memberships))
		return false, failure
	}
	paths: [int(MAX_DIRECTORIES)]string
	for descriptor, index in memberships {
		if descriptor.handle.project != project || !membership_handle_is_valid(descriptor.handle) {
			return false, Failure_Context{
				code = .Stale_Membership,
				operation = .Initialize_File_Enumeration,
				project = project,
				membership = descriptor.handle,
			}
		}
		paths[index] = directory_path_text(&memberships[index].path)
	}
	return file_root_enumerator_init(enumerator, {}, project, paths[:len(memberships)], policy, allocators)
}

/* dir_file_enumerator_init prepares the same bounded traversal for one ordinary Dir. */
dir_file_enumerator_init :: proc(
	enumerator: ^File_Enumerator,
	dir: Dir_Handle,
	path: string,
	policy: Policy,
	allocators: Allocator_Set,
) -> (ok: bool, failure: Failure_Context) {
	if !dir_handle_is_valid(dir) {
		return false, Failure_Context{code = .Invalid_Dir, operation = .Initialize_File_Enumeration}
	}
	return file_root_enumerator_init(enumerator, dir, {}, []string{path}, policy, allocators)
}

@(private)
file_root_enumerator_init :: proc(
	enumerator: ^File_Enumerator,
	dir: Dir_Handle,
	project: Project_Handle,
	paths: []string,
	policy: Policy,
	allocators: Allocator_Set,
) -> (ok: bool, failure: Failure_Context) {
	assert(enumerator != nil)
	enumerator^ = {}
	dir_scope := dir_handle_is_valid(dir)
	project_scope := project_handle_is_valid(project)
	if dir_scope == project_scope || len(paths) == 0 {
		return false, file_scope_failure(dir, project, .Initialize_File_Enumeration, .Invalid_Registry)
	}
	if policy_ok, policy_failure := policy_validate(policy); !policy_ok {
		policy_failure.operation = .Initialize_File_Enumeration
		policy_failure.project = project
		return false, policy_failure
	}
	if allocators.persistent.procedure == nil || allocators.temporary.procedure == nil {
		return false, file_scope_failure(dir, project, .Initialize_File_Enumeration, .Persistent_Memory_Limit)
	}
	if len(paths) > int(policy.directories) {
		failure = file_scope_failure(dir, project, .Initialize_File_Enumeration, .Directory_Limit)
		failure.maximum = u64(policy.directories)
		failure.actual = u64(len(paths))
		return false, failure
	}
	state, state_error := new(File_Enumerator_State, allocators.persistent)
	if state_error != nil {
		return false, file_scope_failure(dir, project, .Initialize_File_Enumeration, .Persistent_Memory_Limit)
	}
	state.dir = dir
	state.project = project
	state.policy = policy
	state.allocators = allocators
	state.generation = File_Enumeration_Generation(1)
	state.root_paths, state_error = make([]string, len(paths), allocators.persistent)
	if state_error != nil {
		file_enumerator_state_destroy(state)
		return false, file_scope_failure(dir, project, .Initialize_File_Enumeration, .Persistent_Memory_Limit)
	}
	state.candidates, state_error = make(
		[dynamic]File_Candidate_Owner,
		0,
		int(policy.file_candidates),
		allocators.persistent,
	)
	if state_error != nil {
		file_enumerator_state_destroy(state)
		return false, file_scope_failure(dir, project, .Initialize_File_Enumeration, .Persistent_Memory_Limit)
	}
	for path, index in paths {
		normalized: document.Normalized_Path
		normalized_ok, _ := document.path_normalize(path, &normalized, allocators.temporary)
		if !normalized_ok || document.normalized_path_text(&normalized) != path {
			file_enumerator_state_destroy(state)
			return false, file_scope_failure(dir, project, .Initialize_File_Enumeration, .Invalid_Path)
		}
		owned, path_error := strings.clone(path, allocators.persistent)
		if path_error != nil {
			file_enumerator_state_destroy(state)
			return false, file_scope_failure(dir, project, .Initialize_File_Enumeration, .Persistent_Memory_Limit)
		}
		state.root_paths[index] = owned
	}
	enumerator.state = state
	return true, {}
}

/* file_enumerator_advance performs at most one configured turn and publishes only complete candidates. */
file_enumerator_advance :: proc(
	enumerator: ^File_Enumerator,
	project: Project_Handle,
	cancelled := false,
) -> (result: File_Enumeration_Result, ok: bool, failure: Failure_Context) {
	return file_root_enumerator_advance(enumerator, {}, project, cancelled)
}

/* dir_file_enumerator_advance performs one bounded ordinary-Dir traversal turn. */
dir_file_enumerator_advance :: proc(
	enumerator: ^File_Enumerator,
	dir: Dir_Handle,
	cancelled := false,
) -> (result: File_Enumeration_Result, ok: bool, failure: Failure_Context) {
	return file_root_enumerator_advance(enumerator, dir, {}, cancelled)
}

@(private)
file_root_enumerator_advance :: proc(
	enumerator: ^File_Enumerator,
	dir: Dir_Handle,
	project: Project_Handle,
	cancelled: bool,
) -> (result: File_Enumeration_Result, ok: bool, failure: Failure_Context) {
	state, resolved := file_enumerator_resolve(enumerator, dir, project, .Enumerate_Files)
	if resolved.code != .None {
		return {}, false, resolved
	}
	result.dir = dir
	result.project = project
	result.generation = state.generation
	result.examined_entries = state.examined_entries
	result.candidate_count = u32(len(state.candidates))
	if state.cancelled {
		result.cancelled = true
		return result, true, {}
	}
	if state.complete {
		result.complete = true
		return result, true, {}
	}
	if cancelled {
		if state.walker_active {
			os.walker_destroy(&state.walker)
			state.walker = {}
			state.walker_active = false
		}
		file_enumerator_candidates_clear(state)
		state.cancelled = true
		result.cancelled = true
		result.candidate_count = 0
		return result, true, {}
	}

	for result.processed_entries < state.policy.entries_per_turn {
		if !state.walker_active {
			for state.root_index < len(state.root_paths) && !os.is_directory(state.root_paths[state.root_index]) {
				state.root_index += 1
			}
			if state.root_index >= len(state.root_paths) {
				slice.sort_by(state.candidates[:], file_candidate_less)
				state.complete = true
				result.complete = true
				break
			}
			os.walker_init(&state.walker, state.root_paths[state.root_index])
			state.walker_active = true
		}

		info, walked := os.walker_walk(&state.walker)
		if _, walk_error := os.walker_error(&state.walker); walk_error != nil {
			return {}, false, file_scope_failure(dir, project, .Enumerate_Files, .Filesystem_Failure)
		}
		if !walked {
			os.walker_destroy(&state.walker)
			state.walker = {}
			state.walker_active = false
			state.root_index += 1
			continue
		}

		if state.examined_entries >= state.policy.examined_entries {
			failure = file_scope_failure(dir, project, .Enumerate_Files, .Examined_Entry_Limit)
			failure.maximum = u64(state.policy.examined_entries)
			failure.actual = u64(state.examined_entries) + 1
			return {}, false, failure
		}
		state.examined_entries += 1
		result.processed_entries += 1
		if len(info.name) > 0 && info.name[0] == '.' {
			if info.type == .Directory do os.walker_skip_dir(&state.walker)
			continue
		}
		if info.type != .Regular {
			continue
		}
		normalized: document.Normalized_Path
		normalized_ok, _ := document.path_normalize(info.fullpath, &normalized, state.allocators.temporary)
		if !normalized_ok {
			continue
		}
		path := document.normalized_path_text(&normalized)
		if file_candidate_find(state.candidates[:], path) >= 0 {
			continue
		}
		if len(state.candidates) >= int(state.policy.file_candidates) {
			failure = file_scope_failure(dir, project, .Enumerate_Files, .File_Candidate_Limit)
			failure.maximum = u64(state.policy.file_candidates)
			failure.actual = u64(len(state.candidates)) + 1
			return {}, false, failure
		}
		if state.retained_path_bytes + u64(len(path)) > state.policy.retained_path_bytes {
			failure = file_scope_failure(dir, project, .Enumerate_Files, .Retained_Path_Limit)
			failure.maximum = state.policy.retained_path_bytes
			failure.actual = state.retained_path_bytes + u64(len(path))
			return {}, false, failure
		}
		owned, path_error := strings.clone(path, state.allocators.persistent)
		if path_error != nil {
			return {}, false, file_scope_failure(dir, project, .Enumerate_Files, .Persistent_Memory_Limit)
		}
		append(&state.candidates, File_Candidate_Owner{
			path = owned,
			membership_count = file_candidate_membership_count(state.root_paths, path),
		})
		state.retained_path_bytes += u64(len(path))
	}
	result.examined_entries = state.examined_entries
	result.candidate_count = u32(len(state.candidates))
	return result, true, {}
}

/* file_enumerator_candidates copies one complete generation and rejects stale Project consumers. */
file_enumerator_candidates :: proc(
	enumerator: ^File_Enumerator,
	project: Project_Handle,
) -> (batch: File_Candidate_Batch, ok: bool, failure: Failure_Context) {
	return file_root_enumerator_candidates(enumerator, {}, project)
}

/* dir_file_enumerator_candidates copies one complete ordinary-Dir candidate generation. */
dir_file_enumerator_candidates :: proc(
	enumerator: ^File_Enumerator,
	dir: Dir_Handle,
) -> (batch: File_Candidate_Batch, ok: bool, failure: Failure_Context) {
	return file_root_enumerator_candidates(enumerator, dir, {})
}

@(private)
file_root_enumerator_candidates :: proc(
	enumerator: ^File_Enumerator,
	dir: Dir_Handle,
	project: Project_Handle,
) -> (batch: File_Candidate_Batch, ok: bool, failure: Failure_Context) {
	state, resolved := file_enumerator_resolve(enumerator, dir, project, .File_Candidates)
	if resolved.code != .None {
		return {}, false, resolved
	}
	if !state.complete || state.cancelled {
		return {}, false, file_scope_failure(dir, project, .File_Candidates, .Invariant_Violation)
	}
	owner, owner_error := new(File_Candidate_Batch_State, state.allocators.persistent)
	if owner_error != nil {
		return {}, false, file_scope_failure(dir, project, .File_Candidates, .Persistent_Memory_Limit)
	}
	owner.allocator = state.allocators.persistent
	owner.descriptors, owner_error = make([]File_Candidate_Descriptor, len(state.candidates), owner.allocator)
	if owner_error != nil {
		file_candidate_batch_state_destroy(owner)
		return {}, false, file_scope_failure(dir, project, .File_Candidates, .Persistent_Memory_Limit)
	}
	owner.paths, owner_error = make([]u8, int(state.retained_path_bytes), owner.allocator)
	if owner_error != nil {
		file_candidate_batch_state_destroy(owner)
		return {}, false, file_scope_failure(dir, project, .File_Candidates, .Persistent_Memory_Limit)
	}
	offset := 0
	for candidate, index in state.candidates {
		copy(owner.paths[offset:], transmute([]u8)candidate.path)
		owner.descriptors[index] = File_Candidate_Descriptor{
			dir = dir,
			project = project,
			generation = state.generation,
			path = string(owner.paths[offset:offset + len(candidate.path)]),
			membership_count = candidate.membership_count,
		}
		offset += len(candidate.path)
	}
	assert(offset == len(owner.paths))
	batch = File_Candidate_Batch{
		state = owner,
		dir = dir,
		project = project,
		generation = state.generation,
		descriptors = owner.descriptors,
	}
	return batch, true, {}
}

/* file_candidate_batch_close releases one copied complete candidate generation. */
file_candidate_batch_close :: proc(batch: ^File_Candidate_Batch) -> bool {
	if batch == nil || batch.state == nil {
		return false
	}
	file_candidate_batch_state_destroy((^File_Candidate_Batch_State)(batch.state))
	batch^ = {}
	return true
}

/* file_enumerator_close releases traversal, roots, and private candidates. */
file_enumerator_close :: proc(enumerator: ^File_Enumerator) -> bool {
	if enumerator == nil || enumerator.state == nil {
		return false
	}
	file_enumerator_state_destroy((^File_Enumerator_State)(enumerator.state))
	enumerator^ = File_Enumerator{closed = true}
	return true
}

@(private)
file_enumerator_resolve :: proc(
	enumerator: ^File_Enumerator,
	dir: Dir_Handle,
	project: Project_Handle,
	operation: Operation,
) -> (state: ^File_Enumerator_State, failure: Failure_Context) {
	if enumerator == nil || enumerator.state == nil {
		return nil, file_scope_failure(dir, project, operation, .Invalid_Registry)
	}
	state = (^File_Enumerator_State)(enumerator.state)
	if enumerator.closed {
		return nil, file_scope_failure(dir, project, operation, .Closed_Registry)
	}
	if state.dir != dir {
		return nil, file_scope_failure(dir, project, operation, .Stale_Dir)
	}
	if state.project != project {
		return nil, Failure_Context{code = .Stale_Project, operation = operation, project = project}
	}
	return state, {}
}

@(private)
file_enumerator_candidates_clear :: proc(state: ^File_Enumerator_State) {
	for candidate in state.candidates {
		delete(candidate.path, state.allocators.persistent)
	}
	clear(&state.candidates)
	state.retained_path_bytes = 0
}

@(private)
file_enumerator_state_destroy :: proc(state: ^File_Enumerator_State) {
	if state == nil {
		return
	}
	if state.walker_active {
		os.walker_destroy(&state.walker)
	}
	file_enumerator_candidates_clear(state)
	if state.candidates != nil {
		delete(state.candidates)
	}
	for path in state.root_paths {
		if len(path) > 0 {
			delete(path, state.allocators.persistent)
		}
	}
	if state.root_paths != nil {
		delete(state.root_paths, state.allocators.persistent)
	}
	allocator := state.allocators.persistent
	free(state, allocator)
}

@(private)
file_candidate_batch_state_destroy :: proc(state: ^File_Candidate_Batch_State) {
	if state == nil {
		return
	}
	allocator := state.allocator
	if state.paths != nil {
		delete(state.paths, allocator)
	}
	if state.descriptors != nil {
		delete(state.descriptors, allocator)
	}
	free(state, allocator)
}

@(private)
file_candidate_find :: proc(candidates: []File_Candidate_Owner, path: string) -> int {
	for candidate, index in candidates {
		if candidate.path == path {
			return index
		}
	}
	return -1
}

@(private)
file_candidate_membership_count :: proc(roots: []string, path: string) -> u32 {
	count: u32
	for root in roots {
		if file_candidate_path_contains(root, path) {
			count += 1
		}
	}
	return count
}

@(private)
file_candidate_path_contains :: proc(root, path: string) -> bool {
	if root == "/" {
		return strings.has_prefix(path, "/")
	}
	return len(path) > len(root) && strings.has_prefix(path, root) && path[len(root)] == '/'
}

@(private)
file_candidate_less :: proc(left, right: File_Candidate_Owner) -> bool {
	return strings.compare(left.path, right.path) < 0
}

@(private)
enumeration_failure :: proc(
	project: Project_Handle,
	operation: Operation,
	code: Failure_Code,
) -> Failure_Context {
	return file_scope_failure({}, project, operation, code)
}

@(private)
file_scope_failure :: proc(
	dir: Dir_Handle,
	project: Project_Handle,
	operation: Operation,
	code: Failure_Code,
) -> Failure_Context {
	_ = dir
	return Failure_Context{code = code, operation = operation, project = project}
}
