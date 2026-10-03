// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../bridge"
import "../hosting"
import "../ui"
import endian "core:encoding/endian"
import "core:unicode/utf8"
import base_runtime "base:runtime"

/* UI_Role_Command_Procedure dispatches one previously admitted copied command. */
UI_Role_Command_Procedure :: proc(
	user_data: rawptr,
	role: ui.Role,
	provider: ui.Role_Provider_Handle,
	command_name: string,
) -> bool

/* Racket_UI_Role_Result reports the final provider scope after one Racket turn. */
Racket_UI_Role_Result :: struct {
	role:  ui.Role,
	scope: ui.Role_Scope,
	calls: u16,
}

@(private)
Racket_UI_Role_Call :: struct {
	roles:            ^ui.Role_Registry,
	ui_registry:      ^ui.Registry,
	renderer:         ui.Renderer_Profile,
	token:            u64,
	last_role:        ui.Role,
	last_scope:       ui.Role_Scope,
	command:          UI_Role_Command_Procedure,
	command_user_data: rawptr,
	calls:            u16,
	failure:          ui.Role_Failure,
}

@(private)
Decoded_UI_Role_Request :: struct {
	expected_scope:       bridge.UI_Role_Scope_Record,
	operation:            bridge.UI_Role_Operation,
	role:                 ui.Role,
	expected_provider_id: ui.Role_Provider_ID,
	expected_provider_generation: ui.Role_Provider_Generation,
	provider_id:          ui.Role_Provider_ID,
	provider_generation:  ui.Role_Provider_Generation,
	provider_kind:        bridge.UI_Role_Provider_Kind,
	proposal_root_generation: ui.Root_Generation,
	requirements:         ui.Renderer_Capabilities,
	name:                 string,
	package_name:         string,
	content:              []u8,
	command_name:         string,
	callback_budget:      u16,
}

/* racket_ui_role_turn lends checked session-scoped role authority to Racket. */
racket_ui_role_turn :: proc(
	racket_runtime: ^hosting.Runtime,
	roles: ^ui.Role_Registry,
	ui_registry: ^ui.Registry,
	renderer: ui.Renderer_Profile,
	scenario: i32,
	command: UI_Role_Command_Procedure = nil,
	command_user_data: rawptr = nil,
) -> (result: Racket_UI_Role_Result, ok: bool, failure: ui.Role_Failure) {
	if racket_runtime == nil || roles == nil || ui_registry == nil ||
	   !ui.renderer_profile_is_valid(renderer) {
		return {}, false, ui.Role_Failure {
			operation = .Inspect,
			code = .Invalid_Registry,
		}
	}
	stats, inspected, stats_failure := ui.role_registry_stats(roles)
	if !inspected {
		return {}, false, stats_failure
	}
	token := u64(stats.session_id) ~ (u64(stats.session_generation) << 32)
	if token == 0 {
		token = 1
	}
	call := Racket_UI_Role_Call {
		roles = roles,
		ui_registry = ui_registry,
		renderer = renderer,
		token = token,
		command = command,
		command_user_data = command_user_data,
	}
	executed, runtime_failure := hosting.runtime_ui_role_probe(
		racket_runtime,
		scenario,
		token,
		racket_ui_role_callback,
		&call,
	)
	if !executed {
		if call.last_role >= .Startup && call.last_role <= .Status &&
		   call.last_scope.active.provider_id != ui.Role_Provider_ID(0) &&
		   call.last_scope.active != call.last_scope.fallback {
			_, _, _ = ui.role_registry_fail_package(
				roles,
				call.last_scope,
				call.last_scope.active,
			)
		}
		return {}, false, ui.Role_Failure {
			operation = .Inspect,
			code = .Invalid_Registry,
			actual = u64(runtime_failure.code),
		}
	}
	if call.failure.code != .None {
		return {}, false, call.failure
	}
	return Racket_UI_Role_Result {
		role = call.last_role,
		scope = call.last_scope,
		calls = call.calls,
	}, true, {}
}

@(private)
racket_ui_role_callback :: proc "c" (
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
	call := (^Racket_UI_Role_Call)(user_data)
	if call == nil || kind != .UI_Role || generation == 0 || domain_context != 0 ||
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
	op := bridge.UI_Role_Operation(operation)
	role, role_ok := racket_ui_role_from_code(arg0)
	if !role_ok {
		return 2
	}
	call.calls += 1
	call.last_role = role

	if op == .Scope {
		if input_length != 0 || arg1 != 0 ||
		   output_capacity != bridge.UI_ROLE_SCOPE_RECORD_BYTES {
			return 2
		}
		scope, scoped, scope_failure := ui.role_registry_scope(call.roles, role)
		if !scoped {
			return racket_ui_role_reject(call, scope_failure, failure_code, limit, actual)
		}
		written, encoded := racket_ui_role_encode_scope(
			destination,
			call,
			scope,
			generation,
		)
		if !encoded {
			return 2
		}
		call.last_scope = scope
		output_length^ = written
		return 0
	}

	if input_length < bridge.UI_ROLE_SCOPE_RECORD_BYTES {
		return 2
	}
	expected, decoded := racket_ui_role_decode_scope(input_bytes)
	if !decoded {
		return 2
	}
	current, current_ok, current_failure := ui.role_registry_scope(call.roles, role)
	if !current_ok {
		return racket_ui_role_reject(call, current_failure, failure_code, limit, actual)
	}
	if !racket_ui_role_scope_matches(call, expected, current, generation) {
		return racket_ui_role_reject(
			call,
			ui.Role_Failure {
				operation = .Inspect,
				code = .Stale_Scope,
				role = role,
			},
			failure_code,
			limit,
			actual,
		)
	}
	if current.active != current.fallback {
		active_provider, active_ok, active_failure := ui.role_registry_provider(
			call.roles,
			current.active,
		)
		if !active_ok {
			return racket_ui_role_reject(call, active_failure, failure_code, limit, actual)
		}
		if active_provider.callback_budget > 0 && call.calls > active_provider.callback_budget {
			_, _, _ = ui.role_registry_fail_package(call.roles, current, current.active)
			budget_failure := ui.Role_Failure {
				operation = .Fail,
				code = .Callback_Budget,
				role = role,
				provider = current.active,
				limit = u64(active_provider.callback_budget),
				actual = u64(call.calls),
			}
			return racket_ui_role_reject(
				call,
				budget_failure,
				failure_code,
				limit,
				actual,
			)
		}
	}

	if op == .Snapshot {
		if arg1 != 0 {
			return 2
		}
		written, snapshot_ok, snapshot_failure := racket_ui_role_encode_snapshot(
			destination,
			call,
			current,
			generation,
		)
		if !snapshot_ok {
			return racket_ui_role_reject(
				call,
				snapshot_failure,
				failure_code,
				limit,
				actual,
			)
		}
		call.last_scope = current
		output_length^ = written
		return 0
	}

	if op == .Inspect_Provider {
		provider, inspected, inspect_failure := ui.role_registry_provider_by_id(
			call.roles,
			role,
			ui.Role_Provider_ID(arg1),
		)
		if !inspected {
			return racket_ui_role_reject(call, inspect_failure, failure_code, limit, actual)
		}
		written, encoded := racket_ui_role_encode_provider(destination, provider)
		if !encoded {
			return 2
		}
		call.last_scope = current
		output_length^ = written
		return 0
	}

	if op == .Rollback {
		outcome, rolled_back, rollback_failure := ui.role_registry_rollback(
			call.roles,
			current,
		)
		if !rolled_back {
			return racket_ui_role_reject(call, rollback_failure, failure_code, limit, actual)
		}
		written, encoded := racket_ui_role_encode_outcome(
			destination,
			call,
			outcome,
			generation,
		)
		if !encoded {
			return 2
		}
		call.last_scope = outcome.scope
		output_length^ = written
		return 0
	}

	request, request_ok := racket_ui_role_decode_request(input_bytes, op, role)
	if !request_ok {
		return 2
	}
	switch op {
	case .Propose:
		return racket_ui_role_propose(
			call,
			request,
			generation,
			destination,
			output_length,
			failure_code,
			limit,
			actual,
		)
	case .Activate:
		provider, provider_ok, provider_failure := racket_ui_role_request_provider(
			call,
			request,
		)
		if !provider_ok {
			return racket_ui_role_reject(call, provider_failure, failure_code, limit, actual)
		}
		outcome, activated, activation_failure := ui.role_registry_activate_package(
			call.roles,
			call.ui_registry,
			current,
			provider.handle,
			call.renderer,
		)
		if !activated {
			return racket_ui_role_reject(call, activation_failure, failure_code, limit, actual)
		}
		written, encoded := racket_ui_role_encode_outcome(
			destination,
			call,
			outcome,
			generation,
		)
		if !encoded {
			return 2
		}
		call.last_scope = outcome.scope
		output_length^ = written
		return 0
	case .Replace:
		provider, provider_ok, provider_failure := racket_ui_role_request_provider(
			call,
			request,
		)
		if !provider_ok {
			return racket_ui_role_reject(call, provider_failure, failure_code, limit, actual)
		}
		proposal := racket_ui_role_native_proposal(call, current, provider.handle, request)
		outcome, replaced, replace_failure := ui.role_registry_replace_package(
			call.roles,
			call.ui_registry,
			proposal,
		)
		if !replaced {
			return racket_ui_role_reject(call, replace_failure, failure_code, limit, actual)
		}
		written, encoded := racket_ui_role_encode_outcome(
			destination,
			call,
			outcome,
			generation,
		)
		if !encoded {
			return 2
		}
		call.last_scope = outcome.scope
		output_length^ = written
		return 0
	case .Teardown:
		provider, provider_ok, provider_failure := racket_ui_role_request_provider(
			call,
			request,
		)
		if !provider_ok {
			return racket_ui_role_reject(call, provider_failure, failure_code, limit, actual)
		}
		outcome, torn_down, teardown_failure := ui.role_registry_teardown_package(
			call.roles,
			current,
			provider.handle,
		)
		if !torn_down {
			return racket_ui_role_reject(call, teardown_failure, failure_code, limit, actual)
		}
		written, encoded := racket_ui_role_encode_outcome(
			destination,
			call,
			outcome,
			generation,
		)
		if !encoded {
			return 2
		}
		call.last_scope = outcome.scope
		output_length^ = written
		return 0
	case .Invoke_Command:
		provider, provider_ok, provider_failure := racket_ui_role_request_provider(
			call,
			request,
		)
		if !provider_ok {
			return racket_ui_role_reject(call, provider_failure, failure_code, limit, actual)
		}
		admitted, admission_failure := ui.role_registry_command_is_admitted(
			call.roles,
			provider.handle,
			request.command_name,
		)
		if !admitted {
			return racket_ui_role_reject(call, admission_failure, failure_code, limit, actual)
		}
		if call.command == nil ||
		   !call.command(call.command_user_data, role, provider.handle, request.command_name) {
			failure := ui.Role_Failure {
				operation = .Inspect,
				code = .Command_Not_Admitted,
				role = role,
				provider = provider.handle,
			}
			return racket_ui_role_reject(call, failure, failure_code, limit, actual)
		}
		outcome := ui.Role_Activation_Outcome {
			scope = current,
			previous = current.active,
			provider = current.active,
			confirmed_root = provider.confirmed_root,
		}
		written, encoded := racket_ui_role_encode_outcome(
			destination,
			call,
			outcome,
			generation,
		)
		if !encoded {
			return 2
		}
		call.last_scope = current
		output_length^ = written
		return 0
	case .Scope, .Snapshot, .Inspect_Provider, .Rollback:
		return 2
	}
	return 2
}

@(private)
racket_ui_role_propose :: proc(
	call: ^Racket_UI_Role_Call,
	request: Decoded_UI_Role_Request,
	generation: u64,
	destination: []u8,
	output_length: ^u64,
	failure_code: ^u32,
	limit, actual: ^u64,
) -> i32 {
	if request.provider_id != ui.Role_Provider_ID(0) ||
	   request.provider_generation != ui.Role_Provider_Generation(0) ||
	   request.provider_kind != .Package || len(request.name) == 0 ||
	   len(request.package_name) == 0 || len(request.content) == 0 {
		return 2
	}
	registered, added, add_failure := ui.role_registry_register_package(
		call.roles,
		request.role,
		request.name,
		request.package_name,
		request.requirements,
	)
	if !added {
		return racket_ui_role_reject(call, add_failure, failure_code, limit, actual)
	}
	current, current_ok, current_failure := ui.role_registry_scope(call.roles, request.role)
	if !current_ok {
		return racket_ui_role_reject(call, current_failure, failure_code, limit, actual)
	}
	proposal := racket_ui_role_native_proposal(call, current, registered, request)
	confirmed, confirmed_ok, confirmation_failure := ui.role_registry_confirm_package(
		call.roles,
		call.ui_registry,
		proposal,
	)
	if !confirmed_ok {
		return racket_ui_role_reject(call, confirmation_failure, failure_code, limit, actual)
	}
	final_scope, final_ok, final_failure := ui.role_registry_scope(call.roles, request.role)
	if !final_ok {
		return racket_ui_role_reject(call, final_failure, failure_code, limit, actual)
	}
	outcome := ui.Role_Activation_Outcome {
		scope = final_scope,
		previous = request_scope_active(request.expected_scope),
		provider = confirmed,
		confirmed_root = proposal.expected_root.generation,
	}
	written, encoded := racket_ui_role_encode_outcome(
		destination,
		call,
		outcome,
		generation,
	)
	if !encoded {
		return 2
	}
	call.last_scope = final_scope
	output_length^ = written
	return 0
}

@(private)
racket_ui_role_native_proposal :: proc(
	call: ^Racket_UI_Role_Call,
	scope: ui.Role_Scope,
	provider: ui.Role_Provider_Handle,
	request: Decoded_UI_Role_Request,
) -> ui.Role_Provider_Proposal {
	root, _, _ := ui.registry_handle(call.ui_registry)
	return ui.Role_Provider_Proposal {
		expected_scope = scope,
		provider = provider,
		expected_root = root,
		renderer = call.renderer,
		proposal_bytes = u64(len(request.content)),
		callback_budget = request.callback_budget,
		command_name = request.command_name,
	}
}

@(private)
racket_ui_role_request_provider :: proc(
	call: ^Racket_UI_Role_Call,
	request: Decoded_UI_Role_Request,
) -> (provider: ui.Role_Provider_View, ok: bool, failure: ui.Role_Failure) {
	provider, ok, failure = ui.role_registry_provider_by_id(
		call.roles,
		request.role,
		request.provider_id,
	)
	if !ok {
		return provider, false, failure
	}
	if provider.handle.provider_generation != request.provider_generation {
		return {}, false, ui.Role_Failure {
			operation = .Inspect,
			code = .Stale_Provider,
			role = request.role,
			provider = provider.handle,
		}
	}
	return provider, true, {}
}

@(private)
racket_ui_role_decode_request :: proc(
	input: []u8,
	operation: bridge.UI_Role_Operation,
	role: ui.Role,
) -> (request: Decoded_UI_Role_Request, ok: bool) {
	if len(input) < int(bridge.UI_ROLE_REQUEST_HEADER_BYTES) {
		return {}, false
	}
	request.expected_scope, ok = racket_ui_role_decode_scope(input)
	if !ok || read_ui_u64(input, 96) != u64(operation) ||
	   read_ui_u64(input, 104) != u64(role) {
		return {}, false
	}
	request.operation = operation
	request.role = role
	request.expected_provider_id = ui.Role_Provider_ID(read_ui_u64(input, 112))
	request.expected_provider_generation = ui.Role_Provider_Generation(read_ui_u64(input, 120))
	request.provider_id = ui.Role_Provider_ID(read_ui_u64(input, 128))
	request.provider_generation = ui.Role_Provider_Generation(read_ui_u64(input, 136))
	request.provider_kind = bridge.UI_Role_Provider_Kind(read_ui_u64(input, 144))
	request.proposal_root_generation = ui.Root_Generation(read_ui_u64(input, 152))
	for offset := 160; offset < 232; offset += 8 {
		if read_ui_u64(input, offset) != 0 {
			return {}, false
		}
	}
	requirement_count := read_ui_u64(input, 232)
	name_bytes := read_ui_u64(input, 240)
	package_bytes := read_ui_u64(input, 248)
	content_bytes := read_ui_u64(input, 256)
	command_bytes := read_ui_u64(input, 264)
	callback_budget := read_ui_u64(input, 272)
	if requirement_count > bridge.MAX_UI_ROLE_CAPABILITY_REQUIREMENTS ||
	   callback_budget > u64(max(u16)) {
		return {}, false
	}
	required, required_ok := bridge.ui_role_request_record_bytes(
		0,
		0,
		0,
		0,
		0,
		0,
		0,
		0,
		0,
		requirement_count,
		name_bytes,
		package_bytes,
		content_bytes,
		command_bytes,
	)
	if !required_ok || required != u64(len(input)) {
		return {}, false
	}
	cursor := bridge.UI_ROLE_REQUEST_HEADER_BYTES
	for _ in 0..<requirement_count {
		capability_code := read_ui_u64(input, int(cursor))
		required_value := read_ui_u64(input, int(cursor + 8))
		if capability_code > u64(ui.Renderer_Capability.Full_Redraw) ||
		   required_value != 1 {
			return {}, false
		}
		request.requirements |= {ui.Renderer_Capability(capability_code)}
		cursor += bridge.UI_ROLE_CAPABILITY_REQUIREMENT_RECORD_BYTES
	}
	name_end := cursor + name_bytes
	package_end := name_end + package_bytes
	content_end := package_end + content_bytes
	command_end := content_end + command_bytes
	request.name = string(input[int(cursor):int(name_end)])
	request.package_name = string(input[int(name_end):int(package_end)])
	request.content = input[int(package_end):int(content_end)]
	request.command_name = string(input[int(content_end):int(command_end)])
	request.callback_budget = u16(callback_budget)
	if !utf8.valid_string(request.name) || !utf8.valid_string(request.package_name) ||
	   !utf8.valid_string(request.command_name) {
		return {}, false
	}
	return request, true
}

@(private)
racket_ui_role_encode_scope :: proc(
	destination: []u8,
	call: ^Racket_UI_Role_Call,
	scope: ui.Role_Scope,
	capability_generation: u64,
) -> (written: u64, ok: bool) {
	if len(destination) < int(bridge.UI_ROLE_SCOPE_RECORD_BYTES) {
		return 0, false
	}
	root, root_ok, _ := ui.registry_handle(call.ui_registry)
	if !root_ok {
		return 0, false
	}
	values := [?]u64 {
		bridge.UI_ROLE_CAPABILITY_SCHEMA_VERSION,
		0x7f,
		u64(scope.session_id),
		u64(scope.session_generation),
		u64(root.registry_id),
		u64(root.generation),
		u64(scope.registry_generation),
		u64(scope.role),
		u64(scope.active.provider_id),
		u64(scope.active.provider_generation),
		u64(call.renderer.id),
		capability_generation,
	}
	for item, index in values {
		write_ui_u64(destination, index * 8, item)
	}
	return bridge.UI_ROLE_SCOPE_RECORD_BYTES, true
}

@(private)
racket_ui_role_decode_scope :: proc(input: []u8) -> (scope: bridge.UI_Role_Scope_Record, ok: bool) {
	if len(input) < int(bridge.UI_ROLE_SCOPE_RECORD_BYTES) {
		return {}, false
	}
	fields := (^bridge.UI_Role_Scope_Record)(&scope)
	values := ([^]u64)(fields)[:12]
	for &item, index in values {
		item = read_ui_u64(input, index * 8)
	}
	return scope, true
}

@(private)
racket_ui_role_scope_matches :: proc(
	call: ^Racket_UI_Role_Call,
	expected: bridge.UI_Role_Scope_Record,
	current: ui.Role_Scope,
	capability_generation: u64,
) -> bool {
	root, root_ok, _ := ui.registry_handle(call.ui_registry)
	return root_ok && expected.schema_version == bridge.UI_ROLE_CAPABILITY_SCHEMA_VERSION &&
	       expected.session_id == u64(current.session_id) &&
	       expected.session_generation == u64(current.session_generation) &&
	       expected.ui_registry_id == u64(root.registry_id) &&
	       expected.root_generation == u64(root.generation) &&
	       expected.role_registry_generation == u64(current.registry_generation) &&
	       expected.role == u64(current.role) &&
	       expected.provider_id == u64(current.active.provider_id) &&
	       expected.provider_generation == u64(current.active.provider_generation) &&
	       expected.renderer_profile_id == u64(call.renderer.id) &&
	       expected.capability_generation == capability_generation
}

@(private)
racket_ui_role_encode_provider :: proc(
	destination: []u8,
	provider: ui.Role_Provider_View,
) -> (written: u64, ok: bool) {
	requirement_count: u64
	for capability in ui.Renderer_Capability {
		if capability in provider.required_capabilities {
			requirement_count += 1
		}
	}
	required := bridge.UI_ROLE_PROVIDER_RECORD_BYTES +
	            requirement_count * bridge.UI_ROLE_CAPABILITY_REQUIREMENT_RECORD_BYTES +
	            u64(len(provider.name)) + u64(len(provider.package_name))
	if required > u64(len(destination)) {
		return 0, false
	}
	requirement_offset := bridge.UI_ROLE_PROVIDER_RECORD_BYTES
	name_offset := requirement_offset +
	               requirement_count * bridge.UI_ROLE_CAPABILITY_REQUIREMENT_RECORD_BYTES
	package_offset := name_offset + u64(len(provider.name))
	values := [?]u64 {
		u64(provider.handle.role),
		u64(provider.handle.provider_id),
		u64(provider.handle.provider_generation),
		u64(provider.kind),
		u64(provider.state),
		requirement_offset,
		requirement_count,
		name_offset,
		u64(len(provider.name)),
		package_offset,
		u64(len(provider.package_name)),
		u64(provider.confirmed_root),
	}
	for item, index in values {
		write_ui_u64(destination, index * 8, item)
	}
	cursor := requirement_offset
	for capability in ui.Renderer_Capability {
		if capability in provider.required_capabilities {
			write_ui_u64(destination, int(cursor), u64(capability))
			write_ui_u64(destination, int(cursor + 8), 1)
			cursor += bridge.UI_ROLE_CAPABILITY_REQUIREMENT_RECORD_BYTES
		}
	}
	copy(destination[int(name_offset):], transmute([]u8)provider.name)
	copy(destination[int(package_offset):], transmute([]u8)provider.package_name)
	return required, true
}

@(private)
racket_ui_role_encode_outcome :: proc(
	destination: []u8,
	call: ^Racket_UI_Role_Call,
	outcome: ui.Role_Activation_Outcome,
	capability_generation: u64,
) -> (written: u64, ok: bool) {
	if len(destination) != int(bridge.UI_ROLE_OUTCOME_RECORD_BYTES) {
		return 0, false
	}
	_, scope_ok := racket_ui_role_encode_scope(
		destination,
		call,
		outcome.scope,
		capability_generation,
	)
	if !scope_ok {
		return 0, false
	}
	values := [?]u64 {
		u64(outcome.previous.provider_id),
		u64(outcome.previous.provider_generation),
		u64(outcome.provider.provider_id),
		u64(outcome.provider.provider_generation),
		u64(outcome.confirmed_root),
		u64(outcome.changed),
		u64(outcome.fallback_selected),
		0,
		0,
		0,
		u64(call.calls),
	}
	for item, index in values {
		write_ui_u64(destination, 96 + index * 8, item)
	}
	return bridge.UI_ROLE_OUTCOME_RECORD_BYTES, true
}

@(private)
racket_ui_role_encode_snapshot :: proc(
	destination: []u8,
	call: ^Racket_UI_Role_Call,
	scope: ui.Role_Scope,
	capability_generation: u64,
) -> (written: u64, ok: bool, failure: ui.Role_Failure) {
	root, root_ok, _ := ui.registry_handle(call.ui_registry)
	if !root_ok {
		return 0, false, ui.Role_Failure{operation = .Inspect, code = .Stale_Root, role = scope.role}
	}
	snapshot, copied, _ := ui.registry_snapshot(
		call.ui_registry,
		root,
		call.renderer,
		context.temp_allocator,
	)
	if !copied {
		return 0, false, ui.Role_Failure{operation = .Inspect, code = .Allocation, role = scope.role}
	}
	defer ui.snapshot_close(&snapshot)
	view, viewed := ui.snapshot_view(&snapshot)
	if !viewed {
		return 0, false, ui.Role_Failure{operation = .Inspect, code = .Allocation, role = scope.role}
	}
	providers: [2]ui.Role_Provider_View
	provider_count := 0
	active, active_ok, _ := ui.role_registry_provider(call.roles, scope.active)
	if active_ok {
		providers[provider_count] = active
		provider_count += 1
	}
	if scope.fallback != scope.active {
		fallback, fallback_ok, _ := ui.role_registry_provider(call.roles, scope.fallback)
		if fallback_ok {
			providers[provider_count] = fallback
			provider_count += 1
		}
	}
	requirement_count: u64
	provider_text_bytes: u64
	for provider in providers[:provider_count] {
		provider_text_bytes += u64(len(provider.name) + len(provider.package_name))
		for capability in ui.Renderer_Capability {
			if capability in provider.required_capabilities {
				requirement_count += 1
			}
		}
	}
	content_bytes := u64(len(view.list_content) + len(view.input_content) +
	                     len(view.compact_content)) + provider_text_bytes
	required, size_ok := bridge.ui_role_snapshot_record_bytes(
		u64(len(view.projections)),
		u64(len(view.views)),
		u64(len(view.list_items)),
		u64(len(view.input_choices)),
		u64(len(view.surfaces)),
		u64(len(view.composition)),
		u64(len(view.status_regions)),
		u64(len(view.styles)),
		u64(len(view.decorations)),
		u64(provider_count),
		requirement_count,
		content_bytes,
	)
	if !size_ok || required > u64(len(destination)) {
		return 0, false, ui.Role_Failure {
			operation = .Inspect,
			code = .Proposal_Limit,
			role = scope.role,
			limit = u64(len(destination)),
			actual = required,
		}
	}
	for &byte in destination[:int(required)] {
		byte = 0
	}
	_, scope_encoded := racket_ui_role_encode_scope(
		destination,
		call,
		scope,
		capability_generation,
	)
	if !scope_encoded {
		return 0, false, ui.Role_Failure{operation = .Inspect, code = .Invalid_Registry}
	}
	racket_ui_role_write_handle(destination, 96, view.root_node)
	racket_ui_role_write_handle(destination, 136, view.focus.target)
	write_ui_u64(destination, 176, u64(view.focus.captured))
	racket_ui_role_write_handle(destination, 184, view.focus.return_target)
	header_values := [?]u64 {
		u64(len(view.projections)),
		u64(len(view.views)),
		u64(len(view.list_items)),
		u64(len(view.input_choices)),
		u64(len(view.surfaces)),
		u64(len(view.composition)),
		u64(len(view.status_regions)),
		u64(len(view.styles)),
		u64(len(view.decorations)),
		u64(provider_count),
		requirement_count,
		content_bytes,
		view.accounting.registry_bytes + view.accounting.projection_bytes +
			view.accounting.compact_region_bytes,
		view.accounting.temporary_peak_bytes,
	}
	for item, index in header_values {
		write_ui_u64(destination, 224 + index * 8, item)
	}
	cursor := bridge.UI_ROLE_SNAPSHOT_HEADER_BYTES
	for projection in view.projections {
		racket_ui_role_encode_projection(destination, int(cursor), projection)
		cursor += bridge.UI_ROLE_PROJECTION_RECORD_BYTES
	}
	for visual in view.views {
		racket_ui_role_encode_view(destination, int(cursor), visual)
		cursor += bridge.UI_ROLE_VIEW_RECORD_BYTES
	}
	content_base := required - content_bytes
	list_base := content_base
	input_base := list_base + u64(len(view.list_content))
	compact_base := input_base + u64(len(view.input_content))
	for item in view.list_items {
		racket_ui_role_encode_list_item(destination, int(cursor), item, list_base)
		cursor += bridge.UI_ROLE_LIST_ITEM_RECORD_BYTES
	}
	for choice in view.input_choices {
		racket_ui_role_encode_input_choice(destination, int(cursor), choice, input_base)
		cursor += bridge.UI_ROLE_INPUT_CHOICE_RECORD_BYTES
	}
	for surface in view.surfaces {
		racket_ui_role_encode_surface(destination, int(cursor), surface)
		cursor += bridge.UI_ROLE_SURFACE_RECORD_BYTES
	}
	for composition in view.composition {
		racket_ui_role_encode_composition(destination, int(cursor), composition)
		cursor += bridge.UI_ROLE_COMPOSITION_RECORD_BYTES
	}
	for status in view.status_regions {
		racket_ui_role_encode_status(destination, int(cursor), status, compact_base)
		cursor += bridge.UI_ROLE_STATUS_RECORD_BYTES
	}
	for style in view.styles {
		racket_ui_role_encode_style(destination, int(cursor), style)
		cursor += bridge.UI_ROLE_STYLE_RECORD_BYTES
	}
	for decoration in view.decorations {
		racket_ui_role_encode_decoration(destination, int(cursor), decoration)
		cursor += bridge.UI_ROLE_DECORATION_RECORD_BYTES
	}
	provider_base := cursor
	requirement_base := provider_base +
	                    u64(provider_count) * bridge.UI_ROLE_PROVIDER_RECORD_BYTES
	provider_content_cursor := compact_base + u64(len(view.compact_content))
	requirement_cursor := requirement_base
	for provider, index in providers[:provider_count] {
		provider_requirement_count: u64
		for capability in ui.Renderer_Capability {
			if capability in provider.required_capabilities {
				provider_requirement_count += 1
			}
		}
		name_offset := provider_content_cursor
		package_offset := name_offset + u64(len(provider.name))
		racket_ui_role_encode_snapshot_provider(
			destination,
			int(provider_base + u64(index) * bridge.UI_ROLE_PROVIDER_RECORD_BYTES),
			provider,
			requirement_cursor,
			provider_requirement_count,
			name_offset,
			package_offset,
		)
		for capability in ui.Renderer_Capability {
			if capability in provider.required_capabilities {
				write_ui_u64(destination, int(requirement_cursor), u64(capability))
				write_ui_u64(destination, int(requirement_cursor + 8), 1)
				requirement_cursor += bridge.UI_ROLE_CAPABILITY_REQUIREMENT_RECORD_BYTES
			}
		}
		copy(destination[int(name_offset):], transmute([]u8)provider.name)
		copy(destination[int(package_offset):], transmute([]u8)provider.package_name)
		provider_content_cursor = package_offset + u64(len(provider.package_name))
	}
	copy(destination[int(list_base):], view.list_content)
	copy(destination[int(input_base):], view.input_content)
	copy(destination[int(compact_base):], view.compact_content)
	return required, true, {}
}

@(private)
racket_ui_role_encode_projection :: proc(destination: []u8, offset: int, item: ui.Projection_Descriptor) {
	racket_ui_role_write_handle(destination, offset, item.handle)
	values := [?]u64 {
		u64(item.model.owner_id), u64(item.model.model_id), u64(item.model.generation),
		item.byte_count, u64(item.item_count), u64(item.read_only),
	}
	for value, index in values do write_ui_u64(destination, offset + 40 + index * 8, value)
}

@(private)
racket_ui_role_encode_view :: proc(destination: []u8, offset: int, item: ui.Visual_View_Descriptor) {
	racket_ui_role_write_handle(destination, offset, item.handle)
	write_ui_u64(destination, offset + 40, u64(item.kind))
	racket_ui_role_write_handle(destination, offset + 48, item.projection)
	write_ui_u64(destination, offset + 88, u64(item.read_only))
}

@(private)
racket_ui_role_encode_list_item :: proc(
	destination: []u8, offset: int, item: ui.List_Item_Descriptor, content_base: u64,
) {
	racket_ui_role_write_handle(destination, offset, item.projection)
	values := [?]u64 {
		u64(item.id), content_base + item.text_offset, u64(item.text_bytes),
		u64(item.action.owner_id), u64(item.action.action_id), item.action.generation,
		u64(item.mark), 0,
	}
	for value, index in values do write_ui_u64(destination, offset + 40 + index * 8, value)
}

@(private)
racket_ui_role_encode_input_choice :: proc(
	destination: []u8, offset: int, item: ui.Input_Choice_Descriptor, content_base: u64,
) {
	racket_ui_role_write_handle(destination, offset, item.projection)
	values := [?]u64 {
		u64(item.id), content_base + item.name_offset, u64(item.name_bytes),
		u64(item.action.owner_id), u64(item.action.action_id), item.action.generation,
	}
	for value, index in values do write_ui_u64(destination, offset + 40 + index * 8, value)
}

@(private)
racket_ui_role_encode_surface :: proc(destination: []u8, offset: int, item: ui.Surface_Descriptor) {
	racket_ui_role_write_handle(destination, offset, item.handle)
	write_ui_u64(destination, offset + 40, u64(item.owner_id))
	racket_ui_role_write_handle(destination, offset + 48, item.view)
	values := [?]u64 {
		u64(item.focusable), u64(item.visible), item.input_context, item.keymap_context,
		u64(item.required_profile), u64(i64(item.geometry.row)),
		u64(i64(item.geometry.column)), u64(i64(item.geometry.height)),
		u64(i64(item.geometry.width)),
	}
	for value, index in values do write_ui_u64(destination, offset + 88 + index * 8, value)
}

@(private)
racket_ui_role_encode_composition :: proc(
	destination: []u8, offset: int, item: ui.Composition_Descriptor,
) {
	racket_ui_role_write_handle(destination, offset, item.handle)
	write_ui_u64(destination, offset + 40, u64(item.kind))
	racket_ui_role_write_handle(destination, offset + 48, item.surface)
	racket_ui_role_write_handle(destination, offset + 88, item.first)
	racket_ui_role_write_handle(destination, offset + 128, item.second)
	write_ui_u64(destination, offset + 168, u64(item.orientation))
	write_ui_u64(destination, offset + 176, item.first_weight)
	write_ui_u64(destination, offset + 184, item.second_weight)
	write_ui_u64(destination, offset + 192, u64(item.depth))
}

@(private)
racket_ui_role_encode_status :: proc(
	destination: []u8, offset: int, item: ui.Status_Region_Descriptor, content_base: u64,
) {
	racket_ui_role_write_handle(destination, offset, item.handle)
	write_ui_u64(destination, offset + 40, u64(item.owner_id))
	write_ui_u64(destination, offset + 48, u64(item.placement))
	racket_ui_role_write_handle(destination, offset + 56, item.surface)
	values := [?]u64 {
		u64(item.rows), u64(i64(item.geometry.row)), u64(i64(item.geometry.column)),
		u64(i64(item.geometry.height)), u64(i64(item.geometry.width)),
		content_base + u64(item.content_offset), u64(item.content_bytes),
		u64(item.style_role), u64(item.active),
	}
	for value, index in values do write_ui_u64(destination, offset + 96 + index * 8, value)
}

@(private)
racket_ui_role_encode_style :: proc(destination: []u8, offset: int, item: ui.Style_Descriptor) {
	racket_ui_role_write_handle(destination, offset, item.handle)
	write_ui_u64(destination, offset + 40, u64(item.role))
	write_ui_u64(destination, offset + 48, u64(transmute(u8)item.attributes))
}

@(private)
racket_ui_role_encode_decoration :: proc(
	destination: []u8, offset: int, item: ui.Decoration_Descriptor,
) {
	racket_ui_role_write_handle(destination, offset, item.handle)
	write_ui_u64(destination, offset + 40, u64(item.owner_id))
	write_ui_u64(destination, offset + 48, u64(item.kind))
	racket_ui_role_write_handle(destination, offset + 56, item.projection)
	write_ui_u64(destination, offset + 96, item.start)
	write_ui_u64(destination, offset + 104, item.end)
	write_ui_u64(destination, offset + 112, u64(item.style_role))
}

@(private)
racket_ui_role_encode_snapshot_provider :: proc(
	destination: []u8,
	offset: int,
	provider: ui.Role_Provider_View,
	requirement_offset, requirement_count, name_offset, package_offset: u64,
) {
	values := [?]u64 {
		u64(provider.handle.role), u64(provider.handle.provider_id),
		u64(provider.handle.provider_generation), u64(provider.kind), u64(provider.state),
		requirement_offset, requirement_count, name_offset, u64(len(provider.name)),
		package_offset, u64(len(provider.package_name)), u64(provider.confirmed_root),
	}
	for value, index in values do write_ui_u64(destination, offset + index * 8, value)
}

@(private)
racket_ui_role_write_handle :: proc(destination: []u8, offset: int, handle: ui.Object_Handle) {
	values := [?]u64 {
		u64(handle.registry_id), u64(handle.object_id), u64(handle.root_generation),
		u64(handle.slot), u64(handle.slot_generation),
	}
	for value, index in values do write_ui_u64(destination, offset + index * 8, value)
}

@(private)
racket_ui_role_from_code :: proc(code: u64) -> (role: ui.Role, ok: bool) {
	if code < u64(ui.Role.Startup) || code > u64(ui.Role.Status) {
		return .Invalid, false
	}
	return ui.Role(code), true
}

@(private)
request_scope_active :: proc(scope: bridge.UI_Role_Scope_Record) -> ui.Role_Provider_Handle {
	return ui.Role_Provider_Handle {
		session_id = ui.Role_Session_ID(scope.session_id),
		session_generation = ui.Role_Session_Generation(scope.session_generation),
		role = ui.Role(scope.role),
		provider_id = ui.Role_Provider_ID(scope.provider_id),
		provider_generation = ui.Role_Provider_Generation(scope.provider_generation),
	}
}

@(private)
racket_ui_role_reject :: proc(
	call: ^Racket_UI_Role_Call,
	failure: ui.Role_Failure,
	failure_code: ^u32,
	limit, actual: ^u64,
) -> i32 {
	call.failure = failure
	failure_code^ = u32(failure.code)
	limit^ = failure.limit
	actual^ = failure.actual
	return 1
}

@(private)
read_ui_u64 :: proc(input: []u8, offset: int) -> u64 {
	value, ok := endian.get_u64(input[offset:], .Little)
	assert(ok)
	return value
}

@(private)
write_ui_u64 :: proc(destination: []u8, offset: int, value: u64) {
	written := endian.put_u64(destination[offset:], .Little, value)
	assert(written)
}
