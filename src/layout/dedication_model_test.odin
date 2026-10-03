// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package layout

import "core:testing"

/* Verifies generated dedication transitions against a minimal state-and-generation model. */
@(test)
dedication_transitions_match_model :: proc(t: ^testing.T) {
	fixture: Replacement_Test_Fixture
	if !replacement_test_fixture_init(t, &fixture, 20_861) {
		return
	}
	defer replacement_test_fixture_close(t, &fixture)

	handle, _, _ := registry_handle(&fixture.registry)
	snapshot, _, _ := registry_snapshot(&fixture.registry, handle)
	pane := snapshot.active_pane
	model_state := Pane_Dedication.None
	model_generation := handle.generation
	state := u64(0x6a09e667f3bcc909)
	for _ in 0 ..< 512 {
		state = state * 6_364_136_223_846_793_005 + 1_442_695_040_888_963_407
		requested := Pane_Dedication((state >> 32) % 3)
		expected_changed := requested != model_state
		result, changed_ok, failure := registry_pane_dedication_set(
			&fixture.registry,
			pane,
			requested,
		)
		testing.expect(t, changed_ok)
		testing.expect_value(t, failure.code, Failure_Code.None)
		if !changed_ok {
			return
		}
		if expected_changed {
			model_generation = Layout_Generation(u64(model_generation) + 1)
		}
		testing.expect_value(t, result.previous, model_state)
		testing.expect_value(t, result.current, requested)
		testing.expect_value(t, result.changed, expected_changed)
		testing.expect_value(t, result.layout.generation, model_generation)
		model_state = requested
		pane = result.pane
		observed, observed_ok, _ := registry_pane_dedication_inspect(&fixture.registry, pane)
		stats, stats_ok, _ := registry_stats(&fixture.registry)
		testing.expect(t, observed_ok && stats_ok)
		testing.expect_value(t, observed.dedication, model_state)
		testing.expect_value(t, stats.soft_dedicated_panes, u16(1) if model_state == .Soft else 0)
		testing.expect_value(t, stats.hard_dedicated_panes, u16(1) if model_state == .Hard else 0)
	}
}

/* Verifies policy reuse selects the sole ordinary pane across dedicated competitors. */
@(test)
policy_reuses_only_nondedicated_candidate :: proc(t: ^testing.T) {
	fixture: Replacement_Test_Fixture
	if !replacement_test_fixture_init(t, &fixture, 20_871) {
		return
	}
	defer replacement_test_fixture_close(t, &fixture)

	handle, _, _ := registry_handle(&fixture.registry)
	initial, _, _ := registry_snapshot(&fixture.registry, handle)
	first_split, first_ok, _ := registry_split_right(&fixture.registry, initial.active_pane)
	if !first_ok {
		testing.expect(t, false)
		return
	}
	second_split, second_ok, _ := registry_split_below(&fixture.registry, first_split.original)
	if !second_ok {
		testing.expect(t, false)
		return
	}
	before_soft, _, _ := registry_snapshot(&fixture.registry, second_split.layout)
	soft_target := snapshot_pane(&before_soft, first_split.created.pane_id).pane
	soft, soft_ok, _ := registry_pane_dedication_set(&fixture.registry, soft_target, .Soft)
	if !soft_ok {
		testing.expect(t, false)
		return
	}
	before_hard, _, _ := registry_snapshot(&fixture.registry, soft.layout)
	hard_target := snapshot_pane(&before_hard, first_split.original.pane_id).pane
	hard, hard_ok, _ := registry_pane_dedication_set(&fixture.registry, hard_target, .Hard)
	if !hard_ok {
		testing.expect(t, false)
		return
	}
	request, requested, _ := registry_display_request(
		&fixture.registry,
		hard.layout,
		&fixture.session,
		fixture.second.entry,
	)
	proposal, proposed, _ := registry_display_policy_factory_proposal(
		&fixture.registry,
		&fixture.session,
		request,
	)
	proposal.action_count = 1
	proposal.actions = {}
	proposal.actions[0] = {kind = .Reuse_Least_Recent}
	displayed, displayed_ok, display_failure := registry_display_buffer(
		&fixture.registry,
		&fixture.session,
		proposal,
	)
	testing.expect(t, requested && proposed && displayed_ok)
	testing.expect_value(t, display_failure.code, Failure_Code.None)
	testing.expect_value(t, displayed.pane.pane_id, second_split.created.pane_id)
	after, after_ok, _ := registry_snapshot(&fixture.registry, displayed.layout)
	testing.expect(t, after_ok)
	testing.expect_value(t, snapshot_pane(&after, soft_target.pane_id).dedication, Pane_Dedication.Soft)
	testing.expect_value(t, snapshot_pane(&after, hard_target.pane_id).dedication, Pane_Dedication.Hard)
}
