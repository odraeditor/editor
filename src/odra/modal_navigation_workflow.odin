// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../command"
import "../editor"
import "../interaction"
import editor_view "../view"

@(private)
command_context_modal_navigation_request :: proc(
	commands: ^Command_Context,
	buffer: ^editor.Buffer,
	view: editor_view.View_Handle,
	input: interaction.Input,
) -> (interaction.Modal_Navigation_Request, bool) {
	if commands == nil || commands.profile_activation == nil || buffer == nil ||
	   commands.active_interaction_context.identity.id == interaction.Context_ID(0) ||
	   commands.active_interaction_context.identity.generation == interaction.Context_Generation(0) ||
	   view.view_id == editor_view.View_ID(0) || view.generation == 0 {
		return {}, false
	}
	profile, state, selected := interaction.profile_activation_selection(commands.profile_activation)
	if !selected ||
	   (state.name != "Normal" && state.name != "Visual Character" &&
	    state.name != "Visual Line" && state.name != "Visual Block") {
		return {}, false
	}
	catalog, catalog_ok := interaction.profile_activation_catalog(commands.profile_activation)
	if !catalog_ok {
		return {}, false
	}
	modal_profile := false
	for candidate in catalog.profiles {
		if candidate.identity == profile {
			modal_profile = candidate.name == "modal"
			break
		}
	}
	if !modal_profile {
		return {}, false
	}
	stats, stats_ok, _ := editor.buffer_stats(buffer)
	if !stats_ok {
		return {}, false
	}
	selection, selection_ok, _ := editor.buffer_selection_snapshot(buffer)
	if !selection_ok || selection.point_position.revision != stats.revision {
		return {}, false
	}
	return interaction.Modal_Navigation_Request {
		catalog_generation = catalog.generation,
		snapshot_generation = commands.profile_activation.generation,
		ctx = commands.active_interaction_context.identity,
		view_identity = u64(view.view_id),
		view_generation = view.generation,
		buffer_identity = u64(stats.buffer_id),
		buffer_revision = u64(stats.revision),
		point_offset = u64(selection.point_position.byte_offset),
		input = input,
		profile = profile,
		state = state.identity,
	}, true
}

@(private)
command_context_modal_character_command :: proc(
	target: interaction.Modal_Character_Target_Kind,
) -> (string, bool) {
	#partial switch target {
	case .Find_Next:     return "cursor-find-next-character", true
	case .Find_Previous: return "cursor-find-previous-character", true
	case .Till_Next:     return "cursor-till-next-character", true
	case .Till_Previous: return "cursor-till-previous-character", true
	case:                return "", false
	}
}

@(private)
command_context_is_modal_count_route :: proc(route: command.Native_Route) -> bool {
	#partial switch route {
	case .Cursor_Previous_Grapheme, .Cursor_Next_Grapheme,
	     .Delete_Previous_Grapheme, .Delete_Next_Grapheme,
	     .Cursor_Previous_Line, .Cursor_Next_Line,
	     .Cursor_Line_Start, .Cursor_Line_End,
	     .Cursor_Previous_Word, .Cursor_Next_Word,
	     .Cursor_Next_Word_Start, .Cursor_Word_End,
	     .Cursor_Line_First_Non_Whitespace,
	     .Cursor_Buffer_Start, .Cursor_Buffer_End,
	     .Cursor_Find_Next_Character, .Cursor_Find_Previous_Character,
	     .Cursor_Till_Next_Character, .Cursor_Till_Previous_Character,
	     .Scroll_Previous_Page, .Scroll_Next_Page,
	     .Search_Next_Occurrence, .Search_Previous_Occurrence,
	     .Yank, .Yank_After_Point, .Modal_Repeat_Last_Change:
		return true
	case:
		return false
	}
}
