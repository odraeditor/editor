// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package filesystem

import "core:os"
import "core:testing"

@(test)
/* checked_copy_preserves_trees_rejects_overwrite_and_cleans_bounded_partial_work. */
checked_copy_preserves_trees_rejects_overwrite :: proc(t: ^testing.T) {
	root, root_error := os.make_directory_temp("", "odra-filesystem-copy-*", context.allocator)
	testing.expect(t, root_error == nil)
	if root_error != nil do return
	defer {os.remove_all(root); delete(root)}
	source, _ := os.join_path({root, "source"}, context.allocator)
	destination, _ := os.join_path({root, "destination"}, context.allocator)
	nested, _ := os.join_path({source, "nested"}, context.allocator)
	file, _ := os.join_path({nested, "data.txt"}, context.allocator)
	defer {delete(file); delete(nested); delete(destination); delete(source)}
	testing.expect(t, os.make_directory(source) == nil)
	testing.expect(t, os.make_directory(destination) == nil)
	testing.expect(t, os.make_directory(nested) == nil)
	testing.expect(t, os.write_entire_file(file, "copy payload") == nil)
	root_batch, root_ok, _ := directory_observe(
		root, 1, {persistent = context.allocator, temporary = context.temp_allocator}, true,
	)
	testing.expect(t, root_ok)
	if !root_ok do return
	source_entry, source_found := directory_entry_find_by_name(&root_batch, "source")
	destination_entry, destination_found := directory_entry_find_by_name(&root_batch, "destination")
	testing.expect(t, source_found && destination_found)
	if !source_found || !destination_found { directory_batch_close(&root_batch); return }
	root_identity := root_batch.directory_identity
	directory_batch_close(&root_batch)
	request := Copy_Request {
		source_parent_identity = root_identity,
		source_identity = source_entry.identity,
		source_name = "source",
		source_kind = source_entry.kind,
		destination_parent_identity = destination_entry.identity,
		destination_name = "copy",
		limits = DEFAULT_COPY_LIMITS,
	}
	result, copied, copy_failure := directory_entry_copy(
		root, destination, request,
		{persistent = context.allocator, temporary = context.temp_allocator},
	)
	testing.expectf(t, copied, "copy failed with %v", copy_failure.code)
	testing.expect_value(t, result.outcome, Copy_Outcome.Applied)
	testing.expect_value(t, result.entries, u32(3))
	testing.expect_value(t, result.bytes, u64(len("copy payload")))
	testing.expect_value(t, result.durability, Copy_Durability.Best_Effort_Directory_Metadata)
	_, collision_ok, collision_failure := directory_entry_copy(
		root, destination, request,
		{persistent = context.allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, !collision_ok)
	testing.expect_value(t, collision_failure.code, Failure_Code.Destination_Exists)
	request.destination_name = "bounded"
	request.limits.bytes = 4
	partial, bounded_ok, bounded_failure := directory_entry_copy(
		root, destination, request,
		{persistent = context.allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, !bounded_ok)
	testing.expect_value(t, bounded_failure.code, Failure_Code.Copy_Byte_Limit)
	testing.expect_value(t, partial.outcome, Copy_Outcome.Cleaned_Partial)
	bounded_path, _ := os.join_path({destination, "bounded"}, context.allocator)
	defer delete(bounded_path)
	_, bounded_exists, _ := local_resource_identity(bounded_path)
	testing.expect(t, !bounded_exists)
}
