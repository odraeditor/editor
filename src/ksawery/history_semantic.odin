// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery

/* History_Navigation selects one ordered semantic History movement. */
History_Navigation :: enum u8 {
	Previous,
	Next,
}

/* history_hierarchy_item_count returns revisions and their exact parent relationships in display order. */
history_hierarchy_item_count :: proc(observation: ^History_Observation) -> (u32, bool) {
	descriptor, available := history_observation_descriptor(observation)
	if !available || descriptor.state != .Available do return 0, available
	return descriptor.revision_count + descriptor.parent_links, true
}

/* history_hierarchy_item returns one semantic revision or parent relationship without positional identity. */
history_hierarchy_item :: proc(observation: ^History_Observation, ordinal: u32) -> (History_Item_ID, bool) {
	descriptor, available := history_observation_descriptor(observation)
	if !available || descriptor.state != .Available do return {}, false
	current: u32
	for revision_ordinal in 0 ..< descriptor.revision_count {
		revision, found := history_observation_revision(observation, revision_ordinal)
		if !found do return {}, false
		target := History_Target{generation = descriptor.generation, revision = revision.identity}
		if current == ordinal do return {kind = .Revision, revision = target}, true
		current += 1
		for parent_ordinal in 0 ..< u32(revision.parent_count) {
			if current == ordinal {
				return {kind = .Parent, revision = target, parent = revision.parents[parent_ordinal]}, true
			}
			current += 1
		}
	}
	return {}, false
}

/* history_selection_begin selects the first available History revision. */
history_selection_begin :: proc(observation: ^History_Observation) -> (History_Selection, bool) {
	descriptor, available := history_observation_descriptor(observation)
	if !available do return {}, false
	selection := History_Selection{generation = descriptor.generation}
	first, found := history_hierarchy_item(observation, 0)
	if found do selection.current = first
	return selection, true
}

/* history_selection_is_current checks that local selection belongs to this immutable observation. */
history_selection_is_current :: proc(
	observation: ^History_Observation,
	selection: History_Selection,
) -> bool {
	descriptor, available := history_observation_descriptor(observation)
	if !available || selection.generation != descriptor.generation || !history_selection_is_valid(selection) do return false
	if selection.current == {} do return descriptor.state != .Available
	_, found := history_hierarchy_find(observation, selection.current)
	return found
}

/* history_selection_move moves once through visible exact revision and parent objects. */
history_selection_move :: proc(
	observation: ^History_Observation,
	selection: History_Selection,
	direction: History_Navigation,
) -> (History_Selection, bool, Failure_Code) {
	if !history_selection_is_current(observation, selection) do return {}, false, .Stale_Observation
	count, available := history_hierarchy_item_count(observation)
	if !available || count == 0 do return selection, true, .None
	ordinal, found := history_hierarchy_find(observation, selection.current)
	if !found do return {}, false, .Stale_Observation
	next := ordinal
	switch direction {
	case .Previous:
		if next > 0 do next -= 1
	case .Next:
		if next + 1 < count do next += 1
	}
	item, item_found := history_hierarchy_item(observation, next)
	if !item_found do return {}, false, .Stale_Observation
	next_selection := selection
	next_selection.current = item
	return next_selection, true, .None
}

/* history_selection_reconcile preserves exact revision and parent identities across a fresh History observation. */
history_selection_reconcile :: proc(
	previous, next: ^History_Observation,
	selection: History_Selection,
) -> (History_Selection, bool, Failure_Code) {
	if !history_selection_is_current(previous, selection) do return {}, false, .Stale_Observation
	next_descriptor, described := history_observation_descriptor(next)
	if !described || next_descriptor.generation == selection.generation do return {}, false, .Invalid_Request
	next_selection := History_Selection{generation = next_descriptor.generation}
	if selection.marked != {} {
		count, available := history_observation_revision_count(next)
		if available {
			for ordinal in 0 ..< count {
				revision, found := history_observation_revision(next, ordinal)
				if found && revision.identity == selection.marked.revision {
					next_selection.marked = {
						generation = next_descriptor.generation,
						revision = revision.identity,
					}
					break
				}
			}
		}
	}
	count, available := history_hierarchy_item_count(next)
	if available {
		for ordinal in 0 ..< count {
			candidate, found := history_hierarchy_item(next, ordinal)
			if !found || candidate.kind != selection.current.kind ||
			   candidate.revision.revision != selection.current.revision.revision {
				continue
			}
			if candidate.kind == .Parent && candidate.parent != selection.current.parent do continue
			next_selection.current = candidate
			return next_selection, true, .None
		}
	}
	first, found := history_hierarchy_item(next, 0)
	if found do next_selection.current = first
	return next_selection, true, .None
}

@(private)
history_hierarchy_find :: proc(observation: ^History_Observation, wanted: History_Item_ID) -> (u32, bool) {
	count, available := history_hierarchy_item_count(observation)
	if !available do return 0, false
	for ordinal in 0 ..< count {
		item, found := history_hierarchy_item(observation, ordinal)
		if found && item == wanted do return ordinal, true
	}
	return 0, false
}
