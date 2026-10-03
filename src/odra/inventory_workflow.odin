// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../command"
import "../display"
import "../document"
import "../editor_session"
import "../feedback"
import "../feedback_workflow"
import "../interaction"
import "../ui"

@(private)
Inventory_Workflow_State :: struct {
	command_handle: interaction.Command_Handle,
	return_target:  editor_session.Visible_Target,
	position:       ui.List_View_Position,
	current_entry:  editor_session.Entry_Handle,
	model_generation: u64,
	marks:          [editor_session.DEFAULT_INVENTORY_MARKS]command.Buffer_Marked_Entry,
	mark_count:     u32,
	batch:          [editor_session.DEFAULT_INVENTORY_MARKS]command.Buffer_Marked_Entry,
	batch_count:    u32,
	decisions:      [editor_session.MAX_INVENTORY_MARKS]command.Marked_Entry_Decision,
	decision_count: u32,
	pending_entry:  editor_session.Entry_Handle,
	path:           [document.MAX_PATH_BYTES]byte,
	path_length:    int,
	terminal_only:  bool,
}

@(private)
command_context_traverse_buffer :: proc(
	commands: ^Command_Context,
	forward: bool,
) -> (Interaction_Result, App_Failure) {
	if commands == nil || commands.session_owner == nil {
		return {}, App_Failure{stage = .Session_Access}
	}
	entries: [editor_session.MAX_LIVE_BUFFERS]editor_session.Entry_Handle
	count, copied, copy_failure := editor_session.session_ordered_entries(
		commands.session_owner,
		commands.session_handle,
		entries[:],
	)
	if !copied {
		return {}, App_Failure{stage = .Session_Access, editor_session = copy_failure}
	}
	if count <= 1 {
		command_context_set_diagnostic(commands, "No other buffer")
		return Interaction_Result{changed = true}, {}
	}
	current := -1
	for index in 0 ..< int(count) {
		if entries[index] == commands.current_entry {
			current = index
			break
		}
	}
	if current < 0 {
		command_context_set_diagnostic(commands, "Current buffer is no longer in the session")
		return Interaction_Result{changed = true}, {}
	}
	target := (current + 1) % int(count)
	if !forward do target = (current + int(count) - 1) % int(count)
	_, activated, activation_failure := editor_session.session_activate(
		commands.session_owner,
		entries[target],
	)
	if !activated {
		return {}, App_Failure{stage = .Session_Access, editor_session = activation_failure}
	}
	command_context_set_diagnostic(
		commands,
		"Selected next buffer" if forward else "Selected previous buffer",
	)
	return Interaction_Result{changed = true}, {}
}

@(private)
inventory_workflow_reset :: proc(state: ^Inventory_Workflow_State) {
	if state == nil {
		return
	}
	for index in 0 ..< int(state.mark_count) {
		state.marks[index] = {}
	}
	for index in 0 ..< int(state.batch_count) {
		state.batch[index] = {}
	}
	for index in 0 ..< int(state.decision_count) {
		state.decisions[index] = {}
	}
	state.decision_count = 0
	state.mark_count = 0
	state.batch_count = 0
	state.pending_entry = {}
	state.command_handle = {}
	state.return_target = {}
	state.position = {}
	state.current_entry = {}
	state.model_generation = 0
	state.path_length = 0
	state.terminal_only = false
}

@(private)
inventory_workflow_reset_execution :: proc(state: ^Inventory_Workflow_State) {
	if state == nil do return
	for index in 0 ..< int(state.batch_count) do state.batch[index] = {}
	for index in 0 ..< int(state.decision_count) do state.decisions[index] = {}
	state.batch_count = 0
	state.decision_count = 0
	state.pending_entry = {}
	state.path_length = 0
}

@(private)
dispatch_buffer_inventory_list_input :: proc(
	commands: ^Command_Context,
	input: interaction.Input,
	constraints: display.Viewport_Constraints,
) -> (Interaction_Result, App_Failure) {
	if commands.prompt_workflow.mode == .Marked_Kill_Choice || commands.prompt_workflow.mode == .Marked_Save_Path {
		return dispatch_prompt(commands, nil, nil, {}, input, constraints)
	}
	if commands.prompt_workflow.mode != .None {
		return {}, App_Failure{stage = .Prompt}
	}
	descriptors, copied, copy_failure := editor_session.session_descriptors(
		commands.session_owner,
		commands.session_handle,
		commands.temporary_allocator,
	)
	if !copied do return {}, App_Failure{stage = .Session_Access, editor_session = copy_failure}
	defer editor_session.descriptor_batch_close(&descriptors)
	filtered: [editor_session.MAX_LIVE_BUFFERS]editor_session.Entry_Descriptor
	visible := inventory_workflow_visible_descriptors(
		&commands.inventory_workflow,
		descriptors.descriptors,
		filtered[:],
	)
	if prepared, prepare_failure := inventory_workflow_prepare(
		&commands.inventory_workflow,
		visible,
		constraints.height_rows,
	); !prepared {
		return {}, App_Failure{stage = .UI, ui = prepare_failure}
	}
	if map_failure := command_context_sync_list_map(commands, .Buffer_Inventory); map_failure.stage != .None {
		return {}, map_failure
	}
	metadata, resolution, resolved, resolution_failure := command_context_resolve_context_input(
		commands,
		input,
	)
	if !resolved {
		return {}, resolution_failure
	}
	if resolution.kind != .Command {
		return {}, {}
	}
	contextual_route, contextual_ok := command.contextual_route_decode(metadata.route)
	if contextual_ok &&
	   (contextual_route == .Component_Previous_Row || contextual_route == .Component_Next_Row) {
		delta := i32(1)
		if contextual_route == .Component_Previous_Row {
			delta = -1
		}
		changed, moved, move_failure := inventory_workflow_move(
			&commands.inventory_workflow,
			visible,
			delta,
		)
		if !moved do return {}, App_Failure{stage = .UI, ui = move_failure}
		return Interaction_Result{changed = changed}, {}
	}
	if contextual_route == .Component_Activate_Current {
			index := commands.inventory_workflow.position.current_item
		if index < 0 || index >= i32(len(visible)) {
				return {}, App_Failure{stage = .UI}
			}
			_, activated, activation_failure := editor_session.session_activate(
				commands.session_owner,
			visible[index].graph.entry,
			)
			if !activated {
				return {}, App_Failure{stage = .Session_Access, editor_session = activation_failure}
			}
			inventory_workflow_reset(&commands.inventory_workflow)
			command_context_deactivate_context_map(commands, .Completed)
			return Interaction_Result{changed = true}, {}
	}
	if contextual_route == .Component_Mark_Save {
		return command_context_mark_inventory(commands, visible, .Save)
	}
	if contextual_route == .Component_Mark_Kill {
		return command_context_mark_inventory(commands, visible, .Kill)
	}
	if contextual_route == .Component_Unmark {
		return command_context_mark_inventory(commands, visible, .Invalid)
	}
	if contextual_route == .Component_Execute {
		return command_context_begin_marked_execution(commands)
	}
	if contextual_route == .Component_Close || command_metadata_is_native(metadata, .Keyboard_Quit) {
		return command_context_leave_buffer_inventory(commands)
	}
	return {}, {}
}

@(private)
command_context_mark_inventory :: proc(
	commands: ^Command_Context,
	descriptors: []editor_session.Entry_Descriptor,
	mark: command.Buffer_Mark_Kind,
) -> (Interaction_Result, App_Failure) {
	marked, mark_failure := inventory_workflow_set_current_mark(
		&commands.inventory_workflow,
		descriptors,
		mark,
	)
	if !marked do return {}, App_Failure{stage = .UI, ui = mark_failure}
	return Interaction_Result{changed = true}, {}
}

@(private)
command_context_leave_buffer_inventory :: proc(
	commands: ^Command_Context,
) -> (Interaction_Result, App_Failure) {
	return_target := commands.inventory_workflow.return_target
	if return_target.kind != .Primary_View {
		return {}, App_Failure{stage = .Session_Access}
	}
	inventory_workflow_reset(&commands.inventory_workflow)
	command_context_end_prompt(commands)
	command_context_deactivate_context_map(commands, .Completed)
	_, activated, activation_failure := editor_session.session_activate(
		commands.session_owner,
		return_target.entry,
	)
	if !activated {
		return {}, App_Failure{stage = .Session_Access, editor_session = activation_failure}
	}
	return Interaction_Result{changed = true}, {}
}

@(private)
command_context_begin_marked_execution :: proc(
	commands: ^Command_Context,
) -> (Interaction_Result, App_Failure) {
	inventory_workflow_reset_execution(&commands.inventory_workflow)
	batch := inventory_workflow_snapshot_marks(&commands.inventory_workflow)
	if len(batch) == 0 {
		command_context_set_diagnostic(commands, "No marked buffers")
		return Interaction_Result{changed = true}, {}
	}
	command_context_marked_operation_progress(commands, .Running, 0, u64(commands.inventory_workflow.batch_count))
	return command_context_advance_marked_execution(commands)
}

@(private)
command_context_present_save_some_buffers :: proc(
	commands: ^Command_Context,
	constraints: display.Viewport_Constraints,
	command_handle: interaction.Command_Handle,
	save_all: bool,
) -> (Interaction_Result, App_Failure) {
	presented, present_failure := command_context_present_buffer_inventory(
		commands,
		constraints,
		command_handle,
	)
	if present_failure.stage != .None do return {}, present_failure
	descriptors, copied, copy_failure := editor_session.session_descriptors(
		commands.session_owner,
		commands.session_handle,
		commands.temporary_allocator,
	)
	if !copied do return {}, App_Failure{stage = .Session_Access, editor_session = copy_failure}
	defer editor_session.descriptor_batch_close(&descriptors)
	for descriptor in descriptors.descriptors {
		if !descriptor.modified || descriptor.association != .Document do continue
		if commands.inventory_workflow.mark_count >= editor_session.DEFAULT_INVENTORY_MARKS do break
		commands.inventory_workflow.marks[commands.inventory_workflow.mark_count] = {
			entry = descriptor.graph.entry,
			kind = .Save,
		}
		commands.inventory_workflow.mark_count += 1
	}
	if commands.inventory_workflow.mark_count == 0 {
		command_context_set_diagnostic(commands, "No modified file buffers")
		return Interaction_Result{changed = true}, {}
	}
	if !inventory_workflow_advance_generation(&commands.inventory_workflow) {
		return {}, App_Failure{stage = .UI, ui = {operation = .Prepare, code = .Generation_Limit}}
	}
	if save_all do return command_context_begin_marked_execution(commands)
	return presented, {}
}

@(private)
command_context_advance_marked_execution :: proc(
	commands: ^Command_Context,
) -> (Interaction_Result, App_Failure) {
	batch_total := u64(commands.inventory_workflow.batch_count)
	result, executed, execute_failure := command.buffer_session_execute_buffer_marks(
		command.Buffer_Marked_Execution_Context {
			buffer_session = command.Buffer_Session_Context {
				session = commands.session_owner,
				handle = commands.session_handle,
				command = commands.inventory_workflow.command_handle,
				configuration = commands.entry_configuration,
			},
			decisions = commands.inventory_workflow.decisions[:commands.inventory_workflow.decision_count],
		},
		commands.inventory_workflow.batch[:commands.inventory_workflow.batch_count],
	)
	if result.completed_saves > 0 {
		command_context_unmark_completed_saves(commands, result.completed_saves)
		if refresh_failure := command_context_refresh_buffer_inventory(commands); refresh_failure.stage != .None {
			return {}, refresh_failure
		}
		if result.outcome == .Decision_Required {
			_ = inventory_workflow_snapshot_marks(&commands.inventory_workflow)
		}
	}
	if !executed && result.outcome == .Failed {
		command_context_buffer_session_diagnostic(commands, execute_failure)
		command_context_marked_operation_progress(commands, .Failed, u64(result.completed_saves + result.completed_kills), batch_total)
		inventory_workflow_reset_execution(&commands.inventory_workflow)
		command_context_end_prompt(commands)
		return Interaction_Result{changed = true}, {}
	}
	switch result.outcome {
	case .Completed:
		usage, usage_ok, usage_failure := editor_session.session_usage(
			commands.session_owner,
			commands.session_handle,
		)
		if !usage_ok {
			return {}, App_Failure{stage = .Session_Access, editor_session = usage_failure}
		}
		command_context_end_prompt(commands)
		if usage.live_buffers == 0 {
			inventory_workflow_reset(&commands.inventory_workflow)
			target := startup_visible_target()
			_, _, presented, present_failure := editor_session.session_present_ui(
				commands.session_owner,
				commands.session_handle,
				target.ui,
			)
			if !presented {
				return {}, App_Failure{stage = .Session_Access, editor_session = present_failure}
			}
		} else {
			inventory_workflow_reset_execution(&commands.inventory_workflow)
			inventory_workflow_clear_marks(&commands.inventory_workflow)
			if refresh_failure := command_context_refresh_buffer_inventory(commands); refresh_failure.stage != .None {
				return {}, refresh_failure
			}
		}
		command_context_marked_operation_progress(commands, .Succeeded, batch_total, batch_total)
		return Interaction_Result{changed = true}, {}
	case .Decision_Required:
		commands.inventory_workflow.pending_entry = result.decision_entry
		mark, found := command_context_mark_for_entry(commands, result.decision_entry)
		if !found {
			return {}, App_Failure{stage = .Component_Access}
		}
		if mark == .Save {
			return command_context_begin_marked_save_path(commands)
		}
		return command_context_begin_marked_kill_choice(commands)
	case .Cancelled:
		inventory_workflow_reset_execution(&commands.inventory_workflow)
		command_context_end_prompt(commands)
		command_context_marked_operation_progress(commands, .Cancelled, u64(result.completed_saves + result.completed_kills), batch_total)
		return Interaction_Result{changed = true}, {}
	case .Failed:
		command_context_buffer_session_diagnostic(commands, execute_failure)
		command_context_marked_operation_progress(commands, .Failed, u64(result.completed_saves + result.completed_kills), batch_total)
		inventory_workflow_reset_execution(&commands.inventory_workflow)
		command_context_end_prompt(commands)
		return Interaction_Result{changed = true}, {}
	case .Invalid:
		return {}, App_Failure{stage = .Command_Dispatch}
	}
	unreachable()
}

@(private)
command_context_marked_operation_progress :: proc(
	commands: ^Command_Context,
	state: feedback.Progress_State,
	current: u64,
	total: u64,
) {
	if commands == nil do return
	progress_total := max(total, u64(1))
	progress_current := min(current, progress_total)
	actions: [1]feedback_workflow.Action_Definition
	action_count := 0
	if state == .Running {
		actions[0] = {id = 1, kind = .Cancel, command = "keyboard-quit"}
		action_count = 1
	}
	message := "Marked operations"
	if state == .Succeeded do message = "Marked operations complete"
	if state == .Cancelled do message = "Marked operations cancelled"
	if state == .Failed do message = "Marked operations failed"
	_, _ = command_context_publish_progress(commands, {
		state = state,
		measurement = .Determinate,
		current = progress_current,
		total = progress_total,
		phase = "buffers",
		message = message,
		actions = actions[:action_count],
	})
}

@(private)
command_context_refresh_buffer_inventory :: proc(commands: ^Command_Context) -> App_Failure {
	descriptors, copied, copy_failure := editor_session.session_descriptors(
		commands.session_owner,
		commands.session_handle,
	)
	if !copied {
		return App_Failure{stage = .Session_Access, editor_session = copy_failure}
	}
	defer editor_session.descriptor_batch_close(&descriptors)
	filtered: [editor_session.MAX_LIVE_BUFFERS]editor_session.Entry_Descriptor
	visible := inventory_workflow_visible_descriptors(
		&commands.inventory_workflow,
		descriptors.descriptors,
		filtered[:],
	)
	if len(visible) == 0 {
		if !inventory_workflow_advance_generation(&commands.inventory_workflow) {
			return App_Failure{stage = .UI, ui = {operation = .Prepare, code = .Generation_Limit}}
		}
		return {}
	}
	active := visible[0]
	commands.inventory_workflow.return_target = editor_session.Visible_Target {
		kind = .Primary_View,
		entry = active.graph.entry,
		primary_view = active.graph.primary_view,
	}
	viewport := commands.inventory_workflow.position.viewport_items
	if viewport == 0 do viewport = 1
	if prepared, prepare_failure := inventory_workflow_prepare(
		&commands.inventory_workflow,
		visible,
		viewport,
	); !prepared {
		return App_Failure{stage = .UI, ui = prepare_failure}
	}
	if !inventory_workflow_advance_generation(&commands.inventory_workflow) {
		return App_Failure{stage = .UI, ui = {operation = .Prepare, code = .Generation_Limit}}
	}
	return {}
}

@(private)
command_context_mark_for_entry :: proc(
	commands: ^Command_Context,
	entry: editor_session.Entry_Handle,
) -> (command.Buffer_Mark_Kind, bool) {
	for marked in commands.inventory_workflow.batch[:commands.inventory_workflow.batch_count] {
		if marked.entry == entry {
			return marked.kind, true
		}
	}
	return .Invalid, false
}

@(private)
command_context_unmark_completed_saves :: proc(commands: ^Command_Context, count: u32) {
	remaining := count
	for marked in commands.inventory_workflow.batch[:commands.inventory_workflow.batch_count] {
		if remaining == 0 {
			break
		}
		if marked.kind != .Save {
			continue
		}
		unmarked := inventory_workflow_unmark_entry(&commands.inventory_workflow, marked.entry)
		assert(unmarked)
		remaining -= 1
	}
}

@(private)
command_context_begin_marked_kill_choice :: proc(
	commands: ^Command_Context,
) -> (Interaction_Result, App_Failure) {
	if commands.prompt_workflow.prompt.state != nil {
		_, _ = interaction.prompt_close(&commands.prompt_workflow.prompt)
	}
	choices := prompt_save_discard_cancel_choices()
	prompt_ok, prompt_failure := interaction.prompt_init(
		&commands.prompt_workflow.prompt,
		interaction.Prompt_Config {
			kind = .Fixed_Choice,
			choices = choices[:],
			allocator = commands.persistent_allocator,
		},
	)
	if !prompt_ok {
		return {}, App_Failure{stage = .Prompt, prompt_failure = prompt_failure}
	}
	if !prompt_workflow_begin_projection(&commands.prompt_workflow, .Marked_Kill_Choice) {
		_, _ = interaction.prompt_close(&commands.prompt_workflow.prompt)
		return {}, App_Failure{stage = .UI, ui = {operation = .Prepare, code = .Generation_Limit}}
	}
	if map_failure := command_context_activate_prompt_map(commands, .Marked_Kill_Choice); map_failure.stage != .None {
		_, _ = interaction.prompt_close(&commands.prompt_workflow.prompt)
		commands.prompt_workflow.mode = .None
		return {}, map_failure
	}
	return Interaction_Result{changed = true}, {}
}

@(private)
command_context_begin_marked_save_path :: proc(
	commands: ^Command_Context,
) -> (Interaction_Result, App_Failure) {
	if commands.prompt_workflow.prompt.state != nil {
		_, _ = interaction.prompt_close(&commands.prompt_workflow.prompt)
	}
	prompt_ok, prompt_failure := interaction.prompt_init(
		&commands.prompt_workflow.prompt,
		interaction.Prompt_Config {
			kind = .Text_Entry,
			text_bytes_limit = document.MAX_PATH_BYTES,
			allocator = commands.persistent_allocator,
		},
	)
	if !prompt_ok {
		return {}, App_Failure{stage = .Prompt, prompt_failure = prompt_failure}
	}
	if !prompt_workflow_begin_projection(&commands.prompt_workflow, .Marked_Save_Path) {
		_, _ = interaction.prompt_close(&commands.prompt_workflow.prompt)
		return {}, App_Failure{stage = .UI, ui = {operation = .Prepare, code = .Generation_Limit}}
	}
	if map_failure := command_context_activate_prompt_map(commands, .Marked_Save_Path); map_failure.stage != .None {
		_, _ = interaction.prompt_close(&commands.prompt_workflow.prompt)
		commands.prompt_workflow.mode = .None
		return {}, map_failure
	}
	return Interaction_Result{changed = true}, {}
}

@(private)
dispatch_marked_inventory_prompt :: proc(
	commands: ^Command_Context,
	input: interaction.Input,
) -> (Interaction_Result, App_Failure) {
	metadata, resolution, resolved, resolve_failure := command_context_resolve_prompt_input(commands, input)
	if !resolved {
		return {}, resolve_failure
	}
	if resolution.kind != .Command {
		return {}, {}
	}
	if command_metadata_is_cancel(metadata) {
		_, cancel_failure := interaction.prompt_cancel(&commands.prompt_workflow.prompt)
		if cancel_failure.code != .None {
			return {}, App_Failure{stage = .Prompt, prompt_failure = cancel_failure}
		}
		batch_total := u64(commands.inventory_workflow.batch_count)
		inventory_workflow_reset_execution(&commands.inventory_workflow)
		command_context_deactivate_prompt_map(commands, .Cancelled)
		command_context_end_prompt(commands)
		command_context_marked_operation_progress(commands, .Cancelled, 0, batch_total)
		return Interaction_Result{changed = true}, {}
	}
	if commands.prompt_workflow.mode == .Marked_Kill_Choice {
		choice := command_metadata_prompt_choice(metadata)
		decision := command.Marked_Kill_Decision.None
		switch choice {
		case 1:
			decision = .Save
		case 2:
			decision = .Discard
		case 3:
			decision = .Cancel
		case:
			return {}, {}
		}
		_, choice_failure := interaction.prompt_choice_accept(&commands.prompt_workflow.prompt, choice)
		if choice_failure.code != .None {
			return {}, App_Failure{stage = .Prompt, prompt_failure = choice_failure}
		}
		_, _ = interaction.prompt_close(&commands.prompt_workflow.prompt)
		command_context_deactivate_prompt_map(commands, .Completed)
		commands.prompt_workflow.mode = .None
		if decision == .Cancel {
			batch_total := u64(commands.inventory_workflow.batch_count)
			inventory_workflow_reset_execution(&commands.inventory_workflow)
			command_context_marked_operation_progress(commands, .Cancelled, 0, batch_total)
			return Interaction_Result{changed = true}, {}
		}
		if decision == .Save {
			access, access_ok, access_failure := editor_session.session_entry_access(
				commands.session_owner,
				commands.inventory_workflow.pending_entry,
			)
			borrow, borrowed, borrow_failure := editor_session.entry_access_borrow(access)
			if !access_ok || !borrowed {
				failure := access_failure
				if access_ok {
					failure = borrow_failure
				}
				return {}, App_Failure{stage = .Session_Access, editor_session = failure}
			}
			if !borrow.has_document {
				return command_context_begin_marked_save_path(commands)
			}
		}
		return command_context_resume_marked_with_decision(commands, decision, "", decision == .Save)
	}
	if commands.prompt_workflow.mode != .Marked_Save_Path {
		return {}, App_Failure{stage = .Prompt}
	}
	if command_metadata_is_contextual(metadata, .Prompt_Delete_Previous) {
		transition, prompt_failure := interaction.prompt_text_delete_previous(&commands.prompt_workflow.prompt)
		if prompt_failure.code != .None {
			return {}, App_Failure{stage = .Prompt, prompt_failure = prompt_failure}
		}
		commands.prompt_workflow.rejected = false
		return Interaction_Result{changed = transition == .Changed}, {}
	}
	if command_metadata_is_contextual(metadata, .Prompt_Accept) {
		_, accept_failure := interaction.prompt_text_accept(&commands.prompt_workflow.prompt)
		if accept_failure.code != .None {
			commands.prompt_workflow.rejected = true
			return Interaction_Result{changed = true}, {}
		}
		view, viewed, view_failure := interaction.prompt_view(&commands.prompt_workflow.prompt)
		if !viewed {
			return {}, App_Failure{stage = .Prompt, prompt_failure = view_failure}
		}
		path_storage: [document.MAX_PATH_BYTES]u8
		path, path_ok := command_context_expand_home_path(commands, view.text, path_storage[:])
		if !path_ok {
			_, _ = interaction.prompt_close(&commands.prompt_workflow.prompt)
			command_context_deactivate_prompt_map(commands, .Completed)
			commands.prompt_workflow.mode = .None
			inventory_workflow_reset_execution(&commands.inventory_workflow)
			command_context_set_diagnostic(commands, "Home-relative path exceeds the path limit")
			return Interaction_Result{changed = true}, {}
		}
		commands.inventory_workflow.path_length = copy(commands.inventory_workflow.path[:], transmute([]u8)path)
		_, _ = interaction.prompt_close(&commands.prompt_workflow.prompt)
		command_context_deactivate_prompt_map(commands, .Completed)
		commands.prompt_workflow.mode = .None
		return command_context_resume_marked_with_decision(
			commands,
			.Save,
			string(commands.inventory_workflow.path[:commands.inventory_workflow.path_length]),
			true,
		)
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
	return {}, {}
}

@(private)
command_context_resume_marked_with_decision :: proc(
	commands: ^Command_Context,
	kind: command.Marked_Kill_Decision,
	path: string,
	ephemeral: bool,
) -> (Interaction_Result, App_Failure) {
	if commands.inventory_workflow.decision_count >= editor_session.MAX_INVENTORY_MARKS {
		return {}, App_Failure{stage = .Command_Dispatch}
	}
	index := commands.inventory_workflow.decision_count
	commands.inventory_workflow.decisions[index] = command.Marked_Entry_Decision {
		entry = commands.inventory_workflow.pending_entry,
		kind = kind,
		path = path,
	}
	commands.inventory_workflow.decision_count += 1
	result, failure := command_context_advance_marked_execution(commands)
	if ephemeral && commands.inventory_workflow.decision_count > index {
		for move in index ..< commands.inventory_workflow.decision_count - 1 {
			commands.inventory_workflow.decisions[move] = commands.inventory_workflow.decisions[move + 1]
		}
		commands.inventory_workflow.decision_count -= 1
		commands.inventory_workflow.decisions[commands.inventory_workflow.decision_count] = {}
	}
	commands.inventory_workflow.path_length = 0
	commands.inventory_workflow.pending_entry = {}
	return result, failure
}
