// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language_service

import "base:runtime"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:sys/linux"

@(private)
discover_executable_controlled :: proc(
	executable: string,
	discovery: Executable_Discovery,
	maximum_bytes: u64,
	allocator: runtime.Allocator,
) -> (string, Executable_Source, bool) {
	if len(discovery.explicit_path) > 0 {
		resolved, found := executable_path_confirm(discovery.explicit_path, maximum_bytes, allocator)
		return resolved, .Explicit, found
	}
	if strings.index_byte(executable, '/') >= 0 {
		resolved, found := executable_path_confirm(executable, maximum_bytes, allocator)
		return resolved, .Explicit, found
	}
	if len(discovery.package_artifact) > 0 {
		resolved, found := executable_path_confirm(discovery.package_artifact, maximum_bytes, allocator)
		if found do return resolved, .Package_Artifact, true
	}
	if len(discovery.distributed_artifact) > 0 {
		resolved, found := executable_path_confirm(discovery.distributed_artifact, maximum_bytes, allocator)
		if found do return resolved, .Distributed_Artifact, true
	}
	path := discovery.search_path
	for directory in strings.split_iterator(&path, ":") {
		if len(directory) == 0 do continue
		candidate, join_error := filepath.join([]string{directory, executable}, context.temp_allocator)
		if join_error != nil do continue
		if resolved, found := executable_path_confirm(candidate, maximum_bytes, allocator); found {
			delete(candidate, context.temp_allocator)
			return resolved, .Search_Path, true
		}
		delete(candidate, context.temp_allocator)
	}
	return "", .Invalid, false
}

/* executable_reference_valid admits a lookup name or one absolute explicit path. */
executable_reference_valid :: proc(executable: string) -> bool {
	if strings.index_byte(executable, '\\') >= 0 do return false
	if strings.index_byte(executable, '/') < 0 do return executable != "." && executable != ".."
	return filepath.is_abs(executable)
}

/* environment_redacted_copy exposes an environment key without its value. */
environment_redacted_copy :: proc(entry: string, destination: []u8) -> (string, bool) {
	separator := strings.index_byte(entry, '=')
	suffix := "=<redacted>"
	if separator <= 0 || separator + len(suffix) > len(destination) do return "", false
	copy(destination[:separator], transmute([]u8)entry[:separator])
	copy(destination[separator:separator + len(suffix)], transmute([]u8)suffix)
	return string(destination[:separator + len(suffix)]), true
}

@(private = "file")
executable_path_confirm :: proc(
	path: string,
	maximum_bytes: u64,
	allocator: runtime.Allocator,
) -> (string, bool) {
	if len(path) == 0 || u64(len(path)) > maximum_bytes || !os.is_file(path) do return "", false
	cpath, allocation_error := strings.clone_to_cstring(path, context.temp_allocator)
	if allocation_error != nil || linux.access(cpath, linux.X_OK) != .NONE do return "", false
	resolved, path_error := filepath.abs(path, allocator)
	if path_error != nil || u64(len(resolved)) > maximum_bytes {
		if path_error == nil do delete(resolved, allocator)
		return "", false
	}
	return resolved, true
}
