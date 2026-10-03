// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_editing

import "../language"
import "base:runtime"
import "core:unicode/utf8"

@(private)
Sparse_View_State :: struct {
	descriptor: Sparse_View_Descriptor,
	predicate:  Sparse_Predicate,
	text:       []u8,
	matches:    []Sparse_Match,
	allocator:  runtime.Allocator,
}

/* sparse_view_prepare derives one bounded projection from exact copied analysis. */
sparse_view_prepare :: proc(
	sparse: ^Sparse_View,
	analysis: ^language.Jan_Structural_Analysis,
	source: []u8,
	request: Sparse_View_Request,
	limits := DEFAULT_LIMITS,
	allocator := context.allocator,
	temporary_allocator := context.temp_allocator,
) -> (descriptor: Sparse_View_Descriptor, ok: bool, failure: Failure) {
	if sparse == nil || sparse.state != nil {
		return {}, false, editing_failure(.Derive_Sparse_View, .Invalid_Target, request.scope)
	}
	state, built, build_failure := sparse_view_state_build(
		analysis,
		source,
		request,
		limits,
		allocator,
		temporary_allocator,
		.Derive_Sparse_View,
	)
	if !built do return {}, false, build_failure
	sparse.state = state
	return state.descriptor, true, {}
}

/* sparse_view_refresh atomically replaces matches while retaining the predicate. */
sparse_view_refresh :: proc(
	sparse: ^Sparse_View,
	analysis: ^language.Jan_Structural_Analysis,
	source: []u8,
	scope: Scope,
	generation: Sparse_Generation,
	cancel_requested: ^bool = nil,
	temporary_allocator := context.temp_allocator,
) -> (descriptor: Sparse_View_Descriptor, ok: bool, failure: Failure) {
	current := sparse_view_state(sparse)
	if current == nil || generation == Sparse_Generation(0) ||
	   scope.analysis.buffer_id != current.descriptor.scope.analysis.buffer_id {
		return {}, false, editing_failure(.Refresh_Sparse_View, .Invalid_Target, scope)
	}
	request := Sparse_View_Request {
		operation_id = current.descriptor.operation_id,
		generation = generation,
		scope = scope,
		predicate = current.predicate,
		cancel_requested = cancel_requested,
	}
	if len(current.text) > 0 do request.predicate.text = string(current.text)
	replacement, built, build_failure := sparse_view_state_build(
		analysis,
		source,
		request,
		DEFAULT_LIMITS,
		current.allocator,
		temporary_allocator,
		.Refresh_Sparse_View,
	)
	if !built do return {}, false, build_failure
	sparse.state = replacement
	sparse_view_state_close(current)
	return replacement.descriptor, true, {}
}

/* sparse_view_descriptor copies immutable projection identity and accounting. */
sparse_view_descriptor :: proc(sparse: ^Sparse_View) -> (Sparse_View_Descriptor, bool) {
	state := sparse_view_state(sparse)
	if state == nil do return {}, false
	return state.descriptor, true
}

/* sparse_view_matches borrows copied matches until refresh or close. */
sparse_view_matches :: proc(sparse: ^Sparse_View) -> []Sparse_Match {
	state := sparse_view_state(sparse)
	if state == nil do return nil
	return state.matches
}

/* sparse_view_resolve_source returns one checked canonical source destination. */
sparse_view_resolve_source :: proc(
	sparse: ^Sparse_View,
	current_scope: Scope,
	index: u32,
) -> (result: Navigation_Result, ok: bool, failure: Failure) {
	state := sparse_view_state(sparse)
	result.kind = .Next_Visible_Heading
	if state == nil || state.descriptor.scope != current_scope {
		return result, false, editing_failure(.Navigate_Sparse_View, .Stale, current_scope)
	}
	if index >= u32(len(state.matches)) {
		result.status = .No_Target
		return result, true, {}
	}
	match := state.matches[index]
	result.status = .Resolved
	result.target = match.target
	result.position = match.position
	result.candidates = state.descriptor.match_count
	return result, true, {}
}

/* sparse_view_close releases copied matches and predicate text exactly once. */
sparse_view_close :: proc(sparse: ^Sparse_View) {
	state := sparse_view_state(sparse)
	if state == nil do return
	sparse_view_state_close(state)
	sparse.state = nil
}

@(private)
sparse_view_state_build :: proc(
	analysis: ^language.Jan_Structural_Analysis,
	source: []u8,
	request: Sparse_View_Request,
	limits: Limits,
	allocator: runtime.Allocator,
	temporary_allocator: runtime.Allocator,
	operation: Operation,
) -> (state: ^Sparse_View_State, ok: bool, failure: Failure) {
	if analysis == nil || !scope_is_valid(request.scope) ||
	   request.operation_id == Operation_ID(0) ||
	   request.generation == Sparse_Generation(0) || !limits_are_valid(limits) ||
	   allocator.procedure == nil || temporary_allocator.procedure == nil ||
	   !sparse_predicate_is_valid(request.predicate) || !utf8.valid_string(string(source)) {
		return nil, false, editing_failure(operation, .Invalid_Scope, request.scope)
	}
	if request.cancel_requested != nil && request.cancel_requested^ {
		return nil, false, editing_failure(operation, .Cancelled, request.scope)
	}
	nodes := language.jan_structural_analysis_nodes(analysis)
	usage, inspected := language.jan_structural_analysis_usage(analysis)
	if !inspected || usage.source_bytes != u64(len(source)) || len(nodes) == 0 ||
	   nodes[0].range.scope != request.scope.analysis {
		return nil, false, editing_failure(operation, .Stale, request.scope)
	}
	if len(language.jan_structural_analysis_recoveries(analysis)) > 0 {
		return nil, false, editing_failure(operation, .Malformed, request.scope)
	}
	candidates, candidate_error := make(
		[dynamic]Sparse_Match,
		0,
		min(len(nodes), int(limits.sparse_matches) + 1),
		temporary_allocator,
	)
	if candidate_error != nil {
		return nil, false, editing_failure(operation, .Allocation_Failed, request.scope)
	}
	defer delete(candidates)
	derived := sparse_view_derive_matches(
		&candidates,
		analysis,
		nodes,
		source,
		request,
		limits,
	)
	if !derived {
		if request.cancel_requested != nil && request.cancel_requested^ {
			return nil, false, editing_failure(operation, .Cancelled, request.scope)
		}
		failure = editing_failure(operation, .Limited, request.scope)
		failure.limit = u64(limits.sparse_matches)
		failure.actual = u64(len(candidates)) + 1
		return nil, false, failure
	}
	sparse_matches_sort(candidates[:])

	state, candidate_error = new(Sparse_View_State, allocator)
	if candidate_error != nil {
		return nil, false, editing_failure(operation, .Allocation_Failed, request.scope)
	}
	state^ = Sparse_View_State{allocator = allocator}
	if len(request.predicate.text) > 0 {
		state.text, candidate_error = make([]u8, len(request.predicate.text), allocator)
		if candidate_error == nil do copy(state.text, transmute([]u8)request.predicate.text)
	}
	if candidate_error == nil && len(candidates) > 0 {
		state.matches, candidate_error = make([]Sparse_Match, len(candidates), allocator)
		if candidate_error == nil do copy(state.matches, candidates[:])
	}
	if candidate_error != nil {
		sparse_view_state_close(state)
		return nil, false, editing_failure(operation, .Allocation_Failed, request.scope)
	}
	state.predicate = request.predicate
	if len(state.text) > 0 do state.predicate.text = string(state.text)
	direct_matches: u32
	for match in state.matches do if match.direct_match do direct_matches += 1
	state.descriptor = {
		operation_id = request.operation_id,
		generation = request.generation,
		scope = request.scope,
		match_count = u32(len(state.matches)),
		direct_matches = direct_matches,
		retained_bytes = u64(size_of(Sparse_View_State)) + u64(len(state.text)) +
		                 u64(len(state.matches)) * u64(size_of(Sparse_Match)),
	}
	return state, true, {}
}

@(private)
sparse_view_derive_matches :: proc(
	candidates: ^[dynamic]Sparse_Match,
	analysis: ^language.Jan_Structural_Analysis,
	nodes: []language.Jan_Node_Record,
	source: []u8,
	request: Sparse_View_Request,
	limits: Limits,
) -> bool {
	checked: u32
	if request.predicate.kind == .Indexed_Fact {
		for fact in language.jan_structural_analysis_indexes(analysis) {
			checked += 1
			if checked % limits.cancellation_entries == 0 && request.cancel_requested != nil &&
			   request.cancel_requested^ {
				return false
			}
			if fact.kind != request.predicate.index_kind do continue
			node, found := navigation_node_by_id(nodes, fact.node_id)
			if !found do continue
			heading := node
			heading_ok := node.kind == .Heading
			if !heading_ok do heading, heading_ok = sparse_enclosing_heading(nodes, node)
			if heading_ok && !sparse_append_heading_with_ancestors(candidates, nodes, heading, limits) {
				return false
			}
		}
		return true
	}
	for node in nodes {
		checked += 1
		if checked % limits.cancellation_entries == 0 && request.cancel_requested != nil &&
		   request.cancel_requested^ {
			return false
		}
		matched := false
		switch request.predicate.kind {
		case .Heading_Level:
			matched = node.kind == .Heading &&
			          node.structural_depth == request.predicate.heading_level
		case .Node_Kind:
			matched = node.kind == request.predicate.node_kind
		case .Text_Contains:
			if node.kind == .Heading {
				end := outline_heading_line_end(source, node)
				matched = sparse_bytes_contain(
					source[int(node.range.start):int(end)],
					transmute([]u8)request.predicate.text,
				)
			}
		case .Invalid, .Indexed_Fact:
		}
		if !matched do continue
		heading := node
		heading_ok := node.kind == .Heading
		if !heading_ok do heading, heading_ok = sparse_enclosing_heading(nodes, node)
		if heading_ok && !sparse_append_heading_with_ancestors(candidates, nodes, heading, limits) {
			return false
		}
	}
	return true
}

@(private)
sparse_append_heading_with_ancestors :: proc(
	candidates: ^[dynamic]Sparse_Match,
	nodes: []language.Jan_Node_Record,
	heading: language.Jan_Node_Record,
	limits: Limits,
) -> bool {
	if !sparse_append_unique_match(candidates, heading, true, limits) do return false
	parent_id := heading.parent_id
	for parent_id != language.Jan_Node_ID(0) {
		parent, found := navigation_node_by_id(nodes, parent_id)
		if !found do break
		if parent.kind == .Heading && !sparse_append_unique_match(candidates, parent, false, limits) {
			return false
		}
		parent_id = parent.parent_id
	}
	return true
}

@(private)
sparse_append_unique_match :: proc(
	candidates: ^[dynamic]Sparse_Match,
	heading: language.Jan_Node_Record,
	direct: bool,
	limits: Limits,
) -> bool {
	for &match in candidates^ {
		if match.target.node_id != heading.id do continue
		if direct {
			match.direct_match = true
			match.ancestor_context = false
		}
		return true
	}
	if len(candidates^) >= int(limits.sparse_matches) do return false
	match := Sparse_Match {
		target = navigation_target(heading),
		position = {
			buffer_id = heading.range.scope.buffer_id,
			revision = heading.range.scope.source_revision,
			byte_offset = heading.range.start,
		},
		direct_match = direct,
		ancestor_context = !direct,
	}
	_, append_error := append(candidates, match)
	return append_error == nil
}

@(private)
sparse_enclosing_heading :: proc(
	nodes: []language.Jan_Node_Record,
	node: language.Jan_Node_Record,
) -> (language.Jan_Node_Record, bool) {
	parent_id := node.parent_id
	for parent_id != language.Jan_Node_ID(0) {
		parent, found := navigation_node_by_id(nodes, parent_id)
		if !found do return {}, false
		if parent.kind == .Heading do return parent, true
		parent_id = parent.parent_id
	}
	return {}, false
}

@(private)
sparse_matches_sort :: proc(matches: []Sparse_Match) {
	for index in 1 ..< len(matches) {
		match := matches[index]
		cursor := index
		for cursor > 0 && match.position.byte_offset < matches[cursor - 1].position.byte_offset {
			matches[cursor] = matches[cursor - 1]
			cursor -= 1
		}
		matches[cursor] = match
	}
}

@(private)
sparse_predicate_is_valid :: proc(predicate: Sparse_Predicate) -> bool {
	switch predicate.kind {
	case .Heading_Level:
		return predicate.heading_level > 0 &&
		       predicate.heading_level <= language.MAX_JAN_STRUCTURAL_DEPTH
	case .Node_Kind:
		return language.jan_node_kind_is_valid(predicate.node_kind)
	case .Text_Contains:
		return len(predicate.text) > 0 &&
		       u64(len(predicate.text)) <= MAX_SPARSE_PREDICATE_BYTES &&
		       utf8.valid_string(predicate.text)
	case .Indexed_Fact:
		return predicate.index_kind >= .Heading && predicate.index_kind <= .Recovery_Region
	case .Invalid:
	}
	return false
}

@(private)
sparse_bytes_contain :: proc(source, needle: []u8) -> bool {
	if len(needle) == 0 do return true
	if len(source) < len(needle) do return false
	for start in 0 ..= len(source) - len(needle) {
		matches := true
		for index in 0 ..< len(needle) {
			if source[start + index] != needle[index] {
				matches = false
				break
			}
		}
		if matches do return true
	}
	return false
}

@(private)
sparse_view_state :: proc(sparse: ^Sparse_View) -> ^Sparse_View_State {
	if sparse == nil || sparse.state == nil do return nil
	return cast(^Sparse_View_State)sparse.state
}

@(private)
sparse_view_state_close :: proc(state: ^Sparse_View_State) {
	if state == nil do return
	allocator := state.allocator
	if state.matches != nil do delete(state.matches, allocator)
	if state.text != nil do delete(state.text, allocator)
	state^ = {}
	free(state, allocator)
}
