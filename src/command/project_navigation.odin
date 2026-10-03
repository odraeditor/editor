// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../editor_session"
import "../interaction"
import "../project"
import "../document"
import "base:runtime"

/* Project_File_Search owns one active-Project file traversal until explicit close. */
Project_File_Search :: struct {
	enumerator: project.File_Enumerator,
	dir:        project.Dir_Handle,
	project:    project.Project_Handle,
	root_path:  [document.MAX_PATH_BYTES]u8,
	root_path_length: u32,
}

/* Project_Buffer_Candidate is one copied Project-owned live-buffer selection. */
Project_Buffer_Candidate :: struct {
	entry:  editor_session.Entry_Handle,
	path:   string,
	active: bool,
}

/* Project_Buffer_Candidate_Batch owns copied Project-buffer candidates and paths. */
Project_Buffer_Candidate_Batch :: struct {
	state:      rawptr,
	project:    project.Project_Handle,
	candidates: []Project_Buffer_Candidate,
}

@(private)
Project_Buffer_Candidate_State :: struct {
	candidates: []Project_Buffer_Candidate,
	paths:      []u8,
	allocator:  runtime.Allocator,
}

/* project_find_file_begin captures the exact active Project and begins bounded enumeration. */
project_find_file_begin :: proc(
	ctx: Project_Command_Context,
	search: ^Project_File_Search,
	policy := project.DEFAULT_POLICY,
) -> (ok: bool, failure: Failure_Context) {
	started, start_failure := root_find_file_begin(ctx, search, policy)
	if !started {
		return false, start_failure
	}
	if !project.project_handle_is_valid(search.project) {
		project_find_file_close(search)
		return false, Failure_Context{code = .Invalid_Request, command = ctx.command}
	}
	return true, {}
}

/* root_find_file_begin captures one exact active Dir or Project root. */
root_find_file_begin :: proc(
	ctx: Project_Command_Context,
	search: ^Project_File_Search,
	policy := project.DEFAULT_POLICY,
) -> (ok: bool, failure: Failure_Context) {
	assert(search != nil)
	search^ = {}
	if ctx.persistent_allocator.procedure == nil {
		return false, Failure_Context{code = .Invalid_Request, command = ctx.command}
	}
	roots, roots_ok, roots_failure := editor_session.session_roots(ctx.session, ctx.handle)
	if !roots_ok {
		return false, buffer_session_failure(ctx.command, roots_failure)
	}
	defer editor_session.root_batch_close(&roots)
	if len(roots.descriptors) == 0 {
		active, memberships, ready, ready_failure := project_command_membership(ctx)
		if !ready {
			return false, ready_failure
		}
		defer project.descriptor_batch_close(&memberships)
		initialized, initialize_failure := project.file_enumerator_init(
			&search.enumerator,
			active.descriptor.handle,
			memberships.descriptors,
			policy,
			project.Allocator_Set {
				persistent = ctx.persistent_allocator,
				temporary = ctx.temporary_allocator,
			},
		)
		if !initialized {
			return false, project_command_failure(ctx.command, initialize_failure)
		}
		search.project = active.descriptor.handle
		if len(memberships.descriptors) > 0 {
			path := project.directory_path_text(&memberships.descriptors[0].path)
			copy(search.root_path[:], transmute([]u8)path)
			search.root_path_length = u32(len(path))
		}
		return true, {}
	}
	if len(roots.descriptors) != 1 {
		return false, Failure_Context{code = .Invalid_Request, command = ctx.command}
	}
	root := roots.descriptors[0]
	if len(root.path) > len(search.root_path) {
		return false, Failure_Context{code = .Invalid_Request, command = ctx.command}
	}
	allocators := project.Allocator_Set {
		persistent = ctx.persistent_allocator,
		temporary = ctx.temporary_allocator,
	}
	initialized := false
	initialize_failure: project.Failure_Context
	if root.kind == .Dir {
		initialized, initialize_failure = project.dir_file_enumerator_init(
			&search.enumerator,
			root.dir,
			root.path,
			policy,
			allocators,
		)
		search.dir = root.dir
	} else if root.kind == .Project {
		memberships, memberships_ok, memberships_failure := editor_session.session_project_memberships(
			ctx.session,
			ctx.handle,
			root.project,
		)
		if !memberships_ok {
			return false, buffer_session_failure(ctx.command, memberships_failure)
		}
		defer project.descriptor_batch_close(&memberships)
		initialized, initialize_failure = project.file_enumerator_init(
			&search.enumerator,
			root.project,
			memberships.descriptors,
			policy,
			allocators,
		)
		search.project = root.project
	} else {
		return false, Failure_Context{code = .Invalid_Request, command = ctx.command}
	}
	if !initialized {
		return false, project_command_failure(ctx.command, initialize_failure)
	}
	copy(search.root_path[:], transmute([]u8)root.path)
	search.root_path_length = u32(len(root.path))
	return true, {}
}

/* project_find_file_advance performs one bounded traversal turn against the captured Project. */
project_find_file_advance :: proc(
	ctx: Project_Command_Context,
	search: ^Project_File_Search,
	cancelled := false,
) -> (result: project.File_Enumeration_Result, ok: bool, failure: Failure_Context) {
	if search == nil || !project.project_handle_is_valid(search.project) {
		return {}, false, Failure_Context{code = .Invalid_Request, command = ctx.command}
	}
	return root_find_file_advance(ctx, search, cancelled)
}

/* root_find_file_advance performs one bounded turn for the captured root. */
root_find_file_advance :: proc(
	ctx: Project_Command_Context,
	search: ^Project_File_Search,
	cancelled := false,
) -> (result: project.File_Enumeration_Result, ok: bool, failure: Failure_Context) {
	if !root_file_search_is_current(ctx, search) {
		return {}, false, Failure_Context{code = .Invalid_Request, command = ctx.command}
	}
	advanced: bool
	enumeration_failure: project.Failure_Context
	if project.dir_handle_is_valid(search.dir) {
		result, advanced, enumeration_failure = project.dir_file_enumerator_advance(
			&search.enumerator,
			search.dir,
			cancelled,
		)
	} else {
		result, advanced, enumeration_failure = project.file_enumerator_advance(
			&search.enumerator,
			search.project,
			cancelled,
		)
	}
	if !advanced {
		return {}, false, project_command_failure(ctx.command, enumeration_failure)
	}
	return result, true, {}
}

/* project_find_file_candidates copies only one completed active-Project generation. */
project_find_file_candidates :: proc(
	ctx: Project_Command_Context,
	search: ^Project_File_Search,
) -> (batch: project.File_Candidate_Batch, ok: bool, failure: Failure_Context) {
	if search == nil || !project.project_handle_is_valid(search.project) {
		return {}, false, Failure_Context{code = .Invalid_Request, command = ctx.command}
	}
	return root_find_file_candidates(ctx, search)
}

/* root_find_file_candidates copies one completed current root generation. */
root_find_file_candidates :: proc(
	ctx: Project_Command_Context,
	search: ^Project_File_Search,
) -> (batch: project.File_Candidate_Batch, ok: bool, failure: Failure_Context) {
	if !root_file_search_is_current(ctx, search) {
		return {}, false, Failure_Context{code = .Invalid_Request, command = ctx.command}
	}
	copied: bool
	copy_failure: project.Failure_Context
	if project.dir_handle_is_valid(search.dir) {
		batch, copied, copy_failure = project.dir_file_enumerator_candidates(&search.enumerator, search.dir)
	} else {
		batch, copied, copy_failure = project.file_enumerator_candidates(&search.enumerator, search.project)
	}
	if !copied {
		return {}, false, project_command_failure(ctx.command, copy_failure)
	}
	return batch, true, {}
}

/* root_find_file_path borrows the captured normalized root path while the search is live. */
root_find_file_path :: proc(search: ^Project_File_Search) -> string {
	if search == nil || search.enumerator.state == nil || search.root_path_length > u32(len(search.root_path)) {
		return ""
	}
	return string(search.root_path[:search.root_path_length])
}

@(private)
root_file_search_is_current :: proc(ctx: Project_Command_Context, search: ^Project_File_Search) -> bool {
	if search == nil || search.enumerator.state == nil ||
	   (project.dir_handle_is_valid(search.dir) == project.project_handle_is_valid(search.project)) {
		return false
	}
	roots, listed, _ := editor_session.session_roots(ctx.session, ctx.handle)
	if !listed {
		return false
	}
	defer editor_session.root_batch_close(&roots)
	if len(roots.descriptors) == 0 && project.project_handle_is_valid(search.project) {
		active, inspected, _ := project_inspect_active(ctx)
		return inspected && active.descriptor.handle == search.project
	}
	if len(roots.descriptors) != 1 || roots.descriptors[0].path != root_find_file_path(search) {
		return false
	}
	root := roots.descriptors[0]
	return (root.kind == .Dir && root.dir == search.dir) ||
	       (root.kind == .Project && root.project == search.project)
}

/* project_find_file_close releases one private traversal and invalidates its captured handle. */
project_find_file_close :: proc(search: ^Project_File_Search) -> bool {
	if search == nil || search.enumerator.state == nil {
		return false
	}
	closed := project.file_enumerator_close(&search.enumerator)
	search^ = {}
	return closed
}

/* project_find_directory_candidates returns exact active membership descriptors. */
project_find_directory_candidates :: proc(
	ctx: Project_Command_Context,
) -> (batch: project.Descriptor_Batch, ok: bool, failure: Failure_Context) {
	return project_list_directories(ctx)
}

/* project_switch_buffer_candidates copies only live buffers owned by the active Project. */
project_switch_buffer_candidates :: proc(
	ctx: Project_Command_Context,
) -> (batch: Project_Buffer_Candidate_Batch, ok: bool, failure: Failure_Context) {
	active, active_ok, active_failure := project_inspect_active(ctx)
	if !active_ok {
		return {}, false, active_failure
	}
	classified, classified_ok, classify_failure := editor_session.session_classify_project_buffers(
		ctx.session,
		ctx.handle,
		active.descriptor.handle,
		ctx.temporary_allocator,
	)
	if !classified_ok {
		return {}, false, buffer_session_failure(ctx.command, classify_failure)
	}
	defer editor_session.project_buffer_batch_close(&classified)
	candidate_count := 0
	path_bytes := 0
	for descriptor in classified.descriptors {
		if descriptor.scope == .Project_Owned {
			candidate_count += 1
			path_bytes += len(descriptor.normalized_path)
		}
	}
	if ctx.persistent_allocator.procedure == nil {
		return {}, false, Failure_Context{code = .Invalid_Request, command = ctx.command}
	}
	owner, owner_error := new(Project_Buffer_Candidate_State, ctx.persistent_allocator)
	if owner_error != nil {
		return {}, false, Failure_Context{code = .Temporary_Memory_Limit, command = ctx.command}
	}
	owner.allocator = ctx.persistent_allocator
	owner.candidates, owner_error = make([]Project_Buffer_Candidate, candidate_count, owner.allocator)
	if owner_error != nil {
		project_buffer_candidate_state_destroy(owner)
		return {}, false, Failure_Context{code = .Temporary_Memory_Limit, command = ctx.command}
	}
	owner.paths, owner_error = make([]u8, path_bytes, owner.allocator)
	if owner_error != nil {
		project_buffer_candidate_state_destroy(owner)
		return {}, false, Failure_Context{code = .Temporary_Memory_Limit, command = ctx.command}
	}
	index := 0
	offset := 0
	for descriptor in classified.descriptors {
		if descriptor.scope != .Project_Owned {
			continue
		}
		copy(owner.paths[offset:], transmute([]u8)descriptor.normalized_path)
		owner.candidates[index] = Project_Buffer_Candidate{
			entry = descriptor.graph.entry,
			path = string(owner.paths[offset:offset + len(descriptor.normalized_path)]),
			active = descriptor.active,
		}
		index += 1
		offset += len(descriptor.normalized_path)
	}
	assert(index == len(owner.candidates) && offset == len(owner.paths))
	return Project_Buffer_Candidate_Batch{
		state = owner,
		project = active.descriptor.handle,
		candidates = owner.candidates,
	}, true, {}
}

/* project_buffer_candidate_batch_close releases copied entries and paths. */
project_buffer_candidate_batch_close :: proc(batch: ^Project_Buffer_Candidate_Batch) -> bool {
	if batch == nil || batch.state == nil {
		return false
	}
	project_buffer_candidate_state_destroy((^Project_Buffer_Candidate_State)(batch.state))
	batch^ = {}
	return true
}

@(private)
project_buffer_candidate_state_destroy :: proc(state: ^Project_Buffer_Candidate_State) {
	if state == nil {
		return
	}
	allocator := state.allocator
	if state.paths != nil {
		delete(state.paths, allocator)
	}
	if state.candidates != nil {
		delete(state.candidates, allocator)
	}
	free(state, allocator)
}

@(private)
project_command_failure :: proc(
	command: interaction.Command_Handle,
	failure: project.Failure_Context,
) -> Failure_Context {
	return Failure_Context{
		code = .Editor_Session_Failure,
		command = command,
		project_code = failure.code,
		limit = failure.maximum,
		actual = failure.actual,
	}
}
