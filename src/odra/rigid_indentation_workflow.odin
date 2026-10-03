// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../command"
import "../display"
import "../editor"
import "../interaction"
import editor_view "../view"
import "base:runtime"

@(private)
RIGID_INDENTATION_MAP_ID :: interaction.Map_ID(3_031)

@(private)
Rigid_Indentation_State :: struct {
	active: bool,
	buffer: ^editor.Buffer,
	buffer_id: editor.Buffer_ID,
	start: editor.Anchor,
	end: editor.Anchor,
}

@(private)
rigid_indentation_active :: proc(commands: ^Command_Context) -> bool {
	return commands != nil && commands.rigid_indentation != nil && commands.rigid_indentation.active
}

@(private)
command_context_begin_rigid_indentation :: proc(
	commands: ^Command_Context,
	buffer: ^editor.Buffer,
	view_registry: ^editor_view.Registry,
	view: editor_view.View_Handle,
) -> (Interaction_Result, App_Failure) {
	if commands == nil || buffer == nil || view_registry == nil {
		return {}, App_Failure{stage = .Command_Dispatch}
	}
	if commands.rigid_indentation == nil {
		allocation_error: runtime.Allocator_Error
		commands.rigid_indentation, allocation_error = new(
			Rigid_Indentation_State,
			commands.persistent_allocator,
		)
		if allocation_error != nil do return {}, App_Failure{stage = .Command_Dispatch}
	}
	command_context_finish_rigid_indentation(commands, .Invalidated)
	target, target_ok, target_failure := command.semantic_target_resolve(
		command.Semantic_Target_Context {
			buffer = buffer,
			view_registry = view_registry,
			view = view,
			profile = display.terminal_unicode17_profile(),
		},
		.Active_Region,
	)
	if !target_ok {
		_ = target_failure
		command_context_set_diagnostic(commands, "Select a region before rigid indentation")
		return Interaction_Result{changed = true}, {}
	}
	start, start_ok, start_failure := editor.buffer_anchor_create(
		buffer,
		target.start,
		.Left,
		.Collapse,
	)
	if !start_ok do return {}, App_Failure{stage = .Command_Dispatch, editor = start_failure}
	end, end_ok, end_failure := editor.buffer_anchor_create(
		buffer,
		target.end,
		.Right,
		.Collapse,
	)
	if !end_ok {
		_, _ = editor.buffer_anchor_release(buffer, &start)
		return {}, App_Failure{stage = .Command_Dispatch, editor = end_failure}
	}
	state := commands.rigid_indentation
	state^ = {
		active = true,
		buffer = buffer,
		buffer_id = target.start.buffer_id,
		start = start,
		end = end,
	}
	if map_failure := command_context_sync_rigid_indentation_map(commands); map_failure.stage != .None {
		command_context_finish_rigid_indentation(commands, .Invalidated)
		return {}, map_failure
	}
	command_context_set_diagnostic(commands, "Rigid indentation: Left/Right by one column, Shift-Left/Shift-Right by one indentation width")
	return Interaction_Result{changed = true}, {}
}

@(private)
command_context_sync_rigid_indentation_map :: proc(commands: ^Command_Context) -> App_Failure {
	if !rigid_indentation_active(commands) do return App_Failure{stage = .Command_Resolution}
	bindings: [4]interaction.Binding_Definition
	count := 0
	command_context_add_prompt_binding(bindings[:], &count, rigid_indentation_special(.Right, {}), "rigid-indent-right")
	command_context_add_prompt_binding(bindings[:], &count, rigid_indentation_special(.Left, {}), "rigid-indent-left")
	command_context_add_prompt_binding(bindings[:], &count, rigid_indentation_special(.Right, {.Shift}), "rigid-indent-right-fast")
	command_context_add_prompt_binding(bindings[:], &count, rigid_indentation_special(.Left, {.Shift}), "rigid-indent-left-fast")
	return command_context_sync_context_map(
		commands,
		RIGID_INDENTATION_MAP_ID,
		interaction.Owner_ID(4_031),
		"rigid-indentation",
		.Fallthrough,
		"",
		bindings[:count],
		.Transient_Interaction,
	)
}

@(private)
rigid_indentation_special :: proc(
	kind: interaction.Logical_Key_Kind,
	modifiers: interaction.Modifiers,
) -> interaction.Key_Sequence {
	sequence: interaction.Key_Sequence
	sequence.stroke_count = 1
	sequence.strokes[0] = {kind = kind, modifiers = modifiers}
	return sequence
}

@(private)
command_context_rigid_indentation_range :: proc(
	commands: ^Command_Context,
	buffer: ^editor.Buffer,
) -> (command.Native_Explicit_Range, bool) {
	if !rigid_indentation_active(commands) || commands.rigid_indentation.buffer != buffer {
		return {}, false
	}
	state := commands.rigid_indentation
	start, start_ok, _ := editor.buffer_anchor_resolve(buffer, state.start)
	end, end_ok, _ := editor.buffer_anchor_resolve(buffer, state.end)
	if !start_ok || !end_ok || start.buffer_id != state.buffer_id || end.buffer_id != state.buffer_id {
		return {}, false
	}
	return {present = true, start = start, end = end}, true
}

@(private)
command_context_finish_rigid_indentation :: proc(
	commands: ^Command_Context,
	ending: interaction.Context_Map_End,
) {
	if commands == nil || commands.rigid_indentation == nil do return
	state := commands.rigid_indentation
	if state.buffer != nil {
		_, _ = editor.buffer_anchor_release(state.buffer, &state.start)
		_, _ = editor.buffer_anchor_release(state.buffer, &state.end)
	}
	state^ = {}
	if interaction.context_map_handle_is_valid(commands.interaction_workflow.map_handle) &&
	   commands.interaction_workflow.map_handle.identity.id == RIGID_INDENTATION_MAP_ID {
		command_context_deactivate_context_map(commands, ending)
	}
}
