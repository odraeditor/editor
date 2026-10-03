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

/* Verifies modal operators share canonical Unicode transfer, history, and indentation behavior. */
@(test)
modal_operators_execute_through_canonical_editor_state :: proc(t: ^testing.T) {
	fixture, allocation_error := new(Interaction_Fixture, context.allocator)
	testing.expect(t, allocation_error == nil)
	if allocation_error != nil do return
	defer free(fixture, context.allocator)
	if !interaction_fixture_init(t, fixture, "one 🙂two\nthree\n") do return
	defer interaction_fixture_close(fixture)
	activation: interaction.Profile_Activation
	if !modal_navigation_test_activate(t, fixture, &activation) do return
	defer interaction.profile_activation_close(&activation)
	ring: kill_ring.Ring
	ring_ok, ring_failure := kill_ring.ring_init(
		&ring,
		kill_ring.Ring_ID(7_301),
		kill_ring.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	testing.expectf(t, ring_ok, "modal kill ring failed with %v", ring_failure.code)
	if !ring_ok do return
	defer kill_ring.ring_close(&ring)
	fixture.commands.kill_ring = &ring
	policy_set, policy_failure := editor_view.set_layout_policy(
		&fixture.registry,
		fixture.handle,
		0,
		2,
		editor_view.Display_Profile_ID(1),
	)
	testing.expectf(t, policy_set, "modal layout policy failed with %v", policy_failure.code)
	if !policy_set do return
	constraints := display.Viewport_Constraints{width_cells = 80, height_rows = 24}

	modal_navigation_test_key(t, fixture, 'd', constraints)
	modal_navigation_test_key(t, fixture, 'w', constraints)
	modal_operator_test_expect_text(t, fixture, "🙂two\nthree\n")
	modal_navigation_test_key(t, fixture, 'u', constraints)
	modal_operator_test_expect_text(t, fixture, "one 🙂two\nthree\n")
	modal_operator_test_control_key(t, fixture, 'r', constraints)
	modal_operator_test_expect_text(t, fixture, "🙂two\nthree\n")
	modal_navigation_test_key(t, fixture, 'u', constraints)

	modal_navigation_test_key(t, fixture, 'y', constraints)
	modal_navigation_test_key(t, fixture, 'y', constraints)
	modal_navigation_test_key(t, fixture, 'p', constraints)
	modal_operator_test_expect_text(t, fixture, "oone 🙂two\nne 🙂two\nthree\n")
	modal_navigation_test_key(t, fixture, 'u', constraints)
	modal_operator_test_expect_text(t, fixture, "one 🙂two\nthree\n")

	modal_navigation_test_key(t, fixture, '>', constraints)
	modal_navigation_test_key(t, fixture, '>', constraints)
	modal_operator_test_expect_text(t, fixture, "  one 🙂two\nthree\n")
	modal_navigation_test_key(t, fixture, '<', constraints)
	modal_navigation_test_key(t, fixture, '<', constraints)
	modal_operator_test_expect_text(t, fixture, "one 🙂two\nthree\n")

	modal_navigation_test_key(t, fixture, 'r', constraints)
	modal_operator_test_text_key(t, fixture, '界', "界", constraints)
	modal_operator_test_expect_text(t, fixture, "界ne 🙂two\nthree\n")
	modal_navigation_test_key(t, fixture, 'u', constraints)
	modal_operator_test_expect_text(t, fixture, "one 🙂two\nthree\n")
}

@(private)
modal_operator_test_text_key :: proc(
	t: ^testing.T,
	fixture: ^Interaction_Fixture,
	value: rune,
	text: string,
	constraints: display.Viewport_Constraints,
) {
	_, failure := dispatch_input(
		&fixture.commands,
		&fixture.buffer,
		&fixture.registry,
		fixture.handle,
		interaction.Input {
			kind = .Key,
			stroke = {kind = .Unicode_Scalar, scalar = value},
			text = text,
		},
		constraints,
	)
	testing.expectf(t, failure.stage == .None, "modal text key failed at %v", failure.stage)
}

@(private)
modal_operator_test_control_key :: proc(
	t: ^testing.T,
	fixture: ^Interaction_Fixture,
	value: rune,
	constraints: display.Viewport_Constraints,
) {
	_, failure := dispatch_input(
		&fixture.commands,
		&fixture.buffer,
		&fixture.registry,
		fixture.handle,
		interaction.Input {
			kind = .Key,
			stroke = {kind = .Unicode_Scalar, scalar = value, modifiers = {.Control}},
		},
		constraints,
	)
	testing.expectf(t, failure.stage == .None, "modal control key failed at %v", failure.stage)
}

@(private)
modal_operator_test_expect_text :: proc(
	t: ^testing.T,
	fixture: ^Interaction_Fixture,
	expected: string,
) {
	stats, stats_ok, stats_failure := editor.buffer_stats(&fixture.buffer)
	testing.expectf(t, stats_ok, "modal buffer stats failed with %v", stats_failure.code)
	if !stats_ok do return
	text, allocation_error := make([]byte, int(stats.text_bytes), context.temp_allocator)
	testing.expect(t, allocation_error == nil)
	if allocation_error != nil do return
	defer delete(text, context.temp_allocator)
	_, inspected, inspect_failure := editor.buffer_inspect(
		&fixture.buffer,
		0,
		editor.Byte_Offset(stats.text_bytes),
		text,
	)
	testing.expectf(t, inspected, "modal buffer inspection failed with %v", inspect_failure.code)
	if inspected do testing.expect_value(t, string(text), expected)
}
