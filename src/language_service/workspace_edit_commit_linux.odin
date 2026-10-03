// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

#+build linux
package language_service

import "../transaction"
import "../history"
import "base:runtime"
import "core:fmt"
import "core:os"
import "core:path/filepath"

@(private)
Workspace_File_Phase :: enum u8 {Pending, Staged, Published, Rolled_Back}

@(private)
Workspace_Staged_Operation :: struct {
	operation: Workspace_File_Operation,
	staging_path: string,
	phase: Workspace_File_Phase,
}

/* workspace_edit_commit atomically coordinates reversible local file staging with buffer publication. */
workspace_edit_commit :: proc(
	proposal: ^Workspace_Edit_Proposal,
	transaction_id: transaction.Transaction_ID,
	undo_unit_id: transaction.Undo_Unit_ID,
	allocators: Workspace_Edit_Allocators,
	histories: []^history.Store,
	file_io: Workspace_File_IO,
) -> (Workspace_Edit_Commit, bool, Workspace_Edit_Failure) {
	if proposal == nil || proposal.state == nil || transaction_id == transaction.Transaction_ID(0) ||
	   undo_unit_id == transaction.Undo_Unit_ID(0) || allocators.persistent.procedure == nil ||
	   allocators.temporary.procedure == nil || !workspace_file_io_valid(file_io) {
		return {}, false, Workspace_Edit_Failure{code = .Invalid_Input}
	}
	commit := Workspace_Edit_Commit{}
	transaction_prepared := false
	if len(proposal.edit.snapshots) > 0 {
		prepared, transaction_failure := transaction.proposal_prepare(
			&commit.transaction,
			transaction_id,
			undo_unit_id,
			proposal.edit,
			{persistent = allocators.persistent, temporary = allocators.temporary},
			histories = histories,
		)
		if !prepared {
			return {}, false, Workspace_Edit_Failure{code = .Transaction_Prepare, transaction = transaction_failure}
		}
		transaction_prepared = true
	}
	staged, allocation_error := make([]Workspace_Staged_Operation, len(proposal.operations), allocators.temporary)
	if allocation_error != nil {
		if transaction_prepared do transaction.multibuffer_close(&commit.transaction)
		return {}, false, Workspace_Edit_Failure{code = .Allocation}
	}
	defer {
		for entry in staged do if entry.staging_path != "" do delete(entry.staging_path, allocators.temporary)
		delete(staged, allocators.temporary)
	}
	for operation, index in proposal.operations {
		staged[index].operation = operation
		path, path_ok := workspace_staging_path(operation, transaction_id, index, allocators.temporary)
		if !path_ok {
			if transaction_prepared do transaction.multibuffer_close(&commit.transaction)
			return {}, false, Workspace_Edit_Failure{code = .Allocation, resource = .Path_Bytes, index = u32(index)}
		}
		staged[index].staging_path = path
		if !workspace_file_preflight(operation, path, file_io) {
			if transaction_prepared do transaction.multibuffer_close(&commit.transaction)
			return {}, false, Workspace_Edit_Failure{code = .Filesystem_Preflight, resource = .File_Operation, index = u32(index)}
		}
	}
	for index in 0..<len(staged) {
		if !workspace_file_stage(&staged[index], file_io) {
			rolled_back := workspace_files_rollback(staged[:index], file_io)
			if transaction_prepared do transaction.multibuffer_close(&commit.transaction)
			code := Workspace_Edit_Failure_Code.Filesystem_Stage if rolled_back else .Filesystem_Rollback
			return {}, false, Workspace_Edit_Failure{code = code, resource = .File_Operation, index = u32(index)}
		}
	}
	for index in 0..<len(staged) {
		if !workspace_file_publish(&staged[index], file_io) {
			rolled_back := workspace_files_rollback(staged, file_io)
			if transaction_prepared do transaction.multibuffer_close(&commit.transaction)
			code := Workspace_Edit_Failure_Code.Filesystem_Publish if rolled_back else .Filesystem_Rollback
			return {}, false, Workspace_Edit_Failure{code = code, resource = .File_Operation, index = u32(index)}
		}
	}
	if transaction_prepared {
		transaction_result, committed, transaction_failure := transaction.multibuffer_commit(&commit.transaction)
		if !committed {
			rolled_back := workspace_files_rollback(staged, file_io)
			transaction.multibuffer_close(&commit.transaction)
			code := Workspace_Edit_Failure_Code.Transaction_Commit if rolled_back else .Filesystem_Rollback
			return {}, false, Workspace_Edit_Failure{code = code, transaction = transaction_failure}
		}
		commit.result.transaction = transaction_result
	}
	commit.result.preview = proposal.preview
	for index in 0..<len(staged) {
		if staged[index].operation.kind != .Delete do continue
		if !file_io.remove(file_io.user_data, staged[index].staging_path) && commit.result.cleanup_failure.code == .None {
			commit.result.cleanup_failure = {
				code = .Filesystem_Cleanup,
				resource = .File_Operation,
				index = u32(index),
			}
		}
	}
	return commit, true, {}
}

/* workspace_edit_commit_close releases the retained transaction exactly once. */
workspace_edit_commit_close :: proc(commit: ^Workspace_Edit_Commit) -> bool {
	if commit == nil || commit.closed do return false
	if transaction.multibuffer_transaction_is_valid(&commit.transaction) {
		transaction.multibuffer_close(&commit.transaction)
	}
	commit.closed = true
	return true
}

/* workspace_file_io_default returns the production local-filesystem adapter. */
workspace_file_io_default :: proc() -> Workspace_File_IO {
	return {
		stat = workspace_os_stat,
		rename = workspace_os_rename,
		create = workspace_os_create,
		remove = workspace_os_remove,
	}
}

@(private)
workspace_file_io_valid :: proc(value: Workspace_File_IO) -> bool {
	return value.stat != nil && value.rename != nil && value.create != nil && value.remove != nil
}

@(private)
workspace_staging_path :: proc(
	operation: Workspace_File_Operation,
	transaction_id: transaction.Transaction_ID,
	index: int,
	allocator: runtime.Allocator,
) -> (string, bool) {
	target := operation.destination_path if operation.kind == .Create else operation.source_path
	parent := filepath.dir(target)
	path := fmt.aprintf("%s/.odra-workspace-edit-%016x-%04d.stage", parent, u64(transaction_id), index, allocator = allocator)
	return path, len(path) > 0 && len(path) <= MAX_WORKSPACE_EDIT_PATH_BYTES
}

@(private)
workspace_file_preflight :: proc(operation: Workspace_File_Operation, staging_path: string, file_io: Workspace_File_IO) -> bool {
	staging, staging_ok := file_io.stat(file_io.user_data, staging_path)
	if !staging_ok || staging.exists do return false
	switch operation.kind {
	case .Create:
		destination, ok := file_io.stat(file_io.user_data, operation.destination_path)
		return ok && !destination.exists
	case .Rename:
		source, source_ok := file_io.stat(file_io.user_data, operation.source_path)
		destination, destination_ok := file_io.stat(file_io.user_data, operation.destination_path)
		return source_ok && destination_ok && workspace_source_matches(source, operation) && !destination.exists
	case .Delete:
		source, ok := file_io.stat(file_io.user_data, operation.source_path)
		return ok && workspace_source_matches(source, operation)
	case .Invalid:
		return false
	}
	return false
}

@(private)
workspace_source_matches :: proc(metadata: Workspace_File_Metadata, operation: Workspace_File_Operation) -> bool {
	return metadata.exists && metadata.kind == operation.source_kind &&
		(operation.source_inode == 0 || metadata.inode == operation.source_inode)
}

@(private)
workspace_file_stage :: proc(entry: ^Workspace_Staged_Operation, file_io: Workspace_File_IO) -> bool {
	if entry == nil do return false
	ok := false
	switch entry.operation.kind {
	case .Create:
		ok = file_io.create(file_io.user_data, entry.staging_path)
	case .Rename, .Delete:
		ok = file_io.rename(file_io.user_data, entry.operation.source_path, entry.staging_path)
	case .Invalid:
	}
	if ok do entry.phase = .Staged
	return ok
}

@(private)
workspace_file_publish :: proc(entry: ^Workspace_Staged_Operation, file_io: Workspace_File_IO) -> bool {
	if entry == nil || entry.phase != .Staged do return false
	switch entry.operation.kind {
	case .Create, .Rename:
		if !file_io.rename(file_io.user_data, entry.staging_path, entry.operation.destination_path) do return false
		entry.phase = .Published
	case .Delete:
		// The absent canonical path is the publication; permanent cleanup follows buffer commit.
		entry.phase = .Published
	case .Invalid:
		return false
	}
	return true
}

@(private)
workspace_files_rollback :: proc(entries: []Workspace_Staged_Operation, file_io: Workspace_File_IO) -> bool {
	ok := true
	#reverse for &entry in entries {
		switch entry.operation.kind {
		case .Create:
			if entry.phase == .Published {
				if !file_io.remove(file_io.user_data, entry.operation.destination_path) do ok = false
			} else if entry.phase == .Staged {
				if !file_io.remove(file_io.user_data, entry.staging_path) do ok = false
			}
		case .Rename:
			if entry.phase == .Published {
				if !file_io.rename(file_io.user_data, entry.operation.destination_path, entry.operation.source_path) do ok = false
			} else if entry.phase == .Staged {
				if !file_io.rename(file_io.user_data, entry.staging_path, entry.operation.source_path) do ok = false
			}
		case .Delete:
			if entry.phase == .Published || entry.phase == .Staged {
				if !file_io.rename(file_io.user_data, entry.staging_path, entry.operation.source_path) do ok = false
			}
		case .Invalid:
			ok = false
		}
		if ok do entry.phase = .Rolled_Back
	}
	return ok
}

@(private)
workspace_os_stat :: proc(_: rawptr, path: string) -> (Workspace_File_Metadata, bool) {
	info, stat_error := os.lstat(path, context.temp_allocator)
	if stat_error != nil {
		if stat_error == os.Error(.Not_Exist) do return {}, true
		return {}, false
	}
	defer os.file_info_delete(info, context.temp_allocator)
	kind := Workspace_Resource_Kind.Invalid
	if info.type == .Regular do kind = .Regular_File
	if info.type == .Directory do kind = .Directory
	return {exists = true, inode = info.inode, kind = kind}, kind != .Invalid
}

@(private)
workspace_os_rename :: proc(_: rawptr, from, to: string) -> bool {
	return os.rename(from, to) == nil
}

@(private)
workspace_os_create :: proc(_: rawptr, path: string) -> bool {
	file, create_error := os.open(path, {.Write, .Create, .Excl}, os.Permissions_Default_File)
	if create_error != nil do return false
	return os.close(file) == nil
}

@(private)
workspace_os_remove :: proc(_: rawptr, path: string) -> bool {
	return os.remove(path) == nil
}
