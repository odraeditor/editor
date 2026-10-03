// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../editor_session"
import "../interaction"
import "../project"
import "core:os"
import "core:testing"

/* Verifies Project navigation candidates remain scoped, deduplicated, and stale-safe. */
@(test)
candidates_follow_active_project :: proc(t: ^testing.T) {
	workspace, workspace_error := os.make_directory_temp("", "odra-command-project-nav-*", context.allocator)
	testing.expect(t, workspace_error == nil)
	if workspace_error != nil {
		return
	}
	defer {
		os.remove_all(workspace)
		delete(workspace)
	}
	owned_directory, _ := os.join_path({workspace, "owned"}, context.allocator)
	nested_directory, _ := os.join_path({owned_directory, "nested"}, context.allocator)
	external_directory, _ := os.join_path({workspace, "external"}, context.allocator)
	owned_path, _ := os.join_path({nested_directory, "owned.txt"}, context.allocator)
	external_path, _ := os.join_path({external_directory, "external.txt"}, context.allocator)
	defer {
		delete(external_path)
		delete(owned_path)
		delete(external_directory)
		delete(nested_directory)
		delete(owned_directory)
	}
	testing.expect(t, os.make_directory_all(nested_directory) == nil)
	testing.expect(t, os.make_directory(external_directory) == nil)
	testing.expect(t, os.write_entire_file(owned_path, "owned") == nil)
	testing.expect(t, os.write_entire_file(external_path, "external") == nil)

	session: editor_session.Session
	handle, initialized, _ := editor_session.session_init(
		&session,
		editor_session.Session_ID(951),
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
		project.Project_ID(952),
		"navigation",
		"Navigation",
		owned_directory,
	)
	testing.expect(t, created)

	buffer_ctx := Buffer_Session_Context{
		session = &session,
		handle = handle,
		command = command_handle,
		configuration = editor_session.DEFAULT_ENTRY_CONFIGURATION,
	}
	owned_entry, owned_open, _ := buffer_session_find_file(buffer_ctx, owned_path)
	external_entry, external_open, _ := buffer_session_find_file(buffer_ctx, external_path)
	testing.expect(t, owned_open && external_open)

	file_search: Project_File_Search
	search_started, start_failure := project_find_file_begin(ctx, &file_search)
	testing.expectf(t, search_started, "search start failed: %v", start_failure.code)
	if search_started {
		progress: project.File_Enumeration_Result
		for !progress.complete {
			advanced: bool
			failure: Failure_Context
			progress, advanced, failure = project_find_file_advance(ctx, &file_search)
			testing.expectf(t, advanced, "search advance failed: %v", failure.code)
			if !advanced {
				break
			}
		}
		candidates, copied, copy_failure := project_find_file_candidates(ctx, &file_search)
		testing.expectf(t, copied, "file candidates failed: %v", copy_failure.code)
		if copied {
			testing.expect_value(t, len(candidates.descriptors), 1)
			testing.expect_value(t, candidates.descriptors[0].path, owned_path)
			testing.expect_value(t, candidates.descriptors[0].membership_count, u32(1))
			project.file_candidate_batch_close(&candidates)
		}
		project_find_file_close(&file_search)
	}

	buffers, buffers_ok, buffer_failure := project_switch_buffer_candidates(ctx)
	testing.expectf(t, buffers_ok, "buffer candidates failed: %v", buffer_failure.code)
	if buffers_ok {
		testing.expect_value(t, len(buffers.candidates), 1)
		testing.expect_value(t, buffers.candidates[0].entry, owned_entry.entry)
		testing.expect_value(t, buffers.candidates[0].path, owned_path)
		project_buffer_candidate_batch_close(&buffers)
	}

	directories, directories_ok, _ := project_find_directory_candidates(ctx)
	testing.expect(t, directories_ok)
	if directories_ok {
		testing.expect_value(t, len(directories.descriptors), 1)
		project.descriptor_batch_close(&directories)
	}

	buffer_session_test_release(t, &session, external_entry.entry)
	buffer_session_test_release(t, &session, owned_entry.entry)
	closed, close_failure := editor_session.session_close(&session)
	testing.expectf(t, closed, "session close failed: %v", close_failure.code)
}
