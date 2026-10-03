// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_computation

import "base:runtime"
import "core:mem"
import "core:testing"

/* Verifies Racket adapter and deny-first policy values are copied atomically. */
@(test)
computation_configuration_copies_generation :: proc(t: ^testing.T) {
	configuration: Configuration
	initialized, failure := computation_configuration_init(&configuration, 1, 1, 1)
	testing.expectf(t, initialized, "computation factory configuration failed with %v", failure.code)
	if !initialized do return
	defer computation_configuration_close(&configuration)
	language := [6]u8{'r', 'a', 'c', 'k', 'e', 't'}
	limits := DEFAULT_LIMITS
	limits.output_bytes = 1 * 1_024 * 1_024
	adapters := [1]Adapter_Candidate{{
		identity = "racket",
		language = string(language[:]),
		version = "factory-1",
		class = .Factory_Adapter,
		in_process = true,
		limits = limits,
	}}
	policies := [1]Policy_Candidate{{
		identity = "racket-project",
		language = "racket",
		origin = .Project,
		interactive = .Confirm,
		batch = .Deny,
		effects = {.Read_Resource},
	}}
	candidate := Configuration_Candidate {
		generation = 2,
		adapter_generation = 2,
		policy_generation = 2,
		adapters = adapters[:],
		policies = policies[:],
	}
	descriptor: Configuration_Descriptor
	published: bool
	descriptor, published, failure = computation_configuration_publish(&configuration, candidate)
	testing.expectf(t, published, "computation configuration failed with %v", failure.code)
	testing.expect_value(t, descriptor.adapter_count, u16(1))
	testing.expect_value(t, descriptor.policy_count, u16(1))
	language[0] = 'b'
	adapter, adapter_ok := computation_configuration_adapter(&configuration, 0)
	policy, policy_ok := computation_configuration_policy(&configuration, 0)
	testing.expect(t, adapter_ok && policy_ok)
	testing.expect_value(t, adapter.language, "racket")
	testing.expect_value(t, adapter.limits.output_bytes, u64(1 * 1_024 * 1_024))
	testing.expect_value(t, policy.batch, Authority_Decision.Deny)
}

/* Verifies stale, duplicate-language, and confirm-in-batch candidates retain prior state. */
@(test)
computation_configuration_rejects_atomically :: proc(t: ^testing.T) {
	configuration: Configuration
	initialized, _ := computation_configuration_init(&configuration, 7, 7, 7)
	testing.expect(t, initialized)
	if !initialized do return
	defer computation_configuration_close(&configuration)
	adapters := [2]Adapter_Candidate {
		{identity = "racket-a", language = "racket", version = "1", class = .Factory_Adapter, limits = DEFAULT_LIMITS},
		{identity = "racket-b", language = "racket", version = "2", class = .Configured_Provider, limits = DEFAULT_LIMITS},
	}
	policies := [1]Policy_Candidate{{
		identity = "default",
		language = "racket",
		origin = .Document,
		interactive = .Confirm,
		batch = .Deny,
	}}
	candidate := Configuration_Candidate {
		generation = 8,
		adapter_generation = 8,
		policy_generation = 8,
		adapters = adapters[:],
		policies = policies[:],
	}
	_, published, failure := computation_configuration_publish(&configuration, candidate)
	testing.expect(t, !published)
	testing.expect_value(t, failure.code, Failure_Code.Conflict)
	candidate.adapters = adapters[:1]
	policies[0].batch = .Confirm
	_, published, failure = computation_configuration_publish(&configuration, candidate)
	testing.expect(t, !published)
	testing.expect_value(t, failure.code, Failure_Code.Malformed)
	descriptor, _ := computation_configuration_inspect(&configuration)
	testing.expect_value(t, descriptor.generation, Configuration_Generation(7))
}

/* Verifies allocation failure never replaces or leaks a confirmed generation. */
@(test)
computation_configuration_survives_allocation_faults :: proc(t: ^testing.T) {
	for fail_after in 1 ..< 6 {
		tracking: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracking, context.allocator)
		failing := Computation_Test_Failing_Allocator {
			backing = mem.tracking_allocator(&tracking),
			fail_after = u64(fail_after),
		}
		configuration: Configuration
		initialized, _ := computation_configuration_init(
			&configuration,
			1,
			1,
			1,
			computation_test_failing_allocator(&failing),
		)
		testing.expect(t, initialized)
		if !initialized {
			mem.tracking_allocator_destroy(&tracking)
			continue
		}
		adapters := [1]Adapter_Candidate{{identity = "racket", language = "racket", version = "1", class = .Factory_Adapter, limits = DEFAULT_LIMITS}}
		policies := [1]Policy_Candidate{{identity = "deny", language = "racket", origin = .Document, interactive = .Deny, batch = .Deny}}
		candidate := Configuration_Candidate{generation = 2, adapter_generation = 2, policy_generation = 2, adapters = adapters[:], policies = policies[:]}
		_, published, failure := computation_configuration_publish(&configuration, candidate)
		if !published do testing.expect_value(t, failure.code, Failure_Code.Allocation_Failed)
		descriptor, _ := computation_configuration_inspect(&configuration)
		if !published do testing.expect_value(t, descriptor.generation, Configuration_Generation(1))
		computation_configuration_close(&configuration)
		testing.expect_value(t, tracking.current_memory_allocated, i64(0))
		mem.tracking_allocator_destroy(&tracking)
	}
}

@(private)
Computation_Test_Failing_Allocator :: struct {
	backing:                runtime.Allocator,
	fail_after:             u64,
	successful_allocations: u64,
}

@(private)
computation_test_failing_allocator :: proc(data: ^Computation_Test_Failing_Allocator) -> runtime.Allocator {
	return runtime.Allocator{procedure = computation_test_failing_allocator_proc, data = data}
}

@(private)
computation_test_failing_allocator_proc :: proc(
	allocator_data: rawptr,
	mode: runtime.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	location := #caller_location,
) -> (result: []byte, error: runtime.Allocator_Error) {
	allocator := (^Computation_Test_Failing_Allocator)(allocator_data)
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
