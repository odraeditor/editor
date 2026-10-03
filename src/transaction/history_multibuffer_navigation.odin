// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package transaction

import "../editor"
import "../history"

/*
transaction_multibuffer_history_navigate publishes one complete linked traversal.
Every history participant is prepared before the existing no-fail publication boundary.
*/
transaction_multibuffer_history_navigate :: proc(
	stores: []^history.Store,
	buffers: []^editor.Buffer,
	kind: history.Navigation_Kind,
	target_link_id: history.Link_ID,
	transaction_id: Transaction_ID,
	undo_unit_id: Undo_Unit_ID,
	allocators: Allocator_Set,
	limits := DEFAULT_LIMITS,
) -> (link_id: history.Link_ID, ok: bool, failure: Failure_Context) {
	plan, prepared, history_failure := history.multibuffer_navigation_prepare(
		stores,
		history.Multibuffer_Navigation_Request {
			kind = kind,
			target_link_id = target_link_id,
		},
	)
	if !prepared {
		return 0, false, Failure_Context {
			code = .History_Failure,
			transaction_id = transaction_id,
			buffer_id = history_failure.buffer_id,
			limit = history_failure.maximum,
			actual = history_failure.actual,
			history_failure = history_failure,
		}
	}
	command := "undo"
	if kind == .Redo {
		command = "redo"
	} else if kind == .Select_Branch {
		command = "select-history-branch"
	}
	root: Multibuffer_Transaction
	started, begin_failure := multibuffer_begin(
		&root,
		transaction_id,
		undo_unit_id,
		buffers,
		Origin{kind = .Built_In, descriptor = "history"},
		command,
		allocators,
		limits,
	)
	if !started {
		history.multibuffer_navigation_abort(&plan)
		return 0, false, begin_failure
	}
	for participant in plan.buffers {
		for edit in participant.edits {
			start, start_ok, start_failure := multibuffer_position(&root, participant.buffer_id, edit.start)
			if !start_ok {
				history.multibuffer_navigation_abort(&plan)
				multibuffer_close(&root)
				return 0, false, start_failure
			}
			end, end_ok, end_failure := multibuffer_position(&root, participant.buffer_id, edit.end)
			if !end_ok {
				history.multibuffer_navigation_abort(&plan)
				multibuffer_close(&root)
				return 0, false, end_failure
			}
			applied, apply_failure := multibuffer_splice(
				&root,
				participant.buffer_id,
				editor.Working_Splice{start = start, end = end, replacement = edit.replacement},
			)
			if !applied {
				history.multibuffer_navigation_abort(&plan)
				multibuffer_close(&root)
				return 0, false, apply_failure
			}
		}
	}
	validated, validation_failure := multibuffer_validate(&root)
	if !validated {
		history.multibuffer_navigation_abort(&plan)
		multibuffer_close(&root)
		return 0, false, validation_failure
	}
	_, committed, commit_failure := multibuffer_commit(&root)
	if !committed {
		history.multibuffer_navigation_abort(&plan)
		multibuffer_close(&root)
		return 0, false, commit_failure
	}
	link_id = plan.link_id
	history.multibuffer_navigation_commit_reserved(&plan)
	closed, close_failure := multibuffer_close(&root)
	assert(closed && close_failure.code == .None)
	return link_id, true, {}
}

/*
transaction_multibuffer_history_selective_undo publishes one proven linked compensation.
The compensation is recorded as a new complete linked unit and is itself reversible.
*/
transaction_multibuffer_history_selective_undo :: proc(
	stores: []^history.Store,
	buffers: []^editor.Buffer,
	target_link_id: history.Link_ID,
	analysis_operations: u64,
	transaction_id: Transaction_ID,
	undo_unit_id: Undo_Unit_ID,
	allocators: Allocator_Set,
	limits := DEFAULT_LIMITS,
) -> (link_id: history.Link_ID, ok: bool, failure: Failure_Context) {
	plan, prepared, history_failure := history.multibuffer_selective_prepare(
		stores,
		history.Multibuffer_Selective_Request {
			target_link_id = target_link_id,
			analysis_operations = analysis_operations,
		},
	)
	if !prepared {
		return 0, false, Failure_Context {
			code = .History_Failure,
			transaction_id = transaction_id,
			buffer_id = history_failure.buffer_id,
			limit = history_failure.maximum,
			actual = history_failure.actual,
			history_failure = history_failure,
		}
	}
	defer history.multibuffer_selective_plan_release(&plan)
	root: Multibuffer_Transaction
	started, begin_failure := multibuffer_begin(
		&root,
		transaction_id,
		undo_unit_id,
		buffers,
		Origin{kind = .Built_In, descriptor = "history"},
		"selective-undo",
		allocators,
		limits,
	)
	if !started {
		return 0, false, begin_failure
	}
	for participant in plan.buffers {
		for edit in participant.edits {
			start, start_ok, start_failure := multibuffer_position(&root, participant.buffer_id, edit.start)
			if !start_ok {
				multibuffer_close(&root)
				return 0, false, start_failure
			}
			end, end_ok, end_failure := multibuffer_position(&root, participant.buffer_id, edit.end)
			if !end_ok {
				multibuffer_close(&root)
				return 0, false, end_failure
			}
			applied, apply_failure := multibuffer_splice(
				&root,
				participant.buffer_id,
				editor.Working_Splice{start = start, end = end, replacement = edit.replacement},
			)
			if !applied {
				multibuffer_close(&root)
				return 0, false, apply_failure
			}
		}
	}
	tracked, track_failure := multibuffer_track_history(&root, stores)
	if !tracked {
		multibuffer_close(&root)
		return 0, false, track_failure
	}
	validated, validation_failure := multibuffer_validate(&root)
	if !validated {
		multibuffer_close(&root)
		return 0, false, validation_failure
	}
	_, committed, commit_failure := multibuffer_commit(&root)
	if !committed {
		multibuffer_close(&root)
		return 0, false, commit_failure
	}
	closed, close_failure := multibuffer_close(&root)
	assert(closed && close_failure.code == .None)
	return history.Link_ID(undo_unit_id), true, {}
}
