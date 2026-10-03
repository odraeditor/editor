// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ui

import "core:unicode/utf8"

/* proposal_project_terminal_view copies one bounded already-emulated terminal surface. */
proposal_project_terminal_view :: proc(
	proposal: ^Proposal,
	request: Terminal_Projection_Request,
	rows: []Terminal_Row,
	cells: []Terminal_Cell,
) -> (handle: Object_Handle, ok: bool, failure: Failure) {
	state := proposal_state(proposal)
	if state == nil || request.model.owner_id == Owner_ID(0) ||
	   request.model.model_id == Model_ID(0) || request.model.generation == Model_Generation(0) ||
	   request.session_id == 0 || request.session_generation == 0 || request.revision == 0 ||
	   request.columns == 0 || request.rows == 0 || len(rows) != int(request.rows) ||
	   len(cells) > int(request.columns) * int(request.rows) ||
	   !utf8.valid_string(request.title) || len(request.title) > int(max(u16)) ||
	   request.damage > .Full || request.cursor.style > .Hollow_Block ||
	   (request.lifecycle != .Running && request.lifecycle != .Exited && request.lifecycle != .Failed) {
		return {}, false, generation_failure(state, .Prepare, .Invalid_Terminal_View)
	}
	for row, index in rows {
		if row.row != u16(index) {
			failure = generation_failure(state, .Prepare, .Invalid_Terminal_View)
			failure.actual = u64(index)
			return {}, false, failure
		}
	}
	previous_row, previous_column := u16(0), u16(0)
	for cell, index in cells {
		if cell.row >= request.rows || cell.column >= request.columns ||
		   cell.text_length > TERMINAL_CELL_TEXT_BYTES || cell.width > 3 ||
		   cell.style.foreground.kind > .RGB || cell.style.background.kind > .RGB ||
		   cell.style.underline_color.kind > .RGB ||
		   (index > 0 && (cell.row < previous_row ||
		    (cell.row == previous_row && cell.column <= previous_column))) ||
		   !terminal_cell_text_is_valid(cell) {
			failure = generation_failure(state, .Prepare, .Malformed_Terminal_Cell)
			failure.actual = u64(index)
			return {}, false, failure
		}
		previous_row, previous_column = cell.row, cell.column
	}
	if request.cursor.column >= request.columns || request.cursor.row >= request.rows {
		return {}, false, generation_failure(state, .Prepare, .Invalid_Terminal_View)
	}
	row_bytes := u64(len(rows)) * u64(size_of(Terminal_Row))
	cell_bytes := u64(len(cells)) * u64(size_of(Terminal_Cell))
	projection_bytes := u64(size_of(Terminal_View_State)) + row_bytes + cell_bytes
	limits := state.registry.limits
	if projection_bytes > limits.projection_bytes - state.accounting.projection_bytes {
		failure = generation_failure(state, .Prepare, .Projection_Limit)
		failure.limit = limits.projection_bytes
		failure.actual = state.accounting.projection_bytes + projection_bytes
		return {}, false, failure
	}
	title_bytes := u64(len(request.title))
	if title_bytes > limits.compact_region_bytes - state.accounting.compact_region_bytes {
		failure = generation_failure(state, .Prepare, .Compact_Region_Limit)
		failure.limit = limits.compact_region_bytes
		failure.actual = state.accounting.compact_region_bytes + title_bytes
		return {}, false, failure
	}
	if state.projection_count >= len(state.projections) || state.view_count >= len(state.views) {
		return {}, false, generation_failure(state, .Prepare, .View_Limit)
	}
	if u64(state.next_object_id) > max(u64) - 2 {
		return {}, false, generation_failure(state, .Prepare, .Generation_Limit)
	}
	new_rows, row_error := make([]Terminal_Row, state.terminal_row_count + len(rows), state.allocator)
	if row_error != nil {
		return {}, false, generation_failure(state, .Prepare, .Allocation)
	}
	new_cells, cell_error := make([]Terminal_Cell, state.terminal_cell_count + len(cells), state.allocator)
	if cell_error != nil {
		delete(new_rows, state.allocator)
		return {}, false, generation_failure(state, .Prepare, .Allocation)
	}
	copy(new_rows, state.terminal_rows)
	copy(new_rows[state.terminal_row_count:], rows)
	copy(new_cells, state.terminal_cells)
	copy(new_cells[state.terminal_cell_count:], cells)
	projection, projection_ok := next_handle(state, state.projection_count)
	view, view_ok := next_handle(state, state.view_count)
	assert(projection_ok && view_ok)
	terminal := Terminal_View_State {
		present = true,
		session_id = request.session_id,
		session_generation = request.session_generation,
		revision = request.revision,
		columns = request.columns,
		rows = request.rows,
		damage = request.damage,
		row_offset = u32(state.terminal_row_count),
		row_count = u32(len(rows)),
		cell_offset = u32(state.terminal_cell_count),
		cell_count = u32(len(cells)),
		cursor = request.cursor,
		foreground = request.foreground,
		background = request.background,
		cursor_color = request.cursor_color,
		palette = request.palette,
		lifecycle = request.lifecycle,
		exit_code = request.exit_code,
		activity_generation = request.activity_generation,
		audible_attention = request.audible_attention,
		visual_attention = request.visual_attention,
		title_offset = u32(state.accounting.compact_region_bytes),
		title_bytes = u16(len(request.title)),
	}
	if state.terminal_rows != nil do delete(state.terminal_rows, state.allocator)
	if state.terminal_cells != nil do delete(state.terminal_cells, state.allocator)
	state.terminal_rows = new_rows
	state.terminal_cells = new_cells
	state.terminal_row_count += len(rows)
	state.terminal_cell_count += len(cells)
	state.projections[state.projection_count] = Projection_Descriptor {
		handle = projection,
		model = request.model,
		byte_count = projection_bytes,
		item_count = u32(len(cells)),
		read_only = true,
	}
	state.projection_count += 1
	state.views[state.view_count] = Visual_View_Descriptor {
		handle = view,
		kind = .Terminal_View,
		projection = projection,
		read_only = true,
		terminal = terminal,
	}
	state.view_count += 1
	copy(
		state.compact_content[int(state.accounting.compact_region_bytes):],
		transmute([]u8)request.title,
	)
	state.accounting.projection_bytes += projection_bytes
	state.accounting.compact_region_bytes += title_bytes
	state.accounting.registry_bytes += row_bytes + cell_bytes
	return view, true, {}
}

/* snapshot_terminal_rows borrows one terminal view's immutable row metadata. */
snapshot_terminal_rows :: proc(
	view: Snapshot_View,
	descriptor: Visual_View_Descriptor,
) -> ([]Terminal_Row, bool) {
	if descriptor.kind != .Terminal_View do return nil, false
	state := descriptor.terminal
	end := u64(state.row_offset) + u64(state.row_count)
	if end > u64(len(view.terminal_rows)) do return nil, false
	return view.terminal_rows[state.row_offset:u32(end)], true
}

/* snapshot_terminal_cells borrows one terminal view's immutable visible cells. */
snapshot_terminal_cells :: proc(
	view: Snapshot_View,
	descriptor: Visual_View_Descriptor,
) -> ([]Terminal_Cell, bool) {
	if descriptor.kind != .Terminal_View do return nil, false
	state := descriptor.terminal
	end := u64(state.cell_offset) + u64(state.cell_count)
	if end > u64(len(view.terminal_cells)) do return nil, false
	return view.terminal_cells[state.cell_offset:u32(end)], true
}

/* snapshot_terminal_title borrows copied non-executable title metadata. */
snapshot_terminal_title :: proc(
	view: Snapshot_View,
	descriptor: Visual_View_Descriptor,
) -> (string, bool) {
	if descriptor.kind != .Terminal_View do return "", false
	state := descriptor.terminal
	end := u64(state.title_offset) + u64(state.title_bytes)
	if end > u64(len(view.compact_content)) do return "", false
	return string(view.compact_content[state.title_offset:u32(end)]), true
}

@(private)
terminal_view_matches_projection :: proc(
	state: ^Generation_State,
	terminal: Terminal_View_State,
	projection: ^Projection_Descriptor,
) -> bool {
	if state == nil || projection == nil || !terminal_view_state_is_valid(terminal) ||
	   projection.read_only == false || projection.item_count != terminal.cell_count ||
	   u64(terminal.row_offset) + u64(terminal.row_count) > u64(state.terminal_row_count) ||
	   u64(terminal.cell_offset) + u64(terminal.cell_count) > u64(state.terminal_cell_count) ||
	   u64(terminal.title_offset) + u64(terminal.title_bytes) > state.accounting.compact_region_bytes {
		return false
	}
	return true
}

@(private)
terminal_cell_text_is_valid :: proc(cell: Terminal_Cell) -> bool {
	copy_cell := cell
	text := string(copy_cell.text[:int(copy_cell.text_length)])
	if !utf8.valid_string(text) do return false
	for value in transmute([]u8)text {
		if value < 0x20 || value == 0x7f do return false
	}
	return true
}
