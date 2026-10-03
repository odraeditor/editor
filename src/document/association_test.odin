// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package document

import "../editor"
import "core:mem"
import "core:os"
import "core:testing"

/* Verifies a private path becomes observable only after first-save publication. */
@(test)
unassociated_docs_materialize_after_publish :: proc(t: ^testing.T) {
	fixture, ready := association_fixture_init(t, "first text")
	if !ready {
		return
	}
	defer association_fixture_close(&fixture)
	prepared: Prepared_Association
	prepared_ok, prepare_failure := document_association_prepare(
		&fixture.document,
		fixture.file_path,
		&prepared,
		default_test_allocators(),
	)
	testing.expectf(t, prepared_ok, "association prepare failed with %v", prepare_failure.code)
	if !prepared_ok {
		return
	}
	status, status_ok, _ := document_status(&fixture.document)
	testing.expect(t, status_ok)
	testing.expect_value(t, status.persistence, Persistence_State.Unassociated)
	testing.expect(t, !status.has_target)
	_, stat_error := os.lstat(fixture.file_path, context.temp_allocator)
	testing.expect(t, stat_error != nil)

	result, published, publish_failure := prepared_association_publish(&prepared, &fixture.buffer)
	testing.expectf(t, published, "association publish failed with %v", publish_failure.code)
	testing.expect_value(t, result.publication, Publication_State.Published_Durable)
	testing.expect_value(t, save_read_file(t, fixture.file_path), "first text")
	status, status_ok, _ = document_status(&fixture.document)
	testing.expect(t, status_ok)
	testing.expect(t, status.has_target && status.materialized)
	testing.expect_value(t, status.persistence, Persistence_State.Clean)
	testing.expect_value(t, status.target_path, fixture.file_path)
}

/* Verifies cancellation releases a private target without creating or associating it. */
@(test)
cancelled_association_keeps_unassociated :: proc(t: ^testing.T) {
	fixture, ready := association_fixture_init(t, "unsaved")
	if !ready {
		return
	}
	defer association_fixture_close(&fixture)
	prepared: Prepared_Association
	prepared_ok, _ := document_association_prepare(
		&fixture.document,
		fixture.file_path,
		&prepared,
		default_test_allocators(),
	)
	testing.expect(t, prepared_ok)
	if !prepared_ok {
		return
	}
	aborted, abort_failure := prepared_association_abort(&prepared)
	testing.expectf(t, aborted, "association abort failed with %v", abort_failure.code)
	status, status_ok, _ := document_status(&fixture.document)
	testing.expect(t, status_ok)
	testing.expect_value(t, status.persistence, Persistence_State.Unassociated)
	testing.expect(t, !status.has_target)
	_, stat_error := os.lstat(fixture.file_path, context.temp_allocator)
	testing.expect(t, stat_error != nil)
}

/* Verifies rejected paths and pre-publication races preserve unassociated state. */
@(test)
association_races_publish_no_partial_state :: proc(t: ^testing.T) {
	fixture, ready := association_fixture_init(t, "unsaved")
	if !ready {
		return
	}
	defer association_fixture_close(&fixture)
	prepared: Prepared_Association
	invalid_ok, invalid_failure := document_association_prepare(
		&fixture.document,
		"",
		&prepared,
		default_test_allocators(),
	)
	testing.expect(t, !invalid_ok)
	testing.expect_value(t, invalid_failure.code, Failure_Code.Path_Empty)

	prepared_ok, _ := document_association_prepare(
		&fixture.document,
		fixture.file_path,
		&prepared,
		default_test_allocators(),
	)
	testing.expect(t, prepared_ok)
	if !prepared_ok {
		return
	}
	testing.expect(t, os.make_directory(fixture.file_path) == nil)
	result, published, publish_failure := prepared_association_publish(&prepared, &fixture.buffer)
	testing.expect(t, !published)
	testing.expect_value(t, result.publication, Publication_State.Not_Published)
	testing.expect_value(t, publish_failure.code, Failure_Code.Target_Not_Regular)
	status, status_ok, _ := document_status(&fixture.document)
	testing.expect(t, status_ok)
	testing.expect_value(t, status.persistence, Persistence_State.Unassociated)
	testing.expect(t, !status.has_target)
}

/* Verifies a regular target created after naming is observed and authoritatively replaced. */
@(test)
target_races_are_observed_and_overwritten :: proc(t: ^testing.T) {
	fixture, ready := association_fixture_init(t, "authoritative")
	if !ready {
		return
	}
	defer association_fixture_close(&fixture)
	prepared: Prepared_Association
	prepared_ok, _ := document_association_prepare(
		&fixture.document,
		fixture.file_path,
		&prepared,
		default_test_allocators(),
	)
	testing.expect(t, prepared_ok)
	if !prepared_ok {
		return
	}
	testing.expect(t, os.write_entire_file(fixture.file_path, "raced") == nil)
	result, published, failure := prepared_association_publish(&prepared, &fixture.buffer)
	testing.expectf(t, published, "raced association failed with %v", failure.code)
	testing.expect(t, result.external_change_observed)
	testing.expect_value(t, save_read_file(t, fixture.file_path), "authoritative")
}

/* Verifies candidate allocation failures and abort release all private storage. */
@(test)
association_storage_is_bounded_and_released :: proc(t: ^testing.T) {
	fixture, ready := association_fixture_init(t, "tracked")
	if !ready {
		return
	}
	defer association_fixture_close(&fixture)
	for fail_after in 0 ..< 2 {
		tracking: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracking, context.allocator)
		failing := Open_Failing_Allocator {
			backing = mem.tracking_allocator(&tracking),
			fail_after = u64(fail_after),
		}
		prepared: Prepared_Association
		prepared_ok, failure := document_association_prepare(
			&fixture.document,
			fixture.file_path,
			&prepared,
			Allocator_Set {
				persistent = open_failing_allocator(&failing),
				temporary = context.temp_allocator,
			},
		)
		testing.expect(t, !prepared_ok)
		testing.expect_value(t, failure.code, Failure_Code.Persistent_Memory_Limit)
		testing.expect(t, prepared.state == nil)
		testing.expect_value(t, tracking.current_memory_allocated, i64(0))
		mem.tracking_allocator_destroy(&tracking)
	}
}

@(private)
Association_Fixture :: struct {
	directory: string,
	file_path: string,
	document:  Document,
	buffer:    editor.Buffer,
}

@(private)
association_fixture_init :: proc(t: ^testing.T, contents: string) -> (Association_Fixture, bool) {
	fixture: Association_Fixture
	directory, directory_error := os.make_directory_temp("", "odra-association-*", context.allocator)
	testing.expect(t, directory_error == nil)
	if directory_error != nil {
		return {}, false
	}
	fixture.directory = directory
	fixture.file_path = open_join(directory, "document.txt")
	prepared: Prepared_Open
	request := open_request("")
	request.has_path = false
	opened, open_failure := open_prepare(&prepared, request, default_test_allocators())
	testing.expectf(t, opened, "unassociated open failed with %v", open_failure.code)
	if !opened {
		association_fixture_close(&fixture)
		return {}, false
	}
	buffer_ok, buffer_failure := editor.buffer_init(
		&fixture.buffer,
		editor.Buffer_ID(1),
		contents,
		editor.Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	testing.expectf(t, buffer_ok, "association buffer failed with %v", buffer_failure.code)
	if !buffer_ok {
		prepared_open_abort(&prepared)
		association_fixture_close(&fixture)
		return {}, false
	}
	committed, commit_failure := prepared_open_commit(&prepared, &fixture.document, editor.Revision(0))
	testing.expectf(t, committed, "association document failed with %v", commit_failure.code)
	if !committed {
		_, _ = editor.buffer_close(&fixture.buffer)
		prepared_open_abort(&prepared)
		association_fixture_close(&fixture)
		return {}, false
	}
	return fixture, true
}

@(private)
association_fixture_close :: proc(fixture: ^Association_Fixture) {
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
