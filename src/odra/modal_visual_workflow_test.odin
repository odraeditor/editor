// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../display"
import "../editor"
import "../interaction"
import "../kill_ring"
import editor_view "../view"
import "core:testing"

modal_visual_test_selectors := [5][1]interaction.Profile_State_Selector {
	{{profile_id = 2, state_id = 1}},
	{{profile_id = 2, state_id = 2}},
	{{profile_id = 2, state_id = 3}},
	{{profile_id = 2, state_id = 4}},
	{{profile_id = 2, state_id = 5}},
}

/* Verifies Visual Character movement and operators use the canonical linear selection. */
@(test)
modal_visual_character_uses_canonical_region :: proc(t: ^testing.T) {
	fixture, allocation_error := new(Interaction_Fixture, context.allocator)
	testing.expect(t, allocation_error == nil)
	if allocation_error != nil do return
	defer free(fixture, context.allocator)
	if !interaction_fixture_init(t, fixture, "abc\ndef\n") do return
	defer interaction_fixture_close(fixture)
	activation: interaction.Profile_Activation
	if !modal_visual_test_activate(t, fixture, &activation) do return
	defer interaction.profile_activation_close(&activation)
	ring: kill_ring.Ring
	ring_ok, ring_failure := kill_ring.ring_init(
		&ring,
		kill_ring.Ring_ID(7_401),
		kill_ring.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	testing.expectf(t, ring_ok, "visual kill ring failed with %v", ring_failure.code)
	if !ring_ok do return
	defer kill_ring.ring_close(&ring)
	fixture.commands.kill_ring = &ring
	constraints := display.Viewport_Constraints{width_cells = 80, height_rows = 24}

	modal_navigation_test_key(t, fixture, 'v', constraints)
	modal_visual_test_expect_state(t, fixture, "Visual Character", true, 0, 1)
	modal_navigation_test_key(t, fixture, 'l', constraints)
	modal_visual_test_expect_state(t, fixture, "Visual Character", true, 0, 2)
	modal_navigation_test_key(t, fixture, 'h', constraints)
	modal_visual_test_expect_state(t, fixture, "Visual Character", true, 0, 1)
	modal_navigation_test_key(t, fixture, 'y', constraints)
	modal_visual_test_expect_state(t, fixture, "Normal", false, 0, 1)

	modal_navigation_test_key(t, fixture, 'v', constraints)
	modal_navigation_test_key(t, fixture, 'l', constraints)
	modal_navigation_test_key(t, fixture, 'd', constraints)
	modal_operator_test_expect_text(t, fixture, "a\ndef\n")
	modal_visual_test_expect_state(t, fixture, "Normal", false, 0, 0)
}

/* Verifies Visual Line materialization, active-end exchange, and cancellation. */
@(test)
modal_visual_line_materializes_complete_lines :: proc(t: ^testing.T) {
	fixture, allocation_error := new(Interaction_Fixture, context.allocator)
	testing.expect(t, allocation_error == nil)
	if allocation_error != nil do return
	defer free(fixture, context.allocator)
	if !interaction_fixture_init(t, fixture, "one\ntwo\nthree\n") do return
	defer interaction_fixture_close(fixture)
	activation: interaction.Profile_Activation
	if !modal_visual_test_activate(t, fixture, &activation) do return
	defer interaction.profile_activation_close(&activation)
	constraints := display.Viewport_Constraints{width_cells = 80, height_rows = 24}

	modal_navigation_test_key(t, fixture, 'V', constraints)
	modal_visual_test_expect_state(t, fixture, "Visual Line", true, 0, 4)
	modal_navigation_test_key(t, fixture, 'j', constraints)
	modal_visual_test_expect_state(t, fixture, "Visual Line", true, 0, 8)
	modal_navigation_test_key(t, fixture, 'o', constraints)
	modal_visual_test_expect_state(t, fixture, "Visual Line", true, 0, 8)
	modal_visual_test_escape(t, fixture, constraints)
	modal_visual_test_expect_state(t, fixture, "Normal", false, 0, 8)

	modal_navigation_test_key(t, fixture, 'V', constraints)
	modal_navigation_test_key(t, fixture, 'v', constraints)
	modal_visual_test_expect_state(t, fixture, "Visual Character", true, 0, 1)
}

/* Verifies Visual Block materializes a canonical rectangular selection. */
@(test)
modal_visual_block_uses_canonical_rectangle :: proc(t: ^testing.T) {
	fixture, allocation_error := new(Interaction_Fixture, context.allocator)
	testing.expect(t, allocation_error == nil)
	if allocation_error != nil do return
	defer free(fixture, context.allocator)
	if !interaction_fixture_init(t, fixture, "abcd\nxy\nαβγδ\n") do return
	defer interaction_fixture_close(fixture)
	activation: interaction.Profile_Activation
	if !modal_visual_test_activate(t, fixture, &activation) do return
	defer interaction.profile_activation_close(&activation)
	constraints := display.Viewport_Constraints{width_cells = 80, height_rows = 24}

	modal_navigation_test_key(t, fixture, 'B', constraints)
	modal_visual_test_expect_state(t, fixture, "Visual Block", true, 0, 0)
	modal_navigation_test_key(t, fixture, 'l', constraints)
	modal_navigation_test_key(t, fixture, 'j', constraints)
	modal_visual_test_expect_state(t, fixture, "Visual Block", true, 0, 6)
	logical, viewed, _ := editor_view.snapshot(&fixture.registry, fixture.handle)
	testing.expect(t, viewed)
	testing.expect_value(t, logical.selection_shape, editor.Selection_Shape.Rectangle)
	testing.expect_value(
		t, logical.rectangle_column_policy, editor.Rectangle_Column_Policy.Grapheme,
	)
	modal_visual_test_escape(t, fixture, constraints)
	modal_visual_test_expect_state(t, fixture, "Normal", false, 0, 6)
}

@(private)
modal_visual_test_activate :: proc(
	t: ^testing.T,
	fixture: ^Interaction_Fixture,
	activation: ^interaction.Profile_Activation,
) -> bool {
	bindings := [?]interaction.Layered_Binding_Definition {
		modal_visual_test_binding(1, 'v', "modal-enter-visual-character"),
		modal_visual_test_binding(1, 'V', "modal-enter-visual-line"),
		modal_visual_test_binding(1, 'B', "modal-enter-visual-block"),
		modal_visual_test_binding(3, 'h', "cursor-previous-grapheme"),
		modal_visual_test_binding(3, 'l', "cursor-next-grapheme"),
		modal_visual_test_binding(3, 'd', "kill-region"),
		modal_visual_test_binding(3, 'y', "copy-region"),
		modal_visual_test_binding(4, 'j', "cursor-next-line"),
		modal_visual_test_binding(4, 'o', "exchange-point-and-mark"),
		modal_visual_test_binding(4, 'v', "modal-enter-visual-character"),
		modal_visual_test_binding(4, 0, "modal-enter-normal", .Escape),
		modal_visual_test_binding(5, 'j', "cursor-next-line"),
		modal_visual_test_binding(5, 'l', "cursor-next-grapheme"),
		modal_visual_test_binding(5, 0, "modal-enter-normal", .Escape),
	}
	states := [?]interaction.Interaction_State_Definition {
		{identity = {id = 1, revision = 1}, name = "Normal", admitted_effects = {.Buffer, .View, .Lifecycle, .Text_Mutation}, provenance = {provider = "test", source = "modal-visual"}},
		{identity = {id = 2, revision = 1}, name = "Insert", admits_text_input = true, admitted_effects = {.Buffer, .View, .Lifecycle, .Text_Mutation}, provenance = {provider = "test", source = "modal-visual"}},
		{identity = {id = 3, revision = 1}, name = "Visual Character", admitted_effects = {.Buffer, .View, .Lifecycle, .Text_Mutation}, provenance = {provider = "test", source = "modal-visual"}},
		{identity = {id = 4, revision = 1}, name = "Visual Line", admitted_effects = {.Buffer, .View, .Lifecycle, .Text_Mutation}, provenance = {provider = "test", source = "modal-visual"}},
		{identity = {id = 5, revision = 1}, name = "Visual Block", admitted_effects = {.Buffer, .View, .Lifecycle, .Text_Mutation}, provenance = {provider = "test", source = "modal-visual"}},
	}
	maps := [?]interaction.Map_Definition {{
		identity = {id = 1, revision = 1},
		name = "modal-base",
		precedence = .Profile_Base,
		bindings = bindings[:],
		unmatched_input_policy = .Text_Input,
		provenance = {provider = "test", source = "modal-visual"},
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
		provenance = {provider = "test", source = "modal-visual"},
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
	testing.expectf(t, published, "modal visual activation failed with %v", failure.code)
	if !published do return false
	snapshot, active := interaction.profile_activation_snapshot(activation)
	testing.expect(t, active)
	if !active do return false
	fixture.commands.profile_activation = activation
	fixture.commands.keymap = snapshot
	return true
}

@(private)
modal_visual_test_binding :: proc(
	state_id: u64,
	value: rune,
	command_name: string,
	kind := interaction.Logical_Key_Kind.Unicode_Scalar,
) -> interaction.Layered_Binding_Definition {
	return interaction.Layered_Binding_Definition {
		sequence = {
			strokes = {0 = {kind = kind, scalar = value}},
			stroke_count = 1,
		},
		command_name = command_name,
		operation = .Bind,
		scope = .State_Specific,
		selectors = modal_visual_test_selectors[state_id - 1][:],
		provenance = {provider = "test", source = "modal-visual"},
	}
}

@(private)
modal_visual_test_escape :: proc(
	t: ^testing.T,
	fixture: ^Interaction_Fixture,
	constraints: display.Viewport_Constraints,
) {
	_, failure := dispatch_input(
		&fixture.commands,
		&fixture.buffer,
		&fixture.registry,
		fixture.handle,
		interaction.Input{kind = .Key, stroke = {kind = .Escape}},
		constraints,
	)
	testing.expectf(t, failure.stage == .None, "modal visual Escape failed at %v", failure.stage)
}

@(private)
modal_visual_test_expect_state :: proc(
	t: ^testing.T,
	fixture: ^Interaction_Fixture,
	expected_state: string,
	region_active: bool,
	start_offset, end_offset: u64,
) {
	_, state, selected := interaction.profile_activation_selection(fixture.commands.profile_activation)
	testing.expect(t, selected)
	if selected do testing.expect_value(t, state.name, expected_state)
	logical, viewed, view_failure := editor_view.snapshot(&fixture.registry, fixture.handle)
	testing.expectf(t, viewed, "modal visual snapshot failed with %v", view_failure.code)
	if !viewed do return
	testing.expect_value(t, logical.region_active, region_active)
	if region_active {
		testing.expect(t, logical.mark.present)
		if logical.mark.present {
			start := u64(logical.mark.position.byte_offset)
			end := u64(logical.point_position.byte_offset)
			if start > end do start, end = end, start
			testing.expect_value(t, start, start_offset)
			testing.expect_value(t, end, end_offset)
		}
	}
}
