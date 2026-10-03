// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../editor"
import "../history"
import "../interaction"
import "../search"
import edit_transaction "../transaction"
import editor_view "../view"

/* MIN_REPLACE_ALL_MATCHES is the smallest configurable atomic batch ceiling. */
MIN_REPLACE_ALL_MATCHES :: u64(1)
/* MAX_REPLACE_ALL_MATCHES matches the transaction splice ceiling. */
MAX_REPLACE_ALL_MATCHES :: u64(edit_transaction.MAX_SPLICES)
/* DEFAULT_REPLACE_ALL_MATCHES is the factory atomic replacement ceiling. */
DEFAULT_REPLACE_ALL_MATCHES :: MAX_REPLACE_ALL_MATCHES
/* MIN_REPLACE_ALL_TEXT_BYTES is the smallest admitted combined edit budget. */
MIN_REPLACE_ALL_TEXT_BYTES :: u64(64 * 1_024)
/* MAX_REPLACE_ALL_TEXT_BYTES matches the transaction retained-text ceiling. */
MAX_REPLACE_ALL_TEXT_BYTES :: u64(edit_transaction.MAX_TEXT_BYTES)
/* DEFAULT_REPLACE_ALL_TEXT_BYTES aligns one operation with factory history retention. */
DEFAULT_REPLACE_ALL_TEXT_BYTES :: u64(history.DEFAULT_PAYLOAD_BYTES_PER_UNIT)
/* MIN_REPLACE_ALL_TEMPORARY_BYTES admits one default bounded search turn. */
MIN_REPLACE_ALL_TEMPORARY_BYTES :: u64(64 * 1_024 * 1_024)
/* MAX_REPLACE_ALL_TEMPORARY_BYTES matches transaction scratch storage. */
MAX_REPLACE_ALL_TEMPORARY_BYTES :: u64(edit_transaction.MAX_TEMPORARY_BYTES)
/* DEFAULT_REPLACE_ALL_TEMPORARY_BYTES is the factory private-analysis budget. */
DEFAULT_REPLACE_ALL_TEMPORARY_BYTES :: MAX_REPLACE_ALL_TEMPORARY_BYTES
/* MIN_REPLACE_ALL_ANALYSIS_BYTES admits one complete factory search window. */
MIN_REPLACE_ALL_ANALYSIS_BYTES :: u64(search.DEFAULT_SCAN_WINDOW_BYTES)
/* MAX_REPLACE_ALL_ANALYSIS_BYTES bounds repeated inspection of a maximum buffer. */
MAX_REPLACE_ALL_ANALYSIS_BYTES :: u64(2 * editor.MAX_BUFFER_BYTES)
/* DEFAULT_REPLACE_ALL_ANALYSIS_BYTES permits one bounded revisit per source byte. */
DEFAULT_REPLACE_ALL_ANALYSIS_BYTES :: MAX_REPLACE_ALL_ANALYSIS_BYTES
/* DEFAULT_REPLACE_ALL_TURN_OCCURRENCES bounds one copied enumeration turn. */
DEFAULT_REPLACE_ALL_TURN_OCCURRENCES :: u32(4_096)

/* Replace_All_Limits bounds match count, edit payload, scratch, and analysis work. */
Replace_All_Limits :: struct {
	matches:         u64,
	text_bytes:      u64,
	temporary_bytes: u64,
	analysis_bytes:  u64,
}

/* DEFAULT_REPLACE_ALL_LIMITS supplies the factory atomic replacement profile. */
DEFAULT_REPLACE_ALL_LIMITS :: Replace_All_Limits {
	matches = DEFAULT_REPLACE_ALL_MATCHES,
	text_bytes = DEFAULT_REPLACE_ALL_TEXT_BYTES,
	temporary_bytes = DEFAULT_REPLACE_ALL_TEMPORARY_BYTES,
	analysis_bytes = DEFAULT_REPLACE_ALL_ANALYSIS_BYTES,
}

/* Replace_All_Usage reports complete private analysis and committed batch size. */
Replace_All_Usage :: struct {
	matches:          u64,
	captures:         u64,
	analysis_bytes:   u64,
	source_read_bytes: u64,
	removed_bytes:    u64,
	expanded_bytes:   u64,
	transaction_bytes: u64,
	search_turns:     u64,
	cancellation_checks: u64,
}

/* Replace_All_Request describes one literal or regexp atomic command invocation. */
Replace_All_Request :: struct {
	native:             Native_Context,
	pattern:            string,
	replacement:        string,
	pattern_kind:       search.Pattern_Kind,
	search_policy:      search.Policy,
	replacement_policy: search.Replacement_Policy,
	query_id:           search.Query_ID,
	search_generation:  search.Search_Generation,
	cancellation:       ^search.Cancellation,
	scope:              search.Scope,
	limits:             Replace_All_Limits,
	replacement_limits: search.Replacement_Limits,
}

/* Replace_All_Result owns the committed native result and reports replacement usage. */
Replace_All_Result :: struct {
	native: Native_Result,
	usage:  Replace_All_Usage,
}

/* replace_all_result_close releases the retained transaction result. */
replace_all_result_close :: proc(result: ^Replace_All_Result) {
	if result == nil {
		return
	}
	native_result_close(&result.native)
	result.usage = {}
}

/*
replace_all enumerates one captured scope and publishes one base-relative batch.
Every match and expansion is prepared before transaction validation or publication.
*/
replace_all :: proc(
	request: Replace_All_Request,
) -> (result: Replace_All_Result, ok: bool, failure: Failure_Context) {
	native := request.native
	if native.registry == nil || native.buffer == nil || native.view_registry == nil ||
	   native.persistent_allocator.procedure == nil ||
	   native.temporary_allocator.procedure == nil ||
	   native.transaction_id == edit_transaction.Transaction_ID(0) ||
	   native.undo_unit_id == edit_transaction.Undo_Unit_ID(0) ||
	   request.query_id == search.Query_ID(0) ||
	   request.search_generation == search.Search_Generation(0) ||
	   (request.pattern_kind != .Literal && request.pattern_kind != .Regular_Expression) ||
	   !replace_all_limits_are_valid(request.limits) ||
	   !search.replacement_limits_are_valid(request.replacement_limits) ||
	   request.replacement_limits.expanded_bytes > request.limits.text_bytes ||
	   request.replacement_limits.temporary_bytes > request.limits.temporary_bytes {
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
	expected_route := Native_Route.Replace_String
	query_route := Native_Route.Query_Replace
	if request.pattern_kind == .Regular_Expression {
		expected_route = .Replace_Regexp
		query_route = .Query_Replace_Regexp
	}
	route, route_ok := native_route_decode(metadata.route)
	if metadata.implementation != .Native || !route_ok ||
	   (route != expected_route && route != query_route) {
		return {}, false, Failure_Context{code = .Invalid_Command, command = native.command}
	}
	if native.cancelled {
		return {}, false, Failure_Context{code = .Cancelled, command = native.command}
	}
	if request.cancellation != nil &&
	   request.cancellation.generation != request.search_generation {
		return {}, false, Failure_Context{code = .Invalid_Request, command = native.command}
	}
	logical, logical_ok, logical_failure := editor_view.snapshot(native.view_registry, native.view)
	if !logical_ok {
		return {}, false, native_view_failure(native.command, logical_failure)
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
	display_failure := validate_display_request(native, logical, 2, true)
	if display_failure.code != .None {
		return {}, false, display_failure
	}
	scope := incremental_search_scope(logical, {}, stats)
	if request.scope.buffer_id != editor.Buffer_ID(0) {
		if request.scope.buffer_id != stats.buffer_id || request.scope.revision != stats.revision ||
		   request.scope.start > request.scope.end || u64(request.scope.end) > stats.text_bytes {
			return {}, false, Failure_Context {
				code = .Search_Failure,
				command = native.command,
				search_code = .Invalid_Scope,
				buffer_id = stats.buffer_id,
				revision = stats.revision,
			}
		}
		scope = request.scope
	}
	query_limits, query_limits_ok := replace_all_query_limits(request.limits)
	if !query_limits_ok {
		return {}, false, Failure_Context {
			code = .Temporary_Memory_Limit,
			command = native.command,
			limit = request.limits.temporary_bytes,
		}
	}
	query: search.Query
	query_ok, query_failure := search.query_init(
		&query,
		search.Query_Config {
			id = request.query_id,
			kind = request.pattern_kind,
			pattern = request.pattern,
			policy = search.Policy {
				case_mode = request.search_policy.case_mode,
				boundary_mode = request.search_policy.boundary_mode,
				whitespace_mode = request.search_policy.whitespace_mode,
				wrap = false,
			},
			limits = query_limits,
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
			text = request.replacement,
			policy = request.replacement_policy,
			limits = request.replacement_limits,
			allocator = native.persistent_allocator,
		},
	)
	if !template_ok {
		return {}, false, incremental_search_failure(template_failure)
	}
	defer if template.state != nil do search.replacement_template_close(&template)
	snapshot: editor.Buffer_Snapshot
	snapshot_ok, snapshot_failure := editor.buffer_snapshot_open(native.buffer, &snapshot)
	if !snapshot_ok {
		return {}, false, native_editor_failure(native.command, snapshot_failure)
	}
	defer editor.buffer_snapshot_close(&snapshot)

	array_bytes, arrays_ok := replace_all_array_bytes(request.limits.matches)
	if !arrays_ok || array_bytes > request.limits.temporary_bytes {
		return {}, false, Failure_Context {
			code = .Temporary_Memory_Limit,
			command = native.command,
			limit = request.limits.temporary_bytes,
			actual = array_bytes,
		}
	}
	batch, batch_error := make(
		[]edit_transaction.Base_Splice,
		int(request.limits.matches),
		native.temporary_allocator,
	)
	if batch_error != nil {
		return {}, false, Failure_Context {
			code = .Temporary_Memory_Limit,
			command = native.command,
			actual = array_bytes,
		}
	}
	defer delete(batch, native.temporary_allocator)
	expansions, expansion_array_error := make(
		[]search.Replacement_Expansion,
		int(request.limits.matches),
		native.temporary_allocator,
	)
	if expansion_array_error != nil {
		return {}, false, Failure_Context {
			code = .Temporary_Memory_Limit,
			command = native.command,
			actual = array_bytes,
		}
	}
	defer delete(expansions, native.temporary_allocator)
	expansion_count := 0
	defer {
		for index in 0 ..< expansion_count {
			if expansions[index].state != nil {
				search.replacement_expansion_close(&expansions[index])
			}
		}
	}

	usage: Replace_All_Usage
	origin := scope.start
	minimum_start := scope.start
	complete := false
	for !complete {
		if replace_all_cancelled(request) {
			return {}, false, Failure_Context{code = .Cancelled, command = native.command}
		}
		usage.cancellation_checks += 1
		search_base, search_base_ok := replace_checked_add(array_bytes, usage.expanded_bytes)
		search_peak, search_peak_ok := replace_checked_add(search_base, query_limits.temporary_bytes)
		if !search_base_ok || !search_peak_ok || search_peak > request.limits.temporary_bytes {
			return {}, false, Failure_Context {
				code = .Temporary_Memory_Limit,
				command = native.command,
				limit = request.limits.temporary_bytes,
				actual = search_peak,
			}
		}
		search_result: search.Result
		searched := false
		turn_failure: search.Failure
		turn_request := search.Request {
			scope = scope,
			origin = origin,
			direction = .Forward,
			generation = request.search_generation,
			wrap_already_attempted = true,
		}
		search_allocators := search.Allocator_Set {
			persistent = native.persistent_allocator,
			temporary = native.temporary_allocator,
		}
		if request.pattern_kind == .Literal {
			searched, turn_failure = search.literal_search(
				&search_result,
				&snapshot,
				&query,
				turn_request,
				request.cancellation,
				search_allocators,
			)
		} else {
			searched, turn_failure = search.regexp_search(
				&search_result,
				&snapshot,
				&query,
				turn_request,
				request.cancellation,
				search_allocators,
			)
		}
		if !searched {
			return {}, false, incremental_search_failure(turn_failure)
		}
		turn, turn_ok, turn_view_failure := search.result_view(&search_result)
		if !turn_ok {
			search.result_close(&search_result)
			return {}, false, incremental_search_failure(turn_view_failure)
		}
		usage.search_turns += 1
		usage.analysis_bytes, arrays_ok = replace_checked_add(
			usage.analysis_bytes,
			turn.usage.logical_bytes,
		)
		usage.source_read_bytes, query_limits_ok = replace_checked_add(
			usage.source_read_bytes,
			turn.usage.read_bytes,
		)
		if !arrays_ok || !query_limits_ok || usage.analysis_bytes > request.limits.analysis_bytes {
			search.result_close(&search_result)
			return {}, false, Failure_Context {
				code = .Search_Failure,
				command = native.command,
				search_code = .Work_Limit,
				limit = request.limits.analysis_bytes,
				actual = usage.analysis_bytes,
			}
		}
		if turn.outcome == .Cancelled {
			search.result_close(&search_result)
			return {}, false, Failure_Context{code = .Cancelled, command = native.command}
		}
		last_accepted := Occurrence_Progress{}
		for occurrence in turn.occurrences {
			if occurrence.start < minimum_start {
				continue
			}
			if u64(expansion_count) >= request.limits.matches {
				search.result_close(&search_result)
				return {}, false, Failure_Context {
					code = .Search_Failure,
					command = native.command,
					search_code = .Work_Limit,
					limit = request.limits.matches,
					actual = u64(expansion_count) + 1,
				}
			}
			expansion_index := expansion_count
			expanded, expansion_failure := search.replacement_expand(
				&expansions[expansion_index],
				&snapshot,
				&template,
				occurrence,
				turn.captures,
				search.Allocator_Set {
					persistent = native.temporary_allocator,
					temporary = native.temporary_allocator,
				},
			)
			if !expanded {
				search.result_close(&search_result)
				return {}, false, incremental_search_failure(expansion_failure)
			}
			expansion_count += 1
			expanded_view, expanded_ok, expanded_failure := search.replacement_expansion_view(
				&expansions[expansion_index],
			)
			if !expanded_ok {
				search.result_close(&search_result)
				return {}, false, incremental_search_failure(expanded_failure)
			}
			removed := u64(occurrence.end) - u64(occurrence.start)
			usage.removed_bytes, arrays_ok = replace_checked_add(usage.removed_bytes, removed)
			usage.expanded_bytes, query_limits_ok = replace_checked_add(
				usage.expanded_bytes,
				expanded_view.usage.expanded_bytes,
			)
			transaction_ok: bool
			usage.transaction_bytes, transaction_ok = replace_checked_add(
				usage.removed_bytes,
				usage.expanded_bytes,
			)
			if !arrays_ok || !query_limits_ok || !transaction_ok ||
			   usage.transaction_bytes > request.limits.text_bytes {
				search.result_close(&search_result)
				return {}, false, Failure_Context {
					code = .Text_Limit,
					command = native.command,
					limit = request.limits.text_bytes,
					actual = usage.transaction_bytes,
				}
			}
			private_base, private_base_ok := replace_checked_add(array_bytes, usage.expanded_bytes)
			private_peak, private_peak_ok := replace_checked_add(
				private_base,
				expanded_view.usage.temporary_peak_bytes,
			)
			if !private_base_ok || !private_peak_ok || private_peak > request.limits.temporary_bytes {
				search.result_close(&search_result)
				return {}, false, Failure_Context {
					code = .Temporary_Memory_Limit,
					command = native.command,
					limit = request.limits.temporary_bytes,
					actual = private_peak,
				}
			}
			batch[expansion_index] = edit_transaction.Base_Splice {
				start = editor.Position{buffer_id = scope.buffer_id, revision = scope.revision, byte_offset = occurrence.start},
				end = editor.Position{buffer_id = scope.buffer_id, revision = scope.revision, byte_offset = occurrence.end},
				replacement = expanded_view.text,
			}
			usage.matches += 1
			usage.captures += u64(occurrence.capture_count)
			usage.source_read_bytes, arrays_ok = replace_checked_add(
				usage.source_read_bytes,
				expanded_view.usage.source_bytes,
			)
			if !arrays_ok {
				search.result_close(&search_result)
				return {}, false, Failure_Context{code = .Search_Failure, command = native.command, search_code = .Arithmetic_Overflow}
			}
			minimum_start = occurrence.end
			last_accepted = Occurrence_Progress {
				present = true,
				start = occurrence.start,
				end = occurrence.end,
			}
		}
		turn_complete := turn.progress.complete
		turn_occurrences := len(turn.occurrences)
		next_origin := turn.progress.next_offset
		search.result_close(&search_result)
		complete = turn_complete
		if complete {
			break
		}
		if turn_occurrences == int(query_limits.retained_occurrences) && last_accepted.present {
			next_origin = last_accepted.end
			if last_accepted.start == last_accepted.end {
				next_origin = incremental_regexp_repeat_origin(
					&snapshot,
					scope,
					last_accepted.end,
					.Forward,
				)
			}
		}
		if next_origin <= origin {
			return {}, false, Failure_Context {
				code = .Search_Failure,
				command = native.command,
				search_code = .Work_Limit,
				actual = u64(next_origin),
			}
		}
		origin = next_origin
	}

	if expansion_count == 0 {
		return Replace_All_Result {
			native = Native_Result{completion = .No_Op},
			usage = usage,
		}, true, {}
	}
	current, current_ok, current_failure := editor.buffer_snapshot_is_current(native.buffer, &snapshot)
	if !current_ok {
		return {}, false, native_editor_failure(native.command, current_failure)
	}
	if !current {
		return {}, false, Failure_Context {
			code = .Search_Failure,
			command = native.command,
			search_code = .Stale_Revision,
			buffer_id = scope.buffer_id,
			revision = scope.revision,
		}
	}
	transaction: edit_transaction.Transaction
	started, begin_failure := edit_transaction.transaction_begin(
		&transaction,
		native.transaction_id,
		native.undo_unit_id,
		native.buffer,
		edit_transaction.Origin{kind = .Built_In, descriptor = "native-command"},
		metadata.name,
		edit_transaction.Allocator_Set {
			persistent = native.persistent_allocator,
			temporary = native.temporary_allocator,
		},
	)
	if !started {
		return {}, false, native_transaction_failure(native.command, begin_failure)
	}
	defer {
		if edit_transaction.transaction_is_valid(&transaction) {
			closed, _ := edit_transaction.transaction_close(&transaction)
			assert(closed)
		}
	}
	applied, apply_failure := edit_transaction.transaction_apply_batch(
		&transaction,
		batch[:expansion_count],
	)
	if !applied {
		return {}, false, native_transaction_failure(native.command, apply_failure)
	}
	result_point, point_ok := replace_all_map_offset(
		logical.point_position.byte_offset,
		batch[:expansion_count],
	)
	if !point_ok {
		return {}, false, Failure_Context{code = .Text_Limit, command = native.command}
	}
	target, target_ok, target_failure := edit_transaction.transaction_position(
		&transaction,
		result_point,
	)
	if !target_ok {
		return {}, false, native_transaction_failure(native.command, target_failure)
	}
	view_prepared, view_failure := edit_transaction.transaction_prepare_logical_view(
		&transaction,
		native.view_registry,
		native.view,
		target,
		logical.desired_display_column,
		.Deactivate,
	)
	if !view_prepared {
		return {}, false, native_transaction_failure(native.command, view_failure)
	}
	if native.history_store != nil {
		tracked, track_failure := edit_transaction.transaction_track_history(
			&transaction,
			native.history_store,
			native.history_grouping,
		)
		if !tracked {
			return {}, false, native_transaction_failure(native.command, track_failure)
		}
	}
	if replace_all_cancelled(request) {
		return {}, false, Failure_Context{code = .Cancelled, command = native.command}
	}
	usage.cancellation_checks += 1
	validated, validation_failure := edit_transaction.transaction_validate(&transaction)
	if !validated {
		return {}, false, native_transaction_failure(native.command, validation_failure)
	}
	if replace_all_cancelled(request) {
		_, _ = edit_transaction.transaction_request_cancel(&transaction)
	}
	usage.cancellation_checks += 1
	commit, committed, commit_failure := edit_transaction.transaction_commit(
		&transaction,
		native.commit_observer,
	)
	if !committed {
		if commit_failure.code == .Cancelled {
			return {}, false, Failure_Context{code = .Cancelled, command = native.command}
		}
		return {}, false, native_transaction_failure(native.command, commit_failure)
	}
	finish_committed_view(native, logical.desired_display_column)
	owned_transaction := transaction
	transaction = {}
	return Replace_All_Result {
		native = Native_Result {
			completion = .Buffer_Committed,
			transaction = owned_transaction,
			commit = commit,
		},
		usage = usage,
	}, true, {}
}

@(private)
Occurrence_Progress :: struct {
	present: bool,
	start:   editor.Byte_Offset,
	end:     editor.Byte_Offset,
}

@(private)
replace_all_limits_are_valid :: proc(limits: Replace_All_Limits) -> bool {
	return limits.matches >= MIN_REPLACE_ALL_MATCHES &&
	       limits.matches <= MAX_REPLACE_ALL_MATCHES &&
	       limits.text_bytes >= MIN_REPLACE_ALL_TEXT_BYTES &&
	       limits.text_bytes <= MAX_REPLACE_ALL_TEXT_BYTES &&
	       limits.temporary_bytes >= MIN_REPLACE_ALL_TEMPORARY_BYTES &&
	       limits.temporary_bytes <= MAX_REPLACE_ALL_TEMPORARY_BYTES &&
	       limits.analysis_bytes >= MIN_REPLACE_ALL_ANALYSIS_BYTES &&
	       limits.analysis_bytes <= MAX_REPLACE_ALL_ANALYSIS_BYTES
}

@(private)
replace_all_query_limits :: proc(limits: Replace_All_Limits) -> (search.Limits, bool) {
	query_limits := search.DEFAULT_LIMITS
	query_limits.retained_occurrences = DEFAULT_REPLACE_ALL_TURN_OCCURRENCES
	occurrence_bytes := u64(query_limits.retained_occurrences) * u64(size_of(search.Occurrence))
	capture_bytes, ok := replace_checked_mul(
		u64(query_limits.retained_occurrences) * u64(query_limits.capture_groups),
		u64(size_of(search.Capture)),
	)
	if !ok {
		return {}, false
	}
	arrays, arrays_ok := replace_checked_add(2 * occurrence_bytes, 2 * capture_bytes)
	window := query_limits.scan_window_bytes + query_limits.match_span_bytes
	required, required_ok := replace_checked_add(window, arrays)
	if !arrays_ok || !required_ok {
		return {}, false
	}
	query_limits.temporary_bytes = max(query_limits.temporary_bytes, required)
	if query_limits.temporary_bytes > search.MAX_TEMPORARY_BYTES ||
	   query_limits.temporary_bytes > limits.temporary_bytes {
		return {}, false
	}
	return query_limits, true
}

@(private)
replace_all_array_bytes :: proc(matches: u64) -> (u64, bool) {
	batch_bytes, batch_ok := replace_checked_mul(matches, u64(size_of(edit_transaction.Base_Splice)))
	expansion_bytes, expansion_ok := replace_checked_mul(matches, u64(size_of(search.Replacement_Expansion)))
	if !batch_ok || !expansion_ok {
		return 0, false
	}
	return replace_checked_add(batch_bytes, expansion_bytes)
}

@(private)
replace_all_map_offset :: proc(
	base_offset: editor.Byte_Offset,
	batch: []edit_transaction.Base_Splice,
) -> (editor.Byte_Offset, bool) {
	offset := u64(base_offset)
	base_cursor := u64(0)
	result_cursor := u64(0)
	for splice in batch {
		start := u64(splice.start.byte_offset)
		end := u64(splice.end.byte_offset)
		if offset < start {
			mapped, ok := replace_checked_add(result_cursor, offset - base_cursor)
			return editor.Byte_Offset(mapped), ok
		}
		result_start, start_ok := replace_checked_add(result_cursor, start - base_cursor)
		if !start_ok {
			return 0, false
		}
		inserted := u64(len(splice.replacement))
		if offset == start && start == end {
			return editor.Byte_Offset(result_start), true
		}
		if offset < end {
			return editor.Byte_Offset(result_start), true
		}
		result_end, end_ok := replace_checked_add(result_start, inserted)
		if !end_ok {
			return 0, false
		}
		if offset == end {
			return editor.Byte_Offset(result_end), true
		}
		base_cursor = end
		result_cursor = result_end
	}
	mapped, ok := replace_checked_add(result_cursor, offset - base_cursor)
	return editor.Byte_Offset(mapped), ok
}

@(private)
replace_all_cancelled :: proc(request: Replace_All_Request) -> bool {
	return request.native.cancelled ||
	       search.cancellation_requested(request.cancellation, request.search_generation)
}

@(private)
replace_checked_add :: proc(left, right: u64) -> (u64, bool) {
	if right > max(u64) - left {
		return 0, false
	}
	return left + right, true
}

@(private)
replace_checked_mul :: proc(left, right: u64) -> (u64, bool) {
	if left != 0 && right > max(u64) / left {
		return 0, false
	}
	return left * right, true
}
