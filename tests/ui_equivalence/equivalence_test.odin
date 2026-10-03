// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ui_equivalence

import ui "../../src/ui"
import reference "../ui_reference"
import "core:testing"

/* Cross-checks generated UI publications against the independent lifecycle model. */
@(test)
publications_match_lifecycle_model :: proc(t: ^testing.T) {
	registry: ui.Registry
	registry_ok, _ := ui.registry_init(&registry, ui.Registry_ID(71))
	testing.expect(t, registry_ok)
	if !registry_ok {
		return
	}
	defer ui.registry_close(&registry)
	model: reference.Model
	root: ui.Root_Handle

	for case_index in 0 ..< 64 {
		surface_count := case_index % 4 + 1
		reference_proposal := reference.proposal_init(model.generation)
		proposal, prepared, _ := ui.proposal_begin(&registry, root)
		if !prepared {
			testing.expectf(t, false, "case %d failed to prepare", case_index)
			return
		}
		_, text_style_ok, _ := ui.proposal_add_style(&proposal, .Text_Normal)
		_, list_style_ok, _ := ui.proposal_add_style(&proposal, .List_Normal)
		_, list_current_style_ok, _ := ui.proposal_add_style(
			&proposal, .List_Current, {.Reverse},
		)
		production_nodes: [4]ui.Object_Handle
		production_surfaces: [4]ui.Object_Handle
		reference_nodes: [4]u16
		reference_surfaces: [4]u16
		input_index := -1
		built := text_style_ok && list_style_ok && list_current_style_ok

		for index in 0 ..< surface_count {
			kind := generated_kind(case_index, index)
			selection_owner := ui.Selection_Owner.None
			reference_owner := reference.Selection_Owner.None
			if kind == .List_View || kind == .Tree_View {
				if (case_index + index) % 2 == 0 {
					selection_owner = .Model
					reference_owner = .Model
				} else {
					selection_owner = .View
					reference_owner = .View
				}
			}
			model_reference := ui.Model_Reference {
				owner_id = ui.Owner_ID(index + 1),
				model_id = ui.Model_ID(case_index * 8 + index + 1),
				generation = ui.Model_Generation(case_index + 1),
			}
			view: ui.Object_Handle
			projection_ok, view_ok: bool
			if kind == .List_View {
				items: [16]ui.List_Item_Definition
				for item_index in 0 ..< len(items) {
					items[item_index] = ui.List_Item_Definition {
						id = ui.List_Item_ID(item_index + 1),
						text = "item",
						action = {
							owner_id = ui.Owner_ID(index + 1),
							action_id = ui.List_Action_ID(item_index + 1),
							generation = u64(case_index + 1),
						},
					}
				}
				view, view_ok, _ = ui.proposal_project_list_view(
					&proposal,
					ui.List_Projection_Request {
						model = model_reference,
						position = {
							presentation_generation = u64(case_index + 1),
							selection_owner = selection_owner,
							current_item = 0,
							viewport_items = 16,
						},
					},
					items[:],
				)
				projection_ok = view_ok
			} else if kind == .Tree_View {
				nodes: [16]ui.Tree_Node_Definition
				for node_index in 0 ..< len(nodes) {
					nodes[node_index] = ui.Tree_Node_Definition {
						id = ui.Tree_Node_ID(node_index + 1),
						text = "node",
						action = {
							owner_id = ui.Owner_ID(index + 1),
							action_id = ui.List_Action_ID(node_index + 1),
							generation = u64(case_index + 1),
						},
					}
				}
				view, view_ok, _ = ui.proposal_project_tree_view(
					&proposal,
					ui.Tree_Projection_Request {
						model = model_reference,
						position = {
							presentation_generation = u64(case_index + 1),
							selection_owner = selection_owner,
							current_item = 0,
							viewport_items = 16,
						},
					},
					nodes[:],
				)
				projection_ok = view_ok
			} else if kind == .Input {
				view, view_ok, _ = ui.proposal_project_input(
					&proposal,
					ui.Input_Projection_Request {
						model = model_reference,
						presentation_generation = u64(case_index + 1),
						backing_generation = u64(case_index + 1),
						cursor_offset = 8,
						first_visible_byte = 1,
						viewport_bytes = 8,
						validation = .Valid,
					},
					"12345678",
				)
				projection_ok = view_ok
				input_index = index
			} else {
				projection, projected, _ := ui.proposal_add_projection(
					&proposal,
					model_reference,
					u64(64 + index),
				)
				projection_ok = projected
				view_descriptor := ui.Visual_View_Descriptor {
					kind = kind,
					projection = projection,
				}
				view, view_ok, _ = ui.proposal_add_view(&proposal, view_descriptor)
			}
			surface, surface_ok, _ := ui.proposal_add_surface(
				&proposal,
				ui.Surface_Descriptor {
					owner_id = ui.Owner_ID(index + 1),
					view = view,
					focusable = true,
					visible = true,
					required_profile = ui.Renderer_Profile_ID(1),
				},
			)
			node, node_ok, _ := ui.proposal_add_surface_node(&proposal, surface)
			production_surfaces[index] = surface
			production_nodes[index] = node

			reference_kind := reference.View_Kind.Text
			switch kind {
			case .Text_View:
				reference_kind = .Text
			case .Terminal_View:
				built = false
			case .List_View:
				reference_kind = .List
			case .Tree_View:
				reference_kind = .Tree
			case .Input:
				reference_kind = .Input
			case .Invalid:
				built = false
			}
			reference_surface, reference_node, reference_ok, _ :=
				reference.proposal_add_surface(
					&reference_proposal,
					reference_kind,
					true,
					reference_owner,
				)
			reference_surfaces[index] = reference_surface
			reference_nodes[index] = reference_node
			built = built && projection_ok && view_ok && surface_ok && node_ok && reference_ok
		}

		production_root := production_nodes[0]
		reference_root := reference_nodes[0]
		for index in 1 ..< surface_count {
			orientation := ui.Split_Orientation.Left_Right
			reference_orientation := reference.Orientation.Left_Right
			if (case_index + index) % 2 == 0 {
				orientation = .Above_Below
				reference_orientation = .Above_Below
			}
			production_root, built, _ = ui.proposal_add_split(
				&proposal,
				production_root,
				production_nodes[index],
				orientation,
			)
			reference_split: bool
			reference_root, reference_split, _ = reference.proposal_add_split(
				&reference_proposal,
				reference_root,
				reference_nodes[index],
				reference_orientation,
			)
			built = built && reference_split
		}
		production_root_ok, _ := ui.proposal_set_root(
			&proposal,
			production_root,
			production_surfaces[0],
		)
		reference_root_ok, _ := reference.proposal_set_root(
			&reference_proposal,
			reference_root,
			reference_surfaces[0],
		)
		production_published: bool
		root, production_published, _ = ui.proposal_publish(
			&registry,
			&proposal,
			generated_renderer(),
		)
		_, reference_published, _ := reference.model_publish(&model, &reference_proposal)
		stats, stats_ok, _ := ui.registry_stats(&registry)
		snapshot, snapshot_ok, _ := ui.registry_snapshot(
			&registry,
			root,
			generated_renderer(),
		)
		view, snapshot_view_ok := ui.snapshot_view(&snapshot)

		testing.expectf(
			t,
			built && production_root_ok && reference_root_ok && production_published &&
			reference_published && stats_ok && snapshot_ok && snapshot_view_ok,
			"case %d failed publication",
			case_index,
		)
		testing.expect_value(t, u64(root.generation), model.generation)
		testing.expect_value(t, stats.surfaces, model.active.surface_count)
		testing.expect_value(t, stats.composition_nodes, model.active.node_count)
		testing.expect_value(t, len(view.surfaces), int(model.active.surface_count))
		testing.expect_value(t, len(view.composition), int(model.active.node_count))

		if input_index >= 0 {
			production_captured, _ := ui.registry_capture_focus(
				&registry,
				production_surfaces[input_index],
			)
			reference_input, _ := reference.model_surface_handle(
				&model,
				reference_surfaces[input_index],
			)
			reference_captured, _ := reference.model_capture_focus(&model, reference_input)
			production_return, production_released, _ := ui.registry_release_focus(&registry)
			reference_return, reference_released, _ := reference.model_release_focus(&model)
			testing.expect(
				t,
				production_captured && reference_captured && production_released &&
				reference_released,
			)
			testing.expect_value(t, production_return.slot, u32(0))
			testing.expect_value(t, reference_return.id, reference_surfaces[0])
		}
		if snapshot_ok {
			ui.snapshot_close(&snapshot)
		}
		testing.expect(t, reference.model_validate(&model))
	}
}

/* Ensures generated invalid replacements preserve model and production generations. */
@(test)
bad_replacements_keep_generations :: proc(t: ^testing.T) {
	registry: ui.Registry
	registry_ok, _ := ui.registry_init(&registry, ui.Registry_ID(72))
	testing.expect(t, registry_ok)
	if !registry_ok {
		return
	}
	defer ui.registry_close(&registry)
	model: reference.Model
	root := ui.Root_Handle{}

	for case_index in 0 ..< 32 {
		valid_proposal, _, _ := ui.proposal_begin(&registry, root)
		_, _, _ = ui.proposal_add_style(&valid_proposal, .Text_Normal)
		projection, _, _ := ui.proposal_add_projection(
			&valid_proposal,
			ui.Model_Reference {
				owner_id = 1,
				model_id = 1,
				generation = ui.Model_Generation(case_index + 1),
			},
			64,
		)
		view, _, _ := ui.proposal_add_view(
			&valid_proposal,
			ui.Visual_View_Descriptor{kind = .Text_View, projection = projection},
		)
		surface, _, _ := ui.proposal_add_surface(
			&valid_proposal,
			ui.Surface_Descriptor {
				owner_id = 1,
				view = view,
				focusable = true,
				visible = true,
				required_profile = 1,
			},
		)
		node, _, _ := ui.proposal_add_surface_node(&valid_proposal, surface)
		_, _ = ui.proposal_set_root(&valid_proposal, node, surface)
		root, _, _ = ui.proposal_publish(&registry, &valid_proposal, generated_renderer())

		reference_valid := reference.proposal_init(model.generation)
		reference_surface, reference_node, _, _ := reference.proposal_add_surface(
			&reference_valid,
			.Text,
		)
		_, _ = reference.proposal_set_root(&reference_valid, reference_node, reference_surface)
		_, _, _ = reference.model_publish(&model, &reference_valid)
		before_generation := model.generation

		invalid_proposal, _, _ := ui.proposal_begin(&registry, root)
		_, _, _ = ui.proposal_add_style(&invalid_proposal, .Text_Normal)
		invalid_projection, _, _ := ui.proposal_add_projection(
			&invalid_proposal,
			ui.Model_Reference{owner_id = 1, model_id = 2, generation = 1},
			64,
		)
		invalid_view, _, _ := ui.proposal_add_view(
			&invalid_proposal,
			ui.Visual_View_Descriptor{kind = .Text_View, projection = invalid_projection},
		)
		invalid_surface, _, _ := ui.proposal_add_surface(
			&invalid_proposal,
			ui.Surface_Descriptor {
				owner_id = 1,
				view = invalid_view,
				focusable = true,
				visible = true,
				required_profile = 2,
			},
		)
		invalid_node, _, _ := ui.proposal_add_surface_node(&invalid_proposal, invalid_surface)
		_, _ = ui.proposal_set_root(&invalid_proposal, invalid_node, invalid_surface)
		_, production_replaced, _ := ui.proposal_publish(
			&registry,
			&invalid_proposal,
			generated_renderer(),
		)
		ui.proposal_abort(&invalid_proposal)

		reference_invalid := reference.proposal_init(model.generation)
		_, invalid_reference_node, _, _ := reference.proposal_add_surface(
			&reference_invalid,
			.Text,
		)
		reference_invalid.root_node = invalid_reference_node
		reference_invalid.focus_surface = 99
		_, reference_replaced, _ := reference.model_publish(&model, &reference_invalid)
		current, current_ok, _ := ui.registry_handle(&registry)

		testing.expect(t, !production_replaced && !reference_replaced && current_ok)
		testing.expect_value(t, current, root)
		testing.expect_value(t, model.generation, before_generation)
	}
}

generated_kind :: proc(case_index, surface_index: int) -> ui.Visual_Kind {
	switch (case_index + surface_index) % 4 {
	case 0:
		return .Text_View
	case 1:
		return .List_View
	case 2:
		return .Tree_View
	case 3:
		return .Input
	}
	return .Invalid
}

generated_renderer :: proc() -> ui.Renderer_Profile {
	return ui.Renderer_Profile {
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
