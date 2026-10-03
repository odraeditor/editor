// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package theme_reference

import "base:runtime"
import "core:mem"
import "core:testing"

/* Ensures bootstrap selects the factory night theme while retaining a safe baseline. */
@(test)
bootstrap_selects_night_baseline :: proc(t: ^testing.T) {
	model, initialized, failure := model_init()
	testing.expectf(t, initialized, "theme model init failed with %v", failure.code)
	defer model_close(&model)
	selection, inspected := model_selection(&model)

	testing.expect(t, inspected && model_valid(&model))
	testing.expect_value(t, model.state.provider_count, u16(1))
	testing.expect_value(t, model.state.definition_count, u16(FACTORY_DEFINITIONS))
	testing.expect_value(t, selection.active, selection.fallback)
	testing.expect_value(t, selection.fallback.id, u16(4))
	testing.expect_value(t, selection.baseline.id, u16(5))
}

/* Ensures proposal, confirmation, and selection require current generations. */
@(test)
proposal_selection_check_generation :: proc(t: ^testing.T) {
	model, _, _ := model_init()
	defer model_close(&model)
	proposal := test_proposal(2, 20, 1_024)
	proposed, proposed_ok, _ := model_propose(&model, proposal)
	registry := model.state.selection.registry_generation
	confirmed, confirmed_ok, _ := model_confirm(&model, registry, proposed)
	before := model.state.selection
	selected, selected_ok, _ := model_select(&model, before.selection_generation, confirmed)
	_, stale_ok, stale := model_select(&model, before.selection_generation, selected.fallback)

	testing.expect(t, proposed_ok && confirmed_ok && selected_ok && !stale_ok)
	testing.expect_value(t, stale.code, Failure_Code.Stale_Selection)
	testing.expect_value(t, selected.active, confirmed)
	testing.expect(t, model_valid(&model))
}

/* Ensures replacement rollback and disable leave exactly one selected theme. */
@(test)
rollback_keeps_single_selection :: proc(t: ^testing.T) {
	model, _, _ := model_init()
	defer model_close(&model)
	proposed, _, _ := model_propose(&model, test_proposal(2, 20, 1_024))
	confirmed, _, _ := model_confirm(
		&model,
		model.state.selection.registry_generation,
		proposed,
	)
	selected, _, _ := model_select(
		&model,
		model.state.selection.selection_generation,
		confirmed,
	)
	replaced_selection, replacement, replaced, _ := model_replace(
		&model,
		selected.selection_generation,
		confirmed,
		2_048,
	)
	rolled_back, rollback_ok, _ := model_restore_fallback(
		&model,
		replaced_selection.selection_generation,
	)
	disabled, disabled_ok, _ := model_disable(
		&model,
		rolled_back.selection_generation,
	)

	testing.expect(t, replaced && rollback_ok && disabled_ok)
	testing.expect_value(t, replacement.generation, confirmed.generation + 1)
	testing.expect_value(t, rolled_back.active, rolled_back.fallback)
	testing.expect_value(t, disabled.active, disabled.baseline)
	testing.expect(t, model_valid(&model))
}

/* Ensures provider failure and teardown restore the factory theme. */
@(test)
provider_failure_restores_factory :: proc(t: ^testing.T) {
	model, _, _ := model_init()
	defer model_close(&model)
	proposed, _, _ := model_propose(&model, test_proposal(2, 20, 1_024))
	confirmed, _, _ := model_confirm(
		&model,
		model.state.selection.registry_generation,
		proposed,
	)
	selected, _, _ := model_select(
		&model,
		model.state.selection.selection_generation,
		confirmed,
	)
	failed_selection, failed, _ := model_fail_provider(
		&model,
		selected.selection_generation,
		confirmed.provider,
	)

	testing.expect(t, failed)
	testing.expect_value(t, failed_selection.active, failed_selection.fallback)
	testing.expect_value(t, model.state.definition_count, u16(FACTORY_DEFINITIONS))

	second, _, _ := model_propose(&model, test_proposal(3, 21, 1_024))
	second_confirmed, _, _ := model_confirm(
		&model,
		model.state.selection.registry_generation,
		second,
	)
	second_selected, _, _ := model_select(
		&model,
		model.state.selection.selection_generation,
		second_confirmed,
	)
	closed_selection, closed, _ := model_close_provider(
		&model,
		second_selected.selection_generation,
		second_confirmed.provider,
	)
	testing.expect(t, closed)
	testing.expect_value(t, closed_selection.active, closed_selection.fallback)
	testing.expect(t, model_valid(&model))
}

/* Ensures excessive theme proposals cannot partially mutate the registry. */
@(test)
proposal_limits_reject_without_partial_mutation :: proc(t: ^testing.T) {
	limits := DEFAULT_LIMITS
	limits.providers = 2
	limits.definitions = FACTORY_DEFINITIONS + 1
	limits.retained_bytes = FACTORY_DEFINITIONS * FACTORY_PAYLOAD_BYTES + 1_024
	model, initialized, _ := model_init(limits)
	testing.expect(t, initialized)
	defer model_close(&model)
	before := model.state.selection

	invalid := test_proposal(2, 20, 1_024)
	invalid.identity_bytes = MAX_IDENTITY_BYTES + 1
	_, invalid_ok, invalid_failure := model_propose(&model, invalid)
	first, first_ok, _ := model_propose(&model, test_proposal(2, 20, 1_024))
	_, duplicate_ok, duplicate_failure := model_propose(&model, test_proposal(2, 20, 1_024))
	_, provider_ok, provider_failure := model_propose(&model, test_proposal(3, 21, 1))
	_, definition_ok, definition_failure := model_propose(&model, test_proposal(2, 22, 1))

	testing.expect(t, !invalid_ok && first_ok && !duplicate_ok && !provider_ok && !definition_ok)
	testing.expect_value(t, invalid_failure.code, Failure_Code.Identity_Limit)
	testing.expect_value(t, duplicate_failure.code, Failure_Code.Duplicate_Identity)
	testing.expect_value(t, provider_failure.code, Failure_Code.Provider_Limit)
	testing.expect_value(t, definition_failure.code, Failure_Code.Definition_Limit)
	testing.expect_value(t, before.active, model.state.selection.active)
	testing.expect_value(t, model.state.definition_count, u16(FACTORY_DEFINITIONS + 1))
	testing.expect(t, first.id != 0 && model_valid(&model))
}

/* Ensures allocation faults preserve theme state and release partial copies. */
@(test)
alloc_faults_keep_state_and_cleanup :: proc(t: ^testing.T) {
	for fail_after in 0 ..= FACTORY_DEFINITIONS {
		tracking: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracking, context.allocator)
		failing := Failing_Allocator {
			backing = mem.tracking_allocator(&tracking),
			fail_after = u64(fail_after),
		}
		model, initialized, failure := model_init(DEFAULT_LIMITS, failing_allocator(&failing))
		testing.expect(t, !initialized)
		testing.expect_value(t, failure.code, Failure_Code.Allocation)
		testing.expect_value(t, tracking.current_memory_allocated, 0)
		model_close(&model)
		mem.tracking_allocator_destroy(&tracking)
	}

	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	failing := Failing_Allocator {
		backing = mem.tracking_allocator(&tracking),
		fail_after = max(u64),
	}
	model, initialized, _ := model_init(DEFAULT_LIMITS, failing_allocator(&failing))
	testing.expect(t, initialized)
	before := model.state.selection
	before_bytes := model.state.retained_bytes
	failing.fail_after = failing.successful_allocations
	_, proposed, failure := model_propose(&model, test_proposal(2, 20, 1_024))
	testing.expect(t, !proposed)
	testing.expect_value(t, failure.code, Failure_Code.Allocation)
	testing.expect_value(t, model.state.selection, before)
	testing.expect_value(t, model.state.retained_bytes, before_bytes)
	failing.fail_after = max(u64)
	testing.expect(t, model_close(&model))
	testing.expect_value(t, tracking.current_memory_allocated, 0)
	mem.tracking_allocator_destroy(&tracking)
}

@(private)
test_proposal :: proc(provider_key, identity_key: u32, retained_bytes: u32) -> Proposal {
	return Proposal {
		provider_key = provider_key,
		identity_key = identity_key,
		identity_bytes = 16,
		display_name_bytes = 24,
		provider_name_bytes = 16,
		provenance_bytes = 32,
		style_count = CURRENT_STYLE_ROLES,
		retained_bytes = retained_bytes,
	}
}

@(private)
Failing_Allocator :: struct {
	backing:                runtime.Allocator,
	fail_after:             u64,
	successful_allocations: u64,
}

@(private)
failing_allocator :: proc(data: ^Failing_Allocator) -> runtime.Allocator {
	return runtime.Allocator{procedure = failing_allocator_proc, data = data}
}

@(private)
failing_allocator_proc :: proc(
	allocator_data: rawptr,
	mode: runtime.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	location: runtime.Source_Code_Location,
) -> ([]byte, runtime.Allocator_Error) {
	allocator := cast(^Failing_Allocator)allocator_data
	if mode == .Alloc || mode == .Resize || mode == .Resize_Non_Zeroed {
		if allocator.successful_allocations >= allocator.fail_after {
			return nil, .Out_Of_Memory
		}
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
