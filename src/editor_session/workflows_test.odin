// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package editor_session

import "../document"
import "../editor"
import "../history"
import "../search"
import editor_view "../view"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:testing"

/* Ensures new unassociated buffers receive unique complete session graphs. */
@(test)
creates_unique_unassociated_buffers :: proc(t: ^testing.T) {
	session: Session
	handle, initialized, _ := session_init(&session, Session_ID(401), test_session_allocators())
	testing.expect(t, initialized)
	if !initialized {
		return
	}
	first, first_ok, first_failure := session_create_buffer(
		&session,
		Create_Buffer_Request {
			session = handle,
			name = "notes",
			configuration = DEFAULT_ENTRY_CONFIGURATION,
		},
	)
	testing.expect(t, first_ok)
	testing.expect_value(t, first_failure.code, Failure_Code.None)
	second, second_ok, second_failure := session_create_buffer(
		&session,
		Create_Buffer_Request {
			session = handle,
			name = "żółć-🙂",
			configuration = DEFAULT_ENTRY_CONFIGURATION,
		},
	)
	testing.expect(t, second_ok)
	testing.expect_value(t, second_failure.code, Failure_Code.None)
	if !first_ok || !second_ok {
		return
	}
	testing.expect_value(t, first.outcome, Admission_Outcome.Published)
	testing.expect_value(t, second.outcome, Admission_Outcome.Published)
	testing.expect_value(t, second.visible.entry, second.entry)
	usage_before, usage_ok, _ := session_usage(&session, handle)
	testing.expect(t, usage_ok)
	testing.expect_value(t, usage_before.live_buffers, u32(2))
	testing.expect_value(t, usage_before.live_documents, u32(0))

	_, duplicate_ok, duplicate_failure := session_create_buffer(
		&session,
		Create_Buffer_Request {
			session = handle,
			name = "notes",
			configuration = DEFAULT_ENTRY_CONFIGURATION,
		},
	)
	testing.expect(t, !duplicate_ok)
	testing.expect_value(t, duplicate_failure.code, Failure_Code.Name_Collision)
	usage_after, usage_after_ok, _ := session_usage(&session, handle)
	visible_after, visible_ok, _ := session_visible_target(&session, handle)
	testing.expect(t, usage_after_ok && visible_ok)
	testing.expect_value(t, usage_after, usage_before)
	testing.expect_value(t, visible_after.entry, second.entry)

	test_detach_release(t, &session, second.entry)
	test_detach_release(t, &session, first.entry)
	closed, _ := session_close(&session)
	testing.expect(t, closed)
}

/* Verifies generated surfaces can enter the session as clean revision-zero buffers. */
@(test)
create_buffer_keeps_clean_initial_text :: proc(t: ^testing.T) {
	session: Session
	handle, initialized, _ := session_init(&session, Session_ID(409), test_session_allocators())
	testing.expect(t, initialized)
	if !initialized do return
	created, created_ok, create_failure := session_create_buffer(
		&session,
		Create_Buffer_Request {
			session = handle,
			name = "generated",
			initial_contents = "alpha/\nbeta.odin\n",
			configuration = DEFAULT_ENTRY_CONFIGURATION,
		},
	)
	testing.expectf(t, created_ok, "creation failed: %v", create_failure.code)
	if !created_ok do return
	access, access_ok, _ := session_entry_access(&session, created.entry)
	borrow, borrow_ok, _ := entry_access_borrow(access)
	testing.expect(t, access_ok && borrow_ok)
	if borrow_ok {
		stats, stats_ok, _ := editor.buffer_stats(borrow.buffer)
		testing.expect(t, stats_ok)
		if stats_ok {
			testing.expect_value(t, stats.revision, editor.Revision(0))
			testing.expect_value(t, stats.text_bytes, u64(17))
		}
	}
	assessment, assessed, _ := session_assess_buffer_close(&session, created.entry)
	testing.expect(t, assessed)
	if assessed do testing.expect(t, !assessment.modified)
	test_detach_release(t, &session, created.entry)
	closed, _ := session_close(&session)
	testing.expect(t, closed)
}

/* Ensures dirty closure requires discard and releases copied metadata. */
@(test)
close_requires_discard_and_frees_metadata :: proc(t: ^testing.T) {
	session: Session
	handle, initialized, _ := session_init(&session, Session_ID(410), test_session_allocators())
	testing.expect(t, initialized)
	if !initialized {
		return
	}
	first, first_ok, _ := session_create_buffer(
		&session,
		Create_Buffer_Request {
			session = handle,
			name = "żółć-🙂",
			configuration = DEFAULT_ENTRY_CONFIGURATION,
		},
	)
	second, second_ok, _ := session_create_buffer(
		&session,
		Create_Buffer_Request {
			session = handle,
			name = "second",
			configuration = DEFAULT_ENTRY_CONFIGURATION,
		},
	)
	testing.expect(t, first_ok && second_ok)
	if !first_ok || !second_ok {
		return
	}
	_, activated, _ := session_activate(&session, first.entry)
	access, access_ok, _ := session_entry_access(&session, first.entry)
	borrow, borrow_ok, _ := entry_access_borrow(access)
	testing.expect(t, activated && access_ok && borrow_ok)
	if !borrow_ok {
		return
	}
	start, start_ok, _ := editor.buffer_position(borrow.buffer, 0)
	_, _, changed, change_failure := editor.buffer_splice(
		borrow.buffer,
		editor.Splice {
			start = start,
			end = start,
			replacement = "draft",
		},
		context.temp_allocator,
	)
	testing.expect(t, start_ok && changed)
	testing.expect_value(t, change_failure.code, editor.Failure_Code.None)
	_, reconciled, _ := entry_access_reconcile(access)
	testing.expect(t, reconciled)

	assessment, assessed, assess_failure := session_close_buffer(
		&session,
		Close_Buffer_Request {entry = first.entry},
	)
	testing.expect(t, assessed)
	testing.expect_value(t, assess_failure.code, Failure_Code.None)
	testing.expect_value(t, assessment.outcome, Closure_Outcome.Discard_Required)
	testing.expect(t, assessment.modified && assessment.was_visible)
	testing.expect_value(t, closure_label_text(&assessment.selection_label), "żółć-🙂")
	visible, visible_ok, _ := session_visible_target(&session, handle)
	usage, usage_ok, _ := session_usage(&session, handle)
	testing.expect(t, visible_ok && usage_ok)
	testing.expect_value(t, visible.entry, first.entry)
	testing.expect_value(t, usage.live_buffers, u32(2))

	closed_result, entry_closed, close_failure := session_close_buffer(
		&session,
		Close_Buffer_Request {
			entry = first.entry,
			authority = .Discard_Modified,
		},
	)
	testing.expect(t, entry_closed)
	testing.expect_value(t, close_failure.code, Failure_Code.None)
	testing.expect_value(t, closed_result.outcome, Closure_Outcome.Closed)
	testing.expect_value(t, closed_result.successor.entry, second.entry)
	testing.expect(t, !closed_result.last_buffer && closed_result.cleanup.complete)
	testing.expect_value(t, closure_label_text(&closed_result.selection_label), "żółć-🙂")
	_, stale_ok, stale_failure := entry_access_borrow(access)
	testing.expect(t, !stale_ok)
	testing.expect_value(t, stale_failure.code, Failure_Code.Stale_Entry)

	last_result, last_closed, last_failure := session_close_buffer(
		&session,
		Close_Buffer_Request {entry = second.entry},
	)
	testing.expect(t, last_closed)
	testing.expect_value(t, last_failure.code, Failure_Code.None)
	testing.expect_value(t, last_result.outcome, Closure_Outcome.Closed)
	testing.expect(t, last_result.last_buffer)
	testing.expect_value(t, last_result.successor.kind, Visible_Target_Kind.None)
	testing.expect_value(t, last_result.usage.live_buffers, u32(0))
	session_closed, session_failure := session_close(&session)
	testing.expect(t, session_closed)
	testing.expect_value(t, session_failure.code, Failure_Code.None)
}

/* Ensures active logical preparation blocks session closure without detaching state. */
@(test)
close_rejects_active_preparation :: proc(t: ^testing.T) {
	session: Session
	handle, initialized, _ := session_init(&session, Session_ID(411), test_session_allocators())
	testing.expect(t, initialized)
	if !initialized {
		return
	}
	created, created_ok, _ := session_create_buffer(
		&session,
		Create_Buffer_Request {
			session = handle,
			name = "busy",
			configuration = DEFAULT_ENTRY_CONFIGURATION,
		},
	)
	testing.expect(t, created_ok)
	if !created_ok {
		return
	}
	access, access_ok, _ := session_entry_access(&session, created.entry)
	borrow, borrow_ok, _ := entry_access_borrow(access)
	testing.expect(t, access_ok && borrow_ok)
	if !borrow_ok {
		return
	}
	stats, stats_ok, _ := editor.buffer_stats(borrow.buffer)
	prepared: editor_view.Prepared_Logical_Edit
	prepared_ok, _ := editor_view.logical_edit_prepare(
		borrow.view_registry,
		borrow.primary_view,
		editor_view.Logical_Edit_Request {
			buffer_id = stats.buffer_id,
			base_revision = stats.revision,
			result_point_offset = 0,
			region = .Preserve,
			mark = .Preserve,
		},
		&prepared,
	)
	testing.expect(t, stats_ok && prepared_ok)
	_, closed, close_failure := session_close_buffer(
		&session,
		Close_Buffer_Request {entry = created.entry},
	)
	testing.expect(t, !closed)
	testing.expect_value(t, close_failure.code, Failure_Code.Busy)
	visible, visible_ok, _ := session_visible_target(&session, handle)
	testing.expect(t, visible_ok)
	testing.expect_value(t, visible.entry, created.entry)
	aborted, _ := editor_view.logical_edit_abort(&prepared)
	testing.expect(t, aborted)
	result: Closure_Result
	result, closed, close_failure = session_close_buffer(
		&session,
		Close_Buffer_Request {entry = created.entry},
	)
	testing.expect(t, closed)
	testing.expect_value(t, close_failure.code, Failure_Code.None)
	testing.expect_value(t, result.outcome, Closure_Outcome.Closed)
	session_closed, _ := session_close(&session)
	testing.expect(t, session_closed)
}

/* Verifies first save publishes the document and both full-path indexes. */
@(test)
first_save_publishes_path_indexes :: proc(t: ^testing.T) {
	directory, directory_error := os.make_directory_temp("", "odra-session-associate-*", context.allocator)
	testing.expect(t, directory_error == nil)
	if directory_error != nil {
		return
	}
	defer {
		os.remove_all(directory)
		delete(directory)
	}
	path, path_error := os.join_path({directory, "saved.txt"}, context.allocator)
	testing.expect(t, path_error == nil)
	if path_error != nil {
		return
	}
	defer delete(path)

	session: Session
	handle, initialized, _ := session_init(&session, Session_ID(412), test_session_allocators())
	testing.expect(t, initialized)
	if !initialized {
		return
	}
	created, created_ok, _ := session_create_buffer(
		&session,
		Create_Buffer_Request {
			session = handle,
			name = "draft",
			configuration = DEFAULT_ENTRY_CONFIGURATION,
		},
	)
	testing.expect(t, created_ok)
	if !created_ok {
		return
	}
	access, access_ok, _ := session_entry_access(&session, created.entry)
	borrow, borrow_ok, _ := entry_access_borrow(access)
	testing.expect(t, access_ok && borrow_ok)
	if !borrow_ok {
		return
	}
	start, _, _ := editor.buffer_position(borrow.buffer, 0)
	_, _, changed, _ := editor.buffer_splice(
		borrow.buffer,
		editor.Splice {start = start, end = start, replacement = "saved text"},
		context.temp_allocator,
	)
	testing.expect(t, changed)
	_, reconciled, _ := entry_access_reconcile(access)
	testing.expect(t, reconciled)
	associated, saved, save_failure := session_associate_and_save(
		&session,
		Associate_Save_Request {
			entry = created.entry,
			path = path,
			limits = document.DEFAULT_LIMITS,
		},
	)
	testing.expect(t, saved)
	testing.expect_value(t, save_failure.code, Failure_Code.None)
	testing.expect_value(t, closure_label_text(&associated.selection_label), path)
	testing.expect_value(t, associated.usage.live_documents, u32(1))
	contents, contents_error := os.read_entire_file(path, context.allocator)
	testing.expect(t, contents_error == nil)
	if contents_error == nil {
		testing.expect_value(t, string(contents), "saved text")
		delete(contents)
	}
	found_label, label_found, _ := session_find_label(&session, handle, path)
	found_path, path_found, _ := session_find_path(&session, handle, path)
	testing.expect(t, label_found && path_found)
	testing.expect_value(t, found_label, created.entry)
	testing.expect_value(t, found_path, created.entry)
	borrow, borrow_ok, _ = entry_access_borrow(access)
	testing.expect(t, borrow_ok && borrow.has_document)
	if borrow_ok {
		status, status_ok, _ := document.document_status(borrow.document)
		testing.expect(t, status_ok)
		testing.expect_value(t, status.persistence, document.Persistence_State.Clean)
		testing.expect_value(t, status.target_path, path)
	}
	closed_result, entry_closed, close_failure := session_close_buffer(
		&session,
		Close_Buffer_Request {entry = created.entry},
	)
	testing.expect(t, entry_closed)
	testing.expect_value(t, close_failure.code, Failure_Code.None)
	testing.expect(t, !closed_result.modified && closed_result.last_buffer)
	session_closed, _ := session_close(&session)
	testing.expect(t, session_closed)
}

/* Verifies writing an associated buffer changes its authoritative path atomically. */
@(test)
write_file_replaces_document_identity :: proc(t: ^testing.T) {
	directory, directory_error := os.make_directory_temp("", "odra-session-write-*", context.allocator)
	testing.expect(t, directory_error == nil)
	if directory_error != nil do return
	defer {os.remove_all(directory); delete(directory)}
	source, source_error := os.join_path({directory, "source.txt"}, context.allocator)
	destination, destination_error := os.join_path({directory, "destination.txt"}, context.allocator)
	testing.expect(t, source_error == nil && destination_error == nil)
	if source_error != nil || destination_error != nil do return
	defer {delete(destination); delete(source)}
	testing.expect(t, os.write_entire_file(source, "original") == nil)

	session: Session
	handle, initialized, _ := session_init(&session, Session_ID(421), test_session_allocators())
	testing.expect(t, initialized)
	if !initialized do return
	opened, opened_ok, _ := session_open_path(
		&session,
		Open_Path_Request {
			session = handle,
			path = source,
			encoding = .UTF8,
			configuration = DEFAULT_ENTRY_CONFIGURATION,
		},
	)
	testing.expect(t, opened_ok)
	if !opened_ok do return
	written, saved, save_failure := session_write_entry_to_path(
		&session,
		Associate_Save_Request {
			entry = opened.entry,
			path = destination,
			limits = document.DEFAULT_LIMITS,
		},
	)
	testing.expectf(t, saved, "write failed: %v", save_failure.code)
	testing.expect_value(t, closure_label_text(&written.selection_label), destination)
	_, old_found, _ := session_find_path(&session, handle, source)
	new_entry, new_found, _ := session_find_path(&session, handle, destination)
	testing.expect(t, !old_found && new_found)
	testing.expect_value(t, new_entry, opened.entry)
	contents, contents_error := os.read_entire_file(destination, context.allocator)
	testing.expect(t, contents_error == nil)
	if contents_error == nil {
		testing.expect_value(t, string(contents), "original")
		delete(contents)
	}
	test_detach_release(t, &session, opened.entry)
	closed, _ := session_close(&session)
	testing.expect(t, closed)
}

/* Relocating a directory updates exact and descendant document indexes together. */
@(test)
relocates_paths_for_moved_dirs :: proc(t: ^testing.T) {
	root, root_error := os.make_directory_temp("", "odra-session-relocate-*", context.allocator)
	testing.expect(t, root_error == nil)
	if root_error != nil do return
	defer {os.remove_all(root); delete(root)}
	from, _ := os.join_path({root, "from"}, context.allocator)
	to, _ := os.join_path({root, "to"}, context.allocator)
	old_path, _ := os.join_path({from, "document.txt"}, context.allocator)
	new_path, _ := os.join_path({to, "document.txt"}, context.allocator)
	defer {delete(new_path); delete(old_path); delete(to); delete(from)}
	testing.expect(t, os.make_directory(from) == nil)
	testing.expect(t, os.write_entire_file(old_path, "document") == nil)
	session: Session
	handle, initialized, _ := session_init(&session, Session_ID(413), test_session_allocators())
	testing.expect(t, initialized)
	if !initialized do return
	opened, opened_ok, _ := session_open_path(
		&session,
		Open_Path_Request {
			session = handle,
			path = old_path,
			encoding = .UTF8,
			configuration = DEFAULT_ENTRY_CONFIGURATION,
		},
	)
	testing.expect(t, opened_ok)
	if !opened_ok do return
	testing.expect(t, os.rename(from, to) == nil)
	result, relocated, relocation_failure := session_relocate_document_paths(
		&session, handle, {from = from, to = to, directory = true},
	)
	testing.expectf(t, relocated, "relocation failed: %v", relocation_failure.code)
	testing.expect_value(t, result.relocated, u32(1))
	_, old_found, _ := session_find_path(&session, handle, old_path)
	new_entry, new_found, _ := session_find_path(&session, handle, new_path)
	testing.expect(t, !old_found && new_found)
	testing.expect_value(t, new_entry, opened.entry)
	access, accessed, _ := session_entry_access(&session, opened.entry)
	borrow, borrowed, _ := entry_access_borrow(access)
	testing.expect(t, accessed && borrowed)
	if borrowed {
		status, status_ok, _ := document.document_status(borrow.document)
		testing.expect(t, status_ok)
		testing.expect_value(t, status.target_path, new_path)
	}
	_, closed, _ := session_close_buffer(&session, {entry = opened.entry})
	testing.expect(t, closed)
	session_closed, _ := session_close(&session)
	testing.expect(t, session_closed)
}

/* Ensures normalized paths reuse the existing document without rereading it. */
@(test)
reuses_paths_without_rereading :: proc(t: ^testing.T) {
	directory, directory_error := os.make_directory_temp("", "odra-session-open-*", context.allocator)
	testing.expect(t, directory_error == nil)
	if directory_error != nil {
		return
	}
	defer {
		os.remove_all(directory)
		delete(directory)
	}
	path, path_error := os.join_path({directory, "document.txt"}, context.allocator)
	testing.expect(t, path_error == nil)
	if path_error != nil {
		return
	}
	defer delete(path)
	testing.expect(t, os.write_entire_file(path, "first text") == nil)

	session: Session
	handle, initialized, _ := session_init(&session, Session_ID(402), test_session_allocators())
	testing.expect(t, initialized)
	if !initialized {
		return
	}
	first, first_ok, first_failure := session_open_path(
		&session,
		Open_Path_Request {
			session = handle,
			path = path,
			encoding = .UTF8,
			configuration = DEFAULT_ENTRY_CONFIGURATION,
		},
	)
	testing.expect(t, first_ok)
	testing.expect_value(t, first_failure.code, Failure_Code.None)
	if !first_ok {
		session_close(&session)
		return
	}

	invalid_bytes := []u8{'n', 'e', 'w', 0xff}
	testing.expect(t, os.write_entire_file(path, string(invalid_bytes)) == nil)
	alias := fmt.aprintf("%s/./document.txt", directory)
	defer delete(alias)
	reused, reused_ok, reused_failure := session_open_path(
		&session,
		Open_Path_Request {
			session = handle,
			path = alias,
			encoding = .UTF8,
			configuration = DEFAULT_ENTRY_CONFIGURATION,
		},
	)
	testing.expect(t, reused_ok)
	testing.expect_value(t, reused_failure.code, Failure_Code.None)
	testing.expect_value(t, reused.outcome, Admission_Outcome.Reused)
	testing.expect_value(t, reused.entry, first.entry)
	usage, usage_ok, _ := session_usage(&session, handle)
	testing.expect(t, usage_ok)
	testing.expect_value(t, usage.live_buffers, u32(1))
	testing.expect_value(t, usage.live_documents, u32(1))

	access, access_ok, _ := session_active_entry_access(&session, handle)
	borrow, borrow_ok, _ := entry_access_borrow(access)
	testing.expect(t, access_ok && borrow_ok)
	if borrow_ok {
		bytes: [32]byte
		copied, inspected, _ := editor.buffer_inspect(
			borrow.buffer,
			editor.Byte_Offset(0),
			editor.Byte_Offset(len("first text")),
			bytes[:],
		)
		testing.expect(t, inspected)
		testing.expect_value(t, string(bytes[:copied]), "first text")
		status, status_ok, _ := document.document_status(borrow.document)
		testing.expect(t, status_ok)
		testing.expect_value(t, status.target_path, path)
	}
	test_detach_release(t, &session, first.entry)
	closed, _ := session_close(&session)
	testing.expect(t, closed)
}

/* Verifies absent targets open as empty, unmaterialized documents. */
@(test)
opens_missing_targets_as_empty_docs :: proc(t: ^testing.T) {
	directory, directory_error := os.make_directory_temp("", "odra-session-missing-*", context.allocator)
	testing.expect(t, directory_error == nil)
	if directory_error != nil {
		return
	}
	defer {
		os.remove_all(directory)
		delete(directory)
	}
	path, path_error := os.join_path({directory, "new.txt"}, context.allocator)
	testing.expect(t, path_error == nil)
	if path_error != nil {
		return
	}
	defer delete(path)

	session: Session
	handle, initialized, _ := session_init(&session, Session_ID(403), test_session_allocators())
	testing.expect(t, initialized)
	if !initialized {
		return
	}
	opened, opened_ok, opened_failure := session_open_path(
		&session,
		Open_Path_Request {
			session = handle,
			path = path,
			encoding = .UTF8,
			configuration = DEFAULT_ENTRY_CONFIGURATION,
		},
	)
	testing.expect(t, opened_ok)
	testing.expect_value(t, opened_failure.code, Failure_Code.None)
	if opened_ok {
		access, access_ok, _ := session_active_entry_access(&session, handle)
		borrow, borrow_ok, _ := entry_access_borrow(access)
		testing.expect(t, access_ok && borrow_ok)
		if borrow_ok {
			buffer_stats, stats_ok, _ := editor.buffer_stats(borrow.buffer)
			status, status_ok, _ := document.document_status(borrow.document)
			testing.expect(t, stats_ok && status_ok)
			testing.expect_value(t, buffer_stats.text_bytes, u64(0))
			testing.expect_value(t, status.persistence, document.Persistence_State.Unmaterialized)
		}
		test_detach_release(t, &session, opened.entry)
	}
	closed, _ := session_close(&session)
	testing.expect(t, closed)
}

/* Ensures a path already used as an unassociated label cannot be opened twice. */
@(test)
open_rejects_owned_path_label :: proc(t: ^testing.T) {
	directory, directory_error := os.make_directory_temp("", "odra-session-label-*", context.allocator)
	testing.expect(t, directory_error == nil)
	if directory_error != nil {
		return
	}
	defer {
		os.remove_all(directory)
		delete(directory)
	}
	path, path_error := os.join_path({directory, "collision.txt"}, context.allocator)
	testing.expect(t, path_error == nil)
	if path_error != nil {
		return
	}
	defer delete(path)
	testing.expect(t, os.write_entire_file(path, "must not open") == nil)

	session: Session
	handle, initialized, _ := session_init(&session, Session_ID(404), test_session_allocators())
	testing.expect(t, initialized)
	if !initialized {
		return
	}
	created, created_ok, _ := session_create_buffer(
		&session,
		Create_Buffer_Request {
			session = handle,
			name = path,
			configuration = DEFAULT_ENTRY_CONFIGURATION,
		},
	)
	testing.expect(t, created_ok)
	if !created_ok {
		session_close(&session)
		return
	}
	usage_before, _, _ := session_usage(&session, handle)
	visible_before, _, _ := session_visible_target(&session, handle)
	_, opened, open_failure := session_open_path(
		&session,
		Open_Path_Request {
			session = handle,
			path = path,
			encoding = .UTF8,
			configuration = DEFAULT_ENTRY_CONFIGURATION,
		},
	)
	testing.expect(t, !opened)
	testing.expect_value(t, open_failure.code, Failure_Code.Name_Collision)
	usage_after, _, _ := session_usage(&session, handle)
	visible_after, _, _ := session_visible_target(&session, handle)
	testing.expect_value(t, usage_after, usage_before)
	testing.expect_value(t, visible_after, visible_before)
	test_detach_release(t, &session, created.entry)
	closed, _ := session_close(&session)
	testing.expect(t, closed)
}

/* Ensures open failures after reading release every private graph owner. */
@(test)
open_failure_releases_owners :: proc(t: ^testing.T) {
	directory, directory_error := os.make_directory_temp("", "odra-session-rollback-*", context.allocator)
	testing.expect(t, directory_error == nil)
	if directory_error != nil {
		return
	}
	defer {
		os.remove_all(directory)
		delete(directory)
	}
	path, path_error := os.join_path({directory, "rollback.txt"}, context.allocator)
	testing.expect(t, path_error == nil)
	if path_error != nil {
		return
	}
	defer delete(path)
	testing.expect(t, os.write_entire_file(path, "private contents") == nil)

	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	session: Session
	handle, initialized, _ := session_init(
		&session,
		Session_ID(405),
		Allocator_Set {
			persistent = mem.tracking_allocator(&tracking),
			temporary = context.temp_allocator,
		},
	)
	testing.expect(t, initialized)
	if !initialized {
		return
	}
	baseline := tracking.current_memory_allocated
	configuration := DEFAULT_ENTRY_CONFIGURATION
	configuration.view_config.indentation_policy.display_tab_width = 0
	_, opened, open_failure := session_open_path(
		&session,
		Open_Path_Request {
			session = handle,
			path = path,
			encoding = .UTF8,
			configuration = configuration,
		},
	)
	testing.expect(t, !opened)
	testing.expect_value(t, open_failure.code, Failure_Code.View_Failure)
	usage, usage_ok, _ := session_usage(&session, handle)
	testing.expect(t, usage_ok)
	testing.expect_value(t, usage.live_buffers, u32(0))
	testing.expect_value(t, usage.live_documents, u32(0))
	testing.expect_value(t, usage.prepared_operations, u32(0))
	testing.expect_value(t, tracking.current_memory_allocated, baseline)
	closed, _ := session_close(&session)
	testing.expect(t, closed)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
}

/* Verifies activation restores each retained primary view independently. */
@(test)
activation_restores_primary_views :: proc(t: ^testing.T) {
	directory, directory_error := os.make_directory_temp("", "odra-session-views-*", context.allocator)
	testing.expect(t, directory_error == nil)
	if directory_error != nil {
		return
	}
	defer {
		os.remove_all(directory)
		delete(directory)
	}
	first_path, first_path_error := os.join_path({directory, "first.txt"}, context.allocator)
	second_path, second_path_error := os.join_path({directory, "second.txt"}, context.allocator)
	testing.expect(t, first_path_error == nil && second_path_error == nil)
	if first_path_error != nil || second_path_error != nil {
		if first_path_error == nil {
			delete(first_path)
		}
		if second_path_error == nil {
			delete(second_path)
		}
		return
	}
	defer delete(first_path)
	defer delete(second_path)
	testing.expect(t, os.write_entire_file(first_path, "0123456789") == nil)
	testing.expect(t, os.write_entire_file(second_path, "abcdefghij") == nil)

	session: Session
	handle, initialized, _ := session_init(&session, Session_ID(406), test_session_allocators())
	testing.expect(t, initialized)
	if !initialized {
		return
	}
	first, first_ok, _ := session_open_path(
		&session,
		Open_Path_Request {
			session = handle,
			path = first_path,
			encoding = .UTF8,
			configuration = DEFAULT_ENTRY_CONFIGURATION,
		},
	)
	second, second_ok, _ := session_open_path(
		&session,
		Open_Path_Request {
			session = handle,
			path = second_path,
			encoding = .UTF8,
			configuration = DEFAULT_ENTRY_CONFIGURATION,
		},
	)
	testing.expect(t, first_ok && second_ok)
	if !first_ok || !second_ok {
		return
	}
	first_access, first_access_ok, _ := session_entry_access(&session, first.entry)
	first_borrow, first_borrow_ok, _ := entry_access_borrow(first_access)
	second_access, second_access_ok, _ := session_entry_access(&session, second.entry)
	second_borrow, second_borrow_ok, _ := entry_access_borrow(second_access)
	testing.expect(t, first_access_ok && first_borrow_ok && second_access_ok && second_borrow_ok)
	if !first_borrow_ok || !second_borrow_ok {
		return
	}
	point, point_ok, _ := editor.buffer_position(first_borrow.buffer, editor.Byte_Offset(4))
	mark, mark_ok, _ := editor.buffer_position(first_borrow.buffer, editor.Byte_Offset(1))
	viewport, viewport_ok, _ := editor.buffer_position(first_borrow.buffer, editor.Byte_Offset(2))
	testing.expect(t, point_ok && mark_ok && viewport_ok)
	point_set, _ := editor_view.move_point(
		first_borrow.view_registry,
		first_borrow.primary_view,
		point,
		12,
	)
	mark_set, _ := editor_view.set_mark(
		first_borrow.view_registry,
		first_borrow.primary_view,
		mark,
		true,
	)
	viewport_set, _ := editor_view.set_viewport(
		first_borrow.view_registry,
		first_borrow.primary_view,
		viewport,
		7,
	)
	policy_set, _ := editor_view.set_layout_policy(
		first_borrow.view_registry,
		first_borrow.primary_view,
		12,
		8,
		editor_view.Display_Profile_ID(2),
	)
	testing.expect(t, point_set && mark_set && viewport_set && policy_set)

	activation, activated, activation_failure := session_activate(&session, first.entry)
	testing.expect(t, activated)
	testing.expect_value(t, activation_failure.code, Failure_Code.None)
	testing.expect_value(t, activation.previous.entry, second.entry)
	testing.expect_value(t, activation.visible.entry, first.entry)
	first_snapshot, first_snapshot_ok, _ := editor_view.snapshot(
		first_borrow.view_registry,
		first_borrow.primary_view,
	)
	testing.expect(t, first_snapshot_ok)
	testing.expect_value(t, first_snapshot.point_position.byte_offset, editor.Byte_Offset(4))
	testing.expect(t, first_snapshot.mark.present && first_snapshot.region_active)
	testing.expect_value(t, first_snapshot.mark.position.byte_offset, editor.Byte_Offset(1))
	testing.expect_value(t, first_snapshot.viewport_origin_position.byte_offset, editor.Byte_Offset(2))
	testing.expect_value(t, first_snapshot.horizontal_display_column, u32(7))
	testing.expect_value(t, first_snapshot.desired_display_column, u32(12))
	testing.expect_value(t, first_snapshot.tab_width, u16(8))

	first_history, first_history_ok, _ := history.store_stats(first_borrow.history_store)
	second_history, second_history_ok, _ := history.store_stats(second_borrow.history_store)
	testing.expect(t, first_history_ok && second_history_ok)
	testing.expect(t, first_history.store_id != second_history.store_id)
	_, second_activated, _ := session_activate(&session, second.entry)
	retained, retained_ok, _ := editor_view.snapshot(
		first_borrow.view_registry,
		first_borrow.primary_view,
	)
	testing.expect(t, second_activated && retained_ok)
	testing.expect_value(t, retained, first_snapshot)

	test_detach_release(t, &session, second.entry)
	test_detach_release(t, &session, first.entry)
	closed, _ := session_close(&session)
	testing.expect(t, closed)
}

/* Ensures unresolved outgoing search state blocks session activation. */
@(test)
activation_rejects_pending_search :: proc(t: ^testing.T) {
	directory, directory_error := os.make_directory_temp("", "odra-session-transient-*", context.allocator)
	testing.expect(t, directory_error == nil)
	if directory_error != nil {
		return
	}
	defer {
		os.remove_all(directory)
		delete(directory)
	}
	first_path, _ := os.join_path({directory, "first.txt"}, context.allocator)
	second_path, _ := os.join_path({directory, "second.txt"}, context.allocator)
	defer delete(first_path)
	defer delete(second_path)
	testing.expect(t, os.write_entire_file(first_path, "needle here") == nil)
	testing.expect(t, os.write_entire_file(second_path, "other") == nil)

	session: Session
	handle, initialized, _ := session_init(&session, Session_ID(407), test_session_allocators())
	testing.expect(t, initialized)
	if !initialized {
		return
	}
	first, first_ok, _ := session_open_path(
		&session,
		Open_Path_Request {
			session = handle,
			path = first_path,
			encoding = .UTF8,
			configuration = DEFAULT_ENTRY_CONFIGURATION,
		},
	)
	second, second_ok, _ := session_open_path(
		&session,
		Open_Path_Request {
			session = handle,
			path = second_path,
			encoding = .UTF8,
			configuration = DEFAULT_ENTRY_CONFIGURATION,
		},
	)
	testing.expect(t, first_ok && second_ok)
	if !first_ok || !second_ok {
		return
	}
	_, first_activated, _ := session_activate(&session, first.entry)
	first_access, access_ok, _ := session_entry_access(&session, first.entry)
	first_borrow, borrow_ok, _ := entry_access_borrow(first_access)
	testing.expect(t, first_activated && access_ok && borrow_ok)
	if !borrow_ok {
		return
	}
	query: search.Query
	query_ok, _ := search.query_init(
		&query,
		search.Query_Config {
			id = search.Query_ID(1),
			kind = .Literal,
			pattern = "needle",
			policy = search.DEFAULT_POLICY,
			limits = search.DEFAULT_LIMITS,
			allocator = context.allocator,
		},
	)
	snapshot: editor.Buffer_Snapshot
	snapshot_ok, _ := editor.buffer_snapshot_open(first_borrow.buffer, &snapshot)
	result: search.Result
	searched := false
	if query_ok && snapshot_ok {
		stats, _, _ := editor.buffer_snapshot_stats(&snapshot)
		searched, _ = search.literal_search(
			&result,
			&snapshot,
			&query,
			search.Request {
				scope = search.Scope {
					buffer_id = stats.buffer_id,
					revision = stats.revision,
					start = 0,
					end = editor.Byte_Offset(stats.text_bytes),
				},
				origin = 0,
				direction = .Forward,
				generation = search.Search_Generation(1),
			},
			nil,
			search.Allocator_Set {
				persistent = context.allocator,
				temporary = context.temp_allocator,
			},
		)
		editor.buffer_snapshot_close(&snapshot)
	}
	testing.expect(t, query_ok && snapshot_ok && searched)
	if !searched {
		if query.state != nil {
			search.query_close(&query)
		}
		return
	}
	result_view, result_ok, _ := search.result_view(&result)
	testing.expect(t, result_ok)
	published, _ := editor_view.search_session_publish(
		first_borrow.view_registry,
		first_borrow.primary_view,
		editor_view.Search_Update {
			interaction_generation = 1,
			policy_generation = search.Policy_Generation(1),
			direction = .Forward,
			scope = result_view.scope,
		},
		&query,
		&result,
	)
	testing.expect(t, published)
	_, switched, switch_failure := session_activate(&session, second.entry)
	testing.expect(t, !switched)
	testing.expect_value(t, switch_failure.code, Failure_Code.Busy)
	visible, visible_ok, _ := session_visible_target(&session, handle)
	testing.expect(t, visible_ok)
	testing.expect_value(t, visible.entry, first.entry)
	settled, _ := editor_view.search_session_accept(
		first_borrow.view_registry,
		first_borrow.primary_view,
	)
	_, switched, switch_failure = session_activate(&session, second.entry)
	testing.expect(t, settled && switched)
	testing.expect_value(t, switch_failure.code, Failure_Code.None)

	test_detach_release(t, &session, second.entry)
	test_detach_release(t, &session, first.entry)
	closed, _ := session_close(&session)
	testing.expect(t, closed)
}

/* Ensures create faults release private graphs at every admission boundary. */
@(test)
create_faults_release_private_graphs :: proc(t: ^testing.T) {
	failures: u32
	successes: u32
	for offset in 0 ..< 32 {
		tracking: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracking, context.allocator)
		failing := Session_Failing_Allocator {
			backing = mem.tracking_allocator(&tracking),
			fail_after = max(u64),
		}
		session: Session
		handle, initialized, _ := session_init(
			&session,
			Session_ID(500 + offset),
			Allocator_Set {
				persistent = session_failing_allocator(&failing),
				temporary = context.temp_allocator,
			},
		)
		testing.expect(t, initialized)
		if !initialized {
			mem.tracking_allocator_destroy(&tracking)
			continue
		}
		baseline := tracking.current_memory_allocated
		failing.fail_after = failing.successful_allocations + u64(offset)
		result, created, failure := session_create_buffer(
			&session,
			Create_Buffer_Request {
				session = handle,
				name = "faulted",
				configuration = DEFAULT_ENTRY_CONFIGURATION,
			},
		)
		failing.fail_after = max(u64)
		if created {
			successes += 1
			test_detach_release(t, &session, result.entry)
		} else {
			failures += 1
			testing.expect(t, failure.code != .None)
			usage, usage_ok, _ := session_usage(&session, handle)
			testing.expect(t, usage_ok)
			testing.expect_value(t, usage.live_buffers, u32(0))
			testing.expect_value(t, usage.prepared_operations, u32(0))
			testing.expect_value(t, tracking.current_memory_allocated, baseline)
		}
		closed, _ := session_close(&session)
		testing.expect(t, closed)
		testing.expect_value(t, tracking.current_memory_allocated, i64(0))
		mem.tracking_allocator_destroy(&tracking)
	}
	testing.expect(t, failures > 0)
	testing.expect(t, successes > 0)
}
