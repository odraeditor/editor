// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package project

import "base:runtime"
import "core:mem"
import "core:testing"

/* Verifies every registry initialization allocation fault releases all retained memory. */
@(test)
initialization_faults_release_registry_bytes :: proc(t: ^testing.T) {
	for fail_after in 0 ..< 2 {
		tracking: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracking, context.allocator)
		failing := Project_Failing_Allocator{
			backing = mem.tracking_allocator(&tracking),
			fail_after = u64(fail_after),
		}
		registry: Registry
		initialized, failure := registry_init(
			&registry,
			Owner_Handle{id = Owner_ID(100 + fail_after), generation = Owner_Generation(1)},
			DEFAULT_POLICY,
			Allocator_Set{
				persistent = project_failing_allocator(&failing),
				temporary = context.temp_allocator,
			},
		)
		testing.expect(t, !initialized)
		testing.expect_value(t, failure.code, Failure_Code.Persistent_Memory_Limit)
		testing.expect(t, registry.state == nil)
		testing.expect_value(t, tracking.current_memory_allocated, 0)
		mem.tracking_allocator_destroy(&tracking)
	}
}

/* Verifies preparation allocation faults preserve the empty registry and exact cleanup. */
@(test)
snapshot_preparation_faults_preserve_prior_state :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	failing := Project_Failing_Allocator{
		backing = mem.tracking_allocator(&tracking),
		fail_after = max(u64),
	}
	registry: Registry
	owner := Owner_Handle{id = Owner_ID(201), generation = Owner_Generation(1)}
	initialized, _ := registry_init(
		&registry,
		owner,
		DEFAULT_POLICY,
		Allocator_Set{
			persistent = project_failing_allocator(&failing),
			temporary = context.temp_allocator,
		},
	)
	testing.expect(t, initialized)
	if !initialized {
		mem.tracking_allocator_destroy(&tracking)
		return
	}
	baseline_bytes := tracking.current_memory_allocated
	proposal := [?]Directory_Proposal{{path = "/fault", trust = .Untrusted}}
	for fail_offset in 0 ..< 4 {
		failing.fail_after = failing.successful_allocations + u64(fail_offset)
		prepared: Prepared_Snapshot
		prepared_ok, failure := registry_prepare_snapshot(
			&registry,
			Snapshot_Request{
				owner = owner,
				project_id = Project_ID(202),
				name = "Fault",
				directories = proposal[:],
				temporary = true,
			},
			&prepared,
		)
		testing.expectf(t, !prepared_ok, "fault offset %d unexpectedly passed", fail_offset)
		testing.expect_value(t, failure.code, Failure_Code.Persistent_Memory_Limit)
		testing.expect(t, prepared.state == nil)
		testing.expect(t, registry_validate(&registry))
		testing.expect_value(t, tracking.current_memory_allocated, baseline_bytes)
	}
	failing.fail_after = max(u64)
	registry_close(&registry)
	testing.expect_value(t, tracking.current_memory_allocated, 0)
	mem.tracking_allocator_destroy(&tracking)
}

/* Verifies directory-opening allocation faults preserve the empty active state. */
@(test)
dir_opening_faults_release_private_snapshots :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	failing := Project_Failing_Allocator {
		backing = mem.tracking_allocator(&tracking),
		fail_after = max(u64),
	}
	registry: Registry
	owner := Owner_Handle{id = Owner_ID(211), generation = Owner_Generation(1)}
	initialized, _ := registry_init(
		&registry,
		owner,
		DEFAULT_POLICY,
		Allocator_Set {
			persistent = project_failing_allocator(&failing),
			temporary = context.temp_allocator,
		},
	)
	testing.expect(t, initialized)
	if !initialized {
		mem.tracking_allocator_destroy(&tracking)
		return
	}
	baseline_bytes := tracking.current_memory_allocated
	directories := [?]Directory_Proposal{{path = "/fault/open", trust = .Untrusted}}
	request := Directory_Open_Request {
		owner = owner,
		expected_catalog_generation = 1,
		normalized_path = "/fault/open",
		snapshot = {
			owner = owner,
			project_id = Project_ID(212),
			name = "Fault",
			directories = directories[:],
			temporary = true,
		},
	}
	for fail_offset in 0 ..< 4 {
		failing.fail_after = failing.successful_allocations + u64(fail_offset)
		prepared: Directory_Open_Preparation
		prepared_ok, failure := directory_open_prepare(&registry, request, &prepared)
		testing.expectf(t, !prepared_ok, "fault offset %d unexpectedly passed", fail_offset)
		testing.expect_value(t, failure.code, Failure_Code.Persistent_Memory_Limit)
		testing.expect_value(t, prepared.resolution, Directory_Open_Resolution.Invalid)
		usage, usage_ok := registry_usage(&registry)
		testing.expect(t, usage_ok)
		testing.expect_value(t, usage.projects, u32(0))
		testing.expect_value(t, tracking.current_memory_allocated, baseline_bytes)
	}
	failing.fail_after = max(u64)
	registry_close(&registry)
	testing.expect_value(t, tracking.current_memory_allocated, 0)
	mem.tracking_allocator_destroy(&tracking)
}

@(private)
Project_Failing_Allocator :: struct {
	backing:                runtime.Allocator,
	fail_after:             u64,
	successful_allocations: u64,
}

@(private)
project_failing_allocator :: proc(data: ^Project_Failing_Allocator) -> runtime.Allocator {
	return runtime.Allocator{procedure = project_failing_allocator_proc, data = data}
}

@(private)
project_failing_allocator_proc :: proc(
	allocator_data: rawptr,
	mode: runtime.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	location := #caller_location,
) -> (result: []byte, error: runtime.Allocator_Error) {
	allocator := (^Project_Failing_Allocator)(allocator_data)
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
