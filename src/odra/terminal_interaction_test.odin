// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "core:testing"
import "core:strings"
import "core:time"
import "../command"
import "../display"
import "../editor"
import "../editor_session"
import "../interaction"
import "../kill_ring"
import "../terminal"
import "../terminal_emulator"
import "../terminal_session"
import "../ui"

terminal_modal_test_selectors := [2][1]interaction.Profile_State_Selector {
	{{profile_id = 2, state_id = 1}},
	{{profile_id = 2, state_id = 2}},
}

@(test)
/* Verifies the complete live map, protected recovery, prefixes, and inactive isolation. */
terminal_context_map_is_exact_and_contextual :: proc(t: ^testing.T) {
	keys: Terminal_Interaction_Test_Keys
	commands: Command_Context
	ready := terminal_interaction_test_keys_open(t, &keys, &commands)
	if !ready do return
	defer terminal_interaction_test_keys_close(&keys)
	map_failure := command_context_sync_terminal_map(&commands)
	testing.expect_value(t, map_failure.stage, App_Stage.None)
	if map_failure.stage != .None do return
	inspection, inspected, inspect_failure := interaction.context_map_inspect(
		&keys.maps,
		TERMINAL_CONTEXT_MAP_ID,
		true,
	)
	testing.expectf(t, inspected, "terminal map inspection failed with %v", inspect_failure.code)
	if inspected {
		defer interaction.inspection_result_close(&inspection)
		testing.expect_value(t, len(inspection.records), TERMINAL_CONTEXT_BINDING_COUNT)
		expected := [TERMINAL_CONTEXT_BINDING_COUNT]string {
			"terminal-send-return",
			"terminal-send-tab",
			"terminal-send-backspace",
			"terminal-send-delete",
			"terminal-send-left",
			"terminal-send-right",
			"terminal-send-up",
			"terminal-send-down",
			"terminal-send-prior",
			"terminal-send-next",
			"terminal-yank",
			"terminal-yank-pop",
			"terminal-clear",
			"terminal-send-next-key",
			"terminal-copy-mode",
			"terminal-next-prompt",
			"terminal-previous-prompt",
			"terminal-clear-scrollback",
			"terminal-open-project",
			"terminal-open-here",
		}
		for name in expected {
			found := false
			for record in inspection.records do found = found || record.command_name == name
			testing.expectf(t, found, "terminal binding %s is absent", name)
		}
		for record in inspection.records {
			testing.expect_value(t, record.map_name, "terminal-live")
			testing.expect_value(t, record.precedence, interaction.Precedence_Class.Component_Tool)
		}
	}

	control_g := terminal_interaction_test_scalar_input('g', {.Control})
	protected, protected_failure := terminal_interaction_test_resolve(&commands, control_g)
	testing.expect_value(t, protected_failure.code, interaction.Failure_Code.None)
	terminal_interaction_test_expect_command(t, &keys.registry, protected, "keyboard-quit")

	control_c := terminal_interaction_test_scalar_input('c', {.Control})
	prefix, prefix_failure := terminal_interaction_test_resolve(&commands, control_c)
	testing.expect_value(t, prefix_failure.code, interaction.Failure_Code.None)
	testing.expect_value(t, prefix.kind, interaction.Resolution_Kind.Pending)
	testing.expect_value(t, commands.context_pending.stroke_count, u8(1))
	clear, clear_failure := terminal_interaction_test_resolve(
		&commands,
		terminal_interaction_test_scalar_input('l', {.Control}),
	)
	testing.expect_value(t, clear_failure.code, interaction.Failure_Code.None)
	terminal_interaction_test_expect_command(t, &keys.registry, clear, "terminal-clear-scrollback")

	control_x := terminal_interaction_test_scalar_input('x', {.Control})
	editor_prefix, editor_prefix_failure := terminal_interaction_test_resolve(&commands, control_x)
	testing.expect_value(t, editor_prefix_failure.code, interaction.Failure_Code.None)
	testing.expect_value(t, editor_prefix.kind, interaction.Resolution_Kind.Pending)
	testing.expect_value(t, commands.pending.stroke_count, u8(1))
	list, list_failure := terminal_interaction_test_resolve(
		&commands,
		terminal_interaction_test_scalar_input('b', {}),
	)
	testing.expect_value(t, list_failure.code, interaction.Failure_Code.None)
	terminal_interaction_test_expect_command(t, &keys.registry, list, "list-buffers")

	command_context_deactivate_terminal_map(&commands)
	stats, stats_ok := interaction.context_map_stats(&keys.maps)
	testing.expect(t, stats_ok)
	testing.expect_value(t, stats.active_maps, u8(0))
	outside, outside_failure := terminal_interaction_test_resolve(
		&commands,
		{kind = .Key, stroke = {kind = .Enter}},
	)
	testing.expect_value(t, outside_failure.code, interaction.Failure_Code.None)
	terminal_interaction_test_expect_command(t, &keys.registry, outside, "insert-line-break")
}

@(test)
/* Verifies modal terminal maps add only the specified live and retained-text grammar. */
modal_terminal_context_maps_are_profile_specific :: proc(t: ^testing.T) {
	keys: Terminal_Interaction_Test_Keys
	commands: Command_Context
	ready := terminal_interaction_test_keys_open(t, &keys, &commands)
	if !ready do return
	defer terminal_interaction_test_keys_close(&keys)
	activation: interaction.Profile_Activation
	if !terminal_interaction_test_activate_modal(t, &commands, &keys.registry, &activation) do return
	defer interaction.profile_activation_close(&activation)

	map_failure := command_context_sync_terminal_map(&commands)
	testing.expect_value(t, map_failure.stage, App_Stage.None)
	testing.expect_value(
		t,
		commands.interaction_workflow.map_handle.identity.id,
		MODAL_TERMINAL_CONTEXT_MAP_ID,
	)
	inspection, inspected, inspect_failure := interaction.context_map_inspect(
		&keys.maps,
		MODAL_TERMINAL_CONTEXT_MAP_ID,
		true,
	)
	testing.expectf(t, inspected, "modal terminal map inspection failed with %v", inspect_failure.code)
	if inspected {
		defer interaction.inspection_result_close(&inspection)
		testing.expect_value(t, len(inspection.records), MODAL_TERMINAL_CONTEXT_BINDING_COUNT)
		for record in inspection.records {
			testing.expect_value(t, record.map_name, "terminal-live-modal")
			testing.expect_value(t, record.precedence, interaction.Precedence_Class.Component_Tool)
		}
	}

	prefix, prefix_failure := terminal_interaction_test_resolve(
		&commands,
		terminal_interaction_test_scalar_input('\\', {.Control}),
	)
	testing.expect_value(t, prefix_failure.code, interaction.Failure_Code.None)
	testing.expect_value(t, prefix.kind, interaction.Resolution_Kind.Pending)
	copy_mode, copy_failure := terminal_interaction_test_resolve(
		&commands,
		terminal_interaction_test_scalar_input('n', {.Control}),
	)
	testing.expect_value(t, copy_failure.code, interaction.Failure_Code.None)
	terminal_interaction_test_expect_command(t, &keys.registry, copy_mode, "terminal-copy-mode")

	command_context_deactivate_terminal_map(&commands)
	copy_bindings := modal_terminal_copy_context_bindings()
	copy_map_failure := command_context_sync_context_map(
		&commands,
		MODAL_TERMINAL_COPY_CONTEXT_MAP_ID,
		MODAL_TERMINAL_COPY_CONTEXT_OWNER_ID,
		"terminal-copy-mode-modal",
		.Fallthrough,
		"",
		copy_bindings[:],
		.Component_Tool,
	)
	testing.expect_value(t, copy_map_failure.stage, App_Stage.None)
	test_cases := [?]struct {
		name:         string,
		input:        rune,
		command_name: string,
	} {
		{"left", 'h', "cursor-previous-grapheme"},
		{"down", 'j', "cursor-next-line"},
		{"up", 'k', "cursor-previous-line"},
		{"right", 'l', "cursor-next-grapheme"},
		{"line start", '0', "terminal-beginning-of-line"},
		{"line end", '$', "terminal-end-of-line"},
		{"Insert return", 'i', "modal-enter-insert"},
	}
	for test_case in test_cases {
		resolution, resolution_failure := terminal_interaction_test_resolve(
			&commands,
			terminal_interaction_test_scalar_input(test_case.input, {}),
		)
		testing.expectf(
			t,
			resolution_failure.code == .None,
			"modal terminal %s failed with %v",
			test_case.name,
			resolution_failure.code,
		)
		terminal_interaction_test_expect_command(t, &keys.registry, resolution, test_case.command_name)
	}
	command_context_deactivate_terminal_map(&commands)
}

@(test)
/* Verifies protected cancel stays local while application-mode arrows reach the PTY. */
terminal_interaction_routes_full_screen_input :: proc(t: ^testing.T) {
	fixture, ready := terminal_workflow_fixture_open(t, 9_721)
	testing.expect(t, ready)
	if !ready do return
	defer terminal_workflow_fixture_close(t, &fixture)
	opened, opened_ok, open_failure := terminal_workflow_open(
		&fixture.workflow,
		&fixture.session,
		fixture.handle,
		&fixture.layout,
		terminal_workflow_test_request(
			.Replace_Active,
			[]string{"-c", "sleep 2"},
		),
	)
	testing.expectf(t, opened_ok, "terminal workflow open failed at %v", open_failure.stage)
	if !opened_ok do return
	record, recorded, record_failure := terminal_session.registry_record(&fixture.workflow.registry, opened.terminal)
	testing.expectf(t, recorded, "terminal record failed with %v", record_failure.code)
	if !recorded do return
	testing.expect_value(
		t,
		terminal_emulator.write(record.emulator, transmute([]u8)(string("\x1b[?1h"))),
		terminal_emulator.Result.OK,
	)
	keys: Terminal_Interaction_Test_Keys
	commands := Command_Context {
		session_owner = &fixture.session,
		session_handle = fixture.handle,
		current_entry = opened.entry,
		terminal_workflow = &fixture.workflow,
		persistent_allocator = context.allocator,
		temporary_allocator = context.temp_allocator,
		next_transaction_id = 1,
		next_undo_unit_id = 1,
		grouping_started = time.tick_now(),
		grouping_continuity = 1,
	}
	keys_ready := terminal_interaction_test_keys_open(t, &keys, &commands)
	if !keys_ready do return
	defer terminal_interaction_test_keys_close(&keys)
	access, accessed, _ := editor_session.session_entry_access(&fixture.session, opened.entry)
	entry, borrowed, _ := editor_session.entry_access_borrow(access)
	testing.expect(t, accessed && borrowed)
	if !accessed || !borrowed do return
	command_context_bind_entry(&commands, opened.entry, entry)
	constraints := display.Viewport_Constraints{width_cells = 80, height_rows = 24}
	_, cancel_failure := dispatch_input(
		&commands,
		entry.buffer,
		entry.view_registry,
		entry.primary_view,
		terminal_interaction_test_scalar_input('g', {.Control}),
		constraints,
	)
	testing.expect_value(t, cancel_failure.stage, App_Stage.None)
	after_cancel, cancel_recorded, _ := terminal_session.registry_record(
		&fixture.workflow.registry,
		opened.terminal,
	)
	testing.expect(t, cancel_recorded)
	if cancel_recorded do testing.expect_value(t, after_cancel.process.resources.queued_input_bytes, u64(0))
	_, up_failure := dispatch_input(
		&commands,
		entry.buffer,
		entry.view_registry,
		entry.primary_view,
		{kind = .Key, stroke = {kind = .Up}},
		constraints,
	)
	testing.expect_value(t, up_failure.stage, App_Stage.None)
	after_up, up_recorded, _ := terminal_session.registry_record(
		&fixture.workflow.registry,
		opened.terminal,
	)
	testing.expect(t, up_recorded)
	if up_recorded do testing.expect_value(t, after_up.process.resources.queued_input_bytes, u64(3))
	testing.expect_value(
		t,
		terminal_emulator.write(
			record.emulator,
			transmute([]u8)(string("\r\x1b]8;;https://example.com\x07link\x1b]8;;\x07\r")),
		),
		terminal_emulator.Result.OK,
	)
	open_link, link_found, _ := interaction.command_lookup(&keys.registry, "terminal-open-link")
	testing.expect(t, link_found)
	if link_found {
		_, link_failure := dispatch_input(
			&commands,
			entry.buffer,
			entry.view_registry,
			entry.primary_view,
			{},
			constraints,
			open_link,
		)
		testing.expect_value(t, link_failure.stage, App_Stage.None)
		linked_record, link_recorded, _ := terminal_session.registry_record(
			&fixture.workflow.registry,
			opened.terminal,
		)
		testing.expect(t, link_recorded)
		if link_recorded {
			testing.expect_value(
				t,
				linked_record.process.resources.queued_input_bytes,
				u64(3),
			)
		}
		testing.expect_value(
			t,
			string(commands.diagnostic[:commands.diagnostic_length]),
			"External opening is unavailable: no provider is configured",
		)
	}
	terminal_interaction_test_commands_close(&commands)
}

@(test)
/* Verifies copy mode owns input, retains PTY text, and survives clipboard failure. */
terminal_copy_mode_accepts_real_pty_output :: proc(t: ^testing.T) {
	fixture, ready := terminal_workflow_fixture_open(t, 9_724)
	testing.expect(t, ready)
	if !ready do return
	defer terminal_workflow_fixture_close(t, &fixture)
	opened, opened_ok, open_failure := terminal_workflow_open(
		&fixture.workflow,
		&fixture.session,
		fixture.handle,
		&fixture.layout,
		terminal_workflow_test_request(
			.Replace_Active,
			[]string{
				"-c",
				"printf '\\033]133;A\\007\\033]133;B\\007\\033]133;C\\007alpha-beta\\n'; " +
					"sleep 0.05; " +
					"i=0; while [ \"$i\" -lt 96 ]; do printf 'row-%03d\\n' \"$i\"; i=$((i + 1)); done; " +
					"printf '\\033]133;D;7\\007\\033]133;A\\007'; sleep 2",
			},
		),
	)
	testing.expectf(t, opened_ok, "terminal open failed at %v", open_failure.stage)
	if !opened_ok do return
	resized, resize_failure := terminal_session.registry_resize(
		&fixture.workflow.registry, opened.terminal, 12, 4, 8, 16,
	)
	testing.expectf(t, resized, "terminal resize failed with %v", resize_failure.code)
	if !resized do return
	for _ in 0 ..< 2_000 {
		_, _, _ = terminal_workflow_refresh(&fixture.workflow, &fixture.session, opened.terminal)
		stats, inspected, _ := terminal_session.registry_inspect(&fixture.workflow.registry)
		semantic, semantic_ok, _ := terminal_session.registry_semantic_stats(
			&fixture.workflow.registry, opened.terminal,
		)
		if inspected && stats.output_bytes > 700 && semantic_ok && semantic.result_records > 0 do break
		time.sleep(time.Millisecond)
	}

	ring: kill_ring.Ring
	ring_ok, _ := kill_ring.ring_init(
		&ring,
		kill_ring.Ring_ID(9_724),
		kill_ring.Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, ring_ok)
	if !ring_ok do return
	defer kill_ring.ring_close(&ring)
	fake := app_clipboard_fake("", terminal.Clipboard_Change_Token(1))
	fake.write_failure = true
	adapter: terminal.Clipboard_Adapter
	adapter_ok, _ := terminal.clipboard_adapter_init(
		&adapter,
		terminal.clipboard_default_config(),
		app_clipboard_transport(&fake),
	)
	testing.expect(t, adapter_ok)
	if !adapter_ok do return
	defer terminal.clipboard_adapter_close(&adapter)

	keys: Terminal_Interaction_Test_Keys
	commands := Command_Context {
		session_owner = &fixture.session,
		session_handle = fixture.handle,
		current_entry = opened.entry,
		terminal_workflow = &fixture.workflow,
		kill_ring = &ring,
		persistent_allocator = context.allocator,
		temporary_allocator = context.temp_allocator,
		next_transaction_id = 1,
		next_undo_unit_id = 1,
		grouping_started = time.tick_now(),
		grouping_continuity = 1,
	}
	commands.clipboard_workflow.adapter = &adapter
	if !terminal_interaction_test_keys_open(t, &keys, &commands) do return
	defer terminal_interaction_test_keys_close(&keys)
	access, accessed, _ := editor_session.session_entry_access(&fixture.session, opened.entry)
	entry, borrowed, _ := editor_session.entry_access_borrow(access)
	testing.expect(t, accessed && borrowed)
	if !accessed || !borrowed do return
	command_context_bind_entry(&commands, opened.entry, entry)
	constraints := display.Viewport_Constraints{width_cells = 12, height_rows = 4}
	semantic, semantic_ok, semantic_failure := terminal_session.registry_semantic_stats(
		&fixture.workflow.registry, opened.terminal,
	)
	testing.expectf(t, semantic_ok, "terminal semantic stats failed with %v", semantic_failure.code)
	if semantic_ok {
		testing.expect(t, semantic.prompt_records > 0)
		testing.expect(t, semantic.result_records > 0)
	}
	results: [1]terminal_session.Command_Result_Record
	result_count, result_required, results_ok, results_failure :=
		terminal_session.registry_copy_command_results(
			&fixture.workflow.registry, opened.terminal, results[:],
		)
	testing.expectf(t, results_ok, "terminal result copy failed with %v", results_failure.code)
	testing.expect(t, result_required > 0 && result_count > 0)
	copy_mode, copy_found, _ := interaction.command_lookup(&keys.registry, "terminal-copy-mode")
	testing.expect(t, copy_found)
	if !copy_found do return
	_, copy_failure := dispatch_input(
		&commands, entry.buffer, entry.view_registry, entry.primary_view, {}, constraints, copy_mode,
	)
	testing.expect_value(t, copy_failure.stage, App_Stage.None)
	workflow_entry := terminal_workflow_entry_record(&fixture.workflow, opened.terminal)
	testing.expect(t, workflow_entry != nil && workflow_entry.copy_mode.active)
	if workflow_entry == nil || !workflow_entry.copy_mode.active do return
	search_scratch: [4 * 1_024]u8
	search, searched, search_failure := terminal_session.registry_copy_mode_search(
		&fixture.workflow.registry,
		opened.terminal,
		workflow_entry.copy_mode,
		"alpha",
		.Forward,
		search_scratch[:],
	)
	testing.expectf(t, searched && search.found, "terminal copy search failed with %v", search_failure.code)
	if !searched || !search.found do return
	workflow_entry.copy_mode = search.state
	before, recorded, _ := terminal_session.registry_record(&fixture.workflow.registry, opened.terminal)
	testing.expect(t, recorded)
	buffer_before, buffer_before_ok, _ := editor.buffer_stats(entry.buffer)
	testing.expect(t, buffer_before_ok)
	_, inert_failure := dispatch_input(
		&commands,
		entry.buffer,
		entry.view_registry,
		entry.primary_view,
		terminal_interaction_test_scalar_input('z', {}),
		constraints,
	)
	testing.expect_value(t, inert_failure.stage, App_Stage.None)
	_, text_failure := dispatch_input(
		&commands,
		entry.buffer,
		entry.view_registry,
		entry.primary_view,
		{kind = .Text_Commit, text = "blocked"},
		constraints,
	)
	testing.expect_value(t, text_failure.stage, App_Stage.None)

	_, home_failure := dispatch_input(
		&commands,
		entry.buffer,
		entry.view_registry,
		entry.primary_view,
		{kind = .Key, stroke = {kind = .Home}},
		constraints,
	)
	testing.expect_value(t, home_failure.stage, App_Stage.None)
	_, mark_failure := dispatch_input(
		&commands,
		entry.buffer,
		entry.view_registry,
		entry.primary_view,
		terminal_interaction_test_scalar_input(' ', {.Control}),
		constraints,
	)
	testing.expect_value(t, mark_failure.stage, App_Stage.None)
	testing.expect(t, workflow_entry.copy_mode.selection_active)
	for _ in 0 ..< 4 {
		_, move_failure := dispatch_input(
			&commands,
			entry.buffer,
			entry.view_registry,
			entry.primary_view,
			{kind = .Key, stroke = {kind = .Right}},
			constraints,
		)
		testing.expect_value(t, move_failure.stage, App_Stage.None)
	}
	proposal, proposal_ok, _ := ui.proposal_begin(&fixture.ui_registry)
	_, style_ok, _ := ui.proposal_add_style(&proposal, .Text_Normal)
	_, projected, projection_failure := terminal_workflow_project_ui(
		&fixture.workflow, &proposal, opened.terminal, 9_724, "copy-mode",
	)
	testing.expectf(
		t,
		proposal_ok && style_ok && projected,
		"copy-mode UI projection failed at %v",
		projection_failure.stage,
	)
	if proposal.state != nil do ui.proposal_abort(&proposal)
	_, retain_failure := dispatch_input(
		&commands,
		entry.buffer,
		entry.view_registry,
		entry.primary_view,
		terminal_interaction_test_scalar_input('w', {.Meta}),
		constraints,
	)
	testing.expect_value(t, retain_failure.stage, App_Stage.None)
	ring_stats, ring_inspected, _ := kill_ring.ring_stats(&ring)
	testing.expect(t, ring_inspected)
	if ring_inspected {
		testing.expectf(
			t,
			ring_stats.usage.retained_entries == 1,
			"terminal copy retained %d entries; diagnostic=%s selection=%v mark=%d:%d point=%d:%d",
			ring_stats.usage.retained_entries,
			string(commands.diagnostic[:commands.diagnostic_length]),
			workflow_entry.copy_mode.selection_active,
			workflow_entry.copy_mode.mark_row,
			workflow_entry.copy_mode.mark_column,
			workflow_entry.copy_mode.point_row,
			workflow_entry.copy_mode.point_column,
		)
	}
	testing.expect(t, commands.diagnostic_length > 0)
	after_copy, after_copy_recorded, _ := terminal_session.registry_record(
		&fixture.workflow.registry, opened.terminal,
	)
	testing.expect(t, after_copy_recorded)
	if recorded && after_copy_recorded {
		testing.expect_value(
			t,
			after_copy.process.resources.queued_input_bytes,
			before.process.resources.queued_input_bytes,
		)
	}

	_, first_cancel_failure := dispatch_input(
		&commands,
		entry.buffer,
		entry.view_registry,
		entry.primary_view,
		terminal_interaction_test_scalar_input('g', {.Control}),
		constraints,
	)
	testing.expect_value(t, first_cancel_failure.stage, App_Stage.None)
	testing.expect(t, workflow_entry.copy_mode.active && !workflow_entry.copy_mode.selection_active)
	_, second_cancel_failure := dispatch_input(
		&commands,
		entry.buffer,
		entry.view_registry,
		entry.primary_view,
		terminal_interaction_test_scalar_input('g', {.Control}),
		constraints,
	)
	testing.expect_value(t, second_cancel_failure.stage, App_Stage.None)
	testing.expect(t, !workflow_entry.copy_mode.active)

	_, reenter_failure := dispatch_input(
		&commands, entry.buffer, entry.view_registry, entry.primary_view, {}, constraints, copy_mode,
	)
	testing.expect_value(t, reenter_failure.stage, App_Stage.None)
	_, done_failure := dispatch_input(
		&commands,
		entry.buffer,
		entry.view_registry,
		entry.primary_view,
		{kind = .Key, stroke = {kind = .Enter}},
		constraints,
	)
	testing.expect_value(t, done_failure.stage, App_Stage.None)
	testing.expect(t, !workflow_entry.copy_mode.active)
	after_done, done_recorded, _ := terminal_session.registry_record(
		&fixture.workflow.registry, opened.terminal,
	)
	testing.expect(t, done_recorded)
	if after_copy_recorded && done_recorded {
		testing.expect_value(
			t,
			after_done.process.resources.queued_input_bytes,
			after_copy.process.resources.queued_input_bytes,
		)
	}
	buffer_after, buffer_after_ok, _ := editor.buffer_stats(entry.buffer)
	testing.expect(t, buffer_after_ok)
	if buffer_before_ok && buffer_after_ok {
		testing.expect_value(t, buffer_after.revision, buffer_before.revision)
		testing.expect_value(t, buffer_after.text_bytes, buffer_before.text_bytes)
	}
	terminal_interaction_test_commands_close(&commands)
}

@(test)
/* Verifies child effects remain inert while admitted mouse and links route explicitly. */
terminal_mouse_links_and_effects_are_contained :: proc(t: ^testing.T) {
	fixture, ready := terminal_workflow_fixture_open(t, 9_725)
	testing.expect(t, ready)
	if !ready do return
	defer terminal_workflow_fixture_close(t, &fixture)
	opened, opened_ok, open_failure := terminal_workflow_open(
		&fixture.workflow,
		&fixture.session,
		fixture.handle,
		&fixture.layout,
		terminal_workflow_test_request(
			.Replace_Active,
			[]string{
				"-c",
				"printf '\\033]52;c;SGVsbG8=\\007" +
					"\\033]8;;https://example.com/accepted\\007link\\033]8;;\\007" +
					"\\033[?1000h\\033[?1006h'; sleep 2",
			},
		),
	)
	testing.expectf(t, opened_ok, "terminal open failed at %v", open_failure.stage)
	if !opened_ok do return
	record, recorded, record_failure := terminal_session.registry_record(
		&fixture.workflow.registry, opened.terminal,
	)
	testing.expectf(t, recorded, "terminal record failed with %v", record_failure.code)
	if !recorded do return
	for _ in 0 ..< 2_000 {
		_, _, _ = terminal_workflow_refresh(&fixture.workflow, &fixture.session, opened.terminal)
		state, state_result := terminal_emulator.mouse_state(record.emulator)
		if state_result == .OK && state.tracking do break
		time.sleep(time.Millisecond)
	}

	target: [terminal_session.MAX_HYPERLINK_BYTES]u8
	control_click := terminal_session.Mouse_Request {
		action = .Press,
		button = .Left,
		modifiers = {.Control},
		x = 1,
		y = 1,
	}
	linked, linked_ok, linked_failure := terminal_session.registry_route_mouse(
		&fixture.workflow.registry, opened.terminal, control_click, target[:],
	)
	testing.expectf(t, linked_ok, "terminal link failed with %v", linked_failure.code)
	if linked_ok {
		testing.expect_value(t, linked.route, terminal_session.Mouse_Route.Hyperlink)
		testing.expect_value(
			t,
			string(target[:int(linked.hyperlink_bytes)]),
			"https://example.com/accepted",
		)
		testing.expect_value(t, linked.queued_bytes, u64(0))
	}
	child_request := control_click
	child_request.modifiers = {}
	child, child_ok, child_failure := terminal_session.registry_route_mouse(
		&fixture.workflow.registry, opened.terminal, child_request, nil,
	)
	testing.expectf(t, child_ok, "child mouse failed with %v", child_failure.code)
	if child_ok {
		testing.expect_value(t, child.route, terminal_session.Mouse_Route.Child)
		testing.expect(t, child.queued_bytes > 0)
	}
	local_request := child_request
	local_request.modifiers = {.Shift}
	local, local_ok, local_failure := terminal_session.registry_route_mouse(
		&fixture.workflow.registry, opened.terminal, local_request, nil,
	)
	testing.expectf(t, local_ok, "local mouse failed with %v", local_failure.code)
	if local_ok do testing.expect_value(t, local.route, terminal_session.Mouse_Route.Local)

	text: [256]u8
	snapshot, copied, copy_failure := terminal_session.registry_copy_text(
		&fixture.workflow.registry,
		opened.terminal,
		{scope = .Screen, normalized = true},
		text[:],
	)
	testing.expectf(t, copied, "terminal text copy failed with %v", copy_failure.code)
	if copied {
		visible := string(text[:int(snapshot.copied_bytes)])
		testing.expect(t, strings.contains(visible, "link"))
		testing.expect(t, !strings.contains(visible, "SGVsbG8"))
	}

	disposed, dispose_failure := terminal_workflow_dispose(&fixture.workflow, opened.terminal)
	testing.expectf(t, disposed, "terminal dispose failed at %v", dispose_failure.stage)
	_, stale_ok, stale_failure := terminal_session.registry_route_mouse(
		&fixture.workflow.registry, opened.terminal, child_request, nil,
	)
	testing.expect(t, !stale_ok)
	testing.expect_value(t, stale_failure.code, terminal_session.Failure_Code.Stale_Reference)
	stats, inspected, _ := terminal_session.registry_inspect(&fixture.workflow.registry)
	testing.expect(t, inspected)
	if inspected do testing.expect_value(t, stats.session_count, u16(0))
}

@(test)
/* Verifies closing one terminal preserves another live terminal and the editor session. */
closing_one_terminal_preserves_another :: proc(t: ^testing.T) {
	fixture, ready := terminal_workflow_fixture_open(t, 9_726)
	testing.expect(t, ready)
	if !ready do return
	defer terminal_workflow_fixture_close(t, &fixture)
	first_request := terminal_workflow_test_request(
		.Replace_Active,
		[]string{"-c", "sleep 30"},
	)
	first_request.name = "first-terminal"
	first, first_ok, first_failure := terminal_workflow_open(
		&fixture.workflow,
		&fixture.session,
		fixture.handle,
		&fixture.layout,
		first_request,
	)
	testing.expectf(t, first_ok, "first terminal open failed at %v", first_failure.stage)
	if !first_ok do return
	second_request := terminal_workflow_test_request(
		.Other_Pane,
		[]string{"-c", "read value; printf 'survivor:%s\\n' \"$value\"; sleep 30"},
	)
	second_request.name = "second-terminal"
	second_request.default_session = false
	second_request.terminal.process.name = "second-terminal-workflow-test"
	second_request.terminal.process.make_default = false
	second, second_ok, second_failure := terminal_workflow_open(
		&fixture.workflow,
		&fixture.session,
		fixture.handle,
		&fixture.layout,
		second_request,
	)
	testing.expectf(t, second_ok, "second terminal open failed at %v", second_failure.stage)
	if !second_ok do return
	_, activated, activation_failure := editor_session.session_activate(&fixture.session, first.entry)
	testing.expectf(t, activated, "first terminal activation failed with %v", activation_failure.code)
	if !activated do return

	keys: Terminal_Interaction_Test_Keys
	commands := Command_Context {
		session_owner = &fixture.session,
		session_handle = fixture.handle,
		current_entry = first.entry,
		entry_configuration = editor_session.DEFAULT_ENTRY_CONFIGURATION,
		layout_registry = fixture.layout,
		terminal_workflow = &fixture.workflow,
		persistent_allocator = context.allocator,
		temporary_allocator = context.temp_allocator,
		next_transaction_id = 1,
		next_undo_unit_id = 1,
		grouping_started = time.tick_now(),
		grouping_continuity = 1,
	}
	if !terminal_interaction_test_keys_open(t, &keys, &commands) do return
	defer terminal_interaction_test_keys_close(&keys)
	_, begin_failure := command_context_begin_terminal_kill(&commands, {}, first.entry)
	testing.expect_value(t, begin_failure.stage, App_Stage.None)
	if begin_failure.stage != .None do return
	closed, close_failure := dispatch_terminal_kill_prompt(
		&commands,
		terminal_interaction_test_scalar_input('y', {}),
	)
	testing.expect_value(t, close_failure.stage, App_Stage.None)
	testing.expect(t, closed.changed)
	testing.expect(t, closed.active_entry_closed)
	testing.expect(t, !closed.exit)

	_, first_found, _ := editor_session.session_entry_access(&fixture.session, first.entry)
	testing.expect(t, !first_found)
	surviving, surviving_ok, _ := editor_session.session_terminal_buffer_state(
		&fixture.session,
		second.entry,
	)
	testing.expect(t, surviving_ok)
	if surviving_ok do testing.expect_value(t, surviving.lifecycle, editor_session.Terminal_Lifecycle.Running)
	visible, visible_ok, _ := editor_session.session_visible_target(&fixture.session, fixture.handle)
	testing.expect(t, visible_ok)
	if visible_ok {
		testing.expect_value(t, visible.kind, editor_session.Visible_Target_Kind.Primary_View)
		testing.expect(t, visible.entry != first.entry)
		_, fallback_found, _ := editor_session.session_entry_access(&fixture.session, visible.entry)
		testing.expect(t, fallback_found)
	}
	stats, inspected, _ := terminal_session.registry_inspect(&fixture.workflow.registry)
	testing.expect(t, inspected)
	if inspected {
		testing.expect_value(t, stats.session_count, u16(1))
		testing.expect_value(t, stats.running_count, u16(1))
	}

	_, input_ok, input_failure := terminal_session.registry_send_input(
		&fixture.workflow.registry,
		second.terminal,
		terminal_session.Input_Request {
			kind = .Text,
			action = .Press,
			text = "alive\n",
			source = .Ordinary,
			repeat_count = 1,
		},
	)
	testing.expectf(t, input_ok, "surviving terminal input failed with %v", input_failure.code)
	round_trip := false
	for _ in 0 ..< 2_000 {
		_, refreshed, _ := terminal_workflow_refresh(
			&fixture.workflow,
			&fixture.session,
			second.terminal,
		)
		if refreshed {
			text, copied := terminal_workflow_test_entry_text(&fixture.session, second.entry)
			if copied {
				round_trip = strings.contains(string(text), "survivor:alive")
				delete(text)
			}
			if round_trip do break
		}
		time.sleep(time.Millisecond)
	}
	testing.expect(t, round_trip)
	terminal_interaction_test_commands_close(&commands)
}

@(test)
/* Verifies terminal yank and yank-pop queue text without editing the projection buffer. */
terminal_interaction_yanks_retained_text :: proc(t: ^testing.T) {
	fixture, ready := terminal_workflow_fixture_open(t, 9_723)
	testing.expect(t, ready)
	if !ready do return
	defer terminal_workflow_fixture_close(t, &fixture)
	opened, opened_ok, _ := terminal_workflow_open(
		&fixture.workflow,
		&fixture.session,
		fixture.handle,
		&fixture.layout,
		terminal_workflow_test_request(.Replace_Active, []string{"-c", "sleep 2"}),
	)
	testing.expect(t, opened_ok)
	if !opened_ok do return
	ring: kill_ring.Ring
	ring_ok, _ := kill_ring.ring_init(
		&ring,
		kill_ring.Ring_ID(9_723),
		kill_ring.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	testing.expect(t, ring_ok)
	if !ring_ok do return
	defer kill_ring.ring_close(&ring)
	_, first_ok, _ := command.terminal_text_retain(&ring, {}, "first", 64)
	_, second_ok, _ := command.terminal_text_retain(&ring, {}, "second", 64)
	testing.expect(t, first_ok && second_ok)
	if !first_ok || !second_ok do return

	keys: Terminal_Interaction_Test_Keys
	commands := Command_Context {
		session_owner = &fixture.session,
		session_handle = fixture.handle,
		current_entry = opened.entry,
		terminal_workflow = &fixture.workflow,
		kill_ring = &ring,
		persistent_allocator = context.allocator,
		temporary_allocator = context.temp_allocator,
		next_transaction_id = 1,
		next_undo_unit_id = 1,
		grouping_started = time.tick_now(),
		grouping_continuity = 1,
	}
	if !terminal_interaction_test_keys_open(t, &keys, &commands) do return
	defer terminal_interaction_test_keys_close(&keys)
	access, accessed, _ := editor_session.session_entry_access(&fixture.session, opened.entry)
	entry, borrowed, _ := editor_session.entry_access_borrow(access)
	testing.expect(t, accessed && borrowed)
	if !accessed || !borrowed do return
	command_context_bind_entry(&commands, opened.entry, entry)
	before_stats, before_ok, _ := editor.buffer_stats(entry.buffer)
	testing.expect(t, before_ok)
	constraints := display.Viewport_Constraints{width_cells = 80, height_rows = 24}
	yanked, yank_failure := dispatch_input(
		&commands,
		entry.buffer,
		entry.view_registry,
		entry.primary_view,
		terminal_interaction_test_scalar_input('y', {.Control}),
		constraints,
	)
	testing.expect(t, yanked.changed)
	testing.expect_value(t, yank_failure.stage, App_Stage.None)
	after_yank, yank_recorded, _ := terminal_session.registry_record(
		&fixture.workflow.registry, opened.terminal,
	)
	testing.expect(t, yank_recorded)
	if yank_recorded do testing.expect_value(t, after_yank.process.resources.queued_input_bytes, u64(6))

	rotated, rotate_failure := dispatch_input(
		&commands,
		entry.buffer,
		entry.view_registry,
		entry.primary_view,
		terminal_interaction_test_scalar_input('y', {.Meta}),
		constraints,
	)
	testing.expect(t, rotated.changed)
	testing.expect_value(t, rotate_failure.stage, App_Stage.None)
	after_rotate, rotate_recorded, _ := terminal_session.registry_record(
		&fixture.workflow.registry, opened.terminal,
	)
	testing.expect(t, rotate_recorded)
	if rotate_recorded {
		testing.expect_value(t, after_rotate.process.resources.queued_input_bytes, u64(17))
	}
	next_prompt, prompt_found, _ := interaction.command_lookup(&keys.registry, "terminal-next-prompt")
	testing.expect(t, prompt_found)
	if prompt_found {
		prompt_result, prompt_failure := dispatch_input(
			&commands,
			entry.buffer,
			entry.view_registry,
			entry.primary_view,
			{},
			constraints,
			next_prompt,
		)
		testing.expect(t, prompt_result.changed)
		testing.expect_value(t, prompt_failure.stage, App_Stage.None)
		workflow_entry := terminal_workflow_entry_record(&fixture.workflow, opened.terminal)
		testing.expect(t, workflow_entry != nil)
		if workflow_entry != nil do testing.expect(t, !workflow_entry.yank.valid)
	}
	after_stats, after_ok, _ := editor.buffer_stats(entry.buffer)
	testing.expect(t, after_ok)
	if before_ok && after_ok do testing.expect_value(t, after_stats.text_bytes, before_stats.text_bytes)
	terminal_interaction_test_commands_close(&commands)
}

@(test)
/* Verifies literal-next bypasses one terminal binding without weakening recovery. */
terminal_interaction_literal_next_forwards_exactly_one_input :: proc(t: ^testing.T) {
	fixture, ready := terminal_workflow_fixture_open(t, 9_722)
	testing.expect(t, ready)
	if !ready do return
	defer terminal_workflow_fixture_close(t, &fixture)
	opened, opened_ok, _ := terminal_workflow_open(
		&fixture.workflow,
		&fixture.session,
		fixture.handle,
		&fixture.layout,
		terminal_workflow_test_request(
			.Replace_Active,
			[]string{"-c", "sleep 2"},
		),
	)
	testing.expect(t, opened_ok)
	if !opened_ok do return
	keys: Terminal_Interaction_Test_Keys
	commands := Command_Context {
		session_owner = &fixture.session,
		session_handle = fixture.handle,
		current_entry = opened.entry,
		terminal_workflow = &fixture.workflow,
		persistent_allocator = context.allocator,
		temporary_allocator = context.temp_allocator,
		next_transaction_id = 1,
		next_undo_unit_id = 1,
		grouping_started = time.tick_now(),
		grouping_continuity = 1,
	}
	keys_ready := terminal_interaction_test_keys_open(t, &keys, &commands)
	if !keys_ready do return
	defer terminal_interaction_test_keys_close(&keys)
	access, accessed, _ := editor_session.session_entry_access(&fixture.session, opened.entry)
	entry, borrowed, _ := editor_session.entry_access_borrow(access)
	testing.expect(t, accessed && borrowed)
	if !accessed || !borrowed do return
	command_context_bind_entry(&commands, opened.entry, entry)
	next_key, found, _ := interaction.command_lookup(&keys.registry, "terminal-send-next-key")
	testing.expect(t, found)
	if !found do return
	constraints := display.Viewport_Constraints{width_cells = 80, height_rows = 24}
	_, arm_failure := dispatch_input(
		&commands,
		entry.buffer,
		entry.view_registry,
		entry.primary_view,
		{},
		constraints,
		next_key,
	)
	testing.expect_value(t, arm_failure.stage, App_Stage.None)
	_, protected_failure := dispatch_input(
		&commands,
		entry.buffer,
		entry.view_registry,
		entry.primary_view,
		terminal_interaction_test_scalar_input('g', {.Control}),
		constraints,
	)
	testing.expect_value(t, protected_failure.stage, App_Stage.None)
	after_protected, protected_recorded, _ := terminal_session.registry_record(
		&fixture.workflow.registry,
		opened.terminal,
	)
	testing.expect(t, protected_recorded)
	if protected_recorded do testing.expect_value(t, after_protected.process.resources.queued_input_bytes, u64(0))
	testing.expect_value(t, fixture.workflow.literal_next, opened.terminal)
	_, send_failure := dispatch_input(
		&commands,
		entry.buffer,
		entry.view_registry,
		entry.primary_view,
		terminal_interaction_test_scalar_input('q', {.Control}),
		constraints,
	)
	testing.expect_value(t, send_failure.stage, App_Stage.None)
	after_send, recorded, _ := terminal_session.registry_record(
		&fixture.workflow.registry,
		opened.terminal,
	)
	testing.expect(t, recorded)
	if recorded do testing.expect(t, after_send.process.resources.queued_input_bytes > 0)
	testing.expect_value(t, fixture.workflow.literal_next, terminal_session.Session_Ref{})
	_, rearm_failure := dispatch_input(
		&commands,
		entry.buffer,
		entry.view_registry,
		entry.primary_view,
		terminal_interaction_test_scalar_input('q', {.Control}),
		constraints,
	)
	testing.expect_value(t, rearm_failure.stage, App_Stage.None)
	after_rearm, rearm_recorded, _ := terminal_session.registry_record(
		&fixture.workflow.registry,
		opened.terminal,
	)
	testing.expect(t, rearm_recorded)
	if recorded && rearm_recorded {
		testing.expect_value(
			t,
			after_rearm.process.resources.queued_input_bytes,
			after_send.process.resources.queued_input_bytes,
		)
	}
	testing.expect_value(t, fixture.workflow.literal_next, opened.terminal)
	fixture.workflow.literal_next = {}
	terminal_interaction_test_commands_close(&commands)
}

@(private)
Terminal_Interaction_Test_Keys :: struct {
	registry: interaction.Command_Registry,
	keymap:   interaction.Resolution_Snapshot,
	maps:     interaction.Context_Map_Stack,
}

@(private)
terminal_interaction_test_keys_open :: proc(
	t: ^testing.T,
	state: ^Terminal_Interaction_Test_Keys,
	commands: ^Command_Context,
) -> bool {
	generation := interaction.Registry_Generation(9_720)
	registry_ok, registry_failure := command.built_in_command_registry_init(
		&state.registry,
		generation,
		context.allocator,
	)
	testing.expectf(t, registry_ok, "terminal command registry failed with %v", registry_failure.code)
	if !registry_ok do return false
	bindings := [4]interaction.Binding_Definition {
		{
			strokes = {0 = terminal_context_scalar_stroke('g', {.Control})},
			stroke_count = 1,
			command_name = "keyboard-quit",
		},
		{
			strokes = {0 = terminal_context_scalar_stroke('x', {.Meta})},
			stroke_count = 1,
			command_name = "execute-extended-command",
		},
		{
			strokes = {
				0 = terminal_context_scalar_stroke('x', {.Control}),
				1 = terminal_context_scalar_stroke('b', {}),
			},
			stroke_count = 2,
			command_name = "list-buffers",
		},
		{
			strokes = {0 = interaction.Key_Stroke{kind = .Enter}},
			stroke_count = 1,
			command_name = "insert-line-break",
		},
	}
	keymap_ok, keymap_failure := interaction.snapshot_compile(
		&state.keymap,
		&state.registry,
		interaction.Snapshot_Generation(9_720),
		{
			registry_generation = generation,
			bindings = bindings[:],
			text_fallback_name = "insert-text",
		},
		context.allocator,
	)
	testing.expectf(t, keymap_ok, "terminal keymap failed with %v", keymap_failure.code)
	if !keymap_ok {
		_, _ = interaction.command_registry_close(&state.registry)
		return false
	}
	maps_ok, maps_failure := interaction.context_map_stack_init(
		&state.maps,
		interaction.Context_ID(9_720),
		&state.registry,
		context.allocator,
	)
	testing.expectf(t, maps_ok, "terminal context maps failed with %v", maps_failure.code)
	if !maps_ok {
		_, _ = interaction.snapshot_close(&state.keymap)
		_, _ = interaction.command_registry_close(&state.registry)
		return false
	}
	commands.registry = &state.registry
	commands.registry_generation = generation
	commands.keymap = &state.keymap
	commands.context_maps = &state.maps
	if commands.persistent_allocator.procedure == nil do commands.persistent_allocator = context.allocator
	if commands.temporary_allocator.procedure == nil do commands.temporary_allocator = context.temp_allocator
	if commands.next_transaction_id == 0 do commands.next_transaction_id = 1
	if commands.next_undo_unit_id == 0 do commands.next_undo_unit_id = 1
	return true
}

@(private)
terminal_interaction_test_keys_close :: proc(state: ^Terminal_Interaction_Test_Keys) {
	if state.maps.state != nil do _, _ = interaction.context_map_stack_close(&state.maps)
	if state.keymap.state != nil && !state.keymap.closed do _, _ = interaction.snapshot_close(&state.keymap)
	if state.registry.state != nil && !state.registry.closed do _, _ = interaction.command_registry_close(&state.registry)
}

@(private)
terminal_interaction_test_activate_modal :: proc(
	t: ^testing.T,
	commands: ^Command_Context,
	registry: ^interaction.Command_Registry,
	activation: ^interaction.Profile_Activation,
) -> bool {
	bindings := [?]interaction.Layered_Binding_Definition {
		terminal_interaction_test_modal_binding(1, 'i', "modal-enter-insert"),
		terminal_interaction_test_modal_binding(2, 0, "modal-enter-normal", .Escape),
	}
	states := [?]interaction.Interaction_State_Definition {
		{
			identity = {id = 1, revision = 1},
			name = "Normal",
			admitted_effects = {.Buffer, .View, .Lifecycle, .Text_Mutation},
			provenance = {provider = "test", source = "modal-terminal"},
		},
		{
			identity = {id = 2, revision = 1},
			name = "Insert",
			admits_text_input = true,
			admitted_effects = {.Buffer, .View, .Lifecycle, .Text_Mutation},
			provenance = {provider = "test", source = "modal-terminal"},
		},
	}
	maps := [?]interaction.Map_Definition {{
		identity = {id = 1, revision = 1},
		name = "modal-base",
		precedence = .Profile_Base,
		bindings = bindings[:],
		unmatched_input_policy = .Reject,
		provenance = {provider = "test", source = "modal-terminal"},
	}}
	profiles := [?]interaction.Profile_Definition {{
		identity = {id = 2, revision = 1},
		name = "modal",
		states = states[:],
		initial_state = 1,
		maps = maps[:],
		text_fallback_name = "insert-text",
	}}
	surfaces := [?]interaction.Command_Entry_Surface_Definition {{
		identity = {id = 1, revision = 1},
		name = "extended-command",
		provenance = {provider = "test", source = "modal-terminal"},
	}}
	closed, close_failure := interaction.snapshot_close(&commands.keymap^)
	testing.expectf(t, closed, "terminal fixture snapshot close failed with %v", close_failure.code)
	if !closed do return false
	commands.keymap = nil
	interaction.profile_activation_init(activation)
	commands.active_interaction_context = {identity = {id = 1, generation = 1}}
	published, failure := interaction.profile_activation_replace_catalog(
		activation,
		registry,
		interaction.Profile_Catalog_Definition {
			generation = 1,
			profiles = profiles[:],
			active_profile = 2,
			active_state = 1,
			surfaces = surfaces[:],
		},
		commands.active_interaction_context,
		&commands.pending,
		interaction.DEFAULT_PROFILE_COMPATIBILITY_POLICY,
		interaction.DEFAULT_RESOLUTION_POLICY,
		context.allocator,
	)
	testing.expectf(t, published, "modal terminal activation failed with %v", failure.code)
	if !published do return false
	snapshot, active := interaction.profile_activation_snapshot(activation)
	testing.expect(t, active)
	if !active do return false
	commands.profile_activation = activation
	commands.keymap = snapshot
	return true
}

@(private)
terminal_interaction_test_modal_binding :: proc(
	state_id: u64,
	value: rune,
	command_name: string,
	kind := interaction.Logical_Key_Kind.Unicode_Scalar,
) -> interaction.Layered_Binding_Definition {
	return interaction.Layered_Binding_Definition {
		sequence = {
			strokes = {0 = {kind = kind, scalar = value}},
			stroke_count = 1,
		},
		command_name = command_name,
		operation = .Bind,
		scope = .State_Specific,
		selectors = terminal_modal_test_selectors[state_id - 1][:],
		provenance = {provider = "test", source = "modal-terminal"},
	}
}

@(private)
terminal_interaction_test_resolve :: proc(
	commands: ^Command_Context,
	input: interaction.Input,
) -> (interaction.Resolution, interaction.Failure_Context) {
	return interaction.resolve_contextual_input(
		commands.context_maps,
		commands.keymap,
		commands.registry_generation,
		&commands.context_pending,
		&commands.pending,
		input,
	)
}

@(private)
terminal_interaction_test_expect_command :: proc(
	t: ^testing.T,
	registry: ^interaction.Command_Registry,
	resolution: interaction.Resolution,
	name: string,
) {
	testing.expect_value(t, resolution.kind, interaction.Resolution_Kind.Command)
	if resolution.kind != .Command do return
	metadata, found, _ := interaction.command_metadata(registry, resolution.command)
	testing.expect(t, found)
	if found do testing.expect_value(t, metadata.name, name)
}

@(private)
terminal_interaction_test_scalar_input :: proc(
	value: rune,
	modifiers: interaction.Modifiers,
) -> interaction.Input {
	return {
		kind = .Key,
		stroke = terminal_context_scalar_stroke(value, modifiers),
	}
}

@(private)
terminal_interaction_test_commands_close :: proc(commands: ^Command_Context) {
	command_context_deactivate_terminal_map(commands)
	if commands.location_history != nil {
		free(commands.location_history, commands.persistent_allocator)
		commands.location_history = nil
	}
}
