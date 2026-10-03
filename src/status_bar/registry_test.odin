// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package status_bar

import "base:runtime"
import "core:testing"

@(private = "file")
Registry_Failing_Allocator :: struct {
	backing:                runtime.Allocator,
	fail_after:             u64,
	successful_allocations: u64,
}

@(private = "file")
registry_failing_allocator_proc :: proc(
	allocator_data: rawptr,
	mode: runtime.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	location := #caller_location,
) -> ([]byte, runtime.Allocator_Error) {
	allocator := cast(^Registry_Failing_Allocator)allocator_data
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

@(private = "file")
registry_test_segment :: proc(identity, text: string, group := Group.Right, order := u16(0)) -> Programmable_Segment_Proposal {
	return Programmable_Segment_Proposal {
		identity = identity,
		kind = .Miscellaneous,
		group = group,
		order = order,
		priority = 10,
		full_text = text,
		compact_text = text,
		omittable = true,
		style_role = .Context,
		inspection_text = text,
	}
}

@(private = "file")
registry_test_proposal :: proc(
	name, package_name: string,
	segments: []Programmable_Segment_Proposal,
) -> Provider_Proposal {
	return Provider_Proposal {
		provider_name = name,
		package_name = package_name,
		segments = segments,
	}
}

@(test)
/* Verifies registration copies package state and exposes deterministic group, order, and identity order. */
registry_orders_owned_segments :: proc(t: ^testing.T) {
	registry: Registry
	initialized, failure := registry_init(&registry, 71)
	testing.expect(t, initialized)
	testing.expect_value(t, failure.code, Registry_Failure_Code.None)
	if !initialized do return
	defer registry_close(&registry)
	segments := [3]Programmable_Segment_Proposal {
		registry_test_segment("right-late", "late", .Right, 20),
		registry_test_segment("left-first", "first", .Left, 10),
		registry_test_segment("right-early", "early", .Right, 5),
	}
	provider, registered, register_failure := registry_register(
		&registry,
		1,
		registry_test_proposal("Tasks", "tasks-package", segments[:]),
	)
	testing.expect(t, registered)
	testing.expect_value(t, register_failure.code, Registry_Failure_Code.None)
	testing.expect_value(t, provider.provider_id, Provider_ID(1))
	inspection, inspected, _ := registry_inspect(&registry)
	testing.expect(t, inspected)
	testing.expect_value(t, inspection.registry_generation, Registry_Generation(2))
	testing.expect_value(t, inspection.usage.providers, u16(1))
	testing.expect_value(t, inspection.usage.segments, u16(3))
	descriptor, provider_ok, _ := registry_provider_at(&registry, 0)
	testing.expect(t, provider_ok)
	testing.expect_value(t, provider_descriptor_name(&descriptor), "Tasks")
	testing.expect_value(t, provider_descriptor_package(&descriptor), "tasks-package")
	expected := [?]string{"left-first", "right-early", "right-late"}
	for identity, index in expected {
		view, segment_ok, _ := registry_segment_at(&registry, u16(index))
		testing.expect(t, segment_ok)
		testing.expect_value(t, programmable_segment_identity(&view.descriptor), identity)
		testing.expect(t, view.definition.id > Segment_ID(FACTORY_SEGMENT_COUNT))
	}
}

@(test)
/* Verifies duplicate and factory-owned identities reject without replacing the last valid generation. */
registry_rejects_identity_conflicts :: proc(t: ^testing.T) {
	registry: Registry
	initialized, _ := registry_init(&registry, 72)
	if !testing.expect(t, initialized) do return
	defer registry_close(&registry)
	valid_segments := [1]Programmable_Segment_Proposal {
		registry_test_segment("task-count", "3 tasks"),
	}
	provider, registered, _ := registry_register(
		&registry,
		1,
		registry_test_proposal("Tasks", "tasks-package", valid_segments[:]),
	)
	if !testing.expect(t, registered) do return
	conflicting := [1]Programmable_Segment_Proposal {
		registry_test_segment("position", "forged"),
	}
	_, replaced, replace_failure := registry_replace(
		&registry,
		2,
		provider,
		registry_test_proposal("Tasks", "tasks-package", conflicting[:]),
	)
	testing.expect(t, !replaced)
	testing.expect_value(t, replace_failure.code, Registry_Failure_Code.Factory_Identity_Conflict)
	inspection, inspected, _ := registry_inspect(&registry)
	testing.expect(t, inspected)
	testing.expect_value(t, inspection.registry_generation, Registry_Generation(2))
	view, segment_ok, _ := registry_segment_at(&registry, 0)
	testing.expect(t, segment_ok)
	testing.expect_value(t, programmable_segment_identity(&view.descriptor), "task-count")
	testing.expect_value(t, string(view.definition.full_text), "3 tasks")
	duplicate := [2]Programmable_Segment_Proposal {
		registry_test_segment("same", "one"),
		registry_test_segment("same", "two"),
	}
	_, duplicate_ok, duplicate_failure := registry_replace(
		&registry,
		2,
		provider,
		registry_test_proposal("Tasks", "tasks-package", duplicate[:]),
	)
	testing.expect(t, !duplicate_ok)
	testing.expect_value(t, duplicate_failure.code, Registry_Failure_Code.Duplicate_Segment)
	inspection, _, _ = registry_inspect(&registry)
	testing.expect_value(t, inspection.registry_generation, Registry_Generation(2))
}

@(test)
/* Verifies replacement preserves stable identities, advances generations, and retires stale handles. */
registry_replaces_provider_generation :: proc(t: ^testing.T) {
	registry: Registry
	initialized, _ := registry_init(&registry, 73)
	if !testing.expect(t, initialized) do return
	defer registry_close(&registry)
	initial := [2]Programmable_Segment_Proposal {
		registry_test_segment("alpha", "A", .Right, 20),
		registry_test_segment("beta", "B", .Right, 10),
	}
	provider, registered, _ := registry_register(
		&registry,
		1,
		registry_test_proposal("Package", "sample-package", initial[:]),
	)
	if !testing.expect(t, registered) do return
	alpha_before, before_ok, _ := registry_segment_at(&registry, 1)
	if !testing.expect(t, before_ok) do return
	replacement_segments := [2]Programmable_Segment_Proposal {
		registry_test_segment("alpha", "A2", .Left, 1),
		registry_test_segment("gamma", "G", .Right, 1),
	}
	replacement, replaced, replace_failure := registry_replace(
		&registry,
		2,
		provider,
		registry_test_proposal("Package", "sample-package", replacement_segments[:]),
	)
	testing.expect(t, replaced)
	testing.expect_value(t, replace_failure.code, Registry_Failure_Code.None)
	testing.expect_value(t, replacement.provider_generation, Provider_Generation(2))
	alpha_after, after_ok, _ := registry_segment_at(&registry, 0)
	testing.expect(t, after_ok)
	testing.expect_value(t, programmable_segment_identity(&alpha_after.descriptor), "alpha")
	testing.expect_value(t, alpha_after.descriptor.handle.segment_id, alpha_before.descriptor.handle.segment_id)
	testing.expect_value(
		t,
		alpha_after.descriptor.handle.segment_generation,
		alpha_before.descriptor.handle.segment_generation + 1,
	)
	_, stale_ok, stale_failure := registry_replace(
		&registry,
		3,
		provider,
		registry_test_proposal("Package", "sample-package", replacement_segments[:]),
	)
	testing.expect(t, !stale_ok)
	testing.expect_value(t, stale_failure.code, Registry_Failure_Code.Stale_Provider)
}

@(test)
/* Verifies allocation failure during replacement preserves the exact prior provider generation. */
registry_contains_replacement_alloc :: proc(t: ^testing.T) {
	failing := Registry_Failing_Allocator {backing = context.allocator, fail_after = max(u64)}
	allocator := runtime.Allocator {
		procedure = registry_failing_allocator_proc,
		data = &failing,
	}
	registry: Registry
	initialized, _ := registry_init(&registry, 74, DEFAULT_REGISTRY_LIMITS, allocator)
	if !testing.expect(t, initialized) do return
	defer registry_close(&registry)
	initial := [1]Programmable_Segment_Proposal {
		registry_test_segment("state", "ready"),
	}
	provider, registered, _ := registry_register(
		&registry,
		1,
		registry_test_proposal("State", "state-package", initial[:]),
	)
	if !testing.expect(t, registered) do return
	failing.fail_after = failing.successful_allocations
	replacement := [1]Programmable_Segment_Proposal {
		registry_test_segment("state", "busy"),
	}
	_, replaced, replace_failure := registry_replace(
		&registry,
		2,
		provider,
		registry_test_proposal("State", "state-package", replacement[:]),
	)
	testing.expect(t, !replaced)
	testing.expect_value(t, replace_failure.code, Registry_Failure_Code.Allocation)
	inspection, inspected, _ := registry_inspect(&registry)
	testing.expect(t, inspected)
	testing.expect_value(t, inspection.registry_generation, Registry_Generation(2))
	view, segment_ok, _ := registry_segment_at(&registry, 0)
	testing.expect(t, segment_ok)
	testing.expect_value(t, string(view.definition.full_text), "ready")
}

@(test)
/* Verifies removal, owner teardown, slot reuse, and provider inspection preserve registration order. */
registry_removes_owner_without_reorder :: proc(t: ^testing.T) {
	registry: Registry
	initialized, _ := registry_init(&registry, 75)
	if !testing.expect(t, initialized) do return
	defer registry_close(&registry)
	first_segments := [1]Programmable_Segment_Proposal {registry_test_segment("first", "1")}
	second_segments := [1]Programmable_Segment_Proposal {registry_test_segment("second", "2")}
	third_segments := [1]Programmable_Segment_Proposal {registry_test_segment("third", "3")}
	first, first_ok, _ := registry_register(
		&registry, 1, registry_test_proposal("First", "first-package", first_segments[:]),
	)
	second, second_ok, _ := registry_register(
		&registry, 2, registry_test_proposal("Second", "second-package", second_segments[:]),
	)
	if !testing.expect(t, first_ok && second_ok) do return
	removed, remove_failure := registry_remove(&registry, 3, first)
	testing.expect(t, removed)
	testing.expect_value(t, remove_failure.code, Registry_Failure_Code.None)
	_, stale_ok, stale_failure := registry_replace(
		&registry,
		4,
		first,
		registry_test_proposal("First", "first-package", first_segments[:]),
	)
	testing.expect(t, !stale_ok)
	testing.expect_value(t, stale_failure.code, Registry_Failure_Code.Invalid_Provider)
	_, third_ok, _ := registry_register(
		&registry, 4, registry_test_proposal("Third", "third-package", third_segments[:]),
	)
	if !testing.expect(t, third_ok) do return
	first_visible, visible_ok, _ := registry_provider_at(&registry, 0)
	testing.expect(t, visible_ok)
	testing.expect_value(t, first_visible.handle, second)
	testing.expect_value(t, provider_descriptor_package(&first_visible), "second-package")
	closed, teardown_failure := registry_teardown_provider(&registry, 5, second)
	testing.expect(t, closed)
	testing.expect_value(t, teardown_failure.code, Registry_Failure_Code.None)
	inspection, inspected, _ := registry_inspect(&registry)
	testing.expect(t, inspected)
	testing.expect_value(t, inspection.usage.providers, u16(1))
	testing.expect_value(t, inspection.usage.segments, u16(1))
}
