// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "base:runtime"
import "../interaction"
import "../kill_ring"

/* Terminal_Yank_State retains only kill-ring ordering for one terminal yank sequence. */
Terminal_Yank_State :: struct {
	valid:           bool,
	ring_generation: kill_ring.Generation,
	entry_id:        kill_ring.Entry_ID,
}

/* terminal_text_retain admits one copied terminal selection without buffer mutation. */
terminal_text_retain :: proc(
	ring: ^kill_ring.Ring,
	command_handle: interaction.Command_Handle,
	text: string,
	byte_limit: u64,
) -> (transfer: kill_ring.Reservation_Result, ok: bool, failure: Failure_Context) {
	if ring == nil || !kill_ring.ring_is_valid(ring) || byte_limit == 0 {
		return {}, false, Failure_Context{code = .Invalid_Request, command = command_handle}
	}
	if u64(len(text)) > byte_limit {
		return {}, false, Failure_Context {
			code = .Text_Limit,
			command = command_handle,
			limit = byte_limit,
			actual = u64(len(text)),
		}
	}
	stats, stats_ok, stats_failure := kill_ring.ring_stats(ring)
	if !stats_ok do return {}, false, native_kill_ring_failure(command_handle, stats_failure)
	reservation: kill_ring.Reservation
	reserved_result, reserved, reserve_failure := kill_ring.admission_reserve(
		ring,
		&reservation,
		kill_ring.Admission_Request {
			expected_generation = stats.generation,
			kind = .Copy,
			text = text,
		},
	)
	if !reserved do return {}, false, native_kill_ring_failure(command_handle, reserve_failure)
	transfer = kill_ring.reservation_commit_reserved(&reservation)
	assert(transfer == reserved_result)
	return transfer, true, {}
}

/* terminal_text_yank_copy owns one bounded newest or rotated ring entry copy. */
terminal_text_yank_copy :: proc(
	ring: ^kill_ring.Ring,
	command_handle: interaction.Command_Handle,
	prior: Terminal_Yank_State,
	rotate: bool,
	byte_limit: u64,
	allocator: runtime.Allocator,
) -> (
	copied: kill_ring.Entry_Copy,
	next: Terminal_Yank_State,
	ok: bool,
	failure: Failure_Context,
) {
	if ring == nil || !kill_ring.ring_is_valid(ring) || byte_limit == 0 ||
	   allocator.procedure == nil {
		return {}, {}, false, Failure_Context{code = .Invalid_Request, command = command_handle}
	}
	stats, stats_ok, stats_failure := kill_ring.ring_stats(ring)
	if !stats_ok do return {}, {}, false, native_kill_ring_failure(command_handle, stats_failure)
	entry_id := stats.newest
	if rotate {
		if !prior.valid || prior.ring_generation != stats.generation ||
		   prior.entry_id == kill_ring.Entry_ID(0) {
			return {}, {}, false, Failure_Context {
				code = .Kill_Ring_Failure,
				command = command_handle,
				kill_ring_code = .Stale_Generation,
				kill_ring_generation = stats.generation,
			}
		}
		entry_id = prior.entry_id
	}
	if entry_id == kill_ring.Entry_ID(0) {
		return {}, {}, false, Failure_Context {
			code = .Kill_Ring_Failure,
			command = command_handle,
			kill_ring_code = .Empty_Ring,
			kill_ring_generation = stats.generation,
		}
	}
	copy_ok: bool
	copy_failure: kill_ring.Failure_Context
	if rotate {
		copied, copy_ok, copy_failure = kill_ring.rotation_next(
			ring,
			kill_ring.Rotation_Request {
				expected_generation = stats.generation,
				current_entry = entry_id,
				work_limit = stats.policy.rotation_work,
				byte_limit = min(byte_limit, stats.policy.entry_bytes),
			},
			allocator,
		)
	} else {
		copied, copy_ok, copy_failure = kill_ring.entry_copy(
			ring,
			kill_ring.Entry_Copy_Request {
				expected_generation = stats.generation,
				entry_id = entry_id,
				byte_limit = min(byte_limit, stats.policy.entry_bytes),
			},
			allocator,
		)
	}
	if !copy_ok do return {}, {}, false, native_kill_ring_failure(command_handle, copy_failure)
	next = Terminal_Yank_State {
		valid = true,
		ring_generation = stats.generation,
		entry_id = copied.metadata.id,
	}
	return copied, next, true, {}
}

/* terminal_text_yank_copy_release frees one terminal transfer copy. */
terminal_text_yank_copy_release :: proc(
	copied: ^kill_ring.Entry_Copy,
	allocator: runtime.Allocator,
) {
	kill_ring.entry_copy_release(copied, allocator)
}
