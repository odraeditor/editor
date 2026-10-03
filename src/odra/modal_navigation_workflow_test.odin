// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../display"
import "../editor"
import "../interaction"
import editor_view "../view"
import "core:testing"
import "core:unicode/utf8"

/* Verifies modal counts and line-character targets dispatch through canonical movement. */
@(test)
modal_counts_and_character_search_dispatch :: proc(t: ^testing.T) {
	fixture, allocation_error := new(Interaction_Fixture, context.allocator)
	testing.expect(t, allocation_error == nil)
	if allocation_error != nil do return
	defer free(fixture, context.allocator)
	if !interaction_fixture_init(t, fixture, "alpha tone alpha tone") do return
	defer interaction_fixture_close(fixture)
	activation: interaction.Profile_Activation
	if !modal_navigation_test_activate(t, fixture, &activation) do return
	defer interaction.profile_activation_close(&activation)
	constraints := display.Viewport_Constraints{width_cells = 80, height_rows = 24}

	modal_navigation_test_key(t, fixture, '2', constraints)
	modal_navigation_test_key(t, fixture, 'w', constraints)
	modal_navigation_test_expect_point(t, fixture, 11)
	modal_navigation_test_key(t, fixture, '0', constraints)
	modal_navigation_test_expect_point(t, fixture, 0)
	modal_navigation_test_key(t, fixture, '2', constraints)
	modal_navigation_test_key(t, fixture, 'f', constraints)
	modal_navigation_test_key(t, fixture, 'a', constraints)
	modal_navigation_test_expect_point(t, fixture, 11)
	modal_navigation_test_key(t, fixture, ';', constraints)
	modal_navigation_test_expect_point(t, fixture, 15)
	modal_navigation_test_key(t, fixture, ',', constraints)
	modal_navigation_test_expect_point(t, fixture, 11)
	modal_navigation_test_key(t, fixture, 'f', constraints)
	modal_navigation_test_key(t, fixture, 'z', constraints)
	modal_navigation_test_expect_point(t, fixture, 11)
	modal_navigation_test_key(t, fixture, 'G', constraints)
	modal_navigation_test_expect_point(t, fixture, 21)
	modal_navigation_test_key(t, fixture, 'g', constraints)
	modal_navigation_test_key(t, fixture, 'g', constraints)
	modal_navigation_test_expect_point(t, fixture, 0)
}

/* Verifies modal search reuses accepted canonical history without retaining a prompt. */
@(test)
modal_navigation_repeats_confirmed_search :: proc(t: ^testing.T) {
	fixture, allocation_error := new(Interaction_Fixture, context.allocator)
	testing.expect(t, allocation_error == nil)
	if allocation_error != nil do return
	defer free(fixture, context.allocator)
	if !interaction_fixture_init(t, fixture, "alpha beta alpha beta") do return
	defer interaction_fixture_close(fixture)
	activation: interaction.Profile_Activation
	if !modal_navigation_test_activate(t, fixture, &activation) do return
	defer interaction.profile_activation_close(&activation)
	constraints := display.Viewport_Constraints{width_cells = 80, height_rows = 24}

	modal_navigation_test_key(t, fixture, '/', constraints)
	result, failure := dispatch_input(
		&fixture.commands,
		&fixture.buffer,
		&fixture.registry,
		fixture.handle,
		interaction.Input{kind = .Text_Commit, text = "beta"},
		constraints,
	)
	testing.expectf(t, result.changed && failure.stage == .None, "modal search failed at %v", failure.stage)
	modal_navigation_test_expect_point(t, fixture, 10)
	result, failure = dispatch_input(
		&fixture.commands,
		&fixture.buffer,
		&fixture.registry,
		fixture.handle,
		interaction.Input{kind = .Key, stroke = {kind = .Enter}},
		constraints,
	)
	testing.expectf(t, result.changed && failure.stage == .None, "modal search accept failed at %v", failure.stage)
	testing.expect_value(t, fixture.commands.prompt_workflow.mode, Prompt_Mode.None)

	modal_navigation_test_key(t, fixture, 'n', constraints)
	modal_navigation_test_expect_point(t, fixture, 21)
	testing.expect_value(t, fixture.commands.prompt_workflow.mode, Prompt_Mode.None)
	modal_navigation_test_key(t, fixture, 'N', constraints)
	modal_navigation_test_expect_point(t, fixture, 17)
	testing.expect_value(t, fixture.commands.prompt_workflow.mode, Prompt_Mode.None)
}

@(private)
modal_navigation_test_activate :: proc(
	t: ^testing.T,
	fixture: ^Interaction_Fixture,
	activation: ^interaction.Profile_Activation,
) -> bool {
	bindings := [22]interaction.Layered_Binding_Definition {
		modal_navigation_test_binding('h', "cursor-previous-grapheme"),
		modal_navigation_test_binding('j', "cursor-next-line"),
		modal_navigation_test_binding('k', "cursor-previous-line"),
		modal_navigation_test_binding('l', "cursor-next-grapheme"),
		modal_navigation_test_binding('0', "cursor-line-start"),
		modal_navigation_test_binding('$', "cursor-line-end"),
		modal_navigation_test_binding('^', "cursor-line-first-non-whitespace"),
		modal_navigation_test_binding('w', "cursor-next-word-start"),
		modal_navigation_test_binding('b', "cursor-previous-word"),
		modal_navigation_test_binding('e', "cursor-word-end"),
		modal_navigation_test_pair('g', 'g', "cursor-buffer-start"),
		modal_navigation_test_binding('G', "cursor-buffer-end"),
		modal_navigation_test_binding('/', "isearch-forward"),
		modal_navigation_test_binding('?', "isearch-backward"),
		modal_navigation_test_binding('n', "search-next-occurrence"),
		modal_navigation_test_binding('N', "search-previous-occurrence"),
		modal_navigation_test_binding('x', "delete-next-grapheme"),
		modal_navigation_test_binding('X', "delete-previous-grapheme"),
		modal_navigation_test_binding('p', "yank-after-point"),
		modal_navigation_test_binding('P', "yank"),
		modal_navigation_test_binding('u', "undo"),
		{
			sequence = {
				strokes = {0 = {kind = .Unicode_Scalar, scalar = 'r', modifiers = {.Control}}},
				stroke_count = 1,
			},
			command_name = "redo",
			operation = .Bind,
			scope = .Profile_Specific,
			provenance = {provider = "test", source = "modal-navigation"},
		},
	}
	states := [1]interaction.Interaction_State_Definition {{
		identity = {id = 1, revision = 1},
		name = "Normal",
		admitted_effects = {.Buffer, .View, .Lifecycle, .Text_Mutation},
		provenance = {provider = "test", source = "modal-navigation"},
	}}
	maps := [1]interaction.Map_Definition {{
		identity = {id = 1, revision = 1},
		name = "modal-base",
		precedence = .Profile_Base,
		bindings = bindings[:],
		unmatched_input_policy = .Reject,
		provenance = {provider = "test", source = "modal-navigation"},
	}}
	profiles := [1]interaction.Profile_Definition {{
		identity = {id = 2, revision = 1},
		name = "modal",
		states = states[:],
		initial_state = 1,
		maps = maps[:],
		text_fallback_name = "insert-text",
	}}
	surfaces := [1]interaction.Command_Entry_Surface_Definition {{
		identity = {id = 1, revision = 1},
		name = "extended-command",
		provenance = {provider = "test", source = "modal-navigation"},
	}}
	closed, close_failure := interaction.snapshot_close(&fixture.keymap)
	testing.expectf(t, closed, "direct fixture snapshot close failed with %v", close_failure.code)
	if !closed do return false
	fixture.commands.keymap = nil
	interaction.profile_activation_init(activation)
	fixture.commands.active_interaction_context = {
		identity = {id = 1, generation = 1},
	}
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
	testing.expectf(t, published, "modal navigation activation failed with %v", failure.code)
	if !published do return false
	snapshot, active := interaction.profile_activation_snapshot(activation)
	testing.expect(t, active)
	if !active do return false
	fixture.commands.profile_activation = activation
	fixture.commands.keymap = snapshot
	return true
}

@(private)
modal_navigation_test_binding :: proc(
	value: rune,
	command_name: string,
) -> interaction.Layered_Binding_Definition {
	return interaction.Layered_Binding_Definition {
		sequence = {
			strokes = {0 = {kind = .Unicode_Scalar, scalar = value}},
			stroke_count = 1,
		},
		command_name = command_name,
		operation = .Bind,
		scope = .Profile_Specific,
		provenance = {provider = "test", source = "modal-navigation"},
	}
}

@(private)
modal_navigation_test_pair :: proc(
	first: rune,
	second: rune,
	command_name: string,
) -> interaction.Layered_Binding_Definition {
	result := modal_navigation_test_binding(first, command_name)
	result.sequence.strokes[1] = {kind = .Unicode_Scalar, scalar = second}
	result.sequence.stroke_count = 2
	return result
}

@(private)
modal_navigation_test_key :: proc(
	t: ^testing.T,
	fixture: ^Interaction_Fixture,
	value: rune,
	constraints: display.Viewport_Constraints,
) {
	encoded, encoded_count := utf8.encode_rune(value)
	_, failure := dispatch_input(
		&fixture.commands,
		&fixture.buffer,
		&fixture.registry,
		fixture.handle,
		interaction.Input {
			kind = .Key,
			stroke = {kind = .Unicode_Scalar, scalar = value},
			text = string(encoded[:encoded_count]),
		},
		constraints,
	)
	rejection := interaction.profile_activation_last_rejection(fixture.commands.profile_activation)
	testing.expectf(
		t,
		failure.stage == .None,
		"modal key %c failed at %v with rejection %v",
		value,
		failure.stage,
		rejection.code,
	)
	testing.expectf(
		t,
		rejection.code == .None,
		"modal key %c rejected with %v",
		value,
		rejection.code,
	)
}

@(private)
modal_navigation_test_expect_point :: proc(
	t: ^testing.T,
	fixture: ^Interaction_Fixture,
	expected: u64,
) {
	logical, viewed, failure := editor_view.snapshot(&fixture.registry, fixture.handle)
	testing.expectf(t, viewed, "modal point inspection failed with %v", failure.code)
	if viewed {
		rejection := interaction.profile_activation_last_rejection(fixture.commands.profile_activation)
		testing.expectf(
			t,
			logical.point_position.byte_offset == editor.Byte_Offset(expected),
			"modal point expected %d, got %d; diagnostic=%q rejection=%v",
			expected,
			logical.point_position.byte_offset,
			string(fixture.commands.diagnostic[:fixture.commands.diagnostic_length]),
			rejection.code,
		)
	}
}
