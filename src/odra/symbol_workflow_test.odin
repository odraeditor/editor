// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../command"
import "../editor_session"
import "../interaction"
import "../result_set"
import editor_view "../view"
import "core:os"
import "core:strings"
import "core:testing"

/* Verifies symbol navigation publishes, filters, refreshes, visits, and retains return state. */
@(test)
symbol_navigator_uses_common_result_navigation :: proc(t: ^testing.T) {
	directory, directory_error := os.make_directory_temp("", "odra-symbol-navigation-*", context.allocator)
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
	source_text := "package main\n\nouter :: proc() {\n\tinner := proc() {}\n\t_ = inner\n}\n"
	testing.expect(t, os.write_entire_file(path, source_text) == nil)

	session: editor_session.Session
	handle, session_ok, _ := editor_session.session_init(
		&session,
		editor_session.Session_ID(9_201),
		editor_session.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	testing.expect(t, session_ok)
	if !session_ok do return
	defer session_shutdown_close(&session, handle)
	opened, open_ok, _ := editor_session.session_open_path(
		&session,
		editor_session.Open_Path_Request {
			session = handle,
			path = path,
			encoding = .UTF8,
			configuration = editor_session.DEFAULT_ENTRY_CONFIGURATION,
		},
	)
	testing.expect(t, open_ok)
	if !open_ok do return

	syntax, syntax_error := new(Syntax_Workflow_State, context.allocator)
	testing.expect(t, syntax_error == nil)
	if syntax_error != nil do return
	defer free(syntax, context.allocator)
	syntax_ok, _ := syntax_workflow_init(syntax)
	testing.expect(t, syntax_ok)
	if !syntax_ok do return
	defer syntax_workflow_close(syntax)
	reconciled, _ := syntax_workflow_reconcile(syntax, &session, handle)
	testing.expect(t, reconciled)
	maintained, maintenance_failure := syntax_workflow_maintain(syntax, &session, handle)
	testing.expectf(t, maintained, "syntax maintenance failed with %v", maintenance_failure.code)
	if !maintained do return

	location_history: command.Location_History
	commands := Command_Context {
		session_owner = &session,
		session_handle = handle,
		current_entry = opened.entry,
		location_history = &location_history,
		syntax_workflow = syntax,
		persistent_allocator = context.allocator,
		temporary_allocator = context.temp_allocator,
	}
	access, accessible, _ := editor_session.session_entry_access(&session, opened.entry)
	entry, borrowed, _ := editor_session.entry_access_borrow(access)
	testing.expect(t, accessible && borrowed)
	if !accessible || !borrowed do return
	view, published, publish_failure := command_context_publish_symbols(&commands, entry, 0)
	testing.expectf(t, published, "symbol publication failed at %v", publish_failure.stage)
	if !published do return
	testing.expect_value(t, view.source.kind, result_set.Source_Kind.Language_Symbols)
	testing.expect(t, len(view.locations) >= 2)
	function_found := false
	container_found := false
	for location in view.locations {
		if strings.contains(location.annotation, "function") do function_found = true
		if strings.contains(location.annotation, "outer") do container_found = true
	}
	testing.expect(t, function_found)
	testing.expect(t, container_found)

	candidate_source, built, _ := interaction.result_candidate_source_build(
		view,
		1,
		context.temp_allocator,
	)
	testing.expect(t, built)
	if !built do return
	defer interaction.result_candidate_source_close(&candidate_source)
	candidate_session: interaction.Candidate_Session
	_, initialized, _ := interaction.candidate_session_init(
		&candidate_session,
		{
			session_id = 1,
			limits = interaction.DEFAULT_CANDIDATE_LIMITS,
			persistent_allocator = context.allocator,
			temporary_allocator = context.temp_allocator,
		},
		candidate_source.definition,
	)
	testing.expect(t, initialized)
	if !initialized do return
	defer interaction.candidate_session_close(&candidate_session)
	candidate_view, _, _ := interaction.candidate_session_view(&candidate_session)
	_, filtered, _ := interaction.candidate_session_set_query(
		&candidate_session,
		{session_id = candidate_view.session_id, session_generation = candidate_view.session_generation},
		"inner",
	)
	testing.expect(t, filtered)
	candidate_view, _, _ = interaction.candidate_session_view(&candidate_session)
	testing.expect_value(t, len(candidate_view.rows), 1)

	commands.candidate_ui.return_target = {
		kind = .Primary_View,
		entry = opened.entry,
	}
	visited := command_context_visit_result(&commands, candidate_view.rows[0].action)
	testing.expect(t, visited)
	history_count, history_ok := command.location_history_count(&location_history)
	testing.expect(t, history_ok)
	testing.expect_value(t, history_count, u16(1))
	logical, viewed, _ := editor_view.snapshot(entry.view_registry, entry.primary_view)
	testing.expect(t, viewed)
	testing.expect(t, logical.point_position.byte_offset > 0)

	_, selected, _ := result_set.registry_select(
		command_context_symbol_registry(&commands),
		view.set_id,
		view.generation,
		view.locations[0].id,
	)
	testing.expect(t, selected)
	refreshed, refresh_ok, _ := command_context_publish_symbols(&commands, entry, view.generation)
	testing.expect(t, refresh_ok)
	testing.expect_value(t, refreshed.generation, view.generation + 1)
	testing.expect(t, refreshed.has_selection)
	testing.expect_value(t, refreshed.locations[refreshed.selected_index].id, view.locations[0].id)
}

@(private)
command_context_symbol_registry :: proc(commands: ^Command_Context) -> ^result_set.Registry {
	registry, ok, _ := editor_session.session_result_registry(commands.session_owner, commands.session_handle)
	assert(ok)
	return registry
}
