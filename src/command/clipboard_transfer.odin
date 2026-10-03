// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../interaction"
import "../kill_ring"
import "base:runtime"
import "core:bytes"

/* Clipboard_Token identifies one value within the lifetime of one frontend adapter. */
Clipboard_Token :: distinct u64

/* Clipboard_Transfer_State retains only deduplication tokens, never clipboard text. */
Clipboard_Transfer_State :: struct {
	last_export: Clipboard_Token,
	last_import: Clipboard_Token,
}

/* Clipboard_Import_Kind distinguishes newly admitted and unchanged external values. */
Clipboard_Import_Kind :: enum u8 {
	Invalid,
	Unchanged,
	Admitted,
}

/* Clipboard_Import_Result reports one checked external ring transition. */
Clipboard_Import_Result :: struct {
	kind:     Clipboard_Import_Kind,
	transfer: kill_ring.Reservation_Result,
}

/* Clipboard_Export owns one bounded copied ring value until clipboard_export_close. */
Clipboard_Export :: struct {
	text:       string,
	entry_id:   kill_ring.Entry_ID,
	generation: kill_ring.Generation,
	allocator:  runtime.Allocator,
}

/* clipboard_transfer_record_export records one successful physical export token. */
clipboard_transfer_record_export :: proc(
	state: ^Clipboard_Transfer_State,
	token: Clipboard_Token,
) -> bool {
	if state == nil || token == Clipboard_Token(0) {
		return false
	}
	state.last_export = token
	return true
}

/* clipboard_external_admit deduplicates and admits one copied external value atomically. */
clipboard_external_admit :: proc(
	ring: ^kill_ring.Ring,
	state: ^Clipboard_Transfer_State,
	command: interaction.Command_Handle,
	text: string,
	token: Clipboard_Token,
	temporary_allocator: runtime.Allocator,
	cancelled := false,
) -> (result: Clipboard_Import_Result, ok: bool, failure: Failure_Context) {
	if ring == nil || !kill_ring.ring_is_valid(ring) || state == nil ||
	   token == Clipboard_Token(0) || temporary_allocator.procedure == nil {
		return {}, false, Failure_Context{code = .Invalid_Request, command = command}
	}
	if token == state.last_export || token == state.last_import {
		state.last_import = token
		return Clipboard_Import_Result{kind = .Unchanged}, true, {}
	}
	stats, stats_ok, stats_failure := kill_ring.ring_stats(ring)
	if !stats_ok {
		return {}, false, native_kill_ring_failure(command, stats_failure)
	}
	if stats.newest != kill_ring.Entry_ID(0) && u64(len(text)) <= stats.policy.entry_bytes {
		newest, copied, copy_failure := kill_ring.entry_copy(
			ring,
			kill_ring.Entry_Copy_Request {
				expected_generation = stats.generation,
				entry_id = stats.newest,
				byte_limit = stats.policy.entry_bytes,
			},
			temporary_allocator,
		)
		if !copied {
			return {}, false, native_kill_ring_failure(command, copy_failure)
		}
		same := bytes.equal(transmute([]byte)newest.text, transmute([]byte)text)
		kill_ring.entry_copy_release(&newest, temporary_allocator)
		if same {
			state.last_import = token
			return Clipboard_Import_Result{kind = .Unchanged}, true, {}
		}
	}
	reservation: kill_ring.Reservation
	reserved_result, reserved, reserve_failure := kill_ring.admission_reserve(
		ring,
		&reservation,
		kill_ring.Admission_Request {
			expected_generation = stats.generation,
			kind = .External,
			text = text,
			cancelled = cancelled,
		},
	)
	if !reserved {
		return {}, false, native_kill_ring_failure(command, reserve_failure)
	}
	committed := kill_ring.reservation_commit_reserved(&reservation)
	assert(committed == reserved_result)
	state.last_import = token
	return Clipboard_Import_Result{kind = .Admitted, transfer = committed}, true, {}
}

/* clipboard_export_copy copies the exact post-command retained entry under a byte limit. */
clipboard_export_copy :: proc(
	ring: ^kill_ring.Ring,
	command: interaction.Command_Handle,
	transfer: kill_ring.Reservation_Result,
	byte_limit: u64,
	allocator: runtime.Allocator,
) -> (export: Clipboard_Export, ok: bool, failure: Failure_Context) {
	if ring == nil || !kill_ring.ring_is_valid(ring) ||
	   transfer.entry.id == kill_ring.Entry_ID(0) || byte_limit == 0 ||
	   allocator.procedure == nil {
		return {}, false, Failure_Context{code = .Invalid_Request, command = command}
	}
	stats, stats_ok, stats_failure := kill_ring.ring_stats(ring)
	if !stats_ok {
		return {}, false, native_kill_ring_failure(command, stats_failure)
	}
	if transfer.result_generation != stats.generation {
		return {}, false, Failure_Context {
			code = .Kill_Ring_Failure,
			command = command,
			kill_ring_code = .Stale_Generation,
			kill_ring_generation = stats.generation,
		}
	}
	entry, copied, copy_failure := kill_ring.entry_copy(
		ring,
		kill_ring.Entry_Copy_Request {
			expected_generation = stats.generation,
			entry_id = transfer.entry.id,
			byte_limit = byte_limit,
		},
		allocator,
	)
	if !copied {
		return {}, false, native_kill_ring_failure(command, copy_failure)
	}
	return Clipboard_Export {
		text = entry.text,
		entry_id = entry.metadata.id,
		generation = entry.metadata.generation,
		allocator = allocator,
	}, true, {}
}

/* clipboard_export_close releases one copied ring value. */
clipboard_export_close :: proc(export: ^Clipboard_Export) {
	if export == nil {
		return
	}
	if len(export.text) > 0 && export.allocator.procedure != nil {
		delete(transmute([]byte)export.text, export.allocator)
	}
	export^ = {}
}
