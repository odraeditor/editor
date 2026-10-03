// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import candidate_reference "../candidate_reference"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:slice"
import "core:time"

SELECTED_CANDIDATES :: 4_096
SELECTED_SNAPSHOT_TEXT_BYTES :: 32 * 1_024 * 1_024
SELECTED_QUERY_BYTES :: 4 * 1_024
SELECTED_QUERY_COMPONENTS :: 8
SELECTED_VISIBLE_ROWS :: 4_096
SELECTED_PATTERN_BYTES :: 4 * 1_024
SELECTED_TEMPORARY_BYTES :: 16 * 1_024 * 1_024
SELECTED_REFRESHES_PER_TURN :: 1
ORDINARY_GATE_NS :: i64(5_000_000)
DEMANDING_GATE_NS :: i64(100_000_000)

Profile :: struct {
	name:       string,
	candidates: int,
	query:      string,
	samples:    int,
	gate_ns:    i64,
}

main :: proc() {
	passed := print_policy()
	profiles := [?]Profile {
		{
			name = "ordinary",
			candidates = 256,
			query = "module alpha",
			samples = 512,
			gate_ns = ORDINARY_GATE_NS,
		},
		{
			name = "demanding",
			candidates = 4_096,
			query = "alpha beta gamma delta epsilon zeta eta theta",
			samples = 64,
			gate_ns = DEMANDING_GATE_NS,
		},
	}
	for profile in profiles {
		passed = run_profile(profile) && passed
	}
	passed = run_stress_rejections() && passed
	if !passed {
		os.exit(1)
	}
}

print_policy :: proc() -> bool {
	valid := SELECTED_CANDIDATES == 4_096 &&
		SELECTED_QUERY_COMPONENTS == candidate_reference.MAX_QUERY_COMPONENTS &&
		SELECTED_QUERY_BYTES == candidate_reference.MAX_QUERY_BYTES &&
		SELECTED_VISIBLE_ROWS == SELECTED_CANDIDATES &&
		SELECTED_PATTERN_BYTES <= SELECTED_QUERY_BYTES &&
		SELECTED_TEMPORARY_BYTES >= SELECTED_SNAPSHOT_TEXT_BYTES / 2 &&
		SELECTED_REFRESHES_PER_TURN == 1
	fmt.printf(
		"study=candidate-policy valid=%v candidates=%d snapshot_text_bytes=%d query_bytes=%d query_components=%d visible_rows=%d pattern_bytes=%d temporary_bytes=%d refreshes_per_turn=%d ordinary_gate_ns=%d demanding_gate_ns=%d\n",
		valid,
		SELECTED_CANDIDATES,
		SELECTED_SNAPSHOT_TEXT_BYTES,
		SELECTED_QUERY_BYTES,
		SELECTED_QUERY_COMPONENTS,
		SELECTED_VISIBLE_ROWS,
		SELECTED_PATTERN_BYTES,
		SELECTED_TEMPORARY_BYTES,
		SELECTED_REFRESHES_PER_TURN,
		ORDINARY_GATE_NS,
		DEMANDING_GATE_NS,
	)
	return valid
}

run_profile :: proc(profile: Profile) -> bool {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	candidates, candidate_error := make(
		[]candidate_reference.Candidate,
		profile.candidates,
		allocator,
	)
	if candidate_error != nil {
		mem.tracking_allocator_destroy(&tracking)
		return false
	}
	labels, label_error := make([][128]byte, profile.candidates, allocator)
	if label_error != nil {
		delete(candidates, allocator)
		mem.tracking_allocator_destroy(&tracking)
		return false
	}
	results, result_error := make(
		[]candidate_reference.Projection,
		profile.candidates,
		allocator,
	)
	if result_error != nil {
		delete(labels, allocator)
		delete(candidates, allocator)
		mem.tracking_allocator_destroy(&tracking)
		return false
	}
	for index in 0 ..< profile.candidates {
		label := fmt.bprintf(
			labels[index][:],
			"alpha beta gamma delta epsilon zeta eta theta module-%04d",
			index,
		)
		candidates[index] = candidate_reference.Candidate {
			identity = {kind = 1, primary = u64(index + 1)},
			label = label,
			folded_label = label,
			recency = u64(index % 32),
		}
	}
	samples, sample_error := make([]i64, profile.samples, allocator)
	if sample_error != nil {
		delete(results, allocator)
		delete(labels, allocator)
		delete(candidates, allocator)
		mem.tracking_allocator_destroy(&tracking)
		return false
	}
	count := 0
	ok := false
	failure: candidate_reference.Failure
	checksum: u64
	for sample in 0 ..< profile.samples {
		started := time.tick_now()
		count, ok, failure = candidate_reference.filter(
			candidates,
			profile.query,
			results,
			allocator,
		)
		samples[sample] = time.duration_nanoseconds(time.tick_since(started))
		if count > 0 {
			checksum += results[0].identity.primary
			checksum += results[count - 1].identity.primary
		}
	}
	slice.sort(samples)
	p50 := samples[len(samples) / 2]
	p99 := samples[min(len(samples) - 1, len(samples) * 99 / 100)]
	valid := ok && failure.code == .None && count == profile.candidates &&
		p99 <= profile.gate_ns
	persistent_bytes := tracking.current_memory_allocated
	peak_bytes := tracking.peak_memory_allocated
	delete(samples, allocator)
	delete(results, allocator)
	delete(labels, allocator)
	delete(candidates, allocator)
	cleanup_bytes := tracking.current_memory_allocated
	valid = valid && cleanup_bytes == 0
	mem.tracking_allocator_destroy(&tracking)
	component_count := 8
	if profile.name == "ordinary" {
		component_count = 2
	}
	fmt.printf(
		"study=candidate-filter profile=%s valid=%v candidates=%d components=%d p50_ns=%d p99_ns=%d gate_ns=%d persistent_bytes=%d peak_bytes=%d cleanup_bytes=%d checksum=%d\n",
		profile.name,
		valid,
		profile.candidates,
		component_count,
		p50,
		p99,
		profile.gate_ns,
		persistent_bytes,
		peak_bytes,
		cleanup_bytes,
		checksum,
	)
	return valid
}

run_stress_rejections :: proc() -> bool {
	candidates := []candidate_reference.Candidate {
		{
			identity = {kind = 1, primary = 1},
			label = "Zażółć Alpha",
			folded_label = "zażółć alpha",
		},
	}
	output: [1]candidate_reference.Projection
	count, unicode_ok, _ := candidate_reference.filter(candidates, "ZAŻÓŁĆ", output[:])
	malformed_bytes := []byte{0xff}
	_, malformed_ok, malformed := candidate_reference.filter(
		candidates,
		transmute(string)malformed_bytes,
		output[:],
	)
	_, components_ok, components := candidate_reference.filter(
		candidates,
		"a b c d e f g h i",
		output[:],
	)
	_, output_ok, output_failure := candidate_reference.filter(candidates, "", output[:0])
	valid := unicode_ok && count == 1 && !malformed_ok &&
		malformed.code == .Malformed_UTF8 && !components_ok &&
		components.code == .Component_Limit && !output_ok &&
		output_failure.code == .Output_Limit
	fmt.printf(
		"study=candidate-stress valid=%v unicode=%v malformed=%v component_limit=%v output_limit=%v\n",
		valid,
		unicode_ok,
		malformed.code,
		components.code,
		output_failure.code,
	)
	return valid
}
