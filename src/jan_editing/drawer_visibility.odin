// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_editing

import "../language"
import "../view"

/* drawer_visibility_prepare copies one exact view-local drawer toggle candidate. */
drawer_visibility_prepare :: proc(
	transition: ^Visibility_Transition,
	registry: ^view.Registry,
	analysis: ^language.Jan_Structural_Analysis,
	source: []u8,
	request: Drawer_Visibility_Request,
	limits := DEFAULT_LIMITS,
	allocator := context.allocator,
	temporary_allocator := context.temp_allocator,
) -> (descriptor: Visibility_Transition_Descriptor, ok: bool, failure: Failure) {
	if transition == nil || registry == nil || analysis == nil ||
	   request.operation_id == Operation_ID(0) || !scope_is_valid(request.scope) ||
	   !limits_are_valid(limits) || allocator.procedure == nil ||
	   temporary_allocator.procedure == nil {
		return {}, false, editing_failure(
			.Apply_Drawer_Visibility,
			.Invalid_Scope,
			request.scope,
		)
	}
	inspection, inspected, inspection_failure := structure_inspect(
		analysis,
		source,
		request.scope,
		request.target_id,
	)
	if !inspected {
		inspection_failure.operation = .Apply_Drawer_Visibility
		return {}, false, inspection_failure
	}
	if inspection.target.kind != .Drawer || !inspection.foldable {
		return {}, false, editing_failure(
			.Apply_Drawer_Visibility,
			.Invalid_Target,
			request.scope,
		)
	}
	snapshot, snapshot_ok, snapshot_failure := view.snapshot(registry, request.scope.view_handle)
	if !snapshot_ok {
		return {}, false, drawer_visibility_view_failure(request.scope, snapshot_failure)
	}
	if !scope_matches_view(request.scope, snapshot) {
		return {}, false, editing_failure(
			.Apply_Drawer_Visibility,
			.Stale,
			request.scope,
		)
	}
	if snapshot.hidden_range_count > limits.hidden_ranges {
		failure = editing_failure(.Apply_Drawer_Visibility, .Limited, request.scope)
		failure.limit = u64(limits.hidden_ranges)
		failure.actual = u64(snapshot.hidden_range_count)
		return {}, false, failure
	}
	current, current_error := make(
		[]view.Hidden_Range,
		int(snapshot.hidden_range_count),
		temporary_allocator,
	)
	if current_error != nil {
		return {}, false, editing_failure(
			.Apply_Drawer_Visibility,
			.Allocation_Failed,
			request.scope,
		)
	}
	defer delete(current, temporary_allocator)
	copied, copied_ok, copy_failure := view.visibility_copy_ranges(
		registry,
		request.scope.view_handle,
		current,
	)
	if !copied_ok {
		return {}, false, drawer_visibility_view_failure(request.scope, copy_failure)
	}
	if copied.generation != request.scope.visibility_generation ||
	   copied.source_revision != request.scope.analysis.source_revision ||
	   copied.range_count != snapshot.hidden_range_count {
		return {}, false, editing_failure(
			.Apply_Drawer_Visibility,
			.Stale,
			request.scope,
		)
	}

	folded := false
	for hidden in current {
		if drawer_visibility_range_equal(hidden, inspection.fold_range) {
			folded = true
			continue
		}
		if drawer_visibility_range_overlaps_source(hidden, inspection.selection) {
			return {}, false, editing_failure(
				.Apply_Drawer_Visibility,
				.Hidden_Target,
				request.scope,
			)
		}
	}
	candidate_count := len(current) + 1
	if folded do candidate_count = len(current) - 1
	if u64(candidate_count) > u64(limits.hidden_ranges) {
		failure = editing_failure(.Apply_Drawer_Visibility, .Limited, request.scope)
		failure.limit = u64(limits.hidden_ranges)
		failure.actual = u64(candidate_count)
		return {}, false, failure
	}
	candidate, candidate_error := make(
		[]view.Hidden_Range,
		candidate_count,
		temporary_allocator,
	)
	if candidate_error != nil {
		return {}, false, editing_failure(
			.Apply_Drawer_Visibility,
			.Allocation_Failed,
			request.scope,
		)
	}
	defer delete(candidate, temporary_allocator)
	write_index := 0
	for hidden in current {
		if folded && drawer_visibility_range_equal(hidden, inspection.fold_range) do continue
		candidate[write_index] = hidden
		write_index += 1
	}
	if !folded {
		candidate[write_index] = inspection.fold_range
		write_index += 1
	}
	assert(write_index == len(candidate))
	current_state := Visibility_State.Drawer_Visible
	next_state := Visibility_State.Drawer_Folded
	if folded {
		current_state = .Drawer_Folded
		next_state = .Drawer_Visible
	}
	return visibility_transition_prepare(
		transition,
		registry,
		{
			operation_id = request.operation_id,
			scope = request.scope,
			kind = .Drawer,
			current = current_state,
			selected = next_state,
			ranges = candidate,
		},
		limits,
		allocator,
	)
}

@(private)
drawer_visibility_range_equal :: proc(left, right: view.Hidden_Range) -> bool {
	return left.start == right.start && left.end == right.end
}

@(private)
drawer_visibility_range_overlaps_source :: proc(
	hidden: view.Hidden_Range,
	source: language.Jan_Source_Range,
) -> bool {
	return hidden.start.buffer_id == source.scope.buffer_id &&
	       hidden.start.revision == source.scope.source_revision &&
	       hidden.start.byte_offset < source.end &&
	       hidden.end.byte_offset > source.start
}

@(private)
drawer_visibility_view_failure :: proc(
	scope: Scope,
	view_failure: view.Failure_Context,
) -> Failure {
	failure := editing_failure(.Apply_Drawer_Visibility, .View_Failed, scope)
	failure.view_failure = view_failure
	return failure
}
