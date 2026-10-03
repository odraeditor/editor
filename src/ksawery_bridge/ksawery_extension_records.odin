// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery_bridge

import "../ksawery"
import "core:unicode/utf8"

/* KSAWERY_EXTENSION_SCHEMA_VERSION identifies the first copied provider ABI. */
KSAWERY_EXTENSION_SCHEMA_VERSION :: u64(1)
/* MAX_KSAWERY_EXTENSION_COPY_BYTES bounds one complete copied candidate. */
MAX_KSAWERY_EXTENSION_COPY_BYTES :: u64(ksawery.MAX_EXTENSION_DECLARATION_BYTES)
/* MAX_KSAWERY_EXTENSION_TEXT_BYTES bounds candidate identities and provenance. */
MAX_KSAWERY_EXTENSION_TEXT_BYTES :: u64(ksawery.MAX_EXTENSION_DECLARATION_BYTES)

/* KSAWERY_EXTENSION_HEADER_BYTES is one complete candidate envelope. */
KSAWERY_EXTENSION_HEADER_BYTES :: u64(96)
/* KSAWERY_EXTENSION_CONTRIBUTOR_RECORD_BYTES is one copied contributor width. */
KSAWERY_EXTENSION_CONTRIBUTOR_RECORD_BYTES :: u64(128)
/* KSAWERY_EXTENSION_CONTRIBUTION_RECORD_BYTES is one copied contribution width. */
KSAWERY_EXTENSION_CONTRIBUTION_RECORD_BYTES :: u64(64)
/* KSAWERY_EXTENSION_LIMITS_RECORD_BYTES is one complete resource policy width. */
KSAWERY_EXTENSION_LIMITS_RECORD_BYTES :: u64(112)
/* KSAWERY_EXTENSION_SCOPE_RECORD_BYTES is one exact synchronous turn width. */
KSAWERY_EXTENSION_SCOPE_RECORD_BYTES :: u64(168)
/* KSAWERY_EXTENSION_PROPOSAL_RECORD_BYTES is one provider proposal envelope. */
KSAWERY_EXTENSION_PROPOSAL_RECORD_BYTES :: u64(64)
/* KSAWERY_EXTENSION_OUTCOME_RECORD_BYTES is one checked turn result width. */
KSAWERY_EXTENSION_OUTCOME_RECORD_BYTES :: u64(96)
/* KSAWERY_EXTENSION_USAGE_RECORD_BYTES is one resource-accounting width. */
KSAWERY_EXTENSION_USAGE_RECORD_BYTES :: u64(88)
/* KSAWERY_EXTENSION_FAILURE_RECORD_BYTES is one attributable failure width. */
KSAWERY_EXTENSION_FAILURE_RECORD_BYTES :: u64(80)
/* KSAWERY_EXTENSION_INSPECTION_RECORD_BYTES is one contributor summary width. */
KSAWERY_EXTENSION_INSPECTION_RECORD_BYTES :: u64(160)

/* Ksawery_Extension_Header_Record describes one complete contributor batch. */
Ksawery_Extension_Header_Record :: struct {
	schema_version:      u64,
	record_bytes:        u64,
	api_version:         u64,
	registry_generation: u64,
	contributor_count:   u64,
	contribution_count:  u64,
	text_bytes:          u64,
	limits_offset:       u64,
	limits_count:        u64,
	reserved_0:          u64,
	reserved_1:          u64,
	reserved_2:          u64,
}

/* Ksawery_Extension_Contributor_Record copies one complete generation owner. */
Ksawery_Extension_Contributor_Record :: struct {
	contributor_id:         u64,
	contributor_generation: u64,
	origin:                 u64,
	lifecycle:              u64,
	identity_offset:        u64,
	identity_bytes:         u64,
	label_offset:           u64,
	label_bytes:            u64,
	provenance_offset:      u64,
	provenance_bytes:       u64,
	authorities:            u64,
	first_contribution:     u64,
	contribution_count:     u64,
	limits_index:           u64,
	provider_role_count:    u64,
	reserved:               u64,
}

/* Ksawery_Extension_Contribution_Record copies one owner-local declaration. */
Ksawery_Extension_Contribution_Record :: struct {
	contribution_id:       u64,
	kind:                  u64,
	provider_role:         u64,
	required_observations: u64,
	requested_authorities: u64,
	identity_offset:       u64,
	identity_bytes:        u64,
	reserved:              u64,
}

/* Ksawery_Extension_Limits_Record copies every initial or requested bound. */
Ksawery_Extension_Limits_Record :: struct {
	contributors:                  u64,
	contributions_per_contributor: u64,
	total_contributions:           u64,
	declaration_bytes:             u64,
	observation_bytes:             u64,
	result_bytes:                  u64,
	provider_value_bytes:          u64,
	diagnostic_bytes:              u64,
	turn_deadline_ns:              u64,
	custodian_memory_bytes:        u64,
	callbacks_per_turn:            u64,
	nesting_depth:                 u64,
	retained_native_bytes:         u64,
	temporary_native_bytes:        u64,
}

/* Ksawery_Extension_Scope_Record copies one revocable repository turn. */
Ksawery_Extension_Scope_Record :: struct {
	schema_version:         u64,
	turn_id:                u64,
	contributor_id:         u64,
	contributor_generation: u64,
	repository_offset:      u64,
	repository_bytes:       u64,
	repository_generation:  u64,
	worktree_generation:    u64,
	observation_generation: u64,
	surface:                u64,
	surface_generation:     u64,
	selection_generation:   u64,
	target_kind:            u64,
	target_generation:      u64,
	target_identity:        u64,
	capability_generation:  u64,
	owner_thread:           u64,
	deadline_ns:            u64,
	callback_budget:        u64,
	flags:                  u64,
	reserved:               u64,
}

/* Ksawery_Extension_Proposal_Record copies one bounded provider response. */
Ksawery_Extension_Proposal_Record :: struct {
	schema_version:         u64,
	operation:              u64,
	contributor_id:         u64,
	contributor_generation: u64,
	contribution_id:        u64,
	payload_offset:         u64,
	payload_bytes:          u64,
	flags:                  u64,
}

/* Ksawery_Extension_Outcome_Record copies one admitted or rejected result. */
Ksawery_Extension_Outcome_Record :: struct {
	schema_version:         u64,
	operation:              u64,
	contributor_id:         u64,
	contributor_generation: u64,
	contribution_id:        u64,
	accepted:               u64,
	replacement_generation: u64,
	result_offset:          u64,
	result_bytes:           u64,
	failure_code:           u64,
	diagnostic_offset:      u64,
	diagnostic_bytes:       u64,
}

/* Ksawery_Extension_Usage_Record copies exact retained and turn accounting. */
Ksawery_Extension_Usage_Record :: struct {
	contributions:          u64,
	declaration_bytes:      u64,
	observation_bytes:      u64,
	result_bytes:           u64,
	provider_value_bytes:   u64,
	diagnostic_bytes:       u64,
	retained_native_bytes:  u64,
	temporary_native_bytes: u64,
	turns:                  u64,
	callbacks:              u64,
	failures:               u64,
}

/* Ksawery_Extension_Failure_Record copies one attributable bounded failure. */
Ksawery_Extension_Failure_Record :: struct {
	code:                   u64,
	operation:              u64,
	contributor_id:         u64,
	contributor_generation: u64,
	contribution_id:        u64,
	limit:                  u64,
	actual:                 u64,
	diagnostic_offset:      u64,
	diagnostic_bytes:       u64,
	diagnostic_truncated:   u64,
}

/* Ksawery_Extension_Inspection_Record copies one contributor summary. */
Ksawery_Extension_Inspection_Record :: struct {
	contributor_id:         u64,
	contributor_generation: u64,
	lifecycle:              u64,
	origin:                 u64,
	identity_offset:        u64,
	identity_bytes:         u64,
	label_offset:           u64,
	label_bytes:            u64,
	provenance_offset:      u64,
	provenance_bytes:       u64,
	authorities:            u64,
	contribution_count:     u64,
	provider_role_count:    u64,
	usage_index:            u64,
	failure_index:          u64,
	active_process_id:      u64,
	active_role:            u64,
	observation_generation: u64,
	flags:                  u64,
	reserved:               u64,
}

/* Ksawery_Extension_Record_Failure_Code classifies copied-record rejection. */
Ksawery_Extension_Record_Failure_Code :: enum u16 {
	None,
	Unsupported_Schema,
	Invalid_Header,
	Stale_Generation,
	Contributor_Limit,
	Contribution_Limit,
	Text_Limit,
	Copy_Limit,
	Size_Mismatch,
	Count_Mismatch,
	Invalid_Contributor,
	Invalid_Contribution,
	Duplicate_Contributor,
	Invalid_Text,
	Invalid_Limits,
	Invalid_Scope,
}

/* Ksawery_Extension_Record_Failure identifies one rejected copied record. */
Ksawery_Extension_Record_Failure :: struct {
	code:   Ksawery_Extension_Record_Failure_Code,
	index:  u64,
	limit:  u64,
	actual: u64,
}

/* ksawery_extension_record_bytes returns one complete bounded candidate width. */
ksawery_extension_record_bytes :: proc(contributors, contributions, text_bytes: u64) -> (u64, Ksawery_Extension_Record_Failure) {
	if contributors == 0 || contributors > u64(ksawery.MAX_EXTENSION_CONTRIBUTORS) {
		return 0, {code = .Contributor_Limit, limit = u64(ksawery.MAX_EXTENSION_CONTRIBUTORS), actual = contributors}
	}
	if contributions == 0 || contributions > u64(ksawery.MAX_EXTENSION_CONTRIBUTIONS) {
		return 0, {code = .Contribution_Limit, limit = u64(ksawery.MAX_EXTENSION_CONTRIBUTIONS), actual = contributions}
	}
	if text_bytes > MAX_KSAWERY_EXTENSION_TEXT_BYTES {
		return 0, {code = .Text_Limit, limit = MAX_KSAWERY_EXTENSION_TEXT_BYTES, actual = text_bytes}
	}
	bytes := KSAWERY_EXTENSION_HEADER_BYTES + contributors * KSAWERY_EXTENSION_CONTRIBUTOR_RECORD_BYTES +
		contributions * KSAWERY_EXTENSION_CONTRIBUTION_RECORD_BYTES +
		contributors * KSAWERY_EXTENSION_LIMITS_RECORD_BYTES + text_bytes
	if bytes > MAX_KSAWERY_EXTENSION_COPY_BYTES {
		return 0, {code = .Copy_Limit, limit = MAX_KSAWERY_EXTENSION_COPY_BYTES, actual = bytes}
	}
	return bytes, {}
}

/* ksawery_extension_records_validate rejects malformed complete candidates. */
ksawery_extension_records_validate :: proc(header: Ksawery_Extension_Header_Record, contributors: []Ksawery_Extension_Contributor_Record, contributions: []Ksawery_Extension_Contribution_Record, limits: []Ksawery_Extension_Limits_Record, text: []u8, expected_generation: u64) -> Ksawery_Extension_Record_Failure {
	if header.schema_version != KSAWERY_EXTENSION_SCHEMA_VERSION do return {code = .Unsupported_Schema, actual = header.schema_version}
	if header.api_version != u64(ksawery.EXTENSION_API_VERSION) || header.registry_generation == 0 ||
	   header.reserved_0 != 0 || header.reserved_1 != 0 || header.reserved_2 != 0 {
		return {code = .Invalid_Header}
	}
	if header.registry_generation != expected_generation do return {code = .Stale_Generation, limit = expected_generation, actual = header.registry_generation}
	expected, failure := ksawery_extension_record_bytes(header.contributor_count, header.contribution_count, header.text_bytes)
	if failure.code != .None do return failure
	if header.record_bytes != expected do return {code = .Size_Mismatch, limit = expected, actual = header.record_bytes}
	if header.contributor_count != u64(len(contributors)) || header.contribution_count != u64(len(contributions)) ||
	   header.limits_count != u64(len(limits)) || header.limits_offset != 0 || header.text_bytes != u64(len(text)) ||
	   len(limits) != len(contributors) {
		return {code = .Count_Mismatch}
	}
	for contributor, index in contributors {
		if contributor.contributor_id == 0 || contributor.contributor_generation == 0 ||
		   contributor.origin == 0 || contributor.origin > u64(ksawery.Contributor_Origin.Package) ||
		   contributor.lifecycle == 0 || contributor.lifecycle > u64(ksawery.Contributor_Lifecycle.Closed) ||
		   contributor.reserved != 0 || contributor.limits_index != u64(index) || contributor.contribution_count == 0 ||
		   contributor.contribution_count > u64(ksawery.MAX_EXTENSION_CONTRIBUTIONS_PER_CONTRIBUTOR) ||
		   contributor.first_contribution > u64(len(contributions)) ||
		   contributor.contribution_count > u64(len(contributions)) - contributor.first_contribution {
			return {code = .Invalid_Contributor, index = u64(index)}
		}
		if !ksawery_extension_text_is_valid(text, contributor.identity_offset, contributor.identity_bytes, u64(ksawery.MAX_EXTENSION_IDENTITY_BYTES)) ||
		   !ksawery_extension_text_is_valid(text, contributor.label_offset, contributor.label_bytes, u64(ksawery.MAX_EXTENSION_LABEL_BYTES)) ||
		   !ksawery_extension_text_is_valid(text, contributor.provenance_offset, contributor.provenance_bytes, u64(ksawery.MAX_EXTENSION_PROVENANCE_BYTES)) {
			return {code = .Invalid_Text, index = u64(index)}
		}
		if !ksawery_extension_limits_record_is_valid(limits[index]) do return {code = .Invalid_Limits, index = u64(index)}
		for prior in 0 ..< index {
			if contributors[prior].contributor_id == contributor.contributor_id ||
			   ksawery_extension_text(text, contributors[prior].identity_offset, contributors[prior].identity_bytes) == ksawery_extension_text(text, contributor.identity_offset, contributor.identity_bytes) {
				return {code = .Duplicate_Contributor, index = u64(index)}
			}
		}
	}
	for contribution, index in contributions {
		if contribution.contribution_id == 0 || contribution.kind == 0 || contribution.kind > u64(ksawery.Contribution_Kind.Provider_Role) ||
		   contribution.provider_role > u64(ksawery.Provider_Role.Conflict_Assistance) || contribution.requested_authorities == 0 ||
		   contribution.reserved != 0 || !ksawery_extension_text_is_valid(text, contribution.identity_offset, contribution.identity_bytes, u64(ksawery.MAX_EXTENSION_IDENTITY_BYTES)) {
			return {code = .Invalid_Contribution, index = u64(index)}
		}
	}
	return {}
}

/* ksawery_extension_scope_record_is_valid checks one copied turn envelope. */
ksawery_extension_scope_record_is_valid :: proc(record: Ksawery_Extension_Scope_Record, text: []u8) -> bool {
	return record.schema_version == KSAWERY_EXTENSION_SCHEMA_VERSION && record.turn_id != 0 && record.contributor_id != 0 &&
		record.contributor_generation != 0 && ksawery_extension_text_is_valid(text, record.repository_offset, record.repository_bytes, u64(ksawery.MAX_REPOSITORY_CONTEXT_BYTES)) &&
		record.repository_generation != 0 && record.worktree_generation != 0 && record.observation_generation != 0 &&
		record.surface > 0 && record.surface <= u64(ksawery.Extension_Surface.Inspection) && record.surface_generation != 0 &&
		record.selection_generation != 0 && record.target_kind <= u64(ksawery.Extension_Target_Kind.Process) &&
		((record.target_kind == 0 && record.target_generation == 0 && record.target_identity == 0) || (record.target_kind > 0 && record.target_generation != 0 && record.target_identity != 0)) &&
		record.capability_generation != 0 && record.owner_thread != 0 && record.deadline_ns > 0 &&
		record.deadline_ns <= u64(ksawery.MAX_EXTENSION_TURN_DEADLINE_NS) && record.callback_budget > 0 &&
		record.callback_budget <= u64(ksawery.MAX_EXTENSION_CALLBACKS_PER_TURN) && record.flags & ~u64(0x0f) == 0 && record.reserved == 0
}

/* ksawery_extension_record_layout_is_valid verifies every copied ABI width. */
ksawery_extension_record_layout_is_valid :: proc() -> bool {
	return u64(size_of(Ksawery_Extension_Header_Record)) == KSAWERY_EXTENSION_HEADER_BYTES &&
		u64(size_of(Ksawery_Extension_Contributor_Record)) == KSAWERY_EXTENSION_CONTRIBUTOR_RECORD_BYTES &&
		u64(size_of(Ksawery_Extension_Contribution_Record)) == KSAWERY_EXTENSION_CONTRIBUTION_RECORD_BYTES &&
		u64(size_of(Ksawery_Extension_Limits_Record)) == KSAWERY_EXTENSION_LIMITS_RECORD_BYTES &&
		u64(size_of(Ksawery_Extension_Scope_Record)) == KSAWERY_EXTENSION_SCOPE_RECORD_BYTES &&
		u64(size_of(Ksawery_Extension_Proposal_Record)) == KSAWERY_EXTENSION_PROPOSAL_RECORD_BYTES &&
		u64(size_of(Ksawery_Extension_Outcome_Record)) == KSAWERY_EXTENSION_OUTCOME_RECORD_BYTES &&
		u64(size_of(Ksawery_Extension_Usage_Record)) == KSAWERY_EXTENSION_USAGE_RECORD_BYTES &&
		u64(size_of(Ksawery_Extension_Failure_Record)) == KSAWERY_EXTENSION_FAILURE_RECORD_BYTES &&
		u64(size_of(Ksawery_Extension_Inspection_Record)) == KSAWERY_EXTENSION_INSPECTION_RECORD_BYTES
}

/* ksawery_extension_text borrows one already validated copied field. */
ksawery_extension_text :: proc(text: []u8, offset, count: u64) -> string {
	return string(text[int(offset):int(offset + count)])
}

@(private)
ksawery_extension_text_is_valid :: proc(text: []u8, offset, count, limit: u64) -> bool {
	if count == 0 || count > limit || offset > u64(len(text)) || count > u64(len(text)) - offset do return false
	return utf8.valid_string(ksawery_extension_text(text, offset, count))
}

@(private)
ksawery_extension_limits_record_is_valid :: proc(record: Ksawery_Extension_Limits_Record) -> bool {
	return record.contributors > 0 && record.contributors <= u64(ksawery.MAX_EXTENSION_CONTRIBUTORS) &&
		record.contributions_per_contributor > 0 && record.contributions_per_contributor <= u64(ksawery.MAX_EXTENSION_CONTRIBUTIONS_PER_CONTRIBUTOR) &&
		record.total_contributions > 0 && record.total_contributions <= u64(ksawery.MAX_EXTENSION_CONTRIBUTIONS) &&
		record.declaration_bytes > 0 && record.declaration_bytes <= ksawery.MAX_EXTENSION_DECLARATION_BYTES &&
		record.observation_bytes > 0 && record.observation_bytes <= ksawery.MAX_EXTENSION_OBSERVATION_BYTES &&
		record.result_bytes > 0 && record.result_bytes <= ksawery.MAX_EXTENSION_RESULT_BYTES &&
		record.provider_value_bytes > 0 && record.provider_value_bytes <= ksawery.MAX_EXTENSION_PROVIDER_VALUE_BYTES &&
		record.diagnostic_bytes > 0 && record.diagnostic_bytes <= ksawery.MAX_EXTENSION_DIAGNOSTIC_BYTES &&
		record.turn_deadline_ns > 0 && record.turn_deadline_ns <= u64(ksawery.MAX_EXTENSION_TURN_DEADLINE_NS) &&
		record.custodian_memory_bytes > 0 && record.custodian_memory_bytes <= ksawery.MAX_EXTENSION_CUSTODIAN_MEMORY_BYTES &&
		record.callbacks_per_turn > 0 && record.callbacks_per_turn <= u64(ksawery.MAX_EXTENSION_CALLBACKS_PER_TURN) &&
		record.nesting_depth == u64(ksawery.MAX_EXTENSION_NESTING_DEPTH) && record.retained_native_bytes > 0 &&
		record.retained_native_bytes <= ksawery.MAX_EXTENSION_RETAINED_NATIVE_BYTES && record.temporary_native_bytes > 0 &&
		record.temporary_native_bytes <= ksawery.MAX_EXTENSION_TEMPORARY_NATIVE_BYTES
}
