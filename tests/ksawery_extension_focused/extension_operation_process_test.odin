// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

#+build linux
package ksawery_extension_focused

import ksawery "../../src/ksawery"
import "core:testing"
import "core:time"

Operation_Process_Fixture :: struct {
	submission:  ksawery.Extension_Operation_Submission,
	declaration: ksawery.Contribution_Declaration,
	plan:        ksawery.Extension_Operation_Plan,
	arguments:   [2]ksawery.Extension_Operation_Argument,
}

/* operation_process_fixture_init builds one current declared process request. */
operation_process_fixture_init :: proc(
	fixture: ^Operation_Process_Fixture,
	built_in_git: bool,
) -> bool {
	if fixture == nil do return false
	fixture^ = {}
	handle := ksawery.Contributor_Handle {
		contributor = 3,
		generation = 5,
	}
	repository: ksawery.Repository_Context
	if !ksawery.repository_context_assign(&repository, "/tmp") do return false
	fixture.submission = {
		request = 11,
		contributor = handle,
		contribution = 7,
		repository = repository,
		repository_generation = 9,
	}
	fixture.declaration = {
		id = 7,
		kind = .External_Operation,
		required_observations = {.Status, .Process},
		requested_authority = {.Inspect, .Submit_External_Operation},
	}
	if !ksawery.extension_identity_assign(
		&fixture.declaration.identity,
		"operations.execute",
	) {
		return false
	}
	fixture.plan = {
		contributor = handle,
		contribution = 7,
		plan = 13,
		generation = 17,
		effect = .Read_Only,
		refresh = {.Status, .Process},
		verifier = {kind = .None},
		environment = .Core_Repository,
		diagnostic_policy = .Bounded_Public,
		process_limits = ksawery.DEFAULT_EXTENSION_OPERATION_PROCESS_LIMITS,
	}
	if !ksawery.extension_identity_assign(&fixture.plan.identity, "operations.execute") ||
	   !ksawery.extension_label_assign(&fixture.plan.purpose, "Execute declared operation") {
		return false
	}
	if built_in_git {
		if !ksawery.extension_operation_executable_assign_git(&fixture.plan.executable) ||
		   !ksawery.extension_operation_argument_assign(&fixture.arguments[0], "--version") {
			return false
		}
		fixture.plan.arguments = fixture.arguments[:1]
		return true
	}
	if !ksawery.extension_operation_executable_assign_absolute(
		&fixture.plan.executable,
		"tools.printf",
		"/usr/bin/printf",
	) || !ksawery.extension_operation_argument_assign(&fixture.arguments[0], "%s") ||
	   !ksawery.extension_operation_argument_assign(&fixture.arguments[1], "owned") {
		return false
	}
	fixture.plan.arguments = fixture.arguments[:]
	return true
}

/* operation_process_wait polls one bounded external child to terminal state. */
operation_process_wait :: proc(
	process: ^ksawery.Repository_Process,
) -> ksawery.Repository_Process_Poll {
	now_ns := i64(1)
	for _ in 0 ..< 2_000 {
		poll, polled := ksawery.repository_process_poll(process, now_ns)
		if !polled do return {}
		if poll.state == .Completed || poll.state == .Failed do return poll
		time.sleep(time.Millisecond)
		now_ns += i64(time.Millisecond)
	}
	return {}
}

/* Verifies a configured absolute executable runs through the Process owner. */
@(test)
external_operation_runs_configured_child :: proc(t: ^testing.T) {
	fixture: Operation_Process_Fixture
	testing.expect(t, operation_process_fixture_init(&fixture, false))
	process, started, failure := ksawery.repository_process_start_extension_operation(
		fixture.submission,
		fixture.plan,
		fixture.declaration,
		fixture.submission.contributor,
		fixture.submission.repository,
		fixture.submission.repository_generation,
		1,
	)
	testing.expect(t, started)
	testing.expect_value(t, failure.code, ksawery.Extension_Operation_Failure_Code.None)
	if !started do return
	defer ksawery.repository_process_close(&process)
	fixture.arguments = {}
	poll := operation_process_wait(&process)
	testing.expect_value(t, poll.state, ksawery.Repository_Process_State.Completed)
	output, available := ksawery.repository_process_output(&process)
	testing.expect(t, available)
	testing.expect_value(t, string(output), "owned")
}

/* Verifies the built-in Git role resolves without a provider-supplied path. */
@(test)
external_operation_resolves_git_role :: proc(t: ^testing.T) {
	fixture: Operation_Process_Fixture
	testing.expect(t, operation_process_fixture_init(&fixture, true))
	process, started, failure := ksawery.repository_process_start_extension_operation(
		fixture.submission,
		fixture.plan,
		fixture.declaration,
		fixture.submission.contributor,
		fixture.submission.repository,
		fixture.submission.repository_generation,
		1,
	)
	testing.expect(t, started)
	testing.expect_value(t, failure.code, ksawery.Extension_Operation_Failure_Code.None)
	if !started do return
	defer ksawery.repository_process_close(&process)
	poll := operation_process_wait(&process)
	testing.expect_value(t, poll.state, ksawery.Repository_Process_State.Completed)
	output, available := ksawery.repository_process_output(&process)
	testing.expect(t, available)
	testing.expect(t, len(output) >= 3 && string(output[:3]) == "git")
}

/* Verifies external children receive only the fixed core-owned environment. */
@(test)
external_operation_uses_core_environment :: proc(t: ^testing.T) {
	fixture: Operation_Process_Fixture
	testing.expect(t, operation_process_fixture_init(&fixture, false))
	testing.expect(t, ksawery.extension_operation_executable_assign_absolute(
		&fixture.plan.executable,
		"tools.environment",
		"/usr/bin/env",
	))
	fixture.plan.arguments = nil
	process, started, _ := ksawery.repository_process_start_extension_operation(
		fixture.submission,
		fixture.plan,
		fixture.declaration,
		fixture.submission.contributor,
		fixture.submission.repository,
		fixture.submission.repository_generation,
		1,
	)
	testing.expect(t, started)
	if !started do return
	defer ksawery.repository_process_close(&process)
	poll := operation_process_wait(&process)
	testing.expect_value(t, poll.state, ksawery.Repository_Process_State.Completed)
	output, available := ksawery.repository_process_output(&process)
	testing.expect(t, available)
	testing.expect_value(
		t,
		string(output),
		"PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin\n" +
			"LANG=C\nLC_ALL=C\nGIT_TERMINAL_PROMPT=0\n",
	)
}

/* Verifies the Process owner fails closed when output exceeds the declared limit. */
@(test)
external_operation_enforces_output_limit :: proc(t: ^testing.T) {
	fixture: Operation_Process_Fixture
	testing.expect(t, operation_process_fixture_init(&fixture, false))
	fixture.plan.process_limits.output_bytes = 3
	process, started, failure := ksawery.repository_process_start_extension_operation(
		fixture.submission,
		fixture.plan,
		fixture.declaration,
		fixture.submission.contributor,
		fixture.submission.repository,
		fixture.submission.repository_generation,
		1,
	)
	testing.expect(t, started)
	testing.expect_value(t, failure.code, ksawery.Extension_Operation_Failure_Code.None)
	if !started do return
	defer ksawery.repository_process_close(&process)
	poll := operation_process_wait(&process)
	testing.expect_value(t, poll.state, ksawery.Repository_Process_State.Failed)
	testing.expect_value(t, poll.failure, ksawery.Failure_Code.Output_Limit)
	output, available := ksawery.repository_process_output(&process)
	testing.expect(t, !available && len(output) == 0)
}

/* Verifies stale generations and unavailable declarations fail before start. */
@(test)
external_operation_rejects_stale_context :: proc(t: ^testing.T) {
	fixture: Operation_Process_Fixture
	testing.expect(t, operation_process_fixture_init(&fixture, false))
	_, started, failure := ksawery.repository_process_start_extension_operation(
		fixture.submission,
		fixture.plan,
		fixture.declaration,
		fixture.submission.contributor,
		fixture.submission.repository,
		10,
		1,
	)
	testing.expect(t, !started)
	testing.expect_value(t, failure.code, ksawery.Extension_Operation_Failure_Code.Stale_Repository)
	other_repository: ksawery.Repository_Context
	testing.expect(t, ksawery.repository_context_assign(&other_repository, "/var/tmp"))
	_, started, failure = ksawery.repository_process_start_extension_operation(
		fixture.submission,
		fixture.plan,
		fixture.declaration,
		fixture.submission.contributor,
		other_repository,
		fixture.submission.repository_generation,
		1,
	)
	testing.expect(t, !started)
	testing.expect_value(t, failure.code, ksawery.Extension_Operation_Failure_Code.Stale_Repository)

	stale_contributor := fixture.submission.contributor
	stale_contributor.generation += 1
	_, started, failure = ksawery.repository_process_start_extension_operation(
		fixture.submission,
		fixture.plan,
		fixture.declaration,
		stale_contributor,
		fixture.submission.repository,
		fixture.submission.repository_generation,
		1,
	)
	testing.expect(t, !started)
	testing.expect_value(t, failure.code, ksawery.Extension_Operation_Failure_Code.Stale_Contributor)

	fixture.declaration.requested_authority = {.Inspect}
	_, started, failure = ksawery.repository_process_start_extension_operation(
		fixture.submission,
		fixture.plan,
		fixture.declaration,
		fixture.submission.contributor,
		fixture.submission.repository,
		fixture.submission.repository_generation,
		1,
	)
	testing.expect(t, !started)
	testing.expect_value(
		t,
		failure.code,
		ksawery.Extension_Operation_Failure_Code.Contribution_Unavailable,
	)

	fixture.declaration.requested_authority = {.Inspect, .Submit_External_Operation}
	testing.expect(t, ksawery.extension_operation_executable_assign_absolute(
		&fixture.plan.executable,
		"tools.missing",
		"/not-installed/odra-operation-tool",
	))
	_, started, failure = ksawery.repository_process_start_extension_operation(
		fixture.submission,
		fixture.plan,
		fixture.declaration,
		fixture.submission.contributor,
		fixture.submission.repository,
		fixture.submission.repository_generation,
		1,
	)
	testing.expect(t, !started)
	testing.expect_value(
		t,
		failure.code,
		ksawery.Extension_Operation_Failure_Code.Executable_Unavailable,
	)
}
