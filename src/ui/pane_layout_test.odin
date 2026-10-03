// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ui

import "../editor"
import "../layout"
import editor_view "../view"
import "core:testing"

@(test)
/* pane_layout_projection_preserves_split_geometry_focus_and_pane_state. */
projection_preserves_split_geometry_focus :: proc(t: ^testing.T) {
	buffer: editor.Buffer
	buffer_ok, _ := editor.buffer_init(
		&buffer,
		701,
		"layout text",
		editor.Allocator_Set {persistent = context.allocator, temporary = context.temp_allocator},
	)
	views: editor_view.Registry
	views_ok, _ := editor_view.registry_init(&views, 701, context.allocator)
	root_view, root_view_ok, _ := editor_view.create(&views, &buffer)
	registry: layout.Registry
	layout_ok, _ := layout.registry_init(
		&registry,
		701,
		701,
		&views,
		root_view,
		layout.Geometry_Request{rows = 24, columns = 80},
	)
	initial, _, _ := layout.registry_handle(&registry)
	initial_snapshot, _, _ := layout.registry_snapshot(&registry, initial)
	split, split_ok, _ := layout.registry_split_right(&registry, initial_snapshot.active_pane)
	dedication, dedication_ok, _ := layout.registry_pane_dedication_set(
		&registry, split.created, .Soft,
	)
	focused, focused_ok, _ := layout.registry_focus(&registry, dedication.pane)
	source, source_ok, _ := layout.registry_snapshot(&registry, focused.layout)
	testing.expect(
		t,
		buffer_ok && views_ok && root_view_ok && layout_ok && split_ok &&
		dedication_ok && focused_ok && source_ok,
	)
	if !source_ok {
		return
	}

	ui_registry: Registry
	ui_ok, _ := registry_init(&ui_registry, 701)
	proposal, proposal_ok, _ := proposal_begin(&ui_registry)
	_, style_ok, _ := proposal_add_style(&proposal, .Text_Normal)
	_, status_style_ok, _ := proposal_add_style(&proposal, .Status_Normal, {.Reverse})
	_, active_status_style_ok, _ := proposal_add_style(&proposal, .Status_Active, {.Reverse, .Bold})
	bindings: [layout.MAX_LIVE_PANES]Pane_Text_View_Binding
	binding_count: int
	for node_index in 0 ..< int(source.node_count) {
		node := source.nodes[node_index]
		if node.kind != .Pane do continue
		text_view, projected, failure := proposal_project_editor_text_view(
			&proposal, &views, node.view, &buffer, 701,
		)
		testing.expectf(t, projected, "pane text projection failed with %v", failure.code)
		if !projected do return
		bindings[binding_count] = Pane_Text_View_Binding{pane = node.pane, view = text_view}
		binding_count += 1
	}
	mapped, mapped_ok, map_failure := proposal_map_pane_layout(
		&proposal, source, bindings[:binding_count], 1,
	)
	statuses_ok := mapped_ok
	if mapped_ok {
		state := proposal_state(&proposal)
		for surface_index in 0 ..< state.surface_count {
			_, status_ok, _ := proposal_project_pane_status(
				&proposal,
				state.surfaces[surface_index].handle,
				"-- layout.txt                    0% (1,1)",
			)
			statuses_ok = status_ok && statuses_ok
		}
	}
	root, published, publish_failure := proposal_publish(
		&ui_registry, &proposal, text_test_renderer(),
	)
	snapshot, copied, copy_failure := registry_snapshot(
		&ui_registry, root, text_test_renderer(),
	)
	ui_state, viewed := snapshot_view(&snapshot)

	testing.expectf(t, mapped_ok, "pane layout mapping failed with %v", map_failure.code)
	testing.expectf(t, published, "pane layout publication failed with %v", publish_failure.code)
	testing.expectf(t, copied, "pane layout snapshot failed with %v", copy_failure.code)
	testing.expect(
		t,
		ui_ok && proposal_ok && style_ok && status_style_ok && active_status_style_ok &&
			statuses_ok && viewed,
	)
	testing.expect_value(t, mapped.pane_count, u16(2))
	if viewed {
		testing.expect_value(t, len(ui_state.surfaces), 2)
		testing.expect_value(t, len(ui_state.composition), 3)
		testing.expect_value(t, len(ui_state.status_regions), 2)
		testing.expect_value(t, ui_state.root_node, mapped.root_node)
		testing.expect_value(t, ui_state.focus.target, mapped.focus_surface)
		active_count: int
		soft_count: int
		for surface in ui_state.surfaces {
			testing.expect(t, surface.pane.present)
			testing.expect_value(t, surface.pane.layout_generation, u64(source.handle.generation))
			testing.expect_value(t, surface.pane.content.height, i32(22))
			testing.expect_value(t, surface.pane.status.height, i32(2))
			if surface.pane.active do active_count += 1
			if surface.pane.dedication == .Soft do soft_count += 1
		}
		testing.expect_value(t, active_count, 1)
		testing.expect_value(t, soft_count, 1)
		active_status_count: int
		for status in ui_state.status_regions {
			content, content_ok := snapshot_status_content(ui_state, status)
			testing.expect(t, content_ok && len(content) > 0)
			testing.expect_value(t, status.geometry.height, i32(2))
			if status.active {
				active_status_count += 1
				testing.expect_value(t, status.style_role, Style_Role.Status_Active)
			} else {
				testing.expect_value(t, status.style_role, Style_Role.Status_Normal)
			}
		}
		testing.expect_value(t, active_status_count, 1)
		root_node_found := false
		for node in ui_state.composition {
			if node.handle != ui_state.root_node do continue
			root_node_found = true
			testing.expect_value(t, node.kind, Composition_Kind.Split)
			testing.expect_value(t, node.orientation, Split_Orientation.Left_Right)
			testing.expect(t, node.layout.present)
			testing.expect_value(t, node.layout.node_id, u64(source.root_id))
			testing.expect_value(t, node.layout.geometry_state, Layout_Geometry_State.Operating)
			testing.expect_value(t, node.layout.geometry_rows, i32(24))
			testing.expect_value(t, node.layout.geometry_columns, i32(80))
		}
		testing.expect(t, root_node_found)
	}

	if copied do snapshot_close(&snapshot)
	if ui_ok do registry_close(&ui_registry)
	layout.registry_close(&registry)
	editor_view.close(&views, &root_view)
	editor_view.registry_close(&views)
	editor.buffer_close(&buffer)
}
