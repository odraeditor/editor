// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package result_set

import "base:runtime"
import "core:unicode/utf8"

@(private)
Set_Owner :: struct {
	set_id:          Result_Set_ID,
	generation:      Result_Set_Generation,
	source:          Source_Descriptor,
	metadata:        Source_Metadata,
	completeness:    Completeness,
	continuation:    Continuation,
	refresh:         Refresh_Descriptor,
	edit_capability: Edit_Capability,
	locations:       []Location,
	groups:          []Group,
	storage:         []u8,
	selected_index:  u32,
	has_selection:   bool,
	accounting:      Accounting,
}

@(private)
Registry_State :: struct {
	sets:      [dynamic]Set_Owner,
	limits:    Limits,
	allocator: runtime.Allocator,
}

limits_valid :: proc(limits: Limits) -> bool {
	return limits.sets > 0 && limits.sets <= MAX_RESULT_SETS &&
		limits.locations > 0 && limits.locations <= MAX_RESULT_LOCATIONS &&
		limits.groups > 0 && limits.groups <= MAX_RESULT_GROUPS &&
		limits.text_bytes > 0 && limits.text_bytes <= MAX_RESULT_TEXT_BYTES &&
		limits.preview_bytes > 0 && limits.preview_bytes <= MAX_RESULT_PREVIEW_BYTES &&
		limits.annotation_bytes > 0 && limits.annotation_bytes <= MAX_RESULT_ANNOTATION_BYTES &&
		limits.temporary_bytes > 0 && limits.temporary_bytes <= MAX_RESULT_TEMPORARY_BYTES
}

registry_init :: proc(registry: ^Registry, config: Config) -> (bool, Failure) {
	if registry == nil || registry.state != nil || !limits_valid(config.limits) ||
	   config.allocator.procedure == nil {
		return false, Failure{code = .Invalid_Registry}
	}
	state, allocation_error := new(Registry_State, config.allocator)
	if allocation_error != nil do return false, Failure{code = .Persistent_Memory_Limit}
	state^ = Registry_State{limits = config.limits, allocator = config.allocator}
	state.sets, allocation_error = make([dynamic]Set_Owner, 0, int(config.limits.sets), config.allocator)
	if allocation_error != nil {
		free(state, config.allocator)
		return false, Failure{code = .Persistent_Memory_Limit}
	}
	registry.state = state
	return true, {}
}

registry_publish :: proc(registry: ^Registry, proposal: Publication) -> (Result, bool, Failure) {
	state := registry_state(registry)
	if state == nil do return {}, false, Failure{code = .Closed_Registry}
	index, found := set_find(state, proposal.set_id)
	if proposal.set_id == Result_Set_ID(0) || proposal.source.id == Source_ID(0) ||
	   proposal.source.generation == Source_Generation(0) || proposal.source.kind == .Invalid ||
	   proposal.completeness == .Invalid || proposal.edit_capability == .Invalid ||
	   proposal.completeness == .Complete && proposal.continuation.present ||
	   proposal.completeness == .Incomplete && !proposal.continuation.present {
		return {}, false, Failure{code = .Invalid_Publication, set_id = proposal.set_id}
	}
	if found {
		if proposal.expected_generation != state.sets[index].generation {
			return {}, false, Failure{code = .Stale_Generation, set_id = proposal.set_id,
				generation = proposal.expected_generation}
		}
	} else {
		if proposal.expected_generation != Result_Set_Generation(0) {
			return {}, false, Failure{code = .Stale_Generation, set_id = proposal.set_id,
				generation = proposal.expected_generation}
		}
		if len(state.sets) >= int(state.limits.sets) {
			return {}, false, Failure{code = .Set_Limit, set_id = proposal.set_id,
				limit = u64(state.limits.sets), actual = u64(len(state.sets) + 1)}
		}
	}
	candidate, built, failure := set_build(state, proposal, found, index)
	if !built do return {}, false, failure
	transition := Transition.Published
	if found {
		transition = .Replaced
		set_close(&state.sets[index], state.allocator)
		state.sets[index] = candidate
	} else {
		if _, append_error := append(&state.sets, candidate); append_error != nil {
			set_close(&candidate, state.allocator)
			return {}, false, Failure{code = .Persistent_Memory_Limit, set_id = proposal.set_id}
		}
	}
	return set_result(&candidate, transition), true, {}
}

registry_view :: proc(registry: ^Registry, set_id: Result_Set_ID) -> (View, bool, Failure) {
	state := registry_state(registry)
	if state == nil do return {}, false, Failure{code = .Closed_Registry, set_id = set_id}
	index, found := set_find(state, set_id)
	if !found do return {}, false, Failure{code = .Set_Not_Found, set_id = set_id}
	set := &state.sets[index]
	return View{set_id = set.set_id, generation = set.generation, source = set.source, metadata = set.metadata,
		completeness = set.completeness, continuation = set.continuation, refresh = set.refresh,
		edit_capability = set.edit_capability, locations = set.locations, groups = set.groups,
		selected_index = set.selected_index, has_selection = set.has_selection,
		accounting = set.accounting}, true, {}
}

registry_move :: proc(registry: ^Registry, set_id: Result_Set_ID,
	expected: Result_Set_Generation, movement: Movement) -> (Result, bool, Failure) {
	state := registry_state(registry)
	if state == nil do return {}, false, Failure{code = .Closed_Registry, set_id = set_id}
	index, found := set_find(state, set_id)
	if !found do return {}, false, Failure{code = .Set_Not_Found, set_id = set_id}
	set := &state.sets[index]
	if set.generation != expected do return {}, false, Failure{code = .Stale_Generation,
		set_id = set_id, generation = expected}
	if movement == .Invalid do return {}, false, Failure{code = .Invalid_Movement, set_id = set_id}
	if len(set.locations) == 0 do return {}, false, Failure{code = .No_Selection, set_id = set_id}
	previous := set.selected_index
	#partial switch movement {
	case .First: set.selected_index = 0
	case .Last: set.selected_index = u32(len(set.locations) - 1)
	case .Previous:
		if !set.has_selection || set.selected_index == 0 do set.selected_index = 0
		else do set.selected_index -= 1
	case .Next:
		if !set.has_selection do set.selected_index = 0
		else if int(set.selected_index) + 1 < len(set.locations) do set.selected_index += 1
	}
	transition := Transition.Selected
	if set.has_selection && previous == set.selected_index do transition = .No_Change
	set.has_selection = true
	return set_result(set, transition), true, {}
}

/* registry_select makes one exact generation-local location the canonical selection. */
registry_select :: proc(registry: ^Registry, set_id: Result_Set_ID,
	expected: Result_Set_Generation, location_id: Location_ID) -> (Result, bool, Failure) {
	state := registry_state(registry)
	if state == nil do return {}, false, Failure{code = .Closed_Registry, set_id = set_id}
	index, found := set_find(state, set_id)
	if !found do return {}, false, Failure{code = .Set_Not_Found, set_id = set_id}
	set := &state.sets[index]
	if set.generation != expected do return {}, false, Failure{code = .Stale_Generation,
		set_id = set_id, generation = expected}
	for location, location_index in set.locations {
		if location.id != location_id do continue
		transition := Transition.Selected
		if set.has_selection && set.selected_index == u32(location_index) do transition = .No_Change
		set.selected_index = u32(location_index)
		set.has_selection = true
		return set_result(set, transition), true, {}
	}
	return {}, false, Failure{code = .Invalid_Location, set_id = set_id,
		generation = expected, location_id = location_id}
}

registry_close_set :: proc(registry: ^Registry, set_id: Result_Set_ID,
	expected: Result_Set_Generation) -> (Result, bool, Failure) {
	state := registry_state(registry)
	if state == nil do return {}, false, Failure{code = .Closed_Registry, set_id = set_id}
	index, found := set_find(state, set_id)
	if !found do return {}, false, Failure{code = .Set_Not_Found, set_id = set_id}
	if state.sets[index].generation != expected do return {}, false, Failure{code = .Stale_Generation,
		set_id = set_id, generation = expected}
	result := set_result(&state.sets[index], .Closed)
	set_close(&state.sets[index], state.allocator)
	ordered_remove(&state.sets, index)
	return result, true, {}
}

registry_inspect :: proc(registry: ^Registry) -> (Accounting, bool, Failure) {
	state := registry_state(registry)
	if state == nil do return {}, false, Failure{code = .Closed_Registry}
	result := Accounting{sets = u32(len(state.sets)), retained_bytes = u64(cap(state.sets)) * u64(size_of(Set_Owner))}
	for set in state.sets {
		result.locations += set.accounting.locations
		result.groups += set.accounting.groups
		result.preview_bytes += set.accounting.preview_bytes
		result.annotation_bytes += set.accounting.annotation_bytes
		result.group_label_bytes += set.accounting.group_label_bytes
		result.metadata_bytes += set.accounting.metadata_bytes
		result.retained_bytes += set.accounting.retained_bytes
	}
	return result, true, {}
}

registry_close :: proc(registry: ^Registry) -> (bool, Failure) {
	state := registry_state(registry)
	if state == nil do return false, Failure{code = .Closed_Registry}
	for index in 0 ..< len(state.sets) do set_close(&state.sets[index], state.allocator)
	delete(state.sets)
	allocator := state.allocator
	registry.state = nil
	free(state, allocator)
	return true, {}
}

@(private)
set_build :: proc(state: ^Registry_State, proposal: Publication, replacing: bool,
	index: int) -> (Set_Owner, bool, Failure) {
	if len(proposal.locations) > int(state.limits.locations) do return {}, false,
		Failure{code = .Location_Limit, set_id = proposal.set_id,
			limit = u64(state.limits.locations), actual = u64(len(proposal.locations))}
	if len(proposal.groups) > int(state.limits.groups) do return {}, false,
		Failure{code = .Group_Limit, set_id = proposal.set_id,
			limit = u64(state.limits.groups), actual = u64(len(proposal.groups))}
	if !utf8.valid_string(proposal.metadata.descriptor) do return {}, false,
		Failure{code = .Invalid_Publication, set_id = proposal.set_id}
	group_ids, group_index_error := make(map[Group_ID]bool, len(proposal.groups), state.allocator)
	if group_index_error != nil do return {}, false,
		Failure{code = .Persistent_Memory_Limit, set_id = proposal.set_id}
	defer delete(group_ids)
	location_ids, location_index_error := make(map[Location_ID]bool, len(proposal.locations), state.allocator)
	if location_index_error != nil do return {}, false,
		Failure{code = .Persistent_Memory_Limit, set_id = proposal.set_id}
	defer delete(location_ids)
	text_bytes := u64(len(proposal.metadata.descriptor))
	for group in proposal.groups {
		if group.id == Group_ID(0) || !utf8.valid_string(group.label) do return {}, false,
			Failure{code = .Invalid_Group, set_id = proposal.set_id, group_id = group.id}
		if group_ids[group.id] do return {}, false, Failure{code = .Duplicate_Identity,
			set_id = proposal.set_id, group_id = group.id}
		group_ids[group.id] = true
		text_bytes += u64(len(group.label))
	}
	for location in proposal.locations {
		if location.id == Location_ID(0) || location.buffer_id == 0 || location.start > location.end ||
		   !utf8.valid_string(location.preview) || !utf8.valid_string(location.annotation) {
			return {}, false, Failure{code = .Invalid_Location, set_id = proposal.set_id,
				location_id = location.id}
		}
		if location.preview_match_present &&
		   (location.preview_match_start >= location.preview_match_end ||
		    location.preview_match_end > u32(len(location.preview)) ||
		    !utf8.valid_string(location.preview[:location.preview_match_start]) ||
		    !utf8.valid_string(location.preview[:location.preview_match_end])) {
			return {}, false, Failure{code = .Invalid_Location, set_id = proposal.set_id,
				location_id = location.id}
		}
		if len(location.preview) > int(state.limits.preview_bytes) do return {}, false,
			Failure{code = .Preview_Limit, set_id = proposal.set_id, location_id = location.id,
				limit = u64(state.limits.preview_bytes), actual = u64(len(location.preview))}
		if len(location.annotation) > int(state.limits.annotation_bytes) do return {}, false,
			Failure{code = .Annotation_Limit, set_id = proposal.set_id, location_id = location.id,
				limit = u64(state.limits.annotation_bytes), actual = u64(len(location.annotation))}
		if location_ids[location.id] do return {}, false, Failure{code = .Duplicate_Identity,
			set_id = proposal.set_id, location_id = location.id}
		location_ids[location.id] = true
		if location.group_id != Group_ID(0) && !group_ids[location.group_id] {
			return {}, false, Failure{code = .Invalid_Group, set_id = proposal.set_id,
				location_id = location.id, group_id = location.group_id}
		}
		text_bytes += u64(len(location.preview) + len(location.annotation))
	}
	if text_bytes > state.limits.text_bytes do return {}, false, Failure{code = .Text_Limit,
		set_id = proposal.set_id, limit = state.limits.text_bytes, actual = text_bytes}
	generation := Result_Set_Generation(1)
	if replacing {
		if state.sets[index].generation == Result_Set_Generation(max(u64)) do return {}, false,
			Failure{code = .Arithmetic_Overflow, set_id = proposal.set_id}
		generation = state.sets[index].generation + 1
	}
	owner := Set_Owner{set_id = proposal.set_id, generation = generation, source = proposal.source,
		completeness = proposal.completeness, continuation = proposal.continuation,
		refresh = proposal.refresh, edit_capability = proposal.edit_capability}
	owner.locations, _ = make([]Location, len(proposal.locations), state.allocator)
	owner.groups, _ = make([]Group, len(proposal.groups), state.allocator)
	owner.storage, _ = make([]u8, int(text_bytes), state.allocator)
	if len(owner.locations) != len(proposal.locations) || len(owner.groups) != len(proposal.groups) ||
	   len(owner.storage) != int(text_bytes) {
		set_close(&owner, state.allocator)
		return {}, false, Failure{code = .Persistent_Memory_Limit, set_id = proposal.set_id}
	}
	cursor := 0
	copy(owner.storage[cursor:], proposal.metadata.descriptor)
	owner.metadata = Source_Metadata {
		descriptor = string(owner.storage[:len(proposal.metadata.descriptor)]),
		values = proposal.metadata.values,
	}
	cursor += len(proposal.metadata.descriptor)
	owner.accounting.metadata_bytes = u64(len(proposal.metadata.descriptor))
	for group, group_index in proposal.groups {
		copy(owner.storage[cursor:], group.label)
		owner.groups[group_index] = Group{id = group.id, label = string(owner.storage[cursor:cursor + len(group.label)])}
		cursor += len(group.label)
		owner.accounting.group_label_bytes += u64(len(group.label))
	}
	for location, location_index in proposal.locations {
		preview_start := cursor
		copy(owner.storage[cursor:], location.preview)
		cursor += len(location.preview)
		annotation_start := cursor
		copy(owner.storage[cursor:], location.annotation)
		cursor += len(location.annotation)
		owner.locations[location_index] = Location{id = location.id, group_id = location.group_id,
			buffer_id = location.buffer_id, revision = location.revision, start = location.start,
			end = location.end, source_identity = location.source_identity,
			preview = string(owner.storage[preview_start:annotation_start]),
			annotation = string(owner.storage[annotation_start:cursor]),
			preview_match_start = location.preview_match_start,
			preview_match_end = location.preview_match_end,
			preview_match_present = location.preview_match_present}
		owner.accounting.preview_bytes += u64(len(location.preview))
		owner.accounting.annotation_bytes += u64(len(location.annotation))
	}
	owner.accounting.locations = u32(len(owner.locations))
	owner.accounting.groups = u32(len(owner.groups))
	owner.accounting.retained_bytes = u64(len(owner.storage)) +
		u64(len(owner.locations)) * u64(size_of(Location)) + u64(len(owner.groups)) * u64(size_of(Group))
	selection := proposal.selected
	has_selection := proposal.has_selection
	if !has_selection && replacing && state.sets[index].has_selection {
		selection = state.sets[index].locations[state.sets[index].selected_index].id
		has_selection = true
	}
	if has_selection {
		for location, selected_index in owner.locations {
			if location.id == selection {
				owner.selected_index = u32(selected_index)
				owner.has_selection = true
				break
			}
		}
		if !owner.has_selection {
			set_close(&owner, state.allocator)
			return {}, false, Failure{code = .Invalid_Location, set_id = proposal.set_id,
				location_id = selection}
		}
	}
	return owner, true, {}
}

@(private)
registry_state :: proc(registry: ^Registry) -> ^Registry_State {
	if registry == nil || registry.state == nil do return nil
	return (^Registry_State)(registry.state)
}

@(private)
set_find :: proc(state: ^Registry_State, set_id: Result_Set_ID) -> (int, bool) {
	for set, index in state.sets do if set.set_id == set_id do return index, true
	return 0, false
}

@(private)
set_result :: proc(set: ^Set_Owner, transition: Transition) -> Result {
	result := Result{transition = transition, set_id = set.set_id, generation = set.generation,
		selected_index = set.selected_index, has_selection = set.has_selection}
	if set.has_selection do result.location_id = set.locations[set.selected_index].id
	return result
}

@(private)
set_close :: proc(set: ^Set_Owner, allocator: runtime.Allocator) {
	if set == nil do return
	delete(set.storage, allocator)
	delete(set.groups, allocator)
	delete(set.locations, allocator)
	set^ = {}
}
