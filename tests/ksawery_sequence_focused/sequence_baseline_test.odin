// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery_sequence_focused

import ksawery "../../src/ksawery"
import "base:runtime"
import "core:fmt"
import "core:mem"
import "core:testing"

Sequence_Failing_Allocator :: struct {
	backing:                runtime.Allocator,
	fail_after:             u64,
	successful_allocations: u64,
}

/* Verifies the focused harness compiles the delivered Ksawery package and sequence vocabulary. */
@(test)
production_sequence_baseline_is_available :: proc(t: ^testing.T) {
	testing.expect(t, ksawery.process_limits_are_valid(ksawery.DEFAULT_PROCESS_LIMITS))
	testing.expect_value(t, ksawery.Operation_State.Normal, ksawery.Operation_State.Normal)
	testing.expect_value(t, ksawery.Operation_State.Merging, ksawery.Operation_State.Merging)
	testing.expect_value(t, ksawery.Operation_State.Rebasing, ksawery.Operation_State.Rebasing)
	testing.expect_value(t, ksawery.Operation_State.Cherry_Picking, ksawery.Operation_State.Cherry_Picking)
	testing.expect_value(t, ksawery.Operation_State.Reverting, ksawery.Operation_State.Reverting)
	testing.expect_value(t, ksawery.Operation_State.Bisecting, ksawery.Operation_State.Bisecting)
	testing.expect_value(t, ksawery.Operation_State.Applying_Patches, ksawery.Operation_State.Applying_Patches)
	testing.expect_value(t, ksawery.Operation_State.Other_Sequence, ksawery.Operation_State.Other_Sequence)
}

/* Verifies the delivered Status parser retains unmerged paths as semantic targets. */
@(test)
production_status_retains_unmerged_paths :: proc(t: ^testing.T) {
	repository: ksawery.Repository_Context
	testing.expect(t, ksawery.repository_context_assign(&repository, "/tmp/odra-ksawery-sequence-focused"))
	output := transmute([]u8)(string(
		"# branch.head main\x00" +
		"u UU N... 100644 100644 100644 100644 0123456789012345678901234567890123456789 1234567890123456789012345678901234567890 2345678901234567890123456789012345678901 conflict.txt\x00",
	))
	observation, opened, failure := ksawery.status_observation_open(
		repository,
		ksawery.Observation_Generation(1),
		output,
		nil,
		ksawery.DEFAULT_PROCESS_LIMITS,
	)
	testing.expectf(t, opened, "status observation failed with %v", failure)
	if !opened do return
	defer ksawery.status_observation_close(&observation)
	count, counted := ksawery.status_observation_path_count(&observation)
	testing.expect(t, counted)
	testing.expect_value(t, count, u32(1))
	path, found := ksawery.status_observation_path(&observation, 0)
	testing.expect(t, found)
	testing.expect_value(t, path.group, ksawery.Change_Group.Unmerged)
}

/* Verifies one external sequence retains exact progress and conflict index stages. */
@(test)
sequence_observation_retains_exact_conflict_state :: proc(t: ^testing.T) {
	repository: ksawery.Repository_Context
	testing.expect(t, ksawery.repository_context_assign(&repository, "/tmp/odra-ksawery-sequence-focused"))
	current, target := sequence_test_identities(t)
	source := ksawery.Sequence_Source {
		kind = .Rebase,
		origin = .External,
		marker_mask = 2,
		current = current,
		target = target,
		step = {position = 2, total = 5},
		metadata_bytes = 48,
		supported = true,
	}
	output := transmute([]u8)(string(
		"# branch.oid 0123456789012345678901234567890123456789\x00" +
		"u UU N... 100644 100644 100644 100644 0123456789012345678901234567890123456789 1234567890123456789012345678901234567890 2345678901234567890123456789012345678901 conflict.txt\x00",
	))
	observation, opened, failure := ksawery.sequence_observation_open(
		repository,
		ksawery.Sequence_Generation(7),
		source,
		output,
	)
	testing.expectf(t, opened, "sequence observation failed with %v", failure)
	if !opened do return
	defer ksawery.sequence_observation_close(&observation)
	descriptor, described := ksawery.sequence_observation_descriptor(&observation)
	testing.expect(t, described)
	testing.expect_value(t, descriptor.state, ksawery.Sequence_Observation_State.Conflicted)
	testing.expect_value(t, descriptor.step, ksawery.Sequence_Step{position = 2, total = 5})
	testing.expect(t, descriptor.actions.inspect)
	testing.expect(t, ksawery.sequence_target_is_valid({
		generation = descriptor.generation,
		fingerprint = descriptor.fingerprint,
	}))
	conflict, found := ksawery.sequence_observation_conflict(&observation, 0)
	testing.expect(t, found)
	path, path_found := ksawery.sequence_observation_conflict_path(&observation, conflict)
	testing.expect(t, path_found)
	testing.expect_value(t, path, "conflict.txt")
	testing.expect_value(t, conflict.kind, ksawery.Conflict_Kind.Both_Modified)
	for index in 0 ..< 3 {
		testing.expect(t, conflict.stages[index].available)
		testing.expect(t, ksawery.revision_identity_is_valid(conflict.stages[index].object))
	}
}

/* Verifies retained conflict truncation is explicit and every owned allocation is released. */
@(test)
sequence_observation_truncates_and_cleans_up :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	repository: ksawery.Repository_Context
	testing.expect(t, ksawery.repository_context_assign(&repository, "/tmp/odra-ksawery-sequence-focused"))
	current, target := sequence_test_identities(t)
	source := ksawery.Sequence_Source {
		kind = .Merge,
		origin = .Associated,
		marker_mask = 1,
		current = current,
		target = target,
		metadata_bytes = 8,
		supported = true,
	}
	record :: "u UU N... 100644 100644 100644 100644 0123456789012345678901234567890123456789 1234567890123456789012345678901234567890 2345678901234567890123456789012345678901 conflict.txt\x00"
	output_text :: record + record
	output := transmute([]u8)(string(output_text))
	limits := ksawery.DEFAULT_SEQUENCE_LIMITS
	limits.conflicts = 1
	observation, opened, failure := ksawery.sequence_observation_open(
		repository,
		ksawery.Sequence_Generation(8),
		source,
		output,
		limits,
		allocator,
	)
	testing.expectf(t, opened, "truncated sequence observation failed with %v", failure)
	if opened {
		descriptor, described := ksawery.sequence_observation_descriptor(&observation)
		testing.expect(t, described)
		testing.expect_value(t, descriptor.state, ksawery.Sequence_Observation_State.Truncated)
		testing.expect_value(t, descriptor.conflict_count, u32(1))
		testing.expect_value(t, descriptor.observed_conflicts, u32(2))
		usage, measured := ksawery.sequence_observation_usage(&observation)
		testing.expect(t, measured)
		testing.expect_value(t, usage.conflicts, u32(1))
		testing.expect_value(t, usage.observed_conflicts, u32(2))
		testing.expect(t, usage.allocation_bytes > usage.path_bytes)
		ksawery.sequence_observation_close(&observation)
	}
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&tracking)
}

/* Verifies every admitted porcelain conflict pair and optional index stage is semantic. */
@(test)
sequence_observation_classifies_conflict_pairs :: proc(t: ^testing.T) {
	cases := [?]struct {pair: string, kind: ksawery.Conflict_Kind} {
		{"UU", .Both_Modified},
		{"AA", .Added_By_Both},
		{"UD", .Deleted_By_Them},
		{"DU", .Deleted_By_Us},
		{"AU", .Added_By_Us},
		{"UA", .Added_By_Them},
		{"DD", .Both_Deleted},
		{"XY", .Other},
	}
	repository: ksawery.Repository_Context
	testing.expect(t, ksawery.repository_context_assign(&repository, "/tmp/odra-ksawery-sequence-focused"))
	current, target := sequence_test_identities(t)
	source := ksawery.Sequence_Source {
		kind = .Cherry_Pick,
		origin = .External,
		marker_mask = 8,
		current = current,
		target = target,
		metadata_bytes = 40,
		supported = true,
	}
	for test_case, index in cases {
		output := fmt.aprintf(
			"u %s N... 000000 100644 100644 100644 0000000000000000000000000000000000000000 1234567890123456789012345678901234567890 2345678901234567890123456789012345678901 conflict-%d.txt%c",
			test_case.pair,
			index,
			u8(0),
		)
		observation, opened, failure := ksawery.sequence_observation_open(
			repository,
			ksawery.Sequence_Generation(index + 1),
			source,
			transmute([]u8)output,
		)
		testing.expectf(t, opened, "conflict pair %s failed with %v", test_case.pair, failure)
		if opened {
			conflict, found := ksawery.sequence_observation_conflict(&observation, 0)
			testing.expect(t, found)
			testing.expect_value(t, conflict.kind, test_case.kind)
			testing.expect(t, !conflict.stages[0].available)
			testing.expect(t, conflict.stages[1].available && conflict.stages[2].available)
			ksawery.sequence_observation_close(&observation)
		}
		delete(output)
	}
}

/* Verifies malformed and stale status payloads fail without publishing partial observations. */
@(test)
sequence_observation_rejects_malformed_and_stale_payloads :: proc(t: ^testing.T) {
	repository: ksawery.Repository_Context
	testing.expect(t, ksawery.repository_context_assign(&repository, "/tmp/odra-ksawery-sequence-focused"))
	current, target := sequence_test_identities(t)
	source := ksawery.Sequence_Source {
		kind = .Merge,
		origin = .External,
		marker_mask = 1,
		current = current,
		target = target,
		metadata_bytes = 40,
		supported = true,
	}
	_, malformed_opened, malformed_failure := ksawery.sequence_observation_open(
		repository,
		1,
		source,
		transmute([]u8)(string("u UU incomplete")),
	)
	testing.expect(t, !malformed_opened)
	testing.expect_value(t, malformed_failure, ksawery.Failure_Code.Parse)
	_, stale_opened, stale_failure := ksawery.sequence_observation_open(
		repository,
		2,
		source,
		transmute([]u8)(string("# branch.oid 2345678901234567890123456789012345678901\x00")),
	)
	testing.expect(t, !stale_opened)
	testing.expect_value(t, stale_failure, ksawery.Failure_Code.Stale_Observation)
}

/* Verifies allocation failure tears down all partially opened sequence ownership. */
@(test)
sequence_observation_allocation_failure_cleans_up :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	failing := Sequence_Failing_Allocator {
		backing = mem.tracking_allocator(&tracking),
		fail_after = 1,
	}
	repository: ksawery.Repository_Context
	testing.expect(t, ksawery.repository_context_assign(&repository, "/tmp/odra-ksawery-sequence-focused"))
	current, target := sequence_test_identities(t)
	_, opened, failure := ksawery.sequence_observation_open(
		repository,
		3,
		{
			kind = .Merge,
			origin = .External,
			marker_mask = 1,
			current = current,
			target = target,
			metadata_bytes = 40,
			supported = true,
		},
		nil,
		ksawery.DEFAULT_SEQUENCE_LIMITS,
		sequence_failing_allocator(&failing),
	)
	testing.expect(t, !opened)
	testing.expect_value(t, failure, ksawery.Failure_Code.Allocation)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&tracking)
}

/* Verifies History refresh preserves exact revision, parent, and marked identities across generations. */
@(test)
history_selection_reconciles_exact_identity_after_refresh :: proc(t: ^testing.T) {
	repository: ksawery.Repository_Context
	testing.expect(t, ksawery.repository_context_assign(&repository, "/tmp/odra-ksawery-history-refresh"))
	root :: "0123456789abcdef0123456789abcdef01234567"
	child :: "1234567890abcdef1234567890abcdef12345678"
	output := transmute([]u8)(string(
		"\x1e" + root + "\x00\x00Ada\x00ada@example.invalid\x002026-01-01T00:00:00+00:00\x002026-01-01T00:00:00+00:00\x00root\x00root body\x00" +
		"\x1e" + child + "\x00" + root + "\x00Ada\x00ada@example.invalid\x002026-01-02T00:00:00+00:00\x002026-01-02T00:00:00+00:00\x00child\x00child body\x00",
	))
	previous, previous_opened, previous_failure := ksawery.history_observation_open(
		repository, 801, output, {limits = ksawery.DEFAULT_HISTORY_LIMITS},
	)
	testing.expectf(t, previous_opened, "previous History observation failed with %v", previous_failure)
	if !previous_opened do return
	defer ksawery.history_observation_close(&previous)
	next, next_opened, next_failure := ksawery.history_observation_open(
		repository, 802, output, {limits = ksawery.DEFAULT_HISTORY_LIMITS},
	)
	testing.expectf(t, next_opened, "next History observation failed with %v", next_failure)
	if !next_opened do return
	defer ksawery.history_observation_close(&next)
	selection, selected := ksawery.history_selection_begin(&previous)
	if !selected do return
	next_selection, moved, _ := ksawery.history_selection_move(&previous, selection, .Next)
	if !moved do return
	selection, moved, _ = ksawery.history_selection_move(&previous, next_selection, .Next)
	testing.expect(t, moved && selection.current.kind == .Parent)
	root_identity: ksawery.Revision_Identity
	testing.expect(t, ksawery.revision_identity_assign(&root_identity, root))
	selection.marked = {generation = 801, revision = root_identity}
	reconciled, retained, reconcile_failure := ksawery.history_selection_reconcile(
		&previous, &next, selection,
	)
	testing.expectf(t, retained, "History selection reconciliation failed with %v", reconcile_failure)
	if retained {
		testing.expect(t, ksawery.history_selection_is_current(&next, reconciled))
		testing.expect_value(t, reconciled.generation, ksawery.History_Generation(802))
		testing.expect_value(t, reconciled.current.kind, ksawery.History_Item_Kind.Parent)
		testing.expect_value(t, reconciled.current.parent, root_identity)
		testing.expect_value(t, reconciled.marked.revision, root_identity)
	}
}

/* Verifies Sequence and Conflict emphasis always carries a monochrome fallback cue. */
@(test)
sequence_presentation_roles_are_monochrome_safe :: proc(t: ^testing.T) {
	current, current_ok := ksawery.presentation_role_compose({
		surface = .Sequence,
		subject = .Conflict,
		current = true,
	})
	testing.expect(t, current_ok && ksawery.presentation_role_is_valid(current))
	testing.expect_value(t, current.cue, ksawery.Presentation_Cue.Current)
	destructive, destructive_ok := ksawery.presentation_role_compose({
		surface = .Sequence,
		subject = .Operation,
		destructive = true,
	})
	testing.expect(t, destructive_ok && ksawery.presentation_role_is_valid(destructive))
	testing.expect_value(t, destructive.cue, ksawery.Presentation_Cue.Destructive)
	stage, stage_ok := ksawery.presentation_role_compose({surface = .Conflict, subject = .Stage})
	testing.expect(t, stage_ok && ksawery.presentation_role_is_valid(stage))
}

@(private)
sequence_test_identities :: proc(t: ^testing.T) -> (ksawery.Revision_Identity, ksawery.Revision_Identity) {
	current, target: ksawery.Revision_Identity
	testing.expect(t, ksawery.revision_identity_assign(&current, "0123456789012345678901234567890123456789"))
	testing.expect(t, ksawery.revision_identity_assign(&target, "1234567890123456789012345678901234567890"))
	return current, target
}

sequence_failing_allocator :: proc(state: ^Sequence_Failing_Allocator) -> runtime.Allocator {
	return {procedure = sequence_failing_allocator_proc, data = state}
}

sequence_failing_allocator_proc :: proc(
	allocator_data: rawptr,
	mode: runtime.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	location: runtime.Source_Code_Location,
) -> ([]byte, runtime.Allocator_Error) {
	allocator := cast(^Sequence_Failing_Allocator)allocator_data
	if mode == .Alloc || mode == .Resize || mode == .Resize_Non_Zeroed {
		if allocator.successful_allocations >= allocator.fail_after do return nil, .Out_Of_Memory
		allocator.successful_allocations += 1
	}
	return allocator.backing.procedure(
		allocator.backing.data,
		mode,
		size,
		alignment,
		old_memory,
		old_size,
		location,
	)
}
