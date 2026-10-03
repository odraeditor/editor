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

FUZZ_SEED :: u64(0x6f6472615f747834)
FUZZ_CASES :: 256

main :: proc() {
	state := FUZZ_SEED
	for case_index in 0 ..< FUZZ_CASES {
		if !run_case(&state, case_index) {
			fmt.eprintf("fuzz=multibuffer-proposal seed=%d failed_case=%d\n", FUZZ_SEED, case_index)
			os.exit(1)
		}
	}
	fmt.printf("fuzz=multibuffer-proposal seed=%d cases=%d status=pass\n", FUZZ_SEED, FUZZ_CASES)
}

run_case :: proc(random: ^u64, case_index: int) -> bool {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	first: editor.Buffer
	second: editor.Buffer
	allocator := mem.tracking_allocator(&tracking)
	first_ok, _ := editor.buffer_init(
		&first,
		editor.Buffer_ID(1 + case_index * 2),
		"abcdefgh",
		editor.Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
	)
	second_ok, _ := editor.buffer_init(
		&second,
		editor.Buffer_ID(2 + case_index * 2),
		"ABCDEFGH",
		editor.Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
	)
	if !first_ok || !second_ok {
		if second.state != nil {
			editor.buffer_close(&second)
		}
		if first.state != nil {
			editor.buffer_close(&first)
		}
		mem.tracking_allocator_destroy(&tracking)
		return false
	}

	first_start := fuzz_next(random) % 8
	first_end := first_start + fuzz_next(random) % (9 - first_start)
	second_start := fuzz_next(random) % 8
	second_end := second_start + fuzz_next(random) % (9 - second_start)
	replacements := [5]string{"", "x", "yz", "λ", "🙂"}
	first_replacement := replacements[fuzz_next(random) % u64(len(replacements))]
	second_replacement := replacements[fuzz_next(random) % u64(len(replacements))]
	invalid := fuzz_next(random) % 4 == 0
	first_start_position, _, _ := editor.buffer_position(&first, editor.Byte_Offset(first_start))
	first_end_position, _, _ := editor.buffer_position(&first, editor.Byte_Offset(first_end))
	second_start_position, _, _ := editor.buffer_position(&second, editor.Byte_Offset(second_start))
	second_end_position, _, _ := editor.buffer_position(&second, editor.Byte_Offset(second_end))
	if invalid {
		second_start_position, _, _ = editor.buffer_position(&second, editor.Byte_Offset(7))
		second_end_position, _, _ = editor.buffer_position(&second, editor.Byte_Offset(1))
	}
	first_batch := [1]transaction.Base_Splice{{
		start = first_start_position,
		end = first_end_position,
		replacement = first_replacement,
	}}
	second_batch := [1]transaction.Base_Splice{{
		start = second_start_position,
		end = second_end_position,
		replacement = second_replacement,
	}}
	origins := [4]transaction.Origin_Kind{.Built_In, .Racket, .Language_Tool, .External_Proposal}
	origin := origins[fuzz_next(random) % u64(len(origins))]
	root: transaction.Multibuffer_Transaction
	admitted, failure := transaction.proposal_admit(
		&root,
		transaction.Transaction_ID(1 + case_index),
		transaction.Undo_Unit_ID(1 + case_index),
		transaction.Edit_Proposal {
			origin = transaction.Origin{kind = origin, descriptor = "fuzz"},
			command = "generated-edit",
			snapshots = []transaction.Proposal_Snapshot {
				{buffer = &second, buffer_id = editor.Buffer_ID(2 + case_index * 2), base_revision = editor.Revision(0)},
				{buffer = &first, buffer_id = editor.Buffer_ID(1 + case_index * 2), base_revision = editor.Revision(0)},
			},
			edits = []transaction.Proposal_Edit {
				{buffer_id = editor.Buffer_ID(1 + case_index * 2), base_revision = editor.Revision(0), batch = first_batch[:]},
				{buffer_id = editor.Buffer_ID(2 + case_index * 2), base_revision = editor.Revision(0), batch = second_batch[:]},
			},
		},
		transaction.Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
	)
	case_ok := true
	if invalid {
		case_ok = !admitted && failure.code == .Reversed_Range
		first_stats, _, _ := editor.buffer_stats(&first)
		second_stats, _, _ := editor.buffer_stats(&second)
		case_ok = case_ok && first_stats.revision == 0 && second_stats.revision == 0
	} else {
		if !admitted {
			case_ok = false
		} else {
			_, committed, _ := transaction.multibuffer_commit(&root)
			case_ok = committed &&
			          buffer_equals(&first, replace_model("abcdefgh", first_start, first_end, first_replacement)) &&
			          buffer_equals(&second, replace_model("ABCDEFGH", second_start, second_end, second_replacement))
		}
	}
	if transaction.multibuffer_transaction_is_valid(&root) {
		transaction.multibuffer_close(&root)
	}
	editor.buffer_close(&second)
	editor.buffer_close(&first)
	case_ok = case_ok && tracking.current_memory_allocated == 0
	mem.tracking_allocator_destroy(&tracking)
	return case_ok
}

fuzz_next :: proc(state: ^u64) -> u64 {
	value := state^
	value ~= value << 13
	value ~= value >> 7
	value ~= value << 17
	state^ = value
	return value
}

replace_model :: proc(base: string, start, end: u64, replacement: string) -> string {
	result := make([]byte, len(base) - int(end - start) + len(replacement))
	offset := 0
	offset += copy(result[offset:], base[:int(start)])
	offset += copy(result[offset:], replacement)
	offset += copy(result[offset:], base[int(end):])
	assert(offset == len(result))
	return string(result)
}

buffer_equals :: proc(buffer: ^editor.Buffer, expected: string) -> bool {
	defer delete(expected)
	stats, stats_ok, _ := editor.buffer_stats(buffer)
	if !stats_ok || stats.text_bytes != u64(len(expected)) || stats.revision != editor.Revision(1) {
		return false
	}
	observed := make([]byte, len(expected))
	defer delete(observed)
	_, inspected, _ := editor.buffer_inspect(
		buffer,
		editor.Byte_Offset(0),
		editor.Byte_Offset(len(expected)),
		observed,
	)
	return inspected && string(observed) == expected
}
