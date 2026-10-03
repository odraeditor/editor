// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package transaction

import "../editor"
import "../history"
import editor_view "../view"

/*
transaction_history_navigate publishes one ordinary single-buffer undo or redo.
History activity moves only after the exact transaction result becomes canonical.
*/
transaction_history_navigate :: proc(
	store: ^history.Store,
	buffer: ^editor.Buffer,
	kind: history.Navigation_Kind,
	transaction_id: Transaction_ID,
	undo_unit_id: Undo_Unit_ID,
	allocators: Allocator_Set,
	limits := DEFAULT_LIMITS,
	view_registry: ^editor_view.Registry = nil,
	invoking_view := editor_view.View_Handle{},
	active_node := history.Node_ID{},
	target_node := history.Node_ID{},
	policy_generation := history.Policy_Generation(0),
	analysis_operations := u64(0),
	observer := Commit_Observer{},
) -> (result: history.Navigation_Result, ok: bool, failure: Failure_Context) {
	buffer_stats, buffer_ok, editor_failure := editor.buffer_stats(buffer)
	if !buffer_ok {
		return {}, false, transaction_editor_failure(transaction_id, 0, editor_failure)
	}
	plan, preliminary, prepared, history_failure := history.navigation_prepare(
		store,
		history.Navigation_Request {
			kind = kind,
			buffer_id = buffer_stats.buffer_id,
			current_revision = buffer_stats.revision,
			active_node = active_node,
			target_node = target_node,
			policy_generation = policy_generation,
			analysis_operations = analysis_operations,
		},
	)
	if !prepared {
		return {}, false, navigation_history_failure(transaction_id, buffer_stats, history_failure)
	}
	if preliminary.outcome != .Applied {
		return preliminary, true, {}
	}
	command := "undo"
	if kind == .Redo {
		command = "redo"
	} else if kind == .Select_Branch {
		command = "select-history-branch"
	}
	restore_view: editor_view.View_Handle
	restore_ok := false
	reserved_mark: editor.Anchor
	defer {
		if reserved_mark.buffer_id != editor.Buffer_ID(0) {
			released, _ := editor.buffer_anchor_release(buffer, &reserved_mark)
			assert(released)
		}
	}
	if plan.cursor.present && view_registry != nil {
		restore_view, restore_ok = navigation_restore_view(
			view_registry,
			plan.cursor,
			invoking_view,
		)
		if restore_ok && plan.cursor.mark_present {
			restore_snapshot, snapshot_ok, snapshot_failure := editor_view.snapshot(
				view_registry,
				restore_view,
			)
			if !snapshot_ok {
				history.navigation_abort(&plan)
				return {}, false, transaction_view_failure_for_navigation(
					transaction_id,
					buffer_stats,
					snapshot_failure,
				)
			}
			if !restore_snapshot.mark.present {
				created: bool
				anchor_failure: editor.Failure_Context
				reserved_mark, created, anchor_failure = editor.buffer_anchor_create(
					buffer,
					restore_snapshot.point_position,
					.Left,
					.Collapse,
				)
				if !created {
					history.navigation_abort(&plan)
					return {}, false, transaction_editor_failure(
						transaction_id,
						0,
						anchor_failure,
					)
				}
			}
		}
	}
	root: Transaction
	started, begin_failure := transaction_begin(
		&root,
		transaction_id,
		undo_unit_id,
		buffer,
		Origin{kind = .Built_In, descriptor = "history"},
		command,
		allocators,
		limits,
	)
	if !started {
		history.navigation_abort(&plan)
		return {}, false, begin_failure
	}
	for edit in plan.edits {
		start, start_ok, start_failure := transaction_position(&root, edit.start)
		if !start_ok {
			history.navigation_abort(&plan)
			transaction_close(&root)
			return {}, false, start_failure
		}
		end, end_ok, end_failure := transaction_position(&root, edit.end)
		if !end_ok {
			history.navigation_abort(&plan)
			transaction_close(&root)
			return {}, false, end_failure
		}
		applied, apply_failure := transaction_splice(
			&root,
			editor.Working_Splice{start = start, end = end, replacement = edit.replacement},
		)
		if !applied {
			history.navigation_abort(&plan)
			transaction_close(&root)
			return {}, false, apply_failure
		}
	}
	if plan.cursor.present && view_registry != nil {
		if restore_ok {
			target, target_ok, target_failure := transaction_position(&root, plan.cursor.byte_offset)
			if !target_ok {
				history.navigation_abort(&plan)
				transaction_close(&root)
				return {}, false, target_failure
			}
			mark_result := editor_view.Logical_Mark_Result.Absent
			mark_target: editor.Working_Position
			if plan.cursor.mark_present {
				mark_target, target_ok, target_failure = transaction_position(
					&root,
					plan.cursor.mark_offset,
				)
				if !target_ok {
					history.navigation_abort(&plan)
					transaction_close(&root)
					return {}, false, target_failure
				}
				mark_result = .Position
			}
			region_result := editor_view.Logical_Region_Result.Deactivate
			if plan.cursor.region_active {
				region_result = .Activate
			}
			view_prepared, view_failure := transaction_prepare_logical_view(
				&root,
				view_registry,
				restore_view,
				target,
				plan.cursor.desired_display_column,
				region_result,
				mark_result,
				mark_target,
				&reserved_mark,
				plan.cursor.selection_shape,
				plan.cursor.rectangle_column_policy,
			)
			if !view_prepared {
				history.navigation_abort(&plan)
				transaction_close(&root)
				return {}, false, view_failure
			}
		}
	}
	validated, validation_failure := transaction_validate(&root)
	if !validated {
		history.navigation_abort(&plan)
		transaction_close(&root)
		return {}, false, validation_failure
	}
	commit_result, committed, commit_failure := transaction_commit(&root, observer)
	if !committed {
		history.navigation_abort(&plan)
		transaction_close(&root)
		return {}, false, commit_failure
	}
	result = history.navigation_commit_reserved(&plan, commit_result.result_revision)
	closed, close_failure := transaction_close(&root)
	assert(closed && close_failure.code == .None)
	return result, true, {}
}

@(private)
transaction_view_failure_for_navigation :: proc(
	transaction_id: Transaction_ID,
	buffer: editor.Buffer_Stats,
	view_failure: editor_view.Failure_Context,
) -> Failure_Context {
	return Failure_Context {
		code = .View_Failure,
		transaction_id = transaction_id,
		buffer_id = buffer.buffer_id,
		base_revision = buffer.revision,
		view_failure = view_failure,
	}
}

@(private)
navigation_restore_view :: proc(
	registry: ^editor_view.Registry,
	cursor: history.Cursor_Restore,
	invoking: editor_view.View_Handle,
) -> (editor_view.View_Handle, bool) {
	initiating, initiating_ok, _ := editor_view.snapshot(registry, cursor.initiating_view)
	if initiating_ok && initiating.buffer_id == cursor.buffer_id {
		return cursor.initiating_view, true
	}
	fallback, fallback_ok, _ := editor_view.snapshot(registry, invoking)
	if fallback_ok && fallback.buffer_id == cursor.buffer_id {
		return invoking, true
	}
	return {}, false
}

@(private)
navigation_history_failure :: proc(
	transaction_id: Transaction_ID,
	buffer: editor.Buffer_Stats,
	history_failure: history.Failure_Context,
) -> Failure_Context {
	return Failure_Context {
		code = .History_Failure,
		transaction_id = transaction_id,
		buffer_id = buffer.buffer_id,
		base_revision = buffer.revision,
		limit = history_failure.maximum,
		actual = history_failure.actual,
		history_failure = history_failure,
	}
}
