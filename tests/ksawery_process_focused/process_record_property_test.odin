// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery_process_focused

import ksawery "../../src/ksawery"
import "base:runtime"
import "core:mem"
import "core:testing"

Generated_Terminal_Case :: struct {
	lifecycle: ksawery.Repository_Process_Lifecycle,
	outcome:   ksawery.Repository_Process_Outcome,
}

Process_Record_Failing_Allocator :: struct {
	backing:                runtime.Allocator,
	fail_after:             u64,
	successful_allocations: u64,
}

/* Verifies generated operation chains preserve identity, transitions, progress, truncation, and teardown. */
@(test)
generated_process_record_sequences_are_bounded :: proc(t: ^testing.T) {
	terminal_cases := [?]Generated_Terminal_Case {
		{lifecycle = .Succeeded, outcome = .Verified_Success},
		{lifecycle = .Failed, outcome = .Known_Failure},
		{lifecycle = .Failed, outcome = .Verification_Mismatch},
		{lifecycle = .Cancelled, outcome = .Cancelled_Before_Effect},
		{lifecycle = .Cancelled, outcome = .Cancelled_After_Possible_Effect},
		{lifecycle = .Timed_Out, outcome = .Timed_Out_Before_Effect},
		{lifecycle = .Timed_Out, outcome = .Timed_Out_After_Possible_Effect},
		{lifecycle = .Indeterminate, outcome = .Indeterminate},
	}
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)

	for sequence in 0 ..< 128 {
		authority, proposal := focused_process_record_fixture()
		authority.operation = ksawery.Repository_Operation_ID(sequence + 1)
		proposal.operation = authority.operation
		record, opened, failure := ksawery.process_record_open(
			authority,
			proposal,
			ksawery.DEFAULT_PROCESS_RECORD_LIMITS,
			allocator,
		)
		testing.expectf(t, opened, "generated initial record %d failed with %v", sequence, failure)
		if !opened do continue

		running := proposal
		running.generation = 2
		running.lifecycle = .Running
		running.phase = .Executing
		running.phase_detail = "Executing fetch"
		running.timing = {admitted_ns = 10, started_ns = 10, updated_ns = 20, elapsed_ns = 10}
		if sequence % 2 == 0 {
			running.progress = {kind = .Determinate, current = u64(sequence % 7), total = 7}
		} else {
			running.progress = {kind = .Phase}
		}
		running.actions = {}
		running.actions[0] = {kind = .Inspect, available = true}
		running.actions[1] = {kind = .Cancel, available = true}
		running.action_count = 2
		replaced, replace_failure := ksawery.process_record_replace(
			&record,
			authority,
			running,
			ksawery.DEFAULT_PROCESS_RECORD_LIMITS,
			allocator,
		)
		testing.expectf(t, replaced, "generated running record %d failed with %v", sequence, replace_failure)
		if !replaced {
			ksawery.process_record_close(&record)
			continue
		}

		stale := running
		stale.timing.updated_ns = 21
		stale.timing.elapsed_ns = 11
		replaced, replace_failure = ksawery.process_record_replace(
			&record,
			authority,
			stale,
			ksawery.DEFAULT_PROCESS_RECORD_LIMITS,
			allocator,
		)
		testing.expect(t, !replaced)
		testing.expect_value(t, replace_failure, ksawery.Failure_Code.Process_Record_Stale)

		terminal_case := terminal_cases[sequence % len(terminal_cases)]
		generation := ksawery.Process_Record_Generation(3)
		updated_ns := i64(30)
		if terminal_case.lifecycle == .Cancelled || terminal_case.lifecycle == .Timed_Out ||
		   terminal_case.lifecycle == .Indeterminate {
			cancelling := running
			cancelling.generation = generation
			cancelling.lifecycle = .Cancellation_Requested
			cancelling.phase = .Cancelling
			cancelling.phase_detail = "Cancelling child"
			cancelling.progress = {kind = .Phase}
			cancelling.timing = {admitted_ns = 10, started_ns = 10, updated_ns = updated_ns, elapsed_ns = updated_ns - 10}
			cancelling.actions = {}
			cancelling.actions[0] = {kind = .Inspect, available = true}
			cancelling.action_count = 1
			replaced, replace_failure = ksawery.process_record_replace(
				&record,
				authority,
				cancelling,
				ksawery.DEFAULT_PROCESS_RECORD_LIMITS,
				allocator,
			)
			testing.expectf(t, replaced, "generated cancellation record %d failed with %v", sequence, replace_failure)
			if !replaced {
				ksawery.process_record_close(&record)
				continue
			}
			generation += 1
			updated_ns += 10
		}

		terminal := running
		terminal.generation = generation
		terminal.lifecycle = terminal_case.lifecycle
		terminal.phase = .Verifying
		terminal.phase_detail = "Repository truth checked"
		terminal.outcome = terminal_case.outcome
		terminal.message = "Repository process completed"
		terminal.progress = {kind = .Phase}
		terminal.timing = {
			admitted_ns = 10,
			started_ns = 10,
			updated_ns = updated_ns,
			finished_ns = updated_ns,
			elapsed_ns = updated_ns - 10,
		}
		terminal.output_truncated = sequence % 3 == 0
		terminal.diagnostic_truncated = sequence % 5 == 0
		terminal.exit_status = 0 if terminal.lifecycle == .Succeeded else 1
		terminal.exit_status_available = true
		terminal.actions = {}
		terminal.actions[0] = {kind = .Inspect, available = true}
		terminal.actions[1] = {kind = .Clear, available = true}
		terminal.action_count = 2
		replaced, replace_failure = ksawery.process_record_replace(
			&record,
			authority,
			terminal,
			ksawery.DEFAULT_PROCESS_RECORD_LIMITS,
			allocator,
		)
		testing.expectf(t, replaced, "generated terminal record %d failed with %v", sequence, replace_failure)
		if replaced {
			descriptor, described := ksawery.process_record_descriptor(&record)
			testing.expect(t, described)
			testing.expect_value(t, descriptor.operation, authority.operation)
			testing.expect_value(t, descriptor.generation, generation)
			testing.expect_value(t, descriptor.lifecycle, terminal_case.lifecycle)
			testing.expect_value(t, descriptor.outcome, terminal_case.outcome)
			testing.expect_value(t, descriptor.content.output_truncated, terminal.output_truncated)
			testing.expect_value(t, descriptor.content.diagnostic_truncated, terminal.diagnostic_truncated)

			late := terminal
			late.generation += 1
			late.timing.updated_ns += 1
			late.timing.finished_ns += 1
			late.timing.elapsed_ns += 1
			replaced, replace_failure = ksawery.process_record_replace(
				&record,
				authority,
				late,
				ksawery.DEFAULT_PROCESS_RECORD_LIMITS,
				allocator,
			)
			testing.expect(t, !replaced)
			testing.expect_value(t, replace_failure, ksawery.Failure_Code.Process_Record_Closed)
			preserved, preserved_ok := ksawery.process_record_descriptor(&record)
			testing.expect(t, preserved_ok)
			testing.expect_value(t, preserved.generation, generation)
		}
		ksawery.process_record_close(&record)
		testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	}
	mem.tracking_allocator_destroy(&tracking)
}

/* Verifies allocation failures neither leak storage nor replace a valid generation. */
@(test)
process_record_allocation_faults_preserve_state :: proc(t: ^testing.T) {
	for fail_after: u64 = 0; fail_after < 2; fail_after += 1 {
		tracking: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracking, context.allocator)
		failing := Process_Record_Failing_Allocator {
			backing = mem.tracking_allocator(&tracking),
			fail_after = fail_after,
		}
		authority, proposal := focused_process_record_fixture()
		record, opened, failure := ksawery.process_record_open(
			authority,
			proposal,
			ksawery.DEFAULT_PROCESS_RECORD_LIMITS,
			process_record_failing_allocator(&failing),
		)
		testing.expect(t, !opened)
		testing.expect_value(t, failure, ksawery.Failure_Code.Allocation)
		if opened do ksawery.process_record_close(&record)
		testing.expect_value(t, tracking.current_memory_allocated, i64(0))
		mem.tracking_allocator_destroy(&tracking)
	}

	authority, proposal := focused_process_record_fixture()
	record, opened, failure := ksawery.process_record_open(authority, proposal)
	testing.expectf(t, opened, "allocation preservation fixture failed with %v", failure)
	if !opened do return
	defer ksawery.process_record_close(&record)
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	failing := Process_Record_Failing_Allocator {
		backing = mem.tracking_allocator(&tracking),
		fail_after = 0,
	}
	running := proposal
	running.generation = 2
	running.lifecycle = .Running
	running.phase = .Executing
	running.timing = {admitted_ns = 10, started_ns = 10, updated_ns = 20, elapsed_ns = 10}
	replaced, replace_failure := ksawery.process_record_replace(
		&record,
		authority,
		running,
		ksawery.DEFAULT_PROCESS_RECORD_LIMITS,
		process_record_failing_allocator(&failing),
	)
	testing.expect(t, !replaced)
	testing.expect_value(t, replace_failure, ksawery.Failure_Code.Allocation)
	descriptor, described := ksawery.process_record_descriptor(&record)
	testing.expect(t, described)
	testing.expect_value(t, descriptor.generation, ksawery.Process_Record_Generation(1))
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&tracking)
}

process_record_failing_allocator :: proc(state: ^Process_Record_Failing_Allocator) -> runtime.Allocator {
	return {procedure = process_record_failing_allocator_proc, data = state}
}

process_record_failing_allocator_proc :: proc(
	allocator_data: rawptr,
	mode: runtime.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	location: runtime.Source_Code_Location,
) -> ([]byte, runtime.Allocator_Error) {
	allocator := cast(^Process_Record_Failing_Allocator)allocator_data
	if mode == .Alloc || mode == .Resize || mode == .Resize_Non_Zeroed {
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
