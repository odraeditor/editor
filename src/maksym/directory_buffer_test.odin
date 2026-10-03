// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package maksym

import "../filesystem"
import "core:mem"
import "core:os"
import "core:testing"

/* Verifies selection follows stable resource identity across refresh and rename. */
@(test)
directory_buffer_preserves_selection_by_resource :: proc(t: ^testing.T) {
	root, root_error := os.make_directory_temp("", "odra-maksym-buffer-*", context.allocator)
	testing.expect(t, root_error == nil)
	if root_error != nil do return
	defer {
		os.remove_all(root)
		delete(root)
	}
	first, first_error := os.join_path({root, "alpha.odin"}, context.allocator)
	second, second_error := os.join_path({root, "beta.odin"}, context.allocator)
	renamed, renamed_error := os.join_path({root, "gamma.odin"}, context.allocator)
	testing.expect(t, first_error == nil && second_error == nil && renamed_error == nil)
	if first_error != nil || second_error != nil || renamed_error != nil do return
	defer {
		delete(renamed)
		delete(second)
		delete(first)
	}
	testing.expect(t, os.write_entire_file(first, "package alpha") == nil)
	testing.expect(t, os.write_entire_file(second, "package beta") == nil)

	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	allocator := mem.tracking_allocator(&tracking)
	baseline := tracking.current_memory_allocated
	batch, observed, observe_failure := filesystem.directory_observe(
		root,
		1,
		filesystem.Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
	)
	testing.expectf(t, observed, "observation failed: %v", observe_failure.code)
	if !observed do return
	buffer: Directory_Buffer
	opened, open_failure := directory_buffer_open(&buffer, &batch, allocator)
	testing.expectf(t, opened, "open failed: %v", open_failure.code)
	if !opened {
		_, _ = filesystem.directory_batch_close(&batch)
		return
	}
	view, viewed, view_failure := directory_buffer_view(&buffer)
	testing.expectf(t, viewed, "view failed: %v", view_failure.code)
	if viewed {
		testing.expect_value(t, len(view.entries), 2)
		testing.expect_value(t, view.selected_index, 0)
		selected := view.entries[1].identity
		selected_ok, selection_failure := directory_buffer_select(&buffer, selected)
		testing.expectf(t, selected_ok, "selection failed: %v", selection_failure.code)
		testing.expect(t, os.rename(second, renamed) == nil)
		refresh, refreshed, refresh_observe_failure := filesystem.directory_observe(
			root,
			2,
			filesystem.Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
		)
		testing.expectf(t, refreshed, "refresh observation failed: %v", refresh_observe_failure.code)
		if refreshed {
			published, publish_failure := directory_buffer_refresh(&buffer, &refresh)
			testing.expectf(t, published, "refresh failed: %v", publish_failure.code)
			refreshed_view, refreshed_viewed, _ := directory_buffer_view(&buffer)
			testing.expect(t, refreshed_viewed)
			if refreshed_viewed {
				testing.expect_value(t, refreshed_view.selected_identity, selected)
				testing.expect_value(t, refreshed_view.entries[refreshed_view.selected_index].name, "gamma.odin")
			}
		}
	}
	closed, close_failure := directory_buffer_close(&buffer)
	testing.expectf(t, closed, "close failed: %v", close_failure.code)
	testing.expect_value(t, tracking.current_memory_allocated, baseline)
}

/* Verifies movement clamps at boundaries and invalid refreshes preserve state. */
@(test)
rejects_stale_or_foreign_refresh :: proc(t: ^testing.T) {
	root, root_error := os.make_directory_temp("", "odra-maksym-refresh-*", context.allocator)
	other, other_error := os.make_directory_temp("", "odra-maksym-foreign-*", context.allocator)
	testing.expect(t, root_error == nil && other_error == nil)
	if root_error != nil || other_error != nil do return
	defer {
		os.remove_all(other)
		os.remove_all(root)
		delete(other)
		delete(root)
	}
	entry, entry_error := os.join_path({root, "entry"}, context.allocator)
	testing.expect(t, entry_error == nil)
	if entry_error != nil do return
	defer delete(entry)
	testing.expect(t, os.write_entire_file(entry, "entry") == nil)
	batch, observed, _ := filesystem.directory_observe(
		root, 4, {persistent = context.allocator, temporary = context.temp_allocator})
	testing.expect(t, observed)
	if !observed do return
	buffer: Directory_Buffer
	opened, _ := directory_buffer_open(&buffer, &batch)
	testing.expect(t, opened)
	if !opened do return
	defer directory_buffer_close(&buffer)
	before, _, _ := directory_buffer_view(&buffer)
	boundary, moved, _ := directory_buffer_move(&buffer, -1)
	testing.expect(t, moved)
	testing.expect(t, !boundary.changed)
	stale, stale_observed, _ := filesystem.directory_observe(
		root, 4, {persistent = context.allocator, temporary = context.temp_allocator})
	testing.expect(t, stale_observed)
	if stale_observed {
		refreshed, failure := directory_buffer_refresh(&buffer, &stale)
		testing.expect(t, !refreshed)
		testing.expect_value(t, failure.code, Failure_Code.Invalid_Generation)
		_, _ = filesystem.directory_batch_close(&stale)
	}
	foreign_batch, foreign_observed, _ := filesystem.directory_observe(
		other, 5, {persistent = context.allocator, temporary = context.temp_allocator})
	testing.expect(t, foreign_observed)
	if foreign_observed {
		refreshed, failure := directory_buffer_refresh(&buffer, &foreign_batch)
		testing.expect(t, !refreshed)
		testing.expect_value(t, failure.code, Failure_Code.Directory_Changed)
		_, _ = filesystem.directory_batch_close(&foreign_batch)
	}
	after, _, _ := directory_buffer_view(&buffer)
	testing.expect_value(t, after.generation, before.generation)
	testing.expect_value(t, after.selected_identity, before.selected_identity)
}
