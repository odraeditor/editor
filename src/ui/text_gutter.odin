// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ui

import "core:unicode/utf8"

/* proposal_project_text_gutter copies one composed Gutter into an existing TextView. */
proposal_project_text_gutter :: proc(
	proposal: ^Proposal,
	text_view: Object_Handle,
	generation: u64,
	left_cells, right_cells: u16,
	text_cells: u32,
	rows: []Text_Gutter_Row_Definition,
) -> (ok: bool, failure: Failure) {
	state := proposal_state(proposal)
	view, view_ok := resolve_view(state, text_view)
	if !view_ok || view.kind != .Text_View || !view.text.present || view.text.gutter.present ||
	   generation == 0 || text_cells < 8 || len(rows) == 0 ||
	   len(rows) > MAX_TEXT_GUTTER_ROWS {
		return false, object_failure(state.registry, .Prepare, .Invalid_Text_View, text_view)
	}
	retained_bytes: u64
	for row, index in rows {
		if row.viewport_row != u32(index) || row.left_cells != left_cells ||
		   row.right_cells != right_cells || !text_gutter_text_is_valid(row.left_text) ||
		   !text_gutter_text_is_valid(row.right_text) ||
		   int(row.left_separator_bytes) > len(row.left_text) ||
		   int(row.right_separator_bytes) > len(row.right_text) ||
		   left_cells > 0 && !resolve_style_role(state, row.left_style_role) ||
		   right_cells > 0 && !resolve_style_role(state, row.right_style_role) {
			return false, object_failure(state.registry, .Prepare, .Invalid_Text_View, text_view)
		}
		retained_bytes += u64(len(row.left_text)) + u64(len(row.right_text))
	}
	limits := state.registry.limits
	if retained_bytes > limits.compact_region_bytes - state.accounting.compact_region_bytes {
		failure = object_failure(state.registry, .Prepare, .Compact_Region_Limit, text_view)
		failure.limit = limits.compact_region_bytes
		failure.actual = state.accounting.compact_region_bytes + retained_bytes
		return false, failure
	}
	gutter := Text_Gutter_State {
		present = true,
		generation = generation,
		left_cells = left_cells,
		right_cells = right_cells,
		text_cells = text_cells,
		row_count = u8(len(rows)),
	}
	offset := u32(state.accounting.compact_region_bytes)
	for row, index in rows {
		entry := &gutter.rows[index]
		entry^ = Text_Gutter_Row_Descriptor {
			viewport_row = row.viewport_row,
			logical_line = row.logical_line,
			left_offset = offset,
			left_bytes = u16(len(row.left_text)),
			left_cells = row.left_cells,
			left_separator_bytes = row.left_separator_bytes,
			left_style_role = row.left_style_role,
			right_cells = row.right_cells,
			right_separator_bytes = row.right_separator_bytes,
			right_style_role = row.right_style_role,
			current = row.current,
		}
		copy(state.compact_content[offset:offset + u32(len(row.left_text))],
			transmute([]u8)row.left_text)
		offset += u32(len(row.left_text))
		entry.right_offset = offset
		entry.right_bytes = u16(len(row.right_text))
		copy(state.compact_content[offset:offset + u32(len(row.right_text))],
			transmute([]u8)row.right_text)
		offset += u32(len(row.right_text))
	}
	view.text.gutter = gutter
	state.accounting.compact_region_bytes += retained_bytes
	return true, {}
}

/* snapshot_text_gutter_row borrows one checked copied row from a live snapshot. */
snapshot_text_gutter_row :: proc(
	view: Snapshot_View,
	text: Text_View_State,
	viewport_row: u32,
) -> (row: Text_Gutter_Row_Descriptor, left, right: string, ok: bool) {
	if !text.gutter.present || viewport_row >= u32(text.gutter.row_count) {
		return {}, "", "", false
	}
	row = text.gutter.rows[viewport_row]
	left_end := u64(row.left_offset) + u64(row.left_bytes)
	right_end := u64(row.right_offset) + u64(row.right_bytes)
	if left_end > u64(len(view.compact_content)) || right_end > u64(len(view.compact_content)) {
		return {}, "", "", false
	}
	left = string(view.compact_content[row.left_offset:u32(left_end)])
	right = string(view.compact_content[row.right_offset:u32(right_end)])
	return row, left, right, true
}

@(private)
text_gutter_contract_is_valid :: proc(state: ^Generation_State, gutter: Text_Gutter_State) -> bool {
	if !text_gutter_state_shape_is_valid(gutter) do return false
	if !gutter.present do return true
	for index in 0 ..< int(gutter.row_count) {
		row := gutter.rows[index]
		left_end := u64(row.left_offset) + u64(row.left_bytes)
		right_end := u64(row.right_offset) + u64(row.right_bytes)
		if left_end > state.accounting.compact_region_bytes ||
		   right_end > state.accounting.compact_region_bytes ||
		   gutter.left_cells > 0 && !resolve_style_role(state, row.left_style_role) ||
		   gutter.right_cells > 0 && !resolve_style_role(state, row.right_style_role) {
			return false
		}
	}
	return true
}

@(private = "file")
text_gutter_text_is_valid :: proc(value: string) -> bool {
	if !utf8.valid_string(value) do return false
	for byte in transmute([]u8)value {
		if byte == 0 || byte == '\n' || byte == '\r' || byte == '\t' do return false
	}
	return true
}
