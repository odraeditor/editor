// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../hosting"
import "../theme"
import base_runtime "base:runtime"
import "core:mem"
import "core:testing"

/* Verifies the complete Racket theme lifecycle is copied, routed, and torn down. */
verify_racket_theme_capability :: proc(t: ^testing.T, runtime: ^hosting.Runtime) {
	registry: theme.Registry
	ready, ready_failure := theme.theme_registry_init_factory(&registry, 96)
	testing.expectf(t, ready, "theme registry initialization failed: %v", ready_failure.code)
	if !ready do return
	defer theme.theme_registry_close(&registry)

	inspected_result, inspected_ok, inspected_failure := racket_theme_turn(runtime, &registry, 0)
	testing.expectf(t, inspected_ok, "Racket theme scope failed: %v", inspected_failure.code)
	testing.expect_value(t, inspected_result.calls, u16(1))

	result, composed, compose_failure := racket_theme_turn(runtime, &registry, 3)
	testing.expectf(t, composed, "Racket theme composition failed: %v", compose_failure.code)
	if !composed do return
	testing.expect_value(t, result.calls, u16(9))
	testing.expect_value(t, result.selection.active, result.selection.baseline)

	inspection, inspected, inspect_failure := theme.theme_registry_inspect(&registry)
	testing.expectf(t, inspected, "theme registry inspection failed: %v", inspect_failure.code)
	if !inspected do return
	testing.expect_value(t, inspection.usage.providers, u16(1))
	testing.expect_value(t, inspection.usage.definitions, u16(theme.FACTORY_DEFINITION_COUNT))

	before_failure := result.selection
	_, stale_ok, stale_failure := racket_theme_turn(runtime, &registry, 4)
	testing.expect(t, !stale_ok)
	testing.expect_value(t, stale_failure.code, theme.Failure_Code.Stale_Selection)
	current, current_ok, _ := theme.theme_registry_selection(&registry)
	testing.expect(t, current_ok)
	testing.expect_value(t, current, before_failure)

	_, malformed_ok, malformed_failure := racket_theme_turn(runtime, &registry, 5)
	testing.expect(t, !malformed_ok)
	testing.expect_value(t, malformed_failure.code, theme.Failure_Code.Invalid_Registry)
	current, current_ok, _ = theme.theme_registry_selection(&registry)
	testing.expect(t, current_ok)
	testing.expect_value(t, current, before_failure)

	_, limit_ok, limit_failure := racket_theme_turn(runtime, &registry, 6)
	testing.expect(t, !limit_ok)
	testing.expect_value(t, limit_failure.code, theme.Failure_Code.Operation_Limit)
	testing.expect_value(t, limit_failure.limit, u64(theme.MAX_OPERATIONS_PER_TURN))
	testing.expect_value(t, limit_failure.actual, u64(theme.MAX_OPERATIONS_PER_TURN + 1))
	current, current_ok, _ = theme.theme_registry_selection(&registry)
	testing.expect(t, current_ok)
	testing.expect_value(t, current, before_failure)

	_, exception_ok, exception_failure := racket_theme_turn(runtime, &registry, 7)
	testing.expect(t, !exception_ok)
	testing.expect_value(t, exception_failure.code, theme.Failure_Code.Invalid_Registry)
	current, current_ok, _ = theme.theme_registry_selection(&registry)
	testing.expect(t, current_ok)
	testing.expect_value(t, current.active, current.fallback)
	inspection, inspected, inspect_failure = theme.theme_registry_inspect(&registry)
	testing.expectf(t, inspected, "post-failure inspection failed: %v", inspect_failure.code)
	testing.expect_value(t, inspection.usage.providers, u16(2))
	testing.expect_value(t, inspection.usage.definitions, u16(theme.FACTORY_DEFINITION_COUNT))
	failed_provider, failed_found, failed_failure := theme.theme_registry_provider_at(&registry, 1)
	testing.expectf(t, failed_found, "failed provider lookup failed: %v", failed_failure.code)
	if failed_found {
		testing.expect_value(t, failed_provider.state, theme.Provider_State.Failed)
		_, torn_down, teardown_failure := theme.theme_registry_close_provider(
			&registry, current, failed_provider.handle,
		)
		testing.expectf(t, torn_down, "failed provider teardown failed: %v", teardown_failure.code)
	}
	inspection, inspected, _ = theme.theme_registry_inspect(&registry)
	testing.expect(t, inspected)
	testing.expect_value(t, inspection.usage.providers, u16(1))

	verify_racket_theme_allocation_fault(t)
}

@(private)
verify_racket_theme_allocation_fault :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	fault := Racket_Theme_Failing_Allocator {
		backing = mem.tracking_allocator(&tracking),
	}
	registry: theme.Registry
	_, failure := theme.theme_registry_init_factory(
		&registry,
		97,
		theme.DEFAULT_RESOURCE_LIMITS,
		racket_theme_failing_allocator(&fault),
	)
	testing.expect_value(t, failure.code, theme.Failure_Code.Allocation)
	testing.expect_value(t, tracking.current_memory_allocated, 0)
}

@(private)
Racket_Theme_Failing_Allocator :: struct {
	backing: base_runtime.Allocator,
}

@(private)
racket_theme_failing_allocator :: proc(
	data: ^Racket_Theme_Failing_Allocator,
) -> base_runtime.Allocator {
	return base_runtime.Allocator {
		procedure = racket_theme_failing_allocator_proc,
		data = data,
	}
}

@(private)
racket_theme_failing_allocator_proc :: proc(
	allocator_data: rawptr,
	mode: base_runtime.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	location: base_runtime.Source_Code_Location,
) -> ([]byte, base_runtime.Allocator_Error) {
	if mode == .Alloc || mode == .Resize || mode == .Resize_Non_Zeroed {
		return nil, .Out_Of_Memory
	}
	allocator := cast(^Racket_Theme_Failing_Allocator)allocator_data
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
