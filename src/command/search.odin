// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../display"
import "../editor"
import "../search"
import editor_view "../view"
import "base:runtime"
import "core:unicode/utf8"

/* Incremental_Search_Turn selects a fresh query evaluation or occurrence navigation. */
Incremental_Search_Turn :: enum u8 {
	Invalid,
	Query_Update,
	Repeat,
}

/* Incremental_Search_Request describes one bounded literal or regexp command turn. */
Incremental_Search_Request :: struct {
	buffer:               ^editor.Buffer,
	view_registry:        ^editor_view.Registry,
	view:                 editor_view.View_Handle,
	pattern:              string,
	pattern_kind:         search.Pattern_Kind,
	direction:            search.Direction,
	turn:                 Incremental_Search_Turn,
	query_id:             search.Query_ID,
	search_generation:    search.Search_Generation,
	policy_generation:    search.Policy_Generation,
	cancellation:         ^search.Cancellation,
	policy:               search.Policy,
	limits:               search.Limits,
	profile:              display.Display_Profile,
	constraints:          display.Viewport_Constraints,
	persistent_allocator: runtime.Allocator,
	temporary_allocator:  runtime.Allocator,
}

/*
incremental_search executes and publishes at most one bounded rope scan.
Incomplete work remains explicit in the view and resumes through a later repeat turn.
*/
incremental_search :: proc(
	request: Incremental_Search_Request,
) -> (changed: bool, ok: bool, failure: Failure_Context) {
	if request.buffer == nil || request.view_registry == nil || len(request.pattern) == 0 ||
	   (request.pattern_kind != .Literal && request.pattern_kind != .Regular_Expression) ||
	   (request.direction != .Forward && request.direction != .Backward) ||
	   (request.turn != .Query_Update && request.turn != .Repeat) ||
	   request.query_id == search.Query_ID(0) ||
	   request.search_generation == search.Search_Generation(0) ||
	   request.policy_generation == search.Policy_Generation(0) {
		return false, false, Failure_Context{code = .Invalid_Request}
	}
	if request.cancellation != nil &&
	   request.cancellation.generation != request.search_generation {
		return false, false, Failure_Context{code = .Invalid_Request}
	}
	logical, logical_ok, logical_failure := editor_view.snapshot(
		request.view_registry,
		request.view,
	)
	if !logical_ok {
		return false, false, native_view_failure({}, logical_failure)
	}
	active, active_ok, active_failure := editor_view.search_session_view(
		request.view_registry,
		request.view,
	)
	if !active_ok {
		return false, false, native_view_failure({}, active_failure)
	}
	stats, stats_ok, stats_failure := editor.buffer_stats(request.buffer)
	if !stats_ok {
		return false, false, native_editor_failure({}, stats_failure)
	}
	if logical.buffer_id != stats.buffer_id || logical.revision != stats.revision {
		return false, false, Failure_Context {
			code = .Search_Failure,
			search_code = .Stale_Revision,
			buffer_id = stats.buffer_id,
			revision = stats.revision,
		}
	}
	display_failure := validate_display_request(
		Native_Context {
			buffer = request.buffer,
			view_registry = request.view_registry,
			view = request.view,
			profile = request.profile,
			constraints = request.constraints,
			temporary_allocator = request.temporary_allocator,
		},
		logical,
		2,
		true,
	)
	if display_failure.code != .None {
		return false, false, display_failure
	}
	scope := incremental_search_scope(logical, active, stats)
	origin, wrap_attempted := incremental_search_origin(logical, active, request.direction, request.turn)
	if request.turn == .Query_Update &&
	   ((request.direction == .Forward && origin == scope.start) ||
	    (request.direction == .Backward && origin == scope.end)) {
		wrap_attempted = true
	}

	query: search.Query
	query_ok, query_failure := search.query_init(
		&query,
		search.Query_Config {
			id = request.query_id,
			kind = request.pattern_kind,
			pattern = request.pattern,
			policy = request.policy,
			limits = request.limits,
			allocator = request.persistent_allocator,
			temporary_allocator = request.temporary_allocator,
		},
	)
	if !query_ok {
		return false, false, incremental_search_failure(query_failure)
	}
	defer if query.state != nil do search.query_close(&query)

	snapshot: editor.Buffer_Snapshot
	snapshot_ok, snapshot_failure := editor.buffer_snapshot_open(request.buffer, &snapshot)
	if !snapshot_ok {
		return false, false, native_editor_failure({}, snapshot_failure)
	}
	defer editor.buffer_snapshot_close(&snapshot)
	if request.pattern_kind == .Regular_Expression && request.turn == .Repeat &&
	   active.has_current && int(active.current_index) < len(active.occurrences) {
		current := active.occurrences[active.current_index]
		if current.start == current.end {
			origin = incremental_regexp_repeat_origin(
				&snapshot,
				scope,
				current.start,
				request.direction,
			)
		}
	}
	result: search.Result
	local_cancellation := search.Cancellation{generation = request.search_generation}
	cancellation := request.cancellation
	if cancellation == nil {
		cancellation = &local_cancellation
	}
	search_request := search.Request {
			scope = scope,
			origin = origin,
			direction = request.direction,
			generation = request.search_generation,
			wrap_already_attempted = wrap_attempted,
		}
	search_allocators := search.Allocator_Set {
			persistent = request.persistent_allocator,
			temporary = request.temporary_allocator,
		}
	searched := false
	search_failure: search.Failure
	if request.pattern_kind == .Literal {
		searched, search_failure = search.literal_search(
			&result,
			&snapshot,
			&query,
			search_request,
			cancellation,
			search_allocators,
		)
	} else {
		searched, search_failure = search.regexp_search(
			&result,
			&snapshot,
			&query,
			search_request,
			cancellation,
			search_allocators,
		)
	}
	if !searched {
		return false, false, incremental_search_failure(search_failure)
	}
	defer if result.state != nil do search.result_close(&result)
	result_view, result_ok, result_failure := search.result_view(&result)
	if !result_ok {
		return false, false, incremental_search_failure(result_failure)
	}
	if result_view.outcome == .Cancelled {
		return false, false, Failure_Context{code = .Cancelled}
	}
	target := logical.point_position
	if result_view.outcome == .Matched {
		current := result_view.occurrences[result_view.current_index]
		target_offset := current.end
		if request.direction == .Backward {
			target_offset = current.start
		}
		target, _, snapshot_failure = editor.buffer_position(request.buffer, target_offset)
		if snapshot_failure.code != .None {
			return false, false, native_editor_failure({}, snapshot_failure)
		}
	}
	column, column_ok, column_failure := display.position_display_column(
		request.buffer,
		target,
		request.profile,
		logical.tab_width,
	)
	if !column_ok {
		return false, false, native_display_failure({}, column_failure)
	}
	plan, planned, plan_failure := cursor_reveal_plan(
		request.buffer,
		logical,
		target,
		column,
		request.constraints,
	)
	if !planned {
		return false, false, plan_failure
	}
	interaction_generation := u64(1)
	if active.present {
		interaction_generation = active.interaction_generation + 1
		if interaction_generation == 0 {
			return false, false, Failure_Context{code = .View_Failure, view_code = .State_Generation_Limit}
		}
	}
	published, publish_failure := editor_view.search_session_publish(
		request.view_registry,
		request.view,
		editor_view.Search_Update {
			interaction_generation = interaction_generation,
			policy_generation = request.policy_generation,
			direction = request.direction,
			scope = scope,
		},
		&query,
		&result,
	)
	if !published {
		return false, false, native_view_failure({}, publish_failure)
	}
	if plan.update {
		viewport_ok, viewport_failure := editor_view.set_viewport(
			request.view_registry,
			request.view,
			plan.origin,
			plan.horizontal,
		)
		if !viewport_ok {
			return false, false, native_view_failure({}, viewport_failure)
		}
	}
	return true, true, {}
}

/* incremental_search_accept retains point and closes one active search session. */
incremental_search_accept :: proc(
	registry: ^editor_view.Registry,
	view: editor_view.View_Handle,
) -> (bool, Failure_Context) {
	ok, failure := editor_view.search_session_accept(registry, view)
	if !ok {
		return false, native_view_failure({}, failure)
	}
	return true, {}
}

/* incremental_search_recover restores the retained successful query without rescanning. */
incremental_search_recover :: proc(
	registry: ^editor_view.Registry,
	view: editor_view.View_Handle,
	query_id: search.Query_ID,
	policy: search.Policy,
	limits: search.Limits,
	persistent_allocator: runtime.Allocator,
	temporary_allocator: runtime.Allocator,
) -> (bool, Failure_Context) {
	snapshot, viewed, view_failure := editor_view.search_session_view(registry, view)
	if !viewed {
		return false, native_view_failure({}, view_failure)
	}
	if !snapshot.present || snapshot.status != .Failing ||
	   len(snapshot.last_successful_query) == 0 {
		return false, Failure_Context{code = .Invalid_Request}
	}
	query: search.Query
	query_ok, query_failure := search.query_init(
		&query,
		search.Query_Config {
			id = query_id,
			kind = snapshot.kind,
			pattern = snapshot.last_successful_query,
			policy = policy,
			limits = limits,
			allocator = persistent_allocator,
			temporary_allocator = temporary_allocator,
		},
	)
	if !query_ok {
		return false, incremental_search_failure(query_failure)
	}
	defer if query.state != nil do search.query_close(&query)
	recovered, recover_failure := editor_view.search_session_recover(registry, view, &query)
	if !recovered {
		return false, native_view_failure({}, recover_failure)
	}
	return true, {}
}

/* incremental_search_abort restores origin and closes one active search session. */
incremental_search_abort :: proc(
	registry: ^editor_view.Registry,
	view: editor_view.View_Handle,
) -> (bool, Failure_Context) {
	ok, failure := editor_view.search_session_abort(registry, view)
	if !ok {
		return false, native_view_failure({}, failure)
	}
	return true, {}
}

@(private)
incremental_search_scope :: proc(
	logical: editor_view.Snapshot,
	active: editor_view.Search_Snapshot,
	stats: editor.Buffer_Stats,
) -> search.Scope {
	if active.present {
		return active.scope
	}
	start := editor.Byte_Offset(0)
	end := editor.Byte_Offset(stats.text_bytes)
	if logical.region_active && logical.mark.present {
		start = min(logical.point_position.byte_offset, logical.mark.position.byte_offset)
		end = max(logical.point_position.byte_offset, logical.mark.position.byte_offset)
	}
	return search.Scope {
		buffer_id = stats.buffer_id,
		revision = stats.revision,
		start = start,
		end = end,
	}
}

@(private)
incremental_search_origin :: proc(
	logical: editor_view.Snapshot,
	active: editor_view.Search_Snapshot,
	direction: search.Direction,
	turn: Incremental_Search_Turn,
) -> (editor.Byte_Offset, bool) {
	if !active.present {
		return logical.point_position.byte_offset, false
	}
	if turn == .Query_Update {
		return active.origin_point_position.byte_offset, false
	}
	if active.status == .Pending || active.status == .Wrapped {
		return active.progress.next_offset, active.progress.wrapped
	}
	if active.has_current && int(active.current_index) < len(active.occurrences) {
		current := active.occurrences[active.current_index]
		if direction == .Forward {
			return current.end, false
		}
		return current.start, false
	}
	return active.origin_point_position.byte_offset, false
}

@(private)
incremental_search_failure :: proc(failure: search.Failure) -> Failure_Context {
	return Failure_Context {
		code = .Search_Failure,
		search_code = failure.code,
		search_diagnostic = failure.diagnostic,
		buffer_id = failure.buffer_id,
		revision = failure.revision,
		limit = failure.limit,
		actual = failure.actual,
	}
}

@(private)
incremental_regexp_repeat_origin :: proc(
	snapshot: ^editor.Buffer_Snapshot,
	scope: search.Scope,
	offset: editor.Byte_Offset,
	direction: search.Direction,
) -> editor.Byte_Offset {
	if direction == .Forward {
		if offset >= scope.end {
			return scope.end
		}
		storage: [4]byte
		copied, read_ok, _ := editor.buffer_snapshot_read(snapshot, offset, storage[:])
		if !read_ok || copied == 0 {
			return offset
		}
		_, width := utf8.decode_rune(storage[:copied])
		return editor.Byte_Offset(min(u64(scope.end), u64(offset) + u64(max(width, 1))))
	}
	if offset <= scope.start {
		return scope.start
	}
	read_start := max(u64(scope.start), u64(offset) - min(u64(offset) - u64(scope.start), u64(4)))
	storage: [4]byte
	copied, read_ok, _ := editor.buffer_snapshot_read(
		snapshot,
		editor.Byte_Offset(read_start),
		storage[:int(u64(offset) - read_start)],
	)
	if !read_ok || copied == 0 {
		return offset
	}
	_, width := utf8.decode_last_rune(storage[:copied])
	return editor.Byte_Offset(u64(offset) - u64(max(width, 1)))
}
