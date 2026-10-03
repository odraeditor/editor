// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ui

import "core:mem"
import "core:testing"

@(test)
/* list_view_projection_copies_items_actions_marks_and_clipped_viewport. */
projection_copies_items_and_view :: proc(t: ^testing.T) {
	registry: Registry
	initialized, _ := registry_init(&registry, Registry_ID(61))
	testing.expect(t, initialized)
	if !initialized do return
	defer registry_close(&registry)
	proposal, prepared, _ := proposal_begin(&registry)
	_, normal_style, _ := proposal_add_style(&proposal, .List_Normal)
	_, current_style, _ := proposal_add_style(&proposal, .List_Current, {.Reverse})
	_, emphasis_style, _ := proposal_add_style(&proposal, .List_Emphasis, {.Bold})
	_, metadata_style, _ := proposal_add_style(&proposal, .Filesystem_Metadata, {.Dim})
	_, save_style, _ := proposal_add_style(&proposal, .List_Mark_Save, {.Bold})
	_, kill_style, _ := proposal_add_style(&proposal, .List_Mark_Kill, {.Dim})
	items := []List_Item_Definition {
		{id = 1, text = "Heading", passive = true},
		{id = 2, text = "Open 界", action = list_test_action(2), mark = .Save,
			emphasis_bytes = 4, emphasis_style = .List_Emphasis},
		{id = 3, text = "Close buffer", action = list_test_action(3), mark = .Kill},
		{id = 4, text = "Return", action = list_test_action(4)},
	}
	items[3].style_spans[0] = {start_byte = 0, end_byte = 6, style_role = .Filesystem_Metadata}
	items[3].style_span_count = 1
	list_view, list_ok, list_failure := proposal_project_list_view(
		&proposal,
		List_Projection_Request {
			model = {owner_id = 9, model_id = 17, generation = 23},
			mark_lane = true,
			position = {
				presentation_generation = 5,
				selection_owner = .View,
				current_item = 2,
				first_visible_item = 1,
				viewport_items = 2,
			},
		},
		items,
	)
	testing.expectf(t, list_ok, "list projection failed with %v", list_failure.code)
	if !list_ok do return
	surface, surface_ok, _ := proposal_add_surface(
		&proposal,
		Surface_Descriptor {
			owner_id = 9,
			view = list_view,
			focusable = true,
			visible = true,
			required_profile = 1,
			geometry = {height = 2, width = 24},
		},
	)
	node, node_ok, _ := proposal_add_surface_node(&proposal, surface)
	root_ok, _ := proposal_set_root(&proposal, node, surface)
	root, published, publish_failure := proposal_publish(&registry, &proposal, test_renderer())
	testing.expectf(t, published, "list publication failed with %v", publish_failure.code)
	if !published do return
	snapshot, copied, _ := registry_snapshot(&registry, root, test_renderer())
	testing.expect(t, copied)
	if !copied do return
	defer snapshot_close(&snapshot)
	view, viewed := snapshot_view(&snapshot)
	all, all_ok := snapshot_list_items(view, view.views[0])
	visible, visible_ok := snapshot_list_visible_items(view, view.views[0])
	hit, hit_ok, _ := snapshot_hit_test(
		view,
		Hit_Request{root = root, row = 1, column = 3},
	)
	second_text, second_text_ok := snapshot_list_item_text(view, all[1])
	stats, stats_ok, _ := registry_stats(&registry)

	testing.expect(
		t,
			prepared && normal_style && current_style && emphasis_style && metadata_style && save_style && kill_style && surface_ok &&
			node_ok && root_ok && viewed && all_ok && visible_ok && hit_ok && second_text_ok && stats_ok,
	)
	testing.expect_value(t, len(all), 4)
	testing.expect_value(t, len(visible), 2)
	testing.expect_value(t, visible[0].id, List_Item_ID(2))
	testing.expect_value(t, visible[1].id, List_Item_ID(3))
	testing.expect_value(t, hit.item.kind, Semantic_Item_Kind.List)
	testing.expect_value(t, hit.item.model, Model_Reference{owner_id = 9, model_id = 17, generation = 23})
	testing.expect_value(t, hit.item.item_id, u64(3))
	testing.expect_value(t, hit.item.presentation_generation, u64(5))
	testing.expect_value(t, hit.item.projection_index, u32(2))
	testing.expect_value(t, hit.item.action, list_test_action(3))
	testing.expect_value(t, second_text, "Open 界")
	testing.expect(t, all[0].passive)
	testing.expect_value(t, all[1].mark, List_Mark.Save)
	testing.expect_value(t, all[1].emphasis_bytes, u32(4))
	testing.expect_value(t, all[1].emphasis_style, Style_Role.List_Emphasis)
	testing.expect_value(t, all[2].mark, List_Mark.Kill)
	testing.expect_value(t, all[2].action, list_test_action(3))
	testing.expect_value(t, all[3].style_span_count, u8(1))
	testing.expect_value(t, all[3].style_spans[0].style_role, Style_Role.Filesystem_Metadata)
	testing.expect_value(t, stats.list_items, u32(4))
	testing.expect_value(t, stats.accounting.list_items, u32(4))
	testing.expect(t, stats.accounting.projection_bytes > 0)
}

@(test)
/* list_view_navigation_enforces_selection_owner_and_keeps_current_visible. */
navigation_keeps_selection_visible :: proc(t: ^testing.T) {
	state := List_View_State {
		present = true,
		item_count = 8,
		position = {
			presentation_generation = 4,
			selection_owner = .View,
			current_item = 1,
			viewport_items = 3,
		},
	}
	moved, changed, moved_ok, _ := list_view_move_current(state, 5)
	testing.expect(t, changed && moved_ok)
	testing.expect_value(t, moved.position.current_item, i32(6))
	testing.expect_value(t, moved.position.first_visible_item, u32(4))
	testing.expect_value(t, moved.position.presentation_generation, u64(5))
	resized, resize_changed, resized_ok, _ := list_view_resize(moved, 1)
	testing.expect(t, resize_changed && resized_ok)
	testing.expect_value(t, resized.position.first_visible_item, u32(6))
	testing.expect_value(t, resized.position.presentation_generation, u64(6))
	_, repeated, repeated_ok, _ := list_view_move_current(resized, 0)
	testing.expect(t, !repeated && repeated_ok)

	model_state := state
	model_state.position.selection_owner = .Model
	_, _, wrong_move, wrong_move_failure := list_view_move_current(model_state, 1)
	followed, followed_changed, followed_ok, _ := list_view_follow_model(model_state, 7)
	_, _, wrong_follow, wrong_follow_failure := list_view_follow_model(state, 2)
	testing.expect(t, !wrong_move && followed_changed && followed_ok && !wrong_follow)
	testing.expect_value(t, wrong_move_failure.code, Failure_Code.Wrong_Owner)
	testing.expect_value(t, wrong_follow_failure.code, Failure_Code.Wrong_Owner)
	testing.expect_value(t, followed.position.current_item, i32(7))
	testing.expect_value(t, followed.position.first_visible_item, u32(5))
	testing.expect_value(t, followed.position.presentation_generation, u64(5))
}

@(test)
/* list_view_projection_rejects_invalid_or_excess_items_before_publication. */
projection_rejects_excess_items :: proc(t: ^testing.T) {
	limits := DEFAULT_RESOURCE_LIMITS
	limits.list_items = 2
	registry: Registry
	initialized, _ := registry_init(&registry, Registry_ID(62), limits)
	testing.expect(t, initialized)
	if !initialized do return
	defer registry_close(&registry)
	proposal, _, _ := proposal_begin(&registry)
	_, _, _ = proposal_add_style(&proposal, .List_Normal)
	_, _, _ = proposal_add_style(&proposal, .List_Current, {.Reverse})
	_, _, _ = proposal_add_style(&proposal, .List_Emphasis, {.Bold})
	duplicate := []List_Item_Definition {
		{id = 1, text = "one", action = list_test_action(1)},
		{id = 1, text = "two", action = list_test_action(2)},
	}
	request := List_Projection_Request {
		model = {owner_id = 1, model_id = 2, generation = 3},
		position = {
			presentation_generation = 1,
			selection_owner = .View,
			current_item = 0,
			viewport_items = 2,
		},
	}
	_, duplicate_ok, duplicate_failure := proposal_project_list_view(
		&proposal, request, duplicate,
	)
	testing.expect(t, !duplicate_ok)
	testing.expect_value(t, duplicate_failure.code, Failure_Code.Duplicate_List_Item)
	passive_current := []List_Item_Definition {
		{id = 1, text = "Heading", passive = true},
		{id = 2, text = "one", action = list_test_action(1)},
	}
	_, passive_ok, passive_failure := proposal_project_list_view(
		&proposal, request, passive_current,
	)
	testing.expect(t, !passive_ok)
	testing.expect_value(t, passive_failure.code, Failure_Code.Invalid_List_Action)
	invalid_emphasis := []List_Item_Definition {{
		id = 2,
		text = "éclair",
		action = list_test_action(2),
		emphasis_bytes = 1,
		emphasis_style = .List_Emphasis,
	}}
	_, emphasis_ok, emphasis_failure := proposal_project_list_view(
		&proposal, request, invalid_emphasis,
	)
	testing.expect(t, !emphasis_ok)
	testing.expect_value(t, emphasis_failure.code, Failure_Code.Invalid_Style)

	valid := []List_Item_Definition {
		{id = 1, text = "one", action = list_test_action(1)},
		{id = 2, text = "two", action = list_test_action(2)},
	}
	view, valid_ok, _ := proposal_project_list_view(&proposal, request, valid)
	_, excess_ok, excess_failure := proposal_project_list_view(
		&proposal,
		List_Projection_Request {
			model = {owner_id = 1, model_id = 4, generation = 1},
			position = {
				presentation_generation = 1,
				selection_owner = .View,
				current_item = 0,
				viewport_items = 1,
			},
		},
		[]List_Item_Definition {{id = 3, text = "three", action = list_test_action(3)}},
	)
	testing.expect(t, valid_ok && !excess_ok)
	testing.expect_value(t, excess_failure.code, Failure_Code.List_Item_Limit)
	surface, _, _ := proposal_add_surface(
		&proposal,
		Surface_Descriptor {
			owner_id = 1,
			view = view,
			focusable = true,
			visible = true,
			required_profile = 1,
		},
	)
	node, _, _ := proposal_add_surface_node(&proposal, surface)
	_, _ = proposal_set_root(&proposal, node, surface)
	root, published, _ := proposal_publish(&registry, &proposal, test_renderer())
	snapshot, copied, _ := registry_snapshot(&registry, root, test_renderer())
	if copied do snapshot_close(&snapshot)
	testing.expect(t, published && copied)
}

@(test)
/* list_view_registry_and_snapshot_cleanup_release_all_copied_storage. */
cleanup_releases_copied_storage :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	limits := DEFAULT_RESOURCE_LIMITS
	limits.live_surfaces = 2
	limits.live_views = 2
	limits.composition_nodes = 3
	limits.status_regions = 3
	limits.list_items = 4
	limits.styles = 4
	limits.decorations = 4
	registry: Registry
	initialized, _ := registry_init(&registry, Registry_ID(63), limits, allocator)
	if initialized {
		proposal, _, _ := proposal_begin(&registry)
		_, _, _ = proposal_add_style(&proposal, .List_Normal)
		_, _, _ = proposal_add_style(&proposal, .List_Current, {.Reverse})
		view, projected, _ := proposal_project_list_view(
			&proposal,
			List_Projection_Request {
				model = {owner_id = 1, model_id = 1, generation = 1},
				position = {
					presentation_generation = 1,
					selection_owner = .View,
					current_item = 0,
					viewport_items = 1,
				},
			},
			[]List_Item_Definition {{id = 1, text = "owned", action = list_test_action(1)}},
		)
		surface, _, _ := proposal_add_surface(
			&proposal,
			Surface_Descriptor {
				owner_id = 1,
				view = view,
				focusable = true,
				visible = true,
				required_profile = 1,
			},
		)
		node, _, _ := proposal_add_surface_node(&proposal, surface)
		_, _ = proposal_set_root(&proposal, node, surface)
		root, published, _ := proposal_publish(&registry, &proposal, test_renderer())
		snapshot, copied, _ := registry_snapshot(&registry, root, test_renderer(), allocator)
		if copied do snapshot_close(&snapshot)
		closed, _ := registry_close(&registry)
		testing.expect(t, projected && published && copied && closed)
	}
	cleanup_bytes := tracking.current_memory_allocated
	mem.tracking_allocator_destroy(&tracking)
	testing.expect(t, initialized)
	testing.expect_value(t, cleanup_bytes, i64(0))
}

@(private)
list_test_action :: proc(id: u64) -> List_Action_Reference {
	return List_Action_Reference{owner_id = 1, action_id = List_Action_ID(id), generation = 1}
}
