// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package transaction

import "../editor"
import "core:mem"
import "core:testing"

@(private)
Observer_Probe :: struct {
	transaction: ^Transaction,
	event:       Commit_Event,
	invoked:     bool,
	reentrant_close_ok: bool,
	reentrant_failure:  Failure_Context,
	reentrant_splice_ok: bool,
	reentrant_splice_failure: Failure_Context,
}

/* Verifies observer failure is post-commit and same-transaction reentrant close is rejected. */
@(test)
observer_failure_preserves_commit :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	buffer := test_buffer_open(t, &tracking, editor.Buffer_ID(601), "abc")
	transaction := test_transaction_begin(t, &buffer, &tracking, Transaction_ID(601))
	one, _, _ := transaction_position(&transaction, editor.Byte_Offset(1))
	applied, _ := transaction_splice(
		&transaction,
		editor.Working_Splice{start = one, end = one, replacement = "X"},
	)
	testing.expect(t, applied)
	validated, _ := transaction_validate(&transaction)
	testing.expect(t, validated)
	probe := Observer_Probe{transaction = &transaction}
	result, committed, commit_failure := transaction_commit(
		&transaction,
		Commit_Observer {
			procedure = failing_observer,
			user_data = &probe,
		},
	)
	testing.expectf(t, committed, "commit failed with %v", commit_failure.code)
	testing.expect(t, probe.invoked)
	testing.expect(t, !probe.reentrant_close_ok)
	testing.expect_value(t, probe.reentrant_failure.code, Failure_Code.Reentrant_Mutation)
	testing.expect(t, !probe.reentrant_splice_ok)
	testing.expect_value(t, probe.reentrant_splice_failure.code, Failure_Code.Reentrant_Mutation)
	testing.expect_value(t, result.observer_status, Observer_Status.Failed)
	testing.expect_value(t, probe.event.transaction_id, Transaction_ID(601))
	testing.expect_value(t, probe.event.undo_unit_id, Undo_Unit_ID(601))
	testing.expect_value(t, probe.event.command, "test-command")
	testing.expect_value(t, len(probe.event.splices), 1)
	expect_confirmed_text(t, &buffer, editor.Revision(1), "aXbc")
	closed, close_failure := transaction_close(&transaction)
	testing.expectf(t, closed, "close failed with %v", close_failure.code)
	editor.buffer_close(&buffer)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
}

@(private)
failing_observer :: proc(user_data: rawptr, event: Commit_Event) -> bool {
	probe := (^Observer_Probe)(user_data)
	probe.invoked = true
	probe.event = event
	probe.reentrant_splice_ok, probe.reentrant_splice_failure = transaction_splice(
		probe.transaction,
		{},
	)
	probe.reentrant_close_ok, probe.reentrant_failure = transaction_close(probe.transaction)
	return false
}
