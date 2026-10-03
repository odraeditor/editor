// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery_module

import bridge "../ksawery_bridge"
import "../ksawery"
import "base:runtime"
import "core:encoding/endian"

/* KSAWERY_CONFLICT_ASSISTANCE_BATCH_BYTES is the fixed provider and response length prefix. */
KSAWERY_CONFLICT_ASSISTANCE_BATCH_BYTES :: 16

/* Ksawery_Conflict_Assistance_Evaluation owns one validated provider response. */
Ksawery_Conflict_Assistance_Evaluation :: struct {
	provider:             ksawery.Conflict_Assistance_Provider,
	provider_declaration: ksawery.Contribution_Declaration,
	operation_declaration: ksawery.Contribution_Declaration,
	selection:            ksawery.Conflict_Assistance_Selection,
	request:              ksawery.Conflict_Assistance_Request,
	response:             ksawery.Conflict_Assistance_Response,
	arguments:            [ksawery.MAX_EXTENSION_OPERATION_ARGUMENTS]ksawery.Extension_Operation_Argument,
	available:            bool,
	fallback:             bool,
}

/* ksawery_conflict_assistance_evaluate runs one bounded selected-provider turn. */
ksawery_conflict_assistance_evaluate :: proc(
	evaluation: ^Ksawery_Conflict_Assistance_Evaluation,
	registry: ^Ksawery_Extension_Provider_Registry,
	host: ^Host_Context,
	observation: ksawery.Conflict_Assistance_Observation,
	request_id: ksawery.Conflict_Assistance_Request_ID,
	selection_generation: ksawery.Conflict_Assistance_Selection_Generation,
	session: u64,
	allocator := context.allocator,
) -> ksawery.Conflict_Assistance_Failure {
	if evaluation == nil || request_id == 0 || selection_generation == 0 || session == 0 ||
	   allocator.procedure == nil {
		return {code = .Invalid_Response, request = request_id, target = observation.target.conflict}
	}
	evaluation^ = {}
	_, observation_failure := ksawery.conflict_assistance_observation_validate(observation)
	if observation_failure.code != .None do return observation_failure
	if !ksawery_extension_provider_registry_is_open(registry) || registry.active == nil ||
	   !registry.active.enabled || host == nil {
		ksawery_conflict_assistance_use_fallback(
			evaluation, observation.target, request_id, selection_generation,
		)
		return {}
	}
	input, encoded := ksawery_conflict_assistance_observation_encode(observation, allocator)
	if !encoded do return {code = .Allocation, request = request_id, target = observation.target.conflict}
	defer delete(input, allocator)
	if u64(len(input)) > registry.active.limits.observation_bytes {
		return {code = .Content_Limit, request = request_id, target = observation.target.conflict,
			limit = registry.active.limits.observation_bytes, actual = u64(len(input))}
	}
	output, allocation_error := make(
		[]u8,
		int(min(registry.active.limits.result_bytes, ksawery.MAX_CONFLICT_ASSISTANCE_COPY_BYTES)),
		allocator,
	)
	if allocation_error != nil {
		return {code = .Allocation, request = request_id, target = observation.target.conflict}
	}
	defer delete(output, allocator)
	output_length, evaluated := host_provider_invoke(
		host,
		"source-control.conflict-assistance",
		0,
		u64(request_id),
		"",
		input,
		output,
	)
	if !evaluated || output_length == 0 {
		ksawery_conflict_assistance_use_fallback(
			evaluation, observation.target, request_id, selection_generation,
		)
		return {code = .Provider_Exception, request = request_id, target = observation.target.conflict}
	}
	failure := ksawery_conflict_assistance_decode_evaluation(
		evaluation,
		registry,
		output[:int(output_length)],
		observation.target,
		request_id,
		selection_generation,
		session,
	)
	if failure.code != .None {
		ksawery_conflict_assistance_use_fallback(
			evaluation, observation.target, request_id, selection_generation,
		)
	}
	return failure
}

@(private)
ksawery_conflict_assistance_observation_encode :: proc(
	observation: ksawery.Conflict_Assistance_Observation,
	allocator: runtime.Allocator,
) -> ([]u8, bool) {
	_, failure := ksawery.conflict_assistance_observation_validate(observation)
	if failure.code != .None || allocator.procedure == nil do return nil, false
	repository_copy := observation.target.repository
	repository := transmute([]u8)(ksawery.repository_context_string(&repository_copy))
	path_copy := observation.target.path
	path := path_copy.bytes[:path_copy.length]
	fixed := int(bridge.KSAWERY_CONFLICT_ASSISTANCE_OBSERVATION_BYTES +
		4 * bridge.KSAWERY_CONFLICT_ASSISTANCE_SIDE_BYTES)
	payload_bytes := len(repository) + len(path)
	for side in observation.sides {
		object := side.object
		payload_bytes += int(object.length) + int(side.content.length)
	}
	result, allocation_error := make([]u8, fixed + payload_bytes, allocator)
	if allocation_error != nil do return nil, false
	payload_cursor := 0
	payload := result[fixed:]
	repository_offset := payload_cursor
	copy(payload[payload_cursor:], repository)
	payload_cursor += len(repository)
	path_offset := payload_cursor
	copy(payload[payload_cursor:], path)
	payload_cursor += len(path)
	header := [?]u64 {
		bridge.KSAWERY_CONFLICT_ASSISTANCE_SCHEMA_VERSION,
		u64(len(result)),
		u64(observation.target.repository_generation),
		u64(observation.target.worktree_generation),
		u64(observation.target.observation_generation),
		u64(observation.target.conflict.sequence.generation),
		u64(observation.target.conflict.sequence.fingerprint),
		u64(observation.target.conflict.conflict),
		u64(observation.target.kind),
		u64(transmute(u16)observation.target.classes),
		4,
		u64(payload_bytes),
		u64(repository_offset), u64(len(repository)),
		u64(path_offset), u64(len(path)),
		u64(observation.truncated), 0, 0, 0,
	}
	ksawery_conflict_assistance_put_words(result, 0, header[:])
	for side, index in observation.sides {
		object_offset, object_bytes := u64(0), u64(0)
		object := side.object
		if object.length > 0 {
			object_offset = u64(payload_cursor)
			object_bytes = u64(object.length)
			copy(payload[payload_cursor:], object.bytes[:object.length])
			payload_cursor += int(object.length)
		}
		content_offset, content_bytes := u64(0), u64(side.content.length)
		if content_bytes > 0 {
			content_offset = u64(payload_cursor)
			start := int(side.content.offset)
			end := start + int(side.content.length)
			copy(payload[payload_cursor:], observation.content[start:end])
			payload_cursor += int(side.content.length)
		}
		record := [?]u64 {
			u64(side.kind), u64(side.material), u64(side.mode),
			object_offset, object_bytes, content_offset, content_bytes, u64(side.truncated),
		}
		base := int(bridge.KSAWERY_CONFLICT_ASSISTANCE_OBSERVATION_BYTES) +
			index * int(bridge.KSAWERY_CONFLICT_ASSISTANCE_SIDE_BYTES)
		ksawery_conflict_assistance_put_words(result, base, record[:])
	}
	assert(payload_cursor == payload_bytes)
	return result, true
}

@(private)
ksawery_conflict_assistance_decode_evaluation :: proc(
	evaluation: ^Ksawery_Conflict_Assistance_Evaluation,
	registry: ^Ksawery_Extension_Provider_Registry,
	input: []u8,
	target: ksawery.Conflict_Assistance_Target,
	request_id: ksawery.Conflict_Assistance_Request_ID,
	selection_generation: ksawery.Conflict_Assistance_Selection_Generation,
	session: u64,
) -> ksawery.Conflict_Assistance_Failure {
	failure := ksawery.Conflict_Assistance_Failure {
		request = request_id,
		target = target.conflict,
	}
	if evaluation == nil || registry == nil || registry.active == nil ||
	   len(input) < KSAWERY_CONFLICT_ASSISTANCE_BATCH_BYTES {
		failure.code = .Invalid_Response
		return failure
	}
	provider_bytes := ksawery_conflict_assistance_word(input, 0)
	response_bytes := ksawery_conflict_assistance_word(input, 8)
	if provider_bytes < bridge.KSAWERY_CONFLICT_ASSISTANCE_PROVIDER_BYTES ||
	   response_bytes < bridge.KSAWERY_CONFLICT_ASSISTANCE_RESPONSE_BYTES ||
	   provider_bytes + response_bytes != u64(len(input) - KSAWERY_CONFLICT_ASSISTANCE_BATCH_BYTES) {
		failure.code = .Invalid_Response
		return failure
	}
	provider_start := KSAWERY_CONFLICT_ASSISTANCE_BATCH_BYTES
	response_start := provider_start + int(provider_bytes)
	provider_input := input[provider_start:response_start]
	response_input := input[response_start:]
	provider_record: bridge.Ksawery_Conflict_Assistance_Provider_Record
	for index in 0 ..< 18 {
		ksawery_conflict_assistance_assign_provider_word(
			&provider_record, index, ksawery_conflict_assistance_word(provider_input, index * 8),
		)
	}
	provider_payload := provider_input[int(bridge.KSAWERY_CONFLICT_ASSISTANCE_PROVIDER_BYTES):]
	if record_failure := bridge.ksawery_conflict_assistance_provider_record_validate(
		provider_record, provider_payload,
	); record_failure.code != .None {
		failure.code = .Invalid_Provider
		return failure
	}
	provider, provider_declaration, decoded_provider :=
		ksawery_conflict_assistance_decode_provider(registry.active, provider_record, provider_payload)
	if !decoded_provider {
		failure.code = .Invalid_Provider
		return failure
	}
	failure.provider = provider.provider
	response_record: bridge.Ksawery_Conflict_Assistance_Response_Record
	for index in 0 ..< 16 {
		ksawery_conflict_assistance_assign_response_word(
			&response_record, index, ksawery_conflict_assistance_word(response_input, index * 8),
		)
	}
	response_payload := response_input[int(bridge.KSAWERY_CONFLICT_ASSISTANCE_RESPONSE_BYTES):]
	if record_failure := bridge.ksawery_conflict_assistance_response_record_validate(
		response_record, response_payload,
	); record_failure.code != .None || response_record.request_id != u64(request_id) ||
	   response_record.provider_id != u64(provider.provider) ||
	   response_record.provider_generation != u64(provider.generation) ||
	   response_record.contributor_generation != u64(provider.contributor.generation) {
		failure.code = .Invalid_Response
		return failure
	}
	selection := ksawery.Conflict_Assistance_Selection {
		selection = ksawery.Conflict_Assistance_Selection_ID(u64(request_id)),
		generation = selection_generation,
		scope = .Session,
		session = session,
		provider = ksawery.conflict_assistance_provider_reference(provider),
		confirmed = true,
	}
	request := ksawery.Conflict_Assistance_Request {
		request = request_id,
		selection_generation = selection_generation,
		provider = selection.provider,
		target = target,
	}
	response := ksawery.Conflict_Assistance_Response {
		request = request_id,
		provider = request.provider,
		target = target,
		kind = ksawery.Conflict_Assistance_Response_Kind(response_record.kind),
	}
	if response.kind == .Guidance {
		guidance := string(response_payload[int(response_record.guidance_offset):
			int(response_record.guidance_offset + response_record.guidance_bytes)])
		if !ksawery.conflict_assistance_guidance_assign(&response.guidance, guidance) {
			failure.code = .Invalid_Guidance
			return failure
		}
	} else if response.kind == .External_Tool {
		operation_input := response_payload[int(response_record.operation_offset):
			int(response_record.operation_offset + response_record.operation_bytes)]
		operation, operation_declaration, decoded_operation :=
			ksawery_extension_operation_decode(registry, operation_input, &evaluation.arguments)
		if !decoded_operation {
			failure.code = .Invalid_Tool_Plan
			return failure
		}
		response.tool = {
			request = request_id,
			provider = request.provider,
			target = target,
			access = ksawery.Conflict_Assistance_Tool_Access(response_record.tool_access),
			operation = operation,
		}
		evaluation.operation_declaration = operation_declaration
	}
	_, response_failure := ksawery.conflict_assistance_response_validate(
		response, request, provider,
	)
	if response_failure.code != .None do return response_failure
	evaluation.provider = provider
	evaluation.provider_declaration = provider_declaration
	evaluation.selection = selection
	evaluation.request = request
	evaluation.response = response
	evaluation.available = true
	return {}
}

@(private)
ksawery_conflict_assistance_decode_provider :: proc(
	data: ^Ksawery_Extension_Provider_Data,
	record: bridge.Ksawery_Conflict_Assistance_Provider_Record,
	payload: []u8,
) -> (ksawery.Conflict_Assistance_Provider, ksawery.Contribution_Declaration, bool) {
	if data == nil || record.contributor_generation != u64(data.inspection.handle.generation) {
		return {}, {}, false
	}
	contributor_identity := bridge.ksawery_extension_text(
		payload, record.contributor_identity_offset, record.contributor_identity_bytes,
	)
	identity_copy := data.inspection.identity
	if contributor_identity != string(identity_copy.bytes[:identity_copy.length]) {
		return {}, {}, false
	}
	declaration, declared := ksawery_extension_operation_declaration(
		data, ksawery.Contribution_ID(record.contribution_id),
	)
	if !declared do return {}, {}, false
	provider := ksawery.Conflict_Assistance_Provider {
		origin = .Extension,
		contributor = data.inspection.handle,
		contribution = declaration.id,
		provider = ksawery.Conflict_Assistance_Provider_ID(record.provider_id),
		generation = ksawery.Conflict_Assistance_Provider_Generation(record.provider_generation),
		supported_classes = transmute(ksawery.Conflict_Assistance_Classes)u16(record.supported_classes),
		capabilities = transmute(ksawery.Conflict_Assistance_Capabilities)u8(record.capabilities),
		lifecycle = ksawery.Conflict_Assistance_Provider_Lifecycle(record.lifecycle),
	}
	if !ksawery.extension_identity_assign(
		&provider.identity,
		bridge.ksawery_extension_text(payload, record.identity_offset, record.identity_bytes),
	) || !ksawery.extension_label_assign(
		&provider.label,
		bridge.ksawery_extension_text(payload, record.label_offset, record.label_bytes),
	) {
		return {}, {}, false
	}
	failure := ksawery.conflict_assistance_provider_validate(provider, declaration)
	return provider, declaration, failure.code == .None
}

@(private)
ksawery_conflict_assistance_use_fallback :: proc(
	evaluation: ^Ksawery_Conflict_Assistance_Evaluation,
	target: ksawery.Conflict_Assistance_Target,
	request_id: ksawery.Conflict_Assistance_Request_ID,
	selection_generation: ksawery.Conflict_Assistance_Selection_Generation,
) {
	if evaluation == nil do return
	provider := ksawery.conflict_assistance_builtin_no_op_provider()
	selection := ksawery.conflict_assistance_builtin_fallback_selection(selection_generation)
	evaluation^ = {
		provider = provider,
		selection = selection,
		request = {
			request = request_id,
			selection_generation = selection_generation,
			provider = selection.provider,
			target = target,
		},
		response = {
			request = request_id,
			provider = selection.provider,
			target = target,
			kind = .Declined,
		},
		available = true,
		fallback = true,
	}
}

@(private)
ksawery_conflict_assistance_put_words :: proc(output: []u8, offset: int, words: []u64) {
	for word, index in words {
		assert(endian.put_u64(output[offset + index * 8:], .Little, word))
	}
}

@(private)
ksawery_conflict_assistance_word :: proc(input: []u8, offset: int) -> u64 {
	value, ok := endian.get_u64(input[offset:], .Little)
	assert(ok)
	return value
}

@(private)
ksawery_conflict_assistance_assign_provider_word :: proc(
	record: ^bridge.Ksawery_Conflict_Assistance_Provider_Record,
	index: int,
	value: u64,
) {
	switch index {
	case 0: record.schema_version = value; case 1: record.record_bytes = value
	case 2: record.origin = value; case 3: record.contributor_generation = value
	case 4: record.contribution_id = value; case 5: record.provider_id = value
	case 6: record.provider_generation = value; case 7: record.supported_classes = value
	case 8: record.capabilities = value; case 9: record.lifecycle = value
	case 10: record.contributor_identity_offset = value; case 11: record.contributor_identity_bytes = value
	case 12: record.identity_offset = value; case 13: record.identity_bytes = value
	case 14: record.label_offset = value; case 15: record.label_bytes = value
	case 16: record.payload_bytes = value; case 17: record.reserved = value
	}
}

@(private)
ksawery_conflict_assistance_assign_response_word :: proc(
	record: ^bridge.Ksawery_Conflict_Assistance_Response_Record,
	index: int,
	value: u64,
) {
	switch index {
	case 0: record.schema_version = value; case 1: record.record_bytes = value
	case 2: record.request_id = value; case 3: record.provider_id = value
	case 4: record.provider_generation = value; case 5: record.kind = value
	case 6: record.tool_access = value; case 7: record.guidance_offset = value
	case 8: record.guidance_bytes = value; case 9: record.operation_offset = value
	case 10: record.operation_bytes = value; case 11: record.diagnostic_code = value
	case 12: record.diagnostic_offset = value; case 13: record.diagnostic_bytes = value
	case 14: record.payload_bytes = value; case 15: record.contributor_generation = value
	}
}
