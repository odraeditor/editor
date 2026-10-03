// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ui_reference

Popup_Placement :: enum u8 {
	Invalid,
	Above,
	Below,
	Before,
	After,
}

Popup_Clipping :: enum u8 {
	Invalid,
	Reject,
	Clip,
	Scroll,
	Wrap,
}

Popup_Fallback :: enum u8 {
	Invalid,
	Reject,
	Compact_Feedback,
}

Popup_Placement_State :: enum u8 {
	Invalid,
	Placed,
	Fallback,
	Rejected,
}

Rect :: struct {
	row:    i32,
	column: i32,
	height: i32,
	width:  i32,
}

Popup_Bounds :: struct {
	minimum_rows:      i32,
	minimum_columns:   i32,
	preferred_rows:    i32,
	preferred_columns: i32,
	maximum_rows:      i32,
	maximum_columns:   i32,
}

Popup_Placement_Request :: struct {
	root:               Rect,
	anchor:             Rect,
	placements:         [4]Popup_Placement,
	placement_count:    u8,
	bounds:             Popup_Bounds,
	measured_rows:      i32,
	measured_columns:   i32,
	clipping:           Popup_Clipping,
	fallback:           Popup_Fallback,
}

Popup_Placement_Result :: struct {
	state:     Popup_Placement_State,
	placement: Popup_Placement,
	geometry:  Rect,
	clipped:   bool,
	attempts:  u8,
}

popup_place :: proc(request: Popup_Placement_Request) -> Popup_Placement_Result {
	if !popup_placement_request_is_valid(request) {
		return Popup_Placement_Result{state = .Rejected}
	}
	desired_rows := popup_desired_extent(
		request.measured_rows,
		request.bounds.preferred_rows,
		request.bounds.minimum_rows,
		request.bounds.maximum_rows,
	)
	desired_columns := popup_desired_extent(
		request.measured_columns,
		request.bounds.preferred_columns,
		request.bounds.minimum_columns,
		request.bounds.maximum_columns,
	)
	for index in 0 ..< int(request.placement_count) {
		placement := request.placements[index]
		geometry, clipped, fits := popup_try_placement(
			request,
			placement,
			desired_rows,
			desired_columns,
		)
		if fits {
			return Popup_Placement_Result {
				state = .Placed,
				placement = placement,
				geometry = geometry,
				clipped = clipped,
				attempts = u8(index + 1),
			}
		}
	}
	state := Popup_Placement_State.Rejected
	if request.fallback == .Compact_Feedback {
		state = .Fallback
	}
	return Popup_Placement_Result {
		state = state,
		attempts = request.placement_count,
	}
}

@(private)
popup_placement_request_is_valid :: proc(request: Popup_Placement_Request) -> bool {
	if request.root.height <= 0 || request.root.width <= 0 ||
	   request.anchor.height <= 0 || request.anchor.width <= 0 ||
	   !rect_contains(request.root, request.anchor) || request.placement_count == 0 ||
	   request.placement_count > 4 || request.clipping == .Invalid ||
	   request.fallback == .Invalid || !popup_bounds_valid(request.bounds) {
		return false
	}
	for index in 0 ..< int(request.placement_count) {
		placement := request.placements[index]
		if placement == .Invalid {
			return false
		}
		for prior in 0 ..< index {
			if placement == request.placements[prior] {
				return false
			}
		}
	}
	return true
}

@(private)
popup_bounds_valid :: proc(bounds: Popup_Bounds) -> bool {
	return bounds.minimum_rows > 0 && bounds.minimum_columns > 0 &&
		bounds.minimum_rows <= bounds.preferred_rows &&
		bounds.preferred_rows <= bounds.maximum_rows &&
		bounds.minimum_columns <= bounds.preferred_columns &&
		bounds.preferred_columns <= bounds.maximum_columns
}

@(private)
popup_desired_extent :: proc(measured, preferred, minimum, maximum: i32) -> i32 {
	if measured <= 0 {
		return preferred
	}
	return clamp(measured, minimum, maximum)
}

@(private)
popup_try_placement :: proc(
	request: Popup_Placement_Request,
	placement: Popup_Placement,
	desired_rows, desired_columns: i32,
) -> (geometry: Rect, clipped: bool, fits: bool) {
	root_bottom := request.root.row + request.root.height
	root_right := request.root.column + request.root.width
	anchor_bottom := request.anchor.row + request.anchor.height
	anchor_right := request.anchor.column + request.anchor.width
	available_rows := request.root.height
	available_columns := request.root.width
	switch placement {
	case .Above:
		available_rows = request.anchor.row - request.root.row
	case .Below:
		available_rows = root_bottom - anchor_bottom
	case .Before:
		available_columns = request.anchor.column - request.root.column
	case .After:
		available_columns = root_right - anchor_right
	case .Invalid:
		return {}, false, false
	}
	height, height_clipped, height_ok := popup_fit_extent(
		desired_rows,
		request.bounds.minimum_rows,
		available_rows,
		request.clipping,
	)
	width, width_clipped, width_ok := popup_fit_extent(
		desired_columns,
		request.bounds.minimum_columns,
		available_columns,
		request.clipping,
	)
	if !height_ok || !width_ok {
		return {}, false, false
	}
	geometry.height = height
	geometry.width = width
	switch placement {
	case .Above:
		geometry.row = request.anchor.row - height
		geometry.column = clamp(request.anchor.column, request.root.column, root_right - width)
	case .Below:
		geometry.row = anchor_bottom
		geometry.column = clamp(request.anchor.column, request.root.column, root_right - width)
	case .Before:
		geometry.row = clamp(request.anchor.row, request.root.row, root_bottom - height)
		geometry.column = request.anchor.column - width
	case .After:
		geometry.row = clamp(request.anchor.row, request.root.row, root_bottom - height)
		geometry.column = anchor_right
	case .Invalid:
		return {}, false, false
	}
	return geometry, height_clipped || width_clipped, rect_contains(request.root, geometry)
}

@(private)
popup_fit_extent :: proc(
	desired, minimum, available: i32,
	clipping: Popup_Clipping,
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

@(private)
rect_contains :: proc(outer, inner: Rect) -> bool {
	return inner.row >= outer.row && inner.column >= outer.column &&
		inner.height > 0 && inner.width > 0 &&
		inner.row + inner.height <= outer.row + outer.height &&
		inner.column + inner.width <= outer.column + outer.width
}
