// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ui

import "core:testing"

@(test)
/* Ensures one terminal view publishes copied cells, metadata, and an immutable title. */
terminal_view_copies_emulated_surface :: proc(t: ^testing.T) {
	registry: Registry
	initialized, _ := registry_init(&registry, 91)
	testing.expect(t, initialized)
	if !initialized do return
	defer registry_close(&registry)
	proposal, prepared, _ := proposal_begin(&registry)
	testing.expect(t, prepared)
	if !prepared do return
	_, style_ok, _ := proposal_add_style(&proposal, .Text_Normal)
	rows := []Terminal_Row {{row = 0, dirty = true}, {row = 1, wrapped = true}}
	cells := []Terminal_Cell {{column = 0, row = 0, text_length = 1, width = 0}}
	cells[0].text[0] = 'A'
	cells[0].style.foreground = {
		kind = .RGB,
		rgb = {red = 10, green = 20, blue = 30},
	}
	cells[0].style.attributes = {.Bold, .Italic, .Underline}
	request := terminal_test_request("shell")
	view, view_ok, _ := proposal_project_terminal_view(&proposal, request, rows, cells)
	surface, surface_ok, _ := proposal_add_surface(&proposal, Surface_Descriptor {
		owner_id = 7,
		view = view,
		focusable = true,
		visible = true,
		required_profile = test_renderer().id,
		geometry = {height = 2, width = 4},
	})
	node, node_ok, _ := proposal_add_surface_node(&proposal, surface)
	root_ok, _ := proposal_set_root(&proposal, node, surface)
	root, published, _ := proposal_publish(&registry, &proposal, test_renderer())
	testing.expect(t, style_ok && view_ok && surface_ok && node_ok && root_ok && published)
	if !published do return
	snapshot, copied, _ := registry_snapshot(&registry, root, test_renderer())
	testing.expect(t, copied)
	if !copied do return
	defer snapshot_close(&snapshot)
	root_view, viewed := snapshot_view(&snapshot)
	terminal_view := root_view.views[0]
	copied_rows, rows_ok := snapshot_terminal_rows(root_view, terminal_view)
	copied_cells, cells_ok := snapshot_terminal_cells(root_view, terminal_view)
	title, title_ok := snapshot_terminal_title(root_view, terminal_view)
	testing.expect(t, viewed && rows_ok && cells_ok && title_ok)
	testing.expect_value(t, terminal_view.kind, Visual_Kind.Terminal_View)
	testing.expect_value(t, len(copied_rows), 2)
	testing.expect_value(t, len(copied_cells), 1)
	testing.expect_value(t, copied_cells[0].text[0], u8('A'))
	testing.expect(t, .Italic in copied_cells[0].style.attributes)
	testing.expect_value(t, title, "shell")
	testing.expect_value(t, terminal_view.terminal.lifecycle, Terminal_Lifecycle.Running)
	testing.expect_value(
		t, terminal_view.terminal.audible_attention, request.audible_attention,
	)
	testing.expect_value(
		t, terminal_view.terminal.visual_attention, request.visual_attention,
	)
}

@(test)
/* Ensures child control sequences cannot enter the logical terminal surface. */
terminal_view_rejects_raw_control_bytes :: proc(t: ^testing.T) {
	registry: Registry
	initialized, _ := registry_init(&registry, 92)
	testing.expect(t, initialized)
	if !initialized do return
	defer registry_close(&registry)
	proposal, prepared, _ := proposal_begin(&registry)
	if !prepared do return
	rows := []Terminal_Row {{row = 0}, {row = 1}}
	cells := []Terminal_Cell {{column = 0, row = 0, text_length = 2}}
	cells[0].text[0] = 0x1b
	cells[0].text[1] = '['
	_, projected, failure := proposal_project_terminal_view(
		&proposal,
		terminal_test_request("unsafe"),
		rows,
		cells,
	)
	testing.expect(t, !projected)
	testing.expect_value(t, failure.code, Failure_Code.Malformed_Terminal_Cell)
	proposal_abort(&proposal)
}

@(private)
terminal_test_request :: proc(title: string) -> Terminal_Projection_Request {
	request := Terminal_Projection_Request {
		model = {owner_id = 7, model_id = 9, generation = 11},
		session_id = 3,
		session_generation = 4,
		revision = 5,
		columns = 4,
		rows = 2,
		damage = .Partial,
		cursor = {
			column = 1,
			row = 0,
			style = .Bar,
			in_viewport = true,
			visible = true,
		},
		foreground = {red = 230, green = 230, blue = 230},
		background = {red = 10, green = 10, blue = 10},
		lifecycle = .Running,
		activity_generation = 6,
		audible_attention = true,
		visual_attention = true,
		title = title,
	}
	request.palette[1] = {red = 128, green = 0, blue = 0}
	return request
}
