// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language

@(private)
ODRA_TREE_SITTER_LIBRARY :: #config(
	ODRA_TREE_SITTER_LIBRARY,
	"../../.build/syntax-vendor/libtree-sitter-odin.a",
)

foreign import tree_sitter_runtime {ODRA_TREE_SITTER_LIBRARY}

/* tree_sitter_factory_language resolves a statically packaged grammar by bundle identity. */
tree_sitter_factory_language :: proc(bundle_identity: string) -> rawptr {
	if len(bundle_identity) == 0 do return nil
	return odra_tree_sitter_factory_language(raw_data(bundle_identity), uintptr(len(bundle_identity)))
}

@(private)
Tree_Sitter_Query_Error :: enum i32 {
	None = 0,
	Syntax,
	Node_Type,
	Field,
	Capture,
	Structure,
	Language,
}

@(private)
Tree_Sitter_Parse_State :: struct {
	payload:            rawptr,
	current_byte_offset: u32,
	has_error:          bool,
}

@(private)
Tree_Sitter_Progress_Callback :: proc "c" (state: ^Tree_Sitter_Parse_State) -> bool

@(private)
Tree_Sitter_Parse_Options :: struct {
	payload:           rawptr,
	progress_callback: Tree_Sitter_Progress_Callback,
}

@(private)
Tree_Sitter_Point :: struct {
	row:    u32,
	column: u32,
}

@(private)
Tree_Sitter_Input_Encoding :: enum i32 {
	UTF8 = 0,
	UTF16_LE,
	UTF16_BE,
	Custom,
}

@(private)
Tree_Sitter_Input_Read_Callback :: proc "c" (
	payload: rawptr,
	byte_index: u32,
	position: Tree_Sitter_Point,
	bytes_read: ^u32,
) -> ^u8

@(private)
Tree_Sitter_Input :: struct {
	payload: rawptr,
	read:     Tree_Sitter_Input_Read_Callback,
	encoding: Tree_Sitter_Input_Encoding,
	decode:   rawptr,
}

@(private)
Tree_Sitter_Input_Edit :: struct {
	start_byte:    u32,
	old_end_byte:  u32,
	new_end_byte:  u32,
	start_point:   Tree_Sitter_Point,
	old_end_point: Tree_Sitter_Point,
	new_end_point: Tree_Sitter_Point,
}

@(private)
Tree_Sitter_Node :: struct {
	ctx:     [4]u32,
	id:      rawptr,
	tree:    rawptr,
}

@(private)
Tree_Sitter_Query_Capture :: struct {
	node:  Tree_Sitter_Node,
	index: u32,
}

@(private)
Tree_Sitter_Query_Match :: struct {
	id:            u32,
	pattern_index: u16,
	capture_count: u16,
	captures:      [^]Tree_Sitter_Query_Capture,
}

@(private)
Tree_Sitter_Query_Predicate_Step_Type :: enum i32 {
	Done = 0,
	Capture,
	String,
}

@(private)
Tree_Sitter_Query_Predicate_Step :: struct {
	type:     Tree_Sitter_Query_Predicate_Step_Type,
	value_id: u32,
}

@(private, default_calling_convention="c")
foreign tree_sitter_runtime {
	odra_tree_sitter_memory_install :: proc() ---
	odra_tree_sitter_memory_owner_open :: proc() -> u32 ---
	odra_tree_sitter_memory_owner_begin :: proc(owner: u32) ---
	odra_tree_sitter_memory_owner_end :: proc() ---
	odra_tree_sitter_memory_owner_live_bytes :: proc(owner: u32) -> u64 ---
	odra_tree_sitter_memory_owner_peak_bytes :: proc(owner: u32) -> u64 ---
	odra_tree_sitter_memory_owner_allocations :: proc(owner: u32) -> u64 ---
	odra_tree_sitter_memory_owner_frees :: proc(owner: u32) -> u64 ---
	odra_tree_sitter_memory_owner_close :: proc(owner: u32) -> bool ---
	odra_tree_sitter_factory_language :: proc(identity: [^]u8, length: uintptr) -> rawptr ---
	ts_language_abi_version :: proc(language: rawptr) -> u32 ---
	ts_parser_new :: proc() -> rawptr ---
	ts_parser_delete :: proc(parser: rawptr) ---
	ts_parser_set_language :: proc(parser, language: rawptr) -> bool ---
	ts_parser_parse_with_options :: proc(
		parser, old_tree: rawptr,
		input: Tree_Sitter_Input,
		options: Tree_Sitter_Parse_Options,
	) -> rawptr ---
	ts_parser_parse_string :: proc(
		parser, old_tree: rawptr,
		text: [^]u8,
		length: u32,
	) -> rawptr ---
	ts_parser_reset :: proc(parser: rawptr) ---
	ts_tree_copy :: proc(tree: rawptr) -> rawptr ---
	ts_tree_delete :: proc(tree: rawptr) ---
	ts_tree_edit :: proc(tree: rawptr, edit: ^Tree_Sitter_Input_Edit) ---
	ts_tree_root_node :: proc(tree: rawptr) -> Tree_Sitter_Node ---
	ts_node_is_null :: proc(node: Tree_Sitter_Node) -> bool ---
	ts_node_parent :: proc(node: Tree_Sitter_Node) -> Tree_Sitter_Node ---
	ts_node_is_named :: proc(node: Tree_Sitter_Node) -> bool ---
	ts_node_is_error :: proc(node: Tree_Sitter_Node) -> bool ---
	ts_node_is_missing :: proc(node: Tree_Sitter_Node) -> bool ---
	ts_node_has_error :: proc(node: Tree_Sitter_Node) -> bool ---
	ts_node_child_count :: proc(node: Tree_Sitter_Node) -> u32 ---
	ts_node_child :: proc(node: Tree_Sitter_Node, index: u32) -> Tree_Sitter_Node ---
	ts_node_named_child_count :: proc(node: Tree_Sitter_Node) -> u32 ---
	ts_node_named_child :: proc(node: Tree_Sitter_Node, index: u32) -> Tree_Sitter_Node ---
	ts_node_next_named_sibling :: proc(node: Tree_Sitter_Node) -> Tree_Sitter_Node ---
	ts_node_prev_named_sibling :: proc(node: Tree_Sitter_Node) -> Tree_Sitter_Node ---
	ts_node_type :: proc(node: Tree_Sitter_Node) -> cstring ---
	ts_node_start_byte :: proc(node: Tree_Sitter_Node) -> u32 ---
	ts_node_end_byte :: proc(node: Tree_Sitter_Node) -> u32 ---
	ts_query_new :: proc(
		language: rawptr,
		source: ^u8,
		source_length: u32,
		error_offset: ^u32,
		error_type: ^Tree_Sitter_Query_Error,
	) -> rawptr ---
	ts_query_delete :: proc(query: rawptr) ---
	ts_query_capture_count :: proc(query: rawptr) -> u32 ---
	ts_query_pattern_count :: proc(query: rawptr) -> u32 ---
	ts_query_capture_name_for_id :: proc(query: rawptr, index: u32, length: ^u32) -> ^u8 ---
	ts_query_disable_capture :: proc(query: rawptr, name: ^u8, length: u32) ---
	ts_query_predicates_for_pattern :: proc(
		query: rawptr,
		pattern_index: u32,
		step_count: ^u32,
	) -> [^]Tree_Sitter_Query_Predicate_Step ---
	ts_query_string_value_for_id :: proc(query: rawptr, index: u32, length: ^u32) -> ^u8 ---
	ts_query_cursor_new :: proc() -> rawptr ---
	ts_query_cursor_delete :: proc(cursor: rawptr) ---
	ts_query_cursor_exec :: proc(cursor, query: rawptr, node: Tree_Sitter_Node) ---
	ts_query_cursor_set_match_limit :: proc(cursor: rawptr, limit: u32) ---
	ts_query_cursor_did_exceed_match_limit :: proc(cursor: rawptr) -> bool ---
	ts_query_cursor_set_byte_range :: proc(cursor: rawptr, start, end: u32) -> bool ---
	ts_query_cursor_next_capture :: proc(
		cursor: rawptr,
		match: ^Tree_Sitter_Query_Match,
		capture_index: ^u32,
	) -> bool ---
}
