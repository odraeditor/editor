// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ui

import "../editor"
import editor_view "../view"
import "core:testing"

@(test)
/* Text Gutter projection copies bounded rows without changing the source TextView. */
projection_copies_rows_transactionally :: proc(t: ^testing.T) {
	buffer: editor.Buffer
	buffer_ok, _ := editor.buffer_init(
		&buffer,
		901,
		"alpha\nbeta",
		editor.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	if !buffer_ok {
		testing.expect(t, false)
		return
	}
	defer editor.buffer_close(&buffer)
	views: editor_view.Registry
	views_ok, _ := editor_view.registry_init(&views, 901, context.allocator)
	if !views_ok {
		testing.expect(t, false)
		return
	}
	defer editor_view.registry_close(&views)
	handle, view_ok, _ := editor_view.create(&views, &buffer)
	if !view_ok {
		testing.expect(t, false)
		return
	}
	defer editor_view.close(&views, &handle)

	registry: Registry
	registry_ok, _ := registry_init(&registry, 901)
	if !registry_ok {
		testing.expect(t, false)
		return
	}
	defer registry_close(&registry)
	proposal, proposal_ok, _ := proposal_begin(&registry)
	if !proposal_ok {
		testing.expect(t, false)
		return
	}
	defer proposal_abort(&proposal)
	_, text_style, _ := proposal_add_style(&proposal, .Text_Normal)
	_, background_style, _ := proposal_add_style(&proposal, .Gutter_Background)
	_, number_style, _ := proposal_add_style(&proposal, .Gutter_Line_Number, {.Dim})
	_, current_style, _ := proposal_add_style(&proposal, .Gutter_Line_Number_Current, {.Bold})
	_, separator_style, _ := proposal_add_style(&proposal, .Gutter_Separator, {.Dim})
	text_view, projected, _ := proposal_project_editor_text_view(
		&proposal, &views, handle, &buffer, 901)
	invalid_rows := [1]Text_Gutter_Row_Definition {{
		viewport_row = 1,
		left_text = " 1 │",
		left_cells = 4,
		left_separator_bytes = 3,
		left_style_role = .Gutter_Line_Number,
	}}
	accounting_before := proposal_state(&proposal).accounting
	invalid_ok, invalid_failure := proposal_project_text_gutter(
		&proposal, text_view, 1, 4, 0, 8, invalid_rows[:])
	accounting_after_invalid := proposal_state(&proposal).accounting
	rows := [2]Text_Gutter_Row_Definition {
		{viewport_row = 0, logical_line = 0, left_text = " 1 │", left_cells = 4,
			left_separator_bytes = 3, left_style_role = .Gutter_Line_Number_Current,
			current = true},
		{viewport_row = 1, logical_line = 1, left_text = " 2 │", left_cells = 4,
			left_separator_bytes = 3, left_style_role = .Gutter_Line_Number},
	}
	gutter_ok, gutter_failure := proposal_project_text_gutter(
		&proposal, text_view, 1, 4, 0, 8, rows[:])
	state := proposal_state(&proposal)
	view, resolved := resolve_view(state, text_view)

	testing.expect(t, text_style && background_style && number_style && current_style &&
		separator_style && projected)
	testing.expect(t, !invalid_ok)
	testing.expect_value(t, invalid_failure.code, Failure_Code.Invalid_Text_View)
	testing.expect_value(t, accounting_after_invalid, accounting_before)
	testing.expectf(t, gutter_ok, "Gutter projection failed with %v", gutter_failure.code)
	testing.expect(t, resolved && view.text.gutter.present)
	if resolved && view.text.gutter.present {
		testing.expect_value(t, view.text.source_text_bytes, u64(len("alpha\nbeta")))
		testing.expect_value(t, view.text.gutter.left_cells, u16(4))
		testing.expect_value(t, view.text.gutter.text_cells, u32(8))
		testing.expect_value(t, view.text.gutter.row_count, u8(2))
		first := view.text.gutter.rows[0]
		text := string(state.compact_content[first.left_offset:first.left_offset + u32(first.left_bytes)])
		testing.expect_value(t, text, " 1 │")
		testing.expect(t, first.current)
	}
}
