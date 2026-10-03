// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../bridge"
import "../hosting"
import "../interaction"
import "../status_bar"
import base_runtime "base:runtime"
import endian "core:encoding/endian"

/* Racket_Status_Bar_Turn reports one admitted provider lifecycle turn. */
Racket_Status_Bar_Turn :: struct {
	provider: status_bar.Provider_Handle,
	calls:    u16,
}

@(private)
Racket_Status_Bar_Call :: struct {
	registry:                ^status_bar.Registry,
	commands:                ^interaction.Command_Registry,
	token:                   u64,
	session_id:              u64,
	session_generation:      u64,
	presentation_generation: u64,
	calls:                   u16,
	provider:                status_bar.Provider_Handle,
	failure:                 bridge.Status_Bar_Bridge_Failure_Code,
}

/* racket_status_bar_turn lends one exact bounded provider registry to Racket. */
racket_status_bar_turn :: proc(
	racket_runtime: ^hosting.Runtime,
	registry: ^status_bar.Registry,
	commands: ^interaction.Command_Registry,
	session_id, session_generation, presentation_generation: u64,
	scenario: i32,
) -> (Racket_Status_Bar_Turn, bool, bridge.Status_Bar_Bridge_Failure_Code) {
	if racket_runtime == nil || registry == nil || commands == nil ||
	   session_id == 0 || session_generation == 0 || presentation_generation == 0 {
		return {}, false, .Invalid_Scope
	}
	token := session_id ~ (session_generation << 19) ~ (presentation_generation << 41)
	if token == 0 do token = 1
	call := Racket_Status_Bar_Call {
		registry = registry,
		commands = commands,
		token = token,
		session_id = session_id,
		session_generation = session_generation,
		presentation_generation = presentation_generation,
	}
	executed, _ := hosting.runtime_status_bar_probe(
		racket_runtime,
		scenario,
		token,
		racket_status_bar_callback,
		&call,
	)
	if !executed {
		if call.failure != .None do return {}, false, call.failure
		return {}, false, .Invalid_Schema
	}
	if call.failure != .None do return {}, false, call.failure
	return Racket_Status_Bar_Turn{provider = call.provider, calls = call.calls}, true, .None
}

@(private)
racket_status_bar_callback :: proc "c" (
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
	call := (^Racket_Status_Bar_Call)(user_data)
	if call == nil || kind != .Status_Bar || generation == 0 || token != call.token ||
	   domain_context != 0 || arg1 != 0 || output_length == nil || value == nil ||
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
		if input == nil do return 2
		input_bytes = ([^]u8)(input)[:int(input_length)]
	}
	destination: []u8
	if output_capacity > 0 {
		if output == nil do return 2
		destination = ([^]u8)(output)[:int(output_capacity)]
	}
	if call.calls >= u16(status_bar.DEFAULT_REGISTRY_LIMITS.segments_per_provider) {
		return racket_status_bar_reject(call, .Proposal_Limit, failure_code, limit, actual)
	}
	call.calls += 1
	op := bridge.Status_Bar_Capability_Operation(operation)
	if op == .Scope {
		if input_length != 0 || output_capacity != bridge.STATUS_BAR_SCOPE_RECORD_BYTES ||
		   arg0 < u64(bridge.Status_Bar_Capability_Access.Inspect) ||
		   arg0 > u64(bridge.Status_Bar_Capability_Access.Teardown) {
			return 2
		}
		scope, scoped := racket_status_bar_scope(
			call,
			bridge.Status_Bar_Capability_Access(arg0),
			generation,
			{},
		)
		if !scoped do return racket_status_bar_reject(call, .Invalid_Scope, failure_code, limit, actual)
		racket_status_bar_encode_scope(destination, scope)
		output_length^ = bridge.STATUS_BAR_SCOPE_RECORD_BYTES
		return 0
	}
	if op == .Inspect {
		if arg0 != 0 || input_length != bridge.STATUS_BAR_SCOPE_RECORD_BYTES {
			return 2
		}
		expected, decoded := bridge.status_bar_scope_record_decode(input_bytes)
		if !decoded || expected.access != u64(bridge.Status_Bar_Capability_Access.Inspect) ||
		   !racket_status_bar_scope_is_current(call, expected, generation) {
			return racket_status_bar_reject(call, .Stale_Scope, failure_code, limit, actual)
		}
		written, encoded := racket_status_bar_encode_snapshot(
			destination,
			call,
			generation,
		)
		if !encoded {
			return racket_status_bar_reject(
				call, .Proposal_Limit, failure_code, limit, actual,
				bridge.MAX_STATUS_BAR_INSPECTION_BYTES, output_capacity,
			)
		}
		output_length^ = written
		return 0
	}
	if arg0 != 0 || input_length < bridge.STATUS_BAR_PROPOSAL_HEADER_BYTES ||
	   output_capacity != bridge.STATUS_BAR_OUTCOME_RECORD_BYTES {
		return 2
	}
	request, decoded, decode_failure := status_bar_provider_request_decode(input_bytes, op, call.commands)
	if !decoded {
		return racket_status_bar_reject(call, decode_failure, failure_code, limit, actual)
	}
	if !racket_status_bar_scope_is_current(call, request.expected_scope, generation) {
		return racket_status_bar_reject(call, .Stale_Scope, failure_code, limit, actual)
	}
	provider: status_bar.Provider_Handle
	changed := false
	registry_failure: status_bar.Registry_Failure
	proposal := status_bar_provider_request_proposal(&request)
	switch op {
	case .Register:
		provider, changed, registry_failure = status_bar.registry_register(
			call.registry,
			status_bar.Registry_Generation(request.expected_scope.registry_generation),
			proposal,
		)
	case .Replace:
		provider, changed, registry_failure = status_bar.registry_replace(
			call.registry,
			status_bar.Registry_Generation(request.expected_scope.registry_generation),
			request.expected_provider,
			proposal,
		)
	case .Remove:
		provider = request.expected_provider
		changed, registry_failure = status_bar.registry_remove(
			call.registry,
			status_bar.Registry_Generation(request.expected_scope.registry_generation),
			request.expected_provider,
		)
	case .Teardown:
		provider = request.expected_provider
		changed, registry_failure = status_bar.registry_teardown_provider(
			call.registry,
			status_bar.Registry_Generation(request.expected_scope.registry_generation),
			request.expected_provider,
		)
	case .Scope, .Inspect:
		return 2
	}
	if !changed {
		mapped := racket_status_bar_registry_failure(registry_failure)
		return racket_status_bar_reject(call, mapped, failure_code, limit, actual,
			registry_failure.limit, registry_failure.actual)
	}
	call.provider = provider
	scope, scoped := racket_status_bar_scope(
		call,
		bridge.Status_Bar_Capability_Access(request.expected_scope.access),
		generation,
		provider,
	)
	if !scoped do return racket_status_bar_reject(call, .Invalid_Scope, failure_code, limit, actual)
	segment_count, retained_bytes := racket_status_bar_provider_accounting(call.registry, provider)
	racket_status_bar_encode_outcome(
		destination,
		scope,
		op,
		provider,
		segment_count,
		retained_bytes,
		u64(call.calls),
	)
	output_length^ = bridge.STATUS_BAR_OUTCOME_RECORD_BYTES
	return 0
}

@(private)
racket_status_bar_encode_snapshot :: proc(
	destination: []u8,
	call: ^Racket_Status_Bar_Call,
	capability_generation: u64,
) -> (u64, bool) {
	inspection, inspected, _ := status_bar.registry_inspect(call.registry)
	if !inspected do return 0, false
	provider_count := u64(inspection.usage.providers)
	segment_count := u64(inspection.usage.segments)
	text_bytes: u64
	for index: u16 = 0; index < inspection.usage.providers; index += 1 {
		provider, found, _ := status_bar.registry_provider_at(call.registry, index)
		if !found do return 0, false
		text_bytes += u64(len(status_bar.provider_descriptor_name(&provider)))
		text_bytes += u64(len(status_bar.provider_descriptor_package(&provider)))
	}
	for index: u16 = 0; index < inspection.usage.segments; index += 1 {
		segment, found, _ := status_bar.registry_segment_at(call.registry, index)
		if !found do return 0, false
		text_bytes += u64(len(status_bar.programmable_segment_identity(&segment.descriptor)))
		text_bytes += u64(len(segment.definition.full_text))
		text_bytes += u64(len(segment.definition.compact_text))
		text_bytes += u64(len(segment.definition.inspection_text))
		text_bytes += u64(len(racket_status_bar_command_name(call.commands, segment.definition.primary_command)))
		text_bytes += u64(len(racket_status_bar_command_name(call.commands, segment.definition.secondary_command)))
	}
	required, width_ok := bridge.status_bar_snapshot_record_bytes(
		provider_count, segment_count, text_bytes, 0,
	)
	if !width_ok || required > u64(len(destination)) do return required, false
	for &byte in destination[:int(required)] do byte = 0
	scope, scoped := racket_status_bar_scope(
		call, .Inspect, capability_generation, {},
	)
	if !scoped do return 0, false
	racket_status_bar_encode_scope(destination, scope)
	usage_values := [7]u64 {
		provider_count,
		segment_count,
		inspection.usage.retained_bytes,
		required,
		inspection.usage.preparation_peak_bytes,
		u64(call.calls),
		1,
	}
	for value, index in usage_values do racket_status_bar_put(destination, 96 + index * 8, value)
	limits := inspection.limits
	limit_values := [15]u64 {
		u64(limits.providers),
		u64(limits.segments_per_provider),
		u64(limits.total_segments),
		u64(limits.identity_bytes),
		u64(limits.provider_name_bytes),
		u64(limits.package_name_bytes),
		u64(limits.segment_text_bytes),
		bridge.MAX_STATUS_BAR_COMMAND_NAME_BYTES,
		limits.retained_bytes,
		bridge.MAX_STATUS_BAR_PROPOSAL_BYTES,
		u64(limits.segments_per_provider),
		bridge.MAX_STATUS_BAR_INSPECTION_BYTES,
		limits.retained_bytes,
		bridge.MAX_STATUS_BAR_DIAGNOSTIC_BYTES,
		1,
	}
	for value, index in limit_values do racket_status_bar_put(destination, 152 + index * 8, value)
	count_values := [5]u64 {provider_count, segment_count, 0, text_bytes, 0}
	for value, index in count_values do racket_status_bar_put(destination, 272 + index * 8, value)
	provider_records := bridge.STATUS_BAR_SNAPSHOT_HEADER_BYTES
	segment_records := provider_records + provider_count * bridge.STATUS_BAR_PROVIDER_RECORD_BYTES
	text_cursor := segment_records + segment_count * bridge.STATUS_BAR_SEGMENT_RECORD_BYTES
	first_segment: u64
	for index: u16 = 0; index < inspection.usage.providers; index += 1 {
		provider, found, _ := status_bar.registry_provider_at(call.registry, index)
		if !found do return 0, false
		name := status_bar.provider_descriptor_name(&provider)
		name_offset := text_cursor
		text_cursor = racket_status_bar_copy_text(destination, text_cursor, name)
		package_name := status_bar.provider_descriptor_package(&provider)
		package_offset := text_cursor
		text_cursor = racket_status_bar_copy_text(destination, text_cursor, package_name)
		values := [10]u64 {
			u64(provider.handle.provider_id), u64(provider.handle.provider_generation),
			u64(bridge.Status_Bar_Provider_State.Confirmed),
			name_offset, u64(len(name)), package_offset, u64(len(package_name)),
			first_segment, u64(provider.segment_count), provider.retained_bytes,
		}
		record_offset := int(provider_records + u64(index) * bridge.STATUS_BAR_PROVIDER_RECORD_BYTES)
		for value, field in values do racket_status_bar_put(destination, record_offset + field * 8, value)
		first_segment += u64(provider.segment_count)
	}
	for index: u16 = 0; index < inspection.usage.segments; index += 1 {
		segment, found, _ := status_bar.registry_segment_at(call.registry, index)
		if !found do return 0, false
		definition := segment.definition
		texts := [6]string {
			status_bar.programmable_segment_identity(&segment.descriptor),
			definition.full_text,
			definition.compact_text,
			definition.inspection_text,
			racket_status_bar_command_name(call.commands, definition.primary_command),
			racket_status_bar_command_name(call.commands, definition.secondary_command),
		}
		ranges: [12]u64
		for text, text_index in texts {
			ranges[text_index * 2] = text_cursor
			ranges[text_index * 2 + 1] = u64(len(text))
			text_cursor = racket_status_bar_copy_text(destination, text_cursor, text)
		}
		handle := segment.descriptor.handle
		values := [24]u64 {
			u64(handle.provider.provider_id), u64(handle.provider.provider_generation),
			u64(handle.segment_id), u64(handle.segment_generation),
			u64(bridge.Status_Bar_Provider_State.Confirmed), u64(definition.kind),
			u64(definition.group), u64(segment.descriptor.order), u64(definition.priority),
			u64(definition.omittable), u64(definition.truncatable), u64(definition.style_role),
			ranges[0], ranges[1], ranges[2], ranges[3], ranges[4], ranges[5],
			ranges[6], ranges[7], ranges[8], ranges[9], ranges[10], ranges[11],
		}
		record_offset := int(segment_records + u64(index) * bridge.STATUS_BAR_SEGMENT_RECORD_BYTES)
		for value, field in values do racket_status_bar_put(destination, record_offset + field * 8, value)
	}
	return required, text_cursor == required
}

@(private)
racket_status_bar_command_name :: proc(
	commands: ^interaction.Command_Registry,
	reference: status_bar.Command_Reference,
) -> string {
	if reference == (status_bar.Command_Reference{}) do return ""
	metadata, found, _ := interaction.command_metadata(commands, interaction.Command_Handle {
		registry_generation = interaction.Registry_Generation(reference.registry_generation),
		slot = reference.slot,
		entry_generation = reference.entry_generation,
	})
	if !found do return ""
	return metadata.name
}

@(private)
racket_status_bar_copy_text :: proc(destination: []u8, offset: u64, value: string) -> u64 {
	copy(destination[int(offset):], transmute([]u8)value)
	return offset + u64(len(value))
}

@(private)
racket_status_bar_scope :: proc(
	call: ^Racket_Status_Bar_Call,
	access: bridge.Status_Bar_Capability_Access,
	capability_generation: u64,
	provider: status_bar.Provider_Handle,
) -> (bridge.Status_Bar_Scope_Record, bool) {
	inspection, inspected, _ := status_bar.registry_inspect(call.registry)
	command_stats, commands_ok, _ := interaction.command_registry_stats(call.commands)
	if !inspected || !commands_ok do return {}, false
	return bridge.Status_Bar_Scope_Record {
		schema_version = bridge.STATUS_BAR_CAPABILITY_SCHEMA_VERSION,
		access = u64(access),
		session_id = call.session_id,
		session_generation = call.session_generation,
		registry_id = u64(inspection.registry_id),
		registry_generation = u64(inspection.registry_generation),
		definition_generation = u64(inspection.registry_generation),
		provider_id = u64(provider.provider_id),
		provider_generation = u64(provider.provider_generation),
		command_registry_generation = u64(command_stats.generation),
		presentation_generation = call.presentation_generation,
		capability_generation = capability_generation,
	}, true
}

@(private)
racket_status_bar_scope_is_current :: proc(
	call: ^Racket_Status_Bar_Call,
	scope: bridge.Status_Bar_Scope_Record,
	capability_generation: u64,
) -> bool {
	current, scoped := racket_status_bar_scope(
		call,
		bridge.Status_Bar_Capability_Access(scope.access),
		capability_generation,
		status_bar.Provider_Handle {
			registry_id = status_bar.Registry_ID(scope.registry_id),
			provider_id = status_bar.Provider_ID(scope.provider_id),
			provider_generation = status_bar.Provider_Generation(scope.provider_generation),
		},
	)
	return scoped && current == scope
}

@(private)
racket_status_bar_provider_accounting :: proc(
	registry: ^status_bar.Registry,
	handle: status_bar.Provider_Handle,
) -> (u64, u64) {
	inspection, inspected, _ := status_bar.registry_inspect(registry)
	if !inspected do return 0, 0
	for index: u16 = 0; index < inspection.usage.providers; index += 1 {
		descriptor, found, _ := status_bar.registry_provider_at(registry, index)
		if found && descriptor.handle == handle {
			return u64(descriptor.segment_count), descriptor.retained_bytes
		}
	}
	return 0, 0
}

@(private)
racket_status_bar_encode_scope :: proc(
	destination: []u8,
	scope: bridge.Status_Bar_Scope_Record,
) {
	values := [12]u64 {
		scope.schema_version, scope.access, scope.session_id, scope.session_generation,
		scope.registry_id, scope.registry_generation, scope.definition_generation,
		scope.provider_id, scope.provider_generation, scope.command_registry_generation,
		scope.presentation_generation, scope.capability_generation,
	}
	for value, index in values do racket_status_bar_put(destination, index * 8, value)
}

@(private)
racket_status_bar_encode_outcome :: proc(
	destination: []u8,
	scope: bridge.Status_Bar_Scope_Record,
	operation: bridge.Status_Bar_Capability_Operation,
	provider: status_bar.Provider_Handle,
	segment_count, retained_bytes, operation_count: u64,
) {
	racket_status_bar_encode_scope(destination, scope)
	values := [11]u64 {
		u64(operation), u64(bridge.Status_Bar_Completion.Confirmed), 1,
		u64(provider.provider_id), u64(provider.provider_generation),
		scope.definition_generation, segment_count, retained_bytes, operation_count, 0, 0,
	}
	for value, index in values do racket_status_bar_put(destination, 96 + index * 8, value)
}

@(private)
racket_status_bar_registry_failure :: proc(
	failure: status_bar.Registry_Failure,
) -> bridge.Status_Bar_Bridge_Failure_Code {
	switch failure.code {
	case .None:                      return .None
	case .Invalid_Registry, .Closed_Registry: return .Invalid_Scope
	case .Wrong_Registry, .Stale_Registry:    return .Stale_Scope
	case .Invalid_Provider:          return .Invalid_Provider
	case .Stale_Provider:            return .Stale_Provider
	case .Duplicate_Provider:        return .Duplicate_Provider
	case .Provider_Limit:            return .Provider_Limit
	case .Invalid_Proposal:          return .Invalid_Provider
	case .Invalid_Segment:           return .Invalid_Segment
	case .Duplicate_Segment:         return .Duplicate_Segment
	case .Factory_Identity_Conflict: return .Factory_Identity_Conflict
	case .Segment_Limit:             return .Segment_Limit
	case .Text_Limit, .Retained_Bytes_Limit: return .Text_Limit
	case .Generation_Limit:          return .Generation_Limit
	case .Allocation:                return .Allocation
	}
	return .Invalid_Schema
}

@(private)
racket_status_bar_reject :: proc(
	call: ^Racket_Status_Bar_Call,
	failure: bridge.Status_Bar_Bridge_Failure_Code,
	failure_code: ^u32,
	limit, actual: ^u64,
	failure_limit: u64 = 0,
	failure_actual: u64 = 0,
) -> i32 {
	call.failure = failure
	failure_code^ = u32(failure)
	limit^ = failure_limit
	actual^ = failure_actual
	return 1
}

@(private)
racket_status_bar_put :: proc(destination: []u8, offset: int, value: u64) {
	assert(endian.put_u64(destination[offset:], .Little, value))
}
