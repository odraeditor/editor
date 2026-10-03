// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package terminal_session

import "core:strings"
import "core:testing"
import "core:unicode/utf8"
import "../terminal_emulator"

/* Verifies follow suspension, absolute scrolling, reflow, and compression turns. */
@(test)
scrollback_tracks_viewport_and_incremental_compression :: proc(t: ^testing.T) {
	registry: Registry
	initialized, _ := registry_init(&registry)
	testing.expect(t, initialized)
	if !initialized do return
	defer if registry.state != nil {
		_, _ = registry_close(&registry)
	}
	request := test_open_request("viewport", arguments = []string{"-c", "sleep 30"})
	request.emulator.columns = 10
	request.emulator.rows = 3
	request.start.columns = 10
	request.start.rows = 3
	record, opened, failure := registry_open(&registry, request)
	testing.expectf(
		t, opened, "terminal open failed with %v/%v", failure.code, failure.process_code,
	)
	if !opened do return

	content := transmute([]u8)(string("alpha\r\nbeta\r\ngamma\r\ndelta\r\nepsilon"))
	testing.expect_value(
		t, terminal_emulator.write(record.emulator, content), terminal_emulator.Result.OK,
	)
	scrollback, inspected, scroll_failure := registry_scrollback(&registry, record.ref)
	testing.expectf(t, inspected, "scrollback inspection failed with %v", scroll_failure.code)
	testing.expect(t, scrollback.scrollback_rows > 0)
	testing.expect(t, scrollback.following)
	testing.expect_value(t, scrollback.scrollback_max_bytes, DEFAULT_LIMITS.scrollback_bytes)
	testing.expect_value(t, scrollback.scrollback_max_rows, DEFAULT_LIMITS.scrollback_rows)
	testing.expect_value(t, scrollback.retained_start_row, u64(0))
	testing.expect_value(t, scrollback.retained_end_row, scrollback.total_rows)

	scrollback, inspected, scroll_failure = registry_scroll_viewport(
		&registry, record.ref, .Top,
	)
	testing.expectf(t, inspected, "scroll to top failed with %v", scroll_failure.code)
	testing.expect(t, !scrollback.following)
	testing.expect_value(t, scrollback.viewport_offset, u64(0))

	scrollback, inspected, scroll_failure = registry_scroll_viewport(
		&registry, record.ref, .Row, 1,
	)
	testing.expectf(t, inspected, "absolute scroll failed with %v", scroll_failure.code)
	testing.expect_value(t, scrollback.viewport_offset, u64(1))
	scrollback, inspected, scroll_failure = registry_scroll_viewport(
		&registry, record.ref, .Delta, -1,
	)
	testing.expectf(t, inspected, "delta scroll failed with %v", scroll_failure.code)
	testing.expect_value(t, scrollback.viewport_offset, u64(0))

	_ = terminal_emulator.write(record.emulator, transmute([]u8)(string("\r\nzeta")))
	scrollback, inspected, scroll_failure = registry_scrollback(&registry, record.ref)
	testing.expectf(t, inspected, "suspended viewport inspection failed with %v", scroll_failure.code)
	testing.expect(t, !scrollback.following)
	scrollback, inspected, scroll_failure = registry_scroll_viewport(
		&registry, record.ref, .Bottom,
	)
	testing.expectf(t, inspected, "scroll to bottom failed with %v", scroll_failure.code)
	testing.expect(t, scrollback.following)

	resized, resize_failure := registry_resize(&registry, record.ref, 5, 4, 8, 16)
	testing.expectf(t, resized, "reflow resize failed with %v", resize_failure.code)
	if resized {
		scrollback, inspected, scroll_failure = registry_scrollback(&registry, record.ref)
		testing.expectf(t, inspected, "reflow inspection failed with %v", scroll_failure.code)
		testing.expect_value(t, scrollback.viewport_rows, u64(4))
	}

	completed := false
	for _ in 0 ..< 1_024 {
		compression, compressed, compression_failure := registry_compress_scrollback(
			&registry, record.ref,
		)
		testing.expectf(t, compressed, "compression failed with %v", compression_failure.code)
		if !compressed do break
		if !compression.supported || !compression.pending {
			completed = true
			break
		}
	}
	testing.expect(t, completed)

	_, scrolled, invalid_failure := registry_scroll_viewport(
		&registry, record.ref, .Row, -1,
	)
	testing.expect(t, !scrolled)
	testing.expect_value(t, invalid_failure.code, Failure_Code.Invalid_Argument)
}

/* Verifies bounded visible, absolute-range, normalized, and evicted text copies. */
@(test)
scrollback_copies_bounded_text_and_reports_truncation :: proc(t: ^testing.T) {
	registry: Registry
	initialized, _ := registry_init(&registry)
	testing.expect(t, initialized)
	if !initialized do return
	defer if registry.state != nil {
		_, _ = registry_close(&registry)
	}
	request := test_open_request("text", arguments = []string{"-c", "sleep 30"})
	request.emulator.columns = 10
	request.emulator.rows = 3
	request.start.columns = 10
	request.start.rows = 3
	record, opened, failure := registry_open(&registry, request)
	testing.expectf(
		t, opened, "terminal open failed with %v/%v", failure.code, failure.process_code,
	)
	if !opened do return
	_ = terminal_emulator.write(
		record.emulator,
		transmute([]u8)(string("alpha\r\nbeta\r\ngamma\r\ndelta\r\nepsilon")),
	)

	text: [4 * 1_024]u8
	snapshot, copied, copy_failure := registry_copy_text(
		&registry,
		record.ref,
		Text_Request{scope = .Screen, normalized = true},
		text[:],
	)
	testing.expectf(t, copied, "screen copy failed with %v", copy_failure.code)
	testing.expect(t, !snapshot.truncated)
	testing.expect(t, snapshot.normalized)
	formatted := string(text[:int(snapshot.copied_bytes)])
	testing.expect(t, strings.contains(formatted, "alpha"))
	testing.expect(t, strings.contains(formatted, "epsilon"))

	_, _, _ = registry_scroll_viewport(&registry, record.ref, .Top)
	viewport: [128]u8
	visible, visible_copied, visible_failure := registry_copy_text(
		&registry,
		record.ref,
		Text_Request{scope = .Viewport},
		viewport[:],
	)
	testing.expectf(t, visible_copied, "viewport copy failed with %v", visible_failure.code)
	testing.expect(t, strings.contains(string(viewport[:int(visible.copied_bytes)]), "alpha"))

	range_output: [32]u8
	range_snapshot, range_copied, range_failure := registry_copy_text(
		&registry,
		record.ref,
		Text_Request {
			scope = .Screen_Range,
			range = Text_Range{end_column = 4},
		},
		range_output[:],
	)
	testing.expectf(t, range_copied, "absolute range copy failed with %v", range_failure.code)
	testing.expect_value(t, string(range_output[:int(range_snapshot.copied_bytes)]), "alpha")
	history_snapshot, history_copied, history_failure := registry_copy_text(
		&registry,
		record.ref,
		Text_Request {
			scope = .History_Range,
			range = Text_Range{end_column = 4},
		},
		range_output[:],
	)
	testing.expectf(t, history_copied, "history range copy failed with %v", history_failure.code)
	testing.expect_value(t, string(range_output[:int(history_snapshot.copied_bytes)]), "alpha")

	prefix: [4]u8
	truncated, prefix_copied, prefix_failure := registry_copy_text(
		&registry,
		record.ref,
		Text_Request{scope = .Screen, normalized = true},
		prefix[:],
	)
	testing.expectf(t, prefix_copied, "bounded prefix copy failed with %v", prefix_failure.code)
	testing.expect(t, truncated.truncated)
	testing.expect_value(t, truncated.copied_bytes, u64(len(prefix)))
	testing.expect(t, truncated.required_bytes > truncated.copied_bytes)
	testing.expect_value(t, string(prefix[:]), "alph")

	resized, resize_failure := registry_resize(&registry, record.ref, 5, 4, 8, 16)
	testing.expectf(t, resized, "text reflow failed with %v", resize_failure.code)
	if resized {
		reflowed, reflow_copied, reflow_failure := registry_copy_text(
			&registry,
			record.ref,
			Text_Request{scope = .Screen, normalized = true},
			text[:],
		)
		testing.expectf(t, reflow_copied, "reflowed text failed with %v", reflow_failure.code)
		testing.expect(
			t,
			strings.contains(string(text[:int(reflowed.copied_bytes)]), "epsilon"),
		)
	}

	_, invalid_copied, invalid_failure := registry_copy_text(
		&registry,
		record.ref,
		Text_Request {
			scope = .History_Range,
			range = Text_Range{start_row = 2, end_row = 1},
		},
		text[:],
	)
	testing.expect(t, !invalid_copied)
	testing.expect_value(t, invalid_failure.code, Failure_Code.Invalid_Argument)

	unicode_request := test_open_request("unicode-text", arguments = []string{"-c", "sleep 30"})
	unicode_record, unicode_opened, unicode_failure := registry_open(&registry, unicode_request)
	testing.expectf(t, unicode_opened, "unicode terminal failed with %v", unicode_failure.code)
	if unicode_opened {
		_ = terminal_emulator.write(unicode_record.emulator, transmute([]u8)(string("界")))
		unicode_prefix: [2]u8
		unicode_snapshot, unicode_copied, unicode_copy_failure := registry_copy_text(
			&registry,
			unicode_record.ref,
			Text_Request{scope = .Screen},
			unicode_prefix[:],
		)
		testing.expectf(t, unicode_copied, "unicode copy failed with %v", unicode_copy_failure.code)
		testing.expect(t, unicode_snapshot.truncated)
		testing.expect(t, utf8.valid_string(string(unicode_prefix[:int(unicode_snapshot.copied_bytes)])))
	}

	eviction_request := test_open_request("eviction", arguments = []string{"-c", "sleep 30"})
	eviction_request.emulator.columns = 10
	eviction_request.emulator.rows = 3
	eviction_request.start.columns = 10
	eviction_request.start.rows = 3
	eviction_request.limits.scrollback_bytes = 1
	eviction_request.limits.scrollback_rows = 5
	eviction_request.limits.copied_text_bytes = 64 * 1_024
	evicted_record, evicted_opened, evicted_failure := registry_open(&registry, eviction_request)
	testing.expectf(t, evicted_opened, "eviction terminal failed with %v", evicted_failure.code)
	if !evicted_opened do return
	_ = terminal_emulator.write(evicted_record.emulator, transmute([]u8)(string("old-marker\r\n")))
	filler := transmute([]u8)(string("012345678901234567890123456789\r\n"))
	for _ in 0 ..< 5_000 do _ = terminal_emulator.write(evicted_record.emulator, filler)
	_ = terminal_emulator.write(evicted_record.emulator, transmute([]u8)(string("new-marker")))
	eviction_text: [64 * 1_024]u8
	eviction_snapshot, eviction_copied, eviction_copy_failure := registry_copy_text(
		&registry,
		evicted_record.ref,
		Text_Request{scope = .Screen, normalized = true},
		eviction_text[:],
	)
	testing.expectf(t, eviction_copied, "eviction text failed with %v", eviction_copy_failure.code)
	evicted_text := string(eviction_text[:int(eviction_snapshot.copied_bytes)])
	testing.expect(t, !strings.contains(evicted_text, "old-marker"))
	tail: [128]u8
	tail_snapshot, tail_copied, tail_failure := registry_copy_text(
		&registry,
		evicted_record.ref,
		Text_Request{scope = .Viewport},
		tail[:],
	)
	testing.expectf(t, tail_copied, "eviction tail failed with %v", tail_failure.code)
	testing.expect(t, strings.contains(string(tail[:int(tail_snapshot.copied_bytes)]), "new-marker"))
	eviction_state, eviction_inspected, eviction_state_failure := registry_scrollback(
		&registry, evicted_record.ref,
	)
	testing.expectf(t, eviction_inspected, "eviction state failed with %v", eviction_state_failure.code)
	testing.expect_value(t, eviction_state.scrollback_max_bytes, u64(1))
	testing.expect_value(t, eviction_state.scrollback_max_rows, u64(5))
}
