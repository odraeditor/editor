// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../interaction"
import "../kill_ring"
import "core:mem"
import "core:testing"

/* Verifies export copying plus token and content deduplication around external admission. */
@(test)
clipboard_admits_changed_external_text :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	allocator := mem.tracking_allocator(&tracking)

	ring: kill_ring.Ring
	initialized, init_failure := kill_ring.ring_init(
		&ring,
		kill_ring.Ring_ID(91),
		kill_ring.Allocator_Set{persistent = allocator, temporary = allocator},
	)
	testing.expect(t, initialized && init_failure.code == .None)
	if !initialized {
		return
	}
	command := interaction.Command_Handle {
		registry_generation = interaction.Registry_Generation(1),
		slot = 1,
		entry_generation = 1,
	}
	first := admit_clipboard_fixture(t, &ring, "internal", .Copy)
	export, exported, export_failure := clipboard_export_copy(
		&ring,
		command,
		first,
		64,
		allocator,
	)
	testing.expect(t, exported && export_failure.code == .None)
	testing.expect_value(t, export.text, "internal")
	clipboard_export_close(&export)

	state: Clipboard_Transfer_State
	testing.expect(t, clipboard_transfer_record_export(&state, Clipboard_Token(10)))
	self, self_ok, self_failure := clipboard_external_admit(
		&ring,
		&state,
		command,
		"internal",
		Clipboard_Token(10),
		allocator,
	)
	testing.expect(t, self_ok && self_failure.code == .None)
	testing.expect_value(t, self.kind, Clipboard_Import_Kind.Unchanged)

	same, same_ok, same_failure := clipboard_external_admit(
		&ring,
		&state,
		command,
		"internal",
		Clipboard_Token(11),
		allocator,
	)
	testing.expect(t, same_ok && same_failure.code == .None)
	testing.expect_value(t, same.kind, Clipboard_Import_Kind.Unchanged)

	changed, changed_ok, changed_failure := clipboard_external_admit(
		&ring,
		&state,
		command,
		"external",
		Clipboard_Token(12),
		allocator,
	)
	testing.expect(t, changed_ok && changed_failure.code == .None)
	testing.expect_value(t, changed.kind, Clipboard_Import_Kind.Admitted)
	testing.expect_value(t, changed.transfer.entry.admission_kind, kill_ring.Admission_Kind.External)
	stats, stats_ok, _ := kill_ring.ring_stats(&ring)
	testing.expect(t, stats_ok)
	testing.expect_value(t, stats.usage.retained_entries, u64(2))

	closed, close_failure := kill_ring.ring_close(&ring)
	testing.expect(t, closed && close_failure.code == .None)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
}

/* Verifies rejected tokens and cancellation preserve ring generation and deduplication state. */
@(test)
clipboard_transfer_rejection_preserves_state :: proc(t: ^testing.T) {
	ring: kill_ring.Ring
	initialized, _ := kill_ring.ring_init(
		&ring,
		kill_ring.Ring_ID(92),
		kill_ring.Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, initialized)
	if !initialized {
		return
	}
	defer kill_ring.ring_close(&ring)
	command := interaction.Command_Handle {
		registry_generation = interaction.Registry_Generation(1),
		slot = 1,
		entry_generation = 1,
	}
	state: Clipboard_Transfer_State
	before, before_ok, _ := kill_ring.ring_stats(&ring)
	testing.expect(t, before_ok)
	_, invalid_ok, invalid_failure := clipboard_external_admit(
		&ring,
		&state,
		command,
		"external",
		Clipboard_Token(0),
		context.temp_allocator,
	)
	testing.expect(t, !invalid_ok)
	testing.expect_value(t, invalid_failure.code, Failure_Code.Invalid_Request)
	_, cancelled_ok, cancelled_failure := clipboard_external_admit(
		&ring,
		&state,
		command,
		"external",
		Clipboard_Token(2),
		context.temp_allocator,
		true,
	)
	testing.expect(t, !cancelled_ok)
	testing.expect_value(t, cancelled_failure.kill_ring_code, kill_ring.Failure_Code.Cancelled)
	after, after_ok, _ := kill_ring.ring_stats(&ring)
	testing.expect(t, after_ok)
	testing.expect_value(t, after.generation, before.generation)
	testing.expect_value(t, state.last_import, Clipboard_Token(0))
}

@(private)
admit_clipboard_fixture :: proc(
	t: ^testing.T,
	ring: ^kill_ring.Ring,
	text: string,
	kind: kill_ring.Admission_Kind,
) -> kill_ring.Reservation_Result {
	stats, stats_ok, _ := kill_ring.ring_stats(ring)
	testing.expect(t, stats_ok)
	reservation: kill_ring.Reservation
	result, reserved, failure := kill_ring.admission_reserve(
		ring,
		&reservation,
		kill_ring.Admission_Request {
			expected_generation = stats.generation,
			kind = kind,
			text = text,
		},
	)
	testing.expect(t, reserved && failure.code == .None)
	if !reserved {
		return {}
	}
	committed := kill_ring.reservation_commit_reserved(&reservation)
	testing.expect_value(t, committed, result)
	return committed
}
