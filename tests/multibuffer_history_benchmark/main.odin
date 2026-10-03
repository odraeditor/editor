// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../../src/editor"
import "../../src/history"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:time"

MEBIBYTE :: u64(1024 * 1024)

main :: proc() {
	demanding := run_profile("demanding", 1_000, 64 * MEBIBYTE)
	stress := run_profile("stress", 10_000, 512 * MEBIBYTE)
	if !demanding || !stress {
		os.exit(1)
	}
}

run_profile :: proc(name: string, participant_count: int, metadata_limit: u64) -> bool {
	_ = metadata_limit
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	stores := make([]history.Store, participant_count)
	store_handles := make([]^history.Store, participant_count)
	inputs := make([]history.Multibuffer_Record_Input, participant_count)
	edits := make([]history.Edit_Payload, participant_count)
	defer delete(edits)
	defer delete(inputs)
	defer delete(store_handles)
	defer delete(stores)

	policy := history.DEFAULT_POLICY
	policy.multibuffer_participants = u64(participant_count)
	for index in 0 ..< participant_count {
		buffer_id := editor.Buffer_ID(index + 1)
		history_initialized, _ := history.store_init(
			&stores[index],
			history.Store_ID(index + 1),
			buffer_id,
			editor.Revision(0),
			history.Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
			policy,
		)
		if !history_initialized {
			return benchmark_fail(name, "history-init", index, &tracking)
		}
		store_handles[index] = &stores[index]
		edits[index] = history.Edit_Payload{replacement_text = "x"}
		inputs[index] = history.Multibuffer_Record_Input {
			store = &stores[index],
			record = history.Record_Input {
				source_transaction_id = history.Source_Transaction_ID(1),
				source_undo_unit_id = history.Source_Undo_Unit_ID(1),
				buffer_id = buffer_id,
				base_revision = editor.Revision(0),
				result_revision = editor.Revision(1),
				edits = edits[index:index + 1],
				origin = .Built_In,
				origin_descriptor = "benchmark",
				command = "linked-workspace-edit",
			},
		}
	}
	reservation: history.Multibuffer_Reservation
	prepare_started := time.tick_now()
	validated, validation_failure := history.multibuffer_record_reserve(&reservation, inputs)
	prepare_elapsed := time.tick_since(prepare_started)
	if !validated {
		fmt.eprintf("benchmark=multibuffer-history profile=%s phase=validate failure=%v\n", name, validation_failure.code)
		return false
	}
	publication_started := time.tick_now()
	history.multibuffer_reservation_commit_reserved(&reservation)
	publication_elapsed := time.tick_since(publication_started)
	history_bytes := u64(0)
	retained_links := u64(0)
	for &store in stores {
		stats, stats_ok, _ := history.store_stats(&store)
		if !stats_ok || stats.current_revision != editor.Revision(1) {
			return false
		}
		history_bytes += stats.usage.retained_bytes
		retained_links += stats.usage.retained_links
	}
	closed, close_failure := history.multibuffer_stores_close(store_handles)
	if !closed {
		fmt.eprintf("benchmark=multibuffer-history profile=%s phase=history-close failure=%v\n", name, close_failure.code)
		return false
	}
	cleanup_bytes := tracking.current_memory_allocated
	fmt.printf(
		"benchmark=multibuffer-history profile=%s participants=%d prepare_ns=%d publication_ns=%d history_accounted_bytes=%d retained_links=%d peak_bytes=%d cleanup_bytes=%d\n",
		name,
		participant_count,
		time.duration_nanoseconds(prepare_elapsed),
		time.duration_nanoseconds(publication_elapsed),
		history_bytes,
		retained_links,
		tracking.peak_memory_allocated,
		cleanup_bytes,
	)
	mem.tracking_allocator_destroy(&tracking)
	return retained_links == 1 && cleanup_bytes == 0
}

benchmark_fail :: proc(
	profile, phase: string,
	index: int,
	tracking: ^mem.Tracking_Allocator,
) -> bool {
	fmt.eprintf(
		"benchmark=multibuffer-history profile=%s phase=%s index=%d retained_bytes=%d\n",
		profile,
		phase,
		index,
		tracking.current_memory_allocated,
	)
	return false
}
