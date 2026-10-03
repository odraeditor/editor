// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_editing

import "../language"
import "core:mem"
import "core:testing"

/* Verifies every retained rich projection allocation releases exactly. */
@(test)
rich_presentation_allocation_faults_release_state :: proc(t: ^testing.T) {
	source := "* Heading\nText *bold* \\alpha.\n"
	fixture: List_Test_Fixture
	if !list_test_fixture_open(t, &fixture, source, 2_401) do return
	defer list_test_fixture_close(&fixture)
	for fail_after in 0 ..< 4 {
		tracking: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracking, context.allocator)
		failing := Visibility_Test_Failing_Allocator {
			backing = mem.tracking_allocator(&tracking),
			fail_after = u64(fail_after),
		}
		presentation: Rich_Presentation
		_, prepared, failure := rich_presentation_prepare(
			&presentation,
			&fixture.analysis,
			transmute([]u8)source,
			rich_test_request(fixture.scope, u64(len(source))),
			allocator = visibility_test_failing_allocator(&failing),
		)
		testing.expect(t, !prepared)
		testing.expect_value(t, failure.code, Failure_Code.Allocation_Failed)
		testing.expect_value(t, presentation.state, rawptr(nil))
		testing.expect_value(t, tracking.current_memory_allocated, i64(0))
		mem.tracking_allocator_destroy(&tracking)
	}
}

/* Verifies Unicode normalization and stale footnote edits preserve atomicity. */
@(test)
footnote_editing_preserves_unicode_and_rejects_stale_scope :: proc(t: ^testing.T) {
	footnote_test_expect_edit(
		t,
		"Text [fn::Żółw λ].\n",
		"Text [fn:n1].\n[fn:n1] Żółw λ\n",
		.Normalize_Inline,
		.Anonymous_Footnote_Reference,
		0,
		"n1",
		"",
	)
	source := "See [fn:n].\n"
	fixture: List_Test_Fixture
	if !list_test_fixture_open(t, &fixture, source, 2_402) do return
	defer list_test_fixture_close(&fixture)
	request := Footnote_Edit_Request {
		operation_id = 241,
		scope = fixture.scope,
		kind = .Create_Definition,
		rewrite_generation = 241,
		name = "n",
		text = "note",
	}
	request.scope.analysis.source_revision += 1
	plan: language.Jan_Rewrite_Plan
	planned, failure := footnote_edit_plan_prepare(
		&plan,
		&fixture.analysis,
		transmute([]u8)source,
		request,
	)
	testing.expect(t, !planned)
	testing.expect_value(t, failure.code, Failure_Code.Stale)
	testing.expect_value(t, plan.state, rawptr(nil))
}

/* Verifies every local-footnote rewrite allocation can reject without leaking. */
@(test)
footnote_editing_plan_allocation_faults_release_state :: proc(t: ^testing.T) {
	source := "See [fn:n].\n"
	fixture: List_Test_Fixture
	if !list_test_fixture_open(t, &fixture, source, 2_403) do return
	defer list_test_fixture_close(&fixture)
	for fail_after in 0 ..< 4 {
		tracking: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracking, context.allocator)
		failing := Visibility_Test_Failing_Allocator {
			backing = mem.tracking_allocator(&tracking),
			fail_after = u64(fail_after),
		}
		plan: language.Jan_Rewrite_Plan
		request := Footnote_Edit_Request {
			operation_id = Operation_ID(250 + fail_after),
			scope = fixture.scope,
			kind = .Create_Definition,
			rewrite_generation = language.Jan_Rewrite_Generation(250 + fail_after),
			name = "n",
			text = "note",
		}
		planned, failure := footnote_edit_plan_prepare(
			&plan,
			&fixture.analysis,
			transmute([]u8)source,
			request,
			DEFAULT_LIMITS,
			visibility_test_failing_allocator(&failing),
			context.temp_allocator,
		)
		testing.expect(t, !planned)
		testing.expect_value(t, failure.code, Failure_Code.Allocation_Failed)
		testing.expect_value(t, plan.state, rawptr(nil))
		testing.expect_value(t, tracking.current_memory_allocated, i64(0))
		mem.tracking_allocator_destroy(&tracking)
	}
}

/* Verifies cache construction and result-copy faults release all retained bytes. */
@(test)
preview_cache_allocation_faults_release_state :: proc(t: ^testing.T) {
	for fail_after in 0 ..< 2 {
		tracking: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracking, context.allocator)
		failing := Visibility_Test_Failing_Allocator {
			backing = mem.tracking_allocator(&tracking),
			fail_after = u64(fail_after),
		}
		cache: Preview_Cache
		initialized, failure := preview_cache_init(
			&cache,
			Preview_Cache_Generation(20 + fail_after),
			allocator = visibility_test_failing_allocator(&failing),
		)
		testing.expect(t, !initialized)
		testing.expect_value(t, failure.code, Failure_Code.Allocation_Failed)
		testing.expect_value(t, cache.state, rawptr(nil))
		testing.expect_value(t, tracking.current_memory_allocated, i64(0))
		mem.tracking_allocator_destroy(&tracking)
	}

	source := "Formula $x$.\n"
	fixture: List_Test_Fixture
	if !list_test_fixture_open(t, &fixture, source, 2_404) do return
	defer list_test_fixture_close(&fixture)
	target, found := list_test_node(&fixture.analysis, .Latex_Fragment, 0)
	testing.expect(t, found)
	if !found do return
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	failing := Visibility_Test_Failing_Allocator {
		backing = mem.tracking_allocator(&tracking),
		fail_after = 2,
	}
	cache: Preview_Cache
	initialized, _ := preview_cache_init(
		&cache,
		30,
		allocator = visibility_test_failing_allocator(&failing),
	)
	testing.expect(t, initialized)
	if initialized {
		adapter := preview_factory_adapter(.Latex, fixture.scope.provider_generation)
		request := preview_test_request(fixture.scope, target, .Latex, adapter, 30)
		_, begun, _ := preview_request_begin(
			&cache,
			&fixture.analysis,
			transmute([]u8)source,
			request,
		)
		testing.expect(t, begun)
		descriptor, published, failure := preview_result_publish(
			&cache,
			request.request_id,
			fixture.scope,
			adapter.generation,
			0,
			[]u8{1, 2},
		)
		testing.expect(t, !published)
		testing.expect_value(t, failure.code, Failure_Code.Allocation_Failed)
		testing.expect_value(t, descriptor.status, Preview_Status.Source_Fallback)
		preview_cache_close(&cache)
	}
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&tracking)
}

/* Verifies active-view bounds and cancellation publish no new cache entry. */
@(test)
preview_cache_limits_active_requests_and_cancellation :: proc(t: ^testing.T) {
	source := "Formula $x$.\n"
	fixture: List_Test_Fixture
	if !list_test_fixture_open(t, &fixture, source, 2_405) do return
	defer list_test_fixture_close(&fixture)
	target, found := list_test_node(&fixture.analysis, .Latex_Fragment, 0)
	testing.expect(t, found)
	if !found do return
	limits := DEFAULT_LIMITS
	limits.active_previews_per_view = 1
	cache: Preview_Cache
	initialized, _ := preview_cache_init(&cache, 40, limits)
	testing.expect(t, initialized)
	if !initialized do return
	defer preview_cache_close(&cache)
	adapter := preview_factory_adapter(.Latex, fixture.scope.provider_generation)
	request := preview_test_request(fixture.scope, target, .Latex, adapter, 40)
	_, begun, _ := preview_request_begin(&cache, &fixture.analysis, transmute([]u8)source, request)
	testing.expect(t, begun)
	request.request_id = 41
	request.operation_id = 41
	failure: Failure
	_, begun, failure = preview_request_begin(
		&cache,
		&fixture.analysis,
		transmute([]u8)source,
		request,
	)
	testing.expect(t, !begun)
	testing.expect_value(t, failure.code, Failure_Code.Limited)
	cancelled := true
	request.cancel_requested = &cancelled
	_, begun, failure = preview_request_begin(
		&cache,
		&fixture.analysis,
		transmute([]u8)source,
		request,
	)
	testing.expect(t, !begun)
	testing.expect_value(t, failure.code, Failure_Code.Cancelled)
	descriptor, described := preview_cache_descriptor(&cache)
	testing.expect(t, described)
	testing.expect_value(t, descriptor.entries, u32(1))
	testing.expect_value(t, descriptor.active, u32(1))
}
