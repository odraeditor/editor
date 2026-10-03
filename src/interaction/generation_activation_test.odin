// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package interaction

import "core:testing"

/* Verifies one compatible command and keymap generation publishes as a unit. */
@(test)
replaces_only_complete_pairs :: proc(t: ^testing.T) {
	active: Generation_Activation
	ready: bool
	active.registry, ready = layered_test_registry(t, Registry_Generation(701), context.allocator)
	if !ready do return
	fixture: Profile_Compatibility_Fixture
	profile_compatibility_fixture_prepare_buildable(&fixture)
	fixture.catalog.generation = 701
	completed, completion_failure := generation_activation_complete(
		&active,
		701,
		fixture.catalog,
		layered_active_context(1),
		Context_ID(2),
		context.allocator,
	)
	testing.expectf(t, completed, "active pair failed: %v", completion_failure.code)
	if !completed {
		_, _ = command_registry_close(&active.registry)
		return
	}
	defer generation_activation_close(&active)

	old_handle, old_found, _ := command_lookup(&active.registry, "cursor-previous-grapheme")
	testing.expect(t, old_found)

	candidate: Generation_Activation
	candidate.registry, ready = layered_test_registry(t, Registry_Generation(702), context.allocator)
	if !ready do return
	fixture.catalog.generation = 702
	completed, completion_failure = generation_activation_complete(
		&candidate,
		702,
		fixture.catalog,
		layered_active_context(1),
		Context_ID(2),
		context.allocator,
	)
	testing.expectf(t, completed, "candidate pair failed: %v", completion_failure.code)
	if !completed {
		_, _ = command_registry_close(&candidate.registry)
		return
	}
	pending := Pending_State{snapshot_generation = 1, stroke_count = 1}
	context_pending := Context_Pending_State{context_generation = 1, stroke_count = 1}
	published, publish_failure := generation_activation_publish(
		&active,
		&candidate,
		&pending,
		&context_pending,
	)
	testing.expectf(t, published, "pair publication failed: %v", publish_failure.code)
	testing.expect_value(t, active.generation, Registry_Generation(702))
	testing.expect_value(t, pending.stroke_count, u8(0))
	testing.expect_value(t, context_pending.stroke_count, u8(0))
	testing.expect(t, !candidate.ready)
	_, old_valid, old_failure := command_metadata(&active.registry, old_handle)
	testing.expect(t, !old_valid)
	testing.expect_value(t, old_failure.code, Failure_Code.Invalid_Command)
}

/* Verifies a rejected profile cannot replace the active registry generation. */
@(test)
rejects_incompatible_candidate_atomically :: proc(t: ^testing.T) {
	active: Generation_Activation
	ready: bool
	active.registry, ready = layered_test_registry(t, Registry_Generation(711), context.allocator)
	if !ready do return
	fixture: Profile_Compatibility_Fixture
	profile_compatibility_fixture_prepare_buildable(&fixture)
	fixture.catalog.generation = 711
	completed, _ := generation_activation_complete(
		&active, 711, fixture.catalog, layered_active_context(1), Context_ID(2), context.allocator)
	if !completed {
		_, _ = command_registry_close(&active.registry)
		return
	}
	defer generation_activation_close(&active)

	candidate: Generation_Activation
	candidate.registry, ready = layered_test_registry(t, Registry_Generation(712), context.allocator)
	if !ready do return
	fixture.catalog.generation = 712
	fixture.direct_bindings[0].command_name = "missing-personal-command"
	failure: Failure_Context
	completed, failure = generation_activation_complete(
		&candidate, 712, fixture.catalog, layered_active_context(1), Context_ID(2), context.allocator)
	testing.expect(t, !completed)
	testing.expect_value(t, failure.code, Failure_Code.Unknown_Command)
	_, _ = command_registry_close(&candidate.registry)
	testing.expect_value(t, active.generation, Registry_Generation(711))
	_, active_found, _ := command_lookup(&active.registry, "cursor-previous-grapheme")
	testing.expect(t, active_found)
}
