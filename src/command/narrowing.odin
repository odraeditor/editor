// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../editor"
import "../language"
import editor_view "../view"

/* native_narrow_to_region installs a view-local projection over the active region. */
native_narrow_to_region :: proc(
	request: Native_Context,
	logical: editor_view.Snapshot,
) -> (Native_Result, bool, Failure_Context) {
	if !logical.region_active || !logical.mark.present ||
	   logical.mark.position.byte_offset == logical.point_position.byte_offset {
		return {}, false, Failure_Context{code = .Region_Unavailable, command = request.command}
	}
	start := logical.mark.position
	end := logical.point_position
	if start.byte_offset > end.byte_offset do start, end = end, start
	return native_narrow_to_range(request, start, end)
}

/* native_narrow_to_definition resolves one structural definition without changing selection. */
native_narrow_to_definition :: proc(
	request: Native_Context,
	logical: editor_view.Snapshot,
) -> (Native_Result, bool, Failure_Context) {
	if request.language_owner == nil || request.language_source == nil ||
	   !language.structural_scope_is_valid(request.structural_scope) {
		return Native_Result{completion = .No_Op}, true, {}
	}
	query := structural_language_request(request.structural_scope, logical, .Definition)
	target, _, queried, query_failure := language.tree_sitter_owner_query_structure(
		request.language_owner,
		request.language_source,
		query,
	)
	if !queried {
		if query_failure.code == .No_Structural_Target {
			return Native_Result{completion = .No_Op}, true, {}
		}
		failure := structural_editor_language_failure(query_failure)
		failure.command = request.command
		return {}, false, failure
	}
	start, start_ok, start_failure := editor.buffer_position(request.buffer, target.start)
	if !start_ok do return {}, false, native_editor_failure(request.command, start_failure)
	end, end_ok, end_failure := editor.buffer_position(request.buffer, target.end)
	if !end_ok do return {}, false, native_editor_failure(request.command, end_failure)
	return native_narrow_to_range(request, start, end)
}

/* native_widen clears only the active view's hidden-range projection. */
native_widen :: proc(request: Native_Context) -> (Native_Result, bool, Failure_Context) {
	update, widened, widen_failure := editor_view.visibility_clear(
		request.view_registry,
		request.view,
	)
	if !widened do return {}, false, native_view_failure(request.command, widen_failure)
	completion := Native_Completion.No_Op
	if update.changed do completion = .View_Changed
	return Native_Result{completion = completion}, true, {}
}

@(private)
native_narrow_to_range :: proc(
	request: Native_Context,
	start, end: editor.Position,
) -> (Native_Result, bool, Failure_Context) {
	stats, stats_ok, stats_failure := editor.buffer_stats(request.buffer)
	if !stats_ok do return {}, false, native_editor_failure(request.command, stats_failure)
	if start.buffer_id != stats.buffer_id || end.buffer_id != stats.buffer_id ||
	   start.revision != stats.revision || end.revision != stats.revision ||
	   start.byte_offset >= end.byte_offset || u64(end.byte_offset) > stats.text_bytes {
		return {}, false, Failure_Context{code = .Invalid_Request, command = request.command}
	}
	ranges: [2]editor_view.Hidden_Range
	range_count := 0
	if start.byte_offset > 0 {
		buffer_start, start_ok, start_failure := editor.buffer_position(request.buffer, 0)
		if !start_ok do return {}, false, native_editor_failure(request.command, start_failure)
		ranges[range_count] = {start = buffer_start, end = start}
		range_count += 1
	}
	if u64(end.byte_offset) < stats.text_bytes {
		buffer_end, end_ok, end_failure := editor.buffer_position(
			request.buffer,
			editor.Byte_Offset(stats.text_bytes),
		)
		if !end_ok do return {}, false, native_editor_failure(request.command, end_failure)
		ranges[range_count] = {start = end, end = buffer_end}
		range_count += 1
	}
	update, narrowed, narrow_failure := editor_view.visibility_replace(
		request.view_registry,
		request.view,
		ranges[:range_count],
		request.temporary_allocator,
	)
	if !narrowed do return {}, false, native_view_failure(request.command, narrow_failure)
	completion := Native_Completion.No_Op
	if update.changed do completion = .View_Changed
	return Native_Result{completion = completion}, true, {}
}
