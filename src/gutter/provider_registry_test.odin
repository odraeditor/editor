// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package gutter

import "base:runtime"
import "core:mem"
import "core:testing"

@(private = "file")
Programmable_Failing_Allocator :: struct {
	backing:                runtime.Allocator,
	fail_after:             u64,
	successful_allocations: u64,
}

@(private = "file")
programmable_failing_allocator_proc :: proc(
	allocator_data: rawptr,
	mode: runtime.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	location := #caller_location,
) -> ([]byte, runtime.Allocator_Error) {
	allocator := cast(^Programmable_Failing_Allocator)allocator_data
	if mode == .Alloc || mode == .Alloc_Non_Zeroed || mode == .Resize ||
	   mode == .Resize_Non_Zeroed {
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

@(private = "file")
Programmable_Test_Fixture :: struct {
	lanes:   [1]Programmable_Lane_Proposal,
	markers: [1]Programmable_Marker_Proposal,
}

@(private = "file")
programmable_test_fixture :: proc() -> Programmable_Test_Fixture {
	return {
		lanes = {{
			identity = "notes",
			side = .Right,
			order = 20,
			attachments = {.Logical_Line},
			width_policy = .Content_Presence,
			minimum_cells = 2,
			maximum_cells = 2,
			alignment = .Center,
			visibility = .When_Content,
			collision = .Highest_Priority,
			priority = 100,
			style_role = .Ordinary,
			separator = {kind = .Glyph, value = "│", fallback = "|"},
		}},
		markers = {{
			identity = "review",
			logical_line = 4,
			style_role = .Diagnostic_Information,
			priority = 10,
			representation = {kind = .Glyph, value = "◆", fallback = "*"},
			detail = "Review this line",
		}},
	}
}

@(private = "file")
programmable_test_proposal :: proc(
	fixture: ^Programmable_Test_Fixture,
	definition_generation := Provider_Generation(1),
	marker_generation := Marker_Generation_ID(1),
) -> Programmable_Provider_Proposal {
	assert(fixture != nil)
	return {
		definition_generation = definition_generation,
		marker_generation = marker_generation,
		name = "Personal Notes",
		package_name = "personal-notes",
		complete = true,
		lanes = fixture.lanes[:],
		markers = fixture.markers[:],
	}
}

@(test)
/* Verifies one provider prepares, confirms, activates, replaces, and tears down exactly. */
programmable_registry_runs_complete_lifecycle :: proc(t: ^testing.T) {
	registry: Programmable_Registry
	fixture := programmable_test_fixture()
	ready, _ := programmable_registry_init(&registry)
	if !testing.expect(t, ready) do return
	defer programmable_registry_close(&registry)

	candidate, prepared, failure := programmable_registry_prepare(
		&registry,
		1,
		programmable_test_proposal(&fixture),
	)
	testing.expectf(t, prepared, "prepare failed: %v", failure.code)
	if !prepared do return
	defer if candidate.data != nil do programmable_provider_candidate_close(&candidate)
	confirmed, _ := programmable_provider_candidate_confirm(&candidate)
	testing.expect(t, confirmed)
	activated, activation_failure := programmable_registry_activate(&registry, &candidate)
	testing.expectf(t, activated, "activate failed: %v", activation_failure.code)

	view, viewed, view_failure := programmable_registry_turn_begin(&registry)
	testing.expectf(t, viewed, "view failed: %v", view_failure.code)
	if viewed {
		testing.expect_value(t, view.descriptor.name, "Personal Notes")
		testing.expect_value(t, len(view.lanes), 1)
		testing.expect_value(t, len(view.publication.markers), 1)
		ended, _ := programmable_registry_turn_end(&registry)
		testing.expect(t, ended)
	}

	replacement, replaced, replace_failure := programmable_registry_prepare(
		&registry,
		2,
		programmable_test_proposal(&fixture, 2, 2),
	)
	testing.expectf(t, replaced, "replacement prepare failed: %v", replace_failure.code)
	if replaced {
		programmable_provider_candidate_confirm(&replacement)
		activated, activation_failure = programmable_registry_activate(&registry, &replacement)
		testing.expectf(t, activated, "replacement activate failed: %v", activation_failure.code)
	}
	descriptor, generation, turns, _, inspected := programmable_registry_inspect(&registry)
	testing.expect(t, inspected)
	testing.expect_value(t, generation, u64(3))
	testing.expect_value(t, turns, u16(0))
	testing.expect_value(t, descriptor.definition_generation, Provider_Generation(2))

	removed, remove_failure := programmable_registry_remove(&registry, generation)
	testing.expectf(t, removed, "remove failed: %v", remove_failure.code)
	descriptor, generation, _, _, inspected = programmable_registry_inspect(&registry)
	testing.expect(t, inspected)
	testing.expect_value(t, descriptor.provider, Provider_ID(0))
	testing.expect_value(t, generation, u64(4))
}

@(test)
/* Verifies stale, malformed, and active-turn candidates preserve last-valid data. */
programmable_registry_keeps_last_valid_provider :: proc(t: ^testing.T) {
	registry: Programmable_Registry
	fixture := programmable_test_fixture()
	ready, _ := programmable_registry_init(&registry)
	if !testing.expect(t, ready) do return
	defer programmable_registry_close(&registry)
	candidate, prepared, _ := programmable_registry_prepare(
		&registry, 1, programmable_test_proposal(&fixture),
	)
	if !testing.expect(t, prepared) do return
	programmable_provider_candidate_confirm(&candidate)
	activated, _ := programmable_registry_activate(&registry, &candidate)
	if !testing.expect(t, activated) do return

	_, stale_prepared, failure := programmable_registry_prepare(
		&registry,
		1,
		programmable_test_proposal(&fixture, 2, 2),
	)
	testing.expect(t, !stale_prepared)
	testing.expect_value(t, failure.code, Failure_Code.Stale_Generation)

	view, viewed, _ := programmable_registry_turn_begin(&registry)
	if !testing.expect(t, viewed) do return
	testing.expect_value(t, view.descriptor.definition_generation, Provider_Generation(1))
	_, turn_prepared, turn_failure := programmable_registry_prepare(
		&registry,
		2,
		programmable_test_proposal(&fixture, 2, 2),
	)
	testing.expect(t, !turn_prepared)
	testing.expect_value(t, turn_failure.code, Failure_Code.Active_Turn)
	programmable_registry_turn_end(&registry)

	malformed := programmable_test_proposal(&fixture, 2, 2)
	malformed.package_name = "Invalid Package"
	_, malformed_prepared, malformed_failure := programmable_registry_prepare(&registry, 2, malformed)
	testing.expect(t, !malformed_prepared)
	testing.expect_value(t, malformed_failure.code, Failure_Code.Invalid_Request)

	view, viewed, _ = programmable_registry_turn_begin(&registry)
	if viewed {
		testing.expect_value(t, view.descriptor.definition_generation, Provider_Generation(1))
		programmable_registry_turn_end(&registry)
	}
}

@(test)
/* Verifies suspension, failure reporting, resume, and candidate discard are bounded. */
suspension_and_discard_preserve_registry_state :: proc(t: ^testing.T) {
	registry: Programmable_Registry
	fixture := programmable_test_fixture()
	ready, _ := programmable_registry_init(&registry)
	if !testing.expect(t, ready) do return
	defer programmable_registry_close(&registry)
	candidate, prepared, _ := programmable_registry_prepare(
		&registry, 1, programmable_test_proposal(&fixture),
	)
	if !prepared do return
	programmable_provider_candidate_confirm(&candidate)
	programmable_registry_activate(&registry, &candidate)

	suspended, _ := programmable_registry_suspend(&registry, 2)
	testing.expect(t, suspended)
	_, viewed, failure := programmable_registry_turn_begin(&registry)
	testing.expect(t, !viewed)
	testing.expect_value(t, failure.code, Failure_Code.Provider_Suspended)
	resumed, _ := programmable_registry_resume(&registry, 3)
	testing.expect(t, resumed)

	replacement, replacement_prepared, _ := programmable_registry_prepare(
		&registry,
		4,
		programmable_test_proposal(&fixture, 2, 2),
	)
	if replacement_prepared {
		discarded, _ := programmable_provider_candidate_close(&replacement)
		testing.expect(t, discarded)
	}
	recorded, _ := programmable_registry_fail(
		&registry,
		Failure_Context{operation = .Prepare, code = .Invalid_Marker},
	)
	testing.expect(t, recorded)
	descriptor, _, _, latest, inspected := programmable_registry_inspect(&registry)
	testing.expect(t, inspected)
	testing.expect_value(t, descriptor.state, Programmable_Provider_State.Failed)
	testing.expect_value(t, latest.code, Failure_Code.Invalid_Marker)
}

@(test)
/* programmable_registry_enforces_publication_and_action_limits. */
registry_enforces_publication_and_action_limits :: proc(t: ^testing.T) {
	registry: Programmable_Registry
	fixture := programmable_test_fixture()
	ready, _ := programmable_registry_init(&registry)
	if !testing.expect(t, ready) do return
	defer programmable_registry_close(&registry)

	incomplete := programmable_test_proposal(&fixture)
	incomplete.complete = false
	_, accepted, failure := programmable_registry_prepare(&registry, 1, incomplete)
	testing.expect(t, !accepted)
	testing.expect_value(t, failure.code, Failure_Code.Invalid_Request)

	cancelled := programmable_test_proposal(&fixture)
	cancelled.cancelled = true
	_, accepted, failure = programmable_registry_prepare(&registry, 1, cancelled)
	testing.expect(t, !accepted)
	testing.expect_value(t, failure.code, Failure_Code.Cancelled)

	too_many_lanes: [MAX_PROGRAMMABLE_LANES_PER_PROVIDER + 1]Programmable_Lane_Proposal
	for &lane in too_many_lanes do lane = fixture.lanes[0]
	over_lane := programmable_test_proposal(&fixture)
	over_lane.lanes = too_many_lanes[:]
	_, accepted, failure = programmable_registry_prepare(&registry, 1, over_lane)
	testing.expect(t, !accepted)
	testing.expect_value(t, failure.code, Failure_Code.Invalid_Request)

	over_action := programmable_test_proposal(&fixture)
	over_action.markers[0].action_count = MAX_ACTIONS_PER_MARKER + 1
	_, accepted, failure = programmable_registry_prepare(&registry, 1, over_action)
	testing.expect(t, !accepted)
	testing.expect_value(t, failure.code, Failure_Code.Invalid_Marker)
}

@(test)
/* programmable_registry_contains_allocation_faults_without_retained_bytes. */
allocation_faults_leave_no_registry_bytes :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	backing := mem.tracking_allocator(&tracking)
	failing := Programmable_Failing_Allocator{backing = backing, fail_after = 2}
	allocator := runtime.Allocator {
		procedure = programmable_failing_allocator_proc,
		data = &failing,
	}
	registry: Programmable_Registry
	ready, _ := programmable_registry_init(&registry, allocator)
	if !testing.expect(t, ready) do return
	fixture := programmable_test_fixture()
	_, prepared, failure := programmable_registry_prepare(
		&registry, 1, programmable_test_proposal(&fixture),
	)
	testing.expect(t, !prepared)
	testing.expect_value(t, failure.code, Failure_Code.Allocation)
	closed, _ := programmable_registry_close(&registry)
	testing.expect(t, closed)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&tracking)
}
