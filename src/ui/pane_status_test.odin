// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ui

import "core:testing"

@(test)
/* pane_status_projection_copies_content_style_and_delivered_geometry. */
projection_copies_content_style :: proc(t: ^testing.T) {
	registry: Registry
	initialized, _ := registry_init(&registry, 811)
	if !initialized {
		testing.expect(t, false)
		return
	}
	defer registry_close(&registry)
	proposal, prepared, _ := proposal_begin(&registry)
	_, text_style, _ := proposal_add_style(&proposal, .Text_Normal)
	_, normal_style, _ := proposal_add_style(&proposal, .Status_Normal, {.Reverse})
	_, active_style, _ := proposal_add_style(&proposal, .Status_Active, {.Reverse, .Bold})
	_, identity_style, _ := proposal_add_style(&proposal, .Status_Identity, {.Bold})
	_, position_style, _ := proposal_add_style(&proposal, .Status_Position, {.Dim})
	projection, projected, _ := proposal_add_projection(
		&proposal,
		Model_Reference{owner_id = 811, model_id = 9, generation = 1},
		64,
	)
	view, viewed, _ := proposal_add_view(
		&proposal,
		Visual_View_Descriptor{kind = .Text_View, projection = projection},
	)
	surface, surfaced, _ := proposal_add_surface(
		&proposal,
		Surface_Descriptor {
			owner_id = 811,
			view = view,
			focusable = true,
			visible = true,
			required_profile = 1,
			pane = Pane_Surface_State {
				present = true,
				layout_owner_id = 5,
				layout_id = 6,
				layout_generation = 7,
				node_id = 4,
				status = Cell_Rect{row = 22, column = 0, height = 2, width = 80},
				active = true,
			},
		},
	)
	node, node_ok, _ := proposal_add_surface_node(&proposal, surface)
	if node_ok {
		entry, _ := resolve_node(proposal_state(&proposal), node)
		entry.layout = Layout_Node_State {
			present = true,
			layout_owner_id = 5,
			layout_id = 6,
			layout_generation = 7,
			node_id = 4,
			geometry_state = .Operating,
		}
	}
	status_content := "active.txt                                                            4:8 17%"
	status_spans := [2]Status_Style_Span {
		{start_byte = 0, end_byte = 10, style_role = .Status_Identity},
		{start_byte = 70, end_byte = 77, style_role = .Status_Position},
	}
	status_segments := [2]Status_Segment_Definition {
		{
			identity = 1,
			kind = 1,
			start_byte = 0,
			end_byte = 10,
			start_cell = 0,
			end_cell = 10,
			inspection_text = "active.txt",
			primary_command = {registry_generation = 7, slot = 3, entry_generation = 1},
		},
		{
			identity = 2,
			kind = 2,
			start_byte = 70,
			end_byte = 77,
			start_cell = 70,
			end_cell = 77,
			inspection_text = "line 4, column 8",
		},
	}
	status, status_ok, status_failure := proposal_project_pane_status(
		&proposal,
		surface,
		status_content,
		status_spans[:],
		19,
		status_segments[:],
	)
	root_ok, _ := proposal_set_root(&proposal, node, surface)
	root, published, _ := proposal_publish(&registry, &proposal, text_test_renderer())
	snapshot, copied, snapshot_failure := registry_snapshot(&registry, root, text_test_renderer())
	snapshot_view, snapshot_ok := snapshot_view(&snapshot)

	testing.expectf(t, status_ok, "pane status failed with %v", status_failure.code)
	testing.expect(
		t,
		prepared && text_style && normal_style && active_style && identity_style &&
		position_style && projected && viewed &&
		surfaced && node_ok && root_ok && published && copied && snapshot_ok,
	)
	testing.expectf(t, copied, "snapshot failed with %v", snapshot_failure.code)
	testing.expectf(t, snapshot_ok, "snapshot view unavailable copied=%v", copied)
	if snapshot_ok {
		testing.expect_value(t, len(snapshot_view.status_regions), 1)
		entry := snapshot_view.status_regions[0]
		content, content_ok := snapshot_status_content(snapshot_view, entry)
		testing.expect(t, content_ok)
		testing.expect_value(t, entry.handle, status)
		testing.expect_value(t, entry.geometry, Cell_Rect{row = 22, column = 0, height = 2, width = 80})
		testing.expect_value(t, entry.style_role, Style_Role.Status_Active)
		testing.expect(t, entry.active)
		testing.expect_value(t, entry.style_span_count, u8(2))
		testing.expect_value(t, entry.style_spans[0], status_spans[0])
		testing.expect_value(t, entry.style_spans[1], status_spans[1])
		testing.expect_value(t, entry.presentation_generation, u64(19))
		testing.expect_value(t, entry.segment_count, u8(2))
		segment, inspection, segment_ok := snapshot_status_segment(snapshot_view, entry, 0)
		testing.expect(t, segment_ok)
		testing.expect_value(t, segment.identity, u64(1))
		testing.expect_value(t, inspection, "active.txt")
		command, command_ok := snapshot_status_segment_command(snapshot_view, entry, 0)
		testing.expect(t, command_ok)
		testing.expect_value(t, command.registry_generation, u64(7))
		_, unavailable := snapshot_status_segment_command(snapshot_view, entry, 1)
		testing.expect(t, !unavailable)
		testing.expect_value(t, content, status_content)
		testing.expect_value(
			t,
			snapshot_view.accounting.compact_region_bytes,
			u64(len(content) + len("active.txt") + len("line 4, column 8")),
		)
	}
	if copied do snapshot_close(&snapshot)
}

@(test)
/* Rejects status style spans that split UTF-8 or exceed copied content. */
projection_rejects_invalid_style_spans :: proc(t: ^testing.T) {
	registry: Registry
	initialized, _ := registry_init(&registry, 812)
	testing.expect(t, initialized)
	if !initialized do return
	defer registry_close(&registry)
	proposal, prepared, _ := proposal_begin(&registry)
	defer proposal_abort(&proposal)
	_, status_style, _ := proposal_add_style(&proposal, .Status_Normal)
	_, identity_style, _ := proposal_add_style(&proposal, .Status_Identity)
	invalid: [MAX_STATUS_STYLE_SPANS]Status_Style_Span
	invalid[0] = Status_Style_Span {
		start_byte = 1,
		end_byte = 2,
		style_role = .Status_Identity,
	}
	_, ok, failure := proposal_add_status(
		&proposal,
		Status_Region_Descriptor {
			owner_id = 812,
			placement = .Root_Edge,
			rows = 1,
			geometry = {height = 1, width = 8},
			style_role = .Status_Normal,
			style_spans = invalid,
			style_span_count = 1,
		},
		"é status",
	)
	testing.expect(t, prepared && status_style && identity_style)
	testing.expect(t, !ok)
	testing.expect_value(t, failure.code, Failure_Code.Invalid_Status_Region)
}
