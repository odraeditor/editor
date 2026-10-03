// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package hosting

import "../bridge"
import service "../language_service"
import runtime "base:runtime"
import "core:encoding/endian"
import json "core:encoding/json"
import "core:strings"

/* Language_Service_Provider_Capability lends one native registry to one hosted turn. */
Language_Service_Provider_Capability :: struct {
	registry:              ^service.Provider_Registry,
	token:                 u64,
	project_id:            u64,
	project_generation:    u64,
	membership_id:         u64,
	membership_generation: u64,
	search_path:           string,
	diagnostic_request:    Language_Service_Diagnostic_Command_Request,
}

/* Language_Service_Diagnostic_Command_Request is one accepted copied coordinator request. */
Language_Service_Diagnostic_Command_Request :: struct {
	command:               bridge.Language_Service_Diagnostic_Command,
	diagnostic_generation: u64,
	source_generation:     u64,
}

/* language_service_provider_capability_callback serves copied programmable operations. */
language_service_provider_capability_callback :: proc "c" (
	user_data: rawptr,
	kind: Scoped_Capability_Kind,
	generation, token, domain_context: u64,
	operation: i32,
	arg0, arg1: u64,
	input_pointer: ^u8,
	input_length: u64,
	output_pointer: ^u8,
	output_capacity: u64,
	output_length, value: ^u64,
	failure_code: ^u32,
	limit, actual: ^u64,
) -> i32 {
	context = runtime.default_context()
	capability := (^Language_Service_Provider_Capability)(user_data)
	if capability == nil || capability.registry == nil || kind != .Language_Service ||
	   generation == 0 || token == 0 || token != capability.token || domain_context != 0 ||
	   operation < i32(bridge.Language_Service_Capability_Operation.Scope) ||
	   operation > i32(bridge.Language_Service_Capability_Operation.Invoke_Diagnostic_Command) ||
	   arg0 != 0 || arg1 != 0 || output_length == nil || value == nil ||
	   failure_code == nil || limit == nil || actual == nil ||
	   input_length > bridge.MAX_LANGUAGE_SERVICE_PROPOSAL_BYTES ||
	   (input_length > 0 && input_pointer == nil) {
		return 2
	}
	output_length^ = 0
	value^ = 0
	failure_code^ = 0
	limit^ = 0
	actual^ = 0
	input := []u8{}
	if input_length > 0 do input = ([^]u8)(input_pointer)[:int(input_length)]
	output := []u8{}
	if output_capacity > 0 {
		if output_pointer == nil do return 2
		output = ([^]u8)(output_pointer)[:int(output_capacity)]
	}

	op := bridge.Language_Service_Capability_Operation(operation)
	if op == .Scope {
		if len(input) != 0 || len(output) != int(bridge.LANGUAGE_SERVICE_SCOPE_RECORD_BYTES) do return 2
		if !language_service_capability_write_scope(output, capability, generation) do return 2
		output_length^ = bridge.LANGUAGE_SERVICE_SCOPE_RECORD_BYTES
		return 0
	}
	if len(input) < int(bridge.LANGUAGE_SERVICE_SCOPE_RECORD_BYTES) ||
	   !language_service_capability_scope_matches(input, capability) {
		return language_service_capability_fail(
			service.Failure_Context{code = .Stale_Generation},
			failure_code, limit, actual,
		)
	}
	if op == .Invoke_Diagnostic_Command {
		return language_service_capability_request_diagnostic_command(
			capability, generation, input, output, output_length, failure_code, limit, actual,
		)
	}

	before, before_ok := service.provider_registry_inspect(capability.registry)
	if !before_ok do return language_service_capability_fail(
		service.Failure_Context{code = .Closed}, failure_code, limit, actual,
	)
	result := service.Definition_Handle{}
	changed := false
	failure := service.Failure_Context{}
	switch op {
	case .Propose:
		proposal, decoded, decode_failure := language_service_capability_decode_definition(input, op)
		if !decoded {
			failure = decode_failure
			break
		}
		result, changed, failure = service.provider_registry_propose(capability.registry, proposal)
	case .Confirm, .Select:
		result, changed = language_service_capability_definition_handle(input, capability.registry)
		if !changed {
			failure = service.Failure_Context{code = .Stale_Generation}
			break
		}
		if op == .Confirm {
			changed, failure = service.provider_registry_confirm(capability.registry, result)
		} else {
			changed, failure = service.provider_registry_select(capability.registry, result)
		}
	case .Disable:
		provider_id, id_ok := language_service_capability_u64(input, 176)
		provider_generation, generation_ok := language_service_capability_u64(input, 184)
		if !id_ok || !generation_ok {
			failure = service.Failure_Context{code = .Invalid_Provider}
			break
		}
		provider, resolved, resolve_failure := service.provider_registry_provider_handle(
			capability.registry,
			service.Provider_ID(provider_id),
			service.Provider_Generation(provider_generation),
		)
		if !resolved {
			failure = resolve_failure
			break
		}
		result = provider.definition
		changed, failure = service.provider_registry_disable(capability.registry, provider)
	case .Replace:
		proposal, decoded, decode_failure := language_service_capability_decode_definition(input, op)
		if !decoded {
			failure = decode_failure
			break
		}
		expected, expected_ok := language_service_capability_expected_handle(input, capability.registry)
		if !expected_ok {
			failure = service.Failure_Context{code = .Stale_Generation}
			break
		}
		result, changed, failure = service.provider_registry_replace(
			capability.registry,
			expected,
			proposal,
			service.Executable_Discovery{search_path = capability.search_path},
		)
	case .Restore:
		changed, failure = service.provider_registry_restore_factory(capability.registry)
		if changed {
			after, _ := service.provider_registry_inspect(capability.registry)
			result = after.active
		}
	case .Inspect, .Start, .Stop, .Restart:
		failure = service.Failure_Context{code = .Unsupported_Capability}
	case .Scope, .Invoke_Diagnostic_Command:
		return 2
	}
	if failure.code != .None {
		return language_service_capability_fail(failure, failure_code, limit, actual)
	}
	if len(output) != int(bridge.LANGUAGE_SERVICE_OUTCOME_RECORD_BYTES) do return 2
	if !language_service_capability_write_outcome(
		output, capability, generation, op, before.active, result, changed,
	) {
		return 2
	}
	output_length^ = bridge.LANGUAGE_SERVICE_OUTCOME_RECORD_BYTES
	return 0
}

/* language_service_provider_capability_take_diagnostic_command consumes one accepted request. */
language_service_provider_capability_take_diagnostic_command :: proc(
	capability: ^Language_Service_Provider_Capability,
) -> (request: Language_Service_Diagnostic_Command_Request, ok: bool) {
	if capability == nil || capability.diagnostic_request.command == .Invalid do return {}, false
	request = capability.diagnostic_request
	capability.diagnostic_request = {}
	return request, true
}

@(private = "file")
language_service_capability_request_diagnostic_command :: proc(
	capability: ^Language_Service_Provider_Capability,
	generation: u64,
	input, output: []u8,
	output_length: ^u64,
	failure_code: ^u32,
	limit, actual: ^u64,
) -> i32 {
	if len(input) != int(bridge.LANGUAGE_SERVICE_DIAGNOSTIC_COMMAND_RECORD_BYTES) ||
	   len(output) != int(bridge.LANGUAGE_SERVICE_DIAGNOSTIC_OUTCOME_RECORD_BYTES) {
		return 2
	}
	command_value, command_ok := language_service_capability_u64(input, 136)
	diagnostic_generation, diagnostic_ok := language_service_capability_u64(input, 144)
	source_generation, source_ok := language_service_capability_u64(input, 152)
	command := bridge.Language_Service_Diagnostic_Command(command_value)
	if !command_ok || !diagnostic_ok || !source_ok || command <= .Invalid ||
	   command > .Previous || diagnostic_generation == 0 || source_generation == 0 ||
	   capability.diagnostic_request.command != .Invalid {
		return language_service_capability_fail(
			service.Failure_Context{code = .Invalid_Input}, failure_code, limit, actual)
	}
	capability.diagnostic_request = {command = command,
		diagnostic_generation = diagnostic_generation, source_generation = source_generation}
	if !language_service_capability_write_scope(
		output[:int(bridge.LANGUAGE_SERVICE_SCOPE_RECORD_BYTES)], capability, generation) {
		capability.diagnostic_request = {}
		return 2
	}
	fields := [5]u64{command_value, diagnostic_generation, source_generation, 1, 0}
	for field, index in fields {
		if !endian.put_u64(output[136 + index * 8:], .Little, field) {
			capability.diagnostic_request = {}
			return 2
		}
	}
	output_length^ = bridge.LANGUAGE_SERVICE_DIAGNOSTIC_OUTCOME_RECORD_BYTES
	return 0
}

@(private = "file")
language_service_capability_fail :: proc(
	failure: service.Failure_Context,
	failure_code: ^u32,
	limit, actual: ^u64,
) -> i32 {
	failure_code^ = u32(failure.code)
	limit^ = failure.limit
	actual^ = failure.actual
	return 1
}

@(private = "file")
language_service_capability_scope_matches :: proc(
	input: []u8,
	capability: ^Language_Service_Provider_Capability,
) -> bool {
	inspection, inspected := service.provider_registry_inspect(capability.registry)
	if !inspected do return false
	registry_id, ok0 := language_service_capability_u64(input, 16)
	registry_generation, ok1 := language_service_capability_u64(input, 24)
	selection_generation, ok2 := language_service_capability_u64(input, 32)
	return ok0 && ok1 && ok2 &&
		registry_id == u64(inspection.handle.id) &&
		registry_generation == u64(inspection.handle.generation) &&
		selection_generation == inspection.selection_generation
}

@(private = "file")
language_service_capability_write_scope :: proc(
	output: []u8,
	capability: ^Language_Service_Provider_Capability,
	generation: u64,
) -> bool {
	inspection, inspected := service.provider_registry_inspect(capability.registry)
	if !inspected do return false
	active_provider_id, active_provider_generation: u64
	if inspection.active.id != service.Definition_ID(0) {
		view, viewed, _ := service.provider_registry_definition(capability.registry, inspection.active)
		if viewed {
			active_provider_id = u64(view.provider.handle.id)
			active_provider_generation = u64(view.provider.handle.generation)
		}
	}
	fields := [17]u64{
		bridge.LANGUAGE_SERVICE_CAPABILITY_SCHEMA_VERSION,
		0xffff,
		u64(inspection.handle.id),
		u64(inspection.handle.generation),
		inspection.selection_generation,
		active_provider_id,
		active_provider_generation,
		u64(inspection.active.id),
		u64(inspection.active.generation),
		0,
		0,
		capability.project_id,
		capability.project_generation,
		capability.membership_id,
		capability.membership_generation,
		capability.membership_generation,
		generation,
	}
	for field, index in fields {
		if !endian.put_u64(output[index * 8:], .Little, field) do return false
	}
	return true
}

@(private = "file")
language_service_capability_write_outcome :: proc(
	output: []u8,
	capability: ^Language_Service_Provider_Capability,
	generation: u64,
	operation: bridge.Language_Service_Capability_Operation,
	previous, result: service.Definition_Handle,
	changed: bool,
) -> bool {
	if !language_service_capability_write_scope(
		output[:int(bridge.LANGUAGE_SERVICE_SCOPE_RECORD_BYTES)], capability, generation,
	) {
		return false
	}
	previous_provider_id, previous_provider_generation: u64
	if previous.id != service.Definition_ID(0) {
		view, viewed, _ := service.provider_registry_definition(capability.registry, previous)
		if viewed {
			previous_provider_id = u64(view.provider.handle.id)
			previous_provider_generation = u64(view.provider.handle.generation)
		}
	}
	provider_id, provider_generation: u64
	if result.id != service.Definition_ID(0) {
		view, viewed, _ := service.provider_registry_definition(capability.registry, result)
		if viewed {
			provider_id = u64(view.provider.handle.id)
			provider_generation = u64(view.provider.handle.generation)
		}
	}
	inspection, _ := service.provider_registry_inspect(capability.registry)
	fields := [14]u64{
		u64(operation),
		1,
		1 if changed else 0,
		previous_provider_id,
		previous_provider_generation,
		u64(previous.id),
		u64(previous.generation),
		provider_id,
		provider_generation,
		u64(result.id),
		u64(result.generation),
		0,
		0,
		u64(service.Health.Stopped),
	}
	for field, index in fields {
		if !endian.put_u64(output[136 + index * 8:], .Little, field) do return false
	}
	return endian.put_u64(output[248:], .Little, inspection.usage.retained_bytes)
}

@(private = "file")
language_service_capability_definition_handle :: proc(
	input: []u8,
	registry: ^service.Provider_Registry,
) -> (service.Definition_Handle, bool) {
	inspection, inspected := service.provider_registry_inspect(registry)
	if !inspected do return {}, false
	id, id_ok := language_service_capability_u64(input, 192)
	generation, generation_ok := language_service_capability_u64(input, 200)
	if !id_ok || !generation_ok do return {}, false
	return service.Definition_Handle{
		registry = inspection.handle,
		id = service.Definition_ID(id),
		generation = service.Definition_Generation(generation),
	}, true
}

@(private = "file")
language_service_capability_expected_handle :: proc(
	input: []u8,
	registry: ^service.Provider_Registry,
) -> (service.Definition_Handle, bool) {
	inspection, inspected := service.provider_registry_inspect(registry)
	if !inspected do return {}, false
	id, id_ok := language_service_capability_u64(input, 160)
	generation, generation_ok := language_service_capability_u64(input, 168)
	if !id_ok || !generation_ok do return {}, false
	return service.Definition_Handle{
		registry = inspection.handle,
		id = service.Definition_ID(id),
		generation = service.Definition_Generation(generation),
	}, true
}

@(private = "file")
language_service_capability_decode_definition :: proc(
	input: []u8,
	operation: bridge.Language_Service_Capability_Operation,
) -> (service.Definition_Proposal, bool, service.Failure_Context) {
	if len(input) < int(bridge.LANGUAGE_SERVICE_DEFINITION_HEADER_BYTES) {
		return {}, false, service.Failure_Context{code = .Invalid_Definition}
	}
	counts: [6]u64
	offsets := [6]int{216, 224, 232, 240, 248, 256}
	for offset, index in offsets {
		value, ok := language_service_capability_u64(input, offset)
		if !ok do return {}, false, service.Failure_Context{code = .Invalid_Definition}
		counts[index] = value
	}
	required, required_ok := bridge.language_service_definition_record_bytes(
		counts[0], counts[1], counts[2], counts[3], counts[4], counts[5],
	)
	if !required_ok || required != u64(len(input)) {
		return {}, false, service.Failure_Context{code = .Invalid_Definition}
	}
	provider_kind, kind_ok := language_service_capability_u64(input, 176)
	root_policy, root_ok := language_service_capability_u64(input, 184)
	preferred_encoding, encoding_ok := language_service_capability_u64(input, 192)
	preferred_sync, sync_ok := language_service_capability_u64(input, 200)
	capabilities, capabilities_ok := language_service_capability_u64(input, 208)
	if !kind_ok || !root_ok || !encoding_ok || !sync_ok || !capabilities_ok ||
	   provider_kind < u64(service.Provider_Kind.Factory) ||
	   provider_kind > u64(service.Provider_Kind.Programmable) ||
	   root_policy < u64(service.Root_Policy.Project_Membership) ||
	   root_policy > u64(service.Root_Policy.Workspace_Folder) ||
	   preferred_encoding < u64(service.Position_Encoding.UTF_8) ||
	   preferred_encoding > u64(service.Position_Encoding.UTF_32) ||
	   preferred_sync < u64(service.Synchronization_Mode.Full) ||
	   preferred_sync > u64(service.Synchronization_Mode.Incremental) ||
	   capabilities > u64(max(u16)) {
		return {}, false, service.Failure_Context{code = .Invalid_Definition}
	}
	record_count := bridge.LANGUAGE_SERVICE_DEFINITION_FIXED_TEXT_RECORDS +
		counts[0] + counts[1] + counts[3]
	texts, allocation_error := make([]string, int(record_count), context.temp_allocator)
	if allocation_error != nil do return {}, false, service.Failure_Context{code = .Allocation}
	for index in 0 ..< int(record_count) {
		text, text_ok := language_service_capability_text_record(
			input,
			int(bridge.LANGUAGE_SERVICE_DEFINITION_HEADER_BYTES) + index * int(bridge.LANGUAGE_SERVICE_TEXT_RECORD_BYTES),
		)
		if !text_ok do return {}, false, service.Failure_Context{code = .Invalid_Definition}
		texts[index] = text
	}
	options, options_ok := language_service_capability_options_json(input, int(record_count), counts[2])
	if !options_ok do return {}, false, service.Failure_Context{code = .Malformed_JSON}
	argument_start := int(bridge.LANGUAGE_SERVICE_DEFINITION_FIXED_TEXT_RECORDS)
	environment_start := argument_start + int(counts[0])
	language_start := environment_start + int(counts[1])
	limits, limits_ok := language_service_capability_limits(input)
	deadlines, restart, policy_ok := language_service_capability_policy(input)
	if !limits_ok || !policy_ok do return {}, false, service.Failure_Context{code = .Invalid_Definition}
	_ = operation
	return service.Definition_Proposal{
		kind = service.Provider_Kind(provider_kind),
		name = texts[0],
		executable = texts[1],
		arguments = texts[argument_start:environment_start],
		environment = texts[environment_start:language_start],
		root_policy = service.Root_Policy(root_policy),
		root = texts[2],
		languages = texts[language_start:],
		initialization_options = options,
		client_settings = `{}`,
		requested_capabilities = transmute(service.Capabilities)u16(capabilities),
		preferred_encoding = service.Position_Encoding(preferred_encoding),
		preferred_sync = service.Synchronization_Mode(preferred_sync),
		limits = limits,
		deadlines = deadlines,
		restart = restart,
	}, true, {}
}

@(private = "file")
language_service_capability_options_json :: proc(input: []u8, text_records: int, count: u64) -> (string, bool) {
	if count == 0 do return `{}`, true
	builder, allocation_error := strings.builder_make(context.temp_allocator)
	if allocation_error != nil do return "", false
	if strings.write_byte(&builder, '{') != 1 do return "", false
	base := int(bridge.LANGUAGE_SERVICE_DEFINITION_HEADER_BYTES) +
		text_records * int(bridge.LANGUAGE_SERVICE_TEXT_RECORD_BYTES)
	for index in 0 ..< int(count) {
		record := base + index * int(bridge.LANGUAGE_SERVICE_OPTION_RECORD_BYTES)
		key, key_ok := language_service_capability_text_record(input, record)
		value, value_ok := language_service_capability_text_record(input, record + 16)
		if !key_ok || !value_ok do return "", false
		encoded_key, marshal_error := json.marshal(key, {}, context.temp_allocator)
		if marshal_error != nil do return "", false
		if index > 0 && strings.write_byte(&builder, ',') != 1 do return "", false
		if strings.write_string(&builder, string(encoded_key)) != len(encoded_key) ||
		   strings.write_byte(&builder, ':') != 1 ||
		   strings.write_string(&builder, value) != len(value) {
			return "", false
		}
	}
	if strings.write_byte(&builder, '}') != 1 do return "", false
	return strings.to_string(builder), true
}

@(private = "file")
language_service_capability_text_record :: proc(input: []u8, record_offset: int) -> (string, bool) {
	offset, offset_ok := language_service_capability_u64(input, record_offset)
	bytes, bytes_ok := language_service_capability_u64(input, record_offset + 8)
	if !offset_ok || !bytes_ok || offset > u64(len(input)) || bytes > u64(len(input)) - offset {
		return "", false
	}
	return string(input[int(offset):int(offset + bytes)]), true
}

@(private = "file")
language_service_capability_limits :: proc(input: []u8) -> (service.Service_Limits, bool) {
	values: [35]u64
	for index in 0 ..< len(values) {
		value, ok := language_service_capability_u64(input, 264 + index * 8)
		if !ok do return {}, false
		values[index] = value
	}
	if values[0] > u64(max(u16)) || values[1] > u64(max(u16)) ||
	   values[2] > u64(max(u16)) || values[3] > u64(max(u16)) ||
	   values[4] > u64(max(u32)) || values[6] > u64(max(u16)) ||
	   values[8] > u64(max(u16)) || values[14] > u64(max(u16)) ||
	   values[17] > u64(max(u32)) || values[18] > u64(max(u32)) ||
	   values[19] > u64(max(u32)) || values[21] > u64(max(u32)) ||
	   values[23] > u64(max(u32)) || values[24] > u64(max(u32)) ||
	   values[25] > u64(max(u16)) || values[27] > u64(max(u16)) ||
	   values[29] > u64(max(u32)) {
		return {}, false
	}
	return service.Service_Limits{
		service_definitions = u16(values[0]), providers = u16(values[1]), sessions = u16(values[2]),
		documents_per_session = u16(values[3]), documents_total = u32(values[4]),
		executable_bytes = values[5], arguments = u16(values[6]), argument_bytes = values[7],
		environment_entries = u16(values[8]), environment_bytes = values[9], root_bytes = values[10],
		uri_bytes = values[11], options_bytes = values[12], frame_header_bytes = values[13],
		json_depth = u16(values[14]), message_bytes = values[15], buffered_stream_bytes = values[16],
		outstanding_requests = u32(values[17]), notifications = u32(values[18]), queue_depth = u32(values[19]),
		queue_bytes = values[20], synchronization_changes = u32(values[21]), synchronization_bytes = values[22],
		diagnostics_per_document = u32(values[23]), diagnostics_per_project = u32(values[24]),
		diagnostic_fields = u16(values[25]), diagnostic_message_bytes = values[26], related_locations = u16(values[27]),
		diagnostic_bytes = values[28], candidates = u32(values[29]), candidate_text_bytes = values[30],
		standard_error_bytes = values[31], work_bytes_per_turn = values[32], retained_bytes = values[33],
		temporary_bytes = values[34],
	}, true
}

@(private = "file")
language_service_capability_policy :: proc(input: []u8) -> (service.Deadline_Policy, service.Restart_Policy, bool) {
	values: [10]u64
	for index in 0 ..< len(values) {
		value, ok := language_service_capability_u64(input, 544 + index * 8)
		if !ok || value > u64(max(i64)) do return {}, {}, false
		values[index] = value
	}
	if values[8] > u64(max(u8)) do return {}, {}, false
	return service.Deadline_Policy{
		discovery_ns = i64(values[0]), initialization_ns = i64(values[1]), request_ns = i64(values[2]),
		cancellation_ns = i64(values[3]), idle_step_ns = i64(values[4]), restart_stability_ns = i64(values[5]),
		shutdown_ns = i64(values[6]), forced_termination_ns = i64(values[7]),
	}, service.Restart_Policy{automatic_restarts = u8(values[8]), stability_ns = i64(values[9])}, true
}

@(private = "file")
language_service_capability_u64 :: proc(input: []u8, offset: int) -> (u64, bool) {
	if offset < 0 || offset > len(input) || len(input) - offset < 8 do return 0, false
	return endian.get_u64(input[offset:], .Little)
}
