// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../interaction"
import "../ui"

@(private)
command_context_text_cursor_shape :: proc(commands: ^Command_Context) -> ui.Text_Cursor_Shape {
	if commands == nil || commands.profile_activation == nil do return .Default
	profile, state, selected := interaction.profile_activation_selection(commands.profile_activation)
	if !selected do return .Default
	catalog, catalog_ok := interaction.profile_activation_catalog(commands.profile_activation)
	if !catalog_ok do return .Default
	for candidate in catalog.profiles {
		if candidate.identity != profile || candidate.name != "modal" do continue
		if state.name == "Insert" do return .Bar
		if state.name == "Replace" do return .Underline
		return .Block
	}
	return .Default
}

@(private)
command_context_modal_replace_active :: proc(commands: ^Command_Context) -> bool {
	if commands == nil || commands.profile_activation == nil do return false
	profile, state, selected := interaction.profile_activation_selection(commands.profile_activation)
	if !selected || state.name != "Replace" do return false
	catalog, catalog_ok := interaction.profile_activation_catalog(commands.profile_activation)
	if !catalog_ok do return false
	for candidate in catalog.profiles {
		if candidate.identity == profile do return candidate.name == "modal"
	}
	return false
}
