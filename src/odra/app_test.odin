// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../command"
import "../display"
import "../document"
import "../editor"
import "../editor_session"
import "../interaction"
import "../history"
import "../kill_ring"
import "../layout"
import "../project"
import "../search"
import "../ui"
import terminal "../terminal"
import editor_view "../view"
import "core:os"
import "core:strings"
import "core:testing"
import "core:time"

/* Verifies shutdown closes a session whose published UI root contains no editing entry. */
@(test)
session_shutdown_closes_an_empty_ui_root :: proc(t: ^testing.T) {
	session: editor_session.Session
	handle, initialized, _ := editor_session.session_init(
		&session,
		editor_session.Session_ID(9001),
		editor_session.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	testing.expect(t, initialized)
	_, _, presented, _ := editor_session.session_present_ui(
		&session,
		handle,
		startup_visible_target().ui,
	)
	testing.expect(t, presented)
	shutdown_failure := session_shutdown_close(&session, handle)
	testing.expect_value(t, shutdown_failure.stage, App_Stage.None)
}

/* Verifies interactive pane diagnostics retain operation, identity, bounds, and owner causes. */
@(test)
layout_diagnostics_are_bounded :: proc(t: ^testing.T) {
	commands: Command_Context
	command_context_layout_failure_diagnostic(
		&commands,
		"Pane command rejected",
		layout.Failure_Context {
			code = .Operating_Minimum,
			operation = .Resize,
			layout = {owner_id = 31, layout_id = 32, generation = 33},
			pane = {
				layout = {owner_id = 31, layout_id = 32, generation = 33},
				pane_id = 34,
			},
			maximum = 40,
			actual = 20,
			view_failure = editor_view.Failure_Context {
				code = .Editor_Failure,
				editor_failure = editor.Failure_Context{code = .Stale_Revision},
			},
			session_failure = editor_session.Failure_Context {
				code = .View_Failure,
				view_failure = editor_view.Failure_Context{code = .Active_Preparation},
			},
			display_policy_generation = 35,
			display_action_index = 2,
			hook = {hook_id = 36},
			deferred_sequence = 37,
		},
	)
	diagnostic := string(commands.diagnostic[:commands.diagnostic_length])
	testing.expect(t, strings.contains(diagnostic, "Operating_Minimum during Resize"))
	testing.expect(t, strings.contains(diagnostic, "layout 31:32@33, pane 34"))
	testing.expect(t, strings.contains(diagnostic, "limit 40, actual 20"))
	testing.expect(t, strings.contains(diagnostic, "view Editor_Failure/Stale_Revision"))
	testing.expect(t, strings.contains(diagnostic, "session View_Failure/Active_Preparation"))
	testing.expect(t, strings.contains(diagnostic, "policy 35/2, hook 36, deferred 37"))
	testing.expect(t, commands.diagnostic_length <= len(commands.diagnostic))
}

/* Verifies personal-package failures remain readable editor outcomes. */
@(test)
personal_command_failures_are_contained :: proc(t: ^testing.T) {
	test_cases := [?]struct {
		name:       string,
		failure:    command.Failure_Context,
		expected:   string,
	} {
		{
			name = "package rejection preserves its diagnostic",
			failure = {
				code = .Command_Rejected,
				diagnostic = "Select a node title before inserting a Roman link.",
			},
			expected = "Select a node title before inserting a Roman link.",
		},
		{
			name = "empty rejection receives a readable fallback",
			failure = {code = .Command_Rejected},
			expected = "Package command rejected the request",
		},
		{
			name = "package exception remains non-fatal",
			failure = {code = .Racket_Exception},
			expected = "Package command failed",
		},
		{
			name = "stale package context remains non-fatal",
			failure = {code = .Capability_Failure},
			expected = "Package command is unavailable",
		},
	}
	for test_case in test_cases {
		commands: Command_Context
		contained := command_context_contain_personal_command_failure(
			&commands,
			.Personal,
			test_case.failure,
		)
		testing.expectf(t, contained, "%s was not contained", test_case.name)
		diagnostic := string(commands.diagnostic[:commands.diagnostic_length])
		testing.expect_value(t, diagnostic, test_case.expected)
		testing.expect(t, commands.diagnostic_length <= len(commands.diagnostic))
		for value in transmute([]u8)diagnostic do testing.expect(t, value != 0)
	}
	commands: Command_Context
	testing.expect(
		t,
		!command_context_contain_personal_command_failure(
			&commands,
			.Transaction,
			{code = .Racket_Exception},
		),
	)
}

/* Verifies lazy layout ownership, external shrink recovery, allowlisting, and normal resumption. */
@(test)
layout_keeps_tree_on_small_geometry :: proc(t: ^testing.T) {
	buffer: editor.Buffer
	buffer_ok, _ := editor.buffer_init(
		&buffer,
		editor.Buffer_ID(701),
		"alpha\nbeta",
		editor.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	testing.expect(t, buffer_ok)
	if !buffer_ok {
		return
	}
	views: editor_view.Registry
	views_ok, _ := editor_view.registry_init(&views, editor_view.Registry_ID(701), context.allocator)
	testing.expect(t, views_ok)
	if !views_ok {
		editor.buffer_close(&buffer)
		return
	}
	root_view, view_ok, _ := editor_view.create(&views, &buffer)
	testing.expect(t, view_ok)
	if !view_ok {
		editor_view.registry_close(&views)
		editor.buffer_close(&buffer)
		return
	}
	commands := Command_Context {
		current_entry = editor_session.Entry_Handle {
			registry = editor_session.Registry_Handle {
				session = editor_session.Session_Handle{session_id = 1, generation = 1},
				generation = 1,
			},
			entry_id = 1,
			generation = 1,
		},
	}
	defer {
		command_context_layout_close(&commands)
		editor_view.close(&views, &root_view)
		editor_view.registry_close(&views)
		editor.buffer_close(&buffer)
	}
	ensure_failure := command_context_layout_ensure(
		&commands,
		&views,
		root_view,
		display.Viewport_Constraints{width_cells = 40, height_rows = 12},
	)
	testing.expect_value(t, ensure_failure.stage, App_Stage.None)
	handle, _, _ := layout.registry_handle(&commands.layout_registry)
	initial, _, _ := layout.registry_snapshot(&commands.layout_registry, handle)
	first_split, first_ok, _ := layout.registry_split_right(
		&commands.layout_registry,
		initial.active_pane,
	)
	second_split, second_ok, _ := layout.registry_split_below(
		&commands.layout_registry,
		first_split.original,
	)
	testing.expect(t, first_ok && second_ok)
	shrink_failure := command_context_layout_resize(
		&commands,
		display.Viewport_Constraints{width_cells = 1, height_rows = 1},
	)
	testing.expect_value(t, shrink_failure.stage, App_Stage.None)
	testing.expect(t, command_context_layout_is_insufficient(&commands))
	handle, _, _ = layout.registry_handle(&commands.layout_registry)
	insufficient, _, _ := layout.registry_snapshot(&commands.layout_registry, handle)
	testing.expect_value(t, insufficient.pane_count, u16(3))
	testing.expect_value(t, insufficient.geometry_state, layout.Geometry_State.Insufficient)
	testing.expect(
		t,
		command_context_recovery_route_is_allowed(command.native_route(.Close_Pane)),
	)
	testing.expect(
		t,
		!command_context_recovery_route_is_allowed(command.native_route(.Focus_Next_Pane)),
	)
	grow_failure := command_context_layout_resize(
		&commands,
		display.Viewport_Constraints{width_cells = 40, height_rows = 12},
	)
	testing.expect_value(t, grow_failure.stage, App_Stage.None)
	testing.expect(t, !command_context_layout_is_insufficient(&commands))
	handle, _, _ = layout.registry_handle(&commands.layout_registry)
	recovered, _, _ := layout.registry_snapshot(&commands.layout_registry, handle)
	testing.expect_value(t, recovered.handle.generation, layout.Layout_Generation(u64(second_split.layout.generation) + 2))
	testing.expect_value(t, recovered.pane_count, u16(3))
}

/* Verifies buffer candidates preserve selecting and display-only other-pane focus semantics. */
@(test)
other_pane_workflows_share_policy :: proc(t: ^testing.T) {
	directory, directory_error := os.make_directory_temp("", "odra-other-pane-*", context.allocator)
	testing.expect(t, directory_error == nil)
	if directory_error != nil {
		return
	}
	defer {
		os.remove_all(directory)
		delete(directory)
	}
	path, path_error := os.join_path({directory, "opened.txt"}, context.allocator)
	testing.expect(t, path_error == nil)
	if path_error != nil {
		return
	}
	defer delete(path)
	testing.expect(t, os.write_entire_file(path, "opened in another pane") == nil)

	fixture: Interaction_Fixture
	if !interaction_fixture_init(t, &fixture, "unused") {
		return
	}
	activation: interaction.Profile_Activation
	if !modal_navigation_test_activate(t, &fixture, &activation) do return
	session: editor_session.Session
	handle, session_ok, _ := editor_session.session_init(
		&session,
		editor_session.Session_ID(703),
		editor_session.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	testing.expect(t, session_ok)
	if !session_ok {
		interaction.profile_activation_close(&activation)
		interaction_fixture_close(&fixture)
		return
	}
	defer {
		command_context_close(&fixture.commands)
		shutdown_failure := session_shutdown_close(&session, handle)
		testing.expect_value(t, shutdown_failure.stage, App_Stage.None)
		fixture.commands.session_owner = nil
		interaction_fixture_close(&fixture)
	}
	defer interaction.profile_activation_close(&activation)
	first, first_ok, _ := editor_session.session_create_buffer(
		&session,
		editor_session.Create_Buffer_Request {
			session = handle,
			name = "first",
			configuration = editor_session.DEFAULT_ENTRY_CONFIGURATION,
		},
	)
	second, second_ok, _ := editor_session.session_create_buffer(
		&session,
		editor_session.Create_Buffer_Request {
			session = handle,
			name = "second",
			configuration = editor_session.DEFAULT_ENTRY_CONFIGURATION,
		},
	)
	third, third_ok, _ := editor_session.session_create_buffer(
		&session,
		editor_session.Create_Buffer_Request {
			session = handle,
			name = "third",
			configuration = editor_session.DEFAULT_ENTRY_CONFIGURATION,
		},
	)
	testing.expect(t, first_ok && second_ok && third_ok)
	if !first_ok || !second_ok || !third_ok {
		return
	}
	_, activated, _ := editor_session.session_activate(&session, first.entry)
	testing.expect(t, activated)
	fixture.commands.session_owner = &session
	fixture.commands.session_handle = handle
	fixture.commands.entry_configuration = editor_session.DEFAULT_ENTRY_CONFIGURATION
	fixture.commands.candidate_ui.next_session_id = 1
	fixture.commands.candidate_ui.next_source_generation = 1
	fixture.commands.home_directory = directory
	access, accessed, _ := editor_session.session_entry_access(&session, first.entry)
	borrow, borrowed, _ := editor_session.entry_access_borrow(access)
	testing.expect(t, accessed && borrowed)
	if !accessed || !borrowed {
		return
	}
	command_context_bind_entry(&fixture.commands, first.entry, borrow)
	constraints := display.Viewport_Constraints{width_cells = 80, height_rows = 24}
	ensure_failure := command_context_layout_ensure(
		&fixture.commands,
		borrow.view_registry,
		borrow.primary_view,
		constraints,
	)
	testing.expect_value(t, ensure_failure.stage, App_Stage.None)

	switch_command, switch_found, _ := interaction.command_lookup(
		&fixture.command_registry,
		"switch-to-buffer-other-pane",
	)
	testing.expect(t, switch_found)
	_, present_failure := command_context_present_buffer_navigation(
		&fixture.commands,
		constraints,
		switch_command,
	)
	testing.expect_value(t, present_failure.stage, App_Stage.None)
	_, command_entry_failure := dispatch_session_input(
		&fixture.commands,
		&session,
		handle,
		interaction.Input {
			kind = .Key,
			stroke = {
				kind = .Unicode_Scalar,
				scalar = 'x',
				modifiers = {.Meta},
			},
		},
		constraints,
	)
	testing.expectf(
		t,
		command_entry_failure.stage == .None,
		"command entry failed at %v with interaction %v",
		command_entry_failure.stage,
		command_entry_failure.interaction.code,
	)
	command_view, command_viewed, _ := interaction.candidate_session_view(
		&fixture.commands.candidate_ui.session,
	)
	testing.expect(t, command_viewed)
	if command_viewed {
		testing.expect_value(t, command_view.source_kind, interaction.Candidate_Source_Kind.Commands)
	}
	_, command_leave_failure := dispatch_session_input(
		&fixture.commands,
		&session,
		handle,
		interaction.Input {
			kind = .Key,
			stroke = {
				kind = .Unicode_Scalar,
				scalar = 'g',
				modifiers = {.Control},
			},
		},
		constraints,
	)
	testing.expect_value(t, command_leave_failure.stage, App_Stage.None)
	_, present_failure = command_context_present_buffer_navigation(
		&fixture.commands,
		constraints,
		switch_command,
	)
	testing.expect_value(t, present_failure.stage, App_Stage.None)
	_, query_failure := dispatch_session_input(
		&fixture.commands,
		&session,
		handle,
		interaction.Input{kind = .Text_Commit, text = "second"},
		constraints,
	)
	testing.expect_value(t, query_failure.stage, App_Stage.None)
	_, selection_failure := dispatch_session_input(
		&fixture.commands,
		&session,
		handle,
		interaction.Input{kind = .Key, stroke = interaction.Key_Stroke{kind = .Enter}},
		constraints,
	)
	testing.expect_value(t, selection_failure.stage, App_Stage.None)
	visible, visible_ok, _ := editor_session.session_visible_target(&session, handle)
	testing.expect(t, visible_ok)
	testing.expect_value(t, visible.entry, second.entry)
	layout_handle, _, _ := layout.registry_handle(&fixture.commands.layout_registry)
	after_select, selected_snapshot_ok, _ := layout.registry_snapshot(
		&fixture.commands.layout_registry,
		layout_handle,
	)
	testing.expect(t, selected_snapshot_ok)
	selected_active := other_pane_test_active_entry(after_select)
	testing.expect_value(t, selected_active, second.entry)
	selected_pane := after_select.active_pane.pane_id

	display_command, display_found, _ := interaction.command_lookup(
		&fixture.command_registry,
		"display-buffer-other-pane",
	)
	testing.expect(t, display_found)
	_, present_failure = command_context_present_buffer_navigation(
		&fixture.commands,
		constraints,
		display_command,
	)
	testing.expect_value(t, present_failure.stage, App_Stage.None)
	dispatch_session_input(
		&fixture.commands,
		&session,
		handle,
		interaction.Input{kind = .Text_Commit, text = "third"},
		constraints,
	)
	_, display_selection_failure := dispatch_session_input(
		&fixture.commands,
		&session,
		handle,
		interaction.Input{kind = .Key, stroke = interaction.Key_Stroke{kind = .Enter}},
		constraints,
	)
	testing.expect_value(t, display_selection_failure.stage, App_Stage.None)
	visible, visible_ok, _ = editor_session.session_visible_target(&session, handle)
	testing.expect(t, visible_ok)
	testing.expect_value(t, visible.entry, second.entry)
	layout_handle, _, _ = layout.registry_handle(&fixture.commands.layout_registry)
	after_display, displayed_snapshot_ok, _ := layout.registry_snapshot(
		&fixture.commands.layout_registry,
		layout_handle,
	)
	testing.expect(t, displayed_snapshot_ok)
	testing.expect_value(t, after_display.active_pane.pane_id, selected_pane)
	testing.expect_value(t, other_pane_test_active_entry(after_display), second.entry)
	testing.expect(t, other_pane_test_contains_entry(after_display, third.entry))

	file_command, file_found, _ := interaction.command_lookup(
		&fixture.command_registry,
		"find-file-other-pane",
	)
	testing.expect(t, file_found)
	_, begin_failure := filesystem_path_navigation_begin(
		&fixture.commands,
		.Find_File_Other_Pane,
		file_command,
	)
	testing.expect_value(t, begin_failure.stage, App_Stage.None)
	dispatch_session_input(
		&fixture.commands,
		&session,
		handle,
		interaction.Input{kind = .Text_Commit, text = path},
		constraints,
	)
	_, file_failure := dispatch_session_input(
		&fixture.commands,
		&session,
		handle,
		interaction.Input{kind = .Key, stroke = interaction.Key_Stroke{kind = .Enter}},
		constraints,
	)
	testing.expect_value(t, file_failure.stage, App_Stage.None)
	file_entry, file_found_in_session, _ := editor_session.session_find_path(&session, handle, path)
	testing.expect(t, file_found_in_session)
	visible, visible_ok, _ = editor_session.session_visible_target(&session, handle)
	testing.expect(t, visible_ok)
	testing.expect_value(t, visible.entry, file_entry)
	layout_handle, _, _ = layout.registry_handle(&fixture.commands.layout_registry)
	after_file, file_snapshot_ok, _ := layout.registry_snapshot(
		&fixture.commands.layout_registry,
		layout_handle,
	)
	testing.expect(t, file_snapshot_ok)
	testing.expect_value(t, other_pane_test_active_entry(after_file), file_entry)
}

@(private)
other_pane_test_active_entry :: proc(snapshot: layout.Snapshot) -> editor_session.Entry_Handle {
	for index in 0 ..< int(snapshot.node_count) {
		node := snapshot.nodes[index]
		if node.kind == .Pane && node.active {
			return node.entry
		}
	}
	return {}
}

@(private)
other_pane_test_contains_entry :: proc(
	snapshot: layout.Snapshot,
	entry: editor_session.Entry_Handle,
) -> bool {
	for index in 0 ..< int(snapshot.node_count) {
		node := snapshot.nodes[index]
		if node.kind == .Pane && node.entry == entry {
			return true
		}
	}
	return false
}

/* Verifies component maps nest beneath prompts and leave no active owner. */
@(test)
component_maps_keep_checked_lifetimes :: proc(t: ^testing.T) {
	fixture: Interaction_Fixture
	if !interaction_fixture_init(t, &fixture, "unused") {
		return
	}
	defer interaction_fixture_close(&fixture)

	startup_failure := command_context_sync_list_map(
		&fixture.commands,
		.Startup,
	)
	testing.expect_value(t, startup_failure.stage, App_Stage.None)
	startup_map := fixture.commands.interaction_workflow.map_handle
	stats, stats_ok := interaction.context_map_stats(&fixture.context_maps)
	testing.expect(t, stats_ok)
	testing.expect_value(t, stats.active_maps, u8(1))

	fixture.commands.search.kind = .Literal
	prompt_failure := command_context_activate_prompt_map(
		&fixture.commands,
		.Incremental_Search,
	)
	testing.expect_value(t, prompt_failure.stage, App_Stage.None)
	stats, stats_ok = interaction.context_map_stats(&fixture.context_maps)
	testing.expect(t, stats_ok)
	testing.expect_value(t, stats.active_maps, u8(2))
	startup_resync_failure := command_context_sync_list_map(
		&fixture.commands,
		.Startup,
	)
	testing.expect_value(t, startup_resync_failure.stage, App_Stage.None)
	testing.expect_value(t, fixture.commands.interaction_workflow.map_handle, startup_map)
	stats, stats_ok = interaction.context_map_stats(&fixture.context_maps)
	testing.expect(t, stats_ok)
	testing.expect_value(t, stats.active_maps, u8(2))
	metadata, resolution, resolved, resolve_failure := command_context_resolve_context_input(
		&fixture.commands,
		interaction.Input {
			kind = .Key,
			stroke = interaction.Key_Stroke {
				kind = .Unicode_Scalar,
				scalar = 'g',
				modifiers = {.Control},
			},
		},
	)
	testing.expect(t, resolved)
	testing.expect_value(t, resolve_failure.stage, App_Stage.None)
	testing.expect_value(t, resolution.kind, interaction.Resolution_Kind.Command)
	testing.expect_value(t, metadata.name, "keyboard-quit")

	command_context_deactivate_prompt_map(&fixture.commands, .Cancelled)
	metadata, resolution, resolved, resolve_failure = command_context_resolve_context_input(
		&fixture.commands,
		interaction.Input {
			kind = .Key,
			stroke = interaction.Key_Stroke{kind = .Down},
		},
	)
	testing.expect(t, resolved)
	testing.expect_value(t, resolve_failure.stage, App_Stage.None)
	testing.expect_value(t, resolution.kind, interaction.Resolution_Kind.Command)
	testing.expect_value(t, metadata.name, "component-next-row")

	inventory_failure := command_context_sync_list_map(
		&fixture.commands,
		.Buffer_Inventory,
	)
	testing.expect_value(t, inventory_failure.stage, App_Stage.None)
	testing.expect(t, fixture.commands.interaction_workflow.map_handle != startup_map)
	metadata, resolution, resolved, resolve_failure = command_context_resolve_context_input(
		&fixture.commands,
		interaction.Input {
			kind = .Key,
			stroke = interaction.Key_Stroke {
				kind = .Unicode_Scalar,
				scalar = 'q',
			},
		},
	)
	testing.expect(t, resolved)
	testing.expect_value(t, resolve_failure.stage, App_Stage.None)
	testing.expect_value(t, resolution.kind, interaction.Resolution_Kind.Command)
	testing.expect_value(t, metadata.name, "component-close")

	command_context_deactivate_context_map(&fixture.commands, .Completed)
	result_failure := command_context_sync_candidate_map(&fixture.commands, .Results)
	testing.expect_value(t, result_failure.stage, App_Stage.None)
	metadata, resolution, resolved, resolve_failure = command_context_resolve_context_input(
		&fixture.commands,
		interaction.Input {
			kind = .Key,
			stroke = interaction.Key_Stroke{kind = .Unicode_Scalar, scalar = 'e'},
		},
	)
	testing.expect(t, resolved)
	testing.expect_value(t, resolve_failure.stage, App_Stage.None)
	testing.expect_value(t, resolution.kind, interaction.Resolution_Kind.Command)
	testing.expect_value(t, metadata.name, "result-edit")
	contextual_route, contextual_ok := command.contextual_route_decode(metadata.route)
	testing.expect(t, contextual_ok)
	testing.expect_value(t, contextual_route, command.Contextual_Route.Result_Edit)

	command_context_deactivate_context_map(&fixture.commands, .Completed)
	stats, stats_ok = interaction.context_map_stats(&fixture.context_maps)
	testing.expect(t, stats_ok)
	testing.expect_value(t, stats.active_maps, u8(0))
}

/* Verifies component takeover cancels modal composition without replacing the profile or state. */
@(test)
component_maps_suspend_modal_pending_state :: proc(t: ^testing.T) {
	fixture, allocation_error := new(Interaction_Fixture, context.allocator)
	testing.expect(t, allocation_error == nil)
	if allocation_error != nil do return
	defer free(fixture, context.allocator)
	if !interaction_fixture_init(t, fixture, "unused") do return
	defer interaction_fixture_close(fixture)
	activation: interaction.Profile_Activation
	if !modal_navigation_test_activate(t, fixture, &activation) do return
	defer interaction.profile_activation_close(&activation)

	profile, state, selected := interaction.profile_activation_selection(&activation)
	catalog, catalog_ok := interaction.profile_activation_catalog(&activation)
	surface, surface_ok := interaction.profile_activation_command_entry_surface(
		&activation,
		"extended-command",
	)
	stats, stats_ok, _ := editor.buffer_stats(&fixture.buffer)
	testing.expect(t, selected && catalog_ok && surface_ok && stats_ok)
	if !selected || !catalog_ok || !surface_ok || !stats_ok do return
	request := interaction.Modal_Pending_Request {
		kind = .Count,
		profile = profile,
		state = state.identity,
		catalog_generation = catalog.generation,
		snapshot_generation = activation.generation,
		ctx = fixture.commands.active_interaction_context.identity,
		view_identity = u64(fixture.handle.view_id),
		view_generation = fixture.handle.generation,
		buffer_identity = u64(stats.buffer_id),
		buffer_revision = u64(stats.revision),
		sequence = {
			strokes = {0 = {kind = .Unicode_Scalar, scalar = '2'}},
			stroke_count = 1,
		},
		text = "2",
		count = 2,
	}
	started, pending_failure := interaction.profile_activation_modal_pending_begin(
		&activation,
		request,
	)
	testing.expectf(t, started, "modal count setup failed with %v", pending_failure.code)
	map_failure := command_context_sync_list_map(&fixture.commands, .Startup)
	testing.expect_value(t, map_failure.stage, App_Stage.None)
	pending, inspected := interaction.profile_activation_modal_pending_inspect(&activation)
	testing.expect(t, inspected)
	testing.expect_value(t, pending, interaction.Modal_Pending_State{})
	retained_profile, retained_state, retained := interaction.profile_activation_selection(&activation)
	testing.expect(t, retained)
	testing.expect_value(t, retained_profile, profile)
	testing.expect_value(t, retained_state.identity, state.identity)

	request.kind = .Command_Entry
	request.text = ""
	request.count = 0
	request.sequence.strokes[0].scalar = ':'
	request.command_entry_surface = surface.identity
	started, pending_failure = interaction.profile_activation_modal_pending_begin(&activation, request)
	testing.expectf(t, started, "modal command entry setup failed with %v", pending_failure.code)
	command_map_failure := command_context_sync_candidate_map(&fixture.commands, .Commands)
	testing.expect_value(t, command_map_failure.stage, App_Stage.None)
	metadata, resolution, resolved, resolution_failure := command_context_resolve_context_input(
		&fixture.commands,
		interaction.Input{kind = .Key, stroke = {kind = .Escape}},
	)
	testing.expect(t, resolved)
	testing.expect_value(t, resolution_failure.stage, App_Stage.None)
	testing.expect_value(t, resolution.kind, interaction.Resolution_Kind.Command)
	testing.expect_value(t, metadata.name, "component-close")
	pending, inspected = interaction.profile_activation_modal_pending_inspect(&activation)
	testing.expect(t, inspected)
	testing.expect_value(t, pending.kind, interaction.Modal_Pending_Kind.Command_Entry)
}

/* Verifies a replaced context stack reactivates a same-identity component map. */
@(test)
component_map_sync_replaces_a_stale_generation_handle :: proc(t: ^testing.T) {
	fixture: Interaction_Fixture
	if !interaction_fixture_init(t, &fixture, "unused") {
		return
	}
	defer interaction_fixture_close(&fixture)

	startup_failure := command_context_sync_list_map(&fixture.commands, .Startup)
	testing.expect_value(t, startup_failure.stage, App_Stage.None)
	stale := fixture.commands.interaction_workflow.map_handle
	closed, close_failure := interaction.context_map_stack_close(&fixture.context_maps)
	testing.expect(t, closed)
	testing.expect_value(t, close_failure.code, interaction.Failure_Code.None)
	initialized, init_failure := interaction.context_map_stack_init(
		&fixture.context_maps,
		interaction.Context_ID(103),
		&fixture.command_registry,
		context.allocator,
	)
	testing.expect(t, initialized)
	testing.expect_value(t, init_failure.code, interaction.Failure_Code.None)
	if !initialized do return

	reactivated_failure := command_context_sync_list_map(&fixture.commands, .Startup)
	testing.expect_value(t, reactivated_failure.stage, App_Stage.None)
	current := fixture.commands.interaction_workflow.map_handle
	stats, stats_ok := interaction.context_map_stats(&fixture.context_maps)
	testing.expect(t, stats_ok)
	testing.expect_value(t, stats.active_maps, u8(1))
	testing.expect_value(t, current.ctx, stats.ctx)
	testing.expect(t, current != stale)

	metadata, resolution, resolved, resolve_failure := command_context_resolve_context_input(
		&fixture.commands,
		interaction.Input {
			kind = .Key,
			stroke = interaction.Key_Stroke{kind = .Down},
		},
	)
	testing.expect(t, resolved)
	testing.expect_value(t, resolve_failure.stage, App_Stage.None)
	testing.expect_value(t, resolution.kind, interaction.Resolution_Kind.Command)
	testing.expect_value(t, metadata.name, "component-next-row")
}

/* Verifies navigator selections cannot survive registry or profile replacement. */
@(test)
navigation_requires_current_profile :: proc(t: ^testing.T) {
	fixture: Interaction_Fixture
	if !interaction_fixture_init(t, &fixture, "unused") {
		return
	}
	defer interaction_fixture_close(&fixture)
	current := interaction.Candidate_View {
		source_kind = .Commands,
		scope_identity = 101,
		scope_generation = 101,
		source_generation = 101,
	}
	action := interaction.Candidate_Action {
		kind = .Invoke_Command,
		owner_generation = 101,
	}
	testing.expect(
		t,
		command_context_navigation_selection_is_current(&fixture.commands, current, action),
	)
	stale_registry := current
	stale_registry.scope_identity = 102
	testing.expect(
		t,
		!command_context_navigation_selection_is_current(&fixture.commands, stale_registry, action),
	)
	stale_profile := current
	stale_profile.source_generation = 102
	testing.expect(
		t,
		!command_context_navigation_selection_is_current(&fixture.commands, stale_profile, action),
	)
}

/* Verifies bounded file and buffer prompts publish exact session selections. */
@(test)
buffer_prompts_open_and_reuse_entries :: proc(t: ^testing.T) {
	directory, directory_error := os.make_directory_temp("", "odra-buffer-prompts-*", context.allocator)
	testing.expect(t, directory_error == nil)
	if directory_error != nil {
		return
	}
	defer {
		os.remove_all(directory)
		delete(directory)
	}
	path, path_error := os.join_path({directory, "opened.md"}, context.allocator)
	hidden_path, hidden_path_error := os.join_path({directory, ".notes.md"}, context.allocator)
	projects_path, projects_path_error := os.join_path({directory, "Projects"}, context.allocator)
	testing.expect(
		t,
		path_error == nil && hidden_path_error == nil && projects_path_error == nil,
	)
	if path_error != nil || hidden_path_error != nil || projects_path_error != nil {
		return
	}
	nested_path, nested_path_error := os.join_path({projects_path, "opened.md"}, context.allocator)
	testing.expect(t, nested_path_error == nil)
	if nested_path_error != nil do return
	defer {
		delete(nested_path)
		delete(projects_path)
		delete(hidden_path)
		delete(path)
	}
	testing.expect(t, os.make_directory(projects_path) == nil)
	testing.expect(t, os.write_entire_file(path, "opened") == nil)
	testing.expect(t, os.write_entire_file(hidden_path, "hidden") == nil)
	testing.expect(t, os.write_entire_file(nested_path, "nested") == nil)

	session: editor_session.Session
	handle, initialized, _ := editor_session.session_init(
		&session,
		editor_session.Session_ID(801),
		editor_session.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	testing.expect(t, initialized)
	if !initialized {
		return
	}
	command_definitions := command.built_in_base_command_definitions()
	command_registry: interaction.Command_Registry
	registry_ready, registry_failure := interaction.command_registry_init(
		&command_registry,
		1,
		command_definitions[:],
		context.allocator,
	)
	testing.expectf(t, registry_ready, "command registry failed with %v", registry_failure.code)
	if !registry_ready {
		return
	}
	defer interaction.command_registry_close(&command_registry)
	context_maps: interaction.Context_Map_Stack
	context_ready, context_failure := interaction.context_map_stack_init(
		&context_maps,
		1,
		&command_registry,
		context.allocator,
	)
	testing.expectf(t, context_ready, "context maps failed with %v", context_failure.code)
	if !context_ready {
		return
	}
	defer interaction.context_map_stack_close(&context_maps)
	command_handle, command_ready, command_failure := interaction.command_lookup(
		&command_registry,
		"switch-to-buffer",
	)
	testing.expectf(t, command_ready, "buffer command failed with %v", command_failure.code)
	if !command_ready {
		return
	}
	commands := Command_Context {
		session_owner = &session,
		session_handle = handle,
		entry_configuration = editor_session.DEFAULT_ENTRY_CONFIGURATION,
		registry = &command_registry,
		registry_generation = 1,
		context_maps = &context_maps,
		persistent_allocator = context.allocator,
		temporary_allocator = context.temp_allocator,
		home_directory = directory,
	}
	commands.candidate_ui.next_session_id = 1
	commands.candidate_ui.next_source_generation = 1
	defer command_context_close(&commands)

	started, start_failure := command_context_begin_buffer_prompt(
		&commands,
		.Switch_To_Buffer,
		command_handle,
	)
	testing.expect(t, started.changed && start_failure.stage == .None)
	_, append_failure := dispatch_buffer_session_prompt(
		&commands,
		interaction.Input{kind = .Text_Commit, text = "λ-notes"},
	)
	testing.expect_value(t, append_failure.stage, App_Stage.None)
	label, text, overlay := command_context_overlay(&commands, nil, {})
	testing.expect(t, overlay)
	testing.expect_value(t, label, "Switch to buffer: ")
	testing.expect_value(t, text, "λ-notes")
	_, accept_failure := dispatch_buffer_session_prompt(
		&commands,
		interaction.Input {
			kind = .Key,
			stroke = interaction.Key_Stroke{kind = .Enter},
		},
	)
	testing.expect_value(t, accept_failure.stage, App_Stage.None)
	created, created_found, _ := editor_session.session_find_label(&session, handle, "λ-notes")
	testing.expect(t, created_found)

	find_file_handle, find_file_ready, _ := interaction.command_lookup(
		&command_registry,
		"find-file",
	)
	testing.expect(t, find_file_ready)
	_, _ = filesystem_path_navigation_begin(&commands, .Find_File, find_file_handle)
	constraints := display.Viewport_Constraints{width_cells = 80, height_rows = 24}
	_, _ = dispatch_filesystem_path_navigation_input(
		&commands,
		interaction.Input{kind = .Text_Commit, text = "/"},
		constraints,
	)
	_, _ = dispatch_filesystem_path_navigation_input(
		&commands,
		interaction.Input{kind = .Text_Commit, text = "Projects/"},
		constraints,
	)
	_, nested_query_failure := dispatch_filesystem_path_navigation_input(
		&commands,
		interaction.Input{kind = .Text_Commit, text = "ope"},
		constraints,
	)
	testing.expect_value(t, nested_query_failure.stage, App_Stage.None)
	nested_view, nested_viewed, _ := interaction.candidate_session_view(&commands.candidate_ui.session)
	testing.expect(t, nested_viewed)
	if nested_viewed {
		testing.expect_value(t, nested_view.query, "ope")
		input_storage: [document.MAX_PATH_BYTES]u8
		input_value, input_ok := filesystem_path_navigation_input_value(
			&commands,
			nested_view.query,
			input_storage[:],
		)
		testing.expect(t, input_ok)
		testing.expect_value(t, input_value, "~/Projects/ope")
	}
	testing.expect_value(t, commands.diagnostic_length, 0)
	_, _ = filesystem_path_navigation_leave(&commands)
	_, _ = filesystem_path_navigation_begin(&commands, .Find_File, find_file_handle)
	default_view, default_viewed, _ := interaction.candidate_session_view(&commands.candidate_ui.session)
	testing.expect(t, default_viewed)
	if default_viewed do testing.expect_value(t, len(default_view.rows), 2)
	_, hidden_query_failure := filesystem_path_navigation_set_query(&commands, ".n")
	testing.expect_value(t, hidden_query_failure.stage, App_Stage.None)
	hidden_view, hidden_viewed, _ := interaction.candidate_session_view(&commands.candidate_ui.session)
	testing.expect(t, hidden_viewed)
	if hidden_viewed {
		testing.expect(t, hidden_view.has_selection && len(hidden_view.rows) > 0)
		if hidden_view.has_selection && len(hidden_view.rows) > 0 {
			hidden_descriptor, hidden_descriptor_found := interaction.filesystem_candidate_action_entry(
				hidden_view.rows[hidden_view.selected_row].action,
				&commands.filesystem_path_navigation.batch,
			)
			testing.expect(t, hidden_descriptor_found)
			if hidden_descriptor_found do testing.expect_value(t, hidden_descriptor.path, hidden_path)
		}
	}
	_, hidden_open_failure := dispatch_filesystem_path_navigation_input(
		&commands,
		interaction.Input {
			kind = .Key,
			stroke = interaction.Key_Stroke{kind = .Enter},
		},
		display.Viewport_Constraints{width_cells = 80, height_rows = 24},
	)
	testing.expect_value(t, hidden_open_failure.stage, App_Stage.None)
	hidden_opened, hidden_opened_found, _ := editor_session.session_find_path(
		&session,
		handle,
		hidden_path,
	)
	testing.expect(t, hidden_opened_found)

	_, _ = filesystem_path_navigation_begin(&commands, .Find_File, find_file_handle)
	_, _ = dispatch_filesystem_path_navigation_input(
		&commands,
		interaction.Input{kind = .Text_Commit, text = path},
		display.Viewport_Constraints{width_cells = 80, height_rows = 24},
	)
	_, open_failure := dispatch_filesystem_path_navigation_input(
		&commands,
		interaction.Input {
			kind = .Key,
			stroke = interaction.Key_Stroke{kind = .Enter},
		},
		display.Viewport_Constraints{width_cells = 80, height_rows = 24},
	)
	testing.expect_value(t, open_failure.stage, App_Stage.None)
	normalized: document.Normalized_Path
	normalized_ok, _ := document.path_normalize(
		path,
		&normalized,
		context.allocator,
		document.DEFAULT_LIMITS,
	)
	testing.expect(t, normalized_ok)
	opened, opened_found, _ := editor_session.session_find_path(
		&session,
		handle,
		document.normalized_path_text(&normalized),
	)
	testing.expect(t, opened_found)

	_, _ = filesystem_path_navigation_begin(&commands, .Find_File, find_file_handle)
	_, _ = dispatch_filesystem_path_navigation_input(
		&commands,
		interaction.Input{kind = .Text_Commit, text = path},
		display.Viewport_Constraints{width_cells = 80, height_rows = 24},
	)
	_, reuse_failure := dispatch_filesystem_path_navigation_input(
		&commands,
		interaction.Input {
			kind = .Key,
			stroke = interaction.Key_Stroke{kind = .Enter},
		},
		display.Viewport_Constraints{width_cells = 80, height_rows = 24},
	)
	testing.expect_value(t, reuse_failure.stage, App_Stage.None)
	visible, visible_ok, _ := editor_session.session_visible_target(&session, handle)
	testing.expect(t, visible_ok)
	testing.expect_value(t, visible.entry, opened)

	buffer_prompt_test_release(t, &session, opened)
	buffer_prompt_test_release(t, &session, hidden_opened)
	buffer_prompt_test_release(t, &session, created)
	closed, close_failure := editor_session.session_close(&session)
	testing.expectf(t, closed, "session close failed with %v", close_failure.code)
}

/* Verifies one-root Project scope and removal of legacy multi-dir commands. */
@(test)
one_root_keeps_buffer_scope :: proc(t: ^testing.T) {
	project_directory, project_error := os.make_directory_temp("", "odra-project-*", context.allocator)
	external_directory, external_error := os.make_directory_temp("", "odra-external-*", context.allocator)
	testing.expect(t, project_error == nil && external_error == nil)
	if project_error != nil || external_error != nil {
		return
	}
	defer {
		os.remove_all(project_directory)
		os.remove_all(external_directory)
		delete(project_directory)
		delete(external_directory)
	}
	project_path, _ := os.join_path({project_directory, "owned.md"}, context.allocator)
	external_path, _ := os.join_path({external_directory, "external.md"}, context.allocator)
	defer delete(project_path)
	defer delete(external_path)
	testing.expect(t, os.write_entire_file(project_path, "owned") == nil)
	testing.expect(t, os.write_entire_file(external_path, "external") == nil)

	session: editor_session.Session
	handle, initialized, _ := editor_session.session_init(
		&session,
		editor_session.Session_ID(805),
		editor_session.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	testing.expect(t, initialized)
	if !initialized {
		return
	}
	command_definitions := command.built_in_base_command_definitions()
	command_registry: interaction.Command_Registry
	registry_ready, _ := interaction.command_registry_init(
		&command_registry,
		1,
		command_definitions[:],
		context.allocator,
	)
	testing.expect(t, registry_ready)
	if !registry_ready {
		editor_session.session_close(&session)
		return
	}
	defer interaction.command_registry_close(&command_registry)
	context_maps: interaction.Context_Map_Stack
	context_ready, _ := interaction.context_map_stack_init(
		&context_maps,
		1,
		&command_registry,
		context.allocator,
	)
	testing.expect(t, context_ready)
	if !context_ready {
		editor_session.session_close(&session)
		return
	}
	defer interaction.context_map_stack_close(&context_maps)
	commands := Command_Context {
		session_owner = &session,
		session_handle = handle,
		entry_configuration = editor_session.DEFAULT_ENTRY_CONFIGURATION,
		registry = &command_registry,
		registry_generation = 1,
		context_maps = &context_maps,
		candidate_ui = {next_session_id = 1, next_source_generation = 1},
		project_workflow = {next_project_id = 1},
		persistent_allocator = context.allocator,
		temporary_allocator = context.temp_allocator,
	}
	defer command_context_close(&commands)
	activation, created, create_failure := editor_session.session_open_project_directory(
		&session,
		editor_session.Project_Directory_Open_Request {
			session = handle,
			expected_catalog_generation = 1,
			actual_catalog_generation = 1,
			normalized_path = project_directory,
			matching_projects = 1,
			project_id = project.Project_ID(1),
			project_generation = 1,
			durable_id = "project",
			name = "Project",
			trust = .Untrusted,
			temporary = false,
		},
	)
	testing.expectf(t, created, "Project setup failed: %v", create_failure.code)
	if created {
		_, projected, projection_failure := editor_session.session_roots_replace(
			&session,
			editor_session.Root_Replace_Request {
				session = handle,
				roots = []editor_session.Root_Proposal {{
					kind = .Project,
					path = project_directory,
					project = activation.active.handle,
				}},
			},
		)
		testing.expectf(t, projected, "Project root setup failed: %v", projection_failure.code)
	}
	active, active_ok, _ := editor_session.session_active_project(&session, handle)
	testing.expect(t, active_ok && active.active)
	testing.expect_value(t, active.descriptor.directory_count, u32(1))

	owned_entry, owned_open, _ := editor_session.session_open_path(
		&session,
		editor_session.Open_Path_Request {
			session = handle,
			path = project_path,
			encoding = .UTF8,
			configuration = editor_session.DEFAULT_ENTRY_CONFIGURATION,
		},
	)
	testing.expect(t, owned_open)
	owned_scope, _, owned_classified, _ := editor_session.session_active_project_buffer_scope(
		&session,
		handle,
		activation.active.handle,
	)
	testing.expect(t, owned_classified)
	testing.expect_value(t, owned_scope, editor_session.Project_Buffer_Scope.Project_Owned)
	external_entry, external_open, _ := editor_session.session_open_path(
		&session,
		editor_session.Open_Path_Request {
			session = handle,
			path = external_path,
			encoding = .UTF8,
			configuration = editor_session.DEFAULT_ENTRY_CONFIGURATION,
		},
	)
	testing.expect(t, external_open)
	external_scope, _, external_classified, _ := editor_session.session_active_project_buffer_scope(
		&session,
		handle,
		activation.active.handle,
	)
	testing.expect(t, external_classified)
	testing.expect_value(t, external_scope, editor_session.Project_Buffer_Scope.External)

	legacy_names := [?]string {
		"project-register",
		"project-add-directory",
		"project-remove-directory",
		"project-list-directories",
		"project-find-directory",
	}
	for name in legacy_names {
		_, found, _ := interaction.command_lookup(&command_registry, name)
		testing.expectf(t, !found, "legacy command remains registered: %s", name)
	}
	_, reactivated, _ := editor_session.session_activate(&session, owned_entry.entry)
	testing.expect(t, reactivated)
	reactivated_scope, _, reactivated_classified, _ := editor_session.session_active_project_buffer_scope(
		&session,
		handle,
		activation.active.handle,
	)
	testing.expect(t, reactivated_classified)
	testing.expect_value(t, reactivated_scope, editor_session.Project_Buffer_Scope.Project_Owned)
	_, external_reactivated, _ := editor_session.session_activate(&session, external_entry.entry)
	testing.expect(t, external_reactivated)
	final_scope, _, final_classified, _ := editor_session.session_active_project_buffer_scope(
		&session,
		handle,
		activation.active.handle,
	)
	testing.expect(t, final_classified)
	testing.expect_value(t, final_scope, editor_session.Project_Buffer_Scope.External)
	shutdown_failure := session_shutdown_close(&session, handle)
	testing.expect_value(t, shutdown_failure.stage, App_Stage.None)
}

@(private)
buffer_prompt_test_release :: proc(
	t: ^testing.T,
	session: ^editor_session.Session,
	entry: editor_session.Entry_Handle,
) {
	detached: editor_session.Detached_Entry
	_, detached_ok, detach_failure := editor_session.session_entry_detach(session, entry, &detached)
	testing.expectf(t, detached_ok, "session detach failed with %v", detach_failure.code)
	if !detached_ok {
		return
	}
	_, cleaned, cleanup_failure := editor_session.detached_entry_cleanup(&detached)
	testing.expectf(t, cleaned, "session cleanup failed with %v", cleanup_failure.code)
	if !cleaned {
		return
	}
	released, release_failure := editor_session.detached_entry_release(&detached)
	testing.expectf(t, released, "session release failed with %v", release_failure.code)
}

/* Verifies every command turn resolves the current checked session entry. */
@(test)
session_routes_independent_state :: proc(t: ^testing.T) {
	directory, directory_error := os.make_directory_temp("", "odra-active-routing-*", context.allocator)
	testing.expect(t, directory_error == nil)
	if directory_error != nil {
		return
	}
	defer {
		os.remove_all(directory)
		delete(directory)
	}
	path, path_error := os.join_path({directory, "active.txt"}, context.allocator)
	testing.expect(t, path_error == nil)
	if path_error != nil {
		return
	}
	defer delete(path)
	testing.expect(t, os.write_entire_file(path, "base") == nil)

	fixture: Interaction_Fixture
	if !interaction_fixture_init(t, &fixture, "unused") {
		return
	}
	defer interaction_fixture_close(&fixture)
	session: editor_session.Session
	handle, initialized, _ := editor_session.session_init(
		&session,
		editor_session.Session_ID(802),
		editor_session.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	testing.expect(t, initialized)
	if !initialized {
		return
	}
	file_entry, file_ok, _ := editor_session.session_open_path(
		&session,
		editor_session.Open_Path_Request {
			session = handle,
			path = path,
			encoding = .UTF8,
			configuration = editor_session.DEFAULT_ENTRY_CONFIGURATION,
		},
	)
	notes_entry, notes_ok, _ := editor_session.session_create_buffer(
		&session,
		editor_session.Create_Buffer_Request {
			session = handle,
			name = "notes",
			configuration = editor_session.DEFAULT_ENTRY_CONFIGURATION,
		},
	)
	testing.expect(t, file_ok && notes_ok)
	if !file_ok || !notes_ok {
		return
	}
	fixture.commands.session_owner = &session
	fixture.commands.session_handle = handle
	fixture.commands.entry_configuration = editor_session.DEFAULT_ENTRY_CONFIGURATION
	constraints := display.Viewport_Constraints{width_cells = 80, height_rows = 24}

	inserted, insert_failure := dispatch_session_input(
		&fixture.commands,
		&session,
		handle,
		interaction.Input{kind = .Text_Commit, text = "note"},
		constraints,
	)
	testing.expect(t, inserted.changed && insert_failure.stage == .None)
	testing.expect_value(t, session_entry_text(t, &session, notes_entry.entry), "note")

	_, activated, _ := editor_session.session_activate(&session, file_entry.entry)
	testing.expect(t, activated)
	_, insert_failure = dispatch_session_input(
		&fixture.commands,
		&session,
		handle,
		interaction.Input{kind = .Text_Commit, text = "X"},
		constraints,
	)
	testing.expect_value(t, insert_failure.stage, App_Stage.None)
	dispatch_session_input(
		&fixture.commands,
		&session,
		handle,
		interaction.Input {
			kind = .Key,
			stroke = interaction.Key_Stroke {
				kind = .Unicode_Scalar,
				scalar = 'x',
				modifiers = {.Control},
			},
		},
		constraints,
	)
	undone, undo_failure := dispatch_session_input(
		&fixture.commands,
		&session,
		handle,
		interaction.Input {
			kind = .Key,
			stroke = interaction.Key_Stroke{kind = .Unicode_Scalar, scalar = 'u'},
		},
		constraints,
	)
	testing.expect(t, undone.changed && undo_failure.stage == .None)
	testing.expect_value(t, session_entry_text(t, &session, file_entry.entry), "base")
	testing.expect_value(t, session_entry_text(t, &session, notes_entry.entry), "note")

	dispatch_session_input(
		&fixture.commands,
		&session,
		handle,
		interaction.Input {
			kind = .Key,
			stroke = interaction.Key_Stroke {
				kind = .Unicode_Scalar,
				scalar = 's',
				modifiers = {.Control},
			},
		},
		constraints,
	)
	found, search_failure := dispatch_session_input(
		&fixture.commands,
		&session,
		handle,
		interaction.Input{kind = .Text_Commit, text = "base"},
		constraints,
	)
	testing.expect(t, found.changed && search_failure.stage == .None)
	_, search_accept_failure := dispatch_session_input(
		&fixture.commands,
		&session,
		handle,
		interaction.Input{kind = .Key, stroke = interaction.Key_Stroke{kind = .Enter}},
		constraints,
	)
	testing.expect_value(t, search_accept_failure.stage, App_Stage.None)
	_, save_insert_failure := dispatch_session_input(
		&fixture.commands,
		&session,
		handle,
		interaction.Input{kind = .Text_Commit, text = "Y"},
		constraints,
	)
	testing.expect_value(t, save_insert_failure.stage, App_Stage.None)
	dispatch_session_input(
		&fixture.commands,
		&session,
		handle,
		interaction.Input {
			kind = .Key,
			stroke = interaction.Key_Stroke {
				kind = .Unicode_Scalar,
				scalar = 'x',
				modifiers = {.Control},
			},
		},
		constraints,
	)
	saved, save_failure := dispatch_session_input(
		&fixture.commands,
		&session,
		handle,
		interaction.Input {
			kind = .Key,
			stroke = interaction.Key_Stroke {
				kind = .Unicode_Scalar,
				scalar = 's',
				modifiers = {.Control},
			},
		},
		constraints,
	)
	testing.expect(t, save_failure.stage == .None)
	testing.expect_value(t, saved.save.publication, document.Publication_State.Published_Durable)
	saved_bytes, read_error := os.read_entire_file(path, context.temp_allocator)
	testing.expect(t, read_error == nil)
	if read_error == nil {
		testing.expect_value(t, string(saved_bytes), "baseY")
		delete(saved_bytes, context.temp_allocator)
	}

	_, _, _ = editor_session.session_activate(&session, notes_entry.entry)
	_, note_insert_failure := dispatch_session_input(
		&fixture.commands,
		&session,
		handle,
		interaction.Input{kind = .Text_Commit, text = "!"},
		constraints,
	)
	testing.expect_value(t, note_insert_failure.stage, App_Stage.None)
	testing.expect_value(t, session_entry_text(t, &session, notes_entry.entry), "note!")

	shutdown_failure := session_shutdown_close(&session, handle)
	testing.expect_value(t, shutdown_failure.stage, App_Stage.None)
}

@(private)
session_entry_text :: proc(
	t: ^testing.T,
	session: ^editor_session.Session,
	entry: editor_session.Entry_Handle,
) -> string {
	access, access_ok, _ := editor_session.session_entry_access(session, entry)
	borrow, borrow_ok, _ := editor_session.entry_access_borrow(access)
	testing.expect(t, access_ok && borrow_ok)
	if !borrow_ok {
		return ""
	}
	stats, stats_ok, _ := editor.buffer_stats(borrow.buffer)
	testing.expect(t, stats_ok)
	if !stats_ok {
		return ""
	}
	bytes, allocation_error := make([]u8, int(stats.text_bytes), context.temp_allocator)
	testing.expect(t, allocation_error == nil)
	if allocation_error != nil {
		return ""
	}
	defer delete(bytes, context.temp_allocator)
	_, inspected, _ := editor.buffer_inspect(
		borrow.buffer,
		0,
		editor.Byte_Offset(stats.text_bytes),
		bytes,
	)
	testing.expect(t, inspected)
	return string(bytes)
}

/* Verifies C-x k protects dirty buffers, supports first save, and selects a fallback. */
@(test)
kill_prompt_uses_checked_session :: proc(t: ^testing.T) {
	directory, directory_error := os.make_directory_temp("", "odra-kill-buffer-*", context.allocator)
	testing.expect(t, directory_error == nil)
	if directory_error != nil {
		return
	}
	defer {
		os.remove_all(directory)
		delete(directory)
	}
	save_path, path_error := os.join_path({directory, "saved.txt"}, context.allocator)
	testing.expect(t, path_error == nil)
	if path_error != nil {
		return
	}
	defer delete(save_path)

	fixture: Interaction_Fixture
	if !interaction_fixture_init(t, &fixture, "unused") {
		return
	}
	defer interaction_fixture_close(&fixture)
	session: editor_session.Session
	handle, initialized, _ := editor_session.session_init(
		&session,
		editor_session.Session_ID(803),
		editor_session.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	testing.expect(t, initialized)
	if !initialized {
		return
	}
	first, first_ok, _ := editor_session.session_create_buffer(
		&session,
		editor_session.Create_Buffer_Request {
			session = handle,
			name = "discard-me",
			configuration = editor_session.DEFAULT_ENTRY_CONFIGURATION,
		},
	)
	_, second_ok, _ := editor_session.session_create_buffer(
		&session,
		editor_session.Create_Buffer_Request {
			session = handle,
			name = "save-me",
			configuration = editor_session.DEFAULT_ENTRY_CONFIGURATION,
		},
	)
	testing.expect(t, first_ok && second_ok)
	if !first_ok || !second_ok {
		return
	}
	fixture.commands.session_owner = &session
	fixture.commands.session_handle = handle
	fixture.commands.entry_configuration = editor_session.DEFAULT_ENTRY_CONFIGURATION
	constraints := display.Viewport_Constraints{width_cells = 80, height_rows = 24}
	control := proc(value: rune) -> interaction.Input {
		return interaction.Input {
			kind = .Key,
			stroke = interaction.Key_Stroke {
				kind = .Unicode_Scalar,
				scalar = value,
				modifiers = {.Control},
			},
		}
	}
	plain := proc(value: rune) -> interaction.Input {
		return interaction.Input {
			kind = .Key,
			stroke = interaction.Key_Stroke{kind = .Unicode_Scalar, scalar = value},
		}
	}
	enter := interaction.Input{kind = .Key, stroke = interaction.Key_Stroke{kind = .Enter}}

	_, insert_failure := dispatch_session_input(
		&fixture.commands,
		&session,
		handle,
		interaction.Input{kind = .Text_Commit, text = "saved text"},
		constraints,
	)
	testing.expect_value(t, insert_failure.stage, App_Stage.None)
	dispatch_session_input(&fixture.commands, &session, handle, control('x'), constraints)
	_, kill_start_failure := dispatch_session_input(
		&fixture.commands,
		&session,
		handle,
		plain('k'),
		constraints,
	)
	testing.expect_value(t, kill_start_failure.stage, App_Stage.None)
	testing.expect_value(t, fixture.commands.prompt_workflow.mode, Prompt_Mode.Kill_Buffer)
	_, kill_select_failure := dispatch_session_input(
		&fixture.commands,
		&session,
		handle,
		enter,
		constraints,
	)
	testing.expect_value(t, kill_select_failure.stage, App_Stage.None)
	testing.expect_value(t, fixture.commands.prompt_workflow.mode, Prompt_Mode.Kill_Unassociated_Choice)
	_, save_choice_failure := dispatch_session_input(
		&fixture.commands,
		&session,
		handle,
		plain('s'),
		constraints,
	)
	testing.expect_value(t, save_choice_failure.stage, App_Stage.None)
	testing.expect_value(t, fixture.commands.prompt_workflow.mode, Prompt_Mode.Kill_Save_Path)
	dispatch_session_input(
		&fixture.commands,
		&session,
		handle,
		interaction.Input{kind = .Text_Commit, text = save_path},
		constraints,
	)
	result, path_accept_failure := dispatch_session_input(
		&fixture.commands,
		&session,
		handle,
		enter,
		constraints,
	)
	testing.expect_value(t, path_accept_failure.stage, App_Stage.None)
	testing.expect(t, result.active_entry_closed)
	_, saved_entry_found, _ := editor_session.session_find_label(&session, handle, save_path)
	testing.expect(t, !saved_entry_found)
	saved_bytes, read_error := os.read_entire_file(save_path, context.allocator)
	testing.expect(t, read_error == nil)
	if read_error == nil {
		testing.expect_value(t, string(saved_bytes), "saved text")
		delete(saved_bytes)
	}
	visible, visible_ok, _ := editor_session.session_visible_target(&session, handle)
	testing.expect(t, visible_ok)
	testing.expect_value(t, visible.entry, first.entry)

	_, activated, _ := editor_session.session_activate(&session, first.entry)
	testing.expect(t, activated)
	dispatch_session_input(
		&fixture.commands,
		&session,
		handle,
		interaction.Input{kind = .Text_Commit, text = "discarded"},
		constraints,
	)
	dispatch_session_input(&fixture.commands, &session, handle, control('x'), constraints)
	dispatch_session_input(&fixture.commands, &session, handle, plain('k'), constraints)
	dispatch_session_input(&fixture.commands, &session, handle, enter, constraints)
	testing.expect_value(t, fixture.commands.prompt_workflow.mode, Prompt_Mode.Kill_Unassociated_Choice)
	discarded, discard_failure := dispatch_session_input(
		&fixture.commands,
		&session,
		handle,
		plain('d'),
		constraints,
	)
	testing.expect_value(t, discard_failure.stage, App_Stage.None)
	testing.expect(t, discarded.active_entry_closed)
	scratch_entry, fallback_found, _ := editor_session.session_find_label(&session, handle, "*scratch*")
	testing.expect(t, fallback_found)
	visible, visible_ok, _ = editor_session.session_visible_target(&session, handle)
	testing.expect(t, visible_ok)
	testing.expect_value(t, visible.kind, editor_session.Visible_Target_Kind.Primary_View)
	testing.expect_value(t, visible.entry, scratch_entry)
	shutdown_failure := session_shutdown_close(&session, handle)
	testing.expect_value(t, shutdown_failure.stage, App_Stage.None)
}

/* Verifies exit resolves every dirty MRU entry before detaching any buffer. */
@(test)
exit_saves_or_aborts_before_detach :: proc(t: ^testing.T) {
	directory, directory_error := os.make_directory_temp("", "odra-multi-exit-*", context.allocator)
	testing.expect(t, directory_error == nil)
	if directory_error != nil {
		return
	}
	defer {
		os.remove_all(directory)
		delete(directory)
	}
	first_path, _ := os.join_path({directory, "first.txt"}, context.allocator)
	second_path, _ := os.join_path({directory, "second.txt"}, context.allocator)
	defer delete(first_path)
	defer delete(second_path)
	testing.expect(t, os.write_entire_file(first_path, "one") == nil)
	testing.expect(t, os.write_entire_file(second_path, "two") == nil)

	fixture: Interaction_Fixture
	if !interaction_fixture_init(t, &fixture, "unused") {
		return
	}
	defer interaction_fixture_close(&fixture)
	session: editor_session.Session
	handle, initialized, _ := editor_session.session_init(
		&session,
		editor_session.Session_ID(804),
		editor_session.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	testing.expect(t, initialized)
	if !initialized {
		return
	}
	first, first_ok, _ := editor_session.session_open_path(
		&session,
		editor_session.Open_Path_Request {
			session = handle,
			path = first_path,
			encoding = .UTF8,
			configuration = editor_session.DEFAULT_ENTRY_CONFIGURATION,
		},
	)
	second, second_ok, _ := editor_session.session_open_path(
		&session,
		editor_session.Open_Path_Request {
			session = handle,
			path = second_path,
			encoding = .UTF8,
			configuration = editor_session.DEFAULT_ENTRY_CONFIGURATION,
		},
	)
	_, notes_ok, _ := editor_session.session_create_buffer(
		&session,
		editor_session.Create_Buffer_Request {
			session = handle,
			name = "notes",
			configuration = editor_session.DEFAULT_ENTRY_CONFIGURATION,
		},
	)
	testing.expect(t, first_ok && second_ok && notes_ok)
	if !first_ok || !second_ok || !notes_ok {
		return
	}
	fixture.commands.session_owner = &session
	fixture.commands.session_handle = handle
	fixture.commands.entry_configuration = editor_session.DEFAULT_ENTRY_CONFIGURATION
	constraints := display.Viewport_Constraints{width_cells = 80, height_rows = 24}
	control := proc(value: rune) -> interaction.Input {
		return interaction.Input {
			kind = .Key,
			stroke = interaction.Key_Stroke {
				kind = .Unicode_Scalar,
				scalar = value,
				modifiers = {.Control},
			},
		}
	}
	plain := proc(value: rune) -> interaction.Input {
		return interaction.Input {
			kind = .Key,
			stroke = interaction.Key_Stroke{kind = .Unicode_Scalar, scalar = value},
		}
	}
	_, note_failure := dispatch_session_input(
		&fixture.commands,
		&session,
		handle,
		interaction.Input{kind = .Text_Commit, text = "note"},
		constraints,
	)
	testing.expect_value(t, note_failure.stage, App_Stage.None)
	_, _, _ = editor_session.session_activate(&session, second.entry)
	_, second_edit_failure := dispatch_session_input(
		&fixture.commands,
		&session,
		handle,
		interaction.Input{kind = .Text_Commit, text = "2"},
		constraints,
	)
	testing.expect_value(t, second_edit_failure.stage, App_Stage.None)
	_, _, _ = editor_session.session_activate(&session, first.entry)
	_, first_edit_failure := dispatch_session_input(
		&fixture.commands,
		&session,
		handle,
		interaction.Input{kind = .Text_Commit, text = "1"},
		constraints,
	)
	testing.expect_value(t, first_edit_failure.stage, App_Stage.None)

	dispatch_session_input(&fixture.commands, &session, handle, control('x'), constraints)
	_, exit_start_failure := dispatch_session_input(
		&fixture.commands,
		&session,
		handle,
		control('c'),
		constraints,
	)
	testing.expect_value(t, exit_start_failure.stage, App_Stage.None)
	testing.expect_value(t, fixture.commands.prompt_workflow.mode, Prompt_Mode.Exit_Choice)
	first_save, first_save_failure := dispatch_session_input(
		&fixture.commands,
		&session,
		handle,
		plain('s'),
		constraints,
	)
	testing.expect_value(t, first_save_failure.stage, App_Stage.None)
	testing.expect(t, !first_save.exit)
	testing.expect_value(t, fixture.commands.prompt_workflow.mode, Prompt_Mode.Exit_Choice)
	usage, usage_ok, _ := editor_session.session_usage(&session, handle)
	testing.expect(t, usage_ok)
	testing.expect_value(t, usage.live_buffers, u32(3))
	cancelled, cancel_failure := dispatch_session_input(
		&fixture.commands,
		&session,
		handle,
		plain('c'),
		constraints,
	)
	testing.expect_value(t, cancel_failure.stage, App_Stage.None)
	testing.expect(t, cancelled.changed && !cancelled.exit)
	usage, usage_ok, _ = editor_session.session_usage(&session, handle)
	testing.expect(t, usage_ok)
	testing.expect_value(t, usage.live_buffers, u32(3))
	first_bytes, first_error := os.read_entire_file(first_path, context.allocator)
	testing.expect(t, first_error == nil)
	if first_error == nil {
		testing.expect_value(t, string(first_bytes), "1one")
		delete(first_bytes)
	}

	dispatch_session_input(&fixture.commands, &session, handle, control('x'), constraints)
	dispatch_session_input(&fixture.commands, &session, handle, control('c'), constraints)
	second_save, second_save_failure := dispatch_session_input(
		&fixture.commands,
		&session,
		handle,
		plain('s'),
		constraints,
	)
	testing.expect_value(t, second_save_failure.stage, App_Stage.None)
	testing.expect(t, !second_save.exit)
	testing.expect_value(t, fixture.commands.prompt_workflow.mode, Prompt_Mode.Exit_Choice)
	completed, complete_failure := dispatch_session_input(
		&fixture.commands,
		&session,
		handle,
		plain('d'),
		constraints,
	)
	testing.expect_value(t, complete_failure.stage, App_Stage.None)
	testing.expect(t, completed.exit)
	usage, usage_ok, _ = editor_session.session_usage(&session, handle)
	testing.expect(t, usage_ok)
	testing.expect_value(t, usage.live_buffers, u32(3))
	second_bytes, second_error := os.read_entire_file(second_path, context.allocator)
	testing.expect(t, second_error == nil)
	if second_error == nil {
		testing.expect_value(t, string(second_bytes), "2two")
		delete(second_bytes)
	}
	_, notes_found, _ := editor_session.session_find_label(&session, handle, "notes")
	testing.expect(t, notes_found)
	shutdown_failure := session_shutdown_close(&session, handle)
	testing.expect_value(t, shutdown_failure.stage, App_Stage.None)
}

/* Verifies startup argument admission accepts zero or one path and rejects extras. */
@(test)
startup_admits_zero_or_one_document_path :: proc(t: ^testing.T) {
	testing.expect_value(t, startup_arguments_validate(nil).stage, App_Stage.None)
	one := [1]string{"first.txt"}
	testing.expect_value(t, startup_arguments_validate(one[:]).stage, App_Stage.None)
	two := [2]string{"first.txt", "second.txt"}
	failure := startup_arguments_validate(two[:])
	testing.expect_value(t, failure.stage, App_Stage.Argument_Admission)
	testing.expect_value(t, failure.argument_count, u64(2))
}

/* Verifies pathless startup presents a UI root without publishing editor resources. */
@(test)
startup_ui_owns_no_buffer_graph :: proc(t: ^testing.T) {
	session: editor_session.Session
	handle, initialized, _ := editor_session.session_init(
		&session,
		editor_session.Session_ID(51),
		editor_session.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	testing.expect(t, initialized)
	if !initialized {
		return
	}
	target := startup_visible_target()
	_, visible, presented, _ := editor_session.session_present_ui(
		&session,
		handle,
		target.ui,
	)
	usage, usage_ok, _ := editor_session.session_usage(&session, handle)
	testing.expect(t, presented && usage_ok)
	testing.expect_value(t, visible.kind, editor_session.Visible_Target_Kind.UI_Root)
	testing.expect_value(t, usage.live_buffers, u32(0))
	testing.expect_value(t, usage.live_documents, u32(0))
	closed, _ := editor_session.session_close(&session)
	testing.expect(t, closed)
}

/* Verifies startup opens exact prepared bytes through the ordinary session workflow. */
@(test)
startup_opens_existing_document_text :: proc(t: ^testing.T) {
	directory, directory_error := os.make_directory_temp("", "odra-app-*", context.allocator)
	testing.expect(t, directory_error == nil)
	if directory_error != nil {
		return
	}
	defer {
		os.remove_all(directory)
		delete(directory)
	}
	path, path_error := os.join_path({directory, "opened.txt"}, context.allocator)
	testing.expect(t, path_error == nil)
	if path_error != nil {
		return
	}
	defer delete(path)
	contents := "opened\r\nUnicode: \U0001F642\n"
	testing.expect(t, os.write_entire_file(path, contents) == nil)

	session: editor_session.Session
	handle, initialized, _ := editor_session.session_init(
		&session,
		editor_session.Session_ID(53),
		editor_session.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	testing.expect(t, initialized)
	if !initialized {
		return
	}
	_, opened, open_failure := editor_session.session_open_path(
		&session,
		editor_session.Open_Path_Request {
			session = handle,
			path = path,
			encoding = .UTF8,
			configuration = editor_session.DEFAULT_ENTRY_CONFIGURATION,
		},
	)
	testing.expectf(t, opened, "startup failed with %v", open_failure.code)
	if !opened {
		editor_session.session_close(&session)
		return
	}
	access, access_ok, _ := editor_session.session_active_entry_access(&session, handle)
	entry, borrowed, _ := editor_session.entry_access_borrow(access)
	testing.expect(t, access_ok && borrowed)
	stats, stats_ok, _ := editor.buffer_stats(entry.buffer)
	testing.expect(t, stats_ok)
	bytes, allocation_error := make([]u8, int(stats.text_bytes), context.temp_allocator)
	testing.expect(t, allocation_error == nil)
	if allocation_error != nil {
		return
	}
	defer delete(bytes, context.temp_allocator)
	_, inspected, _ := editor.buffer_inspect(
		entry.buffer,
		0,
		editor.Byte_Offset(stats.text_bytes),
		bytes,
	)
	testing.expect(t, inspected)
	testing.expect_value(t, string(bytes), contents)
	status, status_ok, _ := document.document_status(entry.document)
	testing.expect(t, status_ok)
	testing.expect_value(t, status.persistence, document.Persistence_State.Clean)
	testing.expect(t, status.materialized && status.has_saved_revision)
	shutdown_failure := session_shutdown_close(&session, handle)
	testing.expect_value(t, shutdown_failure.stage, App_Stage.None)
}

/* Verifies the terminal frontend clamps physical geometry to measured projection limits. */
@(test)
geometry_uses_projection_bounds :: proc(t: ^testing.T) {
	ordinary := constraints_from_geometry(terminal.Geometry{width_cells = 80, height_rows = 24})
	testing.expect_value(
		t,
		ordinary,
		display.Viewport_Constraints{width_cells = 80, height_rows = 24},
	)
	large := constraints_from_geometry(terminal.Geometry{width_cells = 500, height_rows = 200})
	testing.expect_value(
		t,
		large,
		display.Viewport_Constraints {
			width_cells = display.OPERATING_VIEWPORT_WIDTH_CELLS,
			height_rows = display.OPERATING_VIEWPORT_HEIGHT_ROWS,
		},
	)
}

/* Verifies incremental literal search edits, repeats, reverses, recovers, and aborts. */
@(test)
search_keeps_text_and_origin :: proc(t: ^testing.T) {
	fixture: Interaction_Fixture
	if !interaction_fixture_init(t, &fixture, "zero alpha one alpha end") {
		return
	}
	defer interaction_fixture_close(&fixture)
	constraints := display.Viewport_Constraints{width_cells = 80, height_rows = 24}
	control := proc(value: rune) -> interaction.Input {
		return interaction.Input {
			kind = .Key,
			stroke = interaction.Key_Stroke {
				kind = .Unicode_Scalar,
				scalar = value,
				modifiers = {.Control},
			},
		}
	}
	started, start_failure := dispatch_input(
		&fixture.commands,
		&fixture.buffer,
		&fixture.registry,
		fixture.handle,
		control('s'),
		constraints,
	)
	testing.expect(t, started.changed && start_failure.stage == .None)
	testing.expect_value(t, fixture.commands.prompt_workflow.mode, Prompt_Mode.Incremental_Search)

	found, find_failure := dispatch_input(
		&fixture.commands,
		&fixture.buffer,
		&fixture.registry,
		fixture.handle,
		interaction.Input{kind = .Text_Commit, text = "alpha"},
		constraints,
	)
	testing.expect(t, found.changed && find_failure.stage == .None)
	logical, logical_ok, _ := editor_view.snapshot(&fixture.registry, fixture.handle)
	testing.expect(t, logical_ok)
	testing.expect_value(t, logical.point_position.byte_offset, editor.Byte_Offset(10))
	label, query_text, overlay_ok := command_context_overlay(
		&fixture.commands,
		&fixture.registry,
		fixture.handle,
	)
	testing.expect(t, overlay_ok)
	testing.expect_value(t, label, "Search → [smart/insensitive any exact]: ")
	testing.expect_value(t, query_text, "alpha")

	repeated, repeat_failure := dispatch_input(
		&fixture.commands,
		&fixture.buffer,
		&fixture.registry,
		fixture.handle,
		control('s'),
		constraints,
	)
	testing.expect(t, repeated.changed && repeat_failure.stage == .None)
	logical, _, _ = editor_view.snapshot(&fixture.registry, fixture.handle)
	testing.expect_value(t, logical.point_position.byte_offset, editor.Byte_Offset(20))

	reversed, reverse_failure := dispatch_input(
		&fixture.commands,
		&fixture.buffer,
		&fixture.registry,
		fixture.handle,
		control('r'),
		constraints,
	)
	testing.expect(t, reversed.changed && reverse_failure.stage == .None)
	logical, _, _ = editor_view.snapshot(&fixture.registry, fixture.handle)
	testing.expect_value(t, logical.point_position.byte_offset, editor.Byte_Offset(5))

	failed, failed_failure := dispatch_input(
		&fixture.commands,
		&fixture.buffer,
		&fixture.registry,
		fixture.handle,
		interaction.Input{kind = .Text_Commit, text = "x"},
		constraints,
	)
	testing.expect(t, failed.changed && failed_failure.stage == .None)
	_, _ = dispatch_input(
		&fixture.commands,
		&fixture.buffer,
		&fixture.registry,
		fixture.handle,
		control('r'),
		constraints,
	)
	search_view, search_ok, _ := editor_view.search_session_view(&fixture.registry, fixture.handle)
	testing.expect(t, search_ok && search_view.present)
	testing.expect_value(t, search_view.status, editor_view.Search_Status.Failing)
	testing.expect_value(t, search_view.last_successful_query, "alpha")
	label, _, overlay_ok = command_context_overlay(
		&fixture.commands,
		&fixture.registry,
		fixture.handle,
	)
	testing.expect(t, overlay_ok)
	testing.expect_value(t, label, "Failing Search ← [smart/insensitive any exact]: ")

	recovered, recover_failure := dispatch_input(
		&fixture.commands,
		&fixture.buffer,
		&fixture.registry,
		fixture.handle,
		control('g'),
		constraints,
	)
	testing.expect(t, recovered.changed && recover_failure.stage == .None)
	prompt_view, prompt_ok, _ := interaction.prompt_view(&fixture.commands.prompt_workflow.prompt)
	testing.expect(t, prompt_ok)
	testing.expect_value(t, prompt_view.text, "alpha")

	accepted, accept_failure := dispatch_input(
		&fixture.commands,
		&fixture.buffer,
		&fixture.registry,
		fixture.handle,
		interaction.Input{kind = .Key, stroke = interaction.Key_Stroke{kind = .Enter}},
		constraints,
	)
	testing.expect(t, accepted.changed && accept_failure.stage == .None)
	testing.expect_value(t, fixture.commands.prompt_workflow.mode, Prompt_Mode.None)
	logical, _, _ = editor_view.snapshot(&fixture.registry, fixture.handle)
	testing.expect_value(t, logical.point_position.byte_offset, editor.Byte_Offset(5))

	_, _ = dispatch_input(
		&fixture.commands,
		&fixture.buffer,
		&fixture.registry,
		fixture.handle,
		control('r'),
		constraints,
	)
	_, _ = dispatch_input(
		&fixture.commands,
		&fixture.buffer,
		&fixture.registry,
		fixture.handle,
		interaction.Input{kind = .Text_Commit, text = "alpha"},
		constraints,
	)
	search_view, search_ok, _ = editor_view.search_session_view(&fixture.registry, fixture.handle)
	testing.expect(t, search_ok && search_view.present)
	testing.expect_value(t, search_view.status, editor_view.Search_Status.Wrapped)
	label, _, overlay_ok = command_context_overlay(
		&fixture.commands,
		&fixture.registry,
		fixture.handle,
	)
	testing.expect(t, overlay_ok)
	testing.expect_value(t, label, "Wrapped Search ← [smart/insensitive any exact]: ")
	aborted, abort_failure := dispatch_input(
		&fixture.commands,
		&fixture.buffer,
		&fixture.registry,
		fixture.handle,
		control('g'),
		constraints,
	)
	testing.expect(t, aborted.changed && abort_failure.stage == .None)
	logical, _, _ = editor_view.snapshot(&fixture.registry, fixture.handle)
	testing.expect_value(t, logical.point_position.byte_offset, editor.Byte_Offset(5))
	expect_interaction_buffer(t, &fixture.buffer, "zero alpha one alpha end")
}

/* Verifies familiar highlight and occur commands retain their distinct accepted outcomes. */
@(test)
familiar_search_acceptance_retains_highlights_and_materializes_occur :: proc(t: ^testing.T) {
	constraints := display.Viewport_Constraints{width_cells = 80, height_rows = 24}
	enter := interaction.Input{kind = .Key, stroke = interaction.Key_Stroke{kind = .Enter}}

	highlight: Interaction_Fixture
	if interaction_fixture_init(t, &highlight, "needle one\nneedle two") {
		started, start_failure := command_context_begin_search(
			&highlight.commands,
			search.Direction.Forward,
			search.Pattern_Kind.Regular_Expression,
		)
		testing.expect(t, started.changed && start_failure.stage == .None)
		highlight.commands.search.post_accept = .Retain_Line_Highlight
		_, query_failure := dispatch_input(
			&highlight.commands,
			&highlight.buffer,
			&highlight.registry,
			highlight.handle,
			interaction.Input{kind = .Text_Commit, text = "needle"},
			constraints,
		)
		testing.expect_value(t, query_failure.stage, App_Stage.None)
		active, active_ok, _ := editor_view.search_session_view(&highlight.registry, highlight.handle)
		testing.expect(t, active_ok && active.present)
		if active_ok && active.present {
			testing.expect_value(t, active.presentation, editor_view.Search_Presentation.Lines)
		}
		accepted, accept_failure := dispatch_input(
			&highlight.commands,
			&highlight.buffer,
			&highlight.registry,
			highlight.handle,
			enter,
			constraints,
		)
		testing.expect(t, accepted.changed && accept_failure.stage == .None)
		retained, retained_ok, _ := editor_view.search_session_view(&highlight.registry, highlight.handle)
		testing.expect(t, retained_ok && retained.present)
		if retained_ok && retained.present {
			testing.expect_value(t, retained.presentation, editor_view.Search_Presentation.Lines)
			_, _ = command.incremental_search_accept(&highlight.registry, highlight.handle)
		}
		interaction_fixture_close(&highlight)
	}

	occur: Interaction_Fixture
	if interaction_fixture_init(t, &occur, "needle one\nneedle two") {
		entry, entry_ok, _ := editor_session.session_create_buffer(
			&occur.session,
			editor_session.Create_Buffer_Request {
				session = occur.session_handle,
				name = "occur-source",
				initial_contents = "needle one\nneedle two",
				configuration = editor_session.DEFAULT_ENTRY_CONFIGURATION,
			},
		)
		testing.expect(t, entry_ok)
		if !entry_ok {
			interaction_fixture_close(&occur)
			return
		}
		_, activated, _ := editor_session.session_activate(&occur.session, entry.entry)
		testing.expect(t, activated)
		access, accessed, _ := editor_session.session_entry_access(&occur.session, entry.entry)
		borrow, borrowed, _ := editor_session.entry_access_borrow(access)
		testing.expect(t, accessed && borrowed)
		if !activated || !accessed || !borrowed {
			interaction_fixture_close(&occur)
			return
		}
		command_context_bind_entry(&occur.commands, entry.entry, borrow)
		started, start_failure := command_context_begin_search(
			&occur.commands,
			search.Direction.Forward,
			search.Pattern_Kind.Regular_Expression,
		)
		testing.expect(t, started.changed && start_failure.stage == .None)
		occur.commands.search.post_accept = .Materialize_Results
		_, query_failure := dispatch_input(
			&occur.commands,
			borrow.buffer,
			borrow.view_registry,
			borrow.primary_view,
			interaction.Input{kind = .Text_Commit, text = "needle"},
			constraints,
		)
		testing.expect_value(t, query_failure.stage, App_Stage.None)
		accepted, accept_failure := dispatch_input(
			&occur.commands,
			borrow.buffer,
			borrow.view_registry,
			borrow.primary_view,
			enter,
			constraints,
		)
		testing.expect(t, accepted.changed && accept_failure.stage == .None)
		testing.expect(t, occur.commands.candidate_ui.session.state != nil)
		refreshed_access, refreshed_accessed, _ := editor_session.session_entry_access(
			&occur.session,
			entry.entry,
		)
		refreshed, refreshed_borrowed, _ := editor_session.entry_access_borrow(refreshed_access)
		testing.expect(t, refreshed_accessed && refreshed_borrowed)
		if !refreshed_accessed || !refreshed_borrowed {
			interaction_fixture_close(&occur)
			return
		}
		inactive, inactive_ok, _ := editor_view.search_session_view(
			refreshed.view_registry,
			refreshed.primary_view,
		)
		testing.expect(t, inactive_ok && !inactive.present)
		interaction_fixture_close(&occur)
	}
}

/* Verifies regexp search bindings, captures, diagnostics, recovery, and reversal. */
@(test)
regexp_search_uses_session_surface :: proc(t: ^testing.T) {
	fixture: Interaction_Fixture
	if !interaction_fixture_init(t, &fixture, "zero alpha-42 one beta-7 end") {
		return
	}
	defer interaction_fixture_close(&fixture)
	constraints := display.Viewport_Constraints{width_cells = 80, height_rows = 24}
	control_meta := proc(value: rune) -> interaction.Input {
		return interaction.Input {
			kind = .Key,
			stroke = interaction.Key_Stroke {
				kind = .Unicode_Scalar,
				scalar = value,
				modifiers = {.Control, .Meta},
			},
		}
	}
	control := proc(value: rune) -> interaction.Input {
		return interaction.Input {
			kind = .Key,
			stroke = interaction.Key_Stroke {
				kind = .Unicode_Scalar,
				scalar = value,
				modifiers = {.Control},
			},
		}
	}
	started, start_failure := dispatch_input(
		&fixture.commands,
		&fixture.buffer,
		&fixture.registry,
		fixture.handle,
		control_meta('s'),
		constraints,
	)
	testing.expect(t, started.changed && start_failure.stage == .None)
	testing.expect_value(t, fixture.commands.search.kind, search.Pattern_Kind.Regular_Expression)
	found, find_failure := dispatch_input(
		&fixture.commands,
		&fixture.buffer,
		&fixture.registry,
		fixture.handle,
		interaction.Input{kind = .Text_Commit, text = "([a-z]+)-([0-9]+)"},
		constraints,
	)
	testing.expect(t, found.changed && find_failure.stage == .None)
	logical, logical_ok, _ := editor_view.snapshot(&fixture.registry, fixture.handle)
	testing.expect(t, logical_ok)
	testing.expect_value(t, logical.point_position.byte_offset, editor.Byte_Offset(13))
	search_view, search_ok, _ := editor_view.search_session_view(&fixture.registry, fixture.handle)
	testing.expect(t, search_ok && search_view.present)
	testing.expect_value(t, search_view.kind, search.Pattern_Kind.Regular_Expression)
	testing.expect(t, search_view.has_current && len(search_view.occurrences) > 0)
	if search_view.has_current && len(search_view.occurrences) > 0 {
		current := search_view.occurrences[search_view.current_index]
		testing.expect_value(t, current.capture_count, u16(3))
		first_capture := int(current.first_capture)
		testing.expect_value(t, search_view.captures[first_capture + 1].start, editor.Byte_Offset(5))
		testing.expect_value(t, search_view.captures[first_capture + 1].end, editor.Byte_Offset(10))
		testing.expect_value(t, search_view.captures[first_capture + 2].start, editor.Byte_Offset(11))
		testing.expect_value(t, search_view.captures[first_capture + 2].end, editor.Byte_Offset(13))
	}
	label, _, overlay_ok := command_context_overlay(
		&fixture.commands,
		&fixture.registry,
		fixture.handle,
	)
	testing.expect(t, overlay_ok)
	testing.expect_value(t, label, "Regexp → [smart/insensitive any exact]: ")
	repeated, repeat_failure := dispatch_input(
		&fixture.commands,
		&fixture.buffer,
		&fixture.registry,
		fixture.handle,
		control_meta('s'),
		constraints,
	)
	testing.expect(t, repeated.changed && repeat_failure.stage == .None)
	logical, _, _ = editor_view.snapshot(&fixture.registry, fixture.handle)
	testing.expect_value(t, logical.point_position.byte_offset, editor.Byte_Offset(24))
	reversed, reverse_failure := dispatch_input(
		&fixture.commands,
		&fixture.buffer,
		&fixture.registry,
		fixture.handle,
		control_meta('r'),
		constraints,
	)
	testing.expect(t, reversed.changed && reverse_failure.stage == .None)
	logical, _, _ = editor_view.snapshot(&fixture.registry, fixture.handle)
	testing.expect_value(t, logical.point_position.byte_offset, editor.Byte_Offset(5))
	invalid, invalid_failure := dispatch_input(
		&fixture.commands,
		&fixture.buffer,
		&fixture.registry,
		fixture.handle,
		interaction.Input{kind = .Text_Commit, text = "("},
		constraints,
	)
	testing.expect(t, invalid.changed && invalid_failure.stage == .None)
	testing.expect(t, fixture.commands.prompt_workflow.rejected)
	label, _, overlay_ok = command_context_overlay(
		&fixture.commands,
		&fixture.registry,
		fixture.handle,
	)
	testing.expect(t, overlay_ok)
	testing.expect(t, strings.contains(label, "Regexp ←"))
	testing.expect(t, strings.contains(label, " at "))
	recovered, recover_failure := dispatch_input(
		&fixture.commands,
		&fixture.buffer,
		&fixture.registry,
		fixture.handle,
		control('g'),
		constraints,
	)
	testing.expect(t, recovered.changed && recover_failure.stage == .None)
	prompt_view, prompt_ok, _ := interaction.prompt_view(&fixture.commands.prompt_workflow.prompt)
	testing.expect(t, prompt_ok)
	testing.expect_value(t, prompt_view.text, "([a-z]+)-([0-9]+)")
	testing.expect(t, !fixture.commands.prompt_workflow.rejected)
	accepted, accept_failure := dispatch_input(
		&fixture.commands,
		&fixture.buffer,
		&fixture.registry,
		fixture.handle,
		interaction.Input{kind = .Key, stroke = interaction.Key_Stroke{kind = .Enter}},
		constraints,
	)
	testing.expect(t, accepted.changed && accept_failure.stage == .None)
	testing.expect_value(t, fixture.commands.prompt_workflow.mode, Prompt_Mode.None)
	expect_interaction_buffer(t, &fixture.buffer, "zero alpha-42 one beta-7 end")
}

/* Verifies accepted search history, live policy toggles, and query extension. */
@(test)
search_controls_reconfigure_query :: proc(t: ^testing.T) {
	fixture: Interaction_Fixture
	if !interaction_fixture_init(t, &fixture, "alpha beta alpha   beta") {
		return
	}
	defer interaction_fixture_close(&fixture)
	constraints := display.Viewport_Constraints{width_cells = 80, height_rows = 24}
	key := proc(value: rune, modifiers: interaction.Modifiers = {}) -> interaction.Input {
		return interaction.Input {
			kind = .Key,
			stroke = {kind = .Unicode_Scalar, scalar = value, modifiers = modifiers},
		}
	}
	special := proc(kind: interaction.Logical_Key_Kind) -> interaction.Input {
		return interaction.Input{kind = .Key, stroke = {kind = kind}}
	}

	_, _ = dispatch_input(&fixture.commands, &fixture.buffer, &fixture.registry, fixture.handle, key('s', {.Control}), constraints)
	_, _ = dispatch_input(
		&fixture.commands,
		&fixture.buffer,
		&fixture.registry,
		fixture.handle,
		interaction.Input{kind = .Text_Commit, text = "alpha"},
		constraints,
	)
	accepted, accept_failure := dispatch_input(
		&fixture.commands,
		&fixture.buffer,
		&fixture.registry,
		fixture.handle,
		special(.Enter),
		constraints,
	)
	testing.expect(t, accepted.changed && accept_failure.stage == .None)

	_, _ = dispatch_input(&fixture.commands, &fixture.buffer, &fixture.registry, fixture.handle, key('s', {.Control}), constraints)
	reused, reuse_failure := dispatch_input(
		&fixture.commands,
		&fixture.buffer,
		&fixture.registry,
		fixture.handle,
		key('s', {.Control}),
		constraints,
	)
	testing.expect(t, reused.changed && reuse_failure.stage == .None)
	prompt_view, prompt_ok, _ := interaction.prompt_view(&fixture.commands.prompt_workflow.prompt)
	testing.expect(t, prompt_ok)
	testing.expect_value(t, prompt_view.text, "alpha")

	_, _ = dispatch_input(&fixture.commands, &fixture.buffer, &fixture.registry, fixture.handle, key('s', {.Meta}), constraints)
	toggled, toggle_failure := dispatch_input(
		&fixture.commands,
		&fixture.buffer,
		&fixture.registry,
		fixture.handle,
		key('c'),
		constraints,
	)
	testing.expect(t, toggled.changed && toggle_failure.stage == .None)
	testing.expect_value(t, fixture.commands.search.policy.case_mode, search.Case_Mode.Sensitive)

	_, _ = dispatch_input(&fixture.commands, &fixture.buffer, &fixture.registry, fixture.handle, key('s', {.Meta}), constraints)
	_, toggle_failure = dispatch_input(&fixture.commands, &fixture.buffer, &fixture.registry, fixture.handle, key('w'), constraints)
	testing.expect_value(t, toggle_failure.stage, App_Stage.None)
	testing.expect_value(t, fixture.commands.search.policy.boundary_mode, search.Boundary_Mode.Word)

	_, _ = dispatch_input(&fixture.commands, &fixture.buffer, &fixture.registry, fixture.handle, key('s', {.Meta}), constraints)
	_, toggle_failure = dispatch_input(&fixture.commands, &fixture.buffer, &fixture.registry, fixture.handle, key(' '), constraints)
	testing.expect_value(t, toggle_failure.stage, App_Stage.None)
	testing.expect_value(t, fixture.commands.search.policy.whitespace_mode, search.Whitespace_Mode.Flexible)

	label, _, overlay_ok := command_context_overlay(&fixture.commands, &fixture.registry, fixture.handle)
	testing.expect(t, overlay_ok)
	testing.expect(t, strings.contains(label, "[sensitive word flex]"))

	_, _ = dispatch_input(&fixture.commands, &fixture.buffer, &fixture.registry, fixture.handle, key('g', {.Control}), constraints)
	_, _ = editor_view.set_point(
		&fixture.registry,
		fixture.handle,
		editor.Position{byte_offset = editor.Byte_Offset(6)},
	)
	_, _ = dispatch_input(&fixture.commands, &fixture.buffer, &fixture.registry, fixture.handle, key('s', {.Control}), constraints)
	extended, extension_failure := dispatch_input(
		&fixture.commands,
		&fixture.buffer,
		&fixture.registry,
		fixture.handle,
		key('w', {.Control}),
		constraints,
	)
	testing.expect(t, extended.changed && extension_failure.stage == .None)
	prompt_view, prompt_ok, _ = interaction.prompt_view(&fixture.commands.prompt_workflow.prompt)
	testing.expect(t, prompt_ok)
	testing.expect_value(t, prompt_view.text, "beta")
}

/* Verifies factory query replacement prompts, responses, rendering state, and grouped undo. */
@(test)
query_replace_is_visible_and_reversible :: proc(t: ^testing.T) {
	fixture: Interaction_Fixture
	if !interaction_fixture_init(t, &fixture, "one one") {
		return
	}
	defer interaction_fixture_close(&fixture)
	constraints := display.Viewport_Constraints{width_cells = 80, height_rows = 24}
	key := proc(value: rune, modifiers: interaction.Modifiers = {}) -> interaction.Input {
		return interaction.Input {
			kind = .Key,
			stroke = interaction.Key_Stroke {
				kind = .Unicode_Scalar,
				scalar = value,
				modifiers = modifiers,
			},
		}
	}
	enter := interaction.Input{kind = .Key, stroke = interaction.Key_Stroke{kind = .Enter}}
	started, start_failure := dispatch_input(
		&fixture.commands,
		&fixture.buffer,
		&fixture.registry,
		fixture.handle,
		key('%', {.Meta}),
		constraints,
	)
	testing.expect(t, started.changed && start_failure.stage == .None)
	testing.expect_value(t, fixture.commands.prompt_workflow.mode, Prompt_Mode.Query_Replacement_Pattern)
	_, _ = dispatch_input(
		&fixture.commands,
		&fixture.buffer,
		&fixture.registry,
		fixture.handle,
		interaction.Input{kind = .Text_Commit, text = "one"},
		constraints,
	)
	pattern_accepted, pattern_failure := dispatch_input(
		&fixture.commands,
		&fixture.buffer,
		&fixture.registry,
		fixture.handle,
		enter,
		constraints,
	)
	testing.expect(t, pattern_accepted.changed && pattern_failure.stage == .None)
	testing.expect_value(t, fixture.commands.prompt_workflow.mode, Prompt_Mode.Query_Replacement_Replacement)
	_, _ = dispatch_input(
		&fixture.commands,
		&fixture.buffer,
		&fixture.registry,
		fixture.handle,
		interaction.Input{kind = .Text_Commit, text = "two"},
		constraints,
	)
	replacement_accepted, replacement_failure := dispatch_input(
		&fixture.commands,
		&fixture.buffer,
		&fixture.registry,
		fixture.handle,
		enter,
		constraints,
	)
	testing.expect(t, replacement_accepted.changed && replacement_failure.stage == .None)
	testing.expect_value(t, fixture.commands.prompt_workflow.mode, Prompt_Mode.Query_Replacement_Response)
	label, text, overlay_ok := command_context_overlay(
		&fixture.commands,
		&fixture.registry,
		fixture.handle,
	)
	testing.expect(t, overlay_ok)
	testing.expect(t, strings.contains(label, "Query replace"))
	testing.expect(t, strings.contains(label, "y/SPC"))
	testing.expect_value(t, text, "one -> two")
	ui_registry: ui.Registry
	ui_initialized, _ := ui.registry_init(&ui_registry, 190)
	testing.expect(t, ui_initialized)
	if ui_initialized {
		proposal, prepared, _ := ui.proposal_begin(&ui_registry)
		_, active_style, _ := ui.proposal_add_style(&proposal, .Status_Active)
		_, rejected_style, _ := ui.proposal_add_style(&proposal, .Diagnostic_Rejected)
		input_view, projected, projection_failure := proposal_project_prompt_input(
			&proposal,
			&fixture.commands,
			{presentation_generation = 1, viewport_bytes = u32(len(text) + 1)},
			&fixture.registry,
			fixture.handle,
		)
		testing.expectf(t, projected, "query response projection failed: %v", projection_failure)
		surface, surfaced, _ := ui.proposal_add_surface(
			&proposal,
			ui.Surface_Descriptor {
				owner_id = ui.Owner_ID(prompt_mode_owner_id(.Query_Replacement_Response)),
				view = input_view,
				focusable = true,
				visible = true,
				required_profile = 1,
				geometry = {height = 1, width = 80},
			},
		)
		node, node_ok, _ := ui.proposal_add_surface_node(&proposal, surface)
		root_ok, _ := ui.proposal_set_root(&proposal, node, surface)
		root, published, publish_failure := ui.proposal_publish(
			&ui_registry,
			&proposal,
			transient_input_test_renderer(),
		)
		testing.expectf(t, published, "query response publish failed: %v", publish_failure)
		if published {
			snapshot, copied, _ := ui.registry_snapshot(
				&ui_registry,
				root,
				transient_input_test_renderer(),
			)
			testing.expect(t, copied)
			if copied {
				state, state_ok := ui.snapshot_view(&snapshot)
				projected_view := state.views[input_view.slot]
				value, value_ok := ui.snapshot_input_value(state, projected_view)
				choices, choices_ok := ui.snapshot_input_choices(state, projected_view)
				testing.expect(t, state_ok && value_ok && choices_ok)
				testing.expect_value(t, value, "one -> two")
				testing.expect_value(t, len(choices), 5)
				if len(choices) == 5 {
					name, name_ok := ui.snapshot_input_choice_name(state, choices[3])
					command_name, command_ok := prompt_input_choice_command(
						&fixture.commands,
						choices[3].action,
					)
					testing.expect(t, name_ok && command_ok)
					testing.expect_value(t, name, "[.] replace and exit")
					testing.expect_value(t, command_name, "query-replace-and-exit")
				}
				ui.snapshot_close(&snapshot)
			}
		}
		testing.expect(t, prepared && active_style && rejected_style && projected &&
			surfaced && node_ok && root_ok)
		ui.registry_close(&ui_registry)
	}

	first, first_failure := dispatch_input(
		&fixture.commands,
		&fixture.buffer,
		&fixture.registry,
		fixture.handle,
		key('y'),
		constraints,
	)
	testing.expect(t, first.changed && first_failure.stage == .None)
	expect_interaction_buffer(t, &fixture.buffer, "two one")
	last, last_failure := dispatch_input(
		&fixture.commands,
		&fixture.buffer,
		&fixture.registry,
		fixture.handle,
		key('.'),
		constraints,
	)
	testing.expect(t, last.changed && last_failure.stage == .None)
	testing.expect_value(t, fixture.commands.prompt_workflow.mode, Prompt_Mode.None)
	expect_interaction_buffer(t, &fixture.buffer, "two two")

	_, _ = dispatch_input(
		&fixture.commands,
		&fixture.buffer,
		&fixture.registry,
		fixture.handle,
		key('x', {.Control}),
		constraints,
	)
	undone, undo_failure := dispatch_input(
		&fixture.commands,
		&fixture.buffer,
		&fixture.registry,
		fixture.handle,
		key('u'),
		constraints,
	)
	testing.expect(t, undone.changed && undo_failure.stage == .None)
	expect_interaction_buffer(t, &fixture.buffer, "one one")
}

@(private)
App_Clipboard_Fake :: struct {
	read_storage:  [64]u8,
	read_bytes:    int,
	read_token:    terminal.Clipboard_Change_Token,
	write_storage: [1024]u8,
	write_bytes:   int,
	read_failure:  bool,
	write_failure: bool,
}

/* Verifies copy exports after retention and changed external text enters ordinary yank. */
@(test)
transfer_syncs_clipboard :: proc(t: ^testing.T) {
	fixture: Interaction_Fixture
	if !interaction_fixture_init(t, &fixture, "alpha") {
		return
	}
	defer interaction_fixture_close(&fixture)
	ring: kill_ring.Ring
	ring_ok, _ := kill_ring.ring_init(
		&ring,
		kill_ring.Ring_ID(301),
		kill_ring.Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, ring_ok)
	if !ring_ok {
		return
	}
	defer kill_ring.ring_close(&ring)
	fixture.commands.kill_ring = &ring

	fake := app_clipboard_fake("!", terminal.Clipboard_Change_Token(2))
	adapter: terminal.Clipboard_Adapter
	adapter_ok, _ := terminal.clipboard_adapter_init(
		&adapter,
		terminal.clipboard_default_config(),
		app_clipboard_transport(&fake),
	)
	testing.expect(t, adapter_ok)
	if !adapter_ok {
		return
	}
	defer terminal.clipboard_adapter_close(&adapter)
	fixture.commands.clipboard_workflow.adapter = &adapter

	marked, _ := editor_view.set_mark(
		&fixture.registry,
		fixture.handle,
		editor.Position {
			buffer_id = editor.Buffer_ID(101),
			revision = editor.Revision(0),
			byte_offset = 0,
		},
		true,
	)
	moved, _ := editor_view.move_point(
		&fixture.registry,
		fixture.handle,
		editor.Position {
			buffer_id = editor.Buffer_ID(101),
			revision = editor.Revision(0),
			byte_offset = 5,
		},
		5,
		.Preserve,
	)
	testing.expect(t, marked && moved)
	constraints := display.Viewport_Constraints{width_cells = 80, height_rows = 24}
	copied, copy_failure := dispatch_input(
		&fixture.commands,
		&fixture.buffer,
		&fixture.registry,
		fixture.handle,
		interaction.Input {
			kind = .Key,
			stroke = interaction.Key_Stroke {
				kind = .Unicode_Scalar,
				scalar = 'w',
				modifiers = {.Meta},
			},
		},
		constraints,
	)
	testing.expect(t, copied.changed && copy_failure.stage == .None)
	testing.expect_value(t, string(fake.write_storage[:fake.write_bytes]), "\x1b]52;c;YWxwaGE=\x07")
	testing.expect_value(
		t,
		fixture.commands.clipboard_workflow.transfer.last_export,
		command.Clipboard_Token(1),
	)

	yank_input := interaction.Input {
		kind = .Key,
		stroke = interaction.Key_Stroke {
			kind = .Unicode_Scalar,
			scalar = 'y',
			modifiers = {.Control},
		},
	}
	yanked, yank_failure := dispatch_input(
		&fixture.commands,
		&fixture.buffer,
		&fixture.registry,
		fixture.handle,
		yank_input,
		constraints,
	)
	testing.expect(t, yanked.changed && yank_failure.stage == .None)
	expect_interaction_buffer(t, &fixture.buffer, "alpha!")
	first_stats, first_stats_ok, _ := kill_ring.ring_stats(&ring)
	testing.expect(t, first_stats_ok)
	testing.expect_value(t, first_stats.usage.retained_entries, u64(2))

	yanked_again, second_yank_failure := dispatch_input(
		&fixture.commands,
		&fixture.buffer,
		&fixture.registry,
		fixture.handle,
		yank_input,
		constraints,
	)
	testing.expect(t, yanked_again.changed && second_yank_failure.stage == .None)
	expect_interaction_buffer(t, &fixture.buffer, "alpha!!")
	second_stats, second_stats_ok, _ := kill_ring.ring_stats(&ring)
	testing.expect(t, second_stats_ok)
	testing.expect_value(t, second_stats.usage.retained_entries, u64(2))
}

/* Verifies region transfer rejection remains inside the interactive session. */
@(test)
region_transfer_without_selection_is_safe :: proc(t: ^testing.T) {
	fixture: Interaction_Fixture
	if !interaction_fixture_init(t, &fixture, "alpha") {
		return
	}
	defer interaction_fixture_close(&fixture)
	ring: kill_ring.Ring
	ring_ok, _ := kill_ring.ring_init(
		&ring,
		kill_ring.Ring_ID(304),
		kill_ring.Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, ring_ok)
	if !ring_ok {
		return
	}
	defer kill_ring.ring_close(&ring)
	fixture.commands.kill_ring = &ring

	constraints := display.Viewport_Constraints{width_cells = 80, height_rows = 24}
	inputs := [2]interaction.Input {
		{
			kind = .Key,
			stroke = interaction.Key_Stroke {
				kind = .Unicode_Scalar,
				scalar = 'w',
				modifiers = {.Meta},
			},
		},
		{
			kind = .Key,
			stroke = interaction.Key_Stroke {
				kind = .Unicode_Scalar,
				scalar = 'w',
				modifiers = {.Control},
			},
		},
	}
	for input in inputs {
		result, failure := dispatch_input(
			&fixture.commands,
			&fixture.buffer,
			&fixture.registry,
			fixture.handle,
			input,
			constraints,
		)
		testing.expect(t, result.changed)
		testing.expect_value(t, failure.stage, App_Stage.None)
		testing.expect_value(
			t,
			string(fixture.commands.diagnostic[:fixture.commands.diagnostic_length]),
			"No active selection",
		)
		expect_interaction_buffer(t, &fixture.buffer, "alpha")
	}
}

/* Verifies clipboard export failure cannot roll back successful internal copy. */
@(test)
terminal_copy_survives_clipboard_export_failure :: proc(t: ^testing.T) {
	fixture: Interaction_Fixture
	if !interaction_fixture_init(t, &fixture, "safe") {
		return
	}
	defer interaction_fixture_close(&fixture)
	ring: kill_ring.Ring
	ring_ok, _ := kill_ring.ring_init(
		&ring,
		kill_ring.Ring_ID(302),
		kill_ring.Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, ring_ok)
	if !ring_ok {
		return
	}
	defer kill_ring.ring_close(&ring)
	fixture.commands.kill_ring = &ring
	fake := app_clipboard_fake("", terminal.Clipboard_Change_Token(1))
	fake.write_failure = true
	adapter: terminal.Clipboard_Adapter
	adapter_ok, _ := terminal.clipboard_adapter_init(
		&adapter,
		terminal.clipboard_default_config(),
		app_clipboard_transport(&fake),
	)
	testing.expect(t, adapter_ok)
	if !adapter_ok {
		return
	}
	defer terminal.clipboard_adapter_close(&adapter)
	fixture.commands.clipboard_workflow.adapter = &adapter

	editor_view.set_mark(
		&fixture.registry,
		fixture.handle,
		editor.Position{buffer_id = editor.Buffer_ID(101), revision = 0, byte_offset = 0},
		true,
	)
	editor_view.move_point(
		&fixture.registry,
		fixture.handle,
		editor.Position{buffer_id = editor.Buffer_ID(101), revision = 0, byte_offset = 4},
		4,
		.Preserve,
	)
	result, failure := dispatch_input(
		&fixture.commands,
		&fixture.buffer,
		&fixture.registry,
		fixture.handle,
		interaction.Input {
			kind = .Key,
			stroke = interaction.Key_Stroke {
				kind = .Unicode_Scalar,
				scalar = 'w',
				modifiers = {.Meta},
			},
		},
		display.Viewport_Constraints{width_cells = 80, height_rows = 24},
	)
	testing.expect(t, result.changed && failure.stage == .None)
	stats, stats_ok, _ := kill_ring.ring_stats(&ring)
	testing.expect(t, stats_ok)
	testing.expect_value(t, stats.usage.retained_entries, u64(1))
	expect_interaction_buffer(t, &fixture.buffer, "safe")
	testing.expect(t, fixture.commands.diagnostic_length > 0)
}

/* Verifies failed external import reports a diagnostic and yanks the internal entry. */
@(test)
yank_falls_back_on_clipboard_failure :: proc(t: ^testing.T) {
	fixture: Interaction_Fixture
	if !interaction_fixture_init(t, &fixture, "") {
		return
	}
	defer interaction_fixture_close(&fixture)
	ring: kill_ring.Ring
	ring_ok, _ := kill_ring.ring_init(
		&ring,
		kill_ring.Ring_ID(303),
		kill_ring.Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, ring_ok)
	if !ring_ok {
		return
	}
	defer kill_ring.ring_close(&ring)
	fixture.commands.kill_ring = &ring
	stats, stats_ok, _ := kill_ring.ring_stats(&ring)
	testing.expect(t, stats_ok)
	reservation: kill_ring.Reservation
	_, reserved, _ := kill_ring.admission_reserve(
		&ring,
		&reservation,
		kill_ring.Admission_Request {
			expected_generation = stats.generation,
			kind = .Copy,
			text = "internal",
		},
	)
	testing.expect(t, reserved)
	if !reserved {
		return
	}
	kill_ring.reservation_commit_reserved(&reservation)

	fake := app_clipboard_fake("external", terminal.Clipboard_Change_Token(4))
	fake.read_failure = true
	adapter: terminal.Clipboard_Adapter
	adapter_ok, _ := terminal.clipboard_adapter_init(
		&adapter,
		terminal.clipboard_default_config(),
		app_clipboard_transport(&fake),
	)
	testing.expect(t, adapter_ok)
	if !adapter_ok {
		return
	}
	defer terminal.clipboard_adapter_close(&adapter)
	fixture.commands.clipboard_workflow.adapter = &adapter

	yanked, yank_failure := dispatch_input(
		&fixture.commands,
		&fixture.buffer,
		&fixture.registry,
		fixture.handle,
		interaction.Input {
			kind = .Key,
			stroke = interaction.Key_Stroke {
				kind = .Unicode_Scalar,
				scalar = 'y',
				modifiers = {.Control},
			},
		},
		display.Viewport_Constraints{width_cells = 80, height_rows = 24},
	)
	testing.expect(t, yanked.changed && yank_failure.stage == .None)
	expect_interaction_buffer(t, &fixture.buffer, "internal")
	testing.expect(t, fixture.commands.diagnostic_length > 0)
	after, after_ok, _ := kill_ring.ring_stats(&ring)
	testing.expect(t, after_ok)
	testing.expect_value(t, after.usage.retained_entries, u64(1))
}

/* Verifies normalized events move by grapheme, reveal the cursor, and publish UTF-8 insertion. */
@(test)
terminal_events_edit_one_canonical_view :: proc(t: ^testing.T) {
	fixture: Interaction_Fixture
	ready := interaction_fixture_init(t, &fixture, "a🙂b\nx界z\nq")
	if !ready {
		return
	}
	defer interaction_fixture_close(&fixture)
	constraints := display.Viewport_Constraints{width_cells = 2, height_rows = 1}
	right := interaction.Input{kind = .Key, stroke = interaction.Key_Stroke{kind = .Right}}
	first, first_failure := dispatch_input(
		&fixture.commands,
		&fixture.buffer,
		&fixture.registry,
		fixture.handle,
		right,
		constraints,
	)
	testing.expect(t, first.changed && first_failure.stage == .None)
	second_right, second_right_failure := dispatch_input(
		&fixture.commands,
		&fixture.buffer,
		&fixture.registry,
		fixture.handle,
		right,
		constraints,
	)
	testing.expect(t, second_right.changed && second_right_failure.stage == .None)
	down := interaction.Input{kind = .Key, stroke = interaction.Key_Stroke{kind = .Down}}
	second, second_failure := dispatch_input(
		&fixture.commands,
		&fixture.buffer,
		&fixture.registry,
		fixture.handle,
		down,
		constraints,
	)
	testing.expect(t, second.changed && second_failure.stage == .None)
	state, _, _ := editor_view.snapshot(&fixture.registry, fixture.handle)
	testing.expect_value(t, state.point_position.byte_offset, editor.Byte_Offset(11))
	testing.expect_value(t, state.desired_display_column, u32(3))
	testing.expect_value(t, state.viewport_origin_position.byte_offset, editor.Byte_Offset(7))
	testing.expect_value(t, state.horizontal_display_column, u32(2))
	third, third_failure := dispatch_input(
		&fixture.commands,
		&fixture.buffer,
		&fixture.registry,
		fixture.handle,
		down,
		constraints,
	)
	testing.expect(t, third.changed && third_failure.stage == .None)
	insert := interaction.Input {
		kind = .Key,
		stroke = interaction.Key_Stroke{kind = .Unicode_Scalar, scalar = 'é'},
		text = "é",
	}
	inserted, insert_failure := dispatch_input(
		&fixture.commands,
		&fixture.buffer,
		&fixture.registry,
		fixture.handle,
		insert,
		constraints,
	)
	testing.expect(t, inserted.changed && insert_failure.stage == .None)
	current, _, _ := editor_view.snapshot(&fixture.registry, fixture.handle)
	testing.expect_value(t, current.revision, editor.Revision(1))
	testing.expect_value(t, current.point_position.byte_offset, editor.Byte_Offset(16))
	stats, _, _ := editor.buffer_stats(&fixture.buffer)
	bytes, allocation_error := make([]u8, int(stats.text_bytes), context.temp_allocator)
	testing.expect(t, allocation_error == nil)
	if allocation_error != nil {
		return
	}
	defer delete(bytes, context.temp_allocator)
	editor.buffer_inspect(&fixture.buffer, 0, editor.Byte_Offset(stats.text_bytes), bytes)
	testing.expect_value(t, string(bytes), "a🙂b\nx界z\nqé")
}

/* Verifies the built-in C-x u sequence reverses one grouped terminal typing unit. */
@(test)
terminal_control_x_u_undoes_grouped_typing :: proc(t: ^testing.T) {
	fixture: Interaction_Fixture
	if !interaction_fixture_init(t, &fixture, "") {
		return
	}
	defer interaction_fixture_close(&fixture)
	constraints := display.Viewport_Constraints{width_cells = 20, height_rows = 4}
	inputs := [2]interaction.Input {
		{kind = .Key, stroke = interaction.Key_Stroke{kind = .Unicode_Scalar, scalar = 'a'}, text = "a"},
		{kind = .Key, stroke = interaction.Key_Stroke{kind = .Unicode_Scalar, scalar = '界'}, text = "界"},
	}
	for input in inputs {
		result, failure := dispatch_input(
			&fixture.commands,
			&fixture.buffer,
			&fixture.registry,
			fixture.handle,
			input,
			constraints,
		)
		testing.expect(t, result.changed && failure.stage == .None)
	}
	stats, _, _ := history.store_stats(&fixture.history)
	testing.expect_value(t, stats.usage.retained_nodes, u64(2))
	testing.expect_value(t, stats.usage.retained_records, u64(2))
	control_x := interaction.Input {
		kind = .Key,
		stroke = interaction.Key_Stroke {
			kind = .Unicode_Scalar,
			scalar = 'x',
			modifiers = {.Control},
		},
	}
	pending, pending_failure := dispatch_input(
		&fixture.commands, &fixture.buffer, &fixture.registry, fixture.handle, control_x, constraints,
	)
	testing.expect(t, !pending.changed && pending_failure.stage == .None)
	undone, undo_failure := dispatch_input(
		&fixture.commands,
		&fixture.buffer,
		&fixture.registry,
		fixture.handle,
		interaction.Input {
			kind = .Key,
			stroke = interaction.Key_Stroke{kind = .Unicode_Scalar, scalar = 'u'},
		},
		constraints,
	)
	testing.expect(t, undone.changed && undo_failure.stage == .None)
	buffer_stats, _, _ := editor.buffer_stats(&fixture.buffer)
	testing.expect_value(t, buffer_stats.revision, editor.Revision(3))
	testing.expect_value(t, buffer_stats.text_bytes, u64(0))
	cursor, _, _ := editor_view.snapshot(&fixture.registry, fixture.handle)
	testing.expect_value(t, cursor.point_position.byte_offset, editor.Byte_Offset(0))
}

/* Verifies insertion failure preserves canonical text and current view state. */
@(test)
terminal_event_insertion_failure_is_atomic :: proc(t: ^testing.T) {
	fixture: Interaction_Fixture
	ready := interaction_fixture_init(t, &fixture, "stable")
	if !ready {
		return
	}
	defer interaction_fixture_close(&fixture)
	before, _, _ := editor_view.snapshot(&fixture.registry, fixture.handle)
	previous := fixture.commands.temporary_allocator
	fixture.commands.temporary_allocator = {}
	event := interaction.Input {
		kind = .Key,
		stroke = interaction.Key_Stroke{kind = .Unicode_Scalar, scalar = 'x'},
		text = "x",
	}
	_, failure := dispatch_input(
		&fixture.commands,
		&fixture.buffer,
		&fixture.registry,
		fixture.handle,
		event,
		display.Viewport_Constraints{width_cells = 8, height_rows = 1},
	)
	fixture.commands.temporary_allocator = previous
	testing.expect_value(t, failure.stage, App_Stage.Command_Dispatch)
	after, _, _ := editor_view.snapshot(&fixture.registry, fixture.handle)
	testing.expect_value(t, after.revision, before.revision)
	testing.expect_value(t, after.point_position, before.point_position)
}

/* Verifies key, text-fallback, and direct dispatch share active-state admission. */
@(test)
dispatch_enforces_interaction_state :: proc(t: ^testing.T) {
	fixture: Interaction_Fixture
	ready := interaction_fixture_init(t, &fixture, "stable")
	if !ready {
		return
	}
	defer interaction_fixture_close(&fixture)
	closed, close_failure := interaction.snapshot_close(&fixture.keymap)
	testing.expectf(t, closed, "legacy fixture keymap close failed with %v", close_failure.code)
	if !closed {
		return
	}

	state := [1]interaction.Interaction_State_Definition {{
		identity = {id = 2, revision = 1},
		name = "synthetic-navigation",
		admits_text_input = false,
		admitted_effects = {.View, .Lifecycle},
		provenance = {provider = "test", source = "state-aware-dispatch"},
	}}
	bindings := [1]interaction.Layered_Binding_Definition {{
		sequence = {
			strokes = {0 = {kind = .Left}},
			stroke_count = 1,
		},
		command_name = "cursor-previous-grapheme",
		operation = .Bind,
		scope = .Profile_Specific,
		provenance = {provider = "test", source = "state-aware-dispatch"},
	}}
	maps := [1]interaction.Map_Definition {{
		identity = {id = 1, revision = 1},
		name = "synthetic-base",
		precedence = .Profile_Base,
		bindings = bindings[:],
		unmatched_input_policy = .Reject,
		provenance = {provider = "test", source = "state-aware-dispatch"},
	}}
	profiles := [1]interaction.Profile_Definition {{
		identity = {id = 2, revision = 1},
		name = "synthetic",
		states = state[:],
		initial_state = 2,
		maps = maps[:],
		text_fallback_name = "insert-text",
	}}
	surfaces := [1]interaction.Command_Entry_Surface_Definition {{
		identity = {id = 1, revision = 1},
		name = "extended-command",
		provenance = {provider = "test", source = "state-aware-dispatch"},
	}}
	activation: interaction.Profile_Activation
	interaction.profile_activation_init(&activation)
	defer interaction.profile_activation_close(&activation)
	pending: interaction.Pending_State
	published, activation_failure := interaction.profile_activation_replace_catalog(
		&activation,
		&fixture.command_registry,
		interaction.Profile_Catalog_Definition {
			generation = 1,
			profiles = profiles[:],
			active_profile = 2,
			active_state = 2,
			surfaces = surfaces[:],
		},
		interaction.Active_Context {
			identity = {id = 1, generation = 1},
		},
		&pending,
		interaction.DEFAULT_PROFILE_COMPATIBILITY_POLICY,
		interaction.DEFAULT_RESOLUTION_POLICY,
		context.allocator,
	)
	testing.expectf(t, published, "state-aware fixture failed with %v", activation_failure.code)
	if !published {
		return
	}
	active, active_ok := interaction.profile_activation_snapshot(&activation)
	testing.expect(t, active_ok)
	if !active_ok {
		return
	}
	fixture.commands.keymap = active
	fixture.commands.profile_activation = &activation
	fixture.commands.pending = {}
	constraints := display.Viewport_Constraints{width_cells = 8, height_rows = 1}

	before, _, _ := editor.buffer_stats(&fixture.buffer)
	_, text_failure := dispatch_input(
		&fixture.commands,
		&fixture.buffer,
		&fixture.registry,
		fixture.handle,
		interaction.Input{kind = .Text_Commit, text = "x"},
		constraints,
	)
	testing.expect_value(t, text_failure.stage, App_Stage.None)
	after_text, _, _ := editor.buffer_stats(&fixture.buffer)
	testing.expect_value(t, after_text.revision, before.revision)
	_, contextual_resolution, contextual_ok, contextual_failure :=
		command_context_resolve_context_input(
			&fixture.commands,
			interaction.Input{kind = .Text_Commit, text = "x"},
		)
	testing.expect(t, contextual_ok)
	testing.expect_value(t, contextual_failure.stage, App_Stage.None)
	testing.expect_value(t, contextual_resolution.kind, interaction.Resolution_Kind.Unbound)

	_, navigation_failure := dispatch_input(
		&fixture.commands,
		&fixture.buffer,
		&fixture.registry,
		fixture.handle,
		interaction.Input {kind = .Key, stroke = {kind = .Left}},
		constraints,
	)
	testing.expect_value(t, navigation_failure.stage, App_Stage.None)
	uppercase, uppercase_ok, _ := interaction.command_lookup(
		&fixture.command_registry,
		"uppercase-current-line",
	)
	testing.expect(t, uppercase_ok)
	_, direct_failure := dispatch_input(
		&fixture.commands,
		&fixture.buffer,
		&fixture.registry,
		fixture.handle,
		{},
		constraints,
		uppercase,
	)
	testing.expect_value(t, direct_failure.stage, App_Stage.Command_Dispatch)
	testing.expect_value(
		t,
		direct_failure.interaction.code,
		interaction.Failure_Code.Command_Effect_Rejected,
	)
	after_direct, _, _ := editor.buffer_stats(&fixture.buffer)
	testing.expect_value(t, after_direct.revision, before.revision)
}

/* Verifies prefix, cancellation, unbound control, and exit use the active keymap. */
@(test)
commands_resolve_cancel_and_exit :: proc(t: ^testing.T) {
	fixture: Interaction_Fixture
	ready := interaction_fixture_init(t, &fixture, "stable")
	if !ready {
		return
	}
	defer interaction_fixture_close(&fixture)
	constraints := display.Viewport_Constraints{width_cells = 8, height_rows = 1}
	control_x := interaction.Input {
		kind = .Key,
		stroke = interaction.Key_Stroke {
			kind = .Unicode_Scalar,
			scalar = 'x',
			modifiers = {.Control},
		},
	}
	pending, pending_failure := dispatch_input(
		&fixture.commands,
		&fixture.buffer,
		&fixture.registry,
		fixture.handle,
		control_x,
		constraints,
	)
	testing.expect(t, !pending.changed && !pending.exit && pending_failure.stage == .None)
	testing.expect_value(t, fixture.commands.pending.stroke_count, u8(1))
	control_g := interaction.Input {
		kind = .Key,
		stroke = interaction.Key_Stroke {
			kind = .Unicode_Scalar,
			scalar = 'g',
			modifiers = {.Control},
		},
	}
	cancelled, cancel_failure := dispatch_input(
		&fixture.commands,
		&fixture.buffer,
		&fixture.registry,
		fixture.handle,
		control_g,
		constraints,
	)
	testing.expect(t, !cancelled.changed && !cancelled.exit && cancel_failure.stage == .None)
	testing.expect_value(t, fixture.commands.pending.stroke_count, u8(0))
	control_q := control_x
	control_q.stroke.scalar = 'q'
	unbound, unbound_failure := dispatch_input(
		&fixture.commands,
		&fixture.buffer,
		&fixture.registry,
		fixture.handle,
		control_q,
		constraints,
	)
	testing.expect(t, !unbound.changed && !unbound.exit && unbound_failure.stage == .None)
	fixture.commands.session_owner = nil
	dispatch_input(
		&fixture.commands,
		&fixture.buffer,
		&fixture.registry,
		fixture.handle,
		control_x,
		constraints,
	)
	prompted, exit_failure := dispatch_input(
		&fixture.commands,
		&fixture.buffer,
		&fixture.registry,
		fixture.handle,
		interaction.Input {
			kind = .Key,
			stroke = interaction.Key_Stroke {
				kind = .Unicode_Scalar,
				scalar = 'c',
				modifiers = {.Control},
			},
		},
		constraints,
	)
	testing.expect(t, !prompted.exit && prompted.changed && exit_failure.stage == .None)
	testing.expect_value(t, fixture.commands.prompt_workflow.mode, Prompt_Mode.Exit_Choice)
	exited, discard_failure := dispatch_input(
		&fixture.commands,
		&fixture.buffer,
		&fixture.registry,
		fixture.handle,
		interaction.Input {
			kind = .Key,
			stroke = interaction.Key_Stroke{kind = .Unicode_Scalar, scalar = 'd'},
			text = "d",
		},
		constraints,
	)
	testing.expect(t, exited.exit && !exited.changed && discard_failure.stage == .None)
}

/* Verifies an unassociated save enters a bounded path prompt and materializes its target. */
@(test)
save_prompt_handles_private_targets :: proc(t: ^testing.T) {
	fixture: Interaction_Fixture
	ready := interaction_fixture_init(t, &fixture, "prompt text")
	if !ready {
		return
	}
	defer interaction_fixture_close(&fixture)
	directory, directory_error := os.make_directory_temp("", "odra-prompt-*", context.allocator)
	testing.expect(t, directory_error == nil)
	if directory_error != nil {
		return
	}
	defer {
		os.remove_all(directory)
		delete(directory)
	}
	path, path_error := os.join_path({directory, "saved.txt"}, context.allocator)
	testing.expect(t, path_error == nil)
	if path_error != nil {
		return
	}
	defer delete(path)
	constraints := display.Viewport_Constraints{width_cells = 80, height_rows = 24}

	control_x := interaction.Input {
		kind = .Key,
		stroke = interaction.Key_Stroke {
			kind = .Unicode_Scalar,
			scalar = 'x',
			modifiers = {.Control},
		},
	}
	control_s := interaction.Input {
		kind = .Key,
		stroke = interaction.Key_Stroke {
			kind = .Unicode_Scalar,
			scalar = 's',
			modifiers = {.Control},
		},
	}
	dispatch_input(&fixture.commands, &fixture.buffer, &fixture.registry, fixture.handle, control_x, constraints)
	prompted, prompt_failure := dispatch_input(
		&fixture.commands,
		&fixture.buffer,
		&fixture.registry,
		fixture.handle,
		control_s,
		constraints,
	)
	testing.expect(t, prompted.changed && prompt_failure.stage == .None)
	testing.expect_value(t, fixture.commands.prompt_workflow.mode, Prompt_Mode.Save_Path)
	_, path_input_failure := dispatch_input(
		&fixture.commands,
		&fixture.buffer,
		&fixture.registry,
		fixture.handle,
		interaction.Input {
			kind = .Key,
			stroke = interaction.Key_Stroke{kind = .Unicode_Scalar, scalar = 'p'},
			text = path,
		},
		constraints,
	)
	testing.expect_value(t, path_input_failure.stage, App_Stage.None)
	saved, save_failure := dispatch_input(
		&fixture.commands,
		&fixture.buffer,
		&fixture.registry,
		fixture.handle,
		interaction.Input{kind = .Key, stroke = interaction.Key_Stroke{kind = .Enter}},
		constraints,
	)
	testing.expect(t, saved.changed && save_failure.stage == .None)
	testing.expect_value(t, saved.save.publication, document.Publication_State.Published_Durable)
	contents, read_error := os.read_entire_file(path, context.temp_allocator)
	testing.expect(t, read_error == nil)
	if read_error == nil {
		testing.expect_value(t, string(contents), "prompt text")
	}
	status, status_ok, _ := document.document_status(&fixture.document)
	testing.expect(t, status_ok)
	testing.expect(t, status.materialized)
	testing.expect_value(t, status.persistence, document.Persistence_State.Clean)
}

/* Verifies unsaved exit can cancel, chain through first-save naming, and exit after publication. */
@(test)
unsaved_exit_handles_unassociated_buffer :: proc(t: ^testing.T) {
	fixture: Interaction_Fixture
	ready := interaction_fixture_init(t, &fixture, "exit text")
	if !ready {
		return
	}
	defer interaction_fixture_close(&fixture)
	fixture.commands.session_owner = nil
	directory, directory_error := os.make_directory_temp("", "odra-exit-*", context.allocator)
	testing.expect(t, directory_error == nil)
	if directory_error != nil {
		return
	}
	defer {
		os.remove_all(directory)
		delete(directory)
	}
	path, path_error := os.join_path({directory, "saved.txt"}, context.allocator)
	testing.expect(t, path_error == nil)
	if path_error != nil {
		return
	}
	defer delete(path)
	constraints := display.Viewport_Constraints{width_cells = 80, height_rows = 24}

	request_fixture_exit(&fixture, constraints)
	ignored, ignored_failure := dispatch_input(
		&fixture.commands,
		&fixture.buffer,
		&fixture.registry,
		fixture.handle,
		interaction.Input {
			kind = .Key,
			stroke = interaction.Key_Stroke{kind = .Unicode_Scalar, scalar = 'z'},
			text = "z",
		},
		constraints,
	)
	testing.expect(t, !ignored.changed && !ignored.exit && ignored_failure.stage == .None)
	testing.expect_value(t, fixture.commands.prompt_workflow.mode, Prompt_Mode.Exit_Choice)
	cancelled, cancel_failure := dispatch_input(
		&fixture.commands,
		&fixture.buffer,
		&fixture.registry,
		fixture.handle,
		interaction.Input {
			kind = .Key,
			stroke = interaction.Key_Stroke{kind = .Unicode_Scalar, scalar = 'c'},
			text = "c",
		},
		constraints,
	)
	testing.expect(t, cancelled.changed && !cancelled.exit && cancel_failure.stage == .None)
	testing.expect_value(t, fixture.commands.prompt_workflow.mode, Prompt_Mode.None)

	request_fixture_exit(&fixture, constraints)
	path_prompt, save_choice_failure := dispatch_input(
		&fixture.commands,
		&fixture.buffer,
		&fixture.registry,
		fixture.handle,
		interaction.Input {
			kind = .Key,
			stroke = interaction.Key_Stroke{kind = .Unicode_Scalar, scalar = 's'},
			text = "s",
		},
		constraints,
	)
	testing.expect(t, path_prompt.changed && !path_prompt.exit && save_choice_failure.stage == .None)
	testing.expect_value(t, fixture.commands.prompt_workflow.mode, Prompt_Mode.Exit_Save_Path)
	cancelled_path, path_cancel_failure := dispatch_input(
		&fixture.commands,
		&fixture.buffer,
		&fixture.registry,
		fixture.handle,
		interaction.Input {
			kind = .Key,
			stroke = interaction.Key_Stroke {
				kind = .Unicode_Scalar,
				scalar = 'g',
				modifiers = {.Control},
			},
		},
		constraints,
	)
	testing.expect(t, cancelled_path.changed && !cancelled_path.exit && path_cancel_failure.stage == .None)

	request_fixture_exit(&fixture, constraints)
	dispatch_input(
		&fixture.commands,
		&fixture.buffer,
		&fixture.registry,
		fixture.handle,
		interaction.Input {
			kind = .Key,
			stroke = interaction.Key_Stroke{kind = .Unicode_Scalar, scalar = 's'},
			text = "s",
		},
		constraints,
	)
	dispatch_input(
		&fixture.commands,
		&fixture.buffer,
		&fixture.registry,
		fixture.handle,
		interaction.Input {
			kind = .Key,
			stroke = interaction.Key_Stroke{kind = .Unicode_Scalar, scalar = 'p'},
			text = path,
		},
		constraints,
	)
	exited, save_failure := dispatch_input(
		&fixture.commands,
		&fixture.buffer,
		&fixture.registry,
		fixture.handle,
		interaction.Input{kind = .Key, stroke = interaction.Key_Stroke{kind = .Enter}},
		constraints,
	)
	testing.expect(t, exited.exit && exited.changed && save_failure.stage == .None)
	testing.expect_value(t, exited.save.publication, document.Publication_State.Published_Durable)
	contents, read_error := os.read_entire_file(path, context.temp_allocator)
	testing.expect(t, read_error == nil)
	if read_error == nil {
		testing.expect_value(t, string(contents), "exit text")
	}
}

/* Verifies clean exit is immediate and a failed exit-save preserves the application. */
@(test)
exit_checks_revision_and_save_failure :: proc(t: ^testing.T) {
	directory, directory_error := os.make_directory_temp("", "odra-exit-state-*", context.allocator)
	testing.expect(t, directory_error == nil)
	if directory_error != nil {
		return
	}
	defer {
		os.remove_all(directory)
		delete(directory)
	}
	path, path_error := os.join_path({directory, "document.txt"}, context.allocator)
	testing.expect(t, path_error == nil)
	if path_error != nil {
		return
	}
	defer delete(path)
	write_error := os.write_entire_file(path, "saved")
	testing.expect(t, write_error == nil)
	if write_error != nil {
		return
	}
	constraints := display.Viewport_Constraints{width_cells = 80, height_rows = 24}

	clean: Interaction_Fixture
	clean_ready := interaction_fixture_init(t, &clean, "saved", path)
	if !clean_ready {
		return
	}
	clean.commands.session_owner = nil
	clean_exit := request_fixture_exit(&clean, constraints)
	testing.expect(t, clean_exit.exit && !clean_exit.changed)
	interaction_fixture_close(&clean)

	missing_path, missing_error := os.join_path({directory, "new.txt"}, context.allocator)
	testing.expect(t, missing_error == nil)
	if missing_error != nil {
		return
	}
	defer delete(missing_path)
	failing: Interaction_Fixture
	failing_ready := interaction_fixture_init(t, &failing, "unsaved", missing_path)
	if !failing_ready {
		return
	}
	failing.commands.session_owner = nil
	defer interaction_fixture_close(&failing)
	os.remove_all(directory)
	prompted := request_fixture_exit(&failing, constraints)
	testing.expect(t, prompted.changed && !prompted.exit)
	continued, save_failure := dispatch_input(
		&failing.commands,
		&failing.buffer,
		&failing.registry,
		failing.handle,
		interaction.Input {
			kind = .Key,
			stroke = interaction.Key_Stroke{kind = .Unicode_Scalar, scalar = 's'},
			text = "s",
		},
		constraints,
	)
	testing.expect(t, continued.changed && !continued.exit && save_failure.stage == .None)
	testing.expect(t, failing.commands.diagnostic_length > 0)
}

/* Verifies rigid indentation retains its checked region across revisions and cancels cleanly. */
@(test)
rigid_indentation_transient_map_tracks_the_selected_region :: proc(t: ^testing.T) {
	fixture: Interaction_Fixture
	if !interaction_fixture_init(t, &fixture, "alpha\n beta\n") do return
	defer interaction_fixture_close(&fixture)
	start, start_ok, _ := editor.buffer_position(&fixture.buffer, 0)
	end, end_ok, _ := editor.buffer_position(&fixture.buffer, editor.Byte_Offset(len("alpha\n beta")))
	testing.expect(t, start_ok && end_ok)
	if !start_ok || !end_ok do return
	selected, _ := editor_view.select_range(
		&fixture.registry,
		fixture.handle,
		start,
		end,
		0,
	)
	testing.expect(t, selected)
	if !selected do return
	started, start_failure := command_context_begin_rigid_indentation(
		&fixture.commands,
		&fixture.buffer,
		&fixture.registry,
		fixture.handle,
	)
	testing.expect(t, started.changed && start_failure.stage == .None)
	testing.expect(t, rigid_indentation_active(&fixture.commands))
	constraints := display.Viewport_Constraints{width_cells = 80, height_rows = 24}
	right, right_failure := dispatch_input(
		&fixture.commands,
		&fixture.buffer,
		&fixture.registry,
		fixture.handle,
		interaction.Input{kind = .Key, stroke = interaction.Key_Stroke{kind = .Right}},
		constraints,
	)
	testing.expect(t, right.changed && right_failure.stage == .None)
	expect_interaction_buffer(t, &fixture.buffer, " alpha\n  beta\n")
	fast, fast_failure := dispatch_input(
		&fixture.commands,
		&fixture.buffer,
		&fixture.registry,
		fixture.handle,
		interaction.Input{
			kind = .Key,
			stroke = interaction.Key_Stroke{kind = .Right, modifiers = {.Shift}},
		},
		constraints,
	)
	testing.expect(t, fast.changed && fast_failure.stage == .None)
	expect_interaction_buffer(t, &fixture.buffer, "     alpha\n      beta\n")
	_, cancel_failure := dispatch_input(
		&fixture.commands,
		&fixture.buffer,
		&fixture.registry,
		fixture.handle,
		interaction.Input{
			kind = .Key,
			stroke = interaction.Key_Stroke{kind = .Unicode_Scalar, scalar = 'g', modifiers = {.Control}},
		},
		constraints,
	)
	testing.expect(t, cancel_failure.stage == .None)
	testing.expect(t, !rigid_indentation_active(&fixture.commands))
}

/* Verifies keyboard macros record canonical commands, replay, and cancel safely. */
@(test)
keyboard_macro_workflow_records_replays_and_preserves_last_on_cancel :: proc(t: ^testing.T) {
	fixture: Interaction_Fixture
	if !interaction_fixture_init(t, &fixture, "text") do return
	defer interaction_fixture_close(&fixture)
	constraints := display.Viewport_Constraints{width_cells = 80, height_rows = 24}
	start, start_found, _ := interaction.command_lookup(&fixture.command_registry, "start-kbd-macro")
	finish, finish_found, _ := interaction.command_lookup(&fixture.command_registry, "end-kbd-macro")
	replay, replay_found, _ := interaction.command_lookup(&fixture.command_registry, "call-last-kbd-macro")
	insert, insert_found, _ := interaction.command_lookup(&fixture.command_registry, "insert-text")
	cancel, cancel_found, _ := interaction.command_lookup(&fixture.command_registry, "keyboard-quit")
	testing.expect(t, start_found && finish_found && replay_found && insert_found && cancel_found)
	if !start_found || !finish_found || !replay_found || !insert_found || !cancel_found do return
	_, start_failure := dispatch_input(
		&fixture.commands, &fixture.buffer, &fixture.registry, fixture.handle,
		{}, constraints, start,
	)
	testing.expect(t, start_failure.stage == .None)
	_, insert_failure := dispatch_input(
		&fixture.commands, &fixture.buffer, &fixture.registry, fixture.handle,
		{}, constraints, insert, "A",
	)
	testing.expect(t, insert_failure.stage == .None)
	_, finish_failure := dispatch_input(
		&fixture.commands, &fixture.buffer, &fixture.registry, fixture.handle,
		{}, constraints, finish,
	)
	testing.expect(t, finish_failure.stage == .None)
	_, replay_failure := dispatch_input(
		&fixture.commands, &fixture.buffer, &fixture.registry, fixture.handle,
		{}, constraints, replay,
	)
	testing.expect(t, replay_failure.stage == .None)
	expect_interaction_buffer(t, &fixture.buffer, "AAtext")
	_, _ = dispatch_input(
		&fixture.commands, &fixture.buffer, &fixture.registry, fixture.handle,
		{}, constraints, start,
	)
	_, _ = dispatch_input(
		&fixture.commands, &fixture.buffer, &fixture.registry, fixture.handle,
		{}, constraints, insert, "B",
	)
	_, cancel_failure := dispatch_input(
		&fixture.commands, &fixture.buffer, &fixture.registry, fixture.handle,
		{}, constraints, cancel,
	)
	testing.expect(t, cancel_failure.stage == .None)
	_, replay_failure = dispatch_input(
		&fixture.commands, &fixture.buffer, &fixture.registry, fixture.handle,
		{}, constraints, replay,
	)
	testing.expect(t, replay_failure.stage == .None)
	expect_interaction_buffer(t, &fixture.buffer, "AABAtext")
}

@(private)
Interaction_Fixture :: struct {
	buffer:   editor.Buffer,
	document: document.Document,
	history:  history.Store,
	registry: editor_view.Registry,
	handle:   editor_view.View_Handle,
	command_registry: interaction.Command_Registry,
	keymap:            interaction.Resolution_Snapshot,
	context_maps:      interaction.Context_Map_Stack,
	session:           editor_session.Session,
	session_handle:    editor_session.Session_Handle,
	commands:          Command_Context,
}

@(private)
interaction_fixture_init :: proc(
	t: ^testing.T,
	fixture: ^Interaction_Fixture,
	text: string,
	path := "",
) -> bool {
	buffer_ok, buffer_failure := editor.buffer_init(
		&fixture.buffer,
		editor.Buffer_ID(101),
		text,
		editor.Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	testing.expectf(t, buffer_ok, "buffer failed with %v", buffer_failure.code)
	if !buffer_ok {
		return false
	}
	prepared_document: document.Prepared_Open
	prepared_ok, document_failure := document.open_prepare(
		&prepared_document,
			document.Open_Request {
				document_id = document.Document_ID(101),
				buffer_id = editor.Buffer_ID(101),
				has_path = len(path) > 0,
				path = path,
				encoding = .UTF8,
		},
		document.Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	testing.expectf(t, prepared_ok, "document failed with %v", document_failure.code)
	if !prepared_ok {
		editor.buffer_close(&fixture.buffer)
		return false
	}
	document_ok, document_commit_failure := document.prepared_open_commit(
		&prepared_document,
		&fixture.document,
		editor.Revision(0),
	)
	testing.expectf(t, document_ok, "document commit failed with %v", document_commit_failure.code)
	if !document_ok {
		document.prepared_open_abort(&prepared_document)
		editor.buffer_close(&fixture.buffer)
		return false
	}
	registry_ok, registry_failure := editor_view.registry_init(
		&fixture.registry,
		editor_view.Registry_ID(101),
		context.allocator,
	)
	testing.expectf(t, registry_ok, "registry failed with %v", registry_failure.code)
	if !registry_ok {
		editor.buffer_close(&fixture.buffer)
		return false
	}
	handle, created, view_failure := editor_view.create(&fixture.registry, &fixture.buffer)
	testing.expectf(t, created, "view failed with %v", view_failure.code)
	if !created {
		editor_view.registry_close(&fixture.registry)
		editor.buffer_close(&fixture.buffer)
		return false
	}
	fixture.handle = handle
	history_ok, history_failure := history.store_init(
		&fixture.history,
		history.Store_ID(101),
		editor.Buffer_ID(101),
		editor.Revision(0),
		history.Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	testing.expectf(t, history_ok, "history failed with %v", history_failure.code)
	if !history_ok {
		editor_view.close(&fixture.registry, &fixture.handle)
		editor_view.registry_close(&fixture.registry)
		editor.buffer_close(&fixture.buffer)
		return false
	}
	racket_definitions := [?]interaction.Command_Definition {{
		name = "uppercase-current-line",
		route = command.racket_route(.Transaction, 1),
		implementation = .Racket,
		invocation = .Ordinary,
		text_requirement = .Prohibited,
		effects = {.Buffer, .View, .Text_Mutation},
		description = "Uppercase the current logical line.",
		interactive = true,
		requirements = {.Active_Buffer},
		provenance = {provider = "test", source = "app-test"},
	}}
	commands_ok, commands_failure := command.built_in_command_registry_init(
		&fixture.command_registry,
		interaction.Registry_Generation(101),
		context.allocator,
		racket_definitions[:],
	)
	testing.expectf(t, commands_ok, "commands failed with %v", commands_failure.code)
	if !commands_ok {
		editor_view.close(&fixture.registry, &fixture.handle)
		editor_view.registry_close(&fixture.registry)
		editor.buffer_close(&fixture.buffer)
		return false
	}
	bindings := [19]interaction.Binding_Definition {
		{
			strokes = {
				0 = interaction.Key_Stroke {
					kind = .Unicode_Scalar,
					scalar = 'x',
					modifiers = {.Control},
				},
				1 = interaction.Key_Stroke{kind = .Unicode_Scalar, scalar = 'u'},
			},
			stroke_count = 2,
			command_name = "undo",
		},
		{
			strokes = {0 = interaction.Key_Stroke{kind = .Right}},
			stroke_count = 1,
			command_name = "cursor-next-grapheme",
		},
		{
			strokes = {0 = interaction.Key_Stroke{kind = .Down}},
			stroke_count = 1,
			command_name = "cursor-next-line",
		},
		{
			strokes = {0 = interaction.Key_Stroke{kind = .Left}},
			stroke_count = 1,
			command_name = "cursor-previous-grapheme",
		},
		{
			strokes = {0 = interaction.Key_Stroke {
				kind = .Unicode_Scalar,
				scalar = 'x',
				modifiers = {.Meta},
			}},
			stroke_count = 1,
			command_name = "execute-extended-command",
		},
		{
			strokes = {0 = interaction.Key_Stroke {
				kind = .Unicode_Scalar,
				scalar = 's',
				modifiers = {.Control},
			}},
			stroke_count = 1,
			command_name = "isearch-forward",
		},
		{
			strokes = {0 = interaction.Key_Stroke {
				kind = .Unicode_Scalar,
				scalar = 'r',
				modifiers = {.Control},
			}},
			stroke_count = 1,
			command_name = "isearch-backward",
		},
		{
			strokes = {0 = interaction.Key_Stroke {
				kind = .Unicode_Scalar,
				scalar = 's',
				modifiers = {.Control, .Meta},
			}},
			stroke_count = 1,
			command_name = "isearch-forward-regexp",
		},
		{
			strokes = {0 = interaction.Key_Stroke {
				kind = .Unicode_Scalar,
				scalar = 'r',
				modifiers = {.Control, .Meta},
			}},
			stroke_count = 1,
			command_name = "isearch-backward-regexp",
		},
		{
			strokes = {0 = interaction.Key_Stroke {
				kind = .Unicode_Scalar,
				scalar = '%',
				modifiers = {.Meta},
			}},
			stroke_count = 1,
			command_name = "query-replace",
		},
		{
			strokes = {0 = interaction.Key_Stroke {
				kind = .Unicode_Scalar,
				scalar = '%',
				modifiers = {.Control, .Meta},
			}},
			stroke_count = 1,
			command_name = "query-replace-regexp",
		},
		{
			strokes = {
				0 = interaction.Key_Stroke {
					kind = .Unicode_Scalar,
					scalar = 'x',
					modifiers = {.Control},
				},
				1 = interaction.Key_Stroke{kind = .Unicode_Scalar, scalar = 'k'},
			},
			stroke_count = 2,
			command_name = "kill-buffer",
		},
		{
			strokes = {
				0 = interaction.Key_Stroke {
					kind = .Unicode_Scalar,
					scalar = 'x',
					modifiers = {.Control},
				},
				1 = interaction.Key_Stroke {
					kind = .Unicode_Scalar,
					scalar = 's',
					modifiers = {.Control},
				},
			},
			stroke_count = 2,
			command_name = "save-associated-document",
		},
		{
			strokes = {
				0 = interaction.Key_Stroke {
					kind = .Unicode_Scalar,
					scalar = 'x',
					modifiers = {.Control},
				},
				1 = interaction.Key_Stroke {
					kind = .Unicode_Scalar,
					scalar = 'c',
					modifiers = {.Control},
				},
			},
			stroke_count = 2,
			command_name = "request-editor-exit",
		},
		{
			strokes = {
				0 = interaction.Key_Stroke {
					kind = .Unicode_Scalar,
					scalar = 'g',
					modifiers = {.Control},
				},
			},
			stroke_count = 1,
			command_name = "keyboard-quit",
		},
		{
			strokes = {0 = interaction.Key_Stroke {
				kind = .Unicode_Scalar,
				scalar = 'w',
				modifiers = {.Meta},
			}},
			stroke_count = 1,
			command_name = "copy-region",
		},
		{
			strokes = {0 = interaction.Key_Stroke {
				kind = .Unicode_Scalar,
				scalar = 'w',
				modifiers = {.Control},
			}},
			stroke_count = 1,
			command_name = "kill-region",
		},
		{
			strokes = {0 = interaction.Key_Stroke {
				kind = .Unicode_Scalar,
				scalar = 'y',
				modifiers = {.Control},
			}},
			stroke_count = 1,
			command_name = "yank",
		},
		{
			strokes = {
				0 = interaction.Key_Stroke {
					kind = .Unicode_Scalar,
					scalar = 's',
					modifiers = {.Meta},
				},
				1 = interaction.Key_Stroke{kind = .Unicode_Scalar, scalar = '.'},
			},
			stroke_count = 2,
			command_name = "search-symbol-at-point",
		},
	}
	keymap_ok, keymap_failure := interaction.snapshot_compile(
		&fixture.keymap,
		&fixture.command_registry,
		interaction.Snapshot_Generation(101),
		interaction.Keymap_Definition {
			registry_generation = interaction.Registry_Generation(101),
			bindings = bindings[:],
			text_fallback_name = "insert-text",
		},
		context.allocator,
	)
	testing.expectf(t, keymap_ok, "keymap failed with %v", keymap_failure.code)
	if !keymap_ok {
		interaction.command_registry_close(&fixture.command_registry)
		editor_view.close(&fixture.registry, &fixture.handle)
		editor_view.registry_close(&fixture.registry)
		editor.buffer_close(&fixture.buffer)
		return false
	}
	context_maps_ok, context_maps_failure := interaction.context_map_stack_init(
		&fixture.context_maps,
		interaction.Context_ID(102),
		&fixture.command_registry,
		context.allocator,
	)
	testing.expectf(t, context_maps_ok, "context maps failed with %v", context_maps_failure.code)
	if !context_maps_ok {
		interaction.snapshot_close(&fixture.keymap)
		interaction.command_registry_close(&fixture.command_registry)
		editor_view.close(&fixture.registry, &fixture.handle)
		editor_view.registry_close(&fixture.registry)
		history.store_close(&fixture.history)
		editor.buffer_close(&fixture.buffer)
		document.document_close(&fixture.document)
		return false
	}
	session_handle, session_ok, session_failure := editor_session.session_init(
		&fixture.session,
		editor_session.Session_ID(101),
		editor_session.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	testing.expectf(t, session_ok, "session failed with %v", session_failure.code)
	if !session_ok {
		interaction.context_map_stack_close(&fixture.context_maps)
		interaction.snapshot_close(&fixture.keymap)
		interaction.command_registry_close(&fixture.command_registry)
		editor_view.close(&fixture.registry, &fixture.handle)
		editor_view.registry_close(&fixture.registry)
		history.store_close(&fixture.history)
		editor.buffer_close(&fixture.buffer)
		document.document_close(&fixture.document)
		return false
	}
	fixture.session_handle = session_handle
	fixture.commands = Command_Context {
		session_owner = &fixture.session,
		session_handle = fixture.session_handle,
		document_owner = &fixture.document,
		history_store = &fixture.history,
		registry = &fixture.command_registry,
		registry_generation = interaction.Registry_Generation(101),
		keymap = &fixture.keymap,
		context_maps = &fixture.context_maps,
		candidate_ui = {next_session_id = 1, next_source_generation = 1},
		persistent_allocator = context.allocator,
		temporary_allocator = context.temp_allocator,
		next_transaction_id = 1,
		next_undo_unit_id = 1,
		search = {
			next_query_id = 1,
			next_generation = 1,
			next_group = 1,
		},
		grouping_started = time.tick_now(),
		grouping_continuity = 1,
	}
	testing.expect(t, command_context_structural_state_init(&fixture.commands))
	if fixture.commands.structural_command_state == nil do return false
	return true
}

@(private)
request_fixture_exit :: proc(
	fixture: ^Interaction_Fixture,
	constraints: display.Viewport_Constraints,
) -> Interaction_Result {
	control_x := interaction.Input {
		kind = .Key,
		stroke = interaction.Key_Stroke {
			kind = .Unicode_Scalar,
			scalar = 'x',
			modifiers = {.Control},
		},
	}
	dispatch_input(
		&fixture.commands,
		&fixture.buffer,
		&fixture.registry,
		fixture.handle,
		control_x,
		constraints,
	)
	result, failure := dispatch_input(
		&fixture.commands,
		&fixture.buffer,
		&fixture.registry,
		fixture.handle,
		interaction.Input {
			kind = .Key,
			stroke = interaction.Key_Stroke {
				kind = .Unicode_Scalar,
				scalar = 'c',
				modifiers = {.Control},
			},
		},
		constraints,
	)
	assert(failure.stage == .None)
	return result
}

@(private)
interaction_fixture_close :: proc(fixture: ^Interaction_Fixture) {
	command_context_close(&fixture.commands)
	if fixture.session_handle.session_id != editor_session.Session_ID(0) {
		_ = session_shutdown_close(&fixture.session, fixture.session_handle)
		fixture.session_handle = {}
	}
	if fixture.context_maps.state != nil {
		interaction.context_map_stack_close(&fixture.context_maps)
	}
	if !fixture.keymap.closed && fixture.keymap.state != nil {
		interaction.snapshot_close(&fixture.keymap)
	}
	if !fixture.command_registry.closed && fixture.command_registry.state != nil {
		interaction.command_registry_close(&fixture.command_registry)
	}
	if fixture.handle.view_id != editor_view.View_ID(0) {
		editor_view.close(&fixture.registry, &fixture.handle)
	}
	if !fixture.registry.closed {
		editor_view.registry_close(&fixture.registry)
	}
	if history.store_is_valid(&fixture.history) {
		history.store_close(&fixture.history)
	}
	if editor.buffer_is_live(&fixture.buffer) {
		editor.buffer_close(&fixture.buffer)
	}
	if fixture.document.state != nil {
		document.document_close(&fixture.document)
	}
}

@(private)
app_clipboard_fake :: proc(text: string, token: terminal.Clipboard_Change_Token) -> App_Clipboard_Fake {
	fake: App_Clipboard_Fake
	copy(fake.read_storage[:], text)
	fake.read_bytes = len(text)
	fake.read_token = token
	return fake
}

@(private)
app_clipboard_transport :: proc(fake: ^App_Clipboard_Fake) -> terminal.Clipboard_Transport {
	return terminal.Clipboard_Transport {
		user_data = rawptr(fake),
		capabilities = {
			read = true,
			write = true,
			presentation = .Outer_Terminal_Client,
		},
		write = app_clipboard_write,
		read = app_clipboard_read,
	}
}

@(private)
app_clipboard_write :: proc "odin" (
	user_data: rawptr,
	frame: []u8,
	_: u32,
	_: u64,
	_: terminal.Clipboard_Cancellation,
) -> (u64, bool, terminal.Clipboard_Failure_Context) {
	fake := (^App_Clipboard_Fake)(user_data)
	if fake.write_failure || len(frame) > len(fake.write_storage) {
		return 0, false, terminal.Clipboard_Failure_Context{code = .Write_Failed}
	}
	copy(fake.write_storage[:], frame)
	fake.write_bytes = len(frame)
	return u64(len(frame)), true, {}
}

@(private)
app_clipboard_read :: proc "odin" (
	user_data: rawptr,
	_: u32,
	_: terminal.Clipboard_Cancellation,
) -> (terminal.Clipboard_Transport_Read, bool, terminal.Clipboard_Failure_Context) {
	fake := (^App_Clipboard_Fake)(user_data)
	if fake.read_failure {
		return {}, false, terminal.Clipboard_Failure_Context{code = .Read_Failed}
	}
	return terminal.Clipboard_Transport_Read {
		text = fake.read_storage[:fake.read_bytes],
		token = fake.read_token,
		reported_bytes = u64(fake.read_bytes),
		complete = true,
	}, true, {}
}

@(private)
expect_interaction_buffer :: proc(t: ^testing.T, buffer: ^editor.Buffer, expected: string) {
	stats, stats_ok, _ := editor.buffer_stats(buffer)
	testing.expect(t, stats_ok)
	if !stats_ok {
		return
	}
	contents, allocation_error := make([]byte, int(stats.text_bytes), context.temp_allocator)
	testing.expect(t, allocation_error == nil)
	if allocation_error != nil {
		return
	}
	defer delete(contents, context.temp_allocator)
	_, inspected, _ := editor.buffer_inspect(
		buffer,
		0,
		editor.Byte_Offset(stats.text_bytes),
		contents,
	)
	testing.expect(t, inspected)
	if inspected {
		testing.expect_value(t, string(contents), expected)
	}
}
