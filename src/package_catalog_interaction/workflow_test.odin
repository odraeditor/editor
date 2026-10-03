// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package package_catalog_interaction

import "core:testing"

/* Verifies prompt, copied candidates, exact confirmation, and progress. */
@(test)
mutating_catalog_workflow_is_generation_bound :: proc(t: ^testing.T) {
	workflow: Workflow
	started, started_ok, _ := workflow_begin(&workflow, .Catalog_Add, availability_available())
	testing.expect(t, started_ok)
	testing.expect_value(t, started.surface, Surface.Prompt)
	requesting, submitted, _ := workflow_submit_prompt(&workflow, started.generation)
	testing.expect(t, submitted)
	candidate_value, candidate_ok := candidate(
		"catalog.example",
		"Example Catalog",
		.Catalog,
		3,
		7,
		"snapshot-a",
		.Current,
	)
	testing.expect(t, candidate_ok)
	selecting, published, _ := workflow_publish_candidates(
		&workflow,
		requesting.generation,
		11,
		[]Candidate{candidate_value},
	)
	testing.expect(t, published)
	testing.expect_value(t, selecting.surface, Surface.Candidates)
	_, stale, stale_failure := workflow_select(&workflow, selecting.generation, 10, 0)
	testing.expect(t, !stale)
	testing.expect_value(t, stale_failure.code, Failure_Code.Stale_Candidates)
	confirming, selected, _ := workflow_select(&workflow, selecting.generation, 11, 0)
	testing.expect(t, selected)
	testing.expect_value(t, confirming.surface, Surface.Confirmation)
	stale_confirmation := confirming.confirmation
	stale_confirmation.record_generation += 1
	_, stale_confirmed, stale_confirm_failure := workflow_confirm(&workflow, stale_confirmation)
	testing.expect(t, !stale_confirmed)
	testing.expect_value(t, stale_confirm_failure.code, Failure_Code.Stale_Confirmation)
	applying, confirmed, _ := workflow_confirm(&workflow, confirming.confirmation)
	testing.expect(t, confirmed)
	progress, progressed, _ := workflow_progress(&workflow, applying.generation, 1, 2, "Publishing catalog state")
	testing.expect(t, progressed)
	testing.expect_value(t, progress.progress, u64(1))
	completed, complete, _ := workflow_complete(&workflow, progress.generation, "Catalog added")
	testing.expect(t, complete)
	testing.expect_value(t, completed.surface, Surface.Results)
}

/* Verifies inspection keeps trust and lifecycle dimensions separate. */
@(test)
inspection_preserves_independent_package_facts_and_return_route :: proc(t: ^testing.T) {
	workflow: Workflow
	started, started_ok, _ := workflow_begin(&workflow, .Catalog_Describe, availability_available())
	testing.expect(t, started_ok)
	candidate_value, candidate_ok := candidate(
		"org.example.package",
		"Example Package 1.0.0",
		.Package,
		4,
		8,
		"snapshot-b",
		.Offline,
	)
	testing.expect(t, candidate_ok)
	selecting, published, _ := workflow_publish_candidates(
		&workflow,
		started.generation,
		12,
		[]Candidate{candidate_value},
	)
	testing.expect(t, published)
	inspecting, selected, _ := workflow_select(&workflow, selecting.generation, 12, 0)
	testing.expect(t, selected)
	testing.expect_value(t, inspecting.phase, Phase.Inspecting)
	value, copied := inspection(
		"org.example.package",
		.Admitted,
		.Verified,
		.Required,
		.Installed,
		.Inactive,
		.Warning,
		.Offline,
		"Curated by catalog A; integrity verified; authority requires confirmation.",
	)
	testing.expect(t, copied)
	inspected, published_inspection, _ := workflow_publish_inspection(&workflow, inspecting.generation, value)
	testing.expect(t, published_inspection)
	testing.expect_value(t, inspected.inspection.curation, Curation_State.Admitted)
	testing.expect_value(t, inspected.inspection.integrity, Integrity_State.Verified)
	testing.expect_value(t, inspected.inspection.authority, Authority_State.Required)
	testing.expect_value(t, inspected.inspection.activation, Activation_State.Inactive)
	returned, returned_ok, _ := workflow_return(&workflow, inspected.generation, 12)
	testing.expect(t, returned_ok)
	testing.expect_value(t, returned.surface, Surface.Candidates)
}

/* Verifies cancellation, stale completion, restart snapshot, and cleanup. */
@(test)
cancellation_and_reset_retain_no_candidate_state :: proc(t: ^testing.T) {
	workflow: Workflow
	started, started_ok, _ := workflow_begin(&workflow, .Catalog_Refresh, availability_available())
	testing.expect(t, started_ok)
	_, stale, stale_failure := workflow_complete(&workflow, started.generation + 1, "stale")
	testing.expect(t, !stale)
	testing.expect_value(t, stale_failure.code, Failure_Code.Stale_Generation)
	cancelled, cancelled_ok, _ := workflow_cancel(&workflow, started.generation)
	testing.expect(t, cancelled_ok)
	testing.expect_value(t, cancelled.phase, Phase.Cancelled)
	restored, present := workflow_snapshot(&workflow)
	testing.expect(t, present)
	testing.expect_value(t, restored.operation, Operation.Catalog_Refresh)
	workflow_reset(&workflow)
	_, snapshot_present := workflow_snapshot(&workflow)
	_, candidates_present := workflow_candidates(&workflow)
	testing.expect(t, !snapshot_present)
	testing.expect(t, !candidates_present)
}

/* Verifies every semantic operation enters an existing shared UI owner. */
@(test)
operations_route_only_to_shared_surfaces :: proc(t: ^testing.T) {
	operations := [?]Operation{
		.Catalog_List,
		.Catalog_Add,
		.Catalog_Disable,
		.Catalog_Remove,
		.Catalog_Refresh,
		.Catalog_Search,
		.Catalog_Describe,
		.Manual_Acquire,
		.Advisory_List,
		.Curator_Validate,
		.Catalog_Doctor,
		.Package_List,
		.Package_Discover,
		.Package_Describe,
		.Package_Install,
		.Package_Enable,
		.Package_Disable,
		.Package_Update,
		.Package_Rollback,
		.Package_Remove,
		.Package_Cleanup,
		.Package_Doctor,
	}
	workflow: Workflow
	for operation in operations {
		snapshot, started, _ := workflow_begin(&workflow, operation, availability_available())
		testing.expect(t, started)
		testing.expect(t, surface_uses_shared_owner(snapshot.surface))
		_, cancelled, _ := workflow_cancel(&workflow, snapshot.generation)
		testing.expect(t, cancelled)
	}
}

/* Verifies unavailable work is retained with one actionable recovery. */
@(test)
unavailable_operation_retains_failure_without_starting_work :: proc(t: ^testing.T) {
	workflow: Workflow
	availability, copied := availability_unavailable(
		"No catalog endpoint is available.",
		"Retry or inspect confirmed offline state.",
	)
	testing.expect(t, copied)
	snapshot, retained, failure := workflow_begin(
		&workflow,
		.Catalog_Refresh,
		availability,
	)
	testing.expect(t, retained)
	testing.expect_value(t, failure.code, Failure_Code.Unavailable)
	testing.expect_value(t, snapshot.phase, Phase.Failed)
	testing.expect(t, !snapshot.cancellable)
	testing.expect_value(t, text_string(&snapshot.failure), "No catalog endpoint is available.")
	testing.expect_value(
		t,
		text_string(&snapshot.recovery),
		"Retry or inspect confirmed offline state.",
	)
}

/* Verifies UI page and text bounds reject oversized borrowed input. */
@(test)
candidate_and_text_bounds_reject_oversized_input :: proc(t: ^testing.T) {
	oversized_text: [MAX_TEXT_BYTES + 1]u8
	for &value in oversized_text do value = 'a'
	_, text_copied := text_copy(string(oversized_text[:]))
	testing.expect(t, !text_copied)

	workflow: Workflow
	started, started_ok, _ := workflow_begin(&workflow, .Catalog_List, availability_available())
	testing.expect(t, started_ok)
	oversized_page: [MAX_CANDIDATES + 1]Candidate
	_, published, failure := workflow_publish_candidates(
		&workflow,
		started.generation,
		1,
		oversized_page[:],
	)
	testing.expect(t, !published)
	testing.expect_value(t, failure.code, Failure_Code.Limit)
}

/* Verifies selected package releases bind confirmation to readable identity. */
@(test)
package_release_selection_requires_exact_confirmation :: proc(t: ^testing.T) {
	workflow: Workflow
	started, started_ok, _ := workflow_begin(
		&workflow,
		.Package_Install,
		availability_available(),
	)
	testing.expect(t, started_ok)
	requesting, submitted, _ := workflow_submit_prompt(&workflow, started.generation)
	testing.expect(t, submitted)
	release, copied := candidate(
		"odra.rot13@0.1.0",
		"ROT13 0.1.0",
		.Package_Release,
		3,
		9,
		"kasper-snapshot",
		.Current,
	)
	testing.expect(t, copied)
	selecting, published, _ := workflow_publish_candidates(
		&workflow,
		requesting.generation,
		15,
		[]Candidate{release},
	)
	testing.expect(t, published)
	confirming, selected, _ := workflow_select(
		&workflow,
		selecting.generation,
		15,
		0,
	)
	testing.expect(t, selected)
	testing.expect_value(t, confirming.phase, Phase.Confirming)
	testing.expect_value(
		t,
		text_string(&confirming.confirmation.candidate_id),
		"odra.rot13@0.1.0",
	)
}
