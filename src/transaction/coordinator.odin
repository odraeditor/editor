// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package transaction

import "../editor"
import "../history"
import editor_view "../view"
import "base:runtime"
import "core:unicode/utf8"

@(private)
NESTED_TRANSACTION_INDEX :: 0
@(private)
NESTED_COMMAND_INDEX :: 1
@(private)
NESTED_DEPTH_INDEX :: 2
@(private)
NESTED_SLOT_INDEX :: 3

@(private)
Savepoint_Frame :: struct {
	command_id:          u64,
	depth:               u64,
	working:             editor.Working_Revision_Savepoint,
	saved_normalized:    []Normalized_Splice,
	saved_has_base_batch: bool,
	saved_requires_diff: bool,
	failed:              bool,
	origin_kind:         Origin_Kind,
	origin_descriptor:   string,
	command:             string,
}

@(private)
Transaction_State :: struct {
	lifecycle:            Lifecycle,
	transaction_id:       Transaction_ID,
	undo_unit_id:         Undo_Unit_ID,
	limits:               Limits,
	allocator:            runtime.Allocator,
	temporary_allocator:  runtime.Allocator,
	buffer:               ^editor.Buffer,
	buffer_id:            editor.Buffer_ID,
	base_revision:        editor.Revision,
	working:              editor.Working_Revision,
	origin_kind:          Origin_Kind,
	origin_descriptor:    string,
	command:              string,
	normalized:           []Normalized_Splice,
	publication_splices:  []editor.Working_Publication_Splice,
	admitted_splices:     u64,
	text_bytes:           u64,
	metadata_bytes:       u64,
	checkpoints:          u64,
	operations_since_checkpoint: u64,
	has_base_batch:       bool,
	requires_diff:        bool,
	cancellation_requested: bool,
	result_revision:      editor.Revision,
	nesting_depth:        u64,
	active_savepoints:    u64,
	nested_commands:      u64,
	savepoints:           u64,
	next_nested_command_id: u64,
	savepoint_frames:     [256]Savepoint_Frame,
	logical_view:         editor_view.Prepared_Logical_Edit,
	logical_view_target:  editor.Working_Position,
	logical_view_result:  editor_view.Logical_Commit_Result,
	has_logical_view:     bool,
	observer_status:      Observer_Status,
	observer_active:      bool,
	history_store:        ^history.Store,
	history_reservation:  history.Reservation,
	history_deferred:     bool,
	history_grouping:     history.Grouping_Context,
	history_cursor:       history.Cursor_Context,
	history_mark_requires_transform: bool,
}

/* transaction_is_valid reports whether a handle still owns coordinator state. */
transaction_is_valid :: proc(transaction: ^Transaction) -> bool {
	return transaction != nil && transaction.state != nil
}

/*
transaction_begin opens one single-buffer root transaction over the confirmed revision.
It copies bounded origin and command metadata and owns all private state until close.
*/
transaction_begin :: proc(
	transaction: ^Transaction,
	transaction_id: Transaction_ID,
	undo_unit_id: Undo_Unit_ID,
	buffer: ^editor.Buffer,
	origin: Origin,
	command: string,
	allocators: Allocator_Set,
	limits := DEFAULT_LIMITS,
) -> (ok: bool, failure: Failure_Context) {
	assert(transaction != nil)
	assert(transaction.state == nil, "transaction is already initialized")
	if transaction_id == Transaction_ID(0) || undo_unit_id == Undo_Unit_ID(0) {
		return false, Failure_Context{code = .Invalid_Identity, transaction_id = transaction_id}
	}
	if !limits_are_valid(limits) {
		return false, Failure_Context{code = .Invalid_Limits, transaction_id = transaction_id}
	}
	if allocators.persistent.procedure == nil {
		return false, Failure_Context{code = .Persistent_Memory_Limit, transaction_id = transaction_id}
	}
	if allocators.temporary.procedure == nil {
		return false, Failure_Context{code = .Temporary_Memory_Limit, transaction_id = transaction_id}
	}
	if origin.kind == .Invalid || !utf8.valid_string(origin.descriptor) {
		return false, Failure_Context{code = .Invalid_Origin, transaction_id = transaction_id}
	}
	if !utf8.valid_string(command) {
		return false, Failure_Context{code = .Command_Limit, transaction_id = transaction_id}
	}
	if u64(len(origin.descriptor)) > limits.origin_bytes {
		return false, Failure_Context {
			code = .Origin_Limit,
			transaction_id = transaction_id,
			limit = limits.origin_bytes,
			actual = u64(len(origin.descriptor)),
		}
	}
	if u64(len(command)) > limits.command_bytes {
		return false, Failure_Context {
			code = .Command_Limit,
			transaction_id = transaction_id,
			limit = limits.command_bytes,
			actual = u64(len(command)),
		}
	}
	buffer_stats, buffer_ok, editor_failure := editor.buffer_stats(buffer)
	if !buffer_ok {
		return false, transaction_editor_failure(transaction_id, 0, editor_failure)
	}

	state_bytes := u64(size_of(Transaction_State))
	metadata_bytes, metadata_ok := checked_add_u64(
		state_bytes,
		u64(len(origin.descriptor) + len(command)),
	)
	if !metadata_ok || metadata_bytes > limits.metadata_bytes {
		actual := metadata_bytes
		if !metadata_ok {
			actual = max(u64)
		}
		return false, Failure_Context {
			code = .Metadata_Memory_Limit,
			transaction_id = transaction_id,
			limit = limits.metadata_bytes,
			actual = actual,
		}
	}

	state, allocation_error := new(Transaction_State, allocators.persistent)
	if allocation_error != nil {
		return false, Failure_Context {
			code = .Persistent_Memory_Limit,
			transaction_id = transaction_id,
			actual = state_bytes,
		}
	}
	state.allocator = allocators.persistent
	origin_copy, origin_error := clone_string(origin.descriptor, allocators.persistent)
	if origin_error != nil {
		free(state, allocators.persistent)
		return false, Failure_Context{code = .Persistent_Memory_Limit, transaction_id = transaction_id}
	}
	command_copy, command_error := clone_string(command, allocators.persistent)
	if command_error != nil {
		delete_string(origin_copy, allocators.persistent)
		free(state, allocators.persistent)
		return false, Failure_Context{code = .Persistent_Memory_Limit, transaction_id = transaction_id}
	}
	working, working_ok, working_failure := editor.buffer_working_revision_open(buffer)
	if !working_ok {
		delete_string(command_copy, allocators.persistent)
		delete_string(origin_copy, allocators.persistent)
		free(state, allocators.persistent)
		return false, transaction_editor_failure(transaction_id, 0, working_failure)
	}

	state.lifecycle = .Building
	state.transaction_id = transaction_id
	state.undo_unit_id = undo_unit_id
	state.limits = limits
	state.temporary_allocator = allocators.temporary
	state.buffer = buffer
	state.buffer_id = buffer_stats.buffer_id
	state.base_revision = buffer_stats.revision
	state.working = working
	state.origin_kind = origin.kind
	state.origin_descriptor = origin_copy
	state.command = command_copy
	state.metadata_bytes = metadata_bytes
	state.next_nested_command_id = 1
	transaction.state = state
	return true, {}
}

/*
transaction_apply_batch admits one ordered base-relative batch and applies it privately.
Multiple insertions at one boundary retain array order. Other equal-start ambiguity is rejected.
*/
transaction_apply_batch :: proc(
	transaction: ^Transaction,
	batch: []Base_Splice,
) -> (ok: bool, failure: Failure_Context) {
	state, state_failure := transaction_building_state(transaction)
	if state_failure.code != .None {
		return false, state_failure
	}
	if !transaction_nested_edit_allowed(state) {
		return false, transaction_failure(state, .Invalid_State)
	}
	if state.has_base_batch || state.requires_diff {
		failure = transaction_failure(state, .Invalid_State)
		return false, transaction_reject_edit(state, failure)
	}
	if !transaction_checkpoint(state, 0) {
		return false, transaction_abort_with(state, .Cancelled)
	}
	batch_count := u64(len(batch))
	total_splices, splice_ok := checked_add_u64(state.admitted_splices, batch_count)
	if !splice_ok || total_splices > state.limits.splices {
		failure = transaction_limit_failure(state, .Splice_Limit, state.limits.splices, total_splices)
		return false, transaction_reject_edit(state, failure)
	}
	validation_failure := validate_base_batch(state, batch)
	if validation_failure.code != .None {
		return false, transaction_reject_edit(state, validation_failure)
	}

	normalized, text_bytes, metadata_bytes, prepared, prepare_failure := normalize_base_batch_prepare(state, batch)
	if !prepared {
		return false, transaction_reject_edit(state, prepare_failure)
	}
	batch_applied, batch_failure := apply_base_batch_private(state, batch)
	if !batch_applied {
		normalized_splices_release(normalized, state.allocator)
		return false, transaction_reject_edit(state, batch_failure)
	}
	state.normalized = normalized
	state.text_bytes = text_bytes
	state.metadata_bytes = metadata_bytes
	state.admitted_splices = total_splices
	state.has_base_batch = true
	return true, {}
}

@(private)
apply_base_batch_private :: proc(
	state: ^Transaction_State,
	batch: []Base_Splice,
) -> (bool, Failure_Context) {
	index := len(batch)
	for index > 0 {
		index -= 1
		splice := batch[index]
		if splice.start.byte_offset == splice.end.byte_offset {
			group_start := index
			for group_start > 0 {
				previous := batch[group_start - 1]
				if previous.start.byte_offset != splice.start.byte_offset ||
				   previous.end.byte_offset != splice.end.byte_offset {
					break
				}
				group_start -= 1
			}
			group_bytes := u64(0)
			for group_index in group_start ..= index {
				if !transaction_checkpoint(state, u64(group_index)) {
					return false, transaction_failure(state, .Cancelled)
				}
				group_bytes_ok: bool
				group_bytes, group_bytes_ok = checked_add_u64(
					group_bytes,
					u64(len(batch[group_index].replacement)),
				)
				if !group_bytes_ok || group_bytes > state.limits.temporary_bytes || group_bytes > u64(max(int)) {
					failure := transaction_failure(state, .Temporary_Memory_Limit)
					failure.splice_index = u64(group_index)
					failure.limit = state.limits.temporary_bytes
					failure.actual = group_bytes
					return false, failure
				}
			}
			if group_bytes > 0 {
				group, allocation_error := make([]byte, int(group_bytes), state.temporary_allocator)
				if allocation_error != nil {
					return false, transaction_failure(state, .Temporary_Memory_Limit)
				}
				offset := 0
				for group_index in group_start ..= index {
					offset += copy(group[offset:], batch[group_index].replacement)
				}
				assert(offset == len(group))
				applied, apply_failure := apply_private_splice(
					state,
					splice.start.byte_offset,
					splice.end.byte_offset,
					string(group),
					u64(group_start),
				)
				delete(group, state.temporary_allocator)
				if !applied {
					return false, apply_failure
				}
			}
			index = group_start
			continue
		}

		if !transaction_checkpoint(state, u64(index)) {
			return false, transaction_failure(state, .Cancelled)
		}
		applied, apply_failure := apply_private_splice(
			state,
			splice.start.byte_offset,
			splice.end.byte_offset,
			splice.replacement,
			u64(index),
		)
		if !applied {
			return false, apply_failure
		}
	}
	return true, {}
}

@(private)
apply_private_splice :: proc(
	state: ^Transaction_State,
	start_offset, end_offset: editor.Byte_Offset,
	replacement: string,
	splice_index: u64,
) -> (bool, Failure_Context) {
	start, start_ok, start_failure := editor.working_revision_position(&state.working, start_offset)
	if !start_ok {
		return false, transaction_editor_failure(state.transaction_id, splice_index, start_failure)
	}
	end, end_ok, end_failure := editor.working_revision_position(&state.working, end_offset)
	if !end_ok {
		return false, transaction_editor_failure(state.transaction_id, splice_index, end_failure)
	}
	applied, apply_failure := editor.working_revision_splice(
		&state.working,
		editor.Working_Splice {
			start = start,
			end = end,
			replacement = replacement,
		},
		state.temporary_allocator,
	)
	if !applied {
		return false, transaction_editor_failure(state.transaction_id, splice_index, apply_failure)
	}
	return true, {}
}

/* transaction_position validates one position in the current private generation. */
transaction_position :: proc(
	transaction: ^Transaction,
	byte_offset: editor.Byte_Offset,
) -> (position: editor.Working_Position, ok: bool, failure: Failure_Context) {
	state, state_failure := transaction_building_state(transaction)
	if state_failure.code != .None {
		return {}, false, state_failure
	}
	position_ok: bool
	editor_failure: editor.Failure_Context
	position, position_ok, editor_failure = editor.working_revision_position(&state.working, byte_offset)
	if !position_ok {
		return {}, false, transaction_editor_failure(state.transaction_id, state.admitted_splices, editor_failure)
	}
	return position, true, {}
}

/* transaction_inspect copies private read-your-writes text into caller-owned storage. */
transaction_inspect :: proc(
	transaction: ^Transaction,
	start, end: editor.Working_Position,
	destination: []byte,
) -> (copied: u64, ok: bool, failure: Failure_Context) {
	state, state_failure := transaction_building_state(transaction)
	if state_failure.code != .None {
		return 0, false, state_failure
	}
	inspected: bool
	editor_failure: editor.Failure_Context
	copied, inspected, editor_failure = editor.working_revision_inspect(
		&state.working,
		start,
		end,
		destination,
	)
	if !inspected {
		return 0, false, transaction_editor_failure(state.transaction_id, state.admitted_splices, editor_failure)
	}
	return copied, true, {}
}

/*
transaction_splice applies one edit in current private coordinates.
Later positions must be reacquired because success advances the private generation.
*/
transaction_splice :: proc(
	transaction: ^Transaction,
	splice: editor.Working_Splice,
) -> (ok: bool, failure: Failure_Context) {
	state, state_failure := transaction_building_state(transaction)
	if state_failure.code != .None {
		return false, state_failure
	}
	if !transaction_nested_edit_allowed(state) {
		return false, transaction_failure(state, .Invalid_State)
	}
	if !transaction_checkpoint(state, state.admitted_splices) {
		return false, transaction_abort_with(state, .Cancelled)
	}
	total_splices, splice_ok := checked_add_u64(state.admitted_splices, 1)
	if !splice_ok || total_splices > state.limits.splices {
		failure = transaction_limit_failure(state, .Splice_Limit, state.limits.splices, total_splices)
		return false, transaction_reject_edit(state, failure)
	}
	start := u64(splice.start.byte_offset)
	end := u64(splice.end.byte_offset)
	if start > end {
		return false, transaction_reject_edit(state, transaction_failure(state, .Reversed_Range))
	}
	operation_bytes, bytes_ok := checked_add_u64(end - start, u64(len(splice.replacement)))
	text_bytes, text_ok := checked_add_u64(state.text_bytes, operation_bytes)
	if !bytes_ok || !text_ok || text_bytes > state.limits.text_bytes {
		actual := text_bytes
		if !bytes_ok || !text_ok {
			actual = max(u64)
		}
		failure = transaction_limit_failure(state, .Text_Limit, state.limits.text_bytes, actual)
		return false, transaction_reject_edit(state, failure)
	}
	applied, editor_failure := editor.working_revision_splice(
		&state.working,
		splice,
		state.temporary_allocator,
	)
	if !applied {
		failure = transaction_editor_failure(state.transaction_id, state.admitted_splices, editor_failure)
		return false, transaction_reject_edit(state, failure)
	}
	state.text_bytes = text_bytes
	state.admitted_splices = total_splices
	state.requires_diff = true
	return true, {}
}

/* transaction_request_cancel marks a building or ready root for cooperative abort. */
transaction_request_cancel :: proc(transaction: ^Transaction) -> (ok: bool, failure: Failure_Context) {
	state, state_failure := transaction_live_state(transaction)
	if state_failure.code != .None {
		return false, state_failure
	}
	if state.observer_active {
		return false, transaction_failure(state, .Reentrant_Mutation)
	}
	if state.lifecycle != .Building && state.lifecycle != .Ready {
		return false, transaction_failure(state, .Invalid_State)
	}
	state.cancellation_requested = true
	return true, {}
}

/*
transaction_track_history attaches one Odin-owned store before validation.
The store must describe this transaction's exact buffer and base revision.
*/
transaction_track_history :: proc(
	transaction: ^Transaction,
	store: ^history.Store,
	grouping := history.Grouping_Context{},
) -> (ok: bool, failure: Failure_Context) {
	state, state_failure := transaction_building_state(transaction)
	if state_failure.code != .None {
		return false, state_failure
	}
	if store == nil || !history.store_is_valid(store) || state.history_store != nil {
		return false, transaction_failure(state, .Invalid_State)
	}
	store_stats, stats_ok, history_failure := history.store_stats(store)
	if !stats_ok {
		return false, transaction_history_failure(state, history_failure)
	}
	if store_stats.buffer_id != state.buffer_id {
		history_failure.code = .Wrong_Buffer
		history_failure.buffer_id = state.buffer_id
		return false, transaction_history_failure(state, history_failure)
	}
	if store_stats.current_revision != state.base_revision {
		history_failure.code = .Stale_Revision
		history_failure.revision = store_stats.current_revision
		history_failure.actual = u64(state.base_revision)
		return false, transaction_history_failure(state, history_failure)
	}
	state.history_store = store
	state.history_grouping = grouping
	return true, {}
}

/*
transaction_validate freezes editing, normalizes the transition, verifies reconstruction,
and reserves the allocation-free publication input before entering Ready.
*/
transaction_validate :: proc(transaction: ^Transaction) -> (ok: bool, failure: Failure_Context) {
	state, state_failure := transaction_building_state(transaction)
	if state_failure.code != .None {
		return false, state_failure
	}
	if state.active_savepoints != 0 || state.nesting_depth != 0 {
		return false, transaction_failure(state, .Invalid_State)
	}
	state.lifecycle = .Validating
	if !transaction_checkpoint(state, state.admitted_splices) {
		return false, transaction_abort_with(state, .Cancelled)
	}
	view_valid, view_failure := transaction_logical_view_validate(state)
	if !view_valid {
		transaction_abort_state(state)
		return false, view_failure
	}
	if state.requires_diff {
		normalized, text_bytes, metadata_bytes, normalized_ok, normalize_failure := normalize_sequential_transition(state)
		if !normalized_ok {
			transaction_abort_state(state)
			return false, normalize_failure
		}
		normalized_splices_release(state.normalized, state.allocator)
		state.normalized = normalized
		state.text_bytes = max(state.text_bytes, text_bytes)
		state.metadata_bytes = metadata_bytes
	}
	transaction_history_cursor_finalize(state)
	if !normalized_reconstructs_working(state) {
		transaction_abort_state(state)
		return false, transaction_failure(state, .Changeset_Mismatch)
	}
	publication_bytes, publication_ok := checked_mul_u64(
		u64(len(state.normalized)),
		u64(size_of(editor.Working_Publication_Splice)),
	)
	metadata_bytes, metadata_ok := checked_add_u64(state.metadata_bytes, publication_bytes)
	if !publication_ok || !metadata_ok || metadata_bytes > state.limits.metadata_bytes {
		actual := metadata_bytes
		if !publication_ok || !metadata_ok {
			actual = max(u64)
		}
		return false, transaction_abort_limit(
			state,
			.Metadata_Memory_Limit,
			state.limits.metadata_bytes,
			actual,
		)
	}
	publication_splices, allocation_error := make(
		[]editor.Working_Publication_Splice,
		len(state.normalized),
		state.allocator,
	)
	if allocation_error != nil {
		transaction_abort_state(state)
		return false, transaction_failure(state, .Persistent_Memory_Limit)
	}
	for splice, index in state.normalized {
		publication_splices[index] = editor.Working_Publication_Splice {
			start = splice.start,
			end = splice.end,
			inserted_bytes = u64(len(splice.replacement_text)),
		}
	}
	state.publication_splices = publication_splices
	state.metadata_bytes = metadata_bytes
	if state.history_store != nil && !state.history_deferred && len(state.normalized) > 0 {
		history_edits, history_edit_error := make(
			[]history.Edit_Payload,
			len(state.normalized),
			state.temporary_allocator,
		)
		if history_edit_error != nil {
			transaction_abort_state(state)
			return false, transaction_failure(state, .Temporary_Memory_Limit)
		}
		for splice, index in state.normalized {
			history_edits[index] = history.Edit_Payload {
				start = splice.start,
				end = splice.end,
				replacement_text = splice.replacement_text,
				removed_text = splice.removed_text,
			}
		}
		result_revision := editor.Revision(u64(state.base_revision) + 1)
		reserved, history_failure := history.record_reserve(
			state.history_store,
			&state.history_reservation,
			history.Record_Input {
				source_transaction_id = history.Source_Transaction_ID(state.transaction_id),
				source_undo_unit_id = history.Source_Undo_Unit_ID(state.undo_unit_id),
				buffer_id = state.buffer_id,
				base_revision = state.base_revision,
				result_revision = result_revision,
				edits = history_edits,
				origin = history_origin(state.origin_kind),
				origin_descriptor = state.origin_descriptor,
				command = state.command,
				cursor = state.history_cursor,
				grouping = state.history_grouping,
			},
		)
		delete(history_edits, state.temporary_allocator)
		if !reserved {
			transaction_abort_state(state)
			return false, transaction_history_failure(state, history_failure)
		}
	} else if state.history_store != nil && !state.history_deferred {
		result_revision := editor.Revision(u64(state.base_revision) + 1)
		reserved, history_failure := history.revision_reserve(
			state.history_store,
			&state.history_reservation,
			state.base_revision,
			result_revision,
		)
		if !reserved {
			transaction_abort_state(state)
			return false, transaction_history_failure(state, history_failure)
		}
	}
	state.lifecycle = .Ready
	return true, {}
}

/* transaction_commit publishes one validated root, then contains one optional observer result. */
transaction_commit :: proc(
	transaction: ^Transaction,
	observer := Commit_Observer{},
) -> (result: Commit_Result, ok: bool, failure: Failure_Context) {
	state, state_failure := transaction_live_state(transaction)
	if state_failure.code != .None {
		return {}, false, state_failure
	}
	if state.observer_active {
		return {}, false, transaction_failure(state, .Reentrant_Mutation)
	}
	if state.lifecycle != .Ready {
		return {}, false, transaction_failure(state, .Invalid_State)
	}
	if state.cancellation_requested {
		return {}, false, transaction_abort_with(state, .Cancelled)
	}
	state.lifecycle = .Publishing
	state.result_revision = editor.working_revision_publish_reserved(
		&state.working,
		state.publication_splices,
	)
	state.logical_view_result = transaction_logical_view_publish_reserved(
		state,
		state.result_revision,
	)
	if history.reservation_is_valid(&state.history_reservation) {
		history.reservation_commit_reserved(&state.history_reservation, state.result_revision)
	}
	state.lifecycle = .Committed
	if observer.procedure != nil {
		state.observer_active = true
		delivered := observer.procedure(observer.user_data, transaction_commit_event(state))
		state.observer_active = false
		state.observer_status = .Succeeded if delivered else .Failed
	}
	return transaction_commit_result(state), true, {}
}

/* transaction_result returns the immutable committed result retained until close. */
transaction_result :: proc(
	transaction: ^Transaction,
) -> (result: Commit_Result, ok: bool, failure: Failure_Context) {
	state, state_failure := transaction_live_state(transaction)
	if state_failure.code != .None {
		return {}, false, state_failure
	}
	if state.lifecycle != .Committed {
		return {}, false, transaction_failure(state, .Invalid_State)
	}
	return transaction_commit_result(state), true, {}
}

/* transaction_abort transitions an unpublished root to Aborted and releases private editor state. */
transaction_abort :: proc(transaction: ^Transaction) -> (ok: bool, failure: Failure_Context) {
	state, state_failure := transaction_live_state(transaction)
	if state_failure.code != .None {
		return false, state_failure
	}
	if state.observer_active {
		return false, transaction_failure(state, .Reentrant_Mutation)
	}
	if state.lifecycle != .Building && state.lifecycle != .Validating && state.lifecycle != .Ready {
		return false, transaction_failure(state, .Invalid_State)
	}
	transaction_abort_state(state)
	return true, {}
}

/* transaction_stats returns lifecycle and resource state without exposing private storage. */
transaction_stats :: proc(
	transaction: ^Transaction,
) -> (stats: Transaction_Stats, ok: bool, failure: Failure_Context) {
	state, state_failure := transaction_live_state(transaction)
	if state_failure.code != .None {
		return {}, false, state_failure
	}
	working_generation := u64(0)
	if editor.working_revision_is_valid(&state.working) {
		working_stats, working_ok, _ := editor.working_revision_stats(&state.working)
		if working_ok {
			working_generation = working_stats.generation
		}
	}
	return Transaction_Stats {
		transaction_id = state.transaction_id,
		undo_unit_id = state.undo_unit_id,
		lifecycle = state.lifecycle,
		buffer_id = state.buffer_id,
		base_revision = state.base_revision,
		working_generation = working_generation,
		nesting_depth = state.nesting_depth,
		active_savepoints = state.active_savepoints,
		usage = transaction_usage(state),
	}, true, {}
}

/*
transaction_close releases coordinator storage and auto-aborts an unpublished root.
All result and metadata views returned by this transaction expire when close returns.
*/
transaction_close :: proc(transaction: ^Transaction) -> (ok: bool, failure: Failure_Context) {
	state, state_failure := transaction_live_state(transaction)
	if state_failure.code != .None {
		return false, state_failure
	}
	if state.observer_active {
		return false, transaction_failure(state, .Reentrant_Mutation)
	}
	if editor.working_revision_is_valid(&state.working) {
		transaction_abort_state(state)
	} else if state.active_savepoints != 0 {
		transaction_nested_frames_release(state)
	}
	transaction.state = nil
	transaction_id := state.transaction_id
	transaction_state_release(state)
	return true, Failure_Context{transaction_id = transaction_id}
}

@(private)
transaction_commit_result :: proc(state: ^Transaction_State) -> Commit_Result {
	return Commit_Result {
		event = transaction_commit_event(state),
		observer_status = state.observer_status,
	}
}

@(private)
transaction_commit_event :: proc(state: ^Transaction_State) -> Commit_Event {
	return Commit_Event {
		transaction_id = state.transaction_id,
		undo_unit_id = state.undo_unit_id,
		origin = Origin{kind = state.origin_kind, descriptor = state.origin_descriptor},
		command = state.command,
		buffer_id = state.buffer_id,
		base_revision = state.base_revision,
		result_revision = state.result_revision,
		splices = state.normalized,
		usage = transaction_usage(state),
		logical_view = state.logical_view_result,
	}
}

@(private)
transaction_usage :: proc(state: ^Transaction_State) -> Resource_Usage {
	return Resource_Usage {
		buffer_participants = 1,
		admitted_splices = state.admitted_splices,
		text_bytes = state.text_bytes,
		metadata_bytes = state.metadata_bytes,
		checkpoints = state.checkpoints,
		nested_commands = state.nested_commands,
		savepoints = state.savepoints,
		logical_views = 1 if state.has_logical_view || state.logical_view_result.present else 0,
	}
}

@(private)
transaction_checkpoint :: proc(state: ^Transaction_State, splice_index: u64) -> bool {
	_ = splice_index
	state.operations_since_checkpoint += 1
	if state.operations_since_checkpoint >= state.limits.checkpoint_operations || state.cancellation_requested {
		state.operations_since_checkpoint = 0
		state.checkpoints += 1
	}
	return !state.cancellation_requested
}

@(private)
transaction_abort_state :: proc(state: ^Transaction_State) {
	if history.reservation_is_valid(&state.history_reservation) {
		aborted, history_failure := history.reservation_abort(&state.history_reservation)
		assert(aborted && history_failure.code == .None)
	}
	if editor.working_revision_is_valid(&state.working) {
		aborted, abort_failure := editor.working_revision_abort(&state.working)
		assert(aborted && abort_failure.code == .None)
	}
	transaction_logical_view_abort(state)
	transaction_nested_frames_release(state)
	state.lifecycle = .Aborted
}

@(private)
history_origin :: proc(origin: Origin_Kind) -> history.Record_Origin {
	switch origin {
	case .Built_In:
		return .Built_In
	case .Racket:
		return .Racket
	case .Language_Tool:
		return .Language_Tool
	case .External_Proposal:
		return .External_Proposal
	case .Invalid:
		return .Invalid
	}
	return .Invalid
}

@(private)
transaction_history_failure :: proc(state: ^Transaction_State, history_failure: history.Failure_Context) -> Failure_Context {
	return Failure_Context {
		code = .History_Failure,
		transaction_id = state.transaction_id,
		buffer_id = state.buffer_id,
		base_revision = state.base_revision,
		limit = history_failure.maximum,
		actual = history_failure.actual,
		history_failure = history_failure,
	}
}

@(private)
transaction_abort_with :: proc(state: ^Transaction_State, code: Failure_Code) -> Failure_Context {
	transaction_abort_state(state)
	return transaction_failure(state, code)
}

@(private)
transaction_abort_limit :: proc(
	state: ^Transaction_State,
	code: Failure_Code,
	limit, actual: u64,
) -> Failure_Context {
	transaction_abort_state(state)
	failure := transaction_failure(state, code)
	failure.limit = limit
	failure.actual = actual
	return failure
}

@(private)
transaction_reject_edit :: proc(
	state: ^Transaction_State,
	failure: Failure_Context,
) -> Failure_Context {
	if state.nesting_depth > 0 && state.active_savepoints > 0 {
		state.savepoint_frames[int(state.active_savepoints - 1)].failed = true
		return failure
	}
	transaction_abort_state(state)
	return failure
}

@(private)
transaction_live_state :: proc(transaction: ^Transaction) -> (^Transaction_State, Failure_Context) {
	if !transaction_is_valid(transaction) {
		return nil, Failure_Context{code = .Invalid_State}
	}
	state := (^Transaction_State)(transaction.state)
	if state.lifecycle == .Closed || state.lifecycle == .Invalid {
		return nil, Failure_Context{code = .Invalid_State, transaction_id = state.transaction_id}
	}
	return state, {}
}

@(private)
transaction_building_state :: proc(transaction: ^Transaction) -> (^Transaction_State, Failure_Context) {
	state, failure := transaction_live_state(transaction)
	if failure.code != .None {
		return nil, failure
	}
	if state.observer_active {
		return nil, transaction_failure(state, .Reentrant_Mutation)
	}
	if state.lifecycle != .Building {
		return nil, transaction_failure(state, .Invalid_State)
	}
	return state, {}
}

@(private)
transaction_failure :: proc(state: ^Transaction_State, code: Failure_Code) -> Failure_Context {
	return Failure_Context {
		code = code,
		transaction_id = state.transaction_id,
		buffer_id = state.buffer_id,
		base_revision = state.base_revision,
		splice_index = state.admitted_splices,
	}
}
