// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package editor_session

import "../editor"
import "core:testing"

/* Verifies terminal-backed entries retain identity, source metadata, and copied text. */
@(test)
terminal_buffer_admission_is_inspectable_and_read_only :: proc(t: ^testing.T) {
	session: Session
	handle, initialized, _ := session_init(&session, Session_ID(951), test_session_allocators())
	testing.expect(t, initialized)
	if !initialized do return
	terminal_ref := Terminal_Session_Ref{id = 7, generation = 3}
	created, created_ok, create_failure := session_create_terminal_buffer(
		&session,
		Create_Terminal_Buffer_Request {
			session = handle,
			name = "terminal",
			terminal = Terminal_Buffer_Source {
				ref = terminal_ref,
				lifecycle = .Running,
				working_context = "/workspace/project",
			},
			copied_projection = "prompt> ready",
			configuration = DEFAULT_ENTRY_CONFIGURATION,
		},
	)
	testing.expectf(t, created_ok, "terminal admission failed with %v", create_failure.code)
	if !created_ok {
		session_close(&session)
		return
	}
	state, inspected, state_failure := session_terminal_buffer_state(&session, created.entry)
	testing.expectf(t, inspected, "terminal inspection failed with %v", state_failure.code)
	testing.expect_value(t, state.terminal, terminal_ref)
	testing.expect_value(t, state.lifecycle, Terminal_Lifecycle.Running)
	testing.expect_value(t, terminal_working_context_text(&state.working_context), "/workspace/project")
	access, access_ok, _ := session_entry_access(&session, created.entry)
	borrow, borrowed, _ := entry_access_borrow(access)
	testing.expect(t, access_ok && borrowed)
	if borrowed {
		testing.expect_value(t, borrow.kind, Entry_Kind.Terminal)
		stats, stats_ok, _ := editor.buffer_stats(borrow.buffer)
		testing.expect(t, stats_ok)
		testing.expect_value(t, stats.kind, editor.Buffer_Kind.Terminal_Projection)
		start, _, _ := editor.buffer_position(borrow.buffer, 0)
		end, _, _ := editor.buffer_position(borrow.buffer, editor.Byte_Offset(stats.text_bytes))
		_, _, changed, splice_failure := editor.buffer_splice(
			borrow.buffer,
			editor.Splice {start = start, end = end, replacement = "mutated"},
			context.temp_allocator,
		)
		testing.expect(t, !changed)
		testing.expect_value(t, splice_failure.code, editor.Failure_Code.Read_Only_Buffer)
	}
	_, saved, save_failure := session_associate_and_save(
		&session,
		Associate_Save_Request {entry = created.entry, path = "/tmp/terminal.txt"},
	)
	testing.expect(t, !saved)
	testing.expect_value(t, save_failure.code, Failure_Code.Invalid_Terminal)
	_, closed, close_failure := session_close_buffer(
		&session,
		Close_Buffer_Request {entry = created.entry, authority = .Discard_Modified},
	)
	testing.expect(t, !closed)
	testing.expect_value(t, close_failure.code, Failure_Code.Terminal_Coordination_Required)

	test_detach_release(t, &session, created.entry)
	session_closed, _ := session_close(&session)
	testing.expect(t, session_closed)
}

/* Verifies final output and exit state survive refresh while stale sources are rejected. */
@(test)
terminal_buffer_refresh_retains_exited_projection :: proc(t: ^testing.T) {
	session: Session
	handle, initialized, _ := session_init(&session, Session_ID(952), test_session_allocators())
	testing.expect(t, initialized)
	if !initialized do return
	terminal_ref := Terminal_Session_Ref{id = 8, generation = 11}
	created, created_ok, _ := session_create_terminal_buffer(
		&session,
		Create_Terminal_Buffer_Request {
			session = handle,
			name = "terminal-2",
			terminal = Terminal_Buffer_Source {
				ref = terminal_ref,
				lifecycle = .Running,
				working_context = "/workspace",
			},
			copied_projection = "running",
			configuration = DEFAULT_ENTRY_CONFIGURATION,
		},
	)
	testing.expect(t, created_ok)
	if !created_ok {
		session_close(&session)
		return
	}
	state, refreshed, refresh_failure := session_refresh_terminal_buffer(
		&session,
		Terminal_Buffer_Update_Request {
			entry = created.entry,
			terminal = terminal_ref,
			lifecycle = .Exited,
			copied_projection = "complete\nexit 0",
		},
	)
	testing.expectf(t, refreshed, "terminal refresh failed with %v", refresh_failure.code)
	testing.expect_value(t, state.lifecycle, Terminal_Lifecycle.Exited)
	testing.expect_value(t, state.projection_revision, editor.Revision(1))
	_, stale_ok, stale_failure := session_refresh_terminal_buffer(
		&session,
		Terminal_Buffer_Update_Request {
			entry = created.entry,
			terminal = Terminal_Session_Ref{id = 8, generation = 10},
			lifecycle = .Exited,
			copied_projection = "stale",
		},
	)
	testing.expect(t, !stale_ok)
	testing.expect_value(t, stale_failure.code, Failure_Code.Stale_Terminal)
	_, restarted, restart_failure := session_refresh_terminal_buffer(
		&session,
		Terminal_Buffer_Update_Request {
			entry = created.entry,
			terminal = terminal_ref,
			lifecycle = .Running,
			copied_projection = "restarted",
		},
	)
	testing.expect(t, !restarted)
	testing.expect_value(t, restart_failure.code, Failure_Code.Invalid_Terminal_Transition)
	access, access_ok, _ := session_entry_access(&session, created.entry)
	borrow, borrowed, _ := entry_access_borrow(access)
	testing.expect(t, access_ok && borrowed)
	if borrowed {
		stats, stats_ok, _ := editor.buffer_stats(borrow.buffer)
		testing.expect(t, stats_ok)
		bytes: [64]byte
		copied, copied_ok, _ := editor.buffer_inspect(
			borrow.buffer,
			0,
			editor.Byte_Offset(stats.text_bytes),
			bytes[:],
		)
		testing.expect(t, copied_ok)
		testing.expect_value(t, string(bytes[:int(copied)]), "complete\nexit 0")
	}
	descriptors, described, _ := session_descriptors(&session, handle)
	testing.expect(t, described)
	if described {
		testing.expect_value(t, len(descriptors.descriptors), 1)
		testing.expect(t, !descriptors.descriptors[0].modified)
		testing.expect_value(t, descriptors.descriptors[0].terminal.lifecycle, Terminal_Lifecycle.Exited)
		descriptor_batch_close(&descriptors)
	}
	test_detach_release(t, &session, created.entry)
	session_closed, _ := session_close(&session)
	testing.expect(t, session_closed)
}

/* Verifies terminal names remain checked, unique, and stable across explicit rename. */
@(test)
terminal_buffer_rename_preserves_source_identity :: proc(t: ^testing.T) {
	session: Session
	handle, initialized, _ := session_init(&session, Session_ID(953), test_session_allocators())
	testing.expect(t, initialized)
	if !initialized do return
	terminal_ref := Terminal_Session_Ref{id = 9, generation = 1}
	created, created_ok, _ := session_create_terminal_buffer(
		&session,
		Create_Terminal_Buffer_Request {
			session = handle,
			name = "terminal",
			terminal = Terminal_Buffer_Source {
				ref = terminal_ref,
				lifecycle = .Running,
				working_context = "/workspace",
			},
			configuration = DEFAULT_ENTRY_CONFIGURATION,
		},
	)
	testing.expect(t, created_ok)
	if !created_ok {
		session_close(&session)
		return
	}
	other, other_ok, _ := session_create_buffer(
		&session,
		Create_Buffer_Request {
			session = handle,
			name = "occupied",
			configuration = DEFAULT_ENTRY_CONFIGURATION,
		},
	)
	testing.expect(t, other_ok)
	label, renamed, rename_failure := session_rename_terminal_buffer(
		&session,
		Rename_Terminal_Buffer_Request {
			entry = created.entry,
			terminal = terminal_ref,
			name = "shell",
		},
	)
	testing.expectf(t, renamed, "terminal rename failed with %v", rename_failure.code)
	testing.expect_value(t, closure_label_text(&label), "shell")
	found, found_ok, _ := session_find_label(&session, handle, "shell")
	testing.expect(t, found_ok)
	testing.expect_value(t, found, created.entry)
	activation, activated, _ := session_activate(&session, found)
	testing.expect(t, activated)
	testing.expect_value(t, activation.visible.entry, created.entry)
	state, state_ok, _ := session_terminal_buffer_state(&session, created.entry)
	testing.expect(t, state_ok)
	testing.expect_value(t, state.terminal, terminal_ref)
	_, collision_ok, collision_failure := session_rename_terminal_buffer(
		&session,
		Rename_Terminal_Buffer_Request {
			entry = created.entry,
			terminal = terminal_ref,
			name = "occupied",
		},
	)
	testing.expect(t, !collision_ok)
	testing.expect_value(t, collision_failure.code, Failure_Code.Name_Collision)
	test_detach_release(t, &session, other.entry)
	test_detach_release(t, &session, created.entry)
	session_closed, _ := session_close(&session)
	testing.expect(t, session_closed)
}
