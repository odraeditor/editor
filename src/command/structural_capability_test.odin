// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../editor"
import "../interaction"
import editor_view "../view"
import "core:testing"

/* Verifies the six structural names resolve to canonical native routes and exact effects. */
@(test)
structural_routes_match_registry :: proc(t: ^testing.T) {
	definitions := native_command_definitions()
	registry: interaction.Command_Registry
	ready, failure := interaction.command_registry_init(
		&registry,
		interaction.Registry_Generation(31),
		definitions[:],
		context.allocator,
	)
	testing.expectf(t, ready, "structural registry setup failed with %v", failure.code)
	if !ready do return
	defer interaction.command_registry_close(&registry)

	names := [?]string {
		"structural-forward",
		"structural-backward",
		"structural-up",
		"structural-down",
		"structural-select",
		"structural-indent",
	}
	routes := [?]Native_Route {
		.Structural_Forward,
		.Structural_Backward,
		.Structural_Up,
		.Structural_Down,
		.Structural_Select,
		.Structural_Indent,
	}
	for name, index in names {
		handle, found, _ := interaction.command_lookup(&registry, name)
		testing.expectf(t, found, "missing structural command %s", name)
		if !found do continue
		metadata, inspected, _ := interaction.command_metadata(&registry, handle)
		testing.expect(t, inspected)
		if !inspected do continue
		route, decoded := native_route_decode(metadata.route)
		testing.expect(t, decoded)
		testing.expect_value(t, route, routes[index])
		testing.expect_value(t, metadata.implementation, interaction.Implementation_Class.Native)
		expected_effects: interaction.Command_Effects = {.View}
		if route == .Structural_Indent {
			expected_effects = {.Buffer, .View, .Text_Mutation}
		}
		testing.expect_value(t, metadata.effects, expected_effects)
	}
}

/* Verifies native and programmable routing share one generation-checked semantic owner. */
@(test)
structural_routes_share_semantic_owner :: proc(t: ^testing.T) {
	contents := "package demo\nmain :: proc() {\n    alpha := 1\n}\n"
	fixture: Structural_Editor_Test_Fixture
	if !structural_editor_test_open(t, &fixture, 831, contents) do return
	defer structural_editor_test_close(&fixture)
	definitions := native_command_definitions()
	registry: interaction.Command_Registry
	ready, failure := interaction.command_registry_init(
		&registry,
		interaction.Registry_Generation(32),
		definitions[:],
		context.allocator,
	)
	testing.expectf(t, ready, "structural registry setup failed with %v", failure.code)
	if !ready do return
	defer interaction.command_registry_close(&registry)
	forward, found, _ := interaction.command_lookup(&registry, "structural-forward")
	testing.expect(t, found)
	if !found do return

	request := fixture.ctx.native
	request.registry = &registry
	request.command = forward
	request.language_owner = &fixture.owner
	request.language_source = &fixture.source
	request.structural_scope = fixture.analysis
	result, executed, execute_failure := native_command_execute(request)
	testing.expectf(
		t,
		executed,
		"native structural route failed with %v/%v",
		execute_failure.structural_code,
		execute_failure.language_code,
	)
	if executed {
		testing.expect_value(t, result.completion, Native_Completion.View_Changed)
		native_result_close(&result)
	}

	state: Structural_Capability_State
	capability := Structural_Capability_Context {
		editor_session_id = Editor_Session_ID(41),
		access = {.Inspect, .Forward},
		capability_generation = 7,
		editor = fixture.ctx,
		state = &state,
	}
	capability.editor.native.registry = &registry
	capability.editor.native.command = forward
	scope, scoped, scope_failure := structural_capability_scope(capability)
	testing.expectf(t, scoped, "structural scope failed with %v", scope_failure.code)
	if !scoped do return
	inspection, inspected, inspection_failure := structural_capability_inspect(capability, scope)
	testing.expectf(t, inspected, "structural inspection failed with %v", inspection_failure.code)
	if inspected {
		testing.expect_value(t, inspection.scope, scope)
	}
	stale := scope
	stale.capability_generation += 1
	_, accepted, stale_failure := structural_capability_inspect(capability, stale)
	testing.expect(t, !accepted)
	testing.expect_value(
		t,
		stale_failure.structural_capability_code,
		Structural_Capability_Failure_Code.Stale_Capability,
	)
	wrong_authority := scope
	wrong_authority.access = {.Inspect}
	_, authorized, authority_failure := structural_capability_inspect(
		capability,
		wrong_authority,
	)
	testing.expect(t, !authorized)
	testing.expect_value(
		t,
		authority_failure.structural_capability_code,
		Structural_Capability_Failure_Code.Wrong_Authority,
	)
	position, _, _ := editor.buffer_position(&fixture.buffer, 1)
	editor_view.move_point(&fixture.views, fixture.view, position, 1, .Deactivate)
	_, current, current_failure := structural_capability_inspect(capability, scope)
	testing.expect(t, !current)
	testing.expect_value(
		t,
		current_failure.structural_capability_code,
		Structural_Capability_Failure_Code.Stale_Selection,
	)
	restricted := capability
	restricted.access = {.Inspect}
	restricted_scope, restricted_ok, _ := structural_capability_scope(restricted)
	testing.expect(t, restricted_ok)
	_, invoked, invocation_failure := structural_capability_invoke(
		restricted,
		restricted_scope,
		.Forward,
	)
	testing.expect(t, !invoked)
	testing.expect_value(
		t,
		invocation_failure.structural_capability_code,
		Structural_Capability_Failure_Code.Permission_Denied,
	)
}
