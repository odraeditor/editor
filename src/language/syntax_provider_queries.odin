// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language

import "core:strings"

@(private)
Tree_Sitter_Capture_Projection :: struct {
	role:            Syntax_Role,
	structural_role: Syntax_Structural_Role,
	precedence:      u16,
	ignored:         bool,
}

/* syntax_provider_compile_queries verifies and atomically compiles query data. */
syntax_provider_compile_queries :: proc(
	runtime: ^Syntax_Provider_Runtime,
	allocator := context.allocator,
	cancellation: Syntax_Provider_Cancellation = {},
) -> (ok: bool, failure: Failure) {
	if runtime == nil || runtime.status != .Loaded {
		return false, syntax_provider_loader_failure(.Compile_Queries, .Invalid_Provider)
	}
	if syntax_provider_cancelled(cancellation) {
		return false, syntax_provider_loader_failure(.Compile_Queries, .Cancelled)
	}
	sources: [MAX_SYNTAX_QUERY_ARTIFACTS][]u8
	total_bytes: u64
	defer {
		for source in sources do if source != nil do delete(source, allocator)
	}
	for query, index in runtime.record.queries[:runtime.record.query_count] {
		query_path := query.path
		source, loaded, load_failure := syntax_artifact_read_verified(
			syntax_artifact_path_view(&query_path),
			query.digest,
			query.size,
			runtime.record.resources.query_bytes,
			.Compile_Queries,
			allocator,
			cancellation,
		)
		if !loaded {
			runtime.latest_failure = load_failure
			return false, load_failure
		}
		sources[index] = source
		if query.size > runtime.record.resources.query_bytes - total_bytes {
			failure = syntax_provider_loader_failure(.Compile_Queries, .Query_Limit)
			failure.limit = runtime.record.resources.query_bytes
			failure.actual = total_bytes + query.size
			runtime.latest_failure = failure
			return false, failure
		}
		total_bytes += query.size
	}
	compiled, compile_failure := tree_sitter_owner_compile_provider_queries(
		&runtime.owner,
		&runtime.record,
		sources[:runtime.record.query_count],
	)
	if !compiled {
		compile_failure.operation = .Compile_Queries
		runtime.latest_failure = compile_failure
		return false, compile_failure
	}
	runtime.query_bytes = total_bytes
	runtime.latest_failure = {}
	return true, {}
}

/* syntax_provider_capture_mapping resolves exact then dotted-parent mappings. */
syntax_provider_capture_mapping :: proc(
	record: ^Syntax_Provider_Record,
	capture: string,
) -> (mapping: Syntax_Capture_Mapping, mapped: bool) {
	if record == nil || len(capture) == 0 do return {}, false
	candidate := capture
	for {
		for entry in record.mappings[:record.mapping_count] {
			entry_capture := entry.capture
			if syntax_capture_name_view(&entry_capture) == candidate do return entry, true
		}
		separator := strings.last_index_byte(candidate, '.')
		if separator < 0 do break
		candidate = candidate[:separator]
	}
	return {}, false
}

/* tree_sitter_owner_compile_mapped_query installs one embedded factory query. */
tree_sitter_owner_compile_mapped_query :: proc(
	owner: ^Tree_Sitter_Owner,
	source: []u8,
	mappings: []Syntax_Capture_Mapping_Proposal,
	generation: Query_Generation,
) -> (ok: bool, failure: Failure) {
	if len(source) == 0 || len(mappings) == 0 ||
	   len(mappings) > MAX_SYNTAX_CAPTURE_MAPPINGS || generation == Query_Generation(0) {
		return false, tree_sitter_failure(.Compile_Queries, .Invalid_Capture_Mapping)
	}
	record: Syntax_Provider_Record
	record.query_count = 1
	record.queries[0] = Syntax_Query_Artifact {
		kind = .Highlights,
		size = u64(len(source)),
		generation = generation,
	}
	record.resources.query_bytes = u64(len(source))
	for mapping, index in mappings {
		if !syntax_mapping_proposal_valid(mapping) {
			return false, tree_sitter_failure(.Compile_Queries, .Invalid_Capture_Mapping)
		}
		for prior in 0 ..< index {
			if mappings[prior].capture == mapping.capture {
				return false, tree_sitter_failure(.Compile_Queries, .Invalid_Capture_Mapping)
			}
		}
		record.mappings[index] = syntax_mapping_copy(mapping)
	}
	record.mapping_count = u16(len(mappings))
	sources := [?][]u8{source}
	return tree_sitter_owner_compile_provider_queries(owner, &record, sources[:])
}

@(private)
tree_sitter_owner_compile_provider_queries :: proc(
	owner: ^Tree_Sitter_Owner,
	record: ^Syntax_Provider_Record,
	sources: [][]u8,
) -> (ok: bool, failure: Failure) {
	state := tree_sitter_owner_state(owner)
	if state == nil || record == nil || len(sources) != int(record.query_count) {
		return false, tree_sitter_failure(.Compile_Queries, .Parser_Initialization)
	}
	candidates: [MAX_SYNTAX_QUERY_ARTIFACTS]rawptr
	defer {
		for candidate in candidates do if candidate != nil do ts_query_delete(candidate)
	}
	tree_sitter_memory_begin(state)
	defer tree_sitter_memory_end()
	for source, index in sources {
		if len(source) == 0 || u64(len(source)) > record.resources.query_bytes || len(source) > int(max(u32)) {
			return false, tree_sitter_failure(.Compile_Queries, .Query_Limit)
		}
		error_offset: u32
		error_type: Tree_Sitter_Query_Error
		candidate := ts_query_new(
			state.language,
			raw_data(source),
			u32(len(source)),
			&error_offset,
			&error_type,
		)
		if candidate == nil {
			failure = tree_sitter_failure(.Compile_Queries, .Invalid_Query)
			failure.limit = u64(error_type)
			failure.actual = u64(error_offset)
			return false, failure
		}
		capture_count := ts_query_capture_count(candidate)
		if capture_count > MAX_SYNTAX_CAPTURE_MAPPINGS {
			ts_query_delete(candidate)
			failure = tree_sitter_failure(.Compile_Queries, .Capture_Limit)
			failure.limit = MAX_SYNTAX_CAPTURE_MAPPINGS
			failure.actual = u64(capture_count)
			return false, failure
		}
		for capture_index in 0 ..< capture_count {
			length: u32
			name_pointer := ts_query_capture_name_for_id(candidate, capture_index, &length)
			if name_pointer == nil || length == 0 {
				ts_query_delete(candidate)
				return false, tree_sitter_failure(.Compile_Queries, .Invalid_Capture_Mapping)
			}
			name := string((cast([^]u8)name_pointer)[:length])
			_, mapped := syntax_provider_capture_mapping(record, name)
			if !mapped do ts_query_disable_capture(candidate, name_pointer, length)
		}
		candidates[index] = candidate
	}

	for query in state.provider_queries[:state.provider_query_count] {
		if query != nil {
			if query == state.query do state.query = nil
			ts_query_delete(query)
		}
	}
	state.provider_queries = {}
	state.provider_query_kinds = {}
	state.provider_query_generations = {}
	state.provider_query_count = record.query_count
	state.provider_capture_mappings = record.mappings
	state.provider_capture_mapping_count = record.mapping_count
	for query, index in record.queries[:record.query_count] {
		state.provider_queries[index] = candidates[index]
		candidates[index] = nil
		state.provider_query_kinds[index] = query.kind
		state.provider_query_generations[index] = query.generation
		if query.kind == .Highlights {
			if state.query != nil do ts_query_delete(state.query)
			state.query = state.provider_queries[index]
			state.query_generation = query.generation
			state.query_bytes = query.size
			state.query_captures = ts_query_capture_count(state.query)
		}
	}
	return true, {}
}

@(private)
tree_sitter_owner_capture_projection :: proc(
	state: ^Tree_Sitter_Owner_State,
	capture: string,
) -> (projection: Tree_Sitter_Capture_Projection, mapped: bool) {
	if state == nil || len(capture) == 0 do return {}, false
	if state.provider_capture_mapping_count == 0 {
		mapping, known := odin_capture_mapping(capture)
		if !known do return {}, false
		return Tree_Sitter_Capture_Projection {
			role = mapping.role,
			precedence = mapping.precedence,
			ignored = mapping.ignored,
		}, true
	}
	candidate := capture
	for {
		for mapping in state.provider_capture_mappings[:state.provider_capture_mapping_count] {
			mapping_capture := mapping.capture
			if syntax_capture_name_view(&mapping_capture) == candidate {
				return Tree_Sitter_Capture_Projection {
					role = mapping.role,
					structural_role = mapping.structural_role,
					precedence = mapping.precedence,
				}, true
			}
		}
		separator := strings.last_index_byte(candidate, '.')
		if separator < 0 do break
		candidate = candidate[:separator]
	}
	return {}, false
}
