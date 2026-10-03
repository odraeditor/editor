// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package editor

import "../text"
import "base:runtime"

@(private)
Buffer_State :: struct {
	buffer_id:              Buffer_ID,
	kind:                   Buffer_Kind,
	read_only:              bool,
	revision:               Revision,
	limits:                 Limits,
	allocator:              runtime.Allocator,
	text_root:              text.Root,
	active_preparations:    u32,
	next_working_revision_id: Working_Revision_ID,
	private_bytes:          u64,
	has_committed_record:   bool,
	committed_change_set:   Change_Set,
	committed_undo_record:  Undo_Record,
	anchor_slabs:           [MAX_ANCHOR_SLABS]^Anchor_Slab,
	anchor_slot_count:      u32,
	anchor_live_count:      u32,
	anchor_free_head:       u32,
	anchor_storage_bytes:   u64,
	selection_point:        Anchor,
	selection_mark:         Anchor,
	selection_mark_present: bool,
	selection_region_active: bool,
	selection_shape:       Selection_Shape,
	selection_rectangle_column_policy: Rectangle_Column_Policy,
	selection_generation:   u64,
}

/*
buffer_init creates a live buffer with revision zero and a private persistent rope.
It borrows the allocator procedures until buffer_close and leaves buffer unchanged on failure.
*/
buffer_init :: proc(
	buffer: ^Buffer,
	buffer_id: Buffer_ID,
	contents: string,
	allocators: Allocator_Set,
	limits := DEFAULT_LIMITS,
	kind := Buffer_Kind.Text,
) -> (ok: bool, failure: Failure_Context) {
	assert(buffer != nil)
	assert(buffer.state == nil, "buffer is already initialized")

	if buffer_id == Buffer_ID(0) {
		return false, Failure_Context {
			code = .Wrong_Buffer,
			buffer_id = buffer_id,
		}
	}
	if kind != .Text && kind != .Terminal_Projection {
		return false, Failure_Context {
			code = .Wrong_Buffer_Kind,
			buffer_id = buffer_id,
		}
	}
	if !limits_are_valid(limits) {
		return false, Failure_Context {
			code = .Work_Limit,
			buffer_id = buffer_id,
		}
	}
	if allocators.persistent.procedure == nil {
		return false, Failure_Context {
			code = .Persistent_Memory_Limit,
			buffer_id = buffer_id,
			limit = limits.persistent_bytes,
		}
	}
	if allocators.temporary.procedure == nil {
		return false, Failure_Context {
			code = .Temporary_Memory_Limit,
			buffer_id = buffer_id,
			limit = limits.temporary_bytes,
		}
	}

	state_bytes := u64(size_of(Buffer_State))
	if state_bytes >= limits.persistent_bytes {
		return false, Failure_Context {
			code = .Persistent_Memory_Limit,
			buffer_id = buffer_id,
			limit = limits.persistent_bytes,
			actual = state_bytes,
		}
	}

	state, state_error := new(Buffer_State, allocators.persistent)
	if state_error != nil {
		return false, Failure_Context {
			code = .Persistent_Memory_Limit,
			buffer_id = buffer_id,
			limit = limits.persistent_bytes,
			actual = state_bytes,
		}
	}

	storage_limits := text.Storage_Limits {
		text_bytes = limits.buffer_bytes,
		persistent_bytes = limits.persistent_bytes - state_bytes,
		temporary_bytes = limits.temporary_bytes,
		tree_levels = text.MAX_TREE_LEVELS,
		reclaim_step_nodes = limits.reclaim_step_nodes,
		reclaim_queue_nodes = limits.reclaim_queue_nodes,
	}
	root, storage_failure := text.root_build(
		contents,
		storage_limits,
		allocators.persistent,
		allocators.temporary,
	)
	if storage_failure.code != .None {
		free(state, allocators.persistent)
		return false, storage_failure_context(buffer_id, storage_failure)
	}

	state.buffer_id = buffer_id
	state.kind = kind
	state.revision = Revision(0)
	state.limits = limits
	state.allocator = allocators.persistent
	state.text_root = root
	state.next_working_revision_id = Working_Revision_ID(1)
	state.anchor_free_head = ANCHOR_FREE_NONE
	buffer.state = state
	origin, origin_ok, origin_failure := buffer_position(buffer, Byte_Offset(0))
	assert(origin_ok && origin_failure.code == .None)
	point, point_ok, point_failure := buffer_anchor_create(
		buffer,
		origin,
		.Right,
		.Collapse,
	)
	if !point_ok {
		closed, _ := buffer_close(buffer)
		assert(closed)
		return false, point_failure
	}
	state.selection_point = point
	state.selection_shape = .Linear
	state.selection_rectangle_column_policy = .Grapheme
	state.selection_generation = 1
	return true, {}
}

/*
buffer_close releases all storage owned by a live buffer and invalidates its handle.
It fails without closing while a prepared splice is outstanding.
*/
buffer_close :: proc(buffer: ^Buffer) -> (ok: bool, failure: Failure_Context) {
	assert(buffer != nil)
	if buffer.state == nil {
		return false, Failure_Context{code = .Closed_Buffer}
	}

	state := (^Buffer_State)(buffer.state)
	if state.active_preparations != 0 {
		return false, Failure_Context {
			code = .Work_Limit,
			buffer_id = state.buffer_id,
			revision = state.revision,
			limit = 0,
			actual = u64(state.active_preparations),
		}
	}
	buffer.state = nil
	buffer_id := state.buffer_id
	revision := state.revision
	allocator := state.allocator
	text.root_release(&state.text_root)
	buffer_release_committed_record(state)
	buffer_release_anchor_storage(state)
	free(state, allocator)
	return true, Failure_Context {
		buffer_id = buffer_id,
		revision = revision,
	}
}

@(private)
buffer_committed_record_bytes :: proc(state: ^Buffer_State) -> u64 {
	if !state.has_committed_record {
		return 0
	}
	return u64(len(state.committed_undo_record.inserted_text)) +
	       u64(len(state.committed_undo_record.removed_text))
}

@(private)
buffer_release_committed_record :: proc(state: ^Buffer_State) {
	if !state.has_committed_record {
		return
	}
	record_bytes := buffer_committed_record_bytes(state)
	assert(state.private_bytes >= record_bytes)
	if len(state.committed_undo_record.inserted_text) > 0 {
		delete(state.committed_undo_record.inserted_text, state.allocator)
	}
	if len(state.committed_undo_record.removed_text) > 0 {
		delete(state.committed_undo_record.removed_text, state.allocator)
	}
	state.private_bytes -= record_bytes
	state.has_committed_record = false
	state.committed_change_set = {}
	state.committed_undo_record = {}
}

/* buffer_is_live reports whether a buffer handle currently owns editor state. */
buffer_is_live :: proc(buffer: ^Buffer) -> bool {
	return buffer != nil && buffer.state != nil
}

/* buffer_read_only reports whether ordinary text mutation is currently disabled. */
buffer_read_only :: proc(buffer: ^Buffer) -> (read_only: bool, ok: bool, failure: Failure_Context) {
	state, state_failure := buffer_live_state(buffer)
	if state_failure.code != .None do return false, false, state_failure
	return state.kind != .Text || state.read_only, true, {}
}

/* buffer_read_only_set changes mutable policy only for an ordinary text buffer. */
buffer_read_only_set :: proc(
	buffer: ^Buffer,
	read_only: bool,
) -> (changed: bool, ok: bool, failure: Failure_Context) {
	state, state_failure := buffer_live_state(buffer)
	if state_failure.code != .None do return false, false, state_failure
	if state.kind != .Text {
		return false, false, Failure_Context {
			code = .Wrong_Buffer_Kind,
			buffer_id = state.buffer_id,
			revision = state.revision,
		}
	}
	changed = state.read_only != read_only
	state.read_only = read_only
	return changed, true, {}
}

/*
buffer_position validates an offset against the live buffer and current revision.
Successful positions are valid only while that revision remains canonical.
*/
buffer_position :: proc(
	buffer: ^Buffer,
	byte_offset: Byte_Offset,
) -> (position: Position, ok: bool, failure: Failure_Context) {
	state, state_failure := buffer_live_state(buffer)
	if state_failure.code != .None {
		return {}, false, state_failure
	}

	stats, stats_ok := text.root_stats(state.text_root)
	assert(stats_ok)
	offset := u64(byte_offset)
	total_bytes := u64(stats.summary.byte_count)
	if offset > total_bytes {
		return {}, false, Failure_Context {
			code = .Out_Of_Range,
			buffer_id = state.buffer_id,
			revision = state.revision,
			start = byte_offset,
			end = byte_offset,
			limit = total_bytes,
			actual = offset,
		}
	}

	if offset < total_bytes {
		value: [1]byte
		_, copy_failure := text.root_copy_range(state.text_root, offset, value[:])
		assert(copy_failure.code == .None)
		if value[0] & 0xc0 == 0x80 {
			return {}, false, Failure_Context {
				code = .Mid_Encoding_Offset,
				buffer_id = state.buffer_id,
				revision = state.revision,
				start = byte_offset,
				end = byte_offset,
				actual = offset,
			}
		}
	}

	position_ok: bool
	position, position_ok = position_make(state.buffer_id, state.revision, byte_offset)
	assert(position_ok)
	return position, true, {}
}

/*
buffer_inspect copies the half-open byte range [start, end) into caller-owned storage.
It performs no allocation and never returns a borrowed view into the rope.
*/
buffer_inspect :: proc(
	buffer: ^Buffer,
	start, end: Byte_Offset,
	destination: []byte,
) -> (copied: u64, ok: bool, failure: Failure_Context) {
	state, state_failure := buffer_live_state(buffer)
	if state_failure.code != .None {
		return 0, false, state_failure
	}

	start_value := u64(start)
	end_value := u64(end)
	if start_value > end_value {
		return 0, false, Failure_Context {
			code = .Reversed_Range,
			buffer_id = state.buffer_id,
			revision = state.revision,
			start = start,
			end = end,
		}
	}

	stats, stats_ok := text.root_stats(state.text_root)
	assert(stats_ok)
	total_bytes := u64(stats.summary.byte_count)
	if end_value > total_bytes {
		return 0, false, Failure_Context {
			code = .Out_Of_Range,
			buffer_id = state.buffer_id,
			revision = state.revision,
			start = start,
			end = end,
			limit = total_bytes,
			actual = end_value,
		}
	}

	result_bytes := end_value - start_value
	if result_bytes > state.limits.inspection_bytes {
		return 0, false, Failure_Context {
			code = .Inspection_Limit,
			buffer_id = state.buffer_id,
			revision = state.revision,
			start = start,
			end = end,
			limit = state.limits.inspection_bytes,
			actual = result_bytes,
		}
	}
	if result_bytes > u64(len(destination)) {
		return 0, false, Failure_Context {
			code = .Out_Of_Range,
			buffer_id = state.buffer_id,
			revision = state.revision,
			start = start,
			end = end,
			limit = u64(len(destination)),
			actual = result_bytes,
		}
	}

	copy_failure: text.Storage_Failure
	copied, copy_failure = text.root_copy_range(
		state.text_root,
		start_value,
		destination[:int(result_bytes)],
	)
	assert(copy_failure.code == .None)
	return copied, true, {}
}

/* buffer_line_at_position resolves the containing logical line in the current revision. */
buffer_line_at_position :: proc(
	buffer: ^Buffer,
	position: Position,
) -> (line: Buffer_Line, ok: bool, failure: Failure_Context) {
	state, state_failure := buffer_live_state(buffer)
	if state_failure.code != .None {
		return {}, false, state_failure
	}
	if position.buffer_id != state.buffer_id {
		return {}, false, Failure_Context {
			code = .Wrong_Buffer,
			buffer_id = state.buffer_id,
			revision = state.revision,
			start = position.byte_offset,
		}
	}
	if position.revision != state.revision {
		return {}, false, Failure_Context {
			code = .Stale_Revision,
			buffer_id = state.buffer_id,
			revision = state.revision,
			start = position.byte_offset,
			actual = u64(position.revision),
		}
	}
	location, located := text.root_line_at_offset(state.text_root, u64(position.byte_offset))
	if !located {
		stats, stats_ok := text.root_stats(state.text_root)
		assert(stats_ok)
		return {}, false, Failure_Context {
			code = .Out_Of_Range,
			buffer_id = state.buffer_id,
			revision = state.revision,
			start = position.byte_offset,
			limit = u64(stats.summary.byte_count),
			actual = u64(position.byte_offset),
		}
	}
	return Buffer_Line {
		buffer_id = state.buffer_id,
		revision = state.revision,
		line_index = location.line_index,
		start = Byte_Offset(location.start),
		content_end = Byte_Offset(location.content_end),
		next_start = Byte_Offset(location.next_start),
	}, true, {}
}

/* buffer_stats returns a bounded snapshot of the live buffer and rope accounting. */
buffer_stats :: proc(buffer: ^Buffer) -> (stats: Buffer_Stats, ok: bool, failure: Failure_Context) {
	state, state_failure := buffer_live_state(buffer)
	if state_failure.code != .None {
		return {}, false, state_failure
	}
	root_stats, root_ok := text.root_stats(state.text_root)
	assert(root_ok)
	return Buffer_Stats {
		buffer_id = state.buffer_id,
		kind = state.kind,
		read_only = state.kind != .Text || state.read_only,
		revision = state.revision,
		text_bytes = u64(root_stats.summary.byte_count),
		line_feed_count = u64(root_stats.summary.line_feed_count),
		tree_height = root_stats.height,
		node_count = root_stats.node_count,
		chunk_count = root_stats.chunk_count,
		persistent_bytes = root_stats.persistent_bytes + u64(size_of(Buffer_State)) + state.private_bytes,
		pending_reclamation = root_stats.pending_reclamation,
	}, true, {}
}

@(private)
buffer_live_state :: proc(buffer: ^Buffer) -> (^Buffer_State, Failure_Context) {
	if buffer == nil || buffer.state == nil {
		return nil, Failure_Context{code = .Closed_Buffer}
	}
	return (^Buffer_State)(buffer.state), {}
}

@(private)
storage_failure_context :: proc(
	buffer_id: Buffer_ID,
	storage_failure: text.Storage_Failure,
) -> Failure_Context {
	code := Failure_Code.Work_Limit
	switch storage_failure.code {
	case .Malformed_UTF8:
		code = .Malformed_UTF8
	case .Text_Limit:
		code = .Buffer_Limit
	case .Persistent_Memory_Limit:
		code = .Persistent_Memory_Limit
	case .Temporary_Memory_Limit:
		code = .Temporary_Memory_Limit
	case .Tree_Height_Limit, .Reclaim_Queue_Limit, .Work_Limit, .Invalid_Limits:
		code = .Work_Limit
	case .Reference_Count_Overflow:
		code = .Work_Limit
	case .Range_Error:
		code = .Out_Of_Range
	case .None:
		code = .None
	}
	return Failure_Context {
		code = code,
		buffer_id = buffer_id,
		limit = storage_failure.limit,
		actual = storage_failure.actual,
	}
}
