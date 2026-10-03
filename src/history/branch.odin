// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package history

import "../editor"

@(private)
branch_navigation_prepare :: proc(
	state: ^Store_State,
	request: Navigation_Request,
) -> (plan: Navigation_Plan, result: Navigation_Result, ok: bool, failure: Failure_Context) {
	assert(state != nil && request.kind == .Select_Branch)
	if !node_id_is_valid(request.active_node) || !node_id_is_valid(request.target_node) {
		return {}, {}, false, store_failure(state, .Invalid_Identity)
	}
	if request.active_node != state.active.id ||
	   request.policy_generation != state.policy_generation {
		failure = store_failure(state, .Stale_Generation)
		failure.node_id = request.active_node
		failure.actual = u64(request.policy_generation)
		return {}, {}, false, failure
	}
	if request.target_node.history_id != state.history_id {
		failure = store_failure(state, .Invalid_Identity)
		failure.node_id = request.target_node
		return {}, {}, false, failure
	}
	if request.analysis_operations == 0 ||
	   request.analysis_operations > state.policy.inspection_nodes {
		return {}, {}, false, store_limit_failure(
			state,
			.Work_Limit,
			state.policy.inspection_nodes,
			request.analysis_operations,
		)
	}
	if request.target_node == state.active.id {
		return {}, Navigation_Result {
			outcome = .Already_Active,
			active_node = state.active.id,
			result_revision = state.current_revision,
			policy_generation = state.policy_generation,
		}, true, {}
	}

	limit := request.analysis_operations
	used := u64(0)
	target, target_ok, target_failure := branch_target_find(state, request.target_node, &used, limit)
	if !target_ok {
		return {}, {}, false, target_failure
	}
	lca, lca_ok := branch_lca_find(state.active, target, &used, limit)
	if !lca_ok {
		return {}, {}, false, branch_work_failure(state, request.target_node, limit, used + 1)
	}

	up_count := state.active.depth - lca.depth
	down_count := target.depth - lca.depth
	path_count, path_ok := checked_add_u64(up_count, down_count)
	if !path_ok || path_count == 0 || path_count >= u64(max(int)) {
		return {}, {}, false, branch_work_failure(state, request.target_node, limit, max(u64))
	}
	path_count += 1
	path, path_error := make([]^Node, int(path_count), state.temporary_allocator)
	if path_error != nil {
		return {}, {}, false, store_failure(state, .Temporary_Memory_Limit)
	}
	pivot := int(up_count)
	branch_path_fill(path, pivot, state.active, lca, target)

	edit_count := u64(0)
	for index in 0 ..< len(path) {
		if index == pivot {
			continue
		}
		node := path[index]
		if node == nil || len(node.records) == 0 {
			delete(path, state.temporary_allocator)
			return {}, {}, false, store_failure(state, .Missing_Payload)
		}
		for record in node.records {
			if record == nil {
				delete(path, state.temporary_allocator)
				return {}, {}, false, store_failure(state, .Missing_Payload)
			}
			if !branch_work_consume(&used, limit, u64(len(record.edits))) {
				delete(path, state.temporary_allocator)
				return {}, {}, false, branch_work_failure(state, request.target_node, limit, used + u64(len(record.edits)))
			}
			count_ok: bool
			edit_count, count_ok = checked_add_u64(edit_count, u64(len(record.edits)))
			if !count_ok || edit_count > u64(max(int)) {
				delete(path, state.temporary_allocator)
				return {}, {}, false, branch_work_failure(state, request.target_node, limit, max(u64))
			}
		}
	}
	edits, edit_error := make([]Navigation_Edit, int(edit_count), state.temporary_allocator)
	if edit_error != nil {
		delete(path, state.temporary_allocator)
		return {}, {}, false, store_failure(state, .Temporary_Memory_Limit)
	}
	if !branch_edits_prepare(edits, path, pivot) {
		delete(edits, state.temporary_allocator)
		delete(path, state.temporary_allocator)
		return {}, {}, false, store_failure(state, .Missing_Payload)
	}
	reserved, reservation_error := new(Reservation_State, state.temporary_allocator)
	if reservation_error != nil {
		delete(edits, state.temporary_allocator)
		delete(path, state.temporary_allocator)
		return {}, {}, false, store_failure(state, .Temporary_Memory_Limit)
	}
	reserved.kind = .Navigation
	reserved.store = state
	reserved.source_node = state.active
	reserved.target_node = target
	reserved.navigation_kind = .Select_Branch
	reserved.navigation_edits = edits
	reserved.navigation_path = path
	reserved.navigation_pivot = pivot
	reserved.expected_revision = editor.Revision(u64(state.current_revision) + 1)
	state.pending_reservation = true
	plan = Navigation_Plan {
		reservation = Reservation{state = reserved},
		kind = .Select_Branch,
		source_node = state.active.id,
		target_node = target.id,
		edits = edits,
		cursor = branch_cursor_restore(path, pivot),
	}
	return plan, Navigation_Result {
		outcome = .Applied,
		active_node = state.active.id,
		result_revision = state.current_revision,
		policy_generation = state.policy_generation,
	}, true, {}
}

@(private)
branch_target_find :: proc(
	state: ^Store_State,
	target_id: Node_ID,
	used: ^u64,
	limit: u64,
) -> (^Node, bool, Failure_Context) {
	child := state.active.first_child
	for child != nil {
		if !branch_work_consume(used, limit, 1) {
			return nil, false, branch_work_failure(state, target_id, limit, used^ + 1)
		}
		if child.id == target_id {
			return child, true, {}
		}
		child = child.next_sibling
	}
	node := state.creation_head
	for node != nil {
		if !branch_work_consume(used, limit, 1) {
			return nil, false, branch_work_failure(state, target_id, limit, used^ + 1)
		}
		if node.id == target_id {
			return node, true, {}
		}
		node = node.creation_next
	}
	failure := store_failure(state, .Stale_Generation)
	failure.node_id = target_id
	return nil, false, failure
}

@(private)
branch_lca_find :: proc(source, target: ^Node, used: ^u64, limit: u64) -> (^Node, bool) {
	left := source
	right := target
	for left.depth > right.depth {
		if !branch_work_consume(used, limit, 1) {
			return nil, false
		}
		left = left.parent
	}
	for right.depth > left.depth {
		if !branch_work_consume(used, limit, 1) {
			return nil, false
		}
		right = right.parent
	}
	for left != right {
		if !branch_work_consume(used, limit, 2) {
			return nil, false
		}
		left = left.parent
		right = right.parent
	}
	return left, true
}

@(private)
branch_path_fill :: proc(path: []^Node, pivot: int, source, lca, target: ^Node) {
	node := source
	for index in 0 ..= pivot {
		path[index] = node
		if node == lca {
			break
		}
		node = node.parent
	}
	node = target
	index := len(path) - 1
	for node != lca {
		path[index] = node
		index -= 1
		node = node.parent
	}
}

@(private)
branch_edits_prepare :: proc(destination: []Navigation_Edit, path: []^Node, pivot: int) -> bool {
	offset := 0
	for index in 0 ..< pivot {
		node := path[index]
		count := node_edit_count(node)
		segment := destination[offset:offset + count]
		if !navigation_unit_edits_prepare(segment, node.records, .Undo) {
			return false
		}
		offset += count
	}
	for index in pivot + 1 ..< len(path) {
		node := path[index]
		count := node_edit_count(node)
		segment := destination[offset:offset + count]
		if !navigation_unit_edits_prepare(segment, node.records, .Redo) {
			return false
		}
		offset += count
	}
	return offset == len(destination)
}

@(private)
node_edit_count :: proc(node: ^Node) -> int {
	count := 0
	for record in node.records {
		count += len(record.edits)
	}
	return count
}

@(private)
branch_cursor_restore :: proc(path: []^Node, pivot: int) -> Cursor_Restore {
	if pivot < len(path) - 1 {
		return navigation_cursor_restore(path[len(path) - 1].records, .Redo)
	}
	return navigation_cursor_restore(path[pivot - 1].records, .Undo)
}

@(private)
branch_work_consume :: proc(used: ^u64, limit, amount: u64) -> bool {
	next, ok := checked_add_u64(used^, amount)
	if !ok || next > limit {
		return false
	}
	used^ = next
	return true
}

@(private)
branch_work_failure :: proc(state: ^Store_State, node_id: Node_ID, limit, actual: u64) -> Failure_Context {
	failure := store_limit_failure(state, .Work_Limit, limit, actual)
	failure.node_id = node_id
	return failure
}
