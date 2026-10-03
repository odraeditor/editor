// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language

import "../editor"
import "base:runtime"
import "core:dynlib"

/* TREE_SITTER_RUNTIME_ABI is the pinned runtime language ABI. */
TREE_SITTER_RUNTIME_ABI :: u32(15)
/* TREE_SITTER_MINIMUM_ABI is the oldest grammar ABI accepted by the runtime. */
TREE_SITTER_MINIMUM_ABI :: u32(13)
/* TREE_SITTER_ODIN_ABI is the pinned generated Odin grammar ABI. */
TREE_SITTER_ODIN_ABI :: u32(14)
/* TREE_SITTER_RACKET_ABI is the pinned generated Racket grammar ABI. */
TREE_SITTER_RACKET_ABI :: u32(15)
/* TREE_SITTER_GO_ABI is the pinned generated Go grammar ABI. */
TREE_SITTER_GO_ABI :: u32(15)
/* TREE_SITTER_RUST_ABI is the pinned generated Rust grammar ABI. */
TREE_SITTER_RUST_ABI :: u32(15)
/* TREE_SITTER_JAVASCRIPT_ABI is the pinned generated JavaScript grammar ABI. */
TREE_SITTER_JAVASCRIPT_ABI :: u32(15)
/* TREE_SITTER_TYPESCRIPT_ABI is the pinned generated TypeScript and TSX grammar ABI. */
TREE_SITTER_TYPESCRIPT_ABI :: u32(14)
/* TREE_SITTER_HTML_ABI is the pinned generated HTML grammar ABI. */
TREE_SITTER_HTML_ABI :: u32(14)
/* TREE_SITTER_CSS_ABI is the pinned generated CSS grammar ABI. */
TREE_SITTER_CSS_ABI :: u32(15)

/* Tree_Sitter_Owner is the opaque native owner of all foreign syntax values. */
Tree_Sitter_Owner :: struct {
	state:  rawptr,
	closed: bool,
}

/* Tree_Sitter_Owner_Stats is copied inspection without foreign pointers. */
Tree_Sitter_Owner_Stats :: struct {
	lifecycle:          Parser_Lifecycle,
	parser_generation:  Parser_Generation,
	tree_generation:    Tree_Generation,
	query_generation:   Query_Generation,
	grammar_abi:        u32,
	query_bytes:        u64,
	query_captures:     u32,
	has_tree:           bool,
	has_query:          bool,
	has_cursor:         bool,
	cancel_requested:   bool,
	progress_checks:    u64,
	current_byte_offset: u32,
	work_limit_bytes:   u64,
	confirmed_buffer_id: editor.Buffer_ID,
	confirmed_revision: editor.Revision,
	selection_generation: Selection_Generation,
	pending:             Pending_Work,
	foreign_live_bytes:  u64,
	foreign_peak_bytes:  u64,
	foreign_allocations: u64,
	foreign_frees:       u64,
}

@(private)
Tree_Sitter_Progress :: struct {
	cancel_requested:   bool,
	checks:              u64,
	current_byte_offset: u32,
	work_limit_bytes:    u64,
}

@(private)
Tree_Sitter_Owner_State :: struct {
	language:           rawptr,
	parser:             rawptr,
	tree:               rawptr,
	query:              rawptr,
	cursor:             rawptr,
	lifecycle:          Parser_Lifecycle,
	parser_generation:  Parser_Generation,
	tree_generation:    Tree_Generation,
	query_generation:   Query_Generation,
	query_bytes:        u64,
	query_captures:     u32,
	progress:           Tree_Sitter_Progress,
	confirmed:          Parse_Snapshot,
	pending:            Pending_Work,
	memory_owner:       u32,
	allocator:          runtime.Allocator,
	dynamic_library:    dynlib.Library,
	provider_queries:   [MAX_SYNTAX_QUERY_ARTIFACTS]rawptr,
	provider_query_kinds: [MAX_SYNTAX_QUERY_ARTIFACTS]Syntax_Query_Kind,
	provider_query_generations: [MAX_SYNTAX_QUERY_ARTIFACTS]Query_Generation,
	provider_query_count: u8,
	provider_capture_mappings: [MAX_SYNTAX_CAPTURE_MAPPINGS]Syntax_Capture_Mapping,
	provider_capture_mapping_count: u16,
}

/* tree_sitter_owner_init creates one parser and cursor for the pinned grammar. */
tree_sitter_owner_init :: proc(
	owner: ^Tree_Sitter_Owner,
	parser_generation: Parser_Generation,
	allocator := context.allocator,
) -> (ok: bool, failure: Failure) {
	return tree_sitter_owner_init_factory(
		owner,
		FACTORY_ODIN_BUNDLE_IDENTITY,
		parser_generation,
		allocator,
	)
}

/* tree_sitter_owner_init_factory creates one owner for an exact factory bundle. */
tree_sitter_owner_init_factory :: proc(
	owner: ^Tree_Sitter_Owner,
	bundle_identity: string,
	parser_generation: Parser_Generation,
	allocator := context.allocator,
) -> (ok: bool, failure: Failure) {
	if owner == nil || parser_generation == Parser_Generation(0) {
		return false, tree_sitter_failure(.Initialize, .Parser_Initialization)
	}
	owner^ = {}
	if allocator.procedure == nil {
		return false, tree_sitter_failure(.Initialize, .Allocation)
	}

	expected_abi, known := factory_syntax_grammar_abi(bundle_identity)
	if !known {
		return false, tree_sitter_failure(.Initialize, .Invalid_Language)
	}
	language := tree_sitter_factory_language(bundle_identity)
	if language == nil {
		return false, tree_sitter_failure(.Initialize, .Parser_Initialization)
	}
	grammar_abi := ts_language_abi_version(language)
	if grammar_abi < TREE_SITTER_MINIMUM_ABI || grammar_abi > TREE_SITTER_RUNTIME_ABI ||
	   grammar_abi != expected_abi {
		failure = tree_sitter_failure(.Initialize, .Grammar_ABI_Incompatible)
		failure.limit = u64(TREE_SITTER_RUNTIME_ABI)
		failure.actual = u64(grammar_abi)
		return false, failure
	}

	return tree_sitter_owner_init_language(owner, language, parser_generation, {}, allocator)
}

@(private)
factory_syntax_grammar_abi :: proc(bundle_identity: string) -> (u32, bool) {
	switch bundle_identity {
	case FACTORY_ODIN_BUNDLE_IDENTITY:
		return TREE_SITTER_ODIN_ABI, true
	case FACTORY_JAN_BUNDLE_IDENTITY:
		return TREE_SITTER_JAN_ABI, true
	case FACTORY_RACKET_BUNDLE_IDENTITY:
		return TREE_SITTER_RACKET_ABI, true
	case FACTORY_GO_BUNDLE_IDENTITY:
		return TREE_SITTER_GO_ABI, true
	case FACTORY_RUST_BUNDLE_IDENTITY:
		return TREE_SITTER_RUST_ABI, true
	case FACTORY_JAVASCRIPT_BUNDLE_IDENTITY, FACTORY_JAVASCRIPT_JSX_IDENTITY:
		return TREE_SITTER_JAVASCRIPT_ABI, true
	case FACTORY_TYPESCRIPT_BUNDLE_IDENTITY, FACTORY_TYPESCRIPT_TSX_IDENTITY:
		return TREE_SITTER_TYPESCRIPT_ABI, true
	case FACTORY_HTML_BUNDLE_IDENTITY:
		return TREE_SITTER_HTML_ABI, true
	case FACTORY_CSS_BUNDLE_IDENTITY:
		return TREE_SITTER_CSS_ABI, true
	}
	return 0, false
}

@(private)
tree_sitter_owner_init_language :: proc(
	owner: ^Tree_Sitter_Owner,
	language: rawptr,
	parser_generation: Parser_Generation,
	dynamic_library: dynlib.Library,
	allocator: runtime.Allocator,
) -> (ok: bool, failure: Failure) {
	if owner == nil || language == nil || parser_generation == Parser_Generation(0) {
		if dynamic_library != nil do _ = dynlib.unload_library(dynamic_library)
		return false, tree_sitter_failure(.Initialize, .Parser_Initialization)
	}
	owner^ = {}
	if allocator.procedure == nil {
		if dynamic_library != nil do _ = dynlib.unload_library(dynamic_library)
		return false, tree_sitter_failure(.Initialize, .Allocation)
	}
	odra_tree_sitter_memory_install()
	memory_owner := odra_tree_sitter_memory_owner_open()
	if memory_owner == 0 {
		if dynamic_library != nil do _ = dynlib.unload_library(dynamic_library)
		return false, tree_sitter_failure(.Initialize, .Retained_Memory_Limit)
	}
	odra_tree_sitter_memory_owner_begin(memory_owner)
	defer odra_tree_sitter_memory_owner_end()
	state, allocation_error := new(Tree_Sitter_Owner_State, allocator)
	if allocation_error != nil {
		_ = odra_tree_sitter_memory_owner_close(memory_owner)
		if dynamic_library != nil do _ = dynlib.unload_library(dynamic_library)
		return false, tree_sitter_failure(.Initialize, .Allocation)
	}
	state^ = Tree_Sitter_Owner_State {
		language = language,
		lifecycle = .Uninitialized,
		parser_generation = parser_generation,
		memory_owner = memory_owner,
		allocator = allocator,
		dynamic_library = dynamic_library,
	}

	state.parser = ts_parser_new()
	if state.parser == nil || !ts_parser_set_language(state.parser, state.language) {
		tree_sitter_state_release(state)
		return false, tree_sitter_failure(.Initialize, .Parser_Initialization)
	}
	state.cursor = ts_query_cursor_new()
	if state.cursor == nil {
		tree_sitter_state_release(state)
		return false, tree_sitter_failure(.Initialize, .Allocation)
	}
	state.lifecycle = .Ready
	owner.state = state
	return true, {}
}

/* tree_sitter_owner_compile_query atomically replaces one validated query. */
tree_sitter_owner_compile_query :: proc(
	owner: ^Tree_Sitter_Owner,
	source: []u8,
	generation: Query_Generation,
) -> (ok: bool, failure: Failure) {
	state := tree_sitter_owner_state(owner)
	if state == nil {
		return false, tree_sitter_failure(.Initialize, .Parser_Initialization)
	}
	if len(source) == 0 {
		return false, tree_sitter_failure(.Initialize, .Invalid_Query)
	}
	if u64(len(source)) > MAX_QUERY_BYTES || u64(len(source)) > u64(max(u32)) {
		failure = tree_sitter_failure(.Initialize, .Query_Limit)
		failure.limit = MAX_QUERY_BYTES
		failure.actual = u64(len(source))
		return false, failure
	}
	if generation == Query_Generation(0) ||
	   generation <= state.query_generation {
		return false, tree_sitter_failure(.Initialize, .Generation_Limit)
	}

	tree_sitter_memory_begin(state)
	defer tree_sitter_memory_end()
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
		failure = tree_sitter_failure(.Initialize, .Invalid_Query)
		failure.limit = u64(error_type)
		failure.actual = u64(error_offset)
		return false, failure
	}
	if mapped, invalid_index := tree_sitter_query_validate_capture_mapping(candidate); !mapped {
		ts_query_delete(candidate)
		failure = tree_sitter_failure(.Initialize, .Invalid_Capture_Mapping)
		failure.actual = u64(invalid_index)
		return false, failure
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
	state.provider_query_count = 0
	state.provider_capture_mappings = {}
	state.provider_capture_mapping_count = 0
	if state.query != nil do ts_query_delete(state.query)
	state.query = candidate
	state.query_generation = generation
	state.query_bytes = u64(len(source))
	state.query_captures = ts_query_capture_count(candidate)
	return true, {}
}

/* tree_sitter_owner_prepare_progress starts one bounded parse-progress window. */
tree_sitter_owner_prepare_progress :: proc(
	owner: ^Tree_Sitter_Owner,
	work_limit_bytes: u64,
) -> (options: Tree_Sitter_Parse_Options, ok: bool, failure: Failure) {
	state := tree_sitter_owner_state(owner)
	if state == nil {
		return {}, false, tree_sitter_failure(.Schedule, .Parser_Initialization)
	}
	if work_limit_bytes == 0 || work_limit_bytes > MAX_ANALYZED_SOURCE_BYTES {
		failure = tree_sitter_failure(.Schedule, .Work_Limit)
		failure.limit = MAX_ANALYZED_SOURCE_BYTES
		failure.actual = work_limit_bytes
		return {}, false, failure
	}
	cancel_requested := state.progress.cancel_requested
	state.progress = Tree_Sitter_Progress {
		cancel_requested = cancel_requested,
		work_limit_bytes = work_limit_bytes,
	}
	return Tree_Sitter_Parse_Options {
		payload = &state.progress,
		progress_callback = tree_sitter_progress_callback,
	}, true, {}
}

/* tree_sitter_owner_request_cancel marks the active progress window cancelled. */
tree_sitter_owner_request_cancel :: proc(
	owner: ^Tree_Sitter_Owner,
) -> (ok: bool, failure: Failure) {
	state := tree_sitter_owner_state(owner)
	if state == nil {
		return false, tree_sitter_failure(.Cancel, .Parser_Initialization)
	}
	state.progress.cancel_requested = true
	return true, {}
}

/* tree_sitter_owner_clear_cancel admits later work after cancellation handling. */
tree_sitter_owner_clear_cancel :: proc(
	owner: ^Tree_Sitter_Owner,
) -> (ok: bool, failure: Failure) {
	state := tree_sitter_owner_state(owner)
	if state == nil {
		return false, tree_sitter_failure(.Cancel, .Parser_Initialization)
	}
	state.progress.cancel_requested = false
	return true, {}
}

/* tree_sitter_owner_stats copies owned lifecycle and progress state. */
tree_sitter_owner_stats :: proc(
	owner: ^Tree_Sitter_Owner,
) -> (stats: Tree_Sitter_Owner_Stats, ok: bool, failure: Failure) {
	state := tree_sitter_owner_state(owner)
	if state == nil {
		return {}, false, tree_sitter_failure(.Inspect, .Parser_Initialization)
	}
	return Tree_Sitter_Owner_Stats {
		lifecycle = state.lifecycle,
		parser_generation = state.parser_generation,
		tree_generation = state.tree_generation,
		query_generation = state.query_generation,
		grammar_abi = ts_language_abi_version(state.language),
		query_bytes = state.query_bytes,
		query_captures = state.query_captures,
		has_tree = state.tree != nil,
		has_query = state.query != nil,
		has_cursor = state.cursor != nil,
		cancel_requested = state.progress.cancel_requested,
		progress_checks = state.progress.checks,
		current_byte_offset = state.progress.current_byte_offset,
		work_limit_bytes = state.progress.work_limit_bytes,
		confirmed_buffer_id = state.confirmed.buffer_id,
		confirmed_revision = state.confirmed.source_revision,
		selection_generation = state.confirmed.selection_generation,
		pending = state.pending,
		foreign_live_bytes = odra_tree_sitter_memory_owner_live_bytes(state.memory_owner),
		foreign_peak_bytes = odra_tree_sitter_memory_owner_peak_bytes(state.memory_owner),
		foreign_allocations = odra_tree_sitter_memory_owner_allocations(state.memory_owner),
		foreign_frees = odra_tree_sitter_memory_owner_frees(state.memory_owner),
	}, true, {}
}

/* tree_sitter_owner_close releases cursor, query, tree, parser, and owner state. */
tree_sitter_owner_close :: proc(
	owner: ^Tree_Sitter_Owner,
) -> (ok: bool, failure: Failure) {
	state := tree_sitter_owner_state(owner)
	if state == nil {
		return false, tree_sitter_failure(.Close, .Parser_Initialization)
	}
	state.lifecycle = .Closed
	unloaded := tree_sitter_state_release(state)
	owner^ = Tree_Sitter_Owner {closed = true}
	if !unloaded do return false, tree_sitter_failure(.Close, .Library_Unload_Failed)
	return true, {}
}

@(private)
tree_sitter_owner_state :: proc(owner: ^Tree_Sitter_Owner) -> ^Tree_Sitter_Owner_State {
	if owner == nil || owner.state == nil || owner.closed do return nil
	return cast(^Tree_Sitter_Owner_State)owner.state
}

@(private)
tree_sitter_progress_callback :: proc "c" (foreign_state: ^Tree_Sitter_Parse_State) -> bool {
	if foreign_state == nil || foreign_state.payload == nil do return true
	progress := cast(^Tree_Sitter_Progress)foreign_state.payload
	progress.checks += 1
	progress.current_byte_offset = foreign_state.current_byte_offset
	return progress.cancel_requested ||
		u64(foreign_state.current_byte_offset) >= progress.work_limit_bytes
}

@(private)
tree_sitter_owner_replace_tree :: proc(
	owner: ^Tree_Sitter_Owner,
	candidate: rawptr,
	generation: Tree_Generation,
) -> bool {
	state := tree_sitter_owner_state(owner)
	if state == nil || candidate == nil || generation == Tree_Generation(0) ||
	   generation <= state.tree_generation {
		if candidate != nil do ts_tree_delete(candidate)
		return false
	}
	if state.tree != nil do ts_tree_delete(state.tree)
	state.tree = candidate
	state.tree_generation = generation
	return true
}

@(private)
tree_sitter_state_release :: proc(state: ^Tree_Sitter_Owner_State) -> bool {
	if state == nil do return true
	tree_sitter_memory_begin(state)
	if state.cursor != nil do ts_query_cursor_delete(state.cursor)
	for query in state.provider_queries[:state.provider_query_count] {
		if query != nil {
			if query == state.query do state.query = nil
			ts_query_delete(query)
		}
	}
	if state.query != nil do ts_query_delete(state.query)
	if state.tree != nil do ts_tree_delete(state.tree)
	if state.parser != nil do ts_parser_delete(state.parser)
	tree_sitter_memory_end()
	closed := odra_tree_sitter_memory_owner_close(state.memory_owner)
	assert(closed, "Tree-sitter foreign allocations remain after owner cleanup")
	library := state.dynamic_library
	allocator := state.allocator
	state^ = {}
	free(state, allocator)
	return library == nil || dynlib.unload_library(library)
}

@(private)
tree_sitter_memory_begin :: proc(state: ^Tree_Sitter_Owner_State) {
	if state != nil do odra_tree_sitter_memory_owner_begin(state.memory_owner)
}

@(private)
tree_sitter_memory_end :: proc() {
	odra_tree_sitter_memory_owner_end()
}

@(private)
tree_sitter_failure :: proc(operation: Operation, code: Failure_Code) -> Failure {
	return Failure {operation = operation, code = code}
}
