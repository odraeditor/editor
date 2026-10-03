// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ui

/* registry_resolve_popup_anchor resolves one current checked popup anchor. */
registry_resolve_popup_anchor :: proc(
	registry: ^Registry,
	popup: Object_Handle,
) -> (resolution: Popup_Anchor_Resolution, ok: bool, failure: Failure) {
	state := registry_state(registry)
	if state == nil || state.active == nil {
		return {}, false, registry_failure(registry, .Inspect, .Invalid_Registry)
	}
	if popup.root_generation != state.generation {
		return {}, false, object_failure(state, .Inspect, .Stale_Popup, popup)
	}
	descriptor, popup_ok := resolve_popup(state.active, popup)
	if !popup_ok {
		return {}, false, object_failure(state, .Inspect, .Invalid_Popup, popup)
	}
	resolution, ok = resolve_popup_anchor(state.active, descriptor^)
	if !ok {
		return {}, false, object_failure(state, .Inspect, .Invalid_Popup_Anchor, popup)
	}
	return resolution, true, {}
}

@(private)
resolve_popup_anchor :: proc(
	state: ^Generation_State,
	popup: Popup_Descriptor,
) -> (resolution: Popup_Anchor_Resolution, ok: bool) {
	if state == nil || popup.anchor.kind == .Invalid ||
	   popup.anchor.kind == .Backend_Coordinates || popup.anchor.height_rows == 0 ||
	   popup.anchor.width_columns == 0 || popup.anchor.presentation_generation == 0 {
		return {}, false
	}
	surface, surface_ok := resolve_surface(state, popup.anchor.source_surface)
	if !surface_ok || !surface.visible || !cell_rect_is_operating(surface.geometry) {
		return {}, false
	}
	view, view_ok := resolve_view(state, surface.view)
	if !view_ok {
		return {}, false
	}
	if popup.anchor.viewport_row > u32(max(i32)) ||
	   popup.anchor.viewport_column > u32(max(i32)) {
		return {}, false
	}
	relative := Cell_Rect {
		row = i32(popup.anchor.viewport_row),
		column = i32(popup.anchor.viewport_column),
		height = i32(popup.anchor.height_rows),
		width = i32(popup.anchor.width_columns),
	}
	if !cell_rect_contains(
		Cell_Rect{height = surface.geometry.height, width = surface.geometry.width},
		relative,
	) {
		return {}, false
	}
	switch popup.anchor.kind {
	case .Cursor:
		if !view.text.present || popup.anchor.source_id != view.text.source.view_id ||
		   popup.anchor.source_generation != view.text.source.state_generation ||
		   popup.anchor.presentation_generation != view.text.source.state_generation ||
		   popup.anchor.start != view.text.effective_point ||
		   popup.anchor.end != view.text.effective_point {
			return {}, false
		}
	case .Logical_Text:
		if !view.text.present || popup.anchor.source_id != view.text.buffer_id ||
		   popup.anchor.source_generation != view.text.revision ||
		   popup.anchor.presentation_generation != view.text.source.state_generation ||
		   popup.anchor.end < popup.anchor.start ||
		   popup.anchor.end > view.text.source_text_bytes {
			return {}, false
		}
	case .Gutter_Marker:
		if !view.text.present || !view.text.gutter.present ||
		   popup.anchor.source_generation != view.text.gutter.generation ||
		   popup.anchor.presentation_generation != view.text.source.state_generation ||
		   !popup_gutter_row_matches(view.text.gutter, popup.anchor.start, relative.row) {
			return {}, false
		}
	case .Surface:
		if popup.anchor.source_id != u64(surface.handle.object_id) ||
		   popup.anchor.source_generation != u64(surface.handle.root_generation) ||
		   popup.anchor.presentation_generation != u64(surface.handle.root_generation) {
			return {}, false
		}
	case .Backend_Coordinates, .Invalid:
		return {}, false
	}
	geometry := Cell_Rect {
		row = surface.geometry.row + relative.row,
		column = surface.geometry.column + relative.column,
		height = relative.height,
		width = relative.width,
	}
	return Popup_Anchor_Resolution {
		root = Root_Handle{registry_id = state.registry_id, generation = state.generation},
		popup = popup.handle,
		kind = popup.anchor.kind,
		source_surface = surface.handle,
		source_view = view.handle,
		owner_id = popup.anchor.owner_id,
		source_id = popup.anchor.source_id,
		source_generation = popup.anchor.source_generation,
		geometry = geometry,
	}, true
}

@(private)
popup_gutter_row_matches :: proc(
	gutter: Text_Gutter_State,
	logical_line: u64,
	viewport_row: i32,
) -> bool {
	for index in 0 ..< int(gutter.row_count) {
		row := gutter.rows[index]
		if row.logical_line == logical_line && i32(row.viewport_row) == viewport_row {
			return true
		}
	}
	return false
}

@(private)
cell_rect_is_operating :: proc(rect: Cell_Rect) -> bool {
	return rect.height > 0 && rect.width > 0
}

@(private)
cell_rect_contains :: proc(outer, inner: Cell_Rect) -> bool {
	return cell_rect_is_operating(outer) && cell_rect_is_operating(inner) &&
		inner.row >= outer.row && inner.column >= outer.column &&
		inner.row + inner.height <= outer.row + outer.height &&
		inner.column + inner.width <= outer.column + outer.width
}
