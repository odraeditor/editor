// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

// Package theme_reference provides an independent bounded model of the theme
// registry lifecycle and its retained-resource ownership.
package theme_reference

import "base:runtime"

MAX_PROVIDERS :: 64
MAX_DEFINITIONS :: 64
MAX_IDENTITY_BYTES :: 96
MAX_DISPLAY_NAME_BYTES :: 96
MAX_PROVIDER_NAME_BYTES :: 96
MAX_PROVENANCE_BYTES :: 256
MAX_STYLES :: 64
CURRENT_STYLE_ROLES :: 27
MAX_RETAINED_BYTES :: 1_024 * 1_024
MAX_PROPOSAL_BYTES :: 64 * 1_024
FACTORY_DEFINITIONS :: 5
FACTORY_PAYLOAD_BYTES :: 512

Provider_State :: enum u8 {
	Invalid,
	Confirmed,
	Failed,
	Closed,
}

Definition_State :: enum u8 {
	Invalid,
	Proposed,
	Confirmed,
	Failed,
	Closed,
}

Failure_Code :: enum u8 {
	None,
	Invalid_Model,
	Invalid_Proposal,
	Invalid_Provider,
	Invalid_Definition,
	Duplicate_Identity,
	Provider_Limit,
	Definition_Limit,
	Identity_Limit,
	Display_Name_Limit,
	Provider_Name_Limit,
	Provenance_Limit,
	Style_Limit,
	Proposal_Limit,
	Retained_Bytes_Limit,
	Definition_Not_Confirmed,
	Factory_Immutable,
	Stale_Registry,
	Stale_Selection,
	Allocation,
}

Provider_Handle :: struct {
	id:         u16,
	generation: u64,
}

Definition_Handle :: struct {
	id:                  u16,
	generation:          u64,
	provider:            Provider_Handle,
}

Proposal :: struct {
	provider_key:       u32,
	identity_key:       u32,
	identity_bytes:     u16,
	display_name_bytes: u16,
	provider_name_bytes: u16,
	provenance_bytes:   u16,
	style_count:        u16,
	retained_bytes:     u32,
}

Limits :: struct {
	providers:          u16,
	definitions:        u16,
	retained_bytes:     u64,
	proposal_bytes:     u64,
}

DEFAULT_LIMITS :: Limits {
	providers = MAX_PROVIDERS,
	definitions = MAX_DEFINITIONS,
	retained_bytes = MAX_RETAINED_BYTES,
	proposal_bytes = MAX_PROPOSAL_BYTES,
}

Failure :: struct {
	code:   Failure_Code,
	limit:  u64,
	actual: u64,
}

Selection :: struct {
	registry_generation:  u64,
	selection_generation: u64,
	active:               Definition_Handle,
	fallback:             Definition_Handle,
	baseline:             Definition_Handle,
}

Provider :: struct {
	handle: Provider_Handle,
	key:    u32,
	state:  Provider_State,
	live:   bool,
}

Definition :: struct {
	handle:        Definition_Handle,
	identity_key:  u32,
	state:         Definition_State,
	retained_data: []byte,
	live:          bool,
}

State :: struct {
	providers:          [MAX_PROVIDERS]Provider,
	definitions:        [MAX_DEFINITIONS]Definition,
	provider_count:     u16,
	definition_count:   u16,
	retained_bytes:     u64,
	next_provider_id:   u16,
	next_definition_id: u16,
	selection:          Selection,
	limits:             Limits,
	allocator:          runtime.Allocator,
}

Model :: struct {
	state:  ^State,
	closed: bool,
}

model_init :: proc(
	limits := DEFAULT_LIMITS,
	allocator := context.allocator,
) -> (model: Model, ok: bool, failure: Failure) {
	if allocator.procedure == nil || !limits_valid(limits) {
		return {}, false, Failure{code = .Invalid_Model}
	}
	state, allocation_error := new(State, allocator)
	if allocation_error != nil {
		return {}, false, Failure{code = .Allocation}
	}
	state^ = State {
		next_provider_id = 2,
		next_definition_id = FACTORY_DEFINITIONS + 1,
		limits = limits,
		allocator = allocator,
	}
	factory := Provider_Handle{id = 1, generation = 1}
	state.providers[0] = Provider {
		handle = factory,
		key = 1,
		state = .Confirmed,
		live = true,
	}
	state.provider_count = 1

	for index in 0 ..< FACTORY_DEFINITIONS {
		data, data_error := make([]byte, FACTORY_PAYLOAD_BYTES, allocator)
		if data_error != nil {
			state_release(state)
			free(state, allocator)
			return {}, false, Failure{code = .Allocation}
		}
		handle := Definition_Handle {
			id = u16(index + 1),
			generation = 1,
			provider = factory,
		}
		state.definitions[index] = Definition {
			handle = handle,
			identity_key = u32(index + 1),
			state = .Confirmed,
			retained_data = data,
			live = true,
		}
		state.definition_count += 1
		state.retained_bytes += FACTORY_PAYLOAD_BYTES
	}
	state.selection = Selection {
		registry_generation = 1,
		selection_generation = 1,
		active = state.definitions[3].handle,
		fallback = state.definitions[3].handle,
		baseline = state.definitions[4].handle,
	}
	model.state = state
	return model, true, {}
}

model_close :: proc(model: ^Model) -> bool {
	if model == nil || model.state == nil || model.closed {
		return false
	}
	state := model.state
	allocator := state.allocator
	state_release(state)
	free(state, allocator)
	model^ = Model{closed = true}
	return true
}

model_selection :: proc(model: ^Model) -> (Selection, bool) {
	if !model_live(model) {
		return {}, false
	}
	return model.state.selection, true
}

model_propose :: proc(
	model: ^Model,
	proposal: Proposal,
) -> (handle: Definition_Handle, ok: bool, failure: Failure) {
	if !model_live(model) {
		return {}, false, Failure{code = .Invalid_Model}
	}
	state := model.state
	if valid, proposal_failure := proposal_validate(state, proposal); !valid {
		return {}, false, proposal_failure
	}
	if definition_by_identity(state, proposal.identity_key) != nil {
		return {}, false, Failure{code = .Duplicate_Identity}
	}
	provider := provider_by_key(state, proposal.provider_key)
	needs_provider := provider == nil
	if needs_provider && state.provider_count >= state.limits.providers {
		return {}, false, Failure {
			code = .Provider_Limit,
			limit = u64(state.limits.providers),
			actual = u64(state.provider_count) + 1,
		}
	}
	if state.definition_count >= state.limits.definitions {
		return {}, false, Failure {
			code = .Definition_Limit,
			limit = u64(state.limits.definitions),
			actual = u64(state.definition_count) + 1,
		}
	}
	retained := u64(proposal.retained_bytes)
	if state.retained_bytes > state.limits.retained_bytes - retained {
		return {}, false, Failure {
			code = .Retained_Bytes_Limit,
			limit = state.limits.retained_bytes,
			actual = state.retained_bytes + retained,
		}
	}
	data, allocation_error := make([]byte, int(proposal.retained_bytes), state.allocator)
	if allocation_error != nil {
		return {}, false, Failure{code = .Allocation}
	}
	if needs_provider {
		provider = provider_free_slot(state)
		if provider == nil {
			delete(data, state.allocator)
			return {}, false, Failure{code = .Provider_Limit}
		}
		provider.handle = Provider_Handle{id = state.next_provider_id, generation = 1}
		provider.key = proposal.provider_key
		provider.state = .Confirmed
		provider.live = true
		state.next_provider_id += 1
		state.provider_count += 1
	}
	definition := definition_free_slot(state)
	if definition == nil {
		delete(data, state.allocator)
		return {}, false, Failure{code = .Definition_Limit}
	}
	handle = Definition_Handle {
		id = state.next_definition_id,
		generation = 1,
		provider = provider.handle,
	}
	definition^ = Definition {
		handle = handle,
		identity_key = proposal.identity_key,
		state = .Proposed,
		retained_data = data,
		live = true,
	}
	state.next_definition_id += 1
	state.definition_count += 1
	state.retained_bytes += retained
	state.selection.registry_generation += 1
	return handle, true, {}
}

model_confirm :: proc(
	model: ^Model,
	expected_registry: u64,
	handle: Definition_Handle,
) -> (confirmed: Definition_Handle, ok: bool, failure: Failure) {
	if !model_live(model) {
		return {}, false, Failure{code = .Invalid_Model}
	}
	state := model.state
	if state.selection.registry_generation != expected_registry {
		return {}, false, Failure{code = .Stale_Registry}
	}
	definition := definition_resolve(state, handle)
	if definition == nil || definition.state != .Proposed {
		return {}, false, Failure{code = .Invalid_Definition}
	}
	definition.handle.generation += 1
	definition.state = .Confirmed
	state.selection.registry_generation += 1
	return definition.handle, true, {}
}

model_select :: proc(
	model: ^Model,
	expected_selection: u64,
	handle: Definition_Handle,
) -> (selection: Selection, ok: bool, failure: Failure) {
	if !model_live(model) {
		return {}, false, Failure{code = .Invalid_Model}
	}
	state := model.state
	if state.selection.selection_generation != expected_selection {
		return {}, false, Failure{code = .Stale_Selection}
	}
	definition := definition_resolve(state, handle)
	if definition == nil {
		return {}, false, Failure{code = .Invalid_Definition}
	}
	if definition.state != .Confirmed {
		return {}, false, Failure{code = .Definition_Not_Confirmed}
	}
	state.selection.active = definition.handle
	state.selection.registry_generation += 1
	state.selection.selection_generation += 1
	return state.selection, true, {}
}

model_replace :: proc(
	model: ^Model,
	expected_selection: u64,
	handle: Definition_Handle,
	retained_bytes: u32,
) -> (selection: Selection, replacement: Definition_Handle, ok: bool, failure: Failure) {
	if !model_live(model) {
		return {}, {}, false, Failure{code = .Invalid_Model}
	}
	state := model.state
	if state.selection.selection_generation != expected_selection {
		return {}, {}, false, Failure{code = .Stale_Selection}
	}
	definition := definition_resolve(state, handle)
	if definition == nil || definition.state != .Confirmed {
		return {}, {}, false, Failure{code = .Definition_Not_Confirmed}
	}
	if definition.handle.provider == state.providers[0].handle {
		return {}, {}, false, Failure{code = .Factory_Immutable}
	}
	if retained_bytes == 0 || retained_bytes > MAX_PROPOSAL_BYTES {
		return {}, {}, false, Failure {
			code = .Proposal_Limit,
			limit = state.limits.proposal_bytes,
			actual = u64(retained_bytes),
		}
	}
	prior_bytes := u64(len(definition.retained_data))
	new_bytes := u64(retained_bytes)
	remaining := state.retained_bytes - prior_bytes
	if remaining > state.limits.retained_bytes - new_bytes {
		return {}, {}, false, Failure {
			code = .Retained_Bytes_Limit,
			limit = state.limits.retained_bytes,
			actual = remaining + new_bytes,
		}
	}
	data, allocation_error := make([]byte, int(retained_bytes), state.allocator)
	if allocation_error != nil {
		return {}, {}, false, Failure{code = .Allocation}
	}
	delete(definition.retained_data, state.allocator)
	definition.retained_data = data
	definition.handle.generation += 1
	replacement = definition.handle
	state.retained_bytes = remaining + new_bytes
	state.selection.active = replacement
	state.selection.registry_generation += 1
	state.selection.selection_generation += 1
	return state.selection, replacement, true, {}
}

model_restore_fallback :: proc(
	model: ^Model,
	expected_selection: u64,
) -> (Selection, bool, Failure) {
	if !model_live(model) {
		return {}, false, Failure{code = .Invalid_Model}
	}
	return model_select(model, expected_selection, model.state.selection.fallback)
}

model_disable :: proc(
	model: ^Model,
	expected_selection: u64,
) -> (Selection, bool, Failure) {
	if !model_live(model) {
		return {}, false, Failure{code = .Invalid_Model}
	}
	return model_select(model, expected_selection, model.state.selection.baseline)
}

model_fail_provider :: proc(
	model: ^Model,
	expected_selection: u64,
	handle: Provider_Handle,
) -> (selection: Selection, ok: bool, failure: Failure) {
	if !model_live(model) {
		return {}, false, Failure{code = .Invalid_Model}
	}
	state := model.state
	if state.selection.selection_generation != expected_selection {
		return {}, false, Failure{code = .Stale_Selection}
	}
	provider := provider_resolve(state, handle)
	if provider == nil || provider.handle == state.providers[0].handle {
		return {}, false, Failure{code = .Invalid_Provider}
	}
	active_failed := state.selection.active.provider == handle
	provider.state = .Failed
	definitions_release_provider(state, handle, .Failed)
	state.selection.registry_generation += 1
	if active_failed {
		state.selection.active = state.selection.fallback
		state.selection.selection_generation += 1
	}
	return state.selection, true, {}
}

model_close_provider :: proc(
	model: ^Model,
	expected_selection: u64,
	handle: Provider_Handle,
) -> (selection: Selection, ok: bool, failure: Failure) {
	if !model_live(model) {
		return {}, false, Failure{code = .Invalid_Model}
	}
	state := model.state
	if state.selection.selection_generation != expected_selection {
		return {}, false, Failure{code = .Stale_Selection}
	}
	provider := provider_resolve(state, handle)
	if provider == nil || provider.handle == state.providers[0].handle {
		return {}, false, Failure{code = .Invalid_Provider}
	}
	active_closed := state.selection.active.provider == handle
	if active_closed {
		state.selection.active = state.selection.fallback
		state.selection.selection_generation += 1
	}
	definitions_release_provider(state, handle, .Closed)
	provider.state = .Closed
	provider.live = false
	state.provider_count -= 1
	state.selection.registry_generation += 1
	return state.selection, true, {}
}

model_valid :: proc(model: ^Model) -> bool {
	if !model_live(model) {
		return false
	}
	state := model.state
	providers, definitions: u16
	retained: u64
	for provider in state.providers {
		if provider.live {
			providers += 1
			if provider.handle.id == 0 || provider.handle.generation == 0 ||
			   provider.key == 0 ||
			   (provider.state != .Confirmed && provider.state != .Failed) {
				return false
			}
		}
	}
	for definition, index in state.definitions {
		if !definition.live {
			continue
		}
		definitions += 1
		retained += u64(len(definition.retained_data))
		if definition.handle.id == 0 || definition.handle.generation == 0 ||
		   definition.identity_key == 0 || len(definition.retained_data) == 0 ||
		   provider_resolve(state, definition.handle.provider) == nil {
			return false
		}
		for prior in 0 ..< index {
			if state.definitions[prior].live &&
			   state.definitions[prior].identity_key == definition.identity_key {
				return false
			}
		}
	}
	active := definition_resolve(state, state.selection.active)
	fallback := definition_resolve(state, state.selection.fallback)
	baseline := definition_resolve(state, state.selection.baseline)
	return providers == state.provider_count && definitions == state.definition_count &&
	       retained == state.retained_bytes && retained <= state.limits.retained_bytes &&
	       active != nil && active.state == .Confirmed &&
	       fallback != nil && fallback.state == .Confirmed &&
	       baseline != nil && baseline.state == .Confirmed &&
	       state.selection.registry_generation > 0 &&
	       state.selection.selection_generation > 0
}

@(private)
limits_valid :: proc(limits: Limits) -> bool {
	return limits.providers >= 1 && limits.providers <= MAX_PROVIDERS &&
	       limits.definitions >= FACTORY_DEFINITIONS && limits.definitions <= MAX_DEFINITIONS &&
	       limits.retained_bytes >= FACTORY_DEFINITIONS * FACTORY_PAYLOAD_BYTES &&
	       limits.retained_bytes <= MAX_RETAINED_BYTES &&
	       limits.proposal_bytes > 0 && limits.proposal_bytes <= MAX_PROPOSAL_BYTES
}

@(private)
proposal_validate :: proc(state: ^State, proposal: Proposal) -> (bool, Failure) {
	if proposal.provider_key == 0 || proposal.identity_key == 0 ||
	   proposal.identity_bytes == 0 || proposal.display_name_bytes == 0 ||
	   proposal.provider_name_bytes == 0 || proposal.provenance_bytes == 0 ||
	   proposal.style_count != CURRENT_STYLE_ROLES || proposal.retained_bytes == 0 {
		return false, Failure{code = .Invalid_Proposal}
	}
	checks := [?]struct {actual, limit: u64, code: Failure_Code} {
		{u64(proposal.identity_bytes), MAX_IDENTITY_BYTES, .Identity_Limit},
		{u64(proposal.display_name_bytes), MAX_DISPLAY_NAME_BYTES, .Display_Name_Limit},
		{u64(proposal.provider_name_bytes), MAX_PROVIDER_NAME_BYTES, .Provider_Name_Limit},
		{u64(proposal.provenance_bytes), MAX_PROVENANCE_BYTES, .Provenance_Limit},
		{u64(proposal.style_count), MAX_STYLES, .Style_Limit},
		{u64(proposal.retained_bytes), state.limits.proposal_bytes, .Proposal_Limit},
	}
	for check in checks {
		if check.actual > check.limit {
			return false, Failure{code = check.code, limit = check.limit, actual = check.actual}
		}
	}
	return true, {}
}

@(private)
model_live :: proc(model: ^Model) -> bool {
	return model != nil && model.state != nil && !model.closed
}

@(private)
provider_free_slot :: proc(state: ^State) -> ^Provider {
	for &provider in state.providers {
		if !provider.live {
			return &provider
		}
	}
	return nil
}

@(private)
definition_free_slot :: proc(state: ^State) -> ^Definition {
	for &definition in state.definitions {
		if !definition.live {
			return &definition
		}
	}
	return nil
}

@(private)
provider_by_key :: proc(state: ^State, key: u32) -> ^Provider {
	for &provider in state.providers {
		if provider.live && provider.key == key {
			return &provider
		}
	}
	return nil
}

@(private)
provider_resolve :: proc(state: ^State, handle: Provider_Handle) -> ^Provider {
	for &provider in state.providers {
		if provider.live && provider.handle == handle {
			return &provider
		}
	}
	return nil
}

@(private)
definition_by_identity :: proc(state: ^State, identity_key: u32) -> ^Definition {
	for &definition in state.definitions {
		if definition.live && definition.identity_key == identity_key {
			return &definition
		}
	}
	return nil
}

@(private)
definition_resolve :: proc(state: ^State, handle: Definition_Handle) -> ^Definition {
	for &definition in state.definitions {
		if definition.live && definition.handle == handle {
			return &definition
		}
	}
	return nil
}

@(private)
definitions_release_provider :: proc(
	state: ^State,
	handle: Provider_Handle,
	final_state: Definition_State,
) {
	for &definition in state.definitions {
		if !definition.live || definition.handle.provider != handle {
			continue
		}
		state.retained_bytes -= u64(len(definition.retained_data))
		delete(definition.retained_data, state.allocator)
		definition.retained_data = nil
		definition.state = final_state
		definition.live = false
		state.definition_count -= 1
	}
}

@(private)
state_release :: proc(state: ^State) {
	for &definition in state.definitions {
		if definition.retained_data != nil {
			delete(definition.retained_data, state.allocator)
			definition.retained_data = nil
		}
		definition.live = false
	}
	state.retained_bytes = 0
	state.definition_count = 0
}
