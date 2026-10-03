// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery_extension_focused

import ksawery "../../src/ksawery"
import odra "../../src/ksawery_module"
import "base:runtime"
import "core:encoding/endian"
import "core:mem"
import "core:testing"

Extension_Fault_Allocator :: struct {
	backing:                runtime.Allocator,
	fail_after:             u64,
	successful_allocations: u64,
}

/* Builds the exact one-contributor copied declaration emitted by the Racket facade. */
extension_provider_batch :: proc(personal_generation, contributor_generation: u64) -> [dynamic]u8 {
	identity :: "personal.repository-tools"
	label :: "Repository tools"
	provenance :: "/tmp/config/odra/init.rkt"
	contribution_identity :: "status.ahead-behind"
	text := identity + label + provenance + contribution_identity
	record_bytes := 96 + 128 + 64 + 112 + len(text)
	words := [?]u64 {
		1, u64(record_bytes), 1, personal_generation, 1, 1, u64(len(text)), 0, 1, 0, 0, 0,
		1, contributor_generation, 2, 1,
		0, u64(len(identity)), u64(len(identity)), u64(len(label)),
		u64(len(identity) + len(label)), u64(len(provenance)),
		3, 0, 1, 0, 0, 0,
		7, 3, 0, 1, 3,
		u64(len(identity) + len(label) + len(provenance)), u64(len(contribution_identity)), 0,
		8, 16, 128, 1 * 1_024 * 1_024, 1 * 1_024 * 1_024,
		1 * 1_024 * 1_024, 256 * 1_024, 4 * 1_024, 250_000_000,
		32 * 1_024 * 1_024, 64, 1, 32 * 1_024 * 1_024, 32 * 1_024 * 1_024,
	}
	result, allocation_error := make([dynamic]u8, record_bytes)
	assert(allocation_error == nil)
	for value, index in words do assert(endian.put_u64(result[index * 8:], .Little, value))
	copy(result[len(words) * 8:], transmute([]u8)text)
	return result
}

/* Builds one valid dynamic turn over the active test contributor. */
extension_provider_scope :: proc(generation: u64) -> ksawery.Extension_Turn_Scope {
	repository: ksawery.Repository_Context
	assert(ksawery.repository_context_assign(&repository, "/tmp/odra-ksawery-extension"))
	return {
		turn = 11,
		contributor = {contributor = 1, generation = ksawery.Contributor_Generation(generation)},
		repository = repository,
		repository_generation = 13,
		worktree_generation = 17,
		observation_generation = 19,
		surface = .Status,
		surface_generation = 23,
		selection_generation = 29,
		target = {kind = .Path, generation = 19, identity = 31},
		capability_generation = 1,
		owner_thread = 37,
		deadline_ns = ksawery.DEFAULT_EXTENSION_TURN_DEADLINE_NS,
		callback_budget = ksawery.DEFAULT_EXTENSION_CALLBACKS_PER_TURN,
	}
}

/* Verifies full generations publish atomically, preserve provenance, replace, and disable. */
@(test)
extension_provider_lifecycle_is_atomic :: proc(t: ^testing.T) {
	registry: odra.Ksawery_Extension_Provider_Registry
	testing.expect(t, odra.ksawery_extension_provider_registry_init(&registry))
	defer odra.ksawery_extension_provider_registry_close(&registry)
	first_bytes := extension_provider_batch(2, 5)
	defer delete(first_bytes)
	first, prepared, failure := odra.ksawery_extension_provider_prepare(&registry, first_bytes[:], 2)
	testing.expectf(t, prepared, "prepare failed with %v", failure)
	if !prepared do return
	defer if first.data != nil do odra.ksawery_extension_provider_candidate_close(&first)
	testing.expect(t, odra.ksawery_extension_provider_candidate_confirm(&first))
	activated, activate_failure := odra.ksawery_extension_provider_activate(&registry, &first)
	testing.expectf(t, activated, "activate failed with %v", activate_failure)
	inspection, inspected := odra.ksawery_extension_provider_inspect(&registry)
	testing.expect(t, inspected)
	testing.expect_value(t, inspection.lifecycle, ksawery.Contributor_Lifecycle.Active)
	testing.expect_value(t, inspection.handle.generation, ksawery.Contributor_Generation(5))
	testing.expect_value(t, inspection.provenance.origin, ksawery.Contributor_Origin.Personal)

	malformed := extension_provider_batch(3, 6)
	defer delete(malformed)
	assert(endian.put_u64(malformed[8:], .Little, u64(len(malformed) + 1)))
	_, malformed_ok, _ := odra.ksawery_extension_provider_prepare(&registry, malformed[:], 3)
	testing.expect(t, !malformed_ok)
	inspection, inspected = odra.ksawery_extension_provider_inspect(&registry)
	testing.expect(t, inspected)
	testing.expect_value(t, inspection.handle.generation, ksawery.Contributor_Generation(5))

	replacement_bytes := extension_provider_batch(3, 6)
	defer delete(replacement_bytes)
	replacement, replacement_ok, _ := odra.ksawery_extension_provider_prepare(&registry, replacement_bytes[:], 3)
	testing.expect(t, replacement_ok)
	if !replacement_ok do return
	defer if replacement.data != nil do odra.ksawery_extension_provider_candidate_close(&replacement)
	testing.expect(t, odra.ksawery_extension_provider_candidate_confirm(&replacement))
	replaced, _ := odra.ksawery_extension_provider_activate(&registry, &replacement)
	testing.expect(t, replaced)
	inspection, inspected = odra.ksawery_extension_provider_inspect(&registry)
	testing.expect(t, inspected)
	testing.expect_value(t, inspection.handle.generation, ksawery.Contributor_Generation(6))
	disabled, _ := odra.ksawery_extension_provider_disable(&registry, inspection.handle)
	testing.expect(t, disabled)
	inspection, inspected = odra.ksawery_extension_provider_inspect(&registry)
	testing.expect(t, inspected)
	testing.expect_value(t, inspection.lifecycle, ksawery.Contributor_Lifecycle.Disabled)
}

/* Verifies disablement revokes turns, rejects repetition, and admits one later generation. */
@(test)
extension_provider_disablement_revokes_and_recovers :: proc(t: ^testing.T) {
	registry: odra.Ksawery_Extension_Provider_Registry
	testing.expect(t, odra.ksawery_extension_provider_registry_init(&registry))
	defer odra.ksawery_extension_provider_registry_close(&registry)
	first_bytes := extension_provider_batch(2, 5)
	defer delete(first_bytes)
	first, prepared, _ := odra.ksawery_extension_provider_prepare(&registry, first_bytes[:], 2)
	testing.expect(t, prepared)
	if !prepared do return
	testing.expect(t, odra.ksawery_extension_provider_candidate_confirm(&first))
	activated, _ := odra.ksawery_extension_provider_activate(&registry, &first)
	testing.expect(t, activated)
	inspection, inspected := odra.ksawery_extension_provider_inspect(&registry)
	testing.expect(t, inspected)
	disabled, disable_failure := odra.ksawery_extension_provider_disable(&registry, inspection.handle)
	testing.expectf(t, disabled, "disable failed with %v", disable_failure)
	_, turn_started, turn_failure := odra.ksawery_extension_provider_turn_begin(
		&registry,
		extension_provider_scope(5),
		{.Inspect},
	)
	testing.expect(t, !turn_started)
	testing.expect_value(t, turn_failure.code, ksawery.Extension_Failure_Code.Stale_Contributor)
	repeated, repeated_failure := odra.ksawery_extension_provider_disable(&registry, inspection.handle)
	testing.expect(t, !repeated)
	testing.expect_value(t, repeated_failure.code, ksawery.Extension_Failure_Code.Stale_Contributor)

	replacement_bytes := extension_provider_batch(3, 6)
	defer delete(replacement_bytes)
	replacement, replacement_prepared, _ := odra.ksawery_extension_provider_prepare(
		&registry,
		replacement_bytes[:],
		3,
	)
	testing.expect(t, replacement_prepared)
	if !replacement_prepared do return
	defer if replacement.data != nil do odra.ksawery_extension_provider_candidate_close(&replacement)
	testing.expect(t, odra.ksawery_extension_provider_candidate_confirm(&replacement))
	reactivated, _ := odra.ksawery_extension_provider_activate(&registry, &replacement)
	testing.expect(t, reactivated)
	inspection, inspected = odra.ksawery_extension_provider_inspect(&registry)
	testing.expect(t, inspected)
	testing.expect_value(t, inspection.handle.generation, ksawery.Contributor_Generation(6))
	testing.expect_value(t, inspection.lifecycle, ksawery.Contributor_Lifecycle.Active)
}

/* Verifies thread, reentrancy, staleness, timeout, and memory revocation. */
@(test)
extension_provider_turns_are_scoped_and_bounded :: proc(t: ^testing.T) {
	registry: odra.Ksawery_Extension_Provider_Registry
	testing.expect(t, odra.ksawery_extension_provider_registry_init(&registry))
	defer odra.ksawery_extension_provider_registry_close(&registry)
	batch := extension_provider_batch(2, 5)
	defer delete(batch)
	candidate, prepared, _ := odra.ksawery_extension_provider_prepare(&registry, batch[:], 2)
	testing.expect(t, prepared)
	if !prepared do return
	testing.expect(t, odra.ksawery_extension_provider_candidate_confirm(&candidate))
	activated, _ := odra.ksawery_extension_provider_activate(&registry, &candidate)
	testing.expect(t, activated)
	scope := extension_provider_scope(5)
	capability, began, begin_failure := odra.ksawery_extension_provider_turn_begin(
		&registry, scope, {.Inspect, .Present})
	testing.expectf(t, began, "turn failed with %v", begin_failure)
	if !began do return
	current := scope
	current.capability_generation = capability.generation
	_, nested, nested_failure := odra.ksawery_extension_provider_turn_begin(&registry, scope, {.Inspect})
	testing.expect(t, !nested)
	testing.expect_value(t, nested_failure.code, ksawery.Extension_Failure_Code.Reentrant_Turn)
	wrong_thread, wrong_thread_failure := odra.ksawery_extension_provider_authorize(
		&registry, capability, current, 41, .Inspect, 1, 1)
	testing.expect(t, !wrong_thread)
	testing.expect_value(t, wrong_thread_failure.code, ksawery.Extension_Failure_Code.Wrong_Thread)
	stale := current
	stale.observation_generation += 1
	stale_ok, stale_failure := odra.ksawery_extension_provider_authorize(
		&registry, capability, stale, 37, .Inspect, 1, 1)
	testing.expect(t, !stale_ok)
	testing.expect_value(t, stale_failure.code, ksawery.Extension_Failure_Code.Stale_Observation)
	timed, timeout_failure := odra.ksawery_extension_provider_authorize(
		&registry, capability, current, 37, .Inspect,
		ksawery.DEFAULT_EXTENSION_TURN_DEADLINE_NS + 1, 1)
	testing.expect(t, !timed)
	testing.expect_value(t, timeout_failure.code, ksawery.Extension_Failure_Code.Timeout)
	within_memory, memory_failure := odra.ksawery_extension_provider_authorize(
		&registry, capability, current, 37, .Inspect, 1,
		ksawery.DEFAULT_EXTENSION_CUSTODIAN_MEMORY_BYTES + 1)
	testing.expect(t, !within_memory)
	testing.expect_value(t, memory_failure.code, ksawery.Extension_Failure_Code.Memory_Limit)
	authorized, _ := odra.ksawery_extension_provider_authorize(
		&registry, capability, current, 37, .Inspect, 1, 1)
	testing.expect(t, authorized)
	registry.active.active_scope.callback_budget = 1
	current.callback_budget = 1
	callback_admitted, callback_failure := odra.ksawery_extension_provider_authorize(
		&registry, capability, current, 37, .Inspect, 1, 1)
	testing.expect(t, !callback_admitted)
	testing.expect_value(t, callback_failure.code, ksawery.Extension_Failure_Code.Callback_Limit)
	testing.expect(t, odra.ksawery_extension_provider_turn_end(&registry))
	authorized, stale_failure = odra.ksawery_extension_provider_authorize(
		&registry, capability, current, 37, .Inspect, 1, 1)
	testing.expect(t, !authorized)
	testing.expect_value(t, stale_failure.code, ksawery.Extension_Failure_Code.Stale_Capability)
}

/* Verifies allocation failure preserves the prior generation and teardown retains zero bytes. */
@(test)
extension_provider_allocation_failure_rolls_back_and_cleans_up :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	backing := mem.tracking_allocator(&tracking)
	fault := Extension_Fault_Allocator{backing = backing, fail_after = max(u64)}
	registry: odra.Ksawery_Extension_Provider_Registry
	testing.expect(t, odra.ksawery_extension_provider_registry_init(
		&registry, extension_fault_allocator(&fault)))
	first_bytes := extension_provider_batch(2, 5)
	first, prepared, _ := odra.ksawery_extension_provider_prepare(&registry, first_bytes[:], 2)
	testing.expect(t, prepared)
	testing.expect(t, odra.ksawery_extension_provider_candidate_confirm(&first))
	activated, _ := odra.ksawery_extension_provider_activate(&registry, &first)
	testing.expect(t, activated)
	fault.fail_after = fault.successful_allocations
	replacement_bytes := extension_provider_batch(3, 6)
	_, replacement_ok, allocation_failure := odra.ksawery_extension_provider_prepare(
		&registry, replacement_bytes[:], 3)
	testing.expect(t, !replacement_ok)
	testing.expect_value(t, allocation_failure.code, ksawery.Extension_Failure_Code.Allocation)
	inspection, inspected := odra.ksawery_extension_provider_inspect(&registry)
	testing.expect(t, inspected)
	testing.expect_value(t, inspection.handle.generation, ksawery.Contributor_Generation(5))
	fault.fail_after = max(u64)
	testing.expect(t, odra.ksawery_extension_provider_registry_close(&registry))
	delete(first_bytes)
	delete(replacement_bytes)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&tracking)
}

extension_fault_allocator :: proc(state: ^Extension_Fault_Allocator) -> runtime.Allocator {
	return {procedure = extension_fault_allocator_proc, data = state}
}

extension_fault_allocator_proc :: proc(
	allocator_data: rawptr,
	mode: runtime.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	location: runtime.Source_Code_Location,
) -> ([]byte, runtime.Allocator_Error) {
	state := cast(^Extension_Fault_Allocator)allocator_data
	if mode == .Alloc || mode == .Alloc_Non_Zeroed || mode == .Resize ||
	   mode == .Resize_Non_Zeroed {
		if state.successful_allocations >= state.fail_after do return nil, .Out_Of_Memory
		state.successful_allocations += 1
	}
	return state.backing.procedure(
		state.backing.data, mode, size, alignment, old_memory, old_size, location)
}
