// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_computation

import "core:testing"

/* Verifies deterministic order, explicit authority, cache accounting, and concurrency bounds. */
@(test)
batch_orders_only_explicit_admitted_targets :: proc(t: ^testing.T) {
	scope := computation_test_scope()
	target := computation_test_target(scope)
	selection := Adapter_Selection {state = .Selected, adapter_generation = scope.adapter_generation}
	requests := []Batch_Target_Request {
		{operation_id = 3, document_id = 2, source_start = u64(target.range.start), scope = scope, target = target,
		 authority = {operation_id = 3, decision = .Allow, policy_generation = scope.policy_generation, explicit_trigger = true}, adapter = selection},
		{operation_id = 2, document_id = 1, source_start = u64(target.range.start), scope = scope, target = target,
		 authority = {operation_id = 2, decision = .Allow, policy_generation = scope.policy_generation, explicit_trigger = true}, adapter = selection, cache_state = .Hit},
		{operation_id = 1, document_id = 1, source_start = u64(target.range.start) - 1, scope = scope, target = target,
		 authority = {operation_id = 1, decision = .Allow, policy_generation = scope.policy_generation, explicit_trigger = true}, adapter = selection},
	}
	requests[2].target.range.start -= 1
	ordered: [3]Batch_Target_Request
	plan, ok, _ := prepare_execution_batch(7, .Atomic, 2, requests, ordered[:])
	testing.expect(t, ok)
	testing.expect_value(t, ordered[0].operation_id, Operation_ID(1))
	testing.expect_value(t, ordered[1].operation_id, Operation_ID(2))
	testing.expect_value(t, ordered[2].operation_id, Operation_ID(3))
	testing.expect_value(t, plan.cache_hits, u32(1))

	requests[0].authority.explicit_trigger = false
	_, implicit_ok, implicit_failure := prepare_execution_batch(8, .Atomic, 2, requests, ordered[:])
	testing.expect(t, !implicit_ok)
	testing.expect_value(t, implicit_failure.code, Failure_Code.Unauthorized)
	requests[0].authority.explicit_trigger = true
	_, concurrency_ok, concurrency_failure := prepare_execution_batch(8, .Atomic, DEFAULT_LIMITS.child_processes + 1, requests, ordered[:])
	testing.expect(t, !concurrency_ok)
	testing.expect_value(t, concurrency_failure.field, Failure_Field.Batch)
}

/* Verifies atomic failure suppresses publication while best effort remains attributable. */
@(test)
batch_summarizes_atomic_and_best_effort_outcomes :: proc(t: ^testing.T) {
	scope := computation_test_scope()
	target := computation_test_target(scope)
	selection := Adapter_Selection {state = .Selected, adapter_generation = scope.adapter_generation}
	requests := []Batch_Target_Request {
		{operation_id = 1, document_id = 1, source_start = u64(target.range.start), scope = scope, target = target,
		 authority = {operation_id = 1, decision = .Allow, policy_generation = scope.policy_generation, explicit_trigger = true}, adapter = selection},
		{operation_id = 2, document_id = 2, source_start = u64(target.range.start), scope = scope, target = target,
		 authority = {operation_id = 2, decision = .Allow, policy_generation = scope.policy_generation, explicit_trigger = true}, adapter = selection},
	}
	ordered: [2]Batch_Target_Request
	plan, ok, _ := prepare_execution_batch(9, .Atomic, 1, requests, ordered[:])
	testing.expect(t, ok)
	outcomes := []Batch_Target_Outcome {
		{operation_id = 1, state = .Completed, byte_count = 8, row_count = 1},
		{operation_id = 2, state = .Rejected, failure = .Evaluation},
	}
	summary, summarized, _ := summarize_execution_batch(plan, ordered[:], outcomes)
	testing.expect(t, summarized)
	testing.expect_value(t, summary.published, u32(0))
	testing.expect_value(t, summary.executed, u32(1))
	testing.expect_value(t, summary.rejected, u32(1))
	plan.mode = .Best_Effort
	summary, summarized, _ = summarize_execution_batch(plan, ordered[:], outcomes)
	testing.expect(t, summarized)
	testing.expect_value(t, summary.published, u32(1))

	outcomes[1] = {operation_id = 2, state = .Cancelled, failure = .Cancelled}
	summary, summarized, _ = summarize_execution_batch(plan, ordered[:], outcomes)
	testing.expect(t, summarized)
	testing.expect(t, summary.descriptor.cancelled)
}

/* Verifies provider state changes only the capabilities that depend on it. */
@(test)
batch_resolves_computation_capability_transitions :: proc(t: ^testing.T) {
	records := computation_capability_availability({language_ready = true})
	for record in records {
		if record.capability == .Formulas || record.capability == .Text_Plots || record.capability == .Results ||
		   record.capability == .Cache || record.capability == .Source_Editing || record.capability == .Noweb {
			testing.expect_value(t, record.state, Availability_State.Available)
		} else {
			testing.expect_value(t, record.state, Availability_State.Unavailable)
		}
	}
	records = computation_capability_availability({language_ready = true, graphical_adapter = true,
		execution_adapter = true, process_owner = true, resource_owner = true, adapter_generation = 41})
	for record in records do testing.expect_value(t, record.state, Availability_State.Available)
}
