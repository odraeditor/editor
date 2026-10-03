// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package view

import "../editor"
import "../search"
import "core:mem"
import "core:testing"

/* Verifies progressive state, stale recomputation, counters, finish, and close cleanup. */
@(test)
replacement_sessions_retain_progress :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	buffer: editor.Buffer
	buffer_ok, _ := editor.buffer_init(
		&buffer,
		401,
		"one two one",
		editor.Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, buffer_ok)
	if !buffer_ok {
		mem.tracking_allocator_destroy(&tracking)
		return
	}
	registry: Registry
	registry_ok, _ := registry_init(&registry, 401, allocator)
	handle, view_ok, _ := create(&registry, &buffer)
	testing.expect(t, registry_ok && view_ok)
	if !registry_ok || !view_ok {
		if registry_ok {
			registry_close(&registry)
		}
		editor.buffer_close(&buffer)
		mem.tracking_allocator_destroy(&tracking)
		return
	}

	query, template, result, scope, ready := prepare_query_replacement_turn(
		t,
		&buffer,
		401,
		"one",
		"ONE",
		1,
		0,
		allocator,
	)
	if !ready {
		close(&registry, &handle)
		registry_close(&registry)
		editor.buffer_close(&buffer)
		mem.tracking_allocator_destroy(&tracking)
		return
	}
	published, publish_failure := query_replacement_session_publish(
		&registry,
		handle,
		Query_Replacement_Update {
			interaction_generation = 1,
			policy_generation = search.Policy_Generation(1),
			direction = .Forward,
			scope = scope,
			semantic_group = 7,
			response = .Started,
		},
		&query,
		&template,
		&result,
	)
	testing.expectf(t, published, "initial query replacement publish failed with %v", publish_failure.code)
	testing.expect(t, query.state == nil && template.state == nil && result.state == nil)
	initial, initial_ok, _ := query_replacement_session_view(&registry, handle)
	view_snapshot, snapshot_ok, _ := snapshot(&registry, handle)
	testing.expect(t, initial_ok && snapshot_ok)
	testing.expect(t, initial.present && initial.has_current)
	testing.expect_value(t, initial.status, Query_Replacement_Status.Awaiting_Response)
	testing.expect_value(t, initial.pattern, "one")
	testing.expect_value(t, initial.replacement, "ONE")
	testing.expect_value(t, initial.semantic_group, Query_Replacement_Group_ID(7))
	testing.expect_value(t, initial.replacements, u64(0))
	testing.expect_value(t, initial.skips, u64(0))
	testing.expect_value(t, view_snapshot.point_position.byte_offset, editor.Byte_Offset(3))

	query, template, result, scope, ready = prepare_query_replacement_turn(
		t,
		&buffer,
		401,
		"one",
		"ONE",
		2,
		3,
		allocator,
	)
	testing.expect(t, ready)
	if ready {
		published, publish_failure = query_replacement_session_publish(
			&registry,
			handle,
			Query_Replacement_Update {
				interaction_generation = 2,
				policy_generation = search.Policy_Generation(1),
				direction = .Forward,
				scope = scope,
				semantic_group = 7,
				response = .Skipped,
				skips = 1,
			},
			&query,
			&template,
			&result,
		)
		testing.expectf(t, published, "skip publish failed with %v", publish_failure.code)
	}
	skipped, skipped_ok, _ := query_replacement_session_view(&registry, handle)
	testing.expect(t, skipped_ok && skipped.has_current)
	if skipped_ok && skipped.has_current {
		current := skipped.occurrences[skipped.current_index]
		testing.expect_value(t, current.start, editor.Byte_Offset(8))
		testing.expect_value(t, skipped.skips, u64(1))
	}

	zero, _, _ := editor.buffer_position(&buffer, 0)
	_, _, inserted, _ := editor.buffer_splice(
		&buffer,
		editor.Splice{start = zero, end = zero, replacement = "!"},
		context.temp_allocator,
	)
	testing.expect(t, inserted)
	_, stale_snapshot_ok, stale_snapshot_failure := snapshot(&registry, handle)
	testing.expectf(t, stale_snapshot_ok, "stale snapshot failed with %v", stale_snapshot_failure.code)
	stale, stale_ok, _ := query_replacement_session_view(&registry, handle)
	testing.expect(t, stale_ok && stale.present && !stale.has_current)
	testing.expect_value(t, stale.status, Query_Replacement_Status.Recomputation_Required)
	testing.expect_value(t, stale.source_revision, editor.Revision(0))
	testing.expect_value(t, stale.observed_revision, editor.Revision(1))

	query, template, result, scope, ready = prepare_query_replacement_turn(
		t,
		&buffer,
		401,
		"one",
		"ONE",
		3,
		0,
		allocator,
	)
	testing.expect(t, ready)
	if ready {
		published, publish_failure = query_replacement_session_publish(
			&registry,
			handle,
			Query_Replacement_Update {
				interaction_generation = 3,
				policy_generation = search.Policy_Generation(1),
				direction = .Forward,
				scope = scope,
				semantic_group = 7,
				response = .Recomputed,
				skips = 1,
			},
			&query,
			&template,
			&result,
		)
		testing.expectf(t, published, "recomputation publish failed with %v", publish_failure.code)
	}
	recomputed, recomputed_ok, _ := query_replacement_session_view(&registry, handle)
	testing.expect(t, recomputed_ok && recomputed.has_current)
	testing.expect_value(t, recomputed.source_revision, editor.Revision(1))
	testing.expect_value(t, recomputed.recomputations, u64(1))

	match_start, _, _ := editor.buffer_position(&buffer, 1)
	match_end, _, _ := editor.buffer_position(&buffer, 4)
	_, _, replaced, _ := editor.buffer_splice(
		&buffer,
		editor.Splice{start = match_start, end = match_end, replacement = "ONE"},
		context.temp_allocator,
	)
	testing.expect(t, replaced)
	_, stale_after_replace_ok, _ := snapshot(&registry, handle)
	testing.expect(t, stale_after_replace_ok)
	query, template, result, scope, ready = prepare_query_replacement_turn(
		t,
		&buffer,
		401,
		"one",
		"ONE",
		4,
		4,
		allocator,
	)
	testing.expect(t, ready)
	if ready {
		published, publish_failure = query_replacement_session_publish(
			&registry,
			handle,
			Query_Replacement_Update {
				interaction_generation = 4,
				policy_generation = search.Policy_Generation(1),
				direction = .Forward,
				scope = scope,
				semantic_group = 7,
				response = .Replaced,
				replacements = 1,
				skips = 1,
			},
			&query,
			&template,
			&result,
		)
		testing.expectf(t, published, "replacement publish failed with %v", publish_failure.code)
	}
	continued, continued_ok, _ := query_replacement_session_view(&registry, handle)
	testing.expect(t, continued_ok && continued.has_current)
	testing.expect_value(t, continued.replacements, u64(1))
	testing.expect_value(t, continued.recomputations, u64(2))

	finished, finish_failure := query_replacement_session_finish(&registry, handle)
	testing.expectf(t, finished, "query replacement finish failed with %v", finish_failure.code)
	finished_state, finished_state_ok, _ := query_replacement_session_view(&registry, handle)
	testing.expect(t, finished_state_ok && !finished_state.present)

	query, template, result, scope, ready = prepare_query_replacement_turn(
		t,
		&buffer,
		401,
		"one",
		"ONE",
		5,
		0,
		allocator,
	)
	testing.expect(t, ready)
	if ready {
		published, _ = query_replacement_session_publish(
			&registry,
			handle,
			Query_Replacement_Update {
				interaction_generation = 1,
				policy_generation = search.Policy_Generation(1),
				direction = .Forward,
				scope = scope,
				semantic_group = 8,
				response = .Started,
			},
			&query,
			&template,
			&result,
		)
		testing.expect(t, published)
	}
	closed, _ := close(&registry, &handle)
	registry_closed, _ := registry_close(&registry)
	buffer_closed, _ := editor.buffer_close(&buffer)
	testing.expect(t, closed && registry_closed && buffer_closed)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&tracking)
}

/* Verifies rejected publication preserves all owners and leaves no partial session. */
@(test)
allocation_failure_is_atomic :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	buffer: editor.Buffer
	buffer_ok, _ := editor.buffer_init(
		&buffer,
		403,
		"needle",
		editor.Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
	)
	registry: Registry
	registry_ok, _ := registry_init(&registry, 403, allocator)
	handle, view_ok, _ := create(&registry, &buffer)
	testing.expect(t, buffer_ok && registry_ok && view_ok)
	if !buffer_ok || !registry_ok || !view_ok {
		if registry_ok {
			registry_close(&registry)
		}
		if buffer_ok {
			editor.buffer_close(&buffer)
		}
		mem.tracking_allocator_destroy(&tracking)
		return
	}
	query, template, result, scope, ready := prepare_query_replacement_turn(
		t,
		&buffer,
		403,
		"needle",
		"thread",
		1,
		0,
		allocator,
	)
	testing.expect(t, ready)
	if ready {
		failing := Failing_Allocator{backing = allocator, fail_after = 0}
		registry_data(&registry).allocator = failing_allocator(&failing)
		published, publish_failure := query_replacement_session_publish(
			&registry,
			handle,
			Query_Replacement_Update {
				interaction_generation = 1,
				policy_generation = search.Policy_Generation(1),
				direction = .Forward,
				scope = scope,
				semantic_group = 11,
				response = .Started,
			},
			&query,
			&template,
			&result,
		)
		registry_data(&registry).allocator = allocator
		testing.expect(t, !published)
		testing.expect_value(t, publish_failure.code, Failure_Code.Persistent_Memory_Limit)
		testing.expect(t, query.state != nil && template.state != nil && result.state != nil)
		state, state_ok, _ := query_replacement_session_view(&registry, handle)
		testing.expect(t, state_ok && !state.present)
		search.result_close(&result)
		search.replacement_template_close(&template)
		search.query_close(&query)
	}
	closed, _ := close(&registry, &handle)
	registry_closed, _ := registry_close(&registry)
	buffer_closed, _ := editor.buffer_close(&buffer)
	testing.expect(t, closed && registry_closed && buffer_closed)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&tracking)
}

@(private)
prepare_query_replacement_turn :: proc(
	t: ^testing.T,
	buffer: ^editor.Buffer,
	buffer_id: editor.Buffer_ID,
	pattern: string,
	replacement: string,
	generation: search.Search_Generation,
	origin: editor.Byte_Offset,
	allocator: mem.Allocator,
) -> (
	query: search.Query,
	template: search.Replacement_Template,
	result: search.Result,
	scope: search.Scope,
	ready: bool,
) {
	query_ok, query_failure := search.query_init(
		&query,
		search.Query_Config {
			id = search.Query_ID(generation),
			kind = .Literal,
			pattern = pattern,
			policy = search.DEFAULT_POLICY,
			limits = search.DEFAULT_LIMITS,
			allocator = allocator,
		},
	)
	testing.expectf(t, query_ok, "query init failed with %v", query_failure.code)
	if !query_ok {
		return {}, {}, {}, {}, false
	}
	template_ok, template_failure := search.replacement_template_init(
		&template,
		&query,
		search.Replacement_Template_Config {
			text = replacement,
			policy = search.DEFAULT_REPLACEMENT_POLICY,
			limits = search.DEFAULT_REPLACEMENT_LIMITS,
			allocator = allocator,
		},
	)
	testing.expectf(t, template_ok, "replacement template init failed with %v", template_failure.code)
	if !template_ok {
		search.query_close(&query)
		return {}, {}, {}, {}, false
	}
	buffer_snapshot: editor.Buffer_Snapshot
	opened, open_failure := editor.buffer_snapshot_open(buffer, &buffer_snapshot)
	testing.expectf(t, opened, "snapshot open failed with %v", open_failure.code)
	if !opened {
		search.replacement_template_close(&template)
		search.query_close(&query)
		return {}, {}, {}, {}, false
	}
	stats, _, _ := editor.buffer_snapshot_stats(&buffer_snapshot)
	scope = search.Scope {
		buffer_id = buffer_id,
		revision = stats.revision,
		start = 0,
		end = editor.Byte_Offset(stats.text_bytes),
	}
	searched, search_failure := search.literal_search(
		&result,
		&buffer_snapshot,
		&query,
		search.Request {
			scope = scope,
			origin = origin,
			direction = .Forward,
			generation = generation,
		},
		nil,
		search.Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
	)
	editor.buffer_snapshot_close(&buffer_snapshot)
	testing.expectf(t, searched, "literal search failed with %v", search_failure.code)
	if !searched {
		search.replacement_template_close(&template)
		search.query_close(&query)
		return {}, {}, {}, {}, false
	}
	return query, template, result, scope, true
}
