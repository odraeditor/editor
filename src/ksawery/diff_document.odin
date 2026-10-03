// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery

import "base:runtime"

/* Diff_Document owns one complete parsed semantic diff and its patch material. */
Diff_Document :: struct {
	state: rawptr,
}

@(private)
Diff_Document_Data :: struct {
	descriptor:   Diff_Document_Descriptor,
	units:        [dynamic]Diff_Unit_Descriptor,
	lines:        [dynamic]Diff_Line_Descriptor,
	presentation: [dynamic]u8,
	patches:      [dynamic]u8,
	limits:       Diff_Limits,
	allocator:    runtime.Allocator,
}

@(private)
Diff_Line_Span :: struct {
	start:    int,
	end:      int,
	next:     int,
	complete: bool,
}

@(private)
Diff_Hunk_Header :: struct {
	old_start: u32,
	old_count: u32,
	new_start: u32,
	new_count: u32,
}

/* diff_document_open parses one complete bounded tracked path detail. */
diff_document_open :: proc(
	detail: ^Path_Detail,
	limits := DEFAULT_DIFF_LIMITS,
	allocator := context.allocator,
) -> (Diff_Document, bool, Failure_Code) {
	if allocator.procedure == nil || !diff_limits_are_valid(limits) {
		return {}, false, .Invalid_Request
	}
	detail_descriptor, described := path_detail_descriptor(detail)
	if !described do return {}, false, .Invalid_Request
	if detail_descriptor.truncated do return {}, false, .Diff_Truncated
	layer, supported := diff_layer_for_detail_kind(detail_descriptor.kind)
	if !supported do return {}, false, .Diff_Unsupported
	content, copied := path_detail_content(detail)
	if !copied || len(content) == 0 do return {}, false, .Diff_Unsupported
	if u64(len(content)) > limits.patch_bytes do return {}, false, .Output_Limit

	state, allocation_error := new(Diff_Document_Data, allocator)
	if allocation_error != nil do return {}, false, .Allocation
	state.allocator = allocator
	state.limits = limits
	state.units, allocation_error = make([dynamic]Diff_Unit_Descriptor, 0, int(min(limits.units, 32)), allocator)
	if allocation_error == nil {
		state.lines, allocation_error = make([dynamic]Diff_Line_Descriptor, 0, 128, allocator)
	}
	if allocation_error == nil {
		state.presentation, allocation_error = make([dynamic]u8, 0, int(min(limits.patch_bytes, 64 * KIBIBYTE)), allocator)
	}
	if allocation_error == nil {
		state.patches, allocation_error = make([dynamic]u8, 0, int(min(limits.patch_bytes, 64 * KIBIBYTE)), allocator)
	}
	if allocation_error != nil {
		diff_document_data_destroy(state)
		return {}, false, .Allocation
	}

	failure := diff_document_parse(state, detail_descriptor.target, layer, content)
	if failure != .None {
		diff_document_data_destroy(state)
		return {}, false, failure
	}
	return Diff_Document{state = state}, true, .None
}

/* diff_document_descriptor returns copied immutable semantic diff metadata. */
diff_document_descriptor :: proc(document: ^Diff_Document) -> (Diff_Document_Descriptor, bool) {
	state := diff_document_data(document)
	if state == nil do return {}, false
	return state.descriptor, true
}

/* diff_document_unit returns one copied semantic unit in source order. */
diff_document_unit :: proc(document: ^Diff_Document, ordinal: u32) -> (Diff_Unit_Descriptor, bool) {
	state := diff_document_data(document)
	if state == nil || ordinal >= u32(len(state.units)) do return {}, false
	return state.units[ordinal], true
}

/* diff_document_line returns one copied semantic body line in source order. */
diff_document_line :: proc(document: ^Diff_Document, ordinal: u32) -> (Diff_Line_Descriptor, bool) {
	state := diff_document_data(document)
	if state == nil || ordinal >= u32(len(state.lines)) do return {}, false
	return state.lines[ordinal], true
}

/* diff_document_presentation returns borrowed complete semantic hunk bytes. */
diff_document_presentation :: proc(document: ^Diff_Document) -> ([]u8, bool) {
	state := diff_document_data(document)
	if state == nil do return nil, false
	return state.presentation[:], true
}

/* diff_document_unit_patch returns borrowed exact patch bytes for one semantic unit. */
diff_document_unit_patch :: proc(
	document: ^Diff_Document,
	target: Diff_Unit_Target,
) -> ([]u8, bool, Failure_Code) {
	state := diff_document_data(document)
	if state == nil || !diff_unit_target_is_valid(target) do return nil, false, .Invalid_Request
	if target.path != state.descriptor.path || target.source != state.descriptor.source ||
	   target.layer != state.descriptor.layer {
		return nil, false, .Stale_Observation
	}
	for unit in state.units {
		if unit.target.unit != target.unit do continue
		start := int(unit.patch.offset)
		end := start + int(unit.patch.length)
		if start < 0 || end < start || end > len(state.patches) do return nil, false, .Patch_Unavailable
		return state.patches[start:end], true, .None
	}
	return nil, false, .Diff_Unit_Unavailable
}

/* diff_document_usage reports exact retained semantic diff resources. */
diff_document_usage :: proc(document: ^Diff_Document) -> (Diff_Usage, bool) {
	state := diff_document_data(document)
	if state == nil do return {}, false
	return Diff_Usage {
		units = u32(len(state.units)),
		lines = u32(len(state.lines)),
		presentation_bytes = u64(len(state.presentation)),
		patch_bytes = u64(len(state.patches)),
		allocation_bytes = diff_document_allocation_bytes(state),
	}, true
}

/* diff_document_is_current checks the exact source path against an observation. */
diff_document_is_current :: proc(document: ^Diff_Document, observation: ^Status_Observation) -> bool {
	state := diff_document_data(document)
	descriptor, available := status_observation_descriptor(observation)
	if state == nil || !available || state.descriptor.path.generation != descriptor.generation do return false
	_, found := status_observation_path_by_id(observation, state.descriptor.path.path)
	return found
}

/* diff_document_close releases every owned semantic diff allocation. */
diff_document_close :: proc(document: ^Diff_Document) {
	state := diff_document_data(document)
	if state == nil do return
	diff_document_data_destroy(state)
	document^ = {}
}

@(private)
diff_document_parse :: proc(
	state: ^Diff_Document_Data,
	path: Path_Target,
	layer: Diff_Layer,
	content: []u8,
) -> Failure_Code {
	if state == nil || !path_target_is_valid(path) || layer == .Invalid do return .Invalid_Request
	first_hunk := -1
	cursor := 0
	for cursor < len(content) {
		span, available := diff_next_line(content, cursor)
		if !available || !span.complete do return .Parse
		line := content[span.start:span.end]
		if diff_line_is_hunk_header(line) {
			first_hunk = span.start
			break
		}
		cursor = span.next
	}
	if first_hunk < 0 do return .Diff_Unsupported
	prelude := content[:first_hunk]
	source := diff_source_id(content)
	cursor = first_hunk
	for cursor < len(content) {
		if u32(len(state.units)) >= state.limits.units do return .Output_Limit
		header_span, available := diff_next_line(content, cursor)
		if !available || !header_span.complete do return .Parse
		header_line := content[header_span.start:header_span.end]
		header, parsed := diff_hunk_header_parse(header_line)
		if !parsed do return .Parse
		hunk_start := header_span.start
		hunk_end := header_span.next
		body_cursor := header_span.next
		old_seen, new_seen: u32
		line_count: u32
		for body_cursor < len(content) {
			span, body_available := diff_next_line(content, body_cursor)
			if !body_available || !span.complete do return .Parse
			line := content[span.start:span.end]
			if diff_line_is_hunk_header(line) do break
			if diff_bytes_have_prefix(line, transmute([]u8)(string("diff --git "))) do return .Parse
			kind, line_ok := diff_body_line_kind(line)
			if !line_ok do return .Parse
			switch kind {
			case .Context:
				old_seen += 1
				new_seen += 1
			case .Addition:
				new_seen += 1
			case .Removal:
				old_seen += 1
			case .No_Newline_Marker:
			case .Invalid:
				return .Parse
			}
			line_count += 1
			if u64(len(line)) > state.limits.line_bytes do return .Output_Limit
			hunk_end = span.next
			body_cursor = span.next
		}
		if line_count == 0 || old_seen != header.old_count || new_seen != header.new_count {
			return .Parse
		}
		unit_id := Diff_Unit_ID(u32(len(state.units)) + 1)
		target := Diff_Unit_Target{path = path, source = source, layer = layer, unit = unit_id}
		presentation_start := len(state.presentation)
		_, allocation_error := append(&state.presentation, ..content[hunk_start:hunk_end])
		if allocation_error != nil do return .Allocation
		patch_start := len(state.patches)
		_, allocation_error = append(&state.patches, ..prelude)
		if allocation_error == nil do _, allocation_error = append(&state.patches, ..content[hunk_start:hunk_end])
		if allocation_error != nil do return .Allocation
		if u64(len(state.presentation)) > state.limits.patch_bytes ||
		   u64(len(state.patches)) > state.limits.patch_bytes {
			return .Output_Limit
		}
		unit := Diff_Unit_Descriptor {
			target = target,
			old_start = header.old_start,
			old_count = header.old_count,
			new_start = header.new_start,
			new_count = header.new_count,
			line_count = line_count,
			presentation = {offset = u32(presentation_start), length = u32(hunk_end - hunk_start)},
			patch = {offset = u32(patch_start), length = u32(len(state.patches) - patch_start)},
		}
		if !diff_unit_descriptor_is_valid(unit, u64(len(state.presentation)), u64(len(state.patches))) {
			return .Parse
		}
		_, allocation_error = append(&state.units, unit)
		if allocation_error != nil do return .Allocation
		failure := diff_document_append_lines(state, target, content[hunk_start:hunk_end], presentation_start)
		if failure != .None do return failure
		if diff_document_allocation_bytes(state) > state.limits.temporary_bytes do return .Output_Limit
		cursor = body_cursor
	}
	if len(state.units) == 0 do return .Diff_Unsupported
	state.descriptor = {
		path = path,
		source = source,
		layer = layer,
		unit_count = u32(len(state.units)),
		line_count = u32(len(state.lines)),
		presentation_bytes = u64(len(state.presentation)),
		patch_bytes = u64(len(state.patches)),
	}
	if !diff_document_descriptor_is_valid(state.descriptor, state.limits) do return .Parse
	return .None
}

@(private)
diff_document_append_lines :: proc(
	state: ^Diff_Document_Data,
	target: Diff_Unit_Target,
	hunk: []u8,
	presentation_start: int,
) -> Failure_Code {
	header, available := diff_next_line(hunk, 0)
	if !available || !header.complete do return .Parse
	cursor := header.next
	old_line, new_line: u32
	header_value, parsed := diff_hunk_header_parse(hunk[header.start:header.end])
	if !parsed do return .Parse
	old_line = header_value.old_start
	new_line = header_value.new_start
	ordinal: u32
	for cursor < len(hunk) {
		span, line_available := diff_next_line(hunk, cursor)
		if !line_available || !span.complete do return .Parse
		line := hunk[span.start:span.end]
		kind, line_ok := diff_body_line_kind(line)
		if !line_ok do return .Parse
		descriptor := Diff_Line_Descriptor {
			unit = target,
			kind = kind,
			ordinal = ordinal,
			text = {
				offset = u32(presentation_start + span.start),
				length = u32(len(line)),
			},
		}
		switch kind {
		case .Context:
			descriptor.old_line = old_line
			descriptor.new_line = new_line
			old_line += 1
			new_line += 1
		case .Addition:
			descriptor.new_line = new_line
			new_line += 1
		case .Removal:
			descriptor.old_line = old_line
			old_line += 1
		case .No_Newline_Marker:
		case .Invalid:
			return .Parse
		}
		if !diff_line_descriptor_is_valid(descriptor, u64(len(state.presentation))) do return .Parse
		_, allocation_error := append(&state.lines, descriptor)
		if allocation_error != nil do return .Allocation
		ordinal += 1
		cursor = span.next
	}
	return .None
}

@(private)
diff_next_line :: proc(content: []u8, start: int) -> (Diff_Line_Span, bool) {
	if start < 0 || start >= len(content) do return {}, false
	for index in start ..< len(content) {
		if content[index] == '\n' {
			return Diff_Line_Span{start = start, end = index, next = index + 1, complete = true}, true
		}
	}
	return Diff_Line_Span{start = start, end = len(content), next = len(content)}, true
}

@(private)
diff_line_is_hunk_header :: proc(line: []u8) -> bool {
	return len(line) >= 4 && line[0] == '@' && line[1] == '@' && line[2] == ' ' && line[3] == '-'
}

@(private)
diff_hunk_header_parse :: proc(line: []u8) -> (Diff_Hunk_Header, bool) {
	if !diff_line_is_hunk_header(line) do return {}, false
	cursor := 4
	old_start, parsed := diff_parse_u32(line, &cursor)
	if !parsed do return {}, false
	old_count := u32(1)
	if cursor < len(line) && line[cursor] == ',' {
		cursor += 1
		old_count, parsed = diff_parse_u32(line, &cursor)
		if !parsed do return {}, false
	}
	if cursor + 2 >= len(line) || line[cursor] != ' ' || line[cursor + 1] != '+' {
		return {}, false
	}
	cursor += 2
	new_start, new_parsed := diff_parse_u32(line, &cursor)
	if !new_parsed do return {}, false
	new_count := u32(1)
	if cursor < len(line) && line[cursor] == ',' {
		cursor += 1
		new_count, new_parsed = diff_parse_u32(line, &cursor)
		if !new_parsed do return {}, false
	}
	if cursor + 2 >= len(line) || line[cursor] != ' ' || line[cursor + 1] != '@' ||
	   line[cursor + 2] != '@' {
		return {}, false
	}
	header := Diff_Hunk_Header {
		old_start = old_start,
		old_count = old_count,
		new_start = new_start,
		new_count = new_count,
	}
	return header, diff_range_is_valid(old_start, old_count) && diff_range_is_valid(new_start, new_count)
}

@(private)
diff_parse_u32 :: proc(content: []u8, cursor: ^int) -> (u32, bool) {
	if cursor == nil || cursor^ < 0 || cursor^ >= len(content) do return 0, false
	value: u64
	digits := 0
	for cursor^ < len(content) {
		byte := content[cursor^]
		if byte < '0' || byte > '9' do break
		value = value * 10 + u64(byte - '0')
		if value > u64(max(u32)) do return 0, false
		cursor^ += 1
		digits += 1
	}
	return u32(value), digits > 0
}

@(private)
diff_body_line_kind :: proc(line: []u8) -> (Diff_Line_Kind, bool) {
	if len(line) == 0 do return .Invalid, false
	switch line[0] {
	case ' ': return .Context, true
	case '+': return .Addition, true
	case '-': return .Removal, true
	case '\\':
		marker := transmute([]u8)(string("\\ No newline at end of file"))
		return .No_Newline_Marker, diff_bytes_equal(line, marker)
	}
	return .Invalid, false
}

@(private)
diff_source_id :: proc(content: []u8) -> Diff_Source_ID {
	hash := u64(14_695_981_039_346_656_037)
	for byte in content {
		hash = (hash ~ u64(byte)) * 1_099_511_628_211
	}
	if hash == 0 do hash = 1
	return Diff_Source_ID(hash)
}

@(private)
diff_bytes_have_prefix :: proc(content, prefix: []u8) -> bool {
	if len(prefix) > len(content) do return false
	for index in 0 ..< len(prefix) {
		if content[index] != prefix[index] do return false
	}
	return true
}

@(private)
diff_bytes_equal :: proc(left, right: []u8) -> bool {
	if len(left) != len(right) do return false
	for index in 0 ..< len(left) {
		if left[index] != right[index] do return false
	}
	return true
}

@(private)
diff_document_allocation_bytes :: proc(state: ^Diff_Document_Data) -> u64 {
	if state == nil do return 0
	return u64(size_of(Diff_Document_Data)) +
	       u64(cap(state.units)) * u64(size_of(Diff_Unit_Descriptor)) +
	       u64(cap(state.lines)) * u64(size_of(Diff_Line_Descriptor)) +
	       u64(cap(state.presentation)) + u64(cap(state.patches))
}

@(private)
diff_document_data :: proc(document: ^Diff_Document) -> ^Diff_Document_Data {
	if document == nil || document.state == nil do return nil
	return cast(^Diff_Document_Data)document.state
}

@(private)
diff_document_data_destroy :: proc(state: ^Diff_Document_Data) {
	if state == nil do return
	delete(state.units)
	delete(state.lines)
	delete(state.presentation)
	delete(state.patches)
	free(state, state.allocator)
}
