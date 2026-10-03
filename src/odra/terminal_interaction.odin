// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "core:unicode/utf8"
import "core:strings"
import "../command"
import "../display"
import "../editor_session"
import "../interaction"
import "../terminal_session"

/* TERMINAL_CONTEXT_MAP_ID identifies the live terminal contextual keymap. */
TERMINAL_CONTEXT_MAP_ID :: interaction.Map_ID(3_017)
/* TERMINAL_CONTEXT_OWNER_ID identifies the live terminal keymap publisher. */
TERMINAL_CONTEXT_OWNER_ID :: interaction.Owner_ID(4_017)
/* TERMINAL_CONTEXT_BINDING_COUNT bounds the maintained live terminal bindings. */
TERMINAL_CONTEXT_BINDING_COUNT :: 20
/* TERMINAL_COPY_CONTEXT_MAP_ID identifies retained-text navigation. */
TERMINAL_COPY_CONTEXT_MAP_ID :: interaction.Map_ID(3_018)
/* TERMINAL_COPY_CONTEXT_OWNER_ID identifies the copy-mode map publisher. */
TERMINAL_COPY_CONTEXT_OWNER_ID :: interaction.Owner_ID(4_018)
/* TERMINAL_COPY_CONTEXT_BINDING_COUNT bounds retained-text bindings. */
TERMINAL_COPY_CONTEXT_BINDING_COUNT :: 12
/* MODAL_TERMINAL_CONTEXT_MAP_ID identifies modal live-terminal continuity. */
MODAL_TERMINAL_CONTEXT_MAP_ID :: interaction.Map_ID(3_019)
/* MODAL_TERMINAL_CONTEXT_OWNER_ID identifies the modal live-terminal publisher. */
MODAL_TERMINAL_CONTEXT_OWNER_ID :: interaction.Owner_ID(4_019)
/* MODAL_TERMINAL_CONTEXT_BINDING_COUNT bounds modal live-terminal bindings. */
MODAL_TERMINAL_CONTEXT_BINDING_COUNT :: TERMINAL_CONTEXT_BINDING_COUNT + 1
/* MODAL_TERMINAL_COPY_CONTEXT_MAP_ID identifies modal retained-text navigation. */
MODAL_TERMINAL_COPY_CONTEXT_MAP_ID :: interaction.Map_ID(3_020)
/* MODAL_TERMINAL_COPY_CONTEXT_OWNER_ID identifies the modal copy-mode publisher. */
MODAL_TERMINAL_COPY_CONTEXT_OWNER_ID :: interaction.Owner_ID(4_020)
/* MODAL_TERMINAL_COPY_CONTEXT_BINDING_COUNT bounds modal copy-mode bindings. */
MODAL_TERMINAL_COPY_CONTEXT_BINDING_COUNT :: TERMINAL_COPY_CONTEXT_BINDING_COUNT + 7
/* COMPILATION_CONTEXT_MAP_ID identifies completed compilation result interaction. */
COMPILATION_CONTEXT_MAP_ID :: interaction.Map_ID(3_021)
/* COMPILATION_CONTEXT_OWNER_ID identifies the compilation result keymap publisher. */
COMPILATION_CONTEXT_OWNER_ID :: interaction.Owner_ID(4_021)
/* COMPILATION_CONTEXT_BINDING_COUNT includes ordinary terminal interaction and rerun. */
COMPILATION_CONTEXT_BINDING_COUNT :: TERMINAL_CONTEXT_BINDING_COUNT + 1
/* MODAL_COMPILATION_CONTEXT_MAP_ID identifies modal compilation result interaction. */
MODAL_COMPILATION_CONTEXT_MAP_ID :: interaction.Map_ID(3_022)
/* MODAL_COMPILATION_CONTEXT_OWNER_ID identifies the modal compilation result publisher. */
MODAL_COMPILATION_CONTEXT_OWNER_ID :: interaction.Owner_ID(4_022)
/* MODAL_COMPILATION_CONTEXT_BINDING_COUNT includes modal terminal interaction and rerun. */
MODAL_COMPILATION_CONTEXT_BINDING_COUNT :: MODAL_TERMINAL_CONTEXT_BINDING_COUNT + 1

/* command_context_active_terminal reports whether the active entry is terminal-backed. */
command_context_active_terminal :: proc(commands: ^Command_Context) -> bool {
	_, active := command_context_active_terminal_state(commands)
	return active
}

@(private)
command_context_active_terminal_state :: proc(
	commands: ^Command_Context,
) -> (editor_session.Terminal_Buffer_State, bool) {
	if commands == nil || commands.session_owner == nil || commands.terminal_workflow == nil ||
	   !commands.terminal_workflow.initialized ||
	   !editor_session.entry_handle_is_valid(commands.current_entry) {
		return {}, false
	}
	state, inspected, _ := editor_session.session_terminal_buffer_state(
		commands.session_owner,
		commands.current_entry,
	)
	return state, inspected
}

@(private)
command_context_sync_terminal_map :: proc(commands: ^Command_Context) -> App_Failure {
	modal := command_context_modal_terminal_profile(commands)
	state, active := command_context_active_terminal_state(commands)
	if active {
		entry := terminal_workflow_entry_record(
			commands.terminal_workflow,
			terminal_session_ref(state.terminal),
		)
		if entry != nil && entry.copy_mode.active {
			if modal {
				bindings := modal_terminal_copy_context_bindings()
				return command_context_sync_context_map(
					commands,
					MODAL_TERMINAL_COPY_CONTEXT_MAP_ID,
					MODAL_TERMINAL_COPY_CONTEXT_OWNER_ID,
					"terminal-copy-mode-modal",
					.Fallthrough,
					"",
					bindings[:],
					.Component_Tool,
				)
			}
			bindings := terminal_copy_context_bindings()
			return command_context_sync_context_map(
				commands,
				TERMINAL_COPY_CONTEXT_MAP_ID,
				TERMINAL_COPY_CONTEXT_OWNER_ID,
				"terminal-copy-mode",
				.Fallthrough,
				"",
				bindings[:],
				.Component_Tool,
			)
		}
		if entry != nil && entry.one_shot_kind == .Compilation &&
		   (state.lifecycle == .Exited || state.lifecycle == .Failed) {
			if modal {
				bindings := modal_compilation_context_bindings()
				return command_context_sync_context_map(
					commands,
					MODAL_COMPILATION_CONTEXT_MAP_ID,
					MODAL_COMPILATION_CONTEXT_OWNER_ID,
					"compilation-results-modal",
					.Fallthrough,
					"",
					bindings[:],
					.Component_Tool,
				)
			}
			bindings := compilation_context_bindings()
			return command_context_sync_context_map(
				commands,
				COMPILATION_CONTEXT_MAP_ID,
				COMPILATION_CONTEXT_OWNER_ID,
				"compilation-results",
				.Fallthrough,
				"",
				bindings[:],
				.Component_Tool,
			)
		}
	}
	if modal {
		bindings := modal_terminal_context_bindings()
		return command_context_sync_context_map(
			commands,
			MODAL_TERMINAL_CONTEXT_MAP_ID,
			MODAL_TERMINAL_CONTEXT_OWNER_ID,
			"terminal-live-modal",
			.Fallthrough,
			"",
			bindings[:],
			.Component_Tool,
		)
	}
	bindings := terminal_context_bindings()
	return command_context_sync_context_map(
		commands,
		TERMINAL_CONTEXT_MAP_ID,
		TERMINAL_CONTEXT_OWNER_ID,
		"terminal-live",
		.Fallthrough,
		"",
		bindings[:],
		.Component_Tool,
	)
}

@(private)
command_context_modal_terminal_profile :: proc(commands: ^Command_Context) -> bool {
	if commands == nil || commands.profile_activation == nil do return false
	profile, _, selected := interaction.profile_activation_selection(commands.profile_activation)
	catalog, catalog_ok := interaction.profile_activation_catalog(commands.profile_activation)
	if !selected || !catalog_ok do return false
	for candidate in catalog.profiles {
		if candidate.identity == profile do return candidate.name == "modal"
	}
	return false
}

@(private)
modal_terminal_copy_context_bindings :: proc() -> [MODAL_TERMINAL_COPY_CONTEXT_BINDING_COUNT]interaction.Binding_Definition {
	bindings: [MODAL_TERMINAL_COPY_CONTEXT_BINDING_COUNT]interaction.Binding_Definition
	direct := terminal_copy_context_bindings()
	index := 0
	for binding in direct {
		bindings[index] = binding
		index += 1
	}
	modal_terminal_copy_context_add_binding(&bindings, &index, terminal_context_scalar('h', {}), "cursor-previous-grapheme")
	modal_terminal_copy_context_add_binding(&bindings, &index, terminal_context_scalar('j', {}), "cursor-next-line")
	modal_terminal_copy_context_add_binding(&bindings, &index, terminal_context_scalar('k', {}), "cursor-previous-line")
	modal_terminal_copy_context_add_binding(&bindings, &index, terminal_context_scalar('l', {}), "cursor-next-grapheme")
	modal_terminal_copy_context_add_binding(&bindings, &index, terminal_context_scalar('0', {}), "terminal-beginning-of-line")
	modal_terminal_copy_context_add_binding(&bindings, &index, terminal_context_scalar('$', {}), "terminal-end-of-line")
	modal_terminal_copy_context_add_binding(&bindings, &index, terminal_context_scalar('i', {}), "modal-enter-insert")
	assert(index == MODAL_TERMINAL_COPY_CONTEXT_BINDING_COUNT)
	return bindings
}

@(private)
modal_terminal_copy_context_add_binding :: proc(
	bindings: ^[MODAL_TERMINAL_COPY_CONTEXT_BINDING_COUNT]interaction.Binding_Definition,
	index: ^int,
	sequence: interaction.Key_Sequence,
	command_name: string,
) {
	assert(bindings != nil && index != nil && index^ < len(bindings))
	bindings[index^] = interaction.Binding_Definition {
		strokes = sequence.strokes,
		stroke_count = sequence.stroke_count,
		command_name = command_name,
	}
	index^ += 1
}

@(private)
terminal_copy_context_bindings :: proc() -> [TERMINAL_COPY_CONTEXT_BINDING_COUNT]interaction.Binding_Definition {
	bindings: [TERMINAL_COPY_CONTEXT_BINDING_COUNT]interaction.Binding_Definition
	index := 0
	terminal_copy_context_add_binding(&bindings, &index, terminal_context_special(.Enter), "terminal-copy-mode-done")
	terminal_copy_context_add_binding(&bindings, &index, terminal_context_special(.Left), "cursor-previous-grapheme")
	terminal_copy_context_add_binding(&bindings, &index, terminal_context_special(.Right), "cursor-next-grapheme")
	terminal_copy_context_add_binding(&bindings, &index, terminal_context_special(.Up), "cursor-previous-line")
	terminal_copy_context_add_binding(&bindings, &index, terminal_context_special(.Down), "cursor-next-line")
	terminal_copy_context_add_binding(&bindings, &index, terminal_context_special(.Home), "terminal-beginning-of-line")
	terminal_copy_context_add_binding(&bindings, &index, terminal_context_special(.End), "terminal-end-of-line")
	terminal_copy_context_add_binding(&bindings, &index, terminal_context_special(.Prior), "scroll-previous-page")
	terminal_copy_context_add_binding(&bindings, &index, terminal_context_special(.Next), "scroll-next-page")
	terminal_copy_context_add_binding(&bindings, &index, terminal_context_scalar(' ', {.Control}), "set-mark-command")
	terminal_copy_context_add_binding(&bindings, &index, terminal_context_scalar('w', {.Meta}), "copy-region")
	terminal_copy_context_add_binding(
		&bindings,
		&index,
		terminal_context_sequence({
			terminal_context_scalar_stroke('c', {.Control}),
			terminal_context_scalar_stroke('r', {.Control}),
		}),
		"terminal-reset-cursor-point",
	)
	assert(index == TERMINAL_COPY_CONTEXT_BINDING_COUNT)
	return bindings
}

@(private)
terminal_copy_context_add_binding :: proc(
	bindings: ^[TERMINAL_COPY_CONTEXT_BINDING_COUNT]interaction.Binding_Definition,
	index: ^int,
	sequence: interaction.Key_Sequence,
	command_name: string,
) {
	assert(bindings != nil && index != nil && index^ < len(bindings))
	bindings[index^] = interaction.Binding_Definition {
		strokes = sequence.strokes,
		stroke_count = sequence.stroke_count,
		command_name = command_name,
	}
	index^ += 1
}

@(private)
command_context_deactivate_terminal_map :: proc(commands: ^Command_Context) {
	if commands == nil ||
	   !interaction.context_map_handle_is_valid(commands.interaction_workflow.map_handle) {
		return
	}
	id := commands.interaction_workflow.map_handle.identity.id
	if id != TERMINAL_CONTEXT_MAP_ID && id != TERMINAL_COPY_CONTEXT_MAP_ID &&
	   id != MODAL_TERMINAL_CONTEXT_MAP_ID && id != MODAL_TERMINAL_COPY_CONTEXT_MAP_ID &&
	   id != COMPILATION_CONTEXT_MAP_ID && id != MODAL_COMPILATION_CONTEXT_MAP_ID {
		return
	}
	command_context_deactivate_context_map(commands, .Invalidated)
}

@(private)
compilation_context_bindings :: proc() -> [COMPILATION_CONTEXT_BINDING_COUNT]interaction.Binding_Definition {
	bindings: [COMPILATION_CONTEXT_BINDING_COUNT]interaction.Binding_Definition
	terminal := terminal_context_bindings()
	for binding, index in terminal do bindings[index] = binding
	bindings[TERMINAL_CONTEXT_BINDING_COUNT] = {
		strokes = terminal_context_scalar('g', {}).strokes,
		stroke_count = 1,
		command_name = "recompile",
	}
	return bindings
}

@(private)
modal_compilation_context_bindings :: proc() -> [MODAL_COMPILATION_CONTEXT_BINDING_COUNT]interaction.Binding_Definition {
	bindings: [MODAL_COMPILATION_CONTEXT_BINDING_COUNT]interaction.Binding_Definition
	terminal := modal_terminal_context_bindings()
	for binding, index in terminal do bindings[index] = binding
	bindings[MODAL_TERMINAL_CONTEXT_BINDING_COUNT] = {
		strokes = terminal_context_scalar('g', {}).strokes,
		stroke_count = 1,
		command_name = "recompile",
	}
	return bindings
}

@(private)
terminal_context_bindings :: proc() -> [TERMINAL_CONTEXT_BINDING_COUNT]interaction.Binding_Definition {
	bindings: [TERMINAL_CONTEXT_BINDING_COUNT]interaction.Binding_Definition
	index := 0
	terminal_context_add_binding(&bindings, &index, terminal_context_special(.Enter), "terminal-send-return")
	terminal_context_add_binding(&bindings, &index, terminal_context_special(.Tab), "terminal-send-tab")
	terminal_context_add_binding(&bindings, &index, terminal_context_special(.Backspace), "terminal-send-backspace")
	terminal_context_add_binding(&bindings, &index, terminal_context_special(.Delete), "terminal-send-delete")
	terminal_context_add_binding(&bindings, &index, terminal_context_special(.Left), "terminal-send-left")
	terminal_context_add_binding(&bindings, &index, terminal_context_special(.Right), "terminal-send-right")
	terminal_context_add_binding(&bindings, &index, terminal_context_special(.Up), "terminal-send-up")
	terminal_context_add_binding(&bindings, &index, terminal_context_special(.Down), "terminal-send-down")
	terminal_context_add_binding(&bindings, &index, terminal_context_special(.Prior), "terminal-send-prior")
	terminal_context_add_binding(&bindings, &index, terminal_context_special(.Next), "terminal-send-next")
	terminal_context_add_binding(&bindings, &index, terminal_context_scalar('y', {.Control}), "terminal-yank")
	terminal_context_add_binding(&bindings, &index, terminal_context_scalar('y', {.Meta}), "terminal-yank-pop")
	terminal_context_add_binding(&bindings, &index, terminal_context_scalar('l', {.Control}), "terminal-clear")
	terminal_context_add_binding(&bindings, &index, terminal_context_scalar('q', {.Control}), "terminal-send-next-key")
	terminal_context_add_binding(
		&bindings,
		&index,
		terminal_context_sequence({
			terminal_context_scalar_stroke('c', {.Control}),
			terminal_context_scalar_stroke('t', {.Control}),
		}),
		"terminal-copy-mode",
	)
	terminal_context_add_binding(
		&bindings,
		&index,
		terminal_context_sequence({
			terminal_context_scalar_stroke('c', {.Control}),
			terminal_context_scalar_stroke('n', {.Control}),
		}),
		"terminal-next-prompt",
	)
	terminal_context_add_binding(
		&bindings,
		&index,
		terminal_context_sequence({
			terminal_context_scalar_stroke('c', {.Control}),
			terminal_context_scalar_stroke('p', {.Control}),
		}),
		"terminal-previous-prompt",
	)
	terminal_context_add_binding(
		&bindings,
		&index,
		terminal_context_sequence({
			terminal_context_scalar_stroke('c', {.Control}),
			terminal_context_scalar_stroke('l', {.Control}),
		}),
		"terminal-clear-scrollback",
	)
	terminal_context_add_binding(
		&bindings,
		&index,
		terminal_context_sequence({
			terminal_context_scalar_stroke('c', {.Control}),
			terminal_context_scalar_stroke('o', {}),
			terminal_context_scalar_stroke('T', {}),
		}),
		"terminal-open-project",
	)
	terminal_context_add_binding(
		&bindings,
		&index,
		terminal_context_sequence({
			terminal_context_scalar_stroke('c', {.Control}),
			interaction.Key_Stroke{kind = .Tab},
			terminal_context_scalar_stroke('t', {}),
		}),
		"terminal-open-here",
	)
	assert(index == TERMINAL_CONTEXT_BINDING_COUNT)
	return bindings
}

@(private)
modal_terminal_context_bindings :: proc() -> [MODAL_TERMINAL_CONTEXT_BINDING_COUNT]interaction.Binding_Definition {
	bindings: [MODAL_TERMINAL_CONTEXT_BINDING_COUNT]interaction.Binding_Definition
	direct := terminal_context_bindings()
	index := 0
	for binding in direct {
		bindings[index] = binding
		index += 1
	}
	modal_terminal_context_add_binding(
		&bindings,
		&index,
		terminal_context_sequence({
			terminal_context_scalar_stroke('\\', {.Control}),
			terminal_context_scalar_stroke('n', {.Control}),
		}),
		"terminal-copy-mode",
	)
	assert(index == MODAL_TERMINAL_CONTEXT_BINDING_COUNT)
	return bindings
}

@(private)
modal_terminal_context_add_binding :: proc(
	bindings: ^[MODAL_TERMINAL_CONTEXT_BINDING_COUNT]interaction.Binding_Definition,
	index: ^int,
	sequence: interaction.Key_Sequence,
	command_name: string,
) {
	assert(bindings != nil && index != nil && index^ < len(bindings))
	bindings[index^] = interaction.Binding_Definition {
		strokes = sequence.strokes,
		stroke_count = sequence.stroke_count,
		command_name = command_name,
	}
	index^ += 1
}

@(private)
terminal_context_add_binding :: proc(
	bindings: ^[TERMINAL_CONTEXT_BINDING_COUNT]interaction.Binding_Definition,
	index: ^int,
	sequence: interaction.Key_Sequence,
	command_name: string,
) {
	assert(bindings != nil && index != nil && index^ < len(bindings))
	bindings[index^] = interaction.Binding_Definition {
		strokes = sequence.strokes,
		stroke_count = sequence.stroke_count,
		command_name = command_name,
	}
	index^ += 1
}

@(private)
terminal_context_special :: proc(kind: interaction.Logical_Key_Kind) -> interaction.Key_Sequence {
	return terminal_context_sequence({interaction.Key_Stroke{kind = kind}})
}

@(private)
terminal_context_scalar :: proc(value: rune, modifiers: interaction.Modifiers) -> interaction.Key_Sequence {
	return terminal_context_sequence({terminal_context_scalar_stroke(value, modifiers)})
}

@(private)
terminal_context_scalar_stroke :: proc(
	value: rune,
	modifiers: interaction.Modifiers,
) -> interaction.Key_Stroke {
	return {kind = .Unicode_Scalar, scalar = value, modifiers = modifiers}
}

@(private)
terminal_context_sequence :: proc(strokes: []interaction.Key_Stroke) -> interaction.Key_Sequence {
	sequence: interaction.Key_Sequence
	assert(len(strokes) > 0 && len(strokes) <= len(sequence.strokes))
	sequence.stroke_count = u8(copy(sequence.strokes[:], strokes))
	return sequence
}

@(private)
command_context_route_terminal_input :: proc(
	commands: ^Command_Context,
	input: interaction.Input,
) -> (
	resolution: interaction.Resolution,
	handled: bool,
	result: Interaction_Result,
	failure: App_Failure,
) {
	state, active := command_context_active_terminal_state(commands)
	if !active do return {}, false, {}, App_Failure{stage = .Session_Access}
	ref := terminal_session_ref(state.terminal)
	_ = terminal_workflow_note_focus(commands.terminal_workflow, ref)
	entry := terminal_workflow_entry_record(commands.terminal_workflow, ref)
	copy_active := entry != nil && entry.copy_mode.active
	prior_context := commands.context_pending
	had_base_pending := commands.pending.stroke_count > 0
	resolved: bool
	resolve_failure: App_Failure
	_, resolution, resolved, resolve_failure = command_context_resolve_context_input(commands, input)
	if !resolved do return resolution, false, {}, resolve_failure
	metadata: interaction.Command_Metadata
	metadata_ok := false
	if resolution.kind == .Command {
		metadata, metadata_ok, _ = interaction.command_metadata(commands.registry, resolution.command)
	}
	if metadata_ok && terminal_interaction_is_protected(metadata) {
		return resolution, false, {}, {}
	}
	if copy_active {
		if resolution.kind == .Unbound {
			commands.context_pending = {}
			commands.pending = {}
			return {}, true, {}, {}
		}
		return resolution, false, {}, {}
	}
	if commands.terminal_workflow.literal_next == ref {
		commands.terminal_workflow.literal_next = {}
		commands.context_pending = {}
		commands.pending = {}
		result = terminal_interaction_send(commands, ref, input, .Literal_Next)
		return {}, true, result, {}
	}
	if metadata_ok {
		route, route_ok := command.native_route_decode(metadata.route)
		if route_ok && command.native_route_is_terminal(route) {
			return resolution, false, {}, {}
		}
	}
	if prior_context.stroke_count > 0 {
		for index in 0 ..< int(prior_context.stroke_count) {
			result = terminal_interaction_send(
				commands,
				ref,
				{kind = .Key, stroke = prior_context.strokes[index]},
				.Ordinary,
			)
		}
		result = terminal_interaction_send(commands, ref, input, .Ordinary)
		commands.pending = {}
		return {}, true, result, {}
	}
	if resolution.kind == .Pending {
		return resolution, false, {}, {}
	}
	if metadata_ok && had_base_pending {
		return resolution, false, {}, {}
	}
	result = terminal_interaction_send(commands, ref, input, .Ordinary)
	return {}, true, result, {}
}

@(private)
command_context_dispatch_terminal_copy_command :: proc(
	commands: ^Command_Context,
	route: command.Native_Route,
	command_handle: interaction.Command_Handle,
) -> (result: Interaction_Result, handled: bool, failure: App_Failure) {
	state, active := command_context_active_terminal_state(commands)
	if !active do return {}, false, {}
	ref := terminal_session_ref(state.terminal)
	entry := terminal_workflow_entry_record(commands.terminal_workflow, ref)
	if entry == nil || !entry.copy_mode.active do return {}, false, {}
	#partial switch route {
	case .Keyboard_Quit:
		transition, cancelled, _ := terminal_session.registry_copy_mode_cancel(
			&commands.terminal_workflow.registry, ref, entry.copy_mode,
		)
		if !cancelled {
			command_context_set_diagnostic(commands, "Terminal copy mode is unavailable")
			return {changed = true}, true, {}
		}
		command_context_apply_terminal_copy_transition(commands, ref, entry, transition)
		message := "Terminal selection cancelled"
		if transition.completed do message = "Terminal copy mode ended"
		command_context_set_diagnostic(commands, message)
		return {changed = true}, true, {}
	case .Cursor_Previous_Grapheme:
		return command_context_move_terminal_copy(commands, ref, entry, .Previous_Column)
	case .Cursor_Next_Grapheme:
		return command_context_move_terminal_copy(commands, ref, entry, .Next_Column)
	case .Cursor_Previous_Line:
		return command_context_move_terminal_copy(commands, ref, entry, .Previous_Row)
	case .Cursor_Next_Line:
		return command_context_move_terminal_copy(commands, ref, entry, .Next_Row)
	case .Scroll_Previous_Page:
		return command_context_move_terminal_copy(commands, ref, entry, .Previous_Page)
	case .Scroll_Next_Page:
		return command_context_move_terminal_copy(commands, ref, entry, .Next_Page)
	case .Set_Mark:
		transition, marked, _ := terminal_session.registry_copy_mode_set_mark(
			&commands.terminal_workflow.registry, ref, entry.copy_mode,
		)
		if marked {
			entry.copy_mode = transition.state
			command_context_set_diagnostic(commands, "Terminal mark set")
		} else {
			command_context_set_diagnostic(commands, "Terminal mark is unavailable")
		}
		return {changed = true}, true, {}
	case .Copy_Region:
		return command_context_copy_terminal_selection(commands, ref, entry, command_handle), true, {}
	case .Terminal_Copy_Mode_Done:
		transition, completed, _ := terminal_session.registry_copy_mode_done(
			&commands.terminal_workflow.registry, ref, entry.copy_mode,
		)
		if completed {
			command_context_apply_terminal_copy_transition(commands, ref, entry, transition)
			command_context_set_diagnostic(commands, "Terminal copy mode ended")
		} else {
			command_context_set_diagnostic(commands, "Terminal copy mode is unavailable")
		}
		return {changed = true}, true, {}
	case .Modal_Enter_Insert:
		transition, completed, _ := terminal_session.registry_copy_mode_done(
			&commands.terminal_workflow.registry, ref, entry.copy_mode,
		)
		if !completed {
			command_context_set_diagnostic(commands, "Terminal copy mode is unavailable")
			return {changed = true}, true, {}
		}
		modal_result, modal_failure := command_context_transition_modal_state(commands, "Insert")
		if modal_failure.stage != .None do return modal_result, true, modal_failure
		_, modal_state, selected := interaction.profile_activation_selection(commands.profile_activation)
		if !selected || modal_state.name != "Insert" {
			command_context_set_diagnostic(commands, "Terminal copy mode Insert return was rejected")
			return {changed = true}, true, {}
		}
		command_context_apply_terminal_copy_transition(commands, ref, entry, transition)
		command_context_set_diagnostic(commands, "Terminal copy mode ended in Insert")
		return {changed = true}, true, {}
	case .Terminal_Beginning_Of_Line:
		return command_context_move_terminal_copy(commands, ref, entry, .Line_Start)
	case .Terminal_End_Of_Line:
		return command_context_move_terminal_copy(commands, ref, entry, .Line_End)
	case .Terminal_Reset_Cursor_Point:
		reset, reset_ok, _ := terminal_session.registry_copy_mode_enter(
			&commands.terminal_workflow.registry, ref,
		)
		if reset_ok {
			reset.state.mark_present = entry.copy_mode.mark_present
			reset.state.selection_active = entry.copy_mode.selection_active
			reset.state.mark_row = entry.copy_mode.mark_row
			reset.state.mark_column = entry.copy_mode.mark_column
			reset.state.follow_tail_on_entry = entry.copy_mode.follow_tail_on_entry
			entry.copy_mode = reset.state
			command_context_scroll_terminal_copy(commands, ref, entry.copy_mode)
			command_context_set_diagnostic(commands, "Terminal copy point reset")
		} else {
			command_context_set_diagnostic(commands, "Terminal copy point is unavailable")
		}
		return {changed = true}, true, {}
	case .Terminal_Send_Return, .Terminal_Send_Tab, .Terminal_Send_Escape,
	     .Terminal_Send_Backspace, .Terminal_Send_Delete, .Terminal_Send_Up,
	     .Terminal_Send_Down, .Terminal_Send_Left, .Terminal_Send_Right,
	     .Terminal_Send_Prior, .Terminal_Send_Next, .Terminal_Send_Space,
	     .Terminal_Undo, .Terminal_Yank, .Terminal_Yank_Pop, .Terminal_Clear:
		command_context_set_diagnostic(commands, "Exit terminal copy mode before sending input")
		return {changed = true}, true, {}
	case .Insert_Text, .Insert_Line_Break, .Insert_Indentation,
	     .Delete_Previous_Grapheme, .Delete_Next_Grapheme, .Delete_Region,
	     .Kill_Region, .Undo, .Redo, .Yank, .Yank_Pop:
		command_context_set_diagnostic(commands, "Terminal copy mode does not edit terminal content")
		return {changed = true}, true, {}
	case:
	}
	return {}, false, {}
}

@(private)
command_context_move_terminal_copy :: proc(
	commands: ^Command_Context,
	ref: terminal_session.Session_Ref,
	entry: ^Terminal_Workflow_Entry,
	movement: terminal_session.Copy_Movement,
) -> (Interaction_Result, bool, App_Failure) {
	transition, moved, _ := terminal_session.registry_copy_mode_move(
		&commands.terminal_workflow.registry, ref, entry.copy_mode, movement,
	)
	if !moved {
		command_context_set_diagnostic(commands, "Terminal copy movement is unavailable")
		return {changed = true}, true, {}
	}
	entry.copy_mode = transition.state
	command_context_scroll_terminal_copy(commands, ref, entry.copy_mode)
	return {changed = transition.changed}, true, {}
}

@(private)
command_context_scroll_terminal_copy :: proc(
	commands: ^Command_Context,
	ref: terminal_session.Session_Ref,
	copy_state: terminal_session.Copy_Mode_State,
) {
	if copy_state.viewport_top_row > u64(max(i64)) do return
	_, _, _ = terminal_session.registry_scroll_viewport(
		&commands.terminal_workflow.registry,
		ref,
		.Row,
		i64(copy_state.viewport_top_row),
	)
}

@(private)
command_context_apply_terminal_copy_transition :: proc(
	commands: ^Command_Context,
	ref: terminal_session.Session_Ref,
	entry: ^Terminal_Workflow_Entry,
	transition: terminal_session.Copy_Mode_Transition,
) {
	if transition.completed {
		entry.copy_mode = {}
		if transition.resume_follow_tail {
			_, _, _ = terminal_session.registry_scroll_viewport(
				&commands.terminal_workflow.registry, ref, .Bottom, 0,
			)
		}
		return
	}
	entry.copy_mode = transition.state
	command_context_scroll_terminal_copy(commands, ref, entry.copy_mode)
}

@(private)
command_context_copy_terminal_selection :: proc(
	commands: ^Command_Context,
	ref: terminal_session.Session_Ref,
	entry: ^Terminal_Workflow_Entry,
	command_handle: interaction.Command_Handle,
) -> Interaction_Result {
	text, allocation_error := make(
		[]u8, int(terminal_session.MAX_COPIED_TEXT_BYTES), commands.temporary_allocator,
	)
	if allocation_error != nil {
		command_context_set_diagnostic(commands, "Terminal copy allocation failed")
		return {changed = true}
	}
	defer delete(text, commands.temporary_allocator)
	snapshot, copied, copy_failure := terminal_session.registry_copy_mode_copy_selection(
		&commands.terminal_workflow.registry, ref, entry.copy_mode, text,
	)
	if !copied {
		message := "No active terminal selection"
		if copy_failure.code == .Output_Limit do message = "Terminal selection exceeds the copy limit"
		command_context_set_diagnostic(commands, message)
		return {changed = true}
	}
	transfer, retained, _ := command.terminal_text_retain(
		commands.kill_ring,
		command_handle,
		string(text[:int(snapshot.copied_bytes)]),
		terminal_session.MAX_COPIED_TEXT_BYTES,
	)
	if !retained {
		command_context_set_diagnostic(commands, "Terminal selection could not be retained")
		return {changed = true}
	}
	command_context_set_diagnostic(commands, "Terminal text copied")
	clipboard := clipboard_workflow_export(
		&commands.clipboard_workflow,
		commands.kill_ring,
		command_handle,
		transfer,
		commands.temporary_allocator,
	)
	if clipboard.diagnostic_length > 0 {
		command_context_set_diagnostic(
			commands,
			string(clipboard.diagnostic[:clipboard.diagnostic_length]),
		)
	}
	return {changed = true}
}

@(private)
command_context_move_terminal_prompt :: proc(
	commands: ^Command_Context,
	ref: terminal_session.Session_Ref,
	forward: bool,
) -> (Interaction_Result, App_Failure) {
	entry := terminal_workflow_entry_record(commands.terminal_workflow, ref)
	if entry == nil {
		command_context_set_diagnostic(commands, "Terminal prompt navigation is unavailable")
		return {changed = true}, {}
	}
	movement := terminal_session.Prompt_Movement.Previous
	if forward do movement = .Next
	prompt, moved, _ := terminal_session.registry_move_prompt(
		&commands.terminal_workflow.registry,
		ref,
		entry.prompt_sequence,
		movement,
	)
	if !moved {
		command_context_set_diagnostic(commands, "No retained prompt in that direction")
		return {changed = true}, {}
	}
	_, scrolled, _ := terminal_session.registry_scroll_viewport(
		&commands.terminal_workflow.registry,
		ref,
		.Row,
		i64(prompt.row),
	)
	if !scrolled {
		command_context_set_diagnostic(commands, "Terminal prompt is no longer retained")
		return {changed = true}, {}
	}
	entry.prompt_sequence = prompt.sequence
	_, _, _ = terminal_workflow_refresh(commands.terminal_workflow, commands.session_owner, ref)
	command_context_set_diagnostic(commands, "Terminal prompt selected")
	return {changed = true}, {}
}

@(private)
terminal_interaction_is_protected :: proc(metadata: interaction.Command_Metadata) -> bool {
	return command_metadata_is_cancel(metadata) ||
	       command_metadata_is_native(metadata, .Execute_Extended_Command)
}

@(private)
terminal_interaction_send :: proc(
	commands: ^Command_Context,
	ref: terminal_session.Session_Ref,
	input: interaction.Input,
	source: terminal_session.Input_Source,
) -> Interaction_Result {
	terminal_workflow_clear_yank(commands.terminal_workflow, ref)
	character_storage: [4]u8
	request, converted := terminal_interaction_input_request(input, source, character_storage[:])
	if !converted {
		command_context_set_diagnostic(commands, "Terminal input is unsupported")
		return {changed = true}
	}
	_, sent, send_failure := terminal_session.registry_send_input(
		&commands.terminal_workflow.registry,
		ref,
		request,
	)
	if !sent {
		message := "Terminal input is unavailable"
		if send_failure.code == .Input_Limit do message = "Terminal input queue is full"
		command_context_set_diagnostic(commands, message)
		return {changed = true}
	}
	return {}
}

@(private)
terminal_interaction_input_request :: proc(
	input: interaction.Input,
	source: terminal_session.Input_Source,
	character_storage: []u8,
) -> (request: terminal_session.Input_Request, ok: bool) {
	request = {source = source, action = .Press, repeat_count = 1}
	if input.kind == .Text_Commit {
		request.kind = .Text
		request.text = input.text
		return request, len(input.text) > 0
	}
	if input.kind != .Key do return {}, false
	request.kind = .Key
	request.modifiers = terminal_interaction_modifiers(input.stroke.modifiers)
	if input.stroke.kind == .Unicode_Scalar {
		encoded, count := utf8.encode_rune(input.stroke.scalar)
		if count <= 0 || count > len(character_storage) do return {}, false
		copy(character_storage[:count], encoded[:count])
		request.key = .Character
		request.text = string(character_storage[:count])
		return request, true
	}
	switch input.stroke.kind {
	case .Left:      request.key = .Left
	case .Right:     request.key = .Right
	case .Up:        request.key = .Up
	case .Down:      request.key = .Down
	case .Home:      request.key = .Home
	case .End:       request.key = .End
	case .Backspace: request.key = .Backspace
	case .Delete:    request.key = .Delete
	case .Enter:     request.key = .Enter
	case .Tab:       request.key = .Tab
	case .Prior:     request.key = .Prior
	case .Next:      request.key = .Next
	case .Escape:    request.key = .Escape
	case .Unicode_Scalar, .Insert, .F4, .Invalid:
		return {}, false
	}
	return request, true
}

@(private)
terminal_interaction_modifiers :: proc(value: interaction.Modifiers) -> terminal_session.Input_Modifiers {
	result: terminal_session.Input_Modifiers
	if .Control in value do result += {.Control}
	if .Meta in value || .Alt in value do result += {.Alt}
	if .Super in value do result += {.Super}
	return result
}

@(private)
command_context_dispatch_terminal_route :: proc(
	commands: ^Command_Context,
	route: command.Native_Route,
	command_handle: interaction.Command_Handle,
	constraints: display.Viewport_Constraints,
) -> (Interaction_Result, App_Failure) {
	#partial switch route {
	case .Terminal_Open, .Terminal_New, .Terminal_Open_Here,
	     .Terminal_Open_Project, .Terminal_Open_Other_Pane, .Terminal_Toggle:
		return command_context_dispatch_terminal_presentation(commands, route, command_handle)
	case .Terminal_List:
		return command_context_present_terminal_inventory(commands, constraints, command_handle)
	case .Terminal_Rename:
		return command_context_begin_terminal_rename(commands, command_handle)
	case .Shell_Command, .Async_Shell_Command, .Compile:
		return command_context_begin_shell_command(commands, route)
	case .Recompile:
		return command_context_recompile(commands)
	}
	state, active := command_context_active_terminal_state(commands)
	if !active {
		command_context_set_diagnostic(commands, "Requires an active terminal")
		return Interaction_Result{changed = true}, {}
	}
	ref := terminal_session_ref(state.terminal)
	_ = terminal_workflow_note_focus(commands.terminal_workflow, ref)
	if route == .Terminal_Copy_Mode {
		entry := terminal_workflow_entry_record(commands.terminal_workflow, ref)
		transition, entered, _ := terminal_session.registry_copy_mode_enter(
			&commands.terminal_workflow.registry, ref,
		)
		if entry == nil || !entered {
			command_context_set_diagnostic(commands, "Terminal copy mode is unavailable")
			return {changed = true}, {}
		}
		if command_context_modal_terminal_profile(commands) {
			modal_result, modal_failure := command_context_transition_modal_state(commands, "Normal")
			if modal_failure.stage != .None do return modal_result, modal_failure
			_, modal_state, selected := interaction.profile_activation_selection(commands.profile_activation)
			if !selected || modal_state.name != "Normal" {
				command_context_set_diagnostic(commands, "Terminal copy mode requires modal Normal state")
				return {changed = true}, {}
			}
		}
		entry.copy_mode = transition.state
		command_context_scroll_terminal_copy(commands, ref, entry.copy_mode)
		command_context_set_diagnostic(commands, "Terminal copy mode entered")
		return {changed = true}, {}
	}
	if route == .Terminal_Copy_Mode_Done || route == .Terminal_Beginning_Of_Line ||
	   route == .Terminal_End_Of_Line || route == .Terminal_Reset_Cursor_Point {
		command_context_set_diagnostic(commands, "Terminal copy mode is not active")
		return {changed = true}, {}
	}
	if route == .Terminal_Yank || route == .Terminal_Yank_Pop {
		return command_context_terminal_yank(
			commands,
			ref,
			command_handle,
			route == .Terminal_Yank_Pop,
		), {}
	}
	terminal_workflow_clear_yank(commands.terminal_workflow, ref)
	if route == .Terminal_Next_Error {
		return command_context_move_active_location(commands, true)
	}
	if route == .Terminal_Next_Prompt || route == .Terminal_Previous_Prompt {
		return command_context_move_terminal_prompt(commands, ref, route == .Terminal_Next_Prompt)
	}
	if route == .Terminal_Open_Link {
		return command_context_open_terminal_link(commands, ref)
	}
	if route == .Terminal_Send_Next_Key {
		commands.terminal_workflow.literal_next = ref
		commands.context_pending = {}
		commands.pending = {}
		command_context_set_diagnostic(commands, "Send next key to terminal")
		return Interaction_Result{changed = true}, {}
	}
	if route == .Terminal_Terminate {
		requested, _ := terminal_session.registry_request_terminate(
			&commands.terminal_workflow.registry,
			ref,
			terminal_workflow_now_ns(commands.terminal_workflow),
		)
		if !requested {
			command_context_set_diagnostic(commands, "Terminal process cannot be terminated")
			return Interaction_Result{changed = true}, {}
		}
		command_context_set_diagnostic(commands, "Terminal termination requested")
		return Interaction_Result{changed = true}, {}
	}
	if route == .Terminal_Clear_Scrollback {
		cleared, _ := terminal_session.registry_clear_scrollback(
			&commands.terminal_workflow.registry,
			ref,
		)
		if !cleared {
			command_context_set_diagnostic(commands, "Terminal scrollback cannot be cleared")
			return Interaction_Result{changed = true}, {}
		}
		_, _, _ = terminal_workflow_refresh(commands.terminal_workflow, commands.session_owner, ref)
		command_context_set_diagnostic(commands, "Terminal scrollback cleared")
		return Interaction_Result{changed = true}, {}
	}
	request, supported := terminal_interaction_route_request(route)
	if supported {
		_, sent, send_failure := terminal_session.registry_send_input(
			&commands.terminal_workflow.registry,
			ref,
			request,
		)
		if !sent {
			message := "Terminal input is unavailable"
			if send_failure.code == .Input_Limit do message = "Terminal input queue is full"
			command_context_set_diagnostic(commands, message)
			return Interaction_Result{changed = true}, {}
		}
		return {}, {}
	}
	command_context_set_diagnostic(commands, "Terminal command is not available in this workflow")
	return Interaction_Result{changed = true}, {}
}

@(private)
command_context_open_terminal_link :: proc(
	commands: ^Command_Context,
	ref: terminal_session.Session_Ref,
) -> (Interaction_Result, App_Failure) {
	revision, projected, _ := terminal_session.registry_project_render(
		&commands.terminal_workflow.registry, ref,
	)
	if !projected || !revision.projection.cursor_in_viewport {
		command_context_set_diagnostic(commands, "No terminal link at cursor")
		return {changed = true}, {}
	}
	target: [terminal_session.MAX_HYPERLINK_BYTES]u8
	_, linked, link_failure := terminal_session.registry_hyperlink_at(
		&commands.terminal_workflow.registry,
		ref,
		revision.projection.cursor_column,
		u32(revision.projection.cursor_row),
		target[:],
	)
	if !linked {
		message := "No terminal link at cursor"
		if link_failure.code == .Hyperlink_Rejected do message = "Terminal link target was rejected"
		command_context_set_diagnostic(commands, message)
		return {changed = true}, {}
	}
	command_context_set_diagnostic(commands, "External opening is unavailable: no provider is configured")
	return {changed = true}, {}
}

@(private)
command_context_terminal_yank :: proc(
	commands: ^Command_Context,
	ref: terminal_session.Session_Ref,
	command_handle: interaction.Command_Handle,
	rotate: bool,
) -> Interaction_Result {
	if !rotate {
		clipboard := clipboard_workflow_import(
			&commands.clipboard_workflow,
			commands.kill_ring,
			command_handle,
			commands.temporary_allocator,
		)
		if clipboard.diagnostic_length > 0 {
			command_context_set_diagnostic(
				commands,
				string(clipboard.diagnostic[:clipboard.diagnostic_length]),
			)
		}
		if !clipboard.ready do return {changed = clipboard.changed}
	}
	entry := terminal_workflow_entry_record(commands.terminal_workflow, ref)
	if entry == nil {
		command_context_set_diagnostic(commands, "Terminal yank context is unavailable")
		return {changed = true}
	}
	if rotate && entry.yanked_multiline {
		command_context_set_diagnostic(commands, "Terminal yank-pop cannot replace multiline input")
		return {changed = true}
	}
	copied, next, copied_ok, copy_failure := command.terminal_text_yank_copy(
		commands.kill_ring,
		command_handle,
		entry.yank,
		rotate,
		terminal_session.MAX_COPIED_TEXT_BYTES,
		commands.temporary_allocator,
	)
	if !copied_ok {
		message := "Nothing to yank"
		if rotate && copy_failure.kill_ring_code == .Stale_Generation {
			message = "Terminal yank-pop is no longer current"
		}
		command_context_set_diagnostic(commands, message)
		return {changed = true}
	}
	defer command.terminal_text_yank_copy_release(&copied, commands.temporary_allocator)
	replace_codepoints := u32(0)
	if rotate do replace_codepoints = entry.yanked_codepoints
	paste, pasted, paste_failure := terminal_session.registry_paste(
		&commands.terminal_workflow.registry,
		ref,
		terminal_session.Paste_Request {
			text = copied.text,
			replace_codepoints = replace_codepoints,
		},
	)
	if !pasted {
		message := "Terminal paste is unavailable"
		if paste_failure.code == .Paste_Rejected {
			message = "Terminal paste requires explicit unsafe confirmation"
		} else if paste_failure.code == .Input_Limit {
			message = "Terminal paste exceeds the input limit"
		}
		command_context_set_diagnostic(commands, message)
		return {changed = true}
	}
	codepoints := utf8.rune_count(copied.text)
	if codepoints < 0 || codepoints > int(terminal_session.MAX_INPUT_REPEAT_COUNT) {
		entry.yank = {}
		entry.yanked_codepoints = 0
		entry.yanked_multiline = false
	} else {
		entry.yank = next
		entry.yanked_codepoints = u32(codepoints)
		entry.yanked_multiline = strings.index_byte(copied.text, '\n') >= 0
	}
	_ = paste
	command_context_set_diagnostic(commands, "Terminal text pasted")
	return {changed = true}
}

@(private)
terminal_interaction_route_request :: proc(
	route: command.Native_Route,
) -> (request: terminal_session.Input_Request, ok: bool) {
	request = {kind = .Key, action = .Press, source = .Ordinary, repeat_count = 1}
	#partial switch route {
	case .Terminal_Send_Return:    request.key = .Enter
	case .Terminal_Send_Tab:       request.key = .Tab
	case .Terminal_Send_Escape:    request.key = .Escape
	case .Terminal_Send_Backspace: request.key = .Backspace
	case .Terminal_Send_Delete:    request.key = .Delete
	case .Terminal_Send_Up:        request.key = .Up
	case .Terminal_Send_Down:      request.key = .Down
	case .Terminal_Send_Left:      request.key = .Left
	case .Terminal_Send_Right:     request.key = .Right
	case .Terminal_Send_Prior:     request.key = .Prior
	case .Terminal_Send_Next:      request.key = .Next
	case .Terminal_Send_Space:     request.key = .Space
	case .Terminal_Clear:
		request.key = .Character
		request.text = "l"
		request.modifiers = {.Control}
	case .Terminal_Undo:
		request.key = .Character
		request.text = "/"
		request.modifiers = {.Control}
	case:
		return {}, false
	}
	return request, true
}

@(private)
terminal_session_ref :: proc(ref: editor_session.Terminal_Session_Ref) -> terminal_session.Session_Ref {
	return {id = terminal_session.Session_ID(ref.id), generation = terminal_session.Session_Generation(ref.generation)}
}
