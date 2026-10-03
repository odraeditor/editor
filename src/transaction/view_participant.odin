// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package transaction

import "../editor"
import "../history"
import editor_view "../view"

/*
transaction_prepare_logical_view admits one initiating view result after text editing is complete.
The current private target, desired column, and region outcome publish with the text root.
*/
transaction_prepare_logical_view :: proc(
	transaction: ^Transaction,
	registry: ^editor_view.Registry,
	handle: editor_view.View_Handle,
	target: editor.Working_Position,
	desired_display_column: u32,
	region: editor_view.Logical_Region_Result,
	mark := editor_view.Logical_Mark_Result.Preserve,
	mark_target := editor.Working_Position{},
	reserved_mark: ^editor.Anchor = nil,
	selection_shape := editor.Selection_Shape.Linear,
	rectangle_column_policy := editor.Rectangle_Column_Policy.Grapheme,
) -> (ok: bool, failure: Failure_Context) {
	state, state_failure := transaction_building_state(transaction)
	if state_failure.code != .None {
		return false, state_failure
	}
	if state.nesting_depth != 0 || state.active_savepoints != 0 {
		return false, transaction_failure(state, .Invalid_State)
	}
	if state.has_logical_view {
		failure = transaction_limit_failure(
			state,
			.Participant_Limit,
			state.limits.logical_views,
			2,
		)
		transaction_abort_state(state)
		return false, failure
	}
	before, before_ok, before_failure := editor_view.snapshot(registry, handle)
	if !before_ok {
		return false, transaction_view_failure(state, before_failure)
	}
	current, current_ok, current_failure := editor.working_revision_position(
		&state.working,
		target.byte_offset,
	)
	if !current_ok || current != target {
		if current_failure.code == .None {
			current_failure = editor.Failure_Context {
				code = .Stale_Revision,
				buffer_id = state.buffer_id,
				revision = state.base_revision,
				start = target.byte_offset,
			}
		}
		failure = transaction_editor_failure(
			state.transaction_id,
			state.admitted_splices,
			current_failure,
		)
		transaction_abort_state(state)
		return false, failure
	}
	if mark == .Position {
		current_mark, mark_ok, mark_failure := editor.working_revision_position(
			&state.working,
			mark_target.byte_offset,
		)
		if !mark_ok || current_mark != mark_target {
			if mark_failure.code == .None {
				mark_failure = editor.Failure_Context {
					code = .Stale_Revision,
					buffer_id = state.buffer_id,
					revision = state.base_revision,
					start = mark_target.byte_offset,
				}
			}
			transaction_abort_state(state)
			return false, transaction_editor_failure(
				state.transaction_id,
				state.admitted_splices,
				mark_failure,
			)
		}
	}
	prepared: editor_view.Prepared_Logical_Edit
	prepared_ok, prepare_failure := editor_view.logical_edit_prepare(
		registry,
		handle,
		editor_view.Logical_Edit_Request {
			buffer_id = state.buffer_id,
			base_revision = state.base_revision,
			result_point_offset = target.byte_offset,
			desired_display_column = desired_display_column,
			region = region,
			mark = mark,
			result_mark_offset = mark_target.byte_offset,
			selection_shape = selection_shape,
			rectangle_column_policy = rectangle_column_policy,
		},
		&prepared,
		reserved_mark,
	)
	if !prepared_ok {
		failure = transaction_view_failure(state, prepare_failure)
		transaction_abort_state(state)
		return false, failure
	}
	state.logical_view = prepared
	state.logical_view_target = target
	state.has_logical_view = true
	state.history_cursor = history.Cursor_Context {
		present = true,
		view = handle,
		buffer_id = state.buffer_id,
		base_revision = state.base_revision,
		result_revision = editor.Revision(u64(state.base_revision) + 1),
		before_byte_offset = before.point_position.byte_offset,
		after_byte_offset = target.byte_offset,
		before_desired_column = before.desired_display_column,
		after_desired_column = desired_display_column,
		before_mark_present = before.mark.present,
		before_mark_offset = before.mark.position.byte_offset if before.mark.present else 0,
		before_region_active = before.region_active,
		before_selection_shape = before.selection_shape,
		before_rectangle_column_policy = before.rectangle_column_policy,
	}
	switch mark {
	case .Preserve:
		state.history_cursor.after_mark_present = before.mark.present
		state.history_cursor.after_mark_offset = before.mark.position.byte_offset if before.mark.present else 0
		state.history_mark_requires_transform = before.mark.present
	case .Absent:
		state.history_cursor.after_mark_present = false
	case .Position:
		state.history_cursor.after_mark_present = true
		state.history_cursor.after_mark_offset = mark_target.byte_offset
	case .Invalid:
		unreachable()
	}
	switch region {
	case .Preserve:
		state.history_cursor.after_region_active = before.region_active
		state.history_cursor.after_selection_shape = before.selection_shape
		state.history_cursor.after_rectangle_column_policy = before.rectangle_column_policy
	case .Deactivate:
		state.history_cursor.after_region_active = false
		state.history_cursor.after_selection_shape = .Linear
		state.history_cursor.after_rectangle_column_policy = .Grapheme
	case .Activate:
		state.history_cursor.after_region_active = true
		state.history_cursor.after_selection_shape = selection_shape
		state.history_cursor.after_rectangle_column_policy = rectangle_column_policy
	case .Invalid:
		unreachable()
	}
	return true, {}
}

@(private)
transaction_history_cursor_finalize :: proc(state: ^Transaction_State) {
	if !state.history_cursor.present || !state.history_mark_requires_transform {
		return
	}
	offset := u64(state.history_cursor.after_mark_offset)
	delta: i64
	for splice in state.normalized {
		start_value := i64(u64(splice.start)) + delta
		end_value := i64(u64(splice.end)) + delta
		assert(start_value >= 0 && end_value >= start_value)
		start := u64(start_value)
		end := u64(end_value)
		inserted := u64(len(splice.replacement_text))
		if offset >= start {
			if start == end && offset == start {
				// Retained mark uses left affinity and stays before insertion.
			} else if offset < end {
				offset = start
			} else if offset == end {
				offset = start + inserted
			} else {
				offset = offset - (end - start) + inserted
			}
		}
		delta += i64(inserted) - i64(end - start)
	}
	state.history_cursor.after_mark_offset = editor.Byte_Offset(offset)
	state.history_mark_requires_transform = false
}

@(private)
transaction_logical_view_validate :: proc(
	state: ^Transaction_State,
) -> (ok: bool, failure: Failure_Context) {
	if !state.has_logical_view {
		return true, {}
	}
	current, current_ok, current_failure := editor.working_revision_position(
		&state.working,
		state.logical_view_target.byte_offset,
	)
	if !current_ok || current != state.logical_view_target {
		if current_failure.code == .None {
			current_failure = editor.Failure_Context {
				code = .Stale_Revision,
				buffer_id = state.buffer_id,
				revision = state.base_revision,
				start = state.logical_view_target.byte_offset,
			}
		}
		return false, transaction_editor_failure(
			state.transaction_id,
			state.admitted_splices,
			current_failure,
		)
	}
	valid, view_failure := editor_view.logical_edit_validate(&state.logical_view)
	if !valid {
		return false, transaction_view_failure(state, view_failure)
	}
	return true, {}
}

@(private)
transaction_logical_view_abort :: proc(state: ^Transaction_State) {
	if !state.has_logical_view {
		return
	}
	aborted, abort_failure := editor_view.logical_edit_abort(&state.logical_view)
	assert(aborted && abort_failure.code == .None)
	state.has_logical_view = false
	state.logical_view_target = {}
}

@(private)
transaction_logical_view_publish_reserved :: proc(
	state: ^Transaction_State,
	result_revision: editor.Revision,
) -> editor_view.Logical_Commit_Result {
	if !state.has_logical_view {
		return {}
	}
	result := editor_view.logical_edit_publish_reserved(&state.logical_view, result_revision)
	state.has_logical_view = false
	state.logical_view_target = {}
	return result
}

@(private)
transaction_view_failure :: proc(
	state: ^Transaction_State,
	view_failure: editor_view.Failure_Context,
) -> Failure_Context {
	return Failure_Context {
		code = .View_Failure,
		transaction_id = state.transaction_id,
		buffer_id = state.buffer_id,
		base_revision = state.base_revision,
		splice_index = state.admitted_splices,
		limit = view_failure.limit,
		actual = view_failure.actual,
		editor_failure = view_failure.editor_failure,
		view_failure = view_failure,
	}
}
