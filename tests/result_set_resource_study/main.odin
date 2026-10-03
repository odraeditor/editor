// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../../src/editor"
import "../../src/result_set"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:time"

STUDY_LOCATIONS :: 65_536
PUBLICATION_GATE_NS :: i64(2_000_000_000)
PERSISTENT_GATE_BYTES :: i64(64 * 1_024 * 1_024)

main :: proc() {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	locations, location_error := make([]result_set.Location_Definition, STUDY_LOCATIONS, allocator)
	if location_error != nil {
		fmt.eprintln("study=result-set valid=false phase=fixture")
		os.exit(1)
	}
	for &location, index in locations {
		location = {
			id = result_set.Location_ID(index + 1),
			buffer_id = editor.Buffer_ID(1),
			revision = editor.Revision(1),
			start = editor.Byte_Offset(index * 2),
			end = editor.Byte_Offset(index * 2 + 1),
			preview = "x",
		}
	}
	registry: result_set.Registry
	ready, _ := result_set.registry_init(&registry,
		result_set.Config{limits = result_set.DEFAULT_LIMITS, allocator = allocator})
	started := time.tick_now()
	publication, published, failure := result_set.registry_publish(&registry, result_set.Publication{
		set_id = 1,
		source = {id = 1, generation = 1, kind = .Test},
		completeness = .Complete,
		edit_capability = .Read_Only,
		locations = locations,
	})
	elapsed_ns := time.duration_nanoseconds(time.tick_since(started))
	usage, inspected, _ := result_set.registry_inspect(&registry)
	valid := ready && published && failure.code == .None && inspected &&
		publication.generation == 1 && usage.locations == STUDY_LOCATIONS &&
		elapsed_ns <= PUBLICATION_GATE_NS && tracking.peak_memory_allocated <= PERSISTENT_GATE_BYTES
	if ready do _, _ = result_set.registry_close(&registry)
	delete(locations, allocator)
	cleanup_bytes := tracking.current_memory_allocated
	valid = valid && cleanup_bytes == 0
	fmt.printf(
		"study=result-set valid=%v locations=%d elapsed_ns=%d gate_ns=%d retained_bytes=%d peak_bytes=%d peak_gate=%d cleanup_bytes=%d\n",
		valid,
		usage.locations,
		elapsed_ns,
		PUBLICATION_GATE_NS,
		usage.retained_bytes,
		tracking.peak_memory_allocated,
		PERSISTENT_GATE_BYTES,
		cleanup_bytes,
	)
	mem.tracking_allocator_destroy(&tracking)
	if !valid do os.exit(1)
}
