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

/* Ensures edited listings derive swaps while rejecting malformed names. */
@(test)
calculates_swaps_and_rejects_invalid_text :: proc(t: ^testing.T) {
	root, root_error := os.make_directory_temp("", "odra-maksym-editable-*", context.allocator)
	testing.expect(t, root_error == nil)
	if root_error != nil do return
	defer { os.remove_all(root); delete(root) }
	names := [?]string{"alpha", "beta"}
	for name in names {
		path, path_error := os.join_path({root, name}, context.allocator)
		testing.expect(t, path_error == nil)
		if path_error == nil { testing.expect(t, os.write_entire_file(path, name) == nil); delete(path) }
	}
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	allocator := mem.tracking_allocator(&tracking)
	baseline := tracking.current_memory_allocated
	batch, observed, _ := filesystem.directory_observe(root, 1, {persistent = allocator, temporary = context.temp_allocator})
	testing.expect(t, observed)
	if !observed do return
	buffer: Directory_Buffer
	opened, _ := directory_buffer_open(&buffer, &batch, allocator)
	testing.expect(t, opened)
	view, viewed, _ := directory_buffer_view(&buffer)
	_, toggled, _ := directory_buffer_toggle_details(&buffer)
	testing.expect(t, toggled)
	view, viewed, _ = directory_buffer_view(&buffer)
	projection: Projection
	built, _ := projection_build(&projection, view, default_projection_config(allocator))
	projected, projection_ok, _ := projection_view(&projection)
	testing.expect(t, viewed && built && projection_ok)
	listing: Editable_Listing
	listing_ok, _ := editable_listing_open(&listing, projected, allocator)
	testing.expect(t, listing_ok)
	header := projected.text[:projected.header_end]
	swapped, swapped_error := strings.concatenate({header, "beta\nalpha\n"}, allocator)
	testing.expect(t, swapped_error == nil)
	if swapped_error != nil do return
	plan: Rename_Plan
	calculated, failure := editable_listing_calculate(&listing, swapped, &plan)
	delete(swapped, allocator)
	testing.expectf(t, calculated, "calculation failed: %v", failure.code)
	plan_view, plan_ok, _ := rename_plan_view(&plan)
	testing.expect(t, plan_ok)
	if plan_ok {
		testing.expect_value(t, len(plan_view.changes), 2)
		testing.expect_value(t, plan_view.changes[0].kind, Change_Kind.Rename)
		testing.expect_value(t, plan_view.changes[0].from, "alpha")
		testing.expect_value(t, plan_view.changes[0].to, "beta")
	}
	_, _ = rename_plan_close(&plan)
	mixed_text, mixed_text_error := strings.concatenate({header, "archive/alpha\n\n"}, allocator)
	testing.expect(t, mixed_text_error == nil)
	if mixed_text_error != nil do return
	mixed: Rename_Plan
	mixed_ok, mixed_failure := editable_listing_calculate(&listing, mixed_text, &mixed)
	delete(mixed_text, allocator)
	testing.expectf(t, mixed_ok, "mixed calculation failed: %v", mixed_failure.code)
	mixed_view, mixed_viewed, _ := rename_plan_view(&mixed)
	testing.expect(t, mixed_viewed)
	if mixed_viewed {
		testing.expect_value(t, mixed_view.changes[0].kind, Change_Kind.Move)
		testing.expect_value(t, mixed_view.changes[1].kind, Change_Kind.Delete)
		testing.expect(t, mixed_view.changes[1].destructive)
	}
	_, _ = rename_plan_close(&mixed)
	invalid_text, invalid_text_error := strings.concatenate({header, "../bad\nbeta\n"}, allocator)
	testing.expect(t, invalid_text_error == nil)
	if invalid_text_error != nil do return
	invalid: Rename_Plan
	invalid_ok, invalid_failure := editable_listing_calculate(&listing, invalid_text, &invalid)
	delete(invalid_text, allocator)
	testing.expect(t, !invalid_ok)
	testing.expect_value(t, invalid_failure.code, Failure_Code.Invalid_Name)
	_, _ = editable_listing_close(&listing)
	_, _ = projection_close(&projection)
	_, _ = directory_buffer_close(&buffer)
	testing.expect_value(t, tracking.current_memory_allocated, baseline)
}

/* Ensures editable names cannot corrupt protected metadata columns. */
@(test)
preserves_and_protects_detailed_metadata :: proc(t: ^testing.T) {
	root, root_error := os.make_directory_temp("", "odra-maksym-editable-details-*", context.allocator)
	testing.expect(t, root_error == nil)
	if root_error != nil do return
	defer { os.remove_all(root); delete(root) }
	path, path_error := os.join_path({root, "alpha"}, context.allocator)
	testing.expect(t, path_error == nil)
	if path_error != nil do return
	defer delete(path)
	testing.expect(t, os.write_entire_file(path, "alpha") == nil)
	batch, observed, _ := filesystem.directory_observe(
		root,
		1,
		{persistent = context.allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, observed)
	if !observed do return
	buffer: Directory_Buffer
	opened, _ := directory_buffer_open(&buffer, &batch)
	testing.expect(t, opened)
	if !opened do return
	defer { _, _ = directory_buffer_close(&buffer) }
	view, viewed, _ := directory_buffer_view(&buffer)
	testing.expect(t, viewed && view.details == .Full)
	if !viewed do return
	projection: Projection
	built, _ := projection_build(&projection, view, default_projection_config())
	testing.expect(t, built)
	if !built do return
	defer { _, _ = projection_close(&projection) }
	projected, projected_ok, _ := projection_view(&projection)
	testing.expect(t, projected_ok && len(projected.rows) == 1)
	if !projected_ok || len(projected.rows) != 1 do return
	listing: Editable_Listing
	listing_opened, _ := editable_listing_open(&listing, projected)
	testing.expect(t, listing_opened)
	if !listing_opened do return
	defer { _, _ = editable_listing_close(&listing) }
	listing_view, listing_viewed, _ := editable_listing_view(&listing)
	testing.expect(t, listing_viewed)
	if !listing_viewed do return
	testing.expect(t, listing_view.names[0].prefix_bytes > 0)
	row := projected.rows[0]
	replacement := "renamed"
	edited_storage, edited_error := make(
		[]u8,
		len(projected.text) - int(row.name_end - row.name_start) + len(replacement),
		context.allocator,
	)
	testing.expect(t, edited_error == nil)
	if edited_error != nil do return
	defer delete(edited_storage)
	offset := copy(edited_storage, transmute([]u8)projected.text[:row.name_start])
	offset += copy(edited_storage[offset:], replacement)
	offset += copy(edited_storage[offset:], transmute([]u8)projected.text[row.name_end:])
	plan: Rename_Plan
	calculated, calculation_failure := editable_listing_calculate(
		&listing,
		string(edited_storage[:offset]),
		&plan,
	)
	testing.expectf(t, calculated, "detailed calculation failed: %v", calculation_failure.code)
	if calculated {
		plan_view, plan_viewed, _ := rename_plan_view(&plan)
		testing.expect(t, plan_viewed && len(plan_view.changes) == 1)
		if plan_viewed && len(plan_view.changes) == 1 {
			testing.expect_value(t, plan_view.changes[0].to, replacement)
		}
		_, _ = rename_plan_close(&plan)
	}
	corrupted, corrupted_error := strings.clone(projected.text, context.allocator)
	testing.expect(t, corrupted_error == nil)
	if corrupted_error == nil {
		defer delete(corrupted)
		corrupted_bytes := transmute([]u8)corrupted
		corrupted_bytes[0] = 'x'
		invalid: Rename_Plan
		valid, failure := editable_listing_calculate(&listing, corrupted, &invalid)
		testing.expect(t, !valid)
		testing.expect_value(t, failure.code, Failure_Code.Invalid_Editable_Projection)
	}
}
