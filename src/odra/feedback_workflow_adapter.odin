// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../feedback"
import "../feedback_routing"
import "../feedback_workflow"
import "../interaction"
import "../ui"

/* Feedback_Workflow_State owns editor feedback state outside the command stack frame. */
Feedback_Workflow_State :: struct {
	workflow:     feedback_workflow.Workflow,
	publications: [feedback_workflow.CHANNEL_COUNT]feedback_workflow.Publication,
}

@(private)
command_context_feedback_init :: proc(
	commands: ^Command_Context,
	profile: ui.Presentation_Profile_Handle,
) -> bool {
	if commands == nil || commands.feedback_state != nil do return false
	state, allocation_error := new(Feedback_Workflow_State, commands.persistent_allocator)
	if allocation_error != nil do return false
	ready, _ := feedback_workflow.workflow_init(
		&state.workflow,
		1,
		profile,
		{persistent = commands.persistent_allocator, temporary = commands.temporary_allocator},
		feedback_workflow.status_frontend(),
	)
	if !ready {
		free(state, commands.persistent_allocator)
		return false
	}
	commands.feedback_state = state
	return ready
}

@(private)
command_context_publish_feedback :: proc(
	commands: ^Command_Context,
	channel: feedback_workflow.Channel,
	message: string,
	severity := feedback.Severity.Information,
	detail := "",
	attention := feedback.Attention.Ordinary,
	retention := feedback.Retention_Policy.None,
	actions: []feedback_workflow.Action_Definition = nil,
) -> (feedback_workflow.Publication, bool) {
	if commands == nil || commands.feedback_state == nil ||
	   !commands.feedback_state.workflow.initialized || len(message) == 0 {
		return {}, false
	}
	class := feedback.Semantic_Class.Information
	if severity == .Warning do class = .Warning
	if severity == .Error do class = .Error
	publication, published, _ := feedback_workflow.workflow_publish_notification(
		&commands.feedback_state.workflow,
		{
			channel = channel,
			class = class,
			severity = severity,
			attention = attention,
			lifecycle = .Attention if attention == .Required else .Transient,
			retention = retention,
			visibility = .Public,
			message = message,
			detail = detail,
			actions = actions,
		},
	)
	if !published do return {}, false
	index := int(channel) - 1
	if index >= 0 && index < len(commands.feedback_state.publications) {
		commands.feedback_state.publications[index] = publication
	}
	return publication, true
}

@(private)
command_context_set_channel_diagnostic :: proc(
	commands: ^Command_Context,
	channel: feedback_workflow.Channel,
	message: string,
	severity := feedback.Severity.Information,
	detail := "",
	attention := feedback.Attention.Ordinary,
	retention := feedback.Retention_Policy.None,
) {
	if commands == nil do return
	count := min(len(message), len(commands.diagnostic))
	copy(commands.diagnostic[:], transmute([]u8)message[:count])
	commands.diagnostic_length = count
	_, _ = command_context_publish_feedback(
		commands,
		channel,
		string(commands.diagnostic[:count]),
		severity,
		detail,
		attention,
		retention,
	)
}

@(private)
command_context_publish_progress :: proc(
	commands: ^Command_Context,
	request: feedback_workflow.Progress_Request,
) -> (feedback_workflow.Publication, bool) {
	if commands == nil || commands.feedback_state == nil ||
	   !commands.feedback_state.workflow.initialized {
		return {}, false
	}
	publication, published, _ := feedback_workflow.workflow_publish_progress(
		&commands.feedback_state.workflow,
		request,
	)
	if published {
		commands.feedback_state.publications[int(feedback_workflow.Channel.Long_Operation) - 1] = publication
		if projection, projected := command_context_feedback_projection(commands); projected {
			content := feedback_routing.projection_content(&projection)
			count := min(len(content), len(commands.diagnostic))
			copy(commands.diagnostic[:], transmute([]u8)content[:count])
			commands.diagnostic_length = count
		}
	}
	return publication, published
}

@(private)
command_context_feedback_projection :: proc(
	commands: ^Command_Context,
) -> (feedback_routing.Projection, bool) {
	if commands == nil do return {}, false
	if commands.feedback_state == nil do return {}, false
	return feedback_workflow.workflow_status_projection(&commands.feedback_state.workflow)
}

@(private)
command_context_resolve_feedback_action :: proc(
	commands: ^Command_Context,
	channel: feedback_workflow.Channel,
	action: feedback.Action_ID,
) -> (interaction.Command_Handle, bool) {
	if commands == nil || commands.registry == nil ||
	   channel <= .Invalid || channel > .Long_Operation {
		return {}, false
	}
	if commands.feedback_state == nil do return {}, false
	publication := commands.feedback_state.publications[int(channel) - 1]
	authority, resolved, _ := feedback_workflow.workflow_resolve_action(
		&commands.feedback_state.workflow,
		publication,
		action,
	)
	if !resolved do return {}, false
	defer feedback.action_authority_release(&authority, commands.temporary_allocator)
	if len(authority.action.argument) > 0 do return {}, false
	handle, found, _ := interaction.command_lookup(commands.registry, authority.action.command)
	return handle, found
}

@(private)
command_context_feedback_close :: proc(commands: ^Command_Context) {
	if commands == nil || commands.feedback_state == nil do return
	if commands.feedback_state.workflow.initialized {
		_, _ = feedback_workflow.workflow_close(&commands.feedback_state.workflow)
	}
	free(commands.feedback_state, commands.persistent_allocator)
	commands.feedback_state = nil
}
