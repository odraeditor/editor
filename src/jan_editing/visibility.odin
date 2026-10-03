// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_editing

import "../view"
import "base:runtime"

@(private)
Visibility_Transition_State_Data :: struct {
	descriptor: Visibility_Transition_Descriptor,
	ranges:     []view.Hidden_Range,
	allocator:  runtime.Allocator,
}

/* local_visibility_next returns the next state in the closed subtree cycle. */
local_visibility_next :: proc(current: Visibility_State) -> (Visibility_State, bool) {
	switch current {
	case .Heading_Only:
		return .Direct_Children, true
	case .Direct_Children:
		return .Complete_Subtree, true
	case .Complete_Subtree:
		return .Heading_Only, true
	case .Invalid, .Overview, .Contents, .Show_All, .Drawer_Visible, .Drawer_Folded:
	}
	return .Invalid, false
}

/* global_visibility_next returns the next state in the closed document cycle. */
global_visibility_next :: proc(current: Visibility_State) -> (Visibility_State, bool) {
	switch current {
	case .Overview:
		return .Contents, true
	case .Contents:
		return .Show_All, true
	case .Show_All:
		return .Overview, true
	case .Invalid, .Heading_Only, .Direct_Children, .Complete_Subtree,
	     .Drawer_Visible, .Drawer_Folded:
	}
	return .Invalid, false
}

/* visibility_transition_is_valid reports whether one prepared transition is live. */
visibility_transition_is_valid :: proc(transition: ^Visibility_Transition) -> bool {
	return transition != nil && transition.state != nil
}

/* visibility_transition_prepare copies one exact deterministic visibility candidate. */
visibility_transition_prepare :: proc(
	transition: ^Visibility_Transition,
	registry: ^view.Registry,
	request: Visibility_Transition_Request,
	limits := DEFAULT_LIMITS,
	allocator := context.allocator,
) -> (descriptor: Visibility_Transition_Descriptor, ok: bool, failure: Failure) {
	assert(transition != nil)
	if visibility_transition_is_valid(transition) {
		return {}, false, editing_failure(.Prepare_Visibility, .Invalid_Visibility, request.scope)
	}
	if !limits_are_valid(limits) || allocator.procedure == nil ||
	   request.operation_id == Operation_ID(0) || !scope_is_valid(request.scope) {
		return {}, false, editing_failure(.Prepare_Visibility, .Invalid_Scope, request.scope)
	}
	snapshot, snapshot_ok, snapshot_failure := view.snapshot(registry, request.scope.view_handle)
	if !snapshot_ok {
		failure = editing_failure(.Prepare_Visibility, .View_Failed, request.scope)
		failure.view_failure = snapshot_failure
		return {}, false, failure
	}
	if !scope_matches_view(request.scope, snapshot) {
		return {}, false, editing_failure(.Prepare_Visibility, .Stale, request.scope)
	}
	next: Visibility_State
	next_ok: bool
	if request.selected != .Invalid {
		next = request.selected
		next_ok = visibility_state_matches_kind(request.kind, next)
	} else if request.kind == .Local {
		next, next_ok = local_visibility_next(request.current)
	} else if request.kind == .Global {
		next, next_ok = global_visibility_next(request.current)
	}
	if !next_ok {
		return {}, false, editing_failure(.Prepare_Visibility, .Invalid_Visibility, request.scope)
	}
	if u64(len(request.ranges)) > u64(limits.hidden_ranges) {
		failure = editing_failure(.Prepare_Visibility, .Limited, request.scope)
		failure.limit = u64(limits.hidden_ranges)
		failure.actual = u64(len(request.ranges))
		return {}, false, failure
	}
	for hidden in request.ranges {
		if hidden.start.buffer_id != request.scope.analysis.buffer_id ||
		   hidden.end.buffer_id != request.scope.analysis.buffer_id ||
		   hidden.start.revision != request.scope.analysis.source_revision ||
		   hidden.end.revision != request.scope.analysis.source_revision ||
		   hidden.start.byte_offset >= hidden.end.byte_offset {
			return {}, false, editing_failure(
				.Prepare_Visibility,
				.Invalid_Visibility,
				request.scope,
			)
		}
	}
	state, state_error := new(Visibility_Transition_State_Data, allocator)
	if state_error != nil {
		return {}, false, editing_failure(.Prepare_Visibility, .Allocation_Failed, request.scope)
	}
	state^ = Visibility_Transition_State_Data{allocator = allocator}
	if len(request.ranges) > 0 {
		state.ranges, state_error = make([]view.Hidden_Range, len(request.ranges), allocator)
		if state_error != nil {
			free(state, allocator)
			return {}, false, editing_failure(
				.Prepare_Visibility,
				.Allocation_Failed,
				request.scope,
			)
		}
		copy(state.ranges, request.ranges)
	}
	state.descriptor = Visibility_Transition_Descriptor {
		operation_id = request.operation_id,
		scope = request.scope,
		kind = request.kind,
		previous = request.current,
		next = next,
		range_count = u32(len(state.ranges)),
		retained_bytes = u64(size_of(Visibility_Transition_State_Data)) +
		                 u64(len(state.ranges)) * u64(size_of(view.Hidden_Range)),
	}
	transition.state = state
	return state.descriptor, true, {}
}

@(private)
visibility_state_matches_kind :: proc(kind: Visibility_Kind, state: Visibility_State) -> bool {
	if kind == .Local {
		return state == .Heading_Only || state == .Direct_Children ||
		       state == .Complete_Subtree
	}
	if kind == .Global {
		return state == .Overview || state == .Contents || state == .Show_All
	}
	if kind == .Drawer {
		return state == .Drawer_Visible || state == .Drawer_Folded
	}
	return false
}

/* visibility_transition_descriptor copies immutable inspection for one live candidate. */
visibility_transition_descriptor :: proc(
	transition: ^Visibility_Transition,
) -> (Visibility_Transition_Descriptor, bool) {
	state := visibility_transition_state(transition)
	if state == nil do return {}, false
	return state.descriptor, true
}

/* visibility_transition_publish revalidates and installs one prepared range generation. */
visibility_transition_publish :: proc(
	transition: ^Visibility_Transition,
	registry: ^view.Registry,
) -> (result: Visibility_Result, ok: bool, failure: Failure) {
	state := visibility_transition_state(transition)
	if state == nil {
		return {}, false, editing_failure(.Publish_Visibility, .Invalid_Visibility, {})
	}
	descriptor := state.descriptor
	snapshot, snapshot_ok, snapshot_failure := view.snapshot(registry, descriptor.scope.view_handle)
	if !snapshot_ok {
		failure = editing_failure(.Publish_Visibility, .View_Failed, descriptor.scope)
		failure.view_failure = snapshot_failure
		return {}, false, failure
	}
	if !scope_matches_view(descriptor.scope, snapshot) {
		return {}, false, editing_failure(.Publish_Visibility, .Stale, descriptor.scope)
	}
	update, published, publish_failure := view.visibility_replace(
		registry,
		descriptor.scope.view_handle,
		state.ranges,
	)
	if !published {
		failure = editing_failure(.Publish_Visibility, .View_Failed, descriptor.scope)
		failure.view_failure = publish_failure
		return {}, false, failure
	}
	result = Visibility_Result{descriptor = descriptor, view = update}
	visibility_transition_close(transition)
	return result, true, {}
}

/* visibility_transition_close releases an unpublished copied candidate. */
visibility_transition_close :: proc(transition: ^Visibility_Transition) {
	state := visibility_transition_state(transition)
	if state == nil do return
	if state.ranges != nil do delete(state.ranges, state.allocator)
	allocator := state.allocator
	free(state, allocator)
	transition.state = nil
}

@(private)
scope_matches_view :: proc(scope: Scope, snapshot: view.Snapshot) -> bool {
	return scope.analysis.buffer_id == snapshot.buffer_id &&
	       scope.analysis.source_revision == snapshot.revision &&
	       scope.view_handle.view_id == snapshot.view_id &&
	       scope.view_handle.generation == snapshot.view_generation &&
	       scope.view_state_generation == snapshot.state_generation &&
	       scope.visibility_generation == snapshot.visibility_generation
}

@(private)
visibility_transition_state :: proc(
	transition: ^Visibility_Transition,
) -> ^Visibility_Transition_State_Data {
	if transition == nil || transition.state == nil do return nil
	return (^Visibility_Transition_State_Data)(transition.state)
}

@(private)
editing_failure :: proc(operation: Operation, code: Failure_Code, scope: Scope) -> Failure {
	return Failure{operation = operation, code = code, scope = scope}
}
