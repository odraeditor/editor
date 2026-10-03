// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package maksym

import "../filesystem"
import "base:runtime"

@(private)
Target_Set_State :: struct {
	id:                 Target_Set_ID,
	generation:         Target_Set_Generation,
	directory_identity: filesystem.Resource_ID,
	listing_generation: u64,
	members:            []Target_Set_Member,
	has_current:        bool,
	current_index:      int,
	member_limit:       u32,
	allocator:          runtime.Allocator,
}

@(private)
Target_Set_Snapshot_State :: struct {
	view:      Target_Set_View,
	allocator: runtime.Allocator,
}

/* target_set_open creates one empty target-set generation. */
target_set_open :: proc(
	set: ^Target_Set,
	config: Target_Set_Config,
) -> (bool, Failure_Context) {
	if set == nil || set.state != nil || config.id == Target_Set_ID(0) ||
	   !filesystem.resource_id_valid(config.directory_identity) ||
	   config.listing_generation == 0 || config.member_limit == 0 ||
	   config.member_limit > MAX_TARGET_SET_MEMBERS || config.allocator.procedure == nil {
		return false, {operation = .Open_Target_Set, code = .Invalid_Target_Set}
	}
	state, allocation_error := new(Target_Set_State, config.allocator)
	if allocation_error != nil {
		return false, {operation = .Open_Target_Set, code = .Persistent_Memory_Limit}
	}
	state^ = {
		id = config.id,
		generation = Target_Set_Generation(1),
		directory_identity = config.directory_identity,
		listing_generation = config.listing_generation,
		current_index = -1,
		member_limit = config.member_limit,
		allocator = config.allocator,
	}
	set.state = state
	return true, {}
}

/* target_set_replace atomically publishes one ordered membership generation. */
target_set_replace :: proc(
	set: ^Target_Set,
	expected_generation: Target_Set_Generation,
	listing_generation: u64,
	members: []Target_Set_Member,
	current_index: int,
) -> (Target_Set_Generation, bool, Failure_Context) {
	state, failure := target_set_resolve(set, .Replace_Target_Set)
	if failure.code != .None do return {}, false, failure
	if expected_generation == Target_Set_Generation(0) ||
	   expected_generation != state.generation || listing_generation != state.listing_generation ||
	   u64(len(members)) > u64(state.member_limit) ||
	   (len(members) == 0 && current_index != -1) ||
	   (len(members) > 0 && (current_index < 0 || current_index >= len(members))) {
		code := Failure_Code.Invalid_Target_Set
		if expected_generation != state.generation do code = .Stale_Target_Set
		if listing_generation != state.listing_generation do code = .Invalid_Generation
		if u64(len(members)) > u64(state.member_limit) do code = .Target_Set_Limit
		return {}, false, {
			operation = .Replace_Target_Set,
			code = code,
			generation = u64(expected_generation),
		}
	}
	if state.generation == Target_Set_Generation(max(u64)) {
		return {}, false, {
			operation = .Replace_Target_Set,
			code = .Target_Set_Limit,
			generation = u64(state.generation),
		}
	}
	for member, index in members {
		if !filesystem.resource_id_valid(member.identity) {
			return {}, false, {
				operation = .Replace_Target_Set,
				code = .Invalid_Target_Set,
				generation = u64(state.generation),
				resource = member.identity,
			}
		}
		for prior in members[:index] {
			if prior.identity == member.identity {
				return {}, false, {
					operation = .Replace_Target_Set,
					code = .Duplicate_Target,
					generation = u64(state.generation),
					resource = member.identity,
				}
			}
		}
	}
	candidate: []Target_Set_Member
	if len(members) > 0 {
		allocation_error: runtime.Allocator_Error
		candidate, allocation_error = make([]Target_Set_Member, len(members), state.allocator)
		if allocation_error != nil {
			return {}, false, {
				operation = .Replace_Target_Set,
				code = .Persistent_Memory_Limit,
				generation = u64(state.generation),
			}
		}
		copy(candidate, members)
	}
	if state.members != nil do delete(state.members, state.allocator)
	state.members = candidate
	state.listing_generation = listing_generation
	state.has_current = len(candidate) > 0
	state.current_index = current_index
	state.generation = Target_Set_Generation(u64(state.generation) + 1)
	return state.generation, true, {}
}

/* target_set_reconcile retains resources present in one checked newer listing. */
target_set_reconcile :: proc(
	set: ^Target_Set,
	expected_generation: Target_Set_Generation,
	expected_listing_generation: u64,
	directory_identity: filesystem.Resource_ID,
	listing_generation: u64,
	visible: []Target_Set_Member,
) -> (Target_Set_Transition, bool, Failure_Context) {
	state, failure := target_set_resolve(set, .Reconcile_Target_Set)
	if failure.code != .None do return {}, false, failure
	if expected_generation == Target_Set_Generation(0) || expected_generation != state.generation {
		return {}, false, {
			operation = .Reconcile_Target_Set,
			code = .Stale_Target_Set,
			generation = u64(expected_generation),
		}
	}
	if state.generation == Target_Set_Generation(max(u64)) {
		return {}, false, {
			operation = .Reconcile_Target_Set,
			code = .Target_Set_Limit,
			generation = u64(state.generation),
		}
	}
	if expected_listing_generation == 0 || expected_listing_generation != state.listing_generation ||
	   listing_generation <= expected_listing_generation {
		return {}, false, {
			operation = .Reconcile_Target_Set,
			code = .Invalid_Generation,
			generation = expected_listing_generation,
		}
	}
	if !filesystem.resource_id_valid(directory_identity) || directory_identity != state.directory_identity {
		return {}, false, {
			operation = .Reconcile_Target_Set,
			code = .Directory_Changed,
			generation = listing_generation,
			resource = directory_identity,
		}
	}
	for member, index in visible {
		if !filesystem.resource_id_valid(member.identity) {
			return {}, false, {
				operation = .Reconcile_Target_Set,
				code = .Invalid_Target_Set,
				generation = listing_generation,
				resource = member.identity,
			}
		}
		for prior in visible[:index] {
			if prior.identity == member.identity {
				return {}, false, {
					operation = .Reconcile_Target_Set,
					code = .Duplicate_Target,
					generation = listing_generation,
					resource = member.identity,
				}
			}
		}
	}
	survivor_count := 0
	for member in state.members {
		if target_set_members_contain(visible, member.identity) do survivor_count += 1
	}
	candidate: []Target_Set_Member
	if survivor_count > 0 {
		allocation_error: runtime.Allocator_Error
		candidate, allocation_error = make([]Target_Set_Member, survivor_count, state.allocator)
		if allocation_error != nil {
			return {}, false, {
				operation = .Reconcile_Target_Set,
				code = .Persistent_Memory_Limit,
				generation = listing_generation,
			}
		}
		candidate_index := 0
		for member in state.members {
			if !target_set_members_contain(visible, member.identity) do continue
			candidate[candidate_index] = member
			candidate_index += 1
		}
	}
	current_identity: filesystem.Resource_ID
	if state.has_current && state.current_index >= 0 && state.current_index < len(state.members) {
		current_identity = state.members[state.current_index].identity
	}
	current_index := -1
	for member, index in candidate {
		if member.identity == current_identity {
			current_index = index
			break
		}
	}
	if current_index < 0 && len(candidate) > 0 {
		current_index = min(max(state.current_index, 0), len(candidate) - 1)
	}
	membership_changed := len(candidate) != len(state.members)
	target_set_commit_members(state, candidate, listing_generation, current_index)
	return {generation = state.generation, changed = membership_changed}, true, {}
}

/* target_set_mark appends one absent resource to the ordered target set. */
target_set_mark :: proc(
	set: ^Target_Set,
	expected_generation: Target_Set_Generation,
	listing_generation: u64,
	identity: filesystem.Resource_ID,
) -> (Target_Set_Transition, bool, Failure_Context) {
	state, failure := target_set_mutation_state(
		set, expected_generation, listing_generation, identity, .Mark_Target,
	)
	if failure.code != .None do return {}, false, failure
	for member in state.members {
		if member.identity == identity {
			return {generation = state.generation}, true, {}
		}
	}
	if len(state.members) >= int(state.member_limit) {
		return {}, false, {
			operation = .Mark_Target,
			code = .Target_Set_Limit,
			generation = u64(state.generation),
			resource = identity,
		}
	}
	candidate, allocation_error := make(
		[]Target_Set_Member,
		len(state.members) + 1,
		state.allocator,
	)
	if allocation_error != nil {
		return {}, false, {
			operation = .Mark_Target,
			code = .Persistent_Memory_Limit,
			generation = u64(state.generation),
		}
	}
	copy(candidate, state.members)
	candidate[len(candidate) - 1] = {identity = identity}
	target_set_commit_members(state, candidate, listing_generation, len(candidate) - 1)
	return {generation = state.generation, changed = true}, true, {}
}

/* target_set_unmark removes one present resource without reordering survivors. */
target_set_unmark :: proc(
	set: ^Target_Set,
	expected_generation: Target_Set_Generation,
	listing_generation: u64,
	identity: filesystem.Resource_ID,
) -> (Target_Set_Transition, bool, Failure_Context) {
	state, failure := target_set_mutation_state(
		set, expected_generation, listing_generation, identity, .Unmark_Target,
	)
	if failure.code != .None do return {}, false, failure
	removed_index := -1
	for member, index in state.members {
		if member.identity == identity {
			removed_index = index
			break
		}
	}
	if removed_index < 0 do return {generation = state.generation}, true, {}
	candidate: []Target_Set_Member
	if len(state.members) > 1 {
		allocation_error: runtime.Allocator_Error
		candidate, allocation_error = make(
			[]Target_Set_Member,
			len(state.members) - 1,
			state.allocator,
		)
		if allocation_error != nil {
			return {}, false, {
				operation = .Unmark_Target,
				code = .Persistent_Memory_Limit,
				generation = u64(state.generation),
			}
		}
		copy(candidate[:removed_index], state.members[:removed_index])
		copy(candidate[removed_index:], state.members[removed_index + 1:])
	}
	current_index := -1
	if len(candidate) > 0 {
		current_index = min(state.current_index, len(candidate) - 1)
		if removed_index < state.current_index do current_index -= 1
		current_index = max(current_index, 0)
	}
	target_set_commit_members(state, candidate, listing_generation, current_index)
	return {generation = state.generation, changed = true}, true, {}
}

/* target_set_invert replaces membership with the unmarked visible resources in visible order. */
target_set_invert :: proc(
	set: ^Target_Set,
	expected_generation: Target_Set_Generation,
	listing_generation: u64,
	visible: []Target_Set_Member,
) -> (Target_Set_Transition, bool, Failure_Context) {
	state, failure := target_set_mutation_state(
		set, expected_generation, listing_generation, {}, .Invert_Targets,
	)
	if failure.code != .None do return {}, false, failure
	if len(visible) > int(state.member_limit) {
		return {}, false, {
			operation = .Invert_Targets,
			code = .Target_Set_Limit,
			generation = u64(state.generation),
		}
	}
	for member, index in visible {
		if !filesystem.resource_id_valid(member.identity) {
			return {}, false, {
				operation = .Invert_Targets,
				code = .Invalid_Target_Set,
				generation = u64(state.generation),
				resource = member.identity,
			}
		}
		for prior in visible[:index] {
			if prior.identity == member.identity {
				return {}, false, {
					operation = .Invert_Targets,
					code = .Duplicate_Target,
					generation = u64(state.generation),
					resource = member.identity,
				}
			}
		}
	}
	unmarked_count := 0
	for member in visible {
		if !target_set_state_contains(state, member.identity) do unmarked_count += 1
	}
	candidate: []Target_Set_Member
	if unmarked_count > 0 {
		allocation_error: runtime.Allocator_Error
		candidate, allocation_error = make([]Target_Set_Member, unmarked_count, state.allocator)
		if allocation_error != nil {
			return {}, false, {
				operation = .Invert_Targets,
				code = .Persistent_Memory_Limit,
				generation = u64(state.generation),
			}
		}
		candidate_index := 0
		for member in visible {
			if target_set_state_contains(state, member.identity) do continue
			candidate[candidate_index] = member
			candidate_index += 1
		}
	}
	current_index := 0 if len(candidate) > 0 else -1
	target_set_commit_members(state, candidate, listing_generation, current_index)
	return {generation = state.generation, changed = true}, true, {}
}

/* target_set_clear removes every target from one checked generation. */
target_set_clear :: proc(
	set: ^Target_Set,
	expected_generation: Target_Set_Generation,
	listing_generation: u64,
) -> (Target_Set_Transition, bool, Failure_Context) {
	state, failure := target_set_mutation_state(
		set, expected_generation, listing_generation, {}, .Clear_Targets,
	)
	if failure.code != .None do return {}, false, failure
	if len(state.members) == 0 do return {generation = state.generation}, true, {}
	target_set_commit_members(state, nil, listing_generation, -1)
	return {generation = state.generation, changed = true}, true, {}
}

/* target_set_move_current moves within the ordered marked set without wrapping. */
target_set_move_current :: proc(
	set: ^Target_Set,
	expected_generation: Target_Set_Generation,
	delta: i32,
) -> (Target_Set_Movement, bool, Failure_Context) {
	state, failure := target_set_resolve(set, .Move_Current_Target)
	if failure.code != .None do return {}, false, failure
	if expected_generation == Target_Set_Generation(0) || expected_generation != state.generation {
		return {}, false, {
			operation = .Move_Current_Target,
			code = .Stale_Target_Set,
			generation = u64(expected_generation),
		}
	}
	if !state.has_current || len(state.members) == 0 || delta == 0 {
		return {generation = state.generation, previous_index = state.current_index,
			current_index = state.current_index}, true, {}
	}
	previous := state.current_index
	next := clamp(previous + int(delta), 0, len(state.members) - 1)
	state.current_index = next
	return {
		generation = state.generation,
		previous_index = previous,
		current_index = next,
		identity = state.members[next].identity,
		changed = next != previous,
	}, true, {}
}

/* target_set_contains reports membership from one exact generation. */
target_set_contains :: proc(
	set: ^Target_Set,
	expected_generation: Target_Set_Generation,
	identity: filesystem.Resource_ID,
) -> (bool, bool, Failure_Context) {
	state, failure := target_set_resolve(set, .Inspect_Target_Set)
	if failure.code != .None do return false, false, failure
	if expected_generation == Target_Set_Generation(0) || expected_generation != state.generation ||
	   !filesystem.resource_id_valid(identity) {
		return false, false, {
			operation = .Inspect_Target_Set,
			code = .Stale_Target_Set,
			generation = u64(expected_generation),
			resource = identity,
		}
	}
	return target_set_state_contains(state, identity), true, {}
}

/* target_set_inspect copies one complete immutable target-set generation. */
target_set_inspect :: proc(
	set: ^Target_Set,
	snapshot: ^Target_Set_Snapshot,
) -> (bool, Failure_Context) {
	state, failure := target_set_resolve(set, .Inspect_Target_Set)
	if failure.code != .None do return false, failure
	if snapshot == nil || snapshot.state != nil {
		return false, {
			operation = .Inspect_Target_Set,
			code = .Invalid_Target_Set,
			generation = u64(state.generation),
		}
	}
	copy_state, allocation_error := new(Target_Set_Snapshot_State, state.allocator)
	if allocation_error != nil {
		return false, {
			operation = .Inspect_Target_Set,
			code = .Persistent_Memory_Limit,
			generation = u64(state.generation),
		}
	}
	copy_state.allocator = state.allocator
	if len(state.members) > 0 {
		copy_state.view.members, allocation_error = make(
			[]Target_Set_Member,
			len(state.members),
			state.allocator,
		)
		if allocation_error != nil {
			free(copy_state, state.allocator)
			return false, {
				operation = .Inspect_Target_Set,
				code = .Persistent_Memory_Limit,
				generation = u64(state.generation),
			}
		}
		copy(copy_state.view.members, state.members)
	}
	copy_state.view.id = state.id
	copy_state.view.generation = state.generation
	copy_state.view.directory_identity = state.directory_identity
	copy_state.view.listing_generation = state.listing_generation
	copy_state.view.has_current = state.has_current
	copy_state.view.current_index = state.current_index
	copy_state.view.member_limit = state.member_limit
	snapshot.state = copy_state
	return true, {}
}

/* target_set_snapshot_view borrows one copied target-set inspection. */
target_set_snapshot_view :: proc(
	snapshot: ^Target_Set_Snapshot,
) -> (Target_Set_View, bool, Failure_Context) {
	if snapshot == nil || snapshot.state == nil {
		return {}, false, {operation = .Inspect_Target_Set, code = .Invalid_Target_Set}
	}
	state := cast(^Target_Set_Snapshot_State)snapshot.state
	return state.view, true, {}
}

/* target_set_snapshot_close releases one copied inspection. */
target_set_snapshot_close :: proc(snapshot: ^Target_Set_Snapshot) -> (bool, Failure_Context) {
	if snapshot == nil || snapshot.state == nil {
		return false, {operation = .Close_Target_Set_Snapshot, code = .Invalid_Target_Set}
	}
	state := cast(^Target_Set_Snapshot_State)snapshot.state
	allocator := state.allocator
	if state.view.members != nil do delete(state.view.members, allocator)
	free(state, allocator)
	snapshot.state = nil
	return true, {}
}

/* target_set_close releases one target-set owner and its membership. */
target_set_close :: proc(set: ^Target_Set) -> (bool, Failure_Context) {
	state, failure := target_set_resolve(set, .Close_Target_Set)
	if failure.code != .None do return false, failure
	allocator := state.allocator
	if state.members != nil do delete(state.members, allocator)
	free(state, allocator)
	set.state = nil
	return true, {}
}

@(private)
target_set_mutation_state :: proc(
	set: ^Target_Set,
	expected_generation: Target_Set_Generation,
	listing_generation: u64,
	identity: filesystem.Resource_ID,
	operation: Operation,
) -> (^Target_Set_State, Failure_Context) {
	state, failure := target_set_resolve(set, operation)
	if failure.code != .None do return nil, failure
	if expected_generation == Target_Set_Generation(0) || expected_generation != state.generation {
		return nil, {
			operation = operation,
			code = .Stale_Target_Set,
			generation = u64(expected_generation),
			resource = identity,
		}
	}
	if listing_generation == 0 || state.generation == Target_Set_Generation(max(u64)) ||
	   (filesystem.resource_id_valid(identity) == false &&
	    (operation == .Mark_Target || operation == .Unmark_Target)) {
		return nil, {
			operation = operation,
			code = .Invalid_Target_Set,
			generation = u64(state.generation),
			resource = identity,
		}
	}
	if listing_generation != state.listing_generation {
		return nil, {
			operation = operation,
			code = .Invalid_Generation,
			generation = listing_generation,
			resource = identity,
		}
	}
	return state, {}
}

@(private)
target_set_commit_members :: proc(
	state: ^Target_Set_State,
	members: []Target_Set_Member,
	listing_generation: u64,
	current_index: int,
) {
	assert(state != nil)
	if state.members != nil do delete(state.members, state.allocator)
	state.members = members
	state.listing_generation = listing_generation
	state.has_current = len(members) > 0
	state.current_index = current_index
	state.generation = Target_Set_Generation(u64(state.generation) + 1)
}

@(private)
target_set_state_contains :: proc(
	state: ^Target_Set_State,
	identity: filesystem.Resource_ID,
) -> bool {
	if state == nil do return false
	for member in state.members {
		if member.identity == identity do return true
	}
	return false
}

@(private)
target_set_members_contain :: proc(
	members: []Target_Set_Member,
	identity: filesystem.Resource_ID,
) -> bool {
	for member in members {
		if member.identity == identity do return true
	}
	return false
}

@(private)
target_set_resolve :: proc(
	set: ^Target_Set,
	operation: Operation,
) -> (^Target_Set_State, Failure_Context) {
	if set == nil || set.state == nil {
		return nil, {operation = operation, code = .Invalid_Target_Set}
	}
	return cast(^Target_Set_State)set.state, {}
}
