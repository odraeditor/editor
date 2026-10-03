// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package transaction

import "../editor"
import "core:mem"
import "core:testing"

/* Verifies an autopair-style child command joins two edits into one root undo unit. */
@(test)
autopair_child_joins_typed_delimiters_atomically :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	buffer := test_buffer_open(t, &tracking, editor.Buffer_ID(410), "ab")
	transaction := test_transaction_begin(t, &buffer, &tracking, Transaction_ID(410))
	open_position, _, _ := transaction_position(&transaction, editor.Byte_Offset(1))
	open_applied, _ := transaction_splice(
		&transaction,
		editor.Working_Splice{start = open_position, end = open_position, replacement = "("},
	)
	testing.expect(t, open_applied)
	child, child_started, _ := transaction_nested_begin(
		&transaction,
		Origin{kind = .Built_In, descriptor = "autopair"},
		"insert-closing-delimiter",
	)
	testing.expect(t, child_started)
	close_position, _, _ := transaction_position(&transaction, editor.Byte_Offset(2))
	close_applied, _ := transaction_splice(
		&transaction,
		editor.Working_Splice{start = close_position, end = close_position, replacement = ")"},
	)
	testing.expect(t, close_applied)
	joined, _ := transaction_nested_succeed(&transaction, &child)
	testing.expect(t, joined)
	expect_private_text(t, &transaction, "a()b")
	validated, _ := transaction_validate(&transaction)
	testing.expect(t, validated)
	result, committed, _ := transaction_commit(&transaction)
	testing.expect(t, committed)
	testing.expect_value(t, result.undo_unit_id, Undo_Unit_ID(410))
	testing.expect_value(t, len(result.splices), 1)
	testing.expect_value(t, result.splices[0].replacement_text, "()")
	expect_confirmed_text(t, &buffer, editor.Revision(1), "a()b")
	transaction_close(&transaction)
	editor.buffer_close(&buffer)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
}

/* Verifies nested success joins one root revision and retains only root undo metadata. */
@(test)
nested_success_joins_one_root_commit :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	buffer := test_buffer_open(t, &tracking, editor.Buffer_ID(401), "ab")
	transaction := test_transaction_begin(t, &buffer, &tracking, Transaction_ID(401))

	root_position, _, _ := transaction_position(&transaction, editor.Byte_Offset(1))
	root_applied, _ := transaction_splice(
		&transaction,
		editor.Working_Splice{start = root_position, end = root_position, replacement = "X"},
	)
	testing.expect(t, root_applied)
	nested, begun, begin_failure := transaction_nested_begin(
		&transaction,
		Origin{kind = .Language_Tool, descriptor = "nested-test"},
		"insert-pair",
	)
	testing.expectf(t, begun, "nested begin failed with %v", begin_failure.code)
	nested_stats, stats_ok, _ := transaction_nested_stats(&transaction, &nested)
	testing.expect(t, stats_ok)
	testing.expect_value(t, nested_stats.depth, u64(1))
	testing.expect_value(t, nested_stats.origin.kind, Origin_Kind.Language_Tool)
	testing.expect_value(t, nested_stats.origin.descriptor, "nested-test")
	testing.expect_value(t, nested_stats.command, "insert-pair")

	nested_position, _, _ := transaction_position(&transaction, editor.Byte_Offset(2))
	nested_applied, _ := transaction_splice(
		&transaction,
		editor.Working_Splice{start = nested_position, end = nested_position, replacement = "()"},
	)
	testing.expect(t, nested_applied)
	joined, join_failure := transaction_nested_succeed(&transaction, &nested)
	testing.expectf(t, joined, "nested join failed with %v", join_failure.code)
	testing.expect(t, !nested_command_is_valid(&nested))
	expect_private_text(t, &transaction, "aX()b")

	stats, transaction_stats_ok, _ := transaction_stats(&transaction)
	testing.expect(t, transaction_stats_ok)
	testing.expect_value(t, stats.nesting_depth, u64(0))
	testing.expect_value(t, stats.active_savepoints, u64(0))
	testing.expect_value(t, stats.usage.nested_commands, u64(1))
	testing.expect_value(t, stats.usage.savepoints, u64(1))
	validated, _ := transaction_validate(&transaction)
	testing.expect(t, validated)
	result, committed, _ := transaction_commit(&transaction)
	testing.expect(t, committed)
	testing.expect_value(t, result.undo_unit_id, Undo_Unit_ID(401))
	testing.expect_value(t, result.origin.kind, Origin_Kind.Built_In)
	testing.expect_value(t, result.command, "test-command")
	expect_confirmed_text(t, &buffer, editor.Revision(1), "aX()b")

	transaction_close(&transaction)
	editor.buffer_close(&buffer)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
}

/* Verifies a handled nested edit failure restores its savepoint and permits root continuation. */
@(test)
handled_nested_failure_restores_and_continues :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	buffer := test_buffer_open(t, &tracking, editor.Buffer_ID(402), "abcd")
	transaction := test_transaction_begin(t, &buffer, &tracking, Transaction_ID(402))
	root_position, _, _ := transaction_position(&transaction, editor.Byte_Offset(1))
	transaction_splice(
		&transaction,
		editor.Working_Splice{start = root_position, end = root_position, replacement = "X"},
	)
	nested, begun, _ := transaction_nested_begin(
		&transaction,
		Origin{kind = .Built_In, descriptor = "nested-test"},
		"failing-child",
	)
	testing.expect(t, begun)
	stale_position, _, _ := transaction_position(&transaction, editor.Byte_Offset(2))
	first_applied, _ := transaction_splice(
		&transaction,
		editor.Working_Splice{start = stale_position, end = stale_position, replacement = "Y"},
	)
	testing.expect(t, first_applied)
	second_applied, second_failure := transaction_splice(
		&transaction,
		editor.Working_Splice{start = stale_position, end = stale_position, replacement = "Z"},
	)
	testing.expect(t, !second_applied)
	testing.expect_value(t, second_failure.code, Failure_Code.Stale_Revision)
	joined, join_failure := transaction_nested_succeed(&transaction, &nested)
	testing.expect(t, !joined)
	testing.expect_value(t, join_failure.code, Failure_Code.Invalid_State)
	rolled_back, rollback_failure := transaction_nested_fail(&transaction, &nested, .Handled)
	testing.expectf(t, rolled_back, "nested rollback failed with %v", rollback_failure.code)
	expect_private_text(t, &transaction, "aXbcd")

	continued_position, _, _ := transaction_position(&transaction, editor.Byte_Offset(5))
	continued, _ := transaction_splice(
		&transaction,
		editor.Working_Splice {
			start = continued_position,
			end = continued_position,
			replacement = "!",
		},
	)
	testing.expect(t, continued)
	validated, _ := transaction_validate(&transaction)
	testing.expect(t, validated)
	_, committed, _ := transaction_commit(&transaction)
	testing.expect(t, committed)
	expect_confirmed_text(t, &buffer, editor.Revision(1), "aXbcd!")

	transaction_close(&transaction)
	editor.buffer_close(&buffer)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
}

/* Verifies rollback restores a previously normalized base batch without rebuilding it. */
@(test)
handled_nested_failure_restores_base_batch :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	buffer := test_buffer_open(t, &tracking, editor.Buffer_ID(407), "abcd")
	transaction := test_transaction_begin(t, &buffer, &tracking, Transaction_ID(407))
	start, _, _ := editor.buffer_position(&buffer, editor.Byte_Offset(1))
	end, _, _ := editor.buffer_position(&buffer, editor.Byte_Offset(2))
	batch_applied, _ := transaction_apply_batch(
		&transaction,
		[]Base_Splice{{start = start, end = end, replacement = "B"}},
	)
	testing.expect(t, batch_applied)
	nested, begun, _ := transaction_nested_begin(
		&transaction,
		Origin{kind = .Built_In, descriptor = "nested-test"},
		"discard-sequential-child",
	)
	testing.expect(t, begun)
	position, _, _ := transaction_position(&transaction, editor.Byte_Offset(2))
	transaction_splice(
		&transaction,
		editor.Working_Splice{start = position, end = position, replacement = "X"},
	)
	rolled_back, _ := transaction_nested_fail(&transaction, &nested, .Handled)
	testing.expect(t, rolled_back)
	expect_private_text(t, &transaction, "aBcd")
	validated, _ := transaction_validate(&transaction)
	testing.expect(t, validated)
	result, committed, _ := transaction_commit(&transaction)
	testing.expect(t, committed)
	testing.expect_value(t, len(result.splices), 1)
	testing.expect_value(t, result.splices[0].start, editor.Byte_Offset(1))
	testing.expect_value(t, result.splices[0].replacement_text, "B")

	transaction_close(&transaction)
	editor.buffer_close(&buffer)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
}

/* Verifies an unhandled nested failure aborts the complete unpublished root. */
@(test)
unhandled_nested_failure_aborts_root :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	buffer := test_buffer_open(t, &tracking, editor.Buffer_ID(403), "abc")
	transaction := test_transaction_begin(t, &buffer, &tracking, Transaction_ID(403))
	position, _, _ := transaction_position(&transaction, editor.Byte_Offset(1))
	transaction_splice(
		&transaction,
		editor.Working_Splice{start = position, end = position, replacement = "root"},
	)
	nested, begun, _ := transaction_nested_begin(
		&transaction,
		Origin{kind = .Built_In, descriptor = "nested-test"},
		"propagated-child",
	)
	testing.expect(t, begun)
	nested_position, _, _ := transaction_position(&transaction, editor.Byte_Offset(1))
	transaction_splice(
		&transaction,
		editor.Working_Splice{start = nested_position, end = nested_position, replacement = "child"},
	)
	propagated, failure := transaction_nested_fail(&transaction, &nested, .Unhandled)
	testing.expectf(t, propagated, "unhandled rollback failed with %v", failure.code)
	expect_lifecycle(t, &transaction, .Aborted)
	expect_confirmed_text(t, &buffer, editor.Revision(0), "abc")
	_, committed, commit_failure := transaction_commit(&transaction)
	testing.expect(t, !committed)
	testing.expect_value(t, commit_failure.code, Failure_Code.Invalid_State)

	transaction_close(&transaction)
	editor.buffer_close(&buffer)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
}

/* Verifies nested frames complete in stack order and retain one root undo unit. */
@(test)
nested_commands_require_lifo_completion :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	buffer := test_buffer_open(t, &tracking, editor.Buffer_ID(404), "abc")
	transaction := test_transaction_begin(t, &buffer, &tracking, Transaction_ID(404))
	outer, outer_ok, _ := transaction_nested_begin(
		&transaction,
		Origin{kind = .Built_In, descriptor = "nested-test"},
		"outer",
	)
	inner, inner_ok, _ := transaction_nested_begin(
		&transaction,
		Origin{kind = .Built_In, descriptor = "nested-test"},
		"inner",
	)
	testing.expect(t, outer_ok && inner_ok)
	completed_out_of_order, order_failure := transaction_nested_succeed(&transaction, &outer)
	testing.expect(t, !completed_out_of_order)
	testing.expect_value(t, order_failure.code, Failure_Code.Invalid_Nested_Command)
	inner_joined, _ := transaction_nested_succeed(&transaction, &inner)
	outer_joined, _ := transaction_nested_succeed(&transaction, &outer)
	testing.expect(t, inner_joined && outer_joined)
	stats, stats_ok, _ := transaction_stats(&transaction)
	testing.expect(t, stats_ok)
	testing.expect_value(t, stats.usage.nested_commands, u64(2))
	testing.expect_value(t, stats.usage.savepoints, u64(2))

	transaction_abort(&transaction)
	transaction_close(&transaction)
	editor.buffer_close(&buffer)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
}

/* Verifies command depth and active savepoint budgets reject independently. */
@(test)
command_and_savepoint_limits_are_independent :: proc(t: ^testing.T) {
	cases := [2]bool{false, true}
	for savepoint_case, case_index in cases {
		tracking: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracking, context.allocator)
		buffer := test_buffer_open(
			t,
			&tracking,
			editor.Buffer_ID(405 + case_index),
			"abc",
		)
		limits := DEFAULT_LIMITS
		if savepoint_case {
			limits.nested_command_depth = 2
			limits.active_savepoints = 1
		} else {
			limits.nested_command_depth = 1
			limits.active_savepoints = 2
		}
		transaction: Transaction
		started, _ := transaction_begin(
			&transaction,
			Transaction_ID(405 + case_index),
			Undo_Unit_ID(405 + case_index),
			&buffer,
			Origin{kind = .Built_In, descriptor = "test"},
			"limited-nesting",
			Allocator_Set {
				persistent = mem.tracking_allocator(&tracking),
				temporary = context.temp_allocator,
			},
			limits,
		)
		testing.expect(t, started)
		outer, outer_ok, _ := transaction_nested_begin(
			&transaction,
			Origin{kind = .Built_In, descriptor = "test"},
			"outer",
		)
		testing.expect(t, outer_ok)
		_, inner_ok, inner_failure := transaction_nested_begin(
			&transaction,
			Origin{kind = .Built_In, descriptor = "test"},
			"inner",
		)
		testing.expect(t, !inner_ok)
		if savepoint_case {
			testing.expect_value(t, inner_failure.code, Failure_Code.Savepoint_Limit)
		} else {
			testing.expect_value(t, inner_failure.code, Failure_Code.Nesting_Limit)
		}
		transaction_nested_fail(&transaction, &outer, .Handled)
		transaction_abort(&transaction)
		transaction_close(&transaction)
		editor.buffer_close(&buffer)
		testing.expect_value(t, tracking.current_memory_allocated, i64(0))
		mem.tracking_allocator_destroy(&tracking)
	}
}
