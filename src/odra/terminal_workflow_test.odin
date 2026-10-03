// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "core:testing"
import "core:time"
import "core:strings"
import "../editor"
import "../editor_session"
import "../interactive_session"
import "../layout"
import "../terminal_emulator"
import "../terminal_session"
import "../ui"
import "../view"

@(test)
/* Ensures one application workflow opens, displays, refreshes, and projects a terminal buffer. */
terminal_workflow_composes_buffer_pane_and_ui :: proc(t: ^testing.T) {
	fixture, ready := terminal_workflow_fixture_open(t, 9_701)
	if !ready do return
	defer terminal_workflow_fixture_close(t, &fixture)
	opened, open_ok, open_failure := terminal_workflow_open(
		&fixture.workflow,
		&fixture.session,
		fixture.handle,
		&fixture.layout,
		terminal_workflow_test_request(.Replace_Active, []string{"-c", "printf ready"}),
	)
	testing.expectf(t, open_ok, "terminal workflow open failed at %v", open_failure.stage)
	if !open_ok do return
	testing.expect(t, opened.terminal.id != 0)
	testing.expect_value(t, opened.view.lifecycle, editor_session.Terminal_Lifecycle.Running)
	layout_handle, _, _ := layout.registry_handle(&fixture.layout)
	layout_view, layout_ok, _ := layout.registry_snapshot(&fixture.layout, layout_handle)
	testing.expect(t, layout_ok)
	testing.expect_value(t, layout_view.nodes[0].entry, opened.entry)
	refreshed := false
	for _ in 0 ..< 200 {
		state, refresh_ok, _ := terminal_workflow_refresh(&fixture.workflow, &fixture.session, opened.terminal)
		if refresh_ok && state.projection_revision > opened.view.projection_revision {
			refreshed = true
			break
		}
		time.sleep(time.Millisecond)
	}
	testing.expect(t, refreshed)
	access, accessed, _ := editor_session.session_entry_access(&fixture.session, opened.entry)
	entry, borrowed, _ := editor_session.entry_access_borrow(access)
	testing.expect(t, accessed && borrowed)
	if !accessed || !borrowed do return
	stats, stats_ok, _ := editor.buffer_stats(entry.buffer)
	testing.expect(t, stats_ok && stats.text_bytes > 0)
	proposal, proposal_ok, _ := ui.proposal_begin(&fixture.ui_registry)
	_, style_ok, _ := ui.proposal_add_style(&proposal, .Text_Normal)
	ui_view, projected, project_failure := terminal_workflow_project_ui(
		&fixture.workflow, &proposal, opened.terminal, 9_701, "shell",
	)
	testing.expectf(t, proposal_ok && style_ok && projected, "terminal UI projection failed at %v", project_failure.stage)
	if proposal.state != nil do ui.proposal_abort(&proposal)
	_ = ui_view
}

@(test)
/* Ensures presentation failure removes the new buffer and child without disturbing the editor. */
terminal_workflow_contains_layout_failure :: proc(t: ^testing.T) {
	fixture, ready := terminal_workflow_fixture_open(t, 9_702)
	if !ready do return
	defer terminal_workflow_fixture_close(t, &fixture)
	closed_layout, _ := layout.registry_close(&fixture.layout)
	testing.expect(t, closed_layout)
	fixture.layout_open = false
	_, opened, failure := terminal_workflow_open(
		&fixture.workflow,
		&fixture.session,
		fixture.handle,
		&fixture.layout,
		terminal_workflow_test_request(.Replace_Active, []string{"-c", "printf ready"}),
	)
	testing.expect(t, !opened)
	testing.expect_value(t, failure.stage, Terminal_Workflow_Stage.Present)
	descriptors, copied, _ := editor_session.session_descriptors(&fixture.session, fixture.handle)
	testing.expect(t, copied)
	if copied {
		testing.expect_value(t, len(descriptors.descriptors), 1)
		editor_session.descriptor_batch_close(&descriptors)
	}
	stats, inspected, _ := terminal_session.registry_inspect(&fixture.workflow.registry)
	testing.expect(t, inspected)
	testing.expect_value(t, stats.session_count, u16(0))
}

@(test)
/* Verifies one-shot task classification remains attached to its terminal entry. */
terminal_workflow_retains_one_shot_kind :: proc(t: ^testing.T) {
	fixture, ready := terminal_workflow_fixture_open(t, 9_708)
	if !ready do return
	defer terminal_workflow_fixture_close(t, &fixture)
	request := terminal_workflow_test_request(.Hidden, []string{"-c", "printf ready"})
	request.one_shot_kind = .Compilation
	opened, open_ok, open_failure := terminal_workflow_open(
		&fixture.workflow,
		&fixture.session,
		fixture.handle,
		&fixture.layout,
		request,
	)
	testing.expectf(t, open_ok, "one-shot terminal open failed at %v", open_failure.stage)
	if !open_ok do return
	entry := terminal_workflow_entry_record(&fixture.workflow, opened.terminal)
	testing.expect(t, entry != nil)
	if entry != nil do testing.expect_value(t, entry.one_shot_kind, Terminal_One_Shot_Kind.Compilation)
}

@(test)
/* Verifies one real PTY survives mirrors, hidden output, reattachment, and process exit. */
terminal_workflow_preserves_session_across_pane_visibility :: proc(t: ^testing.T) {
	fixture, ready := terminal_workflow_fixture_open(t, 9_703)
	if !ready do return
	defer terminal_workflow_fixture_close(t, &fixture)
	opened, open_ok, open_failure := terminal_workflow_open(
		&fixture.workflow,
		&fixture.session,
		fixture.handle,
		&fixture.layout,
		terminal_workflow_test_request(
			.Other_Pane,
			[]string{
				"-c",
				"printf 'first-marker\\n'; sleep 2; " +
					"i=0; while [ \"$i\" -lt 384 ]; do " +
					"printf 'row-%03d-abcdefghijklmnopqrstuvwxyz\\n' \"$i\"; " +
					"i=$((i + 1)); done; sleep 0.1; printf 'final-marker\\n'",
			},
		),
	)
	testing.expectf(t, open_ok, "terminal workflow open failed at %v", open_failure.stage)
	if !open_ok do return

	layout_handle, _, _ := layout.registry_handle(&fixture.layout)
	initial_layout, initial_ok, _ := layout.registry_snapshot(&fixture.layout, layout_handle)
	testing.expect(t, initial_ok && initial_layout.pane_count == 2)
	if !initial_ok do return
	mirrored, mirror_ok, mirror_failure := layout.registry_replace_pane_buffer(
		&fixture.layout,
		initial_layout.active_pane,
		&fixture.session,
		opened.entry,
	)
	testing.expectf(t, mirror_ok, "terminal mirror failed with %v", mirror_failure.code)
	if !mirror_ok do return
	mirrored_layout, mirrored_ok, _ := layout.registry_snapshot(&fixture.layout, mirrored.layout)
	testing.expect(t, mirrored_ok)
	if !mirrored_ok do return
	terminal_nodes, terminal_count := terminal_workflow_test_terminal_nodes(&mirrored_layout, opened.entry)
	testing.expect_value(t, terminal_count, 2)
	if terminal_count != 2 do return
	testing.expect(t, terminal_nodes[0].view != terminal_nodes[1].view)

	access, accessed, _ := editor_session.session_entry_access(&fixture.session, opened.entry)
	entry, borrowed, _ := editor_session.entry_access_borrow(access)
	testing.expect(t, accessed && borrowed)
	if !accessed || !borrowed do return
	viewport := view.Terminal_Viewport{top_row = 12, horizontal_display_column = 3, follow_tail = false}
	viewport_set, viewport_failure := view.terminal_viewport_set(entry.view_registry, terminal_nodes[0].view, viewport)
	testing.expectf(t, viewport_set, "terminal viewport failed with %v", viewport_failure.code)
	first_state, first_state_ok, _ := view.terminal_view_state(entry.view_registry, terminal_nodes[0].view)
	second_state, second_state_ok, _ := view.terminal_view_state(entry.view_registry, terminal_nodes[1].view)
	testing.expect(t, first_state_ok && second_state_ok)
	testing.expect_value(t, first_state.viewport, viewport)
	testing.expect(t, second_state.viewport.follow_tail)

	first_geometry := view.Terminal_Geometry{columns = 40, rows = 10}
	second_geometry := view.Terminal_Geometry{columns = 72, rows = 20}
	_, first_claimed, first_claim_failure := view.terminal_geometry_claim(
		entry.view_registry, terminal_nodes[0].view, first_geometry,
	)
	second_update, second_claimed, second_claim_failure := view.terminal_geometry_claim(
		entry.view_registry, terminal_nodes[1].view, second_geometry,
	)
	testing.expectf(t, first_claimed, "initial geometry claim failed with %v", first_claim_failure.code)
	testing.expectf(t, second_claimed, "geometry transfer failed with %v", second_claim_failure.code)
	testing.expect_value(t, second_update.previous, terminal_nodes[0].view)
	resized, resize_failure := terminal_session.registry_resize(
		&fixture.workflow.registry,
		opened.terminal,
		second_geometry.columns,
		second_geometry.rows,
		9,
		18,
	)
	testing.expectf(
		t,
		resized,
		"focused terminal resize failed with %v process %v",
		resize_failure.code,
		resize_failure.process_code,
	)

	for _ in 0 ..< 2 {
		current_handle, _, _ := layout.registry_handle(&fixture.layout)
		current, current_ok, _ := layout.registry_snapshot(&fixture.layout, current_handle)
		testing.expect(t, current_ok)
		if !current_ok do return
		current_nodes, current_count := terminal_workflow_test_terminal_nodes(&current, opened.entry)
		testing.expect(t, current_count > 0)
		if current_count == 0 do return
		_, detached, detach_failure := layout.registry_replace_pane_buffer(
			&fixture.layout,
			current_nodes[0].pane,
			&fixture.session,
			fixture.initial,
		)
		testing.expectf(t, detached, "terminal detach failed with %v", detach_failure.code)
		if !detached do return
	}
	hidden_handle, _, _ := layout.registry_handle(&fixture.layout)
	hidden, hidden_ok, _ := layout.registry_snapshot(&fixture.layout, hidden_handle)
	testing.expect(t, hidden_ok)
	if !hidden_ok do return
	_, hidden_terminal_count := terminal_workflow_test_terminal_nodes(&hidden, opened.entry)
	testing.expect_value(t, hidden_terminal_count, 0)
	hidden_focus := hidden.active_pane.pane_id

	exited := false
	final_visible := false
	for _ in 0 ..< 4_000 {
		state, refreshed, _ := terminal_workflow_refresh(&fixture.workflow, &fixture.session, opened.terminal)
		if refreshed {
			exited = state.lifecycle == .Exited
			text, copied := terminal_workflow_test_entry_text(&fixture.session, opened.entry)
			if copied {
				final_visible = strings.contains(string(text), "final-marker")
				delete(text)
			}
			if exited && final_visible do break
		}
		time.sleep(time.Millisecond)
	}
	testing.expect(t, exited && final_visible)
	after_output_handle, _, _ := layout.registry_handle(&fixture.layout)
	after_output, after_output_ok, _ := layout.registry_snapshot(&fixture.layout, after_output_handle)
	testing.expect(t, after_output_ok)
	if after_output_ok do testing.expect_value(t, after_output.active_pane.pane_id, hidden_focus)

	stats, inspected, _ := terminal_session.registry_inspect(&fixture.workflow.registry)
	testing.expect(t, inspected)
	testing.expect_value(t, stats.session_count, u16(1))
	testing.expect_value(t, stats.exited_count, u16(1))
	testing.expect(t, stats.output_bytes > 12_000)
	testing.expect(t, stats.retained_bytes <= terminal_session.DEFAULT_LIMITS.state_bytes)
	testing.expect(t, stats.projection_bytes <= terminal_session.DEFAULT_LIMITS.state_bytes)

	reattached, reattached_ok, reattach_failure := layout.registry_replace_pane_buffer(
		&fixture.layout,
		after_output.active_pane,
		&fixture.session,
		opened.entry,
	)
	testing.expectf(t, reattached_ok, "terminal reattachment failed with %v", reattach_failure.code)
	if !reattached_ok do return
	reattached_layout, reattached_layout_ok, _ := layout.registry_snapshot(&fixture.layout, reattached.layout)
	testing.expect(t, reattached_layout_ok)
	if reattached_layout_ok {
		_, reattached_count := terminal_workflow_test_terminal_nodes(&reattached_layout, opened.entry)
		testing.expect_value(t, reattached_count, 1)
	}
	state, state_ok, _ := editor_session.session_terminal_buffer_state(&fixture.session, opened.entry)
	testing.expect(t, state_ok)
	testing.expect_value(t, state.lifecycle, editor_session.Terminal_Lifecycle.Exited)
	closed, close_failure := terminal_workflow_close(&fixture.workflow)
	testing.expectf(t, closed, "terminal workflow close failed at %v", close_failure.stage)
}

@(private)
Terminal_Workflow_Test_Fixture :: struct {
	session:     editor_session.Session,
	handle:      editor_session.Session_Handle,
	initial:     editor_session.Entry_Handle,
	layout:      layout.Registry,
	layout_open: bool,
	workflow:    Terminal_Workflow_State,
	ui_registry: ui.Registry,
}

@(private)
terminal_workflow_fixture_open :: proc(
	t: ^testing.T,
	id: u64,
) -> (fixture: Terminal_Workflow_Test_Fixture, ok: bool) {
	handle, session_ok, _ := editor_session.session_init(
		&fixture.session,
		editor_session.Session_ID(id),
		editor_session.Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	if !session_ok do return fixture, false
	fixture.handle = handle
	created, created_ok, _ := editor_session.session_create_buffer(
		&fixture.session,
		{session = handle, name = "notes", initial_contents = "keep", configuration = editor_session.DEFAULT_ENTRY_CONFIGURATION},
	)
	if !created_ok do return fixture, false
	fixture.initial = created.entry
	access, accessed, _ := editor_session.session_entry_access(&fixture.session, created.entry)
	entry, borrowed, _ := editor_session.entry_access_borrow(access)
	if !accessed || !borrowed do return fixture, false
	layout_ok, _ := layout.registry_init(
		&fixture.layout, layout.Owner_ID(id), layout.Layout_ID(id), entry.view_registry,
		entry.primary_view, {rows = 24, columns = 80, global_reserved_rows = 1},
		layout.DEFAULT_POLICY, context.allocator, created.entry,
	)
	if !layout_ok do return fixture, false
	fixture.layout_open = true
	workflow_ok, _ := terminal_workflow_init(&fixture.workflow)
	if !workflow_ok do return fixture, false
	ui_ok, _ := ui.registry_init(&fixture.ui_registry, ui.Registry_ID(id))
	if !ui_ok do return fixture, false
	testing.expect(t, true)
	return fixture, true
}

@(private)
terminal_workflow_fixture_close :: proc(t: ^testing.T, fixture: ^Terminal_Workflow_Test_Fixture) {
	if fixture.ui_registry.state != nil && !fixture.ui_registry.closed do ui.registry_close(&fixture.ui_registry)
	if fixture.layout_open do layout.registry_close(&fixture.layout)
	if fixture.workflow.initialized {
		closed, failure := terminal_workflow_close(&fixture.workflow)
		testing.expectf(t, closed, "terminal workflow close failed at %v", failure.stage)
	}
	shutdown := session_shutdown_close(&fixture.session, fixture.handle)
	testing.expect_value(t, shutdown.stage, App_Stage.None)
}

@(private)
terminal_workflow_test_request :: proc(
	presentation: Terminal_Presentation,
	arguments: []string,
) -> Terminal_Open_Request {
	options := terminal_emulator.DEFAULT_OPTIONS
	options.columns = 80
	options.rows = 24
	return Terminal_Open_Request {
		name = "terminal",
		working_context = "/tmp",
		presentation = presentation,
		configuration = editor_session.DEFAULT_ENTRY_CONFIGURATION,
		scope = {kind = .Instance},
		default_session = true,
		terminal = {
			process = {
				name = "terminal-workflow-test",
				owner_kind = .Interactive_User,
				owner_label = "terminal workflow test",
				working_directory = "/tmp",
				limits = interactive_session.DEFAULT_LIMITS,
				make_default = true,
			},
			start = {
				executable = "/bin/sh",
				arguments = arguments,
				working_directory = "/tmp",
				columns = 80,
				rows = 24,
			},
			emulator = options,
			limits = terminal_session.DEFAULT_LIMITS,
		},
	}
}

@(private)
terminal_workflow_test_terminal_nodes :: proc(
	snapshot: ^layout.Snapshot,
	entry: editor_session.Entry_Handle,
) -> ([2]layout.Node_Descriptor, int) {
	result: [2]layout.Node_Descriptor
	count := 0
	if snapshot == nil do return result, count
	for node in snapshot.nodes[:snapshot.node_count] {
		if node.kind != .Pane || node.entry != entry do continue
		if count < len(result) do result[count] = node
		count += 1
	}
	return result, count
}

@(private)
terminal_workflow_test_entry_text :: proc(
	session: ^editor_session.Session,
	entry_handle: editor_session.Entry_Handle,
) -> ([]u8, bool) {
	access, accessed, _ := editor_session.session_entry_access(session, entry_handle)
	entry, borrowed, _ := editor_session.entry_access_borrow(access)
	if !accessed || !borrowed do return nil, false
	stats, stats_ok, _ := editor.buffer_stats(entry.buffer)
	if !stats_ok || stats.text_bytes > u64(max(int)) do return nil, false
	snapshot: editor.Buffer_Snapshot
	opened, _ := editor.buffer_snapshot_open(entry.buffer, &snapshot)
	if !opened do return nil, false
	defer editor.buffer_snapshot_close(&snapshot)
	text, allocation_error := make([]u8, int(stats.text_bytes))
	if allocation_error != nil do return nil, false
	_, copied, _ := editor.buffer_snapshot_read(&snapshot, 0, text)
	if !copied {
		delete(text)
		return nil, false
	}
	return text, true
}
