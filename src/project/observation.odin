// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package project

import "base:runtime"
import "core:os"
import "core:strings"

/* Watcher_Hint classifies optional filesystem notifications without treating them as evidence. */
Watcher_Hint :: enum u8 {
	Invalid,
	Activity,
	Loss,
	Overflow,
}

/* Observation_Registry owns bounded refresh candidates for one Project generation. */
Observation_Registry :: struct {
	state:  rawptr,
	closed: bool,
}

/* Observation_Descriptor is one copied published directory observation. */
Observation_Descriptor :: struct {
	membership:    Membership_Handle,
	availability:  Availability,
	dirty:         bool,
	config_present: bool,
}

/* Observation_Batch owns copied observation descriptors until explicit close. */
Observation_Batch :: struct {
	state:       rawptr,
	descriptors: []Observation_Descriptor,
}

/* Reconcile_Result reports one bounded turn and any complete observation publication. */
Reconcile_Result :: struct {
	generation:              Observation_Generation,
	processed_directories:   u32,
	remaining_directories:   u32,
	unavailable_directories: u32,
	published:               bool,
	cancelled:               bool,
}

@(private)
Observation_Entry :: struct {
	membership:         Membership_Handle,
	path:               string,
	trust:              Trust_State,
	availability:       Availability,
	config_present:     bool,
	dirty:              bool,
	candidate_ready:    bool,
	candidate_available: Availability,
	candidate_config:   bool,
}

@(private)
Observation_State :: struct {
	project:      Project_Handle,
	generation:   Observation_Generation,
	entries:      [dynamic]Observation_Entry,
	policy:       Policy,
	dirty_count:  u32,
	reconciling:  bool,
	cursor:       u32,
	allocators:   Allocator_Set,
}

@(private)
Observation_Batch_State :: struct {
	descriptors: []Observation_Descriptor,
	allocator:   runtime.Allocator,
}

/* observation_registry_init copies one membership generation and marks it stale for refresh. */
observation_registry_init :: proc(
	registry: ^Observation_Registry,
	project: Project_Handle,
	memberships: []Membership_Descriptor,
	policy: Policy,
	allocators: Allocator_Set,
) -> (ok: bool, failure: Failure_Context) {
	assert(registry != nil)
	registry^ = {}
	if !project_handle_is_valid(project) || allocators.persistent.procedure == nil ||
	   allocators.temporary.procedure == nil {
		return false, Failure_Context{code = .Invalid_Project, operation = .Initialize_Observations, project = project}
	}
	if policy_ok, policy_failure := policy_validate(policy); !policy_ok {
		policy_failure.operation = .Initialize_Observations
		return false, policy_failure
	}
	if len(memberships) > int(policy.directories) || len(memberships) > int(policy.dirty_markers) {
		return false, observation_failure(
			project,
			.Initialize_Observations,
			.Dirty_Marker_Limit,
			u64(policy.dirty_markers),
			u64(len(memberships)),
		)
	}
	state, state_error := new(Observation_State, allocators.persistent)
	if state_error != nil {
		return false, Failure_Context{code = .Persistent_Memory_Limit, operation = .Initialize_Observations, project = project}
	}
	entries, entries_error := make(
		[dynamic]Observation_Entry,
		0,
		len(memberships),
		allocators.persistent,
	)
	if entries_error != nil {
		free(state, allocators.persistent)
		return false, Failure_Context{code = .Persistent_Memory_Limit, operation = .Initialize_Observations, project = project}
	}
	state^ = Observation_State {
		project = project,
		generation = Observation_Generation(1),
		entries = entries,
		policy = policy,
		dirty_count = u32(len(memberships)),
		allocators = allocators,
	}
	for &descriptor in memberships {
		if !membership_handle_is_valid(descriptor.handle) || descriptor.handle.project != project {
			observation_state_destroy(state)
			return false, Failure_Context{code = .Invalid_Membership, operation = .Initialize_Observations, project = project}
		}
		path, path_error := strings.clone(directory_path_text(&descriptor.path), allocators.persistent)
		if path_error != nil {
			observation_state_destroy(state)
			return false, Failure_Context{code = .Persistent_Memory_Limit, operation = .Initialize_Observations, project = project}
		}
		_, append_error := append(&state.entries, Observation_Entry {
			membership = descriptor.handle,
			path = path,
			trust = descriptor.trust,
			availability = .Stale,
			dirty = true,
		})
		if append_error != nil {
			delete(path, allocators.persistent)
			observation_state_destroy(state)
			return false, Failure_Context{code = .Persistent_Memory_Limit, operation = .Initialize_Observations, project = project}
		}
	}
	registry.state = state
	return true, {}
}

/* observation_mark_hint coalesces activity, loss, and overflow into one bounded dirty marker. */
observation_mark_hint :: proc(
	registry: ^Observation_Registry,
	project: Project_Handle,
	membership: Membership_Handle,
	hint: Watcher_Hint,
) -> (ok: bool, failure: Failure_Context) {
	state, resolved := observation_resolve(registry, project, .Mark_Dirty)
	if resolved.code != .None {
		return false, resolved
	}
	if hint == .Invalid {
		return false, observation_failure(project, .Mark_Dirty, .Invalid_Membership, 0, 0)
	}
	entry := observation_find(state, membership)
	if entry == nil {
		return false, Failure_Context{code = .Stale_Membership, operation = .Mark_Dirty, project = project, membership = membership}
	}
	if !entry.dirty {
		if state.dirty_count >= state.policy.dirty_markers {
			return false, observation_failure(project, .Mark_Dirty, .Dirty_Marker_Limit, u64(state.policy.dirty_markers), u64(state.dirty_count) + 1)
		}
		entry.dirty = true
		state.dirty_count += 1
	}
	if hint == .Loss || hint == .Overflow {
		entry.availability = .Stale
	}
	return true, {}
}

/* observation_request_refresh marks every membership without duplicating dirty work. */
observation_request_refresh :: proc(
	registry: ^Observation_Registry,
	project: Project_Handle,
) -> (ok: bool, failure: Failure_Context) {
	state, resolved := observation_resolve(registry, project, .Refresh)
	if resolved.code != .None {
		return false, resolved
	}
	if len(state.entries) > int(state.policy.dirty_markers) {
		return false, observation_failure(project, .Refresh, .Dirty_Marker_Limit, u64(state.policy.dirty_markers), u64(len(state.entries)))
	}
	for &entry in state.entries {
		entry.dirty = true
		entry.availability = .Stale
		entry.candidate_ready = false
	}
	state.dirty_count = u32(len(state.entries))
	state.reconciling = false
	state.cursor = 0
	return true, {}
}

/* observation_reconcile advances bounded work and publishes only one complete generation. */
observation_reconcile :: proc(
	registry: ^Observation_Registry,
	project: Project_Handle,
	cancelled := false,
) -> (result: Reconcile_Result, ok: bool, failure: Failure_Context) {
	state, resolved := observation_resolve(registry, project, .Reconcile)
	if resolved.code != .None {
		return {}, false, resolved
	}
	result.generation = state.generation
	if cancelled {
		observation_candidate_abort(state)
		result.cancelled = true
		result.remaining_directories = state.dirty_count
		return result, true, {}
	}
	if state.dirty_count == 0 {
		return result, true, {}
	}
	state.reconciling = true
	work_limit := state.policy.entries_per_turn
	for state.cursor < u32(len(state.entries)) && result.processed_directories < work_limit {
		entry := &state.entries[state.cursor]
		state.cursor += 1
		if !entry.dirty {
			continue
		}
		entry.candidate_available = .Unavailable
		entry.candidate_config = false
		if os.is_directory(entry.path) {
			entry.candidate_available = .Available
			if entry.trust == .Trusted {
				config_path, path_error := os.join_path({entry.path, ".odra", "config.rkt"}, state.allocators.temporary)
				if path_error == nil {
					entry.candidate_config = os.is_file(config_path)
					delete(config_path, state.allocators.temporary)
				}
			}
		}
		entry.candidate_ready = true
		result.processed_directories += 1
	}
	for entry in state.entries {
		if entry.dirty && !entry.candidate_ready {
			result.remaining_directories += 1
		}
	}
	if result.remaining_directories > 0 {
		return result, true, {}
	}
	if state.generation == Observation_Generation(max(u64)) {
		observation_candidate_abort(state)
		return {}, false, observation_failure(project, .Reconcile, .Identity_Limit, 0, u64(state.generation))
	}
	for &entry in state.entries {
		if entry.dirty {
			entry.availability = entry.candidate_available
			entry.config_present = entry.candidate_config
			entry.dirty = false
			entry.candidate_ready = false
		}
		if entry.availability == .Unavailable {
			result.unavailable_directories += 1
		}
	}
	state.dirty_count = 0
	state.reconciling = false
	state.cursor = 0
	state.generation += Observation_Generation(1)
	result.generation = state.generation
	result.published = true
	return result, true, {}
}

/* observation_descriptors copies the last completely published observation. */
observation_descriptors :: proc(
	registry: ^Observation_Registry,
	project: Project_Handle,
) -> (batch: Observation_Batch, generation: Observation_Generation, ok: bool, failure: Failure_Context) {
	state, resolved := observation_resolve(registry, project, .Observation_Descriptors)
	if resolved.code != .None {
		return {}, 0, false, resolved
	}
	batch_state, state_error := new(Observation_Batch_State, state.allocators.persistent)
	if state_error != nil {
		return {}, 0, false, observation_failure(project, .Observation_Descriptors, .Persistent_Memory_Limit, 0, 0)
	}
	descriptors, descriptor_error := make([]Observation_Descriptor, len(state.entries), state.allocators.persistent)
	if descriptor_error != nil {
		free(batch_state, state.allocators.persistent)
		return {}, 0, false, observation_failure(project, .Observation_Descriptors, .Persistent_Memory_Limit, 0, 0)
	}
	for entry, index in state.entries {
		descriptors[index] = Observation_Descriptor {
			membership = entry.membership,
			availability = entry.availability,
			dirty = entry.dirty,
			config_present = entry.config_present,
		}
	}
	batch_state^ = Observation_Batch_State{descriptors = descriptors, allocator = state.allocators.persistent}
	return Observation_Batch{state = batch_state, descriptors = descriptors}, state.generation, true, {}
}

/* observation_batch_close releases one copied observation projection. */
observation_batch_close :: proc(batch: ^Observation_Batch) {
	if batch == nil || batch.state == nil {
		return
	}
	state := (^Observation_Batch_State)(batch.state)
	delete(state.descriptors, state.allocator)
	allocator := state.allocator
	free(state, allocator)
	batch^ = {}
}

/* observation_registry_close releases every retained path and invalidates the registry. */
observation_registry_close :: proc(registry: ^Observation_Registry) {
	if registry == nil || registry.state == nil {
		if registry != nil {
			registry.closed = true
		}
		return
	}
	observation_state_destroy((^Observation_State)(registry.state))
	registry^ = Observation_Registry{closed = true}
}

@(private)
observation_resolve :: proc(
	registry: ^Observation_Registry,
	project: Project_Handle,
	operation: Operation,
) -> (state: ^Observation_State, failure: Failure_Context) {
	if registry == nil || registry.state == nil {
		return nil, Failure_Context{code = .Invalid_Registry, operation = operation, project = project}
	}
	state = (^Observation_State)(registry.state)
	if registry.closed {
		return nil, Failure_Context{code = .Closed_Registry, operation = operation, project = project}
	}
	if project != state.project {
		return nil, Failure_Context{code = .Stale_Project, operation = operation, project = project}
	}
	return state, {}
}

@(private)
observation_find :: proc(state: ^Observation_State, membership: Membership_Handle) -> ^Observation_Entry {
	for &entry in state.entries {
		if entry.membership.id == membership.id {
			if entry.membership == membership {
				return &entry
			}
			return nil
		}
	}
	return nil
}

@(private)
observation_candidate_abort :: proc(state: ^Observation_State) {
	for &entry in state.entries {
		entry.candidate_ready = false
	}
	state.reconciling = false
	state.cursor = 0
}

@(private)
observation_state_destroy :: proc(state: ^Observation_State) {
	if state == nil {
		return
	}
	for entry in state.entries {
		delete(entry.path, state.allocators.persistent)
	}
	delete(state.entries)
	allocator := state.allocators.persistent
	free(state, allocator)
}

@(private)
observation_failure :: proc(
	project: Project_Handle,
	operation: Operation,
	code: Failure_Code,
	maximum, actual: u64,
) -> Failure_Context {
	return Failure_Context {
		code = code,
		operation = operation,
		project = project,
		maximum = maximum,
		actual = actual,
	}
}
