// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery_bridge

import "../ksawery"
import "core:unicode/utf8"

/* KSAWERY_CONFLICT_ASSISTANCE_SCHEMA_VERSION identifies the initial helper ABI. */
KSAWERY_CONFLICT_ASSISTANCE_SCHEMA_VERSION :: u64(1)
/* KSAWERY_CONFLICT_ASSISTANCE_PROVIDER_BYTES is one provider declaration header. */
KSAWERY_CONFLICT_ASSISTANCE_PROVIDER_BYTES :: u64(144)
/* KSAWERY_CONFLICT_ASSISTANCE_OBSERVATION_BYTES is one exact Conflict header. */
KSAWERY_CONFLICT_ASSISTANCE_OBSERVATION_BYTES :: u64(160)
/* KSAWERY_CONFLICT_ASSISTANCE_SIDE_BYTES is one copied material reference. */
KSAWERY_CONFLICT_ASSISTANCE_SIDE_BYTES :: u64(64)
/* KSAWERY_CONFLICT_ASSISTANCE_SELECTION_BYTES is one role-selection transition. */
KSAWERY_CONFLICT_ASSISTANCE_SELECTION_BYTES :: u64(160)
/* KSAWERY_CONFLICT_ASSISTANCE_RESPONSE_BYTES is one provider response header. */
KSAWERY_CONFLICT_ASSISTANCE_RESPONSE_BYTES :: u64(128)

/* Ksawery_Conflict_Assistance_Provider_Record declares one helper generation. */
Ksawery_Conflict_Assistance_Provider_Record :: struct {
	schema_version:              u64,
	record_bytes:                u64,
	origin:                      u64,
	contributor_generation:      u64,
	contribution_id:             u64,
	provider_id:                 u64,
	provider_generation:         u64,
	supported_classes:           u64,
	capabilities:                u64,
	lifecycle:                   u64,
	contributor_identity_offset: u64,
	contributor_identity_bytes:  u64,
	identity_offset:             u64,
	identity_bytes:              u64,
	label_offset:                u64,
	label_bytes:                 u64,
	payload_bytes:               u64,
	reserved:                    u64,
}

/* Ksawery_Conflict_Assistance_Observation_Record describes one exact Conflict copy. */
Ksawery_Conflict_Assistance_Observation_Record :: struct {
	schema_version:              u64,
	record_bytes:                u64,
	repository_generation:       u64,
	worktree_generation:         u64,
	observation_generation:      u64,
	sequence_generation:         u64,
	sequence_fingerprint:        u64,
	conflict_id:                 u64,
	conflict_kind:               u64,
	classes:                     u64,
	side_count:                  u64,
	payload_bytes:               u64,
	repository_offset:           u64,
	repository_bytes:            u64,
	path_offset:                 u64,
	path_bytes:                  u64,
	truncated:                   u64,
	reserved_0:                  u64,
	reserved_1:                  u64,
	reserved_2:                  u64,
}

/* Ksawery_Conflict_Assistance_Side_Record points into copied Conflict payload. */
Ksawery_Conflict_Assistance_Side_Record :: struct {
	kind:                        u64,
	material:                    u64,
	mode:                        u64,
	object_offset:               u64,
	object_bytes:                u64,
	content_offset:              u64,
	content_bytes:               u64,
	truncated:                   u64,
}

/* Ksawery_Conflict_Assistance_Selection_Record declares selection or replacement. */
Ksawery_Conflict_Assistance_Selection_Record :: struct {
	schema_version:              u64,
	record_bytes:                u64,
	action:                      u64,
	selection_id:                u64,
	previous_generation:         u64,
	next_generation:             u64,
	scope:                       u64,
	provider_origin:             u64,
	contributor_generation:      u64,
	provider_id:                 u64,
	provider_generation:         u64,
	scope_identity_offset:       u64,
	scope_identity_bytes:        u64,
	repository_offset:           u64,
	repository_bytes:            u64,
	session:                     u64,
	confirmed:                   u64,
	payload_bytes:               u64,
	contributor_identity_offset: u64,
	contributor_identity_bytes:  u64,
}

/* Ksawery_Conflict_Assistance_Response_Record declares one bounded provider result. */
Ksawery_Conflict_Assistance_Response_Record :: struct {
	schema_version:              u64,
	record_bytes:                u64,
	request_id:                  u64,
	provider_id:                 u64,
	provider_generation:         u64,
	kind:                        u64,
	tool_access:                 u64,
	guidance_offset:             u64,
	guidance_bytes:              u64,
	operation_offset:            u64,
	operation_bytes:             u64,
	diagnostic_code:             u64,
	diagnostic_offset:           u64,
	diagnostic_bytes:            u64,
	payload_bytes:               u64,
	contributor_generation:      u64,
}

/* Ksawery_Conflict_Assistance_Record_Failure_Code classifies helper ABI rejection. */
Ksawery_Conflict_Assistance_Record_Failure_Code :: enum u16 {
	None,
	Unsupported_Schema,
	Invalid_Header,
	Size_Mismatch,
	Count_Mismatch,
	Invalid_Range,
	Invalid_Text,
	Invalid_Provider,
	Invalid_Observation,
	Invalid_Side,
	Invalid_Selection,
	Invalid_Response,
	Content_Limit,
	Copy_Limit,
}

/* Ksawery_Conflict_Assistance_Record_Failure retains one rejected field. */
Ksawery_Conflict_Assistance_Record_Failure :: struct {
	code:   Ksawery_Conflict_Assistance_Record_Failure_Code,
	index:  u64,
	limit:  u64,
	actual: u64,
}

/* ksawery_conflict_assistance_provider_record_validate rejects malformed declarations. */
ksawery_conflict_assistance_provider_record_validate :: proc(
	record: Ksawery_Conflict_Assistance_Provider_Record,
	payload: []u8,
) -> Ksawery_Conflict_Assistance_Record_Failure {
	if record.schema_version != KSAWERY_CONFLICT_ASSISTANCE_SCHEMA_VERSION {
		return {code = .Unsupported_Schema, actual = record.schema_version}
	}
	expected := KSAWERY_CONFLICT_ASSISTANCE_PROVIDER_BYTES + u64(len(payload))
	if record.record_bytes != expected || record.payload_bytes != u64(len(payload)) {
		return {code = .Size_Mismatch, limit = expected, actual = record.record_bytes}
	}
	if record.origin != u64(ksawery.Conflict_Assistance_Provider_Origin.Extension) ||
	   record.contributor_generation == 0 || record.contribution_id == 0 ||
	   record.provider_id <= u64(ksawery.BUILT_IN_CONFLICT_ASSISTANCE_PROVIDER_ID) ||
	   record.provider_generation == 0 || record.supported_classes == 0 ||
	   record.supported_classes & ~u64(0x3fe) != 0 || record.capabilities == 0 ||
	   record.capabilities & ~u64(0x7) != 0 || record.lifecycle == 0 ||
	   record.lifecycle > u64(ksawery.Conflict_Assistance_Provider_Lifecycle.Closed) ||
	   record.reserved != 0 {
		return {code = .Invalid_Provider}
	}
	if !ksawery_conflict_assistance_text_range_is_valid(
		payload, record.contributor_identity_offset, record.contributor_identity_bytes,
		u64(ksawery.MAX_EXTENSION_IDENTITY_BYTES), false,
	) || !ksawery_conflict_assistance_text_range_is_valid(
		payload, record.identity_offset, record.identity_bytes,
		u64(ksawery.MAX_EXTENSION_IDENTITY_BYTES), false,
	) || !ksawery_conflict_assistance_text_range_is_valid(
		payload, record.label_offset, record.label_bytes,
		u64(ksawery.MAX_EXTENSION_LABEL_BYTES), false,
	) {
		return {code = .Invalid_Text}
	}
	return {}
}

/* ksawery_conflict_assistance_observation_record_validate checks exact copied material. */
ksawery_conflict_assistance_observation_record_validate :: proc(
	record: Ksawery_Conflict_Assistance_Observation_Record,
	sides: []Ksawery_Conflict_Assistance_Side_Record,
	payload: []u8,
) -> Ksawery_Conflict_Assistance_Record_Failure {
	if record.schema_version != KSAWERY_CONFLICT_ASSISTANCE_SCHEMA_VERSION {
		return {code = .Unsupported_Schema, actual = record.schema_version}
	}
	expected := KSAWERY_CONFLICT_ASSISTANCE_OBSERVATION_BYTES +
		u64(len(sides)) * KSAWERY_CONFLICT_ASSISTANCE_SIDE_BYTES + u64(len(payload))
	if record.record_bytes != expected || record.payload_bytes != u64(len(payload)) {
		return {code = .Size_Mismatch, limit = expected, actual = record.record_bytes}
	}
	if record.side_count != 4 || len(sides) != 4 {
		return {code = .Count_Mismatch, limit = 4, actual = u64(len(sides))}
	}
	if record.repository_generation == 0 || record.worktree_generation == 0 ||
	   record.observation_generation == 0 || record.sequence_generation == 0 ||
	   record.sequence_fingerprint == 0 || record.conflict_id == 0 ||
	   record.conflict_kind == 0 || record.conflict_kind > u64(ksawery.Conflict_Kind.Other) ||
	   record.classes == 0 || record.classes & ~u64(0x3fe) != 0 ||
	   record.truncated > 1 || record.reserved_0 != 0 || record.reserved_1 != 0 ||
	   record.reserved_2 != 0 {
		return {code = .Invalid_Observation}
	}
	if !ksawery_conflict_assistance_text_range_is_valid(
		payload, record.repository_offset, record.repository_bytes,
		u64(ksawery.MAX_REPOSITORY_CONTEXT_BYTES), false,
	) || !ksawery_conflict_assistance_text_range_is_valid(
		payload, record.path_offset, record.path_bytes,
		u64(ksawery.MAX_CONFLICT_ASSISTANCE_PATH_BYTES), false,
	) {
		return {code = .Invalid_Text}
	}
	if payload[int(record.repository_offset)] != '/' {
		return {code = .Invalid_Observation}
	}
	truncated := false
	content_bytes := u64(0)
	for side, index in sides {
		if side.kind != u64(index + 1) || side.material == 0 ||
		   side.material > u64(ksawery.Conflict_Assistance_Material_Kind.Omitted) ||
		   side.truncated > 1 {
			return {code = .Invalid_Side, index = u64(index)}
		}
		if side.material == u64(ksawery.Conflict_Assistance_Material_Kind.Missing) {
			if side.mode != 0 || side.object_offset != 0 || side.object_bytes != 0 ||
			   side.content_offset != 0 || side.content_bytes != 0 || side.truncated != 0 {
				return {code = .Invalid_Side, index = u64(index)}
			}
			continue
		}
		if side.mode == 0 ||
		   (side.kind != u64(ksawery.Conflict_Assistance_Side_Kind.Worktree) &&
		    !ksawery_conflict_assistance_object_range_is_valid(
				payload, side.object_offset, side.object_bytes,
		   )) ||
		   (side.kind == u64(ksawery.Conflict_Assistance_Side_Kind.Worktree) &&
		    (side.object_offset != 0 || side.object_bytes != 0)) ||
		   !ksawery_conflict_assistance_range_is_valid(
			payload, side.content_offset, side.content_bytes, true,
		   ) {
			return {code = .Invalid_Side, index = u64(index)}
		}
		if side.material == u64(ksawery.Conflict_Assistance_Material_Kind.Omitted) &&
		   (side.content_bytes != 0 || side.truncated == 0) {
			return {code = .Invalid_Side, index = u64(index)}
		}
		if side.material == u64(ksawery.Conflict_Assistance_Material_Kind.Text) &&
		   !ksawery_conflict_assistance_text_range_is_valid(
			payload, side.content_offset, side.content_bytes,
			ksawery.MAX_CONFLICT_ASSISTANCE_CONTENT_BYTES, true,
		   ) {
			return {code = .Invalid_Text, index = u64(index)}
		}
		content_bytes += side.content_bytes
		if side.truncated != 0 do truncated = true
	}
	if content_bytes > ksawery.MAX_CONFLICT_ASSISTANCE_CONTENT_BYTES {
		return {code = .Content_Limit,
			limit = ksawery.MAX_CONFLICT_ASSISTANCE_CONTENT_BYTES, actual = content_bytes}
	}
	if (record.truncated != 0) != truncated ||
	   ((record.classes & (u64(1) << u64(ksawery.Conflict_Assistance_Class.Truncated)) != 0) != truncated) {
		return {code = .Invalid_Observation}
	}
	if u64(len(payload)) > ksawery.MAX_CONFLICT_ASSISTANCE_COPY_BYTES {
		return {code = .Copy_Limit,
			limit = ksawery.MAX_CONFLICT_ASSISTANCE_COPY_BYTES, actual = u64(len(payload))}
	}
	return {}
}

/* ksawery_conflict_assistance_selection_record_validate rejects unsafe role changes. */
ksawery_conflict_assistance_selection_record_validate :: proc(
	record: Ksawery_Conflict_Assistance_Selection_Record,
	payload: []u8,
) -> Ksawery_Conflict_Assistance_Record_Failure {
	if record.schema_version != KSAWERY_CONFLICT_ASSISTANCE_SCHEMA_VERSION {
		return {code = .Unsupported_Schema, actual = record.schema_version}
	}
	expected := KSAWERY_CONFLICT_ASSISTANCE_SELECTION_BYTES + u64(len(payload))
	if record.record_bytes != expected || record.payload_bytes != u64(len(payload)) {
		return {code = .Size_Mismatch, limit = expected, actual = record.record_bytes}
	}
	if record.action == 0 || record.action > 3 || record.selection_id == 0 ||
	   record.next_generation == 0 || record.scope <= 1 ||
	   record.scope > u64(ksawery.Conflict_Assistance_Selection_Scope.Session) {
		return {code = .Invalid_Selection}
	}
	if record.action == 1 && record.previous_generation != 0 {
		return {code = .Invalid_Selection}
	}
	if record.action != 1 && (record.previous_generation == 0 ||
	   record.next_generation <= record.previous_generation) {
		return {code = .Invalid_Selection}
	}
	if record.action == 3 {
		if record.provider_origin != u64(ksawery.Conflict_Assistance_Provider_Origin.Built_In_No_Op) ||
		   record.contributor_generation != 0 ||
		   record.provider_id != u64(ksawery.BUILT_IN_CONFLICT_ASSISTANCE_PROVIDER_ID) ||
		   record.provider_generation != u64(ksawery.BUILT_IN_CONFLICT_ASSISTANCE_PROVIDER_GENERATION) ||
		   record.confirmed != 0 || record.contributor_identity_offset != 0 ||
		   record.contributor_identity_bytes != 0 {
			return {code = .Invalid_Selection}
		}
	} else if record.provider_origin != u64(ksawery.Conflict_Assistance_Provider_Origin.Extension) ||
	          record.contributor_generation == 0 ||
	          record.provider_id <= u64(ksawery.BUILT_IN_CONFLICT_ASSISTANCE_PROVIDER_ID) ||
	          record.provider_generation == 0 || record.confirmed != 1 ||
	          !ksawery_conflict_assistance_text_range_is_valid(
			payload, record.contributor_identity_offset, record.contributor_identity_bytes,
			u64(ksawery.MAX_EXTENSION_IDENTITY_BYTES), false,
		  ) {
		return {code = .Invalid_Selection}
	}
	if !ksawery_conflict_assistance_selection_scope_is_valid(record, payload) {
		return {code = .Invalid_Selection}
	}
	return {}
}

/* ksawery_conflict_assistance_response_record_validate checks bounded provider output. */
ksawery_conflict_assistance_response_record_validate :: proc(
	record: Ksawery_Conflict_Assistance_Response_Record,
	payload: []u8,
) -> Ksawery_Conflict_Assistance_Record_Failure {
	if record.schema_version != KSAWERY_CONFLICT_ASSISTANCE_SCHEMA_VERSION {
		return {code = .Unsupported_Schema, actual = record.schema_version}
	}
	expected := KSAWERY_CONFLICT_ASSISTANCE_RESPONSE_BYTES + u64(len(payload))
	if record.record_bytes != expected || record.payload_bytes != u64(len(payload)) {
		return {code = .Size_Mismatch, limit = expected, actual = record.record_bytes}
	}
	if record.request_id == 0 || record.provider_id == 0 || record.provider_generation == 0 ||
	   record.kind == 0 || record.kind > u64(ksawery.Conflict_Assistance_Response_Kind.External_Tool) ||
	   record.diagnostic_code > u64(ksawery.Conflict_Assistance_Failure_Code.Cleanup) ||
	   record.contributor_generation == 0 {
		return {code = .Invalid_Response}
	}
	if !ksawery_conflict_assistance_text_range_is_valid(
		payload, record.diagnostic_offset, record.diagnostic_bytes,
		u64(ksawery.MAX_EXTENSION_DIAGNOSTIC_BYTES), true,
	) {
		return {code = .Invalid_Text}
	}
	if (record.diagnostic_code == 0) != (record.diagnostic_bytes == 0) {
		return {code = .Invalid_Response}
	}
	switch ksawery.Conflict_Assistance_Response_Kind(record.kind) {
	case .Declined, .Editor:
		if record.tool_access != 0 || record.guidance_offset != 0 || record.guidance_bytes != 0 ||
		   record.operation_offset != 0 || record.operation_bytes != 0 {
			return {code = .Invalid_Response}
		}
	case .Guidance:
		if record.tool_access != 0 || record.operation_offset != 0 || record.operation_bytes != 0 ||
		   !ksawery_conflict_assistance_text_range_is_valid(
			payload, record.guidance_offset, record.guidance_bytes,
			u64(ksawery.MAX_CONFLICT_ASSISTANCE_GUIDANCE_BYTES), false,
		   ) {
			return {code = .Invalid_Response}
		}
	case .External_Tool:
		if record.tool_access == 0 ||
		   record.tool_access > u64(ksawery.Conflict_Assistance_Tool_Access.Worktree_Only) ||
		   record.guidance_offset != 0 || record.guidance_bytes != 0 ||
		   !ksawery_conflict_assistance_range_is_valid(
			payload, record.operation_offset, record.operation_bytes, false,
		   ) {
			return {code = .Invalid_Response}
		}
	case .Invalid:
		return {code = .Invalid_Response}
	}
	return {}
}

/* ksawery_conflict_assistance_record_layout_is_valid verifies every fixed ABI width. */
ksawery_conflict_assistance_record_layout_is_valid :: proc() -> bool {
	return u64(size_of(Ksawery_Conflict_Assistance_Provider_Record)) ==
		KSAWERY_CONFLICT_ASSISTANCE_PROVIDER_BYTES &&
		u64(size_of(Ksawery_Conflict_Assistance_Observation_Record)) ==
		KSAWERY_CONFLICT_ASSISTANCE_OBSERVATION_BYTES &&
		u64(size_of(Ksawery_Conflict_Assistance_Side_Record)) ==
		KSAWERY_CONFLICT_ASSISTANCE_SIDE_BYTES &&
		u64(size_of(Ksawery_Conflict_Assistance_Selection_Record)) ==
		KSAWERY_CONFLICT_ASSISTANCE_SELECTION_BYTES &&
		u64(size_of(Ksawery_Conflict_Assistance_Response_Record)) ==
		KSAWERY_CONFLICT_ASSISTANCE_RESPONSE_BYTES
}

@(private)
ksawery_conflict_assistance_range_is_valid :: proc(
	payload: []u8,
	offset, bytes: u64,
	empty: bool,
) -> bool {
	if bytes == 0 do return empty && offset == 0
	return offset < u64(len(payload)) && bytes <= u64(len(payload)) - offset
}

@(private)
ksawery_conflict_assistance_text_range_is_valid :: proc(
	payload: []u8,
	offset, bytes, maximum: u64,
	empty: bool,
) -> bool {
	if bytes > maximum || !ksawery_conflict_assistance_range_is_valid(payload, offset, bytes, empty) {
		return false
	}
	if bytes == 0 do return true
	return utf8.valid_string(string(payload[int(offset):int(offset + bytes)]))
}

@(private)
ksawery_conflict_assistance_object_range_is_valid :: proc(
	payload: []u8,
	offset, bytes: u64,
) -> bool {
	if bytes != 40 && bytes != 64 do return false
	if !ksawery_conflict_assistance_range_is_valid(payload, offset, bytes, false) do return false
	for byte in payload[int(offset):int(offset + bytes)] {
		if !(byte >= '0' && byte <= '9') && !(byte >= 'a' && byte <= 'f') do return false
	}
	return true
}

@(private)
ksawery_conflict_assistance_selection_scope_is_valid :: proc(
	record: Ksawery_Conflict_Assistance_Selection_Record,
	payload: []u8,
) -> bool {
	switch ksawery.Conflict_Assistance_Selection_Scope(record.scope) {
	case .Global:
		return record.scope_identity_offset == 0 && record.scope_identity_bytes == 0 &&
			record.repository_offset == 0 && record.repository_bytes == 0 && record.session == 0
	case .Project:
		return ksawery_conflict_assistance_text_range_is_valid(
			payload, record.scope_identity_offset, record.scope_identity_bytes,
			u64(ksawery.MAX_EXTENSION_IDENTITY_BYTES), false,
		) && record.repository_offset == 0 && record.repository_bytes == 0 && record.session == 0
	case .Repository:
		return record.scope_identity_offset == 0 && record.scope_identity_bytes == 0 &&
			ksawery_conflict_assistance_text_range_is_valid(
				payload, record.repository_offset, record.repository_bytes,
				u64(ksawery.MAX_REPOSITORY_CONTEXT_BYTES), false,
			) && payload[int(record.repository_offset)] == '/' && record.session == 0
	case .Session:
		return record.scope_identity_offset == 0 && record.scope_identity_bytes == 0 &&
			record.repository_offset == 0 && record.repository_bytes == 0 && record.session != 0
	case .Invalid, .Built_In_Fallback:
		return false
	}
	return false
}
