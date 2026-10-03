// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../../src/editor"
import "../../src/transaction"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:slice"
import "core:time"

MEBIBYTE :: u64(1024 * 1024)
DEMANDING_BUFFERS :: 1_000
STRESS_BUFFERS :: 10_000
DEMANDING_SAMPLES :: 12
STRESS_SAMPLES :: 1
DEMANDING_PUBLICATION_GATE_NS :: i64(4_000_000)
STRESS_PUBLICATION_GATE_NS :: i64(16_000_000)

main :: proc() {
	demanding_ok := run_profile(
		"demanding",
		DEMANDING_BUFFERS,
		DEMANDING_SAMPLES,
		64 * MEBIBYTE,
		DEMANDING_PUBLICATION_GATE_NS,
	)
	stress_ok := run_profile(
		"stress",
		STRESS_BUFFERS,
		STRESS_SAMPLES,
		512 * MEBIBYTE,
		STRESS_PUBLICATION_GATE_NS,
	)
	if !demanding_ok || !stress_ok {
		os.exit(1)
	}
}

run_profile :: proc(
	name: string,
	participant_count, sample_count: int,
	metadata_limit: u64,
	publication_gate_ns: i64,
) -> bool {
	publication_latencies := make([]i64, sample_count)
	defer delete(publication_latencies)
	maximum_prepare_ns := i64(0)
	maximum_base_bytes := i64(0)
	maximum_transaction_peak_bytes := i64(0)
	for sample in 0 ..< sample_count {
		prepare_ns, publication_ns, base_bytes, transaction_peak_bytes, sample_ok := run_sample(
			participant_count,
			metadata_limit,
			sample,
		)
		if !sample_ok {
			return false
		}
		publication_latencies[sample] = publication_ns
		maximum_prepare_ns = max(maximum_prepare_ns, prepare_ns)
		maximum_base_bytes = max(maximum_base_bytes, base_bytes)
		maximum_transaction_peak_bytes = max(maximum_transaction_peak_bytes, transaction_peak_bytes)
	}
	slice.sort(publication_latencies)
	p99_index := max(0, (sample_count * 99 + 99) / 100 - 1)
	publication_p99_ns := publication_latencies[p99_index]
	within_gate := publication_p99_ns <= publication_gate_ns
	fmt.printf(
		"benchmark=multibuffer-transaction profile=%s participants=%d samples=%d prepare_max_ns=%d publication_p99_ns=%d publication_gate_ns=%d within_gate=%v base_accounted_bytes=%d transaction_peak_added_bytes=%d\n",
		name,
		participant_count,
		sample_count,
		maximum_prepare_ns,
		publication_p99_ns,
		publication_gate_ns,
		within_gate,
		maximum_base_bytes,
		maximum_transaction_peak_bytes,
	)
	return within_gate
}

run_sample :: proc(
	participant_count: int,
	metadata_limit: u64,
	sample: int,
) -> (prepare_ns, publication_ns, base_bytes, transaction_peak_bytes: i64, ok: bool) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	buffers := make([]editor.Buffer, participant_count)
	snapshots := make([]transaction.Proposal_Snapshot, participant_count)
	edits := make([]transaction.Proposal_Edit, participant_count)
	batches := make([]transaction.Base_Splice, participant_count)
	defer delete(batches)
	defer delete(edits)
	defer delete(snapshots)
	defer delete(buffers)

	allocator := mem.tracking_allocator(&tracking)
	buffer_limits := editor.DEFAULT_LIMITS
	buffer_limits.buffer_bytes = 1 * MEBIBYTE
	buffer_limits.replacement_bytes = 1 * MEBIBYTE
	buffer_limits.persistent_bytes = 16 * MEBIBYTE
	buffer_limits.undo_bytes = 8 * MEBIBYTE
	buffer_limits.inspection_bytes = 1 * MEBIBYTE
	buffer_limits.reclaim_step_nodes = 64
	buffer_limits.reclaim_queue_nodes = 64
	for index in 0 ..< participant_count {
		buffer_id := editor.Buffer_ID(1 + index)
		initialized, init_failure := editor.buffer_init(
			&buffers[index],
			buffer_id,
			"",
			editor.Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
			buffer_limits,
		)
		if !initialized {
			fmt.eprintf("phase=buffer-init index=%d failure=%v\n", index, init_failure.code)
			close_buffers(buffers[:index])
			mem.tracking_allocator_destroy(&tracking)
			return 0, 0, 0, 0, false
		}
		position, _, _ := editor.buffer_position(&buffers[index], editor.Byte_Offset(0))
		batches[index] = transaction.Base_Splice {
			start = position,
			end = position,
			replacement = "x",
		}
		snapshots[index] = transaction.Proposal_Snapshot {
			buffer = &buffers[index],
			buffer_id = buffer_id,
			base_revision = editor.Revision(0),
		}
		edits[index] = transaction.Proposal_Edit {
			buffer_id = buffer_id,
			base_revision = editor.Revision(0),
			batch = batches[index:index + 1],
		}
	}
	base_bytes = tracking.current_memory_allocated

	limits := transaction.DEFAULT_LIMITS
	limits.buffer_participants = u64(participant_count)
	limits.splices = u64(participant_count)
	limits.metadata_bytes = metadata_limit
	root: transaction.Multibuffer_Transaction
	prepare_started := time.tick_now()
	admitted, admission_failure := transaction.proposal_admit(
		&root,
		transaction.Transaction_ID(1 + sample),
		transaction.Undo_Unit_ID(1 + sample),
		transaction.Edit_Proposal {
			origin = transaction.Origin{kind = .External_Proposal, descriptor = "benchmark"},
			command = "benchmark-workspace-edit",
			snapshots = snapshots,
			edits = edits,
		},
		transaction.Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
		limits,
	)
	prepare_elapsed := time.tick_since(prepare_started)
	if !admitted {
		fmt.eprintf("phase=proposal-admit participants=%d failure=%v actual=%d limit=%d\n", participant_count, admission_failure.code, admission_failure.actual, admission_failure.limit)
		if transaction.multibuffer_transaction_is_valid(&root) {
			transaction.multibuffer_close(&root)
		}
		close_buffers(buffers)
		mem.tracking_allocator_destroy(&tracking)
		return 0, 0, 0, 0, false
	}

	publication_started := time.tick_now()
	result, committed, commit_failure := transaction.multibuffer_commit(&root)
	publication_elapsed := time.tick_since(publication_started)
	if !committed || len(result.buffers) != participant_count {
		fmt.eprintf("phase=commit participants=%d failure=%v results=%d\n", participant_count, commit_failure.code, len(result.buffers))
		transaction.multibuffer_close(&root)
		close_buffers(buffers)
		mem.tracking_allocator_destroy(&tracking)
		return 0, 0, 0, 0, false
	}
	transaction_peak_bytes = tracking.peak_memory_allocated - base_bytes
	transaction.multibuffer_close(&root)
	close_buffers(buffers)
	if tracking.current_memory_allocated != 0 {
		fmt.eprintf("phase=cleanup participants=%d retained_bytes=%d\n", participant_count, tracking.current_memory_allocated)
		mem.tracking_allocator_destroy(&tracking)
		return 0, 0, 0, 0, false
	}
	mem.tracking_allocator_destroy(&tracking)
	return time.duration_nanoseconds(prepare_elapsed),
	       time.duration_nanoseconds(publication_elapsed),
	       base_bytes,
	       transaction_peak_bytes,
	       true
}

close_buffers :: proc(buffers: []editor.Buffer) {
	for &buffer in buffers {
		if buffer.state != nil {
			editor.buffer_close(&buffer)
		}
	}
}
