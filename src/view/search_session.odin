// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package view

import "../editor"
import "../search"

/*
search_session_publish consumes query and result on success and publishes one complete
incremental-search state transition without retaining borrowed search data.
*/
search_session_publish :: proc(
	registry: ^Registry,
	handle: View_Handle,
	update: Search_Update,
	query: ^search.Query,
	result: ^search.Result,
) -> (ok: bool, failure: Failure_Context) {
	slot, slot_failure := resolve(registry, handle)
	if slot_failure.code != .None {
		return false, slot_failure
	}
	if slot.active_preparation || slot.state_generation == max(u64) ||
	   slot.query_replacement_session.active {
		return false, mutation_failure(registry, handle, slot)
	}
	query_view, query_ok, query_failure := search.query_view(query)
	if !query_ok ||
	   (query_view.kind != .Literal && query_view.kind != .Regular_Expression) {
		if query_failure.code == .None {
			query_failure.code = .Invalid_Pattern_Kind
		}
		return false, search_failure_context(registry, handle, query_failure)
	}
	result_view, result_ok, result_failure := search.result_view(result)
	if !result_ok {
		return false, search_failure_context(registry, handle, result_failure)
	}
	stats, stats_ok, stats_failure := editor.buffer_stats(slot.buffer)
	if !stats_ok {
		return false, editor_failure_context(registry, handle, stats_failure)
	}
	if update.interaction_generation == 0 ||
	   update.policy_generation == search.Policy_Generation(0) || update.direction == .Invalid ||
	   update.scope.buffer_id != slot.buffer_id || update.scope.buffer_id != stats.buffer_id ||
	   update.scope.revision != stats.revision || result_view.scope != update.scope ||
	   result_view.outcome == .Invalid || result_view.outcome == .Cancelled {
		return false, view_failure(registry, handle, .Invalid_Search_Session)
	}
	if slot.search_session.active {
		if update.interaction_generation != slot.search_session.interaction_generation + 1 ||
		   (update.policy_generation != slot.search_session.policy_generation &&
		    update.policy_generation != slot.search_session.policy_generation + 1) ||
		   slot.search_session.source_revision != stats.revision {
			return false, view_failure(registry, handle, .Stale_Search)
		}
	} else if update.interaction_generation != 1 {
		return false, view_failure(registry, handle, .Invalid_Search_Session)
	}
	if !search_result_is_valid(result_view, update.scope) {
		return false, view_failure(registry, handle, .Invalid_Search_Session)
	}

	new_successful_query: []byte
	if result_view.outcome == .Matched {
		new_successful_query, _ = make(
			[]byte,
			len(query_view.pattern),
			registry_data(registry).allocator,
		)
		if new_successful_query == nil && len(query_view.pattern) > 0 {
			return false, view_failure(registry, handle, .Persistent_Memory_Limit)
		}
		copy(new_successful_query, query_view.pattern)
	}

	created_origins := false
	if !slot.search_session.active {
		origins_ok, origins_failure := search_session_create_origins(slot)
		if !origins_ok {
			delete(new_successful_query, registry_data(registry).allocator)
			return false, editor_failure_context(registry, handle, origins_failure)
		}
		created_origins = true
	}
	if result_view.outcome == .Matched {
		current := result_view.occurrences[result_view.current_index]
		target_offset := current.end
		if update.direction == .Backward {
			target_offset = current.start
		}
		position, position_ok, position_failure := editor.buffer_position(slot.buffer, target_offset)
		if !position_ok {
			if created_origins {
				search_session_release_origins(slot)
			}
			delete(new_successful_query, registry_data(registry).allocator)
			return false, editor_failure_context(registry, handle, position_failure)
		}
		moved, move_failure := editor.buffer_selection_set_point(slot.buffer, position)
		if !moved {
			if created_origins {
				search_session_release_origins(slot)
			}
			delete(new_successful_query, registry_data(registry).allocator)
			return false, editor_failure_context(registry, handle, move_failure)
		}
		stored, stored_failure := editor.buffer_anchor_move(slot.buffer, slot.stored_point, position)
		assert(stored && stored_failure.code == .None)
	}

	allocator := registry_data(registry).allocator
	if slot.search_session.query.state != nil {
		search.query_close(&slot.search_session.query)
	}
	slot.search_session.query = query^
	query^ = {}
	if result_view.outcome == .Matched {
		if slot.search_session.has_match_result {
			search.result_close(&slot.search_session.match_result)
		}
		slot.search_session.match_result = result^
		result^ = {}
		slot.search_session.has_match_result = true
		delete(slot.search_session.last_successful_query, allocator)
		slot.search_session.last_successful_query = new_successful_query
	} else {
		search.result_close(result)
	}
	slot.search_session.active = true
	slot.search_session.interaction_generation = update.interaction_generation
	slot.search_session.policy_generation = update.policy_generation
	slot.search_session.source_revision = stats.revision
	slot.search_session.direction = update.direction
	slot.search_session.scope = update.scope
	slot.search_session.progress = result_view.progress
	slot.search_session.usage = result_view.usage
	slot.search_session.allocator = allocator
	switch result_view.outcome {
	case .Matched:
		slot.search_session.status = .Active
	case .No_Match:
		slot.search_session.status = .Failing
	case .Incomplete:
		slot.search_session.status = .Pending
		if result_view.progress.wrapped {
			slot.search_session.status = .Wrapped
		}
	case .Cancelled, .Invalid:
		unreachable()
	}
	slot.state_generation += 1
	return true, {}
}

/* search_session_accept keeps the selected point and releases all transient state. */
search_session_accept :: proc(
	registry: ^Registry,
	handle: View_Handle,
) -> (ok: bool, failure: Failure_Context) {
	slot, slot_failure := resolve(registry, handle)
	if slot_failure.code != .None {
		return false, slot_failure
	}
	if !slot.search_session.active {
		return false, view_failure(registry, handle, .Invalid_Search_Session)
	}
	if slot.active_preparation || slot.state_generation == max(u64) {
		return false, mutation_failure(registry, handle, slot)
	}
	released, search_failure := search_session_release(slot)
	if !released {
		return false, search_failure_context(registry, handle, search_failure)
	}
	slot.state_generation += 1
	return true, {}
}

/* search_session_presentation_set changes only the projection of one active search. */
search_session_presentation_set :: proc(
	registry: ^Registry,
	handle: View_Handle,
	presentation: Search_Presentation,
) -> (ok: bool, failure: Failure_Context) {
	slot, slot_failure := resolve(registry, handle)
	if slot_failure.code != .None do return false, slot_failure
	if !slot.search_session.active ||
	   (presentation != .Matches && presentation != .Lines) {
		return false, view_failure(registry, handle, .Invalid_Search_Session)
	}
	if slot.active_preparation || slot.state_generation == max(u64) {
		return false, mutation_failure(registry, handle, slot)
	}
	if slot.search_session.presentation == presentation do return true, {}
	slot.search_session.presentation = presentation
	slot.state_generation += 1
	return true, {}
}

/* search_session_recover consumes the last successful query after a failed suffix. */
search_session_recover :: proc(
	registry: ^Registry,
	handle: View_Handle,
	query: ^search.Query,
) -> (ok: bool, failure: Failure_Context) {
	slot, slot_failure := resolve(registry, handle)
	if slot_failure.code != .None {
		return false, slot_failure
	}
	if !slot.search_session.active || slot.search_session.status != .Failing ||
	   len(slot.search_session.last_successful_query) == 0 ||
	   slot.active_preparation || slot.state_generation == max(u64) ||
	   slot.search_session.interaction_generation == max(u64) {
		return false, view_failure(registry, handle, .Invalid_Search_Session)
	}
	query_view, query_ok, query_failure := search.query_view(query)
	if !query_ok {
		return false, search_failure_context(registry, handle, query_failure)
	}
	active_query_view, active_query_ok, _ := search.query_view(&slot.search_session.query)
	if !active_query_ok || query_view.kind != active_query_view.kind ||
	   query_view.pattern != string(slot.search_session.last_successful_query) {
		return false, view_failure(registry, handle, .Invalid_Search_Session)
	}
	if slot.search_session.query.state != nil {
		closed, close_failure := search.query_close(&slot.search_session.query)
		if !closed {
			return false, search_failure_context(registry, handle, close_failure)
		}
	}
	slot.search_session.query = query^
	query^ = {}
	slot.search_session.status = .Active
	slot.search_session.interaction_generation += 1
	slot.state_generation += 1
	return true, {}
}

/* search_session_abort restores buffer/view point and viewport, then releases transient state. */
search_session_abort :: proc(
	registry: ^Registry,
	handle: View_Handle,
) -> (ok: bool, failure: Failure_Context) {
	slot, slot_failure := resolve(registry, handle)
	if slot_failure.code != .None {
		return false, slot_failure
	}
	if !slot.search_session.active {
		return false, view_failure(registry, handle, .Invalid_Search_Session)
	}
	if slot.active_preparation || slot.state_generation == max(u64) {
		return false, mutation_failure(registry, handle, slot)
	}
	origin_point, point_ok, point_failure := editor.buffer_anchor_resolve(
		slot.buffer,
		slot.search_session.origin_point,
	)
	if !point_ok {
		return false, editor_failure_context(registry, handle, point_failure)
	}
	origin_viewport, viewport_ok, viewport_failure := editor.buffer_anchor_resolve(
		slot.buffer,
		slot.search_session.origin_viewport,
	)
	if !viewport_ok {
		return false, editor_failure_context(registry, handle, viewport_failure)
	}
	point_moved, point_move_failure := editor.buffer_selection_set_point(slot.buffer, origin_point)
	if !point_moved {
		return false, editor_failure_context(registry, handle, point_move_failure)
	}
	stored, stored_failure := editor.buffer_anchor_move(
		slot.buffer,
		slot.stored_point,
		origin_point,
	)
	assert(stored && stored_failure.code == .None)
	viewport_moved, viewport_move_failure := editor.buffer_anchor_move(
		slot.buffer,
		slot.viewport_origin,
		origin_viewport,
	)
	assert(viewport_moved && viewport_move_failure.code == .None)
	slot.horizontal_display_column = slot.search_session.origin_horizontal_column
	released, search_failure := search_session_release(slot)
	if !released {
		return false, search_failure_context(registry, handle, search_failure)
	}
	slot.state_generation += 1
	return true, {}
}

/* search_session_view borrows active session values until the next view operation or close. */
search_session_view :: proc(
	registry: ^Registry,
	handle: View_Handle,
) -> (Search_Snapshot, bool, Failure_Context) {
	slot, slot_failure := resolve(registry, handle)
	if slot_failure.code != .None {
		return {}, false, slot_failure
	}
	if !slot.search_session.active {
		return {}, true, {}
	}
	query_view, query_ok, query_failure := search.query_view(&slot.search_session.query)
	if !query_ok {
		return {}, false, search_failure_context(registry, handle, query_failure)
	}
	origin_point, origin_ok, origin_failure := editor.buffer_anchor_resolve(
		slot.buffer,
		slot.search_session.origin_point,
	)
	if !origin_ok {
		return {}, false, editor_failure_context(registry, handle, origin_failure)
	}
	snapshot := Search_Snapshot {
		present = true,
		interaction_generation = slot.search_session.interaction_generation,
		policy_generation = slot.search_session.policy_generation,
		source_revision = slot.search_session.source_revision,
		direction = slot.search_session.direction,
		kind = query_view.kind,
		scope = slot.search_session.scope,
		status = slot.search_session.status,
		presentation = slot.search_session.presentation,
		query = query_view.pattern,
		last_successful_query = string(slot.search_session.last_successful_query),
		policy = query_view.policy,
		limits = query_view.limits,
		origin_point_position = origin_point,
		effective_case = query_view.effective_case,
		progress = slot.search_session.progress,
		usage = slot.search_session.usage,
	}
	if slot.search_session.has_match_result {
		result_view, result_ok, result_failure := search.result_view(&slot.search_session.match_result)
		if !result_ok {
			return {}, false, search_failure_context(registry, handle, result_failure)
		}
		snapshot.has_current = result_view.has_current
		snapshot.current_index = result_view.current_index
		snapshot.occurrences = result_view.occurrences
		snapshot.captures = result_view.captures
	}
	return snapshot, true, {}
}

@(private)
search_session_create_origins :: proc(slot: ^View_Slot) -> (bool, editor.Failure_Context) {
	selection, selection_ok, selection_failure := editor.buffer_selection_snapshot(slot.buffer)
	if !selection_ok {
		return false, selection_failure
	}
	viewport, viewport_ok, viewport_failure := editor.buffer_anchor_resolve(
		slot.buffer,
		slot.viewport_origin,
	)
	if !viewport_ok {
		return false, viewport_failure
	}
	origin_point, created, create_failure := editor.buffer_anchor_create(
		slot.buffer,
		selection.point_position,
		.Left,
		.Collapse,
	)
	if !created {
		return false, create_failure
	}
	origin_viewport, viewport_created, viewport_create_failure := editor.buffer_anchor_create(
		slot.buffer,
		viewport,
		.Left,
		.Collapse,
	)
	if !viewport_created {
		editor.buffer_anchor_release(slot.buffer, &origin_point)
		return false, viewport_create_failure
	}
	slot.search_session.origin_point = origin_point
	slot.search_session.origin_viewport = origin_viewport
	slot.search_session.origin_horizontal_column = slot.horizontal_display_column
	return true, {}
}

@(private)
search_session_release_origins :: proc(slot: ^View_Slot) {
	if slot.search_session.origin_viewport.slot != 0 || slot.search_session.origin_viewport.generation != 0 {
		released, _ := editor.buffer_anchor_release(slot.buffer, &slot.search_session.origin_viewport)
		assert(released)
	}
	if slot.search_session.origin_point.slot != 0 || slot.search_session.origin_point.generation != 0 {
		released, _ := editor.buffer_anchor_release(slot.buffer, &slot.search_session.origin_point)
		assert(released)
	}
}

@(private)
search_session_release :: proc(slot: ^View_Slot) -> (bool, search.Failure) {
	if slot == nil || !slot.search_session.active {
		return true, {}
	}
	search_session_release_origins(slot)
	if slot.search_session.has_match_result {
		closed, close_failure := search.result_close(&slot.search_session.match_result)
		if !closed {
			return false, close_failure
		}
	}
	if slot.search_session.query.state != nil {
		closed, close_failure := search.query_close(&slot.search_session.query)
		if !closed {
			return false, close_failure
		}
	}
	delete(slot.search_session.last_successful_query, slot.search_session.allocator)
	slot.search_session = {}
	return true, {}
}

@(private)
search_result_is_valid :: proc(result: search.Result_View, scope: search.Scope) -> bool {
	if result.has_current && int(result.current_index) >= len(result.occurrences) {
		return false
	}
	for occurrence in result.occurrences {
		if occurrence.buffer_id != scope.buffer_id || occurrence.revision != scope.revision ||
		   occurrence.start < scope.start || occurrence.end > scope.end ||
		   occurrence.start > occurrence.end {
			return false
		}
	}
	return true
}
