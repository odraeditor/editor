// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package history

import "base:runtime"
import "../editor"

@(private)
Selective_Plan_State :: struct {
	allocator: runtime.Allocator,
}

/*
selective_prepare proves that one retained ancestor unit can be reversed while
all later retained work remains valid. Replacement text is copied into the
plan, and no store state changes until an ordinary transaction publishes it.
*/
selective_prepare :: proc(
	store: ^Store,
	request: Selective_Request,
) -> (plan: Selective_Plan, ok: bool, failure: Failure_Context) {
	state, state_failure := store_live_state(store)
	if state_failure.code != .None {
		return {}, false, state_failure
	}
	if state.pending_reservation {
		return {}, false, store_failure(state, .Invalid_State)
	}
	if request.cancelled {
		return {}, false, store_failure(state, .Cancelled)
	}
	if request.buffer_id != state.buffer_id {
		return {}, false, store_failure(state, .Wrong_Buffer)
	}
	if request.current_revision != state.current_revision {
		return {}, false, store_revision_failure(state, request.current_revision)
	}
	if !node_id_is_valid(request.active_node) || request.target_unit == Unit_ID(0) {
		return {}, false, store_failure(state, .Invalid_Identity)
	}
	if request.active_node != state.active.id ||
	   request.policy_generation != state.policy_generation {
		failure = store_failure(state, .Stale_Generation)
		failure.node_id = request.active_node
		failure.actual = u64(request.policy_generation)
		return {}, false, failure
	}
	if request.analysis_operations == 0 ||
	   request.analysis_operations > state.policy.selective_operations {
		return {}, false, store_limit_failure(
			state,
			.Work_Limit,
			state.policy.selective_operations,
			request.analysis_operations,
		)
	}
	if request.range.present &&
	   (request.range.revision != state.current_revision || request.range.start > request.range.end) {
		return {}, false, store_revision_failure(state, request.range.revision)
	}

	used := u64(0)
	target := state.active
	for target != state.root && target.unit_id != request.target_unit {
		if !selective_work_consume(&used, request.analysis_operations, 1) {
			return {}, false, selective_work_failure(state, request.target_unit, request.analysis_operations, used + 1)
		}
		target = target.parent
	}
	if target == state.root || target.unit_id != request.target_unit {
		failure = store_failure(state, .Stale_Generation)
		failure.actual = u64(request.target_unit)
		return {}, false, failure
	}
	if len(target.records) == 0 {
		return {}, false, store_failure(state, .Missing_Payload)
	}

	later_count := int(state.active.depth - target.depth)
	later_nodes: []^Node
	if later_count > 0 {
		later_error: runtime.Allocator_Error
		later_nodes, later_error = make([]^Node, later_count, state.temporary_allocator)
		if later_error != nil {
			return {}, false, store_failure(state, .Temporary_Memory_Limit)
		}
		node := state.active
		for index := later_count - 1; index >= 0; index -= 1 {
			later_nodes[index] = node
			node = node.parent
		}
	}

	inverse_count := node_edit_count(target)
	if inverse_count == 0 {
		delete(later_nodes, state.temporary_allocator)
		return {}, false, store_failure(state, .Missing_Payload)
	}
	inverse, inverse_error := make([]Navigation_Edit, inverse_count, state.temporary_allocator)
	if inverse_error != nil {
		delete(later_nodes, state.temporary_allocator)
		return {}, false, store_failure(state, .Temporary_Memory_Limit)
	}
	if !navigation_unit_edits_prepare(inverse, target.records, .Undo) {
		delete(inverse, state.temporary_allocator)
		delete(later_nodes, state.temporary_allocator)
		return {}, false, store_failure(state, .Missing_Payload)
	}
	for &edit in inverse {
		if !selective_work_consume(&used, request.analysis_operations, 1) {
			delete(inverse, state.temporary_allocator)
			delete(later_nodes, state.temporary_allocator)
			return {}, false, selective_work_failure(state, request.target_unit, request.analysis_operations, used + 1)
		}
		for later in later_nodes {
			for record in later.records {
				if record == nil {
					delete(inverse, state.temporary_allocator)
					delete(later_nodes, state.temporary_allocator)
					return {}, false, store_failure(state, .Missing_Payload)
				}
				if !selective_work_consume(&used, request.analysis_operations, u64(len(record.edits))) {
					delete(inverse, state.temporary_allocator)
					delete(later_nodes, state.temporary_allocator)
					return {}, false, selective_work_failure(
						state,
						request.target_unit,
						request.analysis_operations,
						used + u64(len(record.edits)),
					)
				}
				transformed, conflict := selective_edit_transform(edit, record.edits)
				if conflict {
					delete(inverse, state.temporary_allocator)
					delete(later_nodes, state.temporary_allocator)
					failure = store_failure(state, .Dependency_Conflict)
					failure.node_id = target.id
					return {}, false, failure
				}
				edit = transformed
			}
		}
	}
	delete(later_nodes, state.temporary_allocator)

	selected_count := 0
	for edit in inverse {
		included, partial := selective_range_classify(edit, request.range)
		if partial {
			delete(inverse, state.temporary_allocator)
			failure = store_failure(state, .Dependency_Conflict)
			failure.node_id = target.id
			return {}, false, failure
		}
		if included {
			selected_count += 1
		}
	}
	if selected_count == 0 {
		delete(inverse, state.temporary_allocator)
		failure = store_failure(state, .Dependency_Conflict)
		failure.node_id = target.id
		return {}, false, failure
	}
	edits, edits_error := make([]Navigation_Edit, selected_count, state.temporary_allocator)
	if edits_error != nil {
		delete(inverse, state.temporary_allocator)
		return {}, false, store_failure(state, .Temporary_Memory_Limit)
	}
	output := 0
	for edit in inverse {
		included, _ := selective_range_classify(edit, request.range)
		if !included {
			continue
		}
		replacement, replacement_error := clone_string(edit.replacement, state.temporary_allocator)
		if replacement_error != nil {
			selective_edits_release(edits[:output], state.temporary_allocator)
			delete(edits, state.temporary_allocator)
			delete(inverse, state.temporary_allocator)
			return {}, false, store_failure(state, .Temporary_Memory_Limit)
		}
		edits[output] = Navigation_Edit {
			start = edit.start,
			end = edit.end,
			replacement = replacement,
		}
		output += 1
	}
	delete(inverse, state.temporary_allocator)
	plan_state, plan_error := new(Selective_Plan_State, state.temporary_allocator)
	if plan_error != nil {
		selective_edits_release(edits, state.temporary_allocator)
		delete(edits, state.temporary_allocator)
		return {}, false, store_failure(state, .Temporary_Memory_Limit)
	}
	plan_state.allocator = state.temporary_allocator
	return Selective_Plan {
		state = plan_state,
		target_node = target.id,
		target_unit = target.unit_id,
		edits = edits,
		analysis_operations = used,
	}, true, {}
}

/* selective_plan_release releases copied compensating text without changing history. */
selective_plan_release :: proc(plan: ^Selective_Plan) {
	if plan == nil || plan.state == nil {
		return
	}
	state := (^Selective_Plan_State)(plan.state)
	selective_edits_release(plan.edits, state.allocator)
	if plan.edits != nil {
		delete(plan.edits, state.allocator)
	}
	allocator := state.allocator
	plan^ = {}
	free(state, allocator)
}

@(private)
selective_edit_transform :: proc(
	edit: Navigation_Edit,
	later: []Stored_Edit,
) -> (Navigation_Edit, bool) {
	start := u64(edit.start)
	end := u64(edit.end)
	inserted_before := u64(0)
	removed_before := u64(0)
	for change in later {
		change_start := u64(change.start)
		change_end := u64(change.end)
		if start == end && change_start == start && change_end == start {
			return {}, true
		}
		if change_end <= start {
			inserted_ok, removed_ok: bool
			inserted_before, inserted_ok = checked_add_u64(inserted_before, u64(len(change.replacement_text)))
			removed_before, removed_ok = checked_add_u64(removed_before, change_end - change_start)
			if !inserted_ok || !removed_ok {
				return {}, true
			}
			continue
		}
		if change_start >= end {
			continue
		}
		return {}, true
	}
	shifted_start, start_ok := checked_add_u64(start, inserted_before)
	shifted_end, end_ok := checked_add_u64(end, inserted_before)
	if !start_ok || !end_ok || shifted_start < removed_before || shifted_end < removed_before {
		return {}, true
	}
	transformed := edit
	transformed.start = editor.Byte_Offset(shifted_start - removed_before)
	transformed.end = editor.Byte_Offset(shifted_end - removed_before)
	return transformed, false
}

@(private)
selective_range_classify :: proc(edit: Navigation_Edit, selected: Selective_Range) -> (included, partial: bool) {
	if !selected.present {
		return true, false
	}
	if edit.start == edit.end {
		return edit.start >= selected.start && edit.start < selected.end, false
	}
	if edit.end <= selected.start || edit.start >= selected.end {
		return false, false
	}
	if edit.start >= selected.start && edit.end <= selected.end {
		return true, false
	}
	return false, true
}

@(private)
selective_edits_release :: proc(edits: []Navigation_Edit, allocator: runtime.Allocator) {
	for edit in edits {
		delete_string(edit.replacement, allocator)
	}
}

@(private)
selective_work_consume :: proc(used: ^u64, limit, amount: u64) -> bool {
	next, ok := checked_add_u64(used^, amount)
	if !ok || next > limit {
		return false
	}
	used^ = next
	return true
}

@(private)
selective_work_failure :: proc(
	state: ^Store_State,
	unit_id: Unit_ID,
	limit, actual: u64,
) -> Failure_Context {
	failure := store_limit_failure(state, .Work_Limit, limit, actual)
	failure.actual = actual
	failure.node_id = Node_ID{history_id = state.history_id, slot = u64(unit_id), generation = 1}
	return failure
}
