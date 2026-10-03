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

SELECTED_ACTIVE_OPERATIONS :: 1
SELECTED_ACTIVE_CHILDREN :: 1
SELECTED_CHILD_STREAMS :: 2
SELECTED_TITLE_BYTES :: 128
SELECTED_TARGET_BYTES :: 4 * 1_024
SELECTED_PHASE_BYTES :: 64
SELECTED_MESSAGE_BYTES :: 2 * 1_024
SELECTED_RETAINED_RECORDS :: 8
SELECTED_MAX_RETAINED_RECORDS :: 32
SELECTED_RETAINED_BYTES :: 2 * 1_024 * 1_024
SELECTED_MAX_RETAINED_BYTES :: 8 * 1_024 * 1_024
SELECTED_PENDING_EVENTS :: 64
SELECTED_PUBLISHED_UPDATES_PER_STEP :: 1
SELECTED_STREAM_READ_BYTES_PER_STEP :: 64 * 1_024
SELECTED_TEMPORARY_BYTES :: 2 * 1_024 * 1_024
SELECTED_MAX_TEMPORARY_BYTES :: 8 * 1_024 * 1_024
PROFILE_GATE_NS :: i64(5_000_000_000)
RAPID_UPDATE_GATE_NS :: i64(1_000_000_000)
RAPID_UPDATES :: 100_000
WORKFLOW_SEQUENCES :: 128
WORKFLOW_OUTPUT_BYTES :: 64 * 1_024
WORKFLOW_DIAGNOSTIC_BYTES :: 8 * 1_024

Study_Profile :: struct {
	name:             string,
	records:          int,
	title_bytes:      int,
	target_bytes:     int,
	phase_bytes:      int,
	message_bytes:    int,
	output_bytes:     int,
	diagnostic_bytes: int,
	pending_events:   int,
	temporary_bytes:  int,
	retained_limit:   int,
}

Study_Record :: struct {
	operation:  u64,
	generation: u64,
	title:      []u8,
	target:     []u8,
	phase:      []u8,
	message:    []u8,
	output:     []u8,
	diagnostic: []u8,
}

Workflow_Terminal_Case :: struct {
	lifecycle: ksawery.Repository_Process_Lifecycle,
	outcome:   ksawery.Repository_Process_Outcome,
}

main :: proc() {
	ordinary := Study_Profile {
		name = "ordinary",
		records = 2,
		title_bytes = 48,
		target_bytes = 256,
		phase_bytes = 24,
		message_bytes = 256,
		output_bytes = 64 * 1_024,
		diagnostic_bytes = 8 * 1_024,
		pending_events = 8,
		temporary_bytes = 128 * 1_024,
		retained_limit = SELECTED_RETAINED_BYTES,
	}
	demanding := Study_Profile {
		name = "demanding",
		records = SELECTED_RETAINED_RECORDS,
		title_bytes = SELECTED_TITLE_BYTES,
		target_bytes = SELECTED_TARGET_BYTES,
		phase_bytes = SELECTED_PHASE_BYTES,
		message_bytes = SELECTED_MESSAGE_BYTES,
		output_bytes = 192 * 1_024,
		diagnostic_bytes = 32 * 1_024,
		pending_events = SELECTED_PENDING_EVENTS,
		temporary_bytes = SELECTED_TEMPORARY_BYTES,
		retained_limit = SELECTED_RETAINED_BYTES,
	}
	retained := Study_Profile {
		name = "retained-record",
		records = SELECTED_MAX_RETAINED_RECORDS,
		title_bytes = SELECTED_TITLE_BYTES,
		target_bytes = SELECTED_TARGET_BYTES,
		phase_bytes = SELECTED_PHASE_BYTES,
		message_bytes = SELECTED_MESSAGE_BYTES,
		output_bytes = 240 * 1_024,
		diagnostic_bytes = 8 * 1_024,
		pending_events = SELECTED_PENDING_EVENTS,
		temporary_bytes = SELECTED_MAX_TEMPORARY_BYTES,
		retained_limit = SELECTED_MAX_RETAINED_BYTES,
	}

	valid := print_policy()
	valid = run_profile(ordinary) && valid
	valid = run_profile(demanding) && valid
	valid = run_profile(retained) && valid
	valid = run_overflow_profiles() && valid
	valid = run_rapid_updates() && valid
	valid = run_workflow_sequences() && valid
	if !valid do os.exit(1)
}

print_policy :: proc() -> bool {
	valid := SELECTED_ACTIVE_OPERATIONS == 1 &&
		SELECTED_ACTIVE_CHILDREN == 1 &&
		SELECTED_CHILD_STREAMS == 2 &&
		SELECTED_RETAINED_RECORDS < SELECTED_MAX_RETAINED_RECORDS &&
		SELECTED_RETAINED_BYTES < SELECTED_MAX_RETAINED_BYTES &&
		SELECTED_STREAM_READ_BYTES_PER_STEP == 64 * 1_024 &&
		ksawery.DEFAULT_PROCESS_LIMITS.stdout_bytes == ksawery.DEFAULT_PROCESS_OUTPUT_BYTES &&
		ksawery.DEFAULT_PROCESS_LIMITS.diagnostic_bytes == ksawery.DEFAULT_DIAGNOSTIC_BYTES &&
		ksawery.DEFAULT_PROCESS_LIMITS.timeout_nanoseconds == ksawery.DEFAULT_PROCESS_TIMEOUT_NANOSECONDS &&
		ksawery.DEFAULT_PROCESS_LIMITS.cancellation_grace_ns == ksawery.DEFAULT_CANCELLATION_GRACE_NANOSECONDS
	fmt.printf(
		"study=ksawery-process profile=policy valid=%v active_operations=%d active_children=%d child_streams=%d title_bytes=%d target_bytes=%d phase_bytes=%d message_bytes=%d retained_records=%d max_retained_records=%d retained_bytes=%d max_retained_bytes=%d pending_events=%d published_updates_per_step=%d stream_read_bytes_per_step=%d temporary_bytes=%d max_temporary_bytes=%d stdout_bytes=%d max_stdout_bytes=%d diagnostic_bytes=%d max_diagnostic_bytes=%d timeout_ns=%d max_timeout_ns=%d cancellation_grace_ns=%d\n",
		valid,
		SELECTED_ACTIVE_OPERATIONS,
		SELECTED_ACTIVE_CHILDREN,
		SELECTED_CHILD_STREAMS,
		SELECTED_TITLE_BYTES,
		SELECTED_TARGET_BYTES,
		SELECTED_PHASE_BYTES,
		SELECTED_MESSAGE_BYTES,
		SELECTED_RETAINED_RECORDS,
		SELECTED_MAX_RETAINED_RECORDS,
		SELECTED_RETAINED_BYTES,
		SELECTED_MAX_RETAINED_BYTES,
		SELECTED_PENDING_EVENTS,
		SELECTED_PUBLISHED_UPDATES_PER_STEP,
		SELECTED_STREAM_READ_BYTES_PER_STEP,
		SELECTED_TEMPORARY_BYTES,
		SELECTED_MAX_TEMPORARY_BYTES,
		ksawery.DEFAULT_PROCESS_OUTPUT_BYTES,
		ksawery.MAX_PROCESS_OUTPUT_BYTES,
		ksawery.DEFAULT_DIAGNOSTIC_BYTES,
		ksawery.MAX_DIAGNOSTIC_BYTES,
		ksawery.DEFAULT_PROCESS_TIMEOUT_NANOSECONDS,
		ksawery.MAX_PROCESS_TIMEOUT_NANOSECONDS,
		ksawery.DEFAULT_CANCELLATION_GRACE_NANOSECONDS,
	)
	return valid
}

run_profile :: proc(profile: Study_Profile) -> bool {
	if !profile_is_admitted(profile) {
		fmt.printf("study=ksawery-process profile=%s valid=false admitted=false\n", profile.name)
		return false
	}
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	started := time.tick_now()
	records, records_error := make([]Study_Record, profile.records, allocator)
	if records_error != nil {
		mem.tracking_allocator_destroy(&tracking)
		return false
	}
	allocated := true
	for &record, index in records {
		record.operation = u64(index + 1)
		record.generation = u64(index + 1)
		if !record_allocate(&record, profile, allocator) {
			allocated = false
			break
		}
		record_fill(&record, byte(index + 1))
	}
	retained_bytes := tracking.current_memory_allocated
	temporary, temporary_error := make([]u8, profile.temporary_bytes, allocator)
	if temporary_error == nil do bytes_fill(temporary, 0x5a)
	peak_bytes := tracking.peak_memory_allocated
	if temporary != nil do delete(temporary, allocator)
	for &record in records do record_close(&record, allocator)
	delete(records, allocator)
	elapsed_ns := time.duration_nanoseconds(time.tick_since(started))
	cleanup_bytes := tracking.current_memory_allocated
	mem.tracking_allocator_destroy(&tracking)
	valid := allocated && temporary_error == nil &&
		retained_bytes <= i64(profile.retained_limit) &&
		peak_bytes <= i64(profile.retained_limit + profile.temporary_bytes) &&
		elapsed_ns <= PROFILE_GATE_NS && cleanup_bytes == 0
	fmt.printf(
		"study=ksawery-process profile=%s valid=%v records=%d retained_bytes=%d retained_limit=%d temporary_bytes=%d peak_bytes=%d elapsed_ns=%d cleanup_bytes=%d\n",
		profile.name,
		valid,
		profile.records,
		retained_bytes,
		profile.retained_limit,
		profile.temporary_bytes,
		peak_bytes,
		elapsed_ns,
		cleanup_bytes,
	)
	return valid
}

run_overflow_profiles :: proc() -> bool {
	base := Study_Profile {
		name = "overflow",
		records = SELECTED_MAX_RETAINED_RECORDS,
		title_bytes = SELECTED_TITLE_BYTES,
		target_bytes = SELECTED_TARGET_BYTES,
		phase_bytes = SELECTED_PHASE_BYTES,
		message_bytes = SELECTED_MESSAGE_BYTES,
		output_bytes = 64 * 1_024,
		diagnostic_bytes = 8 * 1_024,
		pending_events = SELECTED_PENDING_EVENTS,
		temporary_bytes = SELECTED_TEMPORARY_BYTES,
		retained_limit = SELECTED_MAX_RETAINED_BYTES,
	}
	record_overflow := base
	record_overflow.records = SELECTED_MAX_RETAINED_RECORDS + 1
	content_overflow := base
	content_overflow.output_bytes = int(ksawery.MAX_PROCESS_OUTPUT_BYTES)
	content_overflow.diagnostic_bytes = int(ksawery.MAX_DIAGNOSTIC_BYTES)
	output_overflow := base
	output_overflow.output_bytes = int(ksawery.MAX_PROCESS_OUTPUT_BYTES) + 1
	diagnostic_overflow := base
	diagnostic_overflow.diagnostic_bytes = int(ksawery.MAX_DIAGNOSTIC_BYTES) + 1
	event_overflow := base
	event_overflow.pending_events = SELECTED_PENDING_EVENTS + 1
	temporary_overflow := base
	temporary_overflow.temporary_bytes = SELECTED_MAX_TEMPORARY_BYTES + 1
	valid := !profile_is_admitted(record_overflow) &&
		!profile_is_admitted(content_overflow) &&
		!profile_is_admitted(output_overflow) &&
		!profile_is_admitted(diagnostic_overflow) &&
		!profile_is_admitted(event_overflow) &&
		!profile_is_admitted(temporary_overflow)
	fmt.printf(
		"study=ksawery-process profile=overflow valid=%v record_limit_rejected=%v retained_limit_rejected=%v output_limit_rejected=%v diagnostic_limit_rejected=%v event_limit_rejected=%v temporary_limit_rejected=%v\n",
		valid,
		!profile_is_admitted(record_overflow),
		!profile_is_admitted(content_overflow),
		!profile_is_admitted(output_overflow),
		!profile_is_admitted(diagnostic_overflow),
		!profile_is_admitted(event_overflow),
		!profile_is_admitted(temporary_overflow),
	)
	return valid
}

run_rapid_updates :: proc() -> bool {
	started := time.tick_now()
	generation: u64
	published := 0
	pending := 0
	for _ in 0 ..< RAPID_UPDATES {
		pending += 1
		if pending == SELECTED_PENDING_EVENTS {
			generation += 1
			published += SELECTED_PUBLISHED_UPDATES_PER_STEP
			pending = 0
		}
	}
	if pending > 0 {
		generation += 1
		published += SELECTED_PUBLISHED_UPDATES_PER_STEP
	}
	elapsed_ns := time.duration_nanoseconds(time.tick_since(started))
	expected := (RAPID_UPDATES + SELECTED_PENDING_EVENTS - 1) / SELECTED_PENDING_EVENTS
	valid := generation == u64(expected) && published == expected && elapsed_ns <= RAPID_UPDATE_GATE_NS
	fmt.printf(
		"study=ksawery-process profile=rapid-update valid=%v source_updates=%d published_updates=%d final_generation=%d elapsed_ns=%d gate_ns=%d coalesced=true\n",
		valid,
		RAPID_UPDATES,
		published,
		generation,
		elapsed_ns,
		RAPID_UPDATE_GATE_NS,
	)
	return valid
}

run_workflow_sequences :: proc() -> bool {
	terminal_cases := [?]Workflow_Terminal_Case {
		{lifecycle = .Succeeded, outcome = .Verified_Success},
		{lifecycle = .Failed, outcome = .Known_Failure},
		{lifecycle = .Failed, outcome = .Verification_Mismatch},
		{lifecycle = .Cancelled, outcome = .Cancelled_Before_Effect},
		{lifecycle = .Cancelled, outcome = .Cancelled_After_Possible_Effect},
		{lifecycle = .Timed_Out, outcome = .Timed_Out_Before_Effect},
		{lifecycle = .Timed_Out, outcome = .Timed_Out_After_Possible_Effect},
		{lifecycle = .Indeterminate, outcome = .Indeterminate},
	}
	output, output_error := make([]u8, WORKFLOW_OUTPUT_BYTES, context.allocator)
	diagnostic, diagnostic_error := make([]u8, WORKFLOW_DIAGNOSTIC_BYTES, context.allocator)
	if output_error != nil || diagnostic_error != nil {
		if output != nil do delete(output)
		if diagnostic != nil do delete(diagnostic)
		return false
	}
	defer delete(output)
	defer delete(diagnostic)
	bytes_fill(output, 'o')
	bytes_fill(diagnostic, 'd')

	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	started := time.tick_now()
	max_generation := ksawery.Process_Record_Generation(0)
	cancellation_sequences := 0
	timeout_sequences := 0
	refresh_sequences := 0
	verification_sequences := 0
	restoration_sequences := 0
	valid := true
	previous_selection: ksawery.Process_Selection
	have_previous_selection := false

	for sequence in 0 ..< WORKFLOW_SEQUENCES {
		repository: ksawery.Repository_Context
		valid = ksawery.repository_context_assign(&repository, "/tmp/odra-process-workflow-study") && valid
		authority := ksawery.Process_Record_Authority {
			operation = ksawery.Repository_Operation_ID(sequence + 1),
			repository = repository,
			observation_generation = ksawery.Observation_Generation(sequence + 1),
			kind = .Fetch,
		}
		proposal := workflow_sequence_proposal(authority, output, diagnostic)
		record, opened, _ := ksawery.process_record_open(
			authority,
			proposal,
			ksawery.DEFAULT_PROCESS_RECORD_LIMITS,
			allocator,
		)
		if !opened {
			valid = false
			continue
		}

		proposal.generation = 2
		proposal.lifecycle = .Running
		proposal.phase = .Executing
		proposal.phase_detail = "Executing repository operation"
		proposal.timing = {admitted_ns = 10, started_ns = 10, updated_ns = 20, elapsed_ns = 10}
		workflow_sequence_set_running_actions(&proposal)
		replaced, _ := ksawery.process_record_replace(
			&record, authority, proposal, ksawery.DEFAULT_PROCESS_RECORD_LIMITS, allocator,
		)
		valid = replaced && valid
		if !replaced {
			ksawery.process_record_close(&record)
			continue
		}

		terminal_case := terminal_cases[sequence % len(terminal_cases)]
		generation := ksawery.Process_Record_Generation(3)
		updated_ns := i64(30)
		if terminal_case.lifecycle == .Cancelled || terminal_case.lifecycle == .Timed_Out {
			proposal.generation = generation
			proposal.lifecycle = .Cancellation_Requested
			proposal.phase = .Cancelling
			proposal.phase_detail = "Cancelling repository operation"
			proposal.timing.updated_ns = updated_ns
			proposal.timing.elapsed_ns = updated_ns - 10
			workflow_sequence_set_inspect_action(&proposal)
			replaced, _ = ksawery.process_record_replace(
				&record, authority, proposal, ksawery.DEFAULT_PROCESS_RECORD_LIMITS, allocator,
			)
			valid = replaced && valid
			generation += 1
			updated_ns += 10
			if terminal_case.lifecycle == .Cancelled do cancellation_sequences += 1
			if terminal_case.lifecycle == .Timed_Out do timeout_sequences += 1
		} else {
			proposal.generation = generation
			proposal.lifecycle = .Running
			proposal.phase = .Refreshing
			proposal.phase_detail = "Refreshing repository observations"
			proposal.timing.updated_ns = updated_ns
			proposal.timing.elapsed_ns = updated_ns - 10
			workflow_sequence_set_inspect_action(&proposal)
			replaced, _ = ksawery.process_record_replace(
				&record, authority, proposal, ksawery.DEFAULT_PROCESS_RECORD_LIMITS, allocator,
			)
			valid = replaced && valid
			generation += 1
			updated_ns += 10
			proposal.generation = generation
			proposal.phase = .Verifying
			proposal.phase_detail = "Verifying repository outcome"
			proposal.timing.updated_ns = updated_ns
			proposal.timing.elapsed_ns = updated_ns - 10
			replaced, _ = ksawery.process_record_replace(
				&record, authority, proposal, ksawery.DEFAULT_PROCESS_RECORD_LIMITS, allocator,
			)
			valid = replaced && valid
			generation += 1
			updated_ns += 10
			refresh_sequences += 1
			verification_sequences += 1
		}

		proposal.generation = generation
		proposal.lifecycle = terminal_case.lifecycle
		proposal.outcome = terminal_case.outcome
		proposal.phase = .Verifying
		proposal.phase_detail = "Repository workflow complete"
		proposal.message = "Repository process workflow completed"
		proposal.timing.updated_ns = updated_ns
		proposal.timing.finished_ns = updated_ns
		proposal.timing.elapsed_ns = updated_ns - 10
		proposal.output_truncated = sequence % 3 == 0
		proposal.diagnostic_truncated = sequence % 5 == 0
		proposal.exit_status = 0 if terminal_case.lifecycle == .Succeeded else 1
		proposal.exit_status_available = true
		workflow_sequence_set_terminal_actions(&proposal)
		replaced, _ = ksawery.process_record_replace(
			&record, authority, proposal, ksawery.DEFAULT_PROCESS_RECORD_LIMITS, allocator,
		)
		valid = replaced && valid
		if replaced {
			descriptor, described := ksawery.process_record_descriptor(&record)
			valid = described && descriptor.generation == generation &&
			        descriptor.lifecycle == terminal_case.lifecycle &&
			        descriptor.outcome == terminal_case.outcome && valid
			if generation > max_generation do max_generation = generation
			one := [1]ksawery.Process_Record {record}
			selection, selected := ksawery.process_selection_begin(one[:])
			valid = selected && valid
			if have_previous_selection {
				restored, restoration_ok, _ := ksawery.process_selection_reconcile(
					one[:], previous_selection,
				)
				valid = restoration_ok && restored.current.operation == authority.operation && valid
				if restoration_ok do restoration_sequences += 1
			}
			previous_selection = selection
			have_previous_selection = selected
		}
		ksawery.process_record_close(&record)
		valid = tracking.current_memory_allocated == 0 && valid
	}

	elapsed_ns := time.duration_nanoseconds(time.tick_since(started))
	peak_bytes := tracking.peak_memory_allocated
	cleanup_bytes := tracking.current_memory_allocated
	mem.tracking_allocator_destroy(&tracking)
	valid = cancellation_sequences > 0 && timeout_sequences > 0 &&
	        refresh_sequences > 0 && verification_sequences == refresh_sequences &&
	        restoration_sequences == WORKFLOW_SEQUENCES - 1 &&
	        elapsed_ns <= PROFILE_GATE_NS && cleanup_bytes == 0 && valid
	fmt.printf(
		"study=ksawery-process profile=workflow-sequence valid=%v sequences=%d max_generation=%d cancellation_sequences=%d timeout_sequences=%d refresh_sequences=%d verification_sequences=%d restoration_sequences=%d output_bytes=%d diagnostic_bytes=%d peak_bytes=%d elapsed_ns=%d cleanup_bytes=%d\n",
		valid,
		WORKFLOW_SEQUENCES,
		max_generation,
		cancellation_sequences,
		timeout_sequences,
		refresh_sequences,
		verification_sequences,
		restoration_sequences,
		WORKFLOW_OUTPUT_BYTES,
		WORKFLOW_DIAGNOSTIC_BYTES,
		peak_bytes,
		elapsed_ns,
		cleanup_bytes,
	)
	return valid
}

workflow_sequence_proposal :: proc(
	authority: ksawery.Process_Record_Authority,
	output: []u8,
	diagnostic: []u8,
) -> ksawery.Process_Record_Proposal {
	proposal := ksawery.Process_Record_Proposal {
		operation = authority.operation,
		generation = 1,
		repository = authority.repository,
		observation_generation = authority.observation_generation,
		kind = authority.kind,
		lifecycle = .Admitted,
		phase = .Checking,
		target_kind = .Remote,
		title = "Fetch repository remote",
		target = "origin",
		phase_detail = "Checking repository operation",
		progress = {kind = .Phase},
		timing = {admitted_ns = 10, started_ns = 10, updated_ns = 10},
		output = output,
		diagnostic = diagnostic,
	}
	workflow_sequence_set_inspect_action(&proposal)
	return proposal
}

workflow_sequence_set_inspect_action :: proc(proposal: ^ksawery.Process_Record_Proposal) {
	proposal.actions = {}
	proposal.actions[0] = {kind = .Inspect, available = true}
	proposal.action_count = 1
}

workflow_sequence_set_running_actions :: proc(proposal: ^ksawery.Process_Record_Proposal) {
	workflow_sequence_set_inspect_action(proposal)
	proposal.actions[1] = {kind = .Cancel, available = true}
	proposal.action_count = 2
}

workflow_sequence_set_terminal_actions :: proc(proposal: ^ksawery.Process_Record_Proposal) {
	workflow_sequence_set_inspect_action(proposal)
	proposal.actions[1] = {kind = .Clear, available = true}
	proposal.action_count = 2
}

profile_is_admitted :: proc(profile: Study_Profile) -> bool {
	if profile.records <= 0 || profile.records > SELECTED_MAX_RETAINED_RECORDS ||
	   profile.title_bytes < 0 || profile.title_bytes > SELECTED_TITLE_BYTES ||
	   profile.target_bytes < 0 || profile.target_bytes > SELECTED_TARGET_BYTES ||
	   profile.phase_bytes < 0 || profile.phase_bytes > SELECTED_PHASE_BYTES ||
	   profile.message_bytes < 0 || profile.message_bytes > SELECTED_MESSAGE_BYTES ||
	   profile.output_bytes < 0 || u64(profile.output_bytes) > ksawery.MAX_PROCESS_OUTPUT_BYTES ||
	   profile.diagnostic_bytes < 0 || u64(profile.diagnostic_bytes) > ksawery.MAX_DIAGNOSTIC_BYTES ||
	   profile.pending_events <= 0 || profile.pending_events > SELECTED_PENDING_EVENTS ||
	   profile.temporary_bytes < 0 || profile.temporary_bytes > SELECTED_MAX_TEMPORARY_BYTES ||
	   profile.retained_limit <= 0 || profile.retained_limit > SELECTED_MAX_RETAINED_BYTES {
		return false
	}
	per_record := profile.title_bytes + profile.target_bytes + profile.phase_bytes +
		profile.message_bytes + profile.output_bytes + profile.diagnostic_bytes
	return per_record <= profile.retained_limit / profile.records
}

record_allocate :: proc(record: ^Study_Record, profile: Study_Profile, allocator: mem.Allocator) -> bool {
	if record == nil do return false
	allocation_error: mem.Allocator_Error
	record.title, allocation_error = make([]u8, profile.title_bytes, allocator)
	if allocation_error == nil do record.target, allocation_error = make([]u8, profile.target_bytes, allocator)
	if allocation_error == nil do record.phase, allocation_error = make([]u8, profile.phase_bytes, allocator)
	if allocation_error == nil do record.message, allocation_error = make([]u8, profile.message_bytes, allocator)
	if allocation_error == nil do record.output, allocation_error = make([]u8, profile.output_bytes, allocator)
	if allocation_error == nil do record.diagnostic, allocation_error = make([]u8, profile.diagnostic_bytes, allocator)
	return allocation_error == nil
}

record_fill :: proc(record: ^Study_Record, value: byte) {
	if record == nil do return
	bytes_fill(record.title, value)
	bytes_fill(record.target, value)
	bytes_fill(record.phase, value)
	bytes_fill(record.message, value)
	bytes_fill(record.output, value)
	bytes_fill(record.diagnostic, value)
}

bytes_fill :: proc(storage: []u8, value: byte) {
	for &item in storage do item = value
}

record_close :: proc(record: ^Study_Record, allocator: mem.Allocator) {
	if record == nil do return
	if record.title != nil do delete(record.title, allocator)
	if record.target != nil do delete(record.target, allocator)
	if record.phase != nil do delete(record.phase, allocator)
	if record.message != nil do delete(record.message, allocator)
	if record.output != nil do delete(record.output, allocator)
	if record.diagnostic != nil do delete(record.diagnostic, allocator)
	record^ = {}
}
