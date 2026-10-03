// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package filesystem

import "core:os"
import "core:testing"

/* Ensures checked deletion handles nested trees and reports irreversible work. */
@(test)
checked_deletion_handles_files :: proc(t: ^testing.T) {
	root, root_error := os.make_directory_temp("", "odra-filesystem-delete-*", context.allocator)
	testing.expect(t, root_error == nil)
	if root_error != nil do return
	defer { os.remove_all(root); delete(root) }
	file, _ := os.join_path({root, "discard"}, context.allocator)
	directory, _ := os.join_path({root, "protected"}, context.allocator)
	defer { delete(directory); delete(file) }
	testing.expect(t, os.write_entire_file(file, "payload") == nil)
	testing.expect(t, os.make_directory(directory) == nil)
	nested, _ := os.join_path({directory, "nested"}, context.allocator)
	defer delete(nested)
	testing.expect(t, os.write_entire_file(nested, "nested") == nil)
	batch, observed, _ := directory_observe(root, 1, {persistent = context.allocator, temporary = context.temp_allocator})
	testing.expect(t, observed)
	if !observed do return
	defer directory_batch_close(&batch)
	file_entry, file_found := directory_entry_find_by_name(&batch, "discard")
	directory_entry, directory_found := directory_entry_find_by_name(&batch, "protected")
	testing.expect(t, file_found && directory_found)
	directory_request := [?]Delete_Request{{identity = directory_entry.identity, name = directory_entry.name, kind = directory_entry.kind}}
	directory_result: [1]Delete_Result
	directory_deleted, directory_failure := directory_delete_batch_apply(
		root, batch.directory_identity, directory_request[:], directory_result[:],
		{persistent = context.allocator, temporary = context.temp_allocator},
	)
	testing.expectf(t, directory_deleted, "directory delete failed: %v", directory_failure.code)
	testing.expect(t, !os.exists(directory))
	testing.expect_value(t, directory_result[0].outcome, Rename_Outcome.Applied)
	testing.expect(t, !directory_result[0].recovery_available)
	file_request := [?]Delete_Request{{identity = file_entry.identity, name = file_entry.name, kind = file_entry.kind}}
	file_result: [1]Delete_Result
	file_deleted, file_failure := directory_delete_batch_apply(
		root, batch.directory_identity, file_request[:], file_result[:],
		{persistent = context.allocator, temporary = context.temp_allocator},
	)
	testing.expectf(t, file_deleted, "delete failed: %v", file_failure.code)
	testing.expect(t, !os.exists(file))
	testing.expect_value(t, file_result[0].outcome, Rename_Outcome.Applied)
	testing.expect(t, !file_result[0].recovery_available)
}

@(private)
directory_entry_find_by_name :: proc(batch: ^Directory_Batch, name: string) -> (Entry_Descriptor, bool) {
	for entry in batch.descriptors do if entry.name == name do return entry, true
	return {}, false
}
