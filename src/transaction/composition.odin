// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package transaction

import "../editor"
import "core:unicode/utf8"

/* nested_command_is_valid reports whether a handle identifies an active command frame. */
nested_command_is_valid :: proc(command: ^Nested_Command) -> bool {
	return command != nil &&
	       command^[NESTED_TRANSACTION_INDEX] != 0 &&
	       command^[NESTED_COMMAND_INDEX] != 0 &&
	       command^[NESTED_DEPTH_INDEX] != 0 &&
	       command^[NESTED_SLOT_INDEX] != 0
}

/*
transaction_nested_begin joins one command to a building root and creates its rollback savepoint.
The copied command and origin metadata remain owned by the root until the frame is completed.
*/
transaction_nested_begin :: proc(
	transaction: ^Transaction,
	origin: Origin,
	command: string,
) -> (nested: Nested_Command, ok: bool, failure: Failure_Context) {
	state, state_failure := transaction_building_state(transaction)
	if state_failure.code != .None {
		return {}, false, state_failure
	}
	if !transaction_nested_edit_allowed(state) {
		return {}, false, transaction_failure(state, .Invalid_State)
	}
	if origin.kind == .Invalid || !utf8.valid_string(origin.descriptor) {
		return {}, false, transaction_failure(state, .Invalid_Origin)
	}
	if !utf8.valid_string(command) {
		return {}, false, transaction_failure(state, .Command_Limit)
	}
	if u64(len(origin.descriptor)) > state.limits.origin_bytes {
		return {}, false, transaction_limit_failure(
			state,
			.Origin_Limit,
			state.limits.origin_bytes,
			u64(len(origin.descriptor)),
		)
	}
	if u64(len(command)) > state.limits.command_bytes {
		return {}, false, transaction_limit_failure(
			state,
			.Command_Limit,
			state.limits.command_bytes,
			u64(len(command)),
		)
	}
	next_depth, depth_ok := checked_add_u64(state.nesting_depth, 1)
	if !depth_ok || next_depth > state.limits.nested_command_depth {
		actual := next_depth
		if !depth_ok {
			actual = max(u64)
		}
		return {}, false, transaction_limit_failure(
			state,
			.Nesting_Limit,
			state.limits.nested_command_depth,
			actual,
		)
	}
	next_savepoints, savepoint_ok := checked_add_u64(state.active_savepoints, 1)
	if !savepoint_ok || next_savepoints > state.limits.active_savepoints ||
	   next_savepoints > u64(len(state.savepoint_frames)) {
		actual := next_savepoints
		if !savepoint_ok {
			actual = max(u64)
		}
		return {}, false, transaction_limit_failure(
			state,
			.Savepoint_Limit,
			state.limits.active_savepoints,
			actual,
		)
	}
	if state.next_nested_command_id == 0 {
		return {}, false, transaction_failure(state, .Work_Limit)
	}
	metadata_addition, metadata_addition_ok := checked_add_u64(
		u64(len(origin.descriptor)),
		u64(len(command)),
	)
	metadata_bytes, metadata_ok := checked_add_u64(state.metadata_bytes, metadata_addition)
	if !metadata_addition_ok || !metadata_ok || metadata_bytes > state.limits.metadata_bytes {
		actual := metadata_bytes
		if !metadata_addition_ok || !metadata_ok {
			actual = max(u64)
		}
		return {}, false, transaction_limit_failure(
			state,
			.Metadata_Memory_Limit,
			state.limits.metadata_bytes,
			actual,
		)
	}

	origin_copy, origin_error := clone_string(origin.descriptor, state.allocator)
	if origin_error != nil {
		return {}, false, transaction_failure(state, .Persistent_Memory_Limit)
	}
	command_copy, command_error := clone_string(command, state.allocator)
	if command_error != nil {
		delete_string(origin_copy, state.allocator)
		return {}, false, transaction_failure(state, .Persistent_Memory_Limit)
	}
	working_savepoint: editor.Working_Revision_Savepoint
	opened, editor_failure := editor.working_revision_savepoint_open(
		&state.working,
		&working_savepoint,
	)
	if !opened {
		delete_string(command_copy, state.allocator)
		delete_string(origin_copy, state.allocator)
		return {}, false, transaction_editor_failure(state.transaction_id, state.admitted_splices, editor_failure)
	}

	command_id := state.next_nested_command_id
	if command_id == max(u64) {
		state.next_nested_command_id = 0
	} else {
		state.next_nested_command_id += 1
	}
	slot := state.active_savepoints
	frame := &state.savepoint_frames[int(slot)]
	frame.command_id = command_id
	frame.depth = next_depth
	frame.working = working_savepoint
	frame.saved_normalized = state.normalized
	frame.saved_has_base_batch = state.has_base_batch
	frame.saved_requires_diff = state.requires_diff
	frame.origin_kind = origin.kind
	frame.origin_descriptor = origin_copy
	frame.command = command_copy
	state.nesting_depth = next_depth
	state.active_savepoints = next_savepoints
	state.nested_commands += 1
	state.savepoints += 1
	state.metadata_bytes = metadata_bytes
	return Nested_Command {
		u64(state.transaction_id),
		command_id,
		next_depth,
		slot + 1,
	}, true, {}
}

/* transaction_nested_stats returns active copied metadata without exposing savepoint storage. */
transaction_nested_stats :: proc(
	transaction: ^Transaction,
	nested: ^Nested_Command,
) -> (stats: Nested_Command_Stats, ok: bool, failure: Failure_Context) {
	state, state_failure := transaction_building_state(transaction)
	if state_failure.code != .None {
		return {}, false, state_failure
	}
	frame, _, frame_failure := transaction_nested_frame(state, nested, false)
	if frame_failure.code != .None {
		return {}, false, frame_failure
	}
	return Nested_Command_Stats {
		transaction_id = state.transaction_id,
		depth = frame.depth,
		origin = Origin{kind = frame.origin_kind, descriptor = frame.origin_descriptor},
		command = frame.command,
	}, true, {}
}

/*
transaction_nested_succeed joins the top nested command's private changes into its root.
It consumes the command handle and creates no independent revision or undo unit.
*/
transaction_nested_succeed :: proc(
	transaction: ^Transaction,
	nested: ^Nested_Command,
) -> (ok: bool, failure: Failure_Context) {
	state, state_failure := transaction_building_state(transaction)
	if state_failure.code != .None {
		return false, state_failure
	}
	frame, slot, frame_failure := transaction_nested_frame(state, nested, true)
	if frame_failure.code != .None {
		return false, frame_failure
	}
	if frame.failed {
		return false, transaction_failure(state, .Invalid_State)
	}
	discarded, discard_failure := editor.working_revision_savepoint_discard(&frame.working)
	assert(discarded && discard_failure.code == .None)
	transaction_release_superseded_normalized(state, slot, frame.saved_normalized)
	transaction_nested_frame_pop(state, frame, nested)
	return true, {}
}

/*
transaction_nested_fail restores and consumes the top command savepoint.
A handled failure returns the root to Building; an unhandled failure aborts the root.
*/
transaction_nested_fail :: proc(
	transaction: ^Transaction,
	nested: ^Nested_Command,
	disposition: Nested_Failure_Disposition,
) -> (ok: bool, failure: Failure_Context) {
	state, state_failure := transaction_building_state(transaction)
	if state_failure.code != .None {
		return false, state_failure
	}
	if disposition != .Handled && disposition != .Unhandled {
		return false, transaction_failure(state, .Invalid_Nested_Command)
	}
	frame, _, frame_failure := transaction_nested_frame(state, nested, true)
	if frame_failure.code != .None {
		return false, frame_failure
	}
	restored, restore_failure := editor.working_revision_savepoint_restore(
		&state.working,
		&frame.working,
	)
	if !restored {
		failure = transaction_editor_failure(state.transaction_id, state.admitted_splices, restore_failure)
		if editor.working_revision_savepoint_is_live(&frame.working) {
			discarded, discard_failure := editor.working_revision_savepoint_discard(&frame.working)
			assert(discarded && discard_failure.code == .None)
		}
		transaction_nested_frame_pop(state, frame, nested)
		transaction_abort_state(state)
		return false, failure
	}
	if !normalized_same_storage(state.normalized, frame.saved_normalized) {
		normalized_splices_release(state.normalized, state.allocator)
		state.normalized = frame.saved_normalized
	}
	state.has_base_batch = frame.saved_has_base_batch
	state.requires_diff = frame.saved_requires_diff
	transaction_nested_frame_pop(state, frame, nested)
	if disposition == .Unhandled {
		transaction_abort_state(state)
	}
	return true, {}
}

@(private)
transaction_nested_frame :: proc(
	state: ^Transaction_State,
	nested: ^Nested_Command,
	require_top: bool,
) -> (frame: ^Savepoint_Frame, slot: u64, failure: Failure_Context) {
	if !nested_command_is_valid(nested) ||
	   Transaction_ID(nested^[NESTED_TRANSACTION_INDEX]) != state.transaction_id {
		return nil, 0, transaction_failure(state, .Invalid_Nested_Command)
	}
	slot_value := nested^[NESTED_SLOT_INDEX]
	if slot_value == 0 || slot_value > state.active_savepoints {
		return nil, 0, transaction_failure(state, .Invalid_Nested_Command)
	}
	slot = slot_value - 1
	if require_top && slot_value != state.active_savepoints {
		return nil, 0, transaction_failure(state, .Invalid_Nested_Command)
	}
	frame = &state.savepoint_frames[int(slot)]
	if frame.command_id != nested^[NESTED_COMMAND_INDEX] ||
	   frame.depth != nested^[NESTED_DEPTH_INDEX] {
		return nil, 0, transaction_failure(state, .Invalid_Nested_Command)
	}
	return frame, slot, {}
}

@(private)
transaction_nested_frame_pop :: proc(
	state: ^Transaction_State,
	frame: ^Savepoint_Frame,
	nested: ^Nested_Command,
) {
	assert(state.active_savepoints > 0 && state.nesting_depth > 0)
	delete_string(frame.command, state.allocator)
	delete_string(frame.origin_descriptor, state.allocator)
	frame^ = {}
	state.active_savepoints -= 1
	state.nesting_depth -= 1
	nested^ = {}
}

@(private)
transaction_release_superseded_normalized :: proc(
	state: ^Transaction_State,
	completed_slot: u64,
	saved: []Normalized_Splice,
) {
	if normalized_same_storage(saved, state.normalized) || saved == nil {
		return
	}
	for index in 0 ..< int(completed_slot) {
		if normalized_same_storage(state.savepoint_frames[index].saved_normalized, saved) {
			return
		}
	}
	normalized_splices_release(saved, state.allocator)
}

@(private)
transaction_nested_frames_release :: proc(state: ^Transaction_State) {
	current := state.normalized
	for active := state.active_savepoints; active > 0; active -= 1 {
		index := active - 1
		frame := &state.savepoint_frames[int(index)]
		if editor.working_revision_savepoint_is_live(&frame.working) {
			discarded, discard_failure := editor.working_revision_savepoint_discard(&frame.working)
			assert(discarded && discard_failure.code == .None)
		}
		if frame.saved_normalized != nil &&
		   !normalized_same_storage(frame.saved_normalized, current) {
			shared_below := false
			for lower in 0 ..< int(index) {
				if normalized_same_storage(state.savepoint_frames[lower].saved_normalized, frame.saved_normalized) {
					shared_below = true
					break
				}
			}
			if !shared_below {
				normalized_splices_release(frame.saved_normalized, state.allocator)
			}
		}
		delete_string(frame.command, state.allocator)
		delete_string(frame.origin_descriptor, state.allocator)
		frame^ = {}
	}
	state.active_savepoints = 0
	state.nesting_depth = 0
}

@(private)
normalized_same_storage :: proc(left, right: []Normalized_Splice) -> bool {
	return raw_data(left) == raw_data(right)
}

@(private)
transaction_limit_failure :: proc(
	state: ^Transaction_State,
	code: Failure_Code,
	limit, actual: u64,
) -> Failure_Context {
	failure := transaction_failure(state, code)
	failure.limit = limit
	failure.actual = actual
	return failure
}

@(private)
transaction_nested_edit_allowed :: proc(state: ^Transaction_State) -> bool {
	if state.active_savepoints == 0 {
		return true
	}
	return !state.savepoint_frames[int(state.active_savepoints - 1)].failed
}
