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
import "base:runtime"
import "core:mem"
import "core:testing"

@(private = "file")
REPLACE_GENERATED_SEED :: u64(0x6f6472617265706c)

/* Verifies generated literal batches match a contiguous leftmost oracle exactly. */
@(test)
literal_replace_matches_oracle :: proc(t: ^testing.T) {
	contents := make([dynamic]byte, 0, 4_096)
	defer delete(contents)
	random := REPLACE_GENERATED_SEED
	for index in 0 ..< 1_024 {
		random = replace_test_next(random)
		append(&contents, byte('a' + rune((random >> 9) % 4)))
		if index % 29 == 0 {
			append(&contents, "ab")
		}
	}
	expected := replace_literal_oracle(contents[:], "ab", "XYZ")
	defer delete(expected)
	fixture: Native_Fixture
	if !native_fixture_init(t, &fixture, string(contents[:]), context.allocator) {
		return
	}
	defer native_fixture_close(t, &fixture)
	request, ready := replace_test_request(t, &fixture, .Literal, "ab", "XYZ")
	if !ready {
		return
	}
	request.search_policy = search.Policy{case_mode = .Sensitive, boundary_mode = .Unrestricted, whitespace_mode = .Exact, wrap = false}
	request.replacement_policy = search.Replacement_Policy{case_preservation = .None}
	request.limits.matches = 2_048
	result, replaced, failure := replace_all(request)
	testing.expectf(t, replaced, "generated replacement failed with %v", failure)
	if replaced {
		replace_all_result_close(&result)
		expect_native_state(t, &fixture, 0, 0, 1, string(expected[:]))
	}
}

/* Verifies overlap, smart case shapes, empty matches, and active-region scope. */
@(test)
replace_handles_boundary_cases :: proc(t: ^testing.T) {
	overlap: Native_Fixture
	if native_fixture_init(t, &overlap, "aaaaa", context.allocator) {
		result, replaced, failure := run_replace_all(t, &overlap, .Literal, "aa", "X")
		testing.expectf(t, replaced, "overlap replacement failed with %v", failure)
		if replaced {
			replace_all_result_close(&result)
			expect_native_state(t, &overlap, 0, 0, 1, "XXa")
		}
		native_fixture_close(t, &overlap)
	}

	case_shapes: Native_Fixture
	if native_fixture_init(t, &case_shapes, "ODRA Odra odra oDra", context.allocator) {
		result, replaced, failure := run_replace_all(t, &case_shapes, .Literal, "odra", "river")
		testing.expectf(t, replaced, "case replacement failed with %v", failure)
		if replaced {
			replace_all_result_close(&result)
			expect_native_state(t, &case_shapes, 0, 0, 1, "RIVER River river river")
		}
		native_fixture_close(t, &case_shapes)
	}

	empty: Native_Fixture
	if native_fixture_init(t, &empty, "bbb", context.allocator) {
		result, replaced, failure := run_replace_all(t, &empty, .Regular_Expression, "a*", "x")
		testing.expectf(t, replaced, "empty regexp replacement failed with %v", failure)
		if replaced {
			replace_all_result_close(&result)
			expect_native_state(t, &empty, 0, 0, 1, "xbxbxb")
		}
		native_fixture_close(t, &empty)
	}

	region: Native_Fixture
	if native_fixture_init(t, &region, "one one one", context.allocator) {
		if replace_test_set_region(t, &region, 4, 7) {
			result, replaced, failure := run_replace_all(t, &region, .Literal, "one", "two")
			testing.expectf(t, replaced, "region replacement failed with %v", failure)
			if replaced {
				replace_all_result_close(&result)
				expect_native_state(t, &region, 7, 7, 1, "one two one")
			}
		}
		native_fixture_close(t, &region)
	}
}

/* Verifies one replace-all remains one reversible unit through undo and redo. */
@(test)
replace_all_round_trips_as_one_history_unit :: proc(t: ^testing.T) {
	fixture: Native_Fixture
	if !native_fixture_init(t, &fixture, "one two one", context.allocator) {
		return
	}
	defer native_fixture_close(t, &fixture)
	result, replaced, failure := run_replace_all(t, &fixture, .Literal, "one", "three")
	testing.expectf(t, replaced, "replace-all failed with %v", failure)
	if !replaced {
		return
	}
	replace_all_result_close(&result)
	undo, undone, undo_failure := execute_named(&fixture, "undo")
	testing.expectf(t, undone, "undo failed with %v", undo_failure)
	if undone {
		native_result_close(&undo)
		expect_native_state(t, &fixture, 0, 0, 2, "one two one")
	}
	redo, redone, redo_failure := execute_named(&fixture, "redo")
	testing.expectf(t, redone, "redo failed with %v", redo_failure)
	if redone {
		native_result_close(&redo)
		expect_native_state(t, &fixture, 0, 0, 3, "three two three")
	}
}

/* Verifies large candidate sets and command limits reject without publication. */
@(test)
replace_all_scale_and_resource_limits_roll_back :: proc(t: ^testing.T) {
	contents := make([]byte, 1_000_000)
	for &value in contents {
		value = 'a'
	}
	fixture: Native_Fixture
	if !native_fixture_init(t, &fixture, string(contents), context.allocator) {
		delete(contents)
		return
	}
	scale_request, ready := replace_test_request(t, &fixture, .Literal, "a", "b")
	if ready {
		scale_request.limits.matches = 64
		_, replaced, failure := replace_all(scale_request)
		testing.expect(t, !replaced)
		testing.expect_value(t, failure.code, Failure_Code.Search_Failure)
		testing.expect_value(t, failure.search_code, search.Failure_Code.Work_Limit)
		replace_expect_buffer(t, &fixture.buffer, 0, string(contents))
	}
	native_fixture_close(t, &fixture)
	delete(contents)

	large_replacement := make([]byte, 40_000)
	for &value in large_replacement {
		value = 'x'
	}
	history_limited: Native_Fixture
	if native_fixture_init(t, &history_limited, "aa", context.allocator) {
		policy_snapshot, inspected, _ := history.store_policy_inspect(&history_limited.history)
		testing.expect(t, inspected)
		if inspected {
			policy := policy_snapshot.policy
			policy.payload_bytes_per_unit = history.MIN_PAYLOAD_BYTES_PER_UNIT
			_, configured, configure_failure := history.store_policy_replace(
				&history_limited.history,
				history.Policy_Replacement_Request {
					expected_generation = policy_snapshot.policy_generation,
					policy = policy,
					operation_limit = policy.pruning_operations,
				},
			)
			testing.expectf(t, configured, "history policy setup failed with %v", configure_failure)
			if configured {
				history_request, request_ready := replace_test_request(
					t,
					&history_limited,
					.Literal,
					"a",
					string(large_replacement),
				)
				if request_ready {
					history_request.limits.matches = 4
					history_request.limits.text_bytes = 128 * 1_024
					history_request.replacement_limits.template_bytes = 64 * 1_024
					history_request.replacement_limits.expanded_bytes = 64 * 1_024
					_, replaced, failure := replace_all(history_request)
					testing.expect(t, !replaced)
					testing.expect_value(t, failure.code, Failure_Code.Publication_Failure)
					testing.expect_value(t, failure.transaction_code, edit_transaction.Failure_Code.History_Failure)
					replace_expect_buffer(t, &history_limited.buffer, 0, "aa")
				}
			}
		}
		native_fixture_close(t, &history_limited)
	}
	delete(large_replacement)
}

/* Verifies persistent and temporary allocator faults leave no command-owned storage. */
@(test)
replace_alloc_faults_are_atomic :: proc(t: ^testing.T) {
	for fail_after in 0 ..< 12 {
		tracking: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracking, context.allocator)
		fault := Native_Failing_Allocator {
			backing = mem.tracking_allocator(&tracking),
			fail_after = u64(fail_after),
		}
		fixture: Native_Fixture
		if native_fixture_init(t, &fixture, "one one", context.allocator) {
			request, ready := replace_test_request(t, &fixture, .Literal, "one", "two")
			if ready {
				request.native.persistent_allocator = native_failing_allocator(&fault)
				result, replaced, _ := replace_all(request)
				if replaced {
					replace_all_result_close(&result)
				} else {
					replace_expect_buffer(t, &fixture.buffer, 0, "one one")
				}
			}
			native_fixture_close(t, &fixture)
		}
		testing.expect_value(t, tracking.current_memory_allocated, i64(0))
		mem.tracking_allocator_destroy(&tracking)
	}

	for fail_after in 0 ..< 8 {
		tracking: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracking, context.allocator)
		fault := Native_Failing_Allocator {
			backing = mem.tracking_allocator(&tracking),
			fail_after = u64(fail_after),
		}
		fixture: Native_Fixture
		if native_fixture_init(t, &fixture, "one one", context.allocator) {
			request, ready := replace_test_request(t, &fixture, .Literal, "one", "two")
			if ready {
				request.native.temporary_allocator = native_failing_allocator(&fault)
				result, replaced, _ := replace_all(request)
				if replaced {
					replace_all_result_close(&result)
				} else {
					replace_expect_buffer(t, &fixture.buffer, 0, "one one")
				}
			}
			native_fixture_close(t, &fixture)
		}
		testing.expect_value(t, tracking.current_memory_allocated, i64(0))
		mem.tracking_allocator_destroy(&tracking)
	}
}

/* Verifies an external revision conflict and in-flight cancellation stop publication. */
@(test)
replace_revalidates_stale_state :: proc(t: ^testing.T) {
	stale: Native_Fixture
	if native_fixture_init(t, &stale, "one one", context.allocator) {
		intervention := Replace_Test_Allocator {
			backing = context.temp_allocator,
			buffer = &stale.buffer,
			mode = .Mutate,
			trigger_after = 0,
		}
		request, ready := replace_test_request(t, &stale, .Literal, "one", "two")
		if ready {
			request.native.temporary_allocator = replace_test_allocator(&intervention)
			_, replaced, failure := replace_all(request)
			testing.expect(t, !replaced)
			testing.expect_value(t, failure.code, Failure_Code.Search_Failure)
			testing.expect_value(t, failure.search_code, search.Failure_Code.Stale_Revision)
			testing.expect(t, intervention.triggered)
			replace_expect_buffer(t, &stale.buffer, 1, "!one one")
		}
		native_fixture_close(t, &stale)
	}

	cancelled: Native_Fixture
	if native_fixture_init(t, &cancelled, "one one", context.allocator) {
		cancellation: search.Cancellation
		_, _ = search.cancellation_reset(&cancellation, 71)
		intervention := Replace_Test_Allocator {
			backing = context.temp_allocator,
			cancellation = &cancellation,
			generation = 71,
			mode = .Cancel,
			trigger_after = 0,
		}
		request, ready := replace_test_request(t, &cancelled, .Literal, "one", "two")
		if ready {
			request.query_id = 71
			request.search_generation = 71
			request.cancellation = &cancellation
			request.native.temporary_allocator = replace_test_allocator(&intervention)
			_, replaced, failure := replace_all(request)
			testing.expect(t, !replaced)
			testing.expect_value(t, failure.code, Failure_Code.Cancelled)
			testing.expect(t, intervention.triggered)
			replace_expect_buffer(t, &cancelled.buffer, 0, "one one")
		}
		native_fixture_close(t, &cancelled)
	}
}

@(private = "file")
Replace_Test_Intervention :: enum u8 {
	None,
	Mutate,
	Cancel,
}

@(private = "file")
Replace_Test_Allocator :: struct {
	backing:       runtime.Allocator,
	buffer:        ^editor.Buffer,
	cancellation:  ^search.Cancellation,
	generation:    search.Search_Generation,
	mode:          Replace_Test_Intervention,
	trigger_after: u64,
	allocations:   u64,
	triggered:     bool,
}

@(private = "file")
replace_test_request :: proc(
	t: ^testing.T,
	fixture: ^Native_Fixture,
	kind: search.Pattern_Kind,
	pattern, replacement: string,
) -> (Replace_All_Request, bool) {
	name := "replace-string"
	if kind == .Regular_Expression {
		name = "replace-regexp"
	}
	handle, found, failure := interaction.command_lookup(&fixture.command_registry, name)
	testing.expectf(t, found, "replace command lookup failed with %v", failure)
	if !found {
		return {}, false
	}
	native := native_request(fixture, handle)
	native.history_store = &fixture.history
	native.history_grouping = history.Grouping_Context{kind = .Independent}
	identity := u64(native.transaction_id)
	return Replace_All_Request {
		native = native,
		pattern = pattern,
		replacement = replacement,
		pattern_kind = kind,
		search_policy = search.DEFAULT_POLICY,
		replacement_policy = search.DEFAULT_REPLACEMENT_POLICY,
		query_id = search.Query_ID(identity),
		search_generation = search.Search_Generation(identity),
		limits = DEFAULT_REPLACE_ALL_LIMITS,
		replacement_limits = search.DEFAULT_REPLACEMENT_LIMITS,
	}, true
}

@(private = "file")
replace_literal_oracle :: proc(source: []byte, pattern, replacement: string) -> [dynamic]byte {
	result := make([dynamic]byte, 0, len(source) + len(replacement))
	index := 0
	pattern_bytes := transmute([]byte)pattern
	replacement_bytes := transmute([]byte)replacement
	for index < len(source) {
		matched := index + len(pattern_bytes) <= len(source) &&
		           string(source[index:index + len(pattern_bytes)]) == pattern
		if matched {
			append(&result, ..replacement_bytes)
			index += len(pattern_bytes)
		} else {
			append(&result, source[index])
			index += 1
		}
	}
	return result
}

@(private = "file")
replace_test_next :: proc(state: u64) -> u64 {
	value := state
	value ~= value << 13
	value ~= value >> 7
	value ~= value << 17
	return value
}

@(private = "file")
replace_test_set_region :: proc(
	t: ^testing.T,
	fixture: ^Native_Fixture,
	start, end: int,
) -> bool {
	start_position, start_ok, _ := editor.buffer_position(&fixture.buffer, editor.Byte_Offset(start))
	end_position, end_ok, _ := editor.buffer_position(&fixture.buffer, editor.Byte_Offset(end))
	marked, _ := editor_view.set_mark(&fixture.view_registry, fixture.view, start_position, true)
	moved, _ := editor_view.move_point(
		&fixture.view_registry,
		fixture.view,
		end_position,
		u32(end),
		.Preserve,
	)
	testing.expect(t, start_ok && end_ok && marked && moved)
	return start_ok && end_ok && marked && moved
}

@(private = "file")
replace_expect_buffer :: proc(
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
	testing.expect_value(t, string(observed), expected)
}

@(private = "file")
replace_test_allocator :: proc(data: ^Replace_Test_Allocator) -> runtime.Allocator {
	return runtime.Allocator{procedure = replace_test_allocator_proc, data = data}
}

@(private = "file")
replace_test_allocator_proc :: proc(
	allocator_data: rawptr,
	mode: runtime.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	location := #caller_location,
) -> (result: []byte, error: runtime.Allocator_Error) {
	allocator := (^Replace_Test_Allocator)(allocator_data)
	if !allocator.triggered &&
	   (mode == .Alloc || mode == .Alloc_Non_Zeroed || mode == .Resize || mode == .Resize_Non_Zeroed) {
		if allocator.allocations >= allocator.trigger_after {
			allocator.triggered = true
			switch allocator.mode {
			case .Mutate:
				start, start_ok, _ := editor.buffer_position(allocator.buffer, 0)
				if start_ok {
					_, _, _, _ = editor.buffer_splice(
						allocator.buffer,
						editor.Splice{start = start, end = start, replacement = "!"},
						context.temp_allocator,
					)
				}
			case .Cancel:
				_ = search.cancellation_request(allocator.cancellation, allocator.generation)
			case .None:
			}
		}
		allocator.allocations += 1
	}
	return allocator.backing.procedure(
		allocator.backing.data,
		mode,
		size,
		alignment,
		old_memory,
		old_size,
		location,
	)
}
