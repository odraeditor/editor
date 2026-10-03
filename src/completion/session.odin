// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package completion

/* Session_Policy selects factory invocation and filtering behavior. */
Session_Policy :: struct {
	explicit_enabled:             bool,
	identifier_enabled:           bool,
	trigger_character_enabled:    bool,
	minimum_identifier_graphemes: u16,
	filter:                       Filter_Policy,
}

/* DEFAULT_SESSION_POLICY starts automatically only on server trigger characters. */
DEFAULT_SESSION_POLICY :: Session_Policy {
	explicit_enabled = true,
	identifier_enabled = false,
	trigger_character_enabled = true,
	minimum_identifier_graphemes = 2,
	filter = DEFAULT_FILTER_POLICY,
}

/* session_policy_is_valid validates one complete invocation and filtering policy. */
session_policy_is_valid :: proc(policy: Session_Policy) -> bool {
	return policy.minimum_identifier_graphemes > 0 &&
		(policy.filter.case_sensitive_prefix || policy.filter.case_insensitive_prefix ||
		 policy.filter.subsequence)
}

/* Refresh_Action identifies local filtering, provider refresh, or dismissal. */
Refresh_Action :: enum u8 {
	Invalid,
	Local_Filter,
	Provider_Request,
	Dismiss,
}

/* controller_refine updates one compatible query without polling document state. */
controller_refine :: proc(
	controller: ^Controller,
	request: Request,
) -> (Refresh_Action, bool, Failure) {
	state := controller_state(controller)
	if state == nil do return .Invalid, false, failure(.Update, .Invalid_Controller)
	if state.session_state == .Invalid || state.session_state == .Dismissed ||
	   state.session_state == .Retired || state.session_state == .Failed {
		return .Dismiss, false, controller_reject(state, failure(.Update, .Invalid_State))
	}
	request_value := request
	query, query_ok := query_context_from_request(&request_value)
	if !query_ok || !controller_refresh_scope_compatible(state.request, request) ||
	   request.scope.document_revision <= state.current_revision ||
	   query.range.start != state.query.range.start {
		return controller_refine_dismiss(state, request_failure(.Update, .Stale_Request, request))
	}
	if request.trigger == .Identifier &&
	   (!state.policy.identifier_enabled ||
	    query.grapheme_count < state.policy.minimum_identifier_graphemes) {
		return controller_refine_dismiss(state, request_failure(.Update, .Invalid_Request, request))
	}
	if state.batch.id != Batch_ID(0) && state.batch.disposition == .Complete {
		if state.next_projection_generation == Projection_Generation(0) {
			return .Invalid, false, controller_reject(state, failure(.Update, .Generation_Limit))
		}
		projection, projected, projection_failure := projection_build(
			&state.batch,
			&state.request,
			query,
			state.selected_candidate,
			state.policy.filter,
			state.next_projection_generation,
			state.allocator,
		)
		if !projected {
			return .Invalid, false, controller_reject(state, projection_failure)
		}
		controller_clear_resolution(state)
		if !state.projection.closed && state.projection.allocator.procedure != nil {
			projection_close(&state.projection)
		}
		state.projection = projection
		state.next_projection_generation += 1
		state.query = query
		state.current_revision = request.scope.document_revision
		state.selected_candidate = projection.selected
		state.retained_during_refresh = false
		state.session_state = .Ready if projection.item_count > 0 else .Empty
		return .Local_Filter, true, {}
	}
	if state.request_replacement_count >= state.limits.request_replacements {
		result := request_failure(.Update, .Request_Limit, request)
		result.limit = u64(state.limits.request_replacements)
		result.actual = u64(state.request_replacement_count) + 1
		return controller_refine_dismiss(state, result)
	}
	if state.batch.id != Batch_ID(0) && state.batch.disposition == .Incomplete &&
	   request.trigger != .Incomplete {
		return controller_refine_dismiss(state, request_failure(.Update, .Invalid_Request, request))
	}
	controller_cancel_request(state)
	state.request = request
	state.query = query
	state.current_revision = request.scope.document_revision
	state.request_replacement_count += 1
	state.session_state = .Requesting
	state.retained_during_refresh = state.batch.id != Batch_ID(0)
	if !state.retained_during_refresh do state.selected_candidate = 0
	return .Provider_Request, true, {}
}

/* controller_select_candidate selects one visible exact candidate identity. */
controller_select_candidate :: proc(
	controller: ^Controller,
	candidate: Candidate_ID,
) -> (bool, Failure) {
	state := controller_state(controller)
	if state == nil do return false, failure(.Select, .Invalid_Controller)
	if state.session_state != .Ready &&
	   !(state.session_state == .Requesting && state.retained_during_refresh) {
		return false, controller_reject(state, failure(.Select, .Invalid_State))
	}
	for item in state.projection.items {
		if item.candidate_id == candidate {
			if state.selected_candidate != candidate do controller_clear_resolution(state)
			state.selected_candidate = candidate
			state.projection.selected = candidate
			return true, {}
		}
	}
	return false, controller_reject(state, failure(.Select, .Invalid_Candidate))
}

/* controller_move_selection changes only the selected visible candidate. */
controller_move_selection :: proc(
	controller: ^Controller,
	movement: Selection_Movement,
) -> (bool, Failure) {
	state := controller_state(controller)
	if state == nil do return false, failure(.Select, .Invalid_Controller)
	if movement == .Invalid ||
	   (state.session_state != .Ready &&
	    !(state.session_state == .Requesting && state.retained_during_refresh)) {
		return false, controller_reject(state, failure(.Select, .Invalid_State))
	}
	if len(state.projection.items) == 0 {
		return false, controller_reject(state, failure(.Select, .Invalid_Candidate))
	}
	selected_index := -1
	for item, index in state.projection.items {
		if item.candidate_id == state.selected_candidate {
			selected_index = index
			break
		}
	}
	if selected_index < 0 {
		return false, controller_reject(state, failure(.Select, .Invalid_Candidate))
	}
	next_index := selected_index
	switch movement {
	case .Next:
		next_index = min(selected_index + 1, len(state.projection.items) - 1)
	case .Previous:
		next_index = max(selected_index - 1, 0)
	case .First:
		next_index = 0
	case .Last:
		next_index = len(state.projection.items) - 1
	case .Invalid:
		unreachable()
	}
	return controller_select_candidate(
		controller,
		state.projection.items[next_index].candidate_id,
	)
}

@(private = "file")
controller_refresh_scope_compatible :: proc(previous, next: Request) -> bool {
	return next.id != previous.id && next.generation > previous.generation &&
		next.scope.document_id == previous.scope.document_id &&
		next.scope.buffer_id == previous.scope.buffer_id &&
		next.scope.view_id == previous.scope.view_id &&
		next.scope.view_generation == previous.scope.view_generation &&
		next.scope.language_id == previous.scope.language_id &&
		next.scope.language_generation == previous.scope.language_generation &&
		next.scope.provider_id == previous.scope.provider_id &&
		next.scope.provider_generation == previous.scope.provider_generation &&
		next.scope.server_session_id == previous.scope.server_session_id &&
		next.scope.server_session_generation == previous.scope.server_session_generation &&
		next.scope.document_binding_id == previous.scope.document_binding_id &&
		next.scope.document_binding_generation == previous.scope.document_binding_generation
}

@(private = "file")
controller_refine_dismiss :: proc(
	state: ^Controller_State,
	rejected: Failure,
) -> (Refresh_Action, bool, Failure) {
	controller_cancel_request(state)
	controller_release_batch(state)
	state.selected_candidate = 0
	state.session_state = .Dismissed
	return .Dismiss, false, controller_reject(state, rejected)
}
