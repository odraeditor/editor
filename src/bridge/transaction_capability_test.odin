// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package bridge

import "../editor"
import edit_transaction "../transaction"
import "core:testing"

/* Verifies command-scoped batches, private reads, sequential edits, and stale rejection. */
@(test)
transactions_lose_released_authority :: proc(t: ^testing.T) {
	buffer: editor.Buffer
	buffer_ready, _ := editor.buffer_init(
		&buffer,
		editor.Buffer_ID(81),
		"abcd",
		editor.Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, buffer_ready)
	if !buffer_ready {
		return
	}
	transaction: edit_transaction.Transaction
	started, _ := edit_transaction.transaction_begin(
		&transaction,
		edit_transaction.Transaction_ID(81),
		edit_transaction.Undo_Unit_ID(81),
		&buffer,
		edit_transaction.Origin{kind = .Racket, descriptor = "capability-test"},
		"composed-command",
		edit_transaction.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	testing.expect(t, started)
	if !started {
		editor.buffer_close(&buffer)
		return
	}

	registry: Transaction_Capability_Registry
	initialized, _ := transaction_capability_registry_init(&registry, Registry_ID(33))
	testing.expect(t, initialized)
	capability, acquired, acquire_failure := transaction_capability_acquire(
		&registry,
		&transaction,
		&buffer,
		701,
	)
	testing.expectf(t, acquired, "capability acquire failed with %v", acquire_failure.code)

	replacement_text := "XY"
	replacements := transmute([]byte)replacement_text
	batch_applied, batch_failure := transaction_capability_apply_batch(
		&registry,
		capability,
		701,
		[]Transaction_Edit_Record{
			{start = 0, end = 1, replacement_offset = 0, replacement_bytes = 1},
			{start = 3, end = 4, replacement_offset = 1, replacement_bytes = 1},
		},
		replacements,
		context.temp_allocator,
	)
	testing.expectf(t, batch_applied, "batch failed with %v", batch_failure.code)

	spliced, splice_failure := transaction_capability_splice(
		&registry,
		capability,
		701,
		2,
		2,
		"!",
	)
	testing.expectf(t, spliced, "splice failed with %v", splice_failure.code)
	observed: [5]byte
	copied, inspected, inspect_failure := transaction_capability_inspect(
		&registry,
		capability,
		701,
		0,
		5,
		observed[:],
	)
	testing.expectf(t, inspected, "inspect failed with %v", inspect_failure.code)
	testing.expect_value(t, copied, u64(5))
	testing.expect_value(t, string(observed[:]), "Xb!cY")

	_, wrong_command, wrong_command_failure := transaction_capability_inspect(
		&registry,
		capability,
		702,
		0,
		1,
		observed[:1],
	)
	testing.expect(t, !wrong_command)
	testing.expect_value(t, wrong_command_failure.code, Failure_Code.Wrong_Command)

	nested, nested_ok, nested_failure := transaction_capability_nested_begin(
		&registry,
		capability,
		701,
		edit_transaction.Origin{kind = .Racket, descriptor = "child"},
		"child-command",
	)
	testing.expectf(t, nested_ok, "nested begin failed with %v", nested_failure.code)
	nested_done, nested_done_failure := transaction_capability_nested_finish(
		&registry,
		capability,
		701,
		nested,
		.Handled,
		true,
	)
	testing.expectf(t, nested_done, "nested finish failed with %v", nested_done_failure.code)

	old_capability := capability
	released, release_failure := transaction_capability_release(&registry, &capability)
	testing.expectf(t, released, "release failed with %v", release_failure.code)
	_, inspected, inspect_failure = transaction_capability_inspect(
		&registry,
		old_capability,
		701,
		0,
		1,
		observed[:1],
	)
	testing.expect(t, !inspected)
	testing.expect_value(t, inspect_failure.code, Failure_Code.Stale_Capability)
	closed, close_failure := transaction_capability_registry_close(&registry)
	testing.expectf(t, closed, "registry close failed with %v", close_failure.code)

	validated, _ := edit_transaction.transaction_validate(&transaction)
	testing.expect(t, validated)
	_, committed, _ := edit_transaction.transaction_commit(&transaction)
	testing.expect(t, committed)
	confirmed: [5]byte
	_, confirmed_ok, _ := editor.buffer_inspect(&buffer, 0, 5, confirmed[:])
	testing.expect(t, confirmed_ok)
	testing.expect_value(t, string(confirmed[:]), "Xb!cY")
	edit_transaction.transaction_close(&transaction)
	editor.buffer_close(&buffer)
}

/* Verifies malformed copied records and reentrant use fail before mutation. */
@(test)
transaction_rejects_bad_reentry :: proc(t: ^testing.T) {
	buffer: editor.Buffer
	editor.buffer_init(
		&buffer,
		editor.Buffer_ID(82),
		"abc",
		editor.Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	transaction: edit_transaction.Transaction
	edit_transaction.transaction_begin(
		&transaction,
		edit_transaction.Transaction_ID(82),
		edit_transaction.Undo_Unit_ID(82),
		&buffer,
		edit_transaction.Origin{kind = .Racket, descriptor = "capability-test"},
		"malformed-command",
		edit_transaction.Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	registry: Transaction_Capability_Registry
	transaction_capability_registry_init(&registry, Registry_ID(34))
	capability, _, _ := transaction_capability_acquire(&registry, &transaction, &buffer, 801)
	malformed_text := "x"
	applied, failure := transaction_capability_apply_batch(
		&registry,
		capability,
		801,
		[]Transaction_Edit_Record{{start = 0, end = 1, replacement_offset = 2, replacement_bytes = 2}},
		transmute([]byte)malformed_text,
		context.temp_allocator,
	)
	testing.expect(t, !applied)
	testing.expect_value(t, failure.code, Failure_Code.Malformed_Record)

	slot, resolved := transaction_capability_resolve(&registry, capability, 801, true, true)
	testing.expect_value(t, resolved.code, Failure_Code.None)
	slot.call_active = true
	one_byte: [1]byte
	_, inspected, inspect_failure := transaction_capability_inspect(
		&registry,
		capability,
		801,
		0,
		1,
		one_byte[:],
	)
	testing.expect(t, !inspected)
	testing.expect_value(t, inspect_failure.code, Failure_Code.Reentrant_Call)
	slot.call_active = false

	transaction_capability_release(&registry, &capability)
	transaction_capability_registry_close(&registry)
	edit_transaction.transaction_abort(&transaction)
	edit_transaction.transaction_close(&transaction)
	editor.buffer_close(&buffer)
}
