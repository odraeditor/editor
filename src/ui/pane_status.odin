// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ui

/* proposal_project_pane_status attaches one composed Status Bar to one pane surface. */
proposal_project_pane_status :: proc(
	proposal: ^Proposal,
	surface: Object_Handle,
	content: string,
	style_spans: []Status_Style_Span = nil,
	presentation_generation: u64 = 0,
	segments: []Status_Segment_Definition = nil,
) -> (handle: Object_Handle, ok: bool, failure: Failure) {
	state := proposal_state(proposal)
	pane_surface, surface_ok := resolve_surface(state, surface)
	if !surface_ok || !pane_surface.pane.present || len(content) == 0 ||
	   len(style_spans) > MAX_STATUS_STYLE_SPANS {
		return {}, false, generation_failure(state, .Prepare, .Invalid_Status_Region)
	}
	for status in state.status_regions[:state.status_count] {
		if status.placement == .Attached && status.surface == surface {
			return {}, false, generation_failure(state, .Prepare, .Invalid_Status_Region)
		}
	}
	geometry := pane_surface.pane.status
	geometry_state := Layout_Geometry_State.Invalid
	for node in state.nodes[:state.node_count] {
		if node.layout.present &&
		   node.layout.layout_owner_id == pane_surface.pane.layout_owner_id &&
		   node.layout.layout_id == pane_surface.pane.layout_id &&
		   node.layout.layout_generation == pane_surface.pane.layout_generation &&
		   node.layout.node_id == pane_surface.pane.node_id {
			geometry_state = node.layout.geometry_state
			break
		}
	}
	if geometry_state == .Invalid ||
	   ((geometry_state == .Operating || geometry_state == .Semantic) &&
	    (geometry.height != 2 || geometry.width <= 0)) {
		return {}, false, generation_failure(state, .Prepare, .Incompatible_Layout)
	}
	style_role := Style_Role.Status_Normal
	if pane_surface.pane.active do style_role = .Status_Active
	spans: [MAX_STATUS_STYLE_SPANS]Status_Style_Span
	copy(spans[:], style_spans)
	return proposal_add_status(
		proposal,
		Status_Region_Descriptor {
			owner_id = pane_surface.owner_id,
			placement = .Attached,
			surface = surface,
			rows = 2,
			geometry = geometry,
			style_role = style_role,
			style_spans = spans,
			style_span_count = u8(len(style_spans)),
			presentation_generation = presentation_generation,
			active = pane_surface.pane.active,
		},
		content,
		segments,
	)
}

/* snapshot_status_content borrows one checked compact status value from a snapshot. */
snapshot_status_content :: proc(
	view: Snapshot_View,
	status: Status_Region_Descriptor,
) -> (content: string, ok: bool) {
	if status.handle.registry_id != view.root.registry_id ||
	   status.handle.root_generation != view.root.generation ||
	   int(status.handle.slot) >= len(view.status_regions) ||
	   int(status.content_offset) > len(view.compact_content) ||
	   int(status.content_bytes) > len(view.compact_content) - int(status.content_offset) {
		return "", false
	}
	canonical := view.status_regions[int(status.handle.slot)]
	if canonical.handle != status.handle || canonical.content_offset != status.content_offset ||
	   canonical.content_bytes != status.content_bytes {
		return "", false
	}
	start := int(status.content_offset)
	end := start + int(status.content_bytes)
	return string(view.compact_content[start:end]), true
}

/* snapshot_status_segment resolves one segment and its copied inspection text. */
snapshot_status_segment :: proc(
	view: Snapshot_View,
	status: Status_Region_Descriptor,
	index: int,
) -> (segment: Status_Segment_Descriptor, inspection: string, ok: bool) {
	if status.handle.registry_id != view.root.registry_id ||
	   status.handle.root_generation != view.root.generation ||
	   int(status.handle.slot) >= len(view.status_regions) || index < 0 ||
	   index >= int(status.segment_count) {
		return {}, "", false
	}
	canonical := view.status_regions[int(status.handle.slot)]
	if canonical.handle != status.handle || canonical.presentation_generation == 0 ||
	   canonical.segment_count != status.segment_count {
		return {}, "", false
	}
	segment = canonical.segments[index]
	if int(segment.inspection_offset) > len(view.compact_content) ||
	   int(segment.inspection_bytes) > len(view.compact_content) - int(segment.inspection_offset) {
		return {}, "", false
	}
	start := int(segment.inspection_offset)
	end := start + int(segment.inspection_bytes)
	return segment, string(view.compact_content[start:end]), true
}

/* snapshot_status_segment_command resolves one generation-checked admitted command. */
snapshot_status_segment_command :: proc(
	view: Snapshot_View,
	status: Status_Region_Descriptor,
	index: int,
	secondary := false,
) -> (reference: Status_Command_Reference, ok: bool) {
	segment, _, segment_ok := snapshot_status_segment(view, status, index)
	if !segment_ok do return {}, false
	reference = segment.primary_command
	if secondary do reference = segment.secondary_command
	return reference, reference.registry_generation != 0
}
