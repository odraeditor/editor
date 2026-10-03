// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package completion

import "core:testing"

/* Verifies active and published inspections expose copied session and resource state. */
@(test)
inspection_reports_active_and_published_state :: proc(t: ^testing.T) {
	registry: Role_Registry
	controller: Controller
	composition, initialized := controller_fixture(&registry, &controller)
	testing.expect(t, initialized)
	if !initialized do return
	defer registry_close(&registry)
	defer controller_close(&controller)

	request := controller_request(301, 1, 3, composition)
	started, _ := controller_start(&controller, 302, 1, request, composition)
	active, inspected, _ := controller_inspect(&controller)
	testing.expect(t, started && inspected)
	testing.expect_value(t, active.state, Session_State.Requesting)
	testing.expect_value(t, active.request.state, Request_State.Prepared)
	testing.expect_value(t, active.query_range, request.query_range)
	testing.expect_value(t, text_view(&active.query), "pri")
	testing.expect_value(t, active.trigger, Trigger_Kind.Explicit)
	testing.expect_value(t, active.current_revision, Document_Revision(3))
	testing.expect_value(t, active.transmitted_revision, Document_Revision(3))
	testing.expect_value(t, active.policy, DEFAULT_SESSION_POLICY)
	testing.expect_value(t, active.projection_generation, Projection_Generation(0))

	_, _ = controller_queue(&controller)
	_, _ = controller_send(&controller)
	first := completion_filter_candidate(303, "pri", provider_order = 0)
	first.availability = .Deprecated
	first.resolved = true
	first.additional_edit_count = 2
	second := completion_filter_candidate(304, "print", provider_order = 1)
	second.additional_edit_count = 1
	duplicate := first
	duplicate.id = 305
	duplicate.provenance.provider_order = 2
	nonmatch := completion_filter_candidate(306, "absent", provider_order = 3)
	items := []Candidate{first, second, duplicate, nonmatch}
	batch := controller_batch(request, items)
	batch.disposition = .Incomplete
	batch.rejected_item_count = 2
	batch.normalization_warning_count = 1
	batch.copied_bytes = 99
	published, publish_failure := controller_publish(&controller, &batch)
	testing.expectf(t, published, "publish failed: %v", publish_failure.code)
	ready, ready_ok, _ := controller_inspect(&controller)
	testing.expect(t, ready_ok)
	testing.expect_value(t, ready.state, Session_State.Ready)
	testing.expect_value(t, ready.batch_id, Batch_ID(91))
	testing.expect_value(t, ready.batch_generation, Batch_Generation(1))
	testing.expect_value(t, ready.projection_generation, Projection_Generation(1))
	testing.expect_value(t, ready.candidate_count, u16(4))
	testing.expect_value(t, ready.filtered_candidate_count, u16(2))
	testing.expect_value(t, ready.deduplicated_candidate_count, u16(1))
	testing.expect_value(t, ready.rejected_candidate_count, u16(2))
	testing.expect_value(t, ready.normalization_warning_count, u16(1))
	testing.expect_value(t, ready.additional_edit_count, u16(5))
	testing.expect_value(t, ready.resolved_candidate_count, u16(2))
	testing.expect_value(t, ready.deprecated_candidate_count, u16(2))
	testing.expect_value(t, ready.match_class_counts, [4]u16{1, 1, 0, 0})
	testing.expect_value(t, ready.selected_candidate, Candidate_ID(303))
	testing.expect(t, ready.selected_resolved)
	testing.expect_value(t, ready.batch_disposition, Batch_Disposition.Incomplete)
	testing.expect_value(t, ready.copied_candidate_bytes, u64(99))
	testing.expect(t, ready.retained_bytes > size_of(Controller_State))
}

/* Verifies incomplete refresh inspection distinguishes retained and transmitted generations. */
@(test)
completion_inspection_reports_incomplete_refresh :: proc(t: ^testing.T) {
	registry: Role_Registry
	controller: Controller
	composition, initialized := controller_fixture(&registry, &controller)
	testing.expect(t, initialized)
	if !initialized do return
	defer registry_close(&registry)
	defer controller_close(&controller)

	request := controller_request(311, 1, 3, composition)
	_, _ = controller_start(&controller, 312, 1, request, composition)
	_, _ = controller_queue(&controller)
	_, _ = controller_send(&controller)
	items := []Candidate{completion_filter_candidate(313, "private")}
	batch := controller_batch(request, items)
	batch.disposition = .Incomplete
	_, _ = controller_publish(&controller, &batch)

	refresh := completion_session_request(request, 314, 2, 4, "priv", .Incomplete)
	action, refined, refine_failure := controller_refine(&controller, refresh)
	testing.expectf(t, refined, "refresh failed: %v", refine_failure.code)
	pending, inspected, _ := controller_inspect(&controller)
	testing.expect(t, inspected)
	testing.expect_value(t, action, Refresh_Action.Provider_Request)
	testing.expect_value(t, pending.state, Session_State.Requesting)
	testing.expect_value(t, pending.request.id, Request_ID(314))
	testing.expect_value(t, pending.request.state, Request_State.Prepared)
	testing.expect_value(t, pending.current_revision, Document_Revision(4))
	testing.expect_value(t, pending.transmitted_revision, Document_Revision(4))
	testing.expect_value(t, text_view(&pending.query), "priv")
	testing.expect_value(t, pending.projection_generation, Projection_Generation(1))
	testing.expect(t, pending.retained_during_refresh)
	testing.expect_value(t, pending.filtered_candidate_count, u16(1))
}

/* Verifies cancelled and stale sessions preserve ordinary diagnostic state. */
@(test)
inspection_reports_cancelled_and_stale_sessions :: proc(t: ^testing.T) {
	registry: Role_Registry
	controller: Controller
	composition, initialized := controller_fixture(&registry, &controller)
	testing.expect(t, initialized)
	if !initialized do return
	defer registry_close(&registry)
	defer controller_close(&controller)

	request := controller_request(321, 1, 3, composition)
	_, _ = controller_start(&controller, 322, 1, request, composition)
	_, _ = controller_queue(&controller)
	_, _ = controller_send(&controller)
	cancelled, _ := controller_cancel(&controller)
	cancelled_state, inspected, _ := controller_inspect(&controller)
	testing.expect(t, cancelled && inspected)
	testing.expect_value(t, cancelled_state.state, Session_State.Dismissed)
	testing.expect_value(t, cancelled_state.request.state, Request_State.Cancelled)
	testing.expect_value(t, cancelled_state.candidate_count, u16(0))
	testing.expect_value(t, cancelled_state.projection_generation, Projection_Generation(0))

	_, _ = controller_retire(&controller)
	request = controller_request(323, 2, 4, composition)
	_, _ = controller_start(&controller, 324, 2, request, composition)
	stale := completion_session_request(request, 325, 3, 5, "other", .Identifier)
	stale.query_range.start -= 1
	stale.query_range.end = stale.query_range.start + 5
	stale.cursor_byte = stale.query_range.end
	action, refined, stale_failure := controller_refine(&controller, stale)
	stale_state, stale_inspected, _ := controller_inspect(&controller)
	testing.expect(t, !refined && stale_inspected)
	testing.expect_value(t, action, Refresh_Action.Dismiss)
	testing.expect_value(t, stale_failure.code, Failure_Code.Stale_Request)
	testing.expect_value(t, stale_state.state, Session_State.Dismissed)
	testing.expect_value(t, stale_state.last_rejection.code, Failure_Code.Stale_Request)
}

/* Verifies empty, failed, and unavailable controller inspections are explicit. */
@(test)
inspection_reports_terminal_states :: proc(t: ^testing.T) {
	registry: Role_Registry
	controller: Controller
	composition, initialized := controller_fixture(&registry, &controller)
	testing.expect(t, initialized)
	if !initialized do return
	defer registry_close(&registry)

	request := controller_request(331, 1, 3, composition)
	_, _ = controller_start(&controller, 332, 1, request, composition)
	_, _ = controller_queue(&controller)
	_, _ = controller_send(&controller)
	empty_batch := controller_batch(request, nil)
	_, _ = controller_publish(&controller, &empty_batch)
	empty, empty_ok, _ := controller_inspect(&controller)
	testing.expect(t, empty_ok)
	testing.expect_value(t, empty.state, Session_State.Empty)
	testing.expect_value(t, empty.filtered_candidate_count, u16(0))

	_, _ = controller_retire(&controller)
	request = controller_request(333, 2, 4, composition)
	_, _ = controller_start(&controller, 334, 2, request, composition)
	_, _ = controller_queue(&controller)
	_, _ = controller_send(&controller)
	failed, reported := controller_fail(&controller, failure(.Publish, .Provider_Unavailable))
	failed_state, failed_ok, _ := controller_inspect(&controller)
	testing.expect(t, failed && failed_ok)
	testing.expect_value(t, reported.operation, Operation.Fail)
	testing.expect_value(t, failed_state.state, Session_State.Failed)
	testing.expect_value(t, failed_state.request.state, Request_State.Failed)
	testing.expect_value(t, failed_state.last_rejection.code, Failure_Code.Provider_Unavailable)

	closed, _ := controller_close(&controller)
	_, available, unavailable := controller_inspect(&controller)
	testing.expect(t, closed && !available)
	testing.expect_value(t, unavailable.code, Failure_Code.Invalid_Controller)
}
