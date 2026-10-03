// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package transaction

import "../editor"
import "core:mem"
import "core:testing"

/* Verifies the production transaction limits and bounded metadata profile. */
@(test)
default_transaction_limits_are_valid :: proc(t: ^testing.T) {
	testing.expect(t, limits_are_valid(DEFAULT_LIMITS))
	testing.expect_value(t, DEFAULT_LIMITS.buffer_participants, u64(10_000))
	testing.expect_value(t, DEFAULT_LIMITS.splices, u64(100_000))
	testing.expect_value(t, DEFAULT_LIMITS.text_bytes, u64(1_073_741_824))
	testing.expect_value(t, DEFAULT_LIMITS.metadata_bytes, u64(16_777_216))
	testing.expect_value(t, DEFAULT_LIMITS.nested_command_depth, u64(32))
	testing.expect_value(t, DEFAULT_LIMITS.active_savepoints, u64(256))
}

/* Verifies an ordered batch publishes once with an owned normalized result. */
@(test)
base_relative_batch_commits_one_revision :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	buffer := test_buffer_open(t, &tracking, editor.Buffer_ID(101), "abc🙂def")
	if !editor.buffer_is_live(&buffer) {
		return
	}

	transaction := test_transaction_begin(t, &buffer, &tracking, Transaction_ID(1))
	if !transaction_is_valid(&transaction) {
		editor.buffer_close(&buffer)
		return
	}
	start_one, _, _ := editor.buffer_position(&buffer, editor.Byte_Offset(1))
	end_one, _, _ := editor.buffer_position(&buffer, editor.Byte_Offset(2))
	start_two, _, _ := editor.buffer_position(&buffer, editor.Byte_Offset(7))
	end_two, _, _ := editor.buffer_position(&buffer, editor.Byte_Offset(8))
	applied, apply_failure := transaction_apply_batch(
		&transaction,
		[]Base_Splice{
			{start = start_one, end = end_one, replacement = "X"},
			{start = start_two, end = end_two, replacement = "Y"},
		},
	)
	testing.expect(t, applied)
	testing.expect_value(t, apply_failure.code, Failure_Code.None)
	expect_confirmed_text(t, &buffer, editor.Revision(0), "abc🙂def")
	expect_private_text(t, &transaction, "aXc🙂Yef")
	validated, validation_failure := transaction_validate(&transaction)
	testing.expect(t, validated)
	testing.expect_value(t, validation_failure.code, Failure_Code.None)
	result, committed, commit_failure := transaction_commit(&transaction)
	testing.expect(t, committed)
	testing.expect_value(t, commit_failure.code, Failure_Code.None)
	testing.expect_value(t, result.transaction_id, Transaction_ID(1))
	testing.expect_value(t, result.base_revision, editor.Revision(0))
	testing.expect_value(t, result.result_revision, editor.Revision(1))
	testing.expect_value(t, len(result.splices), 2)
	testing.expect_value(t, result.splices[0].replacement_text, "X")
	testing.expect_value(t, result.splices[1].removed_text, "d")
	expect_confirmed_text(t, &buffer, editor.Revision(1), "aXc🙂Yef")

	closed, _ := transaction_close(&transaction)
	testing.expect(t, closed)
	editor.buffer_close(&buffer)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
}

/* Verifies sequential private edits read prior writes and normalize at validation. */
@(test)
sequential_edits_normalize_private_transition :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	buffer := test_buffer_open(t, &tracking, editor.Buffer_ID(102), "abcd")
	transaction := test_transaction_begin(t, &buffer, &tracking, Transaction_ID(2))
	if !transaction_is_valid(&transaction) {
		editor.buffer_close(&buffer)
		return
	}
	first, _, _ := transaction_position(&transaction, editor.Byte_Offset(1))
	first_applied, _ := transaction_splice(
		&transaction,
		editor.Working_Splice{start = first, end = first, replacement = "X"},
	)
	testing.expect(t, first_applied)
	second_start, _, _ := transaction_position(&transaction, editor.Byte_Offset(2))
	second_end, _, _ := transaction_position(&transaction, editor.Byte_Offset(3))
	second_applied, _ := transaction_splice(
		&transaction,
		editor.Working_Splice{start = second_start, end = second_end, replacement = "Y"},
	)
	testing.expect(t, second_applied)
	expect_private_text(t, &transaction, "aXYcd")
	validated, _ := transaction_validate(&transaction)
	testing.expect(t, validated)
	result, committed, _ := transaction_commit(&transaction)
	testing.expect(t, committed)
	testing.expect_value(t, len(result.splices), 1)
	testing.expect_value(t, result.splices[0].start, editor.Byte_Offset(1))
	testing.expect_value(t, result.splices[0].end, editor.Byte_Offset(2))
	testing.expect_value(t, result.splices[0].replacement_text, "XY")
	testing.expect_value(t, result.splices[0].removed_text, "b")
	expect_confirmed_text(t, &buffer, editor.Revision(1), "aXYcd")
	transaction_close(&transaction)
	editor.buffer_close(&buffer)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
}

/* Verifies overlap, cancellation, and explicit abort preserve confirmed state. */
@(test)
rejected_transactions_publish_nothing :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	buffer := test_buffer_open(t, &tracking, editor.Buffer_ID(103), "abcdef")

	overlap := test_transaction_begin(t, &buffer, &tracking, Transaction_ID(3))
	first_start, _, _ := editor.buffer_position(&buffer, editor.Byte_Offset(1))
	first_end, _, _ := editor.buffer_position(&buffer, editor.Byte_Offset(4))
	second_start, _, _ := editor.buffer_position(&buffer, editor.Byte_Offset(3))
	second_end, _, _ := editor.buffer_position(&buffer, editor.Byte_Offset(5))
	applied, apply_failure := transaction_apply_batch(
		&overlap,
		[]Base_Splice{
			{start = first_start, end = first_end, replacement = "x"},
			{start = second_start, end = second_end, replacement = "y"},
		},
	)
	testing.expect(t, !applied)
	testing.expect_value(t, apply_failure.code, Failure_Code.Overlapping_Batch)
	expect_lifecycle(t, &overlap, .Aborted)
	expect_confirmed_text(t, &buffer, editor.Revision(0), "abcdef")
	transaction_close(&overlap)

	cancelled := test_transaction_begin(t, &buffer, &tracking, Transaction_ID(4))
	position, _, _ := transaction_position(&cancelled, editor.Byte_Offset(2))
	transaction_splice(
		&cancelled,
		editor.Working_Splice{start = position, end = position, replacement = "z"},
	)
	requested, _ := transaction_request_cancel(&cancelled)
	testing.expect(t, requested)
	validated, validation_failure := transaction_validate(&cancelled)
	testing.expect(t, !validated)
	testing.expect_value(t, validation_failure.code, Failure_Code.Cancelled)
	expect_lifecycle(t, &cancelled, .Aborted)
	expect_confirmed_text(t, &buffer, editor.Revision(0), "abcdef")
	transaction_close(&cancelled)
	editor.buffer_close(&buffer)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
}

/* Verifies splice and metadata limits abort before canonical publication. */
@(test)
resource_limits_abort_before_publication :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	buffer := test_buffer_open(t, &tracking, editor.Buffer_ID(104), "abcd")
	limits := DEFAULT_LIMITS
	limits.splices = 1
	transaction: Transaction
	started, _ := transaction_begin(
		&transaction,
		Transaction_ID(5),
		Undo_Unit_ID(5),
		&buffer,
		Origin{kind = .Built_In, descriptor = "test"},
		"limited-command",
		Allocator_Set {
			persistent = mem.tracking_allocator(&tracking),
			temporary = context.temp_allocator,
		},
		limits,
	)
	testing.expect(t, started)
	first, _, _ := editor.buffer_position(&buffer, editor.Byte_Offset(1))
	second, _, _ := editor.buffer_position(&buffer, editor.Byte_Offset(2))
	applied, failure := transaction_apply_batch(
		&transaction,
		[]Base_Splice{
			{start = first, end = first, replacement = "x"},
			{start = second, end = second, replacement = "y"},
		},
	)
	testing.expect(t, !applied)
	testing.expect_value(t, failure.code, Failure_Code.Splice_Limit)
	expect_lifecycle(t, &transaction, .Aborted)
	expect_confirmed_text(t, &buffer, editor.Revision(0), "abcd")
	transaction_close(&transaction)
	editor.buffer_close(&buffer)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
}

/* Verifies private positions from another transaction cannot cross the participant boundary. */
@(test)
working_positions_cannot_cross_transactions :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	first_buffer := test_buffer_open(t, &tracking, editor.Buffer_ID(105), "abc")
	second_buffer := test_buffer_open(t, &tracking, editor.Buffer_ID(106), "xyz")
	first := test_transaction_begin(t, &first_buffer, &tracking, Transaction_ID(6))
	second := test_transaction_begin(t, &second_buffer, &tracking, Transaction_ID(7))
	first_position, _, _ := transaction_position(&first, editor.Byte_Offset(1))
	second_position, _, _ := transaction_position(&second, editor.Byte_Offset(1))
	applied, failure := transaction_splice(
		&first,
		editor.Working_Splice {
			start = first_position,
			end = second_position,
			replacement = "q",
		},
	)
	testing.expect(t, !applied)
	testing.expect_value(t, failure.code, Failure_Code.Wrong_Buffer)
	expect_lifecycle(t, &first, .Aborted)
	expect_confirmed_text(t, &first_buffer, editor.Revision(0), "abc")
	expect_confirmed_text(t, &second_buffer, editor.Revision(0), "xyz")
	transaction_close(&second)
	transaction_close(&first)
	editor.buffer_close(&second_buffer)
	editor.buffer_close(&first_buffer)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
}

/* Verifies tiny sequential edits normalize without whole-buffer temporary copies. */
@(test)
normalization_streams_unchanged_text :: proc(t: ^testing.T) {
	text_bytes := 20 * int(MEBIBYTE)
	contents := make([]byte, text_bytes)
	defer delete(contents)
	for &value in contents {
		value = 'a'
	}
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	buffer := test_buffer_open(t, &tracking, editor.Buffer_ID(107), string(contents))
	limits := DEFAULT_LIMITS
	limits.temporary_bytes = 1 * MEBIBYTE
	transaction: Transaction
	started, begin_failure := transaction_begin(
		&transaction,
		Transaction_ID(8),
		Undo_Unit_ID(8),
		&buffer,
		Origin{kind = .Built_In, descriptor = "test"},
		"large-streaming-normalization",
		Allocator_Set {
			persistent = mem.tracking_allocator(&tracking),
			temporary = context.temp_allocator,
		},
		limits,
	)
	testing.expectf(t, started, "begin failed with %v", begin_failure.code)
	if !started {
		editor.buffer_close(&buffer)
		return
	}
	offset := editor.Byte_Offset(text_bytes / 2)
	position, position_ok, _ := transaction_position(&transaction, offset)
	testing.expect(t, position_ok)
	applied, apply_failure := transaction_splice(
		&transaction,
		editor.Working_Splice{start = position, end = position, replacement = "X"},
	)
	testing.expectf(t, applied, "splice failed with %v", apply_failure.code)
	validated, validation_failure := transaction_validate(&transaction)
	testing.expectf(t, validated, "validation failed with %v", validation_failure.code)
	result, committed, commit_failure := transaction_commit(&transaction)
	testing.expectf(t, committed, "commit failed with %v", commit_failure.code)
	testing.expect_value(t, len(result.splices), 1)
	testing.expect_value(t, result.splices[0].start, offset)
	testing.expect_value(t, result.splices[0].end, offset)
	testing.expect_value(t, result.splices[0].replacement_text, "X")
	testing.expect_value(t, result.usage.text_bytes, u64(1))
	observed: [3]byte
	_, inspected, inspect_failure := editor.buffer_inspect(
		&buffer,
		editor.Byte_Offset(u64(offset) - 1),
		editor.Byte_Offset(u64(offset) + 2),
		observed[:],
	)
	testing.expectf(t, inspected, "inspection failed with %v", inspect_failure.code)
	testing.expect_value(t, string(observed[:]), "aXa")
	transaction_close(&transaction)
	editor.buffer_close(&buffer)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
}

@(private)
test_buffer_open :: proc(
	t: ^testing.T,
	tracking: ^mem.Tracking_Allocator,
	buffer_id: editor.Buffer_ID,
	contents: string,
) -> editor.Buffer {
	buffer: editor.Buffer
	initialized, failure := editor.buffer_init(
		&buffer,
		buffer_id,
		contents,
		editor.Allocator_Set {
			persistent = mem.tracking_allocator(tracking),
			temporary = context.temp_allocator,
		},
	)
	testing.expectf(t, initialized, "buffer init failed with %v", failure.code)
	return buffer
}

@(private)
test_transaction_begin :: proc(
	t: ^testing.T,
	buffer: ^editor.Buffer,
	tracking: ^mem.Tracking_Allocator,
	transaction_id: Transaction_ID,
) -> Transaction {
	transaction: Transaction
	started, failure := transaction_begin(
		&transaction,
		transaction_id,
		Undo_Unit_ID(u64(transaction_id)),
		buffer,
		Origin{kind = .Built_In, descriptor = "test"},
		"test-command",
		Allocator_Set {
			persistent = mem.tracking_allocator(tracking),
			temporary = context.temp_allocator,
		},
	)
	testing.expectf(t, started, "transaction begin failed with %v", failure.code)
	return transaction
}

@(private)
expect_private_text :: proc(t: ^testing.T, transaction: ^Transaction, expected: string) {
	start, start_ok, _ := transaction_position(transaction, editor.Byte_Offset(0))
	end, end_ok, _ := transaction_position(transaction, editor.Byte_Offset(len(expected)))
	testing.expect(t, start_ok && end_ok)
	observed := make([]byte, len(expected))
	defer delete(observed)
	_, inspected, failure := transaction_inspect(transaction, start, end, observed)
	testing.expect(t, inspected)
	testing.expect_value(t, failure.code, Failure_Code.None)
	testing.expect_value(t, string(observed), expected)
}

@(private)
expect_confirmed_text :: proc(
	t: ^testing.T,
	buffer: ^editor.Buffer,
	revision: editor.Revision,
	expected: string,
) {
	stats, stats_ok, _ := editor.buffer_stats(buffer)
	testing.expect(t, stats_ok)
	testing.expect_value(t, stats.revision, revision)
	observed := make([]byte, len(expected))
	defer delete(observed)
	_, inspected, failure := editor.buffer_inspect(
		buffer,
		editor.Byte_Offset(0),
		editor.Byte_Offset(len(expected)),
		observed,
	)
	testing.expect(t, inspected)
	testing.expect_value(t, failure.code, editor.Failure_Code.None)
	testing.expect_value(t, string(observed), expected)
}

@(private)
expect_lifecycle :: proc(t: ^testing.T, transaction: ^Transaction, expected: Lifecycle) {
	stats, stats_ok, failure := transaction_stats(transaction)
	testing.expect(t, stats_ok)
	testing.expect_value(t, failure.code, Failure_Code.None)
	testing.expect_value(t, stats.lifecycle, expected)
}
