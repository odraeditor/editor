// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package completion

import "../editor"
import "../history"
import "../transaction"
import editor_view "../view"

/* Acceptance_Target supplies checked editor authority for one candidate commit. */
Acceptance_Target :: struct {
	buffer:                 ^editor.Buffer,
	view_registry:          ^editor_view.Registry,
	view:                   editor_view.View_Handle,
	history_store:          ^history.Store,
	transaction_id:         transaction.Transaction_ID,
	undo_unit_id:           transaction.Undo_Unit_ID,
	allocators:             transaction.Allocator_Set,
	transaction_limits:     transaction.Limits,
	commit_observer:        transaction.Commit_Observer,
	desired_display_column: u32,
	writable:               bool,
}

/* Acceptance_Result copies the durable outcome before transaction storage is released. */
Acceptance_Result :: struct {
	candidate_id:    Candidate_ID,
	transaction_id: transaction.Transaction_ID,
	undo_unit_id:   transaction.Undo_Unit_ID,
	base_revision:  Document_Revision,
	result_revision: Document_Revision,
	edit_count:      u8,
	point_byte:      u64,
}

/* Acceptance_Failure preserves both completion and transaction rejection context. */
Acceptance_Failure :: struct {
	completion: Failure,
	transaction: transaction.Failure_Context,
}

@(private = "file")
Acceptance_Edit :: struct {
	range:   Byte_Range,
	text:    string,
	primary: bool,
	order:   u8,
}

/* controller_acceptance_scope copies authority for the currently selected item. */
controller_acceptance_scope :: proc(
	controller: ^Controller,
) -> (Acceptance_Scope, bool, Failure) {
	state := controller_state(controller)
	if state == nil {
		return {}, false, failure(.Accept, .Invalid_Controller)
	}
	candidate := controller_selected_candidate(state)
	if candidate == nil {
		return {}, false, controller_reject(state, failure(.Accept, .Invalid_Candidate))
	}
	return acceptance_scope(state, candidate.id), true, {}
}

/* controller_accept_candidate atomically publishes one exact selected candidate. */
controller_accept_candidate :: proc(
	controller: ^Controller,
	expected: Acceptance_Scope,
	target: Acceptance_Target,
) -> (Acceptance_Result, bool, Acceptance_Failure) {
	state := controller_state(controller)
	if state == nil {
		return {}, false, {completion = failure(.Accept, .Invalid_Controller)}
	}
	candidate := controller_selected_candidate(state)
	if candidate == nil {
		return {}, false, acceptance_reject(controller, state, .Invalid_Candidate)
	}
	if expected != acceptance_scope(state, candidate.id) {
		return {}, false, acceptance_reject(controller, state, .Stale_Scope)
	}
	if candidate.availability == .Unavailable {
		return {}, false, acceptance_reject(controller, state, .Invalid_Candidate)
	}
	if !target.writable {
		return {}, false, acceptance_reject(controller, state, .Write_Forbidden)
	}
	if target.buffer == nil || target.view_registry == nil || target.history_store == nil ||
	   target.transaction_id == transaction.Transaction_ID(0) ||
	   target.undo_unit_id == transaction.Undo_Unit_ID(0) {
		return {}, false, acceptance_reject(controller, state, .Invalid_State)
	}

	buffer_stats, buffer_ok, _ := editor.buffer_stats(target.buffer)
	view_state, view_ok, _ := editor_view.snapshot(target.view_registry, target.view)
	if !buffer_ok || !view_ok ||
	   Buffer_ID(buffer_stats.buffer_id) != expected.request_scope.buffer_id ||
	   Document_Revision(buffer_stats.revision) != expected.request_scope.document_revision ||
	   View_ID(view_state.view_id) != expected.request_scope.view_id ||
	   View_Generation(view_state.view_generation) != expected.request_scope.view_generation ||
	   Buffer_ID(view_state.buffer_id) != expected.request_scope.buffer_id ||
	   Document_Revision(view_state.revision) != expected.request_scope.document_revision {
		return {}, false, acceptance_reject(controller, state, .Stale_Document)
	}

	edits: [MAX_COMPLETION_ADDITIONAL_EDITS + 1]Acceptance_Edit
	edit_count := int(candidate.additional_edit_count) + 1
	primary_range := state.request.query_range
	primary_text := text_view(&candidate.insertion_text)
	if candidate.has_primary_edit {
		primary_range = candidate.primary_edit.range
		primary_text = text_view(&candidate.primary_edit.new_text)
	}
	edits[0] = {range = primary_range, text = primary_text, primary = true}
	for index in 0 ..< int(candidate.additional_edit_count) {
		edits[index + 1] = {
			range = candidate.additional_edits[index].range,
			text = text_view(&candidate.additional_edits[index].new_text),
			order = u8(index + 1),
		}
	}
	acceptance_sort_edits(edits[:edit_count])

	splices: [MAX_COMPLETION_ADDITIONAL_EDITS + 1]transaction.Base_Splice
	point_byte: u64
	delta: i64
	for edit, index in edits[:edit_count] {
		if !range_is_valid(edit.range) || edit.range.end > buffer_stats.text_bytes {
			return {}, false, acceptance_reject(controller, state, .Invalid_Range)
		}
		start, start_ok, _ := editor.buffer_position(target.buffer, editor.Byte_Offset(edit.range.start))
		end, end_ok, _ := editor.buffer_position(target.buffer, editor.Byte_Offset(edit.range.end))
		if !start_ok || !end_ok {
			return {}, false, acceptance_reject(controller, state, .Invalid_Range)
		}
		splices[index] = {start = start, end = end, replacement = edit.text}
		if edit.primary {
			adjusted := i64(edit.range.start) + delta + i64(len(edit.text))
			if adjusted < 0 {
				return {}, false, acceptance_reject(controller, state, .Invalid_Range)
			}
			point_byte = u64(adjusted)
		}
		delta += i64(len(edit.text)) - i64(edit.range.end - edit.range.start)
	}

	root: transaction.Transaction
	started, transaction_failure := transaction.transaction_begin(
		&root,
		target.transaction_id,
		target.undo_unit_id,
		target.buffer,
		transaction.Origin{kind = .Language_Tool, descriptor = "language-completion"},
		"completion-accept",
		target.allocators,
		target.transaction_limits,
	)
	if !started {
		return {}, false, acceptance_transaction_reject(controller, state, transaction_failure)
	}
	defer transaction.transaction_close(&root)

	applied: bool
	applied, transaction_failure = transaction.transaction_apply_batch(&root, splices[:edit_count])
	if !applied {
		return {}, false, acceptance_transaction_reject(controller, state, transaction_failure)
	}
	tracked: bool
	tracked, transaction_failure = transaction.transaction_track_history(&root, target.history_store)
	if !tracked {
		return {}, false, acceptance_transaction_reject(controller, state, transaction_failure)
	}
	point: editor.Working_Position
	point_ok: bool
	point, point_ok, transaction_failure = transaction.transaction_position(
		&root,
		editor.Byte_Offset(point_byte),
	)
	if !point_ok {
		return {}, false, acceptance_transaction_reject(controller, state, transaction_failure)
	}
	view_prepared: bool
	view_prepared, transaction_failure = transaction.transaction_prepare_logical_view(
		&root,
		target.view_registry,
		target.view,
		point,
		target.desired_display_column,
		.Deactivate,
		.Absent,
	)
	if !view_prepared {
		return {}, false, acceptance_transaction_reject(controller, state, transaction_failure)
	}
	validated: bool
	validated, transaction_failure = transaction.transaction_validate(&root)
	if !validated {
		return {}, false, acceptance_transaction_reject(controller, state, transaction_failure)
	}
	commit: transaction.Commit_Result
	committed: bool
	commit, committed, transaction_failure = transaction.transaction_commit(
		&root,
		target.commit_observer,
	)
	if !committed {
		return {}, false, acceptance_transaction_reject(controller, state, transaction_failure)
	}

	result := Acceptance_Result {
		candidate_id = candidate.id,
		transaction_id = commit.transaction_id,
		undo_unit_id = commit.undo_unit_id,
		base_revision = Document_Revision(commit.base_revision),
		result_revision = Document_Revision(commit.result_revision),
		edit_count = u8(edit_count),
		point_byte = point_byte,
	}
	controller_cancel_request(state)
	controller_release_batch(state)
	state.selected_candidate = 0
	state.session_state = .Retired
	state.current_revision = result.result_revision
	return result, true, {}
}

@(private = "file")
acceptance_scope :: proc(state: ^Controller_State, candidate_id: Candidate_ID) -> Acceptance_Scope {
	return {
		controller_id = state.controller_id,
		controller_generation = state.controller_generation,
		session_id = state.session_id,
		session_generation = state.session_generation,
		request_id = state.request.id,
		request_generation = state.request.generation,
		request_scope = state.request.scope,
		batch_id = state.batch.id,
		batch_generation = state.batch.generation,
		projection_generation = state.projection.generation,
		candidate_id = candidate_id,
	}
}

@(private = "file")
acceptance_sort_edits :: proc(edits: []Acceptance_Edit) {
	for index in 1 ..< len(edits) {
		current := edits[index]
		position := index
		for position > 0 && acceptance_edit_less(current, edits[position - 1]) {
			edits[position] = edits[position - 1]
			position -= 1
		}
		edits[position] = current
	}
}

@(private = "file")
acceptance_edit_less :: proc(left, right: Acceptance_Edit) -> bool {
	if left.range.start != right.range.start do return left.range.start < right.range.start
	if left.range.end != right.range.end do return left.range.end < right.range.end
	return left.order < right.order
}

@(private = "file")
acceptance_reject :: proc(
	controller: ^Controller,
	state: ^Controller_State,
	code: Failure_Code,
) -> Acceptance_Failure {
	rejected := failure(.Accept, code)
	_, _ = controller_dismiss(controller)
	return {completion = controller_reject(state, rejected)}
}

@(private = "file")
acceptance_transaction_reject :: proc(
	controller: ^Controller,
	state: ^Controller_State,
	transaction_failure: transaction.Failure_Context,
) -> Acceptance_Failure {
	result := acceptance_reject(controller, state, .Transaction_Rejected)
	result.transaction = transaction_failure
	return result
}
