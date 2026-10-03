// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package theme

import "../ui"
import "base:runtime"

@(private)
Provider_Slot :: struct {
	descriptor: Provider_Descriptor,
	live:       bool,
}

@(private)
Definition_Slot :: struct {
	descriptor: Definition_Descriptor,
	styles:     [MAX_STYLES]ui.Style_Definition,
	live:       bool,
}

@(private)
Registry_State :: struct {
	registry_id:          Registry_ID,
	registry_generation:  Registry_Generation,
	selection_generation: Selection_Generation,
	selection_state:      Selection_State,
	active:               Definition_Handle,
	fallback:             Definition_Handle,
	baseline:             Definition_Handle,
	next_provider_id:     Provider_ID,
	next_definition_id:   Definition_ID,
	providers:            [MAX_PROVIDERS]Provider_Slot,
	definitions:          [MAX_DEFINITIONS]Definition_Slot,
	usage:                Resource_Usage,
	limits:               Resource_Limits,
	latest_failure:       Failure,
	allocator:            runtime.Allocator,
}

/* theme_registry_init copies five factory definitions and selects fallback. */
theme_registry_init :: proc(
	registry: ^Registry,
	registry_id: Registry_ID,
	factory_definitions: []Definition_Proposal,
	fallback_identity, baseline_identity: string,
	limits := DEFAULT_RESOURCE_LIMITS,
	allocator := context.allocator,
) -> (ok: bool, failure: Failure) {
	if registry == nil {
		return false, theme_failure(.Initialize, .Invalid_Registry)
	}
	registry^ = {}
	if registry_id == Registry_ID(0) || allocator.procedure == nil ||
	   !resource_limits_are_valid(limits) ||
	   len(factory_definitions) != FACTORY_DEFINITION_COUNT {
		return false, theme_failure(.Initialize, .Invalid_Registry)
	}
	if !theme_identity_is_valid(fallback_identity) ||
	   !theme_identity_is_valid(baseline_identity) ||
	   fallback_identity == baseline_identity {
		return false, theme_failure(.Initialize, .Invalid_Definition)
	}
	factory_provider_name := ""
	retained_bytes: u64
	for proposal, index in factory_definitions {
		if valid, proposal_failure := definition_proposal_validate(proposal, limits); !valid {
			proposal_failure.operation = .Initialize
			return false, proposal_failure
		}
		if index == 0 {
			factory_provider_name = proposal.provider_name
		} else if proposal.provider_name != factory_provider_name {
			return false, theme_failure(.Initialize, .Factory_Provider_Required)
		}
		for prior in 0 ..< index {
			if factory_definitions[prior].identity == proposal.identity {
				return false, theme_failure(.Initialize, .Duplicate_Definition)
			}
		}
		retained_bytes += definition_proposal_bytes(proposal)
	}
	if retained_bytes > limits.retained_definition_bytes {
		return false, theme_failure_with_limit(
			.Initialize,
			.Retained_Definition_Limit,
			limits.retained_definition_bytes,
			retained_bytes,
		)
	}
	state, allocation_error := new(Registry_State, allocator)
	if allocation_error != nil {
		return false, theme_failure(.Initialize, .Allocation)
	}
	state^ = Registry_State {
		registry_id = registry_id,
		registry_generation = 1,
		selection_generation = 1,
		selection_state = .Factory,
		next_provider_id = 2,
		next_definition_id = Definition_ID(FACTORY_DEFINITION_COUNT + 1),
		limits = limits,
		allocator = allocator,
	}
	factory_handle := Provider_Handle {
		registry_id = registry_id,
		provider_id = 1,
		provider_generation = 1,
	}
	state.providers[0] = Provider_Slot {
		descriptor = Provider_Descriptor {
			handle = factory_handle,
			kind = .Factory,
			state = .Confirmed,
			name = provider_name_copy(factory_provider_name),
		},
		live = true,
	}
	state.usage.providers = 1
	for proposal, index in factory_definitions {
		handle := Definition_Handle {
			registry_id = registry_id,
			provider_id = factory_handle.provider_id,
			provider_generation = factory_handle.provider_generation,
			definition_id = Definition_ID(index + 1),
			definition_generation = 1,
		}
		definition_slot_write(&state.definitions[index], handle, proposal, .Confirmed)
		state.usage.definitions += 1
		state.usage.retained_definition_bytes += state.definitions[index].descriptor.retained_bytes
		state.usage.preparation_peak_bytes = max(
			state.usage.preparation_peak_bytes,
			state.definitions[index].descriptor.retained_bytes,
		)
	}
	fallback := definition_by_name(state, fallback_identity)
	baseline := definition_by_name(state, baseline_identity)
	if fallback == nil || baseline == nil {
		free(state, allocator)
		return false, theme_failure(.Initialize, .Invalid_Definition)
	}
	state.fallback = fallback.descriptor.handle
	state.baseline = baseline.descriptor.handle
	state.active = state.fallback
	registry.state = state
	return true, {}
}

/* theme_registry_close releases registry storage and invalidates every handle. */
theme_registry_close :: proc(registry: ^Registry) -> (ok: bool, failure: Failure) {
	state := registry_state(registry)
	if state == nil {
		return false, registry_access_failure(registry, .Close)
	}
	allocator := state.allocator
	free(state, allocator)
	registry^ = Registry{closed = true}
	return true, {}
}

/* theme_registry_selection copies the exact session-wide selection. */
theme_registry_selection :: proc(
	registry: ^Registry,
) -> (selection: Selection, ok: bool, failure: Failure) {
	state := registry_state(registry)
	if state == nil {
		return {}, false, registry_access_failure(registry, .Inspect)
	}
	return registry_selection(state), true, {}
}

/* theme_registry_inspect copies exact occupancy, accounting, and policy. */
theme_registry_inspect :: proc(
	registry: ^Registry,
) -> (inspection: Registry_Inspection, ok: bool, failure: Failure) {
	state := registry_state(registry)
	if state == nil {
		return {}, false, registry_access_failure(registry, .Inspect)
	}
	inspection = Registry_Inspection {
		selection = registry_selection(state),
		usage = state.usage,
		limits = state.limits,
		latest_failure = state.latest_failure,
	}
	inspection.usage.inspection_bytes = u64(size_of(Registry_Inspection))
	if inspection.usage.inspection_bytes > state.limits.inspection_bytes {
		failure = theme_failure_with_limit(
			.Inspect,
			.Inspection_Limit,
			state.limits.inspection_bytes,
			inspection.usage.inspection_bytes,
		)
		state.latest_failure = failure
		return {}, false, failure
	}
	return inspection, true, {}
}

/* theme_registry_provider copies one exact provider descriptor. */
theme_registry_provider :: proc(
	registry: ^Registry,
	handle: Provider_Handle,
) -> (provider: Provider_Descriptor, ok: bool, failure: Failure) {
	state := registry_state(registry)
	if state == nil {
		return {}, false, registry_access_failure(registry, .Inspect)
	}
	slot, resolve_failure := provider_resolve(state, handle)
	if resolve_failure.code != .None {
		resolve_failure.operation = .Inspect
		state.latest_failure = resolve_failure
		return {}, false, resolve_failure
	}
	return slot.descriptor, true, {}
}

/* theme_registry_definition borrows one exact immutable definition generation. */
theme_registry_definition :: proc(
	registry: ^Registry,
	handle: Definition_Handle,
) -> (view: Definition_View, ok: bool, failure: Failure) {
	state := registry_state(registry)
	if state == nil {
		return {}, false, registry_access_failure(registry, .Inspect)
	}
	slot, resolve_failure := definition_resolve(state, handle)
	if resolve_failure.code != .None {
		resolve_failure.operation = .Inspect
		state.latest_failure = resolve_failure
		return {}, false, resolve_failure
	}
	return Definition_View {
		descriptor = slot.descriptor,
		styles = slot.styles[:slot.descriptor.style_count],
	}, true, {}
}

/* theme_registry_definition_by_name borrows one confirmed identity generation. */
theme_registry_definition_by_name :: proc(
	registry: ^Registry,
	identity: string,
) -> (view: Definition_View, ok: bool, failure: Failure) {
	state := registry_state(registry)
	if state == nil {
		return {}, false, registry_access_failure(registry, .Inspect)
	}
	slot := definition_by_name(state, identity)
	if slot == nil {
		failure = theme_failure(.Inspect, .Invalid_Definition)
		state.latest_failure = failure
		return {}, false, failure
	}
	return Definition_View {
		descriptor = slot.descriptor,
		styles = slot.styles[:slot.descriptor.style_count],
	}, true, {}
}

/* theme_registry_provider_at copies one live provider by stable inspection index. */
theme_registry_provider_at :: proc(
	registry: ^Registry,
	index: u16,
) -> (provider: Provider_Descriptor, ok: bool, failure: Failure) {
	state := registry_state(registry)
	if state == nil {
		return {}, false, registry_access_failure(registry, .Inspect)
	}
	live_index: u16
	for &slot in state.providers {
		if !slot.live do continue
		if live_index == index do return slot.descriptor, true, {}
		live_index += 1
	}
	failure = theme_failure(.Inspect, .Invalid_Provider)
	state.latest_failure = failure
	return {}, false, failure
}

/* theme_registry_definition_at borrows one live definition by inspection index. */
theme_registry_definition_at :: proc(
	registry: ^Registry,
	index: u16,
) -> (view: Definition_View, ok: bool, failure: Failure) {
	state := registry_state(registry)
	if state == nil {
		return {}, false, registry_access_failure(registry, .Inspect)
	}
	live_index: u16
	for &slot in state.definitions {
		if !slot.live do continue
		if live_index == index {
			return Definition_View {
				descriptor = slot.descriptor,
				styles = slot.styles[:slot.descriptor.style_count],
			}, true, {}
		}
		live_index += 1
	}
	failure = theme_failure(.Inspect, .Invalid_Definition)
	state.latest_failure = failure
	return {}, false, failure
}

/* theme_registry_propose copies one complete inactive Racket definition. */
theme_registry_propose :: proc(
	registry: ^Registry,
	expected_registry: Registry_Generation,
	proposal: Definition_Proposal,
) -> (definition: Definition_Handle, ok: bool, failure: Failure) {
	state := registry_state(registry)
	if state == nil {
		return {}, false, registry_access_failure(registry, .Propose)
	}
	if state.registry_generation != expected_registry {
		return {}, false, registry_reject(state, theme_failure(.Propose, .Stale_Registry))
	}
	if valid, proposal_failure := definition_proposal_validate(proposal, state.limits); !valid {
		return {}, false, registry_reject(state, proposal_failure)
	}
	if definition_by_name(state, proposal.identity) != nil {
		return {}, false, registry_reject(state, theme_failure(.Propose, .Duplicate_Definition))
	}
	provider := provider_by_name(state, proposal.provider_name)
	needs_provider := provider == nil
	if provider != nil && provider.descriptor.kind != .Racket {
		return {}, false, registry_reject(state, theme_failure(.Propose, .Duplicate_Provider))
	}
	if provider != nil && provider.descriptor.state != .Confirmed {
		return {}, false, registry_reject(state, theme_failure(.Propose, .Provider_Not_Confirmed))
	}
	if needs_provider && state.usage.providers >= state.limits.providers {
		return {}, false, registry_reject(state, theme_failure_with_limit(
			.Propose, .Provider_Limit, u64(state.limits.providers), u64(state.usage.providers) + 1,
		))
	}
	if state.usage.definitions >= state.limits.definitions {
		return {}, false, registry_reject(state, theme_failure_with_limit(
			.Propose, .Definition_Limit, u64(state.limits.definitions), u64(state.usage.definitions) + 1,
		))
	}
	proposal_bytes := definition_proposal_bytes(proposal)
	if proposal_bytes > state.limits.retained_definition_bytes ||
	   state.usage.retained_definition_bytes >
	   state.limits.retained_definition_bytes - proposal_bytes {
		return {}, false, registry_reject(state, theme_failure_with_limit(
			.Propose,
			.Retained_Definition_Limit,
			state.limits.retained_definition_bytes,
			state.usage.retained_definition_bytes + proposal_bytes,
		))
	}
	if !registry_generation_available(state) || state.next_definition_id == Definition_ID(max(u64)) ||
	   (needs_provider && state.next_provider_id == Provider_ID(max(u64))) {
		return {}, false, registry_reject(state, theme_failure(.Propose, .Generation_Limit))
	}
	if needs_provider {
		provider = provider_free_slot(state)
		if provider == nil {
			return {}, false, registry_reject(state, theme_failure(.Propose, .Provider_Limit))
		}
		provider.descriptor = Provider_Descriptor {
			handle = Provider_Handle {
				registry_id = state.registry_id,
				provider_id = state.next_provider_id,
				provider_generation = 1,
			},
			kind = .Racket,
			state = .Confirmed,
			name = provider_name_copy(proposal.provider_name),
		}
		provider.live = true
		state.next_provider_id += 1
		state.usage.providers += 1
	}
	slot := definition_free_slot(state)
	if slot == nil {
		return {}, false, registry_reject(state, theme_failure(.Propose, .Definition_Limit))
	}
	definition = Definition_Handle {
		registry_id = state.registry_id,
		provider_id = provider.descriptor.handle.provider_id,
		provider_generation = provider.descriptor.handle.provider_generation,
		definition_id = state.next_definition_id,
		definition_generation = 1,
	}
	definition_slot_write(slot, definition, proposal, .Proposed)
	state.next_definition_id += 1
	state.usage.definitions += 1
	state.usage.retained_definition_bytes += proposal_bytes
	state.usage.preparation_peak_bytes = max(state.usage.preparation_peak_bytes, proposal_bytes)
	state.registry_generation += 1
	return definition, true, {}
}

/* theme_registry_confirm confirms one exact proposed immutable generation. */
theme_registry_confirm :: proc(
	registry: ^Registry,
	expected_registry: Registry_Generation,
	handle: Definition_Handle,
) -> (confirmed: Definition_Handle, ok: bool, failure: Failure) {
	state := registry_state(registry)
	if state == nil {
		return {}, false, registry_access_failure(registry, .Confirm)
	}
	if state.registry_generation != expected_registry {
		return {}, false, registry_reject(state, theme_failure(.Confirm, .Stale_Registry))
	}
	slot, resolve_failure := definition_resolve(state, handle)
	if resolve_failure.code != .None {
		resolve_failure.operation = .Confirm
		return {}, false, registry_reject(state, resolve_failure)
	}
	if slot.descriptor.state != .Proposed {
		return {}, false, registry_reject(state, theme_failure(.Confirm, .Definition_Not_Proposed))
	}
	if slot.descriptor.handle.definition_generation == Definition_Generation(max(u64)) ||
	   !registry_generation_available(state) {
		return {}, false, registry_reject(state, theme_failure(.Confirm, .Generation_Limit))
	}
	slot.descriptor.handle.definition_generation += 1
	slot.descriptor.state = .Confirmed
	state.registry_generation += 1
	return slot.descriptor.handle, true, {}
}

/* theme_registry_select selects one exact confirmed definition generation. */
theme_registry_select :: proc(
	registry: ^Registry,
	expected_selection: Selection,
	handle: Definition_Handle,
) -> (selection: Selection, ok: bool, failure: Failure) {
	return registry_select(registry, expected_selection, handle, .Selected, .Select)
}

/* theme_registry_replace atomically confirms and selects a new admitted generation. */
theme_registry_replace :: proc(
	registry: ^Registry,
	expected_selection: Selection,
	handle: Definition_Handle,
	proposal: Definition_Proposal,
) -> (selection: Selection, replacement: Definition_Handle, ok: bool, failure: Failure) {
	state := registry_state(registry)
	if state == nil {
		return {}, {}, false, registry_access_failure(registry, .Replace)
	}
	if !selection_matches(state, expected_selection) {
		return {}, {}, false, registry_reject(state, theme_failure(.Replace, .Stale_Selection))
	}
	slot, resolve_failure := definition_resolve(state, handle)
	if resolve_failure.code != .None {
		resolve_failure.operation = .Replace
		return {}, {}, false, registry_reject(state, resolve_failure)
	}
	provider, provider_failure := provider_resolve(state, slot.descriptor.provider)
	if provider_failure.code != .None || provider.descriptor.kind != .Racket {
		return {}, {}, false, registry_reject(state, theme_failure(.Replace, .Factory_Definition_Immutable))
	}
	if slot.descriptor.state != .Confirmed {
		return {}, {}, false, registry_reject(state, theme_failure(.Replace, .Definition_Not_Confirmed))
	}
	if valid, proposal_failure := definition_proposal_validate(proposal, state.limits); !valid {
		proposal_failure.operation = .Replace
		return {}, {}, false, registry_reject(state, proposal_failure)
	}
	if proposal.identity != theme_name_string(&slot.descriptor.identity) ||
	   proposal.provider_name != provider_name_string(&provider.descriptor.name) {
		return {}, {}, false, registry_reject(state, theme_failure(.Replace, .Invalid_Definition))
	}
	new_bytes := definition_proposal_bytes(proposal)
	retained_without_prior := state.usage.retained_definition_bytes - slot.descriptor.retained_bytes
	if new_bytes > state.limits.retained_definition_bytes ||
	   retained_without_prior > state.limits.retained_definition_bytes - new_bytes {
		return {}, {}, false, registry_reject(state, theme_failure_with_limit(
			.Replace,
			.Retained_Definition_Limit,
			state.limits.retained_definition_bytes,
			retained_without_prior + new_bytes,
		))
	}
	if slot.descriptor.handle.definition_generation == Definition_Generation(max(u64)) ||
	   !selection_generations_available(state) {
		return {}, {}, false, registry_reject(state, theme_failure(.Replace, .Generation_Limit))
	}
	replacement = slot.descriptor.handle
	replacement.definition_generation += 1
	definition_slot_write(slot, replacement, proposal, .Confirmed)
	state.usage.retained_definition_bytes = retained_without_prior + new_bytes
	state.usage.preparation_peak_bytes = max(state.usage.preparation_peak_bytes, new_bytes)
	state.active = replacement
	state.selection_state = .Replaced
	state.registry_generation += 1
	state.selection_generation += 1
	return registry_selection(state), replacement, true, {}
}

/* theme_registry_restore selects the maintained factory fallback. */
theme_registry_restore :: proc(
	registry: ^Registry,
	expected_selection: Selection,
) -> (Selection, bool, Failure) {
	state := registry_state(registry)
	if state == nil do return {}, false, registry_access_failure(registry, .Restore)
	return registry_select(registry, expected_selection, state.fallback, .Restored, .Restore)
}

/* theme_registry_select_baseline selects the color-minimal safe definition. */
theme_registry_select_baseline :: proc(
	registry: ^Registry,
	expected_selection: Selection,
) -> (Selection, bool, Failure) {
	state := registry_state(registry)
	if state == nil do return {}, false, registry_access_failure(registry, .Select_Baseline)
	return registry_select(
		registry, expected_selection, state.baseline, .Safe_Baseline, .Select_Baseline,
	)
}

/* theme_registry_fail_provider closes definitions and restores active fallback. */
theme_registry_fail_provider :: proc(
	registry: ^Registry,
	expected_selection: Selection,
	handle: Provider_Handle,
) -> (selection: Selection, ok: bool, failure: Failure) {
	return registry_remove_provider(registry, expected_selection, handle, true)
}

/* theme_registry_close_provider tears down admitted data after fallback restoration. */
theme_registry_close_provider :: proc(
	registry: ^Registry,
	expected_selection: Selection,
	handle: Provider_Handle,
) -> (selection: Selection, ok: bool, failure: Failure) {
	return registry_remove_provider(registry, expected_selection, handle, false)
}

@(private)
registry_select :: proc(
	registry: ^Registry,
	expected: Selection,
	handle: Definition_Handle,
	selection_state: Selection_State,
	operation: Operation,
) -> (selection: Selection, ok: bool, failure: Failure) {
	state := registry_state(registry)
	if state == nil do return {}, false, registry_access_failure(registry, operation)
	if !selection_matches(state, expected) {
		return {}, false, registry_reject(state, theme_failure(operation, .Stale_Selection))
	}
	slot, resolve_failure := definition_resolve(state, handle)
	if resolve_failure.code != .None {
		resolve_failure.operation = operation
		return {}, false, registry_reject(state, resolve_failure)
	}
	if slot.descriptor.state != .Confirmed {
		return {}, false, registry_reject(state, theme_failure(operation, .Definition_Not_Confirmed))
	}
	if !selection_generations_available(state) {
		return {}, false, registry_reject(state, theme_failure(operation, .Generation_Limit))
	}
	state.active = handle
	state.selection_state = selection_state
	state.registry_generation += 1
	state.selection_generation += 1
	return registry_selection(state), true, {}
}

@(private)
registry_remove_provider :: proc(
	registry: ^Registry,
	expected: Selection,
	handle: Provider_Handle,
	failed: bool,
) -> (selection: Selection, ok: bool, failure: Failure) {
	operation := Operation.Close_Provider
	if failed do operation = .Fail
	state := registry_state(registry)
	if state == nil do return {}, false, registry_access_failure(registry, operation)
	if !selection_matches(state, expected) {
		return {}, false, registry_reject(state, theme_failure(operation, .Stale_Selection))
	}
	provider, resolve_failure := provider_resolve(state, handle)
	if resolve_failure.code != .None {
		resolve_failure.operation = operation
		return {}, false, registry_reject(state, resolve_failure)
	}
	if provider.descriptor.kind != .Racket {
		return {}, false, registry_reject(state, theme_failure(operation, .Factory_Provider_Required))
	}
	active_removed := state.active.provider_id == handle.provider_id &&
		state.active.provider_generation == handle.provider_generation
	if !registry_generation_available(state) ||
	   (active_removed && state.selection_generation == Selection_Generation(max(u64))) {
		return {}, false, registry_reject(state, theme_failure(operation, .Generation_Limit))
	}
	for &definition in state.definitions {
		if !definition.live || definition.descriptor.provider != handle {
			continue
		}
		state.usage.retained_definition_bytes -= definition.descriptor.retained_bytes
		definition = {}
		state.usage.definitions -= 1
	}
	if failed {
		provider.descriptor.state = .Failed
	} else {
		provider^ = {}
		state.usage.providers -= 1
	}
	if active_removed {
		state.active = state.fallback
		state.selection_state = failed ? .Fallback_After_Failure : .Restored
		state.selection_generation += 1
	}
	state.registry_generation += 1
	return registry_selection(state), true, {}
}

@(private)
registry_state :: proc(registry: ^Registry) -> ^Registry_State {
	if registry == nil || registry.state == nil || registry.closed do return nil
	return cast(^Registry_State)registry.state
}

@(private)
registry_access_failure :: proc(registry: ^Registry, operation: Operation) -> Failure {
	if registry != nil && registry.closed {
		return theme_failure(operation, .Closed_Registry)
	}
	return theme_failure(operation, .Invalid_Registry)
}

@(private)
registry_selection :: proc(state: ^Registry_State) -> Selection {
	return Selection {
		registry_id = state.registry_id,
		registry_generation = state.registry_generation,
		selection_generation = state.selection_generation,
		state = state.selection_state,
		active = state.active,
		fallback = state.fallback,
		baseline = state.baseline,
	}
}

@(private)
selection_matches :: proc(state: ^Registry_State, selection: Selection) -> bool {
	return selection == registry_selection(state)
}

@(private)
registry_generation_available :: proc(state: ^Registry_State) -> bool {
	return state.registry_generation != Registry_Generation(max(u64))
}

@(private)
selection_generations_available :: proc(state: ^Registry_State) -> bool {
	return registry_generation_available(state) &&
		state.selection_generation != Selection_Generation(max(u64))
}

@(private)
provider_free_slot :: proc(state: ^Registry_State) -> ^Provider_Slot {
	for &slot in state.providers {
		if !slot.live do return &slot
	}
	return nil
}

@(private)
definition_free_slot :: proc(state: ^Registry_State) -> ^Definition_Slot {
	for &slot in state.definitions {
		if !slot.live do return &slot
	}
	return nil
}

@(private)
provider_by_name :: proc(state: ^Registry_State, name: string) -> ^Provider_Slot {
	for &slot in state.providers {
		if slot.live && provider_name_string(&slot.descriptor.name) == name do return &slot
	}
	return nil
}

@(private)
provider_resolve :: proc(
	state: ^Registry_State,
	handle: Provider_Handle,
) -> (^Provider_Slot, Failure) {
	if handle.registry_id != state.registry_id {
		return nil, Failure{code = .Wrong_Registry, provider = handle}
	}
	for &slot in state.providers {
		if !slot.live || slot.descriptor.handle.provider_id != handle.provider_id do continue
		if slot.descriptor.handle != handle {
			return nil, Failure{code = .Stale_Provider, provider = handle}
		}
		return &slot, {}
	}
	return nil, Failure{code = .Invalid_Provider, provider = handle}
}

@(private)
definition_by_name :: proc(state: ^Registry_State, identity: string) -> ^Definition_Slot {
	for &slot in state.definitions {
		if slot.live && theme_name_string(&slot.descriptor.identity) == identity do return &slot
	}
	return nil
}

@(private)
definition_resolve :: proc(
	state: ^Registry_State,
	handle: Definition_Handle,
) -> (^Definition_Slot, Failure) {
	if handle.registry_id != state.registry_id {
		return nil, Failure{code = .Wrong_Registry, definition = handle}
	}
	for &slot in state.definitions {
		if !slot.live || slot.descriptor.handle.definition_id != handle.definition_id do continue
		if slot.descriptor.handle != handle {
			return nil, Failure{code = .Stale_Definition, definition = handle}
		}
		return &slot, {}
	}
	return nil, Failure{code = .Invalid_Definition, definition = handle}
}

@(private)
definition_slot_write :: proc(
	slot: ^Definition_Slot,
	handle: Definition_Handle,
	proposal: Definition_Proposal,
	state: Definition_State,
) {
	slot^ = Definition_Slot {
		descriptor = Definition_Descriptor {
			handle = handle,
			identity = theme_name_copy(proposal.identity),
			display_name = display_name_copy(proposal.display_name),
			provider = Provider_Handle {
				registry_id = handle.registry_id,
				provider_id = handle.provider_id,
				provider_generation = handle.provider_generation,
			},
			state = state,
			provenance = provenance_text_copy(proposal.provenance),
			style_count = u16(len(proposal.styles)),
			retained_bytes = definition_proposal_bytes(proposal),
		},
		live = true,
	}
	copy(slot.styles[:], proposal.styles)
}

@(private)
theme_name_copy :: proc(value: string) -> Theme_Name {
	result: Theme_Name
	result.length = u16(copy(result.bytes[:], transmute([]u8)value))
	return result
}

@(private)
display_name_copy :: proc(value: string) -> Display_Name {
	result: Display_Name
	result.length = u16(copy(result.bytes[:], transmute([]u8)value))
	return result
}

@(private)
provider_name_copy :: proc(value: string) -> Provider_Name {
	result: Provider_Name
	result.length = u16(copy(result.bytes[:], transmute([]u8)value))
	return result
}

@(private)
provenance_text_copy :: proc(value: string) -> Provenance_Text {
	result: Provenance_Text
	result.length = u16(copy(result.bytes[:], transmute([]u8)value))
	return result
}

@(private)
registry_reject :: proc(state: ^Registry_State, failure: Failure) -> Failure {
	state.latest_failure = failure
	return failure
}
