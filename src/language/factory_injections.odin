// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language

import "../editor"

/* MAX_FACTORY_INJECTION_CAPTURES bounds embedded regions returned by one factory query. */
MAX_FACTORY_INJECTION_CAPTURES :: 256

/* Factory_Injection_Capture is one bounded embedded-language query result. */
Factory_Injection_Capture :: struct {
	start:       editor.Byte_Offset,
	end:         editor.Byte_Offset,
	language_id: Language_ID,
	priority:    u16,
}

/* Factory_Injection_Inspection copies all admitted captures without foreign pointers. */
Factory_Injection_Inspection :: struct {
	captures: [MAX_FACTORY_INJECTION_CAPTURES]Factory_Injection_Capture,
	count:    u16,
}

/* tree_sitter_owner_query_factory_injections extracts maintained embedded regions. */
tree_sitter_owner_query_factory_injections :: proc(
	owner: ^Tree_Sitter_Owner,
	source: ^editor.Buffer_Snapshot,
) -> (inspection: Factory_Injection_Inspection, ok: bool, failure: Failure) {
	state := tree_sitter_owner_state(owner)
	if state == nil || source == nil || state.tree == nil || state.cursor == nil ||
	   state.confirmed.status != .Current {
		return {}, false, tree_sitter_failure(.Publish_Syntax, .Parser_Initialization)
	}
	query: rawptr
	for candidate, index in state.provider_queries[:state.provider_query_count] {
		if state.provider_query_kinds[index] == .Injections {
			query = candidate
			break
		}
	}
	if query == nil do return {}, true, {}
	source_stats, source_ok, _ := editor.buffer_snapshot_stats(source)
	if !source_ok || source_stats.buffer_id != state.confirmed.buffer_id ||
	   source_stats.revision != state.confirmed.source_revision ||
	   source_stats.text_bytes != state.confirmed.usage.retained_source_bytes {
		return {}, false, tree_sitter_failure(.Publish_Syntax, .Unavailable_Base_Snapshot)
	}
	if source_stats.text_bytes > u64(max(u32)) {
		failure = tree_sitter_failure(.Publish_Syntax, .Work_Limit)
		failure.limit = u64(max(u32))
		failure.actual = source_stats.text_bytes
		return {}, false, failure
	}
	tree_sitter_memory_begin(state)
	defer tree_sitter_memory_end()
	ts_query_cursor_set_match_limit(state.cursor, MAX_FACTORY_INJECTION_CAPTURES)
	if !ts_query_cursor_set_byte_range(state.cursor, 0, u32(source_stats.text_bytes)) {
		return {}, false, tree_sitter_failure(.Publish_Syntax, .Invalid_Transaction)
	}
	ts_query_cursor_exec(state.cursor, query, ts_tree_root_node(state.tree))
	match: Tree_Sitter_Query_Match
	capture_index: u32
	for ts_query_cursor_next_capture(state.cursor, &match, &capture_index) {
		if capture_index >= u32(match.capture_count) || match.captures == nil {
			return {}, false, tree_sitter_failure(.Publish_Syntax, .Invalid_Capture_Mapping)
		}
		if inspection.count >= MAX_FACTORY_INJECTION_CAPTURES {
			failure = tree_sitter_failure(.Publish_Syntax, .Capture_Limit)
			failure.limit = MAX_FACTORY_INJECTION_CAPTURES
			failure.actual = u64(inspection.count) + 1
			return {}, false, failure
		}
		capture := match.captures[capture_index]
		length: u32
		name_pointer := ts_query_capture_name_for_id(query, capture.index, &length)
		if name_pointer == nil || length == 0 {
			return {}, false, tree_sitter_failure(.Publish_Syntax, .Invalid_Capture_Mapping)
		}
		name := string((cast([^]u8)name_pointer)[:length])
		language_id := Language_ID(0)
		priority := u16(0)
		switch name {
		case "injection.javascript":
			language_id = FACTORY_JAVASCRIPT_LANGUAGE_ID
			priority = 200
		case "injection.css":
			language_id = FACTORY_CSS_LANGUAGE_ID
			priority = 190
		case:
			continue
		}
		start := ts_node_start_byte(capture.node)
		end := ts_node_end_byte(capture.node)
		if start >= end || u64(end) > source_stats.text_bytes {
			return {}, false, tree_sitter_failure(.Publish_Syntax, .Invalid_Capture_Mapping)
		}
		inspection.captures[inspection.count] = {
			start = editor.Byte_Offset(start),
			end = editor.Byte_Offset(end),
			language_id = language_id,
			priority = priority,
		}
		inspection.count += 1
	}
	if ts_query_cursor_did_exceed_match_limit(state.cursor) {
		failure = tree_sitter_failure(.Publish_Syntax, .Capture_Limit)
		failure.limit = MAX_FACTORY_INJECTION_CAPTURES
		failure.actual = MAX_FACTORY_INJECTION_CAPTURES + 1
		return {}, false, failure
	}
	return inspection, true, {}
}
