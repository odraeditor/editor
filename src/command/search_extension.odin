// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../editor"
import "../kill_ring"
import "../search"
import "base:runtime"
import "core:unicode"
import "core:unicode/utf8"

/* Search_Extension_Unit identifies one admitted source of query text. */
Search_Extension_Unit :: enum u8 {
	Invalid,
	Textual,
	Structural,
	Transferred,
}

/* Search_Query_Extension owns copied query text until explicit close. */
Search_Query_Extension :: struct {
	unit:      Search_Extension_Unit,
	text:      string,
	allocator: runtime.Allocator,
}

/* search_query_extend_nearby copies the next meaningful bounded source unit. */
search_query_extend_nearby :: proc(
	buffer: ^editor.Buffer,
	origin: editor.Byte_Offset,
	unit: Search_Extension_Unit,
	kind: search.Pattern_Kind,
	byte_limit: u64,
	allocator: runtime.Allocator,
	temporary_allocator: runtime.Allocator,
) -> (extension: Search_Query_Extension, available: bool, failure: Failure_Context) {
	if buffer == nil || (unit != .Textual && unit != .Structural) ||
	   (kind != .Literal && kind != .Regular_Expression) || byte_limit == 0 ||
	   allocator.procedure == nil || temporary_allocator.procedure == nil {
		return {}, false, Failure_Context{code = .Invalid_Request}
	}
	stats, stats_ok, stats_failure := editor.buffer_stats(buffer)
	if !stats_ok {
		return {}, false, native_editor_failure({}, stats_failure)
	}
	if u64(origin) > stats.text_bytes {
		return {}, false, Failure_Context {
			code = .Invalid_Request,
			buffer_id = stats.buffer_id,
			revision = stats.revision,
			limit = stats.text_bytes,
			actual = u64(origin),
		}
	}
	_, positioned, position_failure := editor.buffer_position(buffer, origin)
	if !positioned {
		return {}, false, native_editor_failure({}, position_failure)
	}
	read_bytes := min(stats.text_bytes - u64(origin), search.DEFAULT_SCAN_WINDOW_BYTES)
	if read_bytes == 0 {
		return {}, false, {}
	}
	scratch, scratch_error := make([]u8, int(read_bytes), temporary_allocator)
	if scratch_error != nil {
		return {}, false, Failure_Context {
			code = .Temporary_Memory_Limit,
			limit = search.DEFAULT_SCAN_WINDOW_BYTES,
			actual = read_bytes,
		}
	}
	defer delete(scratch, temporary_allocator)
	snapshot: editor.Buffer_Snapshot
	opened, open_failure := editor.buffer_snapshot_open(buffer, &snapshot)
	if !opened {
		return {}, false, native_editor_failure({}, open_failure)
	}
	defer editor.buffer_snapshot_close(&snapshot)
	copied, read_ok, read_failure := editor.buffer_snapshot_read(&snapshot, origin, scratch)
	if !read_ok || copied != read_bytes {
		return {}, false, native_editor_failure({}, read_failure)
	}
	start, end := search_extension_range(scratch, unit)
	if start == end {
		return {}, false, {}
	}
	text := string(scratch[start:end])
	return search_query_extension_copy(unit, text, kind, byte_limit, allocator)
}

/* search_query_extend_transfer copies the newest retained text without rotating it. */
search_query_extend_transfer :: proc(
	ring: ^kill_ring.Ring,
	kind: search.Pattern_Kind,
	byte_limit: u64,
	allocator: runtime.Allocator,
) -> (extension: Search_Query_Extension, available: bool, failure: Failure_Context) {
	if ring == nil || !kill_ring.ring_is_valid(ring) ||
	   (kind != .Literal && kind != .Regular_Expression) || byte_limit == 0 ||
	   allocator.procedure == nil {
		return {}, false, Failure_Context{code = .Invalid_Request}
	}
	stats, stats_ok, stats_failure := kill_ring.ring_stats(ring)
	if !stats_ok {
		return {}, false, native_kill_ring_failure({}, stats_failure)
	}
	if stats.newest == kill_ring.Entry_ID(0) {
		return {}, false, {}
	}
	copy_limit := min(byte_limit, stats.policy.entry_bytes)
	entry, copied, copy_failure := kill_ring.entry_copy(
		ring,
		kill_ring.Entry_Copy_Request {
			expected_generation = stats.generation,
			entry_id = stats.newest,
			byte_limit = copy_limit,
		},
		allocator,
	)
	if !copied {
		return {}, false, native_kill_ring_failure({}, copy_failure)
	}
	defer kill_ring.entry_copy_release(&entry, allocator)
	return search_query_extension_copy(.Transferred, entry.text, kind, byte_limit, allocator)
}

/* search_query_extension_close releases copied query text. */
search_query_extension_close :: proc(extension: ^Search_Query_Extension) {
	if extension == nil {
		return
	}
	if len(extension.text) > 0 && extension.allocator.procedure != nil {
		delete(transmute([]u8)extension.text, extension.allocator)
	}
	extension^ = {}
}

@(private)
search_extension_range :: proc(bytes: []u8, unit: Search_Extension_Unit) -> (int, int) {
	start := 0
	for start < len(bytes) {
		value, width := utf8.decode_rune(bytes[start:])
		if width <= 0 {
			return 0, 0
		}
		eligible := !unicode.is_space(value)
		if unit == .Textual {
			eligible = search_extension_word_rune(value)
		}
		if eligible {
			break
		}
		start += width
	}
	end := start
	for end < len(bytes) {
		value, width := utf8.decode_rune(bytes[end:])
		if width <= 0 {
			return 0, 0
		}
		eligible := !unicode.is_space(value)
		if unit == .Textual {
			eligible = search_extension_word_rune(value)
		}
		if !eligible {
			break
		}
		end += width
	}
	return start, end
}

@(private)
search_extension_word_rune :: proc(value: rune) -> bool {
	return unicode.is_letter(value) || unicode.is_number(value) || value == '_'
}

@(private)
search_query_extension_copy :: proc(
	unit: Search_Extension_Unit,
	text: string,
	kind: search.Pattern_Kind,
	byte_limit: u64,
	allocator: runtime.Allocator,
) -> (Search_Query_Extension, bool, Failure_Context) {
	required := len(text)
	if kind == .Regular_Expression {
		for byte in transmute([]u8)text {
			if search_extension_regexp_metacharacter(byte) {
				required += 1
			}
		}
	}
	if u64(required) > byte_limit {
		return {}, false, Failure_Context {
			code = .Text_Limit,
			limit = byte_limit,
			actual = u64(required),
		}
	}
	copied, copy_error := make([]u8, required, allocator)
	if copy_error != nil {
		return {}, false, Failure_Context{code = .Temporary_Memory_Limit, actual = u64(required)}
	}
	offset := 0
	for byte in transmute([]u8)text {
		if kind == .Regular_Expression && search_extension_regexp_metacharacter(byte) {
			copied[offset] = '\\'
			offset += 1
		}
		copied[offset] = byte
		offset += 1
	}
	return Search_Query_Extension {
		unit = unit,
		text = string(copied),
		allocator = allocator,
	}, true, {}
}

@(private)
search_extension_regexp_metacharacter :: proc(value: u8) -> bool {
	switch value {
	case '.', '^', '$', '*', '+', '?', '(', ')', '[', ']', '{', '}', '\\', '|':
		return true
	}
	return false
}
