// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language_bundle

import "base:runtime"
import "core:mem"
import "core:testing"

BRIDGE_FIXTURE :: `{
  "schema": 1,
  "format-version": 1,
  "id": "org.example.language",
  "display-name": "Example Language",
  "version": {"major": 1, "minor": 0, "patch": 0, "pre-release": null},
  "api-range": {
    "minimum": {"major": 1, "minor": 0, "patch": 0, "pre-release": null},
    "maximum": {"major": 2, "minor": 0, "patch": 0, "pre-release": null}
  },
  "description": "Example language support bundle.",
  "publisher": "org.example",
  "source": "catalog.example",
  "provenance": "Bridge test fixture",
  "targets": [{"platform": "linux", "architecture": "x86-64"}],
  "dependencies": [],
  "authorities": [],
  "contributions": [],
  "artifacts": [],
  "entrypoint": null
}`

/* Verifies encoded Racket data prepares, confirms, and closes one native generation. */
@(test)
language_bundle_bridge_prepares_complete_candidate :: proc(t: ^testing.T) {
	bridge: Bundle_Bridge
	candidate, prepared, failure := bundle_bridge_prepare(
		&bridge, transmute([]u8)(string(BRIDGE_FIXTURE)), 0, 1,
	)
	testing.expectf(t, prepared, "bridge preparation failed with %v", failure.code)
	if !prepared do return
	bundle, present := bundle_candidate_bundle(&candidate.bundle)
	testing.expect(t, present)
	testing.expect_value(t, identity_text_view(&bundle.identity), "org.example.language")
	confirmed, confirm_failure := bundle_bridge_confirm(&bridge, &candidate)
	testing.expectf(t, confirmed, "bridge confirmation failed with %v", confirm_failure.code)
	testing.expect_value(t, bridge.generation, u64(1))
	closed, _ := bundle_bridge_candidate_close(&candidate)
	testing.expect(t, closed)
}

/* Verifies malformed and excessive encodings reject before candidate ownership. */
@(test)
language_bundle_bridge_rejects_malformed_and_excessive_payloads :: proc(t: ^testing.T) {
	bridge: Bundle_Bridge
	_, malformed, malformed_failure := bundle_bridge_prepare(
		&bridge, transmute([]u8)(string(`{"schema":1}`)), 0, 1,
	)
	testing.expect(t, !malformed)
	testing.expect_value(t, malformed_failure.code, Bundle_Failure_Code.Malformed_Encoding)
	excessive := make([]u8, MAX_LANGUAGE_BUNDLE_BYTES + 1, context.temp_allocator)
	defer delete(excessive, context.temp_allocator)
	_, admitted, excessive_failure := bundle_bridge_prepare(&bridge, excessive, 0, 1)
	testing.expect(t, !admitted)
	testing.expect_value(t, excessive_failure.code, Bundle_Failure_Code.Limit)
}

/* Verifies stale and recursively entered preparations cannot create candidates. */
@(test)
language_bundle_bridge_rejects_stale_and_reentrant_preparation :: proc(t: ^testing.T) {
	bridge := Bundle_Bridge{generation = 4}
	_, stale, stale_failure := bundle_bridge_prepare(
		&bridge, transmute([]u8)(string(BRIDGE_FIXTURE)), 3, 5,
	)
	testing.expect(t, !stale)
	testing.expect_value(t, stale_failure.code, Bundle_Failure_Code.Stale_Generation)
	bridge.preparing = true
	_, reentrant, reentrant_failure := bundle_bridge_prepare(
		&bridge, transmute([]u8)(string(BRIDGE_FIXTURE)), 4, 5,
	)
	testing.expect(t, !reentrant)
	testing.expect_value(t, reentrant_failure.code, Bundle_Failure_Code.Reentrant_Preparation)
}

/* Verifies a stale confirmation preserves the bridge and leaves cleanup explicit. */
@(test)
language_bundle_bridge_stale_confirmation_preserves_generation :: proc(t: ^testing.T) {
	bridge: Bundle_Bridge
	candidate, prepared, _ := bundle_bridge_prepare(
		&bridge, transmute([]u8)(string(BRIDGE_FIXTURE)), 0, 2,
	)
	testing.expect(t, prepared)
	if !prepared do return
	bridge.generation = 1
	confirmed, failure := bundle_bridge_confirm(&bridge, &candidate)
	testing.expect(t, !confirmed)
	testing.expect_value(t, failure.code, Bundle_Failure_Code.Stale_Generation)
	testing.expect_value(t, bridge.generation, u64(1))
	closed, _ := bundle_bridge_candidate_close(&candidate)
	testing.expect(t, closed)
}

/* Verifies candidate allocation failure and successful cleanup both retain zero bytes. */
@(test)
language_bundle_bridge_allocation_and_cleanup_are_exact :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	failing := Bridge_Test_Failing_Allocator {
		backing = mem.tracking_allocator(&tracking),
		fail_after = 0,
	}
	bridge: Bundle_Bridge
	_, prepared, failure := bundle_bridge_prepare(
		&bridge,
		transmute([]u8)(string(BRIDGE_FIXTURE)),
		0,
		1,
		bridge_test_failing_allocator(&failing),
	)
	testing.expect(t, !prepared)
	testing.expect_value(t, failure.code, Bundle_Failure_Code.Allocation)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	failing.fail_after = max(u64)
	candidate, admitted, _ := bundle_bridge_prepare(
		&bridge,
		transmute([]u8)(string(BRIDGE_FIXTURE)),
		0,
		1,
		bridge_test_failing_allocator(&failing),
	)
	testing.expect(t, admitted)
	if admitted {
		closed, _ := bundle_bridge_candidate_close(&candidate)
		testing.expect(t, closed)
	}
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
}

@(private)
Bridge_Test_Failing_Allocator :: struct {
	backing:                runtime.Allocator,
	fail_after:             u64,
	successful_allocations: u64,
}

@(private)
bridge_test_failing_allocator :: proc(state: ^Bridge_Test_Failing_Allocator) -> runtime.Allocator {
	return runtime.Allocator{procedure = bridge_test_failing_allocator_proc, data = state}
}

@(private)
bridge_test_failing_allocator_proc :: proc(
	data: rawptr,
	mode: runtime.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	location := #caller_location,
) -> (result: []byte, error: runtime.Allocator_Error) {
	state := cast(^Bridge_Test_Failing_Allocator)data
	if mode == .Alloc || mode == .Alloc_Non_Zeroed || mode == .Resize ||
	   mode == .Resize_Non_Zeroed {
		if state.successful_allocations >= state.fail_after do return nil, .Out_Of_Memory
		state.successful_allocations += 1
	}
	return state.backing.procedure(
		state.backing.data, mode, size, alignment, old_memory, old_size, location,
	)
}
