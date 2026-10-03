// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language

import "../editor"
import "base:runtime"
import "core:slice"
import "core:strconv"

/* MAX_VISIBLE_HALO_BYTES bounds syntax work outside one visible byte range. */
MAX_VISIBLE_HALO_BYTES :: CANCELLATION_CHECK_BYTES

/* Syntax_Query_Result owns one copied normalized syntax snapshot and its spans. */
Syntax_Query_Result :: struct {
	snapshot:    Syntax_Snapshot,
	spans:       [dynamic]Syntax_Span,
	structures:  [dynamic]Syntax_Structural_Projection,
	allocator:   runtime.Allocator,
}

@(private)
Raw_Syntax_Capture :: struct {
	start:      u32,
	end:        u32,
	role:       Syntax_Role,
	precedence: u16,
	serial:     u32,
}

/* tree_sitter_owner_query_spans normalizes one bounded visible-range query. */
tree_sitter_owner_query_spans :: proc(
	owner: ^Tree_Sitter_Owner,
	source: ^editor.Buffer_Snapshot,
	visible_start, visible_end: u64,
	halo_bytes: u64,
	generation: Syntax_Snapshot_Generation,
	allocator := context.allocator,
) -> (result: Syntax_Query_Result, ok: bool, failure: Failure) {
	state := tree_sitter_owner_state(owner)
	if state == nil || source == nil || state.tree == nil || state.query == nil || state.cursor == nil ||
	   state.confirmed.status != .Current {
		return {}, false, tree_sitter_failure(.Publish_Syntax, .Parser_Initialization)
	}
	source_stats, source_ok, _ := editor.buffer_snapshot_stats(source)
	if !source_ok || source_stats.buffer_id != state.confirmed.buffer_id ||
	   source_stats.revision != state.confirmed.source_revision ||
	   source_stats.text_bytes != state.confirmed.usage.retained_source_bytes {
		return {}, false, tree_sitter_failure(.Publish_Syntax, .Unavailable_Base_Snapshot)
	}
	source_bytes := state.confirmed.usage.retained_source_bytes
	if visible_start > visible_end || visible_end > source_bytes {
		return {}, false, tree_sitter_failure(.Publish_Syntax, .Invalid_Transaction)
	}
	if halo_bytes > MAX_VISIBLE_HALO_BYTES {
		failure = tree_sitter_failure(.Publish_Syntax, .Work_Limit)
		failure.limit = MAX_VISIBLE_HALO_BYTES
		failure.actual = halo_bytes
		return {}, false, failure
	}
	if generation == Syntax_Snapshot_Generation(0) || allocator.procedure == nil {
		return {}, false, tree_sitter_failure(.Publish_Syntax, .Allocation)
	}

	query_start := visible_start - min(visible_start, halo_bytes)
	query_end, end_ok := checked_add_u64(visible_end, halo_bytes)
	if !end_ok do query_end = source_bytes
	query_end = min(query_end, source_bytes)
	raw_captures, raw_error := make(
		[dynamic]Raw_Syntax_Capture,
		0,
		int(MAX_VISIBLE_QUERY_SPANS),
		allocator,
	)
	if raw_error != nil {
		return {}, false, tree_sitter_failure(.Publish_Syntax, .Allocation)
	}
	defer delete(raw_captures)
	structures, structures_error := make(
		[dynamic]Syntax_Structural_Projection,
		0,
		min(int(MAX_VISIBLE_QUERY_SPANS), int(state.provider_capture_mapping_count)),
		allocator,
	)
	if structures_error != nil {
		return {}, false, tree_sitter_failure(.Publish_Syntax, .Allocation)
	}
	defer if structures != nil do delete(structures)

	ts_query_cursor_set_match_limit(state.cursor, MAX_VISIBLE_QUERY_SPANS)
	if !ts_query_cursor_set_byte_range(state.cursor, u32(query_start), u32(query_end)) {
		return {}, false, tree_sitter_failure(.Publish_Syntax, .Invalid_Transaction)
	}
	tree_sitter_memory_begin(state)
	defer tree_sitter_memory_end()
	ts_query_cursor_exec(state.cursor, state.query, ts_tree_root_node(state.tree))
	match: Tree_Sitter_Query_Match
	capture_index: u32
	serial: u32
	for ts_query_cursor_next_capture(state.cursor, &match, &capture_index) {
		if capture_index >= u32(match.capture_count) || match.captures == nil {
			failure = tree_sitter_failure(.Publish_Syntax, .Invalid_Capture_Mapping)
			failure.limit = u64(match.capture_count)
			failure.actual = u64(capture_index)
			return {}, false, failure
		}
		if len(raw_captures) >= MAX_CAPTURES {
			failure = tree_sitter_failure(.Publish_Syntax, .Capture_Limit)
			failure.limit = MAX_CAPTURES
			failure.actual = u64(len(raw_captures)) + 1
			return {}, false, failure
		}
		capture := match.captures[capture_index]
		if !tree_sitter_match_predicates_admit(state.query, match, source) do continue
		length: u32
		name_pointer := ts_query_capture_name_for_id(state.query, capture.index, &length)
		if name_pointer == nil || length == 0 {
			failure = tree_sitter_failure(.Publish_Syntax, .Invalid_Capture_Mapping)
			failure.actual = u64(capture.index)
			return {}, false, failure
		}
		name := string((cast([^]u8)name_pointer)[:length])
		mapping, known := tree_sitter_owner_capture_projection(state, name)
		if !known {
			failure = tree_sitter_failure(.Publish_Syntax, .Invalid_Capture_Mapping)
			failure.actual = u64(capture.index)
			return {}, false, failure
		}
		if mapping.ignored do continue
		start := ts_node_start_byte(capture.node)
		end := ts_node_end_byte(capture.node)
		if start >= end do continue
		if u64(end) > source_bytes {
			failure = tree_sitter_failure(.Publish_Syntax, .Invalid_Capture_Mapping)
			failure.limit = source_bytes
			failure.actual = u64(end)
			return {}, false, failure
		}
		if mapping.structural_role != .None && ts_node_is_named(capture.node) {
			if len(structures) >= MAX_VISIBLE_QUERY_SPANS {
				failure = tree_sitter_failure(.Publish_Syntax, .Node_Limit)
				failure.limit = MAX_VISIBLE_QUERY_SPANS
				failure.actual = u64(len(structures)) + 1
				return {}, false, failure
			}
			_, append_error := append(&structures, Syntax_Structural_Projection {
				start = editor.Byte_Offset(start),
				end = editor.Byte_Offset(end),
				role = mapping.structural_role,
				provider = state.confirmed.provider,
				source_revision = state.confirmed.source_revision,
			})
			if append_error != nil {
				return {}, false, tree_sitter_failure(.Publish_Syntax, .Allocation)
			}
		}
		precedence := tree_sitter_pattern_precedence(state.query, u32(match.pattern_index))
		if precedence == 0 do precedence = mapping.precedence
		_, append_error := append(&raw_captures, Raw_Syntax_Capture {
			start = start,
			end = end,
			role = mapping.role,
			precedence = precedence,
			serial = serial,
		})
		if append_error != nil {
			return {}, false, tree_sitter_failure(.Publish_Syntax, .Allocation)
		}
		serial += 1
	}
	if ts_query_cursor_did_exceed_match_limit(state.cursor) {
		failure = tree_sitter_failure(.Publish_Syntax, .Capture_Limit)
		failure.limit = MAX_VISIBLE_QUERY_SPANS
		failure.actual = MAX_VISIBLE_QUERY_SPANS + 1
		return {}, false, failure
	}

	spans, spans_error := syntax_captures_normalize(
		raw_captures[:],
		state.confirmed.provider,
		state.confirmed.source_revision,
		allocator,
	)
	if spans_error.code != .None {
		return {}, false, spans_error
	}
	usage := state.confirmed.usage
	usage.retained_tree_bytes = odra_tree_sitter_memory_owner_live_bytes(state.memory_owner)
	usage.captures = u32(len(raw_captures))
	usage.spans = u32(len(spans))
	usage.retained_span_bytes = u64(len(spans)) * u64(size_of(Syntax_Span))
	result = Syntax_Query_Result {
		snapshot = Syntax_Snapshot {
			generation = generation,
			buffer_id = state.confirmed.buffer_id,
			source_revision = state.confirmed.source_revision,
			language = state.confirmed.language,
			provider = state.confirmed.provider,
			selection_generation = state.confirmed.selection_generation,
			parser_generation = state.parser_generation,
			query_generation = state.query_generation,
			span_count = u32(len(spans)),
			structural_count = u32(len(structures)),
			usage = usage,
		},
		spans = spans,
		structures = structures,
		allocator = allocator,
	}
	structures = nil
	return result, true, {}
}

/* syntax_query_result_close releases copied normalized spans exactly once. */
syntax_query_result_close :: proc(result: ^Syntax_Query_Result) {
	if result == nil do return
	if result.spans != nil do delete(result.spans)
	if result.structures != nil do delete(result.structures)
	result^ = {}
}

@(private)
syntax_captures_normalize :: proc(
	captures: []Raw_Syntax_Capture,
	provider: Provider_Handle,
	revision: editor.Revision,
	allocator: runtime.Allocator,
) -> (spans: [dynamic]Syntax_Span, failure: Failure) {
	slice.sort_by(captures, proc(left, right: Raw_Syntax_Capture) -> bool {
		if left.start != right.start do return left.start < right.start
		if left.precedence != right.precedence do return left.precedence > right.precedence
		return left.serial > right.serial
	})
	heap, heap_error := make([dynamic]Raw_Syntax_Capture, 0, len(captures), allocator)
	if heap_error != nil do return nil, tree_sitter_failure(.Publish_Syntax, .Allocation)
	defer delete(heap)
	spans_error: runtime.Allocator_Error
	spans, spans_error = make([dynamic]Syntax_Span, 0, min(MAX_SYNTAX_SPANS, len(captures) * 2), allocator)
	if spans_error != nil do return nil, tree_sitter_failure(.Publish_Syntax, .Allocation)

	index := 0
	position: u32
	if len(captures) > 0 do position = captures[0].start
	for index < len(captures) || len(heap) > 0 {
		for index < len(captures) && captures[index].start <= position {
			if !syntax_capture_heap_push(&heap, captures[index]) {
				delete(spans)
				return nil, tree_sitter_failure(.Publish_Syntax, .Allocation)
			}
			index += 1
		}
		for len(heap) > 0 && heap[0].end <= position do syntax_capture_heap_pop(&heap)
		if len(heap) == 0 {
			if index < len(captures) {
				position = captures[index].start
				continue
			}
			break
		}
		next := heap[0].end
		if index < len(captures) do next = min(next, captures[index].start)
		if next > position {
			if len(spans) >= MAX_SYNTAX_SPANS {
				delete(spans)
				return nil, tree_sitter_failure(.Publish_Syntax, .Span_Limit)
			}
			top := heap[0]
			if len(spans) > 0 && u64(spans[len(spans) - 1].end) == u64(position) &&
			   spans[len(spans) - 1].role == top.role &&
			   spans[len(spans) - 1].precedence == top.precedence {
				spans[len(spans) - 1].end = editor.Byte_Offset(next)
			} else {
				_, append_error := append(&spans, Syntax_Span {
					start = editor.Byte_Offset(position),
					end = editor.Byte_Offset(next),
					role = top.role,
					precedence = top.precedence,
					provider = provider,
					source_revision = revision,
				})
				if append_error != nil {
					delete(spans)
					return nil, tree_sitter_failure(.Publish_Syntax, .Allocation)
				}
			}
		}
		position = next
	}
	return spans, {}
}

@(private)
syntax_capture_heap_push :: proc(heap: ^[dynamic]Raw_Syntax_Capture, value: Raw_Syntax_Capture) -> bool {
	_, append_error := append(heap, value)
	if append_error != nil do return false
	index := len(heap^) - 1
	for index > 0 {
		parent := (index - 1) / 2
		if !syntax_capture_higher(heap^[index], heap^[parent]) do break
		heap^[index], heap^[parent] = heap^[parent], heap^[index]
		index = parent
	}
	return true
}

@(private)
syntax_capture_heap_pop :: proc(heap: ^[dynamic]Raw_Syntax_Capture) {
	last := len(heap^) - 1
	heap^[0] = heap^[last]
	resize(heap, last)
	index := 0
	for {
		left := index * 2 + 1
		if left >= len(heap^) do break
		right := left + 1
		best := left
		if right < len(heap^) && syntax_capture_higher(heap^[right], heap^[left]) do best = right
		if !syntax_capture_higher(heap^[best], heap^[index]) do break
		heap^[index], heap^[best] = heap^[best], heap^[index]
		index = best
	}
}

@(private)
syntax_capture_higher :: proc(left, right: Raw_Syntax_Capture) -> bool {
	if left.precedence != right.precedence do return left.precedence > right.precedence
	if left.serial != right.serial do return left.serial > right.serial
	return left.end < right.end
}

@(private)
tree_sitter_pattern_precedence :: proc(query: rawptr, pattern_index: u32) -> u16 {
	step_count: u32
	steps := ts_query_predicates_for_pattern(query, pattern_index, &step_count)
	if steps == nil || step_count == 0 do return 0
	values: [3]string
	value_count := 0
	for index in 0 ..< step_count {
		step := steps[index]
		if step.type == .Done {
			if value_count == 3 && values[0] == "set!" && values[1] == "priority" {
				priority, parsed := strconv.parse_uint(values[2], 10)
				if parsed && priority <= uint(max(u16)) do return u16(priority)
			}
			value_count = 0
			continue
		}
		if step.type != .String || value_count >= len(values) do continue
		length: u32
		value_pointer := ts_query_string_value_for_id(query, step.value_id, &length)
		if value_pointer == nil do continue
		values[value_count] = string((cast([^]u8)value_pointer)[:length])
		value_count += 1
	}
	return 0
}

@(private)
tree_sitter_match_predicates_admit :: proc(
	query: rawptr,
	match: Tree_Sitter_Query_Match,
	source: ^editor.Buffer_Snapshot,
) -> bool {
	step_count: u32
	step_pointer := ts_query_predicates_for_pattern(query, u32(match.pattern_index), &step_count)
	if step_pointer == nil || step_count == 0 do return true
	steps := step_pointer[:int(step_count)]
	start := 0
	for end in 0 ..< len(steps) {
		if steps[end].type != .Done do continue
		if end > start && !tree_sitter_predicate_admits(query, match, source, steps[start:end]) {
			return false
		}
		start = end + 1
	}
	return start == len(steps)
}

@(private)
tree_sitter_predicate_admits :: proc(
	query: rawptr,
	match: Tree_Sitter_Query_Match,
	source: ^editor.Buffer_Snapshot,
	steps: []Tree_Sitter_Query_Predicate_Step,
) -> bool {
	if len(steps) == 0 || steps[0].type != .String do return false
	operator, operator_ok := tree_sitter_predicate_string(query, steps[0])
	if !operator_ok do return false
	switch operator {
	case "set!":
		return len(steps) == 3 && steps[1].type == .String && steps[2].type == .String
	case "any-of?":
		if len(steps) < 3 || steps[1].type != .Capture do return false
		node, found := tree_sitter_match_capture_node(match, steps[1].value_id)
		if !found do return false
		for step in steps[2:] {
			literal, literal_ok := tree_sitter_predicate_string(query, step)
			if !literal_ok do return false
			if tree_sitter_capture_equals(source, node, literal) do return true
		}
		return false
	case "lua-match?":
		if len(steps) != 3 || steps[1].type != .Capture do return false
		node, found := tree_sitter_match_capture_node(match, steps[1].value_id)
		pattern, pattern_ok := tree_sitter_predicate_string(query, steps[2])
		return found && pattern_ok && tree_sitter_capture_matches(source, node, pattern)
	case "not-has-parent?":
		if len(steps) < 3 || steps[1].type != .Capture do return false
		node, found := tree_sitter_match_capture_node(match, steps[1].value_id)
		if !found do return false
		parent := ts_node_parent(node)
		if ts_node_is_null(parent) do return true
		parent_type_pointer := ts_node_type(parent)
		if parent_type_pointer == nil do return false
		parent_type := string(parent_type_pointer)
		for step in steps[2:] {
			forbidden, forbidden_ok := tree_sitter_predicate_string(query, step)
			if !forbidden_ok do return false
			if parent_type == forbidden do return false
		}
		return true
	}
	return false
}

@(private)
tree_sitter_predicate_string :: proc(
	query: rawptr,
	step: Tree_Sitter_Query_Predicate_Step,
) -> (value: string, ok: bool) {
	if step.type != .String do return "", false
	length: u32
	pointer := ts_query_string_value_for_id(query, step.value_id, &length)
	if pointer == nil do return "", false
	return string((cast([^]u8)pointer)[:length]), true
}

@(private)
tree_sitter_match_capture_node :: proc(
	match: Tree_Sitter_Query_Match,
	capture_id: u32,
) -> (node: Tree_Sitter_Node, found: bool) {
	if match.captures == nil do return {}, false
	for capture in match.captures[:int(match.capture_count)] {
		if capture.index == capture_id do return capture.node, true
	}
	return {}, false
}

@(private)
tree_sitter_capture_equals :: proc(
	source: ^editor.Buffer_Snapshot,
	node: Tree_Sitter_Node,
	literal: string,
) -> bool {
	start := ts_node_start_byte(node)
	end := ts_node_end_byte(node)
	if end < start || u64(end - start) != u64(len(literal)) do return false
	scratch: [256]u8
	offset := u32(0)
	for offset < end - start {
		take := min(u32(len(scratch)), end - start - offset)
		copied, read_ok, _ := editor.buffer_snapshot_read(
			source,
			editor.Byte_Offset(u64(start) + u64(offset)),
			scratch[:int(take)],
		)
		if !read_ok || copied != u64(take) do return false
		for byte, index in scratch[:int(take)] {
			if byte != literal[int(offset) + index] do return false
		}
		offset += take
	}
	return true
}

@(private)
tree_sitter_capture_matches :: proc(
	source: ^editor.Buffer_Snapshot,
	node: Tree_Sitter_Node,
	pattern: string,
) -> bool {
	start := ts_node_start_byte(node)
	end := ts_node_end_byte(node)
	if end <= start do return false
	capitalized := pattern == "^[A-Z][a-zA-Z0-9]*$"
	macro := pattern == "^_*[A-Z][A-Z0-9_]*$"
	if !capitalized && !macro do return false
	scratch: [256]u8
	offset := u32(0)
	seen_initial := false
	for offset < end - start {
		take := min(u32(len(scratch)), end - start - offset)
		copied, read_ok, _ := editor.buffer_snapshot_read(
			source,
			editor.Byte_Offset(u64(start) + u64(offset)),
			scratch[:int(take)],
		)
		if !read_ok || copied != u64(take) do return false
		for byte in scratch[:int(take)] {
			if !seen_initial {
				if macro && byte == '_' do continue
				if byte < 'A' || byte > 'Z' do return false
				seen_initial = true
				continue
			}
			if capitalized {
				if !tree_sitter_ascii_alphanumeric(byte) do return false
			} else if !((byte >= 'A' && byte <= 'Z') || (byte >= '0' && byte <= '9') || byte == '_') {
				return false
			}
		}
		offset += take
	}
	return seen_initial
}

@(private)
tree_sitter_ascii_alphanumeric :: proc(value: u8) -> bool {
	return (value >= 'A' && value <= 'Z') || (value >= 'a' && value <= 'z') ||
	       (value >= '0' && value <= '9')
}
