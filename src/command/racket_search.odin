// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../bridge"
import "../editor"
import "../hosting"
import "../search"
import editor_view "../view"
import base_runtime "base:runtime"
import endian "core:encoding/endian"
import "core:unicode/utf8"

/* Racket_Search_Result reports the final copied scope and semantic completion. */
Racket_Search_Result :: struct {
	scope:      Search_Capability_Scope,
	policy:     Search_Capability_Policy,
	completion: Native_Completion,
}

@(private)
Racket_Search_Call :: struct {
	search_control: Search_Capability_Context,
	token:          u64,
	expected_scope: Search_Capability_Scope,
	failure:        Failure_Context,
	completion:     Native_Completion,
}

/* racket_search_turn runs one dynamically scoped programmable search composition. */
racket_search_turn :: proc(
	racket_runtime: ^hosting.Runtime,
	search_control: Search_Capability_Context,
	scenario: i32,
) -> (result: Racket_Search_Result, ok: bool, failure: Failure_Context) {
	if racket_runtime == nil {
		return {}, false, search_capability_failure(.Invalid_Context)
	}
	scope, scoped, scope_failure := search_capability_scope(search_control)
	if !scoped {
		return {}, false, scope_failure
	}
	token := search_scope_token(scope)
	call := Racket_Search_Call {
		search_control = search_control,
		token = token,
		expected_scope = scope,
		completion = .No_Op,
	}
	executed, runtime_failure := hosting.runtime_search_probe(
		racket_runtime,
		scenario,
		token,
		racket_search_callback,
		&call,
	)
	if !executed {
		return {}, false, hosting_failure_context({}, runtime_failure)
	}
	if call.failure.code != .None {
		return {}, false, call.failure
	}
	return Racket_Search_Result {
		scope = call.expected_scope,
		policy = call.search_control.policy,
		completion = call.completion,
	}, true, {}
}

@(private)
racket_search_callback :: proc "c" (
	user_data: rawptr,
	kind: hosting.Scoped_Capability_Kind,
	generation, token, domain_context: u64,
	operation: i32,
	arg0, arg1: u64,
	input: ^u8,
	input_length: u64,
	output: ^u8,
	output_capacity: u64,
	output_length, value: ^u64,
	failure_code: ^u32,
	limit, actual: ^u64,
) -> i32 {
	context = base_runtime.default_context()
	call := (^Racket_Search_Call)(user_data)
	if call == nil || kind != .Search || generation == 0 || domain_context != 0 ||
	   token != call.token || output_length == nil || value == nil ||
	   failure_code == nil || limit == nil || actual == nil ||
	   input_length > u64(max(int)) || output_capacity > u64(max(int)) {
		return 2
	}
	output_length^ = 0
	value^ = 0
	failure_code^ = 0
	limit^ = 0
	actual^ = 0
	destination: []u8
	if output_capacity > 0 {
		if output == nil {
			return 2
		}
		destination = ([^]u8)(output)[:int(output_capacity)]
	}

	switch bridge.Search_Operation(operation) {
	case .Scope:
		if input_length != 0 || output_capacity != bridge.SEARCH_SCOPE_RECORD_BYTES {
			return 2
		}
		search_encode_scope(destination, call.expected_scope)
		output_length^ = bridge.SEARCH_SCOPE_RECORD_BYTES
		return 0
	case .Policy:
		if input_length != 0 || output_capacity != bridge.SEARCH_POLICY_RECORD_BYTES {
			return 2
		}
		policy, inspected, failure := search_policy_inspect(
			call.search_control,
			call.expected_scope,
		)
		if !inspected {
			return racket_search_reject(call, failure, failure_code, limit, actual)
		}
		search_encode_policy(destination, policy)
		output_length^ = bridge.SEARCH_POLICY_RECORD_BYTES
		return 0
	case .Session:
		if input == nil || input_length != 8 ||
		   arg0 == 0 || arg0 > bridge.MAX_SEARCH_INSPECTION_OCCURRENCES ||
		   arg1 == 0 || arg1 > bridge.MAX_SEARCH_INSPECTION_CAPTURES {
			return 2
		}
		input_bytes := ([^]u8)(input)[:8]
		text_bytes, text_ok := endian.get_u64(input_bytes, .Little)
		if !text_ok || text_bytes > bridge.MAX_SEARCH_INSPECTION_TEXT_BYTES {
			return 2
		}
		maximum_bytes, admitted := bridge.search_session_record_bytes(arg0, arg1, text_bytes)
		if !admitted || output_capacity != maximum_bytes {
			return 2
		}
		copied, copied_ok, failure := search_session_inspect(
			call.search_control,
			Search_Session_Copy_Request {
				expected_scope = call.expected_scope,
				occurrence_limit = u32(arg0),
				capture_limit = u32(arg1),
				text_bytes_limit = text_bytes,
			},
		)
		if !copied_ok {
			return racket_search_reject(call, failure, failure_code, limit, actual)
		}
		defer search_session_copy_close(&copied)
		required, required_ok := bridge.search_session_record_bytes(
			u64(len(copied.occurrences)),
			u64(len(copied.captures)),
			u64(len(copied.pattern) + len(copied.last_successful_pattern) + len(copied.replacement)),
		)
		if !required_ok || required > output_capacity {
			return 2
		}
		search_encode_session(destination[:int(required)], copied)
		output_length^ = required
		return 0
	case .Invoke:
		if input == nil || output_capacity != bridge.SEARCH_COMMAND_RESULT_RECORD_BYTES ||
		   input_length < bridge.SEARCH_COMMAND_REQUEST_HEADER_BYTES {
			return 2
		}
		request_bytes := ([^]u8)(input)[:int(input_length)]
		request, request_ok := search_decode_command_request(request_bytes)
		if !request_ok {
			return 2
		}
		request.expected_scope = call.expected_scope
		request.policy.generation = call.expected_scope.policy_generation
		cancellation: search.Cancellation
		if search_request_cancelled(request_bytes) {
			cancellation = search.Cancellation {
				generation = request.search_generation,
				requested = true,
			}
			request.cancellation = &cancellation
		}
		result, invoked, failure := search_command_invoke(call.search_control, request)
		if !invoked {
			return racket_search_reject(call, failure, failure_code, limit, actual)
		}
		call.expected_scope = result.result_scope
		call.search_control.policy = request.policy
		call.completion = result.completion
		search_encode_command_result(destination, result)
		output_length^ = bridge.SEARCH_COMMAND_RESULT_RECORD_BYTES
		value^ = u64(result.completion)
		return 0
	}
	return 2
}

@(private)
search_decode_command_request :: proc(bytes: []u8) -> (Search_Command_Request, bool) {
	if u64(len(bytes)) < bridge.SEARCH_COMMAND_REQUEST_HEADER_BYTES {
		return {}, false
	}
	values: [33]u64
	for index in 0 ..< 33 {
		value, ok := endian.get_u64(bytes[index * 8:], .Little)
		if !ok {
			return {}, false
		}
		values[index] = value
	}
	if values[10] > 1 || values[17] > 1 || values[21] > u64(max(u32)) ||
	   values[23] > u64(max(u16)) {
		return {}, false
	}
	required, admitted := bridge.search_command_request_bytes(values[11], values[12], values[13])
	if !admitted || required != u64(len(bytes)) {
		return {}, false
	}
	command_start := int(bridge.SEARCH_COMMAND_REQUEST_HEADER_BYTES)
	pattern_start := command_start + int(values[11])
	replacement_start := pattern_start + int(values[12])
	command_bytes := bytes[command_start:pattern_start]
	pattern_bytes := bytes[pattern_start:replacement_start]
	replacement_bytes := bytes[replacement_start:]
	if !utf8.valid_string(string(command_bytes)) || !utf8.valid_string(string(pattern_bytes)) ||
	   !utf8.valid_string(string(replacement_bytes)) {
		return {}, false
	}
	return Search_Command_Request {
		name = string(command_bytes),
		pattern = string(pattern_bytes),
		replacement = string(replacement_bytes),
		direction = search.Direction(values[0]),
		incremental_turn = Incremental_Search_Turn(values[1]),
		query_action = Query_Replacement_Action(values[2]),
		query_id = search.Query_ID(values[3]),
		search_generation = search.Search_Generation(values[4]),
		semantic_group = editor_view.Query_Replacement_Group_ID(values[5]),
		scope = search.Scope {
			buffer_id = editor.Buffer_ID(values[6]),
			revision = editor.Revision(values[7]),
			start = editor.Byte_Offset(values[8]),
			end = editor.Byte_Offset(values[9]),
		},
		policy = Search_Capability_Policy {
			generation = search.Policy_Generation(0),
			search_policy = search.Policy {
				case_mode = search.Case_Mode(values[14]),
				boundary_mode = search.Boundary_Mode(values[15]),
				whitespace_mode = search.Whitespace_Mode(values[16]),
				wrap = values[17] == 1,
			},
			search_limits = search.Limits {
				pattern_bytes = values[18],
				scan_window_bytes = values[19],
				cancellation_bytes = values[20],
				retained_occurrences = u32(values[21]),
				temporary_bytes = values[22],
				capture_groups = u16(values[23]),
				match_span_bytes = values[24],
			},
			replacement_policy = search.Replacement_Policy {
				case_preservation = search.Case_Preservation(values[25]),
			},
			replacement_limits = search.Replacement_Limits {
				template_bytes = values[26],
				expanded_bytes = values[27],
				temporary_bytes = values[28],
			},
			replace_all_limits = Replace_All_Limits {
				matches = values[29],
				text_bytes = values[30],
				temporary_bytes = values[31],
				analysis_bytes = values[32],
			},
		},
	}, true
}

@(private)
search_request_cancelled :: proc(bytes: []u8) -> bool {
	value, ok := endian.get_u64(bytes[80:], .Little)
	return ok && value == 1
}

@(private)
search_encode_scope :: proc(destination: []u8, scope: Search_Capability_Scope) {
	assert(u64(len(destination)) >= bridge.SEARCH_SCOPE_RECORD_BYTES)
	offset := 0
	search_put(destination, &offset, u64(scope.editor_session_id))
	search_put(destination, &offset, u64(transmute(u8)scope.access))
	search_put(destination, &offset, u64(scope.view.registry_id))
	search_put(destination, &offset, u64(scope.view.view_id))
	search_put(destination, &offset, u64(scope.view.generation))
	search_put(destination, &offset, scope.view_state_generation)
	search_put(destination, &offset, u64(scope.buffer_id))
	search_put(destination, &offset, u64(scope.revision))
	search_put(destination, &offset, u64(scope.command_registry_generation))
	search_put(destination, &offset, u64(scope.session_kind))
	search_put(destination, &offset, scope.interaction_generation)
	search_put(destination, &offset, u64(scope.policy_generation))
	assert(offset == int(bridge.SEARCH_SCOPE_RECORD_BYTES))
}

@(private)
search_encode_policy :: proc(destination: []u8, summary: Search_Policy_Summary) {
	assert(u64(len(destination)) >= bridge.SEARCH_POLICY_RECORD_BYTES)
	search_encode_scope(destination, summary.scope)
	offset := int(bridge.SEARCH_SCOPE_RECORD_BYTES)
	policy := summary.policy
	search_put(destination, &offset, u64(policy.search_policy.case_mode))
	search_put(destination, &offset, u64(policy.search_policy.boundary_mode))
	search_put(destination, &offset, u64(policy.search_policy.whitespace_mode))
	search_put(destination, &offset, u64(policy.search_policy.wrap))
	search_put_search_limits(destination, &offset, policy.search_limits)
	search_put(destination, &offset, u64(policy.replacement_policy.case_preservation))
	search_put_replacement_limits(destination, &offset, policy.replacement_limits)
	search_put(destination, &offset, policy.replace_all_limits.matches)
	search_put(destination, &offset, policy.replace_all_limits.text_bytes)
	search_put(destination, &offset, policy.replace_all_limits.temporary_bytes)
	search_put(destination, &offset, policy.replace_all_limits.analysis_bytes)
	assert(offset == int(bridge.SEARCH_POLICY_RECORD_BYTES))
}

@(private)
search_encode_session :: proc(destination: []u8, copied: Search_Session_Copy) {
	assert(u64(len(destination)) >= bridge.SEARCH_SESSION_HEADER_BYTES)
	search_encode_scope(destination, copied.scope)
	offset := int(bridge.SEARCH_SCOPE_RECORD_BYTES)
	search_put(destination, &offset, u64(copied.present))
	search_put(destination, &offset, u64(copied.kind))
	search_put(destination, &offset, u64(copied.direction))
	search_put(destination, &offset, u64(copied.pattern_kind))
	search_put(destination, &offset, u64(copied.search_scope.buffer_id))
	search_put(destination, &offset, u64(copied.search_scope.revision))
	search_put(destination, &offset, u64(copied.search_scope.start))
	search_put(destination, &offset, u64(copied.search_scope.end))
	search_put(destination, &offset, u64(copied.search_status))
	search_put(destination, &offset, u64(copied.query_status))
	search_put(destination, &offset, u64(copied.last_response))
	search_put(destination, &offset, u64(copied.semantic_group))
	search_put(destination, &offset, u64(len(copied.pattern)))
	search_put(destination, &offset, u64(len(copied.last_successful_pattern)))
	search_put(destination, &offset, u64(len(copied.replacement)))
	search_put(destination, &offset, u64(copied.search_policy.case_mode))
	search_put(destination, &offset, u64(copied.search_policy.boundary_mode))
	search_put(destination, &offset, u64(copied.search_policy.whitespace_mode))
	search_put(destination, &offset, u64(copied.search_policy.wrap))
	search_put_search_limits(destination, &offset, copied.search_limits)
	search_put(destination, &offset, u64(copied.replacement_policy.case_preservation))
	search_put_replacement_limits(destination, &offset, copied.replacement_limits)
	search_put(destination, &offset, u64(copied.effective_case))
	search_put(destination, &offset, u64(copied.source_revision))
	search_put(destination, &offset, u64(copied.observed_revision))
	search_put(destination, &offset, copied.source_text_bytes)
	search_put(destination, &offset, copied.observed_text_bytes)
	search_put(destination, &offset, copied.replacements)
	search_put(destination, &offset, copied.skips)
	search_put(destination, &offset, copied.recomputations)
	search_put(destination, &offset, u64(copied.has_current))
	search_put(destination, &offset, u64(copied.current_index))
	search_put_occurrence(destination, &offset, copied.current)
	search_put(destination, &offset, u64(copied.progress.next_offset))
	search_put(destination, &offset, u64(copied.progress.wrapped))
	search_put(destination, &offset, u64(copied.progress.complete))
	search_put(destination, &offset, copied.usage.logical_bytes)
	search_put(destination, &offset, copied.usage.read_bytes)
	search_put(destination, &offset, copied.usage.scan_turns)
	search_put(destination, &offset, copied.usage.cancellation_checks)
	search_put(destination, &offset, u64(copied.usage.retained_occurrences))
	search_put(destination, &offset, u64(copied.usage.retained_captures))
	search_put(destination, &offset, copied.usage.temporary_peak_bytes)
	search_put(destination, &offset, u64(len(copied.occurrences)))
	search_put(destination, &offset, u64(len(copied.captures)))
	text_bytes := len(copied.pattern) + len(copied.last_successful_pattern) + len(copied.replacement)
	search_put(destination, &offset, u64(text_bytes))
	assert(offset == int(bridge.SEARCH_SESSION_HEADER_BYTES))
	for occurrence in copied.occurrences {
		search_put_occurrence(destination, &offset, occurrence)
	}
	for capture in copied.captures {
		search_put(destination, &offset, u64(capture.group))
		search_put(destination, &offset, u64(capture.start))
		search_put(destination, &offset, u64(capture.end))
	}
	copy(destination[offset:], copied.pattern)
	offset += len(copied.pattern)
	copy(destination[offset:], copied.last_successful_pattern)
	offset += len(copied.last_successful_pattern)
	copy(destination[offset:], copied.replacement)
	offset += len(copied.replacement)
	assert(offset == len(destination))
}

@(private)
search_encode_command_result :: proc(destination: []u8, result: Search_Command_Result) {
	assert(u64(len(destination)) >= bridge.SEARCH_COMMAND_RESULT_RECORD_BYTES)
	search_encode_scope(destination, result.result_scope)
	offset := int(bridge.SEARCH_SCOPE_RECORD_BYTES)
	search_put(destination, &offset, u64(result.completion))
	search_put(destination, &offset, u64(result.changed))
	search_put(destination, &offset, u64(result.query_status))
	search_put(destination, &offset, result.replacements)
	search_put(destination, &offset, result.skips)
	search_put(destination, &offset, u64(result.finished))
	search_put(destination, &offset, result.replacement_usage.source_bytes)
	search_put(destination, &offset, result.replacement_usage.expanded_bytes)
	search_put(destination, &offset, result.replacement_usage.temporary_peak_bytes)
	search_put(destination, &offset, result.replace_all_usage.matches)
	search_put(destination, &offset, result.replace_all_usage.captures)
	search_put(destination, &offset, result.replace_all_usage.analysis_bytes)
	search_put(destination, &offset, result.replace_all_usage.source_read_bytes)
	search_put(destination, &offset, result.replace_all_usage.removed_bytes)
	search_put(destination, &offset, result.replace_all_usage.expanded_bytes)
	search_put(destination, &offset, result.replace_all_usage.transaction_bytes)
	search_put(destination, &offset, result.replace_all_usage.search_turns)
	search_put(destination, &offset, result.replace_all_usage.cancellation_checks)
	search_put(destination, &offset, u64(result.continuation_code))
	search_put(destination, &offset, u64(result.continuation_search_code))
	assert(offset == int(bridge.SEARCH_COMMAND_RESULT_RECORD_BYTES))
}

@(private)
search_put_search_limits :: proc(destination: []u8, offset: ^int, limits: search.Limits) {
	search_put(destination, offset, limits.pattern_bytes)
	search_put(destination, offset, limits.scan_window_bytes)
	search_put(destination, offset, limits.cancellation_bytes)
	search_put(destination, offset, u64(limits.retained_occurrences))
	search_put(destination, offset, limits.temporary_bytes)
	search_put(destination, offset, u64(limits.capture_groups))
	search_put(destination, offset, limits.match_span_bytes)
}

@(private)
search_put_replacement_limits :: proc(
	destination: []u8,
	offset: ^int,
	limits: search.Replacement_Limits,
) {
	search_put(destination, offset, limits.template_bytes)
	search_put(destination, offset, limits.expanded_bytes)
	search_put(destination, offset, limits.temporary_bytes)
}

@(private)
search_put_occurrence :: proc(
	destination: []u8,
	offset: ^int,
	occurrence: search.Occurrence,
) {
	search_put(destination, offset, u64(occurrence.buffer_id))
	search_put(destination, offset, u64(occurrence.revision))
	search_put(destination, offset, u64(occurrence.start))
	search_put(destination, offset, u64(occurrence.end))
	search_put(destination, offset, u64(occurrence.first_capture))
	search_put(destination, offset, u64(occurrence.capture_count))
}

@(private)
search_put :: proc(destination: []u8, offset: ^int, value: u64) {
	assert(offset != nil && offset^ >= 0 && offset^ + 8 <= len(destination))
	written := endian.put_u64(destination[offset^:], .Little, value)
	assert(written)
	offset^ += 8
}

@(private)
racket_search_reject :: proc(
	call: ^Racket_Search_Call,
	failure: Failure_Context,
	failure_code: ^u32,
	limit, actual: ^u64,
) -> i32 {
	call.failure = failure
	code := u32(failure.search_capability_code)
	if code == 0 {
		code = 512 + u32(failure.code)
	}
	failure_code^ = code
	limit^ = failure.limit
	actual^ = failure.actual
	return 1
}

@(private)
search_scope_token :: proc(scope: Search_Capability_Scope) -> u64 {
	token := u64(scope.editor_session_id) ~ (u64(scope.view.view_id) << 1) ~
	         (scope.view_state_generation << 7) ~ (scope.interaction_generation << 13) ~
	         (u64(scope.policy_generation) << 19)
	if token == 0 {
		return 1
	}
	return token
}
