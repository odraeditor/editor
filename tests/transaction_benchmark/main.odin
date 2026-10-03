// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../../src/editor"
import "../../src/transaction"
import "core:fmt"
import "core:os"
import "core:time"

MEBIBYTE :: u64(1024 * 1024)
ORDINARY_SPLICES :: 1
DEMANDING_SPLICES :: 100_000
STRESS_SPLICES :: 1_000_000
ORDINARY_PUBLICATION_GATE_NS :: i64(1_000_000)
DEMANDING_PUBLICATION_GATE_NS :: i64(4_000_000)
STRESS_PUBLICATION_GATE_NS :: i64(16_000_000)

main :: proc() {
	ordinary_ok := run_profile(
		"ordinary",
		ORDINARY_SPLICES,
		"x",
		16 * MEBIBYTE,
		ORDINARY_PUBLICATION_GATE_NS,
	)
	demanding_ok := run_profile(
		"demanding",
		DEMANDING_SPLICES,
		"x",
		32 * MEBIBYTE,
		DEMANDING_PUBLICATION_GATE_NS,
	)
	stress_ok := run_profile(
		"stress",
		STRESS_SPLICES,
		"",
		128 * MEBIBYTE,
		STRESS_PUBLICATION_GATE_NS,
	)
	if !ordinary_ok || !demanding_ok || !stress_ok {
		os.exit(1)
	}
}

run_profile :: proc(
	name: string,
	splice_count: int,
	replacement: string,
	metadata_bytes: u64,
	publication_gate_ns: i64,
) -> bool {
	buffer: editor.Buffer
	initialized, init_failure := editor.buffer_init(
		&buffer,
		editor.Buffer_ID(splice_count + 1),
		"",
		editor.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	if !initialized {
		fmt.eprintf("profile=%s phase=buffer-init failure=%v\n", name, init_failure.code)
		return false
	}

	limits := transaction.DEFAULT_LIMITS
	limits.splices = u64(splice_count)
	limits.metadata_bytes = metadata_bytes
	root: transaction.Transaction
	started, begin_failure := transaction.transaction_begin(
		&root,
		transaction.Transaction_ID(splice_count + 1),
		transaction.Undo_Unit_ID(splice_count + 1),
		&buffer,
		transaction.Origin{kind = .Built_In, descriptor = "benchmark"},
		"benchmark-no-op-batch",
		transaction.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
		limits,
	)
	if !started {
		fmt.eprintf("profile=%s phase=begin failure=%v\n", name, begin_failure.code)
		editor.buffer_close(&buffer)
		return false
	}
	position, _, _ := editor.buffer_position(&buffer, editor.Byte_Offset(0))
	batch := make([]transaction.Base_Splice, splice_count)
	defer delete(batch)
	for &splice in batch {
		splice.start = position
		splice.end = position
		splice.replacement = replacement
	}

	prepare_started := time.tick_now()
	applied, apply_failure := transaction.transaction_apply_batch(&root, batch)
	if !applied {
		fmt.eprintf("profile=%s phase=apply failure=%v\n", name, apply_failure.code)
		transaction.transaction_close(&root)
		editor.buffer_close(&buffer)
		return false
	}
	validated, validation_failure := transaction.transaction_validate(&root)
	prepare_elapsed := time.tick_since(prepare_started)
	if !validated {
		fmt.eprintf("profile=%s phase=validate failure=%v\n", name, validation_failure.code)
		transaction.transaction_close(&root)
		editor.buffer_close(&buffer)
		return false
	}

	publication_started := time.tick_now()
	result, committed, commit_failure := transaction.transaction_commit(&root)
	publication_elapsed := time.tick_since(publication_started)
	if !committed {
		fmt.eprintf("profile=%s phase=commit failure=%v\n", name, commit_failure.code)
		transaction.transaction_close(&root)
		editor.buffer_close(&buffer)
		return false
	}
	prepare_ns := time.duration_nanoseconds(prepare_elapsed)
	publication_ns := time.duration_nanoseconds(publication_elapsed)
	within_gate := publication_ns <= publication_gate_ns
	fmt.printf(
		"benchmark=single-buffer-transaction profile=%s splices=%d replacement_bytes=%d prepare_ns=%d publication_ns=%d publication_gate_ns=%d within_gate=%v metadata_bytes=%d checkpoints=%d\n",
		name,
		splice_count,
		len(replacement),
		prepare_ns,
		publication_ns,
		publication_gate_ns,
		within_gate,
		result.usage.metadata_bytes,
		result.usage.checkpoints,
	)
	transaction.transaction_close(&root)
	closed, close_failure := editor.buffer_close(&buffer)
	if !closed {
		fmt.eprintf("profile=%s phase=buffer-close failure=%v\n", name, close_failure.code)
		return false
	}
	return within_gate
}
