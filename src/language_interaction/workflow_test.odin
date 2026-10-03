// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language_interaction

import "core:testing"

/* Verifies every operation starts through the intended shared surface and authority. */
@(test)
operations_route_to_shared_surfaces :: proc(t: ^testing.T) {
	cases := [?]struct {
		operation: Operation,
		phase: Phase,
		surface: Surface,
		class: Operation_Class,
		factory_owned: bool,
	} {
		{.Show_Hover, .Requesting, .Progress, .Service_Query, false},
		{.Go_To_Definition, .Requesting, .Progress, .Service_Query, false},
		{.Find_References, .Requesting, .Progress, .Service_Query, false},
		{.Document_Symbols, .Requesting, .Progress, .Service_Query, false},
		{.Workspace_Symbols, .Prompting, .Prompt, .Service_Query, false},
		{.Signature_Help, .Requesting, .Progress, .Service_Query, false},
		{.Rename, .Prompting, .Prompt, .Checked_Edit, false},
		{.Format_Buffer, .Requesting, .Progress, .Checked_Edit, false},
		{.Format_Region, .Requesting, .Progress, .Checked_Edit, false},
		{.Code_Actions, .Selecting, .Candidates, .Checked_Edit, false},
		{.Describe_Bundle, .Selecting, .Candidates, .Factory_Inspection, true},
		{.Support_Doctor, .Requesting, .Progress, .Factory_Inspection, true},
		{.Bundle_List, .Requesting, .Progress, .Factory_Inspection, true},
		{.Bundle_Search, .Prompting, .Prompt, .Factory_Inspection, true},
		{.Bundle_Install, .Selecting, .Candidates, .Bundle_Management, true},
		{.Bundle_Enable, .Selecting, .Candidates, .Bundle_Management, true},
		{.Bundle_Disable, .Selecting, .Candidates, .Bundle_Management, true},
		{.Bundle_Update, .Selecting, .Candidates, .Bundle_Management, true},
		{.Bundle_Rollback, .Selecting, .Candidates, .Bundle_Management, true},
		{.Bundle_Remove, .Selecting, .Candidates, .Bundle_Management, true},
		{.Bundle_Refresh_Catalogs, .Requesting, .Progress, .Bundle_Management, true},
	}
	workflow: Workflow
	for test_case in cases {
		snapshot, started, failure := workflow_begin(&workflow, {
			operation = test_case.operation,
			availability = availability_available(),
		})
		testing.expectf(t, started, "operation %v did not start: %v", test_case.operation, failure.code)
		testing.expect_value(t, snapshot.phase, test_case.phase)
		testing.expect_value(t, snapshot.surface, test_case.surface)
		testing.expect_value(t, snapshot.class, test_case.class)
		testing.expect_value(t, snapshot.factory_owned, test_case.factory_owned)
		testing.expect_value(t, snapshot.health, Health.Busy)
		testing.expect(t, snapshot.cancellable)
		testing.expect(t, surface_uses_shared_owner(snapshot.surface))
		_, cancelled, _ := workflow_cancel(&workflow, snapshot.generation)
		testing.expect(t, cancelled)
	}
}

/* Verifies admitted results route to popups, results, candidates, and previews. */
@(test)
published_results_select_existing_surface_owners :: proc(t: ^testing.T) {
	cases := [?]struct {operation: Operation, phase: Phase, surface: Surface} {
		{.Show_Hover, .Completed, .Popup},
		{.Signature_Help, .Completed, .Popup},
		{.Go_To_Definition, .Completed, .Results},
		{.Find_References, .Completed, .Results},
		{.Document_Symbols, .Completed, .Candidates},
		{.Format_Buffer, .Previewing, .Preview},
		{.Format_Region, .Previewing, .Preview},
		{.Bundle_Refresh_Catalogs, .Completed, .Results},
	}
	workflow: Workflow
	for test_case in cases {
		started, ok, _ := workflow_begin(&workflow, {
			operation = test_case.operation,
			availability = availability_available(),
		})
		testing.expect(t, ok)
		published, published_ok, failure := workflow_publish(&workflow, started.generation)
		testing.expectf(t, published_ok, "operation %v did not publish: %v", test_case.operation, failure.code)
		testing.expect_value(t, published.phase, test_case.phase)
		testing.expect_value(t, published.surface, test_case.surface)
		if snapshot_active(published) {
			_, cancelled, _ := workflow_cancel(&workflow, published.generation)
			testing.expect(t, cancelled)
		}
	}
}

/* Verifies preview confirmation, progress, completion, cancellation, and stale rejection. */
@(test)
checked_transitions_are_generation_bound :: proc(t: ^testing.T) {
	workflow: Workflow
	started, ok, _ := workflow_begin(&workflow, {
		operation = .Rename,
		availability = availability_available(),
	})
	testing.expect(t, ok)
	requesting, submitted, _ := workflow_submit(&workflow, started.generation)
	testing.expect(t, submitted)
	preview, published, _ := workflow_publish(&workflow, requesting.generation)
	testing.expect(t, published)
	testing.expect_value(t, preview.surface, Surface.Preview)
	applying, confirmed, _ := workflow_confirm(&workflow, preview.generation)
	testing.expect(t, confirmed)
	progress, progressed, _ := workflow_progress(&workflow, applying.generation, 1, 2, "Applying checked edits")
	testing.expect(t, progressed)
	testing.expect_value(t, progress.progress, u64(1))
	complete, completed, _ := workflow_complete(&workflow, progress.generation, "Rename applied")
	testing.expect(t, completed)
	testing.expect_value(t, complete.health, Health.Idle)
	_, stale, stale_failure := workflow_cancel(&workflow, complete.generation + 1)
	testing.expect(t, !stale)
	testing.expect_value(t, stale_failure.code, Failure_Code.Stale_Generation)
}

/* Verifies unavailable operations retain exact reason and recovery evidence. */
@(test)
unavailable_operations_are_actionable :: proc(t: ^testing.T) {
	availability, copied := availability_unavailable(
		"No active language service supports hover.",
		"Run describe-language-support and configure an available service.",
	)
	testing.expect(t, copied)
	workflow: Workflow
	snapshot, retained, failure := workflow_begin(&workflow, {
		operation = .Show_Hover,
		availability = availability,
	})
	testing.expect(t, retained)
	testing.expect_value(t, failure.code, Failure_Code.Unavailable)
	testing.expect_value(t, snapshot.phase, Phase.Failed)
	testing.expect_value(t, snapshot.health, Health.Failed)
	testing.expect_value(t, text_string(&snapshot.failure), "No active language service supports hover.")
	testing.expect_value(t, text_string(&snapshot.recovery), "Run describe-language-support and configure an available service.")
}
