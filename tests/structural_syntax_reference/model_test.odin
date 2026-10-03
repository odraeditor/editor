// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package structural_syntax_reference

import "base:runtime"
import "core:testing"

fixture :: proc() -> [5]Node {
	return [5]Node {
		{start = 0, end = 20, parent = INVALID_INDEX, first_child = 1, next_sibling = INVALID_INDEX, named = true},
		{start = 0, end = 8, parent = 0, first_child = 2, next_sibling = 3, named = true},
		{start = 2, end = 6, parent = 1, first_child = INVALID_INDEX, next_sibling = INVALID_INDEX, named = true},
		{start = 10, end = 18, parent = 0, first_child = 4, next_sibling = INVALID_INDEX, named = true},
		{start = 12, end = 16, parent = 3, first_child = INVALID_INDEX, next_sibling = INVALID_INDEX, named = true},
	}
}

/* Ensures structural traversal resolves containment, relatives, and expansion. */
@(test)
traversal_resolves_relatives :: proc(t: ^testing.T) {
	nodes := fixture()
	containing, _, contained, _ := query(nodes[:], Request{operation = .Containing, start = 3, end = 3})
	parent, _, parent_ok, _ := query(nodes[:], Request{operation = .Parent, start = 3, end = 3})
	next, _, next_ok, _ := query(nodes[:], Request{operation = .Next, start = 1, end = 1})
	child, _, child_ok, _ := query(nodes[:], Request{operation = .Child, start = 10, end = 18})
	expanded, _, expanded_ok, _ := query(nodes[:], Request{operation = .Expand, start = 2, end = 6})

	testing.expect(t, contained && parent_ok && next_ok && child_ok && expanded_ok)
	testing.expect_value(t, containing.index, u32(2))
	testing.expect_value(t, parent.index, u32(1))
	testing.expect_value(t, next.index, u32(3))
	testing.expect_value(t, child.index, u32(4))
	testing.expect_value(t, expanded.index, u32(1))
}

/* Ensures boundary resolution prefers the deepest named node at a shared start. */
@(test)
boundaries_prefer_deepest_named_node_start :: proc(t: ^testing.T) {
	nodes := fixture()
	target, _, ok, _ := query(nodes[:], Request{operation = .Containing, start = 2, end = 2})
	_, _, absent, failure := query(nodes[:], Request{operation = .Containing, start = 20, end = 20})

	testing.expect(t, ok && !absent)
	testing.expect_value(t, target.index, u32(2))
	testing.expect_value(t, failure.code, Failure_Code.No_Target)
}

/* Ensures structural indentation stays bounded and avoids unreliable error lines. */
@(test)
indentation_is_bounded_and_skips_error_lines :: proc(t: ^testing.T) {
	lines := [?]Indent_Line {
		{start = 0, leading_bytes = 0, desired_level = 0},
		{start = 8, leading_bytes = 0, desired_level = 1},
		{start = 16, leading_bytes = 4, desired_level = 2},
		{start = 24, leading_bytes = 2, desired_level = 0, syntax_error = true},
	}
	plan, ok, _ := indent_plan(lines[:], 4)
	defer indent_plan_close(&plan)

	testing.expect(t, ok)
	testing.expect_value(t, len(plan.edits), 2)
	testing.expect_value(t, plan.usage.lines, u32(4))
	testing.expect_value(t, plan.usage.prepared_bytes, u64(12))
}

/* Ensures cancellation, allocation faults, and cleanup retain explicit outcomes. */
@(test)
cancellation_faults_and_cleanup_are_explicit :: proc(t: ^testing.T) {
	nodes := fixture()
	cancelled := Cancellation{requested = true}
	_, _, queried, query_failure := query(
		nodes[:],
		Request{operation = .Containing, start = 3, end = 3},
		&cancelled,
	)
	lines := [?]Indent_Line{{desired_level = 1}}
	failing := Failing_Allocator{backing = context.allocator, fail_after = 0}
	_, planned, plan_failure := indent_plan(lines[:], 4, nil, failing_allocator(&failing))

	testing.expect(t, !queried && !planned)
	testing.expect_value(t, query_failure.code, Failure_Code.Cancelled)
	testing.expect_value(t, plan_failure.code, Failure_Code.Allocation)
}

Failing_Allocator :: struct {
	backing:                runtime.Allocator,
	fail_after:             u64,
	successful_allocations: u64,
}

failing_allocator :: proc(data: ^Failing_Allocator) -> runtime.Allocator {
	return runtime.Allocator{procedure = failing_allocator_proc, data = data}
}

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
