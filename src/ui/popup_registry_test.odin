// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ui

import "core:mem"
import "core:testing"

@(test)
/* Verifies popup copies, inspection, replacement, dismissal, and generations together. */
registry_manages_generations :: proc(t: ^testing.T) {
	registry: Registry
	initialized, _ := registry_init(&registry, Registry_ID(71))
	testing.expect(t, initialized)
	if !initialized {
		return
	}
	defer registry_close(&registry)

	first, first_popup, first_source, first_ok, _ := publish_popup_test_root(
		&registry, {}, 17, 1, 31,
	)
	inspected, inspect_ok, _ := registry_inspect_popup(&registry, first_popup)
	stats, stats_ok, _ := registry_stats(&registry)
	snapshot, snapshot_ok, _ := registry_snapshot(&registry, first, popup_test_renderer())
	snapshot_data, snapshot_view_ok := snapshot_view(&snapshot)
	if snapshot_ok do defer snapshot_close(&snapshot)

	second, second_popup, second_source, second_ok, _ := publish_popup_test_root(
		&registry, first, 17, 2, 32,
	)
	_, stale_ok, stale_failure := registry_inspect_popup(&registry, first_popup)
	second_inspected, second_inspect_ok, _ := registry_inspect_popup(&registry, second_popup)
	focus, focus_ok, _ := registry_focus(&registry)

	dismissed, dismissed_ok := publish_single_text_root(&registry, second)
	dismissed_stats, dismissed_stats_ok, _ := registry_stats(&registry)
	_, dismissed_popup_ok, dismissed_failure := registry_inspect_popup(&registry, second_popup)

	testing.expect(
		t,
		first_ok && inspect_ok && stats_ok && snapshot_ok && snapshot_view_ok &&
		second_ok && !stale_ok && second_inspect_ok && focus_ok && dismissed_ok &&
		dismissed_stats_ok && !dismissed_popup_ok,
	)
	testing.expect_value(t, inspected.id, Popup_ID(17))
	testing.expect_value(t, stats.popups, u16(1))
	testing.expect_value(t, stats.accounting.popup_bytes, u64(size_of(Popup_Descriptor)))
	testing.expect_value(t, len(snapshot_data.popups), 1)
	testing.expect_value(t, stale_failure.code, Failure_Code.Stale_Popup)
	testing.expect_value(t, second_inspected.generation, Popup_Generation(2))
	testing.expect_value(t, focus.target, second_source)
	testing.expect(t, focus.target != first_source)
	testing.expect_value(t, dismissed.generation, Root_Generation(3))
	testing.expect_value(t, dismissed_stats.popups, u16(0))
	testing.expect_value(t, dismissed_stats.accounting.popup_bytes, u64(0))
	testing.expect_value(t, dismissed_failure.code, Failure_Code.Stale_Popup)
}

@(test)
/* Ensures stale popup replacement leaves the confirmed root unchanged. */
stale_popup_replacement_preserves_confirmed_root :: proc(t: ^testing.T) {
	registry: Registry
	initialized, _ := registry_init(&registry, Registry_ID(72))
	testing.expect(t, initialized)
	if !initialized {
		return
	}
	defer registry_close(&registry)

	first, first_popup, _, first_ok, _ := publish_popup_test_root(
		&registry, {}, 23, 4, 41,
	)
	_, _, _, replaced, replace_failure := publish_popup_test_root(
		&registry, first, 23, 4, 42,
	)
	current, current_ok, _ := registry_handle(&registry)
	popup, popup_ok, _ := registry_inspect_popup(&registry, first_popup)

	testing.expect(t, first_ok && !replaced && current_ok && popup_ok)
	testing.expect_value(t, replace_failure.code, Failure_Code.Invalid_Proposal)
	testing.expect_value(t, current, first)
	testing.expect_value(t, popup.generation, Popup_Generation(4))
}

@(test)
/* Ensures popup registry teardown releases every owned record. */
popup_registry_teardown_releases_owned_records :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	limits := popup_test_limits()

	registry: Registry
	initialized, _ := registry_init(&registry, Registry_ID(73), limits, allocator)
	_, _, _, published, _ := publish_popup_test_root(&registry, {}, 29, 1, 51)
	closed, _ := registry_close(&registry)
	cleanup_bytes := tracking.current_memory_allocated
	mem.tracking_allocator_destroy(&tracking)

	testing.expect(t, initialized && published && closed)
	testing.expect_value(t, cleanup_bytes, i64(0))
}

@(test)
/* Ensures content and action overflow leave an empty registry. */
content_limits_keep_empty_registry :: proc(t: ^testing.T) {
	content_limits := popup_test_limits()
	content_limits.popup_content_bytes = 512
	content_registry: Registry
	content_initialized, _ := registry_init(
		&content_registry, Registry_ID(74), content_limits,
	)
	_, _, _, content_ok, content_failure := publish_popup_test_root(
		&content_registry, {}, 31, 1, 61,
	)
	content_closed, _ := registry_close(&content_registry)

	action_limits := popup_test_limits()
	action_limits.popup_actions = 1
	action_registry: Registry
	action_initialized, _ := registry_init(&action_registry, Registry_ID(75), action_limits)
	_, _, _, action_ok, action_failure := publish_popup_test_root(
		&action_registry, {}, 37, 1, 62,
	)
	action_closed, _ := registry_close(&action_registry)

	testing.expect(
		t,
		content_initialized && !content_ok && content_closed &&
		action_initialized && !action_ok && action_closed,
	)
	testing.expect_value(t, content_failure.code, Failure_Code.Popup_Content_Limit)
	testing.expect_value(t, content_failure.limit, u64(512))
	testing.expect_value(t, action_failure.code, Failure_Code.Popup_Action_Limit)
	testing.expect_value(t, action_failure.limit, u64(1))
}

@(test)
/* Ensures repeated popup replacement has bounded retention and complete cleanup. */
replacement_has_zero_cleanup :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	registry: Registry
	initialized, _ := registry_init(
		&registry, Registry_ID(76), popup_test_limits(), allocator,
	)
	root, _, _, published, _ := publish_popup_test_root(&registry, {}, 41, 1, 71)
	retained := tracking.current_memory_allocated
	replacements_ok := initialized && published
	for generation in 2 ..= 32 {
		root, _, _, published, _ = publish_popup_test_root(
			&registry, root, 41, u64(generation), u64(70 + generation),
		)
		replacements_ok = replacements_ok && published &&
			tracking.current_memory_allocated == retained
	}
	_, dismissed := publish_single_text_root(&registry, root)
	dismissed_bytes := tracking.current_memory_allocated
	dismissed_stats, stats_ok, _ := registry_stats(&registry)
	closed, _ := registry_close(&registry)
	cleanup_bytes := tracking.current_memory_allocated
	mem.tracking_allocator_destroy(&tracking)

	testing.expect(t, replacements_ok && dismissed && stats_ok && closed)
	testing.expect_value(t, dismissed_bytes, retained)
	testing.expect_value(t, dismissed_stats.popups, u16(0))
	testing.expect_value(t, dismissed_stats.accounting.popup_bytes, u64(0))
	testing.expect_value(t, cleanup_bytes, i64(0))
}

@(test)
/* Ensures snapshot allocation faults release every partial popup copy. */
snapshot_faults_release_partial_copies :: proc(t: ^testing.T) {
	registry: Registry
	initialized, _ := registry_init(&registry, Registry_ID(77), popup_test_limits())
	testing.expect(t, initialized)
	if !initialized {
		return
	}
	defer registry_close(&registry)
	root, _, _, published, _ := publish_popup_test_root(&registry, {}, 43, 1, 81)
	testing.expect(t, published)
	if !published {
		return
	}

	for fail_after in 0 ..< 9 {
		tracking: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracking, context.allocator)
		failing := UI_Failing_Allocator {
			backing = mem.tracking_allocator(&tracking),
			fail_after = u64(fail_after),
		}
		snapshot, copied, failure := registry_snapshot(
			&registry,
			root,
			popup_test_renderer(),
			ui_failing_allocator(&failing),
		)
		if copied {
			testing.expect(t, snapshot_close(&snapshot))
		} else {
			testing.expect_value(t, failure.code, Failure_Code.Allocation)
		}
		testing.expect_value(t, tracking.current_memory_allocated, i64(0))
		mem.tracking_allocator_destroy(&tracking)
	}
}

@(private)
publish_popup_test_root :: proc(
	registry: ^Registry,
	expected: Root_Handle,
	popup_id, popup_generation, content_generation: u64,
) -> (
	root: Root_Handle,
	popup, source: Object_Handle,
	ok: bool,
	failure: Failure,
) {
	proposal, prepared, begin_failure := proposal_begin(registry, expected)
	if !prepared {
		return {}, {}, {}, false, begin_failure
	}
	defer if proposal.state != nil do proposal_abort(&proposal)
	_, style_ok, _ := proposal_add_style(&proposal, .Text_Normal)
	source_projection, source_projection_ok, _ := proposal_add_projection(
		&proposal,
		Model_Reference{owner_id = 1, model_id = 1, generation = 1},
		256,
	)
	source_view, source_view_ok, _ := proposal_add_view(
		&proposal,
		Visual_View_Descriptor{kind = .Text_View, projection = source_projection},
	)
	content_projection, content_projection_ok, _ := proposal_add_projection(
		&proposal,
		Model_Reference {
			owner_id = 2,
			model_id = 2,
			generation = Model_Generation(content_generation),
		},
		1_024,
	)
	content_view, content_view_ok, _ := proposal_add_view(
		&proposal,
		Visual_View_Descriptor {
			kind = .Text_View,
			projection = content_projection,
			read_only = true,
		},
	)
	source_ok: bool
	source, source_ok, _ = proposal_add_surface(
		&proposal,
		Surface_Descriptor {
			owner_id = 1,
			view = source_view,
			focusable = true,
			visible = true,
			required_profile = 1,
			geometry = {row = 0, column = 0, height = 24, width = 80},
		},
	)
	content, content_ok, _ := proposal_add_surface(
		&proposal,
		Surface_Descriptor {
			owner_id = 2,
			view = content_view,
			focusable = false,
			visible = true,
			required_profile = 1,
		},
	)
	source_node, node_ok, _ := proposal_add_surface_node(&proposal, source)
	popup_ok: bool
	popup_failure: Failure
	descriptor := Popup_Descriptor {
			id = Popup_ID(popup_id),
			generation = Popup_Generation(popup_generation),
			owner_id = 3,
			owner_generation = popup_generation,
			anchor = {
				kind = .Surface,
				source_surface = source,
				owner_id = 4,
				source_id = u64(source.object_id),
				source_generation = u64(source.root_generation),
				start = 7,
				end = 7,
				presentation_generation = u64(source.root_generation),
				viewport_row = 7,
				viewport_column = 0,
				height_rows = 1,
				width_columns = 80,
			},
			content_surface = content,
			content_generation = content_generation,
			placements = {.Above, .Below, .Invalid, .Invalid},
			placement_count = 2,
			bounds = {
				minimum_rows = 5,
				minimum_columns = 8,
				preferred_rows = 8,
				preferred_columns = 48,
				maximum_rows = 12,
				maximum_columns = 96,
			},
			padding_rows = 1,
			padding_columns = 1,
			border = true,
			clipping = .Wrap,
			behavior = .Informational,
			input_policy = .Preserve_Source_Focus,
			dismissal = {.Explicit_Cancel, .Anchor_Invalidation, .Generation_Replacement},
			fallback = .Compact_Feedback,
			required_profile = 1,
			content_bytes = 1_024,
			action_count = 2,
	}
	popup_test_attach_presentation_profile(&descriptor)
	popup, popup_ok, popup_failure = proposal_add_popup(&proposal, descriptor)
	root_ok, _ := proposal_set_root(&proposal, source_node, source)
	if !popup_ok {
		return {}, {}, {}, false, popup_failure
	}
	published: bool
	root, published, failure = proposal_publish(registry, &proposal, popup_test_renderer())
	return root, popup, source, style_ok && source_projection_ok && source_view_ok &&
		content_projection_ok && content_view_ok && source_ok && content_ok && node_ok &&
		root_ok && published, failure
}

@(private)
popup_test_renderer :: proc() -> Renderer_Profile {
	renderer := test_renderer()
	renderer.capabilities += {.Popup_Overlap}
	return renderer
}

@(private)
popup_test_limits :: proc() -> Resource_Limits {
	limits := DEFAULT_RESOURCE_LIMITS
	limits.live_surfaces = 4
	limits.live_views = 4
	limits.composition_nodes = 7
	limits.status_regions = 5
	limits.list_items = 16
	limits.tree_nodes = 16
	limits.fixed_choices = 4
	limits.styles = 8
	limits.decorations = 8
	limits.event_subscriptions = 8
	limits.queued_events = 8
	limits.callback_depth = 4
	limits.deferred_work = 8
	return limits
}
