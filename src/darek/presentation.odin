// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package darek

/* instance_set_panel_side changes only Darek presentation policy. */
instance_set_panel_side :: proc(
	instance: ^Instance,
	side: Panel_Side,
) -> (changed, ok: bool, failure: Failure_Context) {
	state := instance_state(instance)
	if state == nil || side == .Invalid {
		return false, false, instance_failure(instance, .Visibility, .Invalid_Instance)
	}
	if state.panel_side == side do return false, true, {}
	state.panel_side = side
	return true, true, {}
}

/* instance_adjust_panel_width applies one bounded factory width step. */
instance_adjust_panel_width :: proc(
	instance: ^Instance,
	delta: i32,
) -> (width: u32, changed, ok: bool, failure: Failure_Context) {
	state := instance_state(instance)
	if state == nil || delta == 0 {
		return 0, false, false, instance_failure(instance, .Visibility, .Invalid_Instance)
	}
	next := clamp(i64(state.panel_width) + i64(delta), i64(MIN_PANEL_WIDTH), i64(MAX_PANEL_WIDTH))
	width = u32(next)
	if width == state.panel_width do return width, false, true, {}
	state.panel_width = width
	state.panel_normal_width = width
	state.panel_extra_width = false
	return width, true, true, {}
}

/* instance_fit_panel_width fits bounded visible labels and hierarchy indentation. */
instance_fit_panel_width :: proc(
	instance: ^Instance,
) -> (width: u32, changed, ok: bool, failure: Failure_Context) {
	state := instance_state(instance)
	if state == nil {
		return 0, false, false, instance_failure(instance, .Visibility, .Invalid_Instance)
	}
	if state.panel_width_locked do return state.panel_width, false, true, {}
	required := MIN_PANEL_WIDTH
	project := instance_selected_project_root_index(state)
	project_id := Node_ID(0)
	if project >= 0 do project_id = state.nodes[project].handle.id
	for node, index in state.nodes {
		if !instance_node_visible(state, index) do continue
		candidate := u32(min(len(node.label), int(MAX_PANEL_WIDTH))) + u32(node.depth) * 2 + 4
		required = max(required, candidate)
	}
	width = min(required, MAX_PANEL_WIDTH)
	if width == state.panel_width do return width, false, true, {}
	state.panel_width = width
	state.panel_normal_width = width
	state.panel_extra_width = false
	return width, true, true, {}
}

/* instance_toggle_extra_width exchanges normal and factory extra-wide widths. */
instance_toggle_extra_width :: proc(
	instance: ^Instance,
) -> (width: u32, enabled, changed, ok: bool, failure: Failure_Context) {
	state := instance_state(instance)
	if state == nil {
		return 0, false, false, false, instance_failure(instance, .Visibility, .Invalid_Instance)
	}
	state.panel_extra_width = !state.panel_extra_width
	if state.panel_extra_width {
		state.panel_normal_width = state.panel_width
		state.panel_width = min(EXTRA_PANEL_WIDTH, MAX_PANEL_WIDTH)
	} else {
		state.panel_width = clamp(state.panel_normal_width, MIN_PANEL_WIDTH, MAX_PANEL_WIDTH)
	}
	return state.panel_width, state.panel_extra_width, true, true, {}
}

/* instance_toggle_width_lock changes automatic-fit admission. */
instance_toggle_width_lock :: proc(
	instance: ^Instance,
) -> (enabled, changed, ok: bool, failure: Failure_Context) {
	state := instance_state(instance)
	if state == nil {
		return false, false, false, instance_failure(instance, .Visibility, .Invalid_Instance)
	}
	state.panel_width_locked = !state.panel_width_locked
	return state.panel_width_locked, true, true, {}
}

/* instance_toggle_directory_compression changes only hierarchy presentation policy. */
instance_toggle_directory_compression :: proc(
	instance: ^Instance,
) -> (enabled, changed, ok: bool, failure: Failure_Context) {
	state := instance_state(instance)
	if state == nil {
		return false, false, false, instance_failure(instance, .Visibility, .Invalid_Instance)
	}
	state.directory_compression = !state.directory_compression
	return state.directory_compression, true, true, {}
}

/* instance_set_current_project_only narrows projection without mutating roots. */
instance_set_current_project_only :: proc(
	instance: ^Instance,
	enabled: bool,
) -> (changed, ok: bool, failure: Failure_Context) {
	state := instance_state(instance)
	if state == nil {
		return false, false, instance_failure(instance, .Visibility, .Invalid_Instance)
	}
	if enabled && instance_selected_project_root_index(state) < 0 {
		return false, false, state_failure(state, .Visibility, .Node_Not_Found)
	}
	if state.current_project_only == enabled do return false, true, {}
	state.current_project_only = enabled
	state.first_visible = 0
	return true, true, {}
}

@(private)
node_belongs_to_project :: proc(
	state: ^Instance_State,
	node: Node_Descriptor,
	project_id: Node_ID,
) -> bool {
	if state == nil || project_id == Node_ID(0) do return false
	current := node
	for _ in 0 ..< int(state.policy.depth) + 1 {
		if current.handle.id == project_id do return true
		if current.parent == Node_ID(0) do return false
		index := instance_find_node(state, current.parent)
		if index < 0 do return false
		current = state.nodes[index]
	}
	return false
}
