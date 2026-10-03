// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../command"
import "../display"
import "../editor"
import "../editor_session"
import "../interaction"
import editor_view "../view"

@(private)
command_context_modal_visual_finish_buffer_switch :: proc(
	commands: ^Command_Context,
	target: editor_session.Entry_Handle,
) -> (Interaction_Result, App_Failure) {
	visual, visual_ok := interaction.profile_activation_modal_visual_inspect(
		commands.profile_activation,
	)
	if !visual_ok do return {}, {}
	target_access, target_ok, target_failure := editor_session.session_entry_access(
		commands.session_owner,
		target,
	)
	if !target_ok {
		return {}, App_Failure{stage = .Session_Access, editor_session = target_failure}
	}
	target_entry, target_borrowed, target_borrow_failure := editor_session.entry_access_borrow(
		target_access,
	)
	if !target_borrowed {
		return {}, App_Failure{stage = .Session_Access, editor_session = target_borrow_failure}
	}
	target_stats, target_stats_ok, _ := editor.buffer_stats(target_entry.buffer)
	if !target_stats_ok do return {}, App_Failure{stage = .Session_Access}
	if visual.buffer_identity == u64(target_stats.buffer_id) do return {}, {}
	if commands.candidate_ui.return_target.kind != .Primary_View {
		return {}, App_Failure{stage = .Session_Access}
	}
	source_access, source_ok, source_failure := editor_session.session_entry_access(
		commands.session_owner,
		commands.candidate_ui.return_target.entry,
	)
	if !source_ok {
		return {}, App_Failure{stage = .Session_Access, editor_session = source_failure}
	}
	source_entry, source_borrowed, source_borrow_failure := editor_session.entry_access_borrow(
		source_access,
	)
	if !source_borrowed {
		return {}, App_Failure{stage = .Session_Access, editor_session = source_borrow_failure}
	}
	return command_context_modal_visual_finish(
		commands,
		source_entry.view_registry,
		source_entry.primary_view,
		"Normal",
	)
}

@(private)
command_context_modal_visual_transition :: proc(
	commands: ^Command_Context,
	buffer: ^editor.Buffer,
	view_registry: ^editor_view.Registry,
	view: editor_view.View_Handle,
	target: interaction.Modal_Visual_Kind,
) -> (Interaction_Result, App_Failure) {
	if commands == nil || commands.profile_activation == nil || buffer == nil {
		return {}, App_Failure{stage = .Keymap_Activation}
	}
	if target == .None {
		logical, viewed, view_failure := editor_view.snapshot(view_registry, view)
		if !viewed do return {}, App_Failure{stage = .Command_Dispatch, view = view_failure}
		if logical.region_active {
			deactivated, deactivate_failure := editor_view.set_region_active(view_registry, view, false)
			if !deactivated do return {}, App_Failure{stage = .Command_Dispatch, view = deactivate_failure}
		}
		_ = interaction.profile_activation_modal_visual_clear(commands.profile_activation)
		return command_context_transition_modal_state(commands, "Normal")
	}
	visual, visual_active := interaction.profile_activation_modal_visual_inspect(
		commands.profile_activation,
	)
	logical, viewed, view_failure := editor_view.snapshot(view_registry, view)
	if !viewed do return {}, App_Failure{stage = .Command_Dispatch, view = view_failure}
	anchor := u64(logical.point_position.byte_offset)
	cursor := anchor
	if visual_active {
		if visual.buffer_identity != u64(logical.buffer_id) ||
		   visual.buffer_revision != u64(logical.revision) {
			_ = interaction.profile_activation_modal_visual_clear(commands.profile_activation)
			return command_context_transition_modal_state(commands, "Normal")
		}
		anchor = visual.anchor_offset
		cursor = visual.cursor_offset
	}
	materialized, materialize_failure := command_context_modal_visual_materialize(
		buffer, view_registry, view, target, anchor, cursor,
	)
	if materialize_failure.stage != .None do return {}, materialize_failure
	if !materialized {
		command_context_set_diagnostic(commands, "Visual selection is unavailable")
		return Interaction_Result{changed = true}, {}
	}
	target_name := "Visual Character"
	if target == .Line do target_name = "Visual Line"
	if target == .Block do target_name = "Visual Block"
	transitioned, transition_failure := command_context_transition_modal_state(commands, target_name)
	if transition_failure.stage != .None do return {}, transition_failure
	request, current := command_context_modal_navigation_request(
		commands, buffer, view, interaction.Input{kind = .Key, stroke = {kind = .Escape}},
	)
	if !current {
		return {}, App_Failure{stage = .Keymap_Activation}
	}
	started, start_failure := interaction.profile_activation_modal_visual_begin(
		commands.profile_activation, request, target, anchor, cursor,
	)
	if !started {
		return {}, App_Failure{stage = .Keymap_Activation, interaction = start_failure}
	}
	return Interaction_Result{changed = transitioned.changed || materialized}, {}
}

@(private)
command_context_modal_visual_finish :: proc(
	commands: ^Command_Context,
	view_registry: ^editor_view.Registry,
	view: editor_view.View_Handle,
	target_name: string,
) -> (Interaction_Result, App_Failure) {
	logical, viewed, view_failure := editor_view.snapshot(view_registry, view)
	if !viewed do return {}, App_Failure{stage = .Command_Dispatch, view = view_failure}
	if logical.region_active {
		deactivated, deactivate_failure := editor_view.set_region_active(view_registry, view, false)
		if !deactivated do return {}, App_Failure{stage = .Command_Dispatch, view = deactivate_failure}
	}
	_ = interaction.profile_activation_modal_visual_clear(commands.profile_activation)
	return command_context_transition_modal_state(commands, target_name)
}

@(private)
command_context_modal_visual_move :: proc(
	commands: ^Command_Context,
	buffer: ^editor.Buffer,
	view_registry: ^editor_view.Registry,
	view: editor_view.View_Handle,
	route: command.Native_Route,
	count: u64,
	text: string,
	profile: display.Display_Profile,
	constraints: display.Viewport_Constraints,
) -> (Interaction_Result, App_Failure) {
	visual, active := interaction.profile_activation_modal_visual_inspect(commands.profile_activation)
	if !active do return {}, App_Failure{stage = .Command_Dispatch}
	logical, viewed, view_failure := editor_view.snapshot(view_registry, view)
	if !viewed do return {}, App_Failure{stage = .Command_Dispatch, view = view_failure}
	if visual.buffer_identity != u64(logical.buffer_id) ||
	   visual.buffer_revision != u64(logical.revision) {
		return command_context_modal_visual_transition(
			commands, buffer, view_registry, view, .None,
		)
	}
	cursor, cursor_ok, cursor_failure := editor.buffer_position(
		buffer, editor.Byte_Offset(visual.cursor_offset),
	)
	if !cursor_ok do return {}, App_Failure{stage = .Command_Dispatch, editor = cursor_failure}
	probe := logical
	probe.point_position = cursor
	repeat_count := count
	if repeat_count == 0 do repeat_count = 1
	steps := repeat_count
	kind: display.Navigation_Kind
	character_kind := display.Line_Character_Target_Kind.Invalid
	#partial switch route {
	case .Cursor_Previous_Grapheme: kind = .Previous_Grapheme
	case .Cursor_Next_Grapheme: kind = .Next_Grapheme
	case .Cursor_Previous_Line: kind = .Previous_Line
	case .Cursor_Next_Line: kind = .Next_Line
	case .Cursor_Line_Start: kind = .Line_Start
	case .Cursor_Line_End: kind = .Line_End
	case .Cursor_Previous_Word: kind = .Previous_Word
	case .Cursor_Next_Word: kind = .Next_Word
	case .Cursor_Next_Word_Start: kind = .Next_Word_Start
	case .Cursor_Word_End: kind = .Next_Word
	case .Cursor_Line_First_Non_Whitespace: kind = .Line_First_Non_Whitespace
	case .Cursor_Buffer_Start: kind = .Buffer_Start
	case .Cursor_Buffer_End: kind = .Buffer_End
	case .Scroll_Previous_Page:
		kind = .Previous_Line
		if constraints.height_rows <= 1 do return Interaction_Result{changed = true}, {}
		steps *= u64(constraints.height_rows - 1)
	case .Scroll_Next_Page:
		kind = .Next_Line
		if constraints.height_rows <= 1 do return Interaction_Result{changed = true}, {}
		steps *= u64(constraints.height_rows - 1)
	case .Cursor_Find_Next_Character: character_kind = .Find_Next
	case .Cursor_Find_Previous_Character: character_kind = .Find_Previous
	case .Cursor_Till_Next_Character: character_kind = .Till_Next
	case .Cursor_Till_Previous_Character: character_kind = .Till_Previous
	case: return {}, App_Failure{stage = .Command_Dispatch}
	}
	target := cursor
	desired := logical.desired_display_column
	if character_kind != .Invalid {
		found: bool
		resolved: bool
		target_failure: display.Failure_Context
		target, desired, found, resolved, target_failure = display.line_character_navigation_target(
			buffer, probe, text, character_kind, steps, profile,
		)
		if !resolved do return {}, App_Failure{stage = .Command_Dispatch, display = target_failure}
		if !found do return Interaction_Result{changed = true}, {}
	} else {
		for _ in 0 ..< steps {
			next, next_desired, resolved, target_failure := display.navigation_target(
				buffer, probe, kind, profile,
			)
			if !resolved do return {}, App_Failure{stage = .Command_Dispatch, display = target_failure}
			if next == target do break
			target = next
			desired = next_desired
			probe.point_position = next
			probe.desired_display_column = next_desired
		}
	}
	materialized, materialize_failure := command_context_modal_visual_materialize(
		buffer, view_registry, view, visual.kind,
		visual.anchor_offset, u64(target.byte_offset),
	)
	if materialize_failure.stage != .None do return {}, materialize_failure
	if !materialized do return Interaction_Result{changed = true}, {}
	request, current := command_context_modal_navigation_request(
		commands, buffer, view, interaction.Input{kind = .Key, stroke = {kind = .Escape}},
	)
	if !current do return {}, App_Failure{stage = .Command_Dispatch}
	updated, update_failure := interaction.profile_activation_modal_visual_update(
		commands.profile_activation, request, u64(target.byte_offset),
	)
	if !updated do return {}, App_Failure{stage = .Command_Dispatch, interaction = update_failure}
	_ = desired
	return Interaction_Result{changed = true}, {}
}

@(private)
command_context_modal_visual_materialize :: proc(
	buffer: ^editor.Buffer,
	view_registry: ^editor_view.Registry,
	view: editor_view.View_Handle,
	kind: interaction.Modal_Visual_Kind,
	anchor_offset, cursor_offset: u64,
) -> (bool, App_Failure) {
	anchor, anchor_ok, anchor_failure := editor.buffer_position(
		buffer, editor.Byte_Offset(anchor_offset),
	)
	if !anchor_ok do return false, App_Failure{stage = .Command_Dispatch, editor = anchor_failure}
	cursor, cursor_ok, cursor_failure := editor.buffer_position(
		buffer, editor.Byte_Offset(cursor_offset),
	)
	if !cursor_ok do return false, App_Failure{stage = .Command_Dispatch, editor = cursor_failure}
	logical, viewed, view_failure := editor_view.snapshot(view_registry, view)
	if !viewed do return false, App_Failure{stage = .Command_Dispatch, view = view_failure}
	start := anchor
	end := cursor
	if kind == .Block {
		column, column_ok, column_failure := display.position_display_column(
			buffer, cursor, display.terminal_unicode17_profile(), logical.tab_width,
		)
		if !column_ok do return false, App_Failure{stage = .Command_Dispatch, display = column_failure}
		selected, select_failure := editor_view.select_range(
			view_registry,
			view,
			anchor,
			cursor,
			column,
			.Rectangle,
			.Grapheme,
		)
		if !selected do return false, App_Failure{stage = .Command_Dispatch, view = select_failure}
		return true, {}
	} else if kind == .Line {
		ready: bool
		failure: App_Failure
		start, end, ready, failure = modal_operator_line_range(buffer, anchor, cursor)
		if failure.stage != .None || !ready do return ready, failure
	} else {
		if start.byte_offset > end.byte_offset do start, end = end, start
		probe := logical
		probe.point_position = end
		next, _, resolved, navigation_failure := display.navigation_target(
			buffer, probe, .Next_Grapheme, display.terminal_unicode17_profile(),
		)
		if !resolved do return false, App_Failure{stage = .Command_Dispatch, display = navigation_failure}
		if next.byte_offset > end.byte_offset {
			end = next
		} else if start.byte_offset == end.byte_offset {
			previous, _, previous_ok, previous_failure := display.navigation_target(
				buffer, probe, .Previous_Grapheme, display.terminal_unicode17_profile(),
			)
			if !previous_ok do return false, App_Failure{stage = .Command_Dispatch, display = previous_failure}
			start = previous
		}
	}
	if start.byte_offset == end.byte_offset do return false, {}
	column, column_ok, column_failure := display.position_display_column(
		buffer, end, display.terminal_unicode17_profile(), logical.tab_width,
	)
	if !column_ok do return false, App_Failure{stage = .Command_Dispatch, display = column_failure}
	selected, select_failure := editor_view.select_range(
		view_registry, view, start, end, column,
	)
	if !selected do return false, App_Failure{stage = .Command_Dispatch, view = select_failure}
	return true, {}
}

@(private)
command_context_modal_visual_adopt_region :: proc(
	commands: ^Command_Context,
	buffer: ^editor.Buffer,
	view_registry: ^editor_view.Registry,
	view: editor_view.View_Handle,
) -> (Interaction_Result, App_Failure) {
	visual, active := interaction.profile_activation_modal_visual_inspect(commands.profile_activation)
	if !active do return {}, App_Failure{stage = .Command_Dispatch}
	logical, viewed, view_failure := editor_view.snapshot(view_registry, view)
	if !viewed do return {}, App_Failure{stage = .Command_Dispatch, view = view_failure}
	if !logical.region_active || !logical.mark.present {
		return command_context_modal_visual_finish(commands, view_registry, view, "Normal")
	}
	start := logical.mark.position
	end := logical.point_position
	if start.byte_offset > end.byte_offset do start, end = end, start
	cursor := start
	if end.byte_offset > start.byte_offset {
		probe := logical
		probe.point_position = end
		previous, _, resolved, previous_failure := display.navigation_target(
			buffer, probe, .Previous_Grapheme, display.terminal_unicode17_profile(),
		)
		if !resolved do return {}, App_Failure{stage = .Command_Dispatch, display = previous_failure}
		cursor = previous
	}
	request, current := command_context_modal_navigation_request(
		commands, buffer, view, interaction.Input{kind = .Key, stroke = {kind = .Escape}},
	)
	if !current do return {}, App_Failure{stage = .Command_Dispatch}
	rebased, rebase_failure := interaction.profile_activation_modal_visual_rebase(
		commands.profile_activation,
		request,
		u64(start.byte_offset),
		u64(cursor.byte_offset),
	)
	if !rebased do return {}, App_Failure{stage = .Command_Dispatch, interaction = rebase_failure}
	_ = visual
	return Interaction_Result{changed = true}, {}
}

@(private)
command_context_modal_visual_prepare_search :: proc(
	commands: ^Command_Context,
	buffer: ^editor.Buffer,
	view_registry: ^editor_view.Registry,
	view: editor_view.View_Handle,
) -> App_Failure {
	visual, active := interaction.profile_activation_modal_visual_inspect(commands.profile_activation)
	if !active do return App_Failure{stage = .Command_Dispatch}
	target, target_ok, target_failure := editor.buffer_position(
		buffer, editor.Byte_Offset(visual.cursor_offset),
	)
	if !target_ok do return App_Failure{stage = .Command_Dispatch, editor = target_failure}
	logical, viewed, view_failure := editor_view.snapshot(view_registry, view)
	if !viewed do return App_Failure{stage = .Command_Dispatch, view = view_failure}
	column, column_ok, column_failure := display.position_display_column(
		buffer, target, display.terminal_unicode17_profile(), logical.tab_width,
	)
	if !column_ok do return App_Failure{stage = .Command_Dispatch, display = column_failure}
	moved, move_failure := editor_view.move_point(
		view_registry, view, target, column, .Preserve,
	)
	if !moved do return App_Failure{stage = .Command_Dispatch, view = move_failure}
	return {}
}

@(private)
command_context_modal_visual_reconcile_point :: proc(
	commands: ^Command_Context,
	buffer: ^editor.Buffer,
	view_registry: ^editor_view.Registry,
	view: editor_view.View_Handle,
) -> (Interaction_Result, App_Failure) {
	visual, active := interaction.profile_activation_modal_visual_inspect(commands.profile_activation)
	if !active do return Interaction_Result{changed = true}, {}
	logical, viewed, view_failure := editor_view.snapshot(view_registry, view)
	if !viewed do return {}, App_Failure{stage = .Command_Dispatch, view = view_failure}
	cursor := u64(logical.point_position.byte_offset)
	materialized, materialize_failure := command_context_modal_visual_materialize(
		buffer, view_registry, view, visual.kind, visual.anchor_offset, cursor,
	)
	if materialize_failure.stage != .None do return {}, materialize_failure
	if !materialized do return Interaction_Result{changed = true}, {}
	request, current := command_context_modal_navigation_request(
		commands, buffer, view, interaction.Input{kind = .Key, stroke = {kind = .Escape}},
	)
	if !current do return {}, App_Failure{stage = .Command_Dispatch}
	updated, update_failure := interaction.profile_activation_modal_visual_update(
		commands.profile_activation, request, cursor,
	)
	if !updated do return {}, App_Failure{stage = .Command_Dispatch, interaction = update_failure}
	return Interaction_Result{changed = true}, {}
}

@(private)
command_context_modal_visual_movement_route :: proc(route: command.Native_Route) -> bool {
	#partial switch route {
	case .Cursor_Previous_Grapheme, .Cursor_Next_Grapheme,
	     .Cursor_Previous_Line, .Cursor_Next_Line,
	     .Cursor_Line_Start, .Cursor_Line_End,
	     .Cursor_Previous_Word, .Cursor_Next_Word,
	     .Cursor_Next_Word_Start, .Cursor_Word_End,
	     .Cursor_Line_First_Non_Whitespace,
	     .Cursor_Buffer_Start, .Cursor_Buffer_End,
	     .Cursor_Find_Next_Character, .Cursor_Find_Previous_Character,
	     .Cursor_Till_Next_Character, .Cursor_Till_Previous_Character,
	     .Scroll_Previous_Page, .Scroll_Next_Page:
		return true
	case:
		return false
	}
}
