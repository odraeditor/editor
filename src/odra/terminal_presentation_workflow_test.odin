// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "core:testing"
import "core:time"
import "../command"
import "../display"
import "../editor_session"
import "../interaction"
import "../layout"
import "../terminal_session"

@(test)
/* Verifies ordinary opens reuse one lower pane and retain every editing pane. */
terminal_default_lower_pane_preserves_editing :: proc(t: ^testing.T) {
	for editing_panes in 1 ..= 2 {
		fixture, ready := terminal_workflow_fixture_open(t, u64(9_740 + editing_panes))
		if !ready do return
		commands := terminal_presentation_test_commands(&fixture, "/bin/sh")
		if editing_panes == 2 {
			before := terminal_presentation_test_layout(t, &commands)
			_, split_ok, _ := layout.registry_split_right(&commands.layout_registry, before.active_pane)
			testing.expect(t, split_ok)
		}
		before := terminal_presentation_test_layout(t, &commands)
		return_pane := before.active_pane.pane_id
		_, failure := command_context_dispatch_terminal_presentation(&commands, .Terminal_Open, {})
		testing.expect_value(t, failure.stage, App_Stage.None)
		shown := terminal_presentation_test_layout(t, &commands)
		testing.expect_value(t, shown.pane_count, u16(editing_panes + 1))
		terminal_node, active_ok := command_context_layout_active_node(&shown)
		testing.expect(t, active_ok)
		for node in shown.nodes[:shown.node_count] {
			if node.kind == .Pane && node.pane.pane_id == return_pane {
				testing.expect_value(t, node.entry, fixture.initial)
				testing.expect(t, node.geometry.outer.row < terminal_node.geometry.outer.row)
			}
		}
		first := commands.current_entry
		_, failure = command_context_dispatch_terminal_presentation(&commands, .Terminal_Open, {})
		testing.expect_value(t, failure.stage, App_Stage.None)
		testing.expect_value(t, commands.current_entry, first)
		_, failure = command_context_dispatch_terminal_presentation(&commands, .Terminal_New, {})
		testing.expect_value(t, failure.stage, App_Stage.None)
		testing.expect(t, commands.current_entry != first)
		shown = terminal_presentation_test_layout(t, &commands)
		testing.expect_value(t, shown.pane_count, u16(editing_panes + 1))
		seen_terminal := false
		seen_editor := false
		for _ in 0 ..< int(shown.pane_count) {
			terminal_presentation_test_next_pane(t, &commands)
			seen_terminal = seen_terminal || command_context_active_terminal(&commands)
			seen_editor = seen_editor || commands.current_entry == fixture.initial
		}
		testing.expect(t, seen_terminal && seen_editor)
		_, failure = command_context_dispatch_terminal_presentation(&commands, .Terminal_Toggle, {})
		testing.expect_value(t, failure.stage, App_Stage.None)
		hidden := terminal_presentation_test_layout(t, &commands)
		testing.expect_value(t, hidden.pane_count, u16(editing_panes))
		testing.expect_value(t, hidden.active_pane.pane_id, return_pane)
		testing.expect_value(t, commands.current_entry, fixture.initial)
		stats, inspected, _ := terminal_session.registry_inspect(&fixture.workflow.registry)
		testing.expect(t, inspected)
		testing.expect_value(t, stats.running_count, u16(2))
		terminal_workflow_fixture_close(t, &fixture)
	}
}

@(test)
/* Verifies stale terminal presentation does not close an explicitly replaced editor pane. */
terminal_toggle_preserves_replaced_pane :: proc(t: ^testing.T) {
	fixture, ready := terminal_workflow_fixture_open(t, 9_743)
	if !ready do return
	defer terminal_workflow_fixture_close(t, &fixture)
	commands := terminal_presentation_test_commands(&fixture, "/bin/sh")
	_, failure := command_context_dispatch_terminal_presentation(&commands, .Terminal_Open, {})
	testing.expect_value(t, failure.stage, App_Stage.None)
	replace_failure := command_context_layout_replace_active(&commands, fixture.initial)
	testing.expect_value(t, replace_failure.stage, App_Stage.None)
	_, activated, _ := editor_session.session_activate(&fixture.session, fixture.initial)
	testing.expect(t, activated)
	commands.current_entry = fixture.initial
	_, failure = command_context_dispatch_terminal_presentation(&commands, .Terminal_Toggle, {})
	testing.expect_value(t, failure.stage, App_Stage.None)
	after := terminal_presentation_test_layout(t, &commands)
	testing.expect_value(t, after.pane_count, u16(2))
	testing.expect_value(t, commands.current_entry, fixture.initial)
}

@(private)
terminal_presentation_test_next_pane :: proc(t: ^testing.T, commands: ^Command_Context) {
	registry: interaction.Command_Registry
	registry_ok, _ := command.built_in_command_registry_init(&registry, 9_740, context.allocator)
	testing.expect(t, registry_ok)
	if !registry_ok do return
	defer interaction.command_registry_close(&registry)
	handle, found, _ := interaction.command_lookup(&registry, "focus-next-pane")
	testing.expect(t, found)
	snapshot := terminal_presentation_test_layout(t, commands)
	active, active_ok := command_context_layout_active_node(&snapshot)
	testing.expect(t, active_ok)
	access, accessed, _ := editor_session.session_entry_access(commands.session_owner, active.entry)
	entry, borrowed, _ := editor_session.entry_access_borrow(access)
	testing.expect(t, accessed && borrowed)
	if !accessed || !borrowed do return
	result, executed, failure := command.native_command_execute({
		registry = &registry,
		command = handle,
		buffer = entry.buffer,
		document = entry.document,
		view_registry = entry.view_registry,
		view = active.view,
		layout_registry = &commands.layout_registry,
		profile = display.terminal_unicode17_profile(),
		constraints = {width_cells = 80, height_rows = 24},
		temporary_allocator = context.temp_allocator,
		persistent_allocator = context.allocator,
	})
	testing.expectf(t, executed, "pane focus failed with %v", failure.code)
	command.native_result_close(&result)
	sync_failure := command_context_layout_sync_active_entry(commands)
	testing.expect_value(t, sync_failure.stage, App_Stage.None)
	commands.current_entry = commands.layout_entry
}

@(test)
/* Verifies an explicit other-pane request retains its independent display policy. */
terminal_other_pane_keeps_explicit_placement :: proc(t: ^testing.T) {
	fixture, ready := terminal_workflow_fixture_open(t, 9_744)
	if !ready do return
	defer terminal_workflow_fixture_close(t, &fixture)
	commands := terminal_presentation_test_commands(&fixture, "/bin/sh")
	_, failure := command_context_dispatch_terminal_presentation(&commands, .Terminal_Open_Other_Pane, {})
	testing.expect_value(t, failure.stage, App_Stage.None)
	snapshot := terminal_presentation_test_layout(t, &commands)
	testing.expect_value(t, snapshot.pane_count, u16(2))
	testing.expect(t, !fixture.workflow.toggle.visible)
}

@(test)
/* Verifies shell exit closes the lower pane and returns to the retained editor. */
terminal_lower_pane_exit_returns_to_editor :: proc(t: ^testing.T) {
	fixture, ready := terminal_workflow_fixture_open(t, 9_745)
	if !ready do return
	defer terminal_workflow_fixture_close(t, &fixture)
	commands := terminal_presentation_test_commands(&fixture, "/bin/true")
	_, failure := command_context_dispatch_terminal_presentation(&commands, .Terminal_Open, {})
	testing.expect_value(t, failure.stage, App_Stage.None)
	state, active := command_context_active_terminal_state(&commands)
	testing.expect(t, active)
	if !active do return
	exited := false
	for _ in 0 ..< 2_000 {
		terminal_state, refreshed, _ := terminal_workflow_refresh(
			&fixture.workflow, &fixture.session, terminal_session_ref(state.terminal),
		)
		if refreshed && terminal_state.lifecycle == .Exited {
			exited = true
			break
		}
		time.sleep(time.Millisecond)
	}
	testing.expect(t, exited)
	if !exited do return
	_, failure = command_context_reconcile_terminal_exits(&commands)
	testing.expect_value(t, failure.stage, App_Stage.None)
	snapshot := terminal_presentation_test_layout(t, &commands)
	testing.expect_value(t, snapshot.pane_count, u16(1))
	testing.expect_value(t, commands.current_entry, fixture.initial)
	testing.expect(t, !fixture.workflow.toggle.visible)
	_, failure = command_context_dispatch_terminal_presentation(&commands, .Terminal_Open, {})
	testing.expect_value(t, failure.stage, App_Stage.None)
	snapshot = terminal_presentation_test_layout(t, &commands)
	testing.expect_value(t, snapshot.pane_count, u16(2))
}

@(test)
/* Verifies scoped default reuse and stable independent terminal names. */
terminal_presentation_reuses_scoped_default :: proc(t: ^testing.T) {
	fixture, ready := terminal_workflow_fixture_open(t, 9_731)
	if !ready do return
	defer terminal_workflow_fixture_close(t, &fixture)
	commands := terminal_presentation_test_commands(&fixture, "/bin/sh")

	_, open_failure := command_context_dispatch_terminal_presentation(
		&commands,
		.Terminal_Open,
		{},
	)
	testing.expect_value(t, open_failure.stage, App_Stage.None)
	first, first_ok := terminal_workflow_default(
		&fixture.workflow,
		{kind = .Instance},
	)
	testing.expect(t, first_ok)
	_, resized, resize_failure := terminal_workflow_resize(&fixture.workflow, first.terminal, 100, 20)
	testing.expectf(
		t,
		resized,
		"live terminal resize failed with %v/%v",
		resize_failure.terminal.stage,
		resize_failure.terminal.code,
	)
	terminal_presentation_test_activate_initial(t, &commands, &fixture)
	_, reopen_failure := command_context_dispatch_terminal_presentation(
		&commands,
		.Terminal_Open,
		{},
	)
	testing.expect_value(t, reopen_failure.stage, App_Stage.None)
	stats, inspected, _ := terminal_session.registry_inspect(&fixture.workflow.registry)
	testing.expect(t, inspected)
	testing.expect_value(t, stats.session_count, u16(1))
	testing.expect_value(t, commands.current_entry, first.entry)

	_, new_failure := command_context_dispatch_terminal_presentation(
		&commands,
		.Terminal_New,
		{},
	)
	testing.expect_value(t, new_failure.stage, App_Stage.None)
	stats, inspected, _ = terminal_session.registry_inspect(&fixture.workflow.registry)
	testing.expect(t, inspected)
	testing.expect_value(t, stats.session_count, u16(2))
	testing.expect(t, terminal_presentation_test_has_label(&fixture.session, fixture.handle, "terminal"))
	testing.expect(t, terminal_presentation_test_has_label(&fixture.session, fixture.handle, "terminal-2"))
}

@(test)
/* Verifies toggle restores layout and leaves the terminal process running. */
terminal_toggle_restores_layout_and_process :: proc(t: ^testing.T) {
	fixture, ready := terminal_workflow_fixture_open(t, 9_732)
	if !ready do return
	defer terminal_workflow_fixture_close(t, &fixture)
	commands := terminal_presentation_test_commands(&fixture, "/bin/sh")
	_, show_failure := command_context_dispatch_terminal_presentation(&commands, .Terminal_Toggle, {})
	testing.expect_value(t, show_failure.stage, App_Stage.None)
	shown := terminal_presentation_test_layout(t, &commands)
	testing.expect_value(t, shown.pane_count, u16(2))
	testing.expect(t, fixture.workflow.toggle.visible)
	remembered_height := fixture.workflow.toggle.height
	_, resized, resize_failure := layout.registry_resize_pane(
		&commands.layout_registry, shown.active_pane, .Above_Below, 1,
	)
	testing.expectf(t, resized, "terminal pane resize failed with %v", resize_failure.code)
	resized_layout := terminal_presentation_test_layout(t, &commands)
	resized_node, resized_active := command_context_layout_active_node(&resized_layout)
	testing.expect(t, resized_active)
	remembered_height = resized_node.geometry.outer.height

	_, hide_failure := command_context_dispatch_terminal_presentation(&commands, .Terminal_Toggle, {})
	testing.expect_value(t, hide_failure.stage, App_Stage.None)
	hidden := terminal_presentation_test_layout(t, &commands)
	testing.expect_value(t, hidden.pane_count, u16(1))
	testing.expect_value(t, commands.current_entry, fixture.initial)
	testing.expect(t, !fixture.workflow.toggle.visible)
	stats, inspected, _ := terminal_session.registry_inspect(&fixture.workflow.registry)
	testing.expect(t, inspected)
	testing.expect_value(t, stats.running_count, u16(1))

	_, restore_failure := command_context_dispatch_terminal_presentation(&commands, .Terminal_Toggle, {})
	testing.expect_value(t, restore_failure.stage, App_Stage.None)
	restored := terminal_presentation_test_layout(t, &commands)
	active, active_ok := command_context_layout_active_node(&restored)
	testing.expect(t, active_ok)
	if active_ok do testing.expect_value(t, active.geometry.outer.height, remembered_height)
}

@(test)
/* Verifies an exited default is retained while a fresh default is created. */
terminal_open_replaces_exited_default :: proc(t: ^testing.T) {
	fixture, ready := terminal_workflow_fixture_open(t, 9_733)
	if !ready do return
	defer terminal_workflow_fixture_close(t, &fixture)
	commands := terminal_presentation_test_commands(&fixture, "/bin/true")
	_, open_failure := command_context_dispatch_terminal_presentation(&commands, .Terminal_Open, {})
	testing.expect_value(t, open_failure.stage, App_Stage.None)
	first_state, active := command_context_active_terminal_state(&commands)
	testing.expect(t, active)
	if !active do return
	first_ref := terminal_session_ref(first_state.terminal)
	exited := false
	for _ in 0 ..< 2_000 {
		state, refreshed, _ := terminal_workflow_refresh(&fixture.workflow, &fixture.session, first_ref)
		if refreshed && state.lifecycle == .Exited {
			exited = true
			break
		}
		time.sleep(time.Millisecond)
	}
	testing.expect(t, exited)
	terminal_presentation_test_activate_initial(t, &commands, &fixture)
	_, reopen_failure := command_context_dispatch_terminal_presentation(&commands, .Terminal_Open, {})
	testing.expect_value(t, reopen_failure.stage, App_Stage.None)
	second_state, second_active := command_context_active_terminal_state(&commands)
	testing.expect(t, second_active)
	if second_active do testing.expect(t, terminal_session_ref(second_state.terminal) != first_ref)
	stats, inspected, _ := terminal_session.registry_inspect(&fixture.workflow.registry)
	testing.expect(t, inspected)
	testing.expect_value(t, stats.session_count, u16(2))
	testing.expect_value(t, stats.exited_count, u16(1))
	testing.expect(t, terminal_presentation_test_has_label(&fixture.session, fixture.handle, "terminal"))
	testing.expect(t, terminal_presentation_test_has_label(&fixture.session, fixture.handle, "terminal-2"))
}

@(test)
/* Verifies a completed interactive terminal closes and creates a scratch fallback. */
terminal_exit_returns_to_scratch :: proc(t: ^testing.T) {
	fixture, ready := terminal_workflow_fixture_open(t, 9_734)
	if !ready do return
	defer terminal_workflow_fixture_close(t, &fixture)
	commands := terminal_presentation_test_commands(&fixture, "/bin/true")
	_, open_failure := command_context_dispatch_terminal_presentation(&commands, .Terminal_Open, {})
	testing.expect_value(t, open_failure.stage, App_Stage.None)
	state, active := command_context_active_terminal_state(&commands)
	testing.expect(t, active)
	if !active do return

	initial_kill, initial_killed, initial_failure := command_context_kill_buffer(
		&commands,
		"notes",
		.Discard_Modified,
	)
	testing.expectf(t, initial_killed, "initial buffer close failed with %v", initial_failure.code)
	testing.expect_value(t, initial_kill.completion, command.Buffer_Kill_Completion.Closed)
	if !initial_killed do return

	exited := false
	for _ in 0 ..< 2_000 {
		terminal_state, refreshed, _ := terminal_workflow_refresh(
			&fixture.workflow,
			&fixture.session,
			terminal_session_ref(state.terminal),
		)
		if refreshed && terminal_state.lifecycle == .Exited {
			exited = true
			break
		}
		time.sleep(time.Millisecond)
	}
	testing.expect(t, exited)
	if !exited do return

	changed, reconcile_failure := command_context_reconcile_terminal_exits(&commands)
	testing.expect_value(t, reconcile_failure.stage, App_Stage.None)
	testing.expect(t, changed)
	testing.expect(t, !terminal_presentation_test_has_label(&fixture.session, fixture.handle, "terminal"))
	scratch, scratch_found, _ := editor_session.session_find_label(
		&fixture.session,
		fixture.handle,
		"*scratch*",
	)
	testing.expect(t, scratch_found)
	visible, visible_ok, _ := editor_session.session_visible_target(&fixture.session, fixture.handle)
	testing.expect(t, visible_ok)
	if visible_ok && scratch_found do testing.expect_value(t, visible.entry, scratch)
	stats, inspected, _ := terminal_session.registry_inspect(&fixture.workflow.registry)
	testing.expect(t, inspected)
	if inspected do testing.expect_value(t, stats.session_count, u16(0))
}

@(private)
terminal_presentation_test_commands :: proc(
	fixture: ^Terminal_Workflow_Test_Fixture,
	shell: string,
) -> Command_Context {
	return Command_Context {
		session_owner = &fixture.session,
		session_handle = fixture.handle,
		entry_configuration = editor_session.DEFAULT_ENTRY_CONFIGURATION,
		persistent_allocator = context.allocator,
		temporary_allocator = context.temp_allocator,
		home_directory = "/tmp",
		current_entry = fixture.initial,
		layout_registry = fixture.layout,
		layout_entry = fixture.initial,
		terminal_workflow = &fixture.workflow,
		terminal_global_shell = shell,
	}
}

@(private)
terminal_presentation_test_activate_initial :: proc(
	t: ^testing.T,
	commands: ^Command_Context,
	fixture: ^Terminal_Workflow_Test_Fixture,
) {
	snapshot := terminal_presentation_test_layout(t, commands)
	for node in snapshot.nodes[:snapshot.node_count] {
		if node.kind != .Pane || node.entry != fixture.initial do continue
		_, focused, focus_failure := layout.registry_focus(&commands.layout_registry, node.pane)
		testing.expectf(t, focused, "initial editing pane focus failed with %v", focus_failure.code)
		break
	}
	_, activated, _ := editor_session.session_activate(&fixture.session, fixture.initial)
	testing.expect(t, activated)
	commands.current_entry = fixture.initial
	commands.layout_entry = fixture.initial
}

@(private)
terminal_presentation_test_layout :: proc(
	t: ^testing.T,
	commands: ^Command_Context,
) -> layout.Snapshot {
	handle, handle_ok, _ := layout.registry_handle(&commands.layout_registry)
	testing.expect(t, handle_ok)
	snapshot, snapshot_ok, _ := layout.registry_snapshot(&commands.layout_registry, handle)
	testing.expect(t, snapshot_ok)
	return snapshot
}

@(private)
terminal_presentation_test_has_label :: proc(
	session: ^editor_session.Session,
	handle: editor_session.Session_Handle,
	name: string,
) -> bool {
	descriptors, copied, _ := editor_session.session_descriptors(session, handle)
	if !copied do return false
	defer editor_session.descriptor_batch_close(&descriptors)
	for descriptor in descriptors.descriptors {
		if descriptor.selection_label == name do return true
	}
	return false
}
