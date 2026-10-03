// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery_module

import "../ksawery"

/* Ksawery_Extension_Operation_Workflow_Failure_Code classifies coordinator rejection. */
Ksawery_Extension_Operation_Workflow_Failure_Code :: enum u8 {
	None,
	Invalid_State,
	Decode_Rejected,
	Operation_Active,
	Authority_Rejected,
	Admission_Rejected,
	Process_Record_Rejected,
	Process_Evidence_Rejected,
	Refresh_Evidence_Rejected,
	Invalid_Result,
}

/* Ksawery_Extension_Operation_Workflow_Failure retains contract and Process evidence. */
Ksawery_Extension_Operation_Workflow_Failure :: struct {
	code:      Ksawery_Extension_Operation_Workflow_Failure_Code,
	extension: ksawery.Extension_Operation_Failure,
	provider:  ksawery.Extension_Failure,
	process:   ksawery.Failure_Code,
}

/* Ksawery_Extension_Operation_Refresh_Request names the mandatory core refresh set. */
Ksawery_Extension_Operation_Refresh_Request :: struct {
	request:               ksawery.Extension_Operation_Request_ID,
	repository:            ksawery.Repository_Context,
	admitted_generation:   ksawery.Repository_Generation,
	observations:          ksawery.Extension_Observation_Families,
}

/* Ksawery_Extension_Operation_Workflow owns one child and its terminal evidence. */
Ksawery_Extension_Operation_Workflow :: struct {
	process:               ksawery.Repository_Process,
	submission:            ksawery.Extension_Operation_Submission,
	plan:                  ksawery.Extension_Operation_Plan,
	terminal:              ksawery.Repository_Process_Lifecycle_View,
	public_diagnostic_bytes: u64,
	result:                ksawery.Extension_Operation_Result,
	published_output_bytes: u64,
	published_diagnostic_bytes: u64,
	active:                bool,
	awaiting_refresh:      bool,
	result_available:      bool,
}

/* ksawery_extension_operation_workflow_begin_encoded admits one authorized Racket plan. */
ksawery_extension_operation_workflow_begin_encoded :: proc(
	workflow: ^Ksawery_Extension_Operation_Workflow,
	coordinator: ^Ksawery_Process_Coordinator,
	registry: ^Ksawery_Extension_Provider_Registry,
	input: []u8,
	request: ksawery.Extension_Operation_Request_ID,
	capability: ksawery.Extension_Capability,
	current_scope: ksawery.Extension_Turn_Scope,
	current_thread: u64,
	elapsed_ns: i64,
	memory_bytes: u64,
	now_ns: i64,
) -> (bool, Ksawery_Extension_Operation_Workflow_Failure) {
	if workflow == nil || coordinator == nil || registry == nil || request == 0 ||
	   now_ns < 0 {
		return false, {code = .Invalid_State}
	}
	if workflow.active || coordinator.active || current_scope.active_operation {
		return false, {code = .Operation_Active}
	}
	arguments: [ksawery.MAX_EXTENSION_OPERATION_ARGUMENTS]ksawery.Extension_Operation_Argument
	plan, declaration, decoded := ksawery_extension_operation_decode(registry, input, &arguments)
	if !decoded {
		return false, {code = .Decode_Rejected}
	}
	if plan.effect != .Read_Only && !current_scope.mutation_available {
		return false, {code = .Admission_Rejected,
			extension = {code = .Contribution_Unavailable, plan = plan.plan}}
	}
	authorized, provider_failure := ksawery_extension_provider_authorize(
		registry,
		capability,
		current_scope,
		current_thread,
		.Submit_External_Operation,
		elapsed_ns,
		memory_bytes,
	)
	if !authorized {
		return false, {code = .Authority_Rejected, provider = provider_failure}
	}
	submission := ksawery.Extension_Operation_Submission {
		request = request,
		contributor = current_scope.contributor,
		contribution = plan.contribution,
		repository = current_scope.repository,
		repository_generation = current_scope.repository_generation,
	}
	return ksawery_extension_operation_workflow_begin(
		workflow,
		coordinator,
		submission,
		plan,
		declaration,
		current_scope.contributor,
		current_scope.repository,
		current_scope.repository_generation,
		now_ns,
	)
}

/* ksawery_extension_operation_workflow_begin admits one Process-owned plan. */
ksawery_extension_operation_workflow_begin :: proc(
	workflow: ^Ksawery_Extension_Operation_Workflow,
	coordinator: ^Ksawery_Process_Coordinator,
	submission: ksawery.Extension_Operation_Submission,
	plan: ksawery.Extension_Operation_Plan,
	declaration: ksawery.Contribution_Declaration,
	current_contributor: ksawery.Contributor_Handle,
	current_repository: ksawery.Repository_Context,
	current_repository_generation: ksawery.Repository_Generation,
	now_ns: i64,
) -> (bool, Ksawery_Extension_Operation_Workflow_Failure) {
	if workflow == nil || workflow.active || coordinator == nil || now_ns < 0 {
		return false, {code = .Invalid_State}
	}
	process, started, start_failure := ksawery.repository_process_start_extension_operation(
		submission,
		plan,
		declaration,
		current_contributor,
		current_repository,
		current_repository_generation,
		now_ns,
		coordinator.allocator,
	)
	if !started {
		return false, {code = .Admission_Rejected, extension = start_failure}
	}
	title_copy := plan.purpose
	repository_copy := submission.repository
	recorded, record_failure := ksawery_process_observation_begin(
		coordinator,
		&process,
		ksawery.Observation_Generation(submission.repository_generation),
		{
			kind = .External_Operation,
			target_kind = .Repository,
			title = string(title_copy.bytes[:title_copy.length]),
			target = ksawery.repository_context_string(&repository_copy),
			phase_detail = "Running declared external operation",
		},
		now_ns,
	)
	if !recorded {
		ksawery.repository_process_close(&process)
		return false, {code = .Process_Record_Rejected, process = record_failure}
	}
	workflow^ = {
		process = process,
		submission = submission,
		plan = plan,
		active = true,
	}
	workflow.plan.arguments = nil
	return true, {}
}

/* ksawery_extension_operation_workflow_poll publishes progress or requests refresh. */
ksawery_extension_operation_workflow_poll :: proc(
	workflow: ^Ksawery_Extension_Operation_Workflow,
	coordinator: ^Ksawery_Process_Coordinator,
	now_ns: i64,
) -> (
	Ksawery_Extension_Operation_Refresh_Request,
	bool,
	Ksawery_Extension_Operation_Workflow_Failure,
) {
	if workflow == nil || !workflow.active || coordinator == nil || now_ns < 0 {
		return {}, false, {code = .Invalid_State}
	}
	if workflow.awaiting_refresh {
		return ksawery_extension_operation_refresh_request(workflow), true, {}
	}
	poll, polled := ksawery.repository_process_poll(&workflow.process, now_ns)
	if !polled {
		return {}, false, {code = .Process_Evidence_Rejected, process = poll.failure}
	}
	_, _, view, output, diagnostic, viewed :=
		ksawery.repository_process_extension_operation_snapshot(&workflow.process)
	if !viewed {
		return {}, false, {code = .Process_Evidence_Rejected, process = .Cleanup}
	}
	terminal := poll.state == .Completed || poll.state == .Failed
	changed := u64(len(output)) != workflow.published_output_bytes ||
		u64(len(diagnostic)) != workflow.published_diagnostic_bytes ||
		view.output_truncated || view.diagnostic_truncated
	if changed || terminal {
		phase := ksawery.Repository_Process_Phase.Executing
		phase_detail := "Running declared external operation"
		cancellable := true
		if terminal {
			phase = .Refreshing
			phase_detail = "Refreshing declared repository observations"
			cancellable = false
		}
		published, publish_failure := ksawery_extension_operation_publish_process(
			workflow,
			coordinator,
			view,
			output,
			diagnostic,
			phase,
			phase_detail,
			cancellable,
			now_ns,
		)
		if !published {
			return {}, false, {code = .Process_Record_Rejected, process = publish_failure}
		}
	}
	if !terminal do return {}, false, {}
	_, _, terminal_view, _, terminal_diagnostic, terminal_viewed :=
		ksawery.repository_process_extension_operation_snapshot(&workflow.process)
	if !terminal_viewed ||
	   !ksawery_process_coordinator_detach_child(coordinator, terminal_view.association) {
		return {}, false, {code = .Process_Evidence_Rejected, process = .Stale_Observation}
	}
	workflow.terminal = terminal_view
	workflow.public_diagnostic_bytes = u64(len(terminal_diagnostic))
	workflow.awaiting_refresh = true
	ksawery.repository_process_close(&workflow.process)
	return ksawery_extension_operation_refresh_request(workflow), true, {}
}

/* ksawery_extension_operation_workflow_cancel requests exact-generation termination. */
ksawery_extension_operation_workflow_cancel :: proc(
	workflow: ^Ksawery_Extension_Operation_Workflow,
	coordinator: ^Ksawery_Process_Coordinator,
	now_ns: i64,
) -> (bool, Ksawery_Extension_Operation_Workflow_Failure) {
	if workflow == nil || !workflow.active || workflow.awaiting_refresh ||
	   workflow.process.state == nil || coordinator == nil || !coordinator.child_attached {
		return false, {code = .Invalid_State}
	}
	cancelled, cancel_failure := ksawery.repository_process_request_cancellation(
		&workflow.process,
		{
			operation = coordinator.active_authority.operation,
			generation = coordinator.active_generation,
			requested_ns = now_ns,
		},
	)
	if !cancelled {
		return false, {code = .Process_Evidence_Rejected, process = cancel_failure}
	}
	recorded, record_failure := ksawery_process_observation_note_cancellation(
		coordinator,
		&workflow.process,
		now_ns,
	)
	if !recorded {
		return false, {code = .Process_Record_Rejected, process = record_failure}
	}
	return true, {}
}

/* ksawery_extension_operation_workflow_complete verifies and publishes one terminal result. */
ksawery_extension_operation_workflow_complete :: proc(
	workflow: ^Ksawery_Extension_Operation_Workflow,
	coordinator: ^Ksawery_Process_Coordinator,
	evidence: ksawery.Extension_Operation_Refresh_Evidence,
	now_ns: i64,
) -> (bool, Ksawery_Extension_Operation_Workflow_Failure) {
	if workflow == nil || !workflow.active || !workflow.awaiting_refresh ||
	   coordinator == nil || now_ns < 0 {
		return false, {code = .Invalid_State}
	}
	refresh_completed, verifier_applied, verifier_agreed, valid :=
		ksawery.extension_operation_verifier_apply(workflow.submission, workflow.plan, evidence)
	if !valid {
		return false, {code = .Refresh_Evidence_Rejected}
	}
	if refresh_completed {
		confirmed, confirm_failure := ksawery_process_coordinator_confirm_refresh(
			coordinator,
			evidence.repository,
			ksawery.Observation_Generation(evidence.repository_generation),
		)
		if !confirmed {
			return false, {code = .Process_Record_Rejected, process = confirm_failure}
		}
		verification_proposal, prepared :=
			ksawery_extension_operation_current_proposal(coordinator, now_ns)
		if !prepared {
			return false, {code = .Process_Record_Rejected, process = .Cleanup}
		}
		if verification_proposal.lifecycle != .Cancellation_Requested {
			verification_proposal.lifecycle = .Running
		}
		verification_proposal.phase = .Verifying
		verification_proposal.phase_detail = "Applying declared external operation verifier"
		verification_proposal.actions = {}
		verification_proposal.actions[0] = {kind = .Inspect, available = true}
		verification_proposal.action_count = 1
		published, publish_failure := ksawery_process_coordinator_publish(
			coordinator,
			nil,
			verification_proposal,
		)
		if !published {
			return false, {code = .Process_Record_Rejected, process = publish_failure}
		}
	}
	result := ksawery_extension_operation_result(
		workflow,
		refresh_completed,
		verifier_applied,
		verifier_agreed,
	)
	_, result_failure := ksawery.extension_operation_result_validate(
		result,
		workflow.submission.request,
		workflow.plan,
	)
	if result_failure.code != .None {
		return false, {code = .Invalid_Result, extension = result_failure}
	}
	proposal, prepared := ksawery_extension_operation_current_proposal(coordinator, now_ns)
	if !prepared {
		return false, {code = .Process_Record_Rejected, process = .Cleanup}
	}
	proposal.lifecycle, proposal.outcome, proposal.message =
		ksawery_extension_operation_result_presentation(result)
	proposal.timing.finished_ns = now_ns
	proposal.actions = {}
	proposal.actions[0] = {kind = .Inspect, available = true}
	proposal.actions[1] = {kind = .Clear, available = true}
	proposal.action_count = 2
	published, publish_failure := ksawery_process_coordinator_publish(coordinator, nil, proposal)
	if !published {
		return false, {code = .Process_Record_Rejected, process = publish_failure}
	}
	workflow.result = result
	workflow.result_available = true
	workflow.active = false
	workflow.awaiting_refresh = false
	return true, {}
}

/* ksawery_extension_operation_workflow_inspect returns only a complete result. */
ksawery_extension_operation_workflow_inspect :: proc(
	workflow: ^Ksawery_Extension_Operation_Workflow,
) -> (ksawery.Extension_Operation_Result, bool) {
	if workflow == nil || !workflow.result_available do return {}, false
	return workflow.result, true
}

@(private)
ksawery_extension_operation_refresh_request :: proc(
	workflow: ^Ksawery_Extension_Operation_Workflow,
) -> Ksawery_Extension_Operation_Refresh_Request {
	if workflow == nil do return {}
	return {
		request = workflow.submission.request,
		repository = workflow.submission.repository,
		admitted_generation = workflow.submission.repository_generation,
		observations = workflow.plan.refresh,
	}
}

@(private)
ksawery_extension_operation_publish_process :: proc(
	workflow: ^Ksawery_Extension_Operation_Workflow,
	coordinator: ^Ksawery_Process_Coordinator,
	view: ksawery.Repository_Process_Lifecycle_View,
	output, diagnostic: []u8,
	phase: ksawery.Repository_Process_Phase,
	phase_detail: string,
	cancellable: bool,
	now_ns: i64,
) -> (bool, ksawery.Failure_Code) {
	proposal, prepared := ksawery_extension_operation_current_proposal(coordinator, now_ns)
	if !prepared do return false, .Cleanup
	if proposal.lifecycle != .Cancellation_Requested do proposal.lifecycle = .Running
	proposal.phase = phase
	proposal.phase_detail = phase_detail
	diagnostic_count := min(len(diagnostic), int(ksawery.MAX_PROCESS_STREAM_READ_BYTES_PER_STEP))
	proposal.output = nil
	proposal.diagnostic = diagnostic[:diagnostic_count]
	proposal.output_truncated = view.output_truncated || len(output) > 0
	proposal.diagnostic_truncated = view.diagnostic_truncated || diagnostic_count < len(diagnostic)
	proposal.progress = {
		kind = .Determinate,
		current = min(
			u64(len(output)) + u64(len(diagnostic)),
			workflow.plan.process_limits.output_bytes +
				workflow.plan.process_limits.diagnostic_bytes,
		),
		total = workflow.plan.process_limits.output_bytes +
			workflow.plan.process_limits.diagnostic_bytes,
	}
	proposal.exit_status = view.child.exit_status
	proposal.exit_status_available = view.child.exit_status_available
	proposal.actions = {}
	proposal.actions[0] = {kind = .Inspect, available = true}
	proposal.action_count = 1
	if cancellable {
		proposal.actions[1] = {kind = .Cancel, available = true}
		proposal.action_count = 2
	}
	published, failure := ksawery_process_coordinator_publish(
		coordinator,
		&workflow.process,
		proposal,
	)
	if !published && failure == .Sensitive_Content && len(proposal.diagnostic) > 0 {
		proposal.diagnostic = nil
		proposal.diagnostic_truncated = true
		published, failure = ksawery_process_coordinator_publish(
			coordinator,
			&workflow.process,
			proposal,
		)
	}
	if published {
		workflow.published_output_bytes = u64(len(output))
		workflow.published_diagnostic_bytes = u64(len(diagnostic))
	}
	return published, failure
}

@(private)
ksawery_extension_operation_current_proposal :: proc(
	coordinator: ^Ksawery_Process_Coordinator,
	now_ns: i64,
) -> (ksawery.Process_Record_Proposal, bool) {
	proposal, prepared := ksawery_process_observation_current_proposal(coordinator, now_ns)
	if !prepared || coordinator.record_count == 0 do return {}, false
	record := &coordinator.records[int(coordinator.record_count - 1)]
	descriptor, described := ksawery.process_record_descriptor(record)
	if !described do return {}, false
	message, message_ok := ksawery.process_record_text(record, descriptor.message)
	output, output_ok := ksawery.process_record_text(record, descriptor.content.output)
	diagnostic, diagnostic_ok := ksawery.process_record_text(record, descriptor.content.diagnostic)
	if !message_ok || !output_ok || !diagnostic_ok do return {}, false
	proposal.message = string(message)
	proposal.output = output
	proposal.diagnostic = diagnostic
	proposal.output_truncated = descriptor.content.output_truncated
	proposal.diagnostic_truncated = descriptor.content.diagnostic_truncated
	proposal.exit_status = descriptor.content.exit_status
	proposal.exit_status_available = descriptor.content.exit_status_available
	return proposal, true
}

@(private)
ksawery_extension_operation_result :: proc(
	workflow: ^Ksawery_Extension_Operation_Workflow,
	refresh_completed, verifier_applied, verifier_agreed: bool,
) -> ksawery.Extension_Operation_Result {
	view := workflow.terminal
	effect_possible := workflow.plan.effect != .Read_Only && view.child.children_started > 0
	result := ksawery.Extension_Operation_Result {
		request = workflow.submission.request,
		contributor = workflow.plan.contributor,
		plan = workflow.plan.plan,
		plan_generation = workflow.plan.generation,
		effect_possible = effect_possible,
		exit_code_present = view.child.exit_status_available,
		exit_code = view.child.exit_status,
		refresh_completed = refresh_completed,
		verifier_applied = verifier_applied,
		verifier_agreed = verifier_agreed,
		output_bytes = view.output_bytes,
		diagnostic_bytes = workflow.public_diagnostic_bytes,
		output_truncated = view.output_truncated,
		diagnostic_truncated = view.diagnostic_truncated &&
			workflow.plan.diagnostic_policy == .Bounded_Public,
	}
	if view.termination.reason == .Cancellation {
		result.verifier_agreed = false
		result.outcome = .Cancelled_Before_Effect
		if effect_possible {
			result.outcome = .Cancelled_After_Possible_Effect if refresh_completed else .Indeterminate
		}
		return result
	}
	if view.termination.reason == .Timeout {
		result.verifier_agreed = false
		result.outcome = .Timed_Out_Before_Effect
		if effect_possible {
			result.outcome = .Timed_Out_After_Possible_Effect if refresh_completed else .Indeterminate
		}
		return result
	}
	if view.child.state == .Uncertain || !view.child.exit_status_available {
		result.verifier_agreed = false
		result.outcome = .Indeterminate
		return result
	}
	if view.child.exit_status != 0 {
		result.outcome = .Known_Failure
		result.verifier_agreed = false
		return result
	}
	if refresh_completed && verifier_applied {
		result.outcome = .Verified_Success if verifier_agreed else .Verification_Mismatch
		return result
	}
	result.outcome = .Indeterminate
	return result
}

@(private)
ksawery_extension_operation_result_presentation :: proc(
	result: ksawery.Extension_Operation_Result,
) -> (ksawery.Repository_Process_Lifecycle, ksawery.Repository_Process_Outcome, string) {
	switch result.outcome {
	case .Verified_Success:
		return .Succeeded, result.outcome, "External repository operation verified"
	case .Known_Failure:
		return .Failed, result.outcome, "External repository operation failed"
	case .Cancelled_Before_Effect, .Cancelled_After_Possible_Effect:
		return .Cancelled, result.outcome, "External repository operation cancelled"
	case .Timed_Out_Before_Effect, .Timed_Out_After_Possible_Effect:
		return .Timed_Out, result.outcome, "External repository operation timed out"
	case .Verification_Mismatch:
		return .Failed, result.outcome, "External repository operation verification disagreed"
	case .Indeterminate:
		return .Indeterminate, result.outcome, "External repository operation outcome is indeterminate"
	case .None:
		return .Indeterminate, .Indeterminate, "External repository operation outcome is indeterminate"
	}
	return .Indeterminate, .Indeterminate, "External repository operation outcome is indeterminate"
}
