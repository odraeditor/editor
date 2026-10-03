// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery_process_focused

import ksawery "../../src/ksawery"
import "core:mem"
import "core:testing"

/* Verifies the focused harness compiles the production Ksawery package and its existing process envelope. */
@(test)
production_process_envelope_is_available :: proc(t: ^testing.T) {
	testing.expect(t, ksawery.process_limits_are_valid(ksawery.DEFAULT_PROCESS_LIMITS))
	testing.expect_value(t, ksawery.DEFAULT_PROCESS_LIMITS.stdout_bytes, ksawery.DEFAULT_PROCESS_OUTPUT_BYTES)
	testing.expect_value(t, ksawery.DEFAULT_PROCESS_LIMITS.diagnostic_bytes, ksawery.DEFAULT_DIAGNOSTIC_BYTES)
	testing.expect_value(t, ksawery.DEFAULT_PROCESS_LIMITS.timeout_nanoseconds, ksawery.DEFAULT_PROCESS_TIMEOUT_NANOSECONDS)
	testing.expect_value(t, ksawery.DEFAULT_PROCESS_LIMITS.cancellation_grace_ns, ksawery.DEFAULT_CANCELLATION_GRACE_NANOSECONDS)
}

/* Verifies one focused package can exercise checked Ksawery requests without package-internal tests. */
@(test)
production_process_request_remains_checked :: proc(t: ^testing.T) {
	repository: ksawery.Repository_Context
	testing.expect(t, ksawery.repository_context_assign(&repository, "/tmp/odra-ksawery-focused"))
	request := ksawery.Process_Request {
		kind = .Observe_Status,
		repository = repository,
		limits = ksawery.DEFAULT_PROCESS_LIMITS,
	}
	testing.expect(t, ksawery.process_request_is_valid(request))
	request.kind = .Invalid
	testing.expect(t, !ksawery.process_request_is_valid(request))
}

/* Verifies the measured record envelope and terminal lifecycle vocabulary are exported. */
@(test)
process_record_contract_is_bounded :: proc(t: ^testing.T) {
	testing.expect(t, ksawery.process_record_limits_are_valid(ksawery.DEFAULT_PROCESS_RECORD_LIMITS))
	testing.expect_value(t, ksawery.DEFAULT_PROCESS_RECORD_LIMITS.retained_records, ksawery.DEFAULT_RETAINED_PROCESS_RECORDS)
	testing.expect_value(t, ksawery.DEFAULT_PROCESS_RECORD_LIMITS.retained_bytes, ksawery.DEFAULT_RETAINED_PROCESS_BYTES)
	testing.expect(t, !ksawery.repository_process_lifecycle_is_terminal(.Running))
	testing.expect(t, ksawery.repository_process_lifecycle_is_terminal(.Succeeded))
	testing.expect(t, ksawery.repository_process_lifecycle_is_terminal(.Indeterminate))

	overflow := ksawery.DEFAULT_PROCESS_RECORD_LIMITS
	overflow.retained_records = ksawery.MAX_RETAINED_PROCESS_RECORDS + 1
	testing.expect(t, !ksawery.process_record_limits_are_valid(overflow))
}

/* Verifies a valid proposal is copied and no longer borrows mutable public content. */
@(test)
process_record_proposals_are_copied :: proc(t: ^testing.T) {
	authority, proposal := focused_process_record_fixture()
	title := []u8{'F', 'e', 't', 'c', 'h', ' ', 'o', 'r', 'i', 'g', 'i', 'n'}
	proposal.title = string(title)
	record, opened, failure := ksawery.process_record_open(authority, proposal)
	testing.expectf(t, opened, "process record open failed with %v", failure)
	if !opened do return
	defer ksawery.process_record_close(&record)
	title[0] = 'X'
	descriptor, described := ksawery.process_record_descriptor(&record)
	testing.expect(t, described)
	copied_title, found := ksawery.process_record_text(&record, descriptor.title)
	testing.expect(t, found)
	testing.expect_value(t, string(copied_title), "Fetch origin")
	testing.expect_value(t, descriptor.actions[0].operation, proposal.operation)
	testing.expect_value(t, descriptor.actions[0].generation, proposal.generation)
	usage, measured := ksawery.process_record_usage(&record)
	testing.expect(t, measured)
	testing.expect_value(t, usage.records, u32(1))
	testing.expect_value(t, usage.output_bytes, u64(len(proposal.output)))
}

/* Verifies stale, foreign, sensitive, and post-terminal updates preserve the last valid generation. */
@(test)
process_record_replacement_preserves_last_valid_generation :: proc(t: ^testing.T) {
	authority, proposal := focused_process_record_fixture()
	record, opened, failure := ksawery.process_record_open(authority, proposal)
	testing.expectf(t, opened, "initial process record failed with %v", failure)
	if !opened do return
	defer ksawery.process_record_close(&record)

	stale := proposal
	stale.lifecycle = .Running
	stale.timing = {admitted_ns = 10, started_ns = 10, updated_ns = 12, elapsed_ns = 2}
	replaced, replace_failure := ksawery.process_record_replace(&record, authority, stale)
	testing.expect(t, !replaced)
	testing.expect_value(t, replace_failure, ksawery.Failure_Code.Process_Record_Stale)

	foreign_record := stale
	foreign_record.generation = 2
	foreign_record.operation = 8
	replaced, replace_failure = ksawery.process_record_replace(&record, authority, foreign_record)
	testing.expect(t, !replaced)
	testing.expect_value(t, replace_failure, ksawery.Failure_Code.Stale_Observation)

	sensitive := stale
	sensitive.generation = 2
	sensitive.diagnostic = transmute([]u8)string("Authorization: Bearer private")
	replaced, replace_failure = ksawery.process_record_replace(&record, authority, sensitive)
	testing.expect(t, !replaced)
	testing.expect_value(t, replace_failure, ksawery.Failure_Code.Sensitive_Content)

	running := stale
	running.generation = 2
	replaced, replace_failure = ksawery.process_record_replace(&record, authority, running)
	testing.expectf(t, replaced, "running process record failed with %v", replace_failure)
	if !replaced do return

	terminal := running
	terminal.generation = 3
	terminal.lifecycle = .Succeeded
	terminal.outcome = .Verified_Success
	terminal.message = "Fetch verified"
	terminal.timing = {admitted_ns = 10, started_ns = 10, updated_ns = 20, finished_ns = 20, elapsed_ns = 10}
	terminal.actions = {}
	terminal.actions[0] = {kind = .Inspect, available = true}
	terminal.actions[1] = {kind = .Clear, available = true}
	terminal.action_count = 2
	replaced, replace_failure = ksawery.process_record_replace(&record, authority, terminal)
	testing.expectf(t, replaced, "terminal process record failed with %v", replace_failure)
	if !replaced do return

	late := terminal
	late.generation = 4
	late.timing.updated_ns = 21
	late.timing.finished_ns = 21
	late.timing.elapsed_ns = 11
	replaced, replace_failure = ksawery.process_record_replace(&record, authority, late)
	testing.expect(t, !replaced)
	testing.expect_value(t, replace_failure, ksawery.Failure_Code.Process_Record_Closed)
	descriptor, described := ksawery.process_record_descriptor(&record)
	testing.expect(t, described)
	testing.expect_value(t, descriptor.generation, ksawery.Process_Record_Generation(3))
}

/* Verifies record teardown releases copied storage through the supplied allocator. */
@(test)
process_record_close_releases_owned_storage :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	authority, proposal := focused_process_record_fixture()
	record, opened, failure := ksawery.process_record_open(
		authority,
		proposal,
		ksawery.DEFAULT_PROCESS_RECORD_LIMITS,
		mem.tracking_allocator(&tracking),
	)
	testing.expectf(t, opened, "tracked process record failed with %v", failure)
	if opened do ksawery.process_record_close(&record)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&tracking)
}

focused_process_record_fixture :: proc() -> (ksawery.Process_Record_Authority, ksawery.Process_Record_Proposal) {
	repository: ksawery.Repository_Context
	_ = ksawery.repository_context_assign(&repository, "/tmp/odra-ksawery-focused")
	authority := ksawery.Process_Record_Authority {
		operation = 7,
		repository = repository,
		observation_generation = 11,
		kind = .Fetch,
	}
	proposal := ksawery.Process_Record_Proposal {
		operation = authority.operation,
		generation = 1,
		repository = authority.repository,
		observation_generation = authority.observation_generation,
		kind = authority.kind,
		lifecycle = .Admitted,
		phase = .Checking,
		target_kind = .Remote,
		title = "Fetch origin",
		target = "origin",
		phase_detail = "Checking remote",
		progress = {kind = .Phase},
		timing = {admitted_ns = 10, started_ns = 10, updated_ns = 10},
		output = transmute([]u8)string("ready\n"),
		diagnostic = transmute([]u8)string(""),
		action_count = 1,
	}
	proposal.actions[0] = {kind = .Inspect, available = true}
	return authority, proposal
}
