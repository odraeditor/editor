// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../../src/kill_ring"
import "core:fmt"
import "core:os"
import "core:slice"
import "core:time"

SAMPLES :: 1_024
GATE_NS :: i64(2_000_000)

main :: proc() {
	ring: kill_ring.Ring
	initialized, failure := kill_ring.ring_init(
		&ring,
		kill_ring.Ring_ID(1),
		kill_ring.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	if !initialized {
		fmt.eprintf("benchmark=kill-ring phase=init failure=%v\n", failure.code)
		os.exit(1)
	}
	defer kill_ring.ring_close(&ring)
	text := "ordinary 4 KiB transfer payload"
	for _ in 0 ..< int(kill_ring.DEFAULT_RETAINED_ENTRIES) {
		stats, _, _ := kill_ring.ring_stats(&ring)
		reservation: kill_ring.Reservation
		_, reserved, reserve_failure := kill_ring.admission_reserve(
			&ring,
			&reservation,
			kill_ring.Admission_Request {
				expected_generation = stats.generation,
				kind = .Copy,
				text = text,
			},
		)
		if !reserved {
			fmt.eprintf("benchmark=kill-ring phase=admit failure=%v\n", reserve_failure.code)
			os.exit(1)
		}
		kill_ring.reservation_commit_reserved(&reservation)
	}
	stats, _, _ := kill_ring.ring_stats(&ring)
	latencies := make([]i64, SAMPLES)
	defer delete(latencies)
	checksum := u64(0)
	current := stats.newest
	for sample in 0 ..< SAMPLES {
		started := time.tick_now()
		copied, rotated, rotate_failure := kill_ring.rotation_next(
			&ring,
			kill_ring.Rotation_Request {
				expected_generation = stats.generation,
				current_entry = current,
				work_limit = stats.policy.rotation_work,
				byte_limit = stats.policy.entry_bytes,
			},
			context.allocator,
		)
		latencies[sample] = time.duration_nanoseconds(time.tick_since(started))
		if !rotated {
			fmt.eprintf("benchmark=kill-ring phase=rotation failure=%v\n", rotate_failure.code)
			os.exit(1)
		}
		current = copied.metadata.id
		checksum ~= u64(copied.text[0])
		kill_ring.entry_copy_release(&copied, context.allocator)
	}
	slice.sort(latencies)
	p50 := latencies[(SAMPLES * 50 + 99) / 100 - 1]
	p99 := latencies[(SAMPLES * 99 + 99) / 100 - 1]
	fmt.printf(
		"benchmark=kill-ring entries=%d samples=%d rotation_p50_ns=%d rotation_p99_ns=%d gate_ns=%d checksum=%d\n",
		stats.usage.retained_entries,
		SAMPLES,
		p50,
		p99,
		GATE_NS,
		checksum,
	)
	if p99 > GATE_NS {
		os.exit(1)
	}
}
