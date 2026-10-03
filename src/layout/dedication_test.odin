// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package layout

import "../view"
import "core:testing"

/* Verifies dedication transitions, copied inspection, layout generation, and exact accounting. */
@(test)
dedication_transitions_are_observable :: proc(t: ^testing.T) {
	fixture: Replacement_Test_Fixture
	if !replacement_test_fixture_init(t, &fixture, 20_801) {
		return
	}
	defer replacement_test_fixture_close(t, &fixture)

	handle, _, _ := registry_handle(&fixture.registry)
	initial, _, _ := registry_snapshot(&fixture.registry, handle)
	inspected, inspect_ok, _ := registry_pane_dedication_inspect(
		&fixture.registry,
		initial.active_pane,
	)
	initial_stats, stats_ok, _ := registry_stats(&fixture.registry)
	testing.expect(t, inspect_ok && stats_ok)
	testing.expect_value(t, inspected.dedication, Pane_Dedication.None)
	testing.expect_value(t, initial.nodes[0].dedication, Pane_Dedication.None)
	testing.expect_value(t, initial_stats.soft_dedicated_panes, u16(0))
	testing.expect_value(t, initial_stats.hard_dedicated_panes, u16(0))
	request, requested, _ := registry_display_request(
		&fixture.registry,
		handle,
		&fixture.session,
		fixture.second.entry,
	)
	proposal, proposed, _ := registry_display_policy_factory_proposal(
		&fixture.registry,
		&fixture.session,
		request,
	)
	testing.expect(t, requested && proposed)
	testing.expect(t, proposal.eligibility.exclude_dedicated)

	soft, soft_ok, soft_failure := registry_pane_dedication_set(
		&fixture.registry,
		initial.active_pane,
		.Soft,
	)
	testing.expect(t, soft_ok)
	testing.expect_value(t, soft_failure.code, Failure_Code.None)
	testing.expect_value(t, soft.previous, Pane_Dedication.None)
	testing.expect_value(t, soft.current, Pane_Dedication.Soft)
	testing.expect(t, soft.changed)
	testing.expect_value(t, soft.layout.generation, Layout_Generation(u64(handle.generation) + 1))

	unchanged, unchanged_ok, _ := registry_pane_dedication_set(
		&fixture.registry,
		soft.pane,
		.Soft,
	)
	testing.expect(t, unchanged_ok && !unchanged.changed)
	testing.expect_value(t, unchanged.layout, soft.layout)
	testing.expect_value(t, unchanged.previous, Pane_Dedication.Soft)
	testing.expect_value(t, unchanged.current, Pane_Dedication.Soft)

	hard, hard_ok, _ := registry_pane_dedication_set(&fixture.registry, unchanged.pane, .Hard)
	testing.expect(t, hard_ok && hard.changed)
	after_hard, after_hard_ok, _ := registry_snapshot(&fixture.registry, hard.layout)
	hard_stats, hard_stats_ok, _ := registry_stats(&fixture.registry)
	testing.expect(t, after_hard_ok && hard_stats_ok)
	testing.expect_value(t, snapshot_pane(&after_hard, hard.pane.pane_id).dedication, Pane_Dedication.Hard)
	testing.expect_value(t, hard_stats.soft_dedicated_panes, u16(0))
	testing.expect_value(t, hard_stats.hard_dedicated_panes, u16(1))

	cleared, clear_ok, _ := registry_pane_dedication_set(&fixture.registry, hard.pane, .None)
	testing.expect(t, clear_ok && cleared.changed)
	cleared_stats, cleared_stats_ok, _ := registry_stats(&fixture.registry)
	testing.expect(t, cleared_stats_ok)
	testing.expect_value(t, cleared_stats.soft_dedicated_panes, u16(0))
	testing.expect_value(t, cleared_stats.hard_dedicated_panes, u16(0))
}

/* Verifies invalid and stale dedication requests reject without publishing state. */
@(test)
dedication_rejects_stale_requests :: proc(t: ^testing.T) {
	fixture: Replacement_Test_Fixture
	if !replacement_test_fixture_init(t, &fixture, 20_811) {
		return
	}
	defer replacement_test_fixture_close(t, &fixture)

	handle, _, _ := registry_handle(&fixture.registry)
	initial, _, _ := registry_snapshot(&fixture.registry, handle)
	_, invalid_ok, invalid_failure := registry_pane_dedication_set(
		&fixture.registry,
		initial.active_pane,
		Pane_Dedication(255),
	)
	after_invalid, after_invalid_ok, _ := registry_snapshot(&fixture.registry, handle)
	testing.expect(t, !invalid_ok && after_invalid_ok)
	testing.expect_value(t, invalid_failure.code, Failure_Code.Invalid_Dedication)
	testing.expect_value(t, invalid_failure.operation, Operation.Set_Dedication)
	testing.expect_value(t, invalid_failure.dedication, Pane_Dedication(255))
	testing.expect_value(t, after_invalid, initial)

	split, split_ok, _ := registry_split_right(&fixture.registry, initial.active_pane)
	testing.expect(t, split_ok)
	if !split_ok {
		return
	}
	_, stale_ok, stale_failure := registry_pane_dedication_set(
		&fixture.registry,
		initial.active_pane,
		.Soft,
	)
	after_stale, after_stale_ok, _ := registry_snapshot(&fixture.registry, split.layout)
	testing.expect(t, !stale_ok && after_stale_ok)
	testing.expect_value(t, stale_failure.code, Failure_Code.Stale_Layout)
	testing.expect_value(t, after_stale.handle, split.layout)
	testing.expect_value(t, after_stale.pane_count, u16(2))
}

/* Verifies splitting preserves source dedication and creates one ordinary pane. */
@(test)
pane_dedication_is_pane_owned_across_split :: proc(t: ^testing.T) {
	fixture: Replacement_Test_Fixture
	if !replacement_test_fixture_init(t, &fixture, 20_821) {
		return
	}
	defer replacement_test_fixture_close(t, &fixture)

	handle, _, _ := registry_handle(&fixture.registry)
	initial, _, _ := registry_snapshot(&fixture.registry, handle)
	dedicated, dedicated_ok, _ := registry_pane_dedication_set(
		&fixture.registry,
		initial.active_pane,
		.Soft,
	)
	testing.expect(t, dedicated_ok)
	if !dedicated_ok {
		return
	}
	split, split_ok, _ := registry_split_below(&fixture.registry, dedicated.pane)
	testing.expect(t, split_ok)
	if !split_ok {
		return
	}
	after, snapshot_ok, _ := registry_snapshot(&fixture.registry, split.layout)
	stats, stats_ok, _ := registry_stats(&fixture.registry)
	testing.expect(t, snapshot_ok && stats_ok)
	testing.expect_value(t, snapshot_pane(&after, split.original.pane_id).dedication, Pane_Dedication.Soft)
	testing.expect_value(t, snapshot_pane(&after, split.created.pane_id).dedication, Pane_Dedication.None)
	testing.expect_value(t, stats.soft_dedicated_panes, u16(1))
	testing.expect_value(t, stats.hard_dedicated_panes, u16(0))
}

/* Verifies soft dedication permits explicit replacement and remains pane-owned. */
@(test)
soft_dedication_survives_replacement :: proc(t: ^testing.T) {
	fixture: Replacement_Test_Fixture
	if !replacement_test_fixture_init(t, &fixture, 20_831) {
		return
	}
	defer replacement_test_fixture_close(t, &fixture)

	handle, _, _ := registry_handle(&fixture.registry)
	initial, _, _ := registry_snapshot(&fixture.registry, handle)
	dedicated, dedicated_ok, _ := registry_pane_dedication_set(
		&fixture.registry,
		initial.active_pane,
		.Soft,
	)
	if !dedicated_ok {
		testing.expect(t, false)
		return
	}
	replaced, replaced_ok, replacement_failure := registry_replace_pane_buffer(
		&fixture.registry,
		dedicated.pane,
		&fixture.session,
		fixture.second.entry,
	)
	testing.expect(t, replaced_ok)
	testing.expect_value(t, replacement_failure.code, Failure_Code.None)
	if !replaced_ok {
		return
	}
	inspected, inspected_ok, _ := registry_pane_dedication_inspect(
		&fixture.registry,
		replaced.pane,
	)
	testing.expect(t, inspected_ok)
	testing.expect_value(t, inspected.dedication, Pane_Dedication.Soft)
	testing.expect_value(t, inspected.pane.pane_id, initial.active_pane.pane_id)
}

/* Verifies hard dedication rejects explicit replacement before any state changes. */
@(test)
hard_dedication_rejects_replacement :: proc(t: ^testing.T) {
	fixture: Replacement_Test_Fixture
	if !replacement_test_fixture_init(t, &fixture, 20_841) {
		return
	}
	defer replacement_test_fixture_close(t, &fixture)

	handle, _, _ := registry_handle(&fixture.registry)
	initial, _, _ := registry_snapshot(&fixture.registry, handle)
	dedicated, dedicated_ok, _ := registry_pane_dedication_set(
		&fixture.registry,
		initial.active_pane,
		.Hard,
	)
	if !dedicated_ok {
		testing.expect(t, false)
		return
	}
	before, _, _ := registry_snapshot(&fixture.registry, dedicated.layout)
	views_before, _, _ := view.registry_stats(fixture.views)
	_, replaced_ok, replacement_failure := registry_replace_pane_buffer(
		&fixture.registry,
		dedicated.pane,
		&fixture.session,
		fixture.second.entry,
	)
	after, after_ok, _ := registry_snapshot(&fixture.registry, dedicated.layout)
	views_after, views_after_ok, _ := view.registry_stats(fixture.views)
	testing.expect(t, !replaced_ok && after_ok && views_after_ok)
	testing.expect_value(t, replacement_failure.code, Failure_Code.Dedication_Conflict)
	testing.expect_value(t, replacement_failure.operation, Operation.Replace_Buffer)
	testing.expect_value(t, replacement_failure.pane, dedicated.pane)
	testing.expect_value(t, replacement_failure.dedication, Pane_Dedication.Hard)
	testing.expect_value(t, after, before)
	testing.expect_value(t, views_after, views_before)
}

/* Verifies automatic same-buffer and recency reuse exclude soft and hard panes. */
@(test)
automatic_display_reuse_excludes_dedicated_panes :: proc(t: ^testing.T) {
	fixture: Replacement_Test_Fixture
	if !replacement_test_fixture_init(t, &fixture, 20_851) {
		return
	}
	defer replacement_test_fixture_close(t, &fixture)

	handle, _, _ := registry_handle(&fixture.registry)
	initial, _, _ := registry_snapshot(&fixture.registry, handle)
	split, split_ok, _ := registry_split_right(&fixture.registry, initial.active_pane)
	if !split_ok {
		testing.expect(t, false)
		return
	}
	dedicated, dedicated_ok, _ := registry_pane_dedication_set(
		&fixture.registry,
		split.created,
		.Soft,
	)
	if !dedicated_ok {
		testing.expect(t, false)
		return
	}
	request, requested, _ := registry_display_request(
		&fixture.registry,
		dedicated.layout,
		&fixture.session,
		fixture.first.entry,
	)
	proposal, proposed, _ := registry_display_policy_factory_proposal(
		&fixture.registry,
		&fixture.session,
		request,
	)
	proposal.action_count = 1
	proposal.actions = {}
	proposal.actions[0] = {kind = .Reuse_Same_Buffer}
	_, displayed, display_failure := registry_display_buffer(
		&fixture.registry,
		&fixture.session,
		proposal,
	)
	testing.expect(t, requested && proposed && !displayed)
	testing.expect_value(t, display_failure.code, Failure_Code.No_Other_Pane)

	hard, hard_ok, _ := registry_pane_dedication_set(&fixture.registry, dedicated.pane, .Hard)
	if !hard_ok {
		testing.expect(t, false)
		return
	}
	hard_request, hard_requested, _ := registry_display_request(
		&fixture.registry,
		hard.layout,
		&fixture.session,
		fixture.second.entry,
	)
	hard_proposal, hard_proposed, _ := registry_display_policy_factory_proposal(
		&fixture.registry,
		&fixture.session,
		hard_request,
	)
	hard_proposal.action_count = 1
	hard_proposal.actions = {}
	hard_proposal.actions[0] = {kind = .Reuse_Least_Recent}
	_, hard_displayed, hard_failure := registry_display_buffer(
		&fixture.registry,
		&fixture.session,
		hard_proposal,
	)
	testing.expect(t, hard_requested && hard_proposed && !hard_displayed)
	testing.expect_value(t, hard_failure.code, Failure_Code.No_Other_Pane)
}
