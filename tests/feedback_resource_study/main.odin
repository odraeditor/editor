// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../../src/feedback"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:time"

LATENCY_GATE_NS :: i64(10_000_000)

main :: proc() {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	registry: feedback.Registry
	ready, failure := feedback.registry_init(
		&registry,
		1,
		{persistent = allocator, temporary = allocator},
	)
	if !ready {
		fmt.eprintf("study=feedback phase=initialize valid=false failure=%v\n", failure.code)
		os.exit(1)
	}

	maximum_ns: i64
	total_ns: i64
	samples: i64
	progress := progress_proposal(10_000, 1, 1, .Pending, 0, 1_024)
	if !publish_measured(&registry, progress, &maximum_ns, &total_ns, &samples) do os.exit(1)
	for generation in 2 ..= 1_024 {
		progress = progress_proposal(10_000, feedback.Record_Generation(generation), feedback.Source_Generation(generation), .Running, u64(generation), 1_024)
		progress.replacement = 10_000
		if !publish_measured(&registry, progress, &maximum_ns, &total_ns, &samples) do os.exit(1)
	}
	progress = progress_proposal(10_000, 1_025, 1_025, .Succeeded, 1_024, 1_024)
	progress.replacement = 10_000
	progress.class = .Completion
	if !publish_measured(&registry, progress, &maximum_ns, &total_ns, &samples) do os.exit(1)

	for index in 0 ..< int(feedback.DEFAULT_HISTORY_RECORDS) {
		id := feedback.Record_ID(index + 1)
		pending := progress_proposal(id, 1, 1, .Pending, 0, 1)
		if !publish_measured(&registry, pending, &maximum_ns, &total_ns, &samples) do os.exit(1)
		complete := progress_proposal(id, 2, 2, .Succeeded, 1, 1)
		complete.replacement = id
		complete.class = .Completion
		if !publish_measured(&registry, complete, &maximum_ns, &total_ns, &samples) do os.exit(1)
	}

	for index in 0 ..< int(feedback.DEFAULT_ACTIVE_RECORDS) {
		proposal := notification_proposal(feedback.Record_ID(20_000 + index), feedback.Source_ID(20_000 + index))
		if !publish_measured(&registry, proposal, &maximum_ns, &total_ns, &samples) do os.exit(1)
	}

	stats, inspected, inspect_failure := feedback.registry_stats(&registry)
	if !inspected {
		fmt.eprintf("study=feedback phase=inspect valid=false failure=%v\n", inspect_failure.code)
		os.exit(1)
	}
	average_ns := total_ns / samples
	shape_valid := stats.usage.active_records == feedback.DEFAULT_ACTIVE_RECORDS &&
		stats.usage.history_records == feedback.DEFAULT_HISTORY_RECORDS &&
		stats.usage.history_bytes <= feedback.DEFAULT_HISTORY_BYTES &&
		stats.usage.accepted_updates == u64(samples)
	peak_bytes := tracking.peak_memory_allocated
	closed, close_failure := feedback.registry_close(&registry)
	cleanup_bytes := tracking.current_memory_allocated
	valid := shape_valid && closed && close_failure.code == .None && cleanup_bytes == 0 && maximum_ns <= LATENCY_GATE_NS
	fmt.printf(
		"study=feedback valid=%v active=%d history=%d history_bytes=%d evicted=%d updates=%d average_ns=%d maximum_ns=%d latency_gate_ns=%d peak_bytes=%d cleanup_bytes=%d headless_stride=%d\n",
		valid,
		stats.usage.active_records,
		stats.usage.history_records,
		stats.usage.history_bytes,
		stats.usage.evicted_history,
		stats.usage.accepted_updates,
		average_ns,
		maximum_ns,
		LATENCY_GATE_NS,
		peak_bytes,
		cleanup_bytes,
		stats.policy.headless_progress_stride,
	)
	mem.tracking_allocator_destroy(&tracking)
	if !valid do os.exit(1)
}

publish_measured :: proc(registry: ^feedback.Registry, proposal: feedback.Proposal, maximum_ns, total_ns, samples: ^i64) -> bool {
	start := time.tick_now()
	_, admitted, failure := feedback.registry_publish(registry, proposal)
	elapsed := time.duration_nanoseconds(time.tick_since(start))
	maximum_ns^ = max(maximum_ns^, elapsed)
	total_ns^ += elapsed
	samples^ += 1
	if !admitted {
		fmt.eprintf("study=feedback phase=publish valid=false failure=%v record=%d generation=%d\n", failure.code, proposal.id, proposal.generation)
	}
	return admitted
}

progress_proposal :: proc(id: feedback.Record_ID, generation: feedback.Record_Generation, source_generation: feedback.Source_Generation, state: feedback.Progress_State, current, total: u64) -> feedback.Proposal {
	return {
		id = id,
		generation = generation,
		source = {id = feedback.Source_ID(id), generation = source_generation},
		kind = .Progress,
		class = .Progress,
		severity = .Information,
		attention = .Ordinary,
		lifecycle = .Retained,
		retention = .History,
		visibility = .Public,
		title = "Resource study operation",
		message = "Bounded semantic progress update.",
		progress = {state = state, measurement = .Determinate, current = current, total = total, phase = "work"},
	}
}

notification_proposal :: proc(id: feedback.Record_ID, source: feedback.Source_ID) -> feedback.Proposal {
	return {
		id = id,
		generation = 1,
		source = {id = source, generation = 1},
		kind = .Notification,
		class = .Information,
		severity = .Information,
		attention = .Ordinary,
		lifecycle = .Transient,
		retention = .None,
		visibility = .Public,
		title = "Resource study notification",
		message = "Bounded semantic notification.",
	}
}
