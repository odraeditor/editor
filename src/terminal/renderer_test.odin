// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package terminal_frontend

import "../display"
import "../editor"
import "../language"
import "../search"
import "../ui"
import editor_view "../view"
import "base:runtime"
import "core:mem"
import "core:sys/posix"
import "core:strings"
import "core:testing"

@(test)
/* terminal_renderer_uses_compact_text_icons_for_tree_structure. */
uses_compact_tree_icons :: proc(t: ^testing.T) {
	constraints := display.Viewport_Constraints{width_cells = 24, height_rows = 3}
	renderer: Renderer
	initialized, _ := renderer_init(&renderer, renderer_config(constraints))
	testing.expect(t, initialized)
	if !initialized do return
	defer renderer_close(&renderer)
	profile, profile_ok := renderer_ui_profile(&renderer)
	registry: ui.Registry
	registry_ok, _ := ui.registry_init(&registry, 78)
	testing.expect(t, profile_ok && registry_ok)
	if !profile_ok || !registry_ok do return
	defer ui.registry_close(&registry)
	proposal, prepared, _ := ui.proposal_begin(&registry)
	_, normal_ok, _ := ui.proposal_add_style(&proposal, .List_Normal)
	_, current_ok, _ := ui.proposal_add_style(&proposal, .List_Current, {.Reverse})
	_, directory_ok, _ := ui.proposal_add_style(&proposal, .Filesystem_Directory, {.Bold})
	nodes := []ui.Tree_Node_Definition {
		{id = 1, text = "root", icon = "◆", expandable = true, expanded = true,
			action = {owner_id = 1, action_id = 1, generation = 1}},
		{id = 2, parent = 1, text = "src", depth = 1, expandable = true,
			expanded = true,
			action = {owner_id = 1, action_id = 2, generation = 1}},
		{id = 3, parent = 2, text = "main.odin", icon = "λ", depth = 2,
			indent_depth = 1,
			action = {owner_id = 1, action_id = 3, generation = 1}},
	}
	tree, tree_ok, _ := ui.proposal_project_tree_view(
		&proposal,
		ui.Tree_Projection_Request {
			model = {owner_id = 1, model_id = 1, generation = 1},
			position = {presentation_generation = 1, selection_owner = .Model,
				current_item = 0, viewport_items = 3},
		},
		nodes,
	)
	surface, surface_ok, _ := ui.proposal_add_surface(
		&proposal,
		ui.Surface_Descriptor{owner_id = 1, view = tree, focusable = true, visible = true,
			required_profile = profile.id, geometry = {height = 3, width = 24}},
	)
	node, node_ok, _ := ui.proposal_add_surface_node(&proposal, surface)
	root_ok, _ := ui.proposal_set_root(&proposal, node, surface)
	root, published, _ := ui.proposal_publish(&registry, &proposal, profile)
	snapshot: ui.Snapshot
	copied := false
	if published do snapshot, copied, _ = ui.registry_snapshot(&registry, root, profile)
	ready := prepared && normal_ok && current_ok && directory_ok && tree_ok && surface_ok &&
		node_ok && root_ok && published && copied
	testing.expect(t, ready)
	if !ready do return
	defer ui.snapshot_close(&snapshot)
	frame, rendered, failure := renderer_prepare_ui(
		renderer_state(&renderer), UI_Presentation{root = &snapshot},
	)
	testing.expectf(t, rendered, "tree frame failed with %v", failure.code)
	if !rendered do return
	defer frame_close(&frame)
	output := string(frame.output[:frame.used])
	testing.expect(t, strings.contains(output, "◆ root"))
	testing.expect(t, strings.contains(output, "▾ src"))
	testing.expect(t, strings.contains(output, "λ main.odin"))
}

/* Verifies generic list lowering renders marks, selection, clipping, and empty rows. */
@(test)
encodes_rows_without_feature_branches :: proc(t: ^testing.T) {
	constraints := display.Viewport_Constraints{width_cells = 10, height_rows = 3}
	renderer: Renderer
	initialized, _ := renderer_init(&renderer, renderer_config(constraints))
	testing.expect(t, initialized)
	if !initialized do return
	defer renderer_close(&renderer)
	profile, profile_ok := renderer_ui_profile(&renderer)
	registry: ui.Registry
	registry_ok, _ := ui.registry_init(&registry, 79)
	testing.expect(t, profile_ok && registry_ok)
	if !profile_ok || !registry_ok do return
	defer ui.registry_close(&registry)
	proposal, prepared, _ := ui.proposal_begin(&registry)
	_, normal_ok, _ := ui.proposal_add_style(&proposal, .List_Normal)
	_, current_ok, _ := ui.proposal_add_style(&proposal, .List_Current, {.Reverse})
	_, emphasis_ok, _ := ui.proposal_add_style(&proposal, .List_Emphasis, {.Underline})
	_, metadata_ok, _ := ui.proposal_add_style(&proposal, .Filesystem_Metadata, {.Dim})
	_, save_ok, _ := ui.proposal_add_style(&proposal, .List_Mark_Save, {.Bold})
	_, kill_ok, _ := ui.proposal_add_style(&proposal, .List_Mark_Kill, {.Dim})
	action := proc(id: u64) -> ui.List_Action_Reference {
		return ui.List_Action_Reference{owner_id = 1, action_id = ui.List_Action_ID(id), generation = 1}
	}
	items := []ui.List_Item_Definition {
		{id = 1, text = "alphabet", action = action(1), mark = .Save,
			emphasis_bytes = 5, emphasis_style = .List_Emphasis},
		{id = 2, text = "界xyz", action = action(2), mark = .Kill},
	}
	items[1].style_spans[0] = {start_byte = 3, end_byte = 4, style_role = .Filesystem_Metadata}
	items[1].style_span_count = 1
	view, list_ok, _ := ui.proposal_project_list_view(
		&proposal,
		ui.List_Projection_Request {
			model = {owner_id = 1, model_id = 1, generation = 1},
			mark_lane = true,
			position = {
				presentation_generation = 1,
				selection_owner = .View,
				current_item = 1,
				viewport_items = 3,
			},
		},
		items,
	)
	surface, surface_ok, _ := ui.proposal_add_surface(
		&proposal,
		ui.Surface_Descriptor {
			owner_id = 1,
			view = view,
			focusable = true,
			visible = true,
			required_profile = profile.id,
			geometry = {column = 1, height = 3, width = 7},
		},
	)
	node, node_ok, _ := ui.proposal_add_surface_node(&proposal, surface)
	root_ok, _ := ui.proposal_set_root(&proposal, node, surface)
	root, published, _ := ui.proposal_publish(&registry, &proposal, profile)
	if proposal.state != nil do ui.proposal_abort(&proposal)
	snapshot: ui.Snapshot
	copied := false
	if published do snapshot, copied, _ = ui.registry_snapshot(&registry, root, profile)
	ready := prepared && normal_ok && current_ok && emphasis_ok && metadata_ok && save_ok && kill_ok && list_ok &&
		surface_ok && node_ok && root_ok && published && copied
	testing.expect(t, ready)
	if !ready do return
	defer ui.snapshot_close(&snapshot)
	frame, rendered, failure := renderer_prepare_ui(
		renderer_state(&renderer),
		UI_Presentation{root = &snapshot},
	)
	testing.expectf(t, rendered, "list frame failed with %v", failure.code)
	if !rendered do return
	defer frame_close(&frame)
	expected := "\x1b[?25l\x1b[2J" +
		"\x1b[1;2H\x1b[1mS \x1b[22m\x1b[4malpha\x1b[24m" +
		"\x1b[2;2H\x1b[7m\x1b[2mD \x1b[22m界\x1b[2mx\x1b[22myz\x1b[27m" +
		"\x1b[3;2H       "
	testing.expect_value(t, string(frame.output[:frame.used]), expected)
}

/* Verifies the Gutter is styled beside text and offsets the editing cursor. */
@(test)
projects_gutter_outside_text :: proc(t: ^testing.T) {
	fixture: Renderer_Fixture
	if !renderer_fixture_init(t, &fixture, 80, "alpha\nbeta") do return
	defer renderer_fixture_close(&fixture)
	logical, _, _ := editor_view.snapshot(&fixture.registry, fixture.handle)
	text_constraints := display.Viewport_Constraints{width_cells = 8, height_rows = 3}
	snapshot, projected, _ := display.project(
		&fixture.buffer,
		renderer_projection_request(80, logical, text_constraints),
	)
	if !projected {
		testing.expect(t, false)
		return
	}
	defer display.snapshot_close(&snapshot)
	renderer: Renderer
	renderer_ready, _ := renderer_init(
		&renderer,
		renderer_config(display.Viewport_Constraints{width_cells = 12, height_rows = 3}),
	)
	if !renderer_ready {
		testing.expect(t, false)
		return
	}
	defer renderer_close(&renderer)
	gutter_rows := [3]ui.Text_Gutter_Row_Definition {
		{viewport_row = 0, logical_line = 0, left_text = " 1 │", left_cells = 4,
			left_separator_bytes = 3, left_style_role = .Gutter_Line_Number_Current,
			current = true},
		{viewport_row = 1, logical_line = 1, left_text = " 2 │", left_cells = 4,
			left_separator_bytes = 3, left_style_role = .Gutter_Line_Number},
		{viewport_row = 2, logical_line = 0, left_text = "   │", left_cells = 4,
			left_separator_bytes = 3, left_style_role = .Gutter_Line_Number},
	}
	gutter_cells, gutter_cells_ok := ui_input_cursor_cells(
		renderer_state(&renderer).profile, gutter_rows[0].left_text)
	testing.expect(t, gutter_cells_ok)
	testing.expect_value(t, gutter_cells, u32(4))
	geometry := ui.Cell_Rect{height = 3, width = 12}
	ui_root: Text_UI_Test_Root
	if !text_ui_test_root_init(
		t,
		&ui_root,
		&fixture,
		&renderer,
		snapshot,
		logical,
		text_constraints,
		geometry_override = &geometry,
		gutter_rows = gutter_rows[:],
		gutter_left_cells = 4,
	) {
		return
	}
	defer text_ui_test_root_close(&ui_root)
	frame, prepared, failure := renderer_prepare_ui(
		renderer_state(&renderer), text_ui_test_root_presentation(&ui_root))
	testing.expectf(t, prepared, "gutter frame failed with %v", failure.code)
	if !prepared do return
	defer frame_close(&frame)
	output := string(frame.output[:frame.used])
	testing.expect(t, strings.contains(output, " 1"))
	testing.expect(t, strings.contains(output, "│"))
	testing.expect(t, strings.contains(output, "\x1b[1;5Halpha"))
	testing.expect(t, strings.contains(output, "\x1b[2;5Hbeta"))
	testing.expect(t, strings.contains(output, "\x1b[1;5H\x1b[?25h"))
}

/* Verifies one text UI root encodes deterministic full-frame rows and cursor. */
@(test)
renderer_encodes_deterministic_ansi_rows :: proc(t: ^testing.T) {
	fixture: Renderer_Fixture
	ready := renderer_fixture_init(t, &fixture, 81, "alpha\nbeta")
	if !ready {
		return
	}
	defer renderer_fixture_close(&fixture)
	logical, _, _ := editor_view.snapshot(&fixture.registry, fixture.handle)
	constraints := display.Viewport_Constraints{width_cells = 8, height_rows = 3}
	snapshot, projected, projection_failure := display.project(
		&fixture.buffer,
		renderer_projection_request(21, logical, constraints),
	)
	testing.expectf(t, projected, "projection failed with %v", projection_failure.code)
	if !projected {
		return
	}
	defer display.snapshot_close(&snapshot)
	renderer: Renderer
	renderer_ready, renderer_failure := renderer_init(
		&renderer,
		renderer_config(constraints),
	)
	testing.expectf(t, renderer_ready, "renderer failed with %v", renderer_failure.code)
	if !renderer_ready {
		return
	}
	defer renderer_close(&renderer)
	ui_root: Text_UI_Test_Root
	ui_ready := text_ui_test_root_init(
		t, &ui_root, &fixture, &renderer, snapshot, logical, constraints,
	)
	if !ui_ready {
		return
	}
	defer text_ui_test_root_close(&ui_root)
	presentation := text_ui_test_root_presentation(&ui_root)
	frame, prepared, prepare_failure := renderer_prepare_ui(
		renderer_state(&renderer), presentation,
	)
	testing.expectf(t, prepared, "frame failed with %v", prepare_failure.code)
	if !prepared {
		return
	}
	expected := "\x1b[?25l\x1b[2J\x1b[1;1Halpha" +
	            "\x1b[2;1Hbeta\x1b[3;1H" +
	            "\x1b[1;1H\x1b[?25h"
	testing.expect_value(t, string(frame.output[:frame.used]), expected)
	frame_close(&frame)

	repeated, repeated_ok, repeated_failure := renderer_prepare_ui(
		renderer_state(&renderer), presentation,
	)
	testing.expectf(t, repeated_ok, "repeated frame failed with %v", repeated_failure.code)
	if repeated_ok {
		defer frame_close(&repeated)
		testing.expect_value(t, string(repeated.output[:repeated.used]), expected)
	}
}

/* Verifies the ordinary text background colors the complete cleared terminal canvas. */
@(test)
applies_theme_before_canvas_clear :: proc(t: ^testing.T) {
	fixture: Renderer_Fixture
	ready := renderer_fixture_init(t, &fixture, 811, "alpha")
	if !ready do return
	defer renderer_fixture_close(&fixture)
	logical, _, _ := editor_view.snapshot(&fixture.registry, fixture.handle)
	constraints := display.Viewport_Constraints{width_cells = 8, height_rows = 3}
	snapshot, projected, projection_failure := display.project(
		&fixture.buffer,
		renderer_projection_request(211, logical, constraints),
	)
	testing.expectf(t, projected, "projection failed with %v", projection_failure.code)
	if !projected do return
	defer display.snapshot_close(&snapshot)
	renderer: Renderer
	config := renderer_config(constraints)
	config.color = .True_Color
	renderer_ready, renderer_failure := renderer_init(&renderer, config)
	testing.expectf(t, renderer_ready, "renderer failed with %v", renderer_failure.code)
	if !renderer_ready do return
	defer renderer_close(&renderer)
	ui_root: Text_UI_Test_Root
	background := ui.Optional_SRGB_Color {
		present = true,
		color = {red = 243, green = 235, blue = 221},
	}
	ui_ready := text_ui_test_root_init(
		t,
		&ui_root,
		&fixture,
		&renderer,
		snapshot,
		logical,
		constraints,
		text_background = background,
		cursor_shape = .Bar,
	)
	if !ui_ready do return
	defer text_ui_test_root_close(&ui_root)
	frame, prepared, prepare_failure := renderer_prepare_ui(
		renderer_state(&renderer),
		text_ui_test_root_presentation(&ui_root),
	)
	testing.expectf(t, prepared, "frame failed with %v", prepare_failure.code)
	if !prepared do return
	defer frame_close(&frame)
	expected := "\x1b[?25l\x1b[48;2;243;235;221m\x1b[2J" +
	            "\x1b[1;1Halpha\x1b[49m\x1b[2;1H\x1b[3;1H" +
	            "\x1b[6 q\x1b[1;1H\x1b[?25h"
	testing.expect_value(t, string(frame.output[:frame.used]), expected)
}

/* Verifies one active non-empty region is rendered without changing row text. */
@(test)
renderer_highlights_only_the_active_region :: proc(t: ^testing.T) {
	fixture: Renderer_Fixture
	ready := renderer_fixture_init(t, &fixture, 82, "alpha")
	if !ready {
		return
	}
	defer renderer_fixture_close(&fixture)
	mark, _, _ := editor.buffer_position(&fixture.buffer, editor.Byte_Offset(1))
	point, _, _ := editor.buffer_position(&fixture.buffer, editor.Byte_Offset(4))
	mark_ok, _ := editor_view.set_mark(&fixture.registry, fixture.handle, mark)
	point_ok, _ := editor_view.set_point(&fixture.registry, fixture.handle, point)
	testing.expect(t, mark_ok && point_ok)
	logical, _, _ := editor_view.snapshot(&fixture.registry, fixture.handle)
	constraints := display.Viewport_Constraints{width_cells = 8, height_rows = 1}
	snapshot, projected, _ := display.project(
		&fixture.buffer,
		renderer_projection_request(25, logical, constraints),
	)
	testing.expect(t, projected)
	if !projected {
		return
	}
	defer display.snapshot_close(&snapshot)
	renderer: Renderer
	initialized, _ := renderer_init(&renderer, renderer_config(constraints))
	testing.expect(t, initialized)
	if !initialized {
		return
	}
	defer renderer_close(&renderer)
	span := renderer_test_syntax_span(logical, 5, .Keyword)
	spans := [1]language.Syntax_Span{span}
	syntax_snapshot := renderer_test_syntax_snapshot(logical, span.provider, len(spans))
	ui_root: Text_UI_Test_Root
	if !text_ui_test_root_init(
		t,
		&ui_root,
		&fixture,
		&renderer,
		snapshot,
		logical,
		constraints,
		nil,
		nil,
		{.Reverse},
		{.Reverse},
		&syntax_snapshot,
		spans[:],
	) {
		return
	}
	defer text_ui_test_root_close(&ui_root)
	frame, prepared, _ := renderer_prepare_ui(
		renderer_state(&renderer), text_ui_test_root_presentation(&ui_root),
	)
	testing.expect(t, prepared)
	if prepared {
		defer frame_close(&frame)
		expected := "\x1b[?25l\x1b[2J\x1b[1;1Ha" +
		            "\x1b[7mlph\x1b[27ma\x1b[1;5H\x1b[?25h"
		testing.expect_value(t, string(frame.output[:frame.used]), expected)
	}
}

/* Verifies a rectangular region highlights only each row's derived range. */
@(test)
renderer_highlights_rectangular_ranges_per_row :: proc(t: ^testing.T) {
	fixture: Renderer_Fixture
	if !renderer_fixture_init(t, &fixture, 83, "abcd\nxy") do return
	defer renderer_fixture_close(&fixture)
	mark, mark_ok, _ := editor.buffer_position(&fixture.buffer, editor.Byte_Offset(1))
	point, point_ok, _ := editor.buffer_position(&fixture.buffer, editor.Byte_Offset(6))
	selected, select_failure := editor_view.select_range(
		&fixture.registry,
		fixture.handle,
		mark,
		point,
		1,
		.Rectangle,
		.Grapheme,
	)
	testing.expectf(t, mark_ok && point_ok && selected, "rectangle selection failed with %v", select_failure.code)
	if !selected do return
	logical, _, _ := editor_view.snapshot(&fixture.registry, fixture.handle)
	constraints := display.Viewport_Constraints{width_cells = 8, height_rows = 2}
	snapshot, projected, _ := display.project(
		&fixture.buffer,
		renderer_projection_request(26, logical, constraints),
	)
	testing.expect(t, projected)
	if !projected do return
	defer display.snapshot_close(&snapshot)
	renderer: Renderer
	initialized, _ := renderer_init(&renderer, renderer_config(constraints))
	testing.expect(t, initialized)
	if !initialized do return
	defer renderer_close(&renderer)
	ui_root: Text_UI_Test_Root
	if !text_ui_test_root_init(
		t, &ui_root, &fixture, &renderer, snapshot, logical, constraints,
		nil, nil, {.Reverse}, {.Reverse},
	) {
		return
	}
	defer text_ui_test_root_close(&ui_root)
	frame, prepared, _ := renderer_prepare_ui(
		renderer_state(&renderer), text_ui_test_root_presentation(&ui_root),
	)
	testing.expect(t, prepared)
	if prepared {
		defer frame_close(&frame)
		output := string(frame.output[:frame.used])
		testing.expect(t, strings.contains(output, "\x1b[1;1Ha\x1b[7mb\x1b[27mcd"))
		testing.expect(t, strings.contains(output, "\x1b[2;1Hx\x1b[7my\x1b[27m"))
	}
}

/* Verifies the projected current search occurrence is visible in terminal output. */
@(test)
renderer_highlights_the_current_search_match :: proc(t: ^testing.T) {
	fixture: Renderer_Fixture
	if !renderer_fixture_init(t, &fixture, 84, "alpha beta") {
		return
	}
	defer renderer_fixture_close(&fixture)
	logical, _, _ := editor_view.snapshot(&fixture.registry, fixture.handle)
	constraints := display.Viewport_Constraints{width_cells = 12, height_rows = 1}
	occurrences := [1]search.Occurrence {{
		buffer_id = logical.buffer_id,
		revision = logical.revision,
		start = 6,
		end = 10,
	}}
	request := renderer_projection_request(26, logical, constraints)
	request.search = editor_view.Search_Snapshot {
		present = true,
		interaction_generation = 1,
		source_revision = logical.revision,
		status = .Active,
		scope = search.Scope {
			buffer_id = logical.buffer_id,
			revision = logical.revision,
			start = 0,
			end = 10,
		},
		has_current = true,
		occurrences = occurrences[:],
	}
	snapshot, projected, _ := display.project(&fixture.buffer, request)
	testing.expect(t, projected)
	if !projected {
		return
	}
	defer display.snapshot_close(&snapshot)
	renderer: Renderer
	initialized, _ := renderer_init(&renderer, renderer_config(constraints))
	testing.expect(t, initialized)
	if !initialized {
		return
	}
	defer renderer_close(&renderer)
	ui_root: Text_UI_Test_Root
	if !text_ui_test_root_init(
		t, &ui_root, &fixture, &renderer, snapshot, logical, constraints, &request.search,
	) {
		return
	}
	defer text_ui_test_root_close(&ui_root)
	frame, prepared, _ := renderer_prepare_ui(
		renderer_state(&renderer), text_ui_test_root_presentation(&ui_root),
	)
	testing.expect(t, prepared)
	if prepared {
		defer frame_close(&frame)
		expected := "\x1b[?25l\x1b[2J\x1b[1;1Halpha " +
		            "\x1b[7mbeta\x1b[27m\x1b[1;1H\x1b[?25h"
		testing.expect_value(t, string(frame.output[:frame.used]), expected)
	}
}

/* Verifies current search overrides only the overlapping cells of an active region. */
@(test)
region_wraps_search_precedence :: proc(t: ^testing.T) {
	fixture: Renderer_Fixture
	if !renderer_fixture_init(t, &fixture, 85, "alpha beta") do return
	defer renderer_fixture_close(&fixture)
	mark, _, _ := editor.buffer_position(&fixture.buffer, editor.Byte_Offset(1))
	point, _, _ := editor.buffer_position(&fixture.buffer, editor.Byte_Offset(9))
	mark_ok, _ := editor_view.set_mark(&fixture.registry, fixture.handle, mark)
	point_ok, _ := editor_view.set_point(&fixture.registry, fixture.handle, point)
	testing.expect(t, mark_ok && point_ok)
	logical, _, _ := editor_view.snapshot(&fixture.registry, fixture.handle)
	constraints := display.Viewport_Constraints{width_cells = 12, height_rows = 1}
	occurrences := [1]search.Occurrence {{
		buffer_id = logical.buffer_id,
		revision = logical.revision,
		start = 6,
		end = 10,
	}}
	search_snapshot := editor_view.Search_Snapshot {
		present = true,
		interaction_generation = 1,
		source_revision = logical.revision,
		status = .Active,
		scope = {
			buffer_id = logical.buffer_id,
			revision = logical.revision,
			start = 0,
			end = 10,
		},
		has_current = true,
		occurrences = occurrences[:],
	}
	request := renderer_projection_request(27, logical, constraints)
	request.search = search_snapshot
	snapshot, projected, _ := display.project(&fixture.buffer, request)
	testing.expect(t, projected)
	if !projected do return
	defer display.snapshot_close(&snapshot)
	renderer: Renderer
	initialized, _ := renderer_init(&renderer, renderer_config(constraints))
	testing.expect(t, initialized)
	if !initialized do return
	defer renderer_close(&renderer)
	ui_root: Text_UI_Test_Root
	if !text_ui_test_root_init(
		t,
		&ui_root,
		&fixture,
		&renderer,
		snapshot,
		logical,
		constraints,
		&search_snapshot,
		nil,
		{.Underline},
		{.Reverse},
	) {
		return
	}
	defer text_ui_test_root_close(&ui_root)
	frame, prepared, _ := renderer_prepare_ui(
		renderer_state(&renderer), text_ui_test_root_presentation(&ui_root),
	)
	testing.expect(t, prepared)
	if prepared {
		defer frame_close(&frame)
		expected := "\x1b[?25l\x1b[2J\x1b[1;1Ha" +
		            "\x1b[4mlpha \x1b[24m" +
		            "\x1b[7mbeta\x1b[27m\x1b[1;10H\x1b[?25h"
		testing.expect_value(t, string(frame.output[:frame.used]), expected)
	}
}

/* Verifies search and region override syntax without losing ordinary text. */
@(test)
composes_syntax_region_search :: proc(t: ^testing.T) {
	fixture: Renderer_Fixture
	if !renderer_fixture_init(t, &fixture, 89, "alpha beta") do return
	defer renderer_fixture_close(&fixture)
	mark, _, _ := editor.buffer_position(&fixture.buffer, editor.Byte_Offset(1))
	point, _, _ := editor.buffer_position(&fixture.buffer, editor.Byte_Offset(9))
	mark_ok, _ := editor_view.set_mark(&fixture.registry, fixture.handle, mark)
	point_ok, _ := editor_view.set_point(&fixture.registry, fixture.handle, point)
	testing.expect(t, mark_ok && point_ok)
	logical, _, _ := editor_view.snapshot(&fixture.registry, fixture.handle)
	constraints := display.Viewport_Constraints{width_cells = 12, height_rows = 1}
	occurrences := [1]search.Occurrence {{
		buffer_id = logical.buffer_id,
		revision = logical.revision,
		start = 6,
		end = 10,
	}}
	search_snapshot := editor_view.Search_Snapshot {
		present = true,
		interaction_generation = 1,
		source_revision = logical.revision,
		status = .Active,
		scope = {
			buffer_id = logical.buffer_id,
			revision = logical.revision,
			start = 0,
			end = 10,
		},
		has_current = true,
		occurrences = occurrences[:],
	}
	request := renderer_projection_request(29, logical, constraints)
	request.search = search_snapshot
	display_snapshot, projected, _ := display.project(&fixture.buffer, request)
	testing.expect(t, projected)
	if !projected do return
	defer display.snapshot_close(&display_snapshot)
	renderer: Renderer
	config := renderer_config(constraints)
	config.color = .True_Color
	initialized, _ := renderer_init(&renderer, config)
	testing.expect(t, initialized)
	if !initialized do return
	defer renderer_close(&renderer)
	provider := language.Provider_Handle {
		registry_id = 1,
		language_id = 1,
		provider_id = 1,
		provider_generation = 1,
	}
	spans := [2]language.Syntax_Span {
		{start = 0, end = 5, role = .Keyword, precedence = 20, provider = provider},
		{start = 6, end = 10, role = .Function, precedence = 10, provider = provider},
	}
	for &span in spans do span.source_revision = logical.revision
	syntax_snapshot := language.Syntax_Snapshot {
		generation = 1,
		buffer_id = logical.buffer_id,
		source_revision = logical.revision,
		language = {id = 1, generation = 1},
		provider = provider,
		selection_generation = 1,
		parser_generation = 1,
		query_generation = 1,
		span_count = u32(len(spans)),
		usage = {
			spans = u32(len(spans)),
			retained_span_bytes = u64(len(spans)) * u64(size_of(language.Syntax_Span)),
		},
	}
	ui_root: Text_UI_Test_Root
	if !text_ui_test_root_init(
		t,
		&ui_root,
		&fixture,
		&renderer,
		display_snapshot,
		logical,
		constraints,
		&search_snapshot,
		nil,
		{.Underline},
		{.Reverse},
		&syntax_snapshot,
		spans[:],
	) {
		return
	}
	defer text_ui_test_root_close(&ui_root)
	frame, prepared, failure := renderer_prepare_ui(
		renderer_state(&renderer),
		text_ui_test_root_presentation(&ui_root),
	)
	testing.expectf(t, prepared, "syntax frame failed with %v", failure.code)
	if prepared {
		defer frame_close(&frame)
		expected := "\x1b[?25l\x1b[2J\x1b[1;1H" +
		            "\x1b[38;2;197;134;192ma" +
		            "\x1b[4m\x1b[39mlpha " +
		            "\x1b[24m\x1b[7mbeta\x1b[27m" +
		            "\x1b[1;10H\x1b[?25h"
		testing.expect_value(t, string(frame.output[:frame.used]), expected)
	}
}

/* Verifies incompatible geometry is rejected and resize invalidates physical state. */
@(test)
terminal_renderer_requires_compatible_snapshots :: proc(t: ^testing.T) {
	fixture: Renderer_Fixture
	ready := renderer_fixture_init(t, &fixture, 83, "resize")
	if !ready {
		return
	}
	defer renderer_fixture_close(&fixture)
	logical, _, _ := editor_view.snapshot(&fixture.registry, fixture.handle)
	constraints := display.Viewport_Constraints{width_cells = 8, height_rows = 1}
	snapshot, projected, _ := display.project(
		&fixture.buffer,
		renderer_projection_request(22, logical, constraints),
	)
	testing.expect(t, projected)
	if !projected {
		return
	}
	defer display.snapshot_close(&snapshot)
	renderer: Renderer
	initialized, _ := renderer_init(&renderer, renderer_config(constraints))
	testing.expect(t, initialized)
	if !initialized {
		return
	}
	defer renderer_close(&renderer)
	span := renderer_test_syntax_span(logical, 6, .Keyword)
	spans := [1]language.Syntax_Span{span}
	syntax_snapshot := renderer_test_syntax_snapshot(logical, span.provider, len(spans))
	ui_root: Text_UI_Test_Root
	if !text_ui_test_root_init(
		t,
		&ui_root,
		&fixture,
		&renderer,
		snapshot,
		logical,
		constraints,
		nil,
		nil,
		{.Reverse},
		{.Reverse},
		&syntax_snapshot,
		spans[:],
	) {
		return
	}
	defer text_ui_test_root_close(&ui_root)
	resized, _ := renderer_resize(
		&renderer,
		display.Viewport_Constraints{width_cells = 12, height_rows = 1},
	)
	testing.expect(t, resized)
	_, prepared, failure := renderer_prepare_ui(
		renderer_state(&renderer), text_ui_test_root_presentation(&ui_root),
	)
	testing.expect(t, !prepared)
	testing.expect_value(t, failure.code, Failure_Code.Invalid_UI_Presentation)
}

/* Verifies syntax-aware output rejects its bound before allocating a frame. */
@(test)
rejects_output_limit_before_alloc :: proc(t: ^testing.T) {
	fixture: Renderer_Fixture
	if !renderer_fixture_init(t, &fixture, 90, "bounded") do return
	defer renderer_fixture_close(&fixture)
	logical, _, _ := editor_view.snapshot(&fixture.registry, fixture.handle)
	constraints := display.Viewport_Constraints{width_cells = 8, height_rows = 1}
	display_snapshot, projected, _ := display.project(
		&fixture.buffer,
		renderer_projection_request(30, logical, constraints),
	)
	testing.expect(t, projected)
	if !projected do return
	defer display.snapshot_close(&display_snapshot)
	renderer: Renderer
	config := renderer_config(constraints)
	config.color = .True_Color
	config.max_output_bytes = 64
	initialized, _ := renderer_init(&renderer, config)
	testing.expect(t, initialized)
	if !initialized do return
	defer renderer_close(&renderer)
	span := renderer_test_syntax_span(logical, 7, .Keyword)
	spans := [1]language.Syntax_Span{span}
	syntax_snapshot := renderer_test_syntax_snapshot(logical, span.provider, len(spans))
	root: Text_UI_Test_Root
	if !text_ui_test_root_init(
		t,
		&root,
		&fixture,
		&renderer,
		display_snapshot,
		logical,
		constraints,
		nil,
		nil,
		{.Reverse},
		{.Reverse},
		&syntax_snapshot,
		spans[:],
	) {
		return
	}
	defer text_ui_test_root_close(&root)
	_, prepared, failure := renderer_prepare_ui(
		renderer_state(&renderer),
		text_ui_test_root_presentation(&root),
	)
	testing.expect(t, !prepared)
	testing.expect_value(t, failure.code, Failure_Code.Render_Output_Limit)
	testing.expect_value(t, failure.limit, u64(64))
}

/* Verifies a text UI write failure reports the exact output fault. */
@(test)
terminal_ui_renderer_reports_write_failure :: proc(t: ^testing.T) {
	fixture: Renderer_Fixture
	ready := renderer_fixture_init(t, &fixture, 85, "failure")
	if !ready {
		return
	}
	defer renderer_fixture_close(&fixture)
	logical, _, _ := editor_view.snapshot(&fixture.registry, fixture.handle)
	constraints := display.Viewport_Constraints{width_cells = 8, height_rows = 1}
	snapshot, projected, _ := display.project(
		&fixture.buffer,
		renderer_projection_request(23, logical, constraints),
	)
	testing.expect(t, projected)
	if !projected {
		return
	}
	defer display.snapshot_close(&snapshot)
	renderer: Renderer
	initialized, _ := renderer_init(&renderer, renderer_config(constraints))
	testing.expect(t, initialized)
	if !initialized {
		return
	}
	defer renderer_close(&renderer)
	ui_root: Text_UI_Test_Root
	if !text_ui_test_root_init(
		t, &ui_root, &fixture, &renderer, snapshot, logical, constraints,
	) {
		return
	}
	defer text_ui_test_root_close(&ui_root)
	session := Session {
		output_fd = posix.FD(-1),
		acquired = true,
	}
	_, presented_failure := renderer_present_ui(
		&renderer,
		&session,
		text_ui_test_root_presentation(&ui_root),
	)
	testing.expect_value(t, presented_failure.code, Failure_Code.Write_Failed)
}

/* Verifies every renderer allocation failure releases all admitted storage. */
@(test)
terminal_renderer_allocation_failures_are_atomic :: proc(t: ^testing.T) {
	fixture: Renderer_Fixture
	ready := renderer_fixture_init(t, &fixture, 87, "allocation")
	if !ready {
		return
	}
	defer renderer_fixture_close(&fixture)
	logical, _, _ := editor_view.snapshot(&fixture.registry, fixture.handle)
	constraints := display.Viewport_Constraints{width_cells = 12, height_rows = 2}
	snapshot, projected, _ := display.project(
		&fixture.buffer,
		renderer_projection_request(24, logical, constraints),
	)
	testing.expect(t, projected)
	if !projected {
		return
	}
	defer display.snapshot_close(&snapshot)
	reference_renderer: Renderer
	reference_ready, _ := renderer_init(&reference_renderer, renderer_config(constraints))
	if !reference_ready {
		return
	}
	defer renderer_close(&reference_renderer)
	span := renderer_test_syntax_span(logical, 10, .Keyword)
	spans := [1]language.Syntax_Span{span}
	syntax_snapshot := renderer_test_syntax_snapshot(logical, span.provider, len(spans))
	ui_root: Text_UI_Test_Root
	if !text_ui_test_root_init(
		t,
		&ui_root,
		&fixture,
		&reference_renderer,
		snapshot,
		logical,
		constraints,
		nil,
		nil,
		{.Reverse},
		{.Reverse},
		&syntax_snapshot,
		spans[:],
	) {
		return
	}
	defer text_ui_test_root_close(&ui_root)
	for fail_after in 0 ..< 5 {
		tracking: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracking, context.allocator)
		failing := Renderer_Failing_Allocator {
			backing = mem.tracking_allocator(&tracking),
			fail_after = u64(fail_after),
		}
		config := renderer_config(constraints)
		config.allocator = renderer_failing_allocator(&failing)
		renderer: Renderer
		initialized, init_failure := renderer_init(&renderer, config)
		if fail_after == 0 {
			testing.expect(t, !initialized)
			testing.expect_value(t, init_failure.code, Failure_Code.Renderer_Memory_Limit)
		} else {
			testing.expect(t, initialized)
			if initialized {
				frame, prepared, prepare_failure := renderer_prepare_ui(
					renderer_state(&renderer),
					text_ui_test_root_presentation(&ui_root),
				)
				if fail_after < 2 {
					testing.expect(t, !prepared)
					testing.expect_value(t, prepare_failure.code, Failure_Code.Renderer_Memory_Limit)
				} else {
					testing.expect(t, prepared)
				}
				frame_close(&frame)
				renderer_close(&renderer)
			}
		}
		testing.expect_value(t, tracking.current_memory_allocated, i64(0))
		mem.tracking_allocator_destroy(&tracking)
	}
}

@(private)
Renderer_Failing_Allocator :: struct {
	backing:                runtime.Allocator,
	fail_after:             u64,
	successful_allocations: u64,
}

@(private)
renderer_failing_allocator :: proc(data: ^Renderer_Failing_Allocator) -> runtime.Allocator {
	return runtime.Allocator {
		procedure = renderer_failing_allocator_proc,
		data = data,
	}
}

@(private)
renderer_failing_allocator_proc :: proc(
	allocator_data: rawptr,
	mode: runtime.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	location := #caller_location,
) -> (result: []byte, error: runtime.Allocator_Error) {
	allocator := (^Renderer_Failing_Allocator)(allocator_data)
	if mode == .Alloc || mode == .Alloc_Non_Zeroed || mode == .Resize ||
	   mode == .Resize_Non_Zeroed {
		if allocator.successful_allocations >= allocator.fail_after {
			return nil, .Out_Of_Memory
		}
		allocator.successful_allocations += 1
	}
	return allocator.backing.procedure(
		allocator.backing.data,
		mode,
		size,
		alignment,
		old_memory,
		old_size,
		location,
	)
}

@(private)
Renderer_Fixture :: struct {
	buffer:   editor.Buffer,
	registry: editor_view.Registry,
	handle:   editor_view.View_Handle,
}

@(private)
Text_UI_Test_Root :: struct {
	registry:    ui.Registry,
	snapshot:    ui.Snapshot,
	projections: [1]Text_Surface_Projection,
}

@(private)
text_ui_test_root_init :: proc(
	t: ^testing.T,
	root: ^Text_UI_Test_Root,
	fixture: ^Renderer_Fixture,
	renderer: ^Renderer,
	display_snapshot: display.Snapshot,
	logical: editor_view.Snapshot,
	constraints: display.Viewport_Constraints,
	search_override: ^editor_view.Search_Snapshot = nil,
	geometry_override: ^ui.Cell_Rect = nil,
	region_attributes: ui.Style_Attributes = {.Reverse},
	search_attributes: ui.Style_Attributes = {.Reverse},
	syntax_snapshot: ^language.Syntax_Snapshot = nil,
	syntax_spans: []language.Syntax_Span = nil,
	text_background: ui.Optional_SRGB_Color = {},
	gutter_rows: []ui.Text_Gutter_Row_Definition = nil,
	gutter_left_cells: u16 = 0,
	gutter_right_cells: u16 = 0,
	cursor_shape: ui.Text_Cursor_Shape = .Default,
) -> bool {
	profile, profile_ok := renderer_ui_profile(renderer)
	initialized, _ := ui.registry_init(&root.registry, ui.Registry_ID(logical.buffer_id))
	if !profile_ok || !initialized {
		return false
	}
	proposal, prepared, _ := ui.proposal_begin(&root.registry)
	_, text_style, _ := ui.proposal_add_style(&proposal, .Text_Normal, background = text_background)
	_, region_style, _ := ui.proposal_add_style(&proposal, .Text_Region, region_attributes)
	_, search_style, _ := ui.proposal_add_style(&proposal, .Text_Search_Current, search_attributes)
	view, viewed, _ := ui.proposal_project_editor_text_view(
		&proposal,
		&fixture.registry,
		fixture.handle,
		&fixture.buffer,
		ui.Owner_ID(logical.buffer_id),
		false,
		search_override,
		cursor_shape,
	)
	gutter_styles := true
	gutter_projected := true
	if len(gutter_rows) > 0 {
		_, gutter_background_ok, _ := ui.proposal_add_style(&proposal, .Gutter_Background)
		_, gutter_number_ok, _ := ui.proposal_add_style(&proposal, .Gutter_Line_Number, {.Dim})
		_, gutter_current_ok, _ := ui.proposal_add_style(
			&proposal, .Gutter_Line_Number_Current, {.Bold})
		_, gutter_separator_ok, _ := ui.proposal_add_style(&proposal, .Gutter_Separator, {.Dim})
		gutter_styles = gutter_background_ok && gutter_number_ok && gutter_current_ok &&
			gutter_separator_ok
		gutter_projected, _ = ui.proposal_project_text_gutter(
			&proposal,
			view,
			1,
			gutter_left_cells,
			gutter_right_cells,
			constraints.width_cells,
			gutter_rows,
		)
	}
	syntax_styles := true
	syntax_projected := true
	if syntax_snapshot != nil {
		syntax_styles, _ = ui.proposal_add_factory_syntax_styles(&proposal)
		_, syntax_projected, _ = ui.proposal_project_syntax_decorations(
			&proposal,
			view,
			syntax_snapshot^,
			syntax_spans,
			ui.Owner_ID(logical.buffer_id),
		)
	}
	geometry := ui.Cell_Rect {
		height = i32(constraints.height_rows),
		width = i32(constraints.width_cells),
	}
	if geometry_override != nil do geometry = geometry_override^
	surface, surfaced, _ := ui.proposal_add_surface(
		&proposal,
		ui.Surface_Descriptor {
			owner_id = ui.Owner_ID(logical.buffer_id),
			view = view,
			focusable = true,
			visible = true,
			required_profile = profile.id,
			geometry = geometry,
		},
	)
	node, node_ok, _ := ui.proposal_add_surface_node(&proposal, surface)
	root_ok, _ := ui.proposal_set_root(&proposal, node, surface)
	root_handle, published, _ := ui.proposal_publish(&root.registry, &proposal, profile)
	if proposal.state != nil do ui.proposal_abort(&proposal)
	copied := false
	if published do root.snapshot, copied, _ = ui.registry_snapshot(
		&root.registry, root_handle, profile,
	)
	ready := prepared && text_style && region_style && search_style && viewed && gutter_styles &&
		gutter_projected && syntax_styles && syntax_projected && surfaced &&
		node_ok && root_ok && published && copied
	testing.expect(t, ready)
	if !ready {
		text_ui_test_root_close(root)
		return false
	}
	root.projections[0] = Text_Surface_Projection {
		surface = surface,
		snapshot = display_snapshot,
		logical = logical,
	}
	return true
}

@(private)
text_ui_test_root_presentation :: proc(root: ^Text_UI_Test_Root) -> UI_Presentation {
	return UI_Presentation{root = &root.snapshot, text_surfaces = root.projections[:]}
}

@(private)
text_ui_test_root_close :: proc(root: ^Text_UI_Test_Root) {
	if root.snapshot.state != nil do ui.snapshot_close(&root.snapshot)
	if root.registry.state != nil && !root.registry.closed do ui.registry_close(&root.registry)
}

@(private)
renderer_fixture_init :: proc(
	t: ^testing.T,
	fixture: ^Renderer_Fixture,
	id: u64,
	text: string,
) -> bool {
	buffer_ok, buffer_failure := editor.buffer_init(
		&fixture.buffer,
		editor.Buffer_ID(id),
		text,
		editor.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	testing.expectf(t, buffer_ok, "buffer failed with %v", buffer_failure.code)
	if !buffer_ok {
		return false
	}
	registry_ok, registry_failure := editor_view.registry_init(
		&fixture.registry,
		editor_view.Registry_ID(u32(id)),
		context.allocator,
	)
	testing.expectf(t, registry_ok, "registry failed with %v", registry_failure.code)
	if !registry_ok {
		editor.buffer_close(&fixture.buffer)
		return false
	}
	handle, view_ok, view_failure := editor_view.create(&fixture.registry, &fixture.buffer)
	testing.expectf(t, view_ok, "view failed with %v", view_failure.code)
	if !view_ok {
		editor_view.registry_close(&fixture.registry)
		editor.buffer_close(&fixture.buffer)
		return false
	}
	fixture.handle = handle
	return true
}

@(private)
renderer_fixture_close :: proc(fixture: ^Renderer_Fixture) {
	if fixture.handle.view_id != editor_view.View_ID(0) {
		editor_view.close(&fixture.registry, &fixture.handle)
	}
	if !fixture.registry.closed {
		editor_view.registry_close(&fixture.registry)
	}
	if editor.buffer_is_live(&fixture.buffer) {
		editor.buffer_close(&fixture.buffer)
	}
}

@(private)
renderer_config :: proc(constraints: display.Viewport_Constraints) -> Renderer_Config {
	return Renderer_Config {
		constraints = constraints,
		profile = display.terminal_unicode17_profile(),
		max_output_bytes = MAX_OUTPUT_BYTES,
		allocator = context.allocator,
	}
}

@(private)
renderer_test_syntax_span :: proc(
	logical: editor_view.Snapshot,
	end: editor.Byte_Offset,
	role: language.Syntax_Role,
) -> language.Syntax_Span {
	return language.Syntax_Span {
		start = 0,
		end = end,
		role = role,
		precedence = 10,
		provider = {
			registry_id = 1,
			language_id = 1,
			provider_id = 1,
			provider_generation = 1,
		},
		source_revision = logical.revision,
	}
}

@(private)
renderer_test_syntax_snapshot :: proc(
	logical: editor_view.Snapshot,
	provider: language.Provider_Handle,
	span_count: int,
) -> language.Syntax_Snapshot {
	return language.Syntax_Snapshot {
		generation = 1,
		buffer_id = logical.buffer_id,
		source_revision = logical.revision,
		language = {id = 1, generation = 1},
		provider = provider,
		selection_generation = 1,
		parser_generation = 1,
		query_generation = 1,
		span_count = u32(span_count),
		usage = {
			spans = u32(span_count),
			retained_span_bytes = u64(span_count) * u64(size_of(language.Syntax_Span)),
		},
	}
}

@(private)
renderer_projection_request :: proc(
	id: u64,
	logical: editor_view.Snapshot,
	constraints: display.Viewport_Constraints,
) -> display.Projection_Request {
	return display.Projection_Request {
		snapshot_id = display.Snapshot_ID(id),
		view = logical,
		constraints = constraints,
		profile = display.terminal_unicode17_profile(),
		limits = display.DEFAULT_RESOURCE_LIMITS,
		allocators = display.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	}
}
