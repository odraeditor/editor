// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery_extension_focused

import ksawery "../../src/ksawery"
import "core:testing"

/* Verifies typed plans admit only copied executable and argument shapes. */
@(test)
external_plans_are_typed_and_bounded :: proc(t: ^testing.T) {
	arguments: [2]ksawery.Extension_Operation_Argument
	plan := extension_operation_test_plan(&arguments)
	usage, failure := ksawery.extension_operation_plan_validate(plan)
	testing.expect_value(t, failure.code, ksawery.Extension_Operation_Failure_Code.None)
	testing.expect_value(t, usage.arguments, u32(2))
	testing.expect(t, usage.argument_bytes > 0)
	testing.expect(t, usage.copy_bytes <= ksawery.DEFAULT_EXTENSION_OPERATION_COPY_BYTES)
	testing.expect(t, ksawery.extension_operation_process_limits_are_valid(plan.process_limits))
	testing.expect(t, ksawery.extension_operation_declaration_limits_are_valid(
		ksawery.DEFAULT_EXTENSION_OPERATION_DECLARATION_LIMITS,
	))

	absolute: ksawery.Extension_Operation_Executable
	assigned := ksawery.extension_operation_executable_assign_absolute(
		&absolute, "configured.review-tool", "/opt/odra-tools/review-tool",
	)
	testing.expect(t, assigned)
	if assigned {
		plan.executable = absolute
		_, failure = ksawery.extension_operation_plan_validate(plan)
		testing.expect_value(t, failure.code, ksawery.Extension_Operation_Failure_Code.None)
	}
	testing.expect(t, !ksawery.extension_operation_executable_assign_absolute(
		&absolute, "configured.shell", "sh -c review",
	))
}

/* Verifies refresh, verifier, environment, and process policy fail closed. */
@(test)
external_plans_reject_invalid_policy :: proc(t: ^testing.T) {
	arguments: [2]ksawery.Extension_Operation_Argument
	plan := extension_operation_test_plan(&arguments)
	plan.refresh = {}
	_, failure := ksawery.extension_operation_plan_validate(plan)
	testing.expect_value(t, failure.code, ksawery.Extension_Operation_Failure_Code.Invalid_Refresh)

	plan = extension_operation_test_plan(&arguments)
	plan.verifier.observation = .History
	_, failure = ksawery.extension_operation_plan_validate(plan)
	testing.expect_value(t, failure.code, ksawery.Extension_Operation_Failure_Code.Invalid_Verifier)

	plan = extension_operation_test_plan(&arguments)
	plan.environment = .Invalid
	_, failure = ksawery.extension_operation_plan_validate(plan)
	testing.expect_value(t, failure.code, ksawery.Extension_Operation_Failure_Code.Invalid_Environment)

	plan = extension_operation_test_plan(&arguments)
	plan.process_limits.deadline_nanoseconds =
		ksawery.MAX_EXTENSION_OPERATION_DEADLINE_NS + 1
	_, failure = ksawery.extension_operation_plan_validate(plan)
	testing.expect_value(t, failure.code, ksawery.Extension_Operation_Failure_Code.Invalid_Process_Limits)
}

/* Verifies declaration ceilings reject excess arguments and copied bytes. */
@(test)
external_plan_limits_are_enforced :: proc(t: ^testing.T) {
	arguments: [2]ksawery.Extension_Operation_Argument
	plan := extension_operation_test_plan(&arguments)
	limits := ksawery.DEFAULT_EXTENSION_OPERATION_DECLARATION_LIMITS
	limits.arguments = 1
	_, failure := ksawery.extension_operation_plan_validate(plan, limits)
	testing.expect_value(t, failure.code, ksawery.Extension_Operation_Failure_Code.Argument_Limit)
	limits = ksawery.DEFAULT_EXTENSION_OPERATION_DECLARATION_LIMITS
	limits.argument_bytes = 8
	_, failure = ksawery.extension_operation_plan_validate(plan, limits)
	testing.expect_value(t, failure.code, ksawery.Extension_Operation_Failure_Code.Argument_Bytes_Limit)
}

/* Verifies zero exit becomes success only with refreshed typed proof. */
@(test)
external_results_require_typed_verification :: proc(t: ^testing.T) {
	arguments: [2]ksawery.Extension_Operation_Argument
	plan := extension_operation_test_plan(&arguments)
	result := extension_operation_test_result(plan, .Verified_Success)
	usage, failure := ksawery.extension_operation_result_validate(result, result.request, plan)
	testing.expect_value(t, failure.code, ksawery.Extension_Operation_Failure_Code.None)
	testing.expect_value(t, usage.output_bytes, result.output_bytes)

	plan.verifier = {}
	_, failure = ksawery.extension_operation_plan_validate(plan)
	testing.expect_value(t, failure.code, ksawery.Extension_Operation_Failure_Code.None)
	_, failure = ksawery.extension_operation_result_validate(result, result.request, plan)
	testing.expect_value(t, failure.code, ksawery.Extension_Operation_Failure_Code.Invalid_Result)
	result.outcome = .Indeterminate
	result.effect_possible = true
	result.verifier_applied = false
	result.verifier_agreed = false
	_, failure = ksawery.extension_operation_result_validate(result, result.request, plan)
	testing.expect_value(t, failure.code, ksawery.Extension_Operation_Failure_Code.None)
}

/* Verifies cancellation, truncation, and stale results retain exact evidence. */
@(test)
external_results_preserve_failure_evidence :: proc(t: ^testing.T) {
	arguments: [2]ksawery.Extension_Operation_Argument
	plan := extension_operation_test_plan(&arguments)
	result := extension_operation_test_result(plan, .Cancelled_Before_Effect)
	result.exit_code_present = false
	result.refresh_completed = false
	result.verifier_applied = false
	result.verifier_agreed = false
	_, failure := ksawery.extension_operation_result_validate(result, result.request, plan)
	testing.expect_value(t, failure.code, ksawery.Extension_Operation_Failure_Code.None)

	result.contributor.generation += 1
	_, failure = ksawery.extension_operation_result_validate(result, result.request, plan)
	testing.expect_value(t, failure.code, ksawery.Extension_Operation_Failure_Code.Stale_Contributor)
	result.contributor = plan.contributor
	result.plan_generation += 1
	_, failure = ksawery.extension_operation_result_validate(result, result.request, plan)
	testing.expect_value(t, failure.code, ksawery.Extension_Operation_Failure_Code.Stale_Plan)
	result.plan_generation = plan.generation
	result.output_truncated = true
	_, failure = ksawery.extension_operation_result_validate(result, result.request, plan)
	testing.expect_value(t, failure.code, ksawery.Extension_Operation_Failure_Code.Invalid_Result)
	result.output_bytes = plan.process_limits.output_bytes
	_, failure = ksawery.extension_operation_result_validate(result, result.request, plan)
	testing.expect_value(t, failure.code, ksawery.Extension_Operation_Failure_Code.None)
	plan.diagnostic_policy = .Suppressed
	_, failure = ksawery.extension_operation_result_validate(result, result.request, plan)
	testing.expect_value(t, failure.code, ksawery.Extension_Operation_Failure_Code.Invalid_Result)
}

extension_operation_test_plan :: proc(
	arguments: ^[2]ksawery.Extension_Operation_Argument,
) -> ksawery.Extension_Operation_Plan {
	assert(ksawery.extension_operation_argument_assign(&arguments[0], "status"))
	assert(ksawery.extension_operation_argument_assign(&arguments[1], "--porcelain=v2"))
	identity: ksawery.Extension_Identity
	purpose: ksawery.Extension_Label
	assert(ksawery.extension_identity_assign(&identity, "operation.review-status"))
	assert(ksawery.extension_label_assign(&purpose, "Review repository status"))
	executable: ksawery.Extension_Operation_Executable
	assert(ksawery.extension_operation_executable_assign_git(&executable))
	return {
		contributor = {contributor = 1, generation = 5},
		contribution = 7,
		plan = 11,
		generation = 13,
		identity = identity,
		purpose = purpose,
		executable = executable,
		arguments = arguments^[:],
		effect = .Repository_Mutating,
		refresh = {.Status, .Refs},
		verifier = {kind = .Observation_Available, observation = .Refs},
		environment = .Core_Repository,
		diagnostic_policy = .Bounded_Public,
		process_limits = ksawery.DEFAULT_EXTENSION_OPERATION_PROCESS_LIMITS,
	}
}

extension_operation_test_result :: proc(
	plan: ksawery.Extension_Operation_Plan,
	outcome: ksawery.Repository_Process_Outcome,
) -> ksawery.Extension_Operation_Result {
	return {
		request = 17,
		contributor = plan.contributor,
		plan = plan.plan,
		plan_generation = plan.generation,
		outcome = outcome,
		exit_code_present = true,
		exit_code = 0,
		refresh_completed = true,
		verifier_applied = true,
		verifier_agreed = true,
		output_bytes = 1 * ksawery.KIBIBYTE,
		diagnostic_bytes = 128,
	}
}
