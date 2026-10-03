// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery_process_presentation_focused

import odra "../../src/ksawery_module"
import ksawery "../../src/ksawery"
import "../../src/ui"
import "core:strings"
import "core:testing"

/* Builds one active or terminal record through the real session coordinator. */
process_presentation_test_append :: proc(
	coordinator: ^odra.Ksawery_Process_Coordinator,
	title: string,
	terminal: bool,
	truncated: bool,
) -> (ksawery.Process_Record_Authority, ksawery.Process_Record_Proposal, bool) {
	proposal := ksawery.Process_Record_Proposal {
		lifecycle = .Admitted,
		phase = .Checking,
		target_kind = .Repository,
		title = title,
		target = "/work/process-presentation",
		phase_detail = "Checking repository",
		progress = {kind = .Phase},
		timing = {admitted_ns = 10, started_ns = 10, updated_ns = 10},
		action_count = 1,
	}
	proposal.actions[0] = {kind = .Inspect, available = true}
	authority, admitted, _ := odra.ksawery_process_coordinator_admit(
		coordinator,
		41,
		.History,
		proposal,
	)
	if !admitted do return {}, {}, false
	running := proposal
	running.lifecycle = .Running
	running.phase = .Executing
	running.phase_detail = "Reading repository history"
	running.progress = {kind = .Determinate, current = 1, total = 4}
	running.timing = {admitted_ns = 10, started_ns = 10, updated_ns = 20, elapsed_ns = 10}
	running.output = transmute([]u8)string("history output\nsecond line\n")
	running.diagnostic = transmute([]u8)string("history diagnostic\n")
	running.output_truncated = truncated
	running.diagnostic_truncated = truncated
	running.actions = {}
	running.actions[0] = {kind = .Inspect, available = true}
	running.actions[1] = {kind = .Cancel, available = true}
	running.action_count = 2
	published, _ := odra.ksawery_process_coordinator_publish(coordinator, nil, running)
	if !published do return {}, {}, false
	if !terminal do return authority, running, true
	finished := running
	finished.lifecycle = .Succeeded
	finished.phase = .Verifying
	finished.outcome = .Verified_Success
	finished.phase_detail = "Repository truth checked"
	finished.message = "History inspection verified"
	finished.timing = {admitted_ns = 10, started_ns = 10, updated_ns = 30, finished_ns = 30, elapsed_ns = 20}
	finished.exit_status = 0
	finished.exit_status_available = true
	finished.actions = {}
	finished.actions[0] = {kind = .Inspect, available = true}
	finished.actions[1] = {kind = .Clear, available = true}
	finished.action_count = 2
	published, _ = odra.ksawery_process_coordinator_publish(coordinator, nil, finished)
	if !published do return {}, {}, false
	return authority, finished, true
}

/* Verifies active-first navigation, retained details, truncation, and generation-safe actions. */
@(test)
process_presentation_preserves_selection_and_bounded_detail :: proc(t: ^testing.T) {
	repository: ksawery.Repository_Context
	ready := ksawery.repository_context_assign(&repository, "/work/process-presentation")
	coordinator: odra.Ksawery_Process_Coordinator
	initialized := ready && odra.ksawery_process_coordinator_init(&coordinator, repository)
	testing.expect(t, initialized)
	if !initialized do return
	defer odra.ksawery_process_coordinator_close(&coordinator)
	_, _, first := process_presentation_test_append(&coordinator, "Old history", true, false)
	_, _, second := process_presentation_test_append(&coordinator, "Recent history", true, true)
	active_authority, running, third := process_presentation_test_append(
		&coordinator,
		"Current history",
		false,
		false,
	)
	testing.expect(t, first && second && third)
	if !first || !second || !third do return
	records := coordinator.records[:int(coordinator.record_count)]
	selection, selected := ksawery.process_selection_begin(records)
	testing.expect(t, selected)
	testing.expect_value(t, selection.current.operation, active_authority.operation)
	old_cancel, cancel_available, cancel_failure := ksawery.process_selection_action(records, selection, .Cancel)
	testing.expectf(t, cancel_available, "active cancellation unavailable with %v", cancel_failure)
	next, moved, move_failure := ksawery.process_selection_move(records, selection, .Next)
	testing.expectf(t, moved, "retained Process navigation failed with %v", move_failure)
	detail, detailed, detail_failure := ksawery.process_surface_detail(records, next)
	testing.expectf(t, detailed, "retained Process detail failed with %v", detail_failure)
	if detailed {
		testing.expect(t, detail.row.output_truncated)
		testing.expect(t, detail.row.diagnostic_truncated)
		output, output_ok, _ := ksawery.process_surface_text(records, detail.row.id, .Output)
		diagnostic, diagnostic_ok, _ := ksawery.process_surface_text(records, detail.row.id, .Diagnostic)
		testing.expect(t, output_ok && strings.contains(string(output), "second line"))
		testing.expect(t, diagnostic_ok && strings.contains(string(diagnostic), "history diagnostic"))
	}
	replacement := running
	replacement.phase = .Refreshing
	replacement.phase_detail = "Refreshing repository history"
	replacement.timing = {admitted_ns = 10, started_ns = 10, updated_ns = 30, elapsed_ns = 20}
	replaced, replace_failure := odra.ksawery_process_coordinator_publish(&coordinator, nil, replacement)
	testing.expectf(t, replaced, "active replacement failed with %v", replace_failure)
	records = coordinator.records[:int(coordinator.record_count)]
	current, current_failure := ksawery.process_surface_action_is_current(records, old_cancel)
	testing.expect(t, !current)
	testing.expect_value(t, current_failure, ksawery.Failure_Code.Process_Record_Stale)
	reconciled, reconciled_ok, reconcile_failure := ksawery.process_selection_reconcile(records, selection)
	testing.expectf(t, reconciled_ok, "active selection reconciliation failed with %v", reconcile_failure)
	testing.expect_value(t, reconciled.current.operation, active_authority.operation)
	testing.expect(t, reconciled.current.generation > selection.current.generation)
}

/* Verifies compact progress and terminal failure use bounded non-floating theme roles. */
@(test)
process_presentation_compacts_progress_and_terminal_fallback :: proc(t: ^testing.T) {
	repository: ksawery.Repository_Context
	ready := ksawery.repository_context_assign(&repository, "/work/process-presentation")
	coordinator: odra.Ksawery_Process_Coordinator
	initialized := ready && odra.ksawery_process_coordinator_init(&coordinator, repository)
	testing.expect(t, initialized)
	if !initialized do return
	defer odra.ksawery_process_coordinator_close(&coordinator)
	_, running, appended := process_presentation_test_append(&coordinator, "Current history", false, false)
	testing.expect(t, appended)
	if !appended do return
	storage: [ui.MAX_DIAGNOSTIC_BYTES]u8
	records := coordinator.records[:int(coordinator.record_count)]
	content, role, active, present := odra.ksawery_process_compact_feedback(records, storage[:])
	testing.expect(t, present && active)
	testing.expect_value(t, role, ui.Style_Role.Status_Active)
	testing.expect(t, ui.style_role_is_valid(role))
	testing.expect(t, strings.contains(content, "Reading repository history 1/4"))
	testing.expect(t, strings.contains(content, "$ inspect"))
	testing.expect(t, strings.contains(content, "C-g cancel"))

	failed := running
	failed.lifecycle = .Failed
	failed.phase = .Verifying
	failed.outcome = .Known_Failure
	failed.message = "History inspection failed"
	failed.timing = {admitted_ns = 10, started_ns = 10, updated_ns = 30, finished_ns = 30, elapsed_ns = 20}
	failed.actions = {}
	failed.actions[0] = {kind = .Inspect, available = true}
	failed.actions[1] = {kind = .Clear, available = true}
	failed.action_count = 2
	published, publish_failure := odra.ksawery_process_coordinator_publish(&coordinator, nil, failed)
	testing.expectf(t, published, "terminal Process publication failed with %v", publish_failure)
	records = coordinator.records[:int(coordinator.record_count)]
	content, role, active, present = odra.ksawery_process_compact_feedback(records, storage[:])
	testing.expect(t, present && active)
	testing.expect_value(t, role, ui.Style_Role.Diagnostic_Rejected)
	testing.expect(t, ui.style_role_is_valid(role))
	testing.expect(t, strings.contains(content, "History inspection failed"))
	testing.expect(t, strings.contains(content, "$ inspect"))
	testing.expect(t, !strings.contains(content, "C-g cancel"))
	detail_selection, selected := ksawery.process_selection_begin(records)
	detail, detailed, detail_failure := ksawery.process_surface_detail(records, detail_selection)
	testing.expectf(t, selected && detailed, "non-floating Process fallback failed with %v", detail_failure)
	if detailed do testing.expect_value(t, detail.row.lifecycle, ksawery.Repository_Process_Lifecycle.Failed)
}
