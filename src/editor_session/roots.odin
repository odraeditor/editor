// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package editor_session

import "../document"
import "../project"
import "base:runtime"
import "core:strings"

/* session_roots_replace atomically publishes one complete ordered Dir or Project root set. */
session_roots_replace :: proc(
	session: ^Session,
	request: Root_Replace_Request,
) -> (result: Root_Replace_Result, ok: bool, failure: Failure_Context) {
	data, resolved_failure := resolve_session(session, request.session, .Replace_Roots)
	if resolved_failure.code != .None {
		return {}, false, resolved_failure
	}
	path_bytes, valid, validation_failure := session_roots_request_validate(data, request.roots, .Replace_Roots)
	if !valid {
		return {}, false, validation_failure
	}

	next_generation := data.root_generation + Root_Set_Generation(1)
	if next_generation == Root_Set_Generation(0) ||
	   (len(request.roots) > 0 && u64(data.next_root_id) + u64(len(request.roots)) < u64(data.next_root_id)) {
		return {}, false, session_failure(data, .Replace_Roots, .Identity_Limit)
	}
	prepared, prepare_error := make([]Root_Owner, len(request.roots), data.allocator)
	if prepare_error != nil {
		return {}, false, session_failure(data, .Replace_Roots, .Persistent_Memory_Limit)
	}
	prepared_count := 0
	defer if prepared != nil {
		root_owner_slice_clear(prepared[:prepared_count], data.allocator)
		delete(prepared, data.allocator)
	}

	for root, index in request.roots {
		owned_path, path_error := strings.clone(root.path, data.allocator)
		if path_error != nil {
			return {}, false, session_failure(data, .Replace_Roots, .Persistent_Memory_Limit)
		}
		handle := Root_Handle {
			session = data.handle,
			id = data.next_root_id + Root_ID(index),
			generation = Root_Generation(next_generation),
		}
		prepared[index] = Root_Owner {
			handle = handle,
			kind = root.kind,
			path = owned_path,
			project = root.project,
		}
		if root.kind == .Dir {
			prepared[index].dir = project.Dir_Handle {
				owner = data.project_owner,
				id = project.Dir_ID(u64(handle.id)),
				generation = project.Dir_Generation(u64(handle.generation)),
			}
		}
		prepared_count += 1
	}

	old_roots := data.roots
	old_registry_bytes := data.root_registry_bytes
	data.roots = prepared
	prepared = nil
	data.root_generation = next_generation
	data.next_root_id += Root_ID(len(request.roots))
	data.root_path_bytes = path_bytes
	data.root_registry_bytes = u64(len(data.roots)) * u64(size_of(Root_Owner)) + path_bytes
	assert(data.usage.registry_bytes >= old_registry_bytes)
	data.usage.registry_bytes = data.usage.registry_bytes - old_registry_bytes + data.root_registry_bytes
	data.usage.session_roots = u32(len(data.roots))
	data.usage.root_path_bytes = path_bytes
	session_active_workspace_clear(data)
	root_owner_slice_clear(old_roots, data.allocator)
	if old_roots != nil {
		delete(old_roots, data.allocator)
	}
	result = Root_Replace_Result {
		generation = data.root_generation,
		root_count = u32(len(data.roots)),
		path_bytes = path_bytes,
	}
	assert(session_validate(data))
	return result, true, {}
}

/* session_roots copies the complete ordered active root projection. */
session_roots :: proc(
	session: ^Session,
	handle: Session_Handle,
) -> (batch: Root_Batch, ok: bool, failure: Failure_Context) {
	data, resolved_failure := resolve_session(session, handle, .Inspect_Roots)
	if resolved_failure.code != .None {
		return {}, false, resolved_failure
	}
	state, state_error := new(Root_Batch_State, data.allocator)
	if state_error != nil {
		return {}, false, session_failure(data, .Inspect_Roots, .Persistent_Memory_Limit)
	}
	state.allocator = data.allocator
	state.descriptors, state_error = make([]Root_Descriptor, len(data.roots), data.allocator)
	if state_error != nil {
		root_batch_state_destroy(state)
		return {}, false, session_failure(data, .Inspect_Roots, .Persistent_Memory_Limit)
	}
	state.paths, state_error = make([]u8, int(data.root_path_bytes), data.allocator)
	if state_error != nil {
		root_batch_state_destroy(state)
		return {}, false, session_failure(data, .Inspect_Roots, .Persistent_Memory_Limit)
	}
	offset := 0
	for root, index in data.roots {
		copy(state.paths[offset:], transmute([]u8)root.path)
		state.descriptors[index] = Root_Descriptor {
			handle = root.handle,
			kind = root.kind,
			path = string(state.paths[offset:offset + len(root.path)]),
			dir = root.dir,
			project = root.project,
		}
		offset += len(root.path)
	}
	batch = Root_Batch {
		state = state,
		generation = data.root_generation,
		descriptors = state.descriptors,
	}
	return batch, true, {}
}

/* root_batch_close releases one copied root projection. */
root_batch_close :: proc(batch: ^Root_Batch) -> bool {
	if batch == nil || batch.state == nil {
		return false
	}
	root_batch_state_destroy((^Root_Batch_State)(batch.state))
	batch^ = {}
	return true
}

@(private)
session_project_root_is_valid :: proc(
	data: ^Session_Data,
	handle: project.Project_Handle,
	path: string,
) -> bool {
	if !project.project_handle_is_valid(handle) || handle.owner != data.project_owner ||
	   handle == (project.Project_Handle{}) {
		return false
	}
	registry := session_project_registry(data, handle)
	if registry == nil {
		return false
	}
	descriptor, described, _ := project.registry_project_descriptor(registry, handle)
	if !described || descriptor.temporary || descriptor.directory_count != 1 {
		return false
	}
	memberships, listed, _ := project.registry_membership_descriptors(registry, handle)
	if !listed {
		return false
	}
	defer project.descriptor_batch_close(&memberships)
	return len(memberships.descriptors) == 1 &&
	       project.directory_path_text(&memberships.descriptors[0].path) == path
}

@(private)
session_roots_request_validate :: proc(
	data: ^Session_Data,
	roots: []Root_Proposal,
	operation: Operation,
) -> (path_bytes: u64, ok: bool, failure: Failure_Context) {
	if len(roots) > int(data.policy.session_roots) {
		failure = session_failure(data, operation, .Root_Limit)
		failure.maximum = u64(data.policy.session_roots)
		failure.actual = u64(len(roots))
		return 0, false, failure
	}
	for root, index in roots {
		if root.kind != .Dir && root.kind != .Project {
			return 0, false, session_failure(data, operation, .Invalid_Root)
		}
		normalized: document.Normalized_Path
		normalized_ok, _ := document.path_normalize(root.path, &normalized, data.temporary_allocator)
		if !normalized_ok || document.normalized_path_text(&normalized) != root.path {
			return 0, false, session_failure(data, operation, .Invalid_Path)
		}
		path_bytes += u64(len(root.path))
		if path_bytes > data.policy.root_path_bytes {
			failure = session_failure(data, operation, .Root_Path_Limit)
			failure.maximum = data.policy.root_path_bytes
			failure.actual = path_bytes
			return 0, false, failure
		}
		for previous in roots[:index] {
			if previous.path == root.path {
				return 0, false, session_failure(data, operation, .Duplicate_Root)
			}
		}
		if root.kind == .Dir {
			if root.project != (project.Project_Handle{}) {
				return 0, false, session_failure(data, operation, .Invalid_Root)
			}
		} else if !session_project_root_is_valid(data, root.project, root.path) {
			failure = session_failure(data, operation, .Project_Failure)
			failure.project_failure = project.Failure_Context {
				code = .Invalid_Project,
				operation = .Inspect,
				owner = data.project_owner,
				project = root.project,
			}
			return 0, false, failure
		}
	}
	return path_bytes, true, {}
}

@(private)
session_root_storage_clear :: proc(data: ^Session_Data) {
	if data == nil {
		return
	}
	root_owner_slice_clear(data.roots, data.allocator)
	if data.roots != nil {
		delete(data.roots, data.allocator)
	}
	data.roots = nil
	data.root_path_bytes = 0
	data.root_registry_bytes = 0
	data.usage.session_roots = 0
	data.usage.root_path_bytes = 0
}

@(private)
root_owner_slice_clear :: proc(roots: []Root_Owner, allocator: runtime.Allocator) {
	for &root in roots {
		if len(root.path) > 0 {
			delete(root.path, allocator)
		}
		root = {}
	}
}

@(private)
root_batch_state_destroy :: proc(state: ^Root_Batch_State) {
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
session_roots_validate :: proc(data: ^Session_Data) -> bool {
	if data == nil || data.root_generation == Root_Set_Generation(0) ||
	   data.next_root_id == Root_ID(0) || len(data.roots) > int(data.policy.session_roots) ||
	   data.usage.session_roots != u32(len(data.roots)) ||
	   data.usage.root_path_bytes != data.root_path_bytes ||
	   data.root_path_bytes > data.policy.root_path_bytes ||
	   data.root_registry_bytes != u64(len(data.roots)) * u64(size_of(Root_Owner)) + data.root_path_bytes ||
	   data.usage.registry_bytes < data.root_registry_bytes {
		return false
	}
	path_bytes: u64
	for root, index in data.roots {
		if !root_handle_is_valid(root.handle) || root.handle.session != data.handle ||
		   root.handle.generation != Root_Generation(data.root_generation) || len(root.path) == 0 {
			return false
		}
		path_bytes += u64(len(root.path))
		for previous in data.roots[:index] {
			if previous.path == root.path || previous.handle.id == root.handle.id {
				return false
			}
		}
		switch root.kind {
		case .Dir:
			if !project.dir_handle_is_valid(root.dir) || root.dir.owner != data.project_owner ||
			   u64(root.dir.id) != u64(root.handle.id) ||
			   u64(root.dir.generation) != u64(root.handle.generation) ||
			   root.project != (project.Project_Handle{}) {
				return false
			}
		case .Project:
			if root.dir != (project.Dir_Handle{}) || !project.project_handle_is_valid(root.project) ||
			   root.project.owner != data.project_owner ||
			   !session_project_root_is_valid(data, root.project, root.path) {
				return false
			}
		case .Invalid:
			return false
		}
	}
	return path_bytes == data.root_path_bytes
}

@(private)
session_project_is_projected :: proc(data: ^Session_Data, handle: project.Project_Handle) -> bool {
	if data == nil || !project.project_handle_is_valid(handle) {
		return false
	}
	for root in data.roots {
		if root.kind == .Project && root.project == handle {
			return true
		}
	}
	return false
}

@(private)
session_project_is_in_scope :: proc(data: ^Session_Data, handle: project.Project_Handle) -> bool {
	if data == nil || !project.project_handle_is_valid(handle) {
		return false
	}
	if len(data.roots) == 0 {
		return handle == data.active_project
	}
	return session_project_is_projected(data, handle)
}

@(private)
session_project_registry :: proc(data: ^Session_Data, handle: project.Project_Handle) -> ^project.Registry {
	if data == nil || !project.project_handle_is_valid(handle) || handle.owner != data.project_owner {
		return nil
	}
	if handle == data.primary_project {
		return &data.project_registry
	}
	for &owner in data.workspace_projects {
		if owner.handle == handle {
			return &owner.registry
		}
	}
	return nil
}
