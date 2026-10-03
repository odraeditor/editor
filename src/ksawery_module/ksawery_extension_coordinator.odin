// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery_module

import bridge "../ksawery_bridge"
import "../ksawery"
import "base:runtime"
import "core:encoding/endian"

/* Ksawery_Extension_Provider_Data owns one copied personal contributor generation. */
Ksawery_Extension_Provider_Data :: struct {
	inspection:    ksawery.Contributor_Inspection,
	limits:        ksawery.Extension_Resource_Limits,
	contributions: []bridge.Ksawery_Extension_Contribution_Record,
	text:          []u8,
	active_scope:  ksawery.Extension_Turn_Scope,
	capability:    ksawery.Extension_Capability,
	turn_callbacks: u16,
	turn_active:   bool,
	enabled:       bool,
	status:        ^Ksawery_Extension_Status_Data,
	annotations:   [6]^Ksawery_Extension_Annotation_Data,
	allocator:     runtime.Allocator,
}

/* Ksawery_Extension_Provider_Candidate owns a prepared generation until publication. */
Ksawery_Extension_Provider_Candidate :: struct {
	data:                         ^Ksawery_Extension_Provider_Data,
	expected_personal_generation: u64,
	confirmed:                    bool,
	allocator:                    runtime.Allocator,
}

/* Ksawery_Extension_Provider_Registry owns the last confirmed personal contributor. */
Ksawery_Extension_Provider_Registry :: struct {
	active:              ^Ksawery_Extension_Provider_Data,
	personal_generation: u64,
	capability_generation: u64,
	latest_failure:      ksawery.Extension_Failure,
	allocator:           runtime.Allocator,
	closed:              bool,
}

/* ksawery_extension_provider_registry_init creates one empty native owner. */
ksawery_extension_provider_registry_init :: proc(
	registry: ^Ksawery_Extension_Provider_Registry,
	allocator := context.allocator,
) -> bool {
	if registry == nil || registry.allocator.procedure != nil || registry.closed ||
	   allocator.procedure == nil {
		return false
	}
	registry^ = {capability_generation = 1, allocator = allocator}
	return true
}

/* ksawery_extension_provider_prepare validates and copies one complete bridge batch. */
ksawery_extension_provider_prepare :: proc(
	registry: ^Ksawery_Extension_Provider_Registry,
	input: []u8,
	expected_personal_generation: u64,
) -> (candidate: Ksawery_Extension_Provider_Candidate, ok: bool, failure: ksawery.Extension_Failure) {
	if !ksawery_extension_provider_registry_is_open(registry) || len(input) == 0 ||
	   expected_personal_generation == 0 ||
	   expected_personal_generation <= registry.personal_generation {
		return {}, false, ksawery_extension_provider_reject(registry, .Stale_Contributor, .Prepare)
	}
	if registry.active != nil && registry.active.turn_active {
		return {}, false, ksawery_extension_provider_reject(registry, .Reentrant_Turn, .Prepare)
	}
	data, decoded, decode_failure := ksawery_extension_provider_decode(
		input,
		expected_personal_generation,
		registry.allocator,
	)
	if !decoded {
		if registry != nil do registry.latest_failure = decode_failure
		return {}, false, decode_failure
	}
	return {
		data = data,
		expected_personal_generation = expected_personal_generation,
		allocator = registry.allocator,
	}, true, {}
}

/* ksawery_extension_provider_candidate_confirm makes one full candidate publishable. */
ksawery_extension_provider_candidate_confirm :: proc(
	candidate: ^Ksawery_Extension_Provider_Candidate,
) -> bool {
	if candidate == nil || candidate.data == nil || candidate.confirmed ||
	   candidate.data.inspection.lifecycle != .Prepared {
		return false
	}
	candidate.confirmed = true
	candidate.data.inspection.lifecycle = .Confirmed
	return true
}

/* ksawery_extension_provider_activate atomically replaces the active generation. */
ksawery_extension_provider_activate :: proc(
	registry: ^Ksawery_Extension_Provider_Registry,
	candidate: ^Ksawery_Extension_Provider_Candidate,
) -> (bool, ksawery.Extension_Failure) {
	if !ksawery_extension_provider_registry_is_open(registry) || candidate == nil ||
	   candidate.data == nil || !candidate.confirmed ||
	   candidate.expected_personal_generation <= registry.personal_generation ||
	   (registry.active != nil && registry.active.turn_active) {
		return false, ksawery_extension_provider_reject(registry, .Invalid_Declaration, .Activate)
	}
	prior := registry.active
	registry.active = candidate.data
	registry.active.enabled = true
	registry.active.inspection.lifecycle = .Active
	registry.personal_generation = candidate.expected_personal_generation
	registry.capability_generation += 1
	registry.latest_failure = {}
	candidate^ = {}
	if prior != nil {
		prior.inspection.lifecycle = .Replaced
		ksawery_extension_provider_data_close(prior)
	}
	return true, {}
}

/* ksawery_extension_provider_disable revokes one retained active generation. */
ksawery_extension_provider_disable :: proc(
	registry: ^Ksawery_Extension_Provider_Registry,
	handle: ksawery.Contributor_Handle,
) -> (bool, ksawery.Extension_Failure) {
	if !ksawery_extension_provider_registry_is_open(registry) || registry.active == nil ||
	   registry.active.turn_active || registry.active.inspection.handle != handle ||
	   !registry.active.enabled {
		return false, ksawery_extension_provider_reject(registry, .Stale_Contributor, .Disable)
	}
	registry.active.enabled = false
	registry.active.inspection.lifecycle = .Disabled
	ksawery_extension_annotations_omit_all(registry.active)
	ksawery_extension_status_omit(registry.active)
	registry.capability_generation += 1
	return true, {}
}

/* ksawery_extension_provider_remove releases the personal contributor after a confirmed reload. */
ksawery_extension_provider_remove :: proc(
	registry: ^Ksawery_Extension_Provider_Registry,
	personal_generation: u64,
) -> (bool, ksawery.Extension_Failure) {
	if !ksawery_extension_provider_registry_is_open(registry) || personal_generation == 0 ||
	   personal_generation <= registry.personal_generation ||
	   (registry.active != nil && registry.active.turn_active) {
		return false, ksawery_extension_provider_reject(registry, .Stale_Contributor, .Replace)
	}
	if registry.active != nil do ksawery_extension_provider_data_close(registry.active)
	registry.active = nil
	registry.personal_generation = personal_generation
	registry.capability_generation += 1
	registry.latest_failure = {}
	return true, {}
}

/* ksawery_extension_provider_inspect copies the active contributor summary. */
ksawery_extension_provider_inspect :: proc(
	registry: ^Ksawery_Extension_Provider_Registry,
) -> (ksawery.Contributor_Inspection, bool) {
	if !ksawery_extension_provider_registry_is_open(registry) || registry.active == nil {
		return {}, false
	}
	return registry.active.inspection, true
}

/* ksawery_extension_provider_turn_begin opens one non-reentrant scoped capability. */
ksawery_extension_provider_turn_begin :: proc(
	registry: ^Ksawery_Extension_Provider_Registry,
	scope: ksawery.Extension_Turn_Scope,
	requested: ksawery.Extension_Authorities,
) -> (ksawery.Extension_Capability, bool, ksawery.Extension_Failure) {
	if !ksawery_extension_provider_registry_is_open(registry) || registry.active == nil ||
	   !registry.active.enabled {
		return {}, false, ksawery_extension_provider_reject(registry, .Stale_Contributor, .Begin_Turn)
	}
	if registry.active.turn_active {
		return {}, false, ksawery_extension_provider_reject(registry, .Reentrant_Turn, .Begin_Turn)
	}
	if scope.contributor != registry.active.inspection.handle ||
	   !ksawery.extension_turn_scope_is_valid(scope, registry.active.limits) {
		return {}, false, ksawery_extension_provider_reject(registry, .Invalid_Scope, .Begin_Turn)
	}
	if requested == {} || requested - registry.active.inspection.requested_authority != {} {
		return {}, false, ksawery_extension_provider_reject(registry, .Authority_Unavailable, .Begin_Turn)
	}
	registry.capability_generation += 1
	active_scope := scope
	active_scope.capability_generation = ksawery.Extension_Capability_Generation(registry.capability_generation)
	registry.active.active_scope = active_scope
	registry.active.capability = {
		turn = active_scope.turn,
		contributor = active_scope.contributor,
		generation = active_scope.capability_generation,
		owner_thread = active_scope.owner_thread,
		authorities = requested,
	}
	registry.active.turn_active = true
	registry.active.turn_callbacks = 0
	registry.active.inspection.usage.turns += 1
	return registry.active.capability, true, {}
}

/* ksawery_extension_provider_authorize checks every revocable turn key and resource bound. */
ksawery_extension_provider_authorize :: proc(
	registry: ^Ksawery_Extension_Provider_Registry,
	capability: ksawery.Extension_Capability,
	current_scope: ksawery.Extension_Turn_Scope,
	current_thread: u64,
	required: ksawery.Extension_Authority,
	elapsed_ns: i64,
	memory_bytes: u64,
) -> (bool, ksawery.Extension_Failure) {
	if !ksawery_extension_provider_registry_is_open(registry) || registry.active == nil ||
	   !registry.active.turn_active {
		return false, ksawery_extension_provider_reject(registry, .Stale_Capability, .Publish)
	}
	if current_thread != registry.active.active_scope.owner_thread {
		return false, ksawery_extension_provider_reject(registry, .Wrong_Thread, .Publish)
	}
	if !ksawery.extension_turn_scope_matches(registry.active.active_scope, current_scope) {
		return false, ksawery_extension_provider_reject(registry, .Stale_Observation, .Publish)
	}
	if !ksawery.extension_capability_is_current(
		capability, registry.active.active_scope, current_thread, required) {
		return false, ksawery_extension_provider_reject(registry, .Stale_Capability, .Publish)
	}
	if elapsed_ns < 0 || elapsed_ns > registry.active.limits.turn_deadline_ns {
		return false, ksawery_extension_provider_reject(registry, .Timeout, .Publish)
	}
	if memory_bytes > registry.active.limits.custodian_memory_bytes {
		return false, ksawery_extension_provider_reject(registry, .Memory_Limit, .Publish)
	}
	if registry.active.turn_callbacks >= registry.active.active_scope.callback_budget {
		return false, ksawery_extension_provider_reject(registry, .Callback_Limit, .Publish)
	}
	registry.active.turn_callbacks += 1
	registry.active.inspection.usage.callbacks += 1
	return true, {}
}

/* ksawery_extension_provider_turn_end revokes the current capability. */
ksawery_extension_provider_turn_end :: proc(
	registry: ^Ksawery_Extension_Provider_Registry,
) -> bool {
	if !ksawery_extension_provider_registry_is_open(registry) || registry.active == nil ||
	   !registry.active.turn_active {
		return false
	}
	registry.active.turn_active = false
	registry.active.active_scope = {}
	registry.active.capability = {}
	registry.active.turn_callbacks = 0
	registry.capability_generation += 1
	return true
}

/* ksawery_extension_provider_candidate_close discards one unpublished candidate. */
ksawery_extension_provider_candidate_close :: proc(
	candidate: ^Ksawery_Extension_Provider_Candidate,
) -> bool {
	if candidate == nil || candidate.data == nil do return false
	ksawery_extension_provider_data_close(candidate.data)
	candidate^ = {}
	return true
}

/* ksawery_extension_provider_registry_close releases all retained provider state. */
ksawery_extension_provider_registry_close :: proc(
	registry: ^Ksawery_Extension_Provider_Registry,
) -> bool {
	if !ksawery_extension_provider_registry_is_open(registry) ||
	   (registry.active != nil && registry.active.turn_active) {
		return false
	}
	allocator := registry.allocator
	if registry.active != nil do ksawery_extension_provider_data_close(registry.active)
	registry^ = {allocator = allocator, closed = true}
	return true
}

@(private)
ksawery_extension_provider_decode :: proc(
	input: []u8,
	expected_generation: u64,
	allocator: runtime.Allocator,
) -> (^Ksawery_Extension_Provider_Data, bool, ksawery.Extension_Failure) {
	if len(input) < int(bridge.KSAWERY_EXTENSION_HEADER_BYTES) {
		return nil, false, {operation = .Load, code = .Invalid_Declaration}
	}
	header: bridge.Ksawery_Extension_Header_Record
	for index in 0 ..< 12 do ksawery_extension_assign_header_word(&header, index, ksawery_extension_word(input, index * 8))
	if header.contributor_count != 1 || header.contribution_count == 0 ||
	   header.contribution_count > u64(ksawery.MAX_EXTENSION_CONTRIBUTIONS_PER_CONTRIBUTOR) {
		return nil, false, {operation = .Load, code = .Contribution_Limit}
	}
	required, size_failure := bridge.ksawery_extension_record_bytes(
		header.contributor_count, header.contribution_count, header.text_bytes)
	if size_failure.code != .None || required != u64(len(input)) {
		return nil, false, {operation = .Load, code = .Invalid_Declaration}
	}
	contributor_offset := int(bridge.KSAWERY_EXTENSION_HEADER_BYTES)
	contribution_offset := contributor_offset + int(bridge.KSAWERY_EXTENSION_CONTRIBUTOR_RECORD_BYTES)
	limits_offset := contribution_offset + int(header.contribution_count * bridge.KSAWERY_EXTENSION_CONTRIBUTION_RECORD_BYTES)
	text_offset := limits_offset + int(bridge.KSAWERY_EXTENSION_LIMITS_RECORD_BYTES)
	contributor: bridge.Ksawery_Extension_Contributor_Record
	for index in 0 ..< 16 do ksawery_extension_assign_contributor_word(&contributor, index, ksawery_extension_word(input, contributor_offset + index * 8))
	limit_record: bridge.Ksawery_Extension_Limits_Record
	for index in 0 ..< 14 do ksawery_extension_assign_limits_word(&limit_record, index, ksawery_extension_word(input, limits_offset + index * 8))
	records: [ksawery.MAX_EXTENSION_CONTRIBUTIONS_PER_CONTRIBUTOR]bridge.Ksawery_Extension_Contribution_Record
	for record_index in 0 ..< int(header.contribution_count) {
		base := contribution_offset + record_index * int(bridge.KSAWERY_EXTENSION_CONTRIBUTION_RECORD_BYTES)
		for word_index in 0 ..< 8 do ksawery_extension_assign_contribution_word(&records[record_index], word_index, ksawery_extension_word(input, base + word_index * 8))
	}
	contributors := [?]bridge.Ksawery_Extension_Contributor_Record {contributor}
	limits := [?]bridge.Ksawery_Extension_Limits_Record {limit_record}
	text := input[text_offset:]
	record_failure := bridge.ksawery_extension_records_validate(
		header, contributors[:], records[:int(header.contribution_count)], limits[:], text,
		expected_generation)
	if record_failure.code != .None {
		return nil, false, {operation = .Load, code = .Invalid_Declaration, limit = record_failure.limit, actual = record_failure.actual}
	}
	data, allocation_error := new(Ksawery_Extension_Provider_Data, allocator)
	if allocation_error != nil do return nil, false, {operation = .Load, code = .Allocation}
	data.allocator = allocator
	defer if data != nil do ksawery_extension_provider_data_close(data)
	data.contributions, allocation_error = make([]bridge.Ksawery_Extension_Contribution_Record, int(header.contribution_count), allocator)
	if allocation_error != nil do return nil, false, {operation = .Load, code = .Allocation}
	copy(data.contributions, records[:int(header.contribution_count)])
	data.text, allocation_error = make([]u8, len(text), allocator)
	if allocation_error != nil do return nil, false, {operation = .Load, code = .Allocation}
	copy(data.text, text)
	data.limits = ksawery_extension_limits_from_record(limit_record)
	identity := bridge.ksawery_extension_text(text, contributor.identity_offset, contributor.identity_bytes)
	label := bridge.ksawery_extension_text(text, contributor.label_offset, contributor.label_bytes)
	provenance := bridge.ksawery_extension_text(text, contributor.provenance_offset, contributor.provenance_bytes)
	_ = ksawery.contributor_identity_assign(&data.inspection.identity, identity)
	_ = ksawery.extension_label_assign(&data.inspection.display_name, label)
	_ = ksawery.contributor_provenance_assign(&data.inspection.provenance, ksawery.Contributor_Origin(contributor.origin), provenance)
	data.inspection.handle = {contributor = ksawery.Contributor_ID(contributor.contributor_id), generation = ksawery.Contributor_Generation(contributor.contributor_generation)}
	data.inspection.lifecycle = .Prepared
	data.inspection.requested_authority = transmute(ksawery.Extension_Authorities)u16(contributor.authorities)
	data.inspection.contribution_count = u32(header.contribution_count)
	data.inspection.provider_role_count = u16(contributor.provider_role_count)
	data.inspection.usage = {
		contributions = u32(header.contribution_count),
		declaration_bytes = header.record_bytes,
		retained_native_bytes = u64(size_of(Ksawery_Extension_Provider_Data) + len(data.contributions) * size_of(bridge.Ksawery_Extension_Contribution_Record) + len(data.text)),
	}
	data.enabled = false
	result := data
	data = nil
	return result, true, {}
}

@(private)
ksawery_extension_provider_data_close :: proc(data: ^Ksawery_Extension_Provider_Data) {
	if data == nil do return
	allocator := data.allocator
	if data.status != nil do ksawery_extension_status_data_close(data.status)
	for annotation_data in data.annotations {
		if annotation_data != nil do ksawery_extension_annotation_data_close(annotation_data)
	}
	delete(data.contributions, allocator)
	delete(data.text, allocator)
	free(data, allocator)
}

@(private)
ksawery_extension_provider_reject :: proc(
	registry: ^Ksawery_Extension_Provider_Registry,
	code: ksawery.Extension_Failure_Code,
	operation: ksawery.Extension_Operation,
) -> ksawery.Extension_Failure {
	failure := ksawery.Extension_Failure{code = code, operation = operation}
	if registry != nil {
		registry.latest_failure = failure
		if registry.active != nil {
			registry.active.inspection.latest_failure = failure
			registry.active.inspection.usage.failures += 1
		}
	}
	return failure
}

@(private)
ksawery_extension_provider_registry_is_open :: proc(registry: ^Ksawery_Extension_Provider_Registry) -> bool {
	return registry != nil && registry.allocator.procedure != nil && !registry.closed
}

@(private)
ksawery_extension_word :: proc(input: []u8, offset: int) -> u64 {
	value, ok := endian.get_u64(input[offset:], .Little)
	assert(ok)
	return value
}

@(private)
ksawery_extension_assign_header_word :: proc(record: ^bridge.Ksawery_Extension_Header_Record, index: int, value: u64) {
	switch index {case 0: record.schema_version = value; case 1: record.record_bytes = value; case 2: record.api_version = value; case 3: record.registry_generation = value; case 4: record.contributor_count = value; case 5: record.contribution_count = value; case 6: record.text_bytes = value; case 7: record.limits_offset = value; case 8: record.limits_count = value; case 9: record.reserved_0 = value; case 10: record.reserved_1 = value; case 11: record.reserved_2 = value}
}

@(private)
ksawery_extension_assign_contributor_word :: proc(record: ^bridge.Ksawery_Extension_Contributor_Record, index: int, value: u64) {
	switch index {case 0: record.contributor_id = value; case 1: record.contributor_generation = value; case 2: record.origin = value; case 3: record.lifecycle = value; case 4: record.identity_offset = value; case 5: record.identity_bytes = value; case 6: record.label_offset = value; case 7: record.label_bytes = value; case 8: record.provenance_offset = value; case 9: record.provenance_bytes = value; case 10: record.authorities = value; case 11: record.first_contribution = value; case 12: record.contribution_count = value; case 13: record.limits_index = value; case 14: record.provider_role_count = value; case 15: record.reserved = value}
}

@(private)
ksawery_extension_assign_contribution_word :: proc(record: ^bridge.Ksawery_Extension_Contribution_Record, index: int, value: u64) {
	switch index {case 0: record.contribution_id = value; case 1: record.kind = value; case 2: record.provider_role = value; case 3: record.required_observations = value; case 4: record.requested_authorities = value; case 5: record.identity_offset = value; case 6: record.identity_bytes = value; case 7: record.reserved = value}
}

@(private)
ksawery_extension_assign_limits_word :: proc(record: ^bridge.Ksawery_Extension_Limits_Record, index: int, value: u64) {
	switch index {case 0: record.contributors = value; case 1: record.contributions_per_contributor = value; case 2: record.total_contributions = value; case 3: record.declaration_bytes = value; case 4: record.observation_bytes = value; case 5: record.result_bytes = value; case 6: record.provider_value_bytes = value; case 7: record.diagnostic_bytes = value; case 8: record.turn_deadline_ns = value; case 9: record.custodian_memory_bytes = value; case 10: record.callbacks_per_turn = value; case 11: record.nesting_depth = value; case 12: record.retained_native_bytes = value; case 13: record.temporary_native_bytes = value}
}

@(private)
ksawery_extension_limits_from_record :: proc(record: bridge.Ksawery_Extension_Limits_Record) -> ksawery.Extension_Resource_Limits {
	return {contributors = u16(record.contributors), contributions_per_contributor = u16(record.contributions_per_contributor), total_contributions = u32(record.total_contributions), declaration_bytes = record.declaration_bytes, observation_bytes = record.observation_bytes, result_bytes = record.result_bytes, provider_value_bytes = record.provider_value_bytes, diagnostic_bytes = record.diagnostic_bytes, turn_deadline_ns = i64(record.turn_deadline_ns), custodian_memory_bytes = record.custodian_memory_bytes, callbacks_per_turn = u16(record.callbacks_per_turn), nesting_depth = u8(record.nesting_depth), retained_native_bytes = record.retained_native_bytes, temporary_native_bytes = record.temporary_native_bytes}
}
