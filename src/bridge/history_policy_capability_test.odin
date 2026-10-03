// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package bridge

import "../editor"
import "../history"
import "core:mem"
import "core:testing"
import "core:thread"

@(private)
History_Policy_Thread_Result :: struct {
	registry:   ^History_Policy_Capability_Registry,
	capability: History_Policy_Capability,
	ok:         bool,
	failure:    Failure_Context,
}

@(private)
history_policy_cross_thread_inspect :: proc(observed: ^History_Policy_Thread_Result) {
	_, observed.ok, observed.failure = history_policy_capability_inspect(
		observed.registry,
		observed.capability,
	)
}

/* Verifies policy capabilities copy values and contain stale, thread, reentrant, and policy failures. */
@(test)
history_policy_loses_released_authority :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	allocator := mem.tracking_allocator(&tracking)
	store: history.Store
	store_ready, _ := history.store_init(
		&store,
		history.Store_ID(71),
		editor.Buffer_ID(71),
		editor.Revision(0),
		history.Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, store_ready)
	if !store_ready {
		return
	}
	revision := editor.Revision(0)
	for identity in 1 ..= 65 {
		result_revision := editor.Revision(u64(revision) + 1)
		reservation: history.Reservation
		reserved, _ := history_policy_test_record(
			&store,
			&reservation,
			u64(identity),
			revision,
			result_revision,
		)
		testing.expect(t, reserved)
		if !reserved {
			history.store_close(&store)
			return
		}
		history.reservation_commit_reserved(&reservation, result_revision)
		revision = result_revision
	}

	registry: History_Policy_Capability_Registry
	registry_ready, _ := history_policy_capability_registry_init(&registry, Registry_ID(71))
	testing.expect(t, registry_ready)
	capability, initial, acquired, acquire_failure := history_policy_capability_acquire(
		&registry,
		&store,
	)
	testing.expectf(t, acquired, "policy capability acquire failed with %v", acquire_failure.code)
	testing.expect_value(t, initial.policy_generation, history.Policy_Generation(1))
	inspected, inspected_ok, _ := history_policy_capability_inspect(&registry, capability)
	testing.expect(t, inspected_ok)
	testing.expect_value(t, inspected, initial)

	blocked_policy := initial.policy
	blocked_policy.retained_depth = history.MIN_RETAINED_DEPTH
	_, blocked_ok, blocked_failure := history_policy_capability_replace(
		&registry,
		capability,
		history.Policy_Replacement_Request {
			expected_generation = initial.policy_generation,
			policy = blocked_policy,
			operation_limit = blocked_policy.pruning_operations,
		},
	)
	testing.expect(t, !blocked_ok)
	testing.expect_value(t, blocked_failure.code, Failure_Code.Retention_Blocked)
	testing.expect_value(t, blocked_failure.history_code, history.Failure_Code.Policy_Retention_Blocked)
	testing.expect_value(t, blocked_failure.policy_field, history.Policy_Field.Retained_Depth)
	testing.expect_value(t, blocked_failure.policy_generation, history.Policy_Generation(1))

	invalid_policy := initial.policy
	invalid_policy.global_retained_bytes = history.MIN_GLOBAL_RETAINED_BYTES - 1
	_, invalid_ok, invalid_failure := history_policy_capability_replace(
		&registry,
		capability,
		history.Policy_Replacement_Request {
			expected_generation = initial.policy_generation,
			policy = invalid_policy,
		},
	)
	testing.expect(t, !invalid_ok)
	testing.expect_value(t, invalid_failure.code, Failure_Code.Policy_Range)
	testing.expect_value(t, invalid_failure.policy_field, history.Policy_Field.Global_Retained_Bytes)
	testing.expect_value(t, invalid_failure.minimum, history.MIN_GLOBAL_RETAINED_BYTES)
	testing.expect_value(t, invalid_failure.limit, history.MAX_GLOBAL_RETAINED_BYTES)
	testing.expect_value(t, invalid_failure.actual, history.MIN_GLOBAL_RETAINED_BYTES - 1)

	raised_policy := initial.policy
	raised_policy.inspection_nodes = 512
	replaced, replacement_ok, _ := history_policy_capability_replace(
		&registry,
		capability,
		history.Policy_Replacement_Request {
			expected_generation = initial.policy_generation,
			policy = raised_policy,
		},
	)
	testing.expect(t, replacement_ok)
	testing.expect_value(t, replaced.policy_generation, history.Policy_Generation(2))
	_, stale_ok, stale_failure := history_policy_capability_replace(
		&registry,
		capability,
		history.Policy_Replacement_Request {
			expected_generation = initial.policy_generation,
			policy = raised_policy,
		},
	)
	testing.expect(t, !stale_ok)
	testing.expect_value(t, stale_failure.code, Failure_Code.Stale_Generation)

	slot, resolved := history_policy_capability_resolve(&registry, capability)
	testing.expect_value(t, resolved.code, Failure_Code.None)
	slot.call_active = true
	_, reentrant_ok, reentrant_failure := history_policy_capability_inspect(&registry, capability)
	testing.expect(t, !reentrant_ok)
	testing.expect_value(t, reentrant_failure.code, Failure_Code.Reentrant_Call)
	slot.call_active = false

	cross_thread := History_Policy_Thread_Result{registry = &registry, capability = capability}
	worker := thread.create_and_start_with_poly_data(&cross_thread, history_policy_cross_thread_inspect)
	testing.expect(t, worker != nil)
	if worker != nil {
		thread.join(worker)
		thread.destroy(worker)
		testing.expect(t, !cross_thread.ok)
		testing.expect_value(t, cross_thread.failure.code, Failure_Code.Wrong_Thread)
	}

	retained_close, retained_failure := history_policy_capability_registry_close(&registry)
	testing.expect(t, !retained_close)
	testing.expect_value(t, retained_failure.code, Failure_Code.Retained_Capabilities)
	old_capability := capability
	released, _ := history_policy_capability_release(&registry, &capability)
	testing.expect(t, released)
	_, stale_capability_ok, stale_capability_failure := history_policy_capability_inspect(
		&registry,
		old_capability,
	)
	testing.expect(t, !stale_capability_ok)
	testing.expect_value(t, stale_capability_failure.code, Failure_Code.Stale_Capability)
	registry_closed, _ := history_policy_capability_registry_close(&registry)
	testing.expect(t, registry_closed)
	store_closed, _ := history.store_close(&store)
	testing.expect(t, store_closed)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
}

@(private = "file")
history_policy_test_record :: proc(
	store: ^history.Store,
	reservation: ^history.Reservation,
	identity: u64,
	base, result: editor.Revision,
) -> (bool, history.Failure_Context) {
	edits := [1]history.Edit_Payload {{
		start = 0,
		end = 0,
		replacement_text = "x",
	}}
	return history.record_reserve(store, reservation, history.Record_Input {
		source_transaction_id = history.Source_Transaction_ID(identity),
		source_undo_unit_id = history.Source_Undo_Unit_ID(identity),
		buffer_id = editor.Buffer_ID(71),
		base_revision = base,
		result_revision = result,
		edits = edits[:],
		origin = .Built_In,
		origin_descriptor = "bridge-policy-test",
		command = "bridge-policy-test-edit",
	})
}
