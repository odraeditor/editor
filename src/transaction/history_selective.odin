// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package transaction

import "../editor"
import "../history"

/*
transaction_history_selective_undo publishes one proven compensating edit as
an ordinary tracked transaction, so the compensation is itself undoable.
*/
transaction_history_selective_undo :: proc(
	store: ^history.Store,
	buffer: ^editor.Buffer,
	request: history.Selective_Request,
	transaction_id: Transaction_ID,
	undo_unit_id: Undo_Unit_ID,
	allocators: Allocator_Set,
	origin := Origin{kind = .Built_In, descriptor = "history"},
	limits := DEFAULT_LIMITS,
) -> (result: history.Navigation_Result, ok: bool, failure: Failure_Context) {
	buffer_stats, buffer_ok, editor_failure := editor.buffer_stats(buffer)
	if !buffer_ok {
		return {}, false, transaction_editor_failure(transaction_id, 0, editor_failure)
	}
	if request.buffer_id != buffer_stats.buffer_id ||
	   request.current_revision != buffer_stats.revision {
		return {}, false, navigation_history_failure(
			transaction_id,
			buffer_stats,
			history.Failure_Context {
				code = .Stale_Revision,
				buffer_id = request.buffer_id,
				revision = request.current_revision,
			},
		)
	}
	plan, prepared, history_failure := history.selective_prepare(store, request)
	if !prepared {
		return {}, false, navigation_history_failure(transaction_id, buffer_stats, history_failure)
	}
	defer history.selective_plan_release(&plan)
	root: Transaction
	started, begin_failure := transaction_begin(
		&root,
		transaction_id,
		undo_unit_id,
		buffer,
		origin,
		"selective-undo",
		allocators,
		limits,
	)
	if !started {
		return {}, false, begin_failure
	}
	for edit in plan.edits {
		start, start_ok, start_failure := transaction_position(&root, edit.start)
		if !start_ok {
			transaction_close(&root)
			return {}, false, start_failure
		}
		end, end_ok, end_failure := transaction_position(&root, edit.end)
		if !end_ok {
			transaction_close(&root)
			return {}, false, end_failure
		}
		applied, apply_failure := transaction_splice(
			&root,
			editor.Working_Splice{start = start, end = end, replacement = edit.replacement},
		)
		if !applied {
			transaction_close(&root)
			return {}, false, apply_failure
		}
	}
	tracked, track_failure := transaction_track_history(&root, store)
	if !tracked {
		transaction_close(&root)
		return {}, false, track_failure
	}
	validated, validation_failure := transaction_validate(&root)
	if !validated {
		transaction_close(&root)
		return {}, false, validation_failure
	}
	commit_result, committed, commit_failure := transaction_commit(&root)
	if !committed {
		transaction_close(&root)
		return {}, false, commit_failure
	}
	closed, close_failure := transaction_close(&root)
	assert(closed && close_failure.code == .None)
	stats, stats_ok, stats_failure := history.store_stats(store)
	if !stats_ok {
		return {}, false, navigation_history_failure(transaction_id, buffer_stats, stats_failure)
	}
	return history.Navigation_Result {
		outcome = .Applied,
		active_node = stats.active_node,
		result_revision = commit_result.result_revision,
		policy_generation = stats.policy_generation,
	}, true, {}
}
