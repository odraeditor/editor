// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import history "../candidate_history_reference"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:slice"
import "core:time"

ORDINARY_ENTRIES :: 256
DEMANDING_ENTRIES :: history.SELECTED_ENTRIES
ORDINARY_GATE_NS :: i64(5_000_000)
DEMANDING_GATE_NS :: i64(50_000_000)

Profile :: struct {
	name:    string,
	entries: int,
	samples: int,
	gate_ns: i64,
}

main :: proc() {
	passed := print_policy()
	profiles := [?]Profile {
		{name = "ordinary", entries = ORDINARY_ENTRIES, samples = 512, gate_ns = ORDINARY_GATE_NS},
		{name = "demanding", entries = DEMANDING_ENTRIES, samples = 128, gate_ns = DEMANDING_GATE_NS},
	}
	for profile in profiles {
		passed = run_profile(profile) && passed
	}
	passed = run_stress() && passed
	if !passed {
		os.exit(1)
	}
}

print_policy :: proc() -> bool {
	limits := history.DEFAULT_LIMITS
	valid := limits.entries == history.SELECTED_ENTRIES &&
	         limits.key_bytes == history.SELECTED_KEY_BYTES &&
	         limits.module_bytes == history.SELECTED_MODULE_BYTES &&
	         limits.sequence_ceiling == history.SELECTED_SEQUENCE_CEILING &&
	         limits.dirty_generations == history.SELECTED_DIRTY_GENERATIONS &&
	         limits.flush_events == history.SELECTED_FLUSH_EVENTS &&
	         limits.retries == history.SELECTED_RETRIES &&
	         limits.callbacks == history.SELECTED_CALLBACKS
	fmt.printf(
		"study=candidate-history profile=policy valid=%v selected_entries=%d selected_key_bytes=%d selected_module_bytes=%d selected_sequence_ceiling=%d selected_dirty_generations=%d selected_flush_events=%d selected_retries=%d selected_callbacks=%d ordinary_gate_ns=%d demanding_gate_ns=%d\n",
		valid,
		limits.entries,
		limits.key_bytes,
		limits.module_bytes,
		limits.sequence_ceiling,
		limits.dirty_generations,
		limits.flush_events,
		limits.retries,
		limits.callbacks,
		ORDINARY_GATE_NS,
		DEMANDING_GATE_NS,
	)
	return valid
}

run_profile :: proc(profile: Profile) -> bool {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	state, initialized, _ := history.state_init("resource-study", history.DEFAULT_LIMITS, allocator)
	if !initialized {
		mem.tracking_allocator_destroy(&tracking)
		return false
	}
	keys, keys_error := make([][128]u8, profile.entries, allocator)
	if keys_error != nil {
		history.state_destroy(&state)
		mem.tracking_allocator_destroy(&tracking)
		return false
	}
	for index in 0 ..< profile.entries {
		key := fmt.bprintf(keys[index][:], "/project/src/candidate-%04d-界.odin", index)
		_, recorded, _ := history.record_success(&state, .Project_File, key)
		if !recorded {
			delete(keys, allocator)
			history.state_destroy(&state)
			mem.tracking_allocator_destroy(&tracking)
			return false
		}
	}
	indices, indices_error := make([]int, profile.entries, allocator)
	samples, samples_error := make([]i64, profile.samples, allocator)
	if indices_error != nil || samples_error != nil {
		if samples != nil {delete(samples, allocator)}
		if indices != nil {delete(indices, allocator)}
		delete(keys, allocator)
		history.state_destroy(&state)
		mem.tracking_allocator_destroy(&tracking)
		return false
	}
	checksum: u64
	for sample in 0 ..< profile.samples {
		key := fmt.bprintf(keys[sample % profile.entries][:], "/project/src/candidate-%04d-界.odin", sample % profile.entries)
		started := time.tick_now()
		sequence, recorded, _ := history.record_success(&state, .Project_File, key)
		count, ordered := history.canonical_indices(&state, indices)
		samples[sample] = time.duration_nanoseconds(time.tick_since(started))
		if !recorded || !ordered || count != profile.entries {
			samples[sample] = profile.gate_ns + 1
		}
		checksum += sequence + u64(indices[0])
	}
	slice.sort(samples)
	p50 := samples[len(samples) / 2]
	p99 := samples[min(len(samples) - 1, len(samples) * 99 / 100)]
	module_bytes, module_ok := history.estimated_module_bytes(&state)
	persistent_bytes := tracking.current_memory_allocated
	peak_bytes := tracking.peak_memory_allocated
	valid := state.active_count == profile.entries && module_ok && p99 <= profile.gate_ns
	delete(samples, allocator)
	delete(indices, allocator)
	delete(keys, allocator)
	history.state_destroy(&state)
	cleanup_bytes := tracking.current_memory_allocated
	valid = valid && cleanup_bytes == 0
	mem.tracking_allocator_destroy(&tracking)
	fmt.printf(
		"study=candidate-history profile=%s valid=%v entries=%d module_bytes=%d p50_ns=%d p99_ns=%d gate_ns=%d persistent_bytes=%d peak_bytes=%d cleanup_bytes=%d checksum=%d\n",
		profile.name,
		valid,
		profile.entries,
		module_bytes,
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

run_stress :: proc() -> bool {
	state, initialized, _ := history.state_init("stress-project")
	if !initialized {
		return false
	}
	defer history.state_destroy(&state)
	maximum_key_storage: [history.SELECTED_KEY_BYTES]u8
	for &byte in maximum_key_storage {
		byte = 'a'
	}
	maximum_key_storage[0] = '/'
	_, maximum_ok, _ := history.record_success(
		&state,
		.Project_File,
		transmute(string)maximum_key_storage[:],
	)
	oversized_storage: [history.SELECTED_KEY_BYTES + 1]u8
	for &byte in oversized_storage {
		byte = 'b'
	}
	oversized_storage[0] = '/'
	_, oversized_ok, oversized_failure := history.record_success(
		&state,
		.Project_File,
		transmute(string)oversized_storage[:],
	)
	limits := history.DEFAULT_LIMITS
	limits.entries = 2
	limits.sequence_ceiling = 5
	bounded, bounded_ok, _ := history.state_init("bounded-project", limits)
	if !bounded_ok {
		return false
	}
	defer history.state_destroy(&bounded)
	history.record_success(&bounded, .Command, "alpha")
	history.record_success(&bounded, .Command, "beta")
	history.record_success(&bounded, .Command, "gamma")
	history.record_success(&bounded, .Command, "beta")
	_, renormalized, _ := history.record_success(&bounded, .Command, "beta")
	_, alpha_present := history.lookup(&bounded, .Command, "alpha")
	valid := maximum_ok && !oversized_ok && oversized_failure.code == .Invalid_Key &&
	         bounded.active_count == 2 && !alpha_present && renormalized &&
	         bounded.next_sequence < limits.sequence_ceiling
	fmt.printf(
		"study=candidate-history profile=stress valid=%v maximum_key=%v oversized_key=%v retention=%v renormalization=%v dirty_generations=%d retries=%d callbacks=%d\n",
		valid,
		maximum_ok,
		oversized_failure.code,
		bounded.active_count == 2 && !alpha_present,
		renormalized,
		history.SELECTED_DIRTY_GENERATIONS,
		history.SELECTED_RETRIES,
		history.SELECTED_CALLBACKS,
	)
	return valid
}
