// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package interaction

import "base:runtime"

@(private)
Inspection_Result_State :: struct {
	records:       []Inspection_Record,
	selectors:     []Profile_State_Selector,
	text:          []u8,
	modal_pending: Modal_Pending_State,
	modal_visual:  Modal_Visual_State,
	allocator:     runtime.Allocator,
}

/* keymap_inspect copies one bounded immutable view of the active profile. */
keymap_inspect :: proc(
	registry: ^Command_Registry,
	activation: ^Profile_Activation,
	pending: ^Pending_State,
	query: Inspection_Query,
	allocator := context.allocator,
) -> (result: Inspection_Result, ok: bool, failure: Failure_Context) {
	registry_state := registry_data(registry)
	if registry_state == nil || activation == nil || pending == nil || allocator.procedure == nil {
		return {}, false, Failure_Context{code = .Invalid_Registry}
	}
	if query.kind == .Invalid {
		return {}, false, Failure_Context{code = .Invalid_Input}
	}

	snapshot, snapshot_ok := profile_activation_snapshot(activation)
	snapshot_state := snapshot_data(snapshot)
	if query.kind != .Latest_Rejection && (!snapshot_ok || snapshot_state == nil) {
		return {}, false, Failure_Context{code = .Invalid_Snapshot}
	}
	if snapshot_state != nil && (
		snapshot_state.registry != registry_state ||
		snapshot_state.registry_generation != registry_state.generation
	) {
		return {}, false, Failure_Context {
			code = .Stale_Registry,
			registry_generation = registry_state.generation,
			snapshot_generation = snapshot_state.generation,
		}
	}
	if query.kind == .Sequence && !sequence_valid(query.sequence) {
		return {}, false, Failure_Context {
			code = .Invalid_Input,
			stroke_count = query.sequence.stroke_count,
			limit = MAX_SEQUENCE_STROKES,
			actual = u64(query.sequence.stroke_count),
		}
	}
	if query.kind == .Command && !valid_bounded_text(query.command_name, MAX_COMMAND_NAME_BYTES, false) {
		return {}, false, Failure_Context {
			code = .Invalid_Name,
			limit = MAX_COMMAND_NAME_BYTES,
			actual = u64(len(query.command_name)),
		}
	}
	if query.kind == .Map && query.map_id == Map_ID(0) {
		return {}, false, Failure_Context{code = .Invalid_Map}
	}
	catalog, catalog_active := profile_activation_catalog(activation)
	active_profile, active_state, selection_active := profile_activation_selection(activation)
	if query.kind == .Compatibility && (!catalog_active || !selection_active) {
		return {}, false, Failure_Context{code = .Invalid_Profile_Catalog}
	}

	draft_capacity := 1
	if snapshot_state != nil {
		draft_capacity = int(snapshot_state.inspection_limit)
	}
	drafts, drafts_error := make([]Inspection_Record, draft_capacity, allocator)
	if drafts_error != nil {
		return {}, false, Failure_Context{code = .Persistent_Memory_Limit}
	}
	defer delete(drafts, allocator)
	draft_count := 0
	if query.kind == .Latest_Rejection {
		rejection := profile_activation_last_rejection(activation)
		if rejection.code != .None {
			drafts[0] = inspection_rejection_record(rejection)
			draft_count = 1
		}
	} else if query.kind == .Compatibility {
		collected: bool
		draft_count, collected, failure = compatibility_inspection_collect(
			snapshot_state,
			catalog,
			active_profile,
			active_state,
			drafts[:],
		)
		if !collected {
			return {}, false, failure
		}
	} else if snapshot_state.layered {
		collected: bool
		draft_count, collected, failure = layered_inspection_collect(
			snapshot_state,
			registry_state,
			query,
			drafts[:],
		)
		if !collected {
			return {}, false, failure
		}
	} else {
		collected: bool
		draft_count, collected, failure = legacy_inspection_collect(
			snapshot_state,
			registry_state,
			query,
			drafts[:],
		)
		if !collected {
			return {}, false, failure
		}
	}
	if catalog_active && selection_active && query.kind != .Compatibility {
		for index in 0 ..< draft_count {
			inspection_record_enrich_catalog(
				&drafts[index],
				registry_state,
				catalog,
				active_profile,
				active_state,
			)
		}
		if query.kind == .Command {
			requested, found, _ := lookup_command_data(registry_state, query.command_name)
			if found {
				for surface in catalog.surfaces {
					if draft_count >= len(drafts) || draft_count >= int(snapshot_state.inspection_limit) {
						return {}, false, inspection_limit_failure(snapshot_state, draft_count + 1)
					}
					drafts[draft_count] = inspection_surface_record(
						catalog.generation,
						surface,
						requested,
						active_profile,
						active_state,
						registry_state,
					)
					draft_count += 1
				}
			}
		}
	}

	owner, owner_error := new(Inspection_Result_State, allocator)
	if owner_error != nil {
		return {}, false, Failure_Context{code = .Persistent_Memory_Limit}
	}
	owner.allocator = allocator
	if draft_count > 0 {
		owner.records, owner_error = make([]Inspection_Record, draft_count, allocator)
		if owner_error != nil {
			inspection_result_state_destroy(owner)
			return {}, false, Failure_Context{code = .Persistent_Memory_Limit}
		}
	}
	selector_count := 0
	for draft in drafts[:draft_count] {
		selector_count += len(draft.selectors)
	}
	if selector_count > 0 {
		owner.selectors, owner_error = make([]Profile_State_Selector, selector_count, allocator)
		if owner_error != nil {
			inspection_result_state_destroy(owner)
			return {}, false, Failure_Context{code = .Persistent_Memory_Limit}
		}
	}
	text_bytes := 0
	for draft in drafts[:draft_count] {
		text_bytes += inspection_record_text_bytes(draft)
	}
	if text_bytes > 0 {
		owner.text, owner_error = make([]u8, text_bytes, allocator)
		if owner_error != nil {
			inspection_result_state_destroy(owner)
			return {}, false, Failure_Context{code = .Persistent_Memory_Limit}
		}
	}
	text_offset := 0
	selector_offset := 0
	for draft, index in drafts[:draft_count] {
		owner.records[index], text_offset, selector_offset = inspection_record_copy(
			draft,
			owner.text,
			text_offset,
			owner.selectors,
			selector_offset,
		)
	}
	assert(text_offset == text_bytes)
	assert(selector_offset == selector_count)
	owner.modal_pending = activation.modal_pending
	owner.modal_visual = activation.modal_visual

	identity: Snapshot_Identity
	usage: Keymap_Usage
	if snapshot_state != nil {
		identity = Snapshot_Identity {
			generation = snapshot_state.generation,
			registry_generation = snapshot_state.registry_generation,
			profile = snapshot_state.profile,
			ctx = snapshot_state.ctx,
		}
		usage.map_count = snapshot_state.map_count
		usage.active_map_count = snapshot_state.active_map_count
		usage.snapshot_bytes = snapshot_state.storage_bytes
		if snapshot_state.layered {
			usage.binding_count = u32(len(snapshot_state.layered_bindings))
			usage.remap_count = u32(len(snapshot_state.layered_remaps))
		} else {
			usage.binding_count = u32(snapshot_state.binding_count)
		}
	}
	usage.inspection_records = u16(draft_count)
	result = Inspection_Result {
		snapshot = identity,
		catalog_generation = catalog.generation if catalog_active else 0,
		active_state = active_state.identity if selection_active else {},
		pending = pending^,
		latest_rejection = profile_activation_last_rejection(activation),
		records = owner.records,
		usage = usage,
		state = owner,
	}
	return result, true, {}
}

/* inspection_result_modal_visual copies retained Visual endpoint intent from one live result. */
inspection_result_modal_visual :: proc(
	result: ^Inspection_Result,
) -> (visual: Modal_Visual_State, ok: bool) {
	if result == nil || result.state == nil || result.closed do return {}, false
	owner := cast(^Inspection_Result_State)result.state
	return owner.modal_visual, true
}

/* inspection_result_modal_pending copies the retained modal state from one live result. */
inspection_result_modal_pending :: proc(
	result: ^Inspection_Result,
) -> (pending: Modal_Pending_State, ok: bool) {
	if result == nil || result.state == nil || result.closed do return {}, false
	owner := cast(^Inspection_Result_State)result.state
	return owner.modal_pending, true
}

/* inspection_result_close releases one copied inspection projection. */
inspection_result_close :: proc(result: ^Inspection_Result) -> bool {
	if result == nil || result.state == nil || result.closed {
		return false
	}
	owner := cast(^Inspection_Result_State)result.state
	inspection_result_state_destroy(owner)
	result^ = Inspection_Result{closed = true}
	return true
}

/* context_map_inspect copies the effective bindings owned by one active contextual map. */
context_map_inspect :: proc(
	stack: ^Context_Map_Stack,
	map_id: Map_ID,
	include_sequences: bool,
	allocator := context.allocator,
) -> (result: Inspection_Result, ok: bool, failure: Failure_Context) {
	state := context_map_stack_state(stack)
	if state == nil || state.registry == nil || state.registry.state != .Ready ||
	   map_id == Map_ID(0) || allocator.procedure == nil {
		return {}, false, Failure_Context{code = .Invalid_Context_Map}
	}
	if state.registry.generation != state.registry_generation {
		return {}, false, Failure_Context {
			code = .Stale_Registry,
			registry_generation = state.registry_generation,
		}
	}
	active: ^Context_Map_State
	for &candidate in state.maps {
		if candidate.active && candidate.handle.identity.id == map_id {
			active = &candidate
			break
		}
	}
	if active == nil {
		return {}, false, Failure_Context {
			code = .Invalid_Context_Map,
			map_identity = {id = map_id},
		}
	}
	record_count := 0
	for binding in active.bindings[:int(active.binding_count)] {
		if include_sequences || binding.stroke_count == 1 do record_count += 1
	}
	if record_count > MAX_INSPECTION_ALTERNATIVES {
		return {}, false, Failure_Context {
			code = .Inspection_Limit,
			map_identity = active.handle.identity,
			limit = MAX_INSPECTION_ALTERNATIVES,
			actual = u64(record_count),
		}
	}
	owner, owner_error := new(Inspection_Result_State, allocator)
	if owner_error != nil {
		return {}, false, Failure_Context{code = .Persistent_Memory_Limit}
	}
	owner.allocator = allocator
	if record_count > 0 {
		owner.records, owner_error = make([]Inspection_Record, record_count, allocator)
		if owner_error != nil {
			inspection_result_state_destroy(owner)
			return {}, false, Failure_Context{code = .Persistent_Memory_Limit}
		}
	}
	map_name := string(active.name[:active.name_count])
	text_bytes := 0
	for binding in active.bindings[:int(active.binding_count)] {
		if !include_sequences && binding.stroke_count != 1 do continue
		command_name := command_handle_name(state.registry, binding.command)
		text_bytes += len(command_name) * 2 + len(map_name)
	}
	if text_bytes > 0 {
		owner.text, owner_error = make([]u8, text_bytes, allocator)
		if owner_error != nil {
			inspection_result_state_destroy(owner)
			return {}, false, Failure_Context{code = .Persistent_Memory_Limit}
		}
	}
	write := 0
	text_offset := 0
	for binding in active.bindings[:int(active.binding_count)] {
		if !include_sequences && binding.stroke_count != 1 do continue
		command_name := command_handle_name(state.registry, binding.command)
		draft := Inspection_Record {
			kind = .Binding,
			disposition = .Effective,
			sequence = {strokes = binding.strokes, stroke_count = binding.stroke_count},
			command = binding.command,
			command_name = command_name,
			original_command = binding.command,
			original_command_name = command_name,
			map_identity = active.handle.identity,
			map_name = map_name,
			owner = active.handle.owner,
			precedence = active.precedence,
			priority = active.priority,
			active = true,
			operation = .Bind,
		}
		owner.records[write], text_offset, _ = inspection_record_copy(
			draft,
			owner.text,
			text_offset,
			nil,
			0,
		)
		write += 1
	}
	assert(write == record_count)
	assert(text_offset == text_bytes)
	result = Inspection_Result {
		records = owner.records,
		usage = {
			map_count = 1,
			active_map_count = 1,
			binding_count = u32(record_count),
			inspection_records = u16(record_count),
		},
		state = owner,
	}
	return result, true, {}
}

@(private)
layered_inspection_collect :: proc(
	data: ^Snapshot_Data,
	registry: ^Registry_Data,
	query: Inspection_Query,
	output: []Inspection_Record,
) -> (count: int, ok: bool, failure: Failure_Context) {
	switch query.kind {
	case .Sequence:
		for map_slot in 0 ..< len(data.layered_maps) {
			compiled_map := &data.layered_maps[map_slot]
			binding := layered_map_exact_binding(data, compiled_map, query.sequence)
			if binding == nil || (!compiled_map.active && !query.include_inactive) {
				continue
			}
			if count >= len(output) || count >= int(data.inspection_limit) {
				return 0, false, inspection_limit_failure(data, count + 1)
			}
			output[count] = layered_binding_inspection_record(data, registry, compiled_map, binding)
			count += 1
		}
	case .Command:
		requested, found, lookup_failure := lookup_command_data(registry, query.command_name)
		if !found {
			return 0, false, lookup_failure
		}
		for &compiled_map in data.layered_maps {
			if !compiled_map.active && !query.include_inactive {
				continue
			}
			start := int(compiled_map.binding_start)
			end := start + int(compiled_map.binding_count)
			for &binding in data.layered_bindings[start:end] {
				effective := resolved_command(data, binding.compiled.command)
				if binding.operation == .Mask ||
				   (binding.original_command != requested && effective != requested) {
					continue
				}
				if count >= len(output) || count >= int(data.inspection_limit) {
					return 0, false, inspection_limit_failure(data, count + 1)
				}
				output[count] = layered_binding_inspection_record(data, registry, &compiled_map, &binding)
				count += 1
			}
			start = int(compiled_map.remap_start)
			end = start + int(compiled_map.remap_count)
			for &remap in data.layered_remaps[start:end] {
				if remap.from != requested && remap.to != requested {
					continue
				}
				if count >= len(output) || count >= int(data.inspection_limit) {
					return 0, false, inspection_limit_failure(data, count + 1)
				}
				output[count] = layered_remap_inspection_record(data, registry, &compiled_map, &remap)
				count += 1
			}
		}
	case .Map:
		found := false
		for &compiled_map in data.layered_maps {
			if compiled_map.identity.id != query.map_id {
				continue
			}
			found = true
			if !compiled_map.active && !query.include_inactive {
				continue
			}
			if count >= len(output) || count >= int(data.inspection_limit) {
				return 0, false, inspection_limit_failure(data, count + 1)
			}
			output[count] = layered_map_inspection_record(&compiled_map)
			count += 1
			start := int(compiled_map.binding_start)
			end := start + int(compiled_map.binding_count)
			for &binding in data.layered_bindings[start:end] {
				if count >= len(output) || count >= int(data.inspection_limit) {
					return 0, false, inspection_limit_failure(data, count + 1)
				}
				output[count] = layered_binding_inspection_record(data, registry, &compiled_map, &binding)
				count += 1
			}
			start = int(compiled_map.remap_start)
			end = start + int(compiled_map.remap_count)
			for &remap in data.layered_remaps[start:end] {
				if count >= len(output) || count >= int(data.inspection_limit) {
					return 0, false, inspection_limit_failure(data, count + 1)
				}
				output[count] = layered_remap_inspection_record(data, registry, &compiled_map, &remap)
				count += 1
			}
		}
		if !found {
			return 0, false, Failure_Context{code = .Invalid_Map, map_identity = {id = query.map_id}}
		}
	case .Active_Maps:
		for &compiled_map in data.layered_maps {
			if !compiled_map.active && !query.include_inactive {
				continue
			}
			if count >= len(output) || count >= int(data.inspection_limit) {
				return 0, false, inspection_limit_failure(data, count + 1)
			}
			output[count] = layered_map_inspection_record(&compiled_map)
			count += 1
		}
	case .Bindings:
		for &compiled_map in data.layered_maps {
			if !compiled_map.active && !query.include_inactive {
				continue
			}
			start := int(compiled_map.binding_start)
			end := start + int(compiled_map.binding_count)
			for &binding in data.layered_bindings[start:end] {
				if count >= len(output) || count >= int(data.inspection_limit) {
					return 0, false, inspection_limit_failure(data, count + 1)
				}
				output[count] = layered_binding_inspection_record(data, registry, &compiled_map, &binding)
				count += 1
			}
			start = int(compiled_map.remap_start)
			end = start + int(compiled_map.remap_count)
			for &remap in data.layered_remaps[start:end] {
				if count >= len(output) || count >= int(data.inspection_limit) {
					return 0, false, inspection_limit_failure(data, count + 1)
				}
				output[count] = layered_remap_inspection_record(data, registry, &compiled_map, &remap)
				count += 1
			}
		}
	case .Snapshot:
		output[0] = Inspection_Record{kind = .Snapshot, disposition = .Effective, active = true}
		count = 1
	case .Compatibility, .Latest_Rejection, .Invalid:
		return 0, false, Failure_Context{code = .Invalid_Input}
	}
	return count, true, {}
}

@(private)
legacy_inspection_collect :: proc(
	data: ^Snapshot_Data,
	registry: ^Registry_Data,
	query: Inspection_Query,
	output: []Inspection_Record,
) -> (count: int, ok: bool, failure: Failure_Context) {
	switch query.kind {
	case .Sequence:
		compiled := Compiled_Binding{strokes = query.sequence.strokes, stroke_count = query.sequence.stroke_count}
		exact, _ := find_sequence(data, compiled)
		if exact != nil {
			output[0] = legacy_binding_inspection_record(registry, exact)
			count = 1
		}
	case .Command:
		requested, found, lookup_failure := lookup_command_data(registry, query.command_name)
		if !found {
			return 0, false, lookup_failure
		}
		for &binding in data.bindings[:data.binding_count] {
			if binding.command != requested {
				continue
			}
			if count >= len(output) || count >= int(data.inspection_limit) {
				return 0, false, inspection_limit_failure(data, count + 1)
			}
			output[count] = legacy_binding_inspection_record(registry, &binding)
			count += 1
		}
	case .Snapshot:
		output[0] = Inspection_Record{kind = .Snapshot, disposition = .Effective, active = true}
		count = 1
	case .Bindings:
		for &binding in data.bindings[:data.binding_count] {
			if count >= len(output) || count >= int(data.inspection_limit) {
				return 0, false, inspection_limit_failure(data, count + 1)
			}
			output[count] = legacy_binding_inspection_record(registry, &binding)
			count += 1
		}
	case .Map, .Active_Maps:
		return 0, false, Failure_Context{code = .Invalid_Map}
	case .Compatibility, .Latest_Rejection, .Invalid:
		return 0, false, Failure_Context{code = .Invalid_Input}
	}
	return count, true, {}
}

@(private)
compatibility_inspection_collect :: proc(
	data: ^Snapshot_Data,
	catalog: Profile_Catalog_Definition,
	active_profile: Profile_Identity,
	active_state: Interaction_State_Definition,
	output: []Inspection_Record,
) -> (count: int, ok: bool, failure: Failure_Context) {
	required := 2 + len(catalog.profiles) + len(catalog.surfaces)
	for profile in catalog.profiles {
		required += len(profile.states)
	}
	if required > len(output) || required > int(data.inspection_limit) {
		return 0, false, inspection_limit_failure(data, required)
	}
	output[count] = Inspection_Record {
		kind = .Snapshot,
		disposition = .Effective,
		active = true,
		catalog_generation = catalog.generation,
		profile = active_profile,
		state = active_state.identity,
		state_name = active_state.name,
		state_admits_text_input = active_state.admits_text_input,
		state_admitted_effects = active_state.admitted_effects,
	}
	count += 1
	output[count] = Inspection_Record {
		kind = .Catalog,
		disposition = .Effective,
		active = true,
		catalog_generation = catalog.generation,
		profile = active_profile,
		state = active_state.identity,
	}
	count += 1
	for profile in catalog.profiles {
		profile_active := profile.identity.id == active_profile.id
		output[count] = Inspection_Record {
			kind = .Profile,
			disposition = .Effective if profile_active else .Inactive,
			active = profile_active,
			catalog_generation = catalog.generation,
			profile = profile.identity,
			profile_name = profile.name,
			state = active_state.identity if profile_active else {},
		}
		count += 1
		for state in profile.states {
			state_active := profile_active && state.identity.id == active_state.identity.id
			output[count] = Inspection_Record {
				kind = .State,
				disposition = .Effective if state_active else .Inactive,
				active = state_active,
				catalog_generation = catalog.generation,
				profile = profile.identity,
				profile_name = profile.name,
				state = state.identity,
				state_name = state.name,
				state_admits_text_input = state.admits_text_input,
				state_admitted_effects = state.admitted_effects,
				provenance = state.provenance,
			}
			count += 1
		}
	}
	for surface in catalog.surfaces {
		output[count] = inspection_surface_record(
			catalog.generation,
			surface,
			{},
			active_profile,
			active_state,
			nil,
		)
		count += 1
	}
	return count, true, {}
}

@(private)
inspection_record_enrich_catalog :: proc(
	record: ^Inspection_Record,
	registry: ^Registry_Data,
	catalog: Profile_Catalog_Definition,
	active_profile: Profile_Identity,
	active_state: Interaction_State_Definition,
) {
	if record == nil do return
	record.catalog_generation = catalog.generation
	if record.kind == .Rejection {
		if record.failure.catalog_generation != Profile_Catalog_Generation(0) {
			record.catalog_generation = record.failure.catalog_generation
		}
		record.profile = record.failure.profile
		record.state = record.failure.state
		inspection_record_add_identity_names(record, catalog)
		return
	}
	if record.kind == .Snapshot {
		record.profile = active_profile
		record.state = active_state.identity
		record.state_name = active_state.name
		record.state_admits_text_input = active_state.admits_text_input
		record.state_admitted_effects = active_state.admitted_effects
		inspection_record_add_identity_names(record, catalog)
		return
	}
	if record.kind != .Binding && record.kind != .Remap && record.kind != .Map do return
	record.state = active_state.identity
	record.state_name = active_state.name
	record.state_admits_text_input = active_state.admits_text_input
	record.state_admitted_effects = active_state.admitted_effects
	if record.protected {
		record.profile = active_profile
		record.binding_scope = .Protected_Recovery
		inspection_record_add_identity_names(record, catalog)
	} else if record.kind == .Binding {
		source_profile, source_binding, found := inspection_source_binding(catalog, record^)
		if found {
			record.profile = source_profile.identity
			record.profile_name = source_profile.name
			record.binding_scope = source_binding.scope
			record.selectors = source_binding.selectors
		}
	} else {
		record.profile = active_profile
		inspection_record_add_identity_names(record, catalog)
	}
	entry, command_found := resolve_command(registry, record.command)
	if command_found {
		record.effects_admitted = interaction_state_admits(active_state, entry.effects)
	}
}

@(private)
inspection_source_binding :: proc(
	catalog: Profile_Catalog_Definition,
	record: Inspection_Record,
) -> (profile: Profile_Definition, binding: Layered_Binding_Definition, ok: bool) {
	for candidate_profile in catalog.profiles {
		for candidate_map in candidate_profile.maps {
			if candidate_map.identity.id != record.map_identity.id do continue
			for candidate in candidate_map.bindings {
				if candidate.operation != record.operation ||
				   !command_catalog_sequence_equal(candidate.sequence, record.sequence) ||
				   candidate.command_name != record.original_command_name ||
				   candidate.provenance.provider != record.provenance.provider ||
				   candidate.provenance.source != record.provenance.source ||
				   candidate.provenance.location != record.provenance.location {
					continue
				}
				return candidate_profile, candidate, true
			}
		}
	}
	return {}, {}, false
}

@(private)
inspection_record_add_identity_names :: proc(
	record: ^Inspection_Record,
	catalog: Profile_Catalog_Definition,
) {
	for profile in catalog.profiles {
		if profile.identity.id != record.profile.id do continue
		record.profile_name = profile.name
		for state in profile.states {
			if state.identity.id != record.state.id do continue
			record.state_name = state.name
			return
		}
		return
	}
}

@(private)
inspection_surface_record :: proc(
	catalog_generation: Profile_Catalog_Generation,
	surface: Command_Entry_Surface_Definition,
	command: Command_Handle,
	active_profile: Profile_Identity,
	active_state: Interaction_State_Definition,
	registry: ^Registry_Data,
) -> Inspection_Record {
	result := Inspection_Record {
		kind = .Surface,
		disposition = .Effective,
		active = true,
		catalog_generation = catalog_generation,
		profile = active_profile,
		state = active_state.identity,
		state_name = active_state.name,
		state_admits_text_input = active_state.admits_text_input,
		state_admitted_effects = active_state.admitted_effects,
		command = command,
		command_entry_surface = surface.identity,
		command_entry_surface_name = surface.name,
		provenance = surface.provenance,
		effects_admitted = true,
	}
	if registry != nil {
		entry, found := resolve_command(registry, command)
		if found {
			result.command_name = entry_name(entry)
			result.effects_admitted = interaction_state_admits(active_state, entry.effects)
		}
	}
	return result
}

@(private)
layered_binding_inspection_record :: proc(
	data: ^Snapshot_Data,
	registry: ^Registry_Data,
	compiled_map: ^Compiled_Map,
	binding: ^Layered_Compiled_Binding,
) -> Inspection_Record {
	effective := resolved_command(data, binding.compiled.command)
	return Inspection_Record {
		kind = .Binding,
		disposition = layered_binding_disposition(data, compiled_map, binding),
		sequence = Key_Sequence {
			strokes = binding.compiled.strokes,
			stroke_count = binding.compiled.stroke_count,
		},
		command = effective,
		command_name = command_handle_name(registry, effective),
		original_command = binding.original_command,
		original_command_name = command_handle_name(registry, binding.original_command),
		map_identity = compiled_map.identity,
		map_name = compiled_map_name(compiled_map),
		owner = compiled_map.owner,
		precedence = compiled_map.precedence,
		priority = compiled_map.priority,
		active = compiled_map.active,
		operation = binding.operation,
		provenance = compiled_provenance_view(&binding.provenance),
		protected = compiled_map.precedence == .Protected_Recovery,
		protection_reason = string(binding.protection_reason[:binding.protection_reason_count]),
	}
}

@(private)
layered_remap_inspection_record :: proc(
	data: ^Snapshot_Data,
	registry: ^Registry_Data,
	compiled_map: ^Compiled_Map,
	remap: ^Compiled_Remap,
) -> Inspection_Record {
	disposition := Inspection_Disposition.Inactive
	if compiled_map.active {
		disposition = .Shadowed
		for &candidate_map in data.layered_maps {
			if !candidate_map.active {
				continue
			}
			start := int(candidate_map.remap_start)
			end := start + int(candidate_map.remap_count)
			for &candidate in data.layered_remaps[start:end] {
				if candidate.from == remap.from {
					if &candidate_map == compiled_map && &candidate == remap {
						disposition = .Effective
					}
					return Inspection_Record {
						kind = .Remap,
						disposition = disposition,
						command = remap.to,
						command_name = command_handle_name(registry, remap.to),
						original_command = remap.from,
						original_command_name = command_handle_name(registry, remap.from),
						remap_target = remap.to,
						remap_target_name = command_handle_name(registry, remap.to),
						map_identity = compiled_map.identity,
						map_name = compiled_map_name(compiled_map),
						owner = compiled_map.owner,
						precedence = compiled_map.precedence,
						priority = compiled_map.priority,
						active = compiled_map.active,
						provenance = compiled_provenance_view(&remap.provenance),
					}
				}
			}
		}
	}
	return Inspection_Record {
		kind = .Remap,
		disposition = disposition,
		command = remap.to,
		command_name = command_handle_name(registry, remap.to),
		original_command = remap.from,
		original_command_name = command_handle_name(registry, remap.from),
		remap_target = remap.to,
		remap_target_name = command_handle_name(registry, remap.to),
		map_identity = compiled_map.identity,
		map_name = compiled_map_name(compiled_map),
		owner = compiled_map.owner,
		precedence = compiled_map.precedence,
		priority = compiled_map.priority,
		active = compiled_map.active,
		provenance = compiled_provenance_view(&remap.provenance),
	}
}

@(private)
layered_map_inspection_record :: proc(compiled_map: ^Compiled_Map) -> Inspection_Record {
	disposition := Inspection_Disposition.Inactive
	if compiled_map.active {
		disposition = .Effective
	}
	return Inspection_Record {
		kind = .Map,
		disposition = disposition,
		map_identity = compiled_map.identity,
		map_name = compiled_map_name(compiled_map),
		owner = compiled_map.owner,
		precedence = compiled_map.precedence,
		priority = compiled_map.priority,
		active = compiled_map.active,
		provenance = compiled_provenance_view(&compiled_map.provenance),
		protected = compiled_map.precedence == .Protected_Recovery,
	}
}

@(private)
legacy_binding_inspection_record :: proc(
	registry: ^Registry_Data,
	binding: ^Compiled_Binding,
) -> Inspection_Record {
	return Inspection_Record {
		kind = .Binding,
		disposition = .Effective,
		sequence = Key_Sequence{strokes = binding.strokes, stroke_count = binding.stroke_count},
		command = binding.command,
		command_name = command_handle_name(registry, binding.command),
		original_command = binding.command,
		original_command_name = command_handle_name(registry, binding.command),
		active = true,
		operation = .Bind,
	}
}

@(private)
inspection_rejection_record :: proc(failure: Failure_Context) -> Inspection_Record {
	return Inspection_Record {
		kind = .Rejection,
		disposition = .Rejected,
		command = failure.command,
		map_identity = failure.map_identity,
		owner = failure.owner,
		protected = failure.code == .Protected_Binding || failure.code == .Unsupported_Protected_Input,
		failure = failure,
	}
}

@(private)
layered_binding_disposition :: proc(
	data: ^Snapshot_Data,
	compiled_map: ^Compiled_Map,
	binding: ^Layered_Compiled_Binding,
) -> Inspection_Disposition {
	if !compiled_map.active {
		return .Inactive
	}
	sequence := Key_Sequence{strokes = binding.compiled.strokes, stroke_count = binding.compiled.stroke_count}
	for &candidate_map in data.layered_maps {
		if !candidate_map.active {
			continue
		}
		candidate := layered_map_exact_binding(data, &candidate_map, sequence)
		if candidate == nil {
			continue
		}
		if &candidate_map == compiled_map && candidate == binding {
			if binding.operation == .Mask {
				return .Masked
			}
			return .Effective
		}
		return .Shadowed
	}
	return .Shadowed
}

@(private)
layered_map_exact_binding :: proc(
	data: ^Snapshot_Data,
	compiled_map: ^Compiled_Map,
	sequence: Key_Sequence,
) -> ^Layered_Compiled_Binding {
	query := Compiled_Binding{strokes = sequence.strokes, stroke_count = sequence.stroke_count}
	start := int(compiled_map.binding_start)
	end := start + int(compiled_map.binding_count)
	for &binding in data.layered_bindings[start:end] {
		if sequence_compare(binding.compiled, query) == 0 {
			return &binding
		}
	}
	return nil
}

@(private)
command_handle_name :: proc(registry: ^Registry_Data, handle: Command_Handle) -> string {
	entry, ok := resolve_command(registry, handle)
	if !ok {
		return ""
	}
	return entry_name(entry)
}

@(private)
compiled_map_name :: proc(compiled_map: ^Compiled_Map) -> string {
	return string(compiled_map.name[:compiled_map.name_count])
}

@(private)
compiled_provenance_view :: proc(provenance: ^Compiled_Provenance) -> Definition_Provenance {
	return Definition_Provenance {
		provider = string(provenance.provider[:provenance.provider_count]),
		source = string(provenance.source[:provenance.source_count]),
		location = string(provenance.location[:provenance.location_count]),
	}
}

@(private)
inspection_limit_failure :: proc(data: ^Snapshot_Data, actual: int) -> Failure_Context {
	return Failure_Context {
		code = .Inspection_Limit,
		registry_generation = data.registry_generation,
		snapshot_generation = data.generation,
		limit = u64(data.inspection_limit),
		actual = u64(actual),
	}
}

@(private)
inspection_record_text_bytes :: proc(record: Inspection_Record) -> int {
	return len(record.command_name) + len(record.original_command_name) +
		len(record.remap_target_name) + len(record.map_name) +
		len(record.profile_name) + len(record.state_name) +
		len(record.command_entry_surface_name) +
		len(record.protection_reason) + len(record.provenance.provider) +
		len(record.provenance.source) + len(record.provenance.location)
}

@(private)
inspection_record_copy :: proc(
	record: Inspection_Record,
	storage: []u8,
	offset: int,
	selectors: []Profile_State_Selector,
	selector_offset: int,
) -> (Inspection_Record, int, int) {
	result := record
	cursor := offset
	selector_cursor := selector_offset
	result.command_name, cursor = inspection_copy_text(storage, cursor, record.command_name)
	result.original_command_name, cursor = inspection_copy_text(storage, cursor, record.original_command_name)
	result.remap_target_name, cursor = inspection_copy_text(storage, cursor, record.remap_target_name)
	result.map_name, cursor = inspection_copy_text(storage, cursor, record.map_name)
	result.profile_name, cursor = inspection_copy_text(storage, cursor, record.profile_name)
	result.state_name, cursor = inspection_copy_text(storage, cursor, record.state_name)
	result.command_entry_surface_name, cursor = inspection_copy_text(
		storage,
		cursor,
		record.command_entry_surface_name,
	)
	result.protection_reason, cursor = inspection_copy_text(storage, cursor, record.protection_reason)
	result.provenance.provider, cursor = inspection_copy_text(storage, cursor, record.provenance.provider)
	result.provenance.source, cursor = inspection_copy_text(storage, cursor, record.provenance.source)
	result.provenance.location, cursor = inspection_copy_text(storage, cursor, record.provenance.location)
	if len(record.selectors) > 0 {
		result.selectors = selectors[selector_cursor:selector_cursor + len(record.selectors)]
		copy(result.selectors, record.selectors)
		selector_cursor += len(record.selectors)
	}
	return result, cursor, selector_cursor
}

@(private)
inspection_copy_text :: proc(storage: []u8, offset: int, value: string) -> (string, int) {
	copy(storage[offset:], transmute([]u8)value)
	return string(storage[offset:offset + len(value)]), offset + len(value)
}

@(private)
inspection_result_state_destroy :: proc(state: ^Inspection_Result_State) {
	allocator := state.allocator
	if state.text != nil {
		delete(state.text, allocator)
	}
	if state.selectors != nil {
		delete(state.selectors, allocator)
	}
	if state.records != nil {
		delete(state.records, allocator)
	}
	free(state, allocator)
}
