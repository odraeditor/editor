// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package status_bar

import "../display"
import "core:strings"
import "core:unicode/utf8"

@(private = "file")
Resolved_Segment :: struct {
	definition:     Segment_Definition,
	text:           string,
	cells:          u32,
	prefix_bytes:   u32,
	compact:        bool,
	omitted:        bool,
	truncated:      bool,
}

/* compose creates one exact-width immutable Status Bar view from bounded segments. */
compose :: proc(request: Composition_Request) -> (View, bool, Failure_Context) {
	failure, valid := composition_request_validate(request)
	if !valid do return {}, false, failure

	resolved: [MAX_SEGMENTS]Resolved_Segment
	work: u32
	for segment, index in request.segments {
		cells, cells_ok := status_text_cells(request.profile, segment.full_text)
		if !cells_ok {
			return {}, false, segment_failure(.Invalid_Segment, segment, 0, u64(len(segment.full_text)))
		}
		resolved[index] = Resolved_Segment {
			definition = segment,
			text = segment.full_text,
			cells = cells,
			prefix_bytes = u32(len(segment.full_text)),
		}
	}

	for composition_cells(resolved[:len(request.segments)]) > request.width_cells {
		candidate := degradation_candidate(resolved[:len(request.segments)], true, &work)
		if work > request.limits.work {
			return {}, false, Failure_Context {
				operation = .Compose,
				code = .Work_Limit,
				limit = u64(request.limits.work),
				actual = u64(work),
			}
		}
		if candidate < 0 do break
		segment := &resolved[candidate]
		compact_cells, compact_ok := status_text_cells(request.profile, segment.definition.compact_text)
		if !compact_ok {
			return {}, false, segment_failure(
				.Invalid_Segment,
				segment.definition,
				0,
				u64(len(segment.definition.compact_text)),
			)
		}
		segment.text = segment.definition.compact_text
		segment.cells = compact_cells
		segment.prefix_bytes = u32(len(segment.text))
		segment.compact = true
	}

	for composition_cells(resolved[:len(request.segments)]) > request.width_cells {
		candidate := degradation_candidate(resolved[:len(request.segments)], false, &work)
		if work > request.limits.work {
			return {}, false, Failure_Context {
				operation = .Compose,
				code = .Work_Limit,
				limit = u64(request.limits.work),
				actual = u64(work),
			}
		}
		if candidate < 0 do break
		resolved[candidate].omitted = true
	}

	if composition_cells(resolved[:len(request.segments)]) > request.width_cells {
		truncated := truncate_identity_to_fit(
			resolved[:len(request.segments)],
			request.width_cells,
			request.profile,
		)
		if !truncated || composition_cells(resolved[:len(request.segments)]) > request.width_cells {
			return {}, false, Failure_Context {
				operation = .Compose,
				code = .Width_Insufficient,
				limit = u64(request.width_cells),
				actual = u64(composition_cells(resolved[:len(request.segments)])),
			}
		}
	}

	return composition_materialize(request, resolved[:len(request.segments)], work)
}

/* view_close releases one composed Status Bar generation exactly once. */
view_close :: proc(view: ^View) -> (bool, Failure_Context) {
	if view == nil || view.allocator.procedure == nil {
		return false, Failure_Context{operation = .Close, code = .Closed_View}
	}
	allocator := view.allocator
	delete(view.segments, allocator)
	delete(view.inspection_text, allocator)
	delete(view.text, allocator)
	view^ = {}
	return true, {}
}

@(private = "file")
composition_request_validate :: proc(request: Composition_Request) -> (Failure_Context, bool) {
	if request.generation == Generation(0) {
		return Failure_Context{operation = .Validate, code = .Invalid_Generation}, false
	}
	if request.allocator.procedure == nil || !display.profile_is_valid(request.profile) ||
	   !limits_are_valid(request.limits) || request.width_cells < MIN_REQUIRED_CELLS {
		return Failure_Context{operation = .Validate, code = .Invalid_Request}, false
	}
	if len(request.segments) == 0 || len(request.segments) > int(request.limits.segments) {
		return Failure_Context {
			operation = .Validate,
			code = .Segment_Limit,
			limit = u64(request.limits.segments),
			actual = u64(len(request.segments)),
		}, false
	}
	for segment, index in request.segments {
		if segment.id == Segment_ID(0) || segment.kind == .Invalid || segment.group == .Invalid ||
		   segment.style_role == .Invalid || len(segment.full_text) == 0 ||
		   segment.required && segment.omittable || !segment.required && !segment.omittable ||
		   !status_text_valid(segment.full_text, request.limits.segment_text_bytes) ||
		   !status_optional_text_valid(segment.compact_text, request.limits.segment_text_bytes) ||
		   !status_optional_text_valid(segment.inspection_text, request.limits.segment_text_bytes) {
			return segment_failure(.Invalid_Segment, segment, 0, 0), false
		}
		for previous in request.segments[:index] {
			if previous.id == segment.id {
				return segment_failure(.Invalid_Segment, segment, 0, u64(segment.id)), false
			}
		}
	}
	return {}, true
}

@(private = "file")
status_text_valid :: proc(value: string, limit: u32) -> bool {
	return len(value) > 0 && len(value) <= int(limit) && utf8.valid_string(value) &&
	       strings.index_byte(value, 0) < 0 && strings.index_byte(value, '\n') < 0 &&
	       strings.index_byte(value, '\r') < 0 && strings.index_byte(value, '\t') < 0
}

@(private = "file")
status_optional_text_valid :: proc(value: string, limit: u32) -> bool {
	return len(value) == 0 || status_text_valid(value, limit)
}

@(private = "file")
status_text_cells :: proc(profile: display.Unicode_Profile, value: string) -> (u32, bool) {
	cells: u32
	offset: u64
	for offset < u64(len(value)) {
		grapheme, grapheme_ok, _ := display.profile_next_grapheme(profile, value, offset)
		if !grapheme_ok do return 0, false
		cluster := value[grapheme.start:grapheme.end]
		width, width_ok, _ := display.profile_cluster_width(profile, cluster, cells, 4)
		if !width_ok || width.is_line_break || width.is_tab || width.used_replacement do return 0, false
		cells += u32(width.cells)
		offset = grapheme.end
	}
	return cells, true
}

@(private = "file")
composition_cells :: proc(segments: []Resolved_Segment) -> u32 {
	left, right, left_count, right_count: u32
	for segment in segments {
		if segment.omitted do continue
		if segment.definition.group == .Left {
			left += segment.cells
			left_count += 1
		} else {
			right += segment.cells
			right_count += 1
		}
	}
	if left_count > 1 do left += left_count - 1
	if right_count > 1 do right += right_count - 1
	if left_count > 0 && right_count > 0 do return left + 1 + right
	return left + right
}

@(private = "file")
degradation_candidate :: proc(segments: []Resolved_Segment, compact: bool, work: ^u32) -> int {
	candidate := -1
	priority := max(u16)
	for segment, index in segments {
		work^ += 1
		eligible := !segment.omitted
		if compact {
			eligible = eligible && !segment.compact && len(segment.definition.compact_text) > 0
		} else {
			eligible = eligible && segment.definition.omittable
		}
		if eligible && segment.definition.priority < priority {
			candidate = index
			priority = segment.definition.priority
		}
	}
	return candidate
}

@(private = "file")
truncate_identity_to_fit :: proc(
	segments: []Resolved_Segment,
	width_cells: u32,
	profile: display.Unicode_Profile,
) -> bool {
	index := -1
	priority: u16
	for segment, candidate in segments {
		if !segment.omitted && segment.definition.required && segment.definition.truncatable &&
		   (index < 0 || segment.definition.priority > priority) {
			index = candidate
			priority = segment.definition.priority
		}
	}
	if index < 0 do return false
	segment := &segments[index]
	excess := composition_cells(segments) - width_cells
	target := u32(1)
	if segment.cells > excess + 1 do target = segment.cells - excess
	prefix, prefix_cells, ok := status_prefix_for_cells(profile, segment.text, target - 1)
	if !ok do return false
	segment.prefix_bytes = prefix
	segment.cells = prefix_cells + 1
	segment.truncated = true
	return true
}

@(private = "file")
status_prefix_for_cells :: proc(
	profile: display.Unicode_Profile,
	value: string,
	limit: u32,
) -> (u32, u32, bool) {
	offset: u64
	cells: u32
	for offset < u64(len(value)) {
		grapheme, grapheme_ok, _ := display.profile_next_grapheme(profile, value, offset)
		if !grapheme_ok do return 0, 0, false
		cluster := value[grapheme.start:grapheme.end]
		width, width_ok, _ := display.profile_cluster_width(profile, cluster, cells, 4)
		if !width_ok || width.is_line_break || width.is_tab || width.used_replacement do return 0, 0, false
		if cells + u32(width.cells) > limit do break
		cells += u32(width.cells)
		offset = grapheme.end
	}
	return u32(offset), cells, true
}

@(private = "file")
composition_materialize :: proc(
	request: Composition_Request,
	resolved: []Resolved_Segment,
	work: u32,
) -> (View, bool, Failure_Context) {
	visible_count, inspection_bytes, required_text_bytes: u32
	for segment in resolved {
		if segment.omitted do continue
		visible_count += 1
		inspection_bytes += u32(len(segment.definition.inspection_text))
		required_text_bytes += segment.prefix_bytes
		if segment.truncated do required_text_bytes += u32(len("…"))
	}
	if visible_count > 1 do required_text_bytes += visible_count - 1
	if required_text_bytes < request.width_cells {
		required_text_bytes += request.width_cells - composition_cells(resolved)
	}
	if required_text_bytes > request.limits.view_text_bytes || inspection_bytes > request.limits.view_text_bytes {
		return {}, false, Failure_Context {
			operation = .Compose,
			code = .Text_Limit,
			limit = u64(request.limits.view_text_bytes),
			actual = u64(max(required_text_bytes, inspection_bytes)),
		}
	}
	text_capacity := u64(required_text_bytes)
	text, text_error := make([]u8, int(text_capacity), request.allocator)
	if text_error != nil do return {}, false, allocation_failure(text_capacity)
	segments, segment_error := make([]Segment_View, int(visible_count), request.allocator)
	if segment_error != nil {
		delete(text, request.allocator)
		return {}, false, allocation_failure(u64(visible_count) * u64(size_of(Segment_View)))
	}
	inspection, inspection_error := make([]u8, int(inspection_bytes), request.allocator)
	if inspection_error != nil {
		delete(segments, request.allocator)
		delete(text, request.allocator)
		return {}, false, allocation_failure(u64(inspection_bytes))
	}

	text_bytes, text_cells, view_count, inspection_offset: u32
	left_cells, right_cells, left_count, right_count := composition_group_metrics(resolved)
	leading := u32(0)
	gap := u32(0)
	if left_count == 0 do leading = request.width_cells - right_cells
	if left_count > 0 && right_count > 0 do gap = request.width_cells - left_cells - right_cells
	text_bytes = append_spaces(text, text_bytes, leading)
	text_cells += leading
	for group in Group.Left ..= Group.Right {
		seen: u32
		if group == .Right && left_count > 0 && right_count > 0 {
			text_bytes = append_spaces(text, text_bytes, gap)
			text_cells += gap
		}
		for segment in resolved {
			if segment.omitted || segment.definition.group != group do continue
			if seen > 0 {
				text[text_bytes] = ' '
				text_bytes += 1
				text_cells += 1
			}
			view := &segments[view_count]
			view.id = segment.definition.id
			view.kind = segment.definition.kind
			view.group = segment.definition.group
			view.style_role = segment.definition.style_role
			view.start_byte = text_bytes
			view.start_cell = text_cells
			prefix := segment.text[:int(segment.prefix_bytes)]
			copy(text[text_bytes:], transmute([]u8)(prefix))
			text_bytes += u32(len(prefix))
			if segment.truncated {
				ellipsis := transmute([]u8)(string("…"))
				copy(text[text_bytes:], ellipsis)
				text_bytes += u32(len(ellipsis))
			}
			text_cells += segment.cells
			view.end_byte = text_bytes
			view.end_cell = text_cells
			view.compact = segment.compact
			view.truncated = segment.truncated
			view.primary_command = segment.definition.primary_command
			view.secondary_command = segment.definition.secondary_command
			inspection_value := segment.definition.inspection_text
			if len(inspection_value) > 0 {
				start := inspection_offset
				copy(inspection[start:], transmute([]u8)(inspection_value))
				inspection_offset += u32(len(inspection_value))
				view.inspection_text = string(inspection[start:inspection_offset])
			}
			view_count += 1
			seen += 1
		}
	}
	if right_count == 0 {
		trailing := request.width_cells - text_cells
		text_bytes = append_spaces(text, text_bytes, trailing)
		text_cells += trailing
	}
	if text_bytes > request.limits.view_text_bytes {
		delete(inspection, request.allocator)
		delete(segments, request.allocator)
		delete(text, request.allocator)
		return {}, false, Failure_Context {
			operation = .Compose,
			code = .Text_Limit,
			limit = u64(request.limits.view_text_bytes),
			actual = u64(text_bytes),
		}
	}
	text = text[:text_bytes]
	return View {
		generation = request.generation,
		width_cells = request.width_cells,
		text = text,
		inspection_text = inspection,
		segments = segments,
		accounting = Accounting {
			text_bytes = text_bytes,
			text_cells = text_cells,
			visible_segments = u16(visible_count),
			work = work,
			retained_bytes = u64(text_bytes) + u64(inspection_bytes) +
			                 u64(visible_count) * u64(size_of(Segment_View)),
		},
		allocator = request.allocator,
	}, true, {}
}

@(private = "file")
composition_group_metrics :: proc(segments: []Resolved_Segment) -> (
	left_cells, right_cells, left_count, right_count: u32,
) {
	for segment in segments {
		if segment.omitted do continue
		if segment.definition.group == .Left {
			left_cells += segment.cells
			left_count += 1
		} else {
			right_cells += segment.cells
			right_count += 1
		}
	}
	if left_count > 1 do left_cells += left_count - 1
	if right_count > 1 do right_cells += right_count - 1
	return
}

@(private = "file")
append_spaces :: proc(target: []u8, offset: u32, count: u32) -> u32 {
	for index in 0 ..< count do target[offset + index] = ' '
	return offset + count
}

@(private = "file")
segment_failure :: proc(code: Failure_Code, segment: Segment_Definition, limit, actual: u64) -> Failure_Context {
	return Failure_Context {
		operation = .Validate,
		code = code,
		segment = segment.id,
		limit = limit,
		actual = actual,
	}
}

@(private = "file")
allocation_failure :: proc(actual: u64) -> Failure_Context {
	return Failure_Context{operation = .Compose, code = .Allocation, actual = actual}
}
