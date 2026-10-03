// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../editor"
import "../history"
import "../interaction"
import "../search"
import editor_view "../view"
import "core:mem"
import "core:testing"

/* Verifies skip, wrap, confirmed edits, exit, and one semantic undo unit. */
@(test)
query_replace_groups_confirmed_edits :: proc(t: ^testing.T) {
	fixture: Native_Fixture
	if !native_fixture_init(t, &fixture, "one two one", context.allocator) {
		return
	}
	defer native_fixture_close(t, &fixture)
	start, ready := query_replacement_test_request(t, &fixture, "query-replace", .Start)
	if !ready {
		return
	}
	start.pattern = "one"
	start.replacement = "ONE"
	start.pattern_kind = .Literal
	start.direction = .Forward
	start.semantic_group = 71
	result, ok, failure := query_replacement(start)
	testing.expectf(t, ok, "query replacement start failed with %v", failure)
	testing.expect_value(t, result.status, editor_view.Query_Replacement_Status.Awaiting_Response)
	query_replacement_result_close(&result)

	skip, _ := query_replacement_test_request(t, &fixture, "query-replace", .Skip)
	result, ok, failure = query_replacement(skip)
	testing.expectf(t, ok, "query replacement skip failed with %v", failure)
	testing.expect_value(t, result.skips, u64(1))
	query_replacement_result_close(&result)

	replace, _ := query_replacement_test_request(t, &fixture, "query-replace", .Replace)
	result, ok, failure = query_replacement(replace)
	testing.expectf(t, ok, "query replacement edit failed with %v", failure)
	testing.expect_value(t, result.replacements, u64(1))
	testing.expect_value(t, result.native.completion, Native_Completion.Buffer_Committed)
	status := result.status
	query_replacement_result_close(&result)
	for status == .Pending || status == .Wrapped {
		continuation, _ := query_replacement_test_request(
			t,
			&fixture,
			"query-replace",
			.Continue,
		)
		result, ok, failure = query_replacement(continuation)
		testing.expectf(t, ok, "query replacement continuation failed with %v", failure)
		if !ok {
			return
		}
		status = result.status
		query_replacement_result_close(&result)
	}
	testing.expect_value(t, status, editor_view.Query_Replacement_Status.Awaiting_Response)

	last, _ := query_replacement_test_request(
		t,
		&fixture,
		"query-replace",
		.Replace_And_Exit,
	)
	result, ok, failure = query_replacement(last)
	testing.expectf(t, ok, "query replacement final edit failed with %v", failure)
	testing.expect(t, result.finished)
	testing.expect_value(t, result.replacements, u64(2))
	query_replacement_result_close(&result)
	expect_native_state(t, &fixture, 3, 3, 2, "ONE two ONE")
	state, state_ok, _ := editor_view.query_replacement_session_view(
		&fixture.view_registry,
		fixture.view,
	)
	testing.expect(t, state_ok && !state.present)
	history_stats, history_ok, _ := history.store_stats(&fixture.history)
	testing.expect(t, history_ok)
	testing.expect_value(t, history_stats.active_grouping_kind, history.Grouping_Kind.Query_Replacement)
	testing.expect_value(t, history_stats.active_record_count, u64(2))

	undo, undone, undo_failure := execute_named(&fixture, "undo")
	testing.expectf(t, undone, "query replacement undo failed with %v", undo_failure)
	if undone {
		native_result_close(&undo)
	}
	expect_native_state(t, &fixture, 11, 0, 3, "one two one")
}

/* Verifies replace-remaining delegates to one atomic batch and retains undo grouping. */
@(test)
query_replacement_replaces_remaining_atomically :: proc(t: ^testing.T) {
	fixture: Native_Fixture
	if !native_fixture_init(t, &fixture, "one one one", context.allocator) {
		return
	}
	defer native_fixture_close(t, &fixture)
	start, ready := query_replacement_test_request(t, &fixture, "query-replace", .Start)
	if !ready {
		return
	}
	start.pattern = "one"
	start.replacement = "two"
	start.pattern_kind = .Literal
	start.direction = .Forward
	start.semantic_group = 73
	result, ok, failure := query_replacement(start)
	testing.expectf(t, ok, "query replacement start failed with %v", failure)
	query_replacement_result_close(&result)
	remaining, _ := query_replacement_test_request(
		t,
		&fixture,
		"query-replace",
		.Replace_Remaining,
	)
	result, ok, failure = query_replacement(remaining)
	testing.expectf(t, ok, "replace remaining failed with %v", failure)
	testing.expect(t, result.finished)
	testing.expect_value(t, result.replacements, u64(3))
	testing.expect_value(t, len(result.native.commit.splices), 3)
	query_replacement_result_close(&result)
	expect_native_state(t, &fixture, 3, 0, 1, "two two two")

	undo, undone, undo_failure := execute_named(&fixture, "undo")
	testing.expectf(t, undone, "replace remaining undo failed with %v", undo_failure)
	if undone {
		native_result_close(&undo)
	}
	expect_native_state(t, &fixture, 3, 0, 2, "one one one")
}

/* Verifies stale responses and cancellation never mutate canonical text. */
@(test)
query_replace_rejects_stale_turns :: proc(t: ^testing.T) {
	fixture: Native_Fixture
	if !native_fixture_init(t, &fixture, "needle", context.allocator) {
		return
	}
	defer native_fixture_close(t, &fixture)
	start, ready := query_replacement_test_request(t, &fixture, "query-replace", .Start)
	if !ready {
		return
	}
	start.pattern = "needle"
	start.replacement = "thread"
	start.pattern_kind = .Literal
	start.direction = .Forward
	start.semantic_group = 79
	result, ok, failure := query_replacement(start)
	testing.expectf(t, ok, "query replacement start failed with %v", failure)
	query_replacement_result_close(&result)
	zero, _, _ := editor.buffer_position(&fixture.buffer, 0)
	_, _, changed, _ := editor.buffer_splice(
		&fixture.buffer,
		editor.Splice{start = zero, end = zero, replacement = "!"},
		context.temp_allocator,
	)
	testing.expect(t, changed)
	stale, _ := query_replacement_test_request(t, &fixture, "query-replace", .Skip)
	_, ok, failure = query_replacement(stale)
	testing.expect(t, !ok)
	testing.expect_value(t, failure.code, Failure_Code.Search_Failure)
	testing.expect_value(t, failure.search_code, search.Failure_Code.Stale_Revision)
	expect_native_state(t, &fixture, 7, 0, 1, "!needle")
	recompute, _ := query_replacement_test_request(t, &fixture, "query-replace", .Recompute)
	result, ok, failure = query_replacement(recompute)
	testing.expectf(t, ok, "query replacement recomputation failed with %v", failure)
	status := result.status
	query_replacement_result_close(&result)
	if status == .Pending || status == .Wrapped {
		continuation, _ := query_replacement_test_request(
			t,
			&fixture,
			"query-replace",
			.Continue,
		)
		result, ok, failure = query_replacement(continuation)
		testing.expectf(t, ok, "recomputed continuation failed with %v", failure)
		status = result.status
		query_replacement_result_close(&result)
	}
	testing.expect_value(t, status, editor_view.Query_Replacement_Status.Awaiting_Response)
	quit, _ := query_replacement_test_request(t, &fixture, "query-replace", .Cancel)
	result, ok, failure = query_replacement(quit)
	testing.expectf(t, ok, "query replacement cancel failed with %v", failure)
	testing.expect(t, result.finished)
	query_replacement_result_close(&result)

	cancelled_fixture: Native_Fixture
	if !native_fixture_init(t, &cancelled_fixture, "needle", context.allocator) {
		return
	}
	defer native_fixture_close(t, &cancelled_fixture)
	cancelled, cancelled_ready := query_replacement_test_request(
		t,
		&cancelled_fixture,
		"query-replace",
		.Start,
	)
	if !cancelled_ready {
		return
	}
	cancelled.pattern = "needle"
	cancelled.replacement = "thread"
	cancelled.pattern_kind = .Literal
	cancelled.direction = .Forward
	cancelled.semantic_group = 83
	cancellation := search.Cancellation {
		generation = cancelled.search_generation,
		requested = true,
	}
	cancelled.cancellation = &cancellation
	_, ok, failure = query_replacement(cancelled)
	testing.expect(t, !ok)
	testing.expect_value(t, failure.code, Failure_Code.Cancelled)
	expect_native_state(t, &cancelled_fixture, 0, 0, 0, "needle")
}

/* Verifies regexp query replacement expands captures through the same checked path. */
@(test)
query_replacement_expands_regexp_captures :: proc(t: ^testing.T) {
	fixture: Native_Fixture
	if !native_fixture_init(t, &fixture, "one two", context.allocator) {
		return
	}
	defer native_fixture_close(t, &fixture)
	start, ready := query_replacement_test_request(
		t,
		&fixture,
		"query-replace-regexp",
		.Start,
	)
	if !ready {
		return
	}
	start.pattern = "(one)"
	start.replacement = "\\1!"
	start.pattern_kind = .Regular_Expression
	start.direction = .Forward
	start.semantic_group = 89
	result, ok, failure := query_replacement(start)
	testing.expectf(t, ok, "regexp query replacement start failed with %v", failure)
	query_replacement_result_close(&result)
	replace, _ := query_replacement_test_request(
		t,
		&fixture,
		"query-replace-regexp",
		.Replace_And_Exit,
	)
	result, ok, failure = query_replacement(replace)
	testing.expectf(t, ok, "regexp query replacement failed with %v", failure)
	testing.expect(t, result.finished)
	query_replacement_result_close(&result)
	expect_native_state(t, &fixture, 4, 4, 1, "one! two")
}

/* Verifies generated replace/skip sessions retain their model text and undo as one unit. */
@(test)
query_replace_responses_match_model :: proc(t: ^testing.T) {
	expected := [?]string {
		"x x x",
		"y x x",
		"x y x",
		"y y x",
		"x x y",
		"y x y",
		"x y y",
		"y y y",
	}
	for mask in 0 ..< len(expected) {
		fixture: Native_Fixture
		if !native_fixture_init(t, &fixture, "x x x", context.allocator) {
			continue
		}
		start, ready := query_replacement_test_request(t, &fixture, "query-replace", .Start)
		if !ready {
			native_fixture_close(t, &fixture)
			continue
		}
		start.pattern = "x"
		start.replacement = "y"
		start.pattern_kind = .Literal
		start.direction = .Forward
		start.semantic_group = editor_view.Query_Replacement_Group_ID(100 + mask)
		result, ok, failure := query_replacement(start)
		testing.expectf(t, ok, "generated start %d failed with %v", mask, failure)
		if ok {
			query_replacement_result_close(&result)
		}
		replacements: u64
		for index in 0 ..< 3 {
			if !query_replacement_test_await_response(t, &fixture, "query-replace") {
				break
			}
			action := Query_Replacement_Action.Skip
			if (mask & (1 << u32(index))) != 0 {
				action = .Replace
				replacements += 1
			}
			turn, _ := query_replacement_test_request(t, &fixture, "query-replace", action)
			result, ok, failure = query_replacement(turn)
			testing.expectf(t, ok, "generated turn %d/%d failed with %v", mask, index, failure)
			if ok {
				query_replacement_result_close(&result)
			}
		}
		state, state_ok, _ := editor_view.query_replacement_session_view(
			&fixture.view_registry,
			fixture.view,
		)
		testing.expect(t, state_ok)
		if state_ok && state.present {
			quit, _ := query_replacement_test_request(t, &fixture, "query-replace", .Quit)
			result, ok, failure = query_replacement(quit)
			testing.expectf(t, ok, "generated quit %d failed with %v", mask, failure)
			if ok {
				query_replacement_result_close(&result)
			}
		}
		query_replacement_expect_text(t, &fixture.buffer, replacements, expected[mask])
		if replacements > 0 {
			undo, undone, undo_failure := execute_named(&fixture, "undo")
			testing.expectf(t, undone, "generated undo %d failed with %v", mask, undo_failure)
			if undone {
				native_result_close(&undo)
				query_replacement_expect_text(t, &fixture.buffer, replacements + 1, "x x x")
			}
		}
		native_fixture_close(t, &fixture)
	}
}

/* Verifies case shaping, region capture, empty-match progress, wrap, and limits. */
@(test)
query_replacement_covers_policy_and_scope_edges :: proc(t: ^testing.T) {
	case_fixture: Native_Fixture
	if native_fixture_init(t, &case_fixture, "ODRA Odra odra oDra", context.allocator) {
		start, ready := query_replacement_test_request(t, &case_fixture, "query-replace", .Start)
		if ready {
			start.pattern = "odra"
			start.replacement = "river"
			start.pattern_kind = .Literal
			start.direction = .Forward
			start.semantic_group = 201
			result, ok, failure := query_replacement(start)
			testing.expectf(t, ok, "case query start failed with %v", failure)
			if ok {
				query_replacement_result_close(&result)
				remaining, _ := query_replacement_test_request(
					t,
					&case_fixture,
					"query-replace",
					.Replace_Remaining,
				)
				result, ok, failure = query_replacement(remaining)
				testing.expectf(t, ok, "case query replacement failed with %v", failure)
				if ok {
					query_replacement_result_close(&result)
					query_replacement_expect_text(
						t,
						&case_fixture.buffer,
						1,
						"RIVER River river river",
					)
				}
			}
		}
		native_fixture_close(t, &case_fixture)
	}

	region_fixture: Native_Fixture
	if native_fixture_init(t, &region_fixture, "one one one", context.allocator) {
		region_ready := query_replacement_test_set_region(t, &region_fixture, 4, 7)
		start, ready := query_replacement_test_request(t, &region_fixture, "query-replace", .Start)
		if ready && region_ready {
			start.pattern = "one"
			start.replacement = "two"
			start.pattern_kind = .Literal
			start.direction = .Forward
			start.semantic_group = 203
			result, ok, failure := query_replacement(start)
			testing.expectf(t, ok, "region query start failed with %v", failure)
			if ok {
				query_replacement_result_close(&result)
				remaining, _ := query_replacement_test_request(
					t,
					&region_fixture,
					"query-replace",
					.Replace_Remaining,
				)
				result, ok, failure = query_replacement(remaining)
				testing.expectf(t, ok, "region query replacement failed with %v", failure)
				if ok {
					query_replacement_result_close(&result)
					query_replacement_expect_text(t, &region_fixture.buffer, 1, "one two one")
				}
			}
		}
		native_fixture_close(t, &region_fixture)
	}

	empty_fixture: Native_Fixture
	if native_fixture_init(t, &empty_fixture, "bbb", context.allocator) {
		start, ready := query_replacement_test_request(
			t,
			&empty_fixture,
			"query-replace-regexp",
			.Start,
		)
		if ready {
			start.pattern = "a*"
			start.replacement = "x"
			start.pattern_kind = .Regular_Expression
			start.direction = .Forward
			start.semantic_group = 205
			result, ok, failure := query_replacement(start)
			testing.expectf(t, ok, "empty query start failed with %v", failure)
			if ok {
				query_replacement_result_close(&result)
				remaining, _ := query_replacement_test_request(
					t,
					&empty_fixture,
					"query-replace-regexp",
					.Replace_Remaining,
				)
				result, ok, failure = query_replacement(remaining)
				testing.expectf(t, ok, "empty query replacement failed with %v", failure)
				if ok {
					query_replacement_result_close(&result)
					query_replacement_expect_text(t, &empty_fixture.buffer, 1, "xbxbxb")
				}
			}
		}
		native_fixture_close(t, &empty_fixture)
	}

	wrap_fixture: Native_Fixture
	if native_fixture_init(t, &wrap_fixture, "one middle one", context.allocator) {
		end, end_ok, _ := editor.buffer_position(&wrap_fixture.buffer, 14)
		moved, _ := editor_view.move_point(
			&wrap_fixture.view_registry,
			wrap_fixture.view,
			end,
			14,
			.Preserve,
		)
		start, ready := query_replacement_test_request(t, &wrap_fixture, "query-replace", .Start)
		if ready && end_ok && moved {
			start.pattern = "one"
			start.replacement = "two"
			start.pattern_kind = .Literal
			start.direction = .Forward
			start.semantic_group = 207
			result, ok, failure := query_replacement(start)
			testing.expectf(t, ok, "wrapped query start failed with %v", failure)
			if ok {
				testing.expect_value(t, result.status, editor_view.Query_Replacement_Status.Wrapped)
				query_replacement_result_close(&result)
				testing.expect(t, query_replacement_test_await_response(t, &wrap_fixture, "query-replace"))
				quit, _ := query_replacement_test_request(t, &wrap_fixture, "query-replace", .Quit)
				result, ok, failure = query_replacement(quit)
				testing.expectf(t, ok, "wrapped query quit failed with %v", failure)
				if ok do query_replacement_result_close(&result)
			}
		}
		native_fixture_close(t, &wrap_fixture)
	}

	limit_fixture: Native_Fixture
	if native_fixture_init(t, &limit_fixture, "one", context.allocator) {
		start, ready := query_replacement_test_request(t, &limit_fixture, "query-replace", .Start)
		if ready {
			start.pattern = "one"
			start.replacement = "long"
			start.pattern_kind = .Literal
			start.direction = .Forward
			start.semantic_group = 209
			start.replacement_limits.template_bytes = 1
			_, ok, failure := query_replacement(start)
			testing.expect(t, !ok)
			testing.expect_value(t, failure.code, Failure_Code.Search_Failure)
			query_replacement_expect_text(t, &limit_fixture.buffer, 0, "one")
		}
		native_fixture_close(t, &limit_fixture)
	}
}

/* Verifies persistent allocation faults preserve text and release command-owned storage. */
@(test)
query_replace_alloc_faults_are_atomic :: proc(t: ^testing.T) {
	allocation_failures := 0
	allocation_successes := 0
	for fail_after in 0 ..< 16 {
		tracking: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracking, context.allocator)
		fault := Native_Failing_Allocator {
			backing = mem.tracking_allocator(&tracking),
			fail_after = u64(fail_after),
		}
		fixture: Native_Fixture
		if native_fixture_init(t, &fixture, "one one", context.allocator) {
			start, ready := query_replacement_test_request(t, &fixture, "query-replace", .Start)
			if ready {
				start.pattern = "one"
				start.replacement = "two"
				start.pattern_kind = .Literal
				start.direction = .Forward
				start.semantic_group = 301
				start.native.persistent_allocator = native_failing_allocator(&fault)
				result, ok, _ := query_replacement(start)
				if ok {
					allocation_successes += 1
					query_replacement_result_close(&result)
					cancel, _ := query_replacement_test_request(
						t,
						&fixture,
						"query-replace",
						.Cancel,
					)
					result, ok, _ = query_replacement(cancel)
					if ok do query_replacement_result_close(&result)
				} else {
					allocation_failures += 1
				}
				query_replacement_expect_text(t, &fixture.buffer, 0, "one one")
			}
			native_fixture_close(t, &fixture)
		}
		testing.expect_value(t, tracking.current_memory_allocated, i64(0))
		mem.tracking_allocator_destroy(&tracking)
	}
	testing.expect(t, allocation_failures > 0 && allocation_successes > 0)

	publication_failures := 0
	publication_successes := 0
	for fail_after in 0 ..< 48 {
		tracking: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracking, context.allocator)
		fault := Native_Failing_Allocator {
			backing = mem.tracking_allocator(&tracking),
			fail_after = u64(fail_after),
		}
		fixture: Native_Fixture
		if native_fixture_init(t, &fixture, "one one", context.allocator) {
			start, ready := query_replacement_test_request(t, &fixture, "query-replace", .Start)
			if ready {
				start.pattern = "one"
				start.replacement = "two"
				start.pattern_kind = .Literal
				start.direction = .Forward
				start.semantic_group = 303
				result, ok, failure := query_replacement(start)
				testing.expectf(t, ok, "publication fixture start failed with %v", failure)
				if ok {
					query_replacement_result_close(&result)
					replace, _ := query_replacement_test_request(
						t,
						&fixture,
						"query-replace",
						.Replace,
					)
					replace.native.persistent_allocator = native_failing_allocator(&fault)
					result, ok, failure = query_replacement(replace)
					if ok {
						publication_successes += 1
						query_replacement_result_close(&result)
					} else {
						if failure.code == .Publication_Failure {
							publication_failures += 1
						}
						query_replacement_expect_text(t, &fixture.buffer, 0, "one one")
					}
					state, state_ok, _ := editor_view.query_replacement_session_view(
						&fixture.view_registry,
						fixture.view,
					)
					if state_ok && state.present {
						cancel, _ := query_replacement_test_request(
							t,
							&fixture,
							"query-replace",
							.Cancel,
						)
						result, ok, _ = query_replacement(cancel)
						if ok do query_replacement_result_close(&result)
					}
				}
			}
			native_fixture_close(t, &fixture)
		}
		testing.expect_value(t, tracking.current_memory_allocated, i64(0))
		mem.tracking_allocator_destroy(&tracking)
	}
	testing.expect(t, publication_failures > 0 && publication_successes > 0)
}

@(private)
query_replacement_test_request :: proc(
	t: ^testing.T,
	fixture: ^Native_Fixture,
	name: string,
	action: Query_Replacement_Action,
) -> (Query_Replacement_Request, bool) {
	handle, found, lookup_failure := interaction.command_lookup(&fixture.command_registry, name)
	testing.expectf(t, found, "query replacement lookup failed with %v", lookup_failure)
	if !found {
		return {}, false
	}
	native := native_request(fixture, handle)
	native.history_store = &fixture.history
	native.event_sequence = u64(native.transaction_id)
	native.history_grouping = history.Grouping_Context {
		kind = .Independent,
		view_id = fixture.view.view_id,
		view_generation = fixture.view.generation,
		continuity = 1,
		event_sequence = u64(native.transaction_id),
		monotonic_milliseconds = u64(native.transaction_id) * 10,
	}
	identity := u64(native.transaction_id)
	return Query_Replacement_Request {
		native = native,
		action = action,
		query_id = search.Query_ID(identity),
		search_generation = search.Search_Generation(identity),
		policy_generation = search.Policy_Generation(1),
		search_policy = search.DEFAULT_POLICY,
		search_limits = search.DEFAULT_LIMITS,
		replacement_policy = search.DEFAULT_REPLACEMENT_POLICY,
		replace_all_limits = DEFAULT_REPLACE_ALL_LIMITS,
		replacement_limits = search.DEFAULT_REPLACEMENT_LIMITS,
	}, true
}

@(private = "file")
query_replacement_test_await_response :: proc(
	t: ^testing.T,
	fixture: ^Native_Fixture,
	name: string,
) -> bool {
	for _ in 0 ..< 3 {
		state, state_ok, _ := editor_view.query_replacement_session_view(
			&fixture.view_registry,
			fixture.view,
		)
		testing.expect(t, state_ok && state.present)
		if !state_ok || !state.present {
			return false
		}
		if state.status == .Awaiting_Response {
			return true
		}
		if state.status != .Pending && state.status != .Wrapped {
			return false
		}
		continuation, ready := query_replacement_test_request(t, fixture, name, .Continue)
		if !ready {
			return false
		}
		result, ok, failure := query_replacement(continuation)
		testing.expectf(t, ok, "query continuation failed with %v", failure)
		if !ok {
			return false
		}
		query_replacement_result_close(&result)
	}
	return false
}

@(private = "file")
query_replacement_test_set_region :: proc(
	t: ^testing.T,
	fixture: ^Native_Fixture,
	start_offset, end_offset: editor.Byte_Offset,
) -> bool {
	start, start_ok, _ := editor.buffer_position(&fixture.buffer, start_offset)
	end, end_ok, _ := editor.buffer_position(&fixture.buffer, end_offset)
	marked, _ := editor_view.set_mark(&fixture.view_registry, fixture.view, end, true)
	moved, _ := editor_view.move_point(
		&fixture.view_registry,
		fixture.view,
		start,
		u32(start_offset),
		.Preserve,
	)
	testing.expect(t, start_ok && end_ok && marked && moved)
	return start_ok && end_ok && marked && moved
}

@(private = "file")
query_replacement_expect_text :: proc(
	t: ^testing.T,
	buffer: ^editor.Buffer,
	revision: u64,
	expected: string,
) {
	stats, stats_ok, _ := editor.buffer_stats(buffer)
	testing.expect(t, stats_ok)
	if !stats_ok {
		return
	}
	testing.expect_value(t, u64(stats.revision), revision)
	observed := make([]byte, int(stats.text_bytes), context.temp_allocator)
	defer delete(observed, context.temp_allocator)
	_, inspected, _ := editor.buffer_inspect(
		buffer,
		0,
		editor.Byte_Offset(stats.text_bytes),
		observed,
	)
	testing.expect(t, inspected)
	if inspected {
		testing.expect_value(t, string(observed), expected)
	}
}
