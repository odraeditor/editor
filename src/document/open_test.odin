// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package document

import "../editor"
import "base:runtime"
import "core:mem"
import "core:os"
import "core:testing"

/* Verifies an existing file is prepared exactly and committed as a clean document. */
@(test)
existing_utf8_file_opens_without_byte_rewriting :: proc(t: ^testing.T) {
	fixture, ready := open_fixture_init(t)
	if !ready {
		return
	}
	defer open_fixture_close(&fixture)
	contents := "\uFEFFalpha\r\nsmile: \U0001F642\r"
	written := os.write_entire_file(fixture.file_path, contents)
	testing.expect(t, written == nil)
	if written != nil {
		return
	}

	prepared: Prepared_Open
	opened, failure := open_prepare(
		&prepared,
		open_request(fixture.file_path),
		default_test_allocators(),
	)
	testing.expectf(t, opened, "open failed with %v", failure.code)
	if !opened {
		return
	}
	view, viewed, view_failure := prepared_open_view(&prepared)
	testing.expectf(t, viewed, "view failed with %v", view_failure.code)
	testing.expect_value(t, view.kind, Open_Kind.Materialized)
	testing.expect_value(t, view.contents, contents)
	testing.expect(t, view.observation.exists)
	testing.expect_value(t, view.observation.encoded_bytes, u64(len(contents)))
	testing.expect(t, view.path[0] == '/')

	document: Document
	committed, commit_failure := prepared_open_commit(&prepared, &document, editor.Revision(0))
	testing.expectf(t, committed, "commit failed with %v", commit_failure.code)
	if !committed {
		prepared_open_abort(&prepared)
		return
	}
	status, status_ok, _ := document_status(&document)
	testing.expect(t, status_ok)
	testing.expect_value(t, status.persistence, Persistence_State.Clean)
	testing.expect_value(t, status.target_path, view.path)
	testing.expect(t, status.materialized && status.has_saved_revision)
	closed, _ := document_close(&document)
	testing.expect(t, closed)
}

/* Verifies absent targets and pathless startup publish no external file. */
@(test)
empty_startup_states_do_not_materialize_targets :: proc(t: ^testing.T) {
	fixture, ready := open_fixture_init(t)
	if !ready {
		return
	}
	defer open_fixture_close(&fixture)

	missing: Prepared_Open
	missing_ok, missing_failure := open_prepare(
		&missing,
		open_request(fixture.file_path),
		default_test_allocators(),
	)
	testing.expectf(t, missing_ok, "missing target failed with %v", missing_failure.code)
	missing_view, viewed, _ := prepared_open_view(&missing)
	testing.expect(t, viewed)
	testing.expect_value(t, missing_view.kind, Open_Kind.Unmaterialized)
	testing.expect_value(t, missing_view.contents, "")
	_, stat_error := os.lstat(fixture.file_path, context.temp_allocator)
	testing.expect(t, stat_error != nil)
	missing_aborted, _ := prepared_open_abort(&missing)
	testing.expect(t, missing_aborted)

	unassociated: Prepared_Open
	request := open_request("")
	request.has_path = false
	unassociated_ok, _ := open_prepare(&unassociated, request, default_test_allocators())
	testing.expect(t, unassociated_ok)
	unassociated_view, unassociated_viewed, _ := prepared_open_view(&unassociated)
	testing.expect(t, unassociated_viewed)
	testing.expect_value(t, unassociated_view.kind, Open_Kind.Unassociated)
	document: Document
	committed, _ := prepared_open_commit(&unassociated, &document, editor.Revision(0))
	testing.expect(t, committed)
	status, status_ok, _ := document_status(&document)
	testing.expect(t, status_ok)
	testing.expect_value(t, status.persistence, Persistence_State.Unassociated)
	testing.expect(t, !status.has_target && !status.has_saved_revision)
	document_close(&document)
}

/* Verifies malformed text and unsupported final components leave no candidate. */
@(test)
rejects_unsupported_targets_atomically :: proc(t: ^testing.T) {
	fixture, ready := open_fixture_init(t)
	if !ready {
		return
	}
	defer open_fixture_close(&fixture)

	invalid_bytes := []u8{'a', 0xff, 'b'}
	testing.expect(t, os.write_entire_file(fixture.file_path, invalid_bytes) == nil)
	prepared: Prepared_Open
	opened, failure := open_prepare(
		&prepared,
		open_request(fixture.file_path),
		default_test_allocators(),
	)
	testing.expect(t, !opened)
	testing.expect_value(t, failure.code, Failure_Code.Malformed_UTF8)
	testing.expect_value(t, failure.byte_offset, u64(1))
	testing.expect(t, prepared.state == nil)

	directory_path := open_join(fixture.directory, "directory")
	defer delete(directory_path)
	testing.expect(t, os.make_directory(directory_path) == nil)
	directory_opened, directory_failure := open_prepare(
		&prepared,
		open_request(directory_path),
		default_test_allocators(),
	)
	testing.expect(t, !directory_opened)
	testing.expect_value(t, directory_failure.code, Failure_Code.Target_Not_Regular)

	link_path := open_join(fixture.directory, "link")
	defer delete(link_path)
	testing.expect(t, os.symlink(fixture.file_path, link_path) == nil)
	link_opened, link_failure := open_prepare(
		&prepared,
		open_request(link_path),
		default_test_allocators(),
	)
	testing.expect(t, !link_opened)
	testing.expect_value(t, link_failure.code, Failure_Code.Target_Is_Symbolic_Link)
}

/* Verifies persistent allocation failures release every private open candidate byte. */
@(test)
allocation_failures_leave_no_persistent_storage :: proc(t: ^testing.T) {
	fixture, ready := open_fixture_init(t)
	if !ready {
		return
	}
	defer open_fixture_close(&fixture)
	testing.expect(t, os.write_entire_file(fixture.file_path, "allocated") == nil)

	for fail_after in 0 ..< 3 {
		tracking: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracking, context.allocator)
		failing := Open_Failing_Allocator {
			backing = mem.tracking_allocator(&tracking),
			fail_after = u64(fail_after),
		}
		prepared: Prepared_Open
		opened, failure := open_prepare(
			&prepared,
			open_request(fixture.file_path),
			Allocator_Set {
				persistent = open_failing_allocator(&failing),
				temporary = context.temp_allocator,
			},
		)
		testing.expectf(t, !opened, "allocation %d unexpectedly passed", fail_after)
		testing.expect_value(t, failure.code, Failure_Code.Persistent_Memory_Limit)
		testing.expect(t, prepared.state == nil)
		testing.expect_value(t, tracking.current_memory_allocated, i64(0))
		mem.tracking_allocator_destroy(&tracking)
	}
}

/* Verifies injected reads and interrupted retry exhaustion preserve a zero candidate. */
@(test)
open_io_failures_are_bounded_and_atomic :: proc(t: ^testing.T) {
	fixture, ready := open_fixture_init(t)
	if !ready {
		return
	}
	defer open_fixture_close(&fixture)
	testing.expect(t, os.write_entire_file(fixture.file_path, "read failure") == nil)

	io := linux_open_io()
	io.read = injected_read_failure
	prepared: Prepared_Open
	opened, failure := open_prepare_with_io(
		&prepared,
		open_request(fixture.file_path),
		default_test_allocators(),
		DEFAULT_LIMITS,
		io,
	)
	testing.expect(t, !opened)
	testing.expect_value(t, failure.code, Failure_Code.Read_Failed)
	testing.expect_value(t, failure.platform_code, i32(5))
	testing.expect(t, prepared.state == nil)

	io = linux_open_io()
	io.read = injected_interrupted_read
	opened, failure = open_prepare_with_io(
		&prepared,
		open_request(fixture.file_path),
		default_test_allocators(),
		DEFAULT_LIMITS,
		io,
	)
	testing.expect(t, !opened)
	testing.expect_value(t, failure.code, Failure_Code.Work_Limit)
	testing.expect_value(t, failure.actual, u64(MAX_INTERRUPTED_IO_RETRIES + 1))
	testing.expect(t, prepared.state == nil)
}

/* Verifies path admission, absent parents, permissions, and file size fail precisely. */
@(test)
filesystem_rejects_unsupported_opens :: proc(t: ^testing.T) {
	fixture, ready := open_fixture_init(t)
	if !ready {
		return
	}
	defer open_fixture_close(&fixture)
	prepared: Prepared_Open

	empty_request := open_request("")
	empty_ok, empty_failure := open_prepare(
		&prepared,
		empty_request,
		default_test_allocators(),
	)
	testing.expect(t, !empty_ok)
	testing.expect_value(t, empty_failure.code, Failure_Code.Path_Empty)

	nul_request := open_request("invalid\x00path")
	nul_ok, nul_failure := open_prepare(&prepared, nul_request, default_test_allocators())
	testing.expect(t, !nul_ok)
	testing.expect_value(t, nul_failure.code, Failure_Code.Path_Contains_Nul)

	invalid_path_bytes := []u8{'b', 0xff, 'd'}
	invalid_request := open_request(string(invalid_path_bytes))
	invalid_ok, invalid_failure := open_prepare(
		&prepared,
		invalid_request,
		default_test_allocators(),
	)
	testing.expect(t, !invalid_ok)
	testing.expect_value(t, invalid_failure.code, Failure_Code.Path_Malformed_UTF8)

	missing_parent := open_join(fixture.directory, "missing/document.txt")
	defer delete(missing_parent)
	parent_ok, parent_failure := open_prepare(
		&prepared,
		open_request(missing_parent),
		default_test_allocators(),
	)
	testing.expect(t, !parent_ok)
	testing.expect_value(t, parent_failure.code, Failure_Code.Parent_Not_Found)

	testing.expect(t, os.write_entire_file(fixture.file_path, "private") == nil)
	testing.expect(t, os.change_mode(fixture.file_path, {}) == nil)
	permission_ok, permission_failure := open_prepare(
		&prepared,
		open_request(fixture.file_path),
		default_test_allocators(),
	)
	testing.expect(t, !permission_ok)
	testing.expect_value(t, permission_failure.code, Failure_Code.Open_Failed)
	testing.expect(t, permission_failure.platform_code != 0)
	testing.expect(t, os.change_mode(fixture.file_path, os.Permissions_Default_File) == nil)

	file, file_error := os.open(fixture.file_path, {.Write})
	testing.expect(t, file_error == nil)
	if file_error == nil {
		truncate_error := os.truncate(file, i64(MAX_FILE_BYTES + 1))
		close_error := os.close(file)
		testing.expect(t, truncate_error == nil && close_error == nil)
	}
	oversized_ok, oversized_failure := open_prepare(
		&prepared,
		open_request(fixture.file_path),
		default_test_allocators(),
	)
	testing.expect(t, !oversized_ok)
	testing.expect_value(t, oversized_failure.code, Failure_Code.File_Limit)
	testing.expect_value(t, oversized_failure.limit, MAX_FILE_BYTES)
	testing.expect_value(t, oversized_failure.actual, MAX_FILE_BYTES + 1)
}

/* Verifies temporary allocation failure and an identity race publish no candidate. */
@(test)
temporary_and_identity_failures_keep_zero_state :: proc(t: ^testing.T) {
	fixture, ready := open_fixture_init(t)
	if !ready {
		return
	}
	defer open_fixture_close(&fixture)
	testing.expect(t, os.write_entire_file(fixture.file_path, "stable") == nil)

	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	failing := Open_Failing_Allocator {
		backing = mem.tracking_allocator(&tracking),
		fail_after = 0,
	}
	prepared: Prepared_Open
	temporary_ok, temporary_failure := open_prepare(
		&prepared,
		open_request(fixture.file_path),
		Allocator_Set {
			persistent = context.allocator,
			temporary = open_failing_allocator(&failing),
		},
	)
	testing.expect(t, !temporary_ok)
	testing.expect_value(t, temporary_failure.code, Failure_Code.Temporary_Memory_Limit)
	testing.expect(t, prepared.state == nil)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))

	io := linux_open_io()
	io.inspect_handle = injected_changed_identity
	race_ok, race_failure := open_prepare_with_io(
		&prepared,
		open_request(fixture.file_path),
		default_test_allocators(),
		DEFAULT_LIMITS,
		io,
	)
	testing.expect(t, !race_ok)
	testing.expect_value(t, race_failure.code, Failure_Code.Target_Changed)
	testing.expect(t, prepared.state == nil)
}

@(private)
Open_Fixture :: struct {
	directory: string,
	file_path: string,
}

@(private)
open_fixture_init :: proc(t: ^testing.T) -> (Open_Fixture, bool) {
	directory, directory_error := os.make_directory_temp("", "odra-document-*", context.allocator)
	testing.expect(t, directory_error == nil)
	if directory_error != nil {
		return {}, false
	}
	file_path := open_join(directory, "document.txt")
	return Open_Fixture{directory = directory, file_path = file_path}, true
}

@(private)
open_fixture_close :: proc(fixture: ^Open_Fixture) {
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
open_join :: proc(directory, name: string) -> string {
	joined, error := os.join_path({directory, name}, context.allocator)
	assert(error == nil)
	return joined
}

@(private)
open_request :: proc(path: string) -> Open_Request {
	return Open_Request {
		document_id = Document_ID(1),
		buffer_id = editor.Buffer_ID(1),
		has_path = true,
		path = path,
		encoding = .UTF8,
	}
}

@(private)
default_test_allocators :: proc() -> Allocator_Set {
	return Allocator_Set {
		persistent = context.allocator,
		temporary = context.temp_allocator,
	}
}

@(private)
injected_read_failure :: proc(
	handle: Platform_Handle,
	destination: []u8,
) -> (int, Platform_Error) {
	_ = handle
	_ = destination
	return 0, Platform_Error{code = .Other, platform_code = 5}
}

@(private)
injected_interrupted_read :: proc(
	handle: Platform_Handle,
	destination: []u8,
) -> (int, Platform_Error) {
	_ = handle
	_ = destination
	return 0, Platform_Error{code = .Interrupted, platform_code = 4}
}

@(private)
injected_changed_identity :: proc(
	handle: Platform_Handle,
) -> (Platform_Metadata, Platform_Error) {
	metadata, failure := linux_inspect_handle(handle)
	metadata.identity.inode += 1
	return metadata, failure
}

@(private)
Open_Failing_Allocator :: struct {
	backing:                runtime.Allocator,
	fail_after:             u64,
	successful_allocations: u64,
}

@(private)
open_failing_allocator :: proc(data: ^Open_Failing_Allocator) -> runtime.Allocator {
	return runtime.Allocator {
		procedure = open_failing_allocator_proc,
		data = data,
	}
}

@(private)
open_failing_allocator_proc :: proc(
	allocator_data: rawptr,
	mode: runtime.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	location := #caller_location,
) -> (result: []byte, error: runtime.Allocator_Error) {
	allocator := (^Open_Failing_Allocator)(allocator_data)
	if mode == .Alloc || mode == .Alloc_Non_Zeroed || mode == .Resize ||
	   mode == .Resize_Non_Zeroed {
		if allocator.successful_allocations >= allocator.fail_after {
			return nil, .Out_Of_Memory
		}
		allocator.successful_allocations += 1
	}
	return allocator.backing.procedure(
		allocator.backing.data,
		mode,
		size,
		alignment,
		old_memory,
		old_size,
		location,
	)
}
