// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package completion

import "base:runtime"

@(private)
Controller_State :: struct {
	controller_id:                Controller_ID,
	controller_generation:        Controller_Generation,
	session_id:                   Session_ID,
	session_generation:           Session_Generation,
	session_state:                Session_State,
	request:                      Request,
	batch:                        Batch,
	query:                        Query_Context,
	projection:                   Projection,
	current_revision:             Document_Revision,
	retained_during_refresh:      bool,
	next_projection_generation: Projection_Generation,
	selected_candidate:           Candidate_ID,
	request_replacement_count: u16,
	next_resolve_generation:    Resolve_Generation,
	resolve_request:            Resolve_Request,
	resolve_pending:            bool,
	composition:                  Composition_Scope,
	policy:                       Session_Policy,
	limits:                       Limits,
	last_rejection:               Failure,
	allocator:                    runtime.Allocator,
}

/* controller_init creates one provider-independent completion owner. */
controller_init :: proc(
	controller: ^Controller,
	controller_id: Controller_ID,
	controller_generation: Controller_Generation,
	composition: Composition_Scope,
	limits := DEFAULT_LIMITS,
	allocator := context.allocator,
	policy := DEFAULT_SESSION_POLICY,
) -> (bool, Failure) {
	if controller == nil {
		return false, failure(.Initialize, .Invalid_Controller)
	}
	controller^ = {}
	if controller_id == Controller_ID(0) || controller_generation == Controller_Generation(0) {
		return false, failure(.Initialize, .Invalid_Identity)
	}
	if !composition_is_valid(composition) || !limits_are_valid(limits) ||
	   !session_policy_is_valid(policy) {
		return false, failure(.Initialize, .Invalid_State)
	}
	if allocator.procedure == nil {
		return false, failure(.Initialize, .Allocation)
	}
	state, allocation_error := new(Controller_State, allocator)
	if allocation_error != nil {
		return false, failure(.Initialize, .Allocation)
	}
	state^ = {
		controller_id = controller_id,
		controller_generation = controller_generation,
		composition = composition,
		policy = policy,
		limits = limits,
		next_projection_generation = 1,
		next_resolve_generation = 1,
		allocator = allocator,
	}
	controller.state = state
	return true, {}
}

/* controller_close releases the active batch and controller storage exactly once. */
controller_close :: proc(controller: ^Controller) -> (bool, Failure) {
	state := controller_state(controller)
	if state == nil {
		return false, failure(.Close, .Invalid_Controller)
	}
	controller_release_batch(state)
	allocator := state.allocator
	free(state, allocator)
	controller^ = Controller{closed = true}
	return true, {}
}

/* controller_start binds one prepared request to one exact session and composition. */
controller_start :: proc(
	controller: ^Controller,
	session_id: Session_ID,
	session_generation: Session_Generation,
	request: Request,
	expected_composition: Composition_Scope,
) -> (bool, Failure) {
	state := controller_state(controller)
	if state == nil {
		return false, failure(.Start, .Invalid_Controller)
	}
	if session_id == Session_ID(0) || session_generation == Session_Generation(0) {
		return false, controller_reject(state, failure(.Start, .Invalid_Identity))
	}
	if state.session_state != .Invalid && state.session_state != .Retired {
		return false, controller_reject(state, failure(.Start, .Invalid_State))
	}
	if expected_composition != state.composition || !state.composition.enabled {
		return false, controller_reject(state, failure(.Start, .Stale_Scope))
	}
	request_value := request
	query, query_ok := query_context_from_request(&request_value)
	if !query_ok || (request.trigger == .Explicit && !state.policy.explicit_enabled) ||
	   (request.trigger == .Identifier &&
	    (!state.policy.identifier_enabled ||
	     query.grapheme_count < state.policy.minimum_identifier_graphemes)) ||
	   (request.trigger == .Trigger_Character && !state.policy.trigger_character_enabled) {
		return false, controller_reject(state, request_failure(.Start, .Invalid_Request, request))
	}
	selected_provider := state.composition.selections[role_index(.Provider)].selected
	if selected_provider.implementation_id == Implementation_ID(0) {
		return false, controller_reject(state, failure(.Start, .Provider_Unavailable, .Provider))
	}
	if request.scope.provider_id != Provider_ID(selected_provider.implementation_id) ||
	   request.scope.provider_generation != Provider_Generation(selected_provider.implementation_generation) {
		return false, controller_reject(state, request_failure(.Start, .Stale_Provider, request))
	}
	controller_release_batch(state)
	state.session_id = session_id
	state.session_generation = session_generation
	state.session_state = .Requesting
	state.request = request
	state.query = query
	state.current_revision = request.scope.document_revision
	state.retained_during_refresh = false
	state.selected_candidate = 0
	state.request_replacement_count = 0
	return true, {}
}

/* controller_queue records provider dispatch admission. */
controller_queue :: proc(controller: ^Controller) -> (bool, Failure) {
	return controller_transition_request(controller, .Prepared, .Queued, .Queue)
}

/* controller_send records provider transport publication. */
controller_send :: proc(controller: ^Controller) -> (bool, Failure) {
	return controller_transition_request(controller, .Queued, .Sent, .Send)
}

/* controller_update cancels and replaces the active request generation. */
controller_update :: proc(
	controller: ^Controller,
	request: Request,
) -> (bool, Failure) {
	state := controller_state(controller)
	if state == nil {
		return false, failure(.Update, .Invalid_Controller)
	}
	if state.session_state == .Invalid || state.session_state == .Retired ||
	   state.session_state == .Dismissed {
		return false, controller_reject(state, failure(.Update, .Invalid_State))
	}
	request_value := request
	query, query_ok := query_context_from_request(&request_value)
	if !query_ok || request.generation <= state.request.generation ||
	   request.id == state.request.id || request.scope.document_id != state.request.scope.document_id ||
	   request.scope.buffer_id != state.request.scope.buffer_id ||
	   request.scope.view_id != state.request.scope.view_id ||
	   request.scope.view_generation != state.request.scope.view_generation ||
	   request.scope.provider_id != state.request.scope.provider_id ||
	   request.scope.provider_generation != state.request.scope.provider_generation {
		return false, controller_reject(state, request_failure(.Update, .Stale_Request, request))
	}
	if state.request_replacement_count >= state.limits.request_replacements {
		result := request_failure(.Update, .Request_Limit, request)
		result.limit = u64(state.limits.request_replacements)
		result.actual = u64(state.request_replacement_count) + 1
		return false, controller_reject(state, result)
	}
	controller_cancel_request(state)
	controller_release_batch(state)
	state.request = request
	state.query = query
	state.current_revision = request.scope.document_revision
	state.retained_during_refresh = false
	state.request_replacement_count += 1
	state.session_state = .Requesting
	state.selected_candidate = 0
	return true, {}
}

/* controller_publish copies one exact current provider batch. */
controller_publish :: proc(controller: ^Controller, batch: ^Batch) -> (bool, Failure) {
	state := controller_state(controller)
	if state == nil {
		return false, failure(.Publish, .Invalid_Controller)
	}
	if state.session_state != .Requesting || state.request.state != .Sent {
		return false, controller_reject(state, failure(.Publish, .Invalid_State))
	}
	if batch == nil || batch.request_id != state.request.id ||
	   batch.request_generation != state.request.generation {
		return false, controller_reject(state, failure(.Publish, .Stale_Request))
	}
	if batch.scope.document_revision != state.request.scope.document_revision {
		return false, controller_reject(state, failure(.Publish, .Stale_Document))
	}
	if batch.scope.provider_id != state.request.scope.provider_id ||
	   batch.scope.provider_generation != state.request.scope.provider_generation {
		return false, controller_reject(state, failure(.Publish, .Stale_Provider))
	}
	if !batch_is_valid(batch, &state.request, state.limits) {
		return false, controller_reject(state, failure(.Publish, .Invalid_Batch))
	}
	semantic_selection := controller_semantic_selection(state, batch)
	if state.next_projection_generation == Projection_Generation(0) {
		return false, controller_reject(state, failure(.Publish, .Generation_Limit))
	}
	projection, projected, projection_failure := projection_build(
		batch,
		&state.request,
		state.query,
		semantic_selection,
		state.policy.filter,
		state.next_projection_generation,
		state.allocator,
	)
	if !projected {
		return false, controller_reject(state, projection_failure)
	}
	items, allocation_error := make([]Candidate, len(batch.items), state.allocator)
	if allocation_error != nil {
		projection_close(&projection)
		return false, controller_reject(state, failure(.Publish, .Allocation))
	}
	copy(items, batch.items)
	controller_release_batch(state)
	state.batch = batch^
	state.batch.items = items
	state.projection = projection
	state.next_projection_generation += 1
	state.request.state = .Completed
	state.retained_during_refresh = false
	if len(projection.items) == 0 {
		state.session_state = .Empty
		state.selected_candidate = 0
	} else {
		state.session_state = .Ready
		state.selected_candidate = projection.selected
	}
	return true, {}
}

/* controller_cancel invalidates pending authority and dismisses the session. */
controller_cancel :: proc(controller: ^Controller) -> (bool, Failure) {
	state := controller_state(controller)
	if state == nil {
		return false, failure(.Cancel, .Invalid_Controller)
	}
	if state.session_state == .Invalid || state.session_state == .Retired ||
	   state.session_state == .Dismissed {
		return false, controller_reject(state, failure(.Cancel, .Invalid_State))
	}
	controller_cancel_request(state)
	controller_release_batch(state)
	state.selected_candidate = 0
	state.session_state = .Dismissed
	return true, {}
}

/* controller_fail records one provider failure without publishing candidates. */
controller_fail :: proc(controller: ^Controller, source: Failure) -> (bool, Failure) {
	state := controller_state(controller)
	if state == nil {
		return false, failure(.Fail, .Invalid_Controller)
	}
	if state.session_state != .Requesting {
		return false, controller_reject(state, failure(.Fail, .Invalid_State))
	}
	state.request.state = .Failed
	state.session_state = .Failed
	controller_clear_resolution(state)
	reported := source
	reported.operation = .Fail
	state.last_rejection = reported
	return true, reported
}

/* controller_dismiss clears retained candidates and preserves plain editing. */
controller_dismiss :: proc(controller: ^Controller) -> (bool, Failure) {
	state := controller_state(controller)
	if state == nil {
		return false, failure(.Dismiss, .Invalid_Controller)
	}
	if state.session_state == .Invalid || state.session_state == .Retired ||
	   state.session_state == .Dismissed {
		return false, controller_reject(state, failure(.Dismiss, .Invalid_State))
	}
	controller_cancel_request(state)
	controller_release_batch(state)
	state.selected_candidate = 0
	state.session_state = .Dismissed
	return true, {}
}

/* controller_retire closes one session generation for safe reuse. */
controller_retire :: proc(controller: ^Controller) -> (bool, Failure) {
	state := controller_state(controller)
	if state == nil {
		return false, failure(.Retire, .Invalid_Controller)
	}
	if state.session_state == .Invalid || state.session_state == .Retired {
		return false, controller_reject(state, failure(.Retire, .Invalid_State))
	}
	controller_cancel_request(state)
	controller_release_batch(state)
	state.selected_candidate = 0
	state.session_state = .Retired
	return true, {}
}

/* controller_document_changed rejects an active session bound to another revision. */
controller_document_changed :: proc(
	controller: ^Controller,
	revision: Document_Revision,
) -> (bool, Failure) {
	state := controller_state(controller)
	if state == nil {
		return false, failure(.Cancel, .Invalid_Controller)
	}
	if state.session_state == .Invalid || state.session_state == .Retired ||
	   revision == Document_Revision(0) {
		return false, controller_reject(state, failure(.Cancel, .Invalid_State))
	}
	if revision == state.request.scope.document_revision {
		return true, {}
	}
	_, _ = controller_cancel(controller)
	return false, controller_reject(state, failure(.Cancel, .Stale_Document))
}

/* controller_reconcile_composition adopts compatible roles or dismisses stale provider state. */
controller_reconcile_composition :: proc(
	controller: ^Controller,
	composition: Composition_Scope,
) -> (compatible: bool, failure_result: Failure) {
	state := controller_state(controller)
	if state == nil {
		return false, failure(.Update, .Invalid_Controller)
	}
	if !composition_is_valid(composition) {
		return false, controller_reject(state, failure(.Update, .Stale_Scope))
	}
	previous_provider := state.composition.selections[role_index(.Provider)].selected
	current_provider := composition.selections[role_index(.Provider)].selected
	state.composition = composition
	if state.session_state != .Invalid && state.session_state != .Retired &&
	   (!composition.enabled || previous_provider != current_provider) {
		controller_cancel_request(state)
		controller_release_batch(state)
		state.selected_candidate = 0
		state.session_state = .Dismissed
		return false, controller_reject(state, failure(.Update, .Stale_Provider, .Provider))
	}
	return true, {}
}

/* controller_inspect copies the observable active session and resource state. */
controller_inspect :: proc(controller: ^Controller) -> (Session_Inspection, bool, Failure) {
	state := controller_state(controller)
	if state == nil {
		return {}, false, failure(.Inspect, .Invalid_Controller)
	}
	result := Session_Inspection {
		controller_id = state.controller_id,
		controller_generation = state.controller_generation,
		session_id = state.session_id,
		session_generation = state.session_generation,
		state = state.session_state,
		request = state.request,
		batch_id = state.batch.id,
		batch_generation = state.batch.generation,
		projection_generation = state.projection.generation,
		candidate_count = state.batch.item_count,
		filtered_candidate_count = state.projection.item_count,
		deduplicated_candidate_count = state.projection.deduplicated,
		rejected_candidate_count = state.batch.rejected_item_count,
		normalization_warning_count = state.batch.normalization_warning_count,
		selected_candidate = state.selected_candidate,
		detail_state = controller_detail_state(state),
		resolve_pending = state.resolve_pending,
		trigger = state.query.trigger,
		query_range = state.query.range,
		query = state.query.text,
		current_revision = state.current_revision,
		transmitted_revision = state.request.scope.transmitted_revision,
		batch_disposition = state.batch.disposition,
		retained_during_refresh = state.retained_during_refresh,
		policy = state.policy,
		copied_candidate_bytes = state.batch.copied_bytes,
		composition = state.composition,
		retained_bytes = size_of(Controller_State) +
			u64(len(state.batch.items)) * size_of(Candidate) + state.projection.retained_bytes,
		last_rejection = state.last_rejection,
	}
	for item in state.projection.items {
		match_index := int(item.match_class) - int(Match_Class.Exact)
		if match_index >= 0 && match_index < len(result.match_class_counts) {
			result.match_class_counts[match_index] += 1
		}
	}
	for candidate in state.batch.items {
		result.additional_edit_count += u16(candidate.additional_edit_count)
		if candidate.resolved do result.resolved_candidate_count += 1
		if candidate.availability == .Deprecated do result.deprecated_candidate_count += 1
		if candidate.id == state.selected_candidate do result.selected_resolved = candidate.resolved
	}
	return result, true, {}
}

@(private)
controller_state :: proc(controller: ^Controller) -> ^Controller_State {
	if controller == nil || controller.closed || controller.state == nil {
		return nil
	}
	return cast(^Controller_State)controller.state
}

@(private)
controller_transition_request :: proc(
	controller: ^Controller,
	expected: Request_State,
	next: Request_State,
	operation: Operation,
) -> (bool, Failure) {
	state := controller_state(controller)
	if state == nil {
		return false, failure(operation, .Invalid_Controller)
	}
	if state.session_state != .Requesting || state.request.state != expected {
		return false, controller_reject(state, failure(operation, .Invalid_State))
	}
	state.request.state = next
	return true, {}
}

@(private)
controller_release_batch :: proc(state: ^Controller_State) {
	controller_clear_resolution(state)
	if !state.projection.closed && state.projection.allocator.procedure != nil {
		projection_close(&state.projection)
	}
	if state.batch.items != nil {
		delete(state.batch.items, state.allocator)
	}
	state.batch = {}
	state.projection = {}
	state.retained_during_refresh = false
}

@(private)
controller_semantic_selection :: proc(state: ^Controller_State, batch: ^Batch) -> Candidate_ID {
	if state == nil || batch == nil || state.selected_candidate == Candidate_ID(0) do return 0
	previous: ^Candidate
	for &candidate in state.batch.items {
		if candidate.id == state.selected_candidate {
			previous = &candidate
			break
		}
	}
	if previous == nil do return 0
	for &candidate in batch.items {
		previous_label := previous.label
		candidate_label := candidate.label
		previous_insert := previous.insertion_text
		candidate_insert := candidate.insertion_text
		previous_sort := previous.sort_text
		candidate_sort := candidate.sort_text
		if text_view(&previous_label) == text_view(&candidate_label) &&
		   previous.kind == candidate.kind && previous.has_primary_edit == candidate.has_primary_edit &&
		   text_view(&previous_insert) == text_view(&candidate_insert) &&
		   text_view(&previous_sort) == text_view(&candidate_sort) &&
		   previous.provenance.provider_order == candidate.provenance.provider_order {
			return candidate.id
		}
	}
	return 0
}

@(private)
controller_cancel_request :: proc(state: ^Controller_State) {
	if state.request.state == .Prepared || state.request.state == .Queued ||
	   state.request.state == .Sent {
		state.request.state = .Cancelled
	}
}

@(private)
composition_is_valid :: proc(composition: Composition_Scope) -> bool {
	if composition.registry_id == Role_Registry_ID(0) ||
	   composition.registry_generation == Role_Registry_Generation(0) ||
	   composition.composition_generation == Composition_Generation(0) {
		return false
	}
	for index in 0 ..< MAX_COMPLETION_ROLES {
		selection := composition.selections[index]
		if selection.role != Role(index + 1) || selection.selected.registry_id != composition.registry_id ||
		   selection.selected.role != selection.role || selection.factory.role != selection.role ||
		   selection.selected.implementation_id == Implementation_ID(0) ||
		   selection.selected.implementation_generation == Implementation_Generation(0) ||
		   role_required_capabilities(selection.role) - selection.selected_capabilities != {} ||
		   role_required_capabilities(selection.role) - selection.factory_capabilities != {} {
			return false
		}
	}
	return true
}

@(private)
request_failure :: proc(operation: Operation, code: Failure_Code, request: Request) -> Failure {
	result := failure(operation, code)
	result.request_id = request.id
	result.request_generation = request.generation
	return result
}

@(private)
controller_reject :: proc(state: ^Controller_State, rejected: Failure) -> Failure {
	state.last_rejection = rejected
	return rejected
}
