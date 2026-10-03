// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../gutter"
import "../ui"

@(private)
GUTTER_POPUP_OWNER_ID :: ui.Owner_ID(10_014)
@(private)
GUTTER_POPUP_MODEL_ID :: ui.Model_ID(10_014)
@(private)
GUTTER_POPUP_ID :: ui.Popup_ID(10_014)

@(private)
Gutter_Popup_Composition :: struct {
	present:    bool,
	handle:     ui.Object_Handle,
	descriptor: ui.Popup_Descriptor,
}

@(private)
gutter_popup_style_slot :: proc(role: gutter.Semantic_Role) -> ui.Presentation_Chrome_Slot {
	#partial switch role {
	case .Diagnostic_Error, .Diagnostic_Warning, .Diagnostic_Information,
	     .Diagnostic_Hint, .Stale:
		return .Attention
	case .Unavailable:
		return .Unavailable
	case:
		return .Content
	}
}

@(private)
proposal_compose_gutter_popup :: proc(
	proposal: ^ui.Proposal,
	state: ^Gutter_Inspection_State,
	source_surface: ui.Object_Handle,
	source_state_generation: u64,
	gutter_view: gutter.View,
	presentation_profile: ui.Presentation_Profile_Record,
	profile: ui.Renderer_Profile,
) -> (composition: Gutter_Popup_Composition, ok: bool, failure: ui.Failure) {
	if proposal == nil || state == nil || !state.popup_open {
		return {}, true, {}
	}
	if !ui.presentation_profile_record_is_valid(presentation_profile) ||
	   presentation_profile.definition.role != .Contextual_Information {
		return {}, false, ui.Failure{operation = .Prepare, code = .Invalid_Popup}
	}
	definition := presentation_profile.definition
	if popup_fallback_required(profile, definition.bounds) {
		return {}, true, {}
	}
	if state.popup_generation == max(u64) {
		return {}, false, ui.Failure{operation = .Prepare, code = .Generation_Limit}
	}
	state.popup_generation += 1
	content, projected := gutter_popup_content_project(state, state.popup_generation)
	if !projected {
		return {}, false, ui.Failure{operation = .Prepare, code = .Invalid_Popup_Content}
	}
	row, row_found := gutter_popup_anchor_row(gutter_view, state.logical_line)
	if !row_found {
		return {}, false, ui.Failure{operation = .Prepare, code = .Invalid_Popup_Anchor}
	}
	column, width, lane_found := gutter_popup_anchor_lane(gutter_view, content.lane)
	if !lane_found {
		return {}, false, ui.Failure{operation = .Prepare, code = .Invalid_Popup_Anchor}
	}

	detail := string(content.detail[:content.detail_length])
	items: [1]ui.List_Item_Definition
	items[0] = {
		id = 1,
		text = detail,
		action = {owner_id = GUTTER_POPUP_OWNER_ID, action_id = 1, generation = content.generation},
	}
	style_slot := gutter_popup_style_slot(content.role)
	style_role, style_ok := ui.presentation_profile_definition_style(&definition, style_slot)
	if !style_ok do return {}, false, ui.Failure{operation = .Prepare, code = .Invalid_Style}
	items[0].style_spans[0] = {
		start_byte = 0,
		end_byte = u32(len(detail)),
		style_role = style_role,
	}
	items[0].style_span_count = 1
	item_count := 1
	view, view_ok, view_failure := ui.proposal_project_list_view(
		proposal,
		ui.List_Projection_Request {
			model = {
				owner_id = GUTTER_POPUP_OWNER_ID,
				model_id = GUTTER_POPUP_MODEL_ID,
				generation = ui.Model_Generation(content.generation),
			},
			position = {
				presentation_generation = content.generation,
				selection_owner = .Model,
				current_item = 0,
				first_visible_item = 0,
				viewport_items = u32(item_count),
			},
			read_only = true,
		},
		items[:item_count],
	)
	if !view_ok do return {}, false, view_failure
	content_width := len(detail)
	content_width = clamp(content_width, 14, 76)
	surface, surface_ok, surface_failure := ui.proposal_add_surface(
		proposal,
		ui.Surface_Descriptor {
			owner_id = GUTTER_POPUP_OWNER_ID,
			view = view,
			focusable = false,
			visible = true,
			required_profile = profile.id,
			geometry = {height = i32(item_count), width = i32(content_width)},
		},
	)
	if !surface_ok do return {}, false, surface_failure
	descriptor := ui.Popup_Descriptor {
		id = GUTTER_POPUP_ID,
		generation = ui.Popup_Generation(content.generation),
		owner_id = GUTTER_POPUP_OWNER_ID,
		owner_generation = content.generation,
		anchor = {
			kind = .Gutter_Marker,
			source_surface = source_surface,
			owner_id = GUTTER_POPUP_OWNER_ID,
			source_id = u64(content.marker_id),
			source_generation = u64(gutter_view.generation),
			start = state.logical_line,
			end = state.logical_line,
			presentation_generation = source_state_generation,
			viewport_row = row,
			viewport_column = column,
			height_rows = 1,
			width_columns = width,
		},
		content_surface = surface,
		content_generation = content.generation,
		placements = {.Above, .Below, .After, .Before},
		placement_count = 4,
		bounds = definition.bounds,
		margin_rows = definition.margin_rows,
		margin_columns = definition.margin_columns,
		padding_rows = definition.padding_rows,
		padding_columns = definition.padding_columns,
		border = definition.border == .Single,
		clipping = definition.clipping,
		behavior = .Informational,
		input_policy = .Preserve_Source_Focus,
		dismissal = {
			.Explicit_Cancel,
			.Anchor_Invalidation,
			.Source_Closure,
			.Cursor_Movement,
			.Generation_Replacement,
		},
		fallback = definition.popup_fallback,
		required_profile = profile.id,
		presentation_profile = presentation_profile,
		content_bytes = u32(len(detail)),
		action_count = 1 if content.actionable else 0,
	}
	handle, popup_ok, popup_failure := ui.proposal_add_popup(proposal, descriptor)
	if !popup_ok do return {}, false, popup_failure
	descriptor.handle = handle
	return Gutter_Popup_Composition {
		present = true,
		handle = handle,
		descriptor = descriptor,
	}, true, {}
}

@(private)
gutter_popup_anchor_row :: proc(view: gutter.View, logical_line: u64) -> (u32, bool) {
	for row in view.rows {
		if row.logical_line == logical_line do return row.viewport_row, true
	}
	return 0, false
}

@(private)
gutter_popup_anchor_lane :: proc(
	view: gutter.View,
	lane: gutter.Lane_ID,
) -> (column: u32, width: u16, found: bool) {
	for index in 0 ..< int(view.geometry.lane_count) {
		geometry := view.geometry.lanes[index]
		if geometry.lane != lane || !geometry.visible || geometry.width_cells == 0 do continue
		if geometry.side == .Left {
			return u32(geometry.start_cell), geometry.width_cells, true
		}
		return u32(view.geometry.left_cells) + view.geometry.text_cells +
			u32(geometry.start_cell), geometry.width_cells, true
	}
	return 0, 0, false
}
