// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import ksawery "../../src/ksawery"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:time"
import "base:runtime"

KIBIBYTE :: 1_024
ORDINARY_CONFLICTS :: 32
WIDE_CONFLICTS :: 1_024
STRESS_CONFLICTS :: 4_096
SELECTED_DEFAULT_CONFLICTS :: 1_024
SELECTED_MAX_CONFLICTS :: 16_384
SELECTED_DEFAULT_PATH_BYTES :: 256 * KIBIBYTE
SELECTED_MAX_PATH_BYTES :: 4 * 1_024 * KIBIBYTE
SELECTED_DEFAULT_METADATA_BYTES :: 64 * KIBIBYTE
SELECTED_MAX_METADATA_BYTES :: 512 * KIBIBYTE
SELECTED_DEFAULT_TEMPORARY_BYTES :: 2 * 1_024 * KIBIBYTE
SELECTED_MAX_TEMPORARY_BYTES :: 16 * 1_024 * KIBIBYTE
STUDY_LATENCY_LIMIT_NS :: i64(3_000_000_000)
STUDY_MEMORY_LIMIT_BYTES :: i64(8 * 1_024 * 1_024)
WORKFLOW_STATE_SEQUENCES :: 128

WORKFLOW_CURRENT :: "0123456789012345678901234567890123456789"
WORKFLOW_TARGET :: "1234567890123456789012345678901234567890"

Sequence_Profile :: enum u8 {
	Merge,
	Rebase,
	Cherry_Pick,
	Revert,
	Bisect,
	Apply_Patches,
	External,
	Unknown,
}

Sequence_Measurement :: struct {
	conflicts:     int,
	path_bytes:    int,
	output_bytes:  int,
	maximum_path:  int,
	elapsed_ns:    i64,
	peak_bytes:    i64,
	cleanup_bytes: i64,
}

Workflow_State_Measurement :: struct {
	sequences:             int,
	fingerprint_checks:    int,
	step_checks:           int,
	conflict_checks:       int,
	reentry_checks:        int,
	cancellation_states:   int,
	timeout_states:        int,
	refresh_states:        int,
	verification_states:   int,
	truncation_states:     int,
	peak_bytes:            i64,
	elapsed_ns:            i64,
	cleanup_bytes:         i64,
}

main :: proc() {
	ordinary, ordinary_ok := measure_profile(.Merge, ORDINARY_CONFLICTS)
	wide, wide_ok := measure_profile(.Rebase, WIDE_CONFLICTS)
	stress, stress_ok := measure_profile(.Cherry_Pick, STRESS_CONFLICTS)
	profiles_ok := measure_operation_profiles()
	workflow, workflow_ok := measure_workflow_states()

	malformed := transmute([]u8)(string("u UU incomplete\x00"))
	_, malformed_ok := sequence_shape(malformed)
	truncated, truncated_error := conflict_fixture(4, context.allocator)
	truncated_ok := false
	if truncated_error == nil {
		truncated_view := truncated[:len(truncated) - 1]
		_, truncated_ok = sequence_shape(truncated_view)
	}
	if truncated != nil do delete(truncated)

	valid := ordinary_ok && wide_ok && stress_ok && profiles_ok && workflow_ok &&
		ordinary.conflicts == ORDINARY_CONFLICTS &&
		wide.conflicts == WIDE_CONFLICTS &&
		stress.conflicts == STRESS_CONFLICTS &&
		wide.conflicts == SELECTED_DEFAULT_CONFLICTS &&
		stress.conflicts < SELECTED_MAX_CONFLICTS &&
		wide.path_bytes <= SELECTED_DEFAULT_PATH_BYTES &&
		stress.path_bytes <= SELECTED_MAX_PATH_BYTES &&
		stress.output_bytes <= 4 * 1_024 * KIBIBYTE &&
		ordinary.elapsed_ns <= STUDY_LATENCY_LIMIT_NS &&
		wide.elapsed_ns <= STUDY_LATENCY_LIMIT_NS &&
		stress.elapsed_ns <= STUDY_LATENCY_LIMIT_NS &&
		ordinary.peak_bytes <= STUDY_MEMORY_LIMIT_BYTES &&
		wide.peak_bytes <= STUDY_MEMORY_LIMIT_BYTES &&
		stress.peak_bytes <= STUDY_MEMORY_LIMIT_BYTES &&
		ordinary.cleanup_bytes == 0 && wide.cleanup_bytes == 0 &&
		stress.cleanup_bytes == 0 && !malformed_ok && !truncated_ok &&
		workflow.sequences == WORKFLOW_STATE_SEQUENCES &&
		workflow.fingerprint_checks == WORKFLOW_STATE_SEQUENCES &&
		workflow.step_checks > 0 && workflow.conflict_checks > 0 &&
		workflow.reentry_checks == WORKFLOW_STATE_SEQUENCES &&
		workflow.cancellation_states > 0 && workflow.timeout_states > 0 &&
		workflow.refresh_states > 0 && workflow.verification_states == workflow.refresh_states &&
		workflow.truncation_states > 0 && workflow.peak_bytes <= STUDY_MEMORY_LIMIT_BYTES &&
		workflow.elapsed_ns <= STUDY_LATENCY_LIMIT_NS && workflow.cleanup_bytes == 0

	fmt.printf(
		"study=ksawery-sequences valid=%v profiles=%d ordinary_conflicts=%d ordinary_path_bytes=%d ordinary_output_bytes=%d ordinary_maximum_path=%d ordinary_elapsed_ns=%d ordinary_peak_bytes=%d ordinary_cleanup_bytes=%d wide_conflicts=%d wide_path_bytes=%d wide_output_bytes=%d wide_maximum_path=%d wide_elapsed_ns=%d wide_peak_bytes=%d wide_cleanup_bytes=%d stress_conflicts=%d stress_path_bytes=%d stress_output_bytes=%d stress_maximum_path=%d stress_elapsed_ns=%d stress_peak_bytes=%d stress_cleanup_bytes=%d malformed_rejected=%v truncated_rejected=%v selected_default_conflicts=%d selected_max_conflicts=%d selected_default_path_bytes=%d selected_max_path_bytes=%d selected_default_metadata_bytes=%d selected_max_metadata_bytes=%d selected_default_temporary_bytes=%d selected_max_temporary_bytes=%d latency_limit_ns=%d memory_limit_bytes=%d capture=unbounded-study-only\n",
		valid,
		int(Sequence_Profile.Unknown) + 1,
		ordinary.conflicts, ordinary.path_bytes, ordinary.output_bytes,
		ordinary.maximum_path, ordinary.elapsed_ns, ordinary.peak_bytes,
		ordinary.cleanup_bytes,
		wide.conflicts, wide.path_bytes, wide.output_bytes, wide.maximum_path,
		wide.elapsed_ns, wide.peak_bytes, wide.cleanup_bytes,
		stress.conflicts, stress.path_bytes, stress.output_bytes,
		stress.maximum_path, stress.elapsed_ns, stress.peak_bytes,
		stress.cleanup_bytes,
		!malformed_ok, !truncated_ok,
		SELECTED_DEFAULT_CONFLICTS, SELECTED_MAX_CONFLICTS,
		SELECTED_DEFAULT_PATH_BYTES, SELECTED_MAX_PATH_BYTES,
		SELECTED_DEFAULT_METADATA_BYTES, SELECTED_MAX_METADATA_BYTES,
		SELECTED_DEFAULT_TEMPORARY_BYTES, SELECTED_MAX_TEMPORARY_BYTES,
		STUDY_LATENCY_LIMIT_NS, STUDY_MEMORY_LIMIT_BYTES,
	)
	fmt.printf(
		"study=ksawery-sequences profile=workflow-state valid=%v sequences=%d fingerprint_checks=%d step_checks=%d conflict_checks=%d reentry_checks=%d cancellation_states=%d timeout_states=%d refresh_states=%d verification_states=%d truncation_states=%d peak_bytes=%d elapsed_ns=%d cleanup_bytes=%d\n",
		workflow_ok,
		workflow.sequences,
		workflow.fingerprint_checks,
		workflow.step_checks,
		workflow.conflict_checks,
		workflow.reentry_checks,
		workflow.cancellation_states,
		workflow.timeout_states,
		workflow.refresh_states,
		workflow.verification_states,
		workflow.truncation_states,
		workflow.peak_bytes,
		workflow.elapsed_ns,
		workflow.cleanup_bytes,
	)
	if !valid do os.exit(1)
}

@(private)
measure_workflow_states :: proc() -> (Workflow_State_Measurement, bool) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	started := time.tick_now()
	measurement: Workflow_State_Measurement
	valid := true
	kinds := [?]ksawery.Sequence_Kind {
		.Merge, .Rebase, .Cherry_Pick, .Revert, .Bisect, .Apply_Patches,
	}
	operations := [?]ksawery.Repository_Operation_Kind {
		.Merge, .Rebase, .Cherry_Pick, .Revert, .Bisect, .Resolve_Conflict,
	}
	markers := [?]u16 {1 << 0, 1 << 1, 1 << 3, 1 << 4, 1 << 5, 1 << 6}
	current, current_ok := workflow_revision(WORKFLOW_CURRENT)
	target, target_ok := workflow_revision(WORKFLOW_TARGET)
	valid = current_ok && target_ok
	for sequence_index in 0 ..< WORKFLOW_STATE_SEQUENCES {
		kind_index := sequence_index % len(kinds)
		source := ksawery.Sequence_Source {
			kind = kinds[kind_index],
			origin = sequence_index % 2 == 0 ? .Associated : .External,
			marker_mask = markers[kind_index],
			current = current,
			target = target,
			metadata_bytes = 64,
			supported = true,
		}
		if source.kind == .Rebase {
			source.step = {position = u32(sequence_index % 7 + 1), total = 7}
		}
		conflict_count := sequence_index % 5
		fixture, fixture_error := conflict_fixture(conflict_count, allocator)
		if fixture_error != nil {
			valid = false
			continue
		}
		limits := ksawery.DEFAULT_SEQUENCE_LIMITS
		if conflict_count > 1 && sequence_index % 10 == 4 do limits.conflicts = 1
		observation, opened, failure := ksawery.sequence_observation_open(
			workflow_repository(),
			ksawery.Sequence_Generation(sequence_index + 1),
			source,
			fixture[:],
			limits,
			allocator,
		)
		if fixture != nil do delete(fixture)
		if !opened {
			_ = failure
			valid = false
			continue
		}
		descriptor, described := ksawery.sequence_observation_descriptor(&observation)
		valid = described && descriptor.fingerprint != 0 && valid
		if described {
			measurement.fingerprint_checks += 1
			if source.step != {} && descriptor.step == source.step do measurement.step_checks += 1
			if descriptor.conflict_count > 0 do measurement.conflict_checks += 1
			if descriptor.state == .Truncated do measurement.truncation_states += 1
		}
		fingerprint := descriptor.fingerprint
		ksawery.sequence_observation_close(&observation)

		fixture, fixture_error = conflict_fixture(conflict_count, allocator)
		if fixture_error != nil {
			valid = false
			continue
		}
		reentered, reentered_opened, _ := ksawery.sequence_observation_open(
			workflow_repository(),
			ksawery.Sequence_Generation(WORKFLOW_STATE_SEQUENCES + sequence_index + 1),
			source,
			fixture[:],
			limits,
			allocator,
		)
		if fixture != nil do delete(fixture)
		if reentered_opened {
			reentered_descriptor, reentered_described := ksawery.sequence_observation_descriptor(&reentered)
			if reentered_described && reentered_descriptor.fingerprint == fingerprint {
				measurement.reentry_checks += 1
			} else {
				valid = false
			}
			ksawery.sequence_observation_close(&reentered)
		} else {
			valid = false
		}

		record_valid, terminal := workflow_process_sequence(
			sequence_index,
			operations[kind_index],
			allocator,
		)
		valid = record_valid && valid
		switch terminal {
		case .Cancelled: measurement.cancellation_states += 1
		case .Timed_Out: measurement.timeout_states += 1
		case .Succeeded, .Failed, .Indeterminate:
			measurement.refresh_states += 1
			measurement.verification_states += 1
		case .Invalid, .Admitted, .Running, .Cancellation_Requested:
			valid = false
		}
		measurement.sequences += 1
		valid = tracking.current_memory_allocated == 0 && valid
	}
	measurement.elapsed_ns = time.duration_nanoseconds(time.tick_since(started))
	measurement.peak_bytes = tracking.peak_memory_allocated
	measurement.cleanup_bytes = tracking.current_memory_allocated
	mem.tracking_allocator_destroy(&tracking)
	valid = measurement.sequences == WORKFLOW_STATE_SEQUENCES &&
		measurement.elapsed_ns <= STUDY_LATENCY_LIMIT_NS &&
		measurement.peak_bytes <= STUDY_MEMORY_LIMIT_BYTES &&
		measurement.cleanup_bytes == 0 && valid
	return measurement, valid
}

@(private)
workflow_process_sequence :: proc(
	sequence_index: int,
	kind: ksawery.Repository_Operation_Kind,
	allocator: runtime.Allocator,
) -> (bool, ksawery.Repository_Process_Lifecycle) {
	repository := workflow_repository()
	authority := ksawery.Process_Record_Authority {
		operation = ksawery.Repository_Operation_ID(sequence_index + 1),
		repository = repository,
		observation_generation = ksawery.Observation_Generation(sequence_index + 1),
		kind = kind,
	}
	proposal := ksawery.Process_Record_Proposal {
		operation = authority.operation,
		generation = 1,
		repository = repository,
		observation_generation = authority.observation_generation,
		kind = kind,
		lifecycle = .Admitted,
		phase = .Checking,
		target_kind = .Repository,
		title = "Sequenced repository operation",
		target = "/tmp/odra-sequence-resource-study",
		phase_detail = "Checking exact repository state",
		progress = {kind = .Phase},
		timing = {admitted_ns = 10, started_ns = 10, updated_ns = 10},
		action_count = 1,
	}
	proposal.actions[0] = {kind = .Inspect, available = true}
	record, opened, _ := ksawery.process_record_open(
		authority, proposal, ksawery.DEFAULT_PROCESS_RECORD_LIMITS, allocator,
	)
	if !opened do return false, .Invalid
	defer ksawery.process_record_close(&record)
	proposal.generation = 2
	proposal.lifecycle = .Running
	proposal.phase = .Executing
	proposal.phase_detail = "Executing checked sequence action"
	proposal.timing.updated_ns = 20
	proposal.timing.elapsed_ns = 10
	proposal.actions = {}
	proposal.actions[0] = {kind = .Inspect, available = true}
	proposal.actions[1] = {kind = .Cancel, available = true}
	proposal.action_count = 2
	replaced, _ := ksawery.process_record_replace(
		&record, authority, proposal, ksawery.DEFAULT_PROCESS_RECORD_LIMITS, allocator,
	)
	if !replaced do return false, .Invalid
	terminal_cases := [?]struct {
		lifecycle: ksawery.Repository_Process_Lifecycle,
		outcome:   ksawery.Repository_Process_Outcome,
	} {
		{.Succeeded, .Verified_Success},
		{.Failed, .Known_Failure},
		{.Cancelled, .Cancelled_Before_Effect},
		{.Timed_Out, .Timed_Out_After_Possible_Effect},
		{.Indeterminate, .Indeterminate},
	}
	terminal := terminal_cases[sequence_index % len(terminal_cases)]
	generation := ksawery.Process_Record_Generation(3)
	if terminal.lifecycle == .Cancelled || terminal.lifecycle == .Timed_Out {
		proposal.generation = generation
		proposal.lifecycle = .Cancellation_Requested
		proposal.phase = .Cancelling
		proposal.phase_detail = "Stopping checked sequence action"
		proposal.timing.updated_ns = 30
		proposal.timing.elapsed_ns = 20
		proposal.actions = {}
		proposal.actions[0] = {kind = .Inspect, available = true}
		proposal.action_count = 1
		replaced, _ = ksawery.process_record_replace(
			&record, authority, proposal, ksawery.DEFAULT_PROCESS_RECORD_LIMITS, allocator,
		)
		generation += 1
	} else {
		proposal.generation = generation
		proposal.phase = .Refreshing
		proposal.phase_detail = "Refreshing repository observations"
		proposal.timing.updated_ns = 30
		proposal.timing.elapsed_ns = 20
		proposal.actions = {}
		proposal.actions[0] = {kind = .Inspect, available = true}
		proposal.action_count = 1
		replaced, _ = ksawery.process_record_replace(
			&record, authority, proposal, ksawery.DEFAULT_PROCESS_RECORD_LIMITS, allocator,
		)
		generation += 1
		proposal.generation = generation
		proposal.phase = .Verifying
		proposal.phase_detail = "Verifying refreshed repository truth"
		proposal.timing.updated_ns = 40
		proposal.timing.elapsed_ns = 30
		replaced, _ = ksawery.process_record_replace(
			&record, authority, proposal, ksawery.DEFAULT_PROCESS_RECORD_LIMITS, allocator,
		)
		generation += 1
	}
	if !replaced do return false, .Invalid
	proposal.generation = generation
	proposal.lifecycle = terminal.lifecycle
	proposal.outcome = terminal.outcome
	proposal.phase = .Verifying
	proposal.phase_detail = "Sequenced repository workflow complete"
	proposal.message = "Sequenced repository operation reached terminal state"
	proposal.timing.updated_ns = 50
	proposal.timing.finished_ns = 50
	proposal.timing.elapsed_ns = 40
	proposal.exit_status = terminal.lifecycle == .Succeeded ? 0 : 1
	proposal.exit_status_available = true
	proposal.actions = {}
	proposal.actions[0] = {kind = .Inspect, available = true}
	proposal.actions[1] = {kind = .Clear, available = true}
	proposal.action_count = 2
	replaced, _ = ksawery.process_record_replace(
		&record, authority, proposal, ksawery.DEFAULT_PROCESS_RECORD_LIMITS, allocator,
	)
	if !replaced do return false, .Invalid
	descriptor, described := ksawery.process_record_descriptor(&record)
	return described && descriptor.lifecycle == terminal.lifecycle &&
		descriptor.outcome == terminal.outcome && descriptor.action_count == 2,
		terminal.lifecycle
}

@(private)
workflow_repository :: proc() -> ksawery.Repository_Context {
	repository: ksawery.Repository_Context
	_ = ksawery.repository_context_assign(&repository, "/tmp/odra-sequence-resource-study")
	return repository
}

@(private)
workflow_revision :: proc(text: string) -> (ksawery.Revision_Identity, bool) {
	revision: ksawery.Revision_Identity
	return revision, ksawery.revision_identity_assign(&revision, text)
}

@(private)
measure_profile :: proc(profile: Sequence_Profile, conflict_count: int) -> (Sequence_Measurement, bool) {
	_ = profile
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	started := time.tick_now()
	fixture, allocation_error := conflict_fixture(conflict_count, allocator)
	measurement: Sequence_Measurement
	ok := false
	if allocation_error == nil {
		shape, shaped := sequence_shape(fixture[:])
		measurement.conflicts = shape.conflicts
		measurement.path_bytes = shape.path_bytes
		measurement.output_bytes = len(fixture)
		measurement.maximum_path = shape.maximum_path
		ok = shaped
		delete(fixture)
	}
	measurement.elapsed_ns = time.duration_nanoseconds(time.tick_since(started))
	measurement.peak_bytes = tracking.peak_memory_allocated
	measurement.cleanup_bytes = tracking.current_memory_allocated
	mem.tracking_allocator_destroy(&tracking)
	return measurement, ok
}

Sequence_Shape :: struct {
	conflicts:    int,
	path_bytes:   int,
	maximum_path: int,
}

@(private)
sequence_shape :: proc(data: []u8) -> (Sequence_Shape, bool) {
	if len(data) == 0 || data[len(data) - 1] != 0 do return {}, false
	shape: Sequence_Shape
	offset := 0
	for offset < len(data) {
		end := offset
		for end < len(data) && data[end] != 0 do end += 1
		if end == offset || end >= len(data) do return {}, false
		record := data[offset:end]
		if len(record) < 4 || record[0] != 'u' || record[1] != ' ' do return {}, false
		path_offset := 0
		for _ in 0 ..< 10 {
			for path_offset < len(record) && record[path_offset] != ' ' do path_offset += 1
			if path_offset >= len(record) do return {}, false
			path_offset += 1
		}
		path_length := len(record) - path_offset
		if path_length <= 0 do return {}, false
		shape.conflicts += 1
		shape.path_bytes += path_length
		shape.maximum_path = max(shape.maximum_path, path_length)
		offset = end + 1
	}
	return shape, true
}

@(private)
conflict_fixture :: proc(count: int, allocator: mem.Allocator) -> ([dynamic]u8, runtime.Allocator_Error) {
	if count <= 0 do return nil, nil
	data, allocation_error := make([dynamic]u8, 0, count * 192, allocator)
	if allocation_error != nil do return nil, allocation_error
	for index in 0 ..< count {
		record := fmt.aprintf(
			"u UU N... 100644 100644 100644 100644 0123456789012345678901234567890123456789 1234567890123456789012345678901234567890 2345678901234567890123456789012345678901 conflict-%05d.txt%c",
			index,
			u8(0),
		)
		_, append_error := append(&data, ..transmute([]u8)record)
		delete(record)
		if append_error != nil {
			delete(data)
			return nil, append_error
		}
	}
	return data, nil
}

@(private)
measure_operation_profiles :: proc() -> bool {
	for profile in Sequence_Profile {
		if profile < .Merge || profile > .Unknown do return false
	}
	return true
}
