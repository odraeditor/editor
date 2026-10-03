// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package transaction

import "../editor"
import "../history"
import "base:runtime"
import "core:slice"

@(private)
Multibuffer_Participant :: struct {
	buffer_id:   editor.Buffer_ID,
	transaction: Transaction,
}

@(private)
Multibuffer_Seed :: struct {
	buffer_id: editor.Buffer_ID,
	buffer:    ^editor.Buffer,
}

@(private)
Multibuffer_History_Seed :: struct {
	buffer_id: editor.Buffer_ID,
	store:     ^history.Store,
}

@(private)
Multibuffer_State :: struct {
	lifecycle:       Lifecycle,
	transaction_id:  Transaction_ID,
	undo_unit_id:    Undo_Unit_ID,
	limits:          Limits,
	allocator:       runtime.Allocator,
	temporary_allocator: runtime.Allocator,
	participants:    []Multibuffer_Participant,
	results:         []Buffer_Commit_Result,
	usage:           Resource_Usage,
	cancel_requested: bool,
	observer_active: bool,
	observer_status: Observer_Status,
	history_reservation: history.Multibuffer_Reservation,
}

/* multibuffer_transaction_is_valid reports whether a handle still owns root state. */
multibuffer_transaction_is_valid :: proc(transaction: ^Multibuffer_Transaction) -> bool {
	return transaction != nil && transaction.state != nil
}

/*
multibuffer_begin opens private revisions for one complete non-empty buffer set.
The root orders participants by buffer identity before any edit is admitted.
*/
multibuffer_begin :: proc(
	transaction: ^Multibuffer_Transaction,
	transaction_id: Transaction_ID,
	undo_unit_id: Undo_Unit_ID,
	buffers: []^editor.Buffer,
	origin: Origin,
	command: string,
	allocators: Allocator_Set,
	limits := DEFAULT_LIMITS,
) -> (ok: bool, failure: Failure_Context) {
	assert(transaction != nil)
	assert(transaction.state == nil, "multibuffer transaction is already initialized")
	if len(buffers) == 0 || u64(len(buffers)) > limits.buffer_participants {
		return false, Failure_Context {
			code = .Participant_Limit,
			transaction_id = transaction_id,
			limit = limits.buffer_participants,
			actual = u64(len(buffers)),
		}
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

	seeds, seed_error := make([]Multibuffer_Seed, len(buffers), allocators.temporary)
	if seed_error != nil {
		return false, Failure_Context{code = .Temporary_Memory_Limit, transaction_id = transaction_id}
	}
	defer delete(seeds, allocators.temporary)
	for buffer, index in buffers {
		stats, stats_ok, editor_failure := editor.buffer_stats(buffer)
		if !stats_ok {
			return false, transaction_editor_failure(transaction_id, 0, editor_failure)
		}
		seeds[index] = Multibuffer_Seed{buffer_id = stats.buffer_id, buffer = buffer}
	}
	slice.sort_by(seeds, multibuffer_seed_less)
	for index in 1 ..< len(seeds) {
		if seeds[index - 1].buffer_id == seeds[index].buffer_id {
			return false, Failure_Context {
				code = .Invalid_Identity,
				transaction_id = transaction_id,
				buffer_id = seeds[index].buffer_id,
			}
		}
	}

	state_bytes := u64(size_of(Multibuffer_State))
	participant_bytes, participant_bytes_ok := checked_mul_u64(
		u64(len(seeds)),
		u64(size_of(Multibuffer_Participant)),
	)
	result_bytes, result_bytes_ok := checked_mul_u64(
		u64(len(seeds)),
		u64(size_of(Buffer_Commit_Result)),
	)
	metadata_bytes, metadata_ok := checked_add_u64(state_bytes, participant_bytes)
	metadata_bytes, metadata_ok = checked_add_u64(metadata_bytes, result_bytes)
	if !participant_bytes_ok || !result_bytes_ok || !metadata_ok ||
	   metadata_bytes > limits.metadata_bytes {
		actual := metadata_bytes
		if !participant_bytes_ok || !result_bytes_ok || !metadata_ok {
			actual = max(u64)
		}
		return false, Failure_Context {
			code = .Metadata_Memory_Limit,
			transaction_id = transaction_id,
			limit = limits.metadata_bytes,
			actual = actual,
		}
	}

	state, state_error := new(Multibuffer_State, allocators.persistent)
	if state_error != nil {
		return false, Failure_Context{code = .Persistent_Memory_Limit, transaction_id = transaction_id}
	}
	state.allocator = allocators.persistent
	state.temporary_allocator = allocators.temporary
	participants, participant_error := make(
		[]Multibuffer_Participant,
		len(seeds),
		allocators.persistent,
	)
	if participant_error != nil {
		free(state, allocators.persistent)
		return false, Failure_Context{code = .Persistent_Memory_Limit, transaction_id = transaction_id}
	}
	results, result_error := make([]Buffer_Commit_Result, len(seeds), allocators.persistent)
	if result_error != nil {
		delete(participants, allocators.persistent)
		free(state, allocators.persistent)
		return false, Failure_Context{code = .Persistent_Memory_Limit, transaction_id = transaction_id}
	}
	state.lifecycle = .Building
	state.transaction_id = transaction_id
	state.undo_unit_id = undo_unit_id
	state.limits = limits
	state.participants = participants
	state.results = results
	state.usage.buffer_participants = u64(len(seeds))
	state.usage.metadata_bytes = metadata_bytes

	for seed, index in seeds {
		participant := &state.participants[index]
		participant.buffer_id = seed.buffer_id
		started, begin_failure := transaction_begin(
			&participant.transaction,
			transaction_id,
			undo_unit_id,
			seed.buffer,
			origin,
			command,
			allocators,
			limits,
		)
		if !started {
			multibuffer_release(state)
			return false, begin_failure
		}
		participant_state := (^Transaction_State)(participant.transaction.state)
		participant_usage := transaction_usage(participant_state)
		metadata_total, metadata_total_ok := checked_add_u64(
			state.usage.metadata_bytes,
			participant_usage.metadata_bytes,
		)
		if !metadata_total_ok || metadata_total > limits.metadata_bytes {
			failure = multibuffer_failure(state, .Metadata_Memory_Limit)
			failure.limit = limits.metadata_bytes
			failure.actual = metadata_total
			multibuffer_release(state)
			return false, failure
		}
		state.usage.metadata_bytes = metadata_total
	}
	transaction.state = state
	return true, {}
}

/*
multibuffer_track_history attaches the exact complete store set before validation.
The stores are matched by buffer identity; their caller order is not significant.
*/
multibuffer_track_history :: proc(
	transaction: ^Multibuffer_Transaction,
	stores: []^history.Store,
) -> (ok: bool, failure: Failure_Context) {
	state, state_failure := multibuffer_building_state(transaction)
	if state_failure.code != .None {
		return false, state_failure
	}
	if len(stores) != len(state.participants) {
		return false, multibuffer_failure(state, .Incomplete_Participant_Set)
	}
	seeds, seed_error := make([]Multibuffer_History_Seed, len(stores), state.temporary_allocator)
	if seed_error != nil {
		return false, multibuffer_failure(state, .Temporary_Memory_Limit)
	}
	defer delete(seeds, state.temporary_allocator)
	for store, index in stores {
		stats, stats_ok, history_failure := history.store_stats(store)
		if !stats_ok {
			return false, multibuffer_history_failure(state, history_failure)
		}
		seeds[index] = Multibuffer_History_Seed{buffer_id = stats.buffer_id, store = store}
	}
	slice.sort_by(seeds, multibuffer_history_seed_less)
	for &participant, index in state.participants {
		if seeds[index].buffer_id != participant.buffer_id ||
		   index > 0 && seeds[index - 1].buffer_id == seeds[index].buffer_id {
			return false, multibuffer_failure_for_buffer(state, .Incomplete_Participant_Set, participant.buffer_id)
		}
	}
	for &participant, index in state.participants {
		participant_state := (^Transaction_State)(participant.transaction.state)
		tracked, track_failure := transaction_track_history(&participant.transaction, seeds[index].store)
		if !tracked {
			for &rollback in state.participants {
				rollback_state := (^Transaction_State)(rollback.transaction.state)
				rollback_state.history_store = nil
				rollback_state.history_deferred = false
			}
			return false, track_failure
		}
		participant_state.history_deferred = true
	}
	return true, {}
}

/* multibuffer_apply_batch applies one base-relative batch to its declared participant. */
multibuffer_apply_batch :: proc(
	transaction: ^Multibuffer_Transaction,
	buffer_id: editor.Buffer_ID,
	batch: []Base_Splice,
) -> (ok: bool, failure: Failure_Context) {
	state, state_failure := multibuffer_building_state(transaction)
	if state_failure.code != .None {
		return false, state_failure
	}
	participant := multibuffer_find_participant(state, buffer_id)
	if participant == nil {
		return false, multibuffer_abort_failure(state, .Wrong_Buffer, buffer_id)
	}
	total_splices, total_ok := checked_add_u64(state.usage.admitted_splices, u64(len(batch)))
	if !total_ok || total_splices > state.limits.splices {
		failure = multibuffer_failure(state, .Splice_Limit)
		failure.buffer_id = buffer_id
		failure.limit = state.limits.splices
		failure.actual = total_splices
		multibuffer_abort_state(state)
		return false, failure
	}
	applied, apply_failure := transaction_apply_batch(&participant.transaction, batch)
	if !applied {
		multibuffer_abort_state(state)
		return false, apply_failure
	}
	usage, usage_ok := multibuffer_collect_usage(state)
	if !usage_ok || usage.text_bytes > state.limits.text_bytes ||
	   usage.metadata_bytes > state.limits.metadata_bytes {
		code := Failure_Code.Text_Limit
		limit := state.limits.text_bytes
		actual := usage.text_bytes
		if !usage_ok || usage.metadata_bytes > state.limits.metadata_bytes {
			code = .Metadata_Memory_Limit
			limit = state.limits.metadata_bytes
			actual = usage.metadata_bytes
		}
		failure = multibuffer_failure(state, code)
		failure.buffer_id = buffer_id
		failure.limit = limit
		failure.actual = actual
		multibuffer_abort_state(state)
		return false, failure
	}
	state.usage = usage
	return true, {}
}

/* multibuffer_position validates a private position for one declared buffer. */
multibuffer_position :: proc(
	transaction: ^Multibuffer_Transaction,
	buffer_id: editor.Buffer_ID,
	byte_offset: editor.Byte_Offset,
) -> (position: editor.Working_Position, ok: bool, failure: Failure_Context) {
	state, state_failure := multibuffer_building_state(transaction)
	if state_failure.code != .None {
		return {}, false, state_failure
	}
	participant := multibuffer_find_participant(state, buffer_id)
	if participant == nil {
		return {}, false, multibuffer_failure_for_buffer(state, .Wrong_Buffer, buffer_id)
	}
	return transaction_position(&participant.transaction, byte_offset)
}

/* multibuffer_splice applies one sequential private edit to a declared buffer. */
multibuffer_splice :: proc(
	transaction: ^Multibuffer_Transaction,
	buffer_id: editor.Buffer_ID,
	splice: editor.Working_Splice,
) -> (ok: bool, failure: Failure_Context) {
	state, state_failure := multibuffer_building_state(transaction)
	if state_failure.code != .None {
		return false, state_failure
	}
	participant := multibuffer_find_participant(state, buffer_id)
	if participant == nil {
		return false, multibuffer_abort_failure(state, .Wrong_Buffer, buffer_id)
	}
	if state.usage.admitted_splices >= state.limits.splices {
		failure = multibuffer_failure_for_buffer(state, .Splice_Limit, buffer_id)
		failure.limit = state.limits.splices
		failure.actual = state.usage.admitted_splices + 1
		multibuffer_abort_state(state)
		return false, failure
	}
	applied, apply_failure := transaction_splice(&participant.transaction, splice)
	if !applied {
		multibuffer_abort_state(state)
		return false, apply_failure
	}
	usage, usage_ok := multibuffer_collect_usage(state)
	if !usage_ok || usage.text_bytes > state.limits.text_bytes ||
	   usage.metadata_bytes > state.limits.metadata_bytes {
		failure = multibuffer_failure_for_buffer(state, .Text_Limit, buffer_id)
		failure.limit = state.limits.text_bytes
		failure.actual = usage.text_bytes
		if !usage_ok || usage.metadata_bytes > state.limits.metadata_bytes {
			failure.code = .Metadata_Memory_Limit
			failure.limit = state.limits.metadata_bytes
			failure.actual = usage.metadata_bytes
		}
		multibuffer_abort_state(state)
		return false, failure
	}
	state.usage = usage
	return true, {}
}

/* multibuffer_inspect copies private text for one declared buffer. */
multibuffer_inspect :: proc(
	transaction: ^Multibuffer_Transaction,
	buffer_id: editor.Buffer_ID,
	start, end: editor.Working_Position,
	destination: []byte,
) -> (copied: u64, ok: bool, failure: Failure_Context) {
	state, state_failure := multibuffer_building_state(transaction)
	if state_failure.code != .None {
		return 0, false, state_failure
	}
	participant := multibuffer_find_participant(state, buffer_id)
	if participant == nil {
		return 0, false, multibuffer_failure_for_buffer(state, .Wrong_Buffer, buffer_id)
	}
	return transaction_inspect(&participant.transaction, start, end, destination)
}

/* multibuffer_request_cancel marks the complete root for cooperative abort. */
multibuffer_request_cancel :: proc(
	transaction: ^Multibuffer_Transaction,
) -> (ok: bool, failure: Failure_Context) {
	state, state_failure := multibuffer_live_state(transaction)
	if state_failure.code != .None {
		return false, state_failure
	}
	if state.observer_active {
		return false, multibuffer_failure(state, .Reentrant_Mutation)
	}
	if state.lifecycle != .Building && state.lifecycle != .Ready {
		return false, multibuffer_failure(state, .Invalid_State)
	}
	state.cancel_requested = true
	return true, {}
}

/* multibuffer_validate freezes and reserves every participant before publication. */
multibuffer_validate :: proc(
	transaction: ^Multibuffer_Transaction,
) -> (ok: bool, failure: Failure_Context) {
	return multibuffer_validate_before(transaction, max(u64))
}

/*
multibuffer_commit publishes the prepared set in deterministic order without allocation,
callbacks, cancellation checks, or expected failure between participant installations.
*/
multibuffer_commit :: proc(
	transaction: ^Multibuffer_Transaction,
	observer := Multibuffer_Observer{},
) -> (result: Multibuffer_Commit_Result, ok: bool, failure: Failure_Context) {
	state, state_failure := multibuffer_live_state(transaction)
	if state_failure.code != .None {
		return {}, false, state_failure
	}
	if state.observer_active {
		return {}, false, multibuffer_failure(state, .Reentrant_Mutation)
	}
	if state.lifecycle != .Ready {
		return {}, false, multibuffer_failure(state, .Invalid_State)
	}
	if state.cancel_requested {
		failure = multibuffer_failure(state, .Cancelled)
		multibuffer_abort_state(state)
		return {}, false, failure
	}
	state.lifecycle = .Publishing
	for &participant, index in state.participants {
		participant_state := (^Transaction_State)(participant.transaction.state)
		assert(participant_state.lifecycle == .Ready)
		participant_state.lifecycle = .Publishing
		participant_state.result_revision = editor.working_revision_publish_reserved(
			&participant_state.working,
			participant_state.publication_splices,
		)
		participant_state.logical_view_result = transaction_logical_view_publish_reserved(
			participant_state,
			participant_state.result_revision,
		)
		participant_state.lifecycle = .Committed
		state.results[index].result_revision = participant_state.result_revision
	}
	if history.multibuffer_reservation_is_valid(&state.history_reservation) {
		history.multibuffer_reservation_commit_reserved(&state.history_reservation)
	}
	state.lifecycle = .Committed
	if observer.procedure != nil {
		state.observer_active = true
		delivered := observer.procedure(observer.user_data, multibuffer_commit_event(state))
		state.observer_active = false
		state.observer_status = .Succeeded if delivered else .Failed
	}
	return multibuffer_commit_result(state), true, {}
}

/* multibuffer_result returns the shared committed result retained until close. */
multibuffer_result :: proc(
	transaction: ^Multibuffer_Transaction,
) -> (result: Multibuffer_Commit_Result, ok: bool, failure: Failure_Context) {
	state, state_failure := multibuffer_live_state(transaction)
	if state_failure.code != .None {
		return {}, false, state_failure
	}
	if state.lifecycle != .Committed {
		return {}, false, multibuffer_failure(state, .Invalid_State)
	}
	return multibuffer_commit_result(state), true, {}
}

/* multibuffer_event_for_buffer filters one shared event without changing its identity. */
multibuffer_event_for_buffer :: proc(
	event: Multibuffer_Commit_Event,
	buffer_id: editor.Buffer_ID,
) -> (filtered: Buffer_Commit_Event, ok: bool) {
	low := 0
	high := len(event.buffers)
	for low < high {
		middle := low + (high - low) / 2
		buffer := event.buffers[middle]
		if buffer.buffer_id == buffer_id {
			return Buffer_Commit_Event {
				transaction_id = event.transaction_id,
				undo_unit_id = event.undo_unit_id,
				origin = event.origin,
				command = event.command,
				buffer = buffer,
				usage = event.usage,
			}, true
		}
		if u64(buffer.buffer_id) < u64(buffer_id) {
			low = middle + 1
		} else {
			high = middle
		}
	}
	return {}, false
}

/* multibuffer_abort discards every unpublished private participant. */
multibuffer_abort :: proc(
	transaction: ^Multibuffer_Transaction,
) -> (ok: bool, failure: Failure_Context) {
	state, state_failure := multibuffer_live_state(transaction)
	if state_failure.code != .None {
		return false, state_failure
	}
	if state.observer_active {
		return false, multibuffer_failure(state, .Reentrant_Mutation)
	}
	if state.lifecycle != .Building && state.lifecycle != .Validating && state.lifecycle != .Ready {
		return false, multibuffer_failure(state, .Invalid_State)
	}
	multibuffer_abort_state(state)
	return true, {}
}

/*
multibuffer_close releases root storage and aborts any unpublished participants.
Every borrowed result view expires when this procedure returns.
*/
multibuffer_close :: proc(
	transaction: ^Multibuffer_Transaction,
) -> (ok: bool, failure: Failure_Context) {
	state, state_failure := multibuffer_live_state(transaction)
	if state_failure.code != .None {
		return false, state_failure
	}
	if state.observer_active {
		return false, multibuffer_failure(state, .Reentrant_Mutation)
	}
	if state.lifecycle != .Committed && state.lifecycle != .Aborted {
		multibuffer_abort_state(state)
	}
	transaction.state = nil
	transaction_id := state.transaction_id
	multibuffer_release(state)
	return true, Failure_Context{transaction_id = transaction_id}
}

@(private)
multibuffer_validate_before :: proc(
	transaction: ^Multibuffer_Transaction,
	fail_before_ready_participant: u64,
) -> (ok: bool, failure: Failure_Context) {
	state, state_failure := multibuffer_building_state(transaction)
	if state_failure.code != .None {
		return false, state_failure
	}
	state.lifecycle = .Validating
	if state.cancel_requested {
		failure = multibuffer_failure(state, .Cancelled)
		multibuffer_abort_state(state)
		return false, failure
	}
	for &participant, index in state.participants {
		if u64(index) == fail_before_ready_participant {
			failure = multibuffer_failure_for_buffer(
				state,
				.Persistent_Memory_Limit,
				participant.buffer_id,
			)
			failure.actual = u64(index)
			multibuffer_abort_state(state)
			return false, failure
		}
		participant_state := (^Transaction_State)(participant.transaction.state)
		participant_state.lifecycle = .Building
		validated, validation_failure := transaction_validate(&participant.transaction)
		if !validated {
			multibuffer_abort_state(state)
			return false, validation_failure
		}
		state.results[index] = Buffer_Commit_Result {
			buffer_id = participant_state.buffer_id,
			base_revision = participant_state.base_revision,
			splices = participant_state.normalized,
		}
	}
	usage, usage_ok := multibuffer_collect_usage(state)
	if !usage_ok || usage.text_bytes > state.limits.text_bytes ||
	   usage.metadata_bytes > state.limits.metadata_bytes {
		failure = multibuffer_failure(state, .Metadata_Memory_Limit)
		failure.limit = state.limits.metadata_bytes
		failure.actual = usage.metadata_bytes
		multibuffer_abort_state(state)
		return false, failure
	}
	state.usage = usage
	history_reserved, history_failure := multibuffer_history_reserve(state)
	if !history_reserved {
		failure = multibuffer_history_failure(state, history_failure)
		multibuffer_abort_state(state)
		return false, failure
	}
	state.lifecycle = .Ready
	return true, {}
}

@(private)
multibuffer_history_reserve :: proc(
	state: ^Multibuffer_State,
) -> (ok: bool, failure: history.Failure_Context) {
	attached := false
	for &participant in state.participants {
		participant_state := (^Transaction_State)(participant.transaction.state)
		if participant_state.history_store != nil {
			attached = true
			break
		}
	}
	if !attached {
		return true, {}
	}
	inputs, input_error := make(
		[]history.Multibuffer_Record_Input,
		len(state.participants),
		state.temporary_allocator,
	)
	if input_error != nil {
		return false, history.Failure_Context{code = .Temporary_Memory_Limit}
	}
	defer multibuffer_history_inputs_release(inputs, state.temporary_allocator)
	for &participant, index in state.participants {
		participant_state := (^Transaction_State)(participant.transaction.state)
		if participant_state.history_store == nil || len(participant_state.normalized) == 0 {
			return false, history.Failure_Context {
				code = .Incomplete_Participant_Set,
				buffer_id = participant.buffer_id,
			}
		}
		edits, edit_error := make(
			[]history.Edit_Payload,
			len(participant_state.normalized),
			state.temporary_allocator,
		)
		if edit_error != nil {
			return false, history.Failure_Context {
				code = .Temporary_Memory_Limit,
				buffer_id = participant.buffer_id,
			}
		}
		for splice, splice_index in participant_state.normalized {
			edits[splice_index] = history.Edit_Payload {
				start = splice.start,
				end = splice.end,
				replacement_text = splice.replacement_text,
				removed_text = splice.removed_text,
			}
		}
		inputs[index] = history.Multibuffer_Record_Input {
			store = participant_state.history_store,
			record = history.Record_Input {
				source_transaction_id = history.Source_Transaction_ID(state.transaction_id),
				source_undo_unit_id = history.Source_Undo_Unit_ID(state.undo_unit_id),
				buffer_id = participant_state.buffer_id,
				base_revision = participant_state.base_revision,
				result_revision = editor.Revision(u64(participant_state.base_revision) + 1),
				edits = edits,
				origin = history_origin(participant_state.origin_kind),
				origin_descriptor = participant_state.origin_descriptor,
				command = participant_state.command,
				cursor = participant_state.history_cursor,
				grouping = history.Grouping_Context{kind = .Independent},
			},
		}
	}
	return history.multibuffer_record_reserve(&state.history_reservation, inputs)
}

@(private)
multibuffer_history_inputs_release :: proc(
	inputs: []history.Multibuffer_Record_Input,
	allocator: runtime.Allocator,
) {
	for input in inputs {
		if input.record.edits != nil {
			delete(input.record.edits, allocator)
		}
	}
	delete(inputs, allocator)
}

@(private)
multibuffer_seed_less :: proc(left, right: Multibuffer_Seed) -> bool {
	return u64(left.buffer_id) < u64(right.buffer_id)
}

@(private)
multibuffer_history_seed_less :: proc(left, right: Multibuffer_History_Seed) -> bool {
	return u64(left.buffer_id) < u64(right.buffer_id)
}

@(private)
multibuffer_find_participant :: proc(
	state: ^Multibuffer_State,
	buffer_id: editor.Buffer_ID,
) -> ^Multibuffer_Participant {
	low := 0
	high := len(state.participants)
	for low < high {
		middle := low + (high - low) / 2
		participant := &state.participants[middle]
		if participant.buffer_id == buffer_id {
			return participant
		}
		if u64(participant.buffer_id) < u64(buffer_id) {
			low = middle + 1
		} else {
			high = middle
		}
	}
	return nil
}

@(private)
multibuffer_collect_usage :: proc(state: ^Multibuffer_State) -> (Resource_Usage, bool) {
	usage := Resource_Usage {
		buffer_participants = u64(len(state.participants)),
		metadata_bytes = u64(size_of(Multibuffer_State)) +
		                 u64(len(state.participants)) * u64(size_of(Multibuffer_Participant)) +
		                 u64(len(state.results)) * u64(size_of(Buffer_Commit_Result)),
	}
	for &participant in state.participants {
		if !transaction_is_valid(&participant.transaction) {
			continue
		}
		participant_state := (^Transaction_State)(participant.transaction.state)
		participant_usage := transaction_usage(participant_state)
		fields := [7]^u64 {
			&usage.admitted_splices,
			&usage.text_bytes,
			&usage.metadata_bytes,
			&usage.checkpoints,
			&usage.nested_commands,
			&usage.savepoints,
			&usage.logical_views,
		}
		values := [7]u64 {
			participant_usage.admitted_splices,
			participant_usage.text_bytes,
			participant_usage.metadata_bytes,
			participant_usage.checkpoints,
			participant_usage.nested_commands,
			participant_usage.savepoints,
			participant_usage.logical_views,
		}
		for field, index in fields {
			total, total_ok := checked_add_u64(field^, values[index])
			if !total_ok {
				return usage, false
			}
			field^ = total
		}
	}
	return usage, true
}

@(private)
multibuffer_abort_state :: proc(state: ^Multibuffer_State) {
	if history.multibuffer_reservation_is_valid(&state.history_reservation) {
		aborted, history_failure := history.multibuffer_reservation_abort(&state.history_reservation)
		assert(aborted && history_failure.code == .None)
	}
	for &participant in state.participants {
		if !transaction_is_valid(&participant.transaction) {
			continue
		}
		participant_state := (^Transaction_State)(participant.transaction.state)
		if participant_state.lifecycle == .Building ||
		   participant_state.lifecycle == .Validating ||
		   participant_state.lifecycle == .Ready {
			transaction_abort_state(participant_state)
		}
	}
	state.lifecycle = .Aborted
}

@(private)
multibuffer_release :: proc(state: ^Multibuffer_State) {
	allocator := state.allocator
	for &participant in state.participants {
		if transaction_is_valid(&participant.transaction) {
			closed, close_failure := transaction_close(&participant.transaction)
			assert(closed && close_failure.code == .None)
		}
	}
	if state.results != nil {
		delete(state.results, allocator)
	}
	if state.participants != nil {
		delete(state.participants, allocator)
	}
	state.lifecycle = .Closed
	free(state, allocator)
}

@(private)
multibuffer_live_state :: proc(
	transaction: ^Multibuffer_Transaction,
) -> (^Multibuffer_State, Failure_Context) {
	if !multibuffer_transaction_is_valid(transaction) {
		return nil, Failure_Context{code = .Invalid_State}
	}
	state := (^Multibuffer_State)(transaction.state)
	if state.lifecycle == .Invalid || state.lifecycle == .Closed {
		return nil, Failure_Context{code = .Invalid_State, transaction_id = state.transaction_id}
	}
	return state, {}
}

@(private)
multibuffer_building_state :: proc(
	transaction: ^Multibuffer_Transaction,
) -> (^Multibuffer_State, Failure_Context) {
	state, failure := multibuffer_live_state(transaction)
	if failure.code != .None {
		return nil, failure
	}
	if state.observer_active {
		return nil, multibuffer_failure(state, .Reentrant_Mutation)
	}
	if state.lifecycle != .Building {
		return nil, multibuffer_failure(state, .Invalid_State)
	}
	return state, {}
}

@(private)
multibuffer_failure :: proc(state: ^Multibuffer_State, code: Failure_Code) -> Failure_Context {
	return Failure_Context{code = code, transaction_id = state.transaction_id}
}

@(private)
multibuffer_failure_for_buffer :: proc(
	state: ^Multibuffer_State,
	code: Failure_Code,
	buffer_id: editor.Buffer_ID,
) -> Failure_Context {
	failure := multibuffer_failure(state, code)
	failure.buffer_id = buffer_id
	return failure
}

@(private)
multibuffer_history_failure :: proc(
	state: ^Multibuffer_State,
	history_failure: history.Failure_Context,
) -> Failure_Context {
	return Failure_Context {
		code = .History_Failure,
		transaction_id = state.transaction_id,
		buffer_id = history_failure.buffer_id,
		limit = history_failure.maximum,
		actual = history_failure.actual,
		history_failure = history_failure,
	}
}

@(private)
multibuffer_abort_failure :: proc(
	state: ^Multibuffer_State,
	code: Failure_Code,
	buffer_id: editor.Buffer_ID,
) -> Failure_Context {
	failure := multibuffer_failure_for_buffer(state, code, buffer_id)
	multibuffer_abort_state(state)
	return failure
}

@(private)
multibuffer_commit_event :: proc(state: ^Multibuffer_State) -> Multibuffer_Commit_Event {
	first := (^Transaction_State)(state.participants[0].transaction.state)
	return Multibuffer_Commit_Event {
		transaction_id = state.transaction_id,
		undo_unit_id = state.undo_unit_id,
		origin = Origin{kind = first.origin_kind, descriptor = first.origin_descriptor},
		command = first.command,
		buffers = state.results,
		usage = state.usage,
	}
}

@(private)
multibuffer_commit_result :: proc(state: ^Multibuffer_State) -> Multibuffer_Commit_Result {
	return Multibuffer_Commit_Result {
		event = multibuffer_commit_event(state),
		observer_status = state.observer_status,
	}
}
