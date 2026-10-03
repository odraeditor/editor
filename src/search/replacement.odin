// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package search

import "../editor"
import "base:runtime"
import "core:unicode"
import "core:unicode/utf8"

@(private)
Replacement_Template_State :: struct {
	query_id:               Query_ID,
	pattern_kind:           Pattern_Kind,
	effective_case:         Effective_Case,
	text:                   []byte,
	policy:                 Replacement_Policy,
	limits:                 Replacement_Limits,
	defined_capture_groups: u16,
	has_uppercase_literal:  bool,
	allocator:              runtime.Allocator,
}

@(private)
Replacement_Expansion_State :: struct {
	text:      []byte,
	adapted:   bool,
	usage:     Replacement_Usage,
	allocator: runtime.Allocator,
}

@(private)
Replacement_Case_Shape :: enum u8 {
	None,
	Upper,
	Capitalized,
}

/* replacement_limits_are_valid reports whether expansion bounds coexist safely. */
replacement_limits_are_valid :: proc(limits: Replacement_Limits) -> bool {
	return limits.template_bytes >= MIN_REPLACEMENT_TEMPLATE_BYTES &&
	       limits.template_bytes <= MAX_REPLACEMENT_TEMPLATE_BYTES &&
	       limits.expanded_bytes >= MIN_EXPANDED_REPLACEMENT_BYTES &&
	       limits.expanded_bytes <= MAX_EXPANDED_REPLACEMENT_BYTES &&
	       limits.temporary_bytes >= MIN_REPLACEMENT_TEMPORARY_BYTES &&
	       limits.temporary_bytes <= MAX_REPLACEMENT_TEMPORARY_BYTES &&
	       limits.temporary_bytes >= limits.expanded_bytes
}

/* replacement_template_init copies and admits a template for one live query. */
replacement_template_init :: proc(
	template: ^Replacement_Template,
	query: ^Query,
	config: Replacement_Template_Config,
) -> (ok: bool, failure: Failure) {
	assert(template != nil)
	assert(template.state == nil, "replacement template is already initialized")
	query_value, viewed, query_failure := query_view(query)
	if !viewed {
		return false, query_failure
	}
	if config.policy.case_preservation != .None && config.policy.case_preservation != .Smart {
		return false, Failure{code = .Invalid_Case_Preservation, query_id = query_value.id}
	}
	if !replacement_limits_are_valid(config.limits) {
		return false, Failure{code = .Invalid_Limits, query_id = query_value.id}
	}
	if config.limits.temporary_bytes < query_value.limits.match_span_bytes {
		return false, Failure {
			code = .Invalid_Limits,
			query_id = query_value.id,
			limit = query_value.limits.match_span_bytes,
			actual = config.limits.temporary_bytes,
		}
	}
	if !utf8.valid_string(config.text) {
		return false, Failure {
			code = .Malformed_UTF8,
			query_id = query_value.id,
			actual = u64(len(config.text)),
		}
	}
	if u64(len(config.text)) > config.limits.template_bytes {
		return false, Failure {
			code = .Replacement_Template_Limit,
			query_id = query_value.id,
			limit = config.limits.template_bytes,
			actual = u64(len(config.text)),
		}
	}
	if query_value.kind == .Regular_Expression {
		valid, template_failure := validate_regexp_template(
			config.text,
			query_value.id,
			query_value.regex.defined_capture_groups,
		)
		if !valid {
			return false, template_failure
		}
	}
	if config.allocator.procedure == nil {
		return false, Failure{code = .Persistent_Memory_Limit, query_id = query_value.id}
	}
	state, state_error := new(Replacement_Template_State, config.allocator)
	if state_error != nil {
		return false, Failure {
			code = .Persistent_Memory_Limit,
			query_id = query_value.id,
			actual = u64(size_of(Replacement_Template_State)),
		}
	}
	text, text_error := make([]byte, len(config.text), config.allocator)
	if text_error != nil {
		free(state, config.allocator)
		return false, Failure {
			code = .Persistent_Memory_Limit,
			query_id = query_value.id,
			actual = u64(len(config.text)),
		}
	}
	copy(text, config.text)
	state.query_id = query_value.id
	state.pattern_kind = query_value.kind
	state.effective_case = query_value.effective_case
	state.text = text
	state.policy = config.policy
	state.limits = config.limits
	state.defined_capture_groups = query_value.regex.defined_capture_groups
	state.has_uppercase_literal = contains_uppercase_literal(config.text)
	state.allocator = config.allocator
	template.state = state
	return true, {}
}

/* replacement_template_view borrows one live template's admitted values. */
replacement_template_view :: proc(
	template: ^Replacement_Template,
) -> (view: Replacement_Template_View, ok: bool, failure: Failure) {
	state := replacement_template_state(template)
	if state == nil {
		return {}, false, Failure{code = .Closed_Replacement_Template}
	}
	return Replacement_Template_View {
		query_id = state.query_id,
		pattern_kind = state.pattern_kind,
		text = string(state.text),
		policy = state.policy,
		limits = state.limits,
		defined_capture_groups = state.defined_capture_groups,
		has_uppercase_literal = state.has_uppercase_literal,
	}, true, {}
}

/* replacement_template_close releases copied input and invalidates its handle. */
replacement_template_close :: proc(
	template: ^Replacement_Template,
) -> (ok: bool, failure: Failure) {
	state := replacement_template_state(template)
	if state == nil {
		return false, Failure{code = .Closed_Replacement_Template}
	}
	allocator := state.allocator
	query_id := state.query_id
	delete(state.text, allocator)
	template.state = nil
	free(state, allocator)
	return true, Failure{query_id = query_id}
}

/*
replacement_expand produces one owned occurrence-specific value without mutation.
The occurrence and flattened captures must belong to the supplied immutable snapshot.
*/
replacement_expand :: proc(
	expansion: ^Replacement_Expansion,
	snapshot: ^editor.Buffer_Snapshot,
	template: ^Replacement_Template,
	occurrence: Occurrence,
	captures: []Capture,
	allocators: Allocator_Set,
) -> (ok: bool, failure: Failure) {
	assert(expansion != nil)
	assert(expansion.state == nil, "replacement expansion is already initialized")
	state := replacement_template_state(template)
	if state == nil {
		return false, Failure{code = .Closed_Replacement_Template}
	}
	if allocators.persistent.procedure == nil {
		return false, Failure{code = .Persistent_Memory_Limit, query_id = state.query_id}
	}
	if allocators.temporary.procedure == nil {
		return false, Failure{code = .Temporary_Memory_Limit, query_id = state.query_id}
	}
	snapshot_stats, snapshot_ok, _ := editor.buffer_snapshot_stats(snapshot)
	if !snapshot_ok {
		return false, Failure{code = .Closed_Snapshot, query_id = state.query_id}
	}
	valid, occurrence_failure := validate_replacement_occurrence(
		state,
		occurrence,
		captures,
		snapshot_stats,
	)
	if !valid {
		return false, occurrence_failure
	}

	usage: Replacement_Usage
	boundary_reads, boundaries_valid := replacement_ranges_are_utf8_aligned(
		snapshot,
		occurrence,
		captures,
		snapshot_stats.text_bytes,
	)
	if !boundaries_valid {
		return false, Failure {
			code = .Out_Of_Range,
			buffer_id = occurrence.buffer_id,
			revision = occurrence.revision,
			query_id = state.query_id,
		}
	}
	usage.source_bytes = boundary_reads
	shape: Replacement_Case_Shape
	if state.policy.case_preservation == .Smart &&
	   state.effective_case == .Insensitive &&
	   !state.has_uppercase_literal {
		match_bytes := u64(occurrence.end) - u64(occurrence.start)
		if match_bytes > state.limits.temporary_bytes {
			return false, Failure {
				code = .Temporary_Memory_Limit,
				query_id = state.query_id,
				limit = state.limits.temporary_bytes,
				actual = match_bytes,
			}
		}
		match_text, match_error := make([]byte, int(match_bytes), allocators.temporary)
		if match_error != nil {
			return false, Failure {
				code = .Temporary_Memory_Limit,
				query_id = state.query_id,
				actual = match_bytes,
			}
		}
		read, read_ok := read_snapshot_range(snapshot, occurrence.start, occurrence.end, match_text)
		if !read_ok {
			delete(match_text, allocators.temporary)
			return false, Failure{code = .Out_Of_Range, query_id = state.query_id}
		}
		usage.source_bytes += read
		usage.temporary_peak_bytes = match_bytes
		if !utf8.valid_string(string(match_text)) {
			delete(match_text, allocators.temporary)
			return false, Failure{code = .Malformed_UTF8, query_id = state.query_id}
		}
		shape = replacement_case_shape(string(match_text))
		delete(match_text, allocators.temporary)
	}

	raw_bytes, measured, measure_failure := measure_replacement(state, occurrence, captures)
	if !measured {
		return false, measure_failure
	}
	if raw_bytes > state.limits.expanded_bytes {
		return false, Failure {
			code = .Expansion_Limit,
			query_id = state.query_id,
			limit = state.limits.expanded_bytes,
			actual = raw_bytes,
		}
	}

	if shape == .None {
		return write_expansion(
			expansion,
			snapshot,
			state,
			occurrence,
			captures,
			raw_bytes,
			&usage,
			allocators,
		)
	}
	if raw_bytes > state.limits.temporary_bytes {
		return false, Failure {
			code = .Temporary_Memory_Limit,
			query_id = state.query_id,
			limit = state.limits.temporary_bytes,
			actual = raw_bytes,
		}
	}
	raw_text, raw_error := make([]byte, int(raw_bytes), allocators.temporary)
	if raw_error != nil {
		return false, Failure {
			code = .Temporary_Memory_Limit,
			query_id = state.query_id,
			actual = raw_bytes,
		}
	}
	defer delete(raw_text, allocators.temporary)
	usage.temporary_peak_bytes = max(usage.temporary_peak_bytes, raw_bytes)
	written, wrote, write_failure := fill_raw_replacement(
		raw_text,
		snapshot,
		state,
		occurrence,
		captures,
	)
	if !wrote {
		return false, write_failure
	}
	usage.source_bytes += written.source_bytes
	if !utf8.valid_string(string(raw_text)) {
		return false, Failure{code = .Malformed_UTF8, query_id = state.query_id}
	}
	adapted_bytes, adapted_ok := transformed_utf8_bytes(string(raw_text), shape)
	if !adapted_ok {
		return false, Failure{code = .Arithmetic_Overflow, query_id = state.query_id}
	}
	if adapted_bytes > state.limits.expanded_bytes {
		return false, Failure {
			code = .Expansion_Limit,
			query_id = state.query_id,
			limit = state.limits.expanded_bytes,
			actual = adapted_bytes,
		}
	}
	return write_transformed_expansion(
		expansion,
		raw_text,
		state,
		shape,
		adapted_bytes,
		&usage,
		allocators.persistent,
	)
}

/* replacement_expansion_view borrows one live expanded value. */
replacement_expansion_view :: proc(
	expansion: ^Replacement_Expansion,
) -> (view: Replacement_Expansion_View, ok: bool, failure: Failure) {
	state := replacement_expansion_state(expansion)
	if state == nil {
		return {}, false, Failure{code = .Closed_Replacement_Expansion}
	}
	return Replacement_Expansion_View {
		text = string(state.text),
		adapted = state.adapted,
		usage = state.usage,
	}, true, {}
}

/* replacement_expansion_close releases expanded text and invalidates its handle. */
replacement_expansion_close :: proc(
	expansion: ^Replacement_Expansion,
) -> (ok: bool, failure: Failure) {
	state := replacement_expansion_state(expansion)
	if state == nil {
		return false, Failure{code = .Closed_Replacement_Expansion}
	}
	allocator := state.allocator
	delete(state.text, allocator)
	expansion.state = nil
	free(state, allocator)
	return true, {}
}

@(private)
validate_regexp_template :: proc(
	text: string,
	query_id: Query_ID,
	defined_capture_groups: u16,
) -> (bool, Failure) {
	bytes := transmute([]byte)text
	for index := 0; index < len(bytes); {
		if bytes[index] != '\\' {
			index += 1
			continue
		}
		reference, next, kind, escape_failure := parse_template_escape(bytes, index)
		if escape_failure != .None {
			return false, Failure {
				code = escape_failure,
				query_id = query_id,
				actual = u64(index),
			}
		}
		if kind == .Capture && reference > u64(defined_capture_groups) {
			return false, Failure {
				code = .Capture_Reference,
				query_id = query_id,
				limit = u64(defined_capture_groups),
				actual = reference,
			}
		}
		index = next
	}
	return true, {}
}

@(private)
Template_Escape_Kind :: enum u8 {
	Literal_Backslash,
	Whole_Match,
	Capture,
}

@(private)
parse_template_escape :: proc(
	bytes: []byte,
	index: int,
) -> (reference: u64, next: int, kind: Template_Escape_Kind, failure: Failure_Code) {
	if index + 1 >= len(bytes) || bytes[index] != '\\' {
		return 0, index, {}, .Malformed_Replacement_Template
	}
	next_byte := bytes[index + 1]
	if next_byte == '\\' {
		return 0, index + 2, .Literal_Backslash, .None
	}
	if next_byte == '&' {
		return 0, index + 2, .Whole_Match, .None
	}
	if next_byte < '1' || next_byte > '9' {
		return 0, index, {}, .Malformed_Replacement_Template
	}
	value := u64(0)
	next = index + 1
	for next < len(bytes) && bytes[next] >= '0' && bytes[next] <= '9' {
		digit := u64(bytes[next] - '0')
		if value > (max(u64) - digit) / 10 {
			return 0, index, {}, .Arithmetic_Overflow
		}
		value = value * 10 + digit
		next += 1
	}
	return value, next, .Capture, .None
}

@(private)
validate_replacement_occurrence :: proc(
	state: ^Replacement_Template_State,
	occurrence: Occurrence,
	captures: []Capture,
	snapshot: editor.Buffer_Snapshot_Stats,
) -> (bool, Failure) {
	if occurrence.buffer_id != snapshot.buffer_id {
		return false, Failure{code = .Wrong_Buffer, buffer_id = occurrence.buffer_id, revision = occurrence.revision, query_id = state.query_id}
	}
	if occurrence.revision != snapshot.revision {
		return false, Failure{code = .Stale_Revision, buffer_id = occurrence.buffer_id, revision = occurrence.revision, query_id = state.query_id, actual = u64(snapshot.revision)}
	}
	start, end := u64(occurrence.start), u64(occurrence.end)
	if start > end || end > snapshot.text_bytes {
		return false, Failure{code = .Out_Of_Range, buffer_id = occurrence.buffer_id, revision = occurrence.revision, query_id = state.query_id, limit = snapshot.text_bytes, actual = max(start, end)}
	}
	capture_start := u64(occurrence.first_capture)
	capture_end, capture_ok := checked_add_u64(capture_start, u64(occurrence.capture_count))
	if !capture_ok {
		return false, Failure{code = .Arithmetic_Overflow, query_id = state.query_id}
	}
	if capture_end > u64(len(captures)) {
		return false, Failure{code = .Out_Of_Range, query_id = state.query_id, limit = u64(len(captures)), actual = capture_end}
	}
	seen: [MAX_CAPTURE_GROUPS]bool
	for capture in captures[int(capture_start):int(capture_end)] {
		capture_range_start, capture_range_end := u64(capture.start), u64(capture.end)
		if capture.group >= MAX_CAPTURE_GROUPS ||
		   (capture.group > 0 && capture.group > state.defined_capture_groups) {
			return false, Failure{code = .Capture_Reference, query_id = state.query_id, limit = u64(state.defined_capture_groups), actual = u64(capture.group)}
		}
		if seen[capture.group] {
			return false, Failure{code = .Capture_Reference, query_id = state.query_id, actual = u64(capture.group)}
		}
		seen[capture.group] = true
		if capture_range_start < start || capture_range_start > capture_range_end || capture_range_end > end {
			return false, Failure{code = .Out_Of_Range, query_id = state.query_id, limit = end, actual = max(capture_range_start, capture_range_end)}
		}
	}
	return true, {}
}

@(private)
replacement_ranges_are_utf8_aligned :: proc(
	snapshot: ^editor.Buffer_Snapshot,
	occurrence: Occurrence,
	captures: []Capture,
	text_bytes: u64,
) -> (reads: u64, ok: bool) {
	start_ok, start_reads := snapshot_offset_is_utf8_boundary(snapshot, occurrence.start, text_bytes)
	reads += start_reads
	if !start_ok {
		return reads, false
	}
	end_ok, end_reads := snapshot_offset_is_utf8_boundary(snapshot, occurrence.end, text_bytes)
	reads += end_reads
	if !end_ok {
		return reads, false
	}
	start := int(occurrence.first_capture)
	end := start + int(occurrence.capture_count)
	for capture in captures[start:end] {
		capture_start_ok, capture_start_reads := snapshot_offset_is_utf8_boundary(
			snapshot,
			capture.start,
			text_bytes,
		)
		reads += capture_start_reads
		if !capture_start_ok {
			return reads, false
		}
		capture_end_ok, capture_end_reads := snapshot_offset_is_utf8_boundary(
			snapshot,
			capture.end,
			text_bytes,
		)
		reads += capture_end_reads
		if !capture_end_ok {
			return reads, false
		}
	}
	return reads, true
}

@(private)
snapshot_offset_is_utf8_boundary :: proc(
	snapshot: ^editor.Buffer_Snapshot,
	offset: editor.Byte_Offset,
	text_bytes: u64,
) -> (ok: bool, reads: u64) {
	if u64(offset) == text_bytes {
		return true, 0
	}
	byte_value: [1]byte
	copied, read_ok, _ := editor.buffer_snapshot_read(snapshot, offset, byte_value[:])
	if !read_ok || copied != 1 {
		return false, copied
	}
	return utf8.rune_start(byte_value[0]), 1
}

@(private)
measure_replacement :: proc(
	state: ^Replacement_Template_State,
	occurrence: Occurrence,
	captures: []Capture,
) -> (bytes: u64, ok: bool, failure: Failure) {
	if state.pattern_kind == .Literal {
		return u64(len(state.text)), true, {}
	}
	for index := 0; index < len(state.text); {
		if state.text[index] != '\\' {
			next, add_ok := checked_add_u64(bytes, 1)
			if !add_ok {
				return 0, false, Failure{code = .Arithmetic_Overflow, query_id = state.query_id}
			}
			bytes = next
			index += 1
			continue
		}
		reference, next_index, kind, escape_failure := parse_template_escape(state.text, index)
		assert(escape_failure == .None)
		addition: u64
		switch kind {
		case .Literal_Backslash:
			addition = 1
		case .Whole_Match:
			addition = u64(occurrence.end) - u64(occurrence.start)
		case .Capture:
			capture, found := find_capture(occurrence, captures, u16(reference))
			if found {
				addition = u64(capture.end) - u64(capture.start)
			}
		}
		next, add_ok := checked_add_u64(bytes, addition)
		if !add_ok {
			return 0, false, Failure{code = .Arithmetic_Overflow, query_id = state.query_id}
		}
		bytes = next
		index = next_index
	}
	return bytes, true, {}
}

@(private)
write_expansion :: proc(
	expansion: ^Replacement_Expansion,
	snapshot: ^editor.Buffer_Snapshot,
	template: ^Replacement_Template_State,
	occurrence: Occurrence,
	captures: []Capture,
	bytes: u64,
	usage: ^Replacement_Usage,
	allocators: Allocator_Set,
) -> (bool, Failure) {
	state, state_error := new(Replacement_Expansion_State, allocators.persistent)
	if state_error != nil {
		return false, Failure{code = .Persistent_Memory_Limit, query_id = template.query_id, actual = u64(size_of(Replacement_Expansion_State))}
	}
	text, text_error := make([]byte, int(bytes), allocators.persistent)
	if text_error != nil {
		free(state, allocators.persistent)
		return false, Failure{code = .Persistent_Memory_Limit, query_id = template.query_id, actual = bytes}
	}
	written, wrote, write_failure := fill_raw_replacement(text, snapshot, template, occurrence, captures)
	if !wrote {
		delete(text, allocators.persistent)
		free(state, allocators.persistent)
		return false, write_failure
	}
	if !utf8.valid_string(string(text)) {
		delete(text, allocators.persistent)
		free(state, allocators.persistent)
		return false, Failure{code = .Malformed_UTF8, query_id = template.query_id}
	}
	usage.source_bytes += written.source_bytes
	usage.expanded_bytes = bytes
	state.text = text
	state.adapted = false
	state.usage = usage^
	state.allocator = allocators.persistent
	expansion.state = state
	return true, {}
}

@(private)
write_transformed_expansion :: proc(
	expansion: ^Replacement_Expansion,
	raw_text: []byte,
	template: ^Replacement_Template_State,
	shape: Replacement_Case_Shape,
	bytes: u64,
	usage: ^Replacement_Usage,
	allocator: runtime.Allocator,
) -> (bool, Failure) {
	state, state_error := new(Replacement_Expansion_State, allocator)
	if state_error != nil {
		return false, Failure{code = .Persistent_Memory_Limit, query_id = template.query_id, actual = u64(size_of(Replacement_Expansion_State))}
	}
	text, text_error := make([]byte, int(bytes), allocator)
	if text_error != nil {
		free(state, allocator)
		return false, Failure{code = .Persistent_Memory_Limit, query_id = template.query_id, actual = bytes}
	}
	write_transformed_utf8(text, string(raw_text), shape)
	usage.expanded_bytes = bytes
	state.text = text
	state.adapted = true
	state.usage = usage^
	state.allocator = allocator
	expansion.state = state
	return true, {}
}

@(private)
fill_raw_replacement :: proc(
	destination: []byte,
	snapshot: ^editor.Buffer_Snapshot,
	state: ^Replacement_Template_State,
	occurrence: Occurrence,
	captures: []Capture,
) -> (usage: Replacement_Usage, ok: bool, failure: Failure) {
	if state.pattern_kind == .Literal {
		copy(destination, state.text)
		return {}, true, {}
	}
	offset := 0
	for index := 0; index < len(state.text); {
		if state.text[index] != '\\' {
			destination[offset] = state.text[index]
			offset += 1
			index += 1
			continue
		}
		reference, next_index, kind, escape_failure := parse_template_escape(state.text, index)
		assert(escape_failure == .None)
		switch kind {
		case .Literal_Backslash:
			destination[offset] = '\\'
			offset += 1
		case .Whole_Match:
			read, read_ok := read_snapshot_range(snapshot, occurrence.start, occurrence.end, destination[offset:])
			if !read_ok {
				return usage, false, Failure{code = .Out_Of_Range, query_id = state.query_id}
			}
			offset += int(read)
			usage.source_bytes += read
		case .Capture:
			capture, found := find_capture(occurrence, captures, u16(reference))
			if found {
				read, read_ok := read_snapshot_range(snapshot, capture.start, capture.end, destination[offset:])
				if !read_ok {
					return usage, false, Failure{code = .Out_Of_Range, query_id = state.query_id}
				}
				offset += int(read)
				usage.source_bytes += read
			}
		}
		index = next_index
	}
	assert(offset == len(destination))
	return usage, true, {}
}

@(private)
read_snapshot_range :: proc(
	snapshot: ^editor.Buffer_Snapshot,
	start, end: editor.Byte_Offset,
	destination: []byte,
) -> (u64, bool) {
	bytes := u64(end) - u64(start)
	if bytes == 0 {
		return 0, true
	}
	copied, ok, _ := editor.buffer_snapshot_read(snapshot, start, destination[:int(bytes)])
	return copied, ok && copied == bytes
}

@(private)
find_capture :: proc(
	occurrence: Occurrence,
	captures: []Capture,
	group: u16,
) -> (Capture, bool) {
	start := int(occurrence.first_capture)
	end := start + int(occurrence.capture_count)
	for capture in captures[start:end] {
		if capture.group == group {
			return capture, true
		}
	}
	return {}, false
}

@(private)
contains_uppercase_literal :: proc(text: string) -> bool {
	for code_point in text {
		if unicode.is_upper(code_point) {
			return true
		}
	}
	return false
}

@(private)
replacement_case_shape :: proc(text: string) -> Replacement_Case_Shape {
	has_cased := false
	all_upper := true
	initial_upper := false
	rest_lower := true
	for code_point in text {
		if !unicode.is_upper(code_point) && !unicode.is_lower(code_point) {
			continue
		}
		if !has_cased {
			has_cased = true
			initial_upper = unicode.is_upper(code_point)
		} else if !unicode.is_lower(code_point) {
			rest_lower = false
		}
		if !unicode.is_upper(code_point) {
			all_upper = false
		}
	}
	if has_cased && all_upper {
		return .Upper
	}
	if has_cased && initial_upper && rest_lower {
		return .Capitalized
	}
	return .None
}

@(private)
transformed_utf8_bytes :: proc(text: string, shape: Replacement_Case_Shape) -> (u64, bool) {
	total: u64
	seen_cased := false
	for code_point in text {
		mapped := replacement_case_rune(code_point, shape, &seen_cased)
		_, width := utf8.encode_rune(mapped)
		next, ok := checked_add_u64(total, u64(width))
		if !ok {
			return 0, false
		}
		total = next
	}
	return total, true
}

@(private)
write_transformed_utf8 :: proc(destination: []byte, text: string, shape: Replacement_Case_Shape) {
	offset := 0
	seen_cased := false
	for code_point in text {
		mapped := replacement_case_rune(code_point, shape, &seen_cased)
		encoded, width := utf8.encode_rune(mapped)
		copy(destination[offset:], encoded[:width])
		offset += width
	}
	assert(offset == len(destination))
}

@(private)
replacement_case_rune :: proc(
	code_point: rune,
	shape: Replacement_Case_Shape,
	seen_cased: ^bool,
) -> rune {
	if shape == .Upper {
		return unicode.to_upper(code_point)
	}
	if shape != .Capitalized ||
	   (!unicode.is_upper(code_point) && !unicode.is_lower(code_point)) {
		return code_point
	}
	if !seen_cased^ {
		seen_cased^ = true
		return unicode.to_upper(code_point)
	}
	return unicode.to_lower(code_point)
}

@(private)
checked_add_u64 :: proc(left, right: u64) -> (u64, bool) {
	if right > max(u64) - left {
		return 0, false
	}
	return left + right, true
}

@(private)
replacement_template_state :: proc(template: ^Replacement_Template) -> ^Replacement_Template_State {
	if template == nil || template.state == nil {
		return nil
	}
	return (^Replacement_Template_State)(template.state)
}

@(private)
replacement_expansion_state :: proc(expansion: ^Replacement_Expansion) -> ^Replacement_Expansion_State {
	if expansion == nil || expansion.state == nil {
		return nil
	}
	return (^Replacement_Expansion_State)(expansion.state)
}
