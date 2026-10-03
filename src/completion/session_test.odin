// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package completion

import "core:testing"

@(private)
completion_session_request :: proc(
	request: Request,
	id, generation, revision: u64,
	query_text: string,
	trigger: Trigger_Kind,
) -> Request {
	query, _ := text_copy(query_text)
	result := request
	result.id = Request_ID(id)
	result.generation = Request_Generation(generation)
	result.scope.document_revision = Document_Revision(revision)
	result.scope.transmitted_revision = Document_Revision(revision)
	result.query_range.end = result.query_range.start + u64(len(query_text))
	result.cursor_byte = result.query_range.end
	result.query = query
	result.trigger = trigger
	result.trigger_character = {}
	result.state = .Prepared
	return result
}

/* Verifies identifier invocation is opt-in and retains its prefix threshold. */
@(test)
session_enforces_factory_identifier_prefix :: proc(t: ^testing.T) {
	registry: Role_Registry
	controller: Controller
	policy := DEFAULT_SESSION_POLICY
	policy.identifier_enabled = true
	composition, initialized := controller_fixture(&registry, &controller, policy = policy)
	testing.expect(t, initialized)
	if !initialized do return
	defer registry_close(&registry)
	defer controller_close(&controller)

	base := controller_request(201, 1, 3, composition)
	one := completion_session_request(base, 201, 1, 3, "π", .Identifier)
	started, rejected := controller_start(&controller, 202, 1, one, composition)
	testing.expect(t, !started)
	testing.expect_value(t, rejected.code, Failure_Code.Invalid_Request)
	two := completion_session_request(base, 203, 2, 3, "πx", .Identifier)
	started, _ = controller_start(&controller, 202, 1, two, composition)
	testing.expect(t, started)
}

/* Verifies complete batches filter locally and preserve visible selection. */
@(test)
session_filters_complete_batch_locally :: proc(t: ^testing.T) {
	registry: Role_Registry
	controller: Controller
	policy := DEFAULT_SESSION_POLICY
	policy.identifier_enabled = true
	composition, initialized := controller_fixture(&registry, &controller, policy = policy)
	testing.expect(t, initialized)
	if !initialized do return
	defer registry_close(&registry)
	defer controller_close(&controller)

	request := controller_request(211, 1, 3, composition)
	started, _ := controller_start(&controller, 212, 1, request, composition)
	queued, _ := controller_queue(&controller)
	sent, _ := controller_send(&controller)
	items := []Candidate {
		completion_filter_candidate(213, "print", provider_order = 0),
		completion_filter_candidate(214, "private", provider_order = 1),
	}
	batch := controller_batch(request, items)
	published, _ := controller_publish(&controller, &batch)
	selected, _ := controller_select_candidate(&controller, 214)
	refined_request := completion_session_request(request, 215, 2, 4, "priv", .Identifier)
	action, refined, failure := controller_refine(&controller, refined_request)
	testing.expectf(t, refined, "local refine failed: %v", failure.code)
	inspection, inspected, _ := controller_inspect(&controller)
	testing.expect(t, started && queued && sent && published && selected && inspected)
	testing.expect_value(t, action, Refresh_Action.Local_Filter)
	testing.expect_value(t, inspection.filtered_candidate_count, u16(1))
	testing.expect_value(t, inspection.selected_candidate, Candidate_ID(214))
	testing.expect_value(t, inspection.current_revision, Document_Revision(4))
	testing.expect(t, !inspection.retained_during_refresh)
}

/* Verifies candidate movement is deterministic and clamps at both edges. */
@(test)
session_moves_visible_selection :: proc(t: ^testing.T) {
	registry: Role_Registry
	controller: Controller
	composition, initialized := controller_fixture(&registry, &controller)
	testing.expect(t, initialized)
	if !initialized do return
	defer registry_close(&registry)
	defer controller_close(&controller)

	request := controller_request(216, 1, 3, composition)
	_, _ = controller_start(&controller, 217, 1, request, composition)
	_, _ = controller_queue(&controller)
	_, _ = controller_send(&controller)
	items := []Candidate {
		completion_filter_candidate(218, "print", provider_order = 0),
		completion_filter_candidate(219, "private", provider_order = 1),
		completion_filter_candidate(220, "priority", provider_order = 2),
	}
	batch := controller_batch(request, items)
	published, _ := controller_publish(&controller, &batch)
	testing.expect(t, published)

	_, _ = controller_move_selection(&controller, .Last)
	last, last_ok, _ := controller_inspect(&controller)
	_, _ = controller_move_selection(&controller, .Next)
	clamped_last, clamped_last_ok, _ := controller_inspect(&controller)
	_, _ = controller_move_selection(&controller, .First)
	first, first_ok, _ := controller_inspect(&controller)
	_, _ = controller_move_selection(&controller, .Previous)
	clamped_first, clamped_first_ok, _ := controller_inspect(&controller)
	testing.expect(t, last_ok && clamped_last_ok && first_ok && clamped_first_ok)
	testing.expect_value(t, last.filtered_candidate_count, u16(3))
	testing.expect_value(t, last.selected_candidate, Candidate_ID(219))
	testing.expect_value(t, clamped_last.selected_candidate, Candidate_ID(219))
	testing.expect_value(t, first.selected_candidate, Candidate_ID(218))
	testing.expect_value(t, clamped_first.selected_candidate, Candidate_ID(218))
}

/* Verifies incomplete batches retain projection until the newer response publishes. */
@(test)
completion_session_refreshes_incomplete_batch :: proc(t: ^testing.T) {
	registry: Role_Registry
	controller: Controller
	composition, initialized := controller_fixture(&registry, &controller)
	testing.expect(t, initialized)
	if !initialized do return
	defer registry_close(&registry)
	defer controller_close(&controller)

	request := controller_request(221, 1, 3, composition)
	_, _ = controller_start(&controller, 222, 1, request, composition)
	_, _ = controller_queue(&controller)
	_, _ = controller_send(&controller)
	items := []Candidate {
		completion_filter_candidate(223, "print", provider_order = 0),
		completion_filter_candidate(224, "private", provider_order = 1),
	}
	batch := controller_batch(request, items)
	batch.disposition = .Incomplete
	published, _ := controller_publish(&controller, &batch)
	selected, _ := controller_select_candidate(&controller, 224)
	refresh_request := completion_session_request(request, 225, 2, 4, "priv", .Incomplete)
	action, refreshed, failure := controller_refine(&controller, refresh_request)
	testing.expectf(t, refreshed, "incomplete refresh failed: %v", failure.code)
	pending, pending_ok, _ := controller_inspect(&controller)
	testing.expect(t, published && selected && pending_ok)
	testing.expect_value(t, action, Refresh_Action.Provider_Request)
	testing.expect_value(t, pending.state, Session_State.Requesting)
	testing.expect(t, pending.retained_during_refresh)
	testing.expect_value(t, pending.filtered_candidate_count, u16(2))
	testing.expect_value(t, pending.selected_candidate, Candidate_ID(224))

	_, _ = controller_queue(&controller)
	_, _ = controller_send(&controller)
	replacement_items := []Candidate {
		completion_filter_candidate(226, "priority", provider_order = 0),
		completion_filter_candidate(227, "private", provider_order = 1),
	}
	replacement := controller_batch(refresh_request, replacement_items, 2)
	replacement.id = 92
	replaced, replace_failure := controller_publish(&controller, &replacement)
	testing.expectf(t, replaced, "replacement publish failed: %v", replace_failure.code)
	ready, inspected, _ := controller_inspect(&controller)
	testing.expect(t, inspected)
	testing.expect_value(t, ready.state, Session_State.Ready)
	testing.expect_value(t, ready.selected_candidate, Candidate_ID(227))
	testing.expect(t, !ready.retained_during_refresh)
}

/* Verifies an incompatible query edit dismisses stale session authority. */
@(test)
session_dismisses_incompatible_refresh :: proc(t: ^testing.T) {
	registry: Role_Registry
	controller: Controller
	composition, initialized := controller_fixture(&registry, &controller)
	testing.expect(t, initialized)
	if !initialized do return
	defer registry_close(&registry)
	defer controller_close(&controller)

	request := controller_request(231, 1, 3, composition)
	_, _ = controller_start(&controller, 232, 1, request, composition)
	stale := completion_session_request(request, 233, 2, 4, "other", .Identifier)
	stale.query_range.start = request.query_range.start - 1
	stale.query_range.end = stale.query_range.start + 5
	stale.cursor_byte = stale.query_range.end
	action, refined, failure := controller_refine(&controller, stale)
	inspection, inspected, _ := controller_inspect(&controller)
	testing.expect(t, !refined && inspected)
	testing.expect_value(t, action, Refresh_Action.Dismiss)
	testing.expect_value(t, failure.code, Failure_Code.Stale_Request)
	testing.expect_value(t, inspection.state, Session_State.Dismissed)
}
