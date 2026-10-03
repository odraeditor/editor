// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package filesystem

import "core:os"

/* directory_child_create revalidates one exact parent and creates one absent child. */
directory_child_create :: proc(
	parent: string,
	request: Creation_Request,
	allocators: Allocator_Set,
) -> (result: Creation_Result, ok: bool, failure: Failure_Context) {
	failure.operation = .Apply_Creation
	if len(parent) == 0 || !resource_id_valid(request.parent_identity) ||
	   request.kind == .Invalid || allocators.temporary.procedure == nil {
		failure.code = .Invalid_Arguments
		return {}, false, failure
	}
	if !rename_name_valid(request.name) {
		failure.code = .Invalid_Name
		return {}, false, failure
	}
	observed, observed_ok, observed_failure := directory_observe(
		parent,
		1,
		{persistent = allocators.temporary, temporary = allocators.temporary},
		true,
	)
	if !observed_ok {
		observed_failure.operation = .Apply_Creation
		return {}, false, observed_failure
	}
	defer directory_batch_close(&observed)
	if observed.directory_identity != request.parent_identity {
		failure.code = .Directory_Changed
		return {}, false, failure
	}
	for entry in observed.descriptors {
		if entry.name == request.name {
			failure.code = .Destination_Exists
			return {}, false, failure
		}
	}
	path, path_error := os.join_path({parent, request.name}, allocators.temporary)
	if path_error != nil {
		failure.code = .Persistent_Memory_Limit
		return {}, false, failure
	}
	defer delete(path, allocators.temporary)
	if _, exists, _ := local_resource_identity(path); exists {
		failure.code = .Destination_Exists
		return {}, false, failure
	}
	created := false
	if request.kind == .Regular_File {
		file, create_error := os.open(
			path,
			{.Write, .Create, .Excl},
			os.Permissions_Default_File,
		)
		if create_error == nil {
			created = os.close(file) == nil
		}
	} else if request.kind == .Directory {
		created = os.make_directory(path) == nil
	}
	if !created {
		failure.code = .Create_Failed
		return {}, false, failure
	}
	identity, identified, platform_code := local_resource_identity(path)
	if !identified {
		_ = os.remove(path)
		failure.code = .Metadata_Failed
		failure.platform_code = platform_code
		return {}, false, failure
	}
	return Creation_Result{identity = identity, kind = request.kind}, true, {}
}
