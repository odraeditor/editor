// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package bridge

import "../status_bar"
import "../ui"
import endian "core:encoding/endian"

/* STATUS_BAR_CAPABILITY_SCHEMA_VERSION identifies the first programmable segment ABI. */
STATUS_BAR_CAPABILITY_SCHEMA_VERSION :: u64(1)
/* MAX_STATUS_BAR_PROVIDERS bounds package owners retained for one editor session. */
MAX_STATUS_BAR_PROVIDERS :: u64(status_bar.MAX_PROGRAMMABLE_PROVIDERS)
/* MAX_STATUS_BAR_EXTENSION_SEGMENTS bounds one package contribution. */
MAX_STATUS_BAR_EXTENSION_SEGMENTS :: u64(status_bar.MAX_PROGRAMMABLE_SEGMENTS_PER_PROVIDER)
/* MAX_STATUS_BAR_IDENTITY_BYTES bounds one stable package segment identity. */
MAX_STATUS_BAR_IDENTITY_BYTES :: u64(status_bar.MAX_PROGRAMMABLE_IDENTITY_BYTES)
/* MAX_STATUS_BAR_PROVIDER_NAME_BYTES bounds one copied provider name. */
MAX_STATUS_BAR_PROVIDER_NAME_BYTES :: u64(status_bar.MAX_PROGRAMMABLE_PROVIDER_NAME_BYTES)
/* MAX_STATUS_BAR_PACKAGE_NAME_BYTES bounds one copied package identity. */
MAX_STATUS_BAR_PACKAGE_NAME_BYTES :: u64(status_bar.MAX_PROGRAMMABLE_PACKAGE_NAME_BYTES)
/* MAX_STATUS_BAR_COMMAND_NAME_BYTES mirrors the admitted UI command-name ceiling. */
MAX_STATUS_BAR_COMMAND_NAME_BYTES :: u64(ui.MAX_ROLE_COMMAND_NAME_BYTES)
/* MAX_STATUS_BAR_DIAGNOSTIC_BYTES mirrors the Status Bar inspection-text ceiling. */
MAX_STATUS_BAR_DIAGNOSTIC_BYTES :: u64(status_bar.MAX_SEGMENT_TEXT_BYTES)
/* MAX_STATUS_BAR_PROPOSAL_TEXT_BYTES bounds every copied proposal text field. */
MAX_STATUS_BAR_PROPOSAL_TEXT_BYTES :: MAX_STATUS_BAR_PROVIDER_NAME_BYTES +
	MAX_STATUS_BAR_PACKAGE_NAME_BYTES + MAX_STATUS_BAR_EXTENSION_SEGMENTS *
	(MAX_STATUS_BAR_IDENTITY_BYTES + 3 * u64(status_bar.MAX_SEGMENT_TEXT_BYTES) +
		2 * MAX_STATUS_BAR_COMMAND_NAME_BYTES)

/* STATUS_BAR_SCOPE_RECORD_BYTES is one exact session and registry scope. */
STATUS_BAR_SCOPE_RECORD_BYTES :: u64(96)
/* STATUS_BAR_USAGE_RECORD_BYTES publishes exact retained and hosted-turn accounting. */
STATUS_BAR_USAGE_RECORD_BYTES :: u64(56)
/* STATUS_BAR_LIMITS_RECORD_BYTES publishes the complete copied resource policy. */
STATUS_BAR_LIMITS_RECORD_BYTES :: u64(120)
/* STATUS_BAR_SNAPSHOT_HEADER_BYTES precedes providers, segments, and copied text. */
STATUS_BAR_SNAPSHOT_HEADER_BYTES :: u64(312)
/* STATUS_BAR_PROVIDER_RECORD_BYTES is one pointer-free package owner. */
STATUS_BAR_PROVIDER_RECORD_BYTES :: u64(80)
/* STATUS_BAR_SEGMENT_RECORD_BYTES is one pointer-free segment definition. */
STATUS_BAR_SEGMENT_RECORD_BYTES :: u64(192)
/* STATUS_BAR_PROPOSAL_HEADER_BYTES precedes one complete lifecycle proposal. */
STATUS_BAR_PROPOSAL_HEADER_BYTES :: u64(208)
/* STATUS_BAR_OUTCOME_RECORD_BYTES is one copied lifecycle result. */
STATUS_BAR_OUTCOME_RECORD_BYTES :: u64(184)
/* STATUS_BAR_DIAGNOSTIC_RECORD_BYTES precedes one bounded failure message. */
STATUS_BAR_DIAGNOSTIC_RECORD_BYTES :: u64(96)
/* MAX_STATUS_BAR_PROPOSAL_BYTES bounds one complete copied package proposal. */
MAX_STATUS_BAR_PROPOSAL_BYTES :: STATUS_BAR_PROPOSAL_HEADER_BYTES +
	MAX_STATUS_BAR_EXTENSION_SEGMENTS * STATUS_BAR_SEGMENT_RECORD_BYTES +
	MAX_STATUS_BAR_PROPOSAL_TEXT_BYTES
/* MAX_STATUS_BAR_INSPECTION_BYTES bounds one complete copied registry snapshot. */
MAX_STATUS_BAR_INSPECTION_BYTES :: STATUS_BAR_SNAPSHOT_HEADER_BYTES +
	MAX_STATUS_BAR_PROVIDERS * STATUS_BAR_PROVIDER_RECORD_BYTES +
	u64(status_bar.MAX_SEGMENTS) * STATUS_BAR_SEGMENT_RECORD_BYTES +
	MAX_STATUS_BAR_PROPOSAL_TEXT_BYTES + STATUS_BAR_DIAGNOSTIC_RECORD_BYTES +
	MAX_STATUS_BAR_DIAGNOSTIC_BYTES

/* Status_Bar_Capability_Operation identifies one admitted synchronous request. */
Status_Bar_Capability_Operation :: enum i32 {
	Scope = 1,
	Inspect = 2,
	Register = 3,
	Replace = 4,
	Remove = 5,
	Teardown = 6,
}

/* Status_Bar_Capability_Access names checked authority without native ownership. */
Status_Bar_Capability_Access :: enum u64 {
	Inspect = 1,
	Register = 2,
	Replace = 3,
	Remove = 4,
	Teardown = 5,
}

/* Status_Bar_Provider_Kind distinguishes the built-in owner from packages. */
Status_Bar_Provider_Kind :: enum u64 {
	Built_In = 1,
	Package = 2,
}

/* Status_Bar_Provider_State is the copied lifecycle state of one provider. */
Status_Bar_Provider_State :: enum u64 {
	Registered = 1,
	Confirmed = 2,
	Rejected = 3,
	Closed = 4,
}

/* Status_Bar_Completion identifies a confirmed or rejected lifecycle outcome. */
Status_Bar_Completion :: enum u64 {
	Confirmed = 1,
	Rejected = 2,
}

/* Status_Bar_Bridge_Failure_Code classifies one bounded boundary rejection. */
Status_Bar_Bridge_Failure_Code :: enum u64 {
	None,
	Invalid_Schema,
	Access_Denied,
	Invalid_Scope,
	Stale_Scope,
	Invalid_Provider,
	Stale_Provider,
	Provider_Limit,
	Duplicate_Provider,
	Invalid_Segment,
	Segment_Limit,
	Duplicate_Segment,
	Factory_Identity_Conflict,
	Text_Limit,
	Invalid_Style,
	Command_Not_Admitted,
	Proposal_Limit,
	Generation_Limit,
	Allocation,
}

/* Status_Bar_Scope_Record binds capability use to exact native generations. */
Status_Bar_Scope_Record :: struct {
	schema_version:              u64,
	access:                      u64,
	session_id:                  u64,
	session_generation:          u64,
	registry_id:                 u64,
	registry_generation:         u64,
	definition_generation:       u64,
	provider_id:                 u64,
	provider_generation:         u64,
	command_registry_generation: u64,
	presentation_generation:     u64,
	capability_generation:       u64,
}

/* Status_Bar_Usage_Record publishes exact registry and bridge accounting. */
Status_Bar_Usage_Record :: struct {
	providers:             u64,
	segments:              u64,
	retained_bytes:        u64,
	inspection_bytes:      u64,
	preparation_peak_bytes: u64,
	operations_in_turn:    u64,
	hosted_turns:          u64,
}

/* Status_Bar_Limits_Record publishes every selected programmable-segment bound. */
Status_Bar_Limits_Record :: struct {
	providers:             u64,
	segments_per_provider: u64,
	total_segments:        u64,
	identity_bytes:        u64,
	provider_name_bytes:   u64,
	package_name_bytes:    u64,
	segment_text_bytes:    u64,
	command_name_bytes:    u64,
	retained_bytes:        u64,
	proposal_bytes:        u64,
	operations_per_turn:   u64,
	inspection_bytes:      u64,
	preparation_bytes:     u64,
	diagnostic_bytes:      u64,
	concurrent_hosted_turns: u64,
}

/* Status_Bar_Snapshot_Header_Record describes one complete copied registry view. */
Status_Bar_Snapshot_Header_Record :: struct {
	scope:            Status_Bar_Scope_Record,
	usage:            Status_Bar_Usage_Record,
	limits:           Status_Bar_Limits_Record,
	provider_count:   u64,
	segment_count:    u64,
	diagnostic_count: u64,
	text_bytes:       u64,
	diagnostic_bytes: u64,
}

/* Status_Bar_Provider_Record copies one provider without pointers or callbacks. */
Status_Bar_Provider_Record :: struct {
	provider_id:         u64,
	provider_generation: u64,
	state:               u64,
	name_offset:         u64,
	name_bytes:          u64,
	package_offset:      u64,
	package_bytes:       u64,
	first_segment:       u64,
	segment_count:       u64,
	retained_bytes:      u64,
}

/* Status_Bar_Segment_Record copies one semantic definition and trailing ranges. */
Status_Bar_Segment_Record :: struct {
	provider_id:          u64,
	provider_generation:  u64,
	segment_id:           u64,
	segment_generation:   u64,
	state:                u64,
	kind:                 u64,
	group:                u64,
	order:                u64,
	priority:             u64,
	omittable:            u64,
	truncatable:          u64,
	style_role:           u64,
	identity_offset:      u64,
	identity_bytes:       u64,
	full_text_offset:     u64,
	full_text_bytes:      u64,
	compact_text_offset:  u64,
	compact_text_bytes:   u64,
	inspection_offset:    u64,
	inspection_bytes:     u64,
	primary_command_offset: u64,
	primary_command_bytes:  u64,
	secondary_command_offset: u64,
	secondary_command_bytes:  u64,
}

/* Status_Bar_Proposal_Header_Record carries one optimistic lifecycle request. */
Status_Bar_Proposal_Header_Record :: struct {
	expected_scope:               Status_Bar_Scope_Record,
	operation:                    u64,
	expected_provider_id:         u64,
	expected_provider_generation: u64,
	expected_definition_generation: u64,
	provider_id:                  u64,
	provider_generation:          u64,
	provider_kind:                u64,
	segment_count:                u64,
	provider_name_offset:         u64,
	provider_name_bytes:          u64,
	package_name_offset:          u64,
	package_name_bytes:           u64,
	text_bytes:                   u64,
	callback_budget:              u64,
}

/* Status_Bar_Outcome_Record contains refreshed scope and no retained ownership. */
Status_Bar_Outcome_Record :: struct {
	scope:                 Status_Bar_Scope_Record,
	operation:             u64,
	completion:            u64,
	changed:               u64,
	provider_id:           u64,
	provider_generation:   u64,
	definition_generation: u64,
	segment_count:         u64,
	retained_bytes:        u64,
	operation_count:       u64,
	diagnostic_code:       u64,
	diagnostic_bytes:      u64,
}

/* Status_Bar_Diagnostic_Record copies one stable failure and bounded message. */
Status_Bar_Diagnostic_Record :: struct {
	operation:           u64,
	failure_code:        u64,
	provider_id:         u64,
	provider_generation: u64,
	segment_id:          u64,
	segment_generation:  u64,
	expected_generation: u64,
	actual_generation:   u64,
	limit:               u64,
	actual:              u64,
	message_offset:      u64,
	message_bytes:       u64,
}

/* status_bar_operation_is_authorized checks one closed operation and access pair. */
status_bar_operation_is_authorized :: proc(
	operation: Status_Bar_Capability_Operation,
	access: Status_Bar_Capability_Access,
) -> bool {
	switch operation {
	case .Scope, .Inspect:
		return access == .Inspect
	case .Register:
		return access == .Register
	case .Replace:
		return access == .Replace
	case .Remove:
		return access == .Remove
	case .Teardown:
		return access == .Teardown
	}
	return false
}

/* status_bar_scope_record_is_valid checks exact authority and generation identity. */
status_bar_scope_record_is_valid :: proc(scope: Status_Bar_Scope_Record) -> bool {
	provider_pair := (scope.provider_id == 0) == (scope.provider_generation == 0)
	return scope.schema_version == STATUS_BAR_CAPABILITY_SCHEMA_VERSION &&
	       scope.access >= u64(Status_Bar_Capability_Access.Inspect) &&
	       scope.access <= u64(Status_Bar_Capability_Access.Teardown) &&
	       scope.session_id != 0 && scope.session_generation != 0 &&
	       scope.registry_id != 0 && scope.registry_generation != 0 &&
	       scope.definition_generation != 0 && provider_pair &&
	       scope.command_registry_generation != 0 &&
	       scope.presentation_generation != 0 && scope.capability_generation != 0
}

/* status_bar_proposal_record_bytes validates one complete copied request width. */
status_bar_proposal_record_bytes :: proc(segment_count, text_bytes: u64) -> (u64, bool) {
	if segment_count > MAX_STATUS_BAR_EXTENSION_SEGMENTS ||
	   text_bytes > MAX_STATUS_BAR_PROPOSAL_TEXT_BYTES {
		return 0, false
	}
	bytes := STATUS_BAR_PROPOSAL_HEADER_BYTES +
	         segment_count * STATUS_BAR_SEGMENT_RECORD_BYTES + text_bytes
	return bytes, bytes <= MAX_STATUS_BAR_PROPOSAL_BYTES
}

/* status_bar_snapshot_record_bytes validates one complete copied inspection width. */
status_bar_snapshot_record_bytes :: proc(
	provider_count, segment_count, text_bytes, diagnostic_bytes: u64,
) -> (u64, bool) {
	if provider_count > MAX_STATUS_BAR_PROVIDERS ||
	   segment_count > u64(status_bar.MAX_SEGMENTS) ||
	   text_bytes > MAX_STATUS_BAR_PROPOSAL_TEXT_BYTES ||
	   diagnostic_bytes > MAX_STATUS_BAR_DIAGNOSTIC_BYTES {
		return 0, false
	}
	bytes := STATUS_BAR_SNAPSHOT_HEADER_BYTES +
	         provider_count * STATUS_BAR_PROVIDER_RECORD_BYTES +
	         segment_count * STATUS_BAR_SEGMENT_RECORD_BYTES + text_bytes
	if diagnostic_bytes > 0 {
		bytes += STATUS_BAR_DIAGNOSTIC_RECORD_BYTES + diagnostic_bytes
	}
	return bytes, bytes <= MAX_STATUS_BAR_INSPECTION_BYTES
}

/* status_bar_scope_record_decode decodes one exact little-endian scope. */
status_bar_scope_record_decode :: proc(input: []u8) -> (record: Status_Bar_Scope_Record, ok: bool) {
	if len(input) != int(STATUS_BAR_SCOPE_RECORD_BYTES) do return {}, false
	values: [12]u64
	for &value, index in values {
		value, ok = status_bar_record_word(input, index * 8)
		if !ok do return {}, false
	}
	record = Status_Bar_Scope_Record {
		schema_version = values[0], access = values[1], session_id = values[2],
		session_generation = values[3], registry_id = values[4],
		registry_generation = values[5], definition_generation = values[6],
		provider_id = values[7], provider_generation = values[8],
		command_registry_generation = values[9], presentation_generation = values[10],
		capability_generation = values[11],
	}
	return record, status_bar_scope_record_is_valid(record)
}

/* status_bar_segment_record_decode decodes one exact pointer-free definition. */
status_bar_segment_record_decode :: proc(input: []u8) -> (record: Status_Bar_Segment_Record, ok: bool) {
	if len(input) != int(STATUS_BAR_SEGMENT_RECORD_BYTES) do return {}, false
	values: [24]u64
	for &value, index in values {
		value, ok = status_bar_record_word(input, index * 8)
		if !ok do return {}, false
	}
	record = Status_Bar_Segment_Record {
		provider_id = values[0], provider_generation = values[1],
		segment_id = values[2], segment_generation = values[3], state = values[4],
		kind = values[5], group = values[6], order = values[7], priority = values[8],
		omittable = values[9], truncatable = values[10], style_role = values[11],
		identity_offset = values[12], identity_bytes = values[13],
		full_text_offset = values[14], full_text_bytes = values[15],
		compact_text_offset = values[16], compact_text_bytes = values[17],
		inspection_offset = values[18], inspection_bytes = values[19],
		primary_command_offset = values[20], primary_command_bytes = values[21],
		secondary_command_offset = values[22], secondary_command_bytes = values[23],
	}
	return record, true
}

/* status_bar_record_layout_is_valid verifies every C and Racket ABI width. */
status_bar_record_layout_is_valid :: proc() -> bool {
	return u64(size_of(Status_Bar_Scope_Record)) == STATUS_BAR_SCOPE_RECORD_BYTES &&
	       u64(size_of(Status_Bar_Usage_Record)) == STATUS_BAR_USAGE_RECORD_BYTES &&
	       u64(size_of(Status_Bar_Limits_Record)) == STATUS_BAR_LIMITS_RECORD_BYTES &&
	       u64(size_of(Status_Bar_Snapshot_Header_Record)) == STATUS_BAR_SNAPSHOT_HEADER_BYTES &&
	       u64(size_of(Status_Bar_Provider_Record)) == STATUS_BAR_PROVIDER_RECORD_BYTES &&
	       u64(size_of(Status_Bar_Segment_Record)) == STATUS_BAR_SEGMENT_RECORD_BYTES &&
	       u64(size_of(Status_Bar_Proposal_Header_Record)) == STATUS_BAR_PROPOSAL_HEADER_BYTES &&
	       u64(size_of(Status_Bar_Outcome_Record)) == STATUS_BAR_OUTCOME_RECORD_BYTES &&
	       u64(size_of(Status_Bar_Diagnostic_Record)) == STATUS_BAR_DIAGNOSTIC_RECORD_BYTES
}

@(private)
status_bar_record_word :: proc(input: []u8, offset: int) -> (u64, bool) {
	if offset < 0 || offset + 8 > len(input) do return 0, false
	return endian.get_u64(input[offset:], .Little)
}
