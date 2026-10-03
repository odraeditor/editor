// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package document

import "base:runtime"
import "core:strings"

@(private)
Relocation_State :: struct {
	owner:     ^Open_State,
	path:      string,
	allocator: runtime.Allocator,
}

/* document_relocation_prepare retains one checked replacement for an associated path. */
document_relocation_prepare :: proc(
	document: ^Document,
	expected_path, replacement_path: string,
	prepared: ^Prepared_Relocation,
	allocators: Allocator_Set,
	limits := DEFAULT_LIMITS,
) -> (bool, Failure_Context) {
	if prepared == nil || prepared.state != nil {
		return false, Failure_Context{operation = .Prepare_Relocation, code = .Invalid_Preparation}
	}
	owner := document_open_state(document)
	if owner == nil || owner.prepared {
		return false, Failure_Context{operation = .Prepare_Relocation, code = .Closed_Document}
	}
	failure := Failure_Context {
		operation = .Prepare_Relocation,
		document_id = owner.document_id,
		buffer_id = owner.buffer_id,
	}
	if owner.kind == .Unassociated || owner.path != expected_path {
		failure.code = .Target_Changed
		return false, failure
	}
	if owner.active_operations != 0 || owner.active_snapshots != 0 {
		failure.code = .Operation_In_Progress
		failure.actual = u64(owner.active_operations) + u64(owner.active_snapshots)
		return false, failure
	}
	normalized: Normalized_Path
	if normalized_ok, normalized_failure := path_normalize(
		replacement_path, &normalized, allocators.temporary, limits,
	); !normalized_ok {
		normalized_failure.operation = .Prepare_Relocation
		return false, normalized_failure
	}
	target := normalized_path_text(&normalized)
	if target == owner.path {
		failure.code = .Target_Changed
		return false, failure
	}
	state, state_error := new(Relocation_State, allocators.persistent)
	if state_error != nil {
		failure.code = .Persistent_Memory_Limit
		return false, failure
	}
	path, path_error := strings.clone(target, allocators.persistent)
	if path_error != nil {
		free(state, allocators.persistent)
		failure.code = .Persistent_Memory_Limit
		return false, failure
	}
	state.owner = owner
	state.path = path
	state.allocator = allocators.persistent
	prepared.state = state
	return true, {}
}

/* prepared_relocation_publish replaces one document path without filesystem authority. */
prepared_relocation_publish :: proc(prepared: ^Prepared_Relocation) -> (bool, Failure_Context) {
	state := relocation_state(prepared)
	if state == nil || state.owner == nil {
		return false, Failure_Context{operation = .Publish_Relocation, code = .Invalid_Preparation}
	}
	owner := state.owner
	if len(owner.path) > 0 do delete(owner.path, owner.allocator)
	owner.path = state.path
	state.path = ""
	document_id := owner.document_id
	buffer_id := owner.buffer_id
	relocation_consume(prepared)
	return true, Failure_Context {
		operation = .Publish_Relocation,
		document_id = document_id,
		buffer_id = buffer_id,
	}
}

/* prepared_relocation_abort releases one replacement without changing its document. */
prepared_relocation_abort :: proc(prepared: ^Prepared_Relocation) -> (bool, Failure_Context) {
	state := relocation_state(prepared)
	if state == nil {
		return false, Failure_Context{operation = .Abort_Relocation, code = .Invalid_Preparation}
	}
	document_id := state.owner.document_id
	buffer_id := state.owner.buffer_id
	relocation_consume(prepared)
	return true, Failure_Context {
		operation = .Abort_Relocation,
		document_id = document_id,
		buffer_id = buffer_id,
	}
}

@(private)
relocation_state :: proc(prepared: ^Prepared_Relocation) -> ^Relocation_State {
	if prepared == nil || prepared.state == nil do return nil
	return (^Relocation_State)(prepared.state)
}

@(private)
relocation_consume :: proc(prepared: ^Prepared_Relocation) {
	state := relocation_state(prepared)
	if state == nil do return
	if len(state.path) > 0 do delete(state.path, state.allocator)
	allocator := state.allocator
	free(state, allocator)
	prepared.state = nil
}
