// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_computation

import "base:runtime"

@(private)
Configuration_State :: struct {
	descriptor: Configuration_Descriptor,
	adapters:   []Adapter_Record,
	policies:   []Policy_Record,
	arena:      []u8,
	allocator:  runtime.Allocator,
}

/* computation_configuration_init installs one immutable deny-first fallback generation. */
computation_configuration_init :: proc(
	configuration: ^Configuration,
	generation: Configuration_Generation,
	adapter_generation: Adapter_Generation,
	policy_generation: Policy_Generation,
	allocator := context.allocator,
) -> (bool, Failure) {
	if configuration == nil || configuration.state != nil ||
	   generation == Configuration_Generation(0) ||
	   adapter_generation == Adapter_Generation(0) ||
	   policy_generation == Policy_Generation(0) || allocator.procedure == nil {
		return false, computation_failure(.Configure, .Invalid_Request, .Generation)
	}
	state, allocation_error := new(Configuration_State, allocator)
	if allocation_error != nil {
		return false, computation_failure(.Configure, .Allocation_Failed, .Generation)
	}
	state^ = Configuration_State {
		descriptor = {
			generation = generation,
			adapter_generation = adapter_generation,
			policy_generation = policy_generation,
			factory_fallback = true,
		},
		allocator = allocator,
	}
	configuration.state = state
	return true, {}
}

/* computation_configuration_publish validates and swaps one complete copied generation. */
computation_configuration_publish :: proc(
	configuration: ^Configuration,
	candidate: Configuration_Candidate,
) -> (descriptor: Configuration_Descriptor, ok: bool, failure: Failure) {
	current := computation_configuration_state(configuration)
	if current == nil {
		return {}, false, computation_failure(.Configure, .Invalid_Request, .Generation)
	}
	if candidate.generation <= current.descriptor.generation ||
	   candidate.adapter_generation <= current.descriptor.adapter_generation ||
	   candidate.policy_generation <= current.descriptor.policy_generation {
		return current.descriptor, false, computation_failure(.Configure, .Stale, .Generation)
	}
	valid, text_bytes, invalid_failure := computation_configuration_candidate_validate(candidate)
	if !valid do return current.descriptor, false, invalid_failure
	next, copied := computation_configuration_copy(candidate, text_bytes, current.allocator)
	if !copied {
		return current.descriptor, false, computation_failure(.Configure, .Allocation_Failed, .Generation)
	}
	configuration.state = next
	computation_configuration_state_destroy(current)
	return next.descriptor, true, {}
}

/* computation_configuration_inspect copies current generation metadata. */
computation_configuration_inspect :: proc(configuration: ^Configuration) -> (Configuration_Descriptor, bool) {
	state := computation_configuration_state(configuration)
	if state == nil do return {}, false
	return state.descriptor, true
}

/* computation_configuration_adapter borrows one confirmed adapter until replacement. */
computation_configuration_adapter :: proc(configuration: ^Configuration, index: int) -> (Adapter_Record, bool) {
	state := computation_configuration_state(configuration)
	if state == nil || index < 0 || index >= len(state.adapters) do return {}, false
	return state.adapters[index], true
}

/* computation_configuration_policy borrows one confirmed policy until replacement. */
computation_configuration_policy :: proc(configuration: ^Configuration, index: int) -> (Policy_Record, bool) {
	state := computation_configuration_state(configuration)
	if state == nil || index < 0 || index >= len(state.policies) do return {}, false
	return state.policies[index], true
}

/* computation_configuration_close releases every copied configured value exactly. */
computation_configuration_close :: proc(configuration: ^Configuration) {
	if configuration == nil do return
	state := computation_configuration_state(configuration)
	if state != nil do computation_configuration_state_destroy(state)
	configuration.state = nil
}

@(private)
computation_configuration_candidate_validate :: proc(
	candidate: Configuration_Candidate,
) -> (valid: bool, text_bytes: u64, failure: Failure) {
	if candidate.generation == Configuration_Generation(0) ||
	   candidate.adapter_generation == Adapter_Generation(0) ||
	   candidate.policy_generation == Policy_Generation(0) ||
	   len(candidate.adapters) == 0 || len(candidate.policies) == 0 {
		return false, 0, computation_failure(.Configure, .Malformed, .Generation)
	}
	if len(candidate.adapters) > int(MAX_ADAPTERS) || len(candidate.policies) > int(MAX_POLICIES) {
		failure = computation_failure(.Configure, .Limited, .Limit)
		failure.limit = u64(MAX_POLICIES)
		failure.actual = u64(max(len(candidate.adapters), len(candidate.policies)))
		return false, 0, failure
	}
	for adapter, adapter_index in candidate.adapters {
		if !configuration_text_is_valid(adapter.identity, MAX_IDENTITY_BYTES) ||
		   !configuration_text_is_valid(adapter.language, MAX_IDENTITY_BYTES) ||
		   !configuration_text_is_valid(adapter.version, MAX_VERSION_BYTES) ||
		   adapter.class == .Invalid || !limits_are_valid(adapter.limits) {
			return false, text_bytes, computation_failure(.Configure, .Malformed, .Adapter)
		}
		for prior in candidate.adapters[:adapter_index] do if prior.identity == adapter.identity || prior.language == adapter.language {
			return false, text_bytes, computation_failure(.Configure, .Conflict, .Adapter)
		}
		text_bytes += u64(len(adapter.identity) + len(adapter.language) + len(adapter.version))
	}
	for policy, policy_index in candidate.policies {
		if !configuration_text_is_valid(policy.identity, MAX_IDENTITY_BYTES) ||
		   (len(policy.adapter) > 0 && !configuration_text_is_valid(policy.adapter, MAX_IDENTITY_BYTES)) ||
		   !configuration_text_is_valid(policy.language, MAX_IDENTITY_BYTES) ||
		   policy.origin == .Invalid || policy.interactive == .Invalid || policy.batch == .Invalid ||
		   policy.batch == .Confirm {
			return false, text_bytes, computation_failure(.Configure, .Malformed, .Policy)
		}
		for prior in candidate.policies[:policy_index] do if prior.identity == policy.identity {
			return false, text_bytes, computation_failure(.Configure, .Conflict, .Policy)
		}
		text_bytes += u64(len(policy.identity) + len(policy.adapter) + len(policy.language))
	}
	if text_bytes > MAX_CONFIGURATION_BYTES {
		failure = computation_failure(.Configure, .Limited, .Limit)
		failure.limit = MAX_CONFIGURATION_BYTES
		failure.actual = text_bytes
		return false, text_bytes, failure
	}
	return true, text_bytes, {}
}

@(private)
computation_configuration_copy :: proc(
	candidate: Configuration_Candidate,
	text_bytes: u64,
	allocator: runtime.Allocator,
) -> (state: ^Configuration_State, ok: bool) {
	allocation_error: runtime.Allocator_Error
	state, allocation_error = new(Configuration_State, allocator)
	if allocation_error != nil do return nil, false
	state^ = Configuration_State{allocator = allocator}
	state.adapters, allocation_error = make([]Adapter_Record, len(candidate.adapters), allocator)
	if allocation_error != nil do return computation_configuration_copy_failed(state)
	state.policies, allocation_error = make([]Policy_Record, len(candidate.policies), allocator)
	if allocation_error != nil do return computation_configuration_copy_failed(state)
	state.arena, allocation_error = make([]u8, int(text_bytes), allocator)
	if allocation_error != nil do return computation_configuration_copy_failed(state)
	cursor := 0
	for adapter, index in candidate.adapters {
		state.adapters[index] = {
			identity = computation_configuration_arena_copy(state.arena, &cursor, adapter.identity),
			language = computation_configuration_arena_copy(state.arena, &cursor, adapter.language),
			version = computation_configuration_arena_copy(state.arena, &cursor, adapter.version),
			class = adapter.class,
			in_process = adapter.in_process,
			runtime_required = adapter.runtime_required,
			limits = adapter.limits,
		}
	}
	for policy, index in candidate.policies {
		state.policies[index] = {
			identity = computation_configuration_arena_copy(state.arena, &cursor, policy.identity),
			adapter = computation_configuration_arena_copy(state.arena, &cursor, policy.adapter),
			language = computation_configuration_arena_copy(state.arena, &cursor, policy.language),
			origin = policy.origin,
			interactive = policy.interactive,
			batch = policy.batch,
			effects = policy.effects,
		}
	}
	assert(cursor == len(state.arena))
	state.descriptor = {
		generation = candidate.generation,
		adapter_generation = candidate.adapter_generation,
		policy_generation = candidate.policy_generation,
		adapter_count = u16(len(state.adapters)),
		policy_count = u16(len(state.policies)),
		retained_bytes = text_bytes + u64(size_of(Configuration_State)) +
		                 u64(len(state.adapters) * size_of(Adapter_Record)) +
		                 u64(len(state.policies) * size_of(Policy_Record)),
	}
	return state, true
}

@(private)
computation_configuration_arena_copy :: proc(arena: []u8, cursor: ^int, value: string) -> string {
	start := cursor^
	cursor^ += copy(arena[start:], value)
	return string(arena[start:cursor^])
}

@(private)
computation_configuration_copy_failed :: proc(state: ^Configuration_State) -> (^Configuration_State, bool) {
	computation_configuration_state_destroy(state)
	return nil, false
}

@(private)
computation_configuration_state :: proc(configuration: ^Configuration) -> ^Configuration_State {
	if configuration == nil || configuration.state == nil do return nil
	return (^Configuration_State)(configuration.state)
}

@(private)
computation_configuration_state_destroy :: proc(state: ^Configuration_State) {
	if state == nil do return
	allocator := state.allocator
	if state.adapters != nil do delete(state.adapters, allocator)
	if state.policies != nil do delete(state.policies, allocator)
	if state.arena != nil do delete(state.arena, allocator)
	free(state, allocator)
}

@(private)
computation_failure :: proc(kind: Operation_Kind, code: Failure_Code, field: Failure_Field) -> Failure {
	return {kind = kind, code = code, field = field}
}
