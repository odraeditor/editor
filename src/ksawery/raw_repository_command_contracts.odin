// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery

import "core:unicode/utf8"

/* DEFAULT_RAW_REPOSITORY_COMMAND_BYTES is the initial transient input budget. */
DEFAULT_RAW_REPOSITORY_COMMAND_BYTES :: u16(1 * KIBIBYTE)
/* MAX_RAW_REPOSITORY_COMMAND_BYTES is the immutable transient input ceiling. */
MAX_RAW_REPOSITORY_COMMAND_BYTES :: u16(4 * KIBIBYTE)
/* MAX_RAW_REPOSITORY_COMMAND_ARGUMENTS bounds direct Git argument parsing. */
MAX_RAW_REPOSITORY_COMMAND_ARGUMENTS :: 64
/* RAW_REPOSITORY_COMMAND_REFRESH is the mandatory full compatible refresh set. */
RAW_REPOSITORY_COMMAND_REFRESH :: Extension_Observation_Families {
	.Status,
	.History,
	.Refs,
	.Sequence,
	.Conflict,
	.Process,
}

/* Raw_Repository_Command_ID identifies one session-local raw command intent. */
Raw_Repository_Command_ID :: distinct u64
/* Raw_Repository_Command_Confirmation_ID identifies one exact one-shot acknowledgement. */
Raw_Repository_Command_Confirmation_ID :: distinct u64

/* Raw_Repository_Command_Mode selects the explicit built-in interpreter boundary. */
Raw_Repository_Command_Mode :: enum u8 {
	Invalid,
	Git,
	Shell,
}

/* Raw_Repository_Command_Authority names the separate high-authority route. */
Raw_Repository_Command_Authority :: enum u8 {
	Invalid,
	Explicit_User_Confirmation,
}

/* Raw_Repository_Command_Redaction fixes public content handling. */
Raw_Repository_Command_Redaction :: enum u8 {
	Invalid,
	Omit_Sensitive_Content,
}

/* Raw_Repository_Command_Retention fixes command text to the current session. */
Raw_Repository_Command_Retention :: enum u8 {
	Invalid,
	Session_Transient,
}

/* Raw_Repository_Command_Input owns bounded private command text. */
Raw_Repository_Command_Input :: struct {
	mode:   Raw_Repository_Command_Mode,
	bytes:  [MAX_RAW_REPOSITORY_COMMAND_BYTES]u8,
	length: u16,
}

/* Raw_Repository_Command_Limits bounds transient input and child evidence. */
Raw_Repository_Command_Limits :: struct {
	input_bytes:           u16,
	output_bytes:          u64,
	diagnostic_bytes:      u64,
	deadline_nanoseconds:  i64,
	cancellation_grace_ns: i64,
}

/* DEFAULT_RAW_REPOSITORY_COMMAND_LIMITS selects the bounded initial policy. */
DEFAULT_RAW_REPOSITORY_COMMAND_LIMITS :: Raw_Repository_Command_Limits {
	input_bytes = DEFAULT_RAW_REPOSITORY_COMMAND_BYTES,
	output_bytes = DEFAULT_PROCESS_OUTPUT_BYTES,
	diagnostic_bytes = DEFAULT_DIAGNOSTIC_BYTES,
	deadline_nanoseconds = DEFAULT_PROCESS_TIMEOUT_NANOSECONDS,
	cancellation_grace_ns = DEFAULT_CANCELLATION_GRACE_NANOSECONDS,
}

/* Raw_Repository_Command_Verifier names optional core-owned refreshed proof. */
Raw_Repository_Command_Verifier :: struct {
	kind:        Extension_Operation_Verifier_Kind,
	observation: Extension_Observation_Family,
	target:      Extension_Annotation_Target,
	operation:   Operation_State,
}

/* Raw_Repository_Command_Intent is one private session-local command proposal. */
Raw_Repository_Command_Intent :: struct {
	command:               Raw_Repository_Command_ID,
	repository:            Repository_Context,
	repository_generation: Repository_Generation,
	observation_generation: Observation_Generation,
	input:                 Raw_Repository_Command_Input,
	verifier:              Raw_Repository_Command_Verifier,
	refresh:               Extension_Observation_Families,
	authority:             Raw_Repository_Command_Authority,
	redaction:             Raw_Repository_Command_Redaction,
	retention:             Raw_Repository_Command_Retention,
	limits:                Raw_Repository_Command_Limits,
}

/* Raw_Repository_Command_Confirmation owns one exact one-shot private intent. */
Raw_Repository_Command_Confirmation :: struct {
	id:        Raw_Repository_Command_Confirmation_ID,
	intent:    Raw_Repository_Command_Intent,
	confirmed: bool,
	consumed:  bool,
}

/* Raw_Repository_Command_Request is one confirmed Process-bound command. */
Raw_Repository_Command_Request :: struct {
	operation:    Repository_Operation_ID,
	intent:       Raw_Repository_Command_Intent,
	confirmation: Raw_Repository_Command_Confirmation_ID,
}

/* Raw_Repository_Command_Refresh_Evidence records the complete core refresh attempt. */
Raw_Repository_Command_Refresh_Evidence :: struct {
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

/* Raw_Repository_Command_Process_Evidence binds one request to its public Process record. */
Raw_Repository_Command_Process_Evidence :: struct {
	association: Repository_Process_Association,
	started:     bool,
	detached:    bool,
}

/* Raw_Repository_Command_Cleanup_Evidence proves transient ownership was released. */
Raw_Repository_Command_Cleanup_Evidence :: struct {
	input_cleared:        bool,
	confirmation_cleared: bool,
	child_closed:         bool,
	association_detached: bool,
}

/* Raw_Repository_Command_Result retains no entered command text. */
Raw_Repository_Command_Result :: struct {
	command:               Raw_Repository_Command_ID,
	mode:                  Raw_Repository_Command_Mode,
	repository:            Repository_Context,
	process:               Raw_Repository_Command_Process_Evidence,
	outcome:               Repository_Process_Outcome,
	failure:               Failure_Code,
	effect_possible:       bool,
	exit_code_present:     bool,
	exit_code:             i32,
	refresh_completed:     bool,
	verifier_applied:      bool,
	verifier_agreed:       bool,
	output_bytes:          u64,
	diagnostic_bytes:      u64,
	output_truncated:      bool,
	diagnostic_truncated:  bool,
	diagnostic_omitted:    bool,
	cleanup:               Raw_Repository_Command_Cleanup_Evidence,
}

/* Raw_Repository_Command_Failure_Code classifies contract rejection. */
Raw_Repository_Command_Failure_Code :: enum u16 {
	None,
	Invalid_Input,
	Invalid_Intent,
	Confirmation_Required,
	Confirmation_Mismatch,
	Confirmation_Consumed,
	Invalid_Request,
	Stale_Repository,
	Stale_Process,
	Invalid_Refresh,
	Invalid_Result,
	Sensitive_Content,
	Input_Limit,
	Output_Limit,
	Diagnostic_Limit,
	Deadline_Limit,
	Cleanup_Incomplete,
	Allocation,
	Process_Start,
	Executable_Unavailable,
}

/* Raw_Repository_Command_Failure retains one bounded attributable rejection. */
Raw_Repository_Command_Failure :: struct {
	code:    Raw_Repository_Command_Failure_Code,
	command: Raw_Repository_Command_ID,
	limit:   u64,
	actual:  u64,
}

/* raw_repository_command_input_assign copies one private Git or shell command. */
raw_repository_command_input_assign :: proc(
	input: ^Raw_Repository_Command_Input,
	mode: Raw_Repository_Command_Mode,
	text: string,
	limit := DEFAULT_RAW_REPOSITORY_COMMAND_BYTES,
) -> (bool, Raw_Repository_Command_Failure) {
	if input == nil do return false, {code = .Invalid_Input}
	input^ = {}
	if limit == 0 || limit > MAX_RAW_REPOSITORY_COMMAND_BYTES {
		return false, {code = .Input_Limit, limit = u64(MAX_RAW_REPOSITORY_COMMAND_BYTES), actual = u64(limit)}
	}
	if len(text) == 0 || len(text) > int(limit) {
		return false, {code = .Input_Limit, limit = u64(limit), actual = u64(len(text))}
	}
	if mode == .Invalid || !utf8.valid_string(text) {
		return false, {code = .Invalid_Input}
	}
	visible := false
	for value in transmute([]u8)text {
		if value == 0 || value == '\n' || value == '\r' || value == 0x1b || value == 0x7f ||
		   value == 0x9b || (value < 0x20 && value != '\t') {
			return false, {code = .Invalid_Input}
		}
		if value != ' ' && value != '\t' do visible = true
	}
	if !visible do return false, {code = .Invalid_Input}
	input.mode = mode
	input.length = u16(len(text))
	copy(input.bytes[:len(text)], transmute([]u8)text)
	return true, {}
}

/* raw_repository_command_input_is_valid checks one complete transient input value. */
raw_repository_command_input_is_valid :: proc(
	input: Raw_Repository_Command_Input,
	limit := DEFAULT_RAW_REPOSITORY_COMMAND_BYTES,
) -> bool {
	if limit == 0 || limit > MAX_RAW_REPOSITORY_COMMAND_BYTES || input.mode == .Invalid ||
	   input.length == 0 || input.length > limit {
		return false
	}
	copy := input
	assigned: Raw_Repository_Command_Input
	valid, _ := raw_repository_command_input_assign(
		&assigned,
		copy.mode,
		string(copy.bytes[:copy.length]),
		limit,
	)
	return valid && assigned == input
}

/* raw_repository_command_input_text borrows private text only from a live owner. */
raw_repository_command_input_text :: proc(input: ^Raw_Repository_Command_Input) -> string {
	if input == nil || !raw_repository_command_input_is_valid(input^, MAX_RAW_REPOSITORY_COMMAND_BYTES) {
		return ""
	}
	return string(input.bytes[:input.length])
}

/* raw_repository_command_limits_are_valid checks the complete child envelope. */
raw_repository_command_limits_are_valid :: proc(limits: Raw_Repository_Command_Limits) -> bool {
	return limits.input_bytes > 0 && limits.input_bytes <= MAX_RAW_REPOSITORY_COMMAND_BYTES &&
		limits.output_bytes >= MIN_PROCESS_OUTPUT_BYTES &&
		limits.output_bytes <= MAX_PROCESS_OUTPUT_BYTES &&
		limits.diagnostic_bytes >= MIN_DIAGNOSTIC_BYTES &&
		limits.diagnostic_bytes <= MAX_DIAGNOSTIC_BYTES &&
		limits.diagnostic_bytes <= limits.output_bytes &&
		limits.deadline_nanoseconds >= MIN_PROCESS_TIMEOUT_NANOSECONDS &&
		limits.deadline_nanoseconds <= MAX_PROCESS_TIMEOUT_NANOSECONDS &&
		limits.cancellation_grace_ns > 0 &&
		limits.cancellation_grace_ns < limits.deadline_nanoseconds
}

/* raw_repository_command_verifier_is_valid keeps proof independent of provider plans. */
raw_repository_command_verifier_is_valid :: proc(
	verifier: Raw_Repository_Command_Verifier,
	refresh: Extension_Observation_Families,
) -> bool {
	switch verifier.kind {
	case .None:
		return verifier.target == {} && verifier.operation == .Unknown
	case .Observation_Available:
		return verifier.observation in refresh && verifier.target == {} &&
			verifier.operation == .Unknown
	case .Target_Present, .Target_Absent:
		return verifier.observation in refresh &&
			extension_annotation_target_is_valid(verifier.target) &&
			raw_repository_command_target_supports_observation(
				verifier.target.family,
				verifier.observation,
			) && verifier.operation == .Unknown
	case .Operation_State:
		return verifier.observation in refresh &&
			(verifier.observation == .Status || verifier.observation == .Sequence ||
			 verifier.observation == .Conflict) &&
			verifier.target == {} && verifier.operation != .Unknown
	}
	return false
}

/* raw_repository_command_intent_is_valid checks fixed authority and non-persistence policy. */
raw_repository_command_intent_is_valid :: proc(intent: Raw_Repository_Command_Intent) -> bool {
	return intent.command != 0 && repository_context_is_valid(intent.repository) &&
		intent.repository_generation != 0 && intent.observation_generation != 0 &&
		raw_repository_command_input_is_valid(intent.input, intent.limits.input_bytes) &&
		intent.refresh == RAW_REPOSITORY_COMMAND_REFRESH &&
		raw_repository_command_verifier_is_valid(intent.verifier, intent.refresh) &&
		intent.authority == .Explicit_User_Confirmation &&
		intent.redaction == .Omit_Sensitive_Content &&
		intent.retention == .Session_Transient &&
		raw_repository_command_limits_are_valid(intent.limits)
}

/* raw_repository_command_confirmation_prepare snapshots one exact private intent. */
raw_repository_command_confirmation_prepare :: proc(
	intent: Raw_Repository_Command_Intent,
	id: Raw_Repository_Command_Confirmation_ID,
) -> (Raw_Repository_Command_Confirmation, bool, Raw_Repository_Command_Failure) {
	if id == 0 || !raw_repository_command_intent_is_valid(intent) {
		return {}, false, {code = .Invalid_Intent, command = intent.command}
	}
	return {id = id, intent = intent}, true, {}
}

/* raw_repository_command_confirmation_confirm accepts only the exact unused intent. */
raw_repository_command_confirmation_confirm :: proc(
	confirmation: ^Raw_Repository_Command_Confirmation,
	id: Raw_Repository_Command_Confirmation_ID,
	intent: Raw_Repository_Command_Intent,
) -> (bool, Raw_Repository_Command_Failure) {
	if confirmation == nil || confirmation.id == 0 ||
	   !raw_repository_command_intent_is_valid(confirmation.intent) {
		return false, {code = .Confirmation_Required, command = intent.command}
	}
	if confirmation.consumed {
		return false, {code = .Confirmation_Consumed, command = confirmation.intent.command}
	}
	if confirmation.confirmed || confirmation.id != id || confirmation.intent != intent {
		return false, {code = .Confirmation_Mismatch, command = confirmation.intent.command}
	}
	confirmation.confirmed = true
	return true, {}
}

/* raw_repository_command_request_prepare consumes one exact confirmation. */
raw_repository_command_request_prepare :: proc(
	operation: Repository_Operation_ID,
	intent: Raw_Repository_Command_Intent,
	confirmation: ^Raw_Repository_Command_Confirmation,
) -> (Raw_Repository_Command_Request, bool, Raw_Repository_Command_Failure) {
	if operation == 0 || !raw_repository_command_intent_is_valid(intent) || confirmation == nil ||
	   confirmation.id == 0 || confirmation.intent != intent || !confirmation.confirmed {
		return {}, false, {code = .Confirmation_Required, command = intent.command}
	}
	if confirmation.consumed {
		return {}, false, {code = .Confirmation_Consumed, command = intent.command}
	}
	confirmation.consumed = true
	return {operation = operation, intent = intent, confirmation = confirmation.id}, true, {}
}

/* raw_repository_command_request_is_valid checks one closed high-authority request. */
raw_repository_command_request_is_valid :: proc(request: Raw_Repository_Command_Request) -> bool {
	return request.operation != 0 && request.confirmation != 0 &&
		raw_repository_command_intent_is_valid(request.intent)
}

/* raw_repository_command_request_is_current checks the live repository generation. */
raw_repository_command_request_is_current :: proc(
	request: Raw_Repository_Command_Request,
	repository: Repository_Context,
	repository_generation: Repository_Generation,
) -> (bool, Raw_Repository_Command_Failure) {
	if !raw_repository_command_request_is_valid(request) {
		return false, {code = .Invalid_Request, command = request.intent.command}
	}
	if repository != request.intent.repository ||
	   repository_generation != request.intent.repository_generation {
		return false, {code = .Stale_Repository, command = request.intent.command}
	}
	return true, {}
}

/* raw_repository_command_refresh_evidence_is_valid checks a full compatible attempt. */
raw_repository_command_refresh_evidence_is_valid :: proc(
	request: Raw_Repository_Command_Request,
	evidence: Raw_Repository_Command_Refresh_Evidence,
) -> bool {
	if !raw_repository_command_request_is_valid(request) ||
	   evidence.repository != request.intent.repository ||
	   evidence.repository_generation <= request.intent.repository_generation ||
	   evidence.attempted != RAW_REPOSITORY_COMMAND_REFRESH ||
	   evidence.completed - evidence.attempted != {} {
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

/* raw_repository_command_refresh_is_complete reports exact full refresh completion. */
raw_repository_command_refresh_is_complete :: proc(
	request: Raw_Repository_Command_Request,
	evidence: Raw_Repository_Command_Refresh_Evidence,
) -> bool {
	return raw_repository_command_refresh_evidence_is_valid(request, evidence) &&
		evidence.completed == RAW_REPOSITORY_COMMAND_REFRESH
}

/* raw_repository_command_verifier_apply derives typed truth only from refreshed evidence. */
raw_repository_command_verifier_apply :: proc(
	request: Raw_Repository_Command_Request,
	evidence: Raw_Repository_Command_Refresh_Evidence,
) -> (refresh_completed, applied, agreed, valid: bool) {
	if !raw_repository_command_refresh_evidence_is_valid(request, evidence) {
		return false, false, false, false
	}
	refresh_completed = evidence.completed == RAW_REPOSITORY_COMMAND_REFRESH
	verifier := request.intent.verifier
	switch verifier.kind {
	case .None:
		return refresh_completed, false, false, true
	case .Observation_Available:
		applied = verifier.observation in evidence.attempted
		agreed = applied && verifier.observation in evidence.completed
		return refresh_completed, applied, agreed, true
	case .Target_Present, .Target_Absent:
		applied = verifier.observation in evidence.completed && evidence.target_checked
		if !applied do return refresh_completed, false, false, true
		if !raw_repository_command_targets_match(verifier.target, evidence.target) {
			return false, false, false, false
		}
		agreed = evidence.target_present == (verifier.kind == .Target_Present)
		return refresh_completed, true, agreed, true
	case .Operation_State:
		applied = verifier.observation in evidence.completed && evidence.operation_checked
		agreed = applied && evidence.operation == verifier.operation
		return refresh_completed, applied, agreed, true
	}
	return false, false, false, false
}

/* raw_repository_command_process_evidence_is_valid checks exact Process attribution. */
raw_repository_command_process_evidence_is_valid :: proc(
	evidence: Raw_Repository_Command_Process_Evidence,
	request: Raw_Repository_Command_Request,
) -> bool {
	if !evidence.started {
		return evidence.association == {} && !evidence.detached
	}
	authority := evidence.association.authority
	return authority.operation == request.operation &&
		authority.repository == request.intent.repository &&
		authority.observation_generation == request.intent.observation_generation &&
		authority.kind == .Raw_Command && evidence.association.generation != 0
}

/* raw_repository_command_cleanup_is_complete requires every transient owner to close. */
raw_repository_command_cleanup_is_complete :: proc(
	evidence: Raw_Repository_Command_Cleanup_Evidence,
) -> bool {
	return evidence.input_cleared && evidence.confirmation_cleared &&
		evidence.child_closed && evidence.association_detached
}

/* raw_repository_command_public_content_is_valid applies Process privacy policy. */
raw_repository_command_public_content_is_valid :: proc(
	content: []u8,
	limit := DEFAULT_DIAGNOSTIC_BYTES,
) -> bool {
	return u64(len(content)) <= limit && process_public_content_is_valid(content)
}

/* raw_repository_command_result_validate checks terminal evidence without retaining input. */
raw_repository_command_result_validate :: proc(
	result: Raw_Repository_Command_Result,
	request: Raw_Repository_Command_Request,
) -> Raw_Repository_Command_Failure {
	if !raw_repository_command_request_is_valid(request) || result.command != request.intent.command ||
	   result.mode != request.intent.input.mode || result.repository != request.intent.repository {
		return {code = .Invalid_Result, command = request.intent.command}
	}
	if !raw_repository_command_process_evidence_is_valid(result.process, request) {
		return {code = .Stale_Process, command = result.command}
	}
	if result.output_bytes > request.intent.limits.output_bytes {
		return {code = .Output_Limit, command = result.command,
			limit = request.intent.limits.output_bytes, actual = result.output_bytes}
	}
	if result.diagnostic_bytes > request.intent.limits.diagnostic_bytes {
		return {code = .Diagnostic_Limit, command = result.command,
			limit = request.intent.limits.diagnostic_bytes, actual = result.diagnostic_bytes}
	}
	if result.output_truncated && result.output_bytes != request.intent.limits.output_bytes {
		return {code = .Invalid_Result, command = result.command}
	}
	if result.diagnostic_omitted && result.diagnostic_bytes != 0 {
		return {code = .Invalid_Result, command = result.command}
	}
	if result.diagnostic_truncated && !result.diagnostic_omitted &&
	   result.diagnostic_bytes != request.intent.limits.diagnostic_bytes {
		return {code = .Invalid_Result, command = result.command}
	}
	if !raw_repository_command_cleanup_is_complete(result.cleanup) {
		return {code = .Cleanup_Incomplete, command = result.command}
	}
	if result.process.started && (!result.process.detached || !result.cleanup.association_detached ||
	   !result.cleanup.child_closed) {
		return {code = .Cleanup_Incomplete, command = result.command}
	}
	if !raw_repository_command_result_shape_is_valid(result, request.intent.verifier) {
		return {code = .Invalid_Result, command = result.command}
	}
	return {}
}

/* raw_repository_command_confirmation_close clears private confirmation text. */
raw_repository_command_confirmation_close :: proc(confirmation: ^Raw_Repository_Command_Confirmation) {
	if confirmation != nil do confirmation^ = {}
}

/* raw_repository_command_request_close clears private request text. */
raw_repository_command_request_close :: proc(request: ^Raw_Repository_Command_Request) {
	if request != nil do request^ = {}
}

@(private)
raw_repository_command_result_shape_is_valid :: proc(
	result: Raw_Repository_Command_Result,
	verifier: Raw_Repository_Command_Verifier,
) -> bool {
	if !result.process.started {
		return result.outcome == .Cancelled_Before_Effect && !result.effect_possible &&
			result.failure == .Cancelled && !result.exit_code_present && !result.refresh_completed &&
			!result.verifier_applied && !result.verifier_agreed &&
			result.output_bytes == 0 && result.diagnostic_bytes == 0
	}
	switch result.outcome {
	case .Verified_Success:
		return result.failure == .None && result.exit_code_present && result.exit_code == 0 &&
			result.refresh_completed &&
			verifier.kind != .None && result.verifier_applied && result.verifier_agreed
	case .Known_Failure:
		return ((result.exit_code_present && result.exit_code != 0) || result.failure != .None) &&
			!result.verifier_agreed
	case .Cancelled_Before_Effect, .Timed_Out_Before_Effect:
		return !result.effect_possible && !result.verifier_agreed &&
			(result.failure == .Cancelled || result.failure == .Timeout)
	case .Cancelled_After_Possible_Effect, .Timed_Out_After_Possible_Effect:
		return result.effect_possible && result.refresh_completed && !result.verifier_agreed &&
			(result.failure == .Cancelled || result.failure == .Timeout)
	case .Verification_Mismatch:
		return result.failure == .None && result.exit_code_present && result.exit_code == 0 &&
			result.refresh_completed &&
			verifier.kind != .None && result.verifier_applied && !result.verifier_agreed
	case .Indeterminate:
		return !result.verifier_agreed && (result.effect_possible || !result.refresh_completed ||
			!result.exit_code_present || verifier.kind == .None)
	case .None:
		return false
	}
	return false
}

@(private)
raw_repository_command_target_supports_observation :: proc(
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
raw_repository_command_targets_match :: proc(
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
