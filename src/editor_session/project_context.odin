// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package editor_session

import "../project"

/*
session_open_project_directory atomically publishes one resolved Project or
returns an ambiguity without changing the active Project registry.
*/
session_open_project_directory :: proc(
	session: ^Session,
	request: Project_Directory_Open_Request,
) -> (result: Project_Directory_Open_Result, ok: bool, failure: Failure_Context) {
	data, resolved_failure := resolve_session(session, request.session, .Replace_Project)
	if resolved_failure.code != .None {
		return {}, false, resolved_failure
	}
	registry_expected := request.expected
	if !project.project_handle_is_valid(registry_expected) && len(data.roots) > 0 &&
	   !session_project_is_projected(data, data.active_project) {
		registry_expected = data.active_project
	}
	directories: [1]project.Directory_Proposal
	snapshot: project.Snapshot_Request
	if request.matching_projects <= 1 {
		directories[0] = project.Directory_Proposal {
			path = request.normalized_path,
			trust = request.trust,
		}
			snapshot = project.Snapshot_Request {
				owner = data.project_owner,
				project_id = request.project_id,
				project_generation = request.project_generation,
				durable_id = request.durable_id,
				name = request.name,
			directories = directories[:],
			temporary = request.temporary,
		}
	}
	prepared: project.Directory_Open_Preparation
	prepared_ok, project_failure := project.directory_open_prepare(
		&data.project_registry,
		project.Directory_Open_Request {
			owner = data.project_owner,
			expected = registry_expected,
			expected_catalog_generation = request.expected_catalog_generation,
			normalized_path = request.normalized_path,
			matching_projects = request.matching_projects,
			snapshot = snapshot,
		},
		&prepared,
	)
	if !prepared_ok {
		return {}, false, session_project_failure(data, .Replace_Project, project_failure)
	}
	defer project.directory_open_abort(&prepared)
	if prepared.resolution == .Ambiguous {
		usage, usage_ok := project.registry_usage(&data.project_registry)
		assert(usage_ok)
		return Project_Directory_Open_Result{resolution = .Ambiguous, usage = usage}, true, {}
	}
	if project.project_handle_is_valid(request.expected) {
		if request.expected != data.active_project {
			return {}, false, session_project_failure(
				data,
				.Replace_Project,
				project.Failure_Context {
					code = .Stale_Project,
					operation = .Prepare_Directory_Open,
					owner = data.project_owner,
					project = request.expected,
				},
			)
		}
		matches: [int(project.MAX_DIRECTORIES)]project.Membership_Handle
		for slot_index := data.mru_head; slot_index != INVALID_SLOT; slot_index = data.slots[slot_index].next_mru {
			owner := data.slots[slot_index].owner
			if !owner.document_live {
				continue
			}
			count, classified, classify_failure := project.registry_classify_path(
				&data.project_registry,
				request.expected,
				owner.normalized_path,
				matches[:],
			)
			if !classified {
				return {}, false, session_project_failure(data, .Replace_Project, classify_failure)
			}
			if count > 0 {
				return {}, false, session_project_failure(
					data,
					.Replace_Project,
					project.Failure_Context {
						code = .Project_Switch_Unavailable,
						operation = .Prepare_Directory_Open,
						owner = data.project_owner,
						project = request.expected,
					},
				)
			}
		}
	}

	before_usage, before_ok := project.registry_usage(&data.project_registry)
	assert(before_ok && before_usage.registry_bytes == data.project_registry_bytes)
	descriptor, published, publish_failure := project.directory_open_publish(
		&data.project_registry,
		&prepared,
		request.actual_catalog_generation,
	)
	if !published {
		return {}, false, session_project_failure(data, .Replace_Project, publish_failure)
	}
	after_usage, after_ok := project.registry_usage(&data.project_registry)
	assert(after_ok && data.usage.registry_bytes >= data.project_registry_bytes)
	data.usage.registry_bytes = data.usage.registry_bytes - data.project_registry_bytes +
	                            after_usage.registry_bytes
	data.project_registry_bytes = after_usage.registry_bytes
	data.active_project = descriptor.handle
	data.primary_project = descriptor.handle
	result = Project_Directory_Open_Result {
		resolution = .Unregistered if descriptor.temporary else .Registered,
		active = descriptor,
		usage = after_usage,
	}
	assert(session_validate(data))
	return result, true, {}
}

/*
session_replace_project validates and atomically publishes one complete active-Project snapshot.
The directory proposal is borrowed for this call; buffers and documents retain their owners.
*/
session_replace_project :: proc(
	session: ^Session,
	request: Project_Update_Request,
) -> (result: Project_Update_Result, ok: bool, failure: Failure_Context) {
	data, resolved_failure := resolve_session(session, request.session, .Replace_Project)
	if resolved_failure.code != .None {
		return {}, false, resolved_failure
	}
	if len(data.roots) > 0 && !session_project_is_projected(data, data.active_project) {
		return {}, false, session_failure(data, .Replace_Project, .Project_Scope)
	}
	if request.expected != data.active_project {
		project_failure := project.Failure_Context {
			code = .Stale_Project,
			operation = .Replace_Membership,
			owner = data.project_owner,
			project = request.expected,
		}
		return {}, false, session_project_failure(data, .Replace_Project, project_failure)
	}

	previous := data.active_project
	before_usage, before_ok := project.registry_usage(&data.project_registry)
	assert(before_ok && before_usage.registry_bytes == data.project_registry_bytes)
	prepared: project.Prepared_Snapshot
	prepared_ok, prepare_failure := project.registry_prepare_snapshot(
		&data.project_registry,
		project.Snapshot_Request {
			owner = data.project_owner,
			project_id = request.project_id,
			name = request.name,
			directories = request.directories,
			temporary = request.temporary,
		},
		&prepared,
	)
	if !prepared_ok {
		return {}, false, session_project_failure(data, .Replace_Project, prepare_failure)
	}

	descriptor, published, publish_failure := project.prepared_snapshot_publish(
		&data.project_registry,
		&prepared,
	)
	if !published {
		project.prepared_snapshot_abort(&prepared)
		return {}, false, session_project_failure(data, .Replace_Project, publish_failure)
	}
	after_usage, after_ok := project.registry_usage(&data.project_registry)
	assert(after_ok && data.usage.registry_bytes >= data.project_registry_bytes)
	data.usage.registry_bytes = data.usage.registry_bytes - data.project_registry_bytes +
	                            after_usage.registry_bytes
	data.project_registry_bytes = after_usage.registry_bytes
	data.active_project = descriptor.handle
	data.primary_project = descriptor.handle
	result = Project_Update_Result {
		previous = previous,
		active = descriptor,
		usage = after_usage,
	}
	assert(session_validate(data))
	return result, true, {}
}

/* session_active_project returns one copied session-owned Project snapshot when active. */
session_active_project :: proc(
	session: ^Session,
	handle: Session_Handle,
) -> (snapshot: Active_Project_Snapshot, ok: bool, failure: Failure_Context) {
	data, resolved_failure := resolve_session(session, handle, .Inspect_Project)
	if resolved_failure.code != .None {
		return {}, false, resolved_failure
	}
	if !project.project_handle_is_valid(data.active_project) ||
	   (len(data.roots) > 0 && !session_project_is_projected(data, data.active_project)) {
		usage, usage_ok := project.registry_usage(&data.project_registry)
		assert(usage_ok)
		snapshot.usage = usage
		return snapshot, true, {}
	}
	registry := session_project_registry(data, data.active_project)
	if registry == nil {
		return {}, false, session_failure(data, .Inspect_Project, .Project_Scope)
	}
	usage, usage_ok := project.registry_usage(registry)
	assert(usage_ok)
	snapshot.usage = usage
	descriptor, described, project_failure := project.registry_project_descriptor(registry, data.active_project)
	if !described {
		return {}, false, session_project_failure(data, .Inspect_Project, project_failure)
	}
	snapshot.active = true
	snapshot.descriptor = descriptor
	return snapshot, true, {}
}

/* session_project_registry_access creates a checked capability for one active Project generation. */
session_project_registry_access :: proc(
	session: ^Session,
	session_handle: Session_Handle,
	project_handle: project.Project_Handle,
) -> (access: Project_Registry_Access, ok: bool, failure: Failure_Context) {
	data, resolved_failure := resolve_session(session, session_handle, .Inspect_Project)
	if resolved_failure.code != .None {
		return {}, false, resolved_failure
	}
	if len(data.roots) > 0 && !session_project_is_projected(data, project_handle) {
		return {}, false, session_failure(data, .Inspect_Project, .Project_Scope)
	}
	if !session_project_is_in_scope(data, project_handle) {
		project_failure := project.Failure_Context {
			code = .Stale_Project,
			operation = .Inspect,
			owner = data.project_owner,
			project = project_handle,
		}
		return {}, false, session_project_failure(data, .Inspect_Project, project_failure)
	}
	return Project_Registry_Access{state = data, project = project_handle}, true, {}
}

/* project_registry_access_borrow revalidates and borrows the stable session-owned registry. */
project_registry_access_borrow :: proc(
	access: Project_Registry_Access,
) -> (registry: ^project.Registry, ok: bool, failure: Failure_Context) {
	if access.state == nil {
		return nil, false, Failure_Context{code = .Invalid_Session, operation = .Inspect_Project}
	}
	data := (^Session_Data)(access.state)
	if len(data.roots) > 0 && !session_project_is_projected(data, access.project) {
		return nil, false, session_failure(data, .Inspect_Project, .Project_Scope)
	}
	if !project.project_handle_is_valid(access.project) ||
	   !session_project_is_in_scope(data, access.project) {
		project_failure := project.Failure_Context {
			code = .Stale_Project,
			operation = .Inspect,
			owner = data.project_owner,
			project = access.project,
		}
		return nil, false, session_project_failure(data, .Inspect_Project, project_failure)
	}
	registry = session_project_registry(data, access.project)
	if registry == nil {
		return nil, false, session_failure(data, .Inspect_Project, .Project_Scope)
	}
	return registry, true, {}
}

/* session_project_memberships copies the active Project membership in declared order. */
session_project_memberships :: proc(
	session: ^Session,
	session_handle: Session_Handle,
	project_handle: project.Project_Handle,
) -> (batch: project.Descriptor_Batch, ok: bool, failure: Failure_Context) {
	data, resolved_failure := resolve_session(session, session_handle, .Inspect_Project)
	if resolved_failure.code != .None {
		return {}, false, resolved_failure
	}
	if len(data.roots) > 0 && !session_project_is_projected(data, project_handle) {
		return {}, false, session_failure(data, .Inspect_Project, .Project_Scope)
	}
	if !session_project_is_in_scope(data, project_handle) {
		project_failure := project.Failure_Context {
			code = .Stale_Project,
			operation = .Membership_Descriptors,
			owner = data.project_owner,
			project = project_handle,
		}
		return {}, false, session_project_failure(data, .Inspect_Project, project_failure)
	}
	registry := session_project_registry(data, project_handle)
	if registry == nil {
		return {}, false, session_failure(data, .Inspect_Project, .Project_Scope)
	}
	copied_batch, listed, project_failure := project.registry_membership_descriptors(registry, project_handle)
	if !listed {
		return {}, false, session_project_failure(data, .Inspect_Project, project_failure)
	}
	return copied_batch, true, {}
}

/*
session_classify_project_buffers copies every live buffer against one immutable Project generation.
Overlapping memberships produce several handles in one descriptor, never duplicate buffer rows.
*/
session_classify_project_buffers :: proc(
	session: ^Session,
	session_handle: Session_Handle,
	project_handle: project.Project_Handle,
	allocator := context.allocator,
) -> (batch: Project_Buffer_Batch, ok: bool, failure: Failure_Context) {
	data, resolved_failure := resolve_session(session, session_handle, .Inspect_Project)
	if resolved_failure.code != .None {
		return {}, false, resolved_failure
	}
	if allocator.procedure == nil {
		return {}, false, session_failure(data, .Inspect_Project, .Persistent_Memory_Limit)
	}
	if len(data.roots) > 0 && !session_project_is_projected(data, project_handle) {
		return {}, false, session_failure(data, .Inspect_Project, .Project_Scope)
	}
	if !session_project_is_in_scope(data, project_handle) {
		project_failure := project.Failure_Context {
			code = .Stale_Project,
			operation = .Classify_Path,
			owner = data.project_owner,
			project = project_handle,
		}
		return {}, false, session_project_failure(data, .Inspect_Project, project_failure)
	}
	registry := session_project_registry(data, project_handle)
	if registry == nil {
		return {}, false, session_failure(data, .Inspect_Project, .Project_Scope)
	}
	if data.usage.live_buffers > data.policy.descriptor_batch {
		failure = session_failure(data, .Inspect_Project, .Descriptor_Limit)
		failure.maximum = u64(data.policy.descriptor_batch)
		failure.actual = u64(data.usage.live_buffers)
		return {}, false, failure
	}

	path_bytes: u64
	membership_count: u64
	matches: [int(project.MAX_DIRECTORIES)]project.Membership_Handle
	for slot_index := data.mru_head; slot_index != INVALID_SLOT; slot_index = data.slots[slot_index].next_mru {
		owner := data.slots[slot_index].owner
		if !owner.document_live {
			continue
		}
		path_bytes += u64(len(owner.normalized_path))
		count, classified, project_failure := project.registry_classify_path(
			registry,
			project_handle,
			owner.normalized_path,
			matches[:],
		)
		if !classified {
			return {}, false, session_project_failure(data, .Inspect_Project, project_failure)
		}
		membership_count += u64(count)
	}

	state, state_error := new(Project_Buffer_Batch_State, allocator)
	if state_error != nil {
		return {}, false, session_failure(data, .Inspect_Project, .Persistent_Memory_Limit)
	}
	state.allocator = allocator
	state.descriptors, state_error = make(
		[]Project_Buffer_Descriptor,
		int(data.usage.live_buffers),
		allocator,
	)
	if state_error != nil {
		free(state, allocator)
		return {}, false, session_failure(data, .Inspect_Project, .Persistent_Memory_Limit)
	}
	state.paths, state_error = make([]u8, int(path_bytes), allocator)
	if state_error != nil {
		project_buffer_batch_state_destroy(state)
		return {}, false, session_failure(data, .Inspect_Project, .Persistent_Memory_Limit)
	}
	state.memberships, state_error = make(
		[]project.Membership_Handle,
		int(membership_count),
		allocator,
	)
	if state_error != nil {
		project_buffer_batch_state_destroy(state)
		return {}, false, session_failure(data, .Inspect_Project, .Persistent_Memory_Limit)
	}

	descriptor_index := 0
	path_offset := 0
	membership_offset: u32
	for slot_index := data.mru_head; slot_index != INVALID_SLOT; slot_index = data.slots[slot_index].next_mru {
		slot := &data.slots[slot_index]
		owner := slot.owner
		descriptor := Project_Buffer_Descriptor {
			graph = owner_graph(owner, entry_handle(data, slot_index)),
			scope = .Unassociated,
			membership_offset = membership_offset,
			active = slot_index == data.mru_head,
		}
		if owner.document_live {
			path_length := len(owner.normalized_path)
			copy(state.paths[path_offset:], transmute([]u8)owner.normalized_path)
			descriptor.normalized_path = string(state.paths[path_offset:path_offset + path_length])
			path_offset += path_length
			count, classified, project_failure := project.registry_classify_path(
				registry,
				project_handle,
				owner.normalized_path,
				matches[:],
			)
			if !classified {
				project_buffer_batch_state_destroy(state)
				return {}, false, session_project_failure(data, .Inspect_Project, project_failure)
			}
			descriptor.membership_count = count
			descriptor.scope = .External
			if count > 0 {
				descriptor.scope = .Project_Owned
				copy(
					state.memberships[membership_offset:membership_offset + count],
					matches[:count],
				)
				membership_offset += count
			}
		}
		state.descriptors[descriptor_index] = descriptor
		descriptor_index += 1
	}
	assert(path_offset == len(state.paths) && membership_offset == u32(len(state.memberships)))
	batch = Project_Buffer_Batch {
		state = state,
		project_handle = project_handle,
		descriptors = state.descriptors,
		memberships = state.memberships,
	}
	return batch, true, {}
}

/* session_active_project_buffer_scope classifies the active buffer without allocating. */
session_active_project_buffer_scope :: proc(
	session: ^Session,
	session_handle: Session_Handle,
	project_handle: project.Project_Handle,
) -> (scope: Project_Buffer_Scope, membership_count: u32, ok: bool, failure: Failure_Context) {
	data, resolved_failure := resolve_session(session, session_handle, .Inspect_Project)
	if resolved_failure.code != .None {
		return .Invalid, 0, false, resolved_failure
	}
	if len(data.roots) > 0 && !session_project_is_projected(data, project_handle) {
		return .Invalid, 0, false, session_failure(data, .Inspect_Project, .Project_Scope)
	}
	if !session_project_is_in_scope(data, project_handle) {
		project_failure := project.Failure_Context {
			code = .Stale_Project,
			operation = .Classify_Path,
			owner = data.project_owner,
			project = project_handle,
		}
		return .Invalid, 0, false, session_project_failure(data, .Inspect_Project, project_failure)
	}
	registry := session_project_registry(data, project_handle)
	if registry == nil {
		return .Invalid, 0, false, session_failure(data, .Inspect_Project, .Project_Scope)
	}
	if data.mru_head == INVALID_SLOT {
		return .Unassociated, 0, true, {}
	}
	owner := data.slots[data.mru_head].owner
	if !owner.document_live {
		return .Unassociated, 0, true, {}
	}
	matches: [int(project.MAX_DIRECTORIES)]project.Membership_Handle
	count, classified, project_failure := project.registry_classify_path(
		registry,
		project_handle,
		owner.normalized_path,
		matches[:],
	)
	if !classified {
		return .Invalid, 0, false, session_project_failure(data, .Inspect_Project, project_failure)
	}
	if count == 0 {
		return .External, 0, true, {}
	}
	return .Project_Owned, count, true, {}
}

/* project_buffer_batch_close releases one copied Project buffer classification. */
project_buffer_batch_close :: proc(batch: ^Project_Buffer_Batch) -> bool {
	if batch == nil || batch.state == nil {
		return false
	}
	state := (^Project_Buffer_Batch_State)(batch.state)
	project_buffer_batch_state_destroy(state)
	batch^ = {}
	return true
}

@(private)
project_buffer_batch_state_destroy :: proc(state: ^Project_Buffer_Batch_State) {
	if state == nil {
		return
	}
	allocator := state.allocator
	if state.memberships != nil {
		delete(state.memberships, allocator)
	}
	if state.paths != nil {
		delete(state.paths, allocator)
	}
	if state.descriptors != nil {
		delete(state.descriptors, allocator)
	}
	free(state, allocator)
}

@(private)
session_project_failure :: proc(
	data: ^Session_Data,
	operation: Operation,
	project_failure: project.Failure_Context,
) -> Failure_Context {
	failure := session_failure(data, operation, .Project_Failure)
	failure.project_failure = project_failure
	return failure
}
