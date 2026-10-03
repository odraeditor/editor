// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package history

import "base:runtime"

/*
store_inspect copies the active node's immediate retained alternatives within
the caller's explicit result and traversal ceilings. The returned strings and
slice belong to destination_allocator until inspection_release is called.
*/
store_inspect :: proc(
	store: ^Store,
	request: Inspection_Request,
	destination_allocator: runtime.Allocator,
) -> (inspection: Inspection, ok: bool, failure: Failure_Context) {
	state, state_failure := store_live_state(store)
	if state_failure.code != .None {
		return {}, false, state_failure
	}
	if state.pending_reservation {
		return {}, false, store_failure(state, .Invalid_State)
	}
	if destination_allocator.procedure == nil {
		return {}, false, store_failure(state, .Temporary_Memory_Limit)
	}
	if request.buffer_id != state.buffer_id {
		return {}, false, store_failure(state, .Wrong_Buffer)
	}
	if request.current_revision != state.current_revision {
		return {}, false, store_revision_failure(state, request.current_revision)
	}
	if !node_id_is_valid(request.active_node) {
		return {}, false, store_failure(state, .Invalid_Identity)
	}
	if request.active_node != state.active.id ||
	   request.policy_generation != state.policy_generation {
		failure = store_failure(state, .Stale_Generation)
		failure.node_id = request.active_node
		failure.actual = u64(request.policy_generation)
		return {}, false, failure
	}
	if request.result_limit == 0 || request.result_limit > state.policy.inspection_nodes {
		return {}, false, store_limit_failure(
			state,
			.Inspection_Limit,
			state.policy.inspection_nodes,
			request.result_limit,
		)
	}
	if request.traversal_limit == 0 || request.traversal_limit > state.policy.inspection_nodes {
		return {}, false, store_limit_failure(
			state,
			.Work_Limit,
			state.policy.inspection_nodes,
			request.traversal_limit,
		)
	}

	copy_count := min(state.active.child_count, request.result_limit, request.traversal_limit)
	children: []Node_Projection
	if copy_count > 0 {
		allocation_error: runtime.Allocator_Error
		children, allocation_error = make([]Node_Projection, int(copy_count), destination_allocator)
		if allocation_error != nil {
			return {}, false, store_failure(state, .Temporary_Memory_Limit)
		}
	}
	child := state.active.first_child
	for index in 0 ..< int(copy_count) {
		assert(child != nil)
		projection, projection_ok := node_projection_copy(child, destination_allocator)
		if !projection_ok {
			inspection_children_release(children[:index], destination_allocator)
			delete(children, destination_allocator)
			return {}, false, store_failure(state, .Temporary_Memory_Limit)
		}
		children[index] = projection
		child = child.next_sibling
	}
	parent := Node_ID{}
	if state.active.parent != nil {
		parent = state.active.parent.id
	}
	preferred := Node_ID{}
	if state.active.preferred_child != nil {
		preferred = state.active.preferred_child.id
	}
	active_projection, active_ok := node_projection_copy(state.active, destination_allocator)
	if !active_ok {
		inspection_children_release(children, destination_allocator)
		delete(children, destination_allocator)
		return {}, false, store_failure(state, .Temporary_Memory_Limit)
	}
	parent_projection: Node_Projection
	if state.active.parent != nil {
		parent_ok: bool
		parent_projection, parent_ok = node_projection_copy(state.active.parent, destination_allocator)
		if !parent_ok {
			delete_string(active_projection.command, destination_allocator)
			inspection_children_release(children, destination_allocator)
			delete(children, destination_allocator)
			return {}, false, store_failure(state, .Temporary_Memory_Limit)
		}
	}
	preferred_projection: Node_Projection
	if state.active.preferred_child != nil {
		preferred_ok: bool
		preferred_projection, preferred_ok = node_projection_copy(state.active.preferred_child, destination_allocator)
		if !preferred_ok {
			delete_string(parent_projection.command, destination_allocator)
			delete_string(active_projection.command, destination_allocator)
			inspection_children_release(children, destination_allocator)
			delete(children, destination_allocator)
			return {}, false, store_failure(state, .Temporary_Memory_Limit)
		}
	}
	return Inspection {
		active = state.active.id,
		parent = parent,
		preferred_child = preferred,
		active_projection = active_projection,
		parent_projection = parent_projection,
		preferred_projection = preferred_projection,
		has_parent = state.active.parent != nil,
		has_preferred_child = state.active.preferred_child != nil,
		children = children,
		child_count = state.active.child_count,
		traversed_nodes = copy_count,
		truncated = copy_count < state.active.child_count,
		policy_generation = state.policy_generation,
	}, true, {}
}

/* inspection_release releases one caller-owned inspection projection. */
inspection_release :: proc(inspection: ^Inspection, allocator: runtime.Allocator) {
	if inspection == nil {
		return
	}
	delete_string(inspection.active_projection.command, allocator)
	delete_string(inspection.parent_projection.command, allocator)
	delete_string(inspection.preferred_projection.command, allocator)
	inspection_children_release(inspection.children, allocator)
	if inspection.children != nil {
		delete(inspection.children, allocator)
	}
	inspection^ = {}
}

@(private)
node_projection_copy :: proc(node: ^Node, allocator: runtime.Allocator) -> (Node_Projection, bool) {
	assert(node != nil)
	parent := Node_ID{}
	if node.parent != nil {
		parent = node.parent.id
	}
	preferred := Node_ID{}
	if node.preferred_child != nil {
		preferred = node.preferred_child.id
	}
	command := ""
	if len(node.records) > 0 {
		last := node.records[len(node.records) - 1]
		if last != nil {
			command = last.command
		}
	}
	owned_command, command_error := clone_string(command, allocator)
	if command_error != nil {
		return {}, false
	}
	retained_bytes := u64(size_of(Node))
	payload_bytes := u64(0)
	if len(node.records) > 0 {
		retained_bytes, payload_bytes = node_accounted_storage(node)
	}
	return Node_Projection {
		id = node.id,
		unit_id = node.unit_id,
		parent = parent,
		preferred_child = preferred,
		command = owned_command,
		creation_order = node.creation_order,
		retained_bytes = retained_bytes,
		record_count = u64(len(node.records)),
		payload_bytes = payload_bytes,
		depth = node.depth,
		child_count = node.child_count,
	}, true
}

@(private)
inspection_children_release :: proc(children: []Node_Projection, allocator: runtime.Allocator) {
	for child in children {
		delete_string(child.command, allocator)
	}
}
