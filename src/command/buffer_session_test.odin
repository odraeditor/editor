// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../editor"
import "../editor_session"
import "../interaction"
import "core:os"
import "core:testing"

/* Verifies open, reuse, switch, and create publish exact session outcomes. */
@(test)
session_commands_open_reuse_and_create :: proc(t: ^testing.T) {
	directory, directory_error := os.make_directory_temp("", "odra-command-buffers-*", context.allocator)
	testing.expect(t, directory_error == nil)
	if directory_error != nil {
		return
	}
	defer {
		os.remove_all(directory)
		delete(directory)
	}
	first_directory, first_directory_error := os.join_path({directory, "first"}, context.allocator)
	second_directory, second_directory_error := os.join_path({directory, "second"}, context.allocator)
	testing.expect(t, first_directory_error == nil && second_directory_error == nil)
	if first_directory_error != nil || second_directory_error != nil {
		return
	}
	defer delete(first_directory)
	defer delete(second_directory)
	testing.expect(t, os.make_directory(first_directory) == nil)
	testing.expect(t, os.make_directory(second_directory) == nil)
	first_path, first_path_error := os.join_path({first_directory, "same.txt"}, context.allocator)
	second_path, second_path_error := os.join_path({second_directory, "same.txt"}, context.allocator)
	testing.expect(t, first_path_error == nil && second_path_error == nil)
	if first_path_error != nil || second_path_error != nil {
		return
	}
	defer delete(first_path)
	defer delete(second_path)
	testing.expect(t, os.write_entire_file(first_path, "first") == nil)
	testing.expect(t, os.write_entire_file(second_path, "second") == nil)

	session: editor_session.Session
	handle, initialized, _ := editor_session.session_init(
		&session,
		editor_session.Session_ID(701),
		editor_session.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	testing.expect(t, initialized)
	if !initialized {
		return
	}
	command_handle := interaction.Command_Handle {
		registry_generation = interaction.Registry_Generation(1),
		slot = 1,
		entry_generation = 1,
	}
	request := Buffer_Session_Context {
		session = &session,
		handle = handle,
		command = command_handle,
		configuration = editor_session.DEFAULT_ENTRY_CONFIGURATION,
	}
	first, first_ok, _ := buffer_session_find_file(request, first_path)
	second, second_ok, _ := buffer_session_find_file(request, second_path)
	testing.expect(t, first_ok && second_ok)
	testing.expect_value(t, first.completion, Buffer_Session_Completion.Opened)
	testing.expect_value(t, second.completion, Buffer_Session_Completion.Opened)
	testing.expect(t, first.entry != second.entry)

	reused, reused_ok, _ := buffer_session_find_file(request, first_path)
	testing.expect(t, reused_ok)
	testing.expect_value(t, reused.completion, Buffer_Session_Completion.Reused)
	testing.expect_value(t, reused.entry, first.entry)
	visible, visible_ok, _ := editor_session.session_visible_target(&session, handle)
	testing.expect(t, visible_ok)
	testing.expect_value(t, visible.entry, first.entry)

	created, created_ok, _ := buffer_session_switch_to_buffer(request, "λ-notes")
	testing.expect(t, created_ok)
	testing.expect_value(t, created.completion, Buffer_Session_Completion.Created)
	selected, selected_ok, _ := buffer_session_switch_to_buffer(request, second_path)
	testing.expect(t, selected_ok)
	testing.expect_value(t, selected.completion, Buffer_Session_Completion.Activated)
	testing.expect_value(t, selected.entry, second.entry)
	reselected, reselected_ok, _ := buffer_session_switch_to_buffer(request, second_path)
	testing.expect(t, reselected_ok)
	testing.expect_value(t, reselected.completion, Buffer_Session_Completion.Already_Active)

	_, empty_ok, empty_failure := buffer_session_switch_to_buffer(request, "")
	testing.expect(t, !empty_ok)
	testing.expect_value(t, empty_failure.code, Failure_Code.Invalid_Request)

	buffer_session_test_release(t, &session, created.entry)
	buffer_session_test_release(t, &session, second.entry)
	buffer_session_test_release(t, &session, first.entry)
	closed, close_failure := editor_session.session_close(&session)
	testing.expectf(t, closed, "session close failed with %v", close_failure.code)
}

/* Ensures modified files require explicit discard before session removal. */
@(test)
session_kill_requires_discard :: proc(t: ^testing.T) {
	directory, directory_error := os.make_directory_temp("", "odra-command-kill-*", context.allocator)
	testing.expect(t, directory_error == nil)
	if directory_error != nil {
		return
	}
	defer {
		os.remove_all(directory)
		delete(directory)
	}
	path, path_error := os.join_path({directory, "modified.txt"}, context.allocator)
	testing.expect(t, path_error == nil)
	if path_error != nil {
		return
	}
	defer delete(path)
	testing.expect(t, os.write_entire_file(path, "base") == nil)

	session: editor_session.Session
	handle, initialized, _ := editor_session.session_init(
		&session,
		editor_session.Session_ID(702),
		editor_session.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	testing.expect(t, initialized)
	if !initialized {
		return
	}
	command_handle := interaction.Command_Handle {
		registry_generation = interaction.Registry_Generation(1),
		slot = 1,
		entry_generation = 1,
	}
	request := Buffer_Session_Context {
		session = &session,
		handle = handle,
		command = command_handle,
		configuration = editor_session.DEFAULT_ENTRY_CONFIGURATION,
	}
	opened, opened_ok, _ := buffer_session_find_file(request, path)
	testing.expect(t, opened_ok)
	if !opened_ok {
		return
	}
	access, access_ok, _ := editor_session.session_entry_access(&session, opened.entry)
	borrow, borrow_ok, _ := editor_session.entry_access_borrow(access)
	testing.expect(t, access_ok && borrow_ok)
	if !borrow_ok {
		return
	}
	end, end_ok, _ := editor.buffer_position(borrow.buffer, 4)
	_, _, changed, _ := editor.buffer_splice(
		borrow.buffer,
		editor.Splice{start = end, end = end, replacement = "!"},
		context.temp_allocator,
	)
	testing.expect(t, end_ok && changed)
	editor_session.entry_access_reconcile(access)
	assessment, assessed, assess_failure := buffer_session_kill_buffer(request, path)
	testing.expect(t, assessed)
	testing.expect_value(t, assess_failure.code, Failure_Code.None)
	testing.expect_value(t, assessment.completion, Buffer_Kill_Completion.Discard_Required)
	testing.expect_value(t, assessment.closure.association, editor_session.Association_Kind.Document)
	closed, killed, kill_failure := buffer_session_kill_buffer(
		request,
		path,
		.Discard_Modified,
	)
	testing.expect(t, killed)
	testing.expect_value(t, kill_failure.code, Failure_Code.None)
	testing.expect_value(t, closed.completion, Buffer_Kill_Completion.Closed)
	testing.expect(t, closed.closure.last_buffer)
	session_closed, _ := editor_session.session_close(&session)
	testing.expect(t, session_closed)
}

@(private)
buffer_session_test_release :: proc(
	t: ^testing.T,
	session: ^editor_session.Session,
	entry: editor_session.Entry_Handle,
) {
	detached: editor_session.Detached_Entry
	_, detached_ok, detach_failure := editor_session.session_entry_detach(
		session,
		entry,
		&detached,
	)
	testing.expectf(t, detached_ok, "session detach failed with %v", detach_failure.code)
	if !detached_ok {
		return
	}
	_, cleaned, cleanup_failure := editor_session.detached_entry_cleanup(&detached)
	testing.expectf(t, cleaned, "session cleanup failed with %v", cleanup_failure.code)
	if !cleaned {
		return
	}
	released, release_failure := editor_session.detached_entry_release(&detached)
	testing.expectf(t, released, "detached release failed with %v", release_failure.code)
}
