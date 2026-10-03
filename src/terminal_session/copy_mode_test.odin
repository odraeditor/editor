// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package terminal_session

import "core:strings"
import "core:testing"
import "../terminal_emulator"

/* Verifies bounded movement, search, repeated selection copy, and layered cancellation. */
@(test)
copy_mode_navigates_without_terminal_input :: proc(t: ^testing.T) {
	registry: Registry
	initialized, _ := registry_init(&registry)
	testing.expect(t, initialized)
	if !initialized do return
	defer if registry.state != nil {
		_, _ = registry_close(&registry)
	}
	request := test_open_request("copy-mode", arguments = []string{"-c", "sleep 30"})
	request.emulator.columns = 10
	request.emulator.rows = 3
	request.start.columns = 10
	request.start.rows = 3
	record, opened, open_failure := registry_open(&registry, request)
	testing.expectf(t, opened, "terminal open failed with %v", open_failure.code)
	if !opened do return
	_ = terminal_emulator.write(
		record.emulator,
		transmute([]u8)(string("alpha\r\nbeta\r\ngamma\r\ndelta\r\nepsilon")),
	)
	session, resolved := registry_resolve(registry_state(&registry), record.ref)
	testing.expect(t, resolved)
	if !resolved do return
	input_bytes_before := session.process_input_bytes

	entered, enter_ok, enter_failure := registry_copy_mode_enter(&registry, record.ref)
	testing.expectf(t, enter_ok, "copy-mode entry failed with %v", enter_failure.code)
	if !enter_ok do return
	testing.expect(t, entered.state.active)
	testing.expect(t, entered.state.follow_tail_on_entry)

	start, start_ok, start_failure := registry_copy_mode_move(
		&registry, record.ref, entered.state, .Retained_Start,
	)
	testing.expectf(t, start_ok, "retained-start movement failed with %v", start_failure.code)
	if !start_ok do return
	testing.expect_value(t, start.state.point_row, u64(0))
	testing.expect_value(t, start.state.point_column, u32(0))

	marked, mark_ok, mark_failure := registry_copy_mode_set_mark(
		&registry, record.ref, start.state,
	)
	testing.expectf(t, mark_ok, "copy-mode mark failed with %v", mark_failure.code)
	if !mark_ok do return
	moved, move_ok, move_failure := registry_copy_mode_move(
		&registry, record.ref, marked.state, .Next_Column, 4,
	)
	testing.expectf(t, move_ok, "copy-mode movement failed with %v", move_failure.code)
	if !move_ok do return

	selection: [64]u8
	first_copy, first_ok, first_failure := registry_copy_mode_copy_selection(
		&registry, record.ref, moved.state, selection[:],
	)
	testing.expectf(t, first_ok, "selection copy failed with %v", first_failure.code)
	if first_ok {
		testing.expect_value(t, string(selection[:int(first_copy.copied_bytes)]), "alpha")
	}
	second_copy, second_ok, second_failure := registry_copy_mode_copy_selection(
		&registry, record.ref, moved.state, selection[:],
	)
	testing.expectf(t, second_ok, "repeated selection copy failed with %v", second_failure.code)
	if second_ok do testing.expect_value(t, second_copy.copied_bytes, first_copy.copied_bytes)

	first_cancel, cancel_ok, cancel_failure := registry_copy_mode_cancel(
		&registry, record.ref, moved.state,
	)
	testing.expectf(t, cancel_ok, "selection cancellation failed with %v", cancel_failure.code)
	if !cancel_ok do return
	testing.expect(t, first_cancel.selection_deactivated)
	testing.expect(t, first_cancel.state.active)
	testing.expect(t, !first_cancel.state.selection_active)
	second_cancel, exit_ok, exit_failure := registry_copy_mode_cancel(
		&registry, record.ref, first_cancel.state,
	)
	testing.expectf(t, exit_ok, "copy-mode cancellation failed with %v", exit_failure.code)
	testing.expect(t, second_cancel.completed)
	testing.expect(t, second_cancel.resume_follow_tail)
	testing.expect_value(t, session.process_input_bytes, input_bytes_before)
}

@(test)
/* Verifies pointer cells reuse retained copy-mode point, mark, and region state. */
copy_mode_pointer_selects_retained_text :: proc(t: ^testing.T) {
	registry: Registry
	initialized, _ := registry_init(&registry)
	testing.expect(t, initialized)
	if !initialized do return
	defer if registry.state != nil {
		_, _ = registry_close(&registry)
	}
	request := test_open_request("copy-pointer", arguments = []string{"-c", "sleep 30"})
	request.emulator.columns = 10
	request.emulator.rows = 3
	request.start.columns = 10
	request.start.rows = 3
	record, opened, open_failure := registry_open(&registry, request)
	testing.expectf(t, opened, "terminal open failed with %v", open_failure.code)
	if !opened do return
	_ = terminal_emulator.write(
		record.emulator,
		transmute([]u8)(string("alpha\r\nbeta")),
	)
	session, resolved := registry_resolve(registry_state(&registry), record.ref)
	testing.expect(t, resolved)
	if !resolved do return
	input_bytes_before := session.process_input_bytes
	entered, enter_ok, enter_failure := registry_copy_mode_enter(&registry, record.ref)
	testing.expectf(t, enter_ok, "copy-mode entry failed with %v", enter_failure.code)
	if !enter_ok do return

	begin, begin_ok, begin_failure := registry_copy_mode_select_pointer(
		&registry,
		record.ref,
		entered.state,
		{action = .Begin, viewport_row = 0, column = 0},
	)
	testing.expectf(t, begin_ok, "pointer begin failed with %v", begin_failure.code)
	if !begin_ok do return
	testing.expect(t, begin.state.mark_present && !begin.state.selection_active)
	testing.expect_value(t, begin.state.mark_row, u64(0))
	testing.expect_value(t, begin.state.mark_column, u32(0))

	forward, forward_ok, forward_failure := registry_copy_mode_select_pointer(
		&registry,
		record.ref,
		begin.state,
		{action = .Extend, viewport_row = 0, column = 4},
	)
	testing.expectf(t, forward_ok, "pointer extend failed with %v", forward_failure.code)
	if !forward_ok do return
	testing.expect(t, forward.state.selection_active)
	selection: [64]u8
	forward_copy, copied, copy_failure := registry_copy_mode_copy_selection(
		&registry, record.ref, forward.state, selection[:],
	)
	testing.expectf(t, copied, "forward pointer copy failed with %v", copy_failure.code)
	if copied {
		testing.expect_value(t, string(selection[:int(forward_copy.copied_bytes)]), "alpha")
	}

	reverse_begin, reverse_begin_ok, _ := registry_copy_mode_select_pointer(
		&registry,
		record.ref,
		forward.state,
		{action = .Begin, viewport_row = 1, column = 3},
	)
	reverse, reverse_ok, reverse_failure := registry_copy_mode_select_pointer(
		&registry,
		record.ref,
		reverse_begin.state,
		{action = .Extend, viewport_row = 1, column = 1},
	)
	testing.expect(t, reverse_begin_ok)
	testing.expectf(t, reverse_ok, "reverse pointer extend failed with %v", reverse_failure.code)
	if reverse_ok {
		reverse_copy, reverse_copied, reverse_copy_failure := registry_copy_mode_copy_selection(
			&registry, record.ref, reverse.state, selection[:],
		)
		testing.expectf(
			t, reverse_copied, "reverse pointer copy failed with %v", reverse_copy_failure.code,
		)
		if reverse_copied {
			testing.expect_value(t, string(selection[:int(reverse_copy.copied_bytes)]), "eta")
		}
	}

	clamped, clamped_ok, clamped_failure := registry_copy_mode_select_pointer(
		&registry,
		record.ref,
		reverse.state,
		{action = .Begin, viewport_row = min(i64), column = min(i64)},
	)
	testing.expectf(t, clamped_ok, "pointer clamp failed with %v", clamped_failure.code)
	if clamped_ok {
		testing.expect_value(t, clamped.state.point_row, u64(0))
		testing.expect_value(t, clamped.state.point_column, u32(0))
		zero, zero_ok, _ := registry_copy_mode_select_pointer(
			&registry,
			record.ref,
			clamped.state,
			{action = .Extend, viewport_row = min(i64), column = min(i64)},
		)
		testing.expect(t, zero_ok && !zero.state.selection_active)
	}
	_, invalid_ok, invalid_failure := registry_copy_mode_select_pointer(
		&registry, record.ref, entered.state, {action = .Extend},
	)
	testing.expect(t, !invalid_ok)
	testing.expect_value(t, invalid_failure.code, Failure_Code.Invalid_Argument)
	testing.expect_value(t, session.process_input_bytes, input_bytes_before)
}

/* Verifies search wrapping and stable local viewport reconciliation during output. */
@(test)
copy_mode_search_survives_continuing_output :: proc(t: ^testing.T) {
	registry: Registry
	initialized, _ := registry_init(&registry)
	testing.expect(t, initialized)
	if !initialized do return
	defer if registry.state != nil {
		_, _ = registry_close(&registry)
	}
	request := test_open_request("copy-search", arguments = []string{"-c", "sleep 30"})
	request.emulator.columns = 10
	request.emulator.rows = 3
	request.start.columns = 10
	request.start.rows = 3
	record, opened, open_failure := registry_open(&registry, request)
	testing.expectf(t, opened, "terminal open failed with %v", open_failure.code)
	if !opened do return
	_ = terminal_emulator.write(
		record.emulator,
		transmute([]u8)(string("alpha\r\nbeta\r\ngamma\r\ndelta\r\nepsilon")),
	)
	entered, enter_ok, enter_failure := registry_copy_mode_enter(&registry, record.ref)
	testing.expectf(t, enter_ok, "copy-mode entry failed with %v", enter_failure.code)
	if !enter_ok do return

	scratch: [4 * 1_024]u8
	forward, searched, search_failure := registry_copy_mode_search(
		&registry, record.ref, entered.state, "alpha", .Forward, scratch[:],
	)
	testing.expectf(t, searched, "forward search failed with %v", search_failure.code)
	if !searched do return
	testing.expect(t, forward.found)
	testing.expect(t, forward.wrapped)
	testing.expect_value(t, forward.state.point_row, u64(0))
	testing.expect_value(t, forward.state.point_column, u32(0))
	testing.expect_value(t, forward.state.viewport_top_row, u64(0))

	_ = terminal_emulator.write(record.emulator, transmute([]u8)(string("\r\nzeta\r\neta")))
	reconciled, reconcile_ok, reconcile_failure := registry_copy_mode_reconcile(
		&registry, record.ref, forward.state,
	)
	testing.expectf(
		t, reconcile_ok, "output reconciliation failed with %v", reconcile_failure.code,
	)
	if !reconcile_ok do return
	testing.expect_value(t, reconciled.state.point_row, u64(0))
	testing.expect_value(t, reconciled.state.viewport_top_row, u64(0))

	backward, backward_ok, backward_failure := registry_copy_mode_search(
		&registry, record.ref, reconciled.state, "epsilon", .Backward, scratch[:],
	)
	testing.expectf(t, backward_ok, "backward search failed with %v", backward_failure.code)
	if backward_ok {
		testing.expect(t, backward.found)
		testing.expect(t, backward.wrapped)
	}

	done, done_ok, done_failure := registry_copy_mode_done(
		&registry, record.ref, reconciled.state,
	)
	testing.expectf(t, done_ok, "copy-mode completion failed with %v", done_failure.code)
	testing.expect(t, done.completed)
	testing.expect(t, done.resume_follow_tail)
	reentered, reenter_ok, reenter_failure := registry_copy_mode_enter(&registry, record.ref)
	testing.expectf(t, reenter_ok, "copy-mode reentry failed with %v", reenter_failure.code)
	if reenter_ok {
		testing.expect(t, reentered.state.active)
		testing.expect(t, reentered.state.point_row >= reconciled.state.point_row)
	}
	testing.expect(t, strings.contains(string(scratch[:int(backward.searched_bytes)]), "eta"))
}

/* Verifies eviction and reflow clamp stale copy positions to retained bounds. */
@(test)
copy_mode_clamps_stale_retained_positions :: proc(t: ^testing.T) {
	registry: Registry
	initialized, _ := registry_init(&registry)
	testing.expect(t, initialized)
	if !initialized do return
	defer if registry.state != nil {
		_, _ = registry_close(&registry)
	}
	request := test_open_request("copy-eviction", arguments = []string{"-c", "sleep 30"})
	request.emulator.columns = 10
	request.emulator.rows = 3
	request.start.columns = 10
	request.start.rows = 3
	request.limits.scrollback_bytes = 1
	request.limits.scrollback_rows = 5
	record, opened, open_failure := registry_open(&registry, request)
	testing.expectf(t, opened, "terminal open failed with %v", open_failure.code)
	if !opened do return
	_ = terminal_emulator.write(record.emulator, transmute([]u8)(string("old-marker\r\n")))
	entered, enter_ok, enter_failure := registry_copy_mode_enter(&registry, record.ref)
	testing.expectf(t, enter_ok, "copy-mode entry failed with %v", enter_failure.code)
	if !enter_ok do return
	stale := entered.state
	stale.point_row = max(u64)
	stale.point_column = max(u32)
	stale.mark_present = true
	stale.selection_active = true
	stale.mark_row = max(u64)
	stale.mark_column = max(u32)
	filler := transmute([]u8)(string("012345678901234567890123456789\r\n"))
	for _ in 0 ..< 5_000 do _ = terminal_emulator.write(record.emulator, filler)
	resized, resize_failure := registry_resize(&registry, record.ref, 5, 4, 8, 16)
	testing.expectf(t, resized, "copy-mode reflow failed with %v", resize_failure.code)
	reconciled, reconcile_ok, reconcile_failure := registry_copy_mode_reconcile(
		&registry, record.ref, stale,
	)
	testing.expectf(
		t, reconcile_ok, "retention reconciliation failed with %v", reconcile_failure.code,
	)
	if !reconcile_ok do return
	scrollback, inspected, inspect_failure := registry_scrollback(&registry, record.ref)
	testing.expectf(t, inspected, "retention inspection failed with %v", inspect_failure.code)
	if inspected {
		testing.expect(t, reconciled.state.point_row < max(scrollback.total_rows, u64(1)))
		testing.expect(t, reconciled.state.mark_row < max(scrollback.total_rows, u64(1)))
	}
	testing.expect(t, reconciled.state.point_column < u32(5))
	testing.expect(t, reconciled.state.mark_column < u32(5))
}
