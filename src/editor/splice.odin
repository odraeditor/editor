// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package editor

import "../text"
import "base:runtime"
import "core:unicode/utf8"

@(private)
ROPE_NODE_RESERVATION_BYTES :: u64(256)
@(private)
ROPE_CHUNK_RESERVATION_BYTES :: u64(4_160)
@(private)
MIN_UTF8_CHUNK_PAYLOAD :: text.LEAF_MAX_BYTES - 3

/*
buffer_validate_splice checks identity, revision, UTF-8 boundaries, and all configured bounds.
It borrows splice.replacement and does not allocate or mutate canonical state.
*/
buffer_validate_splice :: proc(
	buffer: ^Buffer,
	splice: Splice,
	cancelled := false,
) -> (validated: Validated_Splice, ok: bool, failure: Failure_Context) {
	state, state_failure := buffer_live_state(buffer)
	if state_failure.code != .None {
		return {}, false, state_failure
	}
	if state.kind != .Text || state.read_only {
		return {}, false, Failure_Context {
			code = .Read_Only_Buffer,
			buffer_id = state.buffer_id,
			revision = state.revision,
		}
	}
	if cancelled {
		return {}, false, splice_failure(state, splice, .Cancelled)
	}
	if splice.start.buffer_id != state.buffer_id || splice.end.buffer_id != state.buffer_id {
		return {}, false, splice_failure(state, splice, .Wrong_Buffer)
	}
	if splice.start.revision != splice.end.revision {
		return {}, false, splice_failure(state, splice, .Mismatched_Revision)
	}
	if splice.start.revision != state.revision {
		return {}, false, splice_failure(state, splice, .Stale_Revision)
	}
	if state.revision == Revision(max(u64)) {
		return {}, false, splice_failure(state, splice, .Work_Limit)
	}

	start := u64(splice.start.byte_offset)
	end := u64(splice.end.byte_offset)
	if start > end {
		return {}, false, splice_failure(state, splice, .Reversed_Range)
	}

	root_stats, stats_ok := text.root_stats(state.text_root)
	assert(stats_ok)
	current_bytes := u64(root_stats.summary.byte_count)
	if end > current_bytes {
		return {}, false, Failure_Context {
			code = .Out_Of_Range,
			buffer_id = state.buffer_id,
			revision = state.revision,
			start = splice.start.byte_offset,
			end = splice.end.byte_offset,
			limit = current_bytes,
			actual = end,
		}
	}

	if !buffer_offset_is_boundary(state, start) {
		return {}, false, Failure_Context {
			code = .Mid_Encoding_Offset,
			buffer_id = state.buffer_id,
			revision = state.revision,
			start = splice.start.byte_offset,
			end = splice.end.byte_offset,
			actual = start,
		}
	}
	if !buffer_offset_is_boundary(state, end) {
		return {}, false, Failure_Context {
			code = .Mid_Encoding_Offset,
			buffer_id = state.buffer_id,
			revision = state.revision,
			start = splice.start.byte_offset,
			end = splice.end.byte_offset,
			actual = end,
		}
	}
	if !utf8.valid_string(splice.replacement) {
		return {}, false, splice_failure(state, splice, .Malformed_UTF8)
	}

	replacement_bytes := u64(len(splice.replacement))
	if replacement_bytes > state.limits.replacement_bytes {
		return {}, false, Failure_Context {
			code = .Replacement_Limit,
			buffer_id = state.buffer_id,
			revision = state.revision,
			start = splice.start.byte_offset,
			end = splice.end.byte_offset,
			limit = state.limits.replacement_bytes,
			actual = replacement_bytes,
		}
	}

	removed_bytes := end - start
	base_after_removal := current_bytes - removed_bytes
	result_bytes, result_ok := checked_add_u64(base_after_removal, replacement_bytes)
	if !result_ok || result_bytes > state.limits.buffer_bytes {
		actual := result_bytes
		if !result_ok {
			actual = max(u64)
		}
		return {}, false, Failure_Context {
			code = .Buffer_Limit,
			buffer_id = state.buffer_id,
			revision = state.revision,
			start = splice.start.byte_offset,
			end = splice.end.byte_offset,
			limit = state.limits.buffer_bytes,
			actual = actual,
		}
	}

	undo_bytes, undo_ok := checked_add_u64(removed_bytes, replacement_bytes)
	if !undo_ok || undo_bytes > state.limits.undo_bytes {
		actual := undo_bytes
		if !undo_ok {
			actual = max(u64)
		}
		return {}, false, Failure_Context {
			code = .Undo_Memory_Limit,
			buffer_id = state.buffer_id,
			revision = state.revision,
			start = splice.start.byte_offset,
			end = splice.end.byte_offset,
			limit = state.limits.undo_bytes,
			actual = actual,
		}
	}

	reservation, reservation_failure := splice_reservation(
		state,
		root_stats,
		result_bytes,
		removed_bytes,
		replacement_bytes,
		undo_bytes,
	)
	if reservation_failure.code != .None {
		reservation_failure.buffer_id = state.buffer_id
		reservation_failure.revision = state.revision
		reservation_failure.start = splice.start.byte_offset
		reservation_failure.end = splice.end.byte_offset
		return {}, false, reservation_failure
	}

	return Validated_Splice {
		buffer_id = state.buffer_id,
		base_revision = state.revision,
		start = splice.start.byte_offset,
		end = splice.end.byte_offset,
		replacement = splice.replacement,
		reservation = reservation,
	}, true, {}
}

/*
buffer_prepare_splice builds an unpublished candidate root and owned change records.
The returned handle owns persistent resources until abort or publication consumes it.
Only one preparation may exist for a buffer, and canonical state is unchanged on failure.
*/
@(private)
buffer_prepare_splice :: proc(
	buffer: ^Buffer,
	splice: Splice,
	temporary_allocator: runtime.Allocator,
	cancelled := false,
) -> (prepared: Prepared_Splice, ok: bool, failure: Failure_Context) {
	validated, validation_ok, validation_failure := buffer_validate_splice(buffer, splice, cancelled)
	if !validation_ok {
		return {}, false, validation_failure
	}
	working, working_ok, working_failure := buffer_working_revision_open(buffer)
	if !working_ok {
		return {}, false, working_failure
	}
	start, start_ok, start_failure := working_revision_position(&working, validated.start)
	if !start_ok {
		working_revision_abort(&working)
		return {}, false, start_failure
	}
	end, end_ok, end_failure := working_revision_position(&working, validated.end)
	if !end_ok {
		working_revision_abort(&working)
		return {}, false, end_failure
	}
	applied, apply_failure := working_revision_splice(
		&working,
		Working_Splice {
			start = start,
			end = end,
			replacement = validated.replacement,
		},
		temporary_allocator,
	)
	if !applied {
		working_revision_abort(&working)
		return {}, false, apply_failure
	}
	record_ok, record_failure := working_revision_attach_compat_record(&working, validated)
	if !record_ok {
		working_revision_abort(&working)
		return {}, false, record_failure
	}
	prepared.state = working.state
	working.state = nil
	return prepared, true, {}
}

/* prepared_splice_is_valid reports whether a prepared handle still owns a candidate splice. */
@(private)
prepared_splice_is_valid :: proc(prepared: ^Prepared_Splice) -> bool {
	return prepared != nil && prepared.state != nil
}

/*
prepared_splice_abort discards an unpublished candidate and releases all resources it owns.
Success consumes and invalidates the handle without changing canonical buffer state.
*/
@(private)
prepared_splice_abort :: proc(
	prepared: ^Prepared_Splice,
) -> (ok: bool, failure: Failure_Context) {
	if !prepared_splice_is_valid(prepared) {
		return false, Failure_Context{code = .Work_Limit}
	}
	working := Working_Revision{state = prepared.state}
	prepared.state = nil
	return working_revision_abort(&working)
}

/*
buffer_splice validates, prepares, and atomically publishes one replacement.
On success it advances the revision exactly once; on failure canonical state is unchanged.
Returned text views are buffer-owned and expire at the next successful splice or close.
*/
buffer_splice :: proc(
	buffer: ^Buffer,
	splice: Splice,
	temporary_allocator: runtime.Allocator,
	cancelled := false,
) -> (
	change_set: Change_Set,
	undo_record: Undo_Record,
	ok: bool,
	failure: Failure_Context,
) {
	prepared, prepared_ok, prepare_failure := buffer_prepare_splice(
		buffer,
		splice,
		temporary_allocator,
		cancelled,
	)
	if !prepared_ok {
		return {}, {}, false, prepare_failure
	}
	return prepared_splice_publish(&prepared)
}

@(private)
prepared_splice_publish :: proc(
	prepared: ^Prepared_Splice,
) -> (
	change_set: Change_Set,
	undo_record: Undo_Record,
	ok: bool,
	failure: Failure_Context,
) {
	if !prepared_splice_is_valid(prepared) {
		return {}, {}, false, Failure_Context{code = .Work_Limit}
	}
	working := Working_Revision{state = prepared.state}
	prepared.state = nil
	change_set, undo_record = working_revision_publish_compat(&working)
	return change_set, undo_record, true, Failure_Context {
		buffer_id = change_set.buffer_id,
		revision = change_set.result_revision,
	}
}

/*
prepared_splice_change_set returns the candidate change description without publishing it.
The returned text view is owned by the prepared handle and expires when it is aborted.
*/
@(private)
prepared_splice_change_set :: proc(
	prepared: ^Prepared_Splice,
) -> (change_set: Change_Set, ok: bool, failure: Failure_Context) {
	state, state_failure := prepared_splice_live_state(prepared)
	if state_failure.code != .None {
		return {}, false, state_failure
	}
	return state.compat_change_set, true, {}
}

/*
prepared_splice_undo_record returns candidate undo data without publishing it.
The returned text views are owned by the prepared handle and expire when it is aborted.
*/
@(private)
prepared_splice_undo_record :: proc(
	prepared: ^Prepared_Splice,
) -> (undo_record: Undo_Record, ok: bool, failure: Failure_Context) {
	state, state_failure := prepared_splice_live_state(prepared)
	if state_failure.code != .None {
		return {}, false, state_failure
	}
	return state.compat_undo_record, true, {}
}

/*
prepared_splice_inspect copies a range from the unpublished candidate into caller storage.
It does not expose rope-owned text and does not change either candidate or canonical state.
*/
@(private)
prepared_splice_inspect :: proc(
	prepared: ^Prepared_Splice,
	start, end: Byte_Offset,
	destination: []byte,
) -> (copied: u64, ok: bool, failure: Failure_Context) {
	if !prepared_splice_is_valid(prepared) {
		return 0, false, Failure_Context{code = .Work_Limit}
	}
	working := Working_Revision{state = prepared.state}
	start_position, start_ok, start_failure := working_revision_position(&working, start)
	if !start_ok {
		return 0, false, start_failure
	}
	end_position, end_ok, end_failure := working_revision_position(&working, end)
	if !end_ok {
		return 0, false, end_failure
	}
	return working_revision_inspect(&working, start_position, end_position, destination)
}

@(private)
prepared_splice_live_state :: proc(
	prepared: ^Prepared_Splice,
) -> (^Working_Revision_State, Failure_Context) {
	working := Working_Revision{}
	if prepared != nil {
		working.state = prepared.state
	}
	return working_revision_live_state(&working)
}

@(private)
clone_owned_string :: proc(
	contents: string,
	allocator: runtime.Allocator,
) -> (owned: string, error: runtime.Allocator_Error) {
	if len(contents) == 0 {
		return "", nil
	}
	bytes, allocation_error := make([]byte, len(contents), allocator)
	if allocation_error != nil {
		return "", allocation_error
	}
	copy(bytes, contents)
	return string(bytes), nil
}

@(private)
copy_root_range_owned :: proc(
	root: text.Root,
	start, length: u64,
	allocator: runtime.Allocator,
) -> (owned: string, error: runtime.Allocator_Error) {
	if length == 0 {
		return "", nil
	}
	if length > u64(max(int)) {
		return "", .Out_Of_Memory
	}
	bytes, allocation_error := make([]byte, int(length), allocator)
	if allocation_error != nil {
		return "", allocation_error
	}
	_, copy_failure := text.root_copy_range(root, start, bytes)
	if copy_failure.code != .None {
		delete(bytes, allocator)
		panic("validated removed range could not be copied")
	}
	return string(bytes), nil
}

@(private)
splice_reservation :: proc(
	state: ^Buffer_State,
	root_stats: text.Root_Stats,
	result_bytes, removed_bytes, replacement_bytes, undo_bytes: u64,
) -> (reservation: Splice_Reservation, failure: Failure_Context) {
	replacement_chunks := divide_round_up_u64(replacement_bytes, u64(MIN_UTF8_CHUNK_PAYLOAD))
	boundary_chunks := u64(2)
	new_chunks, chunks_ok := checked_add_u64(replacement_chunks, boundary_chunks)
	if !chunks_ok {
		return {}, Failure_Context{code = .Persistent_Memory_Limit, actual = max(u64)}
	}

	result_chunks, result_chunks_ok := checked_add_u64(root_stats.chunk_count, new_chunks)
	if !result_chunks_ok {
		return {}, Failure_Context{code = .Work_Limit, actual = max(u64)}
	}
	internal_nodes, internal_ok := estimate_internal_nodes(result_chunks)
	if !internal_ok {
		return {}, Failure_Context{code = .Work_Limit, actual = max(u64)}
	}

	created_nodes, created_ok := checked_add_u64(new_chunks, internal_nodes)
	node_work, work_ok := checked_add_u64(root_stats.node_count, created_nodes)
	if !created_ok || !work_ok || node_work > state.limits.splice_nodes {
		actual := node_work
		if !created_ok || !work_ok {
			actual = max(u64)
		}
		return {}, Failure_Context {
			code = .Work_Limit,
			limit = state.limits.splice_nodes,
			actual = actual,
		}
	}

	pointer_count, pointer_count_ok := checked_add_u64(root_stats.node_count, result_chunks)
	parent_count := divide_round_up_u64(result_chunks, u64(text.INTERNAL_MAX_CHILDREN))
	parent_ok: bool
	pointer_count, parent_ok = checked_add_u64(pointer_count, parent_count)
	temporary_bytes, temporary_ok := checked_mul_u64(pointer_count, u64(size_of(rawptr)))
	if !pointer_count_ok || !parent_ok || !temporary_ok || temporary_bytes > state.limits.temporary_bytes {
		actual := temporary_bytes
		if !pointer_count_ok || !parent_ok || !temporary_ok {
			actual = max(u64)
		}
		return {}, Failure_Context {
			code = .Temporary_Memory_Limit,
			limit = state.limits.temporary_bytes,
			actual = actual,
		}
	}

	chunk_bytes, chunk_bytes_ok := checked_mul_u64(new_chunks, ROPE_CHUNK_RESERVATION_BYTES)
	node_bytes, node_bytes_ok := checked_mul_u64(internal_nodes, ROPE_NODE_RESERVATION_BYTES)
	storage_bytes, storage_ok := checked_add_u64(chunk_bytes, node_bytes)
	record_bytes, record_ok := checked_add_u64(undo_bytes, u64(size_of(Working_Revision_State)))
	persistent_bytes, persistent_ok := checked_add_u64(storage_bytes, record_bytes)
	current_bytes, current_ok := checked_add_u64(root_stats.persistent_bytes, u64(size_of(Buffer_State)))
	reserved_total, total_ok := checked_add_u64(current_bytes, persistent_bytes)
	if !chunk_bytes_ok || !node_bytes_ok || !storage_ok || !record_ok || !persistent_ok || !current_ok || !total_ok ||
	   reserved_total > state.limits.persistent_bytes {
		actual := reserved_total
		if !chunk_bytes_ok || !node_bytes_ok || !storage_ok || !record_ok || !persistent_ok || !current_ok || !total_ok {
			actual = max(u64)
		}
		return {}, Failure_Context {
			code = .Persistent_Memory_Limit,
			limit = state.limits.persistent_bytes,
			actual = actual,
		}
	}

	return Splice_Reservation {
		result_bytes = result_bytes,
		removed_bytes = removed_bytes,
		undo_bytes = undo_bytes,
		persistent_bytes = persistent_bytes,
		temporary_bytes = temporary_bytes,
		node_work = node_work,
	}, {}
}

@(private)
buffer_offset_is_boundary :: proc(state: ^Buffer_State, offset: u64) -> bool {
	stats, stats_ok := text.root_stats(state.text_root)
	assert(stats_ok)
	if offset == 0 || offset == u64(stats.summary.byte_count) {
		return true
	}
	value: [1]byte
	_, copy_failure := text.root_copy_range(state.text_root, offset, value[:])
	assert(copy_failure.code == .None)
	return value[0] & 0xc0 != 0x80
}

@(private)
splice_failure :: proc(
	state: ^Buffer_State,
	splice: Splice,
	code: Failure_Code,
) -> Failure_Context {
	return Failure_Context {
		code = code,
		buffer_id = state.buffer_id,
		revision = state.revision,
		start = splice.start.byte_offset,
		end = splice.end.byte_offset,
	}
}

@(private)
estimate_internal_nodes :: proc(leaf_count: u64) -> (u64, bool) {
	if leaf_count == 0 {
		return 0, true
	}
	total := u64(0)
	level_count := leaf_count
	for level_count > 1 {
		level_count = divide_round_up_u64(level_count, u64(text.INTERNAL_MAX_CHILDREN))
		ok: bool
		total, ok = checked_add_u64(total, level_count)
		if !ok {
			return 0, false
		}
	}
	return total, true
}

@(private)
checked_add_u64 :: proc(left, right: u64) -> (u64, bool) {
	if right > max(u64) - left {
		return 0, false
	}
	return left + right, true
}

@(private)
checked_mul_u64 :: proc(left, right: u64) -> (u64, bool) {
	if left != 0 && right > max(u64) / left {
		return 0, false
	}
	return left * right, true
}

@(private)
divide_round_up_u64 :: proc(value, divisor: u64) -> u64 {
	assert(divisor > 0)
	return value / divisor + (1 if value % divisor != 0 else 0)
}
