// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package document

import "../editor"
import "base:runtime"
import "core:os"
import "core:strings"
import "core:unicode/utf8"

@(private)
Open_State :: struct {
	document_id:        Document_ID,
	buffer_id:          editor.Buffer_ID,
	kind:               Open_Kind,
	encoding:           Encoding_Policy,
	path:               string,
	contents:           []u8,
	observation:        External_Observation,
	persistence:        Persistence_State,
	has_saved_revision: bool,
	saved_revision:     editor.Revision,
	active_operations:  u32,
	active_snapshots:   u32,
	allocator:          runtime.Allocator,
	prepared:           bool,
}

/*
path_normalize validates one local path and copies its lexical absolute form.
It performs no filesystem inspection or file read.
*/
path_normalize :: proc(
	path: string,
	normalized: ^Normalized_Path,
	temporary: runtime.Allocator,
	limits := DEFAULT_LIMITS,
) -> (ok: bool, failure: Failure_Context) {
	assert(normalized != nil)
	normalized^ = {}
	failure.operation = .Normalize_Path
	if !limits_are_valid(limits) {
		failure.code = .Invalid_Limits
		return false, failure
	}
	if temporary.procedure == nil {
		failure.code = .Temporary_Memory_Limit
		return false, failure
	}
	if len(path) == 0 {
		failure.code = .Path_Empty
		return false, failure
	}
	if u64(len(path)) > limits.path_bytes {
		failure.code = .Path_Limit
		failure.limit = limits.path_bytes
		failure.actual = u64(len(path))
		return false, failure
	}
	if !utf8.valid_string(path) {
		failure.code = .Path_Malformed_UTF8
		failure.byte_offset = first_invalid_utf8_byte(path)
		return false, failure
	}
	nul_index := strings.index_byte(path, 0)
	if nul_index >= 0 {
		failure.code = .Path_Contains_Nul
		failure.byte_offset = u64(nul_index)
		return false, failure
	}
	absolute, absolute_error := resolve_absolute_path(path, temporary)
	if absolute_error != nil {
		failure.code = .Temporary_Memory_Limit
		failure.actual = u64(len(path))
		return false, failure
	}
	defer delete(absolute, temporary)
	if len(absolute) == 0 || u64(len(absolute)) > limits.path_bytes ||
	   len(absolute) > len(normalized.bytes) {
		failure.code = .Path_Limit
		failure.limit = limits.path_bytes
		failure.actual = u64(len(absolute))
		return false, failure
	}
	copy(normalized.bytes[:], absolute)
	normalized.length = len(absolute)
	return true, {}
}

/* normalized_path_text borrows the complete copied path from one normalized value. */
normalized_path_text :: proc(normalized: ^Normalized_Path) -> string {
	if normalized == nil || normalized.length <= 0 || normalized.length > len(normalized.bytes) {
		return ""
	}
	return string(normalized.bytes[:normalized.length])
}

/*
open_prepare validates and privately reads one zero-or-one-path startup request.
The caller must consume a successful candidate with prepared_open_commit or
prepared_open_abort. No document is published on failure.
*/
open_prepare :: proc(
	prepared: ^Prepared_Open,
	request: Open_Request,
	allocators: Allocator_Set,
	limits := DEFAULT_LIMITS,
) -> (ok: bool, failure: Failure_Context) {
	return open_prepare_with_io(prepared, request, allocators, limits, linux_open_io())
}

/* prepared_open_view borrows the validated path and exact UTF-8 bytes from a candidate. */
prepared_open_view :: proc(
	prepared: ^Prepared_Open,
) -> (view: Open_View, ok: bool, failure: Failure_Context) {
	state := prepared_open_state(prepared)
	if state == nil || !state.prepared {
		return {}, false, Failure_Context {
			code = .Invalid_Preparation,
			operation = .Inspect_Prepared_Open,
		}
	}
	return Open_View {
		document_id = state.document_id,
		buffer_id = state.buffer_id,
		kind = state.kind,
		encoding = state.encoding,
		path = state.path,
		contents = string(state.contents),
		observation = state.observation,
	}, true, {}
}

/*
prepared_open_commit publishes one prepared association at the supplied initial
buffer revision and releases the no-longer-needed source bytes.
*/
prepared_open_commit :: proc(
	prepared: ^Prepared_Open,
	document: ^Document,
	initial_revision: editor.Revision,
) -> (ok: bool, failure: Failure_Context) {
	assert(document != nil)
	assert(document.state == nil, "document is already initialized")
	state := prepared_open_state(prepared)
	if state == nil || !state.prepared {
		return false, Failure_Context {
			code = .Invalid_Preparation,
			operation = .Commit_Open,
		}
	}

	if len(state.contents) > 0 {
		delete(state.contents, state.allocator)
		state.contents = nil
	}
	state.prepared = false
	switch state.kind {
	case .Invalid:
		assert(false, "prepared open has an invalid kind")
	case .Unassociated:
		state.persistence = .Unassociated
	case .Unmaterialized:
		state.persistence = .Unmaterialized
	case .Materialized:
		state.persistence = .Clean
		state.has_saved_revision = true
		state.saved_revision = initial_revision
	}
	document.state = state
	prepared.state = nil
	return true, {}
}

/* prepared_open_abort releases a private candidate without publishing a document. */
prepared_open_abort :: proc(
	prepared: ^Prepared_Open,
) -> (ok: bool, failure: Failure_Context) {
	state := prepared_open_state(prepared)
	if state == nil || !state.prepared {
		return false, Failure_Context {
			code = .Invalid_Preparation,
			operation = .Abort_Open,
		}
	}
	prepared.state = nil
	release_open_state(state)
	return true, {}
}

/* document_status reports immutable lifecycle state and a borrowed target path. */
document_status :: proc(
	document: ^Document,
) -> (status: Document_Status, ok: bool, failure: Failure_Context) {
	state := document_open_state(document)
	if state == nil || state.prepared {
		return {}, false, Failure_Context {
			code = .Closed_Document,
			operation = .Inspect_Status,
		}
	}
	return Document_Status {
		document_id = state.document_id,
		buffer_id = state.buffer_id,
		persistence = state.persistence,
		encoding = state.encoding,
		has_target = state.kind != .Unassociated,
		materialized = state.kind == .Materialized,
		has_saved_revision = state.has_saved_revision,
		saved_revision = state.saved_revision,
		observation = state.observation,
		target_path = state.path,
	}, true, {}
}

/* document_close releases target identity and invalidates a live document handle. */
document_close :: proc(document: ^Document) -> (ok: bool, failure: Failure_Context) {
	state := document_open_state(document)
	if state == nil || state.prepared {
		return false, Failure_Context {
			code = .Closed_Document,
			operation = .Close,
		}
	}
	if state.active_operations != 0 || state.active_snapshots != 0 {
		return false, Failure_Context {
			code = .Operation_In_Progress,
			operation = .Close,
			document_id = state.document_id,
			buffer_id = state.buffer_id,
			limit = 0,
			actual = u64(state.active_operations) + u64(state.active_snapshots),
		}
	}
	document.state = nil
	document_id := state.document_id
	buffer_id := state.buffer_id
	release_open_state(state)
	return true, Failure_Context {
		operation = .Close,
		document_id = document_id,
		buffer_id = buffer_id,
	}
}

@(private)
open_prepare_with_io :: proc(
	prepared: ^Prepared_Open,
	request: Open_Request,
	allocators: Allocator_Set,
	limits: Limits,
	io: Open_IO,
) -> (ok: bool, failure: Failure_Context) {
	assert(prepared != nil)
	assert(prepared.state == nil, "open preparation is already initialized")
	failure = validate_open_request(request, allocators, limits)
	if failure.code != .None {
		return false, failure
	}

	state, allocation_error := new(Open_State, allocators.persistent)
	if allocation_error != nil {
		return false, open_failure(request, .Persistent_Memory_Limit, u64(size_of(Open_State)))
	}
	state.document_id = request.document_id
	state.buffer_id = request.buffer_id
	state.encoding = request.encoding
	state.allocator = allocators.persistent
	state.prepared = true

	if !request.has_path {
		state.kind = .Unassociated
		prepared.state = state
		return true, {}
	}

	absolute, absolute_error := resolve_absolute_path(request.path, allocators.temporary)
	if absolute_error != nil {
		release_open_state(state)
		return false, open_failure(request, .Temporary_Memory_Limit, u64(len(request.path)))
	}
	defer delete(absolute, allocators.temporary)
	if len(absolute) == 0 || u64(len(absolute)) > limits.path_bytes {
		release_open_state(state)
		failure = open_failure(request, .Path_Limit, u64(len(absolute)))
		failure.limit = limits.path_bytes
		return false, failure
	}
	path, path_error := strings.clone(absolute, allocators.persistent)
	if path_error != nil {
		release_open_state(state)
		return false, open_failure(request, .Persistent_Memory_Limit, u64(len(absolute)))
	}
	state.path = path

	parent := os.dir(absolute)
	parent_metadata, parent_error := io.inspect(parent, true, allocators.temporary)
	if parent_error.code != .None {
		failure = platform_failure(request, .Parent_Inaccessible, parent_error)
		if parent_error.code == .Not_Found {
			failure.code = .Parent_Not_Found
		}
		release_open_state(state)
		return false, failure
	}
	if parent_metadata.kind != .Directory {
		release_open_state(state)
		return false, open_failure(request, .Parent_Not_Directory, 0)
	}

	metadata, inspect_error := io.inspect(absolute, false, allocators.temporary)
	if inspect_error.code == .Not_Found {
		state.kind = .Unmaterialized
		state.observation = External_Observation{}
		prepared.state = state
		return true, {}
	}
	if inspect_error.code != .None {
		failure = platform_failure(request, .Target_Inaccessible, inspect_error)
		release_open_state(state)
		return false, failure
	}
	if metadata.kind == .Symbolic_Link {
		release_open_state(state)
		return false, open_failure(request, .Target_Is_Symbolic_Link, 0)
	}
	if metadata.kind != .Regular {
		release_open_state(state)
		return false, open_failure(request, .Target_Not_Regular, 0)
	}
	if metadata.size > limits.file_bytes || metadata.size > u64(max(int)) {
		failure = open_failure(request, .File_Limit, metadata.size)
		failure.limit = limits.file_bytes
		release_open_state(state)
		return false, failure
	}

	handle, open_error := io.open_read(absolute, allocators.temporary)
	if open_error.code != .None {
		failure = platform_failure(request, .Open_Failed, open_error)
		release_open_state(state)
		return false, failure
	}
	opened_metadata, opened_error := io.inspect_handle(handle)
	if opened_error.code != .None || opened_metadata.kind != .Regular ||
	   opened_metadata.identity != metadata.identity || opened_metadata.size != metadata.size {
		io.close(handle)
		failure = platform_failure(request, .Target_Changed, opened_error)
		release_open_state(state)
		return false, failure
	}

	if metadata.size > 0 {
		state.contents, allocation_error = make([]u8, int(metadata.size), allocators.persistent)
		if allocation_error != nil {
			io.close(handle)
			release_open_state(state)
			return false, open_failure(request, .Persistent_Memory_Limit, metadata.size)
		}
	}
	read_failure := read_exact_file(io, handle, state.contents, limits, request)
	close_error := io.close(handle)
	if read_failure.code != .None {
		release_open_state(state)
		return false, read_failure
	}
	if close_error.code != .None {
		failure = platform_failure(request, .Read_Failed, close_error)
		release_open_state(state)
		return false, failure
	}

	contents := string(state.contents)
	if !utf8.valid_string(contents) {
		failure = open_failure(request, .Malformed_UTF8, u64(len(contents)))
		failure.byte_offset = first_invalid_utf8_byte(contents)
		release_open_state(state)
		return false, failure
	}
	state.kind = .Materialized
	state.observation = observation_from_metadata(metadata)
	prepared.state = state
	return true, {}
}

@(private)
validate_open_request :: proc(
	request: Open_Request,
	allocators: Allocator_Set,
	limits: Limits,
) -> Failure_Context {
	failure := open_failure(request, .None, 0)
	if request.document_id == Document_ID(0) {
		failure.code = .Invalid_Document_ID
	} else if request.buffer_id == editor.Buffer_ID(0) {
		failure.code = .Invalid_Buffer_ID
	} else if request.encoding != .UTF8 {
		failure.code = .Invalid_Encoding
	} else if !limits_are_valid(limits) {
		failure.code = .Invalid_Limits
	} else if allocators.persistent.procedure == nil {
		failure.code = .Persistent_Memory_Limit
	} else if allocators.temporary.procedure == nil {
		failure.code = .Temporary_Memory_Limit
	} else if !request.has_path && len(request.path) != 0 {
		failure.code = .Path_Not_Allowed
	} else if request.has_path && len(request.path) == 0 {
		failure.code = .Path_Empty
	} else if u64(len(request.path)) > limits.path_bytes {
		failure.code = .Path_Limit
		failure.limit = limits.path_bytes
		failure.actual = u64(len(request.path))
	} else if request.has_path && !utf8.valid_string(request.path) {
		failure.code = .Path_Malformed_UTF8
		failure.byte_offset = first_invalid_utf8_byte(request.path)
	} else if request.has_path && strings.index_byte(request.path, 0) >= 0 {
		failure.code = .Path_Contains_Nul
		failure.byte_offset = u64(strings.index_byte(request.path, 0))
	}
	return failure
}

@(private)
resolve_absolute_path :: proc(path: string, allocator: runtime.Allocator) -> (string, runtime.Allocator_Error) {
	if os.is_absolute_path(path) {
		return os.clean_path(path, allocator)
	}
	working_directory, working_error := os.get_working_directory(allocator)
	if working_error != nil {
		return "", .Out_Of_Memory
	}
	defer delete(working_directory, allocator)
	return os.join_path({working_directory, path}, allocator)
}

@(private)
read_exact_file :: proc(
	io: Open_IO,
	handle: Platform_Handle,
	contents: []u8,
	limits: Limits,
	request: Open_Request,
) -> Failure_Context {
	offset := 0
	retries: u32
	for offset < len(contents) {
		chunk_end := min(len(contents), offset + int(limits.io_chunk_bytes))
		read_count, read_error := io.read(handle, contents[offset:chunk_end])
		if read_error.code == .Interrupted && read_count == 0 {
			if retries >= limits.interrupted_io_retries {
				failure := platform_failure(request, .Work_Limit, read_error)
				failure.limit = u64(limits.interrupted_io_retries)
				failure.actual = u64(retries + 1)
				return failure
			}
			retries += 1
			continue
		}
		if read_error.code != .None {
			return platform_failure(request, .Read_Failed, read_error)
		}
		if read_count <= 0 {
			failure := open_failure(request, .Unexpected_End_Of_File, u64(offset))
			failure.byte_offset = u64(offset)
			return failure
		}
		offset += read_count
		retries = 0
	}

	extra: [1]u8
	extra_count, extra_error := io.read(handle, extra[:])
	if extra_error.code == .Interrupted {
		return platform_failure(request, .Target_Changed, extra_error)
	}
	if extra_error.code != .None {
		return platform_failure(request, .Read_Failed, extra_error)
	}
	if extra_count != 0 {
		failure := open_failure(request, .Target_Changed, u64(len(contents) + extra_count))
		failure.byte_offset = u64(len(contents))
		return failure
	}
	return {}
}

@(private)
first_invalid_utf8_byte :: proc(contents: string) -> u64 {
	for offset := 0; offset < len(contents); {
		decoded, width := utf8.decode_rune_in_string(contents[offset:])
		if decoded == utf8.RUNE_ERROR && width == 1 {
			return u64(offset)
		}
		offset += width
	}
	return u64(len(contents))
}

@(private)
observation_from_metadata :: proc(metadata: Platform_Metadata) -> External_Observation {
	return External_Observation {
		exists = true,
		identity = metadata.identity,
		encoded_bytes = metadata.size,
		modified_seconds = metadata.modified_seconds,
		modified_nanoseconds = metadata.modified_nanoseconds,
		mode = metadata.mode,
	}
}

@(private)
prepared_open_state :: proc(prepared: ^Prepared_Open) -> ^Open_State {
	if prepared == nil || prepared.state == nil {
		return nil
	}
	return (^Open_State)(prepared.state)
}

@(private)
document_open_state :: proc(document: ^Document) -> ^Open_State {
	if document == nil || document.state == nil {
		return nil
	}
	return (^Open_State)(document.state)
}

@(private)
release_open_state :: proc(state: ^Open_State) {
	if state == nil {
		return
	}
	allocator := state.allocator
	if len(state.contents) > 0 {
		delete(state.contents, allocator)
	}
	if len(state.path) > 0 {
		delete(state.path, allocator)
	}
	free(state, allocator)
}

@(private)
open_failure :: proc(request: Open_Request, code: Failure_Code, actual: u64) -> Failure_Context {
	return Failure_Context {
		code = code,
		operation = .Prepare_Open,
		document_id = request.document_id,
		buffer_id = request.buffer_id,
		actual = actual,
	}
}

@(private)
platform_failure :: proc(
	request: Open_Request,
	code: Failure_Code,
	platform_error: Platform_Error,
) -> Failure_Context {
	failure := open_failure(request, code, 0)
	failure.platform_code = platform_error.platform_code
	return failure
}
