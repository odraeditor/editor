// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_computation

import "core:testing"

@(private)
execution_test_configuration :: proc(
	configuration: ^Configuration,
	runtime_required: bool,
	class := Availability_Class.Factory_Adapter,
	interactive := Authority_Decision.Confirm,
	batch := Authority_Decision.Deny,
) -> bool {
	initialized, _ := computation_configuration_init(configuration, 1, 1, 1)
	if !initialized do return false
	adapters := [1]Adapter_Candidate{{
		identity = "racket",
		language = "racket",
		version = "factory-test-1",
		class = class,
		in_process = !runtime_required,
		runtime_required = runtime_required,
		limits = DEFAULT_LIMITS,
	}}
	policies := [1]Policy_Candidate{{
		identity = "racket-project",
		adapter = "racket",
		language = "racket",
		origin = .Project,
		interactive = interactive,
		batch = batch,
		effects = {.Read_Resource, .Child_Process},
	}}
	_, published, _ := computation_configuration_publish(configuration, {
		generation = 23,
		adapter_generation = 29,
		policy_generation = 31,
		adapters = adapters[:],
		policies = policies[:],
	})
	if !published do computation_configuration_close(configuration)
	return published
}

/* Verifies all header scopes resolve by fixed precedence with copied inspection. */
@(test)
execution_arguments_resolve_exact_precedence :: proc(t: ^testing.T) {
	candidates := []Argument_Candidate {
		{key = "session", value = "exact", source = .Invocation, known = true},
		{key = "var", value = "project=2", source = .Project_Language, additive = true, known = true},
		{key = "session", value = "none", source = .Factory_General, known = true},
		{key = "var", value = "factory=1", source = .Factory_Language, additive = true, known = true},
		{key = "provider-option", value = "opaque", source = .Block},
	}
	arguments: [5]Effective_Argument
	trace: [5]Argument_Trace
	environment, ok, failure := resolve_effective_environment(23, candidates, arguments[:], trace[:])
	testing.expectf(t, ok, "argument resolution failed with %v", failure.code)
	testing.expect_value(t, environment.argument_count, u16(3))
	testing.expect_value(t, environment.shadowed_count, u16(1))
	testing.expect_value(t, environment.unknown_count, u16(1))
	for &argument in arguments[:environment.argument_count] {
		key := argument_key_text(&argument.key)
		if key == "session" do testing.expect_value(t, argument_value_text(&argument.value), "exact")
		if key == "var" do testing.expect_value(t, argument_value_text(&argument.value), "factory=1\nproject=2")
		if key == "provider-option" do testing.expect_value(t, argument_value_text(&argument.value), "opaque")
	}
}

/* Verifies exact language selection, unavailable runtimes, and configured replacement. */
@(test)
execution_adapter_selection_is_exact :: proc(t: ^testing.T) {
	configuration: Configuration
	testing.expect(t, execution_test_configuration(&configuration, true))
	defer computation_configuration_close(&configuration)
	selection, selected, failure := select_execution_adapter(&configuration, "racket", "racket", 29, false)
	testing.expect(t, !selected)
	testing.expect_value(t, selection.state, Adapter_Selection_State.Unavailable)
	testing.expect_value(t, failure.code, Failure_Code.Unavailable)
	selection, selected, _ = select_execution_adapter(&configuration, "racket", "racket", 29, true)
	testing.expect(t, selected)
	testing.expect_value(t, selection.state, Adapter_Selection_State.Selected)
	_, selected, failure = select_execution_adapter(&configuration, "emacs-lisp", "", 29, true)
	testing.expect(t, !selected)
	testing.expect_value(t, failure.code, Failure_Code.Unavailable)
	_, selected, failure = select_execution_adapter(&configuration, "racket", "replacement", 29, true)
	testing.expect(t, !selected)
	testing.expect_value(t, failure.code, Failure_Code.Conflict)
	_, selected, failure = select_execution_adapter(&configuration, "racket", "racket", 28, true)
	testing.expect(t, !selected)
	testing.expect_value(t, failure.code, Failure_Code.Stale)
}

/* Verifies the deterministic factory test adapter requires no external runtime. */
@(test)
execution_factory_test_adapter_is_in_process :: proc(t: ^testing.T) {
	configuration: Configuration
	initialized, _ := computation_configuration_init(&configuration, 1, 1, 1)
	testing.expect(t, initialized)
	if !initialized do return
	defer computation_configuration_close(&configuration)
	adapters := [1]Adapter_Candidate{{
		identity = "jan-test",
		language = "jan-test",
		version = "1",
		class = .Factory_Adapter,
		in_process = true,
		limits = DEFAULT_LIMITS,
	}}
	policies := [1]Policy_Candidate{{
		identity = "jan-test-project",
		adapter = "jan-test",
		language = "jan-test",
		origin = .Project,
		interactive = .Allow,
		batch = .Allow,
	}}
	_, published, _ := computation_configuration_publish(&configuration, {
		generation = 23,
		adapter_generation = 29,
		policy_generation = 31,
		adapters = adapters[:],
		policies = policies[:],
	})
	testing.expect(t, published)
	selection, selected, _ := select_execution_adapter(&configuration, "jan-test", "jan-test", 29, false)
	testing.expect(t, selected)
	testing.expect(t, selection.in_process && !selection.runtime_required)
}

/* Verifies deterministic serialization and explicit conversion rejection. */
@(test)
execution_variables_serialize_without_shell_interpretation :: proc(t: ^testing.T) {
	variables := []Variable_Candidate {
		{name = "count", kind = .Scalar, value = "3"},
		{name = "table", kind = .Table, value = "a\tb\n1\t2", rows = 2, columns = 2},
		{name = "literal", kind = .Scalar, value = "$(never-executed)"},
	}
	output: [1_024]u8
	descriptor, text, serialized, failure := serialize_execution_variables(variables, output[:])
	testing.expectf(t, serialized, "serialization failed with %v", failure.code)
	testing.expect_value(t, descriptor.variable_count, u16(3))
	testing.expect(t, descriptor.byte_count > 0 && descriptor.content_hash != 0)
	testing.expect(t, len(text) > len("$(never-executed)"))
	duplicate := []Variable_Candidate{variables[0], variables[0]}
	_, _, serialized, failure = serialize_execution_variables(duplicate, output[:])
	testing.expect(t, !serialized)
	testing.expect_value(t, failure.code, Failure_Code.Conflict)
	tiny: [8]u8
	_, _, serialized, failure = serialize_execution_variables(variables, tiny[:])
	testing.expect(t, !serialized)
	testing.expect_value(t, failure.code, Failure_Code.Limited)
}

/* Verifies implicit triggers deny and one-shot confirmation remains exact. */
@(test)
execution_authority_is_deny_first :: proc(t: ^testing.T) {
	configuration: Configuration
	testing.expect(t, execution_test_configuration(&configuration, false))
	defer computation_configuration_close(&configuration)
	request := Authority_Request {
		operation_id = 41,
		language = "racket",
		adapter_identity = "racket",
		adapter_generation = 29,
		policy_generation = 31,
		origin = .Project,
		invocation = .Interactive,
		effects = {.Read_Resource},
		trusted = true,
		trigger = .Open,
	}
	result, resolved, _ := resolve_execution_authority(&configuration, request)
	testing.expect(t, resolved)
	testing.expect_value(t, result.decision, Authority_Decision.Deny)
	request.trigger = .Command
	result, resolved, _ = resolve_execution_authority(&configuration, request)
	testing.expect(t, resolved)
	testing.expect_value(t, result.decision, Authority_Decision.Confirm)
	confirmation := Confirmation_Record {
		operation_id = request.operation_id,
		adapter_generation = request.adapter_generation,
		policy_generation = request.policy_generation,
		effects = request.effects,
	}
	confirmed, consumed := consume_execution_confirmation(&confirmation, request, result)
	testing.expect(t, consumed)
	testing.expect_value(t, confirmed.decision, Authority_Decision.Allow)
	_, consumed = consume_execution_confirmation(&confirmation, request, result)
	testing.expect(t, !consumed)
	request.invocation = .Batch
	request.trigger = .Explicit_Batch
	result, _, _ = resolve_execution_authority(&configuration, request)
	testing.expect_value(t, result.decision, Authority_Decision.Deny)
}

/* Verifies process requests, cancellation, timeout, quarantine, and cleanup. */
@(test)
execution_process_lifecycle_is_contained :: proc(t: ^testing.T) {
	configuration: Configuration
	testing.expect(t, execution_test_configuration(&configuration, true, .Configured_Provider, .Allow, .Allow))
	defer computation_configuration_close(&configuration)
	selection, selected, _ := select_execution_adapter(&configuration, "racket", "racket", 29, true)
	testing.expect(t, selected)
	authority_request := Authority_Request {
		operation_id = 51,
		language = "racket",
		adapter_identity = "racket",
		adapter_generation = 29,
		policy_generation = 31,
		origin = .Project,
		invocation = .Interactive,
		effects = {.Read_Resource, .Child_Process},
		trusted = true,
		trigger = .Command,
	}
	authority, _, _ := resolve_execution_authority(&configuration, authority_request)
	testing.expect_value(t, authority.decision, Authority_Decision.Allow)
	arguments := []Argument_Candidate{{key = "results", value = "value", source = .Block, known = true}}
	effective: [1]Effective_Argument
	trace: [1]Argument_Trace
	environment, environment_ok, _ := resolve_effective_environment(23, arguments, effective[:], trace[:])
	testing.expect(t, environment_ok)
	variables := []Variable_Candidate{{name = "input", kind = .Scalar, value = "1"}}
	input_bytes: [128]u8
	input, _, input_ok, _ := serialize_execution_variables(variables, input_bytes[:])
	testing.expect(t, input_ok)
	scope := computation_test_scope()
	request, prepared, failure := prepare_process_request(
		51,
		scope,
		selection,
		authority,
		7,
		input,
		environment,
		1_000,
		100,
	)
	testing.expectf(t, prepared, "process request failed with %v", failure.code)
	testing.expect_value(t, request.working_resource, u64(7))
	record := Process_Record {
		operation_id = 51,
		adapter_generation = 29,
		policy_generation = 31,
		state = .Prepared,
		deadline_ns = 1_000,
	}
	record, prepared, _ = process_record_transition(record, .Start, 10)
	testing.expect(t, prepared)
	record, prepared, _ = process_record_transition(record, .Started, 20, 99)
	testing.expect(t, prepared)
	record, prepared, _ = process_record_transition(record, .Timeout, 1_000)
	testing.expect(t, prepared)
	testing.expect_value(t, record.state, Execution_Process_State.Timed_Out)
	health, quarantined := adapter_health_update({}, 51, 29, .Timeout)
	testing.expect(t, quarantined && health.quarantined)
	record, prepared, _ = process_record_transition(record, .Quarantine, 1_001)
	testing.expect(t, prepared)
	record, prepared, _ = process_record_transition(record, .Reconcile, 1_002)
	testing.expect(t, prepared)
	record, prepared, _ = process_record_transition(record, .Cleanup_Confirmed, 1_003)
	testing.expect(t, prepared && record.cleanup_confirmed)
	health, quarantined = adapter_health_update(health, 51, 29, .Reconcile)
	testing.expect(t, quarantined && !health.quarantined)
}

/* Verifies adapter diagnostics remain typed, copied, and source-bound. */
@(test)
execution_diagnostics_are_normalized :: proc(t: ^testing.T) {
	scope := computation_test_scope()
	candidate := Adapter_Diagnostic_Candidate {
		kind = .Evaluation,
		message = "division by zero",
		range = {scope = scope.analysis, start = 8, end = 24},
		has_range = true,
	}
	record, normalized := normalize_adapter_diagnostic(candidate, scope)
	testing.expect(t, normalized)
	testing.expect_value(t, record.kind, Diagnostic_Kind.Evaluation)
	message := string(record.message[:record.length])
	testing.expect_value(t, message, "division by zero")
	candidate.range.scope.source_revision += 1
	_, normalized = normalize_adapter_diagnostic(candidate, scope)
	testing.expect(t, !normalized)
}
