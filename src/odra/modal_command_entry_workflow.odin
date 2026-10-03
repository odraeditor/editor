// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../editor"
import "../interaction"
import editor_view "../view"

@(private)
command_context_modal_command_entry_request :: proc(
	commands: ^Command_Context,
	buffer: ^editor.Buffer,
	view: editor_view.View_Handle,
	input: interaction.Input,
) -> (interaction.Modal_Command_Entry_Request, bool) {
	if commands == nil || commands.profile_activation == nil || buffer == nil ||
	   input.kind != .Key ||
	   commands.active_interaction_context.identity.id == interaction.Context_ID(0) ||
	   commands.active_interaction_context.identity.generation == interaction.Context_Generation(0) ||
	   view.view_id == editor_view.View_ID(0) || view.generation == 0 {
		return {}, false
	}
	profile, state, selected := interaction.profile_activation_selection(commands.profile_activation)
	if !selected do return {}, false
	catalog, catalog_ok := interaction.profile_activation_catalog(commands.profile_activation)
	if !catalog_ok do return {}, false
	modal := false
	for candidate in catalog.profiles {
		if candidate.identity == profile {
			modal = candidate.name == "modal"
			break
		}
	}
	if !modal do return {}, false
	surface, surface_ok := interaction.profile_activation_command_entry_surface(
		commands.profile_activation,
		"extended-command",
	)
	if !surface_ok do return {}, false
	stats, stats_ok, _ := editor.buffer_stats(buffer)
	if !stats_ok do return {}, false
	sequence := interaction.Key_Sequence{stroke_count = 1}
	sequence.strokes[0] = input.stroke
	return interaction.Modal_Command_Entry_Request {
		profile = profile,
		state = state.identity,
		catalog_generation = catalog.generation,
		snapshot_generation = commands.profile_activation.generation,
		ctx = commands.active_interaction_context.identity,
		view_identity = u64(view.view_id),
		view_generation = view.generation,
		buffer_identity = u64(stats.buffer_id),
		buffer_revision = u64(stats.revision),
		sequence = sequence,
		surface = surface.identity,
	}, true
}

@(private)
command_context_modal_command_entry_begin :: proc(
	commands: ^Command_Context,
	buffer: ^editor.Buffer,
	view: editor_view.View_Handle,
	input: interaction.Input,
) -> bool {
	request, relevant := command_context_modal_command_entry_request(commands, buffer, view, input)
	if !relevant do return true
	started, _ := interaction.profile_activation_modal_command_entry_begin(
		commands.profile_activation,
		request,
	)
	return started
}

@(private)
command_context_modal_command_entry_claim :: proc(
	commands: ^Command_Context,
	buffer: ^editor.Buffer,
	view: editor_view.View_Handle,
) -> (claimed: bool, ok: bool) {
	pending, inspected := interaction.profile_activation_modal_pending_inspect(
		commands.profile_activation,
	)
	if !inspected || pending.kind != .Command_Entry do return false, true
	request, relevant := command_context_modal_command_entry_request(
		commands,
		buffer,
		view,
		interaction.Input{kind = .Key, stroke = pending.strokes[0]},
	)
	if !relevant do return false, false
	claimed, _ = interaction.profile_activation_modal_command_entry_claim(
		commands.profile_activation,
		request,
	)
	return claimed, claimed
}
