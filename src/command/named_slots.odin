// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../hosting"
import "base:runtime"
import endian "core:encoding/endian"

/* NAMED_SLOT_SCHEMA_VERSION identifies the native hosting wire contract. */
NAMED_SLOT_SCHEMA_VERSION :: u64(1)
/* NAMED_SLOT_REQUEST_HEADER_BYTES is the fixed request prefix length. */
NAMED_SLOT_REQUEST_HEADER_BYTES :: 72
/* NAMED_SLOT_RESULT_HEADER_BYTES is the fixed result prefix length. */
NAMED_SLOT_RESULT_HEADER_BYTES :: 48
/* NAMED_SLOT_RECORD_BYTES is one fixed typed-slot record length. */
NAMED_SLOT_RECORD_BYTES :: 64
/* MAX_NAMED_SLOTS bounds one copied persistent slot result. */
MAX_NAMED_SLOTS :: 256
/* MAX_NAMED_SLOT_TEXT_BYTES bounds copied text and layout values. */
MAX_NAMED_SLOT_TEXT_BYTES :: 64 * 1024

/* Named_Slot_Action selects one persistent typed-slot operation. */
Named_Slot_Action :: enum u64 {
	Invalid,
	Store_Integer,
	Increment_Integer,
	Store_Text,
	Store_Position,
	List,
	Lookup_Text,
	Store_Layout,
	Lookup_Layout,
}

/* Named_Slot_Kind identifies one persistent slot value representation. */
Named_Slot_Kind :: enum u64 {
	Invalid,
	Integer,
	Text,
	Position,
	Location,
	Layout,
}

/* Named_Slot_Descriptor is one copied persistent typed-slot record. */
Named_Slot_Descriptor :: struct {
	name:    string,
	kind:    Named_Slot_Kind,
	integer: i64,
	text:    string,
	target:  string,
	point:   u64,
	summary: string,
}

/* Named_Slot_Batch owns copied slot records until explicit close. */
Named_Slot_Batch :: struct {
	state:         rawptr,
	generation:    u64,
	slots:         []Named_Slot_Descriptor,
	conflict_kind: Named_Slot_Kind,
	diagnostic:    string,
}

@(private)
Named_Slot_Batch_State :: struct {
	storage:   []byte,
	slots:     []Named_Slot_Descriptor,
	allocator: runtime.Allocator,
}

/* named_slots_list returns the bounded persistent typed-slot inventory. */
named_slots_list :: proc(runtime_owner: ^hosting.Runtime, root: string, allocator: runtime.Allocator) -> (Named_Slot_Batch, bool, Failure_Context) {
	return named_slot_command(runtime_owner, root, .List, "", "", "", "", 0, 0, false, allocator)
}

/* named_slot_store_integer atomically stores one persistent signed integer. */
named_slot_store_integer :: proc(runtime_owner: ^hosting.Runtime, root, name: string, value: i64, replace_conflict: bool, allocator: runtime.Allocator) -> (Named_Slot_Batch, bool, Failure_Context) {
	return named_slot_command(runtime_owner, root, .Store_Integer, name, "", "", "", value, 0, replace_conflict, allocator)
}

/* named_slot_increment_integer applies one checked persistent integer delta. */
named_slot_increment_integer :: proc(runtime_owner: ^hosting.Runtime, root, name: string, delta: i64, allocator: runtime.Allocator) -> (Named_Slot_Batch, bool, Failure_Context) {
	return named_slot_command(runtime_owner, root, .Increment_Integer, name, "", "", "", delta, 0, false, allocator)
}

/* named_slot_store_text atomically stores one bounded persistent text value. */
named_slot_store_text :: proc(runtime_owner: ^hosting.Runtime, root, name, text: string, replace_conflict: bool, allocator: runtime.Allocator) -> (Named_Slot_Batch, bool, Failure_Context) {
	return named_slot_command(runtime_owner, root, .Store_Text, name, text, "", "", 0, 0, replace_conflict, allocator)
}

/* named_slot_store_position atomically stores one persistent document position. */
named_slot_store_position :: proc(runtime_owner: ^hosting.Runtime, root, name, target, summary: string, point: u64, replace_conflict: bool, allocator: runtime.Allocator) -> (Named_Slot_Batch, bool, Failure_Context) {
	return named_slot_command(runtime_owner, root, .Store_Position, name, "", target, summary, 0, point, replace_conflict, allocator)
}

/* named_slot_lookup_text returns one copied persistent text value by name. */
named_slot_lookup_text :: proc(runtime_owner: ^hosting.Runtime, root, name: string, allocator: runtime.Allocator) -> (Named_Slot_Batch, bool, Failure_Context) {
	return named_slot_command(runtime_owner, root, .Lookup_Text, name, "", "", "", 0, 0, false, allocator)
}

/* named_slot_store_layout atomically stores one portable layout value. */
named_slot_store_layout :: proc(runtime_owner: ^hosting.Runtime, root, name, value: string, replace_conflict: bool, allocator: runtime.Allocator) -> (Named_Slot_Batch, bool, Failure_Context) {
	return named_slot_command(runtime_owner, root, .Store_Layout, name, value, "", "", 0, 0, replace_conflict, allocator)
}

/* named_slot_lookup_layout returns one copied portable layout value by name. */
named_slot_lookup_layout :: proc(runtime_owner: ^hosting.Runtime, root, name: string, allocator: runtime.Allocator) -> (Named_Slot_Batch, bool, Failure_Context) {
	return named_slot_command(runtime_owner, root, .Lookup_Layout, name, "", "", "", 0, 0, false, allocator)
}

/* named_slot_batch_close releases one copied persistent slot result. */
named_slot_batch_close :: proc(batch: ^Named_Slot_Batch) -> bool {
	if batch == nil || batch.state == nil do return false
	state := (^Named_Slot_Batch_State)(batch.state)
	named_slot_batch_state_destroy(state)
	batch^ = {}
	return true
}

@(private)
named_slot_command :: proc(
	runtime_owner: ^hosting.Runtime,
	root: string,
	action: Named_Slot_Action,
	name, text, target, summary: string,
	signed_scalar: i64,
	point: u64,
	replace_conflict: bool,
	allocator: runtime.Allocator,
) -> (Named_Slot_Batch, bool, Failure_Context) {
	if runtime_owner == nil || len(root) == 0 || action == .Invalid ||
	   action != .List && len(name) == 0 || len(text) > MAX_NAMED_SLOT_TEXT_BYTES {
		return {}, false, Failure_Context{code = .Invalid_Request}
	}
	request, encoded := named_slot_request_encode(
		action, name, text, target, summary, signed_scalar, point, replace_conflict, allocator,
	)
	if !encoded do return {}, false, Failure_Context{code = .Temporary_Memory_Limit}
	defer delete(request, allocator)
	output, output_error := make([]byte, hosting.MAX_NAMED_SLOT_COMMAND_BYTES, allocator)
	if output_error != nil do return {}, false, Failure_Context{code = .Temporary_Memory_Limit}
	defer delete(output, allocator)
	output_length, transferred, transfer_failure := hosting.runtime_named_slot_command(
		runtime_owner, root, request, output,
	)
	if !transferred do return {}, false, hosting_failure_context({}, transfer_failure)
	batch, decoded := named_slot_result_decode(output[:int(output_length)], action, allocator)
	if !decoded do return {}, false, Failure_Context{code = .Wrong_Result}
	if len(batch.diagnostic) > 0 {
		failure := Failure_Context{code = .Wrong_Result}
		if batch.conflict_kind != .Invalid do failure.code = .Invalid_Request
		return batch, false, failure
	}
	return batch, true, {}
}

@(private)
named_slot_request_encode :: proc(
	action: Named_Slot_Action,
	name, text, target, summary: string,
	signed_scalar: i64,
	point: u64,
	replace_conflict: bool,
	allocator: runtime.Allocator,
) -> ([]byte, bool) {
	length := NAMED_SLOT_REQUEST_HEADER_BYTES + len(name) + len(text) + len(target) + len(summary)
	if length > hosting.MAX_NAMED_SLOT_COMMAND_BYTES do return nil, false
	request, allocation_error := make([]byte, length, allocator)
	if allocation_error != nil do return nil, false
	scalar := point
	if action == .Store_Integer || action == .Increment_Integer {
		scalar = cast(u64)signed_scalar
	}
	values := [?]u64 {
		NAMED_SLOT_SCHEMA_VERSION, u64(action), u64(len(name)), u64(len(text)),
		u64(len(target)), u64(len(summary)), scalar, 1 if replace_conflict else 0, 0,
	}
	offset := 0
	for value in values {
		assert(endian.put_u64(request[offset:], .Little, value))
		offset += 8
	}
	copy(request[offset:], transmute([]u8)name)
	offset += len(name)
	copy(request[offset:], transmute([]u8)text)
	offset += len(text)
	copy(request[offset:], transmute([]u8)target)
	offset += len(target)
	copy(request[offset:], transmute([]u8)summary)
	return request, true
}

@(private)
named_slot_result_decode :: proc(input: []byte, action: Named_Slot_Action, allocator: runtime.Allocator) -> (batch: Named_Slot_Batch, ok: bool) {
	if len(input) < NAMED_SLOT_RESULT_HEADER_BYTES do return {}, false
	header: [6]u64
	for &value, index in header {
		value, ok = endian.get_u64(input[index * 8:], .Little)
		if !ok do return {}, false
	}
	if header[0] != NAMED_SLOT_SCHEMA_VERSION || header[1] != u64(action) ||
	   header[2] > 1 || header[4] > MAX_NAMED_SLOTS ||
	   (header[2] == 0 && header[3] > u64(Named_Slot_Kind.Layout)) {
		return {}, false
	}
	record_bytes := header[4] * NAMED_SLOT_RECORD_BYTES
	required := u64(NAMED_SLOT_RESULT_HEADER_BYTES) + record_bytes + header[5]
	if required != u64(len(input)) do return {}, false
	state, allocation_error := new(Named_Slot_Batch_State, allocator)
	if allocation_error != nil do return {}, false
	state.allocator = allocator
	state.storage, allocation_error = make([]byte, len(input), allocator)
	if allocation_error != nil {
		free(state, allocator)
		return {}, false
	}
	copy(state.storage, input)
	state.slots, allocation_error = make([]Named_Slot_Descriptor, int(header[4]), allocator)
	if allocation_error != nil {
		named_slot_batch_state_destroy(state)
		return {}, false
	}
	text_offset := NAMED_SLOT_RESULT_HEADER_BYTES + int(record_bytes)
	text_storage := state.storage[text_offset:]
	if header[2] == 0 {
		diagnostic, text_ok := named_slot_text(text_storage, 0, header[5])
		if !text_ok {
			named_slot_batch_state_destroy(state)
			return {}, false
		}
		batch = {state = state, conflict_kind = Named_Slot_Kind(header[3]), diagnostic = diagnostic}
		return batch, true
	}
	for &slot, index in state.slots {
		values: [8]u64
		for &value, word_index in values {
			value, ok = endian.get_u64(
				state.storage[NAMED_SLOT_RESULT_HEADER_BYTES + index * NAMED_SLOT_RECORD_BYTES + word_index * 8:],
				.Little,
			)
				if !ok {
					named_slot_batch_state_destroy(state)
					return {}, false
				}
		}
		slot.name, ok = named_slot_text(text_storage, values[0], values[1])
			if !ok || values[2] < u64(Named_Slot_Kind.Integer) || values[2] > u64(Named_Slot_Kind.Layout) ||
			   values[2] == u64(Named_Slot_Kind.Location) {
			named_slot_batch_state_destroy(state)
			return {}, false
		}
		slot.kind = Named_Slot_Kind(values[2])
		#partial switch slot.kind {
		case .Integer:
			slot.integer = cast(i64)values[3]
			case .Text, .Layout:
			slot.text, ok = named_slot_text(text_storage, values[4], values[5])
		case .Position:
			slot.point = values[3]
			slot.target, ok = named_slot_text(text_storage, values[4], values[5])
			if ok do slot.summary, ok = named_slot_text(text_storage, values[6], values[7])
		case: unreachable()
		}
		if !ok {
			named_slot_batch_state_destroy(state)
			return {}, false
		}
	}
	batch = {state = state, generation = header[3], slots = state.slots}
	return batch, true
}

@(private)
named_slot_text :: proc(text: []byte, offset, length: u64) -> (string, bool) {
	if offset > u64(len(text)) || length > u64(len(text)) - offset do return "", false
	return string(text[int(offset):int(offset + length)]), true
}

@(private)
named_slot_batch_state_destroy :: proc(state: ^Named_Slot_Batch_State) {
	if state == nil do return
	allocator := state.allocator
	if state.slots != nil do delete(state.slots, allocator)
	if state.storage != nil do delete(state.storage, allocator)
	free(state, allocator)
}
