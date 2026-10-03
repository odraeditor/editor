// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package transaction

import "../editor"
import editor_view "../view"
import "core:mem"
import "core:testing"

/* Verifies text and logical view state become observable through one committed result. */
@(test)
logical_view_participant_publishes_with_text :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	buffer := test_buffer_open(t, &tracking, editor.Buffer_ID(501), "abc")
	registry: editor_view.Registry
	registry_ready, _ := editor_view.registry_init(
		&registry,
		editor_view.Registry_ID(501),
		mem.tracking_allocator(&tracking),
	)
	testing.expect(t, registry_ready)
	handle, created, _ := editor_view.create(&registry, &buffer)
	testing.expect(t, created)
	if !registry_ready || !created {
		editor_view.registry_close(&registry)
		editor.buffer_close(&buffer)
		return
	}
	one, _, _ := editor.buffer_position(&buffer, editor.Byte_Offset(1))
	mark_set, _ := editor_view.set_mark(&registry, handle, one)
	testing.expect(t, mark_set)

	transaction := test_transaction_begin(t, &buffer, &tracking, Transaction_ID(501))
	working_one, _, _ := transaction_position(&transaction, editor.Byte_Offset(1))
	applied, _ := transaction_splice(
		&transaction,
		editor.Working_Splice{start = working_one, end = working_one, replacement = "X"},
	)
	testing.expect(t, applied)
	result_cursor, result_cursor_ok, _ := transaction_position(&transaction, editor.Byte_Offset(2))
	testing.expect(t, result_cursor_ok)
	prepared, prepare_failure := transaction_prepare_logical_view(
		&transaction,
		&registry,
		handle,
		result_cursor,
		2,
		.Deactivate,
	)
	testing.expectf(t, prepared, "view prepare failed with %v", prepare_failure.code)
	blocked, blocked_failure := editor_view.set_point(&registry, handle, one)
	testing.expect(t, !blocked)
	testing.expect_value(t, blocked_failure.code, editor_view.Failure_Code.Active_Preparation)
	validated, validation_failure := transaction_validate(&transaction)
	testing.expectf(t, validated, "validation failed with %v", validation_failure.code)
	result, committed, commit_failure := transaction_commit(&transaction)
	testing.expectf(t, committed, "commit failed with %v", commit_failure.code)
	testing.expect(t, result.logical_view.present)
	testing.expect_value(t, result.logical_view.result_revision, editor.Revision(1))
	testing.expect_value(
		t,
		result.logical_view.point_position.byte_offset,
		editor.Byte_Offset(2),
	)
	testing.expect(t, result.logical_view.mark.present)
	testing.expect(t, !result.logical_view.region_active)
	testing.expect_value(t, result.logical_view.desired_display_column, u32(2))
	expect_confirmed_text(t, &buffer, editor.Revision(1), "aXbc")
	logical, logical_ok, _ := editor_view.snapshot(&registry, handle)
	testing.expect(t, logical_ok)
	testing.expect_value(t, logical.point_position.byte_offset, editor.Byte_Offset(2))
	testing.expect(t, logical.mark.present)
	testing.expect(t, !logical.region_active)

	transaction_close(&transaction)
	editor_view.close(&registry, &handle)
	editor_view.registry_close(&registry)
	editor.buffer_close(&buffer)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
}

/* Verifies abort releases a frozen logical participant without exposing either candidate state. */
@(test)
view_abort_restores_mutability :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	buffer := test_buffer_open(t, &tracking, editor.Buffer_ID(502), "abc")
	registry: editor_view.Registry
	editor_view.registry_init(
		&registry,
		editor_view.Registry_ID(502),
		mem.tracking_allocator(&tracking),
	)
	handle, created, _ := editor_view.create(&registry, &buffer)
	testing.expect(t, created)
	if !created {
		editor_view.registry_close(&registry)
		editor.buffer_close(&buffer)
		return
	}
	one, _, _ := editor.buffer_position(&buffer, editor.Byte_Offset(1))
	editor_view.move_point(&registry, handle, one, 1, .Activate)
	before, _, _ := editor_view.snapshot(&registry, handle)

	transaction := test_transaction_begin(t, &buffer, &tracking, Transaction_ID(502))
	working_one, _, _ := transaction_position(&transaction, editor.Byte_Offset(1))
	transaction_splice(
		&transaction,
		editor.Working_Splice{start = working_one, end = working_one, replacement = "X"},
	)
	result_cursor, _, _ := transaction_position(&transaction, editor.Byte_Offset(2))
	prepared, _ := transaction_prepare_logical_view(
		&transaction,
		&registry,
		handle,
		result_cursor,
		2,
		.Deactivate,
	)
	testing.expect(t, prepared)
	transaction_request_cancel(&transaction)
	validated, validation_failure := transaction_validate(&transaction)
	testing.expect(t, !validated)
	testing.expect_value(t, validation_failure.code, Failure_Code.Cancelled)
	expect_confirmed_text(t, &buffer, editor.Revision(0), "abc")
	after, after_ok, _ := editor_view.snapshot(&registry, handle)
	testing.expect(t, after_ok)
	testing.expect_value(t, after.state_generation, before.state_generation)
	testing.expect_value(t, after.point_position, before.point_position)
	testing.expect_value(t, after.mark, before.mark)
	testing.expect_value(t, after.region_active, before.region_active)
	two, _, _ := editor.buffer_position(&buffer, editor.Byte_Offset(2))
	moved, move_failure := editor_view.move_point(&registry, handle, two, 2)
	testing.expectf(t, moved, "view remained frozen with %v", move_failure.code)

	transaction_close(&transaction)
	editor_view.close(&registry, &handle)
	editor_view.registry_close(&registry)
	editor.buffer_close(&buffer)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
}
