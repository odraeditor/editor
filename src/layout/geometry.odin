// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package layout

@(private)
Minimum :: struct {
	rows:    i32,
	columns: i32,
}

/* registry_materialize publishes one complete checked geometry generation. */
registry_materialize :: proc(
	registry: ^Registry,
	expected: Layout_Handle,
	request: Geometry_Request,
	mode := Materialization_Mode.Operating,
) -> (handle: Layout_Handle, ok: bool, failure: Failure_Context) {
	data, resolved := resolve_layout(registry, expected, .Materialize)
	if resolved.code != .None {
		return {}, false, resolved
	}
	if mode != .Operating && mode != .External_Shrink {
		return {}, false, data_failure(data, .Materialize, .Invalid_Geometry)
	}
	materialized, materialize_failure := geometry_materialize_data(
		data,
		request,
		mode,
		.Materialize,
		true,
	)
	if !materialized {
		return {}, false, materialize_failure
	}
	handle = current_layout_handle(data)
	registry_notify_publication(registry)
	return handle, true, {}
}

@(private)
geometry_materialize_data :: proc(
	data: ^Registry_Data,
	request: Geometry_Request,
	mode: Materialization_Mode,
	operation: Operation,
	advance_generation: bool,
) -> (ok: bool, failure: Failure_Context) {
	if !geometry_request_is_valid(request) {
		return false, data_failure(data, operation, .Invalid_Geometry)
	}
	operating: [MAX_NODES]Minimum
	semantic: [MAX_NODES]Minimum
	work: u64
	operating_root, operating_ok, operating_failure := compute_minimum(
		data,
		data.root,
		true,
		&operating,
		&work,
		operation,
	)
	if !operating_ok {
		return false, operating_failure
	}
	semantic_root, semantic_ok, semantic_failure := compute_minimum(
		data,
		data.root,
		false,
		&semantic,
		&work,
		operation,
	)
	if !semantic_ok {
		return false, semantic_failure
	}
	root_rect := Rect {
		row = 0,
		column = 0,
		height = request.rows - request.global_reserved_rows,
		width = request.columns - request.global_reserved_columns,
	}
	state := Geometry_State.Operating
	minimums := &operating
	if !minimum_fits(operating_root, root_rect) {
		if mode == .Operating {
			failure = data_failure(data, operation, .Operating_Minimum)
			failure.maximum = minimum_area(operating_root)
			failure.actual = rect_area(root_rect)
			return false, failure
		}
		if !minimum_fits(semantic_root, root_rect) {
			if advance_generation && data.generation == Layout_Generation(max(u64)) {
				return false, data_failure(data, operation, .Generation_Limit)
			}
			for &slot in data.nodes {
				if slot.live {
					slot.geometry = {}
				}
			}
			if advance_generation {
				data.generation = Layout_Generation(u64(data.generation) + 1)
			}
			data.geometry_request = request
			data.geometry_state = .Insufficient
			data.geometry_work = work
			return true, {}
		}
		state = .Semantic
		minimums = &semantic
	}
	proposed: [MAX_NODES]Pane_Geometry
	assigned, assign_failure := assign_geometry(
		data,
		data.root,
		root_rect,
		minimums,
		&proposed,
		&work,
		operation,
	)
	if !assigned {
		return false, assign_failure
	}
	if !validate_geometry(data, data.root, root_rect, minimums, &proposed, &work) {
		return false, data_failure(data, operation, .Invalid_Geometry)
	}
	if advance_generation && data.generation == Layout_Generation(max(u64)) {
		return false, data_failure(data, operation, .Generation_Limit)
	}
	for &slot, index in data.nodes {
		if slot.live {
			slot.geometry = proposed[index]
		}
	}
	if advance_generation {
		data.generation = Layout_Generation(u64(data.generation) + 1)
	}
	data.geometry_request = request
	data.geometry_state = state
	data.geometry_work = work
	return true, {}
}

@(private)
compute_minimum :: proc(
	data: ^Registry_Data,
	ref: Node_Ref,
	operating: bool,
	minimums: ^[MAX_NODES]Minimum,
	work: ^u64,
	operation: Operation,
) -> (minimum: Minimum, ok: bool, failure: Failure_Context) {
	if !consume_geometry_work(data, work) {
		return {}, false, data_failure(data, operation, .Geometry_Work_Limit)
	}
	slot := resolve_node(data, ref)
	if slot == nil {
		return {}, false, data_failure(data, operation, .Invalid_Topology)
	}
	if slot.kind == .Pane {
		minimum = Minimum{rows = SEMANTIC_CONTENT_ROWS + PANE_STATUS_ROWS, columns = SEMANTIC_COLUMNS}
		if operating {
			rows, rows_ok := checked_add_i32(data.policy.operating_content_rows, PANE_STATUS_ROWS)
			if !rows_ok {
				return {}, false, data_failure(data, operation, .Checked_Integer_Overflow)
			}
			minimum.rows = rows
			minimum.columns = data.policy.operating_columns
		}
		minimums[int(ref.slot)] = minimum
		return minimum, true, {}
	}
	if slot.kind != .Partition || (slot.arrangement != .Above_Below && slot.arrangement != .Left_Right) ||
	   slot.first_weight == 0 || slot.second_weight == 0 {
		return {}, false, data_failure(data, operation, .Invalid_Topology)
	}
	first, first_ok, first_failure := compute_minimum(data, slot.first, operating, minimums, work, operation)
	if !first_ok {
		return {}, false, first_failure
	}
	second, second_ok, second_failure := compute_minimum(data, slot.second, operating, minimums, work, operation)
	if !second_ok {
		return {}, false, second_failure
	}
	if slot.arrangement == .Above_Below {
		rows, rows_ok := checked_add_i32(first.rows, second.rows)
		if !rows_ok {
			return {}, false, data_failure(data, operation, .Checked_Integer_Overflow)
		}
		minimum = Minimum{rows = rows, columns = max(first.columns, second.columns)}
	} else {
		columns, columns_ok := checked_add_i32(first.columns, second.columns)
		if columns_ok {
			columns, columns_ok = checked_add_i32(columns, 1)
		}
		if !columns_ok {
			return {}, false, data_failure(data, operation, .Checked_Integer_Overflow)
		}
		minimum = Minimum{rows = max(first.rows, second.rows), columns = columns}
	}
	minimums[int(ref.slot)] = minimum
	return minimum, true, {}
}

@(private)
assign_geometry :: proc(
	data: ^Registry_Data,
	ref: Node_Ref,
	rect: Rect,
	minimums: ^[MAX_NODES]Minimum,
	proposed: ^[MAX_NODES]Pane_Geometry,
	work: ^u64,
	operation: Operation,
) -> (ok: bool, failure: Failure_Context) {
	if !consume_geometry_work(data, work) {
		return false, data_failure(data, operation, .Geometry_Work_Limit)
	}
	slot := resolve_node(data, ref)
	if slot == nil || !minimum_fits(minimums[int(ref.slot)], rect) {
		return false, data_failure(data, operation, .Invalid_Geometry)
	}
	proposed[int(ref.slot)].outer = rect
	if slot.kind == .Pane {
		content_height := rect.height - PANE_STATUS_ROWS
		proposed[int(ref.slot)].content = Rect {
			row = rect.row,
			column = rect.column,
			height = content_height,
			width = rect.width,
		}
		proposed[int(ref.slot)].status = Rect {
			row = rect.row + content_height,
			column = rect.column,
			height = PANE_STATUS_ROWS,
			width = rect.width,
		}
		return true, {}
	}
	first_minimum := minimums[int(slot.first.slot)]
	second_minimum := minimums[int(slot.second.slot)]
	first_rect, second_rect, separator, divided := divide_rect(
		rect,
		slot.arrangement,
		slot.first_weight,
		slot.second_weight,
		first_minimum,
		second_minimum,
	)
	if !divided {
		return false, data_failure(data, operation, .Invalid_Geometry)
	}
	proposed[int(ref.slot)].separator = separator
	first_ok, first_failure := assign_geometry(data, slot.first, first_rect, minimums, proposed, work, operation)
	if !first_ok {
		return false, first_failure
	}
	return assign_geometry(data, slot.second, second_rect, minimums, proposed, work, operation)
}

@(private)
divide_rect :: proc(
	rect: Rect,
	arrangement: Arrangement,
	first_weight, second_weight: u64,
	first_minimum, second_minimum: Minimum,
) -> (first, second, separator: Rect, ok: bool) {
	axis := rect.height
	first_floor := first_minimum.rows
	second_floor := second_minimum.rows
	if arrangement == .Left_Right {
		axis = rect.width - 1
		first_floor = first_minimum.columns
		second_floor = second_minimum.columns
	}
	if axis < first_floor + second_floor || first_weight == 0 || second_weight == 0 {
		return {}, {}, {}, false
	}
	total := u128(first_weight) + u128(second_weight)
	first_span := i32((u128(axis) * u128(first_weight)) / total)
	second_span := axis - first_span
	if first_span < first_floor {
		first_span = first_floor
		second_span = axis - first_span
	} else if second_span < second_floor {
		second_span = second_floor
		first_span = axis - second_span
	}
	if first_span < first_floor || second_span < second_floor {
		return {}, {}, {}, false
	}
	if arrangement == .Above_Below {
		first = Rect{row = rect.row, column = rect.column, height = first_span, width = rect.width}
		second = Rect{row = rect.row + first_span, column = rect.column, height = second_span, width = rect.width}
		return first, second, {}, true
	}
	if arrangement == .Left_Right {
		first = Rect{row = rect.row, column = rect.column, height = rect.height, width = first_span}
		separator = Rect{row = rect.row, column = rect.column + first_span, height = rect.height, width = 1}
		second = Rect {
			row = rect.row,
			column = separator.column + 1,
			height = rect.height,
			width = second_span,
		}
		return first, second, separator, true
	}
	return {}, {}, {}, false
}

@(private)
validate_geometry :: proc(
	data: ^Registry_Data,
	ref: Node_Ref,
	expected: Rect,
	minimums: ^[MAX_NODES]Minimum,
	proposed: ^[MAX_NODES]Pane_Geometry,
	work: ^u64,
) -> bool {
	if !consume_geometry_work(data, work) {
		return false
	}
	slot := resolve_node(data, ref)
	if slot == nil || proposed[int(ref.slot)].outer != expected ||
	   !minimum_fits(minimums[int(ref.slot)], expected) {
		return false
	}
	if slot.kind == .Pane {
		geometry := proposed[int(ref.slot)]
		return geometry.content.height >= SEMANTIC_CONTENT_ROWS &&
		       geometry.status.height == PANE_STATUS_ROWS &&
		       geometry.content.width == expected.width &&
		       geometry.status.width == expected.width &&
		       geometry.content.height + geometry.status.height == expected.height
	}
	first := proposed[int(slot.first.slot)].outer
	second := proposed[int(slot.second.slot)].outer
	separator := proposed[int(ref.slot)].separator
	if slot.arrangement == .Above_Below {
		if separator != (Rect{}) || first.row != expected.row || second.row != first.row + first.height ||
		   first.column != expected.column || second.column != expected.column ||
		   first.width != expected.width || second.width != expected.width ||
		   first.height + second.height != expected.height {
			return false
		}
	} else if separator.width != 1 || separator.height != expected.height ||
	          first.column != expected.column || separator.column != first.column + first.width ||
	          second.column != separator.column + 1 || first.row != expected.row ||
	          second.row != expected.row || first.height != expected.height ||
	          second.height != expected.height || first.width + 1 + second.width != expected.width {
		return false
	}
	return validate_geometry(data, slot.first, first, minimums, proposed, work) &&
	       validate_geometry(data, slot.second, second, minimums, proposed, work)
}

@(private)
consume_geometry_work :: proc(data: ^Registry_Data, work: ^u64) -> bool {
	if work^ >= data.policy.geometry_work {
		return false
	}
	work^ += 1
	return true
}

@(private)
minimum_fits :: proc(minimum: Minimum, rect: Rect) -> bool {
	return rect.height >= minimum.rows && rect.width >= minimum.columns
}

@(private)
minimum_area :: proc(minimum: Minimum) -> u64 {
	return u64(minimum.rows) * u64(minimum.columns)
}

@(private)
rect_area :: proc(rect: Rect) -> u64 {
	if rect.height <= 0 || rect.width <= 0 {
		return 0
	}
	return u64(rect.height) * u64(rect.width)
}

@(private)
checked_add_i32 :: proc(left, right: i32) -> (value: i32, ok: bool) {
	wide := i64(left) + i64(right)
	if wide > i64(max(i32)) || wide < i64(min(i32)) {
		return 0, false
	}
	return i32(wide), true
}
