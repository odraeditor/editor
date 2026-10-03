// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package status_bar

import "base:runtime"
import "core:unicode/utf8"

@(private)
Stored_Segment :: struct {
	descriptor:       Programmable_Segment_Descriptor,
	kind:             Segment_Kind,
	group:            Group,
	priority:         u16,
	omittable:        bool,
	truncatable:      bool,
	style_role:       Semantic_Role,
	primary_command:  Command_Reference,
	secondary_command: Command_Reference,
	full_text:        [MAX_SEGMENT_TEXT_BYTES]u8,
	full_text_bytes:  u16,
	compact_text:     [MAX_SEGMENT_TEXT_BYTES]u8,
	compact_text_bytes: u16,
	inspection_text:  [MAX_SEGMENT_TEXT_BYTES]u8,
	inspection_text_bytes: u16,
}

@(private)
Provider_Data :: struct {
	descriptor: Provider_Descriptor,
	segments:   [MAX_PROGRAMMABLE_SEGMENTS_PER_PROVIDER]Stored_Segment,
}

@(private)
Provider_Slot :: struct {
	data: ^Provider_Data,
}

@(private)
Registry_State :: struct {
	registry_id:             Registry_ID,
	registry_generation:     Registry_Generation,
	next_provider_id:        Provider_ID,
	next_segment_id:         Segment_ID,
	next_registration_order: u64,
	providers:               [MAX_PROGRAMMABLE_PROVIDERS]Provider_Slot,
	usage:                   Registry_Usage,
	limits:                  Registry_Limits,
	latest_failure:          Registry_Failure,
	allocator:               runtime.Allocator,
}

/* registry_init creates one empty session registry with explicit resource ownership. */
registry_init :: proc(
	registry: ^Registry,
	registry_id: Registry_ID,
	limits := DEFAULT_REGISTRY_LIMITS,
	allocator := context.allocator,
) -> (ok: bool, failure: Registry_Failure) {
	if registry == nil {
		return false, registry_failure(.Initialize, .Invalid_Registry)
	}
	registry^ = {}
	if registry_id == Registry_ID(0) || allocator.procedure == nil ||
	   !registry_limits_are_valid(limits) {
		return false, registry_failure(.Initialize, .Invalid_Registry)
	}
	state, allocation_error := new(Registry_State, allocator)
	if allocation_error != nil {
		return false, registry_failure(.Initialize, .Allocation)
	}
	state^ = Registry_State {
		registry_id = registry_id,
		registry_generation = 1,
		next_provider_id = 1,
		next_segment_id = Segment_ID(FACTORY_SEGMENT_COUNT + 1),
		next_registration_order = 1,
		limits = limits,
		allocator = allocator,
	}
	registry.state = state
	return true, {}
}

/* registry_close releases every provider generation and invalidates the registry. */
registry_close :: proc(registry: ^Registry) -> (ok: bool, failure: Registry_Failure) {
	state := registry_state(registry)
	if state == nil {
		return false, registry_access_failure(registry, .Close)
	}
	allocator := state.allocator
	for &slot in state.providers {
		if slot.data != nil do free(slot.data, allocator)
	}
	free(state, allocator)
	registry^ = Registry{closed = true}
	return true, {}
}

/* registry_inspect copies exact generation, occupancy, limits, and latest rejection. */
registry_inspect :: proc(
	registry: ^Registry,
) -> (inspection: Registry_Inspection, ok: bool, failure: Registry_Failure) {
	state := registry_state(registry)
	if state == nil {
		return {}, false, registry_access_failure(registry, .Inspect)
	}
	return Registry_Inspection {
		registry_id = state.registry_id,
		registry_generation = state.registry_generation,
		usage = state.usage,
		limits = state.limits,
		latest_failure = state.latest_failure,
	}, true, {}
}

/* registry_provider_at copies one provider in stable registration order. */
registry_provider_at :: proc(
	registry: ^Registry,
	index: u16,
) -> (descriptor: Provider_Descriptor, ok: bool, failure: Registry_Failure) {
	state := registry_state(registry)
	if state == nil {
		return {}, false, registry_access_failure(registry, .Inspect)
	}
	data := provider_by_order_index(state, index)
	if data == nil {
		failure = registry_failure(.Inspect, .Invalid_Provider)
		state.latest_failure = failure
		return {}, false, failure
	}
	return data.descriptor, true, {}
}

/* registry_segment_at borrows one immutable segment in stable provider and segment order. */
registry_segment_at :: proc(
	registry: ^Registry,
	index: u16,
) -> (view: Programmable_Segment_View, ok: bool, failure: Registry_Failure) {
	state := registry_state(registry)
	if state == nil {
		return {}, false, registry_access_failure(registry, .Inspect)
	}
	remaining := index
	for provider_index: u16 = 0; provider_index < state.usage.providers; provider_index += 1 {
		provider := provider_by_order_index(state, provider_index)
		if provider == nil do continue
		if remaining < provider.descriptor.segment_count {
			return stored_segment_view(&provider.segments[remaining]), true, {}
		}
		remaining -= provider.descriptor.segment_count
	}
	failure = registry_failure(.Inspect, .Invalid_Segment)
	state.latest_failure = failure
	return {}, false, failure
}

/* registry_register atomically publishes one new package provider generation. */
registry_register :: proc(
	registry: ^Registry,
	expected_registry: Registry_Generation,
	proposal: Provider_Proposal,
) -> (provider: Provider_Handle, ok: bool, failure: Registry_Failure) {
	state := registry_state(registry)
	if state == nil {
		return {}, false, registry_access_failure(registry, .Register)
	}
	if state.registry_generation != expected_registry {
		return {}, false, registry_reject(state, registry_failure(.Register, .Stale_Registry))
	}
	proposal_bytes, valid, validation_failure := provider_proposal_validate(
		proposal,
		state.limits,
		.Register,
	)
	if !valid do return {}, false, registry_reject(state, validation_failure)
	if provider_by_name_or_package(state, proposal.provider_name, proposal.package_name) != nil {
		return {}, false, registry_reject(state, registry_failure(.Register, .Duplicate_Provider))
	}
	if state.usage.providers >= state.limits.providers {
		return {}, false, registry_reject(state, registry_failure_with_limit(
			.Register, .Provider_Limit, u64(state.limits.providers), u64(state.usage.providers) + 1,
		))
	}
	if u32(state.usage.segments) + u32(len(proposal.segments)) > u32(state.limits.total_segments) {
		return {}, false, registry_reject(state, registry_failure_with_limit(
			.Register,
			.Segment_Limit,
			u64(state.limits.total_segments),
			u64(state.usage.segments) + u64(len(proposal.segments)),
		))
	}
	if proposal_bytes > state.limits.retained_bytes ||
	   state.usage.retained_bytes > state.limits.retained_bytes - proposal_bytes {
		return {}, false, registry_reject(state, registry_failure_with_limit(
			.Register,
			.Retained_Bytes_Limit,
			state.limits.retained_bytes,
			state.usage.retained_bytes + proposal_bytes,
		))
	}
	if state.next_provider_id == Provider_ID(max(u64)) ||
	   state.next_registration_order == max(u64) ||
	   !registry_generation_available(state) ||
	   !segment_ids_available(state.next_segment_id, len(proposal.segments)) {
		return {}, false, registry_reject(state, registry_failure(.Register, .Generation_Limit))
	}
	slot := provider_free_slot(state)
	if slot == nil {
		return {}, false, registry_reject(state, registry_failure(.Register, .Provider_Limit))
	}
	provider = Provider_Handle {
		registry_id = state.registry_id,
		provider_id = state.next_provider_id,
		provider_generation = 1,
	}
	candidate, prepared := provider_data_prepare(
		state,
		proposal,
		provider,
		state.next_registration_order,
		state.next_segment_id,
		nil,
	)
	if !prepared {
		return {}, false, registry_reject(state, registry_failure(.Register, .Allocation))
	}
	slot.data = candidate
	state.next_provider_id += 1
	state.next_segment_id += Segment_ID(len(proposal.segments))
	state.next_registration_order += 1
	state.usage.providers += 1
	state.usage.segments += u16(len(proposal.segments))
	state.usage.retained_bytes += proposal_bytes
	state.usage.preparation_peak_bytes = max(state.usage.preparation_peak_bytes, proposal_bytes)
	state.registry_generation += 1
	return provider, true, {}
}

/* registry_replace atomically replaces one exact provider while preserving stable segment IDs. */
registry_replace :: proc(
	registry: ^Registry,
	expected_registry: Registry_Generation,
	handle: Provider_Handle,
	proposal: Provider_Proposal,
) -> (replacement: Provider_Handle, ok: bool, failure: Registry_Failure) {
	state := registry_state(registry)
	if state == nil {
		return {}, false, registry_access_failure(registry, .Replace)
	}
	if state.registry_generation != expected_registry {
		return {}, false, registry_reject(state, registry_failure(.Replace, .Stale_Registry))
	}
	prior, resolve_failure := provider_resolve(state, handle, .Replace)
	if resolve_failure.code != .None {
		return {}, false, registry_reject(state, resolve_failure)
	}
	proposal_bytes, valid, validation_failure := provider_proposal_validate(
		proposal,
		state.limits,
		.Replace,
	)
	if !valid do return {}, false, registry_reject(state, validation_failure)
	if proposal.provider_name != provider_descriptor_name(&prior.descriptor) ||
	   proposal.package_name != provider_descriptor_package(&prior.descriptor) {
		return {}, false, registry_reject(state, registry_failure(.Replace, .Invalid_Proposal))
	}
	segments_without_prior := u32(state.usage.segments) - u32(prior.descriptor.segment_count)
	if segments_without_prior + u32(len(proposal.segments)) > u32(state.limits.total_segments) {
		return {}, false, registry_reject(state, registry_failure_with_limit(
			.Replace,
			.Segment_Limit,
			u64(state.limits.total_segments),
			u64(segments_without_prior) + u64(len(proposal.segments)),
		))
	}
	retained_without_prior := state.usage.retained_bytes - prior.descriptor.retained_bytes
	if proposal_bytes > state.limits.retained_bytes ||
	   retained_without_prior > state.limits.retained_bytes - proposal_bytes {
		return {}, false, registry_reject(state, registry_failure_with_limit(
			.Replace,
			.Retained_Bytes_Limit,
			state.limits.retained_bytes,
			retained_without_prior + proposal_bytes,
		))
	}
	new_segments := count_new_segment_identities(prior, proposal)
	if handle.provider_generation == Provider_Generation(max(u64)) ||
	   !registry_generation_available(state) ||
	   !segment_generations_available(prior, proposal) ||
	   !segment_ids_available(state.next_segment_id, new_segments) {
		return {}, false, registry_reject(state, registry_failure(.Replace, .Generation_Limit))
	}
	replacement = handle
	replacement.provider_generation += 1
	candidate, prepared := provider_data_prepare(
		state,
		proposal,
		replacement,
		prior.descriptor.registration_order,
		state.next_segment_id,
		prior,
	)
	if !prepared {
		return {}, false, registry_reject(state, registry_failure(.Replace, .Allocation))
	}
	slot := provider_slot_for_data(state, prior)
	if slot == nil {
		free(candidate, state.allocator)
		return {}, false, registry_reject(state, registry_failure(.Replace, .Invalid_Provider))
	}
	free(prior, state.allocator)
	slot.data = candidate
	state.next_segment_id += Segment_ID(new_segments)
	state.usage.segments = u16(segments_without_prior + u32(len(proposal.segments)))
	state.usage.retained_bytes = retained_without_prior + proposal_bytes
	state.usage.preparation_peak_bytes = max(state.usage.preparation_peak_bytes, proposal_bytes)
	state.registry_generation += 1
	return replacement, true, {}
}

/* registry_remove removes one exact package provider and every owned segment. */
registry_remove :: proc(
	registry: ^Registry,
	expected_registry: Registry_Generation,
	handle: Provider_Handle,
) -> (ok: bool, failure: Registry_Failure) {
	return registry_remove_provider(registry, expected_registry, handle, .Remove)
}

/* registry_teardown_provider removes all state owned by one closing package provider. */
registry_teardown_provider :: proc(
	registry: ^Registry,
	expected_registry: Registry_Generation,
	handle: Provider_Handle,
) -> (ok: bool, failure: Registry_Failure) {
	return registry_remove_provider(registry, expected_registry, handle, .Teardown)
}

@(private)
registry_remove_provider :: proc(
	registry: ^Registry,
	expected_registry: Registry_Generation,
	handle: Provider_Handle,
	operation: Registry_Operation,
) -> (ok: bool, failure: Registry_Failure) {
	state := registry_state(registry)
	if state == nil do return false, registry_access_failure(registry, operation)
	if state.registry_generation != expected_registry {
		return false, registry_reject(state, registry_failure(operation, .Stale_Registry))
	}
	provider, resolve_failure := provider_resolve(state, handle, operation)
	if resolve_failure.code != .None {
		return false, registry_reject(state, resolve_failure)
	}
	if !registry_generation_available(state) {
		return false, registry_reject(state, registry_failure(operation, .Generation_Limit))
	}
	slot := provider_slot_for_data(state, provider)
	if slot == nil {
		return false, registry_reject(state, registry_failure(operation, .Invalid_Provider))
	}
	state.usage.providers -= 1
	state.usage.segments -= provider.descriptor.segment_count
	state.usage.retained_bytes -= provider.descriptor.retained_bytes
	free(provider, state.allocator)
	slot.data = nil
	state.registry_generation += 1
	return true, {}
}

@(private)
provider_data_prepare :: proc(
	state: ^Registry_State,
	proposal: Provider_Proposal,
	handle: Provider_Handle,
	registration_order: u64,
	first_new_segment_id: Segment_ID,
	prior: ^Provider_Data,
) -> (^Provider_Data, bool) {
	data, allocation_error := new(Provider_Data, state.allocator)
	if allocation_error != nil do return nil, false
	data^ = {}
	data.descriptor = Provider_Descriptor {
		handle = handle,
		registration_order = registration_order,
		segment_count = u16(len(proposal.segments)),
		retained_bytes = provider_proposal_bytes(proposal),
	}
	data.descriptor.provider_name_bytes = u16(copy(
		data.descriptor.provider_name[:],
		transmute([]u8)proposal.provider_name,
	))
	data.descriptor.package_name_bytes = u16(copy(
		data.descriptor.package_name[:],
		transmute([]u8)proposal.package_name,
	))
	indices := provider_proposal_order(proposal)
	next_segment_id := first_new_segment_id
	for output_index in 0 ..< len(proposal.segments) {
		segment := proposal.segments[indices[output_index]]
		prior_segment := stored_segment_by_identity(prior, segment.identity)
		segment_handle := Programmable_Segment_Handle {
			provider = handle,
			segment_id = next_segment_id,
			segment_generation = 1,
		}
		if prior_segment != nil {
			segment_handle.segment_id = prior_segment.descriptor.handle.segment_id
			segment_handle.segment_generation = prior_segment.descriptor.handle.segment_generation + 1
		} else {
			next_segment_id += 1
		}
		stored_segment_write(&data.segments[output_index], segment_handle, segment)
	}
	return data, true
}

@(private)
stored_segment_write :: proc(
	stored: ^Stored_Segment,
	handle: Programmable_Segment_Handle,
	proposal: Programmable_Segment_Proposal,
) {
	stored^ = Stored_Segment {
		descriptor = Programmable_Segment_Descriptor {
			handle = handle,
			order = proposal.order,
			retained_bytes = programmable_segment_proposal_bytes(proposal),
		},
		kind = proposal.kind,
		group = proposal.group,
		priority = proposal.priority,
		omittable = proposal.omittable,
		truncatable = proposal.truncatable,
		style_role = proposal.style_role,
		primary_command = proposal.primary_command,
		secondary_command = proposal.secondary_command,
	}
	stored.descriptor.identity_bytes = u16(copy(
		stored.descriptor.identity[:],
		transmute([]u8)proposal.identity,
	))
	stored.full_text_bytes = u16(copy(stored.full_text[:], transmute([]u8)proposal.full_text))
	stored.compact_text_bytes = u16(copy(
		stored.compact_text[:],
		transmute([]u8)proposal.compact_text,
	))
	stored.inspection_text_bytes = u16(copy(
		stored.inspection_text[:],
		transmute([]u8)proposal.inspection_text,
	))
}

@(private)
stored_segment_view :: proc(stored: ^Stored_Segment) -> Programmable_Segment_View {
	return Programmable_Segment_View {
		descriptor = stored.descriptor,
		definition = Segment_Definition {
			id = stored.descriptor.handle.segment_id,
			kind = stored.kind,
			group = stored.group,
			priority = stored.priority,
			full_text = string(stored.full_text[:stored.full_text_bytes]),
			compact_text = string(stored.compact_text[:stored.compact_text_bytes]),
			omittable = stored.omittable,
			truncatable = stored.truncatable,
			style_role = stored.style_role,
			inspection_text = string(stored.inspection_text[:stored.inspection_text_bytes]),
			primary_command = stored.primary_command,
			secondary_command = stored.secondary_command,
		},
	}
}

@(private)
provider_proposal_validate :: proc(
	proposal: Provider_Proposal,
	limits: Registry_Limits,
	operation: Registry_Operation,
) -> (bytes: u64, ok: bool, failure: Registry_Failure) {
	if len(proposal.provider_name) == 0 || !utf8.valid_string(proposal.provider_name) ||
	   text_contains_control_bytes(proposal.provider_name) ||
	   len(proposal.provider_name) > int(limits.provider_name_bytes) ||
	   !programmable_identity_is_valid(proposal.package_name, int(limits.package_name_bytes)) {
		return 0, false, registry_failure(operation, .Invalid_Proposal)
	}
	if len(proposal.segments) == 0 || len(proposal.segments) > int(limits.segments_per_provider) {
		return 0, false, registry_failure_with_limit(
			operation,
			.Segment_Limit,
			u64(limits.segments_per_provider),
			u64(len(proposal.segments)),
		)
	}
	for segment, index in proposal.segments {
		if !programmable_identity_is_valid(segment.identity, int(limits.identity_bytes)) {
			return 0, false, registry_failure(operation, .Invalid_Segment)
		}
		if factory_segment_identity_is_reserved(segment.identity) {
			return 0, false, registry_failure(operation, .Factory_Identity_Conflict)
		}
		if len(segment.full_text) == 0 || len(segment.full_text) > int(limits.segment_text_bytes) ||
		   len(segment.compact_text) > int(limits.segment_text_bytes) ||
		   len(segment.inspection_text) > int(limits.segment_text_bytes) ||
		   !utf8.valid_string(segment.full_text) || !utf8.valid_string(segment.compact_text) ||
		   !utf8.valid_string(segment.inspection_text) ||
		   text_contains_control_bytes(segment.full_text) ||
		   text_contains_control_bytes(segment.compact_text) ||
		   text_contains_control_bytes(segment.inspection_text) {
			return 0, false, registry_failure_with_limit(
				operation,
				.Text_Limit,
				u64(limits.segment_text_bytes),
				u64(max(
					len(segment.full_text),
					max(len(segment.compact_text), len(segment.inspection_text)),
				)),
			)
		}
		if !programmable_segment_policy_is_valid(segment) {
			return 0, false, registry_failure(operation, .Invalid_Segment)
		}
		for prior in 0 ..< index {
			if proposal.segments[prior].identity == segment.identity {
				return 0, false, registry_failure(operation, .Duplicate_Segment)
			}
		}
	}
	return provider_proposal_bytes(proposal), true, {}
}

@(private)
programmable_segment_policy_is_valid :: proc(proposal: Programmable_Segment_Proposal) -> bool {
	return proposal.kind == .Miscellaneous && group_is_valid(proposal.group) &&
		semantic_role_is_valid(proposal.style_role) && (proposal.omittable || proposal.truncatable) &&
		command_reference_is_valid(proposal.primary_command) &&
		command_reference_is_valid(proposal.secondary_command)
}

@(private)
group_is_valid :: proc(group: Group) -> bool {
	return group == .Left || group == .Right
}

@(private)
semantic_role_is_valid :: proc(role: Semantic_Role) -> bool {
	switch role {
	case .Ordinary, .Safety, .Buffer_Identity, .Position, .Alert, .Context,
	     .Workspace, .Project, .Editing_Context, .Disabled:
		return true
	case .Invalid:
		return false
	}
	return false
}

@(private)
command_reference_is_valid :: proc(reference: Command_Reference) -> bool {
	zero := reference.registry_generation == 0 && reference.slot == 0 && reference.entry_generation == 0
	complete := reference.registry_generation != 0 && reference.slot != 0 && reference.entry_generation != 0
	return zero || complete
}

@(private)
text_contains_control_bytes :: proc(value: string) -> bool {
	for byte in transmute([]u8)value {
		if byte < 32 || byte == 127 do return true
	}
	return false
}

@(private)
programmable_identity_is_valid :: proc(identity: string, limit: int) -> bool {
	if len(identity) == 0 || len(identity) > limit || identity[0] == '-' ||
	   identity[len(identity) - 1] == '-' {
		return false
	}
	for byte in transmute([]u8)identity {
		if (byte < 'a' || byte > 'z') && (byte < '0' || byte > '9') && byte != '-' {
			return false
		}
	}
	return true
}

@(private)
factory_segment_identity_is_reserved :: proc(identity: string) -> bool {
	switch identity {
	case "alert", "encoding", "buffer-state", "pane-state", "buffer-identity",
	     "buffer-size", "buffer-context", "position", "progress",
	     "workspace", "project", "editing-context":
		return true
	}
	return false
}

@(private)
provider_proposal_bytes :: proc(_: Provider_Proposal) -> u64 {
	return u64(size_of(Provider_Data))
}

@(private)
programmable_segment_proposal_bytes :: proc(proposal: Programmable_Segment_Proposal) -> u64 {
	return u64(size_of(Programmable_Segment_Descriptor)) +
		u64(len(proposal.identity) + len(proposal.full_text) + len(proposal.compact_text) +
		len(proposal.inspection_text))
}

@(private)
provider_proposal_order :: proc(proposal: Provider_Proposal) -> [MAX_PROGRAMMABLE_SEGMENTS_PER_PROVIDER]int {
	indices: [MAX_PROGRAMMABLE_SEGMENTS_PER_PROVIDER]int
	for index in 0 ..< len(proposal.segments) do indices[index] = index
	for index in 1 ..< len(proposal.segments) {
		candidate := indices[index]
		position := index
		for position > 0 && segment_proposal_less(
			proposal.segments[candidate],
			proposal.segments[indices[position - 1]],
		) {
			indices[position] = indices[position - 1]
			position -= 1
		}
		indices[position] = candidate
	}
	return indices
}

@(private)
segment_proposal_less :: proc(a, b: Programmable_Segment_Proposal) -> bool {
	if a.group != b.group do return u8(a.group) < u8(b.group)
	if a.order != b.order do return a.order < b.order
	return string_less(a.identity, b.identity)
}

@(private)
string_less :: proc(a, b: string) -> bool {
	shared := min(len(a), len(b))
	for index in 0 ..< shared {
		if a[index] != b[index] do return a[index] < b[index]
	}
	return len(a) < len(b)
}

@(private)
provider_by_order_index :: proc(state: ^Registry_State, index: u16) -> ^Provider_Data {
	if index >= state.usage.providers do return nil
	selected: ^Provider_Data
	prior_order: u64
	for current: u16 = 0; current <= index; current += 1 {
		selected = nil
		for &slot in state.providers {
			if slot.data == nil || slot.data.descriptor.registration_order <= prior_order do continue
			if selected == nil || slot.data.descriptor.registration_order < selected.descriptor.registration_order {
				selected = slot.data
			}
		}
		if selected == nil do return nil
		prior_order = selected.descriptor.registration_order
	}
	return selected
}

@(private)
provider_by_name_or_package :: proc(
	state: ^Registry_State,
	name, package_name: string,
) -> ^Provider_Data {
	for &slot in state.providers {
		if slot.data == nil do continue
		if provider_descriptor_name(&slot.data.descriptor) == name ||
		   provider_descriptor_package(&slot.data.descriptor) == package_name {
			return slot.data
		}
	}
	return nil
}

@(private)
provider_resolve :: proc(
	state: ^Registry_State,
	handle: Provider_Handle,
	operation: Registry_Operation,
) -> (^Provider_Data, Registry_Failure) {
	if handle.registry_id != state.registry_id {
		return nil, Registry_Failure{operation = operation, code = .Wrong_Registry, provider = handle}
	}
	for &slot in state.providers {
		if slot.data == nil || slot.data.descriptor.handle.provider_id != handle.provider_id do continue
		if slot.data.descriptor.handle != handle {
			return nil, Registry_Failure{operation = operation, code = .Stale_Provider, provider = handle}
		}
		return slot.data, {}
	}
	return nil, Registry_Failure{operation = operation, code = .Invalid_Provider, provider = handle}
}

@(private)
provider_free_slot :: proc(state: ^Registry_State) -> ^Provider_Slot {
	for &slot in state.providers {
		if slot.data == nil do return &slot
	}
	return nil
}

@(private)
provider_slot_for_data :: proc(state: ^Registry_State, data: ^Provider_Data) -> ^Provider_Slot {
	for &slot in state.providers {
		if slot.data == data do return &slot
	}
	return nil
}

@(private)
stored_segment_by_identity :: proc(data: ^Provider_Data, identity: string) -> ^Stored_Segment {
	if data == nil do return nil
	for &segment in data.segments[:data.descriptor.segment_count] {
		if programmable_segment_identity(&segment.descriptor) == identity do return &segment
	}
	return nil
}

@(private)
count_new_segment_identities :: proc(data: ^Provider_Data, proposal: Provider_Proposal) -> int {
	count := 0
	for segment in proposal.segments {
		if stored_segment_by_identity(data, segment.identity) == nil do count += 1
	}
	return count
}

@(private)
segment_generations_available :: proc(data: ^Provider_Data, proposal: Provider_Proposal) -> bool {
	for segment in proposal.segments {
		prior := stored_segment_by_identity(data, segment.identity)
		if prior != nil && prior.descriptor.handle.segment_generation == Segment_Generation(max(u64)) {
			return false
		}
	}
	return true
}

@(private)
segment_ids_available :: proc(first: Segment_ID, count: int) -> bool {
	if count < 0 do return false
	if count == 0 do return true
	return u64(count - 1) <= max(u64) - u64(first)
}

@(private)
registry_generation_available :: proc(state: ^Registry_State) -> bool {
	return state.registry_generation != Registry_Generation(max(u64))
}

@(private)
registry_state :: proc(registry: ^Registry) -> ^Registry_State {
	if registry == nil || registry.state == nil || registry.closed do return nil
	return cast(^Registry_State)registry.state
}

@(private)
registry_access_failure :: proc(registry: ^Registry, operation: Registry_Operation) -> Registry_Failure {
	if registry != nil && registry.closed do return registry_failure(operation, .Closed_Registry)
	return registry_failure(operation, .Invalid_Registry)
}

@(private)
registry_reject :: proc(state: ^Registry_State, failure: Registry_Failure) -> Registry_Failure {
	state.latest_failure = failure
	return failure
}

@(private)
registry_failure :: proc(operation: Registry_Operation, code: Registry_Failure_Code) -> Registry_Failure {
	return Registry_Failure{operation = operation, code = code}
}

@(private)
registry_failure_with_limit :: proc(
	operation: Registry_Operation,
	code: Registry_Failure_Code,
	limit, actual: u64,
) -> Registry_Failure {
	return Registry_Failure{operation = operation, code = code, limit = limit, actual = actual}
}
