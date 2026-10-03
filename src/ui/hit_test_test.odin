// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ui

import "core:testing"

@(test)
/* Rejects a stacking search deeper than the bounded semantic hit path. */
hit_test_rejects_excessive_stack_depth :: proc(t: ^testing.T) {
	surfaces: [MAX_LIVE_SURFACES + 2]Surface_Descriptor
	root := Root_Handle{registry_id = 1, generation = 1}
	_, hit, failure := snapshot_hit_test(
		Snapshot_View {
			root = root,
			renderer = {id = 1, max_rows = 24, max_columns = 80},
			surfaces = surfaces[:],
		},
		Hit_Request{root = root, row = 0, column = 0},
	)
	testing.expect(t, !hit)
	testing.expect_value(t, failure.code, Failure_Code.Geometry_Work_Limit)
	testing.expect_value(t, failure.limit, MAX_HIT_TEST_DEPTH)
}

@(test)
/* Resolves popup precedence without falling through to obscured pane content. */
hit_test_consumes_topmost_popup :: proc(t: ^testing.T) {
	fixture: Hit_Test_Fixture
	snapshot := hit_test_snapshot(&fixture)
	popup_handle := hit_test_handle(30, 5)
	popups := [1]Popup_Descriptor {{
		handle = popup_handle,
		content_surface = hit_test_handle(31, 6),
		geometry = {
			state = .Placed,
			outer = {row = 3, column = 4, height = 5, width = 12},
			content = {row = 4, column = 5, height = 3, width = 10},
			z_order = 4,
			obscures_underlay = true,
		},
	}}
	snapshot.popups = popups[:]

	border, border_ok, _ := snapshot_hit_test(
		snapshot,
		Hit_Request{root = snapshot.root, row = 3, column = 4},
	)
	content, content_ok, _ := snapshot_hit_test(
		snapshot,
		Hit_Request{root = snapshot.root, row = 5, column = 8},
	)

	testing.expect(t, border_ok && content_ok)
	testing.expect_value(t, border.kind, Hit_Kind.Popup)
	testing.expect_value(t, content.kind, Hit_Kind.Popup)
	testing.expect_value(t, border.popup, popup_handle)
	testing.expect_value(t, content.popup, popup_handle)
	testing.expect_value(t, border.surface, popups[0].content_surface)
}

@(test)
/* Resolves attached pane regions and gutter geometry before pane content. */
hit_test_classifies_pane_regions :: proc(t: ^testing.T) {
	fixture: Hit_Test_Fixture
	snapshot := hit_test_snapshot(&fixture)

	left_gutter, left_ok, _ := snapshot_hit_test(
		snapshot,
		Hit_Request{root = snapshot.root, row = 3, column = 3},
	)
	right_gutter, right_ok, _ := snapshot_hit_test(
		snapshot,
		Hit_Request{root = snapshot.root, row = 3, column = 20},
	)
	content, content_ok, _ := snapshot_hit_test(
		snapshot,
		Hit_Request{root = snapshot.root, row = 3, column = 10},
	)
	status, status_ok, _ := snapshot_hit_test(
		snapshot,
		Hit_Request{root = snapshot.root, row = 12, column = 10},
	)
	separator, separator_ok, _ := snapshot_hit_test(
		snapshot,
		Hit_Request{root = snapshot.root, row = 13, column = 10},
	)
	pane, pane_ok, _ := snapshot_hit_test(
		snapshot,
		Hit_Request{root = snapshot.root, row = 3, column = 23},
	)

	testing.expect(t, left_ok && right_ok && content_ok && status_ok && separator_ok && pane_ok)
	testing.expect_value(t, left_gutter.kind, Hit_Kind.Gutter)
	testing.expect_value(t, right_gutter.kind, Hit_Kind.Gutter)
	testing.expect_value(t, content.kind, Hit_Kind.Content)
	testing.expect_value(t, content.surface, hit_test_handle(20, 2))
	testing.expect_value(t, status.kind, Hit_Kind.Status)
	testing.expect_value(t, status.status, hit_test_handle(40, 4))
	testing.expect_value(t, separator.kind, Hit_Kind.Separator)
	testing.expect_value(t, separator.local_row, i32(0))
	testing.expect_value(t, pane.kind, Hit_Kind.Surface)
	testing.expect_value(t, pane.surface, hit_test_handle(20, 2))
}

@(test)
/* Resolves the last visible overlapping surface and bounded background. */
hit_test_respects_surface_order_and_background :: proc(t: ^testing.T) {
	fixture: Hit_Test_Fixture
	snapshot := hit_test_snapshot(&fixture)

	overlap, overlap_ok, _ := snapshot_hit_test(
		snapshot,
		Hit_Request{root = snapshot.root, row = 4, column = 5},
	)
	background, background_ok, _ := snapshot_hit_test(
		snapshot,
		Hit_Request{root = snapshot.root, row = 23, column = 79},
	)

	testing.expect(t, overlap_ok && background_ok)
	testing.expect_value(t, overlap.surface, hit_test_handle(20, 2))
	testing.expect_value(t, background.kind, Hit_Kind.Background)
	testing.expect_value(t, background.geometry, Cell_Rect{row = 0, column = 0, height = 24, width = 80})
}

@(test)
/* Rejects stale roots and coordinates outside the admitted frontend geometry. */
hit_test_rejects_stale_or_unbounded_requests :: proc(t: ^testing.T) {
	fixture: Hit_Test_Fixture
	snapshot := hit_test_snapshot(&fixture)
	_, stale_ok, stale_failure := snapshot_hit_test(
		snapshot,
		Hit_Request{root = {registry_id = 1, generation = 2}, row = 1, column = 1},
	)
	_, negative_ok, negative_failure := snapshot_hit_test(
		snapshot,
		Hit_Request{root = snapshot.root, row = -1, column = 1},
	)
	_, outside_ok, outside_failure := snapshot_hit_test(
		snapshot,
		Hit_Request{root = snapshot.root, row = 24, column = 1},
	)

	testing.expect(t, !stale_ok && !negative_ok && !outside_ok)
	testing.expect_value(t, stale_failure.operation, Operation.Hit_Test)
	testing.expect_value(t, stale_failure.code, Failure_Code.Stale_Root)
	testing.expect_value(t, negative_failure.code, Failure_Code.Invalid_Hit)
	testing.expect_value(t, outside_failure.code, Failure_Code.Invalid_Hit)
}

@(private)
Hit_Test_Fixture :: struct {
	views:    [2]Visual_View_Descriptor,
	surfaces: [2]Surface_Descriptor,
	statuses: [1]Status_Region_Descriptor,
}

@(private)
hit_test_snapshot :: proc(fixture: ^Hit_Test_Fixture) -> Snapshot_View {
	root := Root_Handle{registry_id = 1, generation = 1}
	bottom_view := hit_test_handle(10, 0)
	top_view := hit_test_handle(11, 1)
	fixture.views = [2]Visual_View_Descriptor {
		{handle = bottom_view, kind = .Text_View},
		{
			handle = top_view,
			kind = .Text_View,
			text = {
				present = true,
				gutter = {present = true, left_cells = 3, right_cells = 2, text_cells = 15},
			},
		},
	}
	bottom_surface := hit_test_handle(19, 1)
	top_surface := hit_test_handle(20, 2)
	fixture.surfaces = [2]Surface_Descriptor {
		{
			handle = bottom_surface,
			view = bottom_view,
			focusable = true,
			visible = true,
			geometry = {row = 0, column = 0, height = 20, width = 40},
		},
		{
			handle = top_surface,
			view = top_view,
			focusable = true,
			visible = true,
			geometry = {row = 2, column = 2, height = 10, width = 20},
			pane = {
				present = true,
				layout_owner_id = 7,
				layout_id = 8,
				layout_generation = 9,
				pane_id = 10,
				pane_slot = 1,
				pane_generation = 2,
				outer = {row = 2, column = 2, height = 12, width = 22},
				content = {row = 2, column = 2, height = 10, width = 20},
				status = {row = 12, column = 2, height = 1, width = 20},
				separator = {row = 13, column = 2, height = 1, width = 20},
			},
		},
	}
	fixture.statuses = [1]Status_Region_Descriptor {{
		handle = hit_test_handle(40, 4),
		surface = top_surface,
		geometry = {row = 12, column = 2, height = 1, width = 20},
	}}
	return Snapshot_View {
		root = root,
		renderer = {id = 1, max_rows = 24, max_columns = 80, max_cells = 1_920},
		views = fixture.views[:],
		surfaces = fixture.surfaces[:],
		status_regions = fixture.statuses[:],
	}
}

@(private)
hit_test_handle :: proc(id: u64, slot: u32) -> Object_Handle {
	return Object_Handle {
		registry_id = 1,
		object_id = Object_ID(id),
		root_generation = 1,
		slot = slot,
		slot_generation = 1,
	}
}
