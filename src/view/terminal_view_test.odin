// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package view

import "../editor"
import "core:testing"

/* Verifies mirrored terminal views share one buffer while retaining independent local state. */
@(test)
terminal_mirrors_keep_independent_viewport_and_copy_state :: proc(t: ^testing.T) {
	buffer: editor.Buffer
	initialized, _ := editor.buffer_init(
		&buffer,
		editor.Buffer_ID(951),
		"terminal projection",
		editor.Allocator_Set {persistent = context.allocator, temporary = context.temp_allocator},
		editor.DEFAULT_LIMITS,
		.Terminal_Projection,
	)
	testing.expect(t, initialized)
	if !initialized do return
	registry: Registry
	ready, _ := registry_init(&registry, Registry_ID(951), context.allocator)
	testing.expect(t, ready)
	if !ready {
		editor.buffer_close(&buffer)
		return
	}
	primary, primary_ok, _ := create(&registry, &buffer)
	first, first_ok, _ := clone_additional(&registry, primary)
	second, second_ok, _ := clone_additional(&registry, primary)
	testing.expect(t, primary_ok && first_ok && second_ok)
	if !primary_ok || !first_ok || !second_ok do return
	first_viewport := Terminal_Viewport {
		top_row = 120,
		horizontal_display_column = 7,
		follow_tail = false,
	}
	viewport_set, viewport_failure := terminal_viewport_set(&registry, first, first_viewport)
	testing.expectf(t, viewport_set, "terminal viewport failed with %v", viewport_failure.code)
	copy_set, copy_failure := terminal_copy_state_set(
		&registry,
		first,
		Terminal_Copy_State {
			active = true,
			point_row = 125,
			point_column = 4,
			mark_present = true,
			mark_row = 121,
			mark_column = 2,
		},
	)
	testing.expectf(t, copy_set, "terminal copy state failed with %v", copy_failure.code)
	first_state, first_state_ok, _ := terminal_view_state(&registry, first)
	second_state, second_state_ok, _ := terminal_view_state(&registry, second)
	first_snapshot, first_snapshot_ok, _ := snapshot(&registry, first)
	second_snapshot, second_snapshot_ok, _ := snapshot(&registry, second)
	testing.expect(t, first_state_ok && second_state_ok && first_snapshot_ok && second_snapshot_ok)
	testing.expect_value(t, first_snapshot.buffer_id, second_snapshot.buffer_id)
	testing.expect_value(t, first_state.viewport, first_viewport)
	testing.expect(t, first_state.copy.active && first_state.copy.mark_present)
	testing.expect(t, second_state.viewport.follow_tail)
	testing.expect_value(t, second_state.copy, Terminal_Copy_State{})

	first_closed, _ := close(&registry, &first)
	second_closed, _ := close(&registry, &second)
	primary_closed, _ := close(&registry, &primary)
	testing.expect(t, first_closed && second_closed && primary_closed)
	testing.expect(t, editor.buffer_is_live(&buffer))
	registry_closed, _ := registry_close(&registry)
	buffer_closed, _ := editor.buffer_close(&buffer)
	testing.expect(t, registry_closed && buffer_closed)
}

/* Verifies focus transfers the sole PTY geometry authority without duplicating ownership. */
@(test)
terminal_focus_transfers_geometry_authority :: proc(t: ^testing.T) {
	buffer: editor.Buffer
	initialized, _ := editor.buffer_init(
		&buffer,
		editor.Buffer_ID(952),
		"terminal",
		editor.Allocator_Set {persistent = context.allocator, temporary = context.temp_allocator},
		editor.DEFAULT_LIMITS,
		.Terminal_Projection,
	)
	testing.expect(t, initialized)
	if !initialized do return
	registry: Registry
	ready, _ := registry_init(&registry, Registry_ID(952), context.allocator)
	testing.expect(t, ready)
	if !ready {
		editor.buffer_close(&buffer)
		return
	}
	primary, primary_ok, _ := create(&registry, &buffer)
	mirror, mirror_ok, _ := clone_additional(&registry, primary)
	testing.expect(t, primary_ok && mirror_ok)
	if !primary_ok || !mirror_ok do return
	first, claimed, claim_failure := terminal_geometry_claim(
		&registry,
		primary,
		Terminal_Geometry{columns = 80, rows = 24},
	)
	testing.expectf(t, claimed, "initial geometry claim failed with %v", claim_failure.code)
	testing.expect(t, first.changed)
	second, transferred, transfer_failure := terminal_geometry_claim(
		&registry,
		mirror,
		Terminal_Geometry{columns = 132, rows = 40},
	)
	testing.expectf(t, transferred, "geometry transfer failed with %v", transfer_failure.code)
	testing.expect_value(t, second.previous, primary)
	testing.expect_value(t, second.current, mirror)
	primary_state, primary_state_ok, _ := terminal_view_state(&registry, primary)
	mirror_state, mirror_state_ok, _ := terminal_view_state(&registry, mirror)
	testing.expect(t, primary_state_ok && mirror_state_ok)
	testing.expect(t, !primary_state.geometry_authority)
	testing.expect(t, mirror_state.geometry_authority)
	testing.expect_value(t, mirror_state.geometry, Terminal_Geometry{columns = 132, rows = 40})
	released, release_failure := terminal_geometry_release(&registry, mirror)
	testing.expectf(t, released, "geometry release failed with %v", release_failure.code)
	released_again, released_again_failure := terminal_geometry_release(&registry, mirror)
	testing.expect(t, !released_again)
	testing.expect_value(t, released_again_failure.code, Failure_Code.Geometry_Authority_Required)

	mirror_closed, _ := close(&registry, &mirror)
	primary_closed, _ := close(&registry, &primary)
	testing.expect(t, mirror_closed && primary_closed && editor.buffer_is_live(&buffer))
	registry_closed, _ := registry_close(&registry)
	buffer_closed, _ := editor.buffer_close(&buffer)
	testing.expect(t, registry_closed && buffer_closed)
}

/* Verifies text views reject terminal state and rebind clears terminal attachment. */
@(test)
terminal_attachment_clears_on_text_rebind :: proc(t: ^testing.T) {
	terminal_buffer: editor.Buffer
	text_buffer: editor.Buffer
	terminal_ready, _ := editor.buffer_init(
		&terminal_buffer,
		editor.Buffer_ID(953),
		"terminal",
		editor.Allocator_Set {persistent = context.allocator, temporary = context.temp_allocator},
		editor.DEFAULT_LIMITS,
		.Terminal_Projection,
	)
	text_ready, _ := editor.buffer_init(
		&text_buffer,
		editor.Buffer_ID(954),
		"text",
		editor.Allocator_Set {persistent = context.allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, terminal_ready && text_ready)
	if !terminal_ready || !text_ready do return
	registry: Registry
	ready, _ := registry_init(&registry, Registry_ID(953), context.allocator)
	testing.expect(t, ready)
	terminal_primary, terminal_primary_ok, _ := create(&registry, &terminal_buffer)
	text_primary, text_primary_ok, _ := create(&registry, &text_buffer)
	mirror, mirror_ok, _ := clone_additional(&registry, terminal_primary)
	testing.expect(t, terminal_primary_ok && text_primary_ok && mirror_ok)
	rebound, rebind_failure := rebind_additional(&registry, mirror, text_primary)
	testing.expectf(t, rebound, "text rebind failed with %v", rebind_failure.code)
	text_snapshot, snapshot_ok, _ := snapshot(&registry, mirror)
	testing.expect(t, snapshot_ok)
	testing.expect_value(t, text_snapshot.buffer_kind, editor.Buffer_Kind.Text)
	testing.expect_value(t, text_snapshot.terminal, Terminal_View_State{})
	_, terminal_ok, terminal_failure := terminal_view_state(&registry, mirror)
	testing.expect(t, !terminal_ok)
	testing.expect_value(t, terminal_failure.code, Failure_Code.Terminal_View_Required)

	mirror_closed, _ := close(&registry, &mirror)
	terminal_closed, _ := close(&registry, &terminal_primary)
	text_closed, _ := close(&registry, &text_primary)
	testing.expect(t, mirror_closed && terminal_closed && text_closed)
	registry_closed, _ := registry_close(&registry)
	terminal_buffer_closed, _ := editor.buffer_close(&terminal_buffer)
	text_buffer_closed, _ := editor.buffer_close(&text_buffer)
	testing.expect(t, registry_closed && terminal_buffer_closed && text_buffer_closed)
}
