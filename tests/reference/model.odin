// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package reference

import "../../src/editor"
import "base:runtime"
import "core:unicode/utf8"

Model :: struct {
	buffer_id: editor.Buffer_ID,
	revision:  editor.Revision,
	bytes:     []u8,
	allocator: runtime.Allocator,
}

model_init :: proc(
	initial_text: string,
	buffer_id := editor.Buffer_ID(1),
	limits := editor.DEFAULT_LIMITS,
	allocator := context.allocator,
) -> (model: Model, failure: editor.Failure_Context, ok: bool) {
	if buffer_id == editor.Buffer_ID(0) {
		return {}, failure_make(.Wrong_Buffer, buffer_id), false
	}
	if !utf8.valid_string(initial_text) {
		return {}, failure_make(.Malformed_UTF8, buffer_id), false
	}
	if u64(len(initial_text)) > limits.buffer_bytes {
		return {}, failure_make(
			.Buffer_Limit,
			buffer_id,
			limit = limits.buffer_bytes,
			actual = u64(len(initial_text)),
		), false
	}

	bytes := make([]u8, len(initial_text), allocator)
	copy(bytes, initial_text)
	return Model {
		buffer_id = buffer_id,
		revision = editor.Revision(0),
		bytes = bytes,
		allocator = allocator,
	}, {}, true
}

model_deinit :: proc(model: ^Model) {
	if model.bytes != nil {
		delete(model.bytes, model.allocator)
	}
	model^ = {}
}

model_text :: proc(model: ^Model) -> string {
	return transmute(string)model.bytes
}

model_position :: proc(model: ^Model, byte_offset: u64) -> (editor.Position, bool) {
	return editor.position_make(
		model.buffer_id,
		model.revision,
		editor.Byte_Offset(byte_offset),
	)
}

model_splice :: proc(
	model: ^Model,
	splice: editor.Splice,
	limits := editor.DEFAULT_LIMITS,
) -> (failure: editor.Failure_Context, ok: bool) {
	if splice.start.buffer_id != model.buffer_id || splice.end.buffer_id != model.buffer_id {
		return failure_for_splice(.Wrong_Buffer, model, splice), false
	}
	if splice.start.revision != splice.end.revision {
		return failure_for_splice(.Mismatched_Revision, model, splice), false
	}
	if splice.start.revision != model.revision {
		return failure_for_splice(.Stale_Revision, model, splice), false
	}

	start := u64(splice.start.byte_offset)
	end := u64(splice.end.byte_offset)
	if start > end {
		return failure_for_splice(.Reversed_Range, model, splice), false
	}
	if end > u64(len(model.bytes)) {
		return failure_for_splice(.Out_Of_Range, model, splice), false
	}
	if !model_boundary_is_valid(model, start) || !model_boundary_is_valid(model, end) {
		return failure_for_splice(.Mid_Encoding_Offset, model, splice), false
	}
	if !utf8.valid_string(splice.replacement) {
		return failure_for_splice(.Malformed_UTF8, model, splice), false
	}
	if u64(len(splice.replacement)) > limits.replacement_bytes {
		return failure_for_splice(
			.Replacement_Limit,
			model,
			splice,
			limits.replacement_bytes,
			u64(len(splice.replacement)),
		), false
	}

	removed_bytes := end - start
	retained_bytes := u64(len(model.bytes)) - removed_bytes
	if u64(len(splice.replacement)) > limits.buffer_bytes - retained_bytes {
		return failure_for_splice(
			.Buffer_Limit,
			model,
			splice,
			limits.buffer_bytes,
			retained_bytes + u64(len(splice.replacement)),
		), false
	}

	result_length := int(retained_bytes + u64(len(splice.replacement)))
	result := make([]u8, result_length, model.allocator)
	start_index := int(start)
	end_index := int(end)
	inserted_end := start_index + len(splice.replacement)
	copy(result[:start_index], model.bytes[:start_index])
	copy(result[start_index:inserted_end], splice.replacement)
	copy(result[inserted_end:], model.bytes[end_index:])

	delete(model.bytes, model.allocator)
	model.bytes = result
	model.revision += 1
	return {}, true
}

@(private)
model_boundary_is_valid :: proc(model: ^Model, byte_offset: u64) -> bool {
	if byte_offset == u64(len(model.bytes)) {
		return true
	}
	return utf8.rune_start(model.bytes[int(byte_offset)])
}

@(private)
failure_make :: proc(
	code: editor.Failure_Code,
	buffer_id: editor.Buffer_ID,
	revision := editor.Revision(0),
	start := editor.Byte_Offset(0),
	end := editor.Byte_Offset(0),
	limit := u64(0),
	actual := u64(0),
) -> editor.Failure_Context {
	return editor.Failure_Context {
		code = code,
		buffer_id = buffer_id,
		revision = revision,
		start = start,
		end = end,
		limit = limit,
		actual = actual,
	}
}

@(private)
failure_for_splice :: proc(
	code: editor.Failure_Code,
	model: ^Model,
	splice: editor.Splice,
	limit := u64(0),
	actual := u64(0),
) -> editor.Failure_Context {
	return failure_make(
		code,
		model.buffer_id,
		model.revision,
		splice.start.byte_offset,
		splice.end.byte_offset,
		limit,
		actual,
	)
}
