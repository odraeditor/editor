// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package filesystem

import "core:os"
import "core:testing"

/* Ensures relative moves retain identity and fail cleanly on collisions. */
@(test)
checked_relative_moves_preserve_identity :: proc(t: ^testing.T) {
	root, root_error := os.make_directory_temp("", "odra-filesystem-move-*", context.allocator)
	testing.expect(t, root_error == nil)
	if root_error != nil do return
	defer { os.remove_all(root); delete(root) }
	archive, _ := os.join_path({root, "archive"}, context.allocator)
	source, _ := os.join_path({root, "source"}, context.allocator)
	destination, _ := os.join_path({archive, "moved"}, context.allocator)
	defer { delete(destination); delete(source); delete(archive) }
	testing.expect(t, os.make_directory(archive) == nil)
	testing.expect(t, os.write_entire_file(source, "payload") == nil)
	batch, observed, _ := directory_observe(root, 1, {persistent = context.allocator, temporary = context.temp_allocator})
	testing.expect(t, observed)
	if !observed do return
	defer directory_batch_close(&batch)
	source_entry: Entry_Descriptor
	for entry in batch.descriptors do if entry.name == "source" do source_entry = entry
	request := [?]Move_Request{{identity = source_entry.identity, from = "source", to = "archive/moved"}}
	results: [1]Rename_Result
	moved, failure := directory_move_batch_apply(
		root, batch.directory_identity, request[:], results[:],
		{persistent = context.allocator, temporary = context.temp_allocator},
	)
	testing.expectf(t, moved, "move failed: %v", failure.code)
	testing.expect(t, !os.exists(source) && os.exists(destination))
	identity, identified, _ := local_resource_identity(destination)
	testing.expect(t, identified && identity == source_entry.identity)
}
