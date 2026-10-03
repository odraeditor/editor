// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package transaction

import "../editor"
import "core:mem"
import "core:testing"

/* Compares deterministic non-overlapping batches with a simple contiguous oracle. */
@(test)
deterministic_batches_match_a_contiguous_model :: proc(t: ^testing.T) {
	for case_index in 0 ..< 64 {
		base := "0123456789abcdefghijklmnopqrstuvwxyz"
		first_start := u64(case_index % 8)
		first_end := first_start + u64(case_index % 3)
		second_start := u64(18 + case_index % 8)
		second_end := second_start + u64((case_index + 1) % 3)
		replacements := [?]string{"", "X", "λ", "🙂"}
		first_replacement := replacements[case_index % len(replacements)]
		second_replacement := replacements[(case_index + 1) % len(replacements)]
		expected := contiguous_batch_apply(
			base,
			first_start,
			first_end,
			first_replacement,
			second_start,
			second_end,
			second_replacement,
		)

		tracking: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracking, context.allocator)
		buffer := test_buffer_open(
			t,
			&tracking,
			editor.Buffer_ID(200 + case_index),
			base,
		)
		transaction := test_transaction_begin(
			t,
			&buffer,
			&tracking,
			Transaction_ID(200 + case_index),
		)
		first_start_position, _, _ := editor.buffer_position(&buffer, editor.Byte_Offset(first_start))
		first_end_position, _, _ := editor.buffer_position(&buffer, editor.Byte_Offset(first_end))
		second_start_position, _, _ := editor.buffer_position(&buffer, editor.Byte_Offset(second_start))
		second_end_position, _, _ := editor.buffer_position(&buffer, editor.Byte_Offset(second_end))
		applied, apply_failure := transaction_apply_batch(
			&transaction,
			[]Base_Splice{
				{
					start = first_start_position,
					end = first_end_position,
					replacement = first_replacement,
				},
				{
					start = second_start_position,
					end = second_end_position,
					replacement = second_replacement,
				},
			},
		)
		testing.expectf(t, applied, "case %d apply failed with %v", case_index, apply_failure.code)
		if applied {
			validated, validation_failure := transaction_validate(&transaction)
			testing.expectf(t, validated, "case %d validation failed with %v", case_index, validation_failure.code)
			if validated {
				_, committed, commit_failure := transaction_commit(&transaction)
				testing.expectf(t, committed, "case %d commit failed with %v", case_index, commit_failure.code)
			}
		}
		expect_confirmed_text(t, &buffer, editor.Revision(1), expected)
		transaction_close(&transaction)
		editor.buffer_close(&buffer)
		testing.expect_value(t, tracking.current_memory_allocated, i64(0))
		mem.tracking_allocator_destroy(&tracking)
		delete(expected)
	}
}

/* Verifies stable same-boundary insertion order and overlap negative space. */
@(test)
batch_ordering_contract_is_deterministic :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	buffer := test_buffer_open(t, &tracking, editor.Buffer_ID(270), "ab")
	transaction := test_transaction_begin(t, &buffer, &tracking, Transaction_ID(270))
	boundary, _, _ := editor.buffer_position(&buffer, editor.Byte_Offset(1))
	applied, apply_failure := transaction_apply_batch(
		&transaction,
		[]Base_Splice{
			{start = boundary, end = boundary, replacement = "A"},
			{start = boundary, end = boundary, replacement = "B"},
			{start = boundary, end = boundary, replacement = "C"},
		},
	)
	testing.expect(t, applied)
	testing.expect_value(t, apply_failure.code, Failure_Code.None)
	transaction_validate(&transaction)
	transaction_commit(&transaction)
	expect_confirmed_text(t, &buffer, editor.Revision(1), "aABCb")
	transaction_close(&transaction)
	editor.buffer_close(&buffer)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
}

@(private)
contiguous_batch_apply :: proc(
	base: string,
	first_start, first_end: u64,
	first_replacement: string,
	second_start, second_end: u64,
	second_replacement: string,
) -> string {
	result_length := u64(len(base)) - (first_end - first_start) - (second_end - second_start) +
	                 u64(len(first_replacement) + len(second_replacement))
	result := make([]byte, int(result_length))
	result_offset := 0
	result_offset += copy(result[result_offset:], base[:int(first_start)])
	result_offset += copy(result[result_offset:], first_replacement)
	result_offset += copy(result[result_offset:], base[int(first_end):int(second_start)])
	result_offset += copy(result[result_offset:], second_replacement)
	result_offset += copy(result[result_offset:], base[int(second_end):])
	assert(result_offset == len(result))
	return string(result)
}
