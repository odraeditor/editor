// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package darek

/* instance_toggle_preview changes preview policy and invalidates older work. */
instance_toggle_preview :: proc(
	instance: ^Instance,
) -> (enabled, changed, ok: bool, failure: Failure_Context) {
	state := instance_state(instance)
	if state == nil {
		return false, false, false, instance_failure(instance, .Navigate, .Invalid_Instance)
	}
	if !instance_advance_task(state) {
		return false, false, false, state_failure(state, .Navigate, .Invalid_Generation)
	}
	state.preview_enabled = !state.preview_enabled
	state.preview_target = Node_ID(0)
	state.preview_task = state.task_generation
	return state.preview_enabled, true, true, {}
}

/* instance_preview_request issues the newest exact selected-file preview intent. */
instance_preview_request :: proc(
	instance: ^Instance,
) -> (request: Preview_Request, ok: bool, failure: Failure_Context) {
	state := instance_state(instance)
	if state == nil || !state.preview_enabled {
		return {}, false, instance_failure(instance, .Navigate, .Invalid_Instance)
	}
	index := instance_selected_index(state)
	if index < 0 {
		return {}, false, state_failure(state, .Navigate, .Node_Not_Found)
	}
	target := state.nodes[index]
	if target.kind != .File {
		return {}, false, state_failure(state, .Navigate, .Invalid_Node)
	}
	if !instance_advance_task(state) {
		return {}, false, state_failure(state, .Navigate, .Invalid_Generation)
	}
	state.preview_target = target.handle.id
	state.preview_task = state.task_generation
	return Preview_Request {
		instance_id = state.id,
		instance_generation = state.generation,
		node_generation = state.node_generation,
		selection_generation = state.selection_generation,
		task_generation = state.task_generation,
		target = target.handle,
		resource = target.resource,
		path = target.path,
	}, true, {}
}

/* instance_preview_request_validate rejects stale selection and task work. */
instance_preview_request_validate :: proc(
	instance: ^Instance,
	request: Preview_Request,
) -> (ok: bool, failure: Failure_Context) {
	state := instance_state(instance)
	if state == nil || !state.preview_enabled {
		return false, instance_failure(instance, .Navigate, .Invalid_Instance)
	}
	if request.instance_id != state.id || request.instance_generation != state.generation ||
	   request.node_generation != state.node_generation ||
	   request.selection_generation != state.selection_generation ||
	   request.task_generation != state.task_generation ||
	   request.target.id != state.preview_target {
		return false, state_failure(state, .Navigate, .Stale_Generation)
	}
	return true, {}
}

/* instance_toggle_file_follow changes file-follow policy and invalidates older work. */
instance_toggle_file_follow :: proc(
	instance: ^Instance,
) -> (enabled, changed, ok: bool, failure: Failure_Context) {
	state := instance_state(instance)
	if state == nil {
		return false, false, false, instance_failure(instance, .Navigate, .Invalid_Instance)
	}
	if !instance_advance_task(state) {
		return false, false, false, state_failure(state, .Navigate, .Invalid_Generation)
	}
	state.follow_enabled = !state.follow_enabled
	state.follow_observed = 0
	state.follow_task = state.task_generation
	return state.follow_enabled, true, true, {}
}

/* instance_follow_observe admits only the newest nonzero active-file generation. */
instance_follow_observe :: proc(
	instance: ^Instance,
	observed_generation: u64,
) -> (task: Task_Generation, accepted, ok: bool, failure: Failure_Context) {
	state := instance_state(instance)
	if state == nil || !state.follow_enabled || observed_generation == 0 {
		return 0, false, false, instance_failure(instance, .Navigate, .Invalid_Instance)
	}
	if observed_generation <= state.follow_observed {
		return state.follow_task, false, true, {}
	}
	if !instance_advance_task(state) {
		return 0, false, false, state_failure(state, .Navigate, .Invalid_Generation)
	}
	state.follow_observed = observed_generation
	state.follow_task = state.task_generation
	return state.follow_task, true, true, {}
}

@(private)
instance_advance_task :: proc(state: ^Instance_State) -> bool {
	if state == nil || state.task_generation == Task_Generation(max(u64)) do return false
	state.task_generation = Task_Generation(u64(state.task_generation) + 1)
	return true
}

@(private)
instance_advance_selection :: proc(state: ^Instance_State) -> bool {
	if state == nil || state.selection_generation == Selection_Generation(max(u64)) do return false
	state.selection_generation = Selection_Generation(u64(state.selection_generation) + 1)
	return true
}
