// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../../src/editor"
import "../../src/language"
import "core:fmt"
import "core:os"
import "core:time"

main :: proc() {
	text := make([]u8, 1 * 1_024 * 1_024)
	defer delete(text)
	pattern := "alpha beta gamma_delta\n"
	for offset := 0; offset < len(text); offset += len(pattern) {
		copy(text[offset:], pattern)
	}
	buffer: editor.Buffer
	ready, _ := editor.buffer_init(&buffer, 1, string(text), {
		persistent = context.allocator, temporary = context.temp_allocator})
	if !ready do os.exit(1)
	defer editor.buffer_close(&buffer)
	snapshot: editor.Buffer_Snapshot
	opened, _ := editor.buffer_snapshot_open(&buffer, &snapshot)
	if !opened do os.exit(1)
	defer editor.buffer_snapshot_close(&snapshot)
	limits := language.DEFAULT_SYMBOL_LIMITS
	limits.symbols = 65_536
	started := time.tick_now()
	index, indexed, failure := language.generic_symbol_index(
		&snapshot, 0, false, 1, 1, limits, context.allocator)
	if !indexed {
		fmt.eprintf("study=symbol-navigation failure=%v\n", failure.code)
		os.exit(1)
	}
	defer language.symbol_index_close(&index)
	view, viewed, _ := language.symbol_index_view(&index)
	elapsed := time.duration_nanoseconds(time.tick_since(started))
	fmt.printf("study=symbol-navigation bytes=%d symbols=%d retained=%d temporary=%d work=%d elapsed_ns=%d complete=%v\n",
		len(text), view.symbols, view.descriptor.usage.retained_bytes,
		view.descriptor.usage.temporary_bytes, view.descriptor.usage.work_items,
		elapsed, view.descriptor.completeness)
	if !viewed || view.symbols == 0 || view.descriptor.usage.temporary_bytes > limits.temporary_bytes do os.exit(1)
}
