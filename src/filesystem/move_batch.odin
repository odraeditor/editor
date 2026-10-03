// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package filesystem

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:unicode/utf8"

/* directory_move_batch_apply preflights and applies one root-relative move set. */
directory_move_batch_apply :: proc(
	root: string,
	root_identity: Resource_ID,
	requests: []Move_Request,
	results: []Rename_Result,
	allocators: Allocator_Set,
) -> (bool, Failure_Context) {
	failure := Failure_Context{operation = .Apply_Move_Batch}
	if len(requests) == 0 || len(results) < len(requests) || !resource_id_valid(root_identity) ||
	   allocators.temporary.procedure == nil {
		failure.code = .Invalid_Arguments
		return false, failure
	}
	for request, index in requests do results[index] = {identity = request.identity, outcome = .Unapplied}
	observed, observed_ok, observed_failure := directory_observe(
		root, 1, {persistent = allocators.temporary, temporary = allocators.temporary}, true,
	)
	if !observed_ok { observed_failure.operation = .Apply_Move_Batch; return false, observed_failure }
	defer directory_batch_close(&observed)
	if observed.directory_identity != root_identity { failure.code = .Directory_Changed; return false, failure }
	for request, index in requests {
		if !resource_id_valid(request.identity) || !rename_name_valid(request.from) ||
		   !relative_destination_valid(request.to) || request.from == request.to {
			failure.code = .Invalid_Name; failure.actual = u64(index); return false, failure
		}
		entry, found := directory_entry_find(&observed, request.identity)
		if !found || entry.name != request.from {
			failure.code = .Source_Changed; failure.actual = u64(index); return false, failure
		}
		if entry.kind == .Directory && len(request.to) > len(request.from) &&
		   strings.has_prefix(request.to, request.from) && request.to[len(request.from)] == '/' {
			failure.code = .Recursive_Move; failure.actual = u64(index); return false, failure
		}
		for previous in requests[:index] {
			if previous.to == request.to || previous.identity == request.identity {
				failure.code = .Duplicate_Destination; failure.actual = u64(index); return false, failure
			}
		}
		destination, destination_error := os.join_path({root, request.to}, allocators.temporary)
		if destination_error != nil { failure.code = .Persistent_Memory_Limit; return false, failure }
		if existing_identity, exists, _ := local_resource_identity(destination); exists {
			is_source := false
			for candidate in requests do if candidate.identity == existing_identity do is_source = true
			if !is_source { delete(destination, allocators.temporary); failure.code = .Destination_Exists; failure.actual = u64(index); return false, failure }
		}
		parent := filepath.dir(destination)
		parent_identity, parent_exists, _ := local_resource_identity(parent)
		delete(destination, allocators.temporary)
		if !parent_exists { failure.code = .Destination_Parent_Missing; failure.actual = u64(index); return false, failure }
		if parent_identity.device != root_identity.device {
			failure.code = .Cross_Device_Move; failure.actual = u64(index); return false, failure
		}
	}
	sources, allocation_error := make([]string, len(requests), allocators.temporary)
	if allocation_error != nil { failure.code = .Persistent_Memory_Limit; return false, failure }
	defer for value in sources do if len(value) > 0 do delete(value, allocators.temporary)
	temporaries: []string
	temporaries, allocation_error = make([]string, len(requests), allocators.temporary)
	if allocation_error != nil { failure.code = .Persistent_Memory_Limit; return false, failure }
	defer for value in temporaries do if len(value) > 0 do delete(value, allocators.temporary)
	destinations: []string
	destinations, allocation_error = make([]string, len(requests), allocators.temporary)
	if allocation_error != nil { failure.code = .Persistent_Memory_Limit; return false, failure }
	defer for value in destinations do if len(value) > 0 do delete(value, allocators.temporary)
	for request, index in requests {
		path_error: runtime.Allocator_Error
		sources[index], path_error = os.join_path({root, request.from}, allocators.temporary)
		if path_error != nil { failure.code = .Persistent_Memory_Limit; return false, failure }
		destinations[index], path_error = os.join_path({root, request.to}, allocators.temporary)
		if path_error != nil { failure.code = .Persistent_Memory_Limit; return false, failure }
		storage: [128]u8
		name := fmt.bprintf(storage[:], ".odra-move-%016x-%04d", root_identity.inode, index)
		temporaries[index], path_error = os.join_path({root, name}, allocators.temporary)
		if path_error != nil { failure.code = .Persistent_Memory_Limit; return false, failure }
		if _, exists, _ := local_resource_identity(temporaries[index]); exists {
			failure.code = .Destination_Exists; failure.actual = u64(index); return false, failure
		}
	}
	staged := 0
	for _, index in requests {
		if os.rename(sources[index], temporaries[index]) != nil {
			failure.code = .Rename_Failed; failure.actual = u64(index)
			for rollback in 0 ..< staged {
				if os.rename(temporaries[rollback], sources[rollback]) != nil { results[rollback].outcome = .Failed; failure.code = .Rollback_Failed } else { results[rollback].outcome = .Rolled_Back }
			}
			return false, failure
		}
		staged += 1
	}
	applied := 0
	for _, index in requests {
		if os.rename(temporaries[index], destinations[index]) != nil {
			failure.code = .Rename_Failed; failure.actual = u64(index)
			for rollback in 0 ..< applied {
				if os.rename(destinations[rollback], sources[rollback]) != nil { results[rollback].outcome = .Failed; failure.code = .Rollback_Failed } else { results[rollback].outcome = .Rolled_Back }
			}
			for rollback in index ..< len(requests) {
				if os.rename(temporaries[rollback], sources[rollback]) != nil { results[rollback].outcome = .Failed; failure.code = .Rollback_Failed } else { results[rollback].outcome = .Rolled_Back }
			}
			return false, failure
		}
		results[index].outcome = .Applied
		applied += 1
	}
	return true, {}
}

@(private)
relative_destination_valid :: proc(path: string) -> bool {
	if len(path) == 0 || len(path) > MAX_PATH_STORAGE_BYTES || !utf8.valid_string(path) ||
	   strings.index_byte(path, 0) >= 0 || os.is_absolute_path(path) {
		return false
	}
	start := 0
	for byte, index in transmute([]u8)path {
		if byte != '/' do continue
		if index == start || path[start:index] == "." || path[start:index] == ".." do return false
		start = index + 1
	}
	return start < len(path) && path[start:] != "." && path[start:] != ".."
}
