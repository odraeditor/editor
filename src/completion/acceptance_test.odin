// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package completion

import "../editor"
import "../history"
import "../transaction"
import editor_view "../view"
import "core:mem"
import "core:testing"

@(private = "file")
Acceptance_Fixture :: struct {
	tracking:   mem.Tracking_Allocator,
	buffer:     editor.Buffer,
	views:      editor_view.Registry,
	view:       editor_view.View_Handle,
	history:    history.Store,
	roles:      Role_Registry,
	controller: Controller,
	composition: Composition_Scope,
}

/* Verifies selected completion edits publish atomically with cursor and history state. */
@(test)
applies_candidate_as_undo_unit :: proc(t: ^testing.T) {
	fixture: Acceptance_Fixture
	ready := acceptance_fixture_open(t, &fixture, "package main\n\npri")
	if !ready do return
	defer acceptance_fixture_close(t, &fixture)

	request := acceptance_request(&fixture, {start = 14, end = 17})
	primary_text, _ := text_copy("fmt.println")
	import_text, _ := text_copy("import \"core:fmt\"\n")
	candidate := test_candidate(701)
	candidate.has_primary_edit = true
	candidate.primary_edit = {range = request.query_range, new_text = primary_text}
	candidate.additional_edits[0] = {
		range = {start = 0, end = 0},
		new_text = import_text,
	}
	candidate.additional_edit_count = 1
	acceptance_publish(t, &fixture, request, []Candidate{candidate})
	scope, scoped, _ := controller_acceptance_scope(&fixture.controller)
	testing.expect(t, scoped)
	result, accepted, acceptance_failure := controller_accept_candidate(
		&fixture.controller,
		scope,
		acceptance_target(&fixture, 701),
	)
	testing.expectf(t, accepted, "acceptance failed with %v", acceptance_failure.completion.code)
	testing.expect_value(t, result.result_revision, Document_Revision(2))
	testing.expect_value(t, result.edit_count, u8(2))
	testing.expect_value(t, result.point_byte, u64(len("import \"core:fmt\"\npackage main\n\nfmt.println")))
	acceptance_expect_text(
		t,
		&fixture.buffer,
		2,
		"import \"core:fmt\"\npackage main\n\nfmt.println\n",
	)
	view_state, view_ok, _ := editor_view.snapshot(&fixture.views, fixture.view)
	testing.expect(t, view_ok)
	testing.expect_value(t, view_state.point_position.byte_offset, editor.Byte_Offset(result.point_byte))
	testing.expect(t, !view_state.mark.present && !view_state.region_active)
	inspection, inspected, _ := controller_inspect(&fixture.controller)
	testing.expect(t, inspected)
	testing.expect_value(t, inspection.state, Session_State.Retired)

	_, undone, undo_failure := transaction.transaction_history_navigate(
		&fixture.history,
		&fixture.buffer,
		.Undo,
		702,
		702,
		transaction.Allocator_Set {
			persistent = mem.tracking_allocator(&fixture.tracking),
			temporary = context.temp_allocator,
		},
		transaction.DEFAULT_LIMITS,
		&fixture.views,
		fixture.view,
	)
	testing.expectf(t, undone, "completion undo failed with %v", undo_failure.code)
	acceptance_expect_text(t, &fixture.buffer, 3, "package main\n\npri\n")
}

/* Verifies stale authority and overlapping edits never publish partial text. */
@(test)
rejects_stale_or_overlapping_candidates :: proc(t: ^testing.T) {
	fixture: Acceptance_Fixture
	ready := acceptance_fixture_open(t, &fixture, "package main\n\npri")
	if !ready do return
	defer acceptance_fixture_close(t, &fixture)

	request := acceptance_request(&fixture, {start = 14, end = 17})
	primary_text, _ := text_copy("print")
	overlap_text, _ := text_copy("overlap")
	candidate := test_candidate(711)
	candidate.has_primary_edit = true
	candidate.primary_edit = {range = request.query_range, new_text = primary_text}
	candidate.additional_edits[0] = {
		range = {start = 16, end = 17},
		new_text = overlap_text,
	}
	candidate.additional_edit_count = 1
	acceptance_publish(t, &fixture, request, []Candidate{candidate})
	scope, _, _ := controller_acceptance_scope(&fixture.controller)
	stale := scope
	stale.batch_generation += 1
	_, accepted_stale, stale_failure := controller_accept_candidate(
		&fixture.controller,
		stale,
		acceptance_target(&fixture, 711),
	)
	testing.expect(t, !accepted_stale)
	testing.expect_value(t, stale_failure.completion.code, Failure_Code.Stale_Scope)
	acceptance_expect_text(t, &fixture.buffer, 1, "package main\n\npri\n")

	_, _ = controller_retire(&fixture.controller)
	request.id += 1
	request.generation += 1
	acceptance_publish(t, &fixture, request, []Candidate{candidate})
	scope, _, _ = controller_acceptance_scope(&fixture.controller)
	_, accepted_overlap, overlap_failure := controller_accept_candidate(
		&fixture.controller,
		scope,
		acceptance_target(&fixture, 712),
	)
	testing.expect(t, !accepted_overlap)
	testing.expect_value(t, overlap_failure.completion.code, Failure_Code.Transaction_Rejected)
	testing.expect_value(t, overlap_failure.transaction.code, transaction.Failure_Code.Overlapping_Batch)
	acceptance_expect_text(t, &fixture.buffer, 1, "package main\n\npri\n")
}

/* Verifies plain insertion fallback respects write policy before replacing the query. */
@(test)
acceptance_applies_plain_text_only_when_writable :: proc(t: ^testing.T) {
	fixture: Acceptance_Fixture
	ready := acceptance_fixture_open(t, &fixture, "package main\n\npri")
	if !ready do return
	defer acceptance_fixture_close(t, &fixture)

	request := acceptance_request(&fixture, {start = 14, end = 17})
	candidate := test_candidate(721)
	acceptance_publish(t, &fixture, request, []Candidate{candidate})
	scope, _, _ := controller_acceptance_scope(&fixture.controller)
	read_only := acceptance_target(&fixture, 721)
	read_only.writable = false
	_, accepted_read_only, read_only_failure := controller_accept_candidate(
		&fixture.controller,
		scope,
		read_only,
	)
	testing.expect(t, !accepted_read_only)
	testing.expect_value(t, read_only_failure.completion.code, Failure_Code.Write_Forbidden)
	acceptance_expect_text(t, &fixture.buffer, 1, "package main\n\npri\n")

	_, _ = controller_retire(&fixture.controller)
	request.id += 1
	request.generation += 1
	acceptance_publish(t, &fixture, request, []Candidate{candidate})
	scope, _, _ = controller_acceptance_scope(&fixture.controller)
	result, accepted, failure := controller_accept_candidate(
		&fixture.controller,
		scope,
		acceptance_target(&fixture, 722),
	)
	testing.expectf(t, accepted, "plain completion failed with %v", failure.completion.code)
	testing.expect_value(t, result.point_byte, u64(19))
	acceptance_expect_text(t, &fixture.buffer, 2, "package main\n\nprint\n")
}

/* Verifies trigger-character completion inserts after the receiver instead of replacing it. */
@(test)
plain_insert_keeps_trigger_receiver :: proc(t: ^testing.T) {
	fixture: Acceptance_Fixture
	ready := acceptance_fixture_open(t, &fixture, "fmt.")
	if !ready do return
	defer acceptance_fixture_close(t, &fixture)

	request := acceptance_request(&fixture, {start = 4, end = 4}, "")
	trigger, _ := text_copy(".")
	request.trigger = .Trigger_Character
	request.trigger_character = trigger
	candidate := test_candidate(731)
	insertion, _ := text_copy("println")
	candidate.insertion_text = insertion
	acceptance_publish(t, &fixture, request, []Candidate{candidate})
	scope, _, _ := controller_acceptance_scope(&fixture.controller)
	_, accepted, failure := controller_accept_candidate(
		&fixture.controller,
		scope,
		acceptance_target(&fixture, 731),
	)
	testing.expectf(t, accepted, "trigger acceptance failed with %v", failure.completion.code)
	acceptance_expect_text(t, &fixture.buffer, 2, "fmt.println\n")
}

@(private = "file")
acceptance_fixture_open :: proc(
	t: ^testing.T,
	fixture: ^Acceptance_Fixture,
	text: string,
) -> bool {
	fixture^ = {}
	mem.tracking_allocator_init(&fixture.tracking, context.allocator)
	allocator := mem.tracking_allocator(&fixture.tracking)
	buffer_ok, buffer_failure := editor.buffer_init(
		&fixture.buffer,
		601,
		text,
		editor.Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
	)
	testing.expectf(t, buffer_ok, "buffer init failed with %v", buffer_failure.code)
	if !buffer_ok do return false
	bootstrap: transaction.Transaction
	started, _ := transaction.transaction_begin(
		&bootstrap,
		600,
		600,
		&fixture.buffer,
		transaction.Origin{kind = .Built_In, descriptor = "completion-test"},
		"completion-test-bootstrap",
		transaction.Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
	)
	end, _, _ := transaction.transaction_position(&bootstrap, editor.Byte_Offset(len(text)))
	_, _ = transaction.transaction_splice(
		&bootstrap,
		editor.Working_Splice{start = end, end = end, replacement = "\n"},
	)
	_, _ = transaction.transaction_validate(&bootstrap)
	_, committed, _ := transaction.transaction_commit(&bootstrap)
	testing.expect(t, started && committed)
	transaction.transaction_close(&bootstrap)

	views_ok, _ := editor_view.registry_init(&fixture.views, 601, allocator)
	view_ok: bool
	fixture.view, view_ok, _ = editor_view.create(&fixture.views, &fixture.buffer)
	history_ok, _ := history.store_init(
		&fixture.history,
		601,
		601,
		1,
		history.Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
	)
	controller_ok: bool
	fixture.composition, controller_ok = controller_fixture(
		&fixture.roles,
		&fixture.controller,
		allocator,
	)
	testing.expect(t, views_ok && view_ok && history_ok && controller_ok)
	return views_ok && view_ok && history_ok && controller_ok
}

@(private = "file")
acceptance_fixture_close :: proc(t: ^testing.T, fixture: ^Acceptance_Fixture) {
	controller_close(&fixture.controller)
	registry_close(&fixture.roles)
	history.store_close(&fixture.history)
	editor_view.close(&fixture.views, &fixture.view)
	editor_view.registry_close(&fixture.views)
	editor.buffer_close(&fixture.buffer)
	mem.tracking_allocator_destroy(&fixture.tracking)
	testing.expect_value(t, fixture.tracking.current_memory_allocated, i64(0))
}

@(private = "file")
acceptance_request :: proc(
	fixture: ^Acceptance_Fixture,
	query_range: Byte_Range,
	query_text := "pri",
) -> Request {
	request := controller_request(601, 1, 1, fixture.composition)
	request.scope.buffer_id = 601
	request.scope.view_id = View_ID(fixture.view.view_id)
	request.scope.view_generation = View_Generation(fixture.view.generation)
	request.cursor_byte = query_range.end
	request.query_range = query_range
	query, _ := text_copy(query_text)
	request.query = query
	return request
}

@(private = "file")
acceptance_publish :: proc(
	t: ^testing.T,
	fixture: ^Acceptance_Fixture,
	request: Request,
	items: []Candidate,
) {
	started, _ := controller_start(
		&fixture.controller,
		601,
		Session_Generation(request.generation),
		request,
		fixture.composition,
	)
	queued, _ := controller_queue(&fixture.controller)
	sent, _ := controller_send(&fixture.controller)
	batch := controller_batch(request, items, Batch_Generation(request.generation))
	published, failure := controller_publish(&fixture.controller, &batch)
	testing.expectf(t, started && queued && sent && published, "publication failed with %v", failure.code)
}

@(private = "file")
acceptance_target :: proc(fixture: ^Acceptance_Fixture, identity: u64) -> Acceptance_Target {
	return {
		buffer = &fixture.buffer,
		view_registry = &fixture.views,
		view = fixture.view,
		history_store = &fixture.history,
		transaction_id = transaction.Transaction_ID(identity),
		undo_unit_id = transaction.Undo_Unit_ID(identity),
		allocators = {
			persistent = mem.tracking_allocator(&fixture.tracking),
			temporary = context.temp_allocator,
		},
		transaction_limits = transaction.DEFAULT_LIMITS,
		desired_display_column = 11,
		writable = true,
	}
}

@(private = "file")
acceptance_expect_text :: proc(
	t: ^testing.T,
	buffer: ^editor.Buffer,
	revision: editor.Revision,
	expected: string,
) {
	observed := make([]byte, len(expected))
	defer delete(observed)
	stats, stats_ok, stats_failure := editor.buffer_stats(buffer)
	testing.expectf(t, stats_ok, "buffer stats failed with %v", stats_failure.code)
	testing.expect_value(t, stats.revision, revision)
	copied, ok, failure := editor.buffer_inspect(
		buffer,
		0,
		editor.Byte_Offset(len(expected)),
		observed,
	)
	testing.expectf(t, ok, "buffer copy failed with %v", failure.code)
	testing.expect_value(t, copied, u64(len(expected)))
	testing.expect_value(t, string(observed), expected)
}
