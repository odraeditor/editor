// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ui

import "core:mem"
import "core:testing"

@(test)
/* Verifies the initial proposal publishes one complete checked generation. */
proposal_publishes_complete_checked_generation :: proc(t: ^testing.T) {
	registry: Registry
	initialized, _ := registry_init(&registry, Registry_ID(41))
	testing.expect(t, initialized)
	if !initialized {
		return
	}
	defer registry_close(&registry)

	proposal, prepared, _ := proposal_begin(&registry)
	_, style_ok, _ := proposal_add_style(&proposal, .Text_Normal)
	_, status_style_ok, _ := proposal_add_style(&proposal, .Status_Normal, {.Reverse})
	projection, projection_ok, _ := proposal_add_projection(
		&proposal,
		Model_Reference{owner_id = 1, model_id = 1, generation = 1},
		1_024,
	)
	view, view_ok, _ := proposal_add_view(
		&proposal,
		Visual_View_Descriptor{kind = .Text_View, projection = projection, read_only = false},
	)
	surface, surface_ok, _ := proposal_add_surface(
		&proposal,
		Surface_Descriptor {
			owner_id = 1,
			view = view,
			focusable = true,
			visible = true,
			required_profile = 1,
		},
	)
	node, node_ok, _ := proposal_add_surface_node(&proposal, surface)
	_, status_ok, _ := proposal_add_status(
		&proposal,
		Status_Region_Descriptor {
			owner_id = 1,
			placement = .Attached,
			surface = surface,
			rows = 1,
			style_role = .Status_Normal,
		},
		"buffer  point 0",
	)
	root_ok, _ := proposal_set_root(&proposal, node, surface)
	root, published, _ := proposal_publish(&registry, &proposal, test_renderer())
	stats, inspected, _ := registry_stats(&registry)

	testing.expect(
		t,
		prepared && style_ok && status_style_ok && projection_ok && view_ok &&
		surface_ok && node_ok && status_ok && root_ok && published && inspected,
	)
	testing.expect_value(t, root.generation, Root_Generation(1))
	testing.expect_value(t, stats.surfaces, u16(1))
	testing.expect_value(t, stats.views, u16(1))
	testing.expect_value(t, stats.projections, u16(1))
	testing.expect_value(t, stats.composition_nodes, u16(1))
	testing.expect_value(t, stats.status_regions, u16(1))
	testing.expect(t, stats.accounting.registry_bytes > 0)
	testing.expect(t, stats.accounting.snapshot_bytes > 0)
	testing.expect_value(t, stats.accounting.style_bytes, u64(2 * size_of(Style_Descriptor)))
	testing.expect_value(t, stats.accounting.decoration_bytes, u64(0))
}

@(test)
/* Ensures invalid replacement leaves the current root unchanged. */
invalid_replacement_preserves_current_root :: proc(t: ^testing.T) {
	registry: Registry
	initialized, _ := registry_init(&registry, Registry_ID(42))
	testing.expect(t, initialized)
	if !initialized {
		return
	}
	defer registry_close(&registry)
	first_root, first_ok := publish_single_text_root(&registry, {})
	testing.expect(t, first_ok)
	if !first_ok {
		return
	}

	proposal, prepared, _ := proposal_begin(&registry, first_root)
	_, _, _ = proposal_add_style(&proposal, .Text_Normal)
	projection, _, _ := proposal_add_projection(
		&proposal,
		Model_Reference{owner_id = 1, model_id = 2, generation = 1},
		64,
	)
	view, _, _ := proposal_add_view(
		&proposal,
		Visual_View_Descriptor{kind = .Text_View, projection = projection},
	)
	surface, _, _ := proposal_add_surface(
		&proposal,
		Surface_Descriptor {
			owner_id = 1,
			view = view,
			focusable = true,
			visible = true,
			required_profile = 2,
		},
	)
	node, _, _ := proposal_add_surface_node(&proposal, surface)
	_, _ = proposal_set_root(&proposal, node, surface)
	_, replaced, replace_failure := proposal_publish(&registry, &proposal, test_renderer())
	current, current_ok, _ := registry_handle(&registry)
	aborted := proposal_abort(&proposal)

	testing.expect(t, prepared && !replaced && current_ok && aborted)
	testing.expect_value(t, replace_failure.code, Failure_Code.Invalid_Proposal)
	testing.expect_value(t, current, first_root)
	_, stale_begin, stale_failure := proposal_begin(&registry, {})
	testing.expect(t, !stale_begin)
	testing.expect_value(t, stale_failure.code, Failure_Code.Stale_Root)
}

@(test)
/* Ensures input focus capture restores its checked return target. */
focus_capture_restores_return_target :: proc(t: ^testing.T) {
	registry: Registry
	initialized, _ := registry_init(&registry, Registry_ID(43))
	testing.expect(t, initialized)
	if !initialized {
		return
	}
	defer registry_close(&registry)

	proposal, _, _ := proposal_begin(&registry)
	_, _, _ = proposal_add_style(&proposal, .Text_Normal)
	text_projection, _, _ := proposal_add_projection(
		&proposal,
		Model_Reference{owner_id = 1, model_id = 1, generation = 1},
		64,
	)
	text_view, _, _ := proposal_add_view(
		&proposal,
		Visual_View_Descriptor{kind = .Text_View, projection = text_projection},
	)
	input_view, _, _ := proposal_project_input(
		&proposal,
		Input_Projection_Request {
			model = {owner_id = 2, model_id = 2, generation = 1},
			presentation_generation = 1,
			backing_generation = 1,
			cursor_offset = 5,
			viewport_bytes = 16,
			validation = .Valid,
		},
		"query",
	)
	text_surface, _, _ := proposal_add_surface(
		&proposal,
		Surface_Descriptor {
			owner_id = 1,
			view = text_view,
			focusable = true,
			visible = true,
			required_profile = 1,
		},
	)
	input_surface, _, _ := proposal_add_surface(
		&proposal,
		Surface_Descriptor {
			owner_id = 2,
			view = input_view,
			focusable = true,
			visible = true,
			required_profile = 1,
		},
	)
	text_node, _, _ := proposal_add_surface_node(&proposal, text_surface)
	input_node, _, _ := proposal_add_surface_node(&proposal, input_surface)
	root_node, _, _ := proposal_add_split(&proposal, text_node, input_node, .Above_Below)
	_, _ = proposal_set_root(&proposal, root_node, text_surface)
	_, published, _ := proposal_publish(&registry, &proposal, test_renderer())
	captured, _ := registry_capture_focus(&registry, input_surface)
	active, active_ok, _ := registry_focus(&registry)
	restored, released, _ := registry_release_focus(&registry)

	testing.expect(t, published && captured && active_ok && released)
	testing.expect(t, active.captured)
	testing.expect_value(t, active.target, input_surface)
	testing.expect_value(t, active.return_target, text_surface)
	testing.expect_value(t, restored, text_surface)
}

@(test)
/* Ensures registry teardown releases all owned storage. */
registry_teardown_releases_all_owned_storage :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	limits := DEFAULT_RESOURCE_LIMITS
	limits.live_surfaces = 4
	limits.live_views = 4
	limits.composition_nodes = 7
	limits.status_regions = 5
	limits.list_items = 16
	limits.styles = 8
	limits.decorations = 8
	limits.event_subscriptions = 8
	limits.queued_events = 8
	limits.callback_depth = 4
	limits.deferred_work = 8

	registry: Registry
	initialized, _ := registry_init(&registry, Registry_ID(44), limits, allocator)
	root, published := publish_single_text_root(&registry, {})
	closed, _ := registry_close(&registry)
	cleanup_bytes := tracking.current_memory_allocated
	mem.tracking_allocator_destroy(&tracking)

	testing.expect(t, initialized && published && closed)
	testing.expect(t, root.generation != Root_Generation(0))
	testing.expect_value(t, cleanup_bytes, i64(0))
	closed_again, _ := registry_close(&registry)
	testing.expect(t, !closed_again)
}

@(private)
publish_single_text_root :: proc(
	registry: ^Registry,
	expected: Root_Handle,
) -> (root: Root_Handle, ok: bool) {
	proposal, prepared, _ := proposal_begin(registry, expected)
	if !prepared {
		return {}, false
	}
	defer if proposal.state != nil do proposal_abort(&proposal)
	_, style_ok, _ := proposal_add_style(&proposal, .Text_Normal)
	projection, projection_ok, _ := proposal_add_projection(
		&proposal,
		Model_Reference{owner_id = 1, model_id = 1, generation = 1},
		64,
	)
	view, view_ok, _ := proposal_add_view(
		&proposal,
		Visual_View_Descriptor{kind = .Text_View, projection = projection},
	)
	surface, surface_ok, _ := proposal_add_surface(
		&proposal,
		Surface_Descriptor {
			owner_id = 1,
			view = view,
			focusable = true,
			visible = true,
			required_profile = 1,
		},
	)
	node, node_ok, _ := proposal_add_surface_node(&proposal, surface)
	root_ok, _ := proposal_set_root(&proposal, node, surface)
	published: bool
	root, published, _ = proposal_publish(registry, &proposal, test_renderer())
	return root, style_ok && projection_ok && view_ok && surface_ok && node_ok &&
		root_ok && published
}

@(private)
test_renderer :: proc() -> Renderer_Profile {
	return Renderer_Profile {
		id = 1,
		capabilities = {
			.Cell_Geometry,
			.Clipping,
			.Unicode_Profile,
			.Text_Cursor,
			.Input_Cursor,
			.Semantic_Attributes,
			.Atomic_Generation,
			.Full_Redraw,
		},
		unicode_profile = 17,
		max_rows = 80,
		max_columns = 240,
		max_cells = 19_200,
		attributes = {.Bold, .Dim, .Underline, .Reverse},
	}
}
