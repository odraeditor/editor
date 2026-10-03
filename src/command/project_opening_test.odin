// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../editor_session"
import "../hosting"
import "../interaction"
import "../project"
import "core:fmt"
import "core:os"
import "core:testing"

/* verify_project_directory_opening covers ordinary Dirs and exact local Projects. */
@(private)
verify_project_directory_opening :: proc(t: ^testing.T, racket_runtime: ^hosting.Runtime) {
	workspace, workspace_error := os.make_directory_temp(
		"",
		"odra-command-project-opening-*",
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
	projects_directory, projects_error := os.join_path({workspace, "projects"}, context.allocator)
	registered_directory, registered_error := os.join_path({workspace, "registered"}, context.allocator)
	unregistered_directory, unregistered_error := os.join_path({workspace, "ordinary"}, context.allocator)
	testing.expect(
		t,
		projects_error == nil && registered_error == nil && unregistered_error == nil,
	)
	if projects_error != nil || registered_error != nil || unregistered_error != nil {
		return
	}
	defer {
		delete(unregistered_directory)
		delete(registered_directory)
		delete(projects_directory)
	}
	testing.expect(t, os.make_directory(projects_directory) == nil)
	testing.expect(t, os.make_directory(registered_directory) == nil)
	testing.expect(t, os.make_directory(unregistered_directory) == nil)

	command_handle := interaction.Command_Handle {
		registry_generation = interaction.Registry_Generation(1),
		slot = 1,
		entry_generation = 1,
	}
	first_session: editor_session.Session
	first_handle, first_initialized, _ := editor_session.session_init(
		&first_session,
		editor_session.Session_ID(1801),
		editor_session.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	testing.expect(t, first_initialized)
	if !first_initialized {
		return
	}
	first_context := Project_Command_Context {
		session = &first_session,
		handle = first_handle,
		command = command_handle,
		persistent_allocator = context.allocator,
		temporary_allocator = context.temp_allocator,
	}
	unregistered, unregistered_ok, unregistered_failure := project_open_directory(
		first_context,
		racket_runtime,
		projects_directory,
		unregistered_directory,
		project.Project_ID(1802),
	)
	testing.expectf(t, unregistered_ok, "unregistered open failed: %v", unregistered_failure.code)
	if unregistered_ok {
		testing.expect_value(t, unregistered.completion, Project_Directory_Open_Completion.Dir)
		testing.expect_value(t, unregistered.roots.root_count, u32(1))
		roots, roots_ok, _ := editor_session.session_roots(&first_session, first_handle)
		testing.expect(t, roots_ok)
		if roots_ok {
			testing.expect_value(t, roots.descriptors[0].kind, editor_session.Root_Kind.Dir)
			testing.expect_value(t, roots.descriptors[0].path, unregistered_directory)
			editor_session.root_batch_close(&roots)
		}
		active, active_ok, _ := editor_session.session_active_project(&first_session, first_handle)
		testing.expect(t, active_ok && !active.active)
		same, same_ok, same_failure := project_open_directory(
			first_context,
			racket_runtime,
			projects_directory,
			unregistered_directory,
			project.Project_ID(1807),
		)
		testing.expectf(t, same_ok, "same-directory open failed: %v", same_failure.code)
		if same_ok {
			testing.expect_value(t, same.completion, Project_Directory_Open_Completion.Already_Active)
			testing.expect_value(t, same.roots.generation, unregistered.roots.generation)
		}
		replacement, replacement_ok, replacement_failure := project_open_directory(
			first_context,
			racket_runtime,
			projects_directory,
			registered_directory,
			project.Project_ID(1808),
		)
		testing.expectf(t, replacement_ok, "replacement open failed: %v", replacement_failure.code)
		if replacement_ok {
			testing.expect_value(t, replacement.completion, Project_Directory_Open_Completion.Dir)
			testing.expect(t, replacement.roots.generation != unregistered.roots.generation)
		}
	}
	first_closed, _ := editor_session.session_close(&first_session)
	testing.expect(t, first_closed)

	write_project_record(t, "registered-a", "Registered A", registered_directory, 7, true)
	second_session: editor_session.Session
	second_handle, second_initialized, _ := editor_session.session_init(
		&second_session,
		editor_session.Session_ID(1803),
		editor_session.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	testing.expect(t, second_initialized)
	if !second_initialized {
		return
	}
	second_context := first_context
	second_context.session = &second_session
	second_context.handle = second_handle
	registered, registered_ok, registered_failure := project_open_directory(
		second_context,
		racket_runtime,
		projects_directory,
		registered_directory,
		project.Project_ID(1804),
	)
	testing.expectf(t, registered_ok, "registered open failed: %v", registered_failure.code)
	if registered_ok {
		testing.expect_value(t, registered.completion, Project_Directory_Open_Completion.Registered)
		testing.expect(t, !registered.activation.active.temporary)
		testing.expect_value(t, registered.activation.active.handle.generation, project.Project_Generation(7))
		testing.expect_value(t, registered.activation.active.trusted_directories, u32(1))
	}
	second_closed, _ := editor_session.session_close(&second_session)
	testing.expect(t, second_closed)

}

@(private)
write_project_record :: proc(
	t: ^testing.T,
	id, name, directory: string,
	generation: u64,
	trusted: bool,
) {
	metadata_directory, metadata_error := os.join_path({directory, ".odra"}, context.allocator)
	testing.expect(t, metadata_error == nil)
	if metadata_error != nil {
		return
	}
	defer delete(metadata_directory)
	testing.expect(t, os.make_directory(metadata_directory) == nil)
	path, path_error := os.join_path({metadata_directory, "project.rkt"}, context.allocator)
	testing.expect(t, path_error == nil)
	if path_error != nil {
		return
	}
	defer delete(path)
	trust := "trusted" if trusted else "untrusted"
	module := fmt.aprintf(
		"#lang odra/config\n(local-project\n #:format-version 2\n #:id %q\n #:generation %d\n #:name %q\n #:root %q\n #:trust %s)\n",
		id,
		generation,
		name,
		directory,
		trust,
	)
	defer delete(module)
	testing.expect(t, os.write_entire_file(path, module) == nil)
}
