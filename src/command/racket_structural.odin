// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../bridge"
import "../hosting"
import "../language"
import editor_view "../view"
import base_runtime "base:runtime"
import endian "core:encoding/endian"

/* Racket_Structural_Result reports the final copied scope and semantic completion. */
Racket_Structural_Result :: struct {
	scope:      Structural_Capability_Scope,
	completion: Native_Completion,
	outcome:    Structural_Capability_Outcome,
}

@(private)
Racket_Structural_Call :: struct {
	structural:     Structural_Capability_Context,
	token:          u64,
	expected_scope: Structural_Capability_Scope,
	failure:        Failure_Context,
	completion:     Native_Completion,
	outcome:        Structural_Capability_Outcome,
	scenario:       i32,
}

/* racket_structural_turn runs one dynamically scoped programmable structural composition. */
racket_structural_turn :: proc(
	racket_runtime: ^hosting.Runtime,
	structural: Structural_Capability_Context,
	scenario: i32,
) -> (result: Racket_Structural_Result, ok: bool, failure: Failure_Context) {
	if racket_runtime == nil {
		return {}, false, structural_capability_failure(.Invalid_Context)
	}
	scope, scoped, scope_failure := structural_capability_scope(structural)
	if !scoped do return {}, false, scope_failure
	call := Racket_Structural_Call {
		structural = structural,
		token = structural_scope_token(scope),
		expected_scope = scope,
		completion = .No_Op,
		scenario = scenario,
	}
	executed, runtime_failure := hosting.runtime_structural_probe(
		racket_runtime,
		scenario,
		call.token,
		racket_structural_callback,
		&call,
	)
	if !executed do return {}, false, hosting_failure_context({}, runtime_failure)
	if call.failure.code != .None do return {}, false, call.failure
	return Racket_Structural_Result {
		scope = call.expected_scope,
		completion = call.completion,
		outcome = call.outcome,
	}, true, {}
}

@(private)
racket_structural_callback :: proc "c" (
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
	call := (^Racket_Structural_Call)(user_data)
	if call == nil || kind != .Structural || generation == 0 || domain_context != 0 ||
	   token != call.token || arg0 != 0 || arg1 != 0 || output_length == nil ||
	   value == nil || failure_code == nil || limit == nil || actual == nil ||
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
		if output == nil do return 2
		destination = ([^]u8)(output)[:int(output_capacity)]
	}

	switch bridge.Structural_Capability_Operation(operation) {
	case .Scope:
		if input_length != 0 || output_capacity != bridge.STRUCTURAL_SCOPE_RECORD_BYTES {
			return 2
		}
		if call.scenario == 20 {
			call.expected_scope.capability_generation += 1
		}
		structural_encode_scope(destination, call.expected_scope)
		output_length^ = bridge.STRUCTURAL_SCOPE_RECORD_BYTES
		return 0
	case .Inspect:
		if input == nil || input_length != bridge.STRUCTURAL_SCOPE_RECORD_BYTES ||
		   output_capacity > bridge.MAX_STRUCTURAL_INSPECTION_BYTES ||
		   output_capacity < bridge.STRUCTURAL_SCOPE_RECORD_BYTES {
			return 2
		}
		input_bytes := ([^]u8)(input)[:int(input_length)]
		if !structural_scope_bytes_match(input_bytes, call.expected_scope) do return 2
		inspection, inspected, failure := structural_capability_inspect(
			call.structural,
			call.expected_scope,
		)
		if !inspected {
			return racket_structural_reject(call, .Invalid, failure, failure_code, limit, actual)
		}
		kind_bytes := u64(0)
		if language.structural_scope_is_valid(inspection.target.scope) &&
		   inspection.target.kind.length > 0 &&
		   inspection.target.kind.length <= language.MAX_STRUCTURAL_NODE_KIND_BYTES {
			kind_bytes = u64(inspection.target.kind.length)
		}
		message_bytes := u64(len(inspection.diagnostic))
		required, admitted := bridge.structural_inspection_record_bytes(
			0,
			kind_bytes,
			message_bytes,
		)
		if !admitted || required > output_capacity do return 2
		structural_encode_inspection(destination[:int(required)], inspection, kind_bytes)
		call.expected_scope = inspection.scope
		output_length^ = required
		return 0
	case .Forward, .Backward, .Up, .Down, .Select, .Indent, .Definition:
		if input == nil || input_length != bridge.STRUCTURAL_REQUEST_RECORD_BYTES ||
		   output_capacity != bridge.STRUCTURAL_OUTCOME_RECORD_BYTES {
			return 2
		}
		input_bytes := ([^]u8)(input)[:int(input_length)]
		if !structural_scope_bytes_match(
			input_bytes[:int(bridge.STRUCTURAL_SCOPE_RECORD_BYTES)],
			call.expected_scope,
		) {
			return 2
		}
		requested_operation, request_ok := structural_decode_request_operation(input_bytes)
		if !request_ok || requested_operation != operation do return 2
		semantic_operation, mapped := structural_semantic_operation(
			bridge.Structural_Capability_Operation(operation),
		)
		if !mapped || !structural_request_selection_matches(call, input_bytes) do return 2
		result, invoked, failure := structural_capability_invoke(
			call.structural,
			call.expected_scope,
			semantic_operation,
		)
		if !invoked {
			return racket_structural_reject(
				call,
				semantic_operation,
				failure,
				failure_code,
				limit,
				actual,
			)
		}
		structural_encode_outcome(destination, result.outcome)
		call.expected_scope = result.outcome.scope
		call.completion = result.outcome.completion
		call.outcome = result.outcome
		output_length^ = bridge.STRUCTURAL_OUTCOME_RECORD_BYTES
		value^ = u64(result.outcome.completion)
		structural_capability_result_close(&result)
		return 0
	}
	return 2
}

@(private)
structural_request_selection_matches :: proc(
	call: ^Racket_Structural_Call,
	bytes: []u8,
) -> bool {
	logical, ok, _ := editor_view.snapshot(
		call.structural.editor.native.view_registry,
		call.structural.editor.native.view,
	)
	if !ok do return false
	base := int(bridge.STRUCTURAL_SCOPE_RECORD_BYTES)
	point, point_ok := endian.get_u64(bytes[base + 8:], .Little)
	start, start_ok := endian.get_u64(bytes[base + 16:], .Little)
	end, end_ok := endian.get_u64(bytes[base + 24:], .Little)
	has_region, region_ok := endian.get_u64(bytes[base + 32:], .Little)
	if !point_ok || !start_ok || !end_ok || !region_ok || has_region > 1 ||
	   point != u64(logical.point_position.byte_offset) {
		return false
	}
	expected_start := point
	expected_end := point
	expected_region := u64(0)
	if logical.region_active && logical.mark.present {
		mark := u64(logical.mark.position.byte_offset)
		expected_start = min(point, mark)
		expected_end = max(point, mark)
		expected_region = 1
	}
	return start == expected_start && end == expected_end && has_region == expected_region
}

@(private)
structural_decode_request_operation :: proc(bytes: []u8) -> (i32, bool) {
	if u64(len(bytes)) != bridge.STRUCTURAL_REQUEST_RECORD_BYTES do return 0, false
	operation, ok := endian.get_u64(bytes[int(bridge.STRUCTURAL_SCOPE_RECORD_BYTES):], .Little)
	if !ok || operation > u64(max(i32)) do return 0, false
	return i32(operation), true
}

@(private)
structural_semantic_operation :: proc(
	operation: bridge.Structural_Capability_Operation,
) -> (language.Structural_Operation, bool) {
	switch operation {
	case .Forward: return .Forward, true
	case .Backward: return .Backward, true
	case .Up: return .Up, true
	case .Down: return .Down, true
	case .Select: return .Select, true
	case .Indent: return .Indent, true
	case .Definition: return .Definition, true
	case .Scope, .Inspect: return .Invalid, false
	}
	unreachable()
}

@(private)
structural_encode_scope :: proc(destination: []u8, scope: Structural_Capability_Scope) {
	assert(u64(len(destination)) >= bridge.STRUCTURAL_SCOPE_RECORD_BYTES)
	offset := 0
	structural_put(destination, &offset, bridge.STRUCTURAL_CAPABILITY_SCHEMA_VERSION)
	structural_put(destination, &offset, u64(transmute(u16)scope.access))
	structural_put(destination, &offset, u64(scope.editor_session_id))
	structural_put(destination, &offset, u64(scope.editor.view.registry_id))
	structural_put(destination, &offset, u64(scope.editor.view.view_id))
	structural_put(destination, &offset, u64(scope.editor.view.generation))
	structural_put(destination, &offset, scope.editor.view_state_generation)
	structural_put(destination, &offset, u64(scope.editor.buffer_id))
	structural_put(destination, &offset, u64(scope.editor.revision))
	structural_put(destination, &offset, scope.editor.selection_generation)
	structural_put(destination, &offset, u64(scope.editor.analysis.language.id))
	structural_put(destination, &offset, u64(scope.editor.analysis.language.generation))
	structural_put(destination, &offset, u64(scope.editor.analysis.provider.registry_id))
	structural_put(destination, &offset, u64(scope.editor.analysis.provider.language_id))
	structural_put(destination, &offset, u64(scope.editor.analysis.provider.provider_id))
	structural_put(destination, &offset, u64(scope.editor.analysis.provider.provider_generation))
	structural_put(destination, &offset, u64(scope.editor.analysis.parser_generation))
	structural_put(destination, &offset, u64(scope.editor.analysis.tree_generation))
	structural_put(destination, &offset, u64(scope.command_registry_generation))
	structural_put(destination, &offset, scope.capability_generation)
	assert(offset == int(bridge.STRUCTURAL_SCOPE_RECORD_BYTES))
}

@(private)
structural_scope_bytes_match :: proc(bytes: []u8, scope: Structural_Capability_Scope) -> bool {
	if u64(len(bytes)) != bridge.STRUCTURAL_SCOPE_RECORD_BYTES do return false
	expected: [bridge.STRUCTURAL_SCOPE_RECORD_BYTES]u8
	structural_encode_scope(expected[:], scope)
	for byte, index in bytes {
		if byte != expected[index] do return false
	}
	return true
}

@(private)
structural_encode_inspection :: proc(
	destination: []u8,
	inspection: Structural_Capability_Inspection,
	kind_bytes: u64,
) {
	structural_encode_scope(destination, inspection.scope)
	target_offset := int(bridge.STRUCTURAL_SCOPE_RECORD_BYTES)
	structural_encode_scope(destination[target_offset:], inspection.scope)
	offset := target_offset + int(bridge.STRUCTURAL_SCOPE_RECORD_BYTES)
	present := kind_bytes > 0
	structural_put(destination, &offset, u64(present))
	structural_put(destination, &offset, u64(inspection.target.start))
	structural_put(destination, &offset, u64(inspection.target.end))
	fixed_bytes := u64(len(destination)) - kind_bytes - u64(len(inspection.diagnostic))
	structural_put(destination, &offset, fixed_bytes)
	structural_put(destination, &offset, kind_bytes)
	structural_put(destination, &offset, u64(inspection.target.depth))
	assert(offset == target_offset + int(bridge.STRUCTURAL_TARGET_RECORD_BYTES))

	plan_offset := offset
	structural_encode_scope(destination[plan_offset:], inspection.scope)
	offset = plan_offset + int(bridge.STRUCTURAL_SCOPE_RECORD_BYTES)
	structural_put(destination, &offset, inspection.plan_start)
	structural_put(destination, &offset, inspection.plan_end)
	structural_put(destination, &offset, 0)
	structural_encode_usage(destination, &offset, inspection.usage)
	assert(offset == plan_offset + int(bridge.STRUCTURAL_PLAN_RECORD_BYTES))

	structural_encode_outcome(destination[offset:], inspection.outcome)
	offset += int(bridge.STRUCTURAL_OUTCOME_RECORD_BYTES)
	structural_encode_usage(destination, &offset, inspection.usage)
	structural_encode_diagnostic(
		destination,
		&offset,
		inspection,
		fixed_bytes + kind_bytes,
	)
	assert(u64(offset) == fixed_bytes)
	if kind_bytes > 0 {
		kind := inspection.target.kind
		copy(
			destination[offset:offset + int(kind_bytes)],
			kind.bytes[:int(kind_bytes)],
		)
		offset += int(kind_bytes)
	}
	copy(destination[offset:], transmute([]u8)inspection.diagnostic)
	offset += len(inspection.diagnostic)
	assert(offset == len(destination))
}

@(private)
structural_encode_outcome :: proc(destination: []u8, outcome: Structural_Capability_Outcome) {
	assert(u64(len(destination)) >= bridge.STRUCTURAL_OUTCOME_RECORD_BYTES)
	structural_encode_scope(destination, outcome.scope)
	offset := int(bridge.STRUCTURAL_SCOPE_RECORD_BYTES)
	structural_put(destination, &offset, u64(outcome.operation))
	structural_put(destination, &offset, u64(outcome.completion))
	structural_put(destination, &offset, u64(outcome.changed))
	structural_put(destination, &offset, outcome.point)
	structural_put(destination, &offset, outcome.mark)
	structural_put(destination, &offset, u64(outcome.region_active))
	structural_put(destination, &offset, outcome.transaction_id)
	structural_put(destination, &offset, outcome.undo_unit_id)
	structural_encode_usage(destination, &offset, outcome.usage)
	assert(offset == int(bridge.STRUCTURAL_OUTCOME_RECORD_BYTES))
}

@(private)
structural_encode_usage :: proc(
	destination: []u8,
	offset: ^int,
	usage: language.Structural_Usage,
) {
	structural_put(destination, offset, u64(usage.visited_nodes))
	structural_put(destination, offset, u64(usage.visited_depth))
	structural_put(destination, offset, u64(usage.indent_lines))
	structural_put(destination, offset, usage.prepared_bytes)
	structural_put(destination, offset, usage.temporary_bytes)
}

@(private)
structural_encode_diagnostic :: proc(
	destination: []u8,
	offset: ^int,
	inspection: Structural_Capability_Inspection,
	message_offset: u64,
) {
	failure := inspection.failure
	structural_put(destination, offset, u64(inspection.outcome.operation))
	structural_put(destination, offset, u64(failure.code))
	structural_put(destination, offset, u64(failure.structural_code))
	structural_put(destination, offset, u64(failure.language_code))
	structural_put(destination, offset, u64(inspection.scope.editor.buffer_id))
	structural_put(destination, offset, u64(inspection.scope.editor.view.view_id))
	structural_put(destination, offset, u64(inspection.scope.editor.revision))
	structural_put(destination, offset, u64(failure.revision))
	structural_put(destination, offset, u64(inspection.scope.editor.analysis.tree_generation))
	structural_put(destination, offset, failure.actual)
	structural_put(destination, offset, failure.limit)
	structural_put(destination, offset, failure.actual)
	structural_put(destination, offset, message_offset)
	structural_put(destination, offset, u64(len(inspection.diagnostic)))
}

@(private)
structural_put :: proc(destination: []u8, offset: ^int, value: u64) {
	assert(offset != nil && offset^ >= 0 && offset^ + 8 <= len(destination))
	written := endian.put_u64(destination[offset^:], .Little, value)
	assert(written)
	offset^ += 8
}

@(private)
racket_structural_reject :: proc(
	call: ^Racket_Structural_Call,
	operation: language.Structural_Operation,
	failure: Failure_Context,
	failure_code: ^u32,
	limit, actual: ^u64,
) -> i32 {
	call.failure = failure
	structural_capability_record_failure(call.structural.state, operation, failure)
	code := u32(failure.structural_capability_code)
	if code == 0 do code = 768 + u32(failure.code)
	failure_code^ = code
	limit^ = failure.limit
	actual^ = failure.actual
	return 1
}

@(private)
structural_scope_token :: proc(scope: Structural_Capability_Scope) -> u64 {
	token := u64(scope.editor_session_id) ~ (u64(scope.editor.view.view_id) << 1) ~
	         (scope.editor.view_state_generation << 7) ~
	         (u64(scope.editor.analysis.tree_generation) << 13) ~
	         (scope.capability_generation << 19)
	if token == 0 do return 1
	return token
}
