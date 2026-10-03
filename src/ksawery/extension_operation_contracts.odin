// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery

import "core:unicode/utf8"

/* DEFAULT_EXTENSION_OPERATION_PLANS is the initial contributor plan budget. */
DEFAULT_EXTENSION_OPERATION_PLANS :: u16(128)
/* MAX_EXTENSION_OPERATION_PLANS is the immutable contributor plan ceiling. */
MAX_EXTENSION_OPERATION_PLANS :: u16(512)
/* DEFAULT_EXTENSION_OPERATION_ARGUMENTS is the initial per-plan argument budget. */
DEFAULT_EXTENSION_OPERATION_ARGUMENTS :: u16(16)
/* MAX_EXTENSION_OPERATION_ARGUMENTS is the immutable per-plan argument ceiling. */
MAX_EXTENSION_OPERATION_ARGUMENTS :: u16(64)
/* MAX_EXTENSION_OPERATION_ARGUMENT_BYTES bounds one copied executable argument. */
MAX_EXTENSION_OPERATION_ARGUMENT_BYTES :: 512
/* DEFAULT_EXTENSION_OPERATION_VECTOR_BYTES is the initial declaration vector budget. */
DEFAULT_EXTENSION_OPERATION_VECTOR_BYTES :: u64(1 * MEBIBYTE)
/* MAX_EXTENSION_OPERATION_VECTOR_BYTES is the immutable declaration vector ceiling. */
MAX_EXTENSION_OPERATION_VECTOR_BYTES :: u64(8 * MEBIBYTE)
/* MAX_EXTENSION_OPERATION_EXECUTABLE_BYTES bounds one configured absolute path. */
MAX_EXTENSION_OPERATION_EXECUTABLE_BYTES :: 4 * KIBIBYTE
/* DEFAULT_EXTENSION_OPERATION_OUTPUT_BYTES is the initial public output budget. */
DEFAULT_EXTENSION_OPERATION_OUTPUT_BYTES :: u64(1 * MEBIBYTE)
/* MAX_EXTENSION_OPERATION_OUTPUT_BYTES is the immutable public output ceiling. */
MAX_EXTENSION_OPERATION_OUTPUT_BYTES :: u64(8 * MEBIBYTE)
/* DEFAULT_EXTENSION_OPERATION_DIAGNOSTIC_BYTES is the initial public diagnostic budget. */
DEFAULT_EXTENSION_OPERATION_DIAGNOSTIC_BYTES :: u64(4 * KIBIBYTE)
/* MAX_EXTENSION_OPERATION_DIAGNOSTIC_BYTES is the immutable public diagnostic ceiling. */
MAX_EXTENSION_OPERATION_DIAGNOSTIC_BYTES :: u64(64 * KIBIBYTE)
/* MIN_EXTENSION_OPERATION_DEADLINE_NS is the smallest admitted child deadline. */
MIN_EXTENSION_OPERATION_DEADLINE_NS :: i64(100_000_000)
/* DEFAULT_EXTENSION_OPERATION_DEADLINE_NS is the initial child deadline. */
DEFAULT_EXTENSION_OPERATION_DEADLINE_NS :: i64(30_000_000_000)
/* MAX_EXTENSION_OPERATION_DEADLINE_NS is the immutable child deadline ceiling. */
MAX_EXTENSION_OPERATION_DEADLINE_NS :: i64(600_000_000_000)
/* DEFAULT_EXTENSION_OPERATION_CANCELLATION_GRACE_NS is the initial graceful-stop budget. */
DEFAULT_EXTENSION_OPERATION_CANCELLATION_GRACE_NS :: i64(250_000_000)
/* MAX_EXTENSION_OPERATION_CANCELLATION_GRACE_NS is the immutable graceful-stop ceiling. */
MAX_EXTENSION_OPERATION_CANCELLATION_GRACE_NS :: i64(5_000_000_000)
/* DEFAULT_EXTENSION_OPERATION_COPY_BYTES is the initial complete-plan copy budget. */
DEFAULT_EXTENSION_OPERATION_COPY_BYTES :: u64(1 * MEBIBYTE)
/* MAX_EXTENSION_OPERATION_COPY_BYTES is the immutable complete-plan copy ceiling. */
MAX_EXTENSION_OPERATION_COPY_BYTES :: u64(8 * MEBIBYTE)

/* Extension_Operation_Plan_ID identifies one contributor-owned external plan. */
Extension_Operation_Plan_ID :: distinct u64
/* Extension_Operation_Plan_Generation_ID identifies one immutable plan generation. */
Extension_Operation_Plan_Generation_ID :: distinct u64
/* Extension_Operation_Request_ID identifies one checked plan submission. */
Extension_Operation_Request_ID :: distinct u64

/* Extension_Operation_Submission binds one plan request to copied repository truth. */
Extension_Operation_Submission :: struct {
	request:               Extension_Operation_Request_ID,
	contributor:           Contributor_Handle,
	contribution:          Contribution_ID,
	repository:            Repository_Context,
	repository_generation: Repository_Generation,
}

/* Extension_Operation_Refresh_Evidence copies one complete core-owned refresh attempt. */
Extension_Operation_Refresh_Evidence :: struct {
	repository:            Repository_Context,
	repository_generation: Repository_Generation,
	attempted:             Extension_Observation_Families,
	completed:             Extension_Observation_Families,
	target_checked:        bool,
	target:                Extension_Annotation_Target,
	target_present:        bool,
	operation_checked:     bool,
	operation:             Operation_State,
}

/* Extension_Operation_Executable_Kind closes ordinary executable selection. */
Extension_Operation_Executable_Kind :: enum u8 {
	Invalid,
	Built_In_Git,
	Configured_Absolute_Path,
}

/* Extension_Operation_Effect declares the strongest possible external effect. */
Extension_Operation_Effect :: enum u8 {
	Invalid,
	Read_Only,
	Repository_Mutating,
	Externally_Mutating,
}

/* Extension_Operation_Environment_Profile selects one core-owned environment. */
Extension_Operation_Environment_Profile :: enum u8 {
	Invalid,
	Core_Repository,
}

/* Extension_Operation_Diagnostic_Policy controls public diagnostic projection. */
Extension_Operation_Diagnostic_Policy :: enum u8 {
	Invalid,
	Suppressed,
	Bounded_Public,
}

/* Extension_Operation_Verifier_Kind closes provider-selectable success evidence. */
Extension_Operation_Verifier_Kind :: enum u8 {
	None,
	Observation_Available,
	Target_Present,
	Target_Absent,
	Operation_State,
}

/* Extension_Operation_Executable is one built-in role or configured absolute path. */
Extension_Operation_Executable :: struct {
	kind:        Extension_Operation_Executable_Kind,
	identity:    Extension_Identity,
	path:        [MAX_EXTENSION_OPERATION_EXECUTABLE_BYTES]u8,
	path_length: u16,
}

/* Extension_Operation_Argument owns one copied non-shell argument. */
Extension_Operation_Argument :: struct {
	bytes:  [MAX_EXTENSION_OPERATION_ARGUMENT_BYTES]u8,
	length: u16,
}

/* Extension_Operation_Verifier names one typed refreshed condition. */
Extension_Operation_Verifier :: struct {
	kind:        Extension_Operation_Verifier_Kind,
	observation: Extension_Observation_Family,
	target:      Extension_Annotation_Target,
	operation:   Operation_State,
}

/* Extension_Operation_Process_Limits bounds one admitted external child. */
Extension_Operation_Process_Limits :: struct {
	output_bytes:          u64,
	diagnostic_bytes:      u64,
	deadline_nanoseconds:  i64,
	cancellation_grace_ns: i64,
}

/* DEFAULT_EXTENSION_OPERATION_PROCESS_LIMITS selects the measured initial envelope. */
DEFAULT_EXTENSION_OPERATION_PROCESS_LIMITS :: Extension_Operation_Process_Limits {
	output_bytes = DEFAULT_EXTENSION_OPERATION_OUTPUT_BYTES,
	diagnostic_bytes = DEFAULT_EXTENSION_OPERATION_DIAGNOSTIC_BYTES,
	deadline_nanoseconds = DEFAULT_EXTENSION_OPERATION_DEADLINE_NS,
	cancellation_grace_ns = DEFAULT_EXTENSION_OPERATION_CANCELLATION_GRACE_NS,
}

/* Extension_Operation_Declaration_Limits bounds one complete plan declaration. */
Extension_Operation_Declaration_Limits :: struct {
	plans:          u16,
	arguments:      u16,
	argument_bytes: u64,
	copy_bytes:     u64,
}

/* DEFAULT_EXTENSION_OPERATION_DECLARATION_LIMITS selects initial declaration bounds. */
DEFAULT_EXTENSION_OPERATION_DECLARATION_LIMITS :: Extension_Operation_Declaration_Limits {
	plans = DEFAULT_EXTENSION_OPERATION_PLANS,
	arguments = DEFAULT_EXTENSION_OPERATION_ARGUMENTS,
	argument_bytes = DEFAULT_EXTENSION_OPERATION_VECTOR_BYTES,
	copy_bytes = DEFAULT_EXTENSION_OPERATION_COPY_BYTES,
}

/* Extension_Operation_Plan is one immutable authority-free process proposal. */
Extension_Operation_Plan :: struct {
	contributor:       Contributor_Handle,
	contribution:      Contribution_ID,
	plan:              Extension_Operation_Plan_ID,
	generation:        Extension_Operation_Plan_Generation_ID,
	identity:          Extension_Identity,
	purpose:           Extension_Label,
	executable:        Extension_Operation_Executable,
	arguments:         []Extension_Operation_Argument,
	effect:            Extension_Operation_Effect,
	refresh:           Extension_Observation_Families,
	verifier:          Extension_Operation_Verifier,
	environment:       Extension_Operation_Environment_Profile,
	diagnostic_policy: Extension_Operation_Diagnostic_Policy,
	process_limits:    Extension_Operation_Process_Limits,
}

/* Extension_Operation_Usage reports exact copied plan and result occupancy. */
Extension_Operation_Usage :: struct {
	arguments:       u32,
	argument_bytes:  u64,
	copy_bytes:      u64,
	output_bytes:    u64,
	diagnostic_bytes: u64,
}

/* Extension_Operation_Result binds terminal Process evidence to one exact plan. */
Extension_Operation_Result :: struct {
	request:              Extension_Operation_Request_ID,
	contributor:          Contributor_Handle,
	plan:                 Extension_Operation_Plan_ID,
	plan_generation:      Extension_Operation_Plan_Generation_ID,
	outcome:              Repository_Process_Outcome,
	effect_possible:      bool,
	exit_code_present:    bool,
	exit_code:            i32,
	refresh_completed:    bool,
	verifier_applied:     bool,
	verifier_agreed:      bool,
	output_bytes:         u64,
	diagnostic_bytes:     u64,
	output_truncated:     bool,
	diagnostic_truncated: bool,
}

/* Extension_Operation_Failure_Code classifies bounded plan and result rejection. */
Extension_Operation_Failure_Code :: enum u16 {
	None,
	Invalid_Plan,
	Invalid_Executable,
	Invalid_Argument,
	Invalid_Effect,
	Invalid_Refresh,
	Invalid_Verifier,
	Invalid_Environment,
	Invalid_Diagnostic_Policy,
	Invalid_Process_Limits,
	Invalid_Result,
	Stale_Contributor,
	Stale_Plan,
	Argument_Limit,
	Argument_Bytes_Limit,
	Output_Limit,
	Diagnostic_Limit,
	Deadline_Limit,
	Copy_Limit,
	Stale_Repository,
	Contribution_Unavailable,
	Executable_Unavailable,
	Process_Start,
	Allocation,
}

/* Extension_Operation_Failure retains attributable bounded rejection evidence. */
Extension_Operation_Failure :: struct {
	code:     Extension_Operation_Failure_Code,
	plan:     Extension_Operation_Plan_ID,
	argument: u32,
	limit:    u64,
	actual:   u64,
}

/* extension_operation_argument_assign copies one UTF-8 argument without interpolation. */
extension_operation_argument_assign :: proc(
	argument: ^Extension_Operation_Argument,
	value: string,
) -> bool {
	if argument == nil do return false
	argument^ = {}
	if len(value) == 0 || len(value) > len(argument.bytes) || !utf8.valid_string(value) do return false
	for byte in transmute([]u8)value {
		if byte == 0 do return false
	}
	copy(argument.bytes[:len(value)], transmute([]u8)value)
	argument.length = u16(len(value))
	return true
}

/* extension_operation_executable_assign_git selects the core-owned Git role. */
extension_operation_executable_assign_git :: proc(
	executable: ^Extension_Operation_Executable,
) -> bool {
	if executable == nil do return false
	executable^ = {}
	executable.kind = .Built_In_Git
	return extension_identity_assign(&executable.identity, "git")
}

/* extension_operation_executable_assign_absolute copies one configured executable. */
extension_operation_executable_assign_absolute :: proc(
	executable: ^Extension_Operation_Executable,
	identity: string,
	path: string,
) -> bool {
	if executable == nil do return false
	executable^ = {}
	if !extension_identity_assign(&executable.identity, identity) ||
	   len(path) == 0 || len(path) > len(executable.path) || path[0] != '/' ||
	   !utf8.valid_string(path) {
		return false
	}
	for byte in transmute([]u8)path {
		if byte == 0 do return false
	}
	executable.kind = .Configured_Absolute_Path
	copy(executable.path[:len(path)], transmute([]u8)path)
	executable.path_length = u16(len(path))
	return true
}

/* extension_operation_process_limits_are_valid checks one child envelope. */
extension_operation_process_limits_are_valid :: proc(
	limits: Extension_Operation_Process_Limits,
) -> bool {
	return limits.output_bytes > 0 &&
		limits.output_bytes <= MAX_EXTENSION_OPERATION_OUTPUT_BYTES &&
		limits.diagnostic_bytes > 0 &&
		limits.diagnostic_bytes <= MAX_EXTENSION_OPERATION_DIAGNOSTIC_BYTES &&
		limits.deadline_nanoseconds >= MIN_EXTENSION_OPERATION_DEADLINE_NS &&
		limits.deadline_nanoseconds <= MAX_EXTENSION_OPERATION_DEADLINE_NS &&
		limits.cancellation_grace_ns > 0 &&
		limits.cancellation_grace_ns <= MAX_EXTENSION_OPERATION_CANCELLATION_GRACE_NS &&
		limits.cancellation_grace_ns < limits.deadline_nanoseconds
}

/* extension_operation_declaration_limits_are_valid checks immutable policy ceilings. */
extension_operation_declaration_limits_are_valid :: proc(
	limits: Extension_Operation_Declaration_Limits,
) -> bool {
	return limits.plans > 0 && limits.plans <= MAX_EXTENSION_OPERATION_PLANS &&
		limits.arguments > 0 && limits.arguments <= MAX_EXTENSION_OPERATION_ARGUMENTS &&
		limits.argument_bytes > 0 &&
		limits.argument_bytes <= MAX_EXTENSION_OPERATION_VECTOR_BYTES &&
		limits.copy_bytes > 0 && limits.copy_bytes <= MAX_EXTENSION_OPERATION_COPY_BYTES
}

/* extension_operation_plan_validate checks one complete immutable proposal. */
extension_operation_plan_validate :: proc(
	plan: Extension_Operation_Plan,
	limits := DEFAULT_EXTENSION_OPERATION_DECLARATION_LIMITS,
) -> (usage: Extension_Operation_Usage, failure: Extension_Operation_Failure) {
	failure.plan = plan.plan
	if !extension_operation_declaration_limits_are_valid(limits) ||
	   !contributor_handle_is_valid(plan.contributor) || plan.contribution == 0 ||
	   plan.plan == 0 || plan.generation == 0 || !extension_identity_is_valid(plan.identity) ||
	   !extension_label_is_valid(plan.purpose) {
		failure.code = .Invalid_Plan
		return
	}
	if !extension_operation_executable_is_valid(plan.executable) {
		failure.code = .Invalid_Executable
		return
	}
	if plan.effect <= .Invalid || plan.effect > .Externally_Mutating {
		failure.code = .Invalid_Effect
		return
	}
	if plan.refresh == {} {
		failure.code = .Invalid_Refresh
		return
	}
	if !extension_operation_verifier_is_valid(plan.verifier, plan.refresh) {
		failure.code = .Invalid_Verifier
		return
	}
	if plan.environment != .Core_Repository {
		failure.code = .Invalid_Environment
		return
	}
	if plan.diagnostic_policy <= .Invalid || plan.diagnostic_policy > .Bounded_Public {
		failure.code = .Invalid_Diagnostic_Policy
		return
	}
	if !extension_operation_process_limits_are_valid(plan.process_limits) {
		failure.code = .Invalid_Process_Limits
		return
	}
	if len(plan.arguments) > int(limits.arguments) {
		failure.code = .Argument_Limit
		failure.limit = u64(limits.arguments)
		failure.actual = u64(len(plan.arguments))
		return
	}
	usage.arguments = u32(len(plan.arguments))
	usage.copy_bytes = u64(size_of(Extension_Operation_Plan)) +
		u64(len(plan.arguments) * size_of(Extension_Operation_Argument))
	for argument, index in plan.arguments {
		if !extension_operation_argument_is_valid(argument) {
			failure.code = .Invalid_Argument
			failure.argument = u32(index)
			return
		}
		usage.argument_bytes += u64(argument.length)
	}
	if usage.argument_bytes > limits.argument_bytes {
		failure.code = .Argument_Bytes_Limit
		failure.limit = limits.argument_bytes
		failure.actual = usage.argument_bytes
		return
	}
	if usage.copy_bytes > limits.copy_bytes {
		failure.code = .Copy_Limit
		failure.limit = limits.copy_bytes
		failure.actual = usage.copy_bytes
		return
	}
	return usage, failure
}

/* extension_operation_submission_validate admits one current declared plan request. */
extension_operation_submission_validate :: proc(
	submission: Extension_Operation_Submission,
	plan: Extension_Operation_Plan,
	declaration: Contribution_Declaration,
	current_contributor: Contributor_Handle,
	current_repository: Repository_Context,
	current_repository_generation: Repository_Generation,
) -> (usage: Extension_Operation_Usage, failure: Extension_Operation_Failure) {
	usage, failure = extension_operation_plan_validate(plan)
	if failure.code != .None do return
	failure.plan = plan.plan
	if submission.request == 0 || !contributor_handle_is_valid(submission.contributor) ||
	   !repository_context_is_valid(submission.repository) ||
	   submission.repository_generation == Repository_Generation(0) {
		failure.code = .Invalid_Plan
		return
	}
	if !contributor_handle_is_valid(current_contributor) ||
	   submission.contributor != current_contributor || plan.contributor != current_contributor {
		failure.code = .Stale_Contributor
		return
	}
	if !repository_context_is_valid(current_repository) ||
	   submission.repository != current_repository ||
	   current_repository_generation == Repository_Generation(0) ||
	   submission.repository_generation != current_repository_generation {
		failure.code = .Stale_Repository
		return
	}
	if submission.contribution != plan.contribution ||
	   !contribution_declaration_is_valid(declaration) ||
	   declaration.id != plan.contribution || declaration.kind != .External_Operation ||
	   .Submit_External_Operation not_in declaration.requested_authority ||
	   plan.refresh - declaration.required_observations != {} {
		failure.code = .Contribution_Unavailable
		return
	}
	return
}

/* extension_operation_verifier_apply derives typed truth only from refreshed evidence. */
extension_operation_verifier_apply :: proc(
	submission: Extension_Operation_Submission,
	plan: Extension_Operation_Plan,
	evidence: Extension_Operation_Refresh_Evidence,
) -> (refresh_completed, applied, agreed, valid: bool) {
	if !extension_operation_refresh_evidence_is_valid(submission, plan, evidence) {
		return false, false, false, false
	}
	refresh_completed = plan.refresh - evidence.completed == {}
	switch plan.verifier.kind {
	case .None:
		return refresh_completed, false, false, true
	case .Observation_Available:
		applied = plan.verifier.observation in evidence.attempted
		agreed = applied && plan.verifier.observation in evidence.completed
		return refresh_completed, applied, agreed, true
	case .Target_Present, .Target_Absent:
		applied = plan.verifier.observation in evidence.completed && evidence.target_checked
		if !applied do return refresh_completed, false, false, true
		if !extension_operation_targets_match(plan.verifier.target, evidence.target) {
			return false, false, false, false
		}
		agreed = evidence.target_present == (plan.verifier.kind == .Target_Present)
		return refresh_completed, true, agreed, true
	case .Operation_State:
		applied = plan.verifier.observation in evidence.completed && evidence.operation_checked
		agreed = applied && evidence.operation == plan.verifier.operation
		return refresh_completed, applied, agreed, true
	}
	return false, false, false, false
}

@(private)
extension_operation_refresh_evidence_is_valid :: proc(
	submission: Extension_Operation_Submission,
	plan: Extension_Operation_Plan,
	evidence: Extension_Operation_Refresh_Evidence,
) -> bool {
	if !repository_context_is_valid(evidence.repository) ||
	   evidence.repository != submission.repository ||
	   evidence.repository_generation <= submission.repository_generation ||
	   evidence.attempted != plan.refresh || evidence.completed - evidence.attempted != {} {
		return false
	}
	if evidence.target_checked {
		if !extension_annotation_target_is_valid(evidence.target) do return false
	} else if evidence.target != {} || evidence.target_present {
		return false
	}
	if !evidence.operation_checked && evidence.operation != .Unknown do return false
	return true
}

@(private)
extension_operation_targets_match :: proc(
	expected, refreshed: Extension_Annotation_Target,
) -> bool {
	if !extension_annotation_target_is_valid(expected) ||
	   !extension_annotation_target_is_valid(refreshed) ||
	   expected.family != refreshed.family || refreshed.generation <= expected.generation ||
	   expected.length != refreshed.length {
		return false
	}
	for index in 0 ..< int(expected.length) {
		if expected.identity[index] != refreshed.identity[index] do return false
	}
	return true
}

/* extension_operation_result_validate checks terminal evidence without trusting exit text. */
extension_operation_result_validate :: proc(
	result: Extension_Operation_Result,
	request: Extension_Operation_Request_ID,
	plan: Extension_Operation_Plan,
) -> (usage: Extension_Operation_Usage, failure: Extension_Operation_Failure) {
	failure.plan = plan.plan
	if result.contributor != plan.contributor {
		failure.code = .Stale_Contributor
		return
	}
	if request == 0 || result.request != request || result.plan != plan.plan ||
	   result.plan_generation != plan.generation {
		failure.code = .Stale_Plan
		return
	}
	if result.output_bytes > plan.process_limits.output_bytes {
		failure.code = .Output_Limit
		failure.limit = plan.process_limits.output_bytes
		failure.actual = result.output_bytes
		return
	}
	if result.diagnostic_bytes > plan.process_limits.diagnostic_bytes {
		failure.code = .Diagnostic_Limit
		failure.limit = plan.process_limits.diagnostic_bytes
		failure.actual = result.diagnostic_bytes
		return
	}
	if plan.diagnostic_policy == .Suppressed &&
	   (result.diagnostic_bytes != 0 || result.diagnostic_truncated) {
		failure.code = .Invalid_Result
		return
	}
	if result.output_truncated && result.output_bytes != plan.process_limits.output_bytes {
		failure.code = .Invalid_Result
		return
	}
	if result.diagnostic_truncated &&
	   result.diagnostic_bytes != plan.process_limits.diagnostic_bytes {
		failure.code = .Invalid_Result
		return
	}
	if (!result.exit_code_present && result.exit_code != 0) ||
	   (result.verifier_agreed && !result.verifier_applied) ||
	   (plan.verifier.kind == .None && (result.verifier_applied || result.verifier_agreed)) {
		failure.code = .Invalid_Result
		return
	}
	if !extension_operation_result_shape_is_valid(result, plan.verifier) {
		failure.code = .Invalid_Result
		return
	}
	usage.output_bytes = result.output_bytes
	usage.diagnostic_bytes = result.diagnostic_bytes
	return usage, failure
}

@(private)
extension_operation_executable_is_valid :: proc(
	executable: Extension_Operation_Executable,
) -> bool {
	if !extension_identity_is_valid(executable.identity) do return false
	switch executable.kind {
	case .Built_In_Git:
		return executable.identity == extension_operation_git_identity() &&
			executable.path_length == 0
	case .Configured_Absolute_Path:
		if executable.path_length == 0 || int(executable.path_length) > len(executable.path) ||
		   executable.path[0] != '/' {
			return false
		}
		for index in 0 ..< int(executable.path_length) {
			if executable.path[index] == 0 do return false
		}
		copy_value := executable
		return utf8.valid_string(string(copy_value.path[:copy_value.path_length]))
	case .Invalid:
		return false
	}
	return false
}

@(private)
extension_operation_git_identity :: proc() -> Extension_Identity {
	identity: Extension_Identity
	assert(extension_identity_assign(&identity, "git"))
	return identity
}

@(private)
extension_operation_argument_is_valid :: proc(argument: Extension_Operation_Argument) -> bool {
	if argument.length == 0 || int(argument.length) > len(argument.bytes) do return false
	for index in 0 ..< int(argument.length) {
		if argument.bytes[index] == 0 do return false
	}
	copy_value := argument
	return utf8.valid_string(string(copy_value.bytes[:copy_value.length]))
}

@(private)
extension_operation_verifier_is_valid :: proc(
	verifier: Extension_Operation_Verifier,
	refresh: Extension_Observation_Families,
) -> bool {
	switch verifier.kind {
	case .None:
		return verifier.target == {} && verifier.operation == .Unknown
	case .Observation_Available:
		return verifier.observation in refresh && verifier.target == {} &&
			verifier.operation == .Unknown
	case .Target_Present, .Target_Absent:
		return verifier.observation in refresh && extension_annotation_target_is_valid(verifier.target) &&
			extension_operation_target_supports_observation(verifier.target.family, verifier.observation) &&
			verifier.operation == .Unknown
	case .Operation_State:
		return verifier.observation in refresh &&
			(verifier.observation == .Status || verifier.observation == .Sequence ||
			 verifier.observation == .Conflict) &&
			verifier.target == {} && verifier.operation != .Unknown
	}
	return false
}

@(private)
extension_operation_target_supports_observation :: proc(
	target: Extension_Annotation_Target_Family,
	observation: Extension_Observation_Family,
) -> bool {
	switch target {
	case .Path, .Diff_Unit:          return observation == .Status
	case .Revision, .Revision_Range: return observation == .History
	case .Ref, .Remote:              return observation == .Refs
	case .Conflict:                  return observation == .Conflict || observation == .Sequence
	case .Sequence:                  return observation == .Sequence
	case .Process:                   return observation == .Process
	case .Invalid:                   return false
	}
	return false
}

@(private)
extension_operation_result_shape_is_valid :: proc(
	result: Extension_Operation_Result,
	verifier: Extension_Operation_Verifier,
) -> bool {
	switch result.outcome {
	case .Verified_Success:
		return result.exit_code_present && result.exit_code == 0 && result.refresh_completed &&
			verifier.kind != .None && result.verifier_applied && result.verifier_agreed
	case .Known_Failure:
		return result.exit_code_present && result.exit_code != 0 && !result.verifier_agreed
	case .Cancelled_Before_Effect, .Timed_Out_Before_Effect:
		return !result.effect_possible && !result.verifier_agreed
	case .Cancelled_After_Possible_Effect, .Timed_Out_After_Possible_Effect:
		return result.effect_possible && result.refresh_completed && !result.verifier_agreed
	case .Verification_Mismatch:
		return result.exit_code_present && result.exit_code == 0 && result.refresh_completed &&
			verifier.kind != .None && result.verifier_applied && !result.verifier_agreed
	case .Indeterminate:
		return result.effect_possible || !result.refresh_completed ||
			!result.exit_code_present || verifier.kind == .None
	case .None:
		return false
	}
	return false
}
