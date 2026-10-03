// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../editor_session"
import "../interaction"
import "core:os"
import "core:testing"

/* verify_dir_root_commands covers ordered addition, exact removal, and empty publication. */
@(private)
verify_dir_root_commands :: proc(t: ^testing.T) {
	workspace, workspace_error := os.make_directory_temp("", "odra-command-dir-roots-*", context.allocator)
	testing.expect(t, workspace_error == nil)
	if workspace_error != nil {return}
	defer {
		os.remove_all(workspace)
		delete(workspace)
	}
	first, first_error := os.join_path({workspace, "first"}, context.allocator)
	second, second_error := os.join_path({workspace, "second"}, context.allocator)
	testing.expect(t, first_error == nil && second_error == nil)
	if first_error != nil || second_error != nil {return}
	defer {
		delete(second)
		delete(first)
	}
	testing.expect(t, os.make_directory(first) == nil)
	testing.expect(t, os.make_directory(second) == nil)
	session: editor_session.Session
	handle, initialized, _ := editor_session.session_init(
		&session,
		editor_session.Session_ID(1821),
		editor_session.Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, initialized)
	if !initialized {return}
	ctx := Project_Command_Context {
		session = &session,
		handle = handle,
		command = interaction.Command_Handle{registry_generation = 1, slot = 1, entry_generation = 1},
		persistent_allocator = context.allocator,
		temporary_allocator = context.temp_allocator,
	}
	first_result, first_ok, _ := dir_root_add(ctx, first)
	second_result, second_ok, _ := dir_root_add(ctx, second)
	testing.expect(t, first_ok && second_ok)
	testing.expect_value(t, first_result.publication.root_count, u32(1))
	testing.expect_value(t, second_result.publication.root_count, u32(2))
	_, inspected, inspect_failure := project_inspect_active(ctx)
	testing.expect(t, !inspected)
	testing.expect_value(t, inspect_failure.code, Failure_Code.Project_Scope_Required)
	_, project_listed, project_list_failure := project_list_directories(ctx)
	testing.expect(t, !project_listed)
	testing.expect_value(t, project_list_failure.code, Failure_Code.Project_Scope_Required)
	roots, listed, _ := editor_session.session_roots(&session, handle)
	testing.expect(t, listed)
	if listed {
		testing.expect_value(t, roots.descriptors[0].path, first)
		testing.expect_value(t, roots.descriptors[1].path, second)
		editor_session.root_batch_close(&roots)
	}
	removed, removed_ok, _ := dir_root_remove(ctx, first)
	testing.expect(t, removed_ok)
	testing.expect_value(t, removed.publication.root_count, u32(1))
	_, duplicate_ok, _ := dir_root_add(ctx, second)
	testing.expect(t, !duplicate_ok)
	empty, empty_ok, _ := dir_root_remove(ctx, second)
	testing.expect(t, empty_ok)
	testing.expect_value(t, empty.publication.root_count, u32(0))
	closed, _ := editor_session.session_close(&session)
	testing.expect(t, closed)
}
