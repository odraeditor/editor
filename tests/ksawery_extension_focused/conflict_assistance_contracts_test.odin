// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery_extension_focused

import ksawery "../../src/ksawery"
import "core:testing"

/* conflict_assistance_test_provider builds one complete active helper declaration. */
conflict_assistance_test_provider :: proc() -> (
	ksawery.Conflict_Assistance_Provider,
	ksawery.Contribution_Declaration,
) {
	identity: ksawery.Extension_Identity
	label: ksawery.Extension_Label
	assert(ksawery.extension_identity_assign(&identity, "conflict.helper"))
	assert(ksawery.extension_label_assign(&label, "Conflict helper"))
	provider := ksawery.Conflict_Assistance_Provider {
		origin = .Extension,
		contributor = {contributor = 3, generation = 5},
		contribution = 7,
		provider = 11,
		generation = 13,
		identity = identity,
		label = label,
		supported_classes = {.Text, .Delete, .Missing_Stage},
		capabilities = {.Present_Guidance, .Open_Editor, .Submit_External_Tool},
		lifecycle = .Active,
	}
	declaration := ksawery.Contribution_Declaration {
		id = provider.contribution,
		identity = identity,
		kind = .Provider_Role,
		provider_role = .Conflict_Assistance,
		required_observations = {.Status, .Sequence, .Conflict, .Process},
		requested_authority = {
			.Inspect,
			.Present,
			.Submit_External_Operation,
			.Assist_Conflict,
		},
	}
	return provider, declaration
}

/* conflict_assistance_test_target builds one exact generation-bound conflict target. */
conflict_assistance_test_target :: proc() -> ksawery.Conflict_Assistance_Target {
	repository: ksawery.Repository_Context
	path: ksawery.Conflict_Assistance_Path
	assert(ksawery.repository_context_assign(&repository, "/tmp/odra-conflict-assistance"))
	assert(ksawery.conflict_assistance_path_assign(&path, "src/example.odin"))
	return {
		repository = repository,
		repository_generation = 17,
		worktree_generation = 19,
		observation_generation = 23,
		conflict = {
			sequence = {generation = 29, fingerprint = 31},
			conflict = 37,
		},
		kind = .Deleted_By_Them,
		classes = {.Text, .Delete, .Missing_Stage},
		path = path,
	}
}

/* conflict_assistance_test_revision returns one valid immutable Git identity. */
conflict_assistance_test_revision :: proc(value: string) -> ksawery.Revision_Identity {
	identity: ksawery.Revision_Identity
	assert(ksawery.revision_identity_assign(&identity, value))
	return identity
}

/* conflict_assistance_test_selection selects one provider for the current session. */
conflict_assistance_test_selection :: proc(
	provider: ksawery.Conflict_Assistance_Provider,
) -> ksawery.Conflict_Assistance_Selection {
	return {
		selection = 41,
		generation = 43,
		scope = .Session,
		session = 47,
		provider = ksawery.conflict_assistance_provider_reference(provider),
		confirmed = true,
	}
}

/* Verifies the immutable built-in no-op remains a valid lowest-precedence fallback. */
@(test)
conflict_assistance_has_no_op_fallback :: proc(t: ^testing.T) {
	provider := ksawery.conflict_assistance_builtin_no_op_provider()
	failure := ksawery.conflict_assistance_provider_validate(provider, {})
	testing.expect_value(t, failure.code, ksawery.Conflict_Assistance_Failure_Code.None)
	selection := ksawery.conflict_assistance_builtin_fallback_selection(1)
	testing.expect(t, ksawery.conflict_assistance_selection_is_valid(selection))
	testing.expect(t, ksawery.conflict_assistance_provider_supports(
		provider, conflict_assistance_test_target(),
	))
}

/* Verifies extension helpers require the exact semantic role and authorities. */
@(test)
conflict_assistance_provider_identity_is_scoped :: proc(t: ^testing.T) {
	provider, declaration := conflict_assistance_test_provider()
	failure := ksawery.conflict_assistance_provider_validate(provider, declaration)
	testing.expect_value(t, failure.code, ksawery.Conflict_Assistance_Failure_Code.None)
	declaration.requested_authority -= {.Assist_Conflict}
	failure = ksawery.conflict_assistance_provider_validate(provider, declaration)
	testing.expect_value(
		t,
		failure.code,
		ksawery.Conflict_Assistance_Failure_Code.Invalid_Contribution,
	)
	provider.supported_classes = {.Binary}
	testing.expect(t, !ksawery.conflict_assistance_provider_supports(
		provider, conflict_assistance_test_target(),
	))
}

/* Verifies exact Base, Current, Applied, and worktree sides remain copied and bounded. */
@(test)
conflict_assistance_observation_copies_exact_sides :: proc(t: ^testing.T) {
	content := transmute([]u8)(string("basecurrentworktree"))
	base := conflict_assistance_test_revision("1111111111111111111111111111111111111111")
	current := conflict_assistance_test_revision("2222222222222222222222222222222222222222")
	observation := ksawery.Conflict_Assistance_Observation {
		target = conflict_assistance_test_target(),
		sides = {
			{kind = .Base, material = .Text, mode = 0o100644, object = base, content = {0, 4}},
			{kind = .Current, material = .Text, mode = 0o100644, object = current, content = {4, 7}},
			{kind = .Applied, material = .Missing},
			{kind = .Worktree, material = .Text, mode = 0o100644, content = {11, 8}},
		},
		content = content,
	}
	usage, failure := ksawery.conflict_assistance_observation_validate(observation)
	testing.expect_value(t, failure.code, ksawery.Conflict_Assistance_Failure_Code.None)
	testing.expect_value(t, usage.sides, u32(3))
	testing.expect_value(t, usage.content_bytes, u64(len(content)))
	observation.sides[1].content.length = 100
	_, failure = ksawery.conflict_assistance_observation_validate(observation)
	testing.expect_value(t, failure.code, ksawery.Conflict_Assistance_Failure_Code.Invalid_Side)
}

/* Verifies exact confirmed selection and request generations reject stale helpers. */
@(test)
conflict_assistance_selection_and_request_are_exact :: proc(t: ^testing.T) {
	provider, _ := conflict_assistance_test_provider()
	selection := conflict_assistance_test_selection(provider)
	testing.expect(t, ksawery.conflict_assistance_selection_is_valid(selection))
	fallback := ksawery.conflict_assistance_builtin_fallback_selection(1)
	testing.expect(t, ksawery.conflict_assistance_selection_precedes(selection, fallback))
	request := ksawery.Conflict_Assistance_Request {
		request = 53,
		selection_generation = selection.generation,
		provider = selection.provider,
		target = conflict_assistance_test_target(),
	}
	failure := ksawery.conflict_assistance_request_validate(request, provider, selection)
	testing.expect_value(t, failure.code, ksawery.Conflict_Assistance_Failure_Code.None)
	request.selection_generation += 1
	failure = ksawery.conflict_assistance_request_validate(request, provider, selection)
	testing.expect_value(t, failure.code, ksawery.Conflict_Assistance_Failure_Code.Stale_Selection)
}

/* Verifies guidance and external tools cannot carry Conflict core actions. */
@(test)
conflict_assistance_responses_are_bounded_and_authority_free :: proc(t: ^testing.T) {
	provider, _ := conflict_assistance_test_provider()
	selection := conflict_assistance_test_selection(provider)
	request := ksawery.Conflict_Assistance_Request {
		request = 53,
		selection_generation = selection.generation,
		provider = selection.provider,
		target = conflict_assistance_test_target(),
	}
	guidance: ksawery.Conflict_Assistance_Guidance
	testing.expect(t, ksawery.conflict_assistance_guidance_assign(
		&guidance, "Compare the copied sides before choosing a core action.",
	))
	response := ksawery.Conflict_Assistance_Response {
		request = request.request,
		provider = request.provider,
		target = request.target,
		kind = .Guidance,
		guidance = guidance,
	}
	usage, failure := ksawery.conflict_assistance_response_validate(response, request, provider)
	testing.expect_value(t, failure.code, ksawery.Conflict_Assistance_Failure_Code.None)
	testing.expect_value(t, usage.guidance_bytes, u64(guidance.length))

	arguments: [1]ksawery.Extension_Operation_Argument
	assert(ksawery.extension_operation_argument_assign(&arguments[0], "mergetool"))
	identity: ksawery.Extension_Identity
	purpose: ksawery.Extension_Label
	executable: ksawery.Extension_Operation_Executable
	assert(ksawery.extension_identity_assign(&identity, "conflict.tool"))
	assert(ksawery.extension_label_assign(&purpose, "Inspect conflict"))
	assert(ksawery.extension_operation_executable_assign_git(&executable))
	operation := ksawery.Extension_Operation_Plan {
		contributor = provider.contributor,
		contribution = 59,
		plan = 61,
		generation = 67,
		identity = identity,
		purpose = purpose,
		executable = executable,
		arguments = arguments[:],
		effect = .Repository_Mutating,
		refresh = ksawery.CONFLICT_ASSISTANCE_TOOL_REFRESH,
		environment = .Core_Repository,
		diagnostic_policy = .Suppressed,
		process_limits = ksawery.DEFAULT_EXTENSION_OPERATION_PROCESS_LIMITS,
	}
	response = {
		request = request.request,
		provider = request.provider,
		target = request.target,
		kind = .External_Tool,
		tool = {
			request = request.request,
			provider = request.provider,
			target = request.target,
			access = .Worktree_Only,
			operation = operation,
		},
	}
	usage, failure = ksawery.conflict_assistance_response_validate(response, request, provider)
	testing.expect_value(t, failure.code, ksawery.Conflict_Assistance_Failure_Code.None)
	testing.expect_value(t, usage.external_tools, u64(1))
	response.tool.access = .Read_Only
	_, failure = ksawery.conflict_assistance_response_validate(response, request, provider)
	testing.expect_value(t, failure.code, ksawery.Conflict_Assistance_Failure_Code.Invalid_Tool_Plan)
}

/* Verifies lifecycle edges and exact accounting remain closed and bounded. */
@(test)
conflict_assistance_lifecycle_and_usage_are_bounded :: proc(t: ^testing.T) {
	testing.expect(t, ksawery.conflict_assistance_provider_lifecycle_transition_is_valid(
		.Declared, .Prepared,
	))
	testing.expect(t, ksawery.conflict_assistance_provider_lifecycle_transition_is_valid(
		.Active, .Declined,
	))
	testing.expect(t, !ksawery.conflict_assistance_provider_lifecycle_transition_is_valid(
		.Closed, .Active,
	))
	usage := ksawery.Conflict_Assistance_Usage {
		providers = 2,
		selections = 1,
		requests = 3,
		sides = 4,
		path_bytes = 16,
		content_bytes = 1 * ksawery.KIBIBYTE,
		guidance_bytes = 128,
		copy_bytes = 2 * ksawery.KIBIBYTE,
	}
	testing.expect(t, ksawery.conflict_assistance_usage_within_limits(
		usage, ksawery.DEFAULT_CONFLICT_ASSISTANCE_LIMITS,
	))
	usage.providers = ksawery.MAX_CONFLICT_ASSISTANCE_PROVIDERS + 1
	testing.expect(t, !ksawery.conflict_assistance_usage_within_limits(
		usage, ksawery.DEFAULT_CONFLICT_ASSISTANCE_LIMITS,
	))
}
