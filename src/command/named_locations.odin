// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../hosting"
import "base:runtime"
import endian "core:encoding/endian"

/* NAMED_LOCATION_SCHEMA_VERSION identifies the native hosting wire contract. */
NAMED_LOCATION_SCHEMA_VERSION :: u64(1)
/* NAMED_LOCATION_REQUEST_HEADER_BYTES is the fixed request prefix length. */
NAMED_LOCATION_REQUEST_HEADER_BYTES :: 64
/* NAMED_LOCATION_RESULT_HEADER_BYTES is the fixed result prefix length. */
NAMED_LOCATION_RESULT_HEADER_BYTES :: 48
/* NAMED_LOCATION_RECORD_BYTES is one fixed location-record length. */
NAMED_LOCATION_RECORD_BYTES :: 72
/* MAX_NAMED_LOCATIONS bounds one copied persistent location result. */
MAX_NAMED_LOCATIONS :: 256
/* NAMED_LOCATION_ABSENT_MARK encodes a location without a retained mark. */
NAMED_LOCATION_ABSENT_MARK :: max(u64)

/* Named_Location_Action selects one persistent location operation. */
Named_Location_Action :: enum u64 {
	Invalid,
	Save,
	List,
}

/* Named_Location_Descriptor is one copied persistent location record. */
Named_Location_Descriptor :: struct {
	name:          string,
	target:        string,
	point:         u64,
	mark:          u64,
	has_mark:      bool,
	region_active: bool,
	summary:       string,
}

/* Named_Location_Batch owns copied location records until explicit close. */
Named_Location_Batch :: struct {
	state:       rawptr,
	generation:  u64,
	locations:   []Named_Location_Descriptor,
	diagnostic:  string,
}

@(private)
Named_Location_Batch_State :: struct {
	storage:    []byte,
	locations:  []Named_Location_Descriptor,
	allocator:  runtime.Allocator,
}

/* named_locations_list returns the bounded persistent location inventory. */
named_locations_list :: proc(
	racket_runtime: ^hosting.Runtime,
	configuration_root: string,
	allocator: runtime.Allocator,
) -> (Named_Location_Batch, bool, Failure_Context) {
	return named_location_command(
		racket_runtime, configuration_root, .List, "", "", 0, 0, false, false, "", allocator,
	)
}

/* named_location_save atomically stores one persistent document location. */
named_location_save :: proc(
	racket_runtime: ^hosting.Runtime,
	configuration_root, name, target: string,
	point, mark: u64,
	has_mark, region_active: bool,
	summary: string,
	allocator: runtime.Allocator,
) -> (Named_Location_Batch, bool, Failure_Context) {
	return named_location_command(
		racket_runtime, configuration_root, .Save, name, target, point, mark,
		has_mark, region_active, summary, allocator,
	)
}

/* named_location_batch_close releases one copied persistent location result. */
named_location_batch_close :: proc(batch: ^Named_Location_Batch) -> bool {
	if batch == nil || batch.state == nil do return false
	state := (^Named_Location_Batch_State)(batch.state)
	named_location_batch_state_destroy(state)
	batch^ = {}
	return true
}

@(private)
named_location_command :: proc(
	racket_runtime: ^hosting.Runtime,
	configuration_root: string,
	action: Named_Location_Action,
	name, target: string,
	point, mark: u64,
	has_mark, region_active: bool,
	summary: string,
	allocator: runtime.Allocator,
) -> (Named_Location_Batch, bool, Failure_Context) {
	if racket_runtime == nil || len(configuration_root) == 0 || action == .Invalid ||
	   (action == .Save && (len(name) == 0 || len(target) == 0 || len(summary) == 0)) ||
	   (region_active && !has_mark) {
		return {}, false, Failure_Context{code = .Invalid_Request}
	}
	request, encoded := named_location_request_encode(
		action, name, target, point, mark, has_mark, region_active, summary, allocator,
	)
	if !encoded do return {}, false, Failure_Context{code = .Temporary_Memory_Limit}
	defer delete(request, allocator)
	output, output_error := make([]byte, hosting.MAX_NAMED_LOCATION_COMMAND_BYTES, allocator)
	if output_error != nil do return {}, false, Failure_Context{code = .Temporary_Memory_Limit}
	defer delete(output, allocator)
	output_length, transferred, transfer_failure := hosting.runtime_named_location_command(
		racket_runtime, configuration_root, request, output,
	)
	if !transferred {
		return {}, false, hosting_failure_context({}, transfer_failure)
	}
	batch, decoded := named_location_result_decode(output[:int(output_length)], action, allocator)
	if !decoded do return {}, false, Failure_Context{code = .Wrong_Result}
	if len(batch.diagnostic) > 0 {
		named_location_batch_close(&batch)
		return {}, false, Failure_Context{code = .Wrong_Result}
	}
	return batch, true, {}
}

@(private)
named_location_request_encode :: proc(
	action: Named_Location_Action,
	name, target: string,
	point, mark: u64,
	has_mark, region_active: bool,
	summary: string,
	allocator: runtime.Allocator,
) -> ([]byte, bool) {
	length := NAMED_LOCATION_REQUEST_HEADER_BYTES + len(name) + len(target) + len(summary)
	if length > hosting.MAX_NAMED_LOCATION_COMMAND_BYTES do return nil, false
	request, allocation_error := make([]byte, length, allocator)
	if allocation_error != nil do return nil, false
	values := [?]u64 {
		NAMED_LOCATION_SCHEMA_VERSION, u64(action), u64(len(name)), u64(len(target)), point,
		mark if has_mark else NAMED_LOCATION_ABSENT_MARK,
		1 if region_active else 0, u64(len(summary)),
	}
	offset := 0
	for value in values {
		assert(endian.put_u64(request[offset:], .Little, value))
		offset += 8
	}
	copy(request[offset:], transmute([]u8)name); offset += len(name)
	copy(request[offset:], transmute([]u8)target); offset += len(target)
	copy(request[offset:], transmute([]u8)summary)
	return request, true
}

@(private)
named_location_result_decode :: proc(
	input: []byte,
	action: Named_Location_Action,
	allocator: runtime.Allocator,
) -> (batch: Named_Location_Batch, ok: bool) {
	if len(input) < NAMED_LOCATION_RESULT_HEADER_BYTES do return {}, false
	header: [6]u64
	for &value, index in header {
		value, ok = endian.get_u64(input[index * 8:], .Little)
		if !ok do return {}, false
	}
	if header[0] != NAMED_LOCATION_SCHEMA_VERSION || header[1] != u64(action) ||
	   header[2] > 1 || header[4] > MAX_NAMED_LOCATIONS {
		return {}, false
	}
	record_bytes := header[4] * NAMED_LOCATION_RECORD_BYTES
	required := u64(NAMED_LOCATION_RESULT_HEADER_BYTES) + record_bytes + header[5]
	if required != u64(len(input)) do return {}, false
	state, allocation_error := new(Named_Location_Batch_State, allocator)
	if allocation_error != nil do return {}, false
	state.allocator = allocator
	state.storage, allocation_error = make([]byte, len(input), allocator)
	if allocation_error != nil {free(state, allocator); return {}, false}
	copy(state.storage, input)
	state.locations, allocation_error = make([]Named_Location_Descriptor, int(header[4]), allocator)
	if allocation_error != nil {named_location_batch_state_destroy(state); return {}, false}
	text_offset := NAMED_LOCATION_RESULT_HEADER_BYTES + int(record_bytes)
	text := state.storage[text_offset:]
	if header[2] == 0 {
		diagnostic, text_ok := named_location_text(text, 0, header[5])
		if !text_ok {named_location_batch_state_destroy(state); return {}, false}
		batch = {state = state, diagnostic = diagnostic}
		return batch, true
	}
	for &location, index in state.locations {
		values: [9]u64
		for &value, word_index in values {
			value, ok = endian.get_u64(
				state.storage[NAMED_LOCATION_RESULT_HEADER_BYTES + index * NAMED_LOCATION_RECORD_BYTES + word_index * 8:],
				.Little,
			)
			if !ok {named_location_batch_state_destroy(state); return {}, false}
		}
		location.name, ok = named_location_text(text, values[0], values[1])
		if !ok {named_location_batch_state_destroy(state); return {}, false}
		location.target, ok = named_location_text(text, values[2], values[3])
		if !ok {named_location_batch_state_destroy(state); return {}, false}
		location.point = values[4]
		location.has_mark = values[5] != NAMED_LOCATION_ABSENT_MARK
		location.mark = values[5] if location.has_mark else 0
		if values[6] > 1 || (values[6] == 1 && !location.has_mark) {
			named_location_batch_state_destroy(state); return {}, false
		}
		location.region_active = values[6] == 1
		location.summary, ok = named_location_text(text, values[7], values[8])
		if !ok {named_location_batch_state_destroy(state); return {}, false}
	}
	batch = {state = state, generation = header[3], locations = state.locations}
	return batch, true
}

@(private)
named_location_text :: proc(text: []byte, offset, length: u64) -> (string, bool) {
	if offset > u64(len(text)) || length > u64(len(text)) - offset do return "", false
	return string(text[int(offset):int(offset + length)]), true
}

@(private)
named_location_batch_state_destroy :: proc(state: ^Named_Location_Batch_State) {
	if state == nil do return
	allocator := state.allocator
	if state.locations != nil do delete(state.locations, allocator)
	if state.storage != nil do delete(state.storage, allocator)
	free(state, allocator)
}
