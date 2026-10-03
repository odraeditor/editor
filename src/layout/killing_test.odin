// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package layout

import "../editor_session"
import "../view"
import "core:mem"
import "core:testing"

/* Verifies dirty admission leaves pane, session, and view state unchanged. */
@(test)
kill_protects_modified_before_layout :: proc(t: ^testing.T) {
	fixture: Replacement_Test_Fixture
	if !replacement_test_fixture_init(t, &fixture, 20_601) {
		return
	}
	defer replacement_test_fixture_close(t, &fixture)
	handle, _, _ := registry_handle(&fixture.registry)
	before, _, _ := registry_snapshot(&fixture.registry, handle)
	view_before, _, _ := view.registry_stats(fixture.views)
	usage_before, _, _ := editor_session.session_usage(&fixture.session, fixture.handle)

	result, killed, failure := registry_kill_buffer(
		&fixture.registry,
		&fixture.session,
		fixture.first.entry,
	)
	testing.expect(t, killed)
	testing.expect_value(t, failure.code, Failure_Code.None)
	testing.expect_value(t, result.outcome, Kill_Outcome.Discard_Required)
	after, after_ok, _ := registry_snapshot(&fixture.registry, handle)
	view_after, _, _ := view.registry_stats(fixture.views)
	usage_after, _, _ := editor_session.session_usage(&fixture.session, fixture.handle)
	testing.expect(t, after_ok)
	testing.expect_value(t, after, before)
	testing.expect_value(t, view_after, view_before)
	testing.expect_value(t, usage_after, usage_before)
}

/* Verifies one killed buffer is excluded from every pane, history, list, and view graph. */
@(test)
kill_replaces_panes_and_purges_state :: proc(t: ^testing.T) {
	fixture: Replacement_Test_Fixture
	if !replacement_test_fixture_init(t, &fixture, 20_611) {
		return
	}
	defer replacement_test_fixture_close(t, &fixture)

	handle, _, _ := registry_handle(&fixture.registry)
	initial, _, _ := registry_snapshot(&fixture.registry, handle)
	second, second_ok, _ := registry_replace_pane_buffer(
		&fixture.registry,
		initial.active_pane,
		&fixture.session,
		fixture.second.entry,
	)
	first, first_ok, _ := registry_replace_pane_buffer(
		&fixture.registry,
		second.pane,
		&fixture.session,
		fixture.first.entry,
	)
	testing.expect(t, second_ok && first_ok)
	if !second_ok || !first_ok {
		return
	}
	first_split, split_ok, _ := registry_split_right(&fixture.registry, first.pane)
	if !split_ok {
		testing.expect(t, false)
		return
	}
	_, second_split_ok, _ := registry_split_below(&fixture.registry, first_split.original)
	testing.expect(t, second_split_ok)
	if !second_split_ok {
		return
	}

	result, killed, kill_failure := registry_kill_buffer(
		&fixture.registry,
		&fixture.session,
		fixture.first.entry,
		.Discard_Modified,
	)
	testing.expect(t, killed)
	testing.expect_value(t, kill_failure.code, Failure_Code.None)
	testing.expect_value(t, result.outcome, Kill_Outcome.Killed)
	testing.expect_value(t, result.replacements, u16(3))
	if !killed {
		return
	}
	after, after_ok, _ := registry_snapshot(&fixture.registry, result.layout)
	testing.expect(t, after_ok)
	for node in after.nodes[:after.node_count] {
		if node.kind != .Pane {
			continue
		}
		testing.expect_value(t, node.entry, fixture.second.entry)
		history, history_ok, _ := registry_pane_history_snapshot(&fixture.registry, node.pane)
		testing.expect(t, history_ok)
		for candidate in history.entries[:history.count] {
			testing.expect(t, candidate.state.entry != fixture.first.entry)
		}
	}
	list, list_ok, _ := registry_buffer_list_snapshot(&fixture.registry, result.layout)
	testing.expect(t, list_ok)
	for candidate in list.entries[:list.count] {
		testing.expect(t, candidate.entry != fixture.first.entry)
	}
	_, first_live, _ := editor_session.session_entry_access(&fixture.session, fixture.first.entry)
	usage, usage_ok, _ := editor_session.session_usage(&fixture.session, fixture.handle)
	view_stats, view_ok, _ := view.registry_stats(fixture.views)
	testing.expect(t, !first_live && usage_ok && view_ok)
	testing.expect_value(t, usage.live_buffers, u32(2))
	testing.expect_value(t, view_stats.retained_count, u16(2))
	testing.expect_value(t, view_stats.additional_count, u16(2))
}

/* Verifies each normal pane prefers its own prior buffer before top-level recency. */
@(test)
coordinated_kill_prefers_each_pane_local_history :: proc(t: ^testing.T) {
	fixture: Replacement_Test_Fixture
	if !replacement_test_fixture_init(t, &fixture, 20_621) {
		return
	}
	defer replacement_test_fixture_close(t, &fixture)
	handle, _, _ := registry_handle(&fixture.registry)
	initial, _, _ := registry_snapshot(&fixture.registry, handle)
	second, _, _ := registry_replace_pane_buffer(
		&fixture.registry,
		initial.active_pane,
		&fixture.session,
		fixture.second.entry,
	)
	first, _, _ := registry_replace_pane_buffer(
		&fixture.registry,
		second.pane,
		&fixture.session,
		fixture.first.entry,
	)
	split, split_ok, _ := registry_split_right(&fixture.registry, first.pane)
	testing.expect(t, split_ok)
	if !split_ok {
		return
	}
	third, third_ok, _ := registry_replace_pane_buffer(
		&fixture.registry,
		split.created,
		&fixture.session,
		fixture.third.entry,
	)
	created_first, first_ok, _ := registry_replace_pane_buffer(
		&fixture.registry,
		third.pane,
		&fixture.session,
		fixture.first.entry,
	)
	testing.expect(t, third_ok && first_ok)
	if !third_ok || !first_ok {
		return
	}
	result, killed, _ := registry_kill_buffer(
		&fixture.registry,
		&fixture.session,
		fixture.first.entry,
		.Discard_Modified,
	)
	testing.expect(t, killed)
	if !killed {
		return
	}
	after, _, _ := registry_snapshot(&fixture.registry, result.layout)
	original := snapshot_pane(&after, split.original.pane_id)
	created := snapshot_pane(&after, created_first.pane.pane_id)
	testing.expect_value(t, original.entry, fixture.second.entry)
	testing.expect_value(t, created.entry, fixture.third.entry)
}

/* Verifies an explicit factory scratch preserves the final displayed pane invariant. */
@(test)
kill_uses_scratch_for_final_buffer :: proc(t: ^testing.T) {
	fixture: Replacement_Test_Fixture
	if !replacement_test_fixture_init(t, &fixture, 20_631) {
		return
	}
	defer replacement_test_fixture_close(t, &fixture)
	replacement_test_close_entry(t, &fixture.session, fixture.third.entry)
	replacement_test_close_entry(t, &fixture.session, fixture.second.entry)
	scratch, scratch_ok, _ := editor_session.session_create_buffer(
		&fixture.session,
		editor_session.Create_Buffer_Request {
			session = fixture.handle,
			name = "*scratch*",
			configuration = editor_session.DEFAULT_ENTRY_CONFIGURATION,
		},
	)
	testing.expect(t, scratch_ok)
	if !scratch_ok {
		return
	}
	fixture.third = scratch
	handle, _, _ := registry_handle(&fixture.registry)
	before, _, _ := registry_snapshot(&fixture.registry, handle)
	_, dedicated_ok, _ := registry_pane_dedication_set(
		&fixture.registry,
		before.active_pane,
		.Hard,
	)
	testing.expect(t, dedicated_ok)
	if !dedicated_ok {
		return
	}
	result, killed, kill_failure := registry_kill_buffer(
		&fixture.registry,
		&fixture.session,
		fixture.first.entry,
		.Discard_Modified,
		scratch.entry,
	)
	testing.expect(t, killed)
	testing.expect_value(t, kill_failure.code, Failure_Code.None)
	testing.expect_value(t, result.outcome, Kill_Outcome.Killed)
	if !killed {
		return
	}
	after, after_ok, _ := registry_snapshot(&fixture.registry, result.layout)
	usage, usage_ok, _ := editor_session.session_usage(&fixture.session, fixture.handle)
	visible, visible_ok, _ := editor_session.session_visible_target(&fixture.session, fixture.handle)
	testing.expect(t, after_ok && usage_ok && visible_ok)
	testing.expect_value(t, after.pane_count, u16(1))
	testing.expect_value(t, after.nodes[0].entry, scratch.entry)
	testing.expect_value(t, after.nodes[0].dedication, Pane_Dedication.None)
	testing.expect_value(t, visible.entry, scratch.entry)
	testing.expect_value(t, usage.live_buffers, u32(1))
}

/* Verifies full pane capacity reuses outgoing additional views during coordinated kill. */
@(test)
kill_reuses_views_at_pane_capacity :: proc(t: ^testing.T) {
	fixture: Replacement_Test_Fixture
	if !replacement_test_fixture_init(t, &fixture, 20_641) {
		return
	}
	defer replacement_test_fixture_close(t, &fixture)
	handle, _, _ := registry_handle(&fixture.registry)
	initial, _, _ := registry_snapshot(&fixture.registry, handle)
	second, second_ok, _ := registry_replace_pane_buffer(
		&fixture.registry,
		initial.active_pane,
		&fixture.session,
		fixture.second.entry,
	)
	first, first_ok, _ := registry_replace_pane_buffer(
		&fixture.registry,
		second.pane,
		&fixture.session,
		fixture.first.entry,
	)
	testing.expect(t, second_ok && first_ok)
	if !second_ok || !first_ok {
		return
	}
	_, materialized, _ := registry_materialize(
		&fixture.registry,
		first.layout,
		Geometry_Request{rows = 4_096, columns = 4_096},
		.Operating,
	)
	testing.expect(t, materialized)
	if !materialized {
		return
	}
	for pane_count in 1 ..< MAX_LIVE_PANES {
		handle, _, _ = registry_handle(&fixture.registry)
		before, _, _ := registry_snapshot(&fixture.registry, handle)
		target: Pane_Handle
		minimum_depth := max(u16)
		for node in before.nodes[:before.node_count] {
			if node.kind == .Pane && node.depth < minimum_depth {
				target = node.pane
				minimum_depth = node.depth
			}
		}
		_, focused, _ := registry_focus(&fixture.registry, target)
		if !focused {
			testing.expect(t, false)
			return
		}
		handle, _, _ = registry_handle(&fixture.registry)
		focused_snapshot, _, _ := registry_snapshot(&fixture.registry, handle)
		_, split_ok, _ := registry_split_right(&fixture.registry, focused_snapshot.active_pane)
		if !split_ok {
			testing.expectf(t, false, "split failed at pane %d", pane_count)
			return
		}
	}
	view_before, view_ok, _ := view.registry_stats(fixture.views)
	testing.expect(t, view_ok)
	testing.expect_value(t, view_before.additional_count, u16(MAX_LIVE_PANES - 1))
	result, killed, kill_failure := registry_kill_buffer(
		&fixture.registry,
		&fixture.session,
		fixture.first.entry,
		.Discard_Modified,
	)
	testing.expect(t, killed)
	testing.expect_value(t, kill_failure.code, Failure_Code.None)
	if !killed {
		return
	}
	after, after_ok, _ := registry_snapshot(&fixture.registry, result.layout)
	view_after, view_after_ok, _ := view.registry_stats(fixture.views)
	testing.expect(t, after_ok && view_after_ok)
	testing.expect_value(t, after.pane_count, u16(MAX_LIVE_PANES))
	testing.expect_value(t, view_after.additional_count, u16(MAX_LIVE_PANES - 1))
	for node in after.nodes[:after.node_count] {
		if node.kind == .Pane {
			testing.expect_value(t, node.entry, fixture.second.entry)
		}
	}
}

/* Verifies missing fallback rejection preserves layout, view, and session state exactly. */
@(test)
kill_rolls_back_without_fallback :: proc(t: ^testing.T) {
	fixture: Replacement_Test_Fixture
	if !replacement_test_fixture_init(t, &fixture, 20_651) {
		return
	}
	defer replacement_test_fixture_close(t, &fixture)
	replacement_test_close_entry(t, &fixture.session, fixture.third.entry)
	replacement_test_close_entry(t, &fixture.session, fixture.second.entry)
	handle, _, _ := registry_handle(&fixture.registry)
	before, _, _ := registry_snapshot(&fixture.registry, handle)
	active := snapshot_pane(&before, before.active_pane.pane_id)
	view_before, view_ok, _ := view.snapshot(fixture.views, active.view)
	view_stats_before, stats_ok, _ := view.registry_stats(fixture.views)
	usage_before, usage_ok, _ := editor_session.session_usage(&fixture.session, fixture.handle)
	testing.expect(t, view_ok && stats_ok && usage_ok)

	_, killed, kill_failure := registry_kill_buffer(
		&fixture.registry,
		&fixture.session,
		fixture.first.entry,
		.Discard_Modified,
	)
	testing.expect(t, !killed)
	testing.expect_value(t, kill_failure.code, Failure_Code.No_Fallback)
	after, after_ok, _ := registry_snapshot(&fixture.registry, handle)
	view_after, view_after_ok, _ := view.snapshot(fixture.views, active.view)
	view_stats_after, stats_after_ok, _ := view.registry_stats(fixture.views)
	usage_after, usage_after_ok, _ := editor_session.session_usage(&fixture.session, fixture.handle)
	testing.expect(t, after_ok && view_after_ok && stats_after_ok && usage_after_ok)
	testing.expect_value(t, after, before)
	testing.expect_value(t, view_after, view_before)
	testing.expect_value(t, view_stats_after, view_stats_before)
	testing.expect_value(t, usage_after, usage_before)
}

/* Verifies prepared-layout allocation failure leaves every published owner unchanged. */
@(test)
kill_rolls_back_on_prepared_alloc_fault :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	failing := Layout_Failing_Allocator {
		backing = mem.tracking_allocator(&tracking),
		fail_after = max(u64),
	}
	fixture: Replacement_Test_Fixture
	if !replacement_test_fixture_init(
		t,
		&fixture,
		20_661,
		layout_failing_allocator(&failing),
	) {
		mem.tracking_allocator_destroy(&tracking)
		return
	}
	defer {
		failing.fail_after = max(u64)
		replacement_test_fixture_close(t, &fixture)
		mem.tracking_allocator_destroy(&tracking)
	}
	handle, _, _ := registry_handle(&fixture.registry)
	initial, _, _ := registry_snapshot(&fixture.registry, handle)
	second, second_ok, _ := registry_replace_pane_buffer(
		&fixture.registry,
		initial.active_pane,
		&fixture.session,
		fixture.second.entry,
	)
	_, first_ok, _ := registry_replace_pane_buffer(
		&fixture.registry,
		second.pane,
		&fixture.session,
		fixture.first.entry,
	)
	testing.expect(t, second_ok && first_ok)
	if !second_ok || !first_ok {
		return
	}
	handle, _, _ = registry_handle(&fixture.registry)
	before, _, _ := registry_snapshot(&fixture.registry, handle)
	active := snapshot_pane(&before, before.active_pane.pane_id)
	view_before, _, _ := view.snapshot(fixture.views, active.view)
	view_stats_before, _, _ := view.registry_stats(fixture.views)
	usage_before, _, _ := editor_session.session_usage(&fixture.session, fixture.handle)
	failing.fail_after = failing.successful_allocations
	_, killed, kill_failure := registry_kill_buffer(
		&fixture.registry,
		&fixture.session,
		fixture.first.entry,
		.Discard_Modified,
	)
	failing.fail_after = max(u64)
	testing.expect(t, !killed)
	testing.expect_value(t, kill_failure.code, Failure_Code.Prepared_Memory_Limit)
	after, after_ok, _ := registry_snapshot(&fixture.registry, handle)
	view_after, view_after_ok, _ := view.snapshot(fixture.views, active.view)
	view_stats_after, stats_after_ok, _ := view.registry_stats(fixture.views)
	usage_after, usage_after_ok, _ := editor_session.session_usage(&fixture.session, fixture.handle)
	testing.expect(t, after_ok && view_after_ok && stats_after_ok && usage_after_ok)
	testing.expect_value(t, after, before)
	testing.expect_value(t, view_after, view_before)
	testing.expect_value(t, view_stats_after, view_stats_before)
	testing.expect_value(t, usage_after, usage_before)
}

/* Verifies soft and hard killed-buffer panes close through ordinary collapse and MRU focus. */
@(test)
kill_closes_dedicated_and_refocuses :: proc(t: ^testing.T) {
	fixture: Replacement_Test_Fixture
	if !replacement_test_fixture_init(t, &fixture, 20_671) {
		return
	}
	defer replacement_test_fixture_close(t, &fixture)

	handle, _, _ := registry_handle(&fixture.registry)
	initial, _, _ := registry_snapshot(&fixture.registry, handle)
	second, second_ok, _ := registry_replace_pane_buffer(
		&fixture.registry,
		initial.active_pane,
		&fixture.session,
		fixture.second.entry,
	)
	first, first_ok, _ := registry_replace_pane_buffer(
		&fixture.registry,
		second.pane,
		&fixture.session,
		fixture.first.entry,
	)
	if !second_ok || !first_ok {
		testing.expect(t, false)
		return
	}
	first_split, first_split_ok, _ := registry_split_right(&fixture.registry, first.pane)
	if !first_split_ok {
		testing.expect(t, false)
		return
	}
	second_split, second_split_ok, _ := registry_split_below(
		&fixture.registry,
		first_split.original,
	)
	if !second_split_ok {
		testing.expect(t, false)
		return
	}
	before_dedication, _, _ := registry_snapshot(&fixture.registry, second_split.layout)
	soft_target := snapshot_pane(&before_dedication, first_split.created.pane_id).pane
	soft, soft_ok, _ := registry_pane_dedication_set(&fixture.registry, soft_target, .Soft)
	if !soft_ok {
		testing.expect(t, false)
		return
	}
	after_soft, _, _ := registry_snapshot(&fixture.registry, soft.layout)
	hard_target := snapshot_pane(&after_soft, first_split.original.pane_id).pane
	_, hard_ok, _ := registry_pane_dedication_set(&fixture.registry, hard_target, .Hard)
	if !hard_ok {
		testing.expect(t, false)
		return
	}

	result, killed, kill_failure := registry_kill_buffer(
		&fixture.registry,
		&fixture.session,
		fixture.first.entry,
		.Discard_Modified,
	)
	testing.expect(t, killed)
	testing.expect_value(t, kill_failure.code, Failure_Code.None)
	testing.expect_value(t, result.replacements, u16(1))
	if !killed {
		return
	}
	after, after_ok, _ := registry_snapshot(&fixture.registry, result.layout)
	stats, stats_ok, _ := registry_stats(&fixture.registry)
	testing.expect(t, after_ok && stats_ok)
	testing.expect_value(t, after.pane_count, u16(1))
	testing.expect_value(t, after.partition_count, u16(0))
	testing.expect_value(t, after.active_pane.pane_id, second_split.created.pane_id)
	testing.expect_value(t, after.nodes[0].entry, fixture.second.entry)
	testing.expect_value(t, after.nodes[0].dedication, Pane_Dedication.None)
	testing.expect_value(t, stats.soft_dedicated_panes, u16(0))
	testing.expect_value(t, stats.hard_dedicated_panes, u16(0))
}

/* Verifies a final dedicated pane survives, clears dedication, and receives fallback. */
@(test)
kill_normalizes_final_dedicated_pane :: proc(t: ^testing.T) {
	fixture: Replacement_Test_Fixture
	if !replacement_test_fixture_init(t, &fixture, 20_681) {
		return
	}
	defer replacement_test_fixture_close(t, &fixture)

	handle, _, _ := registry_handle(&fixture.registry)
	initial, _, _ := registry_snapshot(&fixture.registry, handle)
	second, second_ok, _ := registry_replace_pane_buffer(
		&fixture.registry,
		initial.active_pane,
		&fixture.session,
		fixture.second.entry,
	)
	first, first_ok, _ := registry_replace_pane_buffer(
		&fixture.registry,
		second.pane,
		&fixture.session,
		fixture.first.entry,
	)
	if !second_ok || !first_ok {
		testing.expect(t, false)
		return
	}
	dedicated, dedicated_ok, _ := registry_pane_dedication_set(
		&fixture.registry,
		first.pane,
		.Hard,
	)
	if !dedicated_ok {
		testing.expect(t, false)
		return
	}
	result, killed, kill_failure := registry_kill_buffer(
		&fixture.registry,
		&fixture.session,
		fixture.first.entry,
		.Discard_Modified,
	)
	testing.expect(t, killed)
	testing.expect_value(t, kill_failure.code, Failure_Code.None)
	testing.expect_value(t, result.replacements, u16(1))
	if !killed {
		return
	}
	after, after_ok, _ := registry_snapshot(&fixture.registry, result.layout)
	testing.expect(t, after_ok)
	testing.expect_value(t, after.pane_count, u16(1))
	testing.expect_value(t, after.active_pane.pane_id, dedicated.pane.pane_id)
	testing.expect_value(t, after.nodes[0].entry, fixture.second.entry)
	testing.expect_value(t, after.nodes[0].dedication, Pane_Dedication.None)
}
