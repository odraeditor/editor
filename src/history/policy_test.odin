// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package history

import "../editor"
import "base:runtime"
import "core:mem"
import "core:testing"

/* Verifies a raised live limit governs the next admission without restarting the store. */
@(test)
policy_increase_changes_admission :: proc(t: ^testing.T) {
	policy := DEFAULT_POLICY
	policy.sibling_branches = MIN_SIBLING_BRANCHES
	store: Store
	initialized, _ := store_init(
		&store,
		Store_ID(30),
		editor.Buffer_ID(30),
		editor.Revision(0),
		Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
		policy,
	)
	testing.expect(t, initialized)
	if !initialized {
		return
	}
	defer store_close(&store)
	revision := editor.Revision(0)
	for identity in 1 ..= 2 {
		if !policy_test_branch(t, &store, editor.Buffer_ID(30), u64(identity), &revision) {
			return
		}
	}
	blocked: Reservation
	blocked_result := editor.Revision(u64(revision) + 1)
	blocked_ok, blocked_failure := policy_test_record_reserve(
		&store,
		&blocked,
		editor.Buffer_ID(30),
		3,
		revision,
		blocked_result,
		"x",
		"",
	)
	testing.expect(t, !blocked_ok)
	testing.expect_value(t, blocked_failure.code, Failure_Code.Branch_Limit)

	policy.sibling_branches = MIN_SIBLING_BRANCHES + 1
	state := (^Store_State)(store.state)
	previous_temporary := state.temporary_allocator
	state.temporary_allocator = runtime.nil_allocator()
	replaced, replacement_ok, _ := store_policy_replace(
		&store,
		Policy_Replacement_Request {
			expected_generation = Policy_Generation(1),
			policy = policy,
		},
	)
	state.temporary_allocator = previous_temporary
	testing.expect(t, replacement_ok)
	testing.expect_value(t, replaced.policy_generation, Policy_Generation(2))
	admitted: Reservation
	admitted_ok, _ := policy_test_record_reserve(
		&store,
		&admitted,
		editor.Buffer_ID(30),
		3,
		revision,
		blocked_result,
		"x",
		"",
	)
	testing.expect(t, admitted_ok)
	if admitted_ok {
		reservation_abort(&admitted)
	}
}

/* Verifies live policy replacement publishes one generation or preserves the exact prior store. */
@(test)
policy_replacement_is_atomic :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	allocator := mem.tracking_allocator(&tracking)
	store: Store
	initialized, _ := store_init(
		&store,
		Store_ID(31),
		editor.Buffer_ID(31),
		editor.Revision(0),
		Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, initialized)
	if !initialized {
		return
	}

	revision := editor.Revision(0)
	for identity in 1 ..= 300 {
		if !policy_test_branch(t, &store, editor.Buffer_ID(31), u64(identity), &revision) {
			store_close(&store)
			return
		}
	}
	initial, initial_ok, _ := store_policy_inspect(&store)
	testing.expect(t, initial_ok)
	testing.expect_value(t, initial.policy_generation, Policy_Generation(1))
	testing.expect_value(t, initial.usage.retained_nodes, u64(301))

	raised_policy := initial.policy
	raised_policy.inspection_nodes = 512
	raised, raised_ok, raised_failure := store_policy_replace(
		&store,
		Policy_Replacement_Request {
			expected_generation = initial.policy_generation,
			policy = raised_policy,
		},
	)
	testing.expect(t, raised_ok)
	testing.expect_value(t, raised_failure.code, Failure_Code.None)
	testing.expect_value(t, raised.previous_generation, Policy_Generation(1))
	testing.expect_value(t, raised.policy_generation, Policy_Generation(2))
	testing.expect_value(t, raised.pruned_nodes, u64(0))

	stale_policy := raised_policy
	stale_policy.inspection_nodes = 1_024
	_, stale_ok, stale_failure := store_policy_replace(
		&store,
		Policy_Replacement_Request {
			expected_generation = Policy_Generation(1),
			policy = stale_policy,
		},
	)
	testing.expect(t, !stale_ok)
	testing.expect_value(t, stale_failure.code, Failure_Code.Stale_Generation)

	_, cancelled_ok, cancelled_failure := store_policy_replace(
		&store,
		Policy_Replacement_Request {
			expected_generation = Policy_Generation(2),
			policy = stale_policy,
			cancelled = true,
		},
	)
	testing.expect(t, !cancelled_ok)
	testing.expect_value(t, cancelled_failure.code, Failure_Code.Cancelled)

	invalid_policy := raised_policy
	invalid_policy.global_retained_bytes = MIN_GLOBAL_RETAINED_BYTES - 1
	_, invalid_ok, invalid_failure := store_policy_replace(
		&store,
		Policy_Replacement_Request {
			expected_generation = Policy_Generation(2),
			policy = invalid_policy,
		},
	)
	testing.expect(t, !invalid_ok)
	testing.expect_value(t, invalid_failure.code, Failure_Code.Policy_Range)
	testing.expect_value(t, invalid_failure.field, Policy_Field.Global_Retained_Bytes)

	lowered_policy := raised_policy
	lowered_policy.buffer_nodes = MIN_BUFFER_NODES
	lowered_policy.guaranteed_recent_units = MIN_RECENT_UNITS
	lowered_policy.retained_depth = MIN_RETAINED_DEPTH
	before_failure, _, _ := store_stats(&store)
	state := (^Store_State)(store.state)
	previous_temporary := state.temporary_allocator
	state.temporary_allocator = runtime.nil_allocator()
	_, allocation_ok, allocation_failure := store_policy_replace(
		&store,
		Policy_Replacement_Request {
			expected_generation = Policy_Generation(2),
			policy = lowered_policy,
			operation_limit = 64,
		},
	)
	state.temporary_allocator = previous_temporary
	testing.expect(t, !allocation_ok)
	testing.expect_value(t, allocation_failure.code, Failure_Code.Temporary_Memory_Limit)
	after_allocation_failure, _, _ := store_stats(&store)
	testing.expect_value(t, after_allocation_failure, before_failure)

	_, blocked_ok, blocked_failure := store_policy_replace(
		&store,
		Policy_Replacement_Request {
			expected_generation = Policy_Generation(2),
			policy = lowered_policy,
			operation_limit = 1,
		},
	)
	testing.expect(t, !blocked_ok)
	testing.expect_value(t, blocked_failure.code, Failure_Code.Policy_Retention_Blocked)
	testing.expect_value(t, blocked_failure.field, Policy_Field.Buffer_Nodes)
	after_failure, _, _ := store_stats(&store)
	testing.expect_value(t, after_failure, before_failure)
	after_failure_policy, _, _ := store_policy_inspect(&store)
	testing.expect_value(t, after_failure_policy.policy, raised_policy)

	lowered, lowered_ok, lowered_failure := store_policy_replace(
		&store,
		Policy_Replacement_Request {
			expected_generation = Policy_Generation(2),
			policy = lowered_policy,
			operation_limit = 64,
		},
	)
	testing.expect(t, lowered_ok)
	testing.expect_value(t, lowered_failure.code, Failure_Code.None)
	testing.expect_value(t, lowered.policy_generation, Policy_Generation(3))
	testing.expect_value(t, lowered.pruned_nodes, u64(45))
	testing.expect_value(t, lowered.usage.retained_nodes, MIN_BUFFER_NODES)
	active, _, _ := store_stats(&store)
	testing.expect_value(t, active.active_node, before_failure.active_node)
	testing.expect_value(t, active.current_revision, revision)

	closed, _ := store_close(&store)
	testing.expect(t, closed)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
}

/* Verifies a protected active path blocks an unenforceable depth decrease without partial pruning. */
@(test)
replacement_preserves_protected_depth :: proc(t: ^testing.T) {
	store: Store
	initialized, _ := store_init(
		&store,
		Store_ID(32),
		editor.Buffer_ID(32),
		editor.Revision(0),
		Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, initialized)
	if !initialized {
		return
	}
	revision := editor.Revision(0)
	for identity in 1 ..= 65 {
		result := editor.Revision(u64(revision) + 1)
		reservation: Reservation
		reserved, _ := policy_test_record_reserve(
			&store,
			&reservation,
			editor.Buffer_ID(32),
			u64(identity),
			revision,
			result,
			"x",
			"",
		)
		testing.expect(t, reserved)
		if !reserved {
			store_close(&store)
			return
		}
		reservation_commit_reserved(&reservation, result)
		revision = result
	}
	before, _, _ := store_stats(&store)
	current, _, _ := store_policy_inspect(&store)
	lowered := current.policy
	lowered.retained_depth = MIN_RETAINED_DEPTH
	_, replaced, failure := store_policy_replace(
		&store,
		Policy_Replacement_Request {
			expected_generation = current.policy_generation,
			policy = lowered,
			operation_limit = lowered.pruning_operations,
		},
	)
	testing.expect(t, !replaced)
	testing.expect_value(t, failure.code, Failure_Code.Policy_Retention_Blocked)
	testing.expect_value(t, failure.field, Policy_Field.Retained_Depth)
	after, _, _ := store_stats(&store)
	testing.expect_value(t, after, before)
	store_close(&store)
}

@(private = "file")
policy_test_branch :: proc(
	t: ^testing.T,
	store: ^Store,
	buffer_id: editor.Buffer_ID,
	identity: u64,
	revision: ^editor.Revision,
) -> bool {
	result_revision := editor.Revision(u64(revision^) + 1)
	reservation: Reservation
	reserved, _ := policy_test_record_reserve(
		store,
		&reservation,
		buffer_id,
		identity,
		revision^,
		result_revision,
		"x",
		"",
	)
	testing.expect(t, reserved)
	if !reserved {
		return false
	}
	reservation_commit_reserved(&reservation, result_revision)
	undo, preliminary, prepared, _ := navigation_prepare(
		store,
		Navigation_Request {
			kind = .Undo,
			buffer_id = buffer_id,
			current_revision = result_revision,
		},
	)
	testing.expect(t, prepared && preliminary.outcome == .Applied)
	if !prepared || preliminary.outcome != .Applied {
		return false
	}
	revision^ = editor.Revision(u64(result_revision) + 1)
	navigation_commit_reserved(&undo, revision^)
	return true
}

@(private = "file")
policy_test_record_reserve :: proc(
	store: ^Store,
	reservation: ^Reservation,
	buffer_id: editor.Buffer_ID,
	identity: u64,
	base, result: editor.Revision,
	replacement, removed: string,
) -> (bool, Failure_Context) {
	edits := [1]Edit_Payload {{
		start = editor.Byte_Offset(1),
		end = editor.Byte_Offset(1 + len(removed)),
		replacement_text = replacement,
		removed_text = removed,
	}}
	return record_reserve(store, reservation, Record_Input {
		source_transaction_id = Source_Transaction_ID(identity),
		source_undo_unit_id = Source_Undo_Unit_ID(identity),
		buffer_id = buffer_id,
		base_revision = base,
		result_revision = result,
		edits = edits[:],
		origin = .Built_In,
		origin_descriptor = "policy-test",
		command = "policy-test-edit",
	})
}
