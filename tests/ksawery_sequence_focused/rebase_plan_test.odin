// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery_sequence_focused

import ksawery "../../src/ksawery"
import "core:mem"
import "core:testing"

REBASE_PLAN_A :: "0123456789012345678901234567890123456789"
REBASE_PLAN_B :: "1234567890123456789012345678901234567890"
REBASE_PLAN_C :: "2345678901234567890123456789012345678901"

/* Verifies autosquash projection resolves every fixup and squash to one exact earlier commit. */
@(test)
rebase_plan_resolves_semantic_targets_and_accepts_exact_identity :: proc(t: ^testing.T) {
	commits := [?]ksawery.Rebase_Plan_Commit {
		{conflict_test_revision(t, REBASE_PLAN_A), "Add parser"},
		{conflict_test_revision(t, REBASE_PLAN_B), "fixup! Add parser"},
		{conflict_test_revision(t, REBASE_PLAN_C), "Add rendering"},
		{conflict_test_revision(t, REBASE_OLD_TIP), "squash! Add rendering"},
	}
	upstream := conflict_test_revision(t, REBASE_UPSTREAM)
	old_tip := conflict_test_revision(t, REBASE_OLD_TIP)
	plan, opened, failure := ksawery.rebase_plan_project(commits[:], old_tip, upstream)
	testing.expectf(t, opened, "autosquash plan failed with %v", failure)
	if !opened do return
	defer ksawery.rebase_plan_close(&plan)
	descriptor, described := ksawery.rebase_plan_descriptor(&plan)
	testing.expect(t, described)
	testing.expect_value(t, descriptor.state, ksawery.Rebase_Plan_State.Available)
	testing.expect_value(t, descriptor.step_count, u32(4))
	testing.expect_value(t, descriptor.fixups, u32(1))
	testing.expect_value(t, descriptor.squashes, u32(1))
	fixup, fixup_found := ksawery.rebase_plan_step(&plan, 1)
	testing.expect(t, fixup_found)
	if fixup_found {
		testing.expect_value(t, fixup.action, ksawery.Rebase_Replay_Action.Fixup)
		testing.expect_value(t, fixup.target, commits[0].revision)
		subject, copied := ksawery.rebase_plan_subject(&plan, fixup.subject)
		testing.expect(t, copied)
		testing.expect_value(t, subject, commits[1].subject)
	}
	squash, squash_found := ksawery.rebase_plan_step(&plan, 3)
	testing.expect(t, squash_found)
	if squash_found {
		testing.expect_value(t, squash.action, ksawery.Rebase_Replay_Action.Squash)
		testing.expect_value(t, squash.target, commits[2].revision)
	}
	reviewed, accepted, accept_failure := ksawery.rebase_plan_accept(&plan)
	testing.expectf(t, accepted, "autosquash plan acceptance failed with %v", accept_failure)
	if accepted {
		testing.expect(t, ksawery.rebase_reviewed_plan_is_valid(reviewed))
		testing.expect_value(t, reviewed.fingerprint, descriptor.fingerprint)
		testing.expect_value(t, reviewed.old_tip, old_tip)
		testing.expect_value(t, reviewed.upstream, upstream)
	}
}

/* Verifies exact subject matches win over prefixes while ambiguous prefixes remain unavailable. */
@(test)
rebase_plan_rejects_ambiguous_autosquash_targets :: proc(t: ^testing.T) {
	commits := [?]ksawery.Rebase_Plan_Commit {
		{conflict_test_revision(t, REBASE_PLAN_A), "Build parser"},
		{conflict_test_revision(t, REBASE_PLAN_B), "Build parser options"},
		{conflict_test_revision(t, REBASE_OLD_TIP), "fixup! Build"},
	}
	plan, opened, failure := ksawery.rebase_plan_project(
		commits[:],
		commits[2].revision,
		conflict_test_revision(t, REBASE_UPSTREAM),
	)
	testing.expectf(t, opened, "ambiguous plan failed to project with %v", failure)
	if opened {
		defer ksawery.rebase_plan_close(&plan)
		descriptor, described := ksawery.rebase_plan_descriptor(&plan)
		testing.expect(t, described && descriptor.state == .Ambiguous && descriptor.problem_step == 3)
		_, accepted, accept_failure := ksawery.rebase_plan_accept(&plan)
		testing.expect(t, !accepted && accept_failure == .Action_Unavailable)
	}

	commits[2].subject = "fixup! Build parser"
	exact, exact_opened, exact_failure := ksawery.rebase_plan_project(
		commits[:],
		commits[2].revision,
		conflict_test_revision(t, REBASE_UPSTREAM),
	)
	testing.expectf(t, exact_opened, "exact-match plan failed with %v", exact_failure)
	if exact_opened {
		defer ksawery.rebase_plan_close(&exact)
		step, found := ksawery.rebase_plan_step(&exact, 2)
		testing.expect(t, found && step.target == commits[0].revision)
	}
}

/* Verifies unsupported autosquash forms and stale replay endpoints never become accepted plans. */
@(test)
rebase_plan_rejects_unsupported_and_stale_inputs :: proc(t: ^testing.T) {
	commits := [?]ksawery.Rebase_Plan_Commit {
		{conflict_test_revision(t, REBASE_PLAN_A), "Add parser"},
		{conflict_test_revision(t, REBASE_OLD_TIP), "reword! Add parser"},
	}
	upstream := conflict_test_revision(t, REBASE_UPSTREAM)
	plan, opened, failure := ksawery.rebase_plan_project(commits[:], commits[1].revision, upstream)
	testing.expectf(t, opened, "unsupported plan failed to project with %v", failure)
	if opened {
		defer ksawery.rebase_plan_close(&plan)
		descriptor, described := ksawery.rebase_plan_descriptor(&plan)
		testing.expect(t, described && descriptor.state == .Unsupported && descriptor.problem_step == 2)
	}
	_, stale_opened, stale_failure := ksawery.rebase_plan_project(
		commits[:],
		conflict_test_revision(t, REBASE_PLAN_C),
		upstream,
	)
	testing.expect(t, !stale_opened && stale_failure == .Stale_Observation)
	duplicate := commits
	duplicate[1].revision = duplicate[0].revision
	_, duplicate_opened, duplicate_failure := ksawery.rebase_plan_project(
		duplicate[:],
		duplicate[1].revision,
		upstream,
	)
	testing.expect(t, !duplicate_opened && duplicate_failure == .Invalid_Request)
}

/* Verifies step truncation is explicit and all bounded preview ownership is released. */
@(test)
rebase_plan_truncates_and_cleans_up :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	commits := [?]ksawery.Rebase_Plan_Commit {
		{conflict_test_revision(t, REBASE_PLAN_A), "First"},
		{conflict_test_revision(t, REBASE_PLAN_B), "Second"},
		{conflict_test_revision(t, REBASE_OLD_TIP), "Third"},
	}
	limits := ksawery.DEFAULT_REBASE_PLAN_LIMITS
	limits.steps = 2
	plan, opened, failure := ksawery.rebase_plan_project(
		commits[:],
		commits[2].revision,
		conflict_test_revision(t, REBASE_UPSTREAM),
		limits,
		allocator,
	)
	testing.expectf(t, opened, "truncated plan failed with %v", failure)
	if opened {
		descriptor, described := ksawery.rebase_plan_descriptor(&plan)
		testing.expect(t, described && descriptor.state == .Truncated)
		testing.expect_value(t, descriptor.observed_steps, u32(3))
		usage, measured := ksawery.rebase_plan_usage(&plan)
		testing.expect(t, measured)
		testing.expect_value(t, usage.steps, u32(0))
		testing.expect_value(t, usage.observed_steps, u32(3))
		ksawery.rebase_plan_close(&plan)
	}
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&tracking)
}
