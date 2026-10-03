// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery_module

import ksawery "../ksawery"
import "base:runtime"

/* Ksawery_Process_Coordinator owns one session's stable operation chain and retained records. */
Ksawery_Process_Coordinator :: struct {
	repository:        ksawery.Repository_Context,
	limits:            ksawery.Process_Record_Limits,
	records:           [int(ksawery.MAX_RETAINED_PROCESS_RECORDS)]ksawery.Process_Record,
	record_count:      u32,
	active_authority:  ksawery.Process_Record_Authority,
	active_generation: ksawery.Process_Record_Generation,
	child_association: ksawery.Repository_Process_Association,
	next_operation:    ksawery.Repository_Operation_ID,
	confirmed_observation: ksawery.Observation_Generation,
	active_phase:      ksawery.Repository_Process_Phase,
	active:            bool,
	child_attached:    bool,
	observation_stale: bool,
	allocator:         runtime.Allocator,
}

/* Ksawery_Process_Coordinator_Usage reports bounded coordinator ownership. */
Ksawery_Process_Coordinator_Usage :: struct {
	records:           u32,
	retained_bytes:    u64,
	output_bytes:      u64,
	diagnostic_bytes:  u64,
	active_operations: u8,
	active_children:   u8,
}

/* Ksawery_Repository_Verification_State classifies refreshed repository evidence. */
Ksawery_Repository_Verification_State :: enum u8 {
	Unavailable,
	Verified,
	Known_Failure,
	Mismatch,
}

/* Ksawery_Repository_Verification identifies exact Git-derived evidence for one operation. */
Ksawery_Repository_Verification :: struct {
	operation:            ksawery.Repository_Operation_ID,
	repository:           ksawery.Repository_Context,
	admitted_generation:  ksawery.Observation_Generation,
	refreshed_generation: ksawery.Observation_Generation,
	state:                Ksawery_Repository_Verification_State,
	refresh_attempted:    bool,
}

/* Ksawery_Process_Resolution is one terminal result derived without process-text authority. */
Ksawery_Process_Resolution :: struct {
	lifecycle: ksawery.Repository_Process_Lifecycle,
	outcome:   ksawery.Repository_Process_Outcome,
	failure:   ksawery.Failure_Code,
}

/* ksawery_process_coordinator_init establishes one bounded repository-local operation owner. */
ksawery_process_coordinator_init :: proc(
	coordinator: ^Ksawery_Process_Coordinator,
	repository: ksawery.Repository_Context,
	limits := ksawery.DEFAULT_PROCESS_RECORD_LIMITS,
	allocator := context.allocator,
) -> bool {
	if coordinator == nil || allocator.procedure == nil ||
	   !ksawery.repository_context_is_valid(repository) ||
	   !ksawery.process_record_limits_are_valid(limits) {
		return false
	}
	coordinator^ = {
		repository = repository,
		limits = limits,
		next_operation = 1,
		allocator = allocator,
	}
	return true
}

/* ksawery_process_coordinator_admit opens one stable operation and its first immutable record. */
ksawery_process_coordinator_admit :: proc(
	coordinator: ^Ksawery_Process_Coordinator,
	observation_generation: ksawery.Observation_Generation,
	kind: ksawery.Repository_Operation_Kind,
	proposal: ksawery.Process_Record_Proposal,
) -> (ksawery.Process_Record_Authority, bool, ksawery.Failure_Code) {
	if coordinator == nil || coordinator.allocator.procedure == nil || coordinator.active ||
	   observation_generation == ksawery.Observation_Generation(0) || kind == .Invalid ||
	   coordinator.next_operation == ksawery.Repository_Operation_ID(0) {
		return {}, false, .Invalid_Request
	}
	if coordinator.observation_stale do return {}, false, .Stale_Observation
	if coordinator.confirmed_observation != ksawery.Observation_Generation(0) &&
	   observation_generation != coordinator.confirmed_observation {
		return {}, false, .Stale_Observation
	}
	if proposal.lifecycle != .Admitted ||
	   (proposal.phase != .Checking && proposal.phase != .Executing) {
		return {}, false, .Invalid_Request
	}
	authority := ksawery.Process_Record_Authority {
		operation = coordinator.next_operation,
		repository = coordinator.repository,
		observation_generation = observation_generation,
		kind = kind,
	}
	candidate := proposal
	candidate.operation = authority.operation
	candidate.generation = 1
	candidate.repository = authority.repository
	candidate.observation_generation = authority.observation_generation
	candidate.kind = authority.kind
	record, opened, failure := ksawery.process_record_open(
		authority,
		candidate,
		coordinator.limits,
		coordinator.allocator,
	)
	if !opened do return {}, false, failure
	record_usage, measured := ksawery.process_record_usage(&record)
	if !measured {
		ksawery.process_record_close(&record)
		return {}, false, .Cleanup
	}
	for coordinator.record_count > 0 &&
	    (coordinator.record_count >= coordinator.limits.retained_records ||
	     ksawery_process_coordinator_retained_bytes(coordinator) + record_usage.retained_bytes >
	     coordinator.limits.retained_bytes) {
		ksawery_process_coordinator_evict_oldest(coordinator)
	}
	coordinator.records[int(coordinator.record_count)] = record
	coordinator.record_count += 1
	coordinator.active_authority = authority
	coordinator.active_generation = 1
	coordinator.confirmed_observation = observation_generation
	coordinator.active_phase = candidate.phase
	coordinator.active = true
	coordinator.observation_stale = candidate.phase == .Executing &&
	                                ksawery_process_operation_may_mutate(kind)
	if coordinator.next_operation == ksawery.Repository_Operation_ID(~u64(0)) {
		coordinator.next_operation = 0
	} else {
		coordinator.next_operation += 1
	}
	return authority, true, .None
}

/* ksawery_process_coordinator_attach_child binds the active record to one native owner. */
ksawery_process_coordinator_attach_child :: proc(
	coordinator: ^Ksawery_Process_Coordinator,
	process: ^ksawery.Repository_Process,
	now_ns: i64,
) -> (bool, ksawery.Failure_Code) {
	if coordinator == nil || !coordinator.active || coordinator.child_attached || process == nil {
		return false, .Invalid_Request
	}
	association := ksawery.Repository_Process_Association {
		authority = coordinator.active_authority,
		generation = coordinator.active_generation,
	}
	attached, failure := ksawery.repository_process_associate(process, association, now_ns)
	if !attached do return false, failure
	coordinator.child_association = association
	coordinator.child_attached = true
	return true, .None
}

/* ksawery_process_coordinator_publish replaces the current immutable generation and preserves terminal records. */
ksawery_process_coordinator_publish :: proc(
	coordinator: ^Ksawery_Process_Coordinator,
	process: ^ksawery.Repository_Process,
	proposal: ksawery.Process_Record_Proposal,
) -> (bool, ksawery.Failure_Code) {
	if coordinator == nil || !coordinator.active || coordinator.record_count == 0 {
		return false, .Invalid_Request
	}
	next_generation := coordinator.active_generation + 1
	if next_generation <= coordinator.active_generation do return false, .Process_Record_Stale
	candidate := proposal
	candidate.operation = coordinator.active_authority.operation
	candidate.generation = next_generation
	candidate.repository = coordinator.active_authority.repository
	candidate.observation_generation = coordinator.active_authority.observation_generation
	candidate.kind = coordinator.active_authority.kind
	current := &coordinator.records[int(coordinator.record_count - 1)]
	previous, described := ksawery.process_record_descriptor(current)
	if !described do return false, .Cleanup
	previous_target, targeted := ksawery.process_record_text(current, previous.target)
	if !targeted || previous.target_kind != candidate.target_kind || string(previous_target) != candidate.target {
		return false, .Stale_Observation
	}
	if !ksawery_process_phase_transition_is_valid(
		previous.phase,
		candidate.phase,
		candidate.lifecycle,
	) {
		return false, .Invalid_Request
	}
	if candidate.phase == .Verifying && coordinator.observation_stale {
		return false, .Stale_Observation
	}
	replaced, failure := ksawery.process_record_replace(
		current,
		coordinator.active_authority,
		candidate,
		coordinator.limits,
		coordinator.allocator,
	)
	if !replaced do return false, failure
	if coordinator.child_attached {
		if process == nil {
			coordinator.child_association = {}
			coordinator.child_attached = false
			return false, .Cleanup
		}
		advanced, advance_failure := ksawery.repository_process_advance_record_generation(
			process,
			coordinator.active_generation,
			next_generation,
		)
		if !advanced {
			coordinator.child_association = {}
			coordinator.child_attached = false
			return false, advance_failure
		}
		coordinator.child_association.generation = next_generation
	}
	coordinator.active_generation = next_generation
	coordinator.active_phase = candidate.phase
	if candidate.phase == .Executing &&
	   ksawery_process_operation_may_mutate(coordinator.active_authority.kind) {
		coordinator.observation_stale = true
	}
	if ksawery.repository_process_lifecycle_is_terminal(candidate.lifecycle) {
		coordinator.active = false
	}
	return true, .None
}

/* ksawery_process_coordinator_confirm_refresh advances only from the last confirmed observation. */
ksawery_process_coordinator_confirm_refresh :: proc(
	coordinator: ^Ksawery_Process_Coordinator,
	repository: ksawery.Repository_Context,
	generation: ksawery.Observation_Generation,
) -> (bool, ksawery.Failure_Code) {
	if coordinator == nil || !coordinator.active || coordinator.active_phase != .Refreshing ||
	   repository != coordinator.repository || generation == ksawery.Observation_Generation(0) {
		return false, .Invalid_Request
	}
	if generation <= coordinator.confirmed_observation do return false, .Stale_Observation
	coordinator.confirmed_observation = generation
	coordinator.observation_stale = false
	return true, .None
}

/* ksawery_process_coordinator_command_is_current rejects concurrent and stale repository work. */
ksawery_process_coordinator_command_is_current :: proc(
	coordinator: ^Ksawery_Process_Coordinator,
	repository: ksawery.Repository_Context,
	generation: ksawery.Observation_Generation,
) -> (bool, ksawery.Failure_Code) {
	if coordinator == nil || coordinator.allocator.procedure == nil ||
	   repository != coordinator.repository || generation == ksawery.Observation_Generation(0) {
		return false, .Invalid_Request
	}
	if coordinator.active do return false, .Action_Unavailable
	if coordinator.observation_stale do return false, .Stale_Observation
	if coordinator.confirmed_observation != ksawery.Observation_Generation(0) &&
	   generation != coordinator.confirmed_observation {
		return false, .Stale_Observation
	}
	return true, .None
}

/* ksawery_process_coordinator_resolve_outcome combines child facts with refreshed repository truth. */
ksawery_process_coordinator_resolve_outcome :: proc(
	coordinator: ^Ksawery_Process_Coordinator,
	child: ksawery.Repository_Process_Lifecycle_View,
	verification: Ksawery_Repository_Verification,
) -> (Ksawery_Process_Resolution, bool, ksawery.Failure_Code) {
	if coordinator == nil || !coordinator.active ||
	   child.association.authority != coordinator.active_authority ||
	   child.association.generation != coordinator.active_generation ||
	   verification.operation != coordinator.active_authority.operation ||
	   verification.repository != coordinator.repository ||
	   verification.admitted_generation != coordinator.active_authority.observation_generation {
		return {}, false, .Stale_Observation
	}
	if child.owner_state != .Completed && child.owner_state != .Failed {
		return {}, false, .Invalid_Request
	}
	if child.child.state == .Uncertain || child.failure_evidence.stage == .Reap ||
	   child.failure_evidence.stage == .Cleanup ||
	   child.failure_evidence.secondary_stage == .Reap ||
	   child.failure_evidence.secondary_stage == .Cleanup {
		return {
			lifecycle = .Indeterminate,
			outcome = .Indeterminate,
			failure = child.failure,
		}, true, .None
	}
	effect := child.failure_evidence.effect
	if child.termination.reason == .Cancellation {
		outcome := ksawery.Repository_Process_Outcome.Cancelled_Before_Effect
		if effect == .May_Have_Started do outcome = .Cancelled_After_Possible_Effect
		return {lifecycle = .Cancelled, outcome = outcome, failure = .Cancelled}, true, .None
	}
	if child.termination.reason == .Timeout {
		outcome := ksawery.Repository_Process_Outcome.Timed_Out_Before_Effect
		if effect == .May_Have_Started do outcome = .Timed_Out_After_Possible_Effect
		return {lifecycle = .Timed_Out, outcome = outcome, failure = .Timeout}, true, .None
	}
	verification_valid := ksawery_process_verification_is_valid(coordinator, verification)
	if !verification_valid && effect == .May_Have_Started {
		return {
			lifecycle = .Indeterminate,
			outcome = .Indeterminate,
			failure = child.failure,
		}, true, .None
	}
	if !verification_valid do return {}, false, .Stale_Observation
	if child.owner_state == .Completed {
		switch verification.state {
		case .Verified:
			return {lifecycle = .Succeeded, outcome = .Verified_Success}, true, .None
		case .Known_Failure:
			return {lifecycle = .Failed, outcome = .Known_Failure, failure = child.failure}, true, .None
		case .Mismatch:
			return {lifecycle = .Failed, outcome = .Verification_Mismatch}, true, .None
		case .Unavailable:
			return {lifecycle = .Indeterminate, outcome = .Indeterminate, failure = child.failure}, true, .None
		}
	}
	switch verification.state {
	case .Known_Failure:
		return {lifecycle = .Failed, outcome = .Known_Failure, failure = child.failure}, true, .None
	case .Mismatch:
		return {lifecycle = .Failed, outcome = .Verification_Mismatch, failure = child.failure}, true, .None
	case .Unavailable, .Verified:
		if effect == .May_Have_Started {
			return {lifecycle = .Indeterminate, outcome = .Indeterminate, failure = child.failure}, true, .None
		}
		return {lifecycle = .Failed, outcome = .Known_Failure, failure = child.failure}, true, .None
	}
	return {}, false, .Invalid_Request
}

/* ksawery_process_coordinator_record returns one retained immutable record handle for read-only use. */
ksawery_process_coordinator_record :: proc(
	coordinator: ^Ksawery_Process_Coordinator,
	index: u32,
) -> (^ksawery.Process_Record, bool) {
	if coordinator == nil || index >= coordinator.record_count do return nil, false
	return &coordinator.records[int(index)], true
}

/* ksawery_process_coordinator_detach_child clears only the exact active child association. */
ksawery_process_coordinator_detach_child :: proc(
	coordinator: ^Ksawery_Process_Coordinator,
	association: ksawery.Repository_Process_Association,
) -> bool {
	if coordinator == nil || !coordinator.child_attached || association != coordinator.child_association {
		return false
	}
	coordinator.child_association = {}
	coordinator.child_attached = false
	return true
}

/* ksawery_process_coordinator_usage reports aggregate bounded retained-record ownership. */
ksawery_process_coordinator_usage :: proc(
	coordinator: ^Ksawery_Process_Coordinator,
) -> (Ksawery_Process_Coordinator_Usage, bool) {
	if coordinator == nil || coordinator.allocator.procedure == nil do return {}, false
	usage := Ksawery_Process_Coordinator_Usage {
		records = coordinator.record_count,
		active_operations = coordinator.active ? 1 : 0,
		active_children = coordinator.child_attached ? 1 : 0,
	}
	for index in 0 ..< int(coordinator.record_count) {
		record_usage, measured := ksawery.process_record_usage(&coordinator.records[index])
		if !measured do return {}, false
		usage.retained_bytes += record_usage.retained_bytes
		usage.output_bytes += record_usage.output_bytes
		usage.diagnostic_bytes += record_usage.diagnostic_bytes
	}
	return usage, true
}

/* ksawery_process_coordinator_close releases every retained record and active association. */
ksawery_process_coordinator_close :: proc(coordinator: ^Ksawery_Process_Coordinator) {
	if coordinator == nil do return
	for index in 0 ..< int(coordinator.record_count) {
		ksawery.process_record_close(&coordinator.records[index])
	}
	coordinator^ = {}
}

@(private)
ksawery_process_coordinator_retained_bytes :: proc(coordinator: ^Ksawery_Process_Coordinator) -> u64 {
	if coordinator == nil do return 0
	retained_bytes: u64
	for index in 0 ..< int(coordinator.record_count) {
		usage, measured := ksawery.process_record_usage(&coordinator.records[index])
		if measured do retained_bytes += usage.retained_bytes
	}
	return retained_bytes
}

@(private)
ksawery_process_coordinator_evict_oldest :: proc(coordinator: ^Ksawery_Process_Coordinator) {
	if coordinator == nil || coordinator.record_count == 0 do return
	ksawery.process_record_close(&coordinator.records[0])
	for index in 1 ..< int(coordinator.record_count) {
		coordinator.records[index - 1] = coordinator.records[index]
	}
	coordinator.record_count -= 1
	coordinator.records[int(coordinator.record_count)] = {}
}

@(private)
ksawery_process_operation_may_mutate :: proc(kind: ksawery.Repository_Operation_Kind) -> bool {
	switch kind {
	case .Stage, .Unstage, .Discard, .Commit, .Amend, .Fixup, .Fetch, .Push,
	     .Create_Branch, .Switch_Branch, .Rename_Branch, .Delete_Branch,
	     .Create_Tag, .Delete_Tag, .Merge, .Continue_Merge, .Abort_Merge,
	     .Rebase, .Continue_Rebase, .Skip_Rebase, .Abort_Rebase,
	     .Cherry_Pick, .Continue_Cherry_Pick, .Skip_Cherry_Pick, .Abort_Cherry_Pick,
	     .Revert, .Continue_Revert, .Skip_Revert, .Abort_Revert,
	     .Bisect, .Bisect_Good, .Bisect_Bad, .Bisect_Skip, .Bisect_Reset,
	     .Resolve_Conflict, .Stash, .Worktree, .External_Operation, .Raw_Command:
		return true
	case .Status, .Sequence, .History, .Refs, .Revision_Detail, .Revision_Range, .Path_Detail,
	     .Blame, .Reflog, .Invalid:
		return false
	}
	return false
}

@(private)
ksawery_process_phase_transition_is_valid :: proc(
	previous: ksawery.Repository_Process_Phase,
	next: ksawery.Repository_Process_Phase,
	lifecycle: ksawery.Repository_Process_Lifecycle,
) -> bool {
	if ksawery.repository_process_lifecycle_is_terminal(lifecycle) {
		return next == previous || next == .Verifying || next == .Cleaning_Up
	}
	if lifecycle == .Cancellation_Requested {
		switch previous {
		case .Cancelling:
			return next == .Cancelling || next == .Refreshing
		case .Refreshing:
			return next == .Refreshing || next == .Verifying || next == .Cancelling
		case .Verifying:
			return next == .Verifying || next == .Cancelling || next == .Cleaning_Up
		case .Checking, .Executing:
			return next == .Cancelling
		case .Cleaning_Up, .Invalid:
			return false
		}
	}
	switch previous {
	case .Checking:
		return next == .Checking || next == .Executing || next == .Cancelling
	case .Executing:
		return next == .Executing || next == .Refreshing || next == .Verifying || next == .Cancelling
	case .Refreshing:
		return next == .Refreshing || next == .Verifying || next == .Cancelling
	case .Verifying:
		return next == .Verifying || next == .Cancelling || next == .Cleaning_Up
	case .Cancelling:
		return next == .Cancelling || next == .Refreshing || next == .Cleaning_Up
	case .Cleaning_Up:
		return next == .Cleaning_Up
	case .Invalid:
		return false
	}
	return false
}

@(private)
ksawery_process_verification_is_valid :: proc(
	coordinator: ^Ksawery_Process_Coordinator,
	verification: Ksawery_Repository_Verification,
) -> bool {
	if coordinator == nil || verification.state == .Unavailable {
		return verification.refresh_attempted && verification.refreshed_generation == ksawery.Observation_Generation(0)
	}
	if verification.refreshed_generation == ksawery.Observation_Generation(0) do return false
	if ksawery_process_operation_may_mutate(coordinator.active_authority.kind) {
		return verification.refresh_attempted &&
		       verification.refreshed_generation == coordinator.confirmed_observation &&
		       verification.refreshed_generation > verification.admitted_generation &&
		       !coordinator.observation_stale
	}
	return verification.refreshed_generation == coordinator.confirmed_observation &&
	       verification.refreshed_generation >= verification.admitted_generation
}
