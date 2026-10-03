// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package editor

import "../text"
import "base:runtime"
import "core:unicode/utf8"

@(private)
Working_Revision_Phase :: enum u8 {
	Invalid,
	Building,
	Publishing,
	Published,
	Aborted,
}

@(private)
Working_Revision_State :: struct {
	phase:               Working_Revision_Phase,
	owner:               ^Buffer_State,
	buffer_id:           Buffer_ID,
	base_revision:       Revision,
	working_revision_id: Working_Revision_ID,
	generation:          u64,
	working_root:        text.Root,
	allocator:           runtime.Allocator,
	has_compat_record:   bool,
	compat_change_set:   Change_Set,
	compat_undo_record:  Undo_Record,
}

/* working_revision_is_valid reports whether a handle still owns private state. */
working_revision_is_valid :: proc(working: ^Working_Revision) -> bool {
	return working != nil && working.state != nil
}

/*
buffer_working_revision_open retains the confirmed root as private working state.
Only one working revision may be live for a buffer. The caller must abort or publish it.
*/
buffer_working_revision_open :: proc(
	buffer: ^Buffer,
) -> (working: Working_Revision, ok: bool, failure: Failure_Context) {
	owner, owner_failure := buffer_live_state(buffer)
	if owner_failure.code != .None {
		return {}, false, owner_failure
	}
	if owner.kind != .Text || owner.read_only {
		return {}, false, Failure_Context {
			code = .Read_Only_Buffer,
			buffer_id = owner.buffer_id,
			revision = owner.revision,
		}
	}
	return buffer_working_revision_open_state(owner)
}

@(private)
buffer_working_revision_open_state :: proc(
	owner: ^Buffer_State,
) -> (working: Working_Revision, ok: bool, failure: Failure_Context) {
	assert(owner != nil)
	if owner.active_preparations != 0 {
		return {}, false, Failure_Context {
			code = .Work_Limit,
			buffer_id = owner.buffer_id,
			revision = owner.revision,
			limit = 1,
			actual = u64(owner.active_preparations + 1),
		}
	}
	if owner.next_working_revision_id == Working_Revision_ID(0) {
		return {}, false, Failure_Context {
			code = .Work_Limit,
			buffer_id = owner.buffer_id,
			revision = owner.revision,
		}
	}

	root_stats, stats_ok := text.root_stats(owner.text_root)
	assert(stats_ok)
	private_bytes, private_ok := checked_add_u64(owner.private_bytes, u64(size_of(Working_Revision_State)))
	base_bytes, base_ok := checked_add_u64(root_stats.persistent_bytes, u64(size_of(Buffer_State)))
	total_bytes, total_ok := checked_add_u64(base_bytes, private_bytes)
	if !private_ok || !base_ok || !total_ok || total_bytes > owner.limits.persistent_bytes {
		actual := total_bytes
		if !private_ok || !base_ok || !total_ok {
			actual = max(u64)
		}
		return {}, false, Failure_Context {
			code = .Persistent_Memory_Limit,
			buffer_id = owner.buffer_id,
			revision = owner.revision,
			limit = owner.limits.persistent_bytes,
			actual = actual,
		}
	}

	state, allocation_error := new(Working_Revision_State, owner.allocator)
	if allocation_error != nil {
		return {}, false, Failure_Context {
			code = .Persistent_Memory_Limit,
			buffer_id = owner.buffer_id,
			revision = owner.revision,
			limit = owner.limits.persistent_bytes,
			actual = u64(size_of(Working_Revision_State)),
		}
	}
	retained_root, retain_failure := text.root_retain(owner.text_root)
	if retain_failure.code != .None {
		free(state, owner.allocator)
		return {}, false, storage_failure_context(owner.buffer_id, retain_failure)
	}

	state.phase = .Building
	state.owner = owner
	state.buffer_id = owner.buffer_id
	state.base_revision = owner.revision
	state.working_revision_id = owner.next_working_revision_id
	state.working_root = retained_root
	state.allocator = owner.allocator
	owner.active_preparations = 1
	owner.private_bytes = private_bytes
	if u64(owner.next_working_revision_id) == max(u64) {
		owner.next_working_revision_id = Working_Revision_ID(0)
	} else {
		owner.next_working_revision_id = Working_Revision_ID(u64(owner.next_working_revision_id) + 1)
	}
	return Working_Revision{state = state}, true, {}
}

/* working_revision_stats returns the identity and size of the current private generation. */
working_revision_stats :: proc(
	working: ^Working_Revision,
) -> (stats: Working_Revision_Stats, ok: bool, failure: Failure_Context) {
	state, state_failure := working_revision_live_state(working)
	if state_failure.code != .None {
		return {}, false, state_failure
	}
	root_stats, stats_ok := text.root_stats(state.working_root)
	assert(stats_ok)
	return Working_Revision_Stats {
		buffer_id = state.buffer_id,
		base_revision = state.base_revision,
		working_revision_id = state.working_revision_id,
		generation = state.generation,
		text_bytes = u64(root_stats.summary.byte_count),
	}, true, {}
}

/* working_revision_position validates one UTF-8 boundary in the current private generation. */
working_revision_position :: proc(
	working: ^Working_Revision,
	byte_offset: Byte_Offset,
) -> (position: Working_Position, ok: bool, failure: Failure_Context) {
	state, state_failure := working_revision_live_state(working)
	if state_failure.code != .None {
		return {}, false, state_failure
	}
	offset := u64(byte_offset)
	root_stats, stats_ok := text.root_stats(state.working_root)
	assert(stats_ok)
	total_bytes := u64(root_stats.summary.byte_count)
	if offset > total_bytes {
		return {}, false, Failure_Context {
			code = .Out_Of_Range,
			buffer_id = state.buffer_id,
			revision = state.base_revision,
			start = byte_offset,
			end = byte_offset,
			limit = total_bytes,
			actual = offset,
		}
	}
	if !root_offset_is_boundary(state.working_root, offset) {
		return {}, false, Failure_Context {
			code = .Mid_Encoding_Offset,
			buffer_id = state.buffer_id,
			revision = state.base_revision,
			start = byte_offset,
			end = byte_offset,
			actual = offset,
		}
	}
	return Working_Position {
		buffer_id = state.buffer_id,
		base_revision = state.base_revision,
		working_revision_id = state.working_revision_id,
		generation = state.generation,
		byte_offset = byte_offset,
	}, true, {}
}

/*
working_revision_inspect copies private text into caller-owned storage.
It never exposes rope-owned memory and canonical readers continue to see the confirmed root.
*/
working_revision_inspect :: proc(
	working: ^Working_Revision,
	start, end: Working_Position,
	destination: []byte,
) -> (copied: u64, ok: bool, failure: Failure_Context) {
	state, state_failure := working_revision_live_state(working)
	if state_failure.code != .None {
		return 0, false, state_failure
	}
	positions_ok, position_failure := working_positions_validate(state, start, end)
	if !positions_ok {
		return 0, false, position_failure
	}
	start_value := u64(start.byte_offset)
	end_value := u64(end.byte_offset)
	if start_value > end_value {
		return 0, false, working_failure(state, start.byte_offset, end.byte_offset, .Reversed_Range)
	}
	root_stats, stats_ok := text.root_stats(state.working_root)
	assert(stats_ok)
	total_bytes := u64(root_stats.summary.byte_count)
	if end_value > total_bytes {
		return 0, false, Failure_Context {
			code = .Out_Of_Range,
			buffer_id = state.buffer_id,
			revision = state.base_revision,
			start = start.byte_offset,
			end = end.byte_offset,
			limit = total_bytes,
			actual = end_value,
		}
	}
	result_bytes := end_value - start_value
	if result_bytes > state.owner.limits.inspection_bytes {
		return 0, false, Failure_Context {
			code = .Inspection_Limit,
			buffer_id = state.buffer_id,
			revision = state.base_revision,
			start = start.byte_offset,
			end = end.byte_offset,
			limit = state.owner.limits.inspection_bytes,
			actual = result_bytes,
		}
	}
	if result_bytes > u64(len(destination)) {
		return 0, false, Failure_Context {
			code = .Out_Of_Range,
			buffer_id = state.buffer_id,
			revision = state.base_revision,
			start = start.byte_offset,
			end = end.byte_offset,
			limit = u64(len(destination)),
			actual = result_bytes,
		}
	}
	copy_failure: text.Storage_Failure
	copied, copy_failure = text.root_copy_range(
		state.working_root,
		start_value,
		destination[:int(result_bytes)],
	)
	assert(copy_failure.code == .None)
	return copied, true, {}
}

/*
working_revision_splice applies one validated sequential edit to private state.
Success advances the private generation once; failure preserves both private and canonical text.
*/
working_revision_splice :: proc(
	working: ^Working_Revision,
	splice: Working_Splice,
	temporary_allocator: runtime.Allocator,
	cancelled := false,
) -> (ok: bool, failure: Failure_Context) {
	state, state_failure := working_revision_live_state(working)
	if state_failure.code != .None {
		return false, state_failure
	}
	if cancelled {
		return false, working_failure(state, splice.start.byte_offset, splice.end.byte_offset, .Cancelled)
	}
	if temporary_allocator.procedure == nil {
		return false, Failure_Context {
			code = .Temporary_Memory_Limit,
			buffer_id = state.buffer_id,
			revision = state.base_revision,
			limit = state.owner.limits.temporary_bytes,
		}
	}
	positions_ok, position_failure := working_positions_validate(state, splice.start, splice.end)
	if !positions_ok {
		return false, position_failure
	}
	start := u64(splice.start.byte_offset)
	end := u64(splice.end.byte_offset)
	if start > end {
		return false, working_failure(state, splice.start.byte_offset, splice.end.byte_offset, .Reversed_Range)
	}
	root_stats, stats_ok := text.root_stats(state.working_root)
	assert(stats_ok)
	current_bytes := u64(root_stats.summary.byte_count)
	if end > current_bytes {
		return false, Failure_Context {
			code = .Out_Of_Range,
			buffer_id = state.buffer_id,
			revision = state.base_revision,
			start = splice.start.byte_offset,
			end = splice.end.byte_offset,
			limit = current_bytes,
			actual = end,
		}
	}
	if !root_offset_is_boundary(state.working_root, start) || !root_offset_is_boundary(state.working_root, end) {
		return false, working_failure(state, splice.start.byte_offset, splice.end.byte_offset, .Mid_Encoding_Offset)
	}
	if !utf8.valid_string(splice.replacement) {
		return false, working_failure(state, splice.start.byte_offset, splice.end.byte_offset, .Malformed_UTF8)
	}
	replacement_bytes := u64(len(splice.replacement))
	if replacement_bytes > state.owner.limits.replacement_bytes {
		return false, Failure_Context {
			code = .Replacement_Limit,
			buffer_id = state.buffer_id,
			revision = state.base_revision,
			start = splice.start.byte_offset,
			end = splice.end.byte_offset,
			limit = state.owner.limits.replacement_bytes,
			actual = replacement_bytes,
		}
	}
	result_bytes, result_ok := checked_add_u64(current_bytes - (end - start), replacement_bytes)
	if !result_ok || result_bytes > state.owner.limits.buffer_bytes {
		actual := result_bytes
		if !result_ok {
			actual = max(u64)
		}
		return false, Failure_Context {
			code = .Buffer_Limit,
			buffer_id = state.buffer_id,
			revision = state.base_revision,
			start = splice.start.byte_offset,
			end = splice.end.byte_offset,
			limit = state.owner.limits.buffer_bytes,
			actual = actual,
		}
	}

	_, reservation_failure := splice_reservation(
		state.owner,
		root_stats,
		result_bytes,
		end - start,
		replacement_bytes,
		0,
	)
	if reservation_failure.code != .None {
		reservation_failure.buffer_id = state.buffer_id
		reservation_failure.revision = state.base_revision
		reservation_failure.start = splice.start.byte_offset
		reservation_failure.end = splice.end.byte_offset
		return false, reservation_failure
	}

	prepared_root, prepare_failure := text.root_prepare_splice(
		state.working_root,
		start,
		end,
		splice.replacement,
		temporary_allocator,
		state.owner.limits.splice_nodes,
	)
	if prepare_failure.code != .None {
		failure = storage_failure_context(state.buffer_id, prepare_failure)
		failure.revision = state.base_revision
		failure.start = splice.start.byte_offset
		failure.end = splice.end.byte_offset
		return false, failure
	}
	prepared_stats, prepared_stats_ok := text.root_stats(prepared_root)
	assert(prepared_stats_ok)
	base_private, base_private_ok := checked_add_u64(prepared_stats.persistent_bytes, u64(size_of(Buffer_State)))
	total_private, total_ok := checked_add_u64(base_private, state.owner.private_bytes)
	if !base_private_ok || !total_ok || total_private > state.owner.limits.persistent_bytes {
		text.root_release(&prepared_root)
		actual := total_private
		if !base_private_ok || !total_ok {
			actual = max(u64)
		}
		return false, Failure_Context {
			code = .Persistent_Memory_Limit,
			buffer_id = state.buffer_id,
			revision = state.base_revision,
			start = splice.start.byte_offset,
			end = splice.end.byte_offset,
			limit = state.owner.limits.persistent_bytes,
			actual = actual,
		}
	}

	old_root := state.working_root
	state.working_root = prepared_root
	state.generation += 1
	text.root_release(&old_root)
	return true, {}
}

/*
working_revision_abort discards private state and releases its resources.
It consumes the handle without changing canonical text, revision, anchors, or records.
*/
working_revision_abort :: proc(
	working: ^Working_Revision,
) -> (ok: bool, failure: Failure_Context) {
	state, state_failure := working_revision_live_state(working)
	if state_failure.code != .None {
		return false, state_failure
	}
	state.phase = .Aborted
	working.state = nil
	owner := state.owner
	assert(owner.active_preparations == 1)
	owner.active_preparations = 0
	working_revision_release_compat_record(state)
	assert(owner.private_bytes >= u64(size_of(Working_Revision_State)))
	owner.private_bytes -= u64(size_of(Working_Revision_State))
	text.root_release(&state.working_root)
	buffer_id := state.buffer_id
	base_revision := state.base_revision
	allocator := state.allocator
	free(state, allocator)
	return true, Failure_Context {
		buffer_id = buffer_id,
		revision = base_revision,
	}
}

/*
working_revision_publish_reserved installs a fully validated private root.
The caller must validate normalized_splices and reserve every required resource first.
After entry this procedure does not return an expected failure or permit cancellation.
*/
working_revision_publish_reserved :: proc(
	working: ^Working_Revision,
	normalized_splices: []Working_Publication_Splice,
) -> Revision {
	state := working_revision_assert_publishable(working)
	assert(!state.has_compat_record)
	return working_revision_publish_root(working, normalized_splices, false)
}

@(private)
working_revision_publish_compat :: proc(working: ^Working_Revision) -> (Change_Set, Undo_Record) {
	state := working_revision_assert_publishable(working)
	assert(state.has_compat_record)
	owner := state.owner
	change := Working_Publication_Splice {
		start = state.compat_change_set.start,
		end = Byte_Offset(u64(state.compat_change_set.start) + state.compat_change_set.removed_bytes),
		inserted_bytes = u64(len(state.compat_change_set.replacement_text)),
	}
	_ = working_revision_publish_root(working, []Working_Publication_Splice{change}, true)
	return owner.committed_change_set, owner.committed_undo_record
}

@(private)
working_revision_publish_root :: proc(
	working: ^Working_Revision,
	normalized_splices: []Working_Publication_Splice,
	install_compat_record: bool,
) -> Revision {
	state := (^Working_Revision_State)(working.state)
	owner := state.owner
	assert(owner != nil)
	assert(state.phase == .Building)
	assert(owner.active_preparations == 1)
	assert(owner.revision == state.base_revision)
	assert(state.base_revision != Revision(max(u64)))

	old_root := owner.text_root
	old_inserted_text := owner.committed_undo_record.inserted_text
	old_removed_text := owner.committed_undo_record.removed_text
	old_record_bytes := buffer_committed_record_bytes(owner)
	state_bytes := u64(size_of(Working_Revision_State))
	compat_bytes := working_revision_compat_record_bytes(state)
	assert(owner.private_bytes >= state_bytes + compat_bytes + old_record_bytes)

	// No expected failure, allocation, callback, or cancellation is permitted
	// after the phase enters Publishing.
	state.phase = .Publishing
	owner.text_root = state.working_root
	state.working_root = {}
	owner.revision = Revision(u64(state.base_revision) + 1)
	delta: i64 = 0
	for change in normalized_splices {
		start := u64(change.start)
		end := u64(change.end)
		assert(start <= end)
		adjusted_start_value := i64(start) + delta
		adjusted_end_value := i64(end) + delta
		assert(adjusted_start_value >= 0 && adjusted_end_value >= adjusted_start_value)
		buffer_transform_anchors(
			owner,
			Byte_Offset(u64(adjusted_start_value)),
			Byte_Offset(u64(adjusted_end_value)),
			change.inserted_bytes,
		)
		delta += i64(change.inserted_bytes) - i64(end - start)
	}
	if install_compat_record {
		assert(state.compat_change_set.result_revision == owner.revision)
		owner.committed_change_set = state.compat_change_set
		owner.committed_undo_record = state.compat_undo_record
		owner.has_committed_record = true
		state.compat_change_set = {}
		state.compat_undo_record = {}
		state.has_compat_record = false
	} else {
		owner.committed_change_set = {}
		owner.committed_undo_record = {}
		owner.has_committed_record = false
	}
	owner.active_preparations = 0
	owner.private_bytes -= state_bytes + old_record_bytes
	state.phase = .Published
	working.state = nil
	result_revision := owner.revision
	allocator := state.allocator
	free(state, allocator)

	text.root_release(&old_root)
	if len(old_inserted_text) > 0 {
		delete(old_inserted_text, allocator)
	}
	if len(old_removed_text) > 0 {
		delete(old_removed_text, allocator)
	}
	return result_revision
}

@(private)
working_revision_attach_compat_record :: proc(
	working: ^Working_Revision,
	validated: Validated_Splice,
) -> (ok: bool, failure: Failure_Context) {
	state, state_failure := working_revision_live_state(working)
	if state_failure.code != .None {
		return false, state_failure
	}
	assert(!state.has_compat_record)
	inserted_text, inserted_error := clone_owned_string(validated.replacement, state.allocator)
	if inserted_error != nil {
		return false, Failure_Context {
			code = .Persistent_Memory_Limit,
			buffer_id = state.buffer_id,
			revision = state.base_revision,
			start = validated.start,
			end = validated.end,
			limit = state.owner.limits.persistent_bytes,
			actual = u64(len(validated.replacement)),
		}
	}
	removed_text, removed_error := copy_root_range_owned(
		state.owner.text_root,
		u64(validated.start),
		validated.reservation.removed_bytes,
		state.allocator,
	)
	if removed_error != nil {
		if len(inserted_text) > 0 {
			delete(inserted_text, state.allocator)
		}
		return false, Failure_Context {
			code = .Persistent_Memory_Limit,
			buffer_id = state.buffer_id,
			revision = state.base_revision,
			start = validated.start,
			end = validated.end,
			limit = state.owner.limits.persistent_bytes,
			actual = validated.reservation.removed_bytes,
		}
	}
	record_bytes := u64(len(inserted_text)) + u64(len(removed_text))
	state.owner.private_bytes += record_bytes
	result_revision := Revision(u64(state.base_revision) + 1)
	state.compat_change_set = Change_Set {
		buffer_id = state.buffer_id,
		base_revision = state.base_revision,
		result_revision = result_revision,
		start = validated.start,
		removed_bytes = validated.reservation.removed_bytes,
		replacement_text = inserted_text,
	}
	state.compat_undo_record = Undo_Record {
		buffer_id = state.buffer_id,
		base_revision = state.base_revision,
		result_revision = result_revision,
		start = validated.start,
		removed_text = removed_text,
		inserted_text = inserted_text,
	}
	state.has_compat_record = true
	return true, {}
}

@(private)
working_revision_assert_publishable :: proc(working: ^Working_Revision) -> ^Working_Revision_State {
	state, failure := working_revision_live_state(working)
	assert(failure.code == .None)
	assert(state.owner.revision == state.base_revision)
	return state
}

@(private)
working_revision_live_state :: proc(
	working: ^Working_Revision,
) -> (^Working_Revision_State, Failure_Context) {
	if !working_revision_is_valid(working) {
		return nil, Failure_Context{code = .Work_Limit}
	}
	state := (^Working_Revision_State)(working.state)
	if state.phase != .Building || state.owner == nil || state.owner.active_preparations != 1 ||
	   state.owner.buffer_id != state.buffer_id || state.owner.revision != state.base_revision {
		return nil, Failure_Context {
			code = .Stale_Revision,
			buffer_id = state.buffer_id,
			revision = state.base_revision,
		}
	}
	return state, {}
}

@(private)
working_positions_validate :: proc(
	state: ^Working_Revision_State,
	start, end: Working_Position,
) -> (bool, Failure_Context) {
	if start.buffer_id != state.buffer_id || end.buffer_id != state.buffer_id {
		return false, working_failure(state, start.byte_offset, end.byte_offset, .Wrong_Buffer)
	}
	if start.base_revision != state.base_revision || end.base_revision != state.base_revision {
		return false, working_failure(state, start.byte_offset, end.byte_offset, .Stale_Revision)
	}
	if start.working_revision_id != state.working_revision_id ||
	   end.working_revision_id != state.working_revision_id {
		return false, working_failure(state, start.byte_offset, end.byte_offset, .Wrong_Buffer)
	}
	if start.generation != end.generation || start.generation != state.generation {
		return false, working_failure(state, start.byte_offset, end.byte_offset, .Stale_Revision)
	}
	return true, {}
}

@(private)
root_offset_is_boundary :: proc(root: text.Root, offset: u64) -> bool {
	stats, stats_ok := text.root_stats(root)
	assert(stats_ok)
	if offset == 0 || offset == u64(stats.summary.byte_count) {
		return true
	}
	value: [1]byte
	_, copy_failure := text.root_copy_range(root, offset, value[:])
	assert(copy_failure.code == .None)
	return value[0] & 0xc0 != 0x80
}

@(private)
working_failure :: proc(
	state: ^Working_Revision_State,
	start, end: Byte_Offset,
	code: Failure_Code,
) -> Failure_Context {
	return Failure_Context {
		code = code,
		buffer_id = state.buffer_id,
		revision = state.base_revision,
		start = start,
		end = end,
	}
}

@(private)
working_revision_compat_record_bytes :: proc(state: ^Working_Revision_State) -> u64 {
	if !state.has_compat_record {
		return 0
	}
	return u64(len(state.compat_undo_record.inserted_text)) +
	       u64(len(state.compat_undo_record.removed_text))
}

@(private)
working_revision_release_compat_record :: proc(state: ^Working_Revision_State) {
	if !state.has_compat_record {
		return
	}
	owned_bytes := working_revision_compat_record_bytes(state)
	assert(state.owner.private_bytes >= owned_bytes)
	if len(state.compat_undo_record.inserted_text) > 0 {
		delete(state.compat_undo_record.inserted_text, state.allocator)
	}
	if len(state.compat_undo_record.removed_text) > 0 {
		delete(state.compat_undo_record.removed_text, state.allocator)
	}
	state.owner.private_bytes -= owned_bytes
	state.has_compat_record = false
	state.compat_change_set = {}
	state.compat_undo_record = {}
}
