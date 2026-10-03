// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package view

import "../editor"
import "base:runtime"

@(private)
Prepared_Logical_Edit_State :: struct {
	registry:          ^Registry,
	handle:            View_Handle,
	buffer:            ^editor.Buffer,
	buffer_id:         editor.Buffer_ID,
	base_revision:     editor.Revision,
	state_generation:  u64,
	selection_generation: u64,
	result_offset:     editor.Byte_Offset,
	desired_column:    u32,
	region:            Logical_Region_Result,
	mark:              Logical_Mark_Result,
	result_mark_offset: editor.Byte_Offset,
	selection_shape:    editor.Selection_Shape,
	rectangle_column_policy: editor.Rectangle_Column_Policy,
	reserved_mark:     editor.Anchor,
	has_reserved_mark: bool,
	allocator:         runtime.Allocator,
}

/* logical_edit_is_valid reports whether a prepared logical participant remains live. */
logical_edit_is_valid :: proc(prepared: ^Prepared_Logical_Edit) -> bool {
	return prepared != nil && prepared.state != nil
}

/*
logical_edit_prepare freezes one live view and owns a bounded post-text logical outcome.
The result point offset is validated by the transaction against its private working revision.
*/
logical_edit_prepare :: proc(
	registry: ^Registry,
	handle: View_Handle,
	request: Logical_Edit_Request,
	prepared: ^Prepared_Logical_Edit,
	reserved_mark: ^editor.Anchor = nil,
) -> (ok: bool, failure: Failure_Context) {
	assert(prepared != nil)
	if logical_edit_is_valid(prepared) {
		return false, view_failure(registry, handle, .Active_Preparation)
	}
	if (request.region != .Preserve && request.region != .Deactivate && request.region != .Activate) ||
	   (request.mark != .Preserve && request.mark != .Absent && request.mark != .Position) {
		return false, view_failure(registry, handle, .Invalid_Config)
	}
	slot, slot_failure := resolve(registry, handle)
	if slot_failure.code != .None {
		return false, slot_failure
	}
	if slot.active_preparation {
		return false, view_failure(registry, handle, .Active_Preparation)
	}
	if slot.state_generation == max(u64) {
		return false, generation_failure(registry, handle)
	}
	stats, stats_ok, stats_failure := editor.buffer_stats(slot.buffer)
	if !stats_ok {
		return false, editor_failure_context(registry, handle, stats_failure)
	}
	if request.buffer_id != slot.buffer_id || request.buffer_id != stats.buffer_id {
		return false, editor_failure_context(
			registry,
			handle,
			editor.Failure_Context {
				code = .Wrong_Buffer,
				buffer_id = request.buffer_id,
				revision = request.base_revision,
			},
		)
	}
	if request.base_revision != stats.revision {
		return false, editor_failure_context(
			registry,
			handle,
			editor.Failure_Context {
				code = .Stale_Revision,
				buffer_id = request.buffer_id,
				revision = request.base_revision,
			},
		)
	}
	data := registry_data(registry)
	assert(data != nil)
	selection, selection_ok, selection_failure := editor.buffer_selection_snapshot(slot.buffer)
	if !selection_ok {
		return false, editor_failure_context(registry, handle, selection_failure)
	}
	needs_reserved_mark := request.mark == .Position && !selection.mark.present
	if needs_reserved_mark {
		if reserved_mark == nil {
			return false, view_failure(registry, handle, .Invalid_Config)
		}
		_, reserved_ok, reserved_failure := editor.buffer_anchor_resolve(slot.buffer, reserved_mark^)
		if !reserved_ok {
			return false, editor_failure_context(registry, handle, reserved_failure)
		}
	} else if reserved_mark != nil && reserved_mark.buffer_id != editor.Buffer_ID(0) {
		return false, view_failure(registry, handle, .Invalid_Config)
	}
	state, allocation_error := new(Prepared_Logical_Edit_State, data.allocator)
	if allocation_error != nil {
		return false, view_failure(registry, handle, .Persistent_Memory_Limit)
	}
	state.registry = registry
	state.handle = handle
	state.buffer = slot.buffer
	state.buffer_id = request.buffer_id
	state.base_revision = request.base_revision
	state.state_generation = slot.state_generation
	state.selection_generation = selection.generation
	state.result_offset = request.result_point_offset
	state.desired_column = request.desired_display_column
	state.region = request.region
	state.mark = request.mark
	state.result_mark_offset = request.result_mark_offset
	state.selection_shape = request.selection_shape
	state.rectangle_column_policy = request.rectangle_column_policy
	if needs_reserved_mark {
		state.reserved_mark = reserved_mark^
		state.has_reserved_mark = true
		reserved_mark^ = {}
	}
	state.allocator = data.allocator
	slot.active_preparation = true
	data.storage_bytes += u64(size_of(Prepared_Logical_Edit_State))
	prepared.state = state
	return true, {}
}

/* logical_edit_validate verifies the frozen view and confirmed base before root readiness. */
logical_edit_validate :: proc(
	prepared: ^Prepared_Logical_Edit,
) -> (ok: bool, failure: Failure_Context) {
	state, state_failure := logical_edit_state(prepared)
	if state_failure.code != .None {
		return false, state_failure
	}
	slot, slot_failure := resolve(state.registry, state.handle)
	if slot_failure.code != .None {
		return false, slot_failure
	}
	if !slot.active_preparation || slot.state_generation != state.state_generation {
		return false, view_failure(state.registry, state.handle, .Active_Preparation)
	}
	stats, stats_ok, stats_failure := editor.buffer_stats(state.buffer)
	if !stats_ok {
		return false, editor_failure_context(state.registry, state.handle, stats_failure)
	}
	if stats.buffer_id != state.buffer_id || stats.revision != state.base_revision {
		code := editor.Failure_Code.Stale_Revision
		if stats.buffer_id != state.buffer_id {
			code = .Wrong_Buffer
		}
		return false, editor_failure_context(
			state.registry,
			state.handle,
			editor.Failure_Context {
				code = code,
				buffer_id = state.buffer_id,
				revision = state.base_revision,
			},
		)
	}
	selection, selection_ok, selection_failure := editor.buffer_selection_snapshot(state.buffer)
	if !selection_ok {
		return false, editor_failure_context(state.registry, state.handle, selection_failure)
	}
	if selection.generation != state.selection_generation {
		return false, view_failure(state.registry, state.handle, .Active_Preparation)
	}
	return true, {}
}

/* logical_edit_abort releases one frozen participant without changing view state. */
logical_edit_abort :: proc(
	prepared: ^Prepared_Logical_Edit,
) -> (ok: bool, failure: Failure_Context) {
	state, state_failure := logical_edit_state(prepared)
	if state_failure.code != .None {
		return false, state_failure
	}
	slot, slot_failure := resolve(state.registry, state.handle)
	if slot_failure.code == .None {
		assert(slot.active_preparation)
		slot.active_preparation = false
		if state.has_reserved_mark {
			released, _ := editor.buffer_anchor_release(state.buffer, &state.reserved_mark)
			assert(released)
			state.has_reserved_mark = false
		}
	}
	logical_edit_state_release(prepared, state)
	if slot_failure.code != .None {
		return false, slot_failure
	}
	return true, {}
}

/*
logical_edit_publish_reserved installs a validated result after its text root becomes confirmed.
It performs no allocation and returns no expected failure after publication begins.
*/
logical_edit_publish_reserved :: proc(
	prepared: ^Prepared_Logical_Edit,
	result_revision: editor.Revision,
) -> Logical_Commit_Result {
	state, state_failure := logical_edit_state(prepared)
	assert(state_failure.code == .None)
	slot, slot_failure := resolve(state.registry, state.handle)
	assert(slot_failure.code == .None)
	assert(slot.active_preparation && slot.state_generation == state.state_generation)
	assert(u64(state.base_revision) < max(u64))
	assert(result_revision == editor.Revision(u64(state.base_revision) + 1))
	stats, stats_ok, _ := editor.buffer_stats(state.buffer)
	assert(stats_ok && stats.buffer_id == state.buffer_id && stats.revision == result_revision)
	position, position_ok, _ := editor.buffer_position(state.buffer, state.result_offset)
	assert(position_ok)
	mark_position := editor.Position{}
	if state.mark == .Position {
		mark_position_ok: bool
		mark_position, mark_position_ok, _ = editor.buffer_position(
			state.buffer,
			state.result_mark_offset,
		)
		assert(mark_position_ok)
	}
	region := editor.Selection_Region_Action.Preserve
	if state.region == .Deactivate {
		region = .Deactivate
	} else if state.region == .Activate {
		region = .Activate
	}
	mark := editor.Selection_Mark_Result.Preserve
	if state.mark == .Absent {
		mark = .Absent
	} else if state.mark == .Position {
		mark = .Position
	}
	reserved_mark: ^editor.Anchor
	if state.has_reserved_mark {
		reserved_mark = &state.reserved_mark
	}
	published, publish_failure := editor.buffer_selection_publish_reserved(
		state.buffer,
		position,
		region,
		mark,
		mark_position,
		reserved_mark,
		state.selection_shape,
		state.rectangle_column_policy,
	)
	assert(published && publish_failure.code == .None)
	stored, stored_failure := editor.buffer_anchor_move(
		state.buffer,
		slot.stored_point,
		position,
	)
	assert(stored && stored_failure.code == .None)
	if state.has_reserved_mark && state.reserved_mark.buffer_id == editor.Buffer_ID(0) {
		state.has_reserved_mark = false
	}
	slot.desired_display_column = state.desired_column
	slot.state_generation += 1
	slot.active_preparation = false
	registry := state.registry
	handle := state.handle
	logical_edit_state_release(prepared, state)
	current, current_ok, _ := snapshot(registry, handle)
	assert(current_ok)
	return Logical_Commit_Result {
		present = true,
		view_id = current.view_id,
		view_generation = current.view_generation,
		state_generation = current.state_generation,
		buffer_id = current.buffer_id,
		result_revision = current.revision,
		point_position = current.point_position,
		mark = current.mark,
		region_active = current.region_active,
		selection_shape = current.selection_shape,
		rectangle_column_policy = current.rectangle_column_policy,
		desired_display_column = current.desired_display_column,
	}
}

@(private)
logical_edit_state :: proc(
	prepared: ^Prepared_Logical_Edit,
) -> (^Prepared_Logical_Edit_State, Failure_Context) {
	if !logical_edit_is_valid(prepared) {
		return nil, Failure_Context{code = .Active_Preparation}
	}
	return (^Prepared_Logical_Edit_State)(prepared.state), {}
}

@(private)
logical_edit_state_release :: proc(
	prepared: ^Prepared_Logical_Edit,
	state: ^Prepared_Logical_Edit_State,
) {
	data := registry_data(state.registry)
	assert(data != nil && data.storage_bytes >= u64(size_of(Prepared_Logical_Edit_State)))
	data.storage_bytes -= u64(size_of(Prepared_Logical_Edit_State))
	allocator := state.allocator
	prepared.state = nil
	free(state, allocator)
}
