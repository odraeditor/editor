// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ui

@(private)
popup_compose_geometry :: proc(
	state: ^Generation_State,
	popup: ^Popup_Descriptor,
) -> bool {
	if state == nil || popup == nil || !renderer_profile_is_valid(state.renderer) {
		return false
	}
	anchor, anchor_ok := resolve_popup_anchor(state, popup^)
	content_surface, content_ok := resolve_surface(state, popup.content_surface)
	if !anchor_ok || !content_ok {
		return false
	}
	root := Cell_Rect {
		row = 0,
		column = 0,
		height = i32(state.renderer.max_rows),
		width = i32(state.renderer.max_columns),
	}
	inset_rows := i32(popup.margin_rows) + i32(popup.padding_rows)
	inset_columns := i32(popup.margin_columns) + i32(popup.padding_columns)
	if popup.border {
		inset_rows += 1
		inset_columns += 1
	}
	minimum_rows := i32(popup.bounds.minimum_rows)
	minimum_columns := i32(popup.bounds.minimum_columns)
	if minimum_rows <= inset_rows * 2 || minimum_columns <= inset_columns * 2 {
		return false
	}
	measured_rows := content_surface.geometry.height
	measured_columns := content_surface.geometry.width
	if measured_rows <= 0 do measured_rows = i32(popup.bounds.preferred_rows) - inset_rows * 2
	if measured_columns <= 0 do measured_columns = i32(popup.bounds.preferred_columns) - inset_columns * 2
	desired_rows := clamp(
		measured_rows + inset_rows * 2,
		minimum_rows,
		i32(popup.bounds.maximum_rows),
	)
	desired_columns := clamp(
		measured_columns + inset_columns * 2,
		minimum_columns,
		i32(popup.bounds.maximum_columns),
	)
	for index in 0 ..< int(popup.placement_count) {
		placement := popup.placements[index]
		outer, clipped, fits := popup_try_geometry(
			root,
			anchor.geometry,
			placement,
			desired_rows,
			desired_columns,
			minimum_rows,
			minimum_columns,
			popup.clipping,
		)
		if !fits {
			continue
		}
		content := Cell_Rect {
			row = outer.row + inset_rows,
			column = outer.column + inset_columns,
			height = outer.height - inset_rows * 2,
			width = outer.width - inset_columns * 2,
		}
		if !cell_rect_is_operating(content) {
			return false
		}
		popup.geometry = Popup_Geometry {
			state = .Placed,
			placement = placement,
			anchor = anchor.geometry,
			outer = outer,
			content = content,
			clipped = clipped,
			attempts = u8(index + 1),
			z_order = 1,
			obscures_underlay = true,
		}
		return true
	}
	geometry_state := Popup_Geometry_State.Rejected
	if popup.fallback == .Compact_Feedback {
		geometry_state = .Fallback
	}
	popup.geometry = Popup_Geometry {
		state = geometry_state,
		anchor = anchor.geometry,
		attempts = popup.placement_count,
	}
	return geometry_state == .Fallback
}

@(private)
popup_try_geometry :: proc(
	root, anchor: Cell_Rect,
	placement: Popup_Placement,
	desired_rows, desired_columns, minimum_rows, minimum_columns: i32,
	clipping: Popup_Clipping_Policy,
) -> (geometry: Cell_Rect, clipped: bool, fits: bool) {
	root_bottom := root.row + root.height
	root_right := root.column + root.width
	anchor_bottom := anchor.row + anchor.height
	anchor_right := anchor.column + anchor.width
	available_rows := root.height
	available_columns := root.width
	switch placement {
	case .Above:
		available_rows = anchor.row - root.row
	case .Below:
		available_rows = root_bottom - anchor_bottom
	case .Before:
		available_columns = anchor.column - root.column
	case .After:
		available_columns = root_right - anchor_right
	case .Invalid:
		return {}, false, false
	}
	height, height_clipped, height_ok := popup_fit_geometry_extent(
		desired_rows, minimum_rows, available_rows, clipping,
	)
	width, width_clipped, width_ok := popup_fit_geometry_extent(
		desired_columns, minimum_columns, available_columns, clipping,
	)
	if !height_ok || !width_ok {
		return {}, false, false
	}
	geometry.height = height
	geometry.width = width
	switch placement {
	case .Above:
		geometry.row = anchor.row - height
		geometry.column = clamp(anchor.column, root.column, root_right - width)
	case .Below:
		geometry.row = anchor_bottom
		geometry.column = clamp(anchor.column, root.column, root_right - width)
	case .Before:
		geometry.row = clamp(anchor.row, root.row, root_bottom - height)
		geometry.column = anchor.column - width
	case .After:
		geometry.row = clamp(anchor.row, root.row, root_bottom - height)
		geometry.column = anchor_right
	case .Invalid:
		return {}, false, false
	}
	return geometry, height_clipped || width_clipped, cell_rect_contains(root, geometry)
}

@(private)
popup_fit_geometry_extent :: proc(
	desired, minimum, available: i32,
	clipping: Popup_Clipping_Policy,
) -> (extent: i32, clipped: bool, ok: bool) {
	if available < minimum {
		return 0, false, false
	}
	if desired <= available {
		return desired, false, true
	}
	if clipping == .Reject {
		return 0, false, false
	}
	return available, true, true
}
