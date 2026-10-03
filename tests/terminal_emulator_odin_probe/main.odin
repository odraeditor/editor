// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package terminal_emulator_odin_probe

import terminal_emulator "../../src/terminal_emulator"
import "core:fmt"
import "core:strings"

expect :: proc(condition: bool, message: string) {
	if !condition {
		panic(message)
	}
}

main :: proc() {
	zero_ref: terminal_emulator.Ref
	expect(
		terminal_emulator.close(zero_ref) == .Stale_Handle,
		"zero reference was not rejected",
	)

	options := terminal_emulator.DEFAULT_OPTIONS
	options.allocation_fail_after = 1
	fault_ref, fault_result := terminal_emulator.open(options)
	expect(fault_result == .Allocation_Failed, "allocation fault was not contained")
	expect(fault_ref == terminal_emulator.Ref{}, "failed open returned a live reference")

	ref, result := terminal_emulator.open()
	expect(result == .OK, "terminal open failed")
	expect(ref.slot != 0 && ref.generation != 0, "terminal reference is invalid")

	text := transmute([]u8)(string("alpha\r\nbeta\a\x1b[6n"))
	expect(terminal_emulator.write(ref, text) == .OK, "terminal write failed")
	expect(
		terminal_emulator.resize(ref, 100, 30, 9, 18) == .OK,
		"terminal resize failed",
	)
	state, render_result := terminal_emulator.render(ref)
	expect(render_result == .OK, "render projection failed")
	expect(state.columns == 100 && state.rows == 30, "render geometry mismatch")
	projected_rows := make([]terminal_emulator.Projected_Row, 30)
	projected_cells := make([]terminal_emulator.Projected_Cell, 3_000)
	defer delete(projected_rows)
	defer delete(projected_cells)
	projection, projection_result := terminal_emulator.project(
		ref,
		projected_rows,
		projected_cells,
	)
	expect(projection_result == .OK, "render projection failed")
	expect(
		projection.damage == .Full && projection.columns == 100 && projection.rows == 30,
		"full render projection mismatch",
	)
	expect(projection.damaged_rows == 30 && projection.damaged_cells == 3_000, "full damage mismatch")
	projection, projection_result = terminal_emulator.project(
		ref,
		projected_rows,
		projected_cells,
	)
	expect(projection_result == .OK && projection.damage == .Clean, "stable revision was dirty")
	text_request := terminal_emulator.Text_Request {
		scope = .Screen,
		unwrap = true,
		trim = true,
	}
	empty: [0]u8
	formatted_size, format_result := terminal_emulator.format_text(ref, text_request, empty[:])
	expect(
		format_result == .Buffer_Too_Small && formatted_size > 0,
		"screen text size query failed",
	)
	formatted := make([]u8, formatted_size)
	defer delete(formatted)
	formatted_bytes: int
	formatted_bytes, format_result = terminal_emulator.format_text(ref, text_request, formatted)
	expect(
		format_result == .OK && strings.contains(string(formatted[:formatted_bytes]), "alpha"),
		"screen text copy failed",
	)
	prefix: [4]u8
	prefix_bytes, required_bytes, prefix_result := terminal_emulator.format_text_bounded(
		ref, text_request, prefix[:],
	)
	expect(
		prefix_result == .OK && prefix_bytes == len(prefix) &&
		required_bytes == formatted_size && string(prefix[:]) == "alph",
		"bounded screen text copy failed",
	)
	history_line := transmute([]u8)(string("history\r\n"))
	for _ in 0 ..< 40 do expect(terminal_emulator.write(ref, history_line) == .OK, "history write failed")
	scroll_state, scroll_result := terminal_emulator.scroll_state(ref)
	expect(
		scroll_result == .OK && scroll_state.scrollback_rows > 0 &&
		scroll_state.scrollback_max_bytes == terminal_emulator.DEFAULT_OPTIONS.scrollback_max_bytes,
		"scrollback state mismatch",
	)
	expect(terminal_emulator.scroll(ref, .Top) == .OK, "scroll to top failed")
	scroll_state, scroll_result = terminal_emulator.scroll_state(ref)
	expect(scroll_result == .OK && !scroll_state.viewport_active, "viewport did not suspend follow")
	expect(terminal_emulator.scroll(ref, .Bottom) == .OK, "scroll to bottom failed")
	scroll_state, scroll_result = terminal_emulator.scroll_state(ref)
	expect(scroll_result == .OK && scroll_state.viewport_active, "viewport did not resume follow")
	_, _, compression_result := terminal_emulator.compress(ref)
	expect(compression_result == .OK, "incremental compression failed")

	key_output: [32]u8
	written, key_result := terminal_emulator.encode_key(
		ref,
		.Character,
		.Press,
		bit_set[terminal_emulator.Modifier; u32]{},
		transmute([]u8)(string("x")),
		key_output[:],
	)
	expect(key_result == .OK && written == 1 && key_output[0] == 'x', "key encoding failed")

	selection_output: [4096]u8
	selection_bytes, selection_result := terminal_emulator.select_all(ref, selection_output[:])
	expect(selection_result == .OK && selection_bytes > 0, "selection copy failed")

	snapshot_output: [16 * 1024]u8
	snapshot_bytes, snapshot_result := terminal_emulator.snapshot(ref, snapshot_output[:])
	expect(snapshot_result == .OK && snapshot_bytes > 0, "snapshot copy failed")

	effect_counts, effect_result := terminal_emulator.effects(ref)
	expect(effect_result == .OK, "effect inspection failed")
	expect(effect_counts.bell_count == 1, "bell effect was not captured")
	expect(effect_counts.writeback_count > 0, "writeback effect was not captured")
	expect(effect_counts.writeback_pending_bytes > 0, "writeback bytes were not retained")
	writeback: [64]u8
	writeback_bytes, writeback_pending, writeback_result := terminal_emulator.writeback_copy(
		ref,
		writeback[:],
	)
	expect(
		writeback_result == .OK && writeback_bytes > 0 &&
		writeback_bytes == writeback_pending && writeback[0] == 0x1b,
		"writeback copy failed",
	)
	expect(
		terminal_emulator.writeback_consume(ref, writeback_bytes) == .OK,
		"writeback consume failed",
	)

	features := []terminal_emulator.Feature {
		terminal_emulator.Feature.Key_Encoding,
		terminal_emulator.Feature.Mouse_Encoding,
		terminal_emulator.Feature.Selection,
		terminal_emulator.Feature.Snapshot,
		terminal_emulator.Feature.Kitty_Graphics,
	}
	for feature in features {
		supported, feature_result := terminal_emulator.supports(feature)
		expect(feature_result == .OK && supported, "required feature unavailable")
	}
	simd, simd_result := terminal_emulator.supports(.SIMD)
	expect(simd_result == .OK && !simd, "SIMD build policy mismatch")

	stats, stats_result := terminal_emulator.stats(ref)
	expect(stats_result == .OK && stats.live && stats.live_bytes > 0, "live stats mismatch")
	expect(terminal_emulator.close(ref) == .OK, "terminal close failed")
	expect(terminal_emulator.close(ref) == .Stale_Handle, "repeated close was accepted")
	stats, stats_result = terminal_emulator.stats(ref)
	expect(stats_result == .OK, "closed stats unavailable")
	expect(!stats.live && stats.live_bytes == 0, "closed terminal retained memory")
	expect(stats.allocations == stats.frees, "foreign allocations leaked")

	fmt.println("terminal_emulator_odin_probe=passed")
}
