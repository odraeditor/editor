// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_computation

import "../language"
import "core:fmt"
import "core:unicode/utf8"

/* MAX_EXECUTION_ARGUMENTS bounds one effective header environment. */
MAX_EXECUTION_ARGUMENTS :: u16(512)
/* MAX_ARGUMENT_KEY_BYTES bounds one header-argument identity. */
MAX_ARGUMENT_KEY_BYTES :: 96
/* MAX_ARGUMENT_VALUE_BYTES bounds one copied header-argument value. */
MAX_ARGUMENT_VALUE_BYTES :: 4 * 1_024
/* MAX_VARIABLES bounds one serialized execution input. */
MAX_VARIABLES :: u16(512)
/* MAX_VARIABLE_NAME_BYTES bounds one variable identity. */
MAX_VARIABLE_NAME_BYTES :: 96
/* MAX_DIAGNOSTIC_BYTES bounds one normalized adapter diagnostic. */
MAX_DIAGNOSTIC_BYTES :: 4 * 1_024

/* Argument_Source encodes exact low-to-high header-argument precedence. */
Argument_Source :: enum u8 {
	Invalid,
	Factory_General,
	Factory_Language,
	User_General,
	User_Language,
	Workspace_General,
	Workspace_Language,
	Project_General,
	Project_Language,
	Document_General,
	Document_Language,
	Inherited_General,
	Inherited_Language,
	Affiliated,
	Block,
	Call,
	Invocation,
}

/* Argument_Key is one copied bounded header identity. */
Argument_Key :: struct {
	bytes:  [MAX_ARGUMENT_KEY_BYTES]u8,
	length: u8,
}

/* Argument_Value is one copied bounded header value. */
Argument_Value :: struct {
	bytes:  [MAX_ARGUMENT_VALUE_BYTES]u8,
	length: u16,
}

/* Argument_Candidate is one borrowed header contribution before precedence resolution. */
Argument_Candidate :: struct {
	key:      string,
	value:    string,
	source:   Argument_Source,
	order:    u16,
	additive: bool,
	known:    bool,
}

/* Argument_Trace is one copied inspectable selected or shadowed contribution. */
Argument_Trace :: struct {
	key:         Argument_Key,
	value:       Argument_Value,
	source:      Argument_Source,
	order:       u16,
	additive:    bool,
	known:       bool,
	contributes: bool,
}

/* Effective_Argument is one copied final scalar or composed header value. */
Effective_Argument :: struct {
	key:               Argument_Key,
	value:             Argument_Value,
	source:            Argument_Source,
	contributor_count: u16,
	shadowed_count:    u16,
	additive:          bool,
	known:             bool,
}

/* Effective_Environment reports one complete inspectable header resolution. */
Effective_Environment :: struct {
	configuration_generation: Configuration_Generation,
	argument_count:           u16,
	contribution_count:       u16,
	shadowed_count:           u16,
	unknown_count:            u16,
	complete:                 bool,
}

/* Adapter_Selection_State identifies one exact adapter selection outcome. */
Adapter_Selection_State :: enum u8 {
	Invalid,
	Selected,
	Unavailable,
	Stale,
	Conflict,
}

/* Adapter_Selection is one copied exact-language provider choice. */
Adapter_Selection :: struct {
	state:              Adapter_Selection_State,
	identity:           Argument_Key,
	language:           Argument_Key,
	version:            Argument_Value,
	class:              Availability_Class,
	adapter_generation: Adapter_Generation,
	limits:             Limits,
	in_process:         bool,
	runtime_required:   bool,
}

/* Variable_Value_Kind identifies one explicit adapter input conversion. */
Variable_Value_Kind :: enum u8 {
	Invalid,
	Scalar,
	List,
	Table,
	Source,
	Result,
	Property,
	Resource,
}

/* Variable_Candidate is one borrowed explicit execution input. */
Variable_Candidate :: struct {
	name:   string,
	kind:   Variable_Value_Kind,
	value:  string,
	rows:   u32,
	columns: u32,
}

/* Serialized_Input describes one bounded deterministic adapter input. */
Serialized_Input :: struct {
	variable_count: u16,
	byte_count:     u64,
	content_hash:   u64,
	complete:       bool,
}

/* Trigger_Reason identifies explicit and non-executing editor events. */
Trigger_Reason :: enum u8 {
	Invalid,
	Open,
	Reopen,
	Parse,
	Highlight,
	Fold,
	Completion,
	Navigation,
	Search,
	Lint,
	Agenda,
	Preview,
	Save,
	Follow_Link,
	Restore_Session,
	Command,
	Explicit_Export,
	Explicit_Batch,
}

/* Authority_Request binds policy resolution to one exact operation and adapter. */
Authority_Request :: struct {
	operation_id:      Operation_ID,
	language:          string,
	adapter_identity:  string,
	adapter_generation: Adapter_Generation,
	policy_generation: Policy_Generation,
	origin:            Source_Origin,
	invocation:        Invocation_Context,
	effects:           Effects,
	trusted:           bool,
	trigger:           Trigger_Reason,
}

/* Authority_Result reports one deny-first policy decision without consuming confirmation. */
Authority_Result :: struct {
	operation_id:       Operation_ID,
	decision:           Authority_Decision,
	policy_generation:  Policy_Generation,
	matched_rules:      u16,
	denied_rules:       u16,
	confirmation_rules: u16,
	explicit_trigger:   bool,
}

/* Confirmation_Record is one exact one-shot interactive confirmation. */
Confirmation_Record :: struct {
	operation_id:      Operation_ID,
	adapter_generation: Adapter_Generation,
	policy_generation: Policy_Generation,
	effects:           Effects,
	consumed:          bool,
}

/* Execution_Process_State identifies one checked adapter process lifecycle. */
Execution_Process_State :: enum u8 {
	Invalid,
	Prepared,
	Starting,
	Running,
	Cancelling,
	Completed,
	Failed,
	Timed_Out,
	Quarantined,
	Cleaning,
	Closed,
}

/* Execution_Process_Event identifies one process-owner observation. */
Execution_Process_Event :: enum u8 {
	Invalid,
	Start,
	Started,
	Complete,
	Fail,
	Cancel,
	Timeout,
	Begin_Cleanup,
	Cleanup_Confirmed,
	Quarantine,
	Reconcile,
}

/* Process_Request is one checked effect request for an existing process owner. */
Process_Request :: struct {
	operation_id:       Operation_ID,
	scope:              Scope,
	adapter:            Adapter_Selection,
	authority:          Authority_Result,
	working_resource:   u64,
	input:              Serialized_Input,
	environment:        Effective_Environment,
	limits:             Limits,
	deadline_ns:        i64,
	cancellation_grace_ns: i64,
}

/* Process_Record tracks one child lifecycle without owning operating-system handles. */
Process_Record :: struct {
	operation_id:       Operation_ID,
	adapter_generation: Adapter_Generation,
	policy_generation:  Policy_Generation,
	process_identity:   u64,
	state:              Execution_Process_State,
	started_ns:         i64,
	deadline_ns:        i64,
	output_bytes:       u64,
	cleanup_confirmed:  bool,
}

/* Adapter_Health records exact-generation quarantine and reconciliation. */
Adapter_Health :: struct {
	adapter_generation: Adapter_Generation,
	quarantined:        bool,
	failure:            Failure_Code,
	operation_id:       Operation_ID,
}

/* Diagnostic_Kind identifies one normalized execution failure family. */
Diagnostic_Kind :: enum u8 {
	Invalid,
	Parse,
	Reference,
	Conversion,
	Authorization,
	Adapter,
	Process,
	Evaluation,
	Result_Decoding,
	Stale_Publication,
	Resource,
}

/* Adapter_Diagnostic_Candidate is one borrowed provider diagnostic. */
Adapter_Diagnostic_Candidate :: struct {
	kind:     Diagnostic_Kind,
	message:  string,
	range:    language.Jan_Source_Range,
	has_range: bool,
}

/* Diagnostic_Record is one copied bounded normalized diagnostic. */
Diagnostic_Record :: struct {
	kind:      Diagnostic_Kind,
	message:   [MAX_DIAGNOSTIC_BYTES]u8,
	length:    u16,
	range:     language.Jan_Source_Range,
	has_range: bool,
}

/* argument_key_text borrows one copied header-argument identity. */
argument_key_text :: proc(value: ^Argument_Key) -> string {
	if value == nil || value.length == 0 || int(value.length) > len(value.bytes) do return ""
	return string(value.bytes[:value.length])
}

/* argument_value_text borrows one copied header-argument value. */
argument_value_text :: proc(value: ^Argument_Value) -> string {
	if value == nil || int(value.length) > len(value.bytes) do return ""
	return string(value.bytes[:value.length])
}

/* resolve_effective_environment applies exact header precedence and copies inspection data. */
resolve_effective_environment :: proc(
	generation: Configuration_Generation,
	candidates: []Argument_Candidate,
	arguments: []Effective_Argument,
	trace: []Argument_Trace,
) -> (Effective_Environment, bool, Failure) {
	if generation == Configuration_Generation(0) || len(candidates) > int(MAX_EXECUTION_ARGUMENTS) ||
	   len(arguments) < len(candidates) || len(trace) < len(candidates) {
		return {}, false, execution_failure(.Invalid_Request, .Limit)
	}
	for candidate, index in candidates {
		key, key_ok := argument_key_copy(candidate.key)
		value, value_ok := argument_value_copy(candidate.value)
		if !key_ok || !value_ok || candidate.source == .Invalid {
			return {}, false, execution_failure(.Malformed, .Policy)
		}
		trace[index] = {key = key, value = value, source = candidate.source, order = candidate.order, additive = candidate.additive, known = candidate.known}
	}
	for index in 1 ..< len(candidates) {
		cursor := index
		for cursor > 0 && argument_trace_after(trace[cursor - 1], trace[cursor]) {
			trace[cursor - 1], trace[cursor] = trace[cursor], trace[cursor - 1]
			cursor -= 1
		}
	}
	argument_count, shadowed_count, unknown_count := 0, 0, 0
	for contribution, trace_index in trace[:len(candidates)] {
		argument_index := -1
		for argument, index in arguments[:argument_count] do if argument_key_equal(argument.key, contribution.key) {
			argument_index = index
			break
		}
		if argument_index < 0 {
			arguments[argument_count] = {
				key = contribution.key,
				value = contribution.value,
				source = contribution.source,
				contributor_count = 1,
				additive = contribution.additive,
				known = contribution.known,
			}
			if !contribution.known do unknown_count += 1
			trace[trace_index].contributes = true
			argument_count += 1
			continue
		}
		argument := &arguments[argument_index]
		if argument.additive != contribution.additive {
			return {}, false, execution_failure(.Conflict, .Policy)
		}
		if argument.known != contribution.known {
			return {}, false, execution_failure(.Conflict, .Policy)
		}
		if contribution.additive {
			if !argument_value_append(&argument.value, contribution.value) {
				return {}, false, execution_failure(.Limited, .Limit)
			}
			argument.contributor_count += 1
			argument.source = contribution.source
			trace[trace_index].contributes = true
		} else {
			for prior_index in 0 ..< trace_index do if trace[prior_index].contributes &&
			   argument_key_equal(trace[prior_index].key, contribution.key) {
				trace[prior_index].contributes = false
				break
			}
			argument.value = contribution.value
			argument.source = contribution.source
			argument.shadowed_count += 1
			shadowed_count += 1
			trace[trace_index].contributes = true
		}
	}
	return {
		configuration_generation = generation,
		argument_count = u16(argument_count),
		contribution_count = u16(len(candidates)),
		shadowed_count = u16(shadowed_count),
		unknown_count = u16(unknown_count),
		complete = true,
	}, true, {}
}

/* select_execution_adapter chooses the sole exact-language adapter in one confirmed generation. */
select_execution_adapter :: proc(
	configuration: ^Configuration,
	language_name: string,
	requested_identity: string,
	expected_generation: Adapter_Generation,
	runtime_available: bool,
) -> (Adapter_Selection, bool, Failure) {
	descriptor, inspected := computation_configuration_inspect(configuration)
	if !inspected || len(language_name) == 0 do return {}, false, execution_failure(.Invalid_Request, .Adapter)
	if descriptor.adapter_generation != expected_generation {
		return {state = .Stale, adapter_generation = descriptor.adapter_generation}, false, execution_failure(.Stale, .Adapter)
	}
	for index in 0 ..< int(descriptor.adapter_count) {
		adapter, ok := computation_configuration_adapter(configuration, index)
		if !ok || adapter.language != language_name do continue
		if len(requested_identity) > 0 && adapter.identity != requested_identity {
			return {state = .Conflict, adapter_generation = descriptor.adapter_generation}, false, execution_failure(.Conflict, .Adapter)
		}
		identity, identity_ok := argument_key_copy(adapter.identity)
		language_value, language_ok := argument_key_copy(adapter.language)
		version, version_ok := argument_value_copy(adapter.version)
		if !identity_ok || !language_ok || !version_ok do return {}, false, execution_failure(.Malformed, .Adapter)
		selection := Adapter_Selection {
			state = .Selected,
			identity = identity,
			language = language_value,
			version = version,
			class = adapter.class,
			adapter_generation = descriptor.adapter_generation,
			limits = adapter.limits,
			in_process = adapter.in_process,
			runtime_required = adapter.runtime_required,
		}
		if adapter.runtime_required && !runtime_available {
			selection.state = .Unavailable
			return selection, false, execution_failure(.Unavailable, .Adapter)
		}
		return selection, true, {}
	}
	return {state = .Unavailable, adapter_generation = descriptor.adapter_generation}, false, execution_failure(.Unavailable, .Adapter)
}

/* serialize_execution_variables produces deterministic copied adapter input without shell interpretation. */
serialize_execution_variables :: proc(
	variables: []Variable_Candidate,
	output: []u8,
) -> (Serialized_Input, string, bool, Failure) {
	if len(variables) > int(MAX_VARIABLES) || len(output) == 0 {
		return {}, "", false, execution_failure(.Limited, .Limit)
	}
	cursor := 0
	hash := u64(14_695_981_039_346_656_037)
	for variable, index in variables {
		if len(variable.name) == 0 || len(variable.name) > MAX_VARIABLE_NAME_BYTES ||
		   !utf8.valid_string(variable.name) || variable.kind == .Invalid ||
		   len(variable.value) > MAX_ARGUMENT_VALUE_BYTES || !utf8.valid_string(variable.value) {
			return {}, "", false, execution_failure(.Conversion, .Result)
		}
		for prior in variables[:index] do if prior.name == variable.name {
			return {}, "", false, execution_failure(.Conflict, .Result)
		}
		line := fmt.bprintf(output[cursor:], "%s:%d:%d:%d:%s\n", variable.name, variable.kind, variable.rows, variable.columns, variable.value)
		if len(line) == 0 || cursor + len(line) >= len(output) {
			return {}, "", false, execution_failure(.Limited, .Limit)
		}
		for value in line {
			hash = (hash ~ u64(value)) * 1_099_511_628_211
		}
		cursor += len(line)
	}
	return {variable_count = u16(len(variables)), byte_count = u64(cursor), content_hash = hash, complete = true},
	       string(output[:cursor]), true, {}
}

/* execution_trigger_is_explicit rejects every implicit editor event. */
execution_trigger_is_explicit :: proc(reason: Trigger_Reason) -> bool {
	return reason == .Command || reason == .Explicit_Export || reason == .Explicit_Batch
}

/* resolve_execution_authority applies deny-first policy to one exact request. */
resolve_execution_authority :: proc(
	configuration: ^Configuration,
	request: Authority_Request,
) -> (Authority_Result, bool, Failure) {
	descriptor, inspected := computation_configuration_inspect(configuration)
	result := Authority_Result {
		operation_id = request.operation_id,
		decision = .Deny,
		policy_generation = descriptor.policy_generation,
		explicit_trigger = execution_trigger_is_explicit(request.trigger),
	}
	if !inspected || request.operation_id == Operation_ID(0) || len(request.language) == 0 ||
	   len(request.adapter_identity) == 0 || request.origin == .Invalid || request.invocation == .Invalid ||
	   request.adapter_generation != descriptor.adapter_generation ||
	   request.policy_generation != descriptor.policy_generation {
		return result, false, execution_failure(.Stale, .Authority)
	}
	if !result.explicit_trigger do return result, true, {}
	allow_count := u16(0)
	for index in 0 ..< int(descriptor.policy_count) {
		policy, ok := computation_configuration_policy(configuration, index)
		if !ok || policy.language != request.language ||
		   (len(policy.adapter) > 0 && policy.adapter != request.adapter_identity) ||
		   policy.origin != request.origin ||
		   !effects_contain(policy.effects, request.effects) {
			continue
		}
		result.matched_rules += 1
		decision := policy.interactive
		if request.invocation == .Batch || request.invocation == .Export do decision = policy.batch
		switch decision {
		case .Deny:
			result.denied_rules += 1
		case .Confirm:
			result.confirmation_rules += 1
		case .Allow:
			allow_count += 1
		case .Invalid:
		}
	}
	if result.denied_rules > 0 || result.matched_rules == 0 {
		result.decision = .Deny
	} else if result.confirmation_rules > 0 {
		result.decision = .Confirm if request.invocation == .Interactive && request.trusted else .Deny
	} else if allow_count == result.matched_rules {
		result.decision = .Allow
	}
	return result, true, {}
}

/* consume_execution_confirmation admits one exact pending interactive decision once. */
consume_execution_confirmation :: proc(
	confirmation: ^Confirmation_Record,
	request: Authority_Request,
	result: Authority_Result,
) -> (Authority_Result, bool) {
	if confirmation == nil || confirmation.consumed || result.decision != .Confirm ||
	   request.invocation != .Interactive || !request.trusted ||
	   confirmation.operation_id != request.operation_id ||
	   confirmation.adapter_generation != request.adapter_generation ||
	   confirmation.policy_generation != request.policy_generation ||
	   confirmation.effects != request.effects {
		return result, false
	}
	confirmation.consumed = true
	confirmed := result
	confirmed.decision = .Allow
	return confirmed, true
}

/* prepare_process_request validates authority, limits, deadlines, and exact generations. */
prepare_process_request :: proc(
	operation_id: Operation_ID,
	scope: Scope,
	adapter: Adapter_Selection,
	authority: Authority_Result,
	working_resource: u64,
	input: Serialized_Input,
	environment: Effective_Environment,
	deadline_ns, cancellation_grace_ns: i64,
) -> (Process_Request, bool, Failure) {
	if operation_id == Operation_ID(0) || !scope_is_valid(scope) || adapter.state != .Selected ||
	   authority.operation_id != operation_id || authority.decision != .Allow || !authority.explicit_trigger ||
	   authority.policy_generation != scope.policy_generation ||
	   adapter.adapter_generation != scope.adapter_generation || working_resource == 0 ||
	   !input.complete || !environment.complete ||
	   environment.configuration_generation != scope.configuration_generation ||
	   !limits_are_valid(adapter.limits) || deadline_ns <= 0 || cancellation_grace_ns <= 0 ||
	   cancellation_grace_ns >= deadline_ns {
		return {}, false, execution_failure(.Invalid_Request, .Process)
	}
	return {
		operation_id = operation_id,
		scope = scope,
		adapter = adapter,
		authority = authority,
		working_resource = working_resource,
		input = input,
		environment = environment,
		limits = adapter.limits,
		deadline_ns = deadline_ns,
		cancellation_grace_ns = cancellation_grace_ns,
	}, true, {}
}

/* process_record_transition applies cancellation, timeout, quarantine, and cleanup observations. */
process_record_transition :: proc(
	record: Process_Record,
	event: Execution_Process_Event,
	now_ns: i64,
	process_identity: u64 = 0,
) -> (Process_Record, bool, Failure) {
	if record.operation_id == Operation_ID(0) || record.adapter_generation == Adapter_Generation(0) ||
	   record.policy_generation == Policy_Generation(0) || event == .Invalid || now_ns < 0 {
		return record, false, execution_failure(.Invalid_Request, .Process)
	}
	next := record
	switch record.state {
	case .Prepared:
		if event != .Start do return record, false, execution_failure(.Conflict, .Process)
		next.state = .Starting
	case .Starting:
		if event == .Started && process_identity != 0 {
			next.state = .Running
			next.process_identity = process_identity
			next.started_ns = now_ns
		} else if event == .Fail {
			next.state = .Failed
		} else {
			return record, false, execution_failure(.Conflict, .Process)
		}
	case .Running:
		if event == .Complete {
			next.state = .Completed
		} else if event == .Cancel {
			next.state = .Cancelling
		} else if event == .Timeout || (record.deadline_ns > 0 && now_ns >= record.deadline_ns) {
			next.state = .Timed_Out
		} else if event == .Fail {
			next.state = .Failed
		} else {
			return record, false, execution_failure(.Conflict, .Process)
		}
	case .Cancelling:
		if event == .Complete || event == .Fail {
			next.state = .Cleaning
		} else if event == .Timeout {
			next.state = .Quarantined
		} else {
			return record, false, execution_failure(.Conflict, .Process)
		}
	case .Completed, .Failed, .Timed_Out:
		if event == .Begin_Cleanup {
			next.state = .Cleaning
		} else if event == .Quarantine && record.state == .Timed_Out {
			next.state = .Quarantined
		} else {
			return record, false, execution_failure(.Conflict, .Process)
		}
	case .Quarantined:
		if event != .Reconcile do return record, false, execution_failure(.Quarantined, .Adapter)
		next.state = .Cleaning
	case .Cleaning:
		if event != .Cleanup_Confirmed do return record, false, execution_failure(.Conflict, .Process)
		next.state = .Closed
		next.cleanup_confirmed = true
	case .Closed, .Invalid:
		return record, false, execution_failure(.Conflict, .Process)
	}
	return next, true, {}
}

/* adapter_health_update quarantines timed-out generations until explicit reconciliation. */
adapter_health_update :: proc(
	health: Adapter_Health,
	operation_id: Operation_ID,
	generation: Adapter_Generation,
	event: Execution_Process_Event,
) -> (Adapter_Health, bool) {
	if generation == Adapter_Generation(0) || operation_id == Operation_ID(0) do return health, false
	if health.adapter_generation != Adapter_Generation(0) && health.adapter_generation != generation do return health, false
	next := health
	next.adapter_generation = generation
	#partial switch event {
	case .Timeout, .Quarantine:
		next.quarantined = true
		next.failure = .Timed_Out
		next.operation_id = operation_id
	case .Reconcile:
		if !health.quarantined do return health, false
		next.quarantined = false
		next.failure = .None
		next.operation_id = 0
	case:
		return health, false
	}
	return next, true
}

/* normalize_adapter_diagnostic copies one typed provider diagnostic. */
normalize_adapter_diagnostic :: proc(
	candidate: Adapter_Diagnostic_Candidate,
	scope: Scope,
) -> (Diagnostic_Record, bool) {
	if candidate.kind == .Invalid || len(candidate.message) == 0 ||
	   len(candidate.message) > MAX_DIAGNOSTIC_BYTES || !utf8.valid_string(candidate.message) {
		return {}, false
	}
	if candidate.has_range && (candidate.range.scope != scope.analysis ||
	   !language.jan_source_range_is_valid(candidate.range, scope.source_bytes)) {
		return {}, false
	}
	record := Diagnostic_Record{kind = candidate.kind, range = candidate.range, has_range = candidate.has_range}
	record.length = u16(copy(record.message[:], candidate.message))
	return record, true
}

@(private)
argument_key_copy :: proc(value: string) -> (Argument_Key, bool) {
	if len(value) == 0 || len(value) > MAX_ARGUMENT_KEY_BYTES || !utf8.valid_string(value) do return {}, false
	result: Argument_Key
	result.length = u8(copy(result.bytes[:], value))
	return result, true
}

@(private)
argument_value_copy :: proc(value: string) -> (Argument_Value, bool) {
	if len(value) > MAX_ARGUMENT_VALUE_BYTES || !utf8.valid_string(value) do return {}, false
	result: Argument_Value
	result.length = u16(copy(result.bytes[:], value))
	return result, true
}

@(private)
argument_key_equal :: proc(left, right: Argument_Key) -> bool {
	if left.length != right.length do return false
	left_bytes, right_bytes := left.bytes, right.bytes
	for value, index in left_bytes[:left.length] do if value != right_bytes[index] do return false
	return true
}

@(private)
argument_trace_after :: proc(left, right: Argument_Trace) -> bool {
	return left.source > right.source || (left.source == right.source && left.order > right.order)
}

@(private)
argument_value_append :: proc(target: ^Argument_Value, value: Argument_Value) -> bool {
	separator := 1 if target.length > 0 && value.length > 0 else 0
	if int(target.length) + separator + int(value.length) > len(target.bytes) do return false
	if separator == 1 {
		target.bytes[target.length] = '\n'
		target.length += 1
	}
	value_bytes := value.bytes
	target.length += u16(copy(target.bytes[target.length:], value_bytes[:value.length]))
	return true
}

@(private)
effects_contain :: proc(available, requested: Effects) -> bool {
	for effect := Effect.Read_Resource; effect <= .Credential; effect = Effect(int(effect) + 1) {
		if effect in requested && effect not_in available do return false
	}
	return true
}

@(private)
execution_failure :: proc(code: Failure_Code, field: Failure_Field) -> Failure {
	return {kind = .Execute, code = code, field = field}
}
