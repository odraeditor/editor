// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language

import "base:runtime"

import "../editor"
import "../transaction"

/* Jan_Rewrite_Request proposes replacement text for one exact owned node range. */
Jan_Rewrite_Request :: struct {
	node_id:     Jan_Node_ID,
	range:       Jan_Source_Range,
	replacement: string,
}

/* Jan_Rewrite_Plan owns checked edits and their bounded replacement arena. */
Jan_Rewrite_Plan :: struct {
	state: rawptr,
}

@(private)
Jan_Rewrite_Plan_State :: struct {
	descriptor: Jan_Rewrite_Plan_Descriptor,
	edits:      []Jan_Rewrite_Edit,
	arena:      []u8,
	batch:      []transaction.Base_Splice,
	allocator:  runtime.Allocator,
}

@(private)
Jan_Rewrite_Candidate :: struct {
	range:       Jan_Source_Range,
	replacement: []u8,
}

/* jan_rewrite_plan_prepare validates ownership and copies one minimal splice set. */
jan_rewrite_plan_prepare :: proc(
	plan: ^Jan_Rewrite_Plan,
	analysis: ^Jan_Structural_Analysis,
	source: []u8,
	generation: Jan_Rewrite_Generation,
	requests: []Jan_Rewrite_Request,
	limits := DEFAULT_JAN_RESOURCE_LIMITS,
	allocator := context.allocator,
) -> (ok: bool, failure: Jan_Failure) {
	assert(plan != nil)
	assert(plan.state == nil, "Jan rewrite plan is already initialized")
	analysis_state := jan_structural_analysis_state(analysis)
	if analysis_state == nil || analysis_state.status != .Current {
		return false, jan_rewrite_failure({}, .Incomplete)
	}
	scope := analysis_state.scope
	if generation == Jan_Rewrite_Generation(0) || !jan_resource_limits_are_valid(limits) {
		return false, jan_rewrite_failure(scope, .Invalid_Rewrite)
	}
	if allocator.procedure == nil do return false, jan_rewrite_failure(scope, .Allocation_Failed)
	if len(requests) == 0 || u64(len(requests)) > u64(limits.rewrite_splices) {
		failure = jan_rewrite_failure(scope, .Limited)
		failure.limit = u64(limits.rewrite_splices)
		failure.actual = u64(len(requests))
		return false, failure
	}
	if u64(len(source)) != analysis_state.usage.source_bytes {
		return false, jan_rewrite_failure(scope, .Stale)
	}
	candidates, candidate_error := make([]Jan_Rewrite_Candidate, len(requests), allocator)
	if candidate_error != nil do return false, jan_rewrite_failure(scope, .Allocation_Failed)
	defer delete(candidates, allocator)
	replacement_bytes: u64
	for request, index in requests {
		if request.range.scope != scope {
			return false, jan_rewrite_failure(scope, .Stale)
		}
		if !jan_source_range_is_valid(request.range, u64(len(source))) {
			return false, jan_rewrite_failure(scope, .Invalid_Range)
		}
		if !jan_rewrite_range_has_exact_owner(analysis_state, request) {
			return false, jan_rewrite_failure(scope, .Invalid_Node)
		}
		start := int(request.range.start)
		end := int(request.range.end)
		replacement := transmute([]u8)request.replacement
		prefix, suffix := jan_rewrite_common_edges(source[start:end], replacement)
		minimal_start := start + prefix
		minimal_end := end - suffix
		replacement_end := len(replacement) - suffix
		if minimal_start == minimal_end && prefix == replacement_end {
			return false, jan_rewrite_failure(scope, .Invalid_Rewrite)
		}
		minimal_replacement := replacement[prefix:replacement_end]
		if !jan_source_offset_is_utf8_boundary(source, u32(minimal_start)) ||
		   !jan_source_offset_is_utf8_boundary(source, u32(minimal_end)) {
			return false, jan_rewrite_failure(scope, .Invalid_Range)
		}
		candidates[index] = Jan_Rewrite_Candidate {
			range = {
				scope = scope,
				start = editor.Byte_Offset(minimal_start),
				end = editor.Byte_Offset(minimal_end),
			},
			replacement = minimal_replacement,
		}
		if u64(len(minimal_replacement)) > max(u64) - replacement_bytes {
			return false, jan_rewrite_failure(scope, .Limited)
		}
		replacement_bytes += u64(len(minimal_replacement))
	}
	jan_rewrite_candidates_sort(candidates)
	for index in 1 ..< len(candidates) {
		previous := candidates[index - 1].range
		current := candidates[index].range
		if current.start < previous.end {
			return false, jan_rewrite_failure(scope, .Invalid_Rewrite)
		}
		if current.start == previous.start {
			return false, jan_rewrite_failure(scope, .Invalid_Rewrite)
		}
	}
	metadata_bytes := u64(len(candidates)) *
		(u64(size_of(Jan_Rewrite_Edit)) + u64(size_of(transaction.Base_Splice)))
	if metadata_bytes > limits.rewrite_bytes || replacement_bytes > limits.rewrite_bytes - metadata_bytes {
		failure = jan_rewrite_failure(scope, .Limited)
		failure.limit = limits.rewrite_bytes
		failure.actual = replacement_bytes + metadata_bytes
		return false, failure
	}

	state, state_error := new(Jan_Rewrite_Plan_State, allocator)
	if state_error != nil do return false, jan_rewrite_failure(scope, .Allocation_Failed)
	state^ = Jan_Rewrite_Plan_State{allocator = allocator}
	state.edits, state_error = make([]Jan_Rewrite_Edit, len(candidates), allocator)
	if state_error == nil do state.batch, state_error = make([]transaction.Base_Splice, len(candidates), allocator)
	if state_error == nil && replacement_bytes > 0 {
		state.arena, state_error = make([]u8, int(replacement_bytes), allocator)
	}
	if state_error != nil {
		jan_rewrite_plan_state_close(state)
		return false, jan_rewrite_failure(scope, .Allocation_Failed)
	}
	offset: u64
	for candidate, index in candidates {
		count := u64(len(candidate.replacement))
		if count > 0 do copy(state.arena[int(offset):int(offset + count)], candidate.replacement)
		state.edits[index] = Jan_Rewrite_Edit {
			range = candidate.range,
			replacement_offset = offset,
			replacement_bytes = count,
		}
		replacement := ""
		if count > 0 do replacement = string(state.arena[int(offset):int(offset + count)])
		state.batch[index] = transaction.Base_Splice {
			start = {
				buffer_id = scope.buffer_id,
				revision = scope.source_revision,
				byte_offset = candidate.range.start,
			},
			end = {
				buffer_id = scope.buffer_id,
				revision = scope.source_revision,
				byte_offset = candidate.range.end,
			},
			replacement = replacement,
		}
		offset += count
	}
	state.descriptor = Jan_Rewrite_Plan_Descriptor {
		generation = generation,
		scope = scope,
		splice_count = u32(len(candidates)),
		replacement_bytes = replacement_bytes,
		metadata_bytes = metadata_bytes,
	}
	plan.state = state
	return true, {}
}

/* jan_rewrite_plan_descriptor returns copied bounded plan accounting. */
jan_rewrite_plan_descriptor :: proc(plan: ^Jan_Rewrite_Plan) -> (Jan_Rewrite_Plan_Descriptor, bool) {
	state := jan_rewrite_plan_state(plan)
	if state == nil do return {}, false
	return state.descriptor, true
}

/* jan_rewrite_plan_edits returns plan-owned minimal edit descriptors. */
jan_rewrite_plan_edits :: proc(plan: ^Jan_Rewrite_Plan) -> []Jan_Rewrite_Edit {
	state := jan_rewrite_plan_state(plan)
	if state == nil do return nil
	return state.edits
}

/* jan_rewrite_plan_transaction_batch returns the ordinary borrowed transaction adapter. */
jan_rewrite_plan_transaction_batch :: proc(plan: ^Jan_Rewrite_Plan) -> []transaction.Base_Splice {
	state := jan_rewrite_plan_state(plan)
	if state == nil do return nil
	return state.batch
}

/* jan_rewrite_plan_replacement returns one checked plan-owned replacement slice. */
jan_rewrite_plan_replacement :: proc(
	plan: ^Jan_Rewrite_Plan,
	edit: Jan_Rewrite_Edit,
) -> (string, bool) {
	state := jan_rewrite_plan_state(plan)
	if state == nil || edit.range.scope != state.descriptor.scope ||
	   edit.replacement_offset > u64(len(state.arena)) ||
	   edit.replacement_bytes > u64(len(state.arena)) - edit.replacement_offset {
		return "", false
	}
	start := int(edit.replacement_offset)
	end := int(edit.replacement_offset + edit.replacement_bytes)
	return string(state.arena[start:end]), true
}

/* jan_rewrite_plan_admit prepares the plan through the ordinary transaction boundary. */
jan_rewrite_plan_admit :: proc(
	plan: ^Jan_Rewrite_Plan,
	buffer: ^editor.Buffer,
	root: ^transaction.Multibuffer_Transaction,
	transaction_id: transaction.Transaction_ID,
	undo_unit_id: transaction.Undo_Unit_ID,
	command: string,
	allocators: transaction.Allocator_Set,
	limits := transaction.DEFAULT_LIMITS,
) -> (ok: bool, failure: Jan_Failure) {
	state := jan_rewrite_plan_state(plan)
	if state == nil || buffer == nil || root == nil {
		return false, jan_rewrite_failure({}, .Invalid_Rewrite)
	}
	scope := state.descriptor.scope
	stats, stats_ok, _ := editor.buffer_stats(buffer)
	if !stats_ok || stats.buffer_id != scope.buffer_id || stats.revision != scope.source_revision {
		return false, jan_rewrite_failure(scope, .Stale)
	}
	snapshots := [1]transaction.Proposal_Snapshot{{
		buffer = buffer,
		buffer_id = scope.buffer_id,
		base_revision = scope.source_revision,
	}}
	edits := [1]transaction.Proposal_Edit{{
		buffer_id = scope.buffer_id,
		base_revision = scope.source_revision,
		batch = state.batch,
	}}
	admitted, transaction_failure := transaction.proposal_admit(
		root,
		transaction_id,
		undo_unit_id,
		transaction.Edit_Proposal {
			origin = {kind = .Language_Tool, descriptor = "jan"},
			command = command,
			snapshots = snapshots[:],
			edits = edits[:],
		},
		allocators,
		limits,
	)
	if admitted do return true, {}
	code := Jan_Failure_Code.Invalid_Rewrite
	if transaction_failure.code == .Wrong_Buffer || transaction_failure.code == .Stale_Revision ||
	   transaction_failure.code == .Mismatched_Revision {
		code = .Stale
	}
	failure = jan_rewrite_failure(scope, code)
	failure.limit = transaction_failure.limit
	failure.actual = transaction_failure.actual
	return false, failure
}

/* jan_rewrite_plan_close releases the copied arena and descriptors exactly once. */
jan_rewrite_plan_close :: proc(plan: ^Jan_Rewrite_Plan) {
	state := jan_rewrite_plan_state(plan)
	if state == nil do return
	jan_rewrite_plan_state_close(state)
	plan^ = {}
}

@(private)
jan_rewrite_range_has_exact_owner :: proc(
	state: ^Jan_Structural_Analysis_State,
	request: Jan_Rewrite_Request,
) -> bool {
	if request.node_id != Jan_Node_ID(0) {
		index := int(request.node_id) - 1
		return index >= 0 && index < len(state.nodes) && state.nodes[index].range == request.range
	}
	matches := 0
	for node in state.nodes {
		if node.range == request.range do matches += 1
	}
	return matches == 1
}

@(private)
jan_rewrite_common_edges :: proc(source, replacement: []u8) -> (prefix, suffix: int) {
	limit := min(len(source), len(replacement))
	for prefix < limit && source[prefix] == replacement[prefix] do prefix += 1
	for prefix > 0 && (!jan_rewrite_utf8_boundary(source, prefix) ||
	                    !jan_rewrite_utf8_boundary(replacement, prefix)) {
		prefix -= 1
	}
	remaining_source := len(source) - prefix
	remaining_replacement := len(replacement) - prefix
	for suffix < remaining_source && suffix < remaining_replacement &&
	    source[len(source) - suffix - 1] == replacement[len(replacement) - suffix - 1] {
		suffix += 1
	}
	for suffix > 0 &&
	    (!jan_rewrite_utf8_boundary(source, len(source) - suffix) ||
	     !jan_rewrite_utf8_boundary(replacement, len(replacement) - suffix)) {
		suffix -= 1
	}
	return
}

@(private)
jan_rewrite_utf8_boundary :: proc(source: []u8, offset: int) -> bool {
	if offset == 0 || offset == len(source) do return true
	if offset < 0 || offset > len(source) do return false
	return source[offset] & 0xc0 != 0x80
}

@(private)
jan_rewrite_candidates_sort :: proc(candidates: []Jan_Rewrite_Candidate) {
	for index in 1 ..< len(candidates) {
		candidate := candidates[index]
		cursor := index
		for cursor > 0 &&
		    (candidate.range.start < candidates[cursor - 1].range.start ||
		     (candidate.range.start == candidates[cursor - 1].range.start &&
		      candidate.range.end < candidates[cursor - 1].range.end)) {
			candidates[cursor] = candidates[cursor - 1]
			cursor -= 1
		}
		candidates[cursor] = candidate
	}
}

@(private)
jan_rewrite_plan_state :: proc(plan: ^Jan_Rewrite_Plan) -> ^Jan_Rewrite_Plan_State {
	if plan == nil || plan.state == nil do return nil
	return cast(^Jan_Rewrite_Plan_State)plan.state
}

@(private)
jan_rewrite_plan_state_close :: proc(state: ^Jan_Rewrite_Plan_State) {
	if state == nil do return
	allocator := state.allocator
	if state.batch != nil do delete(state.batch, allocator)
	if state.arena != nil do delete(state.arena, allocator)
	if state.edits != nil do delete(state.edits, allocator)
	state^ = {}
	free(state, allocator)
}

@(private)
jan_rewrite_failure :: proc(scope: Jan_Analysis_Scope, code: Jan_Failure_Code) -> Jan_Failure {
	return Jan_Failure{operation = .Plan_Rewrite, code = code, scope = scope}
}
