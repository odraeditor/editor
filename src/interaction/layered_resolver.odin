// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package interaction

import "base:runtime"
import "core:slice"

@(private)
Compiled_Provenance :: struct {
	provider:       [MAX_SOURCE_BYTES]u8,
	provider_count: u16,
	source:         [MAX_SOURCE_BYTES]u8,
	source_count:   u16,
	location:       [MAX_LOCATION_BYTES]u8,
	location_count: u16,
}

@(private)
Compiled_Map :: struct {
	identity:      Map_Identity,
	owner:         Owner_Handle,
	precedence:    Precedence_Class,
	priority:      i32,
	unmatched_input_policy: Unmatched_Input_Policy,
	active:        bool,
	binding_start: u32,
	binding_count: u16,
	remap_start:   u32,
	remap_count:   u16,
	trie_start:    u32,
	trie_node_count: u32,
	name:          [MAX_IDENTITY_BYTES]u8,
	name_count:    u8,
	provenance:    Compiled_Provenance,
}

@(private)
Compiled_Remap :: struct {
	from:       Command_Handle,
	to:         Command_Handle,
	map_slot:   u16,
	provenance: Compiled_Provenance,
}

@(private)
Compiled_Trie_Node :: struct {
	id:                     u32,
	parent_id:              u32,
	stroke:                 Key_Stroke,
	terminal_binding_index: u32,
	has_children:           bool,
}

@(private)
Layered_Compiled_Binding :: struct {
	compiled:         Compiled_Binding,
	map_slot:         u16,
	operation:        Binding_Operation,
	original_command: Command_Handle,
	provenance:       Compiled_Provenance,
	protection_reason: [MAX_PROTECTION_REASON_BYTES]u8,
	protection_reason_count: u16,
}

/* profile_snapshot_compile validates and atomically replaces one layered profile snapshot. */
profile_snapshot_compile :: proc(
	snapshot: ^Resolution_Snapshot,
	registry: ^Command_Registry,
	generation: Snapshot_Generation,
	profile: Profile_Definition,
	active_context: Active_Context,
	policy: Resolution_Policy,
	allocator: runtime.Allocator,
) -> (ok: bool, failure: Failure_Context) {
	assert(snapshot != nil)
	registry_state := registry_data(registry)
	if registry_state == nil || registry_state.state != .Ready {
		return false, registry_failure(registry, .Invalid_Registry)
	}
	base_failure := Failure_Context {
		registry_generation = registry_state.generation,
		snapshot_generation = generation,
		profile = profile.identity,
		ctx = active_context.identity,
	}
	if snapshot.closed || generation == Snapshot_Generation(0) {
		base_failure.code = .Invalid_Snapshot
		return false, base_failure
	}
	current := snapshot_data(snapshot)
	if current != nil && current.generation == generation {
		base_failure.code = .Generation_Limit
		return false, base_failure
	}
	if !profile_identity_valid(profile.identity) ||
	   !valid_bounded_text(profile.name, MAX_IDENTITY_BYTES, false) {
		base_failure.code = .Invalid_Profile
		return false, base_failure
	}
	if !context_handle_valid(active_context.identity) {
		base_failure.code = .Invalid_Context
		return false, base_failure
	}
	if !resolution_policy_valid(policy) {
		base_failure.code = .Invalid_Profile
		return false, base_failure
	}
	if len(profile.maps) == 0 {
		base_failure.code = .Map_Limit
		base_failure.limit = u64(policy.max_maps)
		base_failure.actual = u64(len(profile.maps))
		return false, base_failure
	}
	protected_bindings: [PROTECTED_RECOVERY_BINDING_COUNT]Layered_Binding_Definition
	effective_maps: [MAX_MAPS]Map_Definition
	effective_map_count := 0
	if policy.enforce_protected_policy {
		catalog := protected_binding_catalog()
		for entry, entry_index in catalog {
			if !protected_sequence_supported(entry.sequence, policy.frontend) {
				base_failure.code = .Unsupported_Protected_Input
				base_failure.binding_index = u32(entry_index)
				base_failure.stroke_count = entry.sequence.stroke_count
				return false, base_failure
			}
		}
		protected_failure := validate_external_protected_conflicts(profile.maps, catalog[:])
		if protected_failure.code != .None {
			protected_failure.registry_generation = registry_state.generation
			protected_failure.snapshot_generation = generation
			protected_failure.profile = profile.identity
			return false, protected_failure
		}
		protected_layered_bindings(&protected_bindings)
		effective_maps[effective_map_count] = protected_map_definition(protected_bindings[:])
		effective_map_count += 1
	}
	if effective_map_count + len(profile.maps) > int(policy.max_maps) {
		base_failure.code = .Map_Limit
		base_failure.limit = u64(policy.max_maps)
		base_failure.actual = u64(effective_map_count + len(profile.maps))
		return false, base_failure
	}
	for map_definition in profile.maps {
		effective_maps[effective_map_count] = map_definition
		effective_map_count += 1
	}
	effective_profile := profile
	effective_profile.maps = effective_maps[:effective_map_count]
	definition_bytes, binding_capacity, remap_capacity, trie_capacity, usage_ok := profile_definition_usage(effective_profile, policy)
	if !usage_ok {
		base_failure.code = .Definition_Memory_Limit
		base_failure.limit = policy.max_definition_bytes
		base_failure.actual = definition_bytes
		return false, base_failure
	}
	if allocator.procedure == nil {
		base_failure.code = .Persistent_Memory_Limit
		return false, base_failure
	}
	candidate, allocation_error := new(Snapshot_Data, allocator)
	if allocation_error != nil {
		base_failure.code = .Persistent_Memory_Limit
		base_failure.actual = u64(size_of(Snapshot_Data))
		return false, base_failure
	}
	candidate.state = .Ready
	candidate.generation = generation
	candidate.registry = registry_state
	candidate.registry_generation = registry_state.generation
	candidate.profile = profile.identity
	candidate.ctx = active_context.identity
	candidate.allocator = allocator
	candidate.inspection_limit = policy.max_inspection_alternatives
	candidate.layered = true
	candidate.storage_bytes = u64(size_of(Snapshot_Data))

	candidate.layered_maps, allocation_error = make([]Compiled_Map, len(effective_profile.maps), allocator)
	if allocation_error != nil {
		free(candidate, allocator)
		base_failure.code = .Persistent_Memory_Limit
		base_failure.actual = u64(len(effective_profile.maps) * size_of(Compiled_Map))
		return false, base_failure
	}
	candidate.layered_bindings, allocation_error = make(
		[]Layered_Compiled_Binding,
		binding_capacity,
		allocator,
	)
	if allocation_error != nil {
		delete(candidate.layered_maps, allocator)
		free(candidate, allocator)
		base_failure.code = .Persistent_Memory_Limit
		base_failure.actual = u64(binding_capacity * size_of(Layered_Compiled_Binding))
		return false, base_failure
	}
	candidate.layered_remaps, allocation_error = make([]Compiled_Remap, remap_capacity, allocator)
	if allocation_error != nil {
		delete(candidate.layered_bindings, allocator)
		delete(candidate.layered_maps, allocator)
		free(candidate, allocator)
		base_failure.code = .Persistent_Memory_Limit
		base_failure.actual = u64(remap_capacity * size_of(Compiled_Remap))
		return false, base_failure
	}
	candidate.layered_trie_nodes, allocation_error = make([]Compiled_Trie_Node, trie_capacity, allocator)
	if allocation_error != nil {
		delete(candidate.layered_remaps, allocator)
		delete(candidate.layered_bindings, allocator)
		delete(candidate.layered_maps, allocator)
		free(candidate, allocator)
		base_failure.code = .Persistent_Memory_Limit
		base_failure.actual = u64(trie_capacity * size_of(Compiled_Trie_Node))
		return false, base_failure
	}
	candidate.storage_bytes += u64(len(candidate.layered_maps) * size_of(Compiled_Map))
	candidate.storage_bytes += u64(len(candidate.layered_bindings) * size_of(Layered_Compiled_Binding))
	candidate.storage_bytes += u64(len(candidate.layered_remaps) * size_of(Compiled_Remap))
	candidate.storage_bytes += u64(len(candidate.layered_trie_nodes) * size_of(Compiled_Trie_Node))
	if candidate.storage_bytes > policy.max_snapshot_bytes {
		actual_storage_bytes := candidate.storage_bytes
		release_unretained_layered_candidate(candidate)
		base_failure.code = .Keymap_Memory_Limit
		base_failure.limit = policy.max_snapshot_bytes
		base_failure.actual = actual_storage_bytes
		return false, base_failure
	}

	fallback, fallback_ok, fallback_failure := lookup_command_data(
		registry_state,
		profile.text_fallback_name,
	)
	if !fallback_ok {
		release_unretained_layered_candidate(candidate)
		fallback_failure.code = .Missing_Text_Fallback
		fallback_failure.snapshot_generation = generation
		fallback_failure.profile = profile.identity
		return false, fallback_failure
	}
	fallback_entry, fallback_entry_ok := resolve_command(registry_state, fallback)
	assert(fallback_entry_ok)
	if fallback_entry.invocation != .Text_Input ||
	   fallback_entry.text_requirement != .Required ||
	   fallback_entry.implementation != .Native {
		release_unretained_layered_candidate(candidate)
		base_failure.code = .Invalid_Text_Fallback
		base_failure.command = fallback
		return false, base_failure
	}
	candidate.text_fallback = fallback

	ordered_indices: [MAX_MAPS]int
	ordered, ordering_failure := order_profile_maps(
		effective_profile.maps,
		ordered_indices[:len(effective_profile.maps)],
	)
	if !ordered {
		release_unretained_layered_candidate(candidate)
		ordering_failure.registry_generation = registry_state.generation
		ordering_failure.snapshot_generation = generation
		ordering_failure.profile = profile.identity
		return false, ordering_failure
	}

	compiled_count := 0
	compiled_remap_count := 0
	compiled_trie_count := 0
	for output_slot in 0 ..< len(effective_profile.maps) {
		source_map := effective_profile.maps[ordered_indices[output_slot]]
		compiled_map := &candidate.layered_maps[output_slot]
		map_failure := compile_map_header(
			compiled_map,
			source_map,
			active_context,
			policy,
		)
		if map_failure.code != .None {
			release_unretained_layered_candidate(candidate)
			map_failure.registry_generation = registry_state.generation
			map_failure.snapshot_generation = generation
			map_failure.profile = profile.identity
			return false, map_failure
		}
		compiled_map.binding_start = u32(compiled_count)
		compiled_map.remap_start = u32(compiled_remap_count)
		map_failure = compile_map_remaps(
			candidate,
			compiled_map,
			u16(output_slot),
			source_map,
			registry_state,
			&compiled_remap_count,
		)
		if map_failure.code != .None {
			release_unretained_layered_candidate(candidate)
			map_failure.registry_generation = registry_state.generation
			map_failure.snapshot_generation = generation
			map_failure.profile = profile.identity
			map_failure.map_identity = source_map.identity
			return false, map_failure
		}
		map_failure = compile_map_bindings(
			candidate,
			compiled_map,
			u16(output_slot),
			source_map,
			registry_state,
			&compiled_count,
		)
		if map_failure.code != .None {
			release_unretained_layered_candidate(candidate)
			map_failure.registry_generation = registry_state.generation
			map_failure.snapshot_generation = generation
			map_failure.profile = profile.identity
			map_failure.map_identity = source_map.identity
			return false, map_failure
		}
		compiled_map.trie_start = u32(compiled_trie_count)
		map_failure = compile_map_trie(candidate, compiled_map, &compiled_trie_count)
		if map_failure.code != .None {
			release_unretained_layered_candidate(candidate)
			map_failure.registry_generation = registry_state.generation
			map_failure.snapshot_generation = generation
			map_failure.profile = profile.identity
			map_failure.map_identity = source_map.identity
			return false, map_failure
		}
		candidate.map_count += 1
		if compiled_map.active {
			candidate.active_map_count += 1
		}
	}
	if candidate.active_map_count > policy.max_active_maps {
		release_unretained_layered_candidate(candidate)
		base_failure.code = .Active_Map_Limit
		base_failure.limit = u64(policy.max_active_maps)
		base_failure.actual = u64(candidate.active_map_count)
		return false, base_failure
	}
	candidate.binding_count = u16(compiled_count)

	conflict_failure := validate_layered_conflicts(candidate, effective_profile.maps, policy)
	if conflict_failure.code != .None {
		release_unretained_layered_candidate(candidate)
		conflict_failure.registry_generation = registry_state.generation
		conflict_failure.snapshot_generation = generation
		conflict_failure.profile = profile.identity
		return false, conflict_failure
	}

	retained_without_current := registry_state.retained_maps
	if current != nil && current.registry == registry_state {
		assert(retained_without_current > 0)
		retained_without_current -= 1
	}
	if retained_without_current >= MAX_ACTIVE_SNAPSHOTS {
		release_unretained_layered_candidate(candidate)
		base_failure.code = .Snapshot_Limit
		base_failure.limit = MAX_ACTIVE_SNAPSHOTS
		base_failure.actual = u64(retained_without_current) + 1
		return false, base_failure
	}

	registry_state.retained_maps += 1
	snapshot.state = candidate
	if current != nil {
		release_snapshot_data(current)
	}
	return true, {}
}

@(private)
profile_definition_usage :: proc(
	profile: Profile_Definition,
	policy: Resolution_Policy,
) -> (bytes: u64, binding_count, remap_count, trie_node_count: int, ok: bool) {
	bytes = u64(len(profile.name) + len(profile.text_fallback_name))
	for map_definition in profile.maps {
		if len(map_definition.bindings) > int(policy.max_bindings_per_map) ||
		   len(map_definition.ordering_constraints) > int(policy.max_ordering_constraints) {
			return bytes, binding_count, remap_count, trie_node_count, false
		}
		binding_count += len(map_definition.bindings)
		remap_count += len(map_definition.remaps)
		if binding_count > int(policy.max_total_bindings) {
			return bytes, binding_count, remap_count, trie_node_count, false
		}
		bytes += u64(len(map_definition.name))
		bytes += provenance_bytes(map_definition.provenance)
		bytes += u64(len(map_definition.ordering_constraints) * size_of(Ordering_Constraint))
		for binding in map_definition.bindings {
			trie_node_count += int(binding.sequence.stroke_count)
			bytes += u64(binding.sequence.stroke_count) * u64(size_of(Key_Stroke))
			bytes += u64(len(binding.command_name) + len(binding.protection_reason))
			bytes += provenance_bytes(binding.provenance)
		}
		for remap in map_definition.remaps {
			bytes += u64(len(remap.from_command_name) + len(remap.to_command_name))
			bytes += provenance_bytes(remap.provenance)
		}
		if bytes > policy.max_definition_bytes {
			return bytes, binding_count, remap_count, trie_node_count, false
		}
	}
	return bytes, binding_count, remap_count, trie_node_count, true
}

@(private)
compile_map_trie :: proc(
	candidate: ^Snapshot_Data,
	compiled_map: ^Compiled_Map,
	compiled_count: ^int,
) -> Failure_Context {
	start := int(compiled_map.binding_start)
	end := start + int(compiled_map.binding_count)
	node_start := compiled_count^
	for binding_index in start ..< end {
		binding := candidate.layered_bindings[binding_index]
		parent_id := u32(0)
		terminal_index := -1
		for stroke_index in 0 ..< int(binding.compiled.stroke_count) {
			node_index := find_trie_node_unsorted(
				candidate.layered_trie_nodes,
				node_start,
				compiled_count^,
				parent_id,
				binding.compiled.strokes[stroke_index],
			)
			if node_index < 0 {
				node_index = compiled_count^
				local_id := u32(node_index - node_start + 1)
				candidate.layered_trie_nodes[node_index] = Compiled_Trie_Node {
					id = local_id,
					parent_id = parent_id,
					stroke = binding.compiled.strokes[stroke_index],
				}
				if parent_id != 0 {
					parent_index := find_trie_node_by_id(
						candidate.layered_trie_nodes,
						node_start,
						compiled_count^,
						parent_id,
					)
					assert(parent_index >= 0)
					candidate.layered_trie_nodes[parent_index].has_children = true
				}
				compiled_count^ += 1
			}
			node := &candidate.layered_trie_nodes[node_index]
			if stroke_index + 1 < int(binding.compiled.stroke_count) &&
			   node.terminal_binding_index != 0 {
				return Failure_Context{code = .Ambiguous_Binding, binding_index = u32(binding_index - start)}
			}
			parent_id = node.id
			terminal_index = node_index
		}
		assert(terminal_index >= 0)
		terminal := &candidate.layered_trie_nodes[terminal_index]
		if terminal.terminal_binding_index != 0 || terminal.has_children {
			return Failure_Context{code = .Ambiguous_Binding, binding_index = u32(binding_index - start)}
		}
		terminal.terminal_binding_index = u32(binding_index + 1)
	}
	compiled_map.trie_node_count = u32(compiled_count^ - node_start)
	slice.sort_by(candidate.layered_trie_nodes[node_start:compiled_count^], trie_node_less)
	return {}
}

@(private)
compile_map_remaps :: proc(
	candidate: ^Snapshot_Data,
	compiled_map: ^Compiled_Map,
	map_slot: u16,
	definition: Map_Definition,
	registry: ^Registry_Data,
	compiled_count: ^int,
) -> Failure_Context {
	start := compiled_count^
	for remap, remap_index in definition.remaps {
		if !provenance_valid(remap.provenance) {
			return Failure_Context{code = .Invalid_Provenance, binding_index = u32(remap_index)}
		}
		from, from_ok, _ := lookup_command_data(registry, remap.from_command_name)
		to, to_ok, _ := lookup_command_data(registry, remap.to_command_name)
		if !from_ok || !to_ok || from == to {
			return Failure_Context{code = .Invalid_Remap, binding_index = u32(remap_index)}
		}
		for index in start ..< compiled_count^ {
			if candidate.layered_remaps[index].from == from {
				return Failure_Context{code = .Invalid_Remap, binding_index = u32(remap_index)}
			}
		}
		entry := &candidate.layered_remaps[compiled_count^]
		entry.from = from
		entry.to = to
		entry.map_slot = map_slot
		copy_provenance(&entry.provenance, remap.provenance)
		compiled_count^ += 1
	}
	compiled_map.remap_count = u16(compiled_count^ - start)
	return {}
}

@(private)
compile_map_header :: proc(
	output: ^Compiled_Map,
	definition: Map_Definition,
	active_context: Active_Context,
	policy: Resolution_Policy,
) -> Failure_Context {
	if !map_identity_valid(definition.identity) ||
	   !valid_bounded_text(definition.name, MAX_IDENTITY_BYTES, false) {
		return Failure_Context{code = .Invalid_Map, map_identity = definition.identity}
	}
	if definition.precedence == .Invalid {
		return Failure_Context{code = .Invalid_Precedence, map_identity = definition.identity}
	}
	if definition.unmatched_input_policy == .Invalid {
		return Failure_Context{code = .Invalid_Map, map_identity = definition.identity}
	}
	if len(definition.bindings) > int(policy.max_bindings_per_map) {
		return Failure_Context {
			code = .Map_Binding_Limit,
			map_identity = definition.identity,
			limit = u64(policy.max_bindings_per_map),
			actual = u64(len(definition.bindings)),
		}
	}
	if !provenance_valid(definition.provenance) {
		return Failure_Context{code = .Invalid_Provenance, map_identity = definition.identity}
	}
	active, owner_failure := map_is_active(definition, active_context)
	if owner_failure.code != .None {
		owner_failure.map_identity = definition.identity
		return owner_failure
	}
	output.identity = definition.identity
	output.owner = definition.owner
	output.precedence = definition.precedence
	output.priority = definition.priority
	output.unmatched_input_policy = definition.unmatched_input_policy
	output.active = active
	copy(output.name[:len(definition.name)], transmute([]u8)definition.name)
	output.name_count = u8(len(definition.name))
	copy_provenance(&output.provenance, definition.provenance)
	return {}
}

@(private)
compile_map_bindings :: proc(
	candidate: ^Snapshot_Data,
	compiled_map: ^Compiled_Map,
	map_slot: u16,
	definition: Map_Definition,
	registry: ^Registry_Data,
	compiled_count: ^int,
) -> Failure_Context {
	start := compiled_count^
	for binding, binding_index in definition.bindings {
		if !sequence_valid(binding.sequence) {
			return Failure_Context {
				code = .Sequence_Limit,
				binding_index = u32(binding_index),
				limit = MAX_SEQUENCE_STROKES,
				actual = u64(binding.sequence.stroke_count),
			}
		}
		if !provenance_valid(binding.provenance) {
			return Failure_Context{code = .Invalid_Provenance, binding_index = u32(binding_index)}
		}
		if definition.precedence == .Protected_Recovery {
			if !valid_bounded_text(binding.protection_reason, MAX_PROTECTION_REASON_BYTES, false) {
				return Failure_Context{code = .Invalid_Description, binding_index = u32(binding_index)}
			}
		} else if len(binding.protection_reason) != 0 {
			return Failure_Context{code = .Invalid_Operation, binding_index = u32(binding_index)}
		}
		existing := find_compiled_in_map(candidate.layered_bindings, start, compiled_count^, binding.sequence)
		switch binding.operation {
		case .Bind, .Mask:
			if existing >= 0 {
				return Failure_Context{code = .Duplicate_Binding, binding_index = u32(binding_index)}
			}
			entry := &candidate.layered_bindings[compiled_count^]
			failure := populate_layered_binding(entry, binding, map_slot, registry)
			if failure.code != .None {
				failure.binding_index = u32(binding_index)
				return failure
			}
			compiled_count^ += 1
		case .Replace:
			if existing < 0 {
				return Failure_Context{code = .Invalid_Operation, binding_index = u32(binding_index)}
			}
			failure := populate_layered_binding(
				&candidate.layered_bindings[existing],
				binding,
				map_slot,
				registry,
			)
			if failure.code != .None {
				failure.binding_index = u32(binding_index)
				return failure
			}
		case .Unbind:
			if existing < 0 || len(binding.command_name) != 0 {
				return Failure_Context{code = .Invalid_Operation, binding_index = u32(binding_index)}
			}
			copy(
				candidate.layered_bindings[existing:compiled_count^ - 1],
				candidate.layered_bindings[existing + 1:compiled_count^],
			)
			compiled_count^ -= 1
		case .Invalid:
			return Failure_Context{code = .Invalid_Operation, binding_index = u32(binding_index)}
		}
	}
	compiled_map.binding_count = u16(compiled_count^ - start)
	range_end := compiled_count^
	slice.sort_by(candidate.layered_bindings[start:range_end], layered_binding_less)
	for index in start + 1 ..< range_end {
		previous := candidate.layered_bindings[index - 1].compiled
		current := candidate.layered_bindings[index].compiled
		if sequence_prefix(previous, current) {
			return Failure_Context{code = .Ambiguous_Binding, binding_index = u32(index - start)}
		}
	}

	for index in start ..< range_end {
		entry, entry_ok := resolve_command(registry, candidate.layered_bindings[index].compiled.command)
		if entry_ok && entry.invocation == .Cancellation {
			if candidate.layered_bindings[index].compiled.stroke_count != 1 || candidate.has_cancellation {
				return Failure_Context{code = .Invalid_Binding, binding_index = u32(index - start)}
			}
			candidate.cancellation_command = entry.handle
			candidate.has_cancellation = true
		}
	}
	return {}
}

@(private)
populate_layered_binding :: proc(
	output: ^Layered_Compiled_Binding,
	definition: Layered_Binding_Definition,
	map_slot: u16,
	registry: ^Registry_Data,
) -> Failure_Context {
	command: Command_Handle
	if definition.operation != .Mask {
		ok: bool
		failure: Failure_Context
		command, ok, failure = lookup_command_data(registry, definition.command_name)
		if !ok {
			return failure
		}
	} else if len(definition.command_name) != 0 {
		return Failure_Context{code = .Invalid_Operation}
	}
	output^ = Layered_Compiled_Binding {
		compiled = Compiled_Binding {
			strokes = definition.sequence.strokes,
			stroke_count = definition.sequence.stroke_count,
			command = command,
		},
		map_slot = map_slot,
		operation = definition.operation,
		original_command = command,
	}
	copy_provenance(&output.provenance, definition.provenance)
	if len(definition.protection_reason) > 0 {
		copy(
			output.protection_reason[:len(definition.protection_reason)],
			transmute([]u8)definition.protection_reason,
		)
		output.protection_reason_count = u16(len(definition.protection_reason))
	}
	return {}
}

@(private)
validate_external_protected_conflicts :: proc(
	maps: []Map_Definition,
	catalog: []Protected_Binding,
) -> Failure_Context {
	for map_definition in maps {
		if map_definition.precedence == .Protected_Recovery ||
		   map_definition.identity.id == PROTECTED_RECOVERY_MAP_ID {
			return Failure_Context {
				code = .Protected_Binding,
				map_identity = map_definition.identity,
			}
		}
		for binding, binding_index in map_definition.bindings {
			for protected in catalog {
				if key_sequences_overlap(binding.sequence, protected.sequence) {
					return Failure_Context {
						code = .Protected_Binding,
						map_identity = map_definition.identity,
						binding_index = u32(binding_index),
						stroke_count = binding.sequence.stroke_count,
					}
				}
			}
		}
		for remap, remap_index in map_definition.remaps {
			for protected in catalog {
				if remap.from_command_name == protected.command_name {
					return Failure_Context {
						code = .Protected_Binding,
						map_identity = map_definition.identity,
						binding_index = u32(remap_index),
					}
				}
			}
		}
	}
	return {}
}

@(private)
key_sequences_overlap :: proc(left, right: Key_Sequence) -> bool {
	left_compiled := Compiled_Binding {
		strokes = left.strokes,
		stroke_count = left.stroke_count,
	}
	right_compiled := Compiled_Binding {
		strokes = right.strokes,
		stroke_count = right.stroke_count,
	}
	return sequence_compare(left_compiled, right_compiled) == 0 ||
		sequence_prefix(left_compiled, right_compiled) ||
		sequence_prefix(right_compiled, left_compiled)
}

@(private)
order_profile_maps :: proc(
	maps: []Map_Definition,
	output: []int,
) -> (ok: bool, failure: Failure_Context) {
	if len(maps) != len(output) {
		return false, Failure_Context{code = .Invalid_Ordering}
	}
	for map_definition, map_index in maps {
		if !map_identity_valid(map_definition.identity) {
			return false, Failure_Context{code = .Invalid_Map, map_identity = map_definition.identity}
		}
		for previous_index in 0 ..< map_index {
			if maps[previous_index].identity.id == map_definition.identity.id {
				return false, Failure_Context{code = .Invalid_Map, map_identity = map_definition.identity}
			}
		}
		for constraint in map_definition.ordering_constraints {
			target_index := map_index_by_id(maps, constraint.other)
			if constraint.relation == .Invalid || target_index < 0 ||
			   target_index == map_index ||
			   maps[target_index].precedence != map_definition.precedence {
				return false, Failure_Context {
					code = .Invalid_Ordering,
					map_identity = map_definition.identity,
				}
			}
		}
	}
	selected: [MAX_MAPS]bool
	for output_index in 0 ..< len(maps) {
		best := -1
		for candidate_index in 0 ..< len(maps) {
			if selected[candidate_index] || map_has_unselected_predecessor(maps, candidate_index, selected[:len(maps)]) {
				continue
			}
			if best < 0 || map_definition_less(maps[candidate_index], maps[best]) {
				best = candidate_index
			}
		}
		if best < 0 {
			return false, Failure_Context{code = .Ordering_Cycle}
		}
		output[output_index] = best
		selected[best] = true
	}
	return true, {}
}

@(private)
map_has_unselected_predecessor :: proc(
	maps: []Map_Definition,
	candidate_index: int,
	selected: []bool,
) -> bool {
	candidate := maps[candidate_index]
	for source, source_index in maps {
		if selected[source_index] || source.precedence != candidate.precedence {
			continue
		}
		for constraint in source.ordering_constraints {
			target_index := map_index_by_id(maps, constraint.other)
			if target_index < 0 || maps[target_index].precedence != source.precedence ||
			   constraint.relation == .Invalid {
				return true
			}
			if constraint.relation == .Before && target_index == candidate_index {
				return true
			}
			if constraint.relation == .After && source_index == candidate_index && !selected[target_index] {
				return true
			}
		}
	}
	return false
}

@(private)
map_definition_less :: proc(left, right: Map_Definition) -> bool {
	if left.precedence != right.precedence {
		return left.precedence < right.precedence
	}
	if left.priority != right.priority {
		return left.priority > right.priority
	}
	return left.identity.id < right.identity.id
}

@(private)
validate_layered_conflicts :: proc(
	candidate: ^Snapshot_Data,
	source_maps: []Map_Definition,
	policy: Resolution_Policy,
) -> Failure_Context {
	for left_slot in 0 ..< len(candidate.layered_maps) {
		left := &candidate.layered_maps[left_slot]
		if !left.active {
			continue
		}
		for right_slot in left_slot + 1 ..< len(candidate.layered_maps) {
			right := &candidate.layered_maps[right_slot]
			if !right.active {
				continue
			}
			overlap := maps_overlap(candidate, left, right) || maps_remap_overlap(candidate, left, right)
			if left.precedence == right.precedence && left.priority == right.priority &&
			   overlap &&
			   !maps_explicitly_ordered(source_maps, left.identity.id, right.identity.id) {
				return Failure_Context {
					code = .Ordering_Conflict,
					map_identity = right.identity,
				}
			}
			if policy.enforce_protected_policy && left.precedence == .Protected_Recovery &&
			   overlap {
				return Failure_Context {
					code = .Protected_Binding,
					map_identity = right.identity,
				}
			}
		}
	}
	return {}
}

@(private)
maps_remap_overlap :: proc(candidate: ^Snapshot_Data, left, right: ^Compiled_Map) -> bool {
	left_start := int(left.remap_start)
	left_end := left_start + int(left.remap_count)
	right_start := int(right.remap_start)
	right_end := right_start + int(right.remap_count)
	for left_remap in candidate.layered_remaps[left_start:left_end] {
		for right_remap in candidate.layered_remaps[right_start:right_end] {
			if left_remap.from == right_remap.from {
				return true
			}
		}
	}
	return false
}

@(private)
maps_overlap :: proc(candidate: ^Snapshot_Data, left, right: ^Compiled_Map) -> bool {
	left_index := int(left.binding_start)
	right_index := int(right.binding_start)
	left_end := left_index + int(left.binding_count)
	right_end := right_index + int(right.binding_count)
	for left_index < left_end && right_index < right_end {
		comparison := sequence_compare(
			candidate.layered_bindings[left_index].compiled,
			candidate.layered_bindings[right_index].compiled,
		)
		if comparison == 0 {
			return true
		}
		if comparison < 0 {
			if sequence_prefix(
				candidate.layered_bindings[left_index].compiled,
				candidate.layered_bindings[right_index].compiled,
			) {
				return true
			}
			left_index += 1
		} else {
			if sequence_prefix(
				candidate.layered_bindings[right_index].compiled,
				candidate.layered_bindings[left_index].compiled,
			) {
				return true
			}
			right_index += 1
		}
	}
	return false
}

@(private)
maps_explicitly_ordered :: proc(maps: []Map_Definition, left, right: Map_ID) -> bool {
	return ordering_path_exists(maps, left, right) || ordering_path_exists(maps, right, left)
}

@(private)
ordering_path_exists :: proc(maps: []Map_Definition, from, to: Map_ID) -> bool {
	start := map_index_by_id(maps, from)
	if start < 0 {
		return false
	}
	visited: [MAX_MAPS]bool
	frontier: [MAX_MAPS]int
	frontier[0] = start
	frontier_count := 1
	visited[start] = true
	for cursor := 0; cursor < frontier_count; cursor += 1 {
		current := frontier[cursor]
		for source, source_index in maps {
			for constraint in source.ordering_constraints {
				target_index := map_index_by_id(maps, constraint.other)
				edge_from := source_index
				edge_to := target_index
				if constraint.relation == .After {
					edge_from, edge_to = edge_to, edge_from
				}
				if edge_from != current || edge_to < 0 || visited[edge_to] {
					continue
				}
				if maps[edge_to].identity.id == to {
					return true
				}
				visited[edge_to] = true
				frontier[frontier_count] = edge_to
				frontier_count += 1
			}
		}
	}
	return false
}

@(private)
layered_find_sequence :: proc(
	data: ^Snapshot_Data,
	query: Compiled_Binding,
) -> (exact: ^Compiled_Binding, prefix, masked: bool) {
	for compiled_map in &data.layered_maps {
		if !compiled_map.active {
			continue
		}
		node_start := int(compiled_map.trie_start)
		node_end := node_start + int(compiled_map.trie_node_count)
		parent_id := u32(0)
		terminal: ^Compiled_Trie_Node
		matched := true
		for stroke_index in 0 ..< int(query.stroke_count) {
			terminal = find_trie_node_sorted(
				data.layered_trie_nodes[node_start:node_end],
				parent_id,
				query.strokes[stroke_index],
			)
			if terminal == nil {
				matched = false
				break
			}
			parent_id = terminal.id
		}
		if !matched || terminal == nil {
			continue
		}
		if terminal.terminal_binding_index != 0 {
			binding := &data.layered_bindings[terminal.terminal_binding_index - 1]
			if binding.operation == .Mask {
				return nil, false, true
			}
			return &binding.compiled, false, false
		}
		if terminal.has_children {
			return nil, true, false
		}
	}
	return nil, false, false
}

@(private)
layered_unmatched_input_policy :: proc(
	data: ^Snapshot_Data,
) -> (policy: Unmatched_Input_Policy, compiled_map: ^Compiled_Map) {
	for current_map, map_index in data.layered_maps {
		if !current_map.active || current_map.unmatched_input_policy == .Fallthrough {
			continue
		}
		return current_map.unmatched_input_policy, &data.layered_maps[map_index]
	}
	return .Fallthrough, nil
}

@(private)
layered_remapped_command :: proc(data: ^Snapshot_Data, command: Command_Handle) -> Command_Handle {
	for compiled_map in data.layered_maps {
		if !compiled_map.active {
			continue
		}
		start := int(compiled_map.remap_start)
		end := start + int(compiled_map.remap_count)
		for remap in data.layered_remaps[start:end] {
			if remap.from == command {
				return remap.to
			}
		}
	}
	return command
}

@(private)
find_trie_node_sorted :: proc(
	nodes: []Compiled_Trie_Node,
	parent_id: u32,
	stroke: Key_Stroke,
) -> ^Compiled_Trie_Node {
	low := 0
	high := len(nodes)
	for low < high {
		middle := low + (high - low) / 2
		if trie_node_compare(nodes[middle], parent_id, stroke) < 0 {
			low = middle + 1
		} else {
			high = middle
		}
	}
	if low < len(nodes) && trie_node_compare(nodes[low], parent_id, stroke) == 0 {
		return &nodes[low]
	}
	return nil
}

@(private)
find_trie_node_unsorted :: proc(
	nodes: []Compiled_Trie_Node,
	start, end: int,
	parent_id: u32,
	stroke: Key_Stroke,
) -> int {
	for index in start ..< end {
		if nodes[index].parent_id == parent_id && nodes[index].stroke == stroke {
			return index
		}
	}
	return -1
}

@(private)
find_trie_node_by_id :: proc(
	nodes: []Compiled_Trie_Node,
	start, end: int,
	id: u32,
) -> int {
	for index in start ..< end {
		if nodes[index].id == id {
			return index
		}
	}
	return -1
}

@(private)
trie_node_less :: proc(left, right: Compiled_Trie_Node) -> bool {
	if left.parent_id != right.parent_id {
		return left.parent_id < right.parent_id
	}
	return stroke_compare(left.stroke, right.stroke) < 0
}

@(private)
trie_node_compare :: proc(node: Compiled_Trie_Node, parent_id: u32, stroke: Key_Stroke) -> int {
	if node.parent_id < parent_id {
		return -1
	}
	if node.parent_id > parent_id {
		return 1
	}
	return stroke_compare(node.stroke, stroke)
}

@(private)
layered_binding_less :: proc(left, right: Layered_Compiled_Binding) -> bool {
	return sequence_compare(left.compiled, right.compiled) < 0
}

@(private)
find_compiled_in_map :: proc(
	bindings: []Layered_Compiled_Binding,
	start, end: int,
	sequence: Key_Sequence,
) -> int {
	query := Compiled_Binding {
		strokes = sequence.strokes,
		stroke_count = sequence.stroke_count,
	}
	for index in start ..< end {
		if sequence_compare(bindings[index].compiled, query) == 0 {
			return index
		}
	}
	return -1
}

@(private)
map_is_active :: proc(
	definition: Map_Definition,
	active_context: Active_Context,
) -> (active: bool, failure: Failure_Context) {
	requirement := definition.context_requirement
	if requirement.ctx == (Context_Handle{}) && requirement.owner == (Owner_Handle{}) {
		return true, {}
	}
	if requirement.ctx.id != active_context.identity.id {
		return false, {}
	}
	if requirement.ctx.generation != active_context.identity.generation {
		return false, Failure_Context{code = .Stale_Context, ctx = requirement.ctx}
	}
	if !owner_handle_valid(requirement.owner) || definition.owner != requirement.owner {
		return false, Failure_Context{code = .Invalid_Owner, owner = requirement.owner}
	}
	for owner in active_context.owners {
		if owner.id == requirement.owner.id {
			if owner.generation != requirement.owner.generation {
				return false, Failure_Context{code = .Stale_Owner, owner = requirement.owner}
			}
			return true, {}
		}
	}
	return false, {}
}

@(private)
profile_identity_valid :: proc(identity: Profile_Identity) -> bool {
	return identity.id != Profile_ID(0) && identity.revision != Profile_Revision(0)
}

@(private)
map_identity_valid :: proc(identity: Map_Identity) -> bool {
	return identity.id != Map_ID(0) && identity.revision != Map_Revision(0)
}

@(private)
context_handle_valid :: proc(handle: Context_Handle) -> bool {
	return handle.id != Context_ID(0) && handle.generation != Context_Generation(0)
}

@(private)
owner_handle_valid :: proc(handle: Owner_Handle) -> bool {
	return handle.id != Owner_ID(0) && handle.generation != Owner_Generation(0)
}

@(private)
resolution_policy_valid :: proc(policy: Resolution_Policy) -> bool {
	return policy.max_maps > 0 && policy.max_maps <= MAX_MAPS &&
		policy.max_active_maps > 0 && policy.max_active_maps <= MAX_ACTIVE_MAPS &&
		policy.max_bindings_per_map > 0 && policy.max_bindings_per_map <= MAX_BINDINGS_PER_MAP &&
		policy.max_total_bindings > 0 && policy.max_total_bindings <= MAX_PROFILE_BINDINGS &&
		policy.max_sequence_strokes > 0 && policy.max_sequence_strokes <= MAX_SEQUENCE_STROKES &&
		policy.max_ordering_constraints <= MAX_ORDERING_CONSTRAINTS &&
		policy.max_definition_bytes > 0 && policy.max_definition_bytes <= MAX_DEFINITION_BYTES &&
		policy.max_snapshot_bytes > 0 && policy.max_snapshot_bytes <= MAX_KEYMAP_BYTES &&
		policy.max_inspection_alternatives > 0 &&
		policy.max_inspection_alternatives <= MAX_INSPECTION_ALTERNATIVES
}

@(private)
sequence_valid :: proc(sequence: Key_Sequence) -> bool {
	if sequence.stroke_count == 0 || sequence.stroke_count > MAX_SEQUENCE_STROKES {
		return false
	}
	for index in 0 ..< int(sequence.stroke_count) {
		if !key_stroke_is_valid(sequence.strokes[index]) {
			return false
		}
	}
	return true
}

@(private)
provenance_valid :: proc(provenance: Definition_Provenance) -> bool {
	return valid_bounded_text(provenance.provider, MAX_SOURCE_BYTES, false) &&
		valid_bounded_text(provenance.source, MAX_SOURCE_BYTES, false) &&
		valid_bounded_text(provenance.location, MAX_LOCATION_BYTES, true)
}

@(private)
provenance_bytes :: proc(provenance: Definition_Provenance) -> u64 {
	return u64(len(provenance.provider) + len(provenance.source) + len(provenance.location))
}

@(private)
copy_provenance :: proc(output: ^Compiled_Provenance, provenance: Definition_Provenance) {
	copy(output.provider[:len(provenance.provider)], transmute([]u8)provenance.provider)
	output.provider_count = u16(len(provenance.provider))
	copy(output.source[:len(provenance.source)], transmute([]u8)provenance.source)
	output.source_count = u16(len(provenance.source))
	copy(output.location[:len(provenance.location)], transmute([]u8)provenance.location)
	output.location_count = u16(len(provenance.location))
}

@(private)
map_index_by_id :: proc(maps: []Map_Definition, id: Map_ID) -> int {
	for map_definition, index in maps {
		if map_definition.identity.id == id {
			return index
		}
	}
	return -1
}

@(private)
release_unretained_layered_candidate :: proc(candidate: ^Snapshot_Data) {
	allocator := candidate.allocator
	if candidate.layered_bindings != nil {
		delete(candidate.layered_bindings, allocator)
	}
	if candidate.layered_remaps != nil {
		delete(candidate.layered_remaps, allocator)
	}
	if candidate.layered_trie_nodes != nil {
		delete(candidate.layered_trie_nodes, allocator)
	}
	if candidate.layered_maps != nil {
		delete(candidate.layered_maps, allocator)
	}
	free(candidate, allocator)
}
