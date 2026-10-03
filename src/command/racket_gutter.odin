// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../bridge"
import "../gutter"
import "../interaction"

/* Racket_Gutter_Provider_Request borrows one decoded personal proposal for immediate copying. */
Racket_Gutter_Provider_Request :: struct {
	provider:     gutter.Programmable_Provider_Proposal,
	lanes:        [gutter.MAX_PROGRAMMABLE_LANES_PER_PROVIDER]gutter.Programmable_Lane_Proposal,
	markers:      [gutter.MAX_PROGRAMMABLE_MARKERS_PER_PROVIDER]gutter.Programmable_Marker_Proposal,
	lane_count:   u8,
	marker_count: u16,
}

/* racket_gutter_provider_request_decode validates copied records and admitted commands. */
racket_gutter_provider_request_decode :: proc(
	input: []u8,
	commands: ^interaction.Command_Registry,
) -> (request: Racket_Gutter_Provider_Request, ok: bool, failure: gutter.Failure_Context) {
	if commands == nil || len(input) < int(bridge.GUTTER_PROVIDER_HEADER_BYTES) {
		return {}, false, racket_gutter_failure(.Invalid_Request)
	}
	header, header_ok := bridge.gutter_provider_record_decode(
		input[:int(bridge.GUTTER_PROVIDER_HEADER_BYTES)],
	)
	if !header_ok || header.proposal_bytes != u64(len(input)) {
		return {}, false, racket_gutter_failure(.Invalid_Request)
	}
	request.lane_count = u8(header.lane_count)
	request.marker_count = u16(header.marker_count)
	request.provider.definition_generation = gutter.Provider_Generation(header.definition_generation)
	request.provider.marker_generation = gutter.Marker_Generation_ID(header.marker_generation)
	request.provider.complete = header.complete == 1
	text_start := bridge.GUTTER_PROVIDER_HEADER_BYTES +
		header.lane_count * bridge.GUTTER_LANE_RECORD_BYTES +
		header.marker_count * bridge.GUTTER_MARKER_RECORD_BYTES
	cursor := text_start
	request.provider.name, ok = bridge.gutter_record_text(
		input,
		header.name_offset,
		header.name_bytes,
		cursor,
		bridge.MAX_GUTTER_PROGRAMMABLE_PROVIDER_NAME_BYTES,
	)
	if !ok do return {}, false, racket_gutter_failure(.Invalid_Request)
	cursor += header.name_bytes
	request.provider.package_name, ok = bridge.gutter_record_text(
		input,
		header.package_offset,
		header.package_bytes,
		cursor,
		bridge.MAX_GUTTER_PROGRAMMABLE_PACKAGE_NAME_BYTES,
	)
	if !ok do return {}, false, racket_gutter_failure(.Invalid_Request)
	cursor += header.package_bytes

	for index in 0 ..< int(header.lane_count) {
		offset := int(bridge.GUTTER_PROVIDER_HEADER_BYTES) + index * int(bridge.GUTTER_LANE_RECORD_BYTES)
		record, record_ok := bridge.gutter_lane_record_decode(
			input[offset:offset + int(bridge.GUTTER_LANE_RECORD_BYTES)],
		)
		if !record_ok || record.definition_generation != header.definition_generation ||
		   record.lane_index != u64(index) || record.order > 65_535 ||
		   record.minimum_cells > u64(max(u16)) || record.maximum_cells > u64(max(u16)) ||
		   record.priority > u64(max(u16)) {
			return {}, false, racket_gutter_failure(.Invalid_Lane)
		}
		lane := &request.lanes[index]
		lane.side, ok = racket_gutter_side(record.side)
		if !ok do return {}, false, racket_gutter_failure(.Invalid_Lane)
		lane.order = i16(i64(record.order) - 32_768)
		lane.attachments, ok = racket_gutter_attachments(record.attachments)
		if !ok do return {}, false, racket_gutter_failure(.Invalid_Lane)
		lane.width_policy, ok = racket_gutter_width(record.width_policy)
		if !ok do return {}, false, racket_gutter_failure(.Invalid_Lane)
		lane.minimum_cells = u16(record.minimum_cells)
		lane.maximum_cells = u16(record.maximum_cells)
		lane.alignment, ok = racket_gutter_alignment(record.alignment)
		if !ok do return {}, false, racket_gutter_failure(.Invalid_Lane)
		lane.visibility, ok = racket_gutter_visibility(record.visibility)
		if !ok do return {}, false, racket_gutter_failure(.Invalid_Lane)
		lane.collision, ok = racket_gutter_collision(record.collision)
		if !ok do return {}, false, racket_gutter_failure(.Invalid_Lane)
		lane.priority = u16(record.priority)
		lane.style_role, ok = racket_gutter_role(record.style_role)
		if !ok do return {}, false, racket_gutter_failure(.Invalid_Lane)
		lane.identity, ok = bridge.gutter_record_text(
			input, record.identity_offset, record.identity_bytes, cursor,
			bridge.MAX_GUTTER_PROGRAMMABLE_IDENTITY_BYTES,
		)
		if !ok do return {}, false, racket_gutter_failure(.Invalid_Lane)
		cursor += record.identity_bytes
		lane.separator.kind = .Glyph
		lane.separator.value, ok = bridge.gutter_record_text(
			input, record.separator_offset, record.separator_bytes, cursor,
			u64(gutter.MAX_REPRESENTATION_BYTES),
		)
		if !ok do return {}, false, racket_gutter_failure(.Invalid_Lane)
		cursor += record.separator_bytes
		lane.separator.fallback, ok = bridge.gutter_record_text(
			input, record.fallback_offset, record.fallback_bytes, cursor,
			u64(gutter.MAX_REPRESENTATION_BYTES),
		)
		if !ok do return {}, false, racket_gutter_failure(.Invalid_Lane)
		cursor += record.fallback_bytes
	}

	markers_start := bridge.GUTTER_PROVIDER_HEADER_BYTES +
		header.lane_count * bridge.GUTTER_LANE_RECORD_BYTES
	for index in 0 ..< int(header.marker_count) {
		offset := int(markers_start) + index * int(bridge.GUTTER_MARKER_RECORD_BYTES)
		record, record_ok := bridge.gutter_marker_record_decode(
			input[offset:offset + int(bridge.GUTTER_MARKER_RECORD_BYTES)],
		)
		if !record_ok || record.definition_generation != header.definition_generation ||
		   record.marker_generation != header.marker_generation ||
		   record.marker_index != u64(index) || record.lane_index >= header.lane_count ||
		   record.priority > u64(max(u16)) || record.representation_kind != u64(gutter.Representation_Kind.Glyph) ||
		   record.stale > 1 || record.action_count > gutter.MAX_ACTIONS_PER_MARKER {
			return {}, false, racket_gutter_failure(.Invalid_Marker)
		}
		marker := &request.markers[index]
		marker.lane_index = u8(record.lane_index)
		marker.logical_line = record.logical_line
		marker.style_role, ok = racket_gutter_role(record.style_role)
		if !ok do return {}, false, racket_gutter_failure(.Invalid_Marker)
		marker.priority = u16(record.priority)
		marker.representation.kind = .Glyph
		marker.stale = record.stale == 1
		marker.identity, ok = bridge.gutter_record_text(
			input, record.identity_offset, record.identity_bytes, cursor,
			bridge.MAX_GUTTER_PROGRAMMABLE_IDENTITY_BYTES,
		)
		if !ok do return {}, false, racket_gutter_failure(.Invalid_Marker)
		cursor += record.identity_bytes
		marker.representation.value, ok = bridge.gutter_record_text(
			input, record.value_offset, record.value_bytes, cursor,
			u64(gutter.MAX_REPRESENTATION_BYTES),
		)
		if !ok do return {}, false, racket_gutter_failure(.Invalid_Marker)
		cursor += record.value_bytes
		marker.representation.fallback, ok = bridge.gutter_record_text(
			input, record.fallback_offset, record.fallback_bytes, cursor,
			u64(gutter.MAX_REPRESENTATION_BYTES),
		)
		if !ok do return {}, false, racket_gutter_failure(.Invalid_Marker)
		cursor += record.fallback_bytes
		marker.aggregation_label, ok = bridge.gutter_record_text(
			input, record.aggregation_offset, record.aggregation_bytes, cursor,
			u64(gutter.MAX_REPRESENTATION_BYTES), true,
		)
		if !ok do return {}, false, racket_gutter_failure(.Invalid_Marker)
		cursor += record.aggregation_bytes
		marker.detail, ok = bridge.gutter_record_text(
			input, record.detail_offset, record.detail_bytes, cursor,
			bridge.MAX_GUTTER_PROGRAMMABLE_DETAIL_BYTES, true,
		)
		if !ok do return {}, false, racket_gutter_failure(.Invalid_Marker)
		cursor += record.detail_bytes
		marker.action_count = u8(record.action_count)
		for action_index in 0 ..< gutter.MAX_ACTIONS_PER_MARKER {
			if action_index >= int(record.action_count) {
				if record.action_offsets[action_index] != 0 || record.action_bytes[action_index] != 0 {
					return {}, false, racket_gutter_failure(.Invalid_Marker)
				}
				continue
			}
			name, name_ok := bridge.gutter_record_text(
				input,
				record.action_offsets[action_index],
				record.action_bytes[action_index],
				cursor,
				bridge.MAX_GUTTER_PROGRAMMABLE_COMMAND_NAME_BYTES,
			)
			if !name_ok do return {}, false, racket_gutter_failure(.Invalid_Marker)
			cursor += record.action_bytes[action_index]
			marker.actions[action_index], ok = racket_gutter_command_reference(commands, name)
			if !ok do return {}, false, racket_gutter_failure(.Invalid_Marker)
		}
	}
	if cursor != header.proposal_bytes || cursor - text_start != header.text_bytes {
		return {}, false, racket_gutter_failure(.Invalid_Request)
	}
	return request, true, {}
}

/* racket_gutter_provider_request_proposal repairs self-borrows after value return. */
racket_gutter_provider_request_proposal :: proc(
	request: ^Racket_Gutter_Provider_Request,
) -> gutter.Programmable_Provider_Proposal {
	if request == nil || request.lane_count == 0 ||
	   request.lane_count > gutter.MAX_PROGRAMMABLE_LANES_PER_PROVIDER ||
	   request.marker_count > gutter.MAX_PROGRAMMABLE_MARKERS_PER_PROVIDER {
		return {}
	}
	proposal := request.provider
	proposal.lanes = request.lanes[:request.lane_count]
	proposal.markers = request.markers[:request.marker_count]
	return proposal
}

@(private)
racket_gutter_command_reference :: proc(
	commands: ^interaction.Command_Registry,
	name: string,
) -> (gutter.Command_Reference, bool) {
	handle, found, _ := interaction.command_lookup(commands, name)
	if !found do return {}, false
	return gutter.Command_Reference {
		registry_generation = u64(handle.registry_generation),
		slot = handle.slot,
		entry_generation = handle.entry_generation,
	}, true
}

@(private)
racket_gutter_side :: proc(value: u64) -> (gutter.Side, bool) {
	switch value {case 1: return .Left, true; case 2: return .Right, true}
	return .Invalid, false
}

@(private)
racket_gutter_attachments :: proc(value: u64) -> (gutter.Attachment_Kinds, bool) {
	if value == 1 do return {.Logical_Line}, true
	return {}, false
}

@(private)
racket_gutter_width :: proc(value: u64) -> (gutter.Width_Policy, bool) {
	switch value {
	case 1: return .Fixed, true
	case 2: return .Automatic, true
	case 3: return .Bounded_Automatic, true
	case 4: return .Content_Presence, true
	}
	return .Invalid, false
}

@(private)
racket_gutter_alignment :: proc(value: u64) -> (gutter.Alignment, bool) {
	switch value {case 1: return .Left, true; case 2: return .Center, true; case 3: return .Right, true}
	return .Invalid, false
}

@(private)
racket_gutter_visibility :: proc(value: u64) -> (gutter.Visibility_Policy, bool) {
	switch value {case 1: return .Always, true; case 2: return .When_Content, true; case 3: return .Configured, true}
	return .Invalid, false
}

@(private)
racket_gutter_collision :: proc(value: u64) -> (gutter.Collision_Policy, bool) {
	switch value {
	case 1: return .Highest_Priority, true
	case 2: return .Stack, true
	case 3: return .Aggregate, true
	case 4: return .Primary_With_Details, true
	}
	return .Invalid, false
}

@(private)
racket_gutter_role :: proc(value: u64) -> (gutter.Semantic_Role, bool) {
	role := gutter.Semantic_Role(value)
	if role == .Ordinary || role == .Background || role == .Separator ||
	   (role >= .Diagnostic_Error && role <= .Unavailable) {
		return role, true
	}
	return .Invalid, false
}

@(private)
racket_gutter_failure :: proc(code: gutter.Failure_Code) -> gutter.Failure_Context {
	return gutter.Failure_Context{operation = .Copy, code = code}
}
