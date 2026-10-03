// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../editor_session"
import "../project"

/* Project_Save_Result reports truthful examined, modified, and completed saves. */
Project_Save_Result :: struct {
	examined_buffers: u32,
	modified_buffers: u32,
	saved_buffers:    u32,
}

/* Project_Close_Outcome classifies atomic completion or one required dirty decision. */
Project_Close_Outcome :: enum u8 {
	Invalid,
	Completed,
	Decision_Required,
}

/* Project_Close_Result reports one atomic Project-buffer close attempt. */
Project_Close_Result :: struct {
	outcome:        Project_Close_Outcome,
	examined_buffers: u32,
	closed_buffers: u32,
	decision_entry: editor_session.Entry_Handle,
}

/* Project_Refresh_State owns observations for one exact active Project generation. */
Project_Refresh_State :: struct {
	observations: project.Observation_Registry,
	project:      project.Project_Handle,
}

/* project_save_buffers saves only modified file-backed buffers owned by the active Project. */
project_save_buffers :: proc(
	ctx: Project_Command_Context,
) -> (result: Project_Save_Result, ok: bool, failure: Failure_Context) {
	owned, owned_ok, owned_failure := project_switch_buffer_candidates(ctx)
	if !owned_ok {
		return {}, false, owned_failure
	}
	defer project_buffer_candidate_batch_close(&owned)
	descriptors, descriptors_ok, descriptor_failure := editor_session.session_descriptors(
		ctx.session,
		ctx.handle,
	)
	if !descriptors_ok {
		return {}, false, buffer_session_failure(ctx.command, descriptor_failure)
	}
	defer editor_session.descriptor_batch_close(&descriptors)
	for candidate in owned.candidates {
		result.examined_buffers += 1
		descriptor, found := project_entry_descriptor(descriptors.descriptors, candidate.entry)
		if !found || descriptor.association != .Document || !descriptor.modified {
			continue
		}
		result.modified_buffers += 1
		_, saved, save_failure := buffer_session_save_entry(
			Buffer_Session_Context{
				session = ctx.session,
				handle = ctx.handle,
				command = ctx.command,
			},
			candidate.entry,
		)
		if !saved {
			return result, false, save_failure
		}
		result.saved_buffers += 1
	}
	return result, true, {}
}

/* project_close_buffers validates every dirty decision before one atomic Project-buffer close. */
project_close_buffers :: proc(
	ctx: Project_Command_Context,
	authorities: []editor_session.Close_Buffer_Request = nil,
) -> (result: Project_Close_Result, ok: bool, failure: Failure_Context) {
	owned, owned_ok, owned_failure := project_switch_buffer_candidates(ctx)
	if !owned_ok {
		return {}, false, owned_failure
	}
	defer project_buffer_candidate_batch_close(&owned)
	result.examined_buffers = u32(len(owned.candidates))
	if len(owned.candidates) == 0 {
		result.outcome = .Completed
		return result, true, {}
	}
	requests, request_error := make(
		[]editor_session.Close_Buffer_Request,
		len(owned.candidates),
		ctx.temporary_allocator,
	)
	if request_error != nil {
		return {}, false, Failure_Context{code = .Temporary_Memory_Limit, command = ctx.command}
	}
	defer delete(requests, ctx.temporary_allocator)
	for candidate, index in owned.candidates {
		assessment, assessed, assess_failure := editor_session.session_assess_buffer_close(
			ctx.session,
			candidate.entry,
		)
		if !assessed {
			return {}, false, buffer_session_failure(ctx.command, assess_failure)
		}
		authority := editor_session.Close_Authority.Preserve_Modified
		if assessment.modified {
			found := false
			for supplied in authorities {
				if supplied.entry == candidate.entry {
					authority = supplied.authority
					found = true
					break
				}
			}
			if !found || authority != .Discard_Modified {
				result.outcome = .Decision_Required
				result.decision_entry = candidate.entry
				return result, true, {}
			}
		}
		requests[index] = editor_session.Close_Buffer_Request{
			entry = candidate.entry,
			authority = authority,
		}
	}
	closed, closed_ok, close_failure := editor_session.session_close_buffer_set(ctx.session, requests)
	if !closed_ok {
		return {}, false, buffer_session_failure(ctx.command, close_failure)
	}
	result.outcome = .Completed
	result.closed_buffers = closed.closed_entries
	return result, true, {}
}

/* project_refresh_init captures active membership and initializes explicit observations. */
project_refresh_init :: proc(
	ctx: Project_Command_Context,
	state: ^Project_Refresh_State,
) -> (ok: bool, failure: Failure_Context) {
	assert(state != nil)
	state^ = {}
	if ctx.persistent_allocator.procedure == nil {
		return false, Failure_Context{code = .Invalid_Request, command = ctx.command}
	}
	active, memberships, ready, ready_failure := project_command_membership(ctx)
	if !ready {
		return false, ready_failure
	}
	defer project.descriptor_batch_close(&memberships)
	initialized, initialize_failure := project.observation_registry_init(
		&state.observations,
		active.descriptor.handle,
		memberships.descriptors,
		project.DEFAULT_POLICY,
		project.Allocator_Set{
			persistent = ctx.persistent_allocator,
			temporary = ctx.temporary_allocator,
		},
	)
	if !initialized {
		return false, project_command_failure(ctx.command, initialize_failure)
	}
	state.project = active.descriptor.handle
	return true, {}
}

/* project_refresh_request coalesces an explicit full refresh for the captured Project. */
project_refresh_request :: proc(
	ctx: Project_Command_Context,
	state: ^Project_Refresh_State,
) -> (ok: bool, failure: Failure_Context) {
	if !project_refresh_state_matches(ctx, state) {
		return false, Failure_Context{
			code = .Editor_Session_Failure,
			command = ctx.command,
			project_code = .Stale_Project,
		}
	}
	requested, request_failure := project.observation_request_refresh(&state.observations, state.project)
	if !requested {
		return false, project_command_failure(ctx.command, request_failure)
	}
	return true, {}
}

/* project_refresh_advance performs one bounded reconciliation turn. */
project_refresh_advance :: proc(
	ctx: Project_Command_Context,
	state: ^Project_Refresh_State,
	cancelled := false,
) -> (result: project.Reconcile_Result, ok: bool, failure: Failure_Context) {
	if !project_refresh_state_matches(ctx, state) {
		return {}, false, Failure_Context{
			code = .Editor_Session_Failure,
			command = ctx.command,
			project_code = .Stale_Project,
		}
	}
	reconciled: bool
	reconcile_failure: project.Failure_Context
	result, reconciled, reconcile_failure = project.observation_reconcile(
		&state.observations,
		state.project,
		cancelled,
	)
	if !reconciled {
		return {}, false, project_command_failure(ctx.command, reconcile_failure)
	}
	return result, true, {}
}

/* project_refresh_close releases captured observation state. */
project_refresh_close :: proc(state: ^Project_Refresh_State) -> bool {
	if state == nil || state.observations.state == nil {
		return false
	}
	project.observation_registry_close(&state.observations)
	state^ = {}
	return true
}

@(private)
project_refresh_state_matches :: proc(ctx: Project_Command_Context, state: ^Project_Refresh_State) -> bool {
	if state == nil || state.observations.state == nil || !project.project_handle_is_valid(state.project) {
		return false
	}
	active, active_ok, _ := project_inspect_active(ctx)
	return active_ok && active.descriptor.handle == state.project
}

@(private)
project_entry_descriptor :: proc(
	descriptors: []editor_session.Entry_Descriptor,
	entry: editor_session.Entry_Handle,
) -> (editor_session.Entry_Descriptor, bool) {
	for descriptor in descriptors {
		if descriptor.graph.entry == entry {
			return descriptor, true
		}
	}
	return {}, false
}
