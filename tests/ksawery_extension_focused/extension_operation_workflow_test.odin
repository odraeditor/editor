// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

#+build linux
package ksawery_extension_focused

import bridge "../../src/ksawery_bridge"
import odra "../../src/ksawery_module"
import ksawery "../../src/ksawery"
import "core:encoding/endian"
import "core:testing"
import "core:time"

/* operation_workflow_encoded_plan builds one complete Racket-plan ABI value. */
operation_workflow_encoded_plan :: proc() -> [dynamic]u8 {
	contributor :: "personal.repository-tools"
	identity :: "operations.execute"
	purpose :: "Execute declared operation"
	executable :: "git"
	argument :: "--version"
	text_value := contributor + identity + purpose + executable + argument
	text := transmute([]u8)(string(text_value))
	identity_offset := len(contributor)
	purpose_offset := identity_offset + len(identity)
	executable_offset := purpose_offset + len(purpose)
	argument_offset := executable_offset + len(executable)
	record_bytes := int(
		bridge.KSAWERY_EXTENSION_OPERATION_HEADER_BYTES +
		bridge.KSAWERY_EXTENSION_OPERATION_LIMITS_BYTES +
		bridge.KSAWERY_EXTENSION_OPERATION_VERIFIER_BYTES +
		bridge.KSAWERY_EXTENSION_OPERATION_ARGUMENT_BYTES + u64(len(text)),
	)
	words := [?]u64 {
		bridge.KSAWERY_EXTENSION_OPERATION_SCHEMA_VERSION, u64(record_bytes), 5, 7,
		13, 17, u64(ksawery.Extension_Operation_Effect.Read_Only),
		u64(1 << u64(ksawery.Extension_Observation_Family.Status) |
		    1 << u64(ksawery.Extension_Observation_Family.Process)),
		u64(ksawery.Extension_Operation_Environment_Profile.Core_Repository),
		u64(ksawery.Extension_Operation_Diagnostic_Policy.Bounded_Public),
		u64(ksawery.Extension_Operation_Executable_Kind.Built_In_Git), 1,
		0, u64(len(contributor)), u64(identity_offset), u64(len(identity)),
		u64(purpose_offset), u64(len(purpose)), u64(executable_offset), u64(len(executable)),
		0, 0, u64(len(text)), 0,
		ksawery.DEFAULT_EXTENSION_OPERATION_OUTPUT_BYTES,
		ksawery.DEFAULT_EXTENSION_OPERATION_DIAGNOSTIC_BYTES,
		u64(ksawery.DEFAULT_EXTENSION_OPERATION_DEADLINE_NS),
		u64(ksawery.DEFAULT_EXTENSION_OPERATION_CANCELLATION_GRACE_NS),
		u64(ksawery.Extension_Operation_Verifier_Kind.Observation_Available),
		u64(ksawery.Extension_Observation_Family.Status), 0, 0, 0, 0, 0,
		u64(argument_offset), u64(len(argument)),
	}
	result, allocation_error := make([dynamic]u8, record_bytes)
	assert(allocation_error == nil)
	for value, index in words do assert(endian.put_u64(result[index * 8:], .Little, value))
	copy(result[len(words) * 8:], text)
	return result
}

/* operation_workflow_wait advances one owned child until refresh is required. */
operation_workflow_wait :: proc(
	workflow: ^odra.Ksawery_Extension_Operation_Workflow,
	coordinator: ^odra.Ksawery_Process_Coordinator,
	start_ns := i64(2),
) -> (
	odra.Ksawery_Extension_Operation_Refresh_Request,
	bool,
	odra.Ksawery_Extension_Operation_Workflow_Failure,
) {
	now_ns := start_ns
	for _ in 0 ..< 2_000 {
		request, ready, failure := odra.ksawery_extension_operation_workflow_poll(
			workflow,
			coordinator,
			now_ns,
		)
		if failure.code != .None {
			return {}, false, failure
		}
		if ready do return request, true, {}
		time.sleep(time.Millisecond)
		now_ns += i64(time.Millisecond)
	}
	return {}, false, {code = .Process_Evidence_Rejected, process = .Timeout}
}

/* operation_workflow_begin starts one fixture through the application coordinator. */
operation_workflow_begin :: proc(
	fixture: ^Operation_Process_Fixture,
	workflow: ^odra.Ksawery_Extension_Operation_Workflow,
	coordinator: ^odra.Ksawery_Process_Coordinator,
) -> bool {
	if fixture == nil || workflow == nil || coordinator == nil ||
	   !odra.ksawery_process_coordinator_init(coordinator, fixture.submission.repository) {
		return false
	}
	started, failure := odra.ksawery_extension_operation_workflow_begin(
		workflow,
		coordinator,
		fixture.submission,
		fixture.plan,
		fixture.declaration,
		fixture.submission.contributor,
		fixture.submission.repository,
		fixture.submission.repository_generation,
		1,
	)
	return started && failure.code == .None
}

/* operation_refresh_evidence completes the exact declared observation set. */
operation_refresh_evidence :: proc(
	fixture: ^Operation_Process_Fixture,
) -> ksawery.Extension_Operation_Refresh_Evidence {
	return {
		repository = fixture.submission.repository,
		repository_generation = fixture.submission.repository_generation + 1,
		attempted = fixture.plan.refresh,
		completed = fixture.plan.refresh,
	}
}

/* Verifies one encoded plan is decoded, scoped, authorized, and Process-owned. */
@(test)
external_operation_workflow_admits_authorized_encoded_plan :: proc(t: ^testing.T) {
	registry: odra.Ksawery_Extension_Provider_Registry
	if !testing.expect(t, odra.ksawery_extension_provider_registry_init(&registry)) do return
	defer odra.ksawery_extension_provider_registry_close(&registry)
	batch := extension_provider_batch(2, 5)
	defer delete(batch)
	authorities := u64(1 << u64(ksawery.Extension_Authority.Inspect) |
	                   1 << u64(ksawery.Extension_Authority.Submit_External_Operation))
	observations := u64(1 << u64(ksawery.Extension_Observation_Family.Status) |
	                    1 << u64(ksawery.Extension_Observation_Family.Process))
	assert(endian.put_u64(batch[22 * 8:], .Little, authorities))
	assert(endian.put_u64(batch[29 * 8:], .Little, u64(ksawery.Contribution_Kind.External_Operation)))
	assert(endian.put_u64(batch[31 * 8:], .Little, observations))
	assert(endian.put_u64(batch[32 * 8:], .Little, authorities))
	candidate, prepared, _ := odra.ksawery_extension_provider_prepare(&registry, batch[:], 2)
	if !testing.expect(t, prepared) do return
	testing.expect(t, odra.ksawery_extension_provider_candidate_confirm(&candidate))
	activated, _ := odra.ksawery_extension_provider_activate(&registry, &candidate)
	if !testing.expect(t, activated) do return
	scope := extension_provider_scope(5)
	testing.expect(t, ksawery.repository_context_assign(&scope.repository, "/tmp"))
	capability, began, _ := odra.ksawery_extension_provider_turn_begin(
		&registry,
		scope,
		{.Submit_External_Operation},
	)
	if !testing.expect(t, began) do return
	defer if registry.active.turn_active do odra.ksawery_extension_provider_turn_end(&registry)
	current_scope := scope
	current_scope.capability_generation = capability.generation
	coordinator: odra.Ksawery_Process_Coordinator
	if !testing.expect(t, odra.ksawery_process_coordinator_init(&coordinator, scope.repository)) do return
	defer odra.ksawery_process_coordinator_close(&coordinator)
	workflow: odra.Ksawery_Extension_Operation_Workflow
	defer if workflow.process.state != nil do ksawery.repository_process_close(&workflow.process)
	encoded := operation_workflow_encoded_plan()
	defer delete(encoded)
	mutating := operation_workflow_encoded_plan()
	defer delete(mutating)
	assert(endian.put_u64(
		mutating[6 * 8:],
		.Little,
		u64(ksawery.Extension_Operation_Effect.Repository_Mutating),
	))
	mutation_started, mutation_failure := odra.ksawery_extension_operation_workflow_begin_encoded(
		&workflow, &coordinator, &registry, mutating[:], 40, capability, current_scope,
		scope.owner_thread, 1, 1, 1,
	)
	testing.expect(t, !mutation_started)
	testing.expect_value(
		t, mutation_failure.code,
		odra.Ksawery_Extension_Operation_Workflow_Failure_Code.Admission_Rejected,
	)
	stale := operation_workflow_encoded_plan()
	defer delete(stale)
	assert(endian.put_u64(stale[2 * 8:], .Little, 6))
	stale_started, stale_failure := odra.ksawery_extension_operation_workflow_begin_encoded(
		&workflow, &coordinator, &registry, stale[:], 40, capability, current_scope,
		scope.owner_thread, 1, 1, 1,
	)
	testing.expect(t, !stale_started)
	testing.expect_value(
		t, stale_failure.code,
		odra.Ksawery_Extension_Operation_Workflow_Failure_Code.Decode_Rejected,
	)
	malformed := operation_workflow_encoded_plan()
	defer delete(malformed)
	argument_offset, offset_ok := endian.get_u64(malformed[35 * 8:], .Little)
	assert(offset_ok)
	text_offset := int(
		bridge.KSAWERY_EXTENSION_OPERATION_HEADER_BYTES +
		bridge.KSAWERY_EXTENSION_OPERATION_LIMITS_BYTES +
		bridge.KSAWERY_EXTENSION_OPERATION_VERIFIER_BYTES +
		bridge.KSAWERY_EXTENSION_OPERATION_ARGUMENT_BYTES,
	)
	malformed[text_offset + int(argument_offset)] = 0
	malformed_started, malformed_failure :=
		odra.ksawery_extension_operation_workflow_begin_encoded(
			&workflow, &coordinator, &registry, malformed[:], 40, capability, current_scope,
			scope.owner_thread, 1, 1, 1,
		)
	testing.expect(t, !malformed_started)
	testing.expect_value(
		t, malformed_failure.code,
		odra.Ksawery_Extension_Operation_Workflow_Failure_Code.Decode_Rejected,
	)
	started, start_failure := odra.ksawery_extension_operation_workflow_begin_encoded(
		&workflow,
		&coordinator,
		&registry,
		encoded[:],
		41,
		capability,
		current_scope,
		scope.owner_thread,
		1,
		1,
		1,
	)
	testing.expectf(t, started, "encoded admission failed: %v/%v/%v", start_failure.code,
		start_failure.provider.code, start_failure.extension.code)
	if !started do return
	second_workflow: odra.Ksawery_Extension_Operation_Workflow
	second_started, second_failure := odra.ksawery_extension_operation_workflow_begin_encoded(
		&second_workflow, &coordinator, &registry, encoded[:], 42, capability, current_scope,
		scope.owner_thread, 1, 1, 2,
	)
	testing.expect(t, !second_started)
	testing.expect_value(
		t, second_failure.code,
		odra.Ksawery_Extension_Operation_Workflow_Failure_Code.Operation_Active,
	)
	_, ready, wait_failure := operation_workflow_wait(&workflow, &coordinator)
	testing.expectf(t, ready, "encoded operation did not finish: %v", wait_failure.code)
	if !ready do return
	evidence := ksawery.Extension_Operation_Refresh_Evidence {
		repository = scope.repository,
		repository_generation = scope.repository_generation + 1,
		attempted = {.Status, .Process},
		completed = {.Status, .Process},
	}
	completed, completion_failure := odra.ksawery_extension_operation_workflow_complete(
		&workflow,
		&coordinator,
		evidence,
		20_000_000,
	)
	testing.expectf(t, completed, "encoded completion failed: %v", completion_failure.code)
	result, inspected := odra.ksawery_extension_operation_workflow_inspect(&workflow)
	testing.expect(t, inspected)
	if inspected {
		testing.expect_value(t, result.request, ksawery.Extension_Operation_Request_ID(41))
		testing.expect_value(t, result.outcome, ksawery.Repository_Process_Outcome.Verified_Success)
	}
}

/* Verifies zero exit becomes success only after refreshed typed agreement. */
@(test)
external_operation_workflow_verifies_success :: proc(t: ^testing.T) {
	fixture: Operation_Process_Fixture
	testing.expect(t, operation_process_fixture_init(&fixture, false))
	fixture.plan.verifier = {
		kind = .Observation_Available,
		observation = .Status,
	}
	workflow: odra.Ksawery_Extension_Operation_Workflow
	coordinator: odra.Ksawery_Process_Coordinator
	testing.expect(t, operation_workflow_begin(&fixture, &workflow, &coordinator))
	defer odra.ksawery_process_coordinator_close(&coordinator)
	request, ready, wait_failure := operation_workflow_wait(&workflow, &coordinator)
	testing.expect(t, ready)
	testing.expect_value(t, wait_failure.code, odra.Ksawery_Extension_Operation_Workflow_Failure_Code.None)
	testing.expect_value(t, request.observations, fixture.plan.refresh)
	evidence := operation_refresh_evidence(&fixture)
	completed, failure := odra.ksawery_extension_operation_workflow_complete(
		&workflow,
		&coordinator,
		evidence,
		20_000_000,
	)
	testing.expect(t, completed)
	testing.expect_value(t, failure.code, odra.Ksawery_Extension_Operation_Workflow_Failure_Code.None)
	result, inspected := odra.ksawery_extension_operation_workflow_inspect(&workflow)
	testing.expect(t, inspected)
	testing.expect_value(t, result.outcome, ksawery.Repository_Process_Outcome.Verified_Success)
	testing.expect(t, result.refresh_completed && result.verifier_applied && result.verifier_agreed)
	record, found := odra.ksawery_process_coordinator_record(
		&coordinator,
		coordinator.record_count - 1,
	)
	testing.expect(t, found)
	if found {
		descriptor, described := ksawery.process_record_descriptor(record)
		testing.expect(t, described)
		testing.expect_value(t, descriptor.progress.kind, ksawery.Process_Progress_Kind.Determinate)
		testing.expect_value(t, descriptor.action_count, u8(2))
		testing.expect_value(t, descriptor.actions[0].kind, ksawery.Process_Action_Kind.Inspect)
		testing.expect_value(t, descriptor.actions[1].kind, ksawery.Process_Action_Kind.Clear)
		public_output, copied := ksawery.process_record_text(record, descriptor.content.output)
		testing.expect(t, copied && len(public_output) == 0)
		testing.expect(t, descriptor.content.output_truncated)
	}
	testing.expect(t, workflow.process.state == nil)
	testing.expect(t, !coordinator.active && !coordinator.child_attached)
}

/* Verifies refreshed operation-state disagreement cannot become success. */
@(test)
external_operation_workflow_detects_mismatch :: proc(t: ^testing.T) {
	fixture: Operation_Process_Fixture
	testing.expect(t, operation_process_fixture_init(&fixture, false))
	fixture.plan.verifier = {
		kind = .Operation_State,
		observation = .Status,
		operation = .Normal,
	}
	workflow: odra.Ksawery_Extension_Operation_Workflow
	coordinator: odra.Ksawery_Process_Coordinator
	testing.expect(t, operation_workflow_begin(&fixture, &workflow, &coordinator))
	defer odra.ksawery_process_coordinator_close(&coordinator)
	_, ready, _ := operation_workflow_wait(&workflow, &coordinator)
	testing.expect(t, ready)
	evidence := operation_refresh_evidence(&fixture)
	evidence.operation_checked = true
	evidence.operation = .Rebasing
	completed, _ := odra.ksawery_extension_operation_workflow_complete(
		&workflow,
		&coordinator,
		evidence,
		20_000_000,
	)
	testing.expect(t, completed)
	result, inspected := odra.ksawery_extension_operation_workflow_inspect(&workflow)
	testing.expect(t, inspected)
	testing.expect_value(t, result.outcome, ksawery.Repository_Process_Outcome.Verification_Mismatch)
	testing.expect(t, result.verifier_applied && !result.verifier_agreed)
}

/* Verifies nonzero exit and bounded public diagnostics remain known failure. */
@(test)
external_operation_workflow_classifies_failure :: proc(t: ^testing.T) {
	fixture: Operation_Process_Fixture
	testing.expect(t, operation_process_fixture_init(&fixture, false))
	testing.expect(t, ksawery.extension_operation_executable_assign_absolute(
		&fixture.plan.executable,
		"tools.list",
		"/bin/ls",
	))
	testing.expect(t, ksawery.extension_operation_argument_assign(
		&fixture.arguments[0],
		"/definitely-missing-odra-operation-path",
	))
	fixture.plan.arguments = fixture.arguments[:1]
	workflow: odra.Ksawery_Extension_Operation_Workflow
	coordinator: odra.Ksawery_Process_Coordinator
	testing.expect(t, operation_workflow_begin(&fixture, &workflow, &coordinator))
	defer odra.ksawery_process_coordinator_close(&coordinator)
	_, ready, _ := operation_workflow_wait(&workflow, &coordinator)
	testing.expect(t, ready)
	evidence := operation_refresh_evidence(&fixture)
	completed, _ := odra.ksawery_extension_operation_workflow_complete(
		&workflow,
		&coordinator,
		evidence,
		20_000_000,
	)
	testing.expect(t, completed)
	result, inspected := odra.ksawery_extension_operation_workflow_inspect(&workflow)
	testing.expect(t, inspected)
	testing.expect_value(t, result.outcome, ksawery.Repository_Process_Outcome.Known_Failure)
	testing.expect(t, result.exit_code_present && result.exit_code != 0)
	testing.expect(t, result.diagnostic_bytes > 0)
	record, found := odra.ksawery_process_coordinator_record(
		&coordinator,
		coordinator.record_count - 1,
	)
	testing.expect(t, found)
	if found {
		descriptor, described := ksawery.process_record_descriptor(record)
		diagnostic, copied := ksawery.process_record_text(record, descriptor.content.diagnostic)
		testing.expect(t, described && copied && len(diagnostic) > 0)
	}
}

/* Verifies suppressed diagnostics never enter the public Process record or result. */
@(test)
external_operation_workflow_suppresses_private_diagnostics :: proc(t: ^testing.T) {
	fixture: Operation_Process_Fixture
	testing.expect(t, operation_process_fixture_init(&fixture, false))
	testing.expect(t, ksawery.extension_operation_executable_assign_absolute(
		&fixture.plan.executable,
		"tools.list",
		"/bin/ls",
	))
	testing.expect(t, ksawery.extension_operation_argument_assign(
		&fixture.arguments[0],
		"/definitely-missing-private-operation-path",
	))
	fixture.plan.arguments = fixture.arguments[:1]
	fixture.plan.diagnostic_policy = .Suppressed
	workflow: odra.Ksawery_Extension_Operation_Workflow
	coordinator: odra.Ksawery_Process_Coordinator
	testing.expect(t, operation_workflow_begin(&fixture, &workflow, &coordinator))
	defer odra.ksawery_process_coordinator_close(&coordinator)
	_, ready, wait_failure := operation_workflow_wait(&workflow, &coordinator)
	testing.expectf(t, ready, "suppressed operation did not finish: %v", wait_failure.code)
	if !ready do return
	evidence := operation_refresh_evidence(&fixture)
	completed, completion_failure := odra.ksawery_extension_operation_workflow_complete(
		&workflow,
		&coordinator,
		evidence,
		20_000_000,
	)
	testing.expectf(t, completed, "suppressed completion failed: %v", completion_failure.code)
	result, inspected := odra.ksawery_extension_operation_workflow_inspect(&workflow)
	testing.expect(t, inspected)
	if inspected {
		testing.expect_value(t, result.outcome, ksawery.Repository_Process_Outcome.Known_Failure)
		testing.expect_value(t, result.diagnostic_bytes, u64(0))
		testing.expect(t, !result.diagnostic_truncated)
	}
	record, found := odra.ksawery_process_coordinator_record(
		&coordinator,
		coordinator.record_count - 1,
	)
	testing.expect(t, found)
	if found {
		descriptor, described := ksawery.process_record_descriptor(record)
		diagnostic, copied := ksawery.process_record_text(record, descriptor.content.diagnostic)
		testing.expect(t, described && copied && len(diagnostic) == 0)
		testing.expect(t, !descriptor.content.diagnostic_truncated)
	}
}

/* Verifies exact-generation cancellation records possible mutating effect. */
@(test)
external_operation_workflow_classifies_cancel :: proc(t: ^testing.T) {
	fixture: Operation_Process_Fixture
	testing.expect(t, operation_process_fixture_init(&fixture, false))
	testing.expect(t, ksawery.extension_operation_executable_assign_absolute(
		&fixture.plan.executable,
		"tools.sleep",
		"/usr/bin/sleep",
	))
	testing.expect(t, ksawery.extension_operation_argument_assign(&fixture.arguments[0], "10"))
	fixture.plan.arguments = fixture.arguments[:1]
	fixture.plan.effect = .Repository_Mutating
	workflow: odra.Ksawery_Extension_Operation_Workflow
	coordinator: odra.Ksawery_Process_Coordinator
	testing.expect(t, operation_workflow_begin(&fixture, &workflow, &coordinator))
	defer odra.ksawery_process_coordinator_close(&coordinator)
	cancelled, cancel_failure := odra.ksawery_extension_operation_workflow_cancel(
		&workflow,
		&coordinator,
		2,
	)
	testing.expect(t, cancelled)
	testing.expect_value(t, cancel_failure.code, odra.Ksawery_Extension_Operation_Workflow_Failure_Code.None)
	_, ready, wait_failure := operation_workflow_wait(&workflow, &coordinator, 3)
	testing.expect(t, ready)
	testing.expect_value(t, wait_failure.code, odra.Ksawery_Extension_Operation_Workflow_Failure_Code.None)
	testing.expect_value(t, wait_failure.process, ksawery.Failure_Code.None)
	evidence := operation_refresh_evidence(&fixture)
	completed, _ := odra.ksawery_extension_operation_workflow_complete(
		&workflow,
		&coordinator,
		evidence,
		20_000_000,
	)
	testing.expect(t, completed)
	result, inspected := odra.ksawery_extension_operation_workflow_inspect(&workflow)
	testing.expect(t, inspected)
	testing.expect_value(
		t,
		result.outcome,
		ksawery.Repository_Process_Outcome.Cancelled_After_Possible_Effect,
	)
}

/* Verifies deadline termination records possible mutating effect after refresh. */
@(test)
external_operation_workflow_classifies_timeout :: proc(t: ^testing.T) {
	fixture: Operation_Process_Fixture
	testing.expect(t, operation_process_fixture_init(&fixture, false))
	testing.expect(t, ksawery.extension_operation_executable_assign_absolute(
		&fixture.plan.executable,
		"tools.sleep",
		"/usr/bin/sleep",
	))
	testing.expect(t, ksawery.extension_operation_argument_assign(&fixture.arguments[0], "10"))
	fixture.plan.arguments = fixture.arguments[:1]
	fixture.plan.effect = .Repository_Mutating
	fixture.plan.process_limits.deadline_nanoseconds = ksawery.MIN_EXTENSION_OPERATION_DEADLINE_NS
	fixture.plan.process_limits.cancellation_grace_ns = 10_000_000
	workflow: odra.Ksawery_Extension_Operation_Workflow
	coordinator: odra.Ksawery_Process_Coordinator
	testing.expect(t, operation_workflow_begin(&fixture, &workflow, &coordinator))
	defer odra.ksawery_process_coordinator_close(&coordinator)
	_, ready, _ := operation_workflow_wait(
		&workflow,
		&coordinator,
		ksawery.MIN_EXTENSION_OPERATION_DEADLINE_NS + 2,
	)
	testing.expect(t, ready)
	evidence := operation_refresh_evidence(&fixture)
	completed, _ := odra.ksawery_extension_operation_workflow_complete(
		&workflow,
		&coordinator,
		evidence,
		200_000_000,
	)
	testing.expect(t, completed)
	result, inspected := odra.ksawery_extension_operation_workflow_inspect(&workflow)
	testing.expect(t, inspected)
	testing.expect_value(
		t,
		result.outcome,
		ksawery.Repository_Process_Outcome.Timed_Out_After_Possible_Effect,
	)
}

/* Verifies incomplete refresh after possible effect stays indeterminate. */
@(test)
external_operation_workflow_marks_indeterminate :: proc(t: ^testing.T) {
	fixture: Operation_Process_Fixture
	testing.expect(t, operation_process_fixture_init(&fixture, false))
	fixture.plan.effect = .Repository_Mutating
	fixture.plan.verifier = {
		kind = .Observation_Available,
		observation = .Process,
	}
	workflow: odra.Ksawery_Extension_Operation_Workflow
	coordinator: odra.Ksawery_Process_Coordinator
	testing.expect(t, operation_workflow_begin(&fixture, &workflow, &coordinator))
	defer odra.ksawery_process_coordinator_close(&coordinator)
	_, ready, _ := operation_workflow_wait(&workflow, &coordinator)
	testing.expect(t, ready)
	evidence := operation_refresh_evidence(&fixture)
	evidence.completed = {.Status}
	completed, _ := odra.ksawery_extension_operation_workflow_complete(
		&workflow,
		&coordinator,
		evidence,
		20_000_000,
	)
	testing.expect(t, completed)
	result, inspected := odra.ksawery_extension_operation_workflow_inspect(&workflow)
	testing.expect(t, inspected)
	testing.expect_value(t, result.outcome, ksawery.Repository_Process_Outcome.Indeterminate)
	testing.expect(t, result.effect_possible && !result.refresh_completed)
}
