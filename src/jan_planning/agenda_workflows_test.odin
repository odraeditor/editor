// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_planning

import "../language"
import "core:testing"

/* Agenda_Workflow_Test_Fixture owns one bounded agenda workflow test graph. */
Agenda_Workflow_Test_Fixture :: struct {
	entries: [3]Agenda_Entry_Candidate,
	sources: [2]Agenda_Source_Candidate,
	index:   Agenda_Index,
	result:  Agenda_Query_Result,
}

/* Verifies agenda movement and reveal remain bound to one immutable result revision. */
@(test)
agenda_workflows_navigate_and_reveal_exact_sources :: proc(t: ^testing.T) {
	fixture: Agenda_Workflow_Test_Fixture
	if !agenda_workflow_test_open(t, &fixture) do return
	defer agenda_workflow_test_close(&fixture)

	position, moved, navigation_failure := agenda_navigation_resolve(&fixture.index, &fixture.result, 0, .Last)
	testing.expectf(t, moved, "last movement failed with %v", navigation_failure.code)
	testing.expect_value(t, position, u32(2))
	position, moved, navigation_failure = agenda_navigation_resolve(&fixture.index, &fixture.result, 0, .Next_Date)
	testing.expectf(t, moved, "date movement failed with %v", navigation_failure.code)
	testing.expect_value(t, position, u32(1))
	position, moved, _ = agenda_navigation_resolve(&fixture.index, &fixture.result, position, .Previous_Date)
	testing.expect(t, moved)
	testing.expect_value(t, position, u32(0))

	reveal, revealed, reveal_failure := agenda_source_reveal(&fixture.index, &fixture.result, 0)
	testing.expectf(t, revealed, "source reveal failed with %v", reveal_failure.code)
	testing.expect_value(t, reveal.index_generation, u64(77))
	testing.expect_value(t, reveal.source_revision, u64(7))
	testing.expect_value(t, resource_identity_text(&reveal.resource), "notes/tasks.org")
	_, revealed, reveal_failure = agenda_source_reveal(&fixture.index, &fixture.result, 2)
	testing.expect(t, !revealed)
	testing.expect_value(t, reveal_failure.code, Failure_Code.Unavailable)
}

/* Verifies remote edits revalidate generations and route only exact document targets. */
@(test)
agenda_workflows_prepare_checked_remote_edits :: proc(t: ^testing.T) {
	fixture: Agenda_Workflow_Test_Fixture
	if !agenda_workflow_test_open(t, &fixture) do return
	defer agenda_workflow_test_close(&fixture)

	request := agenda_workflow_test_edit_request(0, .Task_State)
	plan, prepared, failure := agenda_edit_plan_prepare(&fixture.index, &fixture.result, request)
	testing.expectf(t, prepared, "remote edit failed with %v", failure.code)
	testing.expect_value(t, plan.owner, Agenda_Edit_Owner.Task_Metadata)
	testing.expect_value(t, plan.source_revision, u64(7))
	testing.expect_value(t, u64(plan.target.range.scope.source_revision), u64(7))

	request.operation = .Schedule
	plan, prepared, _ = agenda_edit_plan_prepare(&fixture.index, &fixture.result, request)
	testing.expect(t, prepared)
	testing.expect_value(t, plan.owner, Agenda_Edit_Owner.Time)
	request.operation = .Archive
	plan, prepared, _ = agenda_edit_plan_prepare(&fixture.index, &fixture.result, request)
	testing.expect(t, prepared)
	testing.expect_value(t, plan.owner, Agenda_Edit_Owner.Refile_Archive)
	request.index_generation += 1
	_, prepared, failure = agenda_edit_plan_prepare(&fixture.index, &fixture.result, request)
	testing.expect(t, !prepared)
	testing.expect_value(t, failure.code, Failure_Code.Stale)
	request = agenda_workflow_test_edit_request(2, .Task_State)
	_, prepared, failure = agenda_edit_plan_prepare(&fixture.index, &fixture.result, request)
	testing.expect(t, !prepared)
	testing.expect_value(t, failure.code, Failure_Code.Unavailable)
}

/* Verifies bulk policy validates first and reports committed, rejected, and unattempted rows. */
@(test)
agenda_workflows_apply_explicit_bulk_policy :: proc(t: ^testing.T) {
	fixture: Agenda_Workflow_Test_Fixture
	if !agenda_workflow_test_open(t, &fixture) do return
	defer agenda_workflow_test_close(&fixture)

	requests := [?]Agenda_Edit_Request{
		agenda_workflow_test_edit_request(0, .Priority),
		agenda_workflow_test_edit_request(1, .Priority),
	}
	plans: [2]Agenda_Edit_Plan
	record, prepared, failure := agenda_bulk_plan_prepare(
		&fixture.index, &fixture.result, requests[:], .Best_Effort, plans[:],
	)
	testing.expectf(t, prepared, "bulk prepare failed with %v", failure.code)
	testing.expect_value(t, plans[0].entry_index, u32(0))
	testing.expect_value(t, plans[1].entry_index, u32(1))
	next_record, advanced, advance_failure := agenda_bulk_advance(record, .Target_Committed)
	record = next_record
	testing.expect(t, advanced)
	testing.expect_value(t, advance_failure.code, Failure_Code.None)
	next_record, advanced, advance_failure = agenda_bulk_advance(record, .Target_Rejected)
	record = next_record
	testing.expect(t, advanced)
	testing.expect_value(t, record.state, Agenda_Bulk_State.Partial)
	testing.expect_value(t, record.committed, u32(1))
	testing.expect_value(t, record.rejected, u32(1))
	testing.expect_value(t, advance_failure.code, Failure_Code.Partial)

	atomic, atomic_prepared, _ := agenda_bulk_plan_prepare(
		&fixture.index, &fixture.result, requests[:], .Atomic, plans[:],
	)
	testing.expect(t, atomic_prepared)
	atomic_next, atomic_advanced, atomic_failure := agenda_bulk_advance(atomic, .Target_Rejected)
	atomic = atomic_next
	testing.expect(t, atomic_advanced)
	testing.expect_value(t, atomic.state, Agenda_Bulk_State.Failed)
	testing.expect_value(t, atomic.unattempted, u32(1))
	testing.expect_value(t, atomic_failure.unattempted, u32(1))

	requests[1].index_generation += 1
	plans[0].operation_id = 999
	_, prepared, failure = agenda_bulk_plan_prepare(
		&fixture.index, &fixture.result, requests[:], .Recoverable, plans[:],
	)
	testing.expect(t, !prepared)
	testing.expect_value(t, failure.code, Failure_Code.Stale)
	testing.expect_value(t, plans[0].operation_id, Operation_ID(999))
}

/* Verifies refresh, export, providers, and persistent recovery remain explicit. */
@(test)
agenda_workflows_handoff_and_recovery_are_inspectable :: proc(t: ^testing.T) {
	fixture: Agenda_Workflow_Test_Fixture
	if !agenda_workflow_test_open(t, &fixture) do return
	defer agenda_workflow_test_close(&fixture)

	refresh, prepared, failure := agenda_refresh_prepare({
		operation_id = 91,
		reason = .Command,
		current_index_generation = 77,
		source_set = 31,
		configuration_generation = 23,
		provider_generation = 29,
	})
	testing.expectf(t, prepared, "refresh handoff failed with %v", failure.code)
	testing.expect_value(t, refresh.replaces_index_generation, u64(77))
	_, prepared, failure = agenda_refresh_prepare({
		operation_id = 92,
		reason = .Explicit,
		current_index_generation = 77,
		source_set = 31,
		configuration_generation = 23,
		provider_generation = 29,
		cancel_requested = true,
	})
	testing.expect(t, !prepared)
	testing.expect_value(t, failure.code, Failure_Code.Cancelled)

	export, export_prepared, export_failure := agenda_export_prepare(93, .HTML, &fixture.result)
	testing.expectf(t, export_prepared, "export handoff failed with %v", export_failure.code)
	testing.expect_value(t, export.index_generation, u64(77))
	testing.expect(t, export.complete)
	testing.expect_value(t, export.result_count, u32(3))
	testing.expect(t, agenda_provider_contribution_is_valid({
		identity = "calendar",
		provider_generation = 29,
		kind = .Calendar,
		entry_count = 1,
		available = true,
	}))
	testing.expect(t, !agenda_provider_contribution_is_valid({
		identity = "invalid",
		provider_generation = 29,
		kind = .Document,
		entry_count = 1,
	}))

	bulk := [?]Agenda_Bulk_Record{
		{operation_id = 1, mode = .Best_Effort, state = .Active, target_count = 2, next_target = 1, committed = 1},
		{operation_id = 2, mode = .Recoverable, state = .Recovery_Required, target_count = 2, next_target = 1, committed = 1},
		{},
	}
	clocks: [0]Active_Clock_Record
	refiles: [0]Refile_Publication_Record
	attachments: [0]Attachment_Workflow_Record
	recovery := planning_recovery_inspect(clocks[:], refiles[:], attachments[:], bulk[:])
	testing.expect_value(t, recovery.record_count, u32(3))
	testing.expect_value(t, recovery.valid_records, u32(2))
	testing.expect_value(t, recovery.active_records, u32(1))
	testing.expect_value(t, recovery.recovery_required, u32(1))
	testing.expect_value(t, recovery.malformed_records, u32(1))
}

@(private = "file")
agenda_workflow_test_open :: proc(t: ^testing.T, fixture: ^Agenda_Workflow_Test_Fixture) -> bool {
	fixture^ = {}
	scope := planning_test_scope()
	fixture.entries = {
		{identity = "today", kind = .Document, target = planning_test_target(scope), has_target = true,
			category = "Work", heading_path = "Project / Today", task_state = "TODO",
			timestamp = 1_000, plain_text = "today task"},
		{identity = "tomorrow", kind = .Document, target = planning_test_target(scope), has_target = true,
			category = "Work", heading_path = "Project / Tomorrow", task_state = "TODO",
			timestamp = 90_000, plain_text = "tomorrow task"},
		{identity = "calendar", kind = .Calendar, category = "Calendar",
			heading_path = "Provider / Calendar", timestamp = 100_000,
			plain_text = "calendar task", provider_annotation = "provider"},
	}
	resource, _ := resource_identity_copy(7, "notes/tasks.org")
	provider_resource, _ := resource_identity_copy(8, "calendar/default")
	baseline := language.jan_factory_baseline()
	fixture.sources = {
		{identity = "tasks", kind = .File, state = .Confirmed, resource = resource,
			document_revision = 7, baseline = baseline, configuration_generation = 23,
			provider_generation = 29, document_limit = 8, discovered_documents = 1,
			root_admitted = true, entries = fixture.entries[:2]},
		{identity = "calendar", kind = .Provider, state = .Confirmed, resource = provider_resource,
			durable_version = 4, baseline = baseline, configuration_generation = 23,
			provider_generation = 29, document_limit = 8, discovered_documents = 1,
			root_admitted = true, entries = fixture.entries[2:]},
	}
	_, indexed, index_failure := agenda_index_prepare(&fixture.index, {
		operation_id = 71, generation = 77, source_set = 31,
		configuration_generation = 23, provider_generation = 29,
		sources = fixture.sources[:], entry_limit = 16,
		copied_text_limit = 1_048_576, derived_state_limit = 8_388_608,
	})
	testing.expectf(t, indexed, "workflow index failed with %v", index_failure.code)
	if !indexed do return false
	_, queried, query_failure := agenda_query_prepare(&fixture.result, &fixture.index, {
		operation_id = 72, index_generation = 77, configuration_generation = 23,
		query_dialect = "jan-agenda-v1", kind = .Text, primary = "task",
		sort = []Agenda_Sort_Spec{{key = .Time}}, result_limit = 16,
	})
	testing.expectf(t, queried, "workflow query failed with %v", query_failure.code)
	if !queried {
		agenda_index_close(&fixture.index)
		return false
	}
	return true
}

@(private = "file")
agenda_workflow_test_close :: proc(fixture: ^Agenda_Workflow_Test_Fixture) {
	agenda_query_close(&fixture.result)
	agenda_index_close(&fixture.index)
}

@(private = "file")
agenda_workflow_test_edit_request :: proc(row: u32, operation: Agenda_Edit_Operation) -> Agenda_Edit_Request {
	return {
		operation_id = 81,
		index_generation = 77,
		configuration_generation = 23,
		provider_generation = 29,
		row = row,
		operation = operation,
	}
}
