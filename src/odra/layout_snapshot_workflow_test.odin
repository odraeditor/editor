// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../editor_session"
import "../layout"
import "core:os"
import "core:testing"

/* Portable layout snapshots round-trip pane topology, targets, focus, and dedication. */
@(test)
snapshot_round_trips_session_layout :: proc(t: ^testing.T) {
	directory, directory_error := os.make_directory_temp("", "odra-layout-snapshot-*", context.allocator)
	testing.expect(t, directory_error == nil)
	if directory_error != nil do return
	defer {
		os.remove_all(directory)
		delete(directory)
	}
	first_path, first_error := os.join_path({directory, "first.odin"}, context.allocator)
	second_path, second_error := os.join_path({directory, "second.odin"}, context.allocator)
	testing.expect(t, first_error == nil && second_error == nil)
	if first_error != nil || second_error != nil do return
	defer delete(first_path)
	defer delete(second_path)
	testing.expect(t, os.write_entire_file(first_path, "package first\n") == nil)
	testing.expect(t, os.write_entire_file(second_path, "package second\n") == nil)

	session: editor_session.Session
	handle, initialized, _ := editor_session.session_init(
		&session,
		editor_session.Session_ID(9_401),
		editor_session.Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, initialized)
	if !initialized do return
	first, first_ok, _ := editor_session.session_open_path(
		&session,
		editor_session.Open_Path_Request {
			session = handle,
			path = first_path,
			encoding = .UTF8,
			configuration = editor_session.DEFAULT_ENTRY_CONFIGURATION,
		},
	)
	second, second_ok, _ := editor_session.session_open_path(
		&session,
		editor_session.Open_Path_Request {
			session = handle,
			path = second_path,
			encoding = .UTF8,
			configuration = editor_session.DEFAULT_ENTRY_CONFIGURATION,
		},
	)
	testing.expect(t, first_ok && second_ok)
	if !first_ok || !second_ok {
		editor_session.session_close(&session)
		return
	}
	_, activated, _ := editor_session.session_activate(&session, first.entry)
	testing.expect(t, activated)
	access, accessible, _ := editor_session.session_entry_access(&session, first.entry)
	entry, borrowed, _ := editor_session.entry_access_borrow(access)
	testing.expect(t, accessible && borrowed)
	if !accessible || !borrowed do return
	commands := Command_Context {
		session_owner = &session,
		session_handle = handle,
		entry_configuration = editor_session.DEFAULT_ENTRY_CONFIGURATION,
		persistent_allocator = context.allocator,
		layout_entry = first.entry,
	}
	layout_ok, _ := layout.registry_init(
		&commands.layout_registry,
		layout.Owner_ID(9_401),
		layout.Layout_ID(9_401),
		entry.view_registry,
		entry.primary_view,
		layout.Geometry_Request{rows = 20, columns = 80, global_reserved_rows = 1},
		layout.DEFAULT_POLICY,
		context.allocator,
		first.entry,
	)
	testing.expect(t, layout_ok)
	if !layout_ok do return
	defer {
		command_context_layout_close(&commands)
		_, _, _ = editor_session.session_close_buffer(
			&session, editor_session.Close_Buffer_Request{entry = second.entry, authority = .Discard_Modified},
		)
		_, _, _ = editor_session.session_close_buffer(
			&session, editor_session.Close_Buffer_Request{entry = first.entry, authority = .Discard_Modified},
		)
		editor_session.session_close(&session)
	}
	layout_handle, _, _ := layout.registry_handle(&commands.layout_registry)
	initial, _, _ := layout.registry_snapshot(&commands.layout_registry, layout_handle)
	split, split_ok, _ := layout.registry_split_right(&commands.layout_registry, initial.active_pane)
	testing.expect(t, split_ok)
	if !split_ok do return
	replaced, replaced_ok, _ := layout.registry_replace_pane_buffer(
		&commands.layout_registry, split.created, &session, second.entry,
	)
	testing.expect(t, replaced_ok)
	if !replaced_ok do return
	soft, soft_ok, _ := layout.registry_pane_dedication_set(
		&commands.layout_registry, replaced.pane, .Soft,
	)
	testing.expect(t, soft_ok)
	if !soft_ok do return
	_, focused, _ := layout.registry_focus(&commands.layout_registry, soft.pane)
	testing.expect(t, focused)
	if !focused do return
	commands.layout_entry = second.entry

	encoded, encoded_ok := command_context_layout_snapshot_encode(&commands)
	testing.expect(t, encoded_ok)
	if !encoded_ok do return
	defer delete(encoded, context.allocator)
	restored, complete := command_context_layout_snapshot_restore(&commands, encoded)
	testing.expect(t, restored && complete)
	final_handle, _, _ := layout.registry_handle(&commands.layout_registry)
	final, final_ok, _ := layout.registry_snapshot(&commands.layout_registry, final_handle)
	testing.expect(t, final_ok)
	testing.expect_value(t, final.pane_count, u16(2))
	testing.expect_value(t, final.nodes[0].arrangement, layout.Arrangement.Left_Right)
	active, active_ok := command_context_layout_active_node(&final)
	testing.expect(t, active_ok)
	if active_ok {
		testing.expect_value(t, active.entry, second.entry)
		testing.expect_value(t, active.dedication, layout.Pane_Dedication.Soft)
	}
}
