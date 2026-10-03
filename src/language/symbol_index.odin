// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language

import "../document"
import "../editor"
import "base:runtime"
import "core:unicode"
import "core:unicode/utf8"

@(private)
Symbol_Index_Entry :: struct {
	id:              Symbol_ID,
	parent_id:       Symbol_ID,
	hierarchy_depth: u16,
	start:           editor.Byte_Offset,
	end:             editor.Byte_Offset,
	name_start:      u32,
	name_bytes:      u16,
	kind:            Symbol_Kind,
}

@(private)
Symbol_Index_State :: struct {
	descriptor: Symbol_Result_Descriptor,
	entries:    [dynamic]Symbol_Index_Entry,
	text:       [dynamic]u8,
	allocator:  runtime.Allocator,
}

@(private)
Symbol_Tree_Frame :: struct {
	node:            Tree_Sitter_Node,
	parent_symbol:   Symbol_ID,
	hierarchy_depth: u16,
}

/* tree_sitter_owner_symbol_index extracts one exact maintained Odin generation. */
tree_sitter_owner_symbol_index :: proc(
	owner: ^Tree_Sitter_Owner,
	source: ^editor.Buffer_Snapshot,
	scope: Symbol_Query_Scope,
	result_generation: Symbol_Result_Generation,
	limits := DEFAULT_SYMBOL_LIMITS,
	allocator := context.allocator,
) -> (index: Symbol_Index, ok: bool, failure: Failure) {
	state := tree_sitter_owner_state(owner)
	source_bytes, valid, validation_failure := symbol_tree_query_validate(
		state,
		source,
		scope,
		result_generation,
		limits,
	)
	if !valid do return {}, false, validation_failure
	index_state, initialized, init_failure := symbol_index_state_init(
		scope,
		result_generation,
		limits,
		allocator,
	)
	if !initialized do return {}, false, init_failure

	stack, stack_error := make([dynamic]Symbol_Tree_Frame, 0, 256, allocator)
	if stack_error != nil {
		symbol_index_state_close(index_state)
		return {}, false, symbol_failure(scope, .Allocation)
	}
	defer delete(stack)
	root := ts_tree_root_node(state.tree)
	if ts_node_is_null(root) {
		symbol_index_state_close(index_state)
		return {}, false, symbol_failure(scope, .Symbol_Capability_Unavailable)
	}
	_, append_error := append(&stack, Symbol_Tree_Frame{node = root})
	if append_error != nil {
		symbol_index_state_close(index_state)
		return {}, false, symbol_failure(scope, .Allocation)
	}

	for len(stack) > 0 {
		frame := pop(&stack)
		index_state.descriptor.usage.work_items += 1
		if state.progress.cancel_requested {
			symbol_index_state_close(index_state)
			return {}, false, symbol_failure(scope, .Cancelled)
		}
		if index_state.descriptor.usage.work_items > limits.work_items {
			index_state.descriptor.completeness = .Incomplete
			break
		}

		parent_symbol := frame.parent_symbol
		child_depth := frame.hierarchy_depth
		kind, declaration := odin_symbol_node_kind(frame.node)
		if declaration {
			name_node, named := odin_symbol_name_node(frame.node)
			if named {
				entry, admitted, admit_failure := symbol_index_admit_node(
					index_state,
					source,
					name_node,
					kind,
					frame.parent_symbol,
					frame.hierarchy_depth,
					limits,
					source_bytes,
				)
				if admit_failure.code != .None {
					symbol_index_state_close(index_state)
					return {}, false, admit_failure
				}
				if admitted {
					parent_symbol = entry.id
					if frame.hierarchy_depth < limits.hierarchy_depth {
						child_depth = frame.hierarchy_depth + 1
					} else {
						index_state.descriptor.completeness = .Incomplete
					}
				}
			}
		}

		child_count := ts_node_named_child_count(frame.node)
		for reverse_index in 0 ..< child_count {
			child_index := child_count - reverse_index - 1
			child := ts_node_named_child(frame.node, child_index)
			if ts_node_is_null(child) do continue
			_, child_error := append(&stack, Symbol_Tree_Frame {
				node = child,
				parent_symbol = parent_symbol,
				hierarchy_depth = child_depth,
			})
			if child_error != nil {
				symbol_index_state_close(index_state)
				return {}, false, symbol_failure(scope, .Allocation)
			}
		}
	}
	index_state.descriptor.usage.symbols = u32(len(index_state.entries))
	index_state.descriptor.usage.retained_bytes = symbol_index_retained_bytes(index_state)
	index_state.descriptor.usage.temporary_bytes = u64(cap(stack)) * u64(size_of(Symbol_Tree_Frame))
	if index_state.descriptor.usage.retained_bytes > limits.retained_bytes {
		failure = symbol_failure(scope, .Symbol_Memory_Limit)
		failure.limit = limits.retained_bytes
		failure.actual = index_state.descriptor.usage.retained_bytes
		symbol_index_state_close(index_state)
		return {}, false, failure
	}
	return Symbol_Index{state = index_state}, true, {}
}

/* tree_sitter_owner_symbol_at_point resolves one exact syntax-tree identifier. */
tree_sitter_owner_symbol_at_point :: proc(
	owner: ^Tree_Sitter_Owner,
	source: ^editor.Buffer_Snapshot,
	scope: Symbol_Query_Scope,
	point: editor.Byte_Offset,
) -> (symbol: Generic_Symbol, ok: bool, failure: Failure) {
	state := tree_sitter_owner_state(owner)
	source_bytes, valid, validation_failure := symbol_tree_query_validate(
		state,
		source,
		scope,
		1,
		DEFAULT_SYMBOL_LIMITS,
	)
	if !valid do return {}, false, validation_failure
	if u64(point) > source_bytes ||
	   !structural_snapshot_boundary(source, u64(point), source_bytes) {
		return {}, false, symbol_failure(scope, .Invalid_UTF8_Boundary)
	}
	root := ts_tree_root_node(state.tree)
	usage: Structural_Usage
	node, found, target_failure := structural_deepest_named(
		state,
		root,
		u32(point),
		u32(point),
		&usage,
	)
	if !found {
		failure = symbol_failure(scope, target_failure.code)
		if failure.code == .No_Structural_Target do failure.code = .No_Symbol
		return {}, false, failure
	}
	pointer := ts_node_type(node)
	if pointer == nil || string(pointer) != "identifier" {
		return {}, false, symbol_failure(scope, .No_Symbol)
	}
	start := ts_node_start_byte(node)
	end := ts_node_end_byte(node)
	if start >= end || u64(end) > source_bytes {
		return {}, false, symbol_failure(scope, .Invalid_UTF8_Boundary)
	}
	name_bytes := int(end - start)
	if name_bytes > MAX_SYMBOL_NAME_BYTES {
		failure = symbol_failure(scope, .Symbol_Name_Limit)
		failure.limit = MAX_SYMBOL_NAME_BYTES
		failure.actual = u64(name_bytes)
		return {}, false, failure
	}
	name: Symbol_Name
	copied, read_ok, _ := editor.buffer_snapshot_read(
		source,
		editor.Byte_Offset(start),
		name.bytes[:name_bytes],
	)
	if !read_ok || copied != u64(name_bytes) {
		return {}, false, symbol_failure(scope, .Unavailable_Base_Snapshot)
	}
	name.length = u16(name_bytes)
	return Generic_Symbol {
		location = Symbol_Range {
			buffer_id = scope.buffer_id,
			document_id = scope.document_id,
			has_document = scope.has_document,
			source_revision = scope.source_revision,
			start = editor.Byte_Offset(start),
			end = editor.Byte_Offset(end),
		},
		name = name,
	}, true, {}
}

/* generic_symbol_at_point resolves a Unicode symbol without language evidence. */
generic_symbol_at_point :: proc(
	source: ^editor.Buffer_Snapshot,
	document_id: document.Document_ID,
	has_document: bool,
	point: editor.Byte_Offset,
) -> (symbol: Generic_Symbol, ok: bool, failure: Failure) {
	stats, inspected, _ := editor.buffer_snapshot_stats(source)
	if !inspected || u64(point) > stats.text_bytes ||
	   has_document != (document_id != document.Document_ID(0)) {
		return {}, false, Failure{operation = .Query_Symbols, code = .Invalid_Symbol_Query}
	}
	if !structural_snapshot_boundary(source, u64(point), stats.text_bytes) {
		return {}, false, Failure{operation = .Query_Symbols, code = .Invalid_UTF8_Boundary}
	}
	window_radius := u64(MAX_SYMBOL_NAME_BYTES + 4)
	window_start := u64(0)
	if u64(point) > window_radius do window_start = u64(point) - window_radius
	window_end := min(stats.text_bytes, u64(point) + window_radius)
	for window_start > 0 && !structural_snapshot_boundary(source, window_start, stats.text_bytes) {
		window_start += 1
	}
	window: [MAX_SYMBOL_NAME_BYTES * 2 + 8]u8
	window_bytes := int(window_end - window_start)
	copied, read_ok, _ := editor.buffer_snapshot_read(
		source,
		editor.Byte_Offset(window_start),
		window[:window_bytes],
	)
	if !read_ok || copied != u64(window_bytes) {
		return {}, false, Failure{operation = .Query_Symbols, code = .Unavailable_Base_Snapshot}
	}
	text := window[:window_bytes]
	local_point := int(u64(point) - window_start)
	seed_start, seed_end, found := generic_symbol_seed(text, local_point)
	if !found {
		return {}, false, Failure{operation = .Query_Symbols, code = .No_Symbol}
	}
	start := seed_start
	for start > 0 {
		value, width := utf8.decode_last_rune(text[:start])
		if width <= 0 || !generic_symbol_rune(value) do break
		start -= width
	}
	end := seed_end
	for end < len(text) {
		value, width := utf8.decode_rune(text[end:])
		if width <= 0 || !generic_symbol_rune(value) do break
		end += width
	}
	name_bytes := end - start
	if name_bytes > MAX_SYMBOL_NAME_BYTES ||
	   start == 0 && window_start > 0 || end == len(text) && window_end < stats.text_bytes {
		failure = Failure{operation = .Query_Symbols, code = .Symbol_Name_Limit}
		failure.limit = MAX_SYMBOL_NAME_BYTES
		failure.actual = u64(name_bytes)
		return {}, false, failure
	}
	name: Symbol_Name
	name.length = u16(copy(name.bytes[:], text[start:end]))
	return Generic_Symbol {
		location = Symbol_Range {
			buffer_id = stats.buffer_id,
			document_id = document_id,
			has_document = has_document,
			source_revision = stats.revision,
			start = editor.Byte_Offset(window_start + u64(start)),
			end = editor.Byte_Offset(window_start + u64(end)),
		},
		name = name,
	}, true, {}
}

/* generic_symbol_index extracts bounded Unicode symbol tokens without language analysis. */
generic_symbol_index :: proc(
	source: ^editor.Buffer_Snapshot,
	document_id: document.Document_ID,
	has_document: bool,
	request_generation: Symbol_Request_Generation,
	result_generation: Symbol_Result_Generation,
	limits := DEFAULT_SYMBOL_LIMITS,
	allocator := context.allocator,
) -> (index: Symbol_Index, ok: bool, failure: Failure) {
	stats, inspected, _ := editor.buffer_snapshot_stats(source)
	if !inspected || has_document != (document_id != document.Document_ID(0)) ||
	   request_generation == Symbol_Request_Generation(0) ||
	   result_generation == Symbol_Result_Generation(0) ||
	   !symbol_limits_are_valid(limits) {
		return {}, false, Failure{operation = .Query_Symbols, code = .Invalid_Symbol_Query}
	}
	scope := generic_symbol_scope(
		stats.buffer_id,
		document_id,
		has_document,
		stats.revision,
		request_generation,
	)
	if stats.text_bytes > limits.temporary_bytes {
		return {}, false, Failure {
			operation = .Query_Symbols,
			code = .Symbol_Memory_Limit,
			limit = limits.temporary_bytes,
			actual = stats.text_bytes,
		}
	}
	state, initialized, init_failure := symbol_index_state_init(
		scope,
		result_generation,
		limits,
		allocator,
	)
	if !initialized do return {}, false, init_failure
	text, text_error := make([]u8, int(stats.text_bytes), allocator)
	if text_error != nil {
		symbol_index_state_close(state)
		return {}, false, symbol_failure(scope, .Allocation)
	}
	defer delete(text, allocator)
	if stats.text_bytes > 0 {
		copied, read_ok, _ := editor.buffer_snapshot_read(source, 0, text)
		if !read_ok || copied != stats.text_bytes {
			symbol_index_state_close(state)
			return {}, false, symbol_failure(scope, .Unavailable_Base_Snapshot)
		}
	}
	state.descriptor.usage.temporary_bytes = stats.text_bytes
	cursor := 0
	for cursor < len(text) {
		state.descriptor.usage.work_items += 1
		if state.descriptor.usage.work_items > limits.work_items {
			state.descriptor.completeness = .Incomplete
			break
		}
		value, width := utf8.decode_rune(text[cursor:])
		if width <= 0 {
			symbol_index_state_close(state)
			return {}, false, symbol_failure(scope, .Invalid_UTF8_Boundary)
		}
		if !generic_symbol_rune(value) {
			cursor += width
			continue
		}
		start := cursor
		cursor += width
		for cursor < len(text) {
			value, width = utf8.decode_rune(text[cursor:])
			if width <= 0 || !generic_symbol_rune(value) do break
			cursor += width
			state.descriptor.usage.work_items += 1
			if state.descriptor.usage.work_items > limits.work_items do break
		}
		name_bytes := cursor - start
		if name_bytes == 0 do continue
		if len(state.entries) >= int(limits.symbols) {
			state.descriptor.completeness = .Incomplete
			break
		}
		if name_bytes > int(limits.name_bytes) {
			state.descriptor.completeness = .Incomplete
			continue
		}
		name_start := len(state.text)
		for byte in text[start:cursor] {
			if _, append_error := append(&state.text, byte); append_error != nil {
				symbol_index_state_close(state)
				return {}, false, symbol_failure(scope, .Allocation)
			}
		}
		entry := Symbol_Index_Entry {
			id = Symbol_ID(len(state.entries) + 1),
			start = editor.Byte_Offset(start),
			end = editor.Byte_Offset(cursor),
			name_start = u32(name_start),
			name_bytes = u16(name_bytes),
			kind = .Variable,
		}
		if _, append_error := append(&state.entries, entry); append_error != nil {
			symbol_index_state_close(state)
			return {}, false, symbol_failure(scope, .Allocation)
		}
		if symbol_index_retained_bytes(state) > limits.retained_bytes {
			ordered_remove(&state.entries, len(state.entries) - 1)
			_ = resize(&state.text, name_start)
			state.descriptor.completeness = .Incomplete
			break
		}
	}
	state.descriptor.usage.symbols = u32(len(state.entries))
	state.descriptor.usage.retained_bytes = symbol_index_retained_bytes(state)
	return Symbol_Index{state = state}, true, {}
}

/* symbol_index_view copies immutable generation metadata. */
symbol_index_view :: proc(index: ^Symbol_Index) -> (view: Symbol_Index_View, ok: bool, failure: Failure) {
	state := symbol_index_state(index)
	if state == nil do return {}, false, Failure{operation = .Inspect_Symbols, code = .Invalid_Symbol_Query}
	return Symbol_Index_View{descriptor = state.descriptor, symbols = u32(len(state.entries))}, true, {}
}

/* symbol_index_descriptor copies one admitted symbol by stable order. */
symbol_index_descriptor :: proc(
	index: ^Symbol_Index,
	ordinal: u32,
) -> (descriptor: Symbol_Descriptor, ok: bool, failure: Failure) {
	state := symbol_index_state(index)
	if state == nil || ordinal >= u32(len(state.entries)) {
		return {}, false, Failure{operation = .Inspect_Symbols, code = .Invalid_Symbol_Query}
	}
	entry := &state.entries[ordinal]
	name: Symbol_Name
	name.length = entry.name_bytes
	copy(name.bytes[:], state.text[entry.name_start:entry.name_start + u32(entry.name_bytes)])
	container: Symbol_Container
	if entry.parent_id != Symbol_ID(0) {
		parent_index := int(u64(entry.parent_id) - 1)
		if parent_index >= 0 && parent_index < len(state.entries) {
			parent := &state.entries[parent_index]
			container.length = min(parent.name_bytes, u16(MAX_SYMBOL_CONTAINER_BYTES))
			copy(container.bytes[:], state.text[parent.name_start:parent.name_start + u32(container.length)])
		}
	}
	return Symbol_Descriptor {
		id = entry.id,
		parent_id = entry.parent_id,
		hierarchy_depth = entry.hierarchy_depth,
		provider = state.descriptor.scope.provider,
		result_generation = state.descriptor.generation,
		location = Symbol_Range {
			buffer_id = state.descriptor.scope.buffer_id,
			document_id = state.descriptor.scope.document_id,
			has_document = state.descriptor.scope.has_document,
			source_revision = state.descriptor.scope.source_revision,
			start = entry.start,
			end = entry.end,
		},
		name = name,
		kind = entry.kind,
		container = container,
	}, true, {}
}

/* symbol_index_close releases one immutable generation exactly once. */
symbol_index_close :: proc(index: ^Symbol_Index) {
	state := symbol_index_state(index)
	if state == nil do return
	symbol_index_state_close(state)
	index^ = {}
}

@(private)
symbol_tree_query_validate :: proc(
	state: ^Tree_Sitter_Owner_State,
	source: ^editor.Buffer_Snapshot,
	scope: Symbol_Query_Scope,
	result_generation: Symbol_Result_Generation,
	limits: Symbol_Limits,
) -> (source_bytes: u64, ok: bool, failure: Failure) {
	if state == nil || source == nil || state.tree == nil || state.confirmed.status != .Current ||
	   !symbol_query_scope_is_valid(scope) || !symbol_limits_are_valid(limits) ||
	   result_generation == Symbol_Result_Generation(0) {
		return 0, false, symbol_failure(scope, .Invalid_Symbol_Query)
	}
	stats, inspected, _ := editor.buffer_snapshot_stats(source)
	if !inspected do return 0, false, symbol_failure(scope, .Unavailable_Base_Snapshot)
	source_bytes = stats.text_bytes
	if stats.buffer_id != scope.buffer_id || stats.revision != scope.source_revision ||
	   state.confirmed.buffer_id != scope.buffer_id ||
	   state.confirmed.source_revision != scope.source_revision ||
	   state.confirmed.language != scope.language || state.confirmed.provider != scope.provider ||
	   state.confirmed.selection_generation != scope.selection_generation {
		return source_bytes, false, symbol_failure(scope, .Stale_Selection)
	}
	if state.progress.cancel_requested do return source_bytes, false, symbol_failure(scope, .Cancelled)
	return source_bytes, true, {}
}

@(private)
symbol_index_state_init :: proc(
	scope: Symbol_Query_Scope,
	generation: Symbol_Result_Generation,
	limits: Symbol_Limits,
	allocator: runtime.Allocator,
) -> (^Symbol_Index_State, bool, Failure) {
	if allocator.procedure == nil do return nil, false, symbol_failure(scope, .Allocation)
	state, state_error := new(Symbol_Index_State, allocator)
	if state_error != nil do return nil, false, symbol_failure(scope, .Allocation)
	state^ = Symbol_Index_State {
		descriptor = Symbol_Result_Descriptor {
			scope = scope,
			generation = generation,
			completeness = .Complete,
		},
		allocator = allocator,
	}
	entry_capacity := min(int(limits.symbols), 256)
	state.entries, state_error = make([dynamic]Symbol_Index_Entry, 0, entry_capacity, allocator)
	if state_error == nil {
		text_capacity := min(int(limits.retained_bytes / 4), 4 * 1_024)
		state.text, state_error = make([dynamic]u8, 0, text_capacity, allocator)
	}
	if state_error != nil {
		symbol_index_state_close(state)
		return nil, false, symbol_failure(scope, .Allocation)
	}
	return state, true, {}
}

@(private)
symbol_index_admit_node :: proc(
	state: ^Symbol_Index_State,
	source: ^editor.Buffer_Snapshot,
	node: Tree_Sitter_Node,
	kind: Symbol_Kind,
	parent_id: Symbol_ID,
	depth: u16,
	limits: Symbol_Limits,
	source_bytes: u64,
) -> (entry: Symbol_Index_Entry, admitted: bool, failure: Failure) {
	if len(state.entries) >= int(limits.symbols) {
		state.descriptor.completeness = .Incomplete
		return {}, false, {}
	}
	start := ts_node_start_byte(node)
	end := ts_node_end_byte(node)
	if start >= end || u64(end) > source_bytes do return {}, false, {}
	name_bytes := int(end - start)
	if name_bytes > int(limits.name_bytes) {
		state.descriptor.completeness = .Incomplete
		return {}, false, {}
	}
	name_start := len(state.text)
	for _ in 0 ..< name_bytes {
		if _, append_error := append(&state.text, u8(0)); append_error != nil {
			return {}, false, symbol_failure(state.descriptor.scope, .Allocation)
		}
	}
	copied, read_ok, _ := editor.buffer_snapshot_read(
		source,
		editor.Byte_Offset(start),
		state.text[name_start:name_start + name_bytes],
	)
	if !read_ok || copied != u64(name_bytes) {
		_ = resize(&state.text, name_start)
		return {}, false, symbol_failure(state.descriptor.scope, .Unavailable_Base_Snapshot)
	}
	entry = Symbol_Index_Entry {
		id = Symbol_ID(len(state.entries) + 1),
		parent_id = parent_id,
		hierarchy_depth = depth,
		start = editor.Byte_Offset(start),
		end = editor.Byte_Offset(end),
		name_start = u32(name_start),
		name_bytes = u16(name_bytes),
		kind = kind,
	}
	if _, append_error := append(&state.entries, entry); append_error != nil {
		_ = resize(&state.text, name_start)
		return {}, false, symbol_failure(state.descriptor.scope, .Allocation)
	}
	if symbol_index_retained_bytes(state) > limits.retained_bytes {
		ordered_remove(&state.entries, len(state.entries) - 1)
		_ = resize(&state.text, name_start)
		state.descriptor.completeness = .Incomplete
		return {}, false, {}
	}
	return entry, true, {}
}

@(private)
odin_symbol_node_kind :: proc(node: Tree_Sitter_Node) -> (kind: Symbol_Kind, declaration: bool) {
	pointer := ts_node_type(node)
	if pointer == nil do return .Invalid, false
	switch string(pointer) {
	case "package_declaration": return .Module, true
	case "procedure_declaration", "overloaded_procedure_declaration": return .Function, true
	case "struct_declaration": return .Struct, true
	case "enum_declaration": return .Enum, true
	case "union_declaration": return .Union, true
	case "bit_field_declaration", "const_type_declaration": return .Type, true
	case "const_declaration": return .Constant, true
	case "variable_declaration", "var_declaration": return .Variable, true
	case "assignment_statement": return .Variable, odin_assignment_declares(node)
	}
	return .Invalid, false
}

@(private)
odin_assignment_declares :: proc(node: Tree_Sitter_Node) -> bool {
	child_count := ts_node_child_count(node)
	for index in 0 ..< child_count {
		pointer := ts_node_type(ts_node_child(node, index))
		if pointer != nil && string(pointer) == ":=" do return true
	}
	return false
}

@(private)
odin_symbol_name_node :: proc(node: Tree_Sitter_Node) -> (Tree_Sitter_Node, bool) {
	child_count := ts_node_named_child_count(node)
	for index in 0 ..< child_count {
		child := ts_node_named_child(node, index)
		pointer := ts_node_type(child)
		if pointer == nil || string(pointer) == "attributes" do continue
		return odin_first_identifier(child)
	}
	return {}, false
}

@(private)
odin_first_identifier :: proc(node: Tree_Sitter_Node) -> (Tree_Sitter_Node, bool) {
	if ts_node_is_null(node) do return {}, false
	pointer := ts_node_type(node)
	if pointer != nil && string(pointer) == "identifier" do return node, true
	child_count := ts_node_named_child_count(node)
	for index in 0 ..< child_count {
		if result, found := odin_first_identifier(ts_node_named_child(node, index)); found {
			return result, true
		}
	}
	return {}, false
}

@(private)
generic_symbol_seed :: proc(text: []u8, point: int) -> (start, end: int, found: bool) {
	if point < len(text) {
		value, width := utf8.decode_rune(text[point:])
		if width > 0 && generic_symbol_rune(value) do return point, point + width, true
	}
	if point > 0 {
		value, width := utf8.decode_last_rune(text[:point])
		if width > 0 && generic_symbol_rune(value) do return point - width, point, true
	}
	return 0, 0, false
}

@(private)
generic_symbol_rune :: proc(value: rune) -> bool {
	return unicode.is_letter(value) || unicode.is_number(value) || value == '_'
}

@(private)
symbol_index_retained_bytes :: proc(state: ^Symbol_Index_State) -> u64 {
	if state == nil do return 0
	return u64(size_of(Symbol_Index_State)) +
		u64(cap(state.entries)) * u64(size_of(Symbol_Index_Entry)) + u64(cap(state.text))
}

@(private)
symbol_index_state :: proc(index: ^Symbol_Index) -> ^Symbol_Index_State {
	if index == nil || index.state == nil do return nil
	return cast(^Symbol_Index_State)index.state
}

@(private)
symbol_index_state_close :: proc(state: ^Symbol_Index_State) {
	if state == nil do return
	if state.entries != nil do delete(state.entries)
	if state.text != nil do delete(state.text)
	allocator := state.allocator
	free(state, allocator)
}

@(private)
symbol_failure :: proc(scope: Symbol_Query_Scope, code: Failure_Code) -> Failure {
	return Failure {
		operation = .Query_Symbols,
		code = code,
		language_id = scope.language.id,
		provider = scope.provider,
		selection_generation = scope.selection_generation,
		source_revision = scope.source_revision,
	}
}
