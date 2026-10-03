// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package view

import "../editor"
import "../search"
import "core:mem"
import "core:testing"

/* Verifies matched, failed, and aborted turns retain or restore exact view-local state. */
@(test)
search_sessions_publish_failed_suffixes :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	buffer: editor.Buffer
	initialized, _ := editor.buffer_init(
		&buffer,
		301,
		"00 needle 11 needle 22",
		editor.Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, initialized)
	if !initialized {
		mem.tracking_allocator_destroy(&tracking)
		return
	}
	registry: Registry
	registry_ok, _ := registry_init(&registry, 301, allocator)
	testing.expect(t, registry_ok)
	handle, created, _ := create(&registry, &buffer)
	testing.expect(t, created)
	if !registry_ok || !created {
		if registry_ok {
			registry_close(&registry)
		}
		editor.buffer_close(&buffer)
		mem.tracking_allocator_destroy(&tracking)
		return
	}
	origin, _, _ := editor.buffer_position(&buffer, 1)
	viewport, _, _ := editor.buffer_position(&buffer, 0)
	point_set, _ := set_point(&registry, handle, origin)
	viewport_set, _ := set_viewport(&registry, handle, viewport, 3)
	testing.expect(t, point_set && viewport_set)

	query, result, ready := prepare_search_turn(
		t,
		&buffer,
		301,
		"needle",
		1,
		false,
		allocator,
	)
	if !ready {
		close(&registry, &handle)
		registry_close(&registry)
		editor.buffer_close(&buffer)
		mem.tracking_allocator_destroy(&tracking)
		return
	}
	published, publish_failure := search_session_publish(
		&registry,
		handle,
		Search_Update {
			interaction_generation = 1,
			policy_generation = search.Policy_Generation(1),
			direction = .Forward,
			scope = search.Scope{buffer_id = 301, revision = 0, start = 0, end = 22},
		},
		&query,
		&result,
	)
	testing.expectf(t, published, "search publish failed with %v", publish_failure.code)
	testing.expect(t, query.state == nil && result.state == nil)
	matched, matched_ok, _ := snapshot(&registry, handle)
	matched_search, matched_search_ok, _ := search_session_view(&registry, handle)
	testing.expect(t, matched_ok)
	testing.expect(t, matched_search_ok)
	testing.expect(t, matched_search.present && matched_search.has_current)
	testing.expect_value(t, matched_search.status, Search_Status.Active)
	testing.expect_value(t, matched_search.query, "needle")
	testing.expect_value(t, matched_search.last_successful_query, "needle")
	testing.expect_value(t, matched.point_position.byte_offset, editor.Byte_Offset(9))
	presentation_set, presentation_failure := search_session_presentation_set(
		&registry,
		handle,
		.Lines,
	)
	testing.expectf(t, presentation_set, "search presentation failed with %v", presentation_failure.code)
	line_search, line_search_ok, _ := search_session_view(&registry, handle)
	testing.expect(t, line_search_ok)
	if line_search_ok do testing.expect_value(t, line_search.presentation, Search_Presentation.Lines)
	transient, transient_ok, _ := transient_state(&registry, handle)
	testing.expect(t, transient_ok)
	testing.expect(t, transient.search && !transient.query_replacement)

	failed_query, failed_result, failed_ready := prepare_search_turn(
		t,
		&buffer,
		301,
		"missing",
		2,
		true,
		allocator,
	)
	testing.expect(t, failed_ready)
	if failed_ready {
		failed_published, failed_publish_failure := search_session_publish(
			&registry,
			handle,
			Search_Update {
				interaction_generation = 2,
				policy_generation = search.Policy_Generation(1),
				direction = .Forward,
				scope = search.Scope{buffer_id = 301, revision = 0, start = 0, end = 22},
			},
			&failed_query,
			&failed_result,
		)
		testing.expectf(t, failed_published, "failed turn publish failed with %v", failed_publish_failure.code)
	}
	failing, failing_ok, _ := snapshot(&registry, handle)
	failing_search, failing_search_ok, _ := search_session_view(&registry, handle)
	testing.expect(t, failing_ok)
	testing.expect(t, failing_search_ok)
	testing.expect_value(t, failing_search.status, Search_Status.Failing)
	testing.expect_value(t, failing_search.query, "missing")
	testing.expect_value(t, failing_search.last_successful_query, "needle")
	testing.expect(t, failing_search.has_current)
	testing.expect_value(t, failing.point_position.byte_offset, editor.Byte_Offset(9))

	aborted, abort_failure := search_session_abort(&registry, handle)
	testing.expectf(t, aborted, "search abort failed with %v", abort_failure.code)
	settled, settled_ok, _ := transient_state(&registry, handle)
	testing.expect(t, settled_ok)
	testing.expect(t, !settled.search && !settled.query_replacement)
	restored, restored_ok, _ := snapshot(&registry, handle)
	restored_search, restored_search_ok, _ := search_session_view(&registry, handle)
	testing.expect(t, restored_ok)
	testing.expect(t, restored_search_ok && !restored_search.present)
	testing.expect_value(t, restored.point_position.byte_offset, editor.Byte_Offset(1))
	testing.expect_value(t, restored.viewport_origin_position.byte_offset, editor.Byte_Offset(0))
	testing.expect_value(t, restored.horizontal_display_column, u32(3))

	closed, _ := close(&registry, &handle)
	registry_closed, _ := registry_close(&registry)
	buffer_closed, _ := editor.buffer_close(&buffer)
	testing.expect(t, closed && registry_closed && buffer_closed)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&tracking)
}

/* Verifies a changed buffer revision invalidates and cleans transient search state. */
@(test)
search_invalidates_on_external_change :: proc(t: ^testing.T) {
	buffer: editor.Buffer
	initialized, _ := editor.buffer_init(
		&buffer,
		303,
		"needle",
		editor.Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, initialized)
	if !initialized {
		return
	}
	defer editor.buffer_close(&buffer)
	registry: Registry
	registry_ok, _ := registry_init(&registry, 303, context.allocator)
	testing.expect(t, registry_ok)
	handle, created, _ := create(&registry, &buffer)
	testing.expect(t, created)
	if !registry_ok || !created {
		return
	}
	defer {
		close(&registry, &handle)
		registry_close(&registry)
	}
	query, result, ready := prepare_search_turn(t, &buffer, 303, "needle", 1, false, context.allocator)
	testing.expect(t, ready)
	if !ready {
		return
	}
	published, _ := search_session_publish(
		&registry,
		handle,
		Search_Update {
			interaction_generation = 1,
			policy_generation = search.Policy_Generation(1),
			direction = .Forward,
			scope = search.Scope{buffer_id = 303, revision = 0, start = 0, end = 6},
		},
		&query,
		&result,
	)
	testing.expect(t, published)
	start, _, _ := editor.buffer_position(&buffer, 0)
	end, _, _ := editor.buffer_position(&buffer, 1)
	_, _, spliced, _ := editor.buffer_splice(
		&buffer,
		editor.Splice{start = start, end = end, replacement = "N"},
		context.temp_allocator,
	)
	testing.expect(t, spliced)
	current, current_ok, current_failure := snapshot(&registry, handle)
	current_search, current_search_ok, _ := search_session_view(&registry, handle)
	testing.expectf(t, current_ok, "stale cleanup failed with %v", current_failure.code)
	testing.expect(t, current_search_ok && !current_search.present)
	testing.expect_value(t, current.revision, editor.Revision(1))
}

@(private)
prepare_search_turn :: proc(
	t: ^testing.T,
	buffer: ^editor.Buffer,
	buffer_id: editor.Buffer_ID,
	pattern: string,
	generation: search.Search_Generation,
	wrap_already_attempted: bool,
	allocator: mem.Allocator,
) -> (query: search.Query, result: search.Result, ready: bool) {
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
		return {}, {}, false
	}
	snapshot: editor.Buffer_Snapshot
	opened, open_failure := editor.buffer_snapshot_open(buffer, &snapshot)
	testing.expectf(t, opened, "snapshot open failed with %v", open_failure.code)
	if !opened {
		search.query_close(&query)
		return {}, {}, false
	}
	stats, _, _ := editor.buffer_snapshot_stats(&snapshot)
	searched, search_failure := search.literal_search(
		&result,
		&snapshot,
		&query,
		search.Request {
			scope = search.Scope{buffer_id = buffer_id, revision = stats.revision, start = 0, end = editor.Byte_Offset(stats.text_bytes)},
			origin = 0,
			direction = .Forward,
			generation = generation,
			wrap_already_attempted = wrap_already_attempted,
		},
		nil,
		search.Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
	)
	editor.buffer_snapshot_close(&snapshot)
	testing.expectf(t, searched, "literal search failed with %v", search_failure.code)
	if !searched {
		search.query_close(&query)
		return {}, {}, false
	}
	return query, result, true
}
