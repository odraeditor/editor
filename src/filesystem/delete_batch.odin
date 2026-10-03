// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package filesystem

import "core:os"

/* directory_delete_batch_apply preflights all targets before permanent file deletion begins. */
directory_delete_batch_preflight :: proc(
	root: string,
	root_identity: Resource_ID,
	requests: []Delete_Request,
	allocators: Allocator_Set,
) -> (bool, Failure_Context) {
	failure := Failure_Context{operation = .Apply_Delete_Batch}
	if len(requests) == 0 || !resource_id_valid(root_identity) || allocators.temporary.procedure == nil {
		failure.code = .Invalid_Arguments
		return false, failure
	}
	observed, observed_ok, observed_failure := directory_observe(
		root, 1, {persistent = allocators.temporary, temporary = allocators.temporary}, true,
	)
	if !observed_ok { observed_failure.operation = .Apply_Delete_Batch; return false, observed_failure }
	defer directory_batch_close(&observed)
	if observed.directory_identity != root_identity { failure.code = .Directory_Changed; return false, failure }
	for request, index in requests {
		if !resource_id_valid(request.identity) || !rename_name_valid(request.name) || request.kind == .Invalid {
			failure.code = .Invalid_Name; failure.actual = u64(index); return false, failure
		}
		entry, found := directory_entry_find(&observed, request.identity)
		if !found || entry.name != request.name || entry.kind != request.kind {
			failure.code = .Source_Changed; failure.actual = u64(index); return false, failure
		}
		for previous in requests[:index] {
			if previous.identity == request.identity {
				failure.code = .Duplicate_Destination; failure.actual = u64(index); return false, failure
			}
		}
	}
	return true, {}
}

/* directory_delete_batch_apply preflights all targets before permanent file deletion begins. */
directory_delete_batch_apply :: proc(
	root: string,
	root_identity: Resource_ID,
	requests: []Delete_Request,
	results: []Delete_Result,
	allocators: Allocator_Set,
) -> (bool, Failure_Context) {
	failure := Failure_Context{operation = .Apply_Delete_Batch}
	if len(requests) == 0 || len(results) < len(requests) || !resource_id_valid(root_identity) ||
	   allocators.temporary.procedure == nil {
		failure.code = .Invalid_Arguments
		return false, failure
	}
	for request, index in requests {
		results[index] = {identity = request.identity, outcome = .Unapplied, recovery_available = false}
	}
	if valid, preflight_failure := directory_delete_batch_preflight(root, root_identity, requests, allocators); !valid {
		return false, preflight_failure
	}
	for request, index in requests {
		path, path_error := os.join_path({root, request.name}, allocators.temporary)
		if path_error != nil { failure.code = .Persistent_Memory_Limit; failure.actual = u64(index); return false, failure }
		removed := os.remove_all(path) if request.kind == .Directory else os.remove(path)
		delete(path, allocators.temporary)
		if removed != nil {
			failure.code = .Delete_Failed
			failure.actual = u64(index)
			results[index].outcome = .Failed
			return false, failure
		}
		results[index].outcome = .Applied
	}
	return true, {}
}
