// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package editor

import "../text"

@(private)
ANCHOR_SLAB_CAPACITY :: u32(1_024)
@(private)
MAX_ANCHOR_SLABS :: int((MAX_ANCHORS + ANCHOR_SLAB_CAPACITY - 1) / ANCHOR_SLAB_CAPACITY)
@(private)
ANCHOR_FREE_NONE :: max(u32)

@(private)
Anchor_Slot :: struct {
	byte_offset:     Byte_Offset,
	generation:      u32,
	next_free:       u32,
	affinity:        Anchor_Affinity,
	deletion_policy: Anchor_Deletion_Policy,
	live:            bool,
}

@(private)
Anchor_Slab :: struct {
	slots: [ANCHOR_SLAB_CAPACITY]Anchor_Slot,
}

/*
buffer_anchor_create admits one persistent location at a current-revision position.
The buffer owns its storage; callers own only the checked handle and must release it.
*/
buffer_anchor_create :: proc(
	buffer: ^Buffer,
	position: Position,
	affinity: Anchor_Affinity,
	deletion_policy: Anchor_Deletion_Policy,
) -> (anchor: Anchor, ok: bool, failure: Failure_Context) {
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
		}
	}
	_, position_ok, position_failure := buffer_position(buffer, position.byte_offset)
	if !position_ok {
		return {}, false, position_failure
	}
	if affinity != .Left && affinity != .Right {
		return {}, false, anchor_failure(state, .Invalid_Anchor)
	}
	if deletion_policy != .Collapse && deletion_policy != .Invalidate {
		return {}, false, anchor_failure(state, .Invalid_Anchor)
	}
	if state.active_preparations != 0 {
		return {}, false, Failure_Context {
			code = .Work_Limit,
			buffer_id = state.buffer_id,
			revision = state.revision,
			limit = 0,
			actual = u64(state.active_preparations),
		}
	}
	if state.anchor_live_count >= state.limits.anchors {
		return {}, false, Failure_Context {
			code = .Anchor_Limit,
			buffer_id = state.buffer_id,
			revision = state.revision,
			limit = u64(state.limits.anchors),
			actual = u64(state.anchor_live_count) + 1,
		}
	}

	slot_index: u32
	if state.anchor_free_head != ANCHOR_FREE_NONE {
		slot_index = state.anchor_free_head
		slot := buffer_anchor_slot(state, slot_index)
		assert(slot != nil && !slot.live && slot.generation != 0)
		state.anchor_free_head = slot.next_free
	} else {
		if state.anchor_slot_count >= state.limits.anchors {
			return {}, false, Failure_Context {
				code = .Anchor_Limit,
				buffer_id = state.buffer_id,
				revision = state.revision,
				limit = u64(state.limits.anchors),
				actual = u64(state.anchor_slot_count) + 1,
			}
		}
		slot_index = state.anchor_slot_count
		if slot_index % ANCHOR_SLAB_CAPACITY == 0 {
			allocated, allocation_failure := buffer_allocate_anchor_slab(state)
			if !allocated {
				return {}, false, allocation_failure
			}
		}
		state.anchor_slot_count += 1
	}

	slot := buffer_anchor_slot(state, slot_index)
	assert(slot != nil && !slot.live)
	if slot.generation == 0 {
		slot.generation = 1
	}
	slot.byte_offset = position.byte_offset
	slot.affinity = affinity
	slot.deletion_policy = deletion_policy
	slot.next_free = ANCHOR_FREE_NONE
	slot.live = true
	state.anchor_live_count += 1
	return Anchor {
		buffer_id = state.buffer_id,
		slot = slot_index,
		generation = slot.generation,
	}, true, {}
}

/* buffer_anchor_resolve returns the anchor as a position in the current revision. */
buffer_anchor_resolve :: proc(
	buffer: ^Buffer,
	anchor: Anchor,
) -> (position: Position, ok: bool, failure: Failure_Context) {
	state, state_failure := buffer_live_state(buffer)
	if state_failure.code != .None {
		return {}, false, state_failure
	}
	slot, slot_failure := buffer_checked_anchor_slot(state, anchor)
	if slot_failure.code != .None {
		return {}, false, slot_failure
	}
	position_ok: bool
	position, position_ok = position_make(state.buffer_id, state.revision, slot.byte_offset)
	assert(position_ok)
	return position, true, {}
}

/* buffer_anchor_move changes one live anchor to a current checked text boundary. */
buffer_anchor_move :: proc(
	buffer: ^Buffer,
	anchor: Anchor,
	position: Position,
) -> (ok: bool, failure: Failure_Context) {
	state, state_failure := buffer_live_state(buffer)
	if state_failure.code != .None {
		return false, state_failure
	}
	slot, slot_failure := buffer_checked_anchor_slot(state, anchor)
	if slot_failure.code != .None {
		return false, slot_failure
	}
	if position.buffer_id != state.buffer_id {
		return false, Failure_Context {
			code = .Wrong_Buffer,
			buffer_id = state.buffer_id,
			revision = state.revision,
			start = position.byte_offset,
		}
	}
	if position.revision != state.revision {
		return false, Failure_Context {
			code = .Stale_Revision,
			buffer_id = state.buffer_id,
			revision = state.revision,
			start = position.byte_offset,
		}
	}
	_, position_ok, position_failure := buffer_position(buffer, position.byte_offset)
	if !position_ok {
		return false, position_failure
	}
	if state.active_preparations != 0 {
		return false, Failure_Context {
			code = .Work_Limit,
			buffer_id = state.buffer_id,
			revision = state.revision,
			limit = 0,
			actual = u64(state.active_preparations),
		}
	}
	slot.byte_offset = position.byte_offset
	return true, {}
}

/*
buffer_anchor_release releases one live anchor and invalidates the supplied handle.
Other copies of the handle become stale through its generation check.
*/
buffer_anchor_release :: proc(
	buffer: ^Buffer,
	anchor: ^Anchor,
) -> (ok: bool, failure: Failure_Context) {
	state, state_failure := buffer_live_state(buffer)
	if state_failure.code != .None {
		return false, state_failure
	}
	if anchor == nil {
		return false, anchor_failure(state, .Invalid_Anchor)
	}
	slot, slot_failure := buffer_checked_anchor_slot(state, anchor^)
	if slot_failure.code != .None {
		return false, slot_failure
	}
	if state.active_preparations != 0 {
		return false, Failure_Context {
			code = .Work_Limit,
			buffer_id = state.buffer_id,
			revision = state.revision,
			limit = 0,
			actual = u64(state.active_preparations),
		}
	}
	buffer_retire_anchor_slot(state, anchor.slot, slot)
	anchor^ = {}
	return true, Failure_Context {
		buffer_id = state.buffer_id,
		revision = state.revision,
	}
}

/* buffer_anchor_stats returns occupancy and exact slab storage for live anchors. */
buffer_anchor_stats :: proc(
	buffer: ^Buffer,
) -> (stats: Anchor_Stats, ok: bool, failure: Failure_Context) {
	state, state_failure := buffer_live_state(buffer)
	if state_failure.code != .None {
		return {}, false, state_failure
	}
	return Anchor_Stats {
		live_count = state.anchor_live_count,
		slot_count = state.anchor_slot_count,
		capacity = state.limits.anchors,
		storage_bytes = state.anchor_storage_bytes,
		slot_bytes = u64(size_of(Anchor_Slot)),
	}, true, {}
}

@(private)
buffer_allocate_anchor_slab :: proc(
	state: ^Buffer_State,
) -> (ok: bool, failure: Failure_Context) {
	slab_index := int(state.anchor_slot_count / ANCHOR_SLAB_CAPACITY)
	assert(slab_index >= 0 && slab_index < MAX_ANCHOR_SLABS)
	assert(state.anchor_slabs[slab_index] == nil)

	root_stats, root_ok := text.root_stats(state.text_root)
	assert(root_ok)
	slab_bytes := u64(size_of(Anchor_Slab))
	required, required_ok := checked_add_u64(
		root_stats.persistent_bytes + u64(size_of(Buffer_State)) + state.private_bytes,
		slab_bytes,
	)
	if !required_ok || required > state.limits.persistent_bytes {
		actual := required
		if !required_ok {
			actual = max(u64)
		}
		return false, Failure_Context {
			code = .Persistent_Memory_Limit,
			buffer_id = state.buffer_id,
			revision = state.revision,
			limit = state.limits.persistent_bytes,
			actual = actual,
		}
	}

	slab, allocation_error := new(Anchor_Slab, state.allocator)
	if allocation_error != nil {
		return false, Failure_Context {
			code = .Persistent_Memory_Limit,
			buffer_id = state.buffer_id,
			revision = state.revision,
			limit = state.limits.persistent_bytes,
			actual = required,
		}
	}
	state.anchor_slabs[slab_index] = slab
	state.anchor_storage_bytes += slab_bytes
	state.private_bytes += slab_bytes
	return true, {}
}

@(private)
buffer_anchor_slot :: proc(state: ^Buffer_State, slot_index: u32) -> ^Anchor_Slot {
	if slot_index >= state.anchor_slot_count && slot_index % ANCHOR_SLAB_CAPACITY != 0 {
		return nil
	}
	slab_index := int(slot_index / ANCHOR_SLAB_CAPACITY)
	if slab_index < 0 || slab_index >= MAX_ANCHOR_SLABS {
		return nil
	}
	slab := state.anchor_slabs[slab_index]
	if slab == nil {
		return nil
	}
	return &slab.slots[slot_index % ANCHOR_SLAB_CAPACITY]
}

@(private)
buffer_checked_anchor_slot :: proc(
	state: ^Buffer_State,
	anchor: Anchor,
) -> (^Anchor_Slot, Failure_Context) {
	if anchor.buffer_id != state.buffer_id {
		return nil, anchor_failure(state, .Wrong_Buffer)
	}
	if anchor.generation == 0 || anchor.slot >= state.anchor_slot_count {
		return nil, anchor_failure(state, .Invalid_Anchor)
	}
	slot := buffer_anchor_slot(state, anchor.slot)
	if slot == nil || !slot.live || slot.generation != anchor.generation {
		return nil, anchor_failure(state, .Invalid_Anchor)
	}
	return slot, {}
}

@(private)
buffer_retire_anchor_slot :: proc(
	state: ^Buffer_State,
	slot_index: u32,
	slot: ^Anchor_Slot,
) {
	assert(slot != nil && slot.live)
	assert(state.anchor_live_count > 0)
	slot.live = false
	slot.byte_offset = 0
	slot.affinity = .Invalid
	slot.deletion_policy = .Invalid
	state.anchor_live_count -= 1
	if slot.generation != max(u32) {
		slot.generation += 1
		slot.next_free = state.anchor_free_head
		state.anchor_free_head = slot_index
	} else {
		slot.next_free = ANCHOR_FREE_NONE
	}
}

@(private)
buffer_transform_anchors :: proc(
	state: ^Buffer_State,
	start, end: Byte_Offset,
	replacement_bytes: u64,
) {
	start_value := u64(start)
	end_value := u64(end)
	removed_bytes := end_value - start_value
	for slot_index in 0 ..< state.anchor_slot_count {
		slot := buffer_anchor_slot(state, slot_index)
		assert(slot != nil)
		if !slot.live {
			continue
		}
		offset := u64(slot.byte_offset)
		if offset < start_value {
			continue
		}
		if removed_bytes == 0 && offset == start_value {
			if slot.affinity == .Right {
				slot.byte_offset = Byte_Offset(start_value + replacement_bytes)
			}
			continue
		}
		if offset == start_value {
			if slot.affinity == .Right {
				slot.byte_offset = Byte_Offset(start_value + replacement_bytes)
			}
			continue
		}
		if offset < end_value {
			if slot.deletion_policy == .Invalidate {
				buffer_retire_anchor_slot(state, slot_index, slot)
			} else if slot.affinity == .Right {
				slot.byte_offset = Byte_Offset(start_value + replacement_bytes)
			} else {
				slot.byte_offset = start
			}
			continue
		}
		if offset == end_value {
			slot.byte_offset = Byte_Offset(start_value + replacement_bytes)
			continue
		}
		slot.byte_offset = Byte_Offset(offset - removed_bytes + replacement_bytes)
	}
}

@(private)
buffer_release_anchor_storage :: proc(state: ^Buffer_State) {
	for &slab in state.anchor_slabs {
		if slab != nil {
			free(slab, state.allocator)
			slab = nil
		}
	}
	assert(state.private_bytes >= state.anchor_storage_bytes)
	state.private_bytes -= state.anchor_storage_bytes
	state.anchor_storage_bytes = 0
	state.anchor_slot_count = 0
	state.anchor_live_count = 0
	state.anchor_free_head = ANCHOR_FREE_NONE
}

@(private)
anchor_failure :: proc(state: ^Buffer_State, code: Failure_Code) -> Failure_Context {
	return Failure_Context {
		code = code,
		buffer_id = state.buffer_id,
		revision = state.revision,
	}
}
