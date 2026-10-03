// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery_module

import "../ksawery"

/* Ksawery_Conflict_Assistance_Surface_Action closes Conflict helper composition. */
Ksawery_Conflict_Assistance_Surface_Action :: enum u8 {
	None,
	Return,
	Open_Editor,
	Run_External_Tool,
}

/* Ksawery_Conflict_Assistance_Presentation is the bounded Conflict-surface view. */
Ksawery_Conflict_Assistance_Presentation :: struct {
	provider:          ksawery.Conflict_Assistance_Provider_Reference,
	label:             ksawery.Extension_Label,
	response:          ksawery.Conflict_Assistance_Response_Kind,
	guidance:          ksawery.Conflict_Assistance_Guidance,
	fallback:          bool,
	return_available:  bool,
	editor_available:  bool,
	tool_available:    bool,
	core_actions_only: bool,
	failure:           ksawery.Conflict_Assistance_Failure,
}

/* Ksawery_Conflict_Assistance_Workflow owns one Conflict helper turn and tool. */
Ksawery_Conflict_Assistance_Workflow :: struct {
	evaluation:        Ksawery_Conflict_Assistance_Evaluation,
	operation:         Ksawery_Extension_Operation_Workflow,
	admission:         ksawery.Conflict_Assistance_Tool_Admission,
	result:            ksawery.Conflict_Assistance_Tool_Result,
	failure:           ksawery.Conflict_Assistance_Failure,
	selected_action:   Ksawery_Conflict_Assistance_Surface_Action,
	composed:          bool,
	result_available:  bool,
}

/* ksawery_conflict_assistance_workflow_compose selects one validated surface response. */
ksawery_conflict_assistance_workflow_compose :: proc(
	workflow: ^Ksawery_Conflict_Assistance_Workflow,
	evaluation: Ksawery_Conflict_Assistance_Evaluation,
	failure: ksawery.Conflict_Assistance_Failure = {},
) -> bool {
	if workflow == nil || !evaluation.available do return false
	_, response_failure := ksawery.conflict_assistance_response_validate(
		evaluation.response,
		evaluation.request,
		evaluation.provider,
	)
	if response_failure.code != .None do return false
	workflow^ = {
		evaluation = evaluation,
		failure = failure,
		composed = true,
	}
	if workflow.evaluation.response.kind == .External_Tool {
		argument_count := len(workflow.evaluation.response.tool.operation.arguments)
		workflow.evaluation.response.tool.operation.arguments =
			workflow.evaluation.arguments[:argument_count]
	}
	return true
}

/* ksawery_conflict_assistance_workflow_inspect copies the current surface view. */
ksawery_conflict_assistance_workflow_inspect :: proc(
	workflow: ^Ksawery_Conflict_Assistance_Workflow,
) -> (Ksawery_Conflict_Assistance_Presentation, bool) {
	if workflow == nil || !workflow.composed do return {}, false
	evaluation := &workflow.evaluation
	presentation := Ksawery_Conflict_Assistance_Presentation {
		provider = evaluation.request.provider,
		label = evaluation.provider.label,
		response = evaluation.response.kind,
		guidance = evaluation.response.guidance,
		fallback = evaluation.fallback,
		return_available = !workflow.operation.active,
		core_actions_only = true,
		failure = workflow.failure,
	}
	if !workflow.operation.active {
		presentation.editor_available = evaluation.response.kind == .Editor
		presentation.tool_available = evaluation.response.kind == .External_Tool
	}
	return presentation, true
}

/* ksawery_conflict_assistance_workflow_choose records a non-tool Conflict action. */
ksawery_conflict_assistance_workflow_choose :: proc(
	workflow: ^Ksawery_Conflict_Assistance_Workflow,
	action: Ksawery_Conflict_Assistance_Surface_Action,
) -> bool {
	if workflow == nil || !workflow.composed || workflow.operation.active do return false
	switch action {
	case .Return:
		workflow.selected_action = action
		return true
	case .Open_Editor:
		if workflow.evaluation.response.kind != .Editor do return false
		workflow.selected_action = action
		return true
	case .None, .Run_External_Tool:
		return false
	}
	return false
}

/* ksawery_conflict_assistance_workflow_begin_tool admits one tool to Process. */
ksawery_conflict_assistance_workflow_begin_tool :: proc(
	workflow: ^Ksawery_Conflict_Assistance_Workflow,
	coordinator: ^Ksawery_Process_Coordinator,
	index_before: ksawery.Conflict_Assistance_Index_Fingerprint,
	current_contributor: ksawery.Contributor_Handle,
	current_repository: ksawery.Repository_Context,
	current_repository_generation: ksawery.Repository_Generation,
	now_ns: i64,
) -> (bool, ksawery.Conflict_Assistance_Failure) {
	if workflow == nil || !workflow.composed || workflow.operation.active ||
	   workflow.evaluation.response.kind != .External_Tool {
		return false, {code = .Invalid_Response}
	}
	evaluation := &workflow.evaluation
	tool := evaluation.response.tool
	admission := ksawery.Conflict_Assistance_Tool_Admission {
		request = evaluation.request,
		operation = {
			request = ksawery.Extension_Operation_Request_ID(u64(evaluation.request.request)),
			contributor = evaluation.provider.contributor,
			contribution = tool.operation.contribution,
			repository = evaluation.request.target.repository,
			repository_generation = evaluation.request.target.repository_generation,
		},
		access = tool.access,
		index_before = index_before,
	}
	failure := ksawery.conflict_assistance_tool_admission_validate(
		admission,
		tool,
		evaluation.provider,
		evaluation.selection,
		evaluation.provider_declaration,
		evaluation.operation_declaration,
		current_contributor,
		current_repository,
		current_repository_generation,
	)
	if failure.code != .None {
		workflow.failure = failure
		return false, failure
	}
	started, _ := ksawery_extension_operation_workflow_begin(
		&workflow.operation,
		coordinator,
		admission.operation,
		tool.operation,
		evaluation.operation_declaration,
		current_contributor,
		current_repository,
		current_repository_generation,
		now_ns,
	)
	if !started {
		failure.code = .Tool_Unavailable
		workflow.failure = failure
		return false, failure
	}
	workflow.admission = admission
	workflow.selected_action = .Run_External_Tool
	workflow.failure = {}
	return true, {}
}

/* ksawery_conflict_assistance_workflow_poll returns the mandatory refresh request. */
ksawery_conflict_assistance_workflow_poll :: proc(
	workflow: ^Ksawery_Conflict_Assistance_Workflow,
	coordinator: ^Ksawery_Process_Coordinator,
	now_ns: i64,
) -> (Ksawery_Extension_Operation_Refresh_Request, bool, Ksawery_Extension_Operation_Workflow_Failure) {
	if workflow == nil do return {}, false, {code = .Invalid_State}
	return ksawery_extension_operation_workflow_poll(&workflow.operation, coordinator, now_ns)
}

/* ksawery_conflict_assistance_workflow_complete checks refresh and core authority. */
ksawery_conflict_assistance_workflow_complete :: proc(
	workflow: ^Ksawery_Conflict_Assistance_Workflow,
	coordinator: ^Ksawery_Process_Coordinator,
	evidence: ksawery.Conflict_Assistance_Tool_Refresh_Evidence,
	now_ns: i64,
) -> (bool, ksawery.Conflict_Assistance_Failure) {
	if workflow == nil || !workflow.composed || !workflow.operation.active ||
	   !workflow.operation.awaiting_refresh {
		return false, {code = .Invalid_Response}
	}
	extension_evidence := ksawery.Extension_Operation_Refresh_Evidence {
		repository = evidence.repository,
		repository_generation = evidence.repository_generation,
		attempted = evidence.attempted,
		completed = evidence.completed,
	}
	completed, _ := ksawery_extension_operation_workflow_complete(
		&workflow.operation,
		coordinator,
		extension_evidence,
		now_ns,
	)
	if !completed {
		failure := ksawery.Conflict_Assistance_Failure {
			code = .Stale_Observation,
			provider = workflow.evaluation.provider.provider,
			request = workflow.evaluation.request.request,
			target = workflow.evaluation.request.target.conflict,
		}
		workflow.failure = failure
		return false, failure
	}
	operation_result, available := ksawery_extension_operation_workflow_inspect(&workflow.operation)
	if !available do return false, {code = .Invalid_Response}
	result := ksawery.Conflict_Assistance_Tool_Result {
		request = workflow.evaluation.request.request,
		provider = workflow.evaluation.request.provider,
		target = workflow.evaluation.request.target,
		operation = operation_result,
		refresh_completed = ksawery.conflict_assistance_tool_refresh_is_complete(
			workflow.admission,
			evidence,
		),
	}
	result.index_preserved = result.refresh_completed &&
		evidence.index_after == workflow.admission.index_before
	result.conflict_retained = result.refresh_completed && evidence.target_present &&
		evidence.target.repository == result.target.repository &&
		evidence.target.conflict == result.target.conflict &&
		evidence.target.path == result.target.path
	failure := ksawery.conflict_assistance_tool_result_validate(
		result,
		workflow.admission,
		workflow.evaluation.response.tool,
		evidence,
	)
	workflow.result = result
	workflow.result_available = true
	workflow.failure = failure
	return failure.code == .None, failure
}

/* ksawery_conflict_assistance_workflow_return restores ordinary Conflict ownership. */
ksawery_conflict_assistance_workflow_return :: proc(
	workflow: ^Ksawery_Conflict_Assistance_Workflow,
) -> bool {
	if workflow == nil || !workflow.composed || workflow.operation.active do return false
	workflow.selected_action = .Return
	return true
}

/* ksawery_conflict_assistance_workflow_close releases any owned tool child. */
ksawery_conflict_assistance_workflow_close :: proc(
	workflow: ^Ksawery_Conflict_Assistance_Workflow,
) {
	if workflow == nil do return
	if workflow.operation.process.state != nil {
		ksawery.repository_process_close(&workflow.operation.process)
	}
	workflow^ = {}
}
