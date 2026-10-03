// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_editing

import "../language"
import "core:testing"

/* Verifies contextual action selects the deepest Stage 2 syntax deterministically. */
@(test)
contextual_action_uses_stable_inspectable_precedence :: proc(t: ^testing.T) {
	source := "* Heading\n| a | b |\n"
	fixture: List_Test_Fixture
	if !list_test_fixture_open(t, &fixture, source, 2_601) do return
	defer list_test_fixture_close(&fixture)
	heading, resolved, failure := context_action_resolve(
		&fixture.analysis,
		transmute([]u8)source,
		{operation_id = 401, scope = fixture.scope, point = 0},
	)
	testing.expectf(t, resolved, "heading context failed with %v", failure.code)
	testing.expect_value(t, heading.status, Context_Resolution_Status.Resolved)
	testing.expect_value(t, heading.ctx, Authoring_Context.Heading)
	testing.expect_value(t, heading.command, Authoring_Command.Cycle_Heading)
	table: Context_Resolution
	table, resolved, failure = context_action_resolve(
		&fixture.analysis,
		transmute([]u8)source,
		{operation_id = 402, scope = fixture.scope, point = 10},
	)
	testing.expectf(t, resolved, "table context failed with %v", failure.code)
	testing.expect_value(t, table.ctx, Authoring_Context.Table)
	testing.expect(t, table.precedence > heading.precedence)
	for value in 1 ..= int(Authoring_Context.Future_Citation) {
		ctx := Authoring_Context(value)
		testing.expect_value(t, authoring_context_precedence(ctx), u8(value))
	}
}

/* Verifies recognized later-stage syntax returns unavailable with its exact owner. */
@(test)
contextual_action_does_not_fall_through_future_stage_syntax :: proc(t: ^testing.T) {
	source := ":PROPERTIES:\n:ID: abc\n:END:\n"
	fixture: List_Test_Fixture
	if !list_test_fixture_open(t, &fixture, source, 2_602) do return
	defer list_test_fixture_close(&fixture)
	property, found := list_test_node(&fixture.analysis, .Node_Property, 0)
	testing.expect(t, found)
	if !found do return
	resolution, resolved, failure := context_action_resolve(
		&fixture.analysis,
		transmute([]u8)source,
		{operation_id = 403, scope = fixture.scope, point = property.range.start},
	)
	testing.expectf(t, resolved, "future context failed with %v", failure.code)
	testing.expect_value(t, resolution.status, Context_Resolution_Status.Unavailable)
	testing.expect_value(t, resolution.ctx, Authoring_Context.Future_Property)
	testing.expect_value(t, resolution.command, Authoring_Command.Unavailable)
	testing.expect_value(t, resolution.future_owner, language.Jan_Stage.Planning_And_Agenda)
}

/* Verifies speed keys are admitted at structural prefixes but never in ordinary text. */
@(test)
speed_keys_require_declared_structural_positions :: proc(t: ^testing.T) {
	source := "* Heading\nordinary text\n"
	fixture: List_Test_Fixture
	if !list_test_fixture_open(t, &fixture, source, 2_603) do return
	defer list_test_fixture_close(&fixture)
	speed, resolved, failure := speed_key_resolve(
		&fixture.analysis,
		transmute([]u8)source,
		{operation_id = 404, scope = fixture.scope, point = 0},
		'n',
	)
	testing.expectf(t, resolved, "heading speed key failed with %v", failure.code)
	testing.expect(t, speed.admitted)
	testing.expect_value(t, speed.command, Authoring_Command.Move_Down)
	ordinary: Speed_Key_Resolution
	ordinary, resolved, failure = speed_key_resolve(
		&fixture.analysis,
		transmute([]u8)source,
		{operation_id = 405, scope = fixture.scope, point = 14},
		'n',
	)
	testing.expectf(t, resolved, "ordinary context failed with %v", failure.code)
	testing.expect(t, !ordinary.admitted)
}

/* Verifies repetition resolves the current semantic target instead of replaying a range. */
@(test)
semantic_repeat_resolves_a_fresh_target_at_point :: proc(t: ^testing.T) {
	source := "* First\nbody\n* Second heading\n"
	fixture: List_Test_Fixture
	if !list_test_fixture_open(t, &fixture, source, 2_604) do return
	defer list_test_fixture_close(&fixture)
	first, resolved, _ := context_action_resolve(
		&fixture.analysis,
		transmute([]u8)source,
		{operation_id = 406, scope = fixture.scope, point = 0},
	)
	testing.expect(t, resolved)
	metadata, captured := semantic_repeat_capture(first, .Move_Down)
	testing.expect(t, captured)
	if !captured do return
	second, repeated, failure := semantic_repeat_resolve(
		&fixture.analysis,
		transmute([]u8)source,
		fixture.scope,
		14,
		metadata,
	)
	testing.expectf(t, repeated, "repeat resolution failed with %v", failure.code)
	testing.expect_value(t, second.command, Authoring_Command.Move_Down)
	testing.expect(t, second.target.node_id != first.target.node_id)
	testing.expect(t, second.target.range.start != first.target.range.start)
}
