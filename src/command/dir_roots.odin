// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../document"
import "../editor_session"
import "core:os"

/* Dir_Root_Completion identifies one ordered session-root mutation. */
Dir_Root_Completion :: enum u8 {
	Invalid,
	Added,
	Removed,
}

/* Dir_Root_Result reports one complete root-set publication. */
Dir_Root_Result :: struct {
	completion: Dir_Root_Completion,
	publication: editor_session.Root_Replace_Result,
}

/* dir_root_add appends one ordinary Dir without changing existing root projections. */
dir_root_add :: proc(
	ctx: Project_Command_Context,
	path: string,
) -> (result: Dir_Root_Result, ok: bool, failure: Failure_Context) {
	if !project_command_context_is_valid(ctx) || len(path) == 0 || !os.is_directory(path) {
		return {}, false, Failure_Context{code = .Invalid_Request, command = ctx.command}
	}
	normalized: document.Normalized_Path
	normalized_ok, _ := document.path_normalize(path, &normalized, ctx.temporary_allocator)
	if !normalized_ok {
		return {}, false, Failure_Context{code = .Invalid_Request, command = ctx.command}
	}
	target := document.normalized_path_text(&normalized)
	roots, listed, list_failure := editor_session.session_roots(ctx.session, ctx.handle)
	if !listed {
		return {}, false, buffer_session_failure(ctx.command, list_failure)
	}
	defer editor_session.root_batch_close(&roots)
	proposals, proposal_error := make(
		[]editor_session.Root_Proposal,
		len(roots.descriptors) + 1,
		ctx.temporary_allocator,
	)
	if proposal_error != nil {
		return {}, false, Failure_Context{code = .Temporary_Memory_Limit, command = ctx.command}
	}
	defer delete(proposals, ctx.temporary_allocator)
	for root, index in roots.descriptors {
		if root.path == target {
			return {}, false, Failure_Context{code = .Invalid_Request, command = ctx.command}
		}
		proposals[index] = editor_session.Root_Proposal {
			kind = root.kind,
			path = root.path,
			project = root.project,
		}
	}
	proposals[len(proposals) - 1] = editor_session.Root_Proposal{kind = .Dir, path = target}
	publication, published, publish_failure := editor_session.session_roots_replace(
		ctx.session,
		editor_session.Root_Replace_Request{session = ctx.handle, roots = proposals},
	)
	if !published {
		return {}, false, buffer_session_failure(ctx.command, publish_failure)
	}
	return Dir_Root_Result{completion = .Added, publication = publication}, true, {}
}

/* dir_root_remove removes one exact root while preserving relative order. */
dir_root_remove :: proc(
	ctx: Project_Command_Context,
	path: string,
) -> (result: Dir_Root_Result, ok: bool, failure: Failure_Context) {
	if !project_command_context_is_valid(ctx) || len(path) == 0 {
		return {}, false, Failure_Context{code = .Invalid_Request, command = ctx.command}
	}
	normalized: document.Normalized_Path
	normalized_ok, _ := document.path_normalize(path, &normalized, ctx.temporary_allocator)
	if !normalized_ok {
		return {}, false, Failure_Context{code = .Invalid_Request, command = ctx.command}
	}
	target := document.normalized_path_text(&normalized)
	roots, listed, list_failure := editor_session.session_roots(ctx.session, ctx.handle)
	if !listed {
		return {}, false, buffer_session_failure(ctx.command, list_failure)
	}
	defer editor_session.root_batch_close(&roots)
	target_index := -1
	for root, index in roots.descriptors {
		if root.path == target {
			target_index = index
			break
		}
	}
	if target_index < 0 {
		return {}, false, Failure_Context{code = .Invalid_Request, command = ctx.command}
	}
	proposals, proposal_error := make(
		[]editor_session.Root_Proposal,
		len(roots.descriptors) - 1,
		ctx.temporary_allocator,
	)
	if proposal_error != nil {
		return {}, false, Failure_Context{code = .Temporary_Memory_Limit, command = ctx.command}
	}
	defer delete(proposals, ctx.temporary_allocator)
	proposal_index := 0
	for root, index in roots.descriptors {
		if index == target_index {continue}
		proposals[proposal_index] = editor_session.Root_Proposal {
			kind = root.kind,
			path = root.path,
			project = root.project,
		}
		proposal_index += 1
	}
	publication, published, publish_failure := editor_session.session_roots_replace(
		ctx.session,
		editor_session.Root_Replace_Request{session = ctx.handle, roots = proposals},
	)
	if !published {
		return {}, false, buffer_session_failure(ctx.command, publish_failure)
	}
	return Dir_Root_Result{completion = .Removed, publication = publication}, true, {}
}
