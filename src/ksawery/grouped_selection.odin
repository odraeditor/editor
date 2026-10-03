// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery

import "base:runtime"

/* MIN_GROUP_TARGETS is the smallest useful grouped-operation capacity. */
MIN_GROUP_TARGETS :: u32(2)
/* MAX_GROUP_TARGETS is the immutable grouped-operation capacity ceiling. */
MAX_GROUP_TARGETS :: u32(256)
/* DEFAULT_GROUP_TARGETS is the initial grouped-operation capacity. */
DEFAULT_GROUP_TARGETS :: u32(64)

/* Grouped_Selection_ID identifies one exact ordered target set. */
Grouped_Selection_ID :: distinct u64

/* Grouped_Granularity distinguishes complete-path and semantic-hunk sets. */
Grouped_Granularity :: enum u8 {
	Invalid,
	Complete_Paths,
	Diff_Units,
}

/* Grouped_Selection_Limits bounds one session-local target set. */
Grouped_Selection_Limits :: struct {
	targets: u32,
}

/* DEFAULT_GROUPED_SELECTION_LIMITS selects the initial target-set envelope. */
DEFAULT_GROUPED_SELECTION_LIMITS :: Grouped_Selection_Limits {
	targets = DEFAULT_GROUP_TARGETS,
}

/* Grouped_Target describes one exact marked path or hunk. */
Grouped_Target :: struct {
	granularity: Grouped_Granularity,
	group:       Change_Group,
	path:        Path_Target,
	unit:        Diff_Unit_Target,
	old_start:   u32,
	old_count:   u32,
	new_start:   u32,
	new_count:   u32,
}

/* Grouped_Selection_Descriptor reports one bounded compatible target set. */
Grouped_Selection_Descriptor :: struct {
	id:          Grouped_Selection_ID,
	repository:  Repository_Context,
	generation:  Observation_Generation,
	granularity: Grouped_Granularity,
	action:      Index_Action,
	layer:       Diff_Layer,
	targets:     u32,
}

/* Grouped_Selection owns one ordered session-local compatible target set. */
Grouped_Selection :: struct {
	state: rawptr,
}

/* Grouped_Selection_Usage reports exact retained target-set resources. */
Grouped_Selection_Usage :: struct {
	targets:          u32,
	allocation_bytes: u64,
}

@(private)
Grouped_Selection_Data :: struct {
	descriptor: Grouped_Selection_Descriptor,
	targets:    [dynamic]Grouped_Target,
	limits:     Grouped_Selection_Limits,
	allocator:  runtime.Allocator,
}

/* grouped_selection_open creates one empty set bound to an exact observation. */
grouped_selection_open :: proc(
	observation: ^Status_Observation,
	limits := DEFAULT_GROUPED_SELECTION_LIMITS,
	allocator := context.allocator,
) -> (Grouped_Selection, bool, Failure_Code) {
	descriptor, observed := status_observation_descriptor(observation)
	if allocator.procedure == nil || !observed || !grouped_selection_limits_are_valid(limits) {
		return {}, false, .Invalid_Request
	}
	state, allocation_error := new(Grouped_Selection_Data, allocator)
	if allocation_error != nil do return {}, false, .Allocation
	state.allocator = allocator
	state.limits = limits
	state.descriptor.repository = descriptor.repository
	state.descriptor.generation = descriptor.generation
	state.targets, allocation_error = make([dynamic]Grouped_Target, 0, int(min(limits.targets, 8)), allocator)
	if allocation_error != nil {
		grouped_selection_data_destroy(state)
		return {}, false, .Allocation
	}
	return Grouped_Selection{state = state}, true, .None
}

/* grouped_selection_descriptor copies immutable set metadata. */
grouped_selection_descriptor :: proc(
	selection: ^Grouped_Selection,
) -> (Grouped_Selection_Descriptor, bool) {
	state := grouped_selection_data(selection)
	if state == nil do return {}, false
	return state.descriptor, true
}

/* grouped_selection_target returns one marked target in explicit mark order. */
grouped_selection_target :: proc(
	selection: ^Grouped_Selection,
	ordinal: u32,
) -> (Grouped_Target, bool) {
	state := grouped_selection_data(selection)
	if state == nil || ordinal >= u32(len(state.targets)) do return {}, false
	return state.targets[ordinal], true
}

/* grouped_selection_mark adds one compatible semantic selection exactly once. */
grouped_selection_mark :: proc(
	observation: ^Status_Observation,
	document: ^Diff_Document,
	current: Status_Selection,
	selection: ^Grouped_Selection,
) -> (bool, Failure_Code) {
	state := grouped_selection_data(selection)
	if state == nil do return false, .Invalid_Request
	if !grouped_selection_is_current(state, observation) do return false, .Stale_Observation
	target, action, layer, selected, failure := grouped_target_from_selection(observation, document, current)
	if !selected do return false, failure
	if u32(len(state.targets)) >= state.limits.targets do return false, .Target_Limit
	for existing in state.targets {
		if grouped_target_same_identity(existing, target) do return false, .Target_Duplicate
	}
	if len(state.targets) > 0 {
		compatibility_failure := grouped_target_compatibility(state, target, action, layer)
		if compatibility_failure != .None do return false, compatibility_failure
	} else {
		state.descriptor.granularity = target.granularity
		state.descriptor.action = action
		state.descriptor.layer = layer
	}
	_, allocation_error := append(&state.targets, target)
	if allocation_error != nil do return false, .Allocation
	grouped_selection_reidentify(state)
	return true, .None
}

/* grouped_selection_unmark removes one exact currently selected marked target. */
grouped_selection_unmark :: proc(
	observation: ^Status_Observation,
	document: ^Diff_Document,
	current: Status_Selection,
	selection: ^Grouped_Selection,
) -> (bool, Failure_Code) {
	state := grouped_selection_data(selection)
	if state == nil do return false, .Invalid_Request
	if !grouped_selection_is_current(state, observation) do return false, .Stale_Observation
	target, _, _, selected, failure := grouped_target_from_selection(observation, document, current)
	if !selected do return false, failure
	for existing, index in state.targets {
		if !grouped_target_same_identity(existing, target) do continue
		ordered_remove(&state.targets, index)
		if len(state.targets) == 0 {
			state.descriptor.granularity = .Invalid
			state.descriptor.action = .Invalid
			state.descriptor.layer = .Invalid
		}
		grouped_selection_reidentify(state)
		return true, .None
	}
	return false, .Path_Unavailable
}

/* grouped_selection_clear removes every mark while preserving observation binding. */
grouped_selection_clear :: proc(selection: ^Grouped_Selection) -> bool {
	state := grouped_selection_data(selection)
	if state == nil do return false
	clear(&state.targets)
	state.descriptor.id = {}
	state.descriptor.granularity = .Invalid
	state.descriptor.action = .Invalid
	state.descriptor.layer = .Invalid
	state.descriptor.targets = 0
	return true
}

/* grouped_selection_contains reports exact membership without changing order. */
grouped_selection_contains :: proc(selection: ^Grouped_Selection, target: Grouped_Target) -> bool {
	state := grouped_selection_data(selection)
	if state == nil do return false
	for existing in state.targets {
		if grouped_target_same_identity(existing, target) do return true
	}
	return false
}

/* grouped_selection_contains_current reports membership for one semantic selection. */
grouped_selection_contains_current :: proc(
	observation: ^Status_Observation,
	document: ^Diff_Document,
	current: Status_Selection,
	selection: ^Grouped_Selection,
) -> bool {
	target, _, _, selected, _ := grouped_target_from_selection(observation, document, current)
	return selected && grouped_selection_contains(selection, target)
}

/* grouped_selection_action_available requires at least two compatible targets. */
grouped_selection_action_available :: proc(
	selection: ^Grouped_Selection,
	action: Index_Action,
) -> bool {
	state := grouped_selection_data(selection)
	return state != nil && len(state.targets) >= 2 && state.descriptor.action == action &&
	       state.descriptor.id != Grouped_Selection_ID(0)
}

/* grouped_selection_reconcile invalidates marks across every fresh observation. */
grouped_selection_reconcile :: proc(
	selection: ^Grouped_Selection,
	next: ^Status_Observation,
) -> (u32, bool, Failure_Code) {
	state := grouped_selection_data(selection)
	descriptor, observed := status_observation_descriptor(next)
	if state == nil || !observed || descriptor.repository != state.descriptor.repository ||
	   descriptor.generation == state.descriptor.generation {
		return 0, false, .Invalid_Request
	}
	removed := u32(len(state.targets))
	grouped_selection_clear(selection)
	state.descriptor.generation = descriptor.generation
	return removed, true, .None
}

/* grouped_selection_usage reports exact retained target storage. */
grouped_selection_usage :: proc(selection: ^Grouped_Selection) -> (Grouped_Selection_Usage, bool) {
	state := grouped_selection_data(selection)
	if state == nil do return {}, false
	return Grouped_Selection_Usage {
		targets = u32(len(state.targets)),
		allocation_bytes = u64(size_of(Grouped_Selection_Data)) +
		                   u64(cap(state.targets)) * u64(size_of(Grouped_Target)),
	}, true
}

/* grouped_selection_close releases one owned target set. */
grouped_selection_close :: proc(selection: ^Grouped_Selection) {
	state := grouped_selection_data(selection)
	if state == nil do return
	grouped_selection_data_destroy(state)
	selection^ = {}
}

/* grouped_selection_limits_are_valid checks the complete target-set envelope. */
grouped_selection_limits_are_valid :: proc(limits: Grouped_Selection_Limits) -> bool {
	return limits.targets >= MIN_GROUP_TARGETS && limits.targets <= MAX_GROUP_TARGETS
}

@(private)
grouped_target_from_selection :: proc(
	observation: ^Status_Observation,
	document: ^Diff_Document,
	current: Status_Selection,
) -> (Grouped_Target, Index_Action, Diff_Layer, bool, Failure_Code) {
	if current.current.kind == .Path {
		target, selected, failure := status_selection_path_target(observation, current)
		if !selected do return {}, .Invalid, .Invalid, false, failure
		path, found := status_observation_path_by_id(observation, target.path)
		if !found do return {}, .Invalid, .Invalid, false, .Path_Unavailable
		action, layer, supported := grouped_path_action(path.group)
		if !supported do return {}, .Invalid, .Invalid, false, .Action_Unavailable
		return Grouped_Target{granularity = .Complete_Paths, group = path.group, path = target},
		       action, layer, true, .None
	}
	if current.current.kind == .Diff_Unit {
		target, selected, failure := status_selection_diff_unit_target(observation, document, current)
		if !selected do return {}, .Invalid, .Invalid, false, failure
		action := Index_Action.Stage
		if target.layer == .Index {
			action = .Unstage
		} else if target.layer != .Working_Tree {
			return {}, .Invalid, .Invalid, false, .Action_Unavailable
		}
		unit, found := grouped_selection_diff_unit(document, target)
		if !found do return {}, .Invalid, .Invalid, false, .Diff_Unit_Unavailable
		return Grouped_Target {
			granularity = .Diff_Units,
			group = current.current.group,
			path = target.path,
			unit = target,
			old_start = unit.old_start,
			old_count = unit.old_count,
			new_start = unit.new_start,
			new_count = unit.new_count,
		}, action, target.layer, true, .None
	}
	return {}, .Invalid, .Invalid, false, .Action_Unavailable
}

@(private)
grouped_path_action :: proc(group: Change_Group) -> (Index_Action, Diff_Layer, bool) {
	if group == .Untracked || group == .Unstaged do return .Stage, .Working_Tree, true
	if group == .Staged do return .Unstage, .Index, true
	return .Invalid, .Invalid, false
}

@(private)
grouped_selection_diff_unit :: proc(
	document: ^Diff_Document,
	target: Diff_Unit_Target,
) -> (Diff_Unit_Descriptor, bool) {
	descriptor, described := diff_document_descriptor(document)
	if !described do return {}, false
	for unit_index in 0 ..< descriptor.unit_count {
		unit, found := diff_document_unit(document, unit_index)
		if found && unit.target == target do return unit, true
	}
	return {}, false
}

@(private)
grouped_target_same_identity :: proc(left, right: Grouped_Target) -> bool {
	if left.granularity != right.granularity do return false
	if left.granularity == .Complete_Paths do return left.path == right.path && left.group == right.group
	if left.granularity == .Diff_Units do return left.unit == right.unit
	return false
}

@(private)
grouped_target_compatibility :: proc(
	state: ^Grouped_Selection_Data,
	target: Grouped_Target,
	action: Index_Action,
	layer: Diff_Layer,
) -> Failure_Code {
	if state == nil || len(state.targets) == 0 do return .Invalid_Request
	if state.descriptor.granularity != target.granularity || state.descriptor.action != action ||
	   state.descriptor.layer != layer {
		return .Target_Incompatible
	}
	if target.granularity == .Diff_Units {
		if state.targets[0].path != target.path do return .Target_Incompatible
		for existing in state.targets {
			if grouped_diff_targets_overlap(existing, target) do return .Target_Overlap
		}
	}
	return .None
}

@(private)
grouped_diff_targets_overlap :: proc(left, right: Grouped_Target) -> bool {
	if left.granularity != .Diff_Units || right.granularity != .Diff_Units do return false
	return grouped_ranges_overlap(left.old_start, left.old_count, right.old_start, right.old_count) ||
	       grouped_ranges_overlap(left.new_start, left.new_count, right.new_start, right.new_count)
}

@(private)
grouped_ranges_overlap :: proc(left_start, left_count, right_start, right_count: u32) -> bool {
	if left_count == 0 || right_count == 0 do return false
	left_end := u64(left_start) + u64(left_count)
	right_end := u64(right_start) + u64(right_count)
	return u64(left_start) < right_end && u64(right_start) < left_end
}

@(private)
grouped_selection_is_current :: proc(
	state: ^Grouped_Selection_Data,
	observation: ^Status_Observation,
) -> bool {
	descriptor, observed := status_observation_descriptor(observation)
	return state != nil && observed && descriptor.repository == state.descriptor.repository &&
	       descriptor.generation == state.descriptor.generation
}

@(private)
grouped_selection_reidentify :: proc(state: ^Grouped_Selection_Data) {
	if state == nil do return
	state.descriptor.targets = u32(len(state.targets))
	if len(state.targets) == 0 {
		state.descriptor.id = {}
		return
	}
	hash := u64(14_695_981_039_346_656_037)
	for target in state.targets {
		values := [?]u64 {
			u64(target.granularity), u64(target.group), u64(target.path.generation),
			u64(target.path.path), u64(target.unit.source), u64(target.unit.layer),
			u64(target.unit.unit), u64(target.old_start), u64(target.old_count),
			u64(target.new_start), u64(target.new_count),
		}
		for value in values do hash = (hash ~ value) * 1_099_511_628_211
	}
	if hash == 0 do hash = 1
	state.descriptor.id = Grouped_Selection_ID(hash)
}

@(private)
grouped_selection_data :: proc(selection: ^Grouped_Selection) -> ^Grouped_Selection_Data {
	if selection == nil || selection.state == nil do return nil
	return cast(^Grouped_Selection_Data)selection.state
}

@(private)
grouped_selection_data_destroy :: proc(state: ^Grouped_Selection_Data) {
	if state == nil do return
	delete(state.targets)
	free(state, state.allocator)
}
