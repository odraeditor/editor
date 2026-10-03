// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package filesystem

import "base:runtime"
import "core:os"
import "core:slice"
import "core:strings"
import "core:time"
import "core:unicode/utf8"

@(private)
Directory_State :: struct {
	infos:       []os.File_Info,
	descriptors: []Entry_Descriptor,
	labels:      []string,
	allocator:   runtime.Allocator,
}

/* path_normalize validates and copies one lexical absolute local path. */
path_normalize :: proc(
	path: string,
	normalized: ^Normalized_Path,
	temporary: runtime.Allocator,
) -> (bool, Failure_Context) {
	if normalized == nil {
		return false, Failure_Context{operation = .Normalize_Path, code = .Invalid_Arguments}
	}
	normalized^ = {}
	failure := Failure_Context{operation = .Normalize_Path}
	if temporary.procedure == nil {
		failure.code = .Invalid_Arguments
		return false, failure
	}
	if len(path) == 0 {
		failure.code = .Path_Empty
		return false, failure
	}
	if len(path) > MAX_PATH_STORAGE_BYTES {
		failure.code = .Path_Limit
		failure.limit = MAX_PATH_BYTES
		failure.actual = u64(len(path))
		return false, failure
	}
	if !utf8.valid_string(path) {
		failure.code = .Path_Malformed_UTF8
		return false, failure
	}
	if nul_index := strings.index_byte(path, 0); nul_index >= 0 {
		failure.code = .Path_Contains_Nul
		failure.byte_offset = u64(nul_index)
		return false, failure
	}
	absolute, absolute_error := local_absolute_path(path, temporary)
	if absolute_error != nil {
		failure.code = .Path_Normalization_Failed
		return false, failure
	}
	defer delete(absolute, temporary)
	if len(absolute) == 0 || len(absolute) > MAX_PATH_STORAGE_BYTES {
		failure.code = .Path_Limit
		failure.limit = MAX_PATH_BYTES
		failure.actual = u64(len(absolute))
		return false, failure
	}
	copy(normalized.bytes[:], transmute([]u8)absolute)
	normalized.length = len(absolute)
	return true, {}
}

@(private)
local_absolute_path :: proc(path: string, allocator: runtime.Allocator) -> (string, runtime.Allocator_Error) {
	if os.is_absolute_path(path) do return os.clean_path(path, allocator)
	working_directory, working_error := os.get_working_directory(allocator)
	if working_error != nil do return "", .Out_Of_Memory
	defer delete(working_directory, allocator)
	return os.join_path({working_directory, path}, allocator)
}

/* directory_observe copies one complete bounded immediate-directory generation. */
directory_observe :: proc(
	path: string,
	generation: u64,
	allocators: Allocator_Set,
	include_hidden := false,
) -> (batch: Directory_Batch, ok: bool, failure: Failure_Context) {
	failure.operation = .Observe_Directory
	if generation == 0 || allocators.persistent.procedure == nil ||
	   allocators.temporary.procedure == nil {
		failure.code = .Invalid_Arguments
		return {}, false, failure
	}
	normalized: Normalized_Path
	if normalized_ok, normalize_failure := path_normalize(path, &normalized, allocators.temporary);
	   !normalized_ok {
		normalize_failure.operation = .Observe_Directory
		return {}, false, normalize_failure
	}
	directory_path := normalized_path_text(&normalized)
	directory_identity, directory_identified, platform_code := local_resource_identity(directory_path)
	if !directory_identified {
		failure.code = .Metadata_Failed
		failure.platform_code = platform_code
		return {}, false, failure
	}
	infos, directory_error := os.read_directory_by_path(
		directory_path,
		int(MAX_DIRECTORY_ENTRIES) + 1,
		allocators.persistent,
	)
	if directory_error != nil {
		failure.code = .Directory_Open_Failed
		return {}, false, failure
	}
	if len(infos) > int(MAX_DIRECTORY_ENTRIES) {
		actual := len(infos)
		os.file_info_slice_delete(infos, allocators.persistent)
		failure.code = .Directory_Entry_Limit
		failure.limit = u64(MAX_DIRECTORY_ENTRIES)
		failure.actual = u64(actual)
		return {}, false, failure
	}
	state, state_error := new(Directory_State, allocators.persistent)
	if state_error != nil {
		os.file_info_slice_delete(infos, allocators.persistent)
		failure.code = .Persistent_Memory_Limit
		return {}, false, failure
	}
	state.allocator = allocators.persistent
	state.infos = infos
	state.descriptors, state_error = make([]Entry_Descriptor, len(infos), allocators.persistent)
	if state_error != nil {
		directory_state_release(state)
		failure.code = .Persistent_Memory_Limit
		return {}, false, failure
	}
	state.labels, state_error = make([]string, len(infos), allocators.persistent)
	if state_error != nil {
		directory_state_release(state)
		failure.code = .Persistent_Memory_Limit
		return {}, false, failure
	}
	count := 0
	for info in infos {
		if len(info.name) == 0 || len(info.name) > MAX_PATH_STORAGE_BYTES ||
		   len(info.fullpath) == 0 || len(info.fullpath) > MAX_PATH_STORAGE_BYTES ||
		   !utf8.valid_string(info.name) || !utf8.valid_string(info.fullpath) {
			directory_state_release(state)
			failure.code = .Path_Malformed_UTF8
			return {}, false, failure
		}
		if !include_hidden && info.name[0] == '.' do continue
		kind := Entry_Kind.Invalid
		#partial switch info.type {
		case .Regular:
			kind = .Regular_File
		case .Directory:
			kind = .Directory
		case:
			continue
		}
		identity, identified, identity_platform_code := local_resource_identity(info.fullpath)
		if !identified {
			directory_state_release(state)
			failure.code = .Metadata_Failed
			failure.platform_code = identity_platform_code
			return {}, false, failure
		}
		label := info.name
		if kind == .Directory {
			bytes, allocation_error := make([]u8, len(info.name) + 1, allocators.persistent)
			if allocation_error != nil {
				directory_state_release(state)
				failure.code = .Persistent_Memory_Limit
				return {}, false, failure
			}
			copy(bytes, transmute([]u8)info.name)
			bytes[len(info.name)] = '/'
			label = string(bytes)
			state.labels[count] = label
		}
		state.descriptors[count] = Entry_Descriptor {
			identity = identity,
			name = info.name,
			label = label,
			path = info.fullpath,
			kind = kind,
			permissions = transmute(u32)info.mode,
			size_bytes = info.size,
			modified_seconds = time.to_unix_seconds(info.modification_time),
		}
		count += 1
	}
	state.descriptors = state.descriptors[:count]
	state.labels = state.labels[:count]
	slice.sort_by(state.descriptors, directory_entry_less)
	batch = Directory_Batch {
		directory = normalized,
		directory_identity = directory_identity,
		generation = generation,
		descriptors = state.descriptors,
		state = state,
	}
	return batch, true, {}
}

/* directory_batch_close releases one copied directory observation. */
directory_batch_close :: proc(batch: ^Directory_Batch) -> (bool, Failure_Context) {
	if batch == nil || batch.state == nil {
		return false, Failure_Context{
			operation = .Close_Directory_Observation,
			code = .Invalid_Arguments,
		}
	}
	directory_state_release(cast(^Directory_State)batch.state)
	batch^ = {}
	return true, {}
}

/* directory_entry_find revalidates one stable identity within its immutable batch. */
directory_entry_find :: proc(batch: ^Directory_Batch, identity: Resource_ID) -> (Entry_Descriptor, bool) {
	if batch == nil || batch.state == nil || !resource_id_valid(identity) do return {}, false
	for descriptor in batch.descriptors {
		if descriptor.identity == identity do return descriptor, true
	}
	return {}, false
}

@(private)
directory_state_release :: proc(state: ^Directory_State) {
	if state == nil do return
	for label in state.labels {
		if len(label) > 0 do delete(label, state.allocator)
	}
	delete(state.labels, state.allocator)
	delete(state.descriptors, state.allocator)
	os.file_info_slice_delete(state.infos, state.allocator)
	free(state, state.allocator)
}

@(private)
directory_entry_less :: proc(left, right: Entry_Descriptor) -> bool {
	if left.kind != right.kind do return left.kind == .Directory
	return strings.compare(left.label, right.label) < 0
}
