// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package completion

import "base:runtime"

@(private)
Implementation_Slot :: struct {
	record: Implementation_Record,
	live:   bool,
}

@(private)
Registry_State :: struct {
	registry_id:            Role_Registry_ID,
	registry_generation:    Role_Registry_Generation,
	composition_generation: Composition_Generation,
	next_implementation_id: Implementation_ID,
	implementations:        [MAX_COMPLETION_IMPLEMENTATIONS]Implementation_Slot,
	selections:             [MAX_COMPLETION_ROLES]Role_Selection,
	live_count:             u16,
	factory_count:          u16,
	package_count:          u16,
	personal_count:         u16,
	replacement_count:      u16,
	enabled:                bool,
	limits:                 Limits,
	last_rejection:         Failure,
	allocator:              runtime.Allocator,
}

/* registry_init publishes one complete maintained factory composition. */
registry_init :: proc(
	registry: ^Role_Registry,
	registry_id: Role_Registry_ID,
	limits := DEFAULT_LIMITS,
	allocator := context.allocator,
) -> (bool, Failure) {
	if registry == nil {
		return false, failure(.Initialize, .Invalid_Registry)
	}
	registry^ = {}
	if registry_id == Role_Registry_ID(0) {
		return false, failure(.Initialize, .Invalid_Identity)
	}
	if !limits_are_valid(limits) {
		return false, failure(.Initialize, .Invalid_State)
	}
	if allocator.procedure == nil {
		return false, failure(.Initialize, .Allocation)
	}
	state, allocation_error := new(Registry_State, allocator)
	if allocation_error != nil {
		return false, failure(.Initialize, .Allocation)
	}
	state^ = {
		registry_id = registry_id,
		registry_generation = 1,
		composition_generation = 1,
		next_implementation_id = 1,
		enabled = true,
		limits = limits,
		allocator = allocator,
	}
	for role_value in 1 ..= MAX_COMPLETION_ROLES {
		role := Role(role_value)
		record, ok := registry_install_factory(state, role)
		if !ok {
			free(state, allocator)
			return false, failure(.Initialize, .Invalid_Role, role)
		}
		state.selections[role_value - 1] = {
			role = role,
			selected = record.handle,
			selected_capabilities = record.definition.capabilities,
			factory = record.handle,
			factory_capabilities = record.definition.capabilities,
		}
	}
	registry.state = state
	return true, {}
}

/* registry_close releases registry storage exactly once. */
registry_close :: proc(registry: ^Role_Registry) -> (bool, Failure) {
	state := registry_state(registry)
	if state == nil {
		return false, failure(.Close, .Invalid_Registry)
	}
	allocator := state.allocator
	free(state, allocator)
	registry^ = Role_Registry{closed = true}
	return true, {}
}

/* registry_scope copies one exact complete selection snapshot. */
registry_scope :: proc(registry: ^Role_Registry) -> (Composition_Scope, bool, Failure) {
	state := registry_state(registry)
	if state == nil {
		return {}, false, failure(.Inspect, .Invalid_Registry)
	}
	return registry_scope_from_state(state), true, {}
}

/* registry_record copies one exact immutable implementation generation. */
registry_record :: proc(
	registry: ^Role_Registry,
	handle: Implementation_Handle,
) -> (Implementation_Record, bool, Failure) {
	state := registry_state(registry)
	if state == nil {
		return {}, false, failure(.Inspect, .Invalid_Registry, handle.role, handle)
	}
	slot, resolved, code := registry_resolve(state, handle)
	if !resolved {
		return {}, false, registry_reject(state, failure(.Inspect, code, handle.role, handle))
	}
	return slot.record, true, {}
}

/* registry_register copies one package or personal implementation. */
registry_register :: proc(
	registry: ^Role_Registry,
	definition: Implementation_Definition,
) -> (Implementation_Record, bool, Failure) {
	state := registry_state(registry)
	if state == nil {
		return {}, false, failure(.Register, .Invalid_Registry, definition.role)
	}
	code := definition_failure(definition)
	if code != .None {
		return {}, false, registry_reject(state, failure(.Register, code, definition.role))
	}
	if definition.kind == .Factory {
		return {}, false, registry_reject(state, failure(.Register, .Invalid_Kind, definition.role))
	}
	candidate_name := definition.name
	candidate_source := definition.source
	for &slot in state.implementations {
		if slot.live && slot.record.definition.role == definition.role &&
		   name_view(&slot.record.definition.name) == name_view(&candidate_name) &&
		   name_view(&slot.record.definition.source) == name_view(&candidate_source) {
			return {}, false, registry_reject(
				state,
				failure(.Register, .Duplicate_Implementation, definition.role),
			)
		}
	}
	if state.live_count >= state.limits.implementations {
		result := failure(.Register, .Implementation_Limit, definition.role)
		result.limit = u64(state.limits.implementations)
		result.actual = u64(state.live_count) + 1
		return {}, false, registry_reject(state, result)
	}
	if state.next_implementation_id == Implementation_ID(0) || !registry_can_advance(state) {
		return {}, false, registry_reject(state, failure(.Register, .Generation_Limit, definition.role))
	}
	for &slot in state.implementations {
		if slot.live {
			continue
		}
		record := Implementation_Record {
			handle = {
				registry_id = state.registry_id,
				role = definition.role,
				implementation_id = state.next_implementation_id,
				implementation_generation = 1,
			},
			definition = definition,
		}
		state.next_implementation_id += 1
		slot = {record = record, live = true}
		state.live_count += 1
		if definition.kind == .Package do state.package_count += 1
		if definition.kind == .Personal do state.personal_count += 1
		state.registry_generation += 1
		return record, true, {}
	}
	return {}, false, registry_reject(state, failure(.Register, .Implementation_Limit, definition.role))
}

/* registry_select atomically selects one exact compatible role generation. */
registry_select :: proc(
	registry: ^Role_Registry,
	expected: Composition_Scope,
	handle: Implementation_Handle,
) -> (Composition_Scope, bool, Failure) {
	state := registry_state(registry)
	if state == nil {
		return {}, false, failure(.Select, .Invalid_Registry, handle.role, handle)
	}
	if !registry_scope_matches(state, expected) {
		return {}, false, registry_reject(state, failure(.Select, .Stale_Scope, handle.role, handle))
	}
	slot, resolved, code := registry_resolve(state, handle)
	if !resolved {
		return {}, false, registry_reject(state, failure(.Select, code, handle.role, handle))
	}
	selection := &state.selections[role_index(handle.role)]
	if selection.selected != handle {
		if !registry_can_advance(state) {
			return {}, false, registry_reject(state, failure(.Select, .Generation_Limit, handle.role, handle))
		}
		selection.selected = handle
		selection.selected_capabilities = slot.record.definition.capabilities
		state.enabled = true
		state.registry_generation += 1
		state.composition_generation += 1
	}
	return registry_scope_from_state(state), true, {}
}

/* registry_replace publishes one immutable replacement generation. */
registry_replace :: proc(
	registry: ^Role_Registry,
	expected: Composition_Scope,
	handle: Implementation_Handle,
	definition: Implementation_Definition,
) -> (Implementation_Record, Composition_Scope, bool, Failure) {
	state := registry_state(registry)
	if state == nil {
		return {}, {}, false, failure(.Replace, .Invalid_Registry, handle.role, handle)
	}
	if !registry_scope_matches(state, expected) {
		return {}, {}, false, registry_reject(state, failure(.Replace, .Stale_Scope, handle.role, handle))
	}
	slot, resolved, code := registry_resolve(state, handle)
	if !resolved {
		return {}, {}, false, registry_reject(state, failure(.Replace, code, handle.role, handle))
	}
	definition_code := definition_failure(definition)
	if definition_code != .None || definition.role != handle.role ||
	   definition.kind != slot.record.definition.kind {
		if definition_code == .None do definition_code = .Invalid_Kind
		return {}, {}, false, registry_reject(state, failure(.Replace, definition_code, handle.role, handle))
	}
	if state.replacement_count >= state.limits.replacements {
		return {}, {}, false, registry_reject(state, failure(.Replace, .Replacement_Limit, handle.role, handle))
	}
	if handle.implementation_generation == Implementation_Generation(max(u64)) ||
	   !registry_can_advance(state) {
		return {}, {}, false, registry_reject(state, failure(.Replace, .Generation_Limit, handle.role, handle))
	}
	replacement := slot.record
	replacement.handle.implementation_generation += 1
	replacement.definition = definition
	slot.record = replacement
	selection := &state.selections[role_index(handle.role)]
	if selection.selected == handle {
		selection.selected = replacement.handle
		selection.selected_capabilities = replacement.definition.capabilities
	}
	if selection.factory == handle {
		selection.factory = replacement.handle
		selection.factory_capabilities = replacement.definition.capabilities
	}
	state.replacement_count += 1
	state.registry_generation += 1
	state.composition_generation += 1
	return replacement, registry_scope_from_state(state), true, {}
}

/* registry_restore atomically selects the complete maintained factory composition. */
registry_restore :: proc(
	registry: ^Role_Registry,
	expected: Composition_Scope,
) -> (Composition_Scope, bool, Failure) {
	state := registry_state(registry)
	if state == nil {
		return {}, false, failure(.Restore, .Invalid_Registry)
	}
	if !registry_scope_matches(state, expected) {
		return {}, false, registry_reject(state, failure(.Restore, .Stale_Scope))
	}
	changed := !state.enabled
	for &selection in state.selections {
		changed = changed || selection.selected != selection.factory
	}
	if changed {
		if !registry_can_advance(state) {
			return {}, false, registry_reject(state, failure(.Restore, .Generation_Limit))
		}
		for &selection in state.selections {
			selection.selected = selection.factory
			selection.selected_capabilities = selection.factory_capabilities
		}
		state.enabled = true
		state.registry_generation += 1
		state.composition_generation += 1
	}
	return registry_scope_from_state(state), true, {}
}

/* registry_disable selects the safe plain-editing baseline. */
registry_disable :: proc(
	registry: ^Role_Registry,
	expected: Composition_Scope,
) -> (Composition_Scope, bool, Failure) {
	state := registry_state(registry)
	if state == nil {
		return {}, false, failure(.Disable, .Invalid_Registry)
	}
	if !registry_scope_matches(state, expected) {
		return {}, false, registry_reject(state, failure(.Disable, .Stale_Scope))
	}
	if state.enabled {
		if !registry_can_advance(state) {
			return {}, false, registry_reject(state, failure(.Disable, .Generation_Limit))
		}
		state.enabled = false
		state.registry_generation += 1
		state.composition_generation += 1
	}
	return registry_scope_from_state(state), true, {}
}

/* registry_inspect copies bounded occupancy, composition, and rejection state. */
registry_inspect :: proc(registry: ^Role_Registry) -> (Registry_Inspection, bool, Failure) {
	state := registry_state(registry)
	if state == nil {
		return {}, false, failure(.Inspect, .Invalid_Registry)
	}
	inspection := Registry_Inspection {
		stats = {
			registry_id = state.registry_id,
			registry_generation = state.registry_generation,
			composition_generation = state.composition_generation,
			live_implementations = state.live_count,
			factory_implementations = state.factory_count,
			package_implementations = state.package_count,
			personal_implementations = state.personal_count,
			replacements = state.replacement_count,
			retained_bytes = size_of(Registry_State),
		},
		composition = registry_scope_from_state(state),
		last_rejection = state.last_rejection,
	}
	for &slot in state.implementations {
		if !slot.live {
			continue
		}
		inspection.implementations[inspection.implementation_count] = slot.record
		inspection.implementation_count += 1
	}
	return inspection, true, {}
}

@(private)
registry_install_factory :: proc(state: ^Registry_State, role: Role) -> (Implementation_Record, bool) {
	name, name_ok := name_copy(factory_name(role))
	source, source_ok := name_copy("odra/factory")
	if !name_ok || !source_ok || state.next_implementation_id == Implementation_ID(0) {
		return {}, false
	}
	record := Implementation_Record {
		handle = {
			registry_id = state.registry_id,
			role = role,
			implementation_id = state.next_implementation_id,
			implementation_generation = 1,
		},
		definition = {
			name = name,
			source = source,
			role = role,
			kind = .Factory,
			capabilities = factory_capabilities(role),
		},
	}
	index := int(state.live_count)
	state.implementations[index] = {record = record, live = true}
	state.next_implementation_id += 1
	state.live_count += 1
	state.factory_count += 1
	return record, true
}

@(private)
registry_state :: proc(registry: ^Role_Registry) -> ^Registry_State {
	if registry == nil || registry.closed || registry.state == nil {
		return nil
	}
	return cast(^Registry_State)registry.state
}

@(private)
registry_resolve :: proc(
	state: ^Registry_State,
	handle: Implementation_Handle,
) -> (^Implementation_Slot, bool, Failure_Code) {
	if handle.registry_id != state.registry_id || handle.role == .Invalid ||
	   handle.implementation_id == Implementation_ID(0) ||
	   handle.implementation_generation == Implementation_Generation(0) {
		return nil, false, .Invalid_Identity
	}
	for &slot in state.implementations {
		if !slot.live || slot.record.handle.implementation_id != handle.implementation_id {
			continue
		}
		if slot.record.handle == handle {
			return &slot, true, .None
		}
		return nil, false, .Stale_Implementation
	}
	return nil, false, .Invalid_Identity
}

@(private)
registry_scope_from_state :: proc(state: ^Registry_State) -> Composition_Scope {
	return {
		registry_id = state.registry_id,
		registry_generation = state.registry_generation,
		composition_generation = state.composition_generation,
		selections = state.selections,
		enabled = state.enabled,
	}
}

@(private)
registry_scope_matches :: proc(state: ^Registry_State, scope: Composition_Scope) -> bool {
	return scope.registry_id == state.registry_id &&
		scope.registry_generation == state.registry_generation &&
		scope.composition_generation == state.composition_generation
}

@(private)
registry_can_advance :: proc(state: ^Registry_State) -> bool {
	return state.registry_generation != Role_Registry_Generation(max(u64)) &&
		state.composition_generation != Composition_Generation(max(u64))
}

@(private)
definition_failure :: proc(definition: Implementation_Definition) -> Failure_Code {
	if definition.role <= .Invalid || int(definition.role) > MAX_COMPLETION_ROLES {
		return .Invalid_Role
	}
	if definition.kind == .Invalid {
		return .Invalid_Kind
	}
	if definition.name.byte_count == 0 || definition.source.byte_count == 0 {
		return .Invalid_Name
	}
	required := role_required_capabilities(definition.role)
	if required - definition.capabilities != {} {
		return .Invalid_Kind
	}
	return .None
}

@(private)
role_required_capabilities :: proc(role: Role) -> Capabilities {
	switch role {
	case .Invalid:
		return {}
	case .Provider:
		return {.Explicit}
	case .Policy:
		return {.Explicit, .Identifier}
	case .Presentation:
		return {.Documentation}
	}
	return {}
}

@(private)
factory_capabilities :: proc(role: Role) -> Capabilities {
	switch role {
	case .Invalid:
		return {}
	case .Provider:
		return {.Explicit, .Identifier, .Trigger_Character, .Incomplete, .Resolve, .Additional_Edits, .Documentation}
	case .Policy:
		return {.Explicit, .Identifier, .Trigger_Character, .Incomplete}
	case .Presentation:
		return {.Documentation}
	}
	return {}
}

@(private)
factory_name :: proc(role: Role) -> string {
	switch role {
	case .Invalid:      return ""
	case .Provider:     return "language-service"
	case .Policy:       return "factory-completion"
	case .Presentation: return "interactive-candidate"
	}
	return ""
}

@(private)
role_index :: proc(role: Role) -> int {
	return int(role) - 1
}

@(private)
failure :: proc(
	operation: Operation,
	code: Failure_Code,
	role := Role.Invalid,
	implementation := Implementation_Handle{},
) -> Failure {
	return {operation = operation, code = code, role = role, implementation = implementation}
}

@(private)
registry_reject :: proc(state: ^Registry_State, rejected: Failure) -> Failure {
	state.last_rejection = rejected
	return rejected
}
