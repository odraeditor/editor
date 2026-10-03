// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery_extension_focused

import command "../../src/ksawery_command"
import ksawery "../../src/ksawery"
import "core:testing"

/* Verifies scalar arguments stay inert until one request is explicitly prepared. */
@(test)
extension_command_family_edits_scalar_arguments_without_effects :: proc(t: ^testing.T) {
	choices := [1]ksawery.Extension_Command_Choice {
		{1, extension_command_test_identity("choice.safe"), extension_command_test_label("Safe")},
	}
	arguments := [4]ksawery.Extension_Command_Argument_Definition {
		{1, extension_command_test_identity("argument.force"), extension_command_test_label("Force"), .Boolean, true, 0, nil},
		{2, extension_command_test_identity("argument.mode"), extension_command_test_label("Mode"), .Closed_Choice, true, 0, choices[:]},
		{3, extension_command_test_identity("argument.note"), extension_command_test_label("Note"), .Text, true, 64, nil},
		{4, extension_command_test_identity("argument.provider-state"), extension_command_test_label("Provider state"), .Opaque, true, 32, nil},
	}
	actions := [1]ksawery.Extension_Command_Action_Definition {{
		id = 1,
		identity = extension_command_test_identity("action.inspect"),
		label = extension_command_test_label("Inspect"),
		authority = .Inspect,
		observations = {.Refs},
		target_families = {.Ref},
		operation_requirement = .Any,
	}}
	family := extension_command_family_test_definition(arguments[:], actions[:], {.Refs})
	state: command.Ksawery_Command_Family_State
	begun, failure := command.ksawery_command_family_begin(
		&state, family, 1, extension_command_test_context(), 43, context.allocator,
	)
	testing.expectf(t, begun, "family begin failed: %v/%v", failure.code, failure.contract.code)
	if !begun do return
	defer command.ksawery_command_family_close(&state)
	arguments[0].kind = .Text
	choices[0].id = 99
	actions[0].observations = {.Status}
	testing.expect_value(t, state.edit_generation, u64(1))
	testing.expect(t, !state.submitted)
	set, _ := command.ksawery_command_family_set_boolean(&state, 1, true)
	testing.expect(t, set)
	set, _ = command.ksawery_command_family_set_choice(&state, 2, 1)
	testing.expect(t, set)
	set, _ = command.ksawery_command_family_set_text(&state, 3, "review locally")
	testing.expect(t, set)
	set, _ = command.ksawery_command_family_set_opaque(&state, 4, []u8{4, 8, 15, 16, 23, 42})
	testing.expect(t, set)
	testing.expect(t, !state.submitted)
	request, prepared, prepare_failure := command.ksawery_command_family_prepare(&state)
	testing.expectf(t, prepared, "family prepare failed: %v/%v", prepare_failure.code, prepare_failure.contract.code)
	if prepared {
		testing.expect_value(t, len(request.arguments), 4)
		testing.expect_value(t, request.arguments[0].kind, ksawery.Extension_Command_Argument_Kind.Boolean)
		testing.expect_value(t, request.arguments[3].content.length, u16(6))
	}
	_, prepared, prepare_failure = command.ksawery_command_family_prepare(&state)
	testing.expect(t, !prepared)
	testing.expect_value(t, prepare_failure.code, command.Ksawery_Command_Family_Failure_Code.Already_Submitted)
}

/* Verifies exact selections and refs require a sealed one-shot confirmation. */
@(test)
extension_command_family_confirms_exact_repository_targets_once :: proc(t: ^testing.T) {
	arguments := [2]ksawery.Extension_Command_Argument_Definition {
		{1, extension_command_test_identity("argument.selection"), extension_command_test_label("Selection"), .Selection, true, 0, nil},
		{2, extension_command_test_identity("argument.ref"), extension_command_test_label("Ref"), .Ref, true, 0, nil},
	}
	actions := [1]ksawery.Extension_Command_Action_Definition {{
		id = 2,
		identity = extension_command_test_identity("action.apply"),
		label = extension_command_test_label("Apply"),
		authority = .Request_Core_Action,
		observations = {.Refs},
		target_families = {.Ref},
		operation_requirement = .Idle,
		core_operation = .Push,
		mutates_repository = true,
		confirmation_required = true,
	}}
	family := extension_command_family_test_definition(arguments[:], actions[:], {.Refs})
	command_context := extension_command_test_context()
	state: command.Ksawery_Command_Family_State
	begun, _ := command.ksawery_command_family_begin(
		&state, family, 2, command_context, 47, context.allocator,
	)
	if !testing.expect(t, begun) do return
	defer command.ksawery_command_family_close(&state)
	set, _ := command.ksawery_command_family_set_target(&state, 1, .Selection, command_context.target)
	testing.expect(t, set)
	set, _ = command.ksawery_command_family_set_target(&state, 2, .Ref, command_context.target)
	testing.expect(t, set)
	_, prepared, failure := command.ksawery_command_family_prepare(&state)
	testing.expect(t, !prepared)
	testing.expect_value(t, failure.code, command.Ksawery_Command_Family_Failure_Code.Confirmation_Required)
	confirmed, _ := command.ksawery_command_family_confirm(&state, 53)
	testing.expect(t, confirmed)
	set, failure = command.ksawery_command_family_set_target(&state, 2, .Ref, command_context.target)
	testing.expect(t, !set)
	testing.expect_value(t, failure.code, command.Ksawery_Command_Family_Failure_Code.Confirmation_Sealed)
	request, final_prepared, final_failure := command.ksawery_command_family_prepare(&state)
	testing.expectf(t, final_prepared, "family prepare failed: %v", final_failure.code)
	if final_prepared do testing.expect_value(t, request.confirmation, ksawery.Extension_Command_Confirmation_ID(53))
	testing.expect_value(t, state.confirmation, ksawery.Extension_Command_Confirmation_ID(0))
}

/* Verifies revision kinds preserve exact History generations and cancellation produces no request. */
@(test)
extension_command_family_validates_revision_ranges_and_cancellation :: proc(t: ^testing.T) {
	arguments := [2]ksawery.Extension_Command_Argument_Definition {
		{1, extension_command_test_identity("argument.revision"), extension_command_test_label("Revision"), .Revision, true, 0, nil},
		{2, extension_command_test_identity("argument.range"), extension_command_test_label("Range"), .Revision_Range, true, 0, nil},
	}
	actions := [1]ksawery.Extension_Command_Action_Definition {{
		id = 1,
		identity = extension_command_test_identity("action.inspect"),
		label = extension_command_test_label("Inspect"),
		authority = .Inspect,
		observations = {.History},
		target_families = {.Revision, .Revision_Range},
		operation_requirement = .Any,
	}}
	family := extension_command_family_test_definition(arguments[:], actions[:], {.History})
	command_context := extension_command_test_context()
	command_context.observation = .History
	assert(ksawery.extension_annotation_target_assign(
		&command_context.target, .Revision, 19, transmute([]u8)(string("0123456789abcdef")),
	))
	state: command.Ksawery_Command_Family_State
	begun, _ := command.ksawery_command_family_begin(
		&state, family, 1, command_context, 59, context.allocator,
	)
	if !testing.expect(t, begun) do return
	defer command.ksawery_command_family_close(&state)
	set, _ := command.ksawery_command_family_set_target(&state, 1, .Revision, command_context.target)
	testing.expect(t, set)
	range_target: ksawery.Extension_Annotation_Target
	assert(ksawery.extension_annotation_target_assign(
		&range_target, .Revision_Range, 19, transmute([]u8)(string("main..topic")),
	))
	set, _ = command.ksawery_command_family_set_target(&state, 2, .Revision_Range, range_target)
	testing.expect(t, set)
	range_target.generation += 1
	stale_set, stale_failure := command.ksawery_command_family_set_target(&state, 2, .Revision_Range, range_target)
	testing.expect(t, !stale_set)
	testing.expect_value(t, stale_failure.contract.code, ksawery.Extension_Repository_Command_Failure_Code.Stale_Target)
	cancelled, _ := command.ksawery_command_family_cancel(&state)
	testing.expect(t, cancelled)
	_, prepared, prepare_failure := command.ksawery_command_family_prepare(&state)
	testing.expect(t, !prepared)
	testing.expect_value(t, prepare_failure.code, command.Ksawery_Command_Family_Failure_Code.Cancelled)
}

extension_command_family_test_definition :: proc(
	arguments: []ksawery.Extension_Command_Argument_Definition,
	actions: []ksawery.Extension_Command_Action_Definition,
	observations: ksawery.Extension_Observation_Families,
) -> ksawery.Extension_Command_Family_Generation {
	contributor_identity: ksawery.Contributor_Identity
	assert(ksawery.contributor_identity_assign(&contributor_identity, "personal.repository-tools"))
	return {
		contributor = {contributor = 1, generation = 5},
		contributor_identity = contributor_identity,
		contribution = 7,
		family = 61,
		identity = extension_command_test_identity("family.repository-operation"),
		label = extension_command_test_label("Repository operation"),
		generation = 67,
		observations = observations,
		arguments = arguments,
		actions = actions,
	}
}
