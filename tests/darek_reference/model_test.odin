// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package darek_reference

import "core:testing"

tree :: proc() -> [5]Definition {
	return {
		{id = 1, kind = .Project, label = "Odra", expandable = true},
		{id = 2, parent = 1, kind = .Directory, label = "docs", expandable = true},
		{id = 3, parent = 2, kind = .File, label = "guide.md"},
		{id = 4, parent = 1, kind = .Directory, label = "src", expandable = true},
		{id = 5, parent = 4, kind = .File, label = "main.odin"},
	}
}

/* Ensures collapsed nodes cannot leak into visible navigation. */
@(test)
tree_expansion_controls_visible_navigation :: proc(t: ^testing.T) {
	model := model_init()
	defer model_close(&model)
	definitions := tree()
	published, failure := model_publish(&model, 1, definitions[:])
	testing.expect(t, published)
	testing.expect_value(t, failure, Failure_Code.None)
	testing.expect_value(t, model_visible_count(&model), 1)
	testing.expect(t, model_toggle_selected(&model))
	testing.expect_value(t, model_visible_count(&model), 3)
	testing.expect(t, model_move_visible(&model, 1))
	testing.expect_value(t, model.selected, Node_ID(2))
	testing.expect(t, model_toggle_selected(&model))
	testing.expect_value(t, model_visible_count(&model), 4)
	testing.expect(t, model_move_visible(&model, 1))
	testing.expect_value(t, model.selected, Node_ID(3))
	testing.expect(t, model_move_parent(&model))
	testing.expect_value(t, model.selected, Node_ID(2))
	testing.expect(t, model_move_sibling(&model, 1))
	testing.expect_value(t, model.selected, Node_ID(4))
	testing.expect(t, model_validate(&model))
}

/* Ensures refresh keeps stable identities and rejects stale publication. */
@(test)
refresh_keeps_identity_and_rejects_stale :: proc(t: ^testing.T) {
	model := model_init()
	defer model_close(&model)
	definitions := tree()
	first_ok, _ := model_publish(&model, 3, definitions[:])
	_ = model_toggle_selected(&model)
	_ = model_move_visible(&model, 2)
	testing.expect_value(t, model.selected, Node_ID(4))
	updated := []Definition {
		{id = 1, kind = .Project, label = "Odra", expandable = true},
		{id = 4, parent = 1, kind = .Directory, label = "source", expandable = true},
		{id = 6, parent = 1, kind = .File, label = "README.md"},
	}
	second_ok, _ := model_publish(&model, 4, updated)
	stale_ok, stale_failure := model_publish(&model, 4, updated)
	testing.expect(t, first_ok && second_ok && !stale_ok)
	testing.expect_value(t, stale_failure, Failure_Code.Invalid_Generation)
	testing.expect_value(t, model.selected, Node_ID(4))
	testing.expect_value(t, model.nodes[0].expanded, true)
	testing.expect_value(t, model.generation, u64(4))
	testing.expect(t, model_validate(&model))
}

/* Ensures panel visibility and focus exchange do not reset the tree. */
@(test)
panel_focus_keeps_tree :: proc(t: ^testing.T) {
	model := model_init()
	defer model_close(&model)
	definitions := tree()
	published, _ := model_publish(&model, 1, definitions[:])
	testing.expect(t, published)
	testing.expect(t, model_toggle_panel(&model))
	testing.expect(t, model.panel_visible && !model.panel_focused)
	testing.expect(t, model_toggle_focus(&model))
	testing.expect(t, model.panel_visible && model.panel_focused)
	testing.expect(t, model_toggle_focus(&model))
	testing.expect(t, model.panel_visible && !model.panel_focused)
	testing.expect(t, model_toggle_panel(&model))
	testing.expect(t, !model.panel_visible && !model.panel_focused)
	testing.expect_value(t, model.generation, u64(1))
	testing.expect(t, model_validate(&model))
}

/* Ensures invalid tree publications leave the last valid generation active. */
@(test)
bad_publish_keeps_last_generation :: proc(t: ^testing.T) {
	model := model_init()
	defer model_close(&model)
	definitions := tree()
	baseline_ok, _ := model_publish(&model, 7, definitions[:])
	duplicate := []Definition {
		{id = 1, kind = .Project, label = "one", expandable = true},
		{id = 1, kind = .Directory, label = "two", expandable = true},
	}
	duplicate_ok, duplicate_failure := model_publish(&model, 8, duplicate)
	orphan := []Definition {
		{id = 9, parent = 44, kind = .File, label = "orphan"},
	}
	orphan_ok, orphan_failure := model_publish(&model, 8, orphan)
	testing.expect(t, baseline_ok && !duplicate_ok && !orphan_ok)
	testing.expect_value(t, duplicate_failure, Failure_Code.Duplicate_Node)
	testing.expect_value(t, orphan_failure, Failure_Code.Missing_Parent)
	testing.expect_value(t, model.generation, u64(7))
	testing.expect_value(t, model.count, 5)
	testing.expect(t, model_validate(&model))
}

/* Exercises generated navigation traces to protect invariants and cleanup. */
@(test)
navigation_keeps_invariants :: proc(t: ^testing.T) {
	model := model_init()
	definitions := tree()
	for generation in 1 ..= 256 {
		published, failure := model_publish(&model, u64(generation), definitions[:])
		testing.expectf(t, published, "generation %d failed with %v", generation, failure)
		_ = model_toggle_selected(&model)
		_ = model_move_visible(&model, 1)
		_ = model_move_sibling(&model, 1)
		_ = model_move_parent(&model)
		testing.expectf(t, model_validate(&model), "generation %d invalid", generation)
	}
	model_close(&model)
	testing.expect_value(t, model, Model{})
}

/* Ensures Workspace roots preserve ordering, tree state, and checked context. */
@(test)
workspace_roots_keep_order_and_context :: proc(t: ^testing.T) {
	model := model_init()
	defer model_close(&model)
	initial := []Definition {
		{id = 10, kind = .Project, label = "Core", expandable = true},
		{id = 11, parent = 10, kind = .Directory, label = "src", expandable = true},
		{id = 20, kind = .Project, label = "Docs", expandable = true},
		{id = 21, parent = 20, kind = .File, label = "guide.md"},
	}
	published, failure := model_publish_workspace(&model, 1, 7, initial)
	testing.expectf(t, published, "Workspace publication failed with %v", failure)
	testing.expect_value(t, model.root_mode, Root_Mode.Workspace)
	testing.expect_value(t, model.workspace_generation, u64(7))
	testing.expect_value(t, model_visible_count(&model), 2)
	testing.expect(t, model_toggle_selected(&model))
	testing.expect(t, model_move_visible(&model, 1))
	testing.expect_value(t, model.selected, Node_ID(11))

	reordered := []Definition {
		{id = 20, kind = .Project, label = "Docs", expandable = true},
		{id = 21, parent = 20, kind = .File, label = "guide.md"},
		{id = 10, kind = .Project, label = "Core", expandable = true},
		{id = 11, parent = 10, kind = .Directory, label = "src", expandable = true},
	}
	replaced, _ := model_publish_workspace(&model, 2, 8, reordered)
	testing.expect(t, replaced)
	testing.expect_value(t, model.nodes[0].definition.id, Node_ID(20))
	testing.expect_value(t, model.nodes[2].definition.id, Node_ID(10))
	testing.expect(t, model.nodes[2].expanded)
	testing.expect_value(t, model.selected, Node_ID(11))
	testing.expect(t, model_validate(&model))
}

/* Ensures membership changes and exclusive roots reconcile node identity. */
@(test)
workspace_changes_reconcile_identity :: proc(t: ^testing.T) {
	model := model_init()
	defer model_close(&model)
	one := []Definition {{id = 10, kind = .Project, label = "Core", expandable = true}}
	one_ok, _ := model_publish_workspace(&model, 1, 4, one)
	testing.expect(t, one_ok)
	testing.expect_value(t, model_visible_count(&model), 1)

	with_missing := []Definition {
		{id = 10, kind = .Project, label = "Core", expandable = true},
		{id = 30, kind = .Project, label = "Missing", unavailable = true},
	}
	added, _ := model_publish_workspace(&model, 2, 5, with_missing)
	testing.expect(t, added)
	testing.expect_value(t, model_visible_count(&model), 2)
	model.selected = 30

	removed, _ := model_publish_workspace(&model, 3, 6, one)
	testing.expect(t, removed)
	testing.expect_value(t, model.selected, Node_ID(10))

	exclusive := []Definition {
		{id = 10, kind = .Project, label = "Core", expandable = true},
		{id = 11, parent = 10, kind = .Directory, label = "src", expandable = true},
	}
	exclusive_ok, _ := model_publish(&model, 4, exclusive)
	testing.expect(t, exclusive_ok)
	testing.expect_value(t, model.root_mode, Root_Mode.Exclusive_Project)
	testing.expect_value(t, model.workspace_generation, u64(0))
	testing.expect_value(t, model.nodes[0].definition.id, Node_ID(10))
	testing.expect(t, model_validate(&model))
}
