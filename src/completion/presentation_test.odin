// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package completion

import "../ui"
import "core:strings"
import "core:testing"

/* Verifies all candidate kinds, annotations, availability, selection, and viewport projection. */
@(test)
presentation_projects_semantic_candidate_rows :: proc(t: ^testing.T) {
	registry: Role_Registry
	controller: Controller
	composition, initialized := controller_fixture(&registry, &controller)
	testing.expect(t, initialized)
	if !initialized do return
	defer registry_close(&registry)
	defer controller_close(&controller)

	kinds := [?]Candidate_Kind {
		.Textual, .Callable, .Construct, .Value, .Type, .Module, .Field, .Keyword,
	}
	labels := [?]string {
		"pri-0", "pri-1", "pri-2", "pri-3", "pri-4", "pri-5", "pri-6", "pri-7",
	}
	items: [len(kinds)]Candidate
	for kind, index in kinds {
		items[index] = completion_presentation_candidate(
			Candidate_ID(801 + index),
			kind,
			labels[index],
		)
	}
	items[1].label_detail, _ = text_copy("(value: string)")
	items[1].description, _ = text_copy("core formatter")
	items[6].availability = .Deprecated
	items[7].availability = .Unavailable
	request := controller_request(811, 1, 3, composition)
	started, _ := controller_start(&controller, 812, 1, request, composition)
	queued, _ := controller_queue(&controller)
	sent, _ := controller_send(&controller)
	batch := controller_batch(request, items[:])
	published, _ := controller_publish(&controller, &batch)
	selected, _ := controller_select_candidate(&controller, 808)
	testing.expect(t, started && queued && sent && published && selected)

	ui_registry: ui.Registry
	ui_initialized, _ := ui.registry_init(&ui_registry, 813)
	testing.expect(t, ui_initialized)
	if !ui_initialized do return
	defer ui.registry_close(&ui_registry)
	proposal, prepared, _ := ui.proposal_begin(&ui_registry)
	styles_ok := completion_presentation_test_styles(&proposal)
	list, projected, projection_failure := controller_project_candidates(
		&controller,
		&proposal,
		completion_presentation_test_request(814, 3, 96),
	)
	testing.expectf(t, projected, "candidate projection failed with %v", projection_failure.code)
	if !projected do return
	surface, surface_ok, _ := ui.proposal_add_surface(
		&proposal,
		ui.Surface_Descriptor {
			owner_id = 82,
			view = list,
			focusable = true,
			visible = true,
			required_profile = 1,
			geometry = {height = 3, width = 96},
		},
	)
	node, node_ok, _ := ui.proposal_add_surface_node(&proposal, surface)
	root_ok, _ := ui.proposal_set_root(&proposal, node, surface)
	root, root_published, root_failure := ui.proposal_publish(
		&ui_registry,
		&proposal,
		completion_presentation_test_renderer(),
	)
	testing.expectf(t, root_published, "candidate publication failed with %v", root_failure.code)
	if !root_published do return
	snapshot, copied, _ := ui.registry_snapshot(
		&ui_registry,
		root,
		completion_presentation_test_renderer(),
	)
	testing.expect(t, copied)
	if !copied do return
	defer ui.snapshot_close(&snapshot)
	view, viewed := ui.snapshot_view(&snapshot)
	all, all_ok := ui.snapshot_list_items(view, view.views[0])
	visible, visible_ok := ui.snapshot_list_visible_items(view, view.views[0])
	first, first_ok := ui.snapshot_list_item_text(view, all[0])
	callable, callable_ok := ui.snapshot_list_item_text(view, all[1])
	deprecated, deprecated_ok := ui.snapshot_list_item_text(view, all[6])
	unavailable, unavailable_ok := ui.snapshot_list_item_text(view, all[7])

	testing.expect(
		t,
		prepared && styles_ok && surface_ok && node_ok && root_ok && viewed && all_ok &&
		visible_ok && first_ok && callable_ok && deprecated_ok && unavailable_ok,
	)
	testing.expect_value(t, len(all), 8)
	testing.expect_value(t, len(visible), 3)
	testing.expect_value(t, view.views[0].list.position.current_item, i32(7))
	testing.expect_value(t, view.views[0].list.position.first_visible_item, u32(5))
	testing.expect_value(t, first, "pri-0")
	testing.expect(t, strings.contains(callable, "(value: string) - core formatter"))
	testing.expect(t, strings.has_suffix(deprecated, "[deprecated]"))
	testing.expect(t, strings.has_suffix(unavailable, "[unavailable]"))
	testing.expect_value(t, all[0].icon_role, ui.List_Icon_Role.Textual)
	testing.expect_value(t, all[0].icon_style_role, ui.Style_Role.Syntax_String)
	testing.expect_value(t, all[1].icon_role, ui.List_Icon_Role.Callable)
	testing.expect_value(t, all[1].style_span_count, u8(1))
	testing.expect_value(t, all[1].style_spans[0].style_role, ui.Style_Role.List_Emphasis)
	testing.expect_value(t, all[6].style_spans[0].style_role, ui.Style_Role.Diagnostic_Rejected)
	testing.expect_value(t, all[7].action.owner_id, ui.Owner_ID(82))
	testing.expect_value(t, all[7].action.action_id, ui.List_Action_ID(808))
	testing.expect_value(t, all[7].action.generation, u64(1))
}

/* Verifies empty and narrow candidate generations remain valid and bounded. */
@(test)
presentation_keeps_empty_truncated_states :: proc(t: ^testing.T) {
	registry: Role_Registry
	controller: Controller
	composition, initialized := controller_fixture(&registry, &controller)
	if !initialized do return
	defer registry_close(&registry)
	defer controller_close(&controller)
	request := controller_request(821, 1, 3, composition)
	_, _ = controller_start(&controller, 822, 1, request, composition)
	_, _ = controller_queue(&controller)
	_, _ = controller_send(&controller)
	batch := controller_batch(request, nil)
	_, _ = controller_publish(&controller, &batch)

	ui_registry: ui.Registry
	ui_initialized, _ := ui.registry_init(&ui_registry, 823)
	if !ui_initialized do return
	defer ui.registry_close(&ui_registry)
	proposal, _, _ := ui.proposal_begin(&ui_registry)
	_ = completion_presentation_test_styles(&proposal)
	list, projected, _ := controller_project_candidates(
		&controller,
		&proposal,
		completion_presentation_test_request(824, 4, 16),
	)
	testing.expect(t, projected)
	if projected {
		surface, _, _ := ui.proposal_add_surface(
			&proposal,
			ui.Surface_Descriptor {
				owner_id = 82,
				view = list,
				focusable = true,
				visible = true,
				required_profile = 1,
				geometry = {height = 1, width = 16},
			},
		)
		node, _, _ := ui.proposal_add_surface_node(&proposal, surface)
		_, _ = ui.proposal_set_root(&proposal, node, surface)
		root, published, _ := ui.proposal_publish(
			&ui_registry,
			&proposal,
			completion_presentation_test_renderer(),
		)
		if published {
			snapshot, copied, _ := ui.registry_snapshot(
				&ui_registry, root, completion_presentation_test_renderer(),
			)
			if copied {
				view, _ := ui.snapshot_view(&snapshot)
				all, all_ok := ui.snapshot_list_items(view, view.views[0])
				testing.expect(t, all_ok)
				testing.expect_value(t, len(all), 0)
				testing.expect_value(t, view.views[0].list.position.current_item, i32(-1))
				ui.snapshot_close(&snapshot)
			}
			testing.expect(t, copied)
		}
		testing.expect(t, published)
	}

	row: Presentation_Row
	candidate := completion_presentation_candidate(825, .Module, "pri-long-candidate")
	candidate.description, _ = text_copy("long annotation")
	row_ok := completion_presentation_row(&row, &candidate, 16)
	row_text := string(row.bytes[:row.byte_count])
	testing.expect(t, row_ok)
	testing.expect_value(t, len(row_text), 16)
	testing.expect(t, strings.has_suffix(row_text, "..."))
}

@(private)
completion_presentation_candidate :: proc(
	id: Candidate_ID,
	kind: Candidate_Kind,
	label_value: string,
) -> Candidate {
	candidate := test_candidate(id)
	label, _ := text_copy(label_value)
	candidate.label = label
	candidate.filter_text = label
	candidate.sort_text = label
	candidate.insertion_text = label
	candidate.kind = kind
	candidate.copied_bytes = u64(len(label_value) * 4)
	return candidate
}

@(private)
completion_presentation_test_request :: proc(
	generation: u64,
	viewport_items, row_bytes: u32,
) -> Presentation_Request {
	registry: ui.Presentation_Profile_Registry
	initialized, _ := ui.presentation_profile_registry_init(&registry, 91)
	if !initialized do return {}
	scope, scoped, _ := ui.presentation_profile_registry_scope(
		&registry,
		.Interactive_Candidates,
	)
	record, recorded, _ := ui.presentation_profile_registry_record(&registry, scope.selected)
	_, _ = ui.presentation_profile_registry_close(&registry)
	if !scoped || !recorded do return {}
	return {
		presentation_generation = generation,
		viewport_items = viewport_items,
		row_bytes = row_bytes,
		profile = record,
	}
}

@(private)
completion_presentation_test_styles :: proc(proposal: ^ui.Proposal) -> bool {
	roles := [?]ui.Style_Role {
		.List_Normal,
		.List_Current,
		.List_Emphasis,
		.Syntax_String,
		.Syntax_Function,
		.Syntax_Constructor,
		.Syntax_Constant,
		.Syntax_Type,
		.Syntax_Label,
		.Syntax_Attribute,
		.Syntax_Keyword,
		.Popup_Diagnostic,
		.Popup_Unavailable,
		.Diagnostic_Rejected,
		.Status_Alert,
	}
	for role in roles {
		_, added, _ := ui.proposal_add_style(proposal, role)
		if !added do return false
	}
	return true
}

@(private)
completion_presentation_test_renderer :: proc() -> ui.Renderer_Profile {
	return {
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
