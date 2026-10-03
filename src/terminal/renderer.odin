// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package terminal_frontend

import "base:runtime"
import "../display"
import "../editor"
import "../ui"

@(private)
Cached_Row :: struct {
	text_offset:             u32,
	text_bytes:              u32,
	region_start_text_offset: u32,
	region_end_text_offset:   u32,
	region_visible:           bool,
	search_start_text_offset: u32,
	search_end_text_offset:   u32,
	search_visible:           bool,
	has_content:              bool,
}

@(private)
Renderer_State :: struct {
	allocator:        runtime.Allocator,
	constraints:      display.Viewport_Constraints,
	profile:          display.Display_Profile,
	color:            ui.Renderer_Color_Capability,
	icons:            Icon_Profile,
	max_output_bytes: u32,
	terminal_cursor_style_active: bool,
}

@(private)
Render_Frame :: struct {
	allocator: runtime.Allocator,
	output:    []u8,
	used:      u32,
	color:     ui.Renderer_Color_Capability,
	style:     Terminal_Style,
}

/* renderer_init creates one bounded physical renderer for one geometry. */
renderer_init :: proc(
	renderer: ^Renderer,
	config: Renderer_Config,
) -> (ok: bool, failure: Failure_Context) {
	if renderer == nil || renderer.state != nil || renderer.closed ||
	   config.allocator.procedure == nil || config.max_output_bytes == 0 ||
	   config.max_output_bytes > MAX_OUTPUT_BYTES || config.color > .True_Color {
		return false, Failure_Context{code = .Invalid_Renderer}
	}
	_, constraints_ok, constraints_failure := display.representation_estimate(
		config.constraints,
		0,
		0,
		0,
		0,
		0,
	)
	if !constraints_ok || !display.display_profile_is_valid(config.profile) {
		return false, Failure_Context {
			code = .Invalid_Renderer,
			display_failure = constraints_failure,
		}
	}
	state, allocation_error := new(Renderer_State, config.allocator)
	if allocation_error != nil {
		return false, Failure_Context {
			code = .Renderer_Memory_Limit,
			actual = u64(size_of(Renderer_State)),
		}
	}
	state.allocator = config.allocator
	state.constraints = config.constraints
	state.profile = config.profile
	state.color = config.color
	state.icons = config.icons if config.icons != .Invalid else .Portable
	state.max_output_bytes = config.max_output_bytes
	renderer.state = state
	return true, {}
}

/* renderer_resize changes physical geometry and forces the next full redraw. */
renderer_resize :: proc(
	renderer: ^Renderer,
	constraints: display.Viewport_Constraints,
) -> (ok: bool, failure: Failure_Context) {
	state := renderer_state(renderer)
	if state == nil {
		return false, Failure_Context{code = .Invalid_Renderer}
	}
	_, constraints_ok, display_failure := display.representation_estimate(
		constraints,
		0,
		0,
		0,
		0,
		0,
	)
	if !constraints_ok {
		return false, Failure_Context {
			code = .Invalid_Renderer,
			display_failure = display_failure,
		}
	}
	state.constraints = constraints
	return true, {}
}

/* renderer_close releases physical renderer ownership and closes it. */
renderer_close :: proc(renderer: ^Renderer) -> (ok: bool, failure: Failure_Context) {
	state := renderer_state(renderer)
	if state == nil {
		return false, Failure_Context{code = .Invalid_Renderer}
	}
	allocator := state.allocator
	free(state, allocator)
	renderer.state = nil
	renderer.closed = true
	return true, {}
}

@(private)
frame_capture_search :: proc(
	cached: ^Cached_Row,
	source: display.Snapshot_View,
	row: display.Display_Row,
) {
	if row.boundary_count == 0 || cached.text_bytes == 0 {
		return
	}
	boundaries := source.boundaries[
		row.first_boundary:row.first_boundary + row.boundary_count
	]
	visible_start := boundaries[0].source_byte_offset
	visible_end := boundaries[len(boundaries) - 1].source_byte_offset
	for match in source.search_matches {
		if !match.current || !match.intersects_visible {
			continue
		}
		match_start := max(match.start, visible_start)
		match_end := min(match.end, visible_end)
		if match_start >= match_end {
			continue
		}
		start_text_offset, start_found := region_boundary_text_offset(boundaries, match_start)
		end_text_offset, end_found := region_boundary_text_offset(boundaries, match_end)
		if !start_found || !end_found || start_text_offset >= end_text_offset {
			continue
		}
		cached.search_start_text_offset = start_text_offset
		cached.search_end_text_offset = end_text_offset
		cached.search_visible = true
		return
	}
}

@(private)
frame_capture_region :: proc(
	cached: ^Cached_Row,
	source: display.Snapshot_View,
	row: display.Display_Row,
) {
	if !source.region.active || (!source.region.rectangular && source.region.start == source.region.end) ||
	   row.boundary_count == 0 || cached.text_bytes == 0 {
		return
	}
	boundaries := source.boundaries[
		row.first_boundary:row.first_boundary + row.boundary_count
	]
	visible_start := boundaries[0].source_byte_offset
	visible_end := boundaries[len(boundaries) - 1].source_byte_offset
	region_start := max(source.region.start, visible_start)
	region_end := min(source.region.end, visible_end)
	if source.region.rectangular {
		if !row.region_active do return
		region_start = max(row.region_start, visible_start)
		region_end = min(row.region_end, visible_end)
	}
	if region_start >= region_end {
		return
	}
	start_text_offset, start_found := region_boundary_text_offset(boundaries, region_start)
	end_text_offset, end_found := region_boundary_text_offset(boundaries, region_end)
	assert(start_found && end_found)
	assert(start_text_offset < end_text_offset && end_text_offset <= cached.text_bytes)
	cached.region_start_text_offset = start_text_offset
	cached.region_end_text_offset = end_text_offset
	cached.region_visible = true
}

@(private)
region_boundary_text_offset :: proc(
	boundaries: []display.Boundary_Map,
	source_offset: editor.Byte_Offset,
) -> (text_offset: u32, found: bool) {
	for boundary in boundaries {
		if boundary.source_byte_offset == source_offset {
			return boundary.row_text_offset, true
		}
	}
	return 0, false
}

@(private)
frame_close :: proc(frame: ^Render_Frame) {
	if frame.allocator.procedure == nil {
		return
	}
	delete(frame.output, frame.allocator)
	frame^ = {}
}

@(private)
frame_append_cursor :: proc(frame: ^Render_Frame, row, column: u32) {
	frame_append_string(frame, "\x1b[")
	frame_append_decimal(frame, row)
	frame_append_byte(frame, ';')
	frame_append_decimal(frame, column)
	frame_append_byte(frame, 'H')
}

@(private)
frame_append_decimal :: proc(frame: ^Render_Frame, value: u32) {
	digits: [10]u8
	count := len(digits)
	current := value
	for {
		count -= 1
		digits[count] = u8('0') + u8(current % 10)
		current /= 10
		if current == 0 {
			break
		}
	}
	frame_append_bytes(frame, digits[count:])
}

@(private)
frame_append_string :: proc(frame: ^Render_Frame, value: string) {
	assert(u64(frame.used) + u64(len(value)) <= u64(len(frame.output)))
	copy(frame.output[frame.used:], value)
	frame.used += u32(len(value))
}

@(private)
frame_append_bytes :: proc(frame: ^Render_Frame, values: []u8) {
	assert(u64(frame.used) + u64(len(values)) <= u64(len(frame.output)))
	copy(frame.output[frame.used:], values)
	frame.used += u32(len(values))
}

@(private)
frame_append_byte :: proc(frame: ^Render_Frame, value: u8) {
	assert(frame.used < u32(len(frame.output)))
	frame.output[frame.used] = value
	frame.used += 1
}

@(private)
renderer_state :: proc(renderer: ^Renderer) -> ^Renderer_State {
	if renderer == nil || renderer.state == nil || renderer.closed {
		return nil
	}
	return (^Renderer_State)(renderer.state)
}

@(private)
renderer_memory_failure :: proc(actual: u64) -> Failure_Context {
	return Failure_Context {
		code = .Renderer_Memory_Limit,
		limit = u64(MAX_OUTPUT_BYTES),
		actual = actual,
	}
}
