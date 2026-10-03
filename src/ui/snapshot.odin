// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ui

import "base:runtime"

@(private)
Snapshot_State :: struct {
	view:      Snapshot_View,
	allocator: runtime.Allocator,
}

/* registry_snapshot copies one exact compatible immutable UI generation. */
registry_snapshot :: proc(
	registry: ^Registry,
	expected: Root_Handle,
	renderer: Renderer_Profile,
	allocator := context.allocator,
) -> (snapshot: Snapshot, ok: bool, failure: Failure) {
	state := registry_state(registry)
	if state == nil || state.active == nil {
		return {}, false, registry_failure(registry, .Snapshot, .Invalid_Registry)
	}
	if expected != current_root(state) {
		return {}, false, state_failure(state, .Snapshot, .Stale_Root)
	}
	if !renderer_profile_is_valid(renderer) || renderer != state.active.renderer {
		failure = state_failure(state, .Snapshot, .Renderer_Incompatible)
		failure.required_profile = state.active.renderer.id
		return {}, false, failure
	}
	if allocator.procedure == nil {
		return {}, false, state_failure(state, .Snapshot, .Allocation)
	}
	active := state.active
	snapshot_bytes := u64(active.projection_count * size_of(Projection_Descriptor)) +
		u64(active.view_count * size_of(Visual_View_Descriptor)) +
		u64(active.terminal_row_count * size_of(Terminal_Row)) +
		u64(active.terminal_cell_count * size_of(Terminal_Cell)) +
		u64(active.list_item_count * size_of(List_Item_Descriptor)) +
		u64(len(active.list_content)) +
		u64(active.tree_node_count * size_of(Tree_Node_Descriptor)) +
		u64(len(active.tree_content)) +
		u64(active.input_choice_count * size_of(Input_Choice_Descriptor)) +
		u64(len(active.input_content)) +
		u64(active.surface_count * size_of(Surface_Descriptor)) +
		u64(active.node_count * size_of(Composition_Descriptor)) +
		u64(active.status_count * size_of(Status_Region_Descriptor)) +
		u64(active.popup_count * size_of(Popup_Descriptor)) +
		active.accounting.compact_region_bytes +
		u64(active.style_count * size_of(Style_Descriptor)) +
		u64(active.decoration_count * size_of(Decoration_Descriptor))
	if snapshot_bytes > state.limits.snapshot_bytes {
		failure = state_failure(state, .Snapshot, .Snapshot_Limit)
		failure.limit = state.limits.snapshot_bytes
		failure.actual = snapshot_bytes
		return {}, false, failure
	}
	owner, allocation_error := new(Snapshot_State, allocator)
	if allocation_error != nil {
		return {}, false, state_failure(state, .Snapshot, .Allocation)
	}
	owner.allocator = allocator
	owner.view.root = current_root(state)
	owner.view.root_node = active.root_node
	owner.view.focus = active.focus
	owner.view.renderer = active.renderer
	owner.view.accounting = active.accounting
	owner.view.accounting.snapshot_bytes = snapshot_bytes
	owner.view.projections, allocation_error = snapshot_copy(
		active.projections[:active.projection_count],
		allocator,
	)
	if allocation_error == nil do owner.view.views, allocation_error = snapshot_copy(
		active.views[:active.view_count],
		allocator,
	)
	if allocation_error == nil do owner.view.terminal_rows, allocation_error = snapshot_copy(
		active.terminal_rows[:active.terminal_row_count],
		allocator,
	)
	if allocation_error == nil do owner.view.terminal_cells, allocation_error = snapshot_copy(
		active.terminal_cells[:active.terminal_cell_count],
		allocator,
	)
	if allocation_error == nil do owner.view.list_items, allocation_error = snapshot_copy(
		active.list_items[:active.list_item_count],
		allocator,
	)
	if allocation_error == nil do owner.view.list_content, allocation_error = snapshot_copy(
		active.list_content,
		allocator,
	)
	if allocation_error == nil do owner.view.tree_nodes, allocation_error = snapshot_copy(
		active.tree_nodes[:active.tree_node_count],
		allocator,
	)
	if allocation_error == nil do owner.view.tree_content, allocation_error = snapshot_copy(
		active.tree_content,
		allocator,
	)
	if allocation_error == nil do owner.view.input_choices, allocation_error = snapshot_copy(
		active.input_choices[:active.input_choice_count],
		allocator,
	)
	if allocation_error == nil do owner.view.input_content, allocation_error = snapshot_copy(
		active.input_content,
		allocator,
	)
	if allocation_error == nil do owner.view.surfaces, allocation_error = snapshot_copy(
		active.surfaces[:active.surface_count],
		allocator,
	)
	if allocation_error == nil do owner.view.composition, allocation_error = snapshot_copy(
		active.nodes[:active.node_count],
		allocator,
	)
	if allocation_error == nil do owner.view.status_regions, allocation_error = snapshot_copy(
		active.status_regions[:active.status_count],
		allocator,
	)
	if allocation_error == nil do owner.view.popups, allocation_error = snapshot_copy(
		active.popups[:active.popup_count],
		allocator,
	)
	if allocation_error == nil do owner.view.compact_content, allocation_error = snapshot_copy(
		active.compact_content[:int(active.accounting.compact_region_bytes)],
		allocator,
	)
	if allocation_error == nil do owner.view.styles, allocation_error = snapshot_copy(
		active.styles[:active.style_count],
		allocator,
	)
	if allocation_error == nil do owner.view.decorations, allocation_error = snapshot_copy(
		active.decorations[:active.decoration_count],
		allocator,
	)
	if allocation_error != nil {
		snapshot_state_release(owner)
		return {}, false, state_failure(state, .Snapshot, .Allocation)
	}
	return Snapshot{state = owner}, true, {}
}

/* snapshot_view borrows one immutable copied generation from its live owner. */
snapshot_view :: proc(snapshot: ^Snapshot) -> (view: Snapshot_View, ok: bool) {
	state := snapshot_state(snapshot)
	if state == nil {
		return {}, false
	}
	return state.view, true
}

/* snapshot_close releases all copied generation storage exactly once. */
snapshot_close :: proc(snapshot: ^Snapshot) -> bool {
	state := snapshot_state(snapshot)
	if state == nil {
		return false
	}
	snapshot_state_release(state)
	snapshot^ = {}
	return true
}

@(private)
snapshot_state :: proc(snapshot: ^Snapshot) -> ^Snapshot_State {
	if snapshot == nil || snapshot.state == nil {
		return nil
	}
	return cast(^Snapshot_State)snapshot.state
}

@(private)
snapshot_state_release :: proc(state: ^Snapshot_State) {
	if state == nil {
		return
	}
	allocator := state.allocator
	if state.view.decorations != nil do delete(state.view.decorations, allocator)
	if state.view.styles != nil do delete(state.view.styles, allocator)
	if state.view.compact_content != nil do delete(state.view.compact_content, allocator)
	if state.view.status_regions != nil do delete(state.view.status_regions, allocator)
	if state.view.popups != nil do delete(state.view.popups, allocator)
	if state.view.composition != nil do delete(state.view.composition, allocator)
	if state.view.surfaces != nil do delete(state.view.surfaces, allocator)
	if state.view.list_content != nil do delete(state.view.list_content, allocator)
	if state.view.list_items != nil do delete(state.view.list_items, allocator)
	if state.view.tree_content != nil do delete(state.view.tree_content, allocator)
	if state.view.tree_nodes != nil do delete(state.view.tree_nodes, allocator)
	if state.view.input_content != nil do delete(state.view.input_content, allocator)
	if state.view.input_choices != nil do delete(state.view.input_choices, allocator)
	if state.view.terminal_cells != nil do delete(state.view.terminal_cells, allocator)
	if state.view.terminal_rows != nil do delete(state.view.terminal_rows, allocator)
	if state.view.views != nil do delete(state.view.views, allocator)
	if state.view.projections != nil do delete(state.view.projections, allocator)
	free(state, allocator)
}

@(private)
snapshot_copy :: proc(source: []$T, allocator: runtime.Allocator) -> ([]T, runtime.Allocator_Error) {
	if len(source) == 0 {
		return nil, nil
	}
	target, allocation_error := make([]T, len(source), allocator)
	if allocation_error != nil {
		return nil, allocation_error
	}
	copy(target, source)
	return target, nil
}
