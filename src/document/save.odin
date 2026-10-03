// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package document

import "../editor"
import "base:runtime"
import "core:fmt"
import "core:os"

@(private)
NEW_FILE_MODE :: u32(0o666)

@(private)
Prepared_Save_State :: struct {
	owner:                    ^Open_State,
	buffer:                   ^editor.Buffer,
	snapshot:                 editor.Buffer_Snapshot,
	limits:                   Limits,
	io:                       Save_IO,
	external_change_observed: bool,
	target_existed:           bool,
	target_mode:              u32,
	temporary_path:           [4_097]byte,
	temporary_path_length:    int,
	temporary_created:        bool,
	allocator:                runtime.Allocator,
}

/*
save_prepare retains one exact buffer revision for an explicit associated-document save.
A successful preparation must be consumed by prepared_save_publish or prepared_save_abort.
*/
save_prepare :: proc(
	document: ^Document,
	buffer: ^editor.Buffer,
	prepared: ^Prepared_Save,
	limits := DEFAULT_LIMITS,
) -> (ok: bool, failure: Failure_Context) {
	return save_prepare_with_io(document, buffer, prepared, limits, linux_save_io())
}

/*
prepared_save_publish streams and atomically replaces the target, then consumes the preparation.
Its result remains authoritative when a returned failure reports that publication already occurred.
*/
prepared_save_publish :: proc(
	prepared: ^Prepared_Save,
) -> (result: Save_Result, ok: bool, failure: Failure_Context) {
	state := prepared_save_state(prepared)
	if state == nil {
		return {}, false, Failure_Context {
			code = .Invalid_Preparation,
			operation = .Publish_Save,
			publication = .Not_Published,
		}
	}
	result = save_result(state, .Not_Published)

	handle, created, create_failure := create_temporary_file(state)
	if !created {
		return consume_failed_save(prepared, result, create_failure)
	}
	state.temporary_created = true

	if state.target_existed {
		mode_error := state.io.set_mode(handle, state.target_mode)
		if mode_error.code != .None {
			failure = save_platform_failure(state, .Permission_Failed, mode_error, .Not_Published)
			return consume_prepublication_failure(prepared, handle, result, failure)
		}
	}

	failure = stream_snapshot(state, handle)
	if failure.code != .None {
		return consume_prepublication_failure(prepared, handle, result, failure)
	}
	sync_error := state.io.sync(handle)
	if sync_error.code != .None {
		failure = save_platform_failure(state, .File_Sync_Failed, sync_error, .Not_Published)
		return consume_prepublication_failure(prepared, handle, result, failure)
	}
	close_error := state.io.close(handle)
	if close_error.code != .None {
		failure = save_platform_failure(state, .Close_Failed, close_error, .Not_Published)
		return consume_prepublication_failure(prepared, Platform_Handle(-1), result, failure)
	}

	parent := os.dir(state.owner.path)
	directory, directory_error := state.io.open_directory(parent)
	if directory_error.code != .None {
		failure = save_platform_failure(state, .Directory_Open_Failed, directory_error, .Not_Published)
		return consume_prepublication_failure(prepared, Platform_Handle(-1), result, failure)
	}

	rename_error := state.io.rename(save_temporary_path(state), state.owner.path)
	if rename_error.code != .None {
		_ = state.io.close(directory)
		failure = save_platform_failure(state, .Rename_Failed, rename_error, .Not_Published)
		return consume_prepublication_failure(prepared, Platform_Handle(-1), result, failure)
	}
	state.temporary_created = false
	publish_document_revision(state)

	directory_sync_error := state.io.sync(directory)
	directory_close_error := state.io.close(directory)
	publication := Publication_State.Published_Durable
	if directory_sync_error.code != .None {
		publication = .Published_Durability_Uncertain
	}
	result = save_result(state, publication)

	metadata, metadata_error := state.io.inspect(state.owner.path, false, state.allocator)
	if metadata_error.code == .None && metadata.kind == .Regular {
		state.owner.observation = observation_from_metadata(metadata)
		result.observation = state.owner.observation
	} else {
		state.owner.observation = External_Observation{exists = true}
		result.observation = state.owner.observation
	}

	if directory_sync_error.code != .None {
		failure = save_platform_failure(state, .Directory_Sync_Failed, directory_sync_error, publication)
		return consume_save(prepared, result, false, failure)
	}
	if directory_close_error.code != .None {
		failure = save_platform_failure(state, .Close_Failed, directory_close_error, publication)
		return consume_save(prepared, result, false, failure)
	}
	if metadata_error.code != .None || metadata.kind != .Regular {
		failure = save_platform_failure(state, .Metadata_Failed, metadata_error, publication)
		return consume_save(prepared, result, false, failure)
	}
	return consume_save(prepared, result, true, {})
}

/* prepared_save_abort releases an unpublished save snapshot and restores document state. */
prepared_save_abort :: proc(
	prepared: ^Prepared_Save,
) -> (ok: bool, failure: Failure_Context) {
	state := prepared_save_state(prepared)
	if state == nil {
		return false, Failure_Context {
			code = .Invalid_Preparation,
			operation = .Abort_Save,
			publication = .Not_Published,
		}
	}
	result := save_result(state, .Not_Published)
	_, _, failure = consume_save(prepared, result, true, {})
	failure.operation = .Abort_Save
	return true, failure
}

@(private)
save_prepare_with_io :: proc(
	document: ^Document,
	buffer: ^editor.Buffer,
	prepared: ^Prepared_Save,
	limits: Limits,
	io: Save_IO,
) -> (ok: bool, failure: Failure_Context) {
	assert(prepared != nil)
	assert(prepared.state == nil, "save preparation is already initialized")
	owner := document_open_state(document)
	if owner == nil || owner.prepared {
		return false, Failure_Context{code = .Closed_Document, operation = .Prepare_Save}
	}
	failure = save_failure(owner, .None, .Not_Published)
	if !limits_are_valid(limits) {
		failure.code = .Invalid_Limits
		return false, failure
	}
	if owner.kind == .Unassociated || len(owner.path) == 0 {
		failure.code = .Path_Required
		return false, failure
	}
	if owner.encoding != .UTF8 {
		failure.code = .Invalid_Encoding
		return false, failure
	}
	if owner.active_operations >= limits.active_operations ||
	   owner.active_snapshots >= limits.save_snapshots {
		failure.code = .Operation_In_Progress
		failure.limit = u64(limits.active_operations)
		failure.actual = u64(owner.active_operations)
		return false, failure
	}
	buffer_stats, buffer_ok, buffer_failure := editor.buffer_stats(buffer)
	if !buffer_ok {
		failure.code = .Snapshot_Failed
		failure.actual = u64(buffer_failure.code)
		return false, failure
	}
	if buffer_stats.buffer_id != owner.buffer_id {
		failure.code = .Invalid_Buffer_ID
		failure.actual = u64(buffer_stats.buffer_id)
		return false, failure
	}
	if buffer_stats.text_bytes > limits.file_bytes {
		failure.code = .File_Limit
		failure.limit = limits.file_bytes
		failure.actual = buffer_stats.text_bytes
		return false, failure
	}

	parent := os.dir(owner.path)
	parent_metadata, parent_error := io.inspect(parent, true, owner.allocator)
	if parent_error.code != .None {
		failure = save_platform_failure_from_owner(owner, .Parent_Inaccessible, parent_error, .Not_Published)
		if parent_error.code == .Not_Found {
			failure.code = .Parent_Not_Found
		}
		return false, failure
	}
	if parent_metadata.kind != .Directory {
		failure.code = .Parent_Not_Directory
		return false, failure
	}

	target_metadata, target_error := io.inspect(owner.path, false, owner.allocator)
	target_existed := target_error.code == .None
	if target_error.code != .None && target_error.code != .Not_Found {
		return false, save_platform_failure_from_owner(owner, .Target_Inaccessible, target_error, .Not_Published)
	}
	if target_existed && target_metadata.kind == .Symbolic_Link {
		failure.code = .Target_Is_Symbolic_Link
		return false, failure
	}
	if target_existed && target_metadata.kind != .Regular {
		failure.code = .Target_Not_Regular
		return false, failure
	}
	current_observation := External_Observation{}
	if target_existed {
		current_observation = observation_from_metadata(target_metadata)
	}

	state, allocation_error := new(Prepared_Save_State, owner.allocator)
	if allocation_error != nil {
		failure.code = .Persistent_Memory_Limit
		failure.actual = u64(size_of(Prepared_Save_State))
		return false, failure
	}
	state.owner = owner
	state.buffer = buffer
	state.limits = limits
	state.io = io
	state.external_change_observed = current_observation != owner.observation
	state.target_existed = target_existed
	state.target_mode = target_metadata.mode
	state.allocator = owner.allocator
	snapshot_ok, snapshot_failure := editor.buffer_snapshot_open(buffer, &state.snapshot)
	if !snapshot_ok {
		free(state, owner.allocator)
		failure.code = .Snapshot_Failed
		failure.actual = u64(snapshot_failure.code)
		return false, failure
	}
	owner.active_operations += 1
	owner.active_snapshots += 1
	owner.persistence = .Saving
	prepared.state = state
	return true, {}
}

@(private)
create_temporary_file :: proc(
	state: ^Prepared_Save_State,
) -> (handle: Platform_Handle, ok: bool, failure: Failure_Context) {
	parent := os.dir(state.owner.path)
	for attempt: u32 = 0; attempt < state.limits.temporary_name_attempts; attempt += 1 {
		required_bytes := len(parent) + 48
		if required_bytes >= len(state.temporary_path) {
			failure = save_failure(state.owner, .Path_Limit, .Not_Published)
			failure.limit = state.limits.path_bytes
			failure.actual = u64(required_bytes)
			return Platform_Handle(-1), false, failure
		}
		path := fmt.bprintf(
			state.temporary_path[:],
			"%s/.odra-%016x-%016x-%02x.tmp",
			parent,
			u64(state.owner.document_id),
			u64(state.owner.saved_revision),
			attempt,
		)
		state.temporary_path_length = len(path)
		mode := NEW_FILE_MODE
		create_error: Platform_Error
		handle, create_error = state.io.create_exclusive(path, mode)
		if create_error.code == .Exists {
			continue
		}
		if create_error.code != .None {
			return Platform_Handle(-1), false,
			       save_platform_failure(state, .Create_Failed, create_error, .Not_Published)
		}
		return handle, true, {}
	}
	failure = save_failure(state.owner, .Temporary_Name_Limit, .Not_Published)
	failure.limit = u64(state.limits.temporary_name_attempts)
	failure.actual = u64(state.limits.temporary_name_attempts)
	return Platform_Handle(-1), false, failure
}

@(private)
stream_snapshot :: proc(state: ^Prepared_Save_State, handle: Platform_Handle) -> Failure_Context {
	stats, stats_ok, snapshot_failure := editor.buffer_snapshot_stats(&state.snapshot)
	if !stats_ok {
		failure := save_failure(state.owner, .Snapshot_Failed, .Not_Published)
		failure.actual = u64(snapshot_failure.code)
		return failure
	}
	chunk: [IO_CHUNK_BYTES]byte
	offset: u64
	for offset < stats.text_bytes {
		want := min(state.limits.io_chunk_bytes, stats.text_bytes - offset)
		read_count, read_ok, read_failure := editor.buffer_snapshot_read(
			&state.snapshot,
			editor.Byte_Offset(offset),
			chunk[:int(want)],
		)
		if !read_ok || read_count != want {
			failure := save_failure(state.owner, .Snapshot_Failed, .Not_Published)
			failure.byte_offset = offset
			failure.actual = u64(read_failure.code)
			return failure
		}
		written: u64
		retries: u32
		for written < read_count {
			write_count, write_error := state.io.write(
				handle,
				chunk[int(written):int(read_count)],
			)
			if write_count > 0 {
				written += u64(write_count)
				retries = 0
				if write_error.code == .None || write_error.code == .Interrupted {
					continue
				}
			}
			if write_error.code == .Interrupted || (write_error.code == .None && write_count == 0) {
				if retries >= state.limits.interrupted_io_retries {
					failure := save_platform_failure(state, .Work_Limit, write_error, .Not_Published)
					failure.byte_offset = offset + written
					failure.limit = u64(state.limits.interrupted_io_retries)
					failure.actual = u64(retries + 1)
					return failure
				}
				retries += 1
				continue
			}
			failure := save_platform_failure(state, .Write_Failed, write_error, .Not_Published)
			failure.byte_offset = offset + written
			return failure
		}
		offset += read_count
	}
	return {}
}

@(private)
consume_prepublication_failure :: proc(
	prepared: ^Prepared_Save,
	handle: Platform_Handle,
	result: Save_Result,
	incoming_failure: Failure_Context,
) -> (Save_Result, bool, Failure_Context) {
	state := prepared_save_state(prepared)
	assert(state != nil)
	failure := incoming_failure
	if handle != Platform_Handle(-1) {
		_ = state.io.close(handle)
	}
	if state.temporary_created {
		unlink_error := state.io.unlink(save_temporary_path(state))
		state.temporary_created = false
		if unlink_error.code != .None && unlink_error.code != .Not_Found {
			failure = save_platform_failure(state, .Cleanup_Failed, unlink_error, .Not_Published)
		}
	}
	return consume_save(prepared, result, false, failure)
}

@(private)
consume_failed_save :: proc(
	prepared: ^Prepared_Save,
	result: Save_Result,
	failure: Failure_Context,
) -> (Save_Result, bool, Failure_Context) {
	return consume_save(prepared, result, false, failure)
}

@(private)
consume_save :: proc(
	prepared: ^Prepared_Save,
	result: Save_Result,
	ok: bool,
	failure: Failure_Context,
) -> (Save_Result, bool, Failure_Context) {
	state := prepared_save_state(prepared)
	assert(state != nil)
	owner := state.owner
	restore_document_persistence(state)
	assert(owner.active_operations > 0 && owner.active_snapshots > 0)
	owner.active_operations -= 1
	owner.active_snapshots -= 1
	_, _ = editor.buffer_snapshot_close(&state.snapshot)
	allocator := state.allocator
	prepared.state = nil
	free(state, allocator)
	return result, ok, failure
}

@(private)
publish_document_revision :: proc(state: ^Prepared_Save_State) {
	stats, stats_ok, _ := editor.buffer_snapshot_stats(&state.snapshot)
	assert(stats_ok)
	state.owner.kind = .Materialized
	state.owner.has_saved_revision = true
	state.owner.saved_revision = stats.revision
}

@(private)
restore_document_persistence :: proc(state: ^Prepared_Save_State) {
	owner := state.owner
	if owner.kind == .Unassociated {
		owner.persistence = .Unassociated
		return
	}
	if owner.kind == .Unmaterialized {
		owner.persistence = .Unmaterialized
		return
	}
	buffer_stats, buffer_ok, _ := editor.buffer_stats(state.buffer)
	if owner.has_saved_revision && buffer_ok && buffer_stats.revision == owner.saved_revision {
		owner.persistence = .Clean
	} else {
		owner.persistence = .Modified
	}
}

@(private)
save_result :: proc(state: ^Prepared_Save_State, publication: Publication_State) -> Save_Result {
	stats, stats_ok, _ := editor.buffer_snapshot_stats(&state.snapshot)
	assert(stats_ok)
	return Save_Result {
		document_id = state.owner.document_id,
		buffer_id = state.owner.buffer_id,
		saved_revision = stats.revision,
		publication = publication,
		external_change_observed = state.external_change_observed,
		observation = state.owner.observation,
	}
}

@(private)
save_temporary_path :: proc(state: ^Prepared_Save_State) -> string {
	return string(state.temporary_path[:state.temporary_path_length])
}

@(private)
prepared_save_state :: proc(prepared: ^Prepared_Save) -> ^Prepared_Save_State {
	if prepared == nil || prepared.state == nil {
		return nil
	}
	return (^Prepared_Save_State)(prepared.state)
}

@(private)
save_failure :: proc(
	owner: ^Open_State,
	code: Failure_Code,
	publication: Publication_State,
) -> Failure_Context {
	return Failure_Context {
		code = code,
		operation = .Prepare_Save,
		document_id = owner.document_id,
		buffer_id = owner.buffer_id,
		publication = publication,
	}
}

@(private)
save_platform_failure :: proc(
	state: ^Prepared_Save_State,
	code: Failure_Code,
	platform_error: Platform_Error,
	publication: Publication_State,
) -> Failure_Context {
	return save_platform_failure_from_owner(state.owner, code, platform_error, publication)
}

@(private)
save_platform_failure_from_owner :: proc(
	owner: ^Open_State,
	code: Failure_Code,
	platform_error: Platform_Error,
	publication: Publication_State,
) -> Failure_Context {
	failure := save_failure(owner, code, publication)
	failure.operation = .Publish_Save
	failure.platform_code = platform_error.platform_code
	return failure
}
