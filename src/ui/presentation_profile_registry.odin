// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ui

import "base:runtime"

@(private)
Presentation_Profile_Slot :: struct {
	record: Presentation_Profile_Record,
	live:   bool,
}

@(private)
Presentation_Profile_Selection_State :: struct {
	selected: Presentation_Profile_Handle,
	factory:  Presentation_Profile_Handle,
}

@(private)
Presentation_Profile_Registry_State :: struct {
	registry_id:         Presentation_Profile_Registry_ID,
	registry_generation: Presentation_Profile_Registry_Generation,
	next_profile_id:     Presentation_Profile_ID,
	live_count:          u16,
	factory_count:       u16,
	package_count:       u16,
	personal_count:      u16,
	profiles:            [MAX_PRESENTATION_PROFILES]Presentation_Profile_Slot,
	selections:          [PRESENTATION_PROFILE_ROLE_COUNT]Presentation_Profile_Selection_State,
	limits:              Presentation_Profile_Limits,
	last_rejection:      Presentation_Profile_Failure,
	allocator:           runtime.Allocator,
}

/* presentation_profile_registry_init creates every maintained factory selection. */
presentation_profile_registry_init :: proc(
	registry: ^Presentation_Profile_Registry,
	registry_id: Presentation_Profile_Registry_ID,
	limits := DEFAULT_PRESENTATION_PROFILE_LIMITS,
	allocator := context.allocator,
) -> (ok: bool, failure: Presentation_Profile_Failure) {
	if registry == nil {
		return false, presentation_profile_failure(.Initialize, .Invalid_Registry)
	}
	registry^ = {}
	if registry_id == Presentation_Profile_Registry_ID(0) {
		return false, presentation_profile_failure(.Initialize, .Invalid_Identity)
	}
	if !presentation_profile_limits_are_valid(limits) {
		return false, presentation_profile_failure(.Initialize, .Invalid_Profile)
	}
	if allocator.procedure == nil {
		return false, presentation_profile_failure(.Initialize, .Allocation)
	}
	state, allocation_error := new(Presentation_Profile_Registry_State, allocator)
	if allocation_error != nil {
		return false, presentation_profile_failure(.Initialize, .Allocation)
	}
	state^ = {
		registry_id = registry_id,
		registry_generation = 1,
		next_profile_id = 1,
		limits = limits,
		allocator = allocator,
	}
	for role_value in 1..=PRESENTATION_PROFILE_ROLE_COUNT {
		role := Presentation_Profile_Role(role_value)
		factory := presentation_profile_factory_definition(role)
		handle := Presentation_Profile_Handle {
			registry_id = registry_id,
			role = role,
			profile_id = state.next_profile_id,
			profile_generation = 1,
		}
		state.profiles[role_value - 1] = {
			record = {handle = handle, definition = factory},
			live = true,
		}
		state.selections[role_value - 1] = {selected = handle, factory = handle}
		state.next_profile_id += 1
	}
	state.live_count = PRESENTATION_PROFILE_ROLE_COUNT
	state.factory_count = PRESENTATION_PROFILE_ROLE_COUNT
	registry.state = state
	return true, {}
}

/* presentation_profile_registry_close releases registry storage exactly once. */
presentation_profile_registry_close :: proc(
	registry: ^Presentation_Profile_Registry,
) -> (ok: bool, failure: Presentation_Profile_Failure) {
	state := presentation_profile_registry_state(registry)
	if state == nil {
		return false, presentation_profile_failure(.Teardown, .Invalid_Registry)
	}
	allocator := state.allocator
	free(state, allocator)
	registry^ = Presentation_Profile_Registry{closed = true}
	return true, {}
}

/* presentation_profile_registry_scope copies one exact role-selection snapshot. */
presentation_profile_registry_scope :: proc(
	registry: ^Presentation_Profile_Registry,
	role: Presentation_Profile_Role,
) -> (scope: Presentation_Profile_Scope, ok: bool, failure: Presentation_Profile_Failure) {
	state := presentation_profile_registry_state(registry)
	if state == nil {
		return {}, false, presentation_profile_failure(.Inspect, .Invalid_Registry, role)
	}
	if !presentation_profile_role_is_valid(role) {
		return {}, false, presentation_profile_reject(
			state,
			presentation_profile_failure(.Inspect, .Invalid_Role, role),
		)
	}
	return presentation_profile_scope_from_state(state, role), true, {}
}

/* presentation_profile_registry_record copies one exact immutable definition. */
presentation_profile_registry_record :: proc(
	registry: ^Presentation_Profile_Registry,
	handle: Presentation_Profile_Handle,
) -> (record: Presentation_Profile_Record, ok: bool, failure: Presentation_Profile_Failure) {
	state := presentation_profile_registry_state(registry)
	if state == nil {
		return {}, false, presentation_profile_failure(.Inspect, .Invalid_Registry, handle.role, handle)
	}
	slot, resolve_failure := presentation_profile_resolve(state, handle)
	if resolve_failure.code != .None {
		resolve_failure.operation = .Inspect
		return {}, false, presentation_profile_reject(state, resolve_failure)
	}
	return slot.record, true, {}
}

/* presentation_profile_registry_register copies one package or personal profile. */
presentation_profile_registry_register :: proc(
	registry: ^Presentation_Profile_Registry,
	definition: Presentation_Profile_Definition,
) -> (record: Presentation_Profile_Record, ok: bool, failure: Presentation_Profile_Failure) {
	state := presentation_profile_registry_state(registry)
	if state == nil {
		return {}, false, presentation_profile_failure(.Register, .Invalid_Registry, definition.role)
	}
	candidate := definition
	failure = presentation_profile_definition_shape_failure(&candidate, state.limits)
	failure.operation = .Register
	if failure.code != .None {
		return {}, false, presentation_profile_reject(state, failure)
	}
	if definition.kind == .Factory {
		return {}, false, presentation_profile_reject(
			state,
			presentation_profile_failure(.Register, .Invalid_Kind, definition.role),
		)
	}
	if presentation_profile_duplicate_exists(state, &candidate, {}) {
		return {}, false, presentation_profile_reject(
			state,
			presentation_profile_failure(.Register, .Duplicate_Profile, definition.role),
		)
	}
	if state.live_count >= state.limits.profiles {
		failure = presentation_profile_failure(.Register, .Profile_Limit, definition.role)
		failure.limit = u64(state.limits.profiles)
		failure.actual = u64(state.live_count) + 1
		return {}, false, presentation_profile_reject(state, failure)
	}
	if state.next_profile_id == Presentation_Profile_ID(0) ||
	   state.registry_generation == Presentation_Profile_Registry_Generation(max(u64)) {
		return {}, false, presentation_profile_reject(
			state,
			presentation_profile_failure(.Register, .Generation_Limit, definition.role),
		)
	}
	fallback_failure := presentation_profile_validate_fallback(state, &candidate, {})
	if fallback_failure.code != .None {
		fallback_failure.operation = .Register
		return {}, false, presentation_profile_reject(state, fallback_failure)
	}
	for &slot in state.profiles {
		if slot.live {
			continue
		}
		handle := Presentation_Profile_Handle {
			registry_id = state.registry_id,
			role = definition.role,
			profile_id = state.next_profile_id,
			profile_generation = 1,
		}
		state.next_profile_id += 1
		slot = {record = {handle = handle, definition = candidate}, live = true}
		state.live_count += 1
		presentation_profile_increment_kind(state, definition.kind)
		state.registry_generation += 1
		return slot.record, true, {}
	}
	return {}, false, presentation_profile_reject(
		state,
		presentation_profile_failure(.Register, .Profile_Limit, definition.role),
	)
}

/* presentation_profile_registry_select atomically selects a compatible generation. */
presentation_profile_registry_select :: proc(
	registry: ^Presentation_Profile_Registry,
	expected_scope: Presentation_Profile_Scope,
	requested: Presentation_Profile_Handle,
	renderer: Renderer_Profile,
) -> (selection: Presentation_Profile_Selection, ok: bool, failure: Presentation_Profile_Failure) {
	state := presentation_profile_registry_state(registry)
	if state == nil {
		return {}, false, presentation_profile_failure(.Select, .Invalid_Registry, requested.role, requested)
	}
	if !presentation_profile_scope_matches(state, expected_scope) {
		return {}, false, presentation_profile_reject(
			state,
			presentation_profile_failure(.Select, .Stale_Scope, expected_scope.role, requested),
		)
	}
	resolved, fallback_selected, fallback_depth, resolved_ok, resolve_failure :=
		presentation_profile_resolve_for_renderer(state, requested, renderer)
	if !resolved_ok {
		resolve_failure.operation = .Select
		return {}, false, presentation_profile_reject(state, resolve_failure)
	}
	selected := &state.selections[presentation_profile_role_index(expected_scope.role)]
	previous := selected.selected
	if previous != resolved {
		if state.registry_generation == Presentation_Profile_Registry_Generation(max(u64)) {
			return {}, false, presentation_profile_reject(
				state,
				presentation_profile_failure(.Select, .Generation_Limit, requested.role, requested),
			)
		}
		selected.selected = resolved
		state.registry_generation += 1
	}
	scope := presentation_profile_scope_from_state(state, expected_scope.role)
	return {
		scope = scope,
		previous = previous,
		requested = requested,
		selected = resolved,
		changed = previous != resolved,
		fallback_selected = fallback_selected,
		fallback_depth = fallback_depth,
	}, true, {}
}

/* presentation_profile_registry_replace publishes one immutable replacement. */
presentation_profile_registry_replace :: proc(
	registry: ^Presentation_Profile_Registry,
	expected_scope: Presentation_Profile_Scope,
	handle: Presentation_Profile_Handle,
	definition: Presentation_Profile_Definition,
) -> (record: Presentation_Profile_Record, scope: Presentation_Profile_Scope, ok: bool, failure: Presentation_Profile_Failure) {
	state := presentation_profile_registry_state(registry)
	if state == nil {
		return {}, {}, false, presentation_profile_failure(.Replace, .Invalid_Registry, handle.role, handle)
	}
	if !presentation_profile_scope_matches(state, expected_scope) {
		return {}, {}, false, presentation_profile_reject(
			state,
			presentation_profile_failure(.Replace, .Stale_Scope, expected_scope.role, handle),
		)
	}
	slot, resolve_failure := presentation_profile_resolve(state, handle)
	if resolve_failure.code != .None {
		resolve_failure.operation = .Replace
		return {}, {}, false, presentation_profile_reject(state, resolve_failure)
	}
	candidate := definition
	failure = presentation_profile_definition_shape_failure(&candidate, state.limits)
	failure.operation = .Replace
	if failure.code != .None {
		return {}, {}, false, presentation_profile_reject(state, failure)
	}
	if definition.role != handle.role || definition.kind != slot.record.definition.kind {
		return {}, {}, false, presentation_profile_reject(
			state,
			presentation_profile_failure(.Replace, .Invalid_Profile, handle.role, handle),
		)
	}
	if presentation_profile_duplicate_exists(state, &candidate, handle) {
		return {}, {}, false, presentation_profile_reject(
			state,
			presentation_profile_failure(.Replace, .Duplicate_Profile, handle.role, handle),
		)
	}
	fallback_failure := presentation_profile_validate_fallback(state, &candidate, handle)
	if fallback_failure.code != .None {
		fallback_failure.operation = .Replace
		return {}, {}, false, presentation_profile_reject(state, fallback_failure)
	}
	if handle.profile_generation == Presentation_Profile_Generation(max(u64)) ||
	   state.registry_generation == Presentation_Profile_Registry_Generation(max(u64)) {
		return {}, {}, false, presentation_profile_reject(
			state,
			presentation_profile_failure(.Replace, .Generation_Limit, handle.role, handle),
		)
	}
	replacement := handle
	replacement.profile_generation += 1
	slot.record = {handle = replacement, definition = candidate}
	selection := &state.selections[presentation_profile_role_index(handle.role)]
	if selection.selected == handle {
		selection.selected = replacement
	}
	if selection.factory == handle {
		selection.factory = replacement
	}
	for &dependent in state.profiles {
		if dependent.live && dependent.record.handle != replacement &&
		   dependent.record.definition.fallback == handle {
			dependent.record.definition.fallback = replacement
		}
	}
	state.registry_generation += 1
	return slot.record, presentation_profile_scope_from_state(state, handle.role), true, {}
}

/* presentation_profile_registry_restore selects the current factory generation. */
presentation_profile_registry_restore :: proc(
	registry: ^Presentation_Profile_Registry,
	expected_scope: Presentation_Profile_Scope,
	renderer: Renderer_Profile,
) -> (selection: Presentation_Profile_Selection, ok: bool, failure: Presentation_Profile_Failure) {
	state := presentation_profile_registry_state(registry)
	if state == nil {
		return {}, false, presentation_profile_failure(.Restore, .Invalid_Registry, expected_scope.role)
	}
	if !presentation_profile_scope_matches(state, expected_scope) {
		return {}, false, presentation_profile_reject(
			state,
			presentation_profile_failure(.Restore, .Stale_Scope, expected_scope.role),
		)
	}
	factory := state.selections[presentation_profile_role_index(expected_scope.role)].factory
	selection, ok, failure = presentation_profile_registry_select(
		registry,
		expected_scope,
		factory,
		renderer,
	)
	if failure.code != .None {
		failure.operation = .Restore
		state.last_rejection = failure
	}
	return
}

/* presentation_profile_registry_disable rejects absence for the protected role. */
presentation_profile_registry_disable :: proc(
	registry: ^Presentation_Profile_Registry,
	expected_scope: Presentation_Profile_Scope,
) -> (ok: bool, failure: Presentation_Profile_Failure) {
	state := presentation_profile_registry_state(registry)
	if state == nil {
		return false, presentation_profile_failure(.Disable, .Invalid_Registry, expected_scope.role)
	}
	if !presentation_profile_scope_matches(state, expected_scope) {
		return false, presentation_profile_reject(
			state,
			presentation_profile_failure(.Disable, .Stale_Scope, expected_scope.role),
		)
	}
	return false, presentation_profile_reject(
		state,
		presentation_profile_failure(.Disable, .Protected_Role, expected_scope.role),
	)
}

/* presentation_profile_registry_teardown removes one configurable profile. */
presentation_profile_registry_teardown :: proc(
	registry: ^Presentation_Profile_Registry,
	expected_scope: Presentation_Profile_Scope,
	handle: Presentation_Profile_Handle,
) -> (scope: Presentation_Profile_Scope, ok: bool, failure: Presentation_Profile_Failure) {
	state := presentation_profile_registry_state(registry)
	if state == nil {
		return {}, false, presentation_profile_failure(.Teardown, .Invalid_Registry, handle.role, handle)
	}
	if !presentation_profile_scope_matches(state, expected_scope) {
		return {}, false, presentation_profile_reject(
			state,
			presentation_profile_failure(.Teardown, .Stale_Scope, expected_scope.role, handle),
		)
	}
	slot, resolve_failure := presentation_profile_resolve(state, handle)
	if resolve_failure.code != .None {
		resolve_failure.operation = .Teardown
		return {}, false, presentation_profile_reject(state, resolve_failure)
	}
	if slot.record.definition.kind == .Factory {
		return {}, false, presentation_profile_reject(
			state,
			presentation_profile_failure(.Teardown, .Protected_Role, handle.role, handle),
		)
	}
	for &dependent in state.profiles {
		if dependent.live && dependent.record.handle != handle &&
		   dependent.record.definition.fallback == handle {
			return {}, false, presentation_profile_reject(
				state,
				presentation_profile_failure(.Teardown, .Invalid_Fallback, handle.role, handle),
			)
		}
	}
	if state.registry_generation == Presentation_Profile_Registry_Generation(max(u64)) {
		return {}, false, presentation_profile_reject(
			state,
			presentation_profile_failure(.Teardown, .Generation_Limit, handle.role, handle),
		)
	}
	selection := &state.selections[presentation_profile_role_index(handle.role)]
	if selection.selected == handle {
		selection.selected = selection.factory
	}
	presentation_profile_decrement_kind(state, slot.record.definition.kind)
	slot^ = {}
	state.live_count -= 1
	state.registry_generation += 1
	return presentation_profile_scope_from_state(state, handle.role), true, {}
}

/* presentation_profile_registry_inspect copies bounded registry state by value. */
presentation_profile_registry_inspect :: proc(
	registry: ^Presentation_Profile_Registry,
) -> (inspection: Presentation_Profile_Inspection, ok: bool, failure: Presentation_Profile_Failure) {
	state := presentation_profile_registry_state(registry)
	if state == nil {
		return {}, false, presentation_profile_failure(.Inspect, .Invalid_Registry)
	}
	inspection.stats = presentation_profile_stats_from_state(state)
	for role_value in 1..=PRESENTATION_PROFILE_ROLE_COUNT {
		role := Presentation_Profile_Role(role_value)
		inspection.scopes[role_value - 1] = presentation_profile_scope_from_state(state, role)
	}
	for &slot in state.profiles {
		if slot.live {
			inspection.profiles[inspection.profile_count] = slot.record
			inspection.profile_count += 1
		}
	}
	inspection.last_rejection = state.last_rejection
	return inspection, true, {}
}

@(private)
presentation_profile_factory_definition :: proc(
	role: Presentation_Profile_Role,
) -> Presentation_Profile_Definition {
	name_value := "contextual-information"
	if role == .Interactive_Candidates do name_value = "interactive-candidates"
	name, _ := presentation_profile_text(name_value)
	source, _ := presentation_profile_text("odra")
	definition := Presentation_Profile_Definition {
		name = name,
		source = source,
		kind = .Factory,
		role = role,
		mappings = {
			0 = {slot = .Background, style_role = .Popup_Background},
			1 = {slot = .Border, style_role = .Popup_Border},
			2 = {slot = .Title, style_role = .Popup_Border},
			3 = {slot = .Content, style_role = .Popup_Content},
			4 = {slot = .Selection, style_role = .List_Emphasis},
			5 = {slot = .Annotation, style_role = .Popup_Diagnostic},
			6 = {slot = .Separator, style_role = .Popup_Border},
			7 = {slot = .Action, style_role = .List_Emphasis},
			8 = {slot = .Unavailable, style_role = .Popup_Unavailable},
			9 = {slot = .Attention, style_role = .Popup_Diagnostic},
		},
		mapping_count = 10,
		margin_columns = 1,
		border = .Single,
		bounds = {
			minimum_rows = 3,
			minimum_columns = 18,
			preferred_rows = 5,
			preferred_columns = 56,
			maximum_rows = 8,
			maximum_columns = 80,
		},
		clipping = .Clip,
		popup_fallback = .Compact_Feedback,
		degradation = .Portable_Border,
		required_capabilities = {.Cell_Geometry, .Clipping},
		configurable = true,
	}
	if role == .Interactive_Candidates {
		definition.mappings = {
			0 = {slot = .Background, style_role = .List_Normal},
			1 = {slot = .Border, style_role = .List_Emphasis},
			2 = {slot = .Title, style_role = .List_Emphasis},
			3 = {slot = .Content, style_role = .List_Normal},
			4 = {slot = .Selection, style_role = .List_Current},
			5 = {slot = .Annotation, style_role = .List_Emphasis},
			6 = {slot = .Separator, style_role = .List_Emphasis},
			7 = {slot = .Action, style_role = .List_Current},
			8 = {slot = .Unavailable, style_role = .Diagnostic_Rejected},
			9 = {slot = .Attention, style_role = .Status_Alert},
		}
		definition.margin_columns = 0
	}
	return definition
}

@(private)
presentation_profile_validate_fallback :: proc(
	state: ^Presentation_Profile_Registry_State,
	definition: ^Presentation_Profile_Definition,
	replaced: Presentation_Profile_Handle,
) -> Presentation_Profile_Failure {
	if state == nil || definition == nil {
		return presentation_profile_failure(.Register, .Invalid_Fallback)
	}
	if definition.kind == .Factory {
		return {}
	}
	current := definition.fallback
	for depth in 1..=state.limits.fallback_depth {
		if replaced.profile_id != Presentation_Profile_ID(0) &&
		   current.profile_id == replaced.profile_id {
			failure := presentation_profile_failure(
				.Register,
				.Fallback_Cycle,
				definition.role,
				current,
			)
			failure.fallback_depth = u8(depth)
			return failure
		}
		slot, resolve_failure := presentation_profile_resolve(state, current)
		if resolve_failure.code != .None {
			resolve_failure.code = .Invalid_Fallback
			resolve_failure.fallback_depth = u8(depth)
			return resolve_failure
		}
		if slot.record.definition.kind == .Factory {
			return {}
		}
		current = slot.record.definition.fallback
	}
	failure := presentation_profile_failure(
		.Register,
		.Fallback_Depth,
		definition.role,
		definition.fallback,
	)
	failure.limit = u64(state.limits.fallback_depth)
	failure.actual = u64(state.limits.fallback_depth) + 1
	failure.fallback_depth = state.limits.fallback_depth
	return failure
}

@(private)
presentation_profile_resolve_for_renderer :: proc(
	state: ^Presentation_Profile_Registry_State,
	requested: Presentation_Profile_Handle,
	renderer: Renderer_Profile,
) -> (
	resolved: Presentation_Profile_Handle,
	fallback_selected: bool,
	fallback_depth: u8,
	ok: bool,
	failure: Presentation_Profile_Failure,
) {
	if !renderer_profile_is_valid(renderer) {
		return {}, false, 0, false, presentation_profile_failure(
			.Select,
			.Renderer_Incompatible,
			requested.role,
			requested,
		)
	}
	current := requested
	for depth in 0..=state.limits.fallback_depth {
		slot, resolve_failure := presentation_profile_resolve(state, current)
		if resolve_failure.code != .None {
			return {}, false, u8(depth), false, resolve_failure
		}
		if slot.record.definition.required_capabilities & renderer.capabilities ==
		   slot.record.definition.required_capabilities {
			return current, depth > 0, u8(depth), true, {}
		}
		if slot.record.definition.kind == .Factory {
			break
		}
		current = slot.record.definition.fallback
	}
	failure = presentation_profile_failure(
		.Select,
		.Renderer_Incompatible,
		requested.role,
		requested,
	)
	failure.fallback_depth = state.limits.fallback_depth
	return {}, false, state.limits.fallback_depth, false, failure
}

@(private)
presentation_profile_resolve :: proc(
	state: ^Presentation_Profile_Registry_State,
	handle: Presentation_Profile_Handle,
) -> (slot: ^Presentation_Profile_Slot, failure: Presentation_Profile_Failure) {
	if state == nil || handle.registry_id != state.registry_id ||
	   handle.registry_id == Presentation_Profile_Registry_ID(0) {
		return nil, presentation_profile_failure(
			.Inspect,
			.Invalid_Identity,
			handle.role,
			handle,
		)
	}
	if !presentation_profile_role_is_valid(handle.role) ||
	   handle.profile_id == Presentation_Profile_ID(0) ||
	   handle.profile_generation == Presentation_Profile_Generation(0) {
		return nil, presentation_profile_failure(
			.Inspect,
			.Invalid_Profile,
			handle.role,
			handle,
		)
	}
	for &candidate in state.profiles {
		if candidate.live && candidate.record.handle.profile_id == handle.profile_id {
			if candidate.record.handle == handle {
				return &candidate, {}
			}
			return nil, presentation_profile_failure(
				.Inspect,
				.Stale_Profile,
				handle.role,
				handle,
			)
		}
	}
	return nil, presentation_profile_failure(
		.Inspect,
		.Stale_Profile,
		handle.role,
		handle,
	)
}

@(private)
presentation_profile_duplicate_exists :: proc(
	state: ^Presentation_Profile_Registry_State,
	definition: ^Presentation_Profile_Definition,
	excluded: Presentation_Profile_Handle,
) -> bool {
	for &slot in state.profiles {
		if !slot.live || slot.record.handle == excluded ||
		   slot.record.definition.role != definition.role {
			continue
		}
		if slot.record.definition.name == definition.name &&
		   slot.record.definition.source == definition.source {
			return true
		}
	}
	return false
}

@(private)
presentation_profile_scope_from_state :: proc(
	state: ^Presentation_Profile_Registry_State,
	role: Presentation_Profile_Role,
) -> Presentation_Profile_Scope {
	selection := state.selections[presentation_profile_role_index(role)]
	return {
		registry_id = state.registry_id,
		registry_generation = state.registry_generation,
		role = role,
		selected = selection.selected,
		factory = selection.factory,
	}
}

@(private)
presentation_profile_scope_matches :: proc(
	state: ^Presentation_Profile_Registry_State,
	expected: Presentation_Profile_Scope,
) -> bool {
	if state == nil || expected.registry_id != state.registry_id ||
	   !presentation_profile_role_is_valid(expected.role) ||
	   expected.registry_generation != state.registry_generation {
		return false
	}
	current := state.selections[presentation_profile_role_index(expected.role)]
	return expected.selected == current.selected && expected.factory == current.factory
}

@(private)
presentation_profile_stats_from_state :: proc(
	state: ^Presentation_Profile_Registry_State,
) -> Presentation_Profile_Stats {
	return {
		registry_id = state.registry_id,
		registry_generation = state.registry_generation,
		live_profiles = state.live_count,
		factory_profiles = state.factory_count,
		package_profiles = state.package_count,
		personal_profiles = state.personal_count,
		retained_bytes = size_of(Presentation_Profile_Registry_State),
	}
}

@(private)
presentation_profile_increment_kind :: proc(
	state: ^Presentation_Profile_Registry_State,
	kind: Presentation_Profile_Kind,
) {
	switch kind {
	case .Factory:
		state.factory_count += 1
	case .Package:
		state.package_count += 1
	case .Personal:
		state.personal_count += 1
	case .Invalid:
	}
}

@(private)
presentation_profile_decrement_kind :: proc(
	state: ^Presentation_Profile_Registry_State,
	kind: Presentation_Profile_Kind,
) {
	switch kind {
	case .Factory:
		state.factory_count -= 1
	case .Package:
		state.package_count -= 1
	case .Personal:
		state.personal_count -= 1
	case .Invalid:
	}
}

@(private)
presentation_profile_role_index :: proc(role: Presentation_Profile_Role) -> int {
	return int(role) - 1
}

@(private)
presentation_profile_registry_state :: proc(
	registry: ^Presentation_Profile_Registry,
) -> ^Presentation_Profile_Registry_State {
	if registry == nil || registry.state == nil || registry.closed {
		return nil
	}
	return cast(^Presentation_Profile_Registry_State)registry.state
}

@(private)
presentation_profile_reject :: proc(
	state: ^Presentation_Profile_Registry_State,
	failure: Presentation_Profile_Failure,
) -> Presentation_Profile_Failure {
	if state != nil {
		state.last_rejection = failure
	}
	return failure
}

@(private)
presentation_profile_failure :: proc(
	operation: Presentation_Profile_Operation,
	code: Presentation_Profile_Failure_Code,
	role := Presentation_Profile_Role.Invalid,
	profile := Presentation_Profile_Handle{},
) -> Presentation_Profile_Failure {
	return {operation = operation, code = code, role = role, profile = profile}
}
