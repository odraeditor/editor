// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery

/* Status_Item_Kind distinguishes sections, paths, and semantic diff units. */
Status_Item_Kind :: enum u8 {
	Invalid,
	Group,
	Path,
	Diff_Unit,
}

/* Status_Navigation selects one ordered semantic Status movement. */
Status_Navigation :: enum u8 {
	Previous,
	Next,
}

/* Status_Item_ID identifies one Status hierarchy object in one observation. */
Status_Item_ID :: struct {
	kind:   Status_Item_Kind,
	group:  Change_Group,
	path:   Path_ID,
	source: Diff_Source_ID,
	unit:   Diff_Unit_ID,
}

/* Status_Item describes one visible semantic object and its hierarchy parent. */
Status_Item :: struct {
	id:     Status_Item_ID,
	parent: Status_Item_ID,
}

/* Status_Selection owns local navigation and expanded-detail identity. */
Status_Selection :: struct {
	generation: Observation_Generation,
	current:    Status_Item_ID,
	expanded:   Path_Target,
}

/* status_hierarchy_item_count returns the exact visible semantic-item count. */
status_hierarchy_item_count :: proc(
	observation: ^Status_Observation,
	document: ^Diff_Document = nil,
) -> (u32, bool) {
	descriptor, available := status_observation_descriptor(observation)
	if !available do return 0, false
	count: u32
	for group in STATUS_GROUP_ORDER {
		group_count := status_hierarchy_group_path_count(observation, group)
		if group_count == 0 do continue
		count += 1 + group_count
		path_count, _ := status_observation_path_count(observation)
		for path_index in 0 ..< path_count {
			path, found := status_observation_path(observation, path_index)
			if !found || path.group != group do continue
			unit_count, matches := status_hierarchy_diff_unit_count(observation, document, path)
			if matches do count += unit_count
		}
	}
	return count, descriptor.generation != Observation_Generation(0)
}

/* status_hierarchy_item returns one section-or-path object in display order. */
status_hierarchy_item :: proc(
	observation: ^Status_Observation,
	ordinal: u32,
	document: ^Diff_Document = nil,
) -> (Status_Item, bool) {
	descriptor, available := status_observation_descriptor(observation)
	if !available || descriptor.generation == Observation_Generation(0) do return {}, false
	current: u32
	for group in STATUS_GROUP_ORDER {
		group_count := status_hierarchy_group_path_count(observation, group)
		if group_count == 0 do continue
		group_id := Status_Item_ID{kind = .Group, group = group}
		if current == ordinal do return Status_Item{id = group_id}, true
		current += 1
		path_count, _ := status_observation_path_count(observation)
		for path_index in 0 ..< path_count {
			path, found := status_observation_path(observation, path_index)
			if !found || path.group != group do continue
			if current == ordinal {
				return Status_Item{
					id = {kind = .Path, group = group, path = path.id},
					parent = group_id,
				}, true
			}
			current += 1
			unit_count, matches := status_hierarchy_diff_unit_count(observation, document, path)
			if !matches do continue
			path_id := Status_Item_ID{kind = .Path, group = group, path = path.id}
			for unit_index in 0 ..< unit_count {
				unit, unit_found := diff_document_unit(document, unit_index)
				if !unit_found do return {}, false
				if current == ordinal {
					return Status_Item {
						id = {
							kind = .Diff_Unit,
							group = group,
							path = path.id,
							source = unit.target.source,
							unit = unit.target.unit,
						},
						parent = path_id,
					}, true
				}
				current += 1
			}
		}
	}
	return {}, false
}

/* status_selection_begin selects the first available Status hierarchy object. */
status_selection_begin :: proc(observation: ^Status_Observation) -> (Status_Selection, bool) {
	descriptor, available := status_observation_descriptor(observation)
	if !available do return {}, false
	first, found := status_hierarchy_item(observation, 0)
	if !found {
		return Status_Selection{generation = descriptor.generation}, true
	}
	return Status_Selection{generation = descriptor.generation, current = first.id}, true
}

/* status_selection_is_current checks that local state belongs to this observation. */
status_selection_is_current :: proc(
	observation: ^Status_Observation,
	selection: Status_Selection,
	document: ^Diff_Document = nil,
) -> bool {
	descriptor, available := status_observation_descriptor(observation)
	if !available || selection.generation != descriptor.generation do return false
	return status_selection_item_exists(observation, selection.current, document)
}

/* status_selection_move moves once through visible semantic Status objects. */
status_selection_move :: proc(
	observation: ^Status_Observation,
	selection: Status_Selection,
	direction: Status_Navigation,
	document: ^Diff_Document = nil,
) -> (Status_Selection, bool, Failure_Code) {
	if !status_selection_is_current(observation, selection, document) do return {}, false, .Stale_Observation
	count, available := status_hierarchy_item_count(observation, document)
	if !available || count == 0 do return selection, true, .None
	ordinal, found := status_hierarchy_find(observation, selection.current, document)
	if !found do return {}, false, .Stale_Observation
	next := ordinal
	switch direction {
	case .Previous:
		if next > 0 do next -= 1
	case .Next:
		if next + 1 < count do next += 1
	}
	item, item_found := status_hierarchy_item(observation, next, document)
	if !item_found do return {}, false, .Stale_Observation
	next_selection := selection
	next_selection.current = item.id
	return next_selection, true, .None
}

/* status_selection_toggle_expansion toggles detail for the selected exact path. */
status_selection_toggle_expansion :: proc(
	observation: ^Status_Observation,
	selection: Status_Selection,
	document: ^Diff_Document = nil,
) -> (Status_Selection, bool, Failure_Code) {
	if !status_selection_is_current(observation, selection, document) do return {}, false, .Stale_Observation
	if selection.current.kind == .Diff_Unit {
		next_selection := selection
		next_selection.current = {
			kind = .Path,
			group = selection.current.group,
			path = selection.current.path,
		}
		next_selection.expanded = {}
		return next_selection, true, .None
	}
	if selection.current.kind != .Path do return selection, true, .None
	next_selection := selection
	target := Path_Target{generation = selection.generation, path = selection.current.path}
	if next_selection.expanded == target {
		next_selection.expanded = {}
	} else {
		next_selection.expanded = target
	}
	return next_selection, true, .None
}

/* status_selection_path_target returns the selected path's checked action identity. */
status_selection_path_target :: proc(
	observation: ^Status_Observation,
	selection: Status_Selection,
) -> (Path_Target, bool, Failure_Code) {
	if !status_selection_is_current(observation, selection) do return {}, false, .Stale_Observation
	if selection.current.kind != .Path do return {}, false, .Path_Unavailable
	return Path_Target{generation = selection.generation, path = selection.current.path}, true, .None
}

/* status_selection_diff_unit_target returns the selected exact semantic hunk. */
status_selection_diff_unit_target :: proc(
	observation: ^Status_Observation,
	document: ^Diff_Document,
	selection: Status_Selection,
) -> (Diff_Unit_Target, bool, Failure_Code) {
	if !status_selection_is_current(observation, selection, document) {
		return {}, false, .Stale_Observation
	}
	if selection.current.kind != .Diff_Unit do return {}, false, .Diff_Unit_Unavailable
	target := Diff_Unit_Target {
		path = {generation = selection.generation, path = selection.current.path},
		source = selection.current.source,
		layer = diff_layer_for_group(selection.current.group),
		unit = selection.current.unit,
	}
	if !diff_unit_target_is_valid(target) do return {}, false, .Diff_Unit_Unavailable
	_, patch_available, failure := diff_document_unit_patch(document, target)
	if !patch_available do return {}, false, failure
	return target, true, .None
}

/* status_selection_reconcile preserves targets across a confirmed fresh observation. */
status_selection_reconcile :: proc(
	previous: ^Status_Observation,
	next: ^Status_Observation,
	selection: Status_Selection,
	document: ^Diff_Document = nil,
) -> (Status_Selection, bool, Failure_Code) {
	if !status_selection_is_current(previous, selection, document) do return {}, false, .Stale_Observation
	next_descriptor, next_available := status_observation_descriptor(next)
	if !next_available || next_descriptor.generation == selection.generation do return {}, false, .Invalid_Request
	next_selection := Status_Selection{generation = next_descriptor.generation}
	if selection.current.kind == .Path || selection.current.kind == .Diff_Unit {
		previous_path, previous_found := status_selection_path(previous, selection.current.path)
		if previous_found {
			matched, match_found := status_observation_find_path_by_text(next, previous, previous_path)
			if match_found {
				next_selection.current = {kind = .Path, group = matched.group, path = matched.id}
				if selection.expanded.path == previous_path.id {
					next_selection.expanded = {generation = next_descriptor.generation, path = matched.id}
				}
				return next_selection, true, .None
			}
		}
		if status_hierarchy_group_path_count(next, selection.current.group) > 0 {
			next_selection.current = {kind = .Group, group = selection.current.group}
			return next_selection, true, .None
		}
	} else if selection.current.kind == .Group && status_hierarchy_group_path_count(next, selection.current.group) > 0 {
		next_selection.current = selection.current
		return next_selection, true, .None
	}
	first, found := status_hierarchy_item(next, 0)
	if found do next_selection.current = first.id
	return next_selection, true, .None
}

@(private)
STATUS_GROUP_ORDER :: [?]Change_Group{.Unmerged, .Untracked, .Unstaged, .Staged}

@(private)
status_hierarchy_group_path_count :: proc(observation: ^Status_Observation, group: Change_Group) -> u32 {
	path_count, available := status_observation_path_count(observation)
	if !available do return 0
	count: u32
	for path_index in 0 ..< path_count {
		path, found := status_observation_path(observation, path_index)
		if found && path.group == group do count += 1
	}
	return count
}

@(private)
status_hierarchy_find :: proc(
	observation: ^Status_Observation,
	wanted: Status_Item_ID,
	document: ^Diff_Document = nil,
) -> (u32, bool) {
	count, available := status_hierarchy_item_count(observation, document)
	if !available do return 0, false
	for ordinal in 0 ..< count {
		item, found := status_hierarchy_item(observation, ordinal, document)
		if found && item.id == wanted do return ordinal, true
	}
	return 0, false
}

@(private)
status_selection_item_exists :: proc(
	observation: ^Status_Observation,
	wanted: Status_Item_ID,
	document: ^Diff_Document = nil,
) -> bool {
	_, found := status_hierarchy_find(observation, wanted, document)
	return found
}

@(private)
status_hierarchy_diff_unit_count :: proc(
	observation: ^Status_Observation,
	document: ^Diff_Document,
	path: Status_Path,
) -> (u32, bool) {
	if document == nil || document.state == nil || !diff_document_is_current(document, observation) do return 0, false
	descriptor, described := diff_document_descriptor(document)
	if !described || descriptor.path.path != path.id do return 0, false
	layer := diff_layer_for_group(path.group)
	if layer == .Invalid || descriptor.layer != layer do return 0, false
	return descriptor.unit_count, true
}

@(private)
diff_layer_for_group :: proc(group: Change_Group) -> Diff_Layer {
	if group == .Unstaged do return .Working_Tree
	if group == .Staged do return .Index
	return .Invalid
}

@(private)
status_selection_path :: proc(observation: ^Status_Observation, wanted: Path_ID) -> (Status_Path, bool) {
	path_count, available := status_observation_path_count(observation)
	if !available do return {}, false
	for path_index in 0 ..< path_count {
		path, found := status_observation_path(observation, path_index)
		if found && path.id == wanted do return path, true
	}
	return {}, false
}

@(private)
status_observation_find_path_by_text :: proc(
	observation: ^Status_Observation,
	previous: ^Status_Observation,
	wanted: Status_Path,
) -> (Status_Path, bool) {
	wanted_text, copied := status_observation_path_text(previous, wanted)
	if !copied do return {}, false
	path_count, available := status_observation_path_count(observation)
	if !available do return {}, false
	for path_index in 0 ..< path_count {
		candidate, found := status_observation_path(observation, path_index)
		if !found do continue
		candidate_text, candidate_copied := status_observation_path_text(observation, candidate)
		if candidate_copied && status_path_text_equal(candidate_text, wanted_text) do return candidate, true
	}
	return {}, false
}

@(private)
status_path_text_equal :: proc(left: []u8, right: []u8) -> bool {
	if len(left) != len(right) do return false
	for index in 0 ..< len(left) {
		if left[index] != right[index] do return false
	}
	return true
}
