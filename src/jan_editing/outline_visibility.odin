// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_editing

import "../editor"
import "../language"
import "../view"

/* outline_visibility_prepare derives and copies one exact outline visibility transition. */
outline_visibility_prepare :: proc(
	transition: ^Visibility_Transition,
	registry: ^view.Registry,
	analysis: ^language.Jan_Structural_Analysis,
	source: []u8,
	request: Outline_Visibility_Request,
	limits := DEFAULT_LIMITS,
	allocator := context.allocator,
	temporary_allocator := context.temp_allocator,
) -> (descriptor: Visibility_Transition_Descriptor, ok: bool, failure: Failure) {
	if transition == nil || registry == nil || analysis == nil ||
	   !scope_is_valid(request.scope) || !limits_are_valid(limits) ||
	   request.operation_id == Operation_ID(0) || allocator.procedure == nil ||
	   temporary_allocator.procedure == nil {
		return {}, false, editing_failure(.Apply_Outline_Visibility, .Invalid_Scope, request.scope)
	}
	nodes := language.jan_structural_analysis_nodes(analysis)
	usage, inspected := language.jan_structural_analysis_usage(analysis)
	if !inspected || usage.source_bytes != u64(len(source)) || len(nodes) == 0 ||
	   nodes[0].range.scope != request.scope.analysis {
		return {}, false, editing_failure(.Apply_Outline_Visibility, .Stale, request.scope)
	}
	selected := request.selected
	if selected == .Invalid {
		if request.kind == .Local {
			selected, ok = local_visibility_next(request.current)
		} else if request.kind == .Global {
			selected, ok = global_visibility_next(request.current)
		}
		if !ok {
			return {}, false, editing_failure(
				.Apply_Outline_Visibility,
				.Invalid_Visibility,
				request.scope,
			)
		}
	}
	if !visibility_state_matches_kind(request.kind, selected) {
		return {}, false, editing_failure(
			.Apply_Outline_Visibility,
			.Invalid_Visibility,
			request.scope,
		)
	}
	capacity := min(len(nodes) + len(request.retained_ranges) * 2, int(limits.hidden_ranges) + 1)
	ranges, ranges_error := make([dynamic]view.Hidden_Range, 0, capacity, temporary_allocator)
	if ranges_error != nil {
		return {}, false, editing_failure(
			.Apply_Outline_Visibility,
			.Allocation_Failed,
			request.scope,
		)
	}
	defer delete(ranges)
	derived := false
	if request.kind == .Local {
		heading, found := navigation_node_by_id(nodes, request.heading_id)
		if !found || heading.kind != .Heading {
			return {}, false, editing_failure(
				.Apply_Outline_Visibility,
				.Invalid_Target,
				request.scope,
			)
		}
		if navigation_node_overlaps_recovery(
			heading,
			language.jan_structural_analysis_recoveries(analysis),
		) {
			return {}, false, editing_failure(
				.Apply_Outline_Visibility,
				.Malformed,
				request.scope,
			)
		}
		derived = outline_retain_outside_subtree(
			&ranges,
			request.retained_ranges,
			heading.range,
			request.scope,
			u64(len(source)),
			limits,
		)
		if derived {
			derived = outline_derive_local_ranges(&ranges, nodes, source, heading, selected, limits)
		}
	} else {
		derived = outline_derive_global_ranges(&ranges, nodes, source, selected, limits)
	}
	if !derived {
		failure = editing_failure(.Apply_Outline_Visibility, .Limited, request.scope)
		failure.limit = u64(limits.hidden_ranges)
		failure.actual = u64(len(ranges)) + 1
		return {}, false, failure
	}
	return visibility_transition_prepare(
		transition,
		registry,
		{
			operation_id = request.operation_id,
			scope = request.scope,
			kind = request.kind,
			current = request.current,
			selected = selected,
			ranges = ranges[:],
		},
		limits,
		allocator,
	)
}

/* outline_visibility_reveal_target reveals the minimum hidden target range before use. */
outline_visibility_reveal_target :: proc(
	registry: ^view.Registry,
	scope: Scope,
	target: Target,
	source_bytes: u64,
) -> (update: view.Visibility_Update, ok: bool, failure: Failure) {
	if registry == nil || !target_is_valid(target, scope, source_bytes) {
		return {}, false, editing_failure(.Apply_Outline_Visibility, .Invalid_Target, scope)
	}
	snapshot, snapshot_ok, snapshot_failure := view.snapshot(registry, scope.view_handle)
	if !snapshot_ok {
		failure = editing_failure(.Apply_Outline_Visibility, .View_Failed, scope)
		failure.view_failure = snapshot_failure
		return {}, false, failure
	}
	if !scope_matches_view(scope, snapshot) {
		return {}, false, editing_failure(.Apply_Outline_Visibility, .Stale, scope)
	}
	start := editor.Position {
		buffer_id = scope.analysis.buffer_id,
		revision = scope.analysis.source_revision,
		byte_offset = target.range.start,
	}
	end := start
	end.byte_offset = target.range.end
	update, ok, snapshot_failure = view.visibility_reveal_range(
		registry,
		scope.view_handle,
		start,
		end,
	)
	if !ok {
		failure = editing_failure(.Apply_Outline_Visibility, .View_Failed, scope)
		failure.view_failure = snapshot_failure
		return {}, false, failure
	}
	return update, true, {}
}

@(private)
outline_derive_local_ranges :: proc(
	ranges: ^[dynamic]view.Hidden_Range,
	nodes: []language.Jan_Node_Record,
	source: []u8,
	heading: language.Jan_Node_Record,
	selected: Visibility_State,
	limits: Limits,
) -> bool {
	if selected == .Complete_Subtree do return true
	header_end := outline_heading_line_end(source, heading)
	if selected == .Heading_Only {
		return outline_append_range(ranges, heading.range.scope, header_end, heading.range.end, limits)
	}
	cursor := header_end
	for node in nodes {
		if node.kind != .Heading || node.parent_id != heading.id do continue
		if node.range.start > cursor &&
		   !outline_append_range(ranges, heading.range.scope, cursor, node.range.start, limits) {
			return false
		}
		child_header_end := outline_heading_line_end(source, node)
		cursor = max(cursor, child_header_end)
		next_child_start := node.range.end
		for sibling in nodes {
			if sibling.kind == .Heading && sibling.parent_id == heading.id &&
			   sibling.range.start > node.range.start && sibling.range.start < next_child_start {
				next_child_start = sibling.range.start
			}
		}
		if next_child_start > cursor &&
		   !outline_append_range(ranges, heading.range.scope, cursor, next_child_start, limits) {
			return false
		}
		cursor = max(cursor, next_child_start)
	}
	if cursor < heading.range.end {
		return outline_append_range(ranges, heading.range.scope, cursor, heading.range.end, limits)
	}
	return true
}

@(private)
outline_derive_global_ranges :: proc(
	ranges: ^[dynamic]view.Hidden_Range,
	nodes: []language.Jan_Node_Record,
	source: []u8,
	selected: Visibility_State,
	limits: Limits,
) -> bool {
	if selected == .Show_All do return true
	for node in nodes {
		if node.kind != .Heading do continue
		if selected == .Overview && node.structural_depth != 1 do continue
		start := outline_heading_line_end(source, node)
		end := node.range.end
		if selected == .Contents {
			for next in nodes {
				if next.kind == .Heading && next.range.start > node.range.start &&
				   next.range.start < end {
					end = next.range.start
				}
			}
		}
		if !outline_append_range(ranges, node.range.scope, start, end, limits) do return false
	}
	return true
}

@(private)
outline_retain_outside_subtree :: proc(
	ranges: ^[dynamic]view.Hidden_Range,
	retained: []view.Hidden_Range,
	subtree: language.Jan_Source_Range,
	scope: Scope,
	source_bytes: u64,
	limits: Limits,
) -> bool {
	for hidden in retained {
		if !navigation_hidden_range_is_valid(hidden, scope, source_bytes) do return false
		if hidden.end.byte_offset <= subtree.start || hidden.start.byte_offset >= subtree.end {
			if !outline_append_positions(ranges, hidden.start, hidden.end, limits) do return false
			continue
		}
		if hidden.start.byte_offset < subtree.start {
			end := hidden.end
			end.byte_offset = subtree.start
			if !outline_append_positions(ranges, hidden.start, end, limits) do return false
		}
		if hidden.end.byte_offset > subtree.end {
			start := hidden.start
			start.byte_offset = subtree.end
			if !outline_append_positions(ranges, start, hidden.end, limits) do return false
		}
	}
	return true
}

@(private)
outline_append_range :: proc(
	ranges: ^[dynamic]view.Hidden_Range,
	scope: language.Jan_Analysis_Scope,
	start, end: editor.Byte_Offset,
	limits: Limits,
) -> bool {
	if start >= end do return true
	return outline_append_positions(
		ranges,
		{buffer_id = scope.buffer_id, revision = scope.source_revision, byte_offset = start},
		{buffer_id = scope.buffer_id, revision = scope.source_revision, byte_offset = end},
		limits,
	)
}

@(private)
outline_append_positions :: proc(
	ranges: ^[dynamic]view.Hidden_Range,
	start, end: editor.Position,
	limits: Limits,
) -> bool {
	if len(ranges^) >= int(limits.hidden_ranges) do return false
	_, append_error := append(ranges, view.Hidden_Range{start = start, end = end})
	return append_error == nil
}

@(private)
outline_heading_line_end :: proc(
	source: []u8,
	heading: language.Jan_Node_Record,
) -> editor.Byte_Offset {
	cursor := int(heading.range.start)
	limit := min(int(heading.range.end), len(source))
	for cursor < limit && source[cursor] != '\r' && source[cursor] != '\n' do cursor += 1
	if cursor < limit && source[cursor] == '\r' do cursor += 1
	if cursor < limit && source[cursor] == '\n' do cursor += 1
	return editor.Byte_Offset(cursor)
}
