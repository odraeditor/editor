// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery

/* Ref_Navigation selects one ordered semantic Ref movement. */
Ref_Navigation :: enum u8 {
	Previous,
	Next,
}

/* ref_hierarchy_item_count returns every exact Ref and configured Remote in display order. */
ref_hierarchy_item_count :: proc(observation: ^Ref_Observation) -> (u32, bool) {
	state := ref_observation_data(observation)
	if state == nil do return 0, false
	return u32(len(state.references) + len(state.remotes)), true
}

/* ref_hierarchy_item returns one semantic Ref or Remote item without positional authority. */
ref_hierarchy_item :: proc(observation: ^Ref_Observation, ordinal: u32) -> (Ref_Item_ID, bool) {
	state := ref_observation_data(observation)
	if state == nil do return {}, false
	if ordinal < u32(len(state.references)) {
		return {kind = .Ref, reference = state.references[int(ordinal)]}, true
	}
	remote_ordinal := ordinal - u32(len(state.references))
	if remote_ordinal < u32(len(state.remotes)) {
		return {kind = .Remote, remote = state.remotes[int(remote_ordinal)]}, true
	}
	return {}, false
}

/* ref_selection_begin selects the first available semantic Ref item. */
ref_selection_begin :: proc(observation: ^Ref_Observation) -> (Ref_Selection, bool) {
	descriptor, described := ref_observation_descriptor(observation)
	if !described do return {}, false
	selection := Ref_Selection{generation = descriptor.generation}
	first, found := ref_hierarchy_item(observation, 0)
	if found do selection.current = first
	return selection, true
}

/* ref_selection_is_current checks that a Ref selection belongs to this immutable observation. */
ref_selection_is_current :: proc(observation: ^Ref_Observation, selection: Ref_Selection) -> bool {
	descriptor, described := ref_observation_descriptor(observation)
	if !described || descriptor.generation != selection.generation || !ref_selection_is_valid(selection) do return false
	if selection.current == {} do return true
	_, found := ref_hierarchy_find(observation, selection.current)
	return found
}

/* ref_selection_move moves once through visible exact Ref and Remote identities. */
ref_selection_move :: proc(
	observation: ^Ref_Observation,
	selection: Ref_Selection,
	direction: Ref_Navigation,
) -> (Ref_Selection, bool, Failure_Code) {
	if !ref_selection_is_current(observation, selection) do return {}, false, .Stale_Observation
	count, available := ref_hierarchy_item_count(observation)
	if !available || count == 0 do return selection, true, .None
	ordinal, found := ref_hierarchy_find(observation, selection.current)
	if !found do return {}, false, .Stale_Observation
	next := ordinal
	switch direction {
	case .Previous:
		if next > 0 do next -= 1
	case .Next:
		if next + 1 < count do next += 1
	}
	item, item_found := ref_hierarchy_item(observation, next)
	if !item_found do return {}, false, .Stale_Observation
	next_selection := selection
	next_selection.current = item
	return next_selection, true, .None
}

/* ref_selection_reconcile preserves only an exactly unchanged Ref selection after refresh. */
ref_selection_reconcile :: proc(
	previous, next: ^Ref_Observation,
	selection: Ref_Selection,
) -> (Ref_Selection, bool, Failure_Code) {
	if !ref_selection_is_current(previous, selection) do return {}, false, .Stale_Observation
	next_descriptor, described := ref_observation_descriptor(next)
	if !described || next_descriptor.generation == selection.generation do return {}, false, .Invalid_Request
	next_selection := Ref_Selection{generation = next_descriptor.generation}
	if selection.marked != {} {
		count, available := ref_observation_ref_count(next)
		if available {
			for ordinal in 0 ..< count {
				candidate, found := ref_observation_ref(next, ordinal)
				if found && ref_identity_same_object(candidate, selection.marked) {
					next_selection.marked = candidate
					break
				}
			}
		}
	}
	if selection.current.kind == .Ref {
		count, available := ref_observation_ref_count(next)
		if available {
			for ordinal in 0 ..< count {
				candidate, found := ref_observation_ref(next, ordinal)
				if found && ref_identity_same_object(candidate, selection.current.reference) {
					next_selection.current = {kind = .Ref, reference = candidate}
					return next_selection, true, .None
				}
			}
		}
	}
	first, found := ref_hierarchy_item(next, 0)
	if found do next_selection.current = first
	return next_selection, true, .None
}

@(private)
ref_hierarchy_find :: proc(observation: ^Ref_Observation, wanted: Ref_Item_ID) -> (u32, bool) {
	count, available := ref_hierarchy_item_count(observation)
	if !available do return 0, false
	for ordinal in 0 ..< count {
		item, found := ref_hierarchy_item(observation, ordinal)
		if found && item == wanted do return ordinal, true
	}
	return 0, false
}

@(private)
ref_identity_same_object :: proc(next, previous: Ref_Identity) -> bool {
	return next.repository == previous.repository && next.kind == previous.kind && next.name == previous.name &&
	       next.object == previous.object && next.object_type == previous.object_type
}
