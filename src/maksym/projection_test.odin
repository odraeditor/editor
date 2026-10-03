// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package maksym

import "../filesystem"
import "core:mem"
import "core:os"
import "core:strings"
import "core:testing"

/* Verifies projections map visible names and structural suffixes to stable resources. */
@(test)
dir_projection_keeps_editable_name_ranges :: proc(t: ^testing.T) {
	root, root_error := os.make_directory_temp("", "odra-maksym-projection-*", context.allocator)
	testing.expect(t, root_error == nil)
	if root_error != nil do return
	defer {
		os.remove_all(root)
		delete(root)
	}
	directory, directory_error := os.join_path({root, "alpha"}, context.allocator)
	file, file_error := os.join_path({root, "beta.odin"}, context.allocator)
	testing.expect(t, directory_error == nil && file_error == nil)
	if directory_error != nil || file_error != nil do return
	defer {
		delete(file)
		delete(directory)
	}
	testing.expect(t, os.make_directory(directory) == nil)
	testing.expect(t, os.write_entire_file(file, "package beta") == nil)
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	allocator := mem.tracking_allocator(&tracking)
	baseline := tracking.current_memory_allocated
	batch, observed, _ := filesystem.directory_observe(
		root, 1, {persistent = allocator, temporary = context.temp_allocator})
	testing.expect(t, observed)
	if !observed do return
	buffer: Directory_Buffer
	opened, _ := directory_buffer_open(&buffer, &batch, allocator)
	testing.expect(t, opened)
	if !opened do return
	directory_view, viewed, _ := directory_buffer_view(&buffer)
	testing.expect(t, viewed)
	if !viewed do return
	projection: Projection
	built, build_failure := projection_build(
		&projection,
		directory_view,
		Projection_Config{allocator = allocator, text_bytes = MAX_PROJECTION_BYTES},
	)
	testing.expectf(t, built, "projection failed: %v", build_failure.code)
	if !built do return
	projected_view, projected, _ := projection_view(&projection)
	testing.expect(t, projected)
	if projected {
		testing.expect(t, strings.has_prefix(projected_view.text, root))
		testing.expect(t, projected_view.header_end > u64(len(root)))
		testing.expect(t, strings.contains(projected_view.text, "alpha/\n"))
		testing.expect(t, strings.contains(projected_view.text, "beta.odin\n"))
		testing.expect_value(t, len(projected_view.rows), 2)
		testing.expect_value(
			t,
			projected_view.text[projected_view.rows[0].name_start:projected_view.rows[0].name_end],
			"alpha",
		)
		testing.expect_value(
			t,
			projected_view.text[projected_view.rows[1].name_start:projected_view.rows[1].name_end],
			"beta.odin",
		)
		testing.expect(t, projected_view.rows[0].identity == directory_view.entries[0].identity)
	}
	closed, _ := projection_close(&projection)
	testing.expect(t, closed)
	mode, toggled, _ := directory_buffer_toggle_details(&buffer)
	testing.expect(t, toggled)
	testing.expect_value(t, mode, Details_Mode.Simplified)
	simplified_view, simplified_viewed, _ := directory_buffer_view(&buffer)
	testing.expect(t, simplified_viewed)
	if simplified_viewed {
		simplified: Projection
		simplified_built, _ := projection_build(
			&simplified,
			simplified_view,
			Projection_Config{allocator = allocator, text_bytes = MAX_PROJECTION_BYTES},
		)
		testing.expect(t, simplified_built)
		if simplified_built {
			simplified_projection, simplified_projected, _ := projection_view(&simplified)
			testing.expect(t, simplified_projected)
			if simplified_projected {
				testing.expect(t, strings.has_prefix(simplified_projection.text, root))
				testing.expect(t, strings.has_suffix(simplified_projection.text, "alpha/\nbeta.odin\n"))
			}
			_, _ = projection_close(&simplified)
		}
	}
	buffer_closed, _ := directory_buffer_close(&buffer)
	testing.expect(t, buffer_closed)
	testing.expect_value(t, tracking.current_memory_allocated, baseline)
}
