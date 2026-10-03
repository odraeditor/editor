// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package editor_session

import "../document"
import "../editor"
import "../history"
import editor_view "../view"
import "core:os"
import "core:testing"

/* Verifies stable traversal order is independent from recent activation order. */
@(test)
session_ordered_entries_preserve_slot_order :: proc(t: ^testing.T) {
	session: Session
	handle, initialized, _ := session_init(&session, Session_ID(90), test_session_allocators())
	testing.expect(t, initialized)
	if !initialized do return
	first, first_ok, _ := session_create_buffer(
		&session,
		Create_Buffer_Request {
			session = handle,
			name = "first",
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
	if !first_ok || !second_ok do return
	_, activated, _ := session_activate(&session, first.entry)
	testing.expect(t, activated)
	entries: [2]Entry_Handle
	count, copied, copy_failure := session_ordered_entries(&session, handle, entries[:])
	testing.expectf(t, copied, "ordered copy failed with %v", copy_failure.code)
	testing.expect_value(t, count, u32(2))
	if copied && count == 2 {
		testing.expect_value(t, entries[0], first.entry)
		testing.expect_value(t, entries[1], second.entry)
	}
	test_detach_release(t, &session, first.entry)
	test_detach_release(t, &session, second.entry)
	closed, _ := session_close(&session)
	testing.expect(t, closed)
}

/* Verifies copied inventory descriptors preserve active-then-MRU order and live status. */
@(test)
session_descriptors_copy_complete_inventory :: proc(t: ^testing.T) {
	session: Session
	handle, initialized, _ := session_init(&session, Session_ID(91), test_session_allocators())
	testing.expect(t, initialized)
	if !initialized {
		return
	}
	first, first_ok, _ := session_create_buffer(
		&session,
		Create_Buffer_Request {
			session = handle,
			name = "first",
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
	if borrow_ok {
		position, positioned, _ := editor.buffer_position(borrow.buffer, 0)
		_, _, changed, _ := editor.buffer_splice(
			borrow.buffer,
			editor.Splice{start = position, end = position, replacement = "draft"},
			context.temp_allocator,
		)
		testing.expect(t, positioned && changed)
		_, reconciled, _ := entry_access_reconcile(access)
		testing.expect(t, reconciled)
	}
	batch, copied, copy_failure := session_descriptors(&session, handle)
	testing.expectf(t, copied, "descriptor copy failed with %v", copy_failure.code)
	if copied {
		testing.expect_value(t, len(batch.descriptors), 2)
		testing.expect_value(t, batch.descriptors[0].graph.entry, first.entry)
		testing.expect_value(t, batch.descriptors[0].selection_label, "first")
		testing.expect(t, batch.descriptors[0].active && batch.descriptors[0].modified)
		testing.expect_value(t, batch.descriptors[0].persistence, document.Persistence_State.Unassociated)
		testing.expect_value(t, batch.descriptors[1].graph.entry, second.entry)
		testing.expect(t, !batch.descriptors[1].active && !batch.descriptors[1].modified)
		testing.expect(t, descriptor_batch_close(&batch))
		testing.expect(t, !descriptor_batch_close(&batch))
	}
	test_detach_release(t, &session, first.entry)
	test_detach_release(t, &session, second.entry)
	closed, _ := session_close(&session)
	testing.expect(t, closed)
}

@(private)
Test_Resources :: struct {
	buffer:        editor.Buffer,
	history_store: history.Store,
	document:      document.Document,
}

/* Verifies publication, activation, detachment, and release as one registry lifecycle. */
@(test)
registry_manages_session_graphs :: proc(t: ^testing.T) {
	session: Session
	session_handle, initialized, init_failure := session_init(
		&session,
		Session_ID(41),
		Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	testing.expect(t, initialized)
	testing.expect_value(t, init_failure.code, Failure_Code.None)
	if !initialized {
		return
	}

	first, first_ok := test_resources_init(t, 1, "first")
	if !first_ok {
		session_close(&session)
		return
	}
	first_prepared: Prepared_Entry
	first_preparation, first_prepared_ok, first_failure := session_entry_prepare(
		&session,
		Entry_Prepare_Request {
			session = session_handle,
			kind = .Text,
			selection_label = "first",
			association = .Unassociated,
			resources = Entry_Resources {
				buffer = &first.buffer,
				history_store = &first.history_store,
				document = &first.document,
				has_document = true,
			},
			view_config = editor_view.DEFAULT_CONFIG,
		},
		&first_prepared,
	)
	testing.expect(t, first_prepared_ok)
	testing.expect_value(t, first_failure.code, Failure_Code.None)
	testing.expect_value(t, first_preparation.outcome, Admission_Outcome.Prepared)
	testing.expect(t, !editor.buffer_is_live(&first.buffer))
	testing.expect(t, !history.store_is_valid(&first.history_store))
	if !first_prepared_ok {
		test_resources_close(&first)
		session_close(&session)
		return
	}
	first_result, first_published, first_publish_failure := prepared_entry_publish(&first_prepared)
	testing.expect(t, first_published)
	testing.expect_value(t, first_publish_failure.code, Failure_Code.None)
	testing.expect_value(t, first_result.outcome, Admission_Outcome.Published)

	second, second_ok := test_resources_init(t, 2, "second")
	if !second_ok {
		return
	}
	second_prepared: Prepared_Entry
	_, second_prepared_ok, second_failure := session_entry_prepare(
		&session,
		Entry_Prepare_Request {
			session = session_handle,
			kind = .Text,
			selection_label = "second",
			association = .Unassociated,
			resources = Entry_Resources {
				buffer = &second.buffer,
				history_store = &second.history_store,
				document = &second.document,
				has_document = true,
			},
			view_config = editor_view.DEFAULT_CONFIG,
		},
		&second_prepared,
	)
	testing.expect(t, second_prepared_ok)
	testing.expect_value(t, second_failure.code, Failure_Code.None)
	if !second_prepared_ok {
		test_resources_close(&second)
		return
	}
	second_result, second_published, second_publish_failure := prepared_entry_publish(&second_prepared)
	testing.expect(t, second_published)
	testing.expect_value(t, second_publish_failure.code, Failure_Code.None)
	active_access, access_ok, access_failure := session_active_entry_access(&session, session_handle)
	testing.expect(t, access_ok)
	testing.expect_value(t, access_failure.code, Failure_Code.None)
	active_borrow, borrow_ok, borrow_failure := entry_access_borrow(active_access)
	testing.expect(t, borrow_ok)
	testing.expect_value(t, borrow_failure.code, Failure_Code.None)
	borrowed_stats, borrowed_stats_ok, _ := editor.buffer_stats(active_borrow.buffer)
	testing.expect(t, borrowed_stats_ok)
	testing.expect_value(t, borrowed_stats.buffer_id, editor.Buffer_ID(2))
	reconciled_usage, reconciled, reconcile_failure := entry_access_reconcile(active_access)
	testing.expect(t, reconciled)
	testing.expect_value(t, reconcile_failure.code, Failure_Code.None)
	testing.expect_value(t, reconciled_usage.canonical_text_bytes, u64(len("first") + len("second")))

	found_first, first_found, find_failure := session_find_label(&session, session_handle, "first")
	testing.expect(t, first_found)
	testing.expect_value(t, find_failure.code, Failure_Code.None)
	testing.expect_value(t, found_first, first_result.entry)

	activation, activated, activation_failure := session_activate(&session, first_result.entry)
	testing.expect(t, activated)
	testing.expect_value(t, activation_failure.code, Failure_Code.None)
	testing.expect(t, activation.changed)
	testing.expect_value(t, activation.visible.entry, first_result.entry)

	first_detached: Detached_Entry
	first_detachment, first_detached_ok, first_detach_failure := session_entry_detach(
		&session,
		first_result.entry,
		&first_detached,
	)
	testing.expect(t, first_detached_ok)
	testing.expect_value(t, first_detach_failure.code, Failure_Code.None)
	testing.expect(t, first_detachment.was_visible)
	testing.expect_value(t, first_detachment.successor.entry, second_result.entry)
	first_cleanup, first_cleaned, first_cleanup_failure := detached_entry_cleanup(&first_detached)
	testing.expect(t, first_cleaned)
	testing.expect_value(t, first_cleanup_failure.code, Failure_Code.None)
	testing.expect(t, first_cleanup.complete)
	first_released, first_release_failure := detached_entry_release(&first_detached)
	testing.expect(t, first_released)
	testing.expect_value(t, first_release_failure.code, Failure_Code.None)

	second_detached: Detached_Entry
	second_detachment, second_detached_ok, second_detach_failure := session_entry_detach(
		&session,
		second_result.entry,
		&second_detached,
	)
	testing.expect(t, second_detached_ok)
	testing.expect_value(t, second_detach_failure.code, Failure_Code.None)
	testing.expect_value(t, second_detachment.successor.kind, Visible_Target_Kind.None)
	_, stale_borrow_ok, stale_borrow_failure := entry_access_borrow(active_access)
	testing.expect(t, !stale_borrow_ok)
	testing.expect_value(t, stale_borrow_failure.code, Failure_Code.Stale_Entry)
	_, second_cleaned, second_cleanup_failure := detached_entry_cleanup(&second_detached)
	testing.expect(t, second_cleaned)
	testing.expect_value(t, second_cleanup_failure.code, Failure_Code.None)
	second_released, second_release_failure := detached_entry_release(&second_detached)
	testing.expect(t, second_released)
	testing.expect_value(t, second_release_failure.code, Failure_Code.None)

	usage, usage_ok, usage_failure := session_usage(&session, session_handle)
	testing.expect(t, usage_ok)
	testing.expect_value(t, usage_failure.code, Failure_Code.None)
	testing.expect_value(t, usage.live_buffers, u32(0))
	testing.expect_value(t, usage.live_documents, u32(0))
	testing.expect_value(t, usage.prepared_operations, u32(0))
	testing.expect_value(t, usage.detached_cleanup_entries, u32(0))

	closed, close_failure := session_close(&session)
	testing.expect(t, closed)
	testing.expect_value(t, close_failure.code, Failure_Code.None)
}

/* Ensures normalized document paths remain unique and release cleanly. */
@(test)
registry_indexes_one_normalized_document_path :: proc(t: ^testing.T) {
	directory, directory_error := os.make_directory_temp("", "odra-session-*", context.allocator)
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
	testing.expect(t, os.write_entire_file(path, "document") == nil)

	resources, resources_ok := test_path_resources_init(t, 9, path)
	if !resources_ok {
		return
	}
	status, status_ok, _ := document.document_status(&resources.document)
	testing.expect(t, status_ok)
	if !status_ok {
		test_resources_close(&resources)
		return
	}

	session: Session
	session_handle, initialized, _ := session_init(
		&session,
		Session_ID(73),
		Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	testing.expect(t, initialized)
	if !initialized {
		test_resources_close(&resources)
		return
	}
	prepared: Prepared_Entry
	_, prepared_ok, prepare_failure := session_entry_prepare(
		&session,
		Entry_Prepare_Request {
			session = session_handle,
			kind = .Text,
			selection_label = status.target_path,
			normalized_path = status.target_path,
			association = .Document,
			resources = Entry_Resources {
				buffer = &resources.buffer,
				history_store = &resources.history_store,
				document = &resources.document,
				has_document = true,
			},
			view_config = editor_view.DEFAULT_CONFIG,
		},
		&prepared,
	)
	testing.expect(t, prepared_ok)
	testing.expect_value(t, prepare_failure.code, Failure_Code.None)
	if !prepared_ok {
		test_resources_close(&resources)
		session_close(&session)
		return
	}
	published, published_ok, _ := prepared_entry_publish(&prepared)
	testing.expect(t, published_ok)
	found, found_ok, find_failure := session_find_path(&session, session_handle, status.target_path)
	testing.expect(t, found_ok)
	testing.expect_value(t, find_failure.code, Failure_Code.None)
	testing.expect_value(t, found, published.entry)

	detached: Detached_Entry
	_, detached_ok, _ := session_entry_detach(&session, published.entry, &detached)
	testing.expect(t, detached_ok)
	_, cleaned, _ := detached_entry_cleanup(&detached)
	testing.expect(t, cleaned)
	released, _ := detached_entry_release(&detached)
	testing.expect(t, released)
	closed, _ := session_close(&session)
	testing.expect(t, closed)
}

@(private)
test_resources_init :: proc(t: ^testing.T, ordinal: u64, contents: string) -> (resources: Test_Resources, ok: bool) {
	prepared: document.Prepared_Open
	request := document.Open_Request {
		document_id = document.Document_ID(ordinal),
		buffer_id = editor.Buffer_ID(ordinal),
		encoding = .UTF8,
	}
	prepared_ok, prepared_failure := document.open_prepare(
		&prepared,
		request,
		document.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	testing.expect(t, prepared_ok)
	if !prepared_ok {
		_ = prepared_failure
		return {}, false
	}
	buffer_ok, _ := editor.buffer_init(
		&resources.buffer,
		request.buffer_id,
		contents,
		editor.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	if !buffer_ok {
		document.prepared_open_abort(&prepared)
		return {}, false
	}
	document_ok, _ := document.prepared_open_commit(
		&prepared,
		&resources.document,
		editor.Revision(0),
	)
	if !document_ok {
		editor.buffer_close(&resources.buffer)
		return {}, false
	}
	history_ok, _ := history.store_init(
		&resources.history_store,
		history.Store_ID(ordinal),
		request.buffer_id,
		editor.Revision(0),
		history.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	if !history_ok {
		document.document_close(&resources.document)
		editor.buffer_close(&resources.buffer)
		return {}, false
	}
	return resources, true
}

@(private)
test_path_resources_init :: proc(t: ^testing.T, ordinal: u64, path: string) -> (resources: Test_Resources, ok: bool) {
	prepared: document.Prepared_Open
	request := document.Open_Request {
		document_id = document.Document_ID(ordinal),
		buffer_id = editor.Buffer_ID(ordinal),
		has_path = true,
		path = path,
		encoding = .UTF8,
	}
	prepared_ok, _ := document.open_prepare(
		&prepared,
		request,
		document.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	testing.expect(t, prepared_ok)
	if !prepared_ok {
		return {}, false
	}
	view, viewed, _ := document.prepared_open_view(&prepared)
	testing.expect(t, viewed)
	if !viewed {
		document.prepared_open_abort(&prepared)
		return {}, false
	}
	buffer_ok, _ := editor.buffer_init(
		&resources.buffer,
		request.buffer_id,
		view.contents,
		editor.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	if !buffer_ok {
		document.prepared_open_abort(&prepared)
		return {}, false
	}
	document_ok, _ := document.prepared_open_commit(
		&prepared,
		&resources.document,
		editor.Revision(0),
	)
	if !document_ok {
		editor.buffer_close(&resources.buffer)
		return {}, false
	}
	history_ok, _ := history.store_init(
		&resources.history_store,
		history.Store_ID(ordinal),
		request.buffer_id,
		editor.Revision(0),
		history.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	if !history_ok {
		document.document_close(&resources.document)
		editor.buffer_close(&resources.buffer)
		return {}, false
	}
	return resources, true
}

@(private)
test_resources_close :: proc(resources: ^Test_Resources) {
	if history.store_is_valid(&resources.history_store) {
		history.store_close(&resources.history_store)
	}
	status, document_live, _ := document.document_status(&resources.document)
	_ = status
	if document_live {
		document.document_close(&resources.document)
	}
	if editor.buffer_is_live(&resources.buffer) {
		editor.buffer_close(&resources.buffer)
	}
}
