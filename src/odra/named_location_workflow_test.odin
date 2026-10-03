// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../editor"
import "../editor_session"
import "core:os"
import "core:testing"

/* Named location targets must remain regular files at visit time. */
@(test)
named_location_visit_rejects_missing_targets :: proc(t: ^testing.T) {
	directory, directory_error := os.make_directory_temp(
		"",
		"odra-named-location-target-*",
		context.allocator,
	)
	testing.expect(t, directory_error == nil)
	if directory_error != nil do return
	defer {
		os.remove_all(directory)
		delete(directory)
	}
	missing, path_error := os.join_path({directory, "missing.odin"}, context.allocator)
	testing.expect(t, path_error == nil)
	if path_error != nil do return
	defer delete(missing)
	testing.expect(t, !named_location_target_is_available(missing))
}

/* Stale anchors are rejected without changing the current buffer selection. */
@(test)
named_location_visit_rejects_stale_anchors :: proc(t: ^testing.T) {
	session: editor_session.Session
	handle, initialized, _ := editor_session.session_init(
		&session,
		editor_session.Session_ID(9_201),
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
			name = "named-location-anchor",
			configuration = editor_session.DEFAULT_ENTRY_CONFIGURATION,
		},
	)
	testing.expect(t, created_ok)
	if !created_ok do return
	defer {
		detached: editor_session.Detached_Entry
		_, detached_ok, _ := editor_session.session_entry_detach(&session, created.entry, &detached)
		testing.expect(t, detached_ok)
		if detached_ok {
			_, cleaned, _ := editor_session.detached_entry_cleanup(&detached)
			testing.expect(t, cleaned)
			if cleaned {
				released, _ := editor_session.detached_entry_release(&detached)
				testing.expect(t, released)
			}
		}
		closed, _ := editor_session.session_close(&session)
		testing.expect(t, closed)
	}
	commands := Command_Context {
		session_owner = &session,
		session_handle = handle,
	}
	before_access, before_accessible, _ := editor_session.session_entry_access(&session, created.entry)
	before_entry, before_borrowed, _ := editor_session.entry_access_borrow(before_access)
	testing.expect(t, before_accessible && before_borrowed)
	if !before_accessible || !before_borrowed do return
	before, before_ok, _ := editor.buffer_selection_snapshot(before_entry.buffer)
	testing.expect(t, before_ok)
	testing.expect(
		t,
		!command_context_restore_named_location(&commands, created.entry, 1, 0, false, false),
	)
	after, after_ok, _ := editor.buffer_selection_snapshot(before_entry.buffer)
	testing.expect(t, after_ok)
	testing.expect_value(t, after.point_position, before.point_position)
	testing.expect_value(t, after.mark, before.mark)
	testing.expect_value(t, after.region_active, before.region_active)
}

/* Closing named-location navigation restores the entry that owned the interaction. */
@(test)
location_cancel_restores_return_entry :: proc(t: ^testing.T) {
	session: editor_session.Session
	handle, initialized, _ := editor_session.session_init(
		&session,
		editor_session.Session_ID(9_202),
		editor_session.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	testing.expect(t, initialized)
	if !initialized do return
	first, first_ok, _ := editor_session.session_create_buffer(
		&session,
		editor_session.Create_Buffer_Request {
			session = handle,
			name = "first",
			configuration = editor_session.DEFAULT_ENTRY_CONFIGURATION,
		},
	)
	second, second_ok, _ := editor_session.session_create_buffer(
		&session,
		editor_session.Create_Buffer_Request {
			session = handle,
			name = "second",
			configuration = editor_session.DEFAULT_ENTRY_CONFIGURATION,
		},
	)
	testing.expect(t, first_ok && second_ok)
	if !first_ok || !second_ok do return
	entries := [2]editor_session.Entry_Handle{first.entry, second.entry}
	defer {
		for entry in entries {
			detached: editor_session.Detached_Entry
			_, detached_ok, _ := editor_session.session_entry_detach(&session, entry, &detached)
			testing.expect(t, detached_ok)
			if detached_ok {
				_, cleaned, _ := editor_session.detached_entry_cleanup(&detached)
				testing.expect(t, cleaned)
				if cleaned {
					released, _ := editor_session.detached_entry_release(&detached)
					testing.expect(t, released)
				}
			}
		}
		closed, _ := editor_session.session_close(&session)
		testing.expect(t, closed)
	}
	_, activated, _ := editor_session.session_activate(&session, second.entry)
	testing.expect(t, activated)
	commands := Command_Context {
		session_owner = &session,
		session_handle = handle,
		candidate_ui = {return_target = {kind = .Primary_View, entry = first.entry}},
	}
	result, failure := command_context_leave_named_locations(&commands)
	testing.expect(t, result.changed && failure.stage == .None)
	visible, visible_ok, _ := editor_session.session_visible_target(&session, handle)
	testing.expect(t, visible_ok)
	testing.expect_value(t, visible.entry, first.entry)
}
