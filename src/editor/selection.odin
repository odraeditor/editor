// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package editor

/* buffer_selection_snapshot resolves canonical selection against the current revision. */
buffer_selection_snapshot :: proc(
	buffer: ^Buffer,
) -> (snapshot: Selection_Snapshot, ok: bool, failure: Failure_Context) {
	state, state_failure := buffer_live_state(buffer)
	if state_failure.code != .None {
		return {}, false, state_failure
	}
	point, point_ok, point_failure := buffer_anchor_resolve(buffer, state.selection_point)
	if !point_ok {
		return {}, false, point_failure
	}
	mark: Selection_Mark_Snapshot
	if state.selection_mark_present {
		position, mark_ok, mark_failure := buffer_anchor_resolve(buffer, state.selection_mark)
		if !mark_ok {
			return {}, false, mark_failure
		}
		mark = Selection_Mark_Snapshot{present = true, position = position}
	}
	assert(!state.selection_region_active || mark.present)
	return Selection_Snapshot {
		buffer_id = state.buffer_id,
		revision = state.revision,
		generation = state.selection_generation,
		point_position = point,
		mark = mark,
		region_active = state.selection_region_active,
		shape = state.selection_shape,
		rectangle_column_policy = state.selection_rectangle_column_policy,
	}, true, {}
}

/* buffer_selection_set_point moves canonical point without changing mark or activation. */
buffer_selection_set_point :: proc(
	buffer: ^Buffer,
	position: Position,
) -> (ok: bool, failure: Failure_Context) {
	state, ready_failure := buffer_selection_mutation_state(buffer)
	if ready_failure.code != .None {
		return false, ready_failure
	}
	moved, move_failure := buffer_anchor_move(buffer, state.selection_point, position)
	if !moved {
		return false, move_failure
	}
	state.selection_generation += 1
	return true, {}
}

/* buffer_selection_move publishes point and the requested activation transition atomically. */
buffer_selection_move :: proc(
	buffer: ^Buffer,
	position: Position,
	action := Selection_Region_Action.Deactivate,
) -> (ok: bool, failure: Failure_Context) {
	if action != .Preserve && action != .Deactivate && action != .Activate {
		return false, buffer_selection_failure(buffer, .Work_Limit)
	}
	state, ready_failure := buffer_selection_mutation_state(buffer)
	if ready_failure.code != .None {
		return false, ready_failure
	}
	created_mark := false
	if action == .Activate && !state.selection_mark_present {
		point, point_ok, point_failure := buffer_anchor_resolve(buffer, state.selection_point)
		if !point_ok {
			return false, point_failure
		}
		mark, created, create_failure := buffer_anchor_create(
			buffer,
			point,
			.Left,
			.Collapse,
		)
		if !created {
			return false, create_failure
		}
		state.selection_mark = mark
		state.selection_mark_present = true
		created_mark = true
	}
	moved, move_failure := buffer_anchor_move(buffer, state.selection_point, position)
	if !moved {
		if created_mark {
			released, _ := buffer_anchor_release(buffer, &state.selection_mark)
			assert(released)
			state.selection_mark_present = false
		}
		return false, move_failure
	}
	switch action {
	case .Activate:
		state.selection_region_active = true
		state.selection_shape = .Linear
		state.selection_rectangle_column_policy = .Grapheme
	case .Deactivate:
		state.selection_region_active = false
		state.selection_shape = .Linear
		state.selection_rectangle_column_policy = .Grapheme
	case .Preserve:
	case .Invalid:
		unreachable()
	}
	state.selection_generation += 1
	return true, {}
}

/* buffer_selection_set_mark creates or moves canonical mark and selects activation. */
buffer_selection_set_mark :: proc(
	buffer: ^Buffer,
	position: Position,
	activate := true,
	shape := Selection_Shape.Linear,
	column_policy := Rectangle_Column_Policy.Grapheme,
) -> (ok: bool, failure: Failure_Context) {
	if (shape != .Linear && shape != .Rectangle) || column_policy != .Grapheme {
		return false, buffer_selection_failure(buffer, .Work_Limit)
	}
	state, ready_failure := buffer_selection_mutation_state(buffer)
	if ready_failure.code != .None {
		return false, ready_failure
	}
	if state.selection_mark_present {
		moved, move_failure := buffer_anchor_move(buffer, state.selection_mark, position)
		if !moved {
			return false, move_failure
		}
	} else {
		mark, created, create_failure := buffer_anchor_create(
			buffer,
			position,
			.Left,
			.Collapse,
		)
		if !created {
			return false, create_failure
		}
		state.selection_mark = mark
		state.selection_mark_present = true
	}
	state.selection_region_active = activate
	state.selection_shape = shape if activate else .Linear
	state.selection_rectangle_column_policy = column_policy
	state.selection_generation += 1
	return true, {}
}

/* buffer_selection_set_shape changes only the active canonical region's projection shape. */
buffer_selection_set_shape :: proc(
	buffer: ^Buffer,
	shape: Selection_Shape,
	column_policy := Rectangle_Column_Policy.Grapheme,
) -> (ok: bool, failure: Failure_Context) {
	if (shape != .Linear && shape != .Rectangle) || column_policy != .Grapheme {
		return false, buffer_selection_failure(buffer, .Work_Limit)
	}
	state, state_failure := buffer_live_state(buffer)
	if state_failure.code != .None do return false, state_failure
	if !state.selection_region_active || !state.selection_mark_present {
		return false, buffer_selection_failure(buffer, .Missing_Mark)
	}
	if state.selection_shape == shape &&
	   state.selection_rectangle_column_policy == column_policy {
		return true, {}
	}
	ready_failure: Failure_Context
	state, ready_failure = buffer_selection_mutation_state(buffer)
	if ready_failure.code != .None do return false, ready_failure
	state.selection_shape = shape
	state.selection_rectangle_column_policy = column_policy
	state.selection_generation += 1
	return true, {}
}

/* buffer_selection_set_region_active changes activation without moving endpoints. */
buffer_selection_set_region_active :: proc(
	buffer: ^Buffer,
	active: bool,
) -> (ok: bool, failure: Failure_Context) {
	state, state_failure := buffer_live_state(buffer)
	if state_failure.code != .None {
		return false, state_failure
	}
	if active && !state.selection_mark_present {
		return false, buffer_selection_failure(buffer, .Missing_Mark)
	}
	if state.selection_region_active == active {
		return true, {}
	}
	ready_failure: Failure_Context
	state, ready_failure = buffer_selection_mutation_state(buffer)
	if ready_failure.code != .None {
		return false, ready_failure
	}
	state.selection_region_active = active
	if !active {
		state.selection_shape = .Linear
		state.selection_rectangle_column_policy = .Grapheme
	}
	state.selection_generation += 1
	return true, {}
}

/* buffer_selection_exchange swaps canonical point and mark and activates the region. */
buffer_selection_exchange :: proc(buffer: ^Buffer) -> (ok: bool, failure: Failure_Context) {
	state, state_failure := buffer_live_state(buffer)
	if state_failure.code != .None {
		return false, state_failure
	}
	if !state.selection_mark_present {
		return false, buffer_selection_failure(buffer, .Missing_Mark)
	}
	ready_failure: Failure_Context
	state, ready_failure = buffer_selection_mutation_state(buffer)
	if ready_failure.code != .None {
		return false, ready_failure
	}
	point, point_ok, point_failure := buffer_anchor_resolve(buffer, state.selection_point)
	if !point_ok {
		return false, point_failure
	}
	mark, mark_ok, mark_failure := buffer_anchor_resolve(buffer, state.selection_mark)
	if !mark_ok {
		return false, mark_failure
	}
	point_moved, point_move_failure := buffer_anchor_move(buffer, state.selection_point, mark)
	assert(point_moved && point_move_failure.code == .None)
	mark_moved, mark_move_failure := buffer_anchor_move(buffer, state.selection_mark, point)
	assert(mark_moved && mark_move_failure.code == .None)
	state.selection_region_active = true
	state.selection_generation += 1
	return true, {}
}

/* buffer_selection_clear_mark releases canonical mark and deactivates the region. */
buffer_selection_clear_mark :: proc(buffer: ^Buffer) -> (ok: bool, failure: Failure_Context) {
	state, state_failure := buffer_live_state(buffer)
	if state_failure.code != .None {
		return false, state_failure
	}
	if !state.selection_mark_present {
		return true, {}
	}
	ready_failure: Failure_Context
	state, ready_failure = buffer_selection_mutation_state(buffer)
	if ready_failure.code != .None {
		return false, ready_failure
	}
	released, release_failure := buffer_anchor_release(buffer, &state.selection_mark)
	if !released {
		return false, release_failure
	}
	state.selection_mark_present = false
	state.selection_region_active = false
	state.selection_shape = .Linear
	state.selection_rectangle_column_policy = .Grapheme
	state.selection_generation += 1
	return true, {}
}

/*
buffer_selection_publish_reserved installs a post-edit selection without allocation.
The caller supplies a reserved mark only when Position must create canonical mark.
*/
buffer_selection_publish_reserved :: proc(
	buffer: ^Buffer,
	point: Position,
	region: Selection_Region_Action,
	mark: Selection_Mark_Result,
	mark_position: Position,
	reserved_mark: ^Anchor = nil,
	shape := Selection_Shape.Linear,
	column_policy := Rectangle_Column_Policy.Grapheme,
) -> (ok: bool, failure: Failure_Context) {
	if (region != .Preserve && region != .Deactivate && region != .Activate) ||
	   (mark != .Preserve && mark != .Absent && mark != .Position) ||
	   (region == .Activate &&
	    ((shape != .Linear && shape != .Rectangle) || column_policy != .Grapheme)) {
		return false, buffer_selection_failure(buffer, .Work_Limit)
	}
	state, ready_failure := buffer_selection_mutation_state(buffer)
	if ready_failure.code != .None {
		return false, ready_failure
	}
	needs_reserved_mark := mark == .Position && !state.selection_mark_present
	if needs_reserved_mark {
		if reserved_mark == nil {
			return false, buffer_selection_failure(buffer, .Invalid_Anchor)
		}
		_, reserved_ok, reserved_failure := buffer_anchor_resolve(buffer, reserved_mark^)
		if !reserved_ok {
			return false, reserved_failure
		}
	} else if reserved_mark != nil && reserved_mark.buffer_id != Buffer_ID(0) {
		return false, buffer_selection_failure(buffer, .Invalid_Anchor)
	}
	point_moved, point_failure := buffer_anchor_move(buffer, state.selection_point, point)
	if !point_moved {
		return false, point_failure
	}
	if mark == .Absent && state.selection_mark_present {
		released, release_failure := buffer_anchor_release(buffer, &state.selection_mark)
		assert(released && release_failure.code == .None)
		state.selection_mark_present = false
	} else if mark == .Position {
		if state.selection_mark_present {
			mark_moved, mark_failure := buffer_anchor_move(
				buffer,
				state.selection_mark,
				mark_position,
			)
			assert(mark_moved && mark_failure.code == .None)
		} else {
			state.selection_mark = reserved_mark^
			state.selection_mark_present = true
			reserved_mark^ = {}
			mark_moved, mark_failure := buffer_anchor_move(
				buffer,
				state.selection_mark,
				mark_position,
			)
			assert(mark_moved && mark_failure.code == .None)
		}
	}
	if region == .Deactivate {
		state.selection_region_active = false
		state.selection_shape = .Linear
		state.selection_rectangle_column_policy = .Grapheme
	} else if region == .Activate {
		assert(state.selection_mark_present)
		state.selection_region_active = true
		state.selection_shape = shape
		state.selection_rectangle_column_policy = column_policy
	}
	state.selection_generation += 1
	return true, {}
}

@(private)
buffer_selection_mutation_state :: proc(
	buffer: ^Buffer,
) -> (state: ^Buffer_State, failure: Failure_Context) {
	state, failure = buffer_live_state(buffer)
	if failure.code != .None {
		return nil, failure
	}
	if state.selection_generation == max(u64) {
		return nil, buffer_selection_failure(buffer, .Selection_Generation_Limit)
	}
	if state.active_preparations != 0 {
		return nil, Failure_Context {
			code = .Work_Limit,
			buffer_id = state.buffer_id,
			revision = state.revision,
			limit = 0,
			actual = u64(state.active_preparations),
		}
	}
	return state, {}
}

@(private)
buffer_selection_failure :: proc(buffer: ^Buffer, code: Failure_Code) -> Failure_Context {
	state, state_failure := buffer_live_state(buffer)
	if state_failure.code != .None {
		return state_failure
	}
	return Failure_Context {
		code = code,
		buffer_id = state.buffer_id,
		revision = state.revision,
	}
}
