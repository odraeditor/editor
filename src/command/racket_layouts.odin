// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../bridge"
import "../hosting"
import "../layout"
import base_runtime "base:runtime"

/* Racket_Layout_Result reports the final copied scope after composition. */
Racket_Layout_Result :: struct {
	scope: Layout_Capability_Scope,
}

/* Racket_Layout_Hook owns one registered Racket observer until explicit release. */
Racket_Layout_Hook :: struct {
	runtime:      ^hosting.Runtime,
	registry:     ^layout.Registry,
	handle:       layout.Hook_Handle,
	scenario:     i32,
	calls:        u64,
	failures:     u64,
	last_failure: Failure_Context,
}

@(private)
Racket_Layout_Call :: struct {
	capability:     Layout_Capability_Context,
	token:          u64,
	expected_scope: Layout_Capability_Scope,
	hook_context:   ^layout.Hook_Callback_Context,
	hook_snapshot:  ^layout.Snapshot,
	failure:        Failure_Context,
}

/* racket_layout_hook_register binds one Racket callback to a bounded native hook slot. */
racket_layout_hook_register :: proc(
	racket_runtime: ^hosting.Runtime,
	registry: ^layout.Registry,
	scenario: i32,
	hook: ^Racket_Layout_Hook,
) -> (handle: layout.Hook_Handle, ok: bool, failure: Failure_Context) {
	if racket_runtime == nil || registry == nil || hook == nil || hook.handle.hook_id != 0 {
		return {}, false, layout_capability_failure(.Invalid_Context)
	}
	hook^ = Racket_Layout_Hook {
		runtime = racket_runtime,
		registry = registry,
		scenario = scenario,
	}
	registered: bool
	layout_failure: layout.Failure_Context
	handle, registered, layout_failure = layout.registry_hook_register(
		registry,
		racket_layout_hook_callback,
		hook,
	)
	if !registered {
		hook^ = {}
		return {}, false, layout_capability_layout_failure(layout_failure)
	}
	hook.handle = handle
	return handle, true, {}
}

/* racket_layout_hook_release removes one exact Racket observer identity. */
racket_layout_hook_release :: proc(
	hook: ^Racket_Layout_Hook,
) -> (ok: bool, failure: Failure_Context) {
	if hook == nil || hook.registry == nil || hook.handle.hook_id == 0 {
		return false, layout_capability_failure(.Invalid_Context)
	}
	released, layout_failure := layout.registry_hook_release(hook.registry, &hook.handle)
	if !released {
		return false, layout_capability_layout_failure(layout_failure)
	}
	hook^ = {}
	return true, {}
}

/* racket_layout_turn runs one dynamically scoped programmable layout composition. */
racket_layout_turn :: proc(
	racket_runtime: ^hosting.Runtime,
	capability: Layout_Capability_Context,
	scenario: i32,
) -> (result: Racket_Layout_Result, ok: bool, failure: Failure_Context) {
	if racket_runtime == nil {
		return {}, false, layout_capability_failure(.Invalid_Context)
	}
	scope, scoped, scope_failure := layout_capability_scope(capability)
	if !scoped {
		return {}, false, scope_failure
	}
	token := racket_layout_token(scope)
	call := Racket_Layout_Call {
		capability = capability,
		token = token,
		expected_scope = scope,
	}
	executed, runtime_failure := hosting.runtime_layout_probe(
		racket_runtime,
		scenario,
		token,
		racket_layout_callback,
		&call,
	)
	if !executed {
		return {}, false, hosting_failure_context({}, runtime_failure)
	}
	if call.failure.code != .None {
		return {}, false, call.failure
	}
	return Racket_Layout_Result{scope = call.expected_scope}, true, {}
}

@(private)
racket_layout_callback :: proc "c" (
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
	call := (^Racket_Layout_Call)(user_data)
	if call == nil || kind != .Layout || generation == 0 || domain_context != 0 ||
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

	op := bridge.Layout_Capability_Operation(operation)
	if op == .Scope {
		if input_length != 0 || output_capacity != bridge.LAYOUT_SCOPE_RECORD_BYTES {
			return 2
		}
		racket_layout_encode_scope(destination, call.expected_scope)
		output_length^ = bridge.LAYOUT_SCOPE_RECORD_BYTES
		return 0
	}
	if op == .Snapshot {
		if input_length != bridge.LAYOUT_SCOPE_RECORD_BYTES {
			return 2
		}
		expected, decoded := racket_layout_decode_scope(input_bytes)
		if !decoded {
			return 2
		}
		snapshot, inspected, failure := layout_capability_snapshot(call.capability, expected)
		if !inspected {
			return racket_layout_reject(call, failure, failure_code, limit, actual)
		}
		written, encoded := racket_layout_encode_snapshot(
			destination, call.expected_scope, snapshot,
		)
		if !encoded {
			return 2
		}
		output_length^ = written
		return 0
	}
	if input_length != bridge.LAYOUT_REQUEST_RECORD_BYTES ||
	   output_capacity != bridge.LAYOUT_OUTCOME_RECORD_BYTES {
		return 2
	}
	request, parsed := racket_layout_decode_request(input_bytes)
	if !parsed || request.operation != u64(op) {
		return 2
	}
	access, allowed := racket_layout_operation_access(op)
	if !allowed {
		return 2
	}
	if call.hook_context != nil {
		if access == .Inspect_Dedication {
			inspection, inspected, failure := layout_capability_request(
				&call.capability,
				request.expected,
				access,
				request.pane,
				request.arrangement,
				request.delta,
				request.dedication,
			)
			if !inspected {
				return racket_layout_reject(call, failure, failure_code, limit, actual)
			}
			call.expected_scope = inspection.scope
			racket_layout_encode_outcome(destination, inspection)
			output_length^ = bridge.LAYOUT_OUTCOME_RECORD_BYTES
			return 0
		}
		mutation, deferred, failure := racket_layout_defer_mutation(
			call,
			request.expected,
			access,
			request.pane,
			request.arrangement,
			request.delta,
			request.dedication,
		)
		if !deferred {
			return racket_layout_reject(call, failure, failure_code, limit, actual)
		}
		racket_layout_encode_outcome(destination, mutation)
		output_length^ = bridge.LAYOUT_OUTCOME_RECORD_BYTES
		return 0
	}
	mutation, mutated, failure := layout_capability_request(
		&call.capability,
		request.expected,
		access,
		request.pane,
		request.arrangement,
		request.delta,
		request.dedication,
	)
	if !mutated {
		return racket_layout_reject(call, failure, failure_code, limit, actual)
	}
	call.expected_scope = mutation.scope
	racket_layout_encode_outcome(destination, mutation)
	output_length^ = bridge.LAYOUT_OUTCOME_RECORD_BYTES
	return 0
}

@(private)
racket_layout_hook_callback :: proc "c" (
	user_data: rawptr,
	handle: layout.Hook_Handle,
	snapshot: ^layout.Snapshot,
	ctx: ^layout.Hook_Callback_Context,
) -> bool {
	context = base_runtime.default_context()
	hook := (^Racket_Layout_Hook)(user_data)
	if hook == nil || hook.runtime == nil || hook.registry == nil || snapshot == nil ||
	   ctx == nil || handle != hook.handle || handle != ctx.hook {
		return false
	}
	hook.calls += 1
	capability := Layout_Capability_Context {
		registry = hook.registry,
		access = {
			.Inspect,
			.Split_Below,
			.Split_Right,
			.Focus,
			.Close,
			.Keep_Only,
			.Resize,
			.Balance_Dimensions,
			.Balance_Areas,
			.Inspect_Dedication,
			.Set_Dedication,
		},
		layout_handle = snapshot.handle,
		pane = snapshot.active_pane,
	}
	scope, scoped, scope_failure := layout_capability_scope(capability)
	if !scoped {
		hook.failures += 1
		hook.last_failure = scope_failure
		return false
	}
	call := Racket_Layout_Call {
		capability = capability,
		token = racket_layout_token(scope),
		expected_scope = scope,
		hook_context = ctx,
		hook_snapshot = snapshot,
	}
	scenario := i32(6)
	if hook.calls == 1 {
		scenario = hook.scenario
	}
	executed, runtime_failure := hosting.runtime_layout_probe(
		hook.runtime,
		scenario,
		call.token,
		racket_layout_callback,
		&call,
	)
	if !executed {
		hook.failures += 1
		hook.last_failure = hosting_failure_context({}, runtime_failure)
		return false
	}
	if call.failure.code != .None {
		hook.failures += 1
		hook.last_failure = call.failure
		return false
	}
	return true
}

@(private)
racket_layout_defer_mutation :: proc(
	call: ^Racket_Layout_Call,
	expected: Layout_Capability_Scope,
	access: Layout_Capability_Access,
	target: layout.Pane_Handle,
	arrangement: layout.Arrangement,
	delta: i32,
	dedication: layout.Pane_Dedication,
) -> (result: Layout_Capability_Result, ok: bool, failure: Failure_Context) {
	if call == nil || call.hook_context == nil || call.hook_snapshot == nil {
		return {}, false, layout_capability_failure(.Invalid_Context)
	}
	_, valid, validation_failure := layout_capability_validate(call.capability, expected, access)
	if !valid {
		return {}, false, validation_failure
	}
	if target.layout != expected.layout_handle {
		return {}, false, layout_capability_failure(.Wrong_Layout)
	}
	if !layout_capability_snapshot_contains_pane(call.hook_snapshot^, target) {
		return {}, false, layout_capability_failure(.Stale_Pane)
	}
	operation: layout.Deferred_Operation
	#partial switch access {
	case .Split_Below: operation = .Split_Below
	case .Split_Right: operation = .Split_Right
	case .Focus: operation = .Focus
	case .Close: operation = .Close
	case .Keep_Only: operation = .Keep_Only
	case .Resize: operation = .Resize
	case .Balance_Dimensions: operation = .Balance_Dimensions
	case .Balance_Areas: operation = .Balance_Areas
	case .Set_Dedication: operation = .Set_Dedication
	case .Inspect, .Inspect_Dedication:
		return {}, false, layout_capability_failure(.Permission_Denied)
	}
	_, deferred, layout_failure := layout.registry_defer_request(
		call.hook_context,
		layout.Deferred_Request {
			operation = operation,
			expected = expected.layout_handle,
			pane = target,
			arrangement = arrangement,
			delta = delta,
			dedication = dedication,
		},
	)
	if !deferred {
		return {}, false, layout_capability_layout_failure(layout_failure)
	}
	return Layout_Capability_Result {
		scope = expected,
		primary = target,
		changed = false,
		arrangement = arrangement,
		delta = delta,
		previous_dedication = dedication,
		current_dedication = dedication,
	}, true, {}
}

@(private)
Racket_Layout_Request :: struct {
	expected:    Layout_Capability_Scope,
	operation:   u64,
	pane:        layout.Pane_Handle,
	arrangement: layout.Arrangement,
	delta:       i32,
	dedication:  layout.Pane_Dedication,
}

@(private)
racket_layout_decode_request :: proc(bytes: []u8) -> (request: Racket_Layout_Request, ok: bool) {
	if u64(len(bytes)) != bridge.LAYOUT_REQUEST_RECORD_BYTES {
		return {}, false
	}
	request.expected, ok = racket_layout_decode_scope(bytes[:bridge.LAYOUT_SCOPE_RECORD_BYTES])
	if !ok {
		return {}, false
	}
	request.operation = racket_buffer_session_get(bytes, 64)
	request.pane = racket_layout_decode_pane(bytes, 72)
	request.arrangement = layout.Arrangement(racket_buffer_session_get(bytes, 120))
	request.delta = i32(cast(i64)racket_buffer_session_get(bytes, 128))
	request.dedication = layout.Pane_Dedication(racket_buffer_session_get(bytes, 136))
	return request, true
}

@(private)
racket_layout_operation_access :: proc(
	operation: bridge.Layout_Capability_Operation,
) -> (access: Layout_Capability_Access, ok: bool) {
	switch operation {
	case .Split_Below:
		return .Split_Below, true
	case .Split_Right:
		return .Split_Right, true
	case .Focus:
		return .Focus, true
	case .Close:
		return .Close, true
	case .Keep_Only:
		return .Keep_Only, true
	case .Resize:
		return .Resize, true
	case .Balance_Dimensions:
		return .Balance_Dimensions, true
	case .Balance_Areas:
		return .Balance_Areas, true
	case .Inspect_Dedication:
		return .Inspect_Dedication, true
	case .Set_Dedication:
		return .Set_Dedication, true
	case .Scope, .Snapshot:
	}
	return {}, false
}

@(private)
racket_layout_scope_record :: proc(scope: Layout_Capability_Scope) -> bridge.Layout_Scope_Record {
	return bridge.Layout_Scope_Record {
		schema_version = bridge.LAYOUT_CAPABILITY_SCHEMA_VERSION,
		access = u64(transmute(u16)scope.access),
		owner_id = u64(scope.layout_handle.owner_id),
		layout_id = u64(scope.layout_handle.layout_id),
		layout_generation = u64(scope.layout_handle.generation),
		pane_id = u64(scope.pane.pane_id),
		pane_slot = u64(scope.pane.slot),
		pane_slot_generation = u64(scope.pane.slot_generation),
	}
}

@(private)
racket_layout_encode_scope :: proc(destination: []u8, scope: Layout_Capability_Scope) {
	record := racket_layout_scope_record(scope)
	values := transmute([8]u64)record
	racket_buffer_session_encode_scalars(destination, values[:])
}

@(private)
racket_layout_decode_scope :: proc(bytes: []u8) -> (scope: Layout_Capability_Scope, ok: bool) {
	if u64(len(bytes)) < bridge.LAYOUT_SCOPE_RECORD_BYTES {
		return {}, false
	}
	scope = Layout_Capability_Scope {
		access = transmute(Layout_Capability_Access_Set)u16(racket_buffer_session_get(bytes, 8)),
		layout_handle = {
			owner_id = layout.Owner_ID(racket_buffer_session_get(bytes, 16)),
			layout_id = layout.Layout_ID(racket_buffer_session_get(bytes, 24)),
			generation = layout.Layout_Generation(racket_buffer_session_get(bytes, 32)),
		},
	}
	scope.pane = layout.Pane_Handle {
		layout = scope.layout_handle,
		pane_id = layout.Pane_ID(racket_buffer_session_get(bytes, 40)),
		slot = u16(racket_buffer_session_get(bytes, 48)),
		slot_generation = u32(racket_buffer_session_get(bytes, 56)),
	}
	return scope, racket_buffer_session_get(bytes, 0) == bridge.LAYOUT_CAPABILITY_SCHEMA_VERSION &&
	              scope.access != {} && scope.layout_handle.owner_id != layout.Owner_ID(0) &&
	              scope.layout_handle.layout_id != layout.Layout_ID(0) &&
	              scope.layout_handle.generation != layout.Layout_Generation(0) &&
	              scope.pane.pane_id != layout.Pane_ID(0) && scope.pane.slot_generation != 0
}

@(private)
racket_layout_decode_pane :: proc(bytes: []u8, offset: int) -> layout.Pane_Handle {
	return layout.Pane_Handle {
		layout = {
			owner_id = layout.Owner_ID(racket_buffer_session_get(bytes, offset)),
			layout_id = layout.Layout_ID(racket_buffer_session_get(bytes, offset + 8)),
			generation = layout.Layout_Generation(racket_buffer_session_get(bytes, offset + 16)),
		},
		pane_id = layout.Pane_ID(racket_buffer_session_get(bytes, offset + 24)),
		slot = u16(racket_buffer_session_get(bytes, offset + 32)),
		slot_generation = u32(racket_buffer_session_get(bytes, offset + 40)),
	}
}

@(private)
racket_layout_encode_snapshot :: proc(
	destination: []u8,
	scope: Layout_Capability_Scope,
	snapshot: layout.Snapshot,
) -> (written: u64, ok: bool) {
	required, admitted := bridge.layout_snapshot_record_bytes(u64(snapshot.node_count))
	if !admitted || required > u64(len(destination)) {
		return 0, false
	}
	header := bridge.Layout_Snapshot_Header_Record {
		scope = racket_layout_scope_record(scope),
		geometry_state = u64(snapshot.geometry_state),
		geometry_rows = racket_layout_signed(snapshot.geometry_request.rows),
		geometry_columns = racket_layout_signed(snapshot.geometry_request.columns),
		global_reserved_rows = racket_layout_signed(snapshot.geometry_request.global_reserved_rows),
		global_reserved_columns = racket_layout_signed(snapshot.geometry_request.global_reserved_columns),
		root_id = u64(snapshot.root_id),
		node_count = u64(snapshot.node_count),
		pane_count = u64(snapshot.pane_count),
		partition_count = u64(snapshot.partition_count),
		geometry_work = snapshot.geometry_work,
	}
	racket_layout_record_pane(&header.active_owner_id, snapshot.active_pane)
	header_values := transmute([24]u64)header
	racket_buffer_session_encode_scalars(destination, header_values[:])
	for index in 0 ..< int(snapshot.node_count) {
		base := int(bridge.LAYOUT_SNAPSHOT_HEADER_BYTES +
		            u64(index) * bridge.LAYOUT_NODE_RECORD_BYTES)
		racket_layout_encode_node(destination[base:], snapshot.nodes[index])
	}
	return required, true
}

@(private)
racket_layout_encode_node :: proc(destination: []u8, node: layout.Node_Descriptor) {
	record := bridge.Layout_Node_Record {
		kind = u64(node.kind),
		node_id = u64(node.node_id),
		slot_generation = u64(node.slot_generation),
		parent_id = u64(node.parent_id),
		depth = u64(node.depth),
		arrangement = u64(node.arrangement),
		first_child_id = u64(node.first_child_id),
		second_child_id = u64(node.second_child_id),
		first_weight = node.first_weight,
		second_weight = node.second_weight,
		view_registry_id = u64(node.view.registry_id),
		view_id = u64(node.view.view_id),
		view_generation = u64(node.view.generation),
		buffer_id = u64(node.buffer_id),
		entry_session_id = u64(node.entry.registry.session.session_id),
		entry_session_generation = u64(node.entry.registry.session.generation),
		entry_registry_generation = u64(node.entry.registry.generation),
		entry_id = u64(node.entry.entry_id),
		entry_slot = u64(node.entry.slot),
		entry_generation = u64(node.entry.generation),
		dedication = u64(node.dedication),
		history_count = u64(node.history_count),
		history_generation = node.history_generation,
		outer_row = racket_layout_signed(node.geometry.outer.row),
		outer_column = racket_layout_signed(node.geometry.outer.column),
		outer_height = racket_layout_signed(node.geometry.outer.height),
		outer_width = racket_layout_signed(node.geometry.outer.width),
		content_row = racket_layout_signed(node.geometry.content.row),
		content_column = racket_layout_signed(node.geometry.content.column),
		content_height = racket_layout_signed(node.geometry.content.height),
		content_width = racket_layout_signed(node.geometry.content.width),
		status_row = racket_layout_signed(node.geometry.status.row),
		status_column = racket_layout_signed(node.geometry.status.column),
		status_height = racket_layout_signed(node.geometry.status.height),
		status_width = racket_layout_signed(node.geometry.status.width),
		separator_row = racket_layout_signed(node.geometry.separator.row),
		separator_column = racket_layout_signed(node.geometry.separator.column),
		separator_height = racket_layout_signed(node.geometry.separator.height),
		separator_width = racket_layout_signed(node.geometry.separator.width),
		active = 1 if node.active else 0,
		mru_rank = u64(node.mru_rank),
	}
	racket_layout_record_pane(&record.pane_owner_id, node.pane)
	values := transmute([47]u64)record
	racket_buffer_session_encode_scalars(destination, values[:])
}

@(private)
racket_layout_encode_outcome :: proc(
	destination: []u8,
	result: Layout_Capability_Result,
) {
	record := bridge.Layout_Outcome_Record {
		scope = racket_layout_scope_record(result.scope),
		changed = 1 if result.changed else 0,
		partition_id = u64(result.partition_id),
		arrangement = u64(result.arrangement),
		delta = racket_layout_signed(result.delta),
		first_span = racket_layout_signed(result.first_span),
		second_span = racket_layout_signed(result.second_span),
		previous_dedication = u64(result.previous_dedication),
		current_dedication = u64(result.current_dedication),
	}
	racket_layout_record_pane(&record.primary_owner_id, result.primary)
	racket_layout_record_pane(&record.secondary_owner_id, result.secondary)
	values := transmute([28]u64)record
	racket_buffer_session_encode_scalars(destination, values[:])
}

@(private)
racket_layout_record_pane :: proc(first: ^u64, pane: layout.Pane_Handle) {
	values := ([^]u64)(first)[:6]
	values[0] = u64(pane.layout.owner_id)
	values[1] = u64(pane.layout.layout_id)
	values[2] = u64(pane.layout.generation)
	values[3] = u64(pane.pane_id)
	values[4] = u64(pane.slot)
	values[5] = u64(pane.slot_generation)
}

@(private)
racket_layout_signed :: proc(value: i32) -> u64 {
	return cast(u64)i64(value)
}

@(private)
racket_layout_reject :: proc(
	call: ^Racket_Layout_Call,
	failure: Failure_Context,
	failure_code: ^u32,
	limit, actual: ^u64,
) -> i32 {
	call.failure = failure
	code := u32(failure.code)
	if failure.layout_capability_code != .None {
		code = 256 + u32(failure.layout_capability_code)
	} else if failure.layout_code != .None {
		code = 512 + u32(failure.layout_code)
	}
	failure_code^ = code
	limit^ = failure.limit
	actual^ = failure.actual
	return 1
}

@(private)
racket_layout_token :: proc(scope: Layout_Capability_Scope) -> u64 {
	token := u64(scope.layout_handle.owner_id) ~ (u64(scope.layout_handle.layout_id) << 1) ~
	         (u64(scope.layout_handle.generation) << 7) ~ (u64(scope.pane.pane_id) << 13) ~
	         (u64(scope.pane.slot_generation) << 19)
	if token == 0 {
		return 1
	}
	return token
}
