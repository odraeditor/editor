// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../interaction"
import "core:testing"

/* Completion commands remain semantic registry entries independent of bindings. */
@(test)
completion_commands_use_exact_routes :: proc(t: ^testing.T) {
	definitions := native_command_definitions()
	cases := [?]struct {
		name:  string,
		route: Native_Route,
	} {
		{"complete-at-point", .Complete_At_Point},
		{"completion-next", .Completion_Next},
		{"completion-previous", .Completion_Previous},
		{"completion-first", .Completion_First},
		{"completion-last", .Completion_Last},
		{"completion-accept", .Completion_Accept},
		{"completion-cancel", .Completion_Cancel},
		{"completion-inspect", .Completion_Inspect},
		{"completion-show-documentation", .Completion_Show_Documentation},
		{"describe-completion-state", .Describe_Completion_State},
	}
	for test_case in cases {
		found := false
		for definition in definitions {
			if definition.name != test_case.name {
				continue
			}
			route, decoded := native_route_decode(definition.route)
			testing.expect(t, decoded)
			testing.expect_value(t, route, test_case.route)
			testing.expect(t, definition.interactive)
			found = true
			break
		}
		testing.expectf(t, found, "missing completion command %s", test_case.name)
	}
}

/* Native completion commands defer semantic work to the application coordinator. */
@(test)
completion_commands_request_coordinator_dispatch :: proc(t: ^testing.T) {
	fixture: Native_Fixture
	if !native_fixture_init(t, &fixture, "package main\n", context.allocator) do return
	defer native_fixture_close(t, &fixture)
	names := [?]string {
		"complete-at-point",
		"completion-next",
		"completion-previous",
		"completion-first",
		"completion-last",
		"completion-accept",
		"completion-cancel",
		"completion-inspect",
		"completion-show-documentation",
		"describe-completion-state",
	}
	for name in names {
		result, executed, failure := execute_named(&fixture, name)
		testing.expectf(t, executed, "%s failed with %v", name, failure.code)
		if executed {
			testing.expect_value(t, result.completion, Native_Completion.Completion_Command_Requested)
		}
	}
}

/* The completion map owns local navigation and lets ordinary source input fall through. */
@(test)
completion_context_map_matches_factory_contract :: proc(t: ^testing.T) {
	value: Completion_Context_Map
	testing.expect(t, completion_context_map_init(&value))
	testing.expect_value(t, value.definition.identity.id, COMPLETION_CONTEXT_MAP_ID)
	testing.expect_value(t, value.definition.owner_id, COMPLETION_CONTEXT_OWNER_ID)
	testing.expect_value(
		t,
		value.definition.precedence,
		interaction.Precedence_Class.Transient_Interaction,
	)
	testing.expect_value(
		t,
		value.definition.unmatched_input_policy,
		interaction.Unmatched_Input_Policy.Fallthrough,
	)
	testing.expect_value(t, len(value.definition.bindings), COMPLETION_CONTEXT_BINDING_COUNT)
	testing.expect_value(t, value.definition.text_fallback_name, "")

	expected := [?]struct {
		kind:      interaction.Logical_Key_Kind,
		scalar:    rune,
		modifiers: interaction.Modifiers,
		command:   string,
	} {
		{.Unicode_Scalar, 'n', {.Control}, "completion-next"},
		{.Down, 0, {}, "completion-next"},
		{.Unicode_Scalar, 'p', {.Control}, "completion-previous"},
		{.Up, 0, {}, "completion-previous"},
		{.Unicode_Scalar, '<', {.Meta}, "completion-first"},
		{.Unicode_Scalar, '>', {.Meta}, "completion-last"},
		{.Enter, 0, {}, "completion-accept"},
		{.Tab, 0, {}, "completion-accept"},
		{.Unicode_Scalar, '?', {.Meta}, "completion-show-documentation"},
	}
	for test_case, index in expected {
		binding := value.definition.bindings[index]
		testing.expect_value(t, binding.stroke_count, u8(1))
		testing.expect_value(t, binding.strokes[0].kind, test_case.kind)
		testing.expect_value(t, binding.strokes[0].scalar, test_case.scalar)
		testing.expect_value(t, binding.strokes[0].modifiers, test_case.modifiers)
		testing.expect_value(t, binding.command_name, test_case.command)
	}
	for binding in value.definition.bindings {
		stroke := binding.strokes[0]
		is_protected_cancel := stroke.kind == .Unicode_Scalar && stroke.scalar == 'g' &&
		                      stroke.modifiers == interaction.Modifiers{.Control}
		testing.expect(t, !is_protected_cancel)
	}
	protected := interaction.protected_binding_catalog()
	testing.expect_value(t, protected[0].command_name, "keyboard-quit")
	testing.expect_value(t, protected[0].sequence.strokes[0].scalar, 'g')
}
