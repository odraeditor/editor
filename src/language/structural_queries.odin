// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language

import "../editor"

@(private)
STRUCTURAL_SCAN_BYTES :: 4 * KIBIBYTE

/* tree_sitter_owner_query_structure resolves one copied exact-tree target. */
tree_sitter_owner_query_structure :: proc(
	owner: ^Tree_Sitter_Owner,
	source: ^editor.Buffer_Snapshot,
	request: Structural_Request,
) -> (target: Structural_Target, usage: Structural_Usage, ok: bool, failure: Failure) {
	state, source_bytes, validated, validation_failure := structural_query_validate(
		owner,
		source,
		request,
	)
	if !validated do return {}, {}, false, validation_failure
	if request.operation == .Indent {
		return {}, {}, false, structural_failure(request, .Invalid_Transaction)
	}
	root := ts_tree_root_node(state.tree)
	if ts_node_is_null(root) {
		return {}, {}, false, structural_failure(request, .No_Structural_Target)
	}
	query_start := request.point
	query_end := request.point
	if request.has_region {
		query_start = request.start
		query_end = request.end
	}
	node, contained, containment_failure := structural_deepest_named(
		state,
		root,
		u32(query_start),
		u32(query_end),
		&usage,
	)
	if !contained do return {}, usage, false, structural_failure_from(request, containment_failure)

	switch request.operation {
	case .Forward:
		node = ts_node_next_named_sibling(node)
	case .Backward:
		node = ts_node_prev_named_sibling(node)
	case .Up:
		node = structural_named_parent(state, node, &usage)
	case .Down:
		node = structural_first_named_child(state, node, &usage)
	case .Select:
		if request.has_region && ts_node_start_byte(node) == u32(request.start) &&
		   ts_node_end_byte(node) == u32(request.end) {
			node = structural_named_parent(state, node, &usage)
		}
	case .Definition:
		node = structural_definition_node(state, root, node, &usage)
	case .Invalid, .Indent:
		return {}, usage, false, structural_failure(request, .Invalid_Transaction)
	}
	if state.progress.cancel_requested {
		return {}, usage, false, structural_failure(request, .Cancelled)
	}
	if ts_node_is_null(node) {
		return {}, usage, false, structural_failure(request, .No_Structural_Target)
	}
	return structural_copy_target(request.scope, node, source_bytes, &usage, request)
}

/* tree_sitter_owner_plan_indentation creates copied leading-whitespace edits. */
tree_sitter_owner_plan_indentation :: proc(
	owner: ^Tree_Sitter_Owner,
	source: ^editor.Buffer_Snapshot,
	request: Structural_Request,
	allocator := context.allocator,
) -> (plan: Structural_Indentation_Plan, ok: bool, failure: Failure) {
	state, source_bytes, validated, validation_failure := structural_query_validate(
		owner,
		source,
		request,
	)
	if !validated do return {}, false, validation_failure
	if request.operation != .Indent || allocator.procedure == nil {
		return {}, false, structural_failure(request, .Invalid_Transaction)
	}
	edits, allocation_error := make(
		[dynamic]Structural_Indent_Edit,
		0,
		min(256, MAX_STRUCTURAL_INDENT_LINES),
		allocator,
	)
	if allocation_error != nil do return {}, false, structural_failure(request, .Allocation)
	usage := Structural_Usage{temporary_bytes = u64(cap(edits)) * u64(size_of(Structural_Indent_Edit))}
	line_start, line_start_ok := structural_line_start(source, u64(request.start))
	if !request.has_region {
		line_start, line_start_ok = structural_line_start(source, u64(request.point))
	}
	if !line_start_ok {
		delete(edits)
		return {}, false, structural_failure(request, .Unavailable_Base_Snapshot)
	}
	requested_end := u64(request.end)
	if !request.has_region do requested_end = u64(request.point)
	if request.has_region && requested_end > line_start {
		end_line_start, end_line_ok := structural_line_start(source, requested_end)
		if !end_line_ok {
			delete(edits)
			return {}, false, structural_failure(request, .Unavailable_Base_Snapshot)
		}
		if requested_end == end_line_start do requested_end -= 1
	}

	root := ts_tree_root_node(state.tree)
	cursor := line_start
	for cursor <= source_bytes {
		if usage.indent_lines >= MAX_STRUCTURAL_INDENT_LINES {
			delete(edits)
			failure = structural_failure(request, .Line_Limit)
			failure.limit = MAX_STRUCTURAL_INDENT_LINES
			failure.actual = u64(usage.indent_lines) + 1
			return {}, false, failure
		}
		line_end, next_start, scanned := structural_line_extent(source, cursor, source_bytes)
		if !scanned {
			delete(edits)
			return {}, false, structural_failure(request, .Unavailable_Base_Snapshot)
		}
		usage.indent_lines += 1
		leading_end, blank, leading_ok := structural_line_leading_end(source, cursor, line_end)
		if !leading_ok {
			delete(edits)
			return {}, false, structural_failure(request, .Unavailable_Base_Snapshot)
		}
		if !blank {
			node, found, target_failure := structural_deepest_named(
				state,
				root,
				u32(leading_end),
				u32(leading_end),
				&usage,
			)
			if !found {
				delete(edits)
				return {}, false, structural_failure_from(request, target_failure)
			}
			line_has_error, error_check_ok := structural_line_has_syntax_error(
				state,
				root,
				u32(cursor),
				u32(line_end),
				&usage,
			)
			if !error_check_ok {
				delete(edits)
				failure = structural_failure(request, .Node_Limit)
				failure.limit = MAX_STRUCTURAL_NODES
				failure.actual = u64(usage.visited_nodes)
				return {}, false, failure
			}
			if !line_has_error {
				level, level_ok, level_failure := structural_odin_indent_level(
					state,
					node,
					source,
					leading_end,
					&usage,
				)
				if !level_ok {
					delete(edits)
					return {}, false, structural_failure_from(request, level_failure)
				}
				indent_bytes := u64(level) * FACTORY_ODIN_INDENT_BYTES
				prepared, prepared_ok := structural_checked_add(usage.prepared_bytes, indent_bytes)
				if !prepared_ok || prepared > MAX_STRUCTURAL_PREPARED_BYTES {
					delete(edits)
					failure = structural_failure(request, .Prepared_Text_Limit)
					failure.limit = MAX_STRUCTURAL_PREPARED_BYTES
					failure.actual = prepared
					return {}, false, failure
				}
				usage.prepared_bytes = prepared
				leading_bytes := leading_end - cursor
				if indent_bytes != leading_bytes {
					_, append_error := append(&edits, Structural_Indent_Edit {
						start = editor.Byte_Offset(cursor),
						end = editor.Byte_Offset(leading_end),
						indent_level = level,
						indent_bytes = u32(indent_bytes),
					})
					if append_error != nil {
						delete(edits)
						return {}, false, structural_failure(request, .Allocation)
					}
				}
			}
		}
		if cursor >= requested_end || next_start <= cursor || next_start > source_bytes do break
		cursor = next_start
	}
	usage.temporary_bytes = u64(cap(edits)) * u64(size_of(Structural_Indent_Edit))
	return Structural_Indentation_Plan {
		scope = request.scope,
		start = editor.Byte_Offset(line_start),
		end = editor.Byte_Offset(min(source_bytes, max(requested_end, line_start))),
		edits = edits,
		usage = usage,
		allocator = allocator,
	}, true, {}
}

@(private)
structural_query_validate :: proc(
	owner: ^Tree_Sitter_Owner,
	source: ^editor.Buffer_Snapshot,
	request: Structural_Request,
) -> (state: ^Tree_Sitter_Owner_State, source_bytes: u64, ok: bool, failure: Failure) {
	state = tree_sitter_owner_state(owner)
	if state == nil || source == nil || state.tree == nil || state.confirmed.status != .Current {
		return nil, 0, false, structural_failure(request, .Structural_Capability_Unavailable)
	}
	stats, stats_ok, _ := editor.buffer_snapshot_stats(source)
	if !stats_ok {
		return nil, 0, false, structural_failure(request, .Unavailable_Base_Snapshot)
	}
	source_bytes = stats.text_bytes
	if source_bytes > u64(max(u32)) || !structural_request_is_valid(request, source_bytes) {
		return nil, source_bytes, false, structural_failure(request, .Invalid_Transaction)
	}
	point_boundary := structural_snapshot_boundary(source, u64(request.point), source_bytes)
	start_boundary := structural_snapshot_boundary(source, u64(request.start), source_bytes)
	end_boundary := structural_snapshot_boundary(source, u64(request.end), source_bytes)
	if !point_boundary || !start_boundary || !end_boundary {
		return nil, source_bytes, false, structural_failure(request, .Invalid_UTF8_Boundary)
	}
	expected := Structural_Scope {
		buffer_id = state.confirmed.buffer_id,
		source_revision = state.confirmed.source_revision,
		language = state.confirmed.language,
		provider = state.confirmed.provider,
		selection_generation = state.confirmed.selection_generation,
		parser_generation = state.parser_generation,
		tree_generation = state.tree_generation,
	}
	if request.scope != expected || stats.buffer_id != expected.buffer_id ||
	   stats.revision != expected.source_revision || source_bytes != state.confirmed.usage.retained_source_bytes {
		return nil, source_bytes, false, structural_failure(request, .Stale_Selection)
	}
	if state.progress.cancel_requested {
		return nil, source_bytes, false, structural_failure(request, .Cancelled)
	}
	return state, source_bytes, true, {}
}

@(private)
structural_deepest_named :: proc(
	state: ^Tree_Sitter_Owner_State,
	root: Tree_Sitter_Node,
	start, end: u32,
	usage: ^Structural_Usage,
) -> (node: Tree_Sitter_Node, ok: bool, failure: Failure) {
	if ts_node_is_null(root) || start > end do return {}, false, Failure{code = .No_Structural_Target}
	current := root
	if !structural_node_contains(current, start, end) {
		return {}, false, Failure{code = .No_Structural_Target}
	}
	depth: u16
	for {
		if state.progress.cancel_requested do return {}, false, Failure{code = .Cancelled}
		count := ts_node_named_child_count(current)
		candidate: Tree_Sitter_Node
		candidate_width := max(u32)
		candidate_starts := false
		for index in 0 ..< count {
			usage.visited_nodes += 1
			if usage.visited_nodes > MAX_STRUCTURAL_NODES {
				return {}, false, Failure{code = .Node_Limit, limit = MAX_STRUCTURAL_NODES, actual = u64(usage.visited_nodes)}
			}
			child := ts_node_named_child(current, index)
			if ts_node_is_null(child) || !structural_node_contains(child, start, end) do continue
			starts := start == end && ts_node_start_byte(child) == start
			if start == end && !starts && !(ts_node_start_byte(child) <= start && start < ts_node_end_byte(child)) do continue
			width := ts_node_end_byte(child) - ts_node_start_byte(child)
			if ts_node_is_null(candidate) || (starts && !candidate_starts) ||
			   (starts == candidate_starts && width < candidate_width) {
				candidate = child
				candidate_width = width
				candidate_starts = starts
			}
		}
		if ts_node_is_null(candidate) do break
		if depth >= MAX_STRUCTURAL_DEPTH {
			return {}, false, Failure{code = .Depth_Limit, limit = MAX_STRUCTURAL_DEPTH, actual = u64(depth) + 1}
		}
		current = candidate
		depth += 1
	}
	if !ts_node_is_named(current) do return {}, false, Failure{code = .No_Structural_Target}
	usage.visited_depth = max(usage.visited_depth, depth)
	return current, true, {}
}

@(private)
structural_node_contains :: proc(node: Tree_Sitter_Node, start, end: u32) -> bool {
	if ts_node_is_null(node) do return false
	node_start := ts_node_start_byte(node)
	node_end := ts_node_end_byte(node)
	if start == end do return node_start <= start && start <= node_end
	return node_start <= start && end <= node_end
}

@(private)
structural_named_parent :: proc(
	state: ^Tree_Sitter_Owner_State,
	node: Tree_Sitter_Node,
	usage: ^Structural_Usage,
) -> Tree_Sitter_Node {
	parent := ts_node_parent(node)
	for !ts_node_is_null(parent) {
		usage.visited_nodes += 1
		if usage.visited_nodes > MAX_STRUCTURAL_NODES || state.progress.cancel_requested do return {}
		if ts_node_is_named(parent) do return parent
		parent = ts_node_parent(parent)
	}
	return {}
}

@(private)
structural_definition_node :: proc(
	state: ^Tree_Sitter_Owner_State,
	root, node: Tree_Sitter_Node,
	usage: ^Structural_Usage,
) -> Tree_Sitter_Node {
	current := node
	for !ts_node_is_null(current) {
		if state.progress.cancel_requested do return {}
		parent := ts_node_parent(current)
		if ts_node_is_null(parent) do return {}
		usage.visited_nodes += 1
		if usage.visited_nodes > MAX_STRUCTURAL_NODES do return {}
		if parent.id == root.id && parent.tree == root.tree {
			return current
		}
		current = parent
	}
	return {}
}

@(private)
structural_first_named_child :: proc(
	state: ^Tree_Sitter_Owner_State,
	node: Tree_Sitter_Node,
	usage: ^Structural_Usage,
) -> Tree_Sitter_Node {
	if state.progress.cancel_requested do return {}
	usage.visited_nodes += 1
	if usage.visited_nodes > MAX_STRUCTURAL_NODES do return {}
	return ts_node_named_child(node, 0)
}

@(private)
structural_copy_target :: proc(
	scope: Structural_Scope,
	node: Tree_Sitter_Node,
	source_bytes: u64,
	usage: ^Structural_Usage,
	request: Structural_Request,
) -> (Structural_Target, Structural_Usage, bool, Failure) {
	start := ts_node_start_byte(node)
	end := ts_node_end_byte(node)
	if start >= end || u64(end) > source_bytes {
		return {}, usage^, false, structural_failure(request, .Invalid_UTF8_Boundary)
	}
	type_pointer := ts_node_type(node)
	if type_pointer == nil do return {}, usage^, false, structural_failure(request, .Node_Kind_Limit)
	kind_source := string(type_pointer)
	if len(kind_source) == 0 || len(kind_source) > MAX_STRUCTURAL_NODE_KIND_BYTES {
		failure := structural_failure(request, .Node_Kind_Limit)
		failure.limit = MAX_STRUCTURAL_NODE_KIND_BYTES
		failure.actual = u64(len(kind_source))
		return {}, usage^, false, failure
	}
	kind := Structural_Node_Kind{length = u16(len(kind_source))}
	copy(kind.bytes[:], kind_source)
	depth: u16
	parent := ts_node_parent(node)
	for !ts_node_is_null(parent) {
		if ts_node_is_named(parent) {
			if depth >= MAX_STRUCTURAL_DEPTH {
				failure := structural_failure(request, .Depth_Limit)
				failure.limit = MAX_STRUCTURAL_DEPTH
				failure.actual = u64(depth) + 1
				return {}, usage^, false, failure
			}
			depth += 1
		}
		parent = ts_node_parent(parent)
	}
	usage.visited_depth = max(usage.visited_depth, depth)
	return Structural_Target {
		scope = scope,
		start = editor.Byte_Offset(start),
		end = editor.Byte_Offset(end),
		kind = kind,
		depth = depth,
	}, usage^, true, {}
}

@(private)
structural_odin_indent_level :: proc(
	state: ^Tree_Sitter_Owner_State,
	node: Tree_Sitter_Node,
	source: ^editor.Buffer_Snapshot,
	first_nonspace: u64,
	usage: ^Structural_Usage,
) -> (level: u16, ok: bool, failure: Failure) {
	cursor := node
	for !ts_node_is_null(cursor) {
		usage.visited_nodes += 1
		if usage.visited_nodes > MAX_STRUCTURAL_NODES {
			return 0, false, Failure{code = .Node_Limit, limit = MAX_STRUCTURAL_NODES, actual = u64(usage.visited_nodes)}
		}
		if state.progress.cancel_requested do return 0, false, Failure{code = .Cancelled}
		kind_pointer := ts_node_type(cursor)
		if kind_pointer != nil && structural_odin_indent_owner(string(kind_pointer)) {
			if level >= MAX_STRUCTURAL_DEPTH {
				return 0, false, Failure{code = .Depth_Limit, limit = MAX_STRUCTURAL_DEPTH, actual = u64(level) + 1}
			}
			level += 1
		}
		cursor = ts_node_parent(cursor)
	}
	prefix: [7]u8
	copied, read_ok, _ := editor.buffer_snapshot_read(source, editor.Byte_Offset(first_nonspace), prefix[:])
	if !read_ok do return 0, false, Failure{code = .Unavailable_Base_Snapshot}
	text := string(prefix[:int(copied)])
	dedent := len(text) > 0 && (text[0] == '}' || text[0] == '{')
	if len(text) >= 4 && text[:4] == "case" do dedent = true
	if len(text) >= 7 && text[:7] == "default" do dedent = true
	if dedent && level > 0 do level -= 1
	usage.visited_depth = max(usage.visited_depth, level)
	return level, true, {}
}

@(private)
structural_odin_indent_owner :: proc(kind: string) -> bool {
	return kind == "block" || kind == "struct" || kind == "struct_type" ||
		kind == "union_type" || kind == "enum_type" || kind == "foreign_block" ||
		kind == "switch_case"
}

@(private)
structural_line_has_syntax_error :: proc(
	state: ^Tree_Sitter_Owner_State,
	node: Tree_Sitter_Node,
	line_start, line_end: u32,
	usage: ^Structural_Usage,
) -> (has_error, ok: bool) {
	if ts_node_is_null(node) do return false, true
	node_start := ts_node_start_byte(node)
	node_end := ts_node_end_byte(node)
	if node_end < line_start || node_start > line_end do return false, true
	if ts_node_is_error(node) || ts_node_is_missing(node) do return true, true
	if !ts_node_has_error(node) do return false, true
	count := ts_node_child_count(node)
	for index in 0 ..< count {
		usage.visited_nodes += 1
		if usage.visited_nodes > MAX_STRUCTURAL_NODES || state.progress.cancel_requested {
			return false, false
		}
		child_has_error, child_ok := structural_line_has_syntax_error(
			state,
			ts_node_child(node, index),
			line_start,
			line_end,
			usage,
		)
		if !child_ok || child_has_error do return child_has_error, child_ok
	}
	return false, true
}

@(private)
structural_line_start :: proc(source: ^editor.Buffer_Snapshot, point: u64) -> (u64, bool) {
	if point == 0 do return 0, true
	cursor := point
	scratch: [STRUCTURAL_SCAN_BYTES]u8
	for cursor > 0 {
		start := cursor - min(cursor, u64(len(scratch)))
		copied, ok, _ := editor.buffer_snapshot_read(source, editor.Byte_Offset(start), scratch[:int(cursor - start)])
		if !ok || copied != cursor - start do return 0, false
		for index := int(copied) - 1; index >= 0; index -= 1 {
			if scratch[index] == '\n' do return start + u64(index) + 1, true
		}
		cursor = start
	}
	return 0, true
}

@(private)
structural_snapshot_boundary :: proc(
	source: ^editor.Buffer_Snapshot,
	offset, source_bytes: u64,
) -> bool {
	if offset == 0 || offset == source_bytes do return true
	if offset > source_bytes do return false
	value: [1]u8
	copied, ok, _ := editor.buffer_snapshot_read(source, editor.Byte_Offset(offset), value[:])
	return ok && copied == 1 && value[0] & 0xc0 != 0x80
}

@(private)
structural_line_extent :: proc(
	source: ^editor.Buffer_Snapshot,
	start, source_bytes: u64,
) -> (content_end, next_start: u64, ok: bool) {
	if start > source_bytes do return 0, 0, false
	cursor := start
	scratch: [STRUCTURAL_SCAN_BYTES]u8
	for cursor < source_bytes {
		take := min(u64(len(scratch)), source_bytes - cursor)
		copied, read_ok, _ := editor.buffer_snapshot_read(source, editor.Byte_Offset(cursor), scratch[:int(take)])
		if !read_ok || copied != take do return 0, 0, false
		for byte, index in scratch[:int(copied)] {
			if byte == '\n' do return cursor + u64(index), cursor + u64(index) + 1, true
		}
		cursor += copied
	}
	return source_bytes, source_bytes, true
}

@(private)
structural_line_leading_end :: proc(
	source: ^editor.Buffer_Snapshot,
	start, end: u64,
) -> (leading_end: u64, blank, ok: bool) {
	cursor := start
	scratch: [STRUCTURAL_SCAN_BYTES]u8
	for cursor < end {
		take := min(u64(len(scratch)), end - cursor)
		copied, read_ok, _ := editor.buffer_snapshot_read(source, editor.Byte_Offset(cursor), scratch[:int(take)])
		if !read_ok || copied != take do return 0, false, false
		for byte, index in scratch[:int(copied)] {
			if byte != ' ' && byte != '\t' do return cursor + u64(index), false, true
		}
		cursor += copied
	}
	return end, true, true
}

@(private)
structural_failure :: proc(request: Structural_Request, code: Failure_Code) -> Failure {
	return Failure {
		operation = structural_failure_operation(request.operation),
		code = code,
		language_id = request.scope.language.id,
		provider = request.scope.provider,
		selection_generation = request.scope.selection_generation,
		source_revision = request.scope.source_revision,
	}
}

@(private)
structural_failure_from :: proc(request: Structural_Request, source: Failure) -> Failure {
	failure := structural_failure(request, source.code)
	failure.limit = source.limit
	failure.actual = source.actual
	return failure
}

@(private)
structural_failure_operation :: proc(operation: Structural_Operation) -> Operation {
	if operation == .Indent do return .Plan_Indentation
	return .Query_Structure
}

@(private)
structural_checked_add :: proc(left, right: u64) -> (u64, bool) {
	if right > max(u64) - left do return 0, false
	return left + right, true
}
