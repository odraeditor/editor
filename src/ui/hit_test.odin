// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ui

/* snapshot_hit_test resolves one topmost semantic target from copied UI state. */
snapshot_hit_test :: proc(
	snapshot: Snapshot_View,
	request: Hit_Request,
) -> (result: Hit_Result, ok: bool, failure: Failure) {
	if request.root != snapshot.root {
		return {}, false, hit_failure(snapshot, request, .Stale_Root)
	}
	depth := u64(len(snapshot.popups)) + u64(len(snapshot.surfaces))
	if depth > MAX_HIT_TEST_DEPTH {
		failure = hit_failure(snapshot, request, .Geometry_Work_Limit)
		failure.limit = MAX_HIT_TEST_DEPTH
		failure.actual = depth
		return {}, false, failure
	}
	work := u64(len(snapshot.popups)) +
		u64(len(snapshot.surfaces)) * (u64(len(snapshot.status_regions)) + 1) +
		u64(len(snapshot.views))
	if work > MAX_HIT_TEST_WORK {
		failure = hit_failure(snapshot, request, .Geometry_Work_Limit)
		failure.limit = MAX_HIT_TEST_WORK
		failure.actual = work
		return {}, false, failure
	}
	if request.row < 0 || request.column < 0 ||
	   request.row >= i32(snapshot.renderer.max_rows) ||
	   request.column >= i32(snapshot.renderer.max_columns) {
		return {}, false, hit_failure(snapshot, request, .Invalid_Hit)
	}

	popup_index := topmost_popup_at(snapshot.popups, request.row, request.column)
	if popup_index >= 0 {
		popup := snapshot.popups[popup_index]
		surface, surface_ok := snapshot_surface_descriptor(snapshot, popup.content_surface)
		view: Object_Handle
		pane: Pane_Surface_State
		focusable := false
		if surface_ok {
			view = surface.view
			pane = surface.pane
			focusable = surface.focusable
		}
		return hit_result(
			snapshot,
			request,
			.Popup,
			popup.geometry.outer,
			popup.handle,
			popup.content_surface,
			view,
			{},
			pane,
			focusable,
		), true, {}
	}

	for reverse_index := len(snapshot.surfaces); reverse_index > 0; reverse_index -= 1 {
		surface := snapshot.surfaces[reverse_index - 1]
		if !surface.visible do continue

		status, status_ok := surface_status_at(snapshot, surface, request.row, request.column)
		if status_ok {
			return hit_result(
				snapshot, request, .Status, status.geometry, {}, surface.handle,
				surface.view, status.handle, surface.pane, surface.focusable,
			), true, {}
		}
		if surface.pane.present && cell_rect_contains_point(
			surface.pane.separator, request.row, request.column,
		) {
			return hit_result(
				snapshot, request, .Separator, surface.pane.separator, {}, surface.handle,
				surface.view, {}, surface.pane, surface.focusable,
			), true, {}
		}
		if cell_rect_contains_point(surface.geometry, request.row, request.column) {
			kind := Hit_Kind.Content
			view, view_ok := snapshot_view_descriptor(snapshot, surface.view)
			if view_ok && view.kind == .Text_View && view.text.gutter.present &&
			   text_gutter_contains_column(view.text.gutter, surface.geometry, request.column) {
				kind = .Gutter
			}
			return hit_result(
				snapshot, request, kind, surface.geometry, {}, surface.handle,
				surface.view, {}, surface.pane, surface.focusable,
			), true, {}
		}
		if surface.pane.present && cell_rect_contains_point(
			surface.pane.outer, request.row, request.column,
		) {
			return hit_result(
				snapshot, request, .Surface, surface.pane.outer, {}, surface.handle,
				surface.view, {}, surface.pane, surface.focusable,
			), true, {}
		}
	}

	return hit_result(
		snapshot,
		request,
		.Background,
		Cell_Rect {
			row = 0,
			column = 0,
			height = i32(snapshot.renderer.max_rows),
			width = i32(snapshot.renderer.max_columns),
		},
		{},
		{},
		{},
		{},
		{},
		false,
	), true, {}
}

@(private)
hit_failure :: proc(
	snapshot: Snapshot_View,
	request: Hit_Request,
	code: Failure_Code,
) -> Failure {
	return Failure {
		operation = .Hit_Test,
		code = code,
		root = request.root,
		actual = u64(max(request.row, request.column, 0)),
		required_profile = snapshot.renderer.id,
	}
}

@(private)
hit_result :: proc(
	snapshot: Snapshot_View,
	request: Hit_Request,
	kind: Hit_Kind,
	geometry: Cell_Rect,
	popup, surface, view, status: Object_Handle,
	pane: Pane_Surface_State,
	focusable: bool,
) -> Hit_Result {
	local_row := request.row - geometry.row
	item: Semantic_Item_Hit
	if kind == .Content {
		item, _ = semantic_item_hit(snapshot, view, local_row)
	}
	return Hit_Result {
		root = snapshot.root,
		kind = kind,
		row = request.row,
		column = request.column,
		local_row = local_row,
		local_column = request.column - geometry.column,
		geometry = geometry,
		popup = popup,
		surface = surface,
		view = view,
		status = status,
		pane = pane,
		item = item,
		focusable = focusable,
	}
}

@(private)
semantic_item_hit :: proc(
	snapshot: Snapshot_View,
	view_handle: Object_Handle,
	local_row: i32,
) -> (hit: Semantic_Item_Hit, ok: bool) {
	if local_row < 0 do return {}, false
	view, view_ok := snapshot_view_descriptor(snapshot, view_handle)
	if !view_ok do return {}, false
	projection, projection_ok := snapshot_projection_descriptor(snapshot, view.projection)
	if !projection_ok do return {}, false
	row := u32(local_row)
	switch view.kind {
	case .List_View:
		if !list_view_state_is_valid(view.list) || row >= view.list.position.viewport_items {
			return {}, false
		}
		index := view.list.position.first_visible_item + row
		if index >= view.list.item_count do return {}, false
		storage_index := u64(view.list.item_offset) + u64(index)
		if storage_index >= u64(len(snapshot.list_items)) do return {}, false
		item := snapshot.list_items[int(storage_index)]
		if item.projection != view.projection do return {}, false
		return Semantic_Item_Hit {
			kind = .List,
			projection = view.projection,
			model = projection.model,
			item_id = u64(item.id),
			action = item.action,
			presentation_generation = view.list.position.presentation_generation,
			projection_index = index,
		}, true
	case .Tree_View:
		if !tree_view_state_is_valid(view.tree) || row >= view.tree.position.viewport_items {
			return {}, false
		}
		index := view.tree.position.first_visible_item + row
		if index >= view.tree.node_count do return {}, false
		storage_index := u64(view.tree.node_offset) + u64(index)
		if storage_index >= u64(len(snapshot.tree_nodes)) do return {}, false
		node := snapshot.tree_nodes[int(storage_index)]
		if node.projection != view.projection do return {}, false
		return Semantic_Item_Hit {
			kind = .Tree,
			projection = view.projection,
			model = projection.model,
			item_id = u64(node.id),
			action = node.action,
			presentation_generation = view.tree.position.presentation_generation,
			projection_index = index,
		}, true
	case .Invalid, .Text_View, .Terminal_View, .Input:
	}
	return {}, false
}

@(private)
topmost_popup_at :: proc(popups: []Popup_Descriptor, row, column: i32) -> int {
	selected := -1
	selected_z: u8
	for popup, index in popups {
		if popup.geometry.state == .Invalid ||
		   !cell_rect_contains_point(popup.geometry.outer, row, column) {
			continue
		}
		if selected < 0 || popup.geometry.z_order >= selected_z {
			selected = index
			selected_z = popup.geometry.z_order
		}
	}
	return selected
}

@(private)
surface_status_at :: proc(
	snapshot: Snapshot_View,
	surface: Surface_Descriptor,
	row, column: i32,
) -> (Status_Region_Descriptor, bool) {
	for reverse_index := len(snapshot.status_regions); reverse_index > 0; reverse_index -= 1 {
		status := snapshot.status_regions[reverse_index - 1]
		if status.surface == surface.handle &&
		   cell_rect_contains_point(status.geometry, row, column) {
			return status, true
		}
	}
	return {}, false
}

@(private)
snapshot_view_descriptor :: proc(
	snapshot: Snapshot_View,
	handle: Object_Handle,
) -> (Visual_View_Descriptor, bool) {
	for view in snapshot.views {
		if view.handle == handle do return view, true
	}
	return {}, false
}

@(private)
snapshot_projection_descriptor :: proc(
	snapshot: Snapshot_View,
	handle: Object_Handle,
) -> (Projection_Descriptor, bool) {
	for projection in snapshot.projections {
		if projection.handle == handle do return projection, true
	}
	return {}, false
}

@(private)
snapshot_surface_descriptor :: proc(
	snapshot: Snapshot_View,
	handle: Object_Handle,
) -> (Surface_Descriptor, bool) {
	for surface in snapshot.surfaces {
		if surface.handle == handle do return surface, true
	}
	return {}, false
}

@(private)
text_gutter_contains_column :: proc(
	gutter: Text_Gutter_State,
	geometry: Cell_Rect,
	column: i32,
) -> bool {
	local := column - geometry.column
	return local >= 0 &&
		(local < i32(gutter.left_cells) || local >= geometry.width - i32(gutter.right_cells))
}

@(private)
cell_rect_contains_point :: proc(rect: Cell_Rect, row, column: i32) -> bool {
	if !cell_rect_is_operating(rect) do return false
	return i64(row) >= i64(rect.row) && i64(column) >= i64(rect.column) &&
		i64(row) < i64(rect.row) + i64(rect.height) &&
		i64(column) < i64(rect.column) + i64(rect.width)
}
