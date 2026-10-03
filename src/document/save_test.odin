// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package document

import "../editor"
import "core:mem"
import "core:os"
import "core:testing"

/* Verifies durable replacement preserves exact UTF-8 bytes and current target permissions. */
@(test)
associated_docs_publish_revisions_atomically :: proc(t: ^testing.T) {
	fixture, ready := save_fixture_init(t, true, "old text")
	if !ready {
		return
	}
	defer save_fixture_close(&fixture)
	opened_metadata, opened_metadata_error := linux_inspect(fixture.file_path, false, context.temp_allocator)
	testing.expect(t, opened_metadata_error.code == .None)
	changed_mode := 0o600 if opened_metadata.mode != 0o600 else 0o640
	testing.expect(t, os.change_mode(fixture.file_path, os.perm_number(changed_mode)) == nil)
	testing.expect(t, save_replace_buffer(t, &fixture.buffer, "new \U0001F642 text\n"))

	prepared: Prepared_Save
	prepared_ok, prepare_failure := save_prepare(&fixture.document, &fixture.buffer, &prepared)
	testing.expectf(t, prepared_ok, "save prepare failed with %v", prepare_failure.code)
	if !prepared_ok {
		return
	}
	result, published, publish_failure := prepared_save_publish(&prepared)
	testing.expectf(t, published, "save publish failed with %v", publish_failure.code)
	testing.expect_value(t, result.publication, Publication_State.Published_Durable)
	testing.expect_value(t, result.saved_revision, editor.Revision(1))
	testing.expect(t, result.external_change_observed)
	testing.expect_value(t, save_read_file(t, fixture.file_path), "new \U0001F642 text\n")
	metadata, metadata_error := linux_inspect(fixture.file_path, false, context.temp_allocator)
	testing.expect(t, metadata_error.code == .None)
	testing.expect_value(t, metadata.mode, u32(changed_mode))
	status, status_ok, _ := document_status(&fixture.document)
	testing.expect(t, status_ok)
	testing.expect_value(t, status.persistence, Persistence_State.Clean)
	testing.expect(t, status.materialized && status.has_saved_revision)
}

/* Verifies a privately associated missing target becomes materialized only after publication. */
@(test)
unmaterialized_associations_publish_new_files :: proc(t: ^testing.T) {
	fixture, ready := save_fixture_init(t, false, "")
	if !ready {
		return
	}
	defer save_fixture_close(&fixture)
	testing.expect(t, save_replace_buffer(t, &fixture.buffer, "first materialization"))
	prepared: Prepared_Save
	prepared_ok, _ := save_prepare(&fixture.document, &fixture.buffer, &prepared)
	testing.expect(t, prepared_ok)
	if !prepared_ok {
		return
	}
	result, published, failure := prepared_save_publish(&prepared)
	testing.expectf(t, published, "new target publish failed with %v", failure.code)
	testing.expect_value(t, result.publication, Publication_State.Published_Durable)
	testing.expect_value(t, save_read_file(t, fixture.file_path), "first materialization")
	status, status_ok, _ := document_status(&fixture.document)
	testing.expect(t, status_ok)
	testing.expect(t, status.materialized)
	testing.expect_value(t, status.persistence, Persistence_State.Clean)
}

/* Verifies explicit save observes but overwrites an externally replaced regular target. */
@(test)
save_reports_external_replacement :: proc(t: ^testing.T) {
	fixture, ready := save_fixture_init(t, true, "opened")
	if !ready {
		return
	}
	defer save_fixture_close(&fixture)
	testing.expect(t, os.write_entire_file(fixture.file_path, "external") == nil)
	testing.expect(t, save_replace_buffer(t, &fixture.buffer, "authoritative"))
	prepared: Prepared_Save
	prepared_ok, _ := save_prepare(&fixture.document, &fixture.buffer, &prepared)
	testing.expect(t, prepared_ok)
	if !prepared_ok {
		return
	}
	result, published, failure := prepared_save_publish(&prepared)
	testing.expectf(t, published, "authoritative save failed with %v", failure.code)
	testing.expect(t, result.external_change_observed)
	testing.expect_value(t, save_read_file(t, fixture.file_path), "authoritative")
}

/* Verifies an edit newer than the retained save revision remains modified after publication. */
@(test)
older_snapshot_keeps_newer_edits_modified :: proc(t: ^testing.T) {
	fixture, ready := save_fixture_init(t, true, "base")
	if !ready {
		return
	}
	defer save_fixture_close(&fixture)
	testing.expect(t, save_replace_buffer(t, &fixture.buffer, "captured"))
	prepared: Prepared_Save
	prepared_ok, _ := save_prepare(&fixture.document, &fixture.buffer, &prepared)
	testing.expect(t, prepared_ok)
	if !prepared_ok {
		return
	}
	testing.expect(t, save_replace_buffer(t, &fixture.buffer, "newer edit"))
	result, published, failure := prepared_save_publish(&prepared)
	testing.expectf(t, published, "older snapshot publish failed with %v", failure.code)
	testing.expect_value(t, result.saved_revision, editor.Revision(1))
	testing.expect_value(t, save_read_file(t, fixture.file_path), "captured")
	status, status_ok, _ := document_status(&fixture.document)
	testing.expect(t, status_ok)
	testing.expect_value(t, status.saved_revision, editor.Revision(1))
	testing.expect_value(t, status.persistence, Persistence_State.Modified)
}

/* Verifies pre-publication write failure preserves the prior target and releases the save. */
@(test)
write_failures_leave_existing_targets_unchanged :: proc(t: ^testing.T) {
	fixture, ready := save_fixture_init(t, true, "stable target")
	if !ready {
		return
	}
	defer save_fixture_close(&fixture)
	testing.expect(t, save_replace_buffer(t, &fixture.buffer, "must not publish"))
	io := linux_save_io()
	io.write = injected_write_failure
	prepared: Prepared_Save
	prepared_ok, _ := save_prepare_with_io(
		&fixture.document,
		&fixture.buffer,
		&prepared,
		DEFAULT_LIMITS,
		io,
	)
	testing.expect(t, prepared_ok)
	if !prepared_ok {
		return
	}
	result, published, failure := prepared_save_publish(&prepared)
	testing.expect(t, !published)
	testing.expect_value(t, result.publication, Publication_State.Not_Published)
	testing.expect_value(t, failure.code, Failure_Code.Write_Failed)
	testing.expect_value(t, failure.publication, Publication_State.Not_Published)
	testing.expect_value(t, save_read_file(t, fixture.file_path), "stable target")
	testing.expect(t, prepared.state == nil)
	status, status_ok, _ := document_status(&fixture.document)
	testing.expect(t, status_ok)
	testing.expect_value(t, status.persistence, Persistence_State.Modified)
}

/* Verifies directory-sync failure reports an already published target with uncertain durability. */
@(test)
dir_sync_failures_report_published_uncertainty :: proc(t: ^testing.T) {
	fixture, ready := save_fixture_init(t, true, "before")
	if !ready {
		return
	}
	defer save_fixture_close(&fixture)
	testing.expect(t, save_replace_buffer(t, &fixture.buffer, "published"))
	io := linux_save_io()
	io.sync = injected_directory_sync_failure
	prepared: Prepared_Save
	prepared_ok, _ := save_prepare_with_io(
		&fixture.document,
		&fixture.buffer,
		&prepared,
		DEFAULT_LIMITS,
		io,
	)
	testing.expect(t, prepared_ok)
	if !prepared_ok {
		return
	}
	result, durable, failure := prepared_save_publish(&prepared)
	testing.expect(t, !durable)
	testing.expect_value(t, result.publication, Publication_State.Published_Durability_Uncertain)
	testing.expect_value(t, failure.code, Failure_Code.Directory_Sync_Failed)
	testing.expect_value(t, failure.publication, Publication_State.Published_Durability_Uncertain)
	testing.expect_value(t, save_read_file(t, fixture.file_path), "published")
	status, status_ok, _ := document_status(&fixture.document)
	testing.expect(t, status_ok)
	testing.expect_value(t, status.persistence, Persistence_State.Clean)
}

/* Verifies bounded short writes stream the complete immutable snapshot. */
@(test)
short_writes_publish_complete_snapshots :: proc(t: ^testing.T) {
	fixture, ready := save_fixture_init(t, true, "old")
	if !ready {
		return
	}
	defer save_fixture_close(&fixture)
	replacement: [IO_CHUNK_BYTES + 257]byte
	for index in 0 ..< len(replacement) {
		replacement[index] = byte('a' + index % 26)
	}
	testing.expect(t, save_replace_buffer(t, &fixture.buffer, string(replacement[:])))
	io := linux_save_io()
	io.write = injected_short_write
	prepared: Prepared_Save
	prepared_ok, _ := save_prepare_with_io(&fixture.document, &fixture.buffer, &prepared, DEFAULT_LIMITS, io)
	testing.expect(t, prepared_ok)
	if !prepared_ok {
		return
	}
	_, published, failure := prepared_save_publish(&prepared)
	testing.expectf(t, published, "short-write save failed with %v", failure.code)
	actual := save_read_file(t, fixture.file_path)
	testing.expect(t, actual == string(replacement[:]))
}

/* Verifies interrupted writes exhaust the configured no-progress bound without publication. */
@(test)
interrupted_writes_bound_before_publish :: proc(t: ^testing.T) {
	fixture, ready := save_fixture_init(t, true, "stable")
	if !ready {
		return
	}
	defer save_fixture_close(&fixture)
	testing.expect(t, save_replace_buffer(t, &fixture.buffer, "replacement"))
	io := linux_save_io()
	io.write = injected_interrupted_write
	prepared: Prepared_Save
	prepared_ok, _ := save_prepare_with_io(&fixture.document, &fixture.buffer, &prepared, DEFAULT_LIMITS, io)
	testing.expect(t, prepared_ok)
	if !prepared_ok {
		return
	}
	result, published, failure := prepared_save_publish(&prepared)
	testing.expect(t, !published)
	testing.expect_value(t, result.publication, Publication_State.Not_Published)
	testing.expect_value(t, failure.code, Failure_Code.Work_Limit)
	testing.expect_value(t, failure.actual, u64(MAX_INTERRUPTED_IO_RETRIES + 1))
	testing.expect_value(t, save_read_file(t, fixture.file_path), "stable")
}

/* Verifies file-sync and rename failures each preserve the prior target. */
@(test)
file_sync_and_rename_failures_do_not_publish :: proc(t: ^testing.T) {
	fixture, ready := save_fixture_init(t, true, "prior")
	if !ready {
		return
	}
	defer save_fixture_close(&fixture)
	testing.expect(t, save_replace_buffer(t, &fixture.buffer, "candidate"))

	file_sync_io := linux_save_io()
	file_sync_io.sync = injected_file_sync_failure
	prepared: Prepared_Save
	prepared_ok, _ := save_prepare_with_io(
		&fixture.document,
		&fixture.buffer,
		&prepared,
		DEFAULT_LIMITS,
		file_sync_io,
	)
	testing.expect(t, prepared_ok)
	if !prepared_ok {
		return
	}
	_, published, failure := prepared_save_publish(&prepared)
	testing.expect(t, !published)
	testing.expect_value(t, failure.code, Failure_Code.File_Sync_Failed)
	testing.expect_value(t, save_read_file(t, fixture.file_path), "prior")

	rename_io := linux_save_io()
	rename_io.rename = injected_rename_failure
	prepared_ok, _ = save_prepare_with_io(
		&fixture.document,
		&fixture.buffer,
		&prepared,
		DEFAULT_LIMITS,
		rename_io,
	)
	testing.expect(t, prepared_ok)
	if !prepared_ok {
		return
	}
	_, published, failure = prepared_save_publish(&prepared)
	testing.expect(t, !published)
	testing.expect_value(t, failure.code, Failure_Code.Rename_Failed)
	testing.expect_value(t, save_read_file(t, fixture.file_path), "prior")
}

/* Verifies cleanup failure is explicit while the authoritative target remains unchanged. */
@(test)
temporary_cleanup_failures_are_reported :: proc(t: ^testing.T) {
	fixture, ready := save_fixture_init(t, true, "prior")
	if !ready {
		return
	}
	defer save_fixture_close(&fixture)
	testing.expect(t, save_replace_buffer(t, &fixture.buffer, "candidate"))
	io := linux_save_io()
	io.write = injected_write_failure
	io.unlink = injected_unlink_failure
	prepared: Prepared_Save
	prepared_ok, _ := save_prepare_with_io(&fixture.document, &fixture.buffer, &prepared, DEFAULT_LIMITS, io)
	testing.expect(t, prepared_ok)
	if !prepared_ok {
		return
	}
	result, published, failure := prepared_save_publish(&prepared)
	testing.expect(t, !published)
	testing.expect_value(t, result.publication, Publication_State.Not_Published)
	testing.expect_value(t, failure.code, Failure_Code.Cleanup_Failed)
	testing.expect_value(t, save_read_file(t, fixture.file_path), "prior")
}

/* Verifies save-state allocation failure publishes no operation and leaks no document storage. */
@(test)
save_allocation_failure_preserves_document_state :: proc(t: ^testing.T) {
	directory, directory_error := os.make_directory_temp("", "odra-save-allocation-*", context.allocator)
	testing.expect(t, directory_error == nil)
	if directory_error != nil {
		return
	}
	defer {
		os.remove_all(directory)
		delete(directory)
	}
	path := open_join(directory, "document.txt")
	defer delete(path)
	testing.expect(t, os.write_entire_file(path, "tracked") == nil)
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	failing := Open_Failing_Allocator {
		backing = mem.tracking_allocator(&tracking),
		fail_after = max(u64),
	}
	prepared_open: Prepared_Open
	opened, open_failure := open_prepare(
		&prepared_open,
		open_request(path),
		Allocator_Set {
			persistent = open_failing_allocator(&failing),
			temporary = context.temp_allocator,
		},
	)
	testing.expectf(t, opened, "tracked open failed with %v", open_failure.code)
	if !opened {
		return
	}
	view, viewed, _ := prepared_open_view(&prepared_open)
	testing.expect(t, viewed)
	buffer: editor.Buffer
	buffer_ok, _ := editor.buffer_init(
		&buffer,
		editor.Buffer_ID(1),
		view.contents,
		editor.Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, buffer_ok)
	if !buffer_ok {
		prepared_open_abort(&prepared_open)
		return
	}
	document: Document
	committed, _ := prepared_open_commit(&prepared_open, &document, editor.Revision(0))
	testing.expect(t, committed)
	if !committed {
		_, _ = editor.buffer_close(&buffer)
		prepared_open_abort(&prepared_open)
		return
	}
	failing.fail_after = failing.successful_allocations
	prepared_save: Prepared_Save
	prepared_ok, failure := save_prepare(&document, &buffer, &prepared_save)
	testing.expect(t, !prepared_ok)
	testing.expect_value(t, failure.code, Failure_Code.Persistent_Memory_Limit)
	testing.expect(t, prepared_save.state == nil)
	document_closed, _ := document_close(&document)
	buffer_closed, _ := editor.buffer_close(&buffer)
	testing.expect(t, document_closed && buffer_closed)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
}

@(private)
Save_Fixture :: struct {
	directory: string,
	file_path: string,
	document:  Document,
	buffer:    editor.Buffer,
}

@(private)
save_fixture_init :: proc(t: ^testing.T, materialized: bool, contents: string) -> (Save_Fixture, bool) {
	fixture: Save_Fixture
	directory, directory_error := os.make_directory_temp("", "odra-save-*", context.allocator)
	testing.expect(t, directory_error == nil)
	if directory_error != nil {
		return {}, false
	}
	fixture.directory = directory
	fixture.file_path = open_join(directory, "document.txt")
	if materialized {
		written := os.write_entire_file(fixture.file_path, contents)
		testing.expect(t, written == nil)
		if written != nil {
			save_fixture_close(&fixture)
			return {}, false
		}
	}
	prepared: Prepared_Open
	opened, open_failure := open_prepare(
		&prepared,
		open_request(fixture.file_path),
		default_test_allocators(),
	)
	testing.expectf(t, opened, "fixture open failed with %v", open_failure.code)
	if !opened {
		save_fixture_close(&fixture)
		return {}, false
	}
	view, viewed, _ := prepared_open_view(&prepared)
	testing.expect(t, viewed)
	initialized, editor_failure := editor.buffer_init(
		&fixture.buffer,
		editor.Buffer_ID(1),
		view.contents,
		editor.Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	testing.expectf(t, initialized, "fixture buffer failed with %v", editor_failure.code)
	if !initialized {
		prepared_open_abort(&prepared)
		save_fixture_close(&fixture)
		return {}, false
	}
	committed, commit_failure := prepared_open_commit(&prepared, &fixture.document, editor.Revision(0))
	testing.expectf(t, committed, "fixture commit failed with %v", commit_failure.code)
	if !committed {
		_, _ = editor.buffer_close(&fixture.buffer)
		prepared_open_abort(&prepared)
		save_fixture_close(&fixture)
		return {}, false
	}
	return fixture, true
}

@(private)
save_fixture_close :: proc(fixture: ^Save_Fixture) {
	if fixture.document.state != nil {
		_, _ = document_close(&fixture.document)
	}
	if editor.buffer_is_live(&fixture.buffer) {
		_, _ = editor.buffer_close(&fixture.buffer)
	}
	if len(fixture.directory) > 0 {
		os.remove_all(fixture.directory)
	}
	if len(fixture.file_path) > 0 {
		delete(fixture.file_path)
	}
	if len(fixture.directory) > 0 {
		delete(fixture.directory)
	}
	fixture^ = {}
}

@(private)
save_replace_buffer :: proc(t: ^testing.T, buffer: ^editor.Buffer, replacement: string) -> bool {
	stats, stats_ok, stats_failure := editor.buffer_stats(buffer)
	testing.expectf(t, stats_ok, "buffer stats failed with %v", stats_failure.code)
	if !stats_ok {
		return false
	}
	start, start_ok, _ := editor.buffer_position(buffer, editor.Byte_Offset(0))
	end, end_ok, _ := editor.buffer_position(buffer, editor.Byte_Offset(stats.text_bytes))
	if !start_ok || !end_ok {
		return false
	}
	_, _, published, failure := editor.buffer_splice(
		buffer,
		editor.Splice{start = start, end = end, replacement = replacement},
		context.temp_allocator,
	)
	testing.expectf(t, published, "buffer replacement failed with %v", failure.code)
	return published
}

@(private)
save_read_file :: proc(t: ^testing.T, path: string) -> string {
	bytes, read_error := os.read_entire_file(path, context.temp_allocator)
	testing.expect(t, read_error == nil)
	if read_error != nil {
		return ""
	}
	return string(bytes)
}

@(private)
injected_write_failure :: proc(handle: Platform_Handle, source: []u8) -> (int, Platform_Error) {
	_ = handle
	_ = source
	return 0, Platform_Error{code = .Other, platform_code = 5}
}

@(private)
injected_directory_sync_failure :: proc(handle: Platform_Handle) -> Platform_Error {
	metadata, metadata_error := linux_inspect_handle(handle)
	if metadata_error.code != .None {
		return metadata_error
	}
	if metadata.kind == .Directory {
		return Platform_Error{code = .Other, platform_code = 5}
	}
	return linux_sync(handle)
}

@(private)
injected_short_write :: proc(handle: Platform_Handle, source: []u8) -> (int, Platform_Error) {
	return linux_write(handle, source[:min(len(source), 7)])
}

@(private)
injected_interrupted_write :: proc(handle: Platform_Handle, source: []u8) -> (int, Platform_Error) {
	_ = handle
	_ = source
	return 0, Platform_Error{code = .Interrupted, platform_code = 4}
}

@(private)
injected_file_sync_failure :: proc(handle: Platform_Handle) -> Platform_Error {
	metadata, metadata_error := linux_inspect_handle(handle)
	if metadata_error.code != .None {
		return metadata_error
	}
	if metadata.kind == .Regular {
		return Platform_Error{code = .Other, platform_code = 5}
	}
	return linux_sync(handle)
}

@(private)
injected_rename_failure :: proc(old_path, new_path: string) -> Platform_Error {
	_ = old_path
	_ = new_path
	return Platform_Error{code = .Other, platform_code = 5}
}

@(private)
injected_unlink_failure :: proc(path: string) -> Platform_Error {
	_ = path
	return Platform_Error{code = .Other, platform_code = 5}
}
