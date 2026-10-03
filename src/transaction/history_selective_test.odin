// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package transaction

import "../editor"
import "../history"
import "core:mem"
import "core:testing"

/* Verifies selective undo publishes one range-narrowed compensating history node. */
@(test)
selective_undo_is_reversible :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	allocator := mem.tracking_allocator(&tracking)
	buffer := test_buffer_open(t, &tracking, editor.Buffer_ID(801), "abcdef")
	if !editor.buffer_is_live(&buffer) {
		return
	}
	store: history.Store
	store_ok, _ := history.store_init(
		&store,
		history.Store_ID(81),
		editor.Buffer_ID(801),
		editor.Revision(0),
		history.Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, store_ok)
	if !store_ok {
		editor.buffer_close(&buffer)
		return
	}

	selective_test_commit_batch(
		t,
		&buffer,
		&store,
		&tracking,
		Transaction_ID(801),
		[]Selective_Test_Splice {
			{start = 1, end = 2, replacement = "X"},
			{start = 4, end = 5, replacement = "Q"},
		},
	)
	selective_test_commit_batch(
		t,
		&buffer,
		&store,
		&tracking,
		Transaction_ID(802),
		[]Selective_Test_Splice {{start = 0, end = 0, replacement = "Y"}},
	)
	expect_confirmed_text(t, &buffer, editor.Revision(2), "YaXcdQf")
	before, _, _ := history.store_stats(&store)
	request := history.Selective_Request {
		buffer_id = before.buffer_id,
		current_revision = before.current_revision,
		active_node = before.active_node,
		target_unit = history.Unit_ID(1),
		policy_generation = before.policy_generation,
		analysis_operations = 128,
		range = history.Selective_Range {
			present = true,
			revision = before.current_revision,
			start = editor.Byte_Offset(0),
			end = editor.Byte_Offset(4),
		},
	}
	result, reversed, reverse_failure := transaction_history_selective_undo(
		&store,
		&buffer,
		request,
		Transaction_ID(803),
		Undo_Unit_ID(803),
		Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, reversed)
	testing.expect_value(t, reverse_failure.code, Failure_Code.None)
	testing.expect_value(t, result.outcome, history.Navigation_Outcome.Applied)
	expect_confirmed_text(t, &buffer, editor.Revision(3), "YabcdQf")
	after, _, _ := history.store_stats(&store)
	testing.expect_value(t, after.usage.retained_nodes, before.usage.retained_nodes + 1)
	testing.expect_value(t, after.active_node, result.active_node)

	undo, undo_ok, _ := transaction_history_navigate(
		&store,
		&buffer,
		.Undo,
		Transaction_ID(804),
		Undo_Unit_ID(804),
		Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, undo_ok)
	testing.expect_value(t, undo.outcome, history.Navigation_Outcome.Applied)
	expect_confirmed_text(t, &buffer, editor.Revision(4), "YaXcdQf")

	selective_test_commit_batch(
		t,
		&buffer,
		&store,
		&tracking,
		Transaction_ID(805),
		[]Selective_Test_Splice {{start = 2, end = 3, replacement = "Z"}},
	)
	expect_confirmed_text(t, &buffer, editor.Revision(5), "YaZcdQf")
	conflict_before, _, _ := history.store_stats(&store)
	request.current_revision = conflict_before.current_revision
	request.active_node = conflict_before.active_node
	request.policy_generation = conflict_before.policy_generation
	request.range.revision = conflict_before.current_revision
	_, conflict_ok, conflict_failure := transaction_history_selective_undo(
		&store,
		&buffer,
		request,
		Transaction_ID(806),
		Undo_Unit_ID(806),
		Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, !conflict_ok)
	testing.expect_value(t, conflict_failure.code, Failure_Code.History_Failure)
	testing.expect_value(t, conflict_failure.history_failure.code, history.Failure_Code.Dependency_Conflict)
	expect_confirmed_text(t, &buffer, editor.Revision(5), "YaZcdQf")
	conflict_after, _, _ := history.store_stats(&store)
	testing.expect_value(t, conflict_after.active_node, conflict_before.active_node)
	testing.expect_value(t, conflict_after.usage.retained_nodes, conflict_before.usage.retained_nodes)

	request.analysis_operations = 1
	_, exhausted_ok, exhausted_failure := transaction_history_selective_undo(
		&store,
		&buffer,
		request,
		Transaction_ID(807),
		Undo_Unit_ID(807),
		Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, !exhausted_ok)
	testing.expect_value(t, exhausted_failure.history_failure.code, history.Failure_Code.Work_Limit)
	request.analysis_operations = 128
	request.target_unit = history.Unit_ID(999)
	_, stale_ok, stale_failure := transaction_history_selective_undo(
		&store,
		&buffer,
		request,
		Transaction_ID(808),
		Undo_Unit_ID(808),
		Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, !stale_ok)
	testing.expect_value(t, stale_failure.history_failure.code, history.Failure_Code.Stale_Generation)
	request.target_unit = history.Unit_ID(1)
	request.cancelled = true
	_, cancelled_ok, cancelled_failure := transaction_history_selective_undo(
		&store,
		&buffer,
		request,
		Transaction_ID(809),
		Undo_Unit_ID(809),
		Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, !cancelled_ok)
	testing.expect_value(t, cancelled_failure.history_failure.code, history.Failure_Code.Cancelled)
	expect_confirmed_text(t, &buffer, editor.Revision(5), "YaZcdQf")

	history.store_close(&store)
	editor.buffer_close(&buffer)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
}

@(private = "file")
Selective_Test_Splice :: struct {
	start:       u64,
	end:         u64,
	replacement: string,
}

@(private = "file")
selective_test_commit_batch :: proc(
	t: ^testing.T,
	buffer: ^editor.Buffer,
	store: ^history.Store,
	tracking: ^mem.Tracking_Allocator,
	transaction_id: Transaction_ID,
	inputs: []Selective_Test_Splice,
) {
	root := test_transaction_begin(t, buffer, tracking, transaction_id)
	splices := make([]Base_Splice, len(inputs))
	defer delete(splices)
	for input, index in inputs {
		start, start_ok, _ := editor.buffer_position(buffer, editor.Byte_Offset(input.start))
		end, end_ok, _ := editor.buffer_position(buffer, editor.Byte_Offset(input.end))
		testing.expect(t, start_ok && end_ok)
		splices[index] = Base_Splice{start = start, end = end, replacement = input.replacement}
	}
	applied, _ := transaction_apply_batch(&root, splices)
	tracked, _ := transaction_track_history(&root, store)
	validated, _ := transaction_validate(&root)
	_, committed, _ := transaction_commit(&root)
	closed, _ := transaction_close(&root)
	testing.expect(t, applied && tracked && validated && committed && closed)
}
