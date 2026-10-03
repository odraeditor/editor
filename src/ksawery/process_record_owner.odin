// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery

import "base:runtime"
import "core:unicode/utf8"

/* Process_Record_Authority identifies the exact source allowed to publish one operation chain. */
Process_Record_Authority :: struct {
	operation:              Repository_Operation_ID,
	repository:             Repository_Context,
	observation_generation: Observation_Generation,
	kind:                   Repository_Operation_Kind,
}

@(private)
Process_Record_Data :: struct {
	descriptor: Process_Record_Descriptor,
	storage:    [dynamic]u8,
	usage:      Process_Record_Usage,
	allocator:  runtime.Allocator,
}

/* process_record_open validates and copies the first immutable operation generation. */
process_record_open :: proc(
	authority: Process_Record_Authority,
	proposal: Process_Record_Proposal,
	limits := DEFAULT_PROCESS_RECORD_LIMITS,
	allocator := context.allocator,
) -> (Process_Record, bool, Failure_Code) {
	return process_record_copy(authority, nil, proposal, limits, allocator)
}

/* process_record_replace atomically publishes a newer generation or preserves the current record. */
process_record_replace :: proc(
	record: ^Process_Record,
	authority: Process_Record_Authority,
	proposal: Process_Record_Proposal,
	limits := DEFAULT_PROCESS_RECORD_LIMITS,
	allocator := context.allocator,
) -> (bool, Failure_Code) {
	state := process_record_data(record)
	if state == nil do return false, .Invalid_Request
	next, opened, failure := process_record_copy(authority, &state.descriptor, proposal, limits, allocator)
	if !opened do return false, failure
	previous := record^
	record^ = next
	process_record_close(&previous)
	return true, .None
}

/* process_record_descriptor returns copied semantic metadata for one immutable generation. */
process_record_descriptor :: proc(record: ^Process_Record) -> (Process_Record_Descriptor, bool) {
	state := process_record_data(record)
	if state == nil do return {}, false
	return state.descriptor, true
}

/* process_record_text returns borrowed copied public content for one checked record reference. */
process_record_text :: proc(record: ^Process_Record, reference: Process_Text_Ref) -> ([]u8, bool) {
	state := process_record_data(record)
	end := u64(reference.offset) + u64(reference.length)
	if state == nil || end > u64(len(state.storage)) do return nil, false
	return state.storage[int(reference.offset):int(end)], true
}

/* process_record_usage reports exact owned resources for one immutable generation. */
process_record_usage :: proc(record: ^Process_Record) -> (Process_Record_Usage, bool) {
	state := process_record_data(record)
	if state == nil do return {}, false
	return state.usage, true
}

/* process_record_close releases every allocation owned by one immutable generation. */
process_record_close :: proc(record: ^Process_Record) {
	state := process_record_data(record)
	if state == nil do return
	if state.storage != nil do delete(state.storage)
	allocator := state.allocator
	free(state, allocator)
	record^ = {}
}

@(private)
process_record_copy :: proc(
	authority: Process_Record_Authority,
	previous: ^Process_Record_Descriptor,
	proposal: Process_Record_Proposal,
	limits: Process_Record_Limits,
	allocator: runtime.Allocator,
) -> (Process_Record, bool, Failure_Code) {
	if allocator.procedure == nil || !process_record_limits_are_valid(limits) {
		return {}, false, .Invalid_Request
	}
	if failure := process_record_proposal_failure(authority, previous, proposal, limits); failure != .None {
		return {}, false, failure
	}
	storage_bytes := process_record_proposal_storage_bytes(proposal)
	retained_bytes := u64(size_of(Process_Record_Data)) + storage_bytes
	if retained_bytes > limits.retained_bytes || storage_bytes > limits.temporary_bytes {
		return {}, false, .Process_Record_Limit
	}
	state, allocation_error := new(Process_Record_Data, allocator)
	if allocation_error != nil do return {}, false, .Allocation
	state.allocator = allocator
	state.storage, allocation_error = make([dynamic]u8, 0, int(storage_bytes), allocator)
	if allocation_error != nil {
		free(state, allocator)
		return {}, false, .Allocation
	}
	state.descriptor = Process_Record_Descriptor {
		operation = proposal.operation,
		generation = proposal.generation,
		repository = proposal.repository,
		observation_generation = proposal.observation_generation,
		kind = proposal.kind,
		lifecycle = proposal.lifecycle,
		phase = proposal.phase,
		outcome = proposal.outcome,
		target_kind = proposal.target_kind,
		progress = proposal.progress,
		timing = proposal.timing,
		action_count = proposal.action_count,
	}
	state.descriptor.title, allocation_error = process_record_append(&state.storage, transmute([]u8)proposal.title)
	if allocation_error == nil do state.descriptor.target, allocation_error = process_record_append(&state.storage, transmute([]u8)proposal.target)
	if allocation_error == nil do state.descriptor.phase_detail, allocation_error = process_record_append(&state.storage, transmute([]u8)proposal.phase_detail)
	if allocation_error == nil do state.descriptor.message, allocation_error = process_record_append(&state.storage, transmute([]u8)proposal.message)
	if allocation_error == nil do state.descriptor.content.output, allocation_error = process_record_append(&state.storage, proposal.output)
	if allocation_error == nil do state.descriptor.content.diagnostic, allocation_error = process_record_append(&state.storage, proposal.diagnostic)
	if allocation_error != nil {
		if state.storage != nil do delete(state.storage)
		free(state, allocator)
		return {}, false, .Allocation
	}
	state.descriptor.content.output_truncated = proposal.output_truncated
	state.descriptor.content.diagnostic_truncated = proposal.diagnostic_truncated
	state.descriptor.content.exit_status = proposal.exit_status
	state.descriptor.content.exit_status_available = proposal.exit_status_available
	for index in 0 ..< int(proposal.action_count) {
		action := proposal.actions[index]
		state.descriptor.actions[index] = Process_Action_Descriptor {
			kind = action.kind,
			operation = proposal.operation,
			generation = proposal.generation,
			available = action.available,
		}
	}
	state.usage = Process_Record_Usage {
		records = 1,
		retained_bytes = u64(size_of(Process_Record_Data)) + u64(cap(state.storage)),
		output_bytes = u64(len(proposal.output)),
		diagnostic_bytes = u64(len(proposal.diagnostic)),
		active_operations = 0 if repository_process_lifecycle_is_terminal(proposal.lifecycle) else 1,
	}
	return Process_Record{state = state}, true, .None
}

@(private)
process_record_proposal_failure :: proc(
	authority: Process_Record_Authority,
	previous: ^Process_Record_Descriptor,
	proposal: Process_Record_Proposal,
	limits: Process_Record_Limits,
) -> Failure_Code {
	if !process_record_authority_is_valid(authority) ||
	   proposal.operation == Repository_Operation_ID(0) ||
	   proposal.generation == Process_Record_Generation(0) ||
	   !repository_context_is_valid(proposal.repository) ||
	   proposal.observation_generation == Observation_Generation(0) ||
	   proposal.kind == .Invalid || proposal.lifecycle == .Invalid || proposal.phase == .Invalid {
		return .Invalid_Request
	}
	if proposal.operation != authority.operation || proposal.repository != authority.repository ||
	   proposal.observation_generation != authority.observation_generation || proposal.kind != authority.kind {
		return .Stale_Observation
	}
	if previous == nil {
		if proposal.generation != Process_Record_Generation(1) || proposal.lifecycle != .Admitted {
			return .Process_Record_Stale
		}
	} else {
		if previous.operation != authority.operation || previous.repository != authority.repository ||
		   previous.observation_generation != authority.observation_generation || previous.kind != authority.kind {
			return .Stale_Observation
		}
		if repository_process_lifecycle_is_terminal(previous.lifecycle) do return .Process_Record_Closed
		if proposal.generation <= previous.generation do return .Process_Record_Stale
		if !process_record_transition_is_valid(previous.lifecycle, proposal.lifecycle) do return .Invalid_Request
		if proposal.timing.admitted_ns != previous.timing.admitted_ns ||
		   proposal.timing.started_ns != previous.timing.started_ns ||
		   proposal.timing.updated_ns < previous.timing.updated_ns {
			return .Process_Record_Stale
		}
	}
	if !process_record_outcome_is_valid(proposal.lifecycle, proposal.outcome) ||
	   !process_record_progress_is_valid(proposal.progress) ||
	   !process_record_timing_is_valid(proposal.timing, proposal.lifecycle) ||
	   !process_record_actions_are_valid(proposal) {
		return .Invalid_Request
	}
	if len(proposal.title) == 0 || u32(len(proposal.title)) > limits.title_bytes ||
	   len(proposal.target) == 0 || u32(len(proposal.target)) > limits.target_bytes ||
	   u32(len(proposal.phase_detail)) > limits.phase_bytes ||
	   u32(len(proposal.message)) > limits.message_bytes ||
	   u64(len(proposal.output)) > limits.child.stdout_bytes ||
	   u64(len(proposal.diagnostic)) > limits.child.diagnostic_bytes {
		return .Process_Record_Limit
	}
	if proposal.target_kind == .None ||
	   (repository_process_lifecycle_is_terminal(proposal.lifecycle) && len(proposal.message) == 0) {
		return .Invalid_Request
	}
	if !process_public_content_is_valid(transmute([]u8)proposal.title) ||
	   !process_public_content_is_valid(transmute([]u8)proposal.target) ||
	   !process_public_content_is_valid(transmute([]u8)proposal.phase_detail) ||
	   !process_public_content_is_valid(transmute([]u8)proposal.message) ||
	   !process_public_content_is_valid(proposal.output) ||
	   !process_public_content_is_valid(proposal.diagnostic) {
		return .Sensitive_Content
	}
	storage_bytes := process_record_proposal_storage_bytes(proposal)
	if storage_bytes > limits.retained_bytes || storage_bytes > limits.temporary_bytes {
		return .Process_Record_Limit
	}
	return .None
}

@(private)
process_record_authority_is_valid :: proc(authority: Process_Record_Authority) -> bool {
	return authority.operation != Repository_Operation_ID(0) &&
	       repository_context_is_valid(authority.repository) &&
	       authority.observation_generation != Observation_Generation(0) &&
	       authority.kind != .Invalid
}

@(private)
process_record_transition_is_valid :: proc(
	previous: Repository_Process_Lifecycle,
	next: Repository_Process_Lifecycle,
) -> bool {
	switch previous {
	case .Admitted:
		return next == .Running
	case .Running:
		return next == .Running || next == .Cancellation_Requested ||
		       repository_process_lifecycle_is_terminal(next)
	case .Cancellation_Requested:
		return next == .Cancellation_Requested || next == .Failed || next == .Cancelled ||
		       next == .Timed_Out || next == .Indeterminate
	case .Invalid, .Succeeded, .Failed, .Cancelled, .Timed_Out, .Indeterminate:
		return false
	}
	return false
}

@(private)
process_record_outcome_is_valid :: proc(
	lifecycle: Repository_Process_Lifecycle,
	outcome: Repository_Process_Outcome,
) -> bool {
	switch lifecycle {
	case .Admitted, .Running, .Cancellation_Requested:
		return outcome == .None
	case .Succeeded:
		return outcome == .Verified_Success
	case .Failed:
		return outcome == .Known_Failure || outcome == .Verification_Mismatch
	case .Cancelled:
		return outcome == .Cancelled_Before_Effect || outcome == .Cancelled_After_Possible_Effect
	case .Timed_Out:
		return outcome == .Timed_Out_Before_Effect || outcome == .Timed_Out_After_Possible_Effect
	case .Indeterminate:
		return outcome == .Indeterminate
	case .Invalid:
		return false
	}
	return false
}

@(private)
process_record_progress_is_valid :: proc(progress: Process_Progress) -> bool {
	switch progress.kind {
	case .None, .Phase:
		return progress.current == 0 && progress.total == 0
	case .Determinate:
		return progress.total > 0 && progress.current <= progress.total
	}
	return false
}

@(private)
process_record_timing_is_valid :: proc(
	timing: Process_Record_Timing,
	lifecycle: Repository_Process_Lifecycle,
) -> bool {
	if timing.admitted_ns < 0 || timing.started_ns < timing.admitted_ns ||
	   timing.updated_ns < timing.started_ns {
		return false
	}
	if repository_process_lifecycle_is_terminal(lifecycle) {
		return timing.finished_ns >= timing.updated_ns && timing.elapsed_ns == timing.finished_ns - timing.admitted_ns
	}
	return timing.finished_ns == 0 && timing.elapsed_ns == timing.updated_ns - timing.admitted_ns
}

@(private)
process_record_actions_are_valid :: proc(proposal: Process_Record_Proposal) -> bool {
	if proposal.action_count > MAX_PROCESS_ACTIONS do return false
	seen: [MAX_PROCESS_ACTIONS + 1]bool
	for index in 0 ..< int(proposal.action_count) {
		action := proposal.actions[index]
		ordinal := int(action.kind)
		if action.kind == .Invalid || ordinal >= len(seen) || seen[ordinal] || !action.available {
			return false
		}
		seen[ordinal] = true
		switch action.kind {
		case .Inspect:
		case .Cancel:
			if proposal.lifecycle != .Running do return false
		case .Clear:
			if !repository_process_lifecycle_is_terminal(proposal.lifecycle) do return false
		case .Invalid:
			return false
		}
	}
	return true
}

@(private)
process_public_content_is_valid :: proc(content: []u8) -> bool {
	if !utf8.valid_string(string(content)) do return false
	for value in content {
		if value == 0x1b || value == 0x7f || value == 0x9b ||
		   (value < 0x20 && value != '\n' && value != '\r' && value != '\t') {
			return false
		}
	}
	sensitive := [?]string {
		"://",
		"authorization:",
		"proxy-authorization:",
		"bearer ",
		"password=",
		"passwd=",
		"token=",
		"secret=",
		"api_key=",
		"apikey=",
		"oauth",
		"git_askpass",
		"ssh_askpass",
		"credential.helper",
	}
	for marker in sensitive {
		if process_ascii_contains_fold(content, marker) do return false
	}
	return true
}

@(private)
process_ascii_contains_fold :: proc(content: []u8, marker: string) -> bool {
	if len(marker) == 0 || len(content) < len(marker) do return false
	for start in 0 ..< len(content) - len(marker) + 1 {
		matched := true
		for index in 0 ..< len(marker) {
			value := content[start + index]
			if value >= 'A' && value <= 'Z' do value += 'a' - 'A'
			if value != marker[index] {
				matched = false
				break
			}
		}
		if matched do return true
	}
	return false
}

@(private)
process_record_proposal_storage_bytes :: proc(proposal: Process_Record_Proposal) -> u64 {
	return u64(len(proposal.title)) + u64(len(proposal.target)) +
	       u64(len(proposal.phase_detail)) + u64(len(proposal.message)) +
	       u64(len(proposal.output)) + u64(len(proposal.diagnostic))
}

@(private)
process_record_append :: proc(
	storage: ^[dynamic]u8,
	content: []u8,
) -> (Process_Text_Ref, runtime.Allocator_Error) {
	if storage == nil do return {}, runtime.Allocator_Error{}
	reference := Process_Text_Ref{offset = u32(len(storage^)), length = u32(len(content))}
	if len(content) == 0 do return reference, nil
	_, allocation_error := append(storage, ..content)
	return reference, allocation_error
}

@(private)
process_record_data :: proc(record: ^Process_Record) -> ^Process_Record_Data {
	if record == nil || record.state == nil do return nil
	return cast(^Process_Record_Data)record.state
}
