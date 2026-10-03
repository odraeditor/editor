// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language

import "base:runtime"

/* Provider_Definition is one bounded native provider registration proposal. */
Provider_Definition :: struct {
	name:         string,
	parser_name:  string,
	grammar_abi:  u32,
	capabilities: Provider_Capabilities,
	provenance:   string,
}

/* Provider_Registry_Stats reports exact registry occupancy and generation. */
Provider_Registry_Stats :: struct {
	registry_id:         Registry_ID,
	registry_generation: Registry_Generation,
	language:            Language_Identity,
	live_providers:      u16,
	native_providers:    u16,
	disabled:            bool,
}

/* Provider_Registry owns one bounded native provider-selection responsibility. */
Provider_Registry :: struct {
	state:  rawptr,
	closed: bool,
}

@(private)
Provider_Slot :: struct {
	descriptor: Provider_Descriptor,
	live:       bool,
}

@(private)
Provider_Registry_State :: struct {
	registry_id:         Registry_ID,
	registry_generation: Registry_Generation,
	language:            Language_Identity,
	active:              Provider_Handle,
	factory:             Provider_Handle,
	selection_state:     Selection_State,
	next_provider_id:    Provider_ID,
	live_count:          u16,
	native_count:        u16,
	providers:           [MAX_PROVIDERS]Provider_Slot,
	allocator:           runtime.Allocator,
}

/* provider_registry_init creates one confirmed active factory provider. */
provider_registry_init :: proc(
	registry: ^Provider_Registry,
	registry_id: Registry_ID,
	language: Language_Identity,
	factory: Provider_Definition,
	allocator := context.allocator,
) -> (ok: bool, failure: Failure) {
	if registry == nil {
		return false, provider_failure(.Initialize, .Invalid_Registry, language.id)
	}
	registry^ = {}
	if registry_id == Registry_ID(0) || !language_identity_is_valid(language) {
		return false, provider_failure(.Initialize, .Invalid_Language, language.id)
	}
	if allocator.procedure == nil {
		return false, provider_failure(.Initialize, .Allocation, language.id)
	}
	if valid, definition_failure := provider_definition_validate(factory, .Factory, language.id); !valid {
		definition_failure.operation = .Initialize
		return false, definition_failure
	}
	state, allocation_error := new(Provider_Registry_State, allocator)
	if allocation_error != nil {
		return false, provider_failure(.Initialize, .Allocation, language.id)
	}
	state^ = Provider_Registry_State {
		registry_id = registry_id,
		registry_generation = 1,
		language = language,
		next_provider_id = 1,
		allocator = allocator,
	}
	factory_handle, registered := provider_register(state, factory, .Factory, .Confirmed)
	if !registered {
		free(state, allocator)
		return false, provider_failure(.Initialize, .Provider_Limit, language.id)
	}
	state.active = factory_handle
	state.factory = factory_handle
	state.selection_state = .Factory
	registry.state = state
	return true, {}
}

/* provider_registry_close releases registry storage and invalidates every provider. */
provider_registry_close :: proc(
	registry: ^Provider_Registry,
) -> (ok: bool, failure: Failure) {
	state := provider_registry_state(registry)
	if state == nil {
		return false, provider_failure(.Close, .Invalid_Registry)
	}
	for &slot in state.providers {
		if slot.live {
			slot.descriptor.state = .Closed
			slot = {}
		}
	}
	allocator := state.allocator
	free(state, allocator)
	registry^ = Provider_Registry{closed = true}
	return true, {}
}

/* provider_registry_selection copies the exact single-active selection. */
provider_registry_selection :: proc(
	registry: ^Provider_Registry,
) -> (selection: Provider_Selection, ok: bool, failure: Failure) {
	state := provider_registry_state(registry)
	if state == nil {
		return {}, false, provider_failure(.Inspect, .Invalid_Registry)
	}
	return provider_selection(state), true, {}
}

/* provider_registry_provider copies one exact provider descriptor. */
provider_registry_provider :: proc(
	registry: ^Provider_Registry,
	handle: Provider_Handle,
) -> (provider: Provider_Descriptor, ok: bool, failure: Failure) {
	state := provider_registry_state(registry)
	if state == nil {
		return {}, false, provider_failure(.Inspect, .Invalid_Registry, handle.language_id, handle)
	}
	slot, resolve_failure := provider_resolve(state, handle)
	if resolve_failure.code != .None do return {}, false, resolve_failure
	return slot.descriptor, true, {}
}

/* provider_registry_register_native copies one inactive synthetic provider. */
provider_registry_register_native :: proc(
	registry: ^Provider_Registry,
	definition: Provider_Definition,
) -> (provider: Provider_Handle, ok: bool, failure: Failure) {
	state := provider_registry_state(registry)
	if state == nil {
		return {}, false, provider_failure(.Register, .Invalid_Registry)
	}
	if valid, definition_failure := provider_definition_validate(definition, .Native, state.language.id); !valid {
		return {}, false, definition_failure
	}
	for &slot in state.providers {
		if slot.live && provider_name_string(&slot.descriptor.name) == definition.name {
			return {}, false, provider_failure(
				.Register,
				.Duplicate_Provider,
				state.language.id,
				slot.descriptor.handle,
			)
		}
	}
	if state.live_count >= MAX_PROVIDERS {
		failure = provider_failure(.Register, .Provider_Limit, state.language.id)
		failure.limit = MAX_PROVIDERS
		failure.actual = u64(state.live_count) + 1
		return {}, false, failure
	}
	if !provider_generation_available(state) {
		return {}, false, provider_failure(.Register, .Generation_Limit, state.language.id)
	}
	registered: bool
	provider, registered = provider_register(state, definition, .Native, .Registered)
	if !registered {
		return {}, false, provider_failure(.Register, .Provider_Limit, state.language.id)
	}
	state.registry_generation += 1
	return provider, true, {}
}

/* provider_registry_confirm_native confirms one registered synthetic provider. */
provider_registry_confirm_native :: proc(
	registry: ^Provider_Registry,
	handle: Provider_Handle,
) -> (provider: Provider_Handle, ok: bool, failure: Failure) {
	state := provider_registry_state(registry)
	if state == nil {
		return {}, false, provider_failure(.Confirm, .Invalid_Registry, handle.language_id, handle)
	}
	slot, resolve_failure := provider_resolve(state, handle)
	if resolve_failure.code != .None {
		resolve_failure.operation = .Confirm
		return {}, false, resolve_failure
	}
	if slot.descriptor.kind != .Native || slot.descriptor.state != .Registered {
		return {}, false, provider_failure(.Confirm, .Invalid_Provider, state.language.id, handle)
	}
	if slot.descriptor.handle.provider_generation == Provider_Generation(max(u64)) ||
	   state.registry_generation == Registry_Generation(max(u64)) {
		return {}, false, provider_failure(.Confirm, .Generation_Limit, state.language.id, handle)
	}
	slot.descriptor.handle.provider_generation += 1
	slot.descriptor.state = .Confirmed
	state.registry_generation += 1
	return slot.descriptor.handle, true, {}
}

/* provider_registry_replace atomically selects one confirmed native generation. */
provider_registry_replace :: proc(
	registry: ^Provider_Registry,
	expected: Provider_Selection,
	handle: Provider_Handle,
) -> (selection: Provider_Selection, ok: bool, failure: Failure) {
	state := provider_registry_state(registry)
	if state == nil {
		return {}, false, provider_failure(.Replace, .Invalid_Registry, handle.language_id, handle)
	}
	if !provider_selection_matches(state, expected) {
		return {}, false, provider_failure(.Replace, .Stale_Selection, state.language.id, handle)
	}
	slot, resolve_failure := provider_resolve(state, handle)
	if resolve_failure.code != .None {
		resolve_failure.operation = .Replace
		return {}, false, resolve_failure
	}
	if slot.descriptor.kind != .Native {
		return {}, false, provider_failure(.Replace, .Invalid_Provider, state.language.id, handle)
	}
	if slot.descriptor.state != .Confirmed {
		return {}, false, provider_failure(.Replace, .Provider_Not_Confirmed, state.language.id, handle)
	}
	if state.registry_generation == Registry_Generation(max(u64)) {
		return {}, false, provider_failure(.Replace, .Generation_Limit, state.language.id, handle)
	}
	state.active = handle
	state.selection_state = .Replacement
	state.registry_generation += 1
	return provider_selection(state), true, {}
}

/* provider_registry_disable atomically removes the active provider selection. */
provider_registry_disable :: proc(
	registry: ^Provider_Registry,
	expected: Provider_Selection,
) -> (selection: Provider_Selection, ok: bool, failure: Failure) {
	state := provider_registry_state(registry)
	if state == nil {
		return {}, false, provider_failure(.Disable, .Invalid_Registry)
	}
	if !provider_selection_matches(state, expected) {
		return {}, false, provider_failure(.Disable, .Stale_Selection, state.language.id)
	}
	if state.registry_generation == Registry_Generation(max(u64)) {
		return {}, false, provider_failure(.Disable, .Generation_Limit, state.language.id)
	}
	state.active = {}
	state.selection_state = .Disabled
	state.registry_generation += 1
	return provider_selection(state), true, {}
}

/* provider_registry_restore selects the maintained confirmed factory provider. */
provider_registry_restore :: proc(
	registry: ^Provider_Registry,
	expected: Provider_Selection,
) -> (selection: Provider_Selection, ok: bool, failure: Failure) {
	state := provider_registry_state(registry)
	if state == nil {
		return {}, false, provider_failure(.Restore, .Invalid_Registry)
	}
	if !provider_selection_matches(state, expected) {
		return {}, false, provider_failure(.Restore, .Stale_Selection, state.language.id)
	}
	factory, resolve_failure := provider_resolve(state, state.factory)
	if resolve_failure.code != .None || factory.descriptor.state != .Confirmed {
		return {}, false, provider_failure(.Restore, .Factory_Provider_Required, state.language.id, state.factory)
	}
	if state.registry_generation == Registry_Generation(max(u64)) {
		return {}, false, provider_failure(.Restore, .Generation_Limit, state.language.id)
	}
	state.active = state.factory
	state.selection_state = .Restored
	state.registry_generation += 1
	return provider_selection(state), true, {}
}

/* provider_registry_fail_active contains failure and restores factory or plain text. */
provider_registry_fail_active :: proc(
	registry: ^Provider_Registry,
	expected: Provider_Selection,
	handle: Provider_Handle,
) -> (selection: Provider_Selection, ok: bool, failure: Failure) {
	state := provider_registry_state(registry)
	if state == nil {
		return {}, false, provider_failure(.Fail, .Invalid_Registry, handle.language_id, handle)
	}
	if !provider_selection_matches(state, expected) {
		return {}, false, provider_failure(.Fail, .Stale_Selection, state.language.id, handle)
	}
	if state.active != handle {
		return {}, false, provider_failure(.Fail, .Provider_Not_Active, state.language.id, handle)
	}
	slot, resolve_failure := provider_resolve(state, handle)
	if resolve_failure.code != .None {
		resolve_failure.operation = .Fail
		return {}, false, resolve_failure
	}
	if slot.descriptor.handle.provider_generation == Provider_Generation(max(u64)) ||
	   state.registry_generation == Registry_Generation(max(u64)) {
		return {}, false, provider_failure(.Fail, .Generation_Limit, state.language.id, handle)
	}
	slot.descriptor.handle.provider_generation += 1
	slot.descriptor.state = .Failed
	factory, factory_failure := provider_resolve(state, state.factory)
	if handle != state.factory && factory_failure.code == .None && factory.descriptor.state == .Confirmed {
		state.active = state.factory
		state.selection_state = .Restored
	} else {
		state.active = {}
		state.selection_state = .Disabled
	}
	state.registry_generation += 1
	return provider_selection(state), true, {}
}

/* provider_registry_close_native removes one provider and restores factory when active. */
provider_registry_close_native :: proc(
	registry: ^Provider_Registry,
	expected: Provider_Selection,
	handle: Provider_Handle,
) -> (selection: Provider_Selection, ok: bool, failure: Failure) {
	state := provider_registry_state(registry)
	if state == nil {
		return {}, false, provider_failure(.Close, .Invalid_Registry, handle.language_id, handle)
	}
	if !provider_selection_matches(state, expected) {
		return {}, false, provider_failure(.Close, .Stale_Selection, state.language.id, handle)
	}
	slot, resolve_failure := provider_resolve(state, handle)
	if resolve_failure.code != .None {
		resolve_failure.operation = .Close
		return {}, false, resolve_failure
	}
	if slot.descriptor.kind != .Native {
		return {}, false, provider_failure(.Close, .Invalid_Provider, state.language.id, handle)
	}
	if state.registry_generation == Registry_Generation(max(u64)) {
		return {}, false, provider_failure(.Close, .Generation_Limit, state.language.id, handle)
	}
	was_active := state.active == handle
	slot.descriptor.state = .Closed
	slot^ = {}
	state.live_count -= 1
	state.native_count -= 1
	if was_active {
		factory, factory_failure := provider_resolve(state, state.factory)
		if factory_failure.code == .None && factory.descriptor.state == .Confirmed {
			state.active = state.factory
			state.selection_state = .Restored
		} else {
			state.active = {}
			state.selection_state = .Disabled
		}
	}
	state.registry_generation += 1
	return provider_selection(state), true, {}
}

/* provider_registry_stats copies exact provider accounting. */
provider_registry_stats :: proc(
	registry: ^Provider_Registry,
) -> (stats: Provider_Registry_Stats, ok: bool, failure: Failure) {
	state := provider_registry_state(registry)
	if state == nil {
		return {}, false, provider_failure(.Inspect, .Invalid_Registry)
	}
	return Provider_Registry_Stats {
		registry_id = state.registry_id,
		registry_generation = state.registry_generation,
		language = state.language,
		live_providers = state.live_count,
		native_providers = state.native_count,
		disabled = state.selection_state == .Disabled,
	}, true, {}
}

@(private)
provider_register :: proc(
	state: ^Provider_Registry_State,
	definition: Provider_Definition,
	kind: Provider_Kind,
	provider_state: Provider_State,
) -> (handle: Provider_Handle, ok: bool) {
	if state == nil || state.live_count >= MAX_PROVIDERS do return {}, false
	for &slot in state.providers {
		if slot.live do continue
		handle = Provider_Handle {
			registry_id = state.registry_id,
			language_id = state.language.id,
			provider_id = state.next_provider_id,
			provider_generation = 1,
		}
		slot.descriptor = Provider_Descriptor {
			handle = handle,
			kind = kind,
			state = provider_state,
			name = provider_name_copy(definition.name),
			parser_name = parser_name_copy(definition.parser_name),
			grammar_abi = definition.grammar_abi,
			capabilities = definition.capabilities,
			query_generation = 1,
			provenance = provenance_copy(definition.provenance),
		}
		slot.live = true
		state.next_provider_id += 1
		state.live_count += 1
		if kind == .Native do state.native_count += 1
		return handle, true
	}
	return {}, false
}

@(private)
provider_resolve :: proc(
	state: ^Provider_Registry_State,
	handle: Provider_Handle,
) -> (slot: ^Provider_Slot, failure: Failure) {
	if state == nil || handle.registry_id != state.registry_id ||
	   handle.language_id != state.language.id || handle.provider_id == Provider_ID(0) {
		return nil, provider_failure(.Inspect, .Invalid_Provider, handle.language_id, handle)
	}
	for &candidate in state.providers {
		if !candidate.live || candidate.descriptor.handle.provider_id != handle.provider_id do continue
		if candidate.descriptor.handle != handle {
			return nil, provider_failure(.Inspect, .Stale_Provider, state.language.id, handle)
		}
		return &candidate, {}
	}
	return nil, provider_failure(.Inspect, .Stale_Provider, state.language.id, handle)
}

@(private)
provider_selection :: proc(state: ^Provider_Registry_State) -> Provider_Selection {
	return Provider_Selection {
		registry_id = state.registry_id,
		registry_generation = state.registry_generation,
		language = state.language,
		state = state.selection_state,
		active = state.active,
		factory = state.factory,
	}
}

@(private)
provider_selection_matches :: proc(
	state: ^Provider_Registry_State,
	expected: Provider_Selection,
) -> bool {
	return state != nil && expected == provider_selection(state)
}

@(private)
provider_registry_state :: proc(registry: ^Provider_Registry) -> ^Provider_Registry_State {
	if registry == nil || registry.state == nil || registry.closed do return nil
	return cast(^Provider_Registry_State)registry.state
}

@(private)
provider_generation_available :: proc(state: ^Provider_Registry_State) -> bool {
	return state != nil && state.next_provider_id != Provider_ID(0) &&
		state.registry_generation != Registry_Generation(max(u64))
}

@(private)
language_identity_is_valid :: proc(language: Language_Identity) -> bool {
	return language.id != Language_ID(0) && language.generation != Language_Generation(0) &&
		language.name.length > 0 && language.name.length <= MAX_LANGUAGE_NAME_BYTES
}

@(private)
provider_definition_validate :: proc(
	definition: Provider_Definition,
	kind: Provider_Kind,
	language_id: Language_ID,
) -> (ok: bool, failure: Failure) {
	if kind != .Factory && kind != .Native {
		return false, provider_failure(.Register, .Invalid_Provider, language_id)
	}
	if len(definition.name) == 0 || len(definition.name) > MAX_PROVIDER_NAME_BYTES {
		failure = provider_failure(.Register, .Provider_Name_Limit, language_id)
		failure.limit = MAX_PROVIDER_NAME_BYTES
		failure.actual = u64(len(definition.name))
		return false, failure
	}
	if len(definition.parser_name) == 0 || len(definition.parser_name) > MAX_PARSER_NAME_BYTES {
		failure = provider_failure(.Register, .Parser_Name_Limit, language_id)
		failure.limit = MAX_PARSER_NAME_BYTES
		failure.actual = u64(len(definition.parser_name))
		return false, failure
	}
	if len(definition.provenance) == 0 || len(definition.provenance) > MAX_PROVENANCE_BYTES {
		failure = provider_failure(.Register, .Provenance_Limit, language_id)
		failure.limit = MAX_PROVENANCE_BYTES
		failure.actual = u64(len(definition.provenance))
		return false, failure
	}
	if definition.grammar_abi == 0 || definition.capabilities == {} {
		return false, provider_failure(.Register, .Invalid_Provider, language_id)
	}
	return true, {}
}

@(private)
provider_name_copy :: proc(value: string) -> Provider_Name {
	result: Provider_Name
	result.length = u16(copy(result.bytes[:], transmute([]u8)value))
	return result
}

@(private)
parser_name_copy :: proc(value: string) -> Parser_Name {
	result: Parser_Name
	result.length = u16(copy(result.bytes[:], transmute([]u8)value))
	return result
}

@(private)
provenance_copy :: proc(value: string) -> Provenance_Text {
	result: Provenance_Text
	result.length = u16(copy(result.bytes[:], transmute([]u8)value))
	return result
}

@(private)
provider_name_string :: proc(value: ^Provider_Name) -> string {
	if value == nil do return ""
	return string(value.bytes[:value.length])
}

@(private)
provider_failure :: proc(
	operation: Operation,
	code: Failure_Code,
	language_id := Language_ID(0),
	provider := Provider_Handle{},
) -> Failure {
	return Failure {
		operation = operation,
		code = code,
		language_id = language_id,
		provider = provider,
	}
}
