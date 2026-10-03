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

/* Verifies marked saves report truthful completion before a later save failure. */
@(test)
marked_saves_keep_external_effects :: proc(t: ^testing.T) {
	directory, directory_error := os.make_directory_temp("", "odra-marked-save-*", context.allocator)
	testing.expect(t, directory_error == nil)
	if directory_error != nil {
		return
	}
	defer {
		os.remove_all(directory)
		delete(directory)
	}
	first_path, _ := os.join_path({directory, "first.txt"}, context.allocator)
	missing_path, _ := os.join_path({directory, "missing", "second.txt"}, context.allocator)
	defer delete(first_path)
	defer delete(missing_path)

	session: editor_session.Session
	handle, initialized, _ := marked_test_session_init(&session, 731)
	testing.expect(t, initialized)
	if !initialized {
		return
	}
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
	marked_test_modify(t, &session, first.entry, "one")
	marked_test_modify(t, &session, second.entry, "two")
	_, activated, _ := editor_session.session_activate(&session, first.entry)
	testing.expect(t, activated)

	marks := []Buffer_Marked_Entry {
		{entry = first.entry, kind = .Save},
		{entry = second.entry, kind = .Save},
	}
	request := marked_test_execution_context(
		&session,
		handle,
		[]Marked_Entry_Decision {
			{entry = second.entry, kind = .Save, path = missing_path},
			{entry = first.entry, kind = .Save, path = first_path},
		},
	)
	result, executed, failure := buffer_session_execute_buffer_marks(request, marks)
	testing.expect(t, !executed)
	testing.expect(t, failure.code != .None)
	testing.expect_value(t, result.outcome, Marked_Execution_Outcome.Failed)
	testing.expect_value(t, result.completed_saves, u32(1))
	testing.expect_value(t, result.pending_saves, u32(1))
	first_bytes, first_error := os.read_entire_file(first_path, context.allocator)
	testing.expect(t, first_error == nil)
	if first_error == nil {
		testing.expect_value(t, string(first_bytes), "one")
		delete(first_bytes)
	}
	usage, usage_ok, _ := editor_session.session_usage(&session, handle)
	testing.expect(t, usage_ok)
	testing.expect_value(t, usage.live_buffers, u32(2))
	marked_test_release(t, &session, second.entry, .Discard_Modified)
	marked_test_release(t, &session, first.entry, .Preserve_Modified)
	closed, _ := editor_session.session_close(&session)
	testing.expect(t, closed)
}

/* Verifies every dirty kill decision is resolved before any marked buffer closes. */
@(test)
marked_kills_form_one_set :: proc(t: ^testing.T) {
	session: editor_session.Session
	handle, initialized, _ := marked_test_session_init(&session, 733)
	testing.expect(t, initialized)
	if !initialized {
		return
	}
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
	marked_test_modify(t, &session, first.entry, "one")
	marked_test_modify(t, &session, second.entry, "two")

	marks := []Buffer_Marked_Entry {
		{entry = first.entry, kind = .Kill},
		{entry = second.entry, kind = .Kill},
	}
	incomplete := marked_test_execution_context(
		&session,
		handle,
		[]Marked_Entry_Decision{{entry = second.entry, kind = .Discard}},
	)
	pending, admitted, pending_failure := buffer_session_execute_buffer_marks(incomplete, marks)
	testing.expect(t, admitted)
	testing.expect_value(t, pending_failure.code, Failure_Code.None)
	testing.expect_value(t, pending.outcome, Marked_Execution_Outcome.Decision_Required)
	testing.expect_value(t, pending.completed_kills, u32(0))
	usage, usage_ok, _ := editor_session.session_usage(&session, handle)
	testing.expect(t, usage_ok)
	testing.expect_value(t, usage.live_buffers, u32(2))

	complete := marked_test_execution_context(
		&session,
		handle,
		[]Marked_Entry_Decision {
			{entry = second.entry, kind = .Discard},
			{entry = first.entry, kind = .Discard},
		},
	)
	completed, executed, execute_failure := buffer_session_execute_buffer_marks(complete, marks)
	testing.expectf(t, executed, "marked kill failed with %v", execute_failure.code)
	testing.expect_value(t, completed.outcome, Marked_Execution_Outcome.Completed)
	testing.expect_value(t, completed.completed_kills, u32(2))
	testing.expect_value(t, completed.pending_kills, u32(0))
	usage, usage_ok, _ = editor_session.session_usage(&session, handle)
	testing.expect(t, usage_ok)
	testing.expect_value(t, usage.live_buffers, u32(0))
	closed, _ := editor_session.session_close(&session)
	testing.expect(t, closed)
}

@(private)
marked_test_session_init :: proc(
	session: ^editor_session.Session,
	id: u64,
) -> (editor_session.Session_Handle, bool, editor_session.Failure_Context) {
	return editor_session.session_init(
		session,
		editor_session.Session_ID(id),
		editor_session.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
}

@(private)
marked_test_modify :: proc(
	t: ^testing.T,
	session: ^editor_session.Session,
	entry: editor_session.Entry_Handle,
	text: string,
) {
	access, access_ok, _ := editor_session.session_entry_access(session, entry)
	borrow, borrow_ok, _ := editor_session.entry_access_borrow(access)
	testing.expect(t, access_ok && borrow_ok)
	if !borrow_ok {
		return
	}
	position, positioned, _ := editor.buffer_position(borrow.buffer, 0)
	_, _, changed, _ := editor.buffer_splice(
		borrow.buffer,
		editor.Splice{start = position, end = position, replacement = text},
		context.temp_allocator,
	)
	testing.expect(t, positioned && changed)
	_, reconciled, _ := editor_session.entry_access_reconcile(access)
	testing.expect(t, reconciled)
}

@(private)
marked_test_execution_context :: proc(
	session: ^editor_session.Session,
	handle: editor_session.Session_Handle,
	decisions: []Marked_Entry_Decision,
) -> Buffer_Marked_Execution_Context {
	return Buffer_Marked_Execution_Context {
		buffer_session = Buffer_Session_Context {
			session = session,
			handle = handle,
			command = interaction.Command_Handle {
				registry_generation = 1,
				slot = 1,
				entry_generation = 1,
			},
			configuration = editor_session.DEFAULT_ENTRY_CONFIGURATION,
		},
		decisions = decisions,
	}
}

@(private)
marked_test_release :: proc(
	t: ^testing.T,
	session: ^editor_session.Session,
	entry: editor_session.Entry_Handle,
	authority: editor_session.Close_Authority,
) {
	result, closed, failure := editor_session.session_close_buffer(
		session,
		editor_session.Close_Buffer_Request{entry = entry, authority = authority},
	)
	testing.expectf(t, closed && result.outcome == .Closed, "cleanup failed with %v", failure.code)
}
