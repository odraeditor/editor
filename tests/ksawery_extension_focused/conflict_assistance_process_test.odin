// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

#+build linux
package ksawery_extension_focused

import ksawery "../../src/ksawery"
import "core:testing"

Conflict_Assistance_Process_Fixture :: struct {
	provider:              ksawery.Conflict_Assistance_Provider,
	provider_declaration:  ksawery.Contribution_Declaration,
	operation_declaration: ksawery.Contribution_Declaration,
	selection:             ksawery.Conflict_Assistance_Selection,
	request:               ksawery.Conflict_Assistance_Request,
	tool:                  ksawery.Conflict_Assistance_Tool_Plan,
	arguments:             [2]ksawery.Extension_Operation_Argument,
	index:                 ksawery.Conflict_Assistance_Index_Fingerprint,
}

/* conflict_assistance_process_fixture_init builds one admitted repository-neutral tool. */
conflict_assistance_process_fixture_init :: proc(
	fixture: ^Conflict_Assistance_Process_Fixture,
) -> bool {
	if fixture == nil do return false
	fixture^ = {}
	fixture.provider, fixture.provider_declaration = conflict_assistance_test_provider()
	fixture.selection = conflict_assistance_test_selection(fixture.provider)
	fixture.request = {
		request = 53,
		selection_generation = fixture.selection.generation,
		provider = fixture.selection.provider,
		target = conflict_assistance_test_target(),
	}
	if !ksawery.repository_context_assign(&fixture.request.target.repository, "/tmp") {
		return false
	}
	fixture.operation_declaration = {
		id = 59,
		kind = .External_Operation,
		required_observations = ksawery.CONFLICT_ASSISTANCE_TOOL_REFRESH,
		requested_authority = {.Inspect, .Submit_External_Operation},
	}
	if !ksawery.extension_identity_assign(
		&fixture.operation_declaration.identity,
		"conflict.tool",
	) {
		return false
	}
	identity: ksawery.Extension_Identity
	purpose: ksawery.Extension_Label
	executable: ksawery.Extension_Operation_Executable
	if !ksawery.extension_identity_assign(&identity, "conflict.tool") ||
	   !ksawery.extension_label_assign(&purpose, "Inspect conflict") ||
	   !ksawery.extension_operation_executable_assign_absolute(
		&executable,
		"tools.printf",
		"/usr/bin/printf",
	) ||
	   !ksawery.extension_operation_argument_assign(&fixture.arguments[0], "%s") ||
	   !ksawery.extension_operation_argument_assign(&fixture.arguments[1], "assisted") {
		return false
	}
	fixture.tool = {
		request = fixture.request.request,
		provider = fixture.request.provider,
		target = fixture.request.target,
		access = .Worktree_Only,
		operation = {
			contributor = fixture.provider.contributor,
			contribution = fixture.operation_declaration.id,
			plan = 61,
			generation = 67,
			identity = identity,
			purpose = purpose,
			executable = executable,
			arguments = fixture.arguments[:],
			effect = .Repository_Mutating,
			refresh = ksawery.CONFLICT_ASSISTANCE_TOOL_REFRESH,
			verifier = {kind = .None},
			environment = .Core_Repository,
			diagnostic_policy = .Bounded_Public,
			process_limits = ksawery.DEFAULT_EXTENSION_OPERATION_PROCESS_LIMITS,
		},
	}
	return ksawery.conflict_assistance_index_fingerprint_compute(
		&fixture.index,
		transmute([]u8)(string("100644 object 0\tpath\x00")),
	)
}

/* conflict_assistance_process_refresh builds complete post-tool core evidence. */
conflict_assistance_process_refresh :: proc(
	fixture: ^Conflict_Assistance_Process_Fixture,
) -> ksawery.Conflict_Assistance_Tool_Refresh_Evidence {
	target := fixture.request.target
	target.repository_generation += 1
	target.worktree_generation += 1
	target.observation_generation += 1
	return {
		repository = target.repository,
		repository_generation = target.repository_generation,
		worktree_generation = target.worktree_generation,
		observation_generation = target.observation_generation,
		attempted = ksawery.CONFLICT_ASSISTANCE_TOOL_REFRESH,
		completed = ksawery.CONFLICT_ASSISTANCE_TOOL_REFRESH,
		target_checked = true,
		target_present = true,
		target = target,
		index_after = fixture.index,
	}
}

/* conflict_assistance_process_result builds terminal external-operation evidence. */
conflict_assistance_process_result :: proc(
	fixture: ^Conflict_Assistance_Process_Fixture,
	admission: ksawery.Conflict_Assistance_Tool_Admission,
	output_bytes: u64,
) -> ksawery.Conflict_Assistance_Tool_Result {
	return {
		request = fixture.request.request,
		provider = fixture.request.provider,
		target = fixture.request.target,
		operation = {
			request = admission.operation.request,
			contributor = fixture.provider.contributor,
			plan = fixture.tool.operation.plan,
			plan_generation = fixture.tool.operation.generation,
			outcome = .Indeterminate,
			effect_possible = true,
			exit_code_present = true,
			exit_code = 0,
			refresh_completed = true,
			output_bytes = output_bytes,
		},
		refresh_completed = true,
		index_preserved = true,
		conflict_retained = true,
	}
}

/* Verifies one admitted helper runs through the existing external Process owner. */
@(test)
conflict_assistance_tool_uses_external_process_owner :: proc(t: ^testing.T) {
	fixture: Conflict_Assistance_Process_Fixture
	if !testing.expect(t, conflict_assistance_process_fixture_init(&fixture)) do return
	process, admission, started, failure :=
		ksawery.repository_process_start_conflict_assistance_tool(
			fixture.request,
			fixture.provider,
			fixture.selection,
			fixture.tool,
			fixture.provider_declaration,
			fixture.operation_declaration,
			fixture.index,
			fixture.provider.contributor,
			fixture.request.target.repository,
			fixture.request.target.repository_generation,
			1,
		)
	testing.expectf(t, started, "tool start failed: %v", failure.code)
	if !started do return
	defer ksawery.repository_process_close(&process)
	associated, association_failure := ksawery.repository_process_associate(
		&process,
		{
			authority = {
				operation = 71,
				repository = fixture.request.target.repository,
				observation_generation = fixture.request.target.observation_generation,
				kind = .External_Operation,
			},
			generation = 1,
		},
		1,
	)
	testing.expect_value(t, association_failure, ksawery.Failure_Code.None)
	if !testing.expect(t, associated) do return
	poll := operation_process_wait(&process)
	testing.expect_value(t, poll.state, ksawery.Repository_Process_State.Completed)
	view, output, diagnostic, available :=
		ksawery.repository_process_conflict_assistance_tool_snapshot(
			&process,
			admission,
			fixture.tool,
		)
	testing.expect(t, available)
	testing.expect_value(t, string(output), "assisted")
	testing.expect_value(t, len(diagnostic), 0)
	testing.expect_value(t, view.child.children_started, u32(1))
	testing.expect_value(t, view.child.children_reaped, u32(1))
	result := conflict_assistance_process_result(&fixture, admission, u64(len(output)))
	evidence := conflict_assistance_process_refresh(&fixture)
	failure = ksawery.conflict_assistance_tool_result_validate(
		result,
		admission,
		fixture.tool,
		evidence,
	)
	testing.expect_value(t, failure.code, ksawery.Conflict_Assistance_Failure_Code.None)
}

/* Verifies a provider cannot claim success with its own verifier. */
@(test)
conflict_assistance_tool_cannot_declare_success :: proc(t: ^testing.T) {
	fixture: Conflict_Assistance_Process_Fixture
	if !testing.expect(t, conflict_assistance_process_fixture_init(&fixture)) do return
	fixture.tool.operation.verifier = {
		kind = .Observation_Available,
		observation = .Conflict,
	}
	_, _, started, failure := ksawery.repository_process_start_conflict_assistance_tool(
		fixture.request,
		fixture.provider,
		fixture.selection,
		fixture.tool,
		fixture.provider_declaration,
		fixture.operation_declaration,
		fixture.index,
		fixture.provider.contributor,
		fixture.request.target.repository,
		fixture.request.target.repository_generation,
		1,
	)
	testing.expect(t, !started)
	testing.expect_value(t, failure.code, ksawery.Conflict_Assistance_Failure_Code.Invalid_Tool_Plan)
}

/* Verifies refreshed index mutation is rejected even after a zero exit. */
@(test)
conflict_assistance_tool_rejects_direct_index_mutation :: proc(t: ^testing.T) {
	fixture: Conflict_Assistance_Process_Fixture
	if !testing.expect(t, conflict_assistance_process_fixture_init(&fixture)) do return
	process, admission, started, _ := ksawery.repository_process_start_conflict_assistance_tool(
		fixture.request, fixture.provider, fixture.selection, fixture.tool,
		fixture.provider_declaration, fixture.operation_declaration, fixture.index,
		fixture.provider.contributor, fixture.request.target.repository,
		fixture.request.target.repository_generation, 1,
	)
	if !testing.expect(t, started) do return
	defer ksawery.repository_process_close(&process)
	result := conflict_assistance_process_result(&fixture, admission, 0)
	evidence := conflict_assistance_process_refresh(&fixture)
	assert(ksawery.conflict_assistance_index_fingerprint_compute(
		&evidence.index_after,
		transmute([]u8)(string("changed index")),
	))
	result.index_preserved = false
	failure := ksawery.conflict_assistance_tool_result_validate(
		result, admission, fixture.tool, evidence,
	)
	testing.expect_value(
		t,
		failure.code,
		ksawery.Conflict_Assistance_Failure_Code.Index_Mutation_Prohibited,
	)
}

/* Verifies Mark Resolved or sequence advancement cannot pass helper completion. */
@(test)
conflict_assistance_tool_preserves_separate_core_actions :: proc(t: ^testing.T) {
	fixture: Conflict_Assistance_Process_Fixture
	if !testing.expect(t, conflict_assistance_process_fixture_init(&fixture)) do return
	process, admission, started, _ := ksawery.repository_process_start_conflict_assistance_tool(
		fixture.request, fixture.provider, fixture.selection, fixture.tool,
		fixture.provider_declaration, fixture.operation_declaration, fixture.index,
		fixture.provider.contributor, fixture.request.target.repository,
		fixture.request.target.repository_generation, 1,
	)
	if !testing.expect(t, started) do return
	defer ksawery.repository_process_close(&process)
	result := conflict_assistance_process_result(&fixture, admission, 0)
	result.conflict_retained = false
	evidence := conflict_assistance_process_refresh(&fixture)
	evidence.target_present = false
	evidence.target = {}
	failure := ksawery.conflict_assistance_tool_result_validate(
		result, admission, fixture.tool, evidence,
	)
	testing.expect_value(
		t,
		failure.code,
		ksawery.Conflict_Assistance_Failure_Code.Core_Action_Prohibited,
	)
}
