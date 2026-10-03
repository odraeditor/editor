// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_editing

import "../editor"
import "../view"
import "base:runtime"
import "core:mem"
import "core:testing"

/* Verifies local and global visibility use closed deterministic cycles. */
@(test)
visibility_transitions_are_deterministic :: proc(t: ^testing.T) {
	next, ok := local_visibility_next(.Heading_Only)
	testing.expect(t, ok)
	testing.expect_value(t, next, Visibility_State.Direct_Children)
	next, ok = local_visibility_next(next)
	testing.expect(t, ok)
	testing.expect_value(t, next, Visibility_State.Complete_Subtree)
	next, ok = local_visibility_next(next)
	testing.expect(t, ok)
	testing.expect_value(t, next, Visibility_State.Heading_Only)
	_, invalid_local := local_visibility_next(.Overview)
	testing.expect(t, !invalid_local)

	next, ok = global_visibility_next(.Overview)
	testing.expect(t, ok)
	testing.expect_value(t, next, Visibility_State.Contents)
	next, ok = global_visibility_next(next)
	testing.expect(t, ok)
	testing.expect_value(t, next, Visibility_State.Show_All)
	next, ok = global_visibility_next(next)
	testing.expect(t, ok)
	testing.expect_value(t, next, Visibility_State.Overview)
}

/* Verifies a prepared transition publishes one view generation and consumes itself. */
@(test)
visibility_transition_publishes_exact_view_state :: proc(t: ^testing.T) {
	buffer: editor.Buffer
	registry: view.Registry
	handle: view.View_Handle
	ready := visibility_test_context(t, &buffer, &registry, &handle)
	if !ready do return
	defer visibility_test_close(t, &buffer, &registry, &handle)

	range := [1]view.Hidden_Range{visibility_test_range(&buffer, 2, 8)}
	scope := visibility_test_scope(&registry, handle)
	transition: Visibility_Transition
	descriptor, prepared, prepare_failure := visibility_transition_prepare(
		&transition,
		&registry,
		{
			operation_id = 1,
			scope = scope,
			kind = .Local,
			current = .Heading_Only,
			ranges = range[:],
		},
	)
	testing.expectf(t, prepared, "prepare failed with %v", prepare_failure.code)
	testing.expect_value(t, descriptor.next, Visibility_State.Direct_Children)
	testing.expect_value(t, descriptor.range_count, u32(1))
	result, published, publish_failure := visibility_transition_publish(&transition, &registry)
	testing.expectf(t, published, "publish failed with %v", publish_failure.code)
	testing.expect(t, !visibility_transition_is_valid(&transition))
	testing.expect_value(t, result.view.generation, view.Visibility_Generation(1))
	testing.expect_value(t, result.view.range_count, u32(1))
	state, state_ok, _ := view.snapshot(&registry, handle)
	testing.expect(t, state_ok)
	testing.expect_value(t, state.hidden_range_count, u32(1))
}

/* Verifies stale view state rejects publication while explicit close releases ownership. */
@(test)
visibility_transition_rejects_stale_publication :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	allocator := mem.tracking_allocator(&tracking)
	buffer: editor.Buffer
	buffer_ok, _ := editor.buffer_init(
		&buffer,
		401,
		"abcdefghij",
		editor.Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
	)
	registry: view.Registry
	registry_ok, _ := view.registry_init(&registry, 401, allocator)
	handle, view_ok, _ := view.create(&registry, &buffer)
	testing.expect(t, buffer_ok && registry_ok && view_ok)
	if !buffer_ok || !registry_ok || !view_ok do return

	range := [1]view.Hidden_Range{visibility_test_range(&buffer, 2, 8)}
	transition: Visibility_Transition
	_, prepared, _ := visibility_transition_prepare(
		&transition,
		&registry,
		{
			operation_id = 2,
			scope = visibility_test_scope(&registry, handle),
			kind = .Global,
			current = .Overview,
			ranges = range[:],
		},
		allocator = allocator,
	)
	testing.expect(t, prepared)
	changed, _ := view.set_layout_policy(&registry, handle, 4, 4, 1)
	testing.expect(t, changed)
	_, published, failure := visibility_transition_publish(&transition, &registry)
	testing.expect(t, !published)
	testing.expect_value(t, failure.code, Failure_Code.Stale)
	testing.expect(t, visibility_transition_is_valid(&transition))
	visibility_transition_close(&transition)
	testing.expect(t, !visibility_transition_is_valid(&transition))

	view_closed, _ := view.close(&registry, &handle)
	registry_closed, _ := view.registry_close(&registry)
	buffer_closed, _ := editor.buffer_close(&buffer)
	testing.expect(t, view_closed && registry_closed && buffer_closed)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
}

/* Verifies every transition allocation can fail without retaining ownership. */
@(test)
visibility_transition_allocation_faults_release_state :: proc(t: ^testing.T) {
	buffer: editor.Buffer
	registry: view.Registry
	handle: view.View_Handle
	ready := visibility_test_context(t, &buffer, &registry, &handle)
	if !ready do return
	defer visibility_test_close(t, &buffer, &registry, &handle)
	range := [1]view.Hidden_Range{visibility_test_range(&buffer, 2, 8)}

	for fail_after in 0 ..< 2 {
		tracking: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracking, context.allocator)
		failing := Visibility_Test_Failing_Allocator {
			backing = mem.tracking_allocator(&tracking),
			fail_after = u64(fail_after),
		}
		transition: Visibility_Transition
		_, prepared, failure := visibility_transition_prepare(
			&transition,
			&registry,
			{
				operation_id = Operation_ID(10 + fail_after),
				scope = visibility_test_scope(&registry, handle),
				kind = .Local,
				current = .Heading_Only,
				ranges = range[:],
			},
			allocator = visibility_test_failing_allocator(&failing),
		)
		testing.expect(t, !prepared)
		testing.expect_value(t, failure.code, Failure_Code.Allocation_Failed)
		testing.expect(t, !visibility_transition_is_valid(&transition))
		testing.expect_value(t, tracking.current_memory_allocated, i64(0))
		mem.tracking_allocator_destroy(&tracking)
	}
}

@(private)
visibility_test_context :: proc(
	t: ^testing.T,
	buffer: ^editor.Buffer,
	registry: ^view.Registry,
	handle: ^view.View_Handle,
) -> bool {
	buffer_ok, _ := editor.buffer_init(
		buffer,
		399,
		"abcdefghij",
		editor.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	registry_ok, _ := view.registry_init(registry, 399, context.allocator)
	ready := false
	if buffer_ok && registry_ok {
		handle^, ready, _ = view.create(registry, buffer)
	}
	testing.expect(t, buffer_ok && registry_ok && ready)
	return buffer_ok && registry_ok && ready
}

@(private)
visibility_test_scope :: proc(registry: ^view.Registry, handle: view.View_Handle) -> Scope {
	snapshot, ok, _ := view.snapshot(registry, handle)
	assert(ok)
	scope := editing_test_scope(snapshot.buffer_id, snapshot.revision)
	scope.view_handle = handle
	scope.view_state_generation = snapshot.state_generation
	scope.visibility_generation = snapshot.visibility_generation
	return scope
}

@(private)
visibility_test_range :: proc(buffer: ^editor.Buffer, start, end: u64) -> view.Hidden_Range {
	start_position, _, _ := editor.buffer_position(buffer, editor.Byte_Offset(start))
	end_position, _, _ := editor.buffer_position(buffer, editor.Byte_Offset(end))
	return {start = start_position, end = end_position}
}

@(private)
visibility_test_close :: proc(
	t: ^testing.T,
	buffer: ^editor.Buffer,
	registry: ^view.Registry,
	handle: ^view.View_Handle,
) {
	view_closed, _ := view.close(registry, handle)
	registry_closed, _ := view.registry_close(registry)
	buffer_closed, _ := editor.buffer_close(buffer)
	testing.expect(t, view_closed && registry_closed && buffer_closed)
}

@(private)
Visibility_Test_Failing_Allocator :: struct {
	backing:                runtime.Allocator,
	fail_after:             u64,
	successful_allocations: u64,
}

@(private)
visibility_test_failing_allocator :: proc(
	data: ^Visibility_Test_Failing_Allocator,
) -> runtime.Allocator {
	return runtime.Allocator {
		procedure = visibility_test_failing_allocator_proc,
		data = data,
	}
}

@(private)
visibility_test_failing_allocator_proc :: proc(
	allocator_data: rawptr,
	mode: runtime.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	location := #caller_location,
) -> (result: []byte, error: runtime.Allocator_Error) {
	allocator := (^Visibility_Test_Failing_Allocator)(allocator_data)
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
