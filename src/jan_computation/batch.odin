// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_computation

import "core:slice"

/* Batch_Target_State identifies one deterministic execution/publication outcome. */
Batch_Target_State :: enum u8 {
	Invalid,
	Ready,
	Cache_Hit,
	Completed,
	Rejected,
	Unattempted,
	Cancelled,
}

/* Batch_Target_Request is one copied-order candidate for explicit batch execution. */
Batch_Target_Request :: struct {
	operation_id: Operation_ID,
	document_id:  u64,
	source_start: u64,
	scope:        Scope,
	target:       Semantic_Target,
	authority:    Authority_Result,
	adapter:      Adapter_Selection,
	cache_state:  Cache_State,
}

/* Batch_Plan describes an admitted stable execution order. */
Batch_Plan :: struct {
	batch_id:       Batch_ID,
	mode:           Batch_Mode,
	target_count:   u32,
	concurrency:    u16,
	cache_hits:     u32,
	ready_count:    u32,
	complete:       bool,
}

/* Batch_Target_Outcome attributes one exact target result. */
Batch_Target_Outcome :: struct {
	operation_id: Operation_ID,
	state:        Batch_Target_State,
	failure:      Failure_Code,
	byte_count:   u64,
	row_count:    u32,
}

/* Batch_Summary separates execution from atomic publication accounting. */
Batch_Summary :: struct {
	descriptor:  Batch_Descriptor,
	executed:    u32,
	cache_hits:  u32,
	published:   u32,
	rejected:    u32,
	unattempted: u32,
	cancelled:   u32,
	output_bytes: u64,
	result_rows:  u64,
	complete:    bool,
}

/* prepare_execution_batch copies a deterministic admitted order. */
prepare_execution_batch :: proc(
	batch_id: Batch_ID,
	mode: Batch_Mode,
	concurrency: u16,
	requests: []Batch_Target_Request,
	ordered: []Batch_Target_Request,
	limits := DEFAULT_LIMITS,
) -> (Batch_Plan, bool, Failure) {
	if batch_id == Batch_ID(0) || mode == .Invalid || concurrency == 0 ||
	   concurrency > limits.child_processes || len(requests) == 0 ||
	   len(requests) > int(limits.executable_targets) || len(ordered) < len(requests) {
		return {}, false, batch_failure(batch_id, .Invalid_Request, .Batch)
	}
	copy(ordered, requests)
	slice.sort_by(ordered[:len(requests)], batch_target_less)
	plan := Batch_Plan {batch_id = batch_id, mode = mode, target_count = u32(len(requests)),
	                   concurrency = concurrency, complete = true}
	for request, index in ordered[:len(requests)] {
		if request.operation_id == Operation_ID(0) || request.document_id == 0 ||
		   !scope_is_valid(request.scope) || !semantic_target_is_valid(request.target, request.scope) ||
		   u64(request.target.range.start) != request.source_start || request.authority.operation_id != request.operation_id ||
		   request.authority.decision != .Allow || !request.authority.explicit_trigger ||
		   request.authority.policy_generation != request.scope.policy_generation ||
		   request.adapter.state != .Selected || request.adapter.adapter_generation != request.scope.adapter_generation {
			return {}, false, batch_failure(batch_id, .Unauthorized, .Authority)
		}
		if index > 0 && ordered[index - 1].operation_id == request.operation_id {
			return {}, false, batch_failure(batch_id, .Conflict, .Target)
		}
		if request.cache_state == .Hit do plan.cache_hits += 1
		if request.cache_state != .Hit do plan.ready_count += 1
	}
	return plan, true, {}
}

/* summarize_execution_batch validates exact outcomes and publication semantics. */
summarize_execution_batch :: proc(
	plan: Batch_Plan,
	ordered: []Batch_Target_Request,
	outcomes: []Batch_Target_Outcome,
	limits := DEFAULT_LIMITS,
) -> (Batch_Summary, bool, Failure) {
	if !plan.complete || len(ordered) != int(plan.target_count) || len(outcomes) != len(ordered) {
		return {}, false, batch_failure(plan.batch_id, .Invalid_Request, .Batch)
	}
	summary := Batch_Summary {}
	for outcome, index in outcomes {
		request := ordered[index]
		if outcome.operation_id != request.operation_id || outcome.state == .Invalid ||
		   outcome.byte_count > limits.output_bytes || outcome.row_count > limits.result_rows {
			return {}, false, batch_failure(plan.batch_id, .Conflict, .Batch)
		}
		summary.output_bytes += outcome.byte_count
		summary.result_rows += u64(outcome.row_count)
		if summary.output_bytes > limits.retained_output_bytes {
			return {}, false, batch_failure(plan.batch_id, .Limited, .Limit)
		}
		switch outcome.state {
		case .Completed:
			summary.executed += 1
		case .Cache_Hit:
			summary.cache_hits += 1
		case .Rejected:
			if outcome.failure == .None do return {}, false, batch_failure(plan.batch_id, .Conflict, .Batch)
			summary.rejected += 1
		case .Unattempted:
			summary.unattempted += 1
		case .Cancelled:
			summary.cancelled += 1
		case .Ready, .Invalid:
			return {}, false, batch_failure(plan.batch_id, .Conflict, .Batch)
		}
	}
	successful := summary.executed + summary.cache_hits
	if plan.mode == .Atomic && (summary.rejected > 0 || summary.unattempted > 0 || summary.cancelled > 0) {
		summary.published = 0
	} else {
		summary.published = successful
	}
	summary.descriptor = {
		batch_id = plan.batch_id,
		mode = plan.mode,
		target_count = plan.target_count,
		completed = successful,
		rejected = summary.rejected + summary.cancelled,
		unattempted = summary.unattempted,
		cancelled = summary.cancelled > 0,
	}
	if summary.descriptor.completed + summary.descriptor.rejected + summary.descriptor.unattempted != plan.target_count {
		return {}, false, batch_failure(plan.batch_id, .Conflict, .Batch)
	}
	summary.complete = true
	return summary, true, {}
}

/* Computation_Runtime_State identifies inputs to capability availability. */
Computation_Runtime_State :: struct {
	language_ready:       bool,
	graphical_adapter:    bool,
	execution_adapter:    bool,
	process_owner:        bool,
	resource_owner:       bool,
	adapter_generation:   Adapter_Generation,
}

/* computation_capability_availability resolves operational domain state. */
computation_capability_availability :: proc(state: Computation_Runtime_State) -> [11]Availability_Record {
	records := computation_capability_declarations()
	for &record in records {
		record.state = .Unavailable
		switch record.capability {
		case .Formulas, .Text_Plots, .Results, .Cache, .Source_Editing, .Noweb:
			if state.language_ready do record.state = .Available
		case .Graphical_Plots:
			if state.language_ready && state.graphical_adapter do record.state = .Available
		case .Execution, .Sessions:
			if state.language_ready && state.execution_adapter && state.process_owner do record.state = .Available
		case .Tangling:
			if state.language_ready && state.resource_owner do record.state = .Available
		case .Batch:
			if state.language_ready && state.execution_adapter && state.process_owner do record.state = .Available
		case .Invalid:
		}
		if record.class == .Factory_Adapter && record.state == .Available do record.adapter_generation = state.adapter_generation
	}
	return records
}

@(private)
batch_target_less :: proc(left, right: Batch_Target_Request) -> bool {
	if left.document_id != right.document_id do return left.document_id < right.document_id
	if left.source_start != right.source_start do return left.source_start < right.source_start
	return left.operation_id < right.operation_id
}

@(private)
batch_failure :: proc(batch_id: Batch_ID, code: Failure_Code, field: Failure_Field) -> Failure {
	return {operation_id = Operation_ID(batch_id), kind = .Batch, code = code, field = field}
}
