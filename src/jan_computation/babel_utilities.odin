// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_computation

/* MAX_BABEL_UTILITY_TEXT bounds one adapter-independent editing result. */
MAX_BABEL_UTILITY_TEXT :: 64 * 1_024

/* Babel_Utility_Failure classifies adapter-independent source inspection. */
Babel_Utility_Failure :: enum u8 {
	None,
	No_Source_Block,
	Malformed_Source,
	Invalid_Point,
	Invalid_Argument,
	Limit,
}

/* Babel_Source_Block is one complete source block in an immutable document. */
Babel_Source_Block :: struct {
	start:          int,
	header_end:     int,
	body_start:     int,
	body_end:       int,
	end_start:      int,
	end:            int,
	language_start: int,
	language_end:   int,
}

/* Babel_Named_Target identifies a copied-name source or result location. */
Babel_Named_Target :: struct {
	name_start: int,
	name_end:   int,
	target:     int,
}

/* babel_source_block_at resolves the complete source block containing point. */
babel_source_block_at :: proc(source: string, point: int) -> (Babel_Source_Block, bool, Babel_Utility_Failure) {
	if point < 0 || point > len(source) do return {}, false, .Invalid_Point
	line_start := 0
	open: Babel_Source_Block
	for line_start < len(source) {
		line_end := babel_line_end(source, line_start)
		content_start := babel_content_start(source, line_start, line_end)
		if babel_prefix_folded(source, content_start, line_end, "#+begin_src") {
			if open.body_start != 0 do return {}, false, .Malformed_Source
			language_start := content_start + len("#+begin_src")
			for language_start < line_end && babel_horizontal_space(source[language_start]) do language_start += 1
			language_end := language_start
			for language_end < line_end && !babel_horizontal_space(source[language_end]) do language_end += 1
			if language_start == language_end do return {}, false, .Malformed_Source
			open = {
				start = line_start,
				header_end = line_end,
				body_start = babel_next_line_start(source, line_end),
				language_start = language_start,
				language_end = language_end,
			}
		} else if babel_prefix_folded(source, content_start, line_end, "#+end_src") {
			if open.body_start == 0 do return {}, false, .Malformed_Source
			open.body_end = line_start
			open.end_start = line_start
			open.end = babel_next_line_start(source, line_end)
			if point >= open.start && point <= open.end do return open, true, .None
			open = {}
		}
		line_start = babel_next_line_start(source, line_end)
	}
	if open.body_start != 0 do return {}, false, .Malformed_Source
	return {}, false, .No_Source_Block
}

/* babel_result_after_block resolves the first adjacent result owner. */
babel_result_after_block :: proc(source: string, block: Babel_Source_Block) -> (int, bool) {
	if !babel_source_block_valid(source, block) do return 0, false
	line_start := block.end
	for line_start < len(source) {
		line_end := babel_line_end(source, line_start)
		content_start := babel_content_start(source, line_start, line_end)
		if content_start == line_end {
			line_start = babel_next_line_start(source, line_end)
			continue
		}
		if babel_prefix_folded(source, content_start, line_end, "#+results:") do return line_start, true
		return 0, false
	}
	return 0, false
}

/* babel_named_source_at returns the indexed named source in source order. */
babel_named_source_at :: proc(source: string, target_index: int) -> (Babel_Named_Target, bool) {
	if target_index < 0 do return {}, false
	line_start := 0
	pending: Babel_Named_Target
	found := 0
	for line_start < len(source) {
		line_end := babel_line_end(source, line_start)
		content_start := babel_content_start(source, line_start, line_end)
		if babel_prefix_folded(source, content_start, line_end, "#+name:") {
			name_start := content_start + len("#+name:")
			for name_start < line_end && babel_horizontal_space(source[name_start]) do name_start += 1
			name_end := line_end
			for name_end > name_start && babel_horizontal_space(source[name_end - 1]) do name_end -= 1
			pending = {name_start = name_start, name_end = name_end}
		} else if babel_prefix_folded(source, content_start, line_end, "#+begin_src") && pending.name_end > pending.name_start {
			pending.target = line_start
			if found == target_index do return pending, true
			found += 1
			pending = {}
		} else if content_start < line_end && source[content_start] == '*' {
			pending = {}
		}
		line_start = babel_next_line_start(source, line_end)
	}
	return {}, false
}

/* babel_named_result_at returns the indexed named result in source order. */
babel_named_result_at :: proc(source: string, target_index: int) -> (Babel_Named_Target, bool) {
	if target_index < 0 do return {}, false
	line_start := 0
	found := 0
	for line_start < len(source) {
		line_end := babel_line_end(source, line_start)
		content_start := babel_content_start(source, line_start, line_end)
		if babel_prefix_folded(source, content_start, line_end, "#+results:") {
			name_start := content_start + len("#+results:")
			for name_start < line_end && babel_horizontal_space(source[name_start]) do name_start += 1
			name_end := line_end
			for name_end > name_start && babel_horizontal_space(source[name_end - 1]) do name_end -= 1
			if name_end > name_start {
				if found == target_index do return {name_start = name_start, name_end = name_end, target = line_start}, true
				found += 1
			}
		}
		line_start = babel_next_line_start(source, line_end)
	}
	return {}, false
}

/* babel_demarcation_text constructs a safe source-block split at a line boundary. */
babel_demarcation_text :: proc(
	source: string,
	block: Babel_Source_Block,
	point: int,
	output: []u8,
) -> (string, bool, Babel_Utility_Failure) {
	if !babel_source_block_valid(source, block) do return "", false, .Malformed_Source
	if point < block.body_start || point > block.body_end ||
	   (point > block.body_start && source[point - 1] != '\n') {
		return "", false, .Invalid_Point
	}
	suffix_start := block.language_start
	suffix_end := block.header_end
	required := len("#+end_src\n#+begin_src ") + suffix_end - suffix_start + 1
	if required > len(output) || required > MAX_BABEL_UTILITY_TEXT do return "", false, .Limit
	cursor := copy(output, "#+end_src\n#+begin_src ")
	cursor += copy(output[cursor:], source[suffix_start:suffix_end])
	cursor += copy(output[cursor:], "\n")
	return string(output[:cursor]), true, .None
}

/* babel_header_argument_insertion validates one explicit header argument. */
babel_header_argument_insertion :: proc(argument: string, output: []u8) -> (string, bool, Babel_Utility_Failure) {
	if len(argument) < 2 || argument[0] != ':' do return "", false, .Invalid_Argument
	for value in transmute([]u8)argument do if value == '\n' || value == '\r' {
		return "", false, .Invalid_Argument
	}
	if len(argument) + 1 > len(output) do return "", false, .Limit
	output[0] = ' '
	copy(output[1:], argument)
	return string(output[:len(argument) + 1]), true, .None
}

/* babel_source_hash calculates a stable hash over effective block source. */
babel_source_hash :: proc(source: string, block: Babel_Source_Block) -> (u64, bool) {
	if !babel_source_block_valid(source, block) do return 0, false
	hash := u64(1469598103934665603)
	for value in transmute([]u8)source[block.language_start:block.header_end] {
		hash = (hash ~ u64(value)) * 1099511628211
	}
	for value in transmute([]u8)source[block.body_start:block.body_end] {
		hash = (hash ~ u64(value)) * 1099511628211
	}
	return hash, true
}

@(private)
babel_source_block_valid :: proc(source: string, block: Babel_Source_Block) -> bool {
	return block.start >= 0 && block.start < block.header_end && block.header_end < block.body_start &&
	       block.body_start <= block.body_end && block.body_end == block.end_start &&
	       block.end_start < block.end && block.end <= len(source) &&
	       block.language_start >= block.start && block.language_start < block.language_end &&
	       block.language_end <= block.header_end
}

@(private)
babel_line_end :: proc(source: string, start: int) -> int {
	end := start
	for end < len(source) && source[end] != '\n' && source[end] != '\r' do end += 1
	return end
}

@(private)
babel_next_line_start :: proc(source: string, end: int) -> int {
	next := end
	if next < len(source) && source[next] == '\r' do next += 1
	if next < len(source) && source[next] == '\n' do next += 1
	return next
}

@(private)
babel_content_start :: proc(source: string, start, end: int) -> int {
	result := start
	for result < end && babel_horizontal_space(source[result]) do result += 1
	return result
}

@(private)
babel_horizontal_space :: proc(value: u8) -> bool {
	return value == ' ' || value == '\t'
}

@(private)
babel_prefix_folded :: proc(source: string, start, end: int, expected: string) -> bool {
	if start < 0 || end < start || end - start < len(expected) do return false
	for value, index in transmute([]u8)expected {
		actual := source[start + index]
		expected_value := value
		if actual >= 'A' && actual <= 'Z' do actual += 'a' - 'A'
		if expected_value >= 'A' && expected_value <= 'Z' do expected_value += 'a' - 'A'
		if actual != expected_value do return false
	}
	return true
}
