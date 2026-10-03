// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package interaction

/* profile_compatibility_policy_valid checks one non-zero bounded catalog policy. */
profile_compatibility_policy_valid :: proc(policy: Profile_Compatibility_Policy) -> bool {
	return policy.max_profiles > 0 && policy.max_profiles <= MAX_INTERACTION_PROFILES &&
		policy.max_states_per_profile > 0 &&
		policy.max_states_per_profile <= MAX_INTERACTION_STATES_PER_PROFILE &&
		policy.max_total_states > 0 && policy.max_total_states <= MAX_INTERACTION_STATES &&
		policy.max_shared_selectors > 0 &&
		policy.max_shared_selectors <= MAX_SHARED_BINDING_SELECTORS &&
		policy.max_total_selectors > 0 &&
		policy.max_total_selectors <= MAX_PROFILE_BINDING_SELECTORS &&
		policy.max_command_entry_surfaces > 0 &&
		policy.max_command_entry_surfaces <= MAX_COMMAND_ENTRY_SURFACES &&
		policy.max_catalog_bytes > 0 && policy.max_catalog_bytes <= MAX_PROFILE_CATALOG_BYTES
}

/* interaction_state_definition_valid checks one borrowed state contract. */
interaction_state_definition_valid :: proc(
	definition: Interaction_State_Definition,
) -> bool {
	return definition.identity.id != Interaction_State_ID(0) &&
		definition.identity.revision != Interaction_State_Revision(0) &&
		valid_bounded_text(definition.name, MAX_IDENTITY_BYTES, false) &&
		provenance_valid(definition.provenance)
}

/* command_entry_surface_definition_valid checks one borrowed surface contract. */
command_entry_surface_definition_valid :: proc(
	definition: Command_Entry_Surface_Definition,
) -> bool {
	return definition.identity.id != Command_Entry_Surface_ID(0) &&
		definition.identity.revision != Command_Entry_Surface_Revision(0) &&
		valid_bounded_text(definition.name, MAX_IDENTITY_BYTES, false) &&
		provenance_valid(definition.provenance)
}

/* interaction_state_admits returns whether one state accepts every declared effect. */
interaction_state_admits :: proc(
	state: Interaction_State_Definition,
	effects: Command_Effects,
) -> bool {
	for effect in Command_Effect {
		if effect in effects && effect not_in state.admitted_effects do return false
	}
	return true
}

/* profile_catalog_definition_validate checks structural compatibility before ownership. */
profile_catalog_definition_validate :: proc(
	definition: Profile_Catalog_Definition,
	policy := DEFAULT_PROFILE_COMPATIBILITY_POLICY,
) -> (usage: Profile_Compatibility_Usage, failure: Failure_Context) {
	if !profile_compatibility_policy_valid(policy) {
		return {}, Failure_Context{code = .Invalid_Profile_Catalog}
	}
	if definition.generation == Profile_Catalog_Generation(0) ||
	   len(definition.profiles) == 0 {
		return {}, Failure_Context {
			code = .Invalid_Profile_Catalog,
			catalog_generation = definition.generation,
		}
	}
	if len(definition.profiles) > int(policy.max_profiles) {
		return {}, Failure_Context {
			code = .Profile_Catalog_Limit,
			catalog_generation = definition.generation,
			limit = u64(policy.max_profiles),
			actual = u64(len(definition.profiles)),
		}
	}
	if len(definition.surfaces) == 0 ||
	   len(definition.surfaces) > int(policy.max_command_entry_surfaces) {
		return {}, Failure_Context {
			code = .Command_Entry_Surface_Limit,
			catalog_generation = definition.generation,
			limit = u64(policy.max_command_entry_surfaces),
			actual = u64(len(definition.surfaces)),
		}
	}

	active_profile_found := false
	active_state_found := false
	for profile, profile_index in definition.profiles {
		if !profile_identity_valid(profile.identity) ||
		   !valid_bounded_text(profile.name, MAX_IDENTITY_BYTES, false) {
			return {}, Failure_Context {
				code = .Invalid_Profile,
				catalog_generation = definition.generation,
				profile = profile.identity,
			}
		}
		for prior in definition.profiles[:profile_index] {
			if prior.identity.id == profile.identity.id {
				return {}, Failure_Context {
					code = .Invalid_Profile,
					catalog_generation = definition.generation,
					profile = profile.identity,
				}
			}
		}
		if len(profile.states) == 0 || len(profile.states) > int(policy.max_states_per_profile) {
			return {}, Failure_Context {
				code = .Interaction_State_Limit,
				catalog_generation = definition.generation,
				profile = profile.identity,
				limit = u64(policy.max_states_per_profile),
				actual = u64(len(profile.states)),
			}
		}
		usage.state_count += u16(len(profile.states))
		if usage.state_count > policy.max_total_states {
			return {}, Failure_Context {
				code = .Interaction_State_Limit,
				catalog_generation = definition.generation,
				limit = u64(policy.max_total_states),
				actual = u64(usage.state_count),
			}
		}
		initial_found := false
		for state, state_index in profile.states {
			if !interaction_state_definition_valid(state) {
				return {}, Failure_Context {
					code = .Invalid_Interaction_State,
					catalog_generation = definition.generation,
					profile = profile.identity,
					state = state.identity,
				}
			}
			for prior in profile.states[:state_index] {
				if prior.identity.id == state.identity.id {
					return {}, Failure_Context {
						code = .Invalid_Interaction_State,
						catalog_generation = definition.generation,
						profile = profile.identity,
						state = state.identity,
					}
				}
			}
			if state.identity.id == profile.initial_state do initial_found = true
			if profile.identity.id == definition.active_profile &&
			   state.identity.id == definition.active_state {
				active_state_found = true
			}
		}
		if !initial_found {
			return {}, Failure_Context {
				code = .Invalid_Interaction_State,
				catalog_generation = definition.generation,
				profile = profile.identity,
				state = {id = profile.initial_state},
			}
		}
		if profile.identity.id == definition.active_profile do active_profile_found = true

		for map_definition in profile.maps {
			for binding in map_definition.bindings {
				usage.scoped_binding_count += 1
				scope_failure := profile_binding_scope_validate(
					definition,
					profile.identity,
					binding,
					policy,
				)
				if scope_failure.code != .None do return {}, scope_failure
				usage.shared_selector_count += u32(len(binding.selectors))
				if usage.shared_selector_count > policy.max_total_selectors {
					return {}, Failure_Context {
						code = .Shared_Selector_Limit,
						catalog_generation = definition.generation,
						profile = profile.identity,
						binding_scope = binding.scope,
						limit = u64(policy.max_total_selectors),
						actual = u64(usage.shared_selector_count),
					}
				}
			}
		}
	}
	if !active_profile_found || !active_state_found {
		return {}, Failure_Context {
			code = .Invalid_Interaction_State,
			catalog_generation = definition.generation,
			profile = {id = definition.active_profile},
			state = {id = definition.active_state},
		}
	}

	for surface, surface_index in definition.surfaces {
		if !command_entry_surface_definition_valid(surface) {
			return {}, Failure_Context {
				code = .Invalid_Command_Entry_Surface,
				catalog_generation = definition.generation,
				command_entry_surface = surface.identity,
			}
		}
		for prior in definition.surfaces[:surface_index] {
			if prior.identity.id == surface.identity.id {
				return {}, Failure_Context {
					code = .Invalid_Command_Entry_Surface,
					catalog_generation = definition.generation,
					command_entry_surface = surface.identity,
				}
			}
		}
	}
	usage.profile_count = u16(len(definition.profiles))
	usage.command_entry_surface_count = u16(len(definition.surfaces))
	usage.definition_bytes = profile_catalog_definition_bytes(definition)
	if usage.definition_bytes > policy.max_catalog_bytes {
		return {}, Failure_Context {
			code = .Profile_Catalog_Memory_Limit,
			catalog_generation = definition.generation,
			limit = policy.max_catalog_bytes,
			actual = usage.definition_bytes,
		}
	}
	return usage, {}
}

@(private)
profile_binding_scope_validate :: proc(
	catalog: Profile_Catalog_Definition,
	owner: Profile_Identity,
	binding: Layered_Binding_Definition,
	policy: Profile_Compatibility_Policy,
) -> Failure_Context {
	switch binding.scope {
	case .Protected_Recovery:
		if len(binding.selectors) != 0 || len(binding.protection_reason) == 0 {
			return Failure_Context {
				code = .Invalid_Binding_Scope,
				catalog_generation = catalog.generation,
				profile = owner,
				binding_scope = binding.scope,
			}
		}
	case .Profile_Specific:
		if len(binding.selectors) != 0 {
			return Failure_Context {
				code = .Invalid_Binding_Scope,
				catalog_generation = catalog.generation,
				profile = owner,
				binding_scope = binding.scope,
			}
		}
	case .State_Specific:
		if len(binding.selectors) == 0 || len(binding.selectors) > int(policy.max_shared_selectors) {
			return Failure_Context {
				code = .Shared_Selector_Limit,
				catalog_generation = catalog.generation,
				profile = owner,
				binding_scope = binding.scope,
				limit = u64(policy.max_shared_selectors),
				actual = u64(len(binding.selectors)),
			}
		}
		for selector, selector_index in binding.selectors {
			if selector.profile_id != owner.id || !profile_state_selector_exists(catalog, selector) {
				return Failure_Context {
					code = .Invalid_Shared_Selector,
					catalog_generation = catalog.generation,
					profile = owner,
					state = {id = selector.state_id},
					binding_scope = binding.scope,
					selector_index = u32(selector_index),
				}
			}
			for prior in binding.selectors[:selector_index] {
				if prior == selector {
					return Failure_Context {
						code = .Invalid_Shared_Selector,
						catalog_generation = catalog.generation,
						profile = owner,
						state = {id = selector.state_id},
						binding_scope = binding.scope,
						selector_index = u32(selector_index),
					}
				}
			}
		}
	case .Shared_Continuity:
		if len(binding.selectors) == 0 || len(binding.selectors) > int(policy.max_shared_selectors) {
			return Failure_Context {
				code = .Shared_Selector_Limit,
				catalog_generation = catalog.generation,
				profile = owner,
				binding_scope = binding.scope,
				limit = u64(policy.max_shared_selectors),
				actual = u64(len(binding.selectors)),
			}
		}
		for selector, selector_index in binding.selectors {
			if !profile_state_selector_exists(catalog, selector) {
				return Failure_Context {
					code = .Invalid_Shared_Selector,
					catalog_generation = catalog.generation,
					profile = {id = selector.profile_id},
					state = {id = selector.state_id},
					binding_scope = binding.scope,
					selector_index = u32(selector_index),
				}
			}
			for prior in binding.selectors[:selector_index] {
				if prior == selector {
					return Failure_Context {
						code = .Invalid_Shared_Selector,
						catalog_generation = catalog.generation,
						profile = {id = selector.profile_id},
						state = {id = selector.state_id},
						binding_scope = binding.scope,
						selector_index = u32(selector_index),
					}
				}
			}
		}
	case .Invalid:
		return Failure_Context {
			code = .Invalid_Binding_Scope,
			catalog_generation = catalog.generation,
			profile = owner,
			binding_scope = binding.scope,
		}
	}
	return {}
}

@(private)
profile_state_selector_exists :: proc(
	catalog: Profile_Catalog_Definition,
	selector: Profile_State_Selector,
) -> bool {
	if selector.profile_id == Profile_ID(0) || selector.state_id == Interaction_State_ID(0) {
		return false
	}
	for profile in catalog.profiles {
		if profile.identity.id != selector.profile_id do continue
		for state in profile.states {
			if state.identity.id == selector.state_id do return true
		}
	}
	return false
}

@(private)
profile_catalog_definition_bytes :: proc(definition: Profile_Catalog_Definition) -> u64 {
	bytes := u64(size_of(Profile_Catalog_Definition))
	bytes += u64(len(definition.profiles) * size_of(Profile_Definition))
	bytes += u64(len(definition.surfaces) * size_of(Command_Entry_Surface_Definition))
	for profile in definition.profiles {
		bytes += u64(len(profile.name) + len(profile.text_fallback_name))
		bytes += u64(len(profile.states) * size_of(Interaction_State_Definition))
		bytes += u64(len(profile.maps) * size_of(Map_Definition))
		for state in profile.states {
			bytes += u64(len(state.name)) + provenance_bytes(state.provenance)
		}
		for map_definition in profile.maps {
			bytes += u64(len(map_definition.name)) + provenance_bytes(map_definition.provenance)
			bytes += u64(len(map_definition.bindings) * size_of(Layered_Binding_Definition))
			bytes += u64(len(map_definition.remaps) * size_of(Command_Remap_Definition))
			bytes += u64(len(map_definition.ordering_constraints) * size_of(Ordering_Constraint))
			for binding in map_definition.bindings {
				bytes += u64(len(binding.selectors) * size_of(Profile_State_Selector))
				bytes += u64(len(binding.command_name) + len(binding.protection_reason))
				bytes += provenance_bytes(binding.provenance)
			}
			for remap in map_definition.remaps {
				bytes += u64(len(remap.from_command_name) + len(remap.to_command_name))
				bytes += provenance_bytes(remap.provenance)
			}
		}
	}
	for surface in definition.surfaces {
		bytes += u64(len(surface.name)) + provenance_bytes(surface.provenance)
	}
	return bytes
}
