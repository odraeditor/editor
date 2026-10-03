// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../command"
import "../editor"
import "../editor_session"
import editor_view "../view"
import "core:testing"

/* Region slots copy the exact active UTF-8 range and reject inactive or empty regions. */
@(test)
region_text_requires_active_region :: proc(t: ^testing.T) {
	buffer: editor.Buffer
	initialized, _ := editor.buffer_init(
		&buffer,
		editor.Buffer_ID(9_301),
		"zero żółć λ end",
		editor.Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, initialized)
	if !initialized do return
	defer editor.buffer_close(&buffer)

	_, inactive := named_slot_region_text(&buffer, context.allocator)
	testing.expect(t, !inactive)
	start, _, _ := editor.buffer_position(&buffer, editor.Byte_Offset(5))
	end, _, _ := editor.buffer_position(&buffer, editor.Byte_Offset(16))
	marked, _ := editor.buffer_selection_set_mark(&buffer, start, true)
	moved, _ := editor.buffer_selection_move(&buffer, end, .Preserve)
	testing.expect(t, marked && moved)
	text, copied := named_slot_region_text(&buffer, context.allocator)
	testing.expect(t, copied)
	if copied {
		testing.expect_value(t, text, "żółć λ")
		delete(text, context.allocator)
	}
}

/* Named slot prompts identify the value type instead of relying on an unqualified slot name. */
@(test)
named_slot_operation_labels_identify_value_type :: proc(t: ^testing.T) {
	testing.expect_value(t, named_slot_operation_type_label(.Store_Number), "Integer")
	testing.expect_value(t, named_slot_operation_type_label(.Store_Text), "Text")
	testing.expect_value(t, named_slot_operation_type_label(.Store_Position), "Position")
	testing.expect_value(t, named_slot_operation_type_label(.Store_Layout), "Layout")
}

/* Candidate previews are bounded, single-line summaries of already loaded slot values. */
@(test)
slot_previews_summarize_values :: proc(t: ^testing.T) {
	text_storage: [NAMED_SLOT_CANDIDATE_PREVIEW_BYTES]u8
	text_preview := named_slot_candidate_preview(
		command.Named_Slot_Descriptor{kind = .Text, text = "  make_task(\"Review\")\nnext line  "},
		text_storage[:],
	)
	testing.expect_value(t, text_preview, "make_task(\"Review\") next line")

	integer_storage: [NAMED_SLOT_CANDIDATE_PREVIEW_BYTES]u8
	integer_preview := named_slot_candidate_preview(
		command.Named_Slot_Descriptor{kind = .Integer, integer = -42},
		integer_storage[:],
	)
	testing.expect_value(t, integer_preview, "-42")

	position_storage: [NAMED_SLOT_CANDIDATE_PREVIEW_BYTES]u8
	position_preview := named_slot_candidate_preview(
		command.Named_Slot_Descriptor{kind = .Position, target = "/tmp/main.odin", point = 18},
		position_storage[:],
	)
	testing.expect_value(t, position_preview, "main.odin @ byte 18")

	layout_storage: [NAMED_SLOT_CANDIDATE_PREVIEW_BYTES]u8
	layout_preview := named_slot_candidate_preview(
		command.Named_Slot_Descriptor{kind = .Layout, text = "opaque layout"},
		layout_storage[:],
	)
	testing.expect_value(t, layout_preview, "")
}

/* A successful region store deactivates the region without releasing mark. */
@(test)
region_store_deactivates_selection :: proc(t: ^testing.T) {
	session: editor_session.Session
	handle, initialized, _ := editor_session.session_init(
		&session,
		editor_session.Session_ID(9_501),
		editor_session.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	testing.expect(t, initialized)
	if !initialized do return
	created, created_ok, _ := editor_session.session_create_buffer(
		&session,
		editor_session.Create_Buffer_Request {
			session = handle,
			name = "stored-region",
			configuration = editor_session.DEFAULT_ENTRY_CONFIGURATION,
		},
	)
	testing.expect(t, created_ok)
	if !created_ok {
		editor_session.session_close(&session)
		return
	}
	defer {
		_, _, _ = editor_session.session_close_buffer(
			&session,
			editor_session.Close_Buffer_Request {
				entry = created.entry,
				authority = .Discard_Modified,
			},
		)
		editor_session.session_close(&session)
	}
	access, accessible, _ := editor_session.session_entry_access(&session, created.entry)
	entry, borrowed, _ := editor_session.entry_access_borrow(access)
	testing.expect(t, accessible && borrowed)
	if !accessible || !borrowed do return
	start, start_ok, _ := editor.buffer_position(entry.buffer, 0)
	end, end_ok, _ := editor.buffer_position(entry.buffer, 0)
	testing.expect(t, start_ok && end_ok)
	if !start_ok || !end_ok do return
	marked, _ := editor_view.set_mark(entry.view_registry, entry.primary_view, start, true)
	moved, _ := editor_view.set_point(entry.view_registry, entry.primary_view, end)
	testing.expect(t, marked && moved)
	commands := Command_Context{session_owner = &session}
	state := Named_Slot_Workflow_State {
		operation = .Store_Region_Text,
		region_entry = created.entry,
		region_view = entry.primary_view,
	}
	testing.expect(t, command_context_deactivate_stored_region(&commands, &state))
	selection, selected, _ := editor.buffer_selection_snapshot(entry.buffer)
	testing.expect(t, selected)
	if selected {
		testing.expect(t, selection.mark.present)
		testing.expect(t, !selection.region_active)
	}
}
