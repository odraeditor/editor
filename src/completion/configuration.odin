// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package completion

/* Factory_Configuration selects one complete named composition and bounded policy. */
Factory_Configuration :: struct {
	enabled:      bool,
	provider:     Name,
	policy:       Name,
	presentation: Name,
	session:      Session_Policy,
	limits:       Limits,
}

/* factory_configuration returns the maintained language completion composition. */
factory_configuration :: proc() -> Factory_Configuration {
	provider, provider_ok := name_copy("language-service")
	policy, policy_ok := name_copy("factory-completion")
	presentation, presentation_ok := name_copy("interactive-candidate")
	assert(provider_ok && policy_ok && presentation_ok)
	return {
		enabled = true,
		provider = provider,
		policy = policy,
		presentation = presentation,
		session = DEFAULT_SESSION_POLICY,
		limits = DEFAULT_LIMITS,
	}
}

/* factory_configuration_is_valid validates one complete named bounded configuration. */
factory_configuration_is_valid :: proc(configuration: Factory_Configuration) -> bool {
	return configuration.provider.byte_count > 0 && configuration.policy.byte_count > 0 &&
		configuration.presentation.byte_count > 0 &&
		session_policy_is_valid(configuration.session) && limits_are_valid(configuration.limits)
}

/* registry_configure atomically selects one complete compatible named composition. */
registry_configure :: proc(
	registry: ^Role_Registry,
	expected: Composition_Scope,
	configuration: Factory_Configuration,
) -> (Composition_Scope, bool, Failure) {
	state := registry_state(registry)
	if state == nil {
		return {}, false, failure(.Select, .Invalid_Registry)
	}
	if !registry_scope_matches(state, expected) {
		return {}, false, registry_reject(state, failure(.Select, .Stale_Scope))
	}
	if !factory_configuration_is_valid(configuration) {
		return {}, false, registry_reject(state, failure(.Select, .Invalid_State))
	}
	if !configuration.enabled {
		return registry_disable(registry, expected)
	}

	names := [MAX_COMPLETION_ROLES]Name {
		configuration.provider,
		configuration.policy,
		configuration.presentation,
	}
	selected: [MAX_COMPLETION_ROLES]Implementation_Record
	for role_value in 1 ..= MAX_COMPLETION_ROLES {
		role := Role(role_value)
		found := false
		for slot in state.implementations {
			slot_name := slot.record.definition.name
			if slot.live && slot.record.definition.role == role &&
			   name_view(&slot_name) == name_view(&names[role_value - 1]) {
				selected[role_value - 1] = slot.record
				found = true
				break
			}
		}
		if !found {
			return {}, false, registry_reject(
				state,
				failure(.Select, .Stale_Implementation, role),
			)
		}
	}

	changed := !state.enabled
	for index in 0 ..< MAX_COMPLETION_ROLES {
		changed = changed || state.selections[index].selected != selected[index].handle
	}
	if changed {
		if !registry_can_advance(state) {
			return {}, false, registry_reject(state, failure(.Select, .Generation_Limit))
		}
		for index in 0 ..< MAX_COMPLETION_ROLES {
			state.selections[index].selected = selected[index].handle
			state.selections[index].selected_capabilities = selected[index].definition.capabilities
		}
		state.enabled = true
		state.registry_generation += 1
		state.composition_generation += 1
	}
	return registry_scope_from_state(state), true, {}
}
