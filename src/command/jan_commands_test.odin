// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../interaction"
import "core:testing"

/* Verifies the Stage 1 and complete Stage 2 public Jan catalog. */
@(test)
jan_commands_are_registered_and_contained :: proc(t: ^testing.T) {
	expected := [?]string {
		"jan-inspect-syntax",
		"jan-lint",
		"jan-lint-refresh",
		"jan-language-status",
	}
	definitions := native_command_definitions()
	for name in expected {
		found := false
		for definition in definitions {
			if definition.name != name do continue
			found = true
			testing.expect_value(t, definition.implementation, interaction.Implementation_Class.Native)
			testing.expect_value(t, definition.invocation, interaction.Invocation_Class.Ordinary)
			testing.expect_value(t, definition.text_requirement, interaction.Text_Requirement.Prohibited)
			testing.expect_value(t, definition.effects, interaction.Command_Effects{.Lifecycle})
			testing.expect(t, definition.interactive)
			route, decoded := native_route_decode(definition.route)
			testing.expect(t, decoded)
			testing.expect(t, route >= .Jan_Inspect_Syntax && route <= .Jan_Language_Status)
			break
		}
		testing.expectf(t, found, "missing public Jan command %s", name)
	}
	structured := jan_structured_command_definitions()
	testing.expect_value(t, len(structured), JAN_STRUCTURED_COMMAND_COUNT)
	drawer_toggle_found := false
	for definition, index in structured {
		testing.expect(t, len(definition.name) > len("jan-"))
		testing.expect(t, definition.name[:len("jan-")] == "jan-")
		testing.expect_value(t, definition.implementation, interaction.Implementation_Class.Native)
		testing.expect_value(t, definition.invocation, interaction.Invocation_Class.Ordinary)
		testing.expect_value(t, definition.text_requirement, interaction.Text_Requirement.Prohibited)
		route, decoded := native_route_decode(definition.route)
		testing.expect(t, decoded)
		testing.expect(
			t,
			(route >= .Jan_Cycle && route <= .Jan_Inspect_Availability) ||
			route == .Jan_Toggle_Drawer,
		)
		expected_effects := interaction.Command_Effects{.View, .Lifecycle}
		if jan_route_changes_source(route) {
			expected_effects = {.Buffer, .View, .Lifecycle, .Text_Mutation}
		}
		testing.expect_value(t, definition.effects, expected_effects)
		if definition.name == "jan-capture" || definition.name == "jan-feed-refresh" ||
		   definition.name == "jan-agenda" || definition.name == "jan-planning-status" {
			testing.expect_value(t, definition.requirements, interaction.Command_Requirements{})
		}
		if definition.name == "jan-toggle-drawer" {
			drawer_toggle_found = true
			testing.expect_value(t, route, Native_Route.Jan_Toggle_Drawer)
			testing.expect(t, !jan_route_changes_source(route))
		}
		for prior in structured[:index] do testing.expect(t, prior.name != definition.name)
	}
	testing.expect(t, drawer_toggle_found)
	planning := jan_planning_command_definitions()
	testing.expect_value(t, len(planning), JAN_PLANNING_COMMAND_COUNT)
	for definition, index in planning {
		testing.expect(t, len(definition.name) > len("jan-"))
		testing.expect(t, definition.name[:len("jan-")] == "jan-")
		testing.expect_value(t, definition.implementation, interaction.Implementation_Class.Native)
		testing.expect_value(t, definition.invocation, interaction.Invocation_Class.Ordinary)
		testing.expect_value(t, definition.text_requirement, interaction.Text_Requirement.Prohibited)
		route, decoded := native_route_decode(definition.route)
		testing.expect(t, decoded)
		testing.expect(t, native_route_is_jan_planning(route))
		expected_effects := interaction.Command_Effects{.View, .Lifecycle}
		if jan_route_changes_source(route) {
			expected_effects = {.Buffer, .View, .Lifecycle, .Text_Mutation}
		}
		testing.expect_value(t, definition.effects, expected_effects)
		for prior in structured do testing.expect(t, prior.name != definition.name)
		for prior in planning[:index] do testing.expect(t, prior.name != definition.name)
	}
	computation := jan_computation_command_definitions()
	testing.expect_value(t, len(computation), JAN_COMPUTATION_COMMAND_COUNT)
	for definition, index in computation {
		testing.expect(t, len(definition.name) > len("jan-"))
		testing.expect(t, definition.name[:len("jan-")] == "jan-")
		testing.expect_value(t, definition.implementation, interaction.Implementation_Class.Native)
		testing.expect_value(t, definition.invocation, interaction.Invocation_Class.Ordinary)
		testing.expect_value(t, definition.text_requirement, interaction.Text_Requirement.Prohibited)
		route, decoded := native_route_decode(definition.route)
		testing.expect(t, decoded)
		testing.expect(t, native_route_is_jan_computation(route))
		expected_effects := interaction.Command_Effects{.View, .Lifecycle}
		if jan_route_changes_source(route) do expected_effects = {.Buffer, .View, .Lifecycle, .Text_Mutation}
		testing.expect_value(t, definition.effects, expected_effects)
		for prior in structured do testing.expect(t, prior.name != definition.name)
		for prior in planning do testing.expect(t, prior.name != definition.name)
		for prior in computation[:index] do testing.expect(t, prior.name != definition.name)
	}
	output := jan_output_command_definitions()
	testing.expect_value(t, len(output), JAN_OUTPUT_COMMAND_COUNT)
	for definition, index in output {
		testing.expect(t, len(definition.name) > len("jan-"))
		testing.expect(t, definition.name[:len("jan-")] == "jan-")
		testing.expect_value(t, definition.implementation, interaction.Implementation_Class.Native)
		testing.expect_value(t, definition.invocation, interaction.Invocation_Class.Ordinary)
		testing.expect_value(t, definition.text_requirement, interaction.Text_Requirement.Prohibited)
		route, decoded := native_route_decode(definition.route)
		testing.expect(t, decoded)
		testing.expect(t, native_route_is_jan_output(route))
		expected_effects := interaction.Command_Effects{.View, .Lifecycle}
		if jan_route_changes_source(route) do expected_effects = {.Buffer, .View, .Lifecycle, .Text_Mutation}
		testing.expect_value(t, definition.effects, expected_effects)
		for prior in structured do testing.expect(t, prior.name != definition.name)
		for prior in planning do testing.expect(t, prior.name != definition.name)
		for prior in computation do testing.expect(t, prior.name != definition.name)
		for prior in output[:index] do testing.expect(t, prior.name != definition.name)
	}
}
