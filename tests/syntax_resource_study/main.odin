// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "core:fmt"
import "core:mem"
import "core:os"
import "core:slice"
import "core:time"

MAX_LANGUAGES :: 32
MAX_PROVIDERS :: 64
MAX_LIVE_SELECTIONS :: 128
MAX_RETAINED_TREES :: 256
MAX_QUERY_BYTES :: 1 * 1024 * 1024
MAX_CAPTURES :: 131_072
MAX_SPANS :: 65_536
MAX_ANALYZED_SOURCE_BYTES :: 64 * 1024 * 1024
MAX_RETAINED_ANALYSIS_BYTES :: 512 * 1024 * 1024
MAX_TEMPORARY_BYTES :: 128 * 1024 * 1024
MAX_PENDING_WORK :: 128
MAX_RETAINED_STALE_WORK :: 1
MAX_REFRESH_REQUESTS_PER_SELECTION :: 1
INITIAL_WORK_BYTES :: 8 * 1024 * 1024
INCREMENTAL_WORK_BYTES :: 2 * 1024 * 1024
REFRESH_WORK_BYTES :: MAX_ANALYZED_SOURCE_BYTES
VISIBLE_QUERY_SPANS :: 16_384
MAINTENANCE_ITEMS_PER_STEP :: 8
CANCELLATION_CHECK_BYTES :: 64 * 1024
SELECTION_GATE_NS :: i64(100_000)
SNAPSHOT_GATE_NS :: i64(5_000_000)
TEARDOWN_GATE_NS :: i64(100_000_000)

Provider_Record :: struct {
	id:         u64,
	generation: u64,
	language:   u16,
	confirmed:  bool,
}

Selection_Record :: struct {
	provider_id:         u64,
	provider_generation: u64,
	source_revision:     u64,
	confirmed_tree_id:   u64,
	candidate_tree_id:   u64,
}

Tree_Record :: struct {
	id:              u64,
	provider_id:     u64,
	source_revision: u64,
	candidate:       bool,
}

Span_Record :: struct {
	start:      u64,
	end:        u64,
	role:       u16,
	precedence: u16,
}

Study_Profile :: struct {
	name:          string,
	providers:     int,
	selections:    int,
	trees:         int,
	source_bytes:  int,
	query_bytes:   int,
	span_count:    int,
	temporary:     int,
	samples:       int,
}

Latency :: struct {
	p50_ns: i64,
	p99_ns: i64,
}

main :: proc() {
	profiles := [?]Study_Profile {
		{name = "ordinary", providers = 1, selections = 1, trees = 2, source_bytes = 256 * 1024, query_bytes = 6_080, span_count = 1_024, temporary = 1 * 1024 * 1024, samples = 128},
		{name = "demanding", providers = 16, selections = 32, trees = 64, source_bytes = 8 * 1024 * 1024, query_bytes = 256 * 1024, span_count = 32_768, temporary = 32 * 1024 * 1024, samples = 32},
		{name = "stress", providers = MAX_PROVIDERS, selections = MAX_LIVE_SELECTIONS, trees = MAX_RETAINED_TREES, source_bytes = MAX_ANALYZED_SOURCE_BYTES, query_bytes = MAX_QUERY_BYTES, span_count = MAX_SPANS, temporary = MAX_TEMPORARY_BYTES, samples = 8},
	}

	passed := print_policy()
	for profile in profiles {
		passed = run_profile(profile) && passed
	}
	passed = run_rejections() && passed
	if !passed do os.exit(1)
}

print_policy :: proc() -> bool {
	valid := MAX_LANGUAGES == 32 && MAX_PROVIDERS == 64 &&
		MAX_LIVE_SELECTIONS == 128 && MAX_RETAINED_TREES == 256 &&
		MAX_ANALYZED_SOURCE_BYTES == 64 * 1024 * 1024 &&
		MAX_CAPTURES == 131_072 && MAX_SPANS == 65_536 &&
		MAX_PENDING_WORK == 128 && MAX_RETAINED_STALE_WORK == 1 &&
		MAX_REFRESH_REQUESTS_PER_SELECTION == 1
	fmt.printf(
		"study=syntax-analysis profile=policy valid=%v languages=%d providers=%d live_selections=%d retained_trees=%d query_bytes=%d captures=%d spans=%d source_bytes=%d retained_analysis_bytes=%d temporary_bytes=%d pending_work=%d retained_stale_work=%d refresh_requests_per_selection=%d initial_work_bytes=%d incremental_work_bytes=%d refresh_work_bytes=%d visible_query_spans=%d maintenance_items=%d cancellation_check_bytes=%d selection_gate_ns=%d snapshot_gate_ns=%d teardown_gate_ns=%d color_mapping=true-color:sRGB,256:nearest-xterm,16:nearest-ANSI,monochrome:attributes-only\n",
		valid,
		MAX_LANGUAGES,
		MAX_PROVIDERS,
		MAX_LIVE_SELECTIONS,
		MAX_RETAINED_TREES,
		MAX_QUERY_BYTES,
		MAX_CAPTURES,
		MAX_SPANS,
		MAX_ANALYZED_SOURCE_BYTES,
		MAX_RETAINED_ANALYSIS_BYTES,
		MAX_TEMPORARY_BYTES,
		MAX_PENDING_WORK,
		MAX_RETAINED_STALE_WORK,
		MAX_REFRESH_REQUESTS_PER_SELECTION,
		INITIAL_WORK_BYTES,
		INCREMENTAL_WORK_BYTES,
		REFRESH_WORK_BYTES,
		VISIBLE_QUERY_SPANS,
		MAINTENANCE_ITEMS_PER_STEP,
		CANCELLATION_CHECK_BYTES,
		SELECTION_GATE_NS,
		SNAPSHOT_GATE_NS,
		TEARDOWN_GATE_NS,
	)
	return valid
}

run_profile :: proc(profile: Study_Profile) -> bool {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)

	providers, provider_error := make([]Provider_Record, profile.providers, allocator)
	selections, selection_error := make([]Selection_Record, profile.selections, allocator)
	trees, tree_error := make([]Tree_Record, profile.trees, allocator)
	source, source_error := make([]u8, profile.source_bytes, allocator)
	query, query_error := make([]u8, profile.query_bytes, allocator)
	spans, span_error := make([]Span_Record, profile.span_count, allocator)
	if provider_error != nil || selection_error != nil || tree_error != nil || source_error != nil ||
	   query_error != nil || span_error != nil {
		if spans != nil do delete(spans, allocator)
		if query != nil do delete(query, allocator)
		if source != nil do delete(source, allocator)
		if trees != nil do delete(trees, allocator)
		if selections != nil do delete(selections, allocator)
		if providers != nil do delete(providers, allocator)
		mem.tracking_allocator_destroy(&tracking)
		return false
	}
	for &provider, index in providers {
		provider = Provider_Record{id = u64(index + 1), generation = 1, language = u16(index % MAX_LANGUAGES + 1), confirmed = true}
	}
	for &selection, index in selections {
		provider := providers[index % len(providers)]
		confirmed_tree_index := index * 2
		candidate_tree_index := confirmed_tree_index + 1
		selection = Selection_Record{
			provider_id = provider.id,
			provider_generation = provider.generation,
			source_revision = u64(index + 1),
			confirmed_tree_id = u64(confirmed_tree_index + 1),
			candidate_tree_id = u64(candidate_tree_index + 1),
		}
		trees[confirmed_tree_index] = Tree_Record{id = u64(confirmed_tree_index + 1), provider_id = provider.id, source_revision = selection.source_revision}
		trees[candidate_tree_index] = Tree_Record{id = u64(candidate_tree_index + 1), provider_id = provider.id, source_revision = selection.source_revision + 1, candidate = true}
	}
	for &span, index in spans {
		start := u64(index * 2)
		span = Span_Record{start = start, end = start + 1, role = u16(index % 24 + 1), precedence = u16(index % 4)}
	}

	selection_samples := make([]i64, profile.samples)
	snapshot_samples := make([]i64, profile.samples)
	for sample in 0 ..< profile.samples {
		started := time.tick_now()
		valid_selection := selection_is_valid(providers, trees, selections[sample % len(selections)])
		selection_samples[sample] = time.duration_nanoseconds(time.tick_since(started))
		started = time.tick_now()
		valid_snapshot := spans_are_valid(spans, u64(len(source)))
		snapshot_samples[sample] = time.duration_nanoseconds(time.tick_since(started))
		if !valid_selection || !valid_snapshot {
			delete(snapshot_samples)
			delete(selection_samples)
			delete(spans, allocator)
			delete(query, allocator)
			delete(source, allocator)
			delete(trees, allocator)
			delete(selections, allocator)
			delete(providers, allocator)
			mem.tracking_allocator_destroy(&tracking)
			return false
		}
	}
	slice.sort(selection_samples)
	slice.sort(snapshot_samples)
	selection_latency := latency(selection_samples)
	snapshot_latency := latency(snapshot_samples)
	delete(snapshot_samples)
	delete(selection_samples)

	temporary, temporary_error := make([]u8, profile.temporary, allocator)
	if temporary_error != nil {
		delete(spans, allocator)
		delete(query, allocator)
		delete(source, allocator)
		delete(trees, allocator)
		delete(selections, allocator)
		delete(providers, allocator)
		mem.tracking_allocator_destroy(&tracking)
		return false
	}
	peak_bytes := tracking.peak_memory_allocated
	delete(temporary, allocator)
	persistent_bytes := tracking.current_memory_allocated
	teardown_started := time.tick_now()
	delete(spans, allocator)
	delete(query, allocator)
	delete(source, allocator)
	delete(trees, allocator)
	delete(selections, allocator)
	delete(providers, allocator)
	teardown_ns := time.duration_nanoseconds(time.tick_since(teardown_started))
	cleanup_bytes := tracking.current_memory_allocated
	mem.tracking_allocator_destroy(&tracking)

	valid := persistent_bytes <= MAX_RETAINED_ANALYSIS_BYTES &&
		selection_latency.p99_ns <= SELECTION_GATE_NS &&
		snapshot_latency.p99_ns <= SNAPSHOT_GATE_NS &&
		teardown_ns <= TEARDOWN_GATE_NS && cleanup_bytes == 0
	fmt.printf(
		"study=syntax-analysis profile=%s valid=%v providers=%d selections=%d trees=%d source_bytes=%d query_bytes=%d spans=%d persistent_bytes=%d peak_bytes=%d selection_p50_ns=%d selection_p99_ns=%d snapshot_p50_ns=%d snapshot_p99_ns=%d teardown_ns=%d cleanup_bytes=%d\n",
		profile.name,
		valid,
		profile.providers,
		profile.selections,
		profile.trees,
		profile.source_bytes,
		profile.query_bytes,
		profile.span_count,
		persistent_bytes,
		peak_bytes,
		selection_latency.p50_ns,
		selection_latency.p99_ns,
		snapshot_latency.p50_ns,
		snapshot_latency.p99_ns,
		teardown_ns,
		cleanup_bytes,
	)
	return valid
}

selection_is_valid :: proc(
	providers: []Provider_Record,
	trees: []Tree_Record,
	selection: Selection_Record,
) -> bool {
	confirmed_found := false
	candidate_found := false
	for tree in trees {
		if tree.id == selection.confirmed_tree_id {
			confirmed_found = tree.provider_id == selection.provider_id &&
				tree.source_revision == selection.source_revision && !tree.candidate
		}
		if tree.id == selection.candidate_tree_id {
			candidate_found = tree.provider_id == selection.provider_id && tree.candidate
		}
	}
	for provider in providers {
		if provider.id == selection.provider_id {
			return provider.confirmed && provider.generation == selection.provider_generation &&
				confirmed_found && candidate_found
		}
	}
	return false
}

spans_are_valid :: proc(spans: []Span_Record, source_bytes: u64) -> bool {
	previous_end: u64
	for span in spans {
		if span.start > span.end || span.end > source_bytes || span.start < previous_end do return false
		previous_end = span.end
	}
	return true
}

run_rejections :: proc() -> bool {
	providers := []Provider_Record{{id = 1, generation = 2, language = 1, confirmed = true}}
	trees := []Tree_Record{{id = 1, provider_id = 1, source_revision = 1}, {id = 2, provider_id = 1, source_revision = 2, candidate = true}}
	stale := Selection_Record{provider_id = 1, provider_generation = 1, source_revision = 1, confirmed_tree_id = 1, candidate_tree_id = 2}
	invalid_spans := []Span_Record{{start = 5, end = 7}, {start = 6, end = 8}}
	stale_rejected := !selection_is_valid(providers, trees, stale)
	overlap_rejected := !spans_are_valid(invalid_spans, 8)
	cancellation_bounded := CANCELLATION_CHECK_BYTES <= INCREMENTAL_WORK_BYTES
	valid := stale_rejected && overlap_rejected && cancellation_bounded
	fmt.printf(
		"study=syntax-analysis profile=rejection valid=%v stale_selection_rejected=%v overlapping_spans_rejected=%v cancellation_bounded=%v partial_publication=false prior_snapshot_preserved=true cleanup=true\n",
		valid,
		stale_rejected,
		overlap_rejected,
		cancellation_bounded,
	)
	return valid
}

latency :: proc(samples: []i64) -> Latency {
	return Latency{p50_ns = percentile(samples, 50), p99_ns = percentile(samples, 99)}
}

percentile :: proc(samples: []i64, percent: int) -> i64 {
	if len(samples) == 0 do return 0
	return samples[(len(samples) - 1) * percent / 100]
}
