// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../editor_session"
import "../hosting"
import "../interaction"
import "../project"
import "core:os"
import "core:testing"

/* verify_workspace_commands covers create, open, update, list, and inspect through hosting. */
@(private)
verify_workspace_commands :: proc(t: ^testing.T, racket_runtime: ^hosting.Runtime) {
	home, home_error := os.make_directory_temp("", "odra-command-workspace-*", context.allocator)
	testing.expect(t, home_error == nil)
	if home_error != nil {
		return
	}
	defer {os.remove_all(home); delete(home)}
	first, first_error := os.join_path({home, "first"}, context.allocator)
	second, second_error := os.join_path({home, "second"}, context.allocator)
	configuration_root, configuration_error := os.join_path(
		{home, "config", "odra"}, context.allocator,
	)
	testing.expect(t, first_error == nil && second_error == nil && configuration_error == nil)
	if first_error != nil || second_error != nil || configuration_error != nil {
		return
	}
	defer {delete(first); delete(second); delete(configuration_root)}
	testing.expect(t, os.make_directory(first) == nil)
	testing.expect(t, os.make_directory(second) == nil)
	first_id, first_promoted := workspace_test_promote(
		t, racket_runtime, configuration_root, first, "First Project", 8_101,
	)
	second_id, second_promoted := workspace_test_promote(
		t, racket_runtime, configuration_root, second, "Second Project", 8_102,
	)
	if !first_promoted || !second_promoted {
		return
	}

	session: editor_session.Session
	handle, initialized, _ := editor_session.session_init(
		&session,
		editor_session.Session_ID(8_103),
		editor_session.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	testing.expect(t, initialized)
	if !initialized {
		return
	}
	ctx := workspace_test_context(&session, handle)
	members := [2]editor_session.Workspace_Project_Proposal {
		{
			project_id = project.Project_ID(81_011),
			project_generation = project.Project_Generation(1),
			durable_id = project.project_durable_id_text(&first_id),
			name = "First Project",
			root = first,
			trust = .Untrusted,
		},
		{
			project_id = project.Project_ID(81_012),
			project_generation = project.Project_Generation(1),
			durable_id = project.project_durable_id_text(&second_id),
			name = "Second Project",
			root = second,
			trust = .Untrusted,
		},
	}
	prepared: editor_session.Workspace_Activation_Preparation
	prepared_ok, _ := editor_session.session_prepare_workspace_activation(
		&session,
		editor_session.Workspace_Activation_Proposal {
			session = handle,
			id = "temporary-composition",
			generation = 1,
			name = "Temporary Composition",
			projects = members[:],
		},
		&prepared,
	)
	testing.expect(t, prepared_ok)
	_, admitted, _ := editor_session.session_admit_workspace_activation(&session, &prepared)
	testing.expect(t, admitted)
	if !admitted {
		editor_session.session_abort_workspace_activation(&prepared)
		editor_session.session_close(&session)
		return
	}

	created, created_ok, create_failure := workspace_create(
		ctx, racket_runtime, configuration_root, "Daily Work",
	)
	testing.expectf(t, created_ok, "Workspace create failed: %v", create_failure.code)
	if !created_ok {
		editor_session.session_close(&session)
		return
	}
	testing.expect_value(t, created.completion, Workspace_Command_Completion.Created)
	testing.expect_value(t, len(created.batch.descriptors), 1)
	testing.expect_value(t, len(created.batch.members), 2)
	workspace_id: [editor_session.MAX_WORKSPACE_ID_BYTES]u8
	id := created.batch.descriptors[0].id
	copy(workspace_id[:], transmute([]u8)id)
	id_copy := string(workspace_id[:len(id)])
	testing.expect(t, workspace_command_batch_close(&created.batch))

	listed, listed_ok, _ := workspace_list(ctx, racket_runtime, configuration_root)
	testing.expect(t, listed_ok)
	if listed_ok {
		testing.expect_value(t, listed.completion, Workspace_Command_Completion.Listed)
		testing.expect_value(t, len(listed.batch.descriptors), 1)
		testing.expect_value(t, listed.batch.descriptors[0].id, id_copy)
		workspace_command_batch_close(&listed.batch)
	}
	inspected, inspected_ok, _ := workspace_inspect(ctx, racket_runtime, configuration_root, id_copy)
	testing.expect(t, inspected_ok)
	if inspected_ok {
		testing.expect_value(t, inspected.completion, Workspace_Command_Completion.Inspected)
		testing.expect_value(t, len(inspected.batch.members), 2)
		workspace_command_batch_close(&inspected.batch)
	}
	updated, updated_ok, _ := workspace_update(
		ctx, racket_runtime, configuration_root, id_copy, 1, "Daily Work Updated",
	)
	testing.expect(t, updated_ok)
	if updated_ok {
		testing.expect_value(t, updated.completion, Workspace_Command_Completion.Updated)
		testing.expect_value(t, updated.batch.descriptors[0].generation, u64(2))
		workspace_command_batch_close(&updated.batch)
	}
	closed, _ := editor_session.session_close(&session)
	testing.expect(t, closed)

	reopened_session: editor_session.Session
	reopened_handle, reopened_ready, _ := editor_session.session_init(
		&reopened_session,
		editor_session.Session_ID(8_104),
		editor_session.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	testing.expect(t, reopened_ready)
	if reopened_ready {
		reopened_ctx := workspace_test_context(&reopened_session, reopened_handle)
		reopened, opened_ok, _ := workspace_open(
			reopened_ctx, racket_runtime, configuration_root, id_copy,
		)
		testing.expect(t, opened_ok)
		if opened_ok {
			testing.expect_value(t, reopened.completion, Workspace_Command_Completion.Opened)
			testing.expect_value(t, reopened.activation.workspace.project_count, u32(2))
			workspace_command_batch_close(&reopened.batch)
		}
		closed, _ = editor_session.session_close(&reopened_session)
		testing.expect(t, closed)
	}
}

@(private)
workspace_test_promote :: proc(
	t: ^testing.T,
	racket_runtime: ^hosting.Runtime,
	configuration_root, root, name: string,
	session_id: u64,
) -> (durable_id: project.Project_Durable_ID, ok: bool) {
	session: editor_session.Session
	handle, initialized, _ := editor_session.session_init(
		&session,
		editor_session.Session_ID(session_id),
		editor_session.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	if !initialized {
		return {}, false
	}
	_, roots_ready, _ := editor_session.session_roots_replace(
		&session,
		editor_session.Root_Replace_Request {
			session = handle,
			roots = []editor_session.Root_Proposal{{kind = .Dir, path = root}},
		},
	)
	if !roots_ready {
		editor_session.session_close(&session)
		return {}, false
	}
	result, promoted, promotion_failure := project_promote(
		workspace_test_context(&session, handle),
		racket_runtime,
		configuration_root,
		root,
		name,
	)
	testing.expectf(t, promoted, "Workspace Project promotion failed: %v", promotion_failure.code)
	if promoted {
		durable_id = result.activation.active.durable_id
	}
	closed, _ := editor_session.session_close(&session)
	testing.expect(t, closed)
	return durable_id, promoted && closed
}

@(private)
workspace_test_context :: proc(
	session: ^editor_session.Session,
	handle: editor_session.Session_Handle,
) -> Project_Command_Context {
	return Project_Command_Context {
		session = session,
		handle = handle,
		command = interaction.Command_Handle {
			registry_generation = interaction.Registry_Generation(1),
			slot = 1,
			entry_generation = 1,
		},
		persistent_allocator = context.allocator,
		temporary_allocator = context.temp_allocator,
	}
}
