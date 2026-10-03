// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package transaction

import "../editor"
import "base:runtime"

@(private)
limits_are_valid :: proc(limits: Limits) -> bool {
	return limits.buffer_participants > 0 &&
	       limits.buffer_participants <= MAX_BUFFER_PARTICIPANTS &&
	       limits.splices > 0 &&
	       limits.text_bytes > 0 &&
	       limits.temporary_bytes > 0 &&
	       limits.metadata_bytes >= u64(size_of(Transaction_State)) &&
	       limits.origin_bytes > 0 &&
	       limits.command_bytes > 0 &&
	       limits.nested_command_depth > 0 &&
	       limits.nested_command_depth <= MAX_NESTED_COMMAND_DEPTH &&
	       limits.active_savepoints > 0 &&
	       limits.active_savepoints <= MAX_ACTIVE_SAVEPOINTS &&
	       limits.logical_views > 0 &&
	       limits.logical_views <= MAX_LOGICAL_VIEW_PARTICIPANTS &&
	       limits.checkpoint_operations > 0
}

@(private)
clone_string :: proc(
	contents: string,
	allocator: runtime.Allocator,
) -> (owned: string, error: runtime.Allocator_Error) {
	if len(contents) == 0 {
		return "", nil
	}
	bytes, allocation_error := make([]byte, len(contents), allocator)
	if allocation_error != nil {
		return "", allocation_error
	}
	copy(bytes, contents)
	return string(bytes), nil
}

@(private)
delete_string :: proc(contents: string, allocator: runtime.Allocator) {
	if len(contents) > 0 {
		delete(contents, allocator)
	}
}

@(private)
normalized_splices_release :: proc(splices: []Normalized_Splice, allocator: runtime.Allocator) {
	for splice in splices {
		delete_string(splice.replacement_text, allocator)
		delete_string(splice.removed_text, allocator)
	}
	if splices != nil {
		delete(splices, allocator)
	}
}

@(private)
transaction_state_release :: proc(state: ^Transaction_State) {
	allocator := state.allocator
	if state.active_savepoints != 0 {
		transaction_nested_frames_release(state)
	}
	transaction_logical_view_abort(state)
	normalized_splices_release(state.normalized, allocator)
	if state.publication_splices != nil {
		delete(state.publication_splices, allocator)
	}
	delete_string(state.command, allocator)
	delete_string(state.origin_descriptor, allocator)
	state.lifecycle = .Closed
	free(state, allocator)
}

@(private)
transaction_editor_failure :: proc(
	transaction_id: Transaction_ID,
	splice_index: u64,
	editor_failure: editor.Failure_Context,
) -> Failure_Context {
	code := Failure_Code.Work_Limit
	switch editor_failure.code {
	case .None:
		code = .None
	case .Closed_Buffer:
		code = .Invalid_State
	case .Wrong_Buffer_Kind, .Read_Only_Buffer:
		code = .Invalid_State
	case .Wrong_Buffer:
		code = .Wrong_Buffer
	case .Stale_Revision:
		code = .Stale_Revision
	case .Mismatched_Revision:
		code = .Mismatched_Revision
	case .Reversed_Range:
		code = .Reversed_Range
	case .Out_Of_Range:
		code = .Out_Of_Range
	case .Mid_Encoding_Offset:
		code = .Mid_Encoding_Offset
	case .Malformed_UTF8:
		code = .Malformed_UTF8
	case .Buffer_Limit, .Replacement_Limit, .Undo_Memory_Limit:
		code = .Text_Limit
	case .Persistent_Memory_Limit:
		code = .Persistent_Memory_Limit
	case .Temporary_Memory_Limit:
		code = .Temporary_Memory_Limit
	case .Inspection_Limit, .Anchor_Limit, .Invalid_Anchor, .Missing_Mark,
	     .Selection_Generation_Limit, .Work_Limit:
		code = .Work_Limit
	case .Cancelled:
		code = .Cancelled
	}
	return Failure_Context {
		code = code,
		transaction_id = transaction_id,
		buffer_id = editor_failure.buffer_id,
		base_revision = editor_failure.revision,
		splice_index = splice_index,
		limit = editor_failure.limit,
		actual = editor_failure.actual,
		editor_failure = editor_failure,
	}
}

@(private)
checked_add_u64 :: proc(left, right: u64) -> (u64, bool) {
	if right > max(u64) - left {
		return 0, false
	}
	return left + right, true
}

@(private)
checked_mul_u64 :: proc(left, right: u64) -> (u64, bool) {
	if left != 0 && right > max(u64) / left {
		return 0, false
	}
	return left * right, true
}
