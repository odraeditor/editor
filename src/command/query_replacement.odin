// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../display"
import "../editor"
import "../interaction"
import "../search"
import edit_transaction "../transaction"
import editor_view "../view"

/* Query_Replacement_Action selects one checked progressive-replacement turn. */
Query_Replacement_Action :: enum u8 {
	Invalid,
	Start,
	Continue,
	Recompute,
	Replace,
	Skip,
	Replace_Remaining,
	Replace_And_Exit,
	Quit,
	Cancel,
}

/* Query_Replacement_Request describes one literal or regexp interaction turn. */
Query_Replacement_Request :: struct {
	native:             Native_Context,
	action:             Query_Replacement_Action,
	pattern:            string,
	replacement:        string,
	pattern_kind:       search.Pattern_Kind,
	direction:          search.Direction,
	semantic_group:     editor_view.Query_Replacement_Group_ID,
	query_id:           search.Query_ID,
	search_generation:  search.Search_Generation,
	policy_generation:  search.Policy_Generation,
	cancellation:       ^search.Cancellation,
	search_policy:      search.Policy,
	search_limits:      search.Limits,
	replacement_policy: search.Replacement_Policy,
	replace_all_limits: Replace_All_Limits,
	replacement_limits: search.Replacement_Limits,
}

/* Query_Replacement_Result owns any committed transaction and reports the terminal state. */
Query_Replacement_Result :: struct {
	native:               Native_Result,
	status:               editor_view.Query_Replacement_Status,
	replacements:         u64,
	skips:                u64,
	finished:             bool,
	replacement_usage:    search.Replacement_Usage,
	replace_all_usage:    Replace_All_Usage,
	continuation_failure: Failure_Context,
}

/* query_replacement_result_close releases a retained progressive transaction result. */
query_replacement_result_close :: proc(result: ^Query_Replacement_Result) {
	if result == nil {
		return
	}
	native_result_close(&result.native)
	result^ = {}
}

/*
query_replacement executes one checked response and never reverses earlier confirmations.
A post-commit continuation failure ends the session and is reported on the successful result.
*/
query_replacement :: proc(
	request: Query_Replacement_Request,
) -> (result: Query_Replacement_Result, ok: bool, failure: Failure_Context) {
	native := request.native
	if native.registry == nil || native.buffer == nil || native.view_registry == nil ||
	   request.action == .Invalid || request.policy_generation == search.Policy_Generation(0) {
		return {}, false, Failure_Context{code = .Invalid_Request, command = native.command}
	}
	metadata, metadata_ok, metadata_failure := interaction.command_metadata(
		native.registry,
		native.command,
	)
	if !metadata_ok {
		return {}, false, Failure_Context {
			code = .Invalid_Command,
			command = native.command,
			interaction_code = metadata_failure.code,
		}
	}
	route, route_ok := native_route_decode(metadata.route)
	if metadata.implementation != .Native || !route_ok ||
	   (route != .Query_Replace && route != .Query_Replace_Regexp) {
		return {}, false, Failure_Context{code = .Invalid_Command, command = native.command}
	}
	if native.cancelled {
		return {}, false, Failure_Context{code = .Cancelled, command = native.command}
	}
	logical, logical_ok, logical_failure := editor_view.snapshot(
		native.view_registry,
		native.view,
	)
	if !logical_ok {
		return {}, false, native_view_failure(native.command, logical_failure)
	}
	active, active_ok, active_failure := editor_view.query_replacement_session_view(
		native.view_registry,
		native.view,
	)
	if !active_ok {
		return {}, false, native_view_failure(native.command, active_failure)
	}
	stats, stats_ok, stats_failure := editor.buffer_stats(native.buffer)
	if !stats_ok {
		return {}, false, native_editor_failure(native.command, stats_failure)
	}
	if logical.buffer_id != stats.buffer_id || logical.revision != stats.revision {
		return {}, false, Failure_Context {
			code = .Search_Failure,
			command = native.command,
			search_code = .Stale_Revision,
			buffer_id = stats.buffer_id,
			revision = stats.revision,
		}
	}
	expected_kind := search.Pattern_Kind.Literal
	if route == .Query_Replace_Regexp {
		expected_kind = .Regular_Expression
	}

	if request.action == .Start {
		if active.present || len(request.pattern) == 0 || request.pattern_kind != expected_kind ||
		   (request.direction != .Forward && request.direction != .Backward) ||
		   request.semantic_group == editor_view.Query_Replacement_Group_ID(0) ||
		   request.search_policy.case_mode == .Invalid ||
		   request.replacement_policy.case_preservation == .Invalid {
			return {}, false, Failure_Context{code = .Invalid_Request, command = native.command}
		}
		scope := incremental_search_scope(logical, {}, stats)
		wrap_attempted := (request.direction == .Forward && logical.point_position.byte_offset == scope.start) ||
		                  (request.direction == .Backward && logical.point_position.byte_offset == scope.end)
		return query_replacement_scan(
			request,
			request.pattern,
			request.replacement,
			request.pattern_kind,
			request.direction,
			request.search_policy,
			request.replacement_policy,
			request.semantic_group,
			1,
			0,
			0,
			scope,
			logical.point_position.byte_offset,
			wrap_attempted,
			.Started,
		)
	}
	if !active.present || active.kind != expected_kind {
		return {}, false, Failure_Context{code = .Invalid_Request, command = native.command}
	}
	if active.policy_generation != request.policy_generation ||
	   active.search_policy != request.search_policy || active.search_limits != request.search_limits ||
	   active.replacement_policy != request.replacement_policy ||
	   active.replacement_limits != request.replacement_limits {
		return {}, false, Failure_Context{code = .Invalid_Request, command = native.command}
	}
	if request.action == .Quit || request.action == .Cancel {
		finished, finish_failure := editor_view.query_replacement_session_finish(
			native.view_registry,
			native.view,
		)
		if !finished {
			return {}, false, native_view_failure(native.command, finish_failure)
		}
		return Query_Replacement_Result {
			status = active.status,
			replacements = active.replacements,
			skips = active.skips,
			finished = true,
		}, true, {}
	}
	if request.query_id == search.Query_ID(0) ||
	   request.search_generation == search.Search_Generation(0) {
		return {}, false, Failure_Context{code = .Invalid_Request, command = native.command}
	}
	if active.status == .Recomputation_Required && request.action != .Recompute {
		return {}, false, Failure_Context {
			code = .Search_Failure,
			command = native.command,
			search_code = .Stale_Revision,
			buffer_id = stats.buffer_id,
			revision = stats.revision,
		}
	}
	switch request.action {
	case .Continue:
		if active.status != .Pending && active.status != .Wrapped {
			return {}, false, Failure_Context{code = .Invalid_Request, command = native.command}
		}
		return query_replacement_scan_active(
			request,
			active,
			active.scope,
			active.progress.next_offset,
			active.progress.wrapped,
			.Continued,
			active.replacements,
			active.skips,
		)
	case .Recompute:
		if active.status != .Recomputation_Required {
			return {}, false, Failure_Context{code = .Invalid_Request, command = native.command}
		}
		scope := active.scope
		if scope.start == 0 && u64(scope.end) == active.source_text_bytes {
			scope.end = editor.Byte_Offset(stats.text_bytes)
		} else if stats.text_bytes != active.source_text_bytes {
			return {}, false, Failure_Context {
				code = .Search_Failure,
				command = native.command,
				search_code = .Stale_Revision,
				buffer_id = stats.buffer_id,
				revision = stats.revision,
			}
		}
		if scope.start > scope.end || u64(scope.end) > stats.text_bytes {
			return {}, false, Failure_Context{code = .Invalid_Request, command = native.command}
		}
		scope.revision = stats.revision
		origin := logical.point_position.byte_offset
		if origin < scope.start || origin > scope.end {
			origin = scope.start if active.direction == .Forward else scope.end
		}
		return query_replacement_scan_active(
			request,
			active,
			scope,
			origin,
			false,
			.Recomputed,
			active.replacements,
			active.skips,
		)
	case .Skip:
		if !active.has_current || active.skips == max(u64) {
			return {}, false, Failure_Context{code = .Invalid_Request, command = native.command}
		}
		origin, origin_ok, origin_failure := query_replacement_next_origin(
			request,
			active,
		)
		if !origin_ok {
			return {}, false, origin_failure
		}
		return query_replacement_scan_active(
			request,
			active,
			active.scope,
			origin,
			false,
			.Skipped,
			active.replacements,
			active.skips + 1,
		)
	case .Replace, .Replace_And_Exit:
		if !active.has_current || active.replacements == max(u64) {
			return {}, false, Failure_Context{code = .Invalid_Request, command = native.command}
		}
		return query_replacement_replace_current(
			request,
			logical,
			active,
			request.action == .Replace_And_Exit,
		)
	case .Replace_Remaining:
		if !active.has_current {
			return {}, false, Failure_Context{code = .Invalid_Request, command = native.command}
		}
		return query_replacement_replace_remaining(request, active)
	case .Invalid, .Start, .Quit, .Cancel:
		return {}, false, Failure_Context{code = .Invalid_Request, command = native.command}
	}
	unreachable()
}

@(private)
query_replacement_scan_active :: proc(
	request: Query_Replacement_Request,
	active: editor_view.Query_Replacement_Snapshot,
	scope: search.Scope,
	origin: editor.Byte_Offset,
	wrap_attempted: bool,
	response: editor_view.Query_Replacement_Response,
	replacements, skips: u64,
) -> (Query_Replacement_Result, bool, Failure_Context) {
	if active.interaction_generation == max(u64) {
		return {}, false, Failure_Context {
			code = .View_Failure,
			command = request.native.command,
			view_code = .State_Generation_Limit,
		}
	}
	return query_replacement_scan(
		request,
		active.pattern,
		active.replacement,
		active.kind,
		active.direction,
		active.search_policy,
		active.replacement_policy,
		active.semantic_group,
		active.interaction_generation + 1,
		replacements,
		skips,
		scope,
		origin,
		wrap_attempted,
		response,
	)
}

@(private)
query_replacement_scan :: proc(
	request: Query_Replacement_Request,
	pattern, replacement: string,
	pattern_kind: search.Pattern_Kind,
	direction: search.Direction,
	search_policy: search.Policy,
	replacement_policy: search.Replacement_Policy,
	semantic_group: editor_view.Query_Replacement_Group_ID,
	interaction_generation, replacements, skips: u64,
	scope: search.Scope,
	origin: editor.Byte_Offset,
	wrap_attempted: bool,
	response: editor_view.Query_Replacement_Response,
) -> (Query_Replacement_Result, bool, Failure_Context) {
	native := request.native
	if request.query_id == search.Query_ID(0) ||
	   request.search_generation == search.Search_Generation(0) ||
	   interaction_generation == 0 {
		return {}, false, Failure_Context{code = .Invalid_Request, command = native.command}
	}
	query: search.Query
	query_ok, query_failure := search.query_init(
		&query,
		search.Query_Config {
			id = request.query_id,
			kind = pattern_kind,
			pattern = pattern,
			policy = search_policy,
			limits = request.search_limits,
			allocator = native.persistent_allocator,
			temporary_allocator = native.temporary_allocator,
		},
	)
	if !query_ok {
		return {}, false, incremental_search_failure(query_failure)
	}
	defer if query.state != nil do search.query_close(&query)
	template: search.Replacement_Template
	template_ok, template_failure := search.replacement_template_init(
		&template,
		&query,
		search.Replacement_Template_Config {
			text = replacement,
			policy = replacement_policy,
			limits = request.replacement_limits,
			allocator = native.persistent_allocator,
		},
	)
	if !template_ok {
		return {}, false, incremental_search_failure(template_failure)
	}
	defer if template.state != nil do search.replacement_template_close(&template)
	buffer_snapshot: editor.Buffer_Snapshot
	opened, open_failure := editor.buffer_snapshot_open(native.buffer, &buffer_snapshot)
	if !opened {
		return {}, false, native_editor_failure(native.command, open_failure)
	}
	defer editor.buffer_snapshot_close(&buffer_snapshot)
	result: search.Result
	searched := false
	search_failure: search.Failure
	search_request := search.Request {
		scope = scope,
		origin = origin,
		direction = direction,
		generation = request.search_generation,
		wrap_already_attempted = wrap_attempted,
	}
	allocators := search.Allocator_Set {
		persistent = native.persistent_allocator,
		temporary = native.temporary_allocator,
	}
	if pattern_kind == .Literal {
		searched, search_failure = search.literal_search(
			&result,
			&buffer_snapshot,
			&query,
			search_request,
			request.cancellation,
			allocators,
		)
	} else {
		searched, search_failure = search.regexp_search(
			&result,
			&buffer_snapshot,
			&query,
			search_request,
			request.cancellation,
			allocators,
		)
	}
	if !searched {
		return {}, false, incremental_search_failure(search_failure)
	}
	defer if result.state != nil do search.result_close(&result)
	result_view, result_ok, result_failure := search.result_view(&result)
	if !result_ok {
		return {}, false, incremental_search_failure(result_failure)
	}
	if result_view.outcome == .Cancelled {
		return {}, false, Failure_Context{code = .Cancelled, command = native.command}
	}
	published, publish_failure := editor_view.query_replacement_session_publish(
		native.view_registry,
		native.view,
		editor_view.Query_Replacement_Update {
			interaction_generation = interaction_generation,
			policy_generation = request.policy_generation,
			direction = direction,
			scope = scope,
			semantic_group = semantic_group,
			response = response,
			replacements = replacements,
			skips = skips,
		},
		&query,
		&template,
		&result,
	)
	if !published {
		return {}, false, native_view_failure(native.command, publish_failure)
	}
	state, state_ok, state_failure := editor_view.query_replacement_session_view(
		native.view_registry,
		native.view,
	)
	if !state_ok {
		return {}, false, native_view_failure(native.command, state_failure)
	}
	result_value := Query_Replacement_Result {
		status = state.status,
		replacements = state.replacements,
		skips = state.skips,
	}
	if state.status == .Exhausted {
		finished, finish_failure := editor_view.query_replacement_session_finish(
			native.view_registry,
			native.view,
		)
		if !finished {
			return {}, false, native_view_failure(native.command, finish_failure)
		}
		result_value.finished = true
	}
	return result_value, true, {}
}

@(private)
query_replacement_next_origin :: proc(
	request: Query_Replacement_Request,
	active: editor_view.Query_Replacement_Snapshot,
) -> (editor.Byte_Offset, bool, Failure_Context) {
	current := active.occurrences[active.current_index]
	origin := current.end if active.direction == .Forward else current.start
	if active.kind != .Regular_Expression || current.start != current.end {
		return origin, true, {}
	}
	buffer_snapshot: editor.Buffer_Snapshot
	opened, open_failure := editor.buffer_snapshot_open(request.native.buffer, &buffer_snapshot)
	if !opened {
		return 0, false, native_editor_failure(request.native.command, open_failure)
	}
	origin = incremental_regexp_repeat_origin(
		&buffer_snapshot,
		active.scope,
		origin,
		active.direction,
	)
	editor.buffer_snapshot_close(&buffer_snapshot)
	return origin, true, {}
}

@(private)
query_replacement_replace_current :: proc(
	request: Query_Replacement_Request,
	logical: editor_view.Snapshot,
	active: editor_view.Query_Replacement_Snapshot,
	exit_after: bool,
) -> (Query_Replacement_Result, bool, Failure_Context) {
	native := request.native
	current := active.occurrences[active.current_index]
	query: search.Query
	query_ok, query_failure := search.query_init(
		&query,
		search.Query_Config {
			id = request.query_id,
			kind = active.kind,
			pattern = active.pattern,
			policy = active.search_policy,
			limits = active.search_limits,
			allocator = native.persistent_allocator,
			temporary_allocator = native.temporary_allocator,
		},
	)
	if !query_ok {
		return {}, false, incremental_search_failure(query_failure)
	}
	defer search.query_close(&query)
	template: search.Replacement_Template
	template_ok, template_failure := search.replacement_template_init(
		&template,
		&query,
		search.Replacement_Template_Config {
			text = active.replacement,
			policy = active.replacement_policy,
			limits = request.replacement_limits,
			allocator = native.persistent_allocator,
		},
	)
	if !template_ok {
		return {}, false, incremental_search_failure(template_failure)
	}
	defer search.replacement_template_close(&template)
	buffer_snapshot: editor.Buffer_Snapshot
	opened, open_failure := editor.buffer_snapshot_open(native.buffer, &buffer_snapshot)
	if !opened {
		return {}, false, native_editor_failure(native.command, open_failure)
	}
	defer editor.buffer_snapshot_close(&buffer_snapshot)
	expansion: search.Replacement_Expansion
	expanded, expansion_failure := search.replacement_expand(
		&expansion,
		&buffer_snapshot,
		&template,
		current,
		active.captures,
		search.Allocator_Set {
			persistent = native.persistent_allocator,
			temporary = native.temporary_allocator,
		},
	)
	if !expanded {
		return {}, false, incremental_search_failure(expansion_failure)
	}
	defer search.replacement_expansion_close(&expansion)
	expansion_view, expansion_ok, expansion_view_failure := search.replacement_expansion_view(
		&expansion,
	)
	if !expansion_ok {
		return {}, false, incremental_search_failure(expansion_view_failure)
	}
	start, start_ok, start_failure := editor.buffer_position(native.buffer, current.start)
	if !start_ok {
		return {}, false, native_editor_failure(native.command, start_failure)
	}
	end, end_ok, end_failure := editor.buffer_position(native.buffer, current.end)
	if !end_ok {
		return {}, false, native_editor_failure(native.command, end_failure)
	}
	column, column_ok, column_failure := display.position_display_column(
		native.buffer,
		start,
		native.profile,
		logical.tab_width,
	)
	if !column_ok {
		return {}, false, native_display_failure(native.command, column_failure)
	}
	final_column, width_ok, width_failure := inserted_text_end_column(
		expansion_view.text,
		column,
		logical.tab_width,
		native.profile,
	)
	if !width_ok {
		width_failure.command = native.command
		return {}, false, width_failure
	}
	grouping := native.history_grouping
	grouping.kind = .Query_Replacement
	grouping.view_id = native.view.view_id
	grouping.view_generation = native.view.generation
	grouping.continuity = u64(active.semantic_group)
	native.history_grouping = grouping
	result_offset := editor.Byte_Offset(u64(current.start) + u64(len(expansion_view.text)))
	command_name := "query-replace"
	if active.kind == .Regular_Expression {
		command_name = "query-replace-regexp"
	}
	native_result, committed, commit_failure := native_edit_publish(
		native,
		logical,
		edit_transaction.Origin{kind = .Built_In, descriptor = "native-command"},
		command_name,
		start,
		end,
		expansion_view.text,
		result_offset,
		final_column,
		false,
		nil,
	)
	if !committed {
		return {}, false, commit_failure
	}
	result := Query_Replacement_Result {
		native = native_result,
		status = .Awaiting_Response,
		replacements = active.replacements + 1,
		skips = active.skips,
		replacement_usage = expansion_view.usage,
	}
	if exit_after {
		finished, finish_failure := editor_view.query_replacement_session_finish(
			native.view_registry,
			native.view,
		)
		if !finished {
			result.finished = true
			result.continuation_failure = native_view_failure(native.command, finish_failure)
			return result, true, {}
		}
		result.finished = true
		return result, true, {}
	}
	new_scope, scope_ok := query_replacement_scope_after_edit(
		active.scope,
		current,
		u64(len(expansion_view.text)),
	)
	if !scope_ok {
		query_replacement_end_after_commit(&result, native)
		result.continuation_failure = Failure_Context{code = .Text_Limit, command = native.command}
		return result, true, {}
	}
	new_scope.revision = editor.Revision(u64(active.scope.revision) + 1)
	origin := result_offset if active.direction == .Forward else current.start
	continued, continued_ok, continuation_failure := query_replacement_scan_active(
		request,
		active,
		new_scope,
		origin,
		false,
		.Replaced,
		active.replacements + 1,
		active.skips,
	)
	if !continued_ok {
		query_replacement_end_after_commit(&result, native)
		result.continuation_failure = continuation_failure
		return result, true, {}
	}
	continued.native = native_result
	return continued, true, {}
}

@(private)
query_replacement_replace_remaining :: proc(
	request: Query_Replacement_Request,
	active: editor_view.Query_Replacement_Snapshot,
) -> (Query_Replacement_Result, bool, Failure_Context) {
	native := request.native
	current := active.occurrences[active.current_index]
	scope := active.scope
	if active.direction == .Forward {
		scope.start = current.start
	} else {
		scope.end = current.end
	}
	grouping := native.history_grouping
	grouping.kind = .Query_Replacement
	grouping.view_id = native.view.view_id
	grouping.view_generation = native.view.generation
	grouping.continuity = u64(active.semantic_group)
	native.history_grouping = grouping
	all_result, replaced, replace_failure := replace_all(
		Replace_All_Request {
			native = native,
			pattern = active.pattern,
			replacement = active.replacement,
			pattern_kind = active.kind,
			search_policy = active.search_policy,
			replacement_policy = active.replacement_policy,
			query_id = request.query_id,
			search_generation = request.search_generation,
			cancellation = request.cancellation,
			scope = scope,
			limits = request.replace_all_limits,
			replacement_limits = request.replacement_limits,
		},
	)
	if !replaced {
		return {}, false, replace_failure
	}
	finished, finish_failure := editor_view.query_replacement_session_finish(
		native.view_registry,
		native.view,
	)
	result := Query_Replacement_Result {
		native = all_result.native,
		status = .Exhausted,
		replacements = active.replacements + all_result.usage.matches,
		skips = active.skips,
		finished = true,
		replace_all_usage = all_result.usage,
	}
	if !finished {
		result.continuation_failure = native_view_failure(native.command, finish_failure)
	}
	all_result.native = {}
	replace_all_result_close(&all_result)
	return result, true, {}
}

@(private)
query_replacement_scope_after_edit :: proc(
	scope: search.Scope,
	occurrence: search.Occurrence,
	replacement_bytes: u64,
) -> (search.Scope, bool) {
	updated := scope
	removed := u64(occurrence.end) - u64(occurrence.start)
	end := u64(scope.end)
	if replacement_bytes >= removed {
		delta := replacement_bytes - removed
		if end > max(u64) - delta {
			return {}, false
		}
		end += delta
	} else {
		delta := removed - replacement_bytes
		if delta > end {
			return {}, false
		}
		end -= delta
	}
	updated.end = editor.Byte_Offset(end)
	return updated, true
}

@(private)
query_replacement_end_after_commit :: proc(
	result: ^Query_Replacement_Result,
	native: Native_Context,
) {
	finished, _ := editor_view.query_replacement_session_finish(
		native.view_registry,
		native.view,
	)
	result.finished = finished
}
