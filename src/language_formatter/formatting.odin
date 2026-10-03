// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language_formatter

import "../editor"
import "../language_service"
import "../transaction"
import "base:runtime"
import json "core:encoding/json"
import "core:slice"
import "core:strings"
import "core:unicode/utf8"

Formatting_Source :: struct {
	formatter:       Formatter_Handle,
	buffer:          ^editor.Buffer,
	buffer_id:       editor.Buffer_ID,
	base_revision:   editor.Revision,
	text:            string,
	position_encoding: language_service.Position_Encoding,
	scope:           Formatter_Scope,
	start_byte:      u64,
	end_byte:        u64,
	limits:          Formatter_Limits,
}

Formatting_Proposal :: struct {
	edit:  transaction.Edit_Proposal,
	state: rawptr,
}

@(private)
Formatting_Proposal_State :: struct {
	snapshot:    [1]transaction.Proposal_Snapshot,
	edit:        [1]transaction.Proposal_Edit,
	splices:     [dynamic]transaction.Base_Splice,
	replacements: [dynamic]string,
	allocator:   runtime.Allocator,
}

/* formatting_proposal_from_output converts external output into one exact-revision transaction proposal. */
formatting_proposal_from_output :: proc(
	source: Formatting_Source,
	formatted: []u8,
	allocator := context.allocator,
) -> (Formatting_Proposal, bool, Failure) {
	if !formatting_source_valid(source) do return {}, false, Failure{code = .Invalid_Input}
	if u64(len(formatted)) > source.limits.output_bytes || !utf8.valid_string(string(formatted)) {
		return {}, false, Failure{code = .Output_Limit, resource = .Output_Bytes, limit = source.limits.output_bytes, actual = u64(len(formatted))}
	}
	state, opened, failure := formatting_state_open(source, allocator)
	if !opened do return {}, false, failure
	replacement, allocation_error := strings.clone(string(formatted), allocator)
	if allocation_error != nil {
		formatting_state_destroy(state)
		return {}, false, Failure{code = .Allocation}
	}
	_, append_error := append(&state.replacements, replacement)
	if append_error != nil {
		delete(replacement, allocator)
		formatting_state_destroy(state)
		return {}, false, Failure{code = .Allocation}
	}
	splice, valid := formatting_splice(source, source.start_byte, source.end_byte, replacement)
	if !valid {
		formatting_state_destroy(state)
		return {}, false, Failure{code = .Malformed_Output}
	}
	_, append_error = append(&state.splices, splice)
	if append_error != nil {
		formatting_state_destroy(state)
		return {}, false, Failure{code = .Allocation}
	}
	return formatting_state_finish(state, source), true, {}
}

/* formatting_proposal_from_lsp normalizes one JSON-RPC formatting result into bounded base-relative edits. */
formatting_proposal_from_lsp :: proc(
	source: Formatting_Source,
	response: []u8,
	allocator := context.allocator,
) -> (Formatting_Proposal, bool, Failure) {
	if !formatting_source_valid(source) || source.position_encoding == .Invalid ||
	   u64(len(response)) > source.limits.output_bytes {
		return {}, false, Failure{code = .Invalid_Input}
	}
	value, parse_error := json.parse_bytes(response, .JSON, true, context.temp_allocator)
	if parse_error != .None do return {}, false, Failure{code = .Malformed_Output}
	defer json.destroy_value(value, context.temp_allocator)
	object, object_ok := value.(json.Object)
	if !object_ok do return {}, false, Failure{code = .Malformed_Output}
	result, present := object["result"]
	if !present do return {}, false, Failure{code = .Malformed_Output}
	if _, empty := result.(json.Null); empty {
		state, opened, failure := formatting_state_open(source, allocator)
		if !opened do return {}, false, failure
		return formatting_state_finish(state, source), true, {}
	}
	edits, edits_ok := result.(json.Array)
	if !edits_ok || u64(len(edits)) > u64(source.limits.edits) {
		return {}, false, Failure{code = .Resource_Limit, resource = .Edit, limit = u64(source.limits.edits), actual = u64(len(edits))}
	}
	state, opened, failure := formatting_state_open(source, allocator)
	if !opened do return {}, false, failure
	for item in edits {
		item_object, item_ok := item.(json.Object)
		if !item_ok {
			formatting_state_destroy(state)
			return {}, false, Failure{code = .Malformed_Output}
		}
		range_value, range_present := item_object["range"]
		text_value, text_present := item_object["newText"]
		new_text, text_ok := text_value.(json.String)
		if !range_present || !text_present || !text_ok || !utf8.valid_string(string(new_text)) {
			formatting_state_destroy(state)
			return {}, false, Failure{code = .Malformed_Output}
		}
		start, end, range_ok := formatting_lsp_range(source, range_value)
		if !range_ok {
			formatting_state_destroy(state)
			return {}, false, Failure{code = .Malformed_Output}
		}
		replacement, allocation_error := strings.clone(string(new_text), allocator)
		if allocation_error != nil {
			formatting_state_destroy(state)
			return {}, false, Failure{code = .Allocation}
		}
		_, append_error := append(&state.replacements, replacement)
		if append_error != nil {
			delete(replacement, allocator)
			formatting_state_destroy(state)
			return {}, false, Failure{code = .Allocation}
		}
		splice, valid := formatting_splice(source, start, end, replacement)
		if !valid {
			formatting_state_destroy(state)
			return {}, false, Failure{code = .Malformed_Output}
		}
		_, append_error = append(&state.splices, splice)
		if append_error != nil {
			formatting_state_destroy(state)
			return {}, false, Failure{code = .Allocation}
		}
	}
	slice.sort_by(state.splices[:], formatting_splice_less)
	for index in 1..<len(state.splices) {
		previous := state.splices[index - 1]
		current := state.splices[index]
		if current.start.byte_offset < previous.end.byte_offset ||
		   (current.start.byte_offset == previous.start.byte_offset && current.end.byte_offset == previous.end.byte_offset) {
			formatting_state_destroy(state)
			return {}, false, Failure{code = .Overlapping_Edit}
		}
	}
	return formatting_state_finish(state, source), true, {}
}

formatting_proposal_close :: proc(proposal: ^Formatting_Proposal) -> bool {
	if proposal == nil || proposal.state == nil do return false
	formatting_state_destroy(cast(^Formatting_Proposal_State)proposal.state)
	proposal^ = {}
	return true
}

@(private)
formatting_source_valid :: proc(source: Formatting_Source) -> bool {
	if !formatter_handle_valid(source.formatter) || source.buffer == nil || source.buffer_id == editor.Buffer_ID(0) ||
	   source.scope == .Invalid || !formatter_limits_valid(source.limits) || !utf8.valid_string(source.text) ||
	   u64(len(source.text)) > source.limits.input_bytes || source.start_byte > source.end_byte ||
	   source.end_byte > u64(len(source.text)) || !utf8.valid_string(source.text[:int(source.start_byte)]) ||
	   !utf8.valid_string(source.text[:int(source.end_byte)]) {
		return false
	}
	if source.scope == .Document && (source.start_byte != 0 || source.end_byte != u64(len(source.text))) do return false
	stats, stats_ok, _ := editor.buffer_stats(source.buffer)
	return stats_ok && stats.buffer_id == source.buffer_id && stats.revision == source.base_revision &&
		stats.text_bytes == u64(len(source.text))
}

@(private)
formatting_state_open :: proc(
	source: Formatting_Source,
	allocator: runtime.Allocator,
) -> (^Formatting_Proposal_State, bool, Failure) {
	if allocator.procedure == nil do return nil, false, Failure{code = .Allocation}
	state, allocation_error := new(Formatting_Proposal_State, allocator)
	if allocation_error != nil do return nil, false, Failure{code = .Allocation}
	state.allocator = allocator
	state.splices, allocation_error = make([dynamic]transaction.Base_Splice, 0, 4, allocator)
	if allocation_error == nil do state.replacements, allocation_error = make([dynamic]string, 0, 4, allocator)
	if allocation_error != nil {
		formatting_state_destroy(state)
		return nil, false, Failure{code = .Allocation}
	}
	state.snapshot[0] = {
		buffer = source.buffer,
		buffer_id = source.buffer_id,
		base_revision = source.base_revision,
	}
	return state, true, {}
}

@(private)
formatting_state_finish :: proc(state: ^Formatting_Proposal_State, source: Formatting_Source) -> Formatting_Proposal {
	state.edit[0] = {
		buffer_id = source.buffer_id,
		base_revision = source.base_revision,
		batch = state.splices[:],
	}
	return {
		edit = {
			origin = {kind = .Language_Tool, descriptor = "language-formatter"},
			command = "format-document",
			snapshots = state.snapshot[:],
			edits = state.edit[:],
		},
		state = state,
	}
}

@(private)
formatting_state_destroy :: proc(state: ^Formatting_Proposal_State) {
	if state == nil do return
	allocator := state.allocator
	for replacement in state.replacements do delete(replacement, allocator)
	if state.replacements != nil do delete(state.replacements)
	if state.splices != nil do delete(state.splices)
	free(state, allocator)
}

@(private)
formatting_lsp_range :: proc(source: Formatting_Source, value: json.Value) -> (u64, u64, bool) {
	object, object_ok := value.(json.Object)
	if !object_ok do return 0, 0, false
	start_value, start_present := object["start"]
	end_value, end_present := object["end"]
	if !start_present || !end_present do return 0, 0, false
	start_position, start_ok := language_service.lsp_position_from_json(start_value)
	end_position, end_ok := language_service.lsp_position_from_json(end_value)
	if !start_ok || !end_ok do return 0, 0, false
	start, start_converted, _ := language_service.position_to_byte_offset(source.text, start_position, source.position_encoding)
	end, end_converted, _ := language_service.position_to_byte_offset(source.text, end_position, source.position_encoding)
	if !start_converted || !end_converted || start > end do return 0, 0, false
	if source.scope == .Range && (start < source.start_byte || end > source.end_byte) do return 0, 0, false
	return start, end, true
}

@(private)
formatting_splice :: proc(source: Formatting_Source, start, end: u64, replacement: string) -> (transaction.Base_Splice, bool) {
	start_position, start_ok := editor.position_make(source.buffer_id, source.base_revision, editor.Byte_Offset(start))
	end_position, end_ok := editor.position_make(source.buffer_id, source.base_revision, editor.Byte_Offset(end))
	return {start = start_position, end = end_position, replacement = replacement}, start_ok && end_ok
}

@(private)
formatting_splice_less :: proc(left, right: transaction.Base_Splice) -> bool {
	if left.start.byte_offset != right.start.byte_offset do return left.start.byte_offset < right.start.byte_offset
	return left.end.byte_offset < right.end.byte_offset
}
