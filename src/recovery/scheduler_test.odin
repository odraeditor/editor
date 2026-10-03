// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package recovery

import "core:testing"

/* Verifies rapid commits coalesce while the maximum interval remains binding. */
@(test)
scheduler_coalesces_commits_with_a_hard_deadline :: proc(t: ^testing.T) {
	state: Scheduler
	initialized, failure := scheduler_init(&state, DEFAULT_POLICY, context.allocator)
	testing.expectf(t, initialized, "scheduler init failed with %v", failure.code)
	defer scheduler_close(&state)

	marked, _ := scheduler_mark_commit(&state, Buffer_ID(2), 1, 100)
	testing.expect(t, marked)
	marked, _ = scheduler_mark_commit(&state, Buffer_ID(2), 2, 250)
	testing.expect(t, marked)
	_, due, _ := scheduler_claim_due(&state, 549)
	testing.expect(t, !due)
	claim: Checkpoint_Claim
	claim, due, _ = scheduler_claim_due(&state, 550)
	testing.expect(t, due)
	testing.expect_value(t, claim.revision, u64(2))
}

/* Verifies failed publication is retried without losing a newer pending commit. */
@(test)
scheduler_requeues_failed_claim_behind_newer_work :: proc(t: ^testing.T) {
	state: Scheduler
	initialized, _ := scheduler_init(&state, DEFAULT_POLICY, context.allocator)
	testing.expect(t, initialized)
	defer scheduler_close(&state)

	marked, _ := scheduler_mark_commit(&state, Buffer_ID(7), 3, 100)
	testing.expect(t, marked)
	claim, due, _ := scheduler_claim_due(&state, 400)
	testing.expect(t, due)
	marked, _ = scheduler_mark_commit(&state, Buffer_ID(7), 4, 450)
	testing.expect(t, marked)
	resolved, _ := scheduler_resolve_claim(&state, claim, false)
	testing.expect(t, resolved)
	retry: Checkpoint_Claim
	retry, due, _ = scheduler_claim_due(&state, 750)
	testing.expect(t, due)
	testing.expect_value(t, retry.revision, u64(4))
}

/* Verifies confirmed save retirement never discards a newer dirty revision. */
@(test)
scheduler_save_retires_only_obsolete_checkpoint_state :: proc(t: ^testing.T) {
	state: Scheduler
	initialized, _ := scheduler_init(&state, DEFAULT_POLICY, context.allocator)
	testing.expect(t, initialized)
	defer scheduler_close(&state)

	marked, _ := scheduler_mark_commit(&state, Buffer_ID(9), 5, 100)
	testing.expect(t, marked)
	claim, due, _ := scheduler_claim_due(&state, 400)
	testing.expect(t, due)
	resolved, _ := scheduler_resolve_claim(&state, claim, true)
	testing.expect(t, resolved)
	marked, _ = scheduler_mark_commit(&state, Buffer_ID(9), 6, 500)
	testing.expect(t, marked)
	retired, saved, _ := scheduler_confirm_saved(&state, Buffer_ID(9), 5)
	testing.expect(t, saved)
	testing.expect_value(t, retired, u64(5))
	pending: Checkpoint_Claim
	pending, due, _ = scheduler_claim_due(&state, 800)
	testing.expect(t, due)
	testing.expect_value(t, pending.revision, u64(6))
}

/* Verifies equal deadlines select the lower stable buffer identity first. */
@(test)
scheduler_due_order_is_deterministic :: proc(t: ^testing.T) {
	state: Scheduler
	initialized, _ := scheduler_init(&state, DEFAULT_POLICY, context.allocator)
	testing.expect(t, initialized)
	defer scheduler_close(&state)

	marked, _ := scheduler_mark_commit(&state, Buffer_ID(12), 1, 100)
	testing.expect(t, marked)
	marked, _ = scheduler_mark_commit(&state, Buffer_ID(3), 1, 100)
	testing.expect(t, marked)
	claim, due, _ := scheduler_claim_due(&state, 400)
	testing.expect(t, due)
	testing.expect_value(t, claim.buffer_id, Buffer_ID(3))
}

/* Verifies explicit buffer closure releases scheduling capacity and pending work. */
@(test)
scheduler_forget_releases_one_buffer :: proc(t: ^testing.T) {
	state: Scheduler
	initialized, _ := scheduler_init(&state, DEFAULT_POLICY, context.allocator)
	testing.expect(t, initialized)
	defer scheduler_close(&state)
	marked, _ := scheduler_mark_commit(&state, Buffer_ID(17), 1, 100)
	testing.expect(t, marked)
	forgotten, failure := scheduler_forget_buffer(&state, Buffer_ID(17))
	testing.expectf(t, forgotten, "forget failed with %v", failure.code)
	_, due, _ := scheduler_claim_due(&state, 10_000)
	testing.expect(t, !due)
}
