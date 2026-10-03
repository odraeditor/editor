// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../display"
import "../interaction"
import "../ui"
import "core:testing"

modal_replace_test_selectors := [2][1]interaction.Profile_State_Selector {
	{{profile_id = 2, state_id = 1}},
	{{profile_id = 2, state_id = 2}},
}

/* Verifies Replace transitions, Unicode edits, line-end insertion, history, and presentation. */
@(test)
modal_replace_uses_canonical_text_input :: proc(t: ^testing.T) {
	fixture, allocation_error := new(Interaction_Fixture, context.allocator)
	testing.expect(t, allocation_error == nil)
	if allocation_error != nil do return
	defer free(fixture, context.allocator)
	if !interaction_fixture_init(t, fixture, "é🙂x\nz") do return
	defer interaction_fixture_close(fixture)
	activation: interaction.Profile_Activation
	if !modal_replace_test_activate(t, fixture, &activation) do return
	defer interaction.profile_activation_close(&activation)
	constraints := display.Viewport_Constraints{width_cells = 80, height_rows = 24}

	modal_navigation_test_key(t, fixture, 'R', constraints)
	modal_replace_test_expect_state(t, fixture, "Replace")
	testing.expect_value(t, command_context_text_cursor_shape(&fixture.commands), ui.Text_Cursor_Shape.Underline)

	replaced, replace_failure := dispatch_input(
		&fixture.commands,
		&fixture.buffer,
		&fixture.registry,
		fixture.handle,
		interaction.Input{kind = .Text_Commit, text = "界a"},
		constraints,
	)
	testing.expectf(t, replaced.changed && replace_failure.stage == .None, "replace input failed at %v", replace_failure.stage)
	modal_operator_test_expect_text(t, fixture, "界ax\nz")

	modal_navigation_test_key(t, fixture, '$', constraints)
	inserted, insert_failure := dispatch_input(
		&fixture.commands,
		&fixture.buffer,
		&fixture.registry,
		fixture.handle,
		interaction.Input{kind = .Text_Commit, text = "!"},
		constraints,
	)
	testing.expectf(t, inserted.changed && insert_failure.stage == .None, "line-end input failed at %v", insert_failure.stage)
	modal_operator_test_expect_text(t, fixture, "界ax!\nz")

	modal_replace_test_escape(t, fixture, constraints)
	modal_replace_test_expect_state(t, fixture, "Normal")
	testing.expect_value(t, command_context_text_cursor_shape(&fixture.commands), ui.Text_Cursor_Shape.Block)
	modal_navigation_test_key(t, fixture, 'u', constraints)
	modal_operator_test_expect_text(t, fixture, "界ax\nz")
	modal_navigation_test_key(t, fixture, 'u', constraints)
	modal_operator_test_expect_text(t, fixture, "é🙂x\nz")
	modal_replace_test_redo(t, fixture, constraints)
	modal_operator_test_expect_text(t, fixture, "界ax\nz")
	modal_replace_test_redo(t, fixture, constraints)
	modal_operator_test_expect_text(t, fixture, "界ax!\nz")
	modal_navigation_test_key(t, fixture, '.', constraints)
	modal_operator_test_expect_text(t, fixture, "界ax!界a!\nz")
	modal_navigation_test_key(t, fixture, 'u', constraints)
	modal_operator_test_expect_text(t, fixture, "界ax!\nz")
}

/* Verifies unsupported counts leave Normal active and direct text input remains insertion. */
@(test)
modal_replace_preserves_count_and_direct_profile_boundaries :: proc(t: ^testing.T) {
	modal, modal_allocation_error := new(Interaction_Fixture, context.allocator)
	testing.expect(t, modal_allocation_error == nil)
	if modal_allocation_error != nil do return
	defer free(modal, context.allocator)
	if !interaction_fixture_init(t, modal, "ab") do return
	defer interaction_fixture_close(modal)
	activation: interaction.Profile_Activation
	if !modal_replace_test_activate(t, modal, &activation) do return
	defer interaction.profile_activation_close(&activation)
	constraints := display.Viewport_Constraints{width_cells = 80, height_rows = 24}

	modal_navigation_test_key(t, modal, '2', constraints)
	modal_navigation_test_key(t, modal, 'R', constraints)
	modal_replace_test_expect_state(t, modal, "Normal")
	testing.expect(t, modal.commands.diagnostic_length > 0)
	modal_operator_test_expect_text(t, modal, "ab")

	direct, direct_allocation_error := new(Interaction_Fixture, context.allocator)
	testing.expect(t, direct_allocation_error == nil)
	if direct_allocation_error != nil do return
	defer free(direct, context.allocator)
	if !interaction_fixture_init(t, direct, "ab") do return
	defer interaction_fixture_close(direct)
	inserted, insert_failure := dispatch_input(
		&direct.commands,
		&direct.buffer,
		&direct.registry,
		direct.handle,
		interaction.Input{kind = .Text_Commit, text = "R"},
		constraints,
	)
	testing.expectf(t, inserted.changed && insert_failure.stage == .None, "direct input failed at %v", insert_failure.stage)
	modal_operator_test_expect_text(t, direct, "Rab")
	testing.expect_value(t, command_context_text_cursor_shape(&direct.commands), ui.Text_Cursor_Shape.Default)
}

@(private)
modal_replace_test_activate :: proc(
	t: ^testing.T,
	fixture: ^Interaction_Fixture,
	activation: ^interaction.Profile_Activation,
) -> bool {
	bindings := [?]interaction.Layered_Binding_Definition {
		modal_replace_test_binding(1, 'R', "modal-enter-replace"),
		modal_replace_test_binding(1, '$', "cursor-line-end"),
		modal_replace_test_binding(1, 'u', "undo"),
		modal_replace_test_binding(1, '.', "modal-repeat-last-change"),
		modal_replace_test_binding(1, 'r', "redo", .Unicode_Scalar, {.Control}),
		modal_replace_test_binding(2, '$', "cursor-line-end"),
		modal_replace_test_binding(2, 0, "modal-enter-normal", .Escape),
	}
	states := [?]interaction.Interaction_State_Definition {
		{
			identity = {id = 1, revision = 1},
			name = "Normal",
			admitted_effects = {.Buffer, .View, .Lifecycle, .Text_Mutation},
			provenance = {provider = "test", source = "modal-replace"},
		},
		{
			identity = {id = 2, revision = 1},
			name = "Replace",
			admits_text_input = true,
			admitted_effects = {.Buffer, .View, .Lifecycle, .Text_Mutation},
			provenance = {provider = "test", source = "modal-replace"},
		},
	}
	maps := [?]interaction.Map_Definition {{
		identity = {id = 1, revision = 1},
		name = "modal-base",
		precedence = .Profile_Base,
		bindings = bindings[:],
		unmatched_input_policy = .Text_Input,
		provenance = {provider = "test", source = "modal-replace"},
	}}
	profiles := [?]interaction.Profile_Definition {{
		identity = {id = 2, revision = 1},
		name = "modal",
		states = states[:],
		initial_state = 1,
		maps = maps[:],
		text_fallback_name = "insert-text",
	}}
	surfaces := [?]interaction.Command_Entry_Surface_Definition {{
		identity = {id = 1, revision = 1},
		name = "extended-command",
		provenance = {provider = "test", source = "modal-replace"},
	}}
	closed, close_failure := interaction.snapshot_close(&fixture.keymap)
	testing.expectf(t, closed, "direct fixture snapshot close failed with %v", close_failure.code)
	if !closed do return false
	fixture.commands.keymap = nil
	interaction.profile_activation_init(activation)
	fixture.commands.active_interaction_context = {identity = {id = 1, generation = 1}}
	published, failure := interaction.profile_activation_replace_catalog(
		activation,
		&fixture.command_registry,
		interaction.Profile_Catalog_Definition {
			generation = 1,
			profiles = profiles[:],
			active_profile = 2,
			active_state = 1,
			surfaces = surfaces[:],
		},
		fixture.commands.active_interaction_context,
		&fixture.commands.pending,
		interaction.DEFAULT_PROFILE_COMPATIBILITY_POLICY,
		interaction.DEFAULT_RESOLUTION_POLICY,
		context.allocator,
	)
	testing.expectf(t, published, "modal replace activation failed with %v", failure.code)
	if !published do return false
	snapshot, active := interaction.profile_activation_snapshot(activation)
	testing.expect(t, active)
	if !active do return false
	fixture.commands.profile_activation = activation
	fixture.commands.keymap = snapshot
	return true
}

@(private)
modal_replace_test_binding :: proc(
	state_id: u64,
	value: rune,
	command_name: string,
	kind := interaction.Logical_Key_Kind.Unicode_Scalar,
	modifiers: interaction.Modifiers = {},
) -> interaction.Layered_Binding_Definition {
	return interaction.Layered_Binding_Definition {
		sequence = {
			strokes = {0 = {kind = kind, scalar = value, modifiers = modifiers}},
			stroke_count = 1,
		},
		command_name = command_name,
		operation = .Bind,
		scope = .State_Specific,
		selectors = modal_replace_test_selectors[state_id - 1][:],
		provenance = {provider = "test", source = "modal-replace"},
	}
}

@(private)
modal_replace_test_expect_state :: proc(
	t: ^testing.T,
	fixture: ^Interaction_Fixture,
	expected: string,
) {
	_, state, selected := interaction.profile_activation_selection(fixture.commands.profile_activation)
	testing.expect(t, selected)
	if selected do testing.expect_value(t, state.name, expected)
}

@(private)
modal_replace_test_escape :: proc(
	t: ^testing.T,
	fixture: ^Interaction_Fixture,
	constraints: display.Viewport_Constraints,
) {
	result, failure := dispatch_input(
		&fixture.commands,
		&fixture.buffer,
		&fixture.registry,
		fixture.handle,
		interaction.Input{kind = .Key, stroke = {kind = .Escape}},
		constraints,
	)
	testing.expectf(t, result.changed && failure.stage == .None, "replace cancel failed at %v", failure.stage)
}

@(private)
modal_replace_test_redo :: proc(
	t: ^testing.T,
	fixture: ^Interaction_Fixture,
	constraints: display.Viewport_Constraints,
) {
	result, failure := dispatch_input(
		&fixture.commands,
		&fixture.buffer,
		&fixture.registry,
		fixture.handle,
		interaction.Input {
			kind = .Key,
			stroke = {kind = .Unicode_Scalar, scalar = 'r', modifiers = {.Control}},
		},
		constraints,
	)
	testing.expectf(t, result.changed && failure.stage == .None, "replace redo failed at %v", failure.stage)
}
