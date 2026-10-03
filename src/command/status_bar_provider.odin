// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../bridge"
import "../interaction"
import "../status_bar"
import endian "core:encoding/endian"
import "core:unicode/utf8"

/* Status_Bar_Provider_Request borrows one validated Racket proposal for immediate native copying. */
Status_Bar_Provider_Request :: struct {
	expected_scope:    bridge.Status_Bar_Scope_Record,
	operation:         bridge.Status_Bar_Capability_Operation,
	expected_provider: status_bar.Provider_Handle,
	segment_count:     u16,
	provider:          status_bar.Provider_Proposal,
	segments:          [status_bar.MAX_PROGRAMMABLE_SEGMENTS_PER_PROVIDER]status_bar.Programmable_Segment_Proposal,
}

/* status_bar_provider_request_decode validates copied records and resolves admitted commands. */
status_bar_provider_request_decode :: proc(
	input: []u8,
	operation: bridge.Status_Bar_Capability_Operation,
	commands: ^interaction.Command_Registry,
) -> (request: Status_Bar_Provider_Request, ok: bool, failure: bridge.Status_Bar_Bridge_Failure_Code) {
	if commands == nil || len(input) < int(bridge.STATUS_BAR_PROPOSAL_HEADER_BYTES) {
		return {}, false, .Invalid_Schema
	}
	request.expected_scope, ok = bridge.status_bar_scope_record_decode(
		input[:int(bridge.STATUS_BAR_SCOPE_RECORD_BYTES)],
	)
	if !ok || status_bar_request_word(input, 96) != u64(operation) {
		return {}, false, .Invalid_Scope
	}
	expected_access := status_bar_provider_operation_access(operation)
	if expected_access == 0 || request.expected_scope.access != expected_access {
		return {}, false, .Access_Denied
	}
	stats, stats_ok, _ := interaction.command_registry_stats(commands)
	if !stats_ok || request.expected_scope.command_registry_generation != u64(stats.generation) {
		return {}, false, .Stale_Scope
	}
	request.operation = operation
	registry_id := status_bar.Registry_ID(request.expected_scope.registry_id)
	expected_id := status_bar.Provider_ID(status_bar_request_word(input, 104))
	expected_generation := status_bar.Provider_Generation(status_bar_request_word(input, 112))
	request.expected_provider = {
		registry_id = registry_id,
		provider_id = expected_id,
		provider_generation = expected_generation,
	}
	provider_id := status_bar.Provider_ID(status_bar_request_word(input, 128))
	provider_generation := status_bar.Provider_Generation(status_bar_request_word(input, 136))
	provider_kind := status_bar_request_word(input, 144)
	segment_count := status_bar_request_word(input, 152)
	text_bytes := status_bar_request_word(input, 192)
	callback_budget := status_bar_request_word(input, 200)
	required, width_ok := bridge.status_bar_proposal_record_bytes(segment_count, text_bytes)
	if !width_ok || required != u64(len(input)) || callback_budget != 1 ||
	   status_bar_request_word(input, 120) != request.expected_scope.definition_generation ||
	   provider_kind != u64(bridge.Status_Bar_Provider_Kind.Package) ||
	   provider_id != expected_id || provider_generation != expected_generation {
		return {}, false, .Invalid_Schema
	}
	has_proposal := operation == .Register || operation == .Replace
	if has_proposal != (segment_count > 0) ||
	   (!has_proposal && text_bytes != 0) ||
	   (operation == .Register && (expected_id != 0 || expected_generation != 0)) ||
	   (operation != .Register && (expected_id == 0 || expected_generation == 0)) {
		return {}, false, .Invalid_Provider
	}
	text_start := bridge.STATUS_BAR_PROPOSAL_HEADER_BYTES +
	              segment_count * bridge.STATUS_BAR_SEGMENT_RECORD_BYTES
	cursor := text_start
	provider_name, range_ok := status_bar_request_text(
		input,
		status_bar_request_word(input, 160),
		status_bar_request_word(input, 168),
		cursor,
	)
	if !range_ok do return {}, false, .Invalid_Schema
	cursor += u64(len(provider_name))
	package_name := ""
	package_name, range_ok = status_bar_request_text(
		input,
		status_bar_request_word(input, 176),
		status_bar_request_word(input, 184),
		cursor,
	)
	if !range_ok do return {}, false, .Invalid_Schema
	cursor += u64(len(package_name))
	if has_proposal && (len(provider_name) == 0 || len(package_name) == 0) {
		return {}, false, .Invalid_Provider
	}
	request.provider.provider_name = provider_name
	request.provider.package_name = package_name
	request.segment_count = u16(segment_count)
	for index in 0..<int(segment_count) {
		record_offset := int(bridge.STATUS_BAR_PROPOSAL_HEADER_BYTES) +
		                 index * int(bridge.STATUS_BAR_SEGMENT_RECORD_BYTES)
		record, record_ok := bridge.status_bar_segment_record_decode(
			input[record_offset:record_offset + int(bridge.STATUS_BAR_SEGMENT_RECORD_BYTES)],
		)
		if !record_ok || record.provider_id != u64(provider_id) ||
		   record.provider_generation != u64(provider_generation) ||
		   record.segment_id != 0 || record.segment_generation != 0 ||
		   record.state != u64(bridge.Status_Bar_Provider_State.Registered) ||
		   record.kind != u64(status_bar.Segment_Kind.Miscellaneous) ||
		   record.group < u64(status_bar.Group.Left) || record.group > u64(status_bar.Group.Right) ||
		   record.order > u64(max(u16)) || record.priority > u64(max(u16)) ||
		   record.omittable > 1 || record.truncatable > 1 ||
		   !status_bar_provider_role_is_admitted(record.style_role) {
			return {}, false, .Invalid_Segment
		}
		segment := &request.segments[index]
		segment.kind = .Miscellaneous
		segment.group = status_bar.Group(record.group)
		segment.order = u16(record.order)
		segment.priority = u16(record.priority)
		segment.omittable = record.omittable == 1
		segment.truncatable = record.truncatable == 1
		segment.style_role = status_bar.Semantic_Role(record.style_role)
		text_ranges := [?][2]u64 {
			{record.identity_offset, record.identity_bytes},
			{record.full_text_offset, record.full_text_bytes},
			{record.compact_text_offset, record.compact_text_bytes},
			{record.inspection_offset, record.inspection_bytes},
			{record.primary_command_offset, record.primary_command_bytes},
			{record.secondary_command_offset, record.secondary_command_bytes},
		}
		values: [6]string
		for text_range, text_index in text_ranges {
			values[text_index], range_ok = status_bar_request_text(
				input, text_range[0], text_range[1], cursor,
			)
			if !range_ok do return {}, false, .Invalid_Schema
			cursor += text_range[1]
		}
		segment.identity = values[0]
		segment.full_text = values[1]
		segment.compact_text = values[2]
		segment.inspection_text = values[3]
		segment.primary_command, ok = status_bar_provider_command_reference(commands, values[4])
		if !ok do return {}, false, .Command_Not_Admitted
		segment.secondary_command, ok = status_bar_provider_command_reference(commands, values[5])
		if !ok do return {}, false, .Command_Not_Admitted
	}
	if cursor != required do return {}, false, .Invalid_Schema
	return request, true, .None
}

/* status_bar_provider_request_proposal repairs the self-borrow after value return. */
status_bar_provider_request_proposal :: proc(
	request: ^Status_Bar_Provider_Request,
) -> status_bar.Provider_Proposal {
	if request == nil || request.segment_count > status_bar.MAX_PROGRAMMABLE_SEGMENTS_PER_PROVIDER {
		return {}
	}
	proposal := request.provider
	proposal.segments = request.segments[:request.segment_count]
	return proposal
}

@(private)
status_bar_provider_operation_access :: proc(
	operation: bridge.Status_Bar_Capability_Operation,
) -> u64 {
	switch operation {
	case .Inspect: return u64(bridge.Status_Bar_Capability_Access.Inspect)
	case .Register: return u64(bridge.Status_Bar_Capability_Access.Register)
	case .Replace: return u64(bridge.Status_Bar_Capability_Access.Replace)
	case .Remove: return u64(bridge.Status_Bar_Capability_Access.Remove)
	case .Teardown: return u64(bridge.Status_Bar_Capability_Access.Teardown)
	case .Scope:
	}
	return 0
}

@(private)
status_bar_provider_command_reference :: proc(
	commands: ^interaction.Command_Registry,
	name: string,
) -> (reference: status_bar.Command_Reference, ok: bool) {
	if len(name) == 0 do return {}, true
	handle, found, _ := interaction.command_lookup(commands, name)
	if !found do return {}, false
	return status_bar.Command_Reference {
		registry_generation = u64(handle.registry_generation),
		slot = handle.slot,
		entry_generation = handle.entry_generation,
	}, true
}

@(private)
status_bar_provider_role_is_admitted :: proc(value: u64) -> bool {
	return value == u64(status_bar.Semantic_Role.Ordinary) ||
	       value == u64(status_bar.Semantic_Role.Context) ||
	       value == u64(status_bar.Semantic_Role.Editing_Context) ||
	       value == u64(status_bar.Semantic_Role.Disabled)
}

@(private)
status_bar_request_text :: proc(
	input: []u8,
	offset, count, expected_offset: u64,
) -> (string, bool) {
	if offset != expected_offset || offset > u64(len(input)) || count > u64(len(input)) - offset {
		return "", false
	}
	value := string(input[int(offset):int(offset + count)])
	return value, utf8.valid_string(value)
}

@(private)
status_bar_request_word :: proc(input: []u8, offset: int) -> u64 {
	value, ok := endian.get_u64(input[offset:], .Little)
	assert(ok)
	return value
}
