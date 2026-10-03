// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package history

import "base:runtime"

/* store_policy_inspect returns one copied policy generation without exposing store storage. */
store_policy_inspect :: proc(store: ^Store) -> (snapshot: Policy_Snapshot, ok: bool, failure: Failure_Context) {
	state, state_failure := store_live_state(store)
	if state_failure.code != .None {
		return {}, false, state_failure
	}
	return Policy_Snapshot {
		policy = state.policy,
		policy_generation = state.policy_generation,
		usage = state.usage,
	}, true, {}
}

/*
store_policy_replace atomically activates one complete policy generation.
Required pruning is planned and validated against protected topology before any node is released.
*/
store_policy_replace :: proc(
	store: ^Store,
	request: Policy_Replacement_Request,
) -> (result: Policy_Replacement_Result, ok: bool, failure: Failure_Context) {
	state, state_failure := store_live_state(store)
	if state_failure.code != .None {
		return {}, false, state_failure
	}
	if state.pending_reservation {
		return {}, false, store_failure(state, .Invalid_State)
	}
	if request.expected_generation == Policy_Generation(0) ||
	   request.expected_generation != state.policy_generation {
		failure = store_failure(state, .Stale_Generation)
		failure.actual = u64(request.expected_generation)
		return {}, false, failure
	}
	if request.cancelled {
		return {}, false, store_failure(state, .Cancelled)
	}
	if valid, policy_failure := policy_validate(request.policy); !valid {
		policy_failure.store_id = state.store_id
		policy_failure.history_id = state.history_id
		policy_failure.buffer_id = state.buffer_id
		policy_failure.revision = state.current_revision
		policy_failure.policy_generation = state.policy_generation
		return {}, false, policy_failure
	}
	if state.policy_generation == Policy_Generation(max(u64)) {
		return {}, false, store_failure(state, .Invalid_State)
	}

	projected_usage := state.usage
	projected_buffer_bytes := state.buffer_retained_bytes
	selected: map[^Node]bool
	projection_failure := policy_projection_failure(
		state,
		request.policy,
		selected,
		projected_usage,
		projected_buffer_bytes,
	)
	if projection_failure.code == .None {
		return policy_activate(state, request.policy, 0), true, {}
	}

	limit := min(request.operation_limit, request.policy.pruning_operations)
	selected_error: runtime.Allocator_Error
	selected, selected_error = make(map[^Node]bool, int(limit), state.temporary_allocator)
	if selected_error != nil {
		return {}, false, store_failure(state, .Temporary_Memory_Limit)
	}
	defer delete(selected)
	selection, selection_error := make([]^Node, int(limit), state.temporary_allocator)
	if selection_error != nil {
		return {}, false, store_failure(state, .Temporary_Memory_Limit)
	}
	defer delete(selection, state.temporary_allocator)

	selected_count := 0
	candidate_cursor := state.creation_head
	for {
		projection_failure = policy_projection_failure(
			state,
			request.policy,
			selected,
			projected_usage,
			projected_buffer_bytes,
		)
		if projection_failure.code == .None {
			break
		}
		if selected_count >= len(selection) {
			return {}, false, projection_failure
		}
		target := policy_projection_target(state, projection_failure.node_id)
		candidate := policy_pruning_candidate(
			state,
			request.policy,
			selected,
			target,
			&candidate_cursor,
		)
		if candidate == nil {
			return {}, false, projection_failure
		}
		selected[candidate] = true
		selection[selected_count] = candidate
		selected_count += 1
		candidate_bytes, candidate_payload := node_accounted_storage(candidate)
		projected_usage.retained_bytes -= candidate_bytes
		projected_usage.retained_nodes -= 1
		projected_usage.retained_records -= u64(len(candidate.records))
		projected_usage.retained_payload_bytes -= candidate_payload
		projected_buffer_bytes -= candidate_bytes
	}

	for node in selection[:selected_count] {
		assert(node.child_count == 0)
		node_detach_leaf(node)
		creation_detach(state, node)
		node_release_accounted(state, node)
	}
	state.usage.pruning_operations += u64(selected_count)
	return policy_activate(state, request.policy, u64(selected_count)), true, {}
}

@(private)
policy_activate :: proc(state: ^Store_State, policy: Policy, pruned_nodes: u64) -> Policy_Replacement_Result {
	previous_generation := state.policy_generation
	state.policy = policy
	state.policy_generation = Policy_Generation(u64(previous_generation) + 1)
	return Policy_Replacement_Result {
		previous_generation = previous_generation,
		policy_generation = state.policy_generation,
		pruned_nodes = pruned_nodes,
		usage = state.usage,
	}
}

@(private)
policy_projection_failure :: proc(
	state: ^Store_State,
	policy: Policy,
	selected: map[^Node]bool,
	usage: Resource_Usage,
	buffer_bytes: u64,
) -> Failure_Context {
	if usage.retained_bytes > policy.global_retained_bytes {
		return policy_retention_failure(state, .Global_Retained_Bytes, policy.global_retained_bytes, usage.retained_bytes)
	}
	if buffer_bytes > policy.buffer_retained_bytes {
		return policy_retention_failure(state, .Buffer_Retained_Bytes, policy.buffer_retained_bytes, buffer_bytes)
	}
	if usage.retained_nodes > policy.global_nodes {
		return policy_retention_failure(state, .Global_Nodes, policy.global_nodes, usage.retained_nodes)
	}
	if usage.retained_nodes > policy.buffer_nodes {
		return policy_retention_failure(state, .Buffer_Nodes, policy.buffer_nodes, usage.retained_nodes)
	}
	for node := state.creation_head; node != nil; node = node.creation_next {
		if selected[node] {
			continue
		}
		if node.depth > policy.retained_depth {
			failure := policy_retention_failure(state, .Retained_Depth, policy.retained_depth, node.depth)
			failure.node_id = node.id
			return failure
		}
		remaining_children := u64(0)
		for child := node.first_child; child != nil; child = child.next_sibling {
			if !selected[child] {
				remaining_children += 1
			}
		}
		if remaining_children > policy.sibling_branches {
			failure := policy_retention_failure(state, .Sibling_Branches, policy.sibling_branches, remaining_children)
			failure.node_id = node.id
			return failure
		}
		if u64(len(node.records)) > policy.records_per_unit {
			failure := policy_retention_failure(state, .Records_Per_Unit, policy.records_per_unit, u64(len(node.records)))
			failure.node_id = node.id
			return failure
		}
		payload := node_payload_bytes(node)
		if payload > policy.payload_bytes_per_unit {
			failure := policy_retention_failure(state, .Payload_Bytes_Per_Unit, policy.payload_bytes_per_unit, payload)
			failure.node_id = node.id
			return failure
		}
	}
	return {}
}

@(private)
policy_pruning_candidate :: proc(
	state: ^Store_State,
	policy: Policy,
	selected: map[^Node]bool,
	target: ^Node,
	candidate_cursor: ^^Node,
) -> ^Node {
	assert(candidate_cursor != nil)
	protected_order := u64(0)
	if state.next_creation_order > policy.guaranteed_recent_units {
		protected_order = state.next_creation_order - policy.guaranteed_recent_units
	}
	first := state.creation_head
	if target == nil && candidate_cursor^ != nil {
		first = candidate_cursor^
	}
	for node := first; node != nil; node = node.creation_next {
		if selected[node] || node == state.root || node == state.active ||
		   node.link != nil ||
		   node.creation_order >= protected_order ||
		   target != nil && !node_is_descendant_or_self(node, target) {
			continue
		}
		remaining_children := u64(0)
		for child := node.first_child; child != nil; child = child.next_sibling {
			if !selected[child] {
				remaining_children += 1
			}
		}
		if remaining_children == 0 {
			candidate_cursor^ = node.creation_next
			return node
		}
	}
	return nil
}

@(private)
policy_projection_target :: proc(state: ^Store_State, id: Node_ID) -> ^Node {
	if !node_id_is_valid(id) {
		return nil
	}
	for node := state.creation_head; node != nil; node = node.creation_next {
		if node.id == id {
			return node
		}
	}
	return nil
}

@(private)
node_is_descendant_or_self :: proc(node, ancestor: ^Node) -> bool {
	for current := node; current != nil; current = current.parent {
		if current == ancestor {
			return true
		}
	}
	return false
}

@(private)
policy_retention_failure :: proc(
	state: ^Store_State,
	field: Policy_Field,
	maximum, actual: u64,
) -> Failure_Context {
	failure := store_failure(state, .Policy_Retention_Blocked)
	failure.field = field
	failure.maximum = maximum
	failure.actual = actual
	return failure
}
