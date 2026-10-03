// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package filesystem

import "core:os"

/* directory_entry_move atomically moves one checked local child without overwrite. */
directory_entry_move :: proc(
	source_parent, destination_parent: string,
	request: Entry_Move_Request,
	allocators: Allocator_Set,
) -> (Entry_Move_Result, bool, Failure_Context) {
	failure := Failure_Context{operation = .Apply_Entry_Move}
	if len(source_parent) == 0 || len(destination_parent) == 0 ||
	   !resource_id_valid(request.source_parent_identity) ||
	   !resource_id_valid(request.source_identity) ||
	   !resource_id_valid(request.destination_parent_identity) ||
	   request.source_kind == .Invalid || !rename_name_valid(request.source_name) ||
	   !rename_name_valid(request.destination_name) || allocators.temporary.procedure == nil {
		failure.code = .Invalid_Arguments
		return {}, false, failure
	}
	source_batch, source_ok, source_failure := directory_observe(
		source_parent, 1, {persistent = allocators.temporary, temporary = allocators.temporary}, true,
	)
	if !source_ok {source_failure.operation = .Apply_Entry_Move; return {}, false, source_failure}
	defer directory_batch_close(&source_batch)
	if source_batch.directory_identity != request.source_parent_identity {
		failure.code = .Directory_Changed
		return {}, false, failure
	}
	source, found := directory_entry_find(&source_batch, request.source_identity)
	if !found || source.name != request.source_name || source.kind != request.source_kind {
		failure.code = .Source_Changed
		return {}, false, failure
	}
	destination_batch, destination_ok, destination_failure := directory_observe(
		destination_parent, 1,
		{persistent = allocators.temporary, temporary = allocators.temporary}, true,
	)
	if !destination_ok {destination_failure.operation = .Apply_Entry_Move; return {}, false, destination_failure}
	defer directory_batch_close(&destination_batch)
	if destination_batch.directory_identity != request.destination_parent_identity {
		failure.code = .Directory_Changed
		return {}, false, failure
	}
	for entry in destination_batch.descriptors do if entry.name == request.destination_name {
		failure.code = .Destination_Exists
		return {}, false, failure
	}
	if request.source_parent_identity.device != request.destination_parent_identity.device {
		failure.code = .Cross_Device_Move
		return {}, false, failure
	}
	source_path, source_error := os.join_path({source_parent, request.source_name}, allocators.temporary)
	destination_path, destination_error := os.join_path(
		{destination_parent, request.destination_name}, allocators.temporary,
	)
	if source_error != nil || destination_error != nil {
		if source_error == nil do delete(source_path, allocators.temporary)
		if destination_error == nil do delete(destination_path, allocators.temporary)
		failure.code = .Persistent_Memory_Limit
		return {}, false, failure
	}
	defer {delete(destination_path, allocators.temporary); delete(source_path, allocators.temporary)}
	if os.rename(source_path, destination_path) != nil {
		failure.code = .Rename_Failed
		return {}, false, failure
	}
	identity, identified, platform_code := local_resource_identity(destination_path)
	if !identified || identity != request.source_identity {
		failure.code = .Metadata_Failed
		failure.platform_code = platform_code
		return {}, false, failure
	}
	return Entry_Move_Result{identity = identity, changed = source_path != destination_path}, true, {}
}
