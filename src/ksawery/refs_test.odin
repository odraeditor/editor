// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery

import "core:mem"
import "core:testing"

@(private)
ref_test_output :: proc() -> []u8 {
	return transmute([]u8)(string(
		"refs/heads/main\x00" + REF_TEST_SHA1 + "\x00commit\x00refs/remotes/origin/main\x00[ahead 2, behind 1]\x00*\x00\n" +
		"refs/remotes/origin/main\x00" + REF_TEST_SHA1 + "\x00commit\x00\x00\x00 \x00\n" +
		"refs/tags/v0.1.0\x00" + REF_TEST_SHA1 + "\x00commit\x00\x00\x00 \x00\n",
	))
}

/* Verifies Ref parsing retains exact names, object identities, remotes, and tracking state. */
@(test)
ref_observation_parses_exact_refs_remotes_and_tracking :: proc(t: ^testing.T) {
	repository: Repository_Context
	ready := repository_context_assign(&repository, "/work/refs")
	testing.expect(t, ready)
	if !ready do return
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	observation, opened, failure := ref_observation_open(
		repository,
		Ref_Generation(4),
		ref_test_output(),
		transmute([]u8)(string("origin\n")),
		transmute([]u8)(string(REF_TEST_SHA1 + "\n")),
		DEFAULT_REF_LIMITS,
		allocator,
	)
	testing.expectf(t, opened, "Ref observation failed with %v", failure)
	if !opened {
		mem.tracking_allocator_destroy(&tracking)
		return
	}
	descriptor, described := ref_observation_descriptor(&observation)
	testing.expect(t, described)
	if described {
		testing.expect_value(t, descriptor.state, Ref_Observation_State.Available)
		testing.expect_value(t, descriptor.head.state, Head_State.Symbolic)
		testing.expect_value(t, descriptor.local_branch_count, u32(1))
		testing.expect_value(t, descriptor.remote_tracking_count, u32(1))
		testing.expect_value(t, descriptor.tag_count, u32(1))
		testing.expect_value(t, descriptor.remote_count, u32(1))
		testing.expect_value(t, descriptor.tracking_relationships, u32(1))
	}
	relationship, found := ref_observation_tracking(&observation, 0)
	testing.expect(t, found)
	if found {
		testing.expect_value(t, relationship.state, Tracking_State.Diverged)
		testing.expect_value(t, relationship.ahead, u32(2))
		testing.expect_value(t, relationship.behind, u32(1))
	}
	usage, measured := ref_observation_usage(&observation)
	testing.expect(t, measured && ref_usage_is_valid(usage, descriptor))
	ref_observation_close(&observation)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&tracking)
}

/* Verifies Ref parsing distinguishes unborn and malformed process output without mutating state. */
@(test)
ref_observation_rejects_malformed_records_and_accepts_unborn_repository :: proc(t: ^testing.T) {
	repository: Repository_Context
	ready := repository_context_assign(&repository, "/work/refs")
	testing.expect(t, ready)
	if !ready do return
	unborn, opened, failure := ref_observation_open(
		repository,
		Ref_Generation(5),
		nil,
		transmute([]u8)(string("origin\n")),
		nil,
		DEFAULT_REF_LIMITS,
	)
	testing.expectf(t, opened, "unborn Ref observation failed with %v", failure)
	if opened {
		descriptor, described := ref_observation_descriptor(&unborn)
		testing.expect(t, described && descriptor.state == .Unborn && descriptor.remote_count == 1)
		ref_observation_close(&unborn)
	}
	malformed := transmute([]u8)(string("refs/heads/main\x00" + REF_TEST_SHA1 + "\x00commit\x00"))
	_, malformed_opened, malformed_failure := ref_observation_open(
		repository,
		Ref_Generation(6),
		malformed,
		nil,
		transmute([]u8)(string(REF_TEST_SHA1 + "\n")),
		DEFAULT_REF_LIMITS,
	)
	testing.expect(t, !malformed_opened && malformed_failure == .Parse)
}

/* Verifies Ref navigation preserves only unchanged exact ref identities after refresh. */
@(test)
ref_selection_reconciles_exact_objects_without_substituting_same_named_refs :: proc(t: ^testing.T) {
	repository: Repository_Context
	ready := repository_context_assign(&repository, "/work/refs")
	testing.expect(t, ready)
	if !ready do return
	previous, previous_opened, previous_failure := ref_observation_open(
		repository, Ref_Generation(7), ref_test_output(), transmute([]u8)(string("origin\n")),
		transmute([]u8)(string(REF_TEST_SHA1 + "\n")), DEFAULT_REF_LIMITS,
	)
	testing.expectf(t, previous_opened, "previous Ref observation failed with %v", previous_failure)
	if !previous_opened do return
	defer ref_observation_close(&previous)
	selection, selected := ref_selection_begin(&previous)
	testing.expect(t, selected && ref_selection_is_current(&previous, selection))
	if !selected do return
	testing.expect(t, selection.current.kind == .Ref && selection.current.reference.kind == .Local_Branch)
	if selection.current.kind != .Ref || selection.current.reference.kind != .Local_Branch do return
	selection.marked = selection.current.reference
	next, next_opened, next_failure := ref_observation_open(
		repository, Ref_Generation(8), ref_test_output(), transmute([]u8)(string("origin\n")),
		transmute([]u8)(string(REF_TEST_SHA1 + "\n")), DEFAULT_REF_LIMITS,
	)
	testing.expectf(t, next_opened, "next Ref observation failed with %v", next_failure)
	if !next_opened do return
	defer ref_observation_close(&next)
	reconciled, retained, reconcile_failure := ref_selection_reconcile(&previous, &next, selection)
	testing.expectf(t, retained, "Ref selection reconciliation failed with %v", reconcile_failure)
	testing.expect(t, retained && ref_selection_is_current(&next, reconciled))
	testing.expect(t, ref_identity_same_object(reconciled.marked, selection.marked))
}
