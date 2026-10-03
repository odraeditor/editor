// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package completion

/* controller_candidate_detail copies detail state for the exact selected candidate. */
controller_candidate_detail :: proc(
	controller: ^Controller,
) -> (detail: Candidate_Detail, ok: bool, failure_result: Failure) {
	state := controller_state(controller)
	if state == nil {
		return {}, false, failure(.Inspect, .Invalid_Controller)
	}
	candidate := controller_selected_candidate(state)
	if candidate == nil {
		return {}, false, controller_reject(state, failure(.Inspect, .Invalid_Candidate))
	}
	return controller_detail_from_candidate(state, candidate), true, {}
}

/* controller_request_candidate_detail issues at most one exact lazy resolve request. */
controller_request_candidate_detail :: proc(
	controller: ^Controller,
) -> (
	detail: Candidate_Detail,
	request: Resolve_Request,
	ok: bool,
	failure_result: Failure,
) {
	state := controller_state(controller)
	if state == nil {
		return {}, {}, false, failure(.Resolve, .Invalid_Controller)
	}
	candidate := controller_selected_candidate(state)
	if candidate == nil {
		return {}, {}, false, controller_reject(state, failure(.Resolve, .Invalid_Candidate))
	}
	detail = controller_detail_from_candidate(state, candidate)
	if detail.state != .Resolve_Required && detail.state != .Resolving {
		return detail, {}, true, {}
	}
	if state.resolve_pending {
		return detail, state.resolve_request, true, {}
	}
	if state.next_resolve_generation == Resolve_Generation(0) {
		return {}, {}, false, controller_reject(state, failure(.Resolve, .Generation_Limit))
	}
	state.resolve_request = {
		generation = state.next_resolve_generation,
		controller_id = state.controller_id,
		controller_generation = state.controller_generation,
		session_id = state.session_id,
		session_generation = state.session_generation,
		batch_id = state.batch.id,
		batch_generation = state.batch.generation,
		projection_generation = state.projection.generation,
		candidate_id = candidate.id,
		provider_id = state.request.scope.provider_id,
		provider_generation = state.request.scope.provider_generation,
		document_revision = state.current_revision,
		token = candidate.resolve_token,
	}
	state.next_resolve_generation += 1
	state.resolve_pending = true
	detail.state = .Resolving
	return detail, state.resolve_request, true, {}
}

/* controller_publish_candidate_resolution updates only admitted detail fields atomically. */
controller_publish_candidate_resolution :: proc(
	controller: ^Controller,
	resolution: Candidate_Resolution,
) -> (bool, Failure) {
	state := controller_state(controller)
	if state == nil do return false, failure(.Resolve, .Invalid_Controller)
	if !state.resolve_pending || resolution.request != state.resolve_request ||
	   !controller_resolve_request_is_current(state, resolution.request) {
		return false, controller_reject(state, failure(.Resolve, .Stale_Request))
	}
	if int(resolution.detail.byte_count) > int(state.limits.detail_bytes) ||
	   int(resolution.documentation.byte_count) > int(state.limits.detail_bytes) {
		return false, controller_reject(state, failure(.Resolve, .Detail_Limit))
	}
	if (resolution.documentation.byte_count == 0) !=
	   (resolution.documentation_format == .Invalid) {
		return false, controller_reject(state, failure(.Resolve, .Invalid_State))
	}
	candidate := controller_selected_candidate(state)
	if candidate == nil || candidate.id != resolution.request.candidate_id {
		return false, controller_reject(state, failure(.Resolve, .Stale_Request))
	}
	old_bytes := u64(candidate.detail.byte_count) + u64(candidate.documentation.byte_count)
	new_bytes := u64(resolution.detail.byte_count) + u64(resolution.documentation.byte_count)
	if new_bytes >= old_bytes {
		delta := new_bytes - old_bytes
		candidate.copied_bytes += delta
		state.batch.copied_bytes += delta
	} else {
		delta := old_bytes - new_bytes
		candidate.copied_bytes -= min(candidate.copied_bytes, delta)
		state.batch.copied_bytes -= min(state.batch.copied_bytes, delta)
	}
	candidate.detail = resolution.detail
	candidate.documentation = resolution.documentation
	candidate.documentation_format = resolution.documentation_format
	candidate.resolved = true
	controller_clear_resolution(state)
	return true, {}
}

/* controller_fail_candidate_resolution contains one stale or failed lazy request. */
controller_fail_candidate_resolution :: proc(
	controller: ^Controller,
	request: Resolve_Request,
	source: Failure,
) -> (bool, Failure) {
	state := controller_state(controller)
	if state == nil do return false, failure(.Resolve, .Invalid_Controller)
	if !state.resolve_pending || request != state.resolve_request {
		return false, controller_reject(state, failure(.Resolve, .Stale_Request))
	}
	controller_clear_resolution(state)
	reported := source
	reported.operation = .Resolve
	if reported.code == .None do reported.code = .Provider_Unavailable
	return true, controller_reject(state, reported)
}

@(private)
controller_detail_state :: proc(state: ^Controller_State) -> Detail_State {
	candidate := controller_selected_candidate(state)
	if candidate == nil do return .Invalid
	return controller_detail_from_candidate(state, candidate).state
}

@(private)
controller_detail_from_candidate :: proc(
	state: ^Controller_State,
	candidate: ^Candidate,
) -> Candidate_Detail {
	detail := Candidate_Detail {
		controller_id = state.controller_id,
		controller_generation = state.controller_generation,
		session_id = state.session_id,
		session_generation = state.session_generation,
		batch_id = state.batch.id,
		batch_generation = state.batch.generation,
		projection_generation = state.projection.generation,
		candidate_id = candidate.id,
		kind = candidate.kind,
		availability = candidate.availability,
		label = candidate.label,
		detail = candidate.detail,
		documentation = candidate.documentation,
		documentation_format = candidate.documentation_format,
	}
	if candidate.detail.byte_count > 0 || candidate.documentation.byte_count > 0 {
		detail.state = .Ready
	} else if state.resolve_pending && state.resolve_request.candidate_id == candidate.id {
		detail.state = .Resolving
	} else if candidate.resolved || candidate.resolve_token.byte_count == 0 ||
	          .Resolve not_in state.request.provider_capabilities ||
	          .Resolve not_in state.composition.selections[role_index(.Provider)].selected_capabilities {
		detail.state = .Unavailable
	} else {
		detail.state = .Resolve_Required
	}
	return detail
}

@(private)
controller_selected_candidate :: proc(state: ^Controller_State) -> ^Candidate {
	if state == nil || state.selected_candidate == Candidate_ID(0) ||
	   (state.session_state != .Ready &&
	    !(state.session_state == .Requesting && state.retained_during_refresh)) {
		return nil
	}
	for &candidate in state.batch.items {
		if candidate.id == state.selected_candidate do return &candidate
	}
	return nil
}

@(private)
controller_resolve_request_is_current :: proc(
	state: ^Controller_State,
	request: Resolve_Request,
) -> bool {
	return state != nil && request.generation != Resolve_Generation(0) &&
		request.controller_id == state.controller_id &&
		request.controller_generation == state.controller_generation &&
		request.session_id == state.session_id &&
		request.session_generation == state.session_generation &&
		request.batch_id == state.batch.id &&
		request.batch_generation == state.batch.generation &&
		request.projection_generation == state.projection.generation &&
		request.candidate_id == state.selected_candidate &&
		request.provider_id == state.request.scope.provider_id &&
		request.provider_generation == state.request.scope.provider_generation &&
		request.document_revision == state.current_revision &&
		request.token.byte_count > 0
}

@(private)
controller_clear_resolution :: proc(state: ^Controller_State) {
	if state == nil do return
	state.resolve_request = {}
	state.resolve_pending = false
}
