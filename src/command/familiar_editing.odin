// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../display"
import "../document"
import "../editor"
import edit_transaction "../transaction"
import editor_view "../view"
import "base:runtime"
import "core:strings"
import "core:unicode"
import "core:unicode/utf8"

@(private)
Familiar_Case_Mode :: enum u8 {
	Upper,
	Lower,
	Capitalized,
}

@(private)
FAMILIAR_FILL_COLUMN :: u32(80)

@(private)
native_kill_line :: proc(
	request: Native_Context,
	logical: editor_view.Snapshot,
	command_name: string,
) -> (Native_Result, bool, Failure_Context) {
	if len(request.text) != 0 do return {}, false, familiar_invalid(request)
	line, line_ok, line_failure := editor.buffer_line_at_position(request.buffer, logical.point_position)
	if !line_ok do return {}, false, native_editor_failure(request.command, line_failure)
	end_offset := line.content_end
	if logical.point_position.byte_offset == line.content_end && line.next_start > line.content_end {
		end_offset = line.next_start
	}
	count := max(request.repeat_count, 1)
	for _ in 1 ..< count {
		if line.next_start == line.content_end do break
		probe, probe_ok, probe_failure := editor.buffer_position(request.buffer, line.next_start)
		if !probe_ok do return {}, false, native_editor_failure(request.command, probe_failure)
		line, line_ok, line_failure = editor.buffer_line_at_position(request.buffer, probe)
		if !line_ok do return {}, false, native_editor_failure(request.command, line_failure)
		end_offset = line.next_start
	}
	end, end_ok, end_failure := editor.buffer_position(request.buffer, end_offset)
	if !end_ok do return {}, false, native_editor_failure(request.command, end_failure)
	if end == logical.point_position do return Native_Result{completion = .No_Op}, true, {}
	remove := request
	remove.explicit_range = {
		present = true,
		start = logical.point_position,
		end = end,
	}
	return native_remove_region(remove, logical, true, command_name)
}

@(private)
native_kill_word :: proc(
	request: Native_Context,
	logical: editor_view.Snapshot,
	backward: bool,
	command_name: string,
) -> (Native_Result, bool, Failure_Context) {
	if len(request.text) != 0 do return {}, false, familiar_invalid(request)
	working := logical
	target := logical.point_position
	kind := display.Navigation_Kind.Next_Word
	if backward do kind = .Previous_Word
	count := max(request.repeat_count, 1)
	for _ in 0 ..< count {
		next, desired, next_ok, next_failure := display.navigation_target(
			request.buffer,
			working,
			kind,
			request.profile,
		)
		if !next_ok do return {}, false, native_display_failure(request.command, next_failure)
		if next == target do break
		target = next
		working.point_position = next
		working.desired_display_column = desired
	}
	if target == logical.point_position do return Native_Result{completion = .No_Op}, true, {}
	remove := request
	remove.explicit_range = {
		present = true,
		start = logical.point_position,
		end = target,
		backward = backward,
	}
	return native_remove_region(remove, logical, true, command_name)
}

@(private)
native_change_word_case :: proc(
	request: Native_Context,
	logical: editor_view.Snapshot,
	mode: Familiar_Case_Mode,
	command_name: string,
) -> (Native_Result, bool, Failure_Context) {
	if len(request.text) != 0 do return {}, false, familiar_invalid(request)
	start_range, found, range_ok, range_failure := display.word_selection_range(
		request.buffer,
		logical,
		request.profile,
	)
	if !range_ok do return {}, false, native_display_failure(request.command, range_failure)
	if !found do return Native_Result{completion = .No_Op}, true, {}
	end := start_range.end
	working := logical
	working.point_position = end
	for _ in 1 ..< max(request.repeat_count, 1) {
		next, _, next_ok, next_failure := display.navigation_target(
			request.buffer,
			working,
			.Next_Word,
			request.profile,
		)
		if !next_ok do return {}, false, native_display_failure(request.command, next_failure)
		if next == end do break
		end = next
		working.point_position = next
	}
	source, source_ok, source_failure := familiar_copy_range(
		request,
		start_range.start,
		end,
	)
	if !source_ok do return {}, false, source_failure
	defer delete(source, request.temporary_allocator)
	output_bytes: u64
	seen_cased := false
	for code_point in string(source) {
		mapped := familiar_case_rune(code_point, mode, &seen_cased)
		_, width := utf8.encode_rune(mapped)
		output_bytes += u64(width)
	}
	if output_bytes > editor.MAX_REPLACEMENT_BYTES || output_bytes > u64(max(int)) {
		return {}, false, Failure_Context{code = .Text_Limit, command = request.command, limit = editor.MAX_REPLACEMENT_BYTES, actual = output_bytes}
	}
	output, output_error := make([]u8, int(output_bytes), request.temporary_allocator)
	if output_error != nil do return {}, false, familiar_memory_failure(request, output_bytes)
	defer delete(output, request.temporary_allocator)
	offset := 0
	seen_cased = false
	for code_point in string(source) {
		mapped := familiar_case_rune(code_point, mode, &seen_cased)
		encoded, width := utf8.encode_rune(mapped)
		copy(output[offset:], encoded[:width])
		offset += width
	}
	return familiar_publish_range(
		request,
		logical,
		command_name,
		start_range.start,
		end,
		string(output),
		editor.Byte_Offset(u64(start_range.start.byte_offset) + output_bytes),
	)
}

@(private)
familiar_case_rune :: proc(code_point: rune, mode: Familiar_Case_Mode, seen_cased: ^bool) -> rune {
	switch mode {
	case .Upper:
		return unicode.to_upper(code_point)
	case .Lower:
		return unicode.to_lower(code_point)
	case .Capitalized:
		if !unicode.is_upper(code_point) && !unicode.is_lower(code_point) do return code_point
		if !seen_cased^ {
			seen_cased^ = true
			return unicode.to_upper(code_point)
		}
		return unicode.to_lower(code_point)
	}
	unreachable()
}

@(private)
native_transpose_words :: proc(
	request: Native_Context,
	logical: editor_view.Snapshot,
	command_name: string,
) -> (Native_Result, bool, Failure_Context) {
	if len(request.text) != 0 do return {}, false, familiar_invalid(request)
	left_point, _, left_ok, left_failure := display.navigation_target(
		request.buffer,
		logical,
		.Previous_Word,
		request.profile,
	)
	if !left_ok do return {}, false, native_display_failure(request.command, left_failure)
	left_logical := logical
	left_logical.point_position = left_point
	left, left_found, left_range_ok, left_range_failure := display.word_selection_range(
		request.buffer,
		left_logical,
		request.profile,
	)
	if !left_range_ok do return {}, false, native_display_failure(request.command, left_range_failure)
	if !left_found do return Native_Result{completion = .No_Op}, true, {}
	right_logical := logical
	right_logical.point_position = left.end
	right_point, _, right_ok, right_failure := display.navigation_target(
		request.buffer,
		right_logical,
		.Next_Word_Start,
		request.profile,
	)
	if !right_ok do return {}, false, native_display_failure(request.command, right_failure)
	right_logical.point_position = right_point
	right, right_found, right_range_ok, right_range_failure := display.word_selection_range(
		request.buffer,
		right_logical,
		request.profile,
	)
	if !right_range_ok do return {}, false, native_display_failure(request.command, right_range_failure)
	if !right_found || right.start.byte_offset <= left.start.byte_offset {
		return Native_Result{completion = .No_Op}, true, {}
	}
	span, span_ok, span_failure := familiar_copy_range(request, left.start, right.end)
	if !span_ok do return {}, false, span_failure
	defer delete(span, request.temporary_allocator)
	left_bytes := int(u64(left.end.byte_offset) - u64(left.start.byte_offset))
	right_start := int(u64(right.start.byte_offset) - u64(left.start.byte_offset))
	right_end := int(u64(right.end.byte_offset) - u64(left.start.byte_offset))
	output, output_error := make([]u8, len(span), request.temporary_allocator)
	if output_error != nil do return {}, false, familiar_memory_failure(request, u64(len(span)))
	defer delete(output, request.temporary_allocator)
	written := copy(output, span[right_start:right_end])
	written += copy(output[written:], span[left_bytes:right_start])
	written += copy(output[written:], span[:left_bytes])
	assert(written == len(output))
	return familiar_publish_range(request, logical, command_name, left.start, right.end, string(output), right.end.byte_offset)
}

@(private)
native_fill_paragraph :: proc(
	request: Native_Context,
	logical: editor_view.Snapshot,
	command_name: string,
) -> (Native_Result, bool, Failure_Context) {
	if len(request.text) != 0 do return {}, false, familiar_invalid(request)
	range, range_ok, range_failure := display.paragraph_selection_range(request.buffer, logical)
	if !range_ok do return {}, false, native_display_failure(request.command, range_failure)
	source, source_ok, source_failure := familiar_copy_range(request, range.start, range.end)
	if !source_ok do return {}, false, source_failure
	defer delete(source, request.temporary_allocator)
	output, output_error := make([]u8, len(source), request.temporary_allocator)
	if output_error != nil do return {}, false, familiar_memory_failure(request, u64(len(source)))
	defer delete(output, request.temporary_allocator)
	read := u64(0)
	written := 0
	column := u32(0)
	pending_space := false
	for read < u64(len(source)) {
		code_point, width := utf8.decode_rune(string(source[read:]))
		if width == 0 || code_point == utf8.RUNE_ERROR && width == 1 {
			return {}, false, Failure_Context{code = .Malformed_Text, command = request.command}
		}
		if unicode.is_space(code_point) {
			pending_space = written > 0
			read += u64(width)
			continue
		}
		word_start := read
		word_bytes := 0
		word_cells := u32(0)
		for read < u64(len(source)) {
			word_rune, word_width := utf8.decode_rune(string(source[read:]))
			if word_width == 0 || unicode.is_space(word_rune) do break
			word_cells += 1
			word_bytes += word_width
			read += u64(word_width)
		}
		if pending_space {
			separator := byte(' ')
			if column > 0 && column + 1 + word_cells > FAMILIAR_FILL_COLUMN {
				separator = '\n'
				column = 0
			} else {
				column += 1
			}
			output[written] = separator
			written += 1
		}
		copy(output[written:], source[word_start:word_start + u64(word_bytes)])
		written += word_bytes
		column += word_cells
		pending_space = false
	}
	if len(source) > 0 && source[len(source) - 1] == '\n' && written > 0 && output[written - 1] != '\n' {
		output[written] = '\n'
		written += 1
	}
	return familiar_publish_range(request, logical, command_name, range.start, range.end, string(output[:written]), range.start.byte_offset)
}

@(private)
native_delete_blank_lines :: proc(
	request: Native_Context,
	logical: editor_view.Snapshot,
	command_name: string,
) -> (Native_Result, bool, Failure_Context) {
	if len(request.text) != 0 do return {}, false, familiar_invalid(request)
	line, line_ok, line_failure := editor.buffer_line_at_position(request.buffer, logical.point_position)
	if !line_ok do return {}, false, native_editor_failure(request.command, line_failure)
	blank, blank_ok, blank_failure := familiar_line_blank(request, line)
	if !blank_ok do return {}, false, blank_failure
	started_on_blank := blank
	if !blank {
		if line.next_start == line.content_end do return Native_Result{completion = .No_Op}, true, {}
		probe, probe_ok, probe_failure := editor.buffer_position(request.buffer, line.next_start)
		if !probe_ok do return {}, false, native_editor_failure(request.command, probe_failure)
		line, line_ok, line_failure = editor.buffer_line_at_position(request.buffer, probe)
		if !line_ok do return {}, false, native_editor_failure(request.command, line_failure)
		blank, blank_ok, blank_failure = familiar_line_blank(request, line)
		if !blank_ok do return {}, false, blank_failure
		if !blank do return Native_Result{completion = .No_Op}, true, {}
	}
	first := line
	last := line
	for first.line_index > 0 {
		probe, probe_ok, probe_failure := editor.buffer_position(request.buffer, editor.Byte_Offset(u64(first.start) - 1))
		if !probe_ok do return {}, false, native_editor_failure(request.command, probe_failure)
		previous, previous_ok, previous_failure := editor.buffer_line_at_position(request.buffer, probe)
		if !previous_ok do return {}, false, native_editor_failure(request.command, previous_failure)
		previous_blank, previous_blank_ok, previous_blank_failure := familiar_line_blank(request, previous)
		if !previous_blank_ok do return {}, false, previous_blank_failure
		if !previous_blank do break
		first = previous
	}
	for last.next_start != last.content_end {
		probe, probe_ok, probe_failure := editor.buffer_position(request.buffer, last.next_start)
		if !probe_ok do return {}, false, native_editor_failure(request.command, probe_failure)
		next, next_ok, next_failure := editor.buffer_line_at_position(request.buffer, probe)
		if !next_ok do return {}, false, native_editor_failure(request.command, next_failure)
		next_blank, next_blank_ok, next_blank_failure := familiar_line_blank(request, next)
		if !next_blank_ok do return {}, false, next_blank_failure
		if !next_blank do break
		last = next
	}
	start, start_ok, start_failure := editor.buffer_position(request.buffer, first.start)
	if !start_ok do return {}, false, native_editor_failure(request.command, start_failure)
	end, end_ok, end_failure := editor.buffer_position(request.buffer, last.next_start)
	if !end_ok do return {}, false, native_editor_failure(request.command, end_failure)
	replacement := ""
	if started_on_blank && last.line_index > first.line_index {
		replacement = "\n"
	}
	return familiar_publish_range(request, logical, command_name, start, end, replacement, start.byte_offset)
}

@(private)
native_comment_dwim :: proc(
	request: Native_Context,
	logical: editor_view.Snapshot,
	command_name: string,
) -> (Native_Result, bool, Failure_Context) {
	if len(request.text) != 0 do return {}, false, familiar_invalid(request)
	target_context := Semantic_Target_Context{
		buffer = request.buffer,
		view_registry = request.view_registry,
		view = request.view,
		profile = request.profile,
		explicit_range = request.explicit_range,
	}
	kind := Semantic_Target_Kind.Line
	if request.explicit_range.present || logical.region_active do kind = .Active_Region
	target, target_ok, target_failure := semantic_target_resolve(target_context, kind)
	if !target_ok do return {}, false, familiar_target_failure(request, target_failure)
	source, source_ok, source_failure := familiar_copy_range(request, target.start, target.end)
	if !source_ok do return {}, false, source_failure
	defer delete(source, request.temporary_allocator)
	prefix, suffix := familiar_comment_delimiters(request.document)
	trimmed_start := 0
	for trimmed_start < len(source) && (source[trimmed_start] == ' ' || source[trimmed_start] == '\t') do trimmed_start += 1
	commented := strings.has_prefix(string(source[trimmed_start:]), prefix)
	if commented {
		remove_end := trimmed_start + len(prefix)
		if remove_end < len(source) && source[remove_end] == ' ' do remove_end += 1
		replacement_bytes := len(source) - (remove_end - trimmed_start)
		if len(suffix) > 0 {
			trimmed_end := len(source)
			for trimmed_end > 0 && unicode.is_space(rune(source[trimmed_end - 1])) do trimmed_end -= 1
			if trimmed_end >= len(suffix) && strings.has_suffix(string(source[:trimmed_end]), suffix) {
				replacement_bytes -= len(suffix)
			}
		}
		output, output_error := make([]u8, replacement_bytes, request.temporary_allocator)
		if output_error != nil do return {}, false, familiar_memory_failure(request, u64(replacement_bytes))
		defer delete(output, request.temporary_allocator)
		written := copy(output, source[:trimmed_start])
		body_end := len(source)
		if len(suffix) > 0 {
			trimmed_end := len(source)
			for trimmed_end > remove_end && (source[trimmed_end - 1] == ' ' || source[trimmed_end - 1] == '\t' || source[trimmed_end - 1] == '\n') do trimmed_end -= 1
			if trimmed_end >= len(suffix) && strings.has_suffix(string(source[:trimmed_end]), suffix) do body_end = trimmed_end - len(suffix)
		}
		written += copy(output[written:], source[remove_end:body_end])
		if body_end < len(source) do written += copy(output[written:], source[body_end + len(suffix):])
		return familiar_publish_range(request, logical, command_name, target.start, target.end, string(output[:written]), target.start.byte_offset)
	}
	extra := len(prefix) + 1 + len(suffix)
	output, output_error := make([]u8, len(source) + extra, request.temporary_allocator)
	if output_error != nil do return {}, false, familiar_memory_failure(request, u64(len(source) + extra))
	defer delete(output, request.temporary_allocator)
	written := copy(output, source[:trimmed_start])
	written += copy(output[written:], transmute([]u8)prefix)
	output[written] = ' '
	written += 1
	written += copy(output[written:], source[trimmed_start:])
	if len(suffix) > 0 do written += copy(output[written:], transmute([]u8)suffix)
	return familiar_publish_range(request, logical, command_name, target.start, target.end, string(output[:written]), target.start.byte_offset)
}

@(private)
native_dynamic_abbrev_expand :: proc(
	request: Native_Context,
	logical: editor_view.Snapshot,
	command_name: string,
) -> (Native_Result, bool, Failure_Context) {
	if len(request.text) != 0 do return {}, false, familiar_invalid(request)
	stats, stats_ok, stats_failure := editor.buffer_stats(request.buffer)
	if !stats_ok do return {}, false, native_editor_failure(request.command, stats_failure)
	if stats.text_bytes == 0 || stats.text_bytes > editor.MAX_REPLACEMENT_BYTES || stats.text_bytes > u64(max(int)) {
		return Native_Result{completion = .No_Op}, true, {}
	}
	start, start_ok, start_failure := editor.buffer_position(request.buffer, 0)
	if !start_ok do return {}, false, native_editor_failure(request.command, start_failure)
	end, end_ok, end_failure := editor.buffer_position(request.buffer, editor.Byte_Offset(stats.text_bytes))
	if !end_ok do return {}, false, native_editor_failure(request.command, end_failure)
	text, text_ok, text_failure := familiar_copy_range(request, start, end)
	if !text_ok do return {}, false, text_failure
	defer delete(text, request.temporary_allocator)
	point := int(logical.point_position.byte_offset)
	prefix_start := point
	for prefix_start > 0 {
		candidate := prefix_start - 1
		for candidate > 0 && (text[candidate] & 0xc0) == 0x80 do candidate -= 1
		code_point, width := utf8.decode_rune(string(text[candidate:prefix_start]))
		if width == 0 || !familiar_word_rune(code_point) do break
		prefix_start = candidate
	}
	if prefix_start == point do return Native_Result{completion = .No_Op}, true, {}
	prefix := string(text[prefix_start:point])
	best_start, best_end := -1, -1
	word_start := -1
	parsed := 0
	for parsed < prefix_start {
		code_point, width := utf8.decode_rune(string(text[parsed:]))
		if width == 0 do break
		word := familiar_word_rune(code_point)
		if word && word_start < 0 do word_start = parsed
		if !word && word_start >= 0 {
			if parsed - word_start > len(prefix) && strings.has_prefix(string(text[word_start:parsed]), prefix) {
				best_start, best_end = word_start, parsed
			}
			word_start = -1
		}
		parsed += width
	}
	if word_start >= 0 && prefix_start - word_start > len(prefix) && strings.has_prefix(string(text[word_start:prefix_start]), prefix) {
		best_start, best_end = word_start, prefix_start
	}
	if best_start < 0 do return Native_Result{completion = .No_Op}, true, {}
	replace_start, replace_start_ok, replace_start_failure := editor.buffer_position(request.buffer, editor.Byte_Offset(prefix_start))
	if !replace_start_ok do return {}, false, native_editor_failure(request.command, replace_start_failure)
	return familiar_publish_range(
		request,
		logical,
		command_name,
		replace_start,
		logical.point_position,
		string(text[best_start:best_end]),
		editor.Byte_Offset(u64(prefix_start + best_end - best_start)),
	)
}

@(private)
familiar_comment_delimiters :: proc(owner: ^document.Document) -> (string, string) {
	if owner == nil do return "//", ""
	status, status_ok, _ := document.document_status(owner)
	if !status_ok || !status.has_target do return "//", ""
	path := status.target_path
	if strings.has_suffix(path, ".rkt") || strings.has_suffix(path, ".scrbl") do return ";", ""
	if strings.has_suffix(path, ".org") || strings.has_suffix(path, ".jan") do return "#", ""
	if strings.has_suffix(path, ".html") || strings.has_suffix(path, ".htm") do return "<!--", "-->"
	if strings.has_suffix(path, ".css") do return "/*", "*/"
	return "//", ""
}

@(private)
familiar_word_rune :: proc(value: rune) -> bool {
	return unicode.is_letter(value) || unicode.is_digit(value) || value == '_'
}

@(private)
familiar_line_blank :: proc(
	request: Native_Context,
	line: editor.Buffer_Line,
) -> (bool, bool, Failure_Context) {
	start, start_ok, start_failure := editor.buffer_position(request.buffer, line.start)
	if !start_ok do return false, false, native_editor_failure(request.command, start_failure)
	end, end_ok, end_failure := editor.buffer_position(request.buffer, line.content_end)
	if !end_ok do return false, false, native_editor_failure(request.command, end_failure)
	text, text_ok, text_failure := familiar_copy_range(request, start, end)
	if !text_ok do return false, false, text_failure
	defer delete(text, request.temporary_allocator)
	for code_point in string(text) {
		if !unicode.is_space(code_point) do return false, true, {}
	}
	return true, true, {}
}

@(private)
familiar_copy_range :: proc(
	request: Native_Context,
	start, end: editor.Position,
) -> (text: []u8, ok: bool, failure: Failure_Context) {
	bytes := u64(end.byte_offset) - u64(start.byte_offset)
	if bytes > editor.MAX_REPLACEMENT_BYTES || bytes > u64(max(int)) {
		return nil, false, Failure_Context{code = .Text_Limit, command = request.command, limit = editor.MAX_REPLACEMENT_BYTES, actual = bytes}
	}
	allocation_error: runtime.Allocator_Error
	text, allocation_error = make([]u8, int(bytes), request.temporary_allocator)
	if allocation_error != nil do return nil, false, familiar_memory_failure(request, bytes)
	_, inspected, inspect_failure := editor.buffer_inspect(request.buffer, start.byte_offset, end.byte_offset, text)
	if !inspected {
		delete(text, request.temporary_allocator)
		return nil, false, native_editor_failure(request.command, inspect_failure)
	}
	return text, true, {}
}

@(private)
familiar_publish_range :: proc(
	request: Native_Context,
	logical: editor_view.Snapshot,
	command_name: string,
	start, end: editor.Position,
	replacement: string,
	result_offset: editor.Byte_Offset,
) -> (Native_Result, bool, Failure_Context) {
	failure := validate_display_request(request, logical, 2, true)
	if failure.code != .None do return {}, false, failure
	return native_edit_publish(
		request,
		logical,
		edit_transaction.Origin{kind = .Built_In, descriptor = "native-command"},
		command_name,
		start,
		end,
		replacement,
		result_offset,
		0,
		false,
		nil,
	)
}

@(private)
familiar_invalid :: proc(request: Native_Context) -> Failure_Context {
	return {code = .Invalid_Request, command = request.command}
}

@(private)
familiar_memory_failure :: proc(request: Native_Context, actual: u64) -> Failure_Context {
	return {code = .Temporary_Memory_Limit, command = request.command, actual = actual}
}

@(private)
familiar_target_failure :: proc(
	request: Native_Context,
	failure: Semantic_Target_Failure,
) -> Failure_Context {
	switch failure.code {
	case .Editor_Failure:
		return {code = .Publication_Failure, command = request.command, editor_code = failure.editor_code}
	case .View_Failure:
		return {code = .View_Failure, command = request.command, view_code = failure.view_code}
	case .Display_Failure:
		return {code = .Display_Failure, command = request.command, display_code = failure.display_code}
	case .Unavailable, .Stale_Context:
		return {code = .Region_Unavailable, command = request.command}
	case .Invalid_Request, .None:
		return familiar_invalid(request)
	}
	unreachable()
}
