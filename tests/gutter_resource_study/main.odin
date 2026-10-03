// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../../src/gutter"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:time"

SAMPLES :: 512
LARGE_BUFFER_LINES :: u64(1_000_000)
AVERAGE_GATE_NS :: i64(2_000_000)
MAXIMUM_GATE_NS :: i64(50_000_000)

main :: proc() {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	registry: gutter.Programmable_Registry
	ready, _ := gutter.programmable_registry_init(&registry, allocator)
	if !ready {
		fmt.eprintln("study=gutter phase=registry-init valid=false")
		os.exit(1)
	}

	identities: [gutter.MAX_PROGRAMMABLE_MARKERS_PER_PROVIDER][24]u8
	markers: [gutter.MAX_PROGRAMMABLE_MARKERS_PER_PROVIDER]gutter.Programmable_Marker_Proposal
	for &marker, index in markers {
		marker = {
			identity = fmt.bprintf(identities[index][:], "marker-%03d", index),
			logical_line = u64(index),
			style_role = .Diagnostic_Information,
			priority = 100,
			representation = {.Glyph, "◆", "*"},
			detail = "Bounded programmable marker used by the Gutter resource study.",
		}
	}
	lane := gutter.Programmable_Lane_Proposal {
		identity = "resource-study",
		side = .Right,
		order = 20,
		attachments = {.Logical_Line},
		width_policy = .Content_Presence,
		minimum_cells = 2,
		maximum_cells = 2,
		alignment = .Center,
		visibility = .When_Content,
		collision = .Highest_Priority,
		priority = 100,
		style_role = .Diagnostic_Information,
		separator = {.Glyph, "│", "|"},
	}
	candidate, prepared, prepare_failure := gutter.programmable_registry_prepare(
		&registry,
		1,
		gutter.Programmable_Provider_Proposal {
			definition_generation = 1,
			marker_generation = 1,
			name = "Gutter resource study",
			package_name = "gutter-resource-study",
			complete = true,
			lanes = []gutter.Programmable_Lane_Proposal{lane},
			markers = markers[:],
		},
	)
	if !prepared {
		fmt.eprintf("study=gutter phase=prepare valid=false failure=%v\n", prepare_failure.code)
		os.exit(1)
	}
	gutter.programmable_provider_candidate_confirm(&candidate)
	activated, activate_failure := gutter.programmable_registry_activate(&registry, &candidate)
	if !activated {
		fmt.eprintf("study=gutter phase=activate valid=false failure=%v\n", activate_failure.code)
		os.exit(1)
	}

	rows: [gutter.MAX_VISIBLE_ROWS]gutter.Visible_Row
	for &row, index in rows {
		row = {viewport_row = u32(index), logical_line = u64(index), has_content = true}
	}
	maximum_ns: i64
	start := time.tick_now()
	for sample in 0 ..< SAMPLES {
		base := u64(sample % 177)
		for &row, index in rows do row.logical_line = base + u64(index)
		provider, viewed, view_failure := gutter.programmable_registry_turn_begin(&registry)
		if !viewed {
			fmt.eprintf("study=gutter phase=view valid=false failure=%v\n", view_failure.code)
			os.exit(1)
		}
		sample_start := time.tick_now()
		resolved, composed, compose_failure := gutter.compose_markers(gutter.Marker_Composition_Request {
			generation = gutter.Generation(sample + 1),
			lanes = provider.lanes,
			publications = []gutter.Marker_Generation_View{provider.publication},
			rows = rows[:],
			buffer_revision = u64(sample + 1),
			allocator = allocator,
			limits = gutter.DEFAULT_LIMITS,
		})
		if !composed {
			fmt.eprintf("study=gutter phase=compose valid=false failure=%v\n", compose_failure.code)
			os.exit(1)
		}
		factory, factory_ok, factory_failure := gutter.compose_factory(gutter.Factory_Request {
			generation = gutter.Generation(sample + 1),
			available_cells = 158,
			minimum_text_cells = gutter.MIN_TEXT_CELLS,
			line_count = LARGE_BUFFER_LINES,
			viewport_rows = gutter.MAX_VISIBLE_ROWS,
			rows = rows[:],
			policy = gutter.DEFAULT_FACTORY_POLICY,
			allocator = allocator,
			limits = gutter.DEFAULT_LIMITS,
		})
		if !factory_ok {
			fmt.eprintf("study=gutter phase=factory valid=false failure=%v\n", factory_failure.code)
			os.exit(1)
		}
		added, add_failure := gutter.view_add_marker_lane(
			&factory, provider.lanes[0], &resolved, rows[:], false,
		)
		if !added {
			fmt.eprintf("study=gutter phase=project valid=false failure=%v\n", add_failure.code)
			os.exit(1)
		}
		gutter.view_close(&factory)
		gutter.resolved_marker_view_close(&resolved)
		gutter.programmable_registry_turn_end(&registry)
		maximum_ns = max(maximum_ns, time.duration_nanoseconds(time.tick_since(sample_start)))
	}
	total_ns := time.duration_nanoseconds(time.tick_since(start))
	average_ns := total_ns / SAMPLES
	peak_bytes := tracking.peak_memory_allocated
	closed, _ := gutter.programmable_registry_close(&registry)
	cleanup_bytes := tracking.current_memory_allocated
	mem.tracking_allocator_destroy(&tracking)
	valid := closed && cleanup_bytes == 0 && average_ns <= AVERAGE_GATE_NS &&
		maximum_ns <= MAXIMUM_GATE_NS
	fmt.printf(
		"study=gutter valid=%v providers=%d lanes=%d markers=%d actions_per_marker=%d text_bytes=%d large_buffer_lines=%d visible_rows=%d samples=%d average_ns=%d average_gate_ns=%d maximum_ns=%d maximum_gate_ns=%d peak_bytes=%d cleanup_bytes=%d no_racket_callbacks=true\n",
		valid,
		gutter.MAX_PROGRAMMABLE_PROVIDERS,
		gutter.MAX_PROGRAMMABLE_LANES_PER_PROVIDER,
		gutter.MAX_PROGRAMMABLE_MARKERS_PER_PROVIDER,
		gutter.MAX_ACTIONS_PER_MARKER,
		gutter.MAX_PROGRAMMABLE_TEXT_BYTES,
		LARGE_BUFFER_LINES,
		gutter.MAX_VISIBLE_ROWS,
		SAMPLES,
		average_ns,
		AVERAGE_GATE_NS,
		maximum_ns,
		MAXIMUM_GATE_NS,
		peak_bytes,
		cleanup_bytes,
	)
	if !valid do os.exit(1)
}
