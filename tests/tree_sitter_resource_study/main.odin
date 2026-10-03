// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import editor "../../src/editor"
import language "../../src/language"
import transaction "../../src/transaction"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:slice"
import "core:time"

MAX_SAMPLES :: 16
VISIBLE_BYTES :: u64(16 * 1024)
CANCELLATION_GATE_NS :: i64(100_000_000)
TEARDOWN_GATE_NS :: i64(100_000_000)

Profile :: struct {
	name:                string,
	source_bytes:        int,
	samples:             int,
	initial_gate_ns:     i64,
	incremental_gate_ns: i64,
	visible_gate_ns:     i64,
}

Latency :: struct {
	p50_ns: i64,
	p99_ns: i64,
}

main :: proc() {
	profiles := [?]Profile {
		{
			name = "ordinary",
			source_bytes = 64 * 1024,
			samples = 16,
			initial_gate_ns = 100_000_000,
			incremental_gate_ns = 50_000_000,
			visible_gate_ns = 25_000_000,
		},
		{
			name = "demanding",
			source_bytes = 2 * 1024 * 1024,
			samples = 3,
			initial_gate_ns = 1_500_000_000,
			incremental_gate_ns = 1_500_000_000,
			visible_gate_ns = 25_000_000,
		},
	}
	passed := true
	for profile in profiles {
		passed = run_profile(profile) && passed
	}
	if !passed do os.exit(1)
}

run_profile :: proc(profile: Profile) -> bool {
	source, source_ok := make_source(profile.source_bytes)
	if !source_ok do return false
	defer delete(source)

	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)

	buffer: editor.Buffer
	initialized, _ := editor.buffer_init(
		&buffer,
		1,
		string(source[:]),
		editor.Allocator_Set {
			persistent = allocator,
			temporary = context.temp_allocator,
		},
	)
	if !initialized {
		mem.tracking_allocator_destroy(&tracking)
		return false
	}
	base: editor.Buffer_Snapshot
	base_open, _ := editor.buffer_snapshot_open(&buffer, &base)
	if !base_open {
		editor.buffer_close(&buffer)
		mem.tracking_allocator_destroy(&tracking)
		return false
	}

	analysis_language, provider := identity()
	initial_samples: [MAX_SAMPLES]i64
	initial_owner: language.Tree_Sitter_Owner
	initial_ready, _ := language.tree_sitter_owner_init(&initial_owner, 1, allocator)
	valid := initial_ready
	if initial_ready {
		query_ready, _ := language.tree_sitter_owner_compile_odin_query(&initial_owner, 1)
		valid = query_ready && valid
		if query_ready {
			for sample in 0 ..< profile.samples {
				started := time.tick_now()
				_, parsed, _ := language.tree_sitter_owner_parse_snapshot(
					&initial_owner,
					&base,
					analysis_language,
					provider,
					1,
					language.Tree_Generation(sample + 1),
				)
				initial_samples[sample] = time.duration_nanoseconds(time.tick_since(started))
				valid = parsed && valid
			}
		}
	}
	initial_latency := measured_latency(initial_samples[:profile.samples])

	splice_start := editor.Byte_Offset(len(source) - 3)
	start, start_ok, _ := editor.buffer_position(&buffer, splice_start)
	end, end_ok, _ := editor.buffer_position(&buffer, splice_start + 2)
	change, _, published, _ := editor.buffer_splice(
		&buffer,
		editor.Splice{start = start, end = end, replacement = "43"},
		context.temp_allocator,
	)
	valid = start_ok && end_ok && published && valid
	result: editor.Buffer_Snapshot
	result_open := false
	if published {
		result_open, _ = editor.buffer_snapshot_open(&buffer, &result)
	}
	valid = result_open && valid
	splices := [1]transaction.Normalized_Splice {{
		start = change.start,
		end = editor.Byte_Offset(u64(change.start) + change.removed_bytes),
		replacement_text = change.replacement_text,
		removed_text = "42",
	}}
	event := transaction.Commit_Event {
		buffer_id = change.buffer_id,
		base_revision = change.base_revision,
		result_revision = change.result_revision,
		splices = splices[:],
	}

	incremental_samples: [MAX_SAMPLES]i64
	foreign_peak_bytes: u64
	for sample in 0 ..< profile.samples {
		owner: language.Tree_Sitter_Owner
		ready, _ := language.tree_sitter_owner_init(
			&owner,
			language.Parser_Generation(sample + 2),
			allocator,
		)
		valid = ready && valid
		if !ready do continue
		query_ready, _ := language.tree_sitter_owner_compile_odin_query(&owner, 1)
		_, base_parsed, _ := language.tree_sitter_owner_parse_snapshot(
			&owner,
			&base,
			analysis_language,
			provider,
			1,
			1,
		)
		valid = query_ready && base_parsed && valid
		if query_ready && base_parsed && result_open {
			started := time.tick_now()
			_, parsed, _ := language.tree_sitter_owner_parse_incremental(
				&owner,
				&base,
				&result,
				event,
				2,
			)
			incremental_samples[sample] = time.duration_nanoseconds(time.tick_since(started))
			valid = parsed && valid
		}
		stats, stats_ok, _ := language.tree_sitter_owner_stats(&owner)
		if stats_ok do foreign_peak_bytes = max(foreign_peak_bytes, stats.foreign_peak_bytes)
		closed, _ := language.tree_sitter_owner_close(&owner)
		valid = stats_ok && closed && valid
	}
	incremental_latency := measured_latency(incremental_samples[:profile.samples])

	visible_samples: [MAX_SAMPLES]i64
	if initial_ready && result_open {
		_, parsed, _ := language.tree_sitter_owner_parse_snapshot(
			&initial_owner,
			&result,
			analysis_language,
			provider,
			1,
			language.Tree_Generation(profile.samples + 1),
		)
		valid = parsed && valid
		visible_end := min(VISIBLE_BYTES, u64(len(source)))
		for sample in 0 ..< profile.samples {
			started := time.tick_now()
			query_result, queried, _ := language.tree_sitter_owner_query_spans(
				&initial_owner,
				&result,
				0,
				visible_end,
				0,
				language.Syntax_Snapshot_Generation(sample + 1),
				allocator,
			)
			visible_samples[sample] = time.duration_nanoseconds(time.tick_since(started))
			valid = queried && valid
			if queried do language.syntax_query_result_close(&query_result)
		}
	}
	visible_latency := measured_latency(visible_samples[:profile.samples])
	cancellation_started := time.tick_now()
	cancel_requested, _ := language.tree_sitter_owner_request_cancel(&initial_owner)
	_, cancellation_succeeded, cancellation_failure := language.tree_sitter_owner_parse_snapshot(
		&initial_owner,
		&result,
		analysis_language,
		provider,
		1,
		language.Tree_Generation(profile.samples + 2),
	)
	cancellation_ns := time.duration_nanoseconds(time.tick_since(cancellation_started))
	cancel_cleared, _ := language.tree_sitter_owner_clear_cancel(&initial_owner)
	valid = cancel_requested && !cancellation_succeeded &&
		cancellation_failure.code == .Cancelled && cancel_cleared && valid

	if initial_ready {
		stats, stats_ok, _ := language.tree_sitter_owner_stats(&initial_owner)
		if stats_ok do foreign_peak_bytes = max(foreign_peak_bytes, stats.foreign_peak_bytes)
		valid = stats_ok && valid
	}
	teardown_started := time.tick_now()
	if initial_ready {
		closed, _ := language.tree_sitter_owner_close(&initial_owner)
		valid = closed && valid
	}
	teardown_ns := time.duration_nanoseconds(time.tick_since(teardown_started))
	if result_open do editor.buffer_snapshot_close(&result)
	editor.buffer_snapshot_close(&base)
	editor.buffer_close(&buffer)
	cleanup_bytes := tracking.current_memory_allocated
	peak_bytes := tracking.peak_memory_allocated
	mem.tracking_allocator_destroy(&tracking)

	within_gates := initial_latency.p99_ns <= profile.initial_gate_ns &&
		incremental_latency.p99_ns <= profile.incremental_gate_ns &&
		visible_latency.p99_ns <= profile.visible_gate_ns &&
		cancellation_ns <= CANCELLATION_GATE_NS &&
		teardown_ns <= TEARDOWN_GATE_NS
	combined_peak_bytes := u64(peak_bytes) + foreign_peak_bytes
	within_resources := combined_peak_bytes <= language.MAX_RETAINED_ANALYSIS_BYTES &&
		cleanup_bytes == 0
	valid = valid && within_gates && within_resources
	fmt.printf(
		"study=tree-sitter-analysis profile=%s valid=%v source_bytes=%d samples=%d initial_p50_ns=%d initial_p99_ns=%d initial_gate_ns=%d incremental_p50_ns=%d incremental_p99_ns=%d incremental_gate_ns=%d visible_bytes=%d visible_p50_ns=%d visible_p99_ns=%d visible_gate_ns=%d cancellation_ns=%d cancellation_gate_ns=%d odin_peak_bytes=%d foreign_peak_bytes=%d combined_peak_bytes=%d teardown_ns=%d teardown_gate_ns=%d cleanup_bytes=%d\n",
		profile.name,
		valid,
		profile.source_bytes,
		profile.samples,
		initial_latency.p50_ns,
		initial_latency.p99_ns,
		profile.initial_gate_ns,
		incremental_latency.p50_ns,
		incremental_latency.p99_ns,
		profile.incremental_gate_ns,
		VISIBLE_BYTES,
		visible_latency.p50_ns,
		visible_latency.p99_ns,
		profile.visible_gate_ns,
		cancellation_ns,
		CANCELLATION_GATE_NS,
		peak_bytes,
		foreign_peak_bytes,
		combined_peak_bytes,
		teardown_ns,
		TEARDOWN_GATE_NS,
		cleanup_bytes,
	)
	return valid
}

make_source :: proc(source_bytes: int) -> ([dynamic]u8, bool) {
	source, allocation_error := make([dynamic]u8, 0, source_bytes + 16)
	if allocation_error != nil do return nil, false
	line := transmute([]u8)(string("value :: 42\n"))
	_, append_error := append(&source, ..transmute([]u8)(string("package study\n")))
	if append_error != nil {
		delete(source)
		return nil, false
	}
	for len(source) + len(line) <= source_bytes {
		_, append_error = append(&source, ..line)
		if append_error != nil {
			delete(source)
			return nil, false
		}
	}
	return source, true
}

identity :: proc() -> (language.Language_Identity, language.Provider_Handle) {
	analysis_language := language.Language_Identity{id = 1, generation = 1}
	return analysis_language, language.Provider_Handle {
		registry_id = 1,
		language_id = analysis_language.id,
		provider_id = 1,
		provider_generation = 1,
	}
}

measured_latency :: proc(samples: []i64) -> Latency {
	slice.sort(samples)
	return Latency {
		p50_ns = percentile(samples, 50),
		p99_ns = percentile(samples, 99),
	}
}

percentile :: proc(samples: []i64, percent: int) -> i64 {
	if len(samples) == 0 do return 0
	return samples[(len(samples) - 1) * percent / 100]
}
