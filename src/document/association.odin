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
Association_State :: struct {
	owner:       ^Open_State,
	path:        string,
	observation: External_Observation,
	target_exists: bool,
	allocator:   runtime.Allocator,
}

/*
document_association_prepare validates one path and retains it privately for an
unassociated document. The document remains observably unassociated until a
prepared first save reaches publication.
*/
document_association_prepare :: proc(
	document: ^Document,
	path: string,
	prepared: ^Prepared_Association,
	allocators: Allocator_Set,
	limits := DEFAULT_LIMITS,
) -> (ok: bool, failure: Failure_Context) {
	return document_association_prepare_with_io(
		document,
		path,
		prepared,
		allocators,
		limits,
		linux_save_io(),
	)
}

/*
prepared_association_publish attempts the first safe save and consumes the
candidate. A pre-publication failure restores unassociated state; a published
result commits the association even when directory durability is uncertain.
*/
prepared_association_publish :: proc(
	prepared: ^Prepared_Association,
	buffer: ^editor.Buffer,
) -> (result: Save_Result, ok: bool, failure: Failure_Context) {
	state := prepared_association_state(prepared)
	if state == nil {
		return {}, false, Failure_Context {
			code = .Invalid_Preparation,
			operation = .Publish_Association,
			publication = .Not_Published,
		}
	}
	owner := state.owner
	owner.path = state.path
	state.path = ""
	owner.observation = state.observation
	owner.kind = .Materialized if state.target_exists else .Unmaterialized
	owner.persistence = .Modified if state.target_exists else .Unmaterialized

	save: Prepared_Save
	prepared_ok, prepare_failure := save_prepare_with_io(
		&Document{state = owner},
		buffer,
		&save,
		DEFAULT_LIMITS,
		linux_save_io(),
	)
	if !prepared_ok {
		result = Save_Result {
			document_id = owner.document_id,
			buffer_id = owner.buffer_id,
			publication = .Not_Published,
		}
		rollback_private_association(owner)
		consume_association(prepared)
		prepare_failure.operation = .Publish_Association
		return result, false, prepare_failure
	}
	saved: bool
	save_failure: Failure_Context
	result, saved, save_failure = prepared_save_publish(&save)
	if result.publication == .Not_Published {
		rollback_private_association(owner)
	}
	consume_association(prepared)
	if !saved {
		save_failure.operation = .Publish_Association
		return result, false, save_failure
	}
	return result, true, {}
}

/* prepared_association_abort releases a private path without changing its document. */
prepared_association_abort :: proc(
	prepared: ^Prepared_Association,
) -> (ok: bool, failure: Failure_Context) {
	state := prepared_association_state(prepared)
	if state == nil {
		return false, Failure_Context {
			code = .Invalid_Preparation,
			operation = .Abort_Association,
		}
	}
	document_id := state.owner.document_id
	buffer_id := state.owner.buffer_id
	consume_association(prepared)
	return true, Failure_Context {
		operation = .Abort_Association,
		document_id = document_id,
		buffer_id = buffer_id,
	}
}

@(private)
document_association_prepare_with_io :: proc(
	document: ^Document,
	path: string,
	prepared: ^Prepared_Association,
	allocators: Allocator_Set,
	limits: Limits,
	io: Save_IO,
) -> (ok: bool, failure: Failure_Context) {
	assert(prepared != nil)
	assert(prepared.state == nil, "association preparation is already initialized")
	owner := document_open_state(document)
	if owner == nil || owner.prepared {
		return false, Failure_Context{code = .Closed_Document, operation = .Prepare_Association}
	}
	failure = association_failure(owner, .None)
	if owner.kind != .Unassociated {
		failure.code = .Path_Not_Allowed
		return false, failure
	}
	if owner.active_operations != 0 || owner.active_snapshots != 0 {
		failure.code = .Operation_In_Progress
		failure.actual = u64(owner.active_operations) + u64(owner.active_snapshots)
		return false, failure
	}
	if !limits_are_valid(limits) {
		failure.code = .Invalid_Limits
		return false, failure
	}
	if allocators.persistent.procedure == nil {
		failure.code = .Persistent_Memory_Limit
		return false, failure
	}
	if allocators.temporary.procedure == nil {
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

	absolute, absolute_error := resolve_absolute_path(path, allocators.temporary)
	if absolute_error != nil {
		failure.code = .Temporary_Memory_Limit
		failure.actual = u64(len(path))
		return false, failure
	}
	defer delete(absolute, allocators.temporary)
	if len(absolute) == 0 || u64(len(absolute)) > limits.path_bytes {
		failure.code = .Path_Limit
		failure.limit = limits.path_bytes
		failure.actual = u64(len(absolute))
		return false, failure
	}

	parent := os.dir(absolute)
	parent_metadata, parent_error := io.inspect(parent, true, allocators.temporary)
	if parent_error.code != .None {
		failure = association_platform_failure(owner, .Parent_Inaccessible, parent_error)
		if parent_error.code == .Not_Found {
			failure.code = .Parent_Not_Found
		}
		return false, failure
	}
	if parent_metadata.kind != .Directory {
		failure.code = .Parent_Not_Directory
		return false, failure
	}

	target, target_error := io.inspect(absolute, false, allocators.temporary)
	target_exists := target_error.code == .None
	if target_error.code != .None && target_error.code != .Not_Found {
		return false, association_platform_failure(owner, .Target_Inaccessible, target_error)
	}
	if target_exists && target.kind == .Symbolic_Link {
		failure.code = .Target_Is_Symbolic_Link
		return false, failure
	}
	if target_exists && target.kind != .Regular {
		failure.code = .Target_Not_Regular
		return false, failure
	}

	state, state_error := new(Association_State, allocators.persistent)
	if state_error != nil {
		failure.code = .Persistent_Memory_Limit
		failure.actual = u64(size_of(Association_State))
		return false, failure
	}
	owned_path, path_error := strings.clone(absolute, allocators.persistent)
	if path_error != nil {
		free(state, allocators.persistent)
		failure.code = .Persistent_Memory_Limit
		failure.actual = u64(len(absolute))
		return false, failure
	}
	state.owner = owner
	state.path = owned_path
	state.target_exists = target_exists
	state.allocator = allocators.persistent
	if target_exists {
		state.observation = observation_from_metadata(target)
	}
	prepared.state = state
	return true, {}
}

@(private)
rollback_private_association :: proc(owner: ^Open_State) {
	if len(owner.path) > 0 {
		delete(owner.path, owner.allocator)
	}
	owner.path = ""
	owner.kind = .Unassociated
	owner.persistence = .Unassociated
	owner.observation = {}
	owner.has_saved_revision = false
	owner.saved_revision = {}
}

@(private)
consume_association :: proc(prepared: ^Prepared_Association) {
	state := prepared_association_state(prepared)
	assert(state != nil)
	allocator := state.allocator
	if len(state.path) > 0 {
		delete(state.path, allocator)
	}
	prepared.state = nil
	free(state, allocator)
}

@(private)
prepared_association_state :: proc(prepared: ^Prepared_Association) -> ^Association_State {
	if prepared == nil || prepared.state == nil {
		return nil
	}
	return (^Association_State)(prepared.state)
}

@(private)
association_failure :: proc(owner: ^Open_State, code: Failure_Code) -> Failure_Context {
	return Failure_Context {
		code = code,
		operation = .Prepare_Association,
		document_id = owner.document_id,
		buffer_id = owner.buffer_id,
		publication = .Not_Published,
	}
}

@(private)
association_platform_failure :: proc(
	owner: ^Open_State,
	code: Failure_Code,
	platform_error: Platform_Error,
) -> Failure_Context {
	failure := association_failure(owner, code)
	failure.platform_code = platform_error.platform_code
	return failure
}
