// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../../src/display"
import "../../src/status_bar"
import "core:fmt"
import "core:os"
import "core:time"

SAMPLES :: 2_000
LATENCY_GATE_NS :: i64(250_000)

main :: proc() {
	registry: status_bar.Registry
	ready, ready_failure := status_bar.registry_init(&registry, status_bar.Registry_ID(1))
	if !ready {
		fmt.eprintf("status-bar registry initialization failed: %v\n", ready_failure.code)
		os.exit(1)
	}
	defer status_bar.registry_close(&registry)

	identity_storage: [status_bar.MAX_PROGRAMMABLE_SEGMENTS][32]u8
	segments: [status_bar.MAX_PROGRAMMABLE_SEGMENTS]status_bar.Programmable_Segment_Proposal
	for &segment, index in segments {
		identity := fmt.bprintf(identity_storage[index][:], "study-segment-%02d", index)
		segment = {
			identity = identity,
			kind = .Miscellaneous,
			group = .Left if index < 10 else .Right,
			order = u16(index),
			priority = u16(index),
			full_text = "status-study",
			compact_text = "s",
			omittable = true,
			truncatable = true,
			style_role = .Context,
			inspection_text = "bounded programmable Status Bar segment",
		}
	}
	first_count := min(status_bar.MAX_PROGRAMMABLE_SEGMENTS_PER_PROVIDER, len(segments))
	first, first_ok, first_failure := status_bar.registry_register(
		&registry,
		1,
		status_bar.Provider_Proposal {
			provider_name = "Study first",
			package_name = "study-first",
			segments = segments[:first_count],
		},
	)
	if !first_ok || first.provider_id == 0 {
		fmt.eprintf("first Status Bar provider failed: %v\n", first_failure.code)
		os.exit(1)
	}
	inspection, inspected, _ := status_bar.registry_inspect(&registry)
	if !inspected {
		fmt.eprintf("first Status Bar inspection failed\n")
		os.exit(1)
	}
	if first_count < len(segments) {
		_, second_ok, second_failure := status_bar.registry_register(
			&registry,
			inspection.registry_generation,
			status_bar.Provider_Proposal {
				provider_name = "Study second",
				package_name = "study-second",
				segments = segments[first_count:],
			},
		)
		if !second_ok {
			fmt.eprintf("second Status Bar provider failed: %v\n", second_failure.code)
			os.exit(1)
		}
	}

	definitions: [status_bar.MAX_PROGRAMMABLE_SEGMENTS]status_bar.Segment_Definition
	inspection, inspected, _ = status_bar.registry_inspect(&registry)
	if !inspected || inspection.usage.segments != status_bar.MAX_PROGRAMMABLE_SEGMENTS {
		fmt.eprintf(
			"maximum Status Bar inspection failed: inspected=%v segments=%d expected=%d\n",
			inspected,
			inspection.usage.segments,
			status_bar.MAX_PROGRAMMABLE_SEGMENTS,
		)
		os.exit(1)
	}
	for index: u16 = 0; index < inspection.usage.segments; index += 1 {
		view, found, _ := status_bar.registry_segment_at(&registry, index)
		if !found {
			fmt.eprintf("Status Bar segment %d was unavailable\n", index)
			os.exit(1)
		}
		definitions[index] = view.definition
	}
	request := status_bar.Factory_Request {
		generation = 1,
		width_cells = 240,
		buffer = {
			generation = 1,
			identity = 1,
			revision = 1,
			label = "main.odin",
			context_label = "src/odra",
			writable = true,
			point_offset = 512,
			text_bytes = 4_096,
			line = 32,
			line_count = 256,
			column = 17,
		},
		programmable = definitions[:inspection.usage.segments],
		profile = display.unicode17_profile(),
		allocator = context.allocator,
		limits = status_bar.DEFAULT_LIMITS,
	}
	start := time.tick_now()
	maximum_ns: i64
	for sample in 0 ..< SAMPLES {
		sample_start := time.tick_now()
		request.generation = status_bar.Generation(sample + 1)
		request.buffer.generation = request.generation
		view, composed, failure := status_bar.compose_factory(request)
		if !composed {
			fmt.eprintf("Status Bar composition failed: %v/%v segment=%d\n", failure.operation, failure.code, failure.segment)
			os.exit(1)
		}
		status_bar.view_close(&view)
		maximum_ns = max(maximum_ns, time.duration_nanoseconds(time.tick_since(sample_start)))
	}
	total_ns := time.duration_nanoseconds(time.tick_since(start))
	average_ns := total_ns / SAMPLES
	valid := maximum_ns <= LATENCY_GATE_NS
	fmt.printf(
		"study=status-bar samples=%d providers=%d programmable_segments=%d width_cells=%d average_ns=%d maximum_ns=%d gate_ns=%d no_racket_callbacks=true valid=%v\n",
		SAMPLES,
		inspection.usage.providers,
		inspection.usage.segments,
		request.width_cells,
		average_ns,
		maximum_ns,
		LATENCY_GATE_NS,
		valid,
	)
	if !valid do os.exit(1)
}
