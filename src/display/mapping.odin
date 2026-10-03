// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package display

import "../editor"
import "../view"

/* snapshot_is_compatible checks every identity and policy that makes derived layout reusable. */
snapshot_is_compatible :: proc(
	snapshot: Snapshot,
	logical: view.Snapshot,
	constraints: Viewport_Constraints,
	profile: Display_Profile,
) -> (compatible: bool, failure: Failure_Context) {
	state := snapshot_state(snapshot)
	if state == nil {
		return false, Failure_Context{code = .Closed_Snapshot}
	}
	key := state.key
	if logical.buffer_id != key.buffer_id || logical.revision != key.buffer_revision {
		return false, Failure_Context {
			code = .Stale_Snapshot,
			buffer_id = logical.buffer_id,
			buffer_revision = logical.revision,
			snapshot_id = key.snapshot_id,
		}
	}
	if u64(logical.view_id) != key.view_id ||
	   logical.view_generation != key.view_generation ||
	   logical.state_generation != key.view_state_generation ||
	   Display_Profile_ID(u64(logical.display_profile_id)) != key.display_profile_id ||
	   logical.tab_width != key.tab_width || constraints != key.constraints ||
	   profile.id != key.display_profile_id ||
	   profile.unicode.version != key.unicode_version {
		return false, Failure_Context {
			code = .Incompatible_Snapshot,
			buffer_id = logical.buffer_id,
			buffer_revision = logical.revision,
			snapshot_id = key.snapshot_id,
			display_profile_id = profile.id,
		}
	}
	return true, {}
}

/* snapshot_source_to_display maps one exact current source boundary into the viewport. */
snapshot_source_to_display :: proc(
	snapshot: Snapshot,
	position: editor.Position,
) -> (display_position: Display_Position, ok: bool, failure: Failure_Context) {
	state := snapshot_state(snapshot)
	if state == nil {
		return {}, false, Failure_Context{code = .Closed_Snapshot}
	}
	if position.buffer_id != state.key.buffer_id {
		return {}, false, Failure_Context {
			code = .Incompatible_Snapshot,
			buffer_id = position.buffer_id,
			buffer_revision = position.revision,
			snapshot_id = state.key.snapshot_id,
		}
	}
	if position.revision != state.key.buffer_revision {
		return {}, false, Failure_Context {
			code = .Stale_Snapshot,
			buffer_id = position.buffer_id,
			buffer_revision = position.revision,
			snapshot_id = state.key.snapshot_id,
		}
	}
	boundary_index, found := source_boundary_index(state.boundaries, position.byte_offset)
	if !found {
		return {}, false, mapping_failure(state, u64(position.byte_offset))
	}
	for row in state.rows {
		first := boundary_index
		row_start := int(row.first_boundary)
		row_end := row_start + int(row.boundary_count)
		if first < row_start || first >= row_end {
			continue
		}
		boundary := state.boundaries[first]
		absolute_column := u64(boundary.display_column)
		visible_start := u64(row.visible_start)
		if absolute_column < visible_start {
			break
		}
		return Display_Position {
			viewport_row = row.viewport_row,
			column = Display_Column(absolute_column - visible_start),
		}, true, {}
	}
	return {}, false, mapping_failure(state, u64(position.byte_offset))
}

/* snapshot_display_to_source maps one exact viewport grapheme boundary to canonical text. */
snapshot_display_to_source :: proc(
	snapshot: Snapshot,
	display_position: Display_Position,
) -> (position: editor.Position, ok: bool, failure: Failure_Context) {
	state := snapshot_state(snapshot)
	if state == nil {
		return {}, false, Failure_Context{code = .Closed_Snapshot}
	}
	row_index := u32(display_position.viewport_row)
	if row_index >= u32(len(state.rows)) {
		return {}, false, mapping_failure(state, u64(row_index))
	}
	row := state.rows[row_index]
	if !row.has_content {
		return {}, false, mapping_failure(state, u64(row_index))
	}
	absolute_column := u64(row.visible_start) + u64(display_position.column)
	boundaries := state.boundaries[
		int(row.first_boundary):int(row.first_boundary + row.boundary_count)
	]
	low := 0
	high := len(boundaries)
	for low < high {
		middle := low + (high - low) / 2
		column := u64(boundaries[middle].display_column)
		if column < absolute_column {
			low = middle + 1
		} else {
			high = middle
		}
	}
	if low >= len(boundaries) || u64(boundaries[low].display_column) != absolute_column {
		return {}, false, mapping_failure(state, absolute_column)
	}
	return editor.Position {
		buffer_id = state.key.buffer_id,
		revision = state.key.buffer_revision,
		byte_offset = boundaries[low].source_byte_offset,
	}, true, {}
}

/* snapshot_display_to_text_hit resolves one represented viewport cell to canonical text. */
snapshot_display_to_text_hit :: proc(
	snapshot: Snapshot,
	display_position: Display_Position,
	work_limit: u64 = OPERATING_POINTER_MAPPING_WORK,
) -> (hit: Text_Hit, ok: bool, failure: Failure_Context) {
	state := snapshot_state(snapshot)
	if state == nil {
		return {}, false, Failure_Context{code = .Closed_Snapshot}
	}
	if work_limit == 0 do return {}, false, mapping_work_failure(state, work_limit + 1, work_limit)
	row_index := u32(display_position.viewport_row)
	if row_index >= u32(len(state.rows)) ||
	   u32(display_position.column) >= state.key.constraints.width_cells {
		return {}, false, mapping_failure(state, u64(row_index))
	}
	row := state.rows[row_index]
	if !row.has_content || row.boundary_count == 0 {
		return {}, false, mapping_failure(state, u64(row_index))
	}
	absolute_column := u64(row.visible_start) + u64(display_position.column)
	boundaries := state.boundaries[
		int(row.first_boundary):int(row.first_boundary + row.boundary_count)
	]
	work: u64
	boundary_index, within_limit := first_boundary_at_or_after(
		boundaries,
		absolute_column,
		&work,
		work_limit,
	)
	if !within_limit do return {}, false, mapping_work_failure(state, work, work_limit)
	if boundary_index < len(boundaries) &&
	   u64(boundaries[boundary_index].display_column) == absolute_column {
		boundary := boundaries[boundary_index]
		if boundary.source_byte_offset != row.source_end {
			represented, representation_within_limit := row_boundary_is_represented(
				state, row, absolute_column, &work, work_limit,
			)
			if !representation_within_limit {
				return {}, false, mapping_work_failure(state, work, work_limit)
			}
			if !represented do return {}, false, mapping_failure(state, absolute_column)
		}
		return text_hit_from_boundary(
			state,
			row,
			display_position,
			boundary,
			display_position.column,
			display_position.column,
			.Exact,
		), true, {}
	}
	if boundary_index == 0 || boundary_index >= len(boundaries) {
		return {}, false, mapping_failure(state, absolute_column)
	}
	leading := boundaries[boundary_index - 1]
	trailing := boundaries[boundary_index]
	leading_column := u64(leading.display_column)
	trailing_column := u64(trailing.display_column)
	if leading_column >= absolute_column || trailing_column <= absolute_column {
		return {}, false, mapping_failure(state, absolute_column)
	}
	represented, representation_within_limit := row_span_is_represented(
		state, row, leading_column, trailing_column, &work, work_limit,
	)
	if !representation_within_limit {
		return {}, false, mapping_work_failure(state, work, work_limit)
	}
	if !represented do return {}, false, mapping_failure(state, absolute_column)
	selected := leading
	affinity := Text_Hit_Affinity.Leading
	if absolute_column - leading_column >= trailing_column - absolute_column {
		selected = trailing
		affinity = .Trailing
	}
	visible_start := u64(row.visible_start)
	return text_hit_from_boundary(
		state,
		row,
		display_position,
		selected,
		Display_Column(leading_column - visible_start),
		Display_Column(trailing_column - visible_start),
		affinity,
	), true, {}
}

/* snapshot_clamp_display_to_text_hit resolves outside motion to the nearest represented boundary. */
snapshot_clamp_display_to_text_hit :: proc(
	snapshot: Snapshot,
	viewport_row, column: i64,
	work_limit: u64 = OPERATING_POINTER_MAPPING_WORK,
) -> (hit: Text_Hit, ok: bool, failure: Failure_Context) {
	state := snapshot_state(snapshot)
	if state == nil do return {}, false, Failure_Context{code = .Closed_Snapshot}
	if work_limit == 0 do return {}, false, mapping_work_failure(state, work_limit + 1, work_limit)
	work: u64
	row_index, row_ok, row_within_limit := nearest_content_row(
		state.rows, viewport_row, &work, work_limit,
	)
	if !row_within_limit do return {}, false, mapping_work_failure(state, work, work_limit)
	if !row_ok do return {}, false, mapping_failure(state, u64(max(viewport_row, 0)))
	width := i64(state.key.constraints.width_cells)
	if column >= 0 && column < width {
		exact_work_limit := (work_limit - work) / 2
		if exact_work_limit == 0 {
			return {}, false, mapping_work_failure(state, work + 1, work_limit)
		}
		resolved, resolved_ok, resolve_failure := snapshot_display_to_text_hit(
			snapshot,
			Display_Position {
				viewport_row = Display_Row_Index(row_index),
				column = Display_Column(column),
			},
			exact_work_limit,
		)
		if resolved_ok do return resolved, true, {}
		if resolve_failure.code != .Mapping_Miss do return {}, false, resolve_failure
		// Reserve the complete failed exact-query budget before bounded fallback.
		work += exact_work_limit
	}
	row := state.rows[row_index]
	boundaries := state.boundaries[
		int(row.first_boundary):int(row.first_boundary + row.boundary_count)
	]
	selected: Boundary_Map
	selected_column: u64
	selected_distance := i64(max(i32))
	found := false
	visible_start := u64(row.visible_start)
	for boundary in boundaries {
		work += 1
		if work > work_limit do return {}, false, mapping_work_failure(state, work, work_limit)
		absolute_column := u64(boundary.display_column)
		if absolute_column < visible_start do continue
		local_column := absolute_column - visible_start
		if local_column > u64(state.key.constraints.width_cells) do continue
		if boundary.source_byte_offset != row.source_end {
			represented, representation_within_limit := row_boundary_is_represented(
				state, row, absolute_column, &work, work_limit,
			)
			if !representation_within_limit {
				return {}, false, mapping_work_failure(state, work, work_limit)
			}
			if !represented do continue
		}
		distance := abs(i64(local_column) - column)
		if !found || distance <= selected_distance {
			selected = boundary
			selected_column = local_column
			selected_distance = distance
			found = true
		}
	}
	if !found do return {}, false, mapping_failure(state, u64(max(column, 0)))
	position := Display_Position {
		viewport_row = Display_Row_Index(row_index),
		column = Display_Column(selected_column),
	}
	return text_hit_from_boundary(
		state,
		row,
		position,
		selected,
		position.column,
		position.column,
		.Exact,
	), true, {}
}

@(private)
first_boundary_at_or_after :: proc(
	boundaries: []Boundary_Map,
	column: u64,
	work: ^u64,
	work_limit: u64,
) -> (index: int, within_limit: bool) {
	low := 0
	high := len(boundaries)
	for low < high {
		work^ += 1
		if work^ > work_limit do return 0, false
		middle := low + (high - low) / 2
		if u64(boundaries[middle].display_column) < column {
			low = middle + 1
		} else {
			high = middle
		}
	}
	return low, true
}

@(private)
row_boundary_is_represented :: proc(
	state: ^Snapshot_State,
	row: Display_Row,
	column: u64,
	work: ^u64,
	work_limit: u64,
) -> (represented: bool, within_limit: bool) {
	for run in state.runs[int(row.first_run):int(row.first_run + row.run_count)] {
		work^ += 1
		if work^ > work_limit do return false, false
		start := u64(run.start_column)
		if column >= start && column <= start + u64(run.cell_count) do return true, true
	}
	return false, true
}

@(private)
nearest_content_row :: proc(
	rows: []Display_Row,
	requested: i64,
	work: ^u64,
	work_limit: u64,
) -> (selected: u32, found: bool, within_limit: bool) {
	selected_distance := i64(max(i32))
	for row in rows {
		work^ += 1
		if work^ > work_limit do return 0, false, false
		if !row.has_content do continue
		index := i64(row.viewport_row)
		distance := abs(index - requested)
		if !found || distance < selected_distance {
			selected = u32(row.viewport_row)
			selected_distance = distance
			found = true
		}
	}
	return selected, found, true
}

@(private)
row_span_is_represented :: proc(
	state: ^Snapshot_State,
	row: Display_Row,
	start, end: u64,
	work: ^u64,
	work_limit: u64,
) -> (represented: bool, within_limit: bool) {
	for run in state.runs[int(row.first_run):int(row.first_run + row.run_count)] {
		work^ += 1
		if work^ > work_limit do return false, false
		run_start := u64(run.start_column)
		run_end := run_start + u64(run.cell_count)
		if start >= run_start && end <= run_end do return true, true
	}
	return false, true
}

@(private)
text_hit_from_boundary :: proc(
	state: ^Snapshot_State,
	row: Display_Row,
	display_position: Display_Position,
	boundary: Boundary_Map,
	span_start, span_end: Display_Column,
	affinity: Text_Hit_Affinity,
) -> Text_Hit {
	return Text_Hit {
		snapshot_id = state.key.snapshot_id,
		buffer_id = state.key.buffer_id,
		buffer_revision = state.key.buffer_revision,
		view_id = state.key.view_id,
		view_generation = state.key.view_generation,
		view_state_generation = state.key.view_state_generation,
		display = display_position,
		position = {
			buffer_id = state.key.buffer_id,
			revision = state.key.buffer_revision,
			byte_offset = boundary.source_byte_offset,
		},
		logical_line = row.logical_line,
		span_start = span_start,
		span_end = span_end,
		affinity = affinity,
	}
}

@(private)
snapshot_state :: proc(snapshot: Snapshot) -> ^Snapshot_State {
	if snapshot.state == nil {
		return nil
	}
	return (^Snapshot_State)(snapshot.state)
}

@(private)
source_boundary_index :: proc(
	boundaries: []Boundary_Map,
	source_offset: editor.Byte_Offset,
) -> (index: int, ok: bool) {
	low := 0
	high := len(boundaries)
	for low < high {
		middle := low + (high - low) / 2
		if boundaries[middle].source_byte_offset < source_offset {
			low = middle + 1
		} else {
			high = middle
		}
	}
	if low >= len(boundaries) || boundaries[low].source_byte_offset != source_offset {
		return 0, false
	}
	return low, true
}

@(private)
mapping_failure :: proc(state: ^Snapshot_State, actual: u64) -> Failure_Context {
	return Failure_Context {
		code = .Mapping_Miss,
		buffer_id = state.key.buffer_id,
		buffer_revision = state.key.buffer_revision,
		snapshot_id = state.key.snapshot_id,
		actual = actual,
	}
}

@(private)
mapping_work_failure :: proc(
	state: ^Snapshot_State,
	actual, limit: u64,
) -> Failure_Context {
	failure := mapping_failure(state, actual)
	failure.code = .Work_Limit
	failure.limit = limit
	return failure
}
