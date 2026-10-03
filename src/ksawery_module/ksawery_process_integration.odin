// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery_module

import ksawery "../ksawery"

/* Ksawery_Process_Observation describes one safe read-only operation record. */
Ksawery_Process_Observation :: struct {
	kind:         ksawery.Repository_Operation_Kind,
	target_kind:  ksawery.Process_Target_Kind,
	title:        string,
	target:       string,
	phase_detail: string,
	refreshing:   bool,
	checking:     bool,
}

/* ksawery_process_observation_path_text resolves one exact checked path target. */
ksawery_process_observation_path_text :: proc(
	observation: ^ksawery.Status_Observation,
	target: ksawery.Path_Target,
) -> ([]u8, bool) {
	descriptor, described := ksawery.status_observation_descriptor(observation)
	if !described || descriptor.generation != target.generation do return nil, false
	for index in 0 ..< descriptor.path_count {
		path, found := ksawery.status_observation_path(observation, index)
		if !found || path.id != target.path do continue
		return ksawery.status_observation_path_text(observation, path)
	}
	return nil, false
}

/* ksawery_process_observation_begin admits and associates one started read-only child. */
ksawery_process_observation_begin :: proc(
	coordinator: ^Ksawery_Process_Coordinator,
	process: ^ksawery.Repository_Process,
	observation_generation: ksawery.Observation_Generation,
	description: Ksawery_Process_Observation,
	now_ns: i64,
) -> (bool, ksawery.Failure_Code) {
	if coordinator == nil || process == nil || process.state == nil || now_ns < 0 ||
	   description.kind == .Invalid || description.target_kind == .None ||
	   len(description.title) == 0 || len(description.target) == 0 {
		return false, .Invalid_Request
	}
	current, current_failure := ksawery_process_coordinator_command_is_current(
		coordinator,
		coordinator.repository,
		observation_generation,
	)
	if !current do return false, current_failure
	admitted_phase := ksawery.Repository_Process_Phase.Checking
	if description.refreshing do admitted_phase = .Executing
	proposal := ksawery.Process_Record_Proposal {
		lifecycle = .Admitted,
		phase = admitted_phase,
		target_kind = description.target_kind,
		title = description.title,
		target = description.target,
		phase_detail = "Checking repository",
		progress = {kind = .Phase},
		timing = {
			admitted_ns = now_ns,
			started_ns = now_ns,
			updated_ns = now_ns,
		},
		action_count = 1,
	}
	proposal.actions[0] = {kind = .Inspect, available = true}
	_, admitted, admit_failure := ksawery_process_coordinator_admit(
		coordinator,
		observation_generation,
		description.kind,
		proposal,
	)
	if !admitted do return false, admit_failure
	attached, attach_failure := ksawery_process_coordinator_attach_child(coordinator, process, now_ns)
	if !attached {
		_ = ksawery_process_observation_finish_without_child(
			coordinator,
			.Failed,
			.Known_Failure,
			"Repository observation could not be associated",
			now_ns,
		)
		return false, attach_failure
	}
	running := proposal
	running.lifecycle = .Running
	running.phase = .Checking if description.checking else
	                .Refreshing if description.refreshing else .Executing
	running.phase_detail = description.phase_detail
	running.actions = {}
	running.actions[0] = {kind = .Inspect, available = true}
	running.actions[1] = {kind = .Cancel, available = true}
	running.action_count = 2
	published, publish_failure := ksawery_process_coordinator_publish(coordinator, process, running)
	if !published {
		view, described := ksawery.repository_process_lifecycle_view(process)
		if described do _ = ksawery_process_coordinator_detach_child(coordinator, view.association)
		_ = ksawery_process_observation_finish_without_child(
			coordinator,
			.Failed,
			.Known_Failure,
			"Repository observation could not be recorded",
			now_ns,
		)
		return false, publish_failure
	}
	return true, .None
}

/* ksawery_process_observation_replace_child advances one multi-child read-only operation. */
ksawery_process_observation_replace_child :: proc(
	coordinator: ^Ksawery_Process_Coordinator,
	completed: ^ksawery.Repository_Process,
	next: ^ksawery.Repository_Process,
	phase_detail: string,
	now_ns: i64,
) -> (bool, ksawery.Failure_Code) {
	if coordinator == nil || completed == nil || next == nil || next.state == nil ||
	   len(phase_detail) == 0 || now_ns < 0 {
		return false, .Invalid_Request
	}
	completed_view, described := ksawery.repository_process_lifecycle_view(completed)
	if !described || completed_view.owner_state != .Completed ||
	   !ksawery_process_coordinator_detach_child(coordinator, completed_view.association) {
		return false, .Stale_Observation
	}
	attached, attach_failure := ksawery_process_coordinator_attach_child(coordinator, next, now_ns)
	if !attached {
		_ = ksawery_process_observation_finish_without_child(
			coordinator,
			.Failed,
			.Known_Failure,
			"Repository observation child could not start",
			now_ns,
		)
		return false, attach_failure
	}
	proposal, prepared := ksawery_process_observation_current_proposal(coordinator, now_ns)
	if !prepared do return false, .Cleanup
	proposal.lifecycle = .Running
	proposal.phase = .Executing
	proposal.phase_detail = phase_detail
	proposal.actions = {}
	proposal.actions[0] = {kind = .Inspect, available = true}
	proposal.actions[1] = {kind = .Cancel, available = true}
	proposal.action_count = 2
	published, publish_failure := ksawery_process_coordinator_publish(coordinator, next, proposal)
	if !published {
		view, view_described := ksawery.repository_process_lifecycle_view(next)
		if view_described do _ = ksawery_process_coordinator_detach_child(coordinator, view.association)
		_ = ksawery_process_observation_finish_without_child(
			coordinator,
			.Failed,
			.Known_Failure,
			"Repository observation child could not be recorded",
			now_ns,
		)
		return false, publish_failure
	}
	return true, .None
}

/* ksawery_process_observation_confirm_refresh advances Status observation authority. */
ksawery_process_observation_confirm_refresh :: proc(
	coordinator: ^Ksawery_Process_Coordinator,
	generation: ksawery.Observation_Generation,
) -> (bool, ksawery.Failure_Code) {
	if coordinator == nil do return false, .Invalid_Request
	return ksawery_process_coordinator_confirm_refresh(
		coordinator,
		coordinator.repository,
		generation,
	)
}

/* ksawery_process_operation_publish_phase advances one active child or childless operation phase. */
ksawery_process_operation_publish_phase :: proc(
	coordinator: ^Ksawery_Process_Coordinator,
	process: ^ksawery.Repository_Process,
	phase: ksawery.Repository_Process_Phase,
	phase_detail: string,
	cancellable: bool,
	now_ns: i64,
) -> (bool, ksawery.Failure_Code) {
	if coordinator == nil || phase == .Invalid || len(phase_detail) == 0 do return false, .Invalid_Request
	proposal, prepared := ksawery_process_observation_current_proposal(coordinator, now_ns)
	if !prepared do return false, .Cleanup
	if proposal.lifecycle != .Cancellation_Requested do proposal.lifecycle = .Running
	proposal.phase = phase
	proposal.phase_detail = phase_detail
	proposal.actions = {}
	proposal.actions[0] = {kind = .Inspect, available = true}
	proposal.action_count = 1
	if cancellable {
		proposal.actions[1] = {kind = .Cancel, available = true}
		proposal.action_count = 2
	}
	return ksawery_process_coordinator_publish(coordinator, process, proposal)
}

/* ksawery_process_operation_detach_child releases the exact completed child association. */
ksawery_process_operation_detach_child :: proc(
	coordinator: ^Ksawery_Process_Coordinator,
	process: ^ksawery.Repository_Process,
) -> (bool, ksawery.Failure_Code) {
	if coordinator == nil || process == nil do return false, .Invalid_Request
	view, described := ksawery.repository_process_lifecycle_view(process)
	if !described || !ksawery_process_coordinator_detach_child(coordinator, view.association) {
		return false, .Stale_Observation
	}
	return true, .None
}

/* ksawery_process_operation_attach_child associates a later child without replacing the public phase. */
ksawery_process_operation_attach_child :: proc(
	coordinator: ^Ksawery_Process_Coordinator,
	process: ^ksawery.Repository_Process,
	now_ns: i64,
) -> (bool, ksawery.Failure_Code) {
	return ksawery_process_coordinator_attach_child(coordinator, process, now_ns)
}

/* ksawery_process_operation_prepare_refresh preserves effect evidence at the refresh generation. */
ksawery_process_operation_prepare_refresh :: proc(
	coordinator: ^Ksawery_Process_Coordinator,
	process: ^ksawery.Repository_Process,
	phase_detail: string,
	now_ns: i64,
) -> (ksawery.Repository_Process_Lifecycle_View, bool, ksawery.Failure_Code) {
	published, publish_failure := ksawery_process_operation_publish_phase(
		coordinator,
		process,
		.Refreshing,
		phase_detail,
		false,
		now_ns,
	)
	if !published do return {}, false, publish_failure
	view, described := ksawery.repository_process_lifecycle_view(process)
	if !described || (view.owner_state != .Completed && view.owner_state != .Failed) {
		return {}, false, .Cleanup
	}
	if !ksawery_process_coordinator_detach_child(coordinator, view.association) {
		return {}, false, .Stale_Observation
	}
	return view, true, .None
}

/* ksawery_process_operation_resolve derives one mutation outcome from child and refreshed truth. */
ksawery_process_operation_resolve :: proc(
	coordinator: ^Ksawery_Process_Coordinator,
	effect: ksawery.Repository_Process_Lifecycle_View,
	state: Ksawery_Repository_Verification_State,
	refreshed_generation: ksawery.Observation_Generation,
	refresh_attempted: bool,
) -> (Ksawery_Process_Resolution, bool, ksawery.Failure_Code) {
	if coordinator == nil do return {}, false, .Invalid_Request
	return ksawery_process_coordinator_resolve_outcome(
		coordinator,
		effect,
		{
			operation = coordinator.active_authority.operation,
			repository = coordinator.repository,
			admitted_generation = coordinator.active_authority.observation_generation,
			refreshed_generation = refreshed_generation,
			state = state,
			refresh_attempted = refresh_attempted,
		},
	)
}

/* ksawery_process_operation_finish_resolution publishes one already resolved mutation outcome. */
ksawery_process_operation_finish_resolution :: proc(
	coordinator: ^Ksawery_Process_Coordinator,
	process: ^ksawery.Repository_Process,
	resolution: Ksawery_Process_Resolution,
	message: string,
	now_ns: i64,
) -> (bool, ksawery.Failure_Code) {
	if coordinator == nil || len(message) == 0 ||
	   !ksawery.repository_process_lifecycle_is_terminal(resolution.lifecycle) {
		return false, .Invalid_Request
	}
	proposal, prepared := ksawery_process_observation_current_proposal(coordinator, now_ns)
	if !prepared do return false, .Cleanup
	proposal.lifecycle = resolution.lifecycle
	proposal.outcome = resolution.outcome
	proposal.message = message
	proposal.timing.finished_ns = now_ns
	proposal.actions = {}
	proposal.actions[0] = {kind = .Inspect, available = true}
	proposal.actions[1] = {kind = .Clear, available = true}
	proposal.action_count = 2
	if process != nil {
		view, described := ksawery.repository_process_lifecycle_view(process)
		if !described do return false, .Cleanup
		proposal.output_truncated = view.output_truncated
		proposal.diagnostic_truncated = view.diagnostic_truncated
		proposal.exit_status = view.child.exit_status
		proposal.exit_status_available = view.child.exit_status_available
	}
	published, publish_failure := ksawery_process_coordinator_publish(coordinator, process, proposal)
	if !published do return false, publish_failure
	if process != nil {
		terminal_view, described := ksawery.repository_process_lifecycle_view(process)
		if !described || !ksawery_process_coordinator_detach_child(coordinator, terminal_view.association) {
			return false, .Cleanup
		}
	}
	return true, .None
}

/* ksawery_process_observation_finish publishes one terminal read-only child outcome. */
ksawery_process_observation_finish :: proc(
	coordinator: ^Ksawery_Process_Coordinator,
	process: ^ksawery.Repository_Process,
	succeeded: bool,
	message: string,
	now_ns: i64,
) -> (bool, ksawery.Failure_Code) {
	if coordinator == nil || process == nil || len(message) == 0 || now_ns < 0 {
		return false, .Invalid_Request
	}
	view, described := ksawery.repository_process_lifecycle_view(process)
	if !described || (view.owner_state != .Completed && view.owner_state != .Failed) {
		return false, .Invalid_Request
	}
	lifecycle := ksawery.Repository_Process_Lifecycle.Succeeded
	outcome := ksawery.Repository_Process_Outcome.Verified_Success
	if !succeeded {
		lifecycle = .Failed
		outcome = .Known_Failure
		if view.termination.reason == .Cancellation {
			lifecycle = .Cancelled
			outcome = .Cancelled_Before_Effect
		} else if view.termination.reason == .Timeout {
			lifecycle = .Timed_Out
			outcome = .Timed_Out_Before_Effect
		} else if view.child.state == .Uncertain ||
		          view.failure_evidence.stage == .Reap || view.failure_evidence.stage == .Cleanup ||
		          view.failure_evidence.secondary_stage == .Reap ||
		          view.failure_evidence.secondary_stage == .Cleanup {
			lifecycle = .Indeterminate
			outcome = .Indeterminate
		}
	}
	proposal, prepared := ksawery_process_observation_current_proposal(coordinator, now_ns)
	if !prepared do return false, .Cleanup
	proposal.lifecycle = lifecycle
	proposal.outcome = outcome
	proposal.message = message
	proposal.timing.finished_ns = now_ns
	proposal.actions = {}
	proposal.actions[0] = {kind = .Inspect, available = true}
	proposal.actions[1] = {kind = .Clear, available = true}
	proposal.action_count = 2
	proposal.output_truncated = view.output_truncated
	proposal.diagnostic_truncated = view.diagnostic_truncated
	proposal.exit_status = view.child.exit_status
	proposal.exit_status_available = view.child.exit_status_available
	published, publish_failure := ksawery_process_coordinator_publish(coordinator, process, proposal)
	if !published do return false, publish_failure
	terminal_view, terminal_described := ksawery.repository_process_lifecycle_view(process)
	if !terminal_described || !ksawery_process_coordinator_detach_child(
		coordinator,
		terminal_view.association,
	) {
		return false, .Cleanup
	}
	return true, .None
}

/* ksawery_process_observation_finish_without_child closes a checked phase that started no child. */
ksawery_process_observation_finish_without_child :: proc(
	coordinator: ^Ksawery_Process_Coordinator,
	lifecycle: ksawery.Repository_Process_Lifecycle,
	outcome: ksawery.Repository_Process_Outcome,
	message: string,
	now_ns: i64,
) -> bool {
	if coordinator == nil || len(message) == 0 || !ksawery.repository_process_lifecycle_is_terminal(lifecycle) {
		return false
	}
	proposal, prepared := ksawery_process_observation_current_proposal(coordinator, now_ns)
	if !prepared do return false
	proposal.lifecycle = lifecycle
	proposal.outcome = outcome
	proposal.message = message
	proposal.timing.finished_ns = now_ns
	proposal.actions = {}
	proposal.actions[0] = {kind = .Inspect, available = true}
	proposal.actions[1] = {kind = .Clear, available = true}
	proposal.action_count = 2
	published, _ := ksawery_process_coordinator_publish(coordinator, nil, proposal)
	return published
}

/* ksawery_process_observation_note_cancellation publishes one exact cancellation request. */
ksawery_process_observation_note_cancellation :: proc(
	coordinator: ^Ksawery_Process_Coordinator,
	process: ^ksawery.Repository_Process,
	now_ns: i64,
) -> (bool, ksawery.Failure_Code) {
	proposal, prepared := ksawery_process_observation_current_proposal(coordinator, now_ns)
	if !prepared do return false, .Cleanup
	proposal.lifecycle = .Cancellation_Requested
	proposal.phase = .Cancelling
	proposal.phase_detail = "Cancelling repository operation"
	proposal.actions = {}
	proposal.actions[0] = {kind = .Inspect, available = true}
	proposal.action_count = 1
	return ksawery_process_coordinator_publish(coordinator, process, proposal)
}

@(private)
ksawery_process_observation_current_proposal :: proc(
	coordinator: ^Ksawery_Process_Coordinator,
	now_ns: i64,
) -> (ksawery.Process_Record_Proposal, bool) {
	if coordinator == nil || !coordinator.active || coordinator.record_count == 0 || now_ns < 0 {
		return {}, false
	}
	record := &coordinator.records[int(coordinator.record_count - 1)]
	descriptor, described := ksawery.process_record_descriptor(record)
	if !described || now_ns < descriptor.timing.updated_ns do return {}, false
	title, titled := ksawery.process_record_text(record, descriptor.title)
	target, targeted := ksawery.process_record_text(record, descriptor.target)
	phase_detail, phased := ksawery.process_record_text(record, descriptor.phase_detail)
	if !titled || !targeted || !phased do return {}, false
	return ksawery.Process_Record_Proposal {
		lifecycle = descriptor.lifecycle,
		phase = descriptor.phase,
		outcome = descriptor.outcome,
		target_kind = descriptor.target_kind,
		title = string(title),
		target = string(target),
		phase_detail = string(phase_detail),
		progress = descriptor.progress,
		timing = {
			admitted_ns = descriptor.timing.admitted_ns,
			started_ns = descriptor.timing.started_ns,
			updated_ns = now_ns,
			elapsed_ns = now_ns - descriptor.timing.admitted_ns,
		},
	}, true
}
