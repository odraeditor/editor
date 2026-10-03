// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language

import "../editor"
import "../transaction"
import "base:runtime"

@(private)
ODIN_HIGHLIGHT_QUERY :: #load(
	"../../third_party/tree-sitter-odin/1.3.0/queries/highlights.scm",
)

/* Odin_Capture_Mapping classifies one known Odin query capture. */
Odin_Capture_Mapping :: struct {
	role:       Syntax_Role,
	precedence: u16,
	ignored:    bool,
}

@(private)
Tree_Sitter_Input_Context :: struct {
	snapshot:   ^editor.Buffer_Snapshot,
	text_bytes: u64,
	scratch:    [CANCELLATION_CHECK_BYTES]u8,
	failed:     bool,
}

/* tree_sitter_owner_compile_odin_query compiles the pinned factory query. */
tree_sitter_owner_compile_odin_query :: proc(
	owner: ^Tree_Sitter_Owner,
	generation: Query_Generation,
) -> (ok: bool, failure: Failure) {
	query := transmute([]u8)(string(ODIN_HIGHLIGHT_QUERY))
	return tree_sitter_owner_compile_query(owner, query, generation)
}

/* tree_sitter_owner_parse_snapshot parses one retained exact buffer revision. */
tree_sitter_owner_parse_snapshot :: proc(
	owner: ^Tree_Sitter_Owner,
	snapshot: ^editor.Buffer_Snapshot,
	language: Language_Identity,
	provider: Provider_Handle,
	selection_generation: Selection_Generation,
	tree_generation: Tree_Generation,
	work_limit_bytes := INITIAL_WORK_BYTES,
) -> (result: Parse_Snapshot, ok: bool, failure: Failure) {
	state := tree_sitter_owner_state(owner)
	if state == nil {
		return {}, false, tree_sitter_failure(.Publish_Parse, .Parser_Initialization)
	}
	if language.id == Language_ID(0) || language.generation == Language_Generation(0) {
		return {}, false, tree_sitter_failure(.Publish_Parse, .Invalid_Language)
	}
	if provider.provider_id == Provider_ID(0) ||
	   provider.provider_generation == Provider_Generation(0) {
		return {}, false, tree_sitter_failure(.Publish_Parse, .Invalid_Provider)
	}
	if selection_generation == Selection_Generation(0) ||
	   tree_generation == Tree_Generation(0) ||
	   state.query == nil || state.query_generation == Query_Generation(0) {
		return {}, false, tree_sitter_failure(.Publish_Parse, .Generation_Limit)
	}

	snapshot_stats, snapshot_ok, _ := editor.buffer_snapshot_stats(snapshot)
	if !snapshot_ok {
		return {}, false, tree_sitter_failure(.Publish_Parse, .Unavailable_Base_Snapshot)
	}
	if snapshot_stats.text_bytes > MAX_ANALYZED_SOURCE_BYTES ||
	   snapshot_stats.text_bytes > u64(max(u32)) {
		failure = tree_sitter_failure(.Publish_Parse, .Source_Limit)
		failure.limit = MAX_ANALYZED_SOURCE_BYTES
		failure.actual = snapshot_stats.text_bytes
		return {}, false, failure
	}

	options, progress_ok, progress_failure := tree_sitter_owner_prepare_progress(
		owner,
		work_limit_bytes,
	)
	if !progress_ok {
		progress_failure.operation = .Publish_Parse
		return {}, false, progress_failure
	}
	input_context := Tree_Sitter_Input_Context {
		snapshot = snapshot,
		text_bytes = snapshot_stats.text_bytes,
	}
	input := Tree_Sitter_Input {
		payload = &input_context,
		read = tree_sitter_snapshot_read,
		encoding = .UTF8,
	}
	state.lifecycle = .Parsing
	state.pending = Pending_Work {
		kind = .Initial,
		selection_generation = selection_generation,
		source_revision = snapshot_stats.revision,
		work_bytes = work_limit_bytes,
	}
	tree_sitter_memory_begin(state)
	candidate := ts_parser_parse_with_options(state.parser, nil, input, options)
	tree_sitter_memory_end()
	state.lifecycle = .Ready
	if input_context.failed {
		if candidate != nil do ts_tree_delete(candidate)
		ts_parser_reset(state.parser)
		return {}, false, tree_sitter_failure(.Publish_Parse, .Unavailable_Base_Snapshot)
	}
	if candidate == nil {
		failure_code := Failure_Code.Work_Limit
		if state.progress.cancel_requested do failure_code = .Cancelled
		ts_parser_reset(state.parser)
		state.pending.refresh_requested = true
		return {}, false, tree_sitter_failure(.Publish_Parse, failure_code)
	}
	if !tree_sitter_owner_replace_tree(owner, candidate, tree_generation) {
		return {}, false, tree_sitter_failure(.Publish_Parse, .Generation_Limit)
	}

	work_bytes := u64(state.progress.current_byte_offset)
	if work_bytes == 0 do work_bytes = snapshot_stats.text_bytes
	usage := Resource_Usage {
		retained_source_bytes = snapshot_stats.text_bytes,
		retained_tree_bytes = odra_tree_sitter_memory_owner_live_bytes(state.memory_owner),
		retained_query_bytes = state.query_bytes,
		captures = state.query_captures,
		work_bytes = work_bytes,
	}
	result = Parse_Snapshot {
		buffer_id = snapshot_stats.buffer_id,
		source_revision = snapshot_stats.revision,
		language = language,
		provider = provider,
		selection_generation = selection_generation,
		parser_generation = state.parser_generation,
		tree_generation = state.tree_generation,
		query_generation = state.query_generation,
		status = .Current,
		usage = usage,
	}
	state.confirmed = result
	state.pending = {}
	return result, true, {}
}

/* tree_sitter_owner_parse_incremental applies one exact normalized commit. */
tree_sitter_owner_parse_incremental :: proc(
	owner: ^Tree_Sitter_Owner,
	base_snapshot, result_snapshot: ^editor.Buffer_Snapshot,
	event: transaction.Commit_Event,
	tree_generation: Tree_Generation,
	work_limit_bytes := INCREMENTAL_WORK_BYTES,
) -> (result: Parse_Snapshot, ok: bool, failure: Failure) {
	state := tree_sitter_owner_state(owner)
	if state == nil || state.tree == nil || state.confirmed.status != .Current {
		return {}, false, tree_sitter_failure(.Publish_Parse, .Parser_Initialization)
	}
	base_stats, base_ok, _ := editor.buffer_snapshot_stats(base_snapshot)
	result_stats, result_ok, _ := editor.buffer_snapshot_stats(result_snapshot)
	if !base_ok || !result_ok {
		return {}, false, tree_sitter_failure(.Publish_Parse, .Unavailable_Base_Snapshot)
	}
	if state.confirmed.buffer_id != event.buffer_id ||
	   state.confirmed.source_revision != event.base_revision ||
	   base_stats.buffer_id != event.buffer_id || base_stats.revision != event.base_revision {
		tree_sitter_queue_refresh(state, result_stats.revision)
		return {}, false, tree_sitter_failure(.Publish_Parse, .Stale_Selection)
	}
	if result_stats.buffer_id != event.buffer_id ||
	   result_stats.revision != event.result_revision ||
	   event.result_revision <= event.base_revision ||
	   result_stats.text_bytes > MAX_ANALYZED_SOURCE_BYTES ||
	   result_stats.text_bytes > u64(max(u32)) {
		tree_sitter_queue_refresh(state, result_stats.revision)
		return {}, false, tree_sitter_failure(.Publish_Parse, .Invalid_Transaction)
	}
	if tree_generation == Tree_Generation(0) || tree_generation <= state.tree_generation {
		return {}, false, tree_sitter_failure(.Publish_Parse, .Generation_Limit)
	}

	tree_sitter_memory_begin(state)
	defer tree_sitter_memory_end()
	edited_tree := ts_tree_copy(state.tree)
	if edited_tree == nil {
		return {}, false, tree_sitter_failure(.Publish_Parse, .Allocation)
	}
	edits_ok := tree_sitter_apply_normalized_edits(
		edited_tree,
		base_snapshot,
		result_snapshot,
		base_stats.text_bytes,
		result_stats.text_bytes,
		event.splices,
	)
	if !edits_ok {
		ts_tree_delete(edited_tree)
		tree_sitter_queue_refresh(state, result_stats.revision)
		return {}, false, tree_sitter_failure(.Publish_Parse, .Invalid_Transaction)
	}

	options, progress_ok, progress_failure := tree_sitter_owner_prepare_progress(owner, work_limit_bytes)
	if !progress_ok {
		ts_tree_delete(edited_tree)
		progress_failure.operation = .Publish_Parse
		return {}, false, progress_failure
	}
	input_context := Tree_Sitter_Input_Context {
		snapshot = result_snapshot,
		text_bytes = result_stats.text_bytes,
	}
	input := Tree_Sitter_Input {
		payload = &input_context,
		read = tree_sitter_snapshot_read,
		encoding = .UTF8,
	}
	state.lifecycle = .Parsing
	state.pending = Pending_Work {
		kind = .Incremental,
		selection_generation = state.confirmed.selection_generation,
		source_revision = result_stats.revision,
		work_bytes = work_limit_bytes,
	}
	candidate := ts_parser_parse_with_options(state.parser, edited_tree, input, options)
	ts_tree_delete(edited_tree)
	state.lifecycle = .Ready
	if input_context.failed {
		if candidate != nil do ts_tree_delete(candidate)
		ts_parser_reset(state.parser)
		tree_sitter_queue_refresh(state, result_stats.revision)
		return {}, false, tree_sitter_failure(.Publish_Parse, .Unavailable_Base_Snapshot)
	}
	if candidate == nil {
		failure_code := Failure_Code.Work_Limit
		if state.progress.cancel_requested do failure_code = .Cancelled
		ts_parser_reset(state.parser)
		tree_sitter_queue_refresh(state, result_stats.revision)
		return {}, false, tree_sitter_failure(.Publish_Parse, failure_code)
	}
	if !tree_sitter_owner_replace_tree(owner, candidate, tree_generation) {
		tree_sitter_queue_refresh(state, result_stats.revision)
		return {}, false, tree_sitter_failure(.Publish_Parse, .Generation_Limit)
	}

	work_bytes := u64(state.progress.current_byte_offset)
	if work_bytes == 0 do work_bytes = result_stats.text_bytes
	usage := state.confirmed.usage
	usage.retained_source_bytes = result_stats.text_bytes
	usage.retained_tree_bytes = odra_tree_sitter_memory_owner_live_bytes(state.memory_owner)
	usage.work_bytes = work_bytes
	result = Parse_Snapshot {
		buffer_id = result_stats.buffer_id,
		source_revision = result_stats.revision,
		language = state.confirmed.language,
		provider = state.confirmed.provider,
		selection_generation = state.confirmed.selection_generation,
		parser_generation = state.parser_generation,
		tree_generation = state.tree_generation,
		query_generation = state.query_generation,
		status = .Current,
		usage = usage,
	}
	state.confirmed = result
	state.pending = {}
	return result, true, {}
}

/* odin_capture_mapping maps every admitted factory capture to one semantic role. */
odin_capture_mapping :: proc(name: string) -> (mapping: Odin_Capture_Mapping, known: bool) {
	switch name {
	case "attribute":
		return Odin_Capture_Mapping{role = .Attribute, precedence = 120}, true
	case "boolean":
		return Odin_Capture_Mapping{role = .Boolean, precedence = 110}, true
	case "character", "string", "string.escape":
		return Odin_Capture_Mapping{role = .String, precedence = 110}, true
	case "comment":
		return Odin_Capture_Mapping{role = .Comment, precedence = 140}, true
	case "constant", "constant.builtin":
		return Odin_Capture_Mapping{role = .Constant, precedence = 115}, true
	case "function.macro":
		return Odin_Capture_Mapping{role = .Function_Builtin, precedence = 131}, true
	case "function", "function.call":
		return Odin_Capture_Mapping{role = .Function, precedence = 130}, true
	case "conditional", "conditional.ternary", "include", "keyword",
	     "keyword.function", "keyword.operator", "keyword.return", "preproc",
	     "repeat", "storageclass":
		return Odin_Capture_Mapping{role = .Keyword, precedence = 105}, true
	case "label":
		return Odin_Capture_Mapping{role = .Label, precedence = 115}, true
	case "float", "number":
		return Odin_Capture_Mapping{role = .Number, precedence = 110}, true
	case "operator":
		return Odin_Capture_Mapping{role = .Operator, precedence = 105}, true
	case "punctuation.bracket", "punctuation.delimiter", "punctuation.special":
		return Odin_Capture_Mapping{role = .Punctuation, precedence = 90}, true
	case "type", "type.builtin", "namespace":
		return Odin_Capture_Mapping{role = .Type, precedence = 120}, true
	case "parameter":
		return Odin_Capture_Mapping{role = .Variable_Parameter, precedence = 115}, true
	case "field", "variable", "variable.builtin":
		return Odin_Capture_Mapping{role = .Variable, precedence = 100}, true
	case "error", "spell":
		return Odin_Capture_Mapping{ignored = true}, true
	}
	return {}, false
}

@(private)
tree_sitter_snapshot_read :: proc "c" (
	payload: rawptr,
	byte_index: u32,
	_: Tree_Sitter_Point,
	bytes_read: ^u32,
) -> ^u8 {
	context = runtime.default_context()
	if bytes_read == nil do return nil
	bytes_read^ = 0
	if payload == nil do return nil
	input := cast(^Tree_Sitter_Input_Context)payload
	if input.failed || u64(byte_index) >= input.text_bytes do return nil

	take := min(u64(len(input.scratch)), input.text_bytes - u64(byte_index))
	copied, read_ok, _ := editor.buffer_snapshot_read(
		input.snapshot,
		editor.Byte_Offset(byte_index),
		input.scratch[:int(take)],
	)
	if !read_ok || copied == 0 {
		input.failed = !read_ok
		return nil
	}
	bytes_read^ = u32(copied)
	return raw_data(input.scratch[:])
}

@(private)
tree_sitter_apply_normalized_edits :: proc(
	tree: rawptr,
	base_snapshot, result_snapshot: ^editor.Buffer_Snapshot,
	base_bytes, result_bytes: u64,
	splices: []transaction.Normalized_Splice,
) -> bool {
	if tree == nil || len(splices) == 0 do return false
	base_cursor: u64
	current_byte_cursor: u64
	current_point: Tree_Sitter_Point
	for splice in splices {
		start := u64(splice.start)
		end := u64(splice.end)
		if start < base_cursor || start > end || end > base_bytes ||
		   u64(len(splice.removed_text)) != end - start ||
		   !tree_sitter_snapshot_range_matches(base_snapshot, start, splice.removed_text) {
			return false
		}
		gap_point, gap_ok := tree_sitter_snapshot_advance(
			base_snapshot,
			base_cursor,
			start,
			current_point,
		)
		if !gap_ok do return false
		current_byte_cursor += start - base_cursor
		start_point := gap_point
		old_end_point, removed_ok := tree_sitter_snapshot_advance(
			base_snapshot,
			start,
			end,
			start_point,
		)
		if !removed_ok do return false
		if !tree_sitter_snapshot_range_matches(
			result_snapshot,
			current_byte_cursor,
			splice.replacement_text,
		) {
			return false
		}
		new_end_point := tree_sitter_point_advance(start_point, transmute([]u8)splice.replacement_text)
		new_end_byte, byte_ok := checked_add_u64(current_byte_cursor, u64(len(splice.replacement_text)))
		old_end_byte, old_byte_ok := checked_add_u64(current_byte_cursor, end - start)
		if !byte_ok || !old_byte_ok || new_end_byte > u64(max(u32)) || old_end_byte > u64(max(u32)) {
			return false
		}
		edit := Tree_Sitter_Input_Edit {
			start_byte = u32(current_byte_cursor),
			old_end_byte = u32(old_end_byte),
			new_end_byte = u32(new_end_byte),
			start_point = start_point,
			old_end_point = old_end_point,
			new_end_point = new_end_point,
		}
		ts_tree_edit(tree, &edit)
		base_cursor = end
		current_byte_cursor = new_end_byte
		current_point = new_end_point
	}
	remaining, remaining_ok := checked_add_u64(current_byte_cursor, base_bytes - base_cursor)
	return remaining_ok && remaining == result_bytes
}

@(private)
tree_sitter_snapshot_advance :: proc(
	snapshot: ^editor.Buffer_Snapshot,
	start, end: u64,
	initial: Tree_Sitter_Point,
) -> (point: Tree_Sitter_Point, ok: bool) {
	if start > end do return {}, false
	point = initial
	cursor := start
	scratch: [CANCELLATION_CHECK_BYTES]u8
	for cursor < end {
		take := min(u64(len(scratch)), end - cursor)
		copied, read_ok, _ := editor.buffer_snapshot_read(
			snapshot,
			editor.Byte_Offset(cursor),
			scratch[:int(take)],
		)
		if !read_ok || copied != take do return {}, false
		point = tree_sitter_point_advance(point, scratch[:int(copied)])
		cursor += copied
	}
	return point, true
}

@(private)
tree_sitter_snapshot_range_matches :: proc(
	snapshot: ^editor.Buffer_Snapshot,
	start: u64,
	expected: string,
) -> bool {
	cursor := u64(0)
	scratch: [CANCELLATION_CHECK_BYTES]u8
	for cursor < u64(len(expected)) {
		take := min(u64(len(scratch)), u64(len(expected)) - cursor)
		copied, read_ok, _ := editor.buffer_snapshot_read(
			snapshot,
			editor.Byte_Offset(start + cursor),
			scratch[:int(take)],
		)
		if !read_ok || copied != take ||
		   string(scratch[:int(copied)]) != expected[int(cursor):int(cursor + copied)] {
			return false
		}
		cursor += copied
	}
	return true
}

@(private)
tree_sitter_point_advance :: proc(point: Tree_Sitter_Point, contents: []u8) -> Tree_Sitter_Point {
	result := point
	for value in contents {
		if value == '\n' {
			result.row += 1
			result.column = 0
		} else {
			result.column += 1
		}
	}
	return result
}

@(private)
tree_sitter_queue_refresh :: proc(state: ^Tree_Sitter_Owner_State, revision: editor.Revision) {
	if state == nil do return
	state.pending = Pending_Work {
		kind = .Refresh,
		selection_generation = state.confirmed.selection_generation,
		source_revision = revision,
		work_bytes = REFRESH_WORK_BYTES,
		refresh_requested = true,
	}
}

@(private)
checked_add_u64 :: proc(left, right: u64) -> (u64, bool) {
	if right > max(u64) - left do return 0, false
	return left + right, true
}

@(private)
tree_sitter_query_validate_capture_mapping :: proc(query: rawptr) -> (ok: bool, invalid_index: u32) {
	if query == nil do return false, 0
	count := ts_query_capture_count(query)
	for index in 0 ..< count {
		length: u32
		name_pointer := ts_query_capture_name_for_id(query, index, &length)
		if name_pointer == nil || length == 0 do return false, index
		name := string((cast([^]u8)name_pointer)[:length])
		mapping, known := odin_capture_mapping(name)
		if !known do return false, index
		if mapping.ignored {
			ts_query_disable_capture(query, name_pointer, length)
		}
	}
	return true, 0
}
