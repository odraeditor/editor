// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery_bridge

import "../ksawery"
import "core:unicode/utf8"

/* KSAWERY_EXTENSION_OPERATION_SCHEMA_VERSION identifies the initial plan ABI. */
KSAWERY_EXTENSION_OPERATION_SCHEMA_VERSION :: u64(1)
/* KSAWERY_EXTENSION_OPERATION_HEADER_BYTES is one complete plan envelope. */
KSAWERY_EXTENSION_OPERATION_HEADER_BYTES :: u64(192)
/* KSAWERY_EXTENSION_OPERATION_LIMITS_BYTES is one external child policy. */
KSAWERY_EXTENSION_OPERATION_LIMITS_BYTES :: u64(32)
/* KSAWERY_EXTENSION_OPERATION_VERIFIER_BYTES is one typed refreshed condition. */
KSAWERY_EXTENSION_OPERATION_VERIFIER_BYTES :: u64(56)
/* KSAWERY_EXTENSION_OPERATION_ARGUMENT_BYTES is one copied argument reference. */
KSAWERY_EXTENSION_OPERATION_ARGUMENT_BYTES :: u64(16)

/* Ksawery_Extension_Operation_Header_Record describes one declared plan. */
Ksawery_Extension_Operation_Header_Record :: struct {
	schema_version:              u64,
	record_bytes:                u64,
	contributor_generation:      u64,
	contribution_id:             u64,
	plan_id:                     u64,
	plan_generation:             u64,
	effect:                      u64,
	refresh_observations:        u64,
	environment_profile:         u64,
	diagnostic_policy:           u64,
	executable_kind:             u64,
	argument_count:              u64,
	contributor_identity_offset: u64,
	contributor_identity_bytes:  u64,
	identity_offset:             u64,
	identity_bytes:              u64,
	purpose_offset:              u64,
	purpose_bytes:               u64,
	executable_identity_offset:  u64,
	executable_identity_bytes:   u64,
	executable_path_offset:      u64,
	executable_path_bytes:       u64,
	text_bytes:                  u64,
	reserved:                    u64,
}

/* Ksawery_Extension_Operation_Limits_Record copies one child resource envelope. */
Ksawery_Extension_Operation_Limits_Record :: struct {
	output_bytes:          u64,
	diagnostic_bytes:      u64,
	deadline_nanoseconds:  u64,
	cancellation_grace_ns: u64,
}

/* Ksawery_Extension_Operation_Verifier_Record copies one typed verifier. */
Ksawery_Extension_Operation_Verifier_Record :: struct {
	kind:              u64,
	observation:       u64,
	operation_state:   u64,
	target_family:     u64,
	target_generation: u64,
	target_offset:     u64,
	target_bytes:      u64,
}

/* Ksawery_Extension_Operation_Argument_Record points into copied plan text. */
Ksawery_Extension_Operation_Argument_Record :: struct {
	offset: u64,
	bytes:  u64,
}

/* Ksawery_Extension_Operation_Record_Failure_Code classifies plan ABI rejection. */
Ksawery_Extension_Operation_Record_Failure_Code :: enum u16 {
	None,
	Unsupported_Schema,
	Invalid_Header,
	Size_Mismatch,
	Count_Mismatch,
	Text_Limit,
	Copy_Limit,
	Invalid_Text,
	Invalid_Executable,
	Invalid_Argument,
	Invalid_Limits,
	Invalid_Verifier,
}

/* Ksawery_Extension_Operation_Record_Failure retains one rejected field. */
Ksawery_Extension_Operation_Record_Failure :: struct {
	code:   Ksawery_Extension_Operation_Record_Failure_Code,
	index:  u64,
	limit:  u64,
	actual: u64,
}

/* ksawery_extension_operation_record_bytes returns one complete encoded width. */
ksawery_extension_operation_record_bytes :: proc(
	argument_count, text_bytes: u64,
) -> (u64, Ksawery_Extension_Operation_Record_Failure) {
	if argument_count > u64(ksawery.MAX_EXTENSION_OPERATION_ARGUMENTS) {
		return 0, {code = .Count_Mismatch,
			limit = u64(ksawery.MAX_EXTENSION_OPERATION_ARGUMENTS), actual = argument_count}
	}
	if text_bytes > ksawery.MAX_EXTENSION_OPERATION_VECTOR_BYTES +
	                u64(ksawery.MAX_EXTENSION_OPERATION_EXECUTABLE_BYTES) +
	                u64(ksawery.MAX_EXTENSION_IDENTITY_BYTES) * 2 +
	                u64(ksawery.MAX_EXTENSION_LABEL_BYTES) {
		return 0, {code = .Text_Limit, actual = text_bytes}
	}
	bytes := KSAWERY_EXTENSION_OPERATION_HEADER_BYTES +
		KSAWERY_EXTENSION_OPERATION_LIMITS_BYTES +
		KSAWERY_EXTENSION_OPERATION_VERIFIER_BYTES +
		argument_count * KSAWERY_EXTENSION_OPERATION_ARGUMENT_BYTES + text_bytes
	if bytes > ksawery.MAX_EXTENSION_OPERATION_COPY_BYTES {
		return 0, {code = .Copy_Limit,
			limit = ksawery.MAX_EXTENSION_OPERATION_COPY_BYTES, actual = bytes}
	}
	return bytes, {}
}

/* ksawery_extension_operation_records_validate rejects malformed plan records. */
ksawery_extension_operation_records_validate :: proc(
	header: Ksawery_Extension_Operation_Header_Record,
	limits: Ksawery_Extension_Operation_Limits_Record,
	verifier: Ksawery_Extension_Operation_Verifier_Record,
	arguments: []Ksawery_Extension_Operation_Argument_Record,
	text: []u8,
) -> Ksawery_Extension_Operation_Record_Failure {
	if header.schema_version != KSAWERY_EXTENSION_OPERATION_SCHEMA_VERSION {
		return {code = .Unsupported_Schema, actual = header.schema_version}
	}
	if header.contributor_generation == 0 || header.contribution_id == 0 ||
	   header.plan_id == 0 || header.plan_generation == 0 || header.effect == 0 ||
	   header.effect > u64(ksawery.Extension_Operation_Effect.Externally_Mutating) ||
	   header.refresh_observations == 0 || header.refresh_observations & ~u64(0x3f) != 0 ||
	   header.environment_profile != u64(ksawery.Extension_Operation_Environment_Profile.Core_Repository) ||
	   header.diagnostic_policy == 0 ||
	   header.diagnostic_policy > u64(ksawery.Extension_Operation_Diagnostic_Policy.Bounded_Public) ||
	   header.executable_kind == 0 ||
	   header.executable_kind > u64(ksawery.Extension_Operation_Executable_Kind.Configured_Absolute_Path) ||
	   header.reserved != 0 {
		return {code = .Invalid_Header}
	}
	expected, failure := ksawery_extension_operation_record_bytes(
		header.argument_count, header.text_bytes,
	)
	if failure.code != .None do return failure
	if header.record_bytes != expected {
		return {code = .Size_Mismatch, limit = expected, actual = header.record_bytes}
	}
	if header.argument_count != u64(len(arguments)) || header.text_bytes != u64(len(text)) {
		return {code = .Count_Mismatch}
	}
	if !ksawery_extension_operation_text_is_valid(
		text, header.contributor_identity_offset, header.contributor_identity_bytes,
		u64(ksawery.MAX_EXTENSION_IDENTITY_BYTES),
	) || !ksawery_extension_operation_text_is_valid(
		text, header.identity_offset, header.identity_bytes,
		u64(ksawery.MAX_EXTENSION_IDENTITY_BYTES),
	) || !ksawery_extension_operation_text_is_valid(
		text, header.purpose_offset, header.purpose_bytes,
		u64(ksawery.MAX_EXTENSION_LABEL_BYTES),
	) {
		return {code = .Invalid_Text}
	}
	if !ksawery_extension_operation_executable_record_is_valid(header, text) {
		return {code = .Invalid_Executable}
	}
	for argument, index in arguments {
		if !ksawery_extension_operation_text_is_valid(
			text, argument.offset, argument.bytes,
			u64(ksawery.MAX_EXTENSION_OPERATION_ARGUMENT_BYTES),
		) {
			return {code = .Invalid_Argument, index = u64(index)}
		}
	}
	if !ksawery_extension_operation_limits_record_is_valid(limits) {
		return {code = .Invalid_Limits}
	}
	if !ksawery_extension_operation_verifier_record_is_valid(
		verifier, header.refresh_observations, text,
	) {
		return {code = .Invalid_Verifier}
	}
	return {}
}

/* ksawery_extension_operation_record_layout_is_valid verifies fixed ABI widths. */
ksawery_extension_operation_record_layout_is_valid :: proc() -> bool {
	return u64(size_of(Ksawery_Extension_Operation_Header_Record)) ==
		KSAWERY_EXTENSION_OPERATION_HEADER_BYTES &&
		u64(size_of(Ksawery_Extension_Operation_Limits_Record)) ==
		KSAWERY_EXTENSION_OPERATION_LIMITS_BYTES &&
		u64(size_of(Ksawery_Extension_Operation_Verifier_Record)) ==
		KSAWERY_EXTENSION_OPERATION_VERIFIER_BYTES &&
		u64(size_of(Ksawery_Extension_Operation_Argument_Record)) ==
		KSAWERY_EXTENSION_OPERATION_ARGUMENT_BYTES
}

@(private)
ksawery_extension_operation_executable_record_is_valid :: proc(
	header: Ksawery_Extension_Operation_Header_Record,
	text: []u8,
) -> bool {
	if !ksawery_extension_operation_text_is_valid(
		text, header.executable_identity_offset, header.executable_identity_bytes,
		u64(ksawery.MAX_EXTENSION_IDENTITY_BYTES),
	) {
		return false
	}
	identity := text[int(header.executable_identity_offset):int(
		header.executable_identity_offset + header.executable_identity_bytes,
	)]
	if header.executable_kind == u64(ksawery.Extension_Operation_Executable_Kind.Built_In_Git) {
		return string(identity) == "git" && header.executable_path_offset == 0 &&
			header.executable_path_bytes == 0
	}
	if !ksawery_extension_operation_text_is_valid(
		text, header.executable_path_offset, header.executable_path_bytes,
		u64(ksawery.MAX_EXTENSION_OPERATION_EXECUTABLE_BYTES),
	) {
		return false
	}
	path := text[int(header.executable_path_offset):int(
		header.executable_path_offset + header.executable_path_bytes,
	)]
	return len(path) > 1 && path[0] == '/'
}

@(private)
ksawery_extension_operation_limits_record_is_valid :: proc(
	record: Ksawery_Extension_Operation_Limits_Record,
) -> bool {
	if record.deadline_nanoseconds > u64(max(i64)) ||
	   record.cancellation_grace_ns > u64(max(i64)) {
		return false
	}
	return ksawery.extension_operation_process_limits_are_valid({
		output_bytes = record.output_bytes,
		diagnostic_bytes = record.diagnostic_bytes,
		deadline_nanoseconds = i64(record.deadline_nanoseconds),
		cancellation_grace_ns = i64(record.cancellation_grace_ns),
	})
}

@(private)
ksawery_extension_operation_verifier_record_is_valid :: proc(
	record: Ksawery_Extension_Operation_Verifier_Record,
	refresh: u64,
	text: []u8,
) -> bool {
	if record.kind > u64(ksawery.Extension_Operation_Verifier_Kind.Operation_State) ||
	   record.observation > u64(ksawery.Extension_Observation_Family.Process) ||
	   record.operation_state > u64(ksawery.Operation_State.Other_Sequence) ||
	   record.target_family > u64(ksawery.Extension_Annotation_Target_Family.Process) {
		return false
	}
	if record.kind == u64(ksawery.Extension_Operation_Verifier_Kind.None) {
		return record.operation_state == 0 && record.target_family == 0 &&
			record.target_generation == 0 && record.target_offset == 0 && record.target_bytes == 0
	}
	if refresh & (u64(1) << record.observation) == 0 do return false
	if record.kind == u64(ksawery.Extension_Operation_Verifier_Kind.Observation_Available) {
		return record.operation_state == 0 && record.target_family == 0 &&
			record.target_generation == 0 && record.target_offset == 0 && record.target_bytes == 0
	}
	if record.kind == u64(ksawery.Extension_Operation_Verifier_Kind.Operation_State) {
		return (record.observation == u64(ksawery.Extension_Observation_Family.Status) ||
		        record.observation == u64(ksawery.Extension_Observation_Family.Sequence) ||
		        record.observation == u64(ksawery.Extension_Observation_Family.Conflict)) &&
			record.operation_state != 0 && record.target_family == 0 &&
			record.target_generation == 0 && record.target_offset == 0 && record.target_bytes == 0
	}
	return record.operation_state == 0 && record.target_family != 0 &&
		record.target_generation != 0 &&
		ksawery_extension_operation_target_supports_observation(
			record.target_family, record.observation,
		) && ksawery_extension_operation_bytes_are_valid(
			text, record.target_offset, record.target_bytes,
			u64(ksawery.MAX_EXTENSION_ANNOTATION_TARGET_BYTES),
		)
}

@(private)
ksawery_extension_operation_target_supports_observation :: proc(
	target, observation: u64,
) -> bool {
	switch ksawery.Extension_Annotation_Target_Family(target) {
	case .Path, .Diff_Unit:
		return observation == u64(ksawery.Extension_Observation_Family.Status)
	case .Revision, .Revision_Range:
		return observation == u64(ksawery.Extension_Observation_Family.History)
	case .Ref, .Remote:
		return observation == u64(ksawery.Extension_Observation_Family.Refs)
	case .Conflict:
		return observation == u64(ksawery.Extension_Observation_Family.Conflict) ||
			observation == u64(ksawery.Extension_Observation_Family.Sequence)
	case .Sequence:
		return observation == u64(ksawery.Extension_Observation_Family.Sequence)
	case .Process:
		return observation == u64(ksawery.Extension_Observation_Family.Process)
	case .Invalid:
		return false
	}
	return false
}

@(private)
ksawery_extension_operation_bytes_are_valid :: proc(
	text: []u8,
	offset, count, limit: u64,
) -> bool {
	return count > 0 && count <= limit && offset <= u64(len(text)) &&
		count <= u64(len(text)) - offset
}

@(private)
ksawery_extension_operation_text_is_valid :: proc(
	text: []u8,
	offset, count, limit: u64,
) -> bool {
	if count == 0 || count > limit || offset > u64(len(text)) ||
	   count > u64(len(text)) - offset {
		return false
	}
	value := text[int(offset):int(offset + count)]
	for byte in value {
		if byte == 0 do return false
	}
	return utf8.valid_string(string(value))
}
