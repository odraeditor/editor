// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "core:strings"
import "core:testing"
import "../interaction"

/* Verifies every live terminal command is a canonical discoverable native identity. */
@(test)
terminal_commands_register_canonical_catalog_metadata :: proc(t: ^testing.T) {
	fixture: Native_Fixture
	if !native_fixture_init(t, &fixture, "terminal", context.allocator) do return
	defer native_fixture_close(t, &fixture)

	names := []string {
		"terminal-open",
		"terminal-new",
		"terminal-open-here",
		"terminal-open-project",
		"terminal-open-other-pane",
		"terminal-toggle",
		"terminal-list",
		"terminal-rename",
		"terminal-copy-mode",
		"terminal-copy-mode-done",
		"terminal-yank",
		"terminal-yank-pop",
		"terminal-beginning-of-line",
		"terminal-end-of-line",
		"terminal-reset-cursor-point",
		"terminal-next-prompt",
		"terminal-previous-prompt",
		"terminal-next-error",
		"terminal-open-link",
		"terminal-clear",
		"terminal-clear-scrollback",
		"terminal-send-next-key",
		"terminal-send-return",
		"terminal-send-tab",
		"terminal-send-escape",
		"terminal-send-backspace",
		"terminal-send-delete",
		"terminal-send-up",
		"terminal-send-down",
		"terminal-send-left",
		"terminal-send-right",
		"terminal-send-prior",
		"terminal-send-next",
		"terminal-send-space",
		"terminal-undo",
		"terminal-terminate",
	}
	for name in names {
		handle, found, lookup_failure := interaction.command_lookup(&fixture.command_registry, name)
		testing.expectf(t, found, "%s lookup failed with %v", name, lookup_failure.code)
		if !found do continue
		metadata, described, metadata_failure := interaction.command_metadata(
			&fixture.command_registry,
			handle,
		)
		testing.expectf(t, described, "%s metadata failed with %v", name, metadata_failure.code)
		if !described do continue
		testing.expect(t, metadata.interactive)
		testing.expect_value(t, metadata.implementation, interaction.Implementation_Class.Native)
		testing.expect_value(t, metadata.invocation, interaction.Invocation_Class.Ordinary)
		testing.expect_value(t, metadata.text_requirement, interaction.Text_Requirement.Prohibited)
		testing.expect(t, strings.has_prefix(metadata.name, "terminal-"))
		route, decoded := native_route_decode(metadata.route)
		testing.expect(t, decoded && native_route_is_terminal(route))

		result, executed, execute_failure := execute_named(&fixture, name)
		testing.expectf(t, executed, "%s dispatch failed with %v", name, execute_failure.code)
		if executed do testing.expect_value(t, result.completion, Native_Completion.Terminal_Command_Requested)
	}
	_, alias_found, _ := interaction.command_lookup(&fixture.command_registry, "term-open")
	testing.expect(t, !alias_found)
}

/* Verifies only active-session operations require a terminal context. */
@(test)
terminal_commands_declare_contextual_availability :: proc(t: ^testing.T) {
	definitions := native_command_definitions()
	general_names := [?]string {
		"terminal-open",
		"terminal-new",
		"terminal-open-here",
		"terminal-open-project",
		"terminal-open-other-pane",
		"terminal-toggle",
		"terminal-list",
		"shell-command",
		"async-shell-command",
		"compile",
		"recompile",
	}
	general := 0
	for definition in definitions {
		route, decoded := native_route_decode(definition.route)
		if !decoded || !native_route_is_terminal(route) do continue
		is_general := false
		for name in general_names {
			if definition.name == name {
				is_general = true
				break
			}
		}
		if is_general {
			general += 1
			testing.expect(t, .Active_Terminal not_in definition.requirements)
		} else {
			testing.expect(t, .Active_Buffer in definition.requirements)
			testing.expect(t, .Active_Terminal in definition.requirements)
		}
	}
	testing.expect_value(t, general, len(general_names))
}
