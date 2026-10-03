// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package filesystem

import "core:os"
import "core:testing"

/* Ensures moves revalidate both identities before changing the filesystem. */
@(test)
checked_entry_move_revalidates_source :: proc(t: ^testing.T) {
	root, root_error := os.make_directory_temp("", "odra-filesystem-move-entry-*", context.allocator)
	testing.expect(t, root_error == nil)
	if root_error != nil do return
	defer {os.remove_all(root); delete(root)}
	source_parent, _ := os.join_path({root, "source"}, context.allocator)
	destination_parent, _ := os.join_path({root, "destination"}, context.allocator)
	source_path, _ := os.join_path({source_parent, "item"}, context.allocator)
	destination_path, _ := os.join_path({destination_parent, "renamed"}, context.allocator)
	defer {delete(destination_path); delete(source_path); delete(destination_parent); delete(source_parent)}
	testing.expect(t, os.make_directory(source_parent) == nil)
	testing.expect(t, os.make_directory(destination_parent) == nil)
	testing.expect(t, os.write_entire_file(source_path, "item") == nil)
	source_batch, source_ok, _ := directory_observe(
		source_parent, 1, {persistent = context.allocator, temporary = context.temp_allocator}, true,
	)
	destination_batch, destination_ok, _ := directory_observe(
		destination_parent, 1, {persistent = context.allocator, temporary = context.temp_allocator}, true,
	)
	testing.expect(t, source_ok && destination_ok)
	if !source_ok || !destination_ok do return
	defer {directory_batch_close(&destination_batch); directory_batch_close(&source_batch)}
	entry, found := directory_entry_find_by_name(&source_batch, "item")
	testing.expect(t, found)
	if !found do return
	result, moved, failure := directory_entry_move(
		source_parent, destination_parent,
		{
			source_parent_identity = source_batch.directory_identity,
			source_identity = entry.identity,
			source_name = "item",
			source_kind = entry.kind,
			destination_parent_identity = destination_batch.directory_identity,
			destination_name = "renamed",
		},
		{persistent = context.allocator, temporary = context.temp_allocator},
	)
	testing.expectf(t, moved, "move failed: %v", failure.code)
	testing.expect(t, result.changed && result.identity == entry.identity)
	testing.expect(t, !os.exists(source_path) && os.exists(destination_path))
}
