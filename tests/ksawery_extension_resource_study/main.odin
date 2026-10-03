// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "base:runtime"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:time"

KIBIBYTE :: 1_024
MEBIBYTE :: 1_024 * KIBIBYTE

SELECTED_DEFAULT_CONTRIBUTORS :: 8
SELECTED_MAX_CONTRIBUTORS :: 32
SELECTED_ACTIVE_GENERATIONS_PER_CONTRIBUTOR :: 1
SELECTED_MAX_ACTIVE_GENERATIONS :: SELECTED_MAX_CONTRIBUTORS
SELECTED_DEFAULT_CONTRIBUTIONS_PER_CONTRIBUTOR :: 16
SELECTED_MAX_CONTRIBUTIONS_PER_CONTRIBUTOR :: 64
SELECTED_DEFAULT_TOTAL_CONTRIBUTIONS :: 128
SELECTED_MAX_TOTAL_CONTRIBUTIONS :: 2_048
SELECTED_IDENTITY_BYTES :: 96
SELECTED_LABEL_BYTES :: 128
SELECTED_PROVENANCE_BYTES :: 1 * KIBIBYTE
SELECTED_DEFAULT_DECLARATION_BYTES :: 1 * MEBIBYTE
SELECTED_MAX_DECLARATION_BYTES :: 8 * MEBIBYTE
SELECTED_DEFAULT_OBSERVATION_BYTES :: 1 * MEBIBYTE
SELECTED_MAX_OBSERVATION_BYTES :: 8 * MEBIBYTE
SELECTED_DEFAULT_RESULT_BYTES :: 1 * MEBIBYTE
SELECTED_MAX_RESULT_BYTES :: 8 * MEBIBYTE
SELECTED_DEFAULT_PROVIDER_VALUE_BYTES :: 256 * KIBIBYTE
SELECTED_MAX_PROVIDER_VALUE_BYTES :: 4 * MEBIBYTE
SELECTED_DEFAULT_DIAGNOSTIC_BYTES :: 4 * KIBIBYTE
SELECTED_MAX_DIAGNOSTIC_BYTES :: 64 * KIBIBYTE
SELECTED_DEFAULT_TURN_DEADLINE_MS :: 250
SELECTED_MAX_TURN_DEADLINE_MS :: 2_000
SELECTED_DEFAULT_CUSTODIAN_MEMORY_BYTES :: 32 * MEBIBYTE
SELECTED_MAX_CUSTODIAN_MEMORY_BYTES :: 128 * MEBIBYTE
SELECTED_DEFAULT_CALLBACKS_PER_TURN :: 64
SELECTED_MAX_CALLBACKS_PER_TURN :: 256
SELECTED_MAX_NESTING_DEPTH :: 1
SELECTED_MAX_RETAINED_NATIVE_BYTES :: 32 * MEBIBYTE
SELECTED_MAX_TEMPORARY_NATIVE_BYTES :: 32 * MEBIBYTE
SELECTED_DEFAULT_EXTERNAL_OPERATIONS :: 128
SELECTED_MAX_EXTERNAL_OPERATIONS :: 512
SELECTED_DEFAULT_EXTERNAL_ARGUMENTS :: 16
SELECTED_MAX_EXTERNAL_ARGUMENTS :: 64
SELECTED_MAX_EXTERNAL_ARGUMENT_BYTES :: 512
SELECTED_MAX_EXTERNAL_ARGUMENT_VECTOR_BYTES :: 8 * MEBIBYTE
SELECTED_MAX_EXTERNAL_EXECUTABLE_BYTES :: 4 * KIBIBYTE
SELECTED_DEFAULT_EXTERNAL_OUTPUT_BYTES :: 1 * MEBIBYTE
SELECTED_MAX_EXTERNAL_OUTPUT_BYTES :: 8 * MEBIBYTE
SELECTED_DEFAULT_EXTERNAL_DEADLINE_MS :: 30_000
SELECTED_MAX_EXTERNAL_DEADLINE_MS :: 600_000
SELECTED_MAX_EXTERNAL_RETAINED_NATIVE_BYTES :: 32 * MEBIBYTE
SELECTED_MAX_EXTERNAL_TEMPORARY_NATIVE_BYTES :: 32 * MEBIBYTE
SELECTED_MAX_WORKFLOW_RECORDS :: SELECTED_MAX_CONTRIBUTORS * 9
SELECTED_MAX_WORKFLOW_ITEMS :: 256
SELECTED_MAX_COMMAND_FAMILY_COPY_BYTES :: 8 * MEBIBYTE
SELECTED_MAX_PROCESS_RECORD_BYTES :: 8 * MEBIBYTE
SELECTED_MAX_CONFLICT_COPY_BYTES :: 8 * MEBIBYTE
SELECTED_MAX_RAW_COMMAND_BYTES :: 4 * KIBIBYTE
SELECTED_MAX_WORKFLOW_OUTPUT_BYTES :: 8 * MEBIBYTE
SELECTED_MAX_WORKFLOW_DIAGNOSTIC_BYTES :: 64 * KIBIBYTE
SELECTED_MAX_WORKFLOW_RETAINED_NATIVE_BYTES :: 32 * MEBIBYTE
SELECTED_MAX_WORKFLOW_TEMPORARY_NATIVE_BYTES :: 32 * MEBIBYTE
PROFILE_GATE_NS :: i64(2_000_000_000)
TURN_GATE_NS :: i64(1_000_000_000)

Contribution_Role :: enum u8 {
	Invalid,
	Status,
	Annotation,
	Command,
	External_Operation,
	Conflict_Assistance,
}

Generation_Lifecycle :: enum u8 {
	Invalid,
	Candidate,
	Confirmed,
	Active,
	Rejected,
	Failed,
	Disabled,
	Retiring,
	Closed,
}

Declaration_Record :: struct {
	contributor_id:    u64,
	generation:        u64,
	contribution_id:   u64,
	role:              Contribution_Role,
	identity_offset:   u32,
	identity_bytes:    u16,
	label_offset:      u32,
	label_bytes:       u16,
	provenance_offset: u32,
	provenance_bytes:  u16,
}

Turn_Scope :: struct {
	contributor_id:        u64,
	contributor_generation: u64,
	repository_generation:  u64,
	observation_generation: u64,
	capability_generation:  u64,
	callback_budget:        u16,
}

Generation_Storage :: struct {
	generation:     u64,
	lifecycle:      Generation_Lifecycle,
	records:        []Declaration_Record,
	text:           []u8,
	observation:    []u8,
	result:         []u8,
	provider_value: []u8,
	diagnostic:     []u8,
	allocator:      mem.Allocator,
}

Study_Profile :: struct {
	name:                          string,
	contributors:                  int,
	contributions_per_contributor: int,
	identity_bytes:                int,
	label_bytes:                   int,
	provenance_bytes:              int,
	observation_bytes:             int,
	result_bytes:                  int,
	provider_value_bytes:          int,
	diagnostic_bytes:              int,
	turns:                         int,
}

Study_Measurement :: struct {
	records:         int,
	retained_bytes:  i64,
	peak_bytes:      i64,
	turn_elapsed_ns: i64,
	elapsed_ns:      i64,
	cleanup_bytes:   i64,
}

Fault_Allocator :: struct {
	backing:                runtime.Allocator,
	fail_after:             u64,
	successful_allocations: u64,
}

External_Executable_Kind :: enum u8 {
	Invalid,
	Built_In_Git,
	Absolute_Path,
}

External_Effect_Class :: enum u8 {
	Invalid,
	Read_Only,
	Repository_Mutating,
	Externally_Mutating,
}

External_Observation_Family :: enum u8 {
	Status,
	History,
	Refs,
	Sequence,
	Conflict,
	Process,
}

External_Observation_Families :: bit_set[External_Observation_Family; u8]

External_Verifier_Kind :: enum u8 {
	None,
	Status_Refresh,
	Ref_Refresh,
	External_Predicate,
}

External_Operation_Outcome :: enum u8 {
	Invalid,
	Verified,
	Failed,
	Indeterminate,
	Cancelled,
}

External_Argument_Record :: struct {
	offset: u32,
	bytes:  u16,
}

External_Operation_Record :: struct {
	id:                 u64,
	executable_kind:    External_Executable_Kind,
	effect:             External_Effect_Class,
	observations:       External_Observation_Families,
	verifier:           External_Verifier_Kind,
	cancellable:        bool,
	identity_offset:    u32,
	identity_bytes:     u16,
	purpose_offset:     u32,
	purpose_bytes:      u16,
	executable_offset:  u32,
	executable_bytes:   u16,
	argument_start:     u32,
	argument_count:     u16,
	output_limit:       u64,
	diagnostic_limit:   u64,
	deadline_ms:        u32,
}

External_Operation_Storage :: struct {
	records:     []External_Operation_Record,
	arguments:   []External_Argument_Record,
	text:        []u8,
	output:      []u8,
	diagnostic:  []u8,
	allocator:   mem.Allocator,
}

External_Study_Profile :: struct {
	name:                 string,
	operations:           int,
	arguments_per_plan:   int,
	argument_bytes:       int,
	absolute_path_bytes:  int,
	output_bytes:         int,
	diagnostic_bytes:     int,
	deadline_ms:          int,
	turns:                int,
}

Workflow_Record_Kind :: enum u8 {
	Invalid,
	Status_Section,
	Annotation,
	Command,
	Command_Family,
	External_Operation,
	Raw_Command,
	Conflict_Assistance,
	Process_Record,
	Refresh,
}

Workflow_Outcome :: enum u8 {
	Invalid,
	Completed,
	Cancelled,
	Timed_Out,
	Truncated,
	Failed,
}

Workflow_Lifecycle :: enum u8 {
	Invalid,
	Candidate,
	Active,
	Reloading,
	Disabled,
	Retiring,
	Closed,
}

Workflow_Record :: struct {
	contributor_id: u64,
	generation:     u64,
	kind:           Workflow_Record_Kind,
	bounded_items:  u16,
	refresh:        External_Observation_Families,
}

Workflow_Storage :: struct {
	generation:      u64,
	lifecycle:       Workflow_Lifecycle,
	provider_enabled: bool,
	fallback_active: bool,
	records:         []Workflow_Record,
	declarations:    []u8,
	command_family:  []u8,
	process_records: []u8,
	conflict_copy:   []u8,
	raw_command:     []u8,
	output:          []u8,
	diagnostic:      []u8,
	allocator:       mem.Allocator,
}

Workflow_Study_Profile :: struct {
	name:                 string,
	contributors:         int,
	declaration_bytes:    int,
	command_family_bytes: int,
	process_record_bytes: int,
	conflict_copy_bytes:  int,
	raw_command_bytes:    int,
	output_bytes:         int,
	diagnostic_bytes:     int,
	turns:                int,
}

Workflow_Coverage :: struct {
	kinds:         [9]int,
	outcomes:      [5]int,
	refreshes:     int,
	cancellations: int,
	timeouts:      int,
	truncations:   int,
}

main :: proc() {
	profiles := [?]Study_Profile {
		{
			name = "ordinary",
			contributors = 2,
			contributions_per_contributor = 8,
			identity_bytes = 24,
			label_bytes = 48,
			provenance_bytes = 128,
			observation_bytes = 64 * KIBIBYTE,
			result_bytes = 64 * KIBIBYTE,
			provider_value_bytes = 16 * KIBIBYTE,
			diagnostic_bytes = 1 * KIBIBYTE,
			turns = 10_000,
		},
		{
			name = "demanding",
			contributors = SELECTED_DEFAULT_CONTRIBUTORS,
			contributions_per_contributor = SELECTED_DEFAULT_CONTRIBUTIONS_PER_CONTRIBUTOR,
			identity_bytes = 64,
			label_bytes = 96,
			provenance_bytes = 512,
			observation_bytes = SELECTED_DEFAULT_OBSERVATION_BYTES,
			result_bytes = SELECTED_DEFAULT_RESULT_BYTES,
			provider_value_bytes = SELECTED_DEFAULT_PROVIDER_VALUE_BYTES,
			diagnostic_bytes = SELECTED_DEFAULT_DIAGNOSTIC_BYTES,
			turns = 50_000,
		},
		{
			name = "stress",
			contributors = SELECTED_MAX_CONTRIBUTORS,
			contributions_per_contributor = SELECTED_MAX_CONTRIBUTIONS_PER_CONTRIBUTOR,
			identity_bytes = SELECTED_IDENTITY_BYTES,
			label_bytes = SELECTED_LABEL_BYTES,
			provenance_bytes = SELECTED_PROVENANCE_BYTES,
			observation_bytes = SELECTED_MAX_OBSERVATION_BYTES,
			result_bytes = SELECTED_MAX_RESULT_BYTES,
			provider_value_bytes = SELECTED_MAX_PROVIDER_VALUE_BYTES,
			diagnostic_bytes = SELECTED_MAX_DIAGNOSTIC_BYTES,
			turns = 100_000,
		},
	}

	passed := print_policy()
	for profile in profiles {
		passed = run_profile(profile) && passed
	}
	passed = run_invalid_shapes() && passed
	passed = run_allocation_fault() && passed
	passed = run_external_operation_profiles() && passed
	passed = run_external_operation_invalid_shapes() && passed
	passed = run_external_operation_allocation_fault() && passed
	passed = run_workflow_profiles() && passed
	passed = run_workflow_invalid_shapes() && passed
	passed = run_workflow_allocation_fault() && passed
	if !passed do os.exit(1)
}

print_policy :: proc() -> bool {
	valid := SELECTED_DEFAULT_CONTRIBUTORS < SELECTED_MAX_CONTRIBUTORS &&
		SELECTED_ACTIVE_GENERATIONS_PER_CONTRIBUTOR == 1 &&
		SELECTED_MAX_ACTIVE_GENERATIONS == SELECTED_MAX_CONTRIBUTORS &&
		SELECTED_DEFAULT_CONTRIBUTIONS_PER_CONTRIBUTOR < SELECTED_MAX_CONTRIBUTIONS_PER_CONTRIBUTOR &&
		SELECTED_DEFAULT_CONTRIBUTORS * SELECTED_DEFAULT_CONTRIBUTIONS_PER_CONTRIBUTOR == SELECTED_DEFAULT_TOTAL_CONTRIBUTIONS &&
		SELECTED_DEFAULT_TOTAL_CONTRIBUTIONS < SELECTED_MAX_TOTAL_CONTRIBUTIONS &&
		SELECTED_MAX_CONTRIBUTORS * SELECTED_MAX_CONTRIBUTIONS_PER_CONTRIBUTOR == SELECTED_MAX_TOTAL_CONTRIBUTIONS &&
		SELECTED_DEFAULT_TURN_DEADLINE_MS < SELECTED_MAX_TURN_DEADLINE_MS &&
		SELECTED_DEFAULT_CUSTODIAN_MEMORY_BYTES < SELECTED_MAX_CUSTODIAN_MEMORY_BYTES &&
		SELECTED_DEFAULT_CALLBACKS_PER_TURN < SELECTED_MAX_CALLBACKS_PER_TURN &&
		SELECTED_MAX_NESTING_DEPTH == 1
	fmt.printf(
		"study=ksawery-extension profile=policy valid=%v default_contributors=%d max_contributors=%d active_generations_per_contributor=%d max_active_generations=%d default_contributions_per_contributor=%d max_contributions_per_contributor=%d default_total_contributions=%d max_total_contributions=%d identity_bytes=%d label_bytes=%d provenance_bytes=%d default_declaration_bytes=%d max_declaration_bytes=%d default_observation_bytes=%d max_observation_bytes=%d default_result_bytes=%d max_result_bytes=%d default_provider_value_bytes=%d max_provider_value_bytes=%d default_diagnostic_bytes=%d max_diagnostic_bytes=%d default_turn_deadline_ms=%d max_turn_deadline_ms=%d default_custodian_memory_bytes=%d max_custodian_memory_bytes=%d default_callbacks_per_turn=%d max_callbacks_per_turn=%d max_nesting_depth=%d max_retained_native_bytes=%d max_temporary_native_bytes=%d\n",
		valid,
		SELECTED_DEFAULT_CONTRIBUTORS,
		SELECTED_MAX_CONTRIBUTORS,
		SELECTED_ACTIVE_GENERATIONS_PER_CONTRIBUTOR,
		SELECTED_MAX_ACTIVE_GENERATIONS,
		SELECTED_DEFAULT_CONTRIBUTIONS_PER_CONTRIBUTOR,
		SELECTED_MAX_CONTRIBUTIONS_PER_CONTRIBUTOR,
		SELECTED_DEFAULT_TOTAL_CONTRIBUTIONS,
		SELECTED_MAX_TOTAL_CONTRIBUTIONS,
		SELECTED_IDENTITY_BYTES,
		SELECTED_LABEL_BYTES,
		SELECTED_PROVENANCE_BYTES,
		SELECTED_DEFAULT_DECLARATION_BYTES,
		SELECTED_MAX_DECLARATION_BYTES,
		SELECTED_DEFAULT_OBSERVATION_BYTES,
		SELECTED_MAX_OBSERVATION_BYTES,
		SELECTED_DEFAULT_RESULT_BYTES,
		SELECTED_MAX_RESULT_BYTES,
		SELECTED_DEFAULT_PROVIDER_VALUE_BYTES,
		SELECTED_MAX_PROVIDER_VALUE_BYTES,
		SELECTED_DEFAULT_DIAGNOSTIC_BYTES,
		SELECTED_MAX_DIAGNOSTIC_BYTES,
		SELECTED_DEFAULT_TURN_DEADLINE_MS,
		SELECTED_MAX_TURN_DEADLINE_MS,
		SELECTED_DEFAULT_CUSTODIAN_MEMORY_BYTES,
		SELECTED_MAX_CUSTODIAN_MEMORY_BYTES,
		SELECTED_DEFAULT_CALLBACKS_PER_TURN,
		SELECTED_MAX_CALLBACKS_PER_TURN,
		SELECTED_MAX_NESTING_DEPTH,
		SELECTED_MAX_RETAINED_NATIVE_BYTES,
		SELECTED_MAX_TEMPORARY_NATIVE_BYTES,
	)
	return valid
}

run_profile :: proc(profile: Study_Profile) -> bool {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	started := time.tick_now()
	active, active_ready := build_generation(profile, 1, allocator)
	if !active_ready {
		mem.tracking_allocator_destroy(&tracking)
		return false
	}
	active.lifecycle = .Active
	turn_started := time.tick_now()
	turns_valid := exercise_scoped_turns(&active, profile.turns)
	turn_elapsed_ns := time.duration_nanoseconds(time.tick_since(turn_started))
	candidate, candidate_ready := build_generation(profile, 2, allocator)
	if candidate_ready {
		candidate.lifecycle = .Confirmed
	}
	replacement_valid := candidate_ready && generation_valid(&active) && generation_valid(&candidate)
	if replacement_valid {
		candidate.lifecycle = .Active
		active.lifecycle = .Retiring
		generation_close(&active)
	}
	retained_bytes := tracking.current_memory_allocated
	peak_bytes := tracking.peak_memory_allocated
	if candidate_ready do generation_close(&candidate)
	if active.records != nil do generation_close(&active)
	measurement := Study_Measurement {
		records = profile.contributors * profile.contributions_per_contributor,
		retained_bytes = retained_bytes,
		peak_bytes = peak_bytes,
		turn_elapsed_ns = turn_elapsed_ns,
		elapsed_ns = time.duration_nanoseconds(time.tick_since(started)),
		cleanup_bytes = tracking.current_memory_allocated,
	}
	mem.tracking_allocator_destroy(&tracking)
	valid := replacement_valid && turns_valid &&
		measurement.records <= SELECTED_MAX_TOTAL_CONTRIBUTIONS &&
		measurement.retained_bytes <= SELECTED_MAX_RETAINED_NATIVE_BYTES &&
		measurement.peak_bytes <= SELECTED_MAX_RETAINED_NATIVE_BYTES + SELECTED_MAX_TEMPORARY_NATIVE_BYTES &&
		measurement.turn_elapsed_ns <= TURN_GATE_NS &&
		measurement.elapsed_ns <= PROFILE_GATE_NS && measurement.cleanup_bytes == 0
	fmt.printf(
		"study=ksawery-extension profile=%s valid=%v contributors=%d records=%d retained_bytes=%d peak_bytes=%d turn_count=%d turn_elapsed_ns=%d elapsed_ns=%d replacement=true cleanup_bytes=%d\n",
		profile.name,
		valid,
		profile.contributors,
		measurement.records,
		measurement.retained_bytes,
		measurement.peak_bytes,
		profile.turns,
		measurement.turn_elapsed_ns,
		measurement.elapsed_ns,
		measurement.cleanup_bytes,
	)
	return valid
}

build_generation :: proc(
	profile: Study_Profile,
	generation: u64,
	allocator: mem.Allocator,
) -> (storage: Generation_Storage, ok: bool) {
	storage.allocator = allocator
	storage.generation = generation
	storage.lifecycle = .Candidate
	if !profile_is_admitted(profile) || generation == 0 do return storage, false
	record_count := profile.contributors * profile.contributions_per_contributor
	text_bytes := record_count * (profile.identity_bytes + profile.label_bytes + profile.provenance_bytes)
	allocation_error: mem.Allocator_Error
	storage.records, allocation_error = make([]Declaration_Record, record_count, allocator)
	if allocation_error == nil do storage.text, allocation_error = make([]u8, text_bytes, allocator)
	if allocation_error == nil do storage.observation, allocation_error = make([]u8, profile.observation_bytes, allocator)
	if allocation_error == nil do storage.result, allocation_error = make([]u8, profile.result_bytes, allocator)
	if allocation_error == nil do storage.provider_value, allocation_error = make([]u8, profile.provider_value_bytes, allocator)
	if allocation_error == nil do storage.diagnostic, allocation_error = make([]u8, profile.diagnostic_bytes, allocator)
	if allocation_error != nil {
		generation_close(&storage)
		return storage, false
	}

	offset := 0
	for record_index in 0 ..< record_count {
		contributor_index := record_index / profile.contributions_per_contributor
		storage.records[record_index] = Declaration_Record {
			contributor_id = u64(contributor_index + 1),
			generation = generation,
			contribution_id = u64(record_index + 1),
			role = Contribution_Role(record_index % int(Contribution_Role.Conflict_Assistance) + 1),
			identity_offset = u32(offset),
			identity_bytes = u16(profile.identity_bytes),
			label_offset = u32(offset + profile.identity_bytes),
			label_bytes = u16(profile.label_bytes),
			provenance_offset = u32(offset + profile.identity_bytes + profile.label_bytes),
			provenance_bytes = u16(profile.provenance_bytes),
		}
		offset += profile.identity_bytes + profile.label_bytes + profile.provenance_bytes
	}
	for &value, index in storage.text do value = u8(index % 251 + 1)
	for &value in storage.observation do value = 0x4f
	for &value in storage.result do value = 0x52
	for &value in storage.provider_value do value = 0x56
	for &value in storage.diagnostic do value = 0x44
	return storage, generation_valid(&storage)
}

generation_valid :: proc(storage: ^Generation_Storage) -> bool {
	if storage == nil || storage.generation == 0 || storage.lifecycle == .Invalid ||
	   len(storage.records) == 0 || len(storage.records) > SELECTED_MAX_TOTAL_CONTRIBUTIONS ||
	   len(storage.text) > SELECTED_MAX_DECLARATION_BYTES ||
	   len(storage.observation) > SELECTED_MAX_OBSERVATION_BYTES ||
	   len(storage.result) > SELECTED_MAX_RESULT_BYTES ||
	   len(storage.provider_value) > SELECTED_MAX_PROVIDER_VALUE_BYTES ||
	   len(storage.diagnostic) > SELECTED_MAX_DIAGNOSTIC_BYTES {
		return false
	}
	for record in storage.records {
		if !declaration_record_valid(record, len(storage.text), storage.generation) do return false
	}
	return true
}

declaration_record_valid :: proc(record: Declaration_Record, text_bytes: int, generation: u64) -> bool {
	return record.contributor_id != 0 && record.generation == generation &&
		record.contribution_id != 0 && record.role > .Invalid && record.role <= .Conflict_Assistance &&
		record.identity_bytes > 0 && int(record.identity_bytes) <= SELECTED_IDENTITY_BYTES &&
		record.label_bytes > 0 && int(record.label_bytes) <= SELECTED_LABEL_BYTES &&
		record.provenance_bytes > 0 && int(record.provenance_bytes) <= SELECTED_PROVENANCE_BYTES &&
		int(record.identity_offset) + int(record.identity_bytes) <= text_bytes &&
		int(record.label_offset) + int(record.label_bytes) <= text_bytes &&
		int(record.provenance_offset) + int(record.provenance_bytes) <= text_bytes
}

profile_is_admitted :: proc(profile: Study_Profile) -> bool {
	record_count := profile.contributors * profile.contributions_per_contributor
	declaration_bytes := record_count * (
		profile.identity_bytes + profile.label_bytes + profile.provenance_bytes + size_of(Declaration_Record))
	return profile.contributors > 0 && profile.contributors <= SELECTED_MAX_CONTRIBUTORS &&
		profile.contributions_per_contributor > 0 &&
		profile.contributions_per_contributor <= SELECTED_MAX_CONTRIBUTIONS_PER_CONTRIBUTOR &&
		record_count <= SELECTED_MAX_TOTAL_CONTRIBUTIONS &&
		profile.identity_bytes > 0 && profile.identity_bytes <= SELECTED_IDENTITY_BYTES &&
		profile.label_bytes > 0 && profile.label_bytes <= SELECTED_LABEL_BYTES &&
		profile.provenance_bytes > 0 && profile.provenance_bytes <= SELECTED_PROVENANCE_BYTES &&
		declaration_bytes <= SELECTED_MAX_DECLARATION_BYTES &&
		profile.observation_bytes > 0 && profile.observation_bytes <= SELECTED_MAX_OBSERVATION_BYTES &&
		profile.result_bytes > 0 && profile.result_bytes <= SELECTED_MAX_RESULT_BYTES &&
		profile.provider_value_bytes > 0 && profile.provider_value_bytes <= SELECTED_MAX_PROVIDER_VALUE_BYTES &&
		profile.diagnostic_bytes > 0 && profile.diagnostic_bytes <= SELECTED_MAX_DIAGNOSTIC_BYTES
}

exercise_scoped_turns :: proc(storage: ^Generation_Storage, turns: int) -> bool {
	if !generation_valid(storage) do return false
	current := Turn_Scope {
		contributor_id = storage.records[0].contributor_id,
		contributor_generation = storage.generation,
		repository_generation = 7,
		observation_generation = 11,
		capability_generation = 13,
		callback_budget = SELECTED_DEFAULT_CALLBACKS_PER_TURN,
	}
	accepted, stale_rejected := 0, 0
	for _ in 0 ..< turns {
		if turn_scope_is_current(current, current) do accepted += 1
		stale := current
		stale.observation_generation += 1
		if !turn_scope_is_current(stale, current) do stale_rejected += 1
	}
	return accepted == turns && stale_rejected == turns
}

turn_scope_is_current :: proc(candidate, current: Turn_Scope) -> bool {
	return candidate.contributor_id != 0 && candidate.contributor_id == current.contributor_id &&
		candidate.contributor_generation == current.contributor_generation &&
		candidate.repository_generation == current.repository_generation &&
		candidate.observation_generation == current.observation_generation &&
		candidate.capability_generation == current.capability_generation &&
		candidate.callback_budget > 0 && candidate.callback_budget <= SELECTED_MAX_CALLBACKS_PER_TURN
}

run_invalid_shapes :: proc() -> bool {
	profile := Study_Profile {
		name = "invalid-shapes",
		contributors = 1,
		contributions_per_contributor = 1,
		identity_bytes = 16,
		label_bytes = 32,
		provenance_bytes = 64,
		observation_bytes = 1 * KIBIBYTE,
		result_bytes = 1 * KIBIBYTE,
		provider_value_bytes = 1 * KIBIBYTE,
		diagnostic_bytes = 256,
		turns = 1,
	}
	storage, ready := build_generation(profile, 1, context.allocator)
	if !ready do return false
	defer generation_close(&storage)
	record := storage.records[0]
	zero_contributor := record
	zero_contributor.contributor_id = 0
	stale_generation := record
	stale_generation.generation += 1
	invalid_role := record
	invalid_role.role = .Invalid
	invalid_range := record
	invalid_range.provenance_offset = u32(len(storage.text))
	overflow := profile
	overflow.contributors = SELECTED_MAX_CONTRIBUTORS + 1
	valid := !declaration_record_valid(zero_contributor, len(storage.text), storage.generation) &&
		!declaration_record_valid(stale_generation, len(storage.text), storage.generation) &&
		!declaration_record_valid(invalid_role, len(storage.text), storage.generation) &&
		!declaration_record_valid(invalid_range, len(storage.text), storage.generation) &&
		!profile_is_admitted(overflow)
	fmt.printf(
		"study=ksawery-extension profile=invalid-shapes valid=%v zero_contributor_rejected=true stale_generation_rejected=true invalid_role_rejected=true invalid_range_rejected=true overflow_rejected=true\n",
		valid,
	)
	return valid
}

run_allocation_fault :: proc() -> bool {
	profile := Study_Profile {
		name = "allocation-fault",
		contributors = 2,
		contributions_per_contributor = 4,
		identity_bytes = 24,
		label_bytes = 48,
		provenance_bytes = 128,
		observation_bytes = 4 * KIBIBYTE,
		result_bytes = 4 * KIBIBYTE,
		provider_value_bytes = 1 * KIBIBYTE,
		diagnostic_bytes = 256,
		turns = 1,
	}
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	backing := mem.tracking_allocator(&tracking)
	active, active_ready := build_generation(profile, 1, backing)
	if !active_ready {
		mem.tracking_allocator_destroy(&tracking)
		return false
	}
	active.lifecycle = .Active
	fault := Fault_Allocator {backing = backing, fail_after = 2}
	candidate, candidate_ready := build_generation(profile, 2, fault_allocator(&fault))
	if candidate.records != nil do generation_close(&candidate)
	prior_preserved := generation_valid(&active) && active.lifecycle == .Active
	generation_close(&active)
	cleanup_bytes := tracking.current_memory_allocated
	mem.tracking_allocator_destroy(&tracking)
	valid := !candidate_ready && prior_preserved && cleanup_bytes == 0
	fmt.printf(
		"study=ksawery-extension profile=allocation-fault valid=%v candidate_rejected=%v prior_generation_preserved=%v cleanup_bytes=%d\n",
		valid,
		!candidate_ready,
		prior_preserved,
		cleanup_bytes,
	)
	return valid
}

run_external_operation_profiles :: proc() -> bool {
	profiles := [?]External_Study_Profile {
		{
			name = "external-ordinary",
			operations = 16,
			arguments_per_plan = 4,
			argument_bytes = 24,
			absolute_path_bytes = 128,
			output_bytes = 64 * KIBIBYTE,
			diagnostic_bytes = 1 * KIBIBYTE,
			deadline_ms = 5_000,
			turns = 10_000,
		},
		{
			name = "external-demanding",
			operations = SELECTED_DEFAULT_EXTERNAL_OPERATIONS,
			arguments_per_plan = SELECTED_DEFAULT_EXTERNAL_ARGUMENTS,
			argument_bytes = 64,
			absolute_path_bytes = 1 * KIBIBYTE,
			output_bytes = SELECTED_DEFAULT_EXTERNAL_OUTPUT_BYTES,
			diagnostic_bytes = SELECTED_DEFAULT_DIAGNOSTIC_BYTES,
			deadline_ms = SELECTED_DEFAULT_EXTERNAL_DEADLINE_MS,
			turns = 50_000,
		},
		{
			name = "external-stress",
			operations = SELECTED_MAX_EXTERNAL_OPERATIONS,
			arguments_per_plan = SELECTED_MAX_EXTERNAL_ARGUMENTS,
			argument_bytes = 128,
			absolute_path_bytes = SELECTED_MAX_EXTERNAL_EXECUTABLE_BYTES,
			output_bytes = SELECTED_MAX_EXTERNAL_OUTPUT_BYTES,
			diagnostic_bytes = SELECTED_MAX_DIAGNOSTIC_BYTES,
			deadline_ms = SELECTED_MAX_EXTERNAL_DEADLINE_MS,
			turns = 100_000,
		},
	}
	passed := print_external_operation_policy()
	for profile in profiles {
		passed = run_external_operation_profile(profile) && passed
	}
	return passed
}

print_external_operation_policy :: proc() -> bool {
	valid := SELECTED_DEFAULT_EXTERNAL_OPERATIONS < SELECTED_MAX_EXTERNAL_OPERATIONS &&
		SELECTED_DEFAULT_EXTERNAL_ARGUMENTS < SELECTED_MAX_EXTERNAL_ARGUMENTS &&
		SELECTED_MAX_EXTERNAL_ARGUMENT_BYTES * SELECTED_MAX_EXTERNAL_ARGUMENTS *
			SELECTED_MAX_EXTERNAL_OPERATIONS > SELECTED_MAX_EXTERNAL_ARGUMENT_VECTOR_BYTES &&
		SELECTED_DEFAULT_EXTERNAL_OUTPUT_BYTES < SELECTED_MAX_EXTERNAL_OUTPUT_BYTES &&
		SELECTED_DEFAULT_EXTERNAL_DEADLINE_MS < SELECTED_MAX_EXTERNAL_DEADLINE_MS
	fmt.printf(
		"study=ksawery-extension profile=external-policy valid=%v default_operations=%d max_operations=%d default_arguments=%d max_arguments=%d max_argument_bytes=%d max_argument_vector_bytes=%d max_executable_bytes=%d default_output_bytes=%d max_output_bytes=%d default_deadline_ms=%d max_deadline_ms=%d retained_native_bytes=%d temporary_native_bytes=%d\n",
		valid,
		SELECTED_DEFAULT_EXTERNAL_OPERATIONS,
		SELECTED_MAX_EXTERNAL_OPERATIONS,
		SELECTED_DEFAULT_EXTERNAL_ARGUMENTS,
		SELECTED_MAX_EXTERNAL_ARGUMENTS,
		SELECTED_MAX_EXTERNAL_ARGUMENT_BYTES,
		SELECTED_MAX_EXTERNAL_ARGUMENT_VECTOR_BYTES,
		SELECTED_MAX_EXTERNAL_EXECUTABLE_BYTES,
		SELECTED_DEFAULT_EXTERNAL_OUTPUT_BYTES,
		SELECTED_MAX_EXTERNAL_OUTPUT_BYTES,
		SELECTED_DEFAULT_EXTERNAL_DEADLINE_MS,
		SELECTED_MAX_EXTERNAL_DEADLINE_MS,
		SELECTED_MAX_EXTERNAL_RETAINED_NATIVE_BYTES,
		SELECTED_MAX_EXTERNAL_TEMPORARY_NATIVE_BYTES,
	)
	return valid
}

run_external_operation_profile :: proc(profile: External_Study_Profile) -> bool {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	started := time.tick_now()
	active, active_ready := build_external_operation_storage(profile, allocator)
	if !active_ready {
		mem.tracking_allocator_destroy(&tracking)
		return false
	}
	turn_started := time.tick_now()
	turns_valid := exercise_external_operation_turns(&active, profile.turns)
	turn_elapsed_ns := time.duration_nanoseconds(time.tick_since(turn_started))
	candidate, candidate_ready := build_external_operation_storage(profile, allocator)
	replacement_valid := candidate_ready && external_operation_storage_valid(&active) &&
		external_operation_storage_valid(&candidate)
	retained_bytes := tracking.current_memory_allocated
	peak_bytes := tracking.peak_memory_allocated
	if candidate_ready do external_operation_storage_close(&candidate)
	external_operation_storage_close(&active)
	cleanup_bytes := tracking.current_memory_allocated
	elapsed_ns := time.duration_nanoseconds(time.tick_since(started))
	mem.tracking_allocator_destroy(&tracking)
	valid := replacement_valid && turns_valid &&
		retained_bytes <= SELECTED_MAX_EXTERNAL_RETAINED_NATIVE_BYTES &&
		peak_bytes <= SELECTED_MAX_EXTERNAL_RETAINED_NATIVE_BYTES +
			SELECTED_MAX_EXTERNAL_TEMPORARY_NATIVE_BYTES &&
		turn_elapsed_ns <= TURN_GATE_NS && elapsed_ns <= PROFILE_GATE_NS &&
		cleanup_bytes == 0
	fmt.printf(
		"study=ksawery-extension profile=%s valid=%v operations=%d executable_roles=2 effect_classes=3 observation_families=6 arguments_per_plan=%d argument_bytes=%d output_bytes=%d diagnostic_bytes=%d deadline_ms=%d turn_count=%d turn_elapsed_ns=%d retained_bytes=%d peak_bytes=%d cancellation=true verification=true replacement=true cleanup_bytes=%d elapsed_ns=%d\n",
		profile.name,
		valid,
		profile.operations,
		profile.arguments_per_plan,
		profile.argument_bytes,
		profile.output_bytes,
		profile.diagnostic_bytes,
		profile.deadline_ms,
		profile.turns,
		turn_elapsed_ns,
		retained_bytes,
		peak_bytes,
		cleanup_bytes,
		elapsed_ns,
	)
	return valid
}

external_study_profile_is_admitted :: proc(profile: External_Study_Profile) -> bool {
	argument_vector_bytes := profile.operations * profile.arguments_per_plan * profile.argument_bytes
	return profile.operations > 0 && profile.operations <= SELECTED_MAX_EXTERNAL_OPERATIONS &&
		profile.arguments_per_plan > 0 && profile.arguments_per_plan <= SELECTED_MAX_EXTERNAL_ARGUMENTS &&
		profile.argument_bytes > 0 && profile.argument_bytes <= SELECTED_MAX_EXTERNAL_ARGUMENT_BYTES &&
		argument_vector_bytes <= SELECTED_MAX_EXTERNAL_ARGUMENT_VECTOR_BYTES &&
		profile.absolute_path_bytes > 1 &&
		profile.absolute_path_bytes <= SELECTED_MAX_EXTERNAL_EXECUTABLE_BYTES &&
		profile.output_bytes > 0 && profile.output_bytes <= SELECTED_MAX_EXTERNAL_OUTPUT_BYTES &&
		profile.diagnostic_bytes > 0 && profile.diagnostic_bytes <= SELECTED_MAX_DIAGNOSTIC_BYTES &&
		profile.deadline_ms > 0 && profile.deadline_ms <= SELECTED_MAX_EXTERNAL_DEADLINE_MS &&
		profile.turns > 0
}

build_external_operation_storage :: proc(
	profile: External_Study_Profile,
	allocator: mem.Allocator,
) -> (storage: External_Operation_Storage, ok: bool) {
	storage.allocator = allocator
	if !external_study_profile_is_admitted(profile) do return storage, false
	argument_count := profile.operations * profile.arguments_per_plan
	text_bytes := 0
	for operation_index in 0 ..< profile.operations {
		executable_bytes := 3
		if operation_index % 2 == 1 do executable_bytes = profile.absolute_path_bytes
		text_bytes += 48 + 96 + executable_bytes +
			profile.arguments_per_plan * profile.argument_bytes
	}
	allocation_error: mem.Allocator_Error
	storage.records, allocation_error = make([]External_Operation_Record, profile.operations, allocator)
	if allocation_error == nil {
		storage.arguments, allocation_error = make([]External_Argument_Record, argument_count, allocator)
	}
	if allocation_error == nil do storage.text, allocation_error = make([]u8, text_bytes, allocator)
	if allocation_error == nil do storage.output, allocation_error = make([]u8, profile.output_bytes, allocator)
	if allocation_error == nil {
		storage.diagnostic, allocation_error = make([]u8, profile.diagnostic_bytes, allocator)
	}
	if allocation_error != nil {
		external_operation_storage_close(&storage)
		return storage, false
	}
	offset := 0
	argument_index := 0
	for operation_index in 0 ..< profile.operations {
		record := &storage.records[operation_index]
		record.id = u64(operation_index + 1)
		record.executable_kind = .Built_In_Git
		record.executable_bytes = 3
		if operation_index % 2 == 1 {
			record.executable_kind = .Absolute_Path
			record.executable_bytes = u16(profile.absolute_path_bytes)
		}
		record.effect = External_Effect_Class(operation_index % 3 + 1)
		switch record.effect {
		case .Read_Only:
			record.observations = {.Status, .History}
			record.verifier = .Status_Refresh
		case .Repository_Mutating:
			record.observations = {.Status, .Refs, .Sequence, .Conflict}
			record.verifier = .Ref_Refresh
		case .Externally_Mutating:
			record.observations = {.Process}
			record.verifier = .External_Predicate
		case .Invalid:
		}
		record.cancellable = operation_index % 2 == 0
		record.identity_offset = u32(offset)
		record.identity_bytes = 48
		external_study_fill(storage.text[offset:offset + 48], 'i')
		offset += 48
		record.purpose_offset = u32(offset)
		record.purpose_bytes = 96
		external_study_fill(storage.text[offset:offset + 96], 'p')
		offset += 96
		record.executable_offset = u32(offset)
		if record.executable_kind == .Built_In_Git {
			copy(storage.text[offset:offset + 3], transmute([]u8)(string("git")))
		} else {
			external_study_fill(
				storage.text[offset:offset + int(record.executable_bytes)], 'x',
			)
			storage.text[offset] = '/'
		}
		offset += int(record.executable_bytes)
		record.argument_start = u32(argument_index)
		record.argument_count = u16(profile.arguments_per_plan)
		for _ in 0 ..< profile.arguments_per_plan {
			argument := &storage.arguments[argument_index]
			argument.offset = u32(offset)
			argument.bytes = u16(profile.argument_bytes)
			external_study_fill(storage.text[offset:offset + profile.argument_bytes], 'a')
			offset += profile.argument_bytes
			argument_index += 1
		}
		record.output_limit = u64(profile.output_bytes)
		record.diagnostic_limit = u64(profile.diagnostic_bytes)
		record.deadline_ms = u32(profile.deadline_ms)
	}
	external_study_fill(storage.output, 'o')
	external_study_fill(storage.diagnostic, 'd')
	return storage, external_operation_storage_valid(&storage)
}

external_study_fill :: proc(buffer: []u8, value: u8) {
	for &entry in buffer do entry = value
}

external_operation_storage_valid :: proc(storage: ^External_Operation_Storage) -> bool {
	if storage == nil || len(storage.records) == 0 ||
	   len(storage.records) > SELECTED_MAX_EXTERNAL_OPERATIONS ||
	   len(storage.output) == 0 || len(storage.output) > SELECTED_MAX_EXTERNAL_OUTPUT_BYTES ||
	   len(storage.diagnostic) == 0 || len(storage.diagnostic) > SELECTED_MAX_DIAGNOSTIC_BYTES {
		return false
	}
	for record in storage.records {
		if !external_operation_record_valid(record, storage.arguments, storage.text) ||
		   u64(len(storage.output)) > record.output_limit ||
		   u64(len(storage.diagnostic)) > record.diagnostic_limit {
			return false
		}
	}
	return true
}

external_operation_record_valid :: proc(
	record: External_Operation_Record,
	arguments: []External_Argument_Record,
	text: []u8,
) -> bool {
	if record.id == 0 || record.executable_kind <= .Invalid ||
	   record.executable_kind > .Absolute_Path || record.effect <= .Invalid ||
	   record.effect > .Externally_Mutating || record.observations == {} ||
	   record.verifier > .External_Predicate ||
	   record.argument_count == 0 || int(record.argument_count) > SELECTED_MAX_EXTERNAL_ARGUMENTS ||
	   int(record.argument_start) + int(record.argument_count) > len(arguments) ||
	   record.output_limit == 0 || record.output_limit > SELECTED_MAX_EXTERNAL_OUTPUT_BYTES ||
	   record.diagnostic_limit == 0 || record.diagnostic_limit > SELECTED_MAX_DIAGNOSTIC_BYTES ||
	   record.deadline_ms == 0 || record.deadline_ms > SELECTED_MAX_EXTERNAL_DEADLINE_MS ||
	   record.identity_bytes == 0 || record.purpose_bytes == 0 || record.executable_bytes == 0 ||
	   int(record.identity_offset) + int(record.identity_bytes) > len(text) ||
	   int(record.purpose_offset) + int(record.purpose_bytes) > len(text) ||
	   int(record.executable_offset) + int(record.executable_bytes) > len(text) {
		return false
	}
	executable := text[int(record.executable_offset):int(record.executable_offset) + int(record.executable_bytes)]
	if record.executable_kind == .Built_In_Git {
		if string(executable) != "git" do return false
	} else if len(executable) > SELECTED_MAX_EXTERNAL_EXECUTABLE_BYTES || executable[0] != '/' {
		return false
	}
	if record.effect != .Read_Only && record.verifier == .None do return false
	argument_bytes := 0
	for argument_index in int(record.argument_start) ..<
	                        int(record.argument_start) + int(record.argument_count) {
		argument := arguments[argument_index]
		if argument.bytes == 0 || int(argument.bytes) > SELECTED_MAX_EXTERNAL_ARGUMENT_BYTES ||
		   int(argument.offset) + int(argument.bytes) > len(text) {
			return false
		}
		argument_bytes += int(argument.bytes)
	}
	return argument_bytes <= SELECTED_MAX_EXTERNAL_ARGUMENT_VECTOR_BYTES
}

exercise_external_operation_turns :: proc(
	storage: ^External_Operation_Storage,
	turns: int,
) -> bool {
	if !external_operation_storage_valid(storage) do return false
	for turn in 0 ..< turns {
		record := storage.records[turn % len(storage.records)]
		if external_operation_outcome(record, 0, false, false, true, true) != .Verified ||
		   external_operation_outcome(record, 1, false, false, true, true) != .Failed ||
		   external_operation_outcome(record, 0, false, true, false, false) != .Indeterminate {
			return false
		}
		if record.cancellable &&
		   (external_operation_outcome(record, 0, true, false, false, false) != .Cancelled ||
		    external_operation_outcome(record, 0, true, true, true, true) != .Indeterminate) {
			return false
		}
	}
	return true
}

external_operation_outcome :: proc(
	record: External_Operation_Record,
	exit_code: i32,
	cancellation_requested, effect_possible, refresh_completed, verifier_agreed: bool,
) -> External_Operation_Outcome {
	if cancellation_requested && record.cancellable {
		if !effect_possible do return .Cancelled
		return .Indeterminate
	}
	if exit_code != 0 do return .Failed
	if !refresh_completed || record.verifier == .None do return .Indeterminate
	if !verifier_agreed do return .Failed
	return .Verified
}

run_external_operation_invalid_shapes :: proc() -> bool {
	profile := External_Study_Profile {
		name = "external-invalid-shapes",
		operations = 4,
		arguments_per_plan = 2,
		argument_bytes = 16,
		absolute_path_bytes = 64,
		output_bytes = 4 * KIBIBYTE,
		diagnostic_bytes = 256,
		deadline_ms = 1_000,
		turns = 1,
	}
	storage, ready := build_external_operation_storage(profile, context.allocator)
	if !ready do return false
	defer external_operation_storage_close(&storage)
	record := storage.records[1]
	invalid_kind := record
	invalid_kind.executable_kind = .Invalid
	relative_path := record
	storage.text[int(relative_path.executable_offset)] = 'x'
	relative_rejected := !external_operation_record_valid(relative_path, storage.arguments, storage.text)
	storage.text[int(relative_path.executable_offset)] = '/'
	invalid_effect := record
	invalid_effect.effect = .Invalid
	missing_observation := record
	missing_observation.observations = {}
	missing_verifier := record
	missing_verifier.verifier = .None
	invalid_deadline := record
	invalid_deadline.deadline_ms = 0
	oversized_output := record
	oversized_output.output_limit = SELECTED_MAX_EXTERNAL_OUTPUT_BYTES + 1
	invalid_arguments := record
	invalid_arguments.argument_count = SELECTED_MAX_EXTERNAL_ARGUMENTS + 1
	valid := !external_operation_record_valid(invalid_kind, storage.arguments, storage.text) &&
		relative_rejected &&
		!external_operation_record_valid(invalid_effect, storage.arguments, storage.text) &&
		!external_operation_record_valid(missing_observation, storage.arguments, storage.text) &&
		!external_operation_record_valid(missing_verifier, storage.arguments, storage.text) &&
		!external_operation_record_valid(invalid_deadline, storage.arguments, storage.text) &&
		!external_operation_record_valid(oversized_output, storage.arguments, storage.text) &&
		!external_operation_record_valid(invalid_arguments, storage.arguments, storage.text)
	fmt.printf(
		"study=ksawery-extension profile=external-invalid-shapes valid=%v executable_kind_rejected=true relative_path_rejected=%v effect_rejected=true observation_rejected=true verifier_rejected=true deadline_rejected=true output_rejected=true arguments_rejected=true\n",
		valid,
		relative_rejected,
	)
	return valid
}

run_external_operation_allocation_fault :: proc() -> bool {
	profile := External_Study_Profile {
		name = "external-allocation-fault",
		operations = 8,
		arguments_per_plan = 4,
		argument_bytes = 24,
		absolute_path_bytes = 128,
		output_bytes = 4 * KIBIBYTE,
		diagnostic_bytes = 256,
		deadline_ms = 1_000,
		turns = 1,
	}
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	backing := mem.tracking_allocator(&tracking)
	active, active_ready := build_external_operation_storage(profile, backing)
	if !active_ready {
		mem.tracking_allocator_destroy(&tracking)
		return false
	}
	fault := Fault_Allocator {backing = backing, fail_after = 3}
	candidate, candidate_ready := build_external_operation_storage(profile, fault_allocator(&fault))
	if candidate.records != nil do external_operation_storage_close(&candidate)
	prior_preserved := external_operation_storage_valid(&active)
	external_operation_storage_close(&active)
	cleanup_bytes := tracking.current_memory_allocated
	mem.tracking_allocator_destroy(&tracking)
	valid := !candidate_ready && prior_preserved && cleanup_bytes == 0
	fmt.printf(
		"study=ksawery-extension profile=external-allocation-fault valid=%v candidate_rejected=%v prior_generation_preserved=%v cleanup_bytes=%d\n",
		valid,
		!candidate_ready,
		prior_preserved,
		cleanup_bytes,
	)
	return valid
}

run_workflow_profiles :: proc() -> bool {
	profiles := [?]Workflow_Study_Profile {
		{
			name = "workflow-ordinary",
			contributors = 2,
			declaration_bytes = 128 * KIBIBYTE,
			command_family_bytes = 128 * KIBIBYTE,
			process_record_bytes = 128 * KIBIBYTE,
			conflict_copy_bytes = 128 * KIBIBYTE,
			raw_command_bytes = 1 * KIBIBYTE,
			output_bytes = 64 * KIBIBYTE,
			diagnostic_bytes = 1 * KIBIBYTE,
			turns = 10_000,
		},
		{
			name = "workflow-demanding",
			contributors = SELECTED_DEFAULT_CONTRIBUTORS,
			declaration_bytes = 1 * MEBIBYTE,
			command_family_bytes = 1 * MEBIBYTE,
			process_record_bytes = 1 * MEBIBYTE,
			conflict_copy_bytes = 1 * MEBIBYTE,
			raw_command_bytes = 2 * KIBIBYTE,
			output_bytes = 1 * MEBIBYTE,
			diagnostic_bytes = 4 * KIBIBYTE,
			turns = 50_000,
		},
		{
			name = "workflow-stress",
			contributors = SELECTED_MAX_CONTRIBUTORS,
			declaration_bytes = 6 * MEBIBYTE,
			command_family_bytes = 6 * MEBIBYTE,
			process_record_bytes = 6 * MEBIBYTE,
			conflict_copy_bytes = 6 * MEBIBYTE,
			raw_command_bytes = SELECTED_MAX_RAW_COMMAND_BYTES,
			output_bytes = 6 * MEBIBYTE,
			diagnostic_bytes = SELECTED_MAX_WORKFLOW_DIAGNOSTIC_BYTES,
			turns = 100_000,
		},
	}
	passed := print_workflow_policy()
	for profile in profiles {
		passed = run_workflow_profile(profile) && passed
	}
	return passed
}

print_workflow_policy :: proc() -> bool {
	valid := SELECTED_MAX_WORKFLOW_RECORDS == SELECTED_MAX_CONTRIBUTORS * 9 &&
		SELECTED_MAX_WORKFLOW_ITEMS == 256 &&
		SELECTED_MAX_RAW_COMMAND_BYTES == 4 * KIBIBYTE &&
		SELECTED_MAX_PROCESS_RECORD_BYTES == 8 * MEBIBYTE &&
		SELECTED_MAX_CONFLICT_COPY_BYTES == 8 * MEBIBYTE
	fmt.printf(
		"study=ksawery-extension profile=workflow-policy valid=%v record_kinds=9 observation_families=6 max_records=%d max_items=%d max_command_family_copy_bytes=%d max_process_record_bytes=%d max_conflict_copy_bytes=%d max_raw_command_bytes=%d max_output_bytes=%d max_diagnostic_bytes=%d retained_native_bytes=%d temporary_native_bytes=%d\n",
		valid,
		SELECTED_MAX_WORKFLOW_RECORDS,
		SELECTED_MAX_WORKFLOW_ITEMS,
		SELECTED_MAX_COMMAND_FAMILY_COPY_BYTES,
		SELECTED_MAX_PROCESS_RECORD_BYTES,
		SELECTED_MAX_CONFLICT_COPY_BYTES,
		SELECTED_MAX_RAW_COMMAND_BYTES,
		SELECTED_MAX_WORKFLOW_OUTPUT_BYTES,
		SELECTED_MAX_WORKFLOW_DIAGNOSTIC_BYTES,
		SELECTED_MAX_WORKFLOW_RETAINED_NATIVE_BYTES,
		SELECTED_MAX_WORKFLOW_TEMPORARY_NATIVE_BYTES,
	)
	return valid
}

run_workflow_profile :: proc(profile: Workflow_Study_Profile) -> bool {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	started := time.tick_now()
	active, active_ready := build_workflow_storage(profile, 1, allocator)
	if !active_ready {
		mem.tracking_allocator_destroy(&tracking)
		return false
	}
	active.lifecycle = .Active
	turn_started := time.tick_now()
	coverage, turns_valid := exercise_workflow_turns(&active, profile.turns)
	turn_elapsed_ns := time.duration_nanoseconds(time.tick_since(turn_started))
	candidate, candidate_ready := build_workflow_storage(profile, 2, allocator)
	if candidate_ready do candidate.lifecycle = .Reloading
	reload_valid := candidate_ready && workflow_storage_valid(&active) &&
		workflow_storage_valid(&candidate)
	if reload_valid {
		candidate.lifecycle = .Active
		active.lifecycle = .Retiring
		workflow_storage_close(&active)
	}
	retained_bytes := tracking.current_memory_allocated
	peak_bytes := tracking.peak_memory_allocated
	fallback_valid := false
	second_reload_valid := false
	if candidate_ready {
		candidate.lifecycle = .Disabled
		candidate.provider_enabled = false
		candidate.fallback_active = true
		fallback_valid = workflow_storage_valid(&candidate)
		candidate.lifecycle = .Reloading
		candidate.provider_enabled = true
		candidate.fallback_active = false
		second_reload_valid = workflow_storage_valid(&candidate)
		candidate.lifecycle = .Active
	}
	raw_cleared := candidate_ready && workflow_clear_raw_command(&candidate)
	if candidate_ready do workflow_storage_close(&candidate)
	if active.records != nil do workflow_storage_close(&active)
	cleanup_bytes := tracking.current_memory_allocated
	elapsed_ns := time.duration_nanoseconds(time.tick_since(started))
	mem.tracking_allocator_destroy(&tracking)
	valid := reload_valid && fallback_valid && second_reload_valid && raw_cleared && turns_valid &&
		retained_bytes <= SELECTED_MAX_WORKFLOW_RETAINED_NATIVE_BYTES &&
		peak_bytes <= SELECTED_MAX_WORKFLOW_RETAINED_NATIVE_BYTES +
			SELECTED_MAX_WORKFLOW_TEMPORARY_NATIVE_BYTES &&
		turn_elapsed_ns <= TURN_GATE_NS && elapsed_ns <= PROFILE_GATE_NS && cleanup_bytes == 0
	fmt.printf(
		"study=ksawery-extension profile=%s valid=%v contributors=%d records=%d sections=%d annotations=%d commands=%d command_families=%d external_operations=%d raw_commands=%d conflict_assistance=%d process_records=%d refresh_records=%d refreshes=%d cancellations=%d timeouts=%d truncations=%d reloads=2 fallback=true retained_bytes=%d peak_bytes=%d raw_cleared=%v cleanup_bytes=%d turn_count=%d turn_elapsed_ns=%d elapsed_ns=%d\n",
		profile.name,
		valid,
		profile.contributors,
		profile.contributors * 9,
		coverage.kinds[0],
		coverage.kinds[1],
		coverage.kinds[2],
		coverage.kinds[3],
		coverage.kinds[4],
		coverage.kinds[5],
		coverage.kinds[6],
		coverage.kinds[7],
		coverage.kinds[8],
		coverage.refreshes,
		coverage.cancellations,
		coverage.timeouts,
		coverage.truncations,
		retained_bytes,
		peak_bytes,
		raw_cleared,
		cleanup_bytes,
		profile.turns,
		turn_elapsed_ns,
		elapsed_ns,
	)
	return valid
}

workflow_profile_is_admitted :: proc(profile: Workflow_Study_Profile) -> bool {
	record_bytes := profile.contributors * 9 * size_of(Workflow_Record)
	retained_bytes := record_bytes + profile.declaration_bytes + profile.command_family_bytes +
		profile.process_record_bytes + profile.conflict_copy_bytes + profile.raw_command_bytes +
		profile.output_bytes + profile.diagnostic_bytes
	return profile.contributors > 0 && profile.contributors <= SELECTED_MAX_CONTRIBUTORS &&
		profile.contributors * 9 <= SELECTED_MAX_WORKFLOW_RECORDS &&
		profile.declaration_bytes > 0 && profile.declaration_bytes <= SELECTED_MAX_DECLARATION_BYTES &&
		profile.command_family_bytes > 0 &&
		profile.command_family_bytes <= SELECTED_MAX_COMMAND_FAMILY_COPY_BYTES &&
		profile.process_record_bytes > 0 &&
		profile.process_record_bytes <= SELECTED_MAX_PROCESS_RECORD_BYTES &&
		profile.conflict_copy_bytes > 0 &&
		profile.conflict_copy_bytes <= SELECTED_MAX_CONFLICT_COPY_BYTES &&
		profile.raw_command_bytes > 0 && profile.raw_command_bytes <= SELECTED_MAX_RAW_COMMAND_BYTES &&
		profile.output_bytes > 0 && profile.output_bytes <= SELECTED_MAX_WORKFLOW_OUTPUT_BYTES &&
		profile.diagnostic_bytes > 0 &&
		profile.diagnostic_bytes <= SELECTED_MAX_WORKFLOW_DIAGNOSTIC_BYTES &&
		retained_bytes <= SELECTED_MAX_WORKFLOW_RETAINED_NATIVE_BYTES && profile.turns > 0
}

build_workflow_storage :: proc(
	profile: Workflow_Study_Profile,
	generation: u64,
	allocator: mem.Allocator,
) -> (storage: Workflow_Storage, ok: bool) {
	storage.allocator = allocator
	storage.generation = generation
	storage.lifecycle = .Candidate
	storage.provider_enabled = true
	if generation == 0 || !workflow_profile_is_admitted(profile) do return storage, false
	record_count := profile.contributors * 9
	allocation_error: mem.Allocator_Error
	storage.records, allocation_error = make([]Workflow_Record, record_count, allocator)
	if allocation_error == nil {
		storage.declarations, allocation_error = make([]u8, profile.declaration_bytes, allocator)
	}
	if allocation_error == nil {
		storage.command_family, allocation_error = make([]u8, profile.command_family_bytes, allocator)
	}
	if allocation_error == nil {
		storage.process_records, allocation_error = make([]u8, profile.process_record_bytes, allocator)
	}
	if allocation_error == nil {
		storage.conflict_copy, allocation_error = make([]u8, profile.conflict_copy_bytes, allocator)
	}
	if allocation_error == nil {
		storage.raw_command, allocation_error = make([]u8, profile.raw_command_bytes, allocator)
	}
	if allocation_error == nil do storage.output, allocation_error = make([]u8, profile.output_bytes, allocator)
	if allocation_error == nil {
		storage.diagnostic, allocation_error = make([]u8, profile.diagnostic_bytes, allocator)
	}
	if allocation_error != nil {
		workflow_storage_close(&storage)
		return storage, false
	}
	all_refreshes: External_Observation_Families = {
		.Status,
		.History,
		.Refs,
		.Sequence,
		.Conflict,
		.Process,
	}
	for record_index in 0 ..< record_count {
		kind := Workflow_Record_Kind(record_index % 9 + 1)
		storage.records[record_index] = Workflow_Record {
			contributor_id = u64(record_index / 9 + 1),
			generation = generation,
			kind = kind,
			bounded_items = workflow_items_for_kind(kind),
			refresh = all_refreshes,
		}
	}
	external_study_fill(storage.declarations, 'd')
	external_study_fill(storage.command_family, 'f')
	external_study_fill(storage.process_records, 'p')
	external_study_fill(storage.conflict_copy, 'c')
	external_study_fill(storage.raw_command, 'r')
	external_study_fill(storage.output, 'o')
	external_study_fill(storage.diagnostic, 'x')
	return storage, workflow_storage_valid(&storage)
}

workflow_items_for_kind :: proc(kind: Workflow_Record_Kind) -> u16 {
	switch kind {
	case .Status_Section, .Annotation:
		return 64
	case .Command:
		return 1
	case .Command_Family:
		return 256
	case .External_Operation, .Raw_Command:
		return 64
	case .Conflict_Assistance:
		return 4
	case .Process_Record:
		return 32
	case .Refresh:
		return 6
	case .Invalid:
		return 0
	}
	return 0
}

workflow_storage_valid :: proc(storage: ^Workflow_Storage) -> bool {
	if storage == nil || storage.generation == 0 || storage.lifecycle == .Invalid ||
	   storage.lifecycle == .Closed || storage.provider_enabled == storage.fallback_active ||
	   len(storage.records) == 0 || len(storage.records) > SELECTED_MAX_WORKFLOW_RECORDS ||
	   len(storage.declarations) == 0 || len(storage.declarations) > SELECTED_MAX_DECLARATION_BYTES ||
	   len(storage.command_family) == 0 ||
	   len(storage.command_family) > SELECTED_MAX_COMMAND_FAMILY_COPY_BYTES ||
	   len(storage.process_records) == 0 ||
	   len(storage.process_records) > SELECTED_MAX_PROCESS_RECORD_BYTES ||
	   len(storage.conflict_copy) == 0 || len(storage.conflict_copy) > SELECTED_MAX_CONFLICT_COPY_BYTES ||
	   len(storage.raw_command) == 0 || len(storage.raw_command) > SELECTED_MAX_RAW_COMMAND_BYTES ||
	   len(storage.output) == 0 || len(storage.output) > SELECTED_MAX_WORKFLOW_OUTPUT_BYTES ||
	   len(storage.diagnostic) == 0 ||
	   len(storage.diagnostic) > SELECTED_MAX_WORKFLOW_DIAGNOSTIC_BYTES {
		return false
	}
	for record in storage.records {
		if !workflow_record_valid(record, storage.generation) do return false
	}
	return true
}

workflow_record_valid :: proc(record: Workflow_Record, generation: u64) -> bool {
	all_refreshes: External_Observation_Families = {
		.Status,
		.History,
		.Refs,
		.Sequence,
		.Conflict,
		.Process,
	}
	return record.contributor_id != 0 && record.generation == generation &&
		record.kind > .Invalid && record.kind <= .Refresh && record.bounded_items > 0 &&
		int(record.bounded_items) <= SELECTED_MAX_WORKFLOW_ITEMS && record.refresh == all_refreshes
}

exercise_workflow_turns :: proc(
	storage: ^Workflow_Storage,
	turns: int,
) -> (coverage: Workflow_Coverage, ok: bool) {
	if !workflow_storage_valid(storage) || turns < 9 do return coverage, false
	for turn in 0 ..< turns {
		record := storage.records[turn % len(storage.records)]
		if !workflow_record_valid(record, storage.generation) do return coverage, false
		kind_index := int(record.kind) - 1
		coverage.kinds[kind_index] += 1
		outcome := Workflow_Outcome(turn % 5 + 1)
		coverage.outcomes[int(outcome) - 1] += 1
		if record.kind == .Refresh do coverage.refreshes += 1
		switch outcome {
		case .Cancelled:
			coverage.cancellations += 1
		case .Timed_Out:
			coverage.timeouts += 1
		case .Truncated:
			coverage.truncations += 1
		case .Completed, .Failed, .Invalid:
		}
	}
	for count in coverage.kinds {
		if count == 0 do return coverage, false
	}
	for count in coverage.outcomes {
		if count == 0 do return coverage, false
	}
	return coverage, coverage.refreshes > 0 && coverage.cancellations > 0 &&
		coverage.timeouts > 0 && coverage.truncations > 0
}

workflow_clear_raw_command :: proc(storage: ^Workflow_Storage) -> bool {
	if storage == nil || storage.raw_command == nil do return false
	for &value in storage.raw_command do value = 0
	for value in storage.raw_command {
		if value != 0 do return false
	}
	return true
}

run_workflow_invalid_shapes :: proc() -> bool {
	profile := Workflow_Study_Profile {
		name = "workflow-invalid-shapes",
		contributors = 1,
		declaration_bytes = 4 * KIBIBYTE,
		command_family_bytes = 4 * KIBIBYTE,
		process_record_bytes = 4 * KIBIBYTE,
		conflict_copy_bytes = 4 * KIBIBYTE,
		raw_command_bytes = 256,
		output_bytes = 4 * KIBIBYTE,
		diagnostic_bytes = 256,
		turns = 9,
	}
	storage, ready := build_workflow_storage(profile, 1, context.allocator)
	if !ready do return false
	defer workflow_storage_close(&storage)
	record := storage.records[0]
	invalid_kind := record
	invalid_kind.kind = .Invalid
	stale_generation := record
	stale_generation.generation += 1
	missing_items := record
	missing_items.bounded_items = 0
	missing_refresh := record
	missing_refresh.refresh = {}
	overflow := profile
	overflow.raw_command_bytes = SELECTED_MAX_RAW_COMMAND_BYTES + 1
	valid := !workflow_record_valid(invalid_kind, storage.generation) &&
		!workflow_record_valid(stale_generation, storage.generation) &&
		!workflow_record_valid(missing_items, storage.generation) &&
		!workflow_record_valid(missing_refresh, storage.generation) &&
		!workflow_profile_is_admitted(overflow)
	fmt.printf(
		"study=ksawery-extension profile=workflow-invalid-shapes valid=%v invalid_kind_rejected=true stale_generation_rejected=true missing_items_rejected=true missing_refresh_rejected=true raw_overflow_rejected=true\n",
		valid,
	)
	return valid
}

run_workflow_allocation_fault :: proc() -> bool {
	profile := Workflow_Study_Profile {
		name = "workflow-allocation-fault",
		contributors = 2,
		declaration_bytes = 4 * KIBIBYTE,
		command_family_bytes = 4 * KIBIBYTE,
		process_record_bytes = 4 * KIBIBYTE,
		conflict_copy_bytes = 4 * KIBIBYTE,
		raw_command_bytes = 256,
		output_bytes = 4 * KIBIBYTE,
		diagnostic_bytes = 256,
		turns = 18,
	}
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	backing := mem.tracking_allocator(&tracking)
	active, active_ready := build_workflow_storage(profile, 1, backing)
	if !active_ready {
		mem.tracking_allocator_destroy(&tracking)
		return false
	}
	active.lifecycle = .Active
	fault := Fault_Allocator {backing = backing, fail_after = 3}
	candidate, candidate_ready := build_workflow_storage(profile, 2, fault_allocator(&fault))
	if candidate.records != nil do workflow_storage_close(&candidate)
	prior_preserved := workflow_storage_valid(&active)
	workflow_storage_close(&active)
	cleanup_bytes := tracking.current_memory_allocated
	mem.tracking_allocator_destroy(&tracking)
	valid := !candidate_ready && prior_preserved && cleanup_bytes == 0
	fmt.printf(
		"study=ksawery-extension profile=workflow-allocation-fault valid=%v candidate_rejected=%v prior_generation_preserved=%v cleanup_bytes=%d\n",
		valid,
		!candidate_ready,
		prior_preserved,
		cleanup_bytes,
	)
	return valid
}

workflow_storage_close :: proc(storage: ^Workflow_Storage) {
	if storage == nil do return
	if storage.records != nil do delete(storage.records, storage.allocator)
	if storage.declarations != nil do delete(storage.declarations, storage.allocator)
	if storage.command_family != nil do delete(storage.command_family, storage.allocator)
	if storage.process_records != nil do delete(storage.process_records, storage.allocator)
	if storage.conflict_copy != nil do delete(storage.conflict_copy, storage.allocator)
	if storage.raw_command != nil do delete(storage.raw_command, storage.allocator)
	if storage.output != nil do delete(storage.output, storage.allocator)
	if storage.diagnostic != nil do delete(storage.diagnostic, storage.allocator)
	storage^ = {}
}

external_operation_storage_close :: proc(storage: ^External_Operation_Storage) {
	if storage == nil do return
	if storage.records != nil do delete(storage.records, storage.allocator)
	if storage.arguments != nil do delete(storage.arguments, storage.allocator)
	if storage.text != nil do delete(storage.text, storage.allocator)
	if storage.output != nil do delete(storage.output, storage.allocator)
	if storage.diagnostic != nil do delete(storage.diagnostic, storage.allocator)
	storage^ = {}
}

generation_close :: proc(storage: ^Generation_Storage) {
	if storage == nil do return
	if storage.records != nil do delete(storage.records, storage.allocator)
	if storage.text != nil do delete(storage.text, storage.allocator)
	if storage.observation != nil do delete(storage.observation, storage.allocator)
	if storage.result != nil do delete(storage.result, storage.allocator)
	if storage.provider_value != nil do delete(storage.provider_value, storage.allocator)
	if storage.diagnostic != nil do delete(storage.diagnostic, storage.allocator)
	storage^ = {}
}

fault_allocator :: proc(state: ^Fault_Allocator) -> runtime.Allocator {
	return {procedure = fault_allocator_proc, data = state}
}

fault_allocator_proc :: proc(
	allocator_data: rawptr,
	mode: runtime.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	location: runtime.Source_Code_Location,
) -> ([]byte, runtime.Allocator_Error) {
	allocator := cast(^Fault_Allocator)allocator_data
	if mode == .Alloc || mode == .Alloc_Non_Zeroed || mode == .Resize || mode == .Resize_Non_Zeroed {
		if allocator.successful_allocations >= allocator.fail_after do return nil, .Out_Of_Memory
		allocator.successful_allocations += 1
	}
	return allocator.backing.procedure(
		allocator.backing.data,
		mode,
		size,
		alignment,
		old_memory,
		old_size,
		location,
	)
}
