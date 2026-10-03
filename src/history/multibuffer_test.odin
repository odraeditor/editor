// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package history

import "../editor"
import "base:runtime"
import "core:mem"
import "core:testing"

/* Verifies deterministic shared identity, complete linkage, and coordinated ownership. */
@(test)
records_reserve_and_commit_one_complete_link :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	allocator := mem.tracking_allocator(&tracking)
	first := test_link_store_init(t, Store_ID(11), editor.Buffer_ID(101), allocator)
	second := test_link_store_init(t, Store_ID(12), editor.Buffer_ID(102), allocator)
	first_edit := [1]Edit_Payload{{replacement_text = "A", removed_text = "a"}}
	second_edit := [1]Edit_Payload{{replacement_text = "B", removed_text = "b"}}
	reservation: Multibuffer_Reservation
	reserved, failure := multibuffer_record_reserve(
		&reservation,
		[]Multibuffer_Record_Input {
			{store = &second, record = test_link_record(editor.Buffer_ID(102), second_edit[:])},
			{store = &first, record = test_link_record(editor.Buffer_ID(101), first_edit[:])},
		},
	)
	testing.expectf(t, reserved, "linked reservation failed with %v", failure.code)
	if !reserved {
		store_close(&second)
		store_close(&first)
		return
	}
	multibuffer_reservation_commit_reserved(&reservation)

	first_stats, _, _ := store_stats(&first)
	second_stats, _, _ := store_stats(&second)
	testing.expect_value(t, first_stats.usage.retained_links, u64(1))
	testing.expect_value(t, second_stats.usage.retained_links, u64(0))
	participants: [2]Link_Participant
	projection, inspected, inspect_failure := link_inspect(
		&second,
		second_stats.active_node,
		participants[:],
	)
	testing.expectf(t, inspected, "link inspection failed with %v", inspect_failure.code)
	testing.expect_value(t, projection.id, Link_ID(900))
	testing.expect_value(t, projection.source_transaction_id, Source_Transaction_ID(800))
	testing.expect_value(t, len(projection.participants), 2)
	testing.expect_value(t, projection.participants[0].buffer_id, editor.Buffer_ID(101))
	testing.expect_value(t, projection.participants[1].buffer_id, editor.Buffer_ID(102))
	testing.expect_value(t, projection.participants[0].node_id, first_stats.active_node)
	testing.expect_value(t, projection.participants[1].node_id, second_stats.active_node)

	closed, close_failure := store_close(&first)
	testing.expect(t, !closed)
	testing.expect_value(t, close_failure.code, Failure_Code.Incomplete_Participant_Set)
	closed, close_failure = multibuffer_stores_close([]^Store{&second, &first})
	testing.expectf(t, closed, "complete store close failed with %v", close_failure.code)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
}

/* Verifies one participant failure aborts every reserved record without retained linkage. */
@(test)
multibuffer_record_failure_preserves_every_store :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	allocator := mem.tracking_allocator(&tracking)
	first := test_link_store_init(t, Store_ID(21), editor.Buffer_ID(201), allocator)
	second := test_link_store_init(t, Store_ID(22), editor.Buffer_ID(202), allocator)
	first_edit := [1]Edit_Payload{{replacement_text = "A", removed_text = "a"}}
	second_edit := [1]Edit_Payload{{replacement_text = "B", removed_text = "b"}}
	second_record := test_link_record(editor.Buffer_ID(202), second_edit[:])
	second_record.base_revision = editor.Revision(7)
	second_record.result_revision = editor.Revision(8)
	reservation: Multibuffer_Reservation
	reserved, failure := multibuffer_record_reserve(
		&reservation,
		[]Multibuffer_Record_Input {
			{store = &first, record = test_link_record(editor.Buffer_ID(201), first_edit[:])},
			{store = &second, record = second_record},
		},
	)
	testing.expect(t, !reserved)
	testing.expect_value(t, failure.code, Failure_Code.Stale_Revision)
	first_stats, _, _ := store_stats(&first)
	second_stats, _, _ := store_stats(&second)
	testing.expect_value(t, first_stats.usage.retained_nodes, u64(1))
	testing.expect_value(t, second_stats.usage.retained_nodes, u64(1))
	testing.expect_value(t, first_stats.usage.retained_links, u64(0))
	store_close(&second)
	store_close(&first)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
}

/* Verifies linked pruning requires and removes one complete eligible participant set. */
@(test)
pruning_rejects_incomplete_sets :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	allocator := mem.tracking_allocator(&tracking)
	first := test_link_store_init(t, Store_ID(31), editor.Buffer_ID(301), allocator)
	second := test_link_store_init(t, Store_ID(32), editor.Buffer_ID(302), allocator)
	policy := DEFAULT_POLICY
	policy.guaranteed_recent_units = MIN_RECENT_UNITS
	store_policy_replace(
		&first,
		Policy_Replacement_Request{expected_generation = 1, policy = policy, operation_limit = 64},
	)
	store_policy_replace(
		&second,
		Policy_Replacement_Request{expected_generation = 1, policy = policy, operation_limit = 64},
	)
	first_edit := [1]Edit_Payload{{replacement_text = "A", removed_text = "a"}}
	second_edit := [1]Edit_Payload{{replacement_text = "B", removed_text = "b"}}
	linked: Multibuffer_Reservation
	multibuffer_record_reserve(
		&linked,
		[]Multibuffer_Record_Input {
			{store = &first, record = test_link_record(editor.Buffer_ID(301), first_edit[:])},
			{store = &second, record = test_link_record(editor.Buffer_ID(302), second_edit[:])},
		},
	)
	multibuffer_reservation_commit_reserved(&linked)
	first_link_stats, _, _ := store_stats(&first)
	second_link_stats, _, _ := store_stats(&second)
	test_link_history_undo(&first, editor.Buffer_ID(301), editor.Revision(1), editor.Revision(2))
	test_link_history_undo(&second, editor.Buffer_ID(302), editor.Revision(1), editor.Revision(2))
	for identity in 1 ..= 33 {
		test_link_history_append(&first, editor.Buffer_ID(301), u64(identity), "x")
		test_link_history_append(&second, editor.Buffer_ID(302), u64(identity + 100), "y")
	}
	_, incomplete_ok, incomplete_failure := multibuffer_prune([]^Store{&first}, 2)
	testing.expect(t, !incomplete_ok)
	testing.expect_value(t, incomplete_failure.code, Failure_Code.Incomplete_Participant_Set)
	pruned, pruned_ok, prune_failure := multibuffer_prune([]^Store{&second, &first}, 2)
	testing.expectf(t, pruned_ok, "linked prune failed with %v", prune_failure.code)
	testing.expect_value(t, pruned, u64(2))
	participants: [2]Link_Participant
	_, first_retained, _ := link_inspect(&first, first_link_stats.active_node, participants[:])
	_, second_retained, _ := link_inspect(&second, second_link_stats.active_node, participants[:])
	testing.expect(t, !first_retained && !second_retained)
	store_close(&second)
	store_close(&first)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
}

@(private = "file")
test_link_store_init :: proc(
	t: ^testing.T,
	store_id: Store_ID,
	buffer_id: editor.Buffer_ID,
	allocator: runtime.Allocator,
) -> Store {
	store: Store
	initialized, failure := store_init(
		&store,
		store_id,
		buffer_id,
		editor.Revision(0),
		Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
	)
	testing.expectf(t, initialized, "store initialization failed with %v", failure.code)
	return store
}

@(private = "file")
test_link_record :: proc(buffer_id: editor.Buffer_ID, edits: []Edit_Payload) -> Record_Input {
	return Record_Input {
		source_transaction_id = Source_Transaction_ID(800),
		source_undo_unit_id = Source_Undo_Unit_ID(900),
		buffer_id = buffer_id,
		base_revision = editor.Revision(0),
		result_revision = editor.Revision(1),
		edits = edits,
		origin = .Built_In,
		origin_descriptor = "test",
		command = "linked-edit",
	}
}

@(private = "file")
test_link_history_undo :: proc(
	store: ^Store,
	buffer_id: editor.Buffer_ID,
	base, result: editor.Revision,
) {
	plan, _, prepared, _ := navigation_prepare(
		store,
		Navigation_Request{kind = .Undo, buffer_id = buffer_id, current_revision = base},
	)
	assert(prepared)
	navigation_commit_reserved(&plan, result)
}

@(private = "file")
test_link_history_append :: proc(
	store: ^Store,
	buffer_id: editor.Buffer_ID,
	identity: u64,
	replacement: string,
) {
	stats, ok, _ := store_stats(store)
	assert(ok)
	edit := [1]Edit_Payload{{replacement_text = replacement}}
	reservation: Reservation
	reserved, _ := record_reserve(
		store,
		&reservation,
		Record_Input {
			source_transaction_id = Source_Transaction_ID(1_000 + identity),
			source_undo_unit_id = Source_Undo_Unit_ID(1_000 + identity),
			buffer_id = buffer_id,
			base_revision = stats.current_revision,
			result_revision = editor.Revision(u64(stats.current_revision) + 1),
			edits = edit[:],
			origin = .Built_In,
			origin_descriptor = "test",
			command = "age-link",
			grouping = Grouping_Context{kind = .Independent},
		},
	)
	assert(reserved)
	reservation_commit_reserved(&reservation, editor.Revision(u64(stats.current_revision) + 1))
}
