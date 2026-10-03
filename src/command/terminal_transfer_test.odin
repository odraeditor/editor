// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "core:testing"
import "../kill_ring"

/* Verifies terminal copy retention and ordered yank rotation stay buffer-independent. */
@(test)
terminal_transfer_retains_and_rotates_text :: proc(t: ^testing.T) {
	ring: kill_ring.Ring
	ring_ok, ring_failure := kill_ring.ring_init(
		&ring,
		kill_ring.Ring_ID(901),
		kill_ring.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	testing.expectf(t, ring_ok, "kill ring failed with %v", ring_failure.code)
	if !ring_ok do return
	defer kill_ring.ring_close(&ring)

	first, first_ok, first_failure := terminal_text_retain(&ring, {}, "first", 64)
	testing.expectf(t, first_ok, "first retention failed with %v", first_failure.code)
	testing.expect(t, first.entry.id != kill_ring.Entry_ID(0))
	second, second_ok, second_failure := terminal_text_retain(&ring, {}, "second", 64)
	testing.expectf(t, second_ok, "second retention failed with %v", second_failure.code)
	testing.expect(t, second.entry.id != first.entry.id)

	newest, yank_state, newest_ok, newest_failure := terminal_text_yank_copy(
		&ring, {}, {}, false, 64, context.temp_allocator,
	)
	testing.expectf(t, newest_ok, "newest yank failed with %v", newest_failure.code)
	if !newest_ok do return
	testing.expect_value(t, newest.text, "second")
	terminal_text_yank_copy_release(&newest, context.temp_allocator)
	rotated, rotated_state, rotated_ok, rotated_failure := terminal_text_yank_copy(
		&ring, {}, yank_state, true, 64, context.temp_allocator,
	)
	testing.expectf(t, rotated_ok, "rotated yank failed with %v", rotated_failure.code)
	if rotated_ok {
		testing.expect_value(t, rotated.text, "first")
		testing.expect(t, rotated_state.entry_id != yank_state.entry_id)
		terminal_text_yank_copy_release(&rotated, context.temp_allocator)
	}
}

/* Verifies terminal transfer limits and stale yank ordering fail before mutation. */
@(test)
terminal_transfer_rejects_stale_rotation :: proc(t: ^testing.T) {
	ring: kill_ring.Ring
	ring_ok, ring_failure := kill_ring.ring_init(
		&ring,
		kill_ring.Ring_ID(902),
		kill_ring.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	testing.expectf(t, ring_ok, "kill ring failed with %v", ring_failure.code)
	if !ring_ok do return
	defer kill_ring.ring_close(&ring)

	_, retained, retain_failure := terminal_text_retain(&ring, {}, "oversized", 4)
	testing.expect(t, !retained)
	testing.expect_value(t, retain_failure.code, Failure_Code.Text_Limit)
	testing.expect_value(t, retain_failure.limit, u64(4))
	_, retained, retain_failure = terminal_text_retain(&ring, {}, "safe", 4)
	testing.expectf(t, retained, "bounded retention failed with %v", retain_failure.code)
	_, _, rotated, rotate_failure := terminal_text_yank_copy(
		&ring,
		{},
		Terminal_Yank_State {
			valid = true,
			ring_generation = kill_ring.Generation(max(u64)),
			entry_id = kill_ring.Entry_ID(1),
		},
		true,
		4,
		context.temp_allocator,
	)
	testing.expect(t, !rotated)
	testing.expect_value(t, rotate_failure.code, Failure_Code.Kill_Ring_Failure)
	testing.expect_value(t, rotate_failure.kill_ring_code, kill_ring.Failure_Code.Stale_Generation)
}
