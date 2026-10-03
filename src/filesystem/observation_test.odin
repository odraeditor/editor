// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package filesystem

import "core:mem"
import "core:os"
import "core:testing"

/* Verifies local observations are complete, stable, typed, sorted, and owned. */
@(test)
directory_observation_copies_resource_evidence :: proc(t: ^testing.T) {
	root, root_error := os.make_directory_temp("", "odra-filesystem-observation-*", context.allocator)
	testing.expect(t, root_error == nil)
	if root_error != nil do return
	defer {
		os.remove_all(root)
		delete(root)
	}
	directory, directory_error := os.join_path({root, "alpha"}, context.allocator)
	file, file_error := os.join_path({root, "zeta.odin"}, context.allocator)
	hidden_directory, hidden_directory_error := os.join_path({root, ".odra"}, context.allocator)
	hidden_file, hidden_file_error := os.join_path({root, ".notes"}, context.allocator)
	hidden_child, hidden_child_error := os.join_path(
		{hidden_directory, "project.rkt"},
		context.allocator,
	)
	testing.expect(t, directory_error == nil && file_error == nil &&
		hidden_directory_error == nil && hidden_file_error == nil && hidden_child_error == nil)
	if directory_error != nil || file_error != nil || hidden_directory_error != nil ||
	   hidden_file_error != nil || hidden_child_error != nil {
		return
	}
	defer {
		delete(hidden_child)
		delete(hidden_file)
		delete(hidden_directory)
		delete(file)
		delete(directory)
	}
	testing.expect(t, os.make_directory(directory) == nil)
	testing.expect(t, os.make_directory(hidden_directory) == nil)
	testing.expect(t, os.write_entire_file(file, "package demo") == nil)
	testing.expect(t, os.write_entire_file(hidden_file, "notes") == nil)
	testing.expect(t, os.write_entire_file(hidden_child, "#lang racket/base") == nil)

	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	allocator := mem.tracking_allocator(&tracking)
	baseline := tracking.current_memory_allocated
	batch, observed, failure := directory_observe(
		root,
		7,
		Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
	)
	testing.expectf(t, observed, "directory observation failed: %v", failure.code)
	if !observed do return
	testing.expect_value(t, batch.generation, u64(7))
	testing.expect(t, resource_id_valid(batch.directory_identity))
	testing.expect_value(t, len(batch.descriptors), 2)
	if len(batch.descriptors) == 2 {
		testing.expect_value(t, batch.descriptors[0].kind, Entry_Kind.Directory)
		testing.expect_value(t, batch.descriptors[0].label, "alpha/")
		testing.expect_value(t, batch.descriptors[1].kind, Entry_Kind.Regular_File)
		testing.expect_value(t, batch.descriptors[1].label, "zeta.odin")
		testing.expect(t, resource_id_valid(batch.descriptors[1].identity))
		descriptor, found := directory_entry_find(&batch, batch.descriptors[1].identity)
		testing.expect(t, found)
		if found do testing.expect_value(t, descriptor.path, file)
		file_identity := batch.descriptors[1].identity
		renamed, rename_error := os.join_path({root, "renamed.odin"}, context.allocator)
		testing.expect(t, rename_error == nil)
		if rename_error == nil {
			testing.expect(t, os.rename(file, renamed) == nil)
			refreshed, refreshed_ok, refreshed_failure := directory_observe(
				root,
				8,
				Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
			)
			testing.expectf(t, refreshed_ok, "refresh failed: %v", refreshed_failure.code)
			if refreshed_ok {
				refreshed_file, found_after_rename := directory_entry_find(&refreshed, file_identity)
				testing.expect(t, found_after_rename)
				if found_after_rename do testing.expect_value(t, refreshed_file.name, "renamed.odin")
				_, _ = directory_batch_close(&refreshed)
			}
			testing.expect(t, os.rename(renamed, file) == nil)
			delete(renamed)
		}
	}
	closed, close_failure := directory_batch_close(&batch)
	testing.expectf(t, closed, "directory close failed: %v", close_failure.code)

	hidden_batch, hidden_observed, hidden_failure := directory_observe(
		root,
		9,
		Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
		true,
	)
	testing.expectf(t, hidden_observed, "hidden observation failed: %v", hidden_failure.code)
	if hidden_observed {
		testing.expect_value(t, len(hidden_batch.descriptors), 4)
		seen_hidden_directory, seen_hidden_file := false, false
		for descriptor in hidden_batch.descriptors {
			if descriptor.name == ".odra" do seen_hidden_directory = true
			if descriptor.name == ".notes" do seen_hidden_file = true
		}
		testing.expect(t, seen_hidden_directory && seen_hidden_file)
		_, _ = directory_batch_close(&hidden_batch)
	}

	hidden_child_batch, hidden_child_observed, hidden_child_failure := directory_observe(
		hidden_directory,
		10,
		Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
	)
	testing.expectf(t, hidden_child_observed, "hidden root failed: %v", hidden_child_failure.code)
	if hidden_child_observed {
		testing.expect_value(t, len(hidden_child_batch.descriptors), 1)
		if len(hidden_child_batch.descriptors) == 1 {
			testing.expect_value(t, hidden_child_batch.descriptors[0].path, hidden_child)
		}
		_, _ = directory_batch_close(&hidden_child_batch)
	}
	testing.expect_value(t, tracking.current_memory_allocated, baseline)
}

/* Verifies unavailable paths fail without publishing partial observations. */
@(test)
directory_observation_rejects_unavailable_paths :: proc(t: ^testing.T) {
	batch, observed, failure := directory_observe(
		"/odra/path/that/does/not/exist",
		1,
		Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, !observed)
	testing.expect_value(t, failure.operation, Operation.Observe_Directory)
	testing.expect(t, failure.code == .Metadata_Failed || failure.code == .Directory_Open_Failed)
	testing.expect(t, batch.state == nil)
}
