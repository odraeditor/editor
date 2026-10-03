// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package layout

import "core:mem"
import "core:testing"

/* Verifies factory policy order, copied request identity, and current generations. */
@(test)
factory_proposal_checks_generation :: proc(t: ^testing.T) {
	fixture: Replacement_Test_Fixture
	if !replacement_test_fixture_init(t, &fixture, 20_701) {
		return
	}
	defer replacement_test_fixture_close(t, &fixture)

	handle, _, _ := registry_handle(&fixture.registry)
	snapshot, snapshot_ok, _ := registry_display_policy_snapshot(&fixture.registry, handle)
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
	valid, validation_failure := registry_display_policy_proposal_validate(
		&fixture.registry,
		&fixture.session,
		proposal,
	)
	testing.expect(t, snapshot_ok && requested && proposed && valid)
	testing.expect_value(t, validation_failure.code, Failure_Code.None)
	testing.expect_value(t, snapshot.generation, Display_Policy_Generation(1))
	testing.expect_value(t, request.layout, handle)
	testing.expect_value(t, request.active_pane.layout, handle)
	testing.expect_value(t, request.entry, fixture.second.entry)
	testing.expect_value(t, proposal.action_count, u16(4))
	testing.expect_value(t, proposal.actions[0].kind, Display_Action_Kind.Reuse_Same_Buffer)
	testing.expect_value(t, proposal.actions[1].kind, Display_Action_Kind.Split_Below)
	testing.expect_value(t, proposal.actions[2].kind, Display_Action_Kind.Split_Right)
	testing.expect_value(t, proposal.actions[3].kind, Display_Action_Kind.Reuse_Least_Recent)
	testing.expect_value(t, proposal.split_height_threshold, DEFAULT_DISPLAY_SPLIT_HEIGHT_THRESHOLD)
	testing.expect_value(t, proposal.split_width_threshold, DEFAULT_DISPLAY_SPLIT_WIDTH_THRESHOLD)
}

/* Verifies complete custom policy replacement and stale proposal rejection. */
@(test)
replacement_invalidates_old_proposals :: proc(t: ^testing.T) {
	fixture: Replacement_Test_Fixture
	if !replacement_test_fixture_init(t, &fixture, 20_711) {
		return
	}
	defer replacement_test_fixture_close(t, &fixture)

	handle, _, _ := registry_handle(&fixture.registry)
	request, _, _ := registry_display_request(&fixture.registry, handle, &fixture.session, fixture.second.entry)
	old_proposal, _, _ := registry_display_policy_factory_proposal(&fixture.registry, &fixture.session, request)
	custom := Display_Policy {
		action_count = 2,
		actions = {
			0 = {kind = .Reuse_Most_Recent},
			1 = {kind = .Split_Right},
		},
		split_height_threshold = 18,
		split_width_threshold = 72,
	}
	replaced, replace_ok, replace_failure := registry_display_policy_replace(
		&fixture.registry,
		Display_Policy_Replacement_Request {
			layout = handle,
			expected_generation = Display_Policy_Generation(1),
			policy = custom,
		},
	)
	testing.expect(t, replace_ok)
	testing.expect_value(t, replace_failure.code, Failure_Code.None)
	testing.expect_value(t, replaced.generation, Display_Policy_Generation(2))
	testing.expect_value(t, replaced.policy, custom)

	old_valid, old_failure := registry_display_policy_proposal_validate(
		&fixture.registry,
		&fixture.session,
		old_proposal,
	)
	testing.expect(t, !old_valid)
	testing.expect_value(t, old_failure.code, Failure_Code.Stale_Display_Policy)
	new_proposal, new_ok, _ := registry_display_policy_factory_proposal(
		&fixture.registry,
		&fixture.session,
		request,
	)
	testing.expect(t, new_ok)
	testing.expect_value(t, new_proposal.action_count, u16(2))
	testing.expect_value(t, new_proposal.actions[0].kind, Display_Action_Kind.Reuse_Most_Recent)
}

/* Verifies malformed, duplicate, and stale copied requests preserve configured state. */
@(test)
rejects_bad_actions_and_stale_layout_requests :: proc(t: ^testing.T) {
	fixture: Replacement_Test_Fixture
	if !replacement_test_fixture_init(t, &fixture, 20_721) {
		return
	}
	defer replacement_test_fixture_close(t, &fixture)

	handle, _, _ := registry_handle(&fixture.registry)
	request, _, _ := registry_display_request(&fixture.registry, handle, &fixture.session, fixture.second.entry)
	proposal, _, _ := registry_display_policy_factory_proposal(&fixture.registry, &fixture.session, request)
	proposal.actions[1] = proposal.actions[0]
	valid, invalid_failure := registry_display_policy_proposal_validate(
		&fixture.registry,
		&fixture.session,
		proposal,
	)
	testing.expect(t, !valid)
	testing.expect_value(t, invalid_failure.code, Failure_Code.Invalid_Display_Action)

	initial, _, _ := registry_snapshot(&fixture.registry, handle)
	split, split_ok, _ := registry_split_below(&fixture.registry, initial.active_pane)
	testing.expect(t, split_ok)
	if !split_ok {
		return
	}
	_, stale_ok, stale_failure := registry_display_policy_factory_proposal(
		&fixture.registry,
		&fixture.session,
		request,
	)
	testing.expect(t, !stale_ok)
	testing.expect_value(t, stale_failure.code, Failure_Code.Stale_Display_Request)
	configured, configured_ok, _ := registry_display_policy_snapshot(&fixture.registry, split.layout)
	testing.expect(t, configured_ok)
	testing.expect_value(t, configured.policy, DEFAULT_DISPLAY_POLICY)
}

/* Verifies factory display creates a below pane, changes only that pane, and preserves focus. */
@(test)
factory_creates_below_without_focus :: proc(t: ^testing.T) {
	fixture: Replacement_Test_Fixture
	if !replacement_test_fixture_init(t, &fixture, 20_731) {
		return
	}
	defer replacement_test_fixture_close(t, &fixture)
	handle, _, _ := registry_handle(&fixture.registry)
	request, _, _ := registry_display_request(&fixture.registry, handle, &fixture.session, fixture.second.entry)
	proposal, _, _ := registry_display_policy_factory_proposal(&fixture.registry, &fixture.session, request)
	displayed, display_ok, display_failure := registry_display_buffer(
		&fixture.registry,
		&fixture.session,
		proposal,
	)
	testing.expect(t, display_ok)
	testing.expect_value(t, display_failure.code, Failure_Code.None)
	testing.expect_value(t, displayed.action, Display_Action_Kind.Split_Below)
	testing.expect(t, displayed.created)
	after, snapshot_ok, _ := registry_snapshot(&fixture.registry, displayed.layout)
	testing.expect(t, snapshot_ok)
	testing.expect_value(t, after.pane_count, u16(2))
	testing.expect_value(t, after.active_pane.pane_id, request.active_pane.pane_id)
	testing.expect_value(t, snapshot_pane(&after, displayed.pane.pane_id).buffer_id, request.buffer_id)
}

/* Verifies same-buffer reuse wins and leaves the layout generation unchanged. */
@(test)
reuses_non_active_same_buffer_before_splitting :: proc(t: ^testing.T) {
	fixture: Replacement_Test_Fixture
	if !replacement_test_fixture_init(t, &fixture, 20_741) {
		return
	}
	defer replacement_test_fixture_close(t, &fixture)
	handle, _, _ := registry_handle(&fixture.registry)
	initial, _, _ := registry_snapshot(&fixture.registry, handle)
	split, split_ok, _ := registry_split_right(&fixture.registry, initial.active_pane)
	testing.expect(t, split_ok)
	if !split_ok {
		return
	}
	request, _, _ := registry_display_request(&fixture.registry, split.layout, &fixture.session, fixture.first.entry)
	proposal, _, _ := registry_display_policy_factory_proposal(&fixture.registry, &fixture.session, request)
	displayed, display_ok, _ := registry_display_buffer(&fixture.registry, &fixture.session, proposal)
	testing.expect(t, display_ok)
	testing.expect_value(t, displayed.action, Display_Action_Kind.Reuse_Same_Buffer)
	testing.expect(t, !displayed.created && !displayed.changed)
	testing.expect_value(t, displayed.layout, split.layout)
	testing.expect_value(t, displayed.pane.pane_id, split.created.pane_id)
}

/* Verifies no eligible reuse or split rejects without changing presentation state. */
@(test)
display_policy_no_destination_is_atomic :: proc(t: ^testing.T) {
	fixture: Replacement_Test_Fixture
	if !replacement_test_fixture_init(t, &fixture, 20_751) {
		return
	}
	defer replacement_test_fixture_close(t, &fixture)
	handle, _, _ := registry_handle(&fixture.registry)
	before, _, _ := registry_snapshot(&fixture.registry, handle)
	request, _, _ := registry_display_request(&fixture.registry, handle, &fixture.session, fixture.second.entry)
	proposal, _, _ := registry_display_policy_factory_proposal(&fixture.registry, &fixture.session, request)
	proposal.action_count = 1
	proposal.actions = {}
	proposal.actions[0] = {kind = .Reuse_Least_Recent}
	_, display_ok, display_failure := registry_display_buffer(&fixture.registry, &fixture.session, proposal)
	after, snapshot_ok, _ := registry_snapshot(&fixture.registry, handle)
	testing.expect(t, !display_ok && snapshot_ok)
	testing.expect_value(t, display_failure.code, Failure_Code.No_Other_Pane)
	testing.expect_value(t, after, before)
}

/* Verifies automatic splitting falls through from the height threshold to the width threshold. */
@(test)
factory_uses_right_split_at_width :: proc(t: ^testing.T) {
	fixture: Replacement_Test_Fixture
	if !replacement_test_fixture_init(t, &fixture, 20_761) {
		return
	}
	defer replacement_test_fixture_close(t, &fixture)
	handle, _, _ := registry_handle(&fixture.registry)
	materialized, materialized_ok, _ := registry_materialize(
		&fixture.registry,
		handle,
		Geometry_Request{rows = 10, columns = 80},
		.Operating,
	)
	testing.expect(t, materialized_ok)
	if !materialized_ok {
		return
	}
	request, _, _ := registry_display_request(
		&fixture.registry,
		materialized,
		&fixture.session,
		fixture.second.entry,
	)
	proposal, _, _ := registry_display_policy_factory_proposal(
		&fixture.registry,
		&fixture.session,
		request,
	)
	displayed, display_ok, _ := registry_display_buffer(&fixture.registry, &fixture.session, proposal)
	testing.expect(t, display_ok)
	testing.expect_value(t, displayed.action, Display_Action_Kind.Split_Right)
}

/* Verifies custom LRU reuse chooses the least-recent non-active pane. */
@(test)
custom_lru_reuses_the_least_recent_eligible_pane :: proc(t: ^testing.T) {
	fixture: Replacement_Test_Fixture
	if !replacement_test_fixture_init(t, &fixture, 20_771) {
		return
	}
	defer replacement_test_fixture_close(t, &fixture)
	handle, _, _ := registry_handle(&fixture.registry)
	initial, _, _ := registry_snapshot(&fixture.registry, handle)
	first_split, first_ok, _ := registry_split_right(&fixture.registry, initial.active_pane)
	testing.expect(t, first_ok)
	if !first_ok {
		return
	}
	current, _, _ := registry_snapshot(&fixture.registry, first_split.layout)
	second_split, second_ok, _ := registry_split_below(&fixture.registry, current.active_pane)
	testing.expect(t, second_ok)
	if !second_ok {
		return
	}
	current, _, _ = registry_snapshot(&fixture.registry, second_split.layout)
	first_other := snapshot_pane(&current, first_split.created.pane_id)
	focused, focused_ok, _ := registry_focus(&fixture.registry, first_other.pane)
	testing.expect(t, focused_ok)
	if !focused_ok {
		return
	}
	current, _, _ = registry_snapshot(&fixture.registry, focused.layout)
	root := snapshot_pane(&current, initial.active_pane.pane_id)
	focused, focused_ok, _ = registry_focus(&fixture.registry, root.pane)
	testing.expect(t, focused_ok)
	if !focused_ok {
		return
	}
	current, _, _ = registry_snapshot(&fixture.registry, focused.layout)
	expected_lru := Pane_ID(0)
	expected_rank := u16(0)
	for index in 0 ..< int(current.node_count) {
		node := current.nodes[index]
		if node.kind == .Pane && !node.active &&
		   (expected_lru == Pane_ID(0) || node.mru_rank > expected_rank) {
			expected_lru = node.pane.pane_id
			expected_rank = node.mru_rank
		}
	}
	custom := Display_Policy {
		action_count = 1,
		actions = {0 = {kind = .Reuse_Least_Recent}},
		split_height_threshold = 1,
		split_width_threshold = 1,
	}
	configured, configured_ok, _ := registry_display_policy_replace(
		&fixture.registry,
		Display_Policy_Replacement_Request {
			layout = focused.layout,
			expected_generation = Display_Policy_Generation(1),
			policy = custom,
		},
	)
	testing.expect(t, configured_ok)
	request, _, _ := registry_display_request(
		&fixture.registry,
		configured.layout,
		&fixture.session,
		fixture.second.entry,
	)
	proposal, _, _ := registry_display_policy_factory_proposal(
		&fixture.registry,
		&fixture.session,
		request,
	)
	displayed, display_ok, _ := registry_display_buffer(&fixture.registry, &fixture.session, proposal)
	testing.expect(t, display_ok)
	testing.expect_value(t, displayed.action, Display_Action_Kind.Reuse_Least_Recent)
	testing.expect_value(t, displayed.pane.pane_id, expected_lru)
	testing.expect_value(t, displayed.layout.generation, Layout_Generation(u64(focused.layout.generation) + 1))
}

/* Verifies inadmissible configured splits reject atomically instead of using the active pane. */
@(test)
inadmissible_splits_preserve_the_only_pane :: proc(t: ^testing.T) {
	fixture: Replacement_Test_Fixture
	if !replacement_test_fixture_init(t, &fixture, 20_781) {
		return
	}
	defer replacement_test_fixture_close(t, &fixture)
	handle, _, _ := registry_handle(&fixture.registry)
	materialized, materialized_ok, _ := registry_materialize(
		&fixture.registry,
		handle,
		Geometry_Request{rows = 4, columns = 8},
		.Operating,
	)
	testing.expect(t, materialized_ok)
	if !materialized_ok {
		return
	}
	custom := Display_Policy {
		action_count = 2,
		actions = {
			0 = {kind = .Split_Below},
			1 = {kind = .Split_Right},
		},
		split_height_threshold = 1,
		split_width_threshold = 1,
	}
	configured, configured_ok, _ := registry_display_policy_replace(
		&fixture.registry,
		Display_Policy_Replacement_Request {
			layout = materialized,
			expected_generation = Display_Policy_Generation(1),
			policy = custom,
		},
	)
	testing.expect(t, configured_ok)
	before, _, _ := registry_snapshot(&fixture.registry, configured.layout)
	request, _, _ := registry_display_request(
		&fixture.registry,
		configured.layout,
		&fixture.session,
		fixture.second.entry,
	)
	proposal, _, _ := registry_display_policy_factory_proposal(
		&fixture.registry,
		&fixture.session,
		request,
	)
	_, displayed, display_failure := registry_display_buffer(&fixture.registry, &fixture.session, proposal)
	after, after_ok, _ := registry_snapshot(&fixture.registry, configured.layout)
	testing.expect(t, !displayed && after_ok)
	testing.expect_value(t, display_failure.code, Failure_Code.No_Other_Pane)
	testing.expect_value(t, after, before)
}

/* Verifies successful display publication has exact accounting and releases all storage. */
@(test)
publication_accounts_and_cleans_up_all_storage :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	allocator := mem.tracking_allocator(&tracking)
	fixture: Replacement_Test_Fixture
	if !replacement_test_fixture_init(t, &fixture, 20_791, allocator) {
		return
	}
	handle, _, _ := registry_handle(&fixture.registry)
	before, _, _ := registry_stats(&fixture.registry)
	request, _, _ := registry_display_request(
		&fixture.registry,
		handle,
		&fixture.session,
		fixture.second.entry,
	)
	proposal, _, _ := registry_display_policy_factory_proposal(
		&fixture.registry,
		&fixture.session,
		request,
	)
	displayed, display_ok, _ := registry_display_buffer(&fixture.registry, &fixture.session, proposal)
	after, after_ok, _ := registry_stats(&fixture.registry)
	testing.expect(t, display_ok && after_ok)
	testing.expect_value(t, after.node_count, before.node_count + 2)
	testing.expect_value(t, after.pane_count, before.pane_count + 1)
	testing.expect_value(t, after.partition_count, before.partition_count + 1)
	testing.expect_value(t, after.display_policy_generation, before.display_policy_generation)
	testing.expect_value(t, after.handle, displayed.layout)
	replacement_test_fixture_close(t, &fixture)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
}
