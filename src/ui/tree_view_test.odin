// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ui

import "core:testing"

@(test)
/* tree_view_and_panel_publish_one_checked_hierarchical_surface. */
tree_and_panel_publish_hierarchy :: proc(t: ^testing.T) {
	registry: Registry
	initialized, _ := registry_init(&registry, Registry_ID(81))
	testing.expect(t, initialized)
	if !initialized do return
	defer registry_close(&registry)
	proposal, prepared, _ := proposal_begin(&registry)
	_, normal_ok, _ := proposal_add_style(&proposal, .List_Normal)
	_, current_ok, _ := proposal_add_style(&proposal, .List_Current, {.Reverse})
	nodes := []Tree_Node_Definition {
		{id = 1, text = "Odra", icon = "◆", expandable = true, expanded = true,
			action = tree_test_action(1)},
		{id = 2, parent = 1, text = "src", depth = 1, expandable = true,
			expanded = true, action = tree_test_action(2)},
		{id = 3, parent = 2, text = "main.odin", icon = "λ", depth = 2,
			indent_depth = 1,
			action = tree_test_action(3)},
	}
	view, projected, projection_failure := proposal_project_tree_view(
		&proposal,
		Tree_Projection_Request {
			model = {owner_id = 7, model_id = 8, generation = 9},
			read_only = true,
			position = {
				presentation_generation = 1,
				selection_owner = .Model,
				current_item = 2,
				viewport_items = 8,
			},
		},
		nodes,
	)
	testing.expectf(t, projected, "tree projection failed with %v", projection_failure.code)
	if !projected do return
	surface, surfaced, _ := proposal_add_surface(
		&proposal,
		Surface_Descriptor {
			owner_id = 7,
			view = view,
			focusable = true,
			visible = true,
			required_profile = 1,
			geometry = {height = 8, width = 32},
		},
	)
	leaf, leaf_ok, _ := proposal_add_surface_node(&proposal, surface)
	panel, panel_ok, _ := proposal_add_panel(&proposal, leaf, .Left, 32)
	root_ok, _ := proposal_set_root(&proposal, panel, surface)
	root, published, publish_failure := proposal_publish(
		&registry, &proposal, tree_test_renderer(),
	)
	testing.expectf(t, published, "tree publication failed with %v", publish_failure.code)
	if !published do return
	snapshot, copied, _ := registry_snapshot(&registry, root, tree_test_renderer())
	testing.expect(t, copied)
	if !copied do return
	defer snapshot_close(&snapshot)
	state, viewed := snapshot_view(&snapshot)
	visible, visible_ok := snapshot_tree_visible_nodes(state, state.views[0])
	hit, hit_ok, _ := snapshot_hit_test(
		state,
		Hit_Request{root = root, row = 2, column = 3},
	)
	label, label_ok := snapshot_tree_node_text(state, visible[2])
	icon, icon_ok := snapshot_tree_node_icon(state, visible[2])
	stats, stats_ok, _ := registry_stats(&registry)
	testing.expect(
		t,
		prepared && normal_ok && current_ok && surfaced && leaf_ok && panel_ok &&
			root_ok && viewed && visible_ok && hit_ok && label_ok && icon_ok && stats_ok,
	)
	testing.expect_value(t, label, "main.odin")
	testing.expect_value(t, icon, "λ")
	testing.expect_value(t, visible[2].depth, u16(2))
	testing.expect_value(t, visible[2].indent_depth, u16(1))
	testing.expect_value(t, visible[2].parent, Tree_Node_ID(2))
	testing.expect_value(t, hit.item.kind, Semantic_Item_Kind.Tree)
	testing.expect_value(t, hit.item.model, Model_Reference{owner_id = 7, model_id = 8, generation = 9})
	testing.expect_value(t, hit.item.item_id, u64(3))
	testing.expect_value(t, hit.item.presentation_generation, u64(1))
	testing.expect_value(t, hit.item.projection_index, u32(2))
	testing.expect_value(t, hit.item.action, tree_test_action(3))
	testing.expect_value(t, state.composition[1].kind, Composition_Kind.Panel)
	testing.expect_value(t, state.composition[1].panel_edge, Panel_Edge.Left)
	testing.expect_value(t, state.composition[1].panel_extent, u32(32))
	testing.expect_value(t, stats.tree_nodes, u32(3))
	testing.expect_value(t, stats.accounting.tree_nodes, u32(3))
}

@(test)
/* tree_view_accepts_an_ordered_forest_with_independent_roots. */
accepts_an_ordered_forest_with_independent_roots :: proc(t: ^testing.T) {
	registry: Registry
	initialized, _ := registry_init(&registry, 73)
	testing.expect(t, initialized)
	if !initialized do return
	defer registry_close(&registry)
	proposal, prepared, _ := proposal_begin(&registry)
	defer proposal_abort(&proposal)
	_, normal_ok, _ := proposal_add_style(&proposal, .List_Normal)
	_, current_ok, _ := proposal_add_style(&proposal, .List_Current, {.Reverse})
	nodes := []Tree_Node_Definition {
		{id = 1, text = "First", expandable = true, expanded = true,
			action = tree_test_action(1)},
		{id = 2, parent = 1, text = "first.txt", depth = 1,
			action = tree_test_action(2)},
		{id = 3, text = "Second", expandable = true, expanded = true,
			action = tree_test_action(3)},
		{id = 4, parent = 3, text = "second.txt", depth = 1,
			action = tree_test_action(4)},
	}
	view, projected, failure := proposal_project_tree_view(
		&proposal,
		Tree_Projection_Request {
			model = {owner_id = 1, model_id = 1, generation = 1},
			position = {
				presentation_generation = 1,
				selection_owner = .View,
				viewport_items = 4,
			},
		},
		nodes,
	)
	surface, surfaced, _ := proposal_add_surface(
		&proposal,
		Surface_Descriptor {
			owner_id = 1,
			view = view,
			focusable = true,
			visible = true,
			required_profile = 1,
			geometry = {height = 4, width = 24},
		},
	)
	leaf, leaf_ok, _ := proposal_add_surface_node(&proposal, surface)
	root_ok, _ := proposal_set_root(&proposal, leaf, surface)
	_, published, publish_failure := proposal_publish(&registry, &proposal, tree_test_renderer())
	testing.expect(
		t,
		prepared && normal_ok && current_ok && projected && surfaced && leaf_ok && root_ok && published,
	)
	testing.expect_value(t, failure.code, Failure_Code.None)
	testing.expect_value(t, publish_failure.code, Failure_Code.None)
}

@(test)
/* tree_view_rejects_duplicate_or_orphaned_nodes_before_publication. */
rejects_invalid_nodes_before_publication :: proc(t: ^testing.T) {
	registry: Registry
	initialized, _ := registry_init(&registry, Registry_ID(82))
	testing.expect(t, initialized)
	if !initialized do return
	defer registry_close(&registry)
	proposal, _, _ := proposal_begin(&registry)
	defer proposal_abort(&proposal)
	_, _, _ = proposal_add_style(&proposal, .List_Normal)
	_, _, _ = proposal_add_style(&proposal, .List_Current, {.Reverse})
	request := Tree_Projection_Request {
		model = {owner_id = 1, model_id = 2, generation = 3},
		position = {
			presentation_generation = 1,
			selection_owner = .View,
			current_item = 0,
			viewport_items = 4,
		},
	}
	duplicate := []Tree_Node_Definition {
		{id = 1, text = "root", expandable = true, expanded = true,
			action = tree_test_action(1)},
		{id = 1, parent = 1, text = "duplicate", depth = 1,
			action = tree_test_action(2)},
	}
	_, duplicate_ok, duplicate_failure := proposal_project_tree_view(
		&proposal, request, duplicate,
	)
	orphan := []Tree_Node_Definition {{
		id = 2,
		parent = 9,
		text = "orphan",
		depth = 1,
		action = tree_test_action(2),
	}}
	_, orphan_ok, orphan_failure := proposal_project_tree_view(&proposal, request, orphan)
	testing.expect(t, !duplicate_ok && !orphan_ok)
	testing.expect_value(t, duplicate_failure.code, Failure_Code.Duplicate_Tree_Node)
	testing.expect_value(t, orphan_failure.code, Failure_Code.Invalid_Tree_Node)
}

@(private)
tree_test_action :: proc(id: u64) -> List_Action_Reference {
	return {owner_id = 7, action_id = List_Action_ID(id), generation = 1}
}

@(private)
tree_test_renderer :: proc() -> Renderer_Profile {
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
