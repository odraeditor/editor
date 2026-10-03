// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package editor_session

import "../document"
import "../editor"
import "../project"
import "core:strings"
import "core:unicode/utf8"

/* session_prepare_workspace_activation copies one complete resolved Project composition. */
session_prepare_workspace_activation :: proc(
	session: ^Session,
	proposal: Workspace_Activation_Proposal,
	prepared: ^Workspace_Activation_Preparation,
) -> (ok: bool, failure: Failure_Context) {
	assert(prepared != nil)
	prepared^ = {}
	data, resolved_failure := resolve_session(session, proposal.session, .Prepare_Workspace)
	if resolved_failure.code != .None {
		return false, resolved_failure
	}
	if !workspace_identity_valid(proposal.id) || proposal.generation == 0 ||
	   !workspace_name_valid(proposal.name) {
		return false, session_failure(data, .Prepare_Workspace, .Invalid_Workspace)
	}
	member_count := u64(len(proposal.projects)) + u64(proposal.unavailable_members)
	if member_count < 1 || member_count > u64(data.policy.session_roots) {
		failure = session_failure(data, .Prepare_Workspace, .Root_Limit)
		failure.minimum = 1
		failure.maximum = u64(data.policy.session_roots)
		failure.actual = member_count
		return false, failure
	}
	prepared.session = data.handle
	prepared.expected_root_set = proposal.expected_root_set
	prepared.project_count = u32(member_count)
	prepared.unavailable_members = proposal.unavailable_members
	if proposal.unavailable_members > 0 {
		prepared.outcome = .Unavailable_Members
		return true, {}
	}
	if proposal.expected_root_set != Root_Set_Generation(0) &&
	   proposal.expected_root_set != data.root_generation {
		return false, session_failure(data, .Prepare_Workspace, .Stale_Workspace)
	}
	path_bytes := 0
	for member, index in proposal.projects {
		normalized: document.Normalized_Path
		normalized_ok, _ := document.path_normalize(member.root, &normalized, data.temporary_allocator)
		if !normalized_ok || document.normalized_path_text(&normalized) != member.root {
			return false, session_failure(data, .Prepare_Workspace, .Invalid_Path)
		}
		path_bytes += len(member.root)
		if u64(path_bytes) > data.policy.root_path_bytes {
			failure = session_failure(data, .Prepare_Workspace, .Root_Path_Limit)
			failure.maximum = data.policy.root_path_bytes
			failure.actual = u64(path_bytes)
			return false, failure
		}
		for previous in proposal.projects[:index] {
			if previous.root == member.root || previous.project_id == member.project_id ||
			   previous.durable_id == member.durable_id {
				return false, session_failure(data, .Prepare_Workspace, .Duplicate_Root)
			}
		}
	}

	state, state_error := new(Workspace_Activation_State, data.allocator)
	if state_error != nil {
		return false, session_failure(data, .Prepare_Workspace, .Persistent_Memory_Limit)
	}
	state.allocator = data.allocator
	state.owner = Workspace_Owner {
		generation = proposal.generation,
		project_count = u32(len(proposal.projects)),
	}
	workspace_identity_copy(&state.owner.id, proposal.id)
	workspace_name_copy(&state.owner.name, proposal.name)
	state.projects, state_error = make([]Workspace_Project_Owner, len(proposal.projects), data.allocator)
	if state_error != nil {
		workspace_activation_state_destroy(state)
		return false, session_failure(data, .Prepare_Workspace, .Persistent_Memory_Limit)
	}
	state.roots, state_error = make([]Root_Proposal, len(proposal.projects), data.allocator)
	if state_error != nil {
		workspace_activation_state_destroy(state)
		return false, session_failure(data, .Prepare_Workspace, .Persistent_Memory_Limit)
	}
	state.paths, state_error = make([]u8, path_bytes, data.allocator)
	if state_error != nil {
		workspace_activation_state_destroy(state)
		return false, session_failure(data, .Prepare_Workspace, .Persistent_Memory_Limit)
	}
	offset := 0
	for member, index in proposal.projects {
		initialized, project_failure := project.registry_init(
			&state.projects[index].registry,
			data.project_owner,
			data.project_policy,
			project.Allocator_Set {
				persistent = data.allocator,
				temporary = data.temporary_allocator,
			},
		)
		if !initialized {
			workspace_activation_state_destroy(state)
			return false, session_project_failure(data, .Prepare_Workspace, project_failure)
		}
		prepared_snapshot: project.Prepared_Snapshot
		project_prepared, project_prepare_failure := project.registry_prepare_snapshot(
			&state.projects[index].registry,
			project.Snapshot_Request {
				owner = data.project_owner,
				project_id = member.project_id,
				project_generation = member.project_generation,
				durable_id = member.durable_id,
				name = member.name,
				directories = []project.Directory_Proposal{{path = member.root, trust = member.trust}},
				temporary = false,
			},
			&prepared_snapshot,
		)
		if !project_prepared {
			workspace_activation_state_destroy(state)
			return false, session_project_failure(data, .Prepare_Workspace, project_prepare_failure)
		}
		descriptor, published, publish_failure := project.prepared_snapshot_publish(
			&state.projects[index].registry,
			&prepared_snapshot,
		)
		if !published {
			project.prepared_snapshot_abort(&prepared_snapshot)
			workspace_activation_state_destroy(state)
			return false, session_project_failure(data, .Prepare_Workspace, publish_failure)
		}
		usage, usage_ok := project.registry_usage(&state.projects[index].registry)
		assert(usage_ok)
		state.projects[index].handle = descriptor.handle
		state.projects[index].registry_bytes = usage.registry_bytes
		copy(state.paths[offset:], transmute([]u8)member.root)
		state.roots[index] = Root_Proposal {
			kind = .Project,
			path = string(state.paths[offset:offset + len(member.root)]),
			project = descriptor.handle,
		}
		offset += len(member.root)
	}
	prepared.state = state
	dirty_entries: u32
	if !session_roots_equal(data, state.roots) {
		dirty_entries, failure = session_modified_entry_count(data, .Prepare_Workspace)
		if failure.code != .None {
			workspace_activation_state_destroy(state)
			prepared^ = {}
			return false, failure
		}
	}
	prepared.dirty_entries = dirty_entries
	prepared.outcome = .Dirty_Protection_Required if dirty_entries > 0 else .Ready
	return true, {}
}

/* session_admit_workspace_activation revalidates and atomically publishes roots and identity. */
session_admit_workspace_activation :: proc(
	session: ^Session,
	prepared: ^Workspace_Activation_Preparation,
) -> (result: Workspace_Activation_Result, ok: bool, failure: Failure_Context) {
	if prepared != nil && prepared.outcome == .Unavailable_Members {
		failure = Failure_Context {
			code = .Unavailable_Workspace_Members,
			operation = .Activate_Workspace,
			actual = u64(prepared.unavailable_members),
		}
		return {}, false, failure
	}
	if prepared == nil || prepared.state == nil ||
	   (prepared.outcome != .Ready && prepared.outcome != .Dirty_Protection_Required) {
		return {}, false, Failure_Context{code = .Invalid_Workspace, operation = .Activate_Workspace}
	}
	data, resolved_failure := resolve_session(session, prepared.session, .Activate_Workspace)
	if resolved_failure.code != .None {
		return {}, false, resolved_failure
	}
	state := (^Workspace_Activation_State)(prepared.state)
	if prepared.expected_root_set != Root_Set_Generation(0) &&
	   prepared.expected_root_set != data.root_generation {
		return {}, false, session_failure(data, .Activate_Workspace, .Stale_Workspace)
	}
	if prepared.outcome == .Dirty_Protection_Required {
		dirty_entries, dirty_failure := session_modified_entry_count(data, .Activate_Workspace)
		if dirty_failure.code != .None {
			return {}, false, dirty_failure
		}
		if dirty_entries > 0 {
			failure = session_failure(data, .Activate_Workspace, .Dirty_Protection_Required)
			failure.actual = u64(dirty_entries)
			return {}, false, failure
		}
	}
	old_projects := data.workspace_projects
	old_project_bytes := data.workspace_project_registry_bytes
	old_active_project := data.active_project
	new_project_bytes: u64
	for owner in state.projects {
		new_project_bytes += owner.registry_bytes
	}
	assert(data.usage.registry_bytes >= old_project_bytes)
	data.workspace_projects = state.projects
	state.projects = nil
	data.workspace_project_registry_bytes = new_project_bytes
	data.usage.registry_bytes = data.usage.registry_bytes - old_project_bytes + new_project_bytes
	data.active_project = state.roots[0].project
	root_result, roots_published, root_failure := session_roots_replace(
		session,
		Root_Replace_Request{session = data.handle, roots = state.roots},
	)
	if !roots_published {
		state.projects = data.workspace_projects
		data.workspace_projects = old_projects
		data.workspace_project_registry_bytes = old_project_bytes
		data.usage.registry_bytes = data.usage.registry_bytes - new_project_bytes + old_project_bytes
		data.active_project = old_active_project
		root_failure.operation = .Activate_Workspace
		return {}, false, root_failure
	}
	workspace_project_slice_destroy(old_projects)
	if old_projects != nil {
		delete(old_projects, data.allocator)
	}
	state.owner.root_set = root_result.generation
	data.active_workspace = state.owner
	data.active_project = state.roots[0].project
	result = Workspace_Activation_Result {
		workspace = workspace_owner_descriptor(&data.active_workspace),
		roots = root_result,
	}
	workspace_activation_state_destroy(state)
	prepared^ = {}
	assert(session_validate(data))
	return result, true, {}
}

/* session_abort_workspace_activation releases one unconsumed copied proposal. */
session_abort_workspace_activation :: proc(prepared: ^Workspace_Activation_Preparation) {
	if prepared == nil {
		return
	}
	if prepared.state != nil {
		workspace_activation_state_destroy((^Workspace_Activation_State)(prepared.state))
	}
	prepared^ = {}
}

/* session_active_workspace returns one copied active Workspace snapshot. */
session_active_workspace :: proc(
	session: ^Session,
	handle: Session_Handle,
) -> (snapshot: Active_Workspace_Snapshot, ok: bool, failure: Failure_Context) {
	data, resolved_failure := resolve_session(session, handle, .Inspect_Workspace)
	if resolved_failure.code != .None {
		return {}, false, resolved_failure
	}
	if data.active_workspace.generation == 0 {
		return {}, true, {}
	}
	return Active_Workspace_Snapshot {
		active = true,
		descriptor = workspace_owner_descriptor(&data.active_workspace),
	}, true, {}
}

/*
session_workspace_recent_entry selects the newest live document owned by any
Project in one exact admitted Workspace generation without allocating.
*/
session_workspace_recent_entry :: proc(
	session: ^Session,
	handle: Session_Handle,
	expected_root_set: Root_Set_Generation,
) -> (entry: Entry_Handle, found: bool, failure: Failure_Context) {
	data, resolved_failure := resolve_session(session, handle, .Inspect_Workspace)
	if resolved_failure.code != .None {
		return {}, false, resolved_failure
	}
	if data.active_workspace.generation == 0 {
		return {}, false, session_failure(data, .Inspect_Workspace, .Invalid_Workspace)
	}
	if expected_root_set == Root_Set_Generation(0) ||
	   expected_root_set != data.root_generation ||
	   expected_root_set != data.active_workspace.root_set {
		return {}, false, session_failure(data, .Inspect_Workspace, .Stale_Workspace)
	}
	if len(data.roots) == 0 || u32(len(data.roots)) != data.active_workspace.project_count {
		return {}, false, session_failure(data, .Inspect_Workspace, .Invalid_Workspace)
	}

	matches: [int(project.MAX_DIRECTORIES)]project.Membership_Handle
	for slot_index := data.mru_head; slot_index != INVALID_SLOT; slot_index = data.slots[slot_index].next_mru {
		owner := data.slots[slot_index].owner
		if !owner.document_live {
			continue
		}
		for root in data.roots {
			if root.kind != .Project {
				return {}, false, session_failure(data, .Inspect_Workspace, .Invalid_Workspace)
			}
			registry := session_project_registry(data, root.project)
			if registry == nil {
				return {}, false, session_failure(data, .Inspect_Workspace, .Project_Scope)
			}
			count, classified, classify_failure := project.registry_classify_path(
				registry,
				root.project,
				owner.normalized_path,
				matches[:],
			)
			if !classified {
				return {}, false, session_project_failure(
					data,
					.Inspect_Workspace,
					classify_failure,
				)
			}
			if count > 0 {
				return entry_handle(data, slot_index), true, {}
			}
		}
	}
	return {}, false, {}
}

/* workspace_id_text returns the copied durable identity text. */
workspace_id_text :: proc(id: ^Workspace_ID) -> string {
	if id == nil || id.length > u32(len(id.bytes)) {
		return ""
	}
	return string(id.bytes[:id.length])
}

/* workspace_name_text returns the copied Workspace display name. */
workspace_name_text :: proc(name: ^Workspace_Name) -> string {
	if name == nil || name.length > u32(len(name.bytes)) {
		return ""
	}
	return string(name.bytes[:name.length])
}

@(private)
session_active_workspace_clear :: proc(data: ^Session_Data) {
	if data != nil {
		data.active_workspace = {}
	}
}

@(private)
workspace_owner_descriptor :: proc(owner: ^Workspace_Owner) -> Workspace_Descriptor {
	return Workspace_Descriptor {
		id = owner.id,
		generation = owner.generation,
		name = owner.name,
		root_set = owner.root_set,
		project_count = owner.project_count,
	}
}

@(private)
workspace_identity_copy :: proc(target: ^Workspace_ID, value: string) {
	copy(target.bytes[:], transmute([]u8)value)
	target.length = u32(len(value))
}

@(private)
workspace_name_copy :: proc(target: ^Workspace_Name, value: string) {
	copy(target.bytes[:], transmute([]u8)value)
	target.length = u32(len(value))
}

@(private)
workspace_identity_valid :: proc(value: string) -> bool {
	if len(value) == 0 || len(value) > MAX_WORKSPACE_ID_BYTES ||
	   !utf8.valid_string(value) || strings.index_byte(value, 0) >= 0 ||
	   value[0] == '-' || value[len(value) - 1] == '-' {
		return false
	}
	previous_hyphen := false
	for byte in transmute([]u8)value {
		if byte == '-' {
			if previous_hyphen {
				return false
			}
			previous_hyphen = true
		} else {
			if !((byte >= 'a' && byte <= 'z') || (byte >= '0' && byte <= '9')) {
				return false
			}
			previous_hyphen = false
		}
	}
	return true
}

@(private)
workspace_name_valid :: proc(value: string) -> bool {
	return len(value) > 0 && len(value) <= MAX_WORKSPACE_NAME_BYTES &&
	       utf8.valid_string(value) && strings.index_byte(value, 0) < 0
}

@(private)
session_roots_equal :: proc(data: ^Session_Data, roots: []Root_Proposal) -> bool {
	if len(data.roots) != len(roots) {
		return false
	}
	for root, index in roots {
		current := &data.roots[index]
		if current.kind != root.kind || current.path != root.path {
			return false
		}
	}
	return true
}

@(private)
session_modified_entry_count :: proc(
	data: ^Session_Data,
	operation: Operation,
) -> (count: u32, failure: Failure_Context) {
	for &slot in data.slots {
		if !slot.live {
			continue
		}
		stats, stats_ok, editor_failure := editor.buffer_stats(&slot.owner.buffer)
		if !stats_ok {
			failure = session_failure(data, operation, .Editor_Failure)
			failure.editor_failure = editor_failure
			return 0, failure
		}
		modified := stats.revision != editor.Revision(0)
		if slot.owner.association == .Document {
			status, status_ok, document_failure := document.document_status(&slot.owner.document)
			if !status_ok {
				failure = session_failure(data, operation, .Document_Failure)
				failure.document_failure = document_failure
				return 0, failure
			}
			modified = !status.has_saved_revision || status.saved_revision != stats.revision
		}
		if modified {
			count += 1
		}
	}
	return count, {}
}

@(private)
workspace_activation_state_destroy :: proc(state: ^Workspace_Activation_State) {
	if state == nil {
		return
	}
	allocator := state.allocator
	if state.paths != nil {
		delete(state.paths, allocator)
	}
	if state.roots != nil {
		delete(state.roots, allocator)
	}
	if state.projects != nil {
		workspace_project_slice_destroy(state.projects)
		delete(state.projects, allocator)
	}
	free(state, allocator)
}

@(private)
workspace_project_slice_destroy :: proc(projects: []Workspace_Project_Owner) {
	for &owner in projects {
		if owner.registry.state != nil {
			progress := project.registry_close(&owner.registry)
			assert(progress.complete && progress.first_failure.code == .None)
		}
		owner = {}
	}
}

@(private)
session_workspace_projects_clear :: proc(data: ^Session_Data) {
	if data == nil {
		return
	}
	workspace_project_slice_destroy(data.workspace_projects)
	if data.workspace_projects != nil {
		delete(data.workspace_projects, data.allocator)
	}
	assert(data.usage.registry_bytes >= data.workspace_project_registry_bytes)
	data.usage.registry_bytes -= data.workspace_project_registry_bytes
	data.workspace_projects = nil
	data.workspace_project_registry_bytes = 0
	if data.active_project != data.primary_project {
		data.active_project = data.primary_project
	}
}
