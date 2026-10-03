// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../editor_session"
import "../language_service"
import language_service_workflow "../language_service_workflow"

@(private)
Language_Service_Workflow_State :: language_service_workflow.Workflow_State

@(private)
Language_Service_Workflow_Session :: language_service_workflow.Workflow_Session

@(private)
Language_Service_Workflow_Document :: language_service_workflow.Workflow_Document

@(private)
Language_Service_Visible_Observation :: language_service_workflow.Visible_Observation

@(private)
Language_Service_Context_Projection :: language_service_workflow.Context_Projection

@(private)
Language_Service_Diagnostic_Source :: language_service_workflow.Diagnostic_Source

@(private)
Language_Support_Workflow_Candidate :: language_service_workflow.Support_Candidate

language_service_workflow_init :: language_service_workflow.Language_Service_Workflow_Init

language_service_workflow_reconcile :: language_service_workflow.Language_Service_Workflow_Reconcile

language_service_workflow_project_visible :: language_service_workflow.Language_Service_Workflow_Project_Visible

language_service_workflow_project_language_context :: language_service_workflow.Language_Service_Workflow_Project_Language_Context

language_service_workflow_diagnostic_source :: language_service_workflow.Language_Service_Workflow_Diagnostic_Source

language_service_diagnostic_source_close :: language_service_workflow.Language_Service_Diagnostic_Source_Close

language_service_workflow_resolve_diagnostic_action :: language_service_workflow.Language_Service_Workflow_Resolve_Diagnostic_Action

language_service_workflow_session_for_buffer :: language_service_workflow.Language_Service_Workflow_Session_For_Buffer

language_service_workflow_restart :: language_service_workflow.Language_Service_Workflow_Restart

language_service_workflow_close :: language_service_workflow.Language_Service_Workflow_Close

language_service_workflow_copy_buffer :: language_service_workflow.Language_Service_Workflow_Copy_Buffer

language_service_workflow_now_ns :: language_service_workflow.Language_Service_Workflow_Now_Ns

language_service_workflow_is_live :: language_service_workflow.Language_Service_Workflow_Is_Live

language_support_workflow_prepare :: language_service_workflow.Language_Support_Workflow_Prepare

language_support_workflow_publish :: language_service_workflow.Language_Support_Workflow_Publish

language_support_workflow_candidate_close :: language_service_workflow.Language_Support_Workflow_Candidate_Close

@(private)
language_service_completion_matches :: proc(
	state: rawptr,
	owner: ^language_service_workflow.Workflow_Session,
) -> bool {
	return completion_workflow_matches_service(cast(^Completion_Workflow_State)state, owner)
}

@(private)
language_service_completion_end :: proc(
	state: rawptr,
	owner: ^language_service_workflow.Workflow_Session,
	send_cancel: bool,
) {
	completion_workflow_end_session(cast(^Completion_Workflow_State)state, owner, send_cancel)
}

@(private)
language_service_completion_receive :: proc(
	state: rawptr,
	owner: ^language_service_workflow.Workflow_Session,
	message: ^language_service.Message,
) -> (handled, changed: bool) {
	return completion_workflow_receive_message(cast(^Completion_Workflow_State)state, owner, message)
}

@(private)
language_service_workflow_step :: proc(
	commands: ^Command_Context,
	session_owner: ^editor_session.Session,
	session_handle: editor_session.Session_Handle,
) -> bool {
	if commands == nil || !language_service_workflow_is_live(commands.language_service_workflow) {
		return false
	}
	changed := language_service_workflow_reconcile(
		commands.language_service_workflow,
		commands.syntax_workflow,
		session_owner,
		session_handle,
		context.temp_allocator,
	)
	changed = language_service_workflow.Language_Service_Workflow_Maintain(
		commands.language_service_workflow,
		{
			state = rawptr(commands.completion_workflow),
			matches_service = language_service_completion_matches,
			end_session = language_service_completion_end,
			receive_message = language_service_completion_receive,
		},
	) || changed
	return completion_workflow_step(commands, session_owner, session_handle) || changed
}
