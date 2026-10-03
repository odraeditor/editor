// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../bridge"
import "../hosting"
import "../kill_ring"
import base_runtime "base:runtime"
import endian "core:encoding/endian"
import "core:unicode/utf8"

@(private)
RACKET_TRANSFER_COMMAND_BYTES :: u64(96)

/* Racket_Transfer_Result reports the final copied scope and semantic completion. */
Racket_Transfer_Result :: struct {
	scope:      Transfer_Capability_Scope,
	completion: Native_Completion,
}

@(private)
Racket_Transfer_Call :: struct {
	transfer:       Transfer_Capability_Context,
	token:          u64,
	expected_scope: Transfer_Capability_Scope,
	failure:       Failure_Context,
	completion:    Native_Completion,
}

/* racket_transfer_turn runs one dynamically scoped programmable transfer composition. */
racket_transfer_turn :: proc(
	racket_runtime: ^hosting.Runtime,
	transfer: Transfer_Capability_Context,
	scenario: i32,
) -> (result: Racket_Transfer_Result, ok: bool, failure: Failure_Context) {
	if racket_runtime == nil {
		return {}, false, transfer_failure(.Invalid_Context)
	}
	scope, scoped, scope_failure := transfer_capability_scope(transfer)
	if !scoped {
		return {}, false, scope_failure
	}
	token := transfer_scope_token(scope)
	call := Racket_Transfer_Call {
		transfer = transfer,
		token = token,
		expected_scope = scope,
		completion = .No_Op,
	}
	executed, runtime_failure := hosting.runtime_transfer_probe(
		racket_runtime,
		scenario,
		token,
		racket_transfer_callback,
		&call,
	)
	if !executed {
		return {}, false, hosting_failure_context({}, runtime_failure)
	}
	if call.failure.code != .None {
		return {}, false, call.failure
	}
	return Racket_Transfer_Result {
		scope = call.expected_scope,
		completion = call.completion,
	}, true, {}
}

@(private)
racket_transfer_callback :: proc "c" (
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
	call := (^Racket_Transfer_Call)(user_data)
	if call == nil || kind != .Transfer || generation == 0 || domain_context != 0 ||
	   token != call.token ||
	   output_length == nil || value == nil || failure_code == nil ||
	   limit == nil || actual == nil || output_capacity > u64(max(int)) ||
	   input_length > u64(max(int)) {
		return 2
	}
	output_length^ = 0
	value^ = 0
	failure_code^ = 0
	limit^ = 0
	actual^ = 0
	destination: []u8
	if output_capacity != 0 {
		if output == nil {
			return 2
		}
		destination = ([^]u8)(output)[:int(output_capacity)]
	}

	switch bridge.Transfer_Operation(operation) {
	case .Scope:
		if output_capacity != bridge.TRANSFER_SCOPE_RECORD_BYTES {
			return 2
		}
		transfer_encode_scope(destination, call.expected_scope)
		output_length^ = bridge.TRANSFER_SCOPE_RECORD_BYTES
		return 0
	case .Region:
		if output_capacity != bridge.TRANSFER_REGION_RECORD_BYTES {
			return 2
		}
		summary, inspected, failure := transfer_region_inspect(
			call.transfer,
			call.expected_scope,
		)
		if !inspected {
			return racket_transfer_reject(call, failure, failure_code, limit, actual)
		}
		transfer_encode_scope(destination, summary.scope)
		transfer_put_u64(destination, 88, u64(summary.point.byte_offset))
		transfer_put_u64(destination, 96, u64(summary.mark.byte_offset))
		transfer_put_u64(destination, 104, u64(summary.region_start))
		transfer_put_u64(destination, 112, u64(summary.region_end))
		flags: u64
		if summary.mark_present do flags |= 1
		if summary.region_active do flags |= 2
		if summary.region_present do flags |= 4
		transfer_put_u64(destination, 120, flags)
		output_length^ = bridge.TRANSFER_REGION_RECORD_BYTES
		return 0
	case .Ring:
		if arg0 > bridge.MAX_TRANSFER_INSPECTION_ENTRIES ||
		   output_capacity < bridge.TRANSFER_RING_HEADER_BYTES {
			return 2
		}
		summary, inspected, failure := transfer_ring_inspect(
			call.transfer,
			call.expected_scope,
			arg0,
		)
		if !inspected {
			return racket_transfer_reject(call, failure, failure_code, limit, actual)
		}
		defer transfer_ring_summary_close(&summary, call.transfer.native.temporary_allocator)
		required, admitted := bridge.transfer_ring_record_bytes(u64(len(summary.inspection.entries)))
		if !admitted || required > output_capacity {
			return 2
		}
		transfer_encode_scope(destination, summary.scope)
		transfer_put_u64(destination, 88, u64(len(summary.inspection.entries)))
		transfer_put_u64(destination, 96, 0)
		for entry, index in summary.inspection.entries {
			base := int(bridge.TRANSFER_RING_HEADER_BYTES + u64(index) * bridge.TRANSFER_RING_ENTRY_BYTES)
			transfer_put_u64(destination, base, u64(entry.id))
			transfer_put_u64(destination, base + 8, entry.byte_count)
			transfer_put_u64(destination, base + 16, u64(entry.admission_kind))
			transfer_put_u64(destination, base + 24, entry.coalesced_operations)
			transfer_put_u64(destination, base + 32, u64(entry.generation))
		}
		output_length^ = required
		return 0
	case .Entry_Text:
		if arg0 == 0 || arg1 > bridge.MAX_TRANSFER_ENTRY_TEXT_BYTES || output_capacity != arg1 {
			return 2
		}
		copied, copied_ok, failure := transfer_entry_text(
			call.transfer,
			call.expected_scope,
			kill_ring.Entry_ID(arg0),
			arg1,
		)
		if !copied_ok {
			return racket_transfer_reject(call, failure, failure_code, limit, actual)
		}
		defer transfer_entry_text_close(&copied, call.transfer.native.temporary_allocator)
		copy(destination, transmute([]u8)copied.entry.text)
		output_length^ = u64(len(copied.entry.text))
		return 0
	case .Invoke:
		if input == nil || input_length == 0 || input_length > RACKET_TRANSFER_COMMAND_BYTES ||
		   output_capacity != bridge.TRANSFER_SCOPE_RECORD_BYTES {
			return 2
		}
		name_bytes := ([^]u8)(input)[:int(input_length)]
		if !utf8.valid_string(string(name_bytes)) {
			return 2
		}
		invoked, invoked_ok, failure := transfer_command_invoke(
			call.transfer,
			Transfer_Command_Request {
				expected_scope = call.expected_scope,
				name = string(name_bytes),
			},
		)
		if !invoked_ok {
			return racket_transfer_reject(call, failure, failure_code, limit, actual)
		}
		call.expected_scope = invoked.result_scope
		call.completion = invoked.native.completion
		value^ = u64(invoked.native.completion)
		transfer_encode_scope(destination, invoked.result_scope)
		output_length^ = bridge.TRANSFER_SCOPE_RECORD_BYTES
		transfer_command_result_close(&invoked)
		return 0
	}
	return 2
}

@(private)
racket_transfer_reject :: proc(
	call: ^Racket_Transfer_Call,
	failure: Failure_Context,
	failure_code: ^u32,
	limit, actual: ^u64,
) -> i32 {
	call.failure = failure
	code := u32(failure.transfer_code)
	if code == 0 {
		code = 256 + u32(failure.code)
	}
	failure_code^ = code
	limit^ = failure.limit
	actual^ = failure.actual
	return 1
}

@(private)
transfer_scope_token :: proc(scope: Transfer_Capability_Scope) -> u64 {
	token := u64(scope.editor_session_id) ~ (u64(scope.view.view_id) << 1) ~
	         (scope.view_state_generation << 7) ~ (u64(scope.ring_generation) << 13)
	if token == 0 {
		return 1
	}
	return token
}

@(private)
transfer_encode_scope :: proc(destination: []u8, scope: Transfer_Capability_Scope) {
	assert(u64(len(destination)) >= bridge.TRANSFER_SCOPE_RECORD_BYTES)
	transfer_put_u64(destination, 0, u64(scope.editor_session_id))
	transfer_put_u64(destination, 8, u64(transmute(u8)scope.access))
	transfer_put_u64(destination, 16, u64(scope.view.registry_id))
	transfer_put_u64(destination, 24, u64(scope.view.view_id))
	transfer_put_u64(destination, 32, u64(scope.view.generation))
	transfer_put_u64(destination, 40, scope.view_state_generation)
	transfer_put_u64(destination, 48, u64(scope.buffer_id))
	transfer_put_u64(destination, 56, u64(scope.revision))
	transfer_put_u64(destination, 64, u64(scope.ring_id))
	transfer_put_u64(destination, 72, u64(scope.ring_generation))
	transfer_put_u64(destination, 80, u64(scope.command_registry_generation))
}

@(private)
transfer_put_u64 :: proc(destination: []u8, offset: int, value: u64) {
	assert(offset >= 0 && offset + 8 <= len(destination))
	written := endian.put_u64(destination[offset:], .Little, value)
	assert(written)
}
