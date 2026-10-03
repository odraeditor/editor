// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package view

import "../editor"
import "../search"

/*
query_replacement_session_publish consumes admitted search owners on success and
publishes one complete progressive-replacement state transition.
*/
query_replacement_session_publish :: proc(
	registry: ^Registry,
	handle: View_Handle,
	update: Query_Replacement_Update,
	query: ^search.Query,
	template: ^search.Replacement_Template,
	result: ^search.Result,
) -> (ok: bool, failure: Failure_Context) {
	slot, slot_failure := resolve(registry, handle)
	if slot_failure.code != .None {
		return false, slot_failure
	}
	if slot.active_preparation || slot.state_generation == max(u64) ||
	   slot.search_session.active {
		return false, query_replacement_failure(registry, handle, .Invalid_Query_Replacement_Session)
	}
	query_view, query_ok, query_failure := search.query_view(query)
	if !query_ok {
		return false, search_failure_context(registry, handle, query_failure)
	}
	template_view, template_ok, template_failure := search.replacement_template_view(template)
	if !template_ok {
		return false, search_failure_context(registry, handle, template_failure)
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
	   update.policy_generation == search.Policy_Generation(0) ||
	   (update.direction != .Forward && update.direction != .Backward) ||
	   update.semantic_group == Query_Replacement_Group_ID(0) ||
	   query_view.kind == .Invalid || template_view.query_id != query_view.id ||
	   template_view.pattern_kind != query_view.kind ||
	   update.scope.buffer_id != slot.buffer_id || update.scope.buffer_id != stats.buffer_id ||
	   update.scope.revision != stats.revision || result_view.scope != update.scope ||
	   !query_replacement_scope_is_valid(update.scope, stats.text_bytes) ||
	   !search_result_is_valid(result_view, update.scope) ||
	   result_view.outcome == .Invalid || result_view.outcome == .Cancelled {
		return false, query_replacement_failure(registry, handle, .Invalid_Query_Replacement_Session)
	}
	active := slot.query_replacement_session.active
	if !query_replacement_transition_is_valid(
		&slot.query_replacement_session,
		update,
		query_view,
		template_view,
		stats.revision,
		stats.text_bytes,
	) {
		code := Failure_Code.Invalid_Query_Replacement_Session
		if active {
			code = .Stale_Query_Replacement
		}
		return false, query_replacement_failure(registry, handle, code)
	}
	query_kind := query_view.kind
	query_policy := query_view.policy
	query_limits := query_view.limits
	replacement_policy := template_view.policy
	replacement_limits := template_view.limits
	effective_case := query_view.effective_case
	result_outcome := result_view.outcome
	result_progress := result_view.progress

	allocator := registry_data(registry).allocator
	pattern: []byte
	replacement: []byte
	if !active {
		pattern, _ = make([]byte, len(query_view.pattern), allocator)
		if pattern == nil && len(query_view.pattern) > 0 {
			return false, query_replacement_failure(registry, handle, .Persistent_Memory_Limit)
		}
		copy(pattern, query_view.pattern)
		replacement, _ = make([]byte, len(template_view.text), allocator)
		if replacement == nil && len(template_view.text) > 0 {
			delete(pattern, allocator)
			return false, query_replacement_failure(registry, handle, .Persistent_Memory_Limit)
		}
		copy(replacement, template_view.text)
	}
	if result_view.outcome == .Matched {
		current := result_view.occurrences[result_view.current_index]
		target_offset := current.end
		if update.direction == .Backward {
			target_offset = current.start
		}
		position, position_ok, position_failure := editor.buffer_position(slot.buffer, target_offset)
		if !position_ok {
			delete(replacement, allocator)
			delete(pattern, allocator)
			return false, editor_failure_context(registry, handle, position_failure)
		}
		moved, move_failure := editor.buffer_selection_set_point(slot.buffer, position)
		if !moved {
			delete(replacement, allocator)
			delete(pattern, allocator)
			return false, editor_failure_context(registry, handle, move_failure)
		}
		stored, stored_failure := editor.buffer_anchor_move(slot.buffer, slot.stored_point, position)
		assert(stored && stored_failure.code == .None)
	}

	state := &slot.query_replacement_session
	previous_revision := state.source_revision
	if active && state.has_match_result {
		closed, close_failure := search.result_close(&state.match_result)
		assert(closed && close_failure.code == .None)
		state.has_match_result = false
	}
	query_closed, query_close_failure := search.query_close(query)
	template_closed, template_close_failure := search.replacement_template_close(template)
	assert(query_closed && query_close_failure.code == .None)
	assert(template_closed && template_close_failure.code == .None)
	if !active {
		state.pattern = pattern
		state.replacement = replacement
		state.kind = query_kind
		state.search_policy = query_policy
		state.search_limits = query_limits
		state.replacement_policy = replacement_policy
		state.replacement_limits = replacement_limits
		state.effective_case = effective_case
		state.semantic_group = update.semantic_group
		state.policy_generation = update.policy_generation
		state.allocator = allocator
	} else if stats.revision != previous_revision {
		state.recomputations += 1
	}
	state.active = true
	state.interaction_generation = update.interaction_generation
	state.source_revision = stats.revision
	state.observed_revision = stats.revision
	state.source_text_bytes = stats.text_bytes
	state.observed_text_bytes = stats.text_bytes
	state.direction = update.direction
	state.scope = update.scope
	state.last_response = update.response
	state.replacements = update.replacements
	state.skips = update.skips
	state.progress = result_progress
	state.usage = result_view.usage
	if result_outcome == .Matched {
		state.match_result = result^
		result^ = {}
		state.has_match_result = true
		state.status = .Awaiting_Response
	} else {
		result_closed, result_close_failure := search.result_close(result)
		assert(result_closed && result_close_failure.code == .None)
		if result_outcome == .No_Match {
			state.status = .Exhausted
		} else {
			state.status = .Pending
			if result_view.progress.wrapped {
				state.status = .Wrapped
			}
		}
	}
	slot.state_generation += 1
	return true, {}
}

/* query_replacement_session_finish retains committed text and releases transient state. */
query_replacement_session_finish :: proc(
	registry: ^Registry,
	handle: View_Handle,
) -> (ok: bool, failure: Failure_Context) {
	slot, slot_failure := resolve(registry, handle)
	if slot_failure.code != .None {
		return false, slot_failure
	}
	if !slot.query_replacement_session.active || slot.active_preparation ||
	   slot.state_generation == max(u64) {
		return false, query_replacement_failure(registry, handle, .Invalid_Query_Replacement_Session)
	}
	released, release_failure := query_replacement_session_release(slot)
	if !released {
		return false, search_failure_context(registry, handle, release_failure)
	}
	slot.state_generation += 1
	return true, {}
}

/* query_replacement_session_view borrows active state until the next view operation. */
query_replacement_session_view :: proc(
	registry: ^Registry,
	handle: View_Handle,
) -> (Query_Replacement_Snapshot, bool, Failure_Context) {
	slot, slot_failure := resolve(registry, handle)
	if slot_failure.code != .None {
		return {}, false, slot_failure
	}
	state := &slot.query_replacement_session
	if !state.active {
		return {}, true, {}
	}
	snapshot := Query_Replacement_Snapshot {
		present = true,
		interaction_generation = state.interaction_generation,
		policy_generation = state.policy_generation,
		source_revision = state.source_revision,
		observed_revision = state.observed_revision,
		source_text_bytes = state.source_text_bytes,
		observed_text_bytes = state.observed_text_bytes,
		direction = state.direction,
		kind = state.kind,
		scope = state.scope,
		status = state.status,
		last_response = state.last_response,
		semantic_group = state.semantic_group,
		pattern = string(state.pattern),
		replacement = string(state.replacement),
		search_policy = state.search_policy,
		search_limits = state.search_limits,
		replacement_policy = state.replacement_policy,
		replacement_limits = state.replacement_limits,
		effective_case = state.effective_case,
		replacements = state.replacements,
		skips = state.skips,
		recomputations = state.recomputations,
		progress = state.progress,
		usage = state.usage,
	}
	if state.has_match_result {
		result_view, result_ok, result_failure := search.result_view(&state.match_result)
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
query_replacement_transition_is_valid :: proc(
	state: ^Query_Replacement_Session,
	update: Query_Replacement_Update,
	query: search.Query_View,
	template: search.Replacement_Template_View,
	current_revision: editor.Revision,
	current_text_bytes: u64,
) -> bool {
	if !state.active {
		return update.interaction_generation == 1 && update.response == .Started &&
		       update.replacements == 0 && update.skips == 0
	}
	if state.interaction_generation == max(u64) ||
	   update.interaction_generation != state.interaction_generation + 1 ||
	   update.policy_generation != state.policy_generation ||
	   update.semantic_group != state.semantic_group ||
	   update.direction != state.direction || query.kind != state.kind ||
	   query.pattern != string(state.pattern) || template.text != string(state.replacement) ||
	   query.policy != state.search_policy || query.limits != state.search_limits ||
	   template.policy != state.replacement_policy || template.limits != state.replacement_limits ||
	   query.effective_case != state.effective_case ||
	   update.response == .Invalid || update.response == .Started {
		return false
	}
	revision_changed := current_revision != state.source_revision
	if !query_replacement_scope_transition_is_valid(
		state,
		update,
		current_text_bytes,
		revision_changed,
	) {
		return false
	}
	if state.status == .Recomputation_Required &&
	   update.response != .Recomputed && update.response != .Replaced {
		return false
	}
	switch update.response {
	case .Continued:
		return !revision_changed && update.replacements == state.replacements &&
		       update.skips == state.skips
	case .Skipped:
		return !revision_changed && update.replacements == state.replacements &&
		       state.skips < max(u64) && update.skips == state.skips + 1
	case .Replaced:
		return revision_changed && state.replacements < max(u64) &&
		       update.replacements == state.replacements + 1 && update.skips == state.skips
	case .Recomputed:
		return revision_changed && update.replacements == state.replacements &&
		       update.skips == state.skips
	case .Invalid, .Started:
		return false
	}
	return false
}

@(private)
query_replacement_scope_is_valid :: proc(scope: search.Scope, text_bytes: u64) -> bool {
	return scope.start <= scope.end && u64(scope.end) <= text_bytes
}

@(private)
query_replacement_scope_transition_is_valid :: proc(
	state: ^Query_Replacement_Session,
	update: Query_Replacement_Update,
	current_text_bytes: u64,
	revision_changed: bool,
) -> bool {
	if !revision_changed {
		return update.scope == state.scope
	}
	if update.scope.start != state.scope.start {
		return false
	}
	if update.response == .Recomputed {
		if state.scope.start == 0 && u64(state.scope.end) == state.source_text_bytes {
			return update.scope.start == 0 && u64(update.scope.end) == current_text_bytes
		}
		return current_text_bytes == state.source_text_bytes && update.scope == search.Scope {
			buffer_id = state.scope.buffer_id,
			revision = update.scope.revision,
			start = state.scope.start,
			end = state.scope.end,
		}
	}
	if update.response != .Replaced {
		return false
	}
	expected_end := u64(state.scope.end)
	if current_text_bytes >= state.source_text_bytes {
		delta := current_text_bytes - state.source_text_bytes
		if expected_end > max(u64) - delta {
			return false
		}
		expected_end += delta
	} else {
		delta := state.source_text_bytes - current_text_bytes
		if delta > expected_end {
			return false
		}
		expected_end -= delta
	}
	return u64(update.scope.end) == expected_end
}

@(private)
query_replacement_session_mark_stale :: proc(
	slot: ^View_Slot,
	observed_revision: editor.Revision,
	observed_text_bytes: u64,
) -> (bool, search.Failure) {
	state := &slot.query_replacement_session
	if !state.active || state.source_revision == observed_revision {
		return true, {}
	}
	if state.has_match_result {
		closed, close_failure := search.result_close(&state.match_result)
		if !closed {
			return false, close_failure
		}
		state.has_match_result = false
	}
	state.observed_revision = observed_revision
	state.observed_text_bytes = observed_text_bytes
	state.status = .Recomputation_Required
	state.progress = {}
	return true, {}
}

@(private)
query_replacement_session_release :: proc(slot: ^View_Slot) -> (bool, search.Failure) {
	if slot == nil || !slot.query_replacement_session.active {
		return true, {}
	}
	state := &slot.query_replacement_session
	if state.has_match_result {
		closed, close_failure := search.result_close(&state.match_result)
		if !closed {
			return false, close_failure
		}
	}
	delete(state.replacement, state.allocator)
	delete(state.pattern, state.allocator)
	state^ = {}
	return true, {}
}

@(private)
query_replacement_failure :: proc(
	registry: ^Registry,
	handle: View_Handle,
	code: Failure_Code,
) -> Failure_Context {
	return view_failure(registry, handle, code)
}
