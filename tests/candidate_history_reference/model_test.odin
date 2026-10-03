// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package candidate_history_reference

import "core:mem"
import "core:testing"

/* Verifies one category/key pair is updated exactly once and ordered by recency. */
@(test)
records_unique_usage_and_order :: proc(t: ^testing.T) {
	state, initialized, failure := state_init("odra-development")
	testing.expectf(t, initialized, "history model init failed with %v", failure.code)
	defer state_destroy(&state)

	_, first_ok, _ := record_success(&state, .Command, "execute-extended-command")
	_, second_ok, _ := record_success(&state, .Document, "/tmp/alpha.md")
	sequence, update_ok, _ := record_success(&state, .Command, "execute-extended-command")
	testing.expect(t, first_ok && second_ok && update_ok)
	testing.expect_value(t, state.active_count, 2)
	testing.expect_value(t, sequence, u64(3))
	indices: [2]int
	count, ordered := canonical_indices(&state, indices[:])
	testing.expect(t, ordered)
	testing.expect_value(t, count, 2)
	if count == 2 {
		testing.expect_value(t, state.entries[indices[0]].category, Category.Command)
		testing.expect_value(t, state.entries[indices[1]].category, Category.Document)
	}
}

/* Verifies deterministic least-recent retention and compact sequence renormalization. */
@(test)
retains_and_renormalizes_order :: proc(t: ^testing.T) {
	limits := DEFAULT_LIMITS
	limits.entries = 3
	limits.sequence_ceiling = 6
	state, initialized, _ := state_init("small-project", limits)
	testing.expect(t, initialized)
	defer state_destroy(&state)

	record_success(&state, .Command, "alpha")
	record_success(&state, .Command, "beta")
	record_success(&state, .Command, "gamma")
	record_success(&state, .Command, "delta")
	_, alpha_present := lookup(&state, .Command, "alpha")
	_, delta_present := lookup(&state, .Command, "delta")
	testing.expect(t, !alpha_present && delta_present)
	record_success(&state, .Command, "beta")
	_, renormalized, failure := record_success(&state, .Command, "beta")
	testing.expectf(t, renormalized, "renormalization failed with %v", failure.code)
	testing.expect(t, state.next_sequence < limits.sequence_ceiling)
	indices: [3]int
	count, ordered := canonical_indices(&state, indices[:])
	testing.expect(t, ordered)
	if count == 3 {
		testing.expect_value(t, state.entries[indices[0]].key, "beta")
		testing.expect_value(t, state.entries[indices[1]].key, "delta")
		testing.expect_value(t, state.entries[indices[2]].key, "gamma")
	}
}

/* Verifies flush thresholds, stale acknowledgements, and the single retry budget. */
@(test)
history_model_bounds_dirty_flush_and_retry_state :: proc(t: ^testing.T) {
	limits := DEFAULT_LIMITS
	limits.flush_events = 2
	state, initialized, _ := state_init("flush-project", limits)
	testing.expect(t, initialized)
	defer state_destroy(&state)

	record_success(&state, .Command, "alpha")
	testing.expect(t, !flush_due(&state))
	record_success(&state, .Command, "beta")
	testing.expect(t, flush_due(&state))
	dirty := state.dirty_generation
	stale_ok, stale := mark_flushed(&state, dirty - 1, 2)
	testing.expect(t, !stale_ok)
	testing.expect_value(t, stale.code, Failure_Code.Stale_Generation)
	retry, _ := note_flush_failure(&state)
	second_retry, exhausted := note_flush_failure(&state)
	testing.expect(t, retry && !second_retry)
	testing.expect_value(t, exhausted.code, Failure_Code.Retry_Exhausted)
	flushed, _ := mark_flushed(&state, dirty, 2)
	testing.expect(t, flushed)
	testing.expect(t, !flush_due(&state))
}

/* Verifies malformed identities and allocation faults retain no model memory. */
@(test)
rejects_bad_identity_without_memory :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	state, initialized, _ := state_init("tracked-project", DEFAULT_LIMITS, allocator)
	testing.expect(t, initialized)
	_, relative_ok, relative_failure := record_success(&state, .Document, "relative.md")
	testing.expect(t, !relative_ok)
	testing.expect_value(t, relative_failure.code, Failure_Code.Invalid_Key)
	state_destroy(&state)
	testing.expect_value(t, tracking.current_memory_allocated, 0)
	mem.tracking_allocator_destroy(&tracking)

	_, allocation_ok, allocation_failure := state_init("allocation-project", DEFAULT_LIMITS, {})
	testing.expect(t, !allocation_ok)
	testing.expect_value(t, allocation_failure.code, Failure_Code.Invalid_State)
}
