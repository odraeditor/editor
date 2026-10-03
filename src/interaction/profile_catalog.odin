// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package interaction

import "base:runtime"

@(private)
Profile_Catalog_State :: struct {
	definition: Profile_Catalog_Definition,
	profiles:   []Profile_Definition,
	states:     []Interaction_State_Definition,
	maps:       []Map_Definition,
	bindings:   []Layered_Binding_Definition,
	selectors:  []Profile_State_Selector,
	surfaces:   []Command_Entry_Surface_Definition,
	remaps:     []Command_Remap_Definition,
	ordering:   []Ordering_Constraint,
	text:       []u8,
	usage:      Profile_Compatibility_Usage,
	allocator:  runtime.Allocator,
}

@(private)
Profile_Catalog_Capacities :: struct {
	states:    int,
	maps:      int,
	bindings:  int,
	selectors: int,
	remaps:    int,
	ordering:  int,
	text:      int,
}

/* profile_catalog_build validates and privately copies one immutable catalog. */
profile_catalog_build :: proc(
	registry: ^Command_Registry,
	definition: Profile_Catalog_Definition,
	policy := DEFAULT_PROFILE_COMPATIBILITY_POLICY,
	allocator := context.allocator,
) -> (catalog: Profile_Catalog, ok: bool, failure: Failure_Context) {
	usage, validation_failure := profile_catalog_validate(registry, definition, policy)
	if validation_failure.code != .None {
		return {}, false, validation_failure
	}
	if allocator.procedure == nil {
		return {}, false, Failure_Context {
			code = .Persistent_Memory_Limit,
			catalog_generation = definition.generation,
		}
	}

	capacities := profile_catalog_capacities(definition)
	owner, allocation_error := new(Profile_Catalog_State, allocator)
	if allocation_error != nil {
		return {}, false, profile_catalog_allocation_failure(definition.generation)
	}
	owner.allocator = allocator

	owner.profiles, allocation_error = make([]Profile_Definition, len(definition.profiles), allocator)
	if allocation_error != nil {
		profile_catalog_state_destroy(owner)
		return {}, false, profile_catalog_allocation_failure(definition.generation)
	}
	if capacities.states > 0 {
		owner.states, allocation_error = make([]Interaction_State_Definition, capacities.states, allocator)
		if allocation_error != nil {
			profile_catalog_state_destroy(owner)
			return {}, false, profile_catalog_allocation_failure(definition.generation)
		}
	}
	if capacities.maps > 0 {
		owner.maps, allocation_error = make([]Map_Definition, capacities.maps, allocator)
		if allocation_error != nil {
			profile_catalog_state_destroy(owner)
			return {}, false, profile_catalog_allocation_failure(definition.generation)
		}
	}
	if capacities.bindings > 0 {
		owner.bindings, allocation_error = make([]Layered_Binding_Definition, capacities.bindings, allocator)
		if allocation_error != nil {
			profile_catalog_state_destroy(owner)
			return {}, false, profile_catalog_allocation_failure(definition.generation)
		}
	}
	if capacities.selectors > 0 {
		owner.selectors, allocation_error = make([]Profile_State_Selector, capacities.selectors, allocator)
		if allocation_error != nil {
			profile_catalog_state_destroy(owner)
			return {}, false, profile_catalog_allocation_failure(definition.generation)
		}
	}
	owner.surfaces, allocation_error = make(
		[]Command_Entry_Surface_Definition,
		len(definition.surfaces),
		allocator,
	)
	if allocation_error != nil {
		profile_catalog_state_destroy(owner)
		return {}, false, profile_catalog_allocation_failure(definition.generation)
	}
	if capacities.remaps > 0 {
		owner.remaps, allocation_error = make([]Command_Remap_Definition, capacities.remaps, allocator)
		if allocation_error != nil {
			profile_catalog_state_destroy(owner)
			return {}, false, profile_catalog_allocation_failure(definition.generation)
		}
	}
	if capacities.ordering > 0 {
		owner.ordering, allocation_error = make([]Ordering_Constraint, capacities.ordering, allocator)
		if allocation_error != nil {
			profile_catalog_state_destroy(owner)
			return {}, false, profile_catalog_allocation_failure(definition.generation)
		}
	}
	owner.text, allocation_error = make([]u8, capacities.text, allocator)
	if allocation_error != nil {
		profile_catalog_state_destroy(owner)
		return {}, false, profile_catalog_allocation_failure(definition.generation)
	}

	profile_catalog_copy_definition(owner, definition)
	retained_bytes := u64(size_of(Profile_Catalog_State)) +
		u64(len(owner.profiles) * size_of(Profile_Definition)) +
		u64(len(owner.states) * size_of(Interaction_State_Definition)) +
		u64(len(owner.maps) * size_of(Map_Definition)) +
		u64(len(owner.bindings) * size_of(Layered_Binding_Definition)) +
		u64(len(owner.selectors) * size_of(Profile_State_Selector)) +
		u64(len(owner.surfaces) * size_of(Command_Entry_Surface_Definition)) +
		u64(len(owner.remaps) * size_of(Command_Remap_Definition)) +
		u64(len(owner.ordering) * size_of(Ordering_Constraint)) +
		u64(len(owner.text))
	usage.retained_bytes = retained_bytes
	usage.temporary_peak_bytes = retained_bytes
	owner.usage = usage
	return Profile_Catalog{state = owner}, true, {}
}

/* profile_catalog_definition borrows the immutable owned definition until close. */
profile_catalog_definition :: proc(
	catalog: ^Profile_Catalog,
) -> (definition: Profile_Catalog_Definition, ok: bool) {
	state := profile_catalog_state(catalog)
	if state == nil {
		return {}, false
	}
	return state.definition, true
}

/* profile_catalog_usage reports exact copied definition and retained storage. */
profile_catalog_usage :: proc(
	catalog: ^Profile_Catalog,
) -> (usage: Profile_Compatibility_Usage, ok: bool) {
	state := profile_catalog_state(catalog)
	if state == nil {
		return {}, false
	}
	return state.usage, true
}

/* profile_catalog_close deterministically releases one immutable catalog owner. */
profile_catalog_close :: proc(catalog: ^Profile_Catalog) -> bool {
	state := profile_catalog_state(catalog)
	if state == nil {
		return false
	}
	profile_catalog_state_destroy(state)
	catalog.state = nil
	catalog.closed = true
	return true
}

@(private)
profile_catalog_validate :: proc(
	registry: ^Command_Registry,
	definition: Profile_Catalog_Definition,
	policy: Profile_Compatibility_Policy,
) -> (usage: Profile_Compatibility_Usage, failure: Failure_Context) {
	usage, failure = profile_catalog_definition_validate(definition, policy)
	if failure.code != .None {
		return usage, failure
	}
	registry_state := registry_data(registry)
	if registry_state == nil || registry_state.state != .Ready {
		return usage, registry_failure(registry, .Invalid_Registry)
	}

	for profile in definition.profiles {
		fallback, fallback_ok, _ := lookup_command_data(registry_state, profile.text_fallback_name)
		if !fallback_ok {
			return usage, Failure_Context {
				code = .Unknown_Command,
				registry_generation = registry_state.generation,
				catalog_generation = definition.generation,
				profile = profile.identity,
			}
		}
		fallback_entry, fallback_resolved := resolve_command(registry_state, fallback)
		if !fallback_resolved || fallback_entry.invocation != .Text_Input {
			return usage, Failure_Context {
				code = .Invalid_Text_Fallback,
				registry_generation = registry_state.generation,
				catalog_generation = definition.generation,
				profile = profile.identity,
				command = fallback,
			}
		}
		if len(profile.maps) == 0 || len(profile.maps) > MAX_MAPS {
			return usage, Failure_Context {
				code = .Map_Limit,
				catalog_generation = definition.generation,
				profile = profile.identity,
				limit = MAX_MAPS,
				actual = u64(len(profile.maps)),
			}
		}
		ordered: [MAX_MAPS]int
		_, ordering_failure := order_profile_maps(profile.maps, ordered[:len(profile.maps)])
		if ordering_failure.code != .None {
			ordering_failure.catalog_generation = definition.generation
			ordering_failure.profile = profile.identity
			return usage, ordering_failure
		}
		protected_catalog := protected_binding_catalog()
		protected_failure := validate_external_protected_conflicts(
			profile.maps,
			protected_catalog[:],
		)
		if protected_failure.code != .None {
			protected_failure.catalog_generation = definition.generation
			protected_failure.profile = profile.identity
			return usage, protected_failure
		}
		for map_definition in profile.maps {
			if !valid_bounded_text(map_definition.name, MAX_IDENTITY_BYTES, false) ||
			   map_definition.precedence == .Invalid ||
			   map_definition.unmatched_input_policy == .Invalid ||
			   !provenance_valid(map_definition.provenance) {
				return usage, Failure_Context {
					code = .Invalid_Map,
					catalog_generation = definition.generation,
					profile = profile.identity,
					map_identity = map_definition.identity,
				}
			}
			if len(map_definition.bindings) > MAX_BINDINGS_PER_MAP {
				return usage, Failure_Context {
					code = .Map_Binding_Limit,
					catalog_generation = definition.generation,
					profile = profile.identity,
					map_identity = map_definition.identity,
					limit = MAX_BINDINGS_PER_MAP,
					actual = u64(len(map_definition.bindings)),
				}
			}
			for binding, binding_index in map_definition.bindings {
				binding_failure := profile_catalog_binding_validate(
					registry_state,
					definition,
					profile.identity,
					map_definition.identity,
					binding,
					u32(binding_index),
				)
				if binding_failure.code != .None {
					return usage, binding_failure
				}
			}
			for remap, remap_index in map_definition.remaps {
				from, from_ok, _ := lookup_command_data(registry_state, remap.from_command_name)
				to, to_ok, _ := lookup_command_data(registry_state, remap.to_command_name)
				if !from_ok || !to_ok || from == to || !provenance_valid(remap.provenance) {
					return usage, Failure_Context {
						code = .Invalid_Remap,
						registry_generation = registry_state.generation,
						catalog_generation = definition.generation,
						profile = profile.identity,
						map_identity = map_definition.identity,
						binding_index = u32(remap_index),
					}
				}
			}
		}
	}
	return usage, {}
}

@(private)
profile_catalog_binding_validate :: proc(
	registry: ^Registry_Data,
	definition: Profile_Catalog_Definition,
	profile: Profile_Identity,
	map_identity: Map_Identity,
	binding: Layered_Binding_Definition,
	binding_index: u32,
) -> Failure_Context {
	failure := Failure_Context {
		registry_generation = registry.generation,
		catalog_generation = definition.generation,
		profile = profile,
		map_identity = map_identity,
		binding_index = binding_index,
		binding_scope = binding.scope,
	}
	if !sequence_valid(binding.sequence) {
		failure.code = .Sequence_Limit
		failure.limit = MAX_SEQUENCE_STROKES
		failure.actual = u64(binding.sequence.stroke_count)
		return failure
	}
	if !provenance_valid(binding.provenance) {
		failure.code = .Invalid_Provenance
		return failure
	}
	if binding.scope == .Protected_Recovery {
		failure.code = .Protected_Binding
		return failure
	}

	switch binding.operation {
	case .Bind, .Replace:
		command, command_ok, _ := lookup_command_data(registry, binding.command_name)
		if !command_ok {
			failure.code = .Unknown_Command
			return failure
		}
		failure.command = command
		if binding.scope == .Shared_Continuity || binding.scope == .State_Specific {
			metadata, metadata_ok := resolve_command(registry, command)
			if !metadata_ok {
				failure.code = .Invalid_Command
				return failure
			}
			for selector, selector_index in binding.selectors {
				state, state_ok := profile_catalog_state_definition(definition, selector)
				if !state_ok || !interaction_state_admits(state, metadata.effects) {
					failure.code = .Incompatible_Shared_Binding
					failure.profile = {id = selector.profile_id}
					failure.state = state.identity
					if !state_ok {
						failure.state = {id = selector.state_id}
					}
					failure.selector_index = u32(selector_index)
					return failure
				}
			}
		}
	case .Unbind, .Mask:
		if len(binding.command_name) != 0 {
			failure.code = .Invalid_Operation
			return failure
		}
	case .Invalid:
		failure.code = .Invalid_Operation
		return failure
	}
	return {}
}

@(private)
profile_catalog_state_definition :: proc(
	definition: Profile_Catalog_Definition,
	selector: Profile_State_Selector,
) -> (state: Interaction_State_Definition, ok: bool) {
	for profile in definition.profiles {
		if profile.identity.id != selector.profile_id {
			continue
		}
		for candidate in profile.states {
			if candidate.identity.id == selector.state_id {
				return candidate, true
			}
		}
	}
	return {}, false
}

@(private)
profile_catalog_capacities :: proc(
	definition: Profile_Catalog_Definition,
) -> Profile_Catalog_Capacities {
	result: Profile_Catalog_Capacities
	for profile in definition.profiles {
		result.states += len(profile.states)
		result.maps += len(profile.maps)
		result.text += len(profile.name) + len(profile.text_fallback_name)
		for state in profile.states {
			result.text += len(state.name) + profile_catalog_provenance_text_bytes(state.provenance)
		}
		for map_definition in profile.maps {
			result.bindings += len(map_definition.bindings)
			result.remaps += len(map_definition.remaps)
			result.ordering += len(map_definition.ordering_constraints)
			result.text += len(map_definition.name) +
				profile_catalog_provenance_text_bytes(map_definition.provenance)
			for binding in map_definition.bindings {
				result.selectors += len(binding.selectors)
				result.text += len(binding.command_name) + len(binding.protection_reason) +
					profile_catalog_provenance_text_bytes(binding.provenance)
			}
			for remap in map_definition.remaps {
				result.text += len(remap.from_command_name) + len(remap.to_command_name) +
					profile_catalog_provenance_text_bytes(remap.provenance)
			}
		}
	}
	for surface in definition.surfaces {
		result.text += len(surface.name) + profile_catalog_provenance_text_bytes(surface.provenance)
	}
	return result
}

@(private)
profile_catalog_copy_definition :: proc(
	owner: ^Profile_Catalog_State,
	definition: Profile_Catalog_Definition,
) {
	state_offset, map_offset, binding_offset := 0, 0, 0
	selector_offset, remap_offset, ordering_offset, text_offset := 0, 0, 0, 0
	for source_profile, profile_index in definition.profiles {
		target_profile := &owner.profiles[profile_index]
		target_profile.identity = source_profile.identity
		target_profile.name, text_offset = profile_catalog_copy_text(owner.text, text_offset, source_profile.name)
		target_profile.initial_state = source_profile.initial_state
		target_profile.text_fallback_name, text_offset = profile_catalog_copy_text(
			owner.text,
			text_offset,
			source_profile.text_fallback_name,
		)
		target_profile.states = owner.states[state_offset:state_offset + len(source_profile.states)]
		for source_state, state_index in source_profile.states {
			target_state := &target_profile.states[state_index]
			target_state.identity = source_state.identity
			target_state.admits_text_input = source_state.admits_text_input
			target_state.admitted_effects = source_state.admitted_effects
			target_state.name, text_offset = profile_catalog_copy_text(owner.text, text_offset, source_state.name)
			target_state.provenance, text_offset = profile_catalog_copy_provenance(
				owner.text,
				text_offset,
				source_state.provenance,
			)
		}
		state_offset += len(source_profile.states)
		target_profile.maps = owner.maps[map_offset:map_offset + len(source_profile.maps)]
		for source_map, map_index in source_profile.maps {
			target_map := &target_profile.maps[map_index]
			target_map.identity = source_map.identity
			target_map.owner = source_map.owner
			target_map.precedence = source_map.precedence
			target_map.priority = source_map.priority
			target_map.context_requirement = source_map.context_requirement
			target_map.unmatched_input_policy = source_map.unmatched_input_policy
			target_map.name, text_offset = profile_catalog_copy_text(owner.text, text_offset, source_map.name)
			target_map.provenance, text_offset = profile_catalog_copy_provenance(
				owner.text,
				text_offset,
				source_map.provenance,
			)
			target_map.bindings = owner.bindings[
				binding_offset:binding_offset + len(source_map.bindings)
			]
			for source_binding, source_binding_index in source_map.bindings {
				target_binding := &target_map.bindings[source_binding_index]
				target_binding.sequence = source_binding.sequence
				target_binding.operation = source_binding.operation
				target_binding.scope = source_binding.scope
				target_binding.command_name, text_offset = profile_catalog_copy_text(
					owner.text,
					text_offset,
					source_binding.command_name,
				)
				target_binding.protection_reason, text_offset = profile_catalog_copy_text(
					owner.text,
					text_offset,
					source_binding.protection_reason,
				)
				target_binding.provenance, text_offset = profile_catalog_copy_provenance(
					owner.text,
					text_offset,
					source_binding.provenance,
				)
				target_binding.selectors = owner.selectors[
					selector_offset:selector_offset + len(source_binding.selectors)
				]
				copy(target_binding.selectors, source_binding.selectors)
				selector_offset += len(source_binding.selectors)
			}
			binding_offset += len(source_map.bindings)
			target_map.remaps = owner.remaps[remap_offset:remap_offset + len(source_map.remaps)]
			for source_remap, source_remap_index in source_map.remaps {
				target_remap := &target_map.remaps[source_remap_index]
				target_remap.from_command_name, text_offset = profile_catalog_copy_text(
					owner.text,
					text_offset,
					source_remap.from_command_name,
				)
				target_remap.to_command_name, text_offset = profile_catalog_copy_text(
					owner.text,
					text_offset,
					source_remap.to_command_name,
				)
				target_remap.provenance, text_offset = profile_catalog_copy_provenance(
					owner.text,
					text_offset,
					source_remap.provenance,
				)
			}
			remap_offset += len(source_map.remaps)
			target_map.ordering_constraints = owner.ordering[
				ordering_offset:ordering_offset + len(source_map.ordering_constraints)
			]
			copy(target_map.ordering_constraints, source_map.ordering_constraints)
			ordering_offset += len(source_map.ordering_constraints)
		}
		map_offset += len(source_profile.maps)
	}
	for source_surface, surface_index in definition.surfaces {
		target_surface := &owner.surfaces[surface_index]
		target_surface.identity = source_surface.identity
		target_surface.name, text_offset = profile_catalog_copy_text(owner.text, text_offset, source_surface.name)
		target_surface.provenance, text_offset = profile_catalog_copy_provenance(
			owner.text,
			text_offset,
			source_surface.provenance,
		)
	}
	assert(state_offset == len(owner.states))
	assert(map_offset == len(owner.maps))
	assert(binding_offset == len(owner.bindings))
	assert(selector_offset == len(owner.selectors))
	assert(remap_offset == len(owner.remaps))
	assert(ordering_offset == len(owner.ordering))
	assert(text_offset == len(owner.text))
	owner.definition = Profile_Catalog_Definition {
		generation = definition.generation,
		profiles = owner.profiles,
		active_profile = definition.active_profile,
		active_state = definition.active_state,
		surfaces = owner.surfaces,
	}
}

@(private)
profile_catalog_copy_provenance :: proc(
	storage: []u8,
	offset: int,
	provenance: Definition_Provenance,
) -> (result: Definition_Provenance, next_offset: int) {
	next_offset = offset
	result.provider, next_offset = profile_catalog_copy_text(storage, next_offset, provenance.provider)
	result.source, next_offset = profile_catalog_copy_text(storage, next_offset, provenance.source)
	result.location, next_offset = profile_catalog_copy_text(storage, next_offset, provenance.location)
	return result, next_offset
}

@(private)
profile_catalog_copy_text :: proc(storage: []u8, offset: int, value: string) -> (string, int) {
	copy(storage[offset:], transmute([]u8)value)
	return string(storage[offset:offset + len(value)]), offset + len(value)
}

@(private)
profile_catalog_provenance_text_bytes :: proc(provenance: Definition_Provenance) -> int {
	return len(provenance.provider) + len(provenance.source) + len(provenance.location)
}

@(private)
profile_catalog_allocation_failure :: proc(
	generation: Profile_Catalog_Generation,
) -> Failure_Context {
	return Failure_Context {
		code = .Persistent_Memory_Limit,
		catalog_generation = generation,
	}
}

@(private)
profile_catalog_state :: proc(catalog: ^Profile_Catalog) -> ^Profile_Catalog_State {
	if catalog == nil || catalog.state == nil || catalog.closed {
		return nil
	}
	return (^Profile_Catalog_State)(catalog.state)
}

@(private)
profile_catalog_state_destroy :: proc(state: ^Profile_Catalog_State) {
	if state == nil {
		return
	}
	allocator := state.allocator
	if state.text != nil do delete(state.text, allocator)
	if state.ordering != nil do delete(state.ordering, allocator)
	if state.remaps != nil do delete(state.remaps, allocator)
	if state.surfaces != nil do delete(state.surfaces, allocator)
	if state.selectors != nil do delete(state.selectors, allocator)
	if state.bindings != nil do delete(state.bindings, allocator)
	if state.maps != nil do delete(state.maps, allocator)
	if state.states != nil do delete(state.states, allocator)
	if state.profiles != nil do delete(state.profiles, allocator)
	free(state, allocator)
}
