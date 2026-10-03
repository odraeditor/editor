// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package filesystem

import "core:os"
import "core:testing"

@(test)
/* checked_creation_revalidates_parents_and_never_overwrites. */
checked_creation_revalidates_parents :: proc(t: ^testing.T) {
	root, root_error := os.make_directory_temp("", "odra-filesystem-create-*", context.allocator)
	testing.expect(t, root_error == nil)
	if root_error != nil do return
	defer {os.remove_all(root); delete(root)}
	batch, observed, _ := directory_observe(
		root, 1, {persistent = context.allocator, temporary = context.temp_allocator}, true,
	)
	testing.expect(t, observed)
	if !observed do return
	root_identity := batch.directory_identity
	directory_batch_close(&batch)
	allocators := Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator}
	file, file_ok, file_failure := directory_child_create(
		root,
		{parent_identity = root_identity, name = "main.odin", kind = .Regular_File},
		allocators,
	)
	testing.expectf(t, file_ok, "file creation failed with %v", file_failure.code)
	testing.expect(t, resource_id_valid(file.identity))
	directory, directory_ok, directory_failure := directory_child_create(
		root,
		{parent_identity = root_identity, name = "src", kind = .Directory},
		allocators,
	)
	testing.expectf(t, directory_ok, "directory creation failed with %v", directory_failure.code)
	testing.expect(t, resource_id_valid(directory.identity))
	_, collision_ok, collision_failure := directory_child_create(
		root,
		{parent_identity = root_identity, name = "main.odin", kind = .Regular_File},
		allocators,
	)
	testing.expect(t, !collision_ok)
	testing.expect_value(t, collision_failure.code, Failure_Code.Destination_Exists)
	_, invalid_ok, invalid_failure := directory_child_create(
		root,
		{parent_identity = root_identity, name = "../escape", kind = .Regular_File},
		allocators,
	)
	testing.expect(t, !invalid_ok)
	testing.expect_value(t, invalid_failure.code, Failure_Code.Invalid_Name)
	stale := root_identity
	stale.inode += 1
	_, stale_ok, stale_failure := directory_child_create(
		root,
		{parent_identity = stale, name = "stale.txt", kind = .Regular_File},
		allocators,
	)
	testing.expect(t, !stale_ok)
	testing.expect_value(t, stale_failure.code, Failure_Code.Directory_Changed)
}
