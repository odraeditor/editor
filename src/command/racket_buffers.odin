// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../bridge"
import "../editor_session"
import "../hosting"
import editor_view "../view"
import base_runtime "base:runtime"
import endian "core:encoding/endian"
import "core:unicode/utf8"

/* Racket_Buffer_Session_Result reports the final copied scope after composition. */
Racket_Buffer_Session_Result :: struct {
	scope: Buffer_Session_Capability_Scope,
}

@(private)
Racket_Buffer_Session_Call :: struct {
	capability:    Buffer_Session_Capability_Context,
	token:         u64,
	expected_scope: Buffer_Session_Capability_Scope,
	failure:       Failure_Context,
}

/* racket_buffer_session_turn runs one dynamically scoped programmable session composition. */
racket_buffer_session_turn :: proc(
	racket_runtime: ^hosting.Runtime,
	capability: Buffer_Session_Capability_Context,
	scenario: i32,
) -> (result: Racket_Buffer_Session_Result, ok: bool, failure: Failure_Context) {
	if racket_runtime == nil {
		return {}, false, buffer_session_capability_failure(.Invalid_Context)
	}
	scope, scoped, scope_failure := buffer_session_capability_scope(capability)
	if !scoped {
		return {}, false, scope_failure
	}
	token := racket_buffer_session_token(scope)
	call := Racket_Buffer_Session_Call {
		capability = capability,
		token = token,
		expected_scope = scope,
	}
	executed, runtime_failure := hosting.runtime_buffer_session_probe(
		racket_runtime,
		scenario,
		token,
		racket_buffer_session_callback,
		&call,
	)
	if !executed {
		return {}, false, hosting_failure_context({}, runtime_failure)
	}
	if call.failure.code != .None {
		return {}, false, call.failure
	}
	return Racket_Buffer_Session_Result{scope = call.expected_scope}, true, {}
}

@(private)
racket_buffer_session_callback :: proc "c" (
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
	call := (^Racket_Buffer_Session_Call)(user_data)
	if call == nil || kind != .Buffer_Session || generation == 0 || domain_context != 0 ||
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
	input_bytes: []u8
	if input_length > 0 {
		if input == nil {
			return 2
		}
		input_bytes = ([^]u8)(input)[:int(input_length)]
	}
	destination: []u8
	if output_capacity > 0 {
		if output == nil {
			return 2
		}
		destination = ([^]u8)(output)[:int(output_capacity)]
	}

	op := bridge.Buffer_Session_Operation(operation)
	if op == .Scope {
		if input_length != 0 || output_capacity != bridge.BUFFER_SESSION_SCOPE_RECORD_BYTES {
			return 2
		}
		racket_buffer_session_encode_scope(destination, call.expected_scope)
		output_length^ = bridge.BUFFER_SESSION_SCOPE_RECORD_BYTES
		return 0
	}
	if len(input_bytes) < int(bridge.BUFFER_SESSION_SCOPE_RECORD_BYTES) {
		return 2
	}
	expected, decoded := racket_buffer_session_decode_scope(input_bytes[:bridge.BUFFER_SESSION_SCOPE_RECORD_BYTES])
	if !decoded {
		return 2
	}

	switch op {
	case .Scope:
		return 2
	case .Usage:
		if input_length != bridge.BUFFER_SESSION_SCOPE_RECORD_BYTES ||
		   output_capacity != bridge.BUFFER_SESSION_USAGE_RECORD_BYTES {
			return 2
		}
		summary, inspected, failure := buffer_session_usage_inspect(call.capability, expected)
		if !inspected {
			return racket_buffer_session_reject(call, failure, failure_code, limit, actual)
		}
		racket_buffer_session_encode_usage(destination, summary)
		output_length^ = bridge.BUFFER_SESSION_USAGE_RECORD_BYTES
		return 0
	case .Descriptors:
		if input_length != bridge.BUFFER_SESSION_SCOPE_RECORD_BYTES ||
		   arg0 > bridge.MAX_BUFFER_SESSION_DESCRIPTORS ||
		   arg1 > bridge.MAX_BUFFER_SESSION_LABEL_BYTES {
			return 2
		}
		batch, inspected, failure := buffer_session_descriptors_inspect(call.capability, expected)
		if !inspected {
			return racket_buffer_session_reject(call, failure, failure_code, limit, actual)
		}
		defer editor_session.descriptor_batch_close(&batch)
		if u64(len(batch.descriptors)) > arg0 {
			failure = buffer_session_capability_failure(.Temporary_Memory_Limit)
			failure.limit = arg0
			failure.actual = u64(len(batch.descriptors))
			return racket_buffer_session_reject(call, failure, failure_code, limit, actual)
		}
		written, encoded := racket_buffer_session_encode_descriptors(
			destination,
			expected,
			batch.descriptors,
			arg1,
		)
		if !encoded {
			return 2
		}
		output_length^ = written
		return 0
	case .Descriptor:
		request, parsed := racket_buffer_session_parse_request(input_bytes, op)
		if !parsed {
			return 2
		}
		copied, inspected, failure := buffer_session_descriptor_inspect(
			call.capability,
			expected,
			request.entry,
		)
		if !inspected {
			return racket_buffer_session_reject(call, failure, failure_code, limit, actual)
		}
		defer buffer_descriptor_copy_close(&copied)
		written, encoded := racket_buffer_session_encode_descriptors(
			destination,
			expected,
			[]editor_session.Entry_Descriptor{copied.descriptor},
			bridge.MAX_BUFFER_SESSION_LABEL_BYTES,
		)
		if !encoded {
			return 2
		}
		output_length^ = written
		return 0
	case .Create, .Open, .Activate, .Save, .Kill, .Execute_Marks:
		return racket_buffer_session_mutate(
			call,
			op,
			input_bytes,
			destination,
			output_length,
			failure_code,
			limit,
			actual,
		)
	}
	return 2
}

@(private)
Racket_Buffer_Session_Request :: struct {
	expected:  Buffer_Session_Capability_Scope,
	entry:     editor_session.Entry_Handle,
	authority: editor_session.Close_Authority,
	text:      string,
	marks:     []Buffer_Marked_Entry,
	decisions: []Marked_Entry_Decision,
}

@(private)
racket_buffer_session_parse_request :: proc(
	input: []u8,
	operation: bridge.Buffer_Session_Operation,
) -> (request: Racket_Buffer_Session_Request, ok: bool) {
	if len(input) < int(bridge.BUFFER_SESSION_REQUEST_HEADER_BYTES) {
		return {}, false
	}
	request.expected, ok = racket_buffer_session_decode_scope(
		input[:bridge.BUFFER_SESSION_SCOPE_RECORD_BYTES],
	)
	if !ok || racket_buffer_session_get(input, 144) != u64(operation) {
		return {}, false
	}
	request.authority = editor_session.Close_Authority(racket_buffer_session_get(input, 152))
	request.entry = racket_buffer_session_decode_entry(input, 160)
	mark_count := racket_buffer_session_get(input, 208)
	text_bytes := racket_buffer_session_get(input, 256)
	decision_count := racket_buffer_session_get(input, 264)
	if text_bytes > bridge.MAX_BUFFER_SESSION_REQUEST_TEXT_BYTES ||
	   mark_count > bridge.MAX_BUFFER_SESSION_MARKS ||
	   decision_count > bridge.MAX_BUFFER_SESSION_DECISIONS {
		return {}, false
	}
	if racket_buffer_session_get(input, 216) != 0 ||
	   racket_buffer_session_get(input, 224) != 0 ||
	   racket_buffer_session_get(input, 232) != 0 ||
	   racket_buffer_session_get(input, 240) != 0 ||
	   racket_buffer_session_get(input, 248) != 0 {
		return {}, false
	}
	mark_bytes := mark_count * bridge.BUFFER_SESSION_MARK_RECORD_BYTES
	record_bytes := decision_count * bridge.BUFFER_SESSION_DECISION_RECORD_BYTES
	payload_start := bridge.BUFFER_SESSION_REQUEST_HEADER_BYTES
	mark_start := payload_start + text_bytes
	record_start := mark_start + mark_bytes
	path_start := record_start + record_bytes
	if path_start > u64(len(input)) {
		return {}, false
	}
	path_bytes := u64(len(input)) - path_start
	required, admitted := bridge.buffer_session_request_record_bytes(
		text_bytes,
		mark_count,
		decision_count,
		path_bytes,
	)
	if !admitted || required != u64(len(input)) {
		return {}, false
	}
	request.text = string(input[payload_start:payload_start + text_bytes])
	if !utf8.valid_string(request.text) {
		return {}, false
	}
	if mark_count > 0 {
		marks, allocation_error := make(
			[]Buffer_Marked_Entry,
			int(mark_count),
			context.temp_allocator,
		)
		if allocation_error != nil do return {}, false
		request.marks = marks
		for index in 0 ..< int(mark_count) {
			base := int(mark_start + u64(index) * bridge.BUFFER_SESSION_MARK_RECORD_BYTES)
			request.marks[index] = Buffer_Marked_Entry {
				entry = racket_buffer_session_decode_entry(input, base),
				kind = Buffer_Mark_Kind(racket_buffer_session_get(input, base + 48)),
			}
		}
	}
	if decision_count == 0 {
		return request, true
	}
	decisions, allocation_error := make(
		[]Marked_Entry_Decision,
		int(decision_count),
		context.temp_allocator,
	)
	if allocation_error != nil {
		if request.marks != nil do delete(request.marks, context.temp_allocator)
		return {}, false
	}
	request.decisions = decisions
	for index in 0 ..< int(decision_count) {
		base := int(record_start + u64(index) * bridge.BUFFER_SESSION_DECISION_RECORD_BYTES)
		path_offset := racket_buffer_session_get(input, base + 56)
		decision_path_bytes := racket_buffer_session_get(input, base + 64)
		if path_offset > path_bytes || decision_path_bytes > path_bytes - path_offset {
			if request.marks != nil do delete(request.marks, context.temp_allocator)
			delete(request.decisions, context.temp_allocator)
			return {}, false
		}
		path := string(input[path_start + path_offset:path_start + path_offset + decision_path_bytes])
		if !utf8.valid_string(path) {
			if request.marks != nil do delete(request.marks, context.temp_allocator)
			delete(request.decisions, context.temp_allocator)
			return {}, false
		}
		request.decisions[index] = Marked_Entry_Decision {
			entry = racket_buffer_session_decode_entry(input, base),
			kind = Marked_Kill_Decision(racket_buffer_session_get(input, base + 48)),
			path = path,
		}
	}
	return request, true
}

@(private)
racket_buffer_session_request_close :: proc(request: ^Racket_Buffer_Session_Request) {
	if request != nil && request.marks != nil {
		delete(request.marks, context.temp_allocator)
		request.marks = nil
	}
	if request != nil && request.decisions != nil {
		delete(request.decisions, context.temp_allocator)
		request.decisions = nil
	}
}

@(private)
racket_buffer_session_mutate :: proc(
	call: ^Racket_Buffer_Session_Call,
	operation: bridge.Buffer_Session_Operation,
	input, destination: []u8,
	output_length: ^u64,
	failure_code: ^u32,
	limit, actual: ^u64,
) -> i32 {
	if u64(len(destination)) != bridge.BUFFER_SESSION_OUTCOME_RECORD_BYTES {
		return 2
	}
	request, parsed := racket_buffer_session_parse_request(input, operation)
	if !parsed {
		return 2
	}
	defer racket_buffer_session_request_close(&request)
	outcome := bridge.Buffer_Session_Outcome_Record{}
	switch operation {
	case .Create:
		result, ok, failure := buffer_session_capability_create(
			call.capability, request.expected, request.text,
		)
		if !ok {
			return racket_buffer_session_reject(call, failure, failure_code, limit, actual)
		}
		call.expected_scope = result.scope
		outcome.completion = u64(result.operation.completion)
		racket_buffer_session_outcome_entry(&outcome, result.operation.entry)
	case .Open:
		result, ok, failure := buffer_session_capability_open(
			call.capability, request.expected, request.text,
		)
		if !ok {
			return racket_buffer_session_reject(call, failure, failure_code, limit, actual)
		}
		call.expected_scope = result.scope
		outcome.completion = u64(result.operation.completion)
		racket_buffer_session_outcome_entry(&outcome, result.operation.entry)
	case .Activate:
		result, ok, failure := buffer_session_capability_activate(
			call.capability, request.expected, request.entry,
		)
		if !ok {
			return racket_buffer_session_reject(call, failure, failure_code, limit, actual)
		}
		call.expected_scope = result.scope
		outcome.completion = u64(result.operation.completion)
		racket_buffer_session_outcome_entry(&outcome, result.operation.entry)
	case .Save:
		result, ok, failure := buffer_session_capability_save(
			call.capability, request.expected, request.entry, request.text,
		)
		if !ok {
			return racket_buffer_session_reject(call, failure, failure_code, limit, actual)
		}
		call.expected_scope = result.scope
		outcome.document_id = u64(result.save.document_id)
		outcome.buffer_id = u64(result.save.buffer_id)
		outcome.saved_revision = u64(result.save.saved_revision)
		outcome.publication = u64(result.save.publication)
		racket_buffer_session_outcome_entry(&outcome, request.entry)
	case .Kill:
		result, ok, failure := buffer_session_capability_kill(
			call.capability, request.expected, request.entry, request.authority,
		)
		if !ok {
			return racket_buffer_session_reject(call, failure, failure_code, limit, actual)
		}
		call.expected_scope = result.scope
		outcome.completion = u64(result.kill.completion)
		outcome.closure_outcome = u64(result.kill.closure.outcome)
		outcome.modified = 1 if result.kill.closure.modified else 0
		outcome.last_buffer = 1 if result.kill.closure.last_buffer else 0
		racket_buffer_session_outcome_entry(&outcome, request.entry)
	case .Execute_Marks:
		result, ok, failure := buffer_session_capability_execute_marks(
			call.capability,
			request.expected,
			request.marks,
			request.decisions,
		)
		if !ok {
			return racket_buffer_session_reject(call, failure, failure_code, limit, actual)
		}
		call.expected_scope = result.scope
		outcome.marked_outcome = u64(result.execution.outcome)
		outcome.completed_saves = u64(result.execution.completed_saves)
		outcome.pending_saves = u64(result.execution.pending_saves)
		outcome.completed_kills = u64(result.execution.completed_kills)
		outcome.pending_kills = u64(result.execution.pending_kills)
		outcome.decision_entry_id = u64(result.execution.decision_entry.entry_id)
		outcome.failed_entry_id = u64(result.execution.failed_entry.entry_id)
	case .Scope, .Usage, .Descriptors, .Descriptor:
		return 2
	}
	outcome.scope = racket_buffer_session_scope_record(call.expected_scope)
	usage, usage_ok, _ := editor_session.session_usage(
		call.capability.buffer_session.session,
		call.capability.buffer_session.handle,
	)
	if usage_ok {
		outcome.live_buffers = u64(usage.live_buffers)
		outcome.live_documents = u64(usage.live_documents)
	}
	racket_buffer_session_encode_outcome(destination, outcome)
	output_length^ = bridge.BUFFER_SESSION_OUTCOME_RECORD_BYTES
	return 0
}

@(private)
racket_buffer_session_reject :: proc(
	call: ^Racket_Buffer_Session_Call,
	failure: Failure_Context,
	failure_code: ^u32,
	limit, actual: ^u64,
) -> i32 {
	call.failure = failure
	code := u32(failure.buffer_session_capability_code)
	if code == 0 {
		code = 256 + u32(failure.code)
	}
	failure_code^ = code
	limit^ = failure.limit
	actual^ = failure.actual
	return 1
}

@(private)
racket_buffer_session_token :: proc(scope: Buffer_Session_Capability_Scope) -> u64 {
	token := u64(scope.editor_session_id) ~ (u64(scope.session.session_id) << 1) ~
	         (u64(scope.session.generation) << 7) ~ (u64(scope.registry.generation) << 13)
	if token == 0 {
		return 1
	}
	return token
}

@(private)
racket_buffer_session_scope_record :: proc(
	scope: Buffer_Session_Capability_Scope,
) -> bridge.Buffer_Session_Scope_Record {
	return bridge.Buffer_Session_Scope_Record {
		editor_session_id = u64(scope.editor_session_id),
		access = u64(transmute(u8)scope.access),
		session_id = u64(scope.session.session_id),
		session_generation = u64(scope.session.generation),
		registry_generation = u64(scope.registry.generation),
		visible_kind = u64(scope.visible.kind),
		visible_entry_session_id = u64(scope.visible.entry.registry.session.session_id),
		visible_entry_session_generation = u64(scope.visible.entry.registry.session.generation),
		visible_entry_registry_generation = u64(scope.visible.entry.registry.generation),
		visible_entry_id = u64(scope.visible.entry.entry_id),
		visible_entry_slot = u64(scope.visible.entry.slot),
		visible_entry_generation = u64(scope.visible.entry.generation),
		visible_view_registry_id = u64(scope.visible.primary_view.registry_id),
		visible_view_id = u64(scope.visible.primary_view.view_id),
		visible_view_generation = u64(scope.visible.primary_view.generation),
		visible_ui_owner_id = scope.visible.ui.owner_id,
		visible_ui_model_id = scope.visible.ui.model_id,
		visible_ui_generation = scope.visible.ui.generation,
	}
}

@(private)
racket_buffer_session_encode_scope :: proc(
	destination: []u8,
	scope: Buffer_Session_Capability_Scope,
) {
	record := racket_buffer_session_scope_record(scope)
	values := transmute([18]u64)record
	racket_buffer_session_encode_scalars(destination, values[:])
}

@(private)
racket_buffer_session_decode_scope :: proc(
	bytes: []u8,
) -> (scope: Buffer_Session_Capability_Scope, ok: bool) {
	if u64(len(bytes)) < bridge.BUFFER_SESSION_SCOPE_RECORD_BYTES {
		return {}, false
	}
	scope = Buffer_Session_Capability_Scope {
		editor_session_id = Editor_Session_ID(racket_buffer_session_get(bytes, 0)),
		access = transmute(Buffer_Session_Access_Set)u8(racket_buffer_session_get(bytes, 8)),
		session = editor_session.Session_Handle {
			session_id = editor_session.Session_ID(racket_buffer_session_get(bytes, 16)),
			generation = editor_session.Session_Generation(racket_buffer_session_get(bytes, 24)),
		},
	}
	scope.registry = editor_session.Registry_Handle {
		session = scope.session,
		generation = editor_session.Registry_Generation(racket_buffer_session_get(bytes, 32)),
	}
	scope.visible = editor_session.Visible_Target {
		kind = editor_session.Visible_Target_Kind(racket_buffer_session_get(bytes, 40)),
		entry = racket_buffer_session_decode_entry(bytes, 48),
		primary_view = {
			registry_id = editor_view.Registry_ID(racket_buffer_session_get(bytes, 96)),
			view_id = editor_view.View_ID(racket_buffer_session_get(bytes, 104)),
			generation = u32(racket_buffer_session_get(bytes, 112)),
		},
		ui = {
			owner_id = racket_buffer_session_get(bytes, 120),
			model_id = racket_buffer_session_get(bytes, 128),
			generation = racket_buffer_session_get(bytes, 136),
		},
	}
	return scope, editor_session.session_handle_is_valid(scope.session) &&
	              editor_session.registry_handle_is_valid(scope.registry) &&
	              editor_session.visible_target_is_valid(scope.visible)
}

@(private)
racket_buffer_session_decode_entry :: proc(bytes: []u8, offset: int) -> editor_session.Entry_Handle {
	return editor_session.Entry_Handle {
		registry = {
			session = {
				session_id = editor_session.Session_ID(racket_buffer_session_get(bytes, offset)),
				generation = editor_session.Session_Generation(racket_buffer_session_get(bytes, offset + 8)),
			},
			generation = editor_session.Registry_Generation(racket_buffer_session_get(bytes, offset + 16)),
		},
		entry_id = editor_session.Entry_ID(racket_buffer_session_get(bytes, offset + 24)),
		slot = u32(racket_buffer_session_get(bytes, offset + 32)),
		generation = u32(racket_buffer_session_get(bytes, offset + 40)),
	}
}

@(private)
racket_buffer_session_encode_usage :: proc(
	destination: []u8,
	summary: Buffer_Session_Usage_Summary,
) {
	record := bridge.Buffer_Session_Usage_Record {
		scope = racket_buffer_session_scope_record(summary.scope),
		live_buffers = u64(summary.usage.live_buffers),
		live_documents = u64(summary.usage.live_documents),
		live_primary_views = u64(summary.usage.live_primary_views),
		activation_entries = u64(summary.usage.activation_entries),
		canonical_text_bytes = summary.usage.canonical_text_bytes,
		retained_label_bytes = summary.usage.retained_label_bytes,
		view_anchors = summary.usage.view_anchors,
		view_context_bytes = summary.usage.view_context_bytes,
		history_bytes = summary.usage.history_bytes,
		registry_bytes = summary.usage.registry_bytes,
		outstanding_capabilities = u64(summary.usage.outstanding_capabilities),
		prepared_operations = u64(summary.usage.prepared_operations),
		detached_cleanup_entries = u64(summary.usage.detached_cleanup_entries),
	}
	values := transmute([31]u64)record
	racket_buffer_session_encode_scalars(destination, values[:])
}

@(private)
racket_buffer_session_encode_descriptors :: proc(
	destination: []u8,
	scope: Buffer_Session_Capability_Scope,
	descriptors: []editor_session.Entry_Descriptor,
	label_limit: u64,
) -> (written: u64, ok: bool) {
	label_bytes: u64
	for descriptor in descriptors {
		label_bytes += u64(len(descriptor.selection_label))
	}
	required, admitted := bridge.buffer_session_descriptor_record_bytes(
		u64(len(descriptors)), label_bytes,
	)
	if !admitted || label_bytes > label_limit || required > u64(len(destination)) {
		return 0, false
	}
	racket_buffer_session_encode_scope(destination, scope)
	racket_buffer_session_put(destination, 144, u64(len(descriptors)))
	racket_buffer_session_put(destination, 152, label_bytes)
	label_start := bridge.BUFFER_SESSION_DESCRIPTOR_HEADER_BYTES +
	               u64(len(descriptors)) * bridge.BUFFER_SESSION_DESCRIPTOR_RECORD_BYTES
	label_offset: u64
	for descriptor, index in descriptors {
		base := int(bridge.BUFFER_SESSION_DESCRIPTOR_HEADER_BYTES +
		            u64(index) * bridge.BUFFER_SESSION_DESCRIPTOR_RECORD_BYTES)
		racket_buffer_session_encode_descriptor(destination[base:], descriptor, label_offset)
		label := transmute([]u8)descriptor.selection_label
		copy(destination[label_start + label_offset:], label)
		label_offset += u64(len(label))
	}
	return required, true
}

@(private)
racket_buffer_session_encode_descriptor :: proc(
	destination: []u8,
	descriptor: editor_session.Entry_Descriptor,
	label_offset: u64,
) {
	record := bridge.Buffer_Session_Descriptor_Record {
		entry_session_id = u64(descriptor.graph.entry.registry.session.session_id),
		entry_session_generation = u64(descriptor.graph.entry.registry.session.generation),
		entry_registry_generation = u64(descriptor.graph.entry.registry.generation),
		entry_id = u64(descriptor.graph.entry.entry_id),
		entry_slot = u64(descriptor.graph.entry.slot),
		entry_generation = u64(descriptor.graph.entry.generation),
		buffer_id = u64(descriptor.graph.buffer_id),
		history_id = u64(descriptor.graph.history_id),
		view_registry_id = u64(descriptor.graph.primary_view.registry_id),
		view_id = u64(descriptor.graph.primary_view.view_id),
		view_generation = u64(descriptor.graph.primary_view.generation),
		has_document = 1 if descriptor.graph.has_document else 0,
		document_id = u64(descriptor.graph.document_id),
		label_offset = label_offset,
		label_bytes = u64(len(descriptor.selection_label)),
		association = u64(descriptor.association),
		persistence = u64(descriptor.persistence),
		operation = u64(descriptor.operation),
		active = 1 if descriptor.active else 0,
		modified = 1 if descriptor.modified else 0,
		activation_sequence = u64(descriptor.activation_sequence),
	}
	values := transmute([21]u64)record
	racket_buffer_session_encode_scalars(destination, values[:])
}

@(private)
racket_buffer_session_outcome_entry :: proc(
	outcome: ^bridge.Buffer_Session_Outcome_Record,
	entry: editor_session.Entry_Handle,
) {
	outcome.entry_session_id = u64(entry.registry.session.session_id)
	outcome.entry_session_generation = u64(entry.registry.session.generation)
	outcome.entry_registry_generation = u64(entry.registry.generation)
	outcome.entry_id = u64(entry.entry_id)
	outcome.entry_slot = u64(entry.slot)
	outcome.entry_generation = u64(entry.generation)
}

@(private)
racket_buffer_session_encode_outcome :: proc(
	destination: []u8,
	outcome: bridge.Buffer_Session_Outcome_Record,
) {
	values := transmute([41]u64)outcome
	racket_buffer_session_encode_scalars(destination, values[:])
}

@(private)
racket_buffer_session_encode_scalars :: proc(destination: []u8, values: []u64) {
	assert(len(destination) >= len(values) * 8)
	for scalar, index in values {
		racket_buffer_session_put(destination, index * 8, scalar)
	}
}

@(private)
racket_buffer_session_put :: proc(destination: []u8, offset: int, value: u64) {
	assert(offset >= 0 && offset + 8 <= len(destination))
	written := endian.put_u64(destination[offset:], .Little, value)
	assert(written)
}

@(private)
racket_buffer_session_get :: proc(source: []u8, offset: int) -> u64 {
	value, ok := endian.get_u64(source[offset:], .Little)
	assert(ok)
	return value
}
