// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../editor"
import "../editor_session"
import "../interaction"
import "../project"
import "core:os"
import "core:testing"

/* Verifies Project save, close protection, and refresh stay scoped to owned buffers. */
@(test)
project_ops_compose_buffers_and_refresh :: proc(t: ^testing.T) {
	workspace, workspace_error := os.make_directory_temp("", "odra-command-project-ops-*", context.allocator)
	testing.expect(t, workspace_error == nil)
	if workspace_error != nil {
		return
	}
	defer {
		os.remove_all(workspace)
		delete(workspace)
	}
	owned_directory, _ := os.join_path({workspace, "owned"}, context.allocator)
	external_directory, _ := os.join_path({workspace, "external"}, context.allocator)
	owned_path, _ := os.join_path({owned_directory, "owned.txt"}, context.allocator)
	external_path, _ := os.join_path({external_directory, "external.txt"}, context.allocator)
	defer {
		delete(external_path)
		delete(owned_path)
		delete(external_directory)
		delete(owned_directory)
	}
	testing.expect(t, os.make_directory(owned_directory) == nil)
	testing.expect(t, os.make_directory(external_directory) == nil)
	testing.expect(t, os.write_entire_file(owned_path, "owned") == nil)
	testing.expect(t, os.write_entire_file(external_path, "external") == nil)

	session: editor_session.Session
	handle, initialized, _ := editor_session.session_init(
		&session,
		editor_session.Session_ID(971),
		editor_session.Allocator_Set{
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	testing.expect(t, initialized)
	if !initialized {
		return
	}
	command_handle := interaction.Command_Handle{
		registry_generation = 1,
		slot = 1,
		entry_generation = 1,
	}
	ctx := Project_Command_Context{
		session = &session,
		handle = handle,
		command = command_handle,
		persistent_allocator = context.allocator,
		temporary_allocator = context.temp_allocator,
	}
	created := activate_test_project(
		ctx,
		project.Project_ID(972),
		"operations",
		"Operations",
		owned_directory,
	)
	testing.expect(t, created)
	buffer_ctx := Buffer_Session_Context{
		session = &session,
		handle = handle,
		command = command_handle,
		configuration = editor_session.DEFAULT_ENTRY_CONFIGURATION,
	}
	owned, owned_open, _ := buffer_session_find_file(buffer_ctx, owned_path)
	external, external_open, _ := buffer_session_find_file(buffer_ctx, external_path)
	testing.expect(t, owned_open && external_open)
	if !owned_open || !external_open {
		return
	}
	project_operations_append(t, &session, owned.entry, "!")
	project_operations_append(t, &session, external.entry, "!")

	saved, saved_ok, save_failure := project_save_buffers(ctx)
	testing.expectf(t, saved_ok, "Project save failed: %v", save_failure.code)
	testing.expect_value(t, saved.examined_buffers, u32(1))
	testing.expect_value(t, saved.modified_buffers, u32(1))
	testing.expect_value(t, saved.saved_buffers, u32(1))
	owned_bytes, owned_read_error := os.read_entire_file(owned_path, context.allocator)
	external_bytes, external_read_error := os.read_entire_file(external_path, context.allocator)
	testing.expect(t, owned_read_error == nil && external_read_error == nil)
	if owned_read_error == nil && external_read_error == nil {
		testing.expect_value(t, string(owned_bytes), "owned!")
		testing.expect_value(t, string(external_bytes), "external")
		delete(external_bytes)
		delete(owned_bytes)
	}

	closed, closed_ok, close_failure := project_close_buffers(ctx)
	testing.expectf(t, closed_ok, "Project close failed: %v", close_failure.code)
	testing.expect_value(t, closed.outcome, Project_Close_Outcome.Completed)
	testing.expect_value(t, closed.closed_buffers, u32(1))
	usage, usage_ok, _ := editor_session.session_usage(&session, handle)
	testing.expect(t, usage_ok)
	testing.expect_value(t, usage.live_buffers, u32(1))

	reopened, reopened_ok, _ := buffer_session_find_file(buffer_ctx, owned_path)
	testing.expect(t, reopened_ok)
	if reopened_ok {
		project_operations_append(t, &session, reopened.entry, "?")
		decision, decision_ok, _ := project_close_buffers(ctx)
		testing.expect(t, decision_ok)
		testing.expect_value(t, decision.outcome, Project_Close_Outcome.Decision_Required)
		testing.expect_value(t, decision.decision_entry, reopened.entry)
		authorities := [1]editor_session.Close_Buffer_Request{{
			entry = reopened.entry,
			authority = .Discard_Modified,
		}}
		discarded, discarded_ok, _ := project_close_buffers(ctx, authorities[:])
		testing.expect(t, discarded_ok)
		testing.expect_value(t, discarded.outcome, Project_Close_Outcome.Completed)
		testing.expect_value(t, discarded.closed_buffers, u32(1))
	}

	refresh: Project_Refresh_State
	refresh_initialized, refresh_failure := project_refresh_init(ctx, &refresh)
	testing.expectf(t, refresh_initialized, "refresh init failed: %v", refresh_failure.code)
	if refresh_initialized {
		progress: project.Reconcile_Result
		for !progress.published {
			advanced: bool
			failure: Failure_Context
			progress, advanced, failure = project_refresh_advance(ctx, &refresh)
			testing.expectf(t, advanced, "refresh failed: %v", failure.code)
			if !advanced {
				break
			}
		}
		testing.expect(t, progress.published)
		requested, request_failure := project_refresh_request(ctx, &refresh)
		testing.expectf(t, requested, "refresh request failed: %v", request_failure.code)
		project_refresh_close(&refresh)
	}

	buffer_session_test_release(t, &session, external.entry)
	session_closed, session_failure := editor_session.session_close(&session)
	testing.expectf(t, session_closed, "session close failed: %v", session_failure.code)
}

@(private)
project_operations_append :: proc(
	t: ^testing.T,
	session: ^editor_session.Session,
	entry: editor_session.Entry_Handle,
	text: string,
) {
	access, access_ok, _ := editor_session.session_entry_access(session, entry)
	borrow, borrowed, _ := editor_session.entry_access_borrow(access)
	testing.expect(t, access_ok && borrowed)
	if !borrowed {
		return
	}
	stats, stats_ok, _ := editor.buffer_stats(borrow.buffer)
	position, position_ok, _ := editor.buffer_position(borrow.buffer, editor.Byte_Offset(stats.text_bytes))
	_, _, changed, _ := editor.buffer_splice(
		borrow.buffer,
		editor.Splice{start = position, end = position, replacement = text},
		context.temp_allocator,
	)
	testing.expect(t, stats_ok && position_ok && changed)
	_, reconciled, _ := editor_session.entry_access_reconcile(access)
	testing.expect(t, reconciled)
}
