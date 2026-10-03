// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../completion"
import "../display"
import "../gutter"
import "../ui"

@(private)
COMPLETION_POPUP_OWNER_ID :: ui.Owner_ID(10_019)
@(private)
COMPLETION_POPUP_ID :: ui.Popup_ID(10_019)

@(private)
Completion_Popup_Composition :: struct {
	present:    bool,
	handle:     ui.Object_Handle,
	descriptor: ui.Popup_Descriptor,
}

@(private)
proposal_compose_completion_popup :: proc(
	proposal: ^ui.Proposal,
	workflow: ^Completion_Workflow_State,
	source_surface: ui.Object_Handle,
	source_state_generation: u64,
	display_view: display.Snapshot_View,
	gutter_view: gutter.View,
	interactive_profile: ui.Presentation_Profile_Record,
	contextual_profile: ui.Presentation_Profile_Record,
	profile: ui.Renderer_Profile,
) -> (composition: Completion_Popup_Composition, ok: bool, failure: ui.Failure) {
	if proposal == nil || !completion_workflow_has_interaction(workflow) {
		return {}, true, {}
	}
	if !display_view.cursor.visible ||
	   !ui.presentation_profile_record_is_valid(interactive_profile) ||
	   interactive_profile.definition.role != .Interactive_Candidates ||
	   popup_fallback_required(profile, interactive_profile.definition.bounds) {
		return {}, true, {}
	}
	inspection, inspected, _ := completion.controller_inspect(&workflow.controller)
	if !inspected || inspection.filtered_candidate_count == 0 ||
	   workflow.presentation_generation == max(u64) || workflow.popup_generation == max(u64) {
		return {}, true, {}
	}
	workflow.presentation_generation += 1
	workflow.popup_generation += 1

	content_view: ui.Object_Handle
	content_rows: u32
	content_columns: u32
	content_bytes: u32
	content_generation := u64(inspection.session_generation)
	if workflow.detail_open {
		if !ui.presentation_profile_record_is_valid(contextual_profile) ||
		   contextual_profile.definition.role != .Contextual_Information {
			return {}, false, ui.Failure{operation = .Prepare, code = .Invalid_Popup}
		}
		detail, projected, detail_failure := completion.controller_project_candidate_detail(
			&workflow.controller,
			proposal,
			completion.Detail_Presentation_Request {
				presentation_generation = workflow.presentation_generation,
				row_bytes = min(
					u32(completion.MAX_COMPLETION_DETAIL_ROW_BYTES),
					u32(interactive_profile.definition.bounds.maximum_columns),
				),
				profile = contextual_profile,
			},
		)
		if !projected do return {}, false, detail_failure
		content_view = detail.view
		content_rows = detail.rows
		content_columns = detail.columns
		content_bytes = detail.content_bytes
		content_generation = u64(inspection.projection_generation)
	} else {
		viewport_items := min(
			u32(inspection.filtered_candidate_count),
			u32(interactive_profile.definition.bounds.maximum_rows),
		)
		candidate_view, projected, projection_failure := completion.controller_project_candidates(
			&workflow.controller,
			proposal,
			completion.Presentation_Request {
				presentation_generation = workflow.presentation_generation,
				viewport_items = viewport_items,
				row_bytes = min(
					u32(completion.MAX_COMPLETION_PRESENTATION_ROW_BYTES),
					u32(interactive_profile.definition.bounds.maximum_columns),
				),
				profile = interactive_profile,
			},
		)
		if !projected do return {}, false, projection_failure
		content_view = candidate_view
		content_rows = viewport_items
		content_columns = u32(interactive_profile.definition.bounds.preferred_columns)
		content_bytes = 1
	}
	content_rows = clamp(
		content_rows,
		u32(interactive_profile.definition.bounds.minimum_rows),
		u32(interactive_profile.definition.bounds.maximum_rows),
	)
	content_columns = clamp(
		content_columns,
		u32(interactive_profile.definition.bounds.minimum_columns),
		u32(interactive_profile.definition.bounds.maximum_columns),
	)
	content, content_ok, content_failure := ui.proposal_add_surface(
		proposal,
		ui.Surface_Descriptor {
			owner_id = COMPLETION_POPUP_OWNER_ID,
			view = content_view,
			focusable = false,
			visible = true,
			required_profile = profile.id,
			geometry = {height = i32(content_rows), width = i32(content_columns)},
		},
	)
	if !content_ok do return {}, false, content_failure
	definition := interactive_profile.definition
	descriptor := ui.Popup_Descriptor {
		id = COMPLETION_POPUP_ID,
		generation = ui.Popup_Generation(workflow.popup_generation),
		owner_id = COMPLETION_POPUP_OWNER_ID,
		owner_generation = u64(workflow.controller_generation),
		anchor = {
			kind = .Cursor,
			source_surface = source_surface,
			owner_id = COMPLETION_POPUP_OWNER_ID,
			source_id = u64(inspection.request.scope.view_id),
			source_generation = source_state_generation,
			start = inspection.request.cursor_byte,
			end = inspection.request.cursor_byte,
			presentation_generation = source_state_generation,
			viewport_row = u32(display_view.cursor.viewport_row),
			viewport_column = u32(gutter_view.geometry.left_cells) +
				u32(display_view.cursor.column),
			height_rows = 1,
			width_columns = 1,
		},
		content_surface = content,
		content_generation = content_generation,
		placements = {.Below, .Above, .After, .Before},
		placement_count = 4,
		bounds = definition.bounds,
		margin_rows = definition.margin_rows,
		margin_columns = definition.margin_columns,
		padding_rows = definition.padding_rows,
		padding_columns = definition.padding_columns,
		border = definition.border == .Single,
		clipping = definition.clipping,
		behavior = .Interactive,
		input_policy = .Transient_Capture,
		dismissal = {
			.Explicit_Cancel,
			.Action_Completion,
			.Owner_Cancellation,
			.Owner_Teardown,
			.Anchor_Invalidation,
			.Generation_Replacement,
			.Focus_Loss,
			.Cursor_Movement,
		},
		fallback = definition.popup_fallback,
		required_profile = profile.id,
		presentation_profile = interactive_profile,
		content_bytes = max(content_bytes, 1),
		action_count = u16(min(inspection.filtered_candidate_count, u16(ui.MAX_POPUP_ACTIONS))),
	}
	handle, popup_ok, popup_failure := ui.proposal_add_popup(proposal, descriptor)
	if !popup_ok do return {}, false, popup_failure
	descriptor.handle = handle
	return {present = true, handle = handle, descriptor = descriptor}, true, {}
}
