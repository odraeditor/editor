// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package terminal_frontend

import "../display"
import "../editor"
import "../layout"
import "../language"
import "../language_service"
import "../ui"
import editor_view "../view"
import "core:strings"
import "core:testing"

/* Verifies retained search presentation exposes every visible match boundary. */
@(test)
search_style_walks_all_visible_matches :: proc(t: ^testing.T) {
	boundaries := []display.Boundary_Map{
		{source_byte_offset = 0, row_text_offset = 0},
		{source_byte_offset = 1, row_text_offset = 1},
		{source_byte_offset = 2, row_text_offset = 2},
		{source_byte_offset = 3, row_text_offset = 3},
		{source_byte_offset = 4, row_text_offset = 4},
		{source_byte_offset = 5, row_text_offset = 5},
		{source_byte_offset = 6, row_text_offset = 6},
	}
	matches := []display.Search_Match_Map{
		{start = 1, end = 2, intersects_visible = true},
		{start = 4, end = 6, current = true, intersects_visible = true},
	}
	active, current, next, ok := frame_search_style_at_offset(matches, boundaries, 0, 6)
	testing.expect(t, ok && !active && !current)
	testing.expect_value(t, next, u32(1))
	active, current, next, ok = frame_search_style_at_offset(matches, boundaries, 1, 6)
	testing.expect(t, ok && active && !current)
	testing.expect_value(t, next, u32(2))
	active, current, next, ok = frame_search_style_at_offset(matches, boundaries, 2, 6)
	testing.expect(t, ok && !active && !current)
	testing.expect_value(t, next, u32(4))
	active, current, next, ok = frame_search_style_at_offset(matches, boundaries, 4, 6)
	testing.expect(t, ok && active && current)
	testing.expect_value(t, next, u32(6))
}

/* Verifies one popup is lowered after its underlay with portable borders and source focus. */
@(test)
popup_overlays_without_focus_transfer :: proc(t: ^testing.T) {
	constraints := display.Viewport_Constraints{width_cells = 30, height_rows = 10}
	renderer: Renderer
	renderer_ok, _ := renderer_init(&renderer, renderer_config(constraints))
	testing.expect(t, renderer_ok)
	if !renderer_ok do return
	defer renderer_close(&renderer)
	profile := renderer_state_ui_profile(renderer_state(&renderer))
	registry: ui.Registry
	registry_ok, _ := ui.registry_init(&registry, 700)
	testing.expect(t, registry_ok)
	if !registry_ok do return
	defer ui.registry_close(&registry)
	proposal, prepared, _ := ui.proposal_begin(&registry)
	_, list_normal_ok, _ := ui.proposal_add_style(&proposal, .List_Normal)
	_, list_current_ok, _ := ui.proposal_add_style(&proposal, .List_Current, {.Reverse})
	_, list_emphasis_ok, _ := ui.proposal_add_style(&proposal, .List_Emphasis, {.Bold})
	_, popup_background_ok, _ := ui.proposal_add_style(
		&proposal, .Popup_Background, {.Reverse}, {}, {},
	)
	_, popup_content_ok, _ := ui.proposal_add_style(
		&proposal, .Popup_Content, {.Bold}, {}, {},
	)
	_, popup_border_ok, _ := ui.proposal_add_style(
		&proposal, .Popup_Border, {.Underline}, {}, {},
	)
	_, popup_diagnostic_ok, _ := ui.proposal_add_style(
		&proposal, .Popup_Diagnostic, {.Bold, .Underline}, {}, {},
	)
	_, popup_unavailable_ok, _ := ui.proposal_add_style(
		&proposal, .Popup_Unavailable, {.Dim}, {}, {},
	)
	source_items := []ui.List_Item_Definition {
		{id = 1, text = "underlay", action = {owner_id = 1, action_id = 1, generation = 1}},
	}
	popup_items := []ui.List_Item_Definition {
		{id = 1, text = "detail one", action = {owner_id = 2, action_id = 1, generation = 2}},
		{id = 2, text = "detail two", action = {owner_id = 2, action_id = 2, generation = 2}},
	}
	source_view, source_view_ok, _ := ui.proposal_project_list_view(
		&proposal,
		ui.List_Projection_Request {
			model = {owner_id = 1, model_id = 1, generation = 1},
			position = {
				presentation_generation = 1,
				selection_owner = .Model,
				current_item = 0,
				viewport_items = 10,
			},
			read_only = true,
		},
		source_items,
	)
	popup_view, popup_view_ok, _ := ui.proposal_project_list_view(
		&proposal,
		ui.List_Projection_Request {
			model = {owner_id = 2, model_id = 2, generation = 2},
			position = {
				presentation_generation = 2,
				selection_owner = .Model,
				current_item = 0,
				viewport_items = 2,
			},
			read_only = true,
		},
		popup_items,
	)
	source_surface, source_surface_ok, _ := ui.proposal_add_surface(
		&proposal,
		ui.Surface_Descriptor {
			owner_id = 1,
			view = source_view,
			focusable = true,
			visible = true,
			required_profile = profile.id,
			geometry = {height = 10, width = 30},
		},
	)
	popup_surface, popup_surface_ok, _ := ui.proposal_add_surface(
		&proposal,
		ui.Surface_Descriptor {
			owner_id = 2,
			view = popup_view,
			visible = true,
			required_profile = profile.id,
			geometry = {height = 2, width = 12},
		},
	)
	source_node, source_node_ok, _ := ui.proposal_add_surface_node(&proposal, source_surface)
	popup_descriptor := ui.Popup_Descriptor {
			id = 1,
			generation = 1,
			owner_id = 3,
			owner_generation = 1,
			anchor = {
				kind = .Surface,
				source_surface = source_surface,
				owner_id = 1,
				source_id = u64(source_surface.object_id),
				source_generation = u64(source_surface.root_generation),
				presentation_generation = u64(source_surface.root_generation),
				viewport_row = 4,
				viewport_column = 5,
				height_rows = 1,
				width_columns = 1,
			},
			content_surface = popup_surface,
			content_generation = 2,
			placements = {.Below, .Invalid, .Invalid, .Invalid},
			placement_count = 1,
			bounds = {
				minimum_rows = 4,
				minimum_columns = 8,
				preferred_rows = 4,
				preferred_columns = 14,
				maximum_rows = 4,
				maximum_columns = 14,
			},
			margin_columns = 1,
			border = true,
			clipping = .Wrap,
			behavior = .Informational,
			input_policy = .Preserve_Source_Focus,
			dismissal = {.Explicit_Cancel, .Anchor_Invalidation},
			fallback = .Compact_Feedback,
			required_profile = profile.id,
			content_bytes = 10,
	}
	popup_descriptor.presentation_profile = terminal_popup_test_profile(popup_descriptor)
	_, popup_ok, popup_failure := ui.proposal_add_popup(&proposal, popup_descriptor)
	root_ok, _ := ui.proposal_set_root(&proposal, source_node, source_surface)
	root, published, publish_failure := ui.proposal_publish(&registry, &proposal, profile)
	snapshot, copied, snapshot_failure := ui.registry_snapshot(&registry, root, profile)
	testing.expectf(t, popup_ok, "popup proposal failed with %v", popup_failure.code)
	testing.expectf(t, published, "popup publication failed with %v", publish_failure.code)
	testing.expectf(t, copied, "popup snapshot failed with %v", snapshot_failure.code)
	testing.expect(
		t,
		prepared && list_normal_ok && list_current_ok && list_emphasis_ok && popup_background_ok &&
		popup_content_ok && popup_border_ok && popup_diagnostic_ok && popup_unavailable_ok &&
		source_view_ok && popup_view_ok && source_surface_ok && popup_surface_ok &&
		source_node_ok && root_ok,
	)
	if !copied do return
	defer ui.snapshot_close(&snapshot)
	view, viewed := ui.snapshot_view(&snapshot)
	frame, frame_ok, frame_failure := renderer_prepare_ui(
		renderer_state(&renderer), UI_Presentation{root = &snapshot},
	)
	testing.expectf(t, frame_ok, "popup frame failed with %v", frame_failure.code)
	if !frame_ok do return
	defer frame_close(&frame)
	output := string(frame.output[:frame.used])
	testing.expect(t, viewed)
	if viewed {
		testing.expect_value(t, view.focus.target, source_surface)
		testing.expect(t, !view.focus.captured)
	}
	testing.expect(t, strings.contains(output, "underlay"))
	testing.expect(t, strings.contains(output, "\x1b[6;6H"))
	testing.expect(t, strings.contains(output, "+----------+"))
	testing.expect(t, strings.contains(output, "detail one"))
	testing.expect(t, strings.contains(output, "detail two"))
	unicode_config := renderer_config(constraints)
	unicode_config.icons = .Nerd_Font
	unicode_renderer: Renderer
	unicode_renderer_ok, _ := renderer_init(&unicode_renderer, unicode_config)
	testing.expect(t, unicode_renderer_ok)
	if !unicode_renderer_ok do return
	defer renderer_close(&unicode_renderer)
	unicode_frame, unicode_frame_ok, unicode_failure := renderer_prepare_ui(
		renderer_state(&unicode_renderer), UI_Presentation{root = &snapshot},
	)
	testing.expectf(t, unicode_frame_ok, "Unicode popup frame failed with %v", unicode_failure.code)
	if !unicode_frame_ok do return
	defer frame_close(&unicode_frame)
	unicode_output := string(unicode_frame.output[:unicode_frame.used])
	testing.expect(t, strings.contains(unicode_output, "┌──────────┐"))
	testing.expect(t, strings.contains(unicode_output, "└──────────┘"))
	resized, _ := renderer_resize(
		&renderer,
		display.Viewport_Constraints{width_cells = 8, height_rows = 3},
	)
	_, stale_ok, stale_failure := renderer_prepare_ui(
		renderer_state(&renderer), UI_Presentation{root = &snapshot},
	)
	restored, _ := renderer_resize(&renderer, constraints)
	restored_frame, restored_ok, restored_failure := renderer_prepare_ui(
		renderer_state(&renderer), UI_Presentation{root = &snapshot},
	)
	testing.expect(t, resized && !stale_ok && restored)
	testing.expect_value(t, stale_failure.code, Failure_Code.Invalid_UI_Presentation)
	testing.expectf(t, restored_ok, "restored popup frame failed with %v", restored_failure.code)
	if restored_ok do frame_close(&restored_frame)
}

/* Verifies complete pane geometry, local status rows, separators, reservations, and active cursor placement. */
@(test)
layout_projects_panes_to_geometry :: proc(t: ^testing.T) {
	fixture: Layout_Renderer_Fixture
	if !layout_renderer_fixture_init(t, &fixture) {
		return
	}
	defer layout_renderer_fixture_close(&fixture)
	handle, _, _ := layout.registry_handle(&fixture.layout_registry)
	initial, _, _ := layout.registry_snapshot(&fixture.layout_registry, handle)
	_, split_ok, split_failure := layout.registry_split_right(
		&fixture.layout_registry,
		initial.active_pane,
	)
	testing.expectf(t, split_ok, "layout split failed with %v", split_failure.code)
	if !split_ok {
		return
	}
	handle, _, _ = layout.registry_handle(&fixture.layout_registry)
	layout_snapshot, snapshot_ok, snapshot_failure := layout.registry_snapshot(
		&fixture.layout_registry,
		handle,
	)
	testing.expectf(t, snapshot_ok, "layout snapshot failed with %v", snapshot_failure.code)
	if !snapshot_ok {
		return
	}
	ui_fixture: UI_Layout_Presentation_Fixture
	ui_ready := ui_layout_presentation_fixture_init(t, &ui_fixture, &fixture, layout_snapshot)
	if !ui_ready {
		return
	}
	defer ui_layout_presentation_fixture_close(&ui_fixture)
	constraints := display.Viewport_Constraints{width_cells = 21, height_rows = 6}
	renderer: Renderer
	renderer_ready, _ := renderer_init(&renderer, renderer_config(constraints))
	testing.expect(t, renderer_ready)
	if !renderer_ready {
		return
	}
	defer renderer_close(&renderer)
	frame, prepared, prepare_failure := renderer_prepare_ui(
		renderer_state(&renderer),
		UI_Presentation {
			root = &ui_fixture.snapshot,
			text_surfaces = ui_fixture.projections[:ui_fixture.count],
		},
	)
	testing.expectf(t, prepared, "layout frame failed with %v", prepare_failure.code)
	if !prepared {
		return
	}
	defer frame_close(&frame)
	output := string(frame.output[:frame.used])
	testing.expect(t, strings.contains(output, "\x1b[1;1Halpha"))
	testing.expect(t, strings.contains(output, "\x1b[1;11Halpha"))
	testing.expect(t, strings.contains(output, "\x1b[1mbeta"))
	testing.expect(t, strings.contains(output, "\x1b[1;10H│"))
	testing.expect(t, strings.contains(output, "\x1b[4;1H\x1b[7m──"))
	testing.expect(t, strings.contains(output, "\x1b[5;1H*left"))
	testing.expect(t, strings.contains(output, "\x1b[5;11H right"))
	testing.expect(t, strings.contains(output, "\x1b[1;1H\x1b[?25h"))
}

/* Verifies a shared active region remains renderable after movement in a second pane. */
@(test)
layout_accepts_shared_region_movement :: proc(t: ^testing.T) {
	fixture: Layout_Renderer_Fixture
	if !layout_renderer_fixture_init(t, &fixture) do return
	defer layout_renderer_fixture_close(&fixture)
	start, _, _ := editor.buffer_position(&fixture.buffer, 0)
	end, _, _ := editor.buffer_position(&fixture.buffer, 5)
	selected, _ := editor_view.select_range(
		&fixture.views,
		fixture.root_view,
		start,
		end,
		5,
	)
	handle, _, _ := layout.registry_handle(&fixture.layout_registry)
	initial, _, _ := layout.registry_snapshot(&fixture.layout_registry, handle)
	split, split_ok, _ := layout.registry_split_right(
		&fixture.layout_registry,
		initial.active_pane,
	)
	focus_result, focus_ok, _ := layout.registry_focus(&fixture.layout_registry, split.created)
	active_snapshot, _, _ := layout.registry_snapshot(&fixture.layout_registry, focus_result.layout)
	active_view: editor_view.View_Handle
	for node in active_snapshot.nodes[:int(active_snapshot.node_count)] {
		if node.kind == .Pane && node.active do active_view = node.view
	}
	moved, _ := editor_view.move_point(&fixture.views, active_view, start, 0, .Preserve)
	handle, _, _ = layout.registry_handle(&fixture.layout_registry)
	layout_snapshot, snapshot_ok, _ := layout.registry_snapshot(&fixture.layout_registry, handle)
	ui_fixture: UI_Layout_Presentation_Fixture
	ui_ready := ui_layout_presentation_fixture_init(t, &ui_fixture, &fixture, layout_snapshot)
	if !ui_ready do return
	defer ui_layout_presentation_fixture_close(&ui_fixture)
	renderer: Renderer
	renderer_ready, _ := renderer_init(
		&renderer,
		renderer_config(display.Viewport_Constraints{width_cells = 21, height_rows = 6}),
	)
	if !renderer_ready do return
	defer renderer_close(&renderer)
	frame, prepared, prepare_failure := renderer_prepare_ui(
		renderer_state(&renderer),
		UI_Presentation {
			root = &ui_fixture.snapshot,
			text_surfaces = ui_fixture.projections[:ui_fixture.count],
		},
	)
	testing.expect(t, selected && split_ok && focus_ok && moved && snapshot_ok && ui_ready && renderer_ready)
	testing.expectf(t, prepared, "shared-region frame failed with %v", prepare_failure.code)
	if prepared do frame_close(&frame)
}

/* Verifies missing and mismatched text-surface projections are rejected before frame allocation. */
@(test)
layout_rejects_incomplete_projection :: proc(t: ^testing.T) {
	fixture: Layout_Renderer_Fixture
	if !layout_renderer_fixture_init(t, &fixture) {
		return
	}
	defer layout_renderer_fixture_close(&fixture)
	handle, _, _ := layout.registry_handle(&fixture.layout_registry)
	layout_snapshot, _, _ := layout.registry_snapshot(&fixture.layout_registry, handle)
	ui_fixture: UI_Layout_Presentation_Fixture
	ui_ready := ui_layout_presentation_fixture_init(t, &ui_fixture, &fixture, layout_snapshot)
	if !ui_ready {
		return
	}
	defer ui_layout_presentation_fixture_close(&ui_fixture)
	renderer: Renderer
	initialized, _ := renderer_init(
		&renderer,
		renderer_config(display.Viewport_Constraints{width_cells = 21, height_rows = 6}),
	)
	testing.expect(t, initialized)
	if !initialized {
		return
	}
	defer renderer_close(&renderer)
	_, missing_ok, missing_failure := renderer_prepare_ui(
		renderer_state(&renderer),
		UI_Presentation{root = &ui_fixture.snapshot},
	)
	testing.expect(t, !missing_ok)
	testing.expect_value(t, missing_failure.code, Failure_Code.Invalid_UI_Presentation)
	mismatched := ui_fixture.projections[0]
	mismatched.surface = {}
	_, mismatched_ok, mismatched_failure := renderer_prepare_ui(
		renderer_state(&renderer),
		UI_Presentation {
			root = &ui_fixture.snapshot,
			text_surfaces = []Text_Surface_Projection{mismatched},
		},
	)
	testing.expect(t, !mismatched_ok)
	testing.expect_value(t, mismatched_failure.code, Failure_Code.Invalid_UI_Presentation)
}

/* Verifies root-edge status, transient input, Unicode cursor, and captured focus lowering. */
@(test)
candidate_input_composes_status_query :: proc(t: ^testing.T) {
	constraints := display.Viewport_Constraints{width_cells = 40, height_rows = 4}
	renderer: Renderer
	renderer_ok, _ := renderer_init(&renderer, renderer_config(constraints))
	testing.expect(t, renderer_ok)
	if !renderer_ok do return
	defer renderer_close(&renderer)
	profile := renderer_state_ui_profile(renderer_state(&renderer))
	registry: ui.Registry
	registry_ok, _ := ui.registry_init(&registry, 92)
	testing.expect(t, registry_ok)
	if !registry_ok do return
	defer ui.registry_close(&registry)
	proposal, prepared, _ := ui.proposal_begin(&registry)
	_, normal_ok, _ := ui.proposal_add_style(&proposal, .List_Normal)
	_, current_ok, _ := ui.proposal_add_style(&proposal, .List_Current, {.Reverse})
	_, status_ok, _ := ui.proposal_add_style(&proposal, .Status_Active, {.Bold})
	_, identity_ok, _ := ui.proposal_add_style(&proposal, .Status_Identity, {.Underline})
	_, rejected_ok, _ := ui.proposal_add_style(&proposal, .Diagnostic_Rejected, {.Reverse})
	items := []ui.List_Item_Definition {
		{id = 1, text = "candidate", action = {owner_id = 2, action_id = 1, generation = 3}},
	}
	list, list_ok, _ := ui.proposal_project_list_view(
		&proposal,
		ui.List_Projection_Request {
			model = {owner_id = 2, model_id = 2, generation = 3},
			position = {
				presentation_generation = 3,
				selection_owner = .Model,
				current_item = 0,
				viewport_items = 3,
			},
			read_only = true,
		},
		items,
	)
	input, input_ok, _ := ui.proposal_project_input(
		&proposal,
		ui.Input_Projection_Request {
			model = {owner_id = 2, model_id = 2, generation = 3},
			presentation_generation = 1,
			backing_generation = 3,
			cursor_offset = 2,
			viewport_bytes = 3,
			validation = .Valid,
		},
		"é",
	)
	list_surface, list_surface_ok, _ := ui.proposal_add_surface(
		&proposal,
		ui.Surface_Descriptor {
			owner_id = 2,
			view = list,
			focusable = true,
			visible = true,
			required_profile = profile.id,
			geometry = {height = 3, width = 40},
		},
	)
	input_surface, input_surface_ok, _ := ui.proposal_add_surface(
		&proposal,
		ui.Surface_Descriptor {
			owner_id = 2,
			view = input,
			focusable = true,
			visible = true,
			required_profile = profile.id,
			geometry = {row = 3, column = 8, height = 1, width = 32},
		},
	)
	list_node, list_node_ok, _ := ui.proposal_add_surface_node(&proposal, list_surface)
	input_node, input_node_ok, _ := ui.proposal_add_surface_node(&proposal, input_surface)
	root_node, root_node_ok, _ := ui.proposal_add_split(
		&proposal, list_node, input_node, .Above_Below, 3, 1,
	)
	status_spans: [ui.MAX_STATUS_STYLE_SPANS]ui.Status_Style_Span
	status_spans[0] = {start_byte = 0, end_byte = 6, style_role = .Status_Identity}
	_, root_status_ok, _ := ui.proposal_add_status(
		&proposal,
		ui.Status_Region_Descriptor {
			owner_id = 2,
			placement = .Root_Edge,
			rows = 1,
			geometry = {row = 3, height = 1, width = 40},
			style_role = .Status_Active,
			style_spans = status_spans,
			style_span_count = 1,
			active = true,
		},
		"Prompt: ",
	)
	root_ok, _ := ui.proposal_set_root(&proposal, root_node, list_surface)
	root, published, _ := ui.proposal_publish(&registry, &proposal, profile)
	captured, _ := ui.registry_capture_focus(&registry, input_surface)
	snapshot, copied, _ := ui.registry_snapshot(&registry, root, profile)
	testing.expect(t, prepared && normal_ok && current_ok && status_ok && identity_ok && rejected_ok &&
		list_ok && input_ok && list_surface_ok && input_surface_ok && list_node_ok &&
		input_node_ok && root_node_ok && root_status_ok && root_ok && published &&
		captured && copied)
	if !copied do return
	defer ui.snapshot_close(&snapshot)
	frame, frame_ok, frame_failure := renderer_prepare_ui(
		renderer_state(&renderer), UI_Presentation{root = &snapshot},
	)
	testing.expectf(t, frame_ok, "candidate input frame failed with %v", frame_failure.code)
	if !frame_ok do return
	defer frame_close(&frame)
	output := string(frame.output[:frame.used])
	testing.expect(t, strings.contains(output, "\x1b[4mPrompt"))
	testing.expect(t, strings.contains(output, ": "))
	testing.expect(t, strings.contains(output, "é"))
	testing.expect(t, strings.contains(output, "\x1b[4;10H\x1b[?25h"))
}

@(private)
UI_Layout_Presentation_Fixture :: struct {
	registry:    ui.Registry,
	snapshot:    ui.Snapshot,
	displays:    [layout.MAX_LIVE_PANES]display.Snapshot,
	projections: [layout.MAX_LIVE_PANES]Text_Surface_Projection,
	count:       int,
}

@(private)
ui_layout_presentation_fixture_init :: proc(
	t: ^testing.T,
	output: ^UI_Layout_Presentation_Fixture,
	source: ^Layout_Renderer_Fixture,
	layout_snapshot: layout.Snapshot,
) -> bool {
	initialized, _ := ui.registry_init(&output.registry, 91)
	proposal, prepared, _ := ui.proposal_begin(&output.registry)
	_, text_style, _ := ui.proposal_add_style(&proposal, .Text_Normal)
	_, region_style, _ := ui.proposal_add_style(&proposal, .Text_Region, {.Reverse})
	_, search_style, _ := ui.proposal_add_style(&proposal, .Text_Search_Current, {.Reverse})
	_, status_style, _ := ui.proposal_add_style(&proposal, .Status_Normal, {.Reverse})
	_, active_status_style, _ := ui.proposal_add_style(&proposal, .Status_Active, {.Reverse})
	_, diagnostic_error_style, _ := ui.proposal_add_style(&proposal, .Diagnostic_Error, {.Underline})
	_, diagnostic_warning_style, _ := ui.proposal_add_style(&proposal, .Diagnostic_Warning, {.Bold})
	_, diagnostic_information_style, _ := ui.proposal_add_style(&proposal, .Diagnostic_Information, {.Reverse})
	_, diagnostic_hint_style, _ := ui.proposal_add_style(&proposal, .Diagnostic_Hint, {.Dim})
	syntax_styles, _ := ui.proposal_add_factory_syntax_styles(&proposal)
	provider := language.Provider_Handle {
		registry_id = 1,
		language_id = 1,
		provider_id = 1,
		provider_generation = 1,
	}
	syntax_projected := true
	diagnostics_projected := true
	bindings: [layout.MAX_LIVE_PANES]ui.Pane_Text_View_Binding
	panes: [layout.MAX_LIVE_PANES]layout.Pane_Handle
	for node_index in 0 ..< int(layout_snapshot.node_count) {
		node := layout_snapshot.nodes[node_index]
		if node.kind != .Pane do continue
		logical, logical_ok, _ := editor_view.snapshot(&source.views, node.view)
		ui_view, ui_view_ok, _ := ui.proposal_project_editor_text_view(
			&proposal, &source.views, node.view, &source.buffer, 91,
		)
		spans := [1]language.Syntax_Span {{
			start = 0,
			end = 5,
			role = .Keyword,
			precedence = 10,
			provider = provider,
			source_revision = logical.revision,
		}}
		syntax_snapshot := language.Syntax_Snapshot {
			generation = language.Syntax_Snapshot_Generation(output.count + 1),
			buffer_id = logical.buffer_id,
			source_revision = logical.revision,
			language = {id = 1, generation = 1},
			provider = provider,
			selection_generation = 1,
			parser_generation = 1,
			query_generation = 1,
			span_count = 1,
			usage = {
				spans = 1,
				retained_span_bytes = u64(size_of(language.Syntax_Span)),
			},
		}
		_, view_syntax_ok, _ := ui.proposal_project_syntax_decorations(
			&proposal,
			ui_view,
			syntax_snapshot,
			spans[:],
			91,
		)
		syntax_projected = syntax_projected && view_syntax_ok
		diagnostic_binding := language_service.Document_Binding_Handle {
			session = {provider = {definition = {registry = {id = 1, generation = 1},
				id = 1, generation = 1}, id = 1, generation = 1}, id = 1, generation = 1},
			id = language_service.Document_Binding_ID(output.count + 1), generation = 1,
		}
		diagnostic_records := [1]language_service.Diagnostic_Record {{
			binding = diagnostic_binding, generation = 1, id = 1,
			canonical_revision = u64(logical.revision), range = {start = 6, end = 10},
			severity = .Warning,
		}}
		_, view_diagnostics_ok, _ := language_service.proposal_project_diagnostics(
			&proposal, ui_view,
			language_service.Diagnostic_Batch_Descriptor {
				binding = diagnostic_binding, generation = 1,
				canonical_revision = u64(logical.revision), diagnostics = 1, warnings = 1,
			},
			diagnostic_records[:], 91,
		)
		diagnostics_projected = diagnostics_projected && view_diagnostics_ok
		constraints := display.Viewport_Constraints {
			width_cells = u32(node.geometry.content.width),
			height_rows = u32(node.geometry.content.height),
		}
		projected, projected_ok, projection_failure := display.project(
			&source.buffer,
			layout_renderer_projection_request(u64(output.count + 1), logical, constraints),
		)
		testing.expectf(t, projected_ok, "pane projection failed with %v", projection_failure.code)
		if !logical_ok || !ui_view_ok || !projected_ok {
			if projected_ok do display.snapshot_close(&projected)
			ui.proposal_abort(&proposal)
			ui_layout_presentation_fixture_close(output)
			return false
		}
		output.displays[output.count] = projected
		output.projections[output.count] = Text_Surface_Projection {
			snapshot = projected,
			logical = logical,
		}
		bindings[output.count] = ui.Pane_Text_View_Binding{pane = node.pane, view = ui_view}
		panes[output.count] = node.pane
		output.count += 1
	}
	_, mapped, _ := ui.proposal_map_pane_layout(
		&proposal, layout_snapshot, bindings[:output.count], 1,
	)
	statuses_ok := mapped
	for index in 0 ..< output.count {
		surface, surface_ok, _ := ui.proposal_pane_surface(&proposal, panes[index])
		output.projections[index].surface = surface
		label := " right"
		if panes[index] == layout_snapshot.active_pane do label = "*left"
		_, status_ok, _ := ui.proposal_project_pane_status(
			&proposal,
			surface,
			label,
		)
		statuses_ok = statuses_ok && surface_ok && status_ok
	}
	root_ok := initialized && prepared && text_style && region_style && search_style &&
		status_style && active_status_style && diagnostic_error_style &&
		diagnostic_warning_style && diagnostic_information_style && diagnostic_hint_style &&
		syntax_styles && syntax_projected && diagnostics_projected && mapped &&
		statuses_ok
	root: ui.Root_Handle
	published := false
	if root_ok do root, published, _ = ui.proposal_publish(
		&output.registry, &proposal, ui_test_renderer_profile(),
	)
	if proposal.state != nil do ui.proposal_abort(&proposal)
	if published do output.snapshot, root_ok, _ = ui.registry_snapshot(
		&output.registry, root, ui_test_renderer_profile(),
	)
	if !root_ok {
		ui_layout_presentation_fixture_close(output)
		return false
	}
	return true
}

@(private)
ui_layout_presentation_fixture_close :: proc(fixture: ^UI_Layout_Presentation_Fixture) {
	if fixture.snapshot.state != nil do ui.snapshot_close(&fixture.snapshot)
	for index in 0 ..< fixture.count {
		if fixture.displays[index].state != nil do display.snapshot_close(&fixture.displays[index])
	}
	if fixture.registry.state != nil && !fixture.registry.closed do ui.registry_close(&fixture.registry)
}

@(private)
ui_test_renderer_profile :: proc() -> ui.Renderer_Profile {
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
			.Popup_Overlap,
		},
		unicode_profile = 1,
		max_rows = 6,
		max_columns = 21,
		max_cells = 126,
		attributes = {
			.Bold, .Dim, .Italic, .Underline, .Blink, .Reverse, .Strikethrough, .Overline,
		},
	}
}

@(private)
Layout_Renderer_Fixture :: struct {
	buffer:          editor.Buffer,
	views:           editor_view.Registry,
	root_view:       editor_view.View_Handle,
	layout_registry: layout.Registry,
}

@(private)
layout_renderer_fixture_init :: proc(t: ^testing.T, fixture: ^Layout_Renderer_Fixture) -> bool {
	buffer_ok, buffer_failure := editor.buffer_init(
		&fixture.buffer,
		editor.Buffer_ID(91),
		"alpha\nbeta\ngamma",
		editor.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	testing.expectf(t, buffer_ok, "buffer failed with %v", buffer_failure.code)
	if !buffer_ok {
		return false
	}
	views_ok, _ := editor_view.registry_init(
		&fixture.views,
		editor_view.Registry_ID(91),
		context.allocator,
	)
	if !views_ok {
		editor.buffer_close(&fixture.buffer)
		return false
	}
	root_view, view_ok, _ := editor_view.create(&fixture.views, &fixture.buffer)
	if !view_ok {
		editor_view.registry_close(&fixture.views)
		editor.buffer_close(&fixture.buffer)
		return false
	}
	fixture.root_view = root_view
	layout_ok, layout_failure := layout.registry_init(
		&fixture.layout_registry,
		layout.Owner_ID(91),
		layout.Layout_ID(91),
		&fixture.views,
		fixture.root_view,
		layout.Geometry_Request {
			rows = 6,
			columns = 21,
			global_reserved_rows = 1,
			global_reserved_columns = 1,
		},
	)
	testing.expectf(t, layout_ok, "layout failed with %v", layout_failure.code)
	if !layout_ok {
		editor_view.close(&fixture.views, &fixture.root_view)
		editor_view.registry_close(&fixture.views)
		editor.buffer_close(&fixture.buffer)
		return false
	}
	return true
}

@(private)
layout_renderer_fixture_close :: proc(fixture: ^Layout_Renderer_Fixture) {
	if !fixture.layout_registry.closed && fixture.layout_registry.state != nil {
		layout.registry_close(&fixture.layout_registry)
	}
	if fixture.root_view.view_id != editor_view.View_ID(0) {
		editor_view.close(&fixture.views, &fixture.root_view)
	}
	if !fixture.views.closed && fixture.views.state != nil {
		editor_view.registry_close(&fixture.views)
	}
	if editor.buffer_is_live(&fixture.buffer) {
		editor.buffer_close(&fixture.buffer)
	}
}

@(private)
layout_renderer_projection_request :: proc(
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

@(private)
terminal_popup_test_profile :: proc(
	descriptor: ui.Popup_Descriptor,
) -> ui.Presentation_Profile_Record {
	name, _ := ui.presentation_profile_text("terminal-popup-test")
	source, _ := ui.presentation_profile_text("terminal-tests")
	return {
		handle = {
			registry_id = 9_101,
			role = .Contextual_Information,
			profile_id = ui.Presentation_Profile_ID(descriptor.id),
			profile_generation = ui.Presentation_Profile_Generation(descriptor.generation),
		},
		definition = {
			name = name,
			source = source,
			kind = .Factory,
			role = .Contextual_Information,
			mappings = {
				0 = {slot = .Background, style_role = .Popup_Background},
				1 = {slot = .Border, style_role = .Popup_Border},
				2 = {slot = .Title, style_role = .Popup_Border},
				3 = {slot = .Content, style_role = .Popup_Content},
				4 = {slot = .Selection, style_role = .List_Emphasis},
				5 = {slot = .Annotation, style_role = .Popup_Diagnostic},
				6 = {slot = .Separator, style_role = .Popup_Border},
				7 = {slot = .Action, style_role = .List_Emphasis},
				8 = {slot = .Unavailable, style_role = .Popup_Unavailable},
				9 = {slot = .Attention, style_role = .Popup_Diagnostic},
			},
			mapping_count = 10,
			margin_rows = descriptor.margin_rows,
			margin_columns = descriptor.margin_columns,
			padding_rows = descriptor.padding_rows,
			padding_columns = descriptor.padding_columns,
			border = .Single if descriptor.border else .None,
			bounds = descriptor.bounds,
			clipping = descriptor.clipping,
			popup_fallback = descriptor.fallback,
			degradation = .Portable_Border,
			required_capabilities = {.Cell_Geometry, .Clipping},
			configurable = true,
		},
	}
}
