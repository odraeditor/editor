// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language

import reference "../../tests/syntax_analysis_reference"
import "base:runtime"
import "core:fmt"
import "core:mem"
import "core:testing"

/* Verifies factory bootstrap creates one confirmed single-active selection. */
@(test)
provider_registry_bootstraps_factory_provider :: proc(t: ^testing.T) {
	registry: Provider_Registry
	initialized, _ := provider_registry_init(&registry, 41, test_language(), factory_definition())
	testing.expect(t, initialized)
	if !initialized do return
	defer provider_registry_close(&registry)

	selection, selected, _ := provider_registry_selection(&registry)
	factory, inspected, _ := provider_registry_provider(&registry, selection.factory)
	stats, accounted, _ := provider_registry_stats(&registry)

	testing.expect(t, selected && inspected && accounted)
	testing.expect_value(t, selection.active, selection.factory)
	testing.expect_value(t, selection.state, Selection_State.Factory)
	testing.expect_value(t, factory.kind, Provider_Kind.Factory)
	testing.expect_value(t, factory.state, Provider_State.Confirmed)
	testing.expect_value(t, stats.live_providers, u16(1))
	testing.expect_value(t, stats.native_providers, u16(0))
}

/* Verifies registration copies descriptors and duplicate names reject atomically. */
@(test)
provider_registration_is_duplicate_safe :: proc(t: ^testing.T) {
	registry: Provider_Registry
	initialized, _ := provider_registry_init(&registry, 42, test_language(), factory_definition())
	testing.expect(t, initialized)
	if !initialized do return
	defer provider_registry_close(&registry)

	definition := native_definition("experimental")
	registered, added, _ := provider_registry_register_native(&registry, definition)
	provider, inspected, _ := provider_registry_provider(&registry, registered)
	_, duplicate, duplicate_failure := provider_registry_register_native(&registry, definition)

	testing.expect(t, added && inspected && !duplicate)
	testing.expect_value(t, provider.kind, Provider_Kind.Native)
	testing.expect_value(t, provider.state, Provider_State.Registered)
	testing.expect_value(t, provider_name_string(&provider.name), "experimental")
	testing.expect_value(t, duplicate_failure.code, Failure_Code.Duplicate_Provider)
}

/* Verifies confirmation, replacement, disable, restoration, and closure are generation checked. */
@(test)
provider_lifecycle_is_single_active_and_atomic :: proc(t: ^testing.T) {
	registry: Provider_Registry
	initialized, _ := provider_registry_init(&registry, 43, test_language(), factory_definition())
	testing.expect(t, initialized)
	if !initialized do return
	defer provider_registry_close(&registry)

	registered, added, _ := provider_registry_register_native(&registry, native_definition("replacement"))
	confirmed, confirmed_ok, _ := provider_registry_confirm_native(&registry, registered)
	before, _, _ := provider_registry_selection(&registry)
	replaced, replaced_ok, _ := provider_registry_replace(&registry, before, confirmed)
	_, stale_ok, stale_failure := provider_registry_disable(&registry, before)
	disabled, disabled_ok, _ := provider_registry_disable(&registry, replaced)
	restored, restored_ok, _ := provider_registry_restore(&registry, disabled)
	closed, closed_ok, _ := provider_registry_close_native(&registry, restored, confirmed)

	testing.expect(t, added && confirmed_ok && replaced_ok && !stale_ok)
	testing.expect(t, disabled_ok && restored_ok && closed_ok)
	testing.expect_value(t, stale_failure.code, Failure_Code.Stale_Selection)
	testing.expect_value(t, replaced.active, confirmed)
	testing.expect_value(t, replaced.state, Selection_State.Replacement)
	testing.expect_value(t, disabled.active, Provider_Handle{})
	testing.expect_value(t, disabled.state, Selection_State.Disabled)
	testing.expect_value(t, restored.active, restored.factory)
	testing.expect_value(t, restored.state, Selection_State.Restored)
	testing.expect_value(t, closed.active, closed.factory)
}

/* Verifies active replacement failure restores the maintained factory provider. */
@(test)
provider_failure_restores_factory :: proc(t: ^testing.T) {
	registry: Provider_Registry
	initialized, _ := provider_registry_init(&registry, 44, test_language(), factory_definition())
	testing.expect(t, initialized)
	if !initialized do return
	defer provider_registry_close(&registry)

	registered, _, _ := provider_registry_register_native(&registry, native_definition("faulting"))
	confirmed, _, _ := provider_registry_confirm_native(&registry, registered)
	before, _, _ := provider_registry_selection(&registry)
	selected, _, _ := provider_registry_replace(&registry, before, confirmed)
	restored, contained, _ := provider_registry_fail_active(&registry, selected, confirmed)
	_, stale_ok, stale_failure := provider_registry_provider(&registry, confirmed)

	testing.expect(t, contained && !stale_ok)
	testing.expect_value(t, restored.active, restored.factory)
	testing.expect_value(t, restored.state, Selection_State.Restored)
	testing.expect_value(t, stale_failure.code, Failure_Code.Stale_Provider)
}

/* Verifies the native registry and independent oracle agree on lifecycle outcomes. */
@(test)
provider_lifecycle_matches_independent_model :: proc(t: ^testing.T) {
	model, model_ready := reference.model_init(1)
	registry: Provider_Registry
	registry_ready, _ := provider_registry_init(&registry, 45, test_language(), factory_definition())
	testing.expect(t, model_ready && registry_ready)
	if !model_ready || !registry_ready do return
	defer provider_registry_close(&registry)

	model_registered, _, _ := reference.model_register(&model, 2)
	model_confirmed, _, _ := reference.model_confirm(&model, model_registered)
	registered, _, _ := provider_registry_register_native(&registry, native_definition("oracle"))
	confirmed, _, _ := provider_registry_confirm_native(&registry, registered)
	production_before, _, _ := provider_registry_selection(&registry)
	model_selected, model_replaced, _ := reference.model_replace(&model, model.selection.generation, model_confirmed)
	production_selected, production_replaced, _ := provider_registry_replace(&registry, production_before, confirmed)
	model_disabled, model_disabled_ok, _ := reference.model_disable(&model, model_selected.generation)
	production_disabled, production_disabled_ok, _ := provider_registry_disable(&registry, production_selected)
	model_restored, model_restored_ok, _ := reference.model_restore(&model, model_disabled.generation)
	production_restored, production_restored_ok, _ := provider_registry_restore(&registry, production_disabled)

	testing.expect(t, model_replaced && production_replaced)
	testing.expect(t, model_disabled_ok && production_disabled_ok)
	testing.expect(t, model_restored_ok && production_restored_ok)
	testing.expect_value(t, production_selected.state, Selection_State.Replacement)
	testing.expect(t, !model_selected.disabled)
	testing.expect_value(t, production_disabled.state, Selection_State.Disabled)
	testing.expect(t, model_disabled.disabled)
	testing.expect_value(t, production_restored.state, Selection_State.Restored)
	testing.expect_value(t, model_restored.active, model_restored.factory)
}

/* Verifies provider and descriptor limits reject without changing active selection. */
@(test)
provider_limits_reject_bad_definitions :: proc(t: ^testing.T) {
	registry: Provider_Registry
	initialized, _ := provider_registry_init(&registry, 46, test_language(), factory_definition())
	testing.expect(t, initialized)
	if !initialized do return
	defer provider_registry_close(&registry)

	oversized := make([]u8, MAX_PROVIDER_NAME_BYTES + 1, context.temp_allocator)
	defer delete(oversized, context.temp_allocator)
	invalid := native_definition(string(oversized))
	_, invalid_ok, invalid_failure := provider_registry_register_native(&registry, invalid)
	testing.expect(t, !invalid_ok)
	testing.expect_value(t, invalid_failure.code, Failure_Code.Provider_Name_Limit)

	name_storage: [MAX_PROVIDERS][32]u8
	for index in 1 ..< MAX_PROVIDERS {
		name := fmt.bprintf(name_storage[index][:], "native-%02d", index)
		_, added, _ := provider_registry_register_native(&registry, native_definition(name))
		testing.expect(t, added)
	}
	before, _, _ := provider_registry_selection(&registry)
	_, overflow, overflow_failure := provider_registry_register_native(&registry, native_definition("overflow"))
	after, _, _ := provider_registry_selection(&registry)
	stats, _, _ := provider_registry_stats(&registry)

	testing.expect(t, !overflow)
	testing.expect_value(t, overflow_failure.code, Failure_Code.Provider_Limit)
	testing.expect_value(t, before.active, after.active)
	testing.expect_value(t, stats.live_providers, u16(MAX_PROVIDERS))
}

/* Verifies registry allocation failure publishes no partial owner. */
@(test)
provider_registry_allocation_failure_is_atomic :: proc(t: ^testing.T) {
	failing := Language_Failing_Allocator{backing = context.allocator, fail_after = 0}
	registry: Provider_Registry
	initialized, failure := provider_registry_init(
		&registry,
		47,
		test_language(),
		factory_definition(),
		language_failing_allocator(&failing),
	)

	testing.expect(t, !initialized)
	testing.expect_value(t, failure.code, Failure_Code.Allocation)
	testing.expect_value(t, registry, Provider_Registry{})
}

/* Verifies normal teardown releases the complete provider table exactly once. */
@(test)
provider_registry_teardown_releases_all_storage :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	registry: Provider_Registry
	initialized, _ := provider_registry_init(&registry, 48, test_language(), factory_definition(), allocator)
	_, added, _ := provider_registry_register_native(&registry, native_definition("tracked"))
	closed, _ := provider_registry_close(&registry)
	retained := tracking.current_memory_allocated
	mem.tracking_allocator_destroy(&tracking)

	testing.expect(t, initialized && added && closed)
	testing.expect_value(t, retained, i64(0))
	closed_again, _ := provider_registry_close(&registry)
	testing.expect(t, !closed_again)
}

@(private = "file")
test_language :: proc() -> Language_Identity {
	name: Language_Name
	name.length = u16(copy(name.bytes[:], "odin"))
	return Language_Identity{id = 1, generation = 1, name = name}
}

@(private = "file")
factory_definition :: proc() -> Provider_Definition {
	return Provider_Definition {
		name = "factory-odin",
		parser_name = "tree-sitter-odin",
		grammar_abi = 14,
		capabilities = {.Initial_Parse, .Incremental_Parse, .Visible_Query, .Syntax_Roles},
		provenance = "tree-sitter-odin v1.3.0",
	}
}

@(private = "file")
native_definition :: proc(name: string) -> Provider_Definition {
	definition := factory_definition()
	definition.name = name
	definition.provenance = "synthetic native provider"
	return definition
}

@(private = "file")
Language_Failing_Allocator :: struct {
	backing:                runtime.Allocator,
	fail_after:             u64,
	successful_allocations: u64,
}

@(private = "file")
language_failing_allocator :: proc(data: ^Language_Failing_Allocator) -> runtime.Allocator {
	return runtime.Allocator{procedure = language_failing_allocator_proc, data = data}
}

@(private = "file")
language_failing_allocator_proc :: proc(
	allocator_data: rawptr,
	mode: runtime.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	location := #caller_location,
) -> (result: []byte, error: runtime.Allocator_Error) {
	allocator := cast(^Language_Failing_Allocator)allocator_data
	if mode == .Alloc || mode == .Alloc_Non_Zeroed || mode == .Resize ||
	   mode == .Resize_Non_Zeroed {
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
