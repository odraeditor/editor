// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package view

import "../editor"
import "../gutter"
import "../indentation"
import "core:testing"

/* Verifies a view retains one copied effective indentation generation. */
@(test)
view_exposes_effective_indentation_policy :: proc(t: ^testing.T) {
	buffer: editor.Buffer
	initialized, _ := editor.buffer_init(
		&buffer,
		editor.Buffer_ID(28),
		"\talpha",
		editor.Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, initialized)
	if !initialized do return
	defer editor.buffer_close(&buffer)
	registry: Registry
	registry_ready, _ := registry_init(&registry, Registry_ID(10), context.allocator)
	testing.expect(t, registry_ready)
	if !registry_ready do return
	handle, created, _ := create(&registry, &buffer)
	testing.expect(t, created)
	if !created do return
	defer {
		closed, _ := close(&registry, &handle)
		testing.expect(t, closed)
		registry_closed, _ := registry_close(&registry)
		testing.expect(t, registry_closed)
	}

	effective := indentation.DEFAULT_EFFECTIVE_POLICY
	effective.policy = {representation = .Tabs, indent_width = 2, display_tab_width = 8}
	effective.scope = .Language
	effective.matcher_kind = .Language
	effective.matcher.length = u16(copy(effective.matcher.bytes[:], "odin"))
	effective.source_generation = 9
	effective.configuration_generation = 4
	set, set_failure := set_indentation_policy(&registry, handle, effective)
	testing.expectf(t, set, "policy replacement failed with %v", set_failure.code)
	state, viewed, _ := snapshot(&registry, handle)
	testing.expect(t, viewed)
	testing.expect_value(t, state.indentation_policy, effective)
	testing.expect_value(t, state.tab_width, u16(8))

	invalid := effective
	invalid.policy.indent_width = 0
	rejected, rejection := set_indentation_policy(&registry, handle, invalid)
	testing.expect(t, !rejected)
	testing.expect_value(t, rejection.code, Failure_Code.Invalid_Config)
	retained, retained_ok, _ := snapshot(&registry, handle)
	testing.expect(t, retained_ok)
	testing.expect_value(t, retained.indentation_policy, effective)
}

/* Verifies point movement updates desired column while retaining mark independently. */
@(test)
view_point_movement_controls_region_activation :: proc(t: ^testing.T) {
	buffer: editor.Buffer
	initialized, _ := editor.buffer_init(
		&buffer,
		editor.Buffer_ID(29),
		"abcd",
		editor.Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, initialized)
	if !initialized {
		return
	}
	defer editor.buffer_close(&buffer)
	registry: Registry
	registry_ready, _ := registry_init(&registry, Registry_ID(29), context.allocator)
	testing.expect(t, registry_ready)
	if !registry_ready {
		return
	}
	defer registry_close(&registry)
	handle, created, _ := create(&registry, &buffer)
	testing.expect(t, created)
	if !created {
		return
	}
	defer close(&registry, &handle)
	two, _, _ := editor.buffer_position(&buffer, editor.Byte_Offset(2))
	extended, _ := move_point(&registry, handle, two, 2, .Activate)
	testing.expect(t, extended)
	extended_state, _, _ := snapshot(&registry, handle)
	testing.expect(t, extended_state.region_active)
	testing.expect(t, extended_state.mark.present)
	testing.expect_value(t, extended_state.mark.position.byte_offset, editor.Byte_Offset(0))
	testing.expect_value(t, extended_state.point_position.byte_offset, editor.Byte_Offset(2))
	testing.expect_value(t, extended_state.desired_display_column, u32(2))
	three, _, _ := editor.buffer_position(&buffer, editor.Byte_Offset(3))
	collapsed, _ := move_point(&registry, handle, three, 3)
	testing.expect(t, collapsed)
	collapsed_state, _, _ := snapshot(&registry, handle)
	testing.expect(t, !collapsed_state.region_active)
	testing.expect(t, collapsed_state.mark.present)
	testing.expect_value(t, collapsed_state.mark.position.byte_offset, editor.Byte_Offset(0))
	testing.expect_value(t, collapsed_state.point_position.byte_offset, editor.Byte_Offset(3))
}

/* Verifies retained mark activation, endpoint exchange, and missing-mark rejection. */
@(test)
mark_is_independent_of_region :: proc(t: ^testing.T) {
	buffer: editor.Buffer
	initialized, _ := editor.buffer_init(
		&buffer,
		editor.Buffer_ID(30),
		"abcde",
		editor.Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, initialized)
	if !initialized {
		return
	}
	defer editor.buffer_close(&buffer)
	registry: Registry
	registry_ready, _ := registry_init(&registry, Registry_ID(30), context.allocator)
	testing.expect(t, registry_ready)
	if !registry_ready {
		return
	}
	defer registry_close(&registry)
	handle, created, _ := create(&registry, &buffer)
	testing.expect(t, created)
	if !created {
		return
	}
	defer close(&registry, &handle)

	activated_without_mark, missing_failure := set_region_active(&registry, handle, true)
	testing.expect(t, !activated_without_mark)
	testing.expect_value(t, missing_failure.code, Failure_Code.Missing_Mark)
	one, _, _ := editor.buffer_position(&buffer, editor.Byte_Offset(1))
	four, _, _ := editor.buffer_position(&buffer, editor.Byte_Offset(4))
	mark_set, _ := set_mark(&registry, handle, one, false)
	point_moved, _ := move_point(&registry, handle, four, 4, .Preserve)
	testing.expect(t, mark_set && point_moved)
	inactive, _, _ := snapshot(&registry, handle)
	testing.expect(t, inactive.mark.present && !inactive.region_active)
	testing.expect_value(t, inactive.point_position.byte_offset, editor.Byte_Offset(4))
	testing.expect_value(t, inactive.mark.position.byte_offset, editor.Byte_Offset(1))

	exchanged, exchange_failure := exchange_point_and_mark(&registry, handle)
	testing.expectf(t, exchanged, "endpoint exchange failed with %v", exchange_failure.code)
	active, _, _ := snapshot(&registry, handle)
	testing.expect(t, active.mark.present && active.region_active)
	testing.expect_value(t, active.point_position.byte_offset, editor.Byte_Offset(1))
	testing.expect_value(t, active.mark.position.byte_offset, editor.Byte_Offset(4))
}

/* Verifies creation, logical-state mutation, snapshots, and terminal close state. */
@(test)
lifecycle_preserves_frontend_independent_state :: proc(t: ^testing.T) {
	buffer: editor.Buffer
	initialized, _ := editor.buffer_init(
		&buffer,
		editor.Buffer_ID(201),
		"alpha🙂omega",
		editor.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	testing.expect(t, initialized)
	if !initialized {
		return
	}

	registry: Registry
	registry_ready, _ := registry_init(&registry, Registry_ID(11), context.allocator)
	testing.expect(t, registry_ready)
	handle, created, create_failure := create(&registry, &buffer)
	testing.expectf(t, created, "view creation failed with %v", create_failure.code)
	if !created {
		editor.buffer_close(&buffer)
		return
	}

	initial, initial_ok, _ := snapshot(&registry, handle)
	testing.expect(t, initial_ok)
	testing.expect_value(t, initial.buffer_id, editor.Buffer_ID(201))
	testing.expect_value(t, initial.revision, editor.Revision(0))
	testing.expect_value(t, initial.point_position.byte_offset, editor.Byte_Offset(0))
	testing.expect_value(t, initial.viewport_origin_position.byte_offset, editor.Byte_Offset(0))
	testing.expect_value(t, initial.tab_width, DEFAULT_TAB_WIDTH)
	testing.expect_value(t, initial.display_profile_id, Display_Profile_ID(1))
	testing.expect_value(t, initial.state_generation, u64(1))

	point, _, _ := editor.buffer_position(&buffer, editor.Byte_Offset(5))
	mark, _, _ := editor.buffer_position(&buffer, editor.Byte_Offset(1))
	viewport, _, _ := editor.buffer_position(&buffer, editor.Byte_Offset(9))
	point_set, _ := set_point(&registry, handle, point)
	mark_set, _ := set_mark(&registry, handle, mark)
	viewport_set, _ := set_viewport(&registry, handle, viewport, 7)
	policy_set, _ := set_layout_policy(&registry, handle, 12, 8, Display_Profile_ID(3))
	testing.expect(t, point_set && mark_set && viewport_set && policy_set)

	updated, updated_ok, _ := snapshot(&registry, handle)
	testing.expect(t, updated_ok)
	testing.expect_value(t, updated.point_position.byte_offset, editor.Byte_Offset(5))
	testing.expect(t, updated.mark.present && updated.region_active)
	testing.expect_value(t, updated.mark.position.byte_offset, editor.Byte_Offset(1))
	testing.expect_value(t, updated.viewport_origin_position.byte_offset, editor.Byte_Offset(9))
	testing.expect_value(t, updated.horizontal_display_column, u32(7))
	testing.expect_value(t, updated.desired_display_column, u32(12))
	testing.expect_value(t, updated.tab_width, u16(8))
	testing.expect_value(t, updated.display_profile_id, Display_Profile_ID(3))
	testing.expect_value(t, updated.state_generation, u64(5))

	deactivated, _ := set_region_active(&registry, handle, false)
	testing.expect(t, deactivated)
	inactive, inactive_ok, _ := snapshot(&registry, handle)
	testing.expect(t, inactive_ok)
	testing.expect(t, inactive.mark.present && !inactive.region_active)
	testing.expect_value(t, inactive.state_generation, u64(6))
	mark_cleared, _ := clear_mark(&registry, handle)
	testing.expect(t, mark_cleared)
	cleared, cleared_ok, _ := snapshot(&registry, handle)
	testing.expect(t, cleared_ok)
	testing.expect(t, !cleared.mark.present && !cleared.region_active)
	testing.expect_value(t, cleared.state_generation, u64(7))

	stale := handle
	closed, _ := close(&registry, &handle)
	testing.expect(t, closed)
	testing.expect_value(t, handle, View_Handle{})
	_, stale_ok, stale_failure := snapshot(&registry, stale)
	testing.expect(t, !stale_ok)
	testing.expect_value(t, stale_failure.code, Failure_Code.Stale_View)
	registry_closed, _ := registry_close(&registry)
	buffer_closed, _ := editor.buffer_close(&buffer)
	testing.expect(t, registry_closed && buffer_closed)
}

/* Verifies view creation preserves canonical selection on anchor-capacity failure. */
@(test)
creation_failure_keeps_registry :: proc(t: ^testing.T) {
	limits := editor.DEFAULT_LIMITS
	limits.anchors = 1
	buffer: editor.Buffer
	initialized, _ := editor.buffer_init(
		&buffer,
		editor.Buffer_ID(203),
		"abc",
		editor.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
		limits,
	)
	testing.expect(t, initialized)
	if !initialized {
		return
	}
	defer editor.buffer_close(&buffer)

	registry: Registry
	registry_ready, _ := registry_init(&registry, Registry_ID(13), context.allocator)
	testing.expect(t, registry_ready)
	_, created, failure := create(&registry, &buffer)
	testing.expect(t, !created)
	testing.expect_value(t, failure.code, Failure_Code.Editor_Failure)
	testing.expect_value(t, failure.editor_failure.code, editor.Failure_Code.Anchor_Limit)
	registry_state, registry_state_ok, _ := registry_stats(&registry)
	testing.expect(t, registry_state_ok)
	testing.expect_value(t, registry_state.live_count, u16(0))
	anchor_stats, stats_ok, _ := editor.buffer_anchor_stats(&buffer)
	testing.expect(t, stats_ok)
	testing.expect_value(t, anchor_stats.live_count, u32(1))
	registry_closed, _ := registry_close(&registry)
	testing.expect(t, registry_closed)
}

/* Verifies wrong-registry rejection and deterministic buffer-close invalidation. */
@(test)
handles_reject_closed_buffers :: proc(t: ^testing.T) {
	buffer: editor.Buffer
	initialized, _ := editor.buffer_init(
		&buffer,
		editor.Buffer_ID(205),
		"abc",
		editor.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	testing.expect(t, initialized)
	if !initialized {
		return
	}

	registry: Registry
	other: Registry
	ready, _ := registry_init(&registry, Registry_ID(15), context.allocator)
	other_ready, _ := registry_init(&other, Registry_ID(16), context.allocator)
	testing.expect(t, ready && other_ready)
	handle, created, _ := create(&registry, &buffer)
	testing.expect(t, created)

	_, wrong_ok, wrong_failure := snapshot(&other, handle)
	testing.expect(t, !wrong_ok)
	testing.expect_value(t, wrong_failure.code, Failure_Code.Wrong_Registry)

	buffer_closed, _ := editor.buffer_close(&buffer)
	testing.expect(t, buffer_closed)
	_, snapshot_ok, snapshot_failure := snapshot(&registry, handle)
	testing.expect(t, !snapshot_ok)
	testing.expect_value(t, snapshot_failure.code, Failure_Code.Editor_Failure)
	testing.expect_value(t, snapshot_failure.editor_failure.code, editor.Failure_Code.Closed_Buffer)
	view_closed, _ := close(&registry, &handle)
	testing.expect(t, view_closed)
	registry_closed, _ := registry_close(&registry)
	other_closed, _ := registry_close(&other)
	testing.expect(t, registry_closed && other_closed)
}

/* Verifies that two views share buffer selection and retain independent viewports. */
@(test)
views_stay_independent_after_edits :: proc(t: ^testing.T) {
	buffer: editor.Buffer
	initialized, _ := editor.buffer_init(
		&buffer,
		editor.Buffer_ID(207),
		"abcdef",
		editor.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	testing.expect(t, initialized)
	if !initialized {
		return
	}

	registry: Registry
	ready, _ := registry_init(&registry, Registry_ID(17), context.allocator)
	testing.expect(t, ready)
	first, first_ok, _ := create(&registry, &buffer)
	second, second_ok, _ := clone_additional(&registry, first)
	testing.expect(t, first_ok && second_ok)

	position_1, _, _ := editor.buffer_position(&buffer, editor.Byte_Offset(1))
	position_2, _, _ := editor.buffer_position(&buffer, editor.Byte_Offset(2))
	position_3, _, _ := editor.buffer_position(&buffer, editor.Byte_Offset(3))
	position_4, _, _ := editor.buffer_position(&buffer, editor.Byte_Offset(4))
	position_5, _, _ := editor.buffer_position(&buffer, editor.Byte_Offset(5))
	first_point_ok, _ := set_point(&registry, first, position_1)
	first_mark_ok, _ := set_mark(&registry, first, position_4)
	second_point_ok, _ := set_point(&registry, second, position_5)
	second_mark_ok, _ := set_mark(&registry, second, position_2)
	second_viewport_ok, _ := set_viewport(&registry, second, position_3, 9)
	testing.expect(
		t,
		first_point_ok && first_mark_ok && second_point_ok &&
		second_mark_ok && second_viewport_ok,
	)

	_, _, published, _ := editor.buffer_splice(
		&buffer,
		editor.Splice{start = position_2, end = position_4, replacement = "X"},
		context.temp_allocator,
	)
	testing.expect(t, published)
	first_snapshot, first_snapshot_ok, _ := snapshot(&registry, first)
	second_snapshot, second_snapshot_ok, _ := snapshot(&registry, second)
	testing.expect(t, first_snapshot_ok && second_snapshot_ok)
	testing.expect_value(
		t,
		first_snapshot.presentation_ownership,
		Presentation_Ownership.Retained_Primary,
	)
	testing.expect_value(
		t,
		second_snapshot.presentation_ownership,
		Presentation_Ownership.Additional,
	)
	testing.expect_value(
		t,
		first_snapshot.point_position.byte_offset,
		editor.Byte_Offset(1),
	)
	testing.expect_value(
		t,
		first_snapshot.mark.position.byte_offset,
		editor.Byte_Offset(2),
	)
	testing.expect_value(
		t,
		second_snapshot.point_position.byte_offset,
		editor.Byte_Offset(4),
	)
	testing.expect_value(
		t,
		first_snapshot.effective_point_position.byte_offset,
		editor.Byte_Offset(4),
	)
	testing.expect_value(
		t,
		second_snapshot.effective_point_position.byte_offset,
		editor.Byte_Offset(4),
	)
	testing.expect_value(
		t,
		second_snapshot.mark.position.byte_offset,
		editor.Byte_Offset(2),
	)
	testing.expect_value(
		t,
		first_snapshot.selection_generation,
		second_snapshot.selection_generation,
	)
	testing.expect_value(
		t,
		second_snapshot.viewport_origin_position.byte_offset,
		editor.Byte_Offset(2),
	)
	testing.expect_value(t, first_snapshot.horizontal_display_column, u32(0))
	testing.expect_value(t, second_snapshot.horizontal_display_column, u32(9))
	registry_state, registry_state_ok, _ := registry_stats(&registry)
	testing.expect(t, registry_state_ok)
	testing.expect_value(t, registry_state.retained_count, u16(1))
	testing.expect_value(t, registry_state.additional_count, u16(1))

	restored, _ := restore_stored_point(&registry, first)
	first_selected, _, _ := snapshot(&registry, first)
	second_not_selected, _, _ := snapshot(&registry, second)
	testing.expect(t, restored)
	testing.expect_value(
		t,
		first_selected.effective_point_position.byte_offset,
		editor.Byte_Offset(1),
	)
	testing.expect_value(
		t,
		second_not_selected.point_position.byte_offset,
		editor.Byte_Offset(4),
	)
	testing.expect_value(
		t,
		second_not_selected.effective_point_position.byte_offset,
		editor.Byte_Offset(1),
	)

	first_closed, _ := close(&registry, &first)
	second_closed, _ := close(&registry, &second)
	registry_closed, _ := registry_close(&registry)
	buffer_closed, _ := editor.buffer_close(&buffer)
	testing.expect(t, first_closed && second_closed && registry_closed && buffer_closed)
}

/* Verifies that each buffer admits one retained primary and bounded explicit copies. */
@(test)
retained_primary_is_unique_per_buffer :: proc(t: ^testing.T) {
	buffer: editor.Buffer
	initialized, _ := editor.buffer_init(
		&buffer,
		editor.Buffer_ID(208),
		"abc",
		editor.Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, initialized)
	if !initialized {
		return
	}
	registry: Registry
	ready, _ := registry_init(&registry, Registry_ID(18), context.allocator)
	primary, primary_ok, _ := create(&registry, &buffer)
	_, duplicate_ok, duplicate_failure := create(&registry, &buffer)
	additional, additional_ok, _ := clone_additional(&registry, primary)
	testing.expect(t, ready && primary_ok && !duplicate_ok && additional_ok)
	testing.expect_value(t, duplicate_failure.code, Failure_Code.Retained_Primary_Exists)
	stats, stats_ok, _ := registry_stats(&registry)
	testing.expect(t, stats_ok)
	testing.expect_value(t, stats.live_count, u16(2))
	testing.expect_value(t, stats.retained_count, u16(1))
	testing.expect_value(t, stats.additional_count, u16(1))
	editor_view_closed, _ := close(&registry, &additional)
	primary_closed, _ := close(&registry, &primary)
	registry_closed, _ := registry_close(&registry)
	buffer_closed, _ := editor.buffer_close(&buffer)
	testing.expect(t, editor_view_closed && primary_closed && registry_closed && buffer_closed)
}

/* Verifies cloned views retain independent Gutter policies across rebind and close. */
@(test)
gutter_is_view_local :: proc(t: ^testing.T) {
	first_buffer: editor.Buffer
	second_buffer: editor.Buffer
	first_ready, _ := editor.buffer_init(
		&first_buffer,
		editor.Buffer_ID(215),
		"first",
		editor.Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	second_ready, _ := editor.buffer_init(
		&second_buffer,
		editor.Buffer_ID(216),
		"second",
		editor.Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	registry: Registry
	registry_ready, _ := registry_init(&registry, Registry_ID(23), context.allocator)
	first, first_ok, _ := create(&registry, &first_buffer)
	second, second_ok, _ := create(&registry, &second_buffer)
	additional, additional_ok, _ := clone_additional(&registry, first)
	testing.expect(
		t,
		first_ready && second_ready && registry_ready && first_ok && second_ok && additional_ok,
	)
	if !first_ready || !second_ready || !registry_ready || !first_ok || !second_ok ||
	   !additional_ok {
		return
	}

	policy := gutter.DEFAULT_FACTORY_POLICY
	policy.mode = .Hybrid
	policy.side = .Right
	policy.visible = false
	set, set_failure := set_gutter_policy(&registry, additional, policy)
	primary_state, primary_ok, _ := snapshot(&registry, first)
	additional_state, additional_state_ok, _ := snapshot(&registry, additional)
	testing.expectf(t, set, "Gutter policy failed with %v", set_failure.code)
	testing.expect(t, primary_ok && additional_state_ok)
	testing.expect_value(t, primary_state.gutter.policy.mode, gutter.Numbering_Mode.Absolute)
	testing.expect_value(t, additional_state.gutter.policy.mode, gutter.Numbering_Mode.Hybrid)
	testing.expect_value(t, additional_state.gutter.policy.side, gutter.Side.Right)
	testing.expect(t, !additional_state.gutter.policy.visible)
	testing.expect(t, additional_state.gutter.overrides_default)
	testing.expect_value(t, additional_state.gutter.generation, u64(2))

	rebound, _ := rebind_additional(&registry, additional, second)
	rebound_state, rebound_ok, _ := snapshot(&registry, additional)
	testing.expect(t, rebound && rebound_ok)
	testing.expect_value(t, rebound_state.buffer_id, editor.Buffer_ID(216))
	testing.expect_value(t, rebound_state.gutter, additional_state.gutter)

	stale := additional
	additional_closed, _ := close(&registry, &additional)
	_, stale_ok, stale_failure := snapshot(&registry, stale)
	testing.expect(t, additional_closed && !stale_ok)
	testing.expect_value(t, stale_failure.code, Failure_Code.Stale_View)
	second_closed, _ := close(&registry, &second)
	first_closed, _ := close(&registry, &first)
	registry_closed, _ := registry_close(&registry)
	second_buffer_closed, _ := editor.buffer_close(&second_buffer)
	first_buffer_closed, _ := editor.buffer_close(&first_buffer)
	testing.expect(
		t,
		second_closed && first_closed && registry_closed && second_buffer_closed &&
		first_buffer_closed,
	)
}

/* Verifies pane-owned views can change buffers without changing additional-view accounting. */
@(test)
rebind_keeps_identity_and_accounting :: proc(t: ^testing.T) {
	first_buffer: editor.Buffer
	second_buffer: editor.Buffer
	first_ready, _ := editor.buffer_init(
		&first_buffer,
		editor.Buffer_ID(213),
		"first",
		editor.Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	second_ready, _ := editor.buffer_init(
		&second_buffer,
		editor.Buffer_ID(214),
		"second",
		editor.Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	registry: Registry
	registry_ready, _ := registry_init(&registry, Registry_ID(22), context.allocator)
	first, first_ok, _ := create(&registry, &first_buffer)
	second, second_ok, _ := create(&registry, &second_buffer)
	additional, additional_ok, _ := clone_additional(&registry, first)
	testing.expect(
		t,
		first_ready && second_ready && registry_ready && first_ok && second_ok && additional_ok,
	)
	if !first_ready || !second_ready || !registry_ready || !first_ok || !second_ok || !additional_ok {
		return
	}
	before, before_ok, _ := registry_stats(&registry)
	rebound, rebound_failure := rebind_additional(&registry, additional, second)
	after, after_ok, _ := registry_stats(&registry)
	state, state_ok, _ := snapshot(&registry, additional)
	testing.expect(t, before_ok && rebound && after_ok && state_ok)
	testing.expect_value(t, rebound_failure.code, Failure_Code.None)
	testing.expect_value(t, before, after)
	testing.expect_value(t, state.buffer_id, editor.Buffer_ID(214))
	testing.expect_value(t, state.presentation_ownership, Presentation_Ownership.Additional)
	primary_rebound, primary_failure := rebind_additional(&registry, first, second)
	testing.expect(t, !primary_rebound)
	testing.expect_value(t, primary_failure.code, Failure_Code.Additional_Required)

	additional_closed, _ := close(&registry, &additional)
	second_closed, _ := close(&registry, &second)
	first_closed, _ := close(&registry, &first)
	registry_closed, _ := registry_close(&registry)
	second_buffer_closed, _ := editor.buffer_close(&second_buffer)
	first_buffer_closed, _ := editor.buffer_close(&first_buffer)
	testing.expect(
		t,
		additional_closed && second_closed && first_closed && registry_closed &&
		second_buffer_closed && first_buffer_closed,
	)
}

/* Verifies additional-view overflow preserves occupancy and all existing handles. */
@(test)
additional_view_capacity_rejection_is_atomic :: proc(t: ^testing.T) {
	buffer: editor.Buffer
	initialized, _ := editor.buffer_init(
		&buffer,
		editor.Buffer_ID(210),
		"capacity",
		editor.Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, initialized)
	if !initialized {
		return
	}
	registry: Registry
	ready, _ := registry_init(&registry, Registry_ID(20), context.allocator)
	primary, primary_ok, _ := create(&registry, &buffer)
	additional: [MAX_ADDITIONAL_VIEWS]View_Handle
	created_all := true
	for &handle in additional {
		created: bool
		handle, created, _ = clone_additional(&registry, primary)
		created_all = created_all && created
	}
	before, before_ok, _ := registry_stats(&registry)
	_, overflow_ok, overflow_failure := clone_additional(&registry, primary)
	after, after_ok, _ := registry_stats(&registry)
	primary_state, primary_live, _ := snapshot(&registry, primary)
	testing.expect(t, ready && primary_ok && created_all && before_ok && after_ok && primary_live)
	testing.expect(t, !overflow_ok)
	testing.expect_value(t, overflow_failure.code, Failure_Code.Capacity_Limit)
	testing.expect_value(t, overflow_failure.limit, u64(MAX_ADDITIONAL_VIEWS))
	testing.expect_value(t, before, after)
	testing.expect_value(t, primary_state.presentation_ownership, Presentation_Ownership.Retained_Primary)
	for index := len(additional) - 1; index >= 0; index -= 1 {
		closed, _ := close(&registry, &additional[index])
		testing.expect(t, closed)
	}
	primary_closed, _ := close(&registry, &primary)
	registry_closed, _ := registry_close(&registry)
	buffer_closed, _ := editor.buffer_close(&buffer)
	testing.expect(t, primary_closed && registry_closed && buffer_closed)
}

/* Verifies that prepared publication blocks anchor mutation without changing view state. */
@(test)
prepared_splices_block_view_anchor_mutation :: proc(t: ^testing.T) {
	buffer: editor.Buffer
	initialized, _ := editor.buffer_init(
		&buffer,
		editor.Buffer_ID(209),
		"abc",
		editor.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	testing.expect(t, initialized)
	if !initialized {
		return
	}
	registry: Registry
	ready, _ := registry_init(&registry, Registry_ID(19), context.allocator)
	handle, created, _ := create(&registry, &buffer)
	testing.expect(t, ready && created)

	end, _, _ := editor.buffer_position(&buffer, editor.Byte_Offset(1))
	working, prepared_ok, _ := editor.buffer_working_revision_open(&buffer)
	working_start, _, _ := editor.working_revision_position(&working, editor.Byte_Offset(0))
	working_end, _, _ := editor.working_revision_position(&working, editor.Byte_Offset(1))
	edited, _ := editor.working_revision_splice(
		&working,
		editor.Working_Splice{start = working_start, end = working_end, replacement = "x"},
		context.temp_allocator,
	)
	testing.expect(t, prepared_ok && edited)
	moved, move_failure := set_point(&registry, handle, end)
	testing.expect(t, !moved)
	testing.expect_value(t, move_failure.code, Failure_Code.Editor_Failure)
	testing.expect_value(t, move_failure.editor_failure.code, editor.Failure_Code.Work_Limit)
	unchanged, unchanged_ok, _ := snapshot(&registry, handle)
	testing.expect(t, unchanged_ok)
	testing.expect_value(t, unchanged.point_position.byte_offset, editor.Byte_Offset(0))
	testing.expect_value(t, unchanged.state_generation, u64(1))
	aborted, _ := editor.working_revision_abort(&working)
	testing.expect(t, aborted)

	view_closed, _ := close(&registry, &handle)
	registry_closed, _ := registry_close(&registry)
	buffer_closed, _ := editor.buffer_close(&buffer)
	testing.expect(t, view_closed && registry_closed && buffer_closed)
}

/* Verifies failed incoming point publication restores the outgoing stored point exactly. */
@(test)
focus_rolls_back_on_prepared_buffer :: proc(t: ^testing.T) {
	outgoing_buffer: editor.Buffer
	incoming_buffer: editor.Buffer
	outgoing_ready, _ := editor.buffer_init(
		&outgoing_buffer,
		editor.Buffer_ID(211),
		"abcdef",
		editor.Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	incoming_ready, _ := editor.buffer_init(
		&incoming_buffer,
		editor.Buffer_ID(212),
		"uvwxyz",
		editor.Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	registry: Registry
	registry_ready, _ := registry_init(&registry, Registry_ID(21), context.allocator)
	outgoing, outgoing_ok, _ := create(&registry, &outgoing_buffer)
	incoming, incoming_ok, _ := create(&registry, &incoming_buffer)
	testing.expect(t, outgoing_ready && incoming_ready && registry_ready && outgoing_ok && incoming_ok)
	if !outgoing_ready || !incoming_ready || !registry_ready || !outgoing_ok || !incoming_ok {
		return
	}
	outgoing_stored, _, _ := editor.buffer_position(&outgoing_buffer, editor.Byte_Offset(1))
	outgoing_effective, _, _ := editor.buffer_position(&outgoing_buffer, editor.Byte_Offset(5))
	incoming_stored, _, _ := editor.buffer_position(&incoming_buffer, editor.Byte_Offset(2))
	outgoing_set, _ := set_point(&registry, outgoing, outgoing_stored)
	outgoing_effective_set, _ := editor.buffer_selection_set_point(&outgoing_buffer, outgoing_effective)
	incoming_set, _ := set_point(&registry, incoming, incoming_stored)
	before_outgoing, before_outgoing_ok, _ := snapshot(&registry, outgoing)
	before_incoming, before_incoming_ok, _ := snapshot(&registry, incoming)
	working, working_ok, _ := editor.buffer_working_revision_open(&incoming_buffer)
	testing.expect(
		t,
		outgoing_set && outgoing_effective_set && incoming_set && before_outgoing_ok &&
		before_incoming_ok && working_ok,
	)
	transferred, transfer_failure := transfer_focus(&registry, outgoing, incoming)
	after_outgoing, after_outgoing_ok, _ := snapshot(&registry, outgoing)
	after_incoming, after_incoming_ok, _ := snapshot(&registry, incoming)
	testing.expect(t, !transferred && after_outgoing_ok && after_incoming_ok)
	testing.expect_value(t, transfer_failure.code, Failure_Code.Editor_Failure)
	testing.expect_value(t, transfer_failure.editor_failure.code, editor.Failure_Code.Work_Limit)
	testing.expect_value(t, after_outgoing, before_outgoing)
	testing.expect_value(t, after_incoming, before_incoming)
	aborted, _ := editor.working_revision_abort(&working)
	incoming_closed, _ := close(&registry, &incoming)
	outgoing_closed, _ := close(&registry, &outgoing)
	registry_closed, _ := registry_close(&registry)
	incoming_buffer_closed, _ := editor.buffer_close(&incoming_buffer)
	outgoing_buffer_closed, _ := editor.buffer_close(&outgoing_buffer)
	testing.expect(
		t,
		aborted && incoming_closed && outgoing_closed && registry_closed && incoming_buffer_closed &&
		outgoing_buffer_closed,
	)
}
