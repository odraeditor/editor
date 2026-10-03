// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package interaction

import "base:runtime"
import endian "core:encoding/endian"

/* PERSONAL_CANDIDATE_RESULT_SCHEMA identifies the current copied result format. */
PERSONAL_CANDIDATE_RESULT_SCHEMA :: u64(2)
/* PERSONAL_CANDIDATE_RESULT_LEGACY_SCHEMA identifies the accepted legacy format. */
PERSONAL_CANDIDATE_RESULT_LEGACY_SCHEMA :: u64(1)
/* PERSONAL_CANDIDATE_RESULT_HEADER_BYTES is the fixed copied header size. */
PERSONAL_CANDIDATE_RESULT_HEADER_BYTES :: 64
/* PERSONAL_CANDIDATE_RESULT_RECORD_BYTES is the current copied row size. */
PERSONAL_CANDIDATE_RESULT_RECORD_BYTES :: 96
/* PERSONAL_CANDIDATE_RESULT_LEGACY_RECORD_BYTES is the legacy copied row size. */
PERSONAL_CANDIDATE_RESULT_LEGACY_RECORD_BYTES :: 88
/* MAX_PERSONAL_CANDIDATES bounds one programmable result surface. */
MAX_PERSONAL_CANDIDATES :: 256

/* Personal_Candidate_Action distinguishes navigation from command resumption. */
Personal_Candidate_Action :: enum u8 {
	Invalid,
	Navigate,
	Resume,
	Resume_Value,
	Resume_Query,
	Navigate_Direct,
}

/* Personal_Candidate_Target is one borrowed package-provided document anchor. */
Personal_Candidate_Target :: struct {
	identity:       string,
	document_path:  string,
	start:          u64,
	end:            u64,
	source_revision: u64,
	action:          Personal_Candidate_Action,
}

/* Personal_Candidate_Source adapts one copied personal-command result. */
Personal_Candidate_Source :: struct {
	definition: Candidate_Source_Definition,
	descriptors: []Candidate_Descriptor_Definition,
	fields:      []string,
	targets:     []Personal_Candidate_Target,
	title:       string,
	initial_query: string,
	allocator:   runtime.Allocator,
}

/* personal_candidate_source_decode validates one complete copied result. */
personal_candidate_source_decode :: proc(
	input: []u8,
	source_generation: u64,
	allocator := context.temp_allocator,
) -> (source: Personal_Candidate_Source, ok: bool, failure: Candidate_Failure) {
	if len(input) < PERSONAL_CANDIDATE_RESULT_HEADER_BYTES ||
	   source_generation == 0 || allocator.procedure == nil {
		return {}, false, Candidate_Failure{code = .Invalid_Source}
	}
	schema := personal_candidate_u64(input, 0)
	generation := personal_candidate_u64(input, 8)
	count := personal_candidate_u64(input, 16)
	record_bytes := personal_candidate_u64(input, 24)
	query_offset := personal_candidate_u64(input, 32)
	query_length := personal_candidate_u64(input, 40)
	string_bytes := personal_candidate_u64(input, 48)
	title_length := personal_candidate_u64(input, 56)
	current_schema := schema == PERSONAL_CANDIDATE_RESULT_SCHEMA &&
	                  record_bytes == PERSONAL_CANDIDATE_RESULT_RECORD_BYTES
	legacy_schema := schema == PERSONAL_CANDIDATE_RESULT_LEGACY_SCHEMA &&
	                 record_bytes == PERSONAL_CANDIDATE_RESULT_LEGACY_RECORD_BYTES
	if (!current_schema && !legacy_schema) || generation == 0 ||
	   count == 0 || count > MAX_PERSONAL_CANDIDATES ||
	   count > u64(max(int)) / record_bytes {
		return {}, false, Candidate_Failure{code = .Invalid_Source}
	}
	record_total := count * record_bytes
	string_start := u64(PERSONAL_CANDIDATE_RESULT_HEADER_BYTES) + record_total
	if string_start > u64(len(input)) || string_bytes != u64(len(input)) - string_start ||
	   !personal_candidate_span_valid(0, title_length, string_bytes) ||
	   !personal_candidate_span_valid(query_offset, query_length, string_bytes) {
		return {}, false, Candidate_Failure{code = .Invalid_Source}
	}
	source.allocator = allocator
	allocation_error: runtime.Allocator_Error
	source.descriptors, allocation_error = make([]Candidate_Descriptor_Definition, int(count), allocator)
	if allocation_error != nil do return personal_candidate_source_allocation_failure(&source)
	source.fields, allocation_error = make([]string, int(count), allocator)
	if allocation_error != nil do return personal_candidate_source_allocation_failure(&source)
	source.targets, allocation_error = make([]Personal_Candidate_Target, int(count), allocator)
	if allocation_error != nil do return personal_candidate_source_allocation_failure(&source)
	strings := input[int(string_start):]
	source.title = string(strings[:int(title_length)])
	source.initial_query = string(strings[int(query_offset):int(query_offset + query_length)])
	for index in 0 ..< int(count) {
		base := PERSONAL_CANDIDATE_RESULT_HEADER_BYTES + index * int(record_bytes)
		values: [12]u64
		value_count := 11
		if current_schema do value_count = 12
		for value_index in 0 ..< value_count {
			offset := base + value_index * 8
			values[value_index] = personal_candidate_u64(input, offset)
		}
		for span_index in 0 ..< 4 {
			if !personal_candidate_span_valid(values[span_index * 2], values[span_index * 2 + 1], string_bytes) {
				personal_candidate_source_close(&source)
				return {}, false, Candidate_Failure{code = .Invalid_Source}
			}
		}
		action := Personal_Candidate_Action.Navigate
		if current_schema {
			switch values[11] {
			case 1: action = .Navigate
			case 2: action = .Resume
			case 3: action = .Resume_Value
			case 4: action = .Resume_Query
			case 5: action = .Navigate_Direct
			case:
				personal_candidate_source_close(&source)
				return {}, false, Candidate_Failure{code = .Invalid_Source}
			}
		}
		if values[8] > values[9] {
			personal_candidate_source_close(&source)
			return {}, false, Candidate_Failure{code = .Invalid_Source}
		}
		identity := personal_candidate_text(strings, values[0], values[1])
		label := personal_candidate_text(strings, values[2], values[3])
		search := personal_candidate_text(strings, values[4], values[5])
		path := personal_candidate_text(strings, values[6], values[7])
		if len(identity) == 0 || len(label) == 0 || len(path) == 0 {
			personal_candidate_source_close(&source)
			return {}, false, Candidate_Failure{code = .Invalid_Source}
		}
		source.fields[index] = search
		source.targets[index] = {
			identity = identity,
			document_path = path,
			start = values[8],
			end = values[9],
			source_revision = values[10],
			action = action,
		}
		fields := source.fields[index:index]
		if len(search) > 0 do fields = source.fields[index:index + 1]
		source.descriptors[index] = {
			identity = {kind = 21, primary = u64(index + 1), secondary = generation},
			label = label,
			searchable_fields = fields,
			action = {
				kind = .Open_Command_Prompt if action == .Resume_Query else
				       .Open_Command_Candidate,
				owner_generation = generation,
				primary = u64(index + 1),
			},
			availability = .Available,
		}
	}
	source.definition = {
		kind = .Personal_Command_Results,
		scope_identity = generation,
		scope_generation = generation,
		source_generation = source_generation,
		descriptors = source.descriptors,
	}
	return source, true, {}
}

/* personal_candidate_source_close releases one decoded copied result. */
personal_candidate_source_close :: proc(source: ^Personal_Candidate_Source) -> bool {
	if source == nil || source.allocator.procedure == nil do return false
	delete(source.targets, source.allocator)
	delete(source.fields, source.allocator)
	delete(source.descriptors, source.allocator)
	source^ = {}
	return true
}

/* personal_candidate_action_target resolves one current semantic result action. */
personal_candidate_action_target :: proc(
	action: Candidate_Action,
	source: ^Personal_Candidate_Source,
) -> (Personal_Candidate_Target, bool) {
	if source == nil ||
	   (action.kind != .Open_Command_Candidate && action.kind != .Open_Command_Prompt) ||
	   action.owner_generation != source.definition.scope_generation ||
	   action.primary == 0 || action.primary > u64(len(source.targets)) {
		return {}, false
	}
	return source.targets[int(action.primary - 1)], true
}

@(private)
personal_candidate_span_valid :: proc(offset, length, total: u64) -> bool {
	return offset <= total && length <= total - offset && offset + length <= u64(max(int))
}

@(private)
personal_candidate_text :: proc(strings: []u8, offset, length: u64) -> string {
	return string(strings[int(offset):int(offset + length)])
}

@(private)
personal_candidate_u64 :: proc(input: []u8, offset: int) -> u64 {
	value, ok := endian.get_u64(input[offset:offset + 8], .Little)
	assert(ok)
	return value
}

@(private)
personal_candidate_source_allocation_failure :: proc(
	source: ^Personal_Candidate_Source,
) -> (Personal_Candidate_Source, bool, Candidate_Failure) {
	personal_candidate_source_close(source)
	return {}, false, Candidate_Failure{code = .Temporary_Memory_Limit}
}
