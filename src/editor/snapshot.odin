// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package editor

import "../text"

@(private)
SNAPSHOT_STORE_INDEX :: 0
@(private)
SNAPSHOT_NODE_INDEX :: 1
@(private)
SNAPSHOT_BUFFER_ID_INDEX :: 2
@(private)
SNAPSHOT_REVISION_INDEX :: 3
@(private)
SNAPSHOT_TEXT_BYTES_INDEX :: 4

/*
buffer_snapshot_open retains the current immutable rope revision without copying text.
The supplied snapshot must be empty. It remains valid independently of later buffer edits
and buffer_close, provided the buffer's persistent allocator remains live until release.
*/
buffer_snapshot_open :: proc(
	buffer: ^Buffer,
	snapshot: ^Buffer_Snapshot,
) -> (ok: bool, failure: Failure_Context) {
	assert(snapshot != nil)
	if buffer_snapshot_is_live(snapshot) {
		return false, Failure_Context{code = .Work_Limit}
	}
	state, state_failure := buffer_live_state(buffer)
	if state_failure.code != .None {
		return false, state_failure
	}
	root_stats, stats_ok := text.root_stats(state.text_root)
	assert(stats_ok)
	retained, retain_failure := text.root_retain(state.text_root)
	if retain_failure.code != .None {
		return false, storage_failure_context(state.buffer_id, retain_failure)
	}

	snapshot^[SNAPSHOT_STORE_INDEX] = retained[0]
	snapshot^[SNAPSHOT_NODE_INDEX] = retained[1]
	snapshot^[SNAPSHOT_BUFFER_ID_INDEX] = uintptr(state.buffer_id)
	snapshot^[SNAPSHOT_REVISION_INDEX] = uintptr(state.revision)
	snapshot^[SNAPSHOT_TEXT_BYTES_INDEX] = uintptr(root_stats.summary.byte_count)
	return true, {}
}

/* buffer_snapshot_is_live reports whether a snapshot currently retains one rope revision. */
buffer_snapshot_is_live :: proc(snapshot: ^Buffer_Snapshot) -> bool {
	return snapshot != nil &&
	       snapshot^[SNAPSHOT_STORE_INDEX] != 0 &&
	       snapshot^[SNAPSHOT_NODE_INDEX] != 0
}

/* buffer_snapshot_stats reports the immutable identity and shared storage of a live snapshot. */
buffer_snapshot_stats :: proc(
	snapshot: ^Buffer_Snapshot,
) -> (stats: Buffer_Snapshot_Stats, ok: bool, failure: Failure_Context) {
	root, live := buffer_snapshot_root(snapshot)
	if !live {
		return {}, false, Failure_Context{code = .Closed_Buffer}
	}
	root_stats, stats_ok := text.root_stats(root)
	assert(stats_ok)
	return Buffer_Snapshot_Stats {
		buffer_id = Buffer_ID(snapshot^[SNAPSHOT_BUFFER_ID_INDEX]),
		revision = Revision(snapshot^[SNAPSHOT_REVISION_INDEX]),
		text_bytes = u64(snapshot^[SNAPSHOT_TEXT_BYTES_INDEX]),
		shared_persistent_bytes = root_stats.persistent_bytes,
		pending_reclamation = root_stats.pending_reclamation,
	}, true, {}
}

/*
buffer_snapshot_read copies at most len(destination) bytes from start without allocation.
Reading at EOF succeeds with zero bytes; a start beyond EOF is rejected.
*/
buffer_snapshot_read :: proc(
	snapshot: ^Buffer_Snapshot,
	start: Byte_Offset,
	destination: []byte,
) -> (copied: u64, ok: bool, failure: Failure_Context) {
	root, live := buffer_snapshot_root(snapshot)
	if !live {
		return 0, false, Failure_Context{code = .Closed_Buffer}
	}
	buffer_id := Buffer_ID(snapshot^[SNAPSHOT_BUFFER_ID_INDEX])
	revision := Revision(snapshot^[SNAPSHOT_REVISION_INDEX])
	text_bytes := u64(snapshot^[SNAPSHOT_TEXT_BYTES_INDEX])
	offset := u64(start)
	if offset > text_bytes {
		return 0, false, Failure_Context {
			code = .Out_Of_Range,
			buffer_id = buffer_id,
			revision = revision,
			start = start,
			limit = text_bytes,
			actual = offset,
		}
	}
	take := min(u64(len(destination)), text_bytes - offset)
	if take == 0 {
		return 0, true, {}
	}
	copy_failure: text.Storage_Failure
	copied, copy_failure = text.root_copy_range(root, offset, destination[:int(take)])
	if copy_failure.code != .None {
		return copied, false, storage_failure_context(buffer_id, copy_failure)
	}
	return copied, true, {}
}

/*
buffer_snapshot_is_current compares a live snapshot with a live buffer.
A stale revision is a successful false result; closed handles are explicit failures.
*/
buffer_snapshot_is_current :: proc(
	buffer: ^Buffer,
	snapshot: ^Buffer_Snapshot,
) -> (current: bool, ok: bool, failure: Failure_Context) {
	if !buffer_snapshot_is_live(snapshot) {
		return false, false, Failure_Context{code = .Closed_Buffer}
	}
	state, state_failure := buffer_live_state(buffer)
	if state_failure.code != .None {
		return false, false, state_failure
	}
	return state.buffer_id == Buffer_ID(snapshot^[SNAPSHOT_BUFFER_ID_INDEX]) &&
	       state.revision == Revision(snapshot^[SNAPSHOT_REVISION_INDEX]), true, {}
}

/* buffer_snapshot_close releases the retained root and invalidates the snapshot handle. */
buffer_snapshot_close :: proc(
	snapshot: ^Buffer_Snapshot,
) -> (ok: bool, failure: Failure_Context) {
	root, live := buffer_snapshot_root(snapshot)
	if !live {
		return false, Failure_Context{code = .Closed_Buffer}
	}
	buffer_id := Buffer_ID(snapshot^[SNAPSHOT_BUFFER_ID_INDEX])
	revision := Revision(snapshot^[SNAPSHOT_REVISION_INDEX])
	text.root_release(&root)
	snapshot^ = {}
	return true, Failure_Context{buffer_id = buffer_id, revision = revision}
}

@(private)
buffer_snapshot_root :: proc(snapshot: ^Buffer_Snapshot) -> (root: text.Root, live: bool) {
	if !buffer_snapshot_is_live(snapshot) {
		return {}, false
	}
	return text.Root {
		snapshot^[SNAPSHOT_STORE_INDEX],
		snapshot^[SNAPSHOT_NODE_INDEX],
	}, true
}
