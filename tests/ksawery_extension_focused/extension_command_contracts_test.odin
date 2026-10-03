// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery_extension_focused

import ksawery "../../src/ksawery"
import "core:testing"

extension_command_test_identity :: proc(value: string) -> ksawery.Extension_Identity {
	identity: ksawery.Extension_Identity
	assert(ksawery.extension_identity_assign(&identity, value))
	return identity
}

extension_command_test_label :: proc(value: string) -> ksawery.Extension_Label {
	label: ksawery.Extension_Label
	assert(ksawery.extension_label_assign(&label, value))
	return label
}

extension_command_test_context :: proc() -> ksawery.Extension_Command_Context {
	repository: ksawery.Repository_Context
	assert(ksawery.repository_context_assign(&repository, "/tmp/odra-extension-command"))
	target: ksawery.Extension_Annotation_Target
	assert(ksawery.extension_annotation_target_assign(
		&target, .Ref, 19, transmute([]u8)(string("refs/heads/main")),
	))
	return {
		contributor = {contributor = 1, generation = 5},
		repository = repository,
		repository_generation = 11,
		worktree_generation = 13,
		observation = .Refs,
		observation_generation = 19,
		surface = .Refs,
		surface_generation = 23,
		selection_generation = 29,
		target_present = true,
		target = target,
		operation_state = .Idle,
		mutation_available = true,
		capability_generation = 31,
	}
}

extension_command_test_family :: proc(
	choices: ^[2]ksawery.Extension_Command_Choice,
	arguments: ^[3]ksawery.Extension_Command_Argument_Definition,
	actions: ^[2]ksawery.Extension_Command_Action_Definition,
) -> ksawery.Extension_Command_Family_Generation {
	choices^ = [2]ksawery.Extension_Command_Choice {
		{1, extension_command_test_identity("choice.fast-forward"), extension_command_test_label("Fast-forward")},
		{2, extension_command_test_identity("choice.merge-commit"), extension_command_test_label("Merge commit")},
	}
	arguments^ = [3]ksawery.Extension_Command_Argument_Definition {
		{1, extension_command_test_identity("argument.force"), extension_command_test_label("Force"), .Boolean, false, 0, nil},
		{2, extension_command_test_identity("argument.mode"), extension_command_test_label("Mode"), .Closed_Choice, true, 0, choices^[:]},
		{3, extension_command_test_identity("argument.note"), extension_command_test_label("Note"), .Text, false, 128, nil},
	}
	actions^ = [2]ksawery.Extension_Command_Action_Definition {
		{
			id = 1,
			identity = extension_command_test_identity("action.inspect"),
			label = extension_command_test_label("Inspect"),
			authority = .Inspect,
			observations = {.Refs},
			target_families = {.Ref, .Remote},
			operation_requirement = .Any,
		},
		{
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
		},
	}
	contributor_identity: ksawery.Contributor_Identity
	assert(ksawery.contributor_identity_assign(&contributor_identity, "personal.repository-tools"))
	return {
		contributor = {contributor = 1, generation = 5},
		contributor_identity = contributor_identity,
		contribution = 7,
		family = 11,
		identity = extension_command_test_identity("family.review-ref"),
		label = extension_command_test_label("Review ref"),
		generation = 17,
		observations = {.Refs},
		arguments = arguments^[:],
		actions = actions^[:],
	}
}

/* Verifies bounded typed family declarations and duplicate rejection. */
@(test)
extension_command_families_are_typed_and_bounded :: proc(t: ^testing.T) {
	choices: [2]ksawery.Extension_Command_Choice
	arguments: [3]ksawery.Extension_Command_Argument_Definition
	actions: [2]ksawery.Extension_Command_Action_Definition
	family := extension_command_test_family(&choices, &arguments, &actions)
	usage, failure := ksawery.extension_command_family_validate(family)
	testing.expect_value(t, failure.code, ksawery.Extension_Repository_Command_Failure_Code.None)
	testing.expect_value(t, usage.arguments, u32(3))
	testing.expect_value(t, usage.choices, u32(2))
	testing.expect_value(t, usage.actions, u32(2))
	testing.expect(t, usage.copy_bytes <= ksawery.DEFAULT_EXTENSION_COMMAND_COPY_BYTES)
	testing.expect(t, ksawery.extension_command_limits_are_valid(ksawery.DEFAULT_EXTENSION_COMMAND_LIMITS))

	arguments[1].id = arguments[0].id
	family.arguments = arguments[:]
	_, failure = ksawery.extension_command_family_validate(family)
	testing.expect_value(t, failure.code, ksawery.Extension_Repository_Command_Failure_Code.Duplicate_Identity)

	family = extension_command_test_family(&choices, &arguments, &actions)
	actions[1].mutates_repository = true
	actions[1].confirmation_required = false
	family.actions = actions[:]
	_, failure = ksawery.extension_command_family_validate(family)
	testing.expect_value(t, failure.code, ksawery.Extension_Repository_Command_Failure_Code.Invalid_Action)
}

/* Verifies contributorless native families stay closed to extension admission. */
@(test)
extension_cannot_augment_closed_families :: proc(t: ^testing.T) {
	choices: [2]ksawery.Extension_Command_Choice
	arguments: [3]ksawery.Extension_Command_Argument_Definition
	actions: [2]ksawery.Extension_Command_Action_Definition
	family := extension_command_test_family(&choices, &arguments, &actions)
	family.contributor = {}
	family.contribution = 0
	_, failure := ksawery.extension_command_family_validate(family)
	testing.expect_value(t, failure.code, ksawery.Extension_Repository_Command_Failure_Code.Invalid_Family)
}

/* Verifies exact context generations and operation requirements gate actions. */
@(test)
extension_command_contexts_gate_actions :: proc(t: ^testing.T) {
	choices: [2]ksawery.Extension_Command_Choice
	arguments: [3]ksawery.Extension_Command_Argument_Definition
	actions: [2]ksawery.Extension_Command_Action_Definition
	_ = extension_command_test_family(&choices, &arguments, &actions)
	command_context := extension_command_test_context()
	failure := ksawery.extension_command_context_validate(command_context)
	testing.expect_value(t, failure.code, ksawery.Extension_Repository_Command_Failure_Code.None)
	available, availability_failure := ksawery.extension_command_action_available(actions[1], command_context)
	testing.expect(t, available)
	command_context.operation_state = .Active
	available, availability_failure = ksawery.extension_command_action_available(actions[1], command_context)
	testing.expect(t, !available)
	testing.expect_value(t, availability_failure.code, ksawery.Extension_Repository_Command_Failure_Code.Operation_Unavailable)
	command_context.operation_state = .Idle
	command_context.mutation_available = false
	available, availability_failure = ksawery.extension_command_action_available(actions[1], command_context)
	testing.expect(t, !available)
	testing.expect_value(t, availability_failure.code, ksawery.Extension_Repository_Command_Failure_Code.Mutation_Unavailable)
	command_context.target.generation += 1
	failure = ksawery.extension_command_context_validate(command_context)
	testing.expect_value(t, failure.code, ksawery.Extension_Repository_Command_Failure_Code.Stale_Target)
}

/* Verifies typed values remain inert and requests require exact confirmation. */
@(test)
extension_command_requests_validate_typed_arguments :: proc(t: ^testing.T) {
	choices: [2]ksawery.Extension_Command_Choice
	definitions: [3]ksawery.Extension_Command_Argument_Definition
	actions: [2]ksawery.Extension_Command_Action_Definition
	family := extension_command_test_family(&choices, &definitions, &actions)
	values := [3]ksawery.Extension_Command_Argument_Value {
		{argument = 1, kind = .Boolean, boolean = true},
		{argument = 2, kind = .Closed_Choice, choice = 1},
		{argument = 3, kind = .Text},
	}
	testing.expect(t, ksawery.extension_command_value_assign_text(&values[2].content, "Reviewed locally"))
	request := ksawery.Extension_Command_Request {
		id = 37,
		family = family.family,
		family_generation = family.generation,
		action = 2,
		command_context = extension_command_test_context(),
		arguments = values[:],
		confirmation = 41,
	}
	usage, failure := ksawery.extension_command_request_validate(request, family)
	testing.expect_value(t, failure.code, ksawery.Extension_Repository_Command_Failure_Code.None)
	testing.expect_value(t, usage.arguments, u32(3))
	testing.expect(t, usage.value_bytes > 0)

	request.confirmation = 0
	_, failure = ksawery.extension_command_request_validate(request, family)
	testing.expect_value(t, failure.code, ksawery.Extension_Repository_Command_Failure_Code.Confirmation_Required)
	request.confirmation = 41
	values[1].choice = 99
	request.arguments = values[:]
	_, failure = ksawery.extension_command_request_validate(request, family)
	testing.expect_value(t, failure.code, ksawery.Extension_Repository_Command_Failure_Code.Invalid_Choice)
	values[1].choice = 1
	request.arguments = values[:1]
	_, failure = ksawery.extension_command_request_validate(request, family)
	testing.expect_value(t, failure.code, ksawery.Extension_Repository_Command_Failure_Code.Missing_Argument)
}

/* Verifies exact result correlation, bounded text, and failed-action integrity. */
@(test)
extension_command_results_are_correlated_and_bounded :: proc(t: ^testing.T) {
	request := ksawery.Extension_Command_Request {
		id = 37,
		family = 11,
		family_generation = 17,
		action = 2,
	}
	result := ksawery.Extension_Command_Result {
		request = request.id,
		family = request.family,
		family_generation = request.family_generation,
		action = request.action,
		status = .Completed,
		core_action_requested = true,
	}
	testing.expect(t, ksawery.extension_command_result_text_assign(
		&result.presentation, "Repository action prepared",
	))
	failure := ksawery.extension_command_result_validate(result, request)
	testing.expect_value(t, failure.code, ksawery.Extension_Repository_Command_Failure_Code.None)
	result.status = .Failed
	failure = ksawery.extension_command_result_validate(result, request)
	testing.expect_value(t, failure.code, ksawery.Extension_Repository_Command_Failure_Code.None)
	result.status = .Rejected
	failure = ksawery.extension_command_result_validate(result, request)
	testing.expect_value(t, failure.code, ksawery.Extension_Repository_Command_Failure_Code.Invalid_Result)
	result.status = .Completed
	result.request += 1
	failure = ksawery.extension_command_result_validate(result, request)
	testing.expect_value(t, failure.code, ksawery.Extension_Repository_Command_Failure_Code.Invalid_Result)
}
