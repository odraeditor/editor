// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_editing

import "../language"
import "core:mem"
import "core:testing"

/* Verifies formula syntax is inspectable and names the linked computation owner. */
@(test)
table_editing_exposes_formula_presence_without_local_execution :: proc(t: ^testing.T) {
	source := "#+name: data\n| a | b |\n#+TBLFM: $1=$2\n"
	fixture: List_Test_Fixture
	if !list_test_fixture_open(t, &fixture, source, 1_901) do return
	defer list_test_fixture_close(&fixture)
	table, found := list_test_node(&fixture.analysis, .Pipe_Table, 0)
	testing.expect(t, found)
	if !found do return
	status, inspected, failure := table_formula_inspect(
		&fixture.analysis,
		transmute([]u8)source,
		fixture.scope,
		table.id,
	)
	testing.expectf(t, inspected, "formula inspection failed with %v", failure.code)
	testing.expect(t, status.present)
	testing.expect_value(
		t,
		string(transmute([]u8)source[int(status.range.start):int(status.range.end)]),
		"#+TBLFM: $1=$2",
	)
	record := table_future_stage_availability()
	testing.expect_value(t, record.class, language.Jan_Availability_Class.Factory_Native)
	testing.expect_value(t, record.owner, language.Jan_Stage.Computable_Documents)
	testing.expect(t, record.available)
}

/* Verifies malformed, stale, cancelled, and over-limit tables reject atomically. */
@(test)
table_editing_rejects_unsafe_candidates :: proc(t: ^testing.T) {
	malformed_source := "| a | b\n"
	malformed: List_Test_Fixture
	if !list_test_fixture_open(t, &malformed, malformed_source, 1_902) do return
	defer list_test_fixture_close(&malformed)
	table, found := list_test_node(&malformed.analysis, .Pipe_Table, 0)
	testing.expect(t, found)
	if !found do return
	plan: language.Jan_Rewrite_Plan
	request := table_test_request(malformed.scope, .Insert_Row_After, table.id)
	planned, failure := table_edit_plan_prepare(
		&plan,
		&malformed.analysis,
		transmute([]u8)malformed_source,
		request,
	)
	testing.expect(t, !planned)
	testing.expect_value(t, failure.code, Failure_Code.Malformed)

	source := "| a | b |\n| c | d |\n"
	fixture: List_Test_Fixture
	if !list_test_fixture_open(t, &fixture, source, 1_903) do return
	defer list_test_fixture_close(&fixture)
	row, row_found := list_test_node(&fixture.analysis, .Table_Row, 0)
	testing.expect(t, row_found)
	if !row_found do return
	request = table_test_request(fixture.scope, .Insert_Row_After, row.id)
	request.scope.analysis.source_revision += 1
	planned, failure = table_edit_plan_prepare(&plan, &fixture.analysis, transmute([]u8)source, request)
	testing.expect(t, !planned)
	testing.expect_value(t, failure.code, Failure_Code.Stale)

	cancelled := true
	request = table_test_request(fixture.scope, .Insert_Row_After, row.id)
	request.cancel_requested = &cancelled
	planned, failure = table_edit_plan_prepare(&plan, &fixture.analysis, transmute([]u8)source, request)
	testing.expect(t, !planned)
	testing.expect_value(t, failure.code, Failure_Code.Cancelled)

	tiny := DEFAULT_LIMITS
	tiny.table_cells = 3
	request.cancel_requested = nil
	planned, failure = table_edit_plan_prepare(
		&plan,
		&fixture.analysis,
		transmute([]u8)source,
		request,
		tiny,
	)
	testing.expect(t, !planned)
	testing.expect_value(t, failure.code, Failure_Code.Limited)
	testing.expect_value(t, failure.limit, u64(3))
	testing.expect_value(t, failure.actual, u64(4))
}

/* Verifies every retained table copy and presentation allocation releases exactly. */
@(test)
table_editing_retained_allocation_faults_release_state :: proc(t: ^testing.T) {
	source := "| a | b |\n"
	fixture: List_Test_Fixture
	if !list_test_fixture_open(t, &fixture, source, 1_904) do return
	defer list_test_fixture_close(&fixture)
	table, found := list_test_node(&fixture.analysis, .Pipe_Table, 0)
	testing.expect(t, found)
	if !found do return
	for fail_after in 0 ..< 2 {
		tracking: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracking, context.allocator)
		failing := Visibility_Test_Failing_Allocator {
			backing = mem.tracking_allocator(&tracking),
			fail_after = u64(fail_after),
		}
		copy_state: Table_Rectangle_Copy
		_, copied, copy_failure := table_rectangle_copy_prepare(
			&copy_state,
			&fixture.analysis,
			transmute([]u8)source,
			Operation_ID(130 + fail_after),
			fixture.scope,
			table.id,
			{row_start = 0, row_end = 1, column_start = 0, column_end = 2},
			allocator = visibility_test_failing_allocator(&failing),
		)
		testing.expect(t, !copied)
		testing.expect_value(t, copy_failure.code, Failure_Code.Allocation_Failed)
		testing.expect(t, !table_rectangle_copy_is_valid(&copy_state))
		testing.expect_value(t, tracking.current_memory_allocated, i64(0))
		mem.tracking_allocator_destroy(&tracking)
	}

	for fail_after in 0 ..< 2 {
		tracking: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracking, context.allocator)
		failing := Visibility_Test_Failing_Allocator {
			backing = mem.tracking_allocator(&tracking),
			fail_after = u64(fail_after),
		}
		presentation: Table_Presentation
		_, prepared, presentation_failure := table_presentation_prepare(
			&presentation,
			&fixture.analysis,
			transmute([]u8)source,
			{operation_id = Operation_ID(140 + fail_after), scope = fixture.scope, table_id = table.id},
			allocator = visibility_test_failing_allocator(&failing),
		)
		testing.expect(t, !prepared)
		testing.expect_value(t, presentation_failure.code, Failure_Code.Allocation_Failed)
		testing.expect(t, !table_presentation_is_valid(&presentation))
		testing.expect_value(t, tracking.current_memory_allocated, i64(0))
		mem.tracking_allocator_destroy(&tracking)
	}
}

/* Verifies every rewrite-plan allocation can fail without publishing or leaking. */
@(test)
table_editing_plan_allocation_faults_release_state :: proc(t: ^testing.T) {
	source := "| a | b |\n"
	fixture: List_Test_Fixture
	if !list_test_fixture_open(t, &fixture, source, 1_905) do return
	defer list_test_fixture_close(&fixture)
	row, found := list_test_node(&fixture.analysis, .Table_Row, 0)
	testing.expect(t, found)
	if !found do return
	for fail_after in 0 ..< 4 {
		tracking: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracking, context.allocator)
		failing := Visibility_Test_Failing_Allocator {
			backing = mem.tracking_allocator(&tracking),
			fail_after = u64(fail_after),
		}
		plan: language.Jan_Rewrite_Plan
		request := table_test_request(fixture.scope, .Insert_Row_After, row.id)
		planned, failure := table_edit_plan_prepare(
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
