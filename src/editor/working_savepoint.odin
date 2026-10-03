// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package editor

import "../text"

@(private)
WORKING_SAVEPOINT_STORE_INDEX :: 0
@(private)
WORKING_SAVEPOINT_NODE_INDEX :: 1
@(private)
WORKING_SAVEPOINT_BUFFER_ID_INDEX :: 2
@(private)
WORKING_SAVEPOINT_BASE_REVISION_INDEX :: 3
@(private)
WORKING_SAVEPOINT_REVISION_ID_INDEX :: 4
@(private)
WORKING_SAVEPOINT_GENERATION_INDEX :: 5

/* working_revision_savepoint_is_live reports whether a savepoint retains one private root. */
working_revision_savepoint_is_live :: proc(savepoint: ^Working_Revision_Savepoint) -> bool {
	return savepoint != nil &&
	       savepoint^[WORKING_SAVEPOINT_STORE_INDEX] != 0 &&
	       savepoint^[WORKING_SAVEPOINT_NODE_INDEX] != 0
}

/*
working_revision_savepoint_open retains the current private root without copying text.
The supplied savepoint must be empty and remains owned independently until consumed.
*/
working_revision_savepoint_open :: proc(
	working: ^Working_Revision,
	savepoint: ^Working_Revision_Savepoint,
) -> (ok: bool, failure: Failure_Context) {
	assert(savepoint != nil)
	if working_revision_savepoint_is_live(savepoint) {
		return false, Failure_Context{code = .Work_Limit}
	}
	state, state_failure := working_revision_live_state(working)
	if state_failure.code != .None {
		return false, state_failure
	}
	retained, retain_failure := text.root_retain(state.working_root)
	if retain_failure.code != .None {
		return false, storage_failure_context(state.buffer_id, retain_failure)
	}
	savepoint^[WORKING_SAVEPOINT_STORE_INDEX] = retained[0]
	savepoint^[WORKING_SAVEPOINT_NODE_INDEX] = retained[1]
	savepoint^[WORKING_SAVEPOINT_BUFFER_ID_INDEX] = uintptr(state.buffer_id)
	savepoint^[WORKING_SAVEPOINT_BASE_REVISION_INDEX] = uintptr(state.base_revision)
	savepoint^[WORKING_SAVEPOINT_REVISION_ID_INDEX] = uintptr(state.working_revision_id)
	savepoint^[WORKING_SAVEPOINT_GENERATION_INDEX] = uintptr(state.generation)
	return true, {}
}

/*
working_revision_savepoint_restore consumes a matching savepoint and restores its private root.
Success advances the working generation once so positions from either branch cannot be reused.
*/
working_revision_savepoint_restore :: proc(
	working: ^Working_Revision,
	savepoint: ^Working_Revision_Savepoint,
) -> (ok: bool, failure: Failure_Context) {
	state, state_failure := working_revision_live_state(working)
	if state_failure.code != .None {
		return false, state_failure
	}
	saved_root, live := working_revision_savepoint_root(savepoint)
	if !live {
		return false, working_failure(state, 0, 0, .Work_Limit)
	}
	if Buffer_ID(savepoint^[WORKING_SAVEPOINT_BUFFER_ID_INDEX]) != state.buffer_id {
		return false, working_failure(state, 0, 0, .Wrong_Buffer)
	}
	if Revision(savepoint^[WORKING_SAVEPOINT_BASE_REVISION_INDEX]) != state.base_revision {
		return false, working_failure(state, 0, 0, .Stale_Revision)
	}
	if Working_Revision_ID(savepoint^[WORKING_SAVEPOINT_REVISION_ID_INDEX]) != state.working_revision_id {
		return false, working_failure(state, 0, 0, .Wrong_Buffer)
	}
	if state.generation == max(u64) {
		return false, working_failure(state, 0, 0, .Work_Limit)
	}
	old_root := state.working_root
	state.working_root = saved_root
	state.generation += 1
	savepoint^ = {}
	text.root_release(&old_root)
	return true, {}
}

/* working_revision_savepoint_discard consumes a retained private root without restoring it. */
working_revision_savepoint_discard :: proc(
	savepoint: ^Working_Revision_Savepoint,
) -> (ok: bool, failure: Failure_Context) {
	root, live := working_revision_savepoint_root(savepoint)
	if !live {
		return false, Failure_Context{code = .Work_Limit}
	}
	buffer_id := Buffer_ID(savepoint^[WORKING_SAVEPOINT_BUFFER_ID_INDEX])
	base_revision := Revision(savepoint^[WORKING_SAVEPOINT_BASE_REVISION_INDEX])
	text.root_release(&root)
	savepoint^ = {}
	return true, Failure_Context{buffer_id = buffer_id, revision = base_revision}
}

@(private)
working_revision_savepoint_root :: proc(
	savepoint: ^Working_Revision_Savepoint,
) -> (root: text.Root, live: bool) {
	if !working_revision_savepoint_is_live(savepoint) {
		return {}, false
	}
	return text.Root {
		savepoint^[WORKING_SAVEPOINT_STORE_INDEX],
		savepoint^[WORKING_SAVEPOINT_NODE_INDEX],
	}, true
}
