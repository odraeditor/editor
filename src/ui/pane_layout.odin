// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ui

import "../layout"

/* Pane_Text_View_Binding associates one delivered pane with its projected visual view. */
Pane_Text_View_Binding :: struct {
	pane: layout.Pane_Handle,
	view: Object_Handle,
}

/* Pane_Layout_Projection returns the complete shared root and checked focus surface. */
Pane_Layout_Projection :: struct {
	root_node:    Object_Handle,
	focus_surface: Object_Handle,
	pane_count:   u16,
}

/* proposal_map_pane_layout maps one immutable delivered pane tree into surfaces and splits. */
proposal_map_pane_layout :: proc(
	proposal: ^Proposal,
	source: layout.Snapshot,
	bindings: []Pane_Text_View_Binding,
	required_profile: Renderer_Profile_ID,
) -> (projection: Pane_Layout_Projection, ok: bool, failure: Failure) {
	state := proposal_state(proposal)
	if state == nil || required_profile == Renderer_Profile_ID(0) ||
	   !pane_layout_source_is_valid(state, source, bindings) {
		return {}, false, generation_failure(state, .Prepare, .Invalid_Layout)
	}
	if state.surface_count + int(source.pane_count) > len(state.surfaces) ||
	   state.node_count + int(source.node_count) > len(state.nodes) {
		return {}, false, generation_failure(state, .Prepare, .Composition_Limit)
	}
	needed := u64(source.pane_count) + u64(source.node_count)
	if needed > u64(max(u64)) - u64(state.next_object_id) {
		return {}, false, generation_failure(state, .Prepare, .Generation_Limit)
	}

	surfaces: [layout.MAX_LIVE_PANES]Object_Handle
	surface_panes: [layout.MAX_LIVE_PANES]layout.Pane_ID
	surface_count: int
	for node_index in 0 ..< int(source.node_count) {
		node := source.nodes[node_index]
		if node.kind != .Pane {
			continue
		}
		binding, _ := pane_binding_find(bindings, node.pane)
		pane_state := pane_surface_state(source, node)
		surface, surface_ok, surface_failure := proposal_add_surface(
			proposal,
			Surface_Descriptor {
				owner_id = Owner_ID(source.handle.owner_id),
				view = binding.view,
				focusable = true,
				visible = true,
				required_profile = required_profile,
				geometry = pane_state.content,
				pane = pane_state,
			},
		)
		if !surface_ok {
			return {}, false, surface_failure
		}
		surfaces[surface_count] = surface
		surface_panes[surface_count] = node.pane.pane_id
		surface_count += 1
		if node.pane == source.active_pane {
			projection.focus_surface = surface
		}
	}

	ui_nodes: [layout.MAX_SNAPSHOT_NODES]Object_Handle
	source_node_ids: [layout.MAX_SNAPSHOT_NODES]layout.Node_ID
	ui_node_count: int
	for reverse_index := int(source.node_count) - 1; reverse_index >= 0; reverse_index -= 1 {
		node := source.nodes[reverse_index]
		ui_node: Object_Handle
		node_ok: bool
		node_failure: Failure
		if node.kind == .Pane {
			surface, found := pane_surface_find(
				surfaces[:surface_count],
				surface_panes[:surface_count],
				node.pane.pane_id,
			)
			if !found {
				return {}, false, generation_failure(state, .Prepare, .Incompatible_Layout)
			}
			ui_node, node_ok, node_failure = proposal_add_surface_node(proposal, surface)
		} else {
			first, first_ok := layout_node_find(
				ui_nodes[:ui_node_count], source_node_ids[:ui_node_count], node.first_child_id,
			)
			second, second_ok := layout_node_find(
				ui_nodes[:ui_node_count], source_node_ids[:ui_node_count], node.second_child_id,
			)
			if !first_ok || !second_ok {
				return {}, false, generation_failure(state, .Prepare, .Incompatible_Layout)
			}
			orientation := Split_Orientation.Above_Below
			if node.arrangement == .Left_Right do orientation = .Left_Right
			ui_node, node_ok, node_failure = proposal_add_split(
				proposal, first, second, orientation, node.first_weight, node.second_weight,
			)
		}
		if !node_ok {
			return {}, false, node_failure
		}
		entry, _ := resolve_node(state, ui_node)
		entry.depth = node.depth
		entry.layout = layout_node_state(source, node)
		ui_nodes[ui_node_count] = ui_node
		source_node_ids[ui_node_count] = node.node_id
		ui_node_count += 1
	}
	projection.root_node, ok = layout_node_find(
		ui_nodes[:ui_node_count], source_node_ids[:ui_node_count], source.root_id,
	)
	if !ok || projection.focus_surface.object_id == Object_ID(0) {
		return {}, false, generation_failure(state, .Prepare, .Incompatible_Layout)
	}
	root_ok, root_failure := proposal_set_root(
		proposal, projection.root_node, projection.focus_surface,
	)
	if !root_ok {
		return {}, false, root_failure
	}
	projection.pane_count = source.pane_count
	return projection, true, {}
}

/* proposal_pane_surface returns the exact projected surface for one delivered pane. */
proposal_pane_surface :: proc(
	proposal: ^Proposal,
	pane: layout.Pane_Handle,
) -> (surface: Object_Handle, ok: bool, failure: Failure) {
	state := proposal_state(proposal)
	if state == nil || pane.layout.owner_id == layout.Owner_ID(0) ||
	   pane.layout.layout_id == layout.Layout_ID(0) || pane.pane_id == layout.Pane_ID(0) {
		return {}, false, generation_failure(state, .Inspect, .Invalid_Layout)
	}
	for candidate in state.surfaces[:state.surface_count] {
		if candidate.pane.present &&
		   candidate.pane.layout_owner_id == u64(pane.layout.owner_id) &&
		   candidate.pane.layout_id == u64(pane.layout.layout_id) &&
		   candidate.pane.layout_generation == u64(pane.layout.generation) &&
		   candidate.pane.pane_id == u64(pane.pane_id) &&
		   candidate.pane.pane_slot == pane.slot &&
		   candidate.pane.pane_generation == pane.slot_generation {
			return candidate.handle, true, {}
		}
	}
	return {}, false, generation_failure(state, .Inspect, .Incompatible_Layout)
}

@(private)
pane_layout_source_is_valid :: proc(
	state: ^Generation_State,
	source: layout.Snapshot,
	bindings: []Pane_Text_View_Binding,
) -> bool {
	if source.handle.owner_id == layout.Owner_ID(0) || source.handle.layout_id == layout.Layout_ID(0) ||
	   source.handle.generation == layout.Layout_Generation(0) || source.root_id == layout.Node_ID(0) ||
	   source.node_count == 0 || source.node_count > layout.MAX_SNAPSHOT_NODES ||
	   source.pane_count == 0 || int(source.pane_count) != len(bindings) ||
	   source.partition_count + source.pane_count != source.node_count ||
	   map_layout_geometry_state(source.geometry_state) == .Invalid {
		return false
	}
	pane_count: int
	partition_count: int
	root_found := false
	active_found := false
	for node_index in 0 ..< int(source.node_count) {
		node := source.nodes[node_index]
		if node.node_id == layout.Node_ID(0) || node.slot_generation == 0 {
			return false
		}
		if node.node_id == source.root_id do root_found = true
		if node.kind == .Pane {
			binding, found := pane_binding_find(bindings, node.pane)
			if !found || node.pane.layout != source.handle || node.buffer_id == 0 ||
			   node.view.view_id == 0 || node.view.generation == 0 {
				return false
			}
			view, view_ok := resolve_view(state, binding.view)
			if !view_ok || !pane_binding_view_is_valid(view, node) {
				return false
			}
			pane_count += 1
			if node.pane == source.active_pane && node.active do active_found = true
		} else if node.kind == .Partition {
			if node.arrangement == .Invalid || node.first_child_id == 0 ||
			   node.second_child_id == 0 || node.first_weight == 0 || node.second_weight == 0 {
				return false
			}
			partition_count += 1
		} else {
			return false
		}
	}
	return root_found && active_found && pane_count == int(source.pane_count) &&
		partition_count == int(source.partition_count)
}

@(private)
pane_binding_view_is_valid :: proc(view: ^Visual_View_Descriptor, node: layout.Node_Descriptor) -> bool {
	switch view.kind {
	case .Text_View:
		return view.text.present &&
			view.text.source.registry_id == u32(node.view.registry_id) &&
			view.text.source.view_id == u64(node.view.view_id) &&
			view.text.source.view_generation == node.view.generation &&
			view.text.buffer_id == u64(node.buffer_id)
	case .Terminal_View:
		return view.terminal.present
	case .Invalid, .List_View, .Tree_View, .Input:
		return false
	}
	return false
}

@(private)
pane_binding_find :: proc(bindings: []Pane_Text_View_Binding, pane: layout.Pane_Handle) -> (Pane_Text_View_Binding, bool) {
	for binding in bindings {
		if binding.pane == pane do return binding, true
	}
	return {}, false
}

@(private)
pane_surface_find :: proc(surfaces: []Object_Handle, panes: []layout.Pane_ID, pane: layout.Pane_ID) -> (Object_Handle, bool) {
	for candidate, index in panes {
		if candidate == pane do return surfaces[index], true
	}
	return {}, false
}

@(private)
layout_node_find :: proc(nodes: []Object_Handle, ids: []layout.Node_ID, id: layout.Node_ID) -> (Object_Handle, bool) {
	for candidate, index in ids {
		if candidate == id do return nodes[index], true
	}
	return {}, false
}

@(private)
map_layout_geometry_state :: proc(value: layout.Geometry_State) -> Layout_Geometry_State {
	#partial switch value {
	case .Operating: return .Operating
	case .Semantic: return .Semantic
	case .Insufficient: return .Insufficient
	}
	return .Invalid
}

@(private)
map_pane_dedication :: proc(value: layout.Pane_Dedication) -> Pane_Dedication {
	switch value {
	case .None: return .None
	case .Soft: return .Soft
	case .Hard: return .Hard
	}
	return .None
}

@(private)
cell_rect :: proc(value: layout.Rect) -> Cell_Rect {
	return Cell_Rect{row = value.row, column = value.column, height = value.height, width = value.width}
}

@(private)
pane_surface_state :: proc(source: layout.Snapshot, node: layout.Node_Descriptor) -> Pane_Surface_State {
	return Pane_Surface_State {
		present = true,
		layout_owner_id = u64(source.handle.owner_id),
		layout_id = u64(source.handle.layout_id),
		layout_generation = u64(source.handle.generation),
		node_id = u64(node.node_id),
		node_generation = node.slot_generation,
		pane_id = u64(node.pane.pane_id),
		pane_slot = node.pane.slot,
		pane_generation = node.pane.slot_generation,
		buffer_id = u64(node.buffer_id),
		entry_id = u64(node.entry.entry_id),
		entry_generation = node.entry.generation,
		dedication = map_pane_dedication(node.dedication),
		history_count = node.history_count,
		history_generation = node.history_generation,
		outer = cell_rect(node.geometry.outer),
		content = cell_rect(node.geometry.content),
		status = cell_rect(node.geometry.status),
		separator = cell_rect(node.geometry.separator),
		active = node.active,
		mru_rank = node.mru_rank,
	}
}

@(private)
layout_node_state :: proc(source: layout.Snapshot, node: layout.Node_Descriptor) -> Layout_Node_State {
	return Layout_Node_State {
		present = true,
		layout_owner_id = u64(source.handle.owner_id),
		layout_id = u64(source.handle.layout_id),
		layout_generation = u64(source.handle.generation),
		node_id = u64(node.node_id),
		node_generation = node.slot_generation,
		parent_id = u64(node.parent_id),
		depth = node.depth,
		geometry_state = map_layout_geometry_state(source.geometry_state),
		geometry_rows = source.geometry_request.rows,
		geometry_columns = source.geometry_request.columns,
		reserved_rows = source.geometry_request.global_reserved_rows,
		reserved_columns = source.geometry_request.global_reserved_columns,
		outer = cell_rect(node.geometry.outer),
		separator = cell_rect(node.geometry.separator),
	}
}
