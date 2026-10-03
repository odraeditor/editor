// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language_service

import "core:os"
import "core:path/filepath"
import "core:testing"

@(private)
executable_test_file :: proc(directory, name: string) -> (string, bool) {
	path, path_error := filepath.join([]string{directory, name}, context.allocator)
	if path_error != nil do return "", false
	if os.write_entire_file(path, "#!/bin/sh\nexit 0\n") != nil ||
	   os.chmod(path, {.Read_User, .Write_User, .Execute_User}) != nil {
		delete(path)
		return "", false
	}
	return path, true
}

/* Verifies explicit, package, distributed, and PATH candidates use fixed precedence. */
@(test)
executable_resolution_uses_controlled_precedence :: proc(t: ^testing.T) {
	root, root_error := os.make_directory_temp("", "odra-executable-*", context.allocator)
	testing.expect(t, root_error == nil)
	if root_error != nil do return
	defer {os.remove_all(root); delete(root)}
	package_path, package_ok := executable_test_file(root, "package-server")
	distributed_path, distributed_ok := executable_test_file(root, "distributed-server")
	path_path, path_ok := executable_test_file(root, "fixture-server")
	testing.expect(t, package_ok && distributed_ok && path_ok)
	if !package_ok || !distributed_ok || !path_ok do return
	defer {delete(package_path); delete(distributed_path); delete(path_path)}
	resolved, source, found := discover_executable_controlled(
		"fixture-server",
		{
			package_artifact = package_path,
			distributed_artifact = distributed_path,
			search_path = root,
		},
		DEFAULT_LIMITS.executable_bytes,
		context.allocator,
	)
	testing.expect(t, found)
	if found {
		defer delete(resolved)
		testing.expect_value(t, source, Executable_Source.Package_Artifact)
		testing.expect_value(t, resolved, package_path)
	}
	missing_package, missing_error := filepath.join([]string{root, "missing"}, context.allocator)
	testing.expect(t, missing_error == nil)
	if missing_error == nil {
		defer delete(missing_package)
		resolved, source, found = discover_executable_controlled(
			"fixture-server",
			{
				package_artifact = missing_package,
				distributed_artifact = distributed_path,
				search_path = root,
			},
			DEFAULT_LIMITS.executable_bytes,
			context.allocator,
		)
		testing.expect(t, found)
		if found {
			defer delete(resolved)
			testing.expect_value(t, source, Executable_Source.Distributed_Artifact)
			testing.expect_value(t, resolved, distributed_path)
		}
	}
}

/* Verifies each process start can observe changed or unavailable executable state. */
@(test)
provider_registry_revalidates_executable_availability :: proc(t: ^testing.T) {
	root, root_error := os.make_directory_temp("", "odra-revalidate-*", context.allocator)
	testing.expect(t, root_error == nil)
	if root_error != nil do return
	defer {os.remove_all(root); delete(root)}
	first, first_ok := executable_test_file(root, "first")
	second, second_ok := executable_test_file(root, "second")
	testing.expect(t, first_ok && second_ok)
	if !first_ok || !second_ok do return
	defer {delete(first); delete(second)}
	registry: Provider_Registry
	initialized, _ := provider_registry_init(&registry, {id = 71, generation = 73})
	testing.expect(t, initialized)
	if !initialized do return
	defer provider_registry_close(&registry)
	handle, proposed, _ := provider_registry_propose(&registry, fixture_definition())
	testing.expect(t, proposed)
	if !proposed do return
	confirmed, _ := provider_registry_confirm(&registry, handle)
	testing.expect(t, confirmed)
	first_resolution, first_resolved, _ := provider_registry_revalidate_executable(
		&registry,
		handle,
		{explicit_path = first},
	)
	testing.expect(t, first_resolved)
	testing.expect_value(t, first_resolution.availability, Executable_Availability.Available)
	testing.expect_value(t, first_resolution.source, Executable_Source.Explicit)
	second_resolution, second_resolved, _ := provider_registry_revalidate_executable(
		&registry,
		handle,
		{explicit_path = second},
	)
	testing.expect(t, second_resolved)
	testing.expect_value(t, second_resolution.availability, Executable_Availability.Changed)
	os.remove(second)
	unavailable, checked, failure := provider_registry_revalidate_executable(
		&registry,
		handle,
		{explicit_path = second},
	)
	testing.expect(t, checked)
	testing.expect_value(t, unavailable.availability, Executable_Availability.Unavailable)
	testing.expect_value(t, failure.code, Failure_Code.Executable_Not_Found)
	view, viewed, _ := provider_registry_definition(&registry, handle)
	testing.expect(t, viewed)
	if viewed {
		testing.expect_value(t, view.executable_availability, Executable_Availability.Unavailable)
		testing.expect_value(t, view.resolved_executable, "")
	}
}

/* Verifies command references remain direct and environment values stay redacted. */
@(test)
executable_policy_rejects_relative_paths_and_redacts_environment :: proc(t: ^testing.T) {
	testing.expect(t, executable_reference_valid("server"))
	testing.expect(t, executable_reference_valid("/opt/odra/server"))
	testing.expect(t, !executable_reference_valid("bin/server"))
	testing.expect(t, !executable_reference_valid("../server"))
	storage: [64]u8
	redacted, copied := environment_redacted_copy("TOKEN=secret-value", storage[:])
	testing.expect(t, copied)
	testing.expect_value(t, redacted, "TOKEN=<redacted>")
	testing.expect(t, !strings_contains(redacted, "secret-value"))
}

@(private = "file")
strings_contains :: proc(value, candidate: string) -> bool {
	if len(candidate) == 0 || len(candidate) > len(value) do return false
	for index in 0 ..= len(value) - len(candidate) {
		if value[index:index + len(candidate)] == candidate do return true
	}
	return false
}
