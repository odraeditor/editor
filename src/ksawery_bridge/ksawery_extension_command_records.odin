// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery_bridge

import "../ksawery"
import "core:unicode/utf8"

/* KSAWERY_EXTENSION_COMMAND_SUBMISSION_SCHEMA_VERSION identifies the request ABI. */
KSAWERY_EXTENSION_COMMAND_SUBMISSION_SCHEMA_VERSION :: u64(1)
/* KSAWERY_EXTENSION_COMMAND_SUBMISSION_HEADER_BYTES is one fixed request prefix. */
KSAWERY_EXTENSION_COMMAND_SUBMISSION_HEADER_BYTES :: u64(80)
/* KSAWERY_EXTENSION_COMMAND_VALUE_RECORD_BYTES is one typed argument reference. */
KSAWERY_EXTENSION_COMMAND_VALUE_RECORD_BYTES :: u64(72)

/* Ksawery_Extension_Command_Submission_Header_Record binds one exact command turn. */
Ksawery_Extension_Command_Submission_Header_Record :: struct {
	schema_version:    u64,
	record_bytes:      u64,
	request_id:        u64,
	family_id:         u64,
	family_generation: u64,
	action_id:         u64,
	confirmation_id:   u64,
	argument_count:    u64,
	context_bytes:     u64,
	payload_bytes:     u64,
}

/* Ksawery_Extension_Command_Value_Record copies one scalar or payload-backed value. */
Ksawery_Extension_Command_Value_Record :: struct {
	argument_id:      u64,
	kind:             u64,
	scalar:           u64,
	content_offset:   u64,
	content_bytes:    u64,
	target_family:    u64,
	target_generation: u64,
	target_offset:    u64,
	target_bytes:     u64,
}

/* Ksawery_Extension_Command_Submission_Failure_Code classifies request ABI rejection. */
Ksawery_Extension_Command_Submission_Failure_Code :: enum u8 {
	None,
	Invalid_Header,
	Size_Mismatch,
	Count_Mismatch,
	Invalid_Value,
	Invalid_Payload,
}

/* Ksawery_Extension_Command_Submission_Failure retains one rejected argument. */
Ksawery_Extension_Command_Submission_Failure :: struct {
	code:   Ksawery_Extension_Command_Submission_Failure_Code,
	index:  u64,
	limit:  u64,
	actual: u64,
}

/* ksawery_extension_command_submission_record_bytes returns one complete request width. */
ksawery_extension_command_submission_record_bytes :: proc(
	argument_count, context_bytes, payload_bytes: u64,
) -> (u64, Ksawery_Extension_Command_Submission_Failure) {
	if argument_count > u64(ksawery.MAX_EXTENSION_COMMAND_ARGUMENTS) {
		return 0, {code = .Count_Mismatch,
			limit = u64(ksawery.MAX_EXTENSION_COMMAND_ARGUMENTS), actual = argument_count}
	}
	if context_bytes < 184 || context_bytes > ksawery.MAX_EXTENSION_COMMAND_COPY_BYTES ||
	   payload_bytes > ksawery.MAX_EXTENSION_COMMAND_COPY_BYTES {
		return 0, {code = .Size_Mismatch, actual = context_bytes + payload_bytes}
	}
	bytes := KSAWERY_EXTENSION_COMMAND_SUBMISSION_HEADER_BYTES +
		argument_count * KSAWERY_EXTENSION_COMMAND_VALUE_RECORD_BYTES +
		context_bytes + payload_bytes
	if bytes > ksawery.MAX_EXTENSION_COMMAND_COPY_BYTES {
		return 0, {code = .Size_Mismatch,
			limit = ksawery.MAX_EXTENSION_COMMAND_COPY_BYTES, actual = bytes}
	}
	return bytes, {}
}

/* ksawery_extension_command_submission_records_validate rejects malformed requests. */
ksawery_extension_command_submission_records_validate :: proc(
	header: Ksawery_Extension_Command_Submission_Header_Record,
	values: []Ksawery_Extension_Command_Value_Record,
	command_context, payload: []u8,
) -> Ksawery_Extension_Command_Submission_Failure {
	if header.schema_version != KSAWERY_EXTENSION_COMMAND_SUBMISSION_SCHEMA_VERSION ||
	   header.request_id == 0 || header.family_id == 0 ||
	   header.family_generation == 0 || header.action_id == 0 {
		return {code = .Invalid_Header}
	}
	expected, size_failure := ksawery_extension_command_submission_record_bytes(
		header.argument_count, header.context_bytes, header.payload_bytes,
	)
	if size_failure.code != .None do return size_failure
	if header.record_bytes != expected {
		return {code = .Size_Mismatch, limit = expected, actual = header.record_bytes}
	}
	if header.argument_count != u64(len(values)) ||
	   header.context_bytes != u64(len(command_context)) ||
	   header.payload_bytes != u64(len(payload)) {
		return {code = .Count_Mismatch}
	}
	for value, index in values {
		if !ksawery_extension_command_value_record_is_valid(value, payload) {
			return {code = .Invalid_Value, index = u64(index)}
		}
	}
	return {}
}

/* ksawery_extension_command_submission_record_layout_is_valid verifies ABI widths. */
ksawery_extension_command_submission_record_layout_is_valid :: proc() -> bool {
	return u64(size_of(Ksawery_Extension_Command_Submission_Header_Record)) ==
		KSAWERY_EXTENSION_COMMAND_SUBMISSION_HEADER_BYTES &&
		u64(size_of(Ksawery_Extension_Command_Value_Record)) ==
		KSAWERY_EXTENSION_COMMAND_VALUE_RECORD_BYTES
}

@(private)
ksawery_extension_command_value_record_is_valid :: proc(
	value: Ksawery_Extension_Command_Value_Record,
	payload: []u8,
) -> bool {
	if value.argument_id == 0 || value.kind == 0 ||
	   value.kind > u64(ksawery.Extension_Command_Argument_Kind.Opaque) {
		return false
	}
	kind := ksawery.Extension_Command_Argument_Kind(value.kind)
	switch kind {
	case .Boolean:
		return value.scalar <= 1 && value.content_offset == 0 && value.content_bytes == 0 &&
			value.target_family == 0 && value.target_generation == 0 &&
			value.target_offset == 0 && value.target_bytes == 0
	case .Closed_Choice:
		return value.scalar != 0 && value.content_offset == 0 && value.content_bytes == 0 &&
			value.target_family == 0 && value.target_generation == 0 &&
			value.target_offset == 0 && value.target_bytes == 0
	case .Text, .Opaque:
		if value.scalar != 0 || value.content_bytes == 0 ||
		   value.target_family != 0 || value.target_generation != 0 ||
		   value.target_offset != 0 || value.target_bytes != 0 ||
		   !ksawery_extension_command_payload_range_is_valid(
			payload, value.content_offset, value.content_bytes,
		) {
			return false
		}
		if kind == .Opaque do return true
		return utf8.valid_string(string(payload[int(value.content_offset):int(value.content_offset + value.content_bytes)]))
	case .Selection, .Ref, .Revision, .Revision_Range:
		if value.scalar != 0 || value.content_offset != 0 || value.content_bytes != 0 ||
		   value.target_family == 0 ||
		   value.target_family > u64(ksawery.Extension_Annotation_Target_Family.Process) ||
		   value.target_generation == 0 || value.target_bytes == 0 ||
		   !ksawery_extension_command_payload_range_is_valid(
			payload, value.target_offset, value.target_bytes,
		) {
			return false
		}
		return utf8.valid_string(string(payload[int(value.target_offset):int(value.target_offset + value.target_bytes)]))
	case .Invalid:
		return false
	}
	return false
}

@(private)
ksawery_extension_command_payload_range_is_valid :: proc(
	payload: []u8,
	offset, count: u64,
) -> bool {
	return offset <= u64(len(payload)) && count <= u64(len(payload)) - offset
}
