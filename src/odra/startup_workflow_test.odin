// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../display"
import "../editor_session"
import "../ui"
import "core:strings"
import "core:testing"

/* Verifies startup list state, actions, clipping, and checked session identity. */
@(test)
startup_list_owns_navigation_and_actions :: proc(t: ^testing.T) {
	state: Startup_Workflow_State
	prepared, prepare_failure := startup_workflow_prepare(&state, 2)
	testing.expectf(t, prepared, "startup prepare failed with %v", prepare_failure.code)
	if !prepared do return
	testing.expect_value(t, state.position.selection_owner, ui.Selection_Owner.View)
	testing.expect_value(t, state.position.current_item, i32(8))
	testing.expect_value(t, state.position.first_visible_item, u32(7))

	action_text: [STARTUP_ACTION_COUNT][STARTUP_ACTION_TEXT_CAPACITY]u8
	profile := display.unicode17_profile()
	items, items_ok := startup_list_items(&action_text, profile)
	testing.expect(t, items_ok)
	if !items_ok do return
	expected_art := [STARTUP_ART_ROWS]string {
		" ██████╗ ██████╗ ██████╗  █████╗",
		"██╔═══██╗██╔══██╗██╔══██╗██╔══██╗",
		"██║◈☼◈██║██║☼◈██║██████╔╝███████║",
		"██║☼◆☼██║██║◈☼██║██╔══██╗██╔══██║",
		"██║◈☼◈██║██║☼◈██║██║  ██║██║◈☼██║",
		"╚██████╔╝██████╔╝██║  ██║██║  ██║",
		" ╚═════╝ ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝",
	}
	for expected, index in expected_art {
		testing.expect_value(t, items[index].text, expected)
		testing.expect(t, items[index].passive)
	}
	testing.expect(t, items[7].passive)
	testing.expect(t, strings.contains(items[8].text, "Create a new buffer"))
	testing.expect(t, strings.contains(items[9].text, "Open File"))
	testing.expect(t, !strings.contains(items[9].text, "local file"))
	testing.expect_value(t, items[9].action.action_id, STARTUP_OPEN_PATH_ACTION)
	testing.expect_value(t, items[10].action.action_id, STARTUP_OPEN_PROJECT_DIRECTORY_ACTION)
	testing.expect_value(t, items[11].action.action_id, STARTUP_OPEN_PROJECT_ACTION)
	testing.expect_value(t, items[12].action.action_id, STARTUP_OPEN_WORKSPACE_ACTION)
	inset, inset_ok := startup_action_block_inset(profile)
	testing.expect(t, inset_ok)
	testing.expect_value(t, inset, u32(7))
	for item_index in STARTUP_ACTION_ROW_OFFSET ..< STARTUP_LIST_ITEM_COUNT {
		text := items[item_index].text
		testing.expect(t, len(text) > int(inset))
		for column in 0 ..< int(inset) {
			testing.expect_value(t, text[column], u8(' '))
		}
		testing.expect(t, text[int(inset)] != ' ')
	}

	changed, moved, move_failure := startup_workflow_move(&state, 4)
	testing.expectf(t, moved, "startup move failed with %v", move_failure.code)
	testing.expect(t, changed)
	testing.expect_value(t, state.position.current_item, i32(12))
	testing.expect_value(t, state.position.first_visible_item, u32(11))
	action, action_ok := startup_workflow_current_action(&state)
	testing.expect(t, action_ok)
	testing.expect_value(t, action, STARTUP_OPEN_WORKSPACE_ACTION)

	resized, resize_failure := startup_workflow_prepare(&state, 1)
	testing.expectf(t, resized, "startup resize failed with %v", resize_failure.code)
	testing.expect_value(t, state.position.first_visible_item, u32(12))
	resized, resize_failure = startup_workflow_prepare(&state, 13)
	testing.expectf(t, resized, "startup expansion failed with %v", resize_failure.code)
	testing.expect_value(t, state.position.first_visible_item, u32(0))
	geometry := startup_surface_geometry(
		{width_cells = 80, height_rows = 24},
		24,
	)
	testing.expect_value(t, geometry.row, i32(5))
	testing.expect_value(t, geometry.column, i32(23))
	testing.expect_value(t, geometry.height, i32(13))
	testing.expect_value(t, geometry.width, i32(33))
	clipped := startup_surface_geometry(
		{width_cells = 20, height_rows = 6},
		6,
	)
	testing.expect_value(t, clipped, ui.Cell_Rect{height = 6, width = 20})
	target := startup_visible_target()
	testing.expect(t, editor_session.visible_target_is_valid(target))
	testing.expect_value(t, target.kind, editor_session.Visible_Target_Kind.UI_Root)
}

/* Verifies a pathless session can atomically select the startup UI target. */
@(test)
startup_ui_target_requires_no_buffer_graph :: proc(t: ^testing.T) {
	session: editor_session.Session
	handle, initialized, init_failure := editor_session.session_init(
		&session,
		editor_session.Session_ID(10_001),
		editor_session.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	testing.expectf(t, initialized, "session init failed with %v", init_failure.code)
	if !initialized do return
	defer editor_session.session_close(&session)
	target := startup_visible_target()
	_, visible, presented, present_failure := editor_session.session_present_ui(
		&session,
		handle,
		target.ui,
	)
	testing.expectf(t, presented, "startup presentation failed with %v", present_failure.code)
	testing.expect_value(t, visible, target)
	usage, usage_ok, usage_failure := editor_session.session_usage(&session, handle)
	testing.expectf(t, usage_ok, "session usage failed with %v", usage_failure.code)
	testing.expect_value(t, usage.live_buffers, u32(0))
	testing.expect_value(t, usage.live_documents, u32(0))
}
