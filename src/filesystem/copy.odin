// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package filesystem

import "core:io"
import "core:os"

@(private)
Copy_State :: struct {
	request:    Copy_Request,
	allocators: Allocator_Set,
	result:     Copy_Result,
}

/* directory_entry_copy copies one exact local child to one checked absent destination. */
directory_entry_copy :: proc(
	source_parent, destination_parent: string,
	request: Copy_Request,
	allocators: Allocator_Set,
) -> (result: Copy_Result, ok: bool, failure: Failure_Context) {
	failure.operation = .Apply_Copy
	if len(source_parent) == 0 || len(destination_parent) == 0 ||
	   !resource_id_valid(request.source_parent_identity) ||
	   !resource_id_valid(request.source_identity) ||
	   !resource_id_valid(request.destination_parent_identity) ||
	   request.source_kind == .Invalid || !rename_name_valid(request.source_name) ||
	   !rename_name_valid(request.destination_name) || allocators.temporary.procedure == nil ||
	   request.limits.bytes == 0 || request.limits.bytes > MAX_COPY_BYTES ||
	   request.limits.entries == 0 || request.limits.entries > MAX_COPY_ENTRIES ||
	   request.limits.depth == 0 || request.limits.depth > MAX_COPY_DEPTH {
		failure.code = .Invalid_Arguments
		return {}, false, failure
	}
	source_batch, source_ok, source_failure := directory_observe(
		source_parent, 1, {persistent = allocators.temporary, temporary = allocators.temporary}, true,
	)
	if !source_ok { source_failure.operation = .Apply_Copy; return {}, false, source_failure }
	defer directory_batch_close(&source_batch)
	if source_batch.directory_identity != request.source_parent_identity {
		failure.code = .Directory_Changed
		return {}, false, failure
	}
	source, source_found := directory_entry_find(&source_batch, request.source_identity)
	if !source_found || source.name != request.source_name || source.kind != request.source_kind {
		failure.code = .Source_Changed
		return {}, false, failure
	}
	destination_batch, destination_ok, destination_failure := directory_observe(
		destination_parent, 1,
		{persistent = allocators.temporary, temporary = allocators.temporary}, true,
	)
	if !destination_ok { destination_failure.operation = .Apply_Copy; return {}, false, destination_failure }
	defer directory_batch_close(&destination_batch)
	if destination_batch.directory_identity != request.destination_parent_identity {
		failure.code = .Directory_Changed
		return {}, false, failure
	}
	for entry in destination_batch.descriptors {
		if entry.name == request.destination_name {
			failure.code = .Destination_Exists
			return {}, false, failure
		}
	}
	source_path, source_path_error := os.join_path(
		{source_parent, request.source_name}, allocators.temporary,
	)
	destination_path, destination_path_error := os.join_path(
		{destination_parent, request.destination_name}, allocators.temporary,
	)
	if source_path_error != nil || destination_path_error != nil {
		if source_path_error == nil do delete(source_path, allocators.temporary)
		if destination_path_error == nil do delete(destination_path, allocators.temporary)
		failure.code = .Persistent_Memory_Limit
		return {}, false, failure
	}
	defer {delete(destination_path, allocators.temporary); delete(source_path, allocators.temporary)}
	if len(source_path) > MAX_PATH_STORAGE_BYTES || len(destination_path) > MAX_PATH_STORAGE_BYTES {
		failure.code = .Path_Limit
		return {}, false, failure
	}
	if _, exists, _ := local_resource_identity(destination_path); exists {
		failure.code = .Destination_Exists
		return {}, false, failure
	}
	state := Copy_State{request = request, allocators = allocators}
	copied, copy_failure := copy_resource(&state, source_path, destination_path, request.source_identity, 1)
	if !copied {
		removed := os.remove_all(destination_path) == nil
		state.result.outcome = .Cleaned_Partial if removed else .Partial_Remains
		if !removed do copy_failure.code = .Partial_Cleanup_Failed
		return state.result, false, copy_failure
	}
	identity, identified, platform_code := local_resource_identity(destination_path)
	if !identified {
		removed := os.remove_all(destination_path) == nil
		state.result.outcome = .Cleaned_Partial if removed else .Partial_Remains
		failure.code = .Metadata_Failed if removed else .Partial_Cleanup_Failed
		failure.platform_code = platform_code
		return state.result, false, failure
	}
	state.result.identity = identity
	state.result.outcome = .Applied
	if request.source_kind == .Directory {
		state.result.durability = .Best_Effort_Directory_Metadata
	} else {
		state.result.durability = .File_Data_Synced
	}
	return state.result, true, {}
}

@(private)
copy_resource :: proc(
	state: ^Copy_State,
	source, destination: string,
	identity: Resource_ID,
	depth: u16,
) -> (bool, Failure_Context) {
	failure := Failure_Context{operation = .Apply_Copy}
	if depth > state.request.limits.depth {
		failure.code = .Copy_Depth_Limit
		failure.actual = u64(depth)
		failure.limit = u64(state.request.limits.depth)
		return false, failure
	}
	current, current_ok, platform_code := local_resource_identity(source)
	if !current_ok || current != identity {
		failure.code = .Source_Changed
		failure.platform_code = platform_code
		return false, failure
	}
	info, info_error := os.stat(source, state.allocators.temporary)
	if info_error != nil {
		failure.code = .Metadata_Failed
		return false, failure
	}
	defer os.file_info_delete(info, state.allocators.temporary)
	if info.type == .Directory {
		if os.make_directory(destination) != nil {
			failure.code = .Copy_Failed
			return false, failure
		}
		state.result.entries += 1
		if state.result.entries > state.request.limits.entries {
			failure.code = .Copy_Entry_Limit
			failure.actual = u64(state.result.entries)
			failure.limit = u64(state.request.limits.entries)
			return false, failure
		}
		batch, observed, observe_failure := directory_observe(
			source, u64(depth),
			{persistent = state.allocators.temporary, temporary = state.allocators.temporary}, true,
		)
		if !observed { observe_failure.operation = .Apply_Copy; return false, observe_failure }
		defer directory_batch_close(&batch)
		if batch.directory_identity != identity {
			failure.code = .Directory_Changed
			return false, failure
		}
		for entry in batch.descriptors {
			source_child, source_error := os.join_path({source, entry.name}, state.allocators.temporary)
			destination_child, destination_error := os.join_path(
				{destination, entry.name}, state.allocators.temporary,
			)
			if source_error != nil || destination_error != nil {
				if source_error == nil do delete(source_child, state.allocators.temporary)
				if destination_error == nil do delete(destination_child, state.allocators.temporary)
				failure.code = .Persistent_Memory_Limit
				return false, failure
			}
			if len(source_child) > MAX_PATH_STORAGE_BYTES || len(destination_child) > MAX_PATH_STORAGE_BYTES {
				delete(destination_child, state.allocators.temporary)
				delete(source_child, state.allocators.temporary)
				failure.code = .Path_Limit
				return false, failure
			}
			child_ok, child_failure := copy_resource(
				state, source_child, destination_child, entry.identity, depth + 1,
			)
			delete(destination_child, state.allocators.temporary)
			delete(source_child, state.allocators.temporary)
			if !child_ok do return false, child_failure
		}
		return true, {}
	}
	if info.type != .Regular {
		failure.code = .Source_Changed
		return false, failure
	}
	size := u64(max(info.size, 0))
	if info.size < 0 || state.result.bytes > state.request.limits.bytes ||
	   size > state.request.limits.bytes - state.result.bytes {
		failure.code = .Copy_Byte_Limit
		failure.actual = state.result.bytes + size
		failure.limit = state.request.limits.bytes
		return false, failure
	}
	source_file, source_error := os.open(source, {.Read})
	if source_error != nil { failure.code = .Copy_Failed; return false, failure }
	defer os.close(source_file)
	destination_file, destination_error := os.open(
		destination, {.Write, .Create, .Excl}, os.Permissions_Default_File,
	)
	if destination_error != nil { failure.code = .Copy_Failed; return false, failure }
	destination_open := true
	defer if destination_open do os.close(destination_file)
	buffer: [65_536]u8
	for {
		count, read_error := os.read(source_file, buffer[:])
		if read_error != nil && read_error != io.Error.EOF {
			failure.code = .Copy_Failed
			return false, failure
		}
		if count == 0 do break
		written := 0
		for written < count {
			step, write_error := os.write(destination_file, buffer[written:count])
			if write_error != nil || step <= 0 { failure.code = .Copy_Failed; return false, failure }
			written += step
		}
		state.result.bytes += u64(count)
		if state.result.bytes > state.request.limits.bytes {
			failure.code = .Copy_Byte_Limit
			failure.actual = state.result.bytes
			failure.limit = state.request.limits.bytes
			return false, failure
		}
	}
	if os.sync(destination_file) != nil {
		failure.code = .Copy_Durability_Failed
		return false, failure
	}
	if os.close(destination_file) != nil {
		failure.code = .Copy_Failed
		return false, failure
	}
	destination_open = false
	state.result.entries += 1
	if state.result.entries > state.request.limits.entries {
		failure.code = .Copy_Entry_Limit
		failure.actual = u64(state.result.entries)
		failure.limit = u64(state.request.limits.entries)
		return false, failure
	}
	return true, {}
}
