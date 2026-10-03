// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery_module

import bridge "../ksawery_bridge"
import "../ksawery"

/* ksawery_extension_operation_decode copies one validated Racket plan into native values. */
ksawery_extension_operation_decode :: proc(
	registry: ^Ksawery_Extension_Provider_Registry,
	input: []u8,
	arguments: ^[ksawery.MAX_EXTENSION_OPERATION_ARGUMENTS]ksawery.Extension_Operation_Argument,
) -> (ksawery.Extension_Operation_Plan, ksawery.Contribution_Declaration, bool) {
	if !ksawery_extension_provider_registry_is_open(registry) || registry.active == nil ||
	   !registry.active.enabled || arguments == nil ||
	   len(input) < int(bridge.KSAWERY_EXTENSION_OPERATION_HEADER_BYTES +
		bridge.KSAWERY_EXTENSION_OPERATION_LIMITS_BYTES +
		bridge.KSAWERY_EXTENSION_OPERATION_VERIFIER_BYTES) {
		return {}, {}, false
	}
	header: bridge.Ksawery_Extension_Operation_Header_Record
	for index in 0 ..< 24 {
		ksawery_extension_operation_assign_header_word(
			&header,
			index,
			ksawery_extension_word(input, index * 8),
		)
	}
	if header.argument_count > u64(ksawery.MAX_EXTENSION_OPERATION_ARGUMENTS) {
		return {}, {}, false
	}
	limits_offset := int(bridge.KSAWERY_EXTENSION_OPERATION_HEADER_BYTES)
	verifier_offset := limits_offset + int(bridge.KSAWERY_EXTENSION_OPERATION_LIMITS_BYTES)
	argument_offset := verifier_offset + int(bridge.KSAWERY_EXTENSION_OPERATION_VERIFIER_BYTES)
	text_offset := argument_offset + int(
		header.argument_count * bridge.KSAWERY_EXTENSION_OPERATION_ARGUMENT_BYTES,
	)
	if text_offset > len(input) do return {}, {}, false
	limits: bridge.Ksawery_Extension_Operation_Limits_Record
	for index in 0 ..< 4 {
		ksawery_extension_operation_assign_limits_word(
			&limits,
			index,
			ksawery_extension_word(input, limits_offset + index * 8),
		)
	}
	verifier: bridge.Ksawery_Extension_Operation_Verifier_Record
	for index in 0 ..< 7 {
		ksawery_extension_operation_assign_verifier_word(
			&verifier,
			index,
			ksawery_extension_word(input, verifier_offset + index * 8),
		)
	}
	argument_records: [ksawery.MAX_EXTENSION_OPERATION_ARGUMENTS]bridge.Ksawery_Extension_Operation_Argument_Record
	for index in 0 ..< int(header.argument_count) {
		base := argument_offset + index * int(bridge.KSAWERY_EXTENSION_OPERATION_ARGUMENT_BYTES)
		argument_records[index] = {
			offset = ksawery_extension_word(input, base),
			bytes = ksawery_extension_word(input, base + 8),
		}
	}
	text := input[text_offset:]
	record_failure := bridge.ksawery_extension_operation_records_validate(
		header,
		limits,
		verifier,
		argument_records[:int(header.argument_count)],
		text,
	)
	if record_failure.code != .None || header.record_bytes != u64(len(input)) ||
	   header.contributor_generation != u64(registry.active.inspection.handle.generation) {
		return {}, {}, false
	}
	contributor_identity := ksawery_extension_operation_text(
		text,
		header.contributor_identity_offset,
		header.contributor_identity_bytes,
	)
	active_identity := registry.active.inspection.identity
	if contributor_identity != string(active_identity.bytes[:active_identity.length]) {
		return {}, {}, false
	}
	declaration, declared := ksawery_extension_operation_declaration(
		registry.active,
		ksawery.Contribution_ID(header.contribution_id),
	)
	if !declared do return {}, {}, false
	plan := ksawery.Extension_Operation_Plan {
		contributor = registry.active.inspection.handle,
		contribution = ksawery.Contribution_ID(header.contribution_id),
		plan = ksawery.Extension_Operation_Plan_ID(header.plan_id),
		generation = ksawery.Extension_Operation_Plan_Generation_ID(header.plan_generation),
		effect = ksawery.Extension_Operation_Effect(header.effect),
		refresh = transmute(ksawery.Extension_Observation_Families)u16(header.refresh_observations),
		environment = ksawery.Extension_Operation_Environment_Profile(header.environment_profile),
		diagnostic_policy = ksawery.Extension_Operation_Diagnostic_Policy(header.diagnostic_policy),
		process_limits = {
			output_bytes = limits.output_bytes,
			diagnostic_bytes = limits.diagnostic_bytes,
			deadline_nanoseconds = i64(limits.deadline_nanoseconds),
			cancellation_grace_ns = i64(limits.cancellation_grace_ns),
		},
	}
	if !ksawery.extension_identity_assign(
		&plan.identity,
		ksawery_extension_operation_text(text, header.identity_offset, header.identity_bytes),
	) || !ksawery.extension_label_assign(
		&plan.purpose,
		ksawery_extension_operation_text(text, header.purpose_offset, header.purpose_bytes),
	) {
		return {}, {}, false
	}
	executable_identity := ksawery_extension_operation_text(
		text,
		header.executable_identity_offset,
		header.executable_identity_bytes,
	)
	switch ksawery.Extension_Operation_Executable_Kind(header.executable_kind) {
	case .Built_In_Git:
		if executable_identity != "git" ||
		   !ksawery.extension_operation_executable_assign_git(&plan.executable) {
			return {}, {}, false
		}
	case .Configured_Absolute_Path:
		if !ksawery.extension_operation_executable_assign_absolute(
			&plan.executable,
			executable_identity,
			ksawery_extension_operation_text(
				text,
				header.executable_path_offset,
				header.executable_path_bytes,
			),
		) {
			return {}, {}, false
		}
	case .Invalid:
		return {}, {}, false
	}
	for index in 0 ..< int(header.argument_count) {
		record := argument_records[index]
		if !ksawery.extension_operation_argument_assign(
			&arguments[index],
			ksawery_extension_operation_text(text, record.offset, record.bytes),
		) {
			return {}, {}, false
		}
	}
	plan.arguments = arguments[:int(header.argument_count)]
	plan.verifier = {
		kind = ksawery.Extension_Operation_Verifier_Kind(verifier.kind),
		observation = ksawery.Extension_Observation_Family(verifier.observation),
		operation = ksawery.Operation_State(verifier.operation_state),
	}
	if verifier.target_family != 0 && !ksawery.extension_annotation_target_assign(
		&plan.verifier.target,
		ksawery.Extension_Annotation_Target_Family(verifier.target_family),
		verifier.target_generation,
		ksawery_extension_operation_bytes(text, verifier.target_offset, verifier.target_bytes),
	) {
		return {}, {}, false
	}
	_, failure := ksawery.extension_operation_plan_validate(plan)
	return plan, declaration, failure.code == .None
}

@(private)
ksawery_extension_operation_declaration :: proc(
	provider: ^Ksawery_Extension_Provider_Data,
	id: ksawery.Contribution_ID,
) -> (ksawery.Contribution_Declaration, bool) {
	if provider == nil || id == 0 do return {}, false
	for record in provider.contributions {
		if ksawery.Contribution_ID(record.contribution_id) != id do continue
		declaration := ksawery.Contribution_Declaration {
			id = id,
			kind = ksawery.Contribution_Kind(record.kind),
			provider_role = ksawery.Provider_Role(record.provider_role),
			required_observations = transmute(ksawery.Extension_Observation_Families)u16(
				record.required_observations,
			),
			requested_authority = transmute(ksawery.Extension_Authorities)u16(
				record.requested_authorities,
			),
		}
		if !ksawery.extension_identity_assign(
			&declaration.identity,
			bridge.ksawery_extension_text(
				provider.text,
				record.identity_offset,
				record.identity_bytes,
			),
		) {
			return {}, false
		}
		return declaration, ksawery.contribution_declaration_is_valid(declaration)
	}
	return {}, false
}

@(private)
ksawery_extension_operation_text :: proc(text: []u8, offset, count: u64) -> string {
	return string(ksawery_extension_operation_bytes(text, offset, count))
}

@(private)
ksawery_extension_operation_bytes :: proc(text: []u8, offset, count: u64) -> []u8 {
	return text[int(offset):int(offset + count)]
}

@(private)
ksawery_extension_operation_assign_header_word :: proc(
	record: ^bridge.Ksawery_Extension_Operation_Header_Record,
	index: int,
	value: u64,
) {
	switch index {
	case 0:  record.schema_version = value
	case 1:  record.record_bytes = value
	case 2:  record.contributor_generation = value
	case 3:  record.contribution_id = value
	case 4:  record.plan_id = value
	case 5:  record.plan_generation = value
	case 6:  record.effect = value
	case 7:  record.refresh_observations = value
	case 8:  record.environment_profile = value
	case 9:  record.diagnostic_policy = value
	case 10: record.executable_kind = value
	case 11: record.argument_count = value
	case 12: record.contributor_identity_offset = value
	case 13: record.contributor_identity_bytes = value
	case 14: record.identity_offset = value
	case 15: record.identity_bytes = value
	case 16: record.purpose_offset = value
	case 17: record.purpose_bytes = value
	case 18: record.executable_identity_offset = value
	case 19: record.executable_identity_bytes = value
	case 20: record.executable_path_offset = value
	case 21: record.executable_path_bytes = value
	case 22: record.text_bytes = value
	case 23: record.reserved = value
	}
}

@(private)
ksawery_extension_operation_assign_limits_word :: proc(
	record: ^bridge.Ksawery_Extension_Operation_Limits_Record,
	index: int,
	value: u64,
) {
	switch index {
	case 0: record.output_bytes = value
	case 1: record.diagnostic_bytes = value
	case 2: record.deadline_nanoseconds = value
	case 3: record.cancellation_grace_ns = value
	}
}

@(private)
ksawery_extension_operation_assign_verifier_word :: proc(
	record: ^bridge.Ksawery_Extension_Operation_Verifier_Record,
	index: int,
	value: u64,
) {
	switch index {
	case 0: record.kind = value
	case 1: record.observation = value
	case 2: record.operation_state = value
	case 3: record.target_family = value
	case 4: record.target_generation = value
	case 5: record.target_offset = value
	case 6: record.target_bytes = value
	}
}
