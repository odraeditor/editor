// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package result_set

import "../editor"
import "../history"
import edit_transaction "../transaction"
import "base:runtime"
import "core:unicode/utf8"

MAX_EDIT_PROPOSALS :: u32(4_096)
MAX_EDIT_TEXT_BYTES :: u64(8 * 1_024 * 1_024)

Edit_Projection :: struct {
	state: rawptr,
}

Edit_Proposal :: struct {
	location_id: Location_ID,
	buffer_id:   editor.Buffer_ID,
	revision:    editor.Revision,
	start:       editor.Byte_Offset,
	end:         editor.Byte_Offset,
	replacement: string,
}

Edit_Target :: struct {
	buffer:  ^editor.Buffer,
	history: ^history.Store,
}

Edit_Inspection :: struct {
	set_id:      Result_Set_ID,
	generation:  Result_Set_Generation,
	proposals:   []Edit_Proposal,
	text_bytes:  u64,
	dirty:       bool,
}

Edit_Apply_Result :: struct {
	transaction_id: edit_transaction.Transaction_ID,
	undo_unit_id:   edit_transaction.Undo_Unit_ID,
	buffer_count:   u32,
	proposal_count: u32,
	buffer_id:      editor.Buffer_ID,
	base_revision:  editor.Revision,
	result_revision: editor.Revision,
}

@(private)
Edit_State :: struct {
	set_id:     Result_Set_ID,
	generation: Result_Set_Generation,
	capability: Edit_Capability,
	locations:  []Location,
	proposals:  [dynamic]Edit_Proposal,
	storage:    [dynamic][]u8,
	text_bytes: u64,
	allocator:  runtime.Allocator,
}

/* edit_projection_begin creates a checked staging surface for one immutable result generation. */
edit_projection_begin :: proc(
	projection: ^Edit_Projection,
	view: View,
	allocator := context.allocator,
) -> (bool, Failure) {
	if projection == nil || projection.state != nil || allocator.procedure == nil ||
	   view.set_id == Result_Set_ID(0) || view.generation == Result_Set_Generation(0) ||
	   view.edit_capability == .Invalid || view.edit_capability == .Read_Only {
		return false, Failure{code = .Invalid_Publication, set_id = view.set_id}
	}
	state, allocation_error := new(Edit_State, allocator)
	if allocation_error != nil do return false, Failure{code = .Persistent_Memory_Limit, set_id = view.set_id}
	state^ = {set_id = view.set_id, generation = view.generation,
		capability = view.edit_capability, allocator = allocator}
	state.locations, allocation_error = make([]Location, len(view.locations), allocator)
	if allocation_error != nil {
		free(state, allocator)
		return false, Failure{code = .Persistent_Memory_Limit, set_id = view.set_id}
	}
	copy(state.locations, view.locations)
	state.proposals, allocation_error = make([dynamic]Edit_Proposal, 0, int(MAX_EDIT_PROPOSALS), allocator)
	if allocation_error != nil {
		delete(state.locations, allocator)
		free(state, allocator)
		return false, Failure{code = .Persistent_Memory_Limit, set_id = view.set_id}
	}
	state.storage, allocation_error = make([dynamic][]u8, 0, int(MAX_EDIT_PROPOSALS), allocator)
	if allocation_error != nil {
		delete(state.proposals)
		delete(state.locations, allocator)
		free(state, allocator)
		return false, Failure{code = .Persistent_Memory_Limit, set_id = view.set_id}
	}
	projection.state = state
	return true, {}
}

/* edit_projection_stage replaces one location's staged text without touching source buffers. */
edit_projection_stage :: proc(
	projection: ^Edit_Projection,
	location_id: Location_ID,
	replacement: string,
) -> (bool, Failure) {
	state := edit_state(projection)
	if state == nil || location_id == Location_ID(0) || !utf8.valid_string(replacement) {
		return false, Failure{code = .Invalid_Location, location_id = location_id}
	}
	location, found := edit_location(state, location_id)
	if !found do return false, Failure{code = .Invalid_Location, set_id = state.set_id,
		location_id = location_id}
	existing := -1
	for proposal, index in state.proposals do if proposal.location_id == location_id do existing = index
	previous_bytes := u64(0)
	if existing >= 0 do previous_bytes = u64(len(state.proposals[existing].replacement))
	projected := state.text_bytes - previous_bytes + u64(len(replacement))
	if projected > MAX_EDIT_TEXT_BYTES do return false, Failure{code = .Text_Limit,
		set_id = state.set_id, limit = MAX_EDIT_TEXT_BYTES, actual = projected}
	copy_bytes, allocation_error := make([]u8, len(replacement), state.allocator)
	if allocation_error != nil do return false, Failure{code = .Persistent_Memory_Limit, set_id = state.set_id}
	copy(copy_bytes, transmute([]u8)replacement)
	proposal := Edit_Proposal{location_id = location.id, buffer_id = location.buffer_id,
		revision = location.revision, start = location.start, end = location.end,
		replacement = string(copy_bytes)}
	if existing >= 0 {
		delete(state.storage[existing], state.allocator)
		state.storage[existing] = copy_bytes
		state.proposals[existing] = proposal
	} else {
		if len(state.proposals) >= int(MAX_EDIT_PROPOSALS) {
			delete(copy_bytes, state.allocator)
			return false, Failure{code = .Location_Limit, set_id = state.set_id,
				limit = u64(MAX_EDIT_PROPOSALS), actual = u64(len(state.proposals) + 1)}
		}
		if _, append_error := append(&state.storage, copy_bytes); append_error != nil {
			delete(copy_bytes, state.allocator)
			return false, Failure{code = .Persistent_Memory_Limit, set_id = state.set_id}
		}
		if _, append_error := append(&state.proposals, proposal); append_error != nil {
			delete(state.storage[len(state.storage) - 1], state.allocator)
			ordered_remove(&state.storage, len(state.storage) - 1)
			return false, Failure{code = .Persistent_Memory_Limit, set_id = state.set_id}
		}
	}
	state.text_bytes = projected
	return true, {}
}

/* edit_projection_inspect borrows exact staged diffs until the next projection operation. */
edit_projection_inspect :: proc(projection: ^Edit_Projection) -> (Edit_Inspection, bool) {
	state := edit_state(projection)
	if state == nil do return {}, false
	return {set_id = state.set_id, generation = state.generation, proposals = state.proposals[:],
		text_bytes = state.text_bytes, dirty = len(state.proposals) > 0}, true
}

/* edit_projection_close protects staged changes unless discard is explicit. */
edit_projection_close :: proc(projection: ^Edit_Projection, discard := false) -> (bool, Failure) {
	state := edit_state(projection)
	if state == nil do return false, Failure{code = .Invalid_Publication}
	if len(state.proposals) > 0 && !discard do return false,
		Failure{code = .Invalid_Publication, set_id = state.set_id, actual = u64(len(state.proposals))}
	edit_state_release(state)
	projection.state = nil
	return true, {}
}

/* edit_projection_apply preflights every target and publishes one shared transaction. */
edit_projection_apply :: proc(
	projection: ^Edit_Projection,
	targets: []Edit_Target,
	transaction_id: edit_transaction.Transaction_ID,
	undo_unit_id: edit_transaction.Undo_Unit_ID,
	allocators: edit_transaction.Allocator_Set,
) -> (Edit_Apply_Result, bool, edit_transaction.Failure_Context) {
	state := edit_state(projection)
	if state == nil || len(state.proposals) == 0 || len(targets) == 0 {
		return {}, false, edit_transaction.Failure_Context{code = .Invalid_State,
			transaction_id = transaction_id}
	}
	if state.capability == .Single_Buffer && len(targets) != 1 {
		return {}, false, edit_transaction.Failure_Context{code = .Participant_Limit,
			transaction_id = transaction_id, limit = 1, actual = u64(len(targets))}
	}
	buffers, buffer_error := make([]^editor.Buffer, len(targets), allocators.temporary)
	if buffer_error != nil do return {}, false,
		edit_transaction.Failure_Context{code = .Temporary_Memory_Limit, transaction_id = transaction_id}
	defer delete(buffers, allocators.temporary)
	stores, store_error := make([]^history.Store, len(targets), allocators.temporary)
	if store_error != nil do return {}, false,
		edit_transaction.Failure_Context{code = .Temporary_Memory_Limit, transaction_id = transaction_id}
	defer delete(stores, allocators.temporary)
	for target, index in targets {
		if target.buffer == nil || target.history == nil do return {}, false,
			edit_transaction.Failure_Context{code = .Incomplete_Participant_Set, transaction_id = transaction_id}
		buffers[index] = target.buffer
		stores[index] = target.history
	}
	if state.capability == .Single_Buffer {
		result, applied, failure := edit_projection_apply_single_buffer(
			state, targets[0], transaction_id, undo_unit_id, allocators,
		)
		if !applied do return {}, false, failure
		for bytes in state.storage do delete(bytes, state.allocator)
		clear(&state.storage)
		clear(&state.proposals)
		state.text_bytes = 0
		return result, true, {}
	}
	root: edit_transaction.Multibuffer_Transaction
	started, failure := edit_transaction.multibuffer_begin(&root, transaction_id, undo_unit_id,
		buffers, {kind = .Built_In, descriptor = "result-set"}, "apply-result-edits", allocators)
	if !started do return {}, false, failure
	defer if edit_transaction.multibuffer_transaction_is_valid(&root) do _, _ = edit_transaction.multibuffer_close(&root)
	tracked: bool
	tracked, failure = edit_transaction.multibuffer_track_history(&root, stores)
	if !tracked do return {}, false, failure
	for target in targets {
		stats, stats_ok, editor_failure := editor.buffer_stats(target.buffer)
		if !stats_ok do return {}, false, edit_transaction.Failure_Context{
			code = .Invalid_State, transaction_id = transaction_id, editor_failure = editor_failure}
		count := 0
		for proposal in state.proposals do if proposal.buffer_id == stats.buffer_id do count += 1
		if count == 0 do continue
		batch, batch_error := make([]edit_transaction.Base_Splice, count, allocators.temporary)
		if batch_error != nil do return {}, false,
			edit_transaction.Failure_Context{code = .Temporary_Memory_Limit, transaction_id = transaction_id}
		batch_index := 0
		batch_ok := true
		for proposal in state.proposals {
			if proposal.buffer_id != stats.buffer_id do continue
			if proposal.revision != stats.revision {
				batch_ok = false
				failure = edit_transaction.Failure_Context{code = .Stale_Revision, transaction_id = transaction_id,
					buffer_id = stats.buffer_id, base_revision = proposal.revision}
				break
			}
			start, start_ok, _ := editor.buffer_position(target.buffer, proposal.start)
			end, end_ok, _ := editor.buffer_position(target.buffer, proposal.end)
			if !start_ok || !end_ok {
				batch_ok = false
				failure = edit_transaction.Failure_Context{code = .Out_Of_Range, transaction_id = transaction_id,
					buffer_id = stats.buffer_id}
				break
			}
			batch[batch_index] = {start = start, end = end, replacement = proposal.replacement}
			batch_index += 1
		}
		if batch_ok {
			batch_ok, failure = edit_transaction.multibuffer_apply_batch(&root, stats.buffer_id, batch)
		}
		delete(batch, allocators.temporary)
		if !batch_ok do return {}, false, failure
	}
	validated: bool
	validated, failure = edit_transaction.multibuffer_validate(&root)
	if !validated do return {}, false, failure
	commit: edit_transaction.Multibuffer_Commit_Result
	committed: bool
	commit, committed, failure = edit_transaction.multibuffer_commit(&root)
	if !committed do return {}, false, failure
	result := Edit_Apply_Result{transaction_id = commit.transaction_id, undo_unit_id = commit.undo_unit_id,
		buffer_count = u32(len(commit.buffers)), proposal_count = u32(len(state.proposals))}
	if len(commit.buffers) == 1 {
		result.buffer_id = commit.buffers[0].buffer_id
		result.base_revision = commit.buffers[0].base_revision
		result.result_revision = commit.buffers[0].result_revision
	}
	for bytes in state.storage do delete(bytes, state.allocator)
	clear(&state.storage)
	clear(&state.proposals)
	state.text_bytes = 0
	return result, true, {}
}

@(private)
edit_projection_apply_single_buffer :: proc(
	state: ^Edit_State,
	target: Edit_Target,
	transaction_id: edit_transaction.Transaction_ID,
	undo_unit_id: edit_transaction.Undo_Unit_ID,
	allocators: edit_transaction.Allocator_Set,
) -> (Edit_Apply_Result, bool, edit_transaction.Failure_Context) {
	stats, stats_ok, editor_failure := editor.buffer_stats(target.buffer)
	if !stats_ok do return {}, false, edit_transaction.Failure_Context{
		code = .Invalid_State, transaction_id = transaction_id, editor_failure = editor_failure}
	batch, batch_error := make([]edit_transaction.Base_Splice, len(state.proposals), allocators.temporary)
	if batch_error != nil do return {}, false,
		edit_transaction.Failure_Context{code = .Temporary_Memory_Limit, transaction_id = transaction_id}
	defer delete(batch, allocators.temporary)
	for proposal, index in state.proposals {
		if proposal.buffer_id != stats.buffer_id do return {}, false,
			edit_transaction.Failure_Context{code = .Incomplete_Participant_Set,
				transaction_id = transaction_id, buffer_id = proposal.buffer_id}
		if proposal.revision != stats.revision do return {}, false,
			edit_transaction.Failure_Context{code = .Stale_Revision, transaction_id = transaction_id,
				buffer_id = stats.buffer_id, base_revision = proposal.revision}
		start, start_ok, _ := editor.buffer_position(target.buffer, proposal.start)
		end, end_ok, _ := editor.buffer_position(target.buffer, proposal.end)
		if !start_ok || !end_ok do return {}, false,
			edit_transaction.Failure_Context{code = .Out_Of_Range, transaction_id = transaction_id,
				buffer_id = stats.buffer_id}
		batch[index] = {start = start, end = end, replacement = proposal.replacement}
	}
	root: edit_transaction.Transaction
	started, failure := edit_transaction.transaction_begin(&root, transaction_id, undo_unit_id,
		target.buffer, {kind = .Built_In, descriptor = "result-set"}, "apply-result-edits", allocators)
	if !started do return {}, false, failure
	defer if edit_transaction.transaction_is_valid(&root) do _, _ = edit_transaction.transaction_close(&root)
	applied: bool
	applied, failure = edit_transaction.transaction_apply_batch(&root, batch)
	if !applied do return {}, false, failure
	tracked: bool
	tracked, failure = edit_transaction.transaction_track_history(&root, target.history)
	if !tracked do return {}, false, failure
	validated: bool
	validated, failure = edit_transaction.transaction_validate(&root)
	if !validated do return {}, false, failure
	commit: edit_transaction.Commit_Result
	committed: bool
	commit, committed, failure = edit_transaction.transaction_commit(&root)
	if !committed do return {}, false, failure
	return Edit_Apply_Result{
		transaction_id = commit.transaction_id,
		undo_unit_id = commit.undo_unit_id,
		buffer_id = commit.buffer_id,
		base_revision = commit.base_revision,
		result_revision = commit.result_revision,
		buffer_count = 1,
		proposal_count = u32(len(state.proposals)),
	}, true, {}
}

@(private)
edit_state :: proc(projection: ^Edit_Projection) -> ^Edit_State {
	if projection == nil || projection.state == nil do return nil
	return (^Edit_State)(projection.state)
}

@(private)
edit_location :: proc(state: ^Edit_State, id: Location_ID) -> (Location, bool) {
	for location in state.locations do if location.id == id do return location, true
	return {}, false
}

@(private)
edit_state_release :: proc(state: ^Edit_State) {
	for bytes in state.storage do delete(bytes, state.allocator)
	delete(state.storage)
	delete(state.proposals)
	delete(state.locations, state.allocator)
	allocator := state.allocator
	free(state, allocator)
}
