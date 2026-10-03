// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ui

import "core:unicode/utf8"

/* proposal_begin allocates one private generation against an exact root. */
proposal_begin :: proc(
	registry: ^Registry,
	expected: Root_Handle = {},
) -> (proposal: Proposal, ok: bool, failure: Failure) {
	state := registry_state(registry)
	if state == nil {
		return {}, false, registry_failure(registry, .Prepare, .Invalid_Registry)
	}
	if state.proposal_active {
		return {}, false, state_failure(state, .Prepare, .Busy)
	}
	if state.generation == Root_Generation(0) {
		if expected.registry_id != Registry_ID(0) || expected.generation != Root_Generation(0) {
			return {}, false, state_failure(state, .Prepare, .Stale_Root)
		}
	} else if expected != current_root(state) {
		return {}, false, state_failure(state, .Prepare, .Stale_Root)
	}
	if state.generation == Root_Generation(max(u64)) {
		return {}, false, state_failure(state, .Prepare, .Generation_Limit)
	}
	candidate, allocated := generation_allocate(state)
	if !allocated {
		return {}, false, state_failure(state, .Prepare, .Allocation)
	}
	state.proposal_active = true
	return Proposal{state = candidate}, true, {}
}

/* proposal_abort releases one unpublished generation exactly once. */
proposal_abort :: proc(proposal: ^Proposal) -> bool {
	state := proposal_state(proposal)
	if state == nil {
		return false
	}
	state.registry.proposal_active = false
	generation_release(state)
	proposal^ = {}
	return true
}

/* proposal_add_projection copies one semantic observation contract. */
proposal_add_projection :: proc(
	proposal: ^Proposal,
	model: Model_Reference,
	byte_count: u64,
	read_only := true,
) -> (handle: Object_Handle, ok: bool, failure: Failure) {
	state := proposal_state(proposal)
	if state == nil || model.owner_id == Owner_ID(0) || model.model_id == Model_ID(0) ||
	   model.generation == Model_Generation(0) {
		return {}, false, generation_failure(state, .Prepare, .Invalid_Projection)
	}
	if state.projection_count >= len(state.projections) {
		return {}, false, generation_failure(state, .Prepare, .View_Limit)
	}
	limits := state.registry.limits
	if byte_count > limits.projection_bytes - state.accounting.projection_bytes {
		failure = generation_failure(state, .Prepare, .Projection_Limit)
		failure.limit = limits.projection_bytes
		failure.actual = state.accounting.projection_bytes + byte_count
		return {}, false, failure
	}
	handle, ok = next_handle(state, state.projection_count)
	if !ok {
		return {}, false, generation_failure(state, .Prepare, .Generation_Limit)
	}
	state.projections[state.projection_count] = Projection_Descriptor {
		handle = handle,
		model = model,
		byte_count = byte_count,
		item_count = 0,
		read_only = read_only,
	}
	state.projection_count += 1
	state.accounting.projection_bytes += byte_count
	return handle, true, {}
}

/* proposal_add_view copies one checked visual primitive descriptor. */
proposal_add_view :: proc(
	proposal: ^Proposal,
	descriptor: Visual_View_Descriptor,
) -> (handle: Object_Handle, ok: bool, failure: Failure) {
	state := proposal_state(proposal)
	if state == nil || state.view_count >= len(state.views) {
		return {}, false, generation_failure(state, .Prepare, .View_Limit)
	}
	projection, projection_ok := resolve_projection(state, descriptor.projection)
	if !projection_ok {
		return {}, false, generation_failure(state, .Prepare, .Invalid_Projection)
	}
	handle, ok = next_handle(state, state.view_count)
	if !ok {
		return {}, false, generation_failure(state, .Prepare, .Generation_Limit)
	}
	entry := descriptor
	entry.handle = handle
	if !visual_contract_is_valid(entry) ||
	   (entry.kind == .Terminal_View && !terminal_view_matches_projection(state, entry.terminal, projection)) ||
	   (entry.kind == .List_View && !list_view_matches_projection(state, entry.list, projection)) ||
	   (entry.kind == .Tree_View && !tree_view_matches_projection(state, entry.tree, projection)) ||
	   (entry.kind == .Input && !input_view_matches_projection(state, entry.input, projection)) {
		return {}, false, generation_failure(state, .Prepare, .Invalid_View)
	}
	state.views[state.view_count] = entry
	state.view_count += 1
	return handle, true, {}
}

/* proposal_add_surface copies one logical containment and focus contract. */
proposal_add_surface :: proc(
	proposal: ^Proposal,
	descriptor: Surface_Descriptor,
) -> (handle: Object_Handle, ok: bool, failure: Failure) {
	state := proposal_state(proposal)
	if state == nil || state.surface_count >= len(state.surfaces) {
		return {}, false, generation_failure(state, .Prepare, .Surface_Limit)
	}
	if descriptor.owner_id == Owner_ID(0) || descriptor.required_profile == Renderer_Profile_ID(0) {
		return {}, false, generation_failure(state, .Prepare, .Invalid_Surface)
	}
	_, view_ok := resolve_view(state, descriptor.view)
	if !view_ok {
		return {}, false, generation_failure(state, .Prepare, .Invalid_View)
	}
	handle, ok = next_handle(state, state.surface_count)
	if !ok {
		return {}, false, generation_failure(state, .Prepare, .Generation_Limit)
	}
	entry := descriptor
	entry.handle = handle
	state.surfaces[state.surface_count] = entry
	state.surface_count += 1
	return handle, true, {}
}

/* proposal_add_popup copies one bounded temporary-surface lifecycle record. */
proposal_add_popup :: proc(
	proposal: ^Proposal,
	descriptor: Popup_Descriptor,
) -> (handle: Object_Handle, ok: bool, failure: Failure) {
	state := proposal_state(proposal)
	if state == nil {
		return {}, false, generation_failure(state, .Prepare, .Invalid_Proposal)
	}
	if state.popup_count >= len(state.popups) {
		failure = generation_failure(state, .Prepare, .Popup_Limit)
		failure.limit = u64(state.registry.limits.live_popups)
		failure.actual = u64(state.popup_count + 1)
		return {}, false, failure
	}
	if !popup_descriptor_shape_is_valid(descriptor) ||
	   !popup_input_mode_is_supported(descriptor) {
		return {}, false, generation_failure(state, .Prepare, .Invalid_Popup)
	}
	source, source_ok := resolve_surface(state, descriptor.anchor.source_surface)
	if !source_ok || !source.visible {
		return {}, false, generation_failure(state, .Prepare, .Invalid_Popup_Anchor)
	}
	content, content_ok := resolve_surface(state, descriptor.content_surface)
	if !content_ok || !content.visible || content.focusable ||
	   content.handle == source.handle || content.required_profile != descriptor.required_profile {
		return {}, false, generation_failure(state, .Prepare, .Invalid_Popup_Content)
	}
	if _, anchor_ok := resolve_popup_anchor(state, descriptor); !anchor_ok {
		return {}, false, generation_failure(state, .Prepare, .Invalid_Popup_Anchor)
	}
	content_view, view_ok := resolve_view(state, content.view)
	if !view_ok ||
	   (descriptor.behavior == .Interactive && content_view.kind != .List_View) {
		return {}, false, generation_failure(state, .Prepare, .Invalid_Popup_Content)
	}
	content_projection, projection_ok := resolve_projection(state, content_view.projection)
	if !projection_ok || u64(descriptor.content_bytes) > content_projection.byte_count {
		return {}, false, generation_failure(state, .Prepare, .Invalid_Popup_Content)
	}
	limits := state.registry.limits
	content_bytes := u64(descriptor.content_bytes)
	if content_bytes > limits.popup_content_bytes - state.accounting.popup_content_bytes {
		failure = generation_failure(state, .Prepare, .Popup_Content_Limit)
		failure.limit = limits.popup_content_bytes
		failure.actual = state.accounting.popup_content_bytes + content_bytes
		return {}, false, failure
	}
	if descriptor.action_count > limits.popup_actions - state.accounting.popup_actions {
		failure = generation_failure(state, .Prepare, .Popup_Action_Limit)
		failure.limit = u64(limits.popup_actions)
		failure.actual = u64(state.accounting.popup_actions) + u64(descriptor.action_count)
		return {}, false, failure
	}
	handle, ok = next_handle(state, state.popup_count)
	if !ok {
		return {}, false, generation_failure(state, .Prepare, .Generation_Limit)
	}
	entry := descriptor
	entry.handle = handle
	state.popups[state.popup_count] = entry
	state.popup_count += 1
	state.accounting.popup_bytes += u64(size_of(Popup_Descriptor))
	state.accounting.popup_content_bytes += content_bytes
	state.accounting.popup_actions += descriptor.action_count
	return handle, true, {}
}

/* proposal_add_surface_node creates one composition leaf for an existing surface. */
proposal_add_surface_node :: proc(
	proposal: ^Proposal,
	surface: Object_Handle,
) -> (handle: Object_Handle, ok: bool, failure: Failure) {
	state := proposal_state(proposal)
	if state == nil || state.node_count >= len(state.nodes) {
		return {}, false, generation_failure(state, .Prepare, .Composition_Limit)
	}
	if _, valid := resolve_surface(state, surface); !valid {
		return {}, false, generation_failure(state, .Prepare, .Invalid_Surface)
	}
	handle, ok = next_handle(state, state.node_count)
	if !ok {
		return {}, false, generation_failure(state, .Prepare, .Generation_Limit)
	}
	state.nodes[state.node_count] = Composition_Descriptor {
		handle = handle,
		kind = .Surface,
		surface = surface,
	}
	state.node_count += 1
	return handle, true, {}
}

/* proposal_add_split creates one bounded binary logical composition node. */
proposal_add_split :: proc(
	proposal: ^Proposal,
	first, second: Object_Handle,
	orientation: Split_Orientation,
	first_weight: u64 = 1,
	second_weight: u64 = 1,
) -> (handle: Object_Handle, ok: bool, failure: Failure) {
	state := proposal_state(proposal)
	if state == nil || state.node_count >= len(state.nodes) {
		return {}, false, generation_failure(state, .Prepare, .Composition_Limit)
	}
	_, first_ok := resolve_node(state, first)
	_, second_ok := resolve_node(state, second)
	if !first_ok || !second_ok || first == second ||
	   (orientation != .Above_Below && orientation != .Left_Right) ||
	   first_weight == 0 || second_weight == 0 {
		return {}, false, generation_failure(state, .Prepare, .Invalid_Composition)
	}
	handle, ok = next_handle(state, state.node_count)
	if !ok {
		return {}, false, generation_failure(state, .Prepare, .Generation_Limit)
	}
	state.nodes[state.node_count] = Composition_Descriptor {
		handle = handle,
		kind = .Split,
		first = first,
		second = second,
		orientation = orientation,
		first_weight = first_weight,
		second_weight = second_weight,
	}
	state.node_count += 1
	return handle, true, {}
}

/* proposal_add_panel wraps one composition child in persistent edge-panel semantics. */
proposal_add_panel :: proc(
	proposal: ^Proposal,
	child: Object_Handle,
	edge: Panel_Edge,
	extent: u32,
) -> (handle: Object_Handle, ok: bool, failure: Failure) {
	state := proposal_state(proposal)
	if state == nil || state.node_count >= len(state.nodes) {
		return {}, false, generation_failure(state, .Prepare, .Composition_Limit)
	}
	_, child_ok := resolve_node(state, child)
	if !child_ok || edge == .Invalid || extent == 0 {
		return {}, false, generation_failure(state, .Prepare, .Invalid_Composition)
	}
	handle, ok = next_handle(state, state.node_count)
	if !ok {
		return {}, false, generation_failure(state, .Prepare, .Generation_Limit)
	}
	state.nodes[state.node_count] = Composition_Descriptor {
		handle = handle,
		kind = .Panel,
		panel_child = child,
		panel_edge = edge,
		panel_extent = extent,
	}
	state.node_count += 1
	return handle, true, {}
}

/* proposal_add_style copies one unique semantic role mapping. */
proposal_add_style :: proc(
	proposal: ^Proposal,
	role: Style_Role,
	attributes: Style_Attributes = {},
	foreground: Optional_SRGB_Color = {},
	background: Optional_SRGB_Color = {},
) -> (handle: Object_Handle, ok: bool, failure: Failure) {
	state := proposal_state(proposal)
	if state == nil {
		return {}, false, generation_failure(state, .Prepare, .Style_Limit)
	}
	definition := Style_Definition {
		role = role,
		foreground = foreground,
		background = background,
		attributes = attributes,
	}
	if !style_definition_is_valid(definition) || resolve_style_role(state, role) {
		return {}, false, generation_failure(state, .Prepare, .Invalid_Style)
	}
	if state.style_count >= len(state.styles) {
		return {}, false, generation_failure(state, .Prepare, .Style_Limit)
	}
	handle, ok = next_handle(state, state.style_count)
	if !ok {
		return {}, false, generation_failure(state, .Prepare, .Generation_Limit)
	}
	state.styles[state.style_count] = Style_Descriptor {
		handle = handle,
		role = role,
		foreground = foreground,
		background = background,
		attributes = attributes,
	}
	state.style_count += 1
	state.accounting.style_bytes += u64(size_of(Style_Descriptor))
	return handle, true, {}
}

/* proposal_add_status copies one attached or root-edge compact region. */
proposal_add_status :: proc(
	proposal: ^Proposal,
	descriptor: Status_Region_Descriptor,
	content: string,
	segment_definitions: []Status_Segment_Definition = nil,
) -> (handle: Object_Handle, ok: bool, failure: Failure) {
	state := proposal_state(proposal)
	if state == nil || state.status_count >= len(state.status_regions) {
		return {}, false, generation_failure(state, .Prepare, .Status_Region_Limit)
	}
	valid_placement := descriptor.placement == .Root_Edge &&
		descriptor.surface.object_id == Object_ID(0) ||
		(descriptor.placement == .Attached && descriptor.surface.object_id != Object_ID(0))
	if !valid_placement || descriptor.owner_id == Owner_ID(0) || descriptor.rows == 0 ||
	   descriptor.style_span_count > MAX_STATUS_STYLE_SPANS ||
	   len(segment_definitions) > MAX_STATUS_SEGMENTS || descriptor.segment_count != 0 ||
	   (len(segment_definitions) > 0 && descriptor.presentation_generation == 0) ||
	   !resolve_style_role(state, descriptor.style_role) {
		return {}, false, generation_failure(state, .Prepare, .Invalid_Status_Region)
	}
	inspection_bytes := u64(0)
	previous_segment_end := u32(0)
	for segment, segment_index in segment_definitions {
		if segment.identity == 0 || segment.kind == 0 || segment.start_byte < previous_segment_end ||
		   segment.start_byte >= segment.end_byte || segment.end_byte > u32(len(content)) ||
		   segment.start_cell >= segment.end_cell ||
		   !utf8.valid_string(content[:int(segment.start_byte)]) ||
		   !utf8.valid_string(content[:int(segment.end_byte)]) ||
		   len(segment.inspection_text) > int(MAX_STATUS_INSPECTION_BYTES) ||
		   !utf8.valid_string(segment.inspection_text) ||
		   !status_command_reference_is_valid(segment.primary_command) ||
		   !status_command_reference_is_valid(segment.secondary_command) {
			return {}, false, generation_failure(state, .Prepare, .Invalid_Status_Region)
		}
		for previous in segment_definitions[:segment_index] {
			if previous.identity == segment.identity {
				return {}, false, generation_failure(state, .Prepare, .Invalid_Status_Region)
			}
		}
		previous_segment_end = segment.end_byte
		inspection_bytes += u64(len(segment.inspection_text))
	}
	previous_end := u32(0)
	for span_index in 0 ..< int(descriptor.style_span_count) {
		span := descriptor.style_spans[span_index]
		if span.start_byte < previous_end || span.start_byte >= span.end_byte ||
		   span.end_byte > u32(len(content)) || !style_role_is_valid(span.style_role) ||
		   !utf8.valid_string(content[:int(span.start_byte)]) ||
		   !utf8.valid_string(content[:int(span.end_byte)]) ||
		   !resolve_style_role(state, span.style_role) {
			return {}, false, generation_failure(state, .Prepare, .Invalid_Status_Region)
		}
		previous_end = span.end_byte
	}
	if descriptor.placement == .Attached {
		if _, surface_ok := resolve_surface(state, descriptor.surface); !surface_ok {
			return {}, false, generation_failure(state, .Prepare, .Invalid_Surface)
		}
	}
	limits := state.registry.limits
	content_bytes := u64(len(content))
	retained_bytes := content_bytes + inspection_bytes
	if retained_bytes >
	   limits.compact_region_bytes - state.accounting.compact_region_bytes {
		failure = generation_failure(state, .Prepare, .Compact_Region_Limit)
		failure.limit = limits.compact_region_bytes
		failure.actual = state.accounting.compact_region_bytes + retained_bytes
		return {}, false, failure
	}
	handle, ok = next_handle(state, state.status_count)
	if !ok {
		return {}, false, generation_failure(state, .Prepare, .Generation_Limit)
	}
	entry := descriptor
	entry.handle = handle
	entry.content_offset = u32(state.accounting.compact_region_bytes)
	entry.content_bytes = u32(content_bytes)
	content_end := int(state.accounting.compact_region_bytes + content_bytes)
	copy(
		state.compact_content[int(state.accounting.compact_region_bytes):content_end],
		transmute([]u8)content,
	)
	inspection_offset := content_end
	for segment, segment_index in segment_definitions {
		entry.segments[segment_index] = Status_Segment_Descriptor {
			identity = segment.identity,
			kind = segment.kind,
			start_byte = segment.start_byte,
			end_byte = segment.end_byte,
			start_cell = segment.start_cell,
			end_cell = segment.end_cell,
			compact = segment.compact,
			truncated = segment.truncated,
			inspection_offset = u32(inspection_offset),
			inspection_bytes = u32(len(segment.inspection_text)),
			primary_command = segment.primary_command,
			secondary_command = segment.secondary_command,
		}
		copy(
			state.compact_content[inspection_offset:inspection_offset + len(segment.inspection_text)],
			transmute([]u8)segment.inspection_text,
		)
		inspection_offset += len(segment.inspection_text)
	}
	entry.segment_count = u8(len(segment_definitions))
	state.status_regions[state.status_count] = entry
	state.status_count += 1
	state.accounting.compact_region_bytes += retained_bytes
	return handle, true, {}
}

@(private = "file")
status_command_reference_is_valid :: proc(reference: Status_Command_Reference) -> bool {
	if reference.registry_generation == 0 {
		return reference.slot == 0 && reference.entry_generation == 0
	}
	return reference.entry_generation > 0
}

/* proposal_add_decoration copies one checked semantic presentation record. */
proposal_add_decoration :: proc(
	proposal: ^Proposal,
	descriptor: Decoration_Descriptor,
) -> (handle: Object_Handle, ok: bool, failure: Failure) {
	state := proposal_state(proposal)
	if state == nil || state.decoration_count >= len(state.decorations) {
		return {}, false, generation_failure(state, .Prepare, .Decoration_Limit)
	}
	if !decoration_shape_is_valid(state, descriptor) {
		return {}, false, generation_failure(state, .Prepare, .Invalid_Decoration)
	}
	if _, projection_ok := resolve_projection(state, descriptor.projection); !projection_ok {
		return {}, false, generation_failure(state, .Prepare, .Invalid_Projection)
	}
	if !decoration_projection_is_valid(state, descriptor) {
		return {}, false, generation_failure(state, .Prepare, .Invalid_Decoration)
	}
	if descriptor.kind == .Text_Range && !decoration_follows_prior_ranges(state, descriptor) {
		return {}, false, generation_failure(state, .Prepare, .Invalid_Decoration)
	}
	handle, ok = next_handle(state, state.decoration_count)
	if !ok {
		return {}, false, generation_failure(state, .Prepare, .Generation_Limit)
	}
	entry := descriptor
	entry.handle = handle
	state.decorations[state.decoration_count] = entry
	state.decoration_count += 1
	state.accounting.decoration_bytes += u64(size_of(Decoration_Descriptor))
	return handle, true, {}
}

/* proposal_set_root selects the complete topology and ordinary focus target. */
proposal_set_root :: proc(
	proposal: ^Proposal,
	root_node, focus_surface: Object_Handle,
) -> (ok: bool, failure: Failure) {
	state := proposal_state(proposal)
	if state == nil {
		return false, generation_failure(state, .Prepare, .Invalid_Proposal)
	}
	if _, root_ok := resolve_node(state, root_node); !root_ok {
		return false, generation_failure(state, .Prepare, .Invalid_Composition)
	}
	focus, focus_ok := resolve_surface(state, focus_surface)
	if !focus_ok || !focus.focusable || !focus.visible {
		return false, generation_failure(state, .Prepare, .Invalid_Focus)
	}
	state.root_node = root_node
	state.focus = Focus_Descriptor{target = focus_surface}
	return true, {}
}

/* proposal_publish validates and atomically replaces the visible root generation. */
proposal_publish :: proc(
	registry: ^Registry,
	proposal: ^Proposal,
	renderer: Renderer_Profile,
) -> (root: Root_Handle, ok: bool, failure: Failure) {
	registry_data := registry_state(registry)
	state := proposal_state(proposal)
	if registry_data == nil || state == nil || state.registry != registry_data {
		return {}, false, registry_failure(registry, .Publish, .Invalid_Proposal)
	}
	if state.expected != registry_data.generation {
		return {}, false, state_failure(registry_data, .Publish, .Stale_Root)
	}
	state.renderer = renderer
	if !proposal_validate_state(state) {
		state.renderer = {}
		return {}, false, generation_failure(state, .Validate, .Invalid_Proposal)
	}
	previous := registry_data.active
	proposal_preserve_transient_capture(state, previous)
	registry_data.active = state
	registry_data.generation = state.generation
	registry_data.proposal_active = false
	registry_data.focus_generation += 1
	proposal^ = {}
	if previous != nil {
		generation_release(previous)
	}
	return current_root(registry_data), true, {}
}

@(private)
proposal_state :: proc(proposal: ^Proposal) -> ^Generation_State {
	if proposal == nil || proposal.state == nil {
		return nil
	}
	return cast(^Generation_State)proposal.state
}

@(private)
proposal_validate_state :: proc(state: ^Generation_State) -> bool {
	if state == nil || state.registry == nil || !renderer_profile_is_valid(state.renderer) ||
	   state.surface_count == 0 || state.view_count == 0 || state.projection_count == 0 ||
	   state.node_count == 0 || state.style_count == 0 ||
	   state.root_node.object_id == Object_ID(0) ||
	   state.focus.target.object_id == Object_ID(0) {
		return false
	}
	if state.accounting.projection_bytes > state.registry.limits.projection_bytes ||
	   state.accounting.style_bytes != u64(state.style_count * size_of(Style_Descriptor)) ||
	   state.accounting.decoration_bytes != u64(state.decoration_count * size_of(Decoration_Descriptor)) ||
	   state.accounting.list_items != u32(state.list_item_count) ||
	   state.accounting.list_items > state.registry.limits.list_items ||
	   state.accounting.tree_nodes != u32(state.tree_node_count) ||
	   state.accounting.tree_nodes > state.registry.limits.tree_nodes ||
	   state.accounting.input_bytes > state.registry.limits.input_bytes ||
	   state.accounting.fixed_choices != u16(state.input_choice_count) ||
	   state.accounting.fixed_choices > state.registry.limits.fixed_choices ||
	   state.accounting.compact_region_bytes > state.registry.limits.compact_region_bytes ||
	   state.accounting.popup_bytes != u64(state.popup_count * size_of(Popup_Descriptor)) ||
	   state.accounting.popup_content_bytes > state.registry.limits.popup_content_bytes ||
	   state.accounting.popup_actions > state.registry.limits.popup_actions {
		return false
	}
	for view in state.views[:state.view_count] {
		projection, projection_ok := resolve_projection(state, view.projection)
		if !projection_ok || !visual_contract_is_valid(view) ||
		   (view.kind == .Text_View && !text_gutter_contract_is_valid(state, view.text.gutter)) ||
		   (view.kind == .Terminal_View && !terminal_view_matches_projection(state, view.terminal, projection)) ||
		   (view.kind == .List_View && !list_view_matches_projection(state, view.list, projection)) ||
		   (view.kind == .Tree_View && !tree_view_matches_projection(state, view.tree, projection)) ||
		   (view.kind == .Input && !input_view_matches_projection(state, view.input, projection)) {
			return false
		}
	}
	root_edge_count := 0
	for status in state.status_regions[:state.status_count] {
		content_end := u64(status.content_offset) + u64(status.content_bytes)
		if content_end > state.accounting.compact_region_bytes {
			return false
		}
		if status.placement == .Root_Edge {
			root_edge_count += 1
		}
		if !resolve_style_role(state, status.style_role) {
			return false
		}
	}
	for decoration in state.decorations[:state.decoration_count] {
		if !decoration_contract_is_valid(state, decoration) {
			return false
		}
	}
	if root_edge_count > 1 {
		return false
	}
	popup_surface_references: [MAX_LIVE_SURFACES]u16
	popup_content_bytes: u64
	popup_actions: u16
	popup_geometry_work: u64
	for &popup in state.popups[:state.popup_count] {
		if !popup_contract_is_valid(state, popup) || !popup_compose_geometry(state, &popup) {
			return false
		}
		content, _ := resolve_surface(state, popup.content_surface)
		popup_surface_references[content.handle.slot] += 1
		popup_content_bytes += u64(popup.content_bytes)
		popup_actions += popup.action_count
		popup_geometry_work += u64(popup.geometry.attempts)
		if popup.geometry.state == .Placed {
			popup_geometry_work += u64(popup.geometry.outer.height) *
				u64(popup.geometry.outer.width)
		}
	}
	if popup_content_bytes != state.accounting.popup_content_bytes ||
	   popup_actions != state.accounting.popup_actions {
		return false
	}
	if state.popup_count > 0 && .Popup_Overlap not_in state.renderer.capabilities {
		return false
	}
	for surface in state.surfaces[:state.surface_count] {
		if surface.required_profile != state.renderer.id {
			return false
		}
		if _, view_ok := resolve_view(state, surface.view); !view_ok {
			return false
		}
	}
	visited: [MAX_COMPOSITION_NODES]bool
	surface_references: [MAX_LIVE_SURFACES]u16
	work: u64
	if !validate_node(state, state.root_node, 0, &visited, &surface_references, &work) {
		return false
	}
	for index in 0 ..< state.node_count {
		if !visited[index] {
			return false
		}
	}
	for index in 0 ..< state.surface_count {
		if popup_surface_references[index] > 1 ||
		   (popup_surface_references[index] == 1 && surface_references[index] != 0) ||
		   (popup_surface_references[index] == 0 && surface_references[index] != 1) {
			return false
		}
	}
	state.accounting.geometry_work = work + popup_geometry_work
	state.accounting.snapshot_bytes = u64(state.projection_count * size_of(Projection_Descriptor)) +
		u64(state.view_count * size_of(Visual_View_Descriptor)) +
		u64(state.terminal_row_count * size_of(Terminal_Row)) +
		u64(state.terminal_cell_count * size_of(Terminal_Cell)) +
		u64(state.list_item_count * size_of(List_Item_Descriptor)) +
		u64(len(state.list_content)) +
		u64(state.tree_node_count * size_of(Tree_Node_Descriptor)) +
		u64(len(state.tree_content)) +
		u64(state.input_choice_count * size_of(Input_Choice_Descriptor)) +
		u64(len(state.input_content)) +
		u64(state.surface_count * size_of(Surface_Descriptor)) +
		u64(state.node_count * size_of(Composition_Descriptor)) +
		u64(state.status_count * size_of(Status_Region_Descriptor)) +
		u64(state.popup_count * size_of(Popup_Descriptor)) +
		state.accounting.compact_region_bytes +
		u64(state.style_count * size_of(Style_Descriptor)) +
		u64(state.decoration_count * size_of(Decoration_Descriptor))
	return state.accounting.snapshot_bytes <= state.registry.limits.snapshot_bytes &&
		state.accounting.geometry_work <= state.registry.limits.geometry_work
}

@(private)
popup_contract_is_valid :: proc(state: ^Generation_State, popup: Popup_Descriptor) -> bool {
	if state == nil || !popup_descriptor_shape_is_valid(popup) ||
	   !popup_input_mode_is_supported(popup) ||
	   popup.required_profile != state.renderer.id ||
	   popup.presentation_profile.definition.required_capabilities & state.renderer.capabilities !=
		popup.presentation_profile.definition.required_capabilities ||
	   popup.content_surface == popup.anchor.source_surface ||
	   popup.content_surface == state.focus.target {
		return false
	}
	if _, anchor_ok := resolve_popup_anchor(state, popup); !anchor_ok {
		return false
	}
	source, source_ok := resolve_surface(state, popup.anchor.source_surface)
	content, content_ok := resolve_surface(state, popup.content_surface)
	if !source_ok || !source.visible || !content_ok || !content.visible || content.focusable ||
	   (popup.behavior == .Interactive &&
	    (!source.focusable || state.focus.target != popup.anchor.source_surface)) {
		return false
	}
	content_view, view_ok := resolve_view(state, content.view)
	if !view_ok || (popup.behavior == .Interactive && content_view.kind != .List_View) {
		return false
	}
	projection, projection_ok := resolve_projection(state, content_view.projection)
	if !projection_ok || u64(popup.content_bytes) > projection.byte_count ||
	   u64(projection.model.generation) != popup.content_generation {
		return false
	}
	if active := state.registry.active; active != nil && active.popup_count > 0 {
		previous := active.popups[0]
		if previous.id == popup.id && popup.generation <= previous.generation {
			return false
		}
	}
	return true
}

@(private)
popup_input_mode_is_supported :: proc(popup: Popup_Descriptor) -> bool {
	return (popup.behavior == .Informational &&
		popup.input_policy == .Preserve_Source_Focus) ||
		(popup.behavior == .Interactive && popup.input_policy == .Transient_Capture)
}

@(private)
proposal_preserve_transient_capture :: proc(
	state, previous: ^Generation_State,
) {
	if state == nil || previous == nil || !previous.focus.transient.active do return
	prior := previous.focus.transient
	for popup in state.popups[:state.popup_count] {
		if popup.id != prior.popup_id || popup.owner_id != prior.owner_id ||
		   popup.generation <= prior.popup_generation ||
		   popup.owner_generation < prior.owner_generation ||
		   popup.behavior != .Interactive || popup.input_policy != .Transient_Capture {
			continue
		}
		state.focus.transient = {
			active = true,
			popup = popup.handle,
			popup_id = popup.id,
			popup_generation = popup.generation,
			owner_id = popup.owner_id,
			owner_generation = popup.owner_generation,
			source_surface = popup.anchor.source_surface,
		}
		return
	}
}

@(private)
decoration_contract_is_valid :: proc(
	state: ^Generation_State,
	descriptor: Decoration_Descriptor,
) -> bool {
	if !decoration_shape_is_valid(state, descriptor) do return false
	if _, projection_ok := resolve_projection(state, descriptor.projection); !projection_ok do return false
	return decoration_projection_is_valid(state, descriptor)
}

@(private)
decoration_shape_is_valid :: proc(
	state: ^Generation_State,
	descriptor: Decoration_Descriptor,
) -> bool {
	return state != nil && descriptor.owner_id != Owner_ID(0) &&
		descriptor.kind != .Invalid && descriptor.end >= descriptor.start &&
		resolve_style_role(state, descriptor.style_role)
}

@(private)
decoration_projection_is_valid :: proc(
	state: ^Generation_State,
	descriptor: Decoration_Descriptor,
) -> bool {
	if descriptor.kind != .Text_Range && descriptor.kind != .Diagnostic {
		return true
	}
	text_view, found := resolve_text_view_projection(state, descriptor.projection)
	return found && (descriptor.kind == .Diagnostic || descriptor.start < descriptor.end) &&
		descriptor.end <= text_view.text.source_text_bytes &&
		descriptor.source_revision == text_view.text.revision
}

@(private)
resolve_text_view_projection :: proc(
	state: ^Generation_State,
	projection: Object_Handle,
) -> (^Visual_View_Descriptor, bool) {
	if state == nil {
		return nil, false
	}
	for &view in state.views[:state.view_count] {
		if view.kind == .Text_View && view.text.present && view.projection == projection {
			return &view, true
		}
	}
	return nil, false
}

@(private)
decoration_follows_prior_ranges :: proc(
	state: ^Generation_State,
	descriptor: Decoration_Descriptor,
) -> bool {
	if state == nil do return false
	for index := state.decoration_count - 1; index >= 0; index -= 1 {
		prior := state.decorations[index]
		if prior.kind == .Text_Range && prior.projection == descriptor.projection {
			return prior.end <= descriptor.start
		}
	}
	return true
}

@(private)
validate_node :: proc(
	state: ^Generation_State,
	handle: Object_Handle,
	depth: u16,
	visited: ^[MAX_COMPOSITION_NODES]bool,
	surface_references: ^[MAX_LIVE_SURFACES]u16,
	work: ^u64,
) -> bool {
	node, valid := resolve_node(state, handle)
	if !valid || visited[node.handle.slot] || depth > state.registry.limits.split_depth {
		return false
	}
	visited[node.handle.slot] = true
	work^ += 1
	switch node.kind {
	case .Surface:
		surface, surface_ok := resolve_surface(state, node.surface)
		if !surface_ok || node.first.object_id != Object_ID(0) ||
		   node.second.object_id != Object_ID(0) ||
		   node.orientation != .Invalid || node.panel_child.object_id != Object_ID(0) ||
		   node.panel_edge != .Invalid || node.panel_extent != 0 {
			return false
		}
		surface_references[surface.handle.slot] += 1
		return true
	case .Split:
		if node.surface.object_id != Object_ID(0) || node.first == node.second ||
		   node.first_weight == 0 || node.second_weight == 0 ||
		   (node.orientation != .Above_Below && node.orientation != .Left_Right) ||
		   node.panel_child.object_id != Object_ID(0) || node.panel_edge != .Invalid ||
		   node.panel_extent != 0 {
			return false
		}
		return validate_node(state, node.first, depth + 1, visited, surface_references, work) &&
			validate_node(state, node.second, depth + 1, visited, surface_references, work)
	case .Panel:
		if node.surface.object_id != Object_ID(0) ||
		   node.first.object_id != Object_ID(0) || node.second.object_id != Object_ID(0) ||
		   node.orientation != .Invalid || node.panel_child.object_id == Object_ID(0) ||
		   node.panel_edge == .Invalid || node.panel_extent == 0 {
			return false
		}
		return validate_node(
			state, node.panel_child, depth + 1, visited, surface_references, work,
		)
	case .Invalid:
		return false
	}
	return false
}
