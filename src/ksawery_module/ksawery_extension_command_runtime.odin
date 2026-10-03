// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery_module

import bridge "../ksawery_bridge"
import "../command"
import "../ksawery"
import "../ksawery_command"
import "base:runtime"
import "core:encoding/endian"

/* KSAWERY_COMMAND_FAMILY_ENVELOPE_BYTES is the fixed action and payload prefix. */
KSAWERY_COMMAND_FAMILY_ENVELOPE_BYTES :: 16
/* KSAWERY_COMMAND_FAMILY_HEADER_BYTES is the fixed copied family header width. */
KSAWERY_COMMAND_FAMILY_HEADER_BYTES :: 144
/* KSAWERY_COMMAND_ARGUMENT_RECORD_BYTES is one copied argument definition width. */
KSAWERY_COMMAND_ARGUMENT_RECORD_BYTES :: 80
/* KSAWERY_COMMAND_CHOICE_RECORD_BYTES is one copied closed-choice definition width. */
KSAWERY_COMMAND_CHOICE_RECORD_BYTES :: 40
/* KSAWERY_COMMAND_ACTION_RECORD_BYTES is one copied action definition width. */
KSAWERY_COMMAND_ACTION_RECORD_BYTES :: 96
/* KSAWERY_COMMAND_CONTEXT_HEADER_BYTES is one copied command context prefix. */
KSAWERY_COMMAND_CONTEXT_HEADER_BYTES :: 184

/* Ksawery_Extension_Command_Operation_Data owns one decoded external-operation route. */
Ksawery_Extension_Command_Operation_Data :: struct {
	plan:        ksawery.Extension_Operation_Plan,
	declaration: ksawery.Contribution_Declaration,
	arguments:   [ksawery.MAX_EXTENSION_OPERATION_ARGUMENTS]ksawery.Extension_Operation_Argument,
	allocator:   runtime.Allocator,
}

/* ksawery_extension_command_external_operation resolves one checked command outcome. */
ksawery_extension_command_external_operation :: proc(
	host: ^Host_Context,
	registry: ^Ksawery_Extension_Provider_Registry,
	personal_generation: u64,
	route: ksawery_command.Ksawery_Extension_Command_Route,
	name: string,
	request: ksawery.Extension_Command_Request,
	allocator: runtime.Allocator,
) -> (^Ksawery_Extension_Command_Operation_Data, bool) {
	if host == nil || registry == nil || registry.active == nil ||
	   !registry.active.enabled || personal_generation == 0 ||
	   route.route.provider != command.RACKET_KSAWERY_ROUTE_PROVIDER ||
	   route.route.operation == 0 || route.contributor != request.command_context.contributor ||
	   route.family != request.family || route.family_generation != request.family_generation ||
	   route.action != request.action || len(name) == 0 || allocator.procedure == nil {
		return nil, false
	}
	submission, encoded := ksawery_extension_command_submission_encode(request, allocator)
	if !encoded do return nil, false
	defer delete(submission, allocator)
	output, output_error := make([]u8, int(ksawery.MAX_EXTENSION_OPERATION_COPY_BYTES), allocator)
	if output_error != nil do return nil, false
	defer delete(output, allocator)
	output_length, evaluated := host_provider_invoke(
		host,
		"source-control.external-operation",
		personal_generation,
		u64(route.route.operation),
		name,
		submission,
		output,
	)
	if !evaluated || output_length == 0 || output_length > u64(len(output)) do return nil, false
	data, data_error := new(Ksawery_Extension_Command_Operation_Data, allocator)
	if data_error != nil do return nil, false
	data.allocator = allocator
	plan, declaration, decoded := ksawery_extension_operation_decode(
		registry,
		output[:int(output_length)],
		&data.arguments,
	)
	if !decoded || plan.contributor != route.contributor {
		free(data, allocator)
		return nil, false
	}
	data.plan = plan
	data.declaration = declaration
	return data, true
}

/* ksawery_extension_command_operation_data_close releases one decoded route. */
ksawery_extension_command_operation_data_close :: proc(
	data: ^Ksawery_Extension_Command_Operation_Data,
) {
	if data == nil do return
	allocator := data.allocator
	data^ = {}
	if allocator.procedure != nil do free(data, allocator)
}

@(private)
ksawery_extension_command_submission_encode :: proc(
	request: ksawery.Extension_Command_Request,
	allocator: runtime.Allocator,
) -> ([]u8, bool) {
	if request.id == 0 || request.family == 0 || request.family_generation == 0 ||
	   request.action == 0 || allocator.procedure == nil {
		return nil, false
	}
	command_context := request.command_context
	repository_copy := command_context.repository
	repository := transmute([]u8)(ksawery.repository_context_string(&repository_copy))
	target: []u8
	if command_context.target_present {
		target = command_context.target.identity[:command_context.target.length]
	}
	context_bytes := u64(KSAWERY_COMMAND_CONTEXT_HEADER_BYTES + len(repository) + len(target))
	payload_bytes: u64
	for value in request.arguments {
		switch value.kind {
		case .Text, .Opaque:
			payload_bytes += u64(value.content.length)
		case .Selection, .Ref, .Revision, .Revision_Range:
			payload_bytes += u64(value.target.length)
		case .Boolean, .Closed_Choice, .Invalid:
		}
	}
	record_bytes, record_failure := bridge.ksawery_extension_command_submission_record_bytes(
		u64(len(request.arguments)), context_bytes, payload_bytes,
	)
	if record_failure.code != .None do return nil, false
	result, allocation_error := make([]u8, int(record_bytes), allocator)
	if allocation_error != nil do return nil, false
	header := bridge.Ksawery_Extension_Command_Submission_Header_Record {
		schema_version = bridge.KSAWERY_EXTENSION_COMMAND_SUBMISSION_SCHEMA_VERSION,
		record_bytes = record_bytes,
		request_id = u64(request.id),
		family_id = u64(request.family),
		family_generation = u64(request.family_generation),
		action_id = u64(request.action),
		confirmation_id = u64(request.confirmation),
		argument_count = u64(len(request.arguments)),
		context_bytes = context_bytes,
		payload_bytes = payload_bytes,
	}
	header_words := transmute([10]u64)header
	ksawery_extension_command_put_words(result, 0, header_words[:])
	context_start := int(bridge.KSAWERY_EXTENSION_COMMAND_SUBMISSION_HEADER_BYTES)
	context_end := context_start + int(context_bytes)
	context_output := result[context_start:context_end]
	if !ksawery_extension_command_context_encode(context_output, command_context, repository, target) {
		delete(result, allocator)
		return nil, false
	}
	values: [ksawery.MAX_EXTENSION_COMMAND_ARGUMENTS]bridge.Ksawery_Extension_Command_Value_Record
	records_start := context_end
	payload_start := records_start + int(
		u64(len(request.arguments)) * bridge.KSAWERY_EXTENSION_COMMAND_VALUE_RECORD_BYTES,
	)
	payload := result[payload_start:]
	payload_cursor := 0
	for value, index in request.arguments {
		record := &values[index]
		record.argument_id = u64(value.argument)
		record.kind = u64(value.kind)
		switch value.kind {
		case .Boolean:
			record.scalar = u64(value.boolean)
		case .Closed_Choice:
			record.scalar = u64(value.choice)
		case .Text, .Opaque:
			content := value.content
			record.content_offset = u64(payload_cursor)
			record.content_bytes = u64(content.length)
			copy(payload[payload_cursor:], content.bytes[:content.length])
			payload_cursor += int(content.length)
		case .Selection, .Ref, .Revision, .Revision_Range:
			target_copy := value.target
			record.target_family = u64(target_copy.family)
			record.target_generation = target_copy.generation
			record.target_offset = u64(payload_cursor)
			record.target_bytes = u64(target_copy.length)
			copy(payload[payload_cursor:], target_copy.identity[:target_copy.length])
			payload_cursor += int(target_copy.length)
		case .Invalid:
			delete(result, allocator)
			return nil, false
		}
		base := records_start + index * int(bridge.KSAWERY_EXTENSION_COMMAND_VALUE_RECORD_BYTES)
		record_words := transmute([9]u64)record^
		ksawery_extension_command_put_words(result, base, record_words[:])
	}
	if payload_cursor != len(payload) {
		delete(result, allocator)
		return nil, false
	}
	validation := bridge.ksawery_extension_command_submission_records_validate(
		header,
		values[:len(request.arguments)],
		context_output,
		payload,
	)
	if validation.code != .None {
		delete(result, allocator)
		return nil, false
	}
	return result, true
}

/* Ksawery_Extension_Command_Data owns one exact runtime-loaded family route. */
Ksawery_Extension_Command_Data :: struct {
	family:     ksawery.Extension_Command_Family_Generation,
	action:     ksawery.Extension_Command_Action_ID,
	arguments:  []ksawery.Extension_Command_Argument_Definition,
	choices:    []ksawery.Extension_Command_Choice,
	actions:    []ksawery.Extension_Command_Action_Definition,
	allocator:  runtime.Allocator,
}

/* ksawery_extension_command_load resolves and decodes one active shared-catalog route. */
ksawery_extension_command_load :: proc(
	host: ^Host_Context,
	provider: ^Ksawery_Extension_Provider_Data,
	personal_generation: u64,
	route: ksawery_command.Ksawery_Extension_Command_Route,
	name: string,
	allocator: runtime.Allocator,
) -> (^Ksawery_Extension_Command_Data, bool) {
	if host == nil || provider == nil || !provider.enabled || personal_generation == 0 ||
	   route.route.provider != command.RACKET_KSAWERY_ROUTE_PROVIDER || route.route.operation == 0 ||
	   len(name) == 0 || allocator.procedure == nil {
		return nil, false
	}
	storage, allocation_error := make(
		[]u8,
		int(ksawery.MAX_EXTENSION_COMMAND_COPY_BYTES + KSAWERY_COMMAND_FAMILY_ENVELOPE_BYTES),
		allocator,
	)
	if allocation_error != nil do return nil, false
	defer delete(storage, allocator)
	length, loaded := host_provider_invoke(
		host,
		"source-control.command-family",
		personal_generation,
		u64(route.route.operation),
		name,
		nil,
		storage,
	)
	if !loaded || length < KSAWERY_COMMAND_FAMILY_ENVELOPE_BYTES ||
	   length > u64(len(storage)) {
		return nil, false
	}
	action := ksawery.Extension_Command_Action_ID(ksawery_extension_command_word(storage, 0))
	family_length := ksawery_extension_command_word(storage, 8)
	if action == 0 || family_length != length - KSAWERY_COMMAND_FAMILY_ENVELOPE_BYTES {
		return nil, false
	}
	data, decoded := ksawery_extension_command_decode(
		provider,
		storage[KSAWERY_COMMAND_FAMILY_ENVELOPE_BYTES:int(length)],
		action,
		allocator,
	)
	if !decoded do return nil, false
	return data, true
}

/* ksawery_extension_command_decode validates and owns one copied active family. */
ksawery_extension_command_decode :: proc(
	provider: ^Ksawery_Extension_Provider_Data,
	input: []u8,
	action: ksawery.Extension_Command_Action_ID,
	allocator: runtime.Allocator,
) -> (^Ksawery_Extension_Command_Data, bool) {
	if provider == nil || len(input) < KSAWERY_COMMAND_FAMILY_HEADER_BYTES || action == 0 do return nil, false
	header: [18]u64
	for &value, index in header do value = ksawery_extension_command_word(input, index * 8)
	argument_count, action_count, choice_count := header[7], header[8], header[9]
	if header[0] != 1 || header[1] != u64(len(input)) ||
	   header[2] != u64(provider.inspection.handle.generation) || header[3] == 0 ||
	   header[4] == 0 || header[5] == 0 || header[6] == 0 || header[10] > u64(len(input)) ||
	   argument_count > u64(ksawery.MAX_EXTENSION_COMMAND_ARGUMENTS) ||
	   action_count == 0 || action_count > u64(ksawery.MAX_EXTENSION_COMMAND_ACTIONS) ||
	   choice_count > u64(ksawery.MAX_EXTENSION_COMMAND_ARGUMENTS) *
	                  u64(ksawery.MAX_EXTENSION_COMMAND_CHOICES) || header[17] != 0 {
		return nil, false
	}
	record_bytes := u64(KSAWERY_COMMAND_FAMILY_HEADER_BYTES) +
		argument_count * KSAWERY_COMMAND_ARGUMENT_RECORD_BYTES +
		choice_count * KSAWERY_COMMAND_CHOICE_RECORD_BYTES +
		action_count * KSAWERY_COMMAND_ACTION_RECORD_BYTES
	if record_bytes > u64(len(input)) || header[10] != u64(len(input)) - record_bytes do return nil, false
	contributor, contributor_ok := ksawery_extension_command_text(
		input, header[11], header[12], record_bytes, u64(ksawery.MAX_EXTENSION_IDENTITY_BYTES), false,
	)
	family_identity, family_identity_ok := ksawery_extension_command_text(
		input, header[13], header[14], record_bytes, u64(ksawery.MAX_EXTENSION_IDENTITY_BYTES), false,
	)
	family_label, family_label_ok := ksawery_extension_command_text(
		input, header[15], header[16], record_bytes, u64(ksawery.MAX_EXTENSION_LABEL_BYTES), false,
	)
	provider_identity := provider.inspection.identity
	if !contributor_ok || !family_identity_ok || !family_label_ok ||
	   contributor != string(provider_identity.bytes[:provider_identity.length]) ||
	   !ksawery_extension_command_contribution_is(provider, ksawery.Contribution_ID(header[3]), header[6]) {
		return nil, false
	}
	data, allocation_error := new(Ksawery_Extension_Command_Data, allocator)
	if allocation_error != nil do return nil, false
	data.allocator = allocator
	defer if data != nil do ksawery_extension_command_data_close(data)
	data.arguments, allocation_error = make(
		[]ksawery.Extension_Command_Argument_Definition, int(argument_count), allocator,
	)
	if allocation_error != nil do return nil, false
	data.choices, allocation_error = make([]ksawery.Extension_Command_Choice, int(choice_count), allocator)
	if allocation_error != nil do return nil, false
	data.actions, allocation_error = make(
		[]ksawery.Extension_Command_Action_Definition, int(action_count), allocator,
	)
	if allocation_error != nil do return nil, false

	choice_base := KSAWERY_COMMAND_FAMILY_HEADER_BYTES + int(argument_count) * KSAWERY_COMMAND_ARGUMENT_RECORD_BYTES
	for &choice, index in data.choices {
		base := choice_base + index * KSAWERY_COMMAND_CHOICE_RECORD_BYTES
		identity, identity_ok := ksawery_extension_command_text(
			input,
			ksawery_extension_command_word(input, base + 8),
			ksawery_extension_command_word(input, base + 16),
			record_bytes,
			u64(ksawery.MAX_EXTENSION_IDENTITY_BYTES),
			false,
		)
		label, label_ok := ksawery_extension_command_text(
			input,
			ksawery_extension_command_word(input, base + 24),
			ksawery_extension_command_word(input, base + 32),
			record_bytes,
			u64(ksawery.MAX_EXTENSION_LABEL_BYTES),
			false,
		)
		choice.id = ksawery.Extension_Command_Choice_ID(ksawery_extension_command_word(input, base))
		if choice.id == 0 || !identity_ok || !label_ok ||
		   !ksawery.extension_identity_assign(&choice.identity, identity) ||
		   !ksawery.extension_label_assign(&choice.label, label) {
			return nil, false
		}
	}

	for &argument, index in data.arguments {
		base := KSAWERY_COMMAND_FAMILY_HEADER_BYTES + index * KSAWERY_COMMAND_ARGUMENT_RECORD_BYTES
		kind := ksawery_extension_command_word(input, base + 8)
		required := ksawery_extension_command_word(input, base + 16)
		maximum_bytes := ksawery_extension_command_word(input, base + 24)
		identity, identity_ok := ksawery_extension_command_text(
			input, ksawery_extension_command_word(input, base + 32),
			ksawery_extension_command_word(input, base + 40), record_bytes,
			u64(ksawery.MAX_EXTENSION_IDENTITY_BYTES), false,
		)
		label, label_ok := ksawery_extension_command_text(
			input, ksawery_extension_command_word(input, base + 48),
			ksawery_extension_command_word(input, base + 56), record_bytes,
			u64(ksawery.MAX_EXTENSION_LABEL_BYTES), false,
		)
		choice_start := ksawery_extension_command_word(input, base + 64)
		argument_choices := ksawery_extension_command_word(input, base + 72)
		argument.id = ksawery.Extension_Command_Argument_ID(ksawery_extension_command_word(input, base))
		if argument.id == 0 || kind == 0 || kind > u64(ksawery.Extension_Command_Argument_Kind.Opaque) ||
		   required > 1 || maximum_bytes > u64(ksawery.MAX_EXTENSION_COMMAND_VALUE_BYTES) ||
		   choice_start > choice_count || argument_choices > choice_count - choice_start ||
		   !identity_ok || !label_ok ||
		   !ksawery.extension_identity_assign(&argument.identity, identity) ||
		   !ksawery.extension_label_assign(&argument.label, label) {
			return nil, false
		}
		argument.kind = ksawery.Extension_Command_Argument_Kind(kind)
		argument.required = required == 1
		argument.max_bytes = u16(maximum_bytes)
		argument.choices = data.choices[int(choice_start):int(choice_start + argument_choices)]
	}

	action_base := choice_base + int(choice_count) * KSAWERY_COMMAND_CHOICE_RECORD_BYTES
	for &definition, index in data.actions {
		base := action_base + index * KSAWERY_COMMAND_ACTION_RECORD_BYTES
		authority := ksawery_extension_command_word(input, base + 8)
		operation_requirement := ksawery_extension_command_word(input, base + 32)
		mutates := ksawery_extension_command_word(input, base + 40)
		confirmation := ksawery_extension_command_word(input, base + 48)
		core_operation := ksawery_extension_command_word(input, base + 88)
		identity, identity_ok := ksawery_extension_command_text(
			input, ksawery_extension_command_word(input, base + 56),
			ksawery_extension_command_word(input, base + 64), record_bytes,
			u64(ksawery.MAX_EXTENSION_IDENTITY_BYTES), false,
		)
		label, label_ok := ksawery_extension_command_text(
			input, ksawery_extension_command_word(input, base + 72),
			ksawery_extension_command_word(input, base + 80), record_bytes,
			u64(ksawery.MAX_EXTENSION_LABEL_BYTES), false,
		)
		definition.id = ksawery.Extension_Command_Action_ID(ksawery_extension_command_word(input, base))
		if definition.id == 0 || authority > u64(ksawery.Extension_Authority.Assist_Conflict) ||
		   operation_requirement == 0 ||
		   operation_requirement > u64(ksawery.Extension_Command_Operation_Requirement.Conflict) ||
		   mutates > 1 || confirmation > 1 ||
		   core_operation > u64(ksawery.Repository_Operation_Kind.Resolve_Conflict) ||
		   !identity_ok || !label_ok ||
		   !ksawery.extension_identity_assign(&definition.identity, identity) ||
		   !ksawery.extension_label_assign(&definition.label, label) {
			return nil, false
		}
		definition.authority = ksawery.Extension_Authority(authority)
		definition.observations = transmute(ksawery.Extension_Observation_Families)u16(
			ksawery_extension_command_word(input, base + 16),
		)
		definition.target_families = transmute(ksawery.Extension_Command_Target_Families)u16(
			ksawery_extension_command_word(input, base + 24),
		)
		definition.operation_requirement = ksawery.Extension_Command_Operation_Requirement(operation_requirement)
		definition.core_operation = ksawery.Repository_Operation_Kind(core_operation)
		definition.mutates_repository = mutates == 1
		definition.confirmation_required = confirmation == 1
		if !ksawery_extension_command_contribution_authorizes(
			provider,
			ksawery.Contribution_ID(header[3]),
			definition.authority,
		) {
			return nil, false
		}
	}

	data.action = action
	data.family = {
		contributor = provider.inspection.handle,
		contributor_identity = provider.inspection.identity,
		contribution = ksawery.Contribution_ID(header[3]),
		family = ksawery.Extension_Command_Family_ID(header[4]),
		generation = ksawery.Extension_Command_Family_Generation_ID(header[5]),
		observations = transmute(ksawery.Extension_Observation_Families)u16(header[6]),
		arguments = data.arguments,
		actions = data.actions,
	}
	if !ksawery.extension_identity_assign(&data.family.identity, family_identity) ||
	   !ksawery.extension_label_assign(&data.family.label, family_label) {
		return nil, false
	}
	_, failure := ksawery.extension_command_family_validate(data.family)
	if failure.code != .None do return nil, false
	found := false
	for definition in data.actions {
		if definition.id == action {
			found = true
			break
		}
	}
	if !found do return nil, false
	result := data
	data = nil
	return result, true
}

@(private)
ksawery_extension_command_contribution_is :: proc(
	provider: ^Ksawery_Extension_Provider_Data,
	id: ksawery.Contribution_ID,
	observations: u64,
) -> bool {
	for contribution in provider.contributions {
		declared_observations := contribution.required_observations
		if contribution.contribution_id == u64(id) &&
		   contribution.kind == u64(ksawery.Contribution_Kind.Command_Family) &&
		   observations & ~declared_observations == 0 &&
		   contribution.requested_authorities != 0 {
			return true
		}
	}
	return false
}

@(private)
ksawery_extension_command_contribution_authorizes :: proc(
	provider: ^Ksawery_Extension_Provider_Data,
	id: ksawery.Contribution_ID,
	authority: ksawery.Extension_Authority,
) -> bool {
	if provider == nil || id == 0 do return false
	for contribution in provider.contributions {
		if contribution.contribution_id == u64(id) {
			return contribution.requested_authorities & (u64(1) << u64(authority)) != 0
		}
	}
	return false
}

@(private)
ksawery_extension_command_text :: proc(
	input: []u8,
	offset, length, minimum_offset, maximum: u64,
	allow_empty: bool,
) -> (string, bool) {
	if length == 0 do return "", allow_empty && offset == 0
	if length > maximum || offset < minimum_offset || offset > u64(len(input)) ||
	   length > u64(len(input)) - offset {
		return "", false
	}
	return string(input[int(offset):int(offset + length)]), true
}

@(private)
ksawery_extension_command_context_encode :: proc(
	output: []u8,
	command_context: ksawery.Extension_Command_Context,
	repository, target: []u8,
) -> bool {
	if len(output) != KSAWERY_COMMAND_CONTEXT_HEADER_BYTES + len(repository) + len(target) ||
	   ksawery.extension_command_context_validate(command_context).code != .None || len(repository) == 0 ||
	   command_context.target_present != (len(target) > 0) {
		return false
	}
	target_offset := KSAWERY_COMMAND_CONTEXT_HEADER_BYTES + len(repository)
	words := [?]u64 {
		1,
		u64(len(output)),
		u64(command_context.contributor.contributor),
		u64(command_context.contributor.generation),
		u64(command_context.repository_generation),
		u64(command_context.worktree_generation),
		u64(command_context.observation),
		command_context.observation_generation,
		u64(command_context.surface) - 1,
		u64(command_context.surface_generation),
		command_context.selection_generation,
		u64(command_context.target_present),
		u64(command_context.target.family),
		command_context.target.generation,
		u64(command_context.operation_state),
		u64(command_context.mutation_available),
		u64(command_context.capability_generation),
		u64(command_context.observation_truncated),
		u64(command_context.privacy_filtered),
		KSAWERY_COMMAND_CONTEXT_HEADER_BYTES,
		u64(len(repository)),
		u64(target_offset),
		u64(len(target)),
	}
	ksawery_extension_command_put_words(output, 0, words[:])
	copy(output[KSAWERY_COMMAND_CONTEXT_HEADER_BYTES:], repository)
	copy(output[target_offset:], target)
	return true
}

@(private)
ksawery_extension_command_put_words :: proc(output: []u8, offset: int, words: []u64) {
	for word, index in words {
		assert(endian.put_u64(output[offset + index * 8:], .Little, word))
	}
}

@(private)
ksawery_extension_command_word :: proc(input: []u8, offset: int) -> u64 {
	value, ok := endian.get_u64(input[offset:], .Little)
	assert(ok)
	return value
}

/* ksawery_extension_command_data_close releases one decoded family and its copied records. */
ksawery_extension_command_data_close :: proc(data: ^Ksawery_Extension_Command_Data) {
	if data == nil do return
	allocator := data.allocator
	if allocator.procedure != nil {
		delete(data.actions, allocator)
		delete(data.choices, allocator)
		delete(data.arguments, allocator)
	}
	free(data, allocator)
}
