// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language_service

import "../editor"
import "../history"
import "../transaction"
import "base:runtime"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:testing"

@(private)
workspace_test_buffer :: proc(t: ^testing.T, allocator: runtime.Allocator, id: editor.Buffer_ID, text: string) -> editor.Buffer {
	buffer: editor.Buffer
	opened, failure := editor.buffer_init(&buffer, id, text, {persistent = allocator, temporary = context.temp_allocator})
	testing.expectf(t, opened, "buffer initialization failed: %v", failure.code)
	return buffer
}

@(private)
workspace_test_text :: proc(buffer: ^editor.Buffer) -> (string, bool) {
	snapshot: editor.Buffer_Snapshot
	opened, _ := editor.buffer_snapshot_open(buffer, &snapshot)
	if !opened do return "", false
	defer editor.buffer_snapshot_close(&snapshot)
	stats, stats_ok, _ := editor.buffer_snapshot_stats(&snapshot)
	if !stats_ok do return "", false
	bytes, allocation_error := make([]u8, int(stats.text_bytes), context.temp_allocator)
	if allocation_error != nil do return "", false
	read, read_ok, _ := editor.buffer_snapshot_read(&snapshot, 0, bytes)
	return string(bytes[:int(read)]), read_ok && read == stats.text_bytes
}

@(private)
workspace_test_context :: proc(documents: []Workspace_Document_Target, resources: []Workspace_Resource_Target = nil) -> Workspace_Edit_Context {
	return {
		root = "/work/project",
		membership = "project-a",
		project_trusted = true,
		position_encoding = .UTF_16,
		documents = documents,
		resources = resources,
		limits = DEFAULT_WORKSPACE_EDIT_LIMITS,
	}
}

/* Verifies versioned and unversioned edits commit atomically and share one undo unit. */
@(test)
workspace_edit_commits_and_undoes_versioned_multibuffer_change :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	first := workspace_test_buffer(t, allocator, 1_201, "alpha")
	second := workspace_test_buffer(t, allocator, 1_202, "beta")
	documents := [?]Workspace_Document_Target {
		{uri = "file:///work/project/a.go", path = "/work/project/a.go", buffer = &first, buffer_id = 1_201, text = "alpha", protocol_version = 7, has_protocol_version = true, resource_kind = .Regular_File},
		{uri = "file:///work/project/b.go", path = "/work/project/b.go", buffer = &second, buffer_id = 1_202, text = "beta", resource_kind = .Regular_File},
	}
	response := transmute([]u8)(string(`{"jsonrpc":"2.0","id":1,"result":{"documentChanges":[{"textDocument":{"uri":"file:///work/project/a.go","version":7},"edits":[{"range":{"start":{"line":0,"character":0},"end":{"line":0,"character":5}},"newText":"ALPHA"}]},{"textDocument":{"uri":"file:///work/project/b.go","version":null},"edits":[{"range":{"start":{"line":0,"character":0},"end":{"line":0,"character":4}},"newText":"BETA"}]}]}}`))
	proposal, normalized, failure := workspace_edit_normalize_rename(workspace_test_context(documents[:]), response, allocator)
	testing.expectf(t, normalized, "workspace edit normalization failed: %v", failure.code)
	first_history: history.Store
	second_history: history.Store
	first_ready, _ := history.store_init(&first_history, 1_201, 1_201, 0, {persistent = allocator, temporary = context.temp_allocator})
	second_ready, _ := history.store_init(&second_history, 1_202, 1_202, 0, {persistent = allocator, temporary = context.temp_allocator})
	testing.expect(t, first_ready && second_ready)
	if normalized && first_ready && second_ready {
		histories := [?]^history.Store{&second_history, &first_history}
		commit, committed, commit_failure := workspace_edit_commit(
			&proposal,
			1_203,
			1_203,
			{persistent = allocator, temporary = context.temp_allocator},
			histories[:],
			workspace_file_io_default(),
		)
		testing.expectf(t, committed, "workspace edit commit failed: %v", commit_failure.code)
		if committed {
			testing.expect_value(t, commit.result.preview.documents, u32(2))
			testing.expect_value(t, commit.result.transaction.undo_unit_id, transaction.Undo_Unit_ID(1_203))
			workspace_edit_commit_close(&commit)
		}
		first_text, first_copied := workspace_test_text(&first)
		second_text, second_copied := workspace_test_text(&second)
		testing.expect(t, first_copied && second_copied)
		testing.expect_value(t, first_text, "ALPHA")
		testing.expect_value(t, second_text, "BETA")
		_, undone, undo_failure := transaction.transaction_multibuffer_history_navigate(
			[]^history.Store{&first_history, &second_history},
			[]^editor.Buffer{&second, &first},
			.Undo,
			0,
			1_204,
			1_204,
			{persistent = allocator, temporary = context.temp_allocator},
		)
		testing.expectf(t, undone, "workspace edit undo failed: %v", undo_failure.code)
		first_text, _ = workspace_test_text(&first)
		second_text, _ = workspace_test_text(&second)
		testing.expect_value(t, first_text, "alpha")
		testing.expect_value(t, second_text, "beta")
	}
	if first_ready && second_ready {
		closed, close_failure := history.multibuffer_stores_close([]^history.Store{&first_history, &second_history})
		testing.expectf(t, closed, "history cleanup failed: %v", close_failure.code)
	} else {
		if first_ready do history.store_close(&first_history)
		if second_ready do history.store_close(&second_history)
	}
	if normalized do workspace_edit_proposal_close(&proposal)
	editor.buffer_close(&second)
	editor.buffer_close(&first)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&tracking)
}

/* Verifies malformed, overlapping, stale-version, and out-of-root edits are rejected whole. */
@(test)
workspace_edit_rejects_invalid_text_and_membership_as_a_whole :: proc(t: ^testing.T) {
	buffer := workspace_test_buffer(t, context.allocator, 1_211, "abcd")
	defer editor.buffer_close(&buffer)
	documents := [?]Workspace_Document_Target {{
		uri = "file:///work/project/a.go", path = "/work/project/a.go", buffer = &buffer,
		buffer_id = 1_211, text = "abcd", protocol_version = 3, has_protocol_version = true,
		resource_kind = .Regular_File,
	}}
	versioned := transmute([]u8)(string(`{"jsonrpc":"2.0","id":1,"result":{"documentChanges":[{"textDocument":{"uri":"file:///work/project/a.go","version":4},"edits":[]}]}}`))
	_, accepted, failure := workspace_edit_normalize_rename(workspace_test_context(documents[:]), versioned)
	testing.expect(t, !accepted)
	testing.expect_value(t, failure.code, Workspace_Edit_Failure_Code.Version_Mismatch)
	overlap := transmute([]u8)(string(`{"jsonrpc":"2.0","id":1,"result":{"changes":{"file:///work/project/a.go":[{"range":{"start":{"line":0,"character":0},"end":{"line":0,"character":3}},"newText":"x"},{"range":{"start":{"line":0,"character":2},"end":{"line":0,"character":4}},"newText":"y"}]}}}`))
	_, accepted, failure = workspace_edit_normalize_rename(workspace_test_context(documents[:]), overlap)
	testing.expect(t, !accepted)
	testing.expect_value(t, failure.code, Workspace_Edit_Failure_Code.Overlapping_Edit)
	code_action := transmute([]u8)(string(`{"jsonrpc":"2.0","id":1,"result":[{"title":"Uppercase","edit":{"changes":{"file:///work/project/a.go":[{"range":{"start":{"line":0,"character":0},"end":{"line":0,"character":1}},"newText":"A"}]}}}]}`))
	action_proposal, action_ok, action_failure := workspace_edit_normalize_code_action(
		workspace_test_context(documents[:]), code_action, 0,
	)
	testing.expectf(t, action_ok, "code action normalization failed: %v", action_failure.code)
	if action_ok do workspace_edit_proposal_close(&action_proposal)
	documents[0].path = "/outside/a.go"
	_, accepted, failure = workspace_edit_normalize_rename(workspace_test_context(documents[:]), overlap)
	testing.expect(t, !accepted)
	testing.expect_value(t, failure.code, Workspace_Edit_Failure_Code.Invalid_Document)
	malformed := transmute([]u8)(string(`{"jsonrpc":"2.0","id":1,"result":{"changes":{},"documentChanges":[]}}`))
	_, accepted, failure = workspace_edit_normalize_rename(workspace_test_context(documents[:]), malformed)
	testing.expect(t, !accepted)
	testing.expect_value(t, failure.code, Workspace_Edit_Failure_Code.Invalid_Workspace_Edit)
}

/* Verifies create, rename, and delete publish only after complete preflight. */
@(test)
workspace_edit_applies_checked_file_operations :: proc(t: ^testing.T) {
	directory, directory_error := os.make_directory_temp("", "odra-workspace-*", context.allocator)
	testing.expect(t, directory_error == nil)
	if directory_error != nil do return
	defer { _ = os.remove_all(directory); delete(directory, context.allocator) }
	old_path := fmt.aprintf("%s/old.go", directory, allocator = context.temp_allocator)
	delete_path := fmt.aprintf("%s/delete.go", directory, allocator = context.temp_allocator)
	new_path := fmt.aprintf("%s/new.go", directory, allocator = context.temp_allocator)
	renamed_path := fmt.aprintf("%s/renamed.go", directory, allocator = context.temp_allocator)
	workspace_test_create_file(old_path)
	workspace_test_create_file(delete_path)
	file_io := workspace_file_io_default()
	old_metadata, _ := file_io.stat(nil, old_path)
	delete_metadata, _ := file_io.stat(nil, delete_path)
	resources := [?]Workspace_Resource_Target {
		{uri = "file:///work/project/old.go", path = old_path, exists_on_disk = true, disk_inode = old_metadata.inode, kind = .Regular_File},
		{uri = "file:///work/project/delete.go", path = delete_path, exists_on_disk = true, disk_inode = delete_metadata.inode, kind = .Regular_File},
		{uri = "file:///work/project/new.go", path = new_path, kind = .Regular_File},
		{uri = "file:///work/project/renamed.go", path = renamed_path, kind = .Regular_File},
	}
	edit_context := workspace_test_context(nil, resources[:])
	edit_context.root = directory
	response := transmute([]u8)(string(`{"jsonrpc":"2.0","id":1,"result":{"documentChanges":[{"kind":"create","uri":"file:///work/project/new.go"},{"kind":"rename","oldUri":"file:///work/project/old.go","newUri":"file:///work/project/renamed.go"},{"kind":"delete","uri":"file:///work/project/delete.go"}]}}`))
	proposal, normalized, failure := workspace_edit_normalize_rename(edit_context, response)
	testing.expectf(t, normalized, "file operation normalization failed: %v", failure.code)
	if !normalized do return
	defer workspace_edit_proposal_close(&proposal)
	commit, committed, commit_failure := workspace_edit_commit(
		&proposal, 1_221, 1_221,
		{persistent = context.allocator, temporary = context.temp_allocator}, nil, file_io,
	)
	testing.expectf(t, committed, "file operation commit failed: %v", commit_failure.code)
	if committed do workspace_edit_commit_close(&commit)
	testing.expect(t, workspace_test_exists(new_path))
	testing.expect(t, workspace_test_exists(renamed_path))
	testing.expect(t, !workspace_test_exists(old_path))
	testing.expect(t, !workspace_test_exists(delete_path))
}

/* Verifies an injected partial publish failure restores every visible path. */
@(test)
workspace_edit_rolls_back_partial_filesystem_publication :: proc(t: ^testing.T) {
	directory, directory_error := os.make_directory_temp("", "odra-workspace-rollback-*", context.allocator)
	testing.expect(t, directory_error == nil)
	if directory_error != nil do return
	defer { _ = os.remove_all(directory); delete(directory, context.allocator) }
	old_path := fmt.aprintf("%s/old.go", directory, allocator = context.temp_allocator)
	new_path := fmt.aprintf("%s/new.go", directory, allocator = context.temp_allocator)
	renamed_path := fmt.aprintf("%s/renamed.go", directory, allocator = context.temp_allocator)
	workspace_test_create_file(old_path)
	base_io := workspace_file_io_default()
	old_metadata, _ := base_io.stat(nil, old_path)
	resources := [?]Workspace_Resource_Target {
		{uri = "file:///work/project/old.go", path = old_path, exists_on_disk = true, disk_inode = old_metadata.inode, kind = .Regular_File},
		{uri = "file:///work/project/new.go", path = new_path, kind = .Regular_File},
		{uri = "file:///work/project/renamed.go", path = renamed_path, kind = .Regular_File},
	}
	edit_context := workspace_test_context(nil, resources[:])
	edit_context.root = directory
	response := transmute([]u8)(string(`{"jsonrpc":"2.0","id":1,"result":{"documentChanges":[{"kind":"create","uri":"file:///work/project/new.go"},{"kind":"rename","oldUri":"file:///work/project/old.go","newUri":"file:///work/project/renamed.go"}]}}`))
	proposal, normalized, _ := workspace_edit_normalize_rename(edit_context, response)
	testing.expect(t, normalized)
	if !normalized do return
	defer workspace_edit_proposal_close(&proposal)
	fault := Workspace_Test_File_Fault{base = base_io, fail_rename = 2}
	fault_io := Workspace_File_IO {
		stat = workspace_test_fault_stat,
		rename = workspace_test_fault_rename,
		create = workspace_test_fault_create,
		remove = workspace_test_fault_remove,
		user_data = &fault,
	}
	_, committed, failure := workspace_edit_commit(
		&proposal, 1_223, 1_223,
		{persistent = context.allocator, temporary = context.temp_allocator}, nil, fault_io,
	)
	testing.expect(t, !committed)
	testing.expect_value(t, failure.code, Workspace_Edit_Failure_Code.Filesystem_Publish)
	testing.expect(t, workspace_test_exists(old_path))
	testing.expect(t, !workspace_test_exists(new_path))
	testing.expect(t, !workspace_test_exists(renamed_path))
}

/* Verifies normalization allocation failure exposes no proposal owner. */
@(test)
workspace_edit_allocation_failure_publishes_nothing :: proc(t: ^testing.T) {
	buffer := workspace_test_buffer(t, context.allocator, 1_231, "abc")
	defer editor.buffer_close(&buffer)
	documents := [?]Workspace_Document_Target {{
		uri = "file:///work/project/a.go", path = "/work/project/a.go", buffer = &buffer,
		buffer_id = 1_231, text = "abc", resource_kind = .Regular_File,
	}}
	response := transmute([]u8)(string(`{"jsonrpc":"2.0","id":1,"result":{"changes":{"file:///work/project/a.go":[{"range":{"start":{"line":0,"character":0},"end":{"line":0,"character":3}},"newText":"ABC"}]}}}`))
	failing := Workspace_Test_Failing_Allocator{backing = context.allocator}
	proposal, normalized, failure := workspace_edit_normalize_rename(
		workspace_test_context(documents[:]), response, workspace_test_failing_allocator(&failing),
	)
	testing.expect(t, !normalized)
	testing.expect_value(t, failure.code, Workspace_Edit_Failure_Code.Allocation)
	testing.expect(t, proposal.state == nil)
}

@(private)
workspace_test_create_file :: proc(path: string) {
	file, create_error := os.open(path, {.Write, .Create, .Excl}, os.Permissions_Default_File)
	assert(create_error == nil)
	assert(os.close(file) == nil)
}

@(private)
workspace_test_exists :: proc(path: string) -> bool {
	info, stat_error := os.lstat(path, context.temp_allocator)
	if stat_error != nil do return false
	os.file_info_delete(info, context.temp_allocator)
	return true
}

@(private = "file")
Workspace_Test_File_Fault :: struct {
	base: Workspace_File_IO,
	rename_calls: u32,
	fail_rename: u32,
}

@(private = "file")
workspace_test_fault_stat :: proc(data: rawptr, path: string) -> (Workspace_File_Metadata, bool) {
	fault := cast(^Workspace_Test_File_Fault)data
	return fault.base.stat(nil, path)
}

@(private = "file")
workspace_test_fault_rename :: proc(data: rawptr, from, to: string) -> bool {
	fault := cast(^Workspace_Test_File_Fault)data
	fault.rename_calls += 1
	if fault.rename_calls == fault.fail_rename do return false
	return fault.base.rename(nil, from, to)
}

@(private = "file")
workspace_test_fault_create :: proc(data: rawptr, path: string) -> bool {
	fault := cast(^Workspace_Test_File_Fault)data
	return fault.base.create(nil, path)
}

@(private = "file")
workspace_test_fault_remove :: proc(data: rawptr, path: string) -> bool {
	fault := cast(^Workspace_Test_File_Fault)data
	return fault.base.remove(nil, path)
}

@(private = "file")
Workspace_Test_Failing_Allocator :: struct {backing: runtime.Allocator}

@(private = "file")
workspace_test_failing_allocator :: proc(data: ^Workspace_Test_Failing_Allocator) -> runtime.Allocator {
	return {procedure = workspace_test_failing_allocator_proc, data = data}
}

@(private = "file")
workspace_test_failing_allocator_proc :: proc(
	_: rawptr,
	mode: runtime.Allocator_Mode,
	_: int,
	_: int,
	_: rawptr,
	_: int,
	_ := #caller_location,
) -> ([]byte, runtime.Allocator_Error) {
	if mode == .Free || mode == .Free_All do return nil, nil
	return nil, .Out_Of_Memory
}
