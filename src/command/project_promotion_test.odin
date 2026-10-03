// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../editor_session"
import "../hosting"
import "../interaction"
import "core:os"
import "core:testing"

/* verify_explicit_dir_promotion covers durable identity and exact root replacement. */
@(private)
verify_explicit_dir_promotion :: proc(t: ^testing.T, racket_runtime: ^hosting.Runtime) {
	workspace, workspace_error := os.make_directory_temp(
		"",
		"odra-command-project-promotion-*",
		context.allocator,
	)
	testing.expect(t, workspace_error == nil)
	if workspace_error != nil {
		return
	}
	defer {
		os.remove_all(workspace)
		delete(workspace)
	}
	dir, dir_error := os.join_path({workspace, "source"}, context.allocator)
	configuration_root, configuration_error := os.join_path(
		{workspace, "config", "odra"},
		context.allocator,
	)
	testing.expect(t, dir_error == nil && configuration_error == nil)
	if dir_error != nil || configuration_error != nil {
		return
	}
	defer {
		delete(configuration_root)
		delete(dir)
	}
	testing.expect(t, os.make_directory(dir) == nil)

	session: editor_session.Session
	handle, initialized, _ := editor_session.session_init(
		&session,
		editor_session.Session_ID(1821),
		editor_session.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	testing.expect(t, initialized)
	if !initialized {
		return
	}
	defer editor_session.session_close(&session)
	_, roots_ready, roots_failure := editor_session.session_roots_replace(
		&session,
		editor_session.Root_Replace_Request {
			session = handle,
			roots = []editor_session.Root_Proposal{{kind = .Dir, path = dir}},
		},
	)
	testing.expectf(t, roots_ready, "Dir root failed: %v", roots_failure.code)
	if !roots_ready {
		return
	}
	ctx := Project_Command_Context {
		session = &session,
		handle = handle,
		command = interaction.Command_Handle {
			registry_generation = interaction.Registry_Generation(1),
			slot = 1,
			entry_generation = 1,
		},
		persistent_allocator = context.allocator,
		temporary_allocator = context.temp_allocator,
	}
	result, promoted, promotion_failure := project_promote(
		ctx,
		racket_runtime,
		configuration_root,
		dir,
		"Editable Project",
	)
	testing.expectf(t, promoted, "Project promotion failed: %v", promotion_failure.code)
	if !promoted {
		return
	}
	testing.expect(t, !result.reconciled)
	testing.expect_value(t, result.roots.root_count, u32(1))
	active, active_ok, _ := editor_session.session_active_project(&session, handle)
	testing.expect(t, active_ok && active.active)
	if active_ok && active.active {
		testing.expect(t, !active.descriptor.temporary)
		testing.expect_value(t, active.descriptor.trusted_directories, u32(0))
	}
	roots, listed, _ := editor_session.session_roots(&session, handle)
	testing.expect(t, listed)
	if listed {
		testing.expect_value(t, roots.descriptors[0].kind, editor_session.Root_Kind.Project)
		testing.expect_value(t, roots.descriptors[0].path, dir)
		editor_session.root_batch_close(&roots)
	}
	local_record, local_error := os.join_path({dir, ".odra", "project.rkt"}, context.allocator)
	testing.expect(t, local_error == nil)
	if local_error == nil {
		defer delete(local_record)
		testing.expect(t, os.is_file(local_record))
	}
}

/* verify_promotion_suppression_round_trip covers reversible exact-Dir preferences. */
@(private)
verify_promotion_suppression_round_trip :: proc(t: ^testing.T, racket_runtime: ^hosting.Runtime) {
	workspace, workspace_error := os.make_directory_temp(
		"",
		"odra-command-promotion-suppression-*",
		context.allocator,
	)
	testing.expect(t, workspace_error == nil)
	if workspace_error != nil {
		return
	}
	defer {
		os.remove_all(workspace)
		delete(workspace)
	}
	dir, dir_error := os.join_path({workspace, "source"}, context.allocator)
	configuration_root, configuration_error := os.join_path(
		{workspace, "config", "odra"},
		context.allocator,
	)
	testing.expect(t, dir_error == nil && configuration_error == nil)
	if dir_error != nil || configuration_error != nil {
		return
	}
	defer {
		delete(configuration_root)
		delete(dir)
	}
	testing.expect(t, os.make_directory(dir) == nil)

	absent, inspected, inspect_failure := project_promotion_suppression(
		racket_runtime,
		configuration_root,
		dir,
		.Inspect,
	)
	testing.expectf(t, inspected, "suppression inspection failed: %v", inspect_failure.code)
	testing.expect(t, !absent.suppressed)
	testing.expect_value(t, absent.generation, u64(0))

	added, added_ok, add_failure := project_promotion_suppression(
		racket_runtime,
		configuration_root,
		dir,
		.Add,
	)
	testing.expectf(t, added_ok, "suppression add failed: %v", add_failure.code)
	testing.expect(t, added.suppressed)
	testing.expect_value(t, added.generation, u64(1))

	restarted, restarted_ok, restart_failure := project_promotion_suppression(
		racket_runtime,
		configuration_root,
		dir,
		.Inspect,
	)
	testing.expectf(t, restarted_ok, "suppression reload failed: %v", restart_failure.code)
	testing.expect(t, restarted.suppressed)
	testing.expect_value(t, restarted.generation, u64(1))

	removed, removed_ok, remove_failure := project_promotion_suppression(
		racket_runtime,
		configuration_root,
		dir,
		.Remove,
	)
	testing.expectf(t, removed_ok, "suppression removal failed: %v", remove_failure.code)
	testing.expect(t, !removed.suppressed)
	testing.expect_value(t, removed.generation, u64(2))
}
