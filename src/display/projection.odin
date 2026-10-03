// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package display

import "../editor"
import "../view"
import "base:runtime"
import "core:unicode/utf8"

@(private)
ROW_SCAN_CHUNK_BYTES :: u64(4 * KIBIBYTE)
@(private)
LINE_CHECKPOINT_INTERVAL_BYTES :: u64(256)

@(private)
Snapshot_State :: struct {
	allocator:   runtime.Allocator,
	key:         Snapshot_Key,
	text:        []u8,
	rows:        []Display_Row,
	runs:        []Text_Run,
	boundaries:  []Boundary_Map,
	checkpoints: []Line_Checkpoint,
	cursor:      Cursor_Target,
	region:      Region_Map,
	search_matches: []Search_Match_Map,
	accounting:  Resource_Accounting,
}

@(private)
Workspace :: struct {
	allocator:  runtime.Allocator,
	source:     []u8,
	text:       []u8,
	rows:       []Display_Row,
	runs:       []Text_Run,
	boundaries: []Boundary_Map,
	checkpoints: []Line_Checkpoint,
	text_count: u32,
	row_count:  u32,
	run_count:  u32,
	boundary_count: u32,
	checkpoint_count: u32,
	source_bytes_examined: u64,
	cursor:     Cursor_Target,
	region:     Region_Map,
	rectangle_ranges: []Selection_Range,
	rectangle_top_line: u64,
	search_matches: []Search_Match_Map,
}

/* project creates one immutable bounded display snapshot from checked editor state. */
project :: proc(
	buffer: ^editor.Buffer,
	request: Projection_Request,
) -> (snapshot: Snapshot, ok: bool, failure: Failure_Context) {
	return project_internal(buffer, request, nil)
}

/* project_view copies the exact view visibility generation before projection. */
project_view :: proc(
	buffer: ^editor.Buffer,
	registry: ^view.Registry,
	handle: view.View_Handle,
	request: Projection_Request,
) -> (snapshot: Snapshot, ok: bool, failure: Failure_Context) {
	if registry == nil || request.view.hidden_range_count > view.MAX_HIDDEN_RANGES {
		return {}, false, Failure_Context {
			code = .Invalid_Request,
			buffer_id = request.view.buffer_id,
			buffer_revision = request.view.revision,
			snapshot_id = request.snapshot_id,
		}
	}
	ranges, allocation_error := make(
		[]view.Hidden_Range,
		int(request.view.hidden_range_count),
		request.allocators.temporary,
	)
	if allocation_error != nil {
		return {}, false, temporary_failure(
			request.snapshot_id,
			u64(request.view.hidden_range_count) * u64(size_of(view.Hidden_Range)),
		)
	}
	defer delete(ranges, request.allocators.temporary)
	visibility, copied, _ := view.visibility_copy_ranges(registry, handle, ranges)
	if !copied || visibility.generation != request.view.visibility_generation ||
	   visibility.source_revision != request.view.revision ||
	   visibility.range_count != request.view.hidden_range_count {
		return {}, false, Failure_Context {
			code = .Stale_Snapshot,
			buffer_id = request.view.buffer_id,
			buffer_revision = request.view.revision,
			snapshot_id = request.snapshot_id,
		}
	}
	project_request := request
	project_request.hidden_ranges = ranges
	return project(buffer, project_request)
}

/* project_cached projects through one bounded checkpoint cache bound to the request view. */
project_cached :: proc(
	buffer: ^editor.Buffer,
	request: Projection_Request,
	cache: ^Projection_Cache,
) -> (snapshot: Snapshot, ok: bool, failure: Failure_Context) {
	cache_state := projection_cache_state(cache)
	if cache_state == nil {
		return {}, false, Failure_Context{code = .Invalid_Cache, snapshot_id = request.snapshot_id}
	}
	if !projection_cache_accepts(cache_state, request) {
		return {}, false, Failure_Context {
			code = .Wrong_View,
			buffer_id = request.view.buffer_id,
			buffer_revision = request.view.revision,
			snapshot_id = request.snapshot_id,
		}
	}
	return project_internal(buffer, request, cache_state)
}

@(private)
project_internal :: proc(
	buffer: ^editor.Buffer,
	request: Projection_Request,
	cache: ^Projection_Cache_State,
) -> (snapshot: Snapshot, ok: bool, failure: Failure_Context) {
	request_ok, request_failure := projection_request_is_valid(request)
	if !request_ok {
		return {}, false, request_failure
	}
	stats, stats_ok, stats_failure := editor.buffer_stats(buffer)
	if !stats_ok {
		return {}, false, editor_failure(stats_failure)
	}
	if stats.buffer_id != request.view.buffer_id {
		return {}, false, Failure_Context {
			code = .Incompatible_Snapshot,
			buffer_id = stats.buffer_id,
			buffer_revision = stats.revision,
			snapshot_id = request.snapshot_id,
		}
	}
	if stats.revision != request.view.revision {
		return {}, false, Failure_Context {
			code = .Stale_Snapshot,
			buffer_id = stats.buffer_id,
			buffer_revision = stats.revision,
			snapshot_id = request.snapshot_id,
			actual = u64(request.view.revision),
		}
	}

	workspace, workspace_ok, workspace_failure := workspace_init(request)
	if !workspace_ok {
		return {}, false, workspace_failure
	}
	defer workspace_destroy(&workspace)
	region_ok, region_failure := region_init(&workspace, buffer, request)
	if !region_ok do return {}, false, region_failure
	search_ok, search_failure := search_matches_init(workspace.search_matches, request.search, buffer)
	if !search_ok do return {}, false, search_failure

	origin_line, origin_ok, origin_failure := editor.buffer_line_at_position(
		buffer,
		request.view.viewport_origin_position,
	)
	if !origin_ok {
		return {}, false, editor_failure(origin_failure)
	}
	current_line := origin_line
	has_logical_line := true
	for row_index in 0 ..< request.constraints.height_rows {
		for has_logical_line {
			hidden_end, hidden := projection_hidden_line_end(current_line, request.hidden_ranges)
			if !hidden do break
			if u64(hidden_end) >= stats.text_bytes {
				has_logical_line = false
				break
			}
			next_position, position_ok, position_failure := editor.buffer_position(buffer, hidden_end)
			if !position_ok do return {}, false, editor_failure(position_failure)
			next_line, line_ok, line_failure := editor.buffer_line_at_position(buffer, next_position)
			if !line_ok do return {}, false, editor_failure(line_failure)
			if next_line.start == current_line.start {
				return {}, false, Failure_Context {
					code = .Invalid_Request,
					buffer_id = request.view.buffer_id,
					buffer_revision = request.view.revision,
					snapshot_id = request.snapshot_id,
				}
			}
			current_line = next_line
		}
		if !has_logical_line {
			workspace.rows[row_index] = Display_Row {
				viewport_row = Display_Row_Index(row_index),
			}
			workspace.row_count += 1
			continue
		}
		laid_out, row_failure := workspace_layout_row(
			&workspace,
			buffer,
			request,
			current_line,
			row_index,
			cache,
		)
		if !laid_out {
			return {}, false, row_failure
		}
		if u64(current_line.next_start) > stats.text_bytes {
			panic("editor line range exceeds buffer statistics")
		}
		if u64(current_line.next_start) == stats.text_bytes &&
		   current_line.content_end == current_line.next_start {
			has_logical_line = false
			continue
		}
		next_position, position_ok, position_failure := editor.buffer_position(
			buffer,
			current_line.next_start,
		)
		if !position_ok {
			return {}, false, editor_failure(position_failure)
		}
		next_line, line_ok, line_failure := editor.buffer_line_at_position(
			buffer,
			next_position,
		)
		if !line_ok {
			return {}, false, editor_failure(line_failure)
		}
		current_line = next_line
	}
	search_matches_finalize(&workspace)

	confirmed, confirmed_ok, confirmed_failure := editor.buffer_stats(buffer)
	if !confirmed_ok {
		return {}, false, editor_failure(confirmed_failure)
	}
	if confirmed.buffer_id != stats.buffer_id || confirmed.revision != stats.revision {
		return {}, false, Failure_Context {
			code = .Stale_Snapshot,
			buffer_id = confirmed.buffer_id,
			buffer_revision = confirmed.revision,
			snapshot_id = request.snapshot_id,
		}
	}

	result_snapshot, snapshot_ok, snapshot_failure := snapshot_from_workspace(workspace, request)
	if !snapshot_ok {
		return {}, false, snapshot_failure
	}
	if cache != nil {
		committed, cache_failure := projection_cache_commit(
			cache,
			request,
			Logical_Line_Index(origin_line.line_index),
			workspace.checkpoints[:workspace.checkpoint_count],
		)
		if !committed {
			snapshot_close(&result_snapshot)
			return {}, false, cache_failure
		}
	}
	return result_snapshot, true, {}
}

/* snapshot_view borrows immutable display data until snapshot_close consumes its owner. */
snapshot_view :: proc(
	snapshot: Snapshot,
) -> (value: Snapshot_View, ok: bool, failure: Failure_Context) {
	if snapshot.state == nil {
		return {}, false, Failure_Context{code = .Closed_Snapshot}
	}
	state := (^Snapshot_State)(snapshot.state)
	return Snapshot_View {
		key = state.key,
		text = string(state.text),
		rows = state.rows,
		runs = state.runs,
		boundaries = state.boundaries,
		checkpoints = state.checkpoints,
		cursor = state.cursor,
		region = state.region,
		search_matches = state.search_matches,
		accounting = state.accounting,
	}, true, {}
}

/* snapshot_close releases every array owned by one non-copied display snapshot. */
snapshot_close :: proc(snapshot: ^Snapshot) -> (ok: bool, failure: Failure_Context) {
	assert(snapshot != nil)
	if snapshot.state == nil {
		return false, Failure_Context{code = .Closed_Snapshot}
	}
	state := (^Snapshot_State)(snapshot.state)
	snapshot_id := state.key.snapshot_id
	allocator := state.allocator
	delete(state.checkpoints, allocator)
	delete(state.search_matches, allocator)
	delete(state.boundaries, allocator)
	delete(state.runs, allocator)
	delete(state.rows, allocator)
	delete(state.text, allocator)
	free(state, allocator)
	snapshot.state = nil
	return true, Failure_Context{snapshot_id = snapshot_id}
}

@(private)
projection_request_is_valid :: proc(
	request: Projection_Request,
) -> (ok: bool, failure: Failure_Context) {
	constraints_ok, constraints_failure := constraints_are_valid(request.constraints, request.limits)
	if !constraints_ok {
		constraints_failure.snapshot_id = request.snapshot_id
		return false, constraints_failure
	}
	profile_id := Display_Profile_ID(u64(request.view.display_profile_id))
	if request.snapshot_id == Snapshot_ID(0) || request.view.view_id == 0 ||
	   request.view.view_generation == 0 || request.view.state_generation == 0 ||
	   request.view.buffer_id == editor.Buffer_ID(0) ||
	   request.view.point_position.buffer_id != request.view.buffer_id ||
	   request.view.point_position.revision != request.view.revision ||
	   request.view.viewport_origin_position.buffer_id != request.view.buffer_id ||
	   request.view.viewport_origin_position.revision != request.view.revision ||
	   request.view.tab_width == 0 || request.view.tab_width > MAX_TAB_WIDTH ||
	   request.allocators.persistent.procedure == nil ||
	   request.allocators.temporary.procedure == nil {
		return false, Failure_Context {
			code = .Invalid_Request,
			buffer_id = request.view.buffer_id,
			buffer_revision = request.view.revision,
			snapshot_id = request.snapshot_id,
		}
	}
	if len(request.hidden_ranges) != int(request.view.hidden_range_count) ||
	   len(request.hidden_ranges) > int(view.MAX_HIDDEN_RANGES) {
		return false, Failure_Context {
			code = .Invalid_Request,
			buffer_id = request.view.buffer_id,
			buffer_revision = request.view.revision,
			snapshot_id = request.snapshot_id,
		}
	}
	for source_range, index in request.hidden_ranges {
		if source_range.start.buffer_id != request.view.buffer_id ||
		   source_range.end.buffer_id != request.view.buffer_id ||
		   source_range.start.revision != request.view.revision ||
		   source_range.end.revision != request.view.revision ||
		   source_range.start.byte_offset >= source_range.end.byte_offset ||
		   index > 0 && request.hidden_ranges[index - 1].end.byte_offset > source_range.start.byte_offset {
			return false, Failure_Context {
				code = .Invalid_Request,
				buffer_id = request.view.buffer_id,
				buffer_revision = request.view.revision,
				snapshot_id = request.snapshot_id,
			}
		}
	}
	if !display_profile_is_valid(request.profile) || profile_id != request.profile.id {
		return false, Failure_Context {
			code = .Invalid_Profile,
			buffer_id = request.view.buffer_id,
			buffer_revision = request.view.revision,
			snapshot_id = request.snapshot_id,
			display_profile_id = request.profile.id,
		}
	}
	if request.view.mark.present &&
	   (request.view.mark.position.buffer_id != request.view.buffer_id ||
	    request.view.mark.position.revision != request.view.revision) {
		return false, Failure_Context {
			code = .Invalid_Request,
			buffer_id = request.view.buffer_id,
			buffer_revision = request.view.revision,
			snapshot_id = request.snapshot_id,
		}
	}
	if request.search.present {
		if request.search.source_revision != request.view.revision ||
		   request.search.scope.buffer_id != request.view.buffer_id ||
		   request.search.scope.revision != request.view.revision ||
		   len(request.search.occurrences) > int(request.limits.search_matches) {
			return false, Failure_Context {
				code = .Search_Match_Limit,
				buffer_id = request.view.buffer_id,
				buffer_revision = request.view.revision,
				snapshot_id = request.snapshot_id,
				limit = u64(request.limits.search_matches),
				actual = u64(len(request.search.occurrences)),
			}
		}
		for occurrence in request.search.occurrences {
			if occurrence.buffer_id != request.view.buffer_id ||
			   occurrence.revision != request.view.revision ||
			   occurrence.start > occurrence.end {
				return false, Failure_Context {
					code = .Invalid_Request,
					buffer_id = request.view.buffer_id,
					buffer_revision = request.view.revision,
					snapshot_id = request.snapshot_id,
				}
			}
		}
	}
	return true, {}
}

@(private)
projection_hidden_line_end :: proc(
	line: editor.Buffer_Line,
	ranges: []view.Hidden_Range,
) -> (editor.Byte_Offset, bool) {
	for source_range in ranges {
		if source_range.start.byte_offset > line.start do break
		if source_range.start.byte_offset <= line.start &&
		   source_range.end.byte_offset >= line.next_start {
			return source_range.end.byte_offset, true
		}
	}
	return 0, false
}

@(private)
workspace_init :: proc(
	request: Projection_Request,
) -> (workspace: Workspace, ok: bool, failure: Failure_Context) {
	workspace.allocator = request.allocators.temporary
	max_cells := u64(request.constraints.width_cells) * u64(request.constraints.height_rows)
	text_capacity := min(request.limits.derived_bytes, request.limits.source_bytes + max_cells * 3)
	boundary_capacity := min(
		u64(request.limits.boundaries),
		max_cells + u64(request.constraints.height_rows) * 2,
	)
	if request.limits.source_bytes > u64(max(int)) || text_capacity > u64(max(int)) ||
	   boundary_capacity > u64(max(int)) {
		return {}, false, Failure_Context {
			code = .Temporary_Memory_Limit,
			snapshot_id = request.snapshot_id,
			limit = u64(max(int)),
			actual = max(request.limits.source_bytes, max(text_capacity, boundary_capacity)),
		}
	}
	source, source_error := make([]u8, int(request.limits.source_bytes), workspace.allocator)
	if source_error != nil {
		return {}, false, temporary_failure(request.snapshot_id, request.limits.source_bytes)
	}
	workspace.source = source
	text, text_error := make([]u8, int(text_capacity), workspace.allocator)
	if text_error != nil {
		workspace_destroy(&workspace)
		return {}, false, temporary_failure(request.snapshot_id, text_capacity)
	}
	workspace.text = text
	rows, rows_error := make([]Display_Row, int(request.constraints.height_rows), workspace.allocator)
	if rows_error != nil {
		workspace_destroy(&workspace)
		return {}, false, temporary_failure(
			request.snapshot_id,
			u64(request.constraints.height_rows) * u64(size_of(Display_Row)),
		)
	}
	workspace.rows = rows
	runs, runs_error := make([]Text_Run, int(request.constraints.height_rows), workspace.allocator)
	if runs_error != nil {
		workspace_destroy(&workspace)
		return {}, false, temporary_failure(
			request.snapshot_id,
			u64(request.constraints.height_rows) * u64(size_of(Text_Run)),
		)
	}
	workspace.runs = runs
	boundaries, boundaries_error := make([]Boundary_Map, int(boundary_capacity), workspace.allocator)
	if boundaries_error != nil {
		workspace_destroy(&workspace)
		return {}, false, temporary_failure(
			request.snapshot_id,
			boundary_capacity * u64(size_of(Boundary_Map)),
		)
	}
	workspace.boundaries = boundaries
	checkpoints, checkpoints_error := make(
		[]Line_Checkpoint,
		int(request.limits.checkpoints),
		workspace.allocator,
	)
	if checkpoints_error != nil {
		workspace_destroy(&workspace)
		return {}, false, temporary_failure(
			request.snapshot_id,
			u64(request.limits.checkpoints) * u64(size_of(Line_Checkpoint)),
		)
	}
	workspace.checkpoints = checkpoints
	search_matches, search_matches_error := make(
		[]Search_Match_Map,
		len(request.search.occurrences),
		workspace.allocator,
	)
	if search_matches_error != nil {
		workspace_destroy(&workspace)
		return {}, false, temporary_failure(
			request.snapshot_id,
			u64(len(request.search.occurrences)) * u64(size_of(Search_Match_Map)),
		)
	}
	workspace.search_matches = search_matches
	return workspace, true, {}
}

@(private)
workspace_destroy :: proc(workspace: ^Workspace) {
	if workspace == nil || workspace.allocator.procedure == nil {
		return
	}
	delete(workspace.boundaries, workspace.allocator)
	delete(workspace.rectangle_ranges, workspace.allocator)
	delete(workspace.search_matches, workspace.allocator)
	delete(workspace.checkpoints, workspace.allocator)
	delete(workspace.runs, workspace.allocator)
	delete(workspace.rows, workspace.allocator)
	delete(workspace.text, workspace.allocator)
	delete(workspace.source, workspace.allocator)
	workspace^ = {}
}

@(private)
workspace_layout_row :: proc(
	workspace: ^Workspace,
	buffer: ^editor.Buffer,
	request: Projection_Request,
	line: editor.Buffer_Line,
	row_index: u32,
	cache: ^Projection_Cache_State,
) -> (ok: bool, failure: Failure_Context) {
	scan_start := line.start
	grapheme_index: u64
	left := u64(request.view.horizontal_display_column)
	right := left + u64(request.constraints.width_cells)
	column: u64
	if cached, cached_ok := projection_cache_checkpoint(cache, request, line, u32(left)); cached_ok {
		scan_start = cached.source_byte_offset
		grapheme_index = cached.grapheme_index
		column = u64(cached.display_column)
	}
	line_bytes := u64(line.content_end) - u64(scan_start)
	parsed_bytes: u64
	copied_bytes: u64
	row_text_start := workspace.text_count
	first_boundary := workspace.boundary_count
	first_run := workspace.run_count
	run_start_column: u64
	run_cells: u64
	run_started := false
	clipped_right := false
	used_replacement := false
	workspace_record_checkpoint(
		workspace,
		line,
		scan_start,
		grapheme_index,
		column,
	)

	for {
		if parsed_bytes >= copied_bytes {
			if parsed_bytes >= line_bytes {
				break
			}
			extended, extend_failure := workspace_extend_line(
				workspace,
				buffer,
				request,
				line,
				scan_start,
				line_bytes,
				&copied_bytes,
			)
			if !extended {
				return false, extend_failure
			}
		}
		grapheme, grapheme_ok, _ := profile_next_grapheme(
			request.profile.unicode,
			string(workspace.source[:copied_bytes]),
			parsed_bytes,
		)
		if !grapheme_ok {
			if copied_bytes < line_bytes && workspace.source_bytes_examined < request.limits.source_bytes {
				extended, extend_failure := workspace_extend_line(
					workspace,
					buffer,
					request,
					line,
					scan_start,
					line_bytes,
					&copied_bytes,
				)
				if !extended {
					return false, extend_failure
				}
				continue
			}
			code := Failure_Code.Malformed_UTF8
			if copied_bytes < line_bytes {
				code = .Source_Byte_Limit
			}
			return false, Failure_Context {
				code = code,
				buffer_id = line.buffer_id,
				buffer_revision = line.revision,
				snapshot_id = request.snapshot_id,
				limit = request.limits.source_bytes,
				actual = workspace.source_bytes_examined + 1,
			}
		}
		if grapheme.end == copied_bytes && copied_bytes < line_bytes {
			if workspace.source_bytes_examined >= request.limits.source_bytes {
				return false, source_limit_failure(request, line, workspace.source_bytes_examined + 1)
			}
			extended, extend_failure := workspace_extend_line(
				workspace,
				buffer,
				request,
				line,
				scan_start,
				line_bytes,
				&copied_bytes,
			)
			if !extended {
				return false, extend_failure
			}
			continue
		}

		cluster := string(workspace.source[grapheme.start:grapheme.end])
		width, width_ok, width_failure := profile_cluster_width(
			request.profile.unicode,
			cluster,
			u32(min(column, u64(max(u32)))),
			request.view.tab_width,
		)
		if !width_ok {
			code := Failure_Code.Malformed_UTF8
			if width_failure.code == .Invalid_Tab_Width {
				code = .Invalid_Request
			}
			return false, Failure_Context {
				code = code,
				buffer_id = line.buffer_id,
				buffer_revision = line.revision,
				snapshot_id = request.snapshot_id,
				actual = width_failure.actual,
			}
		}
		crlf_terminator := width.is_line_break && cluster == "\r" &&
		                   grapheme.end == line_bytes && line.next_start > line.content_end
		if width.is_line_break && !crlf_terminator {
			width = Cluster_Width{cells = 1, used_replacement = true}
		}
		grapheme_start_column := column
		grapheme_end_column := column + u64(width.cells)
		absolute_source := editor.Byte_Offset(u64(scan_start) + grapheme.start)
		workspace_record_boundary(
			workspace,
			request,
			absolute_source,
			row_text_start,
			row_index,
			grapheme_start_column,
		)

		fully_visible := grapheme_start_column >= left && grapheme_end_column <= right
		if fully_visible && !crlf_terminator {
			if !run_started {
				run_started = true
				run_start_column = grapheme_start_column
			}
			written, write_ok := workspace_write_cluster(workspace, request, cluster, width)
			if !write_ok {
				return false, Failure_Context {
					code = .Derived_Storage_Limit,
					buffer_id = line.buffer_id,
					buffer_revision = line.revision,
					snapshot_id = request.snapshot_id,
					limit = request.limits.derived_bytes,
					actual = u64(workspace.text_count) + u64(len(cluster)),
				}
			}
			_ = written
			run_cells += u64(width.cells)
			used_replacement = used_replacement || width.used_replacement
		}
		column = grapheme_end_column
		parsed_bytes = grapheme.end
		grapheme_index += 1
		workspace_record_checkpoint(
			workspace,
			line,
			editor.Byte_Offset(u64(scan_start) + parsed_bytes),
			grapheme_index,
			column,
		)
		if column >= right {
			clipped_right = parsed_bytes < line_bytes
			break
		}
	}

	workspace_record_boundary(
		workspace,
		request,
		editor.Byte_Offset(u64(scan_start) + parsed_bytes),
		row_text_start,
		row_index,
		column,
	)
	if run_started {
		if workspace.run_count >= u32(len(workspace.runs)) {
			return false, Failure_Context {
				code = .Run_Limit,
				snapshot_id = request.snapshot_id,
				limit = u64(request.limits.runs),
				actual = u64(workspace.run_count) + 1,
			}
		}
		workspace.runs[workspace.run_count] = Text_Run {
			text_offset = row_text_start,
			text_bytes = workspace.text_count - row_text_start,
			start_column = Display_Column(run_start_column),
			cell_count = u32(run_cells),
		}
		workspace.run_count += 1
	}
	visible_cells: u64
	if column > left {
		visible_cells = min(column, right) - left
	}
	workspace.rows[row_index] = Display_Row {
		viewport_row = Display_Row_Index(row_index),
		logical_line = Logical_Line_Index(line.line_index),
		source_start = line.start,
		source_end = line.content_end,
		first_run = first_run,
		run_count = workspace.run_count - first_run,
		first_boundary = first_boundary,
		boundary_count = workspace.boundary_count - first_boundary,
		visible_start = Display_Column(left),
		visible_cells = u32(visible_cells),
		clipped_left = left > 0 && line_bytes > 0,
		clipped_right = clipped_right,
		used_replacement = used_replacement,
		has_content = true,
	}
	workspace_rectangle_region_apply(workspace, &workspace.rows[row_index], line)
	workspace.row_count += 1
	return true, {}
}

@(private)
workspace_extend_line :: proc(
	workspace: ^Workspace,
	buffer: ^editor.Buffer,
	request: Projection_Request,
	line: editor.Buffer_Line,
	scan_start: editor.Byte_Offset,
	line_bytes: u64,
	copied_bytes: ^u64,
) -> (ok: bool, failure: Failure_Context) {
	remaining_budget := request.limits.source_bytes - workspace.source_bytes_examined
	remaining_line := line_bytes - copied_bytes^
	chunk_bytes := min(ROW_SCAN_CHUNK_BYTES, min(remaining_budget, remaining_line))
	if chunk_bytes == 0 {
		return false, source_limit_failure(request, line, workspace.source_bytes_examined + 1)
	}
	start := editor.Byte_Offset(u64(scan_start) + copied_bytes^)
	end := editor.Byte_Offset(u64(start) + chunk_bytes)
	_, inspected, inspect_failure := editor.buffer_inspect(
		buffer,
		start,
		end,
		workspace.source[int(copied_bytes^):int(copied_bytes^ + chunk_bytes)],
	)
	if !inspected {
		return false, editor_failure(inspect_failure)
	}
	copied_bytes^ += chunk_bytes
	workspace.source_bytes_examined += chunk_bytes
	return true, {}
}

@(private)
workspace_write_cluster :: proc(
	workspace: ^Workspace,
	request: Projection_Request,
	cluster: string,
	width: Cluster_Width,
) -> (written: u32, ok: bool) {
	if width.is_tab {
		if u64(workspace.text_count) + u64(width.cells) > u64(len(workspace.text)) {
			return 0, false
		}
		for cell_index in 0 ..< u32(width.cells) {
			workspace.text[workspace.text_count + cell_index] = ' '
		}
		workspace.text_count += u32(width.cells)
		return u32(width.cells), true
	}
	if width.used_replacement {
		encoded, encoded_bytes := utf8.encode_rune(request.profile.replacement_rune)
		if u64(workspace.text_count) + u64(encoded_bytes) > u64(len(workspace.text)) {
			return 0, false
		}
		copy(workspace.text[workspace.text_count:], encoded[:encoded_bytes])
		workspace.text_count += u32(encoded_bytes)
		return u32(encoded_bytes), true
	}
	if u64(workspace.text_count) + u64(len(cluster)) > u64(len(workspace.text)) {
		return 0, false
	}
	copy(workspace.text[workspace.text_count:], cluster)
	workspace.text_count += u32(len(cluster))
	return u32(len(cluster)), true
}

@(private)
workspace_record_boundary :: proc(
	workspace: ^Workspace,
	request: Projection_Request,
	source_offset: editor.Byte_Offset,
	row_text_start: u32,
	row_index: u32,
	column: u64,
) {
	left := u64(request.view.horizontal_display_column)
	right := left + u64(request.constraints.width_cells)
	if column >= left && column <= right {
		assert(workspace.boundary_count < u32(len(workspace.boundaries)))
		if workspace.boundary_count == 0 ||
		   workspace.boundaries[workspace.boundary_count - 1].source_byte_offset != source_offset {
			workspace.boundaries[workspace.boundary_count] = Boundary_Map {
				source_byte_offset = source_offset,
				row_text_offset = workspace.text_count - row_text_start,
				display_column = Display_Column(column),
			}
			workspace.boundary_count += 1
		}
	}
	if source_offset == request.view.point_position.byte_offset &&
	   column >= left && column <= right {
		workspace.cursor = Cursor_Target {
			visible = true,
			viewport_row = Display_Row_Index(row_index),
			column = Display_Column(column - left),
		}
	}
	region_record_boundary(&workspace.region, source_offset, row_index, column, left, right)
	search_matches_record_boundary(
		workspace.search_matches,
		source_offset,
		row_index,
		column,
		left,
		right,
	)
}

@(private)
search_matches_init :: proc(
	matches: []Search_Match_Map,
	snapshot: view.Search_Snapshot,
	buffer: ^editor.Buffer,
) -> (bool, Failure_Context) {
	for &match, index in matches {
		occurrence := snapshot.occurrences[index]
		match.start = occurrence.start
		match.end = occurrence.end
		if snapshot.presentation == .Lines {
			start_position, start_ok, start_failure := editor.buffer_position(buffer, occurrence.start)
			if !start_ok do return false, editor_failure(start_failure)
			start_line, start_line_ok, start_line_failure := editor.buffer_line_at_position(buffer, start_position)
			if !start_line_ok do return false, editor_failure(start_line_failure)
			end_offset := occurrence.end
			if end_offset > occurrence.start do end_offset -= 1
			end_position, end_ok, end_failure := editor.buffer_position(buffer, end_offset)
			if !end_ok do return false, editor_failure(end_failure)
			end_line, end_line_ok, end_line_failure := editor.buffer_line_at_position(buffer, end_position)
			if !end_line_ok do return false, editor_failure(end_line_failure)
			match.start = start_line.start
			match.end = end_line.next_start
			if match.end == match.start do match.end = end_line.content_end
		}
		match.current = snapshot.has_current && u32(index) == snapshot.current_index
	}
	return true, {}
}

@(private)
search_matches_record_boundary :: proc(
	matches: []Search_Match_Map,
	source_offset: editor.Byte_Offset,
	row_index: u32,
	column, left, right: u64,
) {
	if column < left || column > right {
		return
	}
	for &match in matches {
		if source_offset >= match.start && source_offset <= match.end {
			match.intersects_visible = true
		}
		if source_offset == match.start {
			match.start_visible = true
			match.start_row = Display_Row_Index(row_index)
			match.start_column = Display_Column(column - left)
		}
		if source_offset == match.end {
			match.end_visible = true
			match.end_row = Display_Row_Index(row_index)
			match.end_column = Display_Column(column - left)
		}
	}
}

@(private)
search_matches_finalize :: proc(workspace: ^Workspace) {
	for &match in workspace.search_matches {
		match.clipped_start = match.intersects_visible && !match.start_visible
		match.clipped_end = match.intersects_visible && !match.end_visible
	}
}

@(private)
region_init :: proc(
	workspace: ^Workspace,
	buffer: ^editor.Buffer,
	request: Projection_Request,
) -> (ok: bool, failure: Failure_Context) {
	region := &workspace.region
	snapshot := request.view
	if !snapshot.region_active {
		return true, {}
	}
	assert(snapshot.mark.present)
	anchor := snapshot.mark.position.byte_offset
	point := snapshot.effective_point_position.byte_offset
	region.active = true
	region.start = min(anchor, point)
	region.end = max(anchor, point)
	if snapshot.selection_shape == .Rectangle {
		descriptor, ranges, resolved, rectangle_failure := rectangular_selection_ranges(
			buffer, snapshot, request.profile, workspace.allocator,
		)
		if !resolved do return false, rectangle_failure
		region.rectangular = true
		workspace.rectangle_ranges = ranges
		workspace.rectangle_top_line = descriptor.top_line
	}
	return true, {}
}

@(private)
workspace_rectangle_region_apply :: proc(
	workspace: ^Workspace,
	row: ^Display_Row,
	line: editor.Buffer_Line,
) {
	if !workspace.region.rectangular || line.line_index < workspace.rectangle_top_line do return
	index := line.line_index - workspace.rectangle_top_line
	if index >= u64(len(workspace.rectangle_ranges)) do return
	selected := workspace.rectangle_ranges[index]
	if selected.start.byte_offset >= selected.end.byte_offset do return
	row.region_active = true
	row.region_start = selected.start.byte_offset
	row.region_end = selected.end.byte_offset
}

@(private)
region_record_boundary :: proc(
	region: ^Region_Map,
	source_offset: editor.Byte_Offset,
	row_index: u32,
	column, left, right: u64,
) {
	if !region.active || column < left || column > right {
		return
	}
	if source_offset == region.start {
		region.start_visible = true
		region.start_viewport_row = Display_Row_Index(row_index)
		region.start_column = Display_Column(column - left)
	}
	if source_offset == region.end {
		region.end_visible = true
		region.end_viewport_row = Display_Row_Index(row_index)
		region.end_column = Display_Column(column - left)
	}
}

@(private)
workspace_record_checkpoint :: proc(
	workspace: ^Workspace,
	line: editor.Buffer_Line,
	source_offset: editor.Byte_Offset,
	grapheme_index: u64,
	column: u64,
) {
	logical_line := Logical_Line_Index(line.line_index)
	if workspace.checkpoint_count > 0 {
		previous := workspace.checkpoints[workspace.checkpoint_count - 1]
		if previous.logical_line == logical_line {
			distance := u64(source_offset) - u64(previous.source_byte_offset)
			if distance < LINE_CHECKPOINT_INTERVAL_BYTES {
				return
			}
		}
	}
	checkpoint := Line_Checkpoint {
		logical_line = logical_line,
		source_byte_offset = source_offset,
		grapheme_index = grapheme_index,
		display_column = Display_Column(column),
	}
	capacity := u32(len(workspace.checkpoints))
	if workspace.checkpoint_count == capacity {
		for index := 1; index < int(capacity); index += 1 {
			workspace.checkpoints[index - 1] = workspace.checkpoints[index]
		}
		workspace.checkpoints[capacity - 1] = checkpoint
		return
	}
	workspace.checkpoints[workspace.checkpoint_count] = checkpoint
	workspace.checkpoint_count += 1
}

@(private)
snapshot_from_workspace :: proc(
	workspace: Workspace,
	request: Projection_Request,
) -> (snapshot: Snapshot, ok: bool, failure: Failure_Context) {
	estimate, estimate_ok, estimate_failure := representation_estimate(
		request.constraints,
		workspace.source_bytes_examined,
		u64(workspace.text_count),
		workspace.run_count,
		workspace.boundary_count,
		workspace.checkpoint_count,
		request.limits,
	)
	if !estimate_ok {
		estimate_failure.snapshot_id = request.snapshot_id
		return {}, false, estimate_failure
	}
	owner_bytes := u64(size_of(Snapshot_State))
	search_match_bytes := u64(len(workspace.search_matches)) * u64(size_of(Search_Match_Map))
	retained_bytes := estimate.accounting.retained_bytes + owner_bytes + search_match_bytes
	if retained_bytes > request.limits.derived_bytes {
		return {}, false, Failure_Context {
			code = .Derived_Storage_Limit,
			snapshot_id = request.snapshot_id,
			limit = request.limits.derived_bytes,
			actual = retained_bytes,
		}
	}
	state, state_error := new(Snapshot_State, request.allocators.persistent)
	if state_error != nil {
		return {}, false, persistent_failure(request.snapshot_id, owner_bytes)
	}
	state.allocator = request.allocators.persistent
	state.key = snapshot_key(request)
	state.cursor = workspace.cursor
	state.region = workspace.region
	state.accounting = estimate.accounting
	state.accounting.search_match_bytes = search_match_bytes
	state.accounting.owner_bytes = owner_bytes
	state.accounting.retained_bytes = retained_bytes
	state.accounting.temporary_peak_bytes = workspace_temporary_bytes(workspace)

	allocated := snapshot_allocate_arrays(state, workspace)
	if !allocated {
		snapshot_state_destroy(state)
		return {}, false, persistent_failure(request.snapshot_id, retained_bytes)
	}
	copy(state.text, workspace.text[:workspace.text_count])
	copy(state.rows, workspace.rows[:workspace.row_count])
	copy(state.runs, workspace.runs[:workspace.run_count])
	copy(state.boundaries, workspace.boundaries[:workspace.boundary_count])
	copy(state.checkpoints, workspace.checkpoints[:workspace.checkpoint_count])
	copy(state.search_matches, workspace.search_matches)
	return Snapshot{state = state}, true, {}
}

@(private)
snapshot_allocate_arrays :: proc(
	state: ^Snapshot_State,
	workspace: Workspace,
) -> bool {
	text, text_error := make([]u8, int(workspace.text_count), state.allocator)
	if text_error != nil do return false
	state.text = text
	rows, rows_error := make([]Display_Row, int(workspace.row_count), state.allocator)
	if rows_error != nil do return false
	state.rows = rows
	runs, runs_error := make([]Text_Run, int(workspace.run_count), state.allocator)
	if runs_error != nil do return false
	state.runs = runs
	boundaries, boundaries_error := make([]Boundary_Map, int(workspace.boundary_count), state.allocator)
	if boundaries_error != nil do return false
	state.boundaries = boundaries
	checkpoints, checkpoints_error := make(
		[]Line_Checkpoint,
		int(workspace.checkpoint_count),
		state.allocator,
	)
	if checkpoints_error != nil do return false
	state.checkpoints = checkpoints
	search_matches, search_matches_error := make(
		[]Search_Match_Map,
		len(workspace.search_matches),
		state.allocator,
	)
	if search_matches_error != nil do return false
	state.search_matches = search_matches
	return true
}

@(private)
snapshot_state_destroy :: proc(state: ^Snapshot_State) {
	if state == nil {
		return
	}
	allocator := state.allocator
	delete(state.checkpoints, allocator)
	delete(state.search_matches, allocator)
	delete(state.boundaries, allocator)
	delete(state.runs, allocator)
	delete(state.rows, allocator)
	delete(state.text, allocator)
	free(state, allocator)
}

@(private)
snapshot_key :: proc(request: Projection_Request) -> Snapshot_Key {
	return Snapshot_Key {
		snapshot_id = request.snapshot_id,
		buffer_id = request.view.buffer_id,
		buffer_revision = request.view.revision,
		view_id = u64(request.view.view_id),
		view_generation = request.view.view_generation,
		view_state_generation = request.view.state_generation,
		display_profile_id = request.profile.id,
		unicode_version = request.profile.unicode.version,
		constraints = request.constraints,
		tab_width = request.view.tab_width,
	}
}

@(private)
workspace_temporary_bytes :: proc(workspace: Workspace) -> u64 {
	return u64(len(workspace.source)) + u64(len(workspace.text)) +
	       u64(len(workspace.rows)) * u64(size_of(Display_Row)) +
	       u64(len(workspace.runs)) * u64(size_of(Text_Run)) +
	       u64(len(workspace.boundaries)) * u64(size_of(Boundary_Map)) +
	       u64(len(workspace.checkpoints)) * u64(size_of(Line_Checkpoint)) +
	       u64(len(workspace.search_matches)) * u64(size_of(Search_Match_Map))
}

@(private)
source_limit_failure :: proc(
	request: Projection_Request,
	line: editor.Buffer_Line,
	actual: u64,
) -> Failure_Context {
	return Failure_Context {
		code = .Source_Byte_Limit,
		buffer_id = line.buffer_id,
		buffer_revision = line.revision,
		snapshot_id = request.snapshot_id,
		limit = request.limits.source_bytes,
		actual = actual,
	}
}

@(private)
editor_failure :: proc(source: editor.Failure_Context) -> Failure_Context {
	return Failure_Context {
		code = .Editor_Failure,
		buffer_id = source.buffer_id,
		buffer_revision = source.revision,
		editor_failure = source,
	}
}

@(private)
temporary_failure :: proc(snapshot_id: Snapshot_ID, actual: u64) -> Failure_Context {
	return Failure_Context {
		code = .Temporary_Memory_Limit,
		snapshot_id = snapshot_id,
		actual = actual,
	}
}

@(private)
persistent_failure :: proc(snapshot_id: Snapshot_ID, actual: u64) -> Failure_Context {
	return Failure_Context {
		code = .Persistent_Memory_Limit,
		snapshot_id = snapshot_id,
		actual = actual,
	}
}
