// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../editor"
import "../history"
import edit_transaction "../transaction"
import editor_view "../view"
import "base:runtime"
import "core:mem"
import "core:testing"

/* Verifies native history commands inspect, select, and compensate through one facade. */
@(test)
native_history_command_facade_is_checked :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	allocator := mem.tracking_allocator(&tracking)
	buffer: editor.Buffer
	buffer_ok, _ := editor.buffer_init(
		&buffer,
		editor.Buffer_ID(901),
		"abc",
		editor.Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, buffer_ok)
	if !buffer_ok {
		return
	}
	store: history.Store
	store_ok, _ := history.store_init(
		&store,
		history.Store_ID(91),
		editor.Buffer_ID(901),
		editor.Revision(0),
		history.Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, store_ok)
	if !store_ok {
		editor.buffer_close(&buffer)
		return
	}
	command_history_test_edit(t, &buffer, &store, allocator, 1, 1, 2, "X")
	command_history_test_edit(t, &buffer, &store, allocator, 2, 3, 3, "Y")
	stats, _, _ := history.store_stats(&store)
	ctx := History_Command_Context {
		store = &store,
		buffer = &buffer,
		persistent_allocator = allocator,
		temporary_allocator = context.temp_allocator,
		transaction_id = edit_transaction.Transaction_ID(10),
		undo_unit_id = edit_transaction.Undo_Unit_ID(10),
	}
	inspection, inspected, inspect_failure := history_command_inspect(
		ctx,
		history.Inspection_Request {
			buffer_id = stats.buffer_id,
			current_revision = stats.current_revision,
			active_node = stats.active_node,
			policy_generation = stats.policy_generation,
			result_limit = 8,
			traversal_limit = 8,
		},
	)
	testing.expect(t, inspected)
	testing.expect_value(t, inspect_failure.code, Failure_Code.None)
	testing.expect_value(t, inspection.active_projection.command, "test-command")
	testing.expect(t, inspection.has_parent)
	history_command_inspection_close(&inspection, context.temp_allocator)

	stale := stats
	stale.policy_generation = history.Policy_Generation(u64(stale.policy_generation) + 1)
	_, selected, select_failure := history_command_select_branch(
		ctx,
		stale.active_node,
		stale.active_parent,
		stale.policy_generation,
		32,
	)
	testing.expect(t, !selected)
	testing.expect_value(t, select_failure.code, Failure_Code.History_Failure)
	testing.expect_value(t, select_failure.history_code, history.Failure_Code.Stale_Generation)

	history.store_close(&store)
	editor.buffer_close(&buffer)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
}

/* Verifies an active reverse-direction region becomes the checked selective range. */
@(test)
active_region_narrows_selective_history_requests :: proc(t: ^testing.T) {
	buffer: editor.Buffer
	buffer_ok, _ := editor.buffer_init(
		&buffer,
		editor.Buffer_ID(902),
		"abcdef",
		editor.Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, buffer_ok)
	if !buffer_ok {
		return
	}
	defer editor.buffer_close(&buffer)
	registry: editor_view.Registry
	registry_ok, _ := editor_view.registry_init(
		&registry,
		editor_view.Registry_ID(92),
		context.allocator,
	)
	testing.expect(t, registry_ok)
	if !registry_ok {
		return
	}
	defer editor_view.registry_close(&registry)
	view, view_ok, _ := editor_view.create(&registry, &buffer)
	testing.expect(t, view_ok)
	if !view_ok {
		return
	}
	defer editor_view.close(&registry, &view)
	mark, _, _ := editor.buffer_position(&buffer, editor.Byte_Offset(4))
	point, _, _ := editor.buffer_position(&buffer, editor.Byte_Offset(1))
	marked, _ := editor_view.set_mark(&registry, view, mark, true)
	moved, _ := editor_view.move_point(&registry, view, point, 1, .Preserve)
	testing.expect(t, marked && moved)
	stats, _, _ := editor.buffer_stats(&buffer)
	selected, selected_ok, failure := history_command_selected_range(
		History_Command_Context {
			buffer = &buffer,
			view_registry = &registry,
			view = view,
		},
		stats,
		{},
	)
	testing.expectf(t, selected_ok, "active range failed with %v", failure.code)
	testing.expect(t, selected.present)
	testing.expect_value(t, selected.revision, editor.Revision(0))
	testing.expect_value(t, selected.start, editor.Byte_Offset(1))
	testing.expect_value(t, selected.end, editor.Byte_Offset(4))
}

@(private = "file")
command_history_test_edit :: proc(
	t: ^testing.T,
	buffer: ^editor.Buffer,
	store: ^history.Store,
	allocator: runtime.Allocator,
	identity, start_offset, end_offset: u64,
	replacement: string,
) {
	transaction: edit_transaction.Transaction
	started, _ := edit_transaction.transaction_begin(
		&transaction,
		edit_transaction.Transaction_ID(identity),
		edit_transaction.Undo_Unit_ID(identity),
		buffer,
		edit_transaction.Origin{kind = .Built_In, descriptor = "command-test"},
		"test-command",
		edit_transaction.Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, started)
	start, _, _ := editor.buffer_position(buffer, editor.Byte_Offset(start_offset))
	end, _, _ := editor.buffer_position(buffer, editor.Byte_Offset(end_offset))
	applied, _ := edit_transaction.transaction_apply_batch(
		&transaction,
		[]edit_transaction.Base_Splice {{start = start, end = end, replacement = replacement}},
	)
	tracked, _ := edit_transaction.transaction_track_history(&transaction, store)
	validated, _ := edit_transaction.transaction_validate(&transaction)
	_, committed, _ := edit_transaction.transaction_commit(&transaction)
	closed, _ := edit_transaction.transaction_close(&transaction)
	testing.expect(t, applied && tracked && validated && committed && closed)
}
