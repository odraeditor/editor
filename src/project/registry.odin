// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package project

import "../document"
import "base:runtime"
import "core:strings"
import "core:unicode/utf8"

@(private)
Membership_Owner :: struct {
	handle:       Membership_Handle,
	path:         string,
	trust:        Trust_State,
	availability: Availability,
}

@(private)
Registry_State :: struct {
	owner:              Owner_Handle,
	project:            Project_Handle,
	durable_id:         string,
	name:               string,
	memberships:        [dynamic]Membership_Owner,
	policy:             Policy,
	usage:              Resource_Usage,
	next_membership_id: Membership_ID,
	temporary:          bool,
	allocators:         Allocator_Set,
}

@(private)
Prepared_State :: struct {
	registry_state: rawptr,
	project:        Project_Handle,
	durable_id:     string,
	name:           string,
	memberships:    [dynamic]Membership_Owner,
	reservation:    Reservation,
	next_membership_id: Membership_ID,
	temporary:      bool,
	consumed:       bool,
	allocator:      runtime.Allocator,
}

@(private)
Descriptor_Batch_State :: struct {
	descriptors: []Membership_Descriptor,
	allocator:   runtime.Allocator,
}

/* registry_init creates one empty checked Project registry with no active Project. */
registry_init :: proc(
	registry: ^Registry,
	owner: Owner_Handle,
	policy: Policy,
	allocators: Allocator_Set,
) -> (ok: bool, failure: Failure_Context) {
	assert(registry != nil)
	registry^ = {}
	if !owner_handle_is_valid(owner) {
		return false, Failure_Context{code = .Invalid_Owner, operation = .Initialize, owner = owner}
	}
	if policy_ok, policy_failure := policy_validate(policy); !policy_ok {
		policy_failure.operation = .Initialize
		return false, policy_failure
	}
	if allocators.persistent.procedure == nil || allocators.temporary.procedure == nil {
		return false, Failure_Context{code = .Persistent_Memory_Limit, operation = .Initialize, owner = owner}
	}
	state, state_error := new(Registry_State, allocators.persistent)
	if state_error != nil {
		return false, Failure_Context{code = .Persistent_Memory_Limit, operation = .Initialize, owner = owner}
	}
	memberships, membership_error := make(
		[dynamic]Membership_Owner,
		0,
		int(policy.directories),
		allocators.persistent,
	)
	if membership_error != nil {
		free(state, allocators.persistent)
		return false, Failure_Context{code = .Persistent_Memory_Limit, operation = .Initialize, owner = owner}
	}
	state^ = Registry_State{
		owner = owner,
		memberships = memberships,
		policy = policy,
		next_membership_id = Membership_ID(1),
		allocators = allocators,
	}
	state.usage.registry_bytes = u64(size_of(Registry_State)) +
		u64(cap(state.memberships)) * u64(size_of(Membership_Owner))
	registry.state = state
	return true, {}
}

/* registry_close releases an empty or populated Project registry and invalidates every handle. */
registry_close :: proc(registry: ^Registry) -> (progress: Cleanup_Progress) {
	if registry == nil || registry.state == nil {
		if registry != nil {
			registry.closed = true
		}
		return Cleanup_Progress{complete = true}
	}
	state := registry_state(registry)
	for &membership in state.memberships {
		progress.released_bytes += u64(len(membership.path))
		delete(membership.path, state.allocators.persistent)
		progress.processed_directories += 1
	}
	delete(state.memberships)
	if len(state.name) > 0 {
		progress.released_bytes += u64(len(state.name))
		delete(state.name, state.allocators.persistent)
	}
	if len(state.durable_id) > 0 {
		progress.released_bytes += u64(len(state.durable_id))
		delete(state.durable_id, state.allocators.persistent)
	}
	progress.released_bytes += u64(size_of(Registry_State))
	free(state, state.allocators.persistent)
	registry^ = Registry{closed = true}
	progress.complete = true
	return
}

/* registry_prepare_snapshot validates and privately owns one complete immutable Project candidate. */
registry_prepare_snapshot :: proc(
	registry: ^Registry,
	request: Snapshot_Request,
	prepared: ^Prepared_Snapshot,
) -> (ok: bool, failure: Failure_Context) {
	assert(prepared != nil)
	prepared^ = {}
	state, resolved := resolve_registry(registry, request.owner, .Prepare)
	if resolved.code != .None {
		return false, resolved
	}
	return registry_prepare_snapshot_state(state, request, prepared, false)
}

/* registry_prepare_replacement_snapshot privately replaces one exact active identity. */
registry_prepare_replacement_snapshot :: proc(
	registry: ^Registry,
	expected: Project_Handle,
	request: Snapshot_Request,
	prepared: ^Prepared_Snapshot,
) -> (ok: bool, failure: Failure_Context) {
	assert(prepared != nil)
	prepared^ = {}
	state, resolved := resolve_registry(registry, request.owner, .Prepare)
	if resolved.code != .None {
		return false, resolved
	}
	if !project_handle_is_valid(expected) || state.project != expected {
		return false, project_failure(state, .Prepare, .Stale_Project)
	}
	return registry_prepare_snapshot_state(state, request, prepared, true)
}

@(private)
registry_prepare_snapshot_state :: proc(
	state: ^Registry_State,
	request: Snapshot_Request,
	prepared: ^Prepared_Snapshot,
	identity_replacement: bool,
) -> (ok: bool, failure: Failure_Context) {
	if request.project_id == Project_ID(0) {
		return false, project_failure(state, .Prepare, .Invalid_Project)
	}
	if !identity_replacement && state.project.id != Project_ID(0) &&
	   state.project.id != request.project_id {
		failure = project_failure(state, .Prepare, .Invalid_Project)
		failure.actual = u64(request.project_id)
		return false, failure
	}
	if !project_name_is_valid(request.name, state.policy.name_bytes) {
		failure = project_failure(state, .Prepare, .Invalid_Name)
		failure.actual = u64(len(request.name))
		failure.maximum = state.policy.name_bytes
		return false, failure
	}
	if request.temporary {
		if len(request.durable_id) != 0 {
			return false, project_failure(state, .Prepare, .Invalid_Project)
		}
	} else if !project_durable_id_is_valid(request.durable_id) {
		failure = project_failure(state, .Prepare, .Invalid_Project)
		failure.actual = u64(len(request.durable_id))
		failure.maximum = MAX_DURABLE_ID_BYTES
		return false, failure
	}
	if len(request.directories) < int(MIN_DIRECTORIES) ||
	   len(request.directories) > int(state.policy.directories) {
		failure = project_failure(state, .Prepare, .Directory_Limit)
		failure.maximum = u64(state.policy.directories)
		failure.actual = u64(len(request.directories))
		return false, failure
	}

	private, private_error := new(Prepared_State, state.allocators.persistent)
	if private_error != nil {
		return false, project_failure(state, .Prepare, .Persistent_Memory_Limit)
	}
	private^ = Prepared_State{
		registry_state = state,
		next_membership_id = state.next_membership_id,
		temporary = request.temporary,
		allocator = state.allocators.persistent,
	}
	private.name, private_error = strings.clone(request.name, private.allocator)
	if private_error != nil {
		free(private, private.allocator)
		return false, project_failure(state, .Prepare, .Persistent_Memory_Limit)
	}
	if len(request.durable_id) > 0 {
		private.durable_id, private_error = strings.clone(request.durable_id, private.allocator)
		if private_error != nil {
			delete(private.name, private.allocator)
			free(private, private.allocator)
			return false, project_failure(state, .Prepare, .Persistent_Memory_Limit)
		}
	}
	private.memberships, private_error = make(
		[dynamic]Membership_Owner,
		0,
		int(state.policy.directories),
		private.allocator,
	)
	if private_error != nil {
		if len(private.durable_id) > 0 {
			delete(private.durable_id, private.allocator)
		}
		delete(private.name, private.allocator)
		free(private, private.allocator)
		return false, project_failure(state, .Prepare, .Persistent_Memory_Limit)
	}

	project_generation := Project_Generation(1)
	if identity_replacement {
		project_generation = request.project_generation
		if project_generation == Project_Generation(0) {
			project_generation = Project_Generation(1)
		}
	} else if state.project.id == Project_ID(0) && request.project_generation != Project_Generation(0) {
		project_generation = request.project_generation
	} else if state.project.id == request.project_id {
		if request.project_generation != Project_Generation(0) {
			prepared_state_release(private)
			return false, project_failure(state, .Prepare, .Invalid_Project)
		}
		if state.project.generation == Project_Generation(max(u64)) {
			prepared_state_release(private)
			return false, project_failure(state, .Prepare, .Identity_Limit)
		}
		project_generation = state.project.generation + Project_Generation(1)
	}
	private.project = Project_Handle{
		owner = state.owner,
		id = request.project_id,
		generation = project_generation,
	}
	private.reservation = Reservation{
		projects = 1,
		directories = u32(len(request.directories)),
		name_bytes = u64(len(request.name)),
		registry_bytes = u64(size_of(Prepared_State)) +
			u64(cap(private.memberships)) * u64(size_of(Membership_Owner)),
	}

	for proposal in request.directories {
		if proposal.trust != .Untrusted && proposal.trust != .Trusted {
			prepared_state_release(private)
			return false, project_failure(state, .Prepare, .Invalid_Path)
		}
		normalized: document.Normalized_Path
		normalized_ok, normalized_failure := document.path_normalize(
			proposal.path,
			&normalized,
			state.allocators.temporary,
		)
		if !normalized_ok {
			failure = project_failure(state, .Prepare, .Invalid_Path)
			failure.actual = normalized_failure.actual
			if normalized_failure.code == .Path_Limit {
				failure.code = .Path_Limit
				failure.maximum = document.MAX_PATH_BYTES
			}
			prepared_state_release(private)
			return false, failure
		}
		path := document.normalized_path_text(&normalized)
		if private_find_path(private, path) >= 0 {
			prepared_state_release(private)
			return false, project_failure(state, .Prepare, .Duplicate_Path)
		}
		if private.reservation.path_bytes + u64(len(path)) > state.policy.retained_path_bytes {
			failure = project_failure(state, .Prepare, .Retained_Path_Limit)
			failure.maximum = state.policy.retained_path_bytes
			failure.actual = private.reservation.path_bytes + u64(len(path))
			prepared_state_release(private)
			return false, failure
		}
		owned_path, path_error := strings.clone(path, private.allocator)
		if path_error != nil {
			prepared_state_release(private)
			return false, project_failure(state, .Prepare, .Persistent_Memory_Limit)
		}
		handle := next_membership_handle(
			state,
			private,
			private.project,
			path,
			proposal.trust,
			u32(len(private.memberships)),
		)
		if !membership_handle_is_valid(handle) {
			delete(owned_path, private.allocator)
			prepared_state_release(private)
			return false, project_failure(state, .Prepare, .Identity_Limit)
		}
		_, append_error := append(&private.memberships, Membership_Owner{
			handle = handle,
			path = owned_path,
			trust = proposal.trust,
			availability = .Unknown,
		})
		if append_error != nil {
			delete(owned_path, private.allocator)
			prepared_state_release(private)
			return false, project_failure(state, .Prepare, .Persistent_Memory_Limit)
		}
		private.reservation.path_bytes += u64(len(path))
	}
	private.reservation.registry_bytes += private.reservation.name_bytes +
		private.reservation.path_bytes + u64(len(private.durable_id))
	prepared.state = private
	return true, {}
}

/* prepared_snapshot_publish atomically replaces the active Project with one complete candidate. */
prepared_snapshot_publish :: proc(
	registry: ^Registry,
	prepared: ^Prepared_Snapshot,
) -> (descriptor: Project_Descriptor, ok: bool, failure: Failure_Context) {
	if registry == nil || registry.state == nil || prepared == nil || prepared.state == nil {
		return {}, false, Failure_Context{code = .Invalid_Registry, operation = .Publish}
	}
	state := registry_state(registry)
	private := prepared_state(prepared)
	if private.consumed || private.registry_state != state {
		return {}, false, project_failure(state, .Publish, .Invalid_Project)
	}
	old_name := state.name
	old_durable_id := state.durable_id
	old_memberships := state.memberships
	state.project = private.project
	state.durable_id = private.durable_id
	state.name = private.name
	state.memberships = private.memberships
	state.next_membership_id = private.next_membership_id
	state.temporary = private.temporary
	state.usage = usage_from_state(state)
	private.name = ""
	private.durable_id = ""
	private.memberships = nil
	private.consumed = true
	prepared_state_release(private)
	prepared^ = {}

	for membership in old_memberships {
		delete(membership.path, state.allocators.persistent)
	}
	if old_memberships != nil {
		delete(old_memberships)
	}
	if len(old_name) > 0 {
		delete(old_name, state.allocators.persistent)
	}
	if len(old_durable_id) > 0 {
		delete(old_durable_id, state.allocators.persistent)
	}
	assert(registry_validate(registry))
	return project_descriptor_from_state(state), true, {}
}

/* prepared_snapshot_abort releases one unpublished Project candidate. */
prepared_snapshot_abort :: proc(prepared: ^Prepared_Snapshot) {
	if prepared == nil || prepared.state == nil {
		return
	}
	prepared_state_release(prepared_state(prepared))
	prepared^ = {}
}

/* registry_project_descriptor returns one copied active Project summary. */
registry_project_descriptor :: proc(
	registry: ^Registry,
	handle: Project_Handle,
) -> (descriptor: Project_Descriptor, ok: bool, failure: Failure_Context) {
	state, resolved := resolve_project(registry, handle, .Inspect)
	if resolved.code != .None {
		return {}, false, resolved
	}
	return project_descriptor_from_state(state), true, {}
}

/* registry_membership_descriptors copies a bounded active membership batch. */
registry_membership_descriptors :: proc(
	registry: ^Registry,
	handle: Project_Handle,
) -> (batch: Descriptor_Batch, ok: bool, failure: Failure_Context) {
	state, resolved := resolve_project(registry, handle, .Membership_Descriptors)
	if resolved.code != .None {
		return {}, false, resolved
	}
	if len(state.memberships) > int(state.policy.descriptor_batch) {
		failure = project_failure(state, .Membership_Descriptors, .Descriptor_Limit)
		failure.maximum = u64(state.policy.descriptor_batch)
		failure.actual = u64(len(state.memberships))
		return {}, false, failure
	}
	batch_state, state_error := new(Descriptor_Batch_State, state.allocators.persistent)
	if state_error != nil {
		return {}, false, project_failure(state, .Membership_Descriptors, .Persistent_Memory_Limit)
	}
	descriptors, descriptor_error := make(
		[]Membership_Descriptor,
		len(state.memberships),
		state.allocators.persistent,
	)
	if descriptor_error != nil {
		free(batch_state, state.allocators.persistent)
		return {}, false, project_failure(state, .Membership_Descriptors, .Persistent_Memory_Limit)
	}
	for membership, index in state.memberships {
		descriptors[index] = membership_descriptor_copy(membership)
	}
	batch_state^ = Descriptor_Batch_State{
		descriptors = descriptors,
		allocator = state.allocators.persistent,
	}
	return Descriptor_Batch{state = batch_state, descriptors = descriptors}, true, {}
}

/* descriptor_batch_close releases one copied membership descriptor batch. */
descriptor_batch_close :: proc(batch: ^Descriptor_Batch) {
	if batch == nil || batch.state == nil {
		return
	}
	state := (^Descriptor_Batch_State)(batch.state)
	if state.descriptors != nil {
		delete(state.descriptors, state.allocator)
	}
	allocator := state.allocator
	free(state, allocator)
	batch^ = {}
}

/* registry_find_membership resolves one exact normalized path in the active Project. */
registry_find_membership :: proc(
	registry: ^Registry,
	project: Project_Handle,
	path: string,
) -> (handle: Membership_Handle, found: bool, failure: Failure_Context) {
	state, resolved := resolve_project(registry, project, .Find_Membership)
	if resolved.code != .None {
		return {}, false, resolved
	}
	normalized: document.Normalized_Path
	if normalized_ok, _ := document.path_normalize(path, &normalized, state.allocators.temporary); !normalized_ok {
		return {}, false, project_failure(state, .Find_Membership, .Invalid_Path)
	}
	target := document.normalized_path_text(&normalized)
	for membership in state.memberships {
		if membership.path == target {
			return membership.handle, true, {}
		}
	}
	return {}, false, {}
}

/* registry_classify_path returns every containing membership from one immutable Project generation. */
registry_classify_path :: proc(
	registry: ^Registry,
	project: Project_Handle,
	path: string,
	results: []Membership_Handle,
) -> (count: u32, ok: bool, failure: Failure_Context) {
	state, resolved := resolve_project(registry, project, .Classify_Path)
	if resolved.code != .None {
		return 0, false, resolved
	}
	normalized: document.Normalized_Path
	if normalized_ok, normalized_failure := document.path_normalize(
		path,
		&normalized,
		state.allocators.temporary,
	); !normalized_ok {
		failure = project_failure(state, .Classify_Path, .Invalid_Path)
		failure.actual = normalized_failure.actual
		return 0, false, failure
	}
	target := document.normalized_path_text(&normalized)
	for membership in state.memberships {
		if !path_contains(membership.path, target) {
			continue
		}
		if int(count) >= len(results) {
			failure = project_failure(state, .Classify_Path, .Descriptor_Limit)
			failure.maximum = u64(len(results))
			failure.actual = u64(count) + 1
			return count, false, failure
		}
		results[count] = membership.handle
		count += 1
	}
	return count, true, {}
}

/* registry_usage reports exact logical Project occupancy and retained bytes. */
registry_usage :: proc(registry: ^Registry) -> (usage: Resource_Usage, ok: bool) {
	if registry == nil || registry.state == nil || registry.closed {
		return {}, false
	}
	return registry_state(registry).usage, true
}

/* registry_validate checks the complete active Project relationship graph. */
registry_validate :: proc(registry: ^Registry) -> bool {
	if registry == nil || registry.state == nil || registry.closed {
		return false
	}
	state := registry_state(registry)
	if !owner_handle_is_valid(state.owner) {
		return false
	}
	if state.project.id == Project_ID(0) {
		return len(state.durable_id) == 0 && len(state.name) == 0 &&
		       len(state.memberships) == 0 && state.usage.projects == 0
	}
	if !project_handle_is_valid(state.project) || !project_name_is_valid(state.name, state.policy.name_bytes) ||
	   (state.temporary && len(state.durable_id) != 0) ||
	   (!state.temporary && !project_durable_id_is_valid(state.durable_id)) ||
	   len(state.memberships) < int(MIN_DIRECTORIES) ||
	   len(state.memberships) > int(state.policy.directories) {
		return false
	}
	for left, left_index in state.memberships {
		if !membership_handle_is_valid(left.handle) || left.handle.project != state.project ||
		   left.handle.slot != u32(left_index) || len(left.path) == 0 {
			return false
		}
		for right_index in left_index + 1 ..< len(state.memberships) {
			if left.path == state.memberships[right_index].path {
				return false
			}
		}
	}
	return state.usage == usage_from_state(state)
}

@(private)
registry_state :: proc(registry: ^Registry) -> ^Registry_State {
	return (^Registry_State)(registry.state)
}

@(private)
prepared_state :: proc(prepared: ^Prepared_Snapshot) -> ^Prepared_State {
	return (^Prepared_State)(prepared.state)
}

@(private)
prepared_state_release :: proc(state: ^Prepared_State) {
	if state == nil {
		return
	}
	for membership in state.memberships {
		delete(membership.path, state.allocator)
	}
	if state.memberships != nil {
		delete(state.memberships)
	}
	if len(state.name) > 0 {
		delete(state.name, state.allocator)
	}
	if len(state.durable_id) > 0 {
		delete(state.durable_id, state.allocator)
	}
	allocator := state.allocator
	free(state, allocator)
}

@(private)
resolve_registry :: proc(
	registry: ^Registry,
	owner: Owner_Handle,
	operation: Operation,
) -> (state: ^Registry_State, failure: Failure_Context) {
	if registry == nil || registry.state == nil {
		return nil, Failure_Context{code = .Invalid_Registry, operation = operation, owner = owner}
	}
	state = registry_state(registry)
	if registry.closed {
		return nil, Failure_Context{code = .Closed_Registry, operation = operation, owner = owner}
	}
	if !owner_handle_is_valid(owner) {
		return nil, Failure_Context{code = .Invalid_Owner, operation = operation, owner = owner}
	}
	if owner.id != state.owner.id {
		return nil, Failure_Context{code = .Wrong_Owner, operation = operation, owner = owner}
	}
	if owner.generation != state.owner.generation {
		return nil, Failure_Context{code = .Stale_Owner, operation = operation, owner = owner}
	}
	return state, {}
}

@(private)
resolve_project :: proc(
	registry: ^Registry,
	handle: Project_Handle,
	operation: Operation,
) -> (state: ^Registry_State, failure: Failure_Context) {
	state, failure = resolve_registry(registry, handle.owner, operation)
	if failure.code != .None {
		return
	}
	if !project_handle_is_valid(handle) || state.project.id == Project_ID(0) {
		return nil, project_failure(state, operation, .Invalid_Project)
	}
	if handle.id != state.project.id {
		return nil, project_failure(state, operation, .Invalid_Project)
	}
	if handle.generation != state.project.generation {
		failure = project_failure(state, operation, .Stale_Project)
		failure.project = handle
		return nil, failure
	}
	return state, {}
}

@(private)
project_failure :: proc(
	state: ^Registry_State,
	operation: Operation,
	code: Failure_Code,
) -> Failure_Context {
	failure := Failure_Context{code = code, operation = operation}
	if state != nil {
		failure.owner = state.owner
		failure.project = state.project
	}
	return failure
}

@(private)
project_name_is_valid :: proc(name: string, limit: u64) -> bool {
	return len(name) > 0 && u64(len(name)) <= limit && utf8.valid_string(name) &&
	       strings.index_byte(name, 0) < 0
}

@(private)
private_find_path :: proc(state: ^Prepared_State, path: string) -> int {
	for membership, index in state.memberships {
		if membership.path == path {
			return index
		}
	}
	return -1
}

@(private)
next_membership_handle :: proc(
	state: ^Registry_State,
	private: ^Prepared_State,
	project: Project_Handle,
	path: string,
	trust: Trust_State,
	slot: u32,
) -> Membership_Handle {
	for membership in state.memberships {
		if membership.path == path {
			generation := membership.handle.generation
			if membership.trust != trust {
				if generation == Membership_Generation(max(u32)) {
					return {}
				}
				generation += Membership_Generation(1)
			}
			return Membership_Handle{
				project = project,
				id = membership.handle.id,
				slot = slot,
				generation = generation,
			}
		}
	}
	if private.next_membership_id == Membership_ID(0) ||
	   private.next_membership_id == Membership_ID(max(u64)) {
		return {}
	}
	handle := Membership_Handle{
		project = project,
		id = private.next_membership_id,
		slot = slot,
		generation = Membership_Generation(1),
	}
	private.next_membership_id += Membership_ID(1)
	return handle
}

@(private)
usage_from_state :: proc(state: ^Registry_State) -> Resource_Usage {
	usage := Resource_Usage{
		projects = 1 if state.project.id != Project_ID(0) else 0,
		directories = u32(len(state.memberships)),
		retained_name_bytes = u64(len(state.name)),
		registry_bytes = u64(size_of(Registry_State)) +
			u64(cap(state.memberships)) * u64(size_of(Membership_Owner)),
	}
	for membership in state.memberships {
		usage.retained_path_bytes += u64(len(membership.path))
		usage.registry_bytes += u64(len(membership.path))
		if membership.trust == .Trusted {
			usage.trusted_directories += 1
		}
		if membership.availability == .Unavailable {
			usage.unavailable_directories += 1
		}
	}
	usage.registry_bytes += usage.retained_name_bytes
	usage.registry_bytes += u64(len(state.durable_id))
	return usage
}

@(private)
project_descriptor_from_state :: proc(state: ^Registry_State) -> Project_Descriptor {
	descriptor := Project_Descriptor{
		handle = state.project,
		directory_count = state.usage.directories,
		trusted_directories = state.usage.trusted_directories,
		unavailable_directories = state.usage.unavailable_directories,
		temporary = state.temporary,
	}
	descriptor.durable_id.length = u32(len(state.durable_id))
	copy(descriptor.durable_id.bytes[:], state.durable_id)
	descriptor.name.length = u32(len(state.name))
	copy(descriptor.name.bytes[:], state.name)
	return descriptor
}

/* project_durable_id_text returns one descriptor-owned durable identity view. */
project_durable_id_text :: proc(identity: ^Project_Durable_ID) -> string {
	if identity == nil || identity.length > u32(len(identity.bytes)) {
		return ""
	}
	return string(identity.bytes[:identity.length])
}

@(private)
project_durable_id_is_valid :: proc(identity: string) -> bool {
	if len(identity) == 0 || len(identity) > int(MAX_DURABLE_ID_BYTES) || !utf8.valid_string(identity) {
		return false
	}
	previous_hyphen := true
	for byte in transmute([]u8)identity {
		if byte == '-' {
			if previous_hyphen {
				return false
			}
			previous_hyphen = true
			continue
		}
		if !(byte >= 'a' && byte <= 'z') && !(byte >= '0' && byte <= '9') {
			return false
		}
		previous_hyphen = false
	}
	return !previous_hyphen
}

@(private)
membership_descriptor_copy :: proc(owner: Membership_Owner) -> Membership_Descriptor {
	descriptor := Membership_Descriptor{
		handle = owner.handle,
		trust = owner.trust,
		availability = owner.availability,
	}
	descriptor.path.length = u32(len(owner.path))
	copy(descriptor.path.bytes[:], owner.path)
	return descriptor
}

@(private)
path_contains :: proc(directory, candidate: string) -> bool {
	if directory == "/" {
		return strings.has_prefix(candidate, "/")
	}
	return candidate == directory ||
		(len(candidate) > len(directory) && strings.has_prefix(candidate, directory) &&
		 candidate[len(directory)] == '/')
}
