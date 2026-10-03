// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_editing

import "../language"
import "base:runtime"

@(private)
Structural_Region_State :: struct {
	descriptor: Structural_Region_Descriptor,
	targets:    []Target,
	allocator:  runtime.Allocator,
}

/* structural_region_prepare validates and owns one sorted complete target set. */
structural_region_prepare :: proc(
	region: ^Structural_Region,
	analysis: ^language.Jan_Structural_Analysis,
	source_bytes: u64,
	operation_id: Operation_ID,
	scope: Scope,
	targets: []Target,
	limits := DEFAULT_LIMITS,
	allocator := context.allocator,
) -> (descriptor: Structural_Region_Descriptor, ok: bool, failure: Failure) {
	if region == nil || region.state != nil || analysis == nil ||
	   operation_id == Operation_ID(0) || !scope_is_valid(scope) ||
	   !limits_are_valid(limits) || allocator.procedure == nil {
		return {}, false, editing_failure(.Validate_Structural_Region, .Invalid_Scope, scope)
	}
	nodes := language.jan_structural_analysis_nodes(analysis)
	usage, inspected := language.jan_structural_analysis_usage(analysis)
	if !inspected || usage.source_bytes != source_bytes || len(nodes) == 0 ||
	   nodes[0].range.scope != scope.analysis {
		return {}, false, editing_failure(.Validate_Structural_Region, .Stale, scope)
	}
	if len(targets) == 0 || u64(len(targets)) > u64(limits.semantic_targets) {
		failure = editing_failure(.Validate_Structural_Region, .Limited, scope)
		failure.limit = u64(limits.semantic_targets)
		failure.actual = u64(len(targets))
		return {}, false, failure
	}
	for target in targets {
		if target.range.scope != scope.analysis {
			return {}, false, editing_failure(.Validate_Structural_Region, .Stale, scope)
		}
		if !structural_region_target_is_complete(target, scope, source_bytes, nodes) {
			return {}, false, editing_failure(.Validate_Structural_Region, .Invalid_Target, scope)
		}
		node, _ := navigation_node_by_id(nodes, target.node_id)
		if navigation_node_overlaps_recovery(
			node,
			language.jan_structural_analysis_recoveries(analysis),
		) {
			return {}, false, editing_failure(.Validate_Structural_Region, .Malformed, scope)
		}
	}
	state, state_error := new(Structural_Region_State, allocator)
	if state_error != nil {
		return {}, false, editing_failure(.Validate_Structural_Region, .Allocation_Failed, scope)
	}
	state^ = Structural_Region_State{allocator = allocator}
	state.targets, state_error = make([]Target, len(targets), allocator)
	if state_error != nil {
		free(state, allocator)
		return {}, false, editing_failure(.Validate_Structural_Region, .Allocation_Failed, scope)
	}
	copy(state.targets, targets)
	structural_region_sort(state.targets)
	for index in 1 ..< len(state.targets) {
		if state.targets[index].range.start < state.targets[index - 1].range.end {
			structural_region_state_close(state)
			return {}, false, editing_failure(.Validate_Structural_Region, .Invalid_Target, scope)
		}
	}
	state.descriptor = {
		operation_id = operation_id,
		scope = scope,
		target_count = u32(len(state.targets)),
		retained_bytes = u64(size_of(Structural_Region_State)) +
		                 u64(len(state.targets)) * u64(size_of(Target)),
	}
	region.state = state
	return state.descriptor, true, {}
}

/* structural_region_plan_prepare validates all replacements before one atomic plan. */
structural_region_plan_prepare :: proc(
	plan: ^language.Jan_Rewrite_Plan,
	region: ^Structural_Region,
	analysis: ^language.Jan_Structural_Analysis,
	source: []u8,
	generation: language.Jan_Rewrite_Generation,
	replacements: []string,
	limits := DEFAULT_LIMITS,
	allocator := context.allocator,
	temporary_allocator := context.temp_allocator,
) -> (ok: bool, failure: Failure) {
	state := structural_region_state(region)
	if plan == nil || state == nil || analysis == nil ||
	   generation == language.Jan_Rewrite_Generation(0) ||
	   len(replacements) != len(state.targets) || !limits_are_valid(limits) ||
	   allocator.procedure == nil || temporary_allocator.procedure == nil {
		scope: Scope
		if state != nil do scope = state.descriptor.scope
		return false, editing_failure(.Plan_Structural_Region, .Invalid_Scope, scope)
	}
	nodes := language.jan_structural_analysis_nodes(analysis)
	usage, inspected := language.jan_structural_analysis_usage(analysis)
	if !inspected || usage.source_bytes != u64(len(source)) || len(nodes) == 0 ||
	   nodes[0].range.scope != state.descriptor.scope.analysis {
		return false, editing_failure(.Plan_Structural_Region, .Stale, state.descriptor.scope)
	}
	requests, requests_error := make([]language.Jan_Rewrite_Request, len(state.targets), temporary_allocator)
	if requests_error != nil {
		return false, editing_failure(.Plan_Structural_Region, .Allocation_Failed, state.descriptor.scope)
	}
	defer delete(requests, temporary_allocator)
	for target, index in state.targets {
		if !structural_region_target_is_complete(
			target,
			state.descriptor.scope,
			u64(len(source)),
			nodes,
		) {
			return false, editing_failure(.Plan_Structural_Region, .Stale, state.descriptor.scope)
		}
		requests[index] = {
			node_id = target.node_id,
			range = target.range,
			replacement = replacements[index],
		}
	}
	jan_limits := language.DEFAULT_JAN_RESOURCE_LIMITS
	jan_limits.rewrite_splices = min(jan_limits.rewrite_splices, limits.rewrite_splices)
	planned, jan_failure := language.jan_rewrite_plan_prepare(
		plan,
		analysis,
		source,
		generation,
		requests,
		jan_limits,
		allocator,
	)
	if !planned do return false, structural_region_failure_from_language(jan_failure, state.descriptor.scope)
	return true, {}
}

/* structural_region_descriptor returns copied immutable accounting. */
structural_region_descriptor :: proc(region: ^Structural_Region) -> (Structural_Region_Descriptor, bool) {
	state := structural_region_state(region)
	if state == nil do return {}, false
	return state.descriptor, true
}

/* structural_region_targets returns region-owned targets in source order. */
structural_region_targets :: proc(region: ^Structural_Region) -> []Target {
	state := structural_region_state(region)
	if state == nil do return nil
	return state.targets
}

/* structural_region_is_valid reports whether the region owns live state. */
structural_region_is_valid :: proc(region: ^Structural_Region) -> bool {
	return structural_region_state(region) != nil
}

/* structural_region_close releases every region-owned target. */
structural_region_close :: proc(region: ^Structural_Region) {
	if region == nil do return
	state := structural_region_state(region)
	if state != nil do structural_region_state_close(state)
	region^ = {}
}

@(private)
structural_region_state :: proc(region: ^Structural_Region) -> ^Structural_Region_State {
	if region == nil || region.state == nil do return nil
	return (^Structural_Region_State)(region.state)
}

@(private)
structural_region_state_close :: proc(state: ^Structural_Region_State) {
	if state == nil do return
	if state.targets != nil do delete(state.targets, state.allocator)
	allocator := state.allocator
	state^ = {}
	free(state, allocator)
}

@(private)
structural_region_target_is_complete :: proc(
	target: Target,
	scope: Scope,
	source_bytes: u64,
	nodes: []language.Jan_Node_Record,
) -> bool {
	if !target_is_valid(target, scope, source_bytes) || target.node_id == language.Jan_Node_ID(0) ||
	   target.kind == .Document || target.kind == .Region {
		return false
	}
	node, found := navigation_node_by_id(nodes, target.node_id)
	return found && node.range == target.range && navigation_target(node).kind == target.kind
}

@(private)
structural_region_sort :: proc(targets: []Target) {
	for index in 1 ..< len(targets) {
		target := targets[index]
		cursor := index
		for cursor > 0 && target.range.start < targets[cursor - 1].range.start {
			targets[cursor] = targets[cursor - 1]
			cursor -= 1
		}
		targets[cursor] = target
	}
}

@(private)
structural_region_failure_from_language :: proc(jan: language.Jan_Failure, scope: Scope) -> Failure {
	code := Failure_Code.Invalid_Target
	#partial switch jan.code {
	case .Stale, .Incomplete: code = .Stale
	case .Limited: code = .Limited
	case .Allocation_Failed: code = .Allocation_Failed
	case .Malformed: code = .Malformed
	case .Cancelled: code = .Cancelled
	}
	return {operation = .Plan_Structural_Region, code = code, scope = scope, limit = jan.limit, actual = jan.actual}
}
