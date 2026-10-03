// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package display

import "../editor"
import "../view"
import "base:runtime"

@(private)
Projection_Cache_State :: struct {
	allocator:          runtime.Allocator,
	view_id:            view.View_ID,
	view_generation:    u32,
	buffer_id:          editor.Buffer_ID,
	buffer_revision:    editor.Revision,
	display_profile_id: Display_Profile_ID,
	unicode_version:    Unicode_Version,
	tab_width:          u16,
	logical_line:       Logical_Line_Index,
	checkpoints:        []Line_Checkpoint,
	checkpoint_count:   u32,
	storage_bytes:      u64,
	valid:              bool,
}

/* projection_cache_init binds bounded checkpoint storage to one exact editor view. */
projection_cache_init :: proc(
	cache: ^Projection_Cache,
	logical: view.Snapshot,
	profile: Display_Profile,
	allocator: runtime.Allocator,
	limits := DEFAULT_RESOURCE_LIMITS,
) -> (ok: bool, failure: Failure_Context) {
	assert(cache != nil)
	if cache.state != nil || cache.closed || logical.view_id == view.View_ID(0) ||
	   logical.view_generation == 0 || allocator.procedure == nil ||
	   !display_profile_is_valid(profile) ||
	   Display_Profile_ID(u64(logical.display_profile_id)) != profile.id ||
	   !resource_limits_are_valid(limits) || limits.checkpoints > MAX_CHECKPOINTS {
		return false, Failure_Context {
			code = .Invalid_Cache,
			buffer_id = logical.buffer_id,
			buffer_revision = logical.revision,
			display_profile_id = profile.id,
		}
	}
	state, state_error := new(Projection_Cache_State, allocator)
	if state_error != nil {
		return false, persistent_failure({}, u64(size_of(Projection_Cache_State)))
	}
	state.allocator = allocator
	checkpoints, checkpoint_error := make([]Line_Checkpoint, int(limits.checkpoints), allocator)
	if checkpoint_error != nil {
		free(state, allocator)
		return false, persistent_failure(
			{},
			u64(size_of(Projection_Cache_State)) +
			u64(limits.checkpoints) * u64(size_of(Line_Checkpoint)),
		)
	}
	state.view_id = logical.view_id
	state.view_generation = logical.view_generation
	state.checkpoints = checkpoints
	state.storage_bytes = u64(size_of(Projection_Cache_State)) +
	                      u64(limits.checkpoints) * u64(size_of(Line_Checkpoint))
	cache.state = state
	return true, {}
}

/* projection_cache_close releases one empty or populated view-owned checkpoint cache. */
projection_cache_close :: proc(
	cache: ^Projection_Cache,
) -> (ok: bool, failure: Failure_Context) {
	assert(cache != nil)
	state := projection_cache_state(cache)
	if state == nil {
		return false, Failure_Context{code = .Invalid_Cache}
	}
	allocator := state.allocator
	delete(state.checkpoints, allocator)
	free(state, allocator)
	cache.state = nil
	cache.closed = true
	return true, {}
}

/* projection_cache_stats returns bounded occupancy without exposing owned storage. */
projection_cache_stats :: proc(
	cache: ^Projection_Cache,
) -> (stats: Projection_Cache_Stats, ok: bool, failure: Failure_Context) {
	state := projection_cache_state(cache)
	if state == nil {
		return {}, false, Failure_Context{code = .Invalid_Cache}
	}
	return Projection_Cache_Stats {
		view_id = u64(state.view_id),
		view_generation = state.view_generation,
		buffer_id = state.buffer_id,
		buffer_revision = state.buffer_revision,
		logical_line = state.logical_line,
		checkpoint_count = state.checkpoint_count,
		capacity = u32(len(state.checkpoints)),
		storage_bytes = state.storage_bytes,
		valid = state.valid,
	}, true, {}
}

/* projection_cache_invalidate_line discards a matching revision-bound logical line. */
projection_cache_invalidate_line :: proc(
	cache: ^Projection_Cache,
	buffer_id: editor.Buffer_ID,
	revision: editor.Revision,
	logical_line: Logical_Line_Index,
) -> (invalidated: bool, failure: Failure_Context) {
	state := projection_cache_state(cache)
	if state == nil {
		return false, Failure_Context{code = .Invalid_Cache}
	}
	if state.valid && state.buffer_id == buffer_id && state.buffer_revision == revision &&
	   state.logical_line == logical_line {
		state.valid = false
		state.checkpoint_count = 0
		return true, {}
	}
	return false, {}
}

@(private)
projection_cache_state :: proc(cache: ^Projection_Cache) -> ^Projection_Cache_State {
	if cache == nil || cache.state == nil || cache.closed {
		return nil
	}
	return (^Projection_Cache_State)(cache.state)
}

@(private)
projection_cache_accepts :: proc(
	state: ^Projection_Cache_State,
	request: Projection_Request,
) -> bool {
	return state != nil && state.view_id == request.view.view_id &&
	       state.view_generation == request.view.view_generation
}

@(private)
projection_cache_key_matches :: proc(
	state: ^Projection_Cache_State,
	request: Projection_Request,
	line: editor.Buffer_Line,
) -> bool {
	return projection_cache_accepts(state, request) && state.valid &&
	       state.buffer_id == request.view.buffer_id &&
	       state.buffer_revision == request.view.revision &&
	       state.display_profile_id == request.profile.id &&
	       state.unicode_version == request.profile.unicode.version &&
	       state.tab_width == request.view.tab_width &&
	       state.logical_line == Logical_Line_Index(line.line_index)
}

@(private)
projection_cache_checkpoint :: proc(
	state: ^Projection_Cache_State,
	request: Projection_Request,
	line: editor.Buffer_Line,
	target_column: u32,
) -> (checkpoint: Line_Checkpoint, ok: bool) {
	if !projection_cache_key_matches(state, request, line) || state.checkpoint_count == 0 {
		return {}, false
	}
	low := 0
	high := int(state.checkpoint_count)
	for low < high {
		middle := low + (high - low) / 2
		if u32(state.checkpoints[middle].display_column) <= target_column {
			low = middle + 1
		} else {
			high = middle
		}
	}
	if low == 0 {
		return {}, false
	}
	return state.checkpoints[low - 1], true
}

@(private)
projection_cache_commit :: proc(
	state: ^Projection_Cache_State,
	request: Projection_Request,
	logical_line: Logical_Line_Index,
	checkpoints: []Line_Checkpoint,
) -> (ok: bool, failure: Failure_Context) {
	if !projection_cache_accepts(state, request) {
		return false, Failure_Context {
			code = .Wrong_View,
			buffer_id = request.view.buffer_id,
			buffer_revision = request.view.revision,
			snapshot_id = request.snapshot_id,
		}
	}
	key_matches := state.valid && state.buffer_id == request.view.buffer_id &&
	               state.buffer_revision == request.view.revision &&
	               state.display_profile_id == request.profile.id &&
	               state.unicode_version == request.profile.unicode.version &&
	               state.tab_width == request.view.tab_width &&
	               state.logical_line == logical_line
	if !key_matches {
		state.checkpoint_count = 0
		state.buffer_id = request.view.buffer_id
		state.buffer_revision = request.view.revision
		state.display_profile_id = request.profile.id
		state.unicode_version = request.profile.unicode.version
		state.tab_width = request.view.tab_width
		state.logical_line = logical_line
		state.valid = true
	}
	incoming_count: u32
	for checkpoint in checkpoints {
		if checkpoint.logical_line == logical_line {
			incoming_count += 1
		}
	}
	capacity := u32(len(state.checkpoints))
	if incoming_count > capacity || state.checkpoint_count + incoming_count > capacity {
		state.checkpoint_count = 0
	}
	skip_count: u32
	if incoming_count > capacity {
		skip_count = incoming_count - capacity
	}
	seen: u32
	for checkpoint in checkpoints {
		if checkpoint.logical_line != logical_line {
			continue
		}
		if seen < skip_count {
			seen += 1
			continue
		}
		inserted := projection_cache_insert(state, checkpoint)
		assert(inserted)
	}
	return true, {}
}

@(private)
projection_cache_insert :: proc(
	state: ^Projection_Cache_State,
	checkpoint: Line_Checkpoint,
) -> bool {
	low := 0
	high := int(state.checkpoint_count)
	for low < high {
		middle := low + (high - low) / 2
		current := state.checkpoints[middle]
		if current.source_byte_offset < checkpoint.source_byte_offset {
			low = middle + 1
		} else {
			high = middle
		}
	}
	if low < int(state.checkpoint_count) &&
	   state.checkpoints[low].source_byte_offset == checkpoint.source_byte_offset {
		state.checkpoints[low] = checkpoint
		return true
	}
	if state.checkpoint_count >= u32(len(state.checkpoints)) {
		return false
	}
	for index := int(state.checkpoint_count); index > low; index -= 1 {
		state.checkpoints[index] = state.checkpoints[index - 1]
	}
	state.checkpoints[low] = checkpoint
	state.checkpoint_count += 1
	return true
}
