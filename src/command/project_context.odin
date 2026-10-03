// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../editor_session"
import "../interaction"
import "../project"
import "base:runtime"

/* Project_Command_Context supplies checked Project and allocation authority for one workflow. */
Project_Command_Context :: struct {
	session:             ^editor_session.Session,
	handle:              editor_session.Session_Handle,
	command:             interaction.Command_Handle,
	persistent_allocator: runtime.Allocator,
	temporary_allocator: runtime.Allocator,
}

/* project_list_directories returns one explicitly owned copied membership batch. */
project_list_directories :: proc(
	ctx: Project_Command_Context,
) -> (batch: project.Descriptor_Batch, ok: bool, failure: Failure_Context) {
	active, batch_result, ready, ready_failure := project_command_membership(ctx)
	_ = active
	if !ready {
		return {}, false, ready_failure
	}
	return batch_result, true, {}
}

/* project_inspect_active returns one copied active-Project summary. */
project_inspect_active :: proc(
	ctx: Project_Command_Context,
) -> (snapshot: editor_session.Active_Project_Snapshot, ok: bool, failure: Failure_Context) {
	if !project_command_context_is_valid(ctx) {
		return {}, false, Failure_Context{code = .Invalid_Request, command = ctx.command}
	}
	current, inspected, inspect_failure := editor_session.session_active_project(
		ctx.session,
		ctx.handle,
	)
	if !inspected {
		return {}, false, buffer_session_failure(ctx.command, inspect_failure)
	}
	if !current.active {
		return {}, false, Failure_Context{code = .Project_Scope_Required, command = ctx.command}
	}
	return current, true, {}
}

@(private)
project_command_membership :: proc(
	ctx: Project_Command_Context,
) -> (
	active: editor_session.Active_Project_Snapshot,
	batch: project.Descriptor_Batch,
	ok: bool,
	failure: Failure_Context,
) {
	if !project_command_context_is_valid(ctx) {
		return {}, {}, false, Failure_Context{code = .Invalid_Request, command = ctx.command}
	}
	current, inspected, inspect_failure := editor_session.session_active_project(
		ctx.session,
		ctx.handle,
	)
	if !inspected {
		return {}, {}, false, buffer_session_failure(ctx.command, inspect_failure)
	}
	if !current.active {
		return {}, {}, false, Failure_Context{code = .Project_Scope_Required, command = ctx.command}
	}
	copied_batch, listed, list_failure := editor_session.session_project_memberships(
		ctx.session,
		ctx.handle,
		current.descriptor.handle,
	)
	if !listed {
		return {}, {}, false, buffer_session_failure(ctx.command, list_failure)
	}
	return current, copied_batch, true, {}
}

@(private)
project_command_context_is_valid :: proc(ctx: Project_Command_Context) -> bool {
	return ctx.session != nil && editor_session.session_handle_is_valid(ctx.handle) &&
	       ctx.temporary_allocator.procedure != nil
}
