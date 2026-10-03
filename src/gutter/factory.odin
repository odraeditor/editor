// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package gutter

import "base:runtime"
import "core:fmt"

/* FACTORY_PROVIDER_ID identifies the built-in logical line-number provider. */
FACTORY_PROVIDER_ID :: Provider_ID(1)
/* FACTORY_PROVIDER_GENERATION identifies the initial built-in provider definition. */
FACTORY_PROVIDER_GENERATION :: Provider_Generation(1)
/* LINE_NUMBER_LANE_ID identifies the factory logical line-number lane. */
LINE_NUMBER_LANE_ID :: Lane_ID(1)

/* Factory_Policy selects the initial logical line-number presentation. */
Factory_Policy :: struct {
	visible:         bool,
	side:            Side,
	order:           i16,
	mode:            Numbering_Mode,
	scope:           Numbering_Scope,
	current_line:    Current_Line_Presentation,
	minimum_digits:  u16,
	maximum_digits:  u16,
	left_padding:    u8,
	right_padding:   u8,
	separator:       Representation,
}

/* DEFAULT_FACTORY_POLICY enables compact absolute logical line numbers. */
DEFAULT_FACTORY_POLICY :: Factory_Policy {
	visible = true,
	side = .Left,
	order = 100,
	mode = .Absolute,
	scope = .Logical,
	current_line = .Absolute,
	minimum_digits = 4,
	maximum_digits = 20,
	left_padding = 0,
	right_padding = 1,
	separator = {kind = .Glyph, value = "│", fallback = "|"},
}

/* Visible_Row copies one current display row's logical identity. */
Visible_Row :: struct {
	viewport_row: u32,
	logical_line: u64,
	has_content:  bool,
}

/* Factory_Request borrows one exact visible projection for line-number composition. */
Factory_Request :: struct {
	generation:          Generation,
	available_cells:     u32,
	minimum_text_cells:  u32,
	line_count:          u64,
	viewport_rows:       u32,
	rows:                []Visible_Row,
	cursor_logical_line: u64,
	cursor_visible:      bool,
	cursor_viewport_row: u32,
	policy:              Factory_Policy,
	allocator:           runtime.Allocator,
	limits:              Limits,
}

/* factory_policy_is_valid checks one complete logical numbering policy. */
factory_policy_is_valid :: proc(policy: Factory_Policy) -> bool {
	return (policy.side == .Left || policy.side == .Right) &&
		numbering_mode_is_valid(policy.mode) && numbering_scope_is_valid(policy.scope) &&
		policy.current_line >= .Absolute && policy.current_line <= .Hidden &&
		policy.minimum_digits > 0 && policy.minimum_digits <= policy.maximum_digits &&
		policy.maximum_digits <= 20 &&
		u16(policy.left_padding) + u16(policy.right_padding) + policy.maximum_digits + 1 <=
			MAX_ROW_TEXT_BYTES &&
		representation_is_valid(policy.separator)
}

/* compose_factory creates one immutable logical line-number Gutter view. */
compose_factory :: proc(request: Factory_Request) -> (View, bool, Failure_Context) {
	failure, valid := factory_request_validate(request)
	if !valid do return {}, false, failure
	if request.policy.scope == .Visual {
		return {}, false, Failure_Context{operation = .Factory, code = .Unsupported_Scope}
	}
	geometry, geometry_ok, geometry_failure := factory_geometry(request)
	if !geometry_ok do return {}, false, geometry_failure
	if request.policy.mode == .None || !request.policy.visible {
		return View {
			generation = request.generation,
			geometry = geometry,
			allocator = request.allocator,
		}, true, {}
	}

	digits := clamp(number_digits(request.line_count), request.policy.minimum_digits,
		request.policy.maximum_digits)
	return factory_materialize(request, geometry, digits)
}

/* factory_geometry resolves line-number width before display projection. */
factory_geometry :: proc(request: Factory_Request) -> (Geometry, bool, Failure_Context) {
	failure, valid := factory_request_validate(request)
	if !valid do return {}, false, failure
	if request.policy.scope == .Visual {
		return {}, false, Failure_Context{operation = .Factory, code = .Unsupported_Scope}
	}
	if request.policy.mode == .None || !request.policy.visible {
		return Geometry {
			available_cells = request.available_cells,
			text_cells = request.available_cells,
		}, true, {}
	}
	digits := clamp(number_digits(request.line_count), request.policy.minimum_digits,
		request.policy.maximum_digits)
	separator_cells := u16(1)
	lane_width := digits + u16(request.policy.left_padding) +
		u16(request.policy.right_padding) + separator_cells
	lane := factory_line_number_lane(
		lane_width,
		request.policy.side,
		request.policy.order,
		request.policy.separator,
	)
	content := Lane_Content_Observation {
		lane = LINE_NUMBER_LANE_ID,
		content_cells = lane_width,
		present = true,
	}
	geometry, geometry_ok, geometry_failure := compose_geometry(Geometry_Request {
		available_cells = request.available_cells,
		minimum_text_cells = request.minimum_text_cells,
		lanes = []Lane_Definition{lane},
		content = []Lane_Content_Observation{content},
		limits = request.limits,
	})
	if !geometry_ok {
		geometry_failure.operation = .Factory
		return {}, false, geometry_failure
	}
	return geometry, true, {}
}

/* view_close releases one composed Gutter generation exactly once. */
view_close :: proc(view: ^View) -> (bool, Failure_Context) {
	if view == nil || view.allocator.procedure == nil {
		return false, Failure_Context{operation = .Close, code = .Closed_View}
	}
	allocator := view.allocator
	if view.rows != nil do delete(view.rows, allocator)
	if view.text != nil do delete(view.text, allocator)
	view^ = {}
	return true, {}
}

@(private = "file")
factory_request_validate :: proc(request: Factory_Request) -> (Failure_Context, bool) {
	if request.generation == Generation(0) {
		return Failure_Context{operation = .Factory, code = .Invalid_Generation}, false
	}
	if request.allocator.procedure == nil || !limits_are_valid(request.limits) ||
	   !factory_policy_is_valid(request.policy) || request.available_cells == 0 ||
	   request.minimum_text_cells < MIN_TEXT_CELLS ||
	   request.minimum_text_cells > request.available_cells || request.line_count == 0 {
		return Failure_Context{operation = .Factory, code = .Invalid_Request}, false
	}
	if request.viewport_rows == 0 || request.viewport_rows > u32(request.limits.visible_rows) ||
	   len(request.rows) > int(request.viewport_rows) {
		return Failure_Context {
			operation = .Factory,
			code = .Row_Limit,
			limit = u64(request.limits.visible_rows),
			actual = u64(request.viewport_rows),
		}, false
	}
	if request.cursor_visible && request.cursor_viewport_row >= request.viewport_rows {
		return Failure_Context{operation = .Factory, code = .Invalid_Request}, false
	}
	if (request.policy.mode == .Relative || request.policy.mode == .Hybrid) &&
	   request.cursor_logical_line >= request.line_count {
		return Failure_Context{operation = .Factory, code = .Invalid_Request}, false
	}
	seen: [MAX_VISIBLE_ROWS]bool
	for row in request.rows {
		if row.viewport_row >= request.viewport_rows || row.logical_line >= request.line_count ||
		   seen[row.viewport_row] {
			return Failure_Context{operation = .Factory, code = .Invalid_Request}, false
		}
		seen[row.viewport_row] = true
	}
	return {}, true
}

@(private = "file")
factory_line_number_lane :: proc(
	width: u16,
	side: Side,
	order: i16,
	separator: Representation,
) -> Lane_Definition {
	return Lane_Definition {
		id = LINE_NUMBER_LANE_ID,
		provider = FACTORY_PROVIDER_ID,
		provider_generation = FACTORY_PROVIDER_GENERATION,
		side = side,
		order = order,
		attachments = {.Logical_Line},
		width_policy = .Automatic,
		minimum_cells = width,
		maximum_cells = width,
		alignment = .Right,
		visibility = .Configured,
		collision = .Highest_Priority,
		priority = max(u16),
		style_role = .Line_Number,
		separator = separator,
	}
}

@(private = "file")
factory_materialize :: proc(
	request: Factory_Request,
	geometry: Geometry,
	digits: u16,
) -> (View, bool, Failure_Context) {
	side_cells := geometry.left_cells
	if request.policy.side == .Right do side_cells = geometry.right_cells
	if side_cells == 0 {
		return View {
			generation = request.generation,
			geometry = geometry,
			allocator = request.allocator,
		}, true, {}
	}
	separator := request.policy.separator.value
	row_bytes := u32(side_cells - 1) + u32(len(separator))
	text_bytes := row_bytes * request.viewport_rows
	if row_bytes > u32(request.limits.row_text_bytes) ||
	   text_bytes > request.limits.view_text_bytes {
		return {}, false, Failure_Context {
			operation = .Factory,
			code = .Text_Limit,
			limit = u64(request.limits.view_text_bytes),
			actual = u64(text_bytes),
		}
	}
	text, text_error := make([]u8, int(text_bytes), request.allocator)
	if text_error != nil do return {}, false, factory_allocation_failure(text_bytes)
	rows, rows_error := make([]Row_View, int(request.viewport_rows), request.allocator)
	if rows_error != nil {
		delete(text, request.allocator)
		return {}, false, factory_allocation_failure(
			u64(request.viewport_rows) * u64(size_of(Row_View)),
		)
	}
	for viewport_row in 0 ..< request.viewport_rows {
		start := viewport_row * row_bytes
		row_storage := text[start:start + row_bytes]
		for &value in row_storage do value = ' '
		if request.policy.side == .Left {
			copy(row_storage[int(row_bytes) - len(separator):], transmute([]u8)(separator))
		} else {
			copy(row_storage[:len(separator)], transmute([]u8)(separator))
		}
		row := Row_View {
			viewport_row = viewport_row,
		}
		if request.policy.side == .Left {
			row.left_offset = start
			row.left_bytes = u16(row_bytes)
			row.left_cells = side_cells
			row.left_separator_bytes = u8(len(separator))
			row.left_role = .Line_Number
		} else {
			row.right_offset = start
			row.right_bytes = u16(row_bytes)
			row.right_cells = side_cells
			row.right_separator_bytes = u8(len(separator))
			row.right_role = .Line_Number
		}
		rows[viewport_row] = row
	}
	for visible in request.rows {
		row := &rows[visible.viewport_row]
		row.logical_line = visible.logical_line
		row.current = request.cursor_visible && visible.viewport_row == request.cursor_viewport_row
		if row.current {
			if request.policy.side == .Left {
				row.left_role = .Current_Line_Number
			} else {
				row.right_role = .Current_Line_Number
			}
		}
		line_number, present := factory_row_number(request, visible.logical_line, row.current)
		if visible.has_content && present {
			row_output := text[row.left_offset:row.left_offset + u32(row.left_bytes)]
			if request.policy.side == .Right {
				row_output = text[row.right_offset:row.right_offset + u32(row.right_bytes)]
			}
			factory_write_number_row(
				row_output,
				line_number,
				digits,
				request.policy,
			)
		}
	}
	retained := u64(text_bytes) + u64(request.viewport_rows) * u64(size_of(Row_View))
	return View {
		generation = request.generation,
		geometry = geometry,
		text = text,
		rows = rows,
		accounting = {
			visible_lanes = 1,
			visible_rows = u16(request.viewport_rows),
			text_bytes = text_bytes,
			work = request.viewport_rows,
			retained_bytes = retained,
		},
		allocator = request.allocator,
	}, true, {}
}

@(private = "file")
factory_write_number_row :: proc(
	output: []u8,
	line_number: u64,
	digits: u16,
	policy: Factory_Policy,
) {
	storage: [20]u8
	number := fmt.bprintf(storage[:], "%d", line_number)
	offset := int(policy.left_padding) + int(digits) - len(number)
	if policy.side == .Right do offset += len(policy.separator.value)
	copy(output[offset:], transmute([]u8)(number))
}

@(private = "file")
factory_row_number :: proc(
	request: Factory_Request,
	logical_line: u64,
	current: bool,
) -> (number: u64, present: bool) {
	if current {
		switch request.policy.current_line {
		case .Absolute:
			return logical_line + 1, true
		case .Zero:
			return 0, true
		case .Hidden:
			return 0, false
		case .Invalid:
			return 0, false
		}
	}
	switch request.policy.mode {
	case .Absolute:
		return logical_line + 1, true
	case .Relative, .Hybrid:
		if logical_line >= request.cursor_logical_line {
			return logical_line - request.cursor_logical_line, true
		}
		return request.cursor_logical_line - logical_line, true
	case .None, .Invalid:
		return 0, false
	}
	return 0, false
}

@(private = "file")
number_digits :: proc(value: u64) -> u16 {
	digits: u16 = 1
	remaining := value
	for remaining >= 10 {
		remaining /= 10
		digits += 1
	}
	return digits
}

@(private = "file")
factory_allocation_failure :: proc(actual: $T) -> Failure_Context {
	return Failure_Context{operation = .Factory, code = .Allocation, actual = u64(actual)}
}
