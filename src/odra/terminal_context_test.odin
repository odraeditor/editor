// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "core:os"
import "core:path/filepath"
import "core:testing"
import "../document"
import "../editor_session"
import "../project"

@(test)
/* Ensures scratch defaults remain instance-scoped and never accept a Workspace override. */
terminal_context_resolves_instance_scratch_default :: proc(t: ^testing.T) {
	fixture, ready := terminal_workflow_fixture_open(t, 9_711)
	testing.expect(t, ready)
	if !ready do return
	defer terminal_workflow_fixture_close(t, &fixture)
	commands := Command_Context {
		session_owner = &fixture.session,
		session_handle = fixture.handle,
		home_directory = "/tmp",
		temporary_allocator = context.temp_allocator,
	}
	resolved, outcome, failure := terminal_context_resolve(
		&commands,
		{purpose = .Default, global_shell = "/bin/sh", workspace_shell = "/invalid/workspace-shell"},
	)
	testing.expect_value(t, failure.code, Terminal_Context_Failure_Code.None)
	testing.expect_value(t, outcome, Terminal_Context_Resolution.Resolved)
	testing.expect_value(t, resolved.scope, Terminal_Context_Scope.Instance)
	testing.expect_value(t, resolved.source, Terminal_Context_Source.Home)
	testing.expect_value(t, resolved.shell_source, Terminal_Shell_Source.Global)
	testing.expect_value(t, terminal_context_directory(&resolved), "/tmp")
	testing.expect_value(t, terminal_context_shell(&resolved), "/bin/sh")
}

@(test)
/* Ensures here resolves only the active document's containing directory. */
terminal_context_resolves_active_resource_directory :: proc(t: ^testing.T) {
	directory, directory_error := os.make_directory_temp("", "odra-terminal-context-*", context.allocator)
	testing.expect(t, directory_error == nil)
	if directory_error != nil do return
	defer {
		os.remove_all(directory)
		delete(directory)
	}
	path, join_error := filepath.join([]string{directory, "active.odin"}, context.temp_allocator)
	testing.expect(t, join_error == nil)
	if join_error != nil do return
	defer delete(path, context.temp_allocator)
	write_error := os.write_entire_file_from_string(path, "package active\n")
	testing.expect(t, write_error == nil)
	if write_error != nil do return
	fixture, ready := terminal_workflow_fixture_open(t, 9_712)
	testing.expect(t, ready)
	if !ready do return
	defer terminal_workflow_fixture_close(t, &fixture)
	_, opened, _ := editor_session.session_open_path(
		&fixture.session,
		{
			session = fixture.handle,
			path = path,
			encoding = document.Encoding_Policy.UTF8,
			configuration = editor_session.DEFAULT_ENTRY_CONFIGURATION,
		},
	)
	testing.expect(t, opened)
	commands := Command_Context {
		session_owner = &fixture.session,
		session_handle = fixture.handle,
		home_directory = "/tmp",
		temporary_allocator = context.temp_allocator,
	}
	resolved, outcome, failure := terminal_context_resolve(
		&commands,
		{purpose = .Here, global_shell = "/bin/sh"},
	)
	testing.expect_value(t, failure.code, Terminal_Context_Failure_Code.None)
	testing.expect_value(t, outcome, Terminal_Context_Resolution.Resolved)
	testing.expect_value(t, resolved.source, Terminal_Context_Source.Resource)
	testing.expect_value(t, terminal_context_directory(&resolved), directory)
}

@(test)
/* Ensures scratch here and invalid filesystem inputs fail before process creation. */
terminal_context_rejects_missing_and_invalid_inputs :: proc(t: ^testing.T) {
	fixture, ready := terminal_workflow_fixture_open(t, 9_713)
	testing.expect(t, ready)
	if !ready do return
	defer terminal_workflow_fixture_close(t, &fixture)
	commands := Command_Context {
		session_owner = &fixture.session,
		session_handle = fixture.handle,
		home_directory = "/not/a/real/odra-directory",
		temporary_allocator = context.temp_allocator,
	}
	_, _, missing_failure := terminal_context_resolve(
		&commands,
		{purpose = .Here, global_shell = "/bin/sh"},
	)
	testing.expect_value(t, missing_failure.code, Terminal_Context_Failure_Code.No_Directory)
	_, _, directory_failure := terminal_context_resolve(
		&commands,
		{purpose = .Default, global_shell = "/bin/sh"},
	)
	testing.expect_value(t, directory_failure.code, Terminal_Context_Failure_Code.Invalid_Directory)
	commands.home_directory = "/tmp"
	_, _, shell_failure := terminal_context_resolve(
		&commands,
		{purpose = .Default, global_shell = "/not/a/real/odra-shell"},
	)
	testing.expect_value(t, shell_failure.code, Terminal_Context_Failure_Code.Invalid_Shell)
}

@(test)
/* Ensures Project context uses containment, then one recent Project, and otherwise asks. */
terminal_context_project_selection_never_chooses_arbitrarily :: proc(t: ^testing.T) {
	first := project.Project_Handle{owner = {id = 1, generation = 1}, id = 11, generation = 1}
	second := project.Project_Handle{owner = {id = 1, generation = 1}, id = 12, generation = 1}
	roots := [3]editor_session.Root_Descriptor {
		{kind = .Project, path = "/work/first", project = first},
		{kind = .Project, path = "/work/second", project = second},
		{kind = .Project, path = "/work/second/nested", project = second},
	}
	directory, handle, outcome := terminal_context_select_project_root(
		roots[:], "/work/second/nested/file.odin", first,
	)
	testing.expect_value(t, outcome, Terminal_Context_Resolution.Resolved)
	testing.expect_value(t, directory, "/work/second/nested")
	testing.expect_value(t, handle, second)
	one := roots[:1]
	directory, handle, outcome = terminal_context_select_project_root(one, "", first)
	testing.expect_value(t, outcome, Terminal_Context_Resolution.Resolved)
	testing.expect_value(t, directory, "/work/first")
	testing.expect_value(t, handle, first)
	_, _, outcome = terminal_context_select_project_root(roots[:], "", second)
	testing.expect_value(t, outcome, Terminal_Context_Resolution.Project_Selection_Required)
	_, _, outcome = terminal_context_select_project_root(roots[:], "", {})
	testing.expect_value(t, outcome, Terminal_Context_Resolution.Project_Selection_Required)
}

@(test)
/* Ensures Workspace shell configuration has deliberate precedence only while active. */
terminal_context_workspace_shell_override_precedence :: proc(t: ^testing.T) {
	shell, source := terminal_context_select_shell(true, "/bin/global", "/bin/workspace")
	testing.expect_value(t, shell, "/bin/workspace")
	testing.expect_value(t, source, Terminal_Shell_Source.Workspace)
	shell, source = terminal_context_select_shell(false, "/bin/global", "/bin/workspace")
	testing.expect_value(t, shell, "/bin/global")
	testing.expect_value(t, source, Terminal_Shell_Source.Global)
}
