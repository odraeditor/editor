// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery_process_focused

import ksawery "../../src/ksawery"
import "core:testing"

/* Verifies an empty Process source remains a valid explicit presentation state. */
@(test)
process_surface_admits_empty_state :: proc(t: ^testing.T) {
	records: [0]ksawery.Process_Record
	surface, described := ksawery.process_surface_descriptor(records[:])
	testing.expect(t, described)
	testing.expect_value(t, surface.state, ksawery.Process_Surface_State.Empty)
	testing.expect_value(t, surface.row_count, u32(0))
	selection, begun := ksawery.process_selection_begin(records[:])
	testing.expect(t, begun)
	testing.expect(t, ksawery.process_selection_is_current(records[:], selection))
	_, detailed, failure := ksawery.process_surface_detail(records[:], selection)
	testing.expect(t, !detailed)
	testing.expect_value(t, failure, ksawery.Failure_Code.Action_Unavailable)
}

/* Verifies Process rows order the active operation before newest retained outcomes. */
@(test)
process_surface_orders_active_and_retained_rows :: proc(t: ^testing.T) {
	records: [3]ksawery.Process_Record
	_, _, opened := process_semantic_record_open(&records[0], 1, true, false, false)
	testing.expect(t, opened)
	_, _, opened = process_semantic_record_open(&records[1], 2, true, false, false)
	testing.expect(t, opened)
	_, _, opened = process_semantic_record_open(&records[2], 3, false, false, false)
	testing.expect(t, opened)
	defer process_semantic_records_close(records[:])
	if !opened do return

	surface, described := ksawery.process_surface_descriptor(records[:])
	testing.expect(t, described)
	testing.expect_value(t, surface.state, ksawery.Process_Surface_State.Available)
	testing.expect_value(t, surface.row_count, u32(3))
	testing.expect_value(t, surface.active_rows, u8(1))
	testing.expect_value(t, surface.retained_rows, u32(2))
	expected := [?]ksawery.Repository_Operation_ID{3, 2, 1}
	for ordinal in 0 ..< surface.row_count {
		row, projected, failure := ksawery.process_surface_row(records[:], ordinal)
		testing.expectf(t, projected, "row %d projection failed with %v", ordinal, failure)
		if projected {
			testing.expect_value(t, row.id.operation, expected[ordinal])
			testing.expect_value(t, row.active, ordinal == 0)
		}
	}

	selection, begun := ksawery.process_selection_begin(records[:])
	testing.expect(t, begun)
	testing.expect_value(t, selection.current.operation, ksawery.Repository_Operation_ID(3))
	next_selection, moved, move_failure := ksawery.process_selection_move(records[:], selection, .Next)
	testing.expectf(t, moved, "next Process movement failed with %v", move_failure)
	testing.expect_value(t, next_selection.current.operation, ksawery.Repository_Operation_ID(2))
	previous_selection: ksawery.Process_Selection
	previous_selection, moved, move_failure = ksawery.process_selection_move(records[:], next_selection, .Previous)
	testing.expectf(t, moved, "previous Process movement failed with %v", move_failure)
	testing.expect_value(t, previous_selection.current.operation, ksawery.Repository_Operation_ID(3))
}

/* Verifies details expose bounded safe content and reject replaced-generation actions. */
@(test)
process_surface_details_and_actions_are_generation_checked :: proc(t: ^testing.T) {
	records: [1]ksawery.Process_Record
	authority, running, opened := process_semantic_record_open(&records[0], 9, false, true, true)
	testing.expect(t, opened)
	defer process_semantic_records_close(records[:])
	if !opened do return

	selection, begun := ksawery.process_selection_begin(records[:])
	testing.expect(t, begun)
	detail, detailed, detail_failure := ksawery.process_surface_detail(records[:], selection)
	testing.expectf(t, detailed, "Process detail failed with %v", detail_failure)
	if !detailed do return
	testing.expect(t, detail.row.active)
	testing.expect(t, detail.row.output_truncated)
	testing.expect(t, detail.row.diagnostic_truncated)
	testing.expect_value(t, detail.action_count, u8(2))
	target_kind, target, targeted, target_failure := ksawery.process_surface_target(records[:], detail.row.id)
	testing.expectf(t, targeted, "safe target failed with %v", target_failure)
	testing.expect_value(t, target_kind, ksawery.Process_Target_Kind.Remote)
	testing.expect_value(t, string(target), "origin")
	output, output_available, output_failure := ksawery.process_surface_text(
		records[:],
		detail.row.id,
		.Output,
	)
	testing.expectf(t, output_available, "bounded output failed with %v", output_failure)
	testing.expect_value(t, string(output), "fetch progress\n")
	cancel, resolved, action_failure := ksawery.process_selection_action(records[:], selection, .Cancel)
	testing.expectf(t, resolved, "cancel action failed with %v", action_failure)
	current, current_failure := ksawery.process_surface_action_is_current(records[:], cancel)
	testing.expectf(t, current, "current cancel rejected with %v", current_failure)

	next := running
	next.generation = 3
	next.phase = .Refreshing
	next.phase_detail = "Refreshing repository"
	next.timing = {admitted_ns = 10, started_ns = 10, updated_ns = 30, elapsed_ns = 20}
	replaced, replace_failure := ksawery.process_record_replace(&records[0], authority, next)
	testing.expectf(t, replaced, "active replacement failed with %v", replace_failure)
	current, current_failure = ksawery.process_surface_action_is_current(records[:], cancel)
	testing.expect(t, !current)
	testing.expect_value(t, current_failure, ksawery.Failure_Code.Process_Record_Stale)
	_, detailed, detail_failure = ksawery.process_surface_detail(records[:], selection)
	testing.expect(t, !detailed)
	testing.expect_value(t, detail_failure, ksawery.Failure_Code.Process_Record_Stale)
	reconciled, reconciled_ok, reconcile_failure := ksawery.process_selection_reconcile(records[:], selection)
	testing.expectf(t, reconciled_ok, "selection reconciliation failed with %v", reconcile_failure)
	testing.expect_value(t, reconciled.current.operation, selection.current.operation)
	testing.expect_value(t, reconciled.current.generation, ksawery.Process_Record_Generation(3))
}

/* Verifies malformed sources cannot expose two simultaneous active operations. */
@(test)
process_surface_rejects_multiple_active_records :: proc(t: ^testing.T) {
	records: [2]ksawery.Process_Record
	_, _, first := process_semantic_record_open(&records[0], 1, false, false, false)
	_, _, second := process_semantic_record_open(&records[1], 2, false, false, false)
	defer process_semantic_records_close(records[:])
	testing.expect(t, first && second)
	_, described := ksawery.process_surface_descriptor(records[:])
	testing.expect(t, !described)
}

process_semantic_record_open :: proc(
	record: ^ksawery.Process_Record,
	operation: ksawery.Repository_Operation_ID,
	terminal: bool,
	output_truncated: bool,
	diagnostic_truncated: bool,
) -> (ksawery.Process_Record_Authority, ksawery.Process_Record_Proposal, bool) {
	authority, proposal := focused_process_record_fixture()
	authority.operation = operation
	proposal.operation = operation
	opened_record, opened, _ := ksawery.process_record_open(authority, proposal)
	if !opened do return {}, {}, false
	record^ = opened_record
	running := proposal
	running.generation = 2
	running.lifecycle = .Running
	running.phase = .Executing
	running.phase_detail = "Executing fetch"
	running.output = transmute([]u8)string("fetch progress\n")
	running.diagnostic = transmute([]u8)string("remote notice\n")
	running.output_truncated = output_truncated
	running.diagnostic_truncated = diagnostic_truncated
	running.timing = {admitted_ns = 10, started_ns = 10, updated_ns = 20, elapsed_ns = 10}
	running.actions = {}
	running.actions[0] = {kind = .Inspect, available = true}
	running.actions[1] = {kind = .Cancel, available = true}
	running.action_count = 2
	replaced, _ := ksawery.process_record_replace(record, authority, running)
	if !replaced {
		ksawery.process_record_close(record)
		return {}, {}, false
	}
	if terminal {
		finished := running
		finished.generation = 3
		finished.lifecycle = .Succeeded
		finished.phase = .Verifying
		finished.phase_detail = "Repository truth checked"
		finished.outcome = .Verified_Success
		finished.message = "Fetch verified"
		finished.timing = {admitted_ns = 10, started_ns = 10, updated_ns = 30, finished_ns = 30, elapsed_ns = 20}
		finished.exit_status = 0
		finished.exit_status_available = true
		finished.actions = {}
		finished.actions[0] = {kind = .Inspect, available = true}
		finished.actions[1] = {kind = .Clear, available = true}
		finished.action_count = 2
		replaced, _ = ksawery.process_record_replace(record, authority, finished)
		if !replaced {
			ksawery.process_record_close(record)
			return {}, {}, false
		}
		return authority, finished, true
	}
	return authority, running, true
}

process_semantic_records_close :: proc(records: []ksawery.Process_Record) {
	for index in 0 ..< len(records) do ksawery.process_record_close(&records[index])
}
