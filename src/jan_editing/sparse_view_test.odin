// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_editing

import "../editor"
import "../language"
import "core:mem"
import "core:testing"

/* Verifies structural, textual, and indexed predicates include minimum ancestors. */
@(test)
sparse_views_derive_matches_with_ancestor_context :: proc(t: ^testing.T) {
	source := string(
		"* Parent :project:\n" +
		"body\n" +
		"** Alpha\n" +
		"text\n" +
		"*** Deep Needle\n" +
		"detail\n" +
		"** Beta\n" +
		"#+begin_quote\nquoted\n#+end_quote\n",
	)
	fixture: Sparse_Test_Fixture
	if !sparse_test_fixture_open(t, &fixture, source, 1001, 0, 1) do return
	defer sparse_test_fixture_close(&fixture)

	textual := sparse_test_prepare(t, &fixture, {
		kind = .Text_Contains,
		text = "Needle",
	})
	if textual.state != nil {
		defer sparse_view_close(&textual)
		descriptor, described := sparse_view_descriptor(&textual)
		testing.expect(t, described)
		testing.expect_value(t, descriptor.match_count, u32(3))
		testing.expect_value(t, descriptor.direct_matches, u32(1))
		matches := sparse_view_matches(&textual)
		testing.expect(t, matches[0].ancestor_context)
		testing.expect(t, matches[1].ancestor_context)
		testing.expect(t, matches[2].direct_match)
	}

	levels := sparse_test_prepare(t, &fixture, {
		kind = .Heading_Level,
		heading_level = 2,
	})
	if levels.state != nil {
		defer sparse_view_close(&levels)
		descriptor, _ := sparse_view_descriptor(&levels)
		testing.expect_value(t, descriptor.match_count, u32(3))
		testing.expect_value(t, descriptor.direct_matches, u32(2))
	}

	blocks := sparse_test_prepare(t, &fixture, {
		kind = .Node_Kind,
		node_kind = .Quote_Block,
	})
	if blocks.state != nil {
		defer sparse_view_close(&blocks)
		descriptor, _ := sparse_view_descriptor(&blocks)
		testing.expect_value(t, descriptor.match_count, u32(2))
		testing.expect_value(t, descriptor.direct_matches, u32(1))
	}

	indexed := sparse_test_prepare(t, &fixture, {
		kind = .Indexed_Fact,
		index_kind = .Tag,
	})
	if indexed.state != nil {
		defer sparse_view_close(&indexed)
		descriptor, _ := sparse_view_descriptor(&indexed)
		testing.expect_value(t, descriptor.direct_matches, u32(1))
	}
}

/* Verifies refresh replaces one generation and source navigation rejects stale scope. */
@(test)
sparse_views_refresh_and_navigate_exact_source :: proc(t: ^testing.T) {
	first: Sparse_Test_Fixture
	if !sparse_test_fixture_open(t, &first, "* Parent\n** Needle\n", 1002, 0, 1) do return
	defer sparse_test_fixture_close(&first)
	sparse := sparse_test_prepare(t, &first, {kind = .Text_Contains, text = "Needle"})
	if sparse.state == nil do return
	defer sparse_view_close(&sparse)

	result, resolved, failure := sparse_view_resolve_source(&sparse, first.scope, 1)
	testing.expectf(t, resolved, "source navigation failed with %v", failure.code)
	testing.expect_value(t, result.status, Navigation_Status.Resolved)
	testing.expect(t, result.position.byte_offset > 0)
	stale := first.scope
	stale.analysis.source_revision += 1
	_, resolved, failure = sparse_view_resolve_source(&sparse, stale, 0)
	testing.expect(t, !resolved)
	testing.expect_value(t, failure.code, Failure_Code.Stale)

	second: Sparse_Test_Fixture
	if !sparse_test_fixture_open(
		t,
		&second,
		"* Parent\n** Needle\n** Another Needle\n",
		1002,
		1,
		2,
	) {
		return
	}
	defer sparse_test_fixture_close(&second)
	descriptor: Sparse_View_Descriptor
	refreshed: bool
	descriptor, refreshed, failure = sparse_view_refresh(
		&sparse,
		&second.analysis,
		transmute([]u8)second.source,
		second.scope,
		2,
	)
	testing.expectf(t, refreshed, "refresh failed with %v", failure.code)
	testing.expect_value(t, descriptor.generation, Sparse_Generation(2))
	testing.expect_value(t, descriptor.direct_matches, u32(2))
	testing.expect_value(t, descriptor.match_count, u32(3))
}

/* Verifies malformed, cancelled, limited, and allocation failures publish no sparse state. */
@(test)
sparse_views_contain_failures_and_release_ownership :: proc(t: ^testing.T) {
	malformed: Sparse_Test_Fixture
	if !sparse_test_fixture_open(
		t,
		&malformed,
		"* Parent\n#+begin_unterminated\nbody\n",
		1003,
		0,
		1,
	) {
		return
	}
	defer sparse_test_fixture_close(&malformed)
	sparse: Sparse_View
	_, prepared, failure := sparse_view_prepare(
		&sparse,
		&malformed.analysis,
		transmute([]u8)malformed.source,
		sparse_test_request(malformed.scope, {kind = .Heading_Level, heading_level = 1}),
	)
	testing.expect(t, !prepared)
	testing.expect_value(t, failure.code, Failure_Code.Malformed)

	clean: Sparse_Test_Fixture
	if !sparse_test_fixture_open(t, &clean, "* Parent\n** Child\n", 1004, 0, 1) do return
	defer sparse_test_fixture_close(&clean)
	cancelled := true
	request := sparse_test_request(clean.scope, {kind = .Heading_Level, heading_level = 2})
	request.cancel_requested = &cancelled
	_, prepared, failure = sparse_view_prepare(
		&sparse,
		&clean.analysis,
		transmute([]u8)clean.source,
		request,
	)
	testing.expect(t, !prepared)
	testing.expect_value(t, failure.code, Failure_Code.Cancelled)

	limits := DEFAULT_LIMITS
	limits.sparse_matches = 1
	request.cancel_requested = nil
	_, prepared, failure = sparse_view_prepare(
		&sparse,
		&clean.analysis,
		transmute([]u8)clean.source,
		request,
		limits,
	)
	testing.expect(t, !prepared)
	testing.expect_value(t, failure.code, Failure_Code.Limited)

	for fail_after in 0 ..< 3 {
		tracking: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracking, context.allocator)
		failing := Visibility_Test_Failing_Allocator {
			backing = mem.tracking_allocator(&tracking),
			fail_after = u64(fail_after),
		}
		request = sparse_test_request(clean.scope, {kind = .Text_Contains, text = "Child"})
		_, prepared, failure = sparse_view_prepare(
			&sparse,
			&clean.analysis,
			transmute([]u8)clean.source,
			request,
			allocator = visibility_test_failing_allocator(&failing),
		)
		testing.expect(t, !prepared)
		testing.expect_value(t, failure.code, Failure_Code.Allocation_Failed)
		testing.expect(t, sparse.state == nil)
		testing.expect_value(t, tracking.current_memory_allocated, i64(0))
		mem.tracking_allocator_destroy(&tracking)
	}

	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	owned: Sparse_View
	request = sparse_test_request(clean.scope, {kind = .Text_Contains, text = "Child"})
	_, prepared, failure = sparse_view_prepare(
		&owned,
		&clean.analysis,
		transmute([]u8)clean.source,
		request,
		allocator = mem.tracking_allocator(&tracking),
	)
	testing.expectf(t, prepared, "tracked sparse view failed with %v", failure.code)
	sparse_view_close(&owned)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&tracking)
}

@(private = "file")
Sparse_Test_Fixture :: struct {
	owner:    language.Jan_Structural_Owner,
	analysis: language.Jan_Structural_Analysis,
	scope:    Scope,
	source:   string,
}

@(private = "file")
sparse_test_fixture_open :: proc(
	t: ^testing.T,
	fixture: ^Sparse_Test_Fixture,
	source: string,
	buffer_id: u64,
	revision: editor.Revision,
	analysis_generation: language.Jan_Analysis_Generation,
) -> bool {
	fixture.source = source
	fixture.scope = editing_test_scope(editor.Buffer_ID(buffer_id), revision)
	fixture.scope.analysis.configuration = language.jan_factory_configuration(1).identity
	fixture.scope.analysis.analysis_generation = analysis_generation
	initialized, failure := language.jan_structural_owner_init(&fixture.owner, 1)
	analyzed := false
	if initialized {
		fixture.analysis, analyzed, failure = language.jan_structural_owner_analyze(
			&fixture.owner,
			transmute([]u8)source,
			fixture.scope.analysis,
		)
	}
	testing.expectf(t, initialized && analyzed, "sparse fixture failed with %v", failure.code)
	return initialized && analyzed
}

@(private = "file")
sparse_test_fixture_close :: proc(fixture: ^Sparse_Test_Fixture) {
	language.jan_structural_analysis_close(&fixture.analysis)
	language.jan_structural_owner_close(&fixture.owner)
}

@(private = "file")
sparse_test_request :: proc(scope: Scope, predicate: Sparse_Predicate) -> Sparse_View_Request {
	return {
		operation_id = 51,
		generation = 1,
		scope = scope,
		predicate = predicate,
	}
}

@(private = "file")
sparse_test_prepare :: proc(
	t: ^testing.T,
	fixture: ^Sparse_Test_Fixture,
	predicate: Sparse_Predicate,
) -> Sparse_View {
	sparse: Sparse_View
	_, prepared, failure := sparse_view_prepare(
		&sparse,
		&fixture.analysis,
		transmute([]u8)fixture.source,
		sparse_test_request(fixture.scope, predicate),
	)
	testing.expectf(t, prepared, "sparse preparation failed with %v", failure.code)
	return sparse
}
