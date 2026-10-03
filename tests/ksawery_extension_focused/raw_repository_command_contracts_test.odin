// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery_extension_focused

import ksawery "../../src/ksawery"
import "core:testing"

/* raw_repository_command_test_intent builds one complete session-local proposal. */
raw_repository_command_test_intent :: proc(
	mode := ksawery.Raw_Repository_Command_Mode.Git,
	verifier := ksawery.Raw_Repository_Command_Verifier{},
) -> ksawery.Raw_Repository_Command_Intent {
	repository: ksawery.Repository_Context
	assert(ksawery.repository_context_assign(&repository, "/tmp"))
	input: ksawery.Raw_Repository_Command_Input
	text := "status --short"
	if mode == .Shell do text = "printf '%s' raw"
	assigned, _ := ksawery.raw_repository_command_input_assign(&input, mode, text)
	assert(assigned)
	return {
		command = 11,
		repository = repository,
		repository_generation = 13,
		observation_generation = 17,
		input = input,
		verifier = verifier,
		refresh = ksawery.RAW_REPOSITORY_COMMAND_REFRESH,
		authority = .Explicit_User_Confirmation,
		redaction = .Omit_Sensitive_Content,
		retention = .Session_Transient,
		limits = ksawery.DEFAULT_RAW_REPOSITORY_COMMAND_LIMITS,
	}
}

/* raw_repository_command_test_request consumes one exact confirmed intent. */
raw_repository_command_test_request :: proc(
	intent: ksawery.Raw_Repository_Command_Intent,
) -> ksawery.Raw_Repository_Command_Request {
	confirmation, prepared, _ := ksawery.raw_repository_command_confirmation_prepare(intent, 19)
	assert(prepared)
	confirmed, _ := ksawery.raw_repository_command_confirmation_confirm(&confirmation, 19, intent)
	assert(confirmed)
	request, requested, _ := ksawery.raw_repository_command_request_prepare(23, intent, &confirmation)
	assert(requested)
	return request
}

/* raw_repository_command_test_result builds one cleaned terminal Process result. */
raw_repository_command_test_result :: proc(
	request: ksawery.Raw_Repository_Command_Request,
) -> ksawery.Raw_Repository_Command_Result {
	return {
		command = request.intent.command,
		mode = request.intent.input.mode,
		repository = request.intent.repository,
		process = {
			association = {
				authority = {
					operation = request.operation,
					repository = request.intent.repository,
					observation_generation = request.intent.observation_generation,
					kind = .Raw_Command,
				},
				generation = 29,
			},
			started = true,
			detached = true,
		},
		outcome = .Indeterminate,
		effect_possible = true,
		exit_code_present = true,
		exit_code = 0,
		refresh_completed = true,
		output_bytes = 32,
		diagnostic_bytes = 8,
		cleanup = {
			input_cleared = true,
			confirmation_cleared = true,
			child_closed = true,
			association_detached = true,
		},
	}
}

/* Verifies Git and shell input remain bounded, private, and free of control bytes. */
@(test)
raw_repository_command_input_is_transient_and_bounded :: proc(t: ^testing.T) {
	git: ksawery.Raw_Repository_Command_Input
	assigned, failure := ksawery.raw_repository_command_input_assign(&git, .Git, "status --short")
	testing.expect(t, assigned)
	testing.expect_value(t, failure.code, ksawery.Raw_Repository_Command_Failure_Code.None)
	testing.expect_value(t, ksawery.raw_repository_command_input_text(&git), "status --short")

	shell: ksawery.Raw_Repository_Command_Input
	assigned, _ = ksawery.raw_repository_command_input_assign(&shell, .Shell, "printf '%s' value")
	testing.expect(t, assigned)
	testing.expect_value(t, shell.mode, ksawery.Raw_Repository_Command_Mode.Shell)

	_, failure = ksawery.raw_repository_command_input_assign(&shell, .Shell, "printf x\nrm -rf x")
	testing.expect_value(t, failure.code, ksawery.Raw_Repository_Command_Failure_Code.Invalid_Input)
	_, failure = ksawery.raw_repository_command_input_assign(&shell, .Shell, "token\x00value")
	testing.expect_value(t, failure.code, ksawery.Raw_Repository_Command_Failure_Code.Invalid_Input)
	_, failure = ksawery.raw_repository_command_input_assign(&shell, .Git, "   ")
	testing.expect_value(t, failure.code, ksawery.Raw_Repository_Command_Failure_Code.Invalid_Input)

	oversized: [ksawery.MAX_RAW_REPOSITORY_COMMAND_BYTES + 1]u8
	for &value in oversized do value = 'x'
	_, failure = ksawery.raw_repository_command_input_assign(
		&shell,
		.Shell,
		string(oversized[:]),
		ksawery.MAX_RAW_REPOSITORY_COMMAND_BYTES,
	)
	testing.expect_value(t, failure.code, ksawery.Raw_Repository_Command_Failure_Code.Input_Limit)
}

/* Verifies exact confirmation is one-shot and private text clears explicitly. */
@(test)
raw_repository_command_confirmation_is_exact_and_consumed :: proc(t: ^testing.T) {
	intent := raw_repository_command_test_intent()
	testing.expect(t, ksawery.raw_repository_command_intent_is_valid(intent))
	confirmation, prepared, failure :=
		ksawery.raw_repository_command_confirmation_prepare(intent, 19)
	testing.expect(t, prepared)
	testing.expect_value(t, failure.code, ksawery.Raw_Repository_Command_Failure_Code.None)

	stale := intent
	stale.repository_generation += 1
	confirmed: bool
	confirmed, failure = ksawery.raw_repository_command_confirmation_confirm(
		&confirmation,
		19,
		stale,
	)
	testing.expect(t, !confirmed)
	testing.expect_value(t, failure.code, ksawery.Raw_Repository_Command_Failure_Code.Confirmation_Mismatch)
	confirmed, failure = ksawery.raw_repository_command_confirmation_confirm(
		&confirmation,
		19,
		intent,
	)
	testing.expect(t, confirmed)
	testing.expect_value(t, failure.code, ksawery.Raw_Repository_Command_Failure_Code.None)
	request: ksawery.Raw_Repository_Command_Request
	requested: bool
	request, requested, failure = ksawery.raw_repository_command_request_prepare(
		23,
		intent,
		&confirmation,
	)
	testing.expect(t, requested)
	testing.expect(t, ksawery.raw_repository_command_request_is_valid(request))
	current, current_failure := ksawery.raw_repository_command_request_is_current(
		request,
		intent.repository,
		intent.repository_generation,
	)
	testing.expect(t, current)
	testing.expect_value(t, current_failure.code, ksawery.Raw_Repository_Command_Failure_Code.None)
	current, current_failure = ksawery.raw_repository_command_request_is_current(
		request,
		intent.repository,
		intent.repository_generation + 1,
	)
	testing.expect(t, !current)
	testing.expect_value(
		t, current_failure.code,
		ksawery.Raw_Repository_Command_Failure_Code.Stale_Repository,
	)
	_, requested, failure = ksawery.raw_repository_command_request_prepare(
		24,
		intent,
		&confirmation,
	)
	testing.expect(t, !requested)
	testing.expect_value(t, failure.code, ksawery.Raw_Repository_Command_Failure_Code.Confirmation_Consumed)

	ksawery.raw_repository_command_confirmation_close(&confirmation)
	ksawery.raw_repository_command_request_close(&request)
	testing.expect_value(t, confirmation, ksawery.Raw_Repository_Command_Confirmation{})
	testing.expect_value(t, request, ksawery.Raw_Repository_Command_Request{})
}

/* Verifies every started raw command requires one full compatible refresh. */
@(test)
raw_repository_command_refresh_is_complete_and_current :: proc(t: ^testing.T) {
	request := raw_repository_command_test_request(raw_repository_command_test_intent())
	evidence := ksawery.Raw_Repository_Command_Refresh_Evidence {
		repository = request.intent.repository,
		repository_generation = request.intent.repository_generation + 1,
		attempted = ksawery.RAW_REPOSITORY_COMMAND_REFRESH,
		completed = ksawery.RAW_REPOSITORY_COMMAND_REFRESH,
	}
	testing.expect(t, ksawery.raw_repository_command_refresh_evidence_is_valid(request, evidence))
	testing.expect(t, ksawery.raw_repository_command_refresh_is_complete(request, evidence))
	refresh_completed, applied, agreed, valid :=
		ksawery.raw_repository_command_verifier_apply(request, evidence)
	testing.expect(t, valid && refresh_completed && !applied && !agreed)

	evidence.completed = {.Status, .Process}
	testing.expect(t, ksawery.raw_repository_command_refresh_evidence_is_valid(request, evidence))
	testing.expect(t, !ksawery.raw_repository_command_refresh_is_complete(request, evidence))
	refresh_completed, applied, agreed, valid =
		ksawery.raw_repository_command_verifier_apply(request, evidence)
	testing.expect(t, valid && !refresh_completed && !applied && !agreed)
	evidence.attempted = {.Status, .Process}
	testing.expect(t, !ksawery.raw_repository_command_refresh_evidence_is_valid(request, evidence))
}

/* Verifies only refreshed typed evidence can upgrade a raw command outcome. */
@(test)
raw_repository_command_verifier_uses_refreshed_typed_truth :: proc(t: ^testing.T) {
	verifier := ksawery.Raw_Repository_Command_Verifier {
		kind = .Operation_State,
		observation = .Status,
		operation = .Normal,
	}
	request := raw_repository_command_test_request(raw_repository_command_test_intent(.Git, verifier))
	evidence := ksawery.Raw_Repository_Command_Refresh_Evidence {
		repository = request.intent.repository,
		repository_generation = request.intent.repository_generation + 1,
		attempted = ksawery.RAW_REPOSITORY_COMMAND_REFRESH,
		completed = ksawery.RAW_REPOSITORY_COMMAND_REFRESH,
		operation_checked = true,
		operation = .Normal,
	}
	refresh_completed, applied, agreed, valid :=
		ksawery.raw_repository_command_verifier_apply(request, evidence)
	testing.expect(t, valid && refresh_completed && applied && agreed)
	evidence.operation = .Merging
	refresh_completed, applied, agreed, valid =
		ksawery.raw_repository_command_verifier_apply(request, evidence)
	testing.expect(t, valid && refresh_completed && applied && !agreed)
	evidence.completed -= {.Status}
	refresh_completed, applied, agreed, valid =
		ksawery.raw_repository_command_verifier_apply(request, evidence)
	testing.expect(t, valid && !refresh_completed && !applied && !agreed)
}

/* Verifies public redaction and terminal outcome, Process, and cleanup contracts. */
@(test)
raw_repository_command_results_are_redacted_and_non_persistent :: proc(t: ^testing.T) {
	testing.expect(t, ksawery.raw_repository_command_public_content_is_valid(
		transmute([]u8)(string("command failed without private context")),
	))
	testing.expect(t, !ksawery.raw_repository_command_public_content_is_valid(
		transmute([]u8)(string("token=private")),
	))
	testing.expect(t, !ksawery.raw_repository_command_public_content_is_valid(
		transmute([]u8)(string("failure\x1b[31m")),
	))

	request := raw_repository_command_test_request(raw_repository_command_test_intent())
	result := raw_repository_command_test_result(request)
	failure := ksawery.raw_repository_command_result_validate(result, request)
	testing.expect_value(t, failure.code, ksawery.Raw_Repository_Command_Failure_Code.None)

	result.outcome = .Verified_Success
	result.verifier_applied = true
	result.verifier_agreed = true
	failure = ksawery.raw_repository_command_result_validate(result, request)
	testing.expect_value(t, failure.code, ksawery.Raw_Repository_Command_Failure_Code.Invalid_Result)

	verifier := ksawery.Raw_Repository_Command_Verifier {
		kind = .Observation_Available,
		observation = .Status,
	}
	request = raw_repository_command_test_request(raw_repository_command_test_intent(.Git, verifier))
	result = raw_repository_command_test_result(request)
	result.outcome = .Verified_Success
	result.verifier_applied = true
	result.verifier_agreed = true
	failure = ksawery.raw_repository_command_result_validate(result, request)
	testing.expect_value(t, failure.code, ksawery.Raw_Repository_Command_Failure_Code.None)

	result.process.association.authority.operation += 1
	failure = ksawery.raw_repository_command_result_validate(result, request)
	testing.expect_value(t, failure.code, ksawery.Raw_Repository_Command_Failure_Code.Stale_Process)
	result.process.association.authority.operation = request.operation
	result.cleanup.child_closed = false
	failure = ksawery.raw_repository_command_result_validate(result, request)
	testing.expect_value(t, failure.code, ksawery.Raw_Repository_Command_Failure_Code.Cleanup_Incomplete)
}
