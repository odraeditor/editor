// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../command"
import "../editor"
import "../gutter"
import editor_view "../view"
import "core:strings"
import "core:testing"

@(test)
/* gutter_commands_override_only_the_active_view_and_reject_visual_scope. */
gutter_commands_scope_to_active_view :: proc(t: ^testing.T) {
	buffer: editor.Buffer
	buffer_ok, _ := editor.buffer_init(
		&buffer,
		editor.Buffer_ID(9_201),
		"one\ntwo\nthree\n",
		editor.Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	registry: editor_view.Registry
	registry_ok, _ := editor_view.registry_init(
		&registry,
		editor_view.Registry_ID(9_202),
		context.allocator,
	)
	primary, primary_ok, _ := editor_view.create(&registry, &buffer)
	additional, additional_ok, _ := editor_view.clone_additional(&registry, primary)
	testing.expect(t, buffer_ok && registry_ok && primary_ok && additional_ok)
	if !buffer_ok || !registry_ok || !primary_ok || !additional_ok do return

	commands := Command_Context{gutter_policy = gutter.DEFAULT_FACTORY_POLICY}
	result, failure := command_context_apply_gutter_command(
		&commands,
		&buffer,
		&registry,
		additional,
		command.Native_Route.Gutter_Cycle_Line_Number_Mode,
		{},
	)
	testing.expect(t, result.changed && failure.stage == .None)
	primary_state, primary_state_ok, _ := editor_view.snapshot(&registry, primary)
	additional_state, additional_state_ok, _ := editor_view.snapshot(&registry, additional)
	testing.expect(t, primary_state_ok && additional_state_ok)
	testing.expect(t, !primary_state.gutter.overrides_default)
	testing.expect(t, additional_state.gutter.overrides_default)
	testing.expect_value(t, additional_state.gutter.policy.mode, gutter.Numbering_Mode.Relative)

	before_generation := additional_state.gutter.generation
	visual_result, visual_failure := command_context_apply_gutter_command(
		&commands,
		&buffer,
		&registry,
		additional,
		command.Native_Route.Gutter_Set_Numbering_Visual,
		{},
	)
	after_visual, after_visual_ok, _ := editor_view.snapshot(&registry, additional)
	testing.expect(t, visual_result.changed && visual_failure.stage == .None && after_visual_ok)
	testing.expect_value(t, after_visual.gutter.generation, before_generation)
	testing.expect(
		t,
		strings.contains(
			string(commands.diagnostic[:commands.diagnostic_length]),
			"unavailable",
		),
	)

	inspect_result, inspect_failure := command_context_apply_gutter_command(
		&commands,
		&buffer,
		&registry,
		additional,
		command.Native_Route.Gutter_Inspect_Numbering,
		{},
	)
	testing.expect(t, inspect_result.changed && inspect_failure.stage == .None)
	testing.expect(
		t,
		strings.contains(
			string(commands.diagnostic[:commands.diagnostic_length]),
			"mode=relative",
		),
	)

	additional_closed, _ := editor_view.close(&registry, &additional)
	primary_closed, _ := editor_view.close(&registry, &primary)
	registry_closed, _ := editor_view.registry_close(&registry)
	buffer_closed, _ := editor.buffer_close(&buffer)
	testing.expect(t, additional_closed && primary_closed && registry_closed && buffer_closed)
}
