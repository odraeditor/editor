// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../display"
import "../editor"
import "../interaction"
import "../search"
import editor_view "../view"
import "core:testing"

/* Verifies an active region becomes the fixed incremental-search scope. */
@(test)
search_honors_active_region :: proc(t: ^testing.T) {
	fixture: Interaction_Fixture
	if !interaction_fixture_init(t, &fixture, "needle xx needle yy needle") {
		return
	}
	defer interaction_fixture_close(&fixture)
	mark, _, _ := editor.buffer_position(&fixture.buffer, 19)
	point, _, _ := editor.buffer_position(&fixture.buffer, 7)
	marked, _ := editor_view.set_mark(&fixture.registry, fixture.handle, mark, true)
	moved, _ := editor_view.set_point(&fixture.registry, fixture.handle, point)
	testing.expect(t, marked && moved)
	constraints := display.Viewport_Constraints{width_cells = 80, height_rows = 24}
	_, start_failure := dispatch_input(
		&fixture.commands,
		&fixture.buffer,
		&fixture.registry,
		fixture.handle,
		search_control_input('s'),
		constraints,
	)
	result, search_failure := dispatch_input(
		&fixture.commands,
		&fixture.buffer,
		&fixture.registry,
		fixture.handle,
		interaction.Input{kind = .Text_Commit, text = "needle"},
		constraints,
	)
	testing.expect(t, start_failure.stage == .None && search_failure.stage == .None)
	testing.expect(t, result.changed)
	search_view, viewed, _ := editor_view.search_session_view(&fixture.registry, fixture.handle)
	testing.expect(t, viewed && search_view.present && search_view.has_current)
	testing.expect_value(t, search_view.scope.start, editor.Byte_Offset(7))
	testing.expect_value(t, search_view.scope.end, editor.Byte_Offset(19))
	testing.expect_value(t, search_view.occurrences[search_view.current_index].start, editor.Byte_Offset(10))
	logical, logical_ok, _ := editor_view.snapshot(&fixture.registry, fixture.handle)
	testing.expect(t, logical_ok)
	testing.expect_value(t, logical.point_position.byte_offset, editor.Byte_Offset(16))
}

/* Verifies a long miss remains pending until a later bounded editor turn. */
@(test)
search_presents_and_resumes_work :: proc(t: ^testing.T) {
	contents: [70_000]byte
	for index in 0 ..< len(contents) {
		contents[index] = 'x'
	}
	for index := 999; index < len(contents); index += 1_000 {
		contents[index] = '\n'
	}
	copy(contents[68_000:], "needle")
	fixture: Interaction_Fixture
	if !interaction_fixture_init(t, &fixture, string(contents[:])) {
		return
	}
	defer interaction_fixture_close(&fixture)
	constraints := display.Viewport_Constraints{width_cells = 80, height_rows = 24}
	_, _ = dispatch_input(
		&fixture.commands,
		&fixture.buffer,
		&fixture.registry,
		fixture.handle,
		search_control_input('s'),
		constraints,
	)
	first, first_failure := dispatch_input(
		&fixture.commands,
		&fixture.buffer,
		&fixture.registry,
		fixture.handle,
		interaction.Input{kind = .Text_Commit, text = "needle"},
		constraints,
	)
	testing.expectf(
		t,
		first.changed && first_failure.stage == .None,
		"pending turn failed at %v with command=%v search=%v view=%v display=%v",
		first_failure.stage,
		first_failure.command.code,
		first_failure.command.search_code,
		first_failure.command.view_code,
		first_failure.command.display_code,
	)
	if first_failure.stage != .None {
		return
	}
	search_view, viewed, _ := editor_view.search_session_view(&fixture.registry, fixture.handle)
	testing.expect(t, viewed && search_view.present)
	testing.expect_value(t, search_view.status, editor_view.Search_Status.Pending)
	label, text, overlay := command_context_overlay(
		&fixture.commands,
		&fixture.registry,
		fixture.handle,
	)
	testing.expect(t, overlay)
	testing.expect_value(t, label, "Pending Search → [smart/insensitive any exact]: ")
	testing.expect_value(t, text, "needle")

	resumed, resume_failure := dispatch_input(
		&fixture.commands,
		&fixture.buffer,
		&fixture.registry,
		fixture.handle,
		search_control_input('s'),
		constraints,
	)
	testing.expect(t, resumed.changed && resume_failure.stage == .None)
	search_view, viewed, _ = editor_view.search_session_view(&fixture.registry, fixture.handle)
	testing.expect(t, viewed && search_view.present && search_view.has_current)
	testing.expect_value(t, search_view.status, editor_view.Search_Status.Active)
	if search_view.has_current {
		testing.expect_value(t, search_view.occurrences[search_view.current_index].start, editor.Byte_Offset(68_000))
	}
}

/* Verifies generated query edits and direction changes preserve interaction invariants. */
@(test)
search_contains_generated_sequences :: proc(t: ^testing.T) {
	contents := "alpha alpine beta ALPHA alpha\n" +
	            "gamma alpha delta alpine alpha\n"
	fixture: Interaction_Fixture
	if !interaction_fixture_init(t, &fixture, contents) {
		return
	}
	defer interaction_fixture_close(&fixture)
	constraints := display.Viewport_Constraints{width_cells = 80, height_rows = 24}
	_, start_failure := dispatch_input(
		&fixture.commands,
		&fixture.buffer,
		&fixture.registry,
		fixture.handle,
		search_control_input('s'),
		constraints,
	)
	testing.expect_value(t, start_failure.stage, App_Stage.None)
	seed := u64(0xd1b54a32d192ed03)
	query_updates, direction_changes := 0, 0
	characters := "alphaZ"
	for _ in 0 ..< 96 {
		seed = search_interaction_next(seed)
		prompt_view, prompt_ok, _ := interaction.prompt_view(&fixture.commands.prompt_workflow.prompt)
		testing.expect(t, prompt_ok)
		if !prompt_ok {
			break
		}
		operation := seed % 4
		input: interaction.Input
		if operation == 0 && len(prompt_view.text) < 8 {
			index := int((seed >> 8) % u64(len(characters)))
			input = interaction.Input{kind = .Text_Commit, text = characters[index:index + 1]}
			query_updates += 1
		} else if operation == 1 && len(prompt_view.text) > 0 {
			input = interaction.Input{kind = .Key, stroke = interaction.Key_Stroke{kind = .Backspace}}
			query_updates += 1
		} else {
			direction := 's'
			if seed & 1 != 0 {
				direction = 'r'
			}
			input = search_control_input(direction)
			direction_changes += 1
		}
		_, failure := dispatch_input(
			&fixture.commands,
			&fixture.buffer,
			&fixture.registry,
			fixture.handle,
			input,
			constraints,
		)
		testing.expectf(t, failure.stage == .None, "generated interaction failed at %v", failure.stage)
	}
	testing.expect(t, query_updates > 0 && direction_changes > 0)
	for _ in 0 ..< 2 {
		if fixture.commands.prompt_workflow.mode == .None {
			break
		}
		_, failure := dispatch_input(
			&fixture.commands,
			&fixture.buffer,
			&fixture.registry,
			fixture.handle,
			search_control_input('g'),
			constraints,
		)
		testing.expect_value(t, failure.stage, App_Stage.None)
	}
	testing.expect_value(t, fixture.commands.prompt_workflow.mode, Prompt_Mode.None)
	expect_interaction_buffer(t, &fixture.buffer, contents)
	logical, logical_ok, _ := editor_view.snapshot(&fixture.registry, fixture.handle)
	testing.expect(t, logical_ok)
	position, position_ok, _ := editor.buffer_position(
		&fixture.buffer,
		logical.point_position.byte_offset,
	)
	testing.expect(t, position_ok)
	testing.expect_value(t, position, logical.point_position)
}

/* Verifies M-s . starts the ordinary symbol-boundary search from generic text. */
@(test)
symbol_at_point_uses_search_session :: proc(t: ^testing.T) {
	contents := "alpha beta alpha"
	fixture: Interaction_Fixture
	if !interaction_fixture_init(t, &fixture, contents) do return
	defer interaction_fixture_close(&fixture)
	point, _, _ := editor.buffer_position(&fixture.buffer, 2)
	_, _ = editor_view.set_point(&fixture.registry, fixture.handle, point)
	constraints := display.Viewport_Constraints{width_cells = 80, height_rows = 24}
	_, prefix_failure := dispatch_input(
		&fixture.commands,
		&fixture.buffer,
		&fixture.registry,
		fixture.handle,
		search_meta_input('s'),
		constraints,
	)
	result, search_failure := dispatch_input(
		&fixture.commands,
		&fixture.buffer,
		&fixture.registry,
		fixture.handle,
		interaction.Input {
			kind = .Key,
			stroke = {kind = .Unicode_Scalar, scalar = '.'},
		},
		constraints,
	)
	testing.expect(t, prefix_failure.stage == .None && search_failure.stage == .None)
	testing.expect(t, result.changed)
	prompt, prompt_ok, _ := interaction.prompt_view(&fixture.commands.prompt_workflow.prompt)
	testing.expect(t, prompt_ok)
	if prompt_ok do testing.expect_value(t, prompt.text, "alpha")
	search_view, viewed, _ := editor_view.search_session_view(&fixture.registry, fixture.handle)
	testing.expect(t, viewed && search_view.present && search_view.has_current)
	if search_view.present {
		testing.expect_value(t, search_view.policy.boundary_mode, search.Boundary_Mode.Symbol)
	}
}

/* Verifies M-s . reports no symbol without moving point or opening search. */
@(test)
missing_symbol_preserves_state :: proc(t: ^testing.T) {
	fixture: Interaction_Fixture
	if !interaction_fixture_init(t, &fixture, "alpha  beta") do return
	defer interaction_fixture_close(&fixture)
	point, _, _ := editor.buffer_position(&fixture.buffer, 6)
	_, _ = editor_view.set_point(&fixture.registry, fixture.handle, point)
	constraints := display.Viewport_Constraints{width_cells = 80, height_rows = 24}
	_, _ = dispatch_input(
		&fixture.commands,
		&fixture.buffer,
		&fixture.registry,
		fixture.handle,
		search_meta_input('s'),
		constraints,
	)
	_, failure := dispatch_input(
		&fixture.commands,
		&fixture.buffer,
		&fixture.registry,
		fixture.handle,
		interaction.Input{kind = .Key, stroke = {kind = .Unicode_Scalar, scalar = '.'}},
		constraints,
	)
	testing.expect_value(t, failure.stage, App_Stage.None)
	logical, logical_ok, _ := editor_view.snapshot(&fixture.registry, fixture.handle)
	testing.expect(t, logical_ok)
	if logical_ok do testing.expect_value(t, logical.point_position.byte_offset, editor.Byte_Offset(6))
	search_view, viewed, _ := editor_view.search_session_view(&fixture.registry, fixture.handle)
	testing.expect(t, viewed && !search_view.present)
	testing.expect_value(t, fixture.commands.prompt_workflow.mode, Prompt_Mode.None)
}

@(private)
search_control_input :: proc(value: rune) -> interaction.Input {
	return interaction.Input {
		kind = .Key,
		stroke = interaction.Key_Stroke {
			kind = .Unicode_Scalar,
			scalar = value,
			modifiers = {.Control},
		},
	}
}

@(private)
search_meta_input :: proc(value: rune) -> interaction.Input {
	return interaction.Input {
		kind = .Key,
		stroke = interaction.Key_Stroke {
			kind = .Unicode_Scalar,
			scalar = value,
			modifiers = {.Meta},
		},
	}
}

@(private)
search_interaction_next :: proc(state: u64) -> u64 {
	value := state
	value ~= value << 13
	value ~= value >> 7
	value ~= value << 17
	return value
}
