// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

// Package structural_syntax_reference provides an independent pointer-free
// oracle for bounded structural traversal and indentation planning.
package structural_syntax_reference

import "base:runtime"

MAX_NODES :: 65_536
MAX_DEPTH :: 1_024
MAX_INDENT_LINES :: 16_384
MAX_PREPARED_BYTES :: 8 * 1_024 * 1_024

INVALID_INDEX :: max(u32)

Operation :: enum u8 {
	Containing,
	Previous,
	Next,
	Parent,
	Child,
	Expand,
}

Failure_Code :: enum u8 {
	None,
	Invalid_Request,
	No_Target,
	Node_Limit,
	Depth_Limit,
	Line_Limit,
	Prepared_Bytes_Limit,
	Cancelled,
	Allocation,
}

Node :: struct {
	start:        u32,
	end:          u32,
	parent:       u32,
	first_child:  u32,
	next_sibling: u32,
	named:        bool,
}

Request :: struct {
	operation: Operation,
	start:     u32,
	end:       u32,
}

Target :: struct {
	index: u32,
	start: u32,
	end:   u32,
	depth: u16,
}

Usage :: struct {
	visited_nodes: u32,
	visited_depth: u16,
	lines:         u32,
	prepared_bytes: u64,
}

Failure :: struct {
	code:   Failure_Code,
	limit:  u64,
	actual: u64,
}

Cancellation :: struct {
	requested: bool,
}

Indent_Line :: struct {
	start:             u32,
	leading_bytes:     u32,
	desired_level:     u16,
	syntax_error:      bool,
}

Indent_Edit :: struct {
	start:             u32,
	removed_bytes:     u32,
	replacement_bytes: u32,
}

Indent_Plan :: struct {
	edits:     [dynamic]Indent_Edit,
	usage:     Usage,
	allocator: runtime.Allocator,
}

query :: proc(
	nodes: []Node,
	request: Request,
	cancellation: ^Cancellation = nil,
) -> (target: Target, usage: Usage, ok: bool, failure: Failure) {
	if len(nodes) == 0 || request.start > request.end {
		return {}, {}, false, Failure{code = .Invalid_Request}
	}
	if len(nodes) > MAX_NODES {
		return {}, {}, false, Failure{code = .Node_Limit, limit = MAX_NODES, actual = u64(len(nodes))}
	}
	containing, containing_usage, found, containing_failure := containing_node(
		nodes,
		request.start,
		request.end,
		cancellation,
	)
	if !found do return {}, containing_usage, false, containing_failure
	usage = containing_usage
	index := containing.index
	switch request.operation {
	case .Containing:
		return containing, usage, true, {}
	case .Parent, .Expand:
		index = named_parent(nodes, index, &usage, cancellation)
	case .Child:
		index = named_child(nodes, index, &usage, cancellation)
	case .Previous:
		index = named_sibling(nodes, containing.index, false, &usage, cancellation)
	case .Next:
		index = named_sibling(nodes, containing.index, true, &usage, cancellation)
	}
	if cancellation != nil && cancellation.requested {
		return {}, usage, false, Failure{code = .Cancelled}
	}
	if index == INVALID_INDEX do return {}, usage, false, Failure{code = .No_Target}
	return target_for(nodes, index, &usage)
}

indent_plan :: proc(
	lines: []Indent_Line,
	tab_bytes: u32,
	cancellation: ^Cancellation = nil,
	allocator := context.allocator,
) -> (plan: Indent_Plan, ok: bool, failure: Failure) {
	if tab_bytes == 0 || allocator.procedure == nil {
		return {}, false, Failure{code = .Invalid_Request}
	}
	if len(lines) > MAX_INDENT_LINES {
		return {}, false, Failure{code = .Line_Limit, limit = MAX_INDENT_LINES, actual = u64(len(lines))}
	}
	edits, allocation_error := make([dynamic]Indent_Edit, 0, len(lines), allocator)
	if allocation_error != nil do return {}, false, Failure{code = .Allocation}
	usage := Usage{lines = u32(len(lines))}
	for line in lines {
		if cancellation != nil && cancellation.requested {
			delete(edits)
			return {}, false, Failure{code = .Cancelled}
		}
		if line.syntax_error do continue
		replacement := u64(line.desired_level) * u64(tab_bytes)
		prepared, prepared_ok := checked_add(usage.prepared_bytes, replacement)
		if !prepared_ok || prepared > MAX_PREPARED_BYTES {
			delete(edits)
			return {}, false, Failure{
				code = .Prepared_Bytes_Limit,
				limit = MAX_PREPARED_BYTES,
				actual = prepared,
			}
		}
		usage.prepared_bytes = prepared
		if replacement == u64(line.leading_bytes) do continue
		_, append_error := append(&edits, Indent_Edit {
			start = line.start,
			removed_bytes = line.leading_bytes,
			replacement_bytes = u32(replacement),
		})
		if append_error != nil {
			delete(edits)
			return {}, false, Failure{code = .Allocation}
		}
	}
	return Indent_Plan{edits = edits, usage = usage, allocator = allocator}, true, {}
}

indent_plan_close :: proc(plan: ^Indent_Plan) {
	if plan == nil do return
	if plan.edits != nil do delete(plan.edits)
	plan^ = {}
}

containing_node :: proc(
	nodes: []Node,
	start, end: u32,
	cancellation: ^Cancellation,
) -> (target: Target, usage: Usage, ok: bool, failure: Failure) {
	best := INVALID_INDEX
	best_width := max(u32)
	for node, index in nodes {
		usage.visited_nodes += 1
		if cancellation != nil && cancellation.requested {
			return {}, usage, false, Failure{code = .Cancelled}
		}
		if !node.named || node.start > start || node.end < end do continue
		if start == end && node.start == start {
			width := node.end - node.start
			if best == INVALID_INDEX || width < best_width {
				best = u32(index)
				best_width = width
			}
			continue
		}
		if start == end && !(node.start <= start && start < node.end) do continue
		width := node.end - node.start
		if best == INVALID_INDEX || width < best_width {
			best = u32(index)
			best_width = width
		}
	}
	if best == INVALID_INDEX do return {}, usage, false, Failure{code = .No_Target}
	return target_for(nodes, best, &usage)
}

target_for :: proc(nodes: []Node, index: u32, usage: ^Usage) -> (Target, Usage, bool, Failure) {
	depth: u16
	cursor := index
	for nodes[cursor].parent != INVALID_INDEX {
		if depth >= MAX_DEPTH {
			return {}, usage^, false, Failure{code = .Depth_Limit, limit = MAX_DEPTH, actual = u64(depth) + 1}
		}
		cursor = nodes[cursor].parent
		depth += 1
	}
	usage.visited_depth = max(usage.visited_depth, depth)
	node := nodes[index]
	return Target{index = index, start = node.start, end = node.end, depth = depth}, usage^, true, {}
}

named_parent :: proc(nodes: []Node, index: u32, usage: ^Usage, cancellation: ^Cancellation) -> u32 {
	cursor := nodes[index].parent
	for cursor != INVALID_INDEX {
		usage.visited_nodes += 1
		if cancellation != nil && cancellation.requested do return INVALID_INDEX
		if nodes[cursor].named do return cursor
		cursor = nodes[cursor].parent
	}
	return INVALID_INDEX
}

named_child :: proc(nodes: []Node, index: u32, usage: ^Usage, cancellation: ^Cancellation) -> u32 {
	cursor := nodes[index].first_child
	for cursor != INVALID_INDEX {
		usage.visited_nodes += 1
		if cancellation != nil && cancellation.requested do return INVALID_INDEX
		if nodes[cursor].named do return cursor
		cursor = nodes[cursor].next_sibling
	}
	return INVALID_INDEX
}

named_sibling :: proc(
	nodes: []Node,
	index: u32,
	forward: bool,
	usage: ^Usage,
	cancellation: ^Cancellation,
) -> u32 {
	parent := nodes[index].parent
	if parent == INVALID_INDEX do return INVALID_INDEX
	cursor := nodes[parent].first_child
	previous := INVALID_INDEX
	for cursor != INVALID_INDEX {
		usage.visited_nodes += 1
		if cancellation != nil && cancellation.requested do return INVALID_INDEX
		if cursor == index {
			if !forward do return previous
			cursor = nodes[cursor].next_sibling
			for cursor != INVALID_INDEX {
				usage.visited_nodes += 1
				if nodes[cursor].named do return cursor
				cursor = nodes[cursor].next_sibling
			}
			return INVALID_INDEX
		}
		if nodes[cursor].named do previous = cursor
		cursor = nodes[cursor].next_sibling
	}
	return INVALID_INDEX
}

checked_add :: proc(left, right: u64) -> (u64, bool) {
	if right > max(u64) - left do return 0, false
	return left + right, true
}
