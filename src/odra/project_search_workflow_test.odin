// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../command"
import "../editor_session"
import "../result_set"
import "../search"
import "core:os"
import "core:testing"

/* Verifies Project search publishes, refreshes, visits, and invalidates common results. */
@(test)
project_search_uses_common_result_navigation :: proc(t: ^testing.T) {
	directory, directory_error := os.make_directory_temp("", "odra-project-search-*", context.allocator)
	testing.expect(t, directory_error == nil)
	if directory_error != nil do return
	defer {
		os.remove_all(directory)
		delete(directory)
	}
	path, path_error := os.join_path({directory, "main.odin"}, context.allocator)
	testing.expect(t, path_error == nil)
	if path_error != nil do return
	defer delete(path)
	testing.expect(t, os.write_entire_file(path, "package main\nneedle := 1\n") == nil)

	session: editor_session.Session
	handle, session_ok, _ := editor_session.session_init(
		&session,
		9_401,
		{persistent = context.allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, session_ok)
	if !session_ok do return
	defer session_shutdown_close(&session, handle)
	activation, project_ok, project_failure := editor_session.session_open_project_directory(
		&session,
		{
			session = handle,
			expected_catalog_generation = 1,
			actual_catalog_generation = 1,
			normalized_path = directory,
			matching_projects = 1,
			project_id = 1,
			project_generation = 1,
			durable_id = "project-search-test",
			name = "Project search test",
			trust = .Untrusted,
		},
	)
	testing.expectf(t, project_ok, "Project setup failed: %v", project_failure.code)
	if !project_ok do return
	_, roots_ok, _ := editor_session.session_roots_replace(
		&session,
		{
			session = handle,
			roots = []editor_session.Root_Proposal {{
				kind = .Project,
				path = directory,
				project = activation.active.handle,
			}},
		},
	)
	testing.expect(t, roots_ok)
	if !roots_ok do return

	location_history, history_error := new(command.Location_History, context.allocator)
	testing.expect(t, history_error == nil)
	if history_error != nil do return
	commands := Command_Context {
		session_owner = &session,
		session_handle = handle,
		entry_configuration = editor_session.DEFAULT_ENTRY_CONFIGURATION,
		location_history = location_history,
		persistent_allocator = context.allocator,
		temporary_allocator = context.temp_allocator,
	}
	defer command_context_close(&commands)
	result, run_failure := command_context_run_project_search(
		&commands,
		"needle",
		search.Pattern_Kind.Literal,
		{},
		0,
		false,
	)
	testing.expectf(t, run_failure.stage == .None, "Project search failed: %v", run_failure.stage)
	testing.expect(t, result.changed)
	registry, registry_ok, _ := editor_session.session_result_registry(&session, handle)
	testing.expect(t, registry_ok)
	if !registry_ok do return
	view, viewed, _ := result_set.registry_view(registry, PROJECT_SEARCH_RESULT_SET_ID)
	testing.expect(t, viewed)
	if !viewed do return
	testing.expect_value(t, view.source.kind, result_set.Source_Kind.Project_Search)
	testing.expect_value(t, len(view.locations), 1)
	first_generation := view.generation
	first_identity := view.locations[0].source_identity
	_, selected, _ := result_set.registry_select(
		registry, view.set_id, view.generation, view.locations[0].id,
	)
	testing.expect(t, selected)

	_, refresh_failure := command_context_run_project_search(
		&commands,
		"needle",
		search.Pattern_Kind.Literal,
		{},
		view.generation,
		false,
	)
	testing.expect_value(t, refresh_failure.stage, App_Stage.None)
	refreshed, refreshed_ok, _ := result_set.registry_view(registry, PROJECT_SEARCH_RESULT_SET_ID)
	testing.expect(t, refreshed_ok)
	testing.expect_value(t, refreshed.generation, first_generation + 1)
	testing.expect(t, refreshed.has_selection)
	testing.expect_value(t, refreshed.locations[refreshed.selected_index].source_identity, first_identity)
	testing.expect(t, command_context_move_project_search_location(
		&commands,
		refreshed.locations[0],
		{},
	))

	os.remove_all(directory)
	_, unavailable_failure := command_context_run_project_search(
		&commands,
		"needle",
		search.Pattern_Kind.Literal,
		{},
		refreshed.generation,
		false,
	)
	testing.expect_value(t, unavailable_failure.stage, App_Stage.None)
	retained, retained_ok, _ := result_set.registry_view(registry, PROJECT_SEARCH_RESULT_SET_ID)
	testing.expect(t, retained_ok)
	testing.expect_value(t, retained.generation, refreshed.generation)
	testing.expect(t, !command_context_move_project_search_location(
		&commands,
		retained.locations[0],
		{},
	))

	command_context_project_search_invalidate(&commands)
	_, still_retained, _ := result_set.registry_view(registry, PROJECT_SEARCH_RESULT_SET_ID)
	testing.expect(t, !still_retained)
	_, active_source, _ := editor_session.session_active_location_source(&session, handle)
	testing.expect(t, !active_source)
	_, repeated_failure := command_context_repeat_project_search(&commands, {})
	testing.expect_value(t, repeated_failure.stage, App_Stage.None)
}
