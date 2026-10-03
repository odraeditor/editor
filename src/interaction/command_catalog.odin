// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package interaction

import "base:runtime"
import "core:slice"

@(private)
Command_Catalog_State :: struct {
	entries:   []Command_Catalog_Entry,
	sequences: []Key_Sequence,
	text:      []u8,
	allocator: runtime.Allocator,
}

@(private)
Catalog_Effective_Binding :: struct {
	sequence: Key_Sequence,
	command:  Command_Handle,
}

/* command_catalog_build copies one immutable interactive registry and binding projection. */
command_catalog_build :: proc(
	registry: ^Command_Registry,
	snapshot: ^Resolution_Snapshot,
	catalog_context: Command_Catalog_Context,
	allocator := context.allocator,
) -> (catalog: Command_Catalog, ok: bool, failure: Failure_Context) {
	registry_state := registry_data(registry)
	snapshot_state := snapshot_data(snapshot)
	if registry_state == nil || snapshot_state == nil || allocator.procedure == nil {
		return {}, false, Failure_Context{code = .Invalid_Registry}
	}
	if snapshot_state.registry != registry_state ||
	   snapshot_state.registry_generation != registry_state.generation {
		return {}, false, Failure_Context {
			code = .Stale_Registry,
			registry_generation = snapshot_state.registry_generation,
			snapshot_generation = snapshot_state.generation,
		}
	}
	interactive_count := 0
	text_bytes := 0
	for entry_index in 0 ..< int(registry_state.command_count) {
		entry := &registry_state.entries[entry_index]
		if !entry.interactive {
			continue
		}
		interactive_count += 1
		text_bytes += len(entry_name(entry)) + len(entry_description(entry))
		provenance := command_entry_provenance(entry)
		text_bytes += len(provenance.provider) + len(provenance.source) + len(provenance.location)
	}
	if interactive_count == 0 || interactive_count > MAX_COMMANDS {
		return {}, false, Failure_Context {
			code = .Inspection_Limit,
			limit = MAX_COMMANDS,
			actual = u64(interactive_count),
		}
	}
	owner, owner_error := new(Command_Catalog_State, allocator)
	if owner_error != nil {
		return {}, false, Failure_Context{code = .Persistent_Memory_Limit}
	}
	owner.allocator = allocator
	owner.entries, owner_error = make([]Command_Catalog_Entry, interactive_count, allocator)
	if owner_error != nil {
		command_catalog_state_destroy(owner)
		return {}, false, Failure_Context{code = .Persistent_Memory_Limit}
	}
	owner.text, owner_error = make([]u8, text_bytes, allocator)
	if owner_error != nil {
		command_catalog_state_destroy(owner)
		return {}, false, Failure_Context{code = .Persistent_Memory_Limit}
	}
	text_offset := 0
	catalog_index := 0
	for entry_index in 0 ..< int(registry_state.command_count) {
		entry := &registry_state.entries[entry_index]
		if !entry.interactive {
			continue
		}
		metadata := Command_Metadata {
			handle = entry.handle,
			implementation = entry.implementation,
			invocation = entry.invocation,
			text_requirement = entry.text_requirement,
			effects = entry.effects,
			interactive = true,
			requirements = entry.requirements,
		}
		metadata.name, text_offset = command_catalog_copy_text(owner.text, text_offset, entry_name(entry))
		metadata.description, text_offset = command_catalog_copy_text(owner.text, text_offset, entry_description(entry))
		provenance := command_entry_provenance(entry)
		metadata.provenance.provider, text_offset = command_catalog_copy_text(owner.text, text_offset, provenance.provider)
		metadata.provenance.source, text_offset = command_catalog_copy_text(owner.text, text_offset, provenance.source)
		metadata.provenance.location, text_offset = command_catalog_copy_text(owner.text, text_offset, provenance.location)
		availability, reason := command_catalog_availability(metadata, catalog_context)
		owner.entries[catalog_index] = Command_Catalog_Entry {
			metadata = metadata,
			availability = availability,
			unavailable_reason = reason,
		}
		catalog_index += 1
	}
	assert(text_offset == text_bytes)
	slice.sort_by(owner.entries, command_catalog_entry_less)

	binding_capacity := int(snapshot_state.binding_count)
	if snapshot_state.layered {
		binding_capacity = len(snapshot_state.layered_bindings)
	}
	candidates, candidate_error := make([]Catalog_Effective_Binding, binding_capacity, allocator)
	if candidate_error != nil {
		command_catalog_state_destroy(owner)
		return {}, false, Failure_Context{code = .Persistent_Memory_Limit}
	}
	defer delete(candidates, allocator)
	candidate_count := command_catalog_collect_bindings(snapshot_state, candidates)
	slice.sort_by(candidates[:candidate_count], command_catalog_binding_less)
	unique_count := 0
	for index in 0 ..< candidate_count {
		candidate := candidates[index]
		if unique_count > 0 && command_catalog_sequence_equal(
			candidates[unique_count - 1].sequence,
			candidate.sequence,
		) {
			continue
		}
		candidates[unique_count] = candidate
		unique_count += 1
	}

	counts: [MAX_COMMANDS]u16
	entry_slots: [MAX_COMMANDS]u16
	for entry, index in owner.entries {
		entry_slots[entry.metadata.handle.slot] = u16(index + 1)
	}
	sequence_count := 0
	for candidate in candidates[:unique_count] {
		mapped := entry_slots[candidate.command.slot]
		if mapped == 0 {
			continue
		}
		counts[mapped - 1] += 1
		sequence_count += 1
	}
	owner.sequences, owner_error = make([]Key_Sequence, sequence_count, allocator)
	if owner_error != nil {
		command_catalog_state_destroy(owner)
		return {}, false, Failure_Context{code = .Persistent_Memory_Limit}
	}
	offset := 0
	for index in 0 ..< len(owner.entries) {
		count := int(counts[index])
		owner.entries[index].bindings = owner.sequences[offset:offset + count]
		offset += count
	}
	cursors: [MAX_COMMANDS]u16
	for candidate in candidates[:unique_count] {
		mapped := entry_slots[candidate.command.slot]
		if mapped == 0 {
			continue
		}
		entry_index := int(mapped - 1)
		binding_index := int(cursors[entry_index])
		owner.entries[entry_index].bindings[binding_index] = candidate.sequence
		cursors[entry_index] += 1
	}
	catalog = Command_Catalog {
		registry_generation = registry_state.generation,
		snapshot_generation = snapshot_state.generation,
		command_entry_surface = catalog_context.command_entry_surface,
		entries = owner.entries,
		state = owner,
	}
	return catalog, true, {}
}

/* command_catalog_close releases one immutable catalog projection. */
command_catalog_close :: proc(catalog: ^Command_Catalog) -> bool {
	if catalog == nil || catalog.state == nil {
		return false
	}
	owner := cast(^Command_Catalog_State)catalog.state
	command_catalog_state_destroy(owner)
	catalog^ = {}
	return true
}

/* command_catalog_entry returns one borrowed entry from the exact catalog generation. */
command_catalog_entry :: proc(
	catalog: ^Command_Catalog,
	command: Command_Handle,
) -> (entry: Command_Catalog_Entry, ok: bool) {
	if catalog == nil || catalog.state == nil ||
	   command.registry_generation != catalog.registry_generation {
		return {}, false
	}
	for candidate in catalog.entries {
		if candidate.metadata.handle == command {
			return candidate, true
		}
	}
	return {}, false
}

@(private)
command_catalog_collect_bindings :: proc(
	snapshot: ^Snapshot_Data,
	output: []Catalog_Effective_Binding,
) -> int {
	count := 0
	if snapshot.layered {
		for binding in snapshot.layered_bindings {
			if !snapshot.layered_maps[binding.map_slot].active {
				continue
			}
			query := binding.compiled
			exact, _, masked := find_active_sequence(snapshot, query)
			if exact == nil || masked {
				continue
			}
			output[count] = Catalog_Effective_Binding {
				sequence = command_catalog_sequence(exact^),
				command = resolved_command(snapshot, exact.command),
			}
			count += 1
		}
		return count
	}
	for binding in snapshot.bindings[:snapshot.binding_count] {
		output[count] = Catalog_Effective_Binding {
			sequence = command_catalog_sequence(binding),
			command = binding.command,
		}
		count += 1
	}
	return count
}

@(private)
command_catalog_availability :: proc(
	metadata: Command_Metadata,
	catalog_context: Command_Catalog_Context,
) -> (Command_Availability, string) {
	requirements := metadata.requirements
	if .Active_Buffer in requirements && !catalog_context.active_buffer {
		return .Unavailable, "Requires an active buffer."
	}
	if .Active_Document in requirements && !catalog_context.active_document {
		return .Unavailable, "Requires an associated document."
	}
	if .Active_Region in requirements && !catalog_context.active_region {
		return .Unavailable, "Requires an active region."
	}
	if .Active_Terminal in requirements && !catalog_context.active_terminal {
		return .Unavailable, "Requires an active terminal."
	}
	if catalog_context.state.id != Interaction_State_ID(0) {
		if metadata.invocation == .Text_Input && !catalog_context.admits_text_input {
			return .Unavailable, "Unavailable in the active interaction state."
		}
		for effect in Command_Effect {
			if effect in metadata.effects && effect not_in catalog_context.admitted_effects {
				return .Unavailable, "Unavailable in the active interaction state."
			}
		}
	}
	return .Available, ""
}

@(private)
command_catalog_sequence :: proc(binding: Compiled_Binding) -> Key_Sequence {
	return Key_Sequence{strokes = binding.strokes, stroke_count = binding.stroke_count}
}

@(private)
command_catalog_entry_less :: proc(left, right: Command_Catalog_Entry) -> bool {
	return left.metadata.name < right.metadata.name
}

@(private)
command_catalog_binding_less :: proc(left, right: Catalog_Effective_Binding) -> bool {
	left_binding := Compiled_Binding{strokes = left.sequence.strokes, stroke_count = left.sequence.stroke_count}
	right_binding := Compiled_Binding{strokes = right.sequence.strokes, stroke_count = right.sequence.stroke_count}
	return sequence_compare(left_binding, right_binding) < 0
}

@(private)
command_catalog_sequence_equal :: proc(left, right: Key_Sequence) -> bool {
	if left.stroke_count != right.stroke_count {
		return false
	}
	for index in 0 ..< int(left.stroke_count) {
		if left.strokes[index] != right.strokes[index] {
			return false
		}
	}
	return true
}

@(private)
command_catalog_copy_text :: proc(storage: []u8, offset: int, value: string) -> (string, int) {
	copy(storage[offset:], transmute([]u8)value)
	return string(storage[offset:offset + len(value)]), offset + len(value)
}

@(private)
command_catalog_state_destroy :: proc(state: ^Command_Catalog_State) {
	allocator := state.allocator
	if state.sequences != nil {
		delete(state.sequences, allocator)
	}
	if state.text != nil {
		delete(state.text, allocator)
	}
	if state.entries != nil {
		delete(state.entries, allocator)
	}
	free(state, allocator)
}
