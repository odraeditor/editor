// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package filesystem

import "core:fmt"
import "core:os"
import "core:strings"
import "core:unicode/utf8"
import "base:runtime"

/* directory_rename_batch_apply preflights and applies one same-directory rename set. */
directory_rename_batch_apply :: proc(
	directory: string,
	directory_identity: Resource_ID,
	requests: []Rename_Request,
	results: []Rename_Result,
	allocators: Allocator_Set,
) -> (bool, Failure_Context) {
	failure := Failure_Context{operation = .Apply_Rename_Batch}
	if len(requests) == 0 || len(results) < len(requests) ||
	   !resource_id_valid(directory_identity) || allocators.persistent.procedure == nil ||
	   allocators.temporary.procedure == nil {
		failure.code = .Invalid_Arguments
		return false, failure
	}
	for request, index in requests do results[index] = {identity = request.identity, outcome = .Unapplied}
	observed, observed_ok, observed_failure := directory_observe(
		directory,
		1,
		{persistent = allocators.temporary, temporary = allocators.temporary},
		true,
	)
	if !observed_ok {
		observed_failure.operation = .Apply_Rename_Batch
		return false, observed_failure
	}
	defer directory_batch_close(&observed)
	if observed.directory_identity != directory_identity {
		failure.code = .Directory_Changed
		return false, failure
	}
	for request, index in requests {
		if !resource_id_valid(request.identity) || !rename_name_valid(request.from) ||
		   !rename_name_valid(request.to) || request.from == request.to {
			failure.code = .Invalid_Name
			failure.actual = u64(index)
			return false, failure
		}
		entry, found := directory_entry_find(&observed, request.identity)
		if !found || entry.name != request.from {
			failure.code = .Source_Changed
			failure.actual = u64(index)
			return false, failure
		}
		for previous in requests[:index] {
			if previous.to == request.to || previous.identity == request.identity {
				failure.code = .Duplicate_Destination
				failure.actual = u64(index)
				return false, failure
			}
		}
		for existing in observed.descriptors {
			if existing.name != request.to do continue
			is_source := false
			for candidate in requests do if candidate.identity == existing.identity do is_source = true
			if !is_source {
				failure.code = .Destination_Exists
				failure.actual = u64(index)
				return false, failure
			}
		}
	}
	source_paths, allocation_error := make([]string, len(requests), allocators.temporary)
	if allocation_error != nil { failure.code = .Persistent_Memory_Limit; return false, failure }
	defer for path in source_paths do if len(path) > 0 do delete(path, allocators.temporary)
	temporary_paths: []string
	temporary_paths, allocation_error = make([]string, len(requests), allocators.temporary)
	if allocation_error != nil { failure.code = .Persistent_Memory_Limit; return false, failure }
	defer for path in temporary_paths do if len(path) > 0 do delete(path, allocators.temporary)
	destination_paths: []string
	destination_paths, allocation_error = make([]string, len(requests), allocators.temporary)
	if allocation_error != nil { failure.code = .Persistent_Memory_Limit; return false, failure }
	defer for path in destination_paths do if len(path) > 0 do delete(path, allocators.temporary)
	for request, index in requests {
		path_error: runtime.Allocator_Error
		source_paths[index], path_error = os.join_path({directory, request.from}, allocators.temporary)
		if path_error != nil { failure.code = .Persistent_Memory_Limit; return false, failure }
		destination_paths[index], path_error = os.join_path({directory, request.to}, allocators.temporary)
		if path_error != nil { failure.code = .Persistent_Memory_Limit; return false, failure }
		name_storage: [128]u8
		temporary_name := fmt.bprintf(name_storage[:], ".odra-rename-%016x-%04d", directory_identity.inode, index)
		temporary_paths[index], path_error = os.join_path({directory, temporary_name}, allocators.temporary)
		if path_error != nil { failure.code = .Persistent_Memory_Limit; return false, failure }
		if _, exists, _ := local_resource_identity(temporary_paths[index]); exists {
			failure.code = .Destination_Exists
			failure.actual = u64(index)
			return false, failure
		}
	}
	staged := 0
	for _, index in requests {
		if os.rename(source_paths[index], temporary_paths[index]) != nil {
			failure.code = .Rename_Failed
			failure.actual = u64(index)
			for rollback in 0 ..< staged {
				if os.rename(temporary_paths[rollback], source_paths[rollback]) != nil {
					failure.code = .Rollback_Failed
					results[rollback].outcome = .Failed
				} else {
					results[rollback].outcome = .Rolled_Back
				}
			}
			return false, failure
		}
		staged += 1
	}
	applied := 0
	for _, index in requests {
		if os.rename(temporary_paths[index], destination_paths[index]) != nil {
			failure.code = .Rename_Failed
			failure.actual = u64(index)
			for rollback in 0 ..< applied {
				if os.rename(destination_paths[rollback], source_paths[rollback]) != nil {
					failure.code = .Rollback_Failed
					results[rollback].outcome = .Failed
				} else {
					results[rollback].outcome = .Rolled_Back
				}
			}
			for rollback in index ..< len(requests) {
				if os.rename(temporary_paths[rollback], source_paths[rollback]) != nil {
					failure.code = .Rollback_Failed
					results[rollback].outcome = .Failed
				} else {
					results[rollback].outcome = .Rolled_Back
				}
			}
			return false, failure
		}
		results[index].outcome = .Applied
		applied += 1
	}
	return true, {}
}

@(private)
rename_name_valid :: proc(name: string) -> bool {
	return len(name) > 0 && len(name) <= MAX_PATH_STORAGE_BYTES && utf8.valid_string(name) &&
	       strings.index_byte(name, 0) < 0 && !strings.contains(name, "/") && name != "." && name != ".."
}
