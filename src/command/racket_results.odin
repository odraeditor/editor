// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../bridge"
import "../editor"
import "../hosting"
import "../result_set"
import base_runtime "base:runtime"
import endian "core:encoding/endian"
import "core:unicode/utf8"

/* Racket_Result_Turn reports the final copied scope and callback count. */
Racket_Result_Turn :: struct {
	scope: Result_Capability_Scope,
	calls: u16,
}

@(private)
Racket_Result_Call :: struct {
	capability: Result_Capability_Context,
	token:      u64,
	scope:      Result_Capability_Scope,
	calls:      u16,
	failure:    result_set.Failure,
}

/* racket_result_turn lends one exact bounded result capability to Racket. */
racket_result_turn :: proc(
	racket_runtime: ^hosting.Runtime,
	capability: Result_Capability_Context,
	scenario: i32,
) -> (Racket_Result_Turn, bool, result_set.Failure) {
	if racket_runtime == nil do return {}, false, result_set.Failure{code = .Invalid_Registry}
	scope, scoped, failure := result_capability_scope(capability)
	if !scoped do return {}, false, failure
	token := u64(scope.editor_session_id) ~ (u64(scope.set_id) << 17) ~
	         (scope.capability_generation << 41)
	if token == 0 do token = 1
	call := Racket_Result_Call{capability = capability, token = token, scope = scope}
	executed, runtime_failure := hosting.runtime_result_probe(
		racket_runtime, scenario, token, racket_result_callback, &call)
	if !executed {
		turn := Racket_Result_Turn{scope = call.scope, calls = call.calls}
		if call.failure.code != .None do return turn, false, call.failure
		return turn, false, result_set.Failure {
			code = .Invalid_Registry,
			actual = u64(runtime_failure.code),
		}
	}
	if call.failure.code != .None do return {}, false, call.failure
	return Racket_Result_Turn{scope = call.scope, calls = call.calls}, true, {}
}

@(private)
racket_result_callback :: proc "c" (
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
	call := (^Racket_Result_Call)(user_data)
	if call == nil || kind != .Result || generation == 0 || token != call.token ||
	   domain_context != 0 || arg0 != 0 || arg1 != 0 || output_length == nil ||
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
		if input == nil do return 2
		input_bytes = ([^]u8)(input)[:int(input_length)]
	}
	destination: []u8
	if output_capacity > 0 {
		if output == nil do return 2
		destination = ([^]u8)(output)[:int(output_capacity)]
	}
	call.calls += 1
	op := bridge.Result_Capability_Operation(operation)
	switch op {
	case .Scope:
		if input_length != 0 || output_capacity != bridge.RESULT_SCOPE_RECORD_BYTES do return 2
		racket_result_encode_scope(destination, call.scope, generation)
		call.capability.capability_generation = generation
		call.scope.capability_generation = generation
		output_length^ = bridge.RESULT_SCOPE_RECORD_BYTES
		return 0
	case .Inspect:
		if input_length != bridge.RESULT_SCOPE_RECORD_BYTES ||
		   output_capacity > bridge.MAX_RESULT_INSPECTION_BYTES ||
		   !racket_result_scope_matches(input_bytes, call.scope, generation) {
			return 2
		}
		view, inspected, inspect_failure := result_capability_inspect(
			call.capability, racket_result_decode_scope(input_bytes))
		if !inspected {
			return racket_result_reject(call, inspect_failure, failure_code, limit, actual)
		}
		written, encoded := racket_result_encode_view(destination, view, call, generation)
		if !encoded do return 2
		output_length^ = written
		return 0
	case .Publish:
		if input_length < bridge.RESULT_PUBLICATION_HEADER_BYTES ||
		   output_capacity != bridge.RESULT_OUTCOME_RECORD_BYTES {
			call.failure = result_set.Failure {
				code = .Invalid_Publication,
				limit = bridge.RESULT_PUBLICATION_HEADER_BYTES,
				actual = input_length,
			}
			return 2
		}
		expected := racket_result_decode_scope(input_bytes)
		if !racket_result_scope_matches(
			input_bytes[:int(bridge.RESULT_SCOPE_RECORD_BYTES)], call.scope, generation) {
			call.failure = result_set.Failure{code = .Invalid_Publication, actual = 2}
			return 2
		}
		publication, decoded := racket_result_decode_publication(input_bytes, call.capability)
		if !decoded {
			call.failure = result_set.Failure{code = .Invalid_Publication, actual = 3}
			return 2
		}
		result, published, publish_failure := result_capability_publish(
			call.capability, expected, publication)
		if !published {
			return racket_result_reject(call, publish_failure, failure_code, limit, actual)
		}
		call.scope.set_generation = result.generation
		racket_result_encode_outcome(destination, call.scope, result, generation)
		output_length^ = bridge.RESULT_OUTCOME_RECORD_BYTES
		value^ = u64(result.transition)
		return 0
	case .Move:
		if input_length != bridge.RESULT_MOVEMENT_REQUEST_BYTES ||
		   output_capacity != bridge.RESULT_OUTCOME_RECORD_BYTES ||
		   !racket_result_scope_matches(
			input_bytes[:int(bridge.RESULT_SCOPE_RECORD_BYTES)], call.scope, generation) {
			return 2
		}
		movement_value := racket_result_read(input_bytes, int(bridge.RESULT_SCOPE_RECORD_BYTES))
		if movement_value < u64(result_set.Movement.First) ||
		   movement_value > u64(result_set.Movement.Last) {
			return 2
		}
		result, moved, move_failure := result_capability_move(
			call.capability,
			racket_result_decode_scope(input_bytes),
			result_set.Movement(movement_value),
		)
		if !moved do return racket_result_reject(call, move_failure, failure_code, limit, actual)
		racket_result_encode_outcome(destination, call.scope, result, generation)
		output_length^ = bridge.RESULT_OUTCOME_RECORD_BYTES
		value^ = u64(result.transition)
		return 0
	}
	return 2
}

@(private)
racket_result_decode_publication :: proc(
	input: []u8,
	capability: Result_Capability_Context,
) -> (result_set.Publication, bool) {
	location_count := racket_result_read(input, 168)
	group_count := racket_result_read(input, 176)
	descriptor_bytes := racket_result_read(input, 184)
	text_bytes := racket_result_read(input, 192)
	required, admitted := bridge.result_publication_record_bytes(
		location_count, group_count, text_bytes)
	if !admitted || required != u64(len(input)) || descriptor_bytes > text_bytes ||
	   location_count > u64(max(int)) || group_count > u64(max(int)) {
		return {}, false
	}
	locations := make([]result_set.Location_Definition, int(location_count), context.temp_allocator)
	groups := make([]result_set.Group_Definition, int(group_count), context.temp_allocator)
	if len(locations) != int(location_count) || len(groups) != int(group_count) do return {}, false
	defer delete(locations, context.temp_allocator)
	defer delete(groups, context.temp_allocator)
	records_end := bridge.RESULT_PUBLICATION_HEADER_BYTES +
	               location_count * bridge.RESULT_LOCATION_RECORD_BYTES +
	               group_count * bridge.RESULT_GROUP_RECORD_BYTES
	if records_end + text_bytes != required do return {}, false
	descriptor_offset := records_end
	descriptor, descriptor_ok := racket_result_text(input, descriptor_offset, descriptor_bytes)
	if !descriptor_ok do return {}, false
	text_cursor := descriptor_offset + descriptor_bytes
	for &location, index in locations {
		base := int(bridge.RESULT_PUBLICATION_HEADER_BYTES) +
		        index * int(bridge.RESULT_LOCATION_RECORD_BYTES)
		preview_offset := racket_result_read(input, base + 56)
		preview_bytes := racket_result_read(input, base + 64)
		annotation_offset := racket_result_read(input, base + 72)
		annotation_bytes := racket_result_read(input, base + 80)
		if preview_offset != text_cursor || annotation_offset != preview_offset + preview_bytes {
			return {}, false
		}
		preview, preview_ok := racket_result_text(input, preview_offset, preview_bytes)
		annotation, annotation_ok := racket_result_text(input, annotation_offset, annotation_bytes)
		if !preview_ok || !annotation_ok do return {}, false
		text_cursor = annotation_offset + annotation_bytes
		location = {
			id = result_set.Location_ID(racket_result_read(input, base)),
			group_id = result_set.Group_ID(racket_result_read(input, base + 8)),
			buffer_id = racket_result_buffer_id(racket_result_read(input, base + 16)),
			revision = racket_result_revision(racket_result_read(input, base + 24)),
			start = racket_result_offset(racket_result_read(input, base + 32)),
			end = racket_result_offset(racket_result_read(input, base + 40)),
			source_identity = racket_result_read(input, base + 48),
			preview = preview,
			annotation = annotation,
		}
	}
	group_base := int(bridge.RESULT_PUBLICATION_HEADER_BYTES +
	              location_count * bridge.RESULT_LOCATION_RECORD_BYTES)
	for &group, index in groups {
		base := group_base + index * int(bridge.RESULT_GROUP_RECORD_BYTES)
		label_offset := racket_result_read(input, base + 8)
		label_bytes := racket_result_read(input, base + 16)
		if label_offset != text_cursor do return {}, false
		label, label_ok := racket_result_text(input, label_offset, label_bytes)
		if !label_ok do return {}, false
		text_cursor = label_offset + label_bytes
		group = {id = result_set.Group_ID(racket_result_read(input, base)), label = label}
	}
	if text_cursor != required do return {}, false
	completeness_value := racket_result_read(input, 72)
	edit_value := racket_result_read(input, 144)
	source_kind := racket_result_read(input, 64)
	if completeness_value < u64(result_set.Completeness.Complete) ||
	   completeness_value > u64(result_set.Completeness.Incomplete) ||
	   edit_value < u64(result_set.Edit_Capability.Read_Only) ||
	   edit_value > u64(result_set.Edit_Capability.Multiple_Buffers) ||
	   source_kind != u64(result_set.Source_Kind.Programmable) ||
	   racket_result_read(input, 80) > 1 || racket_result_read(input, 160) > 1 {
		return {}, false
	}
	publication := result_set.Publication {
		set_id = capability.set_id,
		expected_generation = result_set.Result_Set_Generation(racket_result_read(input, 32)),
		source = {
			id = result_set.Source_ID(racket_result_read(input, 48)),
			generation = result_set.Source_Generation(racket_result_read(input, 56)),
			kind = .Programmable,
		},
		completeness = result_set.Completeness(completeness_value),
		continuation = {
			present = racket_result_read(input, 80) == 1,
			provider = racket_result_read(input, 88),
			cursor = racket_result_read(input, 96),
			limit = racket_result_read(input, 104),
		},
		refresh = {
			provider = racket_result_read(input, 112),
			query_identity = racket_result_read(input, 120),
			policy_generation = racket_result_read(input, 128),
			scope_generation = racket_result_read(input, 136),
		},
		edit_capability = result_set.Edit_Capability(edit_value),
		locations = locations,
		groups = groups,
		selected = result_set.Location_ID(racket_result_read(input, 152)),
		has_selection = racket_result_read(input, 160) == 1,
		metadata = {descriptor = descriptor},
	}
	for &item, index in publication.metadata.values {
		item = racket_result_read(input, 200 + index * 8)
	}
	return publication, true
}

@(private)
racket_result_encode_view :: proc(
	destination: []u8,
	view: result_set.View,
	call: ^Racket_Result_Call,
	generation: u64,
) -> (u64, bool) {
	text_bytes := u64(len(view.metadata.descriptor))
	for location in view.locations do text_bytes += u64(len(location.preview) + len(location.annotation))
	for group in view.groups do text_bytes += u64(len(group.label))
	required, admitted := bridge.result_view_record_bytes(
		u64(len(view.locations)), u64(len(view.groups)), text_bytes)
	if !admitted || required > u64(len(destination)) do return 0, false
	target := destination[:int(required)]
	scope := call.scope
	scope.set_generation = view.generation
	racket_result_encode_scope(target, scope, generation)
	records_end := bridge.RESULT_VIEW_HEADER_BYTES +
	               u64(len(view.locations)) * bridge.RESULT_LOCATION_RECORD_BYTES +
	               u64(len(view.groups)) * bridge.RESULT_GROUP_RECORD_BYTES
	descriptor_offset := records_end
	values := [?]u64 {
		u64(view.source.id), u64(view.source.generation), u64(view.source.kind),
		descriptor_offset, u64(len(view.metadata.descriptor)),
		view.metadata.values[0], view.metadata.values[1], view.metadata.values[2],
		view.metadata.values[3], view.metadata.values[4], view.metadata.values[5],
		view.metadata.values[6], view.metadata.values[7], u64(view.completeness),
		u64(view.continuation.present), view.continuation.provider, view.continuation.cursor,
		view.continuation.limit, view.refresh.provider, view.refresh.query_identity,
		view.refresh.policy_generation, view.refresh.scope_generation, u64(view.edit_capability),
		u64(view.selected_index), u64(view.has_selection), u64(len(view.locations)),
		u64(len(view.groups)), text_bytes, u64(view.accounting.sets),
		u64(view.accounting.locations), u64(view.accounting.groups), view.accounting.preview_bytes,
		view.accounting.annotation_bytes, view.accounting.group_label_bytes,
		view.accounting.metadata_bytes, view.accounting.retained_bytes,
	}
	offset := int(bridge.RESULT_SCOPE_RECORD_BYTES)
	for item in values do racket_result_put(target, &offset, item)
	if offset != int(bridge.RESULT_VIEW_HEADER_BYTES) do return 0, false
	text_offset := int(records_end)
	copy(target[text_offset:], view.metadata.descriptor)
	text_offset += len(view.metadata.descriptor)
	for location, index in view.locations {
		base := int(bridge.RESULT_VIEW_HEADER_BYTES) +
		        index * int(bridge.RESULT_LOCATION_RECORD_BYTES)
		preview_offset := text_offset
		copy(target[text_offset:], location.preview)
		text_offset += len(location.preview)
		annotation_offset := text_offset
		copy(target[text_offset:], location.annotation)
		text_offset += len(location.annotation)
		location_values := [?]u64 {
			u64(location.id), u64(location.group_id), u64(location.buffer_id),
			u64(location.revision), u64(location.start), u64(location.end),
			location.source_identity, u64(preview_offset), u64(len(location.preview)),
			u64(annotation_offset), u64(len(location.annotation)),
		}
		location_offset := base
		for item in location_values do racket_result_put(target, &location_offset, item)
	}
	group_base := int(bridge.RESULT_VIEW_HEADER_BYTES) +
	              len(view.locations) * int(bridge.RESULT_LOCATION_RECORD_BYTES)
	for group, index in view.groups {
		base := group_base + index * int(bridge.RESULT_GROUP_RECORD_BYTES)
		label_offset := text_offset
		copy(target[text_offset:], group.label)
		text_offset += len(group.label)
		group_offset := base
		racket_result_put(target, &group_offset, u64(group.id))
		racket_result_put(target, &group_offset, u64(label_offset))
		racket_result_put(target, &group_offset, u64(len(group.label)))
	}
	return required, text_offset == int(required)
}

@(private)
racket_result_encode_scope :: proc(
	destination: []u8,
	scope: Result_Capability_Scope,
	generation: u64,
) {
	offset := 0
	values := [?]u64 {
		bridge.RESULT_CAPABILITY_SCHEMA_VERSION,
		u64(transmute(u8)scope.access),
		u64(scope.editor_session_id),
		u64(scope.set_id),
		u64(scope.set_generation),
		generation,
	}
	for item in values do racket_result_put(destination, &offset, item)
}

@(private)
racket_result_decode_scope :: proc(input: []u8) -> Result_Capability_Scope {
	return {
		editor_session_id = Editor_Session_ID(racket_result_read(input, 16)),
		access = transmute(Result_Access_Set)u8(racket_result_read(input, 8)),
		set_id = result_set.Result_Set_ID(racket_result_read(input, 24)),
		set_generation = result_set.Result_Set_Generation(racket_result_read(input, 32)),
		capability_generation = racket_result_read(input, 40),
	}
}

@(private)
racket_result_scope_matches :: proc(
	input: []u8,
	scope: Result_Capability_Scope,
	generation: u64,
) -> bool {
	if u64(len(input)) != bridge.RESULT_SCOPE_RECORD_BYTES do return false
	expected: [bridge.RESULT_SCOPE_RECORD_BYTES]u8
	racket_result_encode_scope(expected[:], scope, generation)
	for byte, index in input do if byte != expected[index] do return false
	return true
}

@(private)
racket_result_encode_outcome :: proc(
	destination: []u8,
	scope: Result_Capability_Scope,
	result: result_set.Result,
	generation: u64,
) {
	racket_result_encode_scope(destination, scope, generation)
	offset := int(bridge.RESULT_SCOPE_RECORD_BYTES)
	items := [?]u64 {
		u64(result.transition), u64(result.set_id), u64(result.generation),
		u64(result.location_id), u64(result.selected_index), u64(result.has_selection),
	}
	for item in items do racket_result_put(destination, &offset, item)
}

@(private)
racket_result_reject :: proc(
	call: ^Racket_Result_Call,
	failure: result_set.Failure,
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
racket_result_text :: proc(input: []u8, offset, length: u64) -> (string, bool) {
	if offset > u64(len(input)) || length > u64(len(input)) - offset ||
	   offset > u64(max(int)) || length > u64(max(int)) {
		return "", false
	}
	value := string(input[int(offset):int(offset + length)])
	return value, utf8.valid_string(value)
}

@(private)
racket_result_read :: proc(input: []u8, offset: int) -> u64 {
	value, ok := endian.get_u64(input[offset:], .Little)
	assert(ok)
	return value
}

@(private)
racket_result_put :: proc(destination: []u8, offset: ^int, value: u64) {
	written := endian.put_u64(destination[offset^:], .Little, value)
	assert(written)
	offset^ += 8
}

@(private)
racket_result_buffer_id :: proc(value: u64) -> editor.Buffer_ID {
	return editor.Buffer_ID(value)
}

@(private)
racket_result_revision :: proc(value: u64) -> editor.Revision {
	return editor.Revision(value)
}

@(private)
racket_result_offset :: proc(value: u64) -> editor.Byte_Offset {
	return editor.Byte_Offset(value)
}
