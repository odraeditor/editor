// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package transaction

import "../editor"
import "../history"
import editor_view "../view"
import "core:mem"
import "core:testing"

/* Verifies history navigation shares selection while retaining per-view stored points. */
@(test)
navigation_restores_cursor_with_fallback :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	allocator := mem.tracking_allocator(&tracking)
	buffer := test_buffer_open(t, &tracking, editor.Buffer_ID(707), "abc")
	registry: editor_view.Registry
	registry_ok, _ := editor_view.registry_init(&registry, editor_view.Registry_ID(70), allocator)
	testing.expect(t, registry_ok)
	first, first_ok, _ := editor_view.create(&registry, &buffer)
	second, second_ok, _ := editor_view.clone_additional(&registry, first)
	testing.expect(t, first_ok && second_ok)
	if !registry_ok || !first_ok || !second_ok {
		return
	}
	first_start, _, _ := editor.buffer_position(&buffer, editor.Byte_Offset(1))
	second_start, _, _ := editor.buffer_position(&buffer, editor.Byte_Offset(3))
	first_mark, _, _ := editor.buffer_position(&buffer, editor.Byte_Offset(3))
	editor_view.set_point(&registry, first, first_start)
	editor_view.set_point(&registry, second, second_start)
	editor_view.set_mark(&registry, first, first_mark, true)

	store: history.Store
	store_ok, _ := history.store_init(
		&store,
		history.Store_ID(7),
		editor.Buffer_ID(707),
		editor.Revision(0),
		history.Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, store_ok)
	root := test_transaction_begin(t, &buffer, &tracking, Transaction_ID(710))
	inserted, _ := transaction_apply_batch(
		&root,
		[]Base_Splice{{start = first_start, end = first_start, replacement = "X"}},
	)
	result_cursor, _, _ := transaction_position(&root, editor.Byte_Offset(2))
	view_prepared, _ := transaction_prepare_logical_view(
		&root,
		&registry,
		first,
		result_cursor,
		2,
		.Deactivate,
	)
	tracked, _ := transaction_track_history(&root, &store)
	validated, _ := transaction_validate(&root)
	_, committed, _ := transaction_commit(&root)
	transaction_close(&root)
	testing.expect(t, inserted && view_prepared && tracked && validated && committed)
	expect_confirmed_text(t, &buffer, editor.Revision(1), "aXbc")
	first_after_edit, _, _ := editor_view.snapshot(&registry, first)
	second_after_edit, _, _ := editor_view.snapshot(&registry, second)
	testing.expect_value(t, first_after_edit.point_position.byte_offset, editor.Byte_Offset(2))
	testing.expect_value(t, second_after_edit.point_position.byte_offset, editor.Byte_Offset(4))
	testing.expect_value(t, first_after_edit.effective_point_position.byte_offset, editor.Byte_Offset(2))
	testing.expect_value(t, second_after_edit.effective_point_position.byte_offset, editor.Byte_Offset(2))
	testing.expect(t, first_after_edit.mark.present && !first_after_edit.region_active)
	testing.expect_value(t, first_after_edit.mark.position.byte_offset, editor.Byte_Offset(4))
	testing.expect(t, second_after_edit.mark.present && !second_after_edit.region_active)
	testing.expect_value(t, second_after_edit.mark.position.byte_offset, editor.Byte_Offset(4))

	end, _, _ := editor.buffer_position(&buffer, editor.Byte_Offset(4))
	editor_view.set_point(&registry, first, end)
	allocators := Allocator_Set{persistent = allocator, temporary = context.temp_allocator}
	_, undo_ok, _ := transaction_history_navigate(
		&store,
		&buffer,
		.Undo,
		Transaction_ID(711),
		Undo_Unit_ID(711),
		allocators,
		DEFAULT_LIMITS,
		&registry,
		second,
	)
	testing.expect(t, undo_ok)
	first_after_undo, _, _ := editor_view.snapshot(&registry, first)
	second_after_undo, _, _ := editor_view.snapshot(&registry, second)
	testing.expect_value(t, first_after_undo.point_position.byte_offset, editor.Byte_Offset(1))
	testing.expect_value(t, second_after_undo.point_position.byte_offset, editor.Byte_Offset(3))
	testing.expect_value(t, first_after_undo.effective_point_position.byte_offset, editor.Byte_Offset(1))
	testing.expect_value(t, second_after_undo.effective_point_position.byte_offset, editor.Byte_Offset(1))
	testing.expect(t, first_after_undo.mark.present && first_after_undo.region_active)
	testing.expect_value(t, first_after_undo.mark.position.byte_offset, editor.Byte_Offset(3))
	testing.expect(t, second_after_undo.mark.present && second_after_undo.region_active)
	testing.expect_value(t, second_after_undo.mark.position.byte_offset, editor.Byte_Offset(3))

	_, redo_ok, _ := transaction_history_navigate(
		&store,
		&buffer,
		.Redo,
		Transaction_ID(712),
		Undo_Unit_ID(712),
		allocators,
		DEFAULT_LIMITS,
		&registry,
		second,
	)
	testing.expect(t, redo_ok)
	first_after_redo, _, _ := editor_view.snapshot(&registry, first)
	second_after_redo, _, _ := editor_view.snapshot(&registry, second)
	testing.expect_value(t, first_after_redo.point_position.byte_offset, editor.Byte_Offset(2))
	testing.expect_value(t, second_after_redo.point_position.byte_offset, editor.Byte_Offset(4))
	testing.expect_value(t, first_after_redo.effective_point_position.byte_offset, editor.Byte_Offset(2))
	testing.expect_value(t, second_after_redo.effective_point_position.byte_offset, editor.Byte_Offset(2))
	testing.expect(t, first_after_redo.mark.present && !first_after_redo.region_active)
	testing.expect_value(t, first_after_redo.mark.position.byte_offset, editor.Byte_Offset(4))
	testing.expect(t, second_after_redo.mark.present && !second_after_redo.region_active)
	testing.expect_value(t, second_after_redo.mark.position.byte_offset, editor.Byte_Offset(4))

	editor_view.close(&registry, &first)
	_, fallback_ok, fallback_failure := transaction_history_navigate(
		&store,
		&buffer,
		.Undo,
		Transaction_ID(713),
		Undo_Unit_ID(713),
		allocators,
		DEFAULT_LIMITS,
		&registry,
		second,
	)
	testing.expectf(
		t,
		fallback_ok,
		"fallback navigation failed: %v/%v/%v",
		fallback_failure.code,
		fallback_failure.view_failure.code,
		fallback_failure.view_failure.editor_failure.code,
	)
	fallback, _, _ := editor_view.snapshot(&registry, second)
	testing.expect_value(t, fallback.point_position.byte_offset, editor.Byte_Offset(1))
	testing.expect_value(t, fallback.effective_point_position.byte_offset, editor.Byte_Offset(1))
	testing.expect(t, fallback.mark.present && fallback.region_active)
	testing.expect_value(t, fallback.mark.position.byte_offset, editor.Byte_Offset(3))

	editor_view.close(&registry, &second)
	editor_view.registry_close(&registry)
	history.store_close(&store)
	editor.buffer_close(&buffer)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
}

/* Verifies grouped undo uses the first cursor boundary and redo uses the final boundary. */
@(test)
grouped_history_restores_outer_boundaries :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	allocator := mem.tracking_allocator(&tracking)
	buffer := test_buffer_open(t, &tracking, editor.Buffer_ID(708), "")
	registry: editor_view.Registry
	editor_view.registry_init(&registry, editor_view.Registry_ID(71), allocator)
	view, view_ok, _ := editor_view.create(&registry, &buffer)
	testing.expect(t, view_ok)
	store: history.Store
	history.store_init(
		&store,
		history.Store_ID(8),
		editor.Buffer_ID(708),
		editor.Revision(0),
		history.Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
	)

	for index in 0 ..< 2 {
		identity := u64(index + 1)
		root := test_transaction_begin(t, &buffer, &tracking, Transaction_ID(identity))
		position, _, _ := editor.buffer_position(&buffer, editor.Byte_Offset(index))
		transaction_apply_batch(&root, []Base_Splice{{start = position, end = position, replacement = "x"}})
		target, _, _ := transaction_position(&root, editor.Byte_Offset(index + 1))
		transaction_prepare_logical_view(&root, &registry, view, target, u32(index + 1), .Deactivate)
		transaction_track_history(
			&root,
			&store,
			history.Grouping_Context {
				kind = .Typing_Insert,
				view_id = view.view_id,
				view_generation = view.generation,
				continuity = 1,
				event_sequence = identity,
				monotonic_milliseconds = identity * 10,
			},
		)
		transaction_validate(&root)
		transaction_commit(&root)
		transaction_close(&root)
	}
	allocators := Allocator_Set{persistent = allocator, temporary = context.temp_allocator}
	transaction_history_navigate(
		&store, &buffer, .Undo, Transaction_ID(720), Undo_Unit_ID(720), allocators,
		DEFAULT_LIMITS, &registry, view,
	)
	after_undo, _, _ := editor_view.snapshot(&registry, view)
	testing.expect_value(t, after_undo.point_position.byte_offset, editor.Byte_Offset(0))
	transaction_history_navigate(
		&store, &buffer, .Redo, Transaction_ID(721), Undo_Unit_ID(721), allocators,
		DEFAULT_LIMITS, &registry, view,
	)
	after_redo, _, _ := editor_view.snapshot(&registry, view)
	testing.expect_value(t, after_redo.point_position.byte_offset, editor.Byte_Offset(2))

	editor_view.close(&registry, &view)
	editor_view.registry_close(&registry)
	history.store_close(&store)
	editor.buffer_close(&buffer)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
}
