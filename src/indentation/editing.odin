// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package indentation

/* Normalization_Target selects one explicit leading-indentation representation. */
Normalization_Target :: enum u8 {
	Invalid,
	Tabs,
	Spaces,
}

/* Backspace_Plan identifies one semantic deletion inside leading indentation. */
Backspace_Plan :: struct {
	start:    int,
	end:      int,
	semantic: bool,
}

/* Normalization_Measurement describes one bounded leading-indentation rewrite. */
Normalization_Measurement :: struct {
	required_bytes: u64,
	changed:        bool,
}

/* smart_backspace_plan resolves the previous logical boundary in a line prefix. */
smart_backspace_plan :: proc(prefix: string, policy: Policy) -> (Backspace_Plan, bool) {
	if !policy_is_valid(policy) do return {}, false
	if len(prefix) == 0 do return {}, true
	for value in prefix {
		if value != ' ' && value != '\t' do return {}, true
	}
	end := len(prefix)
	if prefix[end - 1] == '\t' {
		return {start = end - 1, end = end, semantic = true}, true
	}
	spaces := 0
	for index := end - 1; index >= 0 && prefix[index] == ' '; index -= 1 {
		spaces += 1
	}
	if spaces == 0 do return {}, true
	width := int(policy.indent_width)
	remove := spaces % width
	if remove == 0 do remove = min(spaces, width)
	return {start = end - remove, end = end, semantic = true}, true
}

/* normalization_measure computes exact output size without retaining source storage. */
normalization_measure :: proc(
	source: string,
	policy: Policy,
	target: Normalization_Target,
) -> (Normalization_Measurement, bool) {
	if !policy_is_valid(policy) || (target != .Tabs && target != .Spaces) {
		return {}, false
	}
	required := u64(0)
	changed := false
	read := 0
	line_start := true
	for read < len(source) {
		if line_start {
			prefix_end := read
			for prefix_end < len(source) &&
			      (source[prefix_end] == ' ' || source[prefix_end] == '\t') {
				prefix_end += 1
			}
			prefix_bytes, prefix_changed := normalization_prefix_bytes(
				source[read:prefix_end],
				policy,
				target,
			)
			if required > max(u64) - prefix_bytes do return {}, false
			required += prefix_bytes
			changed = changed || prefix_changed
			read = prefix_end
			line_start = false
			if read >= len(source) do break
		}
		if required == max(u64) do return {}, false
		required += 1
		line_start = source[read] == '\n'
		read += 1
	}
	return {required_bytes = required, changed = changed}, true
}

/* normalize_leading writes one exact leading-indentation conversion. */
normalize_leading :: proc(
	source: string,
	destination: []u8,
	policy: Policy,
	target: Normalization_Target,
) -> (written: int, changed: bool, ok: bool) {
	measurement, measured := normalization_measure(source, policy, target)
	if !measured || measurement.required_bytes > u64(len(destination)) {
		return 0, false, false
	}
	read := 0
	line_start := true
	for read < len(source) {
		if line_start {
			prefix_end := read
			for prefix_end < len(source) &&
			      (source[prefix_end] == ' ' || source[prefix_end] == '\t') {
				prefix_end += 1
			}
			written = normalization_prefix_write(
				source[read:prefix_end],
				destination,
				written,
				policy,
				target,
			)
			read = prefix_end
			line_start = false
			if read >= len(source) do break
		}
		destination[written] = source[read]
		line_start = source[read] == '\n'
		written += 1
		read += 1
	}
	return written, measurement.changed, written == int(measurement.required_bytes)
}

@(private)
normalization_prefix_bytes :: proc(
	prefix: string,
	policy: Policy,
	target: Normalization_Target,
) -> (required: u64, changed: bool) {
	if target == .Spaces {
		for value in prefix {
			if value == '\t' {
				required += u64(policy.indent_width)
				changed = true
			} else {
				required += 1
			}
		}
		return
	}
	spaces := 0
	for index := 0; index <= len(prefix); index += 1 {
		if index < len(prefix) && prefix[index] == ' ' {
			spaces += 1
			continue
		}
		tabs := spaces / int(policy.indent_width)
		remainder := spaces % int(policy.indent_width)
		required += u64(tabs + remainder)
		changed = changed || tabs > 0
		spaces = 0
		if index < len(prefix) {
			required += 1
		}
	}
	return
}

@(private)
normalization_prefix_write :: proc(
	prefix: string,
	destination: []u8,
	written: int,
	policy: Policy,
	target: Normalization_Target,
) -> int {
	cursor := written
	if target == .Spaces {
		for value in prefix {
			if value == '\t' {
				for _ in 0 ..< policy.indent_width {
					destination[cursor] = ' '
					cursor += 1
				}
			} else {
				destination[cursor] = u8(value)
				cursor += 1
			}
		}
		return cursor
	}
	spaces := 0
	for index := 0; index <= len(prefix); index += 1 {
		if index < len(prefix) && prefix[index] == ' ' {
			spaces += 1
			continue
		}
		for _ in 0 ..< spaces / int(policy.indent_width) {
			destination[cursor] = '\t'
			cursor += 1
		}
		for _ in 0 ..< spaces % int(policy.indent_width) {
			destination[cursor] = ' '
			cursor += 1
		}
		spaces = 0
		if index < len(prefix) {
			destination[cursor] = prefix[index]
			cursor += 1
		}
	}
	return cursor
}
