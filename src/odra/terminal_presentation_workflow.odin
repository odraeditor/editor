// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../command"
import "../editor_session"
import "../interactive_session"
import "../interaction"
import "../layout"
import "../terminal_emulator"
import "../terminal_session"

@(private)
command_context_dispatch_terminal_presentation :: proc(
	commands: ^Command_Context,
	route: command.Native_Route,
	command_handle: interaction.Command_Handle,
) -> (Interaction_Result, App_Failure) {
	if commands == nil || commands.session_owner == nil || commands.terminal_workflow == nil ||
	   !commands.terminal_workflow.initialized || !command_context_layout_is_live(commands) {
		return {}, App_Failure{stage = .Component_Access}
	}
	purpose := Terminal_Context_Purpose.Default
	if route == .Terminal_Open_Here do purpose = .Here
	if route == .Terminal_Open_Project do purpose = .Project
	working, resolution, context_failure := terminal_context_resolve(
		commands,
		{
			purpose = purpose,
			global_shell = commands.terminal_global_shell,
			workspace_shell = commands.terminal_workspace_shell,
		},
	)
	if resolution == .Project_Selection_Required {
		command_context_set_diagnostic(commands, "Select a Project, then run terminal-open-project again")
		return command_context_present_project_navigation(commands)
	}
	if resolution != .Resolved {
		terminal_context_failure_diagnostic(commands, context_failure)
		return Interaction_Result{changed = true}, {}
	}
	scope := terminal_workflow_scope(&working)
	if commands.terminal_workflow.toggle.visible &&
	   !terminal_workflow_scope_equal(commands.terminal_workflow.toggle.scope, scope) {
		_, hide_failure := command_context_terminal_toggle_hide(commands)
		if hide_failure.stage != .None do return {}, hide_failure
	}
	if route == .Terminal_Toggle {
		if commands.terminal_workflow.toggle.visible {
			return command_context_terminal_toggle_hide(commands)
		}
		return command_context_terminal_toggle_show(commands, &working, command_handle)
	}
	default_session := route == .Terminal_Open || route == .Terminal_Open_Other_Pane
	if default_session {
		retained, found := terminal_workflow_default(commands.terminal_workflow, scope)
		if found {
			if route == .Terminal_Open_Other_Pane {
				return command_context_present_terminal_entry(commands, retained, .Other_Pane)
			}
			return command_context_terminal_lower_pane_show(commands, retained)
		}
	}
	presentation := Terminal_Presentation.Hidden
	if route == .Terminal_Open_Other_Pane do presentation = .Other_Pane
	created, target, create_failure := command_context_create_terminal(
		commands,
		&working,
		presentation,
		default_session,
		command_handle,
	)
	if create_failure.stage != .None do return {}, create_failure
	if presentation == .Other_Pane do return created, {}
	return command_context_terminal_lower_pane_show(commands, target)
}

@(private)
command_context_create_terminal :: proc(
	commands: ^Command_Context,
	working: ^Terminal_Working_Context,
	presentation: Terminal_Presentation,
	default_session: bool,
	command_handle: interaction.Command_Handle,
) -> (Interaction_Result, Terminal_Workflow_Entry, App_Failure) {
	_ = command_handle
	name_storage: [interactive_session.MAX_NAME_BYTES]u8
	name, named := terminal_workflow_next_name(commands.terminal_workflow, name_storage[:])
	if !named do return {}, {}, App_Failure{stage = .Component_Access}
	directory := terminal_context_directory(working)
	shell := terminal_context_shell(working)
	arguments := [1]string{"-i"}
	options := terminal_emulator.DEFAULT_OPTIONS
	opened, open_ok, open_failure := terminal_workflow_open(
		commands.terminal_workflow,
		commands.session_owner,
		commands.session_handle,
		&commands.layout_registry,
		Terminal_Open_Request {
			name = name,
			working_context = directory,
			presentation = presentation,
			configuration = commands.entry_configuration,
			scope = terminal_workflow_scope(working),
			default_session = default_session,
			terminal = {
				process = {
					name = name,
					owner_kind = .Interactive_User,
					owner_label = "interactive user",
					working_directory = directory,
					limits = terminal_interactive_limits(),
					make_default = default_session,
				},
				start = {
					executable = shell,
					arguments = arguments[:],
					working_directory = directory,
					columns = options.columns,
					rows = options.rows,
				},
				emulator = options,
				limits = terminal_session.DEFAULT_LIMITS,
			},
		},
	)
	if !open_ok {
		return {}, {}, app_terminal_workflow_failure(open_failure)
	}
	_ = terminal_workflow_commit_name(commands.terminal_workflow)
	if presentation != .Hidden {
		_, activated, activation_failure := editor_session.session_activate(
			commands.session_owner,
			opened.entry,
		)
		if !activated do return {}, {}, App_Failure{stage = .Session_Access, editor_session = activation_failure}
		commands.layout_entry = opened.entry
		commands.current_entry = opened.entry
		_ = terminal_workflow_note_focus(commands.terminal_workflow, opened.terminal)
	}
	command_context_set_diagnostic(commands, "Terminal created")
	return Interaction_Result{changed = true},
	       terminal_workflow_entry_record(commands.terminal_workflow, opened.terminal)^, {}
}

/* command_context_reconcile_terminal_exits closes completed interactive terminal buffers. */
command_context_reconcile_terminal_exits :: proc(
	commands: ^Command_Context,
) -> (changed: bool, failure: App_Failure) {
	if commands == nil || commands.session_owner == nil || commands.terminal_workflow == nil ||
	   !commands.terminal_workflow.initialized {
		return false, App_Failure{stage = .Component_Access}
	}
	for entry in commands.terminal_workflow.entries {
		if !entry.live || entry.one_shot_kind != .None do continue
		record, recorded, terminal_failure := terminal_session.registry_record(
			&commands.terminal_workflow.registry,
			entry.terminal,
		)
		if !recorded {
			return changed, app_terminal_workflow_failure(
				{stage = .Refresh, terminal = terminal_failure},
			)
		}
		if record.lifecycle != .Exited do continue
		if commands.terminal_workflow.toggle.visible &&
		   commands.terminal_workflow.toggle.terminal == entry.terminal {
			handle, handle_ok, handle_failure := layout.registry_handle(&commands.layout_registry)
			if !handle_ok do return changed, App_Failure{stage = .Layout, layout = handle_failure}
			snapshot, snapshot_ok, snapshot_failure := layout.registry_snapshot(&commands.layout_registry, handle)
			if !snapshot_ok do return changed, App_Failure{stage = .Layout, layout = snapshot_failure}
			// Leave the last pane for the existing scratch-buffer fallback.
			if snapshot.pane_count > 1 {
				_, hide_failure := command_context_terminal_toggle_hide(commands)
				if hide_failure.stage != .None do return changed, hide_failure
			}
		}

		label, label_ok, label_failure := editor_session.session_entry_label(
			commands.session_owner,
			entry.entry,
		)
		if !label_ok {
			return changed, App_Failure{stage = .Session_Access, editor_session = label_failure}
		}
		disposed, dispose_failure := terminal_workflow_dispose(
			commands.terminal_workflow,
			entry.terminal,
		)
		if !disposed do return changed, app_terminal_workflow_failure(dispose_failure)
		kill_result, killed, kill_failure := command_context_kill_buffer(
			commands,
			editor_session.closure_label_text(&label),
			.Discard_Modified,
			terminal_editor_ref(entry.terminal),
		)
		if !killed || kill_result.completion != .Closed {
			return changed, App_Failure{stage = .Command_Dispatch, command = kill_failure}
		}
		fallback_ok, fallback_failure := command_context_ensure_text_fallback(
			commands,
			kill_result.closure,
		)
		if !fallback_ok do return changed, fallback_failure
		changed = true
	}
	if changed do command_context_set_diagnostic(commands, "Terminal exited")
	return changed, {}
}

@(private)
terminal_interactive_limits :: proc() -> interactive_session.Limits {
	limits := interactive_session.DEFAULT_LIMITS
	limits.columns = interactive_session.MAX_COLUMNS
	limits.rows = u16(interactive_session.MAX_CELLS / interactive_session.MAX_COLUMNS)
	return limits
}

@(private)
command_context_present_terminal_entry :: proc(
	commands: ^Command_Context,
	entry: Terminal_Workflow_Entry,
	presentation: Terminal_Presentation,
) -> (Interaction_Result, App_Failure) {
	if presentation == .Other_Pane {
		_, shown, show_failure := command_context_layout_display_entry_result(commands, entry.entry, true)
		if !shown do return {}, show_failure
	} else {
		if replace_failure := command_context_layout_replace_active(commands, entry.entry);
		   replace_failure.stage != .None {
			return {}, replace_failure
		}
		_, activated, activation_failure := editor_session.session_activate(
			commands.session_owner,
			entry.entry,
		)
		if !activated do return {}, App_Failure{stage = .Session_Access, editor_session = activation_failure}
		commands.layout_entry = entry.entry
	}
	commands.current_entry = entry.entry
	_ = terminal_workflow_note_focus(commands.terminal_workflow, entry.terminal)
	command_context_set_diagnostic(commands, "Terminal selected")
	return Interaction_Result{changed = true}, {}
}

@(private)
command_context_terminal_toggle_show :: proc(
	commands: ^Command_Context,
	working: ^Terminal_Working_Context,
	command_handle: interaction.Command_Handle,
) -> (Interaction_Result, App_Failure) {
	scope := terminal_workflow_scope(working)
	target, found := terminal_workflow_last_focused(commands.terminal_workflow, scope)
	if !found {
		target, found = terminal_workflow_default(commands.terminal_workflow, scope)
	}
	if !found {
		_, created, create_failure := command_context_create_terminal(
			commands,
			working,
			.Hidden,
			true,
			command_handle,
		)
		if create_failure.stage != .None do return {}, create_failure
		target = created
	}
	return command_context_terminal_lower_pane_show(commands, target)
}

@(private)
command_context_terminal_lower_pane_show :: proc(
	commands: ^Command_Context,
	target: Terminal_Workflow_Entry,
) -> (Interaction_Result, App_Failure) {
	handle, handle_ok, handle_failure := layout.registry_handle(&commands.layout_registry)
	if !handle_ok do return {}, App_Failure{stage = .Layout, layout = handle_failure}
	before, snapshot_ok, snapshot_failure := layout.registry_snapshot(&commands.layout_registry, handle)
	if !snapshot_ok do return {}, App_Failure{stage = .Layout, layout = snapshot_failure}
	active, active_ok := command_context_layout_active_node(&before)
	if !active_ok do return {}, App_Failure{stage = .Layout}
	toggle := &commands.terminal_workflow.toggle
	if toggle.visible {
		remembered := terminal_workflow_entry_record(commands.terminal_workflow, toggle.terminal)
		for node in before.nodes[:before.node_count] {
			if node.kind != .Pane || node.pane.pane_id != toggle.pane.pane_id do continue
			// A replaced buffer is an ordinary editing pane, not our terminal slot.
			if remembered == nil || node.entry != remembered.entry do break
			pane := node.pane
			if node.entry != target.entry {
				replaced, replaced_ok, replace_failure := layout.registry_replace_pane_buffer(
					&commands.layout_registry, pane, commands.session_owner, target.entry,
				)
				if !replaced_ok do return {}, App_Failure{stage = .Layout, layout = replace_failure}
				pane = replaced.pane
			}
			focused, focused_ok, focus_failure := layout.registry_focus(&commands.layout_registry, pane)
			if !focused_ok do return {}, App_Failure{stage = .Layout, layout = focus_failure}
			_, activated, activation_failure := editor_session.session_activate(commands.session_owner, target.entry)
			if !activated do return {}, App_Failure{stage = .Session_Access, editor_session = activation_failure}
			if active.pane.pane_id != node.pane.pane_id {
				toggle.return_pane = active.pane
				toggle.return_entry = active.entry
			}
			toggle.pane = focused.active
			toggle.terminal = target.terminal
			toggle.scope = target.scope
			commands.layout_entry = target.entry
			commands.current_entry = target.entry
			_ = terminal_workflow_note_focus(commands.terminal_workflow, target.terminal)
			command_context_set_diagnostic(commands, "Terminal pane shown")
			return Interaction_Result{changed = true}, {}
		}
		toggle^ = {height = toggle.height}
	}
	shown, show_failure := command_context_layout_split_entry(commands, target.entry, true)
	if !shown do return {}, show_failure
	after_handle, _, _ := layout.registry_handle(&commands.layout_registry)
	after, after_ok, after_failure := layout.registry_snapshot(&commands.layout_registry, after_handle)
	if !after_ok do return {}, App_Failure{stage = .Layout, layout = after_failure}
	toggle_node, toggle_ok := command_context_layout_active_node(&after)
	if !toggle_ok do return {}, App_Failure{stage = .Layout}
	remembered_height := commands.terminal_workflow.toggle.height
	commands.terminal_workflow.toggle = {
		visible = true,
		pane = toggle_node.pane,
		return_pane = active.pane,
		return_entry = active.entry,
		terminal = target.terminal,
		scope = target.scope,
		height = toggle_node.geometry.outer.height,
	}
	if remembered_height > 0 {
		command_context_terminal_toggle_restore_height(commands, remembered_height)
	}
	commands.current_entry = target.entry
	_ = terminal_workflow_note_focus(commands.terminal_workflow, target.terminal)
	command_context_set_diagnostic(commands, "Terminal pane shown")
	return Interaction_Result{changed = true}, {}
}

@(private)
command_context_terminal_toggle_hide :: proc(
	commands: ^Command_Context,
) -> (Interaction_Result, App_Failure) {
	toggle := &commands.terminal_workflow.toggle
	if !toggle.visible do return Interaction_Result{}, {}
	handle, handle_ok, handle_failure := layout.registry_handle(&commands.layout_registry)
	if !handle_ok do return {}, App_Failure{stage = .Layout, layout = handle_failure}
	snapshot, snapshot_ok, snapshot_failure := layout.registry_snapshot(&commands.layout_registry, handle)
	if !snapshot_ok do return {}, App_Failure{stage = .Layout, layout = snapshot_failure}
	found := false
	preferred_pane := toggle.return_pane.pane_id
	if snapshot.active_pane.pane_id != toggle.pane.pane_id {
		preferred_pane = snapshot.active_pane.pane_id
	}
	remembered := terminal_workflow_entry_record(commands.terminal_workflow, toggle.terminal)
	for node in snapshot.nodes[:snapshot.node_count] {
		if node.kind != .Pane || node.pane.pane_id != toggle.pane.pane_id do continue
		if remembered == nil || node.entry != remembered.entry do break
		toggle.height = node.geometry.outer.height
		toggle.pane = node.pane
		found = true
		break
	}
	remembered_height := toggle.height
	if found {
		_, focused, focus_failure := layout.registry_focus(&commands.layout_registry, toggle.pane)
		if !focused do return {}, App_Failure{stage = .Layout, layout = focus_failure}
		_, closed, close_failure := layout.registry_close_pane(&commands.layout_registry, toggle.pane)
		if !closed do return {}, App_Failure{stage = .Layout, layout = close_failure}
	}
	after_handle, _, _ := layout.registry_handle(&commands.layout_registry)
	after, after_ok, after_failure := layout.registry_snapshot(&commands.layout_registry, after_handle)
	if !after_ok do return {}, App_Failure{stage = .Layout, layout = after_failure}
	for node in after.nodes[:after.node_count] {
		if node.kind != .Pane || node.pane.pane_id != preferred_pane do continue
		_, focused, focus_failure := layout.registry_focus(&commands.layout_registry, node.pane)
		if !focused do return {}, App_Failure{stage = .Layout, layout = focus_failure}
		break
	}
	if sync_failure := command_context_layout_sync_active_entry(commands); sync_failure.stage != .None {
		return {}, sync_failure
	}
	commands.current_entry = commands.layout_entry
	toggle^ = {height = remembered_height}
	command_context_set_diagnostic(commands, "Terminal pane hidden")
	return Interaction_Result{changed = true}, {}
}

@(private)
command_context_terminal_toggle_restore_height :: proc(commands: ^Command_Context, desired: i32) {
	toggle := &commands.terminal_workflow.toggle
	for _ in 0 ..< 256 {
		handle, handle_ok, _ := layout.registry_handle(&commands.layout_registry)
		if !handle_ok do return
		snapshot, snapshot_ok, _ := layout.registry_snapshot(&commands.layout_registry, handle)
		if !snapshot_ok do return
		current := i32(0)
		for node in snapshot.nodes[:snapshot.node_count] {
			if node.kind == .Pane && node.pane.pane_id == toggle.pane.pane_id {
				current = node.geometry.outer.height
				toggle.pane = node.pane
				break
			}
		}
		if current == 0 || current == desired do return
		delta := i32(-1)
		if current < desired do delta = 1
		resized, resized_ok, _ := layout.registry_resize_pane(
			&commands.layout_registry,
			toggle.pane,
			.Above_Below,
			delta,
		)
		if !resized_ok do return
		toggle.pane = resized.pane
	}
}

@(private)
terminal_context_failure_diagnostic :: proc(
	commands: ^Command_Context,
	failure: Terminal_Context_Failure,
) {
	#partial switch failure.code {
	case .No_Directory, .Invalid_Directory:
		command_context_set_diagnostic(commands, "Terminal working directory is unavailable")
	case .No_Shell, .Invalid_Shell:
		command_context_set_diagnostic(commands, "Terminal shell is unavailable")
	case:
		command_context_set_diagnostic(commands, "Terminal context is unavailable")
	}
}

@(private)
command_context_begin_terminal_rename :: proc(
	commands: ^Command_Context,
	command_handle: interaction.Command_Handle,
) -> (Interaction_Result, App_Failure) {
	state, active := command_context_active_terminal_state(commands)
	if !active {
		command_context_set_diagnostic(commands, "Requires an active terminal")
		return Interaction_Result{changed = true}, {}
	}
	label, label_ok, label_failure := editor_session.session_entry_label(
		commands.session_owner,
		commands.current_entry,
	)
	if !label_ok do return {}, App_Failure{stage = .Session_Access, editor_session = label_failure}
	prompt_ok, prompt_failure := interaction.prompt_init(
		&commands.prompt_workflow.prompt,
		interaction.Prompt_Config {
			kind = .Text_Entry,
			text_bytes_limit = editor_session.MAX_NAME_BYTES,
			allow_empty = false,
			allocator = commands.persistent_allocator,
		},
	)
	if !prompt_ok do return {}, App_Failure{stage = .Prompt, prompt_failure = prompt_failure}
	_, append_failure := interaction.prompt_text_append(
		&commands.prompt_workflow.prompt,
		editor_session.closure_label_text(&label),
	)
	if append_failure.code != .None {
		_, _ = interaction.prompt_close(&commands.prompt_workflow.prompt)
		return {}, App_Failure{stage = .Prompt, prompt_failure = append_failure}
	}
	if !prompt_workflow_begin_projection(&commands.prompt_workflow, .Terminal_Rename) {
		_, _ = interaction.prompt_close(&commands.prompt_workflow.prompt)
		return {}, App_Failure{stage = .UI, ui = {operation = .Prepare, code = .Generation_Limit}}
	}
	commands.document_workflow.buffer_command = command_handle
	commands.document_workflow.kill_entry = state.entry
	if map_failure := command_context_activate_prompt_map(commands, .Terminal_Rename);
	   map_failure.stage != .None {
		_, _ = interaction.prompt_close(&commands.prompt_workflow.prompt)
		commands.prompt_workflow.mode = .None
		return {}, map_failure
	}
	return Interaction_Result{changed = true}, {}
}

@(private)
dispatch_terminal_rename_prompt :: proc(
	commands: ^Command_Context,
	input: interaction.Input,
) -> (Interaction_Result, App_Failure) {
	metadata, resolution, resolved, resolve_failure := command_context_resolve_prompt_input(commands, input)
	if !resolved do return {}, resolve_failure
	if resolution.kind != .Command do return {}, {}
	if command_metadata_is_cancel(metadata) {
		_, _ = interaction.prompt_cancel(&commands.prompt_workflow.prompt)
		command_context_deactivate_prompt_map(commands, .Cancelled)
		command_context_end_prompt(commands)
		return Interaction_Result{changed = true}, {}
	}
	if command_metadata_is_contextual(metadata, .Prompt_Delete_Previous) {
		transition, prompt_failure := interaction.prompt_text_delete_previous(&commands.prompt_workflow.prompt)
		if prompt_failure.code != .None do return {}, App_Failure{stage = .Prompt, prompt_failure = prompt_failure}
		commands.prompt_workflow.rejected = false
		return Interaction_Result{changed = transition == .Changed}, {}
	}
	if command_metadata_is_contextual(metadata, .Prompt_Insert_Text) {
		transition, prompt_failure := interaction.prompt_text_append(&commands.prompt_workflow.prompt, resolution.text)
		if prompt_failure.code != .None {
			commands.prompt_workflow.rejected = true
			return Interaction_Result{changed = true}, {}
		}
		commands.prompt_workflow.rejected = false
		return Interaction_Result{changed = transition == .Changed}, {}
	}
	if !command_metadata_is_contextual(metadata, .Prompt_Accept) do return {}, {}
	_, accept_failure := interaction.prompt_text_accept(&commands.prompt_workflow.prompt)
	if accept_failure.code != .None {
		commands.prompt_workflow.rejected = true
		return Interaction_Result{changed = true}, {}
	}
	view, viewed, view_failure := interaction.prompt_view(&commands.prompt_workflow.prompt)
	if !viewed do return {}, App_Failure{stage = .Prompt, prompt_failure = view_failure}
	entry := commands.document_workflow.kill_entry
	state, state_ok, state_failure := editor_session.session_terminal_buffer_state(commands.session_owner, entry)
	if !state_ok do return {}, App_Failure{stage = .Session_Access, editor_session = state_failure}
	_, renamed, _ := editor_session.session_rename_terminal_buffer(
		commands.session_owner,
		{entry = entry, terminal = state.terminal, name = view.text},
	)
	if !renamed {
		commands.prompt_workflow.rejected = true
		return Interaction_Result{changed = true}, {}
	}
	command_context_deactivate_prompt_map(commands, .Completed)
	command_context_end_prompt(commands)
	command_context_set_diagnostic(commands, "Terminal renamed")
	return Interaction_Result{changed = true}, {}
}
