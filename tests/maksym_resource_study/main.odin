// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../../src/filesystem"
import "../../src/maksym"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:time"

ENTRY_COUNT :: 1_024
REPEATED_PROJECTIONS :: 32
LATENCY_GATE_NS :: i64(2_000_000_000)
MEMORY_GATE_BYTES :: i64(64 * 1_024 * 1_024)

main :: proc() {
	root, root_error := os.make_directory_temp("", "odra-maksym-resource-*", context.allocator)
	if root_error != nil do os.exit(1)
	defer {
		os.remove_all(root)
		delete(root)
	}
	for index in 0 ..< ENTRY_COUNT {
		name := fmt.aprintf("entry-%04d.odin", index)
		if index % 17 == 0 {
			delete(name)
			name = fmt.aprintf("zażółć-%04d-資料.odin", index)
		}
		path, path_error := os.join_path({root, name}, context.allocator)
		delete(name)
		if path_error != nil do os.exit(1)
		write_error := os.write_entire_file(path, "package resource_study\n")
		delete(path)
		if write_error != nil do os.exit(1)
	}
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	started := time.tick_now()
	batch, observed, _ := filesystem.directory_observe(
		root,
		1,
		{persistent = allocator, temporary = context.temp_allocator},
	)
	valid := observed
	buffer: maksym.Directory_Buffer
	if observed {
		opened, _ := maksym.directory_buffer_open(&buffer, &batch, allocator)
		valid = opened && valid
	}
	projection: maksym.Projection
	if buffer.state != nil {
		view, viewed, _ := maksym.directory_buffer_view(&buffer)
		built, _ := maksym.projection_build(
			&projection,
			view,
			maksym.default_projection_config(allocator),
		)
		valid = viewed && built && len(view.entries) == ENTRY_COUNT && valid
	}
	if projection.state != nil do _, _ = maksym.projection_close(&projection)
	for _ in 0 ..< REPEATED_PROJECTIONS {
		if buffer.state == nil do break
		_, toggled, _ := maksym.directory_buffer_toggle_details(&buffer)
		_, sorted, _ := maksym.directory_buffer_cycle_sort(&buffer)
		view, viewed, _ := maksym.directory_buffer_view(&buffer)
		built, _ := maksym.projection_build(
			&projection,
			view,
			maksym.default_projection_config(allocator),
		)
		valid = toggled && sorted && viewed && built && valid
		if projection.state != nil do _, _ = maksym.projection_close(&projection)
	}
	if buffer.state != nil {
		view, viewed, _ := maksym.directory_buffer_view(&buffer)
		if viewed && view.details == .Full do _, _, _ = maksym.directory_buffer_toggle_details(&buffer)
		view, viewed, _ = maksym.directory_buffer_view(&buffer)
		built, _ := maksym.projection_build(
			&projection,
			view,
			maksym.default_projection_config(allocator),
		)
		valid = viewed && built && valid
		if built {
			projected, projected_ok, _ := maksym.projection_view(&projection)
			listing: maksym.Editable_Listing
			listing_open, _ := maksym.editable_listing_open(&listing, projected, allocator)
			plan: maksym.Rename_Plan
			calculated := false
			if listing_open do calculated, _ = maksym.editable_listing_calculate(&listing, projected.text, &plan)
			valid = projected_ok && listing_open && calculated && valid
			if plan.state != nil do _, _ = maksym.rename_plan_close(&plan)
			if listing.state != nil do _, _ = maksym.editable_listing_close(&listing)
		}
	}
	latency_ns := time.duration_nanoseconds(time.tick_since(started))
	peak_bytes := tracking.peak_memory_allocated
	valid = latency_ns <= LATENCY_GATE_NS && peak_bytes <= MEMORY_GATE_BYTES && valid
	if projection.state != nil do _, _ = maksym.projection_close(&projection)
	if buffer.state != nil do _, _ = maksym.directory_buffer_close(&buffer)
	if batch.state != nil do _, _ = filesystem.directory_batch_close(&batch)
	cleanup_bytes := tracking.current_memory_allocated
	valid = cleanup_bytes == 0 && valid
	mem.tracking_allocator_destroy(&tracking)
	fmt.printf(
		"study=maksym-editable-core valid=%v entries=%d repeated_projections=%d latency_ns=%d latency_gate_ns=%d peak_bytes=%d memory_gate_bytes=%d cleanup_bytes=%d\n",
		valid,
		ENTRY_COUNT,
		REPEATED_PROJECTIONS,
		latency_ns,
		LATENCY_GATE_NS,
		peak_bytes,
		MEMORY_GATE_BYTES,
		cleanup_bytes,
	)
	if !valid do os.exit(1)
}
