// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package transaction

import "../editor"
import "base:runtime"

@(private)
NORMALIZATION_CHUNK_BYTES :: u64(64 * KIBIBYTE)

@(private)
normalize_base_batch_prepare :: proc(
	state: ^Transaction_State,
	batch: []Base_Splice,
) -> (
	normalized: []Normalized_Splice,
	text_bytes: u64,
	metadata_bytes: u64,
	ok: bool,
	failure: Failure_Context,
) {
	metadata_array_bytes, metadata_ok := checked_mul_u64(
		u64(len(batch)),
		u64(size_of(Normalized_Splice)),
	)
	metadata_total_ok: bool
	metadata_bytes, metadata_total_ok = checked_add_u64(state.metadata_bytes, metadata_array_bytes)
	if !metadata_ok || !metadata_total_ok || metadata_bytes > state.limits.metadata_bytes {
		actual := metadata_bytes
		if !metadata_ok || !metadata_total_ok {
			actual = max(u64)
		}
		failure = transaction_failure(state, .Metadata_Memory_Limit)
		failure.limit = state.limits.metadata_bytes
		failure.actual = actual
		return nil, 0, 0, false, failure
	}
	if len(batch) == 0 {
		return nil, 0, metadata_bytes, true, {}
	}
	allocation_error: runtime.Allocator_Error
	normalized, allocation_error = make([]Normalized_Splice, len(batch), state.allocator)
	if allocation_error != nil {
		return nil, 0, 0, false, transaction_failure(state, .Persistent_Memory_Limit)
	}
	for splice, index in batch {
		removed_bytes := u64(splice.end.byte_offset) - u64(splice.start.byte_offset)
		operation_bytes, operation_ok := checked_add_u64(removed_bytes, u64(len(splice.replacement)))
		text_total, text_ok := checked_add_u64(text_bytes, operation_bytes)
		if !operation_ok || !text_ok || text_total > state.limits.text_bytes {
			normalized_splices_release(normalized, state.allocator)
			actual := text_total
			if !operation_ok || !text_ok {
				actual = max(u64)
			}
			failure = transaction_failure(state, .Text_Limit)
			failure.splice_index = u64(index)
			failure.limit = state.limits.text_bytes
			failure.actual = actual
			return nil, 0, 0, false, failure
		}
		replacement, replacement_error := clone_string(splice.replacement, state.allocator)
		if replacement_error != nil {
			normalized_splices_release(normalized, state.allocator)
			return nil, 0, 0, false, transaction_failure(state, .Persistent_Memory_Limit)
		}
		removed, removed_ok, removed_failure := inspect_confirmed_owned(
			state,
			splice.start.byte_offset,
			splice.end.byte_offset,
		)
		if !removed_ok {
			delete_string(replacement, state.allocator)
			normalized_splices_release(normalized, state.allocator)
			return nil, 0, 0, false, removed_failure
		}
		normalized[index] = Normalized_Splice {
			start = splice.start.byte_offset,
			end = splice.end.byte_offset,
			replacement_text = replacement,
			removed_text = removed,
		}
		text_bytes = text_total
	}
	return normalized, text_bytes, metadata_bytes, true, {}
}

@(private)
normalize_sequential_transition :: proc(
	state: ^Transaction_State,
) -> (
	normalized: []Normalized_Splice,
	text_bytes: u64,
	metadata_bytes: u64,
	ok: bool,
	failure: Failure_Context,
) {
	confirmed_stats, confirmed_ok, confirmed_failure := editor.buffer_stats(state.buffer)
	if !confirmed_ok {
		return nil, 0, 0, false, transaction_editor_failure(
			state.transaction_id,
			state.admitted_splices,
			confirmed_failure,
		)
	}
	if confirmed_stats.revision != state.base_revision {
		return nil, 0, 0, false, transaction_failure(state, .Stale_Revision)
	}
	working_stats, working_ok, working_failure := editor.working_revision_stats(&state.working)
	if !working_ok {
		return nil, 0, 0, false, transaction_editor_failure(
			state.transaction_id,
			state.admitted_splices,
			working_failure,
		)
	}
	prefix, prefix_ok := common_prefix_roots(
		state,
		confirmed_stats.text_bytes,
		working_stats.text_bytes,
	)
	if !prefix_ok {
		return nil, 0, 0, false, transaction_failure(state, .Work_Limit)
	}
	suffix, suffix_ok := common_suffix_roots(
		state,
		confirmed_stats.text_bytes,
		working_stats.text_bytes,
		prefix,
	)
	if !suffix_ok {
		return nil, 0, 0, false, transaction_failure(state, .Work_Limit)
	}
	base_end := confirmed_stats.text_bytes - suffix
	working_end := working_stats.text_bytes - suffix
	replacement, replacement_ok, replacement_failure := inspect_working_range_owned(
		state,
		editor.Byte_Offset(prefix),
		editor.Byte_Offset(working_end),
	)
	if !replacement_ok {
		return nil, 0, 0, false, replacement_failure
	}
	removed, removed_ok, removed_failure := inspect_confirmed_owned(
		state,
		editor.Byte_Offset(prefix),
		editor.Byte_Offset(base_end),
	)
	if !removed_ok {
		delete_string(replacement, state.allocator)
		return nil, 0, 0, false, removed_failure
	}

	operation_bytes, operation_ok := checked_add_u64(u64(len(replacement)), u64(len(removed)))
	if !operation_ok || operation_bytes > state.limits.text_bytes {
		delete_string(removed, state.allocator)
		delete_string(replacement, state.allocator)
		failure = transaction_failure(state, .Text_Limit)
		failure.limit = state.limits.text_bytes
		failure.actual = operation_bytes
		return nil, 0, 0, false, failure
	}
	metadata_ok: bool
	metadata_bytes, metadata_ok = checked_add_u64(
		state.metadata_bytes,
		u64(size_of(Normalized_Splice)),
	)
	if !metadata_ok || metadata_bytes > state.limits.metadata_bytes {
		delete_string(removed, state.allocator)
		delete_string(replacement, state.allocator)
		failure = transaction_failure(state, .Metadata_Memory_Limit)
		failure.limit = state.limits.metadata_bytes
		failure.actual = metadata_bytes
		return nil, 0, 0, false, failure
	}
	allocation_error: runtime.Allocator_Error
	normalized, allocation_error = make([]Normalized_Splice, 1, state.allocator)
	if allocation_error != nil {
		delete_string(removed, state.allocator)
		delete_string(replacement, state.allocator)
		return nil, 0, 0, false, transaction_failure(state, .Persistent_Memory_Limit)
	}
	normalized[0] = Normalized_Splice {
		start = editor.Byte_Offset(prefix),
		end = editor.Byte_Offset(base_end),
		replacement_text = replacement,
		removed_text = removed,
	}
	return normalized, operation_bytes, metadata_bytes, true, {}
}

@(private)
normalized_reconstructs_working :: proc(state: ^Transaction_State) -> bool {
	confirmed_stats, confirmed_ok, _ := editor.buffer_stats(state.buffer)
	working_stats, working_ok, _ := editor.working_revision_stats(&state.working)
	if !confirmed_ok || !working_ok || confirmed_stats.revision != state.base_revision {
		return false
	}
	result_bytes := confirmed_stats.text_bytes
	for splice in state.normalized {
		removed_bytes := u64(splice.end) - u64(splice.start)
		if removed_bytes > result_bytes {
			return false
		}
		result_bytes = result_bytes - removed_bytes + u64(len(splice.replacement_text))
	}
	if result_bytes != working_stats.text_bytes {
		return false
	}
	base_cursor := u64(0)
	result_cursor := u64(0)
	for splice in state.normalized {
		start := u64(splice.start)
		end := u64(splice.end)
		if start < base_cursor || end < start || end > confirmed_stats.text_bytes {
			return false
		}
		if !confirmed_range_equals_string(state, start, end, splice.removed_text) ||
		   !confirmed_range_equals_working(state, base_cursor, start, result_cursor) {
			return false
		}
		result_cursor += start - base_cursor
		if !string_equals_working(state, splice.replacement_text, result_cursor) {
			return false
		}
		result_cursor += u64(len(splice.replacement_text))
		base_cursor = end
	}
	return confirmed_range_equals_working(
		state,
		base_cursor,
		confirmed_stats.text_bytes,
		result_cursor,
	)
}

@(private)
inspect_confirmed_owned :: proc(
	state: ^Transaction_State,
	start, end: editor.Byte_Offset,
) -> (owned: string, ok: bool, failure: Failure_Context) {
	length := u64(end) - u64(start)
	if length == 0 {
		return "", true, {}
	}
	if length > u64(max(int)) || length > state.limits.temporary_bytes {
		failure = transaction_failure(state, .Temporary_Memory_Limit)
		failure.limit = state.limits.temporary_bytes
		failure.actual = length
		return "", false, failure
	}
	bytes, allocation_error := make([]byte, int(length), state.allocator)
	if allocation_error != nil {
		return "", false, transaction_failure(state, .Persistent_Memory_Limit)
	}
	offset := u64(start)
	for offset < u64(end) {
		take := min(NORMALIZATION_CHUNK_BYTES, u64(end) - offset)
		_, inspected, editor_failure := editor.buffer_inspect(
			state.buffer,
			editor.Byte_Offset(offset),
			editor.Byte_Offset(offset + take),
			bytes[int(offset - u64(start)):int(offset - u64(start) + take)],
		)
		if !inspected {
			delete(bytes, state.allocator)
			return "", false, transaction_editor_failure(
				state.transaction_id,
				state.admitted_splices,
				editor_failure,
			)
		}
		offset += take
	}
	return string(bytes), true, {}
}

@(private)
inspect_working_range_owned :: proc(
	state: ^Transaction_State,
	start_offset, end_offset: editor.Byte_Offset,
) -> (owned: string, ok: bool, failure: Failure_Context) {
	text_bytes := u64(end_offset) - u64(start_offset)
	if text_bytes == 0 {
		return "", true, {}
	}
	if text_bytes > u64(max(int)) || text_bytes > state.limits.temporary_bytes {
		failure = transaction_failure(state, .Temporary_Memory_Limit)
		failure.limit = state.limits.temporary_bytes
		failure.actual = text_bytes
		return "", false, failure
	}
	bytes, allocation_error := make([]byte, int(text_bytes), state.allocator)
	if allocation_error != nil {
		return "", false, transaction_failure(state, .Persistent_Memory_Limit)
	}
	offset := u64(start_offset)
	for offset < u64(end_offset) {
		take := working_chunk_length(state, offset, u64(end_offset), NORMALIZATION_CHUNK_BYTES)
		if take == 0 {
			delete(bytes, state.allocator)
			return "", false, transaction_failure(state, .Work_Limit)
		}
		start, start_ok, start_failure := editor.working_revision_position(
			&state.working,
			editor.Byte_Offset(offset),
		)
		end, end_ok, end_failure := editor.working_revision_position(
			&state.working,
			editor.Byte_Offset(offset + take),
		)
		if !start_ok || !end_ok {
			delete(bytes, state.allocator)
			selected_failure := start_failure
			if start_ok {
				selected_failure = end_failure
			}
			return "", false, transaction_editor_failure(
				state.transaction_id,
				state.admitted_splices,
				selected_failure,
			)
		}
		_, inspected, editor_failure := editor.working_revision_inspect(
			&state.working,
			start,
			end,
			bytes[int(offset - u64(start_offset)):int(offset - u64(start_offset) + take)],
		)
		if !inspected {
			delete(bytes, state.allocator)
			return "", false, transaction_editor_failure(
				state.transaction_id,
				state.admitted_splices,
				editor_failure,
			)
		}
		offset += take
	}
	return string(bytes), true, {}
}

@(private)
common_prefix_roots :: proc(state: ^Transaction_State, confirmed_bytes, working_bytes: u64) -> (u64, bool) {
	limit := min(confirmed_bytes, working_bytes)
	offset := u64(0)
	confirmed_chunk: [NORMALIZATION_CHUNK_BYTES]byte
	working_chunk: [NORMALIZATION_CHUNK_BYTES]byte
	for offset < limit {
		take := min(NORMALIZATION_CHUNK_BYTES, limit - offset)
		take = working_chunk_length(state, offset, limit, take)
		if take == 0 {
			return offset, true
		}
		if !inspect_confirmed_chunk(state, offset, take, confirmed_chunk[:int(take)]) ||
		   !inspect_working_chunk(state, offset, take, working_chunk[:int(take)]) {
			return 0, false
		}
		for index in 0 ..< int(take) {
			if confirmed_chunk[index] != working_chunk[index] {
				return confirmed_boundary_at_or_before(state, offset + u64(index)), true
			}
		}
		offset += take
	}
	return limit, true
}

@(private)
common_suffix_roots :: proc(
	state: ^Transaction_State,
	confirmed_bytes, working_bytes, prefix: u64,
) -> (u64, bool) {
	limit := min(confirmed_bytes - prefix, working_bytes - prefix)
	count := u64(0)
	confirmed_chunk: [NORMALIZATION_CHUNK_BYTES]byte
	working_chunk: [NORMALIZATION_CHUNK_BYTES]byte
	for count < limit {
		take := min(NORMALIZATION_CHUNK_BYTES, limit - count)
		for take > 0 {
			confirmed_start := confirmed_bytes - count - take
			working_start := working_bytes - count - take
			if confirmed_position_is_valid(state, confirmed_start) && working_position_is_valid(state, working_start) {
				break
			}
			take -= 1
		}
		if take == 0 {
			return count, true
		}
		confirmed_start := confirmed_bytes - count - take
		working_start := working_bytes - count - take
		if !inspect_confirmed_chunk(state, confirmed_start, take, confirmed_chunk[:int(take)]) ||
		   !inspect_working_chunk(state, working_start, take, working_chunk[:int(take)]) {
			return 0, false
		}
		for reverse_index in 0 ..< int(take) {
			index := int(take) - 1 - reverse_index
			if confirmed_chunk[index] != working_chunk[index] {
				return suffix_boundary_at_or_before(
					state,
					confirmed_bytes,
					working_bytes,
					count + u64(reverse_index),
				), true
			}
		}
		count += take
	}
	return count, true
}

@(private)
confirmed_range_equals_string :: proc(
	state: ^Transaction_State,
	start, end: u64,
	expected: string,
) -> bool {
	if end < start || end - start != u64(len(expected)) {
		return false
	}
	offset := u64(0)
	observed: [NORMALIZATION_CHUNK_BYTES]byte
	for offset < end - start {
		take := min(NORMALIZATION_CHUNK_BYTES, end - start - offset)
		if !inspect_confirmed_chunk(state, start + offset, take, observed[:int(take)]) ||
		   string(observed[:int(take)]) != expected[int(offset):int(offset + take)] {
			return false
		}
		offset += take
	}
	return true
}

@(private)
confirmed_range_equals_working :: proc(
	state: ^Transaction_State,
	confirmed_start, confirmed_end, working_start: u64,
) -> bool {
	if confirmed_end < confirmed_start {
		return false
	}
	length := confirmed_end - confirmed_start
	offset := u64(0)
	confirmed_chunk: [NORMALIZATION_CHUNK_BYTES]byte
	working_chunk: [NORMALIZATION_CHUNK_BYTES]byte
	for offset < length {
		take := min(NORMALIZATION_CHUNK_BYTES, length - offset)
		take = working_chunk_length(state, working_start + offset, working_start + length, take)
		if take == 0 ||
		   !inspect_confirmed_chunk(state, confirmed_start + offset, take, confirmed_chunk[:int(take)]) ||
		   !inspect_working_chunk(state, working_start + offset, take, working_chunk[:int(take)]) ||
		   !normalization_bytes_equal(confirmed_chunk[:int(take)], working_chunk[:int(take)]) {
			return false
		}
		offset += take
	}
	return true
}

@(private)
string_equals_working :: proc(state: ^Transaction_State, expected: string, working_start: u64) -> bool {
	length := u64(len(expected))
	offset := u64(0)
	observed: [NORMALIZATION_CHUNK_BYTES]byte
	for offset < length {
		take := min(NORMALIZATION_CHUNK_BYTES, length - offset)
		take = working_chunk_length(state, working_start + offset, working_start + length, take)
		if take == 0 || !inspect_working_chunk(
			state,
			working_start + offset,
			take,
			observed[:int(take)],
		) || string(observed[:int(take)]) != expected[int(offset):int(offset + take)] {
			return false
		}
		offset += take
	}
	return true
}

@(private)
inspect_confirmed_chunk :: proc(
	state: ^Transaction_State,
	start, length: u64,
	destination: []byte,
) -> bool {
	if length != u64(len(destination)) {
		return false
	}
	_, inspected, _ := editor.buffer_inspect(
		state.buffer,
		editor.Byte_Offset(start),
		editor.Byte_Offset(start + length),
		destination,
	)
	return inspected
}

@(private)
inspect_working_chunk :: proc(
	state: ^Transaction_State,
	start, length: u64,
	destination: []byte,
) -> bool {
	if length != u64(len(destination)) {
		return false
	}
	start_position, start_ok, _ := editor.working_revision_position(
		&state.working,
		editor.Byte_Offset(start),
	)
	end_position, end_ok, _ := editor.working_revision_position(
		&state.working,
		editor.Byte_Offset(start + length),
	)
	if !start_ok || !end_ok {
		return false
	}
	_, inspected, _ := editor.working_revision_inspect(
		&state.working,
		start_position,
		end_position,
		destination,
	)
	return inspected
}

@(private)
confirmed_position_is_valid :: proc(state: ^Transaction_State, offset: u64) -> bool {
	_, ok, _ := editor.buffer_position(state.buffer, editor.Byte_Offset(offset))
	return ok
}

@(private)
working_position_is_valid :: proc(state: ^Transaction_State, offset: u64) -> bool {
	_, ok, _ := editor.working_revision_position(&state.working, editor.Byte_Offset(offset))
	return ok
}

@(private)
working_chunk_length :: proc(state: ^Transaction_State, start, end, requested: u64) -> u64 {
	if start > end {
		return 0
	}
	take := min(requested, end - start)
	for take > 0 && !working_position_is_valid(state, start + take) {
		take -= 1
	}
	return take
}

@(private)
confirmed_boundary_at_or_before :: proc(state: ^Transaction_State, candidate: u64) -> u64 {
	boundary := candidate
	for boundary > 0 &&
	    (!confirmed_position_is_valid(state, boundary) || !working_position_is_valid(state, boundary)) {
		boundary -= 1
	}
	return boundary
}

@(private)
suffix_boundary_at_or_before :: proc(
	state: ^Transaction_State,
	confirmed_bytes, working_bytes, candidate: u64,
) -> u64 {
	boundary := candidate
	for boundary > 0 {
		confirmed_start := confirmed_bytes - boundary
		working_start := working_bytes - boundary
		if confirmed_position_is_valid(state, confirmed_start) &&
		   working_position_is_valid(state, working_start) {
			break
		}
		boundary -= 1
	}
	return boundary
}

@(private)
normalization_bytes_equal :: proc(left, right: []byte) -> bool {
	if len(left) != len(right) {
		return false
	}
	for value, index in left {
		if value != right[index] {
			return false
		}
	}
	return true
}
